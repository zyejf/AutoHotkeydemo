# Tasks

## Phase A: 准备与可测试性重构（已完成）

- [x] Task 1: 创建测试目录与被测脚本可测试性改造
  - [x] SubTask 1.1: 创建 `tests/test_ahk_executor/` 目录
  - [x] SubTask 1.2: 修改 `asd-tauri/src-tauri/ahk_executor/executor.ahk`，将 `OnError`、`OnExit`、`Executor_Init()` 包装在 `if (A_LineFile = A_ScriptFullPath)` main guard 中

## Phase B: 编写 5 个测试文件（已完成）

- [x] Task 2: 编写 test_executor.ahk
  - [x] SubTask 2.1: 文件头部包含 #Requires/#ErrorStdOut/#Include（被测脚本 + AutoHotUnit.ahk）/#Warn 三联/OnError 回调
  - [x] SubTask 2.2: 编写 CommandDispatcher 辅助方法测试套件（GetStr/GetInt/GetBool/GetArr/GetMap/MergeModeConfig/Dispatch 未知命令/RecordKey/ValidateConfig）
  - [x] SubTask 2.3: 修复 #Include 顺序，确保 `#Include "../AutoHotUnit.ahk"` 在被测脚本之后、`#Warn` 在 #Include 之后

- [x] Task 3: 编写 test_ipc_client.ahk
  - [x] SubTask 3.1: 文件头部规范同 Task 2.1
  - [x] SubTask 3.2: 编写 MiniJson 解析测试套件（对象/数组/标量/字符串/转义/嵌套/roundtrip）
  - [x] SubTask 3.3: 编写 IpcClient 消息构造测试套件（初始状态/NextSeq/未连接发送/解析 auth token/重复消息去重）
  - [x] SubTask 3.4: 修复 #Include 顺序

- [x] Task 4: 编写 test_hotkey_hook.ahk
  - [x] SubTask 4.1: 文件头部规范同 Task 2.1
  - [x] SubTask 4.2: 编写 HotkeyHook 测试套件（规范化/注册状态/注册/注销错误路径/UnregisterAll/Init/回调触发）
  - [x] SubTask 4.3: 修复 #Include 顺序

- [x] Task 5: 编写 test_sender.ahk
  - [x] SubTask 5.1: 文件头部规范同 Task 2.1
  - [x] SubTask 5.2: 编写 Sender 测试套件（按键白名单/ValidateKey/ToggleGroup/StartPeriodic/StartSequence/StartEnhanced/StartHold/HoldMode 切换/EmergencyRelease/Shutdown/Init）
  - [x] SubTask 5.3: 修复 #Include 顺序
  - [x] SubTask 5.4: 使用非白名单按键 "F13" 避免 SendInput 副作用；在 afterAll 中调用 EmergencyRelease 清理静态状态

- [x] Task 6: 编写 test_joystick.ahk
  - [x] SubTask 6.1: 文件头部规范（#Include 顺序已调整）
  - [x] SubTask 6.2: 编写 Joystick 测试套件（按键识别/GetButtonNum/GetPovDirection/GetAxisInfo/AxisToVJoyId/PovDirectionToValue/ResolveMethod/IsVJoyAvailable/StopGroup/EmergencyRelease/Init/StartPeriodic/StartSequence/StartHold）
  - [x] SubTask 6.3: 修复 #Include 顺序（将 `#Include "../AutoHotUnit.ahk"` 移到被测脚本之后，将 `#Warn` 移到 #Include 之后）

## Phase C: 集成与验证（已完成）

- [x] Task 7: 更新 run_all_tests.ahk 注册新套件
  - [x] SubTask 7.1: 在 `#Include` 区段末尾追加 5 行 Include（test_ahk_executor/test_*.ahk）
  - [x] SubTask 7.2: 在 `RegisterSuite` 调用区段追加 57 个新套件类的注册
  - [x] SubTask 7.3: 验证 `tests/run_all_tests.ahk` 语法检查通过（exit code 0，stderr 为空）

- [x] Task 8: 运行验证（所有新增测试通过）
  - [x] SubTask 8.1: 对 5 个测试文件分别执行语法检查（全部 exit code 0，stderr 为空）
  - [x] SubTask 8.2: 运行 `tests/run_all_tests.ahk`，新增 57 个套件全部通过（0 失败）
  - [x] SubTask 8.3: 验证 executor.ahk 直接运行行为不变（exit code 1 因 auth token 缺失，stderr 无输出，main guard 工作正常）
  - [x] SubTask 8.4: 验证预先存在的 `Test_ModeNames_Count` 失败与本次新增无关（GUIManagerModeNamesTests 套件，期望 7 个模式但实际 10 个，属于旧测试与新功能不匹配，不在本任务范围内）

# Task Dependencies

- [Task 1] 无依赖，是后续所有任务的前置条件
- [Task 2-6] 互相独立，可并行执行（每个测试文件独立编写）
- [Task 7] 依赖 [Task 2-6] 全部完成（5 个测试文件存在且能通过语法检查）
- [Task 8] 依赖 [Task 7] 完成（run_all_tests.ahk 已注册新套件）
