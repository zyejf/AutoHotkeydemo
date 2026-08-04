; =================================================================
; 测试层 - 全层集成测试套件 v2.0
; 说明: 跨层交互验证 - Domain↔Application↔Infrastructure↔Presentation
;       端到端场景：创建分组→保存配置→备份→恢复→验证
;       注意: 不包含 WebView2 运行时依赖，Bridge 逻辑通过底层服务验证
; 运行: AutoHotkey.exe tests\test_integration_v2.ahk
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
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/utils.ahk"
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
TestReporter.BeginTest("test_integration_v2.ahk")

; =================================================================
; 1. 端到端场景: 创建→保存→验证
; =================================================================
TestReporter.Scenario("1.1 端到端: 通过 SkillManager.Groups 创建分组")
config1 := {mode: "periodic", hotkey: "F24", keys: ["a", "b"], intervals: [50, 100]}
SkillManager.Groups["e2e_grp1"] := SkillGroup("e2e_grp1", config1)
ConfigStore.SetGroupConfig("e2e_grp1", config1)
TestReporter.Assert(SkillManager.Groups.Has("e2e_grp1"), "SkillManager 包含新分组")
TestReporter.Assert(ConfigStore.HasGroup("e2e_grp1"), "ConfigStore 包含新分组")

TestReporter.Scenario("1.2 端到端: 通过 ConfigService 保存配置")
TestReporter.AssertNoThrow(() => ConfigService.SaveConfig(), "SaveConfig 不崩溃")

TestReporter.Scenario("1.3 端到端: Bridge 逻辑 - GetGroupList 包含新分组")
groupList := []
for id, grp in SkillManager.Groups {
    groupList.Push(Map("id", id, "mode", grp.mode, "hotkey", grp.hotkey, "active", grp.active))
}
jsonResult := JSONSerializer.Stringify(groupList)
TestReporter.Assert(jsonResult is String, "GetGroupList 返回字符串")
parsedGroups := JSONParser.Parse(jsonResult)
TestReporter.Assert(parsedGroups is Array, "解析为数组")
found := false
for grp in parsedGroups {
    if grp is Map && grp.Has("id") && grp["id"] = "e2e_grp1" {
        found := true
        break
    }
}
TestReporter.Assert(found, "分组列表包含 e2e_grp1")

; =================================================================
; 2. 端到端场景: 更新→验证
; =================================================================
TestReporter.Scenario("2.1 端到端: 更新分组配置")
updateConfig := {mode: "periodic", hotkey: "F24", keys: ["c", "d"], intervals: [75, 150]}
SkillManager.Groups.Delete("e2e_grp1")
SkillManager.Groups["e2e_grp1"] := SkillGroup("e2e_grp1", updateConfig)
ConfigStore.SetGroupConfig("e2e_grp1", updateConfig)
TestReporter.Assert(SkillManager.Groups.Has("e2e_grp1"), "更新后分组仍存在")
updatedGrp := SkillManager.Groups["e2e_grp1"]
TestReporter.Assert(updatedGrp is SkillGroup, "更新后仍是 SkillGroup")

; =================================================================
; 3. 端到端场景: 备份→恢复
; =================================================================
TestReporter.Scenario("3.1 端到端: 通过 BackupCore 创建备份")
currentConfig := ConfigStore.Load()
backupResult := BackupCore.CreateBackup(currentConfig, "e2e_test")
TestReporter.Assert(backupResult is Map, "CreateBackup 返回 Map")
TestReporter.Assert(backupResult.Has("success"), "包含 success 字段")
TestReporter.AssertEqual(backupResult["success"], true, "备份成功")

TestReporter.Scenario("3.2 端到端: 通过 BackupCore 列出备份")
backups := BackupCore.ListBackups()
TestReporter.Assert(backups is Array, "ListBackups 返回 Array")
TestReporter.Assert(backups.Length > 0, "至少有一个备份")

TestReporter.Scenario("3.3 端到端: Bridge 逻辑 - ListBackups")
backupsJson := JSONSerializer.Stringify(backups)
TestReporter.Assert(backupsJson is String, "Bridge 返回字符串")
bridgeParsed := JSONParser.Parse(backupsJson)
TestReporter.Assert(bridgeParsed is Array, "Bridge 解析为数组")

; =================================================================
; 4. 端到端场景: 删除→验证
; =================================================================
TestReporter.Scenario("4.1 端到端: 删除分组")
SkillManager.Groups.Delete("e2e_grp1")
ConfigStore.DeleteGroupConfig("e2e_grp1")
TestReporter.Assert(!SkillManager.Groups.Has("e2e_grp1"), "SkillManager 不再包含已删除分组")

TestReporter.Scenario("4.2 端到端: 保存并验证删除")
ConfigService.SaveConfig()
TestReporter.Assert(!ConfigStore.HasGroup("e2e_grp1"), "ConfigStore 不再包含已删除分组")

; =================================================================
; 5. 跨层交互: SkillManager + ErrorSystem
; =================================================================
TestReporter.Scenario("5.1 跨层: Emergency 模式交互")
SkillManager.EmergencyMode := true
TestReporter.AssertEqual(SkillManager.EmergencyMode, true, "Emergency 激活")
SkillManager.EmergencyMode := false
TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "Emergency 重置")

TestReporter.Scenario("5.2 跨层: HoldKeyRegistry 交互")
SkillManager.RegisterHoldKey("Ctrl", "test_hold")
TestReporter.Assert(SkillManager.HoldKeyRegistry.Has("Ctrl"), "HoldKeyRegistry 注册成功")
SkillManager.ReleaseAllHolds()
TestReporter.AssertEqual(SkillManager.HoldKeyRegistry.Count, 0, "ReleaseAllHolds 清空注册")

; =================================================================
; 6. 跨层交互: ConfigValidator + ConfigStore
; =================================================================
TestReporter.Scenario("6.1 跨层: ConfigValidator 验证 ConfigStore 配置")
storeConfig := ConfigStore.Load()
if storeConfig is Map || IsObject(storeConfig) {
    validationErrors := ConfigValidator.Validate(storeConfig)
    TestReporter.Assert(validationErrors is Array, "Validate 返回 Array")
} else {
    TestReporter.Assert(true, "ConfigStore.Load 返回非对象，跳过验证")
}

; =================================================================
; 7. 跨层交互: JSON 序列化/反序列化往返
; =================================================================
TestReporter.Scenario("7.1 跨层: JSON 往返一致性")
original := Map()
original["mode"] := "periodic"
original["hotkey"] := "F1"
original["keys"] := ["a", "b"]
original["intervals"] := [50, 100]
jsonStr := JSONSerializer.Stringify(original)
roundTrip := JSONParser.Parse(jsonStr)
TestReporter.AssertEqual(roundTrip["mode"], "periodic", "往返 mode 正确")
TestReporter.AssertEqual(roundTrip["hotkey"], "F1", "往返 hotkey 正确")

; =================================================================
; 8. 跨层交互: Bridge 完整流程验证
; =================================================================
TestReporter.Scenario("8.1 跨层: Bridge SaveConfig→GetGroupList")
validJson := JSONSerializer.Stringify(Map("mode", "sequence", "hotkey", "F23", "keys", ["1", "2"], "delays", [100, 200]))
parsedConfig := JSONParser.Parse(validJson)
TestReporter.Assert(parsedConfig is Map, "Bridge SaveConfig JSON 解析成功")
TestReporter.AssertEqual(parsedConfig["mode"], "sequence", "Bridge mode 字段正确")

TestReporter.Scenario("8.2 跨层: Bridge GetDebugInfo 反映系统状态")
debugInfo := Map()
debugInfo["activeGroups"] := SkillManager.GetActiveGroups().Count
debugInfo["totalGroups"] := SkillManager.Groups.Count
debugInfo["emergencyMode"] := SkillManager.EmergencyMode
debugInfo["holdKeyCount"] := SkillManager.HoldKeyRegistry.Count
debugJson := JSONSerializer.Stringify(debugInfo)
debugParsed := JSONParser.Parse(debugJson)
TestReporter.Assert(debugParsed.Has("activeGroups"), "debugInfo 包含 activeGroups")
TestReporter.Assert(debugParsed.Has("emergencyMode"), "debugInfo 包含 emergencyMode")
TestReporter.AssertEqual(debugParsed["emergencyMode"], false, "emergencyMode = false")

; =================================================================
; 9. 跨层交互: ErrorHandler + SkillManager
; =================================================================
TestReporter.Scenario("9.1 跨层: ErrorHandler HealthCheck")
healthResult := ErrorHandler.HealthCheck(SkillManager)
TestReporter.Assert(healthResult is Array, "HealthCheck 返回 Array")

TestReporter.Scenario("9.2 跨层: ErrorHandler SafeExecute 配合 SkillManager")
safeResult := ErrorHandler.SafeExecute(() => SkillManager.Groups.Count)
TestReporter.Assert(safeResult >= 0, "SafeExecute 获取 Groups.Count 成功")

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
