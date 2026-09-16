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
; A1 已备案妥协 #1：基础设施层引用领域层纯工具类（JoystickInput 无副作用、无状态）
#Include "../domain/joystick_input.ahk"

class ConfigValidator {
    static _validModesMap := Map(
        "periodic", true, "sequence", true, "hybrid", true,
        "enhanced_periodic", true, "enhanced_sequence", true, "enhanced_hybrid", true, "hold", true,
        "joystick_periodic", true, "joystick_sequence", true, "joystick_hold", true
    )

    static _validKeysMap := ""

    ; =================================================================
    ; 可疑配置值阈值
    ; 与 asd-domain::validator（asd-tauri/crates/asd-domain/src/validator.rs）同源，
    ; BUG-6 的双栈对齐项；修改任一侧必须同步另一侧。
    ; =================================================================
    ; 单个间隔/延迟的「合理上界」（毫秒）。超过该值虽不违法（AHK 侧照常执行），
    ; 但通常意味着单位写错（把秒当毫秒）。仅告警，不拦截。
    static MAX_REASONABLE_INTERVAL_MS := 60000

    ; 单个间隔/延迟的「硬错误上界」（毫秒）。超过即判定为非法。
    ; (MAX_REASONABLE_INTERVAL_MS, MAX_INTERVAL_MS] 区间 = 「可疑但合法」，由 WARNING 覆盖。
    static MAX_INTERVAL_MS := 86400000

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
        else {
            ; I18: 验证热键格式合法性，避免无效热键在运行时 Hotkey() 调用时才抛异常
            hotkey := _GetProp(config, "hotkey")
            if !ConfigValidator._IsValidHotkeyFormat(hotkey)
                errors.Push(Map("type", "ERROR", "message", "分组" id "热键格式无效: " hotkey))
        }

        if !ConfigValidator._HasField(config, "mode") {
            errors.Push(Map("type", "ERROR", "message", "分组" id "缺少模式(mode)"))
        } else {
            mode := _GetProp(config, "mode")
            if !ConfigValidator._validModesMap.Has(mode)
                errors.Push(Map("type", "ERROR", "message", "分组" id "有无效的模式: " mode))
            else {
                errors.Push(ConfigValidator._ValidateModeFields(id, mode, config)*)
                errors.Push(ConfigValidator._ValidateSuspiciousModeValues(id, mode, config)*)
            }
        }

        return errors
    }

    ; I18: 验证热键格式是否合法
    ; 合法格式：零或多个修饰键前缀(! ^ + # ~ * < >) + 合法按键名
    ; 合法按键名：F1-F24、PascalCase命名键(Space/Tab/LButton等)、单字母、单数字
    ; 拒绝：纯长数字(12345)、混合无效字符串(xyz123)、空字符串
    static _IsValidHotkeyFormat(hotkey) {
        if hotkey = ""
            return false
        hotkeyStr := String(hotkey)
        pattern := "^[!^+~*<>#]*([fF](?:[1-9]|1[0-9]|2[0-4])|[A-Z][a-zA-Z0-9]+|[a-zA-Z]|[0-9])$"
        return RegExMatch(hotkeyStr, pattern) > 0
    }

    ; =================================================================
    ; 按键名合法性校验（下沉共享工具，与 domain/skill_group.ahk 的
    ; SkillGroup._IsValidKeyName 保持同步；修改任一侧须同步另一侧）
    ; =================================================================
    static _IsValidKeyName(key) {
        if !IsSet(key) || key = ""
            return false
        baseKey := RegExReplace(key, "^[\^+!#]+", "")
        if RegExMatch(baseKey, "^[a-zA-Z0-9]$")
            return true
        if RegExMatch(baseKey, "^[fF]([1-9]|1[0-9]|2[0-4])$")
            return true
        lowerKey := StrLower(baseKey)
        return ConfigValidator._GetValidKeysMap().Has(lowerKey)
    }

    static _GetValidKeysMap() {
        if ConfigValidator._validKeysMap = "" {
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
            ConfigValidator._validKeysMap := m
        }
        return ConfigValidator._validKeysMap
    }

    ; 逐元素校验按键数组：isJoystick 时用 JoystickInput.IsJoystickKey，否则用 _IsValidKeyName
    static _ValidateKeyArray(id, arr, fieldLabel, isJoystick := false) {
        errors := []
        if !(arr is Array)
            return errors
        for i, key in arr {
            if !(key is String) && !IsNumber(key)
                continue
            keyStr := String(key)
            valid := isJoystick ? JoystickInput.IsJoystickKey(keyStr) : ConfigValidator._IsValidKeyName(keyStr)
            if !valid
                errors.Push(Map("type", "ERROR", "message", "分组" id " 的 " fieldLabel "[" i "] 非法按键名: " keyStr))
        }
        return errors
    }

    static ValidateGroupOnly(id, config) {
        if !(config is Map || IsObject(config))
            return [Map("type", "ERROR", "message", "分组" id ": 配置必须是对象")]

        errors := []

        if !ConfigValidator._HasField(config, "hotkey")
            errors.Push(Map("type", "ERROR", "message", "分组" id "缺少热键(hotkey)"))
        else {
            ; I18: 与 _ValidateGroup 一致，追加热键格式校验（Create/Update 分组入口缺口）
            hotkey := _GetProp(config, "hotkey")
            if !ConfigValidator._IsValidHotkeyFormat(hotkey)
                errors.Push(Map("type", "ERROR", "message", "分组" id "热键格式无效: " hotkey))
        }

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
                ; 与 _ValidateGroup 保持一致：Create/Update 入口同样输出可疑值告警
                for e in ConfigValidator._ValidateSuspiciousModeValues(id, mode, config)
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
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "keys"), "keys")*)
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
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "keys"), "keys")*)
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
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "holdKeys"), "holdKeys")*)
                if ConfigValidator._HasField(config, "repeatInterval") {
                    ri := _GetProp(config, "repeatInterval")
                    if IsNumber(ri) && Number(ri) < 10
                        errors.Push(Map("type", "ERROR", "message", "分组" id " repeatInterval=" ri " 过小，最小 10ms"))
                    ; M19: 数值上限检查，防止超大数值导致定时器间隔错误
                    if IsNumber(ri) && Number(ri) > ConfigValidator.MAX_INTERVAL_MS
                        errors.Push(Map("type", "ERROR", "message", "分组" id " repeatInterval=" ri " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
                }

            case "enhanced_periodic":
                if !ConfigValidator._HasField(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式缺少按键(pressKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式按键(pressKeys)不能为空数组"))
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "pressKeys"), "pressKeys")*)
                if !ConfigValidator._HasField(config, "intervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强周期模式缺少间隔(intervals)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "pressKeys", "intervals", "增强周期模式")*)

            case "enhanced_sequence":
                if !ConfigValidator._HasField(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式缺少按键(pressKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "pressKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "增强序列模式按键(pressKeys)不能为空数组"))
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "pressKeys"), "pressKeys")*)
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
                    ; M19: 数值上限检查，防止超大数值导致定时器间隔错误
                    if IsNumber(si) && Number(si) > ConfigValidator.MAX_INTERVAL_MS
                        errors.Push(Map("type", "ERROR", "message", "分组" id " seqInterval=" si " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
                }

            case "joystick_periodic":
                if !ConfigValidator._HasField(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式缺少按键(joyKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式按键(joyKeys)不能为空数组"))
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "joyKeys"), "joyKeys", true)*)
                ; 间隔字段是 joyIntervals，不是 intervals —— 运行时（domain/joystick_executor.ahk
                ; 与 v4 的 ahk_executor/joystick.ahk）读的就是 joyIntervals。校验器原来查 intervals，
                ; 于是任何手柄分组都会被判 ERROR；而 SaveConfig 遇到 ERROR 级问题会**整份配置拒绝保存**，
                ; 等于一个手柄分组就让用户连普通分组都存不下来。
                if !ConfigValidator._HasField(config, "joyIntervals")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄周期模式缺少间隔(joyIntervals)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "joyKeys", "joyIntervals", "手柄周期模式")*)

            case "joystick_sequence":
                if !ConfigValidator._HasField(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式缺少按键(joyKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式按键(joyKeys)不能为空数组"))
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "joyKeys"), "joyKeys", true)*)
                ; 同上：序列模式的延迟字段是 joyDelays（见 joystick_executor.ahk / joystick.ahk）
                if !ConfigValidator._HasField(config, "joyDelays")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄序列模式缺少延迟(joyDelays)"))
                else
                    errors.Push(ConfigValidator._ValidateArrayLength(id, config, "joyKeys", "joyDelays", "手柄序列模式")*)

            case "joystick_hold":
                if !ConfigValidator._HasField(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄长按模式缺少按键(joyKeys)"))
                else if ConfigValidator._IsFieldEmpty(config, "joyKeys")
                    errors.Push(Map("type", "ERROR", "message", "分组" id "手柄长按模式按键(joyKeys)不能为空数组"))
                else
                    errors.Push(ConfigValidator._ValidateKeyArray(id, _GetProp(config, "joyKeys"), "joyKeys", true)*)
                if ConfigValidator._HasField(config, "holdDuration") {
                    hd := _GetProp(config, "holdDuration")
                    if IsNumber(hd) && Number(hd) < 50
                        errors.Push(Map("type", "ERROR", "message", "分组" id " holdDuration=" hd " 过小，最小 50ms"))
                    ; M19: 数值上限检查，防止超大数值导致定时器间隔错误
                    if IsNumber(hd) && Number(hd) > ConfigValidator.MAX_INTERVAL_MS
                        errors.Push(Map("type", "ERROR", "message", "分组" id " holdDuration=" hd " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
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
                    ; M19: 数值上限检查
                    if IsNumber(vv) && Number(vv) > ConfigValidator.MAX_INTERVAL_MS
                        errors.Push(Map("type", "ERROR", "message", "分组" id " holdPattern[" vi "]=" vv " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
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

    ; =================================================================
    ; 可疑配置值检查
    ; 对齐 asd-domain::validator::validate_suspicious_mode_values（BUG-6 双栈对齐）。
    ;
    ; 只输出 WARNING，不新增 ERROR：AHK 侧对「按键数 ↔ 时间序列长度不匹配」有兜底值、
    ; 对超长间隔也会照常执行，功能不会崩；把这些值升级为 ERROR 会拒绝用户原本可用的
    ; 配置，破坏性大于收益。
    ;
    ; 与 Rust 侧的三处刻意差异（改本函数前请先读 asd-domain/src/validator.rs）：
    ;   1. 长度不匹配只在「时间序列比按键多」时告警 —— 「比按键少」已由
    ;      _ValidateArrayLength / _ValidateSubGroups 输出同义 WARNING，避免重复刷屏；
    ;   2. 超长值只覆盖 (MAX_REASONABLE_INTERVAL_MS, MAX_INTERVAL_MS] —— 超过硬上界
    ;      已由既有 ERROR 拦截，同一数值不再叠一条 WARNING；
    ;   3. 子组下标为 1-based（AHK 惯例），Rust 侧为 0-based，跨栈比对日志需 +1。
    ;
    ; hold / joystick_hold 无「按键数 ↔ 时间序列」配对关系，不适用本检查。
    ; =================================================================
    static _ValidateSuspiciousModeValues(id, mode, config) {
        warnings := []
        series := []

        switch mode {
            case "periodic":
                series.Push(ConfigValidator._MakeSeries("intervals", config, "keys", "intervals"))
            case "sequence":
                series.Push(ConfigValidator._MakeSeries("delays", config, "keys", "delays"))
            case "enhanced_periodic":
                series.Push(ConfigValidator._MakeSeries("intervals", config, "pressKeys", "intervals"))
            case "enhanced_sequence":
                series.Push(ConfigValidator._MakeSeries("pressDelays", config, "pressKeys", "pressDelays"))
            case "joystick_periodic":
                series.Push(ConfigValidator._MakeSeries("intervals", config, "joyKeys", "intervals"))
            case "joystick_sequence":
                series.Push(ConfigValidator._MakeSeries("delays", config, "joyKeys", "delays"))
            case "hybrid":
                series.Push(ConfigValidator._CollectGroupItemSeries(config)*)
            case "enhanced_hybrid":
                series.Push(ConfigValidator._CollectGroupItemSeries(config)*)
            default:
                ; hold / joystick_hold：无配对关系，跳过
        }

        for s in series {
            label := s["label"]
            keysLen := s["keysLen"]
            values := s["values"]

            ; 1) 时间序列比按键多：多余的值永远用不上，多半是多写了一个
            if keysLen > 0 && values.Length > keysLen
                warnings.Push(Map("type", "WARNING", "message", "分组" id " " label " 的按键数 (" keysLen ") 与时间序列长度 (" values.Length ") 不匹配，多余的值将被忽略，请确认配置意图"))

            ; 2) 超长间隔/延迟：多半是单位写错（把秒当毫秒）
            ; 只在「未超过硬上界」的值里取最大值 —— 若直接取全局最大值，
            ; [70000, 90000000] 会因最大值越过硬上界而被整体排除，导致漏报。
            maxVal := ConfigValidator._MaxNumberWithin(values, ConfigValidator.MAX_INTERVAL_MS)
            if IsNumber(maxVal) && maxVal > ConfigValidator.MAX_REASONABLE_INTERVAL_MS
                warnings.Push(Map("type", "WARNING", "message", "分组" id " " label " 中存在超长时间值 " maxVal "ms（上限建议 " ConfigValidator.MAX_REASONABLE_INTERVAL_MS "ms），请确认单位是否为毫秒"))
        }

        return warnings
    }

    ; 组装 (标签, 按键数, 时间序列) 三元组。
    ; 字段缺失或非数组时按键数记 0、序列记空数组 —— 调用方用「两者都非空」门槛自动跳过，
    ; 因为空值已由 _ValidateModeFields 报错，此处不再重复提示。
    static _MakeSeries(label, obj, keysField, valuesField, altKeysField := "") {
        keysLen := 0
        if ConfigValidator._HasField(obj, keysField) {
            k := _GetProp(obj, keysField)
            if k is Array
                keysLen := k.Length
        }
        ; 回退必须是独立的 if，不能写成 else if：子组可能同时存在 pressKeys（空串/非数组）
        ; 与 keys（数组），此时第一个分支虽命中却取不到数组，用 else if 会漏检。
        if keysLen = 0 && altKeysField != "" && ConfigValidator._HasField(obj, altKeysField) {
            k := _GetProp(obj, altKeysField)
            if k is Array
                keysLen := k.Length
        }

        values := []
        if ConfigValidator._HasField(obj, valuesField) {
            v := _GetProp(obj, valuesField)
            if v is Array
                values := v
        }

        return Map("label", label, "keysLen", keysLen, "values", values)
    }

    ; 从 hybrid / enhanced_hybrid 的子组中提取 (标签, 按键数, 时间序列)。
    ; 对应 Rust 侧 collect_group_item_series。
    static _CollectGroupItemSeries(config) {
        series := []
        if !ConfigValidator._HasField(config, "groups")
            return series
        groups := _GetProp(config, "groups")
        if !(groups is Array)
            return series

        for i, grp in groups {
            grpType := ""
            if grp is Map && grp.Has("type")
                grpType := grp["type"]
            else if IsObject(grp) && HasProp(grp, "type")
                grpType := grp.type

            if grpType = "periodic"
                series.Push(ConfigValidator._MakeSeries("groups[" i "].intervals", grp, "pressKeys", "intervals", "keys"))
            else if grpType = "sequence"
                series.Push(ConfigValidator._MakeSeries("groups[" i "].delays", grp, "pressKeys", "delays", "keys"))
        }
        return series
    }

    ; 返回数组中「不超过 ceiling」的最大数值；无符合条件的元素时返回 ""
    ; （调用方用 IsNumber 判定结果）。非数值元素直接跳过。
    static _MaxNumberWithin(arr, ceiling) {
        found := false
        maxVal := 0
        for v in arr {
            if !IsNumber(v)
                continue
            n := Number(v)
            if n > ceiling
                continue
            if !found || n > maxVal {
                maxVal := n
                found := true
            }
        }
        return found ? maxVal : ""
    }

    ; =================================================================
    ; 按级别筛选校验结果（BUG-6 附带修复）
    ;
    ; Validate() 返回的是 ERROR 与 WARNING 混合的数组 —— 子组缺失 intervals/delays、
    ; holdTriggers 非 0/1、以及本次新增的可疑值告警，都会产出 WARNING。
    ; 历史上多处调用点直接用 `errors.Length > 0` 判定失败，导致「仅含 WARNING 的合法配置」
    ; 被拒绝导入或保存。判定是否致命**必须只筛 ERROR**，且统一走本函数，
    ; 避免各调用点手写循环时走偏。
    ;
    ; 兼容两种元素形态：Map（生产路径）与带 type 属性的 Object（测试/历史路径）。
    ; =================================================================
    static FilterByType(errors, typeName) {
        result := []
        if !(errors is Array)
            return result
        for e in errors {
            eType := ""
            if e is Map {
                if e.Has("type")
                    eType := e["type"]
            } else if IsObject(e) && HasProp(e, "type")
                eType := e.type
            if eType = typeName
                result.Push(e)
        }
        return result
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
                else if !IsObject(val) && !ConfigValidator._IsValidHotkeyFormat(String(val))
                    ; I18: 控制热键非空时追加格式校验，非法格式升级为 ERROR
                    errors.Push(Map("type", "ERROR", "message", "控制热键 " action " 格式无效: " String(val)))
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
                        ; M19: 数值上限检查
                        if IsNumber(vv) && Number(vv) > ConfigValidator.MAX_INTERVAL_MS
                            errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i " intervals[" vi "]=" vv " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
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
                        ; M19: 数值上限检查
                        if IsNumber(vv) && Number(vv) > ConfigValidator.MAX_INTERVAL_MS
                            errors.Push(Map("type", "ERROR", "message", "分组" id "子组" i " delays[" vi "]=" vv " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
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
                ; M19: 数值上限检查，防止超大数值导致定时器间隔错误
                if IsNumber(v) && Number(v) > ConfigValidator.MAX_INTERVAL_MS
                    errors.Push(Map("type", "ERROR", "message", "分组" id modeName " " valuesField "[" i "] 值 " v " 过大，最大 " ConfigValidator.MAX_INTERVAL_MS "ms(24小时)"))
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
