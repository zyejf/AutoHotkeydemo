; =================================================================
; 领域层 - JoystickExecutor 手柄模式执行器
; 版本: 1.0
; 说明: 实现 IExecutor 接口，提供3种手柄执行模式
;       joystick_periodic / joystick_sequence / joystick_hold
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "joystick_input.ahk"
#Include "../infrastructure/joy_sender.ahk"
#Include "../infrastructure/error_system.ahk"

class JoystickPeriodicExecutor extends IExecutor {
    GetModeName() {
        return "joystick_periodic"
    }

    Execute(group) {
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
                    JoystickExecutor._SendJoyKey(k, "down", sendMethod)
                    SetTimer(() => JoystickExecutor._SendJoyKey(k, "up", sendMethod), -keyDuration)
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
            JoystickExecutor._SendJoyKey(k, "down", sendMethod)
            SetTimer(() => JoystickExecutor._SendJoyKey(k, "up", sendMethod), -keyDuration)
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
    static _SendJoyKey(key, state, sendMethod := "auto") {
        try {
            if JoystickInput.IsButton(key) {
                btnNum := JoystickInput.GetButtonNum(key)
                JoySender.SendBtn(btnNum, state = "down", sendMethod)
            } else if JoystickInput.IsPov(key) {
                direction := JoystickInput.GetPovDirection(key)
                if state = "down"
                    JoySender.SendPov(direction, sendMethod)
                else
                    JoySender.SendPov("CENTER", sendMethod)
            } else if JoystickInput.IsTrigger(key) {
                info := JoystickInput.GetAxisInfo(key)
                value := state = "down" ? 100 : 0
                JoySender.SendAxis(info["axis"], value, sendMethod)
            } else if JoystickInput.IsAxis(key) {
                info := JoystickInput.GetAxisInfo(key)
                value := 50
                if state = "down" {
                    if info["target"] = "RIGHT" || info["target"] = "DOWN"
                        value := 100
                    else
                        value := 0
                }
                JoySender.SendAxis(info["axis"], value, sendMethod)
            }
        } catch as e {
            ErrorSystem.LogError("_SendJoyKey 失败: " key " " state " " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _ReleaseJoyKeys(group) {
        try {
            sendMethod := group.joySendMethod
            for k in group.joyKeys {
                if JoystickInput.IsButton(k) {
                    JoySender.SendBtn(JoystickInput.GetButtonNum(k), false, sendMethod)
                } else if JoystickInput.IsPov(k) {
                    JoySender.SendPov("CENTER", sendMethod)
                } else if JoystickInput.IsAxis(k) || JoystickInput.IsTrigger(k) {
                    info := JoystickInput.GetAxisInfo(k)
                    JoySender.SendAxis(info["axis"], 50, sendMethod)
                }
            }
        } catch as e {
            ErrorSystem.LogError("_ReleaseJoyKeys 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }
}