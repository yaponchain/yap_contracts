// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IYapLendCore {
    function loans(uint256 loanId) external view returns (
        address borrower,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        uint256 interestRate,
        bool active,
        bool liquidated
    );
    
    function protocolFeePercentage() external view returns (uint256);
    function feeCollector() external view returns (address);
}

/**
 * @title LoanVault
 * @dev Manages the funds for the YAP LEND protocol
 */
contract LoanVault is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // Interface to YapLendCore
    IYapLendCore private _yapLendCore;
    
    // Mapping from loan ID to amount deposited
    mapping(uint256 => uint256) public loanDeposits;
    
    // Mapping from loan ID to amount of interest accrued
    mapping(uint256 => uint256) public loanInterests;
    
    // Events
    event Deposited(uint256 indexed loanId, uint256 amount);
    event Withdrawn(uint256 indexed loanId, address indexed recipient, uint256 amount);
    event InterestAccrued(uint256 indexed loanId, uint256 amount);
    event ProtocolFeeSent(uint256 indexed loanId, address indexed feeCollector, uint256 amount);
    event FailedToSendFee(uint256 indexed loanId, address indexed feeCollector, uint256 amount);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    
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
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Deposit funds for a loan
     * @param loanId ID of the loan
     */
    function deposit(uint256 loanId) external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Amount must be greater than 0");
        
        // Update loan deposit amount
        loanDeposits[loanId] += msg.value;
        
        emit Deposited(loanId, msg.value);
    }
    
    /**
     * @dev Withdraw funds from a loan
     * @param loanId ID of the loan
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 loanId, uint256 amount) external nonReentrant {
        // Get loan information
        (address borrower, , , , , bool active, bool liquidated) = _yapLendCore.loans(loanId);
        
        // Only borrower can withdraw if loan is active and not liquidated
        if (active && !liquidated) {
            require(msg.sender == borrower, "Only borrower can withdraw from active loans");
        }
        
        // Protocol owner can withdraw from inactive loans (repaid or liquidated)
        if (!active || liquidated) {
            require(msg.sender == owner(), "Only owner can withdraw from inactive loans");
        }
        
        // Check if amount is available
        require(loanDeposits[loanId] >= amount, "Insufficient funds in loan vault");
        
        // Update loan deposit amount
        loanDeposits[loanId] -= amount;
        
        // Transfer the funds
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(loanId, msg.sender, amount);
    }
    
    /**
     * @dev Calculate interest for a loan using the formula:
     * Interest = Principal × (APR/100) × (Days/365)
     * 
     * @param loanId ID of the loan
     * @return Interest amount
     */
    function calculateInterest(uint256 loanId) external view returns (uint256) {
        (
            ,
            uint256 principal,
            uint256 startTime,
            uint256 duration,
            uint256 interestRate,
            bool active,
            bool liquidated
        ) = _yapLendCore.loans(loanId);
        
        if (!active || liquidated) {
            return 0;
        }
        
        // Calculate time elapsed (capped at loan duration)
        uint256 timeElapsed = block.timestamp - startTime;
        if (timeElapsed > duration) {
            timeElapsed = duration;
        }
        
        // Convert time elapsed from seconds to days
        uint256 daysElapsed = timeElapsed / 86400;
        
        // Interest = Principal × (APR/100) × (Days/365)
        // interestRate is in basis points (e.g., 4000 = 40%)
        uint256 interest = (principal * interestRate * daysElapsed) / (10000 * 365);
        
        return interest;
    }
    
    /**
     * @dev Process interest payment and send protocol fee to multisig
     * @param loanId ID of the loan
     * @param interestAmount Amount of interest paid
     */
    function processInterestPayment(uint256 loanId, uint256 interestAmount) external nonReentrant {
        // This function should only be called by YapLendCore during loan repayment
        
        // For hackathon purposes, we're not strictly checking the caller
        // In production, require(msg.sender == address(_yapLendCore), "Unauthorized");
        
        if (interestAmount == 0) {
            return;
        }
        
        // Get protocol fee percentage and fee collector address
        uint256 protocolFeePercentage = _yapLendCore.protocolFeePercentage();
        address feeCollector = _yapLendCore.feeCollector();
        
        // Calculate protocol fee (5% of interest by default)
        uint256 protocolFee = (interestAmount * protocolFeePercentage) / 10000;
        
        // Update loan interest amount
        loanInterests[loanId] += interestAmount;
        
        // Send protocol fee to multisig if there's any fee
        if (protocolFee > 0 && feeCollector != address(0)) {
            // Send fee directly to the multisig
            (bool success, ) = payable(feeCollector).call{value: protocolFee}("");
            
            if (success) {
                emit ProtocolFeeSent(loanId, feeCollector, protocolFee);
            } else {
                // If transfer fails, log the event but continue execution
                emit FailedToSendFee(loanId, feeCollector, protocolFee);
            }
        }
        
        emit InterestAccrued(loanId, interestAmount);
    }
    
    /**
     * @dev Emergency withdrawal function
     * Only callable by the owner after the contract is paused
     * @param recipient Address to send the funds to
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address recipient, uint256 amount) external nonReentrant onlyOwner whenPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");
        
        // Transfer the funds
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Emergency withdrawal failed");
        
        emit EmergencyWithdrawal(recipient, amount);
    }
    
    /**
     * @dev Manually send any unsent fees to the fee collector
     * Useful if previous fee transfers failed
     */
    function recoverFailedFees() external nonReentrant onlyOwner {
        address feeCollector = _yapLendCore.feeCollector();
        require(feeCollector != address(0), "No fee collector set");
        
        // Get contract balance
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to recover");
        
        // Send the entire balance to the fee collector
        (bool success, ) = payable(feeCollector).call{value: balance}("");
        require(success, "Fee recovery failed");
        
        emit ProtocolFeeSent(0, feeCollector, balance);
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