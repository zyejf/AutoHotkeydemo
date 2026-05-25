; =================================================================
; 测试层 - 边界条件与异常输入专项测试
; 版本: 3.0
; 说明: 覆盖超长输入、深层嵌套、边界值、非法输入、快速注册注销、
;       超长键名、特殊字符往返等边界场景
; 运行: AutoHotkey.exe tests\test_boundary.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
#Include "test_result_reporter.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/config_validator.ahk"

TestReporter.BeginTest("test_boundary.ahk")

; =================================================================
; 场景A: 超长JSON输入 —— 50个数字的长数组
; =================================================================
TestReporter.Scenario("A: 超长JSON数组")

longJson := "["
loop 50 {
    if A_Index > 1
        longJson .= ","
    longJson .= A_Index
}
longJson .= "]"

parsedArr := ""
TestReporter.AssertNoThrow(() => parsedArr := JSONParser.Parse(longJson), "解析50元素JSON数组不崩溃")
TestReporter.AssertEqual(parsedArr.Length, 50, "解析后数组长度=50")
TestReporter.AssertEqual(parsedArr[50], 50, "最后一个元素=50")

; =================================================================
; 场景B: 深层嵌套 —— 10层嵌套对象
; =================================================================
TestReporter.Scenario("B: 深层嵌套10层")

nestedJson := "1"
loop 10 {
    nestedJson := '{"a":' nestedJson '}'
}

parsedNested := ""
TestReporter.AssertNoThrow(() => parsedNested := JSONParser.Parse(nestedJson), "解析10层嵌套JSON不崩溃")
current := parsedNested
loop 10 {
    current := current["a"]
}
TestReporter.AssertEqual(current, 1, "10层嵌套最深层值为1")

; =================================================================
; 场景C: intervals边界值
; =================================================================
TestReporter.Scenario("C: intervals边界值")

config1 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [1])))
TestReporter.AssertEqual(ConfigValidator.Validate(config1).Length, 0, "intervals=[1] 验证通过(errors=0)")

config2 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [0])))
TestReporter.AssertNoThrow(() => ConfigValidator.Validate(config2), "intervals=[0] 不崩溃")

config3 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [-1])))
TestReporter.AssertNoThrow(() => ConfigValidator.Validate(config3), "intervals=[-1] 不崩溃")

; =================================================================
; 场景D: 按键名边界
; =================================================================
TestReporter.Scenario("D: 按键名边界")

TestReporter.AssertEqual(SkillGroup._IsValidKeyName(""), false, "空字符串 = false")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("   "), false, "纯空白 = false")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("F24"), true, "F24 是有效键名")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName("F25"), false, "不存在的键F25 = false")

key500 := ""
loop 500
    key500 .= "x"
TestReporter.AssertNoThrow(() => SkillGroup._IsValidKeyName(key500), "500字符键名不崩溃")
TestReporter.AssertEqual(SkillGroup._IsValidKeyName(key500), false, "500字符键名 = false")

; =================================================================
; 场景E: ModeRegistry 快速注册注销
; =================================================================
TestReporter.Scenario("E: 快速注册→注销→查询")

class BoundaryExecutor extends IExecutor {
    GetModeName() {
        return "boundary_test_mode"
    }
    Execute(group) {
        return 10
    }
}

exec := BoundaryExecutor()
TestReporter.AssertNoThrow(() => ModeRegistry.Register("boundary_test_mode", exec), "注册执行器不崩溃")
TestReporter.Assert(ModeRegistry.HasMode("boundary_test_mode"), "注册后HasMode=true")

ModeRegistry.Unregister("boundary_test_mode")
TestReporter.Assert(!ModeRegistry.HasMode("boundary_test_mode"), "注销后HasMode=false")

TestReporter.AssertThrows(() => ModeRegistry.GetExecutor("boundary_test_mode"), "未注册", "注销后GetExecutor抛异常")

; =================================================================
; 场景F: ConfigStore 边界查询
; =================================================================
TestReporter.Scenario("F: ConfigStore边界查询")

ConfigStore.InitDefaults()
TestReporter.AssertEqual(ConfigStore.HasGroup("nonexistent"), false, "HasGroup('nonexistent') = false")
TestReporter.AssertEqual(ConfigStore.GetGroupConfig("nonexistent", "default"), "default", "GetGroupConfig(不存在, default) = 'default'")

; =================================================================
; 场景G: JSONParser 超长键名
; =================================================================
TestReporter.Scenario("G: 超长键名JSON")

longKey := ""
loop 500
    longKey .= "k"
longKeyJson := '{"' longKey '": 1}'

parsedLongKey := ""
TestReporter.AssertNoThrow(() => parsedLongKey := JSONParser.Parse(longKeyJson), "解析500字符键名JSON不崩溃")
TestReporter.AssertEqual(parsedLongKey[longKey], 1, "超长键对应的值=1")

; =================================================================
; 场景H: JSONSerializer 特殊字符往返
; =================================================================
TestReporter.Scenario("H: 特殊字符往返")

jsonWithSpecial := JSONSerializer.Stringify(Map("str", "line1`nline2`ttab"))
TestReporter.Assert(InStr(jsonWithSpecial, "\n") > 0, "序列化包含 \n 转义")
TestReporter.Assert(InStr(jsonWithSpecial, "\t") > 0, "序列化包含 \t 转义")

reparsed := ""
TestReporter.AssertNoThrow(() => reparsed := JSONParser.Parse(jsonWithSpecial), "含特殊字符JSON能重新解析")
TestReporter.AssertEqual(reparsed["str"], "line1`nline2`ttab", "往返后字符串还原一致")

; =================================================================
; 汇总与退出
; =================================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed > 0 ? 1 : 0)
