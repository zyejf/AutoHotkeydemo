#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Persistent(true)

g := Gui("+Resize", "HTML Test 3")
wb := g.Add("ActiveX", "w560 h680", "Shell.Explorer")
g.OnEvent("Close", (*) => ExitApp())
g.Show("w560 h680")

wb.Navigate("about:blank")
loop 100 {
    if wb.ReadyState = 4
        break
    Sleep 50
}

html := "<html><body style='font-family:Segoe UI;background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;padding:20px;'><h1>Test</h1><p>HTML works!</p></body></html>"
wb.Document.Write(html)
wb.Document.Close()
