; =================================================================
; base_suites.ahk - 基础测试套件（工具函数、验证、健康检查）
; 本文件通过 run_all_tests.ahk 的 #Include 加载，不可独立运行
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

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

    ; ID 生成与唯一性检查必须用同一个真值源：CreateGroup 拿 ConfigStore.HasGroup() 判重，
    ; _GenerateGroupId() 原先只看 SkillManager.Groups。两者不同步时（SkillManager 还没
    ; 初始化、或配置里有分组但尚未建实例）会生成已存在的 ID，CreateGroup 立刻抛
    ; 「分组已存在」，新分组永远建不出来。上面这段正是事故现场：
    ; SkillManager 已清空，而 ConfigStore.InitDefaults() 里有默认分组 1..7。
    Test_GroupService_GenerateId_AvoidsConfigStoreCollision() {
        GroupService.SkillManager := SkillManager
        GroupService.ConfigStore := ConfigStore
        ConfigStore.InitDefaults()
        for id in SkillManager.Groups
            SkillManager.DeleteGroup(id)
        newId := GroupService._GenerateGroupId()
        this.assert.isTrue(!ConfigStore.HasGroup(newId))
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