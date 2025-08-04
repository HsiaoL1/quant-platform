// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityPool} from "../src/LiquidityPool.sol";
import {DQPToken} from "../src/DQPToken.sol";

// Mock ERC20 token for testing
contract MockToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
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
}

contract LiquidityPoolTest is Test {
    LiquidityPool public pool;
    MockToken public tokenA;
    MockToken public tokenB;
    
    address public owner;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    uint256 constant INITIAL_SUPPLY = 1000000 * 10**18;
    
    function setUp() public {
        owner = address(this);
        
        // Create mock tokens
        tokenA = new MockToken("Token A", "TKNA", INITIAL_SUPPLY);
        tokenB = new MockToken("Token B", "TKNB", INITIAL_SUPPLY);
        
        // Create liquidity pool
        pool = new LiquidityPool(
            address(tokenA),
            address(tokenB),
            "LP Token",
            "LP"
        );
        
        // Distribute tokens to users
        tokenA.transfer(user1, 100000 * 10**18);
        tokenA.transfer(user2, 100000 * 10**18);
        tokenB.transfer(user1, 100000 * 10**18);
        tokenB.transfer(user2, 100000 * 10**18);
    }
    
    function testPoolInitialization() public {
        assertEq(address(pool.tokenA()), address(tokenA));
        assertEq(address(pool.tokenB()), address(tokenB));
        assertEq(pool.name(), "LP Token");
        assertEq(pool.symbol(), "LP");
        assertEq(pool.owner(), owner);
    }
    
    function testConstructorValidation() public {
        // Test zero address validation
        vm.expectRevert("Token A cannot be zero address");
        new LiquidityPool(address(0), address(tokenB), "LP", "LP");
        
        vm.expectRevert("Token B cannot be zero address");
        new LiquidityPool(address(tokenA), address(0), "LP", "LP");
        
        // Test same token validation
        vm.expectRevert("Tokens must be different");
        new LiquidityPool(address(tokenA), address(tokenA), "LP", "LP");
    }
    
    function testFirstLiquidityProvision() public {
        uint256 amountA = 1000 * 10**18;
        uint256 amountB = 2000 * 10**18;
        
        // Approve tokens
        tokenA.approve(address(pool), amountA);
        tokenB.approve(address(pool), amountB);
        
        uint256 liquidity = pool.addLiquidity(
            amountA,
            amountB,
            amountA,
            amountB,
            owner
        );
        
        // Check LP token balance (sqrt(1000 * 2000) - 1000 = sqrt(2000000) - 1000 ≈ 414)
        assertGt(liquidity, 0);
        assertEq(pool.balanceOf(owner), liquidity);
        
        // Check reserves
        (uint256 reserveA, uint256 reserveB,) = pool.getReserves();
        assertEq(reserveA, amountA);
        assertEq(reserveB, amountB);
    }
    
    function testSubsequentLiquidityProvision() public {
        // First provision
        uint256 amountA1 = 1000 * 10**18;
        uint256 amountB1 = 2000 * 10**18;
        
        tokenA.approve(address(pool), amountA1);
        tokenB.approve(address(pool), amountB1);
        
        pool.addLiquidity(amountA1, amountB1, amountA1, amountB1, owner);
        
        // Second provision by user1
        vm.startPrank(user1);
        uint256 amountA2 = 500 * 10**18;
        uint256 amountB2 = 1000 * 10**18;
        
        tokenA.approve(address(pool), amountA2);
        tokenB.approve(address(pool), amountB2);
        
        uint256 liquidity2 = pool.addLiquidity(
            amountA2,
            amountB2,
            amountA2,
            amountB2,
            user1
        );
        
        assertGt(liquidity2, 0);
        assertEq(pool.balanceOf(user1), liquidity2);
        vm.stopPrank();
    }
    
    function testRemoveLiquidity() public {
        // Add liquidity first
        uint256 amountA = 1000 * 10**18;
        uint256 amountB = 2000 * 10**18;
        
        tokenA.approve(address(pool), amountA);
        tokenB.approve(address(pool), amountB);
        
        uint256 liquidity = pool.addLiquidity(
            amountA,
            amountB,
            amountA,
            amountB,
            owner
        );
        
        // Remove half of the liquidity
        uint256 liquidityToRemove = liquidity / 2;
        
        (uint256 amountAOut, uint256 amountBOut) = pool.removeLiquidity(
            liquidityToRemove,
            0,
            0,
            owner
        );
        
        assertGt(amountAOut, 0);
        assertGt(amountBOut, 0);
        assertEq(pool.balanceOf(owner), liquidity - liquidityToRemove);
    }
    
    function testSwapAForB() public {
        // Add liquidity first
        uint256 amountA = 1000 * 10**18;
        uint256 amountB = 2000 * 10**18;
        
        tokenA.approve(address(pool), amountA);
        tokenB.approve(address(pool), amountB);
        pool.addLiquidity(amountA, amountB, amountA, amountB, owner);
        
        // Perform swap
        vm.startPrank(user1);
        uint256 swapAmountIn = 100 * 10**18;
        
        uint256 expectedOut = pool.getAmountOut(swapAmountIn, amountA, amountB);
        
        tokenA.approve(address(pool), swapAmountIn);
        uint256 amountOut = pool.swapAForB(swapAmountIn, 0, user1);
        
        assertEq(amountOut, expectedOut);
        assertGt(amountOut, 0);
        vm.stopPrank();
    }
    
    function testSwapBForA() public {
        // Add liquidity first
        uint256 amountA = 1000 * 10**18;
        uint256 amountB = 2000 * 10**18;
        
        tokenA.approve(address(pool), amountA);
        tokenB.approve(address(pool), amountB);
        pool.addLiquidity(amountA, amountB, amountA, amountB, owner);
        
        // Perform swap
        vm.startPrank(user1);
        uint256 swapAmountIn = 200 * 10**18;
        
        uint256 expectedOut = pool.getAmountOut(swapAmountIn, amountB, amountA);
        
        tokenB.approve(address(pool), swapAmountIn);
        uint256 amountOut = pool.swapBForA(swapAmountIn, 0, user1);
        
        assertEq(amountOut, expectedOut);
        assertGt(amountOut, 0);
        vm.stopPrank();
    }
    
    function testGetAmountOut() public {
        uint256 amountIn = 100 * 10**18;
        uint256 reserveIn = 1000 * 10**18;
        uint256 reserveOut = 2000 * 10**18;
        
        uint256 amountOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        
        // Calculate expected: (100 * 997 * 2000) / (1000 * 1000 + 100 * 997)
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        uint256 expected = numerator / denominator;
        
        assertEq(amountOut, expected);
    }
    
    function testGetAmountIn() public {
        uint256 amountOut = 100 * 10**18;
        uint256 reserveIn = 1000 * 10**18;
        uint256 reserveOut = 2000 * 10**18;
        
        uint256 amountIn = pool.getAmountIn(amountOut, reserveIn, reserveOut);
        
        assertGt(amountIn, 0);
        
        // Verify by checking if this amount in gives approximately the desired amount out
        uint256 calculatedOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);
        
        // Should be close (within 1 unit due to rounding)
        assertGe(calculatedOut, amountOut);
        assertLe(calculatedOut, amountOut + 1);
    }
    
    function testSlippageProtection() public {
        // Add liquidity first
        uint256 amountA = 1000 * 10**18;
        uint256 amountB = 2000 * 10**18;
        
        tokenA.approve(address(pool), amountA);
        tokenB.approve(address(pool), amountB);
        pool.addLiquidity(amountA, amountB, amountA, amountB, owner);
        
        // Try swap with insufficient output
        vm.startPrank(user1);
        uint256 swapAmountIn = 100 * 10**18;
        uint256 expectedOut = pool.getAmountOut(swapAmountIn, amountA, amountB);
        
        tokenA.approve(address(pool), swapAmountIn);
        
        // This should revert due to slippage protection
        vm.expectRevert("Insufficient output amount");
        pool.swapAForB(swapAmountIn, expectedOut + 1, user1);
        vm.stopPrank();
    }
    
    function testInsufficientLiquidity() public {
        vm.expectRevert("Insufficient liquidity");
        pool.getAmountOut(100, 0, 1000);
        
        vm.expectRevert("Insufficient liquidity");
        pool.getAmountOut(100, 1000, 0);
    }
    
    function testZeroAmountValidation() public {
        vm.expectRevert("Amount in must be positive");
        pool.getAmountOut(0, 1000, 2000);
        
        vm.expectRevert("Amount out must be positive");
        pool.getAmountIn(0, 1000, 2000);
    }
}