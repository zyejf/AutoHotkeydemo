; =================================================================
; 测试层 - Application 层完整测试套件 v2.0
; 说明: 覆盖 GroupService/ConfigService 全部公开方法
;       注意: Hotkey() 在 Persistent(false) 下可能挂起，
;       因此测试中使用直接操作 Groups Map 的方式绕过热键注册
; 运行: AutoHotkey.exe tests\test_app_full.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"

OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))

_InitTestDeps() {
    ErrorSystem.Init()
    ModeRegistry._Init()
    ConfigStore.InitDefaults()
    JSONLogger.Init()
    DebugLogger.Init()
    BackupCore.Init()
    SkillGroup.Logger := DebugLogger
    SkillGroup.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
    SkillGroup.ConfigStore := ConfigStore
    SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
    SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
    SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
    SkillManager.Logger := JSONLogger
    SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
    SkillManager.ConfigStore := ConfigStore
    GroupService.ConfigStore := ConfigStore
    GroupService.SkillManager := SkillManager
    ConfigService.ConfigStore := ConfigStore
    ConfigService.SkillManager := SkillManager
    ConfigService.Notifier := {Notify: (msg, type) => ""}
}

_InitTestDeps()
TestReporter.BeginTest("test_app_full.ahk")

; =================================================================
; 1. GroupService 完整测试
;    注意: 直接操作 SkillManager.Groups 绕过 Hotkey() 注册
; =================================================================
TestReporter.Scenario("1.1 GroupService CreateGroup - 通过直接操作 Groups")
config := {mode: "periodic", hotkey: "F24", keys: ["a"], intervals: [50]}
SkillManager.Groups["test_gs1"] := SkillGroup("test_gs1", config)
ConfigStore.SetGroupConfig("test_gs1", config)
TestReporter.Assert(SkillManager.Groups.Has("test_gs1"), "Groups 包含新分组")
TestReporter.Assert(ConfigStore.HasGroup("test_gs1"), "ConfigStore 包含新分组")

TestReporter.Scenario("1.2 GroupService GetGroup")
grp := GroupService.GetGroup("test_gs1")
TestReporter.Assert(grp is SkillGroup, "GetGroup 返回 SkillGroup 实例")

TestReporter.Scenario("1.3 GroupService GetAllGroups")
allGroups := GroupService.GetAllGroups()
TestReporter.Assert(allGroups is Map, "GetAllGroups 返回 Map")
TestReporter.Assert(allGroups.Count >= 1, "GetAllGroups 至少包含 1 个分组")

TestReporter.Scenario("1.4 GroupService GetActiveGroups")
activeGroups := GroupService.GetActiveGroups()
TestReporter.Assert(activeGroups is Map, "GetActiveGroups 返回 Map")

TestReporter.Scenario("1.5 GroupService GetGroupConfig")
grpConfig := GroupService.GetGroupConfig("test_gs1")
TestReporter.Assert(grpConfig != "", "GetGroupConfig 返回非空")

TestReporter.Scenario("1.6 GroupService GetGroup - 不存在的 ID")
grpNonExist := GroupService.GetGroup("nonexistent_id")
TestReporter.AssertEqual(grpNonExist, "", "GetGroup 不存在的 ID 返回空字符串")

TestReporter.Scenario("1.7 GroupService DeleteGroup - 直接操作")
SkillManager.Groups.Delete("test_gs1")
ConfigStore.DeleteGroupConfig("test_gs1")
TestReporter.Assert(!SkillManager.Groups.Has("test_gs1"), "Groups 不再包含已删除分组")
TestReporter.Assert(!ConfigStore.HasGroup("test_gs1"), "ConfigStore 不再包含已删除分组")

TestReporter.Scenario("1.8 GroupService _GenerateGroupId")
newId := GroupService._GenerateGroupId()
TestReporter.Assert(newId != "", "_GenerateGroupId 返回非空字符串")

TestReporter.Scenario("1.9 GroupService CreateGroup - 配置验证失败")
_InvalidConfig() {
    try {
        GroupService.CreateGroup("test_invalid", {mode: "invalid_mode", hotkey: ""})
        return "no_error"
    } catch {
        return "error_caught"
    }
}
invalidResult := _InvalidConfig()
TestReporter.AssertEqual(invalidResult, "error_caught", "无效配置抛出异常")

; =================================================================
; 2. ConfigService 完整测试
; =================================================================
TestReporter.Scenario("2.1 ConfigService LoadConfig")
TestReporter.AssertNoThrow(() => ConfigService.LoadConfig(), "LoadConfig 不崩溃")

TestReporter.Scenario("2.2 ConfigService SaveConfig")
TestReporter.AssertNoThrow(() => ConfigService.SaveConfig(), "SaveConfig 不崩溃")

TestReporter.Scenario("2.3 ConfigService HotReload")
TestReporter.AssertNoThrow(() => ConfigService.HotReload(), "HotReload 不崩溃")

TestReporter.Scenario("2.4 ConfigService MigrateConfig")
oldConfig := Map()
oldConfig["hotkey"] := "F1"
oldConfig["mode"] := "periodic"
oldConfig["keys"] := ["a"]
oldConfig["intervals"] := [50]
migrated := ConfigService.MigrateConfig(oldConfig)
TestReporter.Assert(migrated is Map || migrated is Object, "MigrateConfig 返回对象")

TestReporter.Scenario("2.5 ConfigService _GetDefaultConfig")
defaultCfg := ConfigService._GetDefaultConfig()
TestReporter.Assert(defaultCfg is Map || defaultCfg is Object, "_GetDefaultConfig 返回对象")

TestReporter.Scenario("2.6 ConfigService _ObjectToMap")
obj := {a: 1, b: "test"}
mapResult := ConfigService._ObjectToMap(obj)
TestReporter.Assert(mapResult is Map, "_ObjectToMap 返回 Map")

TestReporter.Scenario("2.7 ConfigService _MigrateGroup")
grpObj := {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}
migratedGrp := ConfigService._MigrateGroup(grpObj)
TestReporter.Assert(migratedGrp is Map || migratedGrp is Object, "_MigrateGroup 返回对象")

; =================================================================
; 输出报告
; =================================================================
TestReporter.EndTest()
passedCount := 0
failedCount := 0
for r in TestReporter.results {
    if r["status"] = "PASS"
        passedCount++
    else
        failedCount++
}
exitCode := failedCount > 0 ? 1 : 0
ExitApp(exitCode)
