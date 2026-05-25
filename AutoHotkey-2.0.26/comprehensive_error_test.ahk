#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; =================================================================
; 全面错误类型测试
; 测试 AutoHotkey v2 的各种错误类型
; =================================================================

; 配置错误日志
global ErrorLogFile := A_ScriptDir "\logs\comprehensive_error_test.log"
global DebugMode := true
global TestResults := []
global CurrentTest := ""

; 注册错误处理回调
OnError(HandleRuntimeError, -1)

; =================================================================
; 运行时错误处理
; =================================================================
HandleRuntimeError(Thrown, Mode) {
    global ErrorLogFile, DebugMode, TestResults, CurrentTest
    
    try {
        ; 构建详细的错误报告
        errorReport := FormatErrorReport(Thrown, Mode)
        
        ; 写入日志文件
        FileAppend(errorReport, ErrorLogFile, "UTF-8")
        
        ; 调试模式下输出到调试器
        if DebugMode
            OutputDebug(errorReport)
        
        ; 记录测试结果
        if CurrentTest != "" {
            TestResults.Push({
                Name: CurrentTest,
                Status: "PASS",
                Type: IsObject(Thrown) && HasBase(Thrown, Error.Prototype) ? Type(Thrown) : "Unknown",
                Message: IsObject(Thrown) && HasProp(Thrown, "Message") ? Thrown.Message : String(Thrown)
            })
        }
        
    } catch {
        ; 备用方案
        OutputDebug("Error logging failed")
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

; =================================================================
; 初始化
; =================================================================
InitTest() {
    global ErrorLogFile
    
    ; 确保日志目录存在
    SplitPath(ErrorLogFile, , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
    
    ; 清空日志文件
    if FileExist(ErrorLogFile)
        FileDelete(ErrorLogFile)
    
    ; 写入测试开始标记
    FileAppend("========================================`n", ErrorLogFile, "UTF-8")
    FileAppend("全面错误类型测试 - " A_Now "`n", ErrorLogFile, "UTF-8")
    FileAppend("========================================`n`n", ErrorLogFile, "UTF-8")
}

; =================================================================
; 主程序
; =================================================================
InitTest()

try {
    Main()
} catch as e {
    HandleRuntimeError(e, "Exit")
}

Main() {
    global ErrorLogFile, TestResults
    
    FileAppend("开始全面错误类型测试...`n`n", ErrorLogFile, "UTF-8")
    
    ; 测试各种错误类型
    TestDivisionByZero()
    TestFileNotFound()
    TestTypeError()
    TestValueError()
    TestIndexError()
    TestPropertyError()
    TestMethodError()
    TestMemoryError()
    TestParameterError()
    TestUnsetError()
    TestRegexError()
    TestCOMError()
    TestArrayError()
    TestObjectError()
    TestStringError()
    TestMathError()
    
    ; 显示测试结果
    ShowTestResults()
}

; =================================================================
; 测试函数
; =================================================================

TestDivisionByZero() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "除零错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        result := 1 / 0
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestFileNotFound() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "文件不存在错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        content := FileRead("nonexistent_file_xyz.txt")
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestTypeError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "类型错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试对字符串进行数值运算
        result := "abc" + 123
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestValueError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "值错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        throw ValueError("这是一个自定义值错误", -1, "测试数据")
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestIndexError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "索引错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        arr := [1, 2, 3]
        value := arr[10]  ; 访问不存在的索引
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestPropertyError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "属性错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        obj := {name: "test"}
        value := obj.nonexistent  ; 访问不存在的属性
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestMethodError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "方法错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        arr := [1, 2, 3]
        arr.NonExistentMethod()  ; 调用不存在的方法
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestMemoryError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "内存错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        throw MemoryError("模拟内存不足", -1)
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestParameterError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "参数错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试使用无效参数
        result := SubStr("test", -1, -5)
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestUnsetError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "未设置变量错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试访问未设置的变量
        if IsSet(unsetVar)
            value := unsetVar
        else
            throw UnsetError("变量未设置", -1, "unsetVar")
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestRegexError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "正则表达式错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 使用无效的正则表达式
        result := RegExMatch("test", "[")
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestCOMError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "COM 错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试创建不存在的 COM 对象
        obj := ComObject("NonExistent.Application")
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestArrayError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "数组错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试对非数组使用数组操作
        str := "test"
        str.Push("item")
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestObjectError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "对象错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试对非对象使用对象操作
        num := 123
        num.Property := "value"
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestStringError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "字符串错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试对数字使用字符串方法
        num := 123
        result := StrLower(num)
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

TestMathError() {
    global CurrentTest, ErrorLogFile
    CurrentTest := "数学错误"
    FileAppend("`n>>> 测试: " CurrentTest "`n", ErrorLogFile, "UTF-8")
    
    try {
        ; 尝试计算负数的平方根（不使用复数）
        result := Sqrt(-1)
    } catch as e {
        HandleRuntimeError(e, "Exit")
    }
}

; =================================================================
; 显示测试结果
; =================================================================
ShowTestResults() {
    global TestResults, ErrorLogFile
    
    resultMsg := "========================================`n"
    resultMsg .= "测试结果汇总`n"
    resultMsg .= "========================================`n`n"
    
    passCount := 0
    typeCount := Map()
    
    for result in TestResults {
        status := result.Status = "PASS" ? "✓" : "✗"
        resultMsg .= status " " result.Name " [" result.Type "]`n"
        resultMsg .= "  消息: " result.Message "`n`n"
        
        if result.Status = "PASS"
            passCount++
        
        ; 统计错误类型
        if !typeCount.Has(result.Type)
            typeCount[result.Type] := 0
        typeCount[result.Type]++
    }
    
    resultMsg .= "========================================`n"
    resultMsg .= "总计: " passCount "/" TestResults.Length " 测试通过`n`n"
    
    resultMsg .= "错误类型统计:`n"
    for type, count in typeCount
        resultMsg .= "  " type ": " count " 个`n"
    
    resultMsg .= "========================================`n"
    
    ; 写入日志
    FileAppend(resultMsg, ErrorLogFile, "UTF-8")
    
    ; 显示消息框
    MsgBox(resultMsg, "测试结果", "Iconi")
}
