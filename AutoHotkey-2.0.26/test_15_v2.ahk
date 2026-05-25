#Requires AutoHotkey v2.0
#SingleInstance Force

OnError(LogError, -1)

global LogFile := A_ScriptDir "\test_15_v2.log"
global Num := 0

if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("测试 15 种错误`n`n", LogFile, "UTF-8")

; 测试 1
Num := 1
FileAppend("1. 除零错误`n", LogFile, "UTF-8")
try {
    result := 1 / 0
} catch as e {
    LogError(e, "Exit")
}

; 测试 2
Num := 2
FileAppend("`n2. 索引错误`n", LogFile, "UTF-8")
try {
    arr := [1, 2, 3]
    value := arr[10]
} catch as e {
    LogError(e, "Exit")
}

; 测试 3
Num := 3
FileAppend("`n3. 文件错误`n", LogFile, "UTF-8")
try {
    content := FileRead("nonexistent.txt")
} catch as e {
    LogError(e, "Exit")
}

; 测试 4
Num := 4
FileAppend("`n4. 正则错误`n", LogFile, "UTF-8")
try {
    result := RegExMatch("test", "[")
} catch as e {
    LogError(e, "Exit")
}

; 测试 5
Num := 5
FileAppend("`n5. 类型转换错误`n", LogFile, "UTF-8")
try {
    result := Integer("abc")
} catch as e {
    LogError(e, "Exit")
}

; 测试 6
Num := 6
FileAppend("`n6. 类型运算错误`n", LogFile, "UTF-8")
try {
    result := "abc" + 123
} catch as e {
    LogError(e, "Exit")
}

; 测试 7
Num := 7
FileAppend("`n7. 类型参数错误`n", LogFile, "UTF-8")
try {
    result := StrLower(123)
} catch as e {
    LogError(e, "Exit")
}

; 测试 8
Num := 8
FileAppend("`n8. 方法不存在错误`n", LogFile, "UTF-8")
try {
    obj := {a: 1}
    obj.NonExistentMethod()
} catch as e {
    LogError(e, "Exit")
}

; 测试 9
Num := 9
FileAppend("`n9. 属性不存在错误`n", LogFile, "UTF-8")
try {
    obj := {a: 1}
    value := obj.NonExistentProperty
} catch as e {
    LogError(e, "Exit")
}

; 测试 10
Num := 10
FileAppend("`n10. 数组操作错误`n", LogFile, "UTF-8")
try {
    str := "test"
    str.Push("item")
} catch as e {
    LogError(e, "Exit")
}

; 测试 11
Num := 11
FileAppend("`n11. 对象赋值错误`n", LogFile, "UTF-8")
try {
    num := 123
    num.Property := "value"
} catch as e {
    LogError(e, "Exit")
}

; 测试 12
Num := 12
FileAppend("`n12. 参数范围错误`n", LogFile, "UTF-8")
try {
    result := Sqrt(-1)
} catch as e {
    LogError(e, "Exit")
}

; 测试 13
Num := 13
FileAppend("`n13. 无效数学运算`n", LogFile, "UTF-8")
try {
    result := Log(0)
} catch as e {
    LogError(e, "Exit")
}

; 测试 14
Num := 14
FileAppend("`n14. 自定义值错误`n", LogFile, "UTF-8")
try {
    throw ValueError("测试")
} catch as e {
    LogError(e, "Exit")
}

; 测试 15
Num := 15
FileAppend("`n15. 自定义类型错误`n", LogFile, "UTF-8")
try {
    throw TypeError("测试")
} catch as e {
    LogError(e, "Exit")
}

; 完成
FileAppend("`n========================================`n", LogFile, "UTF-8")
FileAppend("测试完成！共测试 " Num " 种错误`n", LogFile, "UTF-8")
FileAppend("========================================`n", LogFile, "UTF-8")

ToolTip("测试完成！共测试 " Num " 种错误`n日志: " LogFile)
SetTimer(() => ToolTip(), -5000)

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
