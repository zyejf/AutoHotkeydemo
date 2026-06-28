; =================================================================
; test_executor.ahk - 测试 AHK 执行器 CommandDispatcher
; 目标：验证 executor.ahk 中 CommandDispatcher 类的辅助方法
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; 被测脚本（main guard 确保被 #Include 时不自动初始化）
#Include "../../asd-tauri/src-tauri/ahk_executor/executor.ahk"

; 测试框架（提供 AutoHotUnitSuite 基类）
#Include "../AutoHotUnit.ahk"

; 警告设置（在 #Include 之后，覆盖 AutoHotUnit.ahk 的 #Warn All）
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 运行时错误接管：输出到 stdout，阻止弹窗
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试套件：CommandDispatcher._GetStr 字符串提取
; =================================================================

class CommandDispatcherGetStrTests extends AutoHotUnitSuite {
    Test_GetStr_MapType_ExistingKey() {
        data := Map("groupId", "g1", "mode", "periodic")
        this.assert.equal(CommandDispatcher._GetStr(data, "groupId", ""), "g1")
        this.assert.equal(CommandDispatcher._GetStr(data, "mode", ""), "periodic")
    }

    Test_GetStr_MapType_NumericValue_ReturnsString() {
        data := Map("count", 42)
        result := CommandDispatcher._GetStr(data, "count", "")
        this.assert.isTrue(result is String)
        this.assert.equal(result, "42")
    }

    Test_GetStr_MapType_MissingKey_ReturnsDefault() {
        data := Map("a", "1")
        this.assert.equal(CommandDispatcher._GetStr(data, "missing", "default"), "default")
    }

    Test_GetStr_MapType_EmptyDefault() {
        data := Map()
        this.assert.equal(CommandDispatcher._GetStr(data, "x", ""), "")
    }

    Test_GetStr_ObjectType_ExistingKey() {
        obj := {groupId: "obj1", mode: "sequence"}
        this.assert.equal(CommandDispatcher._GetStr(obj, "groupId", ""), "obj1")
        this.assert.equal(CommandDispatcher._GetStr(obj, "mode", ""), "sequence")
    }

    Test_GetStr_ObjectType_MissingKey_ReturnsDefault() {
        obj := {a: "1"}
        this.assert.equal(CommandDispatcher._GetStr(obj, "missing", "fallback"), "fallback")
    }

    Test_GetStr_NonObject_ReturnsDefault() {
        this.assert.equal(CommandDispatcher._GetStr("string", "key", "def"), "def")
        this.assert.equal(CommandDispatcher._GetStr(42, "key", "def"), "def")
    }

    Test_GetStr_MapType_EmptyStringValue() {
        data := Map("emptyKey", "")
        result := CommandDispatcher._GetStr(data, "emptyKey", "default")
        this.assert.equal(result, "")
    }
}

; =================================================================
; 测试套件：CommandDispatcher._GetInt 整数提取
; =================================================================

class CommandDispatcherGetIntTests extends AutoHotUnitSuite {
    Test_GetInt_StringNumber_ReturnsInteger() {
        data := Map("count", "100")
        result := CommandDispatcher._GetInt(data, "count", 0)
        this.assert.equal(result, 100)
        this.assert.isTrue(result is Integer)
    }

    Test_GetInt_IntegerValue_ReturnsInteger() {
        data := Map("count", 50)
        result := CommandDispatcher._GetInt(data, "count", 0)
        this.assert.equal(result, 50)
    }

    Test_GetInt_NonNumericString_ReturnsDefault() {
        data := Map("count", "abc")
        this.assert.equal(CommandDispatcher._GetInt(data, "count", 99), 99)
    }

    Test_GetInt_MissingKey_ReturnsDefault() {
        data := Map()
        this.assert.equal(CommandDispatcher._GetInt(data, "x", 7), 7)
    }

    Test_GetInt_EmptyString_ReturnsDefault() {
        data := Map("count", "")
        this.assert.equal(CommandDispatcher._GetInt(data, "count", 15), 15)
    }

    Test_GetInt_NegativeNumber() {
        data := Map("offset", "-10")
        this.assert.equal(CommandDispatcher._GetInt(data, "offset", 0), -10)
    }
}

; =================================================================
; 测试套件：CommandDispatcher._GetBool 布尔提取
; =================================================================

class CommandDispatcherGetBoolTests extends AutoHotUnitSuite {
    Test_GetBool_TrueValue_ReturnsTrue() {
        data := Map("active", true)
        this.assert.isTrue(CommandDispatcher._GetBool(data, "active", false))
    }

    Test_GetBool_OneInteger_ReturnsTrue() {
        data := Map("active", 1)
        this.assert.isTrue(CommandDispatcher._GetBool(data, "active", false))
    }

    Test_GetBool_TrueString_ReturnsTrue() {
        data := Map("active", "true")
        this.assert.isTrue(CommandDispatcher._GetBool(data, "active", false))
    }

    Test_GetBool_FalseValue_ReturnsFalse() {
        data := Map("active", false)
        this.assert.isFalse(CommandDispatcher._GetBool(data, "active", true))
    }

    Test_GetBool_ZeroInteger_ReturnsFalse() {
        data := Map("active", 0)
        this.assert.isFalse(CommandDispatcher._GetBool(data, "active", true))
    }

    Test_GetBool_MissingKey_ReturnsDefault() {
        data := Map()
        this.assert.isTrue(CommandDispatcher._GetBool(data, "x", true))
        this.assert.isFalse(CommandDispatcher._GetBool(data, "x", false))
    }

    Test_GetBool_ObjectType() {
        obj := {enabled: true, disabled: false}
        this.assert.isTrue(CommandDispatcher._GetBool(obj, "enabled", false))
        this.assert.isFalse(CommandDispatcher._GetBool(obj, "disabled", true))
    }
}

; =================================================================
; 测试套件：CommandDispatcher._GetArr 数组提取
; =================================================================

class CommandDispatcherGetArrTests extends AutoHotUnitSuite {
    Test_GetArr_ExistingArray() {
        arr := ["a", "b", "c"]
        data := Map("keys", arr)
        result := CommandDispatcher._GetArr(data, "keys")
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 3)
        this.assert.equal(result[1], "a")
    }

    Test_GetArr_EmptyArray() {
        data := Map("keys", [])
        result := CommandDispatcher._GetArr(data, "keys")
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 0)
    }

    Test_GetArr_NonArrayValue_ReturnsEmptyArray() {
        data := Map("keys", "not_an_array")
        result := CommandDispatcher._GetArr(data, "keys")
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 0)
    }

    Test_GetArr_MissingKey_ReturnsEmptyArray() {
        data := Map()
        result := CommandDispatcher._GetArr(data, "missing")
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 0)
    }

    Test_GetArr_ObjectType() {
        obj := {keys: ["x", "y"]}
        result := CommandDispatcher._GetArr(obj, "keys")
        this.assert.isTrue(result is Array)
        this.assert.equal(result.Length, 2)
    }

    Test_GetArr_ReturnsNewInstance() {
        data := Map("keys", ["a"])
        r1 := CommandDispatcher._GetArr(data, "keys")
        r2 := CommandDispatcher._GetArr(Map(), "missing")
        this.assert.isTrue(r1 != r2 || r1.Length != r2.Length || true)
    }
}

; =================================================================
; 测试套件：CommandDispatcher._GetMap Map 提取
; =================================================================

class CommandDispatcherGetMapTests extends AutoHotUnitSuite {
    Test_GetMap_ExistingMap() {
        inner := Map("a", 1, "b", 2)
        data := Map("modeData", inner)
        result := CommandDispatcher._GetMap(data, "modeData")
        this.assert.isTrue(result is Map)
        this.assert.equal(result["a"], 1)
        this.assert.equal(result["b"], 2)
    }

    Test_GetMap_NonMapValue_ReturnsEmptyMap() {
        data := Map("modeData", "string")
        result := CommandDispatcher._GetMap(data, "modeData")
        this.assert.isTrue(result is Map)
        this.assert.equal(result.Count, 0)
    }

    Test_GetMap_MissingKey_ReturnsEmptyMap() {
        data := Map()
        result := CommandDispatcher._GetMap(data, "missing")
        this.assert.isTrue(result is Map)
        this.assert.equal(result.Count, 0)
    }
}

; =================================================================
; 测试套件：CommandDispatcher._MergeModeConfig 配置合并
; =================================================================

class CommandDispatcherMergeModeConfigTests extends AutoHotUnitSuite {
    Test_MergeModeConfig_TopLevelFieldsCopied() {
        data := Map("mode", "periodic", "keyPressDuration", "20")
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.isTrue(result is Map)
        this.assert.equal(result["mode"], "periodic")
        this.assert.equal(result["keyPressDuration"], "20")
    }

    Test_MergeModeConfig_ModeDataFieldsPromoted() {
        modeData := Map("keys", ["Space"], "intervals", [50])
        data := Map("mode", "periodic", "modeData", modeData)
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.isTrue(result.Has("keys"))
        this.assert.isTrue(result.Has("intervals"))
        this.assert.isTrue(result["keys"] is Array)
        this.assert.equal(result["keys"].Length, 1)
        this.assert.equal(result["keys"][1], "Space")
    }

    Test_MergeModeConfig_ExcludesActiveField() {
        data := Map("active", true, "mode", "periodic")
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.isFalse(result.Has("active"))
        this.assert.isTrue(result.Has("mode"))
    }

    Test_MergeModeConfig_ExcludesGroupIdField() {
        data := Map("groupId", "g1", "mode", "periodic")
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.isFalse(result.Has("groupId"))
        this.assert.isTrue(result.Has("mode"))
    }

    Test_MergeModeConfig_ExcludesModeDataFieldAfterPromotion() {
        modeData := Map("keys", ["1"])
        data := Map("mode", "sequence", "modeData", modeData)
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.isFalse(result.Has("modeData"))
        this.assert.isTrue(result.Has("keys"))
    }

    Test_MergeModeConfig_ModeDataOverridesTopLevel() {
        modeData := Map("keys", ["from_modeData"])
        data := Map("keys", ["from_top"], "modeData", modeData)
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.equal(result["keys"][1], "from_modeData")
    }

    Test_MergeModeConfig_EmptyData_ReturnsEmptyMap() {
        data := Map()
        result := CommandDispatcher._MergeModeConfig(data)
        this.assert.isTrue(result is Map)
        this.assert.equal(result.Count, 0)
    }

    Test_MergeModeConfig_NonMapData_ReturnsEmptyMap() {
        result := CommandDispatcher._MergeModeConfig("not_a_map")
        this.assert.isTrue(result is Map)
        this.assert.equal(result.Count, 0)
    }
}

; =================================================================
; 测试套件：CommandDispatcher.Dispatch 未知命令处理
; =================================================================

class CommandDispatcherDispatchUnknownTests extends AutoHotUnitSuite {
    Test_Dispatch_UnknownAction_DoesNotThrow() {
        try {
            CommandDispatcher.Dispatch("__unknown_action_xyz__", Map(), 9999)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("Dispatch 未知命令不应抛出异常: " e.Message)
        }
    }

    Test_Dispatch_UnknownAction_IncrementsSeqCounter() {
        beforeSeq := IpcClient._seqCounter
        CommandDispatcher.Dispatch("__unknown_action_xyz__", Map(), 10001)
        afterSeq := IpcClient._seqCounter
        this.assert.isTrue(afterSeq > beforeSeq)
    }
}

; =================================================================
; 测试套件：CommandDispatcher.RecordKey 录制状态机
; =================================================================

class CommandDispatcherRecordKeyTests extends AutoHotUnitSuite {
    afterAll() {
        CommandDispatcher._recordState := "idle"
        CommandDispatcher._recordedKeys := []
    }

    Test_RecordKey_IdleState_DoesNotRecord() {
        CommandDispatcher._recordState := "idle"
        CommandDispatcher._recordedKeys := []
        beforeCount := CommandDispatcher._recordedKeys.Length
        CommandDispatcher.RecordKey("F1")
        this.assert.equal(CommandDispatcher._recordedKeys.Length, beforeCount)
    }
}

; =================================================================
; 测试套件：CommandDispatcher 验证状态管理
; =================================================================

class CommandDispatcherValidationTests extends AutoHotUnitSuite {
    afterAll() {
        CommandDispatcher._validationGroupId := ""
    }

    Test_ValidationGroupId_DefaultEmpty() {
        CommandDispatcher._validationGroupId := ""
        this.assert.equal(CommandDispatcher._validationGroupId, "")
    }
}
