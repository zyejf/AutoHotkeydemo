# Task 6: Rust src-tauri 架构+质量审查发现

> 审查日期: 2026-08-03
> 审查范围: `asd-tauri/src-tauri/` 主 crate
> 审查性质: 只读审查（未修改任何源代码）

## 审查范围

| 文件 | 行数 | 说明 |
|------|------|------|
| `src/lib.rs` | 686 | 19→34 Tauri commands 注册 + 应用初始化 |
| `src/bridge.rs` | 192 | IpcBridge / TauriEventBridge / WatchdogBridge |
| `src/infrastructure/ipc.rs` | 1089 | IpcManager（interprocess named pipe） |
| `src/infrastructure/watchdog.rs` | 929 | ProcessWatchdog + WatchdogRunner + JobObjectGuard |
| `src/infrastructure/logging.rs` | 48 | tracing 日志初始化 |
| `src/commands/config_cmd.rs` | 213 | 11 个配置命令 |
| `src/commands/group_cmd.rs` | 143 | 8 个分组命令 |
| `src/commands/hotkey_cmd.rs` | 146 | 2 个热键命令 |
| `src/commands/recording_cmd.rs` | 122 | 8 个录制命令 |
| `src/commands/system_cmd.rs` | 296 | 5 个系统命令 |
| `src/tests/ipc_tests.rs` | 881 | IPC 传输层测试 |
| `src/tests/bridge_tests.rs` | 336 | Bridge trait 实现测试 |
| `src/tests/config_compat_tests.rs` | 270 | 配置兼容性测试 |
| `Cargo.toml` | 60 | 依赖声明 |

## Tauri commands 清单（34 个，全部合规）

> **注**: AGENTS.md 中记录为 "19 Tauri commands"，实际为 **34 个**（文档过时，见 Finding 4）。

| # | 命令 | 文件 | `#[tauri::command]` | invoke_handler 注册 | 返回类型 |
|---|------|------|---------------------|---------------------|----------|
| 1 | `get_config` | config_cmd.rs:9 | OK | OK | `Result<Config, AppError>` |
| 2 | `save_config` | config_cmd.rs:14 | OK | OK | `Result<(), AppError>` |
| 3 | `validate_config` | config_cmd.rs:21 | OK | OK | `Result<ValidationResult, AppError>` |
| 4 | `list_backups` | config_cmd.rs:27 | OK | OK | `Result<Vec<BackupInfo>, AppError>` |
| 5 | `create_backup` | config_cmd.rs:34 | OK | OK | `Result<String, AppError>` |
| 6 | `restore_backup` | config_cmd.rs:39 | OK | OK | `Result<(), AppError>` |
| 7 | `hot_reload` | config_cmd.rs:50 | OK | OK | `Result<Config, AppError>` |
| 8 | `delete_backup` | config_cmd.rs:55 | OK | OK | `Result<(), AppError>` |
| 9 | `export_config` | config_cmd.rs:66 | OK | OK | `Result<(), AppError>` |
| 10 | `import_config` | config_cmd.rs:77 | OK | OK | `Result<(), AppError>` |
| 11 | `compare_configs` | config_cmd.rs:88 | OK | OK | `Result<ConfigDiff, AppError>` |
| 12 | `get_groups` | group_cmd.rs:77 | OK | OK | `Result<Vec<GroupSummary>, AppError>` |
| 13 | `toggle_group` | group_cmd.rs:83 | OK | OK | `Result<GroupStatus, AppError>` |
| 14 | `get_group_detail` | group_cmd.rs:91 | OK | OK | `Result<SkillGroup, AppError>` |
| 15 | `delete_group` | group_cmd.rs:104 | OK | OK | `Result<(), AppError>` |
| 16 | `toggle_all` | group_cmd.rs:112 | OK | OK | `Result<BatchToggleResult, AppError>` |
| 17 | `batch_toggle_groups` | group_cmd.rs:120 | OK | OK | `Result<BatchToggleResult, AppError>` |
| 18 | `batch_delete_groups` | group_cmd.rs:129 | OK | OK | `Result<BatchDeleteResult, AppError>` |
| 19 | `reorder_groups` | group_cmd.rs:137 | OK | OK | `Result<ReorderResult, AppError>` |
| 20 | `register_hotkey` | hotkey_cmd.rs:5 | OK | OK | `Result<(), AppError>` |
| 21 | `unregister_hotkey` | hotkey_cmd.rs:14 | OK | OK | `Result<(), AppError>` |
| 22 | `start_recording` | recording_cmd.rs:61 | OK | OK | `Result<(), AppError>` |
| 23 | `stop_recording` | recording_cmd.rs:70 | OK | OK | `Result<RecordingResult, AppError>` |
| 24 | `pause_recording` | recording_cmd.rs:77 | OK | OK | `Result<u64, AppError>` |
| 25 | `resume_recording` | recording_cmd.rs:82 | OK | OK | `Result<u64, AppError>` |
| 26 | `export_recording` | recording_cmd.rs:91 | OK | OK | `Result<(), AppError>` |
| 27 | `import_recording` | recording_cmd.rs:106 | OK | OK | `Result<ImportedRecording, AppError>` |
| 28 | `start_validation` | recording_cmd.rs:111 | OK | OK | `Result<u64, AppError>` |
| 29 | `stop_validation` | recording_cmd.rs:119 | OK | OK | `Result<u64, AppError>` |
| 30 | `get_executor_status` | system_cmd.rs:90 | OK | OK | `Result<WatchdogState, AppError>` |
| 31 | `emergency_release` | system_cmd.rs:97 | OK | OK | `Result<(), AppError>` |
| 32 | `clear_emergency` | system_cmd.rs:102 | OK | OK | `Result<(), AppError>` |
| 33 | `toggle_hold_mode` | system_cmd.rs:116 | OK | OK | `Result<bool, AppError>` |
| 34 | `reset_watchdog` | system_cmd.rs:121 | OK | OK | `Result<(), AppError>` |

**结论**: 34 个命令全部正确标注 `#[tauri::command]` 并在 `invoke_handler!` 中注册。无遗漏。

## 发现清单

### Finding 1

- **位置**: `src/lib.rs:390-406`
- **维度**: 架构合规性（已知妥协 #2 扩展分析）
- **严重级别**: Important
- **描述**: `setup_ipc_and_watchdog` 函数中存在嵌套锁获取：在持有 `ipc_manager_arc` 锁（lib.rs:391 `blocking_lock`）的同时，调用 `setup_ipc_callbacks`，后者内部又获取 `watchdog` 锁（lib.rs:335 `blocking_lock`）。形成锁顺序 `ipc_manager → watchdog`。

```rust
// lib.rs:390-395 — 持有 ipc_manager_arc 锁
let guard = tokio::task::block_in_place(|| ipc_manager_arc.blocking_lock());
if let Some(ref mgr) = *guard {
    setup_ipc_callbacks(app_state, mgr, watchdog, ipc_manager_arc);  // ← 内部获取 watchdog 锁
}

// lib.rs:334-357 — setup_ipc_callbacks 内部
let mut guard = tokio::task::block_in_place(|| watchdog.blocking_lock());  // 嵌套获取
guard.set_send_shutdown(Arc::new(move || { ... }));
```

- **根因**: 初始化代码组织导致自然的嵌套锁。`setup_ipc_callbacks` 需要 `&IpcManager` 引用（已持有锁的 guard 解引用）和 `&WatchdogArc`（用于设置 send_shutdown 回调，需获取 watchdog 锁）。
- **死锁风险评估**: 当前**不会死锁**。原因：
  1. 此代码运行在 Tauri `setup` 闭包中（单线程初始化阶段），无并发。
  2. 审查所有运行时锁获取路径（`perform_graceful_shutdown`、`spawn_heartbeat_ping`、`spawn_watchdog` 状态同步、各 callback spawn 任务），均未发现 `watchdog → ipc_manager` 反向锁顺序。
  3. `perform_graceful_shutdown` 虽然先后获取两个锁，但第一个锁在获取第二个前已 `drop`（lib.rs:44-56）。
- **修复建议**:
  1. **文档约束**: 在 lib.rs 中添加注释，明确记录锁顺序约束："ipc_manager 锁必须在 watchdog 锁之前获取，禁止反向顺序"。
  2. **可选重构**: 将 `setup_ipc_callbacks` 拆分为两部分——设置 IPC 回调（不需要 watchdog 锁）和设置 send_shutdown 回调（需要 watchdog 锁），在 `setup_ipc_and_watchdog` 中先释放 ipc_manager 锁再获取 watchdog 锁。

### Finding 2

- **位置**: `src/bridge.rs:26-120`（IpcBridge）、`src/bridge.rs:151-191`（WatchdogBridge）
- **维度**: 架构合规性（已知妥协 #2）
- **严重级别**: Important
- **描述**: `IpcBridge` 和 `WatchdogBridge` 的 trait 实现使用 `block_in_place + block_on` 模式桥接同步 trait 方法到 async 实现，共 5 处：
  - `IpcBridge::send_command` (bridge.rs:29)
  - `IpcBridge::send_and_wait` (bridge.rs:58)
  - `WatchdogBridge::state` (bridge.rs:154)
  - `WatchdogBridge::restart_count` (bridge.rs:164)
  - `WatchdogBridge::reset` (bridge.rs:174)

```rust
fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
    let ipc_manager = self.ipc_manager.clone();
    tokio::task::block_in_place(|| {
        tokio::runtime::Handle::current().block_on(async move {
            let mgr = {
                let manager = ipc_manager.lock().await;  // async 锁
                manager.clone()
            };
            // ...
        })
    })
}
```

- **根因**: `IpcSender` / `ProcessWatcher` trait 在 `asd-domain` 中定义为同步方法（`fn send_command(&self, cmd: IpcCommand) -> Result<u64, String>`），但底层资源（`IpcManager`、`ProcessWatchdog`）使用 `tokio::sync::Mutex` 保护，需要 async 上下文访问。
- **死锁风险评估**: 
  - bridge.rs 内部锁临界区极短（clone 后立即释放 guard），死锁风险低。
  - 但 `block_in_place` 会阻塞当前 tokio 工作线程。如果在 async 上下文中调用这些同步方法（如 `post_connect_callback` spawn 的任务中调用 `state.try_send_ipc_command` → `IpcBridge::send_command`），会阻塞一个工作线程直到 IPC 操作完成。
  - `block_in_place` 要求多线程 tokio 运行时（Tauri 默认满足），且不能在 `Runtime::block_on` 内调用。
- **修复建议**: 
  1. 短期：保持现状，符合 AGENTS.md 妥协 #2 约束。在 bridge.rs 中添加注释说明 `block_in_place` 的约束（不可在 `block_on` 内嵌套调用）。
  2. 长期：将 `IpcSender` / `ProcessWatcher` trait 改为 async（`async fn send_command(...)`），消除 `block_in_place` 需求。但这是 BREAKING CHANGE，需评估对 asd-application crate 的影响。

### Finding 3

- **位置**: `src/lib.rs:214-358`（`setup_ipc_callbacks`）
- **维度**: 架构合规性（IPC 通信规则）
- **严重级别**: Minor
- **描述**: AGENTS.md 规则要求"IPC 通信必须通过 `IpcSender` trait，禁止直接调用 `IpcManager`"。但 `setup_ipc_callbacks` 函数签名接收 `ipc_manager: &IpcManager`（具体类型），直接调用其方法：
  - `ipc_manager.set_heartbeat_callback(...)` (lib.rs:221)
  - `ipc_manager.set_pipe_broken_callback(...)` (lib.rs:230)
  - `ipc_manager.set_post_connect_callback(...)` (lib.rs:249)

- **根因**: 这些是初始化阶段的回调注册，不属于"IPC 通信"范畴，而是基础设施配置。`IpcManager` 没有抽象 trait 接口供回调注册使用。
- **评估**: 
  - 直接调用仅用于设置回调，不涉及命令发送/消息接收。
  - `spawn_ipc_accept_loop` (lib.rs:115) 和 `spawn_heartbeat_ping` (lib.rs:138) 直接操作 `IpcManager`（调用 `accept_loop`、`send`、`is_connected` 等），但这些是基础设施生命周期管理，非业务命令路径。
  - 所有业务命令路径（Tauri commands → AppState → IpcBridge::send_command）均通过 `IpcSender` trait。
- **修复建议**: 
  1. 可接受现状：初始化代码需要操作具体类型，依赖反转在此场景过度抽象。
  2. 如需严格合规，可提取 `IpcManagerConfigurator` trait 用于回调注册，但收益有限。

### Finding 4

- **位置**: `AGENTS.md`（项目规则文档）
- **维度**: 文档一致性
- **严重级别**: Important
- **描述**: AGENTS.md 中多处描述与实际代码不符：

| 文档描述 | 实际情况 | 影响 |
|----------|----------|------|
| "19 Tauri commands + 应用初始化" (Key Files 表) | **34 个** Tauri commands | 文档过时，低估命令规模 |
| "src-tauri 内部有 domain/application 子模块但仅包含 re-export" (妥协 #3) | `src-tauri/src/domain/` 和 `src-tauri/src/application/` **目录不存在** | 妥协 #3 描述的场景已不适用，文档需更新 |
| Common Patterns 示例: `async fn get_config(...) -> Result<Config, String>` | 实际返回 `Result<Config, AppError>`（类型化错误） | 文档示例不准确，实际实现更优 |

- **根因**: 代码迭代后文档未同步更新。妥协 #3 中描述的 "src-tauri 内部 DDD 分层占位" 可能已被移除。
- **修复建议**: 
  1. 更新 AGENTS.md Key Files 表：`19 Tauri commands` → `34 Tauri commands`。
  2. 更新或移除妥协 #3：如果 domain/application 子模块已删除，应移除该妥协条目。
  3. 更新 Common Patterns 中 Tauri Command 示例，反映 `AppError` 返回类型。

### Finding 5

- **位置**: `src/lib.rs:249-330`（`post_connect_callback`）
- **维度**: 架构合规性（已知设计权衡）
- **严重级别**: Minor
- **描述**: `post_connect_callback` 在 AHK 重连成功后执行状态恢复，内部通过 `state.try_send_ipc_command(&cmd)` 发送多个恢复命令（ToggleGroup、RegisterHotkey、HoldModeToggle）。代码中已有详细注释说明竞态窗口（lib.rs:253-256）：

```rust
// 设计决策：post_connect_callback 与 toggle_group 回滚存在理论竞态窗口。
// 如果 toggle_group 在更新内存状态后、IPC 发送失败回滚前，恰好被此回调读取，
// 可能导致恢复状态与实际不一致。窗口极窄（微秒级），且不一致性会在下次
// 切换或重连时自动修正，因此作为已知设计权衡接受。
```

- **评估**: 
  - 竞态窗口已有文档记录，且有自动修正机制。
  - 回调内部正确清理了瞬态状态（emergency_mode、recording_mode、validation_in_progress），防止 Rust-AHK 状态分裂。
  - `recording_mode` 写锁同时保护 `validation_in_progress` 的清理，注释说明清晰（lib.rs:313-328）。
- **修复建议**: 无需修改，设计权衡合理。

### Finding 6

- **位置**: `src/infrastructure/watchdog.rs:67-73`
- **维度**: 代码质量（unsafe 安全性）
- **严重级别**: Minor
- **描述**: `ProcessWatchdog` 使用 `unsafe impl Send` 和 `unsafe impl Sync`，有详细的 SAFETY 注释说明原因：

```rust
// SAFETY: ProcessWatchdog 的所有字段都是 Send 安全的：
// ...
unsafe impl Send for ProcessWatchdog {}
// SAFETY: ProcessWatchdog 的 Sync 安全性不依赖于字段本身的 Sync 性质
// 而是依赖于外部 Mutex 保护：ProcessWatchdog 仅通过 Arc<tokio::sync::Mutex<ProcessWatchdog>> 共享
unsafe impl Sync for ProcessWatchdog {}
```

- **评估**: 
  - SAFETY 注释完整，符合 Rust unsafe 代码规范。
  - `JobObjectGuard` (watchdog.rs:492-499) 同样有 SAFETY 注释。
  - `RawBoxGuard` (watchdog.rs:544-562) 正确实现 RAII 防止内存泄漏。
  - `enum_windows_callback` (watchdog.rs:576-597) 的 unsafe FFI 正确处理空指针检查。
  - Drop 实现正确调用 `CloseHandle` 释放系统资源。
- **修复建议**: 无需修改，unsafe 代码处理规范。

### Finding 7

- **位置**: `src/infrastructure/watchdog.rs:20-23`、`ahk_executor/ipc_client.ahk:20-23`
- **维度**: 架构合规性（心跳超时匹配）
- **严重级别**: Minor
- **描述**: 心跳超时配置跨 Rust/AHK 双端：

| 参数 | Rust 端 (watchdog.rs) | AHK 端 (ipc_client.ahk) | 说明 |
|------|----------------------|-------------------------|------|
| 心跳发送间隔 | `HEARTBEAT_INTERVAL = 1s` (Rust 发 ping) | — | Rust 每 1 秒发送 ping |
| 心跳超时阈值 | `HEARTBEAT_TIMEOUT = 3s` | — | Rust 检测 AHK 心跳超时 |
| 超时计数阈值 | `HEARTBEAT_TIMEOUT_COUNT = 3` | — | 连续 3 次超时才判定 Hung |
| AHK 端心跳超时 | — | `HEARTBEAT_TIMEOUT_MS = 5000` (5s) | AHK 检测 Rust 主进程心跳超时 |

- **评估**: 
  - Rust→AHK 方向：Rust 每 1 秒发 ping，AHK 即时回 pong。Rust 端 3 秒超时 × 3 次 ≈ 6-9 秒无响应判定 Hung。合理。
  - AHK→Rust 方向：AHK 端 5 秒超时检测 Rust 心跳。Rust 的 ping 间隔 1 秒 < 5 秒，正常情况下不会误判。
  - 管道名称一致：Rust `asd_ipc` ↔ AHK `\\.\pipe\asd_ipc`（interprocess crate 自动处理命名空间前缀）。
- **修复建议**: 无需修改，心跳配置匹配。

### Finding 8

- **位置**: `src/infrastructure/ipc.rs:432-483`（`recv` 方法）
- **维度**: 代码质量（健壮性）
- **严重级别**: Minor
- **描述**: IPC 消息接收的边界处理优秀：
  - `MAX_MESSAGE_SIZE = 64KB` 限制单条消息大小 (ipc.rs:17)
  - 超大消息检测后，消耗剩余数据直到换行符，防止管道错位 (ipc.rs:454-468)
  - `MAX_DISCARD_SIZE = 1MB` 限制消耗量，防止异常 AHK 进程发送超长无换行数据导致 OOM (ipc.rs:454)
  - 认证机制：首条消息必须是 auth 类型且 token 匹配 (ipc.rs:166-208)
  - 指数退避：认证失败时使用 1/2/4/8/16/30 秒退避，防止恶意连接洪泛 (ipc.rs:256-267)

- **评估**: 防御性编程到位，边界条件处理完善。
- **修复建议**: 无需修改。

## 无问题声明

以下检查项未发现问题：

1. **Tauri command 宏标注**: 全部 34 个命令正确标注 `#[tauri::command]` 并在 `invoke_handler!` 中注册。无遗漏、无多余。
2. **bridge.rs trait 实现**: `IpcBridge` 实现 `IpcSender`、`TauriEventBridge` 实现 `EventEmitter`、`WatchdogBridge` 实现 `ProcessWatcher`，trait 方法签名与定义一致。
3. **tracing 日志使用**: 全部使用 `tracing::info!/warn!/error!/debug!`，无 `log::` 使用。日志字段结构化（如 `tracing::info!("收到热键事件: {hotkey}")`）。
4. **错误处理**: 使用 `thiserror` 定义 `AppError` / `WatchdogError` / `IpcError`，无手动实现 `std::error::Error`。`?` 操作符传播正确。Tauri command 返回 `Result<T, AppError>`，AppError 实现 `serde::Serialize` 可直接返回前端。
5. **AppState 状态管理**: `Arc<AppState>` 通过 `app.manage()` 注册，commands 通过 `tauri::State<'_, Arc<AppState>>` 访问。trait objects（`Arc<dyn IpcSender>` 等）实现依赖反转。
6. **命名规范**: 函数 snake_case、结构体 PascalCase、常量 SCREAMING_SNAKE_CASE、Trait PascalCase，全部符合规范。
7. **ProcessWatchdog 进程管理**: JobObject 使用 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 确保主进程退出时子进程被终止。`CREATE_NO_WINDOW` 避免弹出控制台。优雅关机三阶段：IPC shutdown → WM_CLOSE → 强制 kill。
8. **IPC 通信通过 trait**: 所有业务命令路径通过 `IpcSender` trait 发送命令（`AppState::send_ipc_command` → `IpcBridge::send_command`）。`IpcManager` 直接调用仅限于初始化回调注册（见 Finding 3）。
9. **管道名称一致**: Rust `asd_ipc` ↔ AHK `\\.\pipe\asd_ipc`。
10. **纯逻辑 crate 无 Tauri 依赖**: Cargo.toml 确认 `asd-domain`、`asd-ipc-protocol`、`asd-application` 作为 path 依赖，不含 tauri/tokio/interprocess/windows 依赖。

## 统计

| 严重级别 | 数量 | 说明 |
|----------|------|------|
| Critical | 0 | 无致命问题 |
| Important | 3 | Finding 1（嵌套锁）、Finding 2（block_in_place 桥接）、Finding 4（文档过时） |
| Minor | 5 | Finding 3（IpcManager 直接调用）、Finding 5（竞态窗口已记录）、Finding 6（unsafe 注释完整）、Finding 7（心跳匹配）、Finding 8（IPC 健壮性） |
| **总计** | **8** | |

### 最关键的 3 个发现摘要

1. **Finding 1（Important）— 嵌套锁获取**: `setup_ipc_and_watchdog` 中存在 `ipc_manager → watchdog` 嵌套锁顺序。当前不死锁（初始化阶段单线程 + 无反向锁顺序），但缺乏文档约束，未来重构可能引入死锁。建议添加锁顺序注释或拆分回调设置。

2. **Finding 2（Important）— block_in_place 桥接同步 trait**: bridge.rs 中 5 处 `block_in_place + block_on` 将同步 trait 方法桥接到 async 实现。符合 AGENTS.md 妥协 #2，但会阻塞 tokio 工作线程。长期建议将 trait 改为 async。

3. **Finding 4（Important）— AGENTS.md 文档过时**: 文档记录 "19 Tauri commands" 实际为 34 个；妥协 #3 描述的 `src-tauri/src/domain/` 和 `application/` 子模块已不存在；Common Patterns 示例的返回类型 `String` 实际为 `AppError`。文档需同步更新。
