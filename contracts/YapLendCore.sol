// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface ICollateralManager {
    function addCollateral(uint256 loanId, address nftAddress, uint256 tokenId) external;
    function removeCollateral(uint256 loanId, address nftAddress, uint256 tokenId) external;
    function validateCollateral(address nftAddress, uint256 tokenId) external view returns (bool);
    function checkNFTValue(address, uint256) external pure returns (uint256);
}

interface INFTVerifier {
    function verifyOwnership(address owner, address nftAddress, uint256 tokenId, bytes memory signature) external view returns (bool);
    function checkApproval(address owner, address nftAddress, uint256 tokenId) external view returns (bool);
}

interface ILoanVault {
    function deposit(uint256 loanId) external payable;
    function withdraw(uint256 loanId, uint256 amount) external;
    function calculateInterest(uint256 loanId) external view returns (uint256);
    function processInterestPayment(uint256 loanId, uint256 interestAmount) external; 
}

interface ILiquidityPool {
    function provideLiquidity() external payable;
    function withdrawLiquidity(uint256 amount) external;
    function calculateAPY() external view returns (uint256);
}

/**
 * @title YapLendCore
 * @dev Main contract for the YAP LEND protocol, manages loan lifecycle
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
    ICollateralManager private _collateralManager;
    INFTVerifier private _nftVerifier;
    ILoanVault private _loanVault;
    ILiquidityPool private _liquidityPool;
    
    // Events
    event LoanCreated(uint256 indexed loanId, address indexed borrower, address indexed lender, uint256 amount, uint256 duration, uint256 interestRate);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event LoanLiquidated(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event CollateralAdded(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId);
    event ProtocolParameterUpdated(string parameter, uint256 value);
    event FeeCollectorUpdated(address newFeeCollector);
    event ProposalManagerUpdated(address newProposalManager);
    
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
        
        _collateralManager = ICollateralManager(collateralManagerAddress);
        _nftVerifier = INFTVerifier(nftVerifierAddress);
        _loanVault = ILoanVault(loanVaultAddress);
        _liquidityPool = ILiquidityPool(liquidityPoolAddress);
        
        _loanIdCounter = 1;
        
        // Set initial interest rate limits - amplos, conforme solicitado
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
     * @dev Creates a new loan with multiple NFTs as collateral
     * Normal users should create loans through the ProposalManager
     * This function can be called directly only by the ProposalManager
     * 
     * @param borrower Address of the borrower
     * @param lender Address of the lender
     * @param nftAddresses Array of NFT contract addresses
     * @param tokenIds Array of token IDs
     * @param loanAmount Amount to borrow
     * @param duration Duration of the loan in seconds
     * @param proposedInterestRate Interest rate proposed by the borrower (APR in basis points)
     * @return loanId Unique identifier for the loan
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
        
        // Validate proposed interest rate
        require(proposedInterestRate >= minInterestRate, "Interest rate too low");
        require(proposedInterestRate <= maxInterestRate, "Interest rate too high");
        
        // Verify NFT ownership
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            require(
                _nftVerifier.verifyOwnership(borrower, nftAddresses[i], tokenIds[i], new bytes(0)),
                "Borrower not owner of NFT"
            );
            require(
                _collateralManager.validateCollateral(nftAddresses[i], tokenIds[i]),
                "Invalid collateral"
            );
        }
        
        // Removida verificação de valor do colateral
        // Parte do valor é determinado pela negociação entre as partes
        
        // If called with funds, ensure sufficient amount is sent
        if (msg.sender == proposalManager) {
            require(msg.value >= loanAmount, "Insufficient funds sent");
        }
        
        // Create loan
        uint256 loanId = _loanIdCounter++;
        
        loans[loanId] = Loan({
            borrower: borrower,
            lender: lender,
            amount: loanAmount,
            startTime: block.timestamp,
            duration: duration,
            interestRate: proposedInterestRate,
            active: true,
            liquidated: false
        });
        
        // Add collateral
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            loanCollaterals[loanId].push(Collateral({
                nftAddress: nftAddresses[i],
                tokenId: tokenIds[i]
            }));
            
            _collateralManager.addCollateral(loanId, nftAddresses[i], tokenIds[i]);
            
            emit CollateralAdded(loanId, nftAddresses[i], tokenIds[i]);
        }
        
        // Transfer loan amount to borrower through vault
        _loanVault.deposit{value: loanAmount}(loanId);
        
        emit LoanCreated(loanId, borrower, lender, loanAmount, duration, proposedInterestRate);
        
        return loanId;
    }
    
    /**
     * @dev Legacy method for backwards compatibility
     * This will be deprecated in future versions
     */
    function createLoan(
        address[] memory nftAddresses,
        uint256[] memory tokenIds,
        uint256 loanAmount,
        uint256 duration,
        uint256 proposedInterestRate
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(nftAddresses.length > 0, "No collateral provided");
        require(nftAddresses.length == tokenIds.length, "Arrays length mismatch");
        require(loanAmount > 0, "Loan amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        
        // Validate proposed interest rate
        require(proposedInterestRate >= minInterestRate, "Interest rate too low");
        require(proposedInterestRate <= maxInterestRate, "Interest rate too high");
        
        // Verify NFT ownership and validate collateral
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            require(
                _nftVerifier.verifyOwnership(msg.sender, nftAddresses[i], tokenIds[i], new bytes(0)),
                "Not owner of NFT"
            );
            require(
                _collateralManager.validateCollateral(nftAddresses[i], tokenIds[i]),
                "Invalid collateral"
            );
        }
        
        // Create loan
        uint256 loanId = _loanIdCounter++;
        
        loans[loanId] = Loan({
            borrower: msg.sender,
            lender: address(0), // No specific lender for direct loans
            amount: loanAmount,
            startTime: block.timestamp,
            duration: duration,
            interestRate: proposedInterestRate, // Use the user's proposed rate
            active: true,
            liquidated: false
        });
        
        // Add collateral
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            loanCollaterals[loanId].push(Collateral({
                nftAddress: nftAddresses[i],
                tokenId: tokenIds[i]
            }));
            
            _collateralManager.addCollateral(loanId, nftAddresses[i], tokenIds[i]);
            
            emit CollateralAdded(loanId, nftAddresses[i], tokenIds[i]);
        }
        
        // Transfer loan amount to borrower through vault
        _loanVault.deposit{value: loanAmount}(loanId);
        
        emit LoanCreated(loanId, msg.sender, address(0), loanAmount, duration, proposedInterestRate);
        
        return loanId;
    }
    
    /**
     * @dev Repay a loan
     * @param loanId ID of the loan to repay
     */
    function repayLoan(uint256 loanId) external payable nonReentrant {
        require(loans[loanId].active, "Loan not active");
        require(!loans[loanId].liquidated, "Loan already liquidated");
        require(block.timestamp <= loans[loanId].startTime + loans[loanId].duration, "Loan expired");
        
        Loan storage loan = loans[loanId];
        require(loan.borrower == msg.sender, "Not the borrower");
        
        // Calculate total amount to repay (principal + interest)
        uint256 interest = _loanVault.calculateInterest(loanId);
        uint256 totalRepayment = loan.amount + interest;
        
        require(msg.value >= totalRepayment, "Insufficient repayment amount");
        
        // Update loan status
        loan.active = false;
        
        // Process repayment - separamos o principal e os juros
        // Primeiro, depositamos o valor principal
        _loanVault.deposit{value: loan.amount}(loanId);
        
        // Depois, processamos o pagamento de juros, que enviará a taxa para a carteira
        if (interest > 0) {
            // Transferir os juros para o LoanVault
            _loanVault.deposit{value: interest}(loanId);
            
            // Processar o pagamento de juros, que calculará e enviará a taxa para a carteira
            _loanVault.processInterestPayment(loanId, interest);
        }
        
        // Return excess payment if any
        uint256 excess = msg.value - totalRepayment;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "Refund failed");
        }
        
        emit LoanRepaid(loanId, msg.sender, totalRepayment);
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
        
        // Process liquidation - this would involve transferring collateral to liquidator or protocol
        // In a real implementation, this would handle auction or direct liquidation process
        
        emit LoanLiquidated(loanId, loan.borrower, loan.amount);
    }
    
    /**
     * @dev Verify NFT ownership without transferring
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param signature Signature to verify ownership
     * @return True if ownership is verified
     */
    function verifyNFTOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId,
        bytes memory signature
    ) public view returns (bool) {
        return _nftVerifier.verifyOwnership(owner, nftAddress, tokenId, signature);
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
     * Using formula: Interest = Principal × (APR/100) × (Days/365)
     * @param principal Principal amount
     * @param interestRate Annual interest rate in basis points (e.g., 4000 = 40%)
     * @param durationInDays Duration of the loan in days
     * @return Expected interest amount
     */
    function simulateInterest(
        uint256 principal,
        uint256 interestRate,
        uint256 durationInDays
    ) external pure returns (uint256) {
        // Interest = Principal × (APR/100) × (Days/365)
        return (principal * interestRate * durationInDays) / (10000 * 365);
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