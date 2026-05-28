; =================================================================
; 基础设施层 - JoySender 手柄按键发送器
; 版本: 1.0
; 说明: 双通道手柄按键发送 — vJoy API (游戏兼容) + 直接Send (无需驱动)
;       auto 模式自动检测vJoy可用性并降级
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "error_system.ahk"

class JoySender {
    static _vJoyAvailable := -1
    static _vJoyDeviceId := 1
    static _vJoyDll := ""
    static _vJoyRefCount := 0

    static IsVJoyAvailable() {
        if JoySender._vJoyAvailable != -1
            return JoySender._vJoyAvailable
        JoySender._vJoyAvailable := JoySender._DetectVJoy()
        return JoySender._vJoyAvailable
    }

    static _DetectVJoy() {
        try {
            hModule := DllCall("LoadLibrary", "Str", "vJoyInterface.dll", "Ptr")
            if hModule {
                JoySender._vJoyDll := "vJoyInterface.dll"
                return true
            }
        } catch {
        }
        try {
            hModule := DllCall("LoadLibrary", "Str", A_WinDir "\System32\vJoyInterface.dll", "Ptr")
            if hModule {
                JoySender._vJoyDll := A_WinDir "\System32\vJoyInterface.dll"
                return true
            }
        } catch {
        }
        return false
    }

    static ResolveMethod(method) {
        if method = "auto"
            return JoySender.IsVJoyAvailable() ? "vjoy" : "direct"
        if method = "vjoy" && !JoySender.IsVJoyAvailable()
            throw Error("vJoy 驱动未安装，无法使用 vjoy 发送方式")
        return method
    }

    static SendBtn(btnNum, state, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            if resolved = "vjoy"
                JoySender._VJoySetBtn(btnNum, state)
            else
                JoySender._DirectSendBtn(btnNum, state)
        } catch as e {
            ErrorSystem.LogError("JoySender.SendBtn vJoy发送失败，回退direct: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
            try {
                JoySender._DirectSendBtn(btnNum, state)
            } catch as e2 {
                ErrorSystem.LogError("JoySender.SendBtn direct回退也失败 btn=" btnNum " state=" state " err=" e2.Message, "WARNING", A_ThisFunc, A_LineNumber)
            }
        }
    }

    static SendPov(direction, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            povVal := JoySender._PovDirectionToValue(direction)
            if resolved = "vjoy"
                JoySender._VJoySetPov(povVal)
            else
                ErrorSystem.LogError("JoySender.SendPov: direct模式不支持POV发送 direction=" direction, "WARNING", A_ThisFunc, A_LineNumber)
        } catch as e {
            ErrorSystem.LogError("JoySender.SendPov 失败: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }

    static SendAxis(axis, value, method := "vjoy") {
        resolved := JoySender.ResolveMethod(method)
        try {
            if resolved = "vjoy"
                JoySender._VJoySetAxis(axis, value)
            else
                ErrorSystem.LogError("JoySender.SendAxis: direct模式不支持轴发送 axis=" axis, "WARNING", A_ThisFunc, A_LineNumber)
        } catch as e {
            ErrorSystem.LogError("JoySender.SendAxis 失败: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }

    static _VJoyOpen() {
        if JoySender._vJoyRefCount > 0 {
            JoySender._vJoyRefCount++
            return true
        }
        h := DllCall(JoySender._vJoyDll "\AcquireVJD", "UInt", JoySender._vJoyDeviceId)
        if h = 0
            throw Error("vJoy AcquireVJD 失败，设备ID=" JoySender._vJoyDeviceId)
        JoySender._vJoyRefCount := 1
        return true
    }

    static _VJoyClose() {
        if JoySender._vJoyRefCount <= 0
            return
        JoySender._vJoyRefCount--
        if JoySender._vJoyRefCount = 0
            DllCall(JoySender._vJoyDll "\RelinquishVJD", "UInt", JoySender._vJoyDeviceId)
    }

    static _VJoySetBtn(btnNum, state) {
        JoySender._VJoyOpen()
        try {
            DllCall(JoySender._vJoyDll "\SetBtn", "UInt", state ? 1 : 0, "UInt", JoySender._vJoyDeviceId, "UChar", btnNum)
        } finally {
            JoySender._VJoyClose()
        }
    }

    static _VJoySetAxis(axis, value) {
        JoySender._VJoyOpen()
        try {
            axisId := JoySender._AxisToVJoyId(axis)
            scaledVal := Round(value * 327.67)
            if scaledVal < 0
                scaledVal := 0
            if scaledVal > 32767
                scaledVal := 32767
            DllCall(JoySender._vJoyDll "\SetAxis", "Int", scaledVal, "UInt", JoySender._vJoyDeviceId, "UInt", axisId)
        } finally {
            JoySender._VJoyClose()
        }
    }

    static _VJoySetPov(povVal) {
        JoySender._VJoyOpen()
        try {
            DllCall(JoySender._vJoyDll "\SetContPov", "UInt", povVal < 0 ? 0xFFFFFFFF : povVal, "UInt", JoySender._vJoyDeviceId, "UInt", 1)
        } finally {
            JoySender._VJoyClose()
        }
    }

    static _AxisToVJoyId(axis) {
        m := Map(
            "JoyX", 0x30, "JoyY", 0x31, "JoyZ", 0x32,
            "JoyR", 0x33, "JoyU", 0x34, "JoyV", 0x35
        )
        return m.Has(axis) ? m[axis] : 0x30
    }

    static _DirectSendBtn(btnNum, state) {
        idx := JoySender._vJoyDeviceId
        action := state ? "Down" : "Up"
        SendInput("{Blind}{" idx "Joy" btnNum " " action "}")
    }

    static _PovDirectionToValue(direction) {
        switch direction {
            case "UP":    return 0
            case "RIGHT": return 9000
            case "DOWN":  return 18000
            case "LEFT":  return 27000
            case "CENTER":return -1
            default:      return -1
        }
    }
}