; =================================================================
; test_joystick.ahk - 测试 AHK 执行器摇杆操作
; 目标：验证 joystick.ahk 中 Joystick 的按键识别、方法解析、状态管理
; 注意：vJoy DLL 在测试环境可能不可用，相关测试应接受降级情况
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; 被测脚本（main guard 确保被 #Include 时不自动初始化）
#Include "../../asd-tauri/src-tauri/ahk_executor/joystick.ahk"

; 测试框架（提供 AutoHotUnitSuite 基类）
#Include "../AutoHotUnit.ahk"

; 警告设置（在 #Include 之后，覆盖 AutoHotUnit.ahk 的 #Warn All）
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

; 运行时错误接管：输出到 stdout，阻止弹窗
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; joystick fixture 加载（T8-06：模式名从 fixture 派生，避免硬编码可复用测试数据）
; =================================================================

_JoystickFixtureMode(sample) {
    config := JSONParser.Parse(FileRead(A_ScriptDir "\fixtures\joystick_config.json", "UTF-8"))
    return config["GroupSettings"][sample]["mode"]
}

; =================================================================
; 测试套件：Joystick.ALLOWED_JOY_KEYS 按键白名单
; =================================================================

class JoystickAllowedKeysTests extends AutoHotUnitSuite {
    Test_AllowedJoyKeys_IsMap() {
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS is Map)
    }

    Test_AllowedJoyKeys_ContainsButtons() {
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("Joy1"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("Joy16"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("Joy32"))
    }

    Test_AllowedJoyKeys_ContainsPov() {
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyPOVUP"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyPOVDOWN"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyPOVLEFT"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyPOVRIGHT"))
    }

    Test_AllowedJoyKeys_ContainsAxes() {
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyX"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyY"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyZ"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyR"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyU"))
        this.assert.isTrue(Joystick.ALLOWED_JOY_KEYS.Has("JoyV"))
    }

    Test_AllowedJoyKeys_DoesNotContainInvalid() {
        this.assert.isFalse(Joystick.ALLOWED_JOY_KEYS.Has("Joy33"))
        this.assert.isFalse(Joystick.ALLOWED_JOY_KEYS.Has("InvalidKey"))
        this.assert.isFalse(Joystick.ALLOWED_JOY_KEYS.Has(""))
        this.assert.isFalse(Joystick.ALLOWED_JOY_KEYS.Has("JoyPOVCENTER"))
    }
}

; =================================================================
; 测试套件：Joystick._ValidateJoyKey 按键验证
; =================================================================

class JoystickValidateKeyTests extends AutoHotUnitSuite {
    Test_ValidateJoyKey_Whitelisted_ReturnsTrue() {
        this.assert.isTrue(Joystick._ValidateJoyKey("Joy1"))
        this.assert.isTrue(Joystick._ValidateJoyKey("Joy32"))
        this.assert.isTrue(Joystick._ValidateJoyKey("JoyX"))
        this.assert.isTrue(Joystick._ValidateJoyKey("JoyPOVUP"))
    }

    Test_ValidateJoyKey_NonWhitelisted_ReturnsFalse() {
        this.assert.isFalse(Joystick._ValidateJoyKey("Joy33"))
        this.assert.isFalse(Joystick._ValidateJoyKey("InvalidKey"))
    }

    Test_ValidateJoyKey_EmptyString_ReturnsFalse() {
        this.assert.isFalse(Joystick._ValidateJoyKey(""))
    }
}

; =================================================================
; 测试套件：Joystick._IsButton 按钮识别
; =================================================================

class JoystickIsButtonTests extends AutoHotUnitSuite {
    Test_IsButton_Joy1_ReturnsTrue() {
        this.assert.isTrue(Joystick._IsButton("Joy1"))
    }

    Test_IsButton_Joy32_ReturnsTrue() {
        this.assert.isTrue(Joystick._IsButton("Joy32"))
    }

    Test_IsButton_JoyX_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsButton("JoyX"))
    }

    Test_IsButton_JoyPOVUP_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsButton("JoyPOVUP"))
    }

    Test_IsButton_EmptyString_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsButton(""))
    }
}

; =================================================================
; 测试套件：Joystick._GetButtonNum 按钮编号提取
; =================================================================

class JoystickGetButtonNumTests extends AutoHotUnitSuite {
    Test_GetButtonNum_Joy1() {
        this.assert.equal(Joystick._GetButtonNum("Joy1"), 1)
    }

    Test_GetButtonNum_Joy32() {
        this.assert.equal(Joystick._GetButtonNum("Joy32"), 32)
    }

    Test_GetButtonNum_Joy16() {
        this.assert.equal(Joystick._GetButtonNum("Joy16"), 16)
    }
}

; =================================================================
; 测试套件：Joystick._IsPov POV 识别
; =================================================================

class JoystickIsPovTests extends AutoHotUnitSuite {
    Test_IsPov_UP() {
        this.assert.isTrue(Joystick._IsPov("JoyPOVUP"))
    }

    Test_IsPov_DOWN() {
        this.assert.isTrue(Joystick._IsPov("JoyPOVDOWN"))
    }

    Test_IsPov_LEFT() {
        this.assert.isTrue(Joystick._IsPov("JoyPOVLEFT"))
    }

    Test_IsPov_RIGHT() {
        this.assert.isTrue(Joystick._IsPov("JoyPOVRIGHT"))
    }

    Test_IsPov_Joy1_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsPov("Joy1"))
    }

    Test_IsPov_JoyX_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsPov("JoyX"))
    }
}

; =================================================================
; 测试套件：Joystick._GetPovDirection POV 方向提取
; =================================================================

class JoystickGetPovDirectionTests extends AutoHotUnitSuite {
    Test_GetPovDirection_UP() {
        this.assert.equal(Joystick._GetPovDirection("JoyPOVUP"), "UP")
    }

    Test_GetPovDirection_DOWN() {
        this.assert.equal(Joystick._GetPovDirection("JoyPOVDOWN"), "DOWN")
    }

    Test_GetPovDirection_LEFT() {
        this.assert.equal(Joystick._GetPovDirection("JoyPOVLEFT"), "LEFT")
    }

    Test_GetPovDirection_RIGHT() {
        this.assert.equal(Joystick._GetPovDirection("JoyPOVRIGHT"), "RIGHT")
    }

    Test_GetPovDirection_Unknown_ReturnsCenter() {
        this.assert.equal(Joystick._GetPovDirection("JoyPOVXYZ"), "CENTER")
    }
}

; =================================================================
; 测试套件：Joystick._IsAxis 轴识别
; =================================================================

class JoystickIsAxisTests extends AutoHotUnitSuite {
    Test_IsAxis_JoyX() {
        this.assert.isTrue(Joystick._IsAxis("JoyX"))
    }

    Test_IsAxis_JoyY() {
        this.assert.isTrue(Joystick._IsAxis("JoyY"))
    }

    Test_IsAxis_JoyZ() {
        this.assert.isTrue(Joystick._IsAxis("JoyZ"))
    }

    Test_IsAxis_JoyR() {
        this.assert.isTrue(Joystick._IsAxis("JoyR"))
    }

    Test_IsAxis_JoyU() {
        this.assert.isTrue(Joystick._IsAxis("JoyU"))
    }

    Test_IsAxis_JoyV() {
        this.assert.isTrue(Joystick._IsAxis("JoyV"))
    }

    Test_IsAxis_Joy1_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsAxis("Joy1"))
    }

    Test_IsAxis_JoyPOVUP_ReturnsFalse() {
        this.assert.isFalse(Joystick._IsAxis("JoyPOVUP"))
    }
}

; =================================================================
; 测试套件：Joystick._GetAxisInfo 轴信息
; =================================================================

class JoystickGetAxisInfoTests extends AutoHotUnitSuite {
    Test_GetAxisInfo_JoyX() {
        info := Joystick._GetAxisInfo("JoyX")
        this.assert.isTrue(info is Map)
        this.assert.equal(info["axis"], "JoyX")
        this.assert.equal(info["id"], 0x30)
    }

    Test_GetAxisInfo_JoyY() {
        info := Joystick._GetAxisInfo("JoyY")
        this.assert.equal(info["axis"], "JoyY")
        this.assert.equal(info["id"], 0x31)
    }

    Test_GetAxisInfo_JoyZ() {
        info := Joystick._GetAxisInfo("JoyZ")
        this.assert.equal(info["axis"], "JoyZ")
        this.assert.equal(info["id"], 0x32)
    }

    Test_GetAxisInfo_JoyR() {
        info := Joystick._GetAxisInfo("JoyR")
        this.assert.equal(info["axis"], "JoyR")
        this.assert.equal(info["id"], 0x33)
    }

    Test_GetAxisInfo_JoyU() {
        info := Joystick._GetAxisInfo("JoyU")
        this.assert.equal(info["axis"], "JoyU")
        this.assert.equal(info["id"], 0x34)
    }

    Test_GetAxisInfo_JoyV() {
        info := Joystick._GetAxisInfo("JoyV")
        this.assert.equal(info["axis"], "JoyV")
        this.assert.equal(info["id"], 0x35)
    }

    Test_GetAxisInfo_UnknownAxis_ReturnsDefault() {
        info := Joystick._GetAxisInfo("UnknownAxis")
        this.assert.isTrue(info is Map)
        this.assert.equal(info["axis"], "JoyX")
        this.assert.equal(info["id"], 0x30)
    }
}

; =================================================================
; 测试套件：Joystick._AxisToVJoyId 轴名转 vJoy ID
; =================================================================

class JoystickAxisToVJoyIdTests extends AutoHotUnitSuite {
    Test_AxisToVJoyId_JoyX() {
        this.assert.equal(Joystick._AxisToVJoyId("JoyX"), 0x30)
    }

    Test_AxisToVJoyId_JoyY() {
        this.assert.equal(Joystick._AxisToVJoyId("JoyY"), 0x31)
    }

    Test_AxisToVJoyId_JoyV() {
        this.assert.equal(Joystick._AxisToVJoyId("JoyV"), 0x35)
    }
}

; =================================================================
; 测试套件：Joystick._PovDirectionToValue POV 方向转值
; =================================================================

class JoystickPovDirectionToValueTests extends AutoHotUnitSuite {
    Test_PovDirectionToValue_UP() {
        this.assert.equal(Joystick._PovDirectionToValue("UP"), 0)
    }

    Test_PovDirectionToValue_RIGHT() {
        this.assert.equal(Joystick._PovDirectionToValue("RIGHT"), 9000)
    }

    Test_PovDirectionToValue_DOWN() {
        this.assert.equal(Joystick._PovDirectionToValue("DOWN"), 18000)
    }

    Test_PovDirectionToValue_LEFT() {
        this.assert.equal(Joystick._PovDirectionToValue("LEFT"), 27000)
    }

    Test_PovDirectionToValue_CENTER() {
        this.assert.equal(Joystick._PovDirectionToValue("CENTER"), -1)
    }

    Test_PovDirectionToValue_Unknown() {
        this.assert.equal(Joystick._PovDirectionToValue("UNKNOWN"), -1)
    }
}

; =================================================================
; 测试套件：Joystick._ResolveMethod 发送方法解析
; =================================================================

class JoystickResolveMethodTests extends AutoHotUnitSuite {
    Test_ResolveMethod_Direct_Preserved() {
        this.assert.equal(Joystick._ResolveMethod("direct"), "direct")
    }

    Test_ResolveMethod_Vjoy_WhenUnavailable_DowngradesToDirect() {
        if !Joystick.IsVJoyAvailable() {
            this.assert.equal(Joystick._ResolveMethod("vjoy"), "direct")
        } else {
            this.assert.equal(Joystick._ResolveMethod("vjoy"), "vjoy")
        }
    }

    Test_ResolveMethod_Auto_WhenUnavailable_ReturnsDirect() {
        if !Joystick.IsVJoyAvailable() {
            this.assert.equal(Joystick._ResolveMethod("auto"), "direct")
        } else {
            this.assert.equal(Joystick._ResolveMethod("auto"), "vjoy")
        }
    }

    Test_ResolveMethod_Auto_WhenAvailable_ReturnsVjoy() {
        if Joystick.IsVJoyAvailable() {
            this.assert.equal(Joystick._ResolveMethod("auto"), "vjoy")
        } else {
            this.assert.isTrue(true)
        }
    }

    Test_ResolveMethod_UnknownMethod_Preserved() {
        this.assert.equal(Joystick._ResolveMethod("unknown_method"), "unknown_method")
    }
}

; =================================================================
; 测试套件：Joystick.IsVJoyAvailable vJoy 可用性
; =================================================================

class JoystickIsVJoyAvailableTests extends AutoHotUnitSuite {
    Test_IsVJoyAvailable_ReturnsBoolean() {
        result := Joystick.IsVJoyAvailable()
        this.assert.isTrue(result = true || result = false)
    }

    Test_IsVJoyAvailable_DoesNotThrow() {
        try {
            Joystick.IsVJoyAvailable()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("IsVJoyAvailable 不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：Joystick.StopGroup 停止执行组
; =================================================================

class JoystickStopGroupTests extends AutoHotUnitSuite {
    Test_StopGroup_Unregistered_DoesNotThrow() {
        try {
            Joystick.StopGroup("__unregistered_joystick_group__")
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("StopGroup 未注册组不应抛出异常: " e.Message)
        }
    }
}

; =================================================================
; 测试套件：Joystick.EmergencyRelease 紧急释放
; =================================================================

class JoystickEmergencyReleaseTests extends AutoHotUnitSuite {
    Test_EmergencyRelease_DoesNotThrow() {
        try {
            Joystick.EmergencyRelease()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("EmergencyRelease 不应抛出异常: " e.Message)
        }
    }

    Test_EmergencyRelease_ClearsActiveGroups() {
        Joystick.EmergencyRelease()
        this.assert.equal(Joystick._activeGroups.Count, 0)
    }

    Test_EmergencyRelease_ClearsTimers() {
        Joystick.EmergencyRelease()
        this.assert.equal(Joystick._timers.Count, 0)
    }

    Test_EmergencyRelease_ClearsHeldKeys() {
        Joystick.EmergencyRelease()
        this.assert.equal(Joystick._heldJoyKeys.Count, 0)
    }
}

; =================================================================
; 测试套件：Joystick.Init 初始化
; =================================================================

class JoystickInitTests extends AutoHotUnitSuite {
    Test_Init_DoesNotThrow() {
        try {
            Joystick.Init()
            this.assert.isTrue(true)
        } catch as e {
            this.assert.fail("Init 不应抛出异常: " e.Message)
        }
    }

    Test_Init_SetsVJoyAvailability() {
        Joystick.Init()
        this.assert.isTrue(Joystick._vJoyAvailable = -1 || Joystick._vJoyAvailable = 0 || Joystick._vJoyAvailable = 1)
    }
}

; =================================================================
; 测试套件：Joystick.StartPeriodic 周期性模式（带清理）
; =================================================================

class JoystickStartPeriodicTests extends AutoHotUnitSuite {
    afterAll() {
        Joystick.EmergencyRelease()
    }

    Test_StartPeriodic_AddsToActiveGroups() {
        Joystick.EmergencyRelease()
        Joystick.StartPeriodic("__test_joy_p_1", ["Joy1"], [100], "direct", 15)
        this.assert.isTrue(Joystick._activeGroups.Has("__test_joy_p_1"))
        Joystick.StopGroup("__test_joy_p_1")
    }

    Test_StartPeriodic_SetsMode() {
        Joystick.EmergencyRelease()
        Joystick.StartPeriodic("__test_joy_p_2", ["Joy1"], [100], "direct", 15)
        state := Joystick._activeGroups["__test_joy_p_2"]
        this.assert.equal(state["mode"], _JoystickFixtureMode("joystick_periodic_sample"))
        Joystick.StopGroup("__test_joy_p_2")
    }

    Test_StartPeriodic_StoresJoyKeys() {
        Joystick.EmergencyRelease()
        Joystick.StartPeriodic("__test_joy_p_3", ["Joy1", "Joy2"], [100, 200], "direct", 15)
        state := Joystick._activeGroups["__test_joy_p_3"]
        this.assert.equal(state["joyKeys"].Length, 2)
        Joystick.StopGroup("__test_joy_p_3")
    }

    Test_StartPeriodic_RepeatedStart_OnlyOneTimer() {
        Joystick.EmergencyRelease()
        Joystick.StartPeriodic("__test_joy_p_4", ["Joy1"], [100], "direct", 15)
        Joystick.StartPeriodic("__test_joy_p_4", ["Joy1"], [100], "direct", 15)
        this.assert.isTrue(Joystick._timers.Has("__test_joy_p_4"))
        this.assert.equal(Joystick._timers.Count, 1)
        Joystick.StopGroup("__test_joy_p_4")
    }

    Test_StopGroup_CancelsReleaseTimers() {
        Joystick.EmergencyRelease()
        Joystick.StartPeriodic("__test_joy_rel", ["Joy1"], [100], "direct", 15)
        Joystick._ScheduleRelease("__test_joy_rel", "Joy1", "direct", 15)
        this.assert.isTrue(Joystick._releaseTimers.Has("__test_joy_rel"))
        this.assert.isTrue(Joystick._releaseTimers["__test_joy_rel"].Has("Joy1"))
        Joystick.StopGroup("__test_joy_rel")
        this.assert.isFalse(Joystick._releaseTimers.Has("__test_joy_rel"))
    }

    Test_VJoyRefCountStableDuringGroupLifetime() {
        Joystick.EmergencyRelease()
        if !Joystick.IsVJoyAvailable() {
            this.assert.isTrue(true)  ; vJoy 驱动不可用，跳过引用计数断言
            return
        }
        Joystick.StartPeriodic("__test_joy_ref", ["Joy1"], [100], "vjoy", 15)
        this.assert.equal(Joystick._vJoyRefCount, 1)
        Joystick._ExecutePeriodic("__test_joy_ref")
        Joystick._ExecutePeriodic("__test_joy_ref")
        this.assert.equal(Joystick._vJoyRefCount, 1)
        Joystick.StopGroup("__test_joy_ref")
        this.assert.equal(Joystick._vJoyRefCount, 0)
    }
}

; =================================================================
; 测试套件：Joystick.StartSequence 序列模式（带清理）
; =================================================================

class JoystickStartSequenceTests extends AutoHotUnitSuite {
    afterAll() {
        Joystick.EmergencyRelease()
    }

    Test_StartSequence_SetsMode() {
        Joystick.EmergencyRelease()
        Joystick.StartSequence("__test_joy_s_1", ["Joy1", "Joy2"], [100, 100], "direct", 15)
        state := Joystick._activeGroups["__test_joy_s_1"]
        this.assert.equal(state["mode"], _JoystickFixtureMode("joystick_sequence_sample"))
        Joystick.StopGroup("__test_joy_s_1")
    }

    Test_StartSequence_InitialStepIsOne() {
        Joystick.EmergencyRelease()
        Joystick.StartSequence("__test_joy_s_2", ["Joy1"], [100], "direct", 15)
        state := Joystick._activeGroups["__test_joy_s_2"]
        this.assert.equal(state["currentStep"], 1)
        Joystick.StopGroup("__test_joy_s_2")
    }
}

; =================================================================
; 测试套件：Joystick.StartHold Hold 模式（使用 direct 方法避免 vJoy 依赖）
; =================================================================

class JoystickStartHoldTests extends AutoHotUnitSuite {
    afterAll() {
        Joystick.EmergencyRelease()
    }

    Test_StartHold_SetsMode() {
        Joystick.EmergencyRelease()
        Joystick.StartHold("__test_joy_h_1", ["Joy1"], "direct")
        if Joystick._activeGroups.Has("__test_joy_h_1") {
            state := Joystick._activeGroups["__test_joy_h_1"]
            this.assert.equal(state["mode"], _JoystickFixtureMode("joystick_hold_sample"))
        } else {
            this.assert.isTrue(true)
        }
        Joystick.StopGroup("__test_joy_h_1")
    }

    Test_StartHold_StoresHeldKeys() {
        Joystick.EmergencyRelease()
        Joystick.StartHold("__test_joy_h_2", ["Joy1", "Joy2"], "direct")
        if Joystick._heldJoyKeys.Has("__test_joy_h_2") {
            this.assert.equal(Joystick._heldJoyKeys["__test_joy_h_2"].Length, 2)
        }
        Joystick.StopGroup("__test_joy_h_2")
    }
}

; =================================================================
; 测试替身：拦截 Joystick 的发送原语（与 Sender._sendHook 同约定）
;
; 用类静态字段而不是脚本级变量承接日志 —— AHK v2 的箭头函数不会闭包捕获
; 脚本级变量（函数 assume-local），而类静态成员是全局可达的。
; =================================================================

class JoyHookSpy {
    static log := []

    static Install() {
        JoyHookSpy.log := []
        Joystick._joySendHook := ((k, s) => JoyHookSpy.Record(k, s))
    }

    static Record(key, state) {
        JoyHookSpy.log.Push(key "|" state)
    }

    static DownCount() {
        n := 0
        for e in JoyHookSpy.log
            if InStr(e, "|down")
                n++
        return n
    }
}

; =================================================================
; 测试套件：Joystick 调度定刻（QPC 整数微秒 + 保相位推进）
;
; 判别性取值说明：间隔统一用 16.001ms。16.001 * 1000 = 16001.000000000002
; 在双精度下**不是**整数，若实现漏掉 Round() 这些断言会立刻变红；
; 而 33.333 / 99.999 这类取值乘 1000 恰好是整数，属假阴性，禁止使用。
; =================================================================

class JoystickSchedulingTests extends AutoHotUnitSuite {
    afterAll() {
        Joystick._joySendHook := ""
        Joystick.EmergencyRelease()
    }

    Test_IntervalAndDelayUs_AreIntegerMicroseconds() {
        this.assert.equal(Joystick._IntervalUsOf([16.001], 1), 16001)
        this.assert.equal(Joystick._DelayUsOf([16.001], 1), 16001)
        this.assert.equal(Joystick._IntervalUsOf([16.001], 1) * 3, Joystick._IntervalUsOf([48.003], 1))
        this.assert.equal(Joystick._IntervalUsOf([1], 1), Joystick.MIN_INTERVAL_US)
        this.assert.equal(Joystick._DelayUsOf([1], 1), Joystick.MIN_INTERVAL_US)
        this.assert.equal(Joystick._IntervalUsOf([], 1), 50000)
        this.assert.equal(Joystick._DelayUsOf([], 1), 100000)
    }

    ; 唤醒周期必须向上取整：Round 会早醒最多 0.5ms，而本实现没有 SleepUntilUs 兜底，
    ; 早醒 = 再排一个 <1ms 的定时器 = 被抬成 15.625ms 网格白吃一格（实测 3 秒多漂 15ms）
    Test_NextPollMs_UsesCeilNotRound() {
        this.assert.equal(Joystick._NextPollMs(1001), 2)
        this.assert.equal(Joystick._NextPollMs(1999), 2)
        this.assert.equal(Joystick._NextPollMs(100000), 100)
        this.assert.equal(Joystick._NextPollMs(500), 1)
        this.assert.equal(Joystick._NextPollMs(0), 1)
        this.assert.equal(Joystick._NextPollMs(-5000), 1)
    }

    Test_JoySendHook_InterceptsBothStates() {
        JoyHookSpy.Install()
        Joystick._SendJoyKey("Joy1", "down", "direct")
        Joystick._SendJoyKey("Joy1", "up", "direct")
        this.assert.equal(JoyHookSpy.log.Length, 2)
        this.assert.equal(JoyHookSpy.log[1], "Joy1|down")
        this.assert.equal(JoyHookSpy.log[2], "Joy1|up")
        ; 阳性对照：白名单校验先于钩子，非法键根本到不了钩子（否则上面三条恒真）
        Joystick._SendJoyKey("JoyBogus", "down", "direct")
        this.assert.equal(JoyHookSpy.log.Length, 2)
        Joystick._joySendHook := ""
    }

    ; 序列模式核心：基准必须从「本次的计划时刻」推进，而不是发送完成后的当前时刻。
    ; 旧实现 `nextStepTime := A_TickCount + nextDelay` 会把每步超时累积进下一步，
    ; 实测 delay=100ms 时步进退化成 110.8ms、3 秒累积漂移 +260ms。
    Test_Sequence_AdvancesBaseFromPlannedDue() {
        JoyHookSpy.Install()
        Joystick.EmergencyRelease()
        id := "__test_joy_seq_base"
        ; 延时取 1000ms、基准设在 0.5s 前：既让首步必然到期，又保证推进后的下一步
        ; 仍在未来（不触发追帧分支），于是「按计划时刻推进」与「按当前时刻推进」
        ; 会差出整整 500ms，断言不会被 µs 级抖动淹没。
        Joystick.StartSequence(id, ["Joy1", "Joy2"], [1000, 1000], "direct", 15)
        state := Joystick._activeGroups[id]
        baseUs := HighResClock.NowUs() - 500000
        state["nextStepTime"] := baseUs
        Joystick._ExecuteSequence(id)
        this.assert.equal(state["nextStepTime"], baseUs + 1000000)
        this.assert.equal(state["currentStep"], 2)
        this.assert.equal(JoyHookSpy.DownCount(), 1)
        ; 阳性对照：基准必须落在「+500ms 的近未来」。若改用当前时刻推进会得到 +1000ms，
        ; 上界断言立刻变红；若基准被漏推进则下界断言变红。
        this.assert.isTrue(state["nextStepTime"] > HighResClock.NowUs())
        this.assert.isTrue(state["nextStepTime"] < HighResClock.NowUs() + 900000)
        Joystick._joySendHook := ""
        Joystick.StopGroup(id)
    }

    ; 滞后时必须保相位单调推进，并把跳过的步数计入 droppedTriggers
    Test_Sequence_PreservesPhaseAndCountsDropped() {
        JoyHookSpy.Install()
        Joystick.EmergencyRelease()
        id := "__test_joy_seq_dropped"
        Joystick.StartSequence(id, ["Joy1", "Joy2"], [16.001, 16.001], "direct", 15)
        state := Joystick._activeGroups[id]
        baseUs := HighResClock.NowUs() - 200000
        state["nextStepTime"] := baseUs
        Joystick._ExecuteSequence(id)
        ; 200ms / 16.001ms = 12.5 → 跳过 12 步，基准落在 baseUs + 13*16001
        this.assert.equal(state["nextStepTime"], baseUs + 13 * 16001)
        this.assert.equal(state["droppedTriggers"], 12)
        ; 保相位：推进量必须是间隔的整数倍
        this.assert.equal(Mod(state["nextStepTime"] - baseUs, 16001), 0)
        Joystick._joySendHook := ""
        Joystick.StopGroup(id)
    }

    ; 周期性模式（**非追帧**路径）：正常到点触发时，基准必须推进到「本次的计划时刻」。
    ; 注意必须走非追帧路径 —— 一旦落后超过一个周期，推进量会被追帧分支重算，
    ; 把「用当前时刻当基准」的缺陷掩盖掉（这正是本用例存在的理由）。
    Test_Periodic_AdvancesBaseFromPlannedDue() {
        JoyHookSpy.Install()
        Joystick.EmergencyRelease()
        id := "__test_joy_per_base"
        Joystick.StartPeriodic(id, ["Joy1"], [16.001], "direct", 15)
        state := Joystick._activeGroups[id]
        ; 落后 28ms：已越过本次计划时刻（+16.001ms），但下一次计划时刻（+32.002ms）
        ; 仍在未来，因此不会进追帧分支 —— `last := dueAt` 的结果可被精确断言。
        baseUs := HighResClock.NowUs() - 28000
        state["lastTriggerTimes"][1] := baseUs
        Joystick._ExecutePeriodic(id)
        tt := state["lastTriggerTimes"]
        this.assert.equal(tt[1], baseUs + 16001)
        this.assert.equal(JoyHookSpy.DownCount(), 1)
        this.assert.isFalse(state.Has("droppedTriggers"))
        ; 阳性对照：若基准被写成「当前时刻」，它就不会还停在 1ms 之前的过去
        this.assert.isTrue(tt[1] < HighResClock.NowUs() - 1000)
        Joystick._joySendHook := ""
        Joystick.StopGroup(id)
    }

    ; 周期性模式：滞后时保相位推进 + 计入 droppedTriggers，
    ; 旧实现 `triggerTimes[i] := now` 会丢相位并吞掉本应发生的触发
    Test_Periodic_PreservesPhaseAndCountsDropped() {
        JoyHookSpy.Install()
        Joystick.EmergencyRelease()
        id := "__test_joy_per_dropped"
        Joystick.StartPeriodic(id, ["Joy1"], [16.001], "direct", 15)
        state := Joystick._activeGroups[id]
        baseUs := HighResClock.NowUs() - 200000
        state["lastTriggerTimes"][1] := baseUs
        Joystick._ExecutePeriodic(id)
        tt := state["lastTriggerTimes"]
        this.assert.equal(tt[1], baseUs + 12 * 16001)
        this.assert.equal(state["droppedTriggers"], 11)
        this.assert.equal(Mod(tt[1] - baseUs, 16001), 0)
        ; 阳性对照：若基准被重置为当前时刻，它就不会还停在 1ms 之前的过去
        this.assert.isTrue(tt[1] < HighResClock.NowUs() - 1000)
        Joystick._joySendHook := ""
        Joystick.StopGroup(id)
    }

    ; 不允许「提前触发」：旧实现 threshold := interval - 5%，配置 100ms 实际按 95ms 发
    Test_Periodic_DoesNotFireBeforeConfiguredInterval() {
        JoyHookSpy.Install()
        Joystick.EmergencyRelease()
        id := "__test_joy_per_early"
        Joystick.StartPeriodic(id, ["Joy1"], [100], "direct", 15)
        state := Joystick._activeGroups[id]
        ; 已过 95ms < 100ms —— 旧实现的 5% 容差会在这里触发，新实现不应触发
        state["lastTriggerTimes"][1] := HighResClock.NowUs() - 95000
        Joystick._ExecutePeriodic(id)
        this.assert.equal(JoyHookSpy.DownCount(), 0)
        ; 阳性对照：再过 8ms 越过 100ms 后必须触发（证明上面那条不是恒真）
        state["lastTriggerTimes"][1] := HighResClock.NowUs() - 103000
        Joystick._ExecutePeriodic(id)
        this.assert.equal(JoyHookSpy.DownCount(), 1)
        Joystick._joySendHook := ""
        Joystick.StopGroup(id)
    }

    ; 空按键表：旧实现在 `_ExecuteSequence` 里 Mod(step, 0) 会除零、joyKeys[1] 会越界
    Test_EmptyJoyKeys_SchedulerIsNoop() {
        JoyHookSpy.Install()
        Joystick.EmergencyRelease()
        id := "__test_joy_empty"
        Joystick.StartSequence(id, [], [], "direct", 15)
        Joystick._ExecuteSequence(id)
        this.assert.equal(Joystick._activeGroups[id]["currentStep"], 1)
        Joystick.StopGroup(id)
        Joystick.StartPeriodic(id, [], [], "direct", 15)
        Joystick._ExecutePeriodic(id)
        this.assert.equal(Joystick._activeGroups[id]["joyKeys"].Length, 0)
        this.assert.equal(JoyHookSpy.DownCount(), 0)
        Joystick._joySendHook := ""
        Joystick.StopGroup(id)
    }
}
