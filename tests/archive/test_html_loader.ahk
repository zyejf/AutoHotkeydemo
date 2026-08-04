#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

Persistent(true)

OnError((e, mode) => {
    try {
        FileAppend(Format("ERROR[{}]: {}`n  File: {} Line: {}`n", mode, e.Message, e.File, e.Line), A_ScriptDir "\debug_error.log", "UTF-8")
    }
    return -1
})

g := Gui("+Resize", "编辑分组 - 深色主题")
wb := g.Add("ActiveX", "w560 h680", "Shell.Explorer")
g.OnEvent("Close", (*) => ExitApp())
g.OnEvent("Size", (guiObj, minMax, w, h) => wb.Move(0, 0, w, h))
g.Show("w560 h680")

htmlPath := A_ScriptDir "\..\presentation\editor_ui.html"
if !FileExist(htmlPath) {
    MsgBox("HTML file not found: " htmlPath)
    ExitApp()
}
wb.Navigate(htmlPath)
