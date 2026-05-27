; =================================================================
; 基础设施层 - JoyHotkeyManager 手柄热键管理器
; 版本: 1.0
; 说明: 手柄按钮热键注册(Joy1~Joy32)、轴/POV轮询(SetTimer)
;       热插拔检测(30s)、多手柄支持
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/joystick_input.ahk"
#Include "error_system.ahk"

class JoyHotkeyManager {
    static _registered := Map()
    static _pollActive := false
    static _povLastState := -1
    static _connPollActive := false
    static _wasConnected := false
    static _joystickId := 1
    static AXIS_HIGH := 70
    static AXIS_LOW := 30
    static TRIGGER_THRESHOLD := 60

    static Init(joystickId := 1) {
        JoyHotkeyManager._joystickId := joystickId
        JoyHotkeyManager._StartConnectionPoll()
    }

    static RegisterHotkey(joyKey, groupId, callback) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                JoyHotkeyManager._registered[key] := Map("groupId", groupId, "callback", callback, "joyKey", joyKey)
                Hotkey(key, (*) => JoyHotkeyManager._OnButtonPress(key), "On")
                return true
            } else if JoystickInput.IsAxis(joyKey) || JoystickInput.IsTrigger(joyKey) {
                JoyHotkeyManager._registered[joyKey] := Map("groupId", groupId, "callback", callback, "joyKey", joyKey)
                JoyHotkeyManager._StartPolling()
                return true
            } else if JoystickInput.IsPov(joyKey) {
                JoyHotkeyManager._registered[joyKey] := Map("groupId", groupId, "callback", callback, "joyKey", joyKey)
                JoyHotkeyManager._StartPolling()
                return true
            }
            return false
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.RegisterHotkey 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    static UnregisterHotkey(joyKey, groupId) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                JoyHotkeyManager._registered.Delete(key)
                try
                    Hotkey(key, "Off")
            } else {
                JoyHotkeyManager._registered.Delete(joyKey)
            }
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.UnregisterHotkey 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
        if JoyHotkeyManager._registered.Count = 0
            JoyHotkeyManager._StopPolling()
    }

    static UnregisterAll(groupId) {
        keysToRemove := []
        for key, info in JoyHotkeyManager._registered {
            if info["groupId"] = groupId
                keysToRemove.Push(key)
        }
        for key in keysToRemove {
            JoyHotkeyManager._registered.Delete(key)
            try
                Hotkey(key, "Off")
        }
        if JoyHotkeyManager._registered.Count = 0 {
            JoyHotkeyManager._StopPolling()
        }
    }

    static _OnButtonPress(key) {
        try {
            if JoyHotkeyManager._registered.Has(key) {
                info := JoyHotkeyManager._registered[key]
                callback := info["callback"]
                callback.Call(info["groupId"])
            }
        } catch as e {
            ErrorSystem.LogError("_OnButtonPress 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _StartPolling() {
        if JoyHotkeyManager._pollActive
            return
        JoyHotkeyManager._pollActive := true
        SetTimer(JoyHotkeyManager._Poll, 50)
    }

    static _StopPolling() {
        JoyHotkeyManager._pollActive := false
        SetTimer(JoyHotkeyManager._Poll, 0)
    }

    static _Poll() {
        if !JoyHotkeyManager._pollActive
            return
        try {
            JoyHotkeyManager._PollPov()
            JoyHotkeyManager._PollAxes()
            JoyHotkeyManager._PollTriggers()
        } catch as e {
        }
    }

    static _PollPov() {
        try {
            val := GetKeyState(JoyHotkeyManager._joystickId "JoyPOV")
            if val = ""
                return
            if val != JoyHotkeyManager._povLastState {
                prevDir := JoystickInput.PovToDirection(JoyHotkeyManager._povLastState)
                newDir := JoystickInput.PovToDirection(val)
                JoyHotkeyManager._povLastState := val
                if prevDir != "" && prevDir != newDir
                    JoyHotkeyManager._TriggerPovCallback(prevDir, false)
                if newDir != ""
                    JoyHotkeyManager._TriggerPovCallback(newDir, true)
            }
        } catch as e {
        }
    }

    static _TriggerPovCallback(direction, isActive) {
        if !isActive
            return
        povKey := "JoyPOV_" direction
        for key, info in JoyHotkeyManager._registered {
            if info.Has("joyKey") && info["joyKey"] = povKey {
                try
                    info["callback"].Call(info["groupId"])
            }
        }
    }

    static _PollAxes() {
        axisKeys := ["JoyX", "JoyY", "JoyR", "JoyU"]
        for _, axis in axisKeys {
            try {
                val := GetKeyState(JoyHotkeyManager._joystickId axis)
                if val = ""
                    continue
                pos := Integer(val)
                JoyHotkeyManager._CheckAxisState(axis, pos, "RIGHT", JoyHotkeyManager.AXIS_HIGH, "LEFT", JoyHotkeyManager.AXIS_LOW)
            } catch as e {
            }
        }
    }

    static _CheckAxisState(axis, pos, dirHigh, thresholdHigh, dirLow, thresholdLow) {
        highKey := axis "_" dirHigh
        lowKey := axis "_" dirLow
        if pos > thresholdHigh {
            JoyHotkeyManager._TriggerJoyCallback(highKey)
        } else if pos < thresholdLow {
            JoyHotkeyManager._TriggerJoyCallback(lowKey)
        }
    }

    static _PollTriggers() {
        triggerAxes := ["JoyZ", "JoyV"]
        for _, axis in triggerAxes {
            try {
                val := GetKeyState(JoyHotkeyManager._joystickId axis)
                if val = ""
                    continue
                pos := Integer(val)
                if pos > JoyHotkeyManager.TRIGGER_THRESHOLD {
                    triggerKey := axis "_DOWN"
                    JoyHotkeyManager._TriggerJoyCallback(triggerKey)
                }
            } catch as e {
            }
        }
    }

    static _TriggerJoyCallback(joyKey) {
        for key, info in JoyHotkeyManager._registered {
            if info.Has("joyKey") && info["joyKey"] = joyKey {
                try
                    info["callback"].Call(info["groupId"])
            }
        }
    }

    static _StartConnectionPoll() {
        if JoyHotkeyManager._connPollActive
            return
        JoyHotkeyManager._connPollActive := true
        JoyHotkeyManager._wasConnected := JoystickInput.IsJoystickConnected()
        SetTimer(JoyHotkeyManager._PollConnection, 30000)
    }

    static _PollConnection() {
        try {
            isConnected := JoystickInput.IsJoystickConnected()
            if isConnected != JoyHotkeyManager._wasConnected {
                JoyHotkeyManager._wasConnected := isConnected
                if isConnected
                    ErrorSystem.LogError("手柄已重新连接", "INFO", A_ThisFunc, A_LineNumber)
                else
                    ErrorSystem.LogError("手柄已断开连接", "WARNING", A_ThisFunc, A_LineNumber)
            }
        } catch as e {
        }
    }

    static IsConnected() {
        return JoystickInput.IsJoystickConnected()
    }
}