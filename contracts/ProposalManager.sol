    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.26;

    import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
    import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

    // Interface para o YapLendCore
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
        
        function nftVerifier() external view returns (address);
    }

    // Interface para o NFTVerifier
    interface INFTVerifier {
        function verifyOwnership(address owner, address nftAddress, uint256 tokenId) external view returns (bool);
        function checkOwnership(address owner, address nftAddress, uint256 tokenId) external view returns (bool);
        function checkApproval(address owner, address nftAddress, uint256 tokenId) external view returns (bool);
    }

    /**
     * @title ProposalManager
     * @dev Manages loan proposals between NFT owners and liquidity providers with escrow integration
     */
    contract ProposalManager is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
        // Interface to YapLendCore
        IYapLendCore private _yapLendCore;
        
        // Interface to NFTVerifier
        INFTVerifier private _nftVerifier;
        
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
        event NFTVerificationFailed(address indexed borrower, address nftAddress, uint256 tokenId);
        event ProposalCancelled(uint256 indexed proposalId, address indexed borrower);
        
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
            __UUPSUpgradeable_init();
            
            _yapLendCore = IYapLendCore(yapLendCoreAddress);
            // Inicialize o NFTVerifier usando o endereço do YapLendCore
            _nftVerifier = INFTVerifier(_yapLendCore.nftVerifier());
            _proposalIdCounter = 1;
        }
        
        /**
         * @dev Function that authorizes upgrades for UUPS pattern
         * @param newImplementation Address of the new implementation
         */
        function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
        
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
            
            // Verify NFT ownership using the updated NFTVerifier
            for (uint256 i = 0; i < nftAddresses.length; i++) {
                bool isOwner = _nftVerifier.checkOwnership(msg.sender, nftAddresses[i], tokenIds[i]);
                require(isOwner, "Not owner of NFT");
                
                bool isApproved = _nftVerifier.checkApproval(msg.sender, nftAddresses[i], tokenIds[i]);
                require(isApproved, "NFT not approved for transfer");
            }
            
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
        // Cache da proposta para reduzir leituras em storage
        Proposal storage prop = proposals[proposalId];
        require(prop.isActive, "Proposal not active");
        
        // Validação da chamada conforme o tipo de proposta
        if (prop.isCounterOffer) {
            // Na contra-oferta, apenas o borrower pode aceitar
            require(msg.sender == prop.borrower, "Unauthorized acceptance");
            require(block.timestamp <= prop.expiresAt, "Counter offer expired");
            
            // Cache do tamanho do array para reduzir leituras
            uint256 len = prop.nftAddresses.length;
            for (uint256 i = 0; i < len; ) {
                // Verifica propriedade e aprovação do NFT
                bool ownerOk = _nftVerifier.verifyOwnership(prop.borrower, prop.nftAddresses[i], prop.tokenIds[i]);
                if (!ownerOk) {
                    emit NFTVerificationFailed(prop.borrower, prop.nftAddresses[i], prop.tokenIds[i]);
                    revert("Borrower no longer owns NFT");
                }
                require(_nftVerifier.checkApproval(prop.borrower, prop.nftAddresses[i], prop.tokenIds[i]), "NFT approval revoked");
                unchecked { i++; }
            }
        } else {
            // Na proposta original, o lender (não o borrower) deve aceitar e enviar os fundos
            require(msg.sender != prop.borrower, "Unauthorized acceptance");
            require(msg.value >= prop.amount, "Insufficient funds sent");
            prop.lender = msg.sender; // Define o lender
            lockedFunds[msg.sender] += prop.amount;
            
            // Se houver excesso, reembolsa imediatamente
            uint256 excess = msg.value - prop.amount;
            if (excess > 0) {
                (bool refunded, ) = payable(msg.sender).call{value: excess}("");
                require(refunded, "Refund failed");
            }
            emit FundsLocked(msg.sender, prop.amount);
        }
        
        // Marca a proposta como inativa
        prop.isActive = false;
        
        // Desbloqueia os fundos do lender
        uint256 amount = prop.amount; // cache local para economizar gás
        lockedFunds[prop.lender] -= amount;
        
        // Cria o empréstimo chamando o contrato central
        uint256 loanId = _yapLendCore.createLoan{value: amount}(
            prop.borrower,
            prop.lender,
            prop.nftAddresses,
            prop.tokenIds,
            amount,
            prop.duration,
            prop.interestRate
        );
        
        emit ProposalAccepted(proposalId, prop.borrower, prop.lender, loanId);
        emit FundsReleased(prop.lender, amount);
    }


            /**
         * @dev Cancel a proposal (only borrower can cancel)
         * @param proposalId ID of the proposal to cancel
         */
        function cancelProposal(uint256 proposalId) external nonReentrant whenNotPaused {
            Proposal storage proposal = proposals[proposalId];
            
            require(proposal.isActive, "Proposal not active");
            require(msg.sender == proposal.borrower, "Only borrower can cancel proposal");
            
            // Para contra-ofertas, verificar se não está expirada
            if (proposal.isCounterOffer) {
                require(block.timestamp <= proposal.expiresAt, "Counter offer already expired");
            }
            
            // Marcar proposta como inativa
            proposal.isActive = false;
            
            // Se for uma contra-oferta, desbloquear os fundos do credor
            if (proposal.isCounterOffer) {
                uint256 amountToUnlock = proposal.amount;
                lockedFunds[proposal.lender] -= amountToUnlock;
                
                // Devolver os fundos ao credor
                (bool success, ) = payable(proposal.lender).call{value: amountToUnlock}("");
                require(success, "Fund return failed");
                
                emit FundsReleased(proposal.lender, amountToUnlock);
            }
            
            emit ProposalCancelled(proposalId, msg.sender);
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
         * @dev Update the NFTVerifier reference (in case it changes in YapLendCore)
         */
        function updateNFTVerifier() external {
            _nftVerifier = INFTVerifier(_yapLendCore.nftVerifier());
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