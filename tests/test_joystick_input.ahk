; =================================================================
; JoystickInput（domain）+ JoySender（infrastructure）测试
; =================================================================
; 覆盖 domain/joystick_input.ahk 的按键分类与映射逻辑：
;   IsButton / IsPov / IsAxis / IsTrigger / GetButtonNum / GetPovDirection /
;   GetAxisInfo / GetAhkReadKey / PovToDirection / DirectionToPovValue /
;   IsJoystickKey
; 以及 infrastructure/joy_sender.ahk 的 IsVJoyAvailable / ResolveMethod。
;
; ⚠️ 本文件设计为被 run_all_tests.ahk #Include，**不可独立运行**（无入口代码）。
;
; 历史（TD-002）：本文件原名 `tests/test_joystick.ahk`，是一个自带
; `JoyTestRunner` + `ExitApp` 的独立脚本 —— 因此它**无法被 #Include，
; 29 条断言从未在 CI 里执行过**。2026-09-16 改造：
;   1. 改名：原 basename 与 `test_ahk_executor/test_joystick.ahk` 撞名，
;      但两者测的**不是同一个类** —— 那边测 executor 的 `Joystick`，
;      这边测 domain 的 `JoystickInput`（`main.ahk:42` 仍在生产链路上 include 它）。
;      撞名会让后来者误以为是重复文件而误删。
;   2. 转成 AutoHotUnitSuite 并接入 run_all_tests，让这些断言真正跑起来。
; =================================================================

; =================================================================
; JoystickInput.IsButton 按钮识别
; =================================================================
class JoystickInputIsButtonTests extends AutoHotUnitSuite {
    Test_IsButton_Joy1() {
        this.assert.isTrue(JoystickInput.IsButton("Joy1"))
    }
    Test_IsButton_Joy15() {
        this.assert.isTrue(JoystickInput.IsButton("Joy15"))
    }
    Test_IsButton_Joy32() {
        this.assert.isTrue(JoystickInput.IsButton("Joy32"))
    }
    Test_IsButton_AxisIsNotButton() {
        this.assert.isFalse(JoystickInput.IsButton("JoyX"))
    }
    Test_IsButton_PovIsNotButton() {
        this.assert.isFalse(JoystickInput.IsButton("JoyPOV_UP"))
    }
}

; =================================================================
; JoystickInput.IsPov POV 识别
; =================================================================
class JoystickInputIsPovTests extends AutoHotUnitSuite {
    Test_IsPov_Up() {
        this.assert.isTrue(JoystickInput.IsPov("JoyPOV_UP"))
    }
    Test_IsPov_Down() {
        this.assert.isTrue(JoystickInput.IsPov("JoyPOV_DOWN"))
    }
    Test_IsPov_Left() {
        this.assert.isTrue(JoystickInput.IsPov("JoyPOV_LEFT"))
    }
    Test_IsPov_Right() {
        this.assert.isTrue(JoystickInput.IsPov("JoyPOV_RIGHT"))
    }
    Test_IsPov_ButtonIsNotPov() {
        this.assert.isFalse(JoystickInput.IsPov("Joy1"))
    }
}

; =================================================================
; JoystickInput.IsAxis 轴识别
; =================================================================
class JoystickInputIsAxisTests extends AutoHotUnitSuite {
    Test_IsAxis_XRight() {
        this.assert.isTrue(JoystickInput.IsAxis("JoyX_RIGHT"))
    }
    Test_IsAxis_YUp() {
        this.assert.isTrue(JoystickInput.IsAxis("JoyY_UP"))
    }
    Test_IsAxis_ButtonIsNotAxis() {
        this.assert.isFalse(JoystickInput.IsAxis("Joy1"))
    }
}

; =================================================================
; JoystickInput.IsTrigger 扳机识别
; =================================================================
class JoystickInputIsTriggerTests extends AutoHotUnitSuite {
    Test_IsTrigger_ZDown() {
        this.assert.isTrue(JoystickInput.IsTrigger("JoyZ_DOWN"))
    }
    Test_IsTrigger_VDown() {
        this.assert.isTrue(JoystickInput.IsTrigger("JoyV_DOWN"))
    }
    Test_IsTrigger_AxisIsNotTrigger() {
        this.assert.isFalse(JoystickInput.IsTrigger("JoyX_RIGHT"))
    }
}

; =================================================================
; JoystickInput.GetButtonNum 按钮号解析
; =================================================================
class JoystickInputGetButtonNumTests extends AutoHotUnitSuite {
    Test_GetButtonNum_Joy1() {
        this.assert.equal(JoystickInput.GetButtonNum("Joy1"), 1)
    }
    Test_GetButtonNum_Joy15() {
        this.assert.equal(JoystickInput.GetButtonNum("Joy15"), 15)
    }
}

; =================================================================
; JoystickInput.GetPovDirection POV 方向解析
; =================================================================
class JoystickInputGetPovDirectionTests extends AutoHotUnitSuite {
    Test_GetPovDirection_Up() {
        this.assert.equal(JoystickInput.GetPovDirection("JoyPOV_UP"), "UP")
    }
    Test_GetPovDirection_Left() {
        this.assert.equal(JoystickInput.GetPovDirection("JoyPOV_LEFT"), "LEFT")
    }
}

; =================================================================
; JoystickInput.GetAxisInfo 轴信息解析
; =================================================================
class JoystickInputGetAxisInfoTests extends AutoHotUnitSuite {
    Test_GetAxisInfo_XRight() {
        info := JoystickInput.GetAxisInfo("JoyX_RIGHT")
        this.assert.equal(info["axis"], "JoyX")
        this.assert.equal(info["target"], "RIGHT")
    }
}

; =================================================================
; JoystickInput.GetAhkReadKey AHK 读取键名映射
; =================================================================
class JoystickInputGetAhkReadKeyTests extends AutoHotUnitSuite {
    Test_GetAhkReadKey_Button() {
        this.assert.equal(JoystickInput.GetAhkReadKey("Joy1"), "Joy1")
    }
    Test_GetAhkReadKey_Pov() {
        this.assert.equal(JoystickInput.GetAhkReadKey("JoyPOV_UP"), "JoyPOV")
    }
    Test_GetAhkReadKey_Axis() {
        this.assert.equal(JoystickInput.GetAhkReadKey("JoyX_RIGHT"), "JoyX")
    }
}

; =================================================================
; JoystickInput.PovToDirection POV 数值 → 方向
; =================================================================
class JoystickInputPovToDirectionTests extends AutoHotUnitSuite {
    Test_PovToDirection_0_IsUp() {
        this.assert.equal(JoystickInput.PovToDirection(0), "UP")
    }
    Test_PovToDirection_9000_IsRight() {
        this.assert.equal(JoystickInput.PovToDirection(9000), "RIGHT")
    }
    Test_PovToDirection_18000_IsDown() {
        this.assert.equal(JoystickInput.PovToDirection(18000), "DOWN")
    }
    Test_PovToDirection_27000_IsLeft() {
        this.assert.equal(JoystickInput.PovToDirection(27000), "LEFT")
    }
    Test_PovToDirection_Negative_IsEmpty() {
        this.assert.isEmpty(JoystickInput.PovToDirection(-1))
    }
}

; =================================================================
; JoystickInput.DirectionToPovValue 方向 → POV 数值
; =================================================================
class JoystickInputDirectionToPovValueTests extends AutoHotUnitSuite {
    Test_DirectionToPovValue_UpAndRight() {
        this.assert.equal(JoystickInput.DirectionToPovValue("UP"), 0)
        this.assert.equal(JoystickInput.DirectionToPovValue("RIGHT"), 9000)
    }
}

; =================================================================
; JoystickInput.IsJoystickKey 手柄键总识别
; =================================================================
class JoystickInputIsJoystickKeyTests extends AutoHotUnitSuite {
    Test_IsJoystickKey_RecognizesAllKinds() {
        this.assert.isTrue(JoystickInput.IsJoystickKey("Joy1"))
        this.assert.isTrue(JoystickInput.IsJoystickKey("JoyPOV_UP"))
        this.assert.isTrue(JoystickInput.IsJoystickKey("JoyX_RIGHT"))
    }
}

; =================================================================
; JoySender.IsVJoyAvailable 返回值形态
; =================================================================
class JoySenderIsVJoyAvailableTests extends AutoHotUnitSuite {
    ; 只断言返回布尔值：是否真装了 vJoy 取决于宿主环境，不能断言真假。
    Test_IsVJoyAvailable_ReturnsBoolean() {
        result := JoySender.IsVJoyAvailable()
        this.assert.isTrue(result = true || result = false)
    }
}

; =================================================================
; JoySender.ResolveMethod 发送方式解析
; =================================================================
class JoySenderResolveMethodTests extends AutoHotUnitSuite {
    Test_ResolveMethod_Auto_ResolvesToKnownMethod() {
        method := JoySender.ResolveMethod("auto")
        this.assert.isTrue(method = "vjoy" || method = "direct")
    }
}
