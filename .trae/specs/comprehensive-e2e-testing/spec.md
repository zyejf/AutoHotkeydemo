# 全面端到端功能测试 Spec

## Why

当前项目已有 505+ Rust 单元/集成测试和 467 个 AHK 执行器单元测试，但所有测试都局限于纯逻辑层或单模块边界内。整个应用的核心链路 —— Tauri 命令层、7 种执行模式、Rust↔AHK IPC 通信、AHK 执行器实际按键输出 —— 缺少真实环境下的端到端验证。这导致以下风险：

1. 单元测试通过 ≠ 应用真实可用（如 IPC 命令链路在真实 named pipe 下可能失败）
2. 19 个 Tauri 命令的业务流程从未被完整验证（如 `save_config` → `create_backup` → `restore_backup` 的备份恢复链路）
3. 7 种执行模式在真实 AHK 子进程下的行为未经验证（如 `enhanced_hybrid` 在多分组并发时的按键序列）
4. AHK 执行器实际按键输出未被验证（按键是否真的发送到了目标窗口）
5. 缺少可重复运行的回归测试套件，每次发布只能靠人工目测

## What Changes

- **新增 tauri-driver + WebDriverIO E2E 测试基础设施**：在 `asd-tauri/e2e/` 下建立独立的 E2E 测试项目，通过 tauri-driver 控制 Tauri 窗口、模拟用户操作、调用 Tauri 命令
- **新增 AHK 按键接收窗口工具**：在 `asd-tauri/e2e/fixtures/` 下创建专用的 AHK 接收窗口脚本，用于捕获并验证 AHK 执行器实际发送的按键序列
- **新增 19 个 Tauri 命令的 E2E 测试**：覆盖 config_cmd（9 个）、group_cmd（7 个）、hotkey_cmd（2 个）、recording_cmd（4 个）、system_cmd（5 个）的完整业务流程
- **新增 7 种执行模式的 E2E 测试**：每种模式（periodic / sequence / hybrid / hold / enhanced_periodic / enhanced_sequence / enhanced_hybrid）至少 1 个真实运行测试用例
- **新增 Rust↔AHK IPC 通信 E2E 测试**：验证 named pipe 双向通信、心跳、热键事件、录制事件、命令 ACK
- **新增 AHK 执行器按键验证 E2E 测试**：通过接收窗口法验证按键实际发送
- **新增测试报告生成器**：自动生成 Markdown 测试报告，包含通过率、失败清单、耗时统计
- **新增测试用例 checklist**：详细的功能测试用例清单，含步骤、预期、实际结果字段
- **新增已知问题清单 + 修复建议**：测试中发现的问题汇总

## Impact

- Affected specs: 无（独立测试项目）
- Affected code:
  - `asd-tauri/e2e/`（新建整个 E2E 测试目录）
  - `asd-tauri/e2e/package.json`（WebDriverIO 依赖）
  - `asd-tauri/e2e/wdio.conf.js`（WebDriverIO 配置）
  - `asd-tauri/e2e/fixtures/key_receiver.ahk`（按键接收窗口工具）
  - `asd-tauri/e2e/fixtures/test_config.json`（测试专用配置）
  - `asd-tauri/e2e/specs/`（测试用例目录）
  - `asd-tauri/e2e/helpers/`（测试辅助函数）
  - `asd-tauri/e2e/reports/`（测试报告输出目录）
  - `docs/e2e-test-report.md`（最终测试报告）
  - `docs/e2e-test-checklist.md`（测试用例 checklist）
  - `docs/e2e-known-issues.md`（已知问题清单）
- Affected docs: `AGENTS.md`（更新测试章节引用 E2E 套件）、`asd-tauri/docs/test-map.md`（登记 E2E 测试资产）

## ADDED Requirements

### Requirement: E2E 测试基础设施

系统 SHALL 在 `asd-tauri/e2e/` 下提供完整的 tauri-driver + WebDriverIO E2E 测试基础设施，包括：

- `package.json` 声明 `@tauri-apps/api`、`webdriverio`、`tauri-driver`、`@wdio/mocha-framework`、`@wdio/spec-reporter`、`@wdio/allure-reporter` 依赖
- `wdio.conf.js` 配置 tauri-driver 作为 WebDriver 后端（capabilities 指定 `tauri:options`）
- `helpers/tauri.js` 封装 tauri-driver 启动、应用启动、命令调用辅助函数
- `helpers/key_receiver.js` 封装按键接收窗口启动与读取辅助函数
- `fixtures/test_config.json` 提供测试专用配置（不污染用户真实 config.json）
- `fixtures/key_receiver.ahk` 提供 AHK 接收窗口脚本（启动一个 GUI 窗口，捕获所有按键事件，写入日志文件供测试读取）

#### Scenario: 启动 E2E 测试环境

- **WHEN** 开发者执行 `cd asd-tauri/e2e && npm install && npm test`
- **THEN** tauri-driver 启动，应用被启动，所有测试用例顺序执行，测试报告输出到 `reports/` 目录

#### Scenario: 测试隔离

- **WHEN** E2E 测试运行
- **THEN** 测试使用 `fixtures/test_config.json` 而非用户真实的 `config.json`，测试结束后用户配置不受影响

### Requirement: 19 个 Tauri 命令 E2E 测试

系统 SHALL 为每个 Tauri 命令提供至少 1 个 E2E 测试用例，覆盖正常流程和典型错误场景。

#### Scenario: config_cmd 命令测试

- **WHEN** 测试 `get_config`、`save_config`、`validate_config`、`list_backups`、`create_backup`、`restore_backup`、`delete_backup`、`export_config`、`import_config`、`compare_configs`、`hot_reload`
- **THEN** 每个命令的成功路径被验证；`save_config → create_backup → restore_backup` 链路被端到端验证；`validate_config` 对非法配置返回明确错误

#### Scenario: group_cmd 命令测试

- **WHEN** 测试 `get_groups`、`toggle_group`、`get_group_detail`、`delete_group`、`toggle_all`、`batch_toggle_groups`、`batch_delete_groups`、`reorder_groups`
- **THEN** 分组的增删改查、批量操作、重排序均通过端到端验证

#### Scenario: hotkey_cmd 命令测试

- **WHEN** 测试 `register_hotkey`、`unregister_hotkey`
- **THEN** 热键注册成功并可通过 `get_executor_status` 查询；注销后不再响应

#### Scenario: recording_cmd 命令测试

- **WHEN** 测试 `start_recording`、`stop_recording`、`pause_recording`、`resume_recording`
- **THEN** 录制状态机正确转换；录制的按键事件被正确捕获

#### Scenario: system_cmd 命令测试

- **WHEN** 测试 `get_executor_status`、`emergency_release`、`clear_emergency`、`toggle_hold_mode`、`reset_watchdog`
- **THEN** 紧急释放能立即停止所有分组；hold 模式切换正确；watchdog 重置生效

### Requirement: 7 种执行模式 E2E 测试

系统 SHALL 为 7 种执行模式各提供至少 1 个真实运行 E2E 测试用例，验证 AHK 执行器实际执行按键序列。

| 模式 | 测试场景 |
|------|---------|
| `periodic` | 单键周期性触发，验证按键间隔符合配置 |
| `sequence` | 多键顺序触发，验证按键顺序与延迟 |
| `hybrid` | 多分组混合，验证周期性键与序列键并行 |
| `hold` | 长按模式，验证 holdDuration 与 holdMode |
| `enhanced_periodic` | 增强周期性，验证 pressKeys + intervals 配置 |
| `enhanced_sequence` | 增强序列，验证 pressDelays 配置 |
| `enhanced_hybrid` | 增强混合，验证多 groups 数组配置 |

#### Scenario: 执行模式测试

- **WHEN** 对每种执行模式启动分组
- **THEN** 接收窗口法捕获的按键序列与配置预期一致（按键顺序、间隔、次数均在容差范围内）

### Requirement: Rust↔AHK IPC 通信 E2E 测试

系统 SHALL 提供真实 named pipe IPC 通信的 E2E 测试，验证：

- Rust 主进程启动 AHK 子进程成功（通过 ProcessWatchdog）
- Rust 发送 `IpcCommand::StartGroup` → AHK 接收并开始执行
- Rust 发送 `IpcCommand::StopGroup` → AHK 接收并停止
- AHK 发送心跳 → Rust 接收并更新 watchdog 状态
- AHK 发送 `hotkey` 事件 → Rust 接收并通过 Tauri event 转发到前端
- AHK 发送 `key_record_event` → Rust 接收并转发
- AHK 发送 `key_send_event` → Rust 接收并转发
- AHK 子进程崩溃 → Rust watchdog 检测并重启（达到最大重试次数后退出）

#### Scenario: IPC 双向通信

- **WHEN** 启动应用并触发分组执行
- **THEN** Rust 日志显示命令下发成功；AHK 日志显示命令接收成功；Rust 收到 AHK 的执行事件转发

#### Scenario: Watchdog 重启

- **WHEN** 强制终止 AHK 子进程
- **THEN** Rust watchdog 检测到进程退出，按配置重试启动；超过 MaxRetries 后 watchdog 进入 `MaxRetriesExceeded` 状态

### Requirement: AHK 执行器按键验证 E2E 测试

系统 SHALL 通过接收窗口法验证 AHK 执行器实际发送的按键，验证方法：

1. 测试启动时先启动 `key_receiver.ahk` 接收窗口（一个 AHK GUI 窗口，使用 `OnMessage` 或 `Hotkey` 捕获按键）
2. 接收窗口将所有捕获的按键事件写入 `e2e/reports/key_log.txt`（格式：`<timestamp>|<key>|<event>`）
3. 测试触发分组执行后，读取 `key_log.txt` 验证按键序列
4. 测试结束后关闭接收窗口

#### Scenario: 按键实际发送验证

- **WHEN** 启动 `periodic` 模式分组（pressKeys=["Space"]，interval=100ms，运行 1 秒）
- **THEN** `key_log.txt` 包含约 10 次 Space 按键事件，间隔在 100ms ± 20ms 容差范围内

### Requirement: 测试报告生成

系统 SHALL 在测试结束后自动生成 Markdown 测试报告，包含：

- 测试概览（总数、通过数、失败数、跳过数、通过率、总耗时）
- 按 suite 分组的详细结果（每个测试用例的名称、状态、耗时、失败原因）
- 失败用例的截图与日志附件路径
- 与历史报告的对比（首次运行可省略）

#### Scenario: 测试报告生成

- **WHEN** 所有 E2E 测试执行完毕
- **THEN** `docs/e2e-test-report.md` 被生成，包含上述所有字段

### Requirement: 测试用例 checklist

系统 SHALL 提供一份详细的功能测试用例 checklist，每个用例包含：

- 用例 ID（如 `E2E-CFG-001`）
- 用例标题
- 前置条件
- 测试步骤（编号列表）
- 预期结果
- 实际结果（测试运行后填充）
- 状态（Pass / Fail / Blocked / Skipped）
- 备注

#### Scenario: checklist 覆盖完整性

- **WHEN** 审阅 `docs/e2e-test-checklist.md`
- **THEN** checklist 覆盖所有 19 个 Tauri 命令、7 种执行模式、IPC 通信、按键验证，且每个用例字段完整

### Requirement: 已知问题清单 + 修复建议

系统 SHALL 整理测试中发现的所有问题，每个问题包含：

- 问题 ID（如 `ISSUE-001`）
- 严重程度（Critical / High / Medium / Low）
- 复现步骤
- 预期行为
- 实际行为
- 影响范围
- 修复建议
- 关联的测试用例 ID

#### Scenario: 已知问题清单

- **WHEN** 测试中发现问题
- **THEN** `docs/e2e-known-issues.md` 被更新，包含上述所有字段

## MODIFIED Requirements

### Requirement: AGENTS.md 测试章节

在 `AGENTS.md` 的 "Testing Requirements" 章节新增「E2E 测试」小节，说明：

- E2E 测试位于 `asd-tauri/e2e/`
- 运行命令：`cd asd-tauri/e2e && npm test`
- 前置条件：需要 tauri-driver 可执行文件、AHK v2 安装
- 测试范围：19 个 Tauri 命令、7 种执行模式、IPC 通信、按键验证

### Requirement: asd-tauri/docs/test-map.md 资产登记

在 test-map.md 新增「E2E 测试」章节，登记所有 E2E 测试资产（文件路径、用例数、覆盖范围）。

## REMOVED Requirements

无（本 spec 不删除任何现有功能）

## 设计决策

### 决策 1：使用 tauri-driver + WebDriverIO 而非 tauri::test

**理由**：
- tauri-driver 是 Tauri 官方推荐的 E2E 测试方案，通过 WebDriver 协议控制真实窗口
- WebDriverIO 是成熟的 Node.js 测试框架，社区活跃，文档完善
- tauri::test 仅能调用 invoke，无法模拟真实 UI 交互（点击、输入、拖拽）
- 用户明确选择 tauri-driver + WebDriverIO

**替代方案**：tauri::test 仅适合命令层测试，无法覆盖 UI 交互；Playwright 不原生支持 Tauri

### 决策 2：接收窗口法验证按键

**理由**：
- AHK 执行器通过 `Send`/`SendInput` 发送按键，最直接的验证方式是让按键发送到一个可见窗口
- 接收窗口法用一个 AHK GUI 窗口捕获所有按键事件，写入日志文件供测试读取
- 比日志插桩法更真实（验证了按键确实到达了目标窗口）
- 比低级键盘钩子法更简单（无需 WH_KEYBOARD_LL）
- 用户明确选择接收窗口法

**替代方案**：日志插桩法不验证真实发送；低级键盘钩子法实现复杂

### 决策 3：测试配置隔离

**理由**：
- E2E 测试不能污染用户真实的 `config.json`
- 使用 `fixtures/test_config.json` 作为测试专用配置
- 测试启动时通过 Tauri 命令 `save_config` 写入测试配置，测试结束后恢复原配置
- 备份测试通过 `tempfile` 创建临时目录，不操作真实 `backups/` 目录

### 决策 4：测试报告使用 Markdown 而非 HTML

**理由**：
- Markdown 易于版本控制、diff 对比、PR review
- WebDriverIO 的 spec-reporter 输出控制台，allure-reporter 输出 HTML；本 spec 选择自定义 Markdown 报告 + spec-reporter 控制台输出
- HTML 报告可作为后续增强项

### 决策 5：E2E 测试目录位于 `asd-tauri/e2e/` 而非 `asd-tauri/tests/`

**理由**：
- E2E 测试是独立的 Node.js 项目，有自己的 `package.json` 和 `node_modules/`
- 与 Rust 测试目录 `asd-tauri/tests/`（Cargo 集成测试）分离，避免混淆
- 已被 `.gitignore` 中的 `node_modules/` 规则覆盖

### 决策 6：覆盖范围全选

**理由**：
- 用户明确要求覆盖 19 个 Tauri 命令、7 种执行模式、IPC 通信、按键验证
- 不全选会导致关键链路未被验证，违背"测试所有功能"的初衷
