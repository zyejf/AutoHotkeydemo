; =================================================================
; 按键发送器 - IPC 指令驱动的按键执行
; 版本: 1.0
; 说明: 收到 IPC 执行指令时发送按键
;       支持各种执行模式（periodic, sequence, enhanced_*）
;       使用 AHK Send/SendInput 命令
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "ipc_client.ahk"

class Sender {
    ; 活跃的执行组: groupId => 执行状态
    static _activeGroups := Map()

    ; 定时器引用: groupId => timerRef
    static _timers := Map()

    ; Hold 模式按住的键: groupId => [keys]
    static _heldKeys := Map()

    ; Hold 模式状态
    static _holdModeEnabled := true

    ; 按键白名单
    static ALLOWED_KEYS := Map(
        "F1", true, "F2", true, "F3", true, "F4", true, "F5", true, "F6", true,
        "F7", true, "F8", true, "F9", true, "F10", true, "F11", true, "F12", true,
        "1", true, "2", true, "3", true, "4", true, "5", true,
        "6", true, "7", true, "8", true, "9", true, "0", true,
        "a", true, "b", true, "c", true, "d", true, "e", true, "f", true,
        "g", true, "h", true, "i", true, "j", true, "k", true, "l", true,
        "m", true, "n", true, "o", true, "p", true, "q", true, "r", true,
        "s", true, "t", true, "u", true, "v", true, "w", true, "x", true,
        "y", true, "z", true,
        "Space", true, "Enter", true, "Tab", true, "Esc", true, "Backspace", true,
        "Delete", true, "Insert", true, "Home", true, "End", true,
        "PgUp", true, "PgDn", true,
        "Up", true, "Down", true, "Left", true, "Right", true,
        "Shift", true, "Ctrl", true, "Alt", true, "LWin", true, "RWin", true,
        "LShift", true, "RShift", true, "LCtrl", true, "RCtrl", true,
        "LAlt", true, "RAlt", true,
        "Numpad0", true, "Numpad1", true, "Numpad2", true, "Numpad3", true,
        "Numpad4", true, "Numpad5", true, "Numpad6", true, "Numpad7", true,
        "Numpad8", true, "Numpad9", true,
        "NumpadEnter", true, "NumpadAdd", true, "NumpadSub", true,
        "NumpadMult", true, "NumpadDiv", true,
        "Joy1", true, "Joy2", true, "Joy3", true, "Joy4", true,
        "Joy5", true, "Joy6", true, "Joy7", true, "Joy8", true,
        "Joy9", true, "Joy10", true, "Joy11", true, "Joy12", true,
        "Joy13", true, "Joy14", true, "Joy15", true, "Joy16", true,
        "Joy17", true, "Joy18", true, "Joy19", true, "Joy20", true,
        "Joy21", true, "Joy22", true, "Joy23", true, "Joy24", true,
        "Joy25", true, "Joy26", true, "Joy27", true, "Joy28", true,
        "Joy29", true, "Joy30", true, "Joy31", true, "Joy32", true,
        "JoyX", true, "JoyY", true, "JoyZ", true, "JoyR", true,
        "JoyU", true, "JoyV", true,
        "JoyPOVUP", true, "JoyPOVDOWN", true,
        "JoyPOVLEFT", true, "JoyPOVRIGHT", true
    )

    ; =================================================================
    ; 公开方法
    ; =================================================================

    static Init() {
        OutputDebug("Sender: 已初始化")
    }

    ; 切换技能组激活状态
    static ToggleGroup(groupId, active) {
        if active
            return Sender._StartGroup(groupId)
        else
            return Sender._StopGroup(groupId)
    }

    ; 紧急释放所有按键
    static EmergencyRelease() {
        OutputDebug("Sender: 紧急释放所有按键")

        ; 停止所有执行组
        groupIds := []
        for id in Sender._activeGroups
            groupIds.Push(id)
        for id in groupIds
            Sender._StopGroup(id)

        ; 释放所有 hold 按键
        for groupId, keys in Sender._heldKeys {
            for k in keys
                Sender._SendKeyUp(k)
        }
        Sender._heldKeys := Map()

        OutputDebug("Sender: 紧急释放完成")
    }

    ; Hold 模式切换
    static HoldModeToggle(enabled) {
        Sender._holdModeEnabled := enabled
        OutputDebug("Sender: Hold 模式 " (enabled ? "启用" : "禁用"))

        if !enabled {
            ; 释放所有 hold 按键
            for groupId, keys in Sender._heldKeys {
                for k in keys
                    Sender._SendKeyUp(k)
            }
            Sender._heldKeys := Map()
        }
    }

    ; 关机清理
    static Shutdown() {
        Sender.EmergencyRelease()
        OutputDebug("Sender: 已关机")
    }

    ; =================================================================
    ; 执行组管理
    ; =================================================================

    static _StartGroup(groupId) {
        if Sender._activeGroups.Has(groupId) {
            OutputDebug("Sender: 组已激活 groupId=" groupId)
            return true
        }

        Sender._activeGroups[groupId] := Map(
            "startTime", A_TickCount,
            "lastTriggerTimes", Map(),
            "currentStep", 1,
            "nextStepTime", 0
        )

        OutputDebug("Sender: 已激活 groupId=" groupId)
        return true
    }

    static _StopGroup(groupId) {
        if !Sender._activeGroups.Has(groupId) {
            OutputDebug("Sender: 组未激活 groupId=" groupId)
            return true
        }

        ; 停止定时器
        if Sender._timers.Has(groupId) {
            SetTimer(Sender._timers[groupId], 0)
            Sender._timers.Delete(groupId)
        }

        ; 释放 hold 按键
        if Sender._heldKeys.Has(groupId) {
            for k in Sender._heldKeys[groupId]
                Sender._SendKeyUp(k)
            Sender._heldKeys.Delete(groupId)
        }

        ; 停止摇杆轮询
        Joystick.StopGroup(groupId)

        Sender._activeGroups.Delete(groupId)
        OutputDebug("Sender: 已停止 groupId=" groupId)
        return true
    }

    ; =================================================================
    ; 执行模式
    ; =================================================================

    ; 启动周期性按键执行
    static StartPeriodic(groupId, keys, intervals, keyPressDuration := 15) {
        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "periodic"
        state["keys"] := keys
        state["intervals"] := intervals
        state["keyPressDuration"] := keyPressDuration

        ; 启动执行定时器
        timerFn := () => Sender._ExecutePeriodic(groupId)
        Sender._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Sender: 启动周期性 groupId=" groupId " keys=" keys.Length)
    }

    ; 启动序列按键执行
    static StartSequence(groupId, keys, delays, keyPressDuration := 15, seqInterval := 0) {
        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "sequence"
        state["keys"] := keys
        state["delays"] := delays
        state["keyPressDuration"] := keyPressDuration
        state["seqInterval"] := seqInterval
        state["currentStep"] := 1
        state["nextStepTime"] := A_TickCount

        timerFn := () => Sender._ExecuteSequence(groupId)
        Sender._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Sender: 启动序列 groupId=" groupId " keys=" keys.Length)
    }

    ; 启动增强周期性
    static StartEnhancedPeriodic(groupId, keys, intervals, keyPressDuration := 15) {
        Sender.StartPeriodic(groupId, keys, intervals, keyPressDuration)
        if Sender._activeGroups.Has(groupId)
            Sender._activeGroups[groupId]["mode"] := "enhanced_periodic"
    }

    ; 启动增强序列
    static StartEnhancedSequence(groupId, keys, delays, keyPressDuration := 15, seqInterval := 0) {
        Sender.StartSequence(groupId, keys, delays, keyPressDuration, seqInterval)
        if Sender._activeGroups.Has(groupId)
            Sender._activeGroups[groupId]["mode"] := "enhanced_sequence"
    }

    ; 启动 Hold 模式
    ; holdDuration=0 表示无限保持（直到主动停止）
    ; holdDuration>0 表示固定时长保持，超时后自动释放并停用分组
    static StartHold(groupId, holdKeys, holdMode := "continuous", holdDuration := 0) {
        if !Sender._holdModeEnabled {
            OutputDebug("Sender: Hold 模式已禁用，跳过 groupId=" groupId)
            return
        }

        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "hold"
        state["holdKeys"] := holdKeys
        state["holdMode"] := holdMode
        state["holdDuration"] := holdDuration

        ; 按住按键
        Sender._heldKeys[groupId] := holdKeys
        for k in holdKeys
            Sender._SendKeyDown(k)

        ; 如果 holdDuration > 0，设置一次性定时器在超时后自动释放
        ; holdDuration=0 表示无限保持，不设置定时器
        ; SetTimer 第二个参数为负数 = 一次性定时器（N 毫秒后触发一次）
        if holdDuration > 0 {
            timerFn := () => Sender._HoldTimeout(groupId)
            Sender._timers[groupId] := timerFn
            SetTimer(timerFn, -holdDuration)
            OutputDebug("Sender: 启动 Hold groupId=" groupId " keys=" holdKeys.Length " mode=" holdMode " duration=" holdDuration "ms")
        } else {
            OutputDebug("Sender: 启动 Hold groupId=" groupId " keys=" holdKeys.Length " mode=" holdMode " duration=infinite")
        }
    }

    ; holdDuration 超时回调：自动释放按键并停用分组
    static _HoldTimeout(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        ; 释放 hold 按键
        if Sender._heldKeys.Has(groupId) {
            for k in Sender._heldKeys[groupId]
                Sender._SendKeyUp(k)
            Sender._heldKeys.Delete(groupId)
        }

        ; 清理定时器引用
        if Sender._timers.Has(groupId)
            Sender._timers.Delete(groupId)

        ; 停用分组
        Sender._activeGroups.Delete(groupId)

        OutputDebug("Sender: Hold 超时自动释放 groupId=" groupId)
    }

    ; 启动混合模式
    static StartHybrid(groupId, groups, keyPressDuration := 15) {
        if !Sender._activeGroups.Has(groupId)
            Sender._StartGroup(groupId)

        state := Sender._activeGroups[groupId]
        state["mode"] := "hybrid"
        state["groups"] := groups
        state["keyPressDuration"] := keyPressDuration
        state["groupTriggerTimes"] := Map()

        timerFn := () => Sender._ExecuteHybrid(groupId)
        Sender._timers[groupId] := timerFn
        SetTimer(timerFn, 10)

        OutputDebug("Sender: 启动混合 groupId=" groupId)
    }

    ; 启动增强混合模式
    static StartEnhancedHybrid(groupId, groups, keyPressDuration := 15) {
        Sender.StartHybrid(groupId, groups, keyPressDuration)
        if Sender._activeGroups.Has(groupId)
            Sender._activeGroups[groupId]["mode"] := "enhanced_hybrid"
    }

    ; =================================================================
    ; 执行引擎
    ; =================================================================

    static _ExecutePeriodic(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        state := Sender._activeGroups[groupId]
        keys := state["keys"]
        intervals := state["intervals"]
        kpd := state["keyPressDuration"]
        now := A_TickCount
        triggerTimes := state["lastTriggerTimes"]
        minRemaining := 0x7FFFFFFF

        for i, k in keys {
            if !triggerTimes.Has(i) {
                triggerTimes[i] := now
                minRemaining := 1
                continue
            }

            interval := i <= intervals.Length ? intervals[i] : 50
            if interval < 10
                interval := 10

            elapsed := now - triggerTimes[i]
            threshold := interval - Max(1, Round(interval * 0.05))

            if elapsed >= threshold {
                capturedKey := k
                Sender._SendKeyDown(capturedKey)
                SetTimer(((ck) => () => Sender._SendKeyUp(ck))(capturedKey), -kpd)
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
        if Sender._timers.Has(groupId)
            SetTimer(Sender._timers[groupId], -nextPoll)
    }

    static _ExecuteSequence(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        state := Sender._activeGroups[groupId]
        keys := state["keys"]
        delays := state["delays"]
        kpd := state["keyPressDuration"]
        now := A_TickCount

        step := state["currentStep"]
        if step > keys.Length
            step := 1

        delay := step <= delays.Length ? delays[step] : 100
        if delay < 10
            delay := 10

        if state["nextStepTime"] = 0
            state["nextStepTime"] := now + delay

        if now < state["nextStepTime"] - 2 {
            remaining := Max(1, state["nextStepTime"] - now - 2)
            if Sender._timers.Has(groupId)
                SetTimer(Sender._timers[groupId], -remaining)
            return
        }

        k := keys[step]
        Sender._SendKeyDown(k)
        SetTimer(((ck) => () => Sender._SendKeyUp(ck))(k), -kpd)

        state["currentStep"] := Mod(step, keys.Length) + 1
        nextDelay := state["currentStep"] <= delays.Length ? delays[state["currentStep"]] : 100
        if nextDelay < 10
            nextDelay := 10
        state["nextStepTime"] := A_TickCount + nextDelay

        if Sender._timers.Has(groupId)
            SetTimer(Sender._timers[groupId], -Max(1, nextDelay))
    }

    static _ExecuteHybrid(groupId) {
        if !Sender._activeGroups.Has(groupId)
            return

        state := Sender._activeGroups[groupId]
        groups := state["groups"]
        kpd := state["keyPressDuration"]
        now := A_TickCount
        triggerTimes := state["groupTriggerTimes"]
        minRemaining := 0x7FFFFFFF

        for grpIdx, grp in groups {
            grpType := grp.Has("type") ? grp["type"] : "periodic"
            grpKeys := grp.Has("pressKeys") ? grp["pressKeys"] : (grp.Has("keys") ? grp["keys"] : [])

            if grpKeys.Length = 0
                continue

            switch grpType {
                case "periodic":
                    grpIntervals := grp.Has("intervals") ? grp["intervals"] : [50]
                    for i, k in grpKeys {
                        triggerKey := grpIdx "." i
                        lastTime := triggerTimes.Has(triggerKey) ? triggerTimes[triggerKey] : now
                        interval := i <= grpIntervals.Length ? grpIntervals[i] : 50
                        if interval < 10
                            interval := 10
                        elapsed := now - lastTime
                        threshold := interval - Max(1, Round(interval * 0.05))
                        if elapsed >= threshold {
                            Sender._SendKeyDown(k)
                            SetTimer(((ck) => () => Sender._SendKeyUp(ck))(k), -kpd)
                            triggerTimes[triggerKey] := now
                            minRemaining := 1
                        } else {
                            remaining := threshold - elapsed
                            if remaining < minRemaining
                                minRemaining := remaining
                        }
                    }
                case "sequence":
                    grpDelays := grp.Has("delays") ? grp["delays"] : [100]
                    stepKey := grpIdx ".step"
                    step := triggerTimes.Has(stepKey) ? triggerTimes[stepKey] : 1
                    if step > grpKeys.Length
                        step := 1
                    delay := step <= grpDelays.Length ? grpDelays[step] : 100
                    nextTimeKey := grpIdx ".nextTime"
                    nextTime := triggerTimes.Has(nextTimeKey) ? triggerTimes[nextTimeKey] : now
                    if now >= nextTime {
                        k := grpKeys[step]
                        Sender._SendKeyDown(k)
                        SetTimer(((ck) => () => Sender._SendKeyUp(ck))(k), -kpd)
                        triggerTimes[stepKey] := Mod(step, grpKeys.Length) + 1
                        nextDelay := triggerTimes[stepKey] <= grpDelays.Length ? grpDelays[triggerTimes[stepKey]] : 100
                        triggerTimes[nextTimeKey] := A_TickCount + nextDelay
                        minRemaining := 1
                    } else {
                        remaining := Max(1, nextTime - now)
                        if remaining < minRemaining
                            minRemaining := remaining
                    }
            }
        }

        nextPoll := Max(1, minRemaining)
        if Sender._timers.Has(groupId)
            SetTimer(Sender._timers[groupId], -nextPoll)
    }

    ; =================================================================
    ; 底层按键操作
    ; =================================================================

    static _ValidateKey(key) {
        if Sender.ALLOWED_KEYS.Has(key)
            return true
        OutputDebug("Sender: 按键被拒绝（不在白名单中） key=" key)
        return false
    }

    static _SendKeyDown(key) {
        if !Sender._ValidateKey(key)
            return
        try {
            SendInput("{Blind}{" key " Down}")
            IpcClient._SendMsg(Map(
                "type", "key_send_event",
                "seq", IpcClient._NextSeq(),
                "data", Map("key", key, "state", "down", "device", "keyboard")
            ))
        } catch as e {
            OutputDebug("Sender: 按键按下失败 key=" key " err=" e.Message)
        }
    }

    static _SendKeyUp(key) {
        if !Sender._ValidateKey(key)
            return
        try {
            SendInput("{Blind}{" key " Up}")
            IpcClient._SendMsg(Map(
                "type", "key_send_event",
                "seq", IpcClient._NextSeq(),
                "data", Map("key", key, "state", "up", "device", "keyboard")
            ))
        } catch as e {
            OutputDebug("Sender: 按键释放失败 key=" key " err=" e.Message)
        }
    }
}
