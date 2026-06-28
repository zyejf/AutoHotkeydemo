# 修复 IPC 架构缺陷 Spec

## Why

Rust/Tauri 项目的 IPC 层存在 5 个严重架构缺陷：类型系统重复、IPC 未接线、命令不发送 IPC、Watchdog 与 IPC 断联、测试方向错误。缺陷 #1-#4 已在前期修复中完成代码编写，但存在 3 个编译阻塞问题；缺陷 #5（IPC 测试方向错误）尚未修复。需要完成剩余编译修复和测试重写，确保 `cargo check`、`cargo test --lib`、`cargo clippy` 全部通过。

## What Changes

- **修复编译阻塞 #1**：在 `infrastructure/watchdog.rs` 中添加 `WatchdogRunner::from_arc()` 方法（`lib.rs` 第 79 行引用但不存在）
- **修复编译阻塞 #2**：将 `ProcessWatchdog::set_state()` 从 `fn` 改为 `pub fn`（`lib.rs` 第 120 行在 pipe-broken 回调中调用，但当前为私有方法）
- **修复编译阻塞 #3**：重写 `tests/ipc_tests.rs` 中使用旧 `IpcCommand` struct 语法的测试（第 319 行 `IpcCommand { action: ..., keys: ..., delay: ..., data: ... }`），改用新的 `IpcCommand` enum 语法
- **缺陷 #5 修复**：重写 `tests/ipc_tests.rs` 中所有使用 `connect_to_ahk()`（客户端模式）的测试，改为使用 `create_listener()` + `accept_from_ahk()`（服务端模式），与实际架构一致（Rust 是 Named Pipe 服务端，AHK 是客户端）

## Impact

- Affected specs: `rust-tauri-migration` Phase 1 Task 1.4（IPC 框架）、Phase 5 Task 5.1（测试体系）
- Affected code:
  - `infrastructure/watchdog.rs` — 添加 `from_arc()` 方法，`set_state()` 可见性变更
  - `tests/ipc_tests.rs` — 完全重写测试以使用服务端模式 + 新 IpcCommand enum

## ADDED Requirements

### Requirement: WatchdogRunner::from_arc() 构造器

系统 SHALL 提供 `WatchdogRunner::from_arc(watchdog: Arc<Mutex<ProcessWatchdog>>)` 构造器，允许从已有的 Arc<Mutex<ProcessWatchdog>> 创建 WatchdogRunner 实例，避免重复包装。

#### Scenario: 从 Arc 创建 WatchdogRunner
- **WHEN** 调用 `WatchdogRunner::from_arc(arc_mutex_watchdog)`
- **THEN** 返回的 `WatchdogRunner` 共享同一个 `Arc<Mutex<ProcessWatchdog>>` 实例，与 AppState 中的 watchdog 字段指向同一对象

### Requirement: ProcessWatchdog::set_state() 公开方法

系统 SHALL 将 `ProcessWatchdog::set_state()` 方法从 `fn` 改为 `pub fn`，允许外部模块（如 pipe-broken 回调）直接设置 Watchdog 状态。

#### Scenario: 外部模块设置 Recovering 状态
- **WHEN** pipe-broken 回调调用 `guard.set_state(WatchdogStateEnum::Recovering)`
- **THEN** Watchdog 状态成功变更为 Recovering，并触发 on_state_change 回调

### Requirement: IPC 测试使用服务端模式

系统 SHALL 将所有 IPC 集成测试从客户端模式（`IpcManager::new()` + `connect_to_ahk()`）改为服务端模式（`create_listener()` + `accept_from_ahk()`），与实际架构一致。

#### Scenario: 测试中 Rust 作为 Named Pipe 服务端
- **WHEN** 运行 IPC 测试
- **THEN** Rust 侧创建 Listener 并 accept 连接，模拟的 AHK 客户端连接到 Rust 监听的管道

#### Scenario: 测试使用 IpcCommand enum
- **WHEN** 测试构造 IPC 命令
- **THEN** 使用 `IpcCommand::ToggleGroup`、`IpcCommand::Ping` 等 enum 变体，而非旧的 struct 字面量语法

### Requirement: 全部测试通过

系统 SHALL 确保 `cargo check`、`cargo test --lib`、`cargo clippy` 全部通过，无编译错误、无测试失败、无 clippy 警告。

#### Scenario: 编译验证
- **WHEN** 执行 `cargo check`
- **THEN** 编译成功，退出码 0

#### Scenario: 测试验证
- **WHEN** 执行 `cargo test --lib`
- **THEN** 所有测试通过，退出码 0

#### Scenario: Clippy 验证
- **WHEN** 执行 `cargo clippy`
- **THEN** 无警告，退出码 0

## MODIFIED Requirements

### Requirement: IPC 测试架构方向

原测试使用 Rust 作为 Named Pipe 客户端（`connect_to_ahk()`），现修改为 Rust 作为 Named Pipe 服务端（`create_listener()` + `accept_from_ahk()`），与生产架构一致。

**变更原因**：生产环境中 Rust 是 Named Pipe 服务端（监听），AHK 是客户端（连接）。测试应验证服务端行为，而非客户端行为。

**迁移路径**：
- 旧模式：`IpcManager::new()` → `connect_to_ahk()` → `send()`/`recv()`
- 新模式：`IpcManager::new()` → `create_listener()` → `accept_from_ahk()` → `send()`/`recv()`/`listen_ahk()`

## REMOVED Requirements

### Requirement: 旧 IpcCommand struct 字面量测试
**Reason**: `IpcCommand` 已从 struct 重构为 enum（`#[serde(tag = "action")]`），旧的 struct 字面量语法不再编译
**Migration**: 使用 `IpcCommand::ToggleGroup { group_id, active }` 等 enum 变体替代
