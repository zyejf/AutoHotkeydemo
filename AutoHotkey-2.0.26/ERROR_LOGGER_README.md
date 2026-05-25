# AutoHotkey v2 错误日志系统使用指南

## 📋 概述

这是一个完整的、生产级别的错误日志系统，用于捕获 AutoHotkey v2 脚本中的所有错误并输出到日志文件，**完全抑制错误弹窗**。

## 🎯 核心特性

- ✅ **完整错误捕获**：捕获所有运行时错误和异常
- ✅ **无弹窗干扰**：自动抑制所有错误对话框
- ✅ **详细日志记录**：包含错误类型、位置、堆栈跟踪等完整信息
- ✅ **日志轮转**：自动管理日志文件大小，防止日志文件过大
- ✅ **灵活配置**：支持多种配置选项
- ✅ **调试支持**：可选的调试模式和控制台输出

## 🚀 快速开始

### 1. 基本使用

将 `error_logger.ahk` 文件放在您的脚本目录中，然后在您的脚本开头添加：

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

; 您的脚本代码
Main()

Main() {
    try {
        ; 您的主要逻辑
        MsgBox("Hello, World!")
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
    }
}
```

### 2. 自定义配置

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

; 自定义错误日志系统
ErrorLogger("D:\MyLogs\app_errors.log", {
    MaxLogSize: 5242880,      ; 5MB
    MaxLogFiles: 20,           ; 保留20个日志文件
    DebugMode: true,           ; 启用调试模式
    LogToConsole: false        ; 不输出到控制台
})

; 您的脚本代码
Main()
```

## 📝 使用示例

### 示例1：捕获除零错误

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

Main()

Main() {
    ErrorLogger.Log("INFO", "开始计算")
    
    try {
        result := 10 / 0  ; 这会触发除零错误
        MsgBox("结果: " result)
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        MsgBox("计算出错，请查看日志文件")
    }
}
```

### 示例2：捕获文件操作错误

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

Main()

Main() {
    ErrorLogger.Log("INFO", "读取配置文件")
    
    try {
        config := FileRead("config.txt")
        MsgBox("配置内容: " config)
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
        MsgBox("无法读取配置文件")
    }
}
```

### 示例3：捕获自定义错误

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

Main()

Main() {
    try {
        ValidateUserInput("")
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
    }
}

ValidateUserInput(input) {
    if (StrLen(input) = 0) {
        throw ValueError("输入不能为空", -1, "ValidateUserInput")
    }
    return true
}
```

### 示例4：记录普通日志信息

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

Main()

Main() {
    ; 记录不同级别的日志
    ErrorLogger.Log("INFO", "应用程序启动")
    ErrorLogger.Log("DEBUG", "调试信息", {User: "Admin", Action: "Login"})
    ErrorLogger.Log("WARNING", "磁盘空间不足")
    
    ; 您的业务逻辑
    ProcessData()
    
    ErrorLogger.Log("INFO", "应用程序结束")
}

ProcessData() {
    ErrorLogger.Log("DEBUG", "开始处理数据")
    ; 处理逻辑...
    ErrorLogger.Log("DEBUG", "数据处理完成")
}
```

## ⚙️ 配置选项

### ErrorLogger 初始化参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `logFile` | String | `A_ScriptDir "\logs\error_" A_YYYY A_MM A_DD ".log"` | 日志文件路径 |
| `options.MaxLogSize` | Integer | 10485760 (10MB) | 单个日志文件最大大小（字节） |
| `options.MaxLogFiles` | Integer | 10 | 保留的日志文件数量 |
| `options.DebugMode` | Boolean | false | 是否启用调试模式（输出到 OutputDebug） |
| `options.LogToConsole` | Boolean | false | 是否输出到控制台 |

### 配置示例

```autohotkey
; 最简配置
ErrorLogger()

; 自定义日志文件路径
ErrorLogger("D:\Logs\myapp.log")

; 完整配置
ErrorLogger("D:\Logs\myapp.log", {
    MaxLogSize: 2097152,       ; 2MB
    MaxLogFiles: 5,             ; 保留5个文件
    DebugMode: true,            ; 启用调试
    LogToConsole: true          ; 输出到控制台
})
```

## 📊 日志格式

### 错误日志格式

```
========================================
Timestamp: 20250111120530
Type: ZeroDivisionError
Mode: Exit
----------------------------------------
Message: Division by zero
What: Division
File: C:\Scripts\myapp.ahk
Line: 42
Stack:
  C:\Scripts\myapp.ahk (42) : Calculate
  C:\Scripts\myapp.ahk (38) : Main
========================================
```

### 普通日志格式

```
========================================
Timestamp: 20250111120530
Level: INFO
----------------------------------------
Message: Application started
File: myapp.ahk
Line: 15
Function: Main
========================================
```

## 🔧 高级功能

### 1. 日志轮转

当日志文件超过 `MaxLogSize` 时，系统会自动轮转日志文件：

```
error_20250111.log      (当前日志)
error_20250111.log.1    (第1个备份)
error_20250111.log.2    (第2个备份)
...
error_20250111.log.10   (第10个备份)
```

### 2. 清理旧日志

```autohotkey
; 清理30天前的日志文件
ErrorLogger.CleanOldLogs(A_ScriptDir "\logs", 30)
```

### 3. 获取日志统计

```autohotkey
stats := ErrorLogger.GetLogStats()
MsgBox("日志文件大小: " stats["Size"] " 字节`n"
     . "错误数量: " stats["ErrorCount"])
```

### 4. 手动记录日志

```autohotkey
; 记录信息日志
ErrorLogger.Log("INFO", "用户登录成功", {User: "Admin"})

; 记录警告日志
ErrorLogger.Log("WARNING", "内存使用率过高", {Usage: "85%"})

; 记录调试日志
ErrorLogger.Log("DEBUG", "变量值", {Var1: value1, Var2: value2})
```

## 🎨 最佳实践

### 1. 在脚本入口处初始化

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

; 尽早初始化错误日志系统
ErrorLogger()

; 主程序入口
try {
    Main()
} catch as e {
    ErrorLogger.LogError(e, "Exit")
    MsgBox("程序出错，请查看日志: " ErrorLogger.LogFile)
}
```

### 2. 为关键操作添加日志

```autohotkey
ProcessFile(filePath) {
    ErrorLogger.Log("DEBUG", "开始处理文件", {File: filePath})
    
    try {
        content := FileRead(filePath)
        ; 处理内容...
        ErrorLogger.Log("DEBUG", "文件处理完成")
    } catch as e {
        ErrorLogger.Log("ERROR", "文件处理失败", {File: filePath, Error: e.Message})
        throw e
    }
}
```

### 3. 使用结构化的额外信息

```autohotkey
; 不推荐
ErrorLogger.Log("INFO", "用户 " userName " 执行了 " action)

; 推荐
ErrorLogger.Log("INFO", "用户操作", {User: userName, Action: action})
```

### 4. 定期清理日志

```autohotkey
; 在脚本启动时清理旧日志
ErrorLogger()
ErrorLogger.CleanOldLogs(, 30)  ; 保留最近30天
```

## 🐛 故障排除

### 问题1：日志文件无法创建

**原因**：日志目录权限不足或路径不存在

**解决**：
```autohotkey
; 确保日志目录存在
logDir := A_ScriptDir "\logs"
if !DirExist(logDir)
    DirCreate(logDir)

ErrorLogger(logDir "\error.log")
```

### 问题2：错误仍然显示弹窗

**原因**：OnError 回调未正确注册

**解决**：
```autohotkey
; 确保在脚本最开始初始化
ErrorLogger()

; 或手动注册
OnError(ErrorLogger.LogError.Bind(ErrorLogger), -1)
```

### 问题3：日志文件过大

**原因**：MaxLogSize 设置过大或日志轮转未启用

**解决**：
```autohotkey
ErrorLogger(, {
    MaxLogSize: 1048576,  ; 1MB
    MaxLogFiles: 5
})
```

## 📚 API 参考

### ErrorLogger 类

#### 静态方法

- `Call(logFile?, options?)` - 初始化错误日志系统
- `LogError(Thrown, Mode)` - 记录错误（由 OnError 自动调用）
- `Log(level, message, extra?)` - 记录普通日志
- `CleanOldLogs(logDir?, daysToKeep?)` - 清理旧日志
- `GetLogStats()` - 获取日志统计信息
- `CheckLogRotation()` - 检查并执行日志轮转
- `RotateLog()` - 手动轮转日志

#### 静态属性

- `LogFile` - 当前日志文件路径
- `MaxLogSize` - 最大日志文件大小
- `MaxLogFiles` - 最大日志文件数量
- `DebugMode` - 调试模式开关
- `LogToConsole` - 控制台输出开关

## 📄 许可证

本错误日志系统基于 AutoHotkey v2 开发，可自由使用和修改。

## 🤝 贡献

欢迎提交问题和改进建议！

---

**版本**: 1.0.0  
**作者**: AutoHotkey 社区  
**最后更新**: 2025-01-11
