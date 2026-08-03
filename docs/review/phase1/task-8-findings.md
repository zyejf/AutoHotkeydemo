# Task 8: Rust 测试覆盖与质量审查发现

审查日期：2026-08-03
审查范围：`D:\1demo\AutoHotkeydemo\asd-tauri` 下所有 Rust 测试资产
审查模式：只读（未修改任何源代码）

## 审查范围

本次审查覆盖以下 Rust 测试资产：

| 类别 | 路径 | 文件数 |
|------|------|--------|
| asd-domain 单元/集成测试 | `crates/asd-domain/src/*.rs`、`crates/asd-domain/tests/*.rs` | 4 + 1 |
| asd-ipc-protocol 单元/集成测试 | `crates/asd-ipc-protocol/src/*.rs`、`tests/*.rs` | 4 + 1 |
| asd-application 单元/集成测试 | `crates/asd-application/src/*.rs`、`tests/*.rs` | 8 + 7 |
| asd-test-harness 工具 crate | `crates/asd-test-harness/src/lib.rs` | 1 |
| src-tauri 单元测试 | `src-tauri/src/**/*.rs` 内联 `#[cfg(test)]` | 12 |
| src-tauri 集成测试 | `src-tauri/src/tests/*.rs`、`src-tauri/tests/*.rs` | 4 + 1 |
| 基准测试 | `src-tauri/benches/benchmarks.rs` | 1 |
| 模糊测试 | `src-tauri/fuzz/fuzz_targets/*.rs` | 5 |
| E2E 测试 | `e2e/specs/*.spec.js` | 9 |
| 测试固件 | `tests/fixtures/configs/tests_config.json`、`e2e/fixtures/test_config.json`、`e2e/fixtures/key_receiver.ahk` | 3 |
| 测试文档 | `docs/test-map.md`、`e2e/docs/*.md` | 3 |

---

## 测试数量统计（实际 vs 声明）

### Rust 测试函数（`#[test]` + `#[tokio::test]`）

| Crate | 声明（AGENTS.md / test-map.md） | 实际 | 差异 | 备注 |
|-------|--------------------------------|------|------|------|
| asd-domain | 125 | **125** | 0 | 完全一致（config 31 + validator 48 + models 3 + integration 43） |
| asd-ipc-protocol | 71 | **71** | 0 | 完全一致（command 3 + message 24 + error 5 + hotkey_merger 6 + integration 33） |
| asd-application | 175 | **176** | +1 | state.rs 实际 36 vs 声明 35 |
| asd-test-harness | 0 | **0** | 0 | 一致（仅工厂函数，无自测） |
| asd-tauri (src-tauri) | 134 | **147** | **+13** | 见下方细分 |
| **总计** | **506+** | **519** | **+13** | — |

### src-tauri 测试数量差异细分

| 文件 | 声明 | 实际 | 差异 |
|------|------|------|------|
| `src/infrastructure/ipc.rs` | 35 | 35 | 0 |
| `src/infrastructure/watchdog.rs` | 21 | 21 | 0 |
| `src/tests/ipc_tests.rs` | 26 | 26 | 0 |
| `src/tests/watchdog_integration_tests.rs` | 14 | **17** | **+3** |
| `src/tests/config_compat_tests.rs` | 11 | 11 | 0 |
| `src/tests/bridge_tests.rs` | **未列出** | **10** | **+10（test-map.md 漏登记）** |
| `src/commands/config_cmd.rs` | 7 | 7 | 0 |
| `src/commands/system_cmd.rs` | 6 | 6 | 0 |
| `src/commands/hotkey_cmd.rs` | 6 | 6 | 0 |
| `src/commands/group_cmd.rs` | 4 | 4 | 0 |
| `src/commands/recording_cmd.rs` | 3 | 3 | 0 |
| `tests/manifest_helper.rs` | 1 | 1 | 0 |
| **src-tauri 小计** | 134 | **147** | **+13** |

### 其他资产数量

| 资产 | 声明 | 实际 | 备注 |
|------|------|------|------|
| Tauri commands（`#[tauri::command]`） | 19（AGENTS.md "19 Tauri commands"） | **34** | config_cmd 11 + group_cmd 8 + hotkey_cmd 2 + recording_cmd 8 + system_cmd 5；AGENTS.md 数字严重过期 |
| 基准测试（criterion bench） | 7 | **7** | 完全一致 |
| 模糊测试（fuzz target） | 3（AGENTS.md）/ 5（test-map.md） | **5** | AGENTS.md 与 test-map.md 自相矛盾；test-map.md 正确 |
| E2E suite | 9 | **9** | 完全一致 |
| E2E 用例 | 53 | **53** | 完全一致 |

---

## E2E 测试清单

| Suite | 文件 | 声明用例 | 实际 it() | ESM | E2E-ID | appendKnownIssue | binary skip |
|-------|------|---------|-----------|-----|--------|------------------|-------------|
| smoke | smoke.spec.js | 1 | 1 | ✅ | ❌ 无编号 | 0 | ✅ 显式 |
| config_cmd | config_cmd.spec.js | 12 | 12 | ✅ | ✅ 24 个 | 2 | 仅 wdio.conf 钩子 |
| group_cmd | group_cmd.spec.js | 8 | 8 | ✅ | ✅ 16 个 | 2 | 仅 wdio.conf 钩子 |
| hotkey_cmd | hotkey_cmd.spec.js | 3 | 3 | ✅ | ✅ 8 个 | 2 | 仅 wdio.conf 钩子 |
| recording_cmd | recording_cmd.spec.js | 5 | 5 | ✅ | ✅ 10 个 | 2 | 仅 wdio.conf 钩子 |
| system_cmd | system_cmd.spec.js | 5 | 5 | ✅ | ✅ 10 个 | 2 | 仅 wdio.conf 钩子 |
| modes | modes.spec.js | 7 | 7 | ✅ | ✅ 28 个 | 3 | 仅 wdio.conf 钩子 |
| ipc | ipc.spec.js | 7 | 7 | ✅ | ✅ 29 个 | 9 | 仅 wdio.conf 钩子 |
| key_send | key_send.spec.js | 5 | 5 | ✅ | ✅ 27 个 | 3 | 仅 wdio.conf 钩子 |
| **总计** | — | **53** | **53** | **9/9** | **8/9** | **25 处** | **1/9 显式** |

---

## 发现清单

### Finding 1
- **位置**: `asd-tauri/src-tauri/Cargo.toml:7`（`test-manifest = []`）+ 全代码库
- **维度**: test-manifest feature 覆盖
- **严重级别**: Critical
- **描述**: `Cargo.toml` 第 7 行定义了 `test-manifest = []` feature，但全代码库中**无任何 `#[cfg(feature = "test-manifest")]` 或 `#[cfg(not(feature = "test-manifest"))]` 使用**（已用 `Select-String` 搜索确认）。AGENTS.md 多处声称"主 crate 测试需要 `--features test-manifest`，否则部分测试会被跳过"，包括：
  - "Testing Requirements > Rust/Tauri 测试"章节："主 crate 测试需要 `--features test-manifest`"
  - "常见错误"章节第 4 条："test-manifest feature 遗漏：主 crate 测试需要 `--features test-manifest`，否则部分测试会被跳过"
- **根因**: feature 早期可能 gate 过 manifest 加载测试，后续重构中被废弃但未删除定义；AGENTS.md 文档未同步更新。
- **修复建议**:
  1. 确认无任何代码引用该 feature 后，从 `Cargo.toml` 删除 `test-manifest = []`；
  2. 同步更新 AGENTS.md 移除所有"test-manifest"相关描述；
  3. 简化测试运行命令（移除 `--features test-manifest`）。

### Finding 2
- **位置**: `asd-tauri/e2e/specs/hotkey_cmd.spec.js:43`、`asd-tauri/e2e/helpers/key_receiver.js:16`
- **维度**: 测试隔离性 / 跨机器可移植性
- **严重级别**: Critical
- **描述**: 两处硬编码 AHK v2 路径 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`：
  ```javascript
  const ahkPath = 'D:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';
  ```
  其他开发者的机器上若 AHK 安装在 `C:\Program Files\AutoHotkey\` 或使用 32 位版本，E2E 测试将立即失败。
- **根因**: E2E 测试开发时直接写死了开发者本机路径，未做环境抽象。
- **修复建议**:
  1. 通过环境变量注入（`process.env.AHK_PATH || require('node:child_process').execSync('where AutoHotkey64.exe')`）；
  2. 或在 `e2e/helpers/config.js` 中集中管理路径常量；
  3. 或在 `wdio.conf.js` 中读取 `tauri.conf.json` 的 AHK 路径配置。

### Finding 3
- **位置**: `asd-tauri/src-tauri/src/commands/{config_cmd.rs, group_cmd.rs, recording_cmd.rs}.rs` 的 `#[cfg(test)] mod tests`
- **维度**: 测试覆盖盲区
- **严重级别**: Critical
- **描述**: 三个 commands 模块共有 **27 个 `#[tauri::command]` 函数**，但单元测试**均未覆盖 command 函数本身**：
  - `config_cmd.rs`：11 个 commands（get_config、save_config、validate_config、list_backups、create_backup、restore_backup、delete_backup、export_config、import_config、compare_configs、hot_reload），7 个测试**全部测试 `ConfigValidator` 和 `AppError`**，未触及任何 command 函数；
  - `group_cmd.rs`：8 个 commands（get_groups、get_group_detail、toggle_group、batch_toggle_groups、delete_group、batch_delete_groups、reorder_groups、register_hotkey、unregister_hotkey — 注：register/unregister 实际在 group_service 中），4 个测试**仅测试 `GroupSummary`/`GroupStatus` 数据结构的 `From` 实现和序列化**；
  - `recording_cmd.rs`：8 个 commands（start_recording、stop_recording、pause_recording、resume_recording、export_recording、import_recording、start_validation、stop_validation），3 个测试**仅测试 `RecordingResult` 数据结构的序列化**。
- **根因**: `#[tauri::command]` 函数需要 `tauri::State<'_, Arc<AppState>>` 参数，Tauri 2.11.2 中无公共构造函数，难以在纯单元测试中构造。`system_cmd.rs` 通过 `_impl` 辅助函数模式绕过了此限制，但其他 commands 未采用此模式。
- **修复建议**:
  1. 仿照 `system_cmd.rs` 的 `_impl` 模式，将 command 函数体提取为 `fn xxx_impl(state: &Arc<AppState>, ...) -> Result<...>`，command 函数仅一行委托；
  2. 对每个 command 至少添加正常路径 + 错误路径测试；
  3. 优先覆盖 `toggle_group`、`save_config`、`start_recording` 等核心命令。

### Finding 4
- **位置**: `asd-tauri/src-tauri/src/tests/bridge_tests.rs`（全文件）+ `asd-tauri/docs/test-map.md`
- **维度**: 测试数量统计与文档登记
- **严重级别**: Important
- **描述**: `bridge_tests.rs` 包含 10 个测试函数（覆盖 IpcBridge::send_and_wait 超时/管道断裂/未初始化、TauriEventBridge、WatchdogBridge 状态/reset/Running），但 `docs/test-map.md` 的"src-tauri 集成测试"表格中**完全未列出 bridge_tests.rs**，导致 test-map.md 测试总数偏低 10 个。
- **根因**: 新增 bridge_tests.rs 时未同步更新 test-map.md。
- **修复建议**: 在 test-map.md 的 src-tauri 表格中追加一行：
  ```
  | asd-tauri | 集成 | src-tauri/src/tests/bridge_tests.rs | 10 | IpcBridge / TauriEventBridge / WatchdogBridge trait 实现 |
  ```

### Finding 5
- **位置**: `asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`
- **维度**: 测试数量统计
- **严重级别**: Important
- **描述**: 实际 17 个测试函数（`test_watchdog_start_child_process`、`test_watchdog_child_crash_restart`、`test_watchdog_runner_auto_restart`、`test_watchdog_restart_limit`、`test_watchdog_failed_state_persistent`、`test_watchdog_exponential_backoff`、`test_watchdog_backoff_wait`、`test_watchdog_backoff_expired`、`test_watchdog_heartbeat_recovery`、`test_watchdog_stable_heartbeat_resets_count`、`test_watchdog_graceful_shutdown`、`test_watchdog_graceful_shutdown_no_child`、`test_watchdog_reset_to_restart`、`test_watchdog_reset_restart_count`、`test_backoff_durations_constant`、`test_max_restart_attempts_constant`、`test_watchdog_full_state_machine_flow`），但 test-map.md 声明 14 个，差 +3。
- **根因**: 文件新增测试后未同步更新 test-map.md。
- **修复建议**: 更新 test-map.md 中 watchdog_integration_tests.rs 的测试数为 17。

### Finding 6
- **位置**: `asd-tauri/src-tauri/tests/manifest_helper.rs`
- **维度**: 测试质量 / 测试有效性
- **严重级别**: Important
- **描述**: `manifest_helper.rs` 整个文件内容仅：
  ```rust
  #[test]
  fn test_manifest_helper_smoke() {
      assert!(true);
  }
  ```
  test-map.md 声称其覆盖"tauri.conf.json manifest 加载冒烟测试"，但**实际未读取、解析或验证任何 manifest 文件**，是空壳测试（tautology）。
- **根因**: 测试作为 `[[test]]` target 占位符创建，但实际验证逻辑从未实现。
- **修复建议**:
  1. 若 manifest 验证确有必要，实现为：读取 `tauri.conf.json`，断言关键字段（productName、version、tauri.windows 等）存在；
  2. 若 manifest 验证已由其他测试覆盖，删除此空壳测试和 Cargo.toml 中的 `[[test]]` 段；
  3. 同步更新 test-map.md 描述。

### Finding 7
- **位置**: `AGENTS.md` "Subdirectories > Rust/Tauri 部分" 与实际 `asd-tauri/fuzz/fuzz_targets/`
- **维度**: 文档一致性
- **严重级别**: Important
- **描述**: AGENTS.md "关键设计决策" 表格 #5 称"3 个 fuzz target"，但实际 `fuzz/Cargo.toml` 注册了 **5 个 fuzz target**：
  1. `fuzz_config_deserialize.rs` — Config 反序列化
  2. `fuzz_ipc_command.rs` — IpcCommand 反序列化
  3. `fuzz_ipc_json.rs` — IpcMessage 反序列化（基础）
  4. `fuzz_ipc_message_parse.rs` — IpcMessage 解析后字段访问与方法调用
  5. `fuzz_hotkey_merger.rs` — HotkeyMerger push/flush 逻辑

  test-map.md 已正确登记 5 个，但 AGENTS.md 未更新。
- **根因**: AGENTS.md 与 test-map.md 之间信息不同步。
- **修复建议**: 更新 AGENTS.md "关键设计决策" #5 为"5 个 fuzz target"。

### Finding 8
- **位置**: `AGENTS.md` "Key Files > Rust/Tauri 部分" + `src-tauri/src/lib.rs`
- **维度**: 文档一致性
- **严重级别**: Important
- **描述**: AGENTS.md 多处声称"19 Tauri commands + 应用初始化"（`asd-tauri/src-tauri/src/lib.rs | 19 Tauri commands + 应用初始化`），但实际：
  - `src/lib.rs` 中 `#[tauri::command]` 数量：**0**
  - `src/commands/*.rs` 中 `#[tauri::command]` 数量：**34**
    - config_cmd.rs: 11
    - group_cmd.rs: 8
    - hotkey_cmd.rs: 2
    - recording_cmd.rs: 8
    - system_cmd.rs: 5
- **根因**: commands 从 lib.rs 拆分到 commands/ 子模块后，AGENTS.md 未同步更新。
- **修复建议**:
  1. 更新 AGENTS.md "Key Files" 表中 lib.rs 描述为"应用初始化 + 19 个 Tauri command 注册（实际命令在 commands/）"；
  2. 或更准确："应用初始化 + Tauri command 注册（34 个命令分布在 commands/）"。

### Finding 9
- **位置**: `asd-tauri/e2e/docs/e2e-test-report.md`（全文件）
- **维度**: 测试报告时效性
- **严重级别**: Minor
- **描述**: `e2e-test-report.md` 记录的运行结果为 2026-06-28 19:36-19:37：
  - 测试用例通过率：20/53 = 37.7%
  - 结论："20/53 测试用例通过"

  但 `e2e-known-issues.md`（更新于 2026-06-29）明确记载："基于 9/9 E2E 测试全部通过的验证结果"、"已解决问题：16 个；未解决问题：1 个；环境限制记录：2 个"。即实际 53/53 全部通过，但报告未更新。
- **根因**: 2026-06-29 修复 ISSUE-013/014/016 后未重新生成报告。
- **修复建议**: 重新运行 `cd asd-tauri/e2e && npm test` 生成最新报告，或手动更新 e2e-test-report.md 的"总体结果"和"按 Suite 统计"表格。

### Finding 10
- **位置**: `AGENTS.md` "E2E 测试"章节
- **维度**: 文档一致性 / 路径准确性
- **严重级别**: Minor
- **描述**: AGENTS.md 引用的 E2E 测试文档路径不准确：
  - 声称"`docs/e2e-test-report.md`（运行后生成）"
  - 声称"`docs/e2e-test-checklist.md`"
  - 声称"`docs/e2e-known-issues.md`"

  实际位置：
  - `asd-tauri/e2e/docs/e2e-test-report.md` ✅ 存在（路径不同）
  - `asd-tauri/e2e/docs/e2e-known-issues.md` ✅ 存在（路径不同）
  - `asd-tauri/docs/e2e-test-checklist.md` ❌ **不存在**
  - `asd-tauri/e2e/docs/` 下也无 e2e-test-checklist.md
- **根因**: checklist 文档从未创建；其他两个文档路径前缀错误。
- **修复建议**:
  1. 更新 AGENTS.md 中三个路径为 `asd-tauri/e2e/docs/e2e-test-report.md`、`asd-tauri/e2e/docs/e2e-known-issues.md`；
  2. 删除对不存在的 `e2e-test-checklist.md` 的引用，或补建该文档。

### Finding 11
- **位置**: `asd-tauri/e2e/specs/smoke.spec.js`（唯一 it 块）
- **维度**: E2E 编号规范
- **严重级别**: Minor
- **描述**: AGENTS.md 强制规范"测试用例编号格式：`E2E-<SUITE>-NNN`（如 `E2E-CFG-001`）"。8/9 spec 文件遵守此规范，但 `smoke.spec.js` 的唯一用例描述为"应用窗口能启动并关闭"，**无 E2E-SMOKE-001 编号**。
- **根因**: 冒烟测试作为最早编写的 spec，未遵循后确立的编号规范。
- **修复建议**: 在 smoke.spec.js 的 it 描述前加 `E2E-SMOKE-001:`，如：`it('E2E-SMOKE-001: 应用窗口能启动并关闭', ...)`。

### Finding 12
- **位置**: `asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`（17 个测试）
- **维度**: 测试可发现性 / 文档完整性
- **严重级别**: Minor
- **描述**: 17 个测试中 **12 个标记 `#[ignore = "涉及真实进程管理且需要时序协调，需手动运行"]`**（如 `test_watchdog_start_child_process`、`test_watchdog_child_crash_restart`、`test_watchdog_runner_auto_restart`、`test_watchdog_restart_limit` 等），仅 5 个默认运行（`test_watchdog_reset_to_restart`、`test_watchdog_reset_restart_count`、`test_backoff_durations_constant`、`test_max_restart_attempts_constant`、`test_watchdog_full_state_machine_flow`）。test-map.md 未说明此 ignore 状态，可能误导读者认为所有 17 个测试在 `cargo test` 时均运行。
- **根因**: ignore 标注在测试文件中，但未同步到 test-map.md。
- **修复建议**: 在 test-map.md 的 watchdog_integration_tests.rs 行追加备注"（12 个 `#[ignore]`，需 `--ignored` 手动运行）"。

### Finding 13
- **位置**: `asd-tauri/src-tauri/src/bridge.rs:200-213`（TauriEventBridge 测试）
- **维度**: 测试覆盖盲区
- **严重级别**: Important
- **描述**: `bridge_tests.rs:200` 的 `test_tauri_event_bridge_emit` 标记为 `#[ignore = "TauriEventBridge 需要 tauri::AppHandle，需在 Tauri 集成环境中运行"]`，且函数体仅 `panic!("此测试需要 Tauri AppHandle，无法在纯单元测试环境中运行")`。即 TauriEventBridge 的 `emit()` 方法（bridge.rs:134-138）**完全无单元测试覆盖**，也未在任何集成测试中验证。
- **根因**: `tauri::AppHandle` 在 Tauri 2.11.2 中无公共构造函数，无法在纯单元测试中实例化。
- **修复建议**:
  1. 将 TauriEventBridge 的 emit 逻辑提取为 `fn emit_with_handle(handle: &impl EventEmitterLike, event: &str, payload: Value) -> bool`，使用 trait 抽象 AppHandle；
  2. 或在 E2E 测试中通过监听 `window.__TAURI__.event.listen` 验证事件发射；
  3. 或使用 mockall 生成 AppHandle mock（需要 tauri 提供 mock 功能）。

### Finding 14
- **位置**: `asd-tauri/src-tauri/src/lib.rs`（27936 bytes）
- **维度**: 测试覆盖盲区
- **严重级别**: Important
- **描述**: `lib.rs` 是 src-tauri 主 crate 最大的源文件（27936 bytes，包含应用初始化、托盘菜单、关机流程、Tauri command 注册等），但 **lib.rs 中 `#[test]`/`#[tokio::test]` 数量为 0**。`#[cfg(test)] mod tests;` 仅声明子模块，所有测试都在 `src/tests/` 下。lib.rs 中的核心函数未被直接测试：
  - `perform_graceful_shutdown()`（lib.rs:27-）
  - `setup_tray_menu()` 相关逻辑
  - Tauri command 注册逻辑（`.invoke_handler(tauri::generate_handler![...])` 中 34 个 commands 的注册）
  - `run()` 函数（应用入口）
- **根因**: lib.rs 强依赖 Tauri 运行时上下文（App、Window、TrayIcon 等），难以单元测试。
- **修复建议**:
  1. 将 `perform_graceful_shutdown` 等纯逻辑函数提取到独立模块，输入输出明确化，便于测试；
  2. 对 Tauri command 注册列表添加编译时断言（如 `const _: () = { assert!(commands.len() == 34); };`）；
  3. 关机流程的关键状态机转换可通过 trait 抽象后单元测试。

### Finding 15
- **位置**: `asd-tauri/e2e/wdio.conf.js:80-200`（onPrepare 钩子）+ 9 个 spec 文件
- **维度**: E2E 测试隔离性
- **严重级别**: Minor
- **描述**: AGENTS.md 强制规范"binary 缺失时所有测试 skip（不 fail）"。但实际：
  - `smoke.spec.js` 在 it 块内显式 `if (!existsSync(binaryPath)) this.skip()` ✅
  - 其他 8 个 spec 文件**无显式 binary skip 逻辑**
  - `wdio.conf.js` 的 `onPrepare` 钩子会记录 `skip-reason.txt`，但**不实际 skip 测试**

  即 binary 缺失时，8 个 spec 会因 WebDriver 会话建立失败而 fail，而非 skip。
- **根因**: binary skip 逻辑未统一封装到 before hook 或 helper 中。
- **修复建议**:
  1. 在 `wdio.conf.js` 的 `before` 钩子中检查 binary 存在性，不存在则 `this.skip()`；
  2. 或在 `helpers/tauri.js` 的 `startApp` 中抛出特定错误，spec 中 catch 后 skip；
  3. 最优解：在 onPrepare 中若 binary 缺失则 `process.exit(0)` 并标记所有测试为 skipped。

### Finding 16
- **位置**: `asd-tauri/src-tauri/src/tests/ipc_tests.rs`（26 个测试）
- **维度**: 测试隔离性 / 测试质量
- **严重级别**: Minor
- **描述**: 26 个测试中 18 个标记 `#[serial]`（serial_test crate），串行执行避免 named pipe 并发冲突。这是正确的设计，但：
  - 8 个非 serial 测试与 serial 测试之间可能存在隐式依赖（共享 pipe 命名空间）；
  - `unique_pipe_name("ping")`、`unique_pipe_name("exec")` 等使用固定字符串后缀，若并发运行多个 test binary 实例（如 `cargo test -- --test-threads=8` 配合非 serial 测试）仍可能碰撞。
- **根因**: serial_test 仅在单个 binary 内串行化，跨进程不隔离。
- **修复建议**:
  1. 将所有 ipc_tests 标记为 `#[serial]`（保守方案）；
  2. 或在 `unique_pipe_name` 中加入 `process::id()` 前缀，确保跨进程唯一。

### Finding 17
- **位置**: `asd-tauri/crates/asd-application/src/state.rs`（36 个测试 vs test-map.md 声明 35）
- **维度**: 测试数量统计
- **严重级别**: Minor
- **描述**: state.rs 实际 36 个 `#[test]`/`#[tokio::test]`，test-map.md 声明 35，差 +1。
- **根因**: 新增测试后未更新 test-map.md。
- **修复建议**: 更新 test-map.md 中 state.rs 的测试数为 36，asd-application 小计为 176，总计为 519。

---

## 覆盖率盲区清单

按严重级别排序：

| # | 盲区位置 | 覆盖现状 | 影响 | 优先级 |
|---|---------|---------|------|--------|
| 1 | `commands/config_cmd.rs` 11 个 command 函数 | 0 直接覆盖（仅测试 ConfigValidator/AppError） | save_config、import_config、hot_reload 等核心命令的错误路径未验证 | 高 |
| 2 | `commands/group_cmd.rs` 8 个 command 函数 | 0 直接覆盖（仅测试 GroupSummary/GroupStatus 序列化） | toggle_group、batch_toggle_groups、reorder_groups 等核心命令未验证 | 高 |
| 3 | `commands/recording_cmd.rs` 8 个 command 函数 | 0 直接覆盖（仅测试 RecordingResult 序列化） | start_recording、stop_recording、export_recording 等核心命令未验证 | 高 |
| 4 | `bridge.rs` TauriEventBridge::emit | 0 覆盖（#[ignore] + panic） | 事件转发到前端的链路无单元测试 | 中 |
| 5 | `lib.rs` perform_graceful_shutdown | 0 直接覆盖 | 关机流程的状态机转换未测试 | 中 |
| 6 | `lib.rs` Tauri command 注册列表 | 0 编译时验证 | 新增/删除 command 时无法自动检测注册遗漏 | 中 |
| 7 | `bridge.rs` IpcBridge::send_message | 仅通过 MockEventEmitter 间接覆盖 | outbound channel 满时的错误路径未直接验证 | 低 |
| 8 | `bridge.rs` send_and_wait 的 cleanup_pending_by_seq | 部分覆盖（timeout/pipe_broken 路径） | oneshot 通道关闭分支未直接验证 | 低 |
| 9 | `infrastructure/ipc.rs` 高级重连逻辑 | 35 个测试覆盖核心路径 | 多次重连退避、心跳超时累积等边界场景未覆盖 | 低 |
| 10 | `commands/recording_cmd.rs` export/import 文件 I/O | 0 覆盖 | 文件路径校验、JSON 格式错误处理未测试 | 低 |

**对照纯逻辑 crate 96.57% 覆盖率**：src-tauri 主 crate 由于 Tauri 运行时强依赖，commands 层和 lib.rs 是覆盖率主要盲区，估计 src-tauri 整体覆盖率显著低于纯逻辑 crate。

---

## 无问题声明

以下维度审查后**未发现问题**：

1. **asd-domain 测试**：125 个测试，与声明完全一致，覆盖 config/validator/models/integration，无隔离性问题。
2. **asd-ipc-protocol 测试**：71 个测试，与声明完全一致，覆盖 13 个 IpcCommand variants 的序列化往返、IpcMessage 构造器、HotkeyMerger。
3. **asd-application 测试**：176 个测试（+1 误差），广泛使用 `tempfile::tempdir()` 确保文件 I/O 隔离（backup_service_tests、concurrency_tests、recording_service_tests、asd-test-harness）。
4. **无全局状态污染**：未发现 `lazy_static!`、`OnceCell`、`static mut` 等全局状态模式（`Select-String` 搜索确认）。
5. **fixture 使用 `include_str!` 相对路径**：`config_compat_tests.rs:3-4` 正确使用相对路径引用 `../../config.json` 和 `../../../tests/fixtures/configs/tests_config.json`，无硬编码绝对路径。
6. **fixture 命名规范**：`tests/fixtures/configs/tests_config.json` 符合 `<场景>_config.json` 规范，并在 test-map.md "测试固件"章节登记。
7. **基准测试**：7 个 criterion bench，覆盖 config_loading、key_validation、group_scheduling、config_serialization、ipc_message_roundtrip、ipc_command_serialization、ipc_send_path，与声明一致，目标明确（<5ms、<1ms、<2ms 等）。
8. **模糊测试覆盖关键反序列化路径**：5 个 fuzz target 覆盖 Config、IpcCommand、IpcMessage、HotkeyMerger，符合"覆盖关键反序列化路径"要求。
9. **config_compat_tests 覆盖**：11 个测试覆盖 7 种执行模式（periodic、sequence、hybrid、hold、enhanced_periodic、enhanced_sequence、enhanced_hybrid）+ control_hotkeys + hold_settings 字段，往返序列化验证充分。
10. **ipc_tests 覆盖**：26 个测试覆盖 ping/pong、execute/result、auth（valid/invalid/no-auth/mismatch/wrong-type）、message_size_limit、pipe_broken_reconnect、heartbeat_callback、pending_responses_cleanup 等关键路径。
11. **E2E 测试数量与结构**：9 suite / 53 用例，与 AGENTS.md 完全一致；全部使用 ESM 语法；8/9 遵守 E2E-<SUITE>-NNN 编号规范；25 处调用 `appendKnownIssue`。
12. **E2E 已知问题管理**：`e2e/docs/e2e-known-issues.md` 详细记录 16 个已解决问题、1 个未解决问题、2 个环境限制，结构清晰。
13. **Tauri command 函数均使用 `#[tauri::command]` 宏**：34 个 commands 全部正确标注（搜索确认）。
14. **错误类型使用 `thiserror`**：AppError、IpcError 均使用 `#[derive(thiserror::Error)]`，符合规范。
15. **纯逻辑 crate 无 Tauri/tokio/interprocess/windows 依赖**：asd-domain、asd-ipc-protocol、asd-application 的 Cargo.toml 未引入禁止依赖。

---

## 统计

### 发现总数
- **Critical**: 3
- **Important**: 6
- **Minor**: 8
- **总计**: 17

### 按维度分布
| 维度 | 数量 |
|------|------|
| 测试覆盖盲区 | 4（Findings 3, 13, 14, 覆盖率盲区清单） |
| 测试数量与声明不符 | 4（Findings 4, 5, 8, 17） |
| 文档一致性 | 4（Findings 7, 9, 10, 12） |
| 测试隔离性 | 2（Findings 2, 16） |
| test-manifest feature | 1（Finding 1） |
| 测试质量 | 2（Findings 6, 11） |
| E2E 规范 | 2（Findings 11, 15） |

### 测试数量实际 vs 声明对比

| Crate | 声明 | 实际 | 差异 |
|-------|------|------|------|
| asd-domain | 125 | 125 | 0 |
| asd-ipc-protocol | 71 | 71 | 0 |
| asd-application | 175 | 176 | +1 |
| asd-test-harness | 0 | 0 | 0 |
| asd-tauri (src-tauri) | 134 | 147 | +13 |
| **Rust 测试总计** | **506+** | **519** | **+13** |
| AHK 执行器测试 | 467 | — | 未审查（仅 Rust） |
| 基准测试 | 7 | 7 | 0 |
| 模糊测试 | 3（AGENTS.md）/ 5（test-map.md） | 5 | AGENTS.md 偏差 -2 |
| E2E suite | 9 | 9 | 0 |
| E2E 用例 | 53 | 53 | 0 |
| Tauri commands | 19（AGENTS.md） | 34 | AGENTS.md 偏差 -15 |

### 最关键的 3 个发现摘要

1. **Critical - Finding 1（test-manifest feature 已废弃）**：Cargo.toml 定义 `test-manifest = []` 但全代码库无任何 `#[cfg(feature = "test-manifest")]` 使用，AGENTS.md 中"主 crate 测试需要 `--features test-manifest`"的说法已过时，应删除 feature 定义并更新文档。

2. **Critical - Finding 2（E2E 硬编码 AHK 路径）**：`e2e/specs/hotkey_cmd.spec.js:43` 和 `e2e/helpers/key_receiver.js:16` 硬编码 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`，在其他开发机器上 E2E 测试会立即失败，应通过环境变量或动态查询注入路径。

3. **Critical - Finding 3（27 个 Tauri command 无直接单元测试）**：config_cmd.rs（11）、group_cmd.rs（8）、recording_cmd.rs（8）三个模块共 27 个 `#[tauri::command]` 函数无直接单元测试覆盖，仅测试了辅助数据结构/函数，建议采用 system_cmd.rs 的 `_impl` 辅助函数模式提取核心逻辑后补测。
