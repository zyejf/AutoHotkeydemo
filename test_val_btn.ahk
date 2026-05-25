#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
Persistent(true)
gui := Gui("+Resize", "Test")
gui.Show("w860 h640")
try {
    wvc := WebView2.CreateControllerAsync(gui.Hwnd).await2()
    wv := wvc.CoreWebView2
    htmlPath := A_ScriptDir "\presentation\app_ui.html"
    htmlContent := FileRead(htmlPath, "UTF-8")
    wv.NavigateToString(htmlContent)
    Sleep(4000)
    result := wv.ExecuteScriptAsync("JSON.stringify({btnDisabled: document.querySelector('[data-action=startValidation]') ? document.querySelector('[data-action=startValidation]').disabled : 'N/A', selectOptions: document.getElementById('validateGroupId') ? document.getElementById('validateGroupId').options.length : 0, contentOnclick: !!document.querySelector('.content').onclick, panelDisplay: document.getElementById('panel-validate') ? document.getElementById('panel-validate').style.display : 'N/A'})").await2()
    FileAppend(result, A_ScriptDir "\test_result.txt", "UTF-8")
} catch as e {
    FileAppend("Error: " e.Message, A_ScriptDir "\test_result.txt", "UTF-8")
}
Sleep(500)
ExitApp(0)
