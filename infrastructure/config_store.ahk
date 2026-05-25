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
        config["GroupSettings"] := this._groupSettings
        config["CONTROL_HOTKEYS"] := this._controlHotkeys
        config["HoldSettings"] := this._holdSettings
        return config
    }

    static Save(config) {
        if !(config is Map)
            return false

        if config.Has("GroupSettings") {
            this._groupSettings := config["GroupSettings"]
            this._RepairEmptyArrays(this._groupSettings)
        }
        if config.Has("CONTROL_HOTKEYS")
            this._controlHotkeys := config["CONTROL_HOTKEYS"]
        if config.Has("HoldSettings")
            this._holdSettings := config["HoldSettings"]

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
                return this._groupSettings
            case "CONTROL_HOTKEYS":
                return this._controlHotkeys
            case "HoldSettings":
                return this._holdSettings
            default:
                if this._metadata.Has(key)
                    return this._metadata[key]
                return default
        }
    }

    static Set(key, value) {
        switch key {
            case "GroupSettings":
                this._groupSettings := value
                return true
            case "CONTROL_HOTKEYS":
                this._controlHotkeys := value
                return true
            case "HoldSettings":
                this._holdSettings := value
                return true
            default:
                try
                    JSONLogger.Log("WARNING", "ConfigStore.Set: 未知配置键 '" key "'",
                                  Map("module", "ConfigStore"))
                return false
        }
    }

    static Has(key) {
        return key = "GroupSettings" || key = "CONTROL_HOTKEYS" || key = "HoldSettings"
    }

    ; =================================================================
    ; 分组配置操作
    ; =================================================================
    static GetGroupConfig(groupId, default := "") {
        if this._groupSettings.Has(groupId)
            return this._groupSettings[groupId]
        return default
    }

    static SetGroupConfig(groupId, config) {
        this._groupSettings[groupId] := config
    }

    static DeleteGroupConfig(groupId) {
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

        for id, config in groupSettings {
            if !(config is Map)
                continue

            mode := config.Has("mode") ? config["mode"] : ""

            switch mode {
                case "periodic":
                    if config.Has("keys") && config["keys"] is Array && config["keys"].Length = 0 {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("keys")
                            config["keys"] := defaults["keys"]
                    }
                case "sequence":
                    if config.Has("keys") && config["keys"] is Array && config["keys"].Length = 0 {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("keys")
                            config["keys"] := defaults["keys"]
                    }
                case "enhanced_periodic":
                    if config.Has("pressKeys") && config["pressKeys"] is Array && config["pressKeys"].Length = 0 {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("pressKeys")
                            config["pressKeys"] := defaults["pressKeys"]
                    }
                case "enhanced_sequence":
                    if config.Has("pressKeys") && config["pressKeys"] is Array && config["pressKeys"].Length = 0 {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("pressKeys")
                            config["pressKeys"] := defaults["pressKeys"]
                    }
                case "enhanced_hybrid", "hybrid":
                    if config.Has("groups") && config["groups"] is Array {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("groups") && defaults["groups"] is Array {
                            for i, grp in config["groups"] {
                                if !(grp is Map)
                                    continue
                                if grp.Has("pressKeys") && grp["pressKeys"] is Array && grp["pressKeys"].Length = 0 {
                                    if i <= defaults["groups"].Length && defaults["groups"][i] is Map && defaults["groups"][i].Has("pressKeys")
                                        grp["pressKeys"] := defaults["groups"][i]["pressKeys"]
                                }
                                if grp.Has("keys") && grp["keys"] is Array && grp["keys"].Length = 0 {
                                    if i <= defaults["groups"].Length && defaults["groups"][i] is Map && defaults["groups"][i].Has("keys")
                                        grp["keys"] := defaults["groups"][i]["keys"]
                                }
                            }
                        }
                    }
                case "hold":
                    if config.Has("holdKeys") && config["holdKeys"] is Array && config["holdKeys"].Length = 0 {
                        defaults := this._GetDefaultGroup(id)
                        if defaults is Map && defaults.Has("holdKeys")
                            config["holdKeys"] := defaults["holdKeys"]
                    }
            }
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
            )
        )
    }

    static _BuildDefaultControlHotkeys() {
        return Map(
            "emergency", "f12",
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
