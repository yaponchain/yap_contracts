// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "./NFTEscrow.sol";

interface ICollateralManager {
    function validateCollateral(address nftAddress, uint256 tokenId) external view returns (bool);
    function getEscrowAddress(address nftAddress, uint256 tokenId, uint256 loanId) external view returns (address);
    function getLoanEscrowAddresses(uint256 loanId) external view returns (address[] memory);
}

/**
 * @title NFTVerifier (Enhanced for Escrow)
 * @dev Verifies NFT ownership both directly and through escrow
 */
contract NFTVerifier is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Signature validity period (in seconds)
    uint256 public signatureValidityPeriod;
    
    // Reference to the collateral manager
    ICollateralManager public collateralManager;
    
    // Mapping to track delegation records for partner projects
    mapping(address => mapping(address => bool)) private delegationRecords;
    
    // Events
    event DelegationRecorded(address indexed nftAddress, address indexed delegatee, bool status);
    event VerificationRequested(address indexed owner, address indexed nftAddress, uint256 tokenId, bool result);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     * @param _collateralManager Address of the collateral manager
     */
    function initialize(address _collateralManager) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        collateralManager = ICollateralManager(_collateralManager);
        signatureValidityPeriod = 1 hours; // Default validity period
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Set collateral manager address
     * @param _collateralManager Address of the collateral manager
     */
    function setCollateralManager(address _collateralManager) external onlyOwner {
        require(_collateralManager != address(0), "Invalid address");
        collateralManager = ICollateralManager(_collateralManager);
    }
    
    /**
     * @dev Record delegation for partner projects
     * @param nftAddress NFT contract address
     * @param delegatee Delegatee address
     * @param status Delegation status
     */
    function recordDelegation(address nftAddress, address delegatee, bool status) external {
        delegationRecords[nftAddress][delegatee] = status;
        emit DelegationRecorded(nftAddress, delegatee, status);
    }
    
   /**
 * @dev Check NFT ownership without emitting events (for gas estimation)
 * @param owner Address of the claimed owner
 * @param nftAddress NFT contract address
 * @param tokenId Token ID
 * @return True if ownership is verified
 */
    function checkOwnership(
        address owner,
        address nftAddress,
        uint256 tokenId
    ) external view returns (bool) {
        // First check direct ownership
        bool directOwnership = _checkDirectOwnership(owner, nftAddress, tokenId);
    
        if (directOwnership) {
        return true;
    }
    
    // If not direct owner, check escrow ownership
    try IERC721(nftAddress).ownerOf(tokenId) returns (address currentOwner) {
        // Check if current owner is an escrow contract
        try NFTEscrow(currentOwner).isBeneficialOwner(owner) returns (bool isBeneficial) {
            return isBeneficial;
        } catch {
            // Not an escrow contract or doesn't implement the interface
            return false;
        }
    } catch {
        // NFT doesn't exist or error in contract call
        return false;
    }
}

    /**
     * @dev Verify NFT ownership, both directly and through escrow
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
        // First check direct ownership
        bool directOwnership = _checkDirectOwnership(owner, nftAddress, tokenId);
        
        if (directOwnership) {
            return true;
        }
        
        // If not direct owner, check escrow ownership
        try IERC721(nftAddress).ownerOf(tokenId) returns (address currentOwner) {
            // Check if current owner is an escrow contract
            try NFTEscrow(currentOwner).isBeneficialOwner(owner) returns (bool isBeneficial) {
                return isBeneficial;
            } catch {
                // Not an escrow contract or doesn't implement the interface
                return false;
            }
        } catch {
            // NFT doesn't exist or error in contract call
            return false;
        }
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
        bool isOwner = _checkDirectOwnership(owner, nftAddress, tokenId);
        if (!isOwner) {
            // If not direct owner, might be beneficial owner through escrow
            // In escrow model, the escrow contract would be the actual owner
            // and would handle approvals, so we don't need additional checks here
            return false;
        }
        
        // Check if the CollateralManager is approved to transfer the NFT
        address approvedAddress = IERC721(nftAddress).getApproved(tokenId);
        bool isApprovedForAll = IERC721(nftAddress).isApprovedForAll(owner, address(collateralManager));
        
        return (approvedAddress == address(collateralManager) || isApprovedForAll);
    }
    
    /**
     * @dev Verify ownership through an escrow contract
     * @param escrowAddress Escrow contract address
     * @param claimedBeneficiary Claimed beneficiary address
     * @return True if beneficiary is verified
     */
    function verifyEscrowBeneficiary(
        address escrowAddress, 
        address claimedBeneficiary
    ) external view returns (bool) {
        try NFTEscrow(escrowAddress).isBeneficialOwner(claimedBeneficiary) returns (bool isBeneficial) {
            return isBeneficial;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Verify ownership through a partner-specific verification method
     * @param escrowAddress Escrow contract address
     * @param verificationData Verification data
     * @return True if ownership is verified
     */
    function verifyPartnerOwnership(
        address escrowAddress,
        bytes calldata verificationData
    ) external view returns (bool) {
        try NFTEscrow(escrowAddress).verifyOwnership(verificationData) returns (bool isVerified) {
            return isVerified;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Check if a delegate has rights for an NFT
     * @param nftAddress NFT contract address
     * @param delegatee Delegatee address
     * @return True if delegation is verified
     */
    function checkDelegation(address nftAddress, address delegatee) external view returns (bool) {
        return delegationRecords[nftAddress][delegatee];
    }
    
    /**
     * @dev Verify delegation through escrow contract
     * @param escrowAddress Escrow contract address
     * @param delegate Delegate address
     * @return True if delegation is verified
     */
    function verifyEscrowDelegation(
        address escrowAddress,
        address delegate
    ) external view returns (bool) {
        try NFTEscrow(escrowAddress).isDelegateFor(delegate) returns (bool isDelegated) {
            return isDelegated;
        } catch {
            return false;
        }
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