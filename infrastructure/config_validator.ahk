; =================================================================
; 基础设施层 - 配置验证器
; 版本: 3.0
; 说明: 验证技能分组配置的完整性和合法性
;       支持所有7种模式的结构化字段验证
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "json_logger.ahk"

class ConfigValidator {
    static _validModesMap := Map(
        "periodic", true, "sequence", true, "hybrid", true,
        "enhanced_periodic", true, "enhanced_sequence", true, "enhanced_hybrid", true, "hold", true,
        "joystick_periodic", true, "joystick_sequence", true, "joystick_hold", true
    )

    static Validate(config) {
        errors := []

        if !ConfigValidator._HasField(config, "GroupSettings") {
            errors.Push(Map("type", "ERROR", "message", "缺少必需的配置节: GroupSettings"))
            return errors
        }

        groupSettings := _GetProp(config, "GroupSettings")
        if groupSettings is Map {
            for id, groupConfig in groupSettings
                errors.Push(ConfigValidator._ValidateGroup(id, groupConfig)*)
        }

        if ConfigValidator._HasField(config, "CONTROL_HOTKEYS")
            errors.Push(ConfigValidator._ValidateHotkeys(_GetProp(config, "CONTROL_HOTKEYS"))*)

        if ConfigValidator._HasField(config, "HoldSettings")
            errors.Push(ConfigValidator._ValidateHoldSettings(_GetProp(config, "HoldSettings"))*)

        return errors
    }

    static ValidateGroupHotkeys(config) {
        errors := []
        groupHotkeys := Map()

        if ConfigValidator._HasField(config, "GroupSettings") {
            gs := _GetProp(config, "GroupSettings")
            if gs is Map {
                for idStr, groupConfig in gs {
                    hotkey := ""
                    if groupConfig is Map && groupConfig.Has("hotkey")
                        hotkey := groupConfig["hotkey"]
                    else if IsObject(groupConfig) && HasProp(groupConfig, "hotkey")
                        hotkey := groupConfig.hotkey

                    if hotkey = "" {
                        errors.Push(Map("type", "ERROR", "message", "分组 " idStr ": 热键不能为空"))
                        continue
                    }

                    if StrLen(hotkey) > 15
                        errors.Push(Map("type", "ERROR", "message", "分组 " idStr ": 热键 '" hotkey "' 过长(>15字符)"))

                    if groupHotkeys.Has(hotkey)
                        errors.Push(Map("type", "ERROR", "message", "热键 '" hotkey "' 与分组 " groupHotkeys[hotkey] " 重复"))
                    groupHotkeys[hotkey] := idStr
                }
            }
        }

        return errors
    }

    static _ValidateGroup(id, config) {
        errors := []

        if !ConfigValidator._HasField(config, "hotkey")
            errors.Push(Map("type", "ERROR", "message", "分组" id "缺少热键(hotkey)"))

        if !ConfigValidator._HasField(config, "mode") {
            errors.Push(Map("type", "ERROR", "message", "分组" id "缺少模式(mode)"))
        } else {
            mode := _GetProp(config, "mode")
            if !ConfigValidator._validModesMap.Has(mode)
                errors.Push(Map("type", "ERROR", "message", "分组" id "有无效的模式: " mode))
            else
                errors.Push(ConfigValidator._ValidateModeFields(id, mode, config)*)
        }

        return errors
    }

    static ValidateGroupOnly(id, config) {
        if !(config is Map || IsObject(config))
            return [Map("type", "ERROR", "message", "分组" id ": 配置必须是对象")]

        errors := []

        if !ConfigValidator._HasField(config, "hotkey")
            errors.Push(Map("type", "ERROR", "message", "分组" id "缺少热键(hotkey)"))

        if !ConfigValidator._HasField(config, "mode") {
            errors.Push(Map("type", "ERROR", "message", "分组" id "缺少模式(mode)"))
        } else {
            mode := _GetProp(config, "mode")
            if !ConfigValidator._validModesMap.Has(mode)
                errors.Push(Map("type", "ERROR", "message", "分组" id "有无效的模式: " mode))
            else {
                fieldErrors := ConfigValidator._ValidateModeFields(id, mode, config)
                for e in fieldErrors
                    errors.Push(e)
            }
        }

        return errors
    }

    static _ValidateModeFields(id, mode, config) {
        errors := []

        switch mode {
            case "periodic":
                if !ConfigValidator._HasField(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式缺少按键(keys)"))
                else if ConfigValidator._IsFieldEmpty(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式按键(keys)不能为空数组"))
                if !ConfigValidator._HasField(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式缺少间隔(intervals)"))
                else if ConfigValidator._IsFieldEmpty(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "周期性模式间隔(intervals)不能为空数组"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "keys", "intervals", "周期性模式")*)

            case "sequence":
                if !ConfigValidator._HasField(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "序列模式缺少按键(keys)"))
                else if ConfigValidator._IsFieldEmpty(config, "keys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "序列模式按键(keys)不能为空数组"))
                if !ConfigValidator._HasField(config, "delays")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "序列模式缺少延迟(delays)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "keys", "delays", "序列模式")*)

            case "hybrid":
                if !ConfigValidator._HasField(config, "groups")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "混合模式缺少分组(groups)"))
                else
                    errors.Push(ConfigValidator._ValidateSubGroups(id, config)*)

            case "hold":
                if !ConfigValidator._HasField(config, "holdKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "长按模式缺少按键(holdKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "holdKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "长按模式按键(holdKeys)不能为空数组"))
                if ConfigValidator._HasField(config, "repeatInterval") {
                    ri := _GetProp(config, "repeatInterval")
                    if IsNumber(ri) && Number(ri) < 10
                        errors.Push(Map("type", "ERROR", "message", "分组" id " repeatInterval=" ri " 过小，最小 10ms"))
                }

            case "enhanced_periodic":
                if !ConfigValidator._HasField(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式缺少按键(pressKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式按键(pressKeys)不能为空数组"))
                if !ConfigValidator._HasField(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式缺少间隔(intervals)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "pressKeys", "intervals", "增强周期模式")*)

            case "enhanced_sequence":
                if !ConfigValidator._HasField(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式缺少按键(pressKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式按键(pressKeys)不能为空数组"))
                if !ConfigValidator._HasField(config, "pressDelays")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式缺少延迟(pressDelays)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "pressKeys", "pressDelays", "增强序列模式")*)

            case "enhanced_hybrid":
                if !ConfigValidator._HasField(config, "groups")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强混合模式缺少分组(groups)"))
                else
                    errors.Push(ConfigValidator._ValidateSubGroups(id, config)*)
                if ConfigValidator._HasField(config, "seqInterval") {
                    si := _GetProp(config, "seqInterval")
                    if IsNumber(si) && Number(si) < 10
                        errors.Push(Map("type", "ERROR", "message", "分组" id " seqInterval=" si " 过小，最小 10ms"))
                }

            case "joystick_periodic":
                if !ConfigValidator._HasField(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式缺少按键(joyKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式按键(joyKeys)不能为空数组"))
                if !ConfigValidator._HasField(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式缺少间隔(intervals)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "joyKeys", "intervals", "手柄周期模式")*)

            case "joystick_sequence":
                if !ConfigValidator._HasField(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式缺少按键(joyKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式按键(joyKeys)不能为空数组"))
                if !ConfigValidator._HasField(config, "delays")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式缺少延迟(delays)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "joyKeys", "delays", "手柄序列模式")*)

            case "joystick_hold":
                if !ConfigValidator._HasField(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄长按模式缺少按键(joyKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄长按模式按键(joyKeys)不能为空数组"))
                if ConfigValidator._HasField(config, "holdDuration") {
                    hd := _GetProp(config, "holdDuration")
                    if IsNumber(hd) && Number(hd) < 50
                        errors.Push(Map("type", "ERROR", "message", "分组" id " holdDuration=" hd " 过小，最小 50ms"))
                }

            default:
                errors.Push(Map("type", "WARNING", "message", "分组" id " (" mode "): 未知模式类型，跳过字段级验证"))
        }

        if ConfigValidator._HasField(config, "holdPattern") {
            hp := _GetProp(config, "holdPattern")
            if hp is Array {
                if hp.Length > 0 && hp.Length < 2
                    errors.Push(Map("type", "ERROR", "message", "分组" id " holdPattern 至少需要2个元素(按下时长,释放时长)"))
                for vi, vv in hp {
                    if IsNumber(vv) && Number(vv) < 10
                        errors.Push(Map("type", "ERROR", "message", "分组" id " holdPattern[" vi "]=" vv " 过小，最小 10ms"))
                }
            }
        }

        if ConfigValidator._HasField(config, "holdTriggers") {
            ht := _GetProp(config, "holdTriggers")
            if ht is Array {
                for vi, vv in ht {
                    if vv != 0 && vv != 1
                        errors.Push(Map("type", "WARNING", "message", "分组" id " holdTriggers[" vi "]=" vv " 应为 0 或 1"))
                }
            }
        }

        return errors
    }

    static _ValidateHotkeys(hotkeys) {
        errors := []
        requiredActions := ["emergency", "toggleAll", "showStatus", "toggleHoldMode", "releaseAllHolds"]
        for action in requiredActions {
            if !ConfigValidator._HasField(hotkeys, action)
                errors.Push(Map("type", "ERROR", "message", "缺少热键配置: " action))
            else {
                val := _GetProp(hotkeys, action)
                if val = "" || !IsObject(val) && StrLen(String(val)) = 0
                    errors.Push(Map("type", "WARNING", "message", "热键配置 " action " 值为空"))
            }
        }
        return errors
    }

    static _ValidateHoldSettings(settings) {
        errors := []

        if ConfigValidator._HasField(settings, "pressSpeed") {
            speed := _GetProp(settings, "pressSpeed")
            try {
                speedNum := speed is Integer ? speed : Integer(speed)
                if speedNum < 1 || speedNum > 100
                    errors.Push(Map("type", "ERROR", "message", "pressSpeed 应在 1-100 范围，当前: " speedNum))
            } catch {
                errors.Push(Map("type", "ERROR", "message", "pressSpeed 值无效，应为数字，当前: " speed))
            }
        }

        if ConfigValidator._HasField(settings, "debounceDelay") {
            delay := _GetProp(settings, "debounceDelay")
            try {
                delayNum := delay is Integer ? delay : Integer(delay)
                if delayNum < 0 || delayNum > 1000
                    errors.Push(Map("type", "WARNING", "message", "debounceDelay 建议在 0-1000 范围，当前: " delayNum))
            } catch {
                errors.Push(Map("type", "WARNING", "message", "debounceDelay 值无效，应为数字，当前: " delay))
            }
        }

        if ConfigValidator._HasField(settings, "checkInterval") {
            interval := _GetProp(settings, "checkInterval")
            try {
                intervalNum := interval is Integer ? interval : Integer(interval)
                if intervalNum < 10 || intervalNum > 1000
                    errors.Push(Map("type", "ERROR", "message", "checkInterval 应在 10-1000 范围，当前: " intervalNum))
            } catch {
                errors.Push(Map("type", "ERROR", "message", "checkInterval 值无效，应为数字，当前: " interval))
            }
        }

        if ConfigValidator._HasField(settings, "allowOverlap") {
            val := _GetProp(settings, "allowOverlap")
            if val != true && val != false && val != 0 && val != 1
                errors.Push(Map("type", "WARNING", "message", "allowOverlap 应为布尔值"))
        }

        if ConfigValidator._HasField(settings, "releaseOnEmergency") {
            val := _GetProp(settings, "releaseOnEmergency")
            if val != true && val != false && val != 0 && val != 1
                errors.Push(Map("type", "WARNING", "message", "releaseOnEmergency 应为布尔值"))
        }

        return errors
    }

    static _IsFieldEmpty(obj, field) {
        if obj is Map {
            if obj.Has(field) {
                val := obj[field]
                if val is Array
                    return val.Length = 0
            }
        } else if IsObject(obj) {
            if HasProp(obj, field) {
                val := obj.%field%
                if val is Array
                    return val.Length = 0
            }
        }
        return false
    }

    static _ValidateSubGroups(id, config) {
        errors := []
        groups := _GetProp(config, "groups")
        if !(groups is Array) || groups.Length = 0 {
            errors.Push(Map("type", "ERROR", "message", "分组" id "子组(groups)不能为空数组"))
            return errors
        }

        for i, grp in groups {
            grpType := ""
            if grp is Map && grp.Has("type")
                grpType := grp["type"]
            else if IsObject(grp) && HasProp(grp, "type")
                grpType := grp.type

            if grpType != "periodic" && grpType != "sequence" {
                errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i "类型必须为 periodic 或 sequence"))
                continue
            }

            pressKeys := ""
            if grp is Map && grp.Has("pressKeys")
                pressKeys := grp["pressKeys"]
            else if IsObject(grp) && HasProp(grp, "pressKeys")
                pressKeys := grp.pressKeys

            if pressKeys is Array && pressKeys.Length = 0
                errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i "按键(pressKeys)不能为空数组"))
            else if !(pressKeys is Array) && pressKeys != ""
                errors.Push(Map("type", "WARNING", "message", "分组" id "子组" i "按键(pressKeys)应为数组"))

            if grp is Map && !grp.Has("pressKeys") && !grp.Has("keys")
                errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i "缺少按键字段"))

            if grpType = "periodic" {
                intervals := ""
                if grp is Map && grp.Has("intervals")
                    intervals := grp["intervals"]
                else if IsObject(grp) && HasProp(grp, "intervals")
                    intervals := grp.intervals

                if intervals = "" || (intervals is Array && intervals.Length = 0)
                    errors.Push(Map("type", "WARNING", "message", "分组" id "子组" i "周期性类型缺少间隔(intervals)，将使用默认值"))
                else if intervals is Array && pressKeys is Array && intervals.Length < pressKeys.Length
                    errors.Push(Map("type", "WARNING", "message", "分组" id "子组" i "间隔(intervals)数量少于按键(pressKeys)，不足部分将使用默认值"))

                if intervals is Array {
                    for vi, vv in intervals {
                        if IsNumber(vv) && Number(vv) < 10
                            errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i " intervals[" vi "]=" vv " 过小，最小 10ms"))
                    }
                }
            } else if grpType = "sequence" {
                delays := ""
                if grp is Map && grp.Has("delays")
                    delays := grp["delays"]
                else if IsObject(grp) && HasProp(grp, "delays")
                    delays := grp.delays

                if delays = "" || (delays is Array && delays.Length = 0)
                    errors.Push(Map("type", "WARNING", "message", "分组" id "子组" i "序列类型缺少延迟(delays)，将使用默认值"))
                else if delays is Array && pressKeys is Array && delays.Length < pressKeys.Length
                    errors.Push(Map("type", "WARNING", "message", "分组" id "子组" i "延迟(delays)数量少于按键(pressKeys)，不足部分将使用默认值"))

                if delays is Array {
                    for vi, vv in delays {
                        if IsNumber(vv) && Number(vv) < 10
                            errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i " delays[" vi "]=" vv " 过小，最小 10ms"))
                    }
                }
            }
        }

        return errors
    }

    static _HasField(obj, field) {
        if obj is Map
            return obj.Has(field)
        else if IsObject(obj)
            return HasProp(obj, field)
        return false
    }

    static _ValidateArrayLength(id, config, keysField, valuesField, modeName) {
        errors := []
        keysArr := _GetProp(config, keysField)
        valuesArr := _GetProp(config, valuesField)
        if keysArr is Array && valuesArr is Array && keysArr.Length > 0 && valuesArr.Length > 0 {
            if valuesArr.Length < keysArr.Length
                errors.Push(Map("type", "WARNING", "message", "分组" id modeName " " valuesField "(" valuesArr.Length ") 少于 " keysField "(" keysArr.Length ")，不足部分将使用默认值"))
            for i, v in valuesArr {
                if IsNumber(v) && Number(v) < 10
                    errors.Push(Map("type", "ERROR", "message", "分组" id modeName " " valuesField "[" i "] 值 " v " 过小，最小 10ms"))
            }
        }
        return errors
    }

    static _ArrayContains(arr, value) {
        for item in arr {
            if item = value
                return true
        }
        return false
    }

    static GetErrorMessage(errorItem) {
        if errorItem is Map && errorItem.Has("message")
            return errorItem["message"]
        return String(errorItem)
    }
}
