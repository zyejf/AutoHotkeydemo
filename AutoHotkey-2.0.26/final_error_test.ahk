#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; 全面错误类型测试 - 最终版
; =================================================================

OnError(LogError, -1)

global LogFile := A_ScriptDir "\final_error_test.log"
global TestCount := 0

; 初始化
if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("========================================`n", LogFile, "UTF-8")
FileAppend("全面错误类型测试 - " A_Now "`n", LogFile, "UTF-8")
FileAppend("========================================`n`n", LogFile, "UTF-8")

; 运行所有测试
RunAllTests()

; 显示结果
ShowResults()

; =================================================================
; 运行所有测试
; =================================================================
RunAllTests() {
    global LogFile
    
    ; 测试 1: 除零错误
    Test("除零错误", () => (1 / 0))
    
    ; 测试 2: 索引错误
    Test("索引错误", () => ([1, 2, 3][10]))
    
    ; 测试 3: 文件错误
    Test("文件错误", () => FileRead("nonexistent.txt"))
    
    ; 测试 4: 正则错误
    Test("正则错误", () => RegExMatch("test", "["))
    
    ; 测试 5: 类型错误
    Test("类型错误", () => Integer("abc"))
    
    ; 测试 6: 方法错误
    Test("方法错误", () => ({a: 1}.NonExistentMethod()))
    
    ; 测试 7: 属性错误
    Test("属性错误", () => ({a: 1}.NonExistentProperty))
    
    ; 测试 8: 参数错误
    Test("参数错误", () => Sqrt(-1))
    
    ; 测试 9: 值错误
    Test("值错误", () => throw ValueError("自定义值错误"))
    
    ; 测试 10: 内存错误
    Test("内存错误", () => throw MemoryError("内存不足"))
    
    ; 测试 11: 未设置错误
    Test("未设置错误", () => throw UnsetError("变量未设置"))
    
    ; 测试 12: 数组操作错误
    Test("数组操作错误", () => ("test".Push("item")))
    
    ; 测试 13: 对象操作错误
    Test("对象操作错误", () => (123.Property := "value"))
    
    ; 测试 14: 字符串操作错误
    Test("字符串操作错误", () => StrLower(123))
    
    ; 测试 15: 数学运算错误
    Test("数学运算错误", () => ("abc" + 123))
}

; =================================================================
; 测试函数
; =================================================================
Test(name, func) {
    global LogFile, TestCount
    
    TestCount++
    FileAppend("测试 #" TestCount ": " name "`n", LogFile, "UTF-8")
    
    try {
        func.Call()
        FileAppend("  ✗ 错误未触发`n`n", LogFile, "UTF-8")
    } catch as e {
        LogError(e, "Exit")
    }
}

; =================================================================
; 错误处理函数
; =================================================================
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        msg := "  ✓ 错误类型: "
        
        if IsObject(Thrown) {
            if HasBase(Thrown, Error.Prototype)
                msg .= Type(Thrown)
            else
                msg .= "Unknown"
            
            if HasProp(Thrown, "Message")
                msg .= "`n  错误消息: " Thrown.Message
        } else {
            msg .= String(Thrown)
        }
        
        msg .= "`n`n"
        
        FileAppend(msg, LogFile, "UTF-8")
        
    } catch {
        OutputDebug("Error")
    }
    
    return 1
}

; =================================================================
; 显示结果
; =================================================================
ShowResults() {
    global LogFile, TestCount
    
    resultMsg := "========================================`n"
    resultMsg .= "测试完成！`n"
    resultMsg .= "共测试 " TestCount " 种错误类型`n"
    resultMsg .= "========================================`n"
    
    FileAppend(resultMsg, LogFile, "UTF-8")
    
    MsgBox(resultMsg "`n日志文件: " LogFile, "测试结果", "Iconi")
}
