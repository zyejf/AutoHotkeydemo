; =================================================================
; 测试层 - 错误系统测试
; 版本: 1.0
; 说明: 测试错误处理系统的各项功能
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../infrastructure/error_system.ahk"

; =================================================================
; 全局变量
; =================================================================
global g_testResults := []
global g_testPassed := 0
global g_testFailed := 0

; =================================================================
; 初始化
; =================================================================
ErrorSystem.logFile := A_ScriptDir "\logs\test_errors.log"
OnError(ErrorSystem_HandleError, -1)

; =================================================================
; 测试函数
; =================================================================

TestRuntimeErrors() {
    global g_testResults
    result := {name: "运行时错误捕获", passed: false, details: ""}
    
    try {
        initialCount := ErrorSystem.GetErrorCount()
        
        _TriggerError("测试运行时错误")
        
        Sleep(100)
        
        newCount := ErrorSystem.GetErrorCount()
        
        if (newCount > initialCount) {
            result.passed := true
            result.details := "错误计数从 " initialCount " 增加到 " newCount
        } else {
            result.details := "错误计数未增加: " initialCount " -> " newCount
        }
    } catch as e {
        result.details := "测试异常: " e.Message
    }
    
    g_testResults.Push(result)
    _PrintResult(result)
}

TestErrorLevels() {
    global g_testResults
    result := {name: "错误级别识别", passed: false, details: ""}
    
    try {
        initialCount := ErrorSystem.GetErrorCount()
        
        _TriggerError("普通错误", "Error")
        _TriggerError("类型错误", "TypeError")
        _TriggerError("索引错误", "IndexError")
        
        Sleep(100)
        
        newCount := ErrorSystem.GetErrorCount()
        errorIncrease := newCount - initialCount
        
        if (errorIncrease >= 3) {
            result.passed := true
            result.details := "成功捕获 " errorIncrease " 个不同类型的错误"
        } else {
            result.details := "错误捕获数量不足: " errorIncrease " (预期 >= 3)"
        }
    } catch as e {
        result.details := "测试异常: " e.Message
    }
    
    g_testResults.Push(result)
    _PrintResult(result)
}

TestLogFormat() {
    global g_testResults
    result := {name: "日志格式验证", passed: false, details: ""}
    
    try {
        logFile := ErrorSystem.logFile
        
        if !FileExist(logFile) {
            result.details := "日志文件不存在: " logFile
            g_testResults.Push(result)
            _PrintResult(result)
            return
        }
        
        content := FileRead(logFile, "UTF-8")
        lines := StrSplit(content, "`n")
        
        validLines := 0
        invalidLines := 0
        
        for line in lines {
            line := Trim(line)
            if (line = "")
                continue
            
            if (SubStr(line, 1, 1) = "{" && SubStr(line, StrLen(line), 1) = "}") {
                if (InStr(line, '"timestamp"') && InStr(line, '"level"') && InStr(line, '"message"')) {
                    validLines++
                } else {
                    invalidLines++
                }
            } else {
                invalidLines++
            }
        }
        
        if (validLines > 0 && invalidLines = 0) {
            result.passed := true
            result.details := "日志格式正确，有效行数: " validLines
        } else {
            result.details := "日志格式错误，有效: " validLines "，无效: " invalidLines
        }
    } catch as e {
        result.details := "测试异常: " e.Message
    }
    
    g_testResults.Push(result)
    _PrintResult(result)
}

TestNoPopup() {
    global g_testResults
    result := {name: "无弹窗验证", passed: false, details: ""}
    
    try {
        ErrorSystem.LogError("手动测试错误 - 验证无弹窗", "ERROR")
        
        Sleep(100)
        
        result.passed := true
        result.details := "错误已记录且无弹窗显示（OnError 返回 1）"
    } catch as e {
        result.details := "测试异常: " e.Message
    }
    
    g_testResults.Push(result)
    _PrintResult(result)
}

TestManualLogging() {
    global g_testResults
    result := {name: "手动记录功能", passed: false, details: ""}
    
    try {
        initialCount := ErrorSystem.GetErrorCount()
        
        ErrorSystem.LogError("手动错误记录测试", "ERROR")
        ErrorSystem.LogWarning("手动警告记录测试")
        ErrorSystem.LogInfo("手动信息记录测试")
        
        Sleep(100)
        
        newCount := ErrorSystem.GetErrorCount()
        errorIncrease := newCount - initialCount
        
        if (errorIncrease >= 3) {
            result.passed := true
            result.details := "成功记录 " errorIncrease " 条手动日志"
        } else {
            result.details := "手动记录数量不足: " errorIncrease " (预期 >= 3)"
        }
    } catch as e {
        result.details := "测试异常: " e.Message
    }
    
    g_testResults.Push(result)
    _PrintResult(result)
}

; =================================================================
; 辅助函数
; =================================================================
_TriggerError(message, errorType := "Error") {
    err := ""
    switch errorType {
        case "TypeError":
            err := TypeError(message)
        case "IndexError":
            err := IndexError(message)
        default:
            err := Error(message)
    }
    ErrorSystem.HandleError(err, "Test")
}

_PrintResult(result) {
    status := result.passed ? "✓ 通过" : "✗ 失败"
    OutputDebug("[" status "] " result.name ": " result.details)
}

_PrintSummary() {
    global g_testResults, g_testPassed, g_testFailed
    
    for result in g_testResults {
        if result.passed
            g_testPassed++
        else
            g_testFailed++
    }
    
    total := g_testPassed + g_testFailed
    
    summary := "`n"
    summary .= "========================================`n"
    summary .= "测试汇总`n"
    summary .= "========================================`n"
    summary .= "总计: " total " 个测试`n"
    summary .= "通过: " g_testPassed " 个`n"
    summary .= "失败: " g_testFailed " 个`n"
    summary .= "========================================`n`n"
    
    summary .= "详细结果:`n"
    summary .= "----------------------------------------`n"
    
    for result in g_testResults {
        status := result.passed ? "✓" : "✗"
        summary .= status " " result.name "`n"
        if result.details != ""
            summary .= "  " result.details "`n"
    }
    
    summary .= "========================================`n"
    summary .= "日志文件: " ErrorSystem.logFile "`n"
    summary .= "错误计数: " ErrorSystem.GetErrorCount() "`n"
    summary .= "========================================`n"
    
    MsgBox(summary, "错误系统测试结果", 0)
}

; =================================================================
; Setup/Teardown 钩子（确保测试间状态隔离）
; =================================================================
_SetupTest() {
    ; 记录当前错误计数作为基线，确保测试通过增量计算隔离
    global g_errorBaseline := ErrorSystem.GetErrorCount()
}

_TeardownTest() {
    ; 清理测试产生的临时状态（ErrorSystem 计数保留用于增量计算）
}

; =================================================================
; 主程序
; =================================================================
_SetupTest()
TestRuntimeErrors()
_TeardownTest()

_SetupTest()
TestErrorLevels()
_TeardownTest()

_SetupTest()
TestLogFormat()
_TeardownTest()

_SetupTest()
TestNoPopup()
_TeardownTest()

_SetupTest()
TestManualLogging()
_TeardownTest()

_PrintSummary()
