#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

Persistent(true)

OnError((e, m) => {
    FileAppend("ERROR: " e.Message "`n", "debug_error.log", "UTF-8")
    return -1
})

try {
    g := Gui("+Resize", "HTML Editor Test")
    wb := g.Add("ActiveX", "w560 h680", "Shell.Explorer")
    g.OnEvent("Close", (*) => ExitApp())
    g.Show("w560 h680")

    wb.Navigate("about:blank")
    while wb.ReadyState != 4
        Sleep 10

    html := "<!DOCTYPE html><html><head><style>body{font-family:Segoe UI;background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;padding:20px;min-height:100vh;}</style></head><body><h1>Test</h1><p>If you see this, HTML embedding works!</p></body></html>"
    wb.Document.Write(html)
    wb.Document.Close()
} catch as e {
    FileAppend("CAUGHT: " e.Message "`n", "debug_error.log", "UTF-8")
}
