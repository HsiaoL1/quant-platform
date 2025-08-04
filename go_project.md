。作为一名Golang后端开发工程师，你需要将 project.md 中 Blockchain
  Infrastructure 的概念，与 smart_contracts/README.md 中的具体实现相结合。

  project.md 中提到的 Blockchain Infrastructure (Rust)
  描述的是一个非常底层的、独立的系统（如自己构建一个区块链节点），这通常是一个庞大
  且专门的工程。而你的核心任务是用Golang构建后端服务，使其能够与已经部署在区块链（
  如以太坊）上的智能合约进行可靠、高效的交互。

  因此，我将为你设计的不是如何用Rust写一个节点，而是如何用Golang实现一个强大的“区块
  链交互层”，作为你整个后端服务与智能合约沟通的桥梁。这个交互层就是你作为Golang开发
  者需要关注的 "Blockchain Infrastructure"。

  我们将完全参考 smart_contracts/README.md
  的分阶段路线图来设计实现步骤，这样你的后端开发可以和合约开发保持同步。

  Golang后端：区块链交互层实现步骤

  关键技术选型

   * 核心库: go-ethereum
     (官方的以太坊Go语言实现，提供了与以太坊节点交互所需的所有工具)。
   * 合约交互: abigen (go-ethereum自带的工具，可以根据合约的ABI生成Go语言的绑定文件，
     让你像调用Go函数一样调用合约)。
   * 配置管理: Viper 或原生库，用于管理RPC节点地址、私钥、合约地址等敏感信息。
   * Web框架: Gin 或 Echo，用于向前端暴露API。

  ---

  阶段零：基础环境搭建 (Foundation)

  在与任何合约交互之前，你需要一个坚实的基础。

   1. 项目结构搭建:
       * 在你的Golang项目中创建一个新的包，例如 pkg/blockchain 或
         internal/blockchain。所有与链交互的代码都将放在这里。
       * 创建 config 模块，用于加载配置文件（如 config.yaml）。

   2. 配置管理:
       * 在 config.yaml 中定义以下字段：
           * rpc_url: 你要连接的以太坊节点RPC地址 (例如 Infura, Alchemy,
             或者你自己的本地节点)。
           * chain_id: 链ID (例如主网是1，Goerli是5)。
           * private_key: 用于发送交易的后端服务私钥（警告：
             绝不能硬编码，要通过环境变量或安全的配置管理工具加载）。
           * contracts: 一个map，用于存放所有已部署合约的地址。

   3. 创建客户端 (Client):
       * 在 blockchain 包中，创建一个 client.go 文件。
       * 实现一个 NewClient() 函数，该函数读取配置，使用 ethclient.Dial(rpc_url)
         初始化一个以太坊客户端实例。这个实例是后续所有操作的基础。

   4. 生成合约的Go绑定:
       * 当智能合约团队编译好合约后，他们会得到合约的ABI（Application Binary
         Interface）和BIN（Binary）文件。
       * 你需要使用 go-ethereum 提供的 abigen 工具，将ABI文件转换为Go代码。例如：

   1         abigen --abi ./DQPToken.abi --pkg contracts --type DQPToken --out
     ./contracts/token.go
       * 这会生成一个 token.go 文件，其中包含了 DQPToken
         合约的所有方法，你可以直接在Go代码中调用。

  ---

  阶段一：平台代币 (DQP Token)

  后端需要支持代币的基本信息查询和事件监控。

   1. 读取数据 (Read-only):
       * 获取代币信息: 实现 GetTokenInfo() 函数，调用 DQPToken Go绑定的 Name(),
         Symbol(), TotalSupply() 等只读方法。
       * 查询用户余额: 实现 GetUserBalance(address string) 函数，调用 BalanceOf()
         方法。
       * API暴露: 创建 GET /token/info 和 GET /users/{address}/balance
         这样的API接口供前端调用。

   2. 监听事件 (Event Listening):
       * 目的: 实时更新你自己的后端数据库（例如，用户的余额、交易记录），而不是每次都
         去链上查询。
       * 实现:
           * 创建一个后台服务（可以是一个独立的goroutine）。
           * 使用 ethclient 的 FilterLogs 和 SubscribeFilterLogs 功能来监听 DQPToken
             合约的 Transfer 事件。
           * 当监听到 Transfer 事件时，解析事件内容（from, to,
             value），并更新你本地数据库中的用户余额表。

  ---

  阶段二：核心功能模块 (预言机 & 流动性池)

   1. 价格预言机 (Price Oracle):
       * 生成绑定: 同样使用 abigen 为 PriceOracle.sol 生成Go绑定。
       * 实现价格查询: 创建一个 GetAssetPrice(pair string) 函数，内部调用预言机合约的
         getLatestPrice() 方法。
       * 缓存: 链上调用有延迟和成本。实现一个缓存层（例如用Redis或内存缓存），将获取
         到的价格缓存几秒钟或几十秒，以提高性能和降低成本。

   2. 流动性池 (Liquidity Pool):
       * 读取数据:
           * 实现 GetPoolReserves(): 获取池子中两种代币的储备量。
           * 实现 CalculateSwapAmount(): 根据输入数量，调用合约的只读方法计算出交易滑
             点和可以兑换的另一个代币数量。
       * 写入数据 (State-changing):
           * 这是核心。你需要实现一个通用的 交易发送器 (Transaction Sender)。
           * 功能: addLiquidity, removeLiquidity, swap。
           * API: 创建 POST /pool/add_liquidity, POST /pool/swap 等API。
           * 后端逻辑:
               1. API接收到用户请求（例如，用户想用1个ETH兑换DQP）。
               2. 后端构建一个调用 swap 方法的交易。使用 go-ethereum 的
                  bind.NewKeyedTransactorWithChainID 创建一个签名器。
               3. 设置Gas价格和Gas Limit（可以使用 ethclient.SuggestGasPrice）。
               4. 使用你的服务私钥对交易进行签名。
               5. 通过 ethclient.SendTransaction 将签名后的交易广播到网络。
               6. 返回交易哈希（TxHash）给前端，前端可以据此追踪交易状态。
       * 监听事件: 监听 Swap, AddLiquidity, RemoveLiquidity
         事件，用于数据分析、计算交易量、更新TVL（总锁仓价值）等。

  ---

  阶段三：核心应用 (策略金库)

   1. 用户交互:
       * API: 创建 POST /vault/deposit 和 POST /vault/withdraw 接口。
       * 逻辑: 与流动性池的逻辑类似，后端接收请求，构建、签名并发送 deposit 或
         withdraw 交易。

   2. 自动化策略执行 (Automated Tasks):
       * Strategy Vault 的 harvest()
         函数需要被定期调用来收取利润。这必须由后端自动完成。
       * 实现:
           * 创建一个独立的后台服务或定时任务（Cron Job）。可以使用 robfig/cron 库。
           * 这个服务会定期（例如每小时）自动调用 harvest() 函数。
           * 这个服务需要使用一个专门的、安全的私钥（"keeper"地址）来发送交易。

   3. 数据分析与追踪:
       * 监听 Deposit 和 Withdraw 事件。
       * 在数据库中记录每个用户的份额、金库的总价值（TVL）、计算并展示APY（年化收益率
         ）。

  ---

  阶段四：去中心化治理 (DAO)

   1. 提案查询:
       * API: GET /proposals, GET /proposals/{id}。
       * 逻辑: 后端需要调用 Governor 合约的各种只读方法来获取提案列表、提案详情、当前
         状态、投票结果等。由于链上存储提案内容成本高，通常提案的详细描述会存在IPFS上
         ，后端需要从合约获取IPFS的哈希，然后去IPFS读取详情。

   2. 投票与提案:
       * API: POST /proposals (创建提案), POST /proposals/{id}/vote (投票)。
       * 逻辑: 同样是构建、签名并发送交易来调用 propose() 和 castVote() 方法。

   3. 事件监控:
       * 监听 ProposalCreated, VoteCast, ProposalExecuted 等事件。
       * 当一个提案被创建或有新的投票时，可以向关注该提案的用户发送通知（邮件、APP推
         送等）。

  总结与建议

  作为Golang开发者，你的任务是：

   1. 抽象化: 将复杂的区块链交互封装成简洁的内部函数。
   2. 服务化: 将这些函数通过API暴露给前端或其他服务。
   3. 自动化: 创建后台任务来处理事件监听和自动化的策略执行。
   4. 数据化: 将链上事件和状态同步到你自己的数据库，用于快速查询和数据分析。
