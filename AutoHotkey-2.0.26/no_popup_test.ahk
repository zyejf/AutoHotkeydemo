#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut "UTF-8"

; =================================================================
; 完全无弹窗的错误处理方案
; =================================================================

; 立即注册错误处理回调（必须在任何可能出错的代码之前）
OnError(HandleAllErrors, -1)

; 全局配置
global ErrorLog := A_ScriptDir "\no_popup_errors.log"
global SuppressAllPopups := true

; 初始化日志
InitErrorLog()

; =================================================================
; 主程序
; =================================================================
try {
    Main()
} catch as e {
    HandleAllErrors(e, "Exit")
}

Main() {
    global ErrorLog
    
    LogMessage("=== 开始测试（无弹窗模式） ===")
    
    ; 测试各种错误
    TestAllErrors()
    
    LogMessage("=== 测试完成 ===")
    ShowFinalResult()
}

; =================================================================
; 测试所有错误类型
; =================================================================
TestAllErrors() {
    ; 测试 1: 除零错误
    TestError("除零错误", () => (1 / 0))
    
    ; 测试 2: 索引错误
    TestError("索引错误", () => ([1, 2, 3][10]))
    
    ; 测试 3: 文件错误
    TestError("文件错误", () => FileRead("nonexistent.txt"))
    
    ; 测试 4: 正则错误
    TestError("正则错误", () => RegExMatch("test", "["))
    
    ; 测试 5: 类型错误
    TestError("类型错误", () => Integer("abc"))
    
    ; 测试 6: 方法错误
    TestError("方法错误", () => ({a: 1}.NonExistentMethod()))
    
    ; 测试 7: 属性错误
    TestError("属性错误", () => ({a: 1}.NonExistentProperty))
    
    ; 测试 8: 参数错误
    TestError("参数错误", () => Sqrt(-1))
    
    ; 测试 9: 值错误
    TestError("值错误", () => throw ValueError("测试"))
    
    ; 测试 10: 内存错误
    TestError("内存错误", () => throw MemoryError("测试"))
    
    ; 测试 11: 未设置错误
    TestError("未设置错误", () => throw UnsetError("测试"))
    
    ; 测试 12: 数组错误
    TestError("数组错误", () => ("test".Push("item")))
    
    ; 测试 13: 对象错误
    TestError("对象错误", () => (123.Property := "value"))
    
    ; 测试 14: 字符串错误
    TestError("字符串错误", () => StrLower(123))
    
    ; 测试 15: 数学错误
    TestError("数学错误", () => ("abc" + 123))
}

; =================================================================
; 测试单个错误
; =================================================================
TestError(name, func) {
    global ErrorLog
    
    LogMessage("`n测试: " name)
    
    try {
        func.Call()
        LogMessage("  ✗ 错误未触发")
    } catch as e {
        HandleAllErrors(e, "Exit")
        LogMessage("  ✓ 错误已捕获")
    }
}

; =================================================================
; 错误处理函数（关键：返回 1 抑制所有弹窗）
; =================================================================
HandleAllErrors(Thrown, Mode) {
    global ErrorLog, SuppressAllPopups
    
    try {
        ; 构建错误报告
        report := "----------------------------------------`n"
        report .= "时间: " A_Now "`n"
        report .= "模式: " Mode "`n"
        
        if IsObject(Thrown) {
            ; 错误类型
            if HasBase(Thrown, Error.Prototype)
                report .= "类型: " Type(Thrown) "`n"
            
            ; 错误消息
            if HasProp(Thrown, "Message")
                report .= "消息: " Thrown.Message "`n"
            
            ; 错误位置
            if HasProp(Thrown, "File")
                report .= "文件: " Thrown.File "`n"
            
            if HasProp(Thrown, "Line")
                report .= "行号: " Thrown.Line "`n"
            
            ; 调用堆栈
            if HasProp(Thrown, "Stack")
                report .= "堆栈:`n" Thrown.Stack "`n"
        } else {
            report .= "错误: " String(Thrown) "`n"
        }
        
        report .= "----------------------------------------`n"
        
        ; 写入日志
        FileAppend(report, ErrorLog, "UTF-8")
        
        ; 输出到调试器
        OutputDebug(report)
        
    } catch as e {
        ; 如果日志记录失败，输出到调试器
        OutputDebug("错误记录失败: " e.Message)
    }
    
    ; 关键：返回 1 抑制所有错误弹窗
    return 1
}

; =================================================================
; 辅助函数
; =================================================================
InitErrorLog() {
    global ErrorLog
    
    ; 确保目录存在
    SplitPath(ErrorLog, , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
    
    ; 清空日志
    if FileExist(ErrorLog)
        FileDelete(ErrorLog)
}

LogMessage(msg) {
    global ErrorLog
    
    try {
        FileAppend(msg "`n", ErrorLog, "UTF-8")
        OutputDebug(msg)
    } catch {
        OutputDebug("日志写入失败")
    }
}

ShowFinalResult() {
    global ErrorLog
    
    ; 读取日志内容
    try {
        content := FileRead(ErrorLog)
        lineCount := StrSplit(content, "`n").Length
        
        resultMsg := "测试完成！`n`n"
        resultMsg .= "日志文件: " ErrorLog "`n"
        resultMsg .= "日志行数: " lineCount "`n`n"
        resultMsg .= "所有错误已被捕获，无弹窗！"
        
        ; 使用 ToolTip 而不是 MsgBox（避免弹窗）
        ToolTip(resultMsg)
        SetTimer(() => ToolTip(), -3000)  ; 3秒后消失
        
    } catch {
        OutputDebug("无法读取日志")
    }
}
