// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StrategyVault} from "../src/StrategyVault.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {DQPToken} from "../src/DQPToken.sol";

// Mock ERC20 token for testing
contract MockAsset {
    string public name = "Mock Asset";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(uint256 _totalSupply) {
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    // Helper function to simulate yield generation
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract StrategyVaultTest is Test {
    StrategyVault public vault;
    LiquidityPool public liquidityPool;
    MockAsset public asset;
    MockAsset public tokenB;
    
    address public owner;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public strategy = address(0x3);
    
    uint256 constant INITIAL_SUPPLY = 1000000 * 10**18;
    
    function setUp() public {
        owner = address(this);
        
        // Create mock assets
        asset = new MockAsset(INITIAL_SUPPLY);
        tokenB = new MockAsset(INITIAL_SUPPLY);
        
        // Create liquidity pool
        liquidityPool = new LiquidityPool(
            address(asset),
            address(tokenB),
            "LP Token",
            "LP"
        );
        
        // Create strategy vault
        vault = new StrategyVault(
            address(asset),
            address(liquidityPool),
            "Strategy Vault Token",
            "SVT"
        );
        
        // Distribute assets to users
        asset.transfer(user1, 10000 * 10**18);
        asset.transfer(user2, 10000 * 10**18);
    }
    
    function testVaultInitialization() public {
        assertEq(address(vault.asset()), address(asset));
        assertEq(address(vault.liquidityPool()), address(liquidityPool));
        assertEq(vault.name(), "Strategy Vault Token");
        assertEq(vault.symbol(), "SVT");
        assertEq(vault.owner(), owner);
        assertEq(vault.strategy(), owner);
        assertEq(vault.feeRecipient(), owner);
        assertEq(vault.performanceFee(), 1000); // 10%
    }
    
    function testDeposit() public {
        uint256 depositAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        
        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 shares = vault.deposit(depositAmount, user1);
        
        assertEq(vault.balanceOf(user1), sharesBefore + shares);
        assertEq(vault.totalAssets(), depositAmount);
        assertGt(shares, 0);
        vm.stopPrank();
    }
    
    function testDepositWhenPaused() public {
        vault.pause();
        
        vm.startPrank(user1);
        asset.approve(address(vault), 1000 * 10**18);
        
        vm.expectRevert();
        vault.deposit(1000 * 10**18, user1);
        vm.stopPrank();
    }
    
    function testWithdraw() public {
        uint256 depositAmount = 1000 * 10**18;
        
        // First deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        
        // Advance time to pass lock period
        vm.warp(block.timestamp + 2 days);
        
        // Withdraw
        uint256 assetsBefore = asset.balanceOf(user1);
        uint256 withdrawnAssets = vault.withdraw(shares, user1, user1);
        
        assertEq(asset.balanceOf(user1), assetsBefore + withdrawnAssets);
        assertEq(vault.balanceOf(user1), 0);
        vm.stopPrank();
    }
    
    function testWithdrawBeforeLockPeriod() public {
        uint256 depositAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);
        
        // Try to withdraw immediately (should fail)
        vm.expectRevert("Withdrawal still locked");
        vault.withdraw(shares, user1, user1);
        vm.stopPrank();
    }
    
    function testPreviewFunctions() public {
        uint256 depositAmount = 1000 * 10**18;
        
        // Preview deposit when vault is empty
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        assertEq(expectedShares, depositAmount); // 1:1 ratio when vault is empty
        
        // Make actual deposit
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        uint256 actualShares = vault.deposit(depositAmount, user1);
        
        assertEq(actualShares, expectedShares);
        
        // Preview withdraw
        uint256 expectedAssets = vault.previewWithdraw(actualShares);
        assertEq(expectedAssets, depositAmount);
        vm.stopPrank();
    }
    
    function testHarvest() public {
        uint256 depositAmount = 1000 * 10**18;
        
        // Deposit assets
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Simulate yield by minting more tokens to the vault
        uint256 yield = 100 * 10**18;
        asset.mint(address(vault), yield);
        
        // Harvest
        uint256 feeRecipientBefore = asset.balanceOf(vault.feeRecipient());
        vault.harvest();
        
        // Check that fee was collected (10% of yield)
        uint256 expectedFee = (yield * vault.performanceFee()) / 10000;
        assertEq(asset.balanceOf(vault.feeRecipient()), feeRecipientBefore + expectedFee);
        
        // Check that total assets increased by net yield
        uint256 expectedNetYield = yield - expectedFee;
        assertEq(vault.totalAssets(), depositAmount + expectedNetYield);
    }
    
    function testSetStrategy() public {
        address newStrategy = address(0x999);
        
        vault.setStrategy(newStrategy);
        assertEq(vault.strategy(), newStrategy);
    }
    
    function testSetStrategyOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setStrategy(address(0x999));
    }
    
    function testSetPerformanceFee() public {
        uint256 newFee = 1500; // 15%
        
        vault.setPerformanceFee(newFee);
        assertEq(vault.performanceFee(), newFee);
    }
    
    function testSetPerformanceFeeTooHigh() public {
        uint256 tooHighFee = 2500; // 25%, above max of 20%
        
        vm.expectRevert("Fee too high");
        vault.setPerformanceFee(tooHighFee);
    }
    
    function testSetLockPeriod() public {
        uint256 newLockPeriod = 7 days;
        
        vault.setLockPeriod(newLockPeriod);
        assertEq(vault.lockPeriod(), newLockPeriod);
    }
    
    function testSetLockPeriodTooLong() public {
        uint256 tooLongPeriod = 31 days;
        
        vm.expectRevert("Lock period too long");
        vault.setLockPeriod(tooLongPeriod);
    }
    
    function testPauseUnpause() public {
        assertFalse(vault.paused());
        
        vault.pause();
        assertTrue(vault.paused());
        
        vault.unpause();
        assertFalse(vault.paused());
    }
    
    function testEmergencyWithdraw() public {
        uint256 depositAmount = 1000 * 10**18;
        
        // Deposit assets
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Pause vault and emergency withdraw
        vault.pause();
        
        uint256 ownerBalanceBefore = asset.balanceOf(owner);
        vault.emergencyWithdraw();
        
        // Owner should receive all assets
        assertGt(asset.balanceOf(owner), ownerBalanceBefore);
    }
    
    function testGetVaultInfo() public {
        uint256 depositAmount = 1000 * 10**18;
        
        // Deposit assets
        vm.startPrank(user1);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        (
            uint256 totalAssets,
            uint256 totalShares,
            uint256 sharePrice,
            uint256 lastHarvest,
            uint256 performanceFee
        ) = vault.getVaultInfo();
        
        assertEq(totalAssets, depositAmount);
        assertGt(totalShares, 0);
        assertGt(sharePrice, 0);
        assertEq(lastHarvest, vault.lastHarvest());
        assertEq(performanceFee, vault.performanceFee());
    }
    
    function testZeroAmountValidation() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Assets must be positive");
        vault.deposit(0, user1);
        
        vm.expectRevert("Shares must be positive");
        vault.withdraw(0, user1, user1);
        
        vm.stopPrank();
    }
    
    function testZeroAddressValidation() public {
        vm.expectRevert("Asset cannot be zero address");
        new StrategyVault(address(0), address(liquidityPool), "Test", "TEST");
        
        vm.expectRevert("Liquidity pool cannot be zero address");
        new StrategyVault(address(asset), address(0), "Test", "TEST");
    }
}