# Checklist

## Phase A: 准备与可测试性重构

- [x] `tests/test_ahk_executor/` 目录已创建
- [x] `asd-tauri/src-tauri/ahk_executor/executor.ahk` 末尾的 `OnError` 调用已包装在 `if (A_LineFile = A_ScriptFullPath)` main guard 中
- [x] `asd-tauri/src-tauri/ahk_executor/executor.ahk` 末尾的 `OnExit` 调用已包装在 main guard 中
- [x] `asd-tauri/src-tauri/ahk_executor/executor.ahk` 末尾的 `Executor_Init()` 调用已包装在 main guard 中
- [x] 直接运行 executor.ahk 仍能正常初始化（auth token 缺失时 ExitApp(1)，stderr 无输出）

## Phase B: 测试文件头部规范（5 个文件均需满足）

- [x] test_executor.ahk 头部包含 `#Requires AutoHotkey v2.0`
- [x] test_executor.ahk 头部包含 `#ErrorStdOut "UTF-8"`
- [x] test_executor.ahk 通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/executor.ahk"` 引入被测脚本
- [x] test_executor.ahk 通过 `#Include "../AutoHotUnit.ahk"` 引入测试框架
- [x] test_executor.ahk 的 `#Warn VarUnset, OutputDebug` 出现在 `#Include "../AutoHotUnit.ahk"` 之后
- [x] test_executor.ahk 的 `#Warn Unreachable, OutputDebug` 出现在 `#Include "../AutoHotUnit.ahk"` 之后
- [x] test_executor.ahk 包含 `#Warn LocalSameAsGlobal, Off`
- [x] test_executor.ahk 包含 `OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))` 回调

- [x] test_ipc_client.ahk 头部包含 `#Requires AutoHotkey v2.0`
- [x] test_ipc_client.ahk 头部包含 `#ErrorStdOut "UTF-8"`
- [x] test_ipc_client.ahk 通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/ipc_client.ahk"` 引入被测脚本
- [x] test_ipc_client.ahk 通过 `#Include "../AutoHotUnit.ahk"` 引入测试框架
- [x] test_ipc_client.ahk 的 `#Warn` 三联出现在 `#Include "../AutoHotUnit.ahk"` 之后
- [x] test_ipc_client.ahk 包含 `OnError` 回调

- [x] test_hotkey_hook.ahk 头部包含 `#Requires AutoHotkey v2.0`
- [x] test_hotkey_hook.ahk 头部包含 `#ErrorStdOut "UTF-8"`
- [x] test_hotkey_hook.ahk 通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/hotkey_hook.ahk"` 引入被测脚本
- [x] test_hotkey_hook.ahk 通过 `#Include "../AutoHotUnit.ahk"` 引入测试框架
- [x] test_hotkey_hook.ahk 的 `#Warn` 三联出现在 `#Include "../AutoHotUnit.ahk"` 之后
- [x] test_hotkey_hook.ahk 包含 `OnError` 回调

- [x] test_sender.ahk 头部包含 `#Requires AutoHotkey v2.0`
- [x] test_sender.ahk 头部包含 `#ErrorStdOut "UTF-8"`
- [x] test_sender.ahk 通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/sender.ahk"` 引入被测脚本
- [x] test_sender.ahk 通过 `#Include "../AutoHotUnit.ahk"` 引入测试框架
- [x] test_sender.ahk 的 `#Warn` 三联出现在 `#Include "../AutoHotUnit.ahk"` 之后
- [x] test_sender.ahk 包含 `OnError` 回调

- [x] test_joystick.ahk 头部包含 `#Requires AutoHotkey v2.0`
- [x] test_joystick.ahk 头部包含 `#ErrorStdOut "UTF-8"`
- [x] test_joystick.ahk 通过 `#Include "../../asd-tauri/src-tauri/ahk_executor/joystick.ahk"` 引入被测脚本
- [x] test_joystick.ahk 通过 `#Include "../AutoHotUnit.ahk"` 引入测试框架
- [x] test_joystick.ahk 的 `#Warn` 三联出现在 `#Include "../AutoHotUnit.ahk"` 之后
- [x] test_joystick.ahk 包含 `OnError` 回调

## Phase B: 测试内容覆盖

- [x] test_executor.ahk 覆盖 CommandDispatcher.GetStr/GetInt/GetBool/GetArr/GetMap
- [x] test_executor.ahk 覆盖 CommandDispatcher.MergeModeConfig
- [x] test_executor.ahk 覆盖 CommandDispatcher.Dispatch 未知命令
- [x] test_executor.ahk 覆盖 CommandDispatcher.RecordKey
- [x] test_executor.ahk 覆盖 CommandDispatcher.ValidateConfig
- [x] test_ipc_client.ahk 覆盖 MiniJson.Parse 对象/数组/标量/字符串/转义/嵌套
- [x] test_ipc_client.ahk 覆盖 MiniJson.Stringify
- [x] test_ipc_client.ahk 覆盖 MiniJson roundtrip
- [x] test_ipc_client.ahk 覆盖 IpcClient 初始状态/NextSeq/未连接发送
- [x] test_ipc_client.ahk 覆盖 IpcClient 解析 auth token/重复消息去重
- [x] test_hotkey_hook.ahk 覆盖 HotkeyHook 规范化（大小写/组合键修饰符顺序）
- [x] test_hotkey_hook.ahk 覆盖 HotkeyHook 注册状态
- [x] test_hotkey_hook.ahk 覆盖 HotkeyHook 注册/注销错误路径
- [x] test_hotkey_hook.ahk 覆盖 HotkeyHook UnregisterAll/Init/回调触发
- [x] test_sender.ahk 覆盖 Sender 按键白名单（allowedKeys 集合）
- [x] test_sender.ahk 覆盖 Sender ValidateKey
- [x] test_sender.ahk 覆盖 Sender ToggleGroup 状态切换
- [x] test_sender.ahk 覆盖 Sender StartPeriodic/StartSequence/StartEnhanced/StartHold
- [x] test_sender.ahk 覆盖 Sender HoldMode 切换/EmergencyRelease/Shutdown/Init
- [x] test_joystick.ahk 覆盖 Joystick 按键识别（IsButton/IsPov/IsAxis/IsTrigger）
- [x] test_joystick.ahk 覆盖 Joystick GetButtonNum/GetPovDirection/GetAxisInfo
- [x] test_joystick.ahk 覆盖 Joystick AxisToVJoyId/PovDirectionToValue
- [x] test_joystick.ahk 覆盖 Joystick ResolveMethod/IsVJoyAvailable
- [x] test_joystick.ahk 覆盖 Joystick StopGroup/EmergencyRelease/Init/StartPeriodic/StartSequence/StartHold

## Phase B: 副作用隔离

- [x] test_sender.ahk 使用非白名单按键 "F13" 避免 SendInput 副作用
- [x] test_sender.ahk 在 afterAll 中调用 EmergencyRelease 清理静态 Map 状态
- [x] test_joystick.ahk 在 afterAll 中清理静态状态（JoystickStartPeriodic/Sequence/HoldTests 均调用 EmergencyRelease）

## Phase C: 集成

- [x] `tests/run_all_tests.ahk` 在 `#Include` 区段末尾追加 5 行 Include
- [x] `tests/run_all_tests.ahk` 在 RegisterSuite 区段追加新套件类的注册（57 个套件）
- [x] `tests/run_all_tests.ahk` 语法检查通过（exit code 0）

## Phase C: 验证

- [x] test_executor.ahk 语法检查通过（exit code 0，stderr 为空）
- [x] test_ipc_client.ahk 语法检查通过（exit code 0，stderr 为空）
- [x] test_hotkey_hook.ahk 语法检查通过（exit code 0，stderr 为空）
- [x] test_sender.ahk 语法检查通过（exit code 0，stderr 为空）
- [x] test_joystick.ahk 语法检查通过（exit code 0，stderr 为空）
- [x] test_executor.ahk 在 run_all_tests.ahk 中运行无 ✗ 标记
- [x] test_ipc_client.ahk 在 run_all_tests.ahk 中运行无 ✗ 标记
- [x] test_hotkey_hook.ahk 在 run_all_tests.ahk 中运行无 ✗ 标记
- [x] test_sender.ahk 在 run_all_tests.ahk 中运行无 ✗ 标记
- [x] test_joystick.ahk 在 run_all_tests.ahk 中运行无 ✗ 标记
- [x] `tests/run_all_tests.ahk` 完整运行（新增 57 个套件全部通过，0 失败；预先存在的 `Test_ModeNames_Count` 失败与本次新增无关）
- [x] executor.ahk 直接运行行为不变（exit code 1 因 auth token 缺失，stderr 无输出，main guard 工作正常）

## 非功能约束

- [x] 5 个测试文件未使用箭头函数块体 `=> { }`（已检查）
- [x] 5 个测试文件未在字符串拼接中错误使用花括号（已检查）
- [x] 5 个测试文件使用 AutoHotUnitSuite 基类与 AutoHotUnitAsserter 断言器
- [x] 5 个测试文件测试方法以 `Test_` 前缀命名

## 备注

- 预先存在的失败：`Test_ModeNames_Count`（GUIManagerModeNamesTests 套件，期望 7 个模式但实际 10 个），属于旧测试与新功能不匹配，不在本任务范围内。
- 测试报告总计 468 个测试，通过 467 个，失败 1 个（预先存在）。新增 57 个套件全部通过。
