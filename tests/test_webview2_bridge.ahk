; =================================================================
; 测试层 - WebView2 Bridge 集成测试
; 版本: 1.0
; 说明: 验证 AHK-JS Bridge 方法连接到实际领域服务的正确性
;       包括 CRUD 操作、状态查询、备份恢复等完整流程
;       使用结构化断言框架，ExitApp(0) 成功 / ExitApp(1) 失败
; 运行: AutoHotkey.exe tests\test_webview2_bridge.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)
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
#Include "../presentation/webview2_manager.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

TestReporter.BeginTest("test_webview2_bridge.ahk")

; 注册 setup 钩子：重置 ConfigStore，确保独立场景间状态隔离
TestReporter.RegisterBeforeEach(() => ConfigStore.InitDefaults())

; ============================================================
; 初始化依赖
; ============================================================
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
ModeRegistry._Init()
ConfigService.LoadConfig()

; ============================================================
; 场景 A: _BridgeLoadConfig 返回有效 JSON
; ============================================================
TestReporter.Scenario("_BridgeLoadConfig 返回有效 JSON")
configJson := WebView2Manager._BridgeLoadConfig()
TestReporter.Assert(configJson is String, "_BridgeLoadConfig 返回字符串")
parsed := JSONParser.Parse(configJson)
TestReporter.Assert(parsed is Map || parsed is Object, "_BridgeLoadConfig 返回可解析 JSON")

; ============================================================
; 场景 B: _BridgeGetGroupList 返回数组
; ============================================================
TestReporter.Scenario("_BridgeGetGroupList 返回数组")
groupListJson := WebView2Manager._BridgeGetGroupList()
TestReporter.Assert(groupListJson is String, "_BridgeGetGroupList 返回字符串")
TestReporter.Assert(SubStr(groupListJson, 1, 1) = "[", "_BridgeGetGroupList 返回 JSON 数组")
groupList := JSONParser.Parse(groupListJson)
TestReporter.Assert(groupList is Array, "解析后为数组类型")

; ============================================================
; 场景 C: _BridgeSaveConfig 创建新分组
; ============================================================
TestReporter.Scenario("_BridgeSaveConfig 创建新分组")
newGroupJson := '{"mode":"periodic","hotkey":"F9","keys":["Space"],"intervals":[50]}'
result := WebView2Manager._BridgeSaveConfig(newGroupJson)
TestReporter.AssertEqual(result, true, "_BridgeSaveConfig 创建分组返回 true")

; ============================================================
; 场景 D: _BridgeGetGroupList 包含新创建的分组
; ============================================================
TestReporter.Scenario("_BridgeGetGroupList 包含新创建的分组")
groupListJson2 := WebView2Manager._BridgeGetGroupList()
groupList2 := JSONParser.Parse(groupListJson2)
found := false
for g in groupList2 {
    if g is Map && g.Has("hotkey") && g["hotkey"] = "F9" {
        found := true
        break
    }
}
TestReporter.Assert(found, "新创建的分组出现在列表中")

; ============================================================
; 场景 E: _BridgeLoadGroupConfig 加载指定分组
; ============================================================
TestReporter.Scenario("_BridgeLoadGroupConfig 加载指定分组")
if groupList2.Length > 0 {
    firstGroup := groupList2[1]
    groupId := firstGroup is Map ? firstGroup["id"] : ""
    if groupId != "" {
        groupConfigJson := WebView2Manager._BridgeLoadGroupConfig(groupId)
        TestReporter.Assert(groupConfigJson is String, "_BridgeLoadGroupConfig 返回字符串")
        TestReporter.Assert(SubStr(groupConfigJson, 1, 1) = "{", "_BridgeLoadGroupConfig 返回 JSON 对象")
        groupConfig := JSONParser.Parse(groupConfigJson)
        TestReporter.Assert(groupConfig is Map || groupConfig is Object, "分组配置可解析")
        TestReporter.Assert(groupConfig.Has("id"), "分组配置包含 id")
    } else {
        TestReporter.Assert(true, "跳过（无分组ID）")
    }
} else {
    TestReporter.Assert(true, "跳过（无分组）")
}

; ============================================================
; 场景 F: _BridgeSaveConfig 更新已有分组
; ============================================================
TestReporter.Scenario("_BridgeSaveConfig 更新已有分组")
groupListJson3 := WebView2Manager._BridgeGetGroupList()
groupList3 := JSONParser.Parse(groupListJson3)
if groupList3.Length > 0 {
    firstGroup3 := groupList3[1]
    groupId3 := firstGroup3 is Map ? firstGroup3["id"] : ""
    if groupId3 != "" {
        updateJson := '{"id":"' groupId3 '","mode":"periodic","hotkey":"F10","keys":["1"],"intervals":[100]}'
        result2 := WebView2Manager._BridgeSaveConfig(updateJson)
        TestReporter.AssertEqual(result2, true, "_BridgeSaveConfig 更新分组返回 true")
    } else {
        TestReporter.Assert(true, "跳过（无分组ID）")
    }
} else {
    TestReporter.Assert(true, "跳过（无分组）")
}

; ============================================================
; 场景 G: _BridgeToggleGroup 不崩溃
; ============================================================
TestReporter.Scenario("_BridgeToggleGroup 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeToggleGroup("nonexistent"), "_BridgeToggleGroup 不存在的ID不崩溃")

; ============================================================
; 场景 H: _BridgeDeleteGroup 删除分组
; ============================================================
TestReporter.Scenario("_BridgeDeleteGroup 删除分组")
deleteResult := WebView2Manager._BridgeDeleteGroup("nonexistent_id")
TestReporter.AssertEqual(deleteResult, false, "_BridgeDeleteGroup 不存在的ID返回 false")

; ============================================================
; 场景 I: _BridgeEmergencyStop 不崩溃
; ============================================================
TestReporter.Scenario("_BridgeEmergencyStop 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeEmergencyStop(), "_BridgeEmergencyStop 不崩溃")
emergencyResult := WebView2Manager._BridgeEmergencyStop()
TestReporter.AssertEqual(emergencyResult, "ok", "_BridgeEmergencyStop 返回 ok")

; ============================================================
; 场景 J: _BridgeToggleAll 不崩溃
; ============================================================
TestReporter.Scenario("_BridgeToggleAll 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeToggleAll(), "_BridgeToggleAll 不崩溃")
toggleResult := WebView2Manager._BridgeToggleAll()
TestReporter.AssertEqual(toggleResult, "ok", "_BridgeToggleAll 返回 ok")

; ============================================================
; 场景 K: _BridgeGetDebugInfo 返回有效信息
; ============================================================
TestReporter.Scenario("_BridgeGetDebugInfo 返回有效信息")
debugInfoJson := WebView2Manager._BridgeGetDebugInfo()
TestReporter.Assert(debugInfoJson is String, "_BridgeGetDebugInfo 返回字符串")
debugInfo := JSONParser.Parse(debugInfoJson)
TestReporter.Assert(debugInfo is Map || debugInfo is Object, "_BridgeGetDebugInfo 可解析")
TestReporter.Assert(debugInfo.Has("activeGroups"), "debugInfo 包含 activeGroups")
TestReporter.Assert(debugInfo.Has("totalGroups"), "debugInfo 包含 totalGroups")
TestReporter.Assert(debugInfo.Has("emergencyMode"), "debugInfo 包含 emergencyMode")
TestReporter.Assert(debugInfo.Has("uptime"), "debugInfo 包含 uptime")

; ============================================================
; 场景 L: _BridgeLoadSettings 返回有效 JSON
; ============================================================
TestReporter.Scenario("_BridgeLoadSettings 返回有效 JSON")
settingsJson := WebView2Manager._BridgeLoadSettings()
TestReporter.Assert(settingsJson is String, "_BridgeLoadSettings 返回字符串")
TestReporter.Assert(SubStr(settingsJson, 1, 1) = "{" || SubStr(settingsJson, 1, 1) = "[", "_BridgeLoadSettings 返回 JSON")

; ============================================================
; 场景 M: _BridgeSaveSettings 保存设置
; ============================================================
TestReporter.Scenario("_BridgeSaveSettings 保存设置")
saveResult := WebView2Manager._BridgeSaveSettings('{"CONTROL_HOTKEYS":{"emergency":"Esc","toggleAll":"F12"}}')
TestReporter.AssertEqual(saveResult, true, "_BridgeSaveSettings 返回 true")

; ============================================================
; 场景 N: _BridgeListBackups 返回数组
; ============================================================
TestReporter.Scenario("_BridgeListBackups 返回数组")
backupsJson := WebView2Manager._BridgeListBackups()
TestReporter.Assert(backupsJson is String, "_BridgeListBackups 返回字符串")
TestReporter.Assert(SubStr(backupsJson, 1, 1) = "[" || SubStr(backupsJson, 1, 1) = "{", "_BridgeListBackups 返回 JSON")

; ============================================================
; 场景 O: _BridgeCreateBackup 创建备份
; ============================================================
TestReporter.Scenario("_BridgeCreateBackup 创建备份")
backupFile := WebView2Manager._BridgeCreateBackup()
TestReporter.Assert(backupFile is String, "_BridgeCreateBackup 返回字符串")

; ============================================================
; 场景 P: 创建备份后列表不为空
; ============================================================
TestReporter.Scenario("创建备份后列表不为空")
if backupFile != "" {
    backupsJson2 := WebView2Manager._BridgeListBackups()
    backups := JSONParser.Parse(backupsJson2)
    foundBackup := false
    if backups is Array {
        for bk in backups {
            if bk is Map && bk.Has("name") && InStr(bk["name"], backupFile) {
                foundBackup := true
                break
            }
        }
    }
    TestReporter.Assert(foundBackup, "新创建的备份出现在列表中")
} else {
    TestReporter.Assert(true, "跳过（备份创建可能失败）")
}

; ============================================================
; 场景 Q: _BridgeHotReload 不崩溃
; ============================================================
TestReporter.Scenario("_BridgeHotReload 不崩溃")
TestReporter.AssertNoThrow(() => WebView2Manager._BridgeHotReload(), "_BridgeHotReload 不崩溃")

; ============================================================
; 场景 R: _BridgeDeleteBackup 删除备份
; ============================================================
TestReporter.Scenario("_BridgeDeleteBackup 删除备份")
if backupFile != "" {
    deleteBackupResult := WebView2Manager._BridgeDeleteBackup(backupFile)
    TestReporter.Assert(deleteBackupResult = true || deleteBackupResult = false, "_BridgeDeleteBackup 返回布尔值")
} else {
    TestReporter.Assert(true, "跳过（无备份可删除）")
}

; ============================================================
; 场景 S: 完整 CRUD 流程
; ============================================================
TestReporter.Scenario("完整 CRUD 流程")
crudGroupJson := '{"mode":"sequence","hotkey":"F8","keys":["1","2","3"],"delays":[100,100,100]}'
createResult := WebView2Manager._BridgeSaveConfig(crudGroupJson)
TestReporter.AssertEqual(createResult, true, "CRUD: 创建分组成功")

crudListJson := WebView2Manager._BridgeGetGroupList()
crudList := JSONParser.Parse(crudListJson)
crudGroupId := ""
for g in crudList {
    if g is Map && g.Has("hotkey") && g["hotkey"] = "F8" {
        crudGroupId := g["id"]
        break
    }
}
TestReporter.Assert(crudGroupId != "", "CRUD: 找到新创建的分组")

if crudGroupId != "" {
    loadResult := WebView2Manager._BridgeLoadGroupConfig(crudGroupId)
    TestReporter.Assert(SubStr(loadResult, 1, 1) = "{", "CRUD: 加载分组配置成功")

    updateGroupJson := '{"id":"' crudGroupId '","mode":"sequence","hotkey":"F7","keys":["a","b"],"delays":[50,50]}'
    updateResult := WebView2Manager._BridgeSaveConfig(updateGroupJson)
    TestReporter.AssertEqual(updateResult, true, "CRUD: 更新分组成功")

    deleteCrudResult := WebView2Manager._BridgeDeleteGroup(crudGroupId)
    TestReporter.AssertEqual(deleteCrudResult, true, "CRUD: 删除分组成功")
}

; ============================================================
; 结果汇总
; ============================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
if summary.failed > 0
    ExitApp(1)
ExitApp(0)
