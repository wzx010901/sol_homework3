# NFT 拍卖市场项目

## 项目简介

这是一个基于 Hardhat 框架开发的 NFT 拍卖市场，支持以下功能：

- NFT 合约：使用 ERC721 标准实现，支持铸造和转移
- 拍卖合约：支持创建拍卖、出价（ERC20 或以太坊）、结束拍卖
- Chainlink 预言机：获取 ERC20 和以太坊到美元的价格
- 合约升级：使用 UUPS 代理模式实现

## 项目结构

```
├── contracts/
│   ├── NFT.sol                # NFT 合约
│   ├── PriceOracle.sol        # 价格预言机合约
│   ├── NFTAuction.sol         # 拍卖合约
│   └── mocks/                 # 测试用模拟合约
│       ├── MockV3Aggregator.sol  # 模拟价格预言机
│       └── MockERC20.sol         # 模拟 ERC20 代币
├── ignition/
│   └── modules/
│       └── NFTAuctionDeployment.ts  # 部署脚本
├── test/
│   ├── NFT.test.ts            # NFT 合约测试
│   ├── PriceOracle.test.ts    # 价格预言机测试
│   └── NFTAuction.test.ts     # 拍卖合约测试
├── hardhat.config.ts          # Hardhat 配置
├── package.json               # 项目依赖
└── .env                       # 环境变量
```

## 功能说明

### NFT 合约
- 实现 ERC721 标准
- 支持铸造 NFT
- 支持转移 NFT

### 价格预言机
- 集成 Chainlink 价格预言机
- 获取 ETH 到 USD 的价格
- 获取 ERC20 代币到 USD 的价格
- 提供价格转换功能)

### 拍卖合约
- 创建拍卖：将 NFT 上架拍卖
- 出价：支持 ERC20 或以太坊出价
- 结束拍卖：NFT 转移给出价最高者，资金转移给卖家
- 平台手续费：可配置的平台手续费
- 可暂停：紧急情况下可暂停合约
- 可升级：使用 UUPS 代理模式实现合约升级

## 部署步骤

### 1. 环境准备

```bash
# 安装依赖
npm install

# 配置环境变量
# 编辑 .env 文件，设置以下变量：
# SEPOLIA_RPC_URL - Sepolia 测试网 RPC URL
# SEPOLIA_PRIVATE_KEY - 部署账户私钥
# ETHERSCAN_API_KEY - Etherscan API 密钥
```

### 2. 编译合约

```bash
npx hardhat compile
```

### 3. 运行测试

```bash
npx hardhat test
```

### 4. 部署到 Sepolia 测试网

```bash
npx hardhat ignition deploy ./ignition/modules/NFTAuctionDeployment.ts --network sepolia
```

### delegatecall 跟 call 的区别是什么

### call 函数
- 执行环境 ：在被调用合约的上下文中执行，使用被调用合约的存储。
- msg.sender ：在被调用合约中， msg.sender 是调用合约的地址。
- 适用场景 ：常规的合约间调用，例如调用其他合约的函数来完成特定任务。
###  delegatecall 函数
- 执行环境 ：在调用合约的上下文中执行，使用调用合约的存储。
- msg.sender ：在执行被调用合约的代码时， msg.sender 保持为原始调用者的地址（不是调用合约的地址）。
- 适用场景 ：代理模式（Proxy Pattern），例如可升级合约、库函数调用等。

call 修改被调用合约的状态，而 delegatecall 修改调用合约的状态。

### 销毁合约 销毁合约并将剩余ETH发送到指定地址
function destroy(address payable recipient) external onlyOwner {
    selfdestruct(recipient);
}

### 升级合约的执行流程是什么（user -> proxy -> implementation）
用户调用代理合约，代理合约通过 delegatecall 转发调用到当前实现合约执行逻辑并返回结果；升级时，管理员更新代理合约中存储的实现合约地址，后续调用将转发到新的实现合约，同时保持存储状态的连续性。

### 代理合约上本身是有存储的，怎么避免跟逻辑合约上的存储产生冲突
代理合约通过使用固定的存储槽（如EIP-1967定义的槽位）存储自身必要数据（如实现合约地址），逻辑合约则从不同的存储槽位开始定义状态变量，从而避免存储布局重叠导致的冲突。

### 逻辑合约升级的存储冲突问题
逻辑合约升级时，由于代理模式下代理与逻辑合约共享存储，若逻辑合约的存储布局（如状态变量的顺序、类型）发生变更，会导致存储位置重叠，从而引发数据错乱或功能异常的问题。

### 可以在逻辑合约的构造函数中初始化变量吗？为什么
不可以，因为逻辑合约的构造函数只在其自身部署时执行，而代理合约通过delegatecall调用逻辑合约时不会触发构造函数，导致初始化无法应用到代理合约的存储中。