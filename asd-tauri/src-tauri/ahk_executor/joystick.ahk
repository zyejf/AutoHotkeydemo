; =================================================================
; vJoy 操作 - IPC 指令驱动的手柄模拟
; 版本: 1.0
; 说明: 通过 DllCall 调用 vJoy SDK
;       支持 joystick_periodic, joystick_sequence, joystick_hold 模式
;       auto 模式自动检测 vJoy 可用性并降级
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class Joystick {
    ; Joystick 按键白名单 - 允许的按键名模式
    static ALLOWED_JOY_KEYS := Map(
        ; 按钮: Joy1 - Joy32 (标准手柄范围)
        "Joy1", true, "Joy2", true, "Joy3", true, "Joy4", true,
        "Joy5", true, "Joy6", true, "Joy7", true, "Joy8", true,
        "Joy9", true, "Joy10", true, "Joy11", true, "Joy12", true,
        "Joy13", true, "Joy14", true, "Joy15", true, "Joy16", true,
        "Joy17", true, "Joy18", true, "Joy19", true, "Joy20", true,
        "Joy21", true, "Joy22", true, "Joy23", true, "Joy24", true,
        "Joy25", true, "Joy26", true, "Joy27", true, "Joy28", true,
        "Joy29", true, "Joy30", true, "Joy31", true, "Joy32", true,
        ; POV 方向
        "JoyPOVUP", true, "JoyPOVDOWN", true, "JoyPOVLEFT", true, "JoyPOVRIGHT", true,
        ; 轴
        "JoyX", true, "JoyY", true, "JoyZ", true, "JoyR", true, "JoyU", true, "JoyV", true
    )

    ; vJoy 可用性: -1=未检测, 0=不可用, 1=可用
    static _vJoyAvailable := -1
    static _vJoyDeviceId := 1
    static _vJoyDll := ""
    static _vJoyRefCount := 0

    ; 活跃的执行组: groupId => 执行状态
    static _activeGroups := Map()

    ; 定时器引用: groupId => timerRef
    static _timers := Map()

    ; 释放定时器引用: groupId => (key => timerRef)，用于停止时取消滞后 up（T6-02）
    static _releaseTimers := Map()

    ; 按住的按键: groupId => [keys]
    static _heldJoyKeys := Map()

    ; =================================================================
    ; 初始化
    ; =================================================================

    static Init() {
        Joystick._DetectVJoy()
        OutputDebug("Joystick: 已初始化 vJoy=" (Joystick._vJoyAvailable = 1 ? "可用" : "不可用"))
    }

    ; =================================================================
    ; 公开方法
    ; =================================================================

    static IsVJoyAvailable() {
        if Joystick._vJoyAvailable = -1
            Joystick._DetectVJoy()
        return Joystick._vJoyAvailable = 1
    }

    ; 启动手柄周期性模式
    static StartPeriodic(groupId, joyKeys, joyIntervals, sendMethod := "auto", keyDuration := 15) {
        ; T6-04 幂等保护：若组已活跃则先彻底停掉旧的（含 vJoy Relinquish + 定时器取消）
        if Joystick._activeGroups.Has(groupId)
            Joystick.StopGroup(groupId)

        resolved := Joystick._ResolveMethod(sendMethod)

        ; T6-07: 组级 vJoy 生命周期 — 组启动时 Acquire 一次
        if resolved = "vjoy" {
            try
                Joystick._VJoyOpen()
            catch as e {
                OutputDebug("Joystick: vJoy Acquire 失败，降级为 direct: " e.Message)
                resolved := "direct"
            }
        }

        Joystick._activeGroups[groupId] := Map(
            "mode", "joystick_periodic",
            "joyKeys", joyKeys,
            "joyIntervals", joyIntervals,
            "sendMethod", resolved,
            "keyDuration", keyDuration,
            "lastTriggerTimes", Map()
        )

        timerFn := () => Joystick._ExecutePeriodic(groupId)
        Joystick._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Joystick: 启动周期性 groupId=" groupId " keys=" joyKeys.Length " method=" resolved)
    }

    ; 启动手柄序列模式
    static StartSequence(groupId, joyKeys, joyDelays, sendMethod := "auto", keyDuration := 15) {
        ; T6-04 幂等保护：若组已活跃则先彻底停掉旧的（含 vJoy Relinquish + 定时器取消）
        if Joystick._activeGroups.Has(groupId)
            Joystick.StopGroup(groupId)

        resolved := Joystick._ResolveMethod(sendMethod)

        ; T6-07: 组级 vJoy 生命周期 — 组启动时 Acquire 一次
        if resolved = "vjoy" {
            try
                Joystick._VJoyOpen()
            catch as e {
                OutputDebug("Joystick: vJoy Acquire 失败，降级为 direct: " e.Message)
                resolved := "direct"
            }
        }

        Joystick._activeGroups[groupId] := Map(
            "mode", "joystick_sequence",
            "joyKeys", joyKeys,
            "joyDelays", joyDelays,
            "sendMethod", resolved,
            "keyDuration", keyDuration,
            "currentStep", 1,
            "nextStepTime", A_TickCount
        )

        timerFn := () => Joystick._ExecuteSequence(groupId)
        Joystick._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Joystick: 启动序列 groupId=" groupId " keys=" joyKeys.Length " method=" resolved)
    }

    ; 启动手柄 Hold 模式
    static StartHold(groupId, joyKeys, sendMethod := "auto") {
        ; T6-04 幂等保护：若组已活跃则先彻底停掉旧的（含 vJoy Relinquish + 定时器取消）
        if Joystick._activeGroups.Has(groupId)
            Joystick.StopGroup(groupId)

        resolved := Joystick._ResolveMethod(sendMethod)

        ; T6-07: 组级 vJoy 生命周期 — 组启动时 Acquire 一次
        if resolved = "vjoy" {
            try
                Joystick._VJoyOpen()
            catch as e {
                OutputDebug("Joystick: vJoy Acquire 失败，降级为 direct: " e.Message)
                resolved := "direct"
            }
        }

        Joystick._activeGroups[groupId] := Map(
            "mode", "joystick_hold",
            "joyKeys", joyKeys,
            "sendMethod", resolved
        )

        ; 按住所有按键
        Joystick._heldJoyKeys[groupId] := joyKeys
        for k in joyKeys
            Joystick._SendJoyKey(k, "down", resolved)

        OutputDebug("Joystick: 启动 Hold groupId=" groupId " keys=" joyKeys.Length " method=" resolved)
    }

    ; 停止手柄执行组
    static StopGroup(groupId) {
        if !Joystick._activeGroups.Has(groupId)
            return

        state := Joystick._activeGroups[groupId]

        ; 停止定时器
        if Joystick._timers.Has(groupId) {
            SetTimer(Joystick._timers[groupId], 0)
            Joystick._timers.Delete(groupId)
        }

        ; T6-02: 取消该组的释放定时器，消除停止后滞后 up
        Joystick._CancelReleaseTimers(groupId)

        ; 释放 hold 按键
        if Joystick._heldJoyKeys.Has(groupId) {
            method := state.Has("sendMethod") ? state["sendMethod"] : "auto"
            for k in Joystick._heldJoyKeys[groupId]
                Joystick._SendJoyKey(k, "up", method)
            Joystick._heldJoyKeys.Delete(groupId)
        }

        ; T6-07: 组级 vJoy 生命周期 — 组停止时 Relinquish 一次
        if state.Has("sendMethod") && state["sendMethod"] = "vjoy"
            Joystick._VJoyClose()

        Joystick._activeGroups.Delete(groupId)
        OutputDebug("Joystick: 已停止 groupId=" groupId)
    }

    ; 紧急释放所有手柄按键
    static EmergencyRelease() {
        for groupId, state in Joystick._activeGroups {
            method := state.Has("sendMethod") ? state["sendMethod"] : "auto"
            if state.Has("joyKeys") {
                for k in state["joyKeys"]
                    Joystick._SendJoyKey(k, "up", method)
            }
            if Joystick._timers.Has(groupId) {
                SetTimer(Joystick._timers[groupId], 0)
            }
            ; T6-02: 取消该组的释放定时器
            Joystick._CancelReleaseTimers(groupId)
            ; T6-07: 组级 vJoy 生命周期 — 紧急释放时 Relinquish
            if method = "vjoy"
                Joystick._VJoyClose()
        }
        Joystick._activeGroups := Map()
        Joystick._timers := Map()
        Joystick._releaseTimers := Map()
        Joystick._heldJoyKeys := Map()
        OutputDebug("Joystick: 紧急释放完成")
    }

    ; =================================================================
    ; 执行引擎
    ; =================================================================

    static _ExecutePeriodic(groupId) {
        if !Joystick._activeGroups.Has(groupId)
            return

        state := Joystick._activeGroups[groupId]
        joyKeys := state["joyKeys"]
        joyIntervals := state["joyIntervals"]
        sendMethod := state["sendMethod"]
        keyDuration := state["keyDuration"]
        now := A_TickCount
        triggerTimes := state["lastTriggerTimes"]
        minRemaining := 0x7FFFFFFF

        for i, k in joyKeys {
            if !triggerTimes.Has(i) {
                triggerTimes[i] := now
                minRemaining := 1
                continue
            }

            interval := i <= joyIntervals.Length ? joyIntervals[i] : 50
            if interval < 10
                interval := 10

            elapsed := now - triggerTimes[i]
            threshold := interval - Max(1, Round(interval * 0.05))

            if elapsed >= threshold {
                capturedKey := k
                capturedMethod := sendMethod
                Joystick._SendJoyKey(capturedKey, "down", capturedMethod)
                Joystick._ScheduleRelease(groupId, capturedKey, capturedMethod, keyDuration)
                triggerTimes[i] := triggerTimes[i] + interval
                if triggerTimes[i] < now - interval
                    triggerTimes[i] := now
                minRemaining := 1
            } else {
                remaining := threshold - elapsed
                if remaining < minRemaining
                    minRemaining := remaining
            }
        }

        nextPoll := Max(1, minRemaining)
        if Joystick._timers.Has(groupId)
            SetTimer(Joystick._timers[groupId], -nextPoll)
    }

    static _ExecuteSequence(groupId) {
        if !Joystick._activeGroups.Has(groupId)
            return

        state := Joystick._activeGroups[groupId]
        joyKeys := state["joyKeys"]
        joyDelays := state["joyDelays"]
        sendMethod := state["sendMethod"]
        keyDuration := state["keyDuration"]
        now := A_TickCount

        step := state["currentStep"]
        if step > joyKeys.Length
            step := 1

        delay := step <= joyDelays.Length ? joyDelays[step] : 100
        if delay < 10
            delay := 10

        if state["nextStepTime"] = 0
            state["nextStepTime"] := now + delay

        if now < state["nextStepTime"] - 2 {
            remaining := Max(1, state["nextStepTime"] - now - 2)
            if Joystick._timers.Has(groupId)
                SetTimer(Joystick._timers[groupId], -remaining)
            return
        }

        k := joyKeys[step]
        capturedKey := k
        capturedMethod := sendMethod
        Joystick._SendJoyKey(capturedKey, "down", capturedMethod)
        Joystick._ScheduleRelease(groupId, capturedKey, capturedMethod, keyDuration)

        state["currentStep"] := Mod(step, joyKeys.Length) + 1
        nextDelay := state["currentStep"] <= joyDelays.Length ? joyDelays[state["currentStep"]] : 100
        if nextDelay < 10
            nextDelay := 10
        state["nextStepTime"] := A_TickCount + nextDelay

        if Joystick._timers.Has(groupId)
            SetTimer(Joystick._timers[groupId], -Max(1, nextDelay))
    }

    ; =================================================================
    ; vJoy 操作
    ; =================================================================

    static _DetectVJoy() {
        try {
            hModule := DllCall("LoadLibrary", "Str", "vJoyInterface.dll", "Ptr")
            if hModule {
                Joystick._vJoyDll := "vJoyInterface.dll"
                Joystick._vJoyAvailable := 1
                return
            }
        } catch {
        }
        try {
            hModule := DllCall("LoadLibrary", "Str", A_WinDir "\System32\vJoyInterface.dll", "Ptr")
            if hModule {
                Joystick._vJoyDll := A_WinDir "\System32\vJoyInterface.dll"
                Joystick._vJoyAvailable := 1
                return
            }
        } catch {
        }
        Joystick._vJoyAvailable := 0
    }

    static _ResolveMethod(method) {
        if method = "auto"
            return Joystick.IsVJoyAvailable() ? "vjoy" : "direct"
        if method = "vjoy" && !Joystick.IsVJoyAvailable()
            return "direct"
        return method
    }

    static _VJoyOpen() {
        if Joystick._vJoyRefCount > 0 {
            Joystick._vJoyRefCount++
            return true
        }
        h := DllCall(Joystick._vJoyDll "\AcquireVJD", "UInt", Joystick._vJoyDeviceId)
        if h = 0
            throw Error("vJoy AcquireVJD 失败，设备ID=" Joystick._vJoyDeviceId)
        Joystick._vJoyRefCount := 1
        return true
    }

    static _VJoyClose() {
        if Joystick._vJoyRefCount <= 0
            return
        Joystick._vJoyRefCount--
        if Joystick._vJoyRefCount = 0
            DllCall(Joystick._vJoyDll "\RelinquishVJD", "UInt", Joystick._vJoyDeviceId)
    }

    static _ValidateJoyKey(key) {
        if Joystick.ALLOWED_JOY_KEYS.Has(key)
            return true
        OutputDebug("Joystick: 按键被拒绝（不在白名单中） key=" key)
        return false
    }

    static _SendJoyKey(key, state, sendMethod := "auto") {
        try {
            if !Joystick._ValidateJoyKey(key)
                return

            if Joystick._IsButton(key) {
                btnNum := Joystick._GetButtonNum(key)
                if sendMethod = "vjoy"
                    Joystick._VJoySetBtn(btnNum, state = "down")
                else
                    Joystick._DirectSendBtn(btnNum, state)
            } else if Joystick._IsPov(key) {
                direction := Joystick._GetPovDirection(key)
                if sendMethod = "vjoy" {
                    if state = "down"
                        Joystick._VJoySetPov(Joystick._PovDirectionToValue(direction))
                    else
                        Joystick._VJoySetPov(0xFFFFFFFF)
                } else {
                    OutputDebug("Joystick: POV 按键在 direct 模式下不支持 key=" key " (需要 vJoy)")
                }
            } else if Joystick._IsAxis(key) {
                info := Joystick._GetAxisInfo(key)
                value := state = "down" ? 100 : 0
                if sendMethod = "vjoy"
                    Joystick._VJoySetAxis(info["axis"], value)
                else
                    OutputDebug("Joystick: Axis 按键在 direct 模式下不支持 key=" key " (需要 vJoy)")
            }
        } catch as e {
            OutputDebug("Joystick: _SendJoyKey 失败 key=" key " state=" state " err=" e.Message)
        }
    }

    static _VJoySetBtn(btnNum, state) {
        if btnNum < 1 || btnNum > 128 {
            OutputDebug("Joystick: vJoy 按键编号超出范围 btnNum=" btnNum)
            return
        }
        ; T6-07: 依赖组级已 Acquire，直接设置按键，不再每次 open/close
        DllCall(Joystick._vJoyDll "\SetBtn", "UInt", state ? 1 : 0, "UInt", Joystick._vJoyDeviceId, "UChar", btnNum)
    }

    static _VJoySetAxis(axis, value) {
        ; T6-07: 依赖组级已 Acquire，直接设置轴，不再每次 open/close
        axisId := Joystick._AxisToVJoyId(axis)
        scaledVal := Round(value * 327.67)
        if scaledVal < 0
            scaledVal := 0
        if scaledVal > 32767
            scaledVal := 32767
        DllCall(Joystick._vJoyDll "\SetAxis", "Int", scaledVal, "UInt", Joystick._vJoyDeviceId, "UInt", axisId)
    }

    static _VJoySetPov(povVal) {
        ; T6-07: 依赖组级已 Acquire，直接设置 POV，不再每次 open/close
        DllCall(Joystick._vJoyDll "\SetContPov", "UInt", povVal < 0 ? 0xFFFFFFFF : povVal, "UInt", Joystick._vJoyDeviceId, "UInt", 1)
    }

    static _DirectSendBtn(btnNum, state) {
        if btnNum < 1 || btnNum > 128 {
            OutputDebug("Joystick: 按键编号超出范围 btnNum=" btnNum)
            return
        }
        idx := Joystick._vJoyDeviceId
        action := state = "down" ? "Down" : "Up"
        SendInput("{Blind}{" idx "Joy" btnNum " " action "}")
    }

    ; =================================================================
    ; 释放定时器纳管（T6-02）
    ; 将逐键 up 一次性定时器登记进 _releaseTimers，分组停止时统一取消
    ; =================================================================

    static _ScheduleRelease(groupId, key, method, kpd) {
        if !Joystick._releaseTimers.Has(groupId)
            Joystick._releaseTimers[groupId] := Map()
        groupTimers := Joystick._releaseTimers[groupId]
        if groupTimers.Has(key)
            SetTimer(groupTimers[key], 0)
        timerFn := ((g, kk, mm) => () => Joystick._OnReleaseKey(g, kk, mm))(groupId, key, method)
        groupTimers[key] := timerFn
        SetTimer(timerFn, -kpd)
    }

    static _OnReleaseKey(groupId, key, method) {
        Joystick._SendJoyKey(key, "up", method)
        if Joystick._releaseTimers.Has(groupId) {
            groupTimers := Joystick._releaseTimers[groupId]
            if groupTimers.Has(key)
                groupTimers.Delete(key)
        }
    }

    static _CancelReleaseTimers(groupId) {
        if !Joystick._releaseTimers.Has(groupId)
            return
        for key, timerRef in Joystick._releaseTimers[groupId]
            SetTimer(timerRef, 0)
        Joystick._releaseTimers.Delete(groupId)
    }

    ; =================================================================
    ; 按键类型识别
    ; =================================================================

    static _IsButton(key) {
        return RegExMatch(key, "^Joy\d+$")
    }

    static _GetButtonNum(key) {
        return Integer(RegExReplace(key, "^Joy", ""))
    }

    static _IsPov(key) {
        return InStr(key, "JoyPOV") = 1
    }

    static _GetPovDirection(key) {
        if InStr(key, "UP")
            return "UP"
        if InStr(key, "DOWN")
            return "DOWN"
        if InStr(key, "LEFT")
            return "LEFT"
        if InStr(key, "RIGHT")
            return "RIGHT"
        return "CENTER"
    }

    static _IsAxis(key) {
        ; T6-07: 静态缓存轴名集合，避免每次 down/up 重建数组
        static axisSet := ""
        if axisSet = "" {
            axisSet := Map(
                "JoyX", true, "JoyY", true, "JoyZ", true,
                "JoyR", true, "JoyU", true, "JoyV", true
            )
        }
        return axisSet.Has(key)
    }

    static _GetAxisInfo(key) {
        ; T6-07: 静态缓存轴信息表，避免每次 down/up 重建 6 个子 Map
        static axisMap := ""
        if axisMap = "" {
            axisMap := Map(
                "JoyX", Map("axis", "JoyX", "id", 0x30),
                "JoyY", Map("axis", "JoyY", "id", 0x31),
                "JoyZ", Map("axis", "JoyZ", "id", 0x32),
                "JoyR", Map("axis", "JoyR", "id", 0x33),
                "JoyU", Map("axis", "JoyU", "id", 0x34),
                "JoyV", Map("axis", "JoyV", "id", 0x35)
            )
        }
        return axisMap.Has(key) ? axisMap[key] : Map("axis", "JoyX", "id", 0x30)
    }

    static _AxisToVJoyId(axis) {
        info := Joystick._GetAxisInfo(axis)
        return info["id"]
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
