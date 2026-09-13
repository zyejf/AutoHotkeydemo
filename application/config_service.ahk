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

    ; 最近一次配置校验产生的 WARNING（供调试面板展示，见 BUG-6 可观测出口）
    static LastValidationWarnings := []

    ; =================================================================
    ; 加载配置
    ; =================================================================
    static LoadConfig() {
        try {
            config := ConfigIO.LoadFromFile(ConfigService.configPath)
            if IsObject(config) && ConfigService._HasErrorSignal(config)
                ErrorSystem.LogError(ConfigService._GetErrorSignal(config), "CRITICAL", A_ThisFunc, A_LineNumber)
        } catch as e {
            JSONLogger.Log("WARNING", "加载配置失败，使用默认配置: " e.Message,
                          Map("module", "ConfigService"))
            ErrorSystem.LogError(e.Message, "WARNING", A_ThisFunc, A_LineNumber)

            ; M18: FileCopy 添加 catch 块记录 WARNING 日志，不再静默吞掉异常
            try
                FileCopy(ConfigService.configPath, ConfigService.configPath ".bak", 1)
            catch as ex {
                JSONLogger.Log("WARNING", "配置备份文件创建失败: " ex.Message,
                              Map("module", "ConfigService"))
            }

            config := ConfigService._GetDefaultConfig()
            ConfigService._SaveToFile(config)
        }

        try {
            config := ConfigService.MigrateConfig(config)

            errors := ConfigValidator.Validate(config)
            if errors.Length > 0 {
                JSONLogger.Log("WARNING", "配置验证问题 " errors.Length " 个",
                              Map("module", "ConfigService"))
                ConfigService._RecordValidationWarnings(errors, "load")
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
                ConfigService._RecordValidationWarnings(errors, "save")
                hasErrors := false
                for err in errors {
                    if err is Map && err.Has("type") && err["type"] = "ERROR" {
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

            return ConfigIO.ExportToFile(ConfigService.configPath, config)
        } catch as e {
            JSONLogger.Log("ERROR", "保存配置失败: " e.Message,
                          Map("module", "ConfigService"))
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; =================================================================
    ; 记录配置校验产生的 WARNING（BUG-6 可观测出口）
    ;
    ; 历史上调用方只写一句「配置验证问题 N 个」，不含任何具体消息，
    ; 导致 WARNING（可疑配置值、子组缺少 intervals/delays 等）对用户完全不可见 ——
    ; 校验器补了告警也没人看得到。现改为：
    ;   ① 逐条写入 JSONLogger；② 存入 LastValidationWarnings 供调试面板展示。
    ;
    ; 返回 WARNING 条数，便于调用方沿用原有的「记数量」日志。
    ; =================================================================
    static _RecordValidationWarnings(errors, stage) {
        warnings := ConfigValidator.FilterByType(errors, "WARNING")
        ConfigService.LastValidationWarnings := warnings
        for w in warnings
            JSONLogger.Log("WARNING", "配置校验[" stage "] " ConfigValidator.GetErrorMessage(w),
                          Map("module", "ConfigService"))
        return warnings.Length
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

            config := ConfigIO.LoadFromFile(ConfigService.configPath)

            if IsObject(config) && ConfigService._HasErrorSignal(config)
                ErrorSystem.LogError(ConfigService._GetErrorSignal(config), "CRITICAL", A_ThisFunc, A_LineNumber)

            errors := ConfigValidator.Validate(config)
            if errors.Length > 0 {
                JSONLogger.Log("WARNING", "热重载验证问题 " errors.Length " 个",
                              Map("module", "ConfigService"))
                ConfigService._RecordValidationWarnings(errors, "hot-reload")
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
        return ConfigIO.ExportToFile(ConfigService.configPath, config)
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
