# Task 4: Rust 纯逻辑 crate 架构与代码质量审查

> 审查日期：2026-08-20
> 审查范围：`asd-domain` / `asd-ipc-protocol` / `asd-application` 三个纯逻辑 crate（含 `asd-test-harness` 作为 dev-dependency 边界佐证）
> 审查性质：只读审查（未修改任何 .rs / .toml 文件）
> 审查维度：workspace 依赖关系、禁用依赖合规、trait 抽象解耦、新增模块职责边界、错误类型（thiserror）、unsafe / unwrap / expect、命名规范、ConfigValidator 校验覆盖

## 执行摘要

本次通读了 3 个纯逻辑 crate 的全部 14 个源文件与 4 份 `Cargo.toml`，并针对禁用依赖、`std::fs`、`unsafe`、手写 `std::error::Error`、`unwrap/expect` 等做了全量检索。共发现 **10 项**问题（**0 Critical、1 Important、9 Minor**）。

**总体判断：架构符合 AGENTS.md 规范，工程质量健康。** 关键合规项全部通过：

- ✅ **5-crate workspace 依赖关系正确**：`asd-domain → asd-ipc-protocol`；`asd-application → asd-domain → asd-ipc-protocol`；`asd-test-harness` 仅作为 `asd-application` 与各测试的 dev-dependency（`asd-test-harness/Cargo.toml` 及 `asd-application` 的 `[dev-dependencies]` 均验证无误）。
- ✅ **禁用依赖零引入**：`asd-domain` / `asd-ipc-protocol` / `asd-application` 三份 `Cargo.toml` 均无 `tokio` / `tauri` / `interprocess` / `windows` / 文件 I/O crate（`tempfile` 仅作为 application 的 dev-dependency）。
- ✅ **`std::fs` 生产代码仅集中在 `config_repository.rs`**：全库检索 `std::fs|fs::`，生产代码命中全部落在 `asd-application/src/config_repository.rs`；`backup_service.rs` / `recording_service.rs` 通过 `ConfigRepository::read_file_to_string / save_to_path / ensure_dir_all / list_dir_files / delete_file` 委派 I/O（I26 注释已登记）。
- ✅ **trait 抽象解耦合理**：`traits.rs` 中 `IpcSender` / `EventEmitter` / `ProcessWatcher` 定义仅引用 `IpcCommand` / `IpcMessage` / `WatchdogStateEnum` 与 `serde_json::Value`，未引用任何禁用类型；三个 trait 的增量方法均提供默认实现（`send_and_wait` / `send_message` / `reset` 返回「not supported」），遵守「新增 trait 方法必须提供默认实现」强制规范。
- ✅ **错误类型全部使用 thiserror**：`AppError`、`IpcError`、`ConfigLoadError` 均为 `#[derive(thiserror::Error)]`；全库检索 `std::error::Error` 零命中，无手写实现。
- ✅ **无 unsafe 代码**：全库检索 `unsafe` 零命中。
- ✅ **生产代码无 panic 类调用**：全库检索 `.unwrap()` / `.expect()` / `panic!` / `todo!` / `unimplemented!`，生产代码（`#[cfg(test)]` 之外）零命中——`config_repository.rs` 的 `atomic_write` 使用 `unwrap_or_default()` 安全兜底；其余命中全部位于 `mod tests` 或 `tests/` 内。
- ✅ **新增模块职责边界清晰**：`backup_service`（备份/恢复/导入导出对比）、`group_service`（分组切换/热键注册/批量操作/排序）、`recording_service`（录制/验证状态机）、`time_format`（时间格式化纯函数）职责单一、无跨层耦合，且均通过 `AppState` 方法 + `IpcSender` trait 访问状态与 IPC，无直接 I/O 泄漏。
- ✅ **命名规范符合要求**：crate 名 snake_case、结构体/枚举 PascalCase、函数/方法 snake_case、常量 SCREAMING_SNAKE_CASE（`VALID_MODES` / `PERIODIC_MODES` / `SEQUENCE_MODES` / `VALID_HOTKEY_KEYS`）。

**主要风险集中在一点**：ConfigValidator 对「控制热键」（`CONTROL_HOTKEYS.*` 五个全局热键）的校验偏弱——空值静默放行、且与分组热键之间无冲突检测（T4-04），这使得「紧急停止」等安全关键热键可能以空值通过校验。其余为依赖声明冗余、错误类型不统一、封装一致性等低风险项。

## 分级统计

| 严重级别 | 数量 | 编号 |
|---------|------|------|
| Critical | 0 | — |
| Important | 1 | T4-04 |
| Minor | 9 | T4-01、T4-02、T4-03、T4-05、T4-06、T4-07、T4-08、T4-09、T4-10 |

---

## 发现清单

### T4-01 — asd-domain 声明 `tracing` 依赖但完全未使用

- **位置**：`asd-tauri/crates/asd-domain/Cargo.toml:11`
- **维度**：架构设计
- **严重级别**：Minor
- **描述**：`asd-domain/Cargo.toml` 声明 `tracing = { workspace = true }`，但全库检索 `tracing` 在 `asd-domain` 目录中仅命中该 `Cargo.toml` 声明一行，`src/` 与 `tests/` 中零使用。AGENTS.md「Rust/Tauri Internal (Workspace)」依赖表亦未为 asd-domain 登记 `tracing`，与声明不一致。
- **根因**：workspace 统一管理依赖（`[workspace.dependencies]` 预置 `tracing`），复制模板时一并带入但未被用到，形成「声明未消费」的冗余依赖。
- **修复建议**：从 `asd-domain/Cargo.toml` 移除 `tracing`，保持领域 crate 最小依赖面；若未来确实需要日志，再按需补回并同步更新 AGENTS.md 依赖表。

### T4-02 — 已 deprecate 的 `SkillManager` 与 AppState 职责重叠，且 AGENTS.md 文档描述失真

- **位置**：`asd-tauri/crates/asd-application/src/scheduler.rs:6-13`
- **维度**：架构设计
- **严重级别**：Minor
- **描述**：`scheduler.rs` 中的 `SkillManager` 已标记 `#[deprecated]`，deprecation note 明确指向 AppState 与 `group_service`，但其仍通过 `lib.rs:pub mod scheduler;` 暴露并被编译进 crate，形成与 `AppState`/`group_service` 职责重叠的死代码。更关键的是，AGENTS.md「Key Files」仍将 `scheduler.rs` 描述为「SkillManager（Arc\<dyn IpcSender\>）」，而实际实现是持有 `HashMap<String, SkillGroup> + HashMap<String, String>` 的普通结构体，`IpcSender` 以参数形式传入（`send_ipc_command(ipc_sender, cmd)`），与文档「Arc\<dyn IpcSender\>」严重不符。
- **根因**：v4.0 重构将调度职责迁入 `AppState` 后，旧 `SkillManager` 以 deprecate 方式保留过渡，但 (1) 未彻底移除、(2) AGENTS.md 中对应行未随重构更新。
- **修复建议**：确认无外部调用后删除 `scheduler.rs` 与 `lib.rs` 中的 `pub mod scheduler`；同步修正 AGENTS.md「Key Files」表中 scheduler.rs 的描述。

### T4-03 — asd-ipc-protocol 为仅 1 处 `debug!` 引入 `tracing`，依赖登记缺失

- **位置**：`asd-tauri/crates/asd-ipc-protocol/Cargo.toml:10`、`asd-tauri/crates/asd-ipc-protocol/src/hotkey_merger.rs:33`
- **维度**：架构设计
- **严重级别**：Minor
- **描述**：`asd-ipc-protocol` 声明 `tracing = { workspace = true }`，实际仅 `hotkey_merger.rs:33` 的 `tracing::debug!("HotkeyMerger: 丢弃无热键的消息...")` 一处使用；AGENTS.md 依赖表将 asd-ipc-protocol 登记为「serde, serde_json, thiserror」（未含 tracing），登记与实际引入不一致。协议层 crate 引入日志框架属于边界上的轻微模糊。
- **根因**：`tracing` 被 workspace 默认预置，`HotkeyMerger` 为了输出丢弃消息的调试信息而顺手使用，未评估「纯协议格式 crate 是否应承担日志职责」。
- **修复建议**：二选一——(a) 移除 `tracing` 依赖，将 `push` 对「无热键消息」的丢弃改为通过返回值/计数暴露给调用方（应用层决定是否记录）；(b) 保留但执行彻底：在 AGENTS.md 依赖表中为 asd-ipc-protocol 补登记 `tracing`，使文档与实现一致。

### T4-04 — ConfigValidator 控制热键空值静默放行 + 无「控制热键 vs 分组热键」冲突检测

- **位置**：`asd-tauri/crates/asd-domain/src/validator.rs:90-94`（`validate_config` 对 5 个控制热键的校验）、`137-139`（`validate_hotkey_format` 空串提前返回）
- **维度**：代码质量 / 配置校验
- **严重级别**：Important
- **描述**：`validate_config` 对 `control_hotkeys.emergency / release_all_holds / show_status / toggle_all / toggle_hold_mode` 仅调用 `validate_hotkey_format`，而该函数第 137-139 行对空字符串**直接 `return`（无 error、无 warning）**。因此一个 `"emergency": ""` 或 `"toggleAll": ""` 的配置会静默通过 `validate_config` 并被 `state.save_config_atomic` 持久化（`save_config_atomic` 依赖 `is_valid()`，仅看 errors）。同时 `validate_duplicate_hotkeys` 只比对分组热键之间，未比对「控制热键」与「分组热键」的冲突（如某分组热键与 `emergency` 相同，无告警）。对照 T3-03：AHK 侧控制热键已有同类缺口的相同问题；Rust 侧相比 AHK 多了格式 warning，但空值仍完全无感。对比相同文件中对分组热键 `validate_hotkey_format` 之后**刻意补了** `group.hotkey.is_empty()` 的 error 分支（validator.rs:120-122），控制热键路径缺失对应的空值 error。
- **根因**：`validate_config` 对控制热键复用 `validate_hotkey_format`，而该函数以「空串不参与格式校验、也不报错」为约定（对可选字段合理），却未意识到控制热键是**必填安全关键字段**，需要独立的空值 error 逻辑。
- **修复建议**：在 `validate_config` 中对 5 个控制热键逐一补 `is_empty()` 的 `add_error("_global", "<field>", "...不能为空")`；并扩展 `validate_duplicate_hotkeys` 或新增函数，将控制热键值纳入去重集合，与分组热键做交叉冲突检测。

### T4-05 — 无效热键键名仅产生 warning 而非 error（需在文档中显式声明为刻意权衡）

- **位置**：`asd-tauri/crates/asd-domain/src/validator.rs:152-158`
- **维度**：代码质量 / 配置校验
- **严重级别**：Minor
- **描述**：`validate_hotkey_format` 对不在 `VALID_HOTKEY_KEYS` 名单内的键（如 `"INVALID_KEY"`）只 `add_warning`，不 `add_error`。由于 `save_config_atomic` 依赖 `is_valid()`（`valid` 由 `errors` 决定），无效热键配置仍会被持久化。这是刻意设计（AHK 键名全集难以穷举，且支持自定义/Unicode 键名），但该权衡未在 AGENTS.md 或代码注释中显式记录。
- **根因**：为避免误报，将「疑似非法格式」降级为 warning，但未在文档中澄清「warning 不阻断保存」这一行为边界。
- **修复建议**：在 `validate_hotkey_format` 上方补充注释，或在 AGENTS.md「配置校验」说明中记录「热键格式只做 warning 级建议，不阻断保存」，避免后续维护者误判为校验遗漏。

### T4-06 — `atomic_write` 为自由函数而非 ConfigRepository 方法，封装口径不一致

- **位置**：`asd-tauri/crates/asd-application/src/config_repository.rs:16`、`asd-tauri/crates/asd-application/src/recording_service.rs:2`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`atomic_write` 是 `config_repository.rs` 中的顶层自由函数（`pub fn atomic_write`），而非 `ConfigRepository` 的关联方法。`recording_service.rs:2` 以 `use crate::config_repository::atomic_write;` 直接引入该自由函数（`recording_service.rs:306` 调用），而 `backup_service.rs` 通过 `ConfigRepository::save_to_path` 委托写入。两种路径打破了「I26 集中封装 std::fs」承诺的统一入口形式——虽然 `std::fs` 调用本身仍在 `config_repository.rs` 内（规则未破坏），但「写文件」能力通过两种抽象面暴露，削弱了封装边界。
- **根因**：`atomic_write` 被定义为自由函数以方便 `save_to_path` 内部复用，但未将其纳入 `ConfigRepository` 的统一 API 面，`recording_service` 直接跨过 `ConfigRepository` 引用该自由函数。
- **修复建议**：将 `atomic_write` 改为 `ConfigRepository` 的 `pub fn atomic_write`（或至少 `pub(crate)`），`recording_service` 统一改走 `ConfigRepository::atomic_write` / `save_to_path`，保持 I/O 唯一入口。

### T4-07 — ConfigRepository 错误返回类型不统一（String vs 类型化错误）

- **位置**：`asd-tauri/crates/asd-application/src/config_repository.rs:105（ConfigLoadError）、119（String）、126（String）、148（String）`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`ConfigRepository` 内错误类型混用：`load_from_file_checked` 返回类型化的 `Result<Config, ConfigLoadError>`，而 `load_from_path` / `save_to_path` / `read_file_to_string` / `ensure_dir_all` / `list_dir_files` / `delete_file` 均返回 `Result<_, String>`。调用方（`backup_service` / `recording_service` / `state`）需用 `map_err(AppError::Config)` 或 `map_err(AppError::Internal)` 手动把 `String` 包进 `AppError`，错误信息以字符串模板散落，丢失了结构化错误类型（如 FileNotFound vs ParseError 的区分）。
- **根因**：`load_from_file_checked` 是后补的「带错误信息的替代方法」（M32），与既有 `String` 风格并存，未统一。
- **修复建议**：逐步将 `ConfigRepository` 的返回值统一为类型化错误（复用 `ConfigLoadError` 或新增 `ConfigStoreError`），保持单一错误抽象；短期内至少在文档注释中说明两种风格的分工与迁移方向。

### T4-08 — `AppError::message()` 对 Io 变体返回空串，序列化依赖手动分支特殊处理

- **位置**：`asd-tauri/crates/asd-application/src/error.rs:42-44（message 的 Io 分支返回 ""）、58-61（Serialize 手动分支）`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`AppError::message()` 对 `AppError::Io(_)` 返回空串 `""`（因为 `std::io::Error` 无法借助 `&str` 返回），序列化时靠 `impl Serialize for AppError` 中 `match` 分支对 Io 单独用 `e.to_string()` 处理。这使 `kind_str()`、`message()`、`Serialize` 三处逻辑需同步维护，任何一个变体的纯字符串分支新增后又忘了在 `Serialize`/`message` 同步，就会产生不一致（当前 Io 是唯一被特殊处理的变体，其余变体的 message 为构建时传入的 `String`）。
- **根因**：为了让 `message()` 返回 `&str`（避免拷贝），采用了「`message()` 返回引用 + Io 特判返回空串」的折中，牺牲了一致性。
- **修复建议**：将 `message()` 改为返回 `Cow<'_, str>`（Io 分支用 `e.to_string()` 构造 owned），删除 `Serialize` 中的 Io 特判，使三处逻辑统一收敛。

### T4-09 — `Config::default()` 的 `version` 仍为 "3.0"，与项目 v4.0 不符

- **位置**：`asd-tauri/crates/asd-domain/src/config.rs:63`
- **维度**：代码质量
- **严重级别**：Minor
- **描述**：`Config::default_config()` 将 `version` 置为 `Some("3.0".to_string())`，但项目当前为 v4.0（AGENTS.md 主题即「ASD 技能管理器 v4.0」）。当配置文件不存在或解析失败回退到默认配置时（`load_from_file` 的 NotFound/ParseError 分支），会写入 `"version": "3.0"`，与 Rust/Tauri 实际版本语义不符，可能干扰依赖 `version` 字段的兼容性/迁移逻辑（如 `config_compat_tests`）。
- **根因**：默认配置在 v3.0 阶段建立后未随 v4.0 升级同步更新版本号。
- **修复建议**：将默认版本号更新为 `"4.0"`（或与 `workspace.package.version` 保持单一来源），并检查依赖该默认 version 的兼容性测试是否需要调整。

### T4-10 — 测试代码直接使用 `std::fs`，与 AGENTS.md「std::fs 仅在 ConfigRepository」的字面规则存在张力

- **位置**：`asd-tauri/crates/asd-application/src/state.rs:882/900/901`（`#[cfg(test)]` 模块内）、`asd-application/tests/*.rs`（backup_service_tests.rs / concurrency_tests.rs / cross_crate_tests.rs / e2e_dataflow_tests.rs）
- **维度**：架构设计 / 规则表述
- **严重级别**：Minor
- **描述**：AGENTS.md 强制规则表述为「std::fs 仅在 asd-application 的 ConfigRepository 中使用」。生产代码严格满足此约束（T4-06 之外的所有生产 `std::fs` 均在 `config_repository.rs`），但 `state.rs` 的测试模块与多个 `tests/` 文件直接调用 `std::fs::read_to_string / write / create_dir_all` 构造/断言测试固件。虽然测试代码不参与生产运行时，豁免是合理惯例，但规则未声明「测试代码豁免」，导致「字面规则」与「实际代码」不一致。
- **根因**：规则以「生产代码 I/O 泄漏」为立法本意，未明确测试代码的边界。
- **修复建议**：在 AGENTS.md 该条规则处补充「（测试代码 `#[cfg(test)]` 与 `tests/` 内允许直接使用 std::fs 构造临时固件）」的豁免说明，使规则语义与代码一致，避免后续审查误报。