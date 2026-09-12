# 测试覆盖与质量审查报告（Task 8）

- 审查日期：2026-08-20
- 审查范围：Rust workspace 测试（asd-domain / asd-ipc-protocol / asd-application / src-tauri）、AHK v2 测试（根目录 tests/ 与 tests/test_ahk_executor/）、E2E 测试（asd-tauri/e2e/）
- 审查方式：只读审查，未修改任何 .ahk / .rs / .json 源文件

## 执行摘要

本次审查对按键连招管理系统（AHK v2 + Rust/Tauri 混合架构）的测试覆盖与测试质量进行了核对与评估。总体结论：**测试基础设施健全、覆盖口径基本可信**，关键测试规模数字（AHK 执行器 57 套件 / 244 个 `Test_` 方法、E2E 9 个 spec / 53 个用例、src-tauri commands 层 82 个 `#[test]`）均与 AGENTS.md 文档口径一致，未发现"测试造假"或"关键路径完全无保障"级别的 Critical 缺陷。

主要覆盖盲区集中在 **IpcManager 消息接收/分发循环** 与 **优雅关机流程主体** 两个基础设施关键路径的单元测试缺失（均为 Important 级），其余为 E2E 代码重复、文档口径漂移、入口 OnError 缺失、fixture 覆盖不足等 Minor 级问题。

### 核对结果（数字口径与文档一致性）

| 项目 | 文档口径 | 实测 | 结论 |
|------|---------|------|------|
| AHK 执行器套件数 | 57 套件 | 57（`class ... extends AutoHotUnitSuite`） | ✅ 一致 |
| AHK 执行器 Test_ 方法数 | 244 | 244（`Test_*(`） | ✅ 一致 |
| E2E spec 文件数 | 9 | 9（specs/ 下 9 个 .spec.js） | ✅ 一致 |
| E2E 用例数 | 53 | 53（`it(` 出现次数） | ✅ 一致 |
| src-tauri commands 层测试 | — | 82 个 `#[test]`/`#[tokio::test]`（5 个文件） | ✅ 覆盖充分 |
| 强制接管指令 | 全部 .ahk 必须含 | 抽查 test_error_captor.ahk 等均含 4 项 | ✅ 合规 |
| `#[ignore]` 数量 | "含 16 ignored" | watchdog 16 + bridge 3 = 19+ | ⚠️ 文档漂移 |

## 发现清单

### T8-01 — IpcManager 消息接收/分发循环缺直接单元测试

- **位置**：`asd-tauri/src-tauri/src/infrastructure/ipc.rs`（`listen_ahk` / 消息解析与 hotkey/heartbeat/recording 分发逻辑）
- **维度**：测试覆盖
- **严重级别**：Important
- **描述**：Rust 侧 IPC 消息接收循环（accept 连接 → 解析 `IpcMessage` JSON → 按 `type` 分发 hotkey/heartbeat/recording 事件）缺乏直接单元测试。现有覆盖仅来自 `bridge_tests.rs` 的 `test_ipc_bridge_send_and_wait_timeout`（只验证超时与管道断裂，且服务端故意不响应），以及 E2E `ipc.spec.js`（7 个黑盒用例）。消息主体的解析与分发分支（含 malformed JSON、未知 type、空 data 等边界）无白盒覆盖。
- **根因**：`listen_ahk` 为 async 方法，内联了连接 accept 与消息处理循环，未把"消息解析 → 分发"抽成可单测的纯函数，导致只能通过真实管道/进程做集成级验证。
- **修复建议**：参照 `shutdown::try_acquire_shutdown_guard` 的模式，将"字节流/JSON 字符串 → `IpcMessage` 解析 + 分发决策"抽取为纯函数（如 `parse_and_dispatch(message_bytes) -> Option<DispatchAction>`），在 `infrastructure/ipc.rs` 内补充 `#[cfg(test)]` 单测覆盖正常/非法 JSON/未知 type 三分支。

### T8-02 — 优雅关机流程主体缺测试（仅关锁纯函数已覆盖）

- **位置**：`asd-tauri/src-tauri/src/lib.rs` `perform_graceful_shutdown`（约 41–43 行调用锁 + 后续 IPC Shutdown 发送、watchdog 停止、窗口销毁序列）
- **维度**：测试覆盖
- **严重级别**：Important
- **描述**：关机流程中仅有锁获取纯函数 `infrastructure::shutdown::try_acquire_shutdown_guard` 被提取并测试（lib.rs `tests` 模块 4 个 `#[test]`：`IPC_PIPE_NAME` 常量 + 3 个锁场景），覆盖到位。但 `perform_graceful_shutdown` 的其余主体——向 AHK 发送 `IpcCommand::Shutdown`、停止 `ProcessWatchdog`、销毁窗口、二次调用被锁拦截后的行为——没有任何测试。进程清理/优雅退出是本系统依赖 `ProcessWatchdog` + panic hook 补偿机制的关键保障（AGENTS.md 设计决策 #6），主体逻辑无回归保障。
- **根因**：函数依赖 `AppState`/`IpcManager`/`Watchdog` 等运行时状态，历史重构只提取了最易抽离的锁原子操作，后续步骤未继续做可测性改造。
- **修复建议**：为 shutdown 序列补充 mock 集成测试（复用 `asd-test-harness` 的 `MockEventEmitter`/`MockProcessWatcher` 与现有 `FailingIpcSender` 模式），至少断言：锁未获取时提前返回、锁获取成功后按序调用 IPC shutdown + watchdog stop；或将序列编排抽为纯决策函数。

### T8-03 — E2E spec 生命周期代码高度重复，失败上报严重级别硬编码、caseId 正则各自维护

- **位置**：`asd-tauri/e2e/specs/*.spec.js`（9 个文件的 `before`/`beforeEach`/`afterEach`/`after` 四段，例 `config_cmd.spec.js:32–95`）
- **维度**：测试质量（可维护性 / 一致性）
- **严重级别**：Important
- **描述**：
  1. 9 个 spec 各自复制了「binary 检测 → skip」「`backupUserConfig`/`restoreUserConfig`」「`appendResult` + 失败时 `appendKnownIssue`」四段近乎相同的生命周期逻辑，约 60 行/spec，共 ~500 行重复。
  2. `appendKnownIssue` 的严重级别在 `config_cmd.spec.js:72` 等所有 spec 中**硬编码为 `'HIGH'`**，无法按实际影响区分 Critical/Major/Minor，报告失真。
  3. 各 spec 的 caseId 提取正则各自硬编码（`E2E-CFG-\d+`、`E2E-GRP-\d+` 等），若某测试标题未按 `E2E-<SUITE>-NNN` 编号，会以完整标题兜底生成 `ISSUE-<完整标题>`，编号体系脆弱。
- **根因**：spec 创建时按文件独立复制模板，缺少共享的 WebdriverIO base hook / 通用 afterEach fixture。
- **修复建议**：抽一个共享辅助模块（如 `helpers/spec-hooks.js`）导出统一的 `beforeEachBinaryGuard`/`afterEachReport`，将 `appendKnownIssue` 的严重级别改为从 `test` 元数据传入或按错误类型推断；统一 caseId 提取为共享函数，禁止在 spec 内硬编码正则。

### T8-04 — `tests/run_all_tests.ahk` 入口缺少 OnError 全局回调

- **位置**：`d:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk`（grep `OnError` 无命中）
- **维度**：测试规范（错误接管机制）
- **严重级别**：Minor
- **描述**：AGENTS.md 规定「测试文件额外必须包含」`OnError((e, mode) => (FileAppend(...), true))` 回调。根目录其余测试文件（test_boundary/test_domain/test_application 等）均含 OnError，但作为批量运行入口的 `run_all_tests.ahk` 未包含。若某个 suite 抛出未被 suite 内部捕获的运行时错误，会触发系统默认错误对话框，中断后续所有 suite 的批量执行。
- **根因**：`run_all_tests.ahk` 被视为"运行器"而非"测试文件"，遗漏了入口级错误接管。
- **修复建议**：在 `run_all_tests.ahk` 顶部（`#Requires` 之后）补充标准的 `#ErrorStdOut "UTF-8"` + `#Warn` 三指令与 `OnError` 回调，确保单个 suite 崩溃不阻塞整体批量运行。

### T8-05 — 测试文档口径漂移（#ignore 数量 / watchdog 测试数 / 固件登记不全）

- **位置**：`AGENTS.md`（"asd-tauri ... 含 16 ignored"）、`asd-tauri/docs/test-map.md:84`（watchdog 记 "17 个测试，15 个 `#[ignore]`"）
- **维度**：测试数据管理（文档一致性）
- **严重级别**：Minor
- **描述**：
  1. `#[ignore]` 实测：`watchdog_integration_tests.rs` 16 处 + `bridge_tests.rs` 3 处 = 19+，与 AGENTS.md "16 ignored"、test-map.md "15 个 #[ignore]" 三处口径互不一致。
  2. test-map.md「测试固件」章登记了 `asd-tauri/tests/fixtures/configs/tests_config.json`，但 `config_compat_tests.rs:3` 还有 `include_str!("../../config.json")`（`MAIN_CONFIG_JSON`）未登记为固件引用。
- **根因**：测试规模统计以手工方式维护，新增/调整 `#[ignore]` 与固件引用后未回写文档。
- **修复建议**：建立测试规模的可自动生成统计（`run_tests.ps1`/`analyze-tests.ps1` 已有 JUnit 解析能力，可扩展输出 `#[ignore]` 数），并将 `MAIN_CONFIG_JSON` 一并登记进 test-map.md「测试固件」表。

### T8-06 — fixtures 覆盖不足：joystick 3 种模式无配置样本，执行器 joystick 测试硬编码 mode 字符串

- **位置**：`d:\1demo\AutoHotkeydemo\tests\fixtures\`（仅 `sample_config.json`、`import_test_data.json` 两个文件）；`tests/test_ahk_executor/test_joystick.ahk:463`（硬编码 `"joystick_periodic"`）
- **维度**：测试数据管理（fixture 规范）
- **严重级别**：Minor
- **描述**：`sample_config.json` 覆盖了 7 种非摇杆执行模式（periodic/sequence/hold/enhanced_* /hybrid），与文档"覆盖 7 种模式"一致，但 3 种摇杆模式（`joystick_periodic`/`joystick_sequence`/`joystick_hold`）无对应配置样本。`test_ahk_executor/test_joystick.ahk` 直接在断言中硬编码 mode 字符串，违背「禁止硬编码可复用的测试数据」规范精神。
- **根因**：fixtures 目录为 v4.1 新增，摇杆模式当时未纳入样本规划。
- **修复建议**：为摇杆 3 模式补充配置样本（如 `joystick_config.json` 或在 sample_config.json 增补 joystick 分组），并在 AGENTS.md「AHK v2 测试固件管理」节登记；`test_joystick.ahk` 的 mode 断言改用 fixture 派生值。

## 总结

- 发现总数：**6**
- 各级别数量：Critical **0**、Important **3**、Minor **3**

> **勘误（2026-08-20）**：本报告首发版总结栏误记为「发现总数 7 / Minor 4」，与正文「发现清单」实际展开的 6 条（T8-01~T8-06，Important 3 + Minor 3）不一致。经核对，正文确无独立的第 4 条 Minor 项，纠正为「总数 6 / Minor 3」。对应 Fix Plan 中的 `T8-07†` 占位项据此关闭。

### Top 5 最严重发现

1. **T8-01**（Important）：IpcManager 消息接收/分发循环无直接单测，IPC 关键路径仅黑盒/间接覆盖。
2. **T8-02**（Important）：`perform_graceful_shutdown` 主体无测试，进程清理关键保障仅锁函数被覆盖。
3. **T8-03**（Important）：E2E 生命周期代码 9 spec 高度重复、失败级别硬编码 HIGH、caseId 正则各自维护。
4. **T8-04**（Minor）：`run_all_tests.ahk` 入口缺 OnError，单 suite 崩溃会弹窗中断批量运行。
5. **T8-05**（Minor）：`#[ignore]` 数量与 watchdog 测试数在 AGENTS.md / test-map.md 间口径互不一致，固件登记不全。