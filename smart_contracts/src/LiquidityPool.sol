// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityPool is ERC20, ReentrancyGuard, Ownable {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;
    
    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public lastUpdated;
    
    uint256 public constant FEE_RATE = 3; // 0.3% fee
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 private constant MINIMUM_LIQUIDITY = 10**3;
    
    event AddLiquidity(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event RemoveLiquidity(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );
    
    event Swap(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    modifier updateReserves() {
        _;
        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
        lastUpdated = block.timestamp;
    }
    
    constructor(
        address _tokenA,
        address _tokenB,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_tokenA != address(0), "Token A cannot be zero address");
        require(_tokenB != address(0), "Token B cannot be zero address");
        require(_tokenA != _tokenB, "Tokens must be different");
        
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }
    
    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) external nonReentrant updateReserves returns (uint256 liquidity) {
        require(amountADesired > 0 && amountBDesired > 0, "Amounts must be positive");
        require(to != address(0), "Recipient cannot be zero address");
        
        uint256 amountA;
        uint256 amountB;
        
        if (reserveA == 0 && reserveB == 0) {
            // First liquidity provision
            amountA = amountADesired;
            amountB = amountBDesired;
            liquidity = sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            // Permanently lock MINIMUM_LIQUIDITY tokens by minting to address(1)
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            // Calculate optimal amounts
            uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Insufficient B amount");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
                require(amountAOptimal <= amountADesired && amountAOptimal >= amountAMin, "Insufficient A amount");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
            
            // Calculate liquidity tokens to mint
            uint256 liquidityA = (amountA * totalSupply()) / reserveA;
            uint256 liquidityB = (amountB * totalSupply()) / reserveB;
            liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
        }
        
        require(liquidity > 0, "Liquidity amount too small");
        
        // Transfer tokens
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        
        // Mint LP tokens
        _mint(to, liquidity);
        
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }
    
    function removeLiquidity(
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) external nonReentrant updateReserves returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "Liquidity must be positive");
        require(to != address(0), "Recipient cannot be zero address");
        require(balanceOf(msg.sender) >= liquidity, "Insufficient liquidity balance");
        
        uint256 totalLiquidity = totalSupply();
        
        // Calculate token amounts to return
        amountA = (liquidity * reserveA) / totalLiquidity;
        amountB = (liquidity * reserveB) / totalLiquidity;
        
        require(amountA >= amountAMin, "Insufficient A amount");
        require(amountB >= amountBMin, "Insufficient B amount");
        
        // Burn LP tokens
        _burn(msg.sender, liquidity);
        
        // Transfer tokens back
        tokenA.transfer(to, amountA);
        tokenB.transfer(to, amountB);
        
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }
    
    function swapAForB(
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external nonReentrant updateReserves returns (uint256 amountOut) {
        require(amountIn > 0, "Amount in must be positive");
        require(to != address(0), "Recipient cannot be zero address");
        
        amountOut = getAmountOut(amountIn, reserveA, reserveB);
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        // Transfer token in
        tokenA.transferFrom(msg.sender, address(this), amountIn);
        
        // Transfer token out
        tokenB.transfer(to, amountOut);
        
        emit Swap(msg.sender, address(tokenA), address(tokenB), amountIn, amountOut);
    }
    
    function swapBForA(
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external nonReentrant updateReserves returns (uint256 amountOut) {
        require(amountIn > 0, "Amount in must be positive");
        require(to != address(0), "Recipient cannot be zero address");
        
        amountOut = getAmountOut(amountIn, reserveB, reserveA);
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        // Transfer token in
        tokenB.transferFrom(msg.sender, address(this), amountIn);
        
        // Transfer token out
        tokenA.transfer(to, amountOut);
        
        emit Swap(msg.sender, address(tokenB), address(tokenA), amountIn, amountOut);
    }
    
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Amount in must be positive");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        // Apply 0.3% fee
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_RATE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        
        amountOut = numerator / denominator;
    }
    
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountIn) {
        require(amountOut > 0, "Amount out must be positive");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        require(amountOut < reserveOut, "Amount out exceeds reserve");
        
        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * (FEE_DENOMINATOR - FEE_RATE);
        
        amountIn = (numerator / denominator) + 1;
    }
    
    function getReserves() external view returns (uint256, uint256, uint256) {
        return (reserveA, reserveB, lastUpdated);
    }
    
    function sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}