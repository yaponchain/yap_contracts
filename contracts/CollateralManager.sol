// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./NFTEscrow.sol";

interface IPriceOracle {
    function getNFTPrice(address nftAddress, uint256 tokenId) external view returns (uint256);
    function getTokenPrice(address tokenAddress) external view returns (uint256);
}

interface IYapLendCore {
    function _loanIdCounter() external view returns (uint256);
}

/**
 * @title CollateralManager
 * @dev Manages NFT collateral for the YAP LEND protocol using escrow contracts
 */
contract CollateralManager is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // Struct to store collateral information
    struct CollateralInfo {
        address nftAddress;
        uint256 tokenId;
        uint256 loanId;
        bool active;
        address escrowAddress; // Endereço do contrato de escrow
    }
    
    // Mapping from collateral ID to CollateralInfo
    mapping(bytes32 => CollateralInfo) public collaterals;
    
    // Mapping from loan ID to array of collateral IDs
    mapping(uint256 => bytes32[]) public loanCollateralIds;
    
    // Mapping from escrow address to collateral ID for lookup
    mapping(address => bytes32) public escrowToCollateralId;
    
    // Mapping of allowed NFT collections (mantido para compatibilidade)
    mapping(address => bool) public allowedCollections;
    
    // Minimum collateral value ratio (mantido para compatibilidade)
    uint256 public minimumCollateralRatio;
    
    // Price oracle interface
    IPriceOracle private _priceOracle;
    
    // YapLendCore interface for loan counter
    IYapLendCore private _yapLendCore;

    // Reference to the NFTEscrow implementation for cloning
    address public escrowImplementation;
    
    // Mapping for partner interfaces
    mapping(address => bytes4) public partnerInterfaces;
    
    // Events
    event CollateralAdded(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId, address escrowAddress);
    event CollateralRemoved(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId, address recipient);
    event CollectionAllowListUpdated(address indexed nftAddress, bool allowed);
    event EscrowCreated(address escrowAddress, address nftAddress, uint256 tokenId, uint256 loanId);
    event PartnerInterfaceRegistered(address partnerProject, bytes4 interfaceId);
    event EscrowInitialized(address escrowAddress, address borrower, address lender);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     * @param priceOracleAddress Address of the price oracle
     * @param yapLendCoreAddress Address of the YapLendCore contract
     */
    function initialize(address priceOracleAddress, address yapLendCoreAddress) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        _priceOracle = IPriceOracle(priceOracleAddress);
        _yapLendCore = IYapLendCore(yapLendCoreAddress);
        minimumCollateralRatio = 15000; // 150%
        
        // Deploy a implementação do NFTEscrow e armazenar para clonar depois
        escrowImplementation = address(new NFTEscrow());
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Create a new escrow contract for a collateral NFT using clones
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param loanId Loan ID
     * @param borrower Borrower address
     * @param lender Lender address
     * @return Address of the created escrow contract
     */
    function createEscrow(
        address nftAddress,
        uint256 tokenId,
        uint256 loanId,
        address borrower,
        address lender
    ) internal returns (address) {
        // Usar o padrão clone para economizar gas
        address escrowAddress = Clones.clone(escrowImplementation);
        
        // Inicializar o clone
        NFTEscrow(escrowAddress).initialize(
            nftAddress,
            tokenId,
            loanId,
            borrower,
            lender,
            address(this) // CollateralManager é o proprietário do escrow
        );
        
        emit EscrowCreated(escrowAddress, nftAddress, tokenId, loanId);
        emit EscrowInitialized(escrowAddress, borrower, lender);
        
        return escrowAddress;
    }
    
    /**
     * @dev Add collateral to a loan using escrow
     * @param loanId ID of the loan
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param borrower Address of the borrower
     * @param lender Address of the lender
     */
    function addCollateral(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId,
        address borrower,
        address lender
    ) external nonReentrant whenNotPaused {
        // Verificar se o NFT existe e o borrower é o proprietário
        try IERC721(nftAddress).ownerOf(tokenId) returns (address currentOwner) {
            require(currentOwner == borrower, "Borrower does not own the NFT");
        } catch {
            revert("NFT does not exist");
        }
        
        // Verificar se o NFT foi aprovado para o CollateralManager
        bool isApproved = IERC721(nftAddress).isApprovedForAll(borrower, address(this)) || 
                          IERC721(nftAddress).getApproved(tokenId) == address(this);
        require(isApproved, "NFT not approved for CollateralManager");
        
        // Gerar um ID único para o colateral
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        
        // Verificar se este NFT já está sendo usado como colateral
        require(!collaterals[collateralId].active, "NFT already used as collateral");
        
        // Criar um contrato escrow para este NFT
        address escrowAddress = createEscrow(nftAddress, tokenId, loanId, borrower, lender);
        
        // Armazenar informações do colateral com o endereço do escrow
        collaterals[collateralId] = CollateralInfo({
            nftAddress: nftAddress,
            tokenId: tokenId,
            loanId: loanId,
            active: true,
            escrowAddress: escrowAddress
        });
        
        // Adicionar ID do colateral à lista de colaterais do empréstimo
        loanCollateralIds[loanId].push(collateralId);
        
        // Mapear o endereço do escrow para o ID do colateral para pesquisa rápida
        escrowToCollateralId[escrowAddress] = collateralId;
        
        // Transferir o NFT para o escrow
        IERC721(nftAddress).safeTransferFrom(borrower, escrowAddress, tokenId);
        
        // Chamar o método depositNFT no contrato escrow para confirmar o depósito
        // Nota: Isso só é necessário se depositNFT faz alguma lógica adicional além da transferência
        NFTEscrow(escrowAddress).depositNFT();
        
        emit CollateralAdded(loanId, nftAddress, tokenId, escrowAddress);
    }
    
    /**
     * @dev Remove collateral from a loan and release the NFT
     * @param loanId ID of the loan
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param recipient Address to receive the NFT
     */
    function removeCollateral(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId,
        address recipient
    ) external nonReentrant whenNotPaused {
        // Generate collateral ID
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        
        require(collaterals[collateralId].active, "Collateral not active");
        require(collaterals[collateralId].loanId == loanId, "Collateral not for this loan");
        
        // Get escrow address
        address escrowAddress = collaterals[collateralId].escrowAddress;
        require(escrowAddress != address(0), "No escrow found");
        
        // Set collateral as inactive
        collaterals[collateralId].active = false;
        
        // Release NFT from escrow to the recipient
        NFTEscrow(escrowAddress).releaseNFT(recipient);
        
        emit CollateralRemoved(loanId, nftAddress, tokenId, recipient);
    }
    
    /**
     * @dev Overloaded method for backward compatibility
     */
    function removeCollateral(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        // Use msg.sender as the recipient by default
        this.removeCollateral(loanId, nftAddress, tokenId, msg.sender);
    }
    
    /**
     * @dev Get all escrow addresses for a loan
     * @param loanId Loan ID
     * @return Array of escrow addresses
     */
    function getLoanEscrowAddresses(uint256 loanId) external view returns (address[] memory) {
        bytes32[] memory collateralIds = loanCollateralIds[loanId];
        address[] memory escrowAddresses = new address[](collateralIds.length);
        
        for (uint256 i = 0; i < collateralIds.length; i++) {
            if (collaterals[collateralIds[i]].active) {
                escrowAddresses[i] = collaterals[collateralIds[i]].escrowAddress;
            }
        }
        
        return escrowAddresses;
    }
    
    /**
     * @dev Get the escrow address for a specific collateral
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param loanId Loan ID
     * @return Escrow contract address
     */
    function getEscrowAddress(
        address nftAddress,
        uint256 tokenId,
        uint256 loanId
    ) external view returns (address) {
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        return collaterals[collateralId].escrowAddress;
    }
    
    /**
     * @dev Register a partner interface for escrow contracts
     * @param partnerProject Partner project address
     * @param interfaceId Interface ID
     */
    function registerPartnerInterface(
        address partnerProject,
        bytes4 interfaceId
    ) external onlyOwner {
        partnerInterfaces[partnerProject] = interfaceId;
        emit PartnerInterfaceRegistered(partnerProject, interfaceId);
    }
    
    /**
     * @dev Apply a partner interface to an existing escrow contract
     * @param escrowAddress Escrow contract address
     * @param partnerProject Partner project address
     */
    function applyPartnerInterface(
        address escrowAddress,
        address partnerProject
    ) external onlyOwner {
        bytes4 interfaceId = partnerInterfaces[partnerProject];
        require(interfaceId != bytes4(0), "Interface not registered");
        
        NFTEscrow(escrowAddress).registerPartnerInterface(partnerProject, interfaceId);
    }
    
    /**
     * @dev Validate if an NFT can be used as collateral
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return True if the NFT is valid collateral
     */
    function validateCollateral(
        address nftAddress,
        uint256 tokenId
    ) external view returns (bool) {
        // Verificar apenas se o NFT existe
        try IERC721(nftAddress).ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Calculate total collateral value for a loan
     * @param loanId ID of the loan
     * @return Total value of all collaterals for the loan
     */
    function calculateTotalCollateralValue(uint256 loanId) external view returns (uint256) {
        bytes32[] memory collateralIds = loanCollateralIds[loanId];
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < collateralIds.length; i++) {
            if (collaterals[collateralIds[i]].active) {
                // Para MVP, mantenha o valor fixo por NFT
                totalValue += 1000 ether;
                
                // Quando o price oracle estiver pronto, implemente:
                // address nftAddress = collaterals[collateralIds[i]].nftAddress;
                // uint256 tokenId = collaterals[collateralIds[i]].tokenId;
                // totalValue += _priceOracle.getNFTPrice(nftAddress, tokenId);
            }
        }
        
        return totalValue;
    }
    
    /**
     * @dev Check the value of an NFT
     * @return Value of the NFT (fixed high value for MVP)
     */
    function checkNFTValue(
        address,  // nftAddress (não utilizado)
        uint256   // tokenId (não utilizado)
    ) external pure returns (uint256) {
        // Valor fixo alto para o MVP
        return 1000 ether;
    }
    
    /**
     * @dev Claim benefits for an NFT in escrow
     * @param loanId Loan ID
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param benefitAddress Address of the benefit contract
     * @param data Calldata for the benefit claim
     * @return Success status
     */
    function claimBenefits(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId,
        address benefitAddress,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        
        require(collaterals[collateralId].active, "Collateral not active");
        
        address escrowAddress = collaterals[collateralId].escrowAddress;
        require(escrowAddress != address(0), "No escrow found");
        
        // Apenas o tomador do empréstimo pode reivindicar benefícios
        // Esta verificação é feita no NFTEscrow, mas verificamos aqui também
        require(NFTEscrow(escrowAddress).borrower() == msg.sender, "Only borrower can claim benefits");
        
        return NFTEscrow(escrowAddress).claimBenefits(benefitAddress, data);
    }
    
    /**
     * @dev Add or remove a collection from the allow list
     * @param nftAddress NFT contract address
     * @param allowed Whether the collection is allowed
     */
    function setCollectionAllowance(address nftAddress, bool allowed) external onlyOwner {
        // Mantido para compatibilidade
        allowedCollections[nftAddress] = allowed;
        emit CollectionAllowListUpdated(nftAddress, allowed);
    }
    
    /**
     * @dev Set the minimum collateral ratio
     * @param newRatio New minimum collateral ratio (in basis points)
     */
    function setMinimumCollateralRatio(uint256 newRatio) external onlyOwner {
        // Mantido para compatibilidade
        require(newRatio >= 10000, "Ratio must be at least 100%");
        minimumCollateralRatio = newRatio;
    }
    
    /**
     * @dev Set a new price oracle
     * @param newPriceOracle Address of the new price oracle
     */
    function setPriceOracle(address newPriceOracle) external onlyOwner {
        require(newPriceOracle != address(0), "Invalid address");
        _priceOracle = IPriceOracle(newPriceOracle);
    }
    
    /**
     * @dev Set the YapLendCore address
     * @param yapLendCoreAddress New YapLendCore address
     */
    function setYapLendCore(address yapLendCoreAddress) external onlyOwner {
        require(yapLendCoreAddress != address(0), "Invalid address");
        _yapLendCore = IYapLendCore(yapLendCoreAddress);
    }
    
    /**
     * @dev Execute a function in an escrow contract (for emergencies)
     * @param escrowAddress Escrow contract address
     * @param data Function calldata
     * @return Success status and return data
     */
    function executeEscrowFunction(
        address escrowAddress,
        bytes calldata data
    ) external onlyOwner returns (bool, bytes memory) {
        // Verificar se é um escrow válido gerenciado por este contrato
        bytes32 collateralId = escrowToCollateralId[escrowAddress];
        require(collateralId != bytes32(0), "Not a valid escrow");
        require(collaterals[collateralId].escrowAddress == escrowAddress, "Escrow address mismatch");
        
        // Execute a chamada
        (bool success, bytes memory returnData) = escrowAddress.call(data);
        return (success, returnData);
    }
    
    /**
     * @dev Get the current number of loans (for iterating)
     * @return Current loan ID counter
     */
    function loanIdCounter() public view returns (uint256) {
        // Use the YapLendCore to get the current loan ID counter
        if (address(_yapLendCore) != address(0)) {
            try _yapLendCore._loanIdCounter() returns (uint256 counter) {
                return counter;
            } catch {
                return 0;
            }
        }
        return 0;
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
}