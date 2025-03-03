// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

/**
 * @title NFTVerifier
 * @dev Verifies NFT ownership without transferring the assets
 */
contract NFTVerifier is Initializable, OwnableUpgradeable {
    using ECDSAUpgradeable for bytes32;
    
    // Mapping of nonce per user address (to prevent replay attacks)
    mapping(address => uint256) public nonces;
    
    // Signature validity period (in seconds)
    uint256 public signatureValidityPeriod;
    
    // Events
    event OwnershipVerified(address indexed owner, address indexed nftAddress, uint256 tokenId, bool result);
    event ApprovalChecked(address indexed owner, address indexed nftAddress, uint256 tokenId, bool result);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        signatureValidityPeriod = 1 hours; // Default validity period
    }
    
    /**
     * @dev Verify NFT ownership using signature
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param signature Signature to verify ownership
     * @return True if ownership is verified
     */
    function verifyOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId,
        bytes memory signature
    ) external view returns (bool) {
        // If signature is empty, check directly on-chain
        if (signature.length == 0) {
            return _checkDirectOwnershipView(owner, nftAddress, tokenId);
        }
        
        // Check signature
        return _verifySignature(owner, nftAddress, tokenId, signature);
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
        
        bool hasApproval = (approvedAddress == address(this) || isApprovedForAll);
        
        return hasApproval;
    }

    // Função não-view para logs (opcional)
    function checkApprovalWithLog(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) external returns (bool) {
        bool result = this.checkApproval(owner, nftAddress, tokenId);
        emit ApprovalChecked(owner, nftAddress, tokenId, result);
        return result;
    }
        
    /**
     * @dev Validate signature for ownership verification
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param signature Signature to verify
     * @return True if signature is valid and user owns the NFT
     */
    function _verifySignature(
        address owner,
        address nftAddress,
        uint256 tokenId,
        bytes memory signature
    ) internal view returns (bool) {
        // Extract timestamp and nonce from signature
        require(signature.length >= 64, "Invalid signature length");
        
        uint256 signatureTimestamp;
        uint256 nonce;
        
        // Decode the timestamp and nonce from the signature
        assembly {
            signatureTimestamp := mload(add(signature, 32))
            nonce := mload(add(signature, 64))
        }
        
        // Check if timestamp is valid
        require(block.timestamp <= signatureTimestamp, "Timestamp from the future");
        require(block.timestamp >= signatureTimestamp - signatureValidityPeriod, "Signature expired");
        
        // Check if nonce is valid
        require(nonce == nonces[owner], "Invalid nonce");
        
        // Create message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                owner,
                nftAddress,
                tokenId,
                nonce,
                signatureTimestamp
            )
        );
        
        // Convert to an Ethereum signed message hash
        bytes32 ethSignedMessageHash = ECDSAUpgradeable.toEthSignedMessageHash(messageHash);
        
        // Recover signer from signature
        address signer = ethSignedMessageHash.recover(signature);
        
        // Check if signer is the claimed owner
        if (signer != owner) {
            return false;
        }
        
        // Verify actual ownership on-chain
        return _checkDirectOwnershipView(owner, nftAddress, tokenId);
    }
    
    /**
     * @dev Check NFT ownership directly on-chain
     * @param owner Address of the claimed owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @return True if owner actually owns the NFT
     */
    function _checkDirectOwnershipView(
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

    // Versão original que emite eventos (para uso interno em funções não-view)
    function _checkDirectOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) internal returns (bool) {
        try IERC721(nftAddress).ownerOf(tokenId) returns (address actualOwner) {
            bool result = (actualOwner == owner);
            emit OwnershipVerified(owner, nftAddress, tokenId, result);
            return result;
        } catch {
            // If ownerOf reverts (token doesn't exist or other issues)
            emit OwnershipVerified(owner, nftAddress, tokenId, false);
            return false;
        }
    }
    
    /**
     * @dev Generate a signature hash for frontend to sign
     * @param owner Address of the owner
     * @param nftAddress NFT contract address
     * @param tokenId Token ID
     * @param deadline Timestamp until which the signature is valid
     * @return Message hash to be signed
     */
    function getMessageHash(
        address owner,
        address nftAddress,
        uint256 tokenId,
        uint256 deadline
    ) external view returns (bytes32) {
        uint256 nonce = nonces[owner];
        
        return keccak256(
            abi.encodePacked(
                owner,
                nftAddress,
                tokenId,
                nonce,
                deadline
            )
        );
    }
    
    /**
     * @dev Increment the nonce for a user
     * Used after a verification to prevent replay attacks
     * @param owner Address of the user
     */
    function incrementNonce(address owner) external onlyOwner {
        nonces[owner]++;
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