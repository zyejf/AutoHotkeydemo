#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\WebView2\WebView2.ahk"
#Include "..\infrastructure\json_parser.ahk"
#Include "..\infrastructure\json_serializer.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Persistent(true)

global wvc, wv, mainGui

mainGui := Gui("+Resize", "技能管理器 v3.0")
mainGui.OnEvent("Close", (*) => ExitApp())
mainGui.OnEvent("Size", OnResize)
mainGui.Show(Format("w{} h{}", 860, 640))

try {
    wvc := WebView2.CreateControllerAsync(mainGui.Hwnd).await2()
    wv := wvc.CoreWebView2

    ahkBridge := {
        SaveConfig: SaveConfig,
        LoadConfig: LoadConfig,
        LoadGroupConfig: LoadGroupConfig,
        GetGroupList: GetGroupList,
        SaveSettings: SaveSettings,
        LoadSettings: LoadSettings,
        EmergencyStop: EmergencyStop,
        ToggleAll: ToggleAll,
        HotReload: HotReload,
        ToggleGroup: ToggleGroup,
        DeleteGroup: DeleteGroup,
        CreateBackup: CreateBackup,
        RestoreBackup: RestoreBackup,
        DeleteBackup: DeleteBackup,
        ListBackups: ListBackups,
        GetDebugInfo: GetDebugInfo,
        TestAction: (msg) => MsgBox(msg, "AHK Bridge", "64")
    }
    wv.AddHostObjectToScript("ahk", ahkBridge)

    htmlPath := A_ScriptDir "\..\presentation\app_ui.html"
    if !FileExist(htmlPath) {
        MsgBox("HTML 文件不存在: " htmlPath, "错误", "16")
        ExitApp()
    }
    htmlContent := FileRead(htmlPath, "UTF-8")
    wv.NavigateToString(htmlContent)
} catch as e {
    MsgBox("WebView2 初始化失败:`n" e.Message "`n`n" e.What, "错误", "16")
    ExitApp()
}

OnResize(guiObj, minMax, width, height) {
    if minMax != -1 {
        try wvc.Fill()
    }
}

SaveConfig(jsonStr) {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if FileExist(configPath) {
            existingContent := FileRead(configPath, "UTF-8")
            existing := JSONParser.Parse(existingContent)
        } else {
            existing := Map()
        }

        groupConfig := JSONParser.Parse(jsonStr)
        groupId := groupConfig.Has("id") ? groupConfig["id"] : "new"

        if !existing.Has("GroupSettings") {
            existing["GroupSettings"] := Map()
        }
        groupSettings := existing["GroupSettings"]
        groupSettings[groupId] := groupConfig

        if groupConfig.Has("id") {
            groupConfig.Delete("id")
        }

        existing["lastModified"] := A_Now

        f := FileOpen(configPath, "w", "UTF-8")
        f.Write(JSONSerializer.Stringify(existing, 4))
        f.Close()
        return true
    } catch as e {
        return false
    }
}

LoadConfig() {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if !FileExist(configPath)
            return "{}"
        content := FileRead(configPath, "UTF-8")
        return content
    } catch as e {
        return "{}"
    }
}

LoadGroupConfig(groupId) {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if !FileExist(configPath)
            return "{}"
        content := FileRead(configPath, "UTF-8")
        config := JSONParser.Parse(content)
        if config.Has("GroupSettings") && config["GroupSettings"].Has(groupId) {
            groupData := config["GroupSettings"][groupId]
            groupData["id"] := groupId
            return JSONSerializer.Stringify(groupData)
        }
        return "{}"
    } catch as e {
        return "{}"
    }
}

GetGroupList() {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if !FileExist(configPath)
            return "[]"
        content := FileRead(configPath, "UTF-8")
        config := JSONParser.Parse(content)
        if !config.Has("GroupSettings")
            return "[]"
        groups := []
        for id, group in config["GroupSettings"] {
            groupObj := Map()
            groupObj["id"] := id
            groupObj["hotkey"] := group.Has("hotkey") ? group["hotkey"] : ""
            groupObj["mode"] := group.Has("mode") ? group["mode"] : "periodic"
            groupObj["active"] := false
            groups.Push(groupObj)
        }
        return JSONSerializer.Stringify(groups)
    } catch as e {
        return "[]"
    }
}

SaveSettings(jsonStr) {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if FileExist(configPath) {
            content := FileRead(configPath, "UTF-8")
            config := JSONParser.Parse(content)
        } else {
            config := Map()
        }
        settings := JSONParser.Parse(jsonStr)
        if settings.Has("CONTROL_HOTKEYS")
            config["CONTROL_HOTKEYS"] := settings["CONTROL_HOTKEYS"]
        if settings.Has("HoldSettings")
            config["HoldSettings"] := settings["HoldSettings"]
        f := FileOpen(configPath, "w", "UTF-8")
        f.Write(JSONSerializer.Stringify(config, 4))
        f.Close()
        return true
    } catch as e {
        return false
    }
}

LoadSettings() {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if !FileExist(configPath)
            return "{}"
        return FileRead(configPath, "UTF-8")
    } catch as e {
        return "{}"
    }
}

EmergencyStop() {
    try {
        return "ok"
    } catch as e {
        return "error"
    }
}

ToggleAll() {
    try {
        return "ok"
    } catch as e {
        return "error"
    }
}

HotReload() {
    try {
        return "ok"
    } catch as e {
        return "error"
    }
}

ToggleGroup(groupId) {
    try {
        return "ok"
    } catch as e {
        return "error"
    }
}

DeleteGroup(groupId) {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if FileExist(configPath) {
            content := FileRead(configPath, "UTF-8")
            config := JSONParser.Parse(content)
            if config.Has("GroupSettings") && config["GroupSettings"].Has(groupId) {
                config["GroupSettings"].Delete(groupId)
                f := FileOpen(configPath, "w", "UTF-8")
                f.Write(JSONSerializer.Stringify(config, 4))
                f.Close()
            }
        }
        return true
    } catch as e {
        return false
    }
}

CreateBackup() {
    try {
        configPath := A_ScriptDir "\..\config.json"
        backupDir := A_ScriptDir "\..\backups"
        if !DirExist(backupDir)
            DirCreate(backupDir)
        timestamp := FormatTime(, "yyyyMMdd_HHmmss")
        backupPath := backupDir "\config_" timestamp ".json"
        if FileExist(configPath)
            FileCopy(configPath, backupPath)
        return backupPath
    } catch as e {
        return ""
    }
}

RestoreBackup(backupName) {
    try {
        backupPath := A_ScriptDir "\..\backups\" backupName
        configPath := A_ScriptDir "\..\config.json"
        if FileExist(backupPath) {
            FileCopy(backupPath, configPath, 1)
            return true
        }
        return false
    } catch as e {
        return false
    }
}

DeleteBackup(backupName) {
    try {
        backupPath := A_ScriptDir "\..\backups\" backupName
        if FileExist(backupPath) {
            FileDelete(backupPath)
            return true
        }
        return false
    } catch as e {
        return false
    }
}

ListBackups() {
    try {
        backupDir := A_ScriptDir "\..\backups"
        if !DirExist(backupDir)
            return "[]"
        backups := []
        loop files backupDir "\*.json" {
            info := Map()
            info["name"] := A_LoopFileName
            info["size"] := A_LoopFileSize
            info["time"] := A_LoopFileTimeModified
            backups.Push(info)
        }
        return JSONSerializer.Stringify(backups)
    } catch as e {
        return "[]"
    }
}

GetDebugInfo() {
    try {
        info := Map()
        info["activeGroups"] := 0
        info["timers"] := 0
        info["errors"] := 0
        info["uptime"] := A_TickCount
        return JSONSerializer.Stringify(info)
    } catch as e {
        return "{}"
    }
}
