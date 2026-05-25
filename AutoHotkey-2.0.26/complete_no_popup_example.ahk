#Requires AutoHotkey v2.0
#SingleInstance Force

; =================================================================
; 完整错误处理示例 - 无弹窗版本
; =================================================================

; 注册运行时错误处理
OnError(LogError, -1)

global LogFile := A_ScriptDir "\logs\all_errors.log"

; 初始化
Init()

; 主程序
try {
    Main()
} catch as e {
    LogError(e, "Exit")
}

; =================================================================
; 初始化
; =================================================================
Init() {
    global LogFile
    
    ; 确保日志目录存在
    SplitPath(LogFile, , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
    
    ; 写入启动日志
    FileAppend("========================================`n", LogFile, "UTF-8")
    FileAppend("脚本启动: " A_Now "`n", LogFile, "UTF-8")
    FileAppend("========================================`n`n", LogFile, "UTF-8")
}

; =================================================================
; 主程序
; =================================================================
Main() {
    global LogFile
    
    FileAppend("主程序开始执行`n`n", LogFile, "UTF-8")
    
    ; 测试运行时错误
    TestRuntimeErrors()
    
    FileAppend("`n主程序执行完成`n", LogFile, "UTF-8")
    
    ; 显示结果
    ShowResult()
}

; =================================================================
; 测试运行时错误
; =================================================================
TestRuntimeErrors() {
    global LogFile
    
    FileAppend("测试运行时错误:`n", LogFile, "UTF-8")
    
    ; 测试 1: 除零错误
    TestError("除零错误", () => (1 / 0))
    
    ; 测试 2: 索引错误
    TestError("索引错误", () => ([1, 2, 3][10]))
    
    ; 测试 3: 文件错误
    TestError("文件错误", () => FileRead("nonexistent.txt"))
    
    ; 测试 4: 类型错误
    TestError("类型错误", () => Integer("abc"))
    
    ; 测试 5: 值错误
    TestError("值错误", () => Sqrt(-1))
}

; =================================================================
; 测试单个错误
; =================================================================
TestError(name, func) {
    global LogFile
    
    FileAppend("  " name ": ", LogFile, "UTF-8")
    
    try {
        func.Call()
        FileAppend("✗ 未触发`n", LogFile, "UTF-8")
    } catch as e {
        LogError(e, "Exit")
        FileAppend("✓ 已捕获`n", LogFile, "UTF-8")
    }
}

; =================================================================
; 错误处理函数
; =================================================================
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        msg := ""
        
        if IsObject(Thrown) {
            if HasBase(Thrown, Error.Prototype)
                msg .= Type(Thrown) ": "
            
            if HasProp(Thrown, "Message")
                msg .= Thrown.Message
        } else {
            msg .= String(Thrown)
        }
        
        FileAppend(msg, LogFile, "UTF-8")
        
    } catch {
        OutputDebug("Error")
    }
    
    return 1  ; 抑制错误弹窗
}

; =================================================================
; 显示结果
; =================================================================
ShowResult() {
    global LogFile
    
    ; 读取日志
    try {
        content := FileRead(LogFile)
        lines := StrSplit(content, "`n").Length
        
        resultMsg := "测试完成！`n`n"
        resultMsg .= "日志文件: " LogFile "`n"
        resultMsg .= "日志行数: " lines "`n`n"
        resultMsg .= "所有错误已被捕获，无弹窗！"
        
        ; 使用 ToolTip 显示（不弹窗）
        ToolTip(resultMsg)
        SetTimer(() => ToolTip(), -5000)
        
    } catch {
        OutputDebug("无法读取日志")
    }
}
