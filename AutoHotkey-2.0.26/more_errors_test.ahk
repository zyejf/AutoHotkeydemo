#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut "UTF-8"

OnError(LogError, -1)

global LogFile := A_ScriptDir "\more_errors_test.log"
global TestNum := 0
global PassNum := 0

if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("========================================`n", LogFile, "UTF-8")
FileAppend("更多错误类型测试 - " A_Now "`n", LogFile, "UTF-8")
FileAppend("========================================`n`n", LogFile, "UTF-8")

; === 基础错误 ===
RunTest("除零错误", () => (1 / 0))
RunTest("索引错误", () => ([1, 2, 3][10]))
RunTest("文件错误", () => FileRead("nonexistent.txt"))
RunTest("正则错误", () => RegExMatch("test", "["))

; === 类型错误 ===
RunTest("类型转换错误", () => Integer("abc"))
RunTest("类型运算错误", () => ("abc" + 123))
RunTest("类型参数错误", () => StrLower(123))

; === 对象错误 ===
RunTest("方法不存在错误", () => ({a: 1}.NonExistentMethod()))
RunTest("属性不存在错误", () => ({a: 1}.NonExistentProperty))
RunTest("数组操作错误", () => ("test".Push("item")))
RunTest("对象赋值错误", () => (123.Property := "value"))

; === 参数错误 ===
RunTest("参数范围错误", () => Sqrt(-1))
RunTest("参数数量错误", () => SubStr("test"))

; === 数学错误 ===
RunTest("负数平方根", () => Sqrt(-1))
RunTest("无效数学运算", () => Log(0))

; === 数组错误 ===
RunTest("数组越界", () => ([1, 2, 3][100]))
RunTest("数组删除错误", () => ([1, 2, 3].RemoveAt(10)))

; === 自定义错误 ===
RunTest("自定义值错误", () => throw ValueError("测试"))
RunTest("自定义类型错误", () => throw TypeError("测试"))
RunTest("自定义内存错误", () => throw MemoryError("测试"))
RunTest("自定义未设置错误", () => throw UnsetError("测试"))

; === COM 错误 ===
RunTest("COM对象错误", () => ComObject("NonExistent.Application"))

; === 对象操作错误 ===
RunTest("对象克隆错误", () => (123).Clone())

; 显示结果
FileAppend("`n========================================`n", LogFile, "UTF-8")
FileAppend("测试完成！`n", LogFile, "UTF-8")
FileAppend("总计: " TestNum " 个测试`n", LogFile, "UTF-8")
FileAppend("通过: " PassNum " 个`n", LogFile, "UTF-8")
FileAppend("成功率: " Round(PassNum / TestNum * 100, 1) "%`n", LogFile, "UTF-8")
FileAppend("========================================`n", LogFile, "UTF-8")

ToolTip("测试完成！`n总计: " TestNum " 个`n通过: " PassNum " 个`n`n日志: " LogFile)
SetTimer(() => ToolTip(), -5000)

; =================================================================
; 测试函数
; =================================================================
RunTest(name, func) {
    global LogFile, TestNum, PassNum
    
    TestNum++
    FileAppend("测试 #" TestNum ": " name "`n", LogFile, "UTF-8")
    
    try {
        func.Call()
        FileAppend("  ✗ 错误未触发`n`n", LogFile, "UTF-8")
    } catch as e {
        LogError(e, "Exit")
        PassNum++
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
    
    return 1
}
