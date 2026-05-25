#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; 注意：此脚本包含故意触发的加载时错误，用于测试
; =================================================================

; 注册运行时错误处理
OnError(LogError, -1)

global LogFile := A_ScriptDir "\runtime_errors.log"

; 初始化日志
if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("=== 运行时错误测试 ===`n`n", LogFile, "UTF-8")

; 测试运行时错误
try {
    result := 1 / 0
} catch as e {
    LogError(e, "Exit")
}

; 下一行会触发加载时错误（语法错误）
; 注意：这行代码在脚本加载时就会被检测到，OnError 无法捕获
result := "abc" + 123

MsgBox("这行不会执行")

LogError(Thrown, Mode) {
    global LogFile
    
    try {
        msg := "错误类型: "
        
        if IsObject(Thrown) {
            if HasBase(Thrown, Error.Prototype)
                msg .= Type(Thrown)
            else
                msg .= "Unknown"
            
            if HasProp(Thrown, "Message")
                msg .= "`n消息: " Thrown.Message
        } else {
            msg .= String(Thrown)
        }
        
        msg .= "`n"
        
        FileAppend(msg, LogFile, "UTF-8")
        
    } catch {
        OutputDebug("Error")
    }
    
    return 1
}
