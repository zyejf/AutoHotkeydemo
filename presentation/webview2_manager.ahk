; =================================================================
; 表现层 - WebView2 管理器（现代 GUI）
; 版本: 1.0
; 说明: 使用 WebView2 渲染现代 HTML/CSS/JS 界面
;       通过 AHK-JS Bridge 连接领域服务
;       替代原生 GUIManager / GroupEditor / GlobalSettingsEditor
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\WebView2\WebView2.ahk"
#Include "..\lib\ahk2_lib\deepclone.ahk"
#Include "..\domain\interfaces.ahk"
#Include "..\domain\key_recorder.ahk"
#Include "..\domain\key_validator.ahk"

class WebView2Manager extends IEventHook {
    static wvc := ""
    static wv := ""
    static mainGui := ""
    static visible := false
    static _updateTimer := 0
    static _eventDebounceTimer := 0
    static _startTick := A_TickCount
    static _lastPushHash := ""

    static Show() {
        _DebugLog("WebView2Manager.Show START")
        try {
            if WebView2Manager.mainGui {
                _DebugLog("WebView2Manager.Show: reusing existing gui")
                WebView2Manager.mainGui.Show()
                WebView2Manager.visible := true
                WebView2Manager._StartAutoUpdate()
                return
            }

            _DebugLog("WebView2Manager.Show: creating gui")
            WebView2Manager.mainGui := Gui("+Resize", "技能管理器 v3.0")
            _DebugLog("WebView2Manager.Show: gui created, setting events")
            WebView2Manager.mainGui.OnEvent("Close", (*) => WebView2Manager._OnClose())
            _DebugLog("WebView2Manager.Show: Close event set")
            WebView2Manager.mainGui.OnEvent("Size", (guiObj, minMax, width, height) => WebView2Manager._OnResize(guiObj, minMax, width, height))
            _DebugLog("WebView2Manager.Show: events set, about to show gui")
            WebView2Manager.mainGui.Show(Format("w{} h{}", 860, 640))
            _DebugLog("WebView2Manager.Show: gui shown, scheduling WebView2 init")

            SetTimer(() => WebView2Manager._InitWebView2(), -50)

        } catch as e {
            ErrorSystem.LogError("WebView2 初始化失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            MsgBox("WebView2 初始化失败:`n" e.Message, "错误", "16")
        }
    }

    static _InitWebView2() {
        _DebugLog("WebView2Manager._InitWebView2 START")
        try {
            EnvSet("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9222")
            wvc := WebView2.CreateControllerAsync(WebView2Manager.mainGui.Hwnd).await2()
            WebView2Manager.wvc := wvc
            WebView2Manager.wv := wvc.CoreWebView2
            _DebugLog("WebView2Manager._InitWebView2: WebView2 created")

            htmlPath := A_ScriptDir "\presentation\app_ui.html"
            if !FileExist(htmlPath) {
                MsgBox("HTML 文件不存在: " htmlPath, "错误", "16")
                return
            }
            fileUrl := "file:///" StrReplace(htmlPath, "\", "/")
            WebView2Manager.wv.add_NavigationCompleted((sender, args) => WebView2Manager._OnNavigationCompleted(sender, args))
            WebView2Manager.wv.Navigate(fileUrl)
            _DebugLog("WebView2Manager._InitWebView2: HTML loaded via Navigate, message handler will be set after navigation completes")

            WebView2Manager.visible := true
            WebView2Manager._StartAutoUpdate()
        } catch as e {
            _DebugLog("WebView2Manager._InitWebView2 ERROR: " e.Message)
            ErrorSystem.LogError("WebView2 初始化失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            MsgBox("WebView2 初始化失败:`n" e.Message, "错误", "16")
        }
    }

    static _OnResize(guiObj, minMax, width, height) {
        if minMax != -1 {
            try WebView2Manager.wvc.Fill()
        }
    }

    static _OnClose(*) {
        WebView2Manager.visible := false
        WebView2Manager._StopAutoUpdate()
        if WebView2Manager._eventDebounceTimer {
            SetTimer(WebView2Manager._eventDebounceTimer, 0)
            WebView2Manager._eventDebounceTimer := 0
        }
        WebView2Manager.mainGui.Hide()
    }

    static _StartAutoUpdate() {
        if WebView2Manager._updateTimer
            return
        updateFn := () => WebView2Manager._PushStateUpdate()
        WebView2Manager._updateTimer := updateFn
        SetTimer(updateFn, 2000)
    }

    static _StopAutoUpdate() {
        if WebView2Manager._updateTimer {
            SetTimer(WebView2Manager._updateTimer, 0)
            WebView2Manager._updateTimer := 0
        }
    }

    static _PushStateUpdate() {
        if !WebView2Manager.visible || !WebView2Manager.wv {
            WebView2Manager._StopAutoUpdate()
            return
        }
        try {
            debugInfo := WebView2Manager._BridgeGetDebugInfo()
            groupList := WebView2Manager._BridgeGetGroupList()
            currentHash := StrLen(debugInfo) + StrLen(groupList)
            if currentHash = WebView2Manager._lastPushHash
                return
            WebView2Manager._lastPushHash := currentHash
            combined := '{"debug":' debugInfo ',"groups":' groupList '}'
            safeCombined := StrReplace(combined, "\", "\\")
            safeCombined := StrReplace(safeCombined, "'", "\'")
            safeCombined := StrReplace(safeCombined, "`n", "\n")
            safeCombined := StrReplace(safeCombined, "`r", "\r")
            safeCombined := StrReplace(safeCombined, "</", "<\/")
            WebView2Manager.wv.ExecuteScriptAsync("if(typeof updateDashboard==='function')updateDashboard('" safeCombined "');")
        } catch as e {
            _DebugLog("_PushStateUpdate error: " e.Message)
        }
    }

    static OnEvent(event, data) {
        switch event {
            case "onActivate", "onDeactivate", "onStateChange", "onConfigChange":
                if WebView2Manager.visible && WebView2Manager.wv {
                    WebView2Manager._lastPushHash := ""
                    if WebView2Manager._eventDebounceTimer {
                        SetTimer(WebView2Manager._eventDebounceTimer, 0)
                        WebView2Manager._eventDebounceTimer := 0
                    }
                    debounceFn := () => WebView2Manager._PushStateUpdate()
                    WebView2Manager._eventDebounceTimer := debounceFn
                    SetTimer(debounceFn, -50)
                }
            case "onError":
                if WebView2Manager.visible && WebView2Manager.wv {
                    WebView2Manager._lastPushHash := ""
                    if WebView2Manager._eventDebounceTimer {
                        SetTimer(WebView2Manager._eventDebounceTimer, 0)
                        WebView2Manager._eventDebounceTimer := 0
                    }
                    debounceFn := () => WebView2Manager._PushStateUpdate()
                    WebView2Manager._eventDebounceTimer := debounceFn
                    SetTimer(debounceFn, -50)
                }
        }
    }

    ; =================================================================
    ; Bridge 诊断
    ; =================================================================

    static _OnNavigationCompleted(sender, args) {
        if (args.IsSuccess) {
            _DebugLog("_OnNavigationCompleted: navigation succeeded, setting up message handler")
            WebView2Manager._SetupWebMessageHandler()
        } else {
            _DebugLog("_OnNavigationCompleted: navigation failed, status=" args.WebErrorStatus)
        }
    }

    static _SetupWebMessageHandler() {
        try {
            _DebugLog("_SetupWebMessageHandler: setting up WebMessageReceived handler")
            WebView2Manager.wv.add_WebMessageReceived((wv, args) => WebView2Manager._OnWebMessageReceived(wv, args))
            _DebugLog("_SetupWebMessageHandler: handler registered, sending init signal to JS")
            WebView2Manager.wv.ExecuteScriptAsync("if(typeof onAhkReady==='function')onAhkReady()")
        } catch as e {
            _DebugLog("_SetupWebMessageHandler error: " e.Message)
        }
    }

    static _OnWebMessageReceived(wv, args) {
        requestId := ""
        try {
            msgJson := args.WebMessageAsJson
            _DebugLog("_OnWebMessageReceived: " SubStr(msgJson, 1, 200))
            msg := JSONParser.Parse(msgJson)
            action := _GetField(msg, "action")
            if action = "" {
                _DebugLog("_OnWebMessageReceived: no action field, ignoring")
                return
            }
            requestId := _GetField(msg, "requestId")
            _DebugLog("_OnWebMessageReceived: action=" action " requestId=" requestId)
            switch action {
                case "GetGroupList":
                    result := WebView2Manager._BridgeGetGroupList()
                    WebView2Manager._SendResponse(requestId, result)
                case "LoadConfig":
                    result := WebView2Manager._BridgeLoadConfig()
                    WebView2Manager._SendResponse(requestId, result)
                case "LoadSettings":
                    result := WebView2Manager._BridgeLoadSettings()
                    WebView2Manager._SendResponse(requestId, result)
                case "EmergencyStop":
                    result := WebView2Manager._BridgeEmergencyStop()
                    WebView2Manager._SendResponse(requestId, result)
                case "ToggleAll":
                    result := WebView2Manager._BridgeToggleAll()
                    WebView2Manager._SendResponse(requestId, result)
                case "HotReload":
                    result := WebView2Manager._BridgeHotReload()
                    WebView2Manager._SendResponse(requestId, result)
                case "ToggleGroup":
                    result := WebView2Manager._BridgeToggleGroup(_GetField(msg, "groupId"))
                    WebView2Manager._SendResponse(requestId, result)
                case "DeleteGroup":
                    result := WebView2Manager._BridgeDeleteGroup(_GetField(msg, "groupId"))
                    WebView2Manager._SendResponse(requestId, result)
                case "SaveConfig":
                    result := WebView2Manager._BridgeSaveConfig(_GetField(msg, "data"))
                    WebView2Manager._SendResponse(requestId, result)
                case "SaveSettings":
                    result := WebView2Manager._BridgeSaveSettings(_GetField(msg, "data"))
                    WebView2Manager._SendResponse(requestId, result)
                case "LoadGroupConfig":
                    result := WebView2Manager._BridgeLoadGroupConfig(_GetField(msg, "groupId"))
                    WebView2Manager._SendResponse(requestId, result)
                case "ListBackups":
                    result := WebView2Manager._BridgeListBackups()
                    WebView2Manager._SendResponse(requestId, result)
                case "CreateBackup":
                    result := WebView2Manager._BridgeCreateBackup()
                    WebView2Manager._SendResponse(requestId, result)
                case "RestoreBackup":
                    result := WebView2Manager._BridgeRestoreBackup(_GetField(msg, "backupName"))
                    WebView2Manager._SendResponse(requestId, result)
                case "DeleteBackup":
                    result := WebView2Manager._BridgeDeleteBackup(_GetField(msg, "backupName"))
                    WebView2Manager._SendResponse(requestId, result)
                case "GetDebugInfo":
                    result := WebView2Manager._BridgeGetDebugInfo()
                    WebView2Manager._SendResponse(requestId, result)
                case "StartRecording":
                    result := WebView2Manager._BridgeStartRecording()
                    WebView2Manager._SendResponse(requestId, result)
                case "StopRecording":
                    result := WebView2Manager._BridgeStopRecording()
                    WebView2Manager._SendResponse(requestId, result)
                case "PauseRecording":
                    result := WebView2Manager._BridgePauseRecording()
                    WebView2Manager._SendResponse(requestId, result)
                case "ResumeRecording":
                    result := WebView2Manager._BridgeResumeRecording()
                    WebView2Manager._SendResponse(requestId, result)
                case "StartValidation":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeStartValidation(_GetField(data, "groupId"))
                    WebView2Manager._SendResponse(requestId, result)
                case "StopValidation":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeStopValidation(_GetField(data, "groupId"))
                    WebView2Manager._SendResponse(requestId, result)
                case "ExportRecording":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeExportRecording(_GetField(data, "mode"), _GetField(data, "keyPressDuration"))
                    WebView2Manager._SendResponse(requestId, result)
                case "GetGroupListForValidation":
                    result := WebView2Manager._BridgeGetGroupListForValidation()
                    WebView2Manager._SendResponse(requestId, result)
                case "GetGroupDetail":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeGetGroupDetail(_GetField(data, "groupId"))
                    WebView2Manager._SendResponse(requestId, result)
                case "ReorderGroups":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeReorderGroups(data)
                    WebView2Manager._SendResponse(requestId, result)
                case "ImportRecording":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeImportRecording(_GetField(data, "groupId"), _GetField(data, "name"), _GetField(data, "mode"), _GetField(data, "config"))
                    WebView2Manager._SendResponse(requestId, result)
                case "ExportConfig":
                    result := WebView2Manager._BridgeExportConfig()
                    WebView2Manager._SendResponse(requestId, result)
                case "ImportConfig":
                    result := WebView2Manager._BridgeImportConfig(_GetField(msg, "data"))
                    WebView2Manager._SendResponse(requestId, result)
                case "BatchToggleGroups":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeBatchToggleGroups(data)
                    WebView2Manager._SendResponse(requestId, result)
                case "BatchDeleteGroups":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeBatchDeleteGroups(data)
                    WebView2Manager._SendResponse(requestId, result)
                case "GetBackupList":
                    result := WebView2Manager._BridgeGetBackupList()
                    WebView2Manager._SendResponse(requestId, result)
                case "CompareConfigs":
                    data := _GetField(msg, "data")
                    result := WebView2Manager._BridgeCompareConfigs(data)
                    WebView2Manager._SendResponse(requestId, result)
                default:
                    _DebugLog("_OnWebMessageReceived: unknown action=" action)
                    if requestId != ""
                        WebView2Manager._SendResponse(requestId, String(JSONSerializer.Stringify(Map("error", true, "message", "Unknown action: " action))))
            }
        } catch as e {
            _DebugLog("_OnWebMessageReceived error: " e.Message)
            if requestId != ""
                WebView2Manager._SendResponse(requestId, String(JSONSerializer.Stringify(Map("error", true, "message", e.Message))))
        }
    }

    static _SendResponse(requestId, result) {
        try {
            if requestId = "" {
                _DebugLog("_SendResponse: no requestId, skip")
                return
            }
            responseObj := Map()
            responseObj["requestId"] := requestId
            if result is Integer {
                responseObj["result"] := result
            } else if result is Float {
                responseObj["result"] := result
            } else if Type(result) = "String" {
                isJson := InStr(result, "{") = 1 || InStr(result, "[") = 1
                if isJson {
                    try {
                        parsed := JSONParser.Parse(result)
                        responseObj["result"] := parsed
                    } catch {
                        responseObj["result"] := result
                    }
                } else if result = "true" {
                    responseObj["result"] := true
                } else if result = "false" {
                    responseObj["result"] := false
                } else if IsNumber(result) {
                    responseObj["result"] := Number(result)
                } else {
                    responseObj["result"] := result
                }
            } else if Type(result) = "Boolean" || result = true || result = false {
                responseObj["result"] := !!result
            } else if IsObject(result) {
                responseObj["result"] := result
            } else {
                responseObj["result"] := String(result)
            }
            response := JSONSerializer.Stringify(responseObj)
            _DebugLog("_SendResponse: " SubStr(response, 1, 300))
            WebView2Manager.wv.PostWebMessageAsJson(response)
        } catch as e {
            _DebugLog("_SendResponse error: " e.Message)
        }
    }

    ; =================================================================
    ; AHK-JS Bridge 方法 — 连接实际领域服务
    ; =================================================================

    static _BridgeSaveConfig(jsonStr) {
        try {
            _DebugLog("_BridgeSaveConfig called: " (IsObject(jsonStr) ? "[object]" : SubStr(jsonStr, 1, 100)))
            if jsonStr is Map
                groupConfig := jsonStr
            else
                groupConfig := JSONParser.Parse(jsonStr)
            groupId := _GetField(groupConfig, "id")

            if groupId = "" {
                groupId := GroupService._GenerateGroupId()
            }

            groupName := ""
            if groupConfig is Map {
                if groupConfig.Has("name") {
                    groupName := groupConfig["name"]
                }
                if groupConfig.Has("id")
                    groupConfig.Delete("id")
            } else if HasProp(groupConfig, "id") {
                if HasProp(groupConfig, "name")
                    groupName := groupConfig.name
                groupConfig.DeleteProp("id")
            }

            if groupName != "" && groupConfig is Map
                groupConfig["name"] := groupName

            isUpdate := SkillManager.Groups.Has(groupId)

            if isUpdate && groupConfig is Map {
                existingCfg := ConfigService.ConfigStore.GetGroupConfig(groupId)
                if existingCfg is Map && existingCfg.Has("order")
                    groupConfig["order"] := existingCfg["order"]
            }

            hotkeyValue := ""
            if groupConfig is Map {
                if groupConfig.Has("hotkey")
                    hotkeyValue := groupConfig["hotkey"]
            } else if HasProp(groupConfig, "hotkey")
                hotkeyValue := groupConfig.hotkey

            if hotkeyValue != "" {
                for existId, existGroup in SkillManager.Groups {
                    if existId = groupId
                        continue
                    if existGroup.hotkey = hotkeyValue {
                        return JSONSerializer.Stringify(Map("error", true, "message", "热键 " hotkeyValue " 已被分组 " existId " 使用，请更换热键"))
                    }
                }
            }

            oldConfigRaw := ConfigService.ConfigStore.GetGroupConfig(groupId)
            oldConfig := deepclone(oldConfigRaw)

            if isUpdate {
                GroupService.UpdateGroup(groupId, groupConfig)
            } else {
                GroupService.CreateGroup(groupId, groupConfig)
            }

            saveResult := ConfigService.SaveConfig()
            if !saveResult {
                if isUpdate && IsObject(oldConfig) {
                    try {
                        GroupService.UpdateGroup(groupId, oldConfig)
                    } catch as rbErr {
                        ErrorSystem.LogError("SaveConfig 失败后回滚也失败: " rbErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                    }
                } else if !isUpdate {
                    try {
                        GroupService.DeleteGroup(groupId)
                    } catch as rbErr {
                        ErrorSystem.LogError("SaveConfig 失败后删除新建分组也失败: " rbErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                    }
                }
                return false
            }
            return true
        } catch as e {
            ErrorSystem.LogError("SaveConfig 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    static _BridgeLoadConfig() {
        try {
            config := ConfigService.ConfigStore.Load()
            return JSONSerializer.Stringify(config)
        } catch as e {
            return "{}"
        }
    }

    static _BridgeLoadGroupConfig(groupId) {
        try {
            _DebugLog("_BridgeLoadGroupConfig called: " groupId)
            if !ConfigService.ConfigStore.HasGroup(groupId)
                return "{}"
            groupConfig := ConfigService.ConfigStore.GetGroupConfig(groupId)
            cloned := deepclone(groupConfig)
            cloned["id"] := groupId
            return JSONSerializer.Stringify(cloned)
        } catch as e {
            return "{}"
        }
    }

    static _SerializeGroupProperties(group, target) {
        props := ["pressKeys", "keys", "holdKeys", "intervals", "delays", "pressDelays",
                  "holdMode", "holdDuration", "autoRepeat", "repeatInterval", "seqInterval"]
        for prop in props
            _CopyProp(group, target, prop)
        if group.HasProp("holdPattern")
            target["holdPattern"] := deepclone(group.holdPattern)
        if group.HasProp("holdTriggers")
            target["holdTriggers"] := deepclone(group.holdTriggers)
    }

    static _BridgeGetGroupList() {
        try {
            _DebugLog("_BridgeGetGroupList called")
            groups := []
            for id, group in SkillManager.Groups {
                groupObj := Map()
                groupObj["id"] := id
                groupObj["name"] := group.name
                groupObj["hotkey"] := group.hotkey
                groupObj["mode"] := group.mode
                groupObj["active"] := group.active
                groupObj["keyPressDuration"] := group.keyPressDuration

                WebView2Manager._SerializeGroupProperties(group, groupObj)

                if HasProp(group, "groups") && group.groups.Length > 0 {
                    subGroups := []
                    for sg in group.groups {
                        sgObj := Map()
                        sgObj["type"] := sg is Map ? (sg.Has("type") ? sg["type"] : "") : (HasProp(sg, "type") ? sg.type : "")
                            _CopyProp(sg, sgObj, "pressKeys")
                            _CopyProp(sg, sgObj, "keys")
                            _CopyProp(sg, sgObj, "holdKeys")
                            _CopyProp(sg, sgObj, "intervals")
                            _CopyProp(sg, sgObj, "delays")
                            _CopyProp(sg, sgObj, "pressDelays")
                            _CopyProp(sg, sgObj, "seqInterval")
                            _CopyProp(sg, sgObj, "holdMode")
                            _CopyProp(sg, sgObj, "holdDuration")
                            _CopyProp(sg, sgObj, "holdPattern")
                            _CopyProp(sg, sgObj, "holdTriggers")
                            _CopyProp(sg, sgObj, "autoRepeat")
                            _CopyProp(sg, sgObj, "repeatInterval")
                        subGroups.Push(sgObj)
                    }
                    groupObj["groups"] := subGroups
                }
                groups.Push(groupObj)
            }
            n := groups.Length
            if n > 1 {
                Loop n - 1 {
                    i := A_Index + 1
                    key := groups[i]
                    j := i - 1
                    keyOrder := HasProp(SkillManager.Groups[key["id"]], "_order") ? SkillManager.Groups[key["id"]]._order : 0
                    while j >= 1 {
                        prevOrder := HasProp(SkillManager.Groups[groups[j]["id"]], "_order") ? SkillManager.Groups[groups[j]["id"]]._order : 0
                        if prevOrder <= keyOrder
                            break
                        groups[j + 1] := groups[j]
                        j--
                    }
                    groups[j + 1] := key
                }
            }
            return JSONSerializer.Stringify(groups)
        } catch as e {
            return "[]"
        }
    }

    static _BridgeSaveSettings(jsonStr) {
        try {
            if jsonStr is Map
                settings := jsonStr
            else
                settings := JSONParser.Parse(jsonStr)
            ch := "", hs := ""
            if settings is Map {
                if settings.Has("CONTROL_HOTKEYS")
                    ch := settings["CONTROL_HOTKEYS"]
                if settings.Has("HoldSettings")
                    hs := settings["HoldSettings"]
            } else {
                if HasProp(settings, "CONTROL_HOTKEYS")
                    ch := settings.CONTROL_HOTKEYS
                if HasProp(settings, "HoldSettings")
                    hs := settings.HoldSettings
            }
            if ch != "" {
                errors := ConfigValidator._ValidateHotkeys(ch)
                if errors.Length > 0 {
                    ErrorSystem.LogError("SaveSettings 验证失败: " ConfigValidator.GetErrorMessage(errors[1]), "ERROR", A_ThisFunc, A_LineNumber)
                    return false
                }
            }
            if hs != "" {
                errors := ConfigValidator._ValidateHoldSettings(hs)
                if errors.Length > 0 {
                    ErrorSystem.LogError("SaveSettings 验证失败: " ConfigValidator.GetErrorMessage(errors[1]), "ERROR", A_ThisFunc, A_LineNumber)
                    return false
                }
            }
            oldCh := ConfigService.ConfigStore.Get("CONTROL_HOTKEYS")
            oldHs := ConfigService.ConfigStore.Get("HoldSettings")
            oldChCopy := deepclone(oldCh)
            oldHsCopy := deepclone(oldHs)
            if ch != ""
                ConfigService.ConfigStore.Set("CONTROL_HOTKEYS", ch)
            if hs != ""
                ConfigService.ConfigStore.Set("HoldSettings", hs)
            saveResult := ConfigService.SaveConfig()
            if !saveResult {
                if ch != ""
                    ConfigService.ConfigStore.Set("CONTROL_HOTKEYS", oldChCopy)
                if hs != ""
                    ConfigService.ConfigStore.Set("HoldSettings", oldHsCopy)
                return false
            }
            if ch != ""
                SkillManager._BindControlHotkeys()
            SkillManager.InvalidateHoldSettingsCache()
            return true
        } catch as e {
            ErrorSystem.LogError("SaveSettings 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    static _BridgeLoadSettings() {
        try {
            config := ConfigService.ConfigStore.Load()
            return JSONSerializer.Stringify(config)
        } catch as e {
            return "{}"
        }
    }

    static _BridgeEmergencyStop() {
        try {
            _DebugLog("_BridgeEmergencyStop called")
            SkillManager.Emergency()
            return "ok"
        } catch as e {
            ErrorSystem.LogError("EmergencyStop 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return "error"
        }
    }

    static _BridgeToggleAll() {
        try {
            SkillManager.ToggleAll()
            return "ok"
        } catch as e {
            ErrorSystem.LogError("ToggleAll 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return "error"
        }
    }

    static _BridgeHotReload() {
        try {
            ConfigService.HotReload()
            return "ok"
        } catch as e {
            ErrorSystem.LogError("HotReload 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return "error"
        }
    }

    static _BridgeToggleGroup(groupId) {
        try {
            if groupId = "" || !SkillManager.Groups.Has(groupId)
                return "error"
            _DebugLog("_BridgeToggleGroup called: " groupId)
            SkillManager.ToggleGroup(groupId)
            return "ok"
        } catch as e {
            ErrorSystem.LogError("ToggleGroup 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return "error"
        }
    }

    static _BridgeDeleteGroup(groupId) {
        try {
            if groupId = "" || !SkillManager.Groups.Has(groupId)
                return "error"
            _DebugLog("_BridgeDeleteGroup called: " groupId)
            oldConfigRaw := ConfigService.ConfigStore.GetGroupConfig(groupId)
            oldConfig := deepclone(oldConfigRaw)
            GroupService.DeleteGroup(groupId)
            if !ConfigService.SaveConfig() {
                try {
                    SkillManager.AddGroup(groupId, oldConfig)
                    ConfigService.ConfigStore.SetGroupConfig(groupId, oldConfig)
                } catch as rbErr {
                    ErrorSystem.LogError("DeleteGroup 保存失败后回滚也失败: " rbErr.Message, "CRITICAL", A_ThisFunc, A_LineNumber)
                }
                return "error"
            }
            return true
        } catch as e {
            ErrorSystem.LogError("DeleteGroup 失败: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return "error"
        }
    }

    static _BridgeCreateBackup() {
        try {
            config := ConfigService.ConfigStore.Load()
            result := BackupCore.CreateBackup(config)
            if result.Has("success") && result["success"]
                return result["file"]
            return ""
        } catch as e {
            return ""
        }
    }

    static _BridgeRestoreBackup(backupName) {
        try {
            if backupName = "" || InStr(backupName, "\") || InStr(backupName, "/") || InStr(backupName, "..")
                return false
            backupPath := BackupCore.backupDir "\" backupName
            result := BackupCore.RestoreBackup(backupPath)
            if result.Has("success") && result["success"] {
                ConfigService.LoadConfig()
                SkillManager._BindControlHotkeys()
                SkillManager.InvalidateHoldSettingsCache()
                return true
            }
            return false
        } catch as e {
            return false
        }
    }

    static _BridgeDeleteBackup(backupName) {
        try {
            if backupName = "" || InStr(backupName, "\") || InStr(backupName, "/") || InStr(backupName, "..")
                return false
            backupPath := BackupCore.backupDir "\" backupName
            return BackupCore.DeleteBackup(backupPath)
        } catch as e {
            return false
        }
    }

    static _BridgeListBackups() {
        try {
            backups := BackupCore.ListBackups()
            result := []
            for bk in backups {
                obj := Map()
                obj["name"] := bk.Has("file") ? bk["file"] : ""
                obj["size"] := bk.Has("size") ? bk["size"] : 0
                obj["time"] := bk.Has("time") ? bk["time"] : ""
                result.Push(obj)
            }
            return JSONSerializer.Stringify(result)
        } catch as e {
            return "[]"
        }
    }

    static _BridgeGetDebugInfo() {
        try {
            info := Map()
            info["activeGroups"] := SkillManager.GetActiveCount()
            info["totalGroups"] := SkillManager.Groups.Count
            info["timers"] := SkillManager.GetTimerCount()
            info["emergencyMode"] := SkillManager.EmergencyMode
            info["holdModeEnabled"] := SkillManager.HoldModeEnabled
            info["uptime"] := A_TickCount - WebView2Manager._startTick
            return JSONSerializer.Stringify(info)
        } catch as e {
            return "{}"
        }
    }

    static _BridgeStartRecording() {
        try {
            if KeyRecorder.IsRecording()
                return 0
            KeyRecorder.Start((evt) => WebView2Manager._PushKeyEvent(evt))
            return 1
        } catch as e {
            _DebugLog("_BridgeStartRecording error: " e.Message)
            return 0
        }
    }

    static _BridgeStopRecording() {
        try {
            if !KeyRecorder.IsRecording()
                return "{}"
            result := KeyRecorder.Stop()
            return JSONSerializer.Stringify(result)
        } catch as e {
            _DebugLog("_BridgeStopRecording error: " e.Message)
            return "{}"
        }
    }

    static _BridgePauseRecording() {
        try {
            if !KeyRecorder.IsRecording() || KeyRecorder.IsPaused()
                return 0
            KeyRecorder.Pause()
            return 1
        } catch as e {
            _DebugLog("_BridgePauseRecording error: " e.Message)
            return 0
        }
    }

    static _BridgeResumeRecording() {
        try {
            if !KeyRecorder.IsRecording() || !KeyRecorder.IsPaused()
                return 0
            KeyRecorder.Resume()
            return 1
        } catch as e {
            _DebugLog("_BridgeResumeRecording error: " e.Message)
            return 0
        }
    }

    static _BridgeStartValidation(groupId) {
        try {
            if KeyValidator.IsActive()
                return 0
            if groupId = ""
                return 0
            if !IsSet(SkillManager) || !SkillManager.Groups.Has(groupId)
                return -1
            if !SkillManager.Groups[groupId].active {
                SkillManager.Groups[groupId]._lastToggleTime := 0
                SkillManager.ToggleGroup(groupId)
                if !SkillManager.Groups[groupId].active
                    return 0
            }
            KeyValidator.Start(groupId, (evt) => WebView2Manager._PushSendEvent(evt))
            return 1
        } catch as e {
            _DebugLog("_BridgeStartValidation error: " e.Message)
            return 0
        }
    }

    static _BridgeStopValidation(groupId) {
        try {
            if groupId != "" && IsSet(SkillManager) && SkillManager.Groups.Has(groupId) {
                try {
                    if SkillManager.Groups[groupId].active
                        SkillManager.ToggleGroup(groupId)
                } catch as e1 {
                    _DebugLog("_BridgeStopValidation: ToggleGroup failed: " e1.Message)
                }
            }
            if !KeyValidator.IsActive()
                return "{}"
            report := KeyValidator.Stop()
            return JSONSerializer.Stringify(report)
        } catch as e {
            _DebugLog("_BridgeStopValidation error: " e.Message)
            try {
                if KeyValidator.IsActive()
                    KeyValidator.Stop()
            } catch {
            }
            return "{}"
        }
    }

    static _BridgeExportRecording(mode, keyPressDuration) {
        try {
            if KeyRecorder.IsRecording()
                return JSONSerializer.Stringify(Map("error", true, "message", "请先停止录制再导出"))
            if mode = ""
                mode := "periodic"
            if keyPressDuration = ""
                keyPressDuration := 15
            else {
                try {
                    keyPressDuration := Integer(keyPressDuration)
                } catch {
                    return JSONSerializer.Stringify(Map("error", true, "message", "按键持续时间必须是数字"))
                }
                if keyPressDuration < 5
                    keyPressDuration := 5
                if keyPressDuration > 100
                    keyPressDuration := 100
            }
            config := KeyRecorder.ExportAsGroupConfig(mode, keyPressDuration)
            return JSONSerializer.Stringify(config)
        } catch as e {
            _DebugLog("_BridgeExportRecording error: " e.Message)
            return "{}"
        }
    }

    static _BridgeGetGroupListForValidation() {
        try {
            items := []
            for id, group in SkillManager.Groups {
                items.Push(Map("id", id, "mode", group.mode, "active", group.active))
            }
            return JSONSerializer.Stringify(items)
        } catch as e {
            _DebugLog("_BridgeGetGroupListForValidation error: " e.Message)
            return "[]"
        }
    }

    static _BridgeReorderGroups(orderData) {
        try {
            if orderData is String {
                try orderData := JSONParser.Parse(orderData)
            }
            if !IsObject(orderData) || orderData.Length = 0
                return false

            oldOrders := Map()
            for existId in SkillManager.Groups {
                oldOrders[existId] := SkillManager.Groups[existId]._order
            }

            newOrder := Map()
            for idx, id in orderData {
                newOrder[id] := idx
            }

            for existId in SkillManager.Groups {
                if !newOrder.Has(existId)
                    newOrder[existId] := newOrder.Count + 1
            }

            for id, orderIdx in newOrder {
                if SkillManager.Groups.Has(id)
                    SkillManager.Groups[id]._order := orderIdx
            }

            saveResult := ConfigService.SaveConfig()
            if !saveResult {
                for id, oldOrderIdx in oldOrders {
                    if SkillManager.Groups.Has(id)
                        SkillManager.Groups[id]._order := oldOrderIdx
                }
                ErrorSystem.LogError("ReorderGroups: SaveConfig failed after reorder", "WARNING", A_ThisFunc, A_LineNumber)
            } else {
                for id, orderIdx in newOrder {
                    if ConfigService.ConfigStore.HasGroup(id) {
                        groupCfg := ConfigService.ConfigStore.GetGroupConfig(id)
                        if groupCfg is Map {
                            groupCfg["order"] := orderIdx
                            ConfigService.ConfigStore.SetGroupConfig(id, groupCfg)
                        }
                    }
                }
            }

            return true
        } catch as e {
            ErrorSystem.LogError("ReorderGroups failed: " e.Message, "ERROR", A_ThisFunc, A_LineNumber)
            return false
        }
    }

    static _BridgeGetGroupDetail(groupId) {
        try {
            if !SkillManager.Groups.Has(groupId)
                return JSONSerializer.Stringify(Map("error", true, "message", "分组不存在"))
            group := SkillManager.Groups[groupId]
            allKeys := []
            if group.HasProp("pressKeys")
                allKeys := group.pressKeys.Clone()
            else if group.HasProp("keys")
                allKeys := group.keys.Clone()
            else if group.HasProp("holdKeys")
                allKeys := group.holdKeys.Clone()
            detail := Map("keys", allKeys, "mode", group.mode)
            detail["name"] := group.name
            if group.HasProp("holdKeys") && group.holdKeys.Length > 0
                detail["holdKeys"] := group.holdKeys.Clone()
            if group.HasProp("keyPressDuration")
                detail["keyPressDuration"] := group.keyPressDuration

            WebView2Manager._SerializeGroupProperties(group, detail)
            if group.HasProp("groups") && group.groups.Length > 0 {
                groupsCopy := []
                for sg in group.groups {
                    sgCopy := deepclone(sg is Map ? sg : Map())
                    if !(sg is Map) && IsObject(sg) {
                        if HasProp(sg, "type")
                            sgCopy["type"] := sg.type
                        if HasProp(sg, "pressKeys")
                            sgCopy["pressKeys"] := deepclone(sg.pressKeys)
                        if HasProp(sg, "keys")
                            sgCopy["keys"] := deepclone(sg.keys)
                        if HasProp(sg, "intervals")
                            sgCopy["intervals"] := deepclone(sg.intervals)
                        if HasProp(sg, "delays")
                            sgCopy["delays"] := deepclone(sg.delays)
                    }
                    groupsCopy.Push(sgCopy)
                }
                detail["groups"] := groupsCopy
            }
            if group.HasProp("seqInterval")
                detail["seqInterval"] := group.seqInterval
            return JSONSerializer.Stringify(detail)
        } catch as e {
            _DebugLog("_BridgeGetGroupDetail error: " e.Message)
            return JSONSerializer.Stringify(Map("error", true, "message", e.Message))
        }
    }

    static _BridgeImportRecording(groupId, name, mode, configJson) {
        try {
            if groupId = ""
                return JSONSerializer.Stringify(Map("ok", false, "message", "分组ID不能为空"))
            if !RegExMatch(groupId, "^[A-Za-z0-9_]+$")
                return JSONSerializer.Stringify(Map("ok", false, "message", "分组ID只能包含字母、数字和下划线"))
            if SkillManager.Groups.Has(groupId)
                return JSONSerializer.Stringify(Map("ok", false, "message", "分组ID已存在"))
            config := JSONParser.Parse(configJson)
            config["hotkey"] := ""
            config["name"] := name != "" ? name : groupId
            if mode != ""
                config["mode"] := mode
            ok := SkillManager.AddGroup(groupId, config)
            if ok {
                if !ConfigService.SaveConfig() {
                    SkillManager.DeleteGroup(groupId)
                    return JSONSerializer.Stringify(Map("ok", false, "message", "保存配置失败，已回滚"))
                }
                return JSONSerializer.Stringify(Map("ok", true, "groupId", groupId))
            }
            return JSONSerializer.Stringify(Map("ok", false, "message", "创建分组失败"))
        } catch as e {
            _DebugLog("_BridgeImportRecording error: " e.Message)
            return JSONSerializer.Stringify(Map("ok", false, "message", e.Message))
        }
    }

    static _BridgeExportConfig() {
        try {
            filePath := A_ScriptDir "\config_export_" StrReplace(StrReplace(A_Now, ":", ""), " ", "_") ".json"
            result := GroupService.ExportGroups(filePath)
            if result
                return JSONSerializer.Stringify(Map("success", true, "path", filePath))
            return JSONSerializer.Stringify(Map("success", false, "error", "导出失败"))
        } catch as e {
            return JSONSerializer.Stringify(Map("success", false, "error", e.Message))
        }
    }

    static _BridgeImportConfig(jsonStr) {
        tempPath := ""
        try {
            tempPath := A_Temp "\ahk_import_" A_Now ".json"
            FileAppend(jsonStr, tempPath)
            result := GroupService.ImportGroups(tempPath)
            try FileDelete(tempPath)
            tempPath := ""
            return JSONSerializer.Stringify(Map("success", true, "groupsLoaded", GroupService.ConfigStore.GetGroupCount()))
        } catch as e {
            if tempPath != ""
                try FileDelete(tempPath)
            return JSONSerializer.Stringify(Map("success", false, "error", e.Message))
        }
    }

    static _BridgeBatchToggleGroups(data) {
        try {
            parsed := data is Map ? data : JSONParser.Parse(String(data))
            ids := parsed.Has("ids") ? parsed["ids"] : []
            activate := parsed.Has("activate") ? parsed["activate"] : true
            success := 0
            skipped := 0
            failed := 0
            for id in ids {
                try {
                    if SkillManager.Groups.Has(id) {
                        if activate && !SkillManager.Groups[id].active {
                            SkillManager.ToggleGroup(id)
                            success += 1
                        } else if !activate && SkillManager.Groups[id].active {
                            SkillManager.ToggleGroup(id)
                            success += 1
                        } else
                            skipped += 1
                    }
                } catch {
                    failed += 1
                }
            }
            return JSONSerializer.Stringify(Map("success", success, "skipped", skipped, "failed", failed))
        } catch as e {
            return JSONSerializer.Stringify(Map("success", 0, "skipped", 0, "failed", 0, "error", e.Message))
        }
    }

    static _BridgeBatchDeleteGroups(data) {
        try {
            parsed := data is Map ? data : JSONParser.Parse(String(data))
            ids := parsed.Has("ids") ? parsed["ids"] : []
            success := 0
            failed := 0
            for id in ids {
                try {
                    SkillManager.DeleteGroup(id)
                    ConfigService.ConfigStore.DeleteGroupConfig(id)
                    success += 1
                } catch {
                    failed += 1
                }
            }
            if success > 0
                ConfigService.SaveConfig()
            BackupCore.RecordConfigChange(ConfigService.ConfigStore.Load())
            return JSONSerializer.Stringify(Map("success", success, "failed", failed))
        } catch as e {
            return JSONSerializer.Stringify(Map("success", 0, "failed", 0, "error", e.Message))
        }
    }

    static _BridgeGetBackupList() {
        try {
            backups := BackupCore.ListBackups()
            result := []
            for b in backups {
                m := Map()
                m["file"] := b.Has("file") ? b["file"] : ""
                m["path"] := b.Has("path") ? b["path"] : ""
                m["time"] := b.Has("time") ? b["time"] : ""
                result.Push(m)
            }
            return JSONSerializer.Stringify(result)
        } catch as e {
            return "[]"
        }
    }

    static _BridgeCompareConfigs(data) {
        try {
            parsed := data is Map ? data : JSONParser.Parse(String(data))
            basePath := parsed.Has("basePath") ? parsed["basePath"] : ""
            targetPath := parsed.Has("targetPath") ? parsed["targetPath"] : ""
            if !basePath || !targetPath
                return JSONSerializer.Stringify(Map("error", "请选择两个配置"))

            if InStr(basePath, "..") || InStr(targetPath, "..")
                return JSONSerializer.Stringify(Map("error", "路径不合法"))

            backupDir := A_ScriptDir "\backups"
            absBase := basePath
            absTarget := targetPath
            if !InStr(absBase, backupDir) || !InStr(absTarget, backupDir)
                return JSONSerializer.Stringify(Map("error", "路径不在备份目录内"))

            if !FileExist(basePath)
                return JSONSerializer.Stringify(Map("error", "基准配置不存在"))
            if !FileExist(targetPath)
                return JSONSerializer.Stringify(Map("error", "目标配置不存在"))

            baseContent := FileRead(basePath)
            targetContent := FileRead(targetPath)
            baseConfig := JSONParser.Parse(baseContent)
            targetConfig := JSONParser.Parse(targetContent)

            diffs := []
            baseGs := baseConfig.Has("GroupSettings") ? baseConfig["GroupSettings"] : Map()
            targetGs := targetConfig.Has("GroupSettings") ? targetConfig["GroupSettings"] : Map()

            allIds := Map()
            for id in baseGs
                allIds[id] := true
            for id in targetGs
                allIds[id] := true

            for id in allIds {
                inBase := baseGs.Has(id)
                inTarget := targetGs.Has(id)
                if !inBase && inTarget {
                    diffs.Push(Map("id", id, "type", "added"))
                    continue
                }
                if inBase && !inTarget {
                    diffs.Push(Map("id", id, "type", "removed"))
                    continue
                }
                bGroup := baseGs[id]
                tGroup := targetGs[id]
                fields := ["mode", "hotkey", "interval", "name", "active"]
                for f in fields {
                    bVal := bGroup.Has(f) ? String(bGroup[f]) : ""
                    tVal := tGroup.Has(f) ? String(tGroup[f]) : ""
                    if bVal != tVal
                        diffs.Push(Map("id", id, "type", "changed", "field", f, "oldValue", bVal, "newValue", tVal))
                }
            }
            return JSONSerializer.Stringify(Map("diffs", diffs))
        } catch as e {
            return JSONSerializer.Stringify(Map("error", e.Message))
        }
    }

    static _PushBridgeEvent(eventType, evt) {
        try {
            if !WebView2Manager.wv
                return
            json := JSONSerializer.Stringify(Map("type", eventType, "data", evt))
            safeJson := StrReplace(json, "\", "\\")
            safeJson := StrReplace(safeJson, "`n", "\n")
            safeJson := StrReplace(safeJson, "`r", "\r")
            safeJson := StrReplace(safeJson, "'", "\'")
            safeJson := StrReplace(safeJson, "</", "<\/")
            WebView2Manager.wv.ExecuteScriptAsync("if(typeof onBridgeEvent==='function')onBridgeEvent('" safeJson "');")
        } catch as e {
            _DebugLog("_PushBridgeEvent error: " e.Message)
        }
    }

    static _PushKeyEvent(evt) {
        WebView2Manager._PushBridgeEvent("keyRecordEvent", evt)
    }

    static _PushSendEvent(evt) {
        WebView2Manager._PushBridgeEvent("keySendEvent", evt)
    }
}

; =================================================================
; 工具函数
; =================================================================

_CopyProp(src, dst, key) {
    try {
        val := ""
        if src is Map {
            if src.Has(key)
                val := src[key]
            else
                return
        } else if IsObject(src) && HasProp(src, key) {
            val := src.%key%
        } else {
            return
        }
        if !(val is String && val = "")
            dst[key] := IsObject(val) ? deepclone(val) : val
    } catch {
    }
}
