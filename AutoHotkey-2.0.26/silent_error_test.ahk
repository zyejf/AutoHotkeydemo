#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut "UTF-8"

; 立即注册错误处理
OnError(LogError, -1)

global LogFile := A_ScriptDir "\silent_errors.log"

; 初始化
if FileExist(LogFile)
    FileDelete(LogFile)

FileAppend("=== 无弹窗错误测试 ===`n`n", LogFile, "UTF-8")

; 测试 1
FileAppend("测试 1: 除零错误`n", LogFile, "UTF-8")
try {
    result := 1 / 0
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 2
FileAppend("`n测试 2: 索引错误`n", LogFile, "UTF-8")
try {
    arr := [1, 2, 3]
    value := arr[10]
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 3
FileAppend("`n测试 3: 文件错误`n", LogFile, "UTF-8")
try {
    content := FileRead("nonexistent.txt")
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 4
FileAppend("`n测试 4: 正则错误`n", LogFile, "UTF-8")
try {
    result := RegExMatch("test", "[")
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 5
FileAppend("`n测试 5: 类型错误`n", LogFile, "UTF-8")
try {
    result := Integer("abc")
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 6
FileAppend("`n测试 6: 方法错误`n", LogFile, "UTF-8")
try {
    obj := {a: 1}
    obj.NonExistentMethod()
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 7
FileAppend("`n测试 7: 属性错误`n", LogFile, "UTF-8")
try {
    obj := {a: 1}
    value := obj.NonExistentProperty
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 测试 8
FileAppend("`n测试 8: 参数错误`n", LogFile, "UTF-8")
try {
    result := Sqrt(-1)
} catch as e {
    LogError(e, "Exit")
    FileAppend("  ✓ 已捕获`n", LogFile, "UTF-8")
}

; 完成
FileAppend("`n========================================`n", LogFile, "UTF-8")
FileAppend("测试完成！所有错误已捕获，无弹窗！`n", LogFile, "UTF-8")
FileAppend("========================================`n", LogFile, "UTF-8")

; 使用 ToolTip 显示结果（不弹窗）
ToolTip("测试完成！`n日志: " LogFile)
SetTimer(() => ToolTip(), -3000)

; 错误处理函数
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
    
    ; 关键：返回 1 抑制弹窗
    return 1
}
