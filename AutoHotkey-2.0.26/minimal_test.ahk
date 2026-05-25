#Requires AutoHotkey v2.0
#SingleInstance Force

; 注册错误处理回调
OnError(LogError, -1)

; 全局日志文件
global LogFile := A_ScriptDir "\test_simple.log"

; 主程序
Main()

Main() {
    ; 创建日志目录
    if !DirExist(A_ScriptDir)
        DirCreate(A_ScriptDir)
    
    ; 写入测试日志
    FileAppend("测试开始: " A_Now "`n", LogFile, "UTF-8")
    
    ; 触发错误
    result := 1 / 0
    
    ; 这行不会执行
    FileAppend("测试结束`n", LogFile, "UTF-8")
}

; 错误处理函数
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        ; 构建错误信息
        msg := "错误被捕获！`n"
        msg .= "时间: " A_Now "`n"
        msg .= "模式: " Mode "`n"
        
        if IsObject(Thrown) && HasProp(Thrown, "Message")
            msg .= "错误: " Thrown.Message "`n"
        
        ; 写入日志
        FileAppend(msg, LogFile, "UTF-8")
        
        ; 显示消息框
        MsgBox("✓ 错误已捕获并记录到日志！`n`n" msg, "测试成功", "Iconi")
        
    } catch {
        OutputDebug("记录错误失败")
    }
    
    ; 返回 1 抑制错误弹窗
    return 1
}
