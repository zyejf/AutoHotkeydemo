#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../domain/interfaces.ahk"
#Include "../domain/joystick_input.ahk"
#Include "../domain/joystick_executor.ahk"
#Include "../infrastructure/joy_sender.ahk"

class JoyTestRunner {
    static total := 0
    static passed := 0
    static failed := 0

    static RunAll() {
        JoyTestRunner.RunTest("IsButton_Joy1", () => JoystickInput.IsButton("Joy1") ? 0 : Error("Joy1应为按钮"))
        JoyTestRunner.RunTest("IsButton_Joy15", () => JoystickInput.IsButton("Joy15") ? 0 : Error("Joy15应为按钮"))
        JoyTestRunner.RunTest("IsButton_Joy32", () => JoystickInput.IsButton("Joy32") ? 0 : Error("Joy32应为按钮"))
        JoyTestRunner.RunTest("IsButton_NotJoyX", () => JoystickInput.IsButton("JoyX") ? Error("JoyX不是按钮") : 0)
        JoyTestRunner.RunTest("IsButton_NotPov", () => JoystickInput.IsButton("JoyPOV_UP") ? Error("JoyPOV_UP不是按钮") : 0)
        JoyTestRunner.RunTest("IsPov_UP", () => JoystickInput.IsPov("JoyPOV_UP") ? 0 : Error("JoyPOV_UP应为POV"))
        JoyTestRunner.RunTest("IsPov_DOWN", () => JoystickInput.IsPov("JoyPOV_DOWN") ? 0 : Error("JoyPOV_DOWN应为POV"))
        JoyTestRunner.RunTest("IsPov_LEFT", () => JoystickInput.IsPov("JoyPOV_LEFT") ? 0 : Error("JoyPOV_LEFT应为POV"))
        JoyTestRunner.RunTest("IsPov_RIGHT", () => JoystickInput.IsPov("JoyPOV_RIGHT") ? 0 : Error("JoyPOV_RIGHT应为POV"))
        JoyTestRunner.RunTest("IsPov_NotButton", () => JoystickInput.IsPov("Joy1") ? Error("Joy1不是POV") : 0)
        JoyTestRunner.RunTest("IsAxis_JoyXRIGHT", () => JoystickInput.IsAxis("JoyX_RIGHT") ? 0 : Error("JoyX_RIGHT应为轴"))
        JoyTestRunner.RunTest("IsAxis_JoyYUP", () => JoystickInput.IsAxis("JoyY_UP") ? 0 : Error("JoyY_UP应为轴"))
        JoyTestRunner.RunTest("IsAxis_NotButton", () => JoystickInput.IsAxis("Joy1") ? Error("Joy1不是轴") : 0)
        JoyTestRunner.RunTest("IsTrigger_JoyZ", () => JoystickInput.IsTrigger("JoyZ_DOWN") ? 0 : Error("JoyZ_DOWN应为扳机"))
        JoyTestRunner.RunTest("IsTrigger_JoyV", () => JoystickInput.IsTrigger("JoyV_DOWN") ? 0 : Error("JoyV_DOWN应为扳机"))
        JoyTestRunner.RunTest("IsTrigger_NotAxis", () => JoystickInput.IsTrigger("JoyX_RIGHT") ? Error("JoyX_RIGHT不是扳机") : 0)
        JoyTestRunner.RunTest("GetButtonNum_Joy1", () => JoystickInput.GetButtonNum("Joy1") = 1 ? 0 : Error("Joy1应为1"))
        JoyTestRunner.RunTest("GetButtonNum_Joy15", () => JoystickInput.GetButtonNum("Joy15") = 15 ? 0 : Error("Joy15应为15"))
        JoyTestRunner.RunTest("GetPovDirection_UP", () => JoystickInput.GetPovDirection("JoyPOV_UP") = "UP" ? 0 : Error("应为UP"))
        JoyTestRunner.RunTest("GetPovDirection_LEFT", () => JoystickInput.GetPovDirection("JoyPOV_LEFT") = "LEFT" ? 0 : Error("应为LEFT"))
        JoyTestRunner.RunTest("GetAxisInfo", () => (info := JoystickInput.GetAxisInfo("JoyX_RIGHT"), info["axis"] = "JoyX" && info["target"] = "RIGHT") ? 0 : Error("轴解析失败"))
        JoyTestRunner.RunTest("GetAhkReadKey_Joy1", () => JoystickInput.GetAhkReadKey("Joy1") = "Joy1" ? 0 : Error("应为Joy1"))
        JoyTestRunner.RunTest("GetAhkReadKey_POV", () => JoystickInput.GetAhkReadKey("JoyPOV_UP") = "JoyPOV" ? 0 : Error("应为JoyPOV"))
        JoyTestRunner.RunTest("GetAhkReadKey_Axis", () => JoystickInput.GetAhkReadKey("JoyX_RIGHT") = "JoyX" ? 0 : Error("应为JoyX"))
        JoyTestRunner.RunTest("PovToDirection_UP", () => JoystickInput.PovToDirection(0) = "UP" ? 0 : Error("0应为UP"))
        JoyTestRunner.RunTest("PovToDirection_RIGHT", () => JoystickInput.PovToDirection(9000) = "RIGHT" ? 0 : Error("9000应为RIGHT"))
        JoyTestRunner.RunTest("PovToDirection_DOWN", () => JoystickInput.PovToDirection(18000) = "DOWN" ? 0 : Error("18000应为DOWN"))
        JoyTestRunner.RunTest("PovToDirection_LEFT", () => JoystickInput.PovToDirection(27000) = "LEFT" ? 0 : Error("27000应为LEFT"))
        JoyTestRunner.RunTest("PovToDirection_NONE", () => JoystickInput.PovToDirection(-1) = "" ? 0 : Error("-1应为空"))
        JoyTestRunner.RunTest("DirectionToPovValue", () => JoystickInput.DirectionToPovValue("UP") = 0 && JoystickInput.DirectionToPovValue("RIGHT") = 9000 ? 0 : Error("方向值映射失败"))
        JoyTestRunner.RunTest("IsJoystickKey_all", () => JoystickInput.IsJoystickKey("Joy1") && JoystickInput.IsJoystickKey("JoyPOV_UP") && JoystickInput.IsJoystickKey("JoyX_RIGHT") ? 0 : Error("IsJoystickKey应识别所有手柄键"))
        JoyTestRunner.RunTest("JoySender_IsVJoyAvailable", () => (result := JoySender.IsVJoyAvailable(), result = true || result = false) ? 0 : Error("应返回bool"))
        JoyTestRunner.RunTest("JoySender_ResolveMethod_auto", () => (method := JoySender.ResolveMethod("auto"), method = "vjoy" || method = "direct") ? 0 : Error("auto应解析为vjoy或direct"))

        JoyTestRunner.Report()
    }

    static RunTest(name, fn) {
        JoyTestRunner.total++
        try {
            fn()
            JoyTestRunner.passed++
        } catch as e {
            JoyTestRunner.failed++
            OutputDebug("FAIL: " name " -> " e.Message "`n")
        }
    }

    static Report() {
        OutputDebug("`n===== 手柄测试汇总 =====`n")
        OutputDebug("总计: " JoyTestRunner.total " | 通过: " JoyTestRunner.passed " | 失败: " JoyTestRunner.failed "`n")
        if JoyTestRunner.failed > 0
            ExitApp(1)
        ExitApp(0)
    }
}

JoyTestRunner.RunAll()