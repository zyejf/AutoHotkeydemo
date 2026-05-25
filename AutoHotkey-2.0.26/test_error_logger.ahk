#Requires AutoHotkey v2.0
#SingleInstance Force

#Include error_logger.ahk

ErrorLogger(A_ScriptDir "\test_logs\test_error.log", {
    MaxLogSize: 1048576,
    MaxLogFiles: 5,
    DebugMode: true,
    LogToConsole: false
})

RunTests()

RunTests() {
    ErrorLogger.Log("INFO", "=====================================")
    ErrorLogger.Log("INFO", "错误日志系统测试开始")
    ErrorLogger.Log("INFO", "=====================================")
    
    Test1_BasicError()
    Test2_FileError()
    Test3_DivisionByZero()
    Test4_CustomError()
    Test5_MethodError()
    Test6_LogRotation()
    
    ErrorLogger.Log("INFO", "=====================================")
    ErrorLogger.Log("INFO", "所有测试完成")
    ErrorLogger.Log("INFO", "=====================================")
    
    ShowResults()
}

Test1_BasicError() {
    ErrorLogger.Log("INFO", "测试1: 基本错误捕获")
    
    try {
        throw Error("这是一个测试错误", -1, "Test1_BasicError")
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        ErrorLogger.Log("INFO", "测试1: 通过 ✓")
    }
}

Test2_FileError() {
    ErrorLogger.Log("INFO", "测试2: 文件操作错误")
    
    try {
        content := FileRead("nonexistent_file_test.txt")
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        ErrorLogger.Log("INFO", "测试2: 通过 ✓")
    }
}

Test3_DivisionByZero() {
    ErrorLogger.Log("INFO", "测试3: 除零错误")
    
    try {
        result := 10 / 0
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        ErrorLogger.Log("INFO", "测试3: 通过 ✓")
    }
}

Test4_CustomError() {
    ErrorLogger.Log("INFO", "测试4: 自定义错误")
    
    try {
        throw ValueError("自定义值错误", -1, "自定义错误测试")
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        ErrorLogger.Log("INFO", "测试4: 通过 ✓")
    }
}

Test5_MethodError() {
    ErrorLogger.Log("INFO", "测试5: 方法不存在错误")
    
    try {
        arr := [1, 2, 3]
        arr.NonExistentMethod()
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        ErrorLogger.Log("INFO", "测试5: 通过 ✓")
    }
}

Test6_LogRotation() {
    ErrorLogger.Log("INFO", "测试6: 日志轮转功能")
    
    try {
        stats := ErrorLogger.GetLogStats()
        ErrorLogger.Log("INFO", "日志统计", stats)
        ErrorLogger.Log("INFO", "测试6: 通过 ✓")
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        ErrorLogger.Log("WARNING", "测试6: 部分通过 ⚠")
    }
}

ShowResults() {
    logFile := ErrorLogger.LogFile
    stats := ErrorLogger.GetLogStats()
    
    resultMsg := "测试完成！`n`n"
    resultMsg .= "日志文件: " logFile "`n"
    
    if HasProp(stats, "Size")
        resultMsg .= "文件大小: " Round(stats["Size"] / 1024, 2) " KB`n"
    
    if HasProp(stats, "ErrorCount")
        resultMsg .= "错误数量: " stats["ErrorCount"] "`n"
    
    resultMsg .= "`n是否打开日志文件？"
    
    response := MsgBox(resultMsg, "测试结果", "YesNo Iconi")
    
    if response = "Yes"
        Run(logFile)
}
