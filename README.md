YapLend Protocol

YapLend is a decentralized NFT lending protocol built on Monad that allows NFT owners to unlock liquidity from their digital assets without selling them. The protocol enables peer-to-peer loans using NFTs as collateral while preserving ownership benefits through a unique escrow mechanism.


Architecture Overview

YapLend follows a modular architecture with upgradeable smart contracts using the UUPS (Universal Upgradeable Proxy Standard) pattern from OpenZeppelin. The system is designed with clear separation of concerns, with specialized contracts handling different aspects of the lending process.
The protocol architecture consists of the following key layers:

Core Layer - Central management of loans and protocol parameters
Collateral Layer - Handling of NFT collateral through escrow contracts
Liquidity Layer - Management of lending funds and interest rates
Proposal Layer - Facilitation of loan proposal creation and negotiation
Oracle Layer - Price discovery for NFTs and other assets
Verification Layer - Ownership validation and security checks

This modular design allows for targeted upgrades, enhanced security, and easier auditability.

Core Components

The YapLend protocol comprises the following main components:
YapLendCore
The central contract that manages the entire loan lifecycle, including loan creation, repayment, and liquidation. It coordinates between all other components and enforces protocol rules.

CollateralManager
Responsible for securing NFT collateral using a novel escrow system. The CollateralManager deploys individual escrow contracts for each NFT collateral, allowing borrowers to retain benefits from their NFTs while they're used as collateral.

NFTEscrow
Individual escrow contracts that hold NFT collateral. These contracts implement delegation features that allow borrowers to maintain access to NFT utility and benefits while the asset is locked as collateral.

LoanVault
Manages the funds associated with each loan, including deposit handling, interest calculations, and withdrawal processes.

LiquidityPool
Provides liquidity for the protocol and manages interest rates based on utilization metrics.

ProposalManager
Facilitates the creation and negotiation of loan proposals between borrowers and lenders.

NFTVerifier
Verifies NFT ownership and handles approval checks to ensure security throughout the lending process.

Key Features

NFT Delegation While Collateralized
Unlike most NFT lending protocols, YapLend allows borrowers to maintain beneficial ownership of their NFTs while they are locked as collateral. This is achieved through a sophisticated escrow system that implements delegation interfaces, enabling borrowers to:

Continue participating in NFT staking programs
Access token airdrops and rewards
Participate in governance votes
Maintain access to utility functions
Claim benefits associated with the NFT

P2P Loan Negotiation
The protocol supports direct peer-to-peer loan negotiations through:

Borrower-initiated loan proposals
Lender counter-offers
Customizable loan terms (duration, interest rate)
Escrow-backed security guarantees

Upgradeable Architecture
All protocol contracts are upgradeable using the UUPS pattern, allowing for:

Bug fixes without disrupting the protocol
Protocol enhancements over time
Parameter adjustments without redeployment

Multi-Collateral Support
Borrowers can use multiple NFTs as collateral for a single loan, increasing their borrowing capacity and diversifying their collateral risk.
Partner Project Integrations
The NFTEscrow contracts can register and support various partner project interfaces, enabling seamless integration with NFT ecosystems that rely on delegation or verification mechanisms.
Technical Implementation
Smart Contract Structure
YapLend implements a comprehensive suite of interconnected smart contracts:

YapLendCore
├── CollateralManager
│   └── NFTEscrow (clones)
├── LoanVault
├── LiquidityPool
├── ProposalManager
├── NFTVerifier
└── PriceOracle

Upgrade Pattern
YapLend uses the UUPS (Universal Upgradeable Proxy Standard) upgrade pattern, which:

Stores upgrade logic in the implementation contract itself
Reduces proxy contract complexity
Provides enhanced security against unauthorized upgrades
Allows for contract logic evolution without state loss

Clone Factory Pattern
The protocol employs the Clone Factory pattern (via OpenZeppelin's Clones library) for NFTEscrow deployment, which:

Significantly reduces gas costs for escrow creation
Allows for minimal proxy contracts that delegate calls to an implementation
Enables the creation of numerous escrow contracts without excessive deployment costs

Reentrancy Protection
All contracts implement robust reentrancy guards to prevent reentrancy attacks. Critical functions are protected with the nonReentrant modifier from OpenZeppelin's ReentrancyGuardUpgradeable contract.
Error Handling
The protocol implements comprehensive error handling with:

Granular require statements with descriptive error messages
Try/catch blocks for external calls to handle failures gracefully
Event emissions for failures that require manual intervention

Event Emission
Extensive event logging is implemented throughout the protocol for:

Off-chain tracking of protocol activity
Facilitating front-end integration
Supporting analytics and monitoring
Enabling historical analysis

Smart Contract Design
YapLendCore.sol
The central contract managing the loan lifecycle:

Creates and tracks loans
Handles repayments and liquidations
Enforces protocol parameters (interest rates, durations)
Coordinates between other protocol components

CollateralManager.sol
Manages NFT collateral through a system of escrow contracts:

Deploys individual escrow contracts for each NFT
Tracks collateral status and associations with loans
Facilitates benefit claiming while NFTs are in escrow
Handles collateral release during repayment or liquidation

NFTEscrow.sol
Holds individual NFT collateral and implements delegation features:

Securely holds the NFT as collateral
Provides delegation interfaces for various partner projects
Enables borrowers to claim benefits and airdrops
Implements ERC721 receiver functionality
Supports partner-specific verification methods

LoanVault.sol
Manages the funds associated with loans:

Tracks loan deposits
Calculates interest accrual
Processes repayments and liquidations
Handles protocol fee collection

LiquidityPool.sol
Manages protocol liquidity and interest rates:

Accepts liquidity provider deposits
Calculates dynamic APYs based on utilization
Handles liquidity withdrawal
Tracks utilization metrics

ProposalManager.sol
Facilitates loan negotiation between borrowers and lenders:

Manages the proposal lifecycle
Handles counter-offers
Locks lender funds during negotiation
Validates NFT ownership and approvals

NFTVerifier.sol
Verifies NFT ownership and approvals:

Validates direct NFT ownership
Checks for escrow beneficial ownership
Verifies NFT approvals for protocol use

PriceOracle.sol
Provides price data for assets:

Tracks floor prices for NFT collections
Supports specific NFT pricing
Integrates with external price feeds

Security Considerations
Access Control
The protocol implements strict access control using OpenZeppelin's OwnableUpgradeable contract and custom modifiers to ensure that only authorized parties can execute sensitive functions.
Funds Protection

Clear separation between contract funds and user funds
Non-custodial design where possible
Emergency functions for fund recovery with appropriate governance controls

Pause Mechanism
All critical contracts include a pause mechanism that can be triggered by the protocol owner in case of emergencies, allowing time for issue resolution without further risk.
Flexible Ownership
The protocol is designed to eventually transition to a decentralized governance model, with current owner-only functions being available for future governance contracts.
Monad Integration
YapLend leverages Monad's accelerated EVM for enhanced performance and reduced gas costs:
Optimized for Monad's Architecture

Designed to benefit from Monad's parallel transaction processing
Takes advantage of reduced gas costs for contract deployments
Optimized for Monad's consensus mechanism

Gas Optimization
The protocol implements several gas optimization strategies:

Clone factory pattern for escrow deployment
Storage packing to minimize storage slots
Batch processing where possible
Optimized loops with gas-efficient patterns

Monad-Specific Configuration

The project includes specific configuration for Monad deployment:

Custom network configuration in Hardhat

Optimized gas settings for Monad
Sourcify integration for Monad contract verification

Deployment

YapLend uses a systematic deployment process to ensure contract integrity:

Deploy implementation contracts

Initialize proxies with proper parameters
Configure contract interconnections
Verify contracts on Monad explorer via Sourcify

Deployment Scripts
The repository includes scripts for:

Local development deployment

Testnet deployment (Monad testnet)
Contract verification
Ownership transfer (for future governance)

License
The YapLend protocol is licensed under the MIT License. See the LICENSE file for details.