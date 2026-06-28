# Crate Extraction 设计文档

> 日期: 2026-05-30
> 状态: Draft
> 范围: asd-tauri 单体 crate → 4 crate workspace

## 1. 动机

当前 `asd-tauri` 是一个单体 crate，所有代码在 `src-tauri/` 下。这导致：

1. **编译耦合** — 修改 domain 层数据结构需要重编译整个 tauri 应用（含 WebView2 绑定）
2. **依赖泄漏** — `domain/config.rs` 直接使用 `std::fs` 和 `tracing`；`application/scheduler.rs` 直接持有 `IpcOutboundSender`（tokio mpsc channel）
3. **无法独立测试** — 纯逻辑验证（如 ConfigValidator）必须链接 tauri + windows + interprocess
4. **协议不可复用** — IPC 协议定义（IpcCommand/IpcMessage）与 AHK 侧耦合在同一个 crate 中，AHK 客户端无法独立引用

## 2. 目标架构

```
asd-tauri/                          ← Cargo workspace 根
├── Cargo.toml                      ← workspace 定义
├── crates/
│   ├── asd-domain/                 ← 纯逻辑 crate
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── config.rs           ← Config 数据结构（无 I/O）
│   │       ├── models.rs           ← SkillGroup
│   │       ├── validator.rs        ← ConfigValidator
│   │       └── traits.rs           ← IpcSender, EventEmitter, ProcessWatcher
│   ├── asd-ipc-protocol/           ← IPC 协议定义
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── command.rs          ← IpcCommand enum
│   │       ├── message.rs          ← IpcMessage struct + 构造方法
│   │       ├── error.rs            ← IpcError enum
│   │       └── hotkey_merger.rs    ← HotkeyMerger
│   └── asd-application/            ← 应用逻辑
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs
│           ├── scheduler.rs        ← SkillManager（依赖 IpcSender trait）
│           ├── state.rs            ← AppState（依赖 EventEmitter + IpcSender trait）
│           ├── error.rs            ← AppError enum
│           └── config_repository.rs ← Config 文件 I/O（从 domain/config.rs 移出）
├── src-tauri/                      ← 表现层 + 基础设施实现
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs                  ← Tauri commands + setup
│       ├── bridge.rs               ← trait 实现桥接（新增）
│       ├── infrastructure/
│       │   ├── ipc.rs              ← IpcManager（保留）
│       │   ├── logging.rs
│       │   └── watchdog.rs         ← ProcessWatchdog（保留）
│       └── commands/               ← Tauri command handlers（保留）
```

## 3. Crate 依赖矩阵

| Crate | asd-domain | asd-ipc-protocol | asd-application | serde | serde_json | indexmap | thiserror | tracing | tokio | tauri | windows | interprocess |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| asd-domain | — | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| asd-ipc-protocol | ✗ | — | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| asd-application | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| asd-tauri | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**关键约束**: asd-domain 和 asd-ipc-protocol 是纯逻辑 crate，不含任何平台依赖。

## 4. 文件迁移映射表

### 4.1 asd-domain

| 源文件 | 目标文件 | 迁移操作 |
|--------|---------|---------|
| `src-tauri/src/domain/config.rs` | `crates/asd-domain/src/config.rs` | 移除 I/O 方法（`load_from_file`, `save_to_file`, `load_from_path`, `save_to_path`），移除 `tracing` 引用，保留数据结构和 `default_config()` |
| `src-tauri/src/domain/models.rs` | `crates/asd-domain/src/models.rs` | `IpcCommand` 和 `IpcMessage` 移至 asd-ipc-protocol；仅保留 `SkillGroup` 及其序列化逻辑 |
| `src-tauri/src/domain/validator.rs` | `crates/asd-domain/src/validator.rs` | 原样迁移，更新 `use` 路径 |
| — | `crates/asd-domain/src/traits.rs` | 新增：定义 `IpcSender`, `EventEmitter`, `ProcessWatcher` trait |
| `src-tauri/src/domain/mod.rs` | `crates/asd-domain/src/lib.rs` | 模块声明 |

### 4.2 asd-ipc-protocol

| 源文件 | 目标文件 | 迁移操作 |
|--------|---------|---------|
| `src-tauri/src/domain/models.rs` (IpcCommand 部分) | `crates/asd-ipc-protocol/src/command.rs` | 提取 `IpcCommand` enum |
| `src-tauri/src/domain/models.rs` (IpcMessage 部分) | `crates/asd-ipc-protocol/src/message.rs` | 提取 `IpcMessage` struct + 构造方法 |
| `src-tauri/src/infrastructure/ipc.rs` (IpcError 部分) | `crates/asd-ipc-protocol/src/error.rs` | 提取 `IpcError` enum |
| `src-tauri/src/infrastructure/ipc.rs` (HotkeyMerger 部分) | `crates/asd-ipc-protocol/src/hotkey_merger.rs` | 提取 `HotkeyMerger`（纯逻辑，不依赖 tokio） |
| — | `crates/asd-ipc-protocol/src/lib.rs` | 模块声明 + re-export |

### 4.3 asd-application

| 源文件 | 目标文件 | 迁移操作 |
|--------|---------|---------|
| `src-tauri/src/application/scheduler.rs` | `crates/asd-application/src/scheduler.rs` | 依赖 `IpcSender` trait 而非 `IpcOutboundSender`；`send_ipc_command` 签名改为接收 `&dyn IpcSender` |
| `src-tauri/src/application/state.rs` | `crates/asd-application/src/state.rs` | 依赖 `EventEmitter` + `IpcSender` trait；移除 `tauri::Emitter` 直接依赖 |
| `src-tauri/src/application/state.rs` (AppError) | `crates/asd-application/src/error.rs` | 提取 `AppError` enum |
| `src-tauri/src/domain/config.rs` (I/O 方法) | `crates/asd-application/src/config_repository.rs` | 提取 `load_from_file`, `save_to_file`, `load_from_path`, `save_to_path` |
| — | `crates/asd-application/src/lib.rs` | 模块声明 |

### 4.4 asd-tauri（重构后）

| 源文件 | 目标文件 | 迁移操作 |
|--------|---------|---------|
| — | `src-tauri/src/bridge.rs` | 新增：`IpcSender`, `EventEmitter`, `ProcessWatcher` trait 的具体实现 |
| `src-tauri/src/lib.rs` | `src-tauri/src/lib.rs` | 更新 import 路径，使用新 crate |
| `src-tauri/src/infrastructure/ipc.rs` | `src-tauri/src/infrastructure/ipc.rs` | 移除 `IpcError`, `HotkeyMerger`（已迁移），保留 `IpcManager` |
| `src-tauri/src/infrastructure/watchdog.rs` | `src-tauri/src/infrastructure/watchdog.rs` | 保留原样 |
| `src-tauri/src/commands/*.rs` | `src-tauri/src/commands/*.rs` | 更新 import 路径 |

### 4.5 测试迁移

| 源文件 | 目标文件 | 说明 |
|--------|---------|------|
| `src-tauri/src/domain/config.rs` (unit_tests) | `crates/asd-domain/src/config.rs` (unit_tests) | 数据结构测试跟随迁移；I/O 测试移至 asd-application |
| `src-tauri/src/domain/models.rs` (tests) | 分散至 asd-domain 和 asd-ipc-protocol | SkillGroup 测试 → asd-domain；IpcCommand/IpcMessage 测试 → asd-ipc-protocol |
| `src-tauri/src/domain/validator.rs` (tests) | `crates/asd-domain/src/validator.rs` (tests) | 原样迁移 |
| `src-tauri/src/infrastructure/ipc.rs` (HotkeyMerger tests) | `crates/asd-ipc-protocol/src/hotkey_merger.rs` (tests) | 跟随迁移 |
| `src-tauri/src/infrastructure/ipc.rs` (IpcManager tests) | `src-tauri/src/infrastructure/ipc.rs` (tests) | 保留在 asd-tauri |
| `src-tauri/src/tests/config_compat_tests.rs` | `src-tauri/src/tests/config_compat_tests.rs` | 保留在 asd-tauri（依赖 config.json 文件） |
| `src-tauri/src/tests/ipc_tests.rs` | `src-tauri/src/tests/ipc_tests.rs` | 保留在 asd-tauri（依赖 interprocess） |
| `src-tauri/src/application/scheduler.rs` (tests) | `crates/asd-application/src/scheduler.rs` (tests) | 跟随迁移 |
| `src-tauri/src/application/state.rs` (tests) | `crates/asd-application/src/state.rs` (tests) | 跟随迁移 |
| `src-tauri/src/commands/config_cmd.rs` (tests) | `src-tauri/src/commands/config_cmd.rs` (tests) | 保留在 asd-tauri |
| `src-tauri/src/commands/group_cmd.rs` (tests) | `src-tauri/src/commands/group_cmd.rs` (tests) | 保留在 asd-tauri |
| `src-tauri/src/commands/recording_cmd.rs` (tests) | `src-tauri/src/commands/recording_cmd.rs` (tests) | 保留在 asd-tauri |

### 4.6 基准测试 / Fuzz 迁移

| 源文件 | 目标文件 | 说明 |
|--------|---------|------|
| `src-tauri/benches/benchmarks.rs` | `src-tauri/benches/benchmarks.rs` | 更新 import 路径 |
| `src-tauri/fuzz/fuzz_targets/fuzz_config_deserialize.rs` | `src-tauri/fuzz/fuzz_targets/fuzz_config_deserialize.rs` | 更新 import 路径 |
| `src-tauri/fuzz/fuzz_targets/fuzz_ipc_command.rs` | `src-tauri/fuzz/fuzz_targets/fuzz_ipc_command.rs` | 更新 import 路径 |
| `src-tauri/fuzz/fuzz_targets/fuzz_ipc_json.rs` | `src-tauri/fuzz/fuzz_targets/fuzz_ipc_json.rs` | 更新 import 路径 |

## 5. Trait 定义

### 5.1 IpcSender

```rust
pub trait IpcSender: Send + Sync {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String>;
}
```

**实现**（在 `src-tauri/src/bridge.rs`）:

```rust
pub struct IpcSenderBridge {
    ipc_manager: Arc<tokio::sync::Mutex<Option<IpcManager>>>,
}

impl IpcSender for IpcSenderBridge {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        let mgr = self.ipc_manager.clone();
        let rt = tokio::runtime::Handle::current();
        rt.block_on(async {
            let mut guard = mgr.lock().await;
            let manager = guard.as_mut().ok_or("IPC 管理器未初始化".to_string())?;
            manager.send_command(cmd).await.map_err(|e| format!("IPC 发送失败: {e}"))
        })
    }
}
```

### 5.2 EventEmitter

```rust
pub trait EventEmitter: Send + Sync {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool;
}
```

**实现**（在 `src-tauri/src/bridge.rs`）:

```rust
pub struct EventEmitterBridge {
    app_handle: RwLock<Option<tauri::AppHandle>>,
}

impl EventEmitter for EventEmitterBridge {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool {
        if let Ok(guard) = self.app_handle.read() {
            if let Some(ref handle) = *guard {
                match handle.emit(event, payload) {
                    Ok(()) => true,
                    Err(e) => {
                        tracing::warn!("emit 事件 '{event}' 失败: {e}");
                        false
                    }
                }
            } else {
                false
            }
        } else {
            false
        }
    }
}
```

### 5.3 ProcessWatcher

```rust
pub trait ProcessWatcher: Send + Sync {
    fn state(&self) -> WatchdogStateEnum;
    fn restart_count(&self) -> u32;
}
```

**实现**（在 `src-tauri/src/bridge.rs`）:

```rust
pub struct ProcessWatcherBridge {
    watchdog: Arc<tokio::sync::Mutex<ProcessWatchdog>>,
}

impl ProcessWatcher for ProcessWatcherBridge {
    fn state(&self) -> WatchdogStateEnum {
        let rt = tokio::runtime::Handle::current();
        rt.block_on(async {
            let guard = self.watchdog.lock().await;
            guard.state().clone()
        })
    }

    fn restart_count(&self) -> u32 {
        let rt = tokio::runtime::Handle::current();
        rt.block_on(async {
            let guard = self.watchdog.lock().await;
            guard.restart_count()
        })
    }
}
```

## 6. I/O 泄漏修复

### 6.1 domain/config.rs 当前泄漏

| 方法 | 泄漏依赖 | 迁移目标 |
|------|---------|---------|
| `load_from_file()` | `std::fs::read_to_string`, `tracing::error!`, `tracing::warn!` | `asd-application::config_repository` |
| `save_to_file()` | `std::fs::write` | `asd-application::config_repository` |
| `load_from_path()` | `std::fs::read_to_string` | `asd-application::config_repository` |
| `save_to_path()` | `std::fs::write`, `fs::rename`, `fs::remove_file` | `asd-application::config_repository` |
| `load_default()` | 间接调用 `load_from_file` | 废弃（`#[deprecated]`），移除 |

### 6.2 config_repository.rs 设计

```rust
pub struct ConfigRepository;

impl ConfigRepository {
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Config { ... }
    pub fn save_to_file<P: AsRef<Path>>(config: &Config, path: P) -> Result<(), String> { ... }
    pub fn load_from_path<P: AsRef<Path>>(path: P) -> Result<Config, String> { ... }
    pub fn save_to_path<P: AsRef<Path>>(config: &Config, path: P) -> Result<(), String> { ... }
}
```

方法签名从 `impl Config` 的方法变为 `ConfigRepository` 的关联函数，`&self` 变为显式参数。

## 7. application/scheduler.rs 依赖解耦

### 当前依赖

```rust
use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};
```

`SkillManager` 持有 `IpcOutboundSender`（tokio mpsc channel），但实际未使用（`#[allow(dead_code)]`）。

### 解耦方案

1. `SkillManager::new()` 不再接收 `IpcOutboundSender`
2. `send_ipc_command` 和 `emergency_release` / `hold_mode_toggle` 改为接收 `Arc<dyn IpcSender>` 或通过参数传递
3. 测试中使用 mock 实现

## 8. application/state.rs 依赖解耦

### 当前依赖

| 依赖 | 用途 | 解耦方案 |
|------|------|---------|
| `tauri::Emitter` + `tauri::AppHandle` | `emit_event()` | 替换为 `Arc<dyn EventEmitter>` |
| `IpcManager` + `IpcOutboundSender` | IPC 通信 | 替换为 `Arc<dyn IpcSender>` |
| `ProcessWatchdog` + `WatchdogStateEnum` | 进程监控 | `WatchdogStateEnum` 移至 asd-domain；`ProcessWatchdog` 通过 `Arc<dyn ProcessWatcher>` 访问 |

### WatchdogStateEnum 迁移

`WatchdogStateEnum` 当前定义在 `infrastructure/watchdog.rs`，但被 `application/state.rs` 使用。需要将其移至 `asd-domain`（纯数据枚举，无平台依赖）。

## 9. Workspace Cargo.toml

```toml
[workspace]
resolver = "2"
members = [
    "crates/asd-domain",
    "crates/asd-ipc-protocol",
    "crates/asd-application",
    "src-tauri",
]

[workspace.package]
version = "0.1.0"
edition = "2021"

[workspace.dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
indexmap = { version = "2", features = ["serde"] }
thiserror = "2.0"
tracing = "0.1"
```

## 10. 各 Crate Cargo.toml

### asd-domain

```toml
[package]
name = "asd-domain"
version.workspace = true
edition.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
indexmap = { workspace = true }
thiserror = { workspace = true }
```

### asd-ipc-protocol

```toml
[package]
name = "asd-ipc-protocol"
version.workspace = true
edition.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
thiserror = { workspace = true }
```

### asd-application

```toml
[package]
name = "asd-application"
version.workspace = true
edition.workspace = true

[dependencies]
asd-domain = { path = "../asd-domain" }
asd-ipc-protocol = { path = "../asd-ipc-protocol" }
serde = { workspace = true }
serde_json = { workspace = true }
indexmap = { workspace = true }
thiserror = { workspace = true }
tracing = { workspace = true }
```

### asd-tauri（更新后）

```toml
[package]
name = "asd-tauri"
version.workspace = true
edition.workspace = true

# ... 保持原有 [features], [lib], [build-dependencies] ...

[dependencies]
asd-domain = { path = "../crates/asd-domain" }
asd-ipc-protocol = { path = "../crates/asd-ipc-protocol" }
asd-application = { path = "../crates/asd-application" }
tauri = { version = "2.11.2", features = ["tray-icon"] }
serde = { workspace = true }
serde_json = { workspace = true }
windows = { version = "0.62.2", features = [...] }
tokio = { version = "1", features = ["full"] }
interprocess = { version = "2.4.2", features = ["tokio"] }
thiserror = { workspace = true }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
clap = { version = "4", features = ["derive"] }
tauri-plugin-opener = "2"
tauri-plugin-global-shortcut = "2.3.1"
tauri-plugin-dialog = "2.7.1"
tauri-plugin-fs = "2.5.1"
tracing-appender = "0.2"
chrono = { version = "0.4", features = ["serde"] }
indexmap = { workspace = true }
```

## 11. 迁移阶段

| Phase | 内容 | 验证标准 |
|-------|------|---------|
| Phase 1 | 创建 asd-domain crate | `cargo test -p asd-domain` 全部通过 |
| Phase 2 | 创建 asd-ipc-protocol crate | `cargo test -p asd-ipc-protocol` 全部通过 |
| Phase 3 | 创建 asd-application crate | `cargo test -p asd-application` 全部通过 |
| Phase 4 | 重构 asd-tauri 主 crate | `cargo test` 全部通过（222 测试） |
| Phase 5 | Miri 验证 | `cargo +nightly miri test -p asd-domain` 通过 |

## 12. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| `IpcSender` trait 的 async 方法 | 需要 `async_trait` 或手动 `Pin<Box<dyn Future>>` | `send_command` 使用同步签名，内部通过 `tokio::runtime::Handle::current().block_on()` 桥接 |
| `WatchdogStateEnum` 跨 crate 移动 | 破坏 `infrastructure/watchdog.rs` 的 `use` 路径 | 在 asd-domain 中定义，在 asd-tauri 中 re-export |
| `SkillGroup` 依赖 `IpcCommand`（通过 `build_toggle_command`） | asd-domain 需要引用 asd-ipc-protocol | `build_toggle_command` 移至 asd-application |
| `config_compat_tests.rs` 使用 `include_str!` | 测试文件路径相对位置变化 | 保留在 asd-tauri 中，不迁移 |
| `IpcMessage::command()` 引用 `IpcCommand` | IpcMessage 和 IpcCommand 必须在同一 crate | 两者都在 asd-ipc-protocol 中 |
| `HotkeyMerger` 使用 `std::time::Instant` | 纯逻辑 crate 可以使用 std | std::time 是 OS-agnostic 的，允许 |

## 13. 不变量

1. **所有 222 个现有测试必须继续通过** — 纯重构，不修改功能逻辑
2. **asd_tauri_lib 的公开 API 不变** — Tauri command 签名不变
3. **asd-domain 和 asd-ipc-protocol 不含平台依赖** — 不依赖 tauri, windows, tokio, interprocess, std::fs, tracing
4. **asd-application 不含 tauri 依赖** — 不直接使用 `tauri::Emitter` 或 `tauri::AppHandle`
5. **编译时间改善** — 修改 domain 层不需要重编译 tauri
