# Task 5: Rust 纯逻辑 crate 架构+质量审查发现

## 审查范围

本次审查覆盖 ASD 技能管理器 v4.0 的三个纯逻辑 crate 及 workspace 根配置：

| Crate | 审查文件 |
|-------|---------|
| `asd-domain` | `src/lib.rs`, `src/config.rs`, `src/models.rs`, `src/validator.rs`, `src/traits.rs`, `Cargo.toml` |
| `asd-ipc-protocol` | `src/lib.rs`, `src/command.rs`, `src/message.rs`, `src/error.rs`, `src/hotkey_merger.rs`, `Cargo.toml` |
| `asd-application` | `src/lib.rs`, `src/scheduler.rs`, `src/state.rs`, `src/config_repository.rs`, `src/error.rs`, `src/group_service.rs`, `src/recording_service.rs`, `src/backup_service.rs`, `src/time_format.rs`, `Cargo.toml` |
| Workspace 根 | `asd-tauri/Cargo.toml` |

审查日期：2026-08-03
审查性质：只读审查（未修改任何源代码文件）

## Crate 依赖关系验证结果

### 依赖关系图（实际验证）

```
asd-ipc-protocol ──→ (serde, serde_json, thiserror, tracing)
asd-domain ──→ asd-ipc-protocol ──→ (serde, serde_json, thiserror, tracing)
asd-domain ──→ (serde, serde_json, indexmap, thiserror, tracing)
asd-application ──→ asd-domain ──→ asd-ipc-protocol
asd-application ──→ (serde, serde_json, indexmap, thiserror, tracing, chrono, parking_lot)
asd-test-harness ──→ asd-domain + asd-ipc-protocol + asd-application
asd-tauri (src-tauri) ──→ asd-application ──→ asd-domain ──→ asd-ipc-protocol
```

### 验证结论

| 检查项 | 结果 |
|--------|------|
| 循环依赖 | 无（依赖链单向：application → domain → ipc-protocol） |
| 禁用依赖（tokio/tauri/interprocess/windows） | **未发现**（三个纯逻辑 crate 的 Cargo.toml 均无禁用依赖） |
| `unsafe` 关键字 | **未发现**（三个 crate 的 src/ 下所有 .rs 文件均无 unsafe 代码） |
| I/O 泄漏到 asd-domain | **未发现**（asd-domain 和 asd-ipc-protocol 的 src/ 下无 std::fs 使用） |
| Miri 兼容性前提 | 满足（无 unsafe，纯逻辑 crate 可通过 Miri 验证） |

### 与 AGENTS.md 文档声明的差异

| AGENTS.md 声明 | 实际情况 | 差异 |
|---------------|---------|------|
| "4-crate workspace 架构" / "4 members" | workspace 实际有 5 个成员（含 `asd-test-harness`） | 文档漂移 |
| asd-ipc-protocol 依赖：serde, serde_json, thiserror | 实际还包含 `tracing` | 文档遗漏 |
| asd-domain 依赖：asd-ipc-protocol, serde, serde_json, indexmap, thiserror | 实际还包含 `tracing` | 文档遗漏 |
| asd-application 依赖：...thiserror, tracing | 实际还包含 `chrono`, `parking_lot` | 文档遗漏 |

## 发现清单

### Finding 1
- **位置**: `asd-tauri/crates/asd-application/src/backup_service.rs:110,116,166,230,312` 和 `asd-tauri/crates/asd-application/src/recording_service.rs:314`
- **维度**: 架构合规性
- **严重级别**: Important
- **描述**: `std::fs` 在 asd-application 的生产代码中被 `backup_service.rs` 和 `recording_service.rs` 直接使用，超出 AGENTS.md 规定的 ConfigRepository 范围。具体使用点：
  - `backup_service.rs:110` — `std::fs::create_dir_all(&backup_dir)`（创建备份目录）
  - `backup_service.rs:116` — `std::fs::read_dir(&backup_dir)`（列出备份文件）
  - `backup_service.rs:166` — `std::fs::create_dir_all(&backup_dir)`（创建备份目录）
  - `backup_service.rs:230` — `std::fs::remove_file(&backup_path)`（删除备份文件）
  - `backup_service.rs:312` — `std::fs::read_to_string(path)`（导入配置时读取文件）
  - `recording_service.rs:314` — `std::fs::read_to_string(path)`（导入录制数据时读取文件）
- **根因**: AGENTS.md "Rust/Tauri 规则" 明确规定 "⚠️ 强制：...任何涉及文件 I/O 的 crate（std::fs 除外，仅在 asd-application 的 ConfigRepository 中使用）"。backup_service 和 recording_service 的文件操作未通过 ConfigRepository 统一封装，而是直接调用 `std::fs`。这违反了 "I/O 泄漏修复" 设计决策（关键设计决策 #2）的约束边界，该决策要求将 I/O 集中到 ConfigRepository 以确保 domain crate 无文件 I/O——虽然 domain 层确实无 I/O，但 application 层的 I/O 也应按文档约束集中在 ConfigRepository。
- **修复建议**: 将 backup_service.rs 和 recording_service.rs 中的文件 I/O 操作委托给 ConfigRepository 或新建的专用 I/O 模块封装。例如：
  - 在 ConfigRepository 中新增 `read_file_to_string(path) -> Result<String, AppError>` 和 `write_file_atomic(path, content)` 等通用方法
  - backup_service 的目录操作（create_dir_all, read_dir, remove_file）可封装为 `BackupRepository` 或扩展 ConfigRepository
  - recording_service 的 import/export 可复用 ConfigRepository 的 `atomic_write` 和新增的 read 方法
  - 更新 AGENTS.md 文档，明确 application 层 I/O 的允许范围

### Finding 2
- **位置**: `asd-tauri/crates/asd-ipc-protocol/src/command.rs:48-51`（IpcCommand::Ping, Shutdown）vs `asd-tauri/src-tauri/ahk_executor/executor.ahk`（case 分支）
- **维度**: 架构合规性（IpcCommand 同步性）
- **严重级别**: Important
- **描述**: IpcCommand 枚举有 13 个 variant，其中 `ping` 和 `shutdown` 两个 variant 在 AHK 执行器 `executor.ahk` 的 `case` 分支中无对应处理。executor.ahk 的 action 分支仅包含 11 个：`toggle_group`, `register_hotkey`, `unregister_hotkey`, `emergency_release`, `hold_mode_toggle`, `start_recording`, `stop_recording`, `pause_recording`, `resume_recording`, `start_validation`, `stop_validation`。AGENTS.md 强制规则要求 "新增 IpcCommand variant 必须同步更新 asd-ipc-protocol/src/command.rs 和对应的 AHK 执行器处理逻辑"。
- **根因**: `ping` 和 `shutdown` 可能在 IPC 客户端层（`ipc_client.ahk`）而非命令分发层（`executor.ahk`）处理。`IpcMessage::ping()` 设置 `r#type: "ping"`（非 action），`IpcMessage::shutdown()` 设置 `r#type: "shutdown"`（非 action）。但 `IpcCommand::Ping` 和 `IpcCommand::Shutdown` 通过 `IpcMessage::command()` 转换后会产生 `action: "ping"` 和 `action: "shutdown"`，这些 action 在 executor.ahk 中无 case 处理，可能被静默忽略或落入默认分支。
- **修复建议**: 
  1. 确认 `IpcCommand::Ping` 和 `IpcCommand::Shutdown` 是否通过 `IpcMessage::command()` 发送（如果是，则 executor.ahk 需要补充 case 分支）
  2. 如果 ping/shutdown 仅通过 `IpcMessage::ping()`/`IpcMessage::shutdown()` 构造函数发送（type 而非 action），则在 ipc_client.ahk 中确认有 type 级处理
  3. 在 AGENTS.md 或代码注释中明确记录 ping/shutdown 的处理层级，避免后续开发者误用

### Finding 3
- **位置**: `AGENTS.md` → "数据结构约定" → "Rust" → IpcCommand 示例
- **维度**: 架构合规性（文档漂移）
- **严重级别**: Important
- **描述**: AGENTS.md "数据结构约定" 章节展示的 IpcCommand 示例与实际代码完全不符：
  - 文档示例：`StartGroup { id: usize }`, `StopGroup { id: usize }`, `StopAll`, `UpdateConfig { config: Config }`
  - 实际代码：`ToggleGroup { group_id: String, active: bool, ... }`, `RegisterHotkey`, `UnregisterHotkey`, `StartRecording`, `StopRecording`, `PauseRecording`, `ResumeRecording`, `EmergencyRelease`, `Ping`, `Shutdown`, `HoldModeToggle`, `StartValidation`, `StopValidation`
  文档列出的 4 个示例 variant 在实际代码中**一个都不存在**，且字段类型也不同（文档用 `id: usize`，实际用 `group_id: String`）。
- **根因**: IpcCommand 经历过重大重构（从 StartGroup/StopGroup 模式改为 ToggleGroup 模式），但 AGENTS.md 的数据结构约定示例未同步更新。
- **修复建议**: 更新 AGENTS.md "数据结构约定" 章节的 IpcCommand 示例，使用实际代码中的 variant 名称和字段类型，或直接引用 `asd-ipc-protocol/src/command.rs`。

### Finding 4
- **位置**: `AGENTS.md` → "支持的执行模式" 表格 vs `asd-tauri/crates/asd-domain/src/config.rs:4-8`（VALID_MODES）和 `config.rs:120-131`（ModeData enum）
- **维度**: 架构合规性（文档漂移）
- **严重级别**: Important
- **描述**: AGENTS.md "支持的执行模式" 表格列出 7 种模式（periodic, sequence, hybrid, hold, enhanced_periodic, enhanced_sequence, enhanced_hybrid），但实际代码支持 10 种模式——额外包含 3 个 joystick 模式：
  - `joystick_periodic`（`JoystickPeriodicData`）
  - `joystick_sequence`（`JoystickSequenceData`）
  - `joystick_hold`（`JoystickHoldData`）
  
  这些模式在 `VALID_MODES` 常量、`ModeData` 枚举、`GroupConfig` 反序列化、`ConfigValidator::validate_mode_data` 中均有完整实现，但 AGENTS.md 完全未记录。
- **根因**: joystick 模式作为新增功能被加入代码，但 AGENTS.md 的模式表格未同步更新。
- **修复建议**: 在 AGENTS.md "支持的执行模式" 表格中补充 3 个 joystick 模式及其必需字段：
  - `joystick_periodic`: `pressKeys`, `intervals`, `joystickId`(可选)
  - `joystick_sequence`: `pressKeys`, `delays`, `joystickId`(可选)
  - `joystick_hold`: `holdDuration`(可选), `autoRepeat`(可选), `repeatInterval`(可选), `joystickId`(可选)

### Finding 5
- **位置**: `AGENTS.md` → "Rust/Tauri 架构（4-Crate Workspace）" vs `asd-tauri/Cargo.toml:3-9`
- **维度**: 架构合规性（文档漂移）
- **严重级别**: Important
- **描述**: AGENTS.md 多处声称 "4-crate workspace 架构" 和 "resolver = "2"，4 members"，但 `asd-tauri/Cargo.toml` 的 workspace 实际有 5 个成员：
  ```toml
  members = [
      "crates/asd-domain",
      "crates/asd-ipc-protocol",
      "crates/asd-application",
      "crates/asd-test-harness",   # ← 文档未提及
      "src-tauri",
  ]
  ```
  `asd-test-harness` crate 完全未在 AGENTS.md 的架构章节、Crate 依赖关系图、关键设计决策中记录。该 crate 依赖全部三个纯逻辑 crate + tempfile，作为测试工具 crate 存在。
- **根因**: asd-test-harness 作为第 5 个 crate 被加入 workspace，但 AGENTS.md 未同步更新架构描述。
- **修复建议**: 
  1. 更新 AGENTS.md 中所有 "4-crate" / "4 members" 表述为 "5-crate" / "5 members"
  2. 在 "Crate 依赖关系" 图中补充 asd-test-harness
  3. 在架构表中补充 asd-test-harness 的定位说明（测试工具 crate）
  4. 在 Subdirectories 表格中补充 `asd-tauri/crates/asd-test-harness/` 条目

### Finding 6
- **位置**: `AGENTS.md` → "Key Files" → `asd-domain/src/validator.rs | ConfigValidator（213 tests）` vs 实际 `validator.rs`
- **维度**: 代码质量（文档准确性）
- **严重级别**: Minor
- **描述**: AGENTS.md Key Files 表格声称 `ConfigValidator（213 tests）`，但实际 `validator.rs` 中仅有 48 个 `#[test]` 函数。AGENTS.md "测试覆盖" 章节又称 "asd-domain 125" 个测试（两者已互相矛盾：213 > 125）。validator.rs 的 48 个测试 + config.rs 的 31 个测试 = 79 个单元测试，加上 integration_tests 后达到 125 是合理的，但 "213 tests" 的数字明显过高且无依据。
- **根因**: 测试数量声明可能来自旧版本或包含参数化展开（但 Rust 标准测试不自动参数化），文档长期未校准。
- **修复建议**: 更正 AGENTS.md Key Files 中 validator.rs 的测试数量。建议使用 `cargo test -p asd-domain -- --list` 输出的实际测试数作为基准，或在文档中标注统计日期。

### Finding 7
- **位置**: `asd-tauri/crates/asd-domain/src/validator.rs:184-185`
- **维度**: 代码质量
- **严重级别**: Minor
- **描述**: `validate_cross_fields` 方法中存在冗余的 None 检查：
  ```rust
  if group.mode == "hold"
      && (group.hold_keys.is_none() || group.hold_keys.as_ref().is_none_or(|k| k.is_empty()))
  ```
  `Option::is_none_or(predicate)` 在 Option 为 None 时已返回 true，因此前置的 `group.hold_keys.is_none() ||` 是冗余的。条件可简化为 `group.hold_keys.as_ref().is_none_or(|k| k.is_empty())`。
- **根因**: 开发者可能对 `is_none_or` 语义不熟悉（该方法在 Rust 1.82.0 稳定），添加了防御性的冗余检查。
- **修复建议**: 移除冗余的 `group.hold_keys.is_none() ||`，简化为 `group.hold_keys.as_ref().is_none_or(|k| k.is_empty())`。

### Finding 8
- **位置**: `asd-tauri/crates/asd-application/src/scheduler.rs:14-15`
- **维度**: 代码质量
- **严重级别**: Minor
- **描述**: `SkillManager` 结构体的 `ipc_sender` 字段被标记为 `#[allow(dead_code)]`，实际上该字段确实从未通过 `self.ipc_sender` 使用。所有 IPC 相关方法（`send_ipc_command`, `emergency_release`, `hold_mode_toggle`）都接收 `ipc_sender: &dyn IpcSender` 作为参数，而非使用实例字段。该结构体已标记 `#[deprecated(since = "3.1.0")]`，建议迁移到 AppState。
- **根因**: SkillManager 在重构为 AppState 的过程中，IPC 调用方式从实例字段改为参数传递，但保留了无用字段。
- **修复建议**: 由于 SkillManager 已废弃，可在下次清理时移除 `ipc_sender` 字段及其 `#[allow(dead_code)]` 标注。短期内保持现状可接受（废弃代码）。

### Finding 9
- **位置**: `asd-tauri/crates/asd-application/src/recording_service.rs:249-250`
- **维度**: 代码质量（可维护性）
- **严重级别**: Minor
- **描述**: `validate_recording_data` 函数中硬编码了模式列表：
  ```rust
  let needs_intervals = ["periodic", "enhanced_periodic", "joystick_periodic"].contains(&mode);
  let needs_delays = ["sequence", "enhanced_sequence", "joystick_sequence"].contains(&mode);
  ```
  这些模式列表与 `asd_domain::config::VALID_MODES` 存在重复维护风险。虽然语义不同（这里是"需要 intervals 的模式"子集，而非全部有效模式），但新增模式时需要在多处更新。
- **根因**: 缺少对模式分类的集中定义，每个需要按模式特征分组的函数都自行硬编码。
- **修复建议**: 考虑在 asd-domain 中定义模式分类辅助函数，如 `mode_needs_intervals(mode: &str) -> bool` 和 `mode_needs_delays(mode: &str) -> bool`，集中维护模式特征映射。

### Finding 10
- **位置**: `asd-tauri/crates/asd-application/src/error.rs:5-17`
- **维度**: 代码质量（错误处理）
- **严重级别**: Minor
- **描述**: `AppError` 实现了 `From<IpcError>` 但未实现 `From<std::io::Error>`。config_repository.rs 和 backup_service.rs 中的文件 I/O 错误通过 `format!("...{e}")` 转为 String，再包装为 `AppError::Config(String)` 或 `AppError::Internal(String)`，原始 `io::Error` 的类型信息（ErrorKind）丢失，无法通过 `downcast` 或模式匹配恢复。
  
  对比 `asd-ipc-protocol/src/error.rs` 的 `IpcError`，后者实现了 `From<std::io::Error>` 并区分 `PipeBroken` 和 `IoError`，错误保留更完整。
- **根因**: AppError 的变体全部接收 String，未使用 `#[source]` 保留源错误。这是为了支持 `Serialize`（序列化为字符串给前端）的权衡。
- **修复建议**: 可为 AppError 增加 `Io(#[source] std::io::Error)` 变体或使用 `#[from]` 派生，同时保持 Serialize 实现。短期内通过 String 传播可接受，但长期建议改进错误链。

### Finding 11
- **位置**: `asd-tauri/crates/asd-application/src/state.rs:145-148, 159-162`
- **维度**: 代码质量（可见性设计）
- **严重级别**: Minor
- **描述**: `set_emergency_mode` 和 `set_hold_mode_enabled` 方法为 `pub` 可见性，但文档注释明确标注 "仅用于测试代码。生产代码应使用 system_cmd::emergency_release/clear_emergency" 和 "生产代码应使用 system_cmd::toggle_hold_mode"。这两个方法绕过了命令层的 `compare_exchange` 保护，直接 `store` 写入，存在测试/生产边界模糊风险。
- **根因**: 为了让 src-tauri 的测试代码和命令层代码都能访问，选择了 `pub` 可见性，但未通过 `#[cfg(test)]` 或 `pub(crate)` 限制。
- **修复建议**: 考虑将这两个方法改为 `#[cfg(test)]` 或 `pub(crate)` 并在测试模块中通过 trait 暴露。如果 src-tauri 测试也需要，可在 asd-test-harness 中提供测试辅助。短期内保持 `pub` + 文档警告可接受。

### Finding 12
- **位置**: `asd-tauri/crates/asd-application/src/state.rs:89-90`
- **维度**: 代码质量
- **严重级别**: Minor
- **描述**: `AppState` 的 `watchdog` 字段被标记为 `#[allow(dead_code)]`，但该字段实际在 `reset_watchdog()` 方法（第 307 行）中通过 `self.watchdog.reset()` 使用。`#[allow(dead_code)]` 标注与实际使用不符，可能是历史遗留——该字段仅在 `ProcessWatcher::reset()` 被覆盖时才"有效"，而默认实现返回 Err。
- **根因**: 当 `ProcessWatcher` 的实现不覆盖 `reset()` 时，`watchdog.reset()` 调用无实际效果，字段在功能上"接近死代码"，但语法上确实被使用。
- **修复建议**: 移除 `#[allow(dead_code)]` 标注（因为字段确实被使用），或添加注释说明为何需要该标注。

## 无问题声明

以下检查项经审查**未发现问题**，特此声明：

| 检查项 | 验证方法 | 结果 |
|--------|---------|------|
| 禁用依赖（tokio/tauri/interprocess/windows） | Grep 搜索三个 crate 的 Cargo.toml | **未发现**任何禁用依赖 |
| `unsafe` 代码 | Grep 搜索三个 crate 的 src/*.rs | **未发现**任何 unsafe 关键字 |
| I/O 泄漏到 asd-domain | Grep 搜索 asd-domain/src/*.rs 的 std::fs | **未发现**（asd-domain 无文件 I/O） |
| I/O 泄漏到 asd-ipc-protocol | Grep 搜索 asd-ipc-protocol/src/*.rs 的 std::fs | **未发现**（asd-ipc-protocol 无文件 I/O） |
| 循环依赖 | 分析 Cargo.toml 依赖链 | **无循环**（单向：application → domain → ipc-protocol） |
| trait 默认实现 | 审查 traits.rs | IpcSender 的 `send_and_wait`/`send_message` 有默认实现；ProcessWatcher 的 `reset` 有默认实现。符合"新增 trait 方法必须提供默认实现"规则 |
| thiserror 使用 | 审查 error.rs 文件 | `IpcError` 和 `AppError` 均使用 `#[derive(Debug, thiserror::Error)]`，符合"使用 thiserror 定义错误类型"规则 |
| `#[tauri::command]` 宏 | 不适用（三个纯逻辑 crate 无 Tauri command） | N/A（纯逻辑 crate 不应包含 Tauri command） |
| IPC 通信通过 IpcSender trait | 审查 state.rs 和 scheduler.rs | 所有 IPC 调用通过 `Arc<dyn IpcSender>` 或 `&dyn IpcSender`，未直接依赖 IpcManager |
| tracing 日志使用 | 审查所有源文件 | 三个 crate 均使用 `tracing::info!`/`warn!`/`error!`/`debug!`，未使用 `log` crate |
| 命名规范 | 审查所有公开类型 | Crate 名 snake_case ✓；结构体/枚举/Trait PascalCase ✓；函数 snake_case ✓；常量 SCREAMING_SNAKE_CASE ✓；模块 snake_case ✓ |
| Miri 兼容性前提 | 无 unsafe 代码 | 满足 Miri 验证前提（0 unsafe） |
| 架构妥协 #1 约束边界 | 审查 traits.rs | asd-domain 仅使用 IpcCommand/IpcMessage 数据结构（serde 序列化），不含 IPC 传输逻辑。符合约束边界 |
| ConfigValidator 覆盖度 | 审查 validator.rs | 10 种模式均有 mode_data 类型匹配校验、空值校验、零值校验；热键格式校验、重复热键检测、跨字段校验完整。覆盖度良好 |
| IpcCommand variant 数量 | 计数 command.rs | 13 个 variant，与 AGENTS.md "13 variants" 声明一致 |
| IpcMessage 构造函数 | 审查 message.rs | 提供 command/response/ping/pong/execute/result/shutdown/hotkey_event/heartbeat/auth/error_response 共 11 个构造函数，覆盖完整 |
| HotkeyMerger 设计 | 审查 hotkey_merger.rs | 使用 HashMap 去重，merge_window 可配置，Default 实现合理（100ms 窗口）。flush 使用 drain 清空，无状态泄漏 |
| 错误传播 `?` 操作符 | 审查所有 Result 返回函数 | `?` 操作符使用正确，配合 `From` impl 实现错误传播。config_repository 返回 `Result<_, String>` 为已知设计（非 AppError） |

## 统计

| 严重级别 | 数量 |
|---------|------|
| Critical | 0 |
| Important | 5 |
| Minor | 7 |
| **合计** | **12** |

### Critical 级别发现（0 项）

无。三个纯逻辑 crate 的核心架构合规性良好：
- 无禁用依赖（tokio/tauri/interprocess/windows）
- 无 unsafe 代码
- 无 I/O 泄漏到 domain 层
- 无循环依赖

### Important 级别发现（5 项）

1. **Finding 1**: std::fs 在 backup_service.rs 和 recording_service.rs 中直接使用，超出 AGENTS.md 规定的 ConfigRepository 范围
2. **Finding 2**: IpcCommand 的 ping/shutdown variant 在 AHK executor.ahk 中无对应 case 处理（需确认是否在 ipc_client.ahk 层处理）
3. **Finding 3**: AGENTS.md 数据结构约定中 IpcCommand 示例变体名与实际代码完全不符（StartGroup/StopGroup vs ToggleGroup 等）
4. **Finding 4**: AGENTS.md 支持的执行模式表格遗漏 3 个 joystick 模式（joystick_periodic/joystick_sequence/joystick_hold）
5. **Finding 5**: AGENTS.md 声称 "4-crate workspace" 但实际有 5 个成员（asd-test-harness 未记录）

### Minor 级别发现（7 项）

6. **Finding 6**: AGENTS.md 声称 ConfigValidator 有 213 tests，实际 validator.rs 仅 48 个 #[test]
7. **Finding 7**: validator.rs 第 185 行 is_none() 冗余检查
8. **Finding 8**: scheduler.rs SkillManager.ipc_sender 字段为死代码（已废弃结构体）
9. **Finding 9**: recording_service.rs 硬编码模式列表，未复用 VALID_MODES
10. **Finding 10**: AppError 缺少 From<std::io::Error> 实现，I/O 错误经 String 传播丢失类型信息
11. **Finding 11**: state.rs set_emergency_mode/set_hold_mode_enabled 为 pub 但文档标注"仅用于测试"
12. **Finding 12**: state.rs watchdog 字段标注 #[allow(dead_code)] 但实际被使用

### 最关键的 3 个发现摘要

1. **Finding 1（std::fs 范围越界）**: 这是架构合规性问题中最重要的一项。AGENTS.md 将 std::fs 的使用范围明确限定在 ConfigRepository，但 backup_service.rs（5 处）和 recording_service.rs（1 处）的生产代码直接调用 std::fs。这违反了 "I/O 集中化" 的设计意图，虽然不构成 Critical（因为 asd-application 本身允许 I/O），但破坏了约束边界的一致性，新增 I/O 操作时容易继续分散。

2. **Finding 2（IpcCommand 同步性）**: AGENTS.md 强制要求 "新增 IpcCommand variant 必须同步更新 AHK 执行器处理逻辑"。ping 和 shutdown 两个 variant 在 executor.ahk 中无 case 分支，可能意味着这两个命令被静默忽略，或在 ipc_client.ahk 层处理。需要验证实际的 IPC 消息流（是通过 IpcMessage::command() 发送 action，还是通过 IpcMessage::ping()/shutdown() 发送 type）。

3. **Finding 3/4/5（文档漂移）**: AGENTS.md 作为项目的强制规则文档，存在多处与实际代码不符的描述：IpcCommand 示例变体名全错、执行模式表少 3 项、workspace 成员数错误。这些漂移会误导开发者，特别是新成员在参照 AGENTS.md 理解架构时会产生认知偏差。建议优先校准文档。
