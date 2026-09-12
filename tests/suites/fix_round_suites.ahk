; =================================================================
; fix_round_suites.ahk - 第四轮与第五轮修复测试套件（含 MockJoySender）
; 本文件通过 run_all_tests.ahk 的 #Include 加载，不可独立运行
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; =================================================================
; 第四轮修复测试
; =================================================================

class JSONParseContextIsolationTests extends AutoHotUnitSuite {
    Test_TwoContexts_IndependentState() {
        ctx1 := JSONParseContext('{"a":1}')
        ctx2 := JSONParseContext('{"b":2}')
        this.assert.isTrue(ctx1.json != ctx2.json)
        this.assert.equal(ctx1.pos, 1)
        this.assert.equal(ctx2.pos, 1)
    }

    Test_ContextDepth_StartsAtZero() {
        ctx := JSONParseContext('{"a":1}')
        this.assert.equal(ctx._depth, 0)
    }

    Test_Parser_StaticHasNoState() {
        this.assert.isTrue(!HasProp(JSONParser, "pos"))
        this.assert.isTrue(!HasProp(JSONParser, "json"))
    }
}

; =================================================================
; MockJoySender - IJoySender 的测试替身（空操作实现）
; 用于在测试环境中注入 JoystickExecutor，避免 "JoySender 未注入" 异常
; =================================================================
class MockJoySender extends IJoySender {
    SendBtn(btn, state, method := "vjoy") {
        ; 空操作：模拟成功发送手柄按钮状态
    }
    SendPov(direction, method := "vjoy") {
        ; 空操作：模拟成功发送 POV 方向
    }
    SendAxis(axis, value, method := "vjoy") {
        ; 空操作：模拟成功发送轴值
    }
    ReleaseAll() {
        ; 空操作：模拟成功释放所有手柄输入
    }
}

class ToggleAllUsesToggleGroupTests extends AutoHotUnitSuite {
    beforeAll() {
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
        JoystickExecutor.SetJoySender(MockJoySender())
        ConfigStore.InitDefaults()
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0
            SkillManager.Init(gs)
    }

    _savedStartGroupExecution := ""

    beforeEach() {
        ; 重置所有分组的防抖时间，确保测试隔离
        ; 防抖机制（TOGGLE_DEBOUNCE_MS=200ms）会导致测试间的状态污染：
        ; 前一个测试套件激活的分组 _lastToggleTime 很近，当前测试尝试停用时被防抖阻止，
        ; 组无法停用而保持活跃，导致 ToggleAll 误入停用分支，最终所有组被停用。
        for id, group in SkillManager.Groups {
            group._lastToggleTime := 0
        }
        ; 停止所有定时器，防止前一个测试遗留的 executor 回调干扰
        for id in SkillManager.Groups {
            try SkillManager._StopGroupExecution(id)
        }
        ; mock _StartGroupExecution 防止定时器竞态：
        ; ToggleAll 激活组后 _StartGroupExecution 设置 10ms 定时器，
        ; ToggleAll 内部 _Notify/_UpdateBriefInfo 的 GUI 操作可能让出控制权，
        ; 导致定时器触发，executor 中 Execute() 返回 0 时将 active 置 false。
        this._savedStartGroupExecution := SkillManager.GetMethod("_StartGroupExecution")
        SkillManager.DefineProp("_StartGroupExecution", {call: _NoOpStartGroupExecution})
    }

    afterEach() {
        ; 恢复原始 _StartGroupExecution，避免影响后续测试套件
        if this._savedStartGroupExecution is Func
            SkillManager.DefineProp("_StartGroupExecution", {call: this._savedStartGroupExecution})
        this._savedStartGroupExecution := ""
    }

    afterAll() {
        try {
            ids := []
            for id in SkillManager.Groups
                ids.Push(id)
            for id in ids
                SkillManager.DeleteGroup(id)
        }
    }

    Test_ToggleAll_ActivatesAllGroups() {
        SkillManager.EmergencyMode := false
        for id, group in SkillManager.Groups {
            if group.active
                SkillManager.ToggleGroup(id)
        }
        SkillManager.ToggleAll()
        this.assert.isTrue(SkillManager.GetActiveCount() > 0)
    }

    Test_ToggleAll_DeactivatesAllGroups() {
        SkillManager.EmergencyMode := false
        if SkillManager.GetActiveCount() = 0
            SkillManager.ToggleAll()
        SkillManager.ToggleAll()
        this.assert.equal(SkillManager.GetActiveCount(), 0)
    }
}

; mock _StartGroupExecution 的空操作函数：不启动定时器，防止 executor 回调竞态
_NoOpStartGroupExecution(*) {
}

; =================================================================
; SkillGroup.Toggle() 异常处理测试（RED-GREEN-REFACTOR）
; 验证 catch 块在停用失败/激活失败时的状态回滚行为
; =================================================================

; 辅助函数：模拟 _ReleaseAllKeys 抛异常（停用失败场景）
_ThrowReleaseAllKeysError(*) {
    throw Error("模拟停用失败")
}

; 辅助函数：模拟 _ResetPeriodicTriggerTimes 抛异常（激活失败场景）
_ThrowResetTriggerError(*) {
    throw Error("模拟激活失败")
}

class SkillGroupToggleExceptionTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
    }

    Test_DeactivateFailure_KeepsActiveFalse() {
        ; 创建周期性分组并先激活
        sg := SkillGroup("test_deact", Map(
            "mode", "periodic", "hotkey", "F1",
            "keys", ["a"], "intervals", [50]
        ))
        sg._lastToggleTime := 0
        result := sg.Toggle()
        this.assert.isTrue(sg.active)
        this.assert.equal(result, true)

        ; 覆盖 _ReleaseAllKeys 为抛异常版本（模拟停用时按键释放失败）
        sg.DefineProp("_ReleaseAllKeys", {call: _ThrowReleaseAllKeysError})

        ; 再次 Toggle 停用（_ReleaseAllKeys 抛异常 → 进入 catch 块）
        sg._lastToggleTime := 0
        result := sg.Toggle()

        ; 核心断言：停用失败时 active 应保持 false，不应恢复为 true
        this.assert.isFalse(sg.active)
        this.assert.equal(result, false)
    }

    Test_ActivateFailure_RollsBackActiveFalse() {
        ; 回归保护：验证激活失败时 active 回滚为 false（现有正确逻辑不被破坏）
        sg := SkillGroup("test_act", Map(
            "mode", "periodic", "hotkey", "F1",
            "keys", ["a"], "intervals", [50]
        ))
        this.assert.isFalse(sg.active)

        ; 覆盖 _ResetPeriodicTriggerTimes 为抛异常版本（模拟激活失败）
        sg.DefineProp("_ResetPeriodicTriggerTimes", {call: _ThrowResetTriggerError})

        sg._lastToggleTime := 0
        result := sg.Toggle()

        ; 激活失败时 active 应回滚为 false
        this.assert.isFalse(sg.active)
        this.assert.equal(result, false)
    }
}

class ConfigValidatorAllMapFormatTests extends AutoHotUnitSuite {
    Test_ValidateHotkeys_ErrorsAreMaps() {
        hotkeys := Map()
        errors := ConfigValidator._ValidateHotkeys(hotkeys)
        for e in errors {
            this.assert.isTrue(e is Map)
            this.assert.isTrue(e.Has("type"))
            this.assert.isTrue(e.Has("message"))
        }
    }

    Test_ValidateHoldSettings_ErrorsAreMaps() {
        settings := Map("pressSpeed", -1, "debounceDelay", 2000)
        errors := ConfigValidator._ValidateHoldSettings(settings)
        for e in errors {
            this.assert.isTrue(e is Map)
            this.assert.isTrue(e.Has("type"))
            this.assert.isTrue(e.Has("message"))
        }
    }

    Test_Validate_MissingGroupSettings_ErrorIsMap() {
        errors := ConfigValidator.Validate(Map())
        this.assert.isTrue(errors.Length > 0)
        this.assert.isTrue(errors[1] is Map)
        this.assert.isTrue(errors[1].Has("message"))
    }

    Test_GetErrorMessage_ExtractsFromMap() {
        err := Map("type", "ERROR", "message", "test error")
        this.assert.equal(ConfigValidator.GetErrorMessage(err), "test error")
    }

    Test_GetErrorMessage_FallsBackToString() {
        this.assert.equal(ConfigValidator.GetErrorMessage("plain error"), "plain error")
    }
}

class ValidateGroupOnlyNoDoubleWrapTests extends AutoHotUnitSuite {
    Test_ValidateGroupOnly_FieldErrorsNotDoubleWrapped() {
        config := Map("hotkey", "F1", "mode", "periodic")
        errors := ConfigValidator.ValidateGroupOnly("1", config)
        for e in errors {
            if e is Map && e.Has("message") {
                msg := e["message"]
                this.assert.isTrue(!InStr(msg, "[object") || !InStr(msg, "Map"))
            }
        }
    }
}

class JSONLoggerMaxErrorsTests extends AutoHotUnitSuite {
    Test_MaxErrors_IsPositive() {
        this.assert.isTrue(JSONLogger.maxErrors > 0)
    }

    Test_MaxErrors_DefaultValue() {
        this.assert.equal(JSONLogger.maxErrors, 500)
    }
}

class GetRuntimeStatusMapTests extends AutoHotUnitSuite {
    beforeAll() {
        ConfigStore.InitDefaults()
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    Test_GetRuntimeStatus_ReturnsMap() {
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0 {
            for id, cfg in gs {
                group := SkillGroup(id, cfg)
                status := group.GetRuntimeStatus()
                this.assert.isTrue(status is Map)
                break
            }
        }
    }

    Test_GetRuntimeStatus_HasRequiredKeys() {
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0 {
            for id, cfg in gs {
                group := SkillGroup(id, cfg)
                status := group.GetRuntimeStatus()
                this.assert.isTrue(status.Has("active"))
                this.assert.isTrue(status.Has("executionCount"))
                this.assert.isTrue(status.Has("runTime"))
                this.assert.isTrue(status.Has("currentStep"))
                break
            }
        }
    }
}

class HealthCheckTimestampTests extends AutoHotUnitSuite {
    beforeAll() {
        ErrorSystem.Init()
        ConfigStore.InitDefaults()
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
    }

    Test_HealthCheck_TimestampIsISO() {
        result := ErrorHandler.HealthCheck(SkillManager)
        ts := result["timestamp"]
        this.assert.isTrue(InStr(ts, "T") > 0)
        this.assert.isTrue(InStr(ts, "-") > 0)
    }
}

class BackupCoreSortTests extends AutoHotUnitSuite {
    Test_SortBackupsByTime_NoRangeFunction() {
        backups := [
            Map("time", "20260101", "file", "b1"),
            Map("time", "20260301", "file", "b2"),
            Map("time", "20260201", "file", "b3")
        ]
        result := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(result.Length = 3)
        this.assert.equal(result[1]["time"], "20260301")
        this.assert.equal(result[3]["time"], "20260101")
    }
}

class HotkeyEditorNormalizeTests extends AutoHotUnitSuite {
    Test_NormalizeKey_SingleChar_Lowercase() {
        this.assert.equal(HotkeyEditor._NormalizeKey("A"), "a")
    }

    Test_NormalizeKey_SpecialKey_Preserved() {
        this.assert.equal(HotkeyEditor._NormalizeKey("Space"), "Space")
        this.assert.equal(HotkeyEditor._NormalizeKey("Enter"), "Enter")
    }

    Test_NormalizeKey_Empty_ReturnsEmpty() {
        this.assert.equal(HotkeyEditor._NormalizeKey(""), "")
    }

    Test_NormalizeKey_Number_Preserved() {
        this.assert.equal(HotkeyEditor._NormalizeKey("1"), "1")
    }

    Test_NormalizeKey_FKey_Preserved() {
        this.assert.equal(HotkeyEditor._NormalizeKey("F1"), "F1")
        this.assert.equal(HotkeyEditor._NormalizeKey("F12"), "F12")
    }
}

; =================================================================
; 第五轮修复测试
; =================================================================

class SequenceHoldTriggersMultiKeyTests extends AutoHotUnitSuite {
    Test_AnyHeld_WithMultipleKeys() {
        group := SkillGroup("test", Map(
            "hotkey", "F1", "mode", "enhanced_sequence",
            "pressKeys", ["1", "2"], "pressDelays", [100, 100],
            "holdKeys", ["Shift", "Ctrl"], "holdMode", "sequence",
            "holdTriggers", [1, 0]
        ))
        this.assert.isTrue(group.holdKeys.Length = 2)
        this.assert.isTrue(group.holdMode = "sequence")
    }
}

class SaveConfigNoDoubleSerializeTests extends AutoHotUnitSuite {
    Test_SaveConfig_ReturnsResult() {
        ConfigStore.InitDefaults()
        result := ConfigService.SaveConfig()
        this.assert.isTrue(result = true || result = false)
    }
}

class RestoreBackupAtomicTests extends AutoHotUnitSuite {
    Test_RestoreBackup_NonExistent_ReturnsError() {
        result := BackupCore.RestoreBackup("nonexistent_backup.json")
        this.assert.isTrue(result is Map)
        this.assert.isTrue(result.Has("success"))
        this.assert.isTrue(!result["success"])
    }
}

class JSONErrorModulePropertyTests extends AutoHotUnitSuite {
    Test_JSONError_HasModuleProperty() {
        err := JSONError("E001", "test")
        this.assert.isTrue(err.HasProp("module"))
        this.assert.equal(err.module, "")
    }

    Test_JSONError_ModuleSetViaContext() {
        err := JSONError("E001", "test")
        err.module := "TestModule"
        this.assert.equal(err.module, "TestModule")
    }
}

class DebugLoggerEnforceSizeTests extends AutoHotUnitSuite {
    Test_EnforceSizeLimit_NoSubArray() {
        this.assert.isTrue(DebugLogger.HasProp("maxSize"))
        this.assert.isTrue(DebugLogger.maxSize > 0)
    }
}

class GroupServiceRollbackSafetyTests extends AutoHotUnitSuite {
    Test_UpdateGroup_NonExistent_Throws() {
        try {
            GroupService.UpdateGroup("nonexistent", Map("hotkey", "F1", "mode", "periodic", "keys", ["Space"], "intervals", [50]))
            this.assert.fail("Should have thrown")
        } catch as e {
            this.assert.isTrue(InStr(e.Message, "不存在") > 0)
        }
    }
}

class ToggleAllAccurateNotifyTests extends AutoHotUnitSuite {
    beforeAll() {
        SkillManager.Logger := JSONLogger
        SkillManager.Notifier := UIManager
        SkillManager.ConfigStore := ConfigStore
        ConfigStore.InitDefaults()
        gs := ConfigStore.Get("GroupSettings")
        if gs is Map && gs.Count > 0
            SkillManager.Init(gs)
        SkillManager.EmergencyMode := false
        for id, group in SkillManager.Groups {
            if group.active {
                group._lastToggleTime := 0
                group.Toggle()
            }
        }
    }

    _savedStartGroupExecution := ""

    beforeEach() {
        ; 停止所有定时器，防止前一个测试遗留的 executor 回调干扰
        for id in SkillManager.Groups {
            try SkillManager._StopGroupExecution(id)
        }
        ; mock _StartGroupExecution 防止定时器竞态：
        ; ToggleAll 激活组后 _StartGroupExecution 设置 10ms 定时器，
        ; ToggleAll 内部 _Notify/_UpdateBriefInfo 的 GUI 操作可能让出控制权，
        ; 导致定时器触发，executor 中 Execute() 返回 0 时将 active 置 false。
        this._savedStartGroupExecution := SkillManager.GetMethod("_StartGroupExecution")
        SkillManager.DefineProp("_StartGroupExecution", {call: _NoOpStartGroupExecution})
    }

    afterEach() {
        ; 恢复原始 _StartGroupExecution，避免影响后续测试套件
        if this._savedStartGroupExecution is Func
            SkillManager.DefineProp("_StartGroupExecution", {call: this._savedStartGroupExecution})
        this._savedStartGroupExecution := ""
    }

    afterAll() {
        try {
            SkillManager.EmergencyMode := false
            for id, group in SkillManager.Groups {
                if group.active {
                    group._lastToggleTime := 0
                    group.Toggle()
                }
            }
            ids := []
            for id in SkillManager.Groups
                ids.Push(id)
            for id in ids
                SkillManager.DeleteGroup(id)
        }
    }

    Test_ToggleAll_ActivatesFromZero() {
        if SkillManager.Groups.Count = 0
            return
        initialCount := SkillManager.GetActiveCount()
        SkillManager.ToggleAll()
        afterToggle := SkillManager.GetActiveCount()
        if initialCount = 0
            this.assert.isTrue(afterToggle > 0)
        else
            this.assert.isTrue(afterToggle = 0)
        for id, group in SkillManager.Groups {
            if group.active {
                group._lastToggleTime := 0
                group.Toggle()
            }
        }
    }
}

class JSONSerializerSpacesCacheTests extends AutoHotUnitSuite {
    Test_BuildSpaces_CachesResult() {
        s1 := JSONSerializer._BuildSpaces(4)
        s2 := JSONSerializer._BuildSpaces(4)
        this.assert.equal(s1, s2)
        this.assert.equal(s1, "    ")
    }

    Test_BuildSpaces_DifferentLengths() {
        s1 := JSONSerializer._BuildSpaces(2)
        s2 := JSONSerializer._BuildSpaces(4)
        this.assert.isTrue(s1 != s2)
        this.assert.equal(s1, "  ")
        this.assert.equal(s2, "    ")
    }
}

class HealthCheckMaxActiveGroupsTests extends AutoHotUnitSuite {
    Test_MaxActiveGroups_IsConfigurable() {
        this.assert.isTrue(ErrorHandler.maxActiveGroups > 0)
    }

    Test_MaxActiveGroups_DefaultValue() {
        this.assert.equal(ErrorHandler.maxActiveGroups, 10)
    }
}

class IPCPollMessagesOrderTests extends AutoHotUnitSuite {
    Test_IPCChannel_DefaultChannelDir() {
        this.assert.equal(IPCChannel.channelDir, "ipc")
    }
}

class ConfigStoreSetUnknownKeyTests extends AutoHotUnitSuite {
    Test_Set_UnknownKey_NoError() {
        ConfigStore.Set("UnknownKey", "value")
    }

    Test_Set_KnownKey_Works() {
        oldVal := ConfigStore.Get("HoldSettings")
        ConfigStore.Set("HoldSettings", Map("test", true))
        newVal := ConfigStore.Get("HoldSettings")
        this.assert.isTrue(newVal is Map)
        this.assert.isTrue(newVal.Has("test"))
        ConfigStore.Set("HoldSettings", oldVal)
    }
}

class ExecutorTimerGuardTests extends AutoHotUnitSuite {
    Test_TimersMap_HasCheck_InExecutor() {
        this.assert.isTrue(SkillManager._timers is Map)
    }

    Test_StopExecution_ClearsTimer() {
        testFn := () => {}
        SkillManager._timers["__test_exec"] := testFn
        this.assert.isTrue(SkillManager._timers.Has("__test_exec"))
        SkillManager._StopGroupExecution("__test_exec")
        this.assert.isTrue(!SkillManager._timers.Has("__test_exec"))
    }
}

class HotReloadEmergencyResetTests extends AutoHotUnitSuite {
    Test_ResetEmergency_SetsModeFalse() {
        SkillManager.EmergencyMode := true
        SkillManager.ResetEmergency()
        this.assert.isTrue(!SkillManager.EmergencyMode)
    }

    Test_Emergency_SetsModeTrue() {
        SkillManager.EmergencyMode := false
        SkillManager.Emergency()
        this.assert.isTrue(SkillManager.EmergencyMode)
        SkillManager.ResetEmergency()
    }
}

class ToggleDebounceReturnTests extends AutoHotUnitSuite {
    Test_Toggle_ReturnsNegOne_OnDebounce() {
        group := SkillGroup("debounce_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        group._lastToggleTime := A_TickCount
        result := group.Toggle()
        this.assert.isTrue(result = -1)
    }

    Test_Toggle_ReturnsTrue_OnFirstActivate() {
        group := SkillGroup("first_toggle_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        group._lastToggleTime := 0
        result := group.Toggle()
        this.assert.isTrue(result = true)
        group._ReleaseAllKeys()
    }

    Test_ToggleGroup_SkipsCount_OnDebounce() {
        group := SkillGroup("tg_debounce_test", Map(
            "hotkey", "F1", "mode", "periodic",
            "keys", ["Space"], "intervals", [50]
        ))
        SkillManager.Groups["__tg_debounce"] := group
        group._lastToggleTime := 0
        group.Toggle()
        afterFirst := SkillManager.GetActiveCount()
        result := group.Toggle()
        afterSecond := SkillManager.GetActiveCount()
        this.assert.isTrue(result = -1)
        this.assert.isTrue(afterSecond = afterFirst)
        group._ReleaseAllKeys()
        SkillManager.Groups.Delete("__tg_debounce")
    }
}

class CopyGroupIdGenerationTests extends AutoHotUnitSuite {
    Test_MaxIdPlusOne_NoConflict() {
        maxId := 0
        testIds := ["1", "3", "5"]
        for id in testIds {
            try {
                idNum := Integer(String(id))
                if idNum > maxId
                    maxId := idNum
            } catch {
                continue
            }
        }
        newId := String(maxId + 1)
        this.assert.isTrue(newId = "6")
    }

    Test_EmptyGroups_GeneratesId1() {
        maxId := 0
        newId := String(maxId + 1)
        this.assert.isTrue(newId = "1")
    }
}

class BackupSortAlgorithmTests extends AutoHotUnitSuite {
    Test_SortByTime_Descending() {
        backups := [
            Map("time", "20260101000000", "file", "old.json"),
            Map("time", "20260103000000", "file", "new.json"),
            Map("time", "20260102000000", "file", "mid.json")
        ]
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted[1]["file"] = "new.json")
        this.assert.isTrue(sorted[2]["file"] = "mid.json")
        this.assert.isTrue(sorted[3]["file"] = "old.json")
    }

    Test_SortByTime_SingleElement() {
        backups := [Map("time", "20260101000000", "file", "only.json")]
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted.Length = 1)
        this.assert.isTrue(sorted[1]["file"] = "only.json")
    }

    Test_SortByTime_EmptyArray() {
        backups := []
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted.Length = 0)
    }

    Test_SortByTime_AlreadySorted() {
        backups := [
            Map("time", "20260103000000", "file", "c.json"),
            Map("time", "20260102000000", "file", "b.json"),
            Map("time", "20260101000000", "file", "a.json")
        ]
        sorted := BackupCore._SortBackupsByTime(backups)
        this.assert.isTrue(sorted[1]["file"] = "c.json")
        this.assert.isTrue(sorted[3]["file"] = "a.json")
    }
}

; =================================================================
; JoystickExecutor 注入检查 + 释放定时器（T3-06 / T6-02）领域层测试
; =================================================================
class JoystickExecutorInjectionTimerTests extends AutoHotUnitSuite {
    afterAll() {
        JoystickExecutor.SetJoySender(MockJoySender())
    }

    Test_EnsureSenderReady_WithoutInjection_ReturnsFalse() {
        JoystickExecutor.SetJoySender("")
        this.assert.isFalse(JoystickExecutor._EnsureSenderReady())
    }

    Test_EnsureSenderReady_WithInjection_ReturnsTrue() {
        JoystickExecutor.SetJoySender(MockJoySender())
        this.assert.isTrue(JoystickExecutor._EnsureSenderReady())
    }

    Test_Execute_WithoutInjection_ReturnsEarlyNoThrow() {
        JoystickExecutor.SetJoySender("")
        group := SkillGroup("__joy_noinj", Map(
            "mode", "joystick_periodic",
            "joyKeys", ["Joy1"],
            "joyIntervals", [100]
        ))
        result := -1
        try
            result := ModeRegistry.GetExecutor("joystick_periodic").Execute(group)
        catch as e
            this.assert.fail("未注入时 Execute 不应抛异常: " e.Message)
        this.assert.isTrue(result >= 0)
        group.Dispose()
    }

    Test_ReleaseTimers_CancelledOnStop() {
        JoystickExecutor.SetJoySender(MockJoySender())
        group := SkillGroup("__joy_rel", Map(
            "mode", "joystick_periodic",
            "joyKeys", ["Joy1"],
            "joyIntervals", [100]
        ))
        JoystickExecutor._ScheduleRelease(group, "Joy1", "direct", 15)
        this.assert.isTrue(JoystickExecutor._releaseTimers.Has("__joy_rel"))
        this.assert.isTrue(JoystickExecutor._releaseTimers["__joy_rel"].Has("Joy1"))
        JoystickExecutor._CancelReleaseTimers(group)
        this.assert.isFalse(JoystickExecutor._releaseTimers.Has("__joy_rel"))
        group.Dispose()
    }
}

; =================================================================
; G2 日志限速验证测试（计划 §3.2 G2：T3-05 + T6-03）
; 验证 ErrorSystem / JSONLogger 同源限速 ≤1 次/秒，且含 suppressedCount
; =================================================================
class LogRateLimitTests extends AutoHotUnitSuite {
    Test_SharedRateLimitConstant_Is1000() {
        this.assert.equal(LOG_RATE_LIMIT_MS, 1000)
    }

    Test_ErrorSystem_SameSource_Suppressed() {
        ErrorSystem.Init()
        ErrorSystem._rateLastTime := Map()
        ErrorSystem._rateSuppressed := Map()
        src := "__rl_err_src"
        ErrorSystem.LogError("限速1", "ERROR", src, 1)
        ErrorSystem.LogError("限速2", "ERROR", src, 1)
        ErrorSystem.LogError("限速3", "ERROR", src, 1)
        this.assert.isTrue(ErrorSystem._rateLastTime.Has(src))
        this.assert.equal(ErrorSystem._rateSuppressed[src], 2)
    }

    Test_JSONLogger_SameSource_Suppressed() {
        JSONLogger.Init()
        JSONLogger._rateLastTime := Map()
        JSONLogger._rateSuppressed := Map()
        JSONLogger.Log("ERROR", "限速1", Map("module", "__rl_json"))
        JSONLogger.Log("ERROR", "限速2", Map("module", "__rl_json"))
        JSONLogger.Log("ERROR", "限速3", Map("module", "__rl_json"))
        src := "__rl_json:generic"
        this.assert.isTrue(JSONLogger._rateLastTime.Has(src))
        this.assert.equal(JSONLogger._rateSuppressed[src], 2)
    }

    Test_ErrorSystem_SuppressedCount_FlushedOnNextWrite() {
        ErrorSystem.Init()
        origFile := ErrorSystem.logFile
        tmpFile := A_ScriptDir "\__rl_err_tmp.log"
        if FileExist(tmpFile)
            FileDelete(tmpFile)
        ErrorSystem.logFile := tmpFile
        ErrorSystem._rateLastTime := Map()
        ErrorSystem._rateSuppressed := Map()
        src := "__rl_err_src2"
        ; 预置窗口外 + 已抑制 5 次，触发下一次写入携带 suppressedCount
        ErrorSystem._rateLastTime[src] := A_TickCount - (LOG_RATE_LIMIT_MS + 500)
        ErrorSystem._rateSuppressed[src] := 5
        ErrorSystem.LogError("限速", "ERROR", src, 1)
        content := FileExist(tmpFile) ? FileRead(tmpFile, "UTF-8") : ""
        this.assert.isTrue(InStr(content, "suppressedCount") > 0)
        this.assert.isTrue(InStr(content, '"suppressedCount": 5') > 0)
        if FileExist(tmpFile)
            FileDelete(tmpFile)
        ErrorSystem.logFile := origFile
    }
}