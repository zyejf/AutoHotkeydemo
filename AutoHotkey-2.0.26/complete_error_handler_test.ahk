#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; =================================================================
; 完整的错误处理方案
; 同时处理加载时和运行时错误
; =================================================================

; 配置错误日志
global ErrorLogFile := A_ScriptDir "\logs\complete_error_test.log"
global DebugMode := true

; 注册错误处理回调
OnError(HandleRuntimeError, -1)

; =================================================================
; 运行时错误处理
; =================================================================
HandleRuntimeError(Thrown, Mode) {
    global ErrorLogFile, DebugMode
    
    try {
        ; 构建详细的错误报告
        errorReport := FormatErrorReport(Thrown, Mode)
        
        ; 写入日志文件
        FileAppend(errorReport, ErrorLogFile, "UTF-8")
        
        ; 调试模式下输出到调试器
        if DebugMode
            OutputDebug(errorReport)
        
        ; 显示通知（测试用）
        MsgBox("✓ 错误已被捕获并记录！`n`n错误: " (IsObject(Thrown) && HasProp(Thrown, "Message") ? Thrown.Message : String(Thrown)) "`n`n日志文件: " ErrorLogFile, "错误捕获成功", "Iconi")
        
    } catch {
        ; 备用方案：输出到 Windows 事件日志
        LogToEventLog("AutoHotkey error logging failed")
    }
    
    return 1  ; 抑制错误对话框
}

; =================================================================
; 格式化错误报告
; =================================================================
FormatErrorReport(Thrown, Mode) {
    report := "========================================`n"
    report .= "Time: " A_Now "`n"
    report .= "Mode: " Mode "`n"
    report .= "----------------------------------------`n"
    
    if IsObject(Thrown) {
        ; 提取所有可用属性
        props := ["Message", "What", "File", "Line", "Extra", "Stack"]
        for prop in props {
            if HasProp(Thrown, prop) {
                value := Thrown.%prop%
                if value != "" {
                    if prop = "Stack"
                        report .= prop ":`n" IndentText(value, "  ") "`n"
                    else
                        report .= prop ": " value "`n"
                }
            }
        }
        
        ; 尝试获取错误类型
        if HasBase(Thrown, Error.Prototype)
            report .= "Type: " Type(Thrown) "`n"
            
    } else {
        report .= "Error: " String(Thrown) "`n"
    }
    
    report .= "========================================`n`n"
    return report
}

; =================================================================
; 辅助函数
; =================================================================
IndentText(text, indent := "  ") {
    lines := StrSplit(text, "`n", "`r")
    result := ""
    for line in lines
        result .= indent line "`n"
    return RTrim(result, "`n")
}

LogToEventLog(message) {
    try {
        Run('eventcreate /ID 1 /L APPLICATION /T WARNING /SO AutoHotkey /D "' message '"', , "Hide")
    } catch {
        ; 静默失败
    }
}

; =================================================================
; 初始化
; =================================================================
InitTest() {
    global ErrorLogFile
    
    ; 确保日志目录存在
    SplitPath(ErrorLogFile, , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
    
    ; 清空日志文件（测试用）
    if FileExist(ErrorLogFile)
        FileDelete(ErrorLogFile)
    
    ; 写入测试开始标记
    FileAppend("========================================`n", ErrorLogFile, "UTF-8")
    FileAppend("完整错误处理方案测试 - " A_Now "`n", ErrorLogFile, "UTF-8")
    FileAppend("========================================`n`n", ErrorLogFile, "UTF-8")
}

; =================================================================
; 主程序
; =================================================================
InitTest()

try {
    ; 您的主程序代码
    Main()
}
catch as e {
    HandleRuntimeError(e, "Exit")
}

Main() {
    global ErrorLogFile
    
    ; 记录程序启动
    FileAppend("程序启动`n`n", ErrorLogFile, "UTF-8")
    
    ; 测试1：除零错误
    TestDivisionByZero()
    
    ; 测试2：文件错误
    TestFileError()
    
    ; 测试3：自定义错误
    TestCustomError()
    
    ; 测试4：未捕获的错误（由 OnError 处理）
    ; 注意：这会导致线程退出，所以放在最后
    TestUncaughtError()
    
    ; 记录程序结束
    FileAppend("`n程序正常结束`n", ErrorLogFile, "UTF-8")
}

; =================================================================
; 测试函数
; =================================================================
TestDivisionByZero() {
    global ErrorLogFile
    
    FileAppend("测试1: 除零错误（try-catch 捕获）`n", ErrorLogFile, "UTF-8")
    
    try {
        result := 1 / 0
    } catch as e {
        HandleRuntimeError(e, "Exit")
        FileAppend("✓ 测试1 通过`n`n", ErrorLogFile, "UTF-8")
    }
}

TestFileError() {
    global ErrorLogFile
    
    FileAppend("测试2: 文件错误（try-catch 捕获）`n", ErrorLogFile, "UTF-8")
    
    try {
        content := FileRead("nonexistent_file_test.txt")
    } catch as e {
        HandleRuntimeError(e, "Exit")
        FileAppend("✓ 测试2 通过`n`n", ErrorLogFile, "UTF-8")
    }
}

TestCustomError() {
    global ErrorLogFile
    
    FileAppend("测试3: 自定义错误（try-catch 捕获）`n", ErrorLogFile, "UTF-8")
    
    try {
        throw ValueError("这是一个自定义错误", -1, "测试数据")
    } catch as e {
        HandleRuntimeError(e, "Exit")
        FileAppend("✓ 测试3 通过`n`n", ErrorLogFile, "UTF-8")
    }
}

TestUncaughtError() {
    global ErrorLogFile
    
    FileAppend("测试4: 未捕获的错误（由 OnError 处理）`n", ErrorLogFile, "UTF-8")
    
    ; 这个错误不会被 try-catch 捕获，会由 OnError 处理
    result := 1 / 0
    
    ; 这行不会执行
    FileAppend("✓ 测试4 通过`n`n", ErrorLogFile, "UTF-8")
}
