; =================================================================
; 测试层 - 基础设施层断言式验证脚本
; 版本: 3.1
; 说明: 全面验证 infrastructure 层所有模块，覆盖正常/边界/异常路径
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/ipc_channel.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; 保留旧版 T 对象声明以兼容，本文件不再使用
T := {passed: 0, failed: 0, errors: []}

TestReporter.BeginTest("test_infrastructure.ahk")

; =================================================================
; 场景A: JSONParser 基础解析
; =================================================================
TestReporter.Scenario("A: JSONParser 基础")

parsed := JSONParser.Parse('{"key":"value","num":42}')
TestReporter.Assert(parsed is Map, "解析返回 Map")
TestReporter.Assert(parsed["key"] = "value", "字符串 key 解析为 value")
TestReporter.AssertEqual(parsed["num"], 42, "num 解析为数值 42")

arr := JSONParser.Parse('[1, 2, 3]')
TestReporter.Assert(arr is Array, "数组解析返回 Array")
TestReporter.AssertEqual(arr.Length, 3, "数组长度 = 3")

nested := JSONParser.Parse('{"a": {"b": [1,2,3]}}')
TestReporter.Assert(nested is Map, "嵌套对象解析返回 Map")
TestReporter.Assert(nested["a"] is Map, "嵌套子对象正确")

; =================================================================
; 场景B: JSONParser 边界输入
; =================================================================
TestReporter.Scenario("B: JSONParser 边界")

TestReporter.AssertNoThrow(() => JSONParser.Parse(""), '空字符串 "" 不崩溃')
TestReporter.AssertNoThrow(() => JSONParser.Parse("   `t`n"), '仅空白不崩溃')
TestReporter.AssertNoThrow(() => JSONParser.Parse(Chr(0xFEFF) . "{}"), 'BOM 头 + {} 不崩溃')

; =================================================================
; 场景C: JSONParser 异常输入
; =================================================================
TestReporter.Scenario("C: JSONParser 异常")

TestReporter.AssertThrows(() => JSONParser.Parse("{bad json"), "对象", "非法 JSON 抛异常")
TestReporter.AssertThrows(() => JSONParser.Parse('{"a":"b'), "未闭合", "未闭合字符串抛异常")
TestReporter.AssertThrows(() => JSONParser.Parse('{"a":1'), "未闭合", "未闭合对象抛异常")

; =================================================================
; 场景D: JSONSerializer 序列化
; =================================================================
TestReporter.Scenario("D: JSONSerializer")

jsonStr := JSONSerializer.Stringify(Map("key", "val"))
TestReporter.Assert(InStr(jsonStr, '"key"') > 0, '序列化包含 key')
TestReporter.Assert(InStr(jsonStr, '"val"') > 0, '序列化包含 val')

emptyMapStr := JSONSerializer.Stringify(Map())
TestReporter.AssertEqual(emptyMapStr, "{}", "空 Map → {}")

emptyArrStr := JSONSerializer.Stringify([])
TestReporter.AssertEqual(emptyArrStr, "[]", "空 Array → []")

roundTrip := JSONParser.Parse(jsonStr)
TestReporter.Assert(roundTrip["key"] = "val", "序列化后可正确反解析（往返测试）")

; =================================================================
; 场景E: ConfigStore 配置存储
; =================================================================
TestReporter.Scenario("E: ConfigStore")

ConfigStore.InitDefaults()
TestReporter.Assert(ConfigStore.HasGroup("1"), "HasGroup('1') = true")
TestReporter.Assert(ConfigStore.HasGroup("6"), "HasGroup('6') = true")
TestReporter.AssertEqual(ConfigStore.GetGroupCount(), 6, "GetGroupCount = 6")
TestReporter.Assert(ConfigStore.Get("CONTROL_HOTKEYS") is Map, "CONTROL_HOTKEYS 是 Map")

ConfigStore.SetGroupConfig("99", Map("hotkey", "F9", "mode", "periodic"))
TestReporter.Assert(ConfigStore.GetGroupConfig("99")["hotkey"] = "F9", "SetGroupConfig/GetGroupConfig 往返一致")

; =================================================================
; 场景F: ConfigValidator 全模式校验（缺必需字段）
; =================================================================
TestReporter.Scenario("F: ConfigValidator 全模式")

; periodic 缺 keys
c1 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "periodic")))
TestReporter.Assert(ConfigValidator.Validate(c1).Length > 0, "periodic 缺 keys → 有错误")

; sequence 缺 delays
c2 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "sequence")))
TestReporter.Assert(ConfigValidator.Validate(c2).Length > 0, "sequence 缺 delays → 有错误")

; enhanced_periodic 缺 pressKeys
c3 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "enhanced_periodic")))
TestReporter.Assert(ConfigValidator.Validate(c3).Length > 0, "enhanced_periodic 缺 pressKeys → 有错误")

; enhanced_sequence 缺 pressDelays
c4 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "enhanced_sequence")))
TestReporter.Assert(ConfigValidator.Validate(c4).Length > 0, "enhanced_sequence 缺 pressDelays → 有错误")

; hybrid 缺 groups
c5 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "hybrid")))
TestReporter.Assert(ConfigValidator.Validate(c5).Length > 0, "hybrid 缺 groups → 有错误")

; enhanced_hybrid 缺 groups
c6 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "enhanced_hybrid")))
TestReporter.Assert(ConfigValidator.Validate(c6).Length > 0, "enhanced_hybrid 缺 groups → 有错误")

; hold 缺 holdKeys
c7 := Map("GroupSettings", Map("1", Map("hotkey", "F1", "mode", "hold")))
TestReporter.Assert(ConfigValidator.Validate(c7).Length > 0, "hold 缺 holdKeys → 有错误")

; =================================================================
; 场景G: ErrorHandler SafeExecute 安全执行
; =================================================================
TestReporter.Scenario("G: ErrorHandler SafeExecute")

result := ErrorHandler.SafeExecute(() => 42, () => 0)
TestReporter.AssertEqual(result, 42, "正常路径返回 42")

fallbackResult := ErrorHandler.SafeExecute(() => throw(Error("test error")), () => "fallback")
TestReporter.AssertEqual(fallbackResult, "fallback", '异常路径返回降级值 "fallback"')

; =================================================================
; 场景H: ErrorHandler RetryWithPolicy 重试策略
; =================================================================
TestReporter.Scenario("H: ErrorHandler RetryWithPolicy")

retryResult := ErrorHandler.RetryWithPolicy(() => 42, 3, 10)
TestReporter.AssertEqual(retryResult, 42, "一次性成功返回 42")

TestReporter.AssertThrows(() => ErrorHandler.RetryWithPolicy(() => throw(Error("fail")), 2, 10),
    "重试", "全部失败抛异常")

; =================================================================
; 场景I: ErrorHandler HealthCheck 健康检查
; =================================================================
TestReporter.Scenario("I: ErrorHandler HealthCheck")

healthyObj := {EmergencyMode: false, GetActiveCount: () => 0, _timers: Map(), HoldKeyRegistry: Map(), GetTimerCount: () => 0}
health := ErrorHandler.HealthCheck(healthyObj)
TestReporter.Assert(health.healthy = true, "健康对象 healthy 为 true")

; =================================================================
; 场景J: BackupCore 备份核心
; =================================================================
TestReporter.Scenario("J: BackupCore")

BackupCore.Init()
TestReporter.Assert(FileExist("backups") != "", "Init 后 backups 目录存在")

createResult := BackupCore.CreateBackup(Map("test", 1), "unittest")
TestReporter.Assert(createResult["success"] = true, "CreateBackup 返回 success:true")

backups := BackupCore.ListBackups()
TestReporter.Assert(backups.Length >= 1, "ListBackups 返回数组长度≥1")

TestReporter.Assert(InStr(backups[1]["file"], "unittest") > 0, "新备份在列表最前面")

; =================================================================
; 场景K: IPCChannel 进程间通信
; =================================================================
TestReporter.Scenario("K: IPCChannel")

IPCChannel.Init()
TestReporter.Assert(FileExist("ipc") != "", "Init 后 ipc 目录存在")

msgList := IPCChannel.PollMessages()
TestReporter.Assert(msgList is Array && msgList.Length = 0, "PollMessages() 返回空数组")

; =================================================================
; 汇总与退出
; =================================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed > 0 ? 1 : 0)
