// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IYapLendCore {
    function createLoan(
        address borrower,
        address lender,
        address[] memory nftAddresses,
        uint256[] memory tokenIds,
        uint256 loanAmount,
        uint256 duration,
        uint256 proposedInterestRate
    ) external payable returns (uint256);
}

/**
 * @title ProposalManager
 * @dev Manages loan proposals between NFT owners and liquidity providers
 */
contract ProposalManager is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    // Interface to YapLendCore
    IYapLendCore private _yapLendCore;
    
    // Struct to store proposal information
    struct Proposal {
        // Borrower (NFT owner) info
        address borrower;
        address[] nftAddresses;
        uint256[] tokenIds;
        
        // Lender (liquidity provider) info
        address lender;
        uint256 amount;
        
        // Terms
        uint256 duration; // in seconds
        uint256 interestRate; // in basis points (e.g., 4000 = 40%)
        
        // Proposal state
        uint256 createdAt;
        uint256 expiresAt;
        bool isActive;
        bool isCounterOffer; // true if this is a counter offer from lender
    }   
    
    // Mapping from proposal ID to Proposal struct
    mapping(uint256 => Proposal) public proposals;
    
    // Counter for proposal IDs
    uint256 private _proposalIdCounter;
    
    // Mapping of locked funds per lender address
    mapping(address => uint256) public lockedFunds;
    
    // Events
    event ProposalCreated(uint256 indexed proposalId, address indexed borrower, address[] nftAddresses, uint256[] tokenIds, uint256 amount, uint256 duration, uint256 interestRate);
    event CounterOfferCreated(uint256 indexed proposalId, address indexed lender, uint256 amount, uint256 duration, uint256 interestRate, uint256 expiresAt);
    event ProposalAccepted(uint256 indexed proposalId, address indexed borrower, address indexed lender, uint256 loanId);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalExpired(uint256 indexed proposalId);
    event FundsLocked(address indexed lender, uint256 amount);
    event FundsReleased(address indexed lender, uint256 amount);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     */
    function initialize(address yapLendCoreAddress) public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        
        _yapLendCore = IYapLendCore(yapLendCoreAddress);
        _proposalIdCounter = 1;
    }
    
    /**
     * @dev Create a loan proposal from NFT owner
     * @param nftAddresses Array of NFT contract addresses
     * @param tokenIds Array of token IDs
     * @param requestedAmount Amount requested by the borrower
     * @param duration Duration of the loan in seconds
     * @param interestRate Proposed interest rate (APR in basis points)
     * @return proposalId ID of the created proposal
     */
    function createProposal(
        address[] memory nftAddresses,
        uint256[] memory tokenIds,
        uint256 requestedAmount,
        uint256 duration,
        uint256 interestRate
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(nftAddresses.length > 0, "No collateral provided");
        require(nftAddresses.length == tokenIds.length, "Arrays length mismatch");
        require(requestedAmount > 0, "Amount must be greater than 0");
        require(duration > 0, "Duration must be greater than 0");
        
        uint256 proposalId = _proposalIdCounter++;
        
        proposals[proposalId] = Proposal({
            borrower: msg.sender,
            nftAddresses: nftAddresses,
            tokenIds: tokenIds,
            lender: address(0),
            amount: requestedAmount,
            duration: duration,
            interestRate: interestRate,
            createdAt: block.timestamp,
            expiresAt: 0, // No expiration for initial proposal
            isActive: true,
            isCounterOffer: false
        });
        
        emit ProposalCreated(proposalId, msg.sender, nftAddresses, tokenIds, requestedAmount, duration, interestRate);
        
        return proposalId;
    }
    
    /**
     * @dev Create a counter offer from liquidity provider
     * @param proposalId ID of the existing proposal
     * @param offerAmount Amount offered by the lender
     * @param duration Duration of the loan in seconds
     * @param interestRate Proposed interest rate (APR in basis points)
     * @param validityPeriod How long the counter offer is valid for (in seconds)
     * @return counterProposalId ID of the created counter proposal
     */
    function createCounterOffer(
        uint256 proposalId,
        uint256 offerAmount,
        uint256 duration,
        uint256 interestRate,
        uint256 validityPeriod
    ) external payable nonReentrant whenNotPaused returns (uint256) {
        require(proposals[proposalId].isActive, "Proposal not active");
        require(msg.value >= offerAmount, "Insufficient funds sent");
        require(validityPeriod > 0 && validityPeriod <= 30 days, "Invalid validity period");
        
        Proposal memory originalProposal = proposals[proposalId];
        
        uint256 counterProposalId = _proposalIdCounter++;
        
        // Lock the funds
        lockedFunds[msg.sender] += offerAmount;
        
        // Create counter offer proposal
        proposals[counterProposalId] = Proposal({
            borrower: originalProposal.borrower,
            nftAddresses: originalProposal.nftAddresses,
            tokenIds: originalProposal.tokenIds,
            lender: msg.sender,
            amount: offerAmount,
            duration: duration,
            interestRate: interestRate,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + validityPeriod,
            isActive: true,
            isCounterOffer: true
        });
        
        // Refund excess ETH if any
        uint256 excess = msg.value - offerAmount;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "Refund failed");
        }
        
        emit CounterOfferCreated(counterProposalId, msg.sender, offerAmount, duration, interestRate, block.timestamp + validityPeriod);
        emit FundsLocked(msg.sender, offerAmount);
        
        return counterProposalId;
    }
    
    /**
     * @dev Accept a proposal or counter offer
     * @param proposalId ID of the proposal to accept
     */
    function acceptProposal(uint256 proposalId) external payable nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.isActive, "Proposal not active");
        require(
            proposal.isCounterOffer ? msg.sender == proposal.borrower : msg.sender != proposal.borrower,
            "Unauthorized acceptance"
        );
        
        // If it's a counter offer, check if it hasn't expired
        if (proposal.isCounterOffer) {
            require(block.timestamp <= proposal.expiresAt, "Counter offer expired");
        } else {
            // If it's an original proposal, the lender becomes the caller
            proposal.lender = msg.sender;
            
            // Check if lender sent enough funds
            require(msg.value >= proposal.amount, "Insufficient funds sent");
            
            // Lock the funds
            lockedFunds[msg.sender] += proposal.amount;
            
            // Refund excess ETH if any
            uint256 excess = msg.value - proposal.amount;
            if (excess > 0) {
                (bool success, ) = payable(msg.sender).call{value: excess}("");
                require(success, "Refund failed");
            }
            
            emit FundsLocked(msg.sender, proposal.amount);
        }
        
        // Mark proposal as inactive
        proposal.isActive = false;
        
        // Unlock the funds from the lender
        uint256 amountToUnlock = proposal.amount;
        lockedFunds[proposal.lender] -= amountToUnlock;
        
        // Create loan in YapLendCore com a nova assinatura da função
        uint256 loanId = _yapLendCore.createLoan{value: proposal.amount}(
            proposal.borrower,
            proposal.lender,
            proposal.nftAddresses,
            proposal.tokenIds,
            proposal.amount,
            proposal.duration,
            proposal.interestRate
        );
        
        emit ProposalAccepted(proposalId, proposal.borrower, proposal.lender, loanId);
        emit FundsReleased(proposal.lender, amountToUnlock);
    }
    
    /**
     * @dev Reject a counter offer (only borrower can reject)
     * @param proposalId ID of the counter offer to reject
     */
    function rejectCounterOffer(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.isActive, "Proposal not active");
        require(proposal.isCounterOffer, "Not a counter offer");
        require(msg.sender == proposal.borrower, "Only borrower can reject");
        require(block.timestamp <= proposal.expiresAt, "Counter offer already expired");
        
        // Mark proposal as inactive
        proposal.isActive = false;
        
        // Unlock the funds from the lender
        uint256 amountToUnlock = proposal.amount;
        lockedFunds[proposal.lender] -= amountToUnlock;
        
        // Return the funds to the lender
        (bool success, ) = payable(proposal.lender).call{value: amountToUnlock}("");
        require(success, "Fund return failed");
        
        emit ProposalRejected(proposalId);
        emit FundsReleased(proposal.lender, amountToUnlock);
    }
    
    /**
     * @dev Process expired counter offers (can be called by anyone)
     * @param proposalId ID of the counter offer to process
     */
    function processExpiredOffer(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.isActive, "Proposal not active");
        require(proposal.isCounterOffer, "Not a counter offer");
        require(block.timestamp > proposal.expiresAt, "Counter offer not expired");
        
        // Mark proposal as inactive
        proposal.isActive = false;
        
        // Unlock the funds from the lender
        uint256 amountToUnlock = proposal.amount;
        lockedFunds[proposal.lender] -= amountToUnlock;
        
        // Return the funds to the lender
        (bool success, ) = payable(proposal.lender).call{value: amountToUnlock}("");
        require(success, "Fund return failed");
        
        emit ProposalExpired(proposalId);
        emit FundsReleased(proposal.lender, amountToUnlock);
    }
    
    /**
     * @dev Check if a counter offer has expired
     * @param proposalId ID of the counter offer
     * @return True if expired
     */
    function isOfferExpired(uint256 proposalId) external view returns (bool) {
        Proposal memory proposal = proposals[proposalId];
        
        if (!proposal.isActive || !proposal.isCounterOffer) {
            return false;
        }
        
        return block.timestamp > proposal.expiresAt;
    }
    
        /**
    * @dev Get detailed proposal information
    * @param proposalId ID of the proposal
    * @return borrower Address of the borrower
    * @return lender Address of the lender
    * @return amount Loan amount
    * @return duration Duration of the loan in seconds
    * @return interestRate Interest rate in basis points
    * @return createdAt Timestamp of proposal creation
    * @return expiresAt Timestamp of expiration
    * @return isActive Whether the proposal is active
    * @return isCounterOffer Whether this is a counter offer
    */
    function getProposal(uint256 proposalId) external view returns (
        address borrower,
        address lender,
        uint256 amount,
        uint256 duration,
        uint256 interestRate,
        uint256 createdAt,
        uint256 expiresAt,
        bool isActive,
        bool isCounterOffer
    ) {
        Proposal memory proposal = proposals[proposalId];
        
        return (
            proposal.borrower,
            proposal.lender,
            proposal.amount,
            proposal.duration,
            proposal.interestRate,
            proposal.createdAt,
            proposal.expiresAt,
            proposal.isActive,
            proposal.isCounterOffer
        );
    }
    
    /**
     * @dev Get collateral information for a proposal
     * @param proposalId ID of the proposal
     * @return nftAddresses Array of NFT addresses
     * @return tokenIds Array of token IDs
     */
    function getProposalCollateral(uint256 proposalId) external view returns (
        address[] memory nftAddresses,
        uint256[] memory tokenIds
    ) {
        Proposal memory proposal = proposals[proposalId];
        
        return (proposal.nftAddresses, proposal.tokenIds);
    }
    
    /**
     * @dev Check how much funds a lender has locked
     * @param lender Address of the lender
     * @return Amount of locked funds
     */
    function getLockedFunds(address lender) external view returns (uint256) {
        return lockedFunds[lender];
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