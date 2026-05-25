; =================================================================
; 测试层 - KeyRecorder 单元测试
; 说明: 覆盖 KeyRecorder 全部公开方法
; 运行: AutoHotkey.exe tests\test_key_recorder.ahk
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off
Persistent(false)

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/key_recorder.ahk"

ErrorSystem.Init()
JSONLogger.Init()
DebugLogger.Init()

TestReporter.BeginTest("test_key_recorder.ahk")

TestReporter.Scenario("1.1 KeyRecorder 初始状态")
TestReporter.Assert(!KeyRecorder.IsRecording(), "初始不应在录制中")
TestReporter.Assert(KeyRecorder.GetEventCount() = 0, "初始事件数应为0")

TestReporter.Scenario("1.2 KeyRecorder.Start 设置录制状态")
captured := []
KeyRecorder.Start((evt) => captured.Push(evt))
TestReporter.Assert(KeyRecorder.IsRecording(), "开始后应在录制中")

TestReporter.Scenario("1.3 KeyRecorder.OnKey 记录事件")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("A", "up", 15)
TestReporter.Assert(KeyRecorder.GetEventCount() = 2, "应记录2个事件")

TestReporter.Scenario("1.4 KeyRecorder.Stop 停止录制并返回结果")
result := KeyRecorder.Stop()
TestReporter.Assert(!KeyRecorder.IsRecording(), "停止后不应在录制中")
TestReporter.Assert(result.Has("events"), "结果应包含 events")
TestReporter.Assert(result.Has("duration"), "结果应包含 duration")
TestReporter.Assert(result["events"].Length = 2, "应有2个事件")

TestReporter.Scenario("1.5 KeyRecorder 事件格式正确")
evt := result["events"][1]
TestReporter.Assert(evt["key"] = "A", "key 应为 A")
TestReporter.Assert(evt["event"] = "down", "event 应为 down")
TestReporter.Assert(evt["device"] = "keyboard", "device 应为 keyboard")

TestReporter.Scenario("1.6 ExportAsGroupConfig 周期性模式")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("A", "up", 15)
KeyRecorder.OnKey("B", "down", 50)
KeyRecorder.OnKey("B", "up", 65)
KeyRecorder.OnKey("A", "down", 100)
KeyRecorder.OnKey("A", "up", 115)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config.Has("keys"), "配置应包含 keys")
TestReporter.Assert(config.Has("intervals"), "配置应包含 intervals")
TestReporter.Assert(config["keys"].Length > 0, "keys 不应为空")

TestReporter.Scenario("1.7 ExportAsGroupConfig 序列模式")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
KeyRecorder.OnKey("B", "down", 100)
KeyRecorder.OnKey("C", "down", 250)
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("sequence", 15)
TestReporter.Assert(config.Has("keys"), "配置应包含 keys")
TestReporter.Assert(config.Has("delays"), "配置应包含 delays")

TestReporter.Scenario("1.8 KeyRecorder 重复 Stop 安全")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnKey("A", "down", 0)
r1 := KeyRecorder.Stop()
r2 := KeyRecorder.Stop()
TestReporter.Assert(r2 = "", "重复 Stop 应返回空")

TestReporter.Scenario("1.9 KeyRecorder 未启动时 OnKey 忽略")
KeyRecorder.OnKey("Z", "down", 0)
TestReporter.Assert(KeyRecorder.GetEventCount() = 0, "未启动时不应记录")

TestReporter.Scenario("1.10 OnMouse 记录鼠标事件")
KeyRecorder.Start((evt) => "")
KeyRecorder.OnMouse("LButton", "click", 10)
TestReporter.Assert(KeyRecorder.GetEventCount() = 1, "应记录1个鼠标事件")
KeyRecorder.Stop()

TestReporter.Scenario("1.11 ExportAsGroupConfig 空事件返回空Map")
KeyRecorder.Start((evt) => "")
KeyRecorder.Stop()
config := KeyRecorder.ExportAsGroupConfig("periodic", 15)
TestReporter.Assert(config.Count = 0, "空事件应返回空Map")

TestReporter.EndTest()
ExitApp()
