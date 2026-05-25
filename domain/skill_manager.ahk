; =================================================================
; 领域层 - SkillManager 分组协调器
; 版本: 3.0
; 说明: 技能管理器核心协调类，管理所有 SkillGroup 的生命周期
;       通过依赖注入使用抽象接口，不依赖任何具体实现
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "interfaces.ahk"
#Include "skill_group.ahk"
#Include "mode_registry.ahk"
#Include "../infrastructure/error_system.ahk"

class SkillManager {
    ; =================================================================
    ; 依赖注入点
    ; =================================================================
    static Logger := ""             ; ILogger 实例
    static Notifier := ""           ; INotifier 实例
    static ConfigStore := ""        ; IConfigStore 实例
    static OnExitCallback := ""     ; 退出回调（由表现层注入）

    ; =================================================================
    ; 系统状态
    ; =================================================================
    static Groups := Map()
    static EmergencyMode := false
    static HoldModeEnabled := true
    static HoldKeyRegistry := Map()
    static _cachedHoldSettings := ""
    static _holdSettingsDirty := true

    static GetTimerCount() {
        return this._timers.Count
    }

    static _GetHoldSettings() {
        if this._holdSettingsDirty {
            this._cachedHoldSettings := this.ConfigStore ? this.ConfigStore.Has("HoldSettings") ? this.ConfigStore.Get("HoldSettings") : "" : ""
            this._holdSettingsDirty := false
        }
        return this._cachedHoldSettings
    }

    static InvalidateHoldSettingsCache() {
        this._holdSettingsDirty := true
    }

    static GetActiveCount() {
        count := 0
        for id, group in SkillManager.Groups {
            if group.active
                count++
        }
        return count
    }

    ; =================================================================
    ; 内部状态
    ; =================================================================
    static _timers := Map()
    static _executionIds := Map()
    static _cleanupTimer := 0
    static _eventHooks := []        ; IEventHook 实例列表
    static _controlHotkeyBindings := Map()

    ; =================================================================
    ; 初始化
    ; =================================================================
    static Init(groupSettings) {
        try {
            ids := []
            for id in this.Groups
                ids.Push(id)
            for id in ids
                this.DeleteGroup(id)

            if groupSettings is Map {
                for id, config in groupSettings
                    this.Groups[id] := SkillGroup(id, config)
            }

            this._BindHotkeys()
            this.InvalidateHoldSettingsCache()

            if this._cleanupTimer
                SetTimer(this._cleanupTimer, 0)
            this._cleanupTimer := () => SkillManager._CleanupOrphanTimers()
            SetTimer(this._cleanupTimer, 30000)

            SkillManager._Notify("技能管理器已启动", "success")
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            throw e
        }
    }

    ; =================================================================
    ; 事件钩子注册
    ; =================================================================
    static RegisterEventHook(hook) {
        try {
            if hook is IEventHook
                this._eventHooks.Push(hook)
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static _DispatchEvent(event, data := "") {
        for hook in this._eventHooks {
            try
                hook.OnEvent(event, data)
            catch as e
                ErrorSystem.LogError("EventHook.OnEvent error: " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 热键绑定
    ; =================================================================
    static _BindHotkeys() {
        for id, group in this.Groups {
            try {
                Hotkey(group.hotkey, ((id) => (*) => this.ToggleGroup(id))(id))
                Hotkey(group.hotkey, "On")
            } catch as e {
                ErrorSystem.LogError("热键绑定失败: " group.hotkey " - " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            }
        }

        this._BindControlHotkeys()
    }

    static _BindControlHotkeys() {
        if !this.ConfigStore || !this.ConfigStore.Has("CONTROL_HOTKEYS")
            return

        for action, oldHk in this._controlHotkeyBindings {
            try {
                Hotkey(oldHk, "Off")
            } catch {
            }
        }
        this._controlHotkeyBindings.Clear()

        ctrlHotkeys := this.ConfigStore.Get("CONTROL_HOTKEYS")
        if !(ctrlHotkeys is Map)
            return

        actions := Map(
            "emergency", (*) => this.Emergency(),
            "toggleAll", (*) => this.ToggleAll(),
            "showStatus", (*) => this.ShowStatus(),
            "toggleHoldMode", (*) => this.ToggleHoldMode(),
            "releaseAllHolds", (*) => this.ReleaseAllHolds()
        )

        for action, callback in actions {
            if ctrlHotkeys.Has(action) {
                hk := ctrlHotkeys[action]
                if hk != "" {
                    try {
                        Hotkey(hk, callback)
                        Hotkey(hk, "On")
                        this._controlHotkeyBindings[action] := hk
                    } catch as e {
                        ErrorSystem.LogError("控制热键绑定失败: " action "=" hk " - " e.Message, "WARNING", A_ThisFunc, A_LineNumber)
                    }
                }
            }
        }
    }

    ; =================================================================
    ; 分组控制
    ; =================================================================
    static ToggleGroup(id) {
        try {
            if this.EmergencyMode {
                SkillManager._Log("DEBUG", "ToggleGroup: 紧急模式已激活，忽略操作 id=" id)
                return
            }

            if !this.Groups.Has(id) {
                SkillManager._Log("ERROR", "ToggleGroup: 分组不存在 id=" id)
                return
            }

            group := this.Groups[id]

            result := group.Toggle()
            if result = -1
                return

            if result {
                this._StartGroupExecution(id)
                this._DispatchEvent("onActivate", Map("groupId", id))
            } else {
                this._StopGroupExecution(id)
                this._DispatchEvent("onDeactivate", Map("groupId", id))
            }

            SkillManager._UpdateBriefInfo()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 删除分组
    ; =================================================================
    static DeleteGroup(id) {
        try {
            if !this.Groups.Has(id)
                return false

            group := this.Groups[id]

            if group.active {
                this._StopGroupExecution(id)
            }

            try {
                group.Dispose()
            } catch as disposeErr {
                SkillManager._Log("WARNING", "Dispose 失败: " disposeErr.Message)
            }

            try {
                Hotkey(group.hotkey, "Off")
            } catch as e {
                SkillManager._Log("WARNING", "注销热键失败: " group.hotkey " - " e.Message)
            }

            this.Groups.Delete(id)
            this._DispatchEvent("onConfigChange", Map("action", "deleteGroup", "groupId", id))

            keysToRemove := []
            for k, groupId in this.HoldKeyRegistry {
                if groupId = id
                    keysToRemove.Push(k)
            }
            for k in keysToRemove
                this.HoldKeyRegistry.Delete(k)

            return true
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; =================================================================
    ; 创建新分组
    ; =================================================================
    static AddGroup(id, config) {
        try {
            if this.Groups.Has(id) {
                SkillManager._Log("ERROR", "AddGroup: 分组已存在 id=" id)
                return false
            }

            try {
                this.Groups[id] := SkillGroup(id, config)
            } catch as sgErr {
                SkillManager._Log("ERROR", "AddGroup: SkillGroup构造失败 id=" id " err=" sgErr.Message)
                return false
            }

            hotkeyStr := _GetProp(config, "hotkey", "")
            if hotkeyStr != "" {
                ctrlHotkeys := this.ConfigStore.Has("CONTROL_HOTKEYS") ? this.ConfigStore.Get("CONTROL_HOTKEYS") : Map()
                if ctrlHotkeys is Map {
                    for action, ctrlHk in ctrlHotkeys {
                        if ctrlHk = hotkeyStr {
                            SkillManager._Notify("警告: 热键 " hotkeyStr " 是控制热键(" action ")，分组热键将覆盖控制热键", "warning")
                            break
                        }
                    }
                }
                try {
                    Hotkey(hotkeyStr, ((id) => (*) => this.ToggleGroup(id))(id))
                    Hotkey(hotkeyStr, "On")
                } catch as hkErr {
                    SkillManager._Log("WARNING", "AddGroup: 热键注册失败 id=" id " hotkey=" hotkeyStr " err=" hkErr.Message)
                    SkillManager._Notify("热键注册失败: " hotkeyStr " 可能被其他程序占用", "error")
                    this.Groups.Delete(id)
                    return false
                }
            }

            this._DispatchEvent("onConfigChange", Map("action", "addGroup", "groupId", id))
            return true
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    ; =================================================================
    ; 执行调度
    ; =================================================================
    static _StartGroupExecution(id) {
        this._StopGroupExecution(id)

        if !this.Groups.Has(id)
            return

        groupId := id
        executionId := A_TickCount . "_" . Random(1, 2147483647)
        this._executionIds[id] := executionId

        executor(gId, execId) {
            try {
                if !SkillManager.Groups.Has(gId)
                    return

                currentId := ""
                try {
                    if SkillManager._executionIds.Has(gId)
                        currentId := SkillManager._executionIds[gId]
                }

                if currentId != execId {
                    return
                }

                if !SkillManager._timers.Has(gId) {
                    SkillManager._StopGroupExecution(gId)
                    return
                }

                grp := SkillManager.Groups[gId]
                if SkillManager.EmergencyMode || !grp.active {
                    SkillManager._StopGroupExecution(gId)
                    SkillManager._DispatchEvent("onDeactivate", Map("groupId", gId))
                    return
                }

                delay := grp.Execute()
                if delay > 0 {
                    try {
                        if !SkillManager._executionIds.Has(gId) || SkillManager._executionIds[gId] != execId
                            return
                    }
                    nextFunc := executor.Bind(gId, execId)
                    SkillManager._timers[gId] := nextFunc
                    SetTimer(nextFunc, -delay)
                } else {
                    if grp.active
                        grp.active := false
                    SkillManager._StopGroupExecution(gId)
                    SkillManager._DispatchEvent("onDeactivate", Map("groupId", gId))
                }
            } catch as e {
                ErrorSystem.LogError("定时器回调异常: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
                SkillManager._StopGroupExecution(gId)
            }
        }

        initialFunc := executor.Bind(groupId, executionId)
        this._timers[id] := initialFunc
        SetTimer(initialFunc, -10)
    }

    static _StopGroupExecution(id) {
        if this._executionIds.Has(id)
            this._executionIds.Delete(id)

        if this._timers.Has(id) {
            timerFunc := this._timers[id]
            try {
                SetTimer(timerFunc, 0)
            } finally {
                this._timers.Delete(id)
            }
        }
        if this.Groups.Has(id) {
            if !this.EmergencyMode
                this.Groups[id]._ReleaseAllKeys()
        }
    }

    ; =================================================================
    ; 长按键管理
    ; =================================================================
    static RegisterHoldKey(key, groupId) {
        holdSettings := SkillManager._GetHoldSettings()
        allowOverlap := IsObject(holdSettings) ? _GetProp(holdSettings, "allowOverlap", false) : false

        if !allowOverlap && this.HoldKeyRegistry.Has(key) {
            existingGroup := this.HoldKeyRegistry[key]
            if existingGroup != groupId {
                SkillManager._Notify("警告: " key " 键已被分组" existingGroup "占用", "warning")
                return false
            }
        }

        this.HoldKeyRegistry[key] := groupId
        return true
    }

    static UnregisterHoldKey(key, groupId) {
        if this.HoldKeyRegistry.Has(key) && this.HoldKeyRegistry[key] = groupId
            this.HoldKeyRegistry.Delete(key)
    }

    static IsKeyAllowed(key, groupId) {
        if !this.HoldKeyRegistry.Has(key)
            return true
        holdSettings := SkillManager._GetHoldSettings()
        allowOverlap := IsObject(holdSettings) ? _GetProp(holdSettings, "allowOverlap", false) : false
        return allowOverlap || this.HoldKeyRegistry[key] = groupId
    }

    ; =================================================================
    ; 紧急停止
    ; =================================================================
    static Emergency() {
        try {
            this.EmergencyMode := true

            for id, group in this.Groups {
                group.active := false
                this._StopGroupExecution(id)
            }

            holdSettings := SkillManager._GetHoldSettings()
            releaseOnEmergency := IsObject(holdSettings) ? _GetProp(holdSettings, "releaseOnEmergency", true) : true
            if releaseOnEmergency {
                for id, group in this.Groups
                    group._ReleaseAllKeys()
            }
            this.HoldKeyRegistry.Clear()

            SkillManager._UpdateBriefInfo()
            this._DispatchEvent("onError", Map("type", "emergency"))
            if SkillManager.HasProp("_resetEmergencyTimer") && SkillManager._resetEmergencyTimer {
                try
                    SetTimer(SkillManager._resetEmergencyTimer, 0)
            }
            resetFn := () => this.ResetEmergency()
            SkillManager._resetEmergencyTimer := resetFn
            SetTimer(resetFn, -3000)
            this._CleanupOrphanTimers()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    static ResetEmergency() {
        try {
            if SkillManager.HasProp("_resetEmergencyTimer") && SkillManager._resetEmergencyTimer {
                try
                    SetTimer(SkillManager._resetEmergencyTimer, 0)
                SkillManager._resetEmergencyTimer := 0
            }
            this.EmergencyMode := false
            SkillManager._UpdateBriefInfo()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 全局开关
    ; =================================================================
    static ToggleAll() {
        try {
            if this.EmergencyMode
                return

            if this.GetActiveCount() > 0 {
                ids := []
                for id in this.Groups
                    ids.Push(id)
                for id in ids {
                    if this.Groups.Has(id)
                        this.Groups[id]._lastToggleTime := 0
                    this.ToggleGroup(id)
                }
                SkillManager._Notify("所有分组已关闭", "info")
                this._CleanupOrphanTimers()
            } else {
                for id in this.Groups {
                    if this.Groups.Has(id)
                        this.Groups[id]._lastToggleTime := 0
                    this.ToggleGroup(id)
                }
                if this.GetActiveCount() > 0
                    SkillManager._Notify(this.GetActiveCount() " 个分组已激活", "success")
                else
                    SkillManager._Notify("没有分组被激活", "warning")
            }

            SkillManager._UpdateBriefInfo()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 长按模式切换
    ; =================================================================
    static ToggleHoldMode() {
        try {
            this.HoldModeEnabled := !this.HoldModeEnabled

            if !this.HoldModeEnabled {
                for id, group in this.Groups {
                    if group.active && group.holdKeys.Length > 0
                        group._ReleaseHoldKeys()
                }
                this.HoldKeyRegistry.Clear()
            }

            SkillManager._Notify("长按功能: " (this.HoldModeEnabled ? "已启用" : "已禁用"),
                                this.HoldModeEnabled ? "success" : "warning")
            SkillManager._UpdateBriefInfo()
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 释放所有长按键
    ; =================================================================
    static ReleaseAllHolds() {
        try {
            for id, group in this.Groups {
                if group.active
                    group._ReleaseHoldKeys()
            }
            this.HoldKeyRegistry.Clear()
            SkillManager._Notify("所有长按键已释放", "info")
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 状态显示
    ; =================================================================
    static ShowStatus() {
        try {
            if this.EmergencyMode {
                SkillManager._Notify("紧急停止模式 | 按热键重新开始", "error")
            } else if this.GetActiveCount() > 0 {
                holdInfo := ""
                for key, groupId in this.HoldKeyRegistry {
                    if holdInfo != ""
                        holdInfo .= ", "
                    holdInfo .= key " (分组" groupId ")"
                }
                if holdInfo != ""
                    SkillManager._Notify("运行中 | " this.GetActiveCount() "个分组 | 长按: " holdInfo, "success")
                else
                    SkillManager._Notify("运行中 | " this.GetActiveCount() "个分组", "success")
            } else {
                SkillManager._Notify("待机 | 按热键开始", "info")
            }
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 清理
    ; =================================================================
    static _CleanupOrphanTimers() {
        keysToRemove := []
        for id, timerFunc in this._timers {
            if !this.Groups.Has(id) || !this.Groups[id].active {
                try {
                    SetTimer(timerFunc, 0)
                }
                keysToRemove.Push(id)
            }
        }
        for id in keysToRemove {
            this._timers.Delete(id)
            if this._executionIds.Has(id)
                this._executionIds.Delete(id)
        }
    }

    static OnExit(*) {
        try {
            if SkillManager._cleanupTimer {
                try
                    SetTimer(SkillManager._cleanupTimer, 0)
                SkillManager._cleanupTimer := 0
            }

            for id, group in SkillManager.Groups
                group._ReleaseAllKeys()

            for id, timerFunc in this._timers {
                try
                    SetTimer(timerFunc, 0)
            }
            this._timers.Clear()
            this._executionIds.Clear()

            for action, hk in this._controlHotkeyBindings {
                try
                    Hotkey(hk, "Off")
            }
            this._controlHotkeyBindings.Clear()

            if SkillManager.OnExitCallback {
                try
                    SkillManager.OnExitCallback()
                catch as exitErr {
                    ErrorSystem.LogError("OnExitCallback 失败: " exitErr.Message, "WARNING", A_ThisFunc, A_LineNumber)
                }
            }

            SkillManager._Notify("系统已关闭", "info")
        } catch as e {
            ErrorSystem.LogError(e.Message, "ERROR", A_ThisFunc, A_LineNumber)
        }
    }

    ; =================================================================
    ; 内部辅助
    ; =================================================================
    static _Log(level, message) {
        if SkillManager.Logger {
            try
                SkillManager.Logger.Log(level, message, Map("module", "SkillManager"))
        }
    }

    static _Notify(message, type := "info") {
        if SkillManager.Notifier {
            try
                SkillManager.Notifier.Notify(message, type)
        }
    }

    static _UpdateBriefInfo() {
        if SkillManager.Notifier {
            try
                SkillManager.Notifier.ShowBriefInfo(this.GetActiveCount(), this.EmergencyMode)
        }
        this._DispatchEvent("onStateChange", Map("activeCount", this.GetActiveCount(), "emergencyMode", this.EmergencyMode, "holdModeEnabled", this.HoldModeEnabled))
    }
}
