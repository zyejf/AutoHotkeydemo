#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; AutoHotkey v2 错误捕获 - 实际使用示例
; =================================================================
; 
; 功能：演示如何在实际项目中使用错误捕获机制
; - 不显示错误弹窗
; - 将错误信息输出到日志文件
; - 支持多种错误类型
;
; 使用方法：
; 1. 将此文件保存为 error_handler.ahk
; 2. 在你的脚本中使用 #Include "error_handler.ahk"
; 3. 或者直接复制相关代码到你的脚本中
;
; =================================================================

; 注册错误处理回调（-1 表示优先调用）
OnError(ErrorHandler, -1)

; 全局配置
global ErrorConfig := Map()
ErrorConfig["LogFile"] := A_ScriptDir "\logs\error.log"
ErrorConfig["MaxLogSize"] := 10485760  ; 10MB
ErrorConfig["DebugMode"] := true
ErrorConfig["ShowNotification"] := true

; =================================================================
; 主程序示例
; =================================================================

Main()

Main() {
    ; 初始化错误处理系统
    InitErrorHandler()
    
    ; 记录程序启动
    LogInfo("程序启动")
    
    try {
        ; 你的主程序逻辑
        ExampleFunction()
        
    } catch as e {
        ; 手动捕获的错误
        ErrorHandler(e, "Exit")
    }
    
    ; 记录程序结束
    LogInfo("程序正常结束")
}

; 示例函数
ExampleFunction() {
    LogInfo("执行示例函数")
    
    ; 这里可以放置你的业务逻辑
    ; 如果发生错误，会被 OnError 自动捕获
    
    ; 示例：故意触发一个错误（取消注释以测试）
    ; result := 1 / 0
}

; =================================================================
; 错误处理系统
; =================================================================

InitErrorHandler() {
    global ErrorConfig
    
    ; 确保日志目录存在
    SplitPath(ErrorConfig["LogFile"], , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
    
    ; 检查日志文件大小
    if FileExist(ErrorConfig["LogFile"]) {
        fileSize := FileGetSize(ErrorConfig["LogFile"])
        if fileSize > ErrorConfig["MaxLogSize"] {
            ; 日志轮转
            RotateLog()
        }
    }
}

; 错误处理回调函数
ErrorHandler(Thrown, Mode) {
    global ErrorConfig
    
    try {
        ; 构建错误信息
        errorMsg := FormatError(Thrown, Mode)
        
        ; 写入日志文件
        FileAppend(errorMsg, ErrorConfig["LogFile"], "UTF-8")
        
        ; 输出到调试器
        if ErrorConfig["DebugMode"]
            OutputDebug(errorMsg)
        
        ; 显示通知（可选）
        if ErrorConfig["ShowNotification"] {
            errMsg := IsObject(Thrown) && HasProp(Thrown, "Message") 
                ? Thrown.Message 
                : String(Thrown)
            
            TrayTip("错误已记录", errMsg, 3, 3)
        }
        
    } catch as e {
        OutputDebug("ErrorHandler: Failed to log error - " e.Message)
    }
    
    ; 返回 1 抑制错误弹窗
    return 1
}

; 格式化错误信息
FormatError(Thrown, Mode) {
    errorMsg := "========================================`n"
    errorMsg .= "Timestamp: " A_Now "`n"
    errorMsg .= "Mode: " Mode "`n"
    
    if IsObject(Thrown) {
        errorMsg .= "Type: " Type(Thrown) "`n"
        
        if HasProp(Thrown, "Message")
            errorMsg .= "Message: " Thrown.Message "`n"
        
        if HasProp(Thrown, "What")
            errorMsg .= "What: " Thrown.What "`n"
        
        if HasProp(Thrown, "File")
            errorMsg .= "File: " Thrown.File "`n"
        
        if HasProp(Thrown, "Line")
            errorMsg .= "Line: " Thrown.Line "`n"
        
        if HasProp(Thrown, "Extra")
            errorMsg .= "Extra: " Thrown.Extra "`n"
        
        if HasProp(Thrown, "Stack")
            errorMsg .= "Stack:`n" Thrown.Stack "`n"
    } else {
        errorMsg .= "Message: " String(Thrown) "`n"
    }
    
    errorMsg .= "========================================`n`n"
    
    return errorMsg
}

; 记录信息日志
LogInfo(message) {
    global ErrorConfig
    
    try {
        logEntry := "[" A_Now "] INFO: " message "`n"
        FileAppend(logEntry, ErrorConfig["LogFile"], "UTF-8")
        
        if ErrorConfig["DebugMode"]
            OutputDebug(logEntry)
            
    } catch {
        OutputDebug("LogInfo: Failed to write log")
    }
}

; 记录警告日志
LogWarning(message) {
    global ErrorConfig
    
    try {
        logEntry := "[" A_Now "] WARNING: " message "`n"
        FileAppend(logEntry, ErrorConfig["LogFile"], "UTF-8")
        
        if ErrorConfig["DebugMode"]
            OutputDebug(logEntry)
            
    } catch {
        OutputDebug("LogWarning: Failed to write log")
    }
}

; 日志轮转
RotateLog() {
    global ErrorConfig
    
    try {
        baseFile := ErrorConfig["LogFile"]
        
        ; 删除最旧的备份
        oldestFile := baseFile ".3"
        if FileExist(oldestFile)
            FileDelete(oldestFile)
        
        ; 轮转备份文件
        if FileExist(baseFile ".2")
            FileMove(baseFile ".2", baseFile ".3", 1)
        
        if FileExist(baseFile ".1")
            FileMove(baseFile ".1", baseFile ".2", 1)
        
        ; 重命名当前日志
        if FileExist(baseFile)
            FileMove(baseFile, baseFile ".1", 1)
        
    } catch as e {
        OutputDebug("RotateLog: Failed - " e.Message)
    }
}

; =================================================================
; 使用说明
; =================================================================
; 
; 1. 基本使用：
;    - 直接运行此脚本，错误会自动捕获并记录
;    - 所有未捕获的错误都会触发 ErrorHandler
;    - 错误信息会写入日志文件，不会显示弹窗
;
; 2. 手动记录日志：
;    LogInfo("程序启动")
;    LogWarning("配置文件不存在")
;
; 3. 手动捕获错误：
;    try {
;        ; 可能出错的代码
;        content := FileRead("config.txt")
;    } catch as e {
;        ErrorHandler(e, "Exit")
;    }
;
; 4. 配置选项：
;    ErrorConfig.LogFile := "自定义日志路径"
;    ErrorConfig.DebugMode := true  ; 输出到调试器
;    ErrorConfig.ShowNotification := true  ; 显示托盘通知
;
; 5. 集成到现有项目：
;    - 将此文件重命名为 error_handler.ahk
;    - 在你的脚本中添加：#Include "error_handler.ahk"
;    - 确保在你的 Main() 函数前调用 InitErrorHandler()
;
; =================================================================
