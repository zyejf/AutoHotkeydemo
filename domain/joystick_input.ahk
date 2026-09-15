; =================================================================
; 领域层 - JoystickInput 手柄输入规范
; 版本: 1.0
; 说明: 定义手柄输入标识的解析、映射和验证规则
;       统一 Joy1 / JoyPOV_UP / JoyX_RIGHT 等标识的语义
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class JoystickInput {
    static THRESHOLD := 80
    static DEADZONE := 20
    static HYSTERESIS := 10

    static IsJoystickKey(key) {
        return JoystickInput.IsButton(key) || JoystickInput.IsPov(key)
            || JoystickInput.IsAxis(key) || JoystickInput.IsTrigger(key)
    }

    static IsButton(key) {
        return RegExMatch(key, "^Joy\d+$") && !RegExMatch(key, "^Joy[XYZRUV]")
    }

    static IsPov(key) {
        return InStr(key, "JoyPOV_") = 1
    }

    static IsAxis(key) {
        return RegExMatch(key, "^Joy[XYZRUV]_(LEFT|RIGHT|UP|DOWN)$")
    }

    static IsTrigger(key) {
        return key = "JoyZ_DOWN" || key = "JoyV_DOWN"
    }

    static GetButtonNum(key) {
        return Integer(RegExReplace(key, "^Joy", ""))
    }

    static GetPovDirection(key) {
        return StrReplace(key, "JoyPOV_", "")
    }

    static GetAxisInfo(key) {
        parts := StrSplit(key, "_")
        return Map("axis", parts[1], "target", parts[2])
    }

    static GetAhkReadKey(key) {
        if JoystickInput.IsButton(key) || JoystickInput.IsTrigger(key)
            return RegExReplace(key, "^(Joy\d+).*", "$1")
        if JoystickInput.IsAxis(key) {
            axis := StrSplit(key, "_")[1]
            return axis
        }
        if JoystickInput.IsPov(key)
            return "JoyPOV"
        return key
    }

    static PovToDirection(value) {
        if value = -1
            return ""
        ; ⚠️ value 是 AHK GetKeyState("NJoyPOV") 的原值，量纲是**百分之一度**
        ;    （0~35900，居中为 -1）。此前这里写成 Integer(value / 100)，
        ;    9000（右）被缩成 90，与下面 4500/13500/22500/31500 的阈值一比
        ;    恒 < 4500 → **任何方向都返回 "UP"**。
        ;    后果：joy_hotkey_manager 的 POV 热键首次移动后 prevDir = newDir = "UP"，
        ;    回调再也不触发（十字键等于失效）。2026-09-16 由新接入的
        ;    JoystickInputPovToDirectionTests 暴露并修复。
        angle := Integer(value)
        if angle >= 0 && angle < 4500
            return "UP"
        if angle >= 4500 && angle < 13500
            return "RIGHT"
        if angle >= 13500 && angle < 22500
            return "DOWN"
        if angle >= 22500 && angle < 31500
            return "LEFT"
        return "UP"
    }

    static DirectionToPovValue(direction) {
        switch direction {
            case "UP":    return 0
            case "RIGHT": return 9000
            case "DOWN":  return 18000
            case "LEFT":  return 27000
            default:      return -1
        }
    }

    static IsJoystickConnected() {
        try {
            return GetKeyState("1Joy1") != ""
        } catch {
            return false
        }
    }

    static GetConnectedJoysticks() {
        result := []
        Loop 16 {
            try {
                if GetKeyState(A_Index "Joy1") != ""
                    result.Push(A_Index)
            } catch {
                break
            }
        }
        return result
    }

    static GetButtonDisplayName(key) {
        names := Map(
            "Joy1", "(A)", "Joy2", "(B)", "Joy3", "(X)", "Joy4", "(Y)",
            "Joy5", "(LB)", "Joy6", "(RB)", "Joy7", "(Back)", "Joy8", "(Start)",
            "Joy9", "(LS)", "Joy10", "(RS)"
        )
        if names.Has(key)
            return key " " names[key]
        return key
    }

    static GetAllJoystickKeys() {
        result := []
        Loop 32
            result.Push("Joy" A_Index)
        for dir in ["UP", "DOWN", "LEFT", "RIGHT"]
            result.Push("JoyPOV_" dir)
        for _, pair in [["JoyX", ["LEFT", "RIGHT"]], ["JoyY", ["UP", "DOWN"]],
                         ["JoyR", ["LEFT", "RIGHT"]], ["JoyU", ["UP", "DOWN"]]] {
            for _, d in pair[2]
                result.Push(pair[1] "_" d)
        }
        result.Push("JoyZ_DOWN")
        result.Push("JoyV_DOWN")
        return result
    }
}