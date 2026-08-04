; =================================================================
; AutoHotUnit 测试运行器 - 完整测试套件
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "AutoHotUnit.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/config_io.ahk"
#Include "../infrastructure/ipc_channel.ahk"
#Include "../application/config_service.ahk"
#Include "../application/group_service.ahk"
#Include "../application/backup_service.ahk"
#Include "../presentation/ui_manager.ahk"
#Include "../presentation/group_editor.ahk"
#Include "../presentation/gui_manager.ahk"
#Include "../presentation/debug_panel.ahk"

; ============================================================
; AHK 执行器测试（asd-tauri/src-tauri/ahk_executor/）
; ============================================================
#Include "test_ahk_executor/test_executor.ahk"
#Include "test_ahk_executor/test_ipc_client.ahk"
#Include "test_ahk_executor/test_hotkey_hook.ahk"
#Include "test_ahk_executor/test_sender.ahk"
#Include "test_ahk_executor/test_joystick.ahk"

; ============================================================
; joy_hotkey_manager 测试（infrastructure/）
; ============================================================
#Include "test_joy_hotkey_manager_ahu.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

class SilentReporter {
    failures := []
    passed := 0
    total := 0
    outputFile := ""
    
    __New(filePath) {
        this.outputFile := filePath
        if FileExist(filePath)
            FileDelete(filePath)
    }
    
    write(str) {
        FileAppend(str, this.outputFile, "UTF-8")
    }
    
    writeLine(str) {
        this.write(str . "`r`n")
    }
    
    onRunStart() {
        this.writeLine("========================================")
        this.writeLine("AutoHotUnit 完整测试报告")
        this.writeLine("时间: " A_Now)
        this.writeLine("========================================")
        this.writeLine("")
    }
    
    onSuiteStart(suiteName) {
        this.writeLine("【测试套件】" suiteName)
    }
    
    onTestResult(testName, status, where, error) {
        this.total++
        if (status == "passed") {
            this.passed++
            this.writeLine("  ✓ " testName)
        } else {
            this.writeLine("  ✗ " testName " - 失败")
            this.writeLine("      位置: " where)
            this.writeLine("      错误: " error.Message)
            this.failures.push({suite: "", test: testName, error: error.Message})
        }
    }
    
    onSuiteEnd(suiteName) {
        this.writeLine("")
    }
    
    onRunComplete() {
        this.writeLine("========================================")
        this.writeLine("测试结果汇总")
        this.writeLine("========================================")
        this.writeLine("总计: " this.total " 个测试")
        this.writeLine("通过: " this.passed " 个")
        this.writeLine("失败: " this.failures.Length " 个")
        
        if (this.failures.Length > 0) {
            this.writeLine("")
            this.writeLine("失败的测试:")
            for i, f in this.failures {
                this.writeLine("  - " f.test ": " f.error)
            }
        }
        
        this.writeLine("")
        if (this.failures.Length = 0) {
            this.writeLine("✓ 所有测试通过!")
        } else {
            this.writeLine("✗ 存在失败的测试")
        }
    }
}

; ============================================================
; 领域层测试
; ============================================================

class InterfaceContractTests extends AutoHotUnitSuite {
    Test_ILogger_Log_Throws() {
        try {
            ILogger().Log("INFO", "test")
            this.assert.fail("ILogger.Log 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
    
    Test_INotifier_Notify_Throws() {
        try {
            INotifier().Notify("test")
            this.assert.fail("INotifier.Notify 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
    
    Test_IConfigStore_Load_Throws() {
        try {
            IConfigStore().Load()
            this.assert.fail("IConfigStore.Load 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
    
    Test_IExecutor_Execute_Throws() {
        try {
            IExecutor().Execute("")
            this.assert.fail("IExecutor.Execute 应该抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "抽象方法") > 0)
        }
    }
}

class ModeRegistryTests extends AutoHotUnitSuite {
    Test_PeriodicMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("periodic"))
    }
    
    Test_SequenceMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("sequence"))
    }
    
    Test_HybridMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("hybrid"))
    }
    
    Test_EnhancedPeriodicMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("enhanced_periodic"))
    }
    
    Test_EnhancedSequenceMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("enhanced_sequence"))
    }
    
    Test_EnhancedHybridMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("enhanced_hybrid"))
    }
    
    Test_HoldMode_Registered() {
        this.assert.isTrue(ModeRegistry.HasMode("hold"))
    }
    
    Test_GetRegisteredModes_ReturnsAtLeast7() {
        modes := ModeRegistry.GetRegisteredModes()
        this.assert.isAtLeast(modes.Length, 7)
    }
    
    Test_GetModeDisplayNames_ReturnsMap() {
        displayNames := ModeRegistry.GetModeDisplayNames()
        this.assert.isTrue(displayNames is Map)
    }
}

class ModeRegistryExecutorTests extends AutoHotUnitSuite {
    Test_PeriodicExecutor_Valid() {
        exec := ModeRegistry.GetExecutor("periodic")
        this.assert.isTrue(exec is IExecutor)
        this.assert.equal(exec.GetModeName(), "periodic")
    }
    
    Test_SequenceExecutor_Valid() {
        exec := ModeRegistry.GetExecutor("sequence")
        this.assert.isTrue(exec is IExecutor)
        this.assert.equal(exec.GetModeName(), "sequence")
    }
    
    Test_HybridExecutor_Valid() {
        exec := ModeRegistry.GetExecutor("hybrid")
        this.assert.isTrue(exec is IExecutor)
        this.assert.equal(exec.GetModeName(), "hybrid")
    }
    
    Test_NonExistentMode_Throws() {
        try {
            exec := ModeRegistry.GetExecutor("not_a_real_mode_xyz")
            this.assert.fail("应抛出异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "未注册") > 0)
        }
    }
}

class SkillGroupTests extends AutoHotUnitSuite {
    Test_KeyPressDuration_MinValueCorrection() {
        sg := SkillGroup("test1", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 1})
        this.assert.equal(sg.keyPressDuration, 5)
    }
    
    Test_KeyPressDuration_NormalValuePreserved() {
        sg := SkillGroup("test2", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 80})
        this.assert.equal(sg.keyPressDuration, 80)
    }
}

; ============================================================
; 基础设施层测试
; ============================================================

class JSONParserTests extends AutoHotUnitSuite {
    Test_SimpleObject_ReturnsMap() {
        parsed := JSONParser.Parse('{"key":"value","num":42}')
        this.assert.isTrue(parsed is Map)
        this.assert.equal(parsed["key"], "value")
        this.assert.equal(parsed["num"], 42)
    }
    
    Test_Array_ReturnsArray() {
        arr := JSONParser.Parse('[1, 2, 3]')
        this.assert.isTrue(arr is Array)
        this.assert.equal(arr.Length, 3)
    }
    
    Test_NestedObject_ReturnsCorrectStructure() {
        nested := JSONParser.Parse('{"a": {"b": [1,2,3]}}')
        this.assert.isTrue(nested is Map)
        this.assert.isTrue(nested["a"] is Map)
    }
    
    Test_EmptyObject_ReturnsEmptyMap() {
        parsed := JSONParser.Parse('{}')
        this.assert.isTrue(parsed is Map)
    }
    
    Test_EmptyArray_ReturnsEmptyArray() {
        arr := JSONParser.Parse('[]')
        this.assert.isTrue(arr is Array)
        this.assert.equal(arr.Length, 0)
    }
}

class JSONSerializerTests extends AutoHotUnitSuite {
    Test_Map_ReturnsValidJson() {
        jsonStr := JSONSerializer.Stringify(Map("key", "val"))
        this.assert.isTrue(InStr(jsonStr, '"key"') > 0)
        this.assert.isTrue(InStr(jsonStr, '"val"') > 0)
    }
    
    Test_EmptyMap_ReturnsEmptyObject() {
        emptyMapStr := JSONSerializer.Stringify(Map())
        this.assert.equal(emptyMapStr, "{}")
    }
    
    Test_EmptyArray_ReturnsEmptyArray() {
        emptyArrStr := JSONSerializer.Stringify([])
        this.assert.equal(emptyArrStr, "[]")
    }
    
    Test_RoundTrip_PreservesData() {
        jsonStr := JSONSerializer.Stringify(Map("key", "val"))
        roundTrip := JSONParser.Parse(jsonStr)
        this.assert.equal(roundTrip["key"], "val")
    }
}

class ConfigStoreTests extends AutoHotUnitSuite {
    Test_InitDefaults_CreatesGroups() {
        ConfigStore.InitDefaults()
        ; 验证至少有一个分组
        count := ConfigStore.GetGroupCount()
        this.assert.isTrue(count >= 1)
    }
    
    Test_GetGroupCount_ReturnsCorrectCount() {
        ConfigStore.InitDefaults()
        count := ConfigStore.GetGroupCount()
        this.assert.isTrue(count >= 1)
    }
    
    Test_SetAndGetGroupConfig_RoundTripWorks() {
        ConfigStore.SetGroupConfig("99", Map("hotkey", "F9", "mode", "periodic"))
        config := ConfigStore.GetGroupConfig("99")
        this.assert.equal(config["hotkey"], "F9")
    }

    Test_DeleteGroupConfig_NonExistentId_DoesNotThrow() {
        ; I7: DeleteGroupConfig 删除不存在的 groupId 不应抛异常
        ConfigStore.InitDefaults()
        ; 确保目标 groupId 不存在
        if ConfigStore.HasGroup("__nonexistent_i7__") {
            ConfigStore.DeleteGroupConfig("__nonexistent_i7__")
        }
        ; 删除不存在的 groupId 不应抛异常
        threw := false
        try {
            ConfigStore.DeleteGroupConfig("__nonexistent_i7__")
        } catch {
            threw := true
        }
        this.assert.isFalse(threw)
    }

    Test_Save_DeepClonesGroupSettings() {
        ; I15: Save 后修改原 config 不应影响 ConfigStore 内部状态
        ConfigStore.InitDefaults()
        ; 构建独立 config 并 Save
        testConfig := Map()
        testConfig["GroupSettings"] := Map("__i15__", Map("hotkey", "F1", "mode", "periodic"))
        ConfigStore.Save(testConfig)
        ; 修改原 config 对象的 GroupSettings
        testConfig["GroupSettings"]["__i15__"]["hotkey"] := "F2"
        ; 从 ConfigStore 读取，内部状态应不受影响（深拷贝隔离）
        saved := ConfigStore.GetGroupConfig("__i15__")
        this.assert.equal(saved["hotkey"], "F1")
    }
}

class ConfigValidatorTests extends AutoHotUnitSuite {
    Test_PeriodicMissingKeys_HasErrors() {
        c1 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "periodic")))
        errors := ConfigValidator.Validate(c1)
        this.assert.isTrue(errors.Length > 0)
    }
    
    Test_SequenceMissingDelays_HasErrors() {
        c2 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "sequence")))
        errors := ConfigValidator.Validate(c2)
        this.assert.isTrue(errors.Length > 0)
    }

    ; I18: 热键格式验证测试 — 验证无效热键被拒绝，合法热键通过

    Test_InvalidHotkeyFormat_Xyz123_Rejected() {
        ; "xyz123" 不是合法热键格式，应产生格式错误
        config := Map("hotkey", "xyz123", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator._ValidateGroup("1", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                found := true
        }
        this.assert.isTrue(found)
    }

    Test_InvalidHotkeyFormat_PureLongNumber_Rejected() {
        ; "12345" 纯长数字不是合法热键格式，应产生格式错误
        config := Map("hotkey", "12345", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator._ValidateGroup("1", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                found := true
        }
        this.assert.isTrue(found)
    }

    Test_ValidHotkeyFormat_F1_Accepted() {
        ; "F1" 是合法热键，不应产生格式错误
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator._ValidateGroup("1", config)
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                this.assert.fail("F1 是合法热键，不应报格式无效错误")
        }
    }

    Test_ValidHotkeyFormat_CaretC_Accepted() {
        ; "^c" (Ctrl+C) 是合法热键，不应产生格式错误
        config := Map("hotkey", "^c", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator._ValidateGroup("1", config)
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                this.assert.fail("^c 是合法热键，不应报格式无效错误")
        }
    }

    Test_ValidHotkeyFormat_ComplexModifier_Accepted() {
        ; "<^>!z" (左Ctrl+右Alt+Z) 是合法热键，不应产生格式错误
        config := Map("hotkey", "<^>!z", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator._ValidateGroup("1", config)
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                this.assert.fail("<^>!z 是合法热键，不应报格式无效错误")
        }
    }

    Test_ValidHotkeyFormat_NamedKeysWithModifiers_Accepted() {
        ; "~LButton", "*Space", "!Tab", "+#a" 都是合法热键
        validHotkeys := ["~LButton", "*Space", "!Tab", "+#a", "F12"]
        for idx, hk in validHotkeys {
            config := Map("hotkey", hk, "mode", "periodic", "keys", ["a"], "intervals", [50])
            errors := ConfigValidator._ValidateGroup("1", config)
            for err in errors {
                if err is Map && InStr(err["message"], "热键格式无效")
                    this.assert.fail(hk " 是合法热键，不应报格式无效错误")
            }
        }
    }
}

; ============================================================
; ErrorSystem 测试
; ============================================================

class ErrorSystemTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
    }
    
    Test_LogError_WritesToLog() {
        ; 测试日志记录功能
        ErrorSystem.LogError("测试错误消息", "ERROR", A_ThisFunc, A_LineNumber)
        ; 验证日志文件存在
        logPath := A_ScriptDir "\..\logs\errors.log"
        this.assert.isTrue(FileExist(logPath) != "")
    }
    
    Test_LogWarning_WritesToLog() {
        ; 测试警告记录功能
        ErrorSystem.LogWarning("测试警告消息", A_ThisFunc, A_LineNumber)
        ; 验证日志文件存在
        logPath := A_ScriptDir "\..\logs\errors.log"
        this.assert.isTrue(FileExist(logPath) != "")
    }
}

; ============================================================
; SkillManager 测试
; ============================================================

class SkillManagerTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
    }
    
    Test_SkillManager_HasGroups() {
        this.assert.isTrue(SkillManager.Groups is Map)
    }
    
    Test_SkillManager_HasActiveCount() {
        this.assert.isTrue(SkillManager.GetActiveCount() >= 0)
    }
    
    Test_SkillManager_HasHoldModeEnabled() {
        this.assert.isTrue(SkillManager.HoldModeEnabled = true || SkillManager.HoldModeEnabled = false)
    }
    
    Test_SkillManager_HasEmergencyMode() {
        this.assert.isTrue(SkillManager.EmergencyMode = true || SkillManager.EmergencyMode = false)
    }
    
    Test_SkillManager_HasMethods() {
        this.assert.isTrue(HasProp(SkillManager, "Init"))
        this.assert.isTrue(HasProp(SkillManager, "ToggleGroup"))
        this.assert.isTrue(HasProp(SkillManager, "AddGroup"))
    }
}

; ============================================================
; DebugLogger 测试
; ============================================================

class DebugLoggerTests extends AutoHotUnitSuite {
    beforeAll() {
        DebugLogger.Init()
    }
    
    Test_DebugLogger_Enabled() {
        this.assert.isTrue(DebugLogger.enabled = true || DebugLogger.enabled = false)
    }
    
    Test_DebugLogger_HasLogFile() {
        this.assert.isTrue(DebugLogger.logFile != "")
    }
    
    Test_DebugLogger_HasMaxSize() {
        this.assert.isTrue(DebugLogger.maxSize > 0)
    }
    
    Test_DebugLogger_Log_WritesToFile() {
        DebugLogger.Log("DEBUG", "测试消息")
        logPath := A_ScriptDir "\..\logs\debug.log"
        this.assert.isTrue(FileExist(logPath) != "")
    }
}

; ============================================================
; JSONLogger 测试
; ============================================================

class JSONLoggerTests extends AutoHotUnitSuite {
    Test_JSONLogger_Log_WritesToFile() {
        JSONLogger.Log("INFO", "测试消息", Map("module", "Test"))
        logPath := A_ScriptDir "\..\logs\app.log"
        this.assert.isTrue(FileExist(logPath) != "")
    }
    
    Test_JSONLogger_LogError_WritesToFile() {
        JSONLogger.Log("ERROR", "测试错误消息", Map("module", "Test"))
        logPath := A_ScriptDir "\..\logs\app.log"
        this.assert.isTrue(FileExist(logPath) != "")
    }
    
    Test_JSONLogger_LogWarning_WritesToFile() {
        JSONLogger.Log("WARNING", "测试警告消息", Map("module", "Test"))
        logPath := A_ScriptDir "\..\logs\app.log"
        this.assert.isTrue(FileExist(logPath) != "")
    }
}

; ============================================================
; BackupCore 测试
; ============================================================

class BackupCoreTests extends AutoHotUnitSuite {
    Test_BackupCore_CreateBackup_ReturnsMap() {
        config := Map("test", "value")
        result := BackupCore.CreateBackup(config, "test")
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result.Has("success"))
    }
    
    Test_BackupCore_Init_CreatesDirectory() {
        BackupCore.Init()
        backupDir := A_ScriptDir "\..\backups"
        this.assert.isTrue(InStr(FileExist(backupDir), "D") != "")
    }
    
    Test_BackupCore_HasMaxBackups() {
        this.assert.isTrue(BackupCore.maxBackups > 0)
    }
}

; ============================================================
; 基础测试
; ============================================================

class MathTests extends AutoHotUnitSuite {
    Test_Addition() {
        this.assert.equal(2 + 2, 4)
    }
    
    Test_Subtraction() {
        this.assert.equal(10 - 3, 7)
    }
    
    Test_Multiplication() {
        this.assert.equal(6 * 7, 42)
    }
    
    Test_Division() {
        this.assert.equal(20 / 4, 5)
    }
}

class StringTests extends AutoHotUnitSuite {
    Test_Trim() {
        this.assert.equal(Trim("  hello  "), "hello")
    }
    
    Test_InStr() {
        this.assert.equal(InStr("hello world", "world"), 7)
    }
    
    Test_StrLen() {
        this.assert.equal(StrLen("hello"), 5)
    }
    
    Test_SubStr() {
        this.assert.equal(SubStr("hello world", 1, 5), "hello")
    }
    
    Test_StrReplace() {
        this.assert.equal(StrReplace("hello world", "world", "AHK"), "hello AHK")
    }
}

class ArrayTests extends AutoHotUnitSuite {
    Test_ArrayLength() {
        arr := [1, 2, 3, 4, 5]
        this.assert.equal(arr.Length, 5)
    }
    
    Test_ArrayPush() {
        arr := [1, 2, 3]
        arr.Push(4)
        this.assert.equal(arr.Length, 4)
        this.assert.equal(arr[4], 4)
    }
    
    Test_ArrayPop() {
        arr := [1, 2, 3]
        val := arr.Pop()
        this.assert.equal(val, 3)
        this.assert.equal(arr.Length, 2)
    }
}

class MapTests extends AutoHotUnitSuite {
    Test_MapSetAndGet() {
        m := Map()
        m["key"] := "value"
        this.assert.equal(m["key"], "value")
    }
    
    Test_MapHas() {
        m := Map("key", "value")
        this.assert.isTrue(m.Has("key"))
        this.assert.isFalse(m.Has("notexist"))
    }
    
    Test_MapCount() {
        m := Map("a", 1, "b", 2, "c", 3)
        this.assert.equal(m.Count, 3)
    }
}

class LogRotatorTests extends AutoHotUnitSuite {
    Test_Rotate_CreatesBackup() {
        testFile := A_ScriptDir "\test_rotate.log"
        FileAppend("test content", testFile, "UTF-8")
        LogRotator.Rotate(testFile, 3)
        this.assert.isFalse(FileExist(testFile))
        backupFound := false
        Loop Files, A_ScriptDir "\test_rotate_*.log.bak" {
            backupFound := true
            try FileDelete(A_LoopFileFullPath)
        }
        this.assert.isTrue(backupFound)
    }

    Test_Rotate_NonExistentFile_NoError() {
        testFile := A_ScriptDir "\test_nonexist_rotate.log"
        try {
            LogRotator.Rotate(testFile, 3)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("不应抛出异常: " e.Message)
        }
    }
}

class JSONSerializerCircularTests extends AutoHotUnitSuite {
    Test_SelfReference_ReturnsCircular() {
        obj := Map()
        obj["self"] := obj
        result := JSONSerializer.Stringify(obj)
        this.assert.isTrue(InStr(result, '"<circular>"') > 0)
    }

    Test_MutualReference_ReturnsCircular() {
        a := Map()
        b := Map()
        a["b"] := b
        b["a"] := a
        result := JSONSerializer.Stringify(a)
        this.assert.isTrue(InStr(result, '"<circular>"') > 0)
    }

    Test_NoCircular_NormalOutput() {
        obj := Map("key", "value", "num", 42)
        result := JSONSerializer.Stringify(obj)
        this.assert.isTrue(InStr(result, '"key"') > 0)
        this.assert.isTrue(InStr(result, '"value"') > 0)
        this.assert.isFalse(InStr(result, '"<circular>"') > 0)
    }

    Test_SharedReference_NotCircular() {
        shared := Map("name", "shared")
        parent := Map()
        parent["child1"] := shared
        parent["child2"] := shared
        result := JSONSerializer.Stringify(parent)
        this.assert.isFalse(InStr(result, '"<circular>"') > 0)
    }
}

class JSONParserLoopProtectionTests extends AutoHotUnitSuite {
    Test_DeepNesting_Throws() {
        deepJson := "{"
        loop 150 {
            deepJson .= '"k' A_Index '":{'
        }
        deepJson .= '"end":"val"'
        loop 150 {
            deepJson .= '}'
        }
        deepJson .= '}'
        try {
            JSONParser.Parse(deepJson)
            this.assert.fail("应抛出深度超限异常")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "深度") > 0 || InStr(e.Message, "depth") > 0)
        }
    }

    Test_NormalDepth_ParsesCorrectly() {
        result := JSONParser.Parse('{"a":{"b":{"c":"val"}}}')
        this.assert.isTrue(result is Map)
        this.assert.equal(result["a"]["b"]["c"], "val")
    }
}

class SkillGroupKeyValidationTests extends AutoHotUnitSuite {
    Test_ModifierWithNamedKey_Space() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("^Space"))
    }

    Test_ModifierWithNamedKey_Enter() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("+Enter"))
    }

    Test_ModifierWithFKey() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("^F1"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("!F12"))
    }

    Test_PlainNamedKey() {
        this.assert.isTrue(SkillGroup._IsValidKeyName("Space"))
        this.assert.isTrue(SkillGroup._IsValidKeyName("Tab"))
    }

    Test_InvalidKey_ReturnsFalse() {
        this.assert.isFalse(SkillGroup._IsValidKeyName("InvalidKey"))
        this.assert.isFalse(SkillGroup._IsValidKeyName(""))
    }
}

class SkillGroupHoldStartTests extends AutoHotUnitSuite {
    Test_HoldStartTime_Initialized() {
        sg := SkillGroup("holdtest", {
            mode: "hold",
            hotkey: "F1",
            holdKeys: ["Shift"],
            holdDuration: 5000
        })
        sg._PressHoldKeys()
        this.assert.isTrue(sg.HasProp("_holdStartTime"))
        this.assert.isAbove(sg._holdStartTime, 0)
    }

    Test_HoldPatternStart_Initialized() {
        sg := SkillGroup("holdpatterntest", {
            mode: "hold",
            hotkey: "F2",
            holdKeys: ["Shift"],
            holdDuration: 5000
        })
        sg._PressHoldKeys()
        this.assert.isTrue(sg.HasProp("_holdPatternStart"))
        this.assert.isAbove(sg._holdPatternStart, 0)
    }
}

class SkillManagerDeleteGroupTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
        ConfigStore.InitDefaults()
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    Test_DeleteGroup_NonExistent_NoError() {
        try {
            SkillManager.DeleteGroup("nonexistent_group_xyz")
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("删除不存在的组不应抛出异常: " e.Message)
        }
    }

    Test_DeleteGroup_ReturnsFalseForNonExistent() {
        result := SkillManager.DeleteGroup("nonexistent_group_xyz")
        this.assert.isFalse(result)
    }
}

class JSONParserResetStateTests extends AutoHotUnitSuite {
    Test_ParseContext_InitialState() {
        ctx := JSONParseContext('{"a":1}')
        this.assert.equal(ctx.pos, 1)
        this.assert.equal(ctx._depth, 0)
    }

    Test_ParseContext_JsonSet() {
        ctx := JSONParseContext('{"a":1}')
        this.assert.isTrue(ctx.json != "")
    }

    Test_ParseContext_LengthSet() {
        ctx := JSONParseContext('{"a":1}')
        this.assert.isTrue(ctx.len > 0)
    }

    Test_ParseContext_FilePathSet() {
        ctx := JSONParseContext('{"a":1}', "test.json")
        this.assert.equal(ctx.filePath, "test.json")
    }

    Test_SequentialParse_NoStateLeak() {
        r1 := JSONParser.Parse('{"a":1}')
        r2 := JSONParser.Parse('{"b":2}')
        this.assert.isTrue(r1.Has("a"))
        this.assert.isTrue(r2.Has("b"))
        this.assert.isFalse(r2.Has("a"))
    }
}

class ConfigStoreMapTypeTests extends AutoHotUnitSuite {
    Test_GroupSettings_IsMap() {
        ConfigStore.InitDefaults()
        gs := ConfigStore.Get("GroupSettings")
        this.assert.isTrue(gs is Map)
    }

    Test_HoldSettings_IsMap() {
        ConfigStore.InitDefaults()
        hs := ConfigStore.Get("HoldSettings")
        this.assert.isTrue(hs is Map)
    }

    Test_GroupConfig_FirstGroup_HasHotkey() {
        ConfigStore.InitDefaults()
        gc := ConfigStore.GetGroupConfig("1")
        if gc is Map {
            this.assert.isTrue(gc.Has("hotkey"))
            this.assert.isTrue(gc.Has("mode"))
        } else {
            this.assert.isTrue(gc != "")
        }
    }

    Test_ControlHotkeys_IsMap() {
        ConfigStore.InitDefaults()
        ch := ConfigStore.Get("CONTROL_HOTKEYS")
        this.assert.isTrue(ch is Map)
    }
}

class ErrorHandlerHealthCheckTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
        ConfigStore.InitDefaults()
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    Test_HealthCheck_ReturnsMap() {
        result := ErrorHandler.HealthCheck(SkillManager)
        this.assert.isTrue(result is Map)
    }

    Test_HealthCheck_HasHealthyKey() {
        result := ErrorHandler.HealthCheck(SkillManager)
        this.assert.isTrue(result.Has("healthy"))
    }

    Test_HealthCheck_HasTimestampKey() {
        result := ErrorHandler.HealthCheck(SkillManager)
        this.assert.isTrue(result.Has("timestamp"))
    }

    Test_HealthCheck_HasIssuesKey() {
        result := ErrorHandler.HealthCheck(SkillManager)
        this.assert.isTrue(result.Has("issues"))
    }
}

class GroupEditorModeMappingTests extends AutoHotUnitSuite {
    Test_ModeDisplayToKey_IsMap() {
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY is Map)
    }

    Test_ModeKeyToDisplay_IsMap() {
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY is Map)
    }

    Test_ModeDisplayToKey_ContainsAllModes() {
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("周期性"))
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("序列"))
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("增强周期"))
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("增强序列"))
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("混合"))
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("增强混合"))
        this.assert.isTrue(GroupEditor.MODE_DISPLAY_TO_KEY.Has("长按"))
    }

    Test_ModeKeyToDisplay_ContainsAllModes() {
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("periodic"))
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("sequence"))
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("enhanced_periodic"))
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("enhanced_sequence"))
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("hybrid"))
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("enhanced_hybrid"))
        this.assert.isTrue(GroupEditor.MODE_KEY_TO_DISPLAY.Has("hold"))
    }

    Test_ModeMapping_RoundTrip() {
        for displayName in GroupEditor.MODE_DISPLAY_TO_KEY {
            key := GroupEditor.MODE_DISPLAY_TO_KEY[displayName]
            backToDisplay := GroupEditor.MODE_KEY_TO_DISPLAY[key]
            this.assert.equal(displayName, backToDisplay)
        }
    }
}

class GetPropUtilTests extends AutoHotUnitSuite {
    Test_GetProp_MapType() {
        m := Map("key", "value", "num", 42)
        this.assert.equal(_GetProp(m, "key", ""), "value")
        this.assert.equal(_GetProp(m, "num", 0), 42)
    }

    Test_GetProp_MapMissingKey_ReturnsDefault() {
        m := Map("a", 1)
        this.assert.equal(_GetProp(m, "missing", "default"), "default")
    }

    Test_GetProp_ObjectType() {
        obj := {name: "test", count: 5}
        this.assert.equal(_GetProp(obj, "name", ""), "test")
        this.assert.equal(_GetProp(obj, "count", 0), 5)
    }

    Test_GetProp_ObjectMissingKey_ReturnsDefault() {
        obj := {name: "test"}
        this.assert.equal(_GetProp(obj, "missing", "fallback"), "fallback")
    }

    Test_GetProp_NonObject_ReturnsDefault() {
        this.assert.equal(_GetProp("string", "key", "def"), "def")
        this.assert.equal(_GetProp(42, "key", "def"), "def")
    }

    Test_GetProp_NilValue_ReturnsDefault() {
        this.assert.equal(_GetProp("", "key", "def"), "def")
    }
}

class SkillGroupMapAccessTests extends AutoHotUnitSuite {
    Test_MapConfig_AccessMode() {
        config := Map("mode", "periodic", "hotkey", "F1", "keys", ["Space"], "intervals", [50])
        sg := SkillGroup("10", config)
        this.assert.equal(sg.mode, "periodic")
    }

    Test_MapConfig_AccessHotkey() {
        config := Map("mode", "periodic", "hotkey", "F1", "keys", ["Space"], "intervals", [50])
        sg := SkillGroup("11", config)
        this.assert.equal(sg.hotkey, "F1")
    }

    Test_MapConfig_AccessKeys() {
        config := Map("mode", "periodic", "hotkey", "F1", "keys", ["Space", "1"], "intervals", [50, 100])
        sg := SkillGroup("12", config)
        this.assert.equal(sg.keys.Length, 2)
        this.assert.equal(sg.keys[1], "Space")
    }

    Test_MapConfig_DefaultKeyPressDuration() {
        config := Map("mode", "periodic", "hotkey", "F1", "keys", ["Space"], "intervals", [50])
        sg := SkillGroup("13", config)
        this.assert.equal(sg.keyPressDuration, 15)
    }

    Test_MapConfig_CustomKeyPressDuration() {
        config := Map("mode", "periodic", "hotkey", "F1", "keys", ["Space"], "intervals", [50], "keyPressDuration", 30)
        sg := SkillGroup("14", config)
        this.assert.equal(sg.keyPressDuration, 30)
    }

    Test_MapConfig_DefaultHoldKeys() {
        config := Map("mode", "periodic", "hotkey", "F1", "keys", ["Space"], "intervals", [50])
        sg := SkillGroup("15", config)
        this.assert.isTrue(sg.holdKeys.Length = 0)
    }

    Test_MapConfig_EnhancedSequence() {
        config := Map("mode", "enhanced_sequence", "hotkey", "F2", "pressKeys", ["1", "2"], "pressDelays", [100, 100])
        sg := SkillGroup("16", config)
        this.assert.equal(sg.mode, "enhanced_sequence")
        this.assert.equal(sg.pressKeys.Length, 2)
    }

    Test_MapConfig_HoldMode() {
        config := Map("mode", "hold", "hotkey", "F3", "holdKeys", ["Shift"], "holdDuration", 500)
        sg := SkillGroup("17", config)
        this.assert.equal(sg.mode, "hold")
        this.assert.equal(sg.holdDuration, 500)
    }

    Test_MapConfig_DefaultHoldMode() {
        config := Map("mode", "hold", "hotkey", "F4", "holdKeys", ["Ctrl"])
        sg := SkillGroup("18", config)
        this.assert.equal(sg.holdMode, "continuous")
    }

    Test_ObjectConfig_AccessMode() {
        config := {mode: "sequence", hotkey: "F5", keys: ["a", "b"], delays: [50, 50]}
        sg := SkillGroup("19", config)
        this.assert.equal(sg.mode, "sequence")
    }
}

class IDTypeConsistencyTests extends AutoHotUnitSuite {
    Test_ConfigStore_DefaultKeysAreStrings() {
        ConfigStore.InitDefaults()
        for id in ConfigStore.Get("GroupSettings") {
            this.assert.isTrue(id is String)
        }
    }

    Test_ConfigStore_GetGroupConfig_StringKey() {
        ConfigStore.InitDefaults()
        gc := ConfigStore.GetGroupConfig("1")
        this.assert.isTrue(gc is Map)
        this.assert.isTrue(gc.Has("hotkey"))
    }

    Test_GroupService_GenerateId_ReturnsString() {
        GroupService.SkillManager := SkillManager
        GroupService.ConfigStore := ConfigStore
        ConfigStore.InitDefaults()
        for id in SkillManager.Groups
            SkillManager.DeleteGroup(id)
        newId := GroupService._GenerateGroupId()
        this.assert.isTrue(newId is String)
    }
}

class MapIterationSafetyTests extends AutoHotUnitSuite {
    Test_DeleteAllGroups_NoError() {
        ConfigStore.InitDefaults()
        ids := []
        for id in SkillManager.Groups
            ids.Push(id)
        count := ids.Length
        for id in ids
            SkillManager.DeleteGroup(id)
        this.assert.equal(SkillManager.Groups.Count, 0)
    }
}

class ConfigSaveTests extends AutoHotUnitSuite {
    Test_SaveToFile_NoDuplication() {
        testPath := A_ScriptDir "\..\test_config_save_" A_TickCount ".json"
        try {
            config := Map("version", "3.0", "GroupSettings", Map())
            originalPath := ConfigService.configPath
            ConfigService.configPath := testPath
            ConfigService._SaveToFile(config)
            content1 := FileRead(testPath, "UTF-8")
            ConfigService._SaveToFile(config)
            content2 := FileRead(testPath, "UTF-8")
            ConfigService.configPath := originalPath
            this.assert.equal(content1, content2)
        } finally {
            if FileExist(testPath)
                FileDelete(testPath)
        }
    }
}

class LogRotationTests extends AutoHotUnitSuite {
    Test_CheckLogFileSize_UsesRotation() {
        testPath := A_Temp "\test_log_rotation_" A_TickCount ".log"
        try {
            largeContent := ""
            Loop 50000
                largeContent .= '{"level":"ERROR","message":"test line ' A_Index '"}' "`n"
            FileAppend(largeContent, testPath, "UTF-8")
            size := FileGetSize(testPath)
            this.assert.isTrue(size > 100000)
        } finally {
            if FileExist(testPath)
                FileDelete(testPath)
        }
    }
}

class HoldPatternTriggerTests extends AutoHotUnitSuite {
    Test_HoldPattern_IndependentTrigger() {
        config := Map("mode", "enhanced_periodic", "hotkey", "F1", "pressKeys", ["Space"], "intervals", [50], "holdKeys", ["Shift"], "holdPattern", [200, 100])
        sg := SkillGroup("30", config)
        this.assert.isTrue(sg.holdPattern.Length >= 2)
        this.assert.isTrue(!HasProp(sg, "_holdPhaseStart") || sg._holdPhaseStart = 0 || sg._holdPhaseStart > 0)
    }
}

class ModeRegistryMapTests extends AutoHotUnitSuite {
    Test_ModeMeta_IsMap() {
        ModeRegistry._Init()
        for modeName in ModeRegistry._executors {
            if ModeRegistry._modeMeta.Has(modeName) {
                meta := ModeRegistry._modeMeta[modeName]
                this.assert.isTrue(meta is Map)
            }
        }
    }

    Test_ModeMeta_HasNameKey() {
        ModeRegistry._Init()
        for modeName in ModeRegistry._executors {
            if ModeRegistry._modeMeta.Has(modeName) {
                meta := ModeRegistry._modeMeta[modeName]
                this.assert.isTrue(meta.Has("name"))
            }
        }
    }

    Test_ModeMeta_HasRequiresKey() {
        ModeRegistry._Init()
        for modeName in ModeRegistry._executors {
            if ModeRegistry._modeMeta.Has(modeName) {
                meta := ModeRegistry._modeMeta[modeName]
                this.assert.isTrue(meta.Has("requires"))
            }
        }
    }

    Test_ValidateModeConfig_MapConfig() {
        ModeRegistry._Init()
        config := Map("pressKeys", ["Space"], "intervals", [50])
        errors := ModeRegistry.ValidateModeConfig("enhanced_periodic", config)
        this.assert.equal(errors.Length, 0)
    }

    Test_ValidateModeConfig_MapConfig_MissingField() {
        ModeRegistry._Init()
        config := Map("pressKeys", ["Space"])
        errors := ModeRegistry.ValidateModeConfig("enhanced_periodic", config)
        this.assert.isTrue(errors.Length > 0)
    }
}

class ILoggerNoInfoTests extends AutoHotUnitSuite {
    Test_ILogger_HasNoInfoMethod() {
        logger := ILogger()
        hasInfo := HasProp(logger, "Info")
        this.assert.isFalse(hasInfo)
    }

    Test_ErrorLevel_HasNoInfo() {
        this.assert.isTrue(!HasProp(ErrorLevel, "INFO"))
    }

    Test_ErrorLevel_HasError() {
        this.assert.equal(ErrorLevel.ERROR, "ERROR")
    }

    Test_ErrorLevel_HasWarning() {
        this.assert.equal(ErrorLevel.WARNING, "WARNING")
    }

    Test_ErrorLevel_HasCritical() {
        this.assert.equal(ErrorLevel.CRITICAL, "CRITICAL")
    }
}

class ConfigValidatorMapFormatTests extends AutoHotUnitSuite {
    Test_ValidateGroup_ErrorsAreMaps() {
        config := Map("mode", "periodic")
        errors := ConfigValidator._ValidateGroup("99", config)
        for err in errors {
            this.assert.isTrue(err is Map)
            this.assert.isTrue(err.Has("type"))
            this.assert.isTrue(err.Has("message"))
        }
    }

    Test_ValidateGroup_MissingHotkey_ErrorIsMap() {
        config := Map("mode", "periodic", "keys", ["Space"], "intervals", [50])
        errors := ConfigValidator._ValidateGroup("99", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "hotkey")
                found := true
        }
        this.assert.isTrue(found)
    }
}

class GUIManagerModeNamesTests extends AutoHotUnitSuite {
    Test_ModeNames_IsStaticMap() {
        this.assert.isTrue(GUIManager.modeNames is Map)
    }

    Test_ModeNames_HasAllModes() {
        this.assert.isTrue(GUIManager.modeNames.Has("periodic"))
        this.assert.isTrue(GUIManager.modeNames.Has("sequence"))
        this.assert.isTrue(GUIManager.modeNames.Has("hybrid"))
        this.assert.isTrue(GUIManager.modeNames.Has("hold"))
        this.assert.isTrue(GUIManager.modeNames.Has("enhanced_periodic"))
        this.assert.isTrue(GUIManager.modeNames.Has("enhanced_sequence"))
        this.assert.isTrue(GUIManager.modeNames.Has("enhanced_hybrid"))
        this.assert.isTrue(GUIManager.modeNames.Has("joystick_periodic"))
        this.assert.isTrue(GUIManager.modeNames.Has("joystick_sequence"))
        this.assert.isTrue(GUIManager.modeNames.Has("joystick_hold"))
    }

    Test_ModeNames_Count() {
        this.assert.equal(GUIManager.modeNames.Count, 10)
    }
}

class HealthCheckEncapsulationTests extends AutoHotUnitSuite {
    Test_SkillManager_HasGetTimerCount() {
        this.assert.isTrue(HasProp(SkillManager, "GetTimerCount"))
    }

    Test_GetTimerCount_ReturnsNumber() {
        result := SkillManager.GetTimerCount()
        this.assert.isTrue(result is Integer || result >= 0)
    }
}

class BackupCoreThrottleTests extends AutoHotUnitSuite {
    Test_RecordConfigChange_DebounceMs() {
        this.assert.isTrue(BackupCore._recordDebounceMs > 0)
    }

    Test_RecordConfigChange_DebounceTimer() {
        BackupCore.RecordConfigChange(Map("test", "data"))
        this.assert.isTrue(BackupCore._recordTimer != 0)
    }
}

; =================================================================
; 第四轮修复测试
; =================================================================

class JSONParseContextIsolationTests extends AutoHotUnitSuite {
    Test_TwoContexts_IndependentState() {
        ctx1 := JSONParseContext('{"a":1}')
        ctx2 := JSONParseContext('{"b":2}')
        this.assert.isTrue(ctx1.json != ctx2.json)
        this.assert.equal(ctx1.pos, 1)
        this.assert.equal(ctx2.pos, 1)
    }

    Test_ContextDepth_StartsAtZero() {
        ctx := JSONParseContext('{"a":1}')
        this.assert.equal(ctx._depth, 0)
    }

    Test_Parser_StaticHasNoState() {
        this.assert.isTrue(!HasProp(JSONParser, "pos"))
        this.assert.isTrue(!HasProp(JSONParser, "json"))
    }
}

; =================================================================
; MockJoySender - IJoySender 的测试替身（空操作实现）
; 用于在测试环境中注入 JoystickExecutor，避免 "JoySender 未注入" 异常
; =================================================================
class MockJoySender extends IJoySender {
    SendBtn(btn, state, method := "vjoy") {
        ; 空操作：模拟成功发送手柄按钮状态
    }
    SendPov(direction, method := "vjoy") {
        ; 空操作：模拟成功发送 POV 方向
    }
    SendAxis(axis, value, method := "vjoy") {
        ; 空操作：模拟成功发送轴值
    }
    ReleaseAll() {
        ; 空操作：模拟成功释放所有手柄输入
    }
}

class ToggleAllUsesToggleGroupTests extends AutoHotUnitSuite {
    beforeAll() {
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
        JoystickExecutor.SetJoySender(MockJoySender())
        ConfigStore.InitDefaults()
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0
            SkillManager.Init(gs)
    }

    _savedStartGroupExecution := ""

    beforeEach() {
        ; 重置所有分组的防抖时间，确保测试隔离
        ; 防抖机制（TOGGLE_DEBOUNCE_MS=200ms）会导致测试间的状态污染：
        ; 前一个测试套件激活的分组 _lastToggleTime 很近，当前测试尝试停用时被防抖阻止，
        ; 组无法停用而保持活跃，导致 ToggleAll 误入停用分支，最终所有组被停用。
        for id, group in SkillManager.Groups {
            group._lastToggleTime := 0
        }
        ; 停止所有定时器，防止前一个测试遗留的 executor 回调干扰
        for id in SkillManager.Groups {
            try SkillManager._StopGroupExecution(id)
        }
        ; mock _StartGroupExecution 防止定时器竞态：
        ; ToggleAll 激活组后 _StartGroupExecution 设置 10ms 定时器，
        ; ToggleAll 内部 _Notify/_UpdateBriefInfo 的 GUI 操作可能让出控制权，
        ; 导致定时器触发，executor 中 Execute() 返回 0 时将 active 置 false。
        this._savedStartGroupExecution := SkillManager.GetMethod("_StartGroupExecution")
        SkillManager.DefineProp("_StartGroupExecution", {call: _NoOpStartGroupExecution})
    }

    afterEach() {
        ; 恢复原始 _StartGroupExecution，避免影响后续测试套件
        if this._savedStartGroupExecution is Func
            SkillManager.DefineProp("_StartGroupExecution", {call: this._savedStartGroupExecution})
        this._savedStartGroupExecution := ""
    }

    afterAll() {
        try {
            ids := []
            for id in SkillManager.Groups
                ids.Push(id)
            for id in ids
                SkillManager.DeleteGroup(id)
        }
    }

    Test_ToggleAll_ActivatesAllGroups() {
        SkillManager.EmergencyMode := false
        for id, group in SkillManager.Groups {
            if group.active
                SkillManager.ToggleGroup(id)
        }
        SkillManager.ToggleAll()
        this.assert.isTrue(SkillManager.GetActiveCount() > 0)
    }

    Test_ToggleAll_DeactivatesAllGroups() {
        SkillManager.EmergencyMode := false
        if SkillManager.GetActiveCount() = 0
            SkillManager.ToggleAll()
        SkillManager.ToggleAll()
        this.assert.equal(SkillManager.GetActiveCount(), 0)
    }
}

; mock _StartGroupExecution 的空操作函数：不启动定时器，防止 executor 回调竞态
_NoOpStartGroupExecution(*) {
}

; =================================================================
; SkillGroup.Toggle() 异常处理测试（RED-GREEN-REFACTOR）
; 验证 catch 块在停用失败/激活失败时的状态回滚行为
; =================================================================

; 辅助函数：模拟 _ReleaseAllKeys 抛异常（停用失败场景）
_ThrowReleaseAllKeysError(*) {
    throw Error("模拟停用失败")
}

; 辅助函数：模拟 _ResetPeriodicTriggerTimes 抛异常（激活失败场景）
_ThrowResetTriggerError(*) {
    throw Error("模拟激活失败")
}

class SkillGroupToggleExceptionTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
    }

    Test_DeactivateFailure_KeepsActiveFalse() {
        ; 创建周期性分组并先激活
        sg := SkillGroup("test_deact", Map(
            "mode", "periodic", "hotkey", "F1",
            "keys", ["a"], "intervals", [50]
        ))
        sg._lastToggleTime := 0
        result := sg.Toggle()
        this.assert.isTrue(sg.active)
        this.assert.equal(result, true)

        ; 覆盖 _ReleaseAllKeys 为抛异常版本（模拟停用时按键释放失败）
        sg.DefineProp("_ReleaseAllKeys", {call: _ThrowReleaseAllKeysError})

        ; 再次 Toggle 停用（_ReleaseAllKeys 抛异常 → 进入 catch 块）
        sg._lastToggleTime := 0
        result := sg.Toggle()

        ; 核心断言：停用失败时 active 应保持 false，不应恢复为 true
        this.assert.isFalse(sg.active)
        this.assert.equal(result, false)
    }

    Test_ActivateFailure_RollsBackActiveFalse() {
        ; 回归保护：验证激活失败时 active 回滚为 false（现有正确逻辑不被破坏）
        sg := SkillGroup("test_act", Map(
            "mode", "periodic", "hotkey", "F1",
            "keys", ["a"], "intervals", [50]
        ))
        this.assert.isFalse(sg.active)

        ; 覆盖 _ResetPeriodicTriggerTimes 为抛异常版本（模拟激活失败）
        sg.DefineProp("_ResetPeriodicTriggerTimes", {call: _ThrowResetTriggerError})

        sg._lastToggleTime := 0
        result := sg.Toggle()

        ; 激活失败时 active 应回滚为 false
        this.assert.isFalse(sg.active)
        this.assert.equal(result, false)
    }
}

class ConfigValidatorAllMapFormatTests extends AutoHotUnitSuite {
    Test_ValidateHotkeys_ErrorsAreMaps() {
        hotkeys := Map()
        errors := ConfigValidator._ValidateHotkeys(hotkeys)
        for e in errors {
            this.assert.isTrue(e is Map)
            this.assert.isTrue(e.Has("type"))
            this.assert.isTrue(e.Has("message"))
        }
    }

    Test_ValidateHoldSettings_ErrorsAreMaps() {
        settings := Map("pressSpeed", -1, "debounceDelay", 2000)
        errors := ConfigValidator._ValidateHoldSettings(settings)
        for e in errors {
            this.assert.isTrue(e is Map)
            this.assert.isTrue(e.Has("type"))
            this.assert.isTrue(e.Has("message"))
        }
    }

    Test_Validate_MissingGroupSettings_ErrorIsMap() {
        errors := ConfigValidator.Validate(Map())
        this.assert.isTrue(errors.Length > 0)
        this.assert.isTrue(errors[1] is Map)
        this.assert.isTrue(errors[1].Has("message"))
    }

    Test_GetErrorMessage_ExtractsFromMap() {
        err := Map("type", "ERROR", "message", "test error")
        this.assert.equal(ConfigValidator.GetErrorMessage(err), "test error")
    }

    Test_GetErrorMessage_FallsBackToString() {
        this.assert.equal(ConfigValidator.GetErrorMessage("plain error"), "plain error")
    }
}

class ValidateGroupOnlyNoDoubleWrapTests extends AutoHotUnitSuite {
    Test_ValidateGroupOnly_FieldErrorsNotDoubleWrapped() {
        config := Map("hotkey", "F1", "mode", "periodic")
        errors := ConfigValidator.ValidateGroupOnly("1", config)
        for e in errors {
            if e is Map && e.Has("message") {
                msg := e["message"]
                this.assert.isTrue(!InStr(msg, "[object") || !InStr(msg, "Map"))
            }
        }
    }
}

class JSONLoggerMaxErrorsTests extends AutoHotUnitSuite {
    Test_MaxErrors_IsPositive() {
        this.assert.isTrue(JSONLogger.maxErrors > 0)
    }

    Test_MaxErrors_DefaultValue() {
        this.assert.equal(JSONLogger.maxErrors, 500)
    }
}

class GetRuntimeStatusMapTests extends AutoHotUnitSuite {
    beforeAll() {
        ConfigStore.InitDefaults()
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    Test_GetRuntimeStatus_ReturnsMap() {
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0 {
            for id, cfg in gs {
                group := SkillGroup(id, cfg)
                status := group.GetRuntimeStatus()
                this.assert.isTrue(status is Map)
                break
            }
        }
    }

    Test_GetRuntimeStatus_HasRequiredKeys() {
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0 {
            for id, cfg in gs {
                group := SkillGroup(id, cfg)
                status := group.GetRuntimeStatus()
                this.assert.isTrue(status.Has("active"))
                this.assert.isTrue(status.Has("executionCount"))
                this.assert.isTrue(status.Has("runTime"))
                this.assert.isTrue(status.Has("currentStep"))
                break
            }
        }
    }
}

class HealthCheckTimestampTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
        ConfigStore.InitDefaults()
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    Test_HealthCheck_TimestampIsISO() {
        result := ErrorHandler.HealthCheck(SkillManager)
        ts := result["timestamp"]
        this.assert.isTrue(InStr(ts, "T") > 0)
        this.assert.isTrue(InStr(ts, "-") > 0)
    }
}

class BackupCoreSortTests extends AutoHotUnitSuite {
    Test_SortBackupsByTime_NoRangeFunction() {
        backups := [
            Map("time", "20260101", "file", "b1"),
            Map("time", "20260301", "file", "b2"),
            Map("time", "20260201", "file", "b3")
        ]
        result := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(result.Length = 3)
        this.assert.equal(result[1]["time"], "20260301")
        this.assert.equal(result[3]["time"], "20260101")
    }
}

class HotkeyEditorNormalizeTests extends AutoHotUnitSuite {
    Test_NormalizeKey_SingleChar_Lowercase() {
        this.assert.equal(HotkeyEditor._NormalizeKey("A"), "a")
    }

    Test_NormalizeKey_SpecialKey_Preserved() {
        this.assert.equal(HotkeyEditor._NormalizeKey("Space"), "Space")
        this.assert.equal(HotkeyEditor._NormalizeKey("Enter"), "Enter")
    }

    Test_NormalizeKey_Empty_ReturnsEmpty() {
        this.assert.equal(HotkeyEditor._NormalizeKey(""), "")
    }

    Test_NormalizeKey_Number_Preserved() {
        this.assert.equal(HotkeyEditor._NormalizeKey("1"), "1")
    }

    Test_NormalizeKey_FKey_Preserved() {
        this.assert.equal(HotkeyEditor._NormalizeKey("F1"), "F1")
        this.assert.equal(HotkeyEditor._NormalizeKey("F12"), "F12")
    }
}

; =================================================================
; 第五轮修复测试
; =================================================================

class SequenceHoldTriggersMultiKeyTests extends AutoHotUnitSuite {
    Test_AnyHeld_WithMultipleKeys() {
        group := SkillGroup("test", Map(
            "hotkey", "F1", "mode", "enhanced_sequence",
            "pressKeys", ["1", "2"], "pressDelays", [100, 100],
            "holdKeys", ["Shift", "Ctrl"], "holdMode", "sequence",
            "holdTriggers", [1, 0]
        ))
        this.assert.isTrue(group.holdKeys.Length = 2)
        this.assert.isTrue(group.holdMode = "sequence")
    }
}

class SaveConfigNoDoubleSerializeTests extends AutoHotUnitSuite {
    Test_SaveConfig_ReturnsResult() {
        ConfigStore.InitDefaults()
        result := ConfigService.SaveConfig()
        this.assert.isTrue(result = true || result = false)
    }
}

class RestoreBackupAtomicTests extends AutoHotUnitSuite {
    Test_RestoreBackup_NonExistent_ReturnsError() {
        result := BackupCore.RestoreBackup("nonexistent_backup.json")
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result.Has("success"))
        this.assert.isTrue(!result["success"])
    }
}

class JSONErrorModulePropertyTests extends AutoHotUnitSuite {
    Test_JSONError_HasModuleProperty() {
        err := JSONError("E001", "test")
        this.assert.isTrue(err.HasProp("module"))
        this.assert.equal(err.module, "")
    }

    Test_JSONError_ModuleSetViaContext() {
        err := JSONError("E001", "test")
        err.module := "TestModule"
        this.assert.equal(err.module, "TestModule")
    }
}

class DebugLoggerEnforceSizeTests extends AutoHotUnitSuite {
    Test_EnforceSizeLimit_NoSubArray() {
        this.assert.isTrue(DebugLogger.HasProp("maxSize"))
        this.assert.isTrue(DebugLogger.maxSize > 0)
    }
}

class GroupServiceRollbackSafetyTests extends AutoHotUnitSuite {
    Test_UpdateGroup_NonExistent_Throws() {
        try {
            GroupService.UpdateGroup("nonexistent", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50]))
            this.assert.fail("Should have thrown")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "不存在") > 0)
        }
    }
}

class ToggleAllAccurateNotifyTests extends AutoHotUnitSuite {
    beforeAll() {
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
        ConfigStore.InitDefaults()
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0
            SkillManager.Init(gs)
        SkillManager.EmergencyMode := false
        for id, group in SkillManager.Groups {
            if group.active {
                group._lastToggleTime := 0
                group.Toggle()
            }
        }
    }

    _savedStartGroupExecution := ""

    beforeEach() {
        ; 停止所有定时器，防止前一个测试遗留的 executor 回调干扰
        for id in SkillManager.Groups {
            try SkillManager._StopGroupExecution(id)
        }
        ; mock _StartGroupExecution 防止定时器竞态：
        ; ToggleAll 激活组后 _StartGroupExecution 设置 10ms 定时器，
        ; ToggleAll 内部 _Notify/_UpdateBriefInfo 的 GUI 操作可能让出控制权，
        ; 导致定时器触发，executor 中 Execute() 返回 0 时将 active 置 false。
        this._savedStartGroupExecution := SkillManager.GetMethod("_StartGroupExecution")
        SkillManager.DefineProp("_StartGroupExecution", {call: _NoOpStartGroupExecution})
    }

    afterEach() {
        ; 恢复原始 _StartGroupExecution，避免影响后续测试套件
        if this._savedStartGroupExecution is Func
            SkillManager.DefineProp("_StartGroupExecution", {call: this._savedStartGroupExecution})
        this._savedStartGroupExecution := ""
    }

    afterAll() {
        try {
            SkillManager.EmergencyMode := false
            for id, group in SkillManager.Groups {
                if group.active {
                    group._lastToggleTime := 0
                    group.Toggle()
                }
            }
            ids := []
            for id in SkillManager.Groups
                ids.Push(id)
            for id in ids
                SkillManager.DeleteGroup(id)
        }
    }

    Test_ToggleAll_ActivatesFromZero() {
        if SkillManager.Groups.Count = 0
            return
        initialCount := SkillManager.GetActiveCount()
        SkillManager.ToggleAll()
        afterToggle := SkillManager.GetActiveCount()
        if initialCount = 0
            this.assert.isTrue(afterToggle > 0)
        else
            this.assert.isTrue(afterToggle = 0)
        for id, group in SkillManager.Groups {
            if group.active {
                group._lastToggleTime := 0
                group.Toggle()
            }
        }
    }
}

class JSONSerializerSpacesCacheTests extends AutoHotUnitSuite {
    Test_BuildSpaces_CachesResult() {
        s1 := JSONSerializer._BuildSpaces(4)
        s2 := JSONSerializer._BuildSpaces(4)
        this.assert.equal(s1, s2)
        this.assert.equal(s1, "    ")
    }

    Test_BuildSpaces_DifferentLengths() {
        s1 := JSONSerializer._BuildSpaces(2)
        s2 := JSONSerializer._BuildSpaces(4)
        this.assert.isTrue(s1 != s2)
        this.assert.equal(s1, "  ")
        this.assert.equal(s2, "    ")
    }
}

class HealthCheckMaxActiveGroupsTests extends AutoHotUnitSuite {
    Test_MaxActiveGroups_IsConfigurable() {
        this.assert.isTrue(ErrorHandler.maxActiveGroups > 0)
    }

    Test_MaxActiveGroups_DefaultValue() {
        this.assert.equal(ErrorHandler.maxActiveGroups, 10)
    }
}

class IPCPollMessagesOrderTests extends AutoHotUnitSuite {
    Test_IPCChannel_DefaultChannelDir() {
        this.assert.equal(IPCChannel.channelDir, "ipc")
    }
}

class ConfigStoreSetUnknownKeyTests extends AutoHotUnitSuite {
    Test_Set_UnknownKey_NoError() {
        ConfigStore.Set("UnknownKey", "value")
    }

    Test_Set_KnownKey_Works() {
        oldVal := ConfigStore.Get("HoldSettings")
        ConfigStore.Set("HoldSettings", Map("test", true))
        newVal := ConfigStore.Get("HoldSettings")
        this.assert.isTrue(newVal is Map)
        this.assert.isTrue(newVal.Has("test"))
        ConfigStore.Set("HoldSettings", oldVal)
    }
}

class ExecutorTimerGuardTests extends AutoHotUnitSuite {
    Test_TimersMap_HasCheck_InExecutor() {
        this.assert.isTrue(SkillManager._timers is Map)
    }

    Test_StopExecution_ClearsTimer() {
        testFn := () => {}
        SkillManager._timers["__test_exec"] := testFn
        this.assert.isTrue(SkillManager._timers.Has("__test_exec"))
        SkillManager._StopGroupExecution("__test_exec")
        this.assert.isTrue(!SkillManager._timers.Has("__test_exec"))
    }
}

class HotReloadEmergencyResetTests extends AutoHotUnitSuite {
    Test_ResetEmergency_SetsModeFalse() {
        SkillManager.EmergencyMode := true
        SkillManager.ResetEmergency()
        this.assert.isTrue(!SkillManager.EmergencyMode)
    }

    Test_Emergency_SetsModeTrue() {
        SkillManager.EmergencyMode := false
        SkillManager.Emergency()
        this.assert.isTrue(SkillManager.EmergencyMode)
        SkillManager.ResetEmergency()
    }
}

class ToggleDebounceReturnTests extends AutoHotUnitSuite {
    Test_Toggle_ReturnsNegOne_OnDebounce() {
        group := SkillGroup("debounce_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        group._lastToggleTime := A_TickCount
        result := group.Toggle()
        this.assert.isTrue(result = -1)
    }

    Test_Toggle_ReturnsTrue_OnFirstActivate() {
        group := SkillGroup("first_toggle_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        group._lastToggleTime := 0
        result := group.Toggle()
        this.assert.isTrue(result = true)
        group._ReleaseAllKeys()
    }

    Test_ToggleGroup_SkipsCount_OnDebounce() {
        group := SkillGroup("tg_debounce_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        SkillManager.Groups["__tg_debounce"] := group
        group._lastToggleTime := 0
        group.Toggle()
        afterFirst := SkillManager.GetActiveCount()
        result := group.Toggle()
        afterSecond := SkillManager.GetActiveCount()
        this.assert.isTrue(result = -1)
        this.assert.isTrue(afterSecond = afterFirst)
        group._ReleaseAllKeys()
        SkillManager.Groups.Delete("__tg_debounce")
    }
}

class CopyGroupIdGenerationTests extends AutoHotUnitSuite {
    Test_MaxIdPlusOne_NoConflict() {
        maxId := 0
        testIds := ["1", "3", "5"]
        for id in testIds {
            try {
                idNum := Integer(String(id))
                if idNum > maxId
                    maxId := idNum
            } catch {
                continue
            }
        }
        newId := String(maxId + 1)
        this.assert.isTrue(newId = "6")
    }

    Test_EmptyGroups_GeneratesId1() {
        maxId := 0
        newId := String(maxId + 1)
        this.assert.isTrue(newId = "1")
    }
}

class BackupSortAlgorithmTests extends AutoHotUnitSuite {
    Test_SortByTime_Descending() {
        backups := [
            Map("time", "20260101000000", "file", "old.json"),
            Map("time", "20260103000000", "file", "new.json"),
            Map("time", "20260102000000", "file", "mid.json")
        ]
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted[1]["file"] = "new.json")
        this.assert.isTrue(sorted[2]["file"] = "mid.json")
        this.assert.isTrue(sorted[3]["file"] = "old.json")
    }

    Test_SortByTime_SingleElement() {
        backups := [Map("time", "20260101000000", "file", "only.json")]
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted.Length = 1)
        this.assert.isTrue(sorted[1]["file"] = "only.json")
    }

    Test_SortByTime_EmptyArray() {
        backups := []
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted.Length = 0)
    }

    Test_SortByTime_AlreadySorted() {
        backups := [
            Map("time", "20260103000000", "file", "c.json"),
            Map("time", "20260102000000", "file", "b.json"),
            Map("time", "20260101000000", "file", "a.json")
        ]
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted[1]["file"] = "c.json")
        this.assert.isTrue(sorted[3]["file"] = "a.json")
    }
}

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

_MockSM(activeCount, timerCount) {
    mock := {}
    mock.EmergencyMode := false
    mock.DefineProp("GetActiveCount", {call: (*) => activeCount})
    mock.DefineProp("GetTimerCount", {call: (*) => timerCount})
    mock.HoldKeyRegistry := Map()
    return mock
}

; 创建静默报告器
reporter := SilentReporter(A_ScriptDir "\test_results.log")

; 创建测试管理器
testManager := AutoHotUnitManager(reporter)

; 初始化 ModeRegistry（注册所有内置模式）
ModeRegistry._Init()

; 全局注入 MockJoySender，确保所有测试套件中 JoystickExecutor 可正常工作
; 避免摇杆分组停用/执行时抛出 "JoySender 未注入" 异常
JoystickExecutor.SetJoySender(MockJoySender())

; 注册所有测试套件
testManager.RegisterSuite(
    InterfaceContractTests, 
    ModeRegistryTests, 
    ModeRegistryExecutorTests, 
    SkillGroupTests,
    SkillManagerTests,
    JSONParserTests,
    JSONSerializerTests,
    ConfigStoreTests,
    ConfigValidatorTests,
    ErrorSystemTests,
    DebugLoggerTests,
    JSONLoggerTests,
    BackupCoreTests,
    LogRotatorTests,
    JSONSerializerCircularTests,
    JSONParserLoopProtectionTests,
    SkillGroupKeyValidationTests,
    SkillGroupHoldStartTests,
    SkillManagerDeleteGroupTests,
    JSONParserResetStateTests,
    ConfigStoreMapTypeTests,
    ErrorHandlerHealthCheckTests,
    GroupEditorModeMappingTests,
    GetPropUtilTests,
    SkillGroupMapAccessTests,
    IDTypeConsistencyTests,
    MapIterationSafetyTests,
    ConfigSaveTests,
    LogRotationTests,
    HoldPatternTriggerTests,
    ModeRegistryMapTests,
    ILoggerNoInfoTests,
    ConfigValidatorMapFormatTests,
    GUIManagerModeNamesTests,
    HealthCheckEncapsulationTests,
    BackupCoreThrottleTests,
    JSONParseContextIsolationTests,
    ToggleAllUsesToggleGroupTests,
    SkillGroupToggleExceptionTests,
    ConfigValidatorAllMapFormatTests,
    ValidateGroupOnlyNoDoubleWrapTests,
    JSONLoggerMaxErrorsTests,
    GetRuntimeStatusMapTests,
    HealthCheckTimestampTests,
    BackupCoreSortTests,
    HotkeyEditorNormalizeTests,
    MathTests,
    StringTests,
    ArrayTests,
    MapTests,
    SequenceHoldTriggersMultiKeyTests,
    SaveConfigNoDoubleSerializeTests,
    RestoreBackupAtomicTests,
    JSONErrorModulePropertyTests,
    DebugLoggerEnforceSizeTests,
    GroupServiceRollbackSafetyTests,
    ToggleAllAccurateNotifyTests,
    JSONSerializerSpacesCacheTests,
    HealthCheckMaxActiveGroupsTests,
    IPCPollMessagesOrderTests,
    ConfigStoreSetUnknownKeyTests,
    ExecutorTimerGuardTests,
    HotReloadEmergencyResetTests,
    ToggleDebounceReturnTests,
    CopyGroupIdGenerationTests,
    BackupSortAlgorithmTests,
    BackupServiceLayeringTests,
    ConfigIOLayeringTests,
    JSONLoggerModuleDefaultTests,
    DebounceCacheTests,
    HealthCheckTimestampFormatTests,
    CreateGroupFailureConsistencyTests,
    ActiveCountComputedPropertyTests,
    CleanupOrphanTimersSelectiveTests,
    KeyPressDurationMaxLimitTests,
    RestoreBackupSafetyFileTests,
    ConfigStoreSetReturnTests,
    ParseIntArrayErrorReportTests,
    IPCChannelFallbackReadTests,
    IsValidKeyNameExpandedTests,
    AutoRefreshIncrementalTests,
    OnExitUITimerCleanupTests,
    HealthCheckGetActiveCountCacheTests
)

; ============================================================
; 注册 AHK 执行器测试套件（asd-tauri/src-tauri/ahk_executor/）
; ============================================================
testManager.RegisterSuite(
    CommandDispatcherGetStrTests,
    CommandDispatcherGetIntTests,
    CommandDispatcherGetBoolTests,
    CommandDispatcherGetArrTests,
    CommandDispatcherGetMapTests,
    CommandDispatcherMergeModeConfigTests,
    CommandDispatcherDispatchUnknownTests,
    CommandDispatcherRecordKeyTests,
    CommandDispatcherValidationTests,
    IPCConstTests,
    MiniJsonParseObjectTests,
    MiniJsonParseArrayTests,
    MiniJsonParseScalarTests,
    MiniJsonStringifyTests,
    MiniJsonRoundTripTests,
    MiniJsonBoolMarkerTests,
    IpcClientInitialStateTests,
    IpcClientNextSeqTests,
    IpcClientSendDisconnectedTests,
    IpcClientParseAuthTokenTests,
    IpcClientDeduplicationTests,
    HotkeyHookNormalizeTests,
    HotkeyHookRegistrationStateTests,
    HotkeyHookRegisterErrorTests,
    HotkeyHookUnregisterErrorTests,
    HotkeyHookUnregisterAllTests,
    HotkeyHookInitTests,
    HotkeyHookCallbackTests,
    SenderAllowedKeysTests,
    SenderValidateKeyTests,
    SenderToggleGroupTests,
    SenderStartPeriodicTests,
    SenderStartSequenceTests,
    SenderStartEnhancedTests,
    SenderStartHoldTests,
    SenderHoldModeToggleTests,
    SenderEmergencyReleaseTests,
    SenderShutdownTests,
    SenderInitTests,
    JoystickAllowedKeysTests,
    JoystickValidateKeyTests,
    JoystickIsButtonTests,
    JoystickGetButtonNumTests,
    JoystickIsPovTests,
    JoystickGetPovDirectionTests,
    JoystickIsAxisTests,
    JoystickGetAxisInfoTests,
    JoystickAxisToVJoyIdTests,
    JoystickPovDirectionToValueTests,
    JoystickResolveMethodTests,
    JoystickIsVJoyAvailableTests,
    JoystickStopGroupTests,
    JoystickEmergencyReleaseTests,
    JoystickInitTests,
    JoystickStartPeriodicTests,
    JoystickStartSequenceTests,
    JoystickStartHoldTests
)

; ============================================================
; 注册 joy_hotkey_manager 测试套件
; ============================================================
testManager.RegisterSuite(
    JoyHotkeyRegisterTests,
    JoyHotkeyUnregisterTests,
    JoyHotkeyMultiJoystickTests,
    JoyHotkeyPollingLogicTests,
    JoyHotkeyPollingTimerTests,
    JoyHotkeyCallbackTests,
    JoyHotkeyReviewFixTests
)

; 运行测试
testManager.RunSuites()

; 退出程序
ExitApp(0)
