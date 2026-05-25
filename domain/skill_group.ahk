; =================================================================
; 领域层 - SkillGroup 按键执行单元
; 版本: 3.0
; 说明: 技能组核心类，管理单个技能组的完整生命周期
;       通过依赖注入使用抽象接口，不依赖任何具体实现
;       支持 7 种执行模式，通过 ModeRegistry 扩展
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "mode_registry.ahk"
#Include "key_validator.ahk"
#Include "../infrastructure/error_system.ahk"

class SkillGroup {
    ; =================================================================
    ; 依赖注入点（由应用启动时配置）
    ; =================================================================
    static Logger := ""             ; ILogger 实例
    static Notifier := ""           ; INotifier 实例
    static ConfigStore := ""        ; IConfigStore 实例
    static IsKeyAllowed := ""       ; Func 回调: (key, groupId) => bool
    static RegisterHoldKey := ""    ; Func 回调: (key, groupId) => bool
    static UnregisterHoldKey := ""  ; Func 回调: (key, groupId) => void

    ; =================================================================
    ; 常量
    ; =================================================================
    static TOGGLE_DEBOUNCE_MS := 200

    ; =================================================================
    ; 按键持续时间属性（带边界检查）
    ; =================================================================
    _keyPressDuration := 15

    keyPressDuration {
        get => this._keyPressDuration
        set {
            if value < 5
                value := 5
            if value > 100
                value := 100
            this._keyPressDuration := value
        }
    }

    ; =================================================================
    ; 构造与初始化
    ; =================================================================
    __New(id, config) {
        try {
            this.id := id
            this.name := _GetProp(config, "name", id)
            this._order := _GetProp(config, "order", 0)
            this.active := false
            this.mode := _GetProp(config, "mode", "periodic")
            this.hotkey := _GetProp(config, "hotkey", "")
            this.keyPressDuration := _GetProp(config, "keyPressDuration", 15)

            this._executionCount := 0
            this._startTime := 0
            this._lastUpdateTime := 0
            this._lastToggleTime := 0
            this._lastSend := Map()
            this._heldKeyMouse := Map()
            this._debounceMs := 0
            this._debounceInitialized := false
            this._InitDebounce()

            this.holdKeys := _GetProp(config, "holdKeys", [])
            this.holdMode := _GetProp(config, "holdMode", "continuous")
            this._heldKeys := Map()
            this._lastTriggerTimes := Map()
            this._isHoldMouse := this._CheckMouseKeys(this.holdKeys)
            this._holdPhaseStart := 0
            this._groupTriggerTimes := Map()
            this._seqSteps := Map()
            this._lastSeqRuns := Map()

            if !ModeRegistry.HasMode(this.mode)
                throw ValueError("无效的执行模式: " this.mode)

            this._SetupMode(config)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 模式初始化
    ; =================================================================
    _SetupMode(config) {
        switch this.mode {
            case "periodic":
                this.keys := _GetProp(config, "keys", [])
                this.intervals := _GetProp(config, "intervals", [])
                this._isMouse := this._CheckMouseKeys(this.keys)
                this._InitPeriodicTriggerTimes(this.keys)

            case "sequence":
                this.keys := _GetProp(config, "keys", [])
                this.delays := _GetProp(config, "delays", [])
                this._currentStep := 1
                this._nextStepTime := 0
                this._nextStepTimeBase := 0
                this._isMouse := this._CheckMouseKeys(this.keys)

            case "hybrid":
                this._SetupHybrid(config)

            case "hold":
                this.holdDuration := _GetProp(config, "holdDuration", 0)
                this.autoRepeat := _GetProp(config, "autoRepeat", false)
                this.repeatInterval := _GetProp(config, "repeatInterval", 1000)
                this._holdStartTime := 0
                this._holdRepeatPhase := ""

            case "enhanced_periodic":
                this.pressKeys := _GetProp(config, "pressKeys", [])
                this.intervals := _GetProp(config, "intervals", [])
                this.pressDelays := _GetProp(config, "pressDelays", [])
                this._pressMouse := this._CheckMouseKeys(this.pressKeys)
                this._InitPeriodicTriggerTimes(this.pressKeys)
                this.holdPattern := _GetProp(config, "holdPattern", [])
                this.holdTriggers := _GetProp(config, "holdTriggers", [])

            case "enhanced_sequence":
                this.pressKeys := _GetProp(config, "pressKeys", [])
                this.pressDelays := _GetProp(config, "pressDelays", [])
                this.delays := _GetProp(config, "delays", _GetProp(config, "intervals", []))
                this._pressMouse := this._CheckMouseKeys(this.pressKeys)
                this._currentStep := 1
                this._nextStepTime := 0
                this._nextStepTimeBase := 0
                this.holdTriggers := _GetProp(config, "holdTriggers", [])
                this.holdPattern := _GetProp(config, "holdPattern", [])
                this._activeHolds := Map()

            case "enhanced_hybrid":
                this._SetupEnhancedHybrid(config)
        }
    }

    _SetupHybrid(config) {
        this.groups := _GetProp(config, "groups", [])
        this._seqSteps.Clear()
        this._lastSeqRuns.Clear()
        this._seqIntervals := Map()
        this._groupTriggerTimes.Clear()
        this._subGroupMouse := Map()

        periodicKeys := []
        periodicIntervals := []
        seqKeys := []
        seqDelays := []

        for grpIdx, grp in this.groups {
            grpType := _GetProp(grp, "type", "periodic")
            pk := _GetProp(grp, "pressKeys", [])
            if grpType = "periodic" {
                pi := _GetProp(grp, "intervals", [])
                for k in pk
                    periodicKeys.Push(k)
                for v in pi
                    periodicIntervals.Push(v)
                for i, k in pk {
                    offset := (i - 1) * 10
                    this._groupTriggerTimes[grpIdx "." i] := A_TickCount - offset
                }
                this._subGroupMouse[grpIdx] := this._CheckMouseKeys(pk)
            } else {
                sd := _GetProp(grp, "delays", [])
                for k in pk
                    seqKeys.Push(k)
                for v in sd
                    seqDelays.Push(v)
                this._subGroupMouse[grpIdx] := this._CheckMouseKeys(pk)
                this._seqSteps[grpIdx] := 1
                this._lastSeqRuns[grpIdx] := 0
                this._seqIntervals[grpIdx] := _GetProp(grp, "seqInterval", 100)
            }
        }

        this.periodicKeys := periodicKeys
        this.periodicIntervals := periodicIntervals
        this._periodicMouse := this._CheckMouseKeys(this.periodicKeys)
        this.seqKeys := seqKeys
        this.seqDelays := seqDelays
        this._seqMouse := this._CheckMouseKeys(this.seqKeys)
        this.seqInterval := _GetProp(config, "seqInterval", 100)
    }

    _SetupEnhancedHybrid(config) {
        this.groups := _GetProp(config, "groups", [])
        this.seqInterval := _GetProp(config, "seqInterval", 100)
        this.holdPattern := _GetProp(config, "holdPattern", [])
        this.holdTriggers := _GetProp(config, "holdTriggers", [])
        this.holdKeys := _GetProp(config, "holdKeys", [])
        this.holdMode := _GetProp(config, "holdMode", "continuous")
        this.holdDuration := _GetProp(config, "holdDuration", 0)
        this.autoRepeat := _GetProp(config, "autoRepeat", false)
        this.repeatInterval := _GetProp(config, "repeatInterval", 100)
        this._activeHolds := Map()

        this.periodicPressKeys := []
        this.seqPressKeys := []
        this._seqSteps.Clear()
        this._lastSeqRuns.Clear()
        this._seqIntervals := Map()
        this._groupTriggerTimes.Clear()
        this._subGroupMouse := Map()

        for grpIdx, grp in this.groups {
            if _GetProp(grp, "type", "periodic") = "periodic" {
                pk := _GetProp(grp, "pressKeys", [])
                intervals := _GetProp(grp, "intervals", [])
                for k in pk
                    this.periodicPressKeys.Push(k)
                for i, k in pk {
                    offset := (i - 1) * 10
                    this._groupTriggerTimes[grpIdx "." i] := A_TickCount - offset
                }
                this._subGroupMouse[grpIdx] := this._CheckMouseKeys(pk)
            } else {
                sk := _GetProp(grp, "pressKeys", [])
                for k in sk
                    this.seqPressKeys.Push(k)
                this._subGroupMouse[grpIdx] := this._CheckMouseKeys(sk)
                this._seqSteps[grpIdx] := 1
                this._lastSeqRuns[grpIdx] := 0
                this._seqIntervals[grpIdx] := _GetProp(grp, "seqInterval", 100)
            }
        }

        this._periodicMouse := this._CheckMouseKeys(this.periodicPressKeys)
        this._seqMouse := this._CheckMouseKeys(this.seqPressKeys)
    }

    ; =================================================================
    ; 按键类型检测
    ; =================================================================
    _CheckMouseKeys(keys) {
        result := []
        for k in keys {
            baseKey := RegExReplace(k, "^[\^+!#]+", "")
            result.Push(baseKey = "LButton" || baseKey = "RButton" || baseKey = "MButton" || baseKey = "XButton1" || baseKey = "XButton2" || baseKey = "WheelUp" || baseKey = "WheelDown")
        }
        return result
    }

    _InitDebounce() {
        if this._debounceInitialized
            return
        holdSettings := SkillManager._GetHoldSettings()
        this._debounceMs := IsObject(holdSettings) ? _GetProp(holdSettings, "debounceDelay", 20) : 20
        if this._debounceMs = 0
            this._debounceMs := 20
        this._debounceInitialized := true
    }

    _InitPeriodicTriggerTimes(keys) {
        for i, k in keys {
            offset := (i - 1) * 10
            this._lastTriggerTimes[i] := A_TickCount - offset
        }
    }

    _ResetPeriodicTriggerTimes() {
        for i in this._lastTriggerTimes
            this._lastTriggerTimes[i] := A_TickCount
        for k in this._groupTriggerTimes {
            parts := StrSplit(k, ".")
            if parts.Length = 2 {
                keyIdx := Integer(parts[2])
                offset := (keyIdx - 1) * 10
                this._groupTriggerTimes[k] := A_TickCount - offset
            } else {
                this._groupTriggerTimes[k] := A_TickCount
            }
        }
    }

    _HasEmptyKeyArrays() {
        switch this.mode {
            case "periodic":
                return this.keys.Length = 0
            case "sequence":
                return this.keys.Length = 0
            case "enhanced_periodic":
                return this.pressKeys.Length = 0
            case "enhanced_sequence":
                return this.pressKeys.Length = 0
            case "enhanced_hybrid":
                return this.periodicPressKeys.Length = 0 && this.seqPressKeys.Length = 0
            case "hybrid":
                return this.periodicKeys.Length = 0 && this.seqKeys.Length = 0
            case "hold":
                return this.holdKeys.Length = 0
            default:
                SkillGroup._Log("WARN", "_HasEmptyKeyArrays: unhandled mode=" this.mode)
                return false
        }
    }

    ; =================================================================
    ; 切换激活状态
    ; =================================================================
    Toggle() {
        wasActive := this.active
        try {
            if A_TickCount - this._lastToggleTime < SkillGroup.TOGGLE_DEBOUNCE_MS
                return -1
            this._lastToggleTime := A_TickCount

            wasActive := this.active
            this.active := !this.active

            if !this.active {
                this._ReleaseAllKeys()
                this._lastSend := Map()
                SkillGroup._Log("DEBUG", "SkillGroup.Toggle: 分组 " this.id " 已关闭")
                return false
            }

            this._executionCount := 0
            this._startTime := A_TickCount
            this._lastUpdateTime := A_TickCount
            if this.HasProp("_skippedHoldKeys") && this._skippedHoldKeys is Map
                this._skippedHoldKeys.Clear()

            switch this.mode {
                case "sequence", "enhanced_sequence":
                    this._currentStep := 1
                    this._nextStepTime := 0
                    this._nextStepTimeBase := 0
                case "periodic", "enhanced_periodic":
                    this._ResetPeriodicTriggerTimes()
                case "hybrid", "enhanced_hybrid":
                    for idx in this._seqSteps
                        this._seqSteps[idx] := 1
                    for idx in this._lastSeqRuns
                        this._lastSeqRuns[idx] := 0
                    this._ResetPeriodicTriggerTimes()
                case "hold":
                    this._holdStartTime := A_TickCount
                    this._holdRepeatPhase := ""
                    if this.holdKeys.Length > 0
                        this._PressHoldKeys()
            }

            if this.holdKeys.Length > 0 && this.holdMode = "continuous" && this.mode != "hold"
                this._PressHoldKeys()

            SkillGroup._Notify("分组 " this.id " 已激活", "success")
            return true
        } catch as e {
            if !wasActive && this.active {
                try
                    this._ReleaseAllKeys()
                this.active := false
            } else {
                this.active := wasActive
            }
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; =================================================================
    ; 长按操作
    ; =================================================================
    _PressHoldKeys() {
        this._holdStartTime := A_TickCount
        this._holdPatternStart := A_TickCount
        isMouseArr := this._isHoldMouse
        for i, k in this.holdKeys {
            if SkillGroup.IsKeyAllowed && !SkillGroup.IsKeyAllowed.Call(k, this.id)
                continue

            if SkillGroup.RegisterHoldKey {
                if !SkillGroup.RegisterHoldKey.Call(k, this.id)
                    continue
            }

            isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
            this._SendHoldKey(k, isMouse, true)
            this._heldKeys[k] := A_TickCount
            this._heldKeyMouse[k] := isMouse
        }
    }

    _ReleaseHoldKeys() {
        for k in this._heldKeys {
            isMouse := this._heldKeyMouse.Has(k) ? this._heldKeyMouse[k] : false
            this._SendHoldKey(k, isMouse, false)
            if SkillGroup.UnregisterHoldKey
                SkillGroup.UnregisterHoldKey.Call(k, this.id)
        }
        this._heldKeys.Clear()
        this._heldKeyMouse.Clear()
    }

    _SendHoldKey(key, isMouse, press := true) {
        if !SkillGroup._IsValidKeyName(key)
            return
        try {
            hasModifier := RegExMatch(key, "^[\^+!#]")
            isWheel := InStr(key, "WheelUp") || InStr(key, "WheelDown")
            if hasModifier {
                if press
                    SendInput("{Blind}" key)
                else {
                    bareKey := RegExReplace(key, "^[\^+!#]+", "")
                    if bareKey != ""
                        SendInput("{Blind}{" bareKey " Up}")
                }
            } else if isWheel {
                if press
                    SendInput("{Blind}{" key "}")
            } else {
                action := press ? "Down" : "Up"
                SendInput("{Blind}{" key " " action "}")
            }

            if KeyValidator.IsActive() {
                if isWheel {
                    if press
                        KeyValidator.OnSend(this.id, key, "down", A_TickCount - KeyValidator.GetStartTime())
                } else {
                    KeyValidator.OnSend(this.id, key, press ? "down" : "up", A_TickCount - KeyValidator.GetStartTime())
                }
            }
        } catch as e {
            SkillGroup._Log("ERROR", "_SendHoldKey 失败: key=" key " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    _ProcessHoldKeys() {
        if this.holdKeys.Length = 0
            return
        switch this.holdMode {
            case "continuous":
                isMouseArr := this._isHoldMouse
                for i, k in this.holdKeys {
                    if this._heldKeys.Has(k)
                        continue
                    if this.HasProp("_skippedHoldKeys") && this._skippedHoldKeys.Has(k)
                        continue
                    if SkillGroup.RegisterHoldKey {
                        if !SkillGroup.RegisterHoldKey.Call(k, this.id) {
                            if !this.HasProp("_skippedHoldKeys")
                                this._skippedHoldKeys := Map()
                            this._skippedHoldKeys[k] := true
                            continue
                        }
                    }
                    isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
                    this._SendHoldKey(k, isMouse, true)
                    this._heldKeys[k] := A_TickCount
                    this._heldKeyMouse[k] := isMouse
                }
            case "periodic":
                this._ExecutePeriodicHoldPattern()
        }
    }

    _ProcessSequenceHoldTriggers(step) {
        if this.holdKeys.Length = 0 || this.holdMode != "sequence" || this.holdTriggers.Length = 0
            return
        shouldHold := step <= this.holdTriggers.Length ? this.holdTriggers[step] : 0
        anyHeld := false
        for k in this.holdKeys {
            if this._heldKeys.Has(k) {
                anyHeld := true
                break
            }
        }
        if shouldHold && !anyHeld {
            this._PressHoldKeys()
        } else if !shouldHold && anyHeld {
            this._ReleaseHoldKeys()
        }
    }

    _ExecutePeriodicHoldPattern() {
        if this.holdPattern.Length < 2
            return
        if this.holdKeys.Length = 0
            return
        pressTime := this.holdPattern[1]
        releaseTime := this.holdPattern[2]
        isMouseArr := this._isHoldMouse

        if this._holdPhaseStart = 0
            this._holdPhaseStart := A_TickCount

        elapsed := A_TickCount - this._holdPhaseStart

        if elapsed < pressTime {
            for i, k in this.holdKeys {
                if !this._heldKeys.Has(k) {
                    if SkillGroup.RegisterHoldKey {
                        if !SkillGroup.RegisterHoldKey.Call(k, this.id)
                            continue
                    }
                    isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
                    this._SendHoldKey(k, isMouse, true)
                    this._heldKeys[k] := A_TickCount
                    this._heldKeyMouse[k] := isMouse
                }
            }
        } else if elapsed < pressTime + releaseTime {
            for i, k in this.holdKeys {
                if this._heldKeys.Has(k) {
                    isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
                    this._SendHoldKey(k, isMouse, false)
                    this._heldKeys.Delete(k)
                    if SkillGroup.UnregisterHoldKey
                        SkillGroup.UnregisterHoldKey.Call(k, this.id)
                }
            }
        } else {
            this._holdPhaseStart := A_TickCount
        }
    }

    ; =================================================================
    ; 混合模式子组执行
    ; =================================================================
    _ExecuteMixedGroups() {
        now := A_TickCount
        minRemaining := 0x7FFFFFFF

        for grpIdx, grp in this.groups {
            grpType := _GetProp(grp, "type", "periodic")
            pressKeys := _GetProp(grp, "pressKeys", [])
            if pressKeys.Length = 0
                continue
            isMouseArr := this._subGroupMouse.Has(grpIdx) ? this._subGroupMouse[grpIdx] : []

            if grpType = "periodic" {
                intervals := _GetProp(grp, "intervals", [])
                for i, k in pressKeys {
                    triggerKey := grpIdx "." i
                    interval := i <= intervals.Length ? intervals[i] : 50
                    if interval < 10
                        interval := 10
                    if !this._groupTriggerTimes.Has(triggerKey) {
                        offset := (i - 1) * 10
                        this._groupTriggerTimes[triggerKey] := now - offset
                        minRemaining := 1
                        continue
                    }
                    elapsed := now - this._groupTriggerTimes[triggerKey]
                    threshold := interval - Max(1, Round(interval * 0.05))
                    if elapsed >= threshold {
                        isMouse := i <= isMouseArr.Length ? isMouseArr[i] : false
                        this._SendKey(k, isMouse)
                        this._groupTriggerTimes[triggerKey] := this._groupTriggerTimes[triggerKey] + interval
                        if this._groupTriggerTimes[triggerKey] < A_TickCount - interval
                            this._groupTriggerTimes[triggerKey] := A_TickCount
                        minRemaining := 1
                    } else {
                        remaining := threshold - elapsed
                        if remaining < minRemaining
                            minRemaining := remaining
                    }
                }
            } else {
                if !this._seqSteps.Has(grpIdx)
                    continue
                seqInterval := this._seqIntervals.Has(grpIdx) ? this._seqIntervals[grpIdx] : 100
                if seqInterval < 10
                    seqInterval := 10
                elapsed := now - this._lastSeqRuns[grpIdx]
                threshold := seqInterval - Max(1, Round(seqInterval * 0.05))
                if elapsed >= threshold {
                    step := this._seqSteps[grpIdx]
                    keyIndex := Mod(step - 1, pressKeys.Length) + 1
                    keyToSend := pressKeys[keyIndex]
                    isMouse := keyIndex <= isMouseArr.Length ? isMouseArr[keyIndex] : false
                    this._SendKey(keyToSend, isMouse)
                    this._seqSteps[grpIdx] := Mod(step, pressKeys.Length) + 1
                    this._lastSeqRuns[grpIdx] := this._lastSeqRuns[grpIdx] + seqInterval
                    if this._lastSeqRuns[grpIdx] < A_TickCount - seqInterval
                        this._lastSeqRuns[grpIdx] := A_TickCount
                    minRemaining := 1
                } else {
                    remaining := threshold - elapsed
                    if remaining < minRemaining
                        minRemaining := remaining
                }
            }
        }
        return Max(1, minRemaining)
    }

    ; =================================================================
    ; 释放所有按键
    ; =================================================================
    _ReleaseAllKeys() {
        switch this.mode {
            case "periodic":
                for i, k in this.keys
                    this._ReleaseKey(k, i <= this._isMouse.Length ? this._isMouse[i] : false)
            case "sequence":
                for i, k in this.keys
                    this._ReleaseKey(k, i <= this._isMouse.Length ? this._isMouse[i] : false)
            case "hybrid":
                for i, k in this.periodicKeys
                    this._ReleaseKey(k, i <= this._periodicMouse.Length ? this._periodicMouse[i] : false)
                for i, k in this.seqKeys
                    this._ReleaseKey(k, i <= this._seqMouse.Length ? this._seqMouse[i] : false)
            case "enhanced_periodic":
                for i, k in this.pressKeys
                    this._ReleaseKey(k, i <= this._pressMouse.Length ? this._pressMouse[i] : false)
            case "enhanced_sequence":
                for i, k in this.pressKeys
                    this._ReleaseKey(k, i <= this._pressMouse.Length ? this._pressMouse[i] : false)
            case "enhanced_hybrid":
                for i, k in this.periodicPressKeys
                    this._ReleaseKey(k, i <= this._periodicMouse.Length ? this._periodicMouse[i] : false)
                for i, k in this.seqPressKeys
                    this._ReleaseKey(k, i <= this._seqMouse.Length ? this._seqMouse[i] : false)
        }
        this._ReleaseHoldKeys()
    }

    _ReleaseKey(key, isMouse) {
        if !SkillGroup._IsValidKeyName(key)
            return
        try {
            hasModifier := RegExMatch(key, "^[\^+!#]")
            isWheel := InStr(key, "WheelUp") || InStr(key, "WheelDown")
            if isWheel {
                return
            }
            if hasModifier {
                bareKey := RegExReplace(key, "^[\^+!#]+", "")
                if bareKey != ""
                    SendInput("{Blind}{" bareKey " Up}")
            } else {
                SendInput("{Blind}{" key " Up}")
            }
        } catch as e {
            SkillGroup._Log("ERROR", "_ReleaseKey 失败: key=" key " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 资源清理
    ; =================================================================
    Dispose() {
        try {
            this.active := false
            this._ReleaseAllKeys()
            this._heldKeys.Clear()
            this._lastTriggerTimes.Clear()
            this._groupTriggerTimes.Clear()
            this._seqSteps.Clear()
            this._lastSeqRuns.Clear()
            this._lastSend := Map()
            this._heldKeyMouse.Clear()
            this._holdPhaseStart := 0
            this._holdStartTime := 0
            this._holdRepeatPhase := ""
            this._executionCount := 0
            this._startTime := 0
            if this.HasProp("_activeHolds") && this._activeHolds is Map
                this._activeHolds.Clear()
            if this.HasProp("_subGroupMouse") && this._subGroupMouse is Map
                this._subGroupMouse.Clear()
            if this.HasProp("_seqIntervals") && this._seqIntervals is Map
                this._seqIntervals.Clear()
            if this.HasProp("_skippedHoldKeys") && this._skippedHoldKeys is Map
                this._skippedHoldKeys.Clear()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 主执行入口
    ; =================================================================
    Execute() {
        if !this.active
            return 0

        if this._HasEmptyKeyArrays()
            return 0

        this._executionCount++
        this._lastUpdateTime := A_TickCount

        try {
            executor := ModeRegistry.GetExecutor(this.mode)
            return executor.Execute(this)
        } catch as e {
            SkillGroup._Log("ERROR", "Execute failed: mode=" this.mode " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return 0
        }
    }

    ; =================================================================
    ; 发送按键（按下即释放，带防抖）
    ; =================================================================
    _SendKey(key, isMouse) {
        if this._lastSend.Has(key) {
            if A_TickCount - this._lastSend[key] < this._debounceMs
                return
        }

        if !SkillGroup._IsValidKeyName(key)
            return

        try {
            duration := this._keyPressDuration > 0 ? this._keyPressDuration : 15
            hasModifier := RegExMatch(key, "^[\^+!#]")
            isWheel := InStr(key, "WheelUp") || InStr(key, "WheelDown")

            if hasModifier {
                SendInput("{Blind}" key)
            } else if isWheel {
                SendInput("{Blind}{" key "}")
            } else {
                SendInput("{Blind}{" key " Down}")
                releaseKey := key
                if !this.HasProp("_pendingReleases")
                    this._pendingReleases := Map()
                if !this.HasProp("_releaseCounter")
                    this._releaseCounter := 0
                this._releaseCounter++
                releaseId := this._releaseCounter
                this._pendingReleases[key] := releaseId
                SetTimer(() => (this._pendingReleases.Has(key) && this._pendingReleases[key] = releaseId ? this._pendingReleases.Delete(key) : 0, SendInput("{Blind}{" releaseKey " Up}")), -duration)
            }
            this._lastSend[key] := A_TickCount

            if KeyValidator.IsActive() {
                if isWheel {
                    KeyValidator.OnSend(this.id, key, "down", A_TickCount - KeyValidator.GetStartTime())
                } else {
                    KeyValidator.OnSend(this.id, key, "down", A_TickCount - KeyValidator.GetStartTime())
                    KeyValidator.OnSend(this.id, key, "up", A_TickCount - KeyValidator.GetStartTime() + duration)
                }
            }
        } catch as e {
            SkillGroup._Log("ERROR", "_SendKey 失败: key=" key " error=" e.Message)
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 运行时状态
    ; =================================================================
    GetRuntimeStatus() {
        try {
            currentStep := 0
            if this.mode = "sequence" || this.mode = "enhanced_sequence"
                currentStep := this._currentStep
            else if this.mode = "hybrid" || this.mode = "enhanced_hybrid" {
                if this._seqSteps.Count > 0 {
                    for grpIdx, step in this._seqSteps {
                        currentStep := step
                        break
                    }
                }
            }

            return Map(
                "active", this.active,
                "executionCount", this._executionCount,
                "runTime", this.active ? A_TickCount - this._startTime : 0,
                "currentStep", currentStep,
                "lastUpdate", this._lastUpdateTime,
                "heldKeys", this._heldKeys.Count
            )
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return Map(
                "active", false,
                "executionCount", 0,
                "runTime", 0,
                "currentStep", 0,
                "lastUpdate", 0,
                "heldKeys", 0
            )
        }
    }

    ; =================================================================
    ; 按键名称验证
    ; =================================================================
    static _validKeysMap := ""

    static _GetValidKeysMap() {
        if SkillGroup._validKeysMap = "" {
            m := Map()
            for k in ["Space", "Enter", "Tab", "Esc", "BackSpace", "Delete",
                       "Insert", "Home", "End", "PgUp", "PgDn",
                       "LButton", "RButton", "MButton", "XButton1", "XButton2",
                       "WheelUp", "WheelDown",
                       "Up", "Down", "Left", "Right",
                       "LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt", "LWin", "RWin",
                       "Shift", "Ctrl", "Alt", "Win",
                       "CapsLock", "ScrollLock", "NumLock", "PrintScreen", "Pause",
                       "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
                       "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
                       "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv", "NumpadEnter",
                       "NumpadDot", "NumpadIns", "NumpadEnd", "NumpadDown",
                       "NumpadPgDn", "NumpadLeft", "NumpadClear", "NumpadRight",
                       "NumpadHome", "NumpadUp", "NumpadPgUp", "NumpadDel"]
                m[StrLower(k)] := true
            SkillGroup._validKeysMap := m
        }
        return SkillGroup._validKeysMap
    }

    static _IsValidKeyName(key) {
        if !IsSet(key) || key = ""
            return false

        baseKey := RegExReplace(key, "^[\^+!#]+", "")

        if RegExMatch(baseKey, "^[a-zA-Z0-9]$")
            return true
        if RegExMatch(baseKey, "^[fF]([1-9]|1[0-9]|2[0-4])$")
            return true

        lowerKey := StrLower(baseKey)
        return SkillGroup._GetValidKeysMap().Has(lowerKey)
    }

    ; =================================================================
    ; 内部日志/通知辅助（通过注入的抽象接口）
    ; =================================================================
    static _Log(level, message) {
        if SkillGroup.Logger {
            try
                SkillGroup.Logger.Log(level, message, Map("module", "SkillGroup"))
        }
    }

    static _Notify(message, type := "info") {
        if SkillGroup.Notifier {
            try
                SkillGroup.Notifier.Notify(message, type)
        }
    }
}
