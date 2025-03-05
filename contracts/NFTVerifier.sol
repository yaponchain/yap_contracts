// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

/**
 * @title NFTVerifier (Simplified)
 * @dev Basic version for initial testing - verifies NFT ownership
 */
contract NFTVerifier is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Signature validity period (in seconds)
    uint256 public signatureValidityPeriod;
    
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
        signatureValidityPeriod = 1 hours; // Default validity period
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Verify NFT ownership directly (simplified version)
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return True if ownership is verified
     */
    function verifyOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) external view returns (bool) {
        return _checkDirectOwnership(owner, nftAddress, tokenId);
    }
    
    /**
     * @dev Check if a user has approved the protocol to use their NFT
     * @param owner Address of the owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return True if approval exists
     */
    function checkApproval(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) external view returns (bool) {
        // Check if the NFT is owned by the provided owner
        bool isOwner = IERC721(nftAddress).ownerOf(tokenId) == owner;
        if (!isOwner) {
            return false;
        }
        
        // Check if this contract is approved to transfer the NFT
        address approvedAddress = IERC721(nftAddress).getApproved(tokenId);
        bool isApprovedForAll = IERC721(nftAddress).isApprovedForAll(owner, address(this));
        
        return (approvedAddress == address(this) || isApprovedForAll);
    }
    
    /**
     * @dev Check NFT ownership directly
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return True if owner actually owns the NFT
     */
    function _checkDirectOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) internal view returns (bool) {
        try IERC721(nftAddress).ownerOf(tokenId) returns (address actualOwner) {
            return (actualOwner == owner);
        } catch {
            // If ownerOf reverts (token doesn't exist or other issues)
            return false;
        }
    }
    
    /**
     * @dev Set the signature validity period
     * @param period New validity period in seconds
     */
    function setSignatureValidityPeriod(uint256 period) external onlyOwner {
        require(period > 0, "Period must be positive");
        signatureValidityPeriod = period;
    }
}