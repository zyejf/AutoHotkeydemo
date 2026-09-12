; =================================================================
; 领域层 - JoystickExecutor 手柄模式执行器
; 版本: 1.1
; 说明: 实现 IExecutor 接口，提供3种手柄执行模式
;       joystick_periodic / joystick_sequence / joystick_hold
;       v1.1: 通过 IJoySender 抽象注入手柄发送能力，解除对 infrastructure/joy_sender 的直接依赖
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "joystick_input.ahk"
#Include "../infrastructure/error_system.ahk"

class JoystickPeriodicExecutor extends IExecutor {
    GetModeName() {
        return "joystick_periodic"
    }

    Execute(group) {
        ; T3-06: 激活前注入检查——未注入一次性告警并阻止进入执行循环
        if !JoystickExecutor._EnsureSenderReady() {
            JoystickExecutor._WarnSenderMissingOnce()
            return 100
        }
        try {
            now := A_TickCount
            joyKeys := group.joyKeys
            joyIntervals := group.joyIntervals
            sendMethod := group.joySendMethod
            keyDuration := group.joyKeyDuration

        if joyKeys.Length = 0
            return 100

        minRemaining := 0x7FFFFFFF

            if !group.HasProp("_joyLastTriggerTimes")
                group._joyLastTriggerTimes := Map()

            for i, k in joyKeys {
                if !group._joyLastTriggerTimes.Has(i) {
                    group._joyLastTriggerTimes[i] := now
                    minRemaining := 1
                    continue
                }
                interval := i <= joyIntervals.Length ? joyIntervals[i] : 50
                if interval < 10
                    interval := 10
                elapsed := now - group._joyLastTriggerTimes[i]
                threshold := interval - Max(1, Round(interval * 0.05))
                if elapsed >= threshold {
                    capturedKey := k
                    capturedMethod := sendMethod
                    JoystickExecutor._SendJoyKey(capturedKey, "down", capturedMethod)
                    JoystickExecutor._ScheduleRelease(group, capturedKey, capturedMethod, keyDuration)
                    group._joyLastTriggerTimes[i] := group._joyLastTriggerTimes[i] + interval
                    if group._joyLastTriggerTimes[i] < A_TickCount - interval
                        group._joyLastTriggerTimes[i] := A_TickCount
                    minRemaining := 1
                } else {
                    remaining := threshold - elapsed
                    if remaining < minRemaining
                        minRemaining := remaining
                }
            }
            return Max(1, minRemaining)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 10
        }
    }
}

class JoystickSequenceExecutor extends IExecutor {
    GetModeName() {
        return "joystick_sequence"
    }

    Execute(group) {
        ; T3-06: 激活前注入检查——未注入一次性告警并阻止进入执行循环
        if !JoystickExecutor._EnsureSenderReady() {
            JoystickExecutor._WarnSenderMissingOnce()
            return 100
        }
        try {
            now := A_TickCount
            joyKeys := group.joyKeys
            joyDelays := group.joyDelays
            sendMethod := group.joySendMethod
            keyDuration := group.joyKeyDuration

            if !group.HasProp("_joyCurrentStep")
                group._joyCurrentStep := 1
            step := group._joyCurrentStep
            if step > joyKeys.Length
                step := 1

            delay := step <= joyDelays.Length ? joyDelays[step] : 100
            if delay < 10
                delay := 10

            if !group.HasProp("_joyNextStepTime") || group._joyNextStepTime = 0 {
                group._joyNextStepTime := now + delay
            } else if now < group._joyNextStepTime - 2 {
                return Max(1, group._joyNextStepTime - now - 2)
            }

            k := joyKeys[step]
            capturedKey := k
            capturedMethod := sendMethod
            JoystickExecutor._SendJoyKey(capturedKey, "down", capturedMethod)
            JoystickExecutor._ScheduleRelease(group, capturedKey, capturedMethod, keyDuration)
            group._joyCurrentStep := Mod(step, joyKeys.Length) + 1

            nextDelay := (group._joyCurrentStep <= joyDelays.Length) ? joyDelays[group._joyCurrentStep] : 100
            if nextDelay < 10
                nextDelay := 10
            group._joyNextStepTime := A_TickCount + nextDelay
            return Max(1, nextDelay)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 100
        }
    }
}

class JoystickHoldExecutor extends IExecutor {
    GetModeName() {
        return "joystick_hold"
    }

    Execute(group) {
        ; T3-06: 激活前注入检查——未注入一次性告警并阻止进入执行循环
        if !JoystickExecutor._EnsureSenderReady() {
            JoystickExecutor._WarnSenderMissingOnce()
            return 50
        }
        try {
            joyKeys := group.joyKeys
            sendMethod := group.joySendMethod

            if !group.HasProp("_joyHoldActive")
                group._joyHoldActive := false

            if !group._joyHoldActive {
                for k in joyKeys
                    JoystickExecutor._SendJoyKey(k, "down", sendMethod)
                group._joyHoldActive := true
            }
            return 50
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 50
        }
    }
}

class JoystickExecutor {
    ; 注入的手柄发送器实例（IJoySender 实现），由 main.ahk InitDependencies 注入
    static _joySender := ""

    ; T6-02: 释放定时器引用: groupId => (key => timerRef)，组停止时统一取消
    static _releaseTimers := Map()

    ; T3-06: 注入缺失告警去重标记，避免每 tick 重复 ERROR 日志风暴
    static _injectionWarned := false

    ; 依赖注入入口 - 设置手柄发送器实现
    static SetJoySender(sender) {
        this._joySender := sender
        ; 重新注入后重置一次性告警标记，允许下次缺失时再次提示
        JoystickExecutor._injectionWarned := false
    }

    ; T3-06: 激活前注入检查——已注入返回 true
    static _EnsureSenderReady() {
        return JoystickExecutor._joySender != ""
    }

    ; T3-06: 未注入时一次性告警（同一进程内仅记录一次）
    static _WarnSenderMissingOnce() {
        if !JoystickExecutor._injectionWarned {
            ErrorSystem.LogError("JoySender 未注入，joystick 模式无法执行；请先调用 SetJoySender", "WARNING", A_ThisFunc, A_LineNumber)
            JoystickExecutor._injectionWarned := true
        }
    }

    static _SendJoyKey(key, state, sendMethod := "auto") {
        ; T3-06: 防御性检查（激活前已前置检查），未注入时静默跳过，避免每 tick 抛异常
        if (this._joySender = "")
            return
        try {
            sender := this._joySender
            if JoystickInput.IsButton(key) {
                btnNum := JoystickInput.GetButtonNum(key)
                sender.SendBtn(btnNum, state = "down", sendMethod)
            } else if JoystickInput.IsPov(key) {
                direction := JoystickInput.GetPovDirection(key)
                if state = "down"
                    sender.SendPov(direction, sendMethod)
                else
                    sender.SendPov("CENTER", sendMethod)
            } else if JoystickInput.IsTrigger(key) {
                info := JoystickInput.GetAxisInfo(key)
                value := state = "down" ? 100 : 0
                sender.SendAxis(info["axis"], value, sendMethod)
            } else if JoystickInput.IsAxis(key) {
                info := JoystickInput.GetAxisInfo(key)
                value := 50
                if state = "down" {
                    if info["target"] = "RIGHT" || info["target"] = "DOWN"
                        value := 100
                    else
                        value := 0
                }
                sender.SendAxis(info["axis"], value, sendMethod)
            }
        } catch as e {
            ErrorSystem.LogError("_SendJoyKey 失败: " key " " state " " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; T6-02: 登记逐键 up 一次性定时器，组停止时取消，消除「停止后滞后发一次 up」
    static _ScheduleRelease(group, key, method, kpd) {
        if !JoystickExecutor._releaseTimers.Has(group.id)
            JoystickExecutor._releaseTimers[group.id] := Map()
        groupTimers := JoystickExecutor._releaseTimers[group.id]
        if groupTimers.Has(key)
            SetTimer(groupTimers[key], 0)
        timerFn := ((g, kk, mm) => () => JoystickExecutor._OnReleaseKey(g, kk, mm))(group, key, method)
        groupTimers[key] := timerFn
        SetTimer(timerFn, -kpd)
    }

    static _OnReleaseKey(group, key, method) {
        JoystickExecutor._SendJoyKey(key, "up", method)
        if JoystickExecutor._releaseTimers.Has(group.id) {
            groupTimers := JoystickExecutor._releaseTimers[group.id]
            if groupTimers.Has(key)
                groupTimers.Delete(key)
        }
    }

    static _CancelReleaseTimers(group) {
        if !JoystickExecutor._releaseTimers.Has(group.id)
            return
        for key, timerRef in JoystickExecutor._releaseTimers[group.id]
            SetTimer(timerRef, 0)
        JoystickExecutor._releaseTimers.Delete(group.id)
    }

    static _ReleaseJoyKeys(group) {
        ; T3-06: 防御性检查——未注入时静默跳过，不再在组停止路径抛异常
        if (this._joySender = "") {
            JoystickExecutor._CancelReleaseTimers(group)
            return
        }
        ; T6-02: 取消该组的滞后 up 定时器，避免随后重复发 up
        JoystickExecutor._CancelReleaseTimers(group)
        try {
            sender := this._joySender
            sendMethod := group.joySendMethod
            for k in group.joyKeys {
                if JoystickInput.IsButton(k) {
                    sender.SendBtn(JoystickInput.GetButtonNum(k), false, sendMethod)
                } else if JoystickInput.IsPov(k) {
                    sender.SendPov("CENTER", sendMethod)
                } else if JoystickInput.IsTrigger(k) {
                    info := JoystickInput.GetAxisInfo(k)
                    sender.SendAxis(info["axis"], 0, sendMethod)
                } else if JoystickInput.IsAxis(k) {
                    info := JoystickInput.GetAxisInfo(k)
                    sender.SendAxis(info["axis"], 50, sendMethod)
                }
            }
        } catch as e {
            ErrorSystem.LogError("_ReleaseJoyKeys 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}