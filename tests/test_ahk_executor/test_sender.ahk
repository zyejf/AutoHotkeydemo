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

    ; 宿主时延类断言的总开关：ASD_HOST_TIMING=0 时跳过（缺省/其它值 = 执行）。
    ; 跳过走 assert.skip 而不是 return —— 跳过的条数会写进汇总，不会静默变绿。
    ;
    ; 为什么需要这个开关（实测，详见 docs/developer-guide.md「宿主时延类断言」）：
    ;   定刻走 **QPC 忙等**，CPU 一被争用就直接打穿，不是"变慢一点"而是量级崩塌。
    ;   本机 12 线程上施加 N 个满载进程，SleepUntil 误差 p50 / periodic 端到端 p50：
    ;       空载        0.005 ms / 15.015 ms
    ;       11 进程     0.005 ms / 15.015 ms     ← 中位数毫无变化，只有尾部开始抖
    ;       14 进程    19.222 ms / 28.448 ms     ← 悬崖：中位数一起崩
    ;   GitHub 共享 runner（2 vCPU）实测落在这条悬崖带上：SleepUntil p95=11.15ms
    ;   （阈值 5）、periodic p95=31.86ms（阈值 20），按插值其中位数也已达 ~6.7ms / ~22ms。
    ;   也就是说：CI 上**中位数同样守不住**，不是把 P95 放宽就能解决的。
    ;   放宽阈值只会得到一条测不出回归的虚线，硬判则是每次都有概率误报 —— 故 CI 显式跳过，
    ;   真正的守护点是争用可控的本机四闸门（默认全跑）。
    _HostTiming() {
        if (EnvGet("ASD_HOST_TIMING") = "0") {
            this.assert.skip("宿主时延断言：ASD_HOST_TIMING=0（共享 runner 的 CPU 争用会打穿 QPC 忙等，实测见 developer-guide）")
        }
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

    ; SleepUntil 的定位误差中位数应 < 1ms
    Test_HighResClock_SleepUntil_ErrorBelow1ms() {
        this._HostTiming()
        errs := []
        Loop 60 {
            t0 := HighResClock.Now()
            HighResClock.SleepUntil(t0 + 12)
            errs.Push(Abs(HighResClock.Now() - t0 - 12))
        }
        this._Sort(errs)
        ; 口径（与 G3b 抖动同因，别改回去）：
        ;   主判据是**中位数 ≤ 1.0**：若 SleepUntil 退化成基于 Sleep/网格的等待，
        ;   中位数会整体抬到数毫秒，这条立刻变红。
        ;   P95 ≤ 5.0 只是拦「整体崩坏」的兜底，不拦单机抖动 —— n=60 时索引是
        ;   Ceil(60*0.95)=57（第 4 大值），只容忍 3 个离群点，按定义就对宿主抢占
        ;   敏感；这是**有意保留**的上限，不是待修的脆弱点。
        ;   实测余量 15.5 倍（70 轮 / 4200 样本，含空载与 4/8 进程忙等负载；最坏
        ;   P95 0.3235，唯一 >5ms 的离群点 8.71ms 落在空载轮），单轮失败概率 ≈1e-9，
        ;   无需加固：提高 n 或加重试都是为 1e-9 量级的事件付复杂度。
        this.assert.isAtMost(this._Pct(errs, 0.5), 1.0)
        this.assert.isAtMost(this._Pct(errs, 0.95), 5.0)
    }

    ; 一次精确定刻按压的保持时长应等于 kpd（原实现走 SetTimer(-kpd)，误差 0~15.6ms）
    Test_PressPrecise_HoldDurationMatchesKpd() {
        this._HostTiming()
        durs := []
        Loop 9 {
            events := []
            Sender._sendHook := (key, st) => events.Push(HighResClock.Now())
            try {
                ; ⚠️ _PressPrecise 的 plannedAt 是整数微秒（调度内部口径），
                ; kpd 仍是毫秒；events 里记录的是毫秒，下面的 15 也就是毫秒。
                t0 := HighResClock.NowUs()
                Sender._PressPrecise("__prec_hold", "F1", t0, 15)
            } finally {
                Sender._sendHook := ""
            }
            this.assert.equal(events.Length, 2)
            durs.Push(Abs(events[2] - events[1] - 15))
        }
        this._Sort(durs)
        ; 原写法是**单样本** + 1ms 上限：宿主一次调度抢占就能让它变红，
        ; 在负载高的 runner 上必然偶发。改为 9 次取中位数 ——
        ; 实现层面的精度仍由 1ms 把关（若退化成 SetTimer 释放，中位数会抬到数毫秒），
        ; 但偶发抢占不再误报。
        this.assert.isAtMost(this._Pct(durs, 0.5), 1.0)
    }

    ; 端到端：periodic 模式下「计划时刻 → 抬起完成」P95 ≤ 20ms
    Test_ExecutePeriodic_EndToEndLatencyP95Within20ms() {
        this._HostTiming()
        ; ---- TD-052：宿主负载下偶发红（与 hybrid 同因，见 Test_ExecuteHybrid_SubGroupsKeepTheirOwnRhythm）----
        ; 采样窗口 4.2s → 8.4s（n≈42 → ≈84）。P95 是**上分位估计**：n≈42 时 _Pct(0.95) 索引=40
        ; 等价「第 3 大值」，宿主一次抢占（Windows 调度网格 15.625ms）即可顶穿 20.0；
        ; n≈84 时索引=80 等价「第 4 大值」。阈值一律不动。
        ; 重试口径同 TD-041：**只重试**「中位数判据全过、仅 P95 兜底越界」这一种宿主抢占签名，
        ; 中位数一旦失败即系统性漂移=真回归，立即失败、绝不重试；重试留痕，不静默。
        m := this._SamplePeriodicE2E(8400)
        if (this._PeriodicE2ETailOnlyFail(m)) {
            msg := "[TD-052] periodic 端到端时延 P95=" Round(m["p95"], 3)
                . " 越界（偏差中位数 " Round(m["jitterP50"], 3) . "ms 正常，n=" m["n"]
                . "）→ 判定为宿主抢占，重试 1 次"
            FileAppend(msg "`n", "*", "UTF-8")
            FileAppend("      " msg "`r`n", A_ScriptDir "\test_results.log", "UTF-8")
            m := this._SamplePeriodicE2E(8400)
        }

        this.assert.isAtLeast(m["n"], 20)
        ; 中位数判系统性漂移（真正的回归信号）：口径同 Test_HighResClock_SleepUntil_ErrorBelow1ms，
        ; 「计划时刻 → 抬起完成」减去 kpd(15ms) 后的**调度偏差**中位数必须 ≤1ms。
        this.assert.isAtMost(m["jitterP50"], 1.0)
        ; P95 兜底：含 kpd 在内的端到端时延上限，原阈值 20.0 原样保留。
        this.assert.isAtMost(m["p95"], 20.0)
    }

    ; 是否属于「只有 P95 兜底越界、其余判据全过」——宿主抢占签名，允许重试一次。
    ; 样本不足或中位数漂移都不属于宿主噪声，一律不重试。（本用例专用，勿与同族其它用例混用）
    _PeriodicE2ETailOnlyFail(m) {
        return (m["n"] >= 20) && (m["jitterP50"] <= 1.0) && (m["p95"] > 20.0)
    }

    ; periodic 端到端采样：返回 n / 调度偏差中位数 / 时延 P95（下划线开头，不收集为用例）
    _SamplePeriodicE2E(windowMs) {
        gid := "__prec_e2e"
        interval := 100
        events := []

        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([st, HighResClock.Now()])
        Sender.StartPeriodic(gid, ["F1"], [interval], 15)
        ; 等第一次 _ExecutePeriodic 建立基准时刻
        Sleep 40
        ; ⚠️ lastTriggerTimes 现在是**整数微秒**（调度内部口径），
        ; 而 events 里记录的 up/down 时刻仍是毫秒，interval 也是毫秒 —— 这里换算回 ms 再比较。
        t0 := Sender._activeGroups[gid]["lastTriggerTimes"][1] / 1000

        try {
            Sleep windowMs
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

        ; 第 i 次按下的计划时刻 = t0 + i * interval
        latencies := []
        i := 1
        while i <= downs.Length && i <= ups.Length {
            latencies.Push(ups[i] - (t0 + i * interval))
            i++
        }
        this._Sort(latencies)
        ; 偏差 = 端到端时延 - kpd：剩下的才是调度误差（中位数口径的回归信号）
        jitter := []
        for L in latencies
            jitter.Push(L - 15)
        this._Sort(jitter)

        ; 空样本时给必然越界的哨兵值，让断言如实失败而不是在这里抛下标越界
        return Map(
            "n", latencies.Length,
            "jitterP50", jitter.Length ? this._Pct(jitter, 0.5) : 999999.0,
            "p95", latencies.Length ? this._Pct(latencies, 0.95) : 999999.0
        )
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
        this._HostTiming()
        ; ---- TD-052：宿主负载下偶发红（与 hybrid 同因）----
        ; 采样窗口 2.2s → 4.4s（n≈44 → ≈88）。宿主抢占无法从代码侧消除：实测 p50 稳定 0.03ms，
        ; 但负载高时偶发 ~15ms（正好一个 15.625ms 定时器网格）的**孤立**离群点。n≈44 时
        ; P95 索引只容忍 2 个离群点，n≈88 时容忍 4 个。阈值一律不动。
        ; 重试口径同 TD-041：**只重试**「中位数判据全过、仅 P95 兜底越界」这一种宿主抢占签名；
        ; 中位数失败 = 系统性漂移 = 真回归，立即失败、绝不重试；重试留痕，不静默。
        m := this._SampleMultiKeyHold(4400)
        if (this._MultiKeyTailOnlyFail(m)) {
            msg := "[TD-052] multiKey 保持时长 P95=" Round(m["p95"], 3)
                . " 越界（中位数 " Round(m["p50"], 3) . "ms 正常，n=" m["n"]
                . "）→ 判定为宿主抢占，重试 1 次"
            FileAppend(msg "`n", "*", "UTF-8")
            FileAppend("      " msg "`r`n", A_ScriptDir "\test_results.log", "UTF-8")
            m := this._SampleMultiKeyHold(4400)
        }

        this.assert.isAtLeast(m["n"], 20)
        ; 中位数判系统性漂移（真正的回归信号），P95 用「一个调度网格」量级兜底。
        this.assert.isAtMost(m["p50"], 1.0)
        this.assert.isAtMost(m["p95"], 20.0)
    }

    ; 是否属于「只有 P95 兜底越界、其余判据全过」——宿主抢占签名，允许重试一次。
    ; （本用例专用，勿与同族其它用例混用）
    _MultiKeyTailOnlyFail(m) {
        return (m["n"] >= 20) && (m["p50"] <= 1.0) && (m["p95"] > 20.0)
    }

    ; 同刻多键保持时长采样：返回 n / 保持时长偏差中位数 / P95（下划线开头，不收集为用例）
    _SampleMultiKeyHold(windowMs) {
        gid := "__prec_multi"
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([key, st, HighResClock.Now()])
        Sender.StartPeriodic(gid, ["F1", "F2"], [100, 100], 15)
        try {
            Sleep windowMs
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
        this._Sort(holds)

        return Map(
            "n", holds.Length,
            "p50", holds.Length ? this._Pct(holds, 0.5) : 999999.0,
            "p95", holds.Length ? this._Pct(holds, 0.95) : 999999.0
        )
    }

    ; 确定性守卫：整数化后返回值必须是**精确的整数微秒**，且 1:3 比例不破
    ;
    ; ⚠️ 取值为什么是 16.001 / 48.003（而不是看起来更自然的 33.333 / 99.999）：
    ;   · 33.333 * 1000 在双精度下**恰好等于** 33333.0（99.999 同理 = 99999.0），
    ;     也就是说「不做取整」的浮点实现在这组取值上也返回精确整数 ——
    ;     用它做断言是**假阴性**，抓不到回归。
    ;   · 16.001 * 1000 = 16001.000000000002（末位脏），浮点实现会原样返回这个脏值，
    ;     只有真正做了取整的实现才会返回 16001。这才是有效的判别取值。
    ;
    ; ⚠️ 为什么必须有这一条：上面的端到端用例依赖**运行时 uptime 的浮点位模式**
    ; —— 浮点下 3 次累加与单次相加是否相等不可预测（扫描 uptime 空间：间隔 33.333
    ; 时拆桶率 48%~85%，即浮点实现也有约 20% 概率"恰好相等"而让用例通过）。
    ; 端到端用例因此**存在假阴性**，不能单独作为验收依据；本用例不依赖运行时量级。
    Test_IntervalUsOf_KeepsExactRatio_AfterRounding() {
        ; ---- 1. 整数性：脏值必须被取整成精确整数 ----
        this.assert.equal(Sender._IntervalUsOf([16.001], 1), 16001)
        this.assert.equal(Sender._IntervalUsOf([48.003], 1), 48003)
        ; 更强的形式：返回值必须没有小数部分
        this.assert.equal(Sender._IntervalUsOf([16.001], 1), Round(Sender._IntervalUsOf([16.001], 1)))
        ; ---- 2. 比例性：1:3 在整数域闭合（浮点下 16001.000000000002×3 ≠ 48003.0）----
        this.assert.equal(Sender._IntervalUsOf([16.001], 1) * 3, Sender._IntervalUsOf([48.003], 1))
        ; ---- 3. 下限夹紧（10 ms = 10000 µs）仍然生效 ----
        this.assert.equal(Sender._IntervalUsOf([1], 1), Sender.MIN_INTERVAL_US)
        this.assert.equal(Sender._DelayUsOf([1], 1), Sender.MIN_INTERVAL_US)
        ; ---- 4. 缺省值：periodic 50 ms，sequence 100 ms ----
        this.assert.equal(Sender._IntervalUsOf([], 1), 50000)
        this.assert.equal(Sender._DelayUsOf([], 1), 100000)
    }

    ; 分桶漂移回归：非整数间隔 1:3（33.333 ms / 99.999 ms）
    ;
    ; 数学上每 3 个 tick 两键同时到期（3 × 33.333 = 99.999）。但**浮点毫秒**累加会产生
    ; 末位误差：`(now+33.333)+33.333+33.333` 与 `now+99.999` 作为 double 并不相等，
    ; Map 把它们判成两个键、拆成两个桶 —— **后一个桶的按键保持时长会塌成 ~0ms**。
    ; 调度时刻改用**整数微秒**后 33333×3 = 99999 精确相等。
    ;
    ; 判据用**事件顺序**而不是时间差：同桶的表现是 down(F1) down(F2) up(F1) up(F2)，
    ; 拆桶则是 down(F1) up(F1) down(F2) up(F2)。顺序不受宿主调度抖动影响，
    ; 因此这条用例在负载高的 runner 上也不会像时延类断言那样偶发误报。
    ;
    ; ⚠️ 不能把间隔改成 [100, 100] 之类的整数：整数在 double 里精确表示，
    ; 浮点累加不会出错，这条用例会退化为恒绿（假阴性）。
    ;
    ; ⚠️ 本用例是**行为**守卫，不是判别守卫：33.333*1000 在双精度里恰好 = 33333.0
    ; （99.999 同理），浮点实现的拆桶率取决于运行时 uptime 的位模式（扫描结果
    ; 48%~85%，即约 20% 概率假阴性通过）。真正抓回归的是上面那条
    ; Test_IntervalUsOf_KeepsExactRatio_AfterRounding —— 本用例只是确认"端到端真的合并了"。
    Test_Periodic_NonIntegerInterval_Ratio1to3_MustNotSplitBucket() {
        gid := "__prec_ratio13"
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([key, st])
        Sender.StartPeriodic(gid, ["F1", "F2"], [33.333, 99.999], 5)
        try {
            Sleep 2600
        } finally {
            Sender.ToggleGroup(gid, false)
            Sender._sendHook := ""
        }

        f2Downs := 0
        merged := 0
        i := 1
        while i <= events.Length {
            if events[i][1] = "F2" && events[i][2] = "down" {
                f2Downs++
                if i > 1 && events[i - 1][2] = "down"
                    merged++
            }
            i++
        }

        this.assert.isAtLeast(f2Downs, 15)
        ; 理论上整数 µs 下必然 100% 合并；留到 90% 是为了容忍首个周期
        ; （基准刚建立、两键尚未对齐）的少数几次不同刻。
        this.assert.isAtLeast(merged / f2Downs, 0.90)
    }

    ; ============================================================
    ; T6 合并遍历（MERGE_TICK_SCAN）开关本身
    ; ============================================================

    ; 开关必须默认开启，且 _ExecutePeriodic 的分派必须真的走合并版。
    ;
    ; ⚠️ 为什么需要这条：下面的 Test_TickMerge_* 是**直接调用**两个实现做等价性比对，
    ;    它们绕过了 `_ExecutePeriodic` 的分派。也就是说，即使分派写坏（永远走 Legacy），
    ;    等价性用例照样全绿——T-B 的收益会静默消失。必须有独立用例钉住分派。
    ;
    ; 判别依据：`state["lastNextDue"]` **只有合并版会写**（提前返回路径与正常路径都写）。
    Test_MergeTickScan_DefaultOn_And_DispatchHonorsIt() {
        this.assert.isTrue(Sender.MERGE_TICK_SCAN)
        baseUs := HighResClock.NowUs()

        ; 开关为 true → 走合并版 → 一定会写 lastNextDue
        okTrue := this._DispatchWritesNextDue("__test_merge_on", baseUs, true)
        this.assert.isTrue(okTrue)
        ; 阳性对照：开关为 false → 走 Legacy → 一定不会写 lastNextDue
        ; （若这条也返回 true，说明 lastNextDue 这个判别依据失效，上面那条就是恒真）
        okFalse := this._DispatchWritesNextDue("__test_merge_off", baseUs, false)
        this.assert.isFalse(okFalse)

        ; hybrid 是第二个分派点，同样要钉住（否则它坏了没人知道）
        this.assert.isTrue(this._DispatchWritesNextDueHybrid("__test_merge_h_on", baseUs, true))
        this.assert.isFalse(this._DispatchWritesNextDueHybrid("__test_merge_h_off", baseUs, false))

        Sender.EmergencyRelease()
    }

    ; 按 flagValue 设置开关后跑一次 _ExecutePeriodic，返回是否写了 lastNextDue
    _DispatchWritesNextDue(gid, baseUs, flagValue) {
        origin := Sender.MERGE_TICK_SCAN
        try {
            if Sender._activeGroups.Has(gid)
                Sender._activeGroups.Delete(gid)
            Sender.MERGE_TICK_SCAN := flagValue
            Sender._StartGroup(gid)
            state := Sender._activeGroups[gid]
            state["mode"] := "periodic"
            state["keys"] := ["F1"]
            state["intervals"] := [100]
            state["keyPressDuration"] := 0
            tt := Map()
            tt[1] := baseUs - 1000000        ; 1 秒前的过去 → 必然已到期
            state["lastTriggerTimes"] := tt
            Sender._sendHook := (key, st) => 0
            try {
                Sender._ExecutePeriodic(gid)
            } finally {
                Sender._sendHook := ""
            }
            return state.Has("lastNextDue")
        } finally {
            Sender.MERGE_TICK_SCAN := origin
            Sender._StopGroup(gid)
        }
    }

    ; 同上，但走 _ExecuteHybrid（第二个分派点）
    _DispatchWritesNextDueHybrid(gid, baseUs, flagValue) {
        origin := Sender.MERGE_TICK_SCAN
        try {
            if Sender._activeGroups.Has(gid)
                Sender._activeGroups.Delete(gid)
            Sender.MERGE_TICK_SCAN := flagValue
            Sender._StartGroup(gid)
            state := Sender._activeGroups[gid]
            state["mode"] := "hybrid"
            state["keyPressDuration"] := 0
            state["groups"] := [Map("type", "periodic", "keys", ["F1"], "intervals", [100])]
            state["groupTriggerTimes"] := Map("1.1", baseUs - 1000000)
            Sender._sendHook := (key, st) => 0
            try {
                Sender._ExecuteHybrid(gid)
            } finally {
                Sender._sendHook := ""
            }
            return state.Has("lastNextDue")
        } finally {
            Sender.MERGE_TICK_SCAN := origin
            Sender._StopGroup(gid)
        }
    }

    ; ============================================================
    ; T6 合并遍历（MERGE_TICK_SCAN）等价性
    ; ============================================================
    ;
    ; 做法：**直接调用** _ExecutePeriodicLegacy / _ExecutePeriodicMerged，**不经定时器**，
    ; 并预先把 triggerTimes 设到「几秒之前的过去」。这样两次调用之间真实时钟的差值 δ
    ; 会被 catch-up 里的 `Floor((now - dueAt - iv) / iv)` 吃掉（只要 δ << interval，
    ; Floor 的结果就相同），**结果与真实时钟无关**，用例是确定性的。
    ;
    ; ⚠️ 不能用真实定时器各跑一遍再比对事件序列：宿主抖动会让两者落在不同的 tick 上，
    ; 产生假失败 —— 那不是回归，是测量方法的问题。
    ;
    ; ⚠️ 也不能用注入假时钟的办法：AHK v2 的**类静态方法只读**（实测
    ; `Clock.Now := () => 42` 报 "Property is read-only"），无法替换 HighResClock.NowUs。

    ; 跑一次指定实现，返回可比较的摘要串（事件序列 + 推进后的基准 + droppedTriggers）
    _RunPeriodicOnce(gid, keys, intervals, behind, baseUs, useMerged) {
        if Sender._activeGroups.Has(gid)
            Sender._activeGroups.Delete(gid)
        Sender._StartGroup(gid)
        state := Sender._activeGroups[gid]
        state["mode"] := "periodic"
        state["keys"] := keys
        state["intervals"] := intervals
        state["keyPressDuration"] := 0        ; kpd=0 → 走异步释放，不引入真实睡眠
        tt := Map()
        i := 1
        while i <= keys.Length {
            tt[i] := baseUs - behind[i] * 1000   ; behind 单位 ms → µs
            i++
        }
        state["lastTriggerTimes"] := tt

        events := []
        Sender._sendHook := (key, st) => events.Push([key, st])
        try {
            if useMerged
                Sender._ExecutePeriodicMerged(gid)
            else
                Sender._ExecutePeriodicLegacy(gid)
        } finally {
            Sender._sendHook := ""
        }

        s := ""
        for ev in events
            s .= ev[1] . ":" . ev[2] . ";"
        s .= "|tt="
        i := 1
        while i <= keys.Length {
            s .= (tt.Has(i) ? tt[i] : "nil") . ","
            i++
        }
        s .= "|dropped=" . (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0)

        ; 独立算出「下一次到期时刻」的真值：推进后的基准 + 各自间隔的最小值。
        ; 合并版把它记在 state["lastNextDue"]，必须与此相等 —— 这正是
        ; 「min(a_i - c) === min(a_i) - c」那步变换的校验点。
        expMin := 0x7FFFFFFFFFFF
        i := 1
        while i <= keys.Length {
            v := tt[i] + Sender._IntervalUsOf(intervals, i)
            if v < expMin
                expMin := v
            i++
        }
        nextDue := state.Has("lastNextDue") ? state["lastNextDue"] : ""
        Sender._activeGroups.Delete(gid)
        return [s, nextDue, expMin]
    }

    ; periodic：4 个确定性场景下合并版必须与旧版逐项一致
    Test_TickMerge_Periodic_MatchesLegacy() {
        scenarios := [
            ["uniform_all_due_same_bucket", ["F1", "F2", "F3"], [1000, 1000, 1000], [3000, 3000, 3000]],
            ["cross_interval_same_bucket", ["F1", "F2"], [1000, 2000], [3000, 4000]],
            ["two_due_distinct_buckets", ["F1", "F2", "F3"], [1000, 1500, 2500], [3000, 3100, 3000]],
            ["none_due_early_return", ["F1", "F2", "F3"], [1000, 1000, 1000], [0, 0, 0]]
        ]
        t0 := HighResClock.NowUs()
        mismatched := ""
        for sc in scenarios {
            a := this._RunPeriodicOnce("__tm_a", sc[2], sc[3], sc[4], t0, false)[1]
            b := this._RunPeriodicOnce("__tm_b", sc[2], sc[3], sc[4], t0, true)[1]
            if a != b
                mismatched .= sc[1] . "(old=" . a . " new=" . b . ") "
        }
        this.assert.equal(mismatched, "")
    }

    ; 合并版记下的 state["lastNextDue"] 必须等于「推进后基准 + 间隔」的最小值。
    ;
    ; 这一条是 T6 最关键的校验点：旧版在发送后重扫一遍求 min(tt+iv-nowAfter)，
    ; 合并版改成在遍历中记下 min(tt+iv) 再减一次 nowAfter。**两者只在整数 µs 下
    ; 严格相等**，所以必须有一条用例钉住它 —— 上面那条只比事件与基准，抓不到这里。
    Test_TickMerge_Periodic_NextDueMatchesFinalBase() {
        scenarios := [
            ["uniform_all_due_same_bucket", ["F1", "F2", "F3"], [1000, 1000, 1000], [3000, 3000, 3000]],
            ["cross_interval_same_bucket", ["F1", "F2"], [1000, 2000], [3000, 4000]],
            ["two_due_distinct_buckets", ["F1", "F2", "F3"], [1000, 1500, 2500], [3000, 3100, 3000]],
            ["none_due_early_return", ["F1", "F2", "F3"], [1000, 1000, 1000], [0, 0, 0]]
        ]
        t0 := HighResClock.NowUs()
        bad := ""
        for sc in scenarios {
            r := this._RunPeriodicOnce("__tm_nd", sc[2], sc[3], sc[4], t0, true)
            if r[2] != r[3]
                bad .= sc[1] . "(lastNextDue=" . r[2] . " expMin=" . r[3] . ") "
        }
        this.assert.equal(bad, "")
    }

    ; 跑一次 hybrid 的指定实现，返回可比较的摘要串
    _RunHybridOnce(gid, groups, gtt, useMerged) {
        if Sender._activeGroups.Has(gid)
            Sender._activeGroups.Delete(gid)
        Sender._StartGroup(gid)
        state := Sender._activeGroups[gid]
        state["mode"] := "hybrid"
        state["groups"] := groups
        state["keyPressDuration"] := 0
        state["groupTriggerTimes"] := gtt

        events := []
        Sender._sendHook := (key, st) => events.Push([key, st])
        try {
            if useMerged
                Sender._ExecuteHybridMerged(gid)
            else
                Sender._ExecuteHybridLegacy(gid)
        } finally {
            Sender._sendHook := ""
        }

        s := ""
        for ev in events
            s .= ev[1] . ":" . ev[2] . ";"
        s .= "|gtt="
        for k, v in gtt
            s .= k . "=" . v . ","
        s .= "|dropped=" . (state.Has("droppedTriggers") ? state["droppedTriggers"] : 0)

        ; 独立算出「下一次到期时刻」的真值（同 periodic 那条用例的理由）
        expMin := 0x7FFFFFFFFFFF
        g := 1
        for grp in groups {
            grpType := grp.Has("type") ? grp["type"] : "periodic"
            if grpType = "sequence" {
                v := gtt.Has(g ".nextTime") ? gtt[g ".nextTime"] : 0
                if v < expMin
                    expMin := v
            } else {
                grpKeys := grp.Has("pressKeys") ? grp["pressKeys"] : (grp.Has("keys") ? grp["keys"] : [])
                grpIntervals := grp.Has("intervals") ? grp["intervals"] : [50]
                i := 1
                while i <= grpKeys.Length {
                    v := gtt[g "." i] + Sender._IntervalUsOf(grpIntervals, i)
                    if v < expMin
                        expMin := v
                    i++
                }
            }
            g++
        }
        nextDue := state.Has("lastNextDue") ? state["lastNextDue"] : ""
        Sender._activeGroups.Delete(gid)
        return [s, nextDue, expMin]
    }

    ; hybrid：periodic 子组 + sequence 子组混合，合并版必须与旧版逐项一致
    Test_TickMerge_Hybrid_MatchesLegacy() {
        groups := [Map("type", "periodic", "keys", ["F1", "F2"], "intervals", [1000, 2000])
                 , Map("type", "sequence", "keys", ["F3", "F4"], "delays", [1000, 1500])]
        t0 := HighResClock.NowUs()
        ; behind = [periodic 第1键, periodic 第2键, sequence 下一个时刻]，单位 ms
        behinds := [[3000, 4000, 2000], [3000, 3100, 0], [0, 0, 0]]

        mismatched := ""
        for bh in behinds {
            ; 两次调用必须用**同一份**初始基准（t0），否则比的是不同的输入
            gttA := Map("1.1", t0 - bh[1] * 1000, "1.2", t0 - bh[2] * 1000
                      , "2.step", 1, "2.nextTime", t0 - bh[3] * 1000)
            gttB := Map("1.1", t0 - bh[1] * 1000, "1.2", t0 - bh[2] * 1000
                      , "2.step", 1, "2.nextTime", t0 - bh[3] * 1000)
            ra := this._RunHybridOnce("__th_a", groups, gttA, false)
            rb := this._RunHybridOnce("__th_b", groups, gttB, true)
            if ra[1] != rb[1]
                mismatched .= "behind=[" . bh[1] . "," . bh[2] . "," . bh[3] . "](old=" . ra[1] . " new=" . rb[1] . ") "
            ; 顺带校验合并版记下的 lastNextDue（同 periodic 那条用例）
            if rb[2] != rb[3]
                mismatched .= "nextDue behind=[" . bh[1] . "," . bh[2] . "," . bh[3] . "]("
                    . rb[2] . "!=" . rb[3] . ") "
        }
        this.assert.equal(mismatched, "")
    }

    ; 端到端：sequence 模式下「计划时刻 → 抬起完成」P95 ≤ 20ms。
    ; 原实现从「发送完成后的当前时刻」推进基准，误差逐步累积：
    ; 实测 delay=100ms 时步进退化成 111.9ms，3 秒内 P95 达 248~263ms。
    Test_ExecuteSequence_EndToEndLatencyP95Within20ms() {
        this._HostTiming()
        ; ---- TD-052：宿主负载下偶发红（与 hybrid 同因）----
        ; 采样窗口 4.2s → 8.4s（n≈42 → ≈84）。P95 是上分位估计：n≈42 时索引=40 等价
        ; 「第 3 大值」，宿主一次抢占即可顶穿 20.0；n≈84 时索引=80 等价「第 4 大值」。
        ; 阈值一律不动。重试口径同 TD-041：**只重试**「中位数判据全过、仅 P95 兜底越界」
        ; 这一种宿主抢占签名；中位数失败 = 系统性漂移 = 真回归，立即失败、绝不重试。
        m := this._SampleSequenceE2E(8400)
        if (this._SequenceE2ETailOnlyFail(m)) {
            msg := "[TD-052] sequence 端到端时延 P95=" Round(m["p95"], 3)
                . " 越界（偏差中位数 " Round(m["jitterP50"], 3) . "ms 正常，n=" m["n"]
                . "）→ 判定为宿主抢占，重试 1 次"
            FileAppend(msg "`n", "*", "UTF-8")
            FileAppend("      " msg "`r`n", A_ScriptDir "\test_results.log", "UTF-8")
            m := this._SampleSequenceE2E(8400)
        }

        this.assert.isAtLeast(m["n"], 20)
        ; 中位数判系统性漂移（口径同 Test_HighResClock_SleepUntil_ErrorBelow1ms）
        this.assert.isAtMost(m["jitterP50"], 1.0)
        ; P95 兜底：含 kpd 在内的端到端时延上限，原阈值 20.0 原样保留
        this.assert.isAtMost(m["p95"], 20.0)
    }

    ; 是否属于「只有 P95 兜底越界、其余判据全过」——宿主抢占签名，允许重试一次。
    ; （本用例专用，勿与同族其它用例混用）
    _SequenceE2ETailOnlyFail(m) {
        return (m["n"] >= 20) && (m["jitterP50"] <= 1.0) && (m["p95"] > 20.0)
    }

    ; sequence 端到端采样：返回 n / 调度偏差中位数 / 时延 P95（下划线开头，不收集为用例）
    _SampleSequenceE2E(windowMs) {
        gid := "__prec_seq_e2e"
        delay := 100
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([st, HighResClock.Now()])
        Sender.StartSequence(gid, ["F1", "F2"], [delay, delay], 15)
        try {
            Sleep windowMs
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

        ; 第 i 次按下的计划时刻 = 首次按下 + (i-1) * delay
        latencies := []
        i := 1
        while i <= ups.Length {
            latencies.Push(ups[i] - (downs[1] + (i - 1) * delay))
            i++
        }
        this._Sort(latencies)
        jitter := []
        for L in latencies
            jitter.Push(L - 15)
        this._Sort(jitter)

        return Map(
            "n", latencies.Length,
            "jitterP50", jitter.Length ? this._Pct(jitter, 0.5) : 999999.0,
            "p95", latencies.Length ? this._Pct(latencies, 0.95) : 999999.0
        )
    }

    ; sequence 步进必须等于配置的 delay，且不随时间漂移
    Test_ExecuteSequence_StepIntervalMatchesDelay_NoDrift() {
        this._HostTiming()
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
        this._HostTiming()
        ; ---- TD-052：宿主负载下偶发红（2026-09-17 G3b：722 跑 1 红，重跑即绿）----
        ; 成因已实测确认是**宿主抢占**，不是产品缺陷：
        ;   · 离群点恰好落在 Windows 调度网格 15.625ms 上（实测 14.97~15.30、21.9、26.4…）；
        ;   · 离群点在 F1 / F2 / F3 三个键上**均匀**出现，而每个键的中位数恒为 0.03ms
        ;     —— 若是某个键的实现缺陷，该键的分布会整体平移（中位数跟着走），实测没有。
        ; 判据一律不动（保持时长中位数 ≤1.0、P95 ≤20.0、步进中位数 ≤2.0），只做两件事：
        ;   ① 采样窗口 3.2s → 6.4s（n≈54 → ≈107）。P95 是**上分位估计**，n≈54 时它等价于
        ;      「第 3 大值」，个别极端离群点即可顶穿；n≈107 时等价「第 5 大值」，同样的
        ;      离群点数量不再顶穿 20.0。样本量同时满足「≥40」的既定规范。
        ;   ② 仍越界时按 TD-041 口径**重试一次**，且**只重试**「中位数判据全过、仅 P95
        ;      兜底越界」这一种宿主抢占签名（见 _HybridTailOnlyFail）。中位数一旦失败即
        ;      系统性漂移 = 真回归，立即失败、绝不重试；重试写进 stdout 与测试日志，不静默。
        m := this._SampleHybridRhythm(6400)
        if (this._HybridTailOnlyFail(m)) {
            msg := "[TD-052] hybrid 保持时长 P95=" Round(m["holdP95"], 3)
                . " 越界（中位数 " Round(m["holdP50"], 3) . "ms 正常，n=" m["holds"]
                . "）→ 判定为宿主抢占，重试 1 次"
            FileAppend(msg "`n", "*", "UTF-8")
            FileAppend("      " msg "`r`n", A_ScriptDir "\test_results.log", "UTF-8")
            m := this._SampleHybridRhythm(6400)
        }

        ; 两个子组都应有足够产出
        this.assert.isAtLeast(m["holds"], 20)
        this.assert.isAtLeast(m["seqSteps"], 15)

        ; 保持时长都精确等于 kpd：中位数判系统性漂移（真正的回归信号），
        ; P95 按一个调度网格量级兜底，拦住「整体拖尾崩坏」而不拦单次宿主抢占。
        this.assert.isAtMost(m["holdP50"], 1.0)
        this.assert.isAtMost(m["holdP95"], 20.0)

        ; periodic 子组保持 100ms 节奏（中位数判漂移，理由同 sequence 步进用例）
        this.assert.isAtLeast(m["f1Steps"], 20)
        this.assert.isAtMost(m["f1P50"], 2.0)

        ; sequence 子组内部相邻按下保持 150ms 节奏
        this.assert.isAtMost(m["seqP50"], 2.0)
    }

    ; 是否属于「只有 P95 兜底越界、其余判据全过」——这是宿主抢占的签名，允许重试一次。
    ; 样本不足或中位数漂移都不属于宿主噪声（是产品/采集问题），一律不重试。
    _HybridTailOnlyFail(m) {
        return (m["holds"] >= 20) && (m["seqSteps"] >= 15) && (m["f1Steps"] >= 20)
            && (m["holdP50"] <= 1.0) && (m["f1P50"] <= 2.0) && (m["seqP50"] <= 2.0)
            && (m["holdP95"] > 20.0)
    }

    ; hybrid 采样：驱动 periodic + sequence 两个子组，返回各判据的统计量。
    ; 抽成私有方法（下划线开头，不会被收集为用例）只为让上面的重试能复用同一段采集。
    _SampleHybridRhythm(windowMs) {
        gid := "__prec_hybrid"
        events := []
        Sender.EmergencyRelease()
        Sender._sendHook := (key, st) => events.Push([key, st, HighResClock.Now()])
        groups := [
            Map("type", "periodic", "pressKeys", ["F1"], "intervals", [100]),
            Map("type", "sequence", "pressKeys", ["F2", "F3"], "delays", [150, 150])
        ]
        Sender.StartHybrid(gid, groups, 15)
        ; 旧写法把 holds / steps 存进 Map，只留下最后一个样本 —— 一次宿主抖动即失败。
        try {
            Sleep windowMs
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

        holdErr := []
        for h in holds
            holdErr.Push(Abs(h - 15))
        this._Sort(holdErr)

        f1 := perSteps.Has("F1") ? perSteps["F1"] : []
        f1Steps := []
        i := 2
        while i <= f1.Length {
            f1Steps.Push(Abs(f1[i] - f1[i - 1] - 100))
            i++
        }
        this._Sort(f1Steps)

        seqErr := []
        for s in seqSteps
            seqErr.Push(Abs(s - 150))
        this._Sort(seqErr)

        ; 空样本时给一个必然越界的哨兵值，让断言如实失败（而不是在这里抛下标越界）
        return Map(
            "holds", holdErr.Length,
            "holdP50", holdErr.Length ? this._Pct(holdErr, 0.5) : 999999.0,
            "holdP95", holdErr.Length ? this._Pct(holdErr, 0.95) : 999999.0,
            "f1Steps", f1Steps.Length,
            "f1P50", f1Steps.Length ? this._Pct(f1Steps, 0.5) : 999999.0,
            "seqSteps", seqErr.Length,
            "seqP50", seqErr.Length ? this._Pct(seqErr, 0.5) : 999999.0
        )
    }
}
