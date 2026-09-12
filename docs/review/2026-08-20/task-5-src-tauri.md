# Task 5: Rust src-tauri 主 crate 架构、安全性与代码质量审查

> 审查日期：2026-08-20
> 审查范围：`asd-tauri/src-tauri/` 主 crate（`Cargo.toml`、`src/lib.rs`、`src/main.rs`、`src/bridge.rs`、`src/commands/` 六文件、`src/infrastructure/` 四文件、`src/tests/` 四文件）
> 审查性质：只读审查（未修改任何 .rs / .toml 文件，仅输出本报告）
> 审查维度：Tauri command 标注与数量、bridge trait 实现与 blocking_lock、IpcManager 管道与错误处理、ProcessWatchdog/WatchdogRunner、优雅关机、并发安全、unsafe/unwrap/expect、配置序列化兼容性、tracing 使用、IPC 是否经 IpcSender trait

## 执行摘要

本次通读了 src-tauri 主 crate 全部 14 个源文件与 1 份 `Cargo.toml`，并针对 `#[tauri::command]`、`blocking_lock`/`block_in_place`、`unsafe`、`log::`、`asd_ipc`、`taskkill` 等做了全量检索。共发现 **14 项**问题（**0 Critical、2 Important、12 Minor**）。

**总体判断：主 crate 工程质量整体健康，安全关键路径（进程清理、JobObject、panic hook、IPC 认证）设计严谨且有多层补偿机制，未发现会导致崩溃/数据损坏/架构严重违规的问题。** 关键合规项全部通过：

- ✅ **34 个 Tauri command 全部标注 `#[tauri::command]`**：`config_cmd` 11 个 + `group_cmd` 8 个 + `hotkey_cmd` 2 个 + `recording_cmd` 8 个 + `system_cmd` 5 个 = **34**，与 AGENTS.md「34 Tauri commands」及 `EXPECTED_TAURI_COMMAND_COUNT = 34` 一致。`generate_handler!` 列表与各命令文件一一对应，无遗漏。
- ✅ **IPC 管道名称已集中为常量**：`IPC_PIPE_NAME = "asd_ipc"` 定义于 `lib.rs:31`，`IpcManager::new` 与 `create_listener` 两处调用均引用常量，Rust 侧无散落硬编码（跨语言与 AHK 侧字符串仍存在，见 T5-12）。
- ✅ **进程清理严格限定项目专用进程**：`STALE_PROCESS_NAMES = ["asd_executor.exe"]`，绝不包含 `AutoHotkey64.exe`（`watchdog.rs:572`），并有专项测试 `test_stale_process_names_excludes_generic_autohotkey` 守护。JobObject 使用 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`，叠加 `register_panic_hook` + `cleanup_stale_executor_processes` 双补偿（I36）。
- ✅ **IPC 认证机制存在**（`accept_from_ahk` 首条消息必须为 `auth` 且 token 匹配，`ipc.rs:166-208`），并有指数退避防恶意连接洪泛。
- ✅ **配置序列化兼容性有 roundtrip 测试守护**：`config_compat_tests.rs::test_roundtrip_serialization` 对 `src-tauri/config.json` 与 `tests/fixtures/configs/tests_config.json` 做 `assert_eq!(original, roundtrip)`，验证字段名/结构一致。
- ✅ **tracing 全面使用**：全库检索 `log::` 零命中，日志统一走 `tracing` 宏。
- ✅ **锁顺序一致无反转**：`ipc_manager → watchdog` 顺序在 `setup_ipc_and_watchdog`、`perform_graceful_shutdown`、`setup_ipc_callbacks` 三处一致，`WatchdogBridge` 仅获取 watchdog 锁，未发现锁顺序反转导致的死锁。

**主要风险集中在两点**：一是 `watchdog.rs` 中 4 处手写 `unsafe impl Send/Sync`（soundness 依赖外部 Mutex 保护这一脆弱不变量，T5-01）；二是 `EXPECTED_TAURI_COMMAND_COUNT` 的编译时断言是永真式、不构成真正的数量守护（T5-02）。其余为阻塞调用、魔法数字、死代码、可预测 token、无单实例保护、持锁跨 await 等低风险项。

## 分级统计

| 严重级别 | 数量 | 编号 |
|---------|------|------|
| Critical | 0 | — |
| Important | 2 | T5-01、T5-02 |
| Minor | 12 | T5-03 ~ T5-14 |

---

## 发现清单

### T5-01 — `ProcessWatchdog` / `JobObjectGuard` 手写 `unsafe impl Send/Sync`，soundness 依赖脆弱的外部 Mutex 不变量

- **位置**：`src/infrastructure/watchdog.rs:67,73,499,502`
- **维度**：安全性
- **严重级别**：Important
- **描述**：src-tauri 主 crate 并非 AGENTS.md「纯逻辑 crate 不含 unsafe」的范畴（windows FFI 必然引入 unsafe），但其中 4 处**手写 `unsafe impl`** 是独立于 FFI 的 soundness 关键点，需单独审视：
  - `unsafe impl Send for ProcessWatchdog`（67 行）与 `unsafe impl Sync for ProcessWatchdog`（73 行）：`ProcessWatchdog` 含 `child: Option<std::process::Child>`，而 `Child` 是 `Send + !Sync`，自动派生无法满足 `Sync`，故手工标记。其安全依据（73 行注释）是「所有访问都经过 `Arc<tokio::sync::Mutex<ProcessWatchdog>>`，不存在并发共享引用」。
  - `unsafe impl Send/Sync for JobObjectGuard`（499/502 行）：`JobObjectGuard(HANDLE)` 手工标记 Send/Sync，依据是 Mutex 保护 + `Drop` 仅调用 `CloseHandle`。
- **根因**：为了把「含 `!Sync` 字段」的结构体装入 `Arc<tokio::sync::Mutex<_>>` 并跨线程共享，选择了手工标记而非重构字段组合。该不变量（「`&ProcessWatchdog` 不会被并发获得」）当前成立：所有生产路径都先持锁再取 `&Guard`，`state()`/`restart_count()` 的调用方均立即 `.clone()`（如 `lib.rs:196-197`、`bridge.rs:198`）。
- **风险**：不变量脆弱——`ProcessWatchdog::state()` 返回 `&WatchdogStateEnum`。若未来任何代码把该引用保存到 `guard` 之外（`let s = guard.state(); drop(guard); // 使用 s`），即形成跨锁的共享引用 → 数据竞争 → UB。这正是「看似有 Mutex 保护、实则靠 discipline 维持」的隐患。
- **修复建议**：① 将 `state()` 改为返回 `Clone` 类型（`WatchdogStateEnum` 本身 `Clone + Serialize`），杜绝引用外泄；② 或改用 `parking_lot`/`std::sync::Mutex` + 确保字段本身可 `Sync`；③ 至少在 `state()` 文档上明确「返回的引用不得跨越锁守卫存活」；④ 若可能，将 `Option<Child>` 拆出，使 `ProcessWatchdog` 的数据面可自动 `Sync`。

### T5-02 — `EXPECTED_TAURI_COMMAND_COUNT` 编译时断言是永真式，不构成真正的数量守护

- **位置**：`src/lib.rs:606-615`
- **维度**：代码质量
- **严重级别**：Important
- **描述**：
  ```rust
  pub const EXPECTED_TAURI_COMMAND_COUNT: usize = 34;
  const _: () = { assert!(EXPECTED_TAURI_COMMAND_COUNT == 34); };
  ```
  断言右侧的 `34` 是独立字面量，与 `generate_handler![...]` 列表**无任何绑定关系**。文档注释声称「如果命令数量变化但未更新此值，编译时断言将失败」，实际不会——新增第 35 个 command 而忘记更新时，两个 `34` 仍相等，编译照常通过。
- **根因**：`generate_handler!` 宏在编译期不对外暴露其 item 数量，无法用 const 断言直接计数；作者用「常量自比」的形式伪造了「编译时追踪点」的观感。
- **风险**：给维护者虚假安全感——依赖此断言的人会以为命令数量被自动守护，实际上 AGENTS.md 文档、`test-map.md`、前端 `api.js` 与命令列表的同步仍完全靠手工。
- **修复建议**：① 删掉这个误导性断言；② 或在 `#[cfg(test)]` 中用一个真实校验替代：构建 `tauri::generate_handler` 后统计已注册命令数并与常量比对（需 Tauri 运行时支持）；③ 至少将注释改写为「此常量仅作文档参考，无编译期强制」，避免误导。

### T5-03 — `IpcBridge`/`WatchdogBridge` 使用 `Handle::current().block_on`，脱离异步运行时上下文会 panic

- **位置**：`src/bridge.rs:47,76,196,206,216`
- **维度**：架构设计
- **严重级别**：Minor
- **描述**：`IpcSender`/`ProcessWatcher` trait 方法签名是同步的，`IpcBridge::send_command/send_and_wait` 与 `WatchdogBridge::state/restart_count/reset` 通过 `tokio::task::block_in_place(|| Handle::current().block_on(async {...}))` 桥接异步底层。`Handle::current()` 在**无 tokio 运行时上下文**时（如未来从纯同步线程、普通 `main` 线程、或未初始化 runtiom 的测试/工具路径调用）会直接 panic。
- **根因**：同步 trait 与 async 底层之间的适配选择了「在当前线程上下文直接 block_on」，隐含「所有调用方必在 tauri 异步运行时内」的约束。当前调用链（Tauri command async 上下文、`post_connect_callback` 的 spawn task）满足，但该约束未被编译器或文档强制。
- **风险**：脆弱——`AppState::send_ipc_command` 是 `&self` 同步方法，任何未来的同步调用点（如后台线程、`Drop` 实现、事件回调）都可能触发 panic。
- **修复建议**：① 在文档中明确 `IpcSender::send_command` 必须于 tauri async runtime 内调用；② 或改用 `tauri::async_runtime::block_on`（Tauri 封装的全局 runtime 句柄）替代裸 `Handle::current()`，避免与 tokio worker 线程状态耦合；③ 长期可考虑把 trait 改为 async（需同步改 asd-domain 与 asd-test-harness 的 mock）。

### T5-04 — `spawn_child` 在异步上下文中执行阻塞 I/O（`taskkill` + `Command::spawn`）

- **位置**：`src/infrastructure/watchdog.rs:781`（调用点，`WatchdogRunner::run` 内）→ `spawn_child`（`watchdog.rs:214` 起）
- **维度**：并发安全
- **严重级别**：Minor
- **描述**：`WatchdogRunner::run` 的 async 循环在 `RestartNeeded` 分支持着 `wd` 锁调用 `wd.spawn_child(&path, &token)`。`spawn_child` 首行 `cleanup_stale_executor_processes()` 内部同步执行 `Command::new("taskkill").output()`（`watchdog.rs:594-597`），随后同步 `Command::spawn()`，整个路径是阻塞 I/O，且此时正持有 tokio `Mutex` 锁。
- **根因**：`cleanup_stale_executor_processes` 被设计为同步函数，在启动子进程前无条件调用；`WatchdogRunner::run` 未做 `spawn_blocking` 隔离。
- **风险**：阻塞一个 tokio worker 线程约数十~数百 ms（`taskkill` 冷启动），多核 runtime 下不致死锁，但降低并发吞吐；也延长了 `wd` 锁的持有时间，拖慢状态轮询。
- **修复建议**：将 `cleanup_stale_executor_processes` + `Command::spawn` 包进 `tokio::task::spawn_blocking`（或改用 `tokio::process::Command`），避免在 async 循环内做阻塞系统调用。

### T5-05 — 心跳/接受循环/进程清理直接操作 `IpcManager`，未走 `IpcSender` trait，仅回调注册有 M31 例外文档

- **位置**：`src/lib.rs:140-174`（`spawn_heartbeat_ping`）、`src/lib.rs:117-138`（`spawn_ipc_accept_loop`）
- **维度**：架构设计
- **严重级别**：Minor
- **描述**：AGENTS.md 强制规则「IPC 通信必须通过 `IpcSender` trait，禁止直接调用 `IpcManager`」。`setup_ipc_callbacks` 有 M31 例外文档（仅限初始化阶段回调注册，`lib.rs:216-236`），但 `spawn_heartbeat_ping` 直接调用 `mgr.send(&msg)`/`mgr.is_connected().await`/`mgr.next_seq()`，`spawn_ipc_accept_loop` 直接调用 `mgr.accept_loop(&listener)`，`send_shutdown` 回调亦直接 `mgr.send(...)`——这些均属运行期 IPC 收发，却无同样的例外注释。
- **根因**：heartbeat/accept-loop/shutdown 消息发送属于基础设施生命周期逻辑，作者默认它们与「应用层命令发送」不同，未显式登记为妥协。
- **风险**：规则例外边界不清晰，后续维护者难以判断哪些直接调用是合法的、哪些是违规；也使「仅 `IpcBridge` 经 trait 发送」的抽象边界被稀释。
- **修复建议**：① 为这些生命周期函数补充与 M31 同款的例外注释，明确「仅限 IPC 基础设施心跳/监听/关机，不扩展到应用层命令」；② 或将这些逻辑下沉为 `IpcManager` 自身的方法（它们本就操作 `IpcManager` 内部状态），从 lib.rs 移入 ipc.rs，减少层间泄漏。

### T5-06 — `JOBOBJECTINFOCLASS(9)` 使用魔法数字

- **位置**：`src/infrastructure/watchdog.rs:518`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`SetInformationJobObject(handle, JOBOBJECTINFOCLASS(9), ...)` 用字面量 `9` 表示 `JobObjectExtendedLimitInformation`，与上方 `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` 结构体、`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 标志位形成一套「具名常量混一个无名字面量」的拼装。
- **根因**：未查 windows crate 是否暴露该枚举的具名常量（`JOBOBJECTINFOCLASS` 关联常量），直接用了数值。
- **修复建议**：改用 windows crate 的具名常量（如 `JobObjectExtendedLimitInformation`），或至少加注释说明 `9` 的语义，避免与其它 JobObject 信息类混淆。

### T5-07 — `on_state_change` 回调机制为死代码，且 `set_state` 在持锁时同步触发回调存在重入死锁隐患

- **位置**：`src/infrastructure/watchdog.rs:55,100-101,108-116`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`on_state_change: Option<StateChangeCallback>` 字段与 `set_on_state_change` setter 存在，但全库检索生产代码**零调用**（前端状态同步改由 `lib.rs::spawn_watchdog` 内的每秒轮询完成）。同时 `set_state`（108-116 行）在持有 watchdog 锁的情况下**同步**调用 `cb(&self.state)`；一旦未来有代码注册了一个会重新 `lock().await` 同一 watchdog 的回调，将立即自我死锁。
- **根因**：v4.0 重构后状态同步从「回调推」（push）改为「轮询拉」（pull），但旧的回调字段/setter 未删除，形成半成品 API。
- **修复建议**：删除 `on_state_change`、`StateChangeCallback` 与 `set_on_state_change`；若保留，须改为「先 clone 状态、释放锁再异步/同步调用回调」并禁止回调内重入锁。

### T5-08 — IPC auth token 由时间戳派生且比较非恒定时间

- **位置**：`src/infrastructure/ipc.rs:76-85`（生成）、`ipc.rs:180`（比较 `token != self.auth_token`）
- **维度**：安全性
- **严重级别**：Minor
- **描述**：auth token 形如 `ASD_<自 UNIX_EPOCH 的纳秒数>`，由系统时钟派生；失败回退为 `ASD_FALLBACK_<pid>_<counter>`。比较用普通 `!=`，非恒定时间。两者对本地 named pipe（已受 OS 权限作用域限制）而言风险较低，但 token 本身就是「弱随机」的加固点。
- **根因**：未引入密码学随机源（如 `getrandom`/`rand`），沿用时间戳拼接的轻量实现。
- **修复建议**：① token 改用密码学随机字节（如 `uuid`/`getrandom`），彻底避免可预测性；② 比较改用常量时间（对本地 pipe 价值有限，可仅作为加固项）；③ 至少保留当前退避 + 5s 认证超时作为恶意连接缓解。

### T5-09 — 无单实例保护，二次启动导致 listener 创建失败 + executor 错连到首个实例

- **位置**：`src/lib.rs:117-138`（`spawn_ipc_accept_loop`）、`src/lib.rs:663`（`IpcManager::new(IPC_PIPE_NAME)`）
- **维度**：健壮性
- **严重级别**：Minor
- **描述**：若用户二次启动应用，第二个实例 `create_listener("asd_ipc")` 会因 named pipe 已被首个实例占用而失败，`spawn_ipc_accept_loop` 记录错误后直接 `return`（无重试）；但第二个实例的 `ProcessWatchdog` 仍会 `spawn_child` 出一个新 `asd_executor.exe`，该 executor 会连接第一个实例的监听器并尝试第一个实例的 auth token（不匹配）→ 认证失败循环。整体表现为「第二个实例半残且干扰第一个实例」。
- **根因**：未加 Tauri 单实例插件或进程互斥锁。
- **修复建议**：使用 `tauri-plugin-single-instance`（或等效互斥锁），二次启动时聚焦已有窗口并退出，从根上消除多实例对 named pipe / executor 的抢占与错连。

### T5-10 — `graceful_shutdown` 持有 watchdog 锁横跨多个 await 点（约 5s+）

- **位置**：`src/infrastructure/watchdog.rs:417-461`
- **维度**：并发安全
- **严重级别**：Minor
- **描述**：`perform_graceful_shutdown`（`lib.rs:58-61`）先 `watchdog.lock().await` 再调用 `graceful_shutdown().await`；后者内部 Phase 1（2s）+ Phase 2（3s）的 `wait_for_exit` 在持有锁的情况下多次 `sleep().await`。期间 `spawn_watchdog` 的状态轮询任务（每秒 `wd_clone.lock().await`）会被阻塞等待。
- **根因**：`graceful_shutdown` 被设计为 `&mut self` 的连贯状态转换方法，锁粒度偏粗。
- **风险**：非死锁（关机阶段轮询阻塞无害），但跨 await 持锁违反 tokio 最佳实践，若未来有其它 waitPath 需在关机期间读 watchdog 会被延迟最多 5s+。
- **修复建议**：将 `wait_for_exit` 的轮询拆到锁外（记录 pid 后释放锁再轮询，最后重新加锁做 `cleanup`），或接受文档化此阶段性阻塞。

### T5-11 — 生产代码存在 `Arc::get_mut().expect` 与入口 `expect`（均已文档化）

- **位置**：`src/lib.rs:408`（`Arc::get_mut(&mut app_state).expect(...)`）、`src/lib.rs:757`（`.expect("Tauri 应用启动失败")`）
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`init_app_state` 用 `Arc::get_mut` 在 `AppState::new` 之后设置 `config_path`，并 `.expect` 兜底——其安全依赖「此处 Arc 引用计数为 1」。M33 注释已完整登记该技术债（`AppState::new` 签名稳定、不便加参）与重置 panic 的触发场景。入口 `.expect` 对桌面应用启动失败属可接受。
- **根因**：采用「构造后 setter」而非「构造参数」注入 config_path 的技术债。
- **修复建议**：按 M33 遗留方案，将 `config_path` 移入 `AppState::new`（同步改 asd-application/asd-test-harness 调用方）；或保留但将 `.expect` 替换为 `if let`+`tracing::error` 的优雅降级。

### T5-12 — 管道名称常量定义在 lib.rs，且与 AHK 侧 `ipc_client.ahk` 硬编码字符串存在跨语言重复

- **位置**：`src/lib.rs:31`（常量）、`src-tauri/ahk_executor/ipc_client.ahk:20`（`static PIPE_NAME := "\\.\pipe\asd_ipc"`）
- **维度**：架构设计
- **严重级别**：Minor
- **描述**：Rust 侧已将 `"asd_ipc"` 收敛为 `IPC_PIPE_NAME` 常量（两处引用均走常量，无散落字面量），这是正面的。但常量放在 `lib.rs` 而非 `ipc.rs`，且 `asd_ipc` 字符串在 AHK 执行器侧为独立硬编码，两语言间无编译期一致性保障——任一侧改名都会静默断开通信，只能在运行时靠认证失败/重连暴露。
- **根因**：跨语言常量无法共享，只能靠约定与文档（`lib.rs:30` 注释已提示「必须与 AHK 一致」）。
- **修复建议**：① 将 `IPC_PIPE_NAME` 移入 `infrastructure/ipc.rs` 作为该模块常量，lib.rs 通过 `infrastructure::ipc::IPC_PIPE_NAME` 引用；② 新增一个运行时/集成自检（或 `config_compat_tests` 风格的正则校验 AHK 文件中的 `asd_ipc` 与 Rust 常量一致），把「跨语言字符串一致」纳入测试守护。

### T5-13 — `watchdog.rs` 存在 `cargo fmt` 未覆盖的缩进异常

- **位置**：`src/infrastructure/watchdog.rs:1056`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`test_cleanup_does_not_terminate_current_process` 前的 `#[test]` 属性缩进为 8 空格，而其下 `fn` 为 4 空格，整体格式不齐（`watchdog.rs:1056`），提示该文件（或该段）未被 `cargo fmt` 整理。
- **根因**：编辑后未统一格式化。
- **修复建议**：对 src-tauri 运行 `cargo fmt`，并纳入 CI 的格式检查门禁。

### T5-14 — `begin_restart` / `reset_to_restart` 终止子进程后未 `wait()`

- **位置**：`src/infrastructure/watchdog.rs:361-382`、`390-403`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`begin_restart` 与 `reset_to_restart` 对旧子进程只 `child.kill()` 后即 `self.child = None`（Drop `Child` 而未 `wait()`）。Windows 下进程被 `TerminateProcess` 后会自动释放资源（无 Unix 僵尸概念），影响很小；但若未来跨平台或需要准确知道退出码，会丢失回收信息。`kill_child()`（160-168 行）则正确做了 `kill()` + `wait()`，两者风格不一致。
- **根因**：与 `kill_child` 的实现不一致，漏掉了 `wait()`。
- **修复建议**：统一封装 `kill_and_reap(&mut Child)` 辅助方法，三处（`kill_child`/`begin_restart`/`reset_to_restart`）复用，保证 kill 后必定 wait。