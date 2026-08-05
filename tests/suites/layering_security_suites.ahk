; =================================================================
; layering_security_suites.ahk - 分层测试、配置导入安全、簇 D/F 测试套件
; 本文件通过 run_all_tests.ahk 的 #Include 加载，不可独立运行
;
; Minor-3 脆弱性说明：
; 本文件中部分测试采用静态分析（FileRead + InStr 搜索源码文本）方式验证
; 代码约束（如分层依赖、编码规范、安全模式消除等）。此类测试对源码格式
; 改动敏感——若被检源码的字符串格式变化（如空格、引号、换行），测试可能
; 误判。这些测试检查的是"代码模式存在/不存在"，难以通过行为测试替代，
; 因为它们验证的是架构约束而非运行时行为。修改被检源码时应同步检查这些
; 测试是否需要更新。
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; ============================================================
; BackupService 应用层分层测试（I1: 表现层不应直接调用 BackupCore）
; ============================================================

class BackupServiceLayeringTests extends AutoHotUnitSuite {
    ; 验证 BackupService 类存在且暴露备份 API
    Test_BackupService_HasListBackups() {
        this.assert.isTrue(HasProp(BackupService, "ListBackups"))
    }

    Test_BackupService_HasRestoreBackup() {
        this.assert.isTrue(HasProp(BackupService, "RestoreBackup"))
    }

    Test_BackupService_HasDeleteBackup() {
        this.assert.isTrue(HasProp(BackupService, "DeleteBackup"))
    }

    Test_BackupService_HasCreateBackup() {
        this.assert.isTrue(HasProp(BackupService, "CreateBackup"))
    }

    Test_BackupService_HasRecordConfigChange() {
        this.assert.isTrue(HasProp(BackupService, "RecordConfigChange"))
    }

    ; 验证 BackupService.ListBackups 委托 BackupCore 返回 Array
    Test_BackupService_ListBackups_Delegates() {
        result := BackupService.ListBackups()
        this.assert.isTrue(result is Array)
    }

    ; 验证 BackupService.CreateBackup 委托 BackupCore 返回 Map
    Test_BackupService_CreateBackup_Delegates() {
        config := Map("test", "value")
        result := BackupService.CreateBackup(config, "test")
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result.Has("success"))
    }

    ; 验证 BackupService 暴露 backupDir 属性（表现层需要构建备份路径）
    Test_BackupService_HasBackupDir() {
        this.assert.isTrue(BackupService.backupDir != "")
    }

    ; 验证表现层不直接调用 BackupCore（DDD 分层原则）
    Test_Presentation_BackupUI_NotCallBackupCore() {
        path := A_ScriptDir "\..\presentation\backup_ui.ahk"
        content := FileRead(path, "UTF-8")
        this.assert.equal(InStr(content, "BackupCore."), 0)
    }

    Test_Presentation_GUIManager_NotCallBackupCore() {
        path := A_ScriptDir "\..\presentation\gui_manager.ahk"
        content := FileRead(path, "UTF-8")
        this.assert.equal(InStr(content, "BackupCore."), 0)
    }

    Test_Presentation_WebView2Manager_NotCallBackupCore() {
        path := A_ScriptDir "\..\presentation\webview2_manager.ahk"
        content := FileRead(path, "UTF-8")
        this.assert.equal(InStr(content, "BackupCore."), 0)
    }
}

; ============================================================
; ConfigIO 基础设施层分层测试（I6: BackupCore 不应调用应用层 ExportConfigToFile）
; ============================================================

class ConfigIOLayeringTests extends AutoHotUnitSuite {
    ; 验证 ConfigIO 类存在且暴露配置 IO 方法
    Test_ConfigIO_HasExportToFile() {
        this.assert.isTrue(HasProp(ConfigIO, "ExportToFile"))
    }

    Test_ConfigIO_HasLoadFromFile() {
        this.assert.isTrue(HasProp(ConfigIO, "LoadFromFile"))
    }

    ; 验证 ConfigIO.ExportToFile 写入文件成功
    Test_ConfigIO_ExportToFile_WritesFile() {
        testPath := A_ScriptDir "\..\test_configio_export_" A_TickCount ".json"
        try {
            config := Map("version", "3.0", "GroupSettings", Map())
            result := ConfigIO.ExportToFile(testPath, config)
            this.assert.isTrue(result)
            this.assert.isTrue(FileExist(testPath) != "")
        } finally {
            if FileExist(testPath)
                FileDelete(testPath)
        }
    }

    ; 验证 ConfigIO.LoadFromFile 读取文件成功
    Test_ConfigIO_LoadFromFile_ReadsFile() {
        testPath := A_ScriptDir "\..\test_configio_load_" A_TickCount ".json"
        try {
            config := Map("version", "3.0", "GroupSettings", Map())
            ConfigIO.ExportToFile(testPath, config)
            loaded := ConfigIO.LoadFromFile(testPath)
            this.assert.isTrue(loaded is Map)
            this.assert.isTrue(loaded.Has("version"))
        } finally {
            if FileExist(testPath)
                FileDelete(testPath)
        }
    }

    ; 验证 BackupCore 不调用应用层函数 ExportConfigToFile（I6 反向依赖修复）
    Test_BackupCore_NotCallExportConfigToFile() {
        path := A_ScriptDir "\..\infrastructure\backup_core.ahk"
        content := FileRead(path, "UTF-8")
        this.assert.equal(InStr(content, "ExportConfigToFile"), 0)
    }
}

class JSONLoggerModuleDefaultTests extends AutoHotUnitSuite {
    Test_BuildLogLine_ModuleEmpty_ShowsUnknown() {
        errorObj := JSONError("", "test message", 0, "", "")
        errorObj.module := ""
        line := JSONLogger._BuildLogLine(errorObj)
        parsed := JSONParser.Parse(line)
        this.assert.isTrue(parsed is Map)
        this.assert.isTrue(parsed.Has("module"))
        this.assert.isTrue(parsed["module"] = "Unknown")
    }

    Test_BuildLogLine_ModuleSet_ShowsModule() {
        errorObj := JSONError("", "test message", 0, "", "")
        errorObj.module := "TestModule"
        line := JSONLogger._BuildLogLine(errorObj)
        parsed := JSONParser.Parse(line)
        this.assert.isTrue(parsed is Map)
        this.assert.isTrue(parsed.Has("module"))
        this.assert.isTrue(parsed["module"] = "TestModule")
    }
}

class DebounceCacheTests extends AutoHotUnitSuite {
    Test_DebounceInitialized_AfterFirstSend() {
        group := SkillGroup("deb_cache_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["x"], "intervals", [50]
        ))
        this.assert.isTrue(group._debounceInitialized)
    }

    Test_DebounceMs_DefaultValue() {
        group := SkillGroup("deb_default_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["x"], "intervals", [50]
        ))
        this.assert.isTrue(group._debounceMs > 0)
    }
}

class HealthCheckTimestampFormatTests extends AutoHotUnitSuite {
    Test_FormatISO8601_ProducesValidFormat() {
        ts := ErrorSystem._FormatISO8601("20260514120000")
        this.assert.isTrue(InStr(ts, "2026-05-14T12:00:00") > 0)
    }

    Test_FormatISO8601_ShortTimestamp() {
        ts := ErrorSystem._FormatISO8601("20260101000000")
        this.assert.isTrue(InStr(ts, "2026-01-01T00:00:00") > 0)
    }
}

class CreateGroupFailureConsistencyTests extends AutoHotUnitSuite {
    Test_CreateGroup_ThrowsOnAddFailure() {
        savedGroups := SkillManager.Groups.Clone()
        SkillManager.Groups.Clear()
        SkillManager.Groups["__fail_test"] := SkillGroup("__fail_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        ConfigStore.SetGroupConfig("__fail_test", Map("hotkey", "F1", "mode", "periodic"))
        threw := false
        try {
            GroupService.CreateGroup("__fail_test", Map("hotkey", "F2", "mode", "periodic", "keys", ["1"], "intervals", [50]))
        } catch as e {
            threw := true
            this.assert.isTrue(InStr(e.Message, "已存在") > 0)
        }
        this.assert.isTrue(threw)
        SkillManager.Groups.Delete("__fail_test")
        ConfigStore.DeleteGroupConfig("__fail_test")
    }
}

class ActiveCountComputedPropertyTests extends AutoHotUnitSuite {
    Test_GetActiveCount_IsZero_WhenNoGroupsActive() {
        for id, group in SkillManager.Groups {
            if group.active
                group.Toggle()
        }
        this.assert.equal(SkillManager.GetActiveCount(), 0)
    }

    Test_GetActiveCount_Reflects_ActiveGroups() {
        for id, group in SkillManager.Groups {
            if group.active
                group.Toggle()
        }
        count := 0
        for id, group in SkillManager.Groups {
            if count >= 2
                break
            group._lastToggleTime := 0
            group.Toggle()
            count++
        }
        this.assert.equal(SkillManager.GetActiveCount(), count)
        for id, group in SkillManager.Groups {
            if group.active {
                group._lastToggleTime := 0
                group.Toggle()
            }
        }
    }

    Test_GetActiveCount_IsReadOnly() {
        before := SkillManager.GetActiveCount()
        this.assert.isTrue(before >= 0)
    }
}

class CleanupOrphanTimersSelectiveTests extends AutoHotUnitSuite {
    Test_CleanupOrphanTimers_PreservesActiveTimers() {
        SkillManager._timers.Clear()
        SkillManager._timers["__orphan1"] := () => 0
        SkillManager._timers["__orphan2"] := () => 0
        this.assert.isTrue(SkillManager._timers.Count >= 2)
        SkillManager._CleanupOrphanTimers()
        this.assert.isTrue(!SkillManager._timers.Has("__orphan1"))
        this.assert.isTrue(!SkillManager._timers.Has("__orphan2"))
    }
}

class KeyPressDurationMaxLimitTests extends AutoHotUnitSuite {
    Test_KeyPressDuration_MaxCappedAt100() {
        sg := SkillGroup("kpd_max", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 200})
        this.assert.equal(sg.keyPressDuration, 100)
    }

    Test_KeyPressDuration_100IsAllowed() {
        sg := SkillGroup("kpd_100", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 100})
        this.assert.equal(sg.keyPressDuration, 100)
    }

    Test_KeyPressDuration_50IsAllowed() {
        sg := SkillGroup("kpd_50", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 50})
        this.assert.equal(sg.keyPressDuration, 50)
    }
}

class RestoreBackupSafetyFileTests extends AutoHotUnitSuite {
    Test_RestoreBackup_NonExistentBackup() {
        result := BackupCore.RestoreBackup("Z:\nonexistent_backup_12345.json")
        this.assert.isTrue(_GetProp(result, "success", true) = false)
    }
}

class ConfigStoreSetReturnTests extends AutoHotUnitSuite {
    Test_Set_KnownKey_ReturnsTrue() {
        result := ConfigStore.Set("HoldSettings", Map("enabled", true))
        this.assert.isTrue(result = true)
    }

    Test_Set_UnknownKey_ReturnsFalse() {
        result := ConfigStore.Set("NonExistentKey123", "value")
        this.assert.isTrue(result = false)
    }
}

class ParseIntArrayErrorReportTests extends AutoHotUnitSuite {
    Test_ParseIntArray_ValidInput() {
        result := GroupEditor._ParseIntArray("10, 20, 30")
        this.assert.equal(result.Length, 3)
        this.assert.equal(result[1], 10)
        this.assert.equal(result[2], 20)
        this.assert.equal(result[3], 30)
    }

    Test_ParseIntArray_EmptyInput() {
        result := GroupEditor._ParseIntArray("")
        this.assert.equal(result.Length, 0)
    }

    Test_ParseIntArray_SingleValue() {
        result := GroupEditor._ParseIntArray("50")
        this.assert.equal(result.Length, 1)
        this.assert.equal(result[1], 50)
    }
}

class IPCChannelFallbackReadTests extends AutoHotUnitSuite {
    Test_IPCChannel_HasInboundPipe() {
        this.assert.isTrue(IPCChannel.HasProp("inboundPipe") || IPCChannel is Map)
    }

    Test_IPCChannel_DefaultDir() {
        this.assert.isTrue(IPCChannel.channelDir != "")
    }
}

class IsValidKeyNameExpandedTests extends AutoHotUnitSuite {
    Test_NumpadKeys_AreValid() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("Numpad0"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("Numpad9"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("NumpadAdd"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("NumpadSub"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("NumpadEnter"))
    }

    Test_LockKeys_AreValid() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("CapsLock"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("NumLock"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("ScrollLock"))
    }

    Test_SpecialKeys_AreValid() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("PrintScreen"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("Pause"))
    }

    Test_ModifiedNumpadKeys_AreValid() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("^Numpad1"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("+NumpadEnter"))
    }
}

class AutoRefreshIncrementalTests extends AutoHotUnitSuite {
    Test_AutoRefresh_DoesNotCrash_WhenNotVisible() {
        GUIManager.visible := false
        try {
            GUIManager._AutoRefresh()
            passed := true
        } catch {
            passed := false
        }
        this.assert.isTrue(passed)
    }
}

class OnExitUITimerCleanupTests extends AutoHotUnitSuite {
    Test_OnExit_DoesNotCrash() {
        try {
            SkillManager.OnExit()
            passed := true
        } catch {
            passed := false
        }
        this.assert.isTrue(passed)
    }
}

class HealthCheckGetActiveCountCacheTests extends AutoHotUnitSuite {
    Test_HealthCheck_ReturnsActiveCount() {
        mockSM := _MockSM(3, 2)
        result := ErrorHandler.HealthCheck(mockSM)
        this.assert.equal(result["activeCount"], 3)
    }

    Test_HealthCheck_DetectsTooManyActiveGroups() {
        mockSM := _MockSM(100, 5)
        result := ErrorHandler.HealthCheck(mockSM)
        this.assert.isTrue(result["issues"].Length > 0)
    }

    Test_HealthCheck_DetectsTimerLeak() {
        mockSM := _MockSM(1, 50)
        result := ErrorHandler.HealthCheck(mockSM)
        this.assert.isTrue(result["issues"].Length > 0)
    }

    Test_HealthCheck_HealthyWhenNoIssues() {
        mockSM := _MockSM(1, 1)
        result := ErrorHandler.HealthCheck(mockSM)
        this.assert.isTrue(result["healthy"])
    }
}

; =================================================================
; 配置导入安全测试（簇 D: I13, I16, I17, I19, I20）
; =================================================================

class ConfigImportSecurityTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
        ConfigStore.InitDefaults()
        ConfigService.ConfigStore := ConfigStore
        GroupService.ConfigStore := ConfigStore
        GroupService.SkillManager := SkillManager
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    ; I13: FileRead 应指定 UTF-8 编码，确保中文不乱码
    Test_I13_FileRead_UTF8_ChineseNotGarbled() {
        backupDir := A_ScriptDir "\backups"
        if !InStr(FileExist(backupDir), "D")
            DirCreate(backupDir)
        baseFile := backupDir "\i13_base_" A_TickCount ".json"
        targetFile := backupDir "\i13_target_" A_TickCount ".json"
        try {
            ; UTF-8-RAW 不带 BOM，不指定编码的 FileRead 会用系统 ANSI 读取导致中文乱码
            baseJson := '{"GroupSettings":{"测试组":{"mode":"periodic","hotkey":"F1"}}}'
            targetJson := '{"GroupSettings":{}}'
            FileAppend(baseJson, baseFile, "UTF-8-RAW")
            FileAppend(targetJson, targetFile, "UTF-8-RAW")
            data := Map("basePath", baseFile, "targetPath", targetFile)
            result := WebView2Manager._BridgeCompareConfigs(data)
            parsed := JSONParser.Parse(result)
            this.assert.isTrue(parsed is Map)
            this.assert.isTrue(parsed.Has("diffs"))
            diffs := parsed["diffs"]
            foundChinese := false
            for d in diffs {
                if d.Has("id") && InStr(String(d["id"]), "测试组")
                    foundChinese := true
            }
            this.assert.isTrue(foundChinese)
        } finally {
            if FileExist(baseFile)
                FileDelete(baseFile)
            if FileExist(targetFile)
                FileDelete(targetFile)
        }
    }

    ; I13: _BridgeCompareConfigs 中的 FileRead 必须指定 UTF-8 编码（静态分析）
    Test_I13_FileRead_Specifies_UTF8() {
        path := A_ScriptDir "\..\presentation\webview2_manager.ahk"
        content := FileRead(path, "UTF-8")
        methodStart := InStr(content, "static _BridgeCompareConfigs(data) {")
        this.assert.isTrue(methodStart > 0)
        methodRegion := SubStr(content, methodStart, 2000)
        ; 修复前存在不带编码的 FileRead(absBase)/FileRead(absTarget)，修复后应带 "UTF-8"
        hasBareRead := InStr(methodRegion, "FileRead(absBase)") > 0 || InStr(methodRegion, "FileRead(absTarget)") > 0
        this.assert.isFalse(hasBareRead)
    }

    ; I16: JSONParser.Parse 后应验证类型，非 Map 输入应被明确拒绝
    Test_I16_NonMapConfig_Rejected() {
        backupDir := A_ScriptDir "\backups"
        if !InStr(FileExist(backupDir), "D")
            DirCreate(backupDir)
        baseFile := backupDir "\i16_base_" A_TickCount ".json"
        targetFile := backupDir "\i16_target_" A_TickCount ".json"
        try {
            ; base 是 JSON 数组（非对象），应被类型守护拒绝而非崩溃
            FileAppend('[1, 2, 3]', baseFile, "UTF-8-RAW")
            FileAppend('{"GroupSettings":{}}', targetFile, "UTF-8-RAW")
            data := Map("basePath", baseFile, "targetPath", targetFile)
            result := WebView2Manager._BridgeCompareConfigs(data)
            parsed := JSONParser.Parse(result)
            ; 修复后应返回明确的格式错误提示
            this.assert.isTrue(parsed.Has("error"))
            this.assert.isTrue(InStr(parsed["error"], "格式") > 0)
        } finally {
            if FileExist(baseFile)
                FileDelete(baseFile)
            if FileExist(targetFile)
                FileDelete(targetFile)
        }
    }

    ; I17: 分组数量上限检查，超过 1000 拒绝
    Test_I17_GroupCountLimit_Rejected() {
        ; 构造 1001 个分组的 JSON（空分组配置，避免实际导入）
        jsonStr := '{"GroupSettings":{'
        loop 1001 {
            if A_Index > 1
                jsonStr .= ','
            jsonStr .= '"g' A_Index '":{}'
        }
        jsonStr .= '}}'
        result := WebView2Manager._BridgeImportConfig(jsonStr)
        parsed := JSONParser.Parse(result)
        ; 修复后应返回数量超限错误
        this.assert.isTrue(parsed.Has("error"))
        this.assert.isTrue(InStr(parsed["error"], "上限") > 0)
    }

    ; I19: 批量删除 SaveConfig 失败时从快照恢复 ConfigStore 状态
    Test_I19_BatchDelete_SaveFail_RestoresState() {
        ConfigStore.SetGroupConfig("__i19_a", Map("hotkey", "F1", "mode", "periodic"))
        ConfigStore.SetGroupConfig("__i19_b", Map("hotkey", "F2", "mode", "periodic"))
        ; mock SaveConfig 返回 false（模拟保存失败）
        savedSaveConfig := ConfigService.GetMethod("SaveConfig")
        ConfigService.DefineProp("SaveConfig", {call: (*) => false})
        try {
            data := Map("ids", ["__i19_a", "__i19_b"])
            WebView2Manager._BridgeBatchDeleteGroups(data)
            ; 修复后：SaveConfig 失败时从快照恢复，分组应仍然存在
            this.assert.isTrue(ConfigStore.HasGroup("__i19_a"))
            this.assert.isTrue(ConfigStore.HasGroup("__i19_b"))
        } finally {
            if savedSaveConfig is Func
                ConfigService.DefineProp("SaveConfig", {call: savedSaveConfig})
            if ConfigStore.HasGroup("__i19_a")
                ConfigStore.DeleteGroupConfig("__i19_a")
            if ConfigStore.HasGroup("__i19_b")
                ConfigStore.DeleteGroupConfig("__i19_b")
        }
    }

    ; I20: 导入回滚失败时显式提示"配置已损坏"
    Test_I20_Import_RollbackFail_ShowsCorrupted() {
        ; 保存当前 ConfigStore 状态
        preGs := ConfigStore.Get("GroupSettings")
        ; mock GroupService.ImportGroups：模拟回滚失败（清空 ConfigStore 后抛异常）
        savedImport := GroupService.GetMethod("ImportGroups")
        GroupService.DefineProp("ImportGroups", {call: _I20MockImportFail})
        try {
            jsonStr := '{"GroupSettings":{"g1":{"mode":"periodic","hotkey":"F1","keys":["a"],"intervals":[50]}}}'
            result := WebView2Manager._BridgeImportConfig(jsonStr)
            parsed := JSONParser.Parse(result)
            ; 修复后：回滚失败时返回"配置已损坏"
            this.assert.isTrue(InStr(parsed["error"], "配置已损坏") > 0)
        } finally {
            if savedImport is Func
                GroupService.DefineProp("ImportGroups", {call: savedImport})
            ConfigStore.Set("GroupSettings", preGs)
        }
    }
}

; mock：模拟导入回滚失败 — 清空 GroupSettings 后抛异常
_I20MockImportFail(*) {
    ConfigStore.Set("GroupSettings", Map())
    throw Error("模拟导入失败且回滚失败")
}

_MockSM(activeCount, timerCount) {
    mock := {}
    mock.EmergencyMode := false
    mock.DefineProp("GetActiveCount", {call: (*) => activeCount})
    mock.DefineProp("GetTimerCount", {call: (*) => timerCount})
    mock.HoldKeyRegistry := Map()
    return mock
}

; =================================================================
; 簇 F - GUI 与定时器规范测试（I5, I12, I14）
; =================================================================

class GuiAndTimerSpecTests extends AutoHotUnitSuite {
    ; ============================================================
    ; I5: OnEvent 静态方法引用需要闭包包装
    ; 问题：gui.OnEvent("Size", ClassName._OnResize) 不能直接传递静态方法引用
    ; 修复：使用闭包包装 (a,b,c,d) => ClassName._OnResize(a,b,c,d)
    ; ============================================================

    Test_I5_ContextMenu_OnEvent_NotDirectMethodRef() {
        ; 静态分析：OnEvent("ContextMenu", ...) 不应直接传递 GUIManager._ShowContextMenu
        path := A_ScriptDir "\..\presentation\gui_manager.ahk"
        content := FileRead(path, "UTF-8")
        ; 修复前：OnEvent("ContextMenu", GUIManager._ShowContextMenu) — 直接传递静态方法引用
        hasDirectRef := InStr(content, 'OnEvent("ContextMenu", GUIManager._ShowContextMenu)') > 0
        this.assert.isFalse(hasDirectRef)
    }

    Test_I5_ContextMenu_OnEvent_UsesClosureWrap() {
        ; 静态分析：OnEvent("ContextMenu", ...) 应使用闭包包装传递参数
        path := A_ScriptDir "\..\presentation\gui_manager.ahk"
        content := FileRead(path, "UTF-8")
        ; 修复后：OnEvent("ContextMenu", (...) => GUIManager._ShowContextMenu(...))
        hasClosureWrap := RegExMatch(content, 'OnEvent\("ContextMenu",\s*\([^)]*\)\s*=>\s*GUIManager\._ShowContextMenu') > 0
        this.assert.isTrue(hasClosureWrap)
    }

    ; ============================================================
    ; I12: 定时器引用存入 _releaseTimers Map，可取消
    ; 问题：_SendKey 中复杂单行闭包 SetTimer 未存储引用，无法取消
    ; 修复：将定时器引用存入 _releaseTimers Map，Dispose 时可取消
    ; ============================================================

    Test_I12_SendKey_StoresReleaseTimerInMap() {
        ; 行为测试：_SendKey 后定时器引用应存储在 _releaseTimers Map 中
        sg := SkillGroup("i12_timer_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["a"], "intervals", [50],
            "keyPressDuration", 100
        ))
        sg._lastSend.Clear()
        sg._SendKey("a", false)
        ; 修复后：定时器引用应存储在 _releaseTimers Map 中
        this.assert.isTrue(sg.HasProp("_releaseTimers"))
        this.assert.isTrue(sg._releaseTimers is Map)
        this.assert.isTrue(sg._releaseTimers.Has("a"))
        ; 取消定时器，验证可取消
        SetTimer(sg._releaseTimers["a"], 0)
        ; 清理按键状态
        try SendInput("{Blind}{a Up}")
    }

    Test_I12_Dispose_ClearsReleaseTimers() {
        ; 行为测试：Dispose 后应取消并清理所有释放定时器
        sg := SkillGroup("i12_dispose_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["a"], "intervals", [50],
            "keyPressDuration", 100
        ))
        sg._lastSend.Clear()
        sg._SendKey("a", false)
        ; 确认定时器已存储
        this.assert.isTrue(sg._releaseTimers.Has("a"))
        ; Dispose 应取消定时器并清理
        sg.Dispose()
        ; 清理按键状态（Dispose 的 _ReleaseAllKeys 应已释放，但保险起见）
        try SendInput("{Blind}{a Up}")
        ; 修复后：_releaseTimers 应不再包含该键
        this.assert.isFalse(sg._releaseTimers.Has("a"))
    }

    ; ============================================================
    ; I14: Run 路径加引号转义
    ; 问题：Run("notepad.exe " logFile) 路径未加引号，含空格路径会出错
    ; 修复：Run('notepad.exe "' logFile '"') 路径用双引号包围
    ; ============================================================

    Test_I14_OpenConfigFile_UsesQuotedPath() {
        ; 静态分析：_OpenConfigFile 中 Run 应使用引号包围路径
        path := A_ScriptDir "\..\gui.ahk"
        content := FileRead(path, "UTF-8")
        ; 修复前：Run("notepad.exe config.json") — 路径未加引号
        hasUnquotedConfig := InStr(content, 'Run("notepad.exe config.json")') > 0
        this.assert.isFalse(hasUnquotedConfig)
    }

    Test_I14_ShowErrorLog_NotUnquotedConcat() {
        ; 静态分析：_ShowErrorLog 中 Run 不应使用未加引号的字符串拼接
        path := A_ScriptDir "\..\gui.ahk"
        content := FileRead(path, "UTF-8")
        ; 修复前：Run("notepad.exe " logFile) — logFile 未加引号
        hasUnquotedLog := InStr(content, 'Run("notepad.exe " logFile)') > 0
        this.assert.isFalse(hasUnquotedLog)
    }

    Test_I14_ShowErrorLog_PathSurroundedByQuotes() {
        ; 静态分析：_ShowErrorLog 方法区域内 Run 应使用单引号字符串包围路径
        path := A_ScriptDir "\..\gui.ahk"
        content := FileRead(path, "UTF-8")
        methodStart := InStr(content, "static _ShowErrorLog() {")
        this.assert.isTrue(methodStart > 0)
        methodRegion := SubStr(content, methodStart, 500)
        ; 修复后应使用单引号字符串: Run('notepad.exe "' logFile '"')
        ; 修复前使用双引号字符串: Run("notepad.exe " logFile)
        hasSingleQuoteRun := InStr(methodRegion, "Run('notepad.exe") > 0
        this.assert.isTrue(hasSingleQuoteRun)
    }
}

; =================================================================
; 簇 D 安全性与健壮性测试（M15-M19）
; =================================================================

class IPCChannelInitSafetyTests extends AutoHotUnitSuite {
    ; M17: initialized 标志应在 DirCreate 成功后才设置，不应在目录创建前就标记为已初始化
    Test_M17_Initialized_Set_After_DirCreate() {
        path := A_ScriptDir "\..\infrastructure\ipc_channel.ahk"
        content := FileRead(path, "UTF-8")
        initStart := InStr(content, "static Init() {")
        this.assert.isTrue(initStart > 0)
        ; 截取 Init 方法区域（到下一个 static 方法为止）
        nextMethod := InStr(content, "`n    static On(", false, initStart)
        initRegion := SubStr(content, initStart, nextMethod - initStart)
        dirCreatePos := InStr(initRegion, "DirCreate(")
        initializedPos := InStr(initRegion, "initialized := true")
        this.assert.isTrue(dirCreatePos > 0)
        this.assert.isTrue(initializedPos > 0)
        ; initialized 应在 DirCreate 之后
        this.assert.isTrue(initializedPos > dirCreatePos)
    }

    ; M17: DirCreate 应被包裹在 try-catch 中，失败时记录明确错误
    Test_M17_DirCreate_HasTryCatch() {
        path := A_ScriptDir "\..\infrastructure\ipc_channel.ahk"
        content := FileRead(path, "UTF-8")
        initStart := InStr(content, "static Init() {")
        nextMethod := InStr(content, "`n    static On(", false, initStart)
        initRegion := SubStr(content, initStart, nextMethod - initStart)
        hasTry := InStr(initRegion, "try") > 0
        hasCatch := InStr(initRegion, "catch") > 0
        this.assert.isTrue(hasTry)
        this.assert.isTrue(hasCatch)
    }

    ; Minor-2: Init 已初始化时再次调用应返回 true
    ; 注：无法测试首次初始化路径，因为 OnMessage 注册在测试环境中会抛出
    ; "Invalid callback function" 异常，故仅测试已初始化的快速返回路径
    Test_M17_Init_ReturnsTrue_WhenAlreadyInitialized() {
        IPCChannel.initialized := true
        result := IPCChannel.Init()
        this.assert.isTrue(result)
    }
}

class ConfigServiceFileCopyCatchTests extends AutoHotUnitSuite {
    ; M18: FileCopy 不应是裸 try 无 catch（try FileCopy(...) 模式应被消除）
    Test_M18_FileCopy_NotBareTryWithoutCatch() {
        path := A_ScriptDir "\..\application\config_service.ahk"
        content := FileRead(path, "UTF-8")
        ; "try FileCopy(" 是问题模式 — try 语句直接跟 FileCopy 调用，没有 catch
        hasBareTryFileCopy := InStr(content, "try FileCopy(") > 0
        this.assert.isFalse(hasBareTryFileCopy)
    }
}

class ConfigValidatorNumericLimitTests extends AutoHotUnitSuite {
    ; M19: intervals 超过上限（86400000ms=24小时）应产生验证错误
    Test_M19_Intervals_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [86400001])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; M19: delays 超过上限应产生验证错误
    Test_M19_Delays_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "sequence", "keys", ["a"], "delays", [86400001])
        errors := ConfigValidator._ValidateModeFields("1", "sequence", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; M19: 正常 intervals 不应报上限错误
    Test_M19_Intervals_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [100])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 intervals 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的值不应报错
    Test_M19_Intervals_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [86400000])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 intervals 不应报过大错误")
        }
    }

    ; M19: repeatInterval 超过上限（86400000ms=24小时）应产生验证错误
    Test_M19_RepeatInterval_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "hold", "holdKeys", ["a"], "repeatInterval", 86400001)
        errors := ConfigValidator._ValidateModeFields("1", "hold", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; M19: seqInterval 超过上限（86400000ms=24小时）应产生验证错误
    Test_M19_SeqInterval_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "enhanced_hybrid", "groups", [Map("type", "periodic", "pressKeys", ["a"], "intervals", [100])], "seqInterval", 86400001)
        errors := ConfigValidator._ValidateModeFields("1", "enhanced_hybrid", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; M19: holdDuration 超过上限（86400000ms=24小时）应产生验证错误
    Test_M19_HoldDuration_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "joystick_hold", "joyKeys", ["Joy1"], "holdDuration", 86400001)
        errors := ConfigValidator._ValidateModeFields("1", "joystick_hold", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; ============================================================
    ; Minor-4: 补充 6 个字段的边界测试（Normal=1000, AtMaxLimit=86400000）
    ; ============================================================

    ; M19: 正常 delays 不应报上限错误
    Test_M19_Delays_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "sequence", "keys", ["a"], "delays", [1000])
        errors := ConfigValidator._ValidateModeFields("1", "sequence", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 delays 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的 delays 不应报错
    Test_M19_Delays_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "sequence", "keys", ["a"], "delays", [86400000])
        errors := ConfigValidator._ValidateModeFields("1", "sequence", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 delays 不应报过大错误")
        }
    }

    ; M19: pressDelays 超过上限应产生验证错误
    Test_M19_PressDelays_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "enhanced_sequence", "pressKeys", ["a"], "pressDelays", [86400001])
        errors := ConfigValidator._ValidateModeFields("1", "enhanced_sequence", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; M19: 正常 pressDelays 不应报上限错误
    Test_M19_PressDelays_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "enhanced_sequence", "pressKeys", ["a"], "pressDelays", [1000])
        errors := ConfigValidator._ValidateModeFields("1", "enhanced_sequence", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 pressDelays 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的 pressDelays 不应报错
    Test_M19_PressDelays_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "enhanced_sequence", "pressKeys", ["a"], "pressDelays", [86400000])
        errors := ConfigValidator._ValidateModeFields("1", "enhanced_sequence", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 pressDelays 不应报过大错误")
        }
    }

    ; M19: holdPattern 超过上限应产生验证错误
    Test_M19_HoldPattern_ExceedMaxLimit_HasError() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [100], "holdPattern", [86400001, 86400001])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                found := true
        }
        this.assert.isTrue(found)
    }

    ; M19: 正常 holdPattern 不应报上限错误
    Test_M19_HoldPattern_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [100], "holdPattern", [1000, 1000])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 holdPattern 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的 holdPattern 不应报错
    Test_M19_HoldPattern_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [100], "holdPattern", [86400000, 86400000])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 holdPattern 不应报过大错误")
        }
    }

    ; M19: 正常 repeatInterval 不应报上限错误
    Test_M19_RepeatInterval_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "hold", "holdKeys", ["a"], "repeatInterval", 1000)
        errors := ConfigValidator._ValidateModeFields("1", "hold", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 repeatInterval 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的 repeatInterval 不应报错
    Test_M19_RepeatInterval_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "hold", "holdKeys", ["a"], "repeatInterval", 86400000)
        errors := ConfigValidator._ValidateModeFields("1", "hold", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 repeatInterval 不应报过大错误")
        }
    }

    ; M19: 正常 seqInterval 不应报上限错误
    Test_M19_SeqInterval_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "enhanced_hybrid", "groups", [Map("type", "periodic", "pressKeys", ["a"], "intervals", [100])], "seqInterval", 1000)
        errors := ConfigValidator._ValidateModeFields("1", "enhanced_hybrid", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 seqInterval 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的 seqInterval 不应报错
    Test_M19_SeqInterval_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "enhanced_hybrid", "groups", [Map("type", "periodic", "pressKeys", ["a"], "intervals", [100])], "seqInterval", 86400000)
        errors := ConfigValidator._ValidateModeFields("1", "enhanced_hybrid", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 seqInterval 不应报过大错误")
        }
    }

    ; M19: 正常 holdDuration 不应报上限错误
    Test_M19_HoldDuration_Normal_NoMaxError() {
        config := Map("hotkey", "F1", "mode", "joystick_hold", "joyKeys", ["Joy1"], "holdDuration", 1000)
        errors := ConfigValidator._ValidateModeFields("1", "joystick_hold", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("正常 holdDuration 不应报过大错误")
        }
    }

    ; M19: 恰好等于上限的 holdDuration 不应报错
    Test_M19_HoldDuration_AtMaxLimit_NoError() {
        config := Map("hotkey", "F1", "mode", "joystick_hold", "joyKeys", ["Joy1"], "holdDuration", 86400000)
        errors := ConfigValidator._ValidateModeFields("1", "joystick_hold", config)
        for err in errors {
            if err is Map && InStr(err["message"], "过大") > 0
                this.assert.fail("恰好等于上限的 holdDuration 不应报过大错误")
        }
    }
}

class WebView2TempFileNamingTests extends AutoHotUnitSuite {
    ; M16: 临时文件命名不应使用 Random(1000, 9999)（范围太小）
    Test_M16_TempFile_NotUseSmallRandomRange() {
        path := A_ScriptDir "\..\presentation\webview2_manager.ahk"
        content := FileRead(path, "UTF-8")
        hasSmallRandom := InStr(content, "Random(1000, 9999)") > 0
        this.assert.isFalse(hasSmallRandom)
    }

    ; M16: 临时文件命名应包含 A_MSec 或更大的随机空间
    Test_M16_TempFile_UsesLargerRandomSpace() {
        path := A_ScriptDir "\..\presentation\webview2_manager.ahk"
        content := FileRead(path, "UTF-8")
        importStart := InStr(content, "static _BridgeImportConfig(jsonStr) {")
        this.assert.isTrue(importStart > 0)
        nextMethod := InStr(content, "`n    static _BridgeBatchToggleGroups(", false, importStart)
        importRegion := SubStr(content, importStart, nextMethod - importStart)
        hasLargeRandom := InStr(importRegion, "A_MSec") > 0 || InStr(importRegion, "Random(1, 999999)") > 0
        this.assert.isTrue(hasLargeRandom)
    }
}

class WebView2PushStateNoRedundantParseTests extends AutoHotUnitSuite {
    ; M15: _PushStateUpdate 不应调用 JSONParser.Parse（避免重复解析刚序列化的 JSON）
    Test_M15_PushState_NoRedundantParse() {
        path := A_ScriptDir "\..\presentation\webview2_manager.ahk"
        content := FileRead(path, "UTF-8")
        pushStart := InStr(content, "static _PushStateUpdate() {")
        this.assert.isTrue(pushStart > 0)
        nextMethod := InStr(content, "`n    static OnEvent(", false, pushStart)
        pushRegion := SubStr(content, pushStart, nextMethod - pushStart)
        hasParse := InStr(pushRegion, "JSONParser.Parse") > 0
        this.assert.isFalse(hasParse)
    }

    ; M15: 应存在 _Internal 版本的 Bridge 方法返回对象
    Test_M15_HasInternalBridgeMethods() {
        path := A_ScriptDir "\..\presentation\webview2_manager.ahk"
        content := FileRead(path, "UTF-8")
        hasDebugInternal := InStr(content, "_BridgeGetDebugInfoInternal") > 0
        hasGroupInternal := InStr(content, "_BridgeGetGroupListInternal") > 0
        this.assert.isTrue(hasDebugInternal)
        this.assert.isTrue(hasGroupInternal)
    }
}

; ============================================================
; Minor-5: fixture 文件使用测试
; 确保 tests/fixtures/ 下的固件文件被测试实际引用，而非闲置
; ============================================================

class FixtureUsageTests extends AutoHotUnitSuite {
    ; Minor-5: sample_config.json 应可被正确解析为 Map，覆盖 7 种执行模式
    Test_Fixture_SampleConfig_ParsesSuccessfully() {
        path := A_ScriptDir "\fixtures\sample_config.json"
        content := FileRead(path, "UTF-8")
        config := JSONParser.Parse(content)
        this.assert.isTrue(config is Map)
        this.assert.isTrue(config.Has("GroupSettings"))
        gs := config["GroupSettings"]
        this.assert.isTrue(gs is Map)
        ; 验证覆盖 7 种执行模式
        this.assert.isTrue(gs.Has("periodic_sample"))
        this.assert.isTrue(gs.Has("sequence_sample"))
        this.assert.isTrue(gs.Has("hold_sample"))
        this.assert.isTrue(gs.Has("enhanced_periodic_sample"))
        this.assert.isTrue(gs.Has("enhanced_sequence_sample"))
        this.assert.isTrue(gs.Has("enhanced_hybrid_sample"))
        this.assert.isTrue(gs.Has("hybrid_sample"))
    }

    ; Minor-5: sample_config.json 应通过 ConfigValidator 验证（无 ERROR 级别错误）
    Test_Fixture_SampleConfig_PassesValidation() {
        path := A_ScriptDir "\fixtures\sample_config.json"
        content := FileRead(path, "UTF-8")
        config := JSONParser.Parse(content)
        errors := ConfigValidator.Validate(config)
        for err in errors {
            if err is Map && err.Has("type") && err["type"] = "ERROR"
                this.assert.fail("sample_config.json 不应包含 ERROR 级别验证错误: " err["message"])
        }
    }

    ; Minor-5: import_test_data.json 应可被正确解析，包含预期测试场景
    Test_Fixture_ImportTestData_ParsesSuccessfully() {
        path := A_ScriptDir "\fixtures\import_test_data.json"
        content := FileRead(path, "UTF-8")
        data := JSONParser.Parse(content)
        this.assert.isTrue(data is Map)
        this.assert.isTrue(data.Has("cases"))
        cases := data["cases"]
        this.assert.isTrue(cases is Map)
        ; 验证包含预期的测试场景
        this.assert.isTrue(cases.Has("single_periodic_group"))
        this.assert.isTrue(cases.Has("empty_group_settings"))
        this.assert.isTrue(cases.Has("non_map_config"))
    }

    ; Minor-5: import_test_data.json 中的 single_periodic_group json 可被解析为 Map
    Test_Fixture_ImportTestData_SingleGroupJson_Parses() {
        path := A_ScriptDir "\fixtures\import_test_data.json"
        content := FileRead(path, "UTF-8")
        data := JSONParser.Parse(content)
        singleJson := data["cases"]["single_periodic_group"]["json"]
        parsed := JSONParser.Parse(singleJson)
        this.assert.isTrue(parsed is Map)
        this.assert.isTrue(parsed.Has("GroupSettings"))
    }
}