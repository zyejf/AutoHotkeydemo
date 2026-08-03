# Task 7: Rust 安全性与健壮性审查发现

## 审查范围

本次审查覆盖 ASD 技能管理器 v4.0 Rust/Tauri 部分的全部核心代码:

**纯逻辑 crate(禁止 unsafe / Tauri / tokio / interprocess / windows 依赖):**
- `asd-tauri/crates/asd-domain/src/`(config.rs, models.rs, validator.rs, traits.rs, lib.rs)
- `asd-tauri/crates/asd-ipc-protocol/src/`(command.rs, message.rs, error.rs, hotkey_merger.rs, lib.rs)
- `asd-tauri/crates/asd-application/src/`(scheduler.rs, state.rs, config_repository.rs, error.rs, group_service.rs, recording_service.rs, backup_service.rs, time_format.rs, lib.rs)

**主 crate(表现层 + 基础设施):**
- `asd-tauri/src-tauri/src/lib.rs`(应用初始化 + 19 个 Tauri command 注册)
- `asd-tauri/src-tauri/src/bridge.rs`(IpcBridge / TauriEventBridge / WatchdogBridge)
- `asd-tauri/src-tauri/src/infrastructure/ipc.rs`(IpcManager named pipe 通信)
- `asd-tauri/src-tauri/src/infrastructure/watchdog.rs`(ProcessWatchdog + JobObjectGuard)
- `asd-tauri/src-tauri/src/commands/`(config_cmd, group_cmd, hotkey_cmd, recording_cmd, system_cmd)

**AHK 执行器(用于交叉验证 pipe 名称和心跳间隔一致性):**
- `asd-tauri/src-tauri/ahk_executor/ipc_client.ahk`

审查维度包括:unsafe 代码、unwrap/expect 使用、IPC 通信安全、进程管理安全、并发安全、错误传播链、配置序列化兼容性、输入验证、AHK 子进程隔离、named pipe 路径一致性。

---

## 发现清单

### Finding 1

- **位置**: `asd-tauri/src-tauri/src/lib.rs:117` 与 `asd-tauri/src-tauri/src/lib.rs:591`
- **维度**: IPC 通信安全 / 健壮性
- **严重级别**: Important
- **描述**: named pipe 名称 `"asd_ipc"` 以字符串字面量形式硬编码在两处独立调用中——`spawn_ipc_accept_loop` 中的 `infrastructure::ipc::create_listener("asd_ipc")` 与 `run()` 中的 `IpcManager::new("asd_ipc")`。两处必须严格一致才能建立通信,但缺乏单一常量约束,任何一处修改而另一处遗漏将导致 Rust 监听器与 IpcManager 使用不同管道名称,IPC 通信静默失败。
- **根因**: 缺乏常量提取。pipe 名称作为魔法字符串散布在初始化代码中,而非定义为模块级常量(如 `const IPC_PIPE_NAME: &str = "asd_ipc";`)并由两处共用。
- **修复建议**: 在 `infrastructure/ipc.rs` 或 `lib.rs` 顶部定义 `const IPC_PIPE_NAME: &str = "asd_ipc";`,将两处 `"asd_ipc"` 替换为该常量引用。同时考虑在 AHK 端(`ipc_client.ahk`)的 `PIPE_NAME` 定义处添加注释,标注与 Rust 端常量的对应关系,形成跨语言一致性契约。

### Finding 2

- **位置**: `asd-tauri/crates/asd-application/src/error.rs:19-26`
- **维度**: 错误传播链完整性
- **严重级别**: Important
- **描述**: `AppError` 实现了 `Serialize` trait,但实现方式为 `serializer.serialize_str(&self.to_string())`,即把整个错误序列化为一个纯字符串。Tauri command 返回 `Result<T, AppError>` 时,前端通过 `invoke` 收到的错误只是一个字符串消息(如 `"配置错误: ..."`)`),丢失了错误变体类型信息(Config / Ipc / GroupNotFound / Validation / Internal)。前端无法基于错误类型进行差异化处理(例如对 GroupNotFound 自动跳转、对 Validation 高亮字段、对 Ipc 显示重连提示),只能依赖字符串匹配,脆弱且易错。
- **根因**: 序列化实现选择了最简单的字符串形式,未考虑前端需要结构化错误信息进行差异化处理。`thiserror::Error` 派生的 `Display` 实现用于人类可读消息,但不应直接作为序列化输出。
- **修复建议**: 将 `Serialize` 实现改为结构化序列化,例如:
  ```rust
  #[derive(Serialize)]
  struct SerializedAppError {
      kind: &'static str,  // "Config" / "Ipc" / "GroupNotFound" / ...
      message: String,
  }
  impl Serialize for AppError {
      fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
          SerializedAppError {
              kind: match self {
                  AppError::Config(_) => "Config",
                  AppError::Ipc(_) => "Ipc",
                  AppError::GroupNotFound(_) => "GroupNotFound",
                  AppError::Validation(_) => "Validation",
                  AppError::Internal(_) => "Internal",
              },
              message: self.to_string(),
          }.serialize(s)
      }
  }
  ```
  前端可基于 `kind` 字段进行差异化错误处理。

### Finding 3

- **位置**: `asd-tauri/crates/asd-domain/src/config.rs:337-345`
- **维度**: 输入验证 / 配置序列化兼容性
- **严重级别**: Important
- **描述**: `GroupConfig` 的自定义 `Deserialize` 实现中,`holdTriggers` 字段解析失败时通过 `unwrap_or_else` 静默替换为空向量 `Vec::new()`,仅写入 `tracing::warn!` 日志,不返回错误。这意味着如果用户配置文件中 `holdTriggers` 字段格式错误(如类型不匹配、JSON 结构异常),配置仍能加载成功,但 `holdTriggers` 数据被丢弃,用户不会收到任何提示。对于依赖 `holdTriggers` 的 hold 模式,这可能导致按键行为异常而用户难以排查。
- **根因**: 注释说明"holdTriggers 是可选字段,解析失败不应阻止配置加载",但混淆了"字段缺失"(可选,合理)与"字段存在但格式错误"(应报错)两种情况。可选字段应通过 `Option<T>` + `default` 处理,而非对格式错误静默吞掉。
- **修复建议**: 区分"字段缺失"和"字段格式错误"两种情况。字段缺失时返回 `None`(当前行为正确);字段存在但解析失败时,应返回 `serde::de::Error::custom(...)` 让调用方知道配置有问题。如果确实需要容忍格式错误(向后兼容),至少应在日志中包含字段路径和原始值,并在 `ValidationResult` 中添加警告项,让前端能展示给用户。

### Finding 4

- **位置**: `asd-tauri/src-tauri/src/infrastructure/watchdog.rs:170-199`(attach_child)与 `180-191`(JobObject 失败处理)
- **维度**: 进程管理安全 / AHK 子进程隔离
- **严重级别**: Important
- **描述**: `attach_child` 方法中,JobObject 创建(`JobObjectGuard::create()`)或进程分配(`guard.assign(&child)`)失败时,仅记录 `tracing::warn!` 日志,子进程仍被启动并跟踪。JobObject 的作用是确保主进程退出时子进程也被终止(`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`),一旦 JobObject 失败,主进程异常退出(panic、kill -9、系统崩溃)时,AHK 子进程(asd_executor.exe)将成为僵尸进程持续运行,可能继续发送按键影响用户系统。`graceful_shutdown` 仅能处理正常退出场景,无法覆盖主进程崩溃。
- **根因**: JobObject 失败被视为非致命错误,优先保证子进程能启动。但未评估僵尸 AHK 进程的安全风险——一个持续发送按键的失控进程可能干扰用户操作。
- **修复建议**: 两种方案:(1) JobObject 创建/分配失败时返回错误,拒绝启动子进程(严格模式,可能导致应用无法运行);(2) 保持当前行为,但增加补偿机制——在主进程启动时检测并清理遗留的 asd_executor.exe 进程(通过进程名匹配 + PID 文件),并在 `graceful_shutdown` 之外,注册 `panic::set_hook` 或 `std::process::abort` 回调尝试终止子进程。推荐方案 (2),在不影响启动成功率的前提下降低僵尸进程风险。

### Finding 5

- **位置**: `asd-tauri/src-tauri/src/commands/recording_cmd.rs:62-68`(start_recording)、`92-100`(export_recording)、`106-109`(import_recording)、`112-117`(start_validation)
- **维度**: 输入验证
- **严重级别**: Important
- **描述**: recording_cmd 命令层缺少输入验证。`start_recording` 和 `start_validation` 接收 `group_id: String` 参数但未验证是否为空字符串;`export_recording` 接收 `path: String` 未验证是否为空;`import_recording` 同样未验证 `path`。对比 `config_cmd.rs` 中的 `restore_backup`/`delete_backup`/`export_config`/`import_config`/`compare_configs` 都有 `if xxx.trim().is_empty()` 验证,recording_cmd 的验证不一致。虽然 `recording_service` 内部可能进行验证(未在本次审查中确认),但 command 层缺乏验证会导致错误延迟到 service 层才暴露,错误消息可能不够友好,且不符合防御性编程原则。
- **根因**: recording_cmd 是在 config_cmd 之后实现的,未遵循已建立的输入验证模式。命令层验证应作为第一道防线,与 service 层验证形成纵深防御。
- **修复建议**: 在 recording_cmd 各命令函数开头添加与 config_cmd 一致的输入验证:
  ```rust
  if group_id.trim().is_empty() {
      return Err(AppError::Validation("分组 ID 不能为空".to_string()));
  }
  if path.trim().is_empty() {
      return Err(AppError::Validation("路径不能为空".to_string()));
  }
  ```

### Finding 6

- **位置**: `asd-tauri/src-tauri/src/lib.rs:335`、`391`、`402`
- **维度**: 并发安全
- **严重级别**: Important
- **描述**: 三处使用 `tokio::task::block_in_place(|| watchdog.blocking_lock())` 或 `ipc_manager_arc.blocking_lock()` 模式获取 tokio Mutex 的同步锁。这是 AGENTS.md "已知架构妥协 #2" 记录的模式,用于在同步上下文(setup 阶段)中访问 tokio 异步锁。`block_in_place` 会通知 tokio 运行时当前线程将阻塞,允许运行时调度其他任务到不同线程,避免完全死锁。但该模式存在约束:(1) 必须在 tokio 多线程运行时上下文中调用,在当前线程运行时或非 tokio 上下文中会 panic;(2) `blocking_lock` 持锁期间不能 `.await`,否则可能死锁。经审查,这三处持锁期间均无 `.await` 调用(仅同步操作如 `set_send_shutdown`、`setup_ipc_callbacks`、`spawn_child`),风险可控。但 `setup_ipc_callbacks`(line 391 调用)内部 line 335 又获取了 watchdog 锁,形成 `ipc_manager_arc → watchdog` 的锁顺序,需确保全局锁顺序一致。
- **根因**: IpcSender/ProcessWatcher trait 定义为同步方法(`fn send_command(&self, ...) -> Result<...>`,无 async),但实现需要访问 tokio 异步锁保护的 IpcManager/ProcessWatchdog,只能通过 `block_in_place + blocking_lock` 桥接。这是 trait 设计与异步运行时之间的阻抗失配。
- **修复建议**: 短期:保持现状,但在 `setup_ipc_callbacks` 中获取 watchdog 锁(line 335)处添加注释,明确标注锁顺序(ipc_manager → watchdog),并验证 `perform_graceful_shutdown` 等其他路径的锁顺序一致。长期:考虑将 `IpcSender`/`ProcessWatcher` trait 改为 async(`async fn send_command(...)`),消除 `blocking_lock` 需求,但这是破坏性变更,需评估影响面。

### Finding 7

- **位置**: `asd-tauri/crates/asd-application/src/config_repository.rs:67-95`(load_from_file)
- **维度**: 错误传播链完整性
- **严重级别**: Minor
- **描述**: `load_from_file` 方法在配置文件解析失败(serde_json 错误)或读取失败(非 NotFound 的 IO 错误)时,返回 `Config::default()` 而非错误。虽然写入了 `tracing::error!`/`tracing::warn!` 日志,但调用方无法区分"配置文件正常加载"和"配置文件损坏已回退到默认"。用户可能在使用默认配置(所有热键为 F10、无分组)的情况下不知情,导致按键行为与预期不符。相比之下,`load_from_file_checked` 方法返回 `Result<Config, ConfigLoadError>`,能正确传播错误。`lib.rs:583` 中应用启动时使用的是 `load_from_file_checked`,这是正确的,但 `load_from_file` 作为公开方法仍可能被误用。
- **根因**: `load_from_file` 设计为"宽容"加载,优先保证应用能启动,但牺牲了错误可见性。`#[deprecated]` 注解应加在此方法上(类似 `save_to_file` 的处理),引导使用 `load_from_file_checked`。
- **修复建议**: 为 `load_from_file` 添加 `#[deprecated(since = "4.0.0", note = "使用 load_from_file_checked 替代,获取详细错误信息")]` 注解,与 `save_to_file` 的弃用处理保持一致。

### Finding 8

- **位置**: `asd-tauri/src-tauri/src/lib.rs:375`
- **维度**: 健壮性
- **严重级别**: Minor
- **描述**: `init_app_state` 中使用 `Arc::get_mut(&mut app_state).expect("AppState should be uniquely held during setup")` 获取可变引用以调用 `set_config_path`。当前在 `setup` 阶段调用,此时 `app_state` 刚创建且未克隆给其他持有者,`Arc::get_mut` 必定返回 `Some`,expect 不会触发。但这是脆弱的隐式假设——如果未来代码重构在 `init_app_state` 之前将 `app_state` 的克隆传递给其他组件(如提前注册到 Tauri manage),`Arc::get_mut` 将返回 `None` 并 panic。
- **根因**: `set_config_path` 需要 `&self`(通过内部 RwLock),但 `Arc::get_mut` 提供 `&mut self`,使用 `get_mut` 是为了在 `Arc::new(AppState::new(...))` 之后设置路径,而非将 `config_path` 作为 `AppState::new` 的参数。
- **修复建议**: 将 `config_path` 作为 `AppState::new` 的参数传入,消除对 `Arc::get_mut` 的依赖;或将 `set_config_path` 的调用移到 `Arc::new` 之前(通过先创建 `AppState` 再包装为 `Arc`)。这样避免 `expect` 并消除未来重构的 panic 风险。

### Finding 9

- **位置**: `asd-tauri/src-tauri/src/commands/group_cmd.rs:84-89`(toggle_group)、`104-110`(delete_group)
- **维度**: 输入验证
- **严重级别**: Minor
- **描述**: `toggle_group` 和 `delete_group` 命令接收 `group_id: String` 参数但未在 command 层验证是否为空,直接委托给 `group_service::toggle_group`/`delete_group`。虽然 `group_service` 内部有 `if group_id.trim().is_empty()` 验证(group_service.rs:56, 119),但 command 层验证不一致——同文件的 `get_group_detail`(line 96-98)有显式空字符串验证。这种不一致增加了维护成本,且 command 层验证能更早拒绝无效请求,避免进入 service 层。
- **根因**: group_cmd 中各命令的输入验证风格不统一,部分命令依赖 service 层验证,部分在 command 层验证。
- **修复建议**: 在 `toggle_group` 和 `delete_group` command 函数开头添加 `if group_id.trim().is_empty() { return Err(AppError::Validation("分组 ID 不能为空".to_string())); }`,与 `get_group_detail` 保持一致。或反过来,移除 `get_group_detail` 的 command 层验证,统一依赖 service 层——但前者更符合防御性编程原则。

---

## 无问题声明(正面发现)

以下维度经审查未发现问题,代码质量良好:

### 1. unsafe 代码合规性(最高优先级)— 无问题

- **纯逻辑 crate(asd-domain, asd-ipc-protocol, asd-application)中无任何 `unsafe` 代码**,完全符合 AGENTS.md 规则要求。
- `src-tauri` 中的 `unsafe` 代码全部集中在 `watchdog.rs`,用于 Windows API 调用(CreateJobObjectW、OpenProcess、AssignProcessToJobObject、CloseHandle、EnumWindows、PostMessageW),这是合理且必要的。
- 所有 `unsafe impl Send/Sync` 都有详细的 SAFETY 注释(watchdog.rs:60-66, 68-72, 494-495, 497-498),说明安全性依赖的外部条件(Mutex 保护)和未来变更约束。
- `RawBoxGuard`(watchdog.rs:544-562)采用 RAII 模式确保 `Box::from_raw` 在任何退出路径下执行,防止 `EnumWindows` 回调异常导致的内存泄漏,设计良好。
- `enum_windows_callback`(watchdog.rs:576-597)对 `lparam` 指针有 null 检查(line 578-581),解引用安全。

### 2. unwrap/expect 使用(panic 风险)— 无 Critical 问题

- 生产代码中 `unwrap`/`expect` 使用极为克制,几乎全部出现在 `#[cfg(test)]` 模块中,这是可接受的。
- 生产代码中仅有的 `expect` 调用:
  - `lib.rs:685` `.expect("Tauri 应用启动失败")` — 应用启动失败时 panic 是合理的,无法恢复。
  - `lib.rs:375` `Arc::get_mut(...).expect(...)` — 见 Finding 8(Minor)。
- `config_repository.rs`、`ipc.rs`、`bridge.rs`、`watchdog.rs`、`state.rs`、`group_service.rs` 的生产代码中**无 unwrap/expect**,全部使用 `?` 操作符或 `map_err` 进行错误传播。
- `atomic_write`(config_repository.rs:16-45)使用 `unwrap_or_default()` 处理时间戳,安全。
- `BACKOFF_DURATIONS.get(restart_count).copied().unwrap_or(...)`(watchdog.rs:369-372)使用 `unwrap_or` 提供默认值,安全。

### 3. IPC 通信安全 — 无 Critical 问题

- **named pipe 路径一致性**: Rust 端 `"asd_ipc"` 经 interprocess crate 的 `GenericNamespaced` 转换为 `\\.\pipe\asd_ipc`,与 AHK 端 `ipc_client.ahk:20` 的 `static PIPE_NAME := "\\.\pipe\asd_ipc"` 完全一致。
- **认证机制**: `accept_from_ahk`(ipc.rs:166-208)要求首条消息必须是 `auth` 类型且 token 匹配,5 秒超时,token 不匹配返回 `AuthFailed`。token 通过环境变量 `ASD_AUTH_TOKEN` 传递(watchdog.rs:245),对本地 IPC 可接受。
- **消息大小限制**: `MAX_MESSAGE_SIZE = 64KB`(ipc.rs:17),发送和接收均检查。接收时使用 `reader.take(MAX_MESSAGE_SIZE)` 限制读取(ipc.rs:438),超大消息有 1MB 残余数据丢弃机制(ipc.rs:454-466),防止 OOM。
- **指数退避**: `accept_loop`(ipc.rs:256-267)对认证失败使用指数退避(1, 2, 4, 8, 16, 30 秒),有位移量上限 `.min(5)` 防止溢出(ipc.rs:265),处理正确。
- **pending response 清理**: `cleanup_stale_pending`(ipc.rs:637-652)定期清理超时的 pending response,防止内存泄漏。`PENDING_CLEANUP_MAX_AGE = 30s` 与 `send_and_wait` 的 timeout 有约束关系(ipc.rs:380-385 有警告日志)。
- **管道断裂处理**: `send`/`recv` 方法正确处理 `BrokenPipe` 错误,清理连接并通知 `pipe_broken` 回调。关机期间(`shutting_down` 标志)抑制回调(ipc.rs:596-599)。

### 4. 进程管理安全 — 无 Critical 问题(见 Finding 4 的 Important 建议)

- **MAX_RESTART_ATTEMPTS = 10**(watchdog.rs:24),符合 AGENTS.md 要求。超过后进入 `Failed` 状态,等待 `reset_watchdog` 命令或优雅关机。
- **三阶段优雅关机**(watchdog.rs:414-458):Phase 1 IPC shutdown(2s 超时)→ Phase 2 WM_CLOSE(3s 超时)→ Phase 3 强制 kill。设计合理,逐步升级。
- **心跳超时匹配**: Rust 端 `HEARTBEAT_TIMEOUT = 3s` + `HEARTBEAT_TIMEOUT_COUNT = 3` ≈ 6 秒判定 Hung(watchdog.rs:23, 21);AHK 端 `HEARTBEAT_TIMEOUT_MS = 5000`(ipc_client.ahk:23)。AHK 端 5 秒无 ping 即断开重连,Rust 端 6 秒判定 Hung,时间窗口匹配合理——AHK 端更积极断开,Rust 端有更大容忍度。
- **CREATE_NO_WINDOW**(watchdog.rs:241):子进程不弹出控制台窗口,避免干扰用户。
- **退避策略**: `BACKOFF_DURATIONS`(watchdog.rs:25-36)为 1, 2, 4, 8, 30, 30, 30, 30, 30, 30 秒,指数退避合理。`stable_heartbeat_count >= 5` 时重置重启计数器(watchdog.rs:262-270),允许进程恢复后重置退避。

### 5. 并发安全 — 无 Critical 问题

- **锁顺序一致**: 经审查 `perform_graceful_shutdown`(lib.rs:43-57)和 `setup_ipc_and_watchdog`(lib.rs:390-406)的锁获取顺序,`ipc_manager → watchdog` 顺序一致,未发现反向锁顺序,无死锁风险。
- **bridge.rs 使用 `block_in_place + block_on` 模式**(bridge.rs:29-49, 58-111):比直接 `blocking_lock` 更安全,`block_in_place` 通知 tokio 运行时当前线程将阻塞,允许调度其他任务。持锁期间在 `block_on` 的 async 块内,锁在 async 上下文中获取但通过 `block_in_place` 保证不会死锁。
- **AppState 并发设计**(state.rs):使用 `parking_lot::RwLock` 保护 `config_state` 和 `active_hotkeys`,TOCTOU 窗口在文档中明确说明(state.rs:73-79, 170-178)。`save_config_atomic` 有完整的回滚机制(state.rs:363-388):磁盘写入失败时,重新获取写锁,检查版本号,回滚内存状态。`AtomicBool` 用于 `emergency_mode`/`hold_mode_enabled`/`validation_in_progress`,使用 `compare_exchange` 保证原子性(system_cmd.rs:30, 57-60, 106-108)。
- **`shutting_down` 标志**: IPC 和 Watchdog 都有 `shutting_down: Arc<AtomicBool>`,关机时设置,抑制不必要的回调(ipc.rs:596-599, watchdog.rs:662-666, 699-702)。
- **关机保护**: `shutdown_guard: AtomicBool` + `compare_exchange`(lib.rs:35-41)防止窗口关闭和托盘退出并发触发重复关机。

### 6. 错误传播链完整性 — 无 Critical 问题(见 Finding 2 的 Important 建议)

- `IpcError`(error.rs)有 10 个变体,覆盖 ConnectionClosed、MessageTooLarge、EmptyMessage、JsonError、IoError、Timeout、ChannelClosed、PipeBroken、NameError、AuthFailed。
- `AppError`(error.rs)有 5 个变体(Config, Ipc, GroupNotFound, Validation, Internal)。
- `From<IpcError> for AppError`(error.rs:28-32)实现错误转换,`From<std::io::Error> for IpcError` 和 `From<serde_json::Error> for IpcError`(ipc-protocol/error.rs:25-49)覆盖常见错误源。
- `?` 操作符在 `config_repository.rs`、`ipc.rs`、`group_service.rs`、`state.rs` 中广泛使用,错误传播链完整。
- `IpcError::from(io::Error)` 优先使用 `ErrorKind::BrokenPipe` 判断(ipc-protocol/error.rs:28),比字符串匹配更可靠,有字符串匹配作为后备(line 33-38)。
- Tauri command 返回 `Result<T, AppError>`,AppError 实现 Serialize 可返回前端(见 Finding 2 的类型信息丢失问题)。

### 7. 配置序列化兼容性 — 无 Critical 问题(见 Finding 3 的 Important 建议)

- `Config` 结构体的 serde 属性(config.rs)与 AHK 端 config.json 格式完全匹配:
  - `#[serde(rename = "CONTROL_HOTKEYS")]` / `#[serde(rename = "GroupSettings")]` / `#[serde(rename = "HoldSettings")]` / `#[serde(rename = "lastModified")]`
  - `ControlHotkeys` 字段:`releaseAllHolds`、`showStatus`、`toggleAll`、`toggleHoldMode` 与 AHK 端 camelCase 一致
  - `GroupConfig` 自定义 Serialize/Deserialize,字段名(hotkey, mode, keyPressDuration, name, holdKeys, holdMode, holdPattern, holdTriggers)与 AHK 端一致
  - `ModeData` 各变体的字段名(keys, intervals, delays, pressKeys, pressDelays, holdDuration, autoRepeat, repeatInterval, seqInterval, groups, joystickId)与 AHK 端一致
- `GroupConfig::deserialize`(config.rs:297-403)对必填字段(hotkey, mode)使用 `missing_field` 错误,对未知 mode 返回 `unknown mode` 错误,验证严格。
- 可选字段使用 `Option<T>` + `default` + `skip_serializing_if = "Option::is_none"`,序列化时 None 字段被跳过,减少配置文件体积。
- `HoldData::hold_duration` 为 `u64`(必填),`JoystickHoldData::hold_duration` 为 `Option<u64>`(可选,支持无限持续),设计区分清晰(config.rs:156-177, 233-259)。
- `GroupItem` 使用 `#[serde(tag = "type")]` 内部标签(config.rs:262),与 AHK 端 `{"type":"periodic",...}` 格式匹配。

### 8. AHK 子进程隔离 — 无 Critical 问题(见 Finding 4 的 Important 建议)

- `CREATE_NO_WINDOW` 标志(watchdog.rs:241)避免子进程弹出控制台窗口。
- `ASD_AUTH_TOKEN` 环境变量(watchdog.rs:245)传递认证 token,不通过命令行参数(避免在进程列表中暴露)。
- JobObject 确保子进程随主进程退出(当 JobObject 创建成功时)。
- `graceful_shutdown` 三阶段关机确保正常退出时子进程被清理。
- 子进程标准输入/输出/错误:子进程通过 named pipe 通信,不直接使用 stdio(由 AHK 执行器内部管理)。

### 9. named pipe 路径一致性 — 无问题

- 已在 IPC 通信安全部分确认:Rust 端 `"asd_ipc"` → interprocess 转换为 `\\.\pipe\asd_ipc`,AHK 端 `\\.\pipe\asd_ipc`,完全一致。
- 测试中使用 `asd_test_harness::unique_pipe_name(tag)` 生成唯一管道名(test-harness/lib.rs:275),避免并发测试碰撞,有 16 线程 × 100 次的并发唯一性测试(test-harness/lib.rs:335-375)。

---

## 统计

### 发现总数: 9

### 各级别数量

| 严重级别 | 数量 | 编号 |
|---------|------|------|
| Critical | 0 | — |
| Important | 6 | Finding 1, 2, 3, 4, 5, 6 |
| Minor | 3 | Finding 7, 8, 9 |

### 各维度分布

| 维度 | 发现数量 | 编号 |
|------|---------|------|
| IPC 通信安全 | 1 | Finding 1 |
| 错误传播链完整性 | 2 | Finding 2, 7 |
| 输入验证 | 2 | Finding 3, 5 |
| 进程管理安全 / AHK 子进程隔离 | 1 | Finding 4 |
| 并发安全 | 1 | Finding 6 |
| 健壮性 | 1 | Finding 8 |
| 输入验证(command 层一致性) | 1 | Finding 9 |

### 无问题维度

| 维度 | 状态 |
|------|------|
| unsafe 代码合规性 | 无问题 — 纯逻辑 crate 无 unsafe,src-tauri 的 unsafe 都有 SAFETY 注释 |
| unwrap/expect 使用 | 无 Critical — 生产代码几乎无 unwrap/expect,仅在测试和不可恢复的启动阶段使用 |
| named pipe 路径一致性 | 无问题 — Rust 端与 AHK 端完全一致 |
| 心跳超时匹配 | 无问题 — Rust ~6s 判定 Hung,AHK 5s 断开,时间窗口合理 |
| 配置序列化兼容性 | 无 Critical — serde rename 与 AHK config.json 格式匹配(Finding 3 是 Minor 次要问题) |

### 最关键的 3 个发现摘要

1. **Finding 4(Important)— JobObject 失败时无僵尸进程补偿机制**: JobObject 创建/分配失败时子进程仍被启动,主进程崩溃时 AHK 子进程可能成为僵尸进程持续发送按键。建议增加启动时遗留进程清理 + panic hook 补偿机制。

2. **Finding 2(Important)— AppError 序列化丢失类型信息**: AppError 序列化为纯字符串,前端无法区分错误类型进行差异化处理。建议改为结构化序列化(包含 kind + message 字段)。

3. **Finding 1(Important)— pipe 名称硬编码在两处**: `"asd_ipc"` 在 lib.rs 两处独立调用中硬编码,修改一处遗漏另一处将导致 IPC 静默失败。建议提取为模块级常量。

### 整体评价

ASD 技能管理器 v4.0 的 Rust/Tauri 部分代码质量整体优良:
- 纯逻辑 crate 严格遵守无 unsafe、无 Tauri/tokio 依赖的规则
- 生产代码中 unwrap/expect 使用极为克制,错误传播链完整
- 并发设计考虑了 TOCTOU 窗口并在文档中明确记录
- IPC 通信有认证、大小限制、指数退避等安全机制
- 配置序列化与 AHK 端格式匹配,有原子写入和回滚机制

主要改进方向集中在:输入验证一致性(recording_cmd/group_cmd)、错误信息结构化(AppError 序列化)、常量提取(pipe 名称)、僵尸进程补偿(JobObject 失败 fallback)。这些问题不会导致立即崩溃,但影响长期可维护性和用户体验。
