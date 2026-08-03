#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Persistent(true)

g := Gui("+Resize", "HTML Editor Test")
wb := g.Add("ActiveX", "w560 h680", "Shell.Explorer")
g.OnEvent("Close", (*) => ExitApp())
g.OnEvent("Size", (guiObj, minMax, w, h) => wb.Move(0, 0, w, h))
g.Show("w560 h680")

wb.Navigate("about:blank")
while wb.ReadyState != 4
    Sleep 50

html := "<!DOCTYPE html><html><head><style>body{font-family:'Segoe UI';background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;padding:20px;min-height:100vh;} h1{font-size:24px;} .card{background:rgba(255,255,255,0.12);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.18);border-radius:16px;padding:20px;margin:10px 0;}</style></head><body><h1>HTML Embedding Test</h1><div class='card'><p>If you see this frosted glass card, HTML embedding works!</p><button style='background:rgba(103,126,234,0.5);color:#fff;border:none;border-radius:8px;padding:8px 16px;cursor:pointer;'>Test Button</button></div></body></html>"
wb.Document.Write(html)
wb.Document.Close()
