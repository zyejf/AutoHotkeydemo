; =================================================================
; 最小化调试 v12 - 验证 ModeRegistry._Init
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"
#Include "../presentation/ui_manager.ahk"

JSONLogger.Init()
DebugLogger.Init()
ConfigStore.InitDefaults()
ConfigService.ConfigStore := ConfigStore
ConfigService.SkillManager := SkillManager
ConfigService.Notifier := UIManager
GroupService.ConfigStore := ConfigStore
GroupService.SkillManager := SkillManager
SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := UIManager
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
SkillManager.Logger := JSONLogger
SkillManager.Notifier := UIManager
SkillManager.ConfigStore := ConfigStore
ErrorSystem.Init()

initResult := ModeRegistry._Init()
FileAppend("ModeRegistry._Init result: " initResult "`n", A_ScriptDir "\debug_trace.log", "UTF-8")

hasPeriodic := ModeRegistry.HasMode("periodic")
FileAppend("HasMode periodic: " hasPeriodic "`n", A_ScriptDir "\debug_trace.log", "UTF-8")

ConfigService.LoadConfig()

TestReporter.BeginTest("deep_v12")

TestReporter.Scenario("ModeRegistry初始化")
TestReporter.Assert(initResult = true, "ModeRegistry._Init 返回 true")

TestReporter.Scenario("Periodic模式已注册")
TestReporter.Assert(hasPeriodic = true, "periodic 模式已注册")

TestReporter.Scenario("GetExecutor返回类型验证")
try {
    exec := ModeRegistry.GetExecutor("periodic")
    isInstance := exec is IExecutor
    TestReporter.Assert(isInstance, "GetExecutor 返回 IExecutor 实例")
} catch as e {
    TestReporter.Assert(false, "GetExecutor 异常: " e.Message)
}

TestReporter.Scenario("JSONParser空字符串")
emptyJsonCaught := false
try {
    JSONParser.Parse("")
} catch {
    emptyJsonCaught := true
}
TestReporter.Assert(emptyJsonCaught, "空字符串解析抛出异常被捕获")

TestReporter.Scenario("Emergency")
emConfig := Map("mode", "periodic", "hotkey", "F1", "keys", ["a"], "intervals", [50])
SkillManager.AddGroup("em_test", emConfig)
SkillManager.ToggleGroup("em_test")
SkillManager.Emergency()
TestReporter.AssertEqual(SkillManager.EmergencyMode, true, "紧急模式已激活")
SkillManager.ResetEmergency()
TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "紧急模式已重置")
SkillManager.DeleteGroup("em_test")

summary := TestReporter.Summarize()
TestReporter.ExportReport()

ExitApp(summary.failed > 0 ? 1 : 0)
