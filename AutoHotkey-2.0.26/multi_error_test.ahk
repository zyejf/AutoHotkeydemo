#Requires AutoHotkey v2.0
#SingleInstance Force

OnError(LogError, -1)

global LogFile := A_ScriptDir "\multi_error_test.log"
global TestCount := 0

if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("=== 多种错误类型测试 ===`n`n", LogFile, "UTF-8")

; 测试 1
TestCount++
FileAppend("测试 1: 除零错误`n", LogFile, "UTF-8")
try {
    result := 1 / 0
} catch as e {
    LogError(e, "Exit")
}

; 测试 2
TestCount++
FileAppend("`n测试 2: 索引错误`n", LogFile, "UTF-8")
try {
    arr := [1, 2, 3]
    value := arr[10]
} catch as e {
    LogError(e, "Exit")
}

; 测试 3
TestCount++
FileAppend("`n测试 3: 文件错误`n", LogFile, "UTF-8")
try {
    content := FileRead("nonexistent.txt")
} catch as e {
    LogError(e, "Exit")
}

; 测试 4
TestCount++
FileAppend("`n测试 4: 正则错误`n", LogFile, "UTF-8")
try {
    result := RegExMatch("test", "[")
} catch as e {
    LogError(e, "Exit")
}

; 测试 5
TestCount++
FileAppend("`n测试 5: 类型错误`n", LogFile, "UTF-8")
try {
    result := Integer("abc")
} catch as e {
    LogError(e, "Exit")
}

; 测试 6
TestCount++
FileAppend("`n测试 6: 方法错误`n", LogFile, "UTF-8")
try {
    obj := {a: 1}
    obj.NonExistentMethod()
} catch as e {
    LogError(e, "Exit")
}

; 测试 7
TestCount++
FileAppend("`n测试 7: 属性错误`n", LogFile, "UTF-8")
try {
    obj := {a: 1}
    value := obj.NonExistentProperty
} catch as e {
    LogError(e, "Exit")
}

; 测试 8
TestCount++
FileAppend("`n测试 8: 参数错误`n", LogFile, "UTF-8")
try {
    result := Sqrt(-1)
} catch as e {
    LogError(e, "Exit")
}

; 测试 9
TestCount++
FileAppend("`n测试 9: 值错误`n", LogFile, "UTF-8")
try {
    throw ValueError("自定义值错误")
} catch as e {
    LogError(e, "Exit")
}

; 测试 10
TestCount++
FileAppend("`n测试 10: 内存错误`n", LogFile, "UTF-8")
try {
    throw MemoryError("内存不足")
} catch as e {
    LogError(e, "Exit")
}

; 测试 11
TestCount++
FileAppend("`n测试 11: 未设置错误`n", LogFile, "UTF-8")
try {
    throw UnsetError("变量未设置")
} catch as e {
    LogError(e, "Exit")
}

; 测试 12
TestCount++
FileAppend("`n测试 12: 数组操作错误`n", LogFile, "UTF-8")
try {
    str := "test"
    str.Push("item")
} catch as e {
    LogError(e, "Exit")
}

; 测试 13
TestCount++
FileAppend("`n测试 13: 对象操作错误`n", LogFile, "UTF-8")
try {
    num := 123
    num.Property := "value"
} catch as e {
    LogError(e, "Exit")
}

; 测试 14
TestCount++
FileAppend("`n测试 14: 字符串操作错误`n", LogFile, "UTF-8")
try {
    result := StrLower(123)
} catch as e {
    LogError(e, "Exit")
}

; 测试 15
TestCount++
FileAppend("`n测试 15: 数学运算错误`n", LogFile, "UTF-8")
try {
    result := "abc" + 123
} catch as e {
    LogError(e, "Exit")
}

; 显示结果
FileAppend("`n========================================`n", LogFile, "UTF-8")
FileAppend("测试完成！共测试 " TestCount " 种错误类型`n", LogFile, "UTF-8")
FileAppend("========================================`n", LogFile, "UTF-8")

MsgBox("测试完成！共测试 " TestCount " 种错误类型`n`n日志文件: " LogFile, "测试结果", "Iconi")

LogError(Thrown, Mode) {
    global LogFile
    
    try {
        msg := "✓ 错误类型: "
        
        if IsObject(Thrown) {
            if HasBase(Thrown, Error.Prototype)
                msg .= Type(Thrown)
            else
                msg .= "Unknown"
            
            if HasProp(Thrown, "Message")
                msg .= "`n  消息: " Thrown.Message
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
