; =================================================================
; 领域层 - 执行模式注册表（插件式扩展机制）
; 版本: 3.0
; 说明: 支持动态注册/注销执行模式，新增模式无需修改核心代码
;       通过注册表模式实现开放封闭原则（OCP）
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "../infrastructure/error_system.ahk"

class ModeRegistry {
    static _executors := Map()
    static _modeMeta := Map()

    ; 注册一个执行模式
    ; executor: 实现 IExecutor 接口的实例
    ; meta: 模式元数据 {name: "显示名", description: "描述", requires: ["字段列表"]}
    static Register(modeName, executor, meta := "") {
        try {
            if !(executor is IExecutor) {
                ErrorSystem.LogError("ModeRegistry.Register: executor 必须实现 IExecutor 接口", "ERROR", A_ThisFunc, A_LineNumber)
                return false
            }

            this._executors[modeName] := executor
            this._modeMeta[modeName] := meta

            return true
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; 注销一个执行模式
    static Unregister(modeName) {
        try {
            if !this._executors.Has(modeName)
                return
            this._executors.Delete(modeName)
            if this._modeMeta.Has(modeName)
                this._modeMeta.Delete(modeName)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; 获取指定模式的执行器
    static GetExecutor(modeName) {
        try {
            if !this._executors.Has(modeName)
                throw ValueError("未注册的执行模式: " modeName)
            return this._executors[modeName]
        } catch as e {
            if e is ValueError
                throw e
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; 检查模式是否存在
    static HasMode(modeName) {
        try {
            return this._executors.Has(modeName)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; 获取所有已注册的模式名称
    static GetRegisteredModes() {
        try {
            modes := []
            for modeName in this._executors
                modes.Push(modeName)
            return modes
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return []
        }
    }

    ; 获取模式元数据
    static GetModeMeta(modeName) {
        try {
            if this._modeMeta.Has(modeName)
                return this._modeMeta[modeName]
            return ""
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return ""
        }
    }

    ; 获取所有模式的显示名称（用于 GUI 下拉框等）
    static GetModeDisplayNames() {
        try {
            result := Map()
            for modeName in this._executors {
                meta := this._modeMeta.Has(modeName) ? this._modeMeta[modeName] : ""
                displayName := (meta && (meta is Map) && meta.Has("name")) ? meta["name"] : modeName
                result[modeName] := displayName
            }
            return result
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return Map()
        }
    }

    ; 验证模式配置是否满足必需字段
    static ValidateModeConfig(modeName, config) {
        try {
            if !this._modeMeta.Has(modeName)
                return []

            meta := this._modeMeta[modeName]
            if !meta || !(meta is Map) || !meta.Has("requires")
                return []

            errors := []
            requires := meta["requires"]
            for field in requires {
                if config is Map {
                    if !config.Has(field)
                        errors.Push("模式 '" modeName "' 缺少必需字段: " field)
                } else if IsObject(config) {
                    if !HasProp(config, field)
                        errors.Push("模式 '" modeName "' 缺少必需字段: " field)
                } else {
                    errors.Push("模式 '" modeName "' 缺少必需字段: " field)
                }
            }
            if meta.Has("requiresNonEmpty") {
                requiresNonEmpty := meta["requiresNonEmpty"]
                for field in requiresNonEmpty {
                    val := ""
                    hasField := false
                    if config is Map {
                        hasField := config.Has(field)
                        if hasField
                            val := config[field]
                    } else if IsObject(config) {
                        hasField := HasProp(config, field)
                        if hasField
                            val := config.%field%
                    }
                    if hasField && val is Array && val.Length = 0
                        errors.Push("模式 '" modeName "' 字段 " field " 不能为空数组")
                }
            }

            return errors
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return []
        }
    }

    ; 初始化内置模式注册（在 main.ahk 的 try-catch 块中调用）
    static _Init() {
        try {
            ModeRegistry.Register("periodic", PeriodicExecutor(), Map(
                "name", "周期性",
                "description", "定时重复按下指定的按键",
                "requires", ["keys", "intervals"],
                "requiresNonEmpty", ["keys"]
            ))

            ModeRegistry.Register("sequence", SequenceExecutor(), Map(
                "name", "序列",
                "description", "按顺序依次按下指定的按键",
                "requires", ["keys", "delays"],
                "requiresNonEmpty", ["keys"]
            ))

            ModeRegistry.Register("hybrid", HybridExecutor(), Map(
                "name", "混合",
                "description", "同时执行周期性按键和序列按键",
                "requires", ["groups"],
                "requiresNonEmpty", ["groups"]
            ))

            ModeRegistry.Register("enhanced_periodic", EnhancedPeriodicExecutor(), Map(
                "name", "增强周期",
                "description", "周期性按键 + 可选长按功能",
                "requires", ["pressKeys", "intervals"],
                "requiresNonEmpty", ["pressKeys"]
            ))

            ModeRegistry.Register("enhanced_sequence", EnhancedSequenceExecutor(), Map(
                "name", "增强序列",
                "description", "序列按键 + 可选长按功能",
                "requires", ["pressKeys", "pressDelays"],
                "requiresNonEmpty", ["pressKeys"]
            ))

            ModeRegistry.Register("enhanced_hybrid", EnhancedHybridExecutor(), Map(
                "name", "增强混合",
                "description", "混合模式 + 可选长按功能",
                "requires", ["groups"],
                "requiresNonEmpty", ["groups"]
            ))

            ModeRegistry.Register("hold", HoldExecutor(), Map(
                "name", "纯长按",
                "description", "按住指定按键不放",
                "requires", ["holdKeys"],
                "requiresNonEmpty", ["holdKeys"]
            ))

            return true
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }
}

; =================================================================
; 内置执行器实现
; =================================================================

; 周期性执行器
class PeriodicExecutor extends IExecutor {
    GetModeName() {
        return "periodic"
    }

    Execute(group) {
        try {
            now := A_TickCount
            keys := group.keys
            intervals := group.intervals
            isMouseArr := group._isMouse
            minRemaining := 0x7FFFFFFF

            for i, k in keys {
                if !group._lastTriggerTimes.Has(i) {
                    group._lastTriggerTimes[i] := now
                    minRemaining := 1
                    continue
                }
                interval := (i <= intervals.Length) ? intervals[i] : 50
                if interval < 10
                    interval := 10
                elapsed := now - group._lastTriggerTimes[i]
                threshold := interval - Max(1, Round(interval * 0.05))
                if elapsed >= threshold {
                    isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
                    group._SendKey(k, isMouse)
                    group._lastTriggerTimes[i] := group._lastTriggerTimes[i] + interval
                    if group._lastTriggerTimes[i] < A_TickCount - interval
                        group._lastTriggerTimes[i] := A_TickCount
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

; 序列执行器
class SequenceExecutor extends IExecutor {
    GetModeName() {
        return "sequence"
    }

    Execute(group) {
        try {
            now := A_TickCount
            step := group._currentStep
            if step > group.keys.Length
                step := 1

            delay := step <= group.delays.Length ? group.delays[step] : 100
            if delay < 10
                delay := 10

            if !group.HasProp("_nextStepTime") || group._nextStepTime = 0 {
                group._nextStepTime := now + delay
            } else if now < group._nextStepTime - 2 {
                return Max(1, group._nextStepTime - now - 2)
            }

            k := group.keys[step]
            isMouseArr := group._isMouse
            isMouse := step <= isMouseArr.Length ? isMouseArr[step] : false

            group._SendKey(k, isMouse)
            group._currentStep := Mod(step, group.keys.Length) + 1

            nextStep := group._currentStep
            nextDelay := nextStep <= group.delays.Length ? group.delays[nextStep] : 100
            if nextDelay < 10
                nextDelay := 10
            if !group.HasProp("_nextStepTimeBase") || group._nextStepTimeBase = 0 {
                group._nextStepTime := A_TickCount + nextDelay
                group._nextStepTimeBase := A_TickCount
            } else {
                group._nextStepTime := group._nextStepTime + nextDelay
                if group._nextStepTime < A_TickCount - nextDelay
                    group._nextStepTime := A_TickCount + nextDelay
            }

            return Max(1, nextDelay - (A_TickCount - now))
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 100
        }
    }
}

; 增强周期性执行器
class EnhancedPeriodicExecutor extends IExecutor {
    GetModeName() {
        return "enhanced_periodic"
    }

    Execute(group) {
        try {
            now := A_TickCount
            pressKeys := group.pressKeys
            intervals := group.intervals
            isMouseArr := group._pressMouse
            minRemaining := 0x7FFFFFFF

            for i, k in pressKeys {
                if !group._lastTriggerTimes.Has(i) {
                    group._lastTriggerTimes[i] := now
                    minRemaining := 1
                    continue
                }
                interval := (i <= intervals.Length) ? intervals[i] : 50
                if interval < 10
                    interval := 10
                elapsed := now - group._lastTriggerTimes[i]
                threshold := interval - Max(1, Round(interval * 0.05))
                if elapsed >= threshold {
                    isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
                    group._SendKey(k, isMouse)
                    group._lastTriggerTimes[i] := group._lastTriggerTimes[i] + interval
                    if group._lastTriggerTimes[i] < A_TickCount - interval
                        group._lastTriggerTimes[i] := A_TickCount
                    minRemaining := 1
                } else {
                    remaining := threshold - elapsed
                    if remaining < minRemaining
                        minRemaining := remaining
                }
            }

            group._ProcessHoldKeys()

            return Max(1, minRemaining)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 10
        }
    }
}

class EnhancedSequenceExecutor extends IExecutor {
    GetModeName() {
        return "enhanced_sequence"
    }

    Execute(group) {
        try {
            now := A_TickCount
            step := group._currentStep
            if step > group.pressKeys.Length
                step := 1

            delay := step <= group.pressDelays.Length ? group.pressDelays[step] : 100
            if delay < 10
                delay := 10

            if !group.HasProp("_nextStepTime") || group._nextStepTime = 0 {
                group._nextStepTime := now + delay
            } else if now < group._nextStepTime - 2 {
                return Max(1, group._nextStepTime - now - 2)
            }

            group._ProcessSequenceHoldTriggers(step)

            k := group.pressKeys[step]
            isMouseArr := group._pressMouse
            isMouse := step <= isMouseArr.Length ? isMouseArr[step] : false

            group._SendKey(k, isMouse)
            group._currentStep := Mod(step, group.pressKeys.Length) + 1

            nextStep := group._currentStep
            nextDelay := nextStep <= group.pressDelays.Length ? group.pressDelays[nextStep] : 100
            if nextDelay < 10
                nextDelay := 10
            if !group.HasProp("_nextStepTimeBase") || group._nextStepTimeBase = 0 {
                group._nextStepTime := A_TickCount + nextDelay
                group._nextStepTimeBase := A_TickCount
            } else {
                group._nextStepTime := group._nextStepTime + nextDelay
                if group._nextStepTime < A_TickCount - nextDelay
                    group._nextStepTime := A_TickCount + nextDelay
            }

            return Max(1, nextDelay - (A_TickCount - now))
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 100
        }
    }
}

; 混合执行器
class HybridExecutor extends IExecutor {
    GetModeName() {
        return "hybrid"
    }

    Execute(group) {
        try {
            delay := group._ExecuteMixedGroups()
            return delay
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 10
        }
    }
}

class EnhancedHybridExecutor extends IExecutor {
    GetModeName() {
        return "enhanced_hybrid"
    }

    Execute(group) {
        try {
            delay := group._ExecuteMixedGroups()
            group._ProcessHoldKeys()

            return Max(1, delay)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 10
        }
    }
}

; 长按执行器
class HoldExecutor extends IExecutor {
    GetModeName() {
        return "hold"
    }

    Execute(group) {
        try {
            if group.holdKeys.Length = 0
                return 0

            if group.holdDuration > 0 {
                if (A_TickCount - group._holdStartTime > group.holdDuration) {
                    if group.autoRepeat {
                        if group._holdRepeatPhase = "" || group._holdRepeatPhase = "press" {
                            group._ReleaseHoldKeys()
                            group._holdRepeatPhase := "release"
                            return 50
                        } else {
                            group._PressHoldKeys()
                            group._holdRepeatPhase := "press"
                            group._holdStartTime := A_TickCount
                            return group.repeatInterval > 0 ? group.repeatInterval : 1000
                        }
                    } else {
                        group.active := false
                        group._ReleaseHoldKeys()
                        group._lastSend := Map()
                        return 0
                    }
                }
                return 50
            }

            if group.autoRepeat && group.repeatInterval > 0 {
                if group._holdRepeatPhase = "" {
                    group._holdRepeatPhase := "press"
                    group._holdStartTime := A_TickCount
                }
                elapsed := A_TickCount - group._holdStartTime
                if group._holdRepeatPhase = "press" && elapsed >= group.repeatInterval {
                    group._ReleaseHoldKeys()
                    group._holdRepeatPhase := "release"
                    group._holdStartTime := A_TickCount
                    return 50
                } else if group._holdRepeatPhase = "release" && elapsed >= 50 {
                    group._PressHoldKeys()
                    group._holdRepeatPhase := "press"
                    group._holdStartTime := A_TickCount
                    return group.repeatInterval
                }
                return 50
            }

            return 5000
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 0
        }
    }
}

; =================================================================
; 内置模式注册 - 已移到 ModeRegistry._Init() 方法中
; 在 main.ahk 的 try-catch 块中调用 ModeRegistry._Init()
; =================================================================
