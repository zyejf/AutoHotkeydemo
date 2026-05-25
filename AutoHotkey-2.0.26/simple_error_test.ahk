#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; 简单测试：验证 OnError 抑制错误弹窗
; =================================================================

; 注册错误处理回调
OnError(LogError, -1)

global LogFile := A_ScriptDir "\logs\simple_error_test.log"

; 初始化日志
if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("=== 错误捕获测试 ===`n", LogFile, "UTF-8")
FileAppend("时间: " A_Now "`n`n", LogFile, "UTF-8")

; 故意触发一个未捕获的错误
; 如果 OnError 工作正常，应该：
; 1. 不会显示错误弹窗
; 2. 错误信息会写入日志
; 3. 显示自定义消息框

result := 1 / 0

; 这行代码不会执行，因为上面的错误会导致线程退出
FileAppend("这行不应该出现`n", LogFile, "UTF-8")

LogError(Thrown, Mode) {
    global LogFile
    
    try {
        errorMsg := "错误被捕获！`n"
        errorMsg .= "时间: " A_Now "`n"
        errorMsg .= "模式: " Mode "`n"
        
        if IsObject(Thrown) && HasProp(Thrown, "Message")
            errorMsg .= "错误: " Thrown.Message "`n"
        else
            errorMsg .= "错误: " String(Thrown) "`n"
        
        FileAppend(errorMsg "`n", LogFile, "UTF-8")
        
        ; 显示自定义消息框（替代错误弹窗）
        MsgBox("✓ 错误已被捕获并记录到日志！`n`n错误信息: " (IsObject(Thrown) && HasProp(Thrown, "Message") ? Thrown.Message : String(Thrown)) "`n`n日志文件: " LogFile, "测试成功", "Iconi")
        
    } catch {
        OutputDebug("记录错误失败")
    }
    
    ; 返回 1 抑制默认错误弹窗
    return 1
}
