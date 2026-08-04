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
    static _pollFn := 0
    static _povLastState := -1
    static _connPollActive := false
    static _connPollTimer := 0
    static _wasConnected := false
    static _joystickId := 1
    static _lastAxisState := Map()
    static _lastTriggerState := Map()
    static _lastPollErrLog := 0  ; I11: 轮询错误限速日志时间戳（每秒最多一次）
    static AXIS_HIGH := 70
    static AXIS_LOW := 30
    static TRIGGER_THRESHOLD := 60

    static Init(joystickId := 1) {
        JoyHotkeyManager._joystickId := joystickId
        JoyHotkeyManager._StartConnectionPoll()
    }

    ; A2: 生命周期清理方法 — 停止所有轮询定时器，防止资源泄漏
    ; 在 main.ahk 的 OnExit 回调中调用，确保连接轮询和轴/POV 轮询定时器被正确停止
    static Shutdown() {
        try {
            JoyHotkeyManager._StopConnectionPoll()
            JoyHotkeyManager._StopPolling()
        } catch as e {
            ErrorSystem.LogError("JoyHotkeyManager.Shutdown 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static RegisterHotkey(joyKey, groupId, callback) {
        try {
            if JoystickInput.IsButton(joyKey) {
                key := JoyHotkeyManager._joystickId joyKey
                if !JoyHotkeyManager._registered.Has(key) {
                    JoyHotkeyManager._registered[key] := []
                    Hotkey(key, (*) => JoyHotkeyManager._OnButtonPress(key), "On")
                }
                for entry in JoyHotkeyManager._registered[key] {
                    if entry["groupId"] = groupId
                        return true
                }
                JoyHotkeyManager._registered[key].Push(Map("groupId", groupId, "callback", callback, "joyKey", joyKey))
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
                if JoyHotkeyManager._registered.Has(key) {
                    entries := JoyHotkeyManager._registered[key]
                    if entries is Array {
                        newEntries := []
                        for _, info in entries {
                            if info["groupId"] != groupId
                                newEntries.Push(info)
                        }
                        if newEntries.Length = 0 {
                            JoyHotkeyManager._registered.Delete(key)
                            try
                                Hotkey(key, "Off")
                        } else {
                            JoyHotkeyManager._registered[key] := newEntries
                        }
                    } else {
                        JoyHotkeyManager._registered.Delete(key)
                        try
                            Hotkey(key, "Off")
                    }
                }
            } else {
                if JoyHotkeyManager._registered.Has(joyKey)
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
            if info is Array {
                for _, entry in info {
                    if entry["groupId"] = groupId {
                        keysToRemove.Push(key)
                        break
                    }
                }
            } else if info["groupId"] = groupId {
                keysToRemove.Push(key)
            }
        }
        for key in keysToRemove {
            entries := JoyHotkeyManager._registered[key]
            if entries is Array {
                newEntries := []
                for _, info in entries {
                    if info["groupId"] != groupId
                        newEntries.Push(info)
                }
                if newEntries.Length = 0 {
                    JoyHotkeyManager._registered.Delete(key)
                    try
                        Hotkey(key, "Off")
                } else {
                    JoyHotkeyManager._registered[key] := newEntries
                }
            } else {
                JoyHotkeyManager._registered.Delete(key)
                try
                    Hotkey(key, "Off")
            }
        }
        if JoyHotkeyManager._registered.Count = 0 {
            JoyHotkeyManager._StopPolling()
        }
    }

    static _OnButtonPress(key) {
        try {
            if JoyHotkeyManager._registered.Has(key) {
                entries := JoyHotkeyManager._registered[key]
                if entries is Array {
                    for _, info in entries {
                        try
                            info["callback"].Call(info["groupId"])
                    }
                } else {
                    info := JoyHotkeyManager._registered[key]
                    callback := info["callback"]
                    callback.Call(info["groupId"])
                }
            }
        } catch as e {
            ErrorSystem.LogError("_OnButtonPress 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _StartPolling() {
        if JoyHotkeyManager._pollActive
            return
        JoyHotkeyManager._pollActive := true
        JoyHotkeyManager._pollFn := () => JoyHotkeyManager._Poll()
        SetTimer(JoyHotkeyManager._pollFn, 50)
    }

    static _StopPolling() {
        JoyHotkeyManager._pollActive := false
        if JoyHotkeyManager._pollFn {
            SetTimer(JoyHotkeyManager._pollFn, 0)
            JoyHotkeyManager._pollFn := 0
        }
    }

    static _Poll() {
        if !JoyHotkeyManager._pollActive
            return
        try {
            JoyHotkeyManager._PollPov()
            JoyHotkeyManager._PollAxes()
            JoyHotkeyManager._PollTriggers()
        } catch as e {
            ; I11: 轮询方法限速日志（每秒最多一次）
            if (A_TickCount - JoyHotkeyManager._lastPollErrLog >= 1000) {
                JoyHotkeyManager._lastPollErrLog := A_TickCount
                OutputDebug("ASD [WARN] JoyHotkeyManager._Poll: " e.Message " at line " e.Line)
            }
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
            ; I11: 轮询方法限速日志（每秒最多一次）
            if (A_TickCount - JoyHotkeyManager._lastPollErrLog >= 1000) {
                JoyHotkeyManager._lastPollErrLog := A_TickCount
                OutputDebug("ASD [WARN] JoyHotkeyManager._PollPov: " e.Message " at line " e.Line)
            }
        }
    }

    static _TriggerPovCallback(direction, isActive) {
        if !isActive
            return
        povKey := "JoyPOV_" direction
        for key, info in JoyHotkeyManager._registered {
            if info is Map && info.Has("joyKey") && info["joyKey"] = povKey {
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
                ; I11: 轮询方法限速日志（每秒最多一次）
                if (A_TickCount - JoyHotkeyManager._lastPollErrLog >= 1000) {
                    JoyHotkeyManager._lastPollErrLog := A_TickCount
                    OutputDebug("ASD [WARN] JoyHotkeyManager._PollAxes: " e.Message " at line " e.Line)
                }
            }
        }
    }

    static _CheckAxisState(axis, pos, dirHigh, thresholdHigh, dirLow, thresholdLow) {
        highKey := axis "_" dirHigh
        lowKey := axis "_" dirLow

        lastState := JoyHotkeyManager._lastAxisState.Has(axis) ? JoyHotkeyManager._lastAxisState[axis] : 0
        newState := 0
        if pos > thresholdHigh
            newState := 1
        else if pos < thresholdLow
            newState := -1

        if newState != lastState {
            if newState = 1
                JoyHotkeyManager._TriggerJoyCallback(highKey)
            else if newState = -1
                JoyHotkeyManager._TriggerJoyCallback(lowKey)
            JoyHotkeyManager._lastAxisState[axis] := newState
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

                lastState := JoyHotkeyManager._lastTriggerState.Has(axis) ? JoyHotkeyManager._lastTriggerState[axis] : 0
                newState := pos > JoyHotkeyManager.TRIGGER_THRESHOLD ? 1 : 0

                if newState != lastState {
                    if newState = 1 {
                        triggerKey := axis "_DOWN"
                        JoyHotkeyManager._TriggerJoyCallback(triggerKey)
                    }
                    JoyHotkeyManager._lastTriggerState[axis] := newState
                }
            } catch as e {
                ; I11: 轮询方法限速日志（每秒最多一次）
                if (A_TickCount - JoyHotkeyManager._lastPollErrLog >= 1000) {
                    JoyHotkeyManager._lastPollErrLog := A_TickCount
                    OutputDebug("ASD [WARN] JoyHotkeyManager._PollTriggers: " e.Message " at line " e.Line)
                }
            }
        }
    }

    static _TriggerJoyCallback(joyKey) {
        for key, info in JoyHotkeyManager._registered {
            if info is Map && info.Has("joyKey") && info["joyKey"] = joyKey {
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
        JoyHotkeyManager._connPollTimer := () => JoyHotkeyManager._PollConnection()
        SetTimer(JoyHotkeyManager._connPollTimer, 30000)
    }

    static _StopConnectionPoll() {
        JoyHotkeyManager._connPollActive := false
        if JoyHotkeyManager._connPollTimer {
            SetTimer(JoyHotkeyManager._connPollTimer, 0)
            JoyHotkeyManager._connPollTimer := 0
        }
    }

    static _PollConnection() {
        try {
            isConnected := JoystickInput.IsJoystickConnected()
            if isConnected != JoyHotkeyManager._wasConnected {
                JoyHotkeyManager._wasConnected := isConnected
                if isConnected
                    ErrorSystem.LogError("手柄已重新连接", "DEBUG", A_ThisFunc, A_LineNumber)
                else
                    ErrorSystem.LogError("手柄已断开连接", "WARNING", A_ThisFunc, A_LineNumber)
            }
        } catch as e {
            ErrorSystem.LogError("_PollConnection 轮询异常: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static IsConnected() {
        return JoystickInput.IsJoystickConnected()
    }
}