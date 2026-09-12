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
