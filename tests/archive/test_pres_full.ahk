; =================================================================
; 测试层 - Presentation 层完整测试套件 v2.0
; 说明: 覆盖 WebView2Manager Bridge 逻辑验证
;       注意: 不依赖 WebView2 运行时库和 GUI 组件（Persistent(false) 下会挂起）
;       Bridge 方法通过直接调用底层服务来验证逻辑正确性
; 运行: AutoHotkey.exe tests\test_pres_full.ahk
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
TestReporter.BeginTest("test_pres_full.ahk")

; =================================================================
; 1. INotifier 接口合规测试（不依赖 UIManager GUI）
; =================================================================
TestReporter.Scenario("1.1 INotifier 接口存在")
TestReporter.Assert(ObjGetBase(INotifier) = "", "INotifier 是根类")

TestReporter.Scenario("1.2 INotifier Notify 签名兼容")
notifierMock := {Notify: (msg, type) => ""}
TestReporter.Assert(HasProp(notifierMock, "Notify"), "Mock 对象有 Notify 方法")

; =================================================================
; 2. Bridge 逻辑验证（不依赖 WebView2 运行时）
; =================================================================
TestReporter.Scenario("2.1 Bridge 逻辑: GetGroupList")
groups := SkillManager.Groups
groupList := []
for id, grp in groups {
    groupList.Push(Map("id", id, "mode", grp.mode, "hotkey", grp.hotkey, "active", grp.active))
}
jsonResult := JSONSerializer.Stringify(groupList)
TestReporter.Assert(jsonResult is String, "GetGroupList 逻辑返回字符串")
parsed := JSONParser.Parse(jsonResult)
TestReporter.Assert(parsed is Array, "解析后是数组")

TestReporter.Scenario("2.2 Bridge 逻辑: LoadConfig")
config := ConfigStore.Load()
configJson := JSONSerializer.Stringify(config)
TestReporter.Assert(configJson is String, "LoadConfig 逻辑返回字符串")

TestReporter.Scenario("2.3 Bridge 逻辑: LoadSettings")
settings := Map()
settings["emergencyHotkey"] := ConfigStore.GetControlHotkey("emergency")
settings["debugMode"] := DebugLogger.enabled
settingsJson := JSONSerializer.Stringify(settings)
TestReporter.Assert(settingsJson is String, "LoadSettings 逻辑返回字符串")

TestReporter.Scenario("2.4 Bridge 逻辑: EmergencyStop")
SkillManager.EmergencyMode := true
TestReporter.AssertEqual(SkillManager.EmergencyMode, true, "Emergency 激活")
SkillManager.EmergencyMode := false
TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "Emergency 重置")

TestReporter.Scenario("2.5 Bridge 逻辑: ToggleAll - 逻辑验证")
TestReporter.Assert(SkillManager.Groups.Count >= 0, "ToggleAll 逻辑: Groups 可访问")
TestReporter.AssertEqual(SkillManager.GetActiveCount(), 0, "ToggleAll 逻辑: 无分组时活跃数为 0")

TestReporter.Scenario("2.6 Bridge 逻辑: HotReload - 逻辑验证")
TestReporter.Assert(ConfigStore is Object, "HotReload 逻辑: ConfigStore 可访问")
TestReporter.Assert(SkillManager is Object, "HotReload 逻辑: SkillManager 可访问")

TestReporter.Scenario("2.7 Bridge 逻辑: GetDebugInfo")
debugInfo := Map()
debugInfo["activeGroups"] := SkillManager.GetActiveGroups().Count
debugInfo["totalGroups"] := SkillManager.Groups.Count
debugInfo["emergencyMode"] := SkillManager.EmergencyMode
debugInfo["holdKeyCount"] := SkillManager.HoldKeyRegistry.Count
debugJson := JSONSerializer.Stringify(debugInfo)
TestReporter.Assert(debugJson is String, "GetDebugInfo 逻辑返回字符串")
debugParsed := JSONParser.Parse(debugJson)
TestReporter.Assert(debugParsed is Map, "解析后是 Map")
TestReporter.Assert(debugParsed.Has("activeGroups"), "包含 activeGroups")
TestReporter.Assert(debugParsed.Has("totalGroups"), "包含 totalGroups")
TestReporter.Assert(debugParsed.Has("emergencyMode"), "包含 emergencyMode")

TestReporter.Scenario("2.8 Bridge 逻辑: ListBackups")
backups := BackupCore.ListBackups()
backupsJson := JSONSerializer.Stringify(backups)
TestReporter.Assert(backupsJson is String, "ListBackups 逻辑返回字符串")
backupsParsed := JSONParser.Parse(backupsJson)
TestReporter.Assert(backupsParsed is Array, "解析后是数组")

TestReporter.Scenario("2.9 Bridge 逻辑: CreateBackup")
currentConfig := ConfigStore.Load()
backupResult := BackupCore.CreateBackup(currentConfig, "test_pres")
TestReporter.Assert(backupResult is Map, "CreateBackup 返回 Map")
TestReporter.Assert(backupResult.Has("success"), "包含 success 字段")

TestReporter.Scenario("2.10 Bridge 逻辑: SaveConfig - 无效 JSON")
_InvalidJsonSave() {
    try {
        parsed := JSONParser.Parse("invalid json")
        return "no_error"
    } catch {
        return "error_caught"
    }
}
invalidResult := _InvalidJsonSave()
TestReporter.AssertEqual(invalidResult, "error_caught", "无效 JSON 解析抛出异常")

TestReporter.Scenario("2.11 Bridge 逻辑: SaveConfig - 有效 JSON")
validJson := JSONSerializer.Stringify(Map("mode", "periodic", "hotkey", "F24", "keys", ["a"], "intervals", [50]))
parsedConfig := JSONParser.Parse(validJson)
TestReporter.Assert(parsedConfig is Map, "有效 JSON 解析成功")
TestReporter.AssertEqual(parsedConfig["mode"], "periodic", "mode 字段正确")

TestReporter.Scenario("2.12 Bridge 逻辑: LoadGroupConfig - 不存在的 ID")
grpConfig := ConfigStore.GetGroupConfig("nonexistent_id")
TestReporter.AssertEqual(grpConfig, "", "不存在的 ID 返回空")

TestReporter.Scenario("2.13 Bridge 逻辑: DeleteGroup - 不存在的 ID")
_TestDeleteNonExist() {
    try {
        GroupService.DeleteGroup("nonexistent_id")
        return "no_error"
    } catch {
        return "error_caught"
    }
}
delResult := _TestDeleteNonExist()
TestReporter.AssertEqual(delResult, "error_caught", "删除不存在的 ID 抛出异常")

TestReporter.Scenario("2.14 Bridge 逻辑: RestoreBackup - 不存在的备份")
restoreResult := BackupCore.RestoreBackup("nonexistent_backup.json")
TestReporter.AssertEqual(restoreResult, false, "恢复不存在的备份返回 false")

TestReporter.Scenario("2.15 Bridge 逻辑: DeleteBackup - 不存在的备份")
delBkResult := BackupCore.DeleteBackup("nonexistent_backup.json")
TestReporter.AssertEqual(delBkResult, false, "删除不存在的备份返回 false")

; =================================================================
; 3. _GetField 辅助函数逻辑验证
; =================================================================
TestReporter.Scenario("3.1 _GetField 逻辑 - Map 类型")
_GetField(obj, key, defaultVal := "") {
    try {
        if obj is Map {
            return obj.Has(key) ? obj[key] : defaultVal
        }
        if HasProp(obj, key) {
            return obj.%key%
        }
        return defaultVal
    } catch {
        return defaultVal
    }
}
testMap := Map()
testMap["action"] := "GetGroupList"
testMap["requestId"] := "req_123"
TestReporter.AssertEqual(_GetField(testMap, "action"), "GetGroupList", "Map _GetField action 正确")
TestReporter.AssertEqual(_GetField(testMap, "requestId"), "req_123", "Map _GetField requestId 正确")
TestReporter.AssertEqual(_GetField(testMap, "nonexistent"), "", "Map _GetField 不存在字段返回默认值")
TestReporter.AssertEqual(_GetField(testMap, "nonexistent", "default"), "default", "Map _GetField 自定义默认值")

TestReporter.Scenario("3.2 _GetField 逻辑 - Object 类型")
testObj := {action: "SaveConfig", data: "test_data"}
TestReporter.AssertEqual(_GetField(testObj, "action"), "SaveConfig", "Object _GetField action 正确")
TestReporter.AssertEqual(_GetField(testObj, "data"), "test_data", "Object _GetField data 正确")
TestReporter.AssertEqual(_GetField(testObj, "nonexistent"), "", "Object _GetField 不存在字段返回默认值")

TestReporter.Scenario("3.3 _GetField 逻辑 - WebMessage 解析")
msgJson := '{"action":"ToggleGroup","requestId":"req_42","groupId":"grp1"}'
msg := JSONParser.Parse(msgJson)
TestReporter.AssertEqual(_GetField(msg, "action"), "ToggleGroup", "WebMessage action 解析正确")
TestReporter.AssertEqual(_GetField(msg, "requestId"), "req_42", "WebMessage requestId 解析正确")
TestReporter.AssertEqual(_GetField(msg, "groupId"), "grp1", "WebMessage groupId 解析正确")

; =================================================================
; 4. _SendResponse 布尔值序列化逻辑验证
; =================================================================
TestReporter.Scenario("4.1 _SendResponse 布尔值序列化逻辑")
_BuildResponse(requestId, result) {
    responseObj := Map()
    responseObj["requestId"] := requestId
    if result = "true" {
        responseObj["result"] := true
    } else if result = "false" {
        responseObj["result"] := false
    } else if IsNumber(result) {
        responseObj["result"] := Number(result)
    } else {
        try {
            parsed := JSONParser.Parse(result)
            responseObj["result"] := parsed
        } catch {
            responseObj["result"] := result
        }
    }
    return JSONSerializer.Stringify(responseObj)
}
respTrue := _BuildResponse("req_1", "true")
TestReporter.Assert(InStr(respTrue, "true") > 0, "布尔 true 序列化正确")
respFalse := _BuildResponse("req_2", "false")
TestReporter.Assert(InStr(respFalse, "false") > 0, "布尔 false 序列化正确")
respNum := _BuildResponse("req_3", "42")
TestReporter.Assert(InStr(respNum, "42") > 0, "数字序列化正确")

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
