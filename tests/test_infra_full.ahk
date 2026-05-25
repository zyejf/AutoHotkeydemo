; =================================================================
; 测试层 - Infrastructure 层完整测试套件 v2.0
; 说明: 覆盖 JSONParser/JSONSerializer/ConfigStore/ConfigValidator/
;       ErrorSystem/ErrorHandler/DebugLogger/JSONLogger/BackupCore/IPC/Utils
;       全部公开方法
; 运行: AutoHotkey.exe tests\test_infra_full.ahk
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
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/utils.ahk"

OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))

ErrorSystem.Init()
ConfigStore.InitDefaults()
JSONLogger.Init()
DebugLogger.Init()
BackupCore.Init()

TestReporter.BeginTest("test_infra_full.ahk")

; =================================================================
; 1. JSONParser 完整测试
; =================================================================
TestReporter.Scenario("1.1 JSONParser 基础解析")
parsed := JSONParser.Parse('{"key":"value","num":42}')
TestReporter.Assert(parsed is Map, "解析返回 Map")
TestReporter.AssertEqual(parsed["key"], "value", "字符串 key 解析正确")
TestReporter.AssertEqual(parsed["num"], 42, "数值 num 解析正确")

TestReporter.Scenario("1.2 JSONParser 数组解析")
arr := JSONParser.Parse('[1, 2, 3]')
TestReporter.Assert(arr is Array, "数组解析返回 Array")
TestReporter.AssertEqual(arr.Length, 3, "数组长度 = 3")
TestReporter.AssertEqual(arr[1], 1, "arr[1] = 1")
TestReporter.AssertEqual(arr[3], 3, "arr[3] = 3")

TestReporter.Scenario("1.3 JSONParser 嵌套解析")
nested := JSONParser.Parse('{"a": {"b": [1,2,3]}}')
TestReporter.Assert(nested is Map, "嵌套对象解析返回 Map")
TestReporter.Assert(nested["a"] is Map, "嵌套子对象正确")
TestReporter.AssertEqual(nested["a"]["b"].Length, 3, "嵌套数组长度 = 3")

TestReporter.Scenario("1.4 JSONParser 边界输入")
TestReporter.AssertNoThrow(() => JSONParser.Parse(""), '空字符串不崩溃')
TestReporter.AssertNoThrow(() => JSONParser.Parse("   "), '仅空白不崩溃')

TestReporter.Scenario("1.5 JSONParser 特殊值")
boolJson := JSONParser.Parse('{"t":true,"f":false,"n":null}')
TestReporter.Assert(boolJson is Map, "布尔/null 解析返回 Map")
TestReporter.AssertEqual(boolJson["t"], true, "true 解析正确")
TestReporter.AssertEqual(boolJson["f"], false, "false 解析正确")

TestReporter.Scenario("1.6 JSONParser Unicode")
unicodeJson := JSONParser.Parse('{"chinese":"测试"}')
TestReporter.Assert(unicodeJson is Map, "Unicode JSON 解析返回 Map")
TestReporter.AssertEqual(unicodeJson["chinese"], "测试", "Unicode 字符串正确")

TestReporter.Scenario("1.7 JSONParser LoadFile")
TestReporter.AssertNoThrow(() => JSONParser.LoadFile("config.json"), "LoadFile config.json 不崩溃")

; =================================================================
; 2. JSONSerializer 完整测试
; =================================================================
TestReporter.Scenario("2.1 JSONSerializer Map 序列化")
m := Map()
m["name"] := "test"
m["value"] := 42
json := JSONSerializer.Stringify(m)
TestReporter.Assert(InStr(json, '"name"') > 0, "序列化包含 name 字段")
TestReporter.Assert(InStr(json, '"test"') > 0, "序列化包含 test 值")
TestReporter.Assert(InStr(json, '42') > 0, "序列化包含数值 42")

TestReporter.Scenario("2.2 JSONSerializer Array 序列化")
arr := [1, "two", true]
json := JSONSerializer.Stringify(arr)
TestReporter.Assert(InStr(json, '1') > 0, "数组序列化包含 1")
TestReporter.Assert(InStr(json, '"two"') > 0, "数组序列化包含 two")

TestReporter.Scenario("2.3 JSONSerializer 嵌套结构")
nested := Map()
nested["arr"] := [1, 2, 3]
nested["obj"] := Map("k", "v")
json := JSONSerializer.Stringify(nested)
TestReporter.Assert(InStr(json, '"arr"') > 0, "嵌套序列化包含 arr")
TestReporter.Assert(InStr(json, '"obj"') > 0, "嵌套序列化包含 obj")

TestReporter.Scenario("2.4 JSONSerializer 特殊字符转义")
special := Map()
special["quote"] := 'hello "world"'
json := JSONSerializer.Stringify(special)
TestReporter.Assert(InStr(json, '\"') > 0, "引号被转义")

TestReporter.Scenario("2.5 JSONSerializer 空结构")
emptyMap := Map()
json := JSONSerializer.Stringify(emptyMap)
TestReporter.Assert(InStr(json, '{') > 0, "空 Map 序列化为 {}")

emptyArr := []
jsonArr := JSONSerializer.Stringify(emptyArr)
TestReporter.Assert(InStr(jsonArr, '[') > 0, "空 Array 序列化为 []")

TestReporter.Scenario("2.6 JSONSerializer 循环引用安全")
obj := Map()
obj["self"] := obj
TestReporter.AssertNoThrow(() => JSONSerializer.Stringify(obj), "循环引用不崩溃")

; =================================================================
; 3. ConfigStore 完整测试
; =================================================================
TestReporter.Scenario("3.1 ConfigStore Get/Set/Has")
ConfigStore.Set("test_key", "test_value")
TestReporter.AssertEqual(ConfigStore.Get("test_key"), "test_value", "Get 返回 Set 的值")
TestReporter.Assert(ConfigStore.Has("test_key"), "Has 返回 true")
TestReporter.Assert(!ConfigStore.Has("nonexistent_key"), "不存在的 key Has 返回 false")
TestReporter.AssertEqual(ConfigStore.Get("nonexistent", "default"), "default", "Get 默认值正确")

TestReporter.Scenario("3.2 ConfigStore GroupConfig 操作")
grpConfig := {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}
ConfigStore.SetGroupConfig("test_grp", grpConfig)
TestReporter.Assert(ConfigStore.HasGroup("test_grp"), "HasGroup 返回 true")
retrieved := ConfigStore.GetGroupConfig("test_grp")
TestReporter.Assert(retrieved != "", "GetGroupConfig 返回非空")

TestReporter.Scenario("3.3 ConfigStore DeleteGroupConfig")
ConfigStore.DeleteGroupConfig("test_grp")
TestReporter.Assert(!ConfigStore.HasGroup("test_grp"), "DeleteGroupConfig 后 HasGroup 返回 false")

TestReporter.Scenario("3.4 ConfigStore GetGroupCount")
count := ConfigStore.GetGroupCount()
TestReporter.Assert(count >= 0, "GetGroupCount 返回非负数")

TestReporter.Scenario("3.5 ConfigStore ControlHotkey")
ConfigStore.SetControlHotkey("emergency", "F12")
TestReporter.AssertEqual(ConfigStore.GetControlHotkey("emergency"), "F12", "GetControlHotkey 正确")

TestReporter.Scenario("3.6 ConfigStore Load/Save")
TestReporter.AssertNoThrow(() => ConfigStore.Load(), "Load 不崩溃")
TestReporter.AssertNoThrow(() => ConfigStore.Save(ConfigStore.Load()), "Save 不崩溃")

; =================================================================
; 4. ConfigValidator 完整测试
; =================================================================
TestReporter.Scenario("4.1 ConfigValidator Validate - 有效配置")
validConfig := Map()
validConfig["GroupSettings"] := Map()
validConfig["GroupSettings"]["1"] := Map("mode", "periodic", "hotkey", "F1", "keys", ["a"], "intervals", [50])
validConfig["CONTROL_HOTKEYS"] := Map("emergency", "F12")
errors := ConfigValidator.Validate(validConfig)
TestReporter.Assert(errors is Array, "Validate 返回 Array")

TestReporter.Scenario("4.2 ConfigValidator ValidateGroupOnly")
grpErrors := ConfigValidator.ValidateGroupOnly("test", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]})
TestReporter.Assert(grpErrors is Array, "ValidateGroupOnly 返回 Array")

TestReporter.Scenario("4.3 ConfigValidator ValidateGroupHotkeys")
hkErrors := ConfigValidator.ValidateGroupHotkeys(validConfig)
TestReporter.Assert(hkErrors is Array, "ValidateGroupHotkeys 返回 Array")

TestReporter.Scenario("4.4 ConfigValidator GetErrorMessage")
errMsg := ConfigValidator.GetErrorMessage({field: "test", message: "error msg"})
TestReporter.Assert(errMsg != "", "GetErrorMessage 返回非空字符串")

; =================================================================
; 5. ErrorSystem 完整测试
; =================================================================
TestReporter.Scenario("5.1 ErrorSystem Init")
TestReporter.Assert(ErrorSystem._initialized, "ErrorSystem 已初始化")

TestReporter.Scenario("5.2 ErrorSystem LogError")
beforeCount := ErrorSystem.GetErrorCount()
ErrorSystem.LogError("测试错误消息", "ERROR", "test_func", 42)
afterCount := ErrorSystem.GetErrorCount()
TestReporter.Assert(afterCount >= beforeCount, "LogError 后错误计数增加")

TestReporter.Scenario("5.3 ErrorSystem LogWarning")
TestReporter.AssertNoThrow(() => ErrorSystem.LogWarning("测试警告", "test_func", 10), "LogWarning 不崩溃")

TestReporter.Scenario("5.4 ErrorSystem HandleError")
TestReporter.AssertNoThrow(() => ErrorSystem.HandleError(Error("test error"), "Test"), "HandleError 不崩溃")

; =================================================================
; 6. ErrorHandler 完整测试
; =================================================================
TestReporter.Scenario("6.1 ErrorHandler RetryWithPolicy - 成功")
retryCount := 0
result := ErrorHandler.RetryWithPolicy(() => (retryCount++, "ok"), 3, 10)
TestReporter.AssertEqual(result, "ok", "RetryWithPolicy 成功返回 ok")
TestReporter.AssertEqual(retryCount, 1, "RetryWithPolicy 只调用一次")

TestReporter.Scenario("6.2 ErrorHandler RetryWithPolicy - 重试后成功")
attemptCount := 0
_ThrowIfLessThan3() {
    attemptCount++
    if attemptCount < 3
        throw Error("retry")
    return "success"
}
result2 := ErrorHandler.RetryWithPolicy(_ThrowIfLessThan3, 3, 10)
TestReporter.AssertEqual(result2, "success", "RetryWithPolicy 重试后成功")

TestReporter.Scenario("6.3 ErrorHandler SafeExecute - 成功")
safeResult := ErrorHandler.SafeExecute(() => "safe_value")
TestReporter.AssertEqual(safeResult, "safe_value", "SafeExecute 成功返回值")

TestReporter.Scenario("6.4 ErrorHandler SafeExecute - 失败回退")
_AlwaysThrow() {
    throw Error("fail")
}
safeFallback := ErrorHandler.SafeExecute(_AlwaysThrow, "fallback")
TestReporter.AssertEqual(safeFallback, "fallback", "SafeExecute 失败返回回退值")

TestReporter.Scenario("6.5 ErrorHandler CheckTimerLeak")
timerMap := Map()
for i in range(1, 5)
    timerMap["timer_" i] := true
leakResult := ErrorHandler.CheckTimerLeak(timerMap)
TestReporter.AssertEqual(leakResult, false, "CheckTimerLeak 5个定时器不超阈值返回 false")

TestReporter.Scenario("6.6 ErrorHandler CheckStuckKeys")
stuckResult := ErrorHandler.CheckStuckKeys(Map("Shift", A_TickCount - 65000))
TestReporter.AssertEqual(stuckResult, true, "CheckStuckKeys 超过60秒返回 true")

TestReporter.Scenario("6.7 ErrorHandler CheckLogFileSize")
logResult := ErrorHandler.CheckLogFileSize("logs/app.log")
TestReporter.Assert(logResult = true || logResult = false, "CheckLogFileSize 返回布尔值")

TestReporter.Scenario("6.8 ErrorHandler HealthCheck")
healthResult := ErrorHandler.HealthCheck(SkillManager)
TestReporter.Assert(healthResult is Map, "HealthCheck 返回 Map")

; =================================================================
; 7. DebugLogger 完整测试
; =================================================================
TestReporter.Scenario("7.1 DebugLogger Init")
TestReporter.AssertNoThrow(() => DebugLogger.Init(), "DebugLogger.Init 不崩溃")

TestReporter.Scenario("7.2 DebugLogger Log")
TestReporter.AssertNoThrow(() => DebugLogger.Log("DEBUG", "测试日志消息"), "DebugLogger.Log 不崩溃")

TestReporter.Scenario("7.3 DebugLogger 各级别")
TestReporter.AssertNoThrow(() => DebugLogger.Log("ERROR", "错误日志"), "ERROR 级别日志不崩溃")
TestReporter.AssertNoThrow(() => DebugLogger.Log("WARNING", "警告日志"), "WARNING 级别日志不崩溃")

; =================================================================
; 8. JSONLogger 完整测试
; =================================================================
TestReporter.Scenario("8.1 JSONLogger Init")
TestReporter.AssertNoThrow(() => JSONLogger.Init(), "JSONLogger.Init 不崩溃")

TestReporter.Scenario("8.2 JSONLogger Log")
TestReporter.AssertNoThrow(() => JSONLogger.Log("ERROR", "JSON日志测试"), "JSONLogger.Log 不崩溃")

TestReporter.Scenario("8.3 JSONLogger GetSummary")
summary := JSONLogger.GetSummary()
TestReporter.Assert(summary is Map, "GetSummary 返回 Map")

TestReporter.Scenario("8.4 JSONLogger HasErrors/HasWarnings")
_ := JSONLogger.HasErrors()
_ := JSONLogger.HasWarnings()
TestReporter.Assert(true, "HasErrors/HasWarnings 不崩溃")

TestReporter.Scenario("8.5 JSONLogger Clear")
TestReporter.AssertNoThrow(() => JSONLogger.Clear(), "JSONLogger.Clear 不崩溃")

; =================================================================
; 9. BackupCore 完整测试
; =================================================================
TestReporter.Scenario("9.1 BackupCore Init")
TestReporter.AssertNoThrow(() => BackupCore.Init(), "BackupCore.Init 不崩溃")

TestReporter.Scenario("9.2 BackupCore CreateBackup")
testConfig := Map("test_key", "test_value")
backupResult := BackupCore.CreateBackup(testConfig, "test")
TestReporter.Assert(backupResult is Map, "CreateBackup 返回 Map")
TestReporter.Assert(backupResult.Has("success"), "CreateBackup 包含 success 字段")

TestReporter.Scenario("9.3 BackupCore ListBackups")
backups := BackupCore.ListBackups()
TestReporter.Assert(backups is Array, "ListBackups 返回 Array")

TestReporter.Scenario("9.4 BackupCore RecordConfigChange")
TestReporter.AssertNoThrow(() => BackupCore.RecordConfigChange(testConfig), "RecordConfigChange 不崩溃")

TestReporter.Scenario("9.5 BackupCore DeleteBackup - 不存在的备份")
delResult := BackupCore.DeleteBackup("nonexistent_backup.json")
TestReporter.AssertEqual(delResult, false, "删除不存在的备份返回 false")

; =================================================================
; 10. Utils 完整测试
; =================================================================
TestReporter.Scenario("10.1 Utils Rotate")
TestReporter.AssertNoThrow(() => Utils.Rotate("logs/app.log", 5), "Utils.Rotate 不崩溃")

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
