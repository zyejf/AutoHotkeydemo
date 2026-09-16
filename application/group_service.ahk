; =================================================================
; 应用层 - 分组生命周期管理服务
; 版本: 3.0
; 说明: 封装 SkillManager 的分组增删改查与状态管理
;       协调 domain 层与 infrastructure 层的交互
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../domain/skill_manager.ahk"
#Include "../infrastructure/config_store.ahk"
#Include "../infrastructure/config_validator.ahk"
#Include "../infrastructure/backup_core.ahk"
#Include "../infrastructure/error_handler.ahk"
#Include "../infrastructure/error_system.ahk"
#Include "../infrastructure/utils.ahk"
#Include "../lib/ahk2_lib/deepclone.ahk"
#Include "config_service.ahk"

class GroupService {
    static ConfigStore := ""
    static SkillManager := ""

    ; =================================================================
    ; 查询
    ; =================================================================
    static GetGroup(id) {
        try {
            if !GroupService.SkillManager.Groups.Has(id)
                throw Error("分组不存在: " id)
            return GroupService.SkillManager.Groups[id]
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static GetAllGroups() {
        try {
            return GroupService.SkillManager.Groups
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static GetActiveGroups() {
        try {
            active := Map()
            for id, group in GroupService.SkillManager.Groups {
                if group.active
                    active[id] := group
            }
            return active
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static GetGroupConfig(id) {
        try {
            if !GroupService.ConfigStore.HasGroup(id)
                throw Error("分组配置不存在: " id)
            return GroupService.ConfigStore.GetGroupConfig(id)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 创建
    ; =================================================================
    static CreateGroup(id, config) {
        try {
            errors := ConfigValidator.ValidateGroupOnly(id, config)
            ; 只按 ERROR 拦截：WARNING（可疑配置值、子组缺默认值等）不应阻断创建/更新
            criticalErrors := ConfigValidator.FilterByType(errors, "ERROR")
            if criticalErrors.Length > 0
                throw Error("配置验证失败: " ConfigValidator.GetErrorMessage(criticalErrors[1]))

            effectiveId := id = "" ? GroupService._GenerateGroupId() : id

            if GroupService.ConfigStore.HasGroup(effectiveId)
                throw Error("分组已存在: " effectiveId)

            result := GroupService.SkillManager.AddGroup(effectiveId, config)

            if result {
                GroupService.ConfigStore.SetGroupConfig(effectiveId, config)
                BackupCore.RecordConfigChange(GroupService.ConfigStore.Load())
            } else {
                throw Error("添加分组失败: " effectiveId)
            }

            return Map("success", result, "id", effectiveId)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 更新
    ; =================================================================
    static UpdateGroup(id, config) {
        try {
            errors := ConfigValidator.ValidateGroupOnly(id, config)
            ; 只按 ERROR 拦截：WARNING（可疑配置值、子组缺默认值等）不应阻断创建/更新
            criticalErrors := ConfigValidator.FilterByType(errors, "ERROR")
            if criticalErrors.Length > 0
                throw Error("配置验证失败: " ConfigValidator.GetErrorMessage(criticalErrors[1]))

            if !GroupService.SkillManager.Groups.Has(id)
                throw Error("分组不存在: " id)

            wasActive := GroupService.SkillManager.Groups[id].active
            oldConfigRef := GroupService.ConfigStore.GetGroupConfig(id)
            oldConfig := deepclone(oldConfigRef)

            if !IsObject(oldConfig) {
                ErrorSystem.LogError("UpdateGroup: 无法获取分组 " id " 的旧配置，拒绝更新以防数据丢失", "CRITICAL", A_ThisFunc, A_LineNumber)
                throw Error("无法获取分组 " id " 的旧配置，请检查数据完整性后重试")
            }

            tempId := id . "_update_temp"
            try {
                addResult := GroupService.SkillManager.AddGroup(tempId, config)
                if !addResult
                    throw Error("新配置验证失败: 临时分组 " tempId " 创建失败 (可能是热键冲突)")
            } catch as addErr {
                throw Error("无法验证新配置: " addErr.Message)
            }

            GroupService.SkillManager.DeleteGroup(tempId)

            if wasActive {
                GroupService.SkillManager._StopGroupExecution(id)
                GroupService.SkillManager.Groups[id].active := false
            }

            GroupService.SkillManager.DeleteGroup(id)

            try {
                addResult := GroupService.SkillManager.AddGroup(id, config)
                if !addResult
                    throw Error("添加分组失败: " id " (可能是热键冲突)")
            } catch as addErr {
                ErrorSystem.LogError("UpdateGroup 添加新配置失败，尝试回滚: " addErr.Message, "ERROR", A_ThisFunc, A_LineNumber)
                try {
                    GroupService.SkillManager.AddGroup(id, oldConfig)
                    GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                    if wasActive
                        GroupService.SkillManager.ToggleGroup(id)
                    ErrorSystem.LogError("UpdateGroup 回滚成功: " id, "WARNING", A_ThisFunc, A_LineNumber)
                } catch as rollbackErr {
                    ErrorSystem.LogError("回滚失败! 分组 " id " 已丢失: " rollbackErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                    try {
                        BackupCore.CreateBackup(Map("lostGroup_" id, oldConfig), "rollback_failure")
                    } catch as bkErr {
                        ErrorSystem.LogError("备份丢失配置也失败: " bkErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                    }
                    GroupService.ConfigStore.SetGroupConfig(id, oldConfig)
                }
                throw addErr
            }

            GroupService.ConfigStore.SetGroupConfig(id, config)
            BackupCore.RecordConfigChange(GroupService.ConfigStore.Load())

            if wasActive
                GroupService.SkillManager.ToggleGroup(id)

            return Map("success", true, "id", id)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 删除
    ; =================================================================
    static DeleteGroup(id) {
        try {
            if !GroupService.SkillManager.Groups.Has(id)
                throw Error("分组不存在: " id)

            result := GroupService.SkillManager.DeleteGroup(id)
            GroupService.ConfigStore.DeleteGroupConfig(id)
            BackupCore.RecordConfigChange(GroupService.ConfigStore.Load())

            return Map("success", result)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 导出/导入
    ; =================================================================
    static ExportGroups(filePath) {
        try {
            config := GroupService.ConfigStore.Load()
            return ConfigIO.ExportToFile(filePath, config)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static ImportGroups(filePathOrConfig) {
        try {
            ; T3-08+T6-12: 支持传入已解析的 Map，避免对同一份 JSON 二次解析
            config := filePathOrConfig is Map ? filePathOrConfig : ConfigIO.LoadFromFile(filePathOrConfig)
            errors := ConfigValidator.Validate(config)
            ; 只按 ERROR 拦截：Validate() 会返回 WARNING（可疑配置值、子组缺少 intervals/delays
            ; 等），用 errors.Length > 0 判定会让合法配置无法导入。且 _ReplaceAllConfig 是
            ; 破坏性替换，被 WARNING 误杀的代价远高于放过一条可疑值。
            criticalErrors := ConfigValidator.FilterByType(errors, "ERROR")
            if criticalErrors.Length > 0
                throw Error("导入配置验证失败: " ConfigValidator.GetErrorMessage(criticalErrors[1]))

            GroupService._ReplaceAllConfig(config)
            return Map("success", true, "groupsLoaded", GroupService.ConfigStore.GetGroupCount())
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 内部
    ; =================================================================
    ; 只统计可转成整数的键，非数字 ID 直接跳过（与调用方的容错口径一致）
    static _MaxNumericId(groups, maxSoFar := 0) {
        for id in groups {
            try {
                idNum := Integer(String(id))
                if idNum > maxSoFar
                    maxSoFar := idNum
            } catch {
                continue
            }
        }
        return maxSoFar
    }

    static _GenerateGroupId() {
        try {
            ; 真值源必须与唯一性检查一致：CreateGroup 用 ConfigStore.HasGroup() 判重，
            ; 这里原先只看 SkillManager.Groups —— 两者不同步时（SkillManager 尚未初始化，
            ; 或配置里有分组但还没建实例）会生成已存在的 ID，CreateGroup 立刻抛
            ; 「分组已存在」，新分组永远建不出来。改成取两边并集的最大值。
            maxId := GroupService._MaxNumericId(GroupService.SkillManager.Groups)

            ; ConfigStore 侧单独兜错：拿不到就以 SkillManager 的结果为准，
            ; 不能让「读不到配置」把「新建分组」也一起废掉。
            try {
                storeCfg := GroupService.ConfigStore ? GroupService.ConfigStore.Load() : ""
                if storeCfg is Map && storeCfg.Has("GroupSettings") && storeCfg["GroupSettings"] is Map
                    maxId := GroupService._MaxNumericId(storeCfg["GroupSettings"], maxId)
            } catch {
                ; best-effort：ConfigStore 不可用时退回只看 SkillManager
            }

            return String(maxId + 1)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    static _ReplaceAllConfig(config) {
        beforeBackup := ""
        try {
            beforeBackup := GroupService.ConfigStore.Load()

            ids := []
            for id in GroupService.SkillManager.Groups
                ids.Push(id)
            for id in ids
                GroupService.SkillManager.DeleteGroup(id)

            GroupService.ConfigStore.Save(config)

            GroupService.SkillManager.Init(
                _GetProp(config, "GroupSettings")
            )

            BackupCore.RecordConfigChange(config)
        } catch as e {
            if beforeBackup {
                try {
                    GroupService.ConfigStore.Save(beforeBackup)
                    groupSettings := beforeBackup.Has("GroupSettings") ? beforeBackup["GroupSettings"] : ""
                    if groupSettings && (groupSettings is Map) && groupSettings.Count > 0
                        GroupService.SkillManager.Init(groupSettings)
                } catch as rbErr {
                    ErrorSystem.LogError("导入回滚失败: " rbErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                }
            }
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }
}
