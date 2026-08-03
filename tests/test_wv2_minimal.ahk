#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\lib\ahk2_lib\WebView2\WebView2.ahk"

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

Persistent(true)

try {
    main := Gui("+Resize", "WebView2 最小测试")
    main.OnEvent("Close", (*) => ExitApp())
    main.Show(Format("w{} h{}", 800, 600))

    wvc := WebView2.CreateControllerAsync(main.Hwnd).await2()
    wv := wvc.CoreWebView2
    wv.Navigate("https://autohotkey.com")

    MsgBox("WebView2 加载成功！", "成功", "64")
} catch as e {
    MsgBox("错误: " e.Message "`n" e.Stack, "WebView2 错误", "16")
    ExitApp()
}
