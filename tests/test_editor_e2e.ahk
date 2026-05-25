#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "test_result_reporter.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"
#Include "../application/group_service.ahk"
#Include "../application/config_service.ahk"

TestReporter.BeginTest("test_editor_e2e.ahk")

JSONLogger.Init()
DebugLogger.Init()
ConfigStore.InitDefaults()
ErrorSystem.Init()
ModeRegistry._Init()

SkillGroup.Logger := DebugLogger
SkillGroup.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillGroup.ConfigStore := ConfigStore
SkillGroup.IsKeyAllowed := ((key, groupId) => true)
SkillGroup.RegisterHoldKey := ((key, groupId) => true)
SkillGroup.UnregisterHoldKey := ((key, groupId) => "")

SkillManager.Logger := JSONLogger
SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
SkillManager.ConfigStore := ConfigStore

; =================================================================
; 场景1: periodic 模式
; =================================================================
TestReporter.Scenario("1: periodic 模式")
config1 := Map("hotkey", "F1", "mode", "periodic", "keys", ["Space", "1", "2"], "intervals", [50, 100, 100])
grp1 := SkillGroup("p1", config1)
TestReporter.AssertEqual(grp1.mode, "periodic", "periodic 模式正确")
TestReporter.AssertEqual(grp1.keys.Length, 3, "periodic 按键数=3")

; =================================================================
; 场景2: sequence 模式
; =================================================================
TestReporter.Scenario("2: sequence 模式")
config2 := Map("hotkey", "F2", "mode", "sequence", "keys", ["1", "2", "3"], "delays", [100, 100, 100])
grp2 := SkillGroup("s1", config2)
TestReporter.AssertEqual(grp2.mode, "sequence", "sequence 模式正确")
TestReporter.AssertEqual(grp2.delays.Length, 3, "sequence 延迟数=3")

; =================================================================
; 场景3: enhanced_periodic 模式（含 holdKeys/holdMode）
; =================================================================
TestReporter.Scenario("3: enhanced_periodic 模式")
config3 := Map("hotkey", "F3", "mode", "enhanced_periodic", "pressKeys", ["Space", "1", "2"], "intervals", [50, 50, 50], "holdKeys", ["Shift"], "holdMode", "continuous")
grp3 := SkillGroup("ep1", config3)
TestReporter.AssertEqual(grp3.mode, "enhanced_periodic", "enhanced_periodic 模式正确")
TestReporter.AssertEqual(grp3.holdKeys.Length, 1, "enhanced_periodic holdKeys数=1")

; =================================================================
; 场景4: enhanced_sequence 模式（含 holdKeys/holdMode）
; =================================================================
TestReporter.Scenario("4: enhanced_sequence 模式")
config4 := Map("hotkey", "F4", "mode", "enhanced_sequence", "pressKeys", ["Space", "4"], "pressDelays", [50, 50], "holdKeys", ["Ctrl"], "holdMode", "continuous")
grp4 := SkillGroup("es1", config4)
TestReporter.AssertEqual(grp4.mode, "enhanced_sequence", "enhanced_sequence 模式正确")
TestReporter.AssertEqual(grp4.holdKeys.Length, 1, "enhanced_sequence holdKeys数=1")
TestReporter.AssertEqual(grp4.holdMode, "continuous", "enhanced_sequence holdMode=continuous")

; =================================================================
; 场景5: enhanced_sequence 无 holdMode 默认值
; =================================================================
TestReporter.Scenario("5: enhanced_sequence 无 holdMode")
config5 := Map("hotkey", "F5", "mode", "enhanced_sequence", "pressKeys", ["1", "2"], "pressDelays", [50, 50])
grp5 := SkillGroup("es2", config5)
TestReporter.AssertEqual(grp5.holdMode, "continuous", "holdMode 默认=continuous")

; =================================================================
; 场景6: hybrid 模式
; =================================================================
TestReporter.Scenario("6: hybrid 模式")
config6 := Map("hotkey", "F6", "mode", "hybrid", "groups", [Map("type", "periodic", "pressKeys", ["Space"], "intervals", [100]), Map("type", "sequence", "pressKeys", ["1", "2"], "delays", [100, 100], "seqInterval", 100)])
grp6 := SkillGroup("h1", config6)
TestReporter.AssertEqual(grp6.mode, "hybrid", "hybrid 模式正确")

; =================================================================
; 场景7: enhanced_hybrid 模式（含 holdKeys）
; =================================================================
TestReporter.Scenario("7: enhanced_hybrid 模式")
config7 := Map("hotkey", "F7", "mode", "enhanced_hybrid", "groups", [Map("type", "periodic", "pressKeys", ["Space"], "intervals", [100]), Map("type", "sequence", "pressKeys", ["1", "2"], "delays", [100, 100], "seqInterval", 100)], "holdKeys", ["Shift", "Ctrl"], "holdMode", "continuous")
grp7 := SkillGroup("eh1", config7)
TestReporter.AssertEqual(grp7.mode, "enhanced_hybrid", "enhanced_hybrid 模式正确")
TestReporter.AssertEqual(grp7.holdKeys.Length, 2, "enhanced_hybrid holdKeys数=2")

; =================================================================
; 场景8: hold 模式
; =================================================================
TestReporter.Scenario("8: hold 模式")
config8 := Map("hotkey", "F8", "mode", "hold", "holdKeys", ["RButton"], "holdDuration", 700, "autoRepeat", false, "repeatInterval", 1000)
grp8 := SkillGroup("hd1", config8)
TestReporter.AssertEqual(grp8.mode, "hold", "hold 模式正确")
TestReporter.AssertEqual(grp8.holdDuration, 700, "hold 持续时长=700")

; =================================================================
; 场景9: enhanced_sequence holdMode=periodic
; =================================================================
TestReporter.Scenario("9: enhanced_sequence holdMode=periodic")
config9 := Map("hotkey", "F9", "mode", "enhanced_sequence", "pressKeys", ["1", "2"], "pressDelays", [50, 50], "holdKeys", ["Shift"], "holdMode", "periodic")
grp9 := SkillGroup("esp1", config9)
TestReporter.AssertEqual(grp9.holdMode, "periodic", "holdMode=periodic 正确保存")

; =================================================================
; 场景10: ConfigValidator 缺少必需字段
; =================================================================
TestReporter.Scenario("10: ConfigValidator 缺少必需字段")
errorsBad := ConfigValidator.ValidateGroupOnly("bad1", Map("hotkey", "F10", "mode", "periodic"))
TestReporter.Assert(errorsBad.Length > 0, "缺少keys字段应报错")

; =================================================================
; 场景11: JSON 序列化/反序列化往返
; =================================================================
TestReporter.Scenario("11: JSON 序列化/反序列化往返")
config11 := Map("hotkey", "F11", "mode", "enhanced_periodic", "pressKeys", ["Space", "1"], "intervals", [50, 100], "holdKeys", ["Shift"], "holdMode", "continuous")
jsonStr := JSONSerializer.Stringify(config11)
TestReporter.Assert(jsonStr != "", "序列化结果非空")
parsed := JSONParser.Parse(jsonStr)
TestReporter.AssertEqual(parsed["mode"], "enhanced_periodic", "反序列化模式正确")
TestReporter.AssertEqual(parsed["holdMode"], "continuous", "反序列化holdMode正确")

; =================================================================
; 结果汇总
; =================================================================
summary := TestReporter.Summarize()
TestReporter.ExportReport()
ExitApp(summary.failed ? 1 : 0)
