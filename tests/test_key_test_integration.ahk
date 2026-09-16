; =================================================================
; 集成测试 - 按键测试页面 KeyRecorder + KeyValidator + SkillGroup
; 说明: 验证录制→导出→验证的完整数据流
; 运行: AutoHotkey.exe tests\test_key_test_integration.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../domain/key_recorder.ahk"
#Include "../domain/key_validator.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

ErrorSystem.Init()
ModeRegistry._Init()
ConfigStore.InitDefaults()
JSONLogger.Init()
DebugLogger.Init()

SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
SkillManager.Logger := JSONLogger
SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillManager.ConfigStore := ConfigStore

TestReporter.BeginTest("test_key_test_integration.ahk")

TestReporter.Scenario("3.1 录制→导出周期性配置 完整流程")
recEvents := []
KeyRecorder.Start((evt) => recEvents.Push(evt))
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("A", "up", 15)
KeyRecorder.OnKey("B", "down", 50)
KeyRecorder.OnKey("B", "up", 65)
KeyRecorder.OnKey("A", "down", 100)
KeyRecorder.OnKey("A", "up", 115)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config.Has("keys"), "导出应包含 keys")
TestReporter.Assert(config["keys"].Length = 3, "应有3个按键（A,B,A）")
TestReporter.Assert(config.Has("intervals"), "导出应包含 intervals")
TestReporter.Assert(config["keyPressDuration"] = 15, "keyPressDuration 应为15")

TestReporter.Scenario("3.2 录制→导出序列配置 完整流程")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("F1", "down", 0)
KeyRecorder.OnKey("F2", "down", 120)
KeyRecorder.OnKey("F3", "down", 280)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("sequence", 20)
TestReporter.Assert(config.Has("delays"), "序列模式应包含 delays")
TestReporter.Assert(config["keys"].Length = 3, "应有3个按键")
TestReporter.Assert(config["keyPressDuration"] = 20, "keyPressDuration 应为20")

TestReporter.Scenario("3.3 KeyValidator 与 SkillGroup 埋点集成")
valEvents := []
KeyValidator.Start("test-group-1", (evt) => valEvents.Push(evt))
KeyValidator.OnSend("test-group-1", "A", "press", 0)
KeyValidator.OnSend("test-group-1", "B", "press", 55)
KeyValidator.OnSend("test-group-1", "C", "press", 110)
report := KeyValidator.Stop()
TestReporter.Assert(report["groupId"] = "test-group-1", "报告 groupId 应匹配")
TestReporter.Assert(report["totalActual"] = 3, "应记录3个实际事件")
TestReporter.Assert(report.Has("details"), "报告应包含 details")
TestReporter.Assert(valEvents.Length = 3, "回调应收到3个事件")

TestReporter.Scenario("3.4 KeyValidator 过滤非目标分组")
KeyValidator.Start("target-group", (evt) => "")
KeyValidator.OnSend("target-group", "A", "press", 0)
KeyValidator.OnSend("other-group", "B", "press", 10)
KeyValidator.OnSend("target-group", "C", "press", 20)
report := KeyValidator.Stop()
TestReporter.Assert(report["totalActual"] = 2, "只应记录目标分组事件")

TestReporter.Scenario("3.5 录制鼠标+键盘混合事件")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnMouse("LButton", "click", 30)
KeyRecorder.OnKey("B", "down", 60)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config["keys"].Length = 3, "混合事件应全部导出")

TestReporter.Scenario("3.6 验证报告偏差计算")
; 同 test_key_validator 2.8：details 需要「期望序列 + 同一键两次 down」两个前提
SkillManager.Groups["dev-test"] := {mode: "periodic", keys: ["A", "B"], intervals: [50, 50]}
KeyValidator.Start("dev-test", (evt) => "")
KeyValidator.OnSend("dev-test", "A", "down", 0)
KeyValidator.OnSend("dev-test", "B", "down", 60)
KeyValidator.OnSend("dev-test", "A", "down", 115)
report := KeyValidator.Stop()
TestReporter.Assert(report.Has("avgIntervalDeviation"), "报告应包含平均偏差")
TestReporter.Assert(report.Has("maxIntervalDeviation"), "报告应包含最大偏差")
TestReporter.Assert(report["details"].Length > 0, "应有偏差详情")

TestReporter.Scenario("3.7 录制器回调实时推送")
pushedEvents := []
KeyRecorder.Start((evt) => pushedEvents.Push(evt))
KeyRecorder.OnKey("X", "down", 0)
KeyRecorder.OnKey("Y", "down", 10)
TestReporter.Assert(pushedEvents.Length = 2, "回调应实时收到2个事件")
KeyRecorder.Stop()

TestReporter.Scenario("3.8 验证器回调实时推送")
pushedValEvents := []
KeyValidator.Start("cb-test", (evt) => pushedValEvents.Push(evt))
KeyValidator.OnSend("cb-test", "A", "press", 0)
KeyValidator.OnSend("cb-test", "B", "press", 10)
TestReporter.Assert(pushedValEvents.Length = 2, "回调应实时收到2个事件")
KeyValidator.Stop()

TestReporter.Scenario("3.9 空录制导出安全")
KeyRecorder.Start((evt) => "")
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config.Count = 0, "空录制应返回空Map")

TestReporter.Scenario("3.10 录制→导出→验证 端到端流程")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("B", "down", 50)
KeyRecorder.OnKey("C", "down", 100)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("sequence", 15)
TestReporter.Assert(config["keys"].Length = 3, "端到端：应有3个按键")
TestReporter.Assert(config.Has("delays"), "端到端：应有 delays")

KeyValidator.Start("e2e-group", (evt) => "")
KeyValidator.OnSend("e2e-group", "A", "press", 0)
KeyValidator.OnSend("e2e-group", "B", "press", 48)
KeyValidator.OnSend("e2e-group", "C", "press", 103)
report := KeyValidator.Stop()
TestReporter.Assert(report["totalActual"] = 3, "端到端：应记录3个事件")
TestReporter.Assert(report.Has("orderCorrect"), "端到端：报告应包含顺序正确性")

TestReporter.Finish()
