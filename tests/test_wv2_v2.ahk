#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\WebView2\WebView2.ahk"
#Include "..\infrastructure\json_parser.ahk"
#Include "..\infrastructure\json_serializer.ahk"

Persistent(true)

global wvc, wv, mainGui

mainGui := Gui("+Resize", "技能管理器 - WebView2 v2")
mainGui.OnEvent("Close", (*) => ExitApp())
mainGui.OnEvent("Size", OnResize)
mainGui.Show(Format("w{} h{}", 640, 740))

try {
    wvc := WebView2.CreateControllerAsync(mainGui.Hwnd).await2()
    wv := wvc.CoreWebView2

    ahkBridge := {
        SaveConfig: SaveConfig,
        CancelEdit: CancelEdit,
        LoadConfig: LoadConfig,
        LoadGroupConfig: LoadGroupConfig,
        GetGroupList: GetGroupList,
        TestAction: (msg) => MsgBox(msg, "AHK Bridge", "64")
    }
    wv.AddHostObjectToScript("ahk", ahkBridge)

    htmlPath := A_ScriptDir "\..\presentation\editor_ui_v2.html"
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

CancelEdit() {
    mainGui.Hide()
}

LoadConfig() {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if FileExist(configPath) {
            return FileRead(configPath, "UTF-8")
        }
        return "{}"
    } catch as e {
        return "{}"
    }
}

LoadGroupConfig(groupId) {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if !FileExist(configPath) {
            return "{}"
        }
        content := FileRead(configPath, "UTF-8")
        config := JSONParser.Parse(content)
        if config.Has("GroupSettings") && config["GroupSettings"].Has(groupId) {
            groupConfig := config["GroupSettings"][groupId]
            groupConfig["id"] := groupId
            return JSONSerializer.Stringify(groupConfig, 2)
        }
        return "{}"
    } catch as e {
        return "{}"
    }
}

GetGroupList() {
    try {
        configPath := A_ScriptDir "\..\config.json"
        if !FileExist(configPath) {
            return "[]"
        }
        content := FileRead(configPath, "UTF-8")
        config := JSONParser.Parse(content)
        if !config.Has("GroupSettings") {
            return "[]"
        }
        groups := []
        for id, grp in config["GroupSettings"] {
            entry := Map()
            entry["id"] := id
            entry["hotkey"] := grp.Has("hotkey") ? grp["hotkey"] : ""
            entry["mode"] := grp.Has("mode") ? grp["mode"] : ""
            groups.Push(entry)
        }
        return JSONSerializer.Stringify(groups, 2)
    } catch as e {
        return "[]"
    }
}
