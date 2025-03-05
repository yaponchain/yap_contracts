// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title LiquidityPool
 * @dev Manages liquidity for the YAP LEND protocol
 */
contract LiquidityPool is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // Mapping from provider address to their liquidity amount
    mapping(address => uint256) public providerLiquidity;
    
    // Total liquidity in the pool
    uint256 public totalLiquidity;
    
    // APY for liquidity providers (in basis points, e.g., 500 = 5%)
    uint256 public liquidityAPY;
    
    // Last update timestamp for APY
    uint256 public lastAPYUpdateTime;
    
    // Utilization target (in basis points, e.g., 8000 = 80%)
    uint256 public utilizationTarget;
    
    // Minimum and maximum APY
    uint256 public minAPY;
    uint256 public maxAPY;
    
    // Utilization ratio (in basis points, e.g., 7500 = 75%)
    uint256 public utilizationRatio;
    
    // Events
    event LiquidityProvided(address indexed provider, uint256 amount);
    event LiquidityWithdrawn(address indexed provider, uint256 amount);
    event APYUpdated(uint256 newAPY);
    event UtilizationRatioUpdated(uint256 newRatio);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract
     */
    function initialize() public initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        liquidityAPY = 500; // 5% initial APY
        lastAPYUpdateTime = block.timestamp;
        utilizationTarget = 8000; // 80% target utilization
        minAPY = 200; // 2% minimum APY
        maxAPY = 2000; // 20% maximum APY
        utilizationRatio = 0; // 0% initial utilization
    }
    
    /**
     * @dev Function that authorizes upgrades for UUPS pattern
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Provide liquidity to the pool
     */
    function provideLiquidity() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Amount must be greater than 0");
        
        // Update provider's liquidity
        providerLiquidity[msg.sender] += msg.value;
        
        // Update total liquidity
        totalLiquidity += msg.value;
        
        // Update utilization ratio
        _updateUtilizationRatio();
        
        emit LiquidityProvided(msg.sender, msg.value);
    }
    
    /**
     * @dev Withdraw liquidity from the pool
     * @param amount Amount to withdraw
     */
    function withdrawLiquidity(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(providerLiquidity[msg.sender] >= amount, "Insufficient liquidity");
        require(address(this).balance >= amount, "Insufficient pool balance");
        
        // Update provider's liquidity
        providerLiquidity[msg.sender] -= amount;
        
        // Update total liquidity
        totalLiquidity -= amount;
        
        // Update utilization ratio
        _updateUtilizationRatio();
        
        // Transfer the funds
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit LiquidityWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Calculate APY based on utilization ratio
     * @return Current APY for liquidity providers
     */
    function calculateAPY() external view returns (uint256) {
        return liquidityAPY;
    }
    
    /**
     * @dev Update the APY based on current utilization ratio
     * Only callable by owner or authorized contracts
     */
    function updateAPY() external onlyOwner {
        _updateAPY();
    }
    
    /**
     * @dev Internal function to update the APY
     */
    function _updateAPY() internal {
        // Update APY based on utilization ratio
        // If utilization is below target, decrease APY
        // If utilization is above target, increase APY
        
        if (utilizationRatio < utilizationTarget) {
            // Decrease APY proportionally
            uint256 decrease = (utilizationTarget - utilizationRatio) * (liquidityAPY - minAPY) / utilizationTarget;
            liquidityAPY = liquidityAPY > (minAPY + decrease) ? (liquidityAPY - decrease) : minAPY;
        } else {
            // Increase APY proportionally
            uint256 increase = (utilizationRatio - utilizationTarget) * (maxAPY - liquidityAPY) / (10000 - utilizationTarget);
            liquidityAPY = (liquidityAPY + increase) < maxAPY ? (liquidityAPY + increase) : maxAPY;
        }
        
        lastAPYUpdateTime = block.timestamp;
        
        emit APYUpdated(liquidityAPY);
    }
    
    /**
     * @dev Update the utilization ratio
     * Called when liquidity is provided or withdrawn
     */
    function _updateUtilizationRatio() internal {
        // In a real system, this would calculate:
        // utilizationRatio = (totalLoaned / totalLiquidity) * 10000
        // For the hackathon, we'll use a simplified approach
        
        // For demo purposes, we'll just use the current contract balance versus total liquidity
        if (totalLiquidity > 0) {
            uint256 available = address(this).balance;
            uint256 utilized = totalLiquidity - available;
            utilizationRatio = (utilized * 10000) / totalLiquidity;
        } else {
            utilizationRatio = 0;
        }
        
        emit UtilizationRatioUpdated(utilizationRatio);
        
        // Update APY when utilization changes
        _updateAPY();
    }
    
    /**
     * @dev Set the utilization target
     * @param newTarget New utilization target (in basis points)
     */
    function setUtilizationTarget(uint256 newTarget) external onlyOwner {
        require(newTarget > 0 && newTarget < 10000, "Invalid target");
        utilizationTarget = newTarget;
    }
    
    /**
     * @dev Set the minimum and maximum APY
     * @param newMinAPY New minimum APY (in basis points)
     * @param newMaxAPY New maximum APY (in basis points)
     */
    function setAPYLimits(uint256 newMinAPY, uint256 newMaxAPY) external onlyOwner {
        require(newMinAPY < newMaxAPY, "Min must be less than max");
        require(newMaxAPY < 5000, "Max APY too high"); // Maximum 50% APY
        
        minAPY = newMinAPY;
        maxAPY = newMaxAPY;
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