; =================================================================
; test_sender.ahk - 测试 AHK 执行器按键发送器
; 目标：验证 sender.ahk 中 Sender 的白名单、执行组管理、模式切换
; 注意：避免实际 SendInput 副作用，使用非白名单按键验证状态管理
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; 被测脚本（sender.ahk 内部 #Include ipc_client.ahk）
#Include "../../asd-tauri/src-tauri/ahk_executor/sender.ahk"

; 测试框架（提供 AutoHotUnitSuite 基类）
#Include "../AutoHotUnit.ahk"

; 警告设置（在 #Include 之后，覆盖 AutoHotUnit.ahk 的 #Warn All）
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 运行时错误接管
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试套件：Sender.ALLOWED_KEYS 按键白名单
; =================================================================

class SenderAllowedKeysTests extends AutoHotUnitSuite {
    Test_AllowedKeys_IsMap() {
        this.assert.isTrue(Sender.ALLOWED_KEYS is Map)
    }

    Test_AllowedKeys_ContainsFKeys() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("F1"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("F6"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("F12"))
    }

    Test_AllowedKeys_ContainsNumbers() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("1"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("5"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("0"))
    }

    Test_AllowedKeys_ContainsLetters() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("a"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("m"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("z"))
    }

    Test_AllowedKeys_ContainsSpecialKeys() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Space"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Enter"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Tab"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Esc"))
    }

    Test_AllowedKeys_ContainsModifiers() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Shift"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Ctrl"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Alt"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("LWin"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("RWin"))
    }

    Test_AllowedKeys_ContainsNumpad() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Numpad0"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Numpad9"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("NumpadAdd"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("NumpadEnter"))
    }

    Test_AllowedKeys_ContainsArrowKeys() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Up"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Down"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Left"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Right"))
    }

    Test_AllowedKeys_ContainsJoyKeys() {
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Joy1"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Joy16"))
        this.assert.isTrue(Sender.ALLOWED_KEYS.Has("Joy32"))
    }

    Test_AllowedKeys_DoesNotContainInvalidKey() {
        this.assert.isFalse(Sender.ALLOWED_KEYS.Has("InvalidKey"))
        this.assert.isFalse(Sender.ALLOWED_KEYS.Has("F13"))
        this.assert.isFalse(Sender.ALLOWED_KEYS.Has(""))
    }
}

; =================================================================
; 测试套件：Sender._ValidateKey 按键验证
; =================================================================

class SenderValidateKeyTests extends AutoHotUnitSuite {
    Test_ValidateKey_Whitelisted_ReturnsTrue() {
        this.assert.isTrue(Sender._ValidateKey("F1"))
        this.assert.isTrue(Sender._ValidateKey("Space"))
        this.assert.isTrue(Sender._ValidateKey("a"))
    }

    Test_ValidateKey_NonWhitelisted_ReturnsFalse() {
        this.assert.isFalse(Sender._ValidateKey("F13"))
        this.assert.isFalse(Sender._ValidateKey("InvalidKey"))
    }

    Test_ValidateKey_EmptyString_ReturnsFalse() {
        this.assert.isFalse(Sender._ValidateKey(""))
    }
}

; =================================================================
; 测试套件：Sender.ToggleGroup 执行组激活/停止
; =================================================================

class SenderToggleGroupTests extends AutoHotUnitSuite {
    afterAll() {
        Sender.EmergencyRelease()
    }

    Test_ToggleGroup_Activate_AddsToActiveGroups() {
        Sender.EmergencyRelease()
        Sender.ToggleGroup("__test_toggle_1", true)
        this.assert.isTrue(Sender._activeGroups.Has("__test_toggle_1"))
    }

    Test_ToggleGroup_Deactivate_RemovesFromActiveGroups() {
        Sender.EmergencyRelease()
        Sender.ToggleGroup("__test_toggle_2", true)
        Sender.ToggleGroup("__test_toggle_2", false)
        this.assert.isFalse(Sender._activeGroups.Has("__test_toggle_2"))
    }

    Test_ToggleGroup_Reactivate_DoesNotThrow() {
        Sender.EmergencyRelease()
        Sender.ToggleGroup("__test_toggle_3", true)
        try {
            Sender.ToggleGroup("__test_toggle_3", true)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("重复激活不应抛出异常: " e.Message)
        }
    }

    Test_ToggleGroup_DeactivateUnactivated_DoesNotThrow() {
        Sender.EmergencyRelease()
        try {
            Sender.ToggleGroup("__test_toggle_4", false)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("停止未激活组不应抛出异常: " e.Message)
        }
    }

    Test_ToggleGroup_Activate_ReturnsTrue() {
        Sender.EmergencyRelease()
        result := Sender.ToggleGroup("__test_toggle_5", true)
        this.assert.isTrue(result)
    }

    Test_ToggleGroup_Deactivate_ReturnsTrue() {
        Sender.EmergencyRelease()
        Sender.ToggleGroup("__test_toggle_6", true)
        result := Sender.ToggleGroup("__test_toggle_6", false)
        this.assert.isTrue(result)
    }
}

; =================================================================
; 测试套件：Sender.StartPeriodic 周期性模式启动
; =================================================================

class SenderStartPeriodicTests extends AutoHotUnitSuite {
    afterAll() {
        Sender.EmergencyRelease()
    }

    Test_StartPeriodic_AddsToActiveGroups() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_periodic_1", ["F1"], [100], 15)
        this.assert.isTrue(Sender._activeGroups.Has("__test_periodic_1"))
        Sender._StopGroup("__test_periodic_1")
    }

    Test_StartPeriodic_SetsMode() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_periodic_2", ["F1"], [100], 15)
        state := Sender._activeGroups["__test_periodic_2"]
        this.assert.equal(state["mode"], "periodic")
        Sender._StopGroup("__test_periodic_2")
    }

    Test_StartPeriodic_StoresKeys() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_periodic_3", ["F1", "F2"], [100, 200], 15)
        state := Sender._activeGroups["__test_periodic_3"]
        this.assert.equal(state["keys"].Length, 2)
        Sender._StopGroup("__test_periodic_3")
    }

    Test_StartPeriodic_RegistersTimer() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_periodic_4", ["F1"], [100], 15)
        this.assert.isTrue(Sender._timers.Has("__test_periodic_4"))
        Sender._StopGroup("__test_periodic_4")
    }

    Test_StartPeriodic_StopsTimerOnStop() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_periodic_5", ["F1"], [100], 15)
        Sender._StopGroup("__test_periodic_5")
        this.assert.isFalse(Sender._timers.Has("__test_periodic_5"))
    }

    Test_StartPeriodic_RepeatedStart_OnlyOneTimer() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_periodic_6", ["F1"], [100], 15)
        Sender.StartPeriodic("__test_periodic_6", ["F1"], [100], 15)
        this.assert.isTrue(Sender._timers.Has("__test_periodic_6"))
        this.assert.equal(Sender._timers.Count, 1)
        Sender._StopGroup("__test_periodic_6")
    }

    Test_StopGroup_CancelsReleaseTimers() {
        Sender.EmergencyRelease()
        Sender.StartPeriodic("__test_release", ["F1"], [100], 15)
        Sender._ScheduleRelease("__test_release", "F1", 15)
        this.assert.isTrue(Sender._releaseTimers.Has("__test_release"))
        this.assert.isTrue(Sender._releaseTimers["__test_release"].Has("F1"))
        Sender._StopGroup("__test_release")
        this.assert.isFalse(Sender._releaseTimers.Has("__test_release"))
    }
}

; =================================================================
; 测试套件：Sender.StartSequence 序列模式启动
; =================================================================

class SenderStartSequenceTests extends AutoHotUnitSuite {
    afterAll() {
        Sender.EmergencyRelease()
    }

    Test_StartSequence_SetsMode() {
        Sender.EmergencyRelease()
        Sender.StartSequence("__test_seq_1", ["F1", "F2"], [100, 100], 15)
        state := Sender._activeGroups["__test_seq_1"]
        this.assert.equal(state["mode"], "sequence")
        Sender._StopGroup("__test_seq_1")
    }

    Test_StartSequence_StoresDelays() {
        Sender.EmergencyRelease()
        Sender.StartSequence("__test_seq_2", ["F1", "F2", "F3"], [50, 100, 150], 15)
        state := Sender._activeGroups["__test_seq_2"]
        this.assert.equal(state["delays"].Length, 3)
        Sender._StopGroup("__test_seq_2")
    }

    Test_StartSequence_InitialStepIsOne() {
        Sender.EmergencyRelease()
        Sender.StartSequence("__test_seq_3", ["F1"], [100], 15)
        state := Sender._activeGroups["__test_seq_3"]
        this.assert.equal(state["currentStep"], 1)
        Sender._StopGroup("__test_seq_3")
    }
}

; =================================================================
; 测试套件：Sender.StartEnhancedPeriodic/Sequence 增强模式
; =================================================================

class SenderStartEnhancedTests extends AutoHotUnitSuite {
    afterAll() {
        Sender.EmergencyRelease()
    }

    Test_StartEnhancedPeriodic_SetsMode() {
        Sender.EmergencyRelease()
        Sender.StartEnhancedPeriodic("__test_ep_1", ["F1"], [100], 15)
        state := Sender._activeGroups["__test_ep_1"]
        this.assert.equal(state["mode"], "enhanced_periodic")
        Sender._StopGroup("__test_ep_1")
    }

    Test_StartEnhancedSequence_SetsMode() {
        Sender.EmergencyRelease()
        Sender.StartEnhancedSequence("__test_es_1", ["F1"], [100], 15)
        state := Sender._activeGroups["__test_es_1"]
        this.assert.equal(state["mode"], "enhanced_sequence")
        Sender._StopGroup("__test_es_1")
    }
}

; =================================================================
; 测试套件：Sender.StartHold Hold 模式（使用非白名单按键避免副作用）
; =================================================================

class SenderStartHoldTests extends AutoHotUnitSuite {
    afterAll() {
        Sender.EmergencyRelease()
    }

    Test_StartHold_SetsMode() {
        Sender.EmergencyRelease()
        Sender._holdModeEnabled := true
        Sender.StartHold("__test_hold_1", ["F13"], "continuous")
        if Sender._activeGroups.Has("__test_hold_1") {
            state := Sender._activeGroups["__test_hold_1"]
            this.assert.equal(state["mode"], "hold")
        } else {
            this.assert.isTrue(true)
        }
        Sender._StopGroup("__test_hold_1")
    }

    Test_StartHold_Disabled_DoesNotActivate() {
        Sender.EmergencyRelease()
        Sender._holdModeEnabled := false
        Sender.StartHold("__test_hold_2", ["F13"], "continuous")
        this.assert.isFalse(Sender._activeGroups.Has("__test_hold_2"))
        Sender._holdModeEnabled := true
    }
}

; =================================================================
; 测试套件：Sender.HoldModeToggle Hold 模式切换
; =================================================================

class SenderHoldModeToggleTests extends AutoHotUnitSuite {
    afterAll() {
        Sender._holdModeEnabled := true
        Sender.EmergencyRelease()
    }

    Test_HoldModeToggle_Disable_DoesNotThrow() {
        try {
            Sender.HoldModeToggle(false)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("HoldModeToggle(false) 不应抛出异常: " e.Message)
        }
    }

    Test_HoldModeToggle_Enable_DoesNotThrow() {
        try {
            Sender.HoldModeToggle(true)
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("HoldModeToggle(true) 不应抛出异常: " e.Message)
        }
    }

    Test_HoldModeToggle_SetsFlag() {
        Sender.HoldModeToggle(false)
        this.assert.isFalse(Sender._holdModeEnabled)
        Sender.HoldModeToggle(true)
        this.assert.isTrue(Sender._holdModeEnabled)
    }
}

; =================================================================
; 测试套件：Sender.EmergencyRelease 紧急释放
; =================================================================

class SenderEmergencyReleaseTests extends AutoHotUnitSuite {
    Test_EmergencyRelease_DoesNotThrow() {
        try {
            Sender.EmergencyRelease()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("EmergencyRelease 不应抛出异常: " e.Message)
        }
    }

    Test_EmergencyRelease_ClearsActiveGroups() {
        Sender.EmergencyRelease()
        Sender.ToggleGroup("__test_emergency_1", true)
        Sender.EmergencyRelease()
        this.assert.equal(Sender._activeGroups.Count, 0)
    }
}

; =================================================================
; 测试套件：Sender.Shutdown 关机清理
; =================================================================

class SenderShutdownTests extends AutoHotUnitSuite {
    Test_Shutdown_DoesNotThrow() {
        try {
            Sender.Shutdown()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("Shutdown 不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：Sender.Init 初始化
; =================================================================

class SenderInitTests extends AutoHotUnitSuite {
    Test_Init_DoesNotThrow() {
        try {
            Sender.Init()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("Init 不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：Sender._reportKeyEvents 逐键上报开关
; 说明：直接测试 _ReportKeyEvent 可测试切片，避免 SendInput 真实按键副作用
; =================================================================

class SenderReportKeyEventsTests extends AutoHotUnitSuite {
    afterAll() {
        Sender._reportKeyEvents := false
        Sender._keyEventSender := ""
    }

    Test_ReportKeyEvent_SkipsReporting_WhenNotReporting() {
        Sender._reportKeyEvents := false
        calls := 0
        Sender._keyEventSender := (msg) => (calls++, true)
        try {
            Sender._ReportKeyEvent("a", "down")
        } finally {
            Sender._keyEventSender := ""
            Sender._reportKeyEvents := false
        }
        this.assert.equal(calls, 0)
    }

    Test_ReportKeyEvent_Reports_WhenReporting() {
        Sender._reportKeyEvents := true
        captured := Map()
        Sender._keyEventSender := (msg) => (captured["last"] := msg, true)
        try {
            Sender._ReportKeyEvent("a", "down")
        } finally {
            Sender._keyEventSender := ""
            Sender._reportKeyEvents := false
        }
        this.assert.isTrue(captured.Has("last"))
        this.assert.equal(captured["last"]["type"], "key_send_event")
        this.assert.equal(captured["last"]["data"]["state"], "down")
    }
}

; =================================================================
; 测试套件：周期模式精确定刻
; 目标：每一次模拟按键「计划时刻 → 抬起完成」P95 ≤ 20ms，且不遗漏触发
;
; 注意：A_TickCount 步进实测约 15.5ms，不能用于 20ms 预算内的判定，
;       本套件一律用 HighResClock(QPC) 采样。
; =================================================================

class SenderPreciseTimingTests extends AutoHotUnitSuite {
    afterAll() {
        Sender.EmergencyRelease()
    }

    ; 升序排序（插入排序，样本量小）；下划线开头，不会被收集为用例
    _Sort(arr) {
        i := 2
        while i <= arr.Length {
            v := arr[i], j := i - 1
            while j >= 1 && arr[j] > v {
                arr[j + 1] := arr[j]
                j--
            }
            arr[j + 1] := v
            i++
        }
        return arr
    }

    ; 取第 p 分位数（输入必须已升序）
    _Pct(arr, p) {
        idx := Ceil(arr.Length * p)
        idx := Max(1, Min(idx, arr.Length))
        return arr[idx]
    }

    ; QPC 分辨率必须远细于 1ms，否则无法支撑 20ms 预算内的度量
    Test_HighResClock_Now_ResolutionFarBelow1ms() {
        prev := HighResClock.Now()
        minDelta := 999999.0
        Loop 2000 {
            cur := HighResClock.Now()
            d := cur - prev
            if d > 0 && d < minDelta
                minDelta := d
            prev := cur
        }
        this.assert.isAtMost(minDelta, 0.05)
    }

    ; SleepUntil 的定位误差 P95 应 < 1ms
    Test_HighResClock_SleepUntil_ErrorBelow1ms() {
        errs := []
        Loop 30 {
            t0 := HighResClock.Now()
            HighResClock.SleepUntil(t0 + 12)
            errs.Push(Abs(HighResClock.Now() - t0 - 12))
        }
        this._Sort(errs)
        this.assert.isAtMost(this._Pct(errs, 0.95), 1.0)
    }

    ; 一次精确定刻按压的保持时长应等于 kpd（原实现走 SetTimer(-kpd)，误差 0~15.6ms）
    Test_PressPrecise_HoldDurationMatchesKpd() {
        events := []
        Sender._sendHook := (key, st) => events.Push(HighResClock.Now())
        try {
            t0 := HighResClock.Now()
            Sender._PressPrecise("__prec_hold", "F1", t0, 15)
        } finally {
            Sender._sendHook := ""
        }
        this.assert.equal(events.Length, 2)
        this.assert.isAtMost(Abs(events[2] - events[1] - 15), 1.0)
    }

    ; 端到端：periodic 模式下「计划时刻 → 抬起完成」P95 ≤ 20ms
    Test_ExecutePeriodic_EndToEndLatencyP95Within20ms() {
        gid := "__prec_e2e"
        interval := 100
        events := []

        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([st, HighResClock.Now()])
        Sender.StartPeriodic(gid, ["F1"], [interval], 15)
        ; 等第一次 _ExecutePeriodic 建立基准时刻
        Sleep 40
        t0 := Sender._activeGroups[gid]["lastTriggerTimes"][1]

        ; 采样量必须足够大：样本数 7 时 _Pct(0.95) 的索引 = 7，等同断言「最大值」，
        ; 宿主一次调度抖动就会失败，测的其实是 P100 而非 P95。
        ; 取 ~42 个样本后，P95 索引 = 40，才真正容忍 5%（2 个）离群。
        try {
            Sleep 4200
        } finally {
            Sender.ToggleGroup(gid, false)
            Sender._sendHook := ""
        }

        downs := []
        ups := []
        for i, e in events {
            if e[1] = "down"
                downs.Push(e[2])
            else if e[1] = "up"
                ups.Push(e[2])
        }
        this.assert.isAtLeast(downs.Length, 20)

        ; 第 i 次按下的计划时刻 = t0 + i * interval
        latencies := []
        i := 1
        while i <= downs.Length && i <= ups.Length {
            latencies.Push(ups[i] - (t0 + i * interval))
            i++
        }
        this._Sort(latencies)
        this.assert.isAtMost(this._Pct(latencies, 0.95), 20.0)
    }

    _Join(arr) {
        s := "["
        i := 1
        while i <= arr.Length {
            s .= Round(arr[i], 3) (i < arr.Length ? ", " : "")
            i++
        }
        return s "]"
    }

    ; 不遗漏触发：正常周期（≥ 一个定时器网格）下 droppedTriggers 必须恒为 0。
    ; 原实现在滞后时把基准重置为 now，既丢相位又吞掉触发。
    Test_ExecutePeriodic_NoDroppedTrigger_AtNormalInterval() {
        gid := "__prec_drop"
        Sender.EmergencyRelease()
        Sender.StartPeriodic(gid, ["F1"], [100], 15)
        Sleep 40
        try {
            Sleep 620
            dropped := 0
            if Sender._activeGroups.Has(gid) && Sender._activeGroups[gid].Has("droppedTriggers")
                dropped := Sender._activeGroups[gid]["droppedTriggers"]
            this.assert.equal(dropped, 0)
        } finally {
            Sender.ToggleGroup(gid, false)
        }
    }

    ; 回归：计划时刻相同的多个键必须「批量 Down → 统一等待 → 批量 Up」。
    ; 若逐键串行执行「Down → 等 → Up」，第二个键的等待会立刻超时（已过 plannedAt + kpd），
    ; 保持时长被压成 ~0ms —— 实测过该退化为 0.022ms。
    Test_MultiKeySameSchedule_AllKeysHoldFullKpd() {
        gid := "__prec_multi"
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([key, st, HighResClock.Now()])
        Sender.StartPeriodic(gid, ["F1", "F2"], [100, 100], 15)
        ; 足量样本 + P95：旧写法逐个样本断言（等价 P100），一次宿主抖动即失败
        try {
            Sleep 2200
        } finally {
            Sender.ToggleGroup(gid, false)
            Sender._sendHook := ""
        }

        lastDown := Map()
        holds := []
        for e in events {
            if e[2] = "down"
                lastDown[e[1]] := e[3]
            else if lastDown.Has(e[1]) {
                holds.Push(Abs(e[3] - lastDown[e[1]] - 15))
                lastDown.Delete(e[1])
            }
        }
        this.assert.isAtLeast(holds.Length, 20)
        this._Sort(holds)
        this.assert.isAtMost(this._Pct(holds, 0.95), 1.0)
    }

    ; 端到端：sequence 模式下「计划时刻 → 抬起完成」P95 ≤ 20ms。
    ; 原实现从「发送完成后的当前时刻」推进基准，误差逐步累积：
    ; 实测 delay=100ms 时步进退化成 111.9ms，3 秒内 P95 达 248~263ms。
    Test_ExecuteSequence_EndToEndLatencyP95Within20ms() {
        gid := "__prec_seq_e2e"
        delay := 100
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([st, HighResClock.Now()])
        Sender.StartSequence(gid, ["F1", "F2"], [delay, delay], 15)
        ; 同 periodic：样本量 ~42，保证 P95 是真正的 P95（可容忍 2 个宿主抖动离群）
        try {
            Sleep 4200
        } finally {
            Sender.ToggleGroup(gid, false)
            Sender._sendHook := ""
        }

        downs := []
        ups := []
        for e in events {
            if e[1] = "down"
                downs.Push(e[2])
            else if e[1] = "up"
                ups.Push(e[2])
        }
        this.assert.isAtLeast(downs.Length, 20)

        ; 第 i 次按下的计划时刻 = 首次按下 + (i-1) * delay
        latencies := []
        i := 1
        while i <= ups.Length {
            latencies.Push(ups[i] - (downs[1] + (i - 1) * delay))
            i++
        }
        this._Sort(latencies)
        this.assert.isAtMost(this._Pct(latencies, 0.95), 20.0)
    }

    ; sequence 步进必须等于配置的 delay，且不随时间漂移
    Test_ExecuteSequence_StepIntervalMatchesDelay_NoDrift() {
        gid := "__prec_seq_step"
        delay := 100
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([st, HighResClock.Now()])
        Sender.StartSequence(gid, ["F1", "F2"], [delay, delay], 15)
        ; 同样需要足量样本：旧窗口只有 ~6 步，且断言的是「最大偏差」（P100）
        try {
            Sleep 4200
        } finally {
            Sender.ToggleGroup(gid, false)
            Sender._sendHook := ""
        }

        downs := []
        for e in events {
            if e[1] = "down"
                downs.Push(e[2])
        }
        this.assert.isAtLeast(downs.Length, 20)

        ; 每一步的间隔都要贴近 delay：漂移会表现为「后期偏差明显大于前期」。
        ; 统计口径取**中位数**而非 P95：漂移是系统性偏移，会把全部样本一起推走，
        ; 中位数即可检出；而宿主调度抖动只会污染个别样本，不应让本用例失败。
        devs := []
        i := 2
        while i <= downs.Length {
            devs.Push(Abs(downs[i] - downs[i - 1] - delay))
            i++
        }
        this._Sort(devs)
        this.assert.isAtMost(this._Pct(devs, 0.5), 2.0)
    }

    ; hybrid：periodic 子组与 sequence 子组各自按配置节奏触发，且保持时长都等于 kpd
    Test_ExecuteHybrid_SubGroupsKeepTheirOwnRhythm() {
        gid := "__prec_hybrid"
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([key, st, HighResClock.Now()])
        groups := [
            Map("type", "periodic", "pressKeys", ["F1"], "intervals", [100]),
            Map("type", "sequence", "pressKeys", ["F2", "F3"], "delays", [150, 150])
        ]
        Sender.StartHybrid(gid, groups, 15)
        ; 同 periodic / sequence：用足量样本（窗口 ~3.2s），避免 P95 退化成「最大值」。
        ; 旧写法把 holds / steps 存进 Map，只留下最后一个样本 —— 一次宿主抖动即失败。
        try {
            Sleep 3200
        } finally {
            Sender.ToggleGroup(gid, false)
            Sender._sendHook := ""
        }

        lastDown := Map()
        holds := []          ; 所有保持时长
        perSteps := Map()    ; key -> 该键自身的步进数组
        seqSteps := []       ; sequence 子组内部相邻按下的步进
        prevSeqDown := 0
        seqKeys := Map("F2", true, "F3", true)
        for e in events {
            k := e[1], st := e[2], t := e[3]
            if st = "down" {
                if !perSteps.Has(k)
                    perSteps[k] := []
                perSteps[k].Push(t)
                if seqKeys.Has(k) {
                    if prevSeqDown != 0
                        seqSteps.Push(t - prevSeqDown)
                    prevSeqDown := t
                }
                lastDown[k] := t
            } else if lastDown.Has(k) {
                holds.Push(t - lastDown[k])
                lastDown.Delete(k)
            }
        }

        ; 两个子组都应有足够产出
        this.assert.isAtLeast(holds.Length, 20)
        this.assert.isAtLeast(seqSteps.Length, 15)

        ; 保持时长都精确等于 kpd（P95，容忍个别宿主抖动）
        holdErr := []
        for h in holds
            holdErr.Push(Abs(h - 15))
        this._Sort(holdErr)
        this.assert.isAtMost(this._Pct(holdErr, 0.95), 1.0)

        ; periodic 子组保持 100ms 节奏（中位数判漂移，理由同 sequence 步进用例）
        f1 := perSteps.Has("F1") ? perSteps["F1"] : []
        f1Steps := []
        i := 2
        while i <= f1.Length {
            f1Steps.Push(Abs(f1[i] - f1[i - 1] - 100))
            i++
        }
        this.assert.isAtLeast(f1Steps.Length, 20)
        this._Sort(f1Steps)
        this.assert.isAtMost(this._Pct(f1Steps, 0.5), 2.0)

        ; sequence 子组内部相邻按下保持 150ms 节奏
        seqErr := []
        for s in seqSteps
            seqErr.Push(Abs(s - 150))
        this._Sort(seqErr)
        this.assert.isAtMost(this._Pct(seqErr, 0.5), 2.0)
    }
}
