; =================================================================
; E2E Key Receiver - 捕获按键事件并写入日志文件
; 说明: 创建 GUI 窗口，在窗口活动时捕获所有测试按键的 down/up 事件
;       日志格式: <timestamp_ms>|<key>|<event>
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message "`n", "*"), true))

; =================================================================
; 全局变量
; =================================================================
global g_logFile := ""
global g_editCtrl := ""

; =================================================================
; 主入口
; =================================================================

; 计算日志文件路径（e2e/reports/key_log.txt）
g_logFile := A_ScriptDir "\..\reports\key_log.txt"

; 启动时清空日志文件
if FileExist(g_logFile)
    FileDelete(g_logFile)
FileAppend("", g_logFile, "UTF-8")

; 创建 GUI 窗口
keyGui := Gui()
keyGui.Title := "E2E Key Receiver"
keyGui.Opt("+AlwaysOnTop")
g_editCtrl := keyGui.Add("Edit", "x10 y10 w380 h280", "等待按键...`r`n")
g_editCtrl.Opt("+ReadOnly")

; 显示窗口
keyGui.Show("w400 h300")

; 要捕获的按键列表
keysToCapture := ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z","0","1","2","3","4","5","6","7","8","9","Space","Enter","Shift","Ctrl","Alt","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"]

; 设置热键上下文为当前 GUI 窗口
Hotkey("IfWinActive", "ahk_id " keyGui.Hwnd)

; 注册每个按键的 down 和 up 事件
for index, key in keysToCapture {
    RegisterKeyHotkey(key)
}

; 重置热键上下文，注册全局 Ctrl+Q 退出
Hotkey("IfWinActive")
Hotkey("^q", (*) => ExitApp())

; GUI 关闭事件
keyGui.OnEvent("Close", (*) => ExitApp())

return

; =================================================================
; 函数定义
; =================================================================

; 注册单个按键的 down/up 热键
RegisterKeyHotkey(key) {
    capturedKey := key
    ; 使用 ~ 前缀让按键继续传递给其他应用（不阻止默认行为）
    hotkeyStr := "~" capturedKey
    try {
        Hotkey(hotkeyStr, (*) => LogKeyEvent(capturedKey, "down"))
        Hotkey(hotkeyStr " up", (*) => LogKeyEvent(capturedKey, "up"))
    } catch as e {
        OutputDebug("KeyReceiver: 注册按键失败 " key " - " e.Message)
    }
}

; 记录按键事件到日志文件并更新 GUI 显示
LogKeyEvent(key, event) {
    global g_logFile, g_editCtrl
    timestamp := A_TickCount
    line := timestamp "|" key "|" event "`n"
    try {
        FileAppend(line, g_logFile, "UTF-8")
    } catch as e {
        OutputDebug("KeyReceiver: 写入日志失败 " e.Message)
    }
    ; 更新 Edit 控件显示（避免无限增长）
    try {
        currentText := g_editCtrl.Value
        if StrLen(currentText) > 2000
            currentText := ""
        g_editCtrl.Value := currentText key " (" event ")`r`n"
    } catch {
        ; 忽略显示错误
    }
}
