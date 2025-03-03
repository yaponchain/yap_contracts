// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IPriceOracle {
    function getNFTPrice(address nftAddress, uint256 tokenId) external view returns (uint256);
    function getTokenPrice(address tokenAddress) external view returns (uint256);
}

/**
 * @title CollateralManager
 * @dev Manages NFT collateral for the YAP LEND protocol
 */
contract CollateralManager is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
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
    
    // Mapping of allowed NFT collections
    mapping(address => bool) public allowedCollections;
    
    // Minimum collateral value ratio (in basis points, e.g., 15000 = 150%)
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
        
        _priceOracle = IPriceOracle(priceOracleAddress);
        minimumCollateralRatio = 15000; // 150%
    }
    
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
        require(allowedCollections[nftAddress], "Collection not allowed");
        
        // Generate a unique collateral ID
        bytes32 collateralId = keccak256(abi.encodePacked(nftAddress, tokenId, loanId));
        
        // Verify this NFT is not already used as collateral
        require(!collaterals[collateralId].active, "NFT already used as collateral");
        
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
        // Check if the collection is allowed
        if (!allowedCollections[nftAddress]) {
            return false;
        }
        
        // Check if the NFT has a minimum value
        uint256 nftValue = _priceOracle.getNFTPrice(nftAddress, tokenId);
        return nftValue > 0;
    }
    
    /**
     * @dev Check the value of an NFT
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return Value of the NFT
     */
    function checkNFTValue(
        address nftAddress,
        uint256 tokenId
    ) external view returns (uint256) {
        return _priceOracle.getNFTPrice(nftAddress, tokenId);
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
            CollateralInfo memory collateral = collaterals[collateralIds[i]];
            
            if (collateral.active) {
                totalValue += _priceOracle.getNFTPrice(collateral.nftAddress, collateral.tokenId);
            }
        }
        
        return totalValue;
    }
    
    /**
     * @dev Add or remove a collection from the allow list
     * @param nftAddress NFT contract address
     * @param allowed Whether the collection is allowed
     */
    function setCollectionAllowance(address nftAddress, bool allowed) external onlyOwner {
        allowedCollections[nftAddress] = allowed;
        emit CollectionAllowListUpdated(nftAddress, allowed);
    }
    
    /**
     * @dev Set the minimum collateral ratio
     * @param newRatio New minimum collateral ratio (in basis points)
     */
    function setMinimumCollateralRatio(uint256 newRatio) external onlyOwner {
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