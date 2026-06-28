# AHK 执行器自动化测试 Spec

## Why

`asd-tauri/src-tauri/ahk_executor/` 目录下的 5 个 AHK 脚本（executor.ahk、ipc_client.ahk、hotkey_hook.ahk、sender.ahk、joystick.ahk）作为 Rust/Tauri 主进程的子进程执行器，承载热键注册、按键模拟、vJoy 调用等关键运行时逻辑，但目前缺少自动化测试覆盖，无法在不依赖 Rust 主进程的前提下验证其内部逻辑正确性，存在回归风险。

复用项目根目录已有的 AutoHotUnit 测试框架，为 5 个被测脚本中可静态验证的辅助方法（按键白名单校验、JSON 解析、热键规范化、IpcClient 消息构造、vJoy 方法解析等）编写自动化测试，建立可独立运行的测试基线，使后续重构具备回归保障。

## What Changes

- 新建 `tests/test_ahk_executor/` 测试目录
- 新建 5 个测试文件，每个测试文件通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/<被测脚本>.ahk"` 引入被测代码，并通过 `#Include "../AutoHotUnit.ahk"` 引入测试框架
- 新建 `tests/test_ahk_executor/test_executor.ahk`：测试 `CommandDispatcher` 的辅助方法（GetStr/GetInt/GetBool/GetArr/GetMap/MergeModeConfig/Dispatch 未知命令/RecordKey/ValidateConfig 等）
- 新建 `tests/test_ahk_executor/test_ipc_client.ahk`：测试 `MiniJson` 解析器与 `IpcClient` 消息构造（NextSeq/parse auth token/重复消息去重等）
- 新建 `tests/test_ahk_executor/test_hotkey_hook.ahk`：测试 `HotkeyHook` 的按键规范化、注册/注销状态、错误处理路径
- 新建 `tests/test_ahk_executor/test_sender.ahk`：测试 `Sender` 的按键白名单、分组 Toggle、Periodic/Sequence/Enhanced/Hold 启动逻辑、EmergencyRelease、Shutdown 等
- 新建 `tests/test_ahk_executor/test_joystick.ahk`：测试 `Joystick` 的按键类型识别、按钮/POV/Axis/Trigger 解析、vJoy 方法解析、StopGroup/EmergencyRelease/Init/Start* 等
- 修改 `asd-tauri/src-tauri/ahk_executor/executor.ahk`：将 `OnError`、`OnExit`、`Executor_Init()` 调用包装在 main guard（`if (A_LineFile = A_ScriptFullPath)`）中，使脚本在被 `#Include` 时不自动初始化（避免测试进程因 auth token 缺失而 ExitApp(1)）
- 修改 `tests/run_all_tests.ahk`：在 `#Include` 区段追加 5 个测试文件的 Include，并在测试套件注册区段追加新套件类的 `RegisterSuite` 调用
- 5 个测试文件顶部必须包含完整的错误接管指令（`#ErrorStdOut "UTF-8"` + `#Warn VarUnset/Unreachable, OutputDebug` + `#Warn LocalSameAsGlobal, Off` + `OnError` 回调），遵循 AGENTS.md 强制规范
- 5 个测试文件不得使用箭头函数块体 `=> { }`（AHK v2 语法陷阱），必须使用逗号表达式或闭包函数替代

## Impact

- Affected specs: `plan-rust-tauri-implementation`（Phase 4 Task 4.1-4.2 的 AHK 执行器实现，本任务为其补齐测试覆盖）、`rust-tauri-migration`（Phase 5 Task 5.1 测试体系的 AHK 侧补充）
- Affected code:
  - `asd-tauri/src-tauri/ahk_executor/executor.ahk`（main guard 重构，外部行为不变）
  - `tests/run_all_tests.ahk`（追加注册新套件）
  - `tests/test_ahk_executor/`（新建目录与 5 个测试文件）
- 不影响 Rust/Tauri 侧代码、不影响前端代码、不影响 AHK v2 主脚本（domain/infrastructure/application/presentation）
- 不破坏现有 198 个 Rust 单元/集成测试与既有 AHK 测试套件

## ADDED Requirements

### Requirement: AHK 执行器测试目录与文件结构

系统 SHALL 在 `tests/test_ahk_executor/` 目录下创建 5 个测试文件，分别对应 5 个被测脚本，文件命名遵循 `test_<被测脚本名>.ahk` 模式。

#### Scenario: 目录与文件存在
- **WHEN** 检查 `tests/test_ahk_executor/` 目录
- **THEN** 目录存在且包含 test_executor.ahk、test_ipc_client.ahk、test_hotkey_hook.ahk、test_sender.ahk、test_joystick.ahk 5 个文件

#### Scenario: 每个测试文件均能独立加载
- **WHEN** 使用 `AutoHotkey64.exe /ErrorStdOut <测试文件>` 执行语法检查
- **THEN** 退出码为 0（无加载时语法错误）
- **AND** stderr 无输出

### Requirement: 测试文件遵循 AGENTS.md 错误接管规范

每个测试文件 SHALL 顶部包含以下指令序列：
1. `#Requires AutoHotkey v2.0`
2. `#ErrorStdOut "UTF-8"`
3. `#Include "../../asd-tauri/src-tauri/ahk_executor/<被测脚本>.ahk"`（被测脚本，main guard 保证不自动初始化）
4. `#Include "../AutoHotUnit.ahk"`（测试框架基类 AutoHotUnitSuite）
5. `#Warn VarUnset, OutputDebug`（在 #Include 之后，覆盖 AutoHotUnit.ahk 的 `#Warn All, StdOut`）
6. `#Warn Unreachable, OutputDebug`
7. `#Warn LocalSameAsGlobal, Off`
8. `OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))`

#### Scenario: 测试文件包含错误接管指令
- **WHEN** 检查任意测试文件头部
- **THEN** 文件包含 `#ErrorStdOut "UTF-8"`、`#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`OnError` 回调
- **AND** `#Warn` 指令出现在 `#Include "../AutoHotUnit.ahk"` 之后

#### Scenario: 运行时错误不弹窗
- **WHEN** 测试执行期间触发运行时错误
- **THEN** OnError 回调将错误信息写入 stdout（通过 `FileAppend(..., "*")`）
- **AND** 回调返回 true 阻止默认错误对话框弹出

### Requirement: executor.ahk 可测试性（main guard）

executor.ahk SHALL 使用 `if (A_LineFile = A_ScriptFullPath)` main guard 包装以下三段代码：
1. `OnError((e, mode) => (OutputDebug("RUNTIME_ERROR: " e.Message " at line " e.Line), true))`
2. `OnExit((exitCode, exitReason) => (Executor_Shutdown(), 0))`
3. `Executor_Init()`

#### Scenario: 直接运行 executor.ahk 时正常初始化
- **WHEN** 通过 `AutoHotkey64.exe executor.ahk` 直接运行
- **THEN** OnError、OnExit、Executor_Init() 全部生效
- **AND** 因 auth token 缺失最终 ExitApp(1)（预期行为，非测试场景）

#### Scenario: 被 #Include 时不自动初始化
- **WHEN** 测试文件通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/executor.ahk"` 引入
- **THEN** Executor_Init() 不被调用
- **AND** 测试进程不因 auth token 缺失而退出
- **AND** CommandDispatcher 类及其辅助方法定义仍可用

### Requirement: 测试覆盖范围

5 个测试文件 SHALL 覆盖以下被测方法/类（不依赖外部 Rust 主进程、不依赖 vJoy SDK 实际加载、不依赖 SendInput 副作用）：

| 测试文件 | 被测脚本 | 覆盖内容 |
|---------|---------|---------|
| test_executor.ahk | executor.ahk | CommandDispatcher.GetStr/GetInt/GetBool/GetArr/GetMap/MergeModeConfig/Dispatch 未知命令/RecordKey/ValidateConfig |
| test_ipc_client.ahk | ipc_client.ahk | MiniJson.Parse 对象/数组/标量/字符串/转义/嵌套、MiniJson.Stringify、roundtrip、IpcClient 初始状态/NextSeq/未连接发送/解析 auth token/重复消息去重 |
| test_hotkey_hook.ahk | hotkey_hook.ahk | HotkeyHook 规范化（大小写/组合键修饰符顺序）、注册状态、注册/注销错误路径、UnregisterAll、Init、回调触发 |
| test_sender.ahk | sender.ahk | Sender 按键白名单（allowedKeys 集合）、ValidateKey、ToggleGroup 状态切换、StartPeriodic/StartSequence/StartEnhanced/StartHold 启动逻辑、HoldMode 切换、EmergencyRelease、Shutdown、Init |
| test_joystick.ahk | joystick.ahk | Joystick 按键识别（IsButton/IsPov/IsAxis/IsTrigger）、GetButtonNum/GetPovDirection/GetAxisInfo、AxisToVJoyId/PovDirectionToValue、ResolveMethod、IsVJoyAvailable、StopGroup/EmergencyRelease/Init/StartPeriodic/StartSequence/StartHold |

#### Scenario: 测试覆盖各被测脚本的核心静态方法
- **WHEN** 运行 `tests/run_all_tests.ahk`
- **THEN** 5 个测试套件中的所有 `Test_*` 方法被执行
- **AND** 测试套件通过 `RegisterSuite` 注册到 `AutoHotUnitManager`

#### Scenario: Sender/Joystick 副作用隔离
- **WHEN** 测试 Sender.StartHold 时
- **THEN** 使用非白名单按键（如 "F13"）避免实际 SendInput 副作用
- **AND** 在 `afterAll()` 中调用 `EmergencyRelease()` 清理静态 Map 状态

### Requirement: run_all_tests.ahk 注册新套件

`tests/run_all_tests.ahk` SHALL：
1. 在 `#Include` 区段末尾追加 5 行：
   ```autohotkey
   #Include "test_ahk_executor/test_executor.ahk"
   #Include "test_ahk_executor/test_ipc_client.ahk"
   #Include "test_ahk_executor/test_hotkey_hook.ahk"
   #Include "test_ahk_executor/test_sender.ahk"
   #Include "test_ahk_executor/test_joystick.ahk"
   ```
2. 在 `RegisterSuite` 调用区段追加新套件类的注册

#### Scenario: run_all_tests.ahk 包含新测试
- **WHEN** 运行 `AutoHotkey64.exe tests/run_all_tests.ahk`
- **THEN** 5 个新套件被执行
- **AND** 输出报告包含新套件的测试结果

### Requirement: 完整测试运行通过

#### Scenario: 所有测试通过
- **WHEN** 执行 `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" d:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk`
- **THEN** 退出码为 0
- **AND** 输出报告显示所有新测试套件全部通过（0 失败）

### Requirement: 5 个测试文件可独立运行

#### Scenario: 单独运行任一测试文件
- **WHEN** 执行 `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests/test_ahk_executor/test_<name>.ahk`
- **THEN** 该测试文件运行结束（不依赖其他测试文件）
- **AND** 退出码反映测试结果（0 通过，非 0 失败）

## MODIFIED Requirements

### Requirement: executor.ahk 初始化流程（main guard 包装）

executor.ahk 末尾的 `OnError`/`OnExit`/`Executor_Init()` 调用 SHALL 被包装在 `if (A_LineFile = A_ScriptFullPath)` 条件块中，确保脚本在被 `#Include` 时不触发自动初始化逻辑（auth token 解析、IPC 连接、心跳启动等），仅在被直接运行时执行。

外部行为（直接运行时的初始化流程）保持不变。

## REMOVED Requirements

无（本次任务为新增测试，不删除任何现有功能或测试）。
