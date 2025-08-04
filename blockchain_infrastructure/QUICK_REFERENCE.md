# Rust区块链开发快速参考手册

## 🚀 快速启动命令

```bash
# 编译项目
cargo build --release

# 启动开发节点
./target/release/defi-blockchain-node --dev --tmp

# 运行测试
cargo test

# 检查代码
cargo check

# 格式化代码
cargo fmt

# 更新依赖
cargo update
```

## 📦 常用Pallet模板

### 基础Pallet结构
```rust
#![cfg_attr(not(feature = "std"), no_std)]

use frame_support::{
    dispatch::DispatchResult,
    pallet_prelude::*,
};
use frame_system::pallet_prelude::*;

pub use pallet::*;

#[frame_support::pallet]
pub mod pallet {
    use super::*;

    #[pallet::pallet]
    pub struct Pallet<T>(_);

    #[pallet::config]
    pub trait Config: frame_system::Config {
        type RuntimeEvent: From<Event<Self>> + IsType<<Self as frame_system::Config>::RuntimeEvent>;
    }

    #[pallet::storage]
    pub type Something<T> = StorageValue<_, u32>;

    #[pallet::event]
    #[pallet::generate_deposit(pub(super) fn deposit_event)]
    pub enum Event<T: Config> {
        SomethingHappened { value: u32 },
    }

    #[pallet::error]
    pub enum Error<T> {
        NoneValue,
        StorageOverflow,
    }

    #[pallet::call]
    impl<T: Config> Pallet<T> {
        #[pallet::call_index(0)]
        #[pallet::weight(10_000)]
        pub fn do_something(origin: OriginFor<T>, value: u32) -> DispatchResult {
            let _who = ensure_signed(origin)?;
            Something::<T>::put(value);
            Self::deposit_event(Event::SomethingHappened { value });
            Ok(())
        }
    }
}
```

### 存储类型模板

#### 单值存储
```rust
#[pallet::storage]
pub type SingleValue<T> = StorageValue<_, u32, ValueQuery>;
```

#### 映射存储
```rust
#[pallet::storage]
pub type SimpleMap<T: Config> = StorageMap<
    _,
    Blake2_128Concat,
    T::AccountId,
    u32,
    ValueQuery,
>;
```

#### 双键映射
```rust
#[pallet::storage]
pub type DoubleMap<T: Config> = StorageDoubleMap<
    _,
    Blake2_128Concat, T::AccountId,
    Blake2_128Concat, u32,
    u32,
    ValueQuery,
>;
```

#### 有界向量
```rust
use frame_support::BoundedVec;

#[pallet::storage]
pub type BoundedList<T: Config> = StorageMap<
    _,
    Blake2_128Concat,
    T::AccountId,
    BoundedVec<u32, T::MaxListSize>,
    ValueQuery,
>;
```

## 🎯 常用配置模板

### Runtime集成模板
```rust
// runtime/src/lib.rs

// 1. 添加到Config实现
impl pallet_your_pallet::Config for Runtime {
    type RuntimeEvent = RuntimeEvent;
    type MaxItems = ConstU32<100>;
}

// 2. 添加到construct_runtime!
construct_runtime!(
    pub struct Runtime {
        // 现有pallet...
        YourPallet: pallet_your_pallet,
    }
);

// 3. 添加到基准测试（如果需要）
#[cfg(feature = "runtime-benchmarks")]
mod benches {
    define_benchmarks!(
        // 现有基准...
        [pallet_your_pallet, YourPallet]
    );
}
```

### Cargo.toml模板
```toml
# pallets/your-pallet/Cargo.toml
[package]
name = "pallet-your-pallet"
version = "1.0.0"
edition = "2021"

[dependencies]
codec = { package = "parity-scale-codec", version = "3.6.1", default-features = false, features = ["derive"] }
scale-info = { version = "2.5.0", default-features = false, features = ["derive"] }
frame-benchmarking = { version = "28.0.0", default-features = false, optional = true }
frame-support = { version = "28.0.0", default-features = false }
frame-system = { version = "28.0.0", default-features = false }
sp-std = { version = "14.0.0", default-features = false }

[features]
default = ["std"]
std = [
	"codec/std",
	"frame-benchmarking?/std",
	"frame-support/std",
	"frame-system/std",
	"scale-info/std",
	"sp-std/std",
]
runtime-benchmarks = [
	"frame-benchmarking/runtime-benchmarks",
]
try-runtime = [
	"frame-support/try-runtime",
	"frame-system/try-runtime",
]
```

## 🔧 调试工具

### 日志宏
```rust
// 导入日志宏
use log::{info, warn, error, debug};

// 在函数中使用
info!("Processing transaction: {:?}", tx_hash);
warn!("Storage nearly full: {}/{}", current, max);
error!("Validation failed: {:?}", error);
debug!("Internal state: {:?}", state);
```

### 断言宏
```rust
// 确保条件满足
ensure!(condition, Error::<T>::ConditionNotMet);

// 确保签名用户
let who = ensure_signed(origin)?;

// 确保root权限
ensure_root(origin)?;

// 条件断言
assert!(condition, "Error message");
assert_eq!(a, b, "Values should be equal");
```

### 测试模板
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use frame_support::{
        assert_ok, assert_noop,
        traits::{Get, OnFinalize, OnInitialize},
    };

    #[test]
    fn basic_test_works() {
        new_test_ext().execute_with(|| {
            // 测试逻辑
            assert_ok!(YourPallet::do_something(RuntimeOrigin::signed(1), 42));
            assert_eq!(YourPallet::something(), Some(42));
        });
    }

    #[test]
    fn error_test_works() {
        new_test_ext().execute_with(|| {
            assert_noop!(
                YourPallet::fail_function(RuntimeOrigin::signed(1)),
                Error::<Test>::SomeError
            );
        });
    }
}
```

## 🌐 RPC和API

### 自定义RPC模板
```rust
// rpc/src/lib.rs
use jsonrpsee::{
    core::{Error as JsonRpseeError, RpcResult},
    proc_macros::rpc,
    types::error::{CallError, ErrorCode, ErrorObject},
};
use sp_api::ProvideRuntimeApi;
use sp_blockchain::HeaderBackend;
use sp_runtime::traits::Block as BlockT;
use std::sync::Arc;

#[rpc(client, server)]
pub trait YourPalletApi<BlockHash> {
    #[method(name = "yourPallet_getData")]
    fn get_data(&self, at: Option<BlockHash>) -> RpcResult<u32>;
}

pub struct YourPalletRpc<C, Block> {
    client: Arc<C>,
    _marker: std::marker::PhantomData<Block>,
}

impl<C, Block> YourPalletRpc<C, Block> {
    pub fn new(client: Arc<C>) -> Self {
        Self {
            client,
            _marker: Default::default(),
        }
    }
}

impl<C, Block> YourPalletApiServer<<Block as BlockT>::Hash> for YourPalletRpc<C, Block>
where
    Block: BlockT,
    C: Send + Sync + 'static + ProvideRuntimeApi<Block> + HeaderBackend<Block>,
{
    fn get_data(&self, at: Option<<Block as BlockT>::Hash>) -> RpcResult<u32> {
        let api = self.client.runtime_api();
        let at = at.unwrap_or_else(|| self.client.info().best_hash);
        
        api.get_data(at).map_err(|e| {
            JsonRpseeError::Call(CallError::Custom(ErrorObject::owned(
                ErrorCode::InternalError.code(),
                "Unable to get data",
                Some(e.to_string()),
            )))
        })
    }
}
```

### Runtime API模板
```rust
// runtime/src/lib.rs - 在impl_runtime_apis!中添加

impl your_pallet_rpc_runtime_api::YourPalletApi<Block> for Runtime {
    fn get_data() -> u32 {
        YourPallet::get_data()
    }
}
```

## 💾 数据库操作

### 存储操作
```rust
// 插入/更新
Storage::<T>::insert(&key, &value);

// 获取
let value = Storage::<T>::get(&key);

// 删除
Storage::<T>::remove(&key);

// 检查存在
let exists = Storage::<T>::contains_key(&key);

// 获取所有键值对
let all_items: Vec<(Key, Value)> = Storage::<T>::iter().collect();

// 带前缀的迭代
let items_with_prefix: Vec<(Key, Value)> = Storage::<T>::iter_prefix(&prefix).collect();
```

### 交易操作
```rust
// 批量操作
#[pallet::call]
impl<T: Config> Pallet<T> {
    #[pallet::weight(items.len() as u64 * 10_000)]
    pub fn batch_operation(
        origin: OriginFor<T>,
        items: Vec<(T::AccountId, u32)>,
    ) -> DispatchResult {
        let _who = ensure_signed(origin)?;
        
        for (account, value) in items {
            Storage::<T>::insert(&account, value);
        }
        
        Ok(())
    }
}
```

## 🔐 权限控制

### Origin检查
```rust
// 签名用户
let who = ensure_signed(origin)?;

// Root权限
ensure_root(origin)?;

// 无签名（固有交易）
ensure_none(origin)?;

// 自定义Origin检查
let who = T::CustomOrigin::ensure_origin(origin)?;
```

### 权限验证
```rust
// 检查账户余额
ensure!(
    T::Currency::free_balance(&who) >= amount,
    Error::<T>::InsufficientBalance
);

// 检查权限
ensure!(
    Self::is_admin(&who),
    Error::<T>::NoPermission
);

// 复合条件检查
ensure!(
    condition1 && condition2,
    Error::<T>::InvalidCondition
);
```

## 🎨 事件和错误

### 事件模板
```rust
#[pallet::event]
#[pallet::generate_deposit(pub(super) fn deposit_event)]
pub enum Event<T: Config> {
    /// 简单事件
    SomethingHappened,
    
    /// 带参数事件
    ValueSet { who: T::AccountId, value: u32 },
    
    /// 复杂事件
    TransactionProcessed {
        from: T::AccountId,
        to: T::AccountId,
        amount: u32,
        fee: u32,
    },
}

// 发出事件
Self::deposit_event(Event::ValueSet { who: who.clone(), value });
```

### 错误处理
```rust
#[pallet::error]
pub enum Error<T> {
    /// 值不存在
    NoneValue,
    /// 存储溢出
    StorageOverflow,
    /// 权限不足
    NoPermission,
    /// 余额不足
    InsufficientBalance,
    /// 参数无效
    InvalidParameter,
}

// 使用错误
return Err(Error::<T>::InsufficientBalance.into());

// 条件错误
ensure!(condition, Error::<T>::InvalidParameter);
```

## 🧪 测试辅助

### Mock Runtime
```rust
use frame_support::{
    construct_runtime, parameter_types,
    traits::{ConstU16, ConstU64},
};
use sp_core::H256;
use sp_runtime::{
    traits::{BlakeTwo256, IdentityLookup}, BuildStorage,
};

type Block = frame_system::mocking::MockBlock<Test>;

construct_runtime!(
    pub struct Test {
        System: frame_system,
        YourPallet: pallet_your_pallet,
    }
);

impl frame_system::Config for Test {
    type BaseCallFilter = frame_support::traits::Everything;
    type BlockWeights = ();
    type BlockLength = ();
    type DbWeight = ();
    type RuntimeOrigin = RuntimeOrigin;
    type RuntimeCall = RuntimeCall;
    type Nonce = u64;
    type Hash = H256;
    type Hashing = BlakeTwo256;
    type AccountId = u64;
    type Lookup = IdentityLookup<Self::AccountId>;
    type Block = Block;
    type RuntimeEvent = RuntimeEvent;
    type BlockHashCount = ConstU64<250>;
    type Version = ();
    type PalletInfo = PalletInfo;
    type AccountData = ();
    type OnNewAccount = ();
    type OnKilledAccount = ();
    type SystemWeightInfo = ();
    type SS58Prefix = ConstU16<42>;
    type OnSetCode = ();
    type MaxConsumers = frame_support::traits::ConstU32<16>;
}

pub fn new_test_ext() -> sp_io::TestExternalities {
    frame_system::GenesisConfig::<Test>::default().build_storage().unwrap().into()
}
```

## 📊 基准测试

### 基准测试模板
```rust
#![cfg(feature = "runtime-benchmarks")]

use super::*;
use frame_benchmarking::v2::*;
use frame_support::traits::Get;
use frame_system::RawOrigin;

#[benchmarks]
mod benchmarks {
    use super::*;

    #[benchmark]
    fn do_something(x: Linear<1, 1000>) {
        let caller: T::AccountId = whitelisted_caller();
        
        #[extrinsic_call]
        do_something(RawOrigin::Signed(caller), x);

        assert_eq!(Something::<T>::get(), Some(x));
    }

    #[benchmark]
    fn complex_operation() {
        let caller: T::AccountId = whitelisted_caller();
        let value = 100u32;
        
        #[extrinsic_call]
        complex_operation(RawOrigin::Signed(caller), value);

        // 验证结果
        assert!(ComplexStorage::<T>::contains_key(&caller));
    }

    impl_benchmark_test_suite!(YourPallet, crate::mock::new_test_ext(), crate::mock::Test);
}
```

## 🔗 有用链接

- [Substrate文档](https://docs.substrate.io/)
- [Polkadot-JS Apps](https://polkadot.js.org/apps/)
- [Substrate代码库](https://github.com/paritytech/substrate)
- [FRAME Pallets](https://docs.substrate.io/reference/frame-pallets/)
- [Rust语言文档](https://doc.rust-lang.org/)

## 📝 常用命令速查

```bash
# 项目管理
cargo new my-pallet --lib
cargo add frame-support frame-system
cargo remove old-dependency

# 开发工具
cargo expand pallet::call  # 查看宏展开
cargo tree                 # 查看依赖树
cargo audit                # 安全审计
cargo clippy               # 代码检查

# 测试相关
cargo test --package pallet-name
cargo test --features runtime-benchmarks
cargo test -- --nocapture  # 显示println!输出

# 构建相关
cargo build --features runtime-benchmarks
cargo build --release --features try-runtime
SKIP_WASM_BUILD=1 cargo check  # 跳过WASM构建

# 格式化和检查
cargo fmt --all
cargo clippy --all-targets --all-features
```

这个快速参考手册包含了开发Substrate区块链时最常用的代码模板和命令，可以作为日常开发的速查手册使用。