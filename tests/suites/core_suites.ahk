; =================================================================
; core_suites.ahk - 领域层与基础设施层测试套件（含 SilentReporter）
; 本文件通过 run_all_tests.ahk 的 #Include 加载，不可独立运行
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

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

    ; G1/T3-01: ValidateGroupOnly 补热键格式校验（Create/Update 分组入口缺口）

    Test_ValidateGroupOnly_InvalidHotkey_Rejected() {
        config := Map("hotkey", "xyz123", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator.ValidateGroupOnly("1", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                found := true
        }
        this.assert.isTrue(found)
    }

    Test_ValidateGroupOnly_ValidHotkey_Accepted() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["a"], "intervals", [50])
        errors := ConfigValidator.ValidateGroupOnly("1", config)
        for err in errors {
            if err is Map && InStr(err["message"], "热键格式无效")
                this.assert.fail("F1 是合法热键，不应报格式无效错误")
        }
    }

    ; G1/T3-02: _ValidateModeFields 按键名合法性校验

    Test_ValidateModeFields_InvalidKeyName_Rejected() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["NotAKey"], "intervals", [50])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "非法按键名")
                found := true
        }
        this.assert.isTrue(found)
    }

    Test_ValidateModeFields_ValidKeyName_Accepted() {
        config := Map("hotkey", "F1", "mode", "periodic", "keys", ["Space", "1"], "intervals", [50, 50])
        errors := ConfigValidator._ValidateModeFields("1", "periodic", config)
        for err in errors {
            if err is Map && InStr(err["message"], "非法按键名")
                this.assert.fail("合法按键名不应报非法按键名错误")
        }
    }

    Test_ValidateModeFields_InvalidJoyKey_Rejected() {
        config := Map("hotkey", "F1", "mode", "joystick_periodic", "joyKeys", ["NotAJoyKey"], "intervals", [50])
        errors := ConfigValidator._ValidateModeFields("1", "joystick_periodic", config)
        found := false
        for err in errors {
            if err is Map && InStr(err["message"], "非法按键名")
                found := true
        }
        this.assert.isTrue(found)
    }

    ; G1/T3-03: _ValidateHotkeys 控制热键格式校验

    Test_ValidateHotkeys_InvalidFormat_Rejected() {
        hotkeys := Map("emergency", "garbage", "toggleAll", "^1", "showStatus", "^0", "toggleHoldMode", "^h", "releaseAllHolds", "^r")
        errors := ConfigValidator._ValidateHotkeys(hotkeys)
        found := false
        for err in errors {
            if err is Map && err.Has("type") && err["type"] = "ERROR" && InStr(err["message"], "格式无效")
                found := true
        }
        this.assert.isTrue(found)
    }

    Test_ValidateHotkeys_EmptyValue_Warning() {
        hotkeys := Map("emergency", "", "toggleAll", "^1", "showStatus", "^0", "toggleHoldMode", "^h", "releaseAllHolds", "^r")
        errors := ConfigValidator._ValidateHotkeys(hotkeys)
        found := false
        for err in errors {
            if err is Map && err.Has("type") && err["type"] = "WARNING" && InStr(err["message"], "值为空")
                found := true
        }
        this.assert.isTrue(found)
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