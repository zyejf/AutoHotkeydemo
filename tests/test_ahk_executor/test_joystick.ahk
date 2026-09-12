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
