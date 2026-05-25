#Requires AutoHotkey v2.0
Persistent(true)
#Include "lib\ahk2_lib\WebView2\WebView2.ahk"
gui := Gui("+Resize", "Test")
gui.Show("w860 h640")
wvc := WebView2.CreateControllerAsync(gui.Hwnd).await2()
wv := wvc.CoreWebView2
html := "<html><body><h1>Test</h1><div id='r'></div></body></html>"
wv.NavigateToString(html)
Sleep(2000)
r := wv.ExecuteScriptAsync("document.getElementById('r').innerText = 'OK'; 'done'").await2()
FileAppend(r, "test_result.txt", "UTF-8")
Sleep(500)
ExitApp(0)
