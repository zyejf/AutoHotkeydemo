#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\WebView2\WebView2.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Persistent(true)

global wvc, wv

main := Gui("+Resize", "技能管理器 - WebView2")
main.OnEvent("Close", (*) => ExitApp())
main.OnEvent("Size", OnResize)
main.Show(Format("w{} h{}", 620, 720))

try {
    wvc := WebView2.CreateControllerAsync(main.Hwnd).await2()
    wv := wvc.CoreWebView2

    ahkBridge := {
        SaveConfig: SaveConfig,
        CancelEdit: CancelEdit,
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
        f := FileOpen(configPath, "w", "UTF-8")
        f.Write(jsonStr)
        f.Close()
        return true
    } catch as e {
        return false
    }
}

CancelEdit() {
    main.Hide()
}
