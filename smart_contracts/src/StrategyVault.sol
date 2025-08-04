// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./LiquidityPool.sol";

contract StrategyVault is ERC20, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable asset;
    LiquidityPool public liquidityPool;
    
    uint256 public totalAssets;
    uint256 public lastHarvest;
    uint256 public performanceFee = 1000; // 10% performance fee
    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // 20% max
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    address public strategy;
    address public feeRecipient;
    
    mapping(address => uint256) public lastDepositTime;
    uint256 public lockPeriod = 1 days; // Minimum lock period for deposits
    
    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 assets, uint256 shares);
    event Harvest(uint256 yield, uint256 fee);
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event EmergencyWithdraw(uint256 amount);
    
    modifier onlyStrategy() {
        require(msg.sender == strategy, "Only strategy can call");
        _;
    }
    
    constructor(
        address _asset,
        address _liquidityPool,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_asset != address(0), "Asset cannot be zero address");
        require(_liquidityPool != address(0), "Liquidity pool cannot be zero address");
        
        asset = IERC20(_asset);
        liquidityPool = LiquidityPool(_liquidityPool);
        strategy = msg.sender;
        feeRecipient = msg.sender;
        lastHarvest = block.timestamp;
    }
    
    function deposit(uint256 assets, address receiver) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (uint256 shares) 
    {
        require(assets > 0, "Assets must be positive");
        require(receiver != address(0), "Receiver cannot be zero address");
        
        shares = previewDeposit(assets);
        require(shares > 0, "Shares must be positive");
        
        // Record deposit time for lock period
        lastDepositTime[receiver] = block.timestamp;
        
        // Transfer assets from user
        asset.safeTransferFrom(msg.sender, address(this), assets);
        
        // Update total assets
        totalAssets += assets;
        
        // Mint shares to receiver
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, assets, shares);
    }
    
    function withdraw(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        require(shares > 0, "Shares must be positive");
        require(receiver != address(0), "Receiver cannot be zero address");
        require(
            block.timestamp >= lastDepositTime[owner] + lockPeriod,
            "Withdrawal still locked"
        );
        
        // Check allowance if not owner
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                require(allowed >= shares, "Insufficient allowance");
                _approve(owner, msg.sender, allowed - shares);
            }
        }
        
        assets = previewWithdraw(shares);
        require(assets > 0, "Assets must be positive");
        require(assets <= totalAssets, "Insufficient assets in vault");
        
        // Burn shares
        _burn(owner, shares);
        
        // Update total assets
        totalAssets -= assets;
        
        // Transfer assets to receiver
        asset.safeTransfer(receiver, assets);
        
        emit Withdraw(msg.sender, assets, shares);
    }
    
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets);
    }
    
    function previewWithdraw(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares);
    }
    
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            return assets;
        }
        return (assets * totalSupply_) / totalAssets;
    }
    
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            return shares;
        }
        return (shares * totalAssets) / totalSupply_;
    }
    
    function executeStrategy() external onlyStrategy nonReentrant {
        uint256 availableAssets = asset.balanceOf(address(this));
        require(availableAssets > 0, "No assets to invest");
        
        // Simple strategy: provide liquidity to the pool
        // This is a basic implementation - more complex strategies can be added
        uint256 half = availableAssets / 2;
        
        // Approve tokens for liquidity pool
        asset.forceApprove(address(liquidityPool), half);
        
        // This is a simplified strategy implementation
        // In reality, you would interact with the specific liquidity pool
        // based on the asset type and pool configuration
    }
    
    function harvest() external onlyStrategy nonReentrant {
        uint256 currentBalance = asset.balanceOf(address(this));
        
        // Calculate yield (difference between current balance and recorded total assets)
        if (currentBalance > totalAssets) {
            uint256 yield = currentBalance - totalAssets;
            uint256 fee = (yield * performanceFee) / FEE_DENOMINATOR;
            uint256 netYield = yield - fee;
            
            // Transfer fee to fee recipient
            if (fee > 0) {
                asset.safeTransfer(feeRecipient, fee);
            }
            
            // Update total assets with net yield
            totalAssets += netYield;
            lastHarvest = block.timestamp;
            
            emit Harvest(yield, fee);
        }
    }
    
    function setStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "Strategy cannot be zero address");
        
        address oldStrategy = strategy;
        strategy = _strategy;
        
        emit StrategyUpdated(oldStrategy, _strategy);
    }
    
    function setPerformanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_PERFORMANCE_FEE, "Fee too high");
        
        uint256 oldFee = performanceFee;
        performanceFee = _fee;
        
        emit PerformanceFeeUpdated(oldFee, _fee);
    }
    
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Fee recipient cannot be zero address");
        feeRecipient = _feeRecipient;
    }
    
    function setLockPeriod(uint256 _lockPeriod) external onlyOwner {
        require(_lockPeriod <= 30 days, "Lock period too long");
        lockPeriod = _lockPeriod;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw() external onlyOwner whenPaused {
        uint256 balance = asset.balanceOf(address(this));
        if (balance > 0) {
            asset.safeTransfer(owner(), balance);
            emit EmergencyWithdraw(balance);
        }
    }
    
    function getVaultInfo() external view returns (
        uint256 _totalAssets,
        uint256 _totalShares,
        uint256 _sharePrice,
        uint256 _lastHarvest,
        uint256 _performanceFee
    ) {
        _totalAssets = totalAssets;
        _totalShares = totalSupply();
        _sharePrice = _totalShares > 0 ? (_totalAssets * 1e18) / _totalShares : 1e18;
        _lastHarvest = lastHarvest;
        _performanceFee = performanceFee;
    }
}