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
    skipped := 0
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
        } else if (status == "skipped") {
            ; 跳过必须留痕：算进总计、不算失败，但单独计数并写出原因
            this.skipped++
            this.writeLine("  ⊘ " testName " - 已跳过")
            this.writeLine("      原因: " error.Message)
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
        ; 「跳过」必须排在「失败」之后：CI 的汇总解析按 总计/通过/失败 顺序取分组
        this.writeLine("跳过: " this.skipped " 个")
        
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

; =================================================================
; JSONSerializer 标量类型分派（TD-030）
;
; 背景：AHK v2 **没有布尔类型** —— `Type(true)` 返回 "Integer"，`true` 就是 `1`、
; `false` 就是 `0`（下面 Test_AhkBoolean_IsIndistinguishableFromInteger 钉住这一事实）。
; 于是「按值判断这是布尔还是数字」在运行时**不可能**：`1 = true` 为真。
; 改动前 `_StringifyValue` 正是这么判的，结果**任何等于 1 的数值被写成 `true`、
; 等于 0 的被写成 `false`**，而 Rust 侧 `serde` 双向严格（实测
; `u64 <- false` 与 `bool <- 0` 都报 invalid type），配置/IPC 报文会整段解析失败。
;
; 因此布尔只能按**键名**判（键名是跨语言契约的一部分，见 JSONSerializer.BoolKeys），
; 其余一律按数字输出。本套件同时钉住两侧，防止任一侧被改回去。
; =================================================================
class JSONSerializerScalarTypeTests extends AutoHotUnitSuite {
    ; 根因：AHK v2 的布尔就是整数，运行时不可区分。这条是整套设计的依据，
    ; 若哪天 AHK 引入真正的布尔类型，这条会先红，提示可以换回类型分派。
    Test_AhkBoolean_IsIndistinguishableFromInteger() {
        this.assert.equal(Type(true), "Integer")
        this.assert.equal(Type(false), "Integer")
        this.assert.equal(Type(1), "Integer")
        ; 值相等 —— 这正是旧实现把 1 当 true、0 当 false 的原因
        this.assert.isTrue(1 = true)
        this.assert.isTrue(0 = false)
    }

    Test_IntegerOne_SerializesAsNumber_NotTrue() {
        this.assert.equal(JSONSerializer.Stringify(1), "1")
    }

    Test_IntegerZero_SerializesAsNumber_NotFalse() {
        this.assert.equal(JSONSerializer.Stringify(0), "0")
    }

    Test_FloatOne_SerializesAsNumber_NotTrue() {
        this.assert.equal(JSONSerializer.Stringify(1.0), "1.0")
    }

    Test_NegativeOne_StaysNumber() {
        this.assert.equal(JSONSerializer.Stringify(-1), "-1")
    }

    Test_Array_OneAndZero_StayNumbers() {
        jsonStr := JSONSerializer.Stringify([1, 0, 2])
        this.assert.isTrue(RegExMatch(jsonStr, "s)^\[\s*1,\s*0,\s*2\s*\]$") > 0)
    }

    ; 契约现场：holdDuration 是 Rust 的 u64，且 0 表示「无限保持」的合法取值。
    ; 写成 false 会让整个配置段解析失败。
    Test_ConfigContract_HoldDurationZero_StaysNumber() {
        jsonStr := JSONSerializer.Stringify(Map("hotkey", "F1", "mode", "hold", "holdDuration", 0))
        this.assert.isTrue(InStr(jsonStr, '"holdDuration": 0') > 0)
    }

    ; 反向：约定的布尔键必须仍然输出 JSON 布尔（写成 0/1 会被 Rust 的 bool 拒绝）
    Test_BoolKey_AllowOverlap_StaysJsonBoolean() {
        jsonStr := JSONSerializer.Stringify(Map("allowOverlap", false, "releaseOnEmergency", true))
        this.assert.isTrue(InStr(jsonStr, '"allowOverlap": false') > 0)
        this.assert.isTrue(InStr(jsonStr, '"releaseOnEmergency": true') > 0)
    }

    Test_BoolKey_SuccessAndError_StayJsonBoolean() {
        jsonStr := JSONSerializer.Stringify(Map("success", false, "error", true))
        this.assert.isTrue(InStr(jsonStr, '"success": false') > 0)
        this.assert.isTrue(InStr(jsonStr, '"error": true') > 0)
    }

    ; 嵌套容器里同样成立：布尔语义跟键走，不跟容器走
    Test_BoolKey_InsideNestedMap_StaysJsonBoolean() {
        jsonStr := JSONSerializer.Stringify(Map("hold", Map("autoRepeat", false, "holdDuration", 0)))
        this.assert.isTrue(InStr(jsonStr, '"autoRepeat": false') > 0)
        this.assert.isTrue(InStr(jsonStr, '"holdDuration": 0') > 0)
    }
}

; =================================================================
; JSONSerializer._EscapeString（T1 快路径）
;
; 快路径的三个判定（不含引号 / 不含反斜杠 / 不含控制字符）必须**合起来恰好覆盖**
; 「需转义字符集」= 0x00-0x1F ∪ {0x22, 0x5C}，漏一个就是静默产出非法 JSON。
; 因此这里除了断言具体输出，还做了一次 0..127 的逐字符等价性扫描
; （与逐字符版 _EscapeStringCharByChar 对照，它是本次改造前的实现）。
; =================================================================
class JSONSerializerEscapeTests extends AutoHotUnitSuite {
    ; AHK v2 的字符串字面量里反斜杠是普通字符、只有双引号需要写成两个，
    ; 混用时极易把解析器绕晕（实测报 Missing """）。统一用 Chr() 构造，避免歧义。
    static Q => Chr(34)      ; 双引号
    static B => Chr(92)      ; 反斜杠

    ; 快路径：无需转义的字符串必须原样返回（含非 ASCII）
    Test_EscapeString_PlainStringReturnsAsIs() {
        this.assert.equal(JSONSerializer._EscapeString(""), "")
        this.assert.equal(JSONSerializer._EscapeString("plain ascii 123"), "plain ascii 123")
        this.assert.equal(JSONSerializer._EscapeString("中文abc"), "中文abc")
        this.assert.equal(JSONSerializer._EscapeString("emoji 😀"), "emoji 😀")
        ; DEL(127) 与 U+2028 都不在需转义集合内
        this.assert.equal(JSONSerializer._EscapeString(Chr(127)), Chr(127))
        this.assert.equal(JSONSerializer._EscapeString(Chr(0x2028)), Chr(0x2028))
    }

    ; 有短写法的控制字符：08 09 0A 0C 0D
    Test_EscapeString_ControlCharsUseShortForms() {
        B := JSONSerializerEscapeTests.B
        this.assert.equal(JSONSerializer._EscapeString(Chr(8)), B "b")
        this.assert.equal(JSONSerializer._EscapeString(Chr(9)), B "t")
        this.assert.equal(JSONSerializer._EscapeString(Chr(10)), B "n")
        this.assert.equal(JSONSerializer._EscapeString(Chr(12)), B "f")
        this.assert.equal(JSONSerializer._EscapeString(Chr(13)), B "r")
        ; 夹在普通字符中间也要正确（StrReplace 不能误伤周边）
        this.assert.equal(JSONSerializer._EscapeString("a" Chr(9) "b"), "a" B "tb")
    }

    ; 没有短写法的控制字符：必须走 \uXXXX 兜底路径
    Test_EscapeString_OtherControlCharsUseUnicodeEscape() {
        B := JSONSerializerEscapeTests.B
        this.assert.equal(JSONSerializer._EscapeString(Chr(0)), B "u0000")
        this.assert.equal(JSONSerializer._EscapeString(Chr(7)), B "u0007")
        this.assert.equal(JSONSerializer._EscapeString(Chr(11)), B "u000B")
        this.assert.equal(JSONSerializer._EscapeString(Chr(31)), B "u001F")
        ; 混合：既有 \uXXXX 又有短写法又有引号
        this.assert.equal(JSONSerializer._EscapeString(Chr(0) . Chr(10) . Chr(34))
                        , B "u0000" B "n" B Chr(34))
    }

    ; 引号与反斜杠。⚠️ 反斜杠必须**先**替换，否则结果会多一层转义
    Test_EscapeString_QuoteAndBackslashOrderMatters() {
        Q := JSONSerializerEscapeTests.Q
        B := JSONSerializerEscapeTests.B
        this.assert.equal(JSONSerializer._EscapeString(Q), B Q)
        this.assert.equal(JSONSerializer._EscapeString(B), B B)
        ; 反斜杠 + 引号：正确结果是 \\\" （3 个反斜杠 + 引号）。
        ; 若先替换引号再替换反斜杠，会得到 \\\\" —— 这条会变红。
        this.assert.equal(JSONSerializer._EscapeString(B Q), B B B Q)
        ; 首尾位置的反斜杠（StrReplace 没有 off-by-one 问题）
        this.assert.equal(JSONSerializer._EscapeString("tail" B), "tail" B B)
        this.assert.equal(JSONSerializer._EscapeString(B "lead"), B B "lead")
    }

    ; 逐字符等价性扫描：单字符与「前后夹普通字符」两种形态，0..127 全覆盖。
    ; 这是本次改造最强的一条 —— 任何漏判/误判都会在这里暴露
    Test_EscapeString_MatchesCharByCharForAllAscii() {
        bad := ""
        i := 0
        while i <= 127 {
            for s in [Chr(i), "x" Chr(i) "y"] {
                a := JSONSerializer._EscapeStringCharByChar(s)
                b := JSONSerializer._EscapeString(s)
                if a != b
                    bad .= "chr(" i ") old=[" a "] new=[" b "] "
            }
            i++
        }
        this.assert.equal(bad, "")
    }

    ; 组合场景等价性（含 NUL、多反斜杠、密集混排）
    Test_EscapeString_MatchesCharByCharForComposites() {
        Q := JSONSerializerEscapeTests.Q
        B := JSONSerializerEscapeTests.B
        cases := ["he said " Q "hi" Q
                , "back" B "slash"
                , "a" Q "b" B "c" Chr(10) "d" Chr(9) "e"
                , B B B B
                , B Q
                , Q B
                , B B Q
                , Chr(0) "nul"
                , "a" Chr(0) "b"
                , Chr(10) Chr(13) Chr(9) Chr(8) Chr(12) Chr(11)]
        bad := ""
        for s in cases {
            a := JSONSerializer._EscapeStringCharByChar(s)
            b := JSONSerializer._EscapeString(s)
            if a != b
                bad .= "old=[" a "] new=[" b "] "
        }
        this.assert.equal(bad, "")
    }

    ; 端到端：Stringify → Parse 往返应保持原值（快路径不能破坏真实序列化）
    Test_EscapeString_RoundTripThroughParser() {
        Q := JSONSerializerEscapeTests.Q
        B := JSONSerializerEscapeTests.B
        m := Map("plain", "abc", "quoted", "say " Q "hi" Q
               , "backslash", "a" B "b", "newline", "l1" Chr(10) "l2")
        jsonStr := JSONSerializer.Stringify(m)
        back := JSONParser.Parse(jsonStr)
        this.assert.equal(back["plain"], "abc")
        this.assert.equal(back["quoted"], "say " Q "hi" Q)
        this.assert.equal(back["backslash"], "a" B "b")
        this.assert.equal(back["newline"], "l1" Chr(10) "l2")
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
        ; 断言日志组件自己配置的实际路径。相对路径由 A_WorkingDir 解析
        ; （跑 tests/run_all_tests.ahk 时是 tests/），写死 "<repo>/logs/"
        ; 只在该目录恰好已存在的脏环境里"通过"，全新 clone 必失败。
        ErrorSystem.Init()
        logPath := ErrorSystem.logFile
        this.assert.isTrue(FileExist(logPath) != "")
    }
    
    Test_LogWarning_WritesToLog() {
        ; 测试警告记录功能
        ErrorSystem.LogWarning("测试警告消息", A_ThisFunc, A_LineNumber)
        ; 验证日志文件存在
        ; 断言日志组件自己配置的实际路径。相对路径由 A_WorkingDir 解析
        ; （跑 tests/run_all_tests.ahk 时是 tests/），写死 "<repo>/logs/"
        ; 只在该目录恰好已存在的脏环境里"通过"，全新 clone 必失败。
        ErrorSystem.Init()
        logPath := ErrorSystem.logFile
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
        logPath := DebugLogger.logFile   ; 同上：按组件实际使用的路径断言
        this.assert.isTrue(FileExist(logPath) != "")
    }
}

; ============================================================
; JSONLogger 测试
; ============================================================

class JSONLoggerTests extends AutoHotUnitSuite {
    Test_JSONLogger_Log_WritesToFile() {
        JSONLogger.Log("INFO", "测试消息", Map("module", "Test"))
        logPath := JSONLogger.logFile   ; 同上：按组件实际使用的路径断言
        this.assert.isTrue(FileExist(logPath) != "")
    }
    
    Test_JSONLogger_LogError_WritesToFile() {
        JSONLogger.Log("ERROR", "测试错误消息", Map("module", "Test"))
        logPath := JSONLogger.logFile   ; 同上：按组件实际使用的路径断言
        this.assert.isTrue(FileExist(logPath) != "")
    }
    
    Test_JSONLogger_LogWarning_WritesToFile() {
        JSONLogger.Log("WARNING", "测试警告消息", Map("module", "Test"))
        logPath := JSONLogger.logFile   ; 同上：按组件实际使用的路径断言
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