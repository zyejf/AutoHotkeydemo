#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"

; =================================================================
; 全面错误类型测试 - 简化版
; =================================================================

global ErrorLogFile := A_ScriptDir "\comprehensive_test.log"
global TestCount := 0
global PassCount := 0

OnError(HandleError, -1)

; 初始化
if FileExist(ErrorLogFile)
    FileDelete(ErrorLogFile)

FileAppend("========================================`n", ErrorLogFile, "UTF-8")
FileAppend("全面错误类型测试 - " A_Now "`n", ErrorLogFile, "UTF-8")
FileAppend("========================================`n`n", ErrorLogFile, "UTF-8")

; 运行测试
RunAllTests()

; 显示结果
ShowResults()

; =================================================================
; 错误处理
; =================================================================
HandleError(Thrown, Mode) {
    global ErrorLogFile, TestCount, PassCount
    
    try {
        TestCount++
        PassCount++
        
        msg := "----------------------------------------`n"
        msg .= "测试 #" TestCount ": "
        
        if IsObject(Thrown) {
            if HasProp(Thrown, "Message")
                msg .= Thrown.Message "`n"
            if HasBase(Thrown, Error.Prototype)
                msg .= "类型: " Type(Thrown) "`n"
        } else {
            msg .= String(Thrown) "`n"
        }
        
        msg .= "----------------------------------------`n`n"
        
        FileAppend(msg, ErrorLogFile, "UTF-8")
        
    } catch {
        OutputDebug("Error")
    }
    
    return 1
}

; =================================================================
; 运行所有测试
; =================================================================
RunAllTests() {
    global ErrorLogFile
    
    FileAppend("开始测试各种错误类型...`n`n", ErrorLogFile, "UTF-8")
    
    ; 测试 1: 除零错误
    Test1()
    
    ; 测试 2: 文件错误
    Test2()
    
    ; 测试 3: 类型错误
    Test3()
    
    ; 测试 4: 值错误
    Test4()
    
    ; 测试 5: 索引错误
    Test5()
    
    ; 测试 6: 方法错误
    Test6()
    
    ; 测试 7: 属性错误
    Test7()
    
    ; 测试 8: 参数错误
    Test8()
    
    ; 测试 9: 正则错误
    Test9()
    
    ; 测试 10: 数组错误
    Test10()
    
    ; 测试 11: 对象错误
    Test11()
    
    ; 测试 12: 字符串错误
    Test12()
    
    ; 测试 13: 数学错误
    Test13()
    
    ; 测试 14: 内存错误
    Test14()
    
    ; 测试 15: 未设置错误
    Test15()
    
    ; 测试 16: COM 错误
    Test16()
}

Test1() {
    global ErrorLogFile
    FileAppend("测试 1: 除零错误`n", ErrorLogFile, "UTF-8")
    try {
        result := 1 / 0
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test2() {
    global ErrorLogFile
    FileAppend("测试 2: 文件错误`n", ErrorLogFile, "UTF-8")
    try {
        content := FileRead("nonexistent.txt")
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test3() {
    global ErrorLogFile
    FileAppend("测试 3: 类型错误`n", ErrorLogFile, "UTF-8")
    try {
        result := "abc" + 123
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test4() {
    global ErrorLogFile
    FileAppend("测试 4: 值错误`n", ErrorLogFile, "UTF-8")
    try {
        throw ValueError("自定义值错误", -1, "测试")
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test5() {
    global ErrorLogFile
    FileAppend("测试 5: 索引错误`n", ErrorLogFile, "UTF-8")
    try {
        arr := [1, 2, 3]
        value := arr[10]
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test6() {
    global ErrorLogFile
    FileAppend("测试 6: 方法错误`n", ErrorLogFile, "UTF-8")
    try {
        arr := [1, 2, 3]
        arr.NonExistentMethod()
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test7() {
    global ErrorLogFile
    FileAppend("测试 7: 属性错误`n", ErrorLogFile, "UTF-8")
    try {
        obj := {name: "test"}
        value := obj.nonexistent
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test8() {
    global ErrorLogFile
    FileAppend("测试 8: 参数错误`n", ErrorLogFile, "UTF-8")
    try {
        result := SubStr("test", -1, -5)
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test9() {
    global ErrorLogFile
    FileAppend("测试 9: 正则错误`n", ErrorLogFile, "UTF-8")
    try {
        result := RegExMatch("test", "[")
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test10() {
    global ErrorLogFile
    FileAppend("测试 10: 数组错误`n", ErrorLogFile, "UTF-8")
    try {
        str := "test"
        str.Push("item")
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test11() {
    global ErrorLogFile
    FileAppend("测试 11: 对象错误`n", ErrorLogFile, "UTF-8")
    try {
        num := 123
        num.Property := "value"
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test12() {
    global ErrorLogFile
    FileAppend("测试 12: 字符串错误`n", ErrorLogFile, "UTF-8")
    try {
        num := 123
        result := StrLower(num)
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test13() {
    global ErrorLogFile
    FileAppend("测试 13: 数学错误`n", ErrorLogFile, "UTF-8")
    try {
        result := Sqrt(-1)
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test14() {
    global ErrorLogFile
    FileAppend("测试 14: 内存错误`n", ErrorLogFile, "UTF-8")
    try {
        throw MemoryError("模拟内存不足", -1)
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test15() {
    global ErrorLogFile
    FileAppend("测试 15: 未设置错误`n", ErrorLogFile, "UTF-8")
    try {
        throw UnsetError("变量未设置", -1, "var")
    } catch as e {
        HandleError(e, "Exit")
    }
}

Test16() {
    global ErrorLogFile
    FileAppend("测试 16: COM 错误`n", ErrorLogFile, "UTF-8")
    try {
        obj := ComObject("NonExistent.Application")
    } catch as e {
        HandleError(e, "Exit")
    }
}

; =================================================================
; 显示结果
; =================================================================
ShowResults() {
    global ErrorLogFile, TestCount, PassCount
    
    resultMsg := "`n========================================`n"
    resultMsg .= "测试结果`n"
    resultMsg .= "========================================`n"
    resultMsg .= "总计: " PassCount "/" TestCount " 测试通过`n"
    resultMsg .= "========================================`n"
    
    FileAppend(resultMsg, ErrorLogFile, "UTF-8")
    
    MsgBox(resultMsg, "测试完成", "Iconi")
}
