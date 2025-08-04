# DeFi 智能合约开发框架指南

本指南详细介绍如何使用 Foundry 框架从零开始构建一个完整的 DeFi 智能合约系统。

## 目录

1. [项目架构概览](#项目架构概览)
2. [Foundry 项目初始化](#foundry-项目初始化)
3. [合约开发基础模块](#合约开发基础模块)
4. [核心合约实现](#核心合约实现)
5. [安全最佳实践](#安全最佳实践)
6. [测试策略](#测试策略)
7. [部署和验证](#部署和验证)

## 项目架构概览

基于现有项目分析，一个典型的 DeFi 项目包含以下核心组件：

```
src/
├── governance/           # 治理相关合约
│   ├── DQPToken.sol     # 治理代币（ERC20 + Votes）
│   ├── DQPGovernor.sol  # 治理合约
│   └── DQPTimelock.sol  # 时间锁合约
├── core/                # 核心 DeFi 功能
│   ├── LiquidityPool.sol # AMM 流动性池
│   ├── StrategyVault.sol # 收益策略金库
│   └── PriceOracle.sol  # 价格预言机
└── interfaces/          # 接口定义
    ├── ILiquidityPool.sol
    ├── IStrategyVault.sol
    └── IPriceOracle.sol
```

## Foundry 项目初始化

### 1. 安装 Foundry

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 验证安装
forge --version
cast --version
anvil --version
```

### 2. 创建新项目

```bash
# 初始化新项目
forge init my-defi-project
cd my-defi-project

# 项目结构
# ├── foundry.toml      # Foundry 配置文件
# ├── src/              # 合约源码
# ├── test/             # 测试文件
# ├── script/           # 部署脚本
# └── lib/              # 依赖库
```

### 3. 配置 foundry.toml

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.19"
optimizer = true
optimizer_runs = 200
gas_reports = ["*"]
auto_detect_solc = false

[profile.default.fuzz]
runs = 1000

[profile.default.invariant]
runs = 256
depth = 15
fail_on_revert = false

[rpc_endpoints]
mainnet = "${MAINNET_RPC_URL}"
goerli = "${GOERLI_RPC_URL}"
sepolia = "${SEPOLIA_RPC_URL}"

[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }
goerli = { key = "${ETHERSCAN_API_KEY}" }
sepolia = { key = "${ETHERSCAN_API_KEY}" }
```

### 4. 安装依赖

```bash
# 安装 OpenZeppelin 合约库
forge install OpenZeppelin/openzeppelin-contracts

# 安装 Forge Standard Library（测试工具）
forge install foundry-rs/forge-std

# 更新 remappings.txt
echo "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/" > remappings.txt
echo "forge-std/=lib/forge-std/src/" >> remappings.txt
```

## 合约开发基础模块

### 1. 治理代币合约

治理代币是 DeFi 项目的核心，结合了 ERC20 功能和治理投票能力：

```solidity
// src/governance/DQPToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DQPToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // 代币分配常量
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * 10**18;     // 20%
    uint256 public constant COMMUNITY_ALLOCATION = 400_000_000 * 10**18; // 40%
    uint256 public constant ECOSYSTEM_ALLOCATION = 300_000_000 * 10**18; // 30%
    uint256 public constant TREASURY_ALLOCATION = 100_000_000 * 10**18;  // 10%
    
    constructor(
        address teamWallet,
        address communityWallet,
        address ecosystemWallet,
        address treasuryWallet
    ) 
        ERC20("DeFi Quant Platform Token", "DQP") 
        ERC20Permit("DeFi Quant Platform Token") 
        Ownable(msg.sender) 
    {
        // 分发代币到各个钱包
        _mint(teamWallet, TEAM_ALLOCATION);
        _mint(communityWallet, COMMUNITY_ALLOCATION);
        _mint(ecosystemWallet, ECOSYSTEM_ALLOCATION);
        _mint(treasuryWallet, TREASURY_ALLOCATION);
    }
    
    // 重写必要的函数以解决继承冲突
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
```

### 2. AMM 流动性池合约

实现基于常数乘积公式的自动做市商：

```solidity
// src/core/LiquidityPool.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
    
    uint256 public constant FEE_RATE = 3; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 private constant MINIMUM_LIQUIDITY = 10**3;
    
    // 事件定义
    event AddLiquidity(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    event RemoveLiquidity(address indexed provider, uint256 amountA, uint256 amountB, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    
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
        require(_tokenA != _tokenB, "Tokens must be different");
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }
    
    // 核心功能实现...
    // [详细实现参考现有代码]
}
```

### 3. 收益策略金库

实现自动化收益策略管理：

```solidity
// src/core/StrategyVault.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract StrategyVault is ERC20, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable asset;
    address public strategy;
    address public feeRecipient;
    
    uint256 public totalAssets;
    uint256 public performanceFee = 1000; // 10%
    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // 20%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    mapping(address => uint256) public lastDepositTime;
    uint256 public lockPeriod = 1 days;
    
    // 事件和修饰符...
    // [详细实现参考现有代码]
}
```

## 核心合约实现

### 步骤 1：设计合约接口

首先定义清晰的接口，确保模块化和可扩展性：

```solidity
// src/interfaces/ILiquidityPool.sol
interface ILiquidityPool {
    function addLiquidity(uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to) external returns (uint256 liquidity);
    function removeLiquidity(uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to) external returns (uint256 amountA, uint256 amountB);
    function swapAForB(uint256 amountIn, uint256 amountOutMin, address to) external returns (uint256 amountOut);
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut);
    function getReserves() external view returns (uint256, uint256, uint256);
}
```

### 步骤 2：实现核心逻辑

按照以下顺序实现核心功能：

1. **基础 ERC20 代币**
2. **流动性池（AMM）**
3. **收益策略金库**
4. **价格预言机**
5. **治理系统**

### 步骤 3：集成外部依赖

```solidity
// 使用 Chainlink 价格预言机
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    AggregatorV3Interface internal priceFeed;
    
    constructor(address _priceFeed) {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }
    
    function getLatestPrice() public view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }
}
```

## 安全最佳实践

### 1. 重入攻击防护

```solidity
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SecureContract is ReentrancyGuard {
    function withdraw() external nonReentrant {
        // 安全的提取逻辑
    }
}
```

### 2. 整数溢出防护

```solidity
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// 或使用 Solidity 0.8+ 内置溢出检查
```

### 3. 访问控制

```solidity
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract GovernedContract is Ownable, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }
}
```

### 4. 紧急暂停机制

```solidity
import "@openzeppelin/contracts/utils/Pausable.sol";

contract EmergencyPausable is Pausable, Ownable {
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}
```

## 测试策略

### 1. 单元测试结构

```solidity
// test/DQPToken.t.sol
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/governance/DQPToken.sol";

contract DQPTokenTest is Test {
    DQPToken public token;
    address public owner = address(1);
    address public team = address(2);
    address public community = address(3);
    
    function setUp() public {
        vm.prank(owner);
        token = new DQPToken(team, community, address(4), address(5));
    }
    
    function testInitialSupply() public {
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }
    
    function testTeamAllocation() public {
        assertEq(token.balanceOf(team), token.TEAM_ALLOCATION());
    }
    
    function testFuzzTransfer(uint256 amount) public {
        vm.assume(amount <= token.balanceOf(team));
        vm.prank(team);
        token.transfer(community, amount);
        assertEq(token.balanceOf(community), token.COMMUNITY_ALLOCATION() + amount);
    }
}
```

### 2. 集成测试

```solidity
// test/integration/LiquidityPoolIntegration.t.sol
contract LiquidityPoolIntegrationTest is Test {
    LiquidityPool public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    
    function testAddLiquidityAndSwap() public {
        // 测试添加流动性
        // 测试交换
        // 验证价格影响
        // 检查手续费收取
    }
}
```

### 3. 模糊测试

```solidity
function testFuzzLiquidityOperations(
    uint256 amountA,
    uint256 amountB,
    uint256 swapAmount
) public {
    // 设置假设条件
    vm.assume(amountA > 1000 && amountA < 1e30);
    vm.assume(amountB > 1000 && amountB < 1e30);
    
    // 执行模糊测试
}
```

### 4. 不变量测试

```solidity
// test/invariant/LiquidityPoolInvariant.t.sol
contract LiquidityPoolInvariantTest is Test {
    LiquidityPool public pool;
    
    function invariant_reserveProductNeverDecreases() public {
        uint256 currentProduct = pool.reserveA() * pool.reserveB();
        // 验证恒定乘积不变量
    }
}
```

## 部署和验证

### 1. 部署脚本

```solidity
// script/Deploy.s.sol
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/governance/DQPToken.sol";
import "../src/core/LiquidityPool.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署治理代币
        DQPToken token = new DQPToken(
            vm.envAddress("TEAM_WALLET"),
            vm.envAddress("COMMUNITY_WALLET"),
            vm.envAddress("ECOSYSTEM_WALLET"),
            vm.envAddress("TREASURY_WALLET")
        );
        
        // 部署流动性池
        LiquidityPool pool = new LiquidityPool(
            address(token),
            vm.envAddress("USDC_TOKEN"),
            "DQP-USDC LP",
            "DQP-USDC"
        );
        
        vm.stopBroadcast();
        
        console.log("DQP Token deployed to:", address(token));
        console.log("Liquidity Pool deployed to:", address(pool));
    }
}
```

### 2. 环境配置

```bash
# .env
PRIVATE_KEY=your_private_key
MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/your-api-key
ETHERSCAN_API_KEY=your_etherscan_api_key
TEAM_WALLET=0x...
COMMUNITY_WALLET=0x...
ECOSYSTEM_WALLET=0x...
TREASURY_WALLET=0x...
USDC_TOKEN=0xA0b86a33E6411E8Ee3B636Fb18f7a7e4b3b5feFf
```

### 3. 部署命令

```bash
# 编译合约
forge build

# 运行测试
forge test

# 测试覆盖率
forge coverage

# 部署到测试网
forge script script/Deploy.s.sol:DeployScript --rpc-url $GOERLI_RPC_URL --broadcast --verify

# 部署到主网
forge script script/Deploy.s.sol:DeployScript --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

### 4. 合约验证

```bash
# 自动验证（部署时）
forge create src/DQPToken.sol:DQPToken --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY --verify

# 手动验证
forge verify-contract 0x... src/DQPToken.sol:DQPToken --etherscan-api-key $ETHERSCAN_API_KEY --chain goerli
```

## 常用命令总结

```bash
# 项目初始化
forge init
forge install

# 开发流程
forge build                 # 编译
forge test                  # 测试
forge coverage              # 覆盖率
forge fmt                   # 格式化代码

# 部署验证
forge script               # 运行脚本
forge create               # 部署合约
forge verify-contract      # 验证合约

# 实用工具
cast call                  # 调用合约
cast send                  # 发送交易
cast balance               # 查看余额
anvil                      # 本地测试网
```

## 总结

这个框架提供了构建 DeFi 项目的完整指南，包括：

1. **模块化架构** - 清晰的代码组织结构
2. **安全最佳实践** - 防护常见攻击向量
3. **全面测试策略** - 单元测试、集成测试、模糊测试
4. **自动化部署** - 脚本化部署和验证流程

通过遵循这个指南，你可以构建安全、可扩展、可维护的 DeFi 智能合约系统。