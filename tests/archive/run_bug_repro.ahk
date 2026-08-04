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
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/mode_registry.ahk"
#Include "../domain/skill_group.ahk"
#Include "../domain/skill_manager.ahk"

OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))

_GetProp(obj, key, default) {
    if obj is Map
        return obj.Has(key) ? obj[key] : default
    return default
}

outFile := "D:\1demo\AutoHotkeydemo\tests\bug_repro_results.txt"
if FileExist(outFile)
    FileDelete(outFile)

_WriteOut(msg) {
    FileAppend(msg "`n", outFile, "UTF-8")
}

_InitTestDeps() {
    ErrorSystem.Init()
    ModeRegistry._Init()
    ConfigStore.InitDefaults()
    JSONLogger.Init()
    DebugLogger.Init()
    SkillGroup.Logger := DebugLogger
    SkillGroup.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
    SkillGroup.ConfigStore := ConfigStore
    SkillGroup.IsKeyAllowed := ((key, groupId) => true)
    SkillGroup.RegisterHoldKey := ((key, groupId) => true)
    SkillGroup.UnregisterHoldKey := ((key, groupId) => "")
    SkillManager.Logger := JSONLogger
    SkillManager.Notifier := {Notify: (msg, type) => "", ShowBriefInfo: (count, em) => ""}
    SkillManager.ConfigStore := ConfigStore
}

try {
    _InitTestDeps()
    TestReporter.BeginTest("BUG复现测试 - 启动分组功能缺陷")

    ; =================================================================
    ; BUG-1: 分组4空配置导致 enhanced_hybrid 静默无操作 (P0)
    ; =================================================================
    TestReporter.Scenario("BUG-1.1: enhanced_hybrid 空子组 pressKeys 导致无按键输出")

    emptyHybridConfig := Map(
        "hotkey", "F4",
        "mode", "enhanced_hybrid",
        "keyPressDuration", 15,
        "seqInterval", 100,
        "holdKeys", ["Shift", "Ctrl"],
        "holdMode", "continuous",
        "groups", [
            Map("type", "periodic", "pressKeys", [], "intervals", []),
            Map("type", "sequence", "pressKeys", [], "delays", [])
        ]
    )

    grp4 := SkillGroup("4", emptyHybridConfig)

    TestReporter.AssertEqual(grp4.mode, "enhanced_hybrid", "BUG-1.1: 分组模式为 enhanced_hybrid")
    TestReporter.AssertEqual(grp4.periodicPressKeys.Length, 0, "BUG-1.1: periodicPressKeys 为空数组（问题根因）")
    TestReporter.AssertEqual(grp4.seqPressKeys.Length, 0, "BUG-1.1: seqPressKeys 为空数组（问题根因）")

    grp4.active := true
    grp4._executionCount := 0
    grp4._startTime := A_TickCount
    delay := grp4.Execute()
    TestReporter.Assert(delay > 0, "BUG-1.1: Execute 返回 delay>0 但实际无按键发出（定时器空转）")
    TestReporter.AssertEqual(grp4._executionCount, 1, "BUG-1.1: 执行计数增加但无实际效果")
    grp4.active := false
    grp4._ReleaseAllKeys()

    TestReporter.Scenario("BUG-1.2: ConfigValidator 不校验空数组，允许无效配置通过")

    errors := ConfigValidator.ValidateGroupOnly("4", emptyHybridConfig)
    hasEmptyArrayError := false
    for e in errors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "空") || InStr(msg, "empty")
            hasEmptyArrayError := true
    }
    TestReporter.Assert(!hasEmptyArrayError, "BUG-1.2: ConfigValidator 未报告空数组问题（验证缺失）")
    TestReporter.AssertEqual(errors.Length, 0, "BUG-1.2: 空数组配置通过验证 0 个错误（问题确认）")

    TestReporter.Scenario("BUG-1.3: 有效 enhanced_hybrid 配置对比 - 应有按键输出")

    validHybridConfig := Map(
        "hotkey", "F4",
        "mode", "enhanced_hybrid",
        "keyPressDuration", 15,
        "seqInterval", 100,
        "holdKeys", ["Shift"],
        "holdMode", "continuous",
        "groups", [
            Map("type", "periodic", "pressKeys", ["Space"], "intervals", [100]),
            Map("type", "sequence", "pressKeys", ["1", "2", "3"], "delays", [100, 100, 100])
        ]
    )

    grp4valid := SkillGroup("4v", validHybridConfig)
    TestReporter.AssertEqual(grp4valid.periodicPressKeys.Length, 1, "BUG-1.3: 有效配置 periodicPressKeys 有1个键")
    TestReporter.AssertEqual(grp4valid.seqPressKeys.Length, 3, "BUG-1.3: 有效配置 seqPressKeys 有3个键")
    grp4valid._ReleaseAllKeys()

    ; =================================================================
    ; BUG-4: ModeRegistry.GetExecutor 返回空字符串导致崩溃 (P1)
    ; =================================================================
    TestReporter.Scenario("BUG-4.1: GetExecutor 对未注册模式返回空字符串")

    unknownExecutor := ModeRegistry.GetExecutor("nonexistent_mode_xyz")
    TestReporter.AssertEqual(unknownExecutor, "", "BUG-4.1: 未注册模式返回空字符串（非对象）")

    TestReporter.Scenario("BUG-4.2: SkillGroup.Execute 对未注册模式崩溃")

    badModeConfig := Map(
        "hotkey", "F9",
        "mode", "nonexistent_mode_xyz",
        "keyPressDuration", 15,
        "pressKeys", ["1"],
        "pressDelays", [100]
    )

    grpBad := SkillGroup("bad", badModeConfig)
    grpBad.active := true
    grpBad._executionCount := 0
    grpBad._startTime := A_TickCount

    crashed := false
    try {
        grpBad.Execute()
    } catch as e {
        crashed := true
    }
    TestReporter.Assert(crashed, "BUG-4.2: 未注册模式 Execute 导致崩溃（问题确认）")
    grpBad.active := false
    grpBad._ReleaseAllKeys()

    ; =================================================================
    ; BUG-6: HoldExecutor 返回 0 时定时器停止但 active 仍为 true (P1)
    ; =================================================================
    TestReporter.Scenario("BUG-6.1: hold 模式 holdDuration 到期后 active 仍为 true")

    holdConfig := Map(
        "hotkey", "F6",
        "mode", "hold",
        "keyPressDuration", 15,
        "holdKeys", ["RButton"],
        "holdDuration", 100,
        "autoRepeat", false,
        "repeatInterval", 1000
    )

    grpHold := SkillGroup("hold6", holdConfig)
    grpHold.active := true
    grpHold._executionCount := 0
    grpHold._startTime := A_TickCount
    grpHold._holdStartTime := A_TickCount

    TestReporter.Assert(grpHold.active, "BUG-6.1: 激活后 active=true")

    grpHold._holdStartTime := A_TickCount - 200

    executor := ModeRegistry.GetExecutor("hold")
    delay := executor.Execute(grpHold)

    TestReporter.AssertEqual(delay, 0, "BUG-6.1: holdDuration 到期后返回 delay=0（定时器将停止）")
    TestReporter.Assert(grpHold.active, "BUG-6.1: 但 active 仍为 true（状态不同步问题确认）")

    grpHold.active := false
    grpHold._ReleaseAllKeys()

    ; =================================================================
    ; BUG-8: ConfigValidator 不校验空数组 (轻微)
    ; =================================================================
    TestReporter.Scenario("BUG-8.1: enhanced_periodic 空 pressKeys 通过验证")

    emptyPeriodicConfig := Map(
        "hotkey", "F7",
        "mode", "enhanced_periodic",
        "pressKeys", [],
        "intervals", []
    )

    errors8 := ConfigValidator.ValidateGroupOnly("7", emptyPeriodicConfig)
    TestReporter.AssertEqual(errors8.Length, 0, "BUG-8.1: 空 pressKeys/intervals 通过验证（应报错）")

    TestReporter.Scenario("BUG-8.2: enhanced_sequence 空 pressDelays 通过验证")

    emptySeqConfig := Map(
        "hotkey", "F8",
        "mode", "enhanced_sequence",
        "pressKeys", ["1"],
        "pressDelays", []
    )

    errors8b := ConfigValidator.ValidateGroupOnly("8", emptySeqConfig)
    TestReporter.AssertEqual(errors8b.Length, 0, "BUG-8.2: 空 pressDelays 通过验证（应报错）")

    ; =================================================================
    ; BUG-10: _SendKey 防抖导致快速重激活时首次按键延迟 (轻微)
    ; =================================================================
    TestReporter.Scenario("BUG-10.1: 快速停用再激活时 _lastSend 未清空")

    periodicConfig10 := Map(
        "hotkey", "F5",
        "mode", "enhanced_periodic",
        "keyPressDuration", 15,
        "pressKeys", ["5"],
        "intervals", [50]
    )

    grp10 := SkillGroup("10", periodicConfig10)
    grp10.active := true
    grp10._executionCount := 0
    grp10._startTime := A_TickCount
    grp10.Execute()
    grp10.active := false

    TestReporter.Assert(grp10._lastSend.Has("5"), "BUG-10.1: 停用后 _lastSend 仍包含键 '5'（未清空）")

    grp10._ReleaseAllKeys()

    ; =================================================================
    ; BUG-3: config.json 与 ConfigStore.InitDefaults() 配置不一致 (P1)
    ; =================================================================
    TestReporter.Scenario("BUG-3.1: ConfigStore.InitDefaults 分组1模式")

    defaultGroup1 := ConfigStore.GetGroupConfig("1")
    defaultMode := _GetProp(defaultGroup1, "mode", "")
    TestReporter.AssertEqual(defaultMode, "enhanced_sequence", "BUG-3.1: InitDefaults 分组1模式为 enhanced_sequence")

    TestReporter.Scenario("BUG-3.2: config.json 分组4 pressKeys 为空（与默认值不同）")

    configFromFile := JSONParser.LoadFile(A_ScriptDir "\..\config.json")
    fileGroupSettings := configFromFile.Has("GroupSettings") ? configFromFile["GroupSettings"] : Map()
    fileGroup4 := fileGroupSettings is Map && fileGroupSettings.Has("4") ? fileGroupSettings["4"] : Map()
    fileGroup4Groups := _GetProp(fileGroup4, "groups", [])
    filePeriodicKeysLen := -1

    if fileGroup4Groups is Array && fileGroup4Groups.Length >= 2 {
        g0 := fileGroup4Groups[1]
        pk := _GetProp(g0, "pressKeys", "")
        filePeriodicKeysLen := pk is Array ? pk.Length : -2
    }

    defaultGroup4 := ConfigStore.GetGroupConfig("4")
    defaultGroup4Groups := _GetProp(defaultGroup4, "groups", [])
    defaultPeriodicKeysLen := -1

    if defaultGroup4Groups is Array && defaultGroup4Groups.Length >= 2 {
        dg0 := defaultGroup4Groups[1]
        dpk := _GetProp(dg0, "pressKeys", "")
        defaultPeriodicKeysLen := dpk is Array ? dpk.Length : -2
    }

    TestReporter.AssertEqual(filePeriodicKeysLen, 0, "BUG-3.2: config.json 分组4 periodic pressKeys 长度=0")
    TestReporter.AssertEqual(defaultPeriodicKeysLen, 1, "BUG-3.2: InitDefaults 分组4 periodic pressKeys 长度=1")

    configDifferent := (filePeriodicKeysLen != defaultPeriodicKeysLen)
    TestReporter.Assert(configDifferent, "BUG-3.2: 配置文件与默认配置不一致（问题确认）")

    ; =================================================================
    ; BUG-5: 定时器闭包竞态条件 - 逻辑验证 (P1)
    ; =================================================================
    TestReporter.Scenario("BUG-5.1: Execute 返回 delay>0 但分组已被外部停止")

    seqConfig := Map(
        "hotkey", "F2",
        "mode", "sequence",
        "keyPressDuration", 5,
        "keys", ["1", "2"],
        "delays", [50, 50]
    )

    grpSeq := SkillGroup("seq5", seqConfig)
    SkillManager.Groups["seq5"] := grpSeq
    grpSeq.active := true
    grpSeq._executionCount := 0
    grpSeq._startTime := A_TickCount

    delay := grpSeq.Execute()
    TestReporter.Assert(delay > 0, "BUG-5.1: sequence Execute 返回 delay>0")

    SkillManager._timers.Delete("seq5")
    TestReporter.Assert(!SkillManager._timers.Has("seq5"), "BUG-5.1: _timers 已删除")
    TestReporter.Assert(grpSeq.active, "BUG-5.1: 但 grpSeq.active 仍为 true（闭包仍会执行）")

    delay2 := grpSeq.Execute()
    TestReporter.Assert(delay2 > 0, "BUG-5.1: 即使 _timers 已删除，Execute 仍返回 delay>0")

    grpSeq.active := false
    grpSeq._ReleaseAllKeys()
    SkillManager.Groups.Delete("seq5")

    TestReporter.Scenario("BUG-5.2: active=false 时 Execute 返回 0")

    grpSeq2 := SkillGroup("seq5b", seqConfig)
    SkillManager.Groups["seq5b"] := grpSeq2
    grpSeq2.active := true
    grpSeq2._executionCount := 0
    grpSeq2._startTime := A_TickCount

    grpSeq2.Execute()
    grpSeq2.active := false

    delay4 := grpSeq2.Execute()
    TestReporter.AssertEqual(delay4, 0, "BUG-5.2: active=false 时 Execute 返回 0")

    grpSeq2._ReleaseAllKeys()
    SkillManager.Groups.Delete("seq5b")

    ; =================================================================
    ; 汇总
    ; =================================================================
    result := TestReporter.EndTest()

    _WriteOut("=== BUG 复现测试结果 ===")
    _WriteOut("通过: " result.summary.passed)
    _WriteOut("失败: " result.summary.failed)
    _WriteOut("跳过: " result.summary.skipped)
    _WriteOut("报告: " result.reportPath)
    _WriteOut("")
    _WriteOut("--- 失败项详情 ---")

    for r in TestReporter.results {
        if r["status"] = "FAIL" {
            _WriteOut("FAIL: " r["test"] " | 期望: " r["expected"] " | 实际: " r["actual"])
        }
    }

    _WriteOut("")
    _WriteOut("--- 全部测试项 ---")
    for r in TestReporter.results {
        _WriteOut(r["status"] ": " r["test"])
    }

} catch as e {
    _WriteOut("FATAL ERROR: " e.Message " at " e.File ":" e.Line)
}

ExitApp(0)
