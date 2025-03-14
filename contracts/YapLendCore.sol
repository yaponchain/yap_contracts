// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ICollateralManager {
    function addCollateral(uint256 loanId, address nftAddress, uint256 tokenId, address borrower, address lender) external;
    function removeCollateral(uint256 loanId, address nftAddress, uint256 tokenId, address recipient) external;
    function validateCollateral(address nftAddress, uint256 tokenId) external view returns (bool);
    function checkNFTValue(address, uint256) external pure returns (uint256);
    function getEscrowAddress(address nftAddress, uint256 tokenId, uint256 loanId) external view returns (address);
    function getLoanEscrowAddresses(uint256 loanId) external view returns (address[] memory);
}

interface INFTVerifier {
    function verifyOwnership(address owner, address nftAddress, uint256 tokenId) external returns (bool);
    function checkApproval(address owner, address nftAddress, uint256 tokenId) external view returns (bool);
    function verifyEscrowBeneficiary(address escrowAddress, address claimedBeneficiary) external view returns (bool);
}

interface ILoanVault {
    function deposit(uint256 loanId) external payable;
    function withdraw(uint256 loanId, uint256 amount) external;
    function calculateInterest(uint256 loanId) external view returns (uint256);
    function processInterestPayment(uint256 loanId, uint256 interestAmount) external; 
    function loanDeposits(uint256 loanId) external view returns (uint256);
}

interface ILiquidityPool {
    function provideLiquidity() external payable;
    function withdrawLiquidity(uint256 amount) external;
    function calculateAPY() external view returns (uint256);
}

/**
 * @title YapLendCore
 * @dev Main contract for the YAP LEND protocol, manages loan lifecycle with escrow integration
 */
contract YapLendCore is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // Struct to store loan information
    struct Loan {
        address borrower;
        address lender;
        uint256 amount;
        uint256 startTime;
        uint256 duration;
        uint256 interestRate; // APR in basis points (e.g., 4000 = 40%)
        bool active;
        bool liquidated;
        bool partiallyRepaid;
    }
    
    // Struct to store collateral information
    struct Collateral {
        address nftAddress;
        uint256 tokenId;
    }
    
    // Mapping from loan ID to Loan struct
    mapping(uint256 => Loan) public loans;
    
    // Mapping from loan ID to array of Collateral structs
    mapping(uint256 => Collateral[]) public loanCollaterals;
    
    // Counter for loan IDs
    uint256 private _loanIdCounter;
    
    // Min and max APR limits (in basis points)
    uint256 public minInterestRate;
    uint256 public maxInterestRate;
    
    // Protocol fee percentage (in basis points, e.g., 500 = 5%)
    uint256 public protocolFeePercentage;
    
    // Multisig wallet to collect protocol fees
    address public feeCollector;

    // Address of the proposal manager contract
    address public proposalManager; 
    
    // Contract interfaces
    ICollateralManager public collateralManager;
    INFTVerifier public nftVerifier;
    ILoanVault private _loanVault;
    ILiquidityPool private _liquidityPool;
    
    // Events
    event LoanCreated(uint256 indexed loanId, address indexed borrower, address indexed lender, uint256 amount, uint256 duration, uint256 interestRate);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event LoanLiquidated(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event PartialRepayment(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event CollateralAdded(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId);
    event ProtocolParameterUpdated(string parameter, uint256 value);
    event FeeCollectorUpdated(address newFeeCollector);
    event ProposalManagerUpdated(address newProposalManager);
    event ProtocolFeeSent(uint256 indexed loanId, address indexed feeCollector, uint256 amount);
    event FailedToSendFee(uint256 indexed loanId, address indexed feeCollector, uint256 amount);
    event CollateralReleaseFailure(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId, address recipient);
    event ExcessReturnFailure(uint256 indexed loanId, address indexed recipient, uint256 amount);
    event AutoWithdrawalTriggered(uint256 indexed loanId, address indexed user, uint256 amount, uint256 timestamp);
    
    // Modifiers
    modifier onlyProposalManager() {
        require(msg.sender == proposalManager, "Only ProposalManager can call");
        _;
    }
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     */
    function initialize(
        address collateralManagerAddress,
        address nftVerifierAddress,
        address loanVaultAddress,
        address liquidityPoolAddress,
        address _feeCollector
    ) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        collateralManager = ICollateralManager(collateralManagerAddress);
        nftVerifier = INFTVerifier(nftVerifierAddress);
        _loanVault = ILoanVault(loanVaultAddress);
        _liquidityPool = ILiquidityPool(liquidityPoolAddress);
        
        _loanIdCounter = 1;
        
        // Set initial interest rate limits 
        minInterestRate = 1; // 0.01% min APR
        maxInterestRate = 100000; // 1000% max APR
        
        // Set protocol fee percentage to 5%
        protocolFeePercentage = 500;
        
        // Set fee collector
        feeCollector = _feeCollector;
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
        /**
     * @dev Legacy method for backwards compatibility
     * This will be deprecated in future versions
     * 
     * @param nftAddresses Array of NFT contract addresses
     * @param tokenIds Array of token IDs
     * @param loanAmount Amount to borrow
     * @param duration Duration of the loan in seconds
     * @param proposedInterestRate Interest rate proposed by the borrower (APR in basis points)
     * @return loanId Unique identifier for the loan
     */
    function createLoan(
        address[] memory nftAddresses,
        uint256[] memory tokenIds,
        uint256 loanAmount,
        uint256 duration,
        uint256 proposedInterestRate
    ) external payable nonReentrant whenNotPaused returns (uint256) {
        require(nftAddresses.length > 0, "No collateral provided");
        require(nftAddresses.length == tokenIds.length, "Arrays length mismatch");
        require(loanAmount > 0, "Loan amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        
        // Validação do interest rate proposto
        require(proposedInterestRate >= minInterestRate, "Interest rate too low");
        require(proposedInterestRate <= maxInterestRate, "Interest rate too high");
        
        // Nova verificação: garantir que os fundos enviados sejam suficientes
        require(msg.value >= loanAmount, "Insufficient funds sent");
        
        // Verificação de propriedade dos NFTs e validade do colateral
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            require(
                nftVerifier.verifyOwnership(msg.sender, nftAddresses[i], tokenIds[i]),
                "Not owner of NFT"
            );
            require(
                collateralManager.validateCollateral(nftAddresses[i], tokenIds[i]),
                "Invalid collateral"
            );
        }
        
        // Criação do loan
        uint256 loanId = _loanIdCounter++;
        loans[loanId] = Loan({
            borrower: msg.sender,
            lender: address(0), // Sem credor específico para empréstimos diretos
            amount: loanAmount,
            startTime: block.timestamp,
            duration: duration,
            interestRate: proposedInterestRate,
            active: true,
            liquidated: false,
            partiallyRepaid: false
        });
        
        // Adição dos colaterais
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            loanCollaterals[loanId].push(Collateral({
                nftAddress: nftAddresses[i],
                tokenId: tokenIds[i]
            }));
            collateralManager.addCollateral(loanId, nftAddresses[i], tokenIds[i], msg.sender, address(0));
            emit CollateralAdded(loanId, nftAddresses[i], tokenIds[i]);
        }
        
        // Opcional: se forem enviados fundos a mais, reembolsa o excesso
        if (msg.value > loanAmount) {
            uint256 refund = msg.value - loanAmount;
            (bool refundSuccess, ) = payable(msg.sender).call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
        
        // Depósito do valor do empréstimo no Vault
        _loanVault.deposit{value: loanAmount}(loanId);
        
        emit LoanCreated(loanId, msg.sender, address(0), loanAmount, duration, proposedInterestRate);
        return loanId;
    }

    
    /**
     * @dev Legacy method for backwards compatibility
     * This will be deprecated in future versions
     */
    function createLoan(
    address borrower,
    address lender,
    address[] memory nftAddresses,
    uint256[] memory tokenIds,
    uint256 loanAmount,
    uint256 duration,
    uint256 proposedInterestRate
    ) external payable nonReentrant whenNotPaused returns (uint256) {
        require(
            msg.sender == proposalManager || msg.sender == owner(),
            "Only ProposalManager or owner can call"
        );
        require(nftAddresses.length > 0, "No collateral provided");
        require(nftAddresses.length == tokenIds.length, "Arrays length mismatch");
        require(loanAmount > 0, "Loan amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        require(borrower != address(0), "Invalid borrower address");
        require(lender != address(0), "Invalid lender address");
        
        // Validação do interest rate proposto
        require(proposedInterestRate >= minInterestRate, "Interest rate too low");
        require(proposedInterestRate <= maxInterestRate, "Interest rate too high");
        
        // Verificação de propriedade dos NFTs e validade do colateral
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            require(
                nftVerifier.verifyOwnership(borrower, nftAddresses[i], tokenIds[i]),
                "Borrower not owner of NFT"
            );
            require(
                collateralManager.validateCollateral(nftAddresses[i], tokenIds[i]),
                "Invalid collateral"
            );
        }
        
        // Se a chamada for do proposalManager, garantir que os fundos enviados sejam suficientes
        if (msg.sender == proposalManager) {
            require(msg.value >= loanAmount, "Insufficient funds sent");
        }
        
        // Criação do loan
        uint256 loanId = _loanIdCounter++;
        loans[loanId] = Loan({
            borrower: borrower,
            lender: lender,
            amount: loanAmount,
            startTime: block.timestamp,
            duration: duration,
            interestRate: proposedInterestRate,
            active: true,
            liquidated: false,
            partiallyRepaid: false
        });
        
        // Adição dos colaterais
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            loanCollaterals[loanId].push(Collateral({
                nftAddress: nftAddresses[i],
                tokenId: tokenIds[i]
            }));
            // Chamada para a adição do colateral com dados de borrower e lender
            collateralManager.addCollateral(loanId, nftAddresses[i], tokenIds[i], borrower, lender);
            emit CollateralAdded(loanId, nftAddresses[i], tokenIds[i]);
        }
        
        // Opcional: se forem enviados fundos a mais, reembolsa o excesso
        if (msg.value > loanAmount) {
            uint256 refund = msg.value - loanAmount;
            (bool refundSuccess, ) = payable(msg.sender).call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
        
        // Depósito do valor do empréstimo no Vault
        _loanVault.deposit{value: loanAmount}(loanId);
        
        emit LoanCreated(loanId, borrower, lender, loanAmount, duration, proposedInterestRate);
        return loanId;
    }

      // Função para verificar condições de saque automático - deixe como está
    function checkAutoWithdrawConditions(uint256 loanId) external {
        Loan memory loan = loans[loanId];
        
        // Verifica se o empréstimo foi pago (não está ativo) e não foi liquidado
        if (!loan.active && !loan.liquidated) {
            // Obtém o saldo do empréstimo no vault usando a interface existente
            uint256 depositAmount = 0;
            try _loanVault.loanDeposits(loanId) returns (uint256 amount) {
                depositAmount = amount;
            } catch {
                return; // Se houver erro, apenas sai da função
            }
            
            // Se houver fundos disponíveis
            if (depositAmount > 0) {
                // Emite o evento para o listener off-chain
                emit AutoWithdrawalTriggered(
                    loanId,
                    loan.lender, 
                    depositAmount,
                    block.timestamp
                );
            }
        }
    }

    /**
     * @dev Repay a loan with robust error handling
     * @param loanId ID of the loan to repay
     */
    function repayLoan(uint256 loanId) external payable nonReentrant {
        require(loans[loanId].active, "Loan not active");
        require(!loans[loanId].liquidated, "Loan already liquidated");
        
        Loan storage loan = loans[loanId];
        
        // Verificar se o empréstimo não expirou
        if (block.timestamp > loan.startTime + loan.duration) {
            revert("Loan expired, cannot be repaid");
        }
        
        require(loan.borrower == msg.sender, "Not the borrower");
        
        // Calcular repagamento com try/catch
        uint256 interest;
        try _loanVault.calculateInterest(loanId) returns (uint256 interestAmount) {
            interest = interestAmount;
        } catch {
            interest = 0; // Fallback se o cálculo falhar
        }
        
        uint256 totalRepayment = loan.amount + interest;
        require(msg.value >= totalRepayment, "Insufficient repayment amount");
        
        // Criar uma variável para rastrear o sucesso da liberação do colateral
        bool allCollateralsReleased = true;
        
        // Release collateral back to the borrower first, com try/catch para cada NFT
        Collateral[] memory collaterals = loanCollaterals[loanId];
        for (uint256 i = 0; i < collaterals.length; i++) {
            try collateralManager.removeCollateral(
                loanId, 
                collaterals[i].nftAddress, 
                collaterals[i].tokenId,
                msg.sender // return to borrower
            ) {
                // Sucesso na liberação do colateral
            } catch {
                // Em caso de falha, emitir evento para que o administrador possa resolver manualmente
                emit CollateralReleaseFailure(loanId, collaterals[i].nftAddress, collaterals[i].tokenId, msg.sender);
                allCollateralsReleased = false;
            }
        }
        
        // Apenas marca o empréstimo como inativo se todos os colaterais foram liberados
        if (allCollateralsReleased) {
            // Update loan status
            loan.active = false;
        } else {
             loan.partiallyRepaid = true;
            // Se houver falha na liberação do colateral, ainda permite o pagamento mas mantém o empréstimo ativo
            // O pagamento será processado, mas o status do empréstimo permanece ativo para permitir outra tentativa de liberação
            emit PartialRepayment(loanId, msg.sender, totalRepayment);
            
            // Processar o pagamento mesmo assim
        }
        
        // Calcular a taxa do protocolo para os juros
        uint256 protocolFee = 0;
        uint256 lenderInterest = 0;
        if (interest > 0) {
            protocolFee = (interest * protocolFeePercentage) / 10000;
            lenderInterest = interest - protocolFee;
        }
        
        // Usar blocos try/catch para cada transferência de fundos
        bool principalSent = false;
        
        // Enviar o principal diretamente para o credor se houver um
        if (loan.lender != address(0)) {
            (bool principalSuccess, ) = payable(loan.lender).call{value: loan.amount}("");
            principalSent = principalSuccess;
            if (!principalSuccess) {
                // Se falhar, tentar depositar no vault como fallback
                _loanVault.deposit{value: loan.amount}(loanId);
            }
        } else {
            // Se não houver credor específico, enviar para o contrato de vault
            _loanVault.deposit{value: loan.amount}(loanId);
            principalSent = true;
        }
        
        // Enviar os juros para o credor (exceto a taxa do protocolo)
        if (interest > 0) {
            if (loan.lender != address(0) && lenderInterest > 0) {
                (bool interestSuccess, ) = payable(loan.lender).call{value: lenderInterest}("");
                if (!interestSuccess) {
                    // Se falhar, depositar no vault como fallback
                    _loanVault.deposit{value: lenderInterest}(loanId);
                }
                
                // Emitir evento para saque automático após pagamento bem-sucedido
                if (interestSuccess && allCollateralsReleased) {
                    emit AutoWithdrawalTriggered(
                        loanId,
                        loan.lender,
                        lenderInterest,
                        block.timestamp
                    );
                }
            } else if (lenderInterest > 0) {
                // Se não houver credor específico, enviar para o contrato de vault
                _loanVault.deposit{value: lenderInterest}(loanId);
            }
            
            // Enviar a taxa do protocolo diretamente para o coletor de taxas
            if (protocolFee > 0) {
                (bool feeSuccess, ) = payable(feeCollector).call{value: protocolFee}("");
                if (feeSuccess) {
                    emit ProtocolFeeSent(loanId, feeCollector, protocolFee);
                } else {
                    emit FailedToSendFee(loanId, feeCollector, protocolFee);
                    // Depositar no vault se falhar
                    _loanVault.deposit{value: protocolFee}(loanId);
                }
            }
        }
        
        // Return excess payment if any
        uint256 excess = msg.value - totalRepayment;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            if (!success) {
                // Se falhar o retorno do excesso, depositar no vault
                _loanVault.deposit{value: excess}(loanId);
                emit ExcessReturnFailure(loanId, msg.sender, excess);
            }
        }
        
        // Se o pagamento foi bem-sucedido e todos os colaterais foram liberados
        if (allCollateralsReleased) {
            emit LoanRepaid(loanId, msg.sender, totalRepayment);
        }
    }

    /**
     * @dev Liquidate a defaulted loan
     * @param loanId ID of the loan to liquidate
     */
    function liquidateLoan(uint256 loanId) external nonReentrant {
        require(loans[loanId].active, "Loan not active");
        require(!loans[loanId].liquidated, "Already liquidated");
        require(
            block.timestamp > loans[loanId].startTime + loans[loanId].duration,
            "Loan not yet defaulted"
        );
        
        Loan storage loan = loans[loanId];
        
        // Update loan status
        loan.active = false;
        loan.liquidated = true;
        
        // Transfer collateral to the lender
        Collateral[] memory collaterals = loanCollaterals[loanId];
        for (uint256 i = 0; i < collaterals.length; i++) {
            // Updated to transfer collateral to lender instead of borrower
            collateralManager.removeCollateral(
                loanId, 
                collaterals[i].nftAddress, 
                collaterals[i].tokenId,
                loan.lender // transfer to lender
            );
        }
        
        emit LoanLiquidated(loanId, loan.borrower, loan.amount);
    }
    
    /**
     * @dev Get the escrow addresses for all collaterals of a loan
     * @param loanId ID of the loan
     * @return Array of escrow addresses
     */
    function getLoanEscrowAddresses(uint256 loanId) external view returns (address[] memory) {
        return collateralManager.getLoanEscrowAddresses(loanId);
    }
    
    /**
     * @dev Get the escrow address for a specific collateral
     * @param loanId ID of the loan
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return Escrow contract address
     */
    function getEscrowAddress(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId
    ) external view returns (address) {
        return collateralManager.getEscrowAddress(nftAddress, tokenId, loanId);
    }
    
    /**
     * @dev Verify NFT ownership without transferring
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return True if ownership is verified
     */
    function verifyNFTOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) public returns (bool) {
        return nftVerifier.verifyOwnership(owner, nftAddress, tokenId);
    }
    
        /**
     * @dev Calculate the exact amount needed for loan repayment
     * @param loanId ID of the loan
     * @return Total amount needed for repayment (principal + interest)
     */
    function getRepaymentAmount(uint256 loanId) external view returns (uint256) {
        Loan memory loan = loans[loanId];
        if (!loan.active || loan.liquidated) {
            return 0;
        }
        
        uint256 interest = 0;
        try _loanVault.calculateInterest(loanId) returns (uint256 interestAmount) {
            interest = interestAmount;
        } catch {
            // Se o cálculo falhar, retorna apenas o principal
            // Isso pode ser impreciso, mas melhor do que falhar completamente
        }
        
        return loan.amount + interest;
    }

    /**
     * @dev Returns all collaterals for a specific loan
     * @param loanId ID of the loan
     * @return Array of Collateral structs
     */
    function getLoanCollaterals(uint256 loanId) external view returns (Collateral[] memory) {
        return loanCollaterals[loanId];
    }
    
        /**
     * @dev Calculate expected interest for a loan simulation
     * Using formula: Interest = Principal × (APR/10000) × (Seconds/SecondsInYear)
     * @param principal Principal amount
     * @param interestRate Annual interest rate in basis points (e.g., 4000 = 40%)
     * @param durationInSeconds Duration of the loan in seconds
     * @return Expected interest amount
     */
    function simulateInterest(
        uint256 principal,
        uint256 interestRate,
        uint256 durationInSeconds
    ) external pure returns (uint256) {
        // Cálculo padrão de juros
        uint256 regularInterest = (principal * interestRate * durationInSeconds) / (10000 * 31536000);
        
        // Cálculo de 5% do APR como juros mínimos
        uint256 minimumInterest = (principal * interestRate * 5) / 1000000;
        
        // Retorna o maior valor
        return regularInterest > minimumInterest ? regularInterest : minimumInterest;
    }
    
    /**
     * @dev Set the loan vault address
     * @param loanVaultAddress New loan vault address
     */
    function setLoanVault(address loanVaultAddress) external onlyOwner {
        require(loanVaultAddress != address(0), "Invalid address");
        _loanVault = ILoanVault(loanVaultAddress);
    }

    /**
     * @dev Set the minimum interest rate
     * @param newMinRate New minimum rate in basis points
     */
    function setMinInterestRate(uint256 newMinRate) external onlyOwner {
        require(newMinRate < maxInterestRate, "Min must be less than max");
        minInterestRate = newMinRate;
        emit ProtocolParameterUpdated("minInterestRate", newMinRate);
    }
    
    /**
     * @dev Set the maximum interest rate
     * @param newMaxRate New maximum rate in basis points
     */
    function setMaxInterestRate(uint256 newMaxRate) external onlyOwner {
        require(newMaxRate > minInterestRate, "Max must be greater than min");
        maxInterestRate = newMaxRate;
        emit ProtocolParameterUpdated("maxInterestRate", newMaxRate);
    }
    
    /**
     * @dev Set the protocol fee percentage
     * @param newFeePercentage New fee percentage in basis points
     */
    function setProtocolFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 3000, "Fee cannot exceed 30%");
        protocolFeePercentage = newFeePercentage;
        emit ProtocolParameterUpdated("protocolFeePercentage", newFeePercentage);
    }
    
    /**
     * @dev Set the fee collector address (multisig)
     * @param newFeeCollector New fee collector address
     */
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        require(newFeeCollector != address(0), "Invalid address");
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }
    
    /**
     * @dev Set the proposal manager address
     * @param _proposalManager New proposal manager address
     */
    function setProposalManager(address _proposalManager) external onlyOwner {
        require(_proposalManager != address(0), "Invalid address");
        proposalManager = _proposalManager;
        emit ProposalManagerUpdated(_proposalManager);
    }

        /**
     * @dev Set the collateral manager address
     * @param collateralManagerAddress New collateral manager address
     */
    function setCollateralManager(address collateralManagerAddress) external onlyOwner {
        require(collateralManagerAddress != address(0), "Invalid address");
        collateralManager = ICollateralManager(collateralManagerAddress);
    }

    /**
     * @dev Set the NFT verifier address
     * @param nftVerifierAddress New NFT verifier address
     */
    function setNFTVerifier(address nftVerifierAddress) external onlyOwner {
        require(nftVerifierAddress != address(0), "Invalid address");
        nftVerifier = INFTVerifier(nftVerifierAddress);
    }

    /**
     * @dev Set the liquidity pool address
     * @param liquidityPoolAddress New liquidity pool address
     */
    function setLiquidityPool(address liquidityPoolAddress) external onlyOwner {
        require(liquidityPoolAddress != address(0), "Invalid address");
        _liquidityPool = ILiquidityPool(liquidityPoolAddress);
    }
    
    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Function to receive Ether
     */
    receive() external payable {}
}