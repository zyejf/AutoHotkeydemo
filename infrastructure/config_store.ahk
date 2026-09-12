; =================================================================
; 基础设施层 - 配置存储实现
; 版本: 3.0
; 说明: 管理全局配置数据的统一存取
;       集中管理 GroupSettings / CONTROL_HOTKEYS / HoldSettings
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\deepclone.ahk"
#Include "json_logger.ahk"

class ConfigStore {
    static _groupSettings := Map()
    static _controlHotkeys := Map()
    static _holdSettings := Map()
    static _metadata := Map("version", "3.0", "lastModified", "")
    static _allowedMetadataKeys := ["version", "lastModified"]

    ; =================================================================
    ; IConfigStore 接口实现
    ; =================================================================
    static Load() {
        config := Map()
        for mk, mv in this._metadata
            config[mk] := mv
        config["GroupSettings"] := deepclone(this._groupSettings)
        config["CONTROL_HOTKEYS"] := deepclone(this._controlHotkeys)
        config["HoldSettings"] := deepclone(this._holdSettings)
        return config
    }

    static Save(config) {
        if !(config is Map)
            return false

        if config.Has("GroupSettings") {
            ; I15: 深拷贝 GroupSettings，避免外部修改影响内部状态（与 Load 对称）
            this._groupSettings := deepclone(config["GroupSettings"])
            this._RepairEmptyArrays(this._groupSettings)
        }
        if config.Has("CONTROL_HOTKEYS")
            this._controlHotkeys := deepclone(config["CONTROL_HOTKEYS"])
        if config.Has("HoldSettings")
            this._holdSettings := deepclone(config["HoldSettings"])

        for ck, cv in config {
            if ck != "GroupSettings" && ck != "CONTROL_HOTKEYS" && ck != "HoldSettings" {
                isAllowed := false
                for ak in this._allowedMetadataKeys {
                    if ck = ak {
                        isAllowed := true
                        break
                    }
                }
                if isAllowed
                    this._metadata[ck] := cv
            }
        }

        return true
    }

    static Get(key, default := "") {
        switch key {
            case "GroupSettings":
                return deepclone(this._groupSettings)
            case "CONTROL_HOTKEYS":
                return deepclone(this._controlHotkeys)
            case "HoldSettings":
                return deepclone(this._holdSettings)
            default:
                if this._metadata.Has(key)
                    return this._metadata[key]
                return default
        }
    }

    static Set(key, value) {
        switch key {
            case "GroupSettings":
                this._groupSettings := deepclone(value)
                return true
            case "CONTROL_HOTKEYS":
                this._controlHotkeys := deepclone(value)
                return true
            case "HoldSettings":
                this._holdSettings := deepclone(value)
                return true
            default:
                try
                    JSONLogger.Log("WARNING", "ConfigStore.Set: 未知配置键 '" key "'",
                                  Map("module", "ConfigStore"))
                return false
        }
    }

    static Has(key) {
        if key = "GroupSettings" || key = "CONTROL_HOTKEYS" || key = "HoldSettings"
            return true
        return this._metadata.Has(key)
    }

    ; =================================================================
    ; 分组配置操作
    ; =================================================================
    static GetGroupConfig(groupId, default := "") {
        if this._groupSettings.Has(groupId)
            return deepclone(this._groupSettings[groupId])
        return default
    }

    static SetGroupConfig(groupId, config) {
        this._groupSettings[groupId] := config
    }

    static DeleteGroupConfig(groupId) {
        ; I7: 先检查 groupId 是否存在，避免 Map.Delete 对不存在的键抛异常
        if this._groupSettings.Has(groupId)
            this._groupSettings.Delete(groupId)
    }

    static HasGroup(groupId) {
        return this._groupSettings.Has(groupId)
    }

    static GetGroupCount() {
        return this._groupSettings.Count
    }

    ; =================================================================
    ; 控制热键操作
    ; =================================================================
    static GetControlHotkey(action) {
        if this._controlHotkeys.Has(action)
            return this._controlHotkeys[action]
        return ""
    }

    static SetControlHotkey(action, hotkey) {
        this._controlHotkeys[action] := hotkey
    }

    ; =================================================================
    ; 初始化为默认配置
    ; =================================================================
    static InitDefaults() {
        this._groupSettings := ConfigStore._BuildDefaultGroupSettings()
        this._controlHotkeys := ConfigStore._BuildDefaultControlHotkeys()
        this._holdSettings := ConfigStore._BuildDefaultHoldSettings()
        this._metadata := Map("version", "3.0", "lastModified", A_Now)
    }

    static _RepairEmptyArrays(groupSettings) {
        if !(groupSettings is Map)
            return

        ; M7: 数据驱动 — mode → 需修复的顶层字段，消除重复 case 分支
        modeFieldMap := Map(
            "periodic", "keys",
            "sequence", "keys",
            "enhanced_periodic", "pressKeys",
            "enhanced_sequence", "pressKeys",
            "hold", "holdKeys",
            "joystick_periodic", "joyKeys",
            "joystick_sequence", "joyKeys",
            "joystick_hold", "joyKeys"
        )

        for id, config in groupSettings {
            if !(config is Map)
                continue

            mode := config.Has("mode") ? config["mode"] : ""

            ; 简单模式：单字段修复
            if modeFieldMap.Has(mode) {
                ConfigStore._RepairArrayField(config, id, modeFieldMap[mode])
                continue
            }

            ; 混合模式：嵌套子组修复
            if mode = "hybrid" || mode = "enhanced_hybrid" {
                if config.Has("groups") && config["groups"] is Array {
                    defaults := ConfigStore._GetDefaultGroup(id)
                    if defaults is Map && defaults.Has("groups") && defaults["groups"] is Array {
                        for i, grp in config["groups"] {
                            if !(grp is Map)
                                continue
                            ConfigStore._RepairSubgroupField(grp, defaults, i, "pressKeys")
                            ConfigStore._RepairSubgroupField(grp, defaults, i, "keys")
                        }
                    }
                }
            }
        }
    }

    ; M7: 修复顶层空数组字段（从默认配置填充）
    static _RepairArrayField(config, id, field) {
        if config.Has(field) && config[field] is Array && config[field].Length = 0 {
            defaults := ConfigStore._GetDefaultGroup(id)
            if defaults is Map && defaults.Has(field)
                config[field] := defaults[field]
        }
    }

    ; M7: 修复子组空数组字段（从默认配置对应位置填充）
    static _RepairSubgroupField(grp, defaults, idx, field) {
        if grp.Has(field) && grp[field] is Array && grp[field].Length = 0 {
            if idx <= defaults["groups"].Length && defaults["groups"][idx] is Map && defaults["groups"][idx].Has(field)
                grp[field] := defaults["groups"][idx][field]
        }
    }

    static _GetDefaultGroup(id) {
        defaults := ConfigStore._BuildDefaultGroupSettings()
        if defaults.Has(id)
            return defaults[id]
        return ""
    }

    static _BuildDefaultGroupSettings() {
        return Map(
            "1", Map(
                "hotkey", "F1",
                "mode", "enhanced_sequence",
                "pressKeys", ["Space", "4", "RButton"],
                "pressDelays", [50, 50, 50]
            ),
            "2", Map(
                "hotkey", "F2",
                "mode", "sequence",
                "keys", ["1", "2", "3", "q"],
                "delays", [100, 100, 100, 100]
            ),
            "3", Map(
                "hotkey", "F3",
                "mode", "enhanced_periodic",
                "pressKeys", ["space", "1", "2", "3", "RButton", "space"],
                "intervals", [50, 50, 50, 50, 50, 50],
                "holdKeys", ["Shift"],
                "holdMode", "continuous"
            ),
            "4", Map(
                "hotkey", "F4",
                "mode", "enhanced_hybrid",
                "groups", [
                    Map("type", "periodic", "pressKeys", ["Space"], "intervals", [100]),
                    Map("type", "sequence", "pressKeys", ["1", "2", "3", "4", "q"], "delays", [100, 100, 100, 100, 100], "seqInterval", 100)
                ],
                "seqInterval", 100,
                "holdKeys", ["Shift", "Ctrl"],
                "holdMode", "continuous",
                "keyPressDuration", 15
            ),
            "5", Map(
                "hotkey", "F5",
                "mode", "enhanced_periodic",
                "pressKeys", ["5"],
                "intervals", [50],
                "holdKeys", ["Shift"],
                "holdMode", "continuous"
            ),
            "6", Map(
                "hotkey", "F6",
                "mode", "hold",
                "holdKeys", ["RButton"],
                "holdDuration", 700,
                "autoRepeat", false,
                "repeatInterval", 1000
            ),
            "7", Map(
                "hotkey", "Joy1",
                "mode", "joystick_periodic",
                "joyKeys", ["Joy1", "Joy2"],
                "joyIntervals", [100, 100],
                "joySendMethod", "auto",
                "joyKeyDuration", 50
            )
        )
    }

    static _BuildDefaultControlHotkeys() {
        return Map(
            "emergency", "F12",
            "toggleAll", "^1",
            "showStatus", "^0",
            "toggleHoldMode", "^h",
            "releaseAllHolds", "^r"
        )
    }

    static _BuildDefaultHoldSettings() {
        return Map(
            "debounceDelay", 20,
            "checkInterval", 50,
            "allowOverlap", false,
            "pressSpeed", 80,
            "releaseOnEmergency", true
        )
    }
}
