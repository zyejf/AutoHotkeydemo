# ASD-Tauri 测试地图

本文件按 crate × 类型 × 文件 × 测试数 × 覆盖范围列出所有测试资源，用于测试资产盘点与新增测试登记。

数据基于 2026-06-27 统计（`#[test]` + `#[tokio::test]` 标记计数，误差 ≤ 5%）。

---

## asd-domain

纯逻辑 crate — 领域模型、配置验证、trait 定义。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-domain | 单元 | crates/asd-domain/src/config.rs | 35 | Config / GroupConfig / ModeData / ControlHotkeys 序列化与默认值 |
| asd-domain | 单元 | crates/asd-domain/src/validator.rs | 48 | ConfigValidator 配置验证规则（按键、间隔、模式、热键） |
| asd-domain | 单元 | crates/asd-domain/src/models.rs | 3 | SkillGroup 领域模型构造与字段访问 |
| asd-domain | 集成 | crates/asd-domain/tests/integration_tests.rs | 43 | 跨模块配置解析与验证集成 |
| **小计** | — | — | **129** | — |

## asd-ipc-protocol

纯逻辑 crate — IPC 协议（命令、消息、错误、热键合并）。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/command.rs | 3 | IpcCommand 枚举序列化（13 variants） |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/message.rs | 24 | IpcMessage 构造器、序列化、字段访问 |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/error.rs | 5 | IpcError 错误类型与 Display 实现 |
| asd-ipc-protocol | 单元 | crates/asd-ipc-protocol/src/hotkey_merger.rs | 6 | HotkeyMerger 热键去重与合并 |
| asd-ipc-protocol | 集成 | crates/asd-ipc-protocol/tests/integration_tests.rs | 33 | IPC 协议端到端序列化/反序列化 |
| **小计** | — | — | **71** | — |

## asd-application

应用逻辑 crate — 调度器、状态、配置仓库、服务层。

### 单元测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-application | 单元 | crates/asd-application/src/state.rs | 36 | AppState 状态管理与 trait object 装配 |
| asd-application | 单元 | crates/asd-application/src/scheduler.rs | 17 | SkillManager 调度逻辑（Arc<dyn IpcSender>） |
| asd-application | 单元 | crates/asd-application/src/config_repository.rs | 24 | ConfigRepository 文件 I/O 与序列化 |
| asd-application | 单元 | crates/asd-application/src/time_format.rs | 4 | 时间格式化工具 |
| asd-application | 单元 | crates/asd-application/src/error.rs | 5 | AppError 错误类型 |
| **单元小计** | — | — | **86** | — |

### 集成测试

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-application | 集成 | crates/asd-application/tests/integration_tests.rs | 36 | 跨服务集成（AppState + Scheduler + ConfigRepo） |
| asd-application | 集成 | crates/asd-application/tests/backup_service_tests.rs | 17 | BackupService 备份创建与恢复 |
| asd-application | 集成 | crates/asd-application/tests/group_service_tests.rs | 16 | GroupService 分组增删改查 |
| asd-application | 集成 | crates/asd-application/tests/cross_crate_tests.rs | 13 | 跨 crate 边界（domain → application → ipc-protocol） |
| asd-application | 集成 | crates/asd-application/tests/recording_service_tests.rs | 11 | RecordingService 按键录制 |
| asd-application | 端到端 | crates/asd-application/tests/e2e_dataflow_tests.rs | 4 | 端到端数据流（Command → Bridge → AppState → Scheduler） |
| asd-application | 集成 | crates/asd-application/tests/concurrency_tests.rs | 4 | AppState 并发安全（Arc<Mutex> 验证） |
| **集成小计** | — | — | **101** | — |
| **总计** | — | — | **187** | — |

## asd-test-harness

测试工具 crate — Mock 实现与工厂函数（仅作为 dev-dependency，无自测）。

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-test-harness | — | crates/asd-test-harness/src/lib.rs | 0 | MockIpcSender / MockEventEmitter / MockProcessWatcher / make_test_state 等工厂函数 |
| **小计** | — | — | **0** | — |

## asd-tauri（src-tauri）

Tauri 主 crate — 表现层 + 基础设施（IPC、Watchdog、Bridge、Commands）。

### 单元测试 + 内联集成测试（`--lib`）

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 单元 | src-tauri/src/infrastructure/ipc.rs | 35 | IpcManager named pipe 通信 |
| asd-tauri | 单元 | src-tauri/src/infrastructure/watchdog.rs | 21 | ProcessWatchdog + WatchdogRunner 进程管理 |
| asd-tauri | 集成 | src-tauri/src/tests/ipc_tests.rs | 26 | IPC 边界条件与错误处理 |
| asd-tauri | 集成 | src-tauri/src/tests/bridge_tests.rs | 13 | IpcBridge / TauriEventBridge / WatchdogBridge trait 实现 + build_hotkey_event_payload 纯函数 |
| asd-tauri | 集成 | src-tauri/src/tests/watchdog_integration_tests.rs | 17 | ProcessWatchdog 跨平台集成（`#![cfg(windows)]` gating） |
| asd-tauri | 集成 | src-tauri/src/tests/config_compat_tests.rs | 11 | Rust Config 与 AHK config.json 格式兼容性 |
| asd-tauri | 单元 | src-tauri/src/commands/config_cmd.rs | 7 | config_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/system_cmd.rs | 6 | get_system_status / emergency_release / toggle_hold_mode 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/hotkey_cmd.rs | 6 | register_hotkey / unregister_hotkey / list_hotkeys 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/group_cmd.rs | 4 | group_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/commands/recording_cmd.rs | 3 | recording_cmd Tauri 命令 |
| asd-tauri | 单元 | src-tauri/src/lib.rs | 4 | IPC_PIPE_NAME 常量验证 + try_acquire_shutdown_guard 关机锁纯函数 |
| **小计** | — | — | **153** | — |

### 集成测试（`tests/` 目录）

| Crate | 类型 | 文件路径 | 测试数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| asd-tauri | 集成 | src-tauri/tests/test_manifest_feature_removed.rs | 1 | 验证 test-manifest feature 已从 Cargo.toml 移除 |
| **总计** | — | — | **217** | — |

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

| Crate | 类型 | 文件路径 | 套件数 | 覆盖范围 |
|-------|------|---------|-------|---------|
| AHK | 单元 | tests/test_ahk_executor/test_executor.ahk | 9 | executor.ahk CommandDispatcher._GetStr/_GetInt/_GetBool/_GetArr/_GetMap、MergeModeConfig、Dispatch unknown、RecordKey、Validation |
| AHK | 单元 | tests/test_ahk_executor/test_ipc_client.ahk | 12 | ipc_client.ahk IPCConst、MiniJson 解析/序列化/往返/布尔标记、IpcClient 初始状态/序列号/断连接收/认证 token/去重 |
| AHK | 单元 | tests/test_ahk_executor/test_hotkey_hook.ahk | 7 | hotkey_hook.ahk Normalize、RegistrationState、Register/Unregister error、UnregisterAll、Init、Callback |
| AHK | 单元 | tests/test_ahk_executor/test_sender.ahk | 11 | sender.ahk AllowedKeys、ValidateKey、ToggleGroup、StartPeriodic/Sequence/Enhanced/Hold、HoldModeToggle、EmergencyRelease、Shutdown、Init |
| AHK | 单元 | tests/test_ahk_executor/test_joystick.ahk | 18 | joystick.ahk AllowedKeys、ValidateKey、IsButton/IsPov/IsAxis、GetButtonNum/GetPovDirection/GetAxisInfo、AxisToVJoyId、PovDirectionToValue、ResolveMethod、IsVJoyAvailable、StopGroup、EmergencyRelease、Init、StartPeriodic/Sequence/Hold |
| **总计** | — | — | **57 套件 / 467 测试** | — |

注：AHK 测试文件位于项目根目录的 `tests/test_ahk_executor/`，非 `asd-tauri/tests/`。被测脚本位于 `asd-tauri/src-tauri/ahk_executor/`。

---

## 测试固件

| 文件路径 | 用途 | 引用方 |
|---------|------|-------|
| asd-tauri/tests/fixtures/configs/tests_config.json | 主测试配置样本（Task 1 迁移自 src-tauri/tests_config.json） | src-tauri/src/tests/config_compat_tests.rs |

---

## 汇总

| 类别 | 测试数 |
|------|-------|
| Rust 测试函数（`#[test]` + `#[tokio::test]`） | 609（asd-domain 129 + asd-ipc-protocol 72 + asd-application 187 + asd-test-harness 4 + asd-tauri 217） |
| AHK 执行器测试 | 57 套件 / 467 测试 |
| 基准测试 | 7 个 criterion bench |
| 模糊测试 | 5 个 fuzz target |
| **Rust + AHK 总计** | **609 测试函数 + 467 AHK 测试** |

文档统计标称值与实际计数的误差 ≤ 5%，符合 spec 要求。

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
| E2E | asd-tauri/e2e/specs/modes.spec.js | 7 | 7 种执行模式 |
| E2E | asd-tauri/e2e/specs/ipc.spec.js | 7 | Rust↔AHK IPC 通信 |
| E2E | asd-tauri/e2e/specs/key_send.spec.js | 5 | AHK 执行器按键验证 |
| **总计** | — | **53** | — |

### E2E 测试固件

| 文件路径 | 用途 |
|---------|------|
| asd-tauri/e2e/fixtures/test_config.json | 测试专用配置（7 模式分组） |
| asd-tauri/e2e/fixtures/key_receiver.ahk | AHK 按键接收窗口（捕获按键事件） |
| asd-tauri/e2e/helpers/tauri.js | Tauri 交互辅助（invoke/getConfig/saveConfig） |
| asd-tauri/e2e/helpers/config.js | 配置管理辅助（备份/恢复/加载测试配置） |
| asd-tauri/e2e/helpers/key_receiver.js | 按键接收器辅助（启停/读取/断言） |
| asd-tauri/e2e/helpers/report.js | 测试报告辅助（结果收集/Markdown 生成） |

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
3. **测试数变更**：每次合并 PR 后更新本地图的测试数列，保持与实际 `#[test]` 计数误差 ≤ 5%。
4. **统计命令**：
   ```powershell
   # 统计各 crate 的 #[test] + #[tokio::test] 数
   Get-ChildItem -Path .\crates,.\src-tauri\src -Recurse -Filter *.rs | ForEach-Object {
     $content = Get-Content $_.FullName -Raw
     $count = ([regex]::Matches($content, '#\[test\]|#\[tokio::test')).Count
     if ($count -gt 0) { "$($_.FullName): $count" }
   }
   ```
