#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; 错误类型测试 - 基础版
; =================================================================

OnError(LogError, -1)

global LogFile := A_ScriptDir "\error_types_test.log"
global TestNum := 0

; 初始化
if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("错误类型测试 - " A_Now "`n`n", LogFile, "UTF-8")

; 测试 1: 除零错误
TestNum := 1
FileAppend("测试 1: 除零错误`n", LogFile, "UTF-8")
try {
    result := 1 / 0
} catch as e {
    LogError(e, "Exit")
}

; 测试 2: 文件错误
TestNum := 2
FileAppend("`n测试 2: 文件错误`n", LogFile, "UTF-8")
try {
    content := FileRead("nonexistent.txt")
} catch as e {
    LogError(e, "Exit")
}

; 测试 3: 值错误
TestNum := 3
FileAppend("`n测试 3: 值错误`n", LogFile, "UTF-8")
try {
    throw ValueError("自定义值错误", -1, "测试")
} catch as e {
    LogError(e, "Exit")
}

; 测试 4: 类型错误
TestNum := 4
FileAppend("`n测试 4: 类型错误`n", LogFile, "UTF-8")
try {
    result := "abc" + 123
} catch as e {
    LogError(e, "Exit")
}

; 测试 5: 索引错误
TestNum := 5
FileAppend("`n测试 5: 索引错误`n", LogFile, "UTF-8")
try {
    arr := [1, 2, 3]
    value := arr[10]
} catch as e {
    LogError(e, "Exit")
}

; 测试 6: 方法错误
TestNum := 6
FileAppend("`n测试 6: 方法错误`n", LogFile, "UTF-8")
try {
    arr := [1, 2, 3]
    arr.NonExistentMethod()
} catch as e {
    LogError(e, "Exit")
}

; 测试 7: 参数错误
TestNum := 7
FileAppend("`n测试 7: 参数错误`n", LogFile, "UTF-8")
try {
    result := SubStr("test", -1, -5)
} catch as e {
    LogError(e, "Exit")
}

; 测试 8: 正则错误
TestNum := 8
FileAppend("`n测试 8: 正则错误`n", LogFile, "UTF-8")
try {
    result := RegExMatch("test", "[")
} catch as e {
    LogError(e, "Exit")
}

; 测试 9: 内存错误
TestNum := 9
FileAppend("`n测试 9: 内存错误`n", LogFile, "UTF-8")
try {
    throw MemoryError("模拟内存不足", -1)
} catch as e {
    LogError(e, "Exit")
}

; 测试 10: 未设置错误
TestNum := 10
FileAppend("`n测试 10: 未设置错误`n", LogFile, "UTF-8")
try {
    throw UnsetError("变量未设置", -1, "var")
} catch as e {
    LogError(e, "Exit")
}

; 显示结果
FileAppend("`n========================================`n", LogFile, "UTF-8")
FileAppend("测试完成！共测试 " TestNum " 种错误类型`n", LogFile, "UTF-8")
FileAppend("========================================`n", LogFile, "UTF-8")

MsgBox("测试完成！共测试 " TestNum " 种错误类型`n`n日志文件: " LogFile, "测试结果", "Iconi")

; =================================================================
; 错误处理函数
; =================================================================
LogError(Thrown, Mode) {
    global LogFile, TestNum
    
    try {
        msg := "错误类型: "
        
        if IsObject(Thrown) {
            if HasBase(Thrown, Error.Prototype)
                msg .= Type(Thrown)
            else
                msg .= "Unknown"
            
            if HasProp(Thrown, "Message")
                msg .= "`n错误消息: " Thrown.Message
            
            if HasProp(Thrown, "Line")
                msg .= "`n错误行号: " Thrown.Line
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
