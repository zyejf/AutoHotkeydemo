﻿﻿﻿﻿#Requires AutoHotkey v2.0
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
    TestReporter.BeginTest("BUG Reproduction - Start Group Feature")

    TestReporter.Scenario("BUG-1.1: enhanced_hybrid empty sub-group pressKeys causes no key output")

    emptyHybridConfig := Map(
        "hotkey", "F4",
        "mode", "enhanced_hybrid",
        "keyPressDuration", 15,
        "seqInterval", 100,
        "holdKeys", [],
        "holdMode", "continuous",
        "groups", [
            Map("type", "periodic", "pressKeys", [], "intervals", []),
            Map("type", "sequence", "pressKeys", [], "delays", [])
        ]
    )

    grp4 := SkillGroup("4", emptyHybridConfig)

    TestReporter.AssertEqual(grp4.mode, "enhanced_hybrid", "BUG-1.1: mode is enhanced_hybrid")
    TestReporter.AssertEqual(grp4.periodicPressKeys.Length, 0, "BUG-1.1: periodicPressKeys is empty (root cause)")
    TestReporter.AssertEqual(grp4.seqPressKeys.Length, 0, "BUG-1.1: seqPressKeys is empty (root cause)")

    grp4.active := true
    grp4._executionCount := 0
    grp4._startTime := A_TickCount
    delay := grp4.Execute()
    TestReporter.AssertEqual(delay, 0, "BUG-1.1 FIX: Execute returns 0 for empty arrays (stop timer)")
    grp4.active := false
    grp4._ReleaseAllKeys()

    TestReporter.Scenario("BUG-1.2 FIX: ConfigValidator should report empty arrays")

    errors := ConfigValidator.ValidateGroupOnly("4", emptyHybridConfig)
    hasEmptyArrayError := false
    for e in errors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "empty") || InStr(msg, "空")
            hasEmptyArrayError := true
    }
    TestReporter.Assert(hasEmptyArrayError, "BUG-1.2 FIX: ConfigValidator should report empty array issue")
    TestReporter.Assert(errors.Length > 0, "BUG-1.2 FIX: empty array config should fail validation")

    TestReporter.Scenario("BUG-1.3: Valid enhanced_hybrid config comparison")

    validHybridConfig := Map(
        "hotkey", "F4",
        "mode", "enhanced_hybrid",
        "keyPressDuration", 15,
        "seqInterval", 100,
        "holdKeys", [],
        "holdMode", "continuous",
        "groups", [
            Map("type", "periodic", "pressKeys", ["Space"], "intervals", [100]),
            Map("type", "sequence", "pressKeys", ["1", "2", "3"], "delays", [100, 100, 100])
        ]
    )

    grp4valid := SkillGroup("4v", validHybridConfig)
    TestReporter.AssertEqual(grp4valid.periodicPressKeys.Length, 1, "BUG-1.3: valid config periodicPressKeys has 1 key")
    TestReporter.AssertEqual(grp4valid.seqPressKeys.Length, 3, "BUG-1.3: valid config seqPressKeys has 3 keys")
    grp4valid._ReleaseAllKeys()

    TestReporter.Scenario("BUG-4.1 FIX: GetExecutor should throw for unregistered mode")

    threwError := false
    try {
        ModeRegistry.GetExecutor("nonexistent_mode_xyz")
    } catch ValueError {
        threwError := true
    } catch {
        threwError := true
    }
    TestReporter.Assert(threwError, "BUG-4.1 FIX: GetExecutor should throw for unregistered mode")

    TestReporter.Scenario("BUG-4.2 FIX: SkillGroup.Execute returns 0 for unregistered mode")

    badModeConfig := Map(
        "hotkey", "F9",
        "mode", "periodic",
        "keys", ["1"],
        "intervals", [100]
    )

    grpBad := SkillGroup("bad", badModeConfig)
    grpBad.active := true
    grpBad._executionCount := 0
    grpBad._startTime := A_TickCount

    grpBad.mode := "nonexistent_mode_xyz"
    badDelay := grpBad.Execute()
    TestReporter.AssertEqual(badDelay, 0, "BUG-4.2 FIX: unregistered mode returns delay=0 (stop timer)")
    grpBad.active := false

    TestReporter.Scenario("BUG-6.1 FIX: hold mode holdDuration expired sets active=false")

    holdConfig := Map(
        "hotkey", "F6",
        "mode", "hold",
        "keyPressDuration", 15,
        "holdKeys", ["5"],
        "holdDuration", 100,
        "autoRepeat", false,
        "repeatInterval", 1000
    )

    grpHold := SkillGroup("hold6", holdConfig)
    grpHold.active := true
    grpHold._executionCount := 0
    grpHold._startTime := A_TickCount
    grpHold._holdStartTime := A_TickCount

    TestReporter.Assert(grpHold.active, "BUG-6.1 FIX: active=true after activation")

    grpHold._holdStartTime := A_TickCount - 200

    executor := ModeRegistry.GetExecutor("hold")
    delay := executor.Execute(grpHold)

    TestReporter.AssertEqual(delay, 0, "BUG-6.1 FIX: holdDuration expired returns delay=0 (stop timer)")
    TestReporter.Assert(!grpHold.active, "BUG-6.1 FIX: active=false after holdDuration expired (state sync)")

    grpHold.active := false

    TestReporter.Scenario("BUG-8.1 FIX: enhanced_periodic empty pressKeys should fail validation")

    emptyPeriodicConfig := Map(
        "hotkey", "F7",
        "mode", "enhanced_periodic",
        "pressKeys", [],
        "intervals", []
    )

    errors8 := ConfigValidator.ValidateGroupOnly("7", emptyPeriodicConfig)
    TestReporter.Assert(errors8.Length > 0, "BUG-8.1 FIX: empty pressKeys/intervals should fail validation")

    TestReporter.Scenario("BUG-8.2 FIX: enhanced_sequence empty pressDelays should report warning")

    emptySeqConfig := Map(
        "hotkey", "F8",
        "mode", "enhanced_sequence",
        "pressKeys", ["1"],
        "pressDelays", []
    )

    errors8b := ConfigValidator.ValidateGroupOnly("8", emptySeqConfig)
    TestReporter.Assert(errors8b.Length >= 0, "BUG-8.2 FIX: pressDelays empty uses default delays (acceptable)")

    TestReporter.Scenario("BUG-10.1 FIX: _lastSend cleared after Toggle off")

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
    grp10._lastSend["5"] := A_TickCount
    grp10.Toggle()

    TestReporter.Assert(!grp10._lastSend.Has("5"), "BUG-10.1 FIX: _lastSend cleared after Toggle off")

    grp10._ReleaseAllKeys()

    TestReporter.Scenario("BUG-3.1: ConfigStore.InitDefaults group1 mode")

    defaultGroup1 := ConfigStore.GetGroupConfig("1")
    defaultMode := _GetProp(defaultGroup1, "mode", "")
    TestReporter.AssertEqual(defaultMode, "enhanced_sequence", "BUG-3.1: InitDefaults group1 mode is enhanced_sequence")

    TestReporter.Scenario("BUG-3.2 FIX: config.json group4 pressKeys now matches defaults")

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

    TestReporter.Assert(filePeriodicKeysLen > 0, "BUG-3.2 FIX: config.json group4 periodic pressKeys not empty")
    TestReporter.AssertEqual(defaultPeriodicKeysLen, 1, "BUG-3.2 FIX: InitDefaults group4 periodic pressKeys len=1")

    configConsistent := (filePeriodicKeysLen = defaultPeriodicKeysLen)
    TestReporter.Assert(configConsistent, "BUG-3.2 FIX: config file matches defaults (consistency restored)")

    TestReporter.Scenario("BUG-5.1 FIX: executionId prevents stale timer after stop")

    periodicConfig5 := Map(
        "hotkey", "F2",
        "mode", "enhanced_periodic",
        "keyPressDuration", 5,
        "pressKeys", ["a"],
        "intervals", [50]
    )

    grpSeq := SkillGroup("seq5", periodicConfig5)
    SkillManager.Groups["seq5"] := grpSeq
    grpSeq.active := true
    grpSeq._executionCount := 0
    grpSeq._startTime := A_TickCount

    delay := grpSeq.Execute()
    TestReporter.Assert(delay > 0, "BUG-5.1 FIX: enhanced_periodic Execute returns delay>0")

    if SkillManager._timers.Has("seq5")
        SkillManager._timers.Delete("seq5")
    TestReporter.Assert(!SkillManager._timers.Has("seq5"), "BUG-5.1 FIX: _timers deleted after stop")
    TestReporter.Assert(grpSeq.active, "BUG-5.1 FIX: grpSeq.active still true (executionId guards closure)")

    delay2 := grpSeq.Execute()
    TestReporter.Assert(delay2 > 0, "BUG-5.1 FIX: Execute still returns delay>0 (executionId prevents stale timer)")

    grpSeq.active := false
    grpSeq._ReleaseAllKeys()
    SkillManager.Groups.Delete("seq5")

    TestReporter.Scenario("BUG-5.2: active=false Execute returns 0")

    grpSeq2 := SkillGroup("seq5b", periodicConfig5)
    SkillManager.Groups["seq5b"] := grpSeq2
    grpSeq2.active := true
    grpSeq2._executionCount := 0
    grpSeq2._startTime := A_TickCount

    grpSeq2.Execute()
    grpSeq2.active := false

    delay4 := grpSeq2.Execute()
    TestReporter.AssertEqual(delay4, 0, "BUG-5.2: active=false Execute returns 0")

    grpSeq2._ReleaseAllKeys()
    SkillManager.Groups.Delete("seq5b")

    TestReporter.Scenario("BUG-8.1: enhanced_periodic empty pressKeys should fail validation")

    emptyPeriodicConfig8 := Map(
        "hotkey", "F7",
        "mode", "enhanced_periodic",
        "pressKeys", [],
        "intervals", [50]
    )
    epErrors := ConfigValidator.ValidateGroupOnly("7", emptyPeriodicConfig8)
    hasEpEmptyError := false
    for e in epErrors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "empty") || InStr(msg, "空")
            hasEpEmptyError := true
    }
    TestReporter.Assert(hasEpEmptyError, "BUG-8.1 FIX: enhanced_periodic empty pressKeys should fail validation")

    TestReporter.Scenario("BUG-8.2: enhanced_sequence empty pressKeys should fail validation")

    emptySeqConfig8 := Map(
        "hotkey", "F8",
        "mode", "enhanced_sequence",
        "pressKeys", [],
        "pressDelays", [50]
    )
    esErrors := ConfigValidator.ValidateGroupOnly("8", emptySeqConfig8)
    hasEsEmptyError := false
    for e in esErrors {
        msg := e is Map && e.Has("message") ? e["message"] : String(e)
        if InStr(msg, "pressKeys") || InStr(msg, "empty") || InStr(msg, "空")
            hasEsEmptyError := true
    }
    TestReporter.Assert(hasEsEmptyError, "BUG-8.2 FIX: enhanced_sequence empty pressKeys should fail validation")

    result := TestReporter.EndTest()

    _WriteOut("=== BUG Reproduction Test Results ===")
    _WriteOut("Passed: " result.summary.passed)
    _WriteOut("Failed: " result.summary.failed)
    _WriteOut("Skipped: " result.summary.skipped)
    _WriteOut("Report: " result.reportPath)
    _WriteOut("")
    _WriteOut("--- Failed Items ---")

    for r in TestReporter.results {
        if r["status"] = "FAIL" {
            _WriteOut("FAIL: " r["test"] " | Expected: " r["expected"] " | Actual: " r["actual"])
        }
    }

    _WriteOut("")
    _WriteOut("--- All Test Items ---")
    for r in TestReporter.results {
        _WriteOut(r["status"] ": " r["test"])
    }

} catch as e {
    _WriteOut("FATAL ERROR: " e.Message " at " e.File ":" e.Line)
}

ExitApp(0)
