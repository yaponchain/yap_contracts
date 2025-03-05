// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

interface IPriceOracle {
    function getNFTPrice(address nftAddress, uint256 tokenId) external view returns (uint256);
    function getTokenPrice(address tokenAddress) external view returns (uint256);
}

/**
 * @title CollateralManager
 * @dev Manages NFT collateral for the YAP LEND protocol
 */
contract CollateralManager is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // Struct to store collateral information
    struct CollateralInfo {
        address nftAddress;
        uint256 tokenId;
        uint256 loanId;
        bool active;
    }
    
    // Mapping from collateral ID to CollateralInfo
    mapping(bytes32 => CollateralInfo) public collaterals;
    
    // Mapping from loan ID to array of collateral IDs
    mapping(uint256 => bytes32[]) public loanCollateralIds;
    
    // Mapping of allowed NFT collections (mantido para compatibilidade, mas não utilizado)
    mapping(address => bool) public allowedCollections;
    
    // Minimum collateral value ratio (mantido para compatibilidade, mas não utilizado)
    uint256 public minimumCollateralRatio;
    
    // Price oracle interface
    IPriceOracle private _priceOracle;
    
    // Events
    event CollateralAdded(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId);
    event CollateralRemoved(uint256 indexed loanId, address indexed nftAddress, uint256 tokenId);
    event CollectionAllowListUpdated(address indexed nftAddress, bool allowed);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     */
    function initialize(address priceOracleAddress) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        _priceOracle = IPriceOracle(priceOracleAddress);
        minimumCollateralRatio = 15000; // 150% (mantido por compatibilidade, mas não utilizado)
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Add collateral to a loan
     * @param loanId ID of the loan
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     */
    function addCollateral(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        // Removida verificação de whitelist:
        // require(allowedCollections[nftAddress], "Collection not allowed");
        
        // Generate a unique collateral ID
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        
        // Verify this NFT is not already used as collateral
        require(!collaterals[collateralId].active, "NFT already used as collateral");
        
        try IERC721(nftAddress).ownerOf(tokenId) returns (address) {
            
        } catch {
            revert("NFT does not exist");
        }
        
        // Store collateral information
        collaterals[collateralId] = CollateralInfo({
            nftAddress: nftAddress,
            tokenId: tokenId,
            loanId: loanId,
            active: true
        });
        
        // Add collateral ID to loan's collateral list
        loanCollateralIds[loanId].push(collateralId);
        
        emit CollateralAdded(loanId, nftAddress, tokenId);
    }
    
    /**
     * @dev Remove collateral from a loan
     * @param loanId ID of the loan
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     */
    function removeCollateral(
        uint256 loanId,
        address nftAddress,
        uint256 tokenId
    ) external nonReentrant {
        // Generate collateral ID
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        
        require(collaterals[collateralId].active, "Collateral not active");
        require(collaterals[collateralId].loanId == loanId, "Collateral not for this loan");
        
        // Set collateral as inactive
        collaterals[collateralId].active = false;
        
        emit CollateralRemoved(loanId, nftAddress, tokenId);
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
     * @dev Check the value of an NFT
     * @return Value of the NFT (fixed high value for MVP)
     */
    function checkNFTValue(
        address,  // nftAddress (não utilizado)
        uint256   // tokenId (não utilizado)
    ) external pure returns (uint256) {
        // Valor fixo alto para o MVP
        // Isso garante que qualquer colateral seja aceito sem consultar o price oracle
        return 1000 ether;
    }
    
    /**
     * @dev Calculate total collateral value for a loan
     * @param loanId ID of the loan
     * @return Total value of all collaterals for the loan
     */
    function calculateTotalCollateralValue(uint256 loanId) external view returns (uint256) {
        bytes32[] memory collateralIds = loanCollateralIds[loanId];
        
        // Modificado para retornar um valor proporcional ao número de NFTs
        // sem depender do price oracle
        return collateralIds.length * 1000 ether;
    }
    
    /**
     * @dev Add or remove a collection from the allow list
     * @param nftAddress NFT contract address
     * @param allowed Whether the collection is allowed
     */
    function setCollectionAllowance(address nftAddress, bool allowed) external onlyOwner {
        // Mantido para compatibilidade, mas não é mais usado no fluxo principal
        allowedCollections[nftAddress] = allowed;
        emit CollectionAllowListUpdated(nftAddress, allowed);
    }
    
    /**
     * @dev Set the minimum collateral ratio
     * @param newRatio New minimum collateral ratio (in basis points)
     */
    function setMinimumCollateralRatio(uint256 newRatio) external onlyOwner {
        // Mantido para compatibilidade, mas não é mais usado no fluxo principal
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