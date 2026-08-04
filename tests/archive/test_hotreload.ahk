; =================================================================
; 测试层 - ConfigService.HotReload 热重载完整测试
; 版本: 1.0
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "test_result_reporter.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

LoadTestDependencies() {
    ConfigStore.InitDefaults()
    JSONLogger.Init()
    DebugLogger.Init()
    SkillGroup.Logger := DebugLogger
    SkillGroup.Notifier := ""
    SkillGroup.ConfigStore := ConfigStore
    SkillGroup.IsKeyAllowed := ((key, groupId) => true)
    SkillGroup.RegisterHoldKey := ((key, groupId) => true)
    SkillGroup.UnregisterHoldKey := ((key, groupId) => "")
    SkillManager.Logger := JSONLogger
    SkillManager.ConfigStore := ConfigStore
    GroupService.ConfigStore := ConfigStore
    GroupService.SkillManager := SkillManager
    ConfigService.ConfigStore := ConfigStore
    ConfigService.SkillManager := SkillManager
}
LoadTestDependencies()

ConfigService.Notifier := ((msg, type, duration) => "")

TestReporter.BeginTest("test_hotreload.ahk")

originalPath := ConfigService.configPath
testFile := A_WorkingDir . "\tests\_test_hotreload.json"

; =================================================================
; 场景A: 正常热重载流程
; =================================================================
TestReporter.Scenario("场景A: 正常热重载")

ConfigService.configPath := testFile

groupConfigA := Map(
    "hotkey", "F1",
    "mode", "periodic",
    "keys", ["a"],
    "intervals", [50]
)
GroupService.CreateGroup("hr_test_a", groupConfigA)
validatedA := ConfigStore.Load()
ExportConfigToFileReal(testFile, validatedA)

resultA := ConfigService.HotReload()
TestReporter.AssertTrue(resultA, "HotReload 正常返回 true")
TestReporter.AssertTrue(ConfigStore.HasGroup("hr_test_a"), "热重载后分组 hr_test_a 存在")

; =================================================================
; 场景B: 配置损坏回滚
; =================================================================
TestReporter.Scenario("场景B: 配置损坏回滚")

FileDelete(testFile)
FileAppend("{ invalid json content !@#$`n", testFile, "UTF-8")

resultB := ConfigService.HotReload()
TestReporter.AssertEqual(resultB, false, "损坏配置热重载返回 false")

; =================================================================
; 场景C: 空分组配置热重载
; =================================================================
TestReporter.Scenario("场景C: 空分组配置热重载")

emptyCfg := Map("version", "3.0", "lastModified", A_Now,
    "GroupSettings", Map(), "CONTROL_HOTKEYS", Map(), "HoldSettings", Map())
emptyJson := JSONSerializer.Serialize(emptyCfg)
FileDelete(testFile)
FileAppend(emptyJson, testFile, "UTF-8")

resultC := ConfigService.HotReload()
TestReporter.AssertTrue(resultC, "空分组热重载返回 true")
TestReporter.AssertEqual(ConfigStore.HasGroup("hr_test_a"), false,
    "旧分组 hr_test_a 已被清除")

; =================================================================
; 场景D: 配置文件不存在
; =================================================================
TestReporter.Scenario("场景D: 配置文件不存在")

ConfigService.configPath := A_WorkingDir . "\tests\_test_nonexist.json"
if FileExist(ConfigService.configPath)
    FileDelete(ConfigService.configPath)

resultD := ConfigService.HotReload()
TestReporter.AssertEqual(resultD, false, "文件不存在时返回 false")

; =================================================================
; 场景E: 热重载分组状态恢复
; =================================================================
TestReporter.Scenario("场景E: 热重载分组状态恢复")

ConfigService.configPath := testFile

groupConfigE := Map(
    "hotkey", "F2",
    "mode", "periodic",
    "keys", ["b"],
    "intervals", [60]
)
GroupService.CreateGroup("hr_test_e", groupConfigE)
ConfigStore.SetGroup("hr_test_e", "active", true)

cfgE := ConfigStore.Load()
ExportConfigToFileReal(testFile, cfgE)

resultE := ConfigService.HotReload()
TestReporter.AssertTrue(resultE, "热重载成功返回 true")
TestReporter.AssertTrue(ConfigStore.HasGroup("hr_test_e"), "热重载后分组 hr_test_e 存在")

groupE := GroupService.GetGroup("hr_test_e")
TestReporter.AssertEqual(groupE.active, true, "热重载后分组 active 状态保持 true")

; =================================================================
; 清理
; =================================================================
ConfigService.configPath := originalPath
try FileDelete(testFile)
try FileDelete(A_WorkingDir . "\tests\_test_nonexist.json")

; =================================================================
; 汇总与报告
; =================================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed > 0 ? 1 : 0)

; =================================================================
; 辅助函数：直接写文件（绕过ConfigService.SaveConfig的验证）
; =================================================================
ExportConfigToFileReal(filePath, config) {
    json := JSONSerializer.Serialize(config)
    FileDelete(filePath)
    FileAppend(json, filePath, "UTF-8")
    return true
}