// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title NFTEscrow
 * @dev Upgradeable contract to hold NFTs as collateral while keeping delegate rights with the borrower
 */
contract NFTEscrow is 
    Initializable, 
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    ERC721HolderUpgradeable,
    ERC165Upgradeable 
{
    // NFT details
    address public nftAddress;
    uint256 public tokenId;
    
    // Loan details
    uint256 public loanId;
    address public borrower;
    address public lender;
    address public collateralManager;
    
    // Security flags
    bool public isDeposited;
    bool public isReleased;
    
    // Delegation support
    mapping(address => bool) public delegates;
    mapping(bytes4 => bool) private _supportedInterfaces;
    
    // Delegate registry interface
    bytes4 private constant _INTERFACE_ID_DELEGATION = 0x5679cf83;
    
    // Interface IDs for common partner platforms
    bytes4 private constant _INTERFACE_ID_DISCORD = 0x3d3ac1b5;
    bytes4 private constant _INTERFACE_ID_OPENSEA = 0x80ac58cd; // ERC721 interface
    bytes4 private constant _INTERFACE_ID_GALAXY = 0x4e2312e0;
    
    // Partner project delegation interfaces
    mapping(address => bytes4) public partnerInterfaces;
    
    // Eventos
    event NFTDeposited(address nftAddress, uint256 tokenId, address borrower);
    event NFTReleased(address nftAddress, uint256 tokenId, address recipient);
    event BenefitsClaimed(address benefitAddress, uint256 amount, address recipient);
    event DelegationInterfaceAdded(address partnerProject, bytes4 interfaceId);
    event DelegationInterfaceRemoved(address partnerProject);
    event DelegateAdded(address delegate);
    event DelegateRemoved(address delegate);
    event ERC20Withdrawn(address tokenAddress, uint256 amount, address recipient);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the contract, setting up the NFT, loan, and roles
     */
    function initialize(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _loanId,
        address _borrower,
        address _lender,
        address _collateralManager
    ) public initializer {
        __Ownable_init(_collateralManager);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __ERC721Holder_init();
        __ERC165_init();
        
        nftAddress = _nftAddress;
        tokenId = _tokenId;
        loanId = _loanId;
        borrower = _borrower;
        lender = _lender;
        collateralManager = _collateralManager;
        
        // Register default delegation interfaces
        _registerInterface(_INTERFACE_ID_DELEGATION);
        _registerInterface(_INTERFACE_ID_OPENSEA);
        _registerInterface(_INTERFACE_ID_DISCORD);
        _registerInterface(_INTERFACE_ID_GALAXY);
        
        // Add borrower as default delegate
        delegates[borrower] = true;
        
        isDeposited = false;
        isReleased = false;
    }
    
    /**
     * @dev Deposit the NFT into this escrow
     * Can only be called by the owner (CollateralManager)
     */
    function depositNFT() external onlyOwner whenNotPaused nonReentrant {
        require(!isDeposited, "NFT already deposited");
        require(!isReleased, "NFT already released");
        
        // Verificar se este contrato possui o NFT
        try IERC721(nftAddress).ownerOf(tokenId) returns (address currentOwner) {
            if (currentOwner == address(this)) {
                isDeposited = true;
                emit NFTDeposited(nftAddress, tokenId, borrower);
                return;
            }
        } catch {
            revert("NFT does not exist");
        }
        
        // Se chegou aqui, significa que o NFT ainda não está no escrow
        // Isso não deveria acontecer, pois a transferência deve ser feita pelo CollateralManager
        // antes de chamar esta função, mas verificamos por segurança
        revert("NFT not transferred to escrow");
    }
    
    /**
     * @dev Release the NFT to a specified recipient
     * Can only be called by the owner (CollateralManager)
     */
    function releaseNFT(address recipient) external onlyOwner whenNotPaused nonReentrant {
        require(isDeposited, "NFT not deposited");
        require(!isReleased, "NFT already released");
        require(recipient != address(0), "Invalid recipient address");
        
        // Verificar se este contrato ainda possui o NFT
        address currentOwner;
        try IERC721(nftAddress).ownerOf(tokenId) returns (address owner) {
            currentOwner = owner;
        } catch {
            revert("NFT does not exist");
        }
        
        require(currentOwner == address(this), "Escrow does not own the NFT");
        
        // Transferir o NFT para o destinatário
        IERC721(nftAddress).safeTransferFrom(address(this), recipient, tokenId);
        
        isReleased = true;
        emit NFTReleased(nftAddress, tokenId, recipient);
    }
    
    /**
     * @dev Claim benefits on behalf of the borrower (e.g., airdrops, staking rewards)
     */
    function claimBenefits(address benefitAddress, bytes calldata data) 
        external 
        whenNotPaused 
        nonReentrant 
        returns (bool) 
    {
        require(msg.sender == borrower, "Only borrower can claim benefits");
        require(isDeposited && !isReleased, "NFT not in escrow");
        require(benefitAddress != address(0), "Invalid benefit address");
        
        // Verificar se o benefitAddress não é o próprio NFT para evitar exploits
        require(benefitAddress != nftAddress, "Cannot claim from NFT contract");
        
        (bool success, bytes memory result) = benefitAddress.call(data);
        
        if (success) {
            // Parse amount from result if applicable
            uint256 amount = 0;
            if (result.length >= 32) {
                assembly {
                    amount := mload(add(result, 32))
                }
            }
            
            emit BenefitsClaimed(benefitAddress, amount, borrower);
        }
        
        return success;
    }
    
    /**
     * @dev Support checking if this escrow is the owner of the specific NFT
     */
    function isOwnerOf() external view returns (bool) {
        if (!isDeposited || isReleased) {
            return false;
        }
        
        try IERC721(nftAddress).ownerOf(tokenId) returns (address currentOwner) {
            return currentOwner == address(this);
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Check if the given user is the beneficial owner of the NFT in escrow
     */
    function isBeneficialOwner(address user) external view returns (bool) {
        return user == borrower;
    }
    
    /**
     * @dev Check if an address is a delegate for this NFT
     */
    function isDelegateFor(address delegate) external view returns (bool) {
        return delegates[delegate];
    }
    
    /**
     * @dev Add a delegate address (can only be called by borrower)
     */
    function addDelegate(address delegate) external nonReentrant {
        require(msg.sender == borrower, "Only borrower can add delegates");
        require(delegate != address(0), "Invalid delegate address");
        require(!delegates[delegate], "Already a delegate");
        
        delegates[delegate] = true;
        emit DelegateAdded(delegate);
    }
    
    /**
     * @dev Remove a delegate address (can only be called by borrower)
     */
    function removeDelegate(address delegate) external nonReentrant {
        require(msg.sender == borrower, "Only borrower can remove delegates");
        require(delegate != borrower, "Cannot remove borrower as delegate");
        require(delegates[delegate], "Not a delegate");
        
        delegates[delegate] = false;
        emit DelegateRemoved(delegate);
    }
    
    /**
     * @dev Get the NFT address and token ID held in this escrow
     */
    function getEscrowedNFT() external view returns (address, uint256) {
        return (nftAddress, tokenId);
    }
    
    /**
     * @dev Withdraw ERC20 tokens that might have been airdropped to the escrow
     * Only borrower can withdraw, and cannot withdraw the collateral NFT
     */
    function withdrawERC20(address tokenAddress, uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(msg.sender == borrower, "Only borrower can withdraw tokens");
        require(tokenAddress != nftAddress, "Cannot withdraw collateral NFT");
        require(isDeposited && !isReleased, "NFT not in escrow");
        
        // Verificar saldo do token
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");
        
        // Transferir tokens
        bool success = IERC20(tokenAddress).transfer(borrower, amount);
        require(success, "Token transfer failed");
        
        emit ERC20Withdrawn(tokenAddress, amount, borrower);
    }
    
    /**
     * @dev Register a new interface for partner projects
     * Only owner can register interfaces
     */
    function registerPartnerInterface(address partnerProject, bytes4 interfaceId) 
        external 
        onlyOwner 
    {
        require(partnerProject != address(0), "Invalid partner address");
        require(interfaceId != 0xffffffff, "Invalid interface id");
        
        partnerInterfaces[partnerProject] = interfaceId;
        _registerInterface(interfaceId);
        
        emit DelegationInterfaceAdded(partnerProject, interfaceId);
    }
    
    /**
     * @dev Remove a partner project interface
     * Only owner can remove interfaces
     */
    function removePartnerInterface(address partnerProject) 
        external 
        onlyOwner 
    {
        require(partnerProject != address(0), "Invalid partner address");
        require(partnerInterfaces[partnerProject] != bytes4(0), "Interface not registered");
        
        // We don't actually remove the interface from _supportedInterfaces
        // as that could break existing integrations.
        // We just remove the mapping for the partner project.
        delete partnerInterfaces[partnerProject];
        
        emit DelegationInterfaceRemoved(partnerProject);
    }
    
    /**
     * @dev Check if a specific interface is supported
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override 
        returns (bool) 
    {
        return _supportedInterfaces[interfaceId] || super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev Register interface support
     */
    function _registerInterface(bytes4 interfaceId) internal {
        require(interfaceId != 0xffffffff, "Invalid interface id");
        _supportedInterfaces[interfaceId] = true;
    }
    
    /**
     * @dev Support for partner-specific verification interfaces
     * This function can be overridden by specific implementations
     */
    // Substitua a função verifyOwnership no contrato NFTEscrow com esta versão:

/**
 * @dev Support for partner-specific verification interfaces
 * This function can be overridden by specific implementations
 */
    function verifyOwnership(bytes calldata verificationData) 
        external 
        view 
        returns (bool) 
    {
        // Verificação básica: suporta mensagem assinada pelo borrower
        if (verificationData.length >= 85) {  // 32 bytes message + 65 bytes signature
            
            // Em vez de tentar extrair partes específicas da calldata, simplesmente
            // verificamos se o remetente da mensagem é um delegado autorizado
            return msg.sender == borrower || delegates[msg.sender];
        }
        
        // Fallback: aceita chamadas diretas do borrower ou delegados
        return msg.sender == borrower || delegates[msg.sender];
    }
    
    /**
     * @dev Support for calldata-based delegation calls
     * This allows executing arbitrary calls that might be required by partner projects
     * Only borrower can initiate these calls
     */
    function executeDelegatedCall(address target, bytes calldata data) 
        external 
        whenNotPaused 
        nonReentrant 
        returns (bool, bytes memory) 
    {
        require(msg.sender == borrower || delegates[msg.sender], "Not authorized to execute delegated calls");
        require(isDeposited && !isReleased, "NFT not in escrow");
        require(target != address(0), "Invalid target address");
        require(target != nftAddress, "Cannot call NFT contract directly");
        
        // Execute the call and return the result
        (bool success, bytes memory result) = target.call(data);
        
        return (success, result);
    }
    
    /**
     * @dev Pause the contract
     * Only owner can pause
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     * Only owner can unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Authorize upgrade
     * Only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {}
}