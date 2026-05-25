; =================================================================
; 测试层 - KeyValidator 单元测试
; 说明: 覆盖 KeyValidator 全部公开方法
; 运行: AutoHotkey.exe tests\test_key_validator.ahk
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
#Include "../domain/key_validator.ahk"

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

TestReporter.BeginTest("test_key_validator.ahk")

TestReporter.Scenario("2.1 KeyValidator 初始状态")
TestReporter.Assert(!KeyValidator.IsActive(), "初始不应激活")

TestReporter.Scenario("2.2 KeyValidator.Start 激活验证")
captured := []
KeyValidator.Start("1", (evt) => captured.Push(evt))
TestReporter.Assert(KeyValidator.IsActive(), "启动后应激活")
TestReporter.Assert(KeyValidator._groupId = "1", "groupId 应为 1")

TestReporter.Scenario("2.3 KeyValidator.OnSend 记录事件")
KeyValidator.OnSend("1", "A", "press", 0)
KeyValidator.OnSend("1", "B", "press", 50)
TestReporter.Assert(KeyValidator.GetActualCount() = 2, "应记录2个事件")

TestReporter.Scenario("2.4 KeyValidator.Stop 生成报告")
report := KeyValidator.Stop()
TestReporter.Assert(!KeyValidator.IsActive(), "停止后不应激活")
TestReporter.Assert(report.Has("groupId"), "报告应包含 groupId")
TestReporter.Assert(report.Has("totalActual"), "报告应包含 totalActual")
TestReporter.Assert(report["totalActual"] = 2, "totalActual 应为2")

TestReporter.Scenario("2.5 KeyValidator 过滤非目标分组事件")
KeyValidator.Start("2", (evt) => "")
KeyValidator.OnSend("1", "A", "press", 0)
KeyValidator.OnSend("2", "B", "press", 10)
TestReporter.Assert(KeyValidator.GetActualCount() = 1, "只应记录目标分组事件")
KeyValidator.Stop()

TestReporter.Scenario("2.6 KeyValidator 重复 Stop 安全")
KeyValidator.Start("1", (evt) => "")
KeyValidator.OnSend("1", "A", "press", 0)
r1 := KeyValidator.Stop()
r2 := KeyValidator.Stop()
TestReporter.Assert(r2 = "", "重复 Stop 应返回空")

TestReporter.Scenario("2.7 KeyValidator 未激活时 OnSend 忽略")
KeyValidator.OnSend("1", "A", "press", 0)
TestReporter.Assert(KeyValidator.GetActualCount() = 0, "未激活时不应记录")

TestReporter.Scenario("2.8 报告包含偏差详情")
KeyValidator.Start("1", (evt) => "")
KeyValidator.OnSend("1", "A", "press", 0)
KeyValidator.OnSend("1", "B", "press", 55)
KeyValidator.OnSend("1", "C", "press", 110)
report := KeyValidator.Stop()
TestReporter.Assert(report.Has("details"), "报告应包含 details")
TestReporter.Assert(report["details"].Length > 0, "details 不应为空")
TestReporter.Assert(report.Has("avgIntervalDeviation"), "报告应包含 avgIntervalDeviation")
TestReporter.Assert(report.Has("maxIntervalDeviation"), "报告应包含 maxIntervalDeviation")

TestReporter.EndTest()
ExitApp()
