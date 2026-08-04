#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Persistent(true)

g := Gui("+Resize", "编辑分组 - 深色主题")
wb := g.Add("ActiveX", "w560 h680", "Shell.Explorer")
g.OnEvent("Close", (*) => ExitApp())
g.OnEvent("Size", (guiObj, minMax, w, h) => wb.Move(0, 0, w, h))
g.Show("w560 h680")

htmlPath := A_ScriptDir "\..\presentation\editor_ui.html"
wb.Navigate(htmlPath)
