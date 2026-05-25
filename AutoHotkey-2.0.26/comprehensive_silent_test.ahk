#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut "UTF-8"

; =================================================================
; 全面错误测试 - 20+ 种错误类型
; =================================================================

; 立即注册错误处理
OnError(LogError, -1)

global LogFile := A_ScriptDir "\comprehensive_silent_test.log"
global TestCount := 0
global PassCount := 0

; 初始化
if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("========================================`n", LogFile, "UTF-8")
FileAppend("全面错误测试 - " A_Now "`n", LogFile, "UTF-8")
FileAppend("========================================`n`n", LogFile, "UTF-8")

; =================================================================
; 运行所有测试
; =================================================================

; === 基础错误 ===
Test("除零错误", () => (1 / 0))
Test("索引错误", () => ([1, 2, 3][10]))
Test("文件错误", () => FileRead("nonexistent.txt"))
Test("正则错误", () => RegExMatch("test", "["))

; === 类型错误 ===
Test("类型转换错误", () => Integer("abc"))
Test("类型运算错误", () => ("abc" + 123))
Test("类型参数错误", () => StrLower(123))

; === 对象错误 ===
Test("方法不存在错误", () => ({a: 1}.NonExistentMethod()))
Test("属性不存在错误", () => ({a: 1}.NonExistentProperty))
Test("数组操作错误", () => ("test".Push("item")))
Test("对象赋值错误", () => (123.Property := "value"))

; === 参数错误 ===
Test("参数范围错误", () => Sqrt(-1))
Test("参数数量错误", () => SubStr("test"))
Test("参数类型错误", () => StrReplace(123, "a", "b"))

; === 数学错误 ===
Test("负数平方根", () => Sqrt(-1))
Test("无效数学运算", () => Log(0))
Test("数值溢出", () => (10 ** 1000))

; === 字符串错误 ===
Test("字符串索引错误", () => SubStr("test", 10, 5))
Test("字符串格式错误", () => Format("{1}", ))

; === 数组错误 ===
Test("数组越界", () => ([1, 2, 3][100]))
Test("数组删除错误", () => ([1, 2, 3].RemoveAt(10)))

; === 函数错误 ===
Test("函数不存在", () => NonExistentFunction())
Test("回调错误", () => ((x) => x + 1).Call())

; === 自定义错误 ===
Test("自定义值错误", () => throw ValueError("自定义值错误"))
Test("自定义类型错误", () => throw TypeError("自定义类型错误"))
Test("自定义内存错误", () => throw MemoryError("自定义内存错误"))
Test("自定义未设置错误", () => throw UnsetError("自定义未设置错误"))
Test("自定义参数错误", () => throw Error("自定义错误"))

; === COM 错误 ===
Test("COM对象错误", () => ComObject("NonExistent.Application"))

; === 对象操作错误 ===
Test("对象克隆错误", () => (123).Clone())
Test("对象删除错误", () => ({a: 1}.Delete("b")))

; === 其他错误 ===
Test("无效变量名", () => (1abc := 123))
Test("无效表达式", () => (1 + + 1))

; =================================================================
; 显示结果
; =================================================================
ShowFinalResult()

; =================================================================
; 测试函数
; =================================================================
Test(name, func) {
    global LogFile, TestCount, PassCount
    
    TestCount++
    FileAppend("测试 #" TestCount ": " name "`n", LogFile, "UTF-8")
    
    try {
        func.Call()
        FileAppend("  ✗ 错误未触发`n`n", LogFile, "UTF-8")
    } catch as e {
        LogError(e, "Exit")
        PassCount++
        FileAppend("  ✓ 已捕获`n`n", LogFile, "UTF-8")
    }
}

; =================================================================
; 错误处理函数
; =================================================================
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        msg := "  错误类型: "
        
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
        
        msg .= "`n"
        
        FileAppend(msg, LogFile, "UTF-8")
        
    } catch {
        OutputDebug("Error")
    }
    
    ; 关键：返回 1 抑制弹窗
    return 1
}

; =================================================================
; 显示最终结果
; =================================================================
ShowFinalResult() {
    global LogFile, TestCount, PassCount
    
    resultMsg := "========================================`n"
    resultMsg .= "测试完成！`n"
    resultMsg .= "总计: " TestCount " 个测试`n"
    resultMsg .= "通过: " PassCount " 个`n"
    resultMsg .= "成功率: " Round(PassCount / TestCount * 100, 1) "%`n"
    resultMsg .= "========================================`n"
    resultMsg .= "`n日志文件: " LogFile
    
    FileAppend(resultMsg, LogFile, "UTF-8")
    
    ; 使用 ToolTip 显示结果（不弹窗）
    ToolTip(resultMsg)
    SetTimer(() => ToolTip(), -5000)
}
