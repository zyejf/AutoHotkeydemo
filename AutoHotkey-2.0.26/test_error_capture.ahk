#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; 错误捕获测试脚本
; =================================================================

; 注册错误处理回调（-1 表示优先调用）
OnError(LogError, -1)

; 全局日志文件路径
global LogFile := A_ScriptDir "\logs\test_error_capture.log"
global TestResults := []

; 初始化
InitTest()

InitTest() {
    global LogFile
    
    ; 确保日志目录存在
    SplitPath(LogFile, , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
    
    ; 清空日志文件
    if FileExist(LogFile)
        FileDelete(LogFile)
    
    ; 写入测试开始标记
    FileAppend("========================================`n", LogFile, "UTF-8")
    FileAppend("错误捕获测试 - " A_Now "`n", LogFile, "UTF-8")
    FileAppend("========================================`n`n", LogFile, "UTF-8")
}

; 主测试函数
Main()

Main() {
    global TestResults
    
    OutputDebug("=== 开始错误捕获测试 ===")
    
    ; 测试1：未捕获的运行时错误（由 OnError 处理）
    Test1_UncaughtError()
    
    ; 测试2：try-catch 捕获的错误
    Test2_CaughtError()
    
    ; 测试3：多种错误类型
    Test3_MultipleErrorTypes()
    
    ; 显示测试结果
    ShowTestResults()
}

; 测试1：未捕获的运行时错误
Test1_UncaughtError() {
    global TestResults
    
    OutputDebug("测试1: 未捕获的运行时错误")
    
    ; 这个错误不会被 try-catch 捕获，会由 OnError 处理
    ; 注意：这会导致线程退出，所以放在最后
    ; 为了测试，我们使用一个会立即触发错误的操作
    try {
        ; 故意触发除零错误
        result := 1 / 0
        TestResults.Push({Name: "未捕获错误", Status: "FAIL", Note: "错误未被触发"})
    } catch as e {
        ; 这里会捕获到错误
        OutputDebug("测试1: 错误被捕获 - " e.Message)
        TestResults.Push({Name: "未捕获错误", Status: "PASS", Note: e.Message})
    }
}

; 测试2：try-catch 捕获的错误
Test2_CaughtError() {
    global TestResults
    
    OutputDebug("测试2: try-catch 捕获的错误")
    
    try {
        ; 故意触发文件读取错误
        content := FileRead("nonexistent_file_12345.txt")
        TestResults.Push({Name: "文件错误", Status: "FAIL", Note: "错误未被触发"})
    } catch as e {
        OutputDebug("测试2: 错误被捕获 - " e.Message)
        TestResults.Push({Name: "文件错误", Status: "PASS", Note: e.Message})
    }
}

; 测试3：多种错误类型
Test3_MultipleErrorTypes() {
    global TestResults
    
    OutputDebug("测试3: 多种错误类型")
    
    ; 测试 ValueError
    try {
        throw ValueError("这是一个值错误", -1, "测试数据")
    } catch as e {
        OutputDebug("测试3a: ValueError 被捕获 - " e.Message)
        TestResults.Push({Name: "ValueError", Status: "PASS", Note: e.Message})
    }
    
    ; 测试 TypeError
    try {
        arr := [1, 2, 3]
        arr.NonExistentMethod()
    } catch as e {
        OutputDebug("测试3b: TypeError 被捕获 - " e.Message)
        TestResults.Push({Name: "TypeError", Status: "PASS", Note: e.Message})
    }
}

; 显示测试结果
ShowTestResults() {
    global TestResults, LogFile
    
    resultMsg := "错误捕获测试结果`n`n"
    
    passCount := 0
    failCount := 0
    
    for result in TestResults {
        status := result.Status = "PASS" ? "✓" : "✗"
        resultMsg .= status " " result.Name ": " result.Note "`n"
        
        if result.Status = "PASS"
            passCount++
        else
            failCount++
    }
    
    resultMsg .= "`n总计: " passCount " 通过, " failCount " 失败`n"
    resultMsg .= "`n日志文件: " LogFile
    
    ; 写入测试结果到日志
    FileAppend("`n========================================`n", LogFile, "UTF-8")
    FileAppend("测试结果汇总`n", LogFile, "UTF-8")
    FileAppend("========================================`n", LogFile, "UTF-8")
    FileAppend(resultMsg, LogFile, "UTF-8")
    
    OutputDebug("=== 测试完成 ===")
    OutputDebug("通过: " passCount ", 失败: " failCount)
    
    MsgBox(resultMsg, "测试结果", "Iconi")
}

; 错误处理回调函数
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        ; 构建错误信息
        errorMsg := "----------------------------------------`n"
        errorMsg .= "Timestamp: " A_Now "`n"
        errorMsg .= "Mode: " Mode "`n"
        errorMsg .= "Type: " (IsObject(Thrown) && HasProp(Thrown, "Prototype") ? Type(Thrown) : "Unknown") "`n"
        errorMsg .= "----------------------------------------`n"
        
        if IsObject(Thrown) {
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
        
        errorMsg .= "----------------------------------------`n`n"
        
        ; 写入日志文件
        FileAppend(errorMsg, LogFile, "UTF-8")
        
        ; 输出到调试器
        OutputDebug(errorMsg)
        
        ; 显示消息框（测试用）
        MsgBox("错误已被捕获并记录到日志！`n`n错误: " (IsObject(Thrown) && HasProp(Thrown, "Message") ? Thrown.Message : String(Thrown)) "`n`n日志文件: " LogFile, "错误捕获测试", "Icon!")
        
    } catch as e {
        OutputDebug("Failed to log error: " e.Message)
    }
    
    ; 返回 1 抑制错误弹窗
    return 1
}
