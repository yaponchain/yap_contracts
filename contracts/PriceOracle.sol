// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IAggregatorV3 {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/**
* @title PriceOracle
* @dev Provides price data for NFTs and tokens
*/
contract PriceOracle is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Struct to store NFT collection price information
    struct CollectionPrice {
        uint256 floorPrice; // Floor price in wei
        uint256 lastUpdated; // Timestamp of last update
    }
    
    // Mapping from NFT address to collection price info
    mapping(address => CollectionPrice) public collectionPrices;
    
    // Mapping from NFT address and token ID to specific NFT price
    mapping(address => mapping(uint256 => uint256)) public specificNFTPrices;
    
    // Mapping from token address to price feed address
    mapping(address => address) public tokenPriceFeeds;
    
    // Price stale threshold (in seconds)
    uint256 public priceStaleThreshold;
    
    // Authorized updaters
    mapping(address => bool) public authorizedUpdaters;
    
    // Events
    event CollectionPriceUpdated(address indexed nftAddress, uint256 floorPrice);
    event SpecificNFTPriceUpdated(address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event TokenPriceFeedUpdated(address indexed tokenAddress, address indexed priceFeed);
    event UpdaterAuthorization(address indexed updater, bool authorized);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
    * @dev Initializes the contract
    */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        priceStaleThreshold = 24 hours;
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
    * @dev Gets the price of a specific NFT
    * @param nftAddress NFT contract address
    * @param tokenId Token ID
    * @return Price of the NFT in wei
    */
    function getNFTPrice(
        address nftAddress,
        uint256 tokenId
    ) external view returns (uint256) {
        // Check if there's a specific price for this NFT
        uint256 specificPrice = specificNFTPrices[nftAddress][tokenId];
        if (specificPrice > 0) {
            return specificPrice;
        }
        
        // Otherwise, return the collection floor price
        CollectionPrice memory collectionPrice = collectionPrices[nftAddress];
        
        // Check if price exists and is not stale
        require(collectionPrice.floorPrice > 0, "No price data available");
        require(
            block.timestamp - collectionPrice.lastUpdated <= priceStaleThreshold,
            "Price data is stale"
        );
        
        return collectionPrice.floorPrice;
    }
    
    /**
    * @dev Gets the price of a token from a Chainlink price feed
    * @param tokenAddress Token contract address
    * @return Price of the token in USD (scaled by 1e8)
    */
    function getTokenPrice(
        address tokenAddress
    ) external view returns (uint256) {
        address priceFeed = tokenPriceFeeds[tokenAddress];
        require(priceFeed != address(0), "No price feed for token");
        
        // Get price from Chainlink price feed
        (
            ,
            int256 price,
            ,
            uint256 updatedAt,
            
        ) = IAggregatorV3(priceFeed).latestRoundData();
        
        // Check if price is positive
        require(price > 0, "Invalid price");
        
        // Check if price is not stale
        require(
            block.timestamp - updatedAt <= priceStaleThreshold,
            "Price data is stale"
        );
        
        return uint256(price);
    }
    
    /**
    * @dev Updates the floor price for an NFT collection
    * @param nftAddress NFT contract address
    * @param floorPrice New floor price in wei
    */
    function updateCollectionPrice(
        address nftAddress,
        uint256 floorPrice
    ) external {
        require(authorizedUpdaters[msg.sender] || msg.sender == owner(), "Not authorized");
        require(floorPrice > 0, "Price must be positive");
        
        collectionPrices[nftAddress] = CollectionPrice({
            floorPrice: floorPrice,
            lastUpdated: block.timestamp
        });
        
        emit CollectionPriceUpdated(nftAddress, floorPrice);
    }
    
    /**
    * @dev Updates the price for a specific NFT
    * @param nftAddress NFT contract address
    * @param tokenId Token ID
    * @param price New price in wei
    */
    function updateSpecificNFTPrice(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    ) external {
        require(authorizedUpdaters[msg.sender] || msg.sender == owner(), "Not authorized");
        
        specificNFTPrices[nftAddress][tokenId] = price;
        
        emit SpecificNFTPriceUpdated(nftAddress, tokenId, price);
    }
    
    /**
    * @dev Updates the price feed for a token
    * @param tokenAddress Token contract address
    * @param priceFeed Chainlink price feed address
    */
    function updateTokenPriceFeed(
        address tokenAddress,
        address priceFeed
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(priceFeed != address(0), "Invalid price feed address");
        
        tokenPriceFeeds[tokenAddress] = priceFeed;
        
        emit TokenPriceFeedUpdated(tokenAddress, priceFeed);
    }
    
    /**
    * @dev Sets the stale threshold for prices
    * @param newThreshold New threshold in seconds
    */
    function setPriceStaleThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "Threshold must be positive");
        priceStaleThreshold = newThreshold;
    }
    
    /**
    * @dev Authorizes or revokes an address to update prices
    * @param updater Updater address
    * @param authorized Authorization status
    */
    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        require(updater != address(0), "Invalid updater address");
        
        authorizedUpdaters[updater] = authorized;
        
        emit UpdaterAuthorization(updater, authorized);
    }
    
    /**
    * @dev Batch update collection prices
    * @param nftAddresses Array of NFT contract addresses
    * @param floorPrices Array of floor prices
    */
    function batchUpdateCollectionPrices(
        address[] calldata nftAddresses,
        uint256[] calldata floorPrices
    ) external {
        require(authorizedUpdaters[msg.sender] || msg.sender == owner(), "Not authorized");
        require(nftAddresses.length == floorPrices.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            require(floorPrices[i] > 0, "Price must be positive");
            
            collectionPrices[nftAddresses[i]] = CollectionPrice({
                floorPrice: floorPrices[i],
                lastUpdated: block.timestamp
            });
            
            emit CollectionPriceUpdated(nftAddresses[i], floorPrices[i]);
        }
    }
}