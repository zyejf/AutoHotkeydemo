; =================================================================
; 测试层 - Domain 层完整测试套件 v2.0
; 说明: 覆盖 interfaces/ModeRegistry/SkillGroup/SkillManager 全部公开方法
;       包含正常路径、边界值、异常处理
; 运行: AutoHotkey.exe tests\test_domain_full.ahk
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
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/debug_logger.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"

OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))

_InitTestDeps() {
    ErrorSystem.Init()
    ModeRegistry._Init()
    ConfigStore.InitDefaults()
    JSONLogger.Init()
    DebugLogger.Init()
    SkillGroup.Logger := DebugLogger
    SkillGroup.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
    SkillGroup.ConfigStore := ConfigStore
    SkillGroup.IsKeyAllowed := ((key, groupId) => SkillManager.IsKeyAllowed(key, groupId))
    SkillGroup.RegisterHoldKey := ((key, groupId) => SkillManager.RegisterHoldKey(key, groupId))
    SkillGroup.UnregisterHoldKey := ((key, groupId) => SkillManager.UnregisterHoldKey(key, groupId))
    SkillManager.Logger := JSONLogger
    SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
    SkillManager.ConfigStore := ConfigStore
}

_InitTestDeps()
TestReporter.BeginTest("test_domain_full.ahk")

; =================================================================
; 1. 接口契约测试
; =================================================================
TestReporter.Scenario("1.1 ILogger 抽象方法抛出异常")
TestReporter.AssertThrows(() => ILogger().Log("DEBUG", "test"), "抽象方法", "ILogger.Log 抛异常")

TestReporter.Scenario("1.2 INotifier 抽象方法抛出异常")
TestReporter.AssertThrows(() => INotifier().Notify("test"), "抽象方法", "INotifier.Notify 抛异常")
TestReporter.AssertThrows(() => INotifier().ShowBriefInfo(0, false), "抽象方法", "INotifier.ShowBriefInfo 抛异常")

TestReporter.Scenario("1.3 IConfigStore 抽象方法抛出异常")
TestReporter.AssertThrows(() => IConfigStore().Load(), "抽象方法", "IConfigStore.Load 抛异常")
TestReporter.AssertThrows(() => IConfigStore().Save({}), "抽象方法", "IConfigStore.Save 抛异常")
TestReporter.AssertThrows(() => IConfigStore().Get("k"), "抽象方法", "IConfigStore.Get 抛异常")
TestReporter.AssertThrows(() => IConfigStore().Set("k", "v"), "抽象方法", "IConfigStore.Set 抛异常")
TestReporter.AssertThrows(() => IConfigStore().Has("k"), "抽象方法", "IConfigStore.Has 抛异常")

TestReporter.Scenario("1.4 IExecutor 抽象方法抛出异常")
TestReporter.AssertThrows(() => IExecutor().Execute(""), "抽象方法", "IExecutor.Execute 抛异常")
TestReporter.AssertThrows(() => IExecutor().GetModeName(), "抽象方法", "IExecutor.GetModeName 抛异常")

TestReporter.Scenario("1.5 IHealthChecker/IEventHook 抽象方法抛出异常")
TestReporter.AssertThrows(() => IHealthChecker().Check(), "抽象方法", "IHealthChecker.Check 抛异常")
TestReporter.AssertThrows(() => IEventHook().OnEvent("test", ""), "抽象方法", "IEventHook.OnEvent 抛异常")

; =================================================================
; 2. ModeRegistry 完整测试
; =================================================================
TestReporter.Scenario("2.1 ModeRegistry 7 种内置模式注册")
TestReporter.Assert(ModeRegistry.HasMode("periodic"), "periodic 已注册")
TestReporter.Assert(ModeRegistry.HasMode("sequence"), "sequence 已注册")
TestReporter.Assert(ModeRegistry.HasMode("hybrid"), "hybrid 已注册")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_periodic"), "enhanced_periodic 已注册")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_sequence"), "enhanced_sequence 已注册")
TestReporter.Assert(ModeRegistry.HasMode("enhanced_hybrid"), "enhanced_hybrid 已注册")
TestReporter.Assert(ModeRegistry.HasMode("hold"), "hold 已注册")

TestReporter.Scenario("2.2 ModeRegistry GetRegisteredModes")
modes := ModeRegistry.GetRegisteredModes()
TestReporter.Assert(modes.Length >= 7, "GetRegisteredModes 返回至少 7 种模式，实际=" modes.Length)

TestReporter.Scenario("2.3 ModeRegistry GetModeDisplayNames")
displayNames := ModeRegistry.GetModeDisplayNames()
TestReporter.Assert(displayNames is Map, "GetModeDisplayNames 返回 Map")
TestReporter.Assert(displayNames.Has("periodic"), "displayNames 包含 periodic")

TestReporter.Scenario("2.4 ModeRegistry GetExecutor")
exec := ModeRegistry.GetExecutor("periodic")
TestReporter.Assert(exec is IExecutor, "GetExecutor(periodic) 返回 IExecutor")
TestReporter.AssertEqual(exec.GetModeName(), "periodic", "periodic 执行器名称正确")

execEmpty := ModeRegistry.GetExecutor("nonexistent_mode")
TestReporter.AssertEqual(execEmpty, "", "不存在的模式返回空字符串")

TestReporter.Scenario("2.5 ModeRegistry Register/Unregister")
ModeRegistry.Register("test_temp_mode", PeriodicExecutor(), {name: "临时测试"})
TestReporter.Assert(ModeRegistry.HasMode("test_temp_mode"), "临时模式注册成功")
meta := ModeRegistry.GetModeMeta("test_temp_mode")
TestReporter.Assert(meta is Map, "GetModeMeta 返回 Map")
TestReporter.Assert(meta.Has("name"), "meta 包含 name 字段")
ModeRegistry.Unregister("test_temp_mode")
TestReporter.Assert(!ModeRegistry.HasMode("test_temp_mode"), "临时模式已注销")

TestReporter.Scenario("2.6 ModeRegistry ValidateModeConfig")
validResult := ModeRegistry.ValidateModeConfig("periodic", {keys: ["a"], intervals: [50]})
TestReporter.Assert(validResult is Array, "ValidateModeConfig 返回 Array")
TestReporter.Assert(validResult.Length = 0, "有效配置返回空错误列表，实际=" validResult.Length)

invalidResult := ModeRegistry.ValidateModeConfig("periodic", {})
TestReporter.Assert(invalidResult.Length > 0, "无效配置返回非空错误列表")

TestReporter.Scenario("2.7 ModeRegistry ValidateModeConfig requiresNonEmpty")
emptyConfig := Map("pressKeys", [], "intervals", [50])
errorsNE := ModeRegistry.ValidateModeConfig("enhanced_periodic", emptyConfig)
TestReporter.Assert(errorsNE.Length > 0, "ValidateModeConfig should report empty pressKeys via requiresNonEmpty")

validConfig := Map("pressKeys", ["a"], "intervals", [50])
errorsOK := ModeRegistry.ValidateModeConfig("enhanced_periodic", validConfig)
TestReporter.AssertEqual(errorsOK.Length, 0, "ValidateModeConfig should pass for non-empty pressKeys")

; =================================================================
; 3. SkillGroup 完整测试
; =================================================================
TestReporter.Scenario("3.1 SkillGroup 构造函数 - periodic 模式")
sg1 := SkillGroup("test_p1", {mode: "periodic", hotkey: "F1", keys: ["a", "b"], intervals: [50, 100]})
TestReporter.AssertEqual(sg1.mode, "periodic", "mode = periodic")
TestReporter.AssertEqual(sg1.hotkey, "F1", "hotkey = F1")
TestReporter.AssertEqual(sg1.keys.Length, 2, "keys.Length = 2")
TestReporter.AssertEqual(sg1.intervals.Length, 2, "intervals.Length = 2")
TestReporter.AssertEqual(sg1.active, false, "初始状态 inactive")

TestReporter.Scenario("3.2 SkillGroup 构造函数 - sequence 模式")
sg2 := SkillGroup("test_s1", {mode: "sequence", hotkey: "F2", keys: ["1", "2", "3"], delays: [100, 200, 300]})
TestReporter.AssertEqual(sg2.mode, "sequence", "mode = sequence")
TestReporter.AssertEqual(sg2.keys.Length, 3, "keys.Length = 3")
TestReporter.AssertEqual(sg2.delays.Length, 3, "delays.Length = 3")

TestReporter.Scenario("3.3 SkillGroup 构造函数 - hybrid 模式")
sg3 := SkillGroup("test_h1", {mode: "hybrid", hotkey: "F3", groups: [{type: "periodic", pressKeys: ["a"], intervals: [50]}, {type: "sequence", pressKeys: ["1"], delays: [100]}]})
TestReporter.AssertEqual(sg3.mode, "hybrid", "mode = hybrid")
TestReporter.AssertEqual(sg3.groups.Length, 2, "groups.Length = 2")

TestReporter.Scenario("3.4 SkillGroup 构造函数 - hold 模式")
sg4 := SkillGroup("test_hold1", {mode: "hold", hotkey: "F4", holdKeys: ["Shift"], holdDuration: 1000})
TestReporter.AssertEqual(sg4.mode, "hold", "mode = hold")
TestReporter.AssertEqual(sg4.holdKeys.Length, 1, "holdKeys.Length = 1")
TestReporter.AssertEqual(sg4.holdDuration, 1000, "holdDuration = 1000")

TestReporter.Scenario("3.5 SkillGroup 构造函数 - enhanced_periodic 模式")
sg5 := SkillGroup("test_ep1", {mode: "enhanced_periodic", hotkey: "F5", pressKeys: ["a", "b"], intervals: [50, 100]})
TestReporter.AssertEqual(sg5.mode, "enhanced_periodic", "mode = enhanced_periodic")
TestReporter.AssertEqual(sg5.pressKeys.Length, 2, "pressKeys.Length = 2")

TestReporter.Scenario("3.6 SkillGroup 构造函数 - enhanced_sequence 模式")
sg6 := SkillGroup("test_es1", {mode: "enhanced_sequence", hotkey: "F6", pressKeys: ["1", "2"], pressDelays: [100, 200]})
TestReporter.AssertEqual(sg6.mode, "enhanced_sequence", "mode = enhanced_sequence")
TestReporter.AssertEqual(sg6.pressKeys.Length, 2, "pressKeys.Length = 2")

TestReporter.Scenario("3.7 SkillGroup 构造函数 - enhanced_hybrid 模式")
sg7 := SkillGroup("test_eh1", {mode: "enhanced_hybrid", hotkey: "F7", groups: [{type: "periodic", pressKeys: ["a"], intervals: [50]}]})
TestReporter.AssertEqual(sg7.mode, "enhanced_hybrid", "mode = enhanced_hybrid")

TestReporter.Scenario("3.8 SkillGroup keyPressDuration 边界值")
sgMin := SkillGroup("test_kpd_min", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 1})
TestReporter.AssertEqual(sgMin.keyPressDuration, 5, "keyPressDuration=1 修正为 5")

sgMax := SkillGroup("test_kpd_max", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 500})
TestReporter.AssertEqual(sgMax.keyPressDuration, 100, "keyPressDuration=500 修正为 100")

sgNorm := SkillGroup("test_kpd_norm", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50], keyPressDuration: 50})
TestReporter.AssertEqual(sgNorm.keyPressDuration, 50, "keyPressDuration=50 正常保留")

TestReporter.Scenario("3.9 SkillGroup 默认值")
sgDef := SkillGroup("test_def", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]})
TestReporter.AssertEqual(sgDef.keyPressDuration, 15, "默认 keyPressDuration = 15")
TestReporter.AssertEqual(sgDef.holdMode, "continuous", "默认 holdMode = continuous")

TestReporter.Scenario("3.10 SkillGroup _IsValidKeyName")
TestReporter.Assert(SkillGroup._IsValidKeyName("a"), "单字母键名有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("F1"), "F1 功能键有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("F12"), "F12 功能键有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("Space"), "Space 特殊键有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("^a"), "Ctrl 修饰键有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("+a"), "Shift 修饰键有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("!a"), "Alt 修饰键有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("#a"), "Win 修饰键有效")
TestReporter.Assert(!SkillGroup._IsValidKeyName(""), "空字符串无效")
TestReporter.Assert(SkillGroup._IsValidKeyName("LButton"), "LButton 有效")
TestReporter.Assert(SkillGroup._IsValidKeyName("Numpad0"), "Numpad0 有效")

TestReporter.Scenario("3.11 SkillGroup GetStatus")
sgSt := SkillGroup("test_status", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]})
status := sgSt.GetStatus()
TestReporter.Assert(status is Map, "GetStatus 返回 Map")
TestReporter.Assert(status.Has("active"), "status 包含 active")
TestReporter.Assert(status.Has("executionCount"), "status 包含 executionCount")
TestReporter.AssertEqual(status["active"], false, "初始 active = false")

TestReporter.Scenario("3.12 SkillGroup Toggle 防抖")
sgTog := SkillGroup("test_toggle", {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]})
result1 := sgTog.Toggle()
TestReporter.AssertEqual(sgTog.active, true, "第一次 Toggle 激活")
result2 := sgTog.Toggle()
TestReporter.AssertEqual(result2, -1, "防抖期间 Toggle 返回 -1")

TestReporter.Scenario("3.13 SkillGroup _CheckMouseKeys")
sgMouse := SkillGroup("test_mouse", {mode: "periodic", hotkey: "F1", keys: ["LButton", "a"], intervals: [50, 50]})
TestReporter.AssertEqual(sgMouse._isMouse.Length, 2, "鼠标检测数组长度 = 2")
TestReporter.AssertEqual(sgMouse._isMouse[1], true, "LButton 检测为鼠标键")
TestReporter.AssertEqual(sgMouse._isMouse[2], false, "a 检测为非鼠标键")

; =================================================================
; 4. SkillManager 完整测试
; =================================================================
TestReporter.Scenario("4.1 SkillManager 初始状态")
TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "初始 EmergencyMode = false")
TestReporter.AssertEqual(SkillManager.HoldModeEnabled, true, "初始 HoldModeEnabled = true")
TestReporter.Assert(SkillManager.Groups is Map, "Groups 是 Map")

TestReporter.Scenario("4.2 SkillManager GetActiveCount")
TestReporter.AssertEqual(SkillManager.GetActiveCount(), 0, "初始 GetActiveCount = 0")

TestReporter.Scenario("4.3 SkillManager GetTimerCount")
TestReporter.AssertEqual(SkillManager.GetTimerCount(), 0, "初始 GetTimerCount = 0")

TestReporter.Scenario("4.4 SkillManager Emergency/ResetEmergency")
SkillManager.EmergencyMode := true
TestReporter.AssertEqual(SkillManager.EmergencyMode, true, "Emergency 后 EmergencyMode = true")
SkillManager.EmergencyMode := false
TestReporter.AssertEqual(SkillManager.EmergencyMode, false, "ResetEmergency 后 EmergencyMode = false")

TestReporter.Scenario("4.5 SkillManager RegisterHoldKey/UnregisterHoldKey")
SkillManager.RegisterHoldKey("Shift", "test_grp")
TestReporter.Assert(SkillManager.HoldKeyRegistry.Has("Shift"), "HoldKeyRegistry 包含 Shift")
TestReporter.AssertEqual(SkillManager.HoldKeyRegistry["Shift"], "test_grp", "HoldKeyRegistry[Shift] = test_grp")
SkillManager.UnregisterHoldKey("Shift", "test_grp")
TestReporter.Assert(!SkillManager.HoldKeyRegistry.Has("Shift"), "UnregisterHoldKey 后 Shift 已移除")

TestReporter.Scenario("4.6 SkillManager IsKeyAllowed - 无冲突")
result := SkillManager.IsKeyAllowed("a", "grp1")
TestReporter.AssertEqual(result, true, "无冲突时 IsKeyAllowed 返回 true")

TestReporter.Scenario("4.7 SkillManager IsKeyAllowed - 有冲突")
SkillManager.RegisterHoldKey("b", "grp2")
result := SkillManager.IsKeyAllowed("b", "grp1")
TestReporter.AssertEqual(result, false, "冲突时 IsKeyAllowed 返回 false")
SkillManager.UnregisterHoldKey("b", "grp2")

TestReporter.Scenario("4.8 SkillManager RegisterEventHook")
hookCalled := false
testHook := {
    OnEvent: (event, data) => (hookCalled := true)
}
SkillManager.RegisterEventHook(testHook)
TestReporter.Assert(SkillManager._eventHooks.Length > 0, "事件钩子已注册")

TestReporter.Scenario("4.9 SkillManager InvalidateHoldSettingsCache")
SkillManager.InvalidateHoldSettingsCache()
TestReporter.AssertEqual(SkillManager._holdSettingsDirty, true, "缓存已标记为脏")

TestReporter.Scenario("4.10 SkillManager ShowStatus 不崩溃")
TestReporter.AssertNoThrow(() => SkillManager.ShowStatus(), "ShowStatus 不抛出异常")

TestReporter.Scenario("4.11 SkillManager ReleaseAllHolds 不崩溃")
TestReporter.AssertNoThrow(() => SkillManager.ReleaseAllHolds(), "ReleaseAllHolds 不抛出异常")

TestReporter.Scenario("4.12 SkillManager ToggleHoldMode")
prevMode := SkillManager.HoldModeEnabled
SkillManager.ToggleHoldMode()
TestReporter.AssertEqual(SkillManager.HoldModeEnabled, !prevMode, "ToggleHoldMode 切换状态")
SkillManager.ToggleHoldMode()
TestReporter.AssertEqual(SkillManager.HoldModeEnabled, prevMode, "再次 ToggleHoldMode 恢复状态")

TestReporter.Scenario("4.13 SkillManager OnExit 不崩溃")
TestReporter.AssertNoThrow(() => SkillManager.OnExit(), "OnExit 不抛出异常")

; =================================================================
; 5. SkillGroup + ModeRegistry 集成
; =================================================================
TestReporter.Scenario("5.1 所有 7 种模式通过 ModeRegistry 获取执行器")
modeList := ["periodic", "sequence", "hybrid", "enhanced_periodic", "enhanced_sequence", "enhanced_hybrid", "hold"]
for mode in modeList {
    exec := ModeRegistry.GetExecutor(mode)
    TestReporter.Assert(exec is IExecutor, mode " 执行器是 IExecutor 实例")
    TestReporter.AssertEqual(exec.GetModeName(), mode, mode " GetModeName() 正确")
}

TestReporter.Scenario("5.2 SkillGroup 各模式构造后 mode 属性正确")
configMap := Map()
configMap["periodic"] := {mode: "periodic", hotkey: "F1", keys: ["a"], intervals: [50]}
configMap["sequence"] := {mode: "sequence", hotkey: "F2", keys: ["a"], delays: [100]}
configMap["hybrid"] := {mode: "hybrid", hotkey: "F3", groups: [{type: "periodic", pressKeys: ["a"], intervals: [50]}]}
configMap["enhanced_periodic"] := {mode: "enhanced_periodic", hotkey: "F4", pressKeys: ["a"], intervals: [50]}
configMap["enhanced_sequence"] := {mode: "enhanced_sequence", hotkey: "F5", pressKeys: ["a"], pressDelays: [100]}
configMap["enhanced_hybrid"] := {mode: "enhanced_hybrid", hotkey: "F6", groups: [{type: "periodic", pressKeys: ["a"], intervals: [50]}]}
configMap["hold"] := {mode: "hold", hotkey: "F7", holdKeys: ["a"], holdDuration: 1000}

for mode, config in configMap {
    sg := SkillGroup("integ_" mode, config)
    TestReporter.AssertEqual(sg.mode, mode, mode " SkillGroup.mode 正确")
}

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
