# ASD-Tauri 测试地图

本文件按 crate × 类型 × 文件 × 测试数 × 覆盖范围列出所有测试资源，用于测试资产盘点与新增测试登记。

> **唯一权威来源**：本文档是测试统计的**单一权威来源**。AGENTS.md 为架构/执行模式/依赖的唯一权威；TESTING.md、developer-guide.md、migration-guide.md 仅引用本文档、不自行复制测试数字。

统计口径（截至 2026-08-20，实测）：
- Rust：`#[test]` + `#[tokio::test]` 属性数（`cargo test --workspace` 实测）
- AHK 执行器：`Test_` 方法数（`tests/test_ahk_executor/*.ahk` 中以 `Test_` 开头的方法定义数）
- 运行用例：AHK v2 完整套件（`tests/run_all_tests.ahk` 汇总）与 E2E（WebDriverIO 用例数）

自洽关系：**小计 = 明细之和 = 汇总 = 各 crate 总计相加**。

---

## asd-domain

纯逻辑 crate — 领域模型、配置验证、trait 定义。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-domain | 单元 | crates/asd-domain/src/config.rs | 35 | Config / GroupConfig / ModeData / ControlHotkeys 序列化与默认值 |
| asd-domain | 单元 | crates/asd-domain/src/validator.rs | 51 | ConfigValidator 配置验证规则（按键、间隔、模式、热键） |
| asd-domain | 单元 | crates/asd-domain/src/models.rs | 3 | SkillGroup 领域模型构造与字段访问 |
| asd-domain | 集成 | crates/asd-domain/tests/integration_tests.rs | 43 | 跨模块配置解析与验证集成 |
| **小计** | — | — | **132** | — |

## asd-ipc-protocol

纯逻辑 crate — IPC 协议（命令、消息、错误、热键合并）。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/command.rs | 4 | IpcCommand 枚举序列化（13 variants） |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/message.rs | 24 | IpcMessage 构造器、序列化、字段访问 |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/error.rs | 5 | IpcError 错误类型与 Display 实现 |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/hotkey_merger.rs | 6 | HotkeyMerger 热键去重与合并 |
| asd-ipc-protocol | 集成 | crates/asd-ipc-protocol/tests/integration_tests.rs | 33 | IPC 协议端到端序列化/反序列化 |
| **小计** | — | — | **72** | — |

## asd-application

应用逻辑 crate — 调度器、状态、配置仓库、服务层。

### 单元测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-application | 单元 | crates/asd-application/src/state.rs | 36 | AppState 状态管理与 trait object 装配 |
| asd-application | 单元 | crates/asd-application/src/scheduler.rs | 17 | SkillManager 调度逻辑（Arc<dyn IpcSender>） |
| asd-application | 单元 | crates/asd-application/src/config_repository.rs | 24 | ConfigRepository 文件 I/O 与序列化 |
| asd-application | 单元 | crates/asd-application/src/time_format.rs | 4 | 时间格式化工具 |
| asd-application | 单元 | crates/asd-application/src/error.rs | 6 | AppError 错误类型 |
| **单元小计** | — | — | **87** | — |

### 集成测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-application | 集成 | crates/asd-application/tests/integration_tests.rs | 34 | 跨服务集成（AppState + Scheduler + ConfigRepo） |
| asd-application | 集成 | crates/asd-application/tests/backup_service_tests.rs | 17 | BackupService 备份创建与恢复 |
| asd-application | 集成 | crates/asd-application/tests/group_service_tests.rs | 16 | GroupService 分组增删改查 |
| asd-application | 集成 | crates/asd-application/tests/cross_crate_tests.rs | 13 | 跨 crate 边界（domain → application → ipc-protocol） |
| asd-application | 集成 | crates/asd-application/tests/recording_service_tests.rs | 11 | RecordingService 按键录制 |
| asd-application | 端到端 | crates/asd-application/tests/e2e_dataflow_tests.rs | 4 | 端到端数据流（Command → Bridge → AppState → Scheduler） |
| asd-application | 集成 | crates/asd-application/tests/concurrency_tests.rs | 4 | AppState 并发安全（Arc<Mutex> 验证） |
| **集成小计** | — | — | **99** | — |
| **总计** | — | — | **186** | — |

## asd-test-harness

测试工具 crate — Mock 实现与工厂函数（dev-dependency，含少量自测）。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-test-harness | 单元 | crates/asd-test-harness/src/lib.rs | 3 | MockIpcSender / MockEventEmitter / MockProcessWatcher / make_test_state 等工厂函数 |
| **小计** | — | — | **3** | — |

## asd-tauri（src-tauri）

Tauri 主 crate — 表现层 + 基础设施（IPC、Watchdog、Bridge、Commands）。

### 单元测试 + 内联集成测试（`--lib`）

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 单元 | src-tauri/src/infrastructure/ipc.rs | 45 | IpcManager named pipe 通信 |
| asd-tauri | 单元 | src-tauri/src/infrastructure/watchdog.rs | 29 | ProcessWatchdog + WatchdogRunner 进程管理 |
| asd-tauri | 集成 | src-tauri/src/tests/ipc_tests.rs | 26 | IPC 边界条件与错误处理 |
| asd-tauri | 集成 | src-tauri/src/tests/bridge_tests.rs | 13 | IpcBridge / TauriEventBridge / WatchdogBridge trait 实现 + build_hotkey_event_payload 纯函数（1 个 `#[ignore]`） |
| asd-tauri | 集成 | src-tauri/src/tests/watchdog_integration_tests.rs | 17 | ProcessWatchdog 跨平台集成（`#![cfg(windows)]` gating，15 个 `#[ignore]` 需 `--ignored` 手动运行） |
| asd-tauri | 集成 | src-tauri/src/tests/config_compat_tests.rs | 11 | Rust Config 与 AHK config.json 格式兼容性 |
| asd-tauri | 单元 | src-tauri/src/commands/config_cmd.rs | 29 | config_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/system_cmd.rs | 6 | get_system_status / emergency_release / toggle_hold_mode 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/hotkey_cmd.rs | 6 | register_hotkey / unregister_hotkey / list_hotkeys 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/group_cmd.rs | 20 | group_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/recording_cmd.rs | 21 | recording_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/lib.rs | 7 | IPC_PIPE_NAME 常量验证 + try_acquire_shutdown_guard 关机锁纯函数 |
| **小计** | — | — | **230** | — |

### 集成测试（`tests/` 目录）

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 集成 | src-tauri/tests/test_manifest_feature_removed.rs | 1 | 验证已废弃的 feature 已从 Cargo.toml 移除 |
| **asd-tauri 总计** | — | — | **231** | — |

## 基准测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 基准 | src-tauri/benches/benchmarks.rs | 7 | criterion 微基准（热路径性能回归检测） |

## 模糊测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_config_deserialize.rs | 1 target | Config 反序列化随机输入 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_ipc_command.rs | 1 target | IpcCommand 反序列化随机输入 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_ipc_json.rs | 1 target | IPC JSON 协议随机输入 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_ipc_message_parse.rs | 1 target | IpcMessage 解析后字段访问与方法调用 |
| asd-tauri | 模糊 | src-tauri/fuzz/fuzz_targets/fuzz_hotkey_merger.rs | 1 target | HotkeyMerger push/flush 逻辑 |

## AHK 执行器测试

使用项目根目录 `tests/AutoHotUnit.ahk` 框架，测试 `src-tauri/ahk_executor/` 下 5 个 AHK 脚本的纯逻辑方法。

| Crate | 类型 | 文件路径 | 套件数 / Test_ 方法数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| AHK | 单元 | tests/test_ahk_executor/test_executor.ahk | 9 / 46 | executor.ahk CommandDispatcher._GetStr/_GetInt/_GetBool/_GetArr/_GetMap、MergeModeConfig、Dispatch unknown、RecordKey、Validation |
| AHK | 单元 | tests/test_ahk_executor/test_ipc_client.ahk | 12 / 64 | ipc_client.ahk IPCConst、MiniJson 解析/序列化/往返/布尔标记、IpcClient 初始状态/序列号/断连接收/认证 token/去重 |
| AHK | 单元 | tests/test_ahk_executor/test_hotkey_hook.ahk | 7 / 28 | hotkey_hook.ahk Normalize、RegistrationState、Register/Unregister error、UnregisterAll、Init、Callback |
| AHK | 单元 | tests/test_ahk_executor/test_sender.ahk | 11 / 42 | sender.ahk AllowedKeys、ValidateKey、ToggleGroup、StartPeriodic/Sequence/Enhanced/Hold、HoldModeToggle、EmergencyRelease、Shutdown、Init |
| AHK | 单元 | tests/test_ahk_executor/test_joystick.ahk | 18 / 75 | joystick.ahk AllowedKeys、ValidateKey、IsButton/IsPov/IsAxis、GetButtonNum/GetPovDirection/GetAxisInfo、AxisToVJoyId、PovDirectionToValue、ResolveMethod、IsVJoyAvailable、StopGroup、EmergencyRelease、Init、StartPeriodic/Sequence/Hold |
| **总计** | — | — | **57 套件 / 255 个 Test_ 方法** | — |

注：AHK 测试文件位于项目根目录的 `tests/test_ahk_executor/`，非 `asd-tauri/tests/`。被测脚本位于 `asd-tauri/src-tauri/ahk_executor/`。

---

## 测试固件

| 文件路径 | 用途 | 引用方 |
|---------|------|-------|
| asd-tauri/tests/fixtures/configs/tests_config.json | 主测试配置样本（Task 1 迁移自 src-tauri/tests_config.json） | src-tauri/src/tests/config_compat_tests.rs |
| asd-tauri/src-tauri/config.json | 主运行时配置样本（`MAIN_CONFIG_JSON`，经 `include_str!("../../config.json")` 引用，用于 Config roundtrip 序列化兼容性验证） | src-tauri/src/tests/config_compat_tests.rs |

---

## 汇总

| 类别 | 统计 |
|------|------|
| Rust 测试函数（`#[test]` + `#[tokio::test]` 属性数） | 624（asd-domain 132 + asd-ipc-protocol 72 + asd-application 186 + asd-test-harness 3 + asd-tauri 231；其中 `#[ignore]` 16 个） |
| AHK 执行器测试（`Test_` 方法数） | 57 套件 / 255 个 `Test_` 方法 |
| AHK v2 完整测试套件（`tests/run_all_tests.ahk` 汇总） | 607 个用例（通过 607 / 失败 0） |
| 基准测试 | 7 个 criterion bench |
| 模糊测试 | 5 个 fuzz target |
| E2E 测试 | 9 suite / 53 用例 |

自洽校验：各 crate「小计 = 明细之和」，上表 Rust 总数 = asd-domain + asd-ipc-protocol + asd-application + asd-test-harness + asd-tauri = 132 + 72 + 186 + 3 + 231 = 624。

> **备注（T8-07† 处置）**：`docs/review/2026-08-20/task-8-tests.md` 分报告《总结》自报「发现总数 7（Important 3 + Minor 4）」，但正文仅列 T8-01~T8-06 共 6 条（其中 Minor 3 条：T8-04/T8-05/T8-06）。已核实第 4 条 Minor 无正文，属该报告自报计数笔误（正文实际为 Important 3 + Minor 3 = 6 条），无遗漏问题，占位 `T8-07†` 予以关闭。

---

## E2E 测试

使用 tauri-driver + WebDriverIO 框架，在真实 Windows 桌面环境下测试完整应用链路。

| Suite | 文件路径 | 用例数 | 覆盖范围 |
|-------|---------|-------|---------|
| E2E | asd-tauri/e2e/specs/smoke.spec.js | 1 | 应用启动与关闭冒烟测试 |
| E2E | asd-tauri/e2e/specs/config_cmd.spec.js | 12 | 11 个 config_cmd 命令 |
| E2E | asd-tauri/e2e/specs/group_cmd.spec.js | 8 | 8 个 group_cmd 命令 |
| E2E | asd-tauri/e2e/specs/hotkey_cmd.spec.js | 3 | 2 个 hotkey_cmd 命令 + 热键触发 |
| E2E | asd-tauri/e2e/specs/recording_cmd.spec.js | 5 | 4 个 recording_cmd 命令 + 状态机 |
| E2E | asd-tauri/e2e/specs/system_cmd.spec.js | 5 | 5 个 system_cmd 命令 |
| E2E | asd-tauri/e2e/specs/modes.spec.js | 7 | 7 种执行模式（系统共支持 10 种，`joystick_*` 三种未纳入 E2E） |
| E2E | asd-tauri/e2e/specs/ipc.spec.js | 7 | Rust↔AHK IPC 通信 |
| E2E | asd-tauri/e2e/specs/key_send.spec.js | 5 | AHK 执行器按键验证 |
| **总计** | — | **53** | — |

> **执行模式口径**：系统能力共 10 种执行模式（见 AGENTS.md「支持的执行模式」）；E2E 覆盖 7 种（`modes.spec.js`），`joystick_periodic` / `joystick_sequence` / `joystick_hold` 三种未纳入 E2E。两口径分别标注，不混用。

### E2E 测试固件

| 文件路径 | 用途 |
|---------|------|
| asd-tauri/e2e/fixtures/test_config.json | 测试专用配置（7 模式分组） |
| asd-tauri/e2e/fixtures/key_receiver.ahk | AHK 按键接收窗口（捕获按键事件） |
| asd-tauri/e2e/helpers/tauri.js | Tauri 交互辅助（invoke/getConfig/saveConfig） |
| asd-tauri/e2e/helpers/config.js | 配置管理辅助（备份/恢复/加载测试配置） |
| asd-tauri/e2e/helpers/key_receiver.js | 按键接收器辅助（启停/读取/断言） |
| asd-tauri/e2e/helpers/report.js | 测试报告辅助（结果收集/Markdown 生成） |
| asd-tauri/e2e/helpers/ahk_path.js | AHK v2 可执行文件路径集中管理（`AHK_PATH` 环境变量覆盖默认路径，消除硬编码） |
| asd-tauri/e2e/helpers/error_utils.js | 错误消息提取（`extractErrorMessage`，兼容 AppError 结构化对象/Error 实例/字符串） |
| asd-tauri/e2e/helpers/spec-hooks.js | 共享 spec 生命周期钩子工厂（before/beforeEach/afterEach/after + `extractCaseId` + `DEFAULT_FAILURE_SEVERITY`） |
| asd-tauri/e2e/helpers/__tests__/ahk_path.test.js | ahk_path.js 单元测试（node:test） |
| asd-tauri/e2e/helpers/__tests__/error_utils.test.js | error_utils.js 单元测试（node:test） |

### 运行方式

```bash
# 前置条件
cargo install tauri-driver --locked
cd asd-tauri && cargo build --release
cd asd-tauri/e2e && npm install

# 运行
cd asd-tauri/e2e && npm test
```

### E2E 测试文档

| 文档 | 路径 | 用途 |
|------|------|------|
| E2E 测试报告 | docs/e2e-test-report.md | 53 个用例的状态总览（PENDING/PASS/FAIL） |
| E2E 测试 Checklist | docs/e2e-test-checklist.md | 每个用例的前置条件、步骤、预期结果 |
| E2E 已知问题 | docs/e2e-known-issues.md | 10 个已知问题与修复建议 |

---

## 维护规范

1. **新增测试文件**：在本地图的对应 crate 小节追加一行，记录文件路径、测试数、覆盖范围。
2. **新增测试固件**：在「测试固件」章节登记路径、用途、引用方。
3. **测试数变更**：每次合并 PR 后更新本地图的测试数列，保持与实际 `#[test]` 计数一致，并同步校验「小计 = 明细之和 = 汇总」。
4. **统计命令**：
   ```powershell
   # 各 crate 实际测试数（权威）：运行测试并查看 test result
   cargo test --workspace 2>&1 | Select-String "test result"
   # 各 crate 的 #[test] + #[tokio::test] 属性数（用于明细表）
   Get-ChildItem -Path .\crates,.\src-tauri\src -Recurse -Filter *.rs | ForEach-Object {
     $content = Get-Content $_.FullName -Raw
     $count = ([regex]::Matches($content, '#\[test\]|#\[tokio::test')).Count
     if ($count -gt 0) { "$($_.FullName): $count" }
   }
   # AHK 执行器 Test_ 方法数
   (Get-ChildItem .\tests\test_ahk_executor\*.ahk | ForEach-Object { (Select-String -Path $_.FullName -Pattern '^\s*Test_[A-Za-z0-9_]+').Count } )
   ```
