#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\WebView2\WebView2.ahk"

Persistent(true)

global wvc, wv

main := Gui("+Resize", "WebView2 HTML 测试")
main.OnEvent("Close", (*) => ExitApp())
main.OnEvent("Size", OnResize)
main.Show(Format("w{} h{}", 620, 720))

try {
    wvc := WebView2.CreateControllerAsync(main.Hwnd).await2()
    wv := wvc.CoreWebView2

    html := "<html><head><style>body{background:#0f0a1e;color:#fff;font-family:Segoe UI,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;}h1{font-size:24px;}</style></head><body><h1>WebView2 工作正常!</h1></body></html>"
    wv.NavigateToString(html)
} catch as e {
    MsgBox("WebView2 初始化失败:`n" e.Message "`n`n" e.Stack, "错误", "16")
    ExitApp()
}

OnResize(guiObj, minMax, width, height) {
    if minMax != -1 {
        try wvc.Fill()
    }
}
