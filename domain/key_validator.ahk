; =================================================================
; 领域层 - KeyValidator 执行验证器
; 版本: 1.0
; 说明: 在 _SendKey/_SendHoldKey 中埋点收集实际发送时序
;       生成验证报告（顺序正确性/间隔偏差/发送成功率/长按时序）
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "../infrastructure/error_system.ahk"

class KeyValidator {
    static _active := false
    static _groupId := ""
    static _expectedSeq := []
    static _actualSeq := []
    static _startTime := 0
    static _onEvent := ""
    static MAX_EVENTS := 10000

    static IsActive() => this._active

    static GetStartTime() => this._startTime

    static GetActualCount() => this._actualSeq.Length

    static Start(groupId, onEvent) {
        if this._active
            return
        this._active := true
        this._groupId := groupId
        this._actualSeq := []
        this._expectedSeq := []
        this._startTime := A_TickCount
        this._onEvent := onEvent
        this._LoadExpectedSequence(groupId)
    }

    static Stop() {
        if !this._active
            return ""
        this._active := false
        report := ""
        try {
            report := this._BuildReport()
        } catch as e {
            ErrorSystem.LogError("KeyValidator BuildReport failed: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
        this._onEvent := ""
        this._groupId := ""
        this._startTime := 0
        this._expectedSeq := []
        this._actualSeq := []
        return report
    }

    static OnSend(groupId, key, event, timestamp) {
        if !this._active
            return
        if groupId != this._groupId
            return
        if this._actualSeq.Length >= this.MAX_EVENTS {
            this.Stop()
            return
        }
        if timestamp = ""
            timestamp := A_TickCount - this._startTime
        baseKey := RegExReplace(key, "^[\^+!#]+", "")
        isMouse := baseKey = "LButton" || baseKey = "RButton" || baseKey = "MButton" || baseKey = "XButton1" || baseKey = "XButton2" || baseKey = "WheelUp" || baseKey = "WheelDown"
        evt := Map(
            "key", key,
            "event", event,
            "timestamp", timestamp,
            "device", isMouse ? "mouse" : "keyboard"
        )
        this._actualSeq.Push(evt)
        if this._onEvent {
            try
                this._onEvent.Call(evt)
            catch as e
                ErrorSystem.LogError("KeyValidator onEvent callback error: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }

    static _LoadExpectedSequence(groupId) {
        if !IsSet(SkillManager)
            return
        if !SkillManager.Groups.Has(groupId)
            return
        group := SkillManager.Groups[groupId]
        this._groupMode := HasProp(group, "mode") ? group.mode : "periodic"
        keys := []
        intervals := []
        if HasProp(group, "groups") && group.groups.Length > 0 {
            for grpIdx, sg in group.groups {
                sgKeys := []
                if sg is Map {
                    if sg.Has("pressKeys")
                        for k in sg["pressKeys"]
                            sgKeys.Push(k)
                    else if sg.Has("keys")
                        for k in sg["keys"]
                            sgKeys.Push(k)
                } else {
                    if HasProp(sg, "pressKeys")
                        for k in sg.pressKeys
                            sgKeys.Push(k)
                    else if HasProp(sg, "keys")
                        for k in sg.keys
                            sgKeys.Push(k)
                }
                sgType := ""
                if sg is Map
                    sgType := sg.Has("type") ? sg["type"] : "periodic"
                else
                    sgType := HasProp(sg, "type") ? sg.type : "periodic"
                sgIntervals := []
                if sg is Map {
                    if sg.Has("intervals") && sg["intervals"].Length > 0 {
                        Loop sg["intervals"].Length
                            sgIntervals.Push(sg["intervals"][A_Index])
                    } else if sg.Has("delays") && sg["delays"].Length > 0 {
                        Loop sg["delays"].Length
                            sgIntervals.Push(sg["delays"][A_Index])
                    }
                } else {
                    if HasProp(sg, "intervals") && sg.intervals.Length > 0 {
                        Loop sg.intervals.Length
                            sgIntervals.Push(sg.intervals[A_Index])
                    } else if HasProp(sg, "delays") && sg.delays.Length > 0 {
                        Loop sg.delays.Length
                            sgIntervals.Push(sg.delays[A_Index])
                    }
                }
                keyIdx := 0
                sgSeqInterval := 0
                if sgType = "sequence" {
                    if HasProp(group, "_seqIntervals") && group._seqIntervals.Has(grpIdx)
                        sgSeqInterval := group._seqIntervals[grpIdx]
                    else {
                        if sg is Map
                            sgSeqInterval := sg.Has("seqInterval") ? sg["seqInterval"] : 0
                        else
                            sgSeqInterval := HasProp(sg, "seqInterval") ? sg.seqInterval : 0
                        if sgSeqInterval <= 0 {
                            Loop sgIntervals.Length
                                sgSeqInterval += sgIntervals[A_Index]
                            sgSeqInterval := sgKeys.Length > 0 ? Round(sgSeqInterval / sgKeys.Length) : 100
                        }
                    }
                }
                for k in sgKeys {
                    keyIdx++
                    interval := 50
                    if sgType = "sequence" {
                        if keyIdx <= sgIntervals.Length
                            interval := sgIntervals[keyIdx]
                        else if sgIntervals.Length > 0
                            interval := sgIntervals[1]
                    } else if sgType = "periodic" {
                        if keyIdx <= sgIntervals.Length
                            interval := sgIntervals[keyIdx]
                        else if sgIntervals.Length > 0
                            interval := sgIntervals[1]
                    }
                    this._expectedSeq.Push(Map("key", k, "interval", interval, "subType", sgType, "seqCycleInterval", sgSeqInterval * sgKeys.Length))
                }
            }
            return
        }
        if HasProp(group, "pressKeys") && group.pressKeys.Length > 0 {
            for k in group.pressKeys
                keys.Push(k)
            if HasProp(group, "intervals") && group.intervals.Length > 0 {
                Loop group.intervals.Length
                    intervals.Push(group.intervals[A_Index])
            } else if HasProp(group, "pressDelays") && group.pressDelays.Length > 0 {
                Loop group.pressDelays.Length
                    intervals.Push(group.pressDelays[A_Index])
            }
        } else if HasProp(group, "keys") && group.keys.Length > 0 {
            for k in group.keys
                keys.Push(k)
            _hasIntervals := HasProp(group, "intervals")
            _hasDelays := HasProp(group, "delays")
            _hasPressDelays := HasProp(group, "pressDelays")
            if _hasIntervals && group.intervals.Length > 0 {
                Loop group.intervals.Length
                    intervals.Push(group.intervals[A_Index])
            } else if _hasDelays && group.delays.Length > 0 {
                Loop group.delays.Length
                    intervals.Push(group.delays[A_Index])
            } else if _hasPressDelays && group.pressDelays.Length > 0 {
                Loop group.pressDelays.Length
                    intervals.Push(group.pressDelays[A_Index])
            }
        } else if HasProp(group, "holdKeys") && group.holdKeys.Length > 0 {
            for k in group.holdKeys
                keys.Push(k)
        }
        this._expectedSeq := []
        for i, k in keys {
            interval := i <= intervals.Length ? intervals[i] : 50
            this._expectedSeq.Push(Map("key", k, "interval", interval))
        }
    }

    static _BuildReport() {
        totalExpected := this._expectedSeq.Length
        totalActual := this._actualSeq.Length

        orderCorrect := true
        if totalActual > 0 && totalExpected > 0 {
            actualKeyIdx := 0
            Loop totalActual {
                i := A_Index
                if this._actualSeq[i]["event"] = "down" {
                    actualKeyIdx++
                    expIdx := Mod(actualKeyIdx - 1, totalExpected) + 1
                    if this._actualSeq[i]["key"] != this._expectedSeq[expIdx]["key"] {
                        orderCorrect := false
                        break
                    }
                }
            }
        }

        details := []
        deviations := []
        lastDownTs := 0
        lastDownKey := ""
        hasPeriodic := false
        Loop totalExpected {
            if this._expectedSeq[A_Index].Has("interval") && this._expectedSeq[A_Index]["interval"] > 0 {
                hasPeriodic := true
                break
            }
        }
        if hasPeriodic {
            isSequenceMode := this._groupMode = "sequence" || this._groupMode = "enhanced_sequence"
            isHybridMode := this._groupMode = "hybrid" || this._groupMode = "enhanced_hybrid"
            totalCycleInterval := 0
            Loop totalExpected {
                iv := this._expectedSeq[A_Index].Has("interval") ? this._expectedSeq[A_Index]["interval"] : 0
                totalCycleInterval += iv
            }
            keyOwnInterval := Map()
            keyIsSeq := Map()
            keySeqCycleInterval := Map()
            Loop totalExpected {
                k := this._expectedSeq[A_Index]["key"]
                if !keyOwnInterval.Has(k) {
                    keyOwnInterval[k] := this._expectedSeq[A_Index].Has("interval") ? this._expectedSeq[A_Index]["interval"] : 50
                    keyIsSeq[k] := isHybridMode && this._expectedSeq[A_Index].Has("subType") && this._expectedSeq[A_Index]["subType"] = "sequence"
                    if keyIsSeq[k] && this._expectedSeq[A_Index].Has("seqCycleInterval")
                        keySeqCycleInterval[k] := this._expectedSeq[A_Index]["seqCycleInterval"]
                    else
                        keySeqCycleInterval[k] := 0
                }
            }
            lastDownByKey := Map()
            Loop totalActual {
                i := A_Index
                if this._actualSeq[i]["event"] != "down"
                    continue
                key := this._actualSeq[i]["key"]
                ts := this._actualSeq[i]["timestamp"]
                if lastDownByKey.Has(key) {
                    actualInterval := ts - lastDownByKey[key]
                    if isSequenceMode
                        expectedInterval := totalCycleInterval
                    else if isHybridMode && keyIsSeq.Has(key) && keyIsSeq[key] && keySeqCycleInterval.Has(key) && keySeqCycleInterval[key] > 0
                        expectedInterval := keySeqCycleInterval[key]
                    else
                        expectedInterval := keyOwnInterval.Has(key) ? keyOwnInterval[key] : 50
                    deviation := expectedInterval > 0 ? Round(Abs(actualInterval - expectedInterval) / expectedInterval * 100, 1) : 0
                    deviations.Push(deviation)
                    status := deviation <= 20 ? "good" : (deviation <= 50 ? "acceptable" : "poor")
                    details.Push(Map(
                        "key", key,
                        "expectedInterval", expectedInterval,
                        "actualInterval", actualInterval,
                        "deviation", deviation,
                        "status", status
                    ))
                }
                lastDownByKey[key] := ts
            }
        } else {
            Loop totalActual {
                i := A_Index
                if this._actualSeq[i]["event"] != "down"
                    continue
                ts := this._actualSeq[i]["timestamp"]
                if lastDownTs > 0 {
                    actualInterval := ts - lastDownTs
                    expectedInterval := totalExpected > 0 && this._expectedSeq[1].Has("interval") ? this._expectedSeq[1]["interval"] : 50
                    deviation := expectedInterval > 0 ? Round(Abs(actualInterval - expectedInterval) / expectedInterval * 100, 1) : 0
                    deviations.Push(deviation)
                    status := deviation <= 20 ? "good" : (deviation <= 50 ? "acceptable" : "poor")
                    details.Push(Map(
                        "key", this._actualSeq[i]["key"],
                        "expectedInterval", expectedInterval,
                        "actualInterval", actualInterval,
                        "deviation", deviation,
                        "status", status
                    ))
                }
                lastDownTs := ts
            }
        }

        avgDeviation := 0
        maxDeviation := 0
        if deviations.Length > 0 {
            sum := 0
            for d in deviations
                sum += d
            avgDeviation := Round(sum / deviations.Length, 1)
            mx := deviations[1]
            for d in deviations
                mx := Max(mx, d)
            maxDeviation := Round(mx, 1)
        }
        actualDownCount := 0
        Loop totalActual {
            if this._actualSeq[A_Index]["event"] = "down"
                actualDownCount++
        }
        sendSuccessRate := totalExpected > 0 ? Round(Min(actualDownCount, totalExpected) / totalExpected, 2) : 1

        holdTimingCorrect := true
        holdDetails := []
        pendingDowns := Map()
        Loop totalActual {
            i := A_Index
            evt := this._actualSeq[i]
            baseKey := RegExReplace(evt["key"], "^[\^+!#]+", "")
            isWheelEvt := baseKey = "WheelUp" || baseKey = "WheelDown"
            if evt["event"] = "down" && !isWheelEvt {
                if !pendingDowns.Has(evt["key"])
                    pendingDowns[evt["key"]] := []
                pendingDowns[evt["key"]].Push(evt["timestamp"])
            } else if evt["event"] = "up" && pendingDowns.Has(evt["key"]) && pendingDowns[evt["key"]].Length > 0 {
                downTs := pendingDowns[evt["key"]].RemoveAt(1)
                holdDuration := evt["timestamp"] - downTs
                isValid := holdDuration >= 5 && holdDuration <= 200
                if !isValid
                    holdTimingCorrect := false
                holdDetails.Push(Map(
                    "key", evt["key"],
                    "downTs", downTs,
                    "upTs", evt["timestamp"],
                    "holdDuration", holdDuration,
                    "valid", isValid
                ))
            }
        }
        for key in pendingDowns {
            if pendingDowns[key].Length > 0 {
                holdTimingCorrect := false
                for downTs in pendingDowns[key] {
                    holdDetails.Push(Map(
                        "key", key,
                        "downTs", downTs,
                        "upTs", 0,
                        "holdDuration", 0,
                        "valid", false
                    ))
                }
            }
        }

        return Map(
            "groupId", this._groupId,
            "duration", A_TickCount - this._startTime,
            "totalExpected", totalExpected,
            "totalActual", totalActual,
            "orderCorrect", orderCorrect,
            "avgIntervalDeviation", avgDeviation,
            "maxIntervalDeviation", maxDeviation,
            "sendSuccessRate", sendSuccessRate,
            "holdTimingCorrect", holdTimingCorrect,
            "holdDetails", holdDetails,
            "details", details
        )
    }
}
