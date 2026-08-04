; =================================================================
; 应用层 - 配置管理服务
; 版本: 3.0
; 说明: 配置文件读写、热重载、回滚恢复
;       协调 domain / infrastructure 层完成配置管理
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/json_parser.ahk"
#Include "../infrastructure/json_serializer.ahk"
#Include "../infrastructure/json_logger.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/migration_logger.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/error_system.ahk"

class ConfigService {
    static configPath := "config.json"
    static ConfigStore := ""
    static SkillManager := ""
    static Notifier := ""

    ; =================================================================
    ; 加载配置
    ; =================================================================
    static LoadConfig() {
        try {
            config := ImportConfigFromFile(ConfigService.configPath)
            if IsObject(config) && ConfigService._HasErrorSignal(config)
                ErrorSystem.LogError(ConfigService._GetErrorSignal(config), "CRITICAL", A_ThisFunc, A_LineNumber)
        } catch as e {
            JSONLogger.Log("WARNING", "加载配置失败，使用默认配置: " e.Message,
                          Map("module", "ConfigService"))
            ErrorSystem.LogError(e.Message, "WARNING", A_ThisFunc, A_LineNumber)

            try FileCopy(ConfigService.configPath, ConfigService.configPath ".bak", 1)

            config := ConfigService._GetDefaultConfig()
            ConfigService._SaveToFile(config)
        }

        try {
            config := ConfigService.MigrateConfig(config)

            errors := ConfigValidator.Validate(config)
            if errors.Length > 0 {
                JSONLogger.Log("WARNING", "配置验证问题 " errors.Length " 个",
                              Map("module", "ConfigService"))
            }

            ConfigService.ConfigStore.Save(config)

            groupSettings := ConfigService.ConfigStore.Get("GroupSettings")
            if groupSettings && (groupSettings is Map) && groupSettings.Count > 0
                ConfigService.SkillManager.Init(groupSettings)

            return Map("success", true, "warnings", errors.Length)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 保存配置
    ; =================================================================
    static SaveConfig(config := "") {
        try {
            if config = ""
                config := ConfigService.ConfigStore.Load()

            config["lastModified"] := A_Now

            errors := ConfigValidator.Validate(config)
            if errors.Length > 0 {
                JSONLogger.Log("WARNING", "保存前配置验证问题 " errors.Length " 个",
                              Map("module", "ConfigService"))
                hasErrors := false
                for e in errors {
                    if e is Map && e.Has("type") && e["type"] = "ERROR" {
                        hasErrors := true
                        break
                    }
                }
                if hasErrors {
                    JSONLogger.Log("ERROR", "配置验证存在严重错误，阻止保存",
                                  Map("module", "ConfigService"))
                    return false
                }
            }

            return ExportConfigToFile(ConfigService.configPath, config)
        } catch as e {
            JSONLogger.Log("ERROR", "保存配置失败: " e.Message,
                          Map("module", "ConfigService"))
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; =================================================================
    ; 等待定时器排空（M6 代码重复消除）
    ; HotReload 与 _Rollback 共用的等待逻辑，带超时保护
    ; =================================================================
    static _WaitForTimersDrain(timeoutMs := 500) {
        waitStart := A_TickCount
        loop {
            try {
                if ConfigService.SkillManager.GetTimerCount() <= 0
                    break
            } catch {
                break
            }
            if (A_TickCount - waitStart) >= timeoutMs
                break
            Sleep(10)
        }
    }

    ; =================================================================
    ; 热重载（带回滚保护）
    ; =================================================================
    static HotReload() {
        beforeBackup := ""
        try {
            if !FileExist(ConfigService.configPath) {
                ConfigService._Notify("配置文件不存在", "error")
                return false
            }

            beforeBackup := ConfigService.ConfigStore.Load()
            BackupCore.CreateBackup(beforeBackup, "pre_reload")
            JSONLogger.Log("DEBUG", "热重载前已创建备份",
                          Map("module", "ConfigService"))

            config := ImportConfigFromFile(ConfigService.configPath)

            if IsObject(config) && ConfigService._HasErrorSignal(config)
                ErrorSystem.LogError(ConfigService._GetErrorSignal(config), "CRITICAL", A_ThisFunc, A_LineNumber)

            errors := ConfigValidator.Validate(config)
            if errors.Length > 0 {
                JSONLogger.Log("WARNING", "热重载验证问题 " errors.Length " 个",
                              Map("module", "ConfigService"))
            }

            ConfigService.SkillManager.Emergency()

            try {
                ConfigService._WaitForTimersDrain()

                ConfigService.ConfigStore.Save(config)

                groupSettings := ConfigService.ConfigStore.Get("GroupSettings")
                if groupSettings && (groupSettings is Map) && groupSettings.Count > 0 {
                    ConfigService.SkillManager.Init(groupSettings)
                    ConfigService._Notify("热重载成功: " groupSettings.Count " 个分组", "success", 3000)
                } else {
                    ids := []
                    for id in ConfigService.SkillManager.Groups
                        ids.Push(id)
                    for id in ids {
                        try
                            ConfigService.SkillManager.DeleteGroup(id)
                    }
                    ConfigService._Notify("热重载完成，但未找到有效分组", "warning", 3000)
                }

                ConfigService.SkillManager.InvalidateHoldSettingsCache()
            } finally {
                ConfigService.SkillManager.ResetEmergency()
            }

            JSONLogger.Log("DEBUG", "热重载成功",
                          Map("module", "ConfigService"))
            return true
        } catch as e {
            JSONLogger.Log("ERROR", "热重载失败，正在回滚: " e.Message,
                          Map("module", "ConfigService"))
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)

            if IsObject(beforeBackup)
                ConfigService._Rollback(beforeBackup)
            ConfigService._Notify("热重载失败，已回滚到之前配置", "error", 5000)
            return false
        }
    }

    ; =================================================================
    ; 回滚
    ; =================================================================
    static _Rollback(config) {
        try {
            ConfigService.SkillManager.Emergency()

            try {
                ConfigService._WaitForTimersDrain()

                ConfigService.ConfigStore.Save(config)

                groupSettings := ConfigService.ConfigStore.Get("GroupSettings")
                if groupSettings && (groupSettings is Map) && groupSettings.Count > 0 {
                    ConfigService.SkillManager.Init(groupSettings)
                } else {
                    ids := []
                    for id in ConfigService.SkillManager.Groups
                        ids.Push(id)
                    for id in ids {
                        try
                            ConfigService.SkillManager.DeleteGroup(id)
                    }
                }

                ConfigService.SkillManager.InvalidateHoldSettingsCache()
            } finally {
                ConfigService.SkillManager.ResetEmergency()
            }

            JSONLogger.Log("DEBUG", "配置已回滚",
                          Map("module", "ConfigService"))
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 格式迁移（清理旧格式）
    ; =================================================================
    static MigrateConfig(config) {
        try {
            if !(config is Map)
                return config

            if config.Has("version") && config["version"] = "3.0"
                return config

            gs := config.Has("GroupSettings") ? config["GroupSettings"] : Map()
            if !(gs is Map)
                return config

            oldVersion := config.Has("version") ? config["version"] : "unknown"

            migrated := Map()
            for id, groupConfig in gs {
                migratedConfig := ConfigService._MigrateGroup(groupConfig, id, oldVersion)
                if migratedConfig
                    migrated[id] := migratedConfig
            }

            if migrated.Count > 0
                config["GroupSettings"] := migrated

            config["version"] := "3.0"
            MigrationLogger.Flush()

            return config
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static _MigrateGroup(config, groupId := "", oldVersion := "unknown") {
        try {
            if !(config is Map || IsObject(config))
                return config

            mode := _GetProp(config, "mode", "")
            result := config is Map ? config.Clone() : ConfigService._ObjectToMap(config)

            if mode = "periodic" || mode = "sequence" {
                legacyKeys := _GetProp(result, "keys", "")
                if legacyKeys && !result.Has("pressKeys") {
                    MigrationLogger.Log(oldVersion, "3.0", groupId, "keys->pressKeys", legacyKeys, legacyKeys)
                    result["pressKeys"] := legacyKeys
                }
                legacyDelays := _GetProp(result, "delays", "")
                if legacyDelays && !result.Has("pressDelays") {
                    MigrationLogger.Log(oldVersion, "3.0", groupId, "delays->pressDelays", legacyDelays, legacyDelays)
                    result["pressDelays"] := legacyDelays
                }
            }

            if mode = "hybrid" || mode = "enhanced_hybrid" {
                groups := _GetProp(result, "groups", "")
                if groups is Array {
                    for i, grp in groups {
                        if grp is Map {
                            if grp.Has("keys") && !grp.Has("pressKeys") {
                                MigrationLogger.Log(oldVersion, "3.0", groupId, "subgroup.keys->pressKeys", grp["keys"], grp["keys"])
                                grp["pressKeys"] := grp["keys"]
                            }
                        } else if IsObject(grp) && HasProp(grp, "keys") && !HasProp(grp, "pressKeys") {
                            MigrationLogger.Log(oldVersion, "3.0", groupId, "subgroup.keys->pressKeys", grp.keys, grp.keys)
                            grp.pressKeys := grp.keys
                        }
                    }
                }
            }

            legacyFields := ["repeatKey", "repeatMode", "type"]
            for field in legacyFields {
                if result.Has(field) {
                    MigrationLogger.Log(oldVersion, "3.0", groupId, "remove-" field, result[field], "")
                    result.Delete(field)
                }
            }

            return result
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static _ObjectToMap(obj) {
        try {
            m := Map()
            for key, value in obj.OwnProps()
                m[key] := value
            return m
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 默认配置
    ; =================================================================
    static _GetDefaultConfig() {
        try {
            return Map(
                "version", "3.0",
                "lastModified", A_Now,
                "GroupSettings", Map(
                    "1", Map("hotkey", "F1", "mode", "enhanced_sequence",
                             "pressKeys", ["Space", "4", "RButton"],
                             "pressDelays", [50, 50, 50])
                ),
                "CONTROL_HOTKEYS", Map(
                    "emergency", "F12", "toggleAll", "^1", "showStatus", "^0",
                    "toggleHoldMode", "^h", "releaseAllHolds", "^r"
                ),
                "HoldSettings", Map(
                    "debounceDelay", 20, "checkInterval", 50,
                    "allowOverlap", false, "pressSpeed", 80,
                    "releaseOnEmergency", true
                )
            )
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 配置加载/存储辅助
    ; =================================================================
    static _SaveToFile(config) {
        return ExportConfigToFile(ConfigService.configPath, config)
    }

    static _Notify(message, type := "info", duration := 0) {
        try {
            if ConfigService.Notifier {
                try
                    ConfigService.Notifier.Notify(message, type, duration)
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _HasErrorSignal(config) {
        if config is Map
            return config.Has("_ERROR_SIGNAL")
        if IsObject(config) && HasProp(config, "_ERROR_SIGNAL")
            return true
        return false
    }

    static _GetErrorSignal(config) {
        if config is Map && config.Has("_ERROR_SIGNAL")
            return config["_ERROR_SIGNAL"]
        if IsObject(config) && HasProp(config, "_ERROR_SIGNAL")
            return config._ERROR_SIGNAL
        return ""
    }
}

; =================================================================
; 通用 IO 函数（委托基础设施层 ConfigIO，保持向后兼容）
; 修复 I6: 配置 IO 逻辑已下沉到 infrastructure/config_io.ahk
; =================================================================

ImportConfigFromFile(filePath) {
    return ConfigIO.LoadFromFile(filePath)
}

ExportConfigToFile(filePath, config) {
    return ConfigIO.ExportToFile(filePath, config)
}
