# AutoHotkey v2 错误捕获机制调研报告

## Why

用户需要了解如何捕获 AutoHotkey v2 的错误弹出窗口信息，要求不弹窗，把错误信息输出到日志中。本调研报告总结了 AutoHotkey v2 的错误处理机制和实现方法。

## What Changes

本调研报告涵盖以下内容：

- AutoHotkey v2 错误处理机制分析
- OnError 函数的使用方法
- #ErrorStdOut 指令的使用方法
- try-catch 错误处理模式
- 源代码层面的错误处理流程
- 已有错误日志系统分析
- 最佳实践建议

## Impact

- 受影响的规范：错误处理规范
- 受影响的代码：错误日志系统、错误捕获模块

## 调研结果

### 1. AutoHotkey v2 错误类型

AutoHotkey v2 有两种主要错误类型：

#### 1.1 加载时错误 (Load-time Errors)

- **定义**：脚本加载阶段的语法错误
- **特点**：阻止脚本运行
- **处理方法**：`#ErrorStdOut` 指令或 `/ErrorStdOut` 命令行参数
- **限制**：`OnError` 无法捕获加载时错误

#### 1.2 运行时错误 (Runtime Errors)

- **定义**：脚本执行过程中发生的错误
- **特点**：可以被 try-catch 捕获，或由 OnError 处理
- **处理方法**：`OnError` 函数、try-catch 块
- **分类**：
  - 可继续错误 (Return)：线程可以继续执行
  - 不可继续错误 (Exit)：线程终止
  - 关键错误 (ExitApp)：程序终止

### 2. OnError 函数详解

#### 2.1 基本用法

```autohotkey
OnError(Callback, AddRemove)
```

**参数说明**：
- `Callback`：回调函数，接收两个参数：
  1. `Thrown`：抛出的值（通常是 Error 对象）
  2. `Mode`：错误模式（Return、Exit、ExitApp）
- `AddRemove`：
  - `1`：在之前注册的回调之后调用（默认）
  - `-1`：在之前注册的回调之前调用
  - `0`：取消注册

#### 2.2 回调函数返回值

| 返回值 | 效果 |
|--------|------|
| `0`、`""` 或无返回值 | 正常继续错误处理流程 |
| `1` | **抑制错误弹窗**和剩余回调 |
| `-1` | 抑制弹窗，如果 Mode 包含 "Return" 则继续执行线程 |

#### 2.3 完整示例

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force

; 注册错误处理回调（-1 表示优先调用）
OnError(LogError, -1)

; 全局日志文件路径
global LogFile := A_ScriptDir "\logs\error_" A_YYYY A_MM A_DD ".log"

Main()

Main() {
    ; 主程序逻辑
    try {
        ; 可能出错的代码
        result := 1 / 0
    } catch as e {
        ; 手动捕获的错误
        LogError(e, "Exit")
    }
}

; 错误处理回调函数
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        ; 确保日志目录存在
        SplitPath(LogFile, , &logDir)
        if !DirExist(logDir)
            DirCreate(logDir)
        
        ; 构建错误信息
        errorMsg := "========================================`n"
        errorMsg .= "Timestamp: " A_Now "`n"
        errorMsg .= "Mode: " Mode "`n"
        errorMsg .= "----------------------------------------`n"
        
        if IsObject(Thrown) {
            if HasProp(Thrown, "Message")
                errorMsg .= "Message: " Thrown.Message "`n"
            if HasProp(Thrown, "What")
                errorMsg .= "What: " Thrown.What "`n"
            if HasProp(Thrown, "File")
                errorMsg .= "File: " Thrown.File "`n"
            if HasProp(Thrown, "Line")
                errorMsg .= "Line: " Thrown.Line "`n"
            if HasProp(Thrown, "Extra")
                errorMsg .= "Extra: " Thrown.Extra "`n"
            if HasProp(Thrown, "Stack")
                errorMsg .= "Stack:`n" Thrown.Stack "`n"
        } else {
            errorMsg .= "Message: " String(Thrown) "`n"
        }
        
        errorMsg .= "========================================`n`n"
        
        ; 写入日志文件
        FileAppend(errorMsg, LogFile, "UTF-8")
        
        ; 可选：输出到调试器
        OutputDebug(errorMsg)
        
    } catch as e {
        OutputDebug("Failed to log error: " e.Message)
    }
    
    ; 返回 1 抑制错误弹窗
    return 1
}
```

### 3. #ErrorStdOut 指令详解

#### 3.1 基本用法

```autohotkey
#ErrorStdOut Encoding
```

**参数说明**：
- `Encoding`：可选，指定输出编码（如 "UTF-8"）
- 默认使用系统默认编码 (CP0)

#### 3.2 使用场景

**场景 1：脚本中添加指令**

```autohotkey
#ErrorStdOut "UTF-8"
; 脚本其余部分...
```

**场景 2：命令行参数**

```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "script.ahk" 2>error.log
```

**场景 3：管道输出**

```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "script.ahk" 2>&1 | clip
```

#### 3.3 限制

- **只对加载时错误有效**
- **不对运行时错误有效**
- 需要在脚本加载前设置

### 4. try-catch 错误处理模式

#### 4.1 基本模式

```autohotkey
try {
    ; 可能出错的代码
    content := FileRead("nonexistent.txt")
} catch as e {
    ; 错误处理
    LogError(e, "Exit")
}
```

#### 4.2 错误类型过滤

```autohotkey
try {
    ; 可能出错的代码
    result := SomeFunction()
} catch as e {
    if e is ValueError {
        ; 处理值错误
        HandleValueError(e)
    } else if e is TypeError {
        ; 处理类型错误
        HandleTypeError(e)
    } else {
        ; 处理其他错误
        HandleGenericError(e)
    }
}
```

#### 4.3 错误传播

```autohotkey
try {
    try {
        ; 内层可能出错的代码
        result := 1 / 0
    } catch as e {
        ; 内层处理
        throw e  ; 重新抛出
    }
} catch as e {
    ; 外层处理
    LogError(e, "Exit")
}
```

### 5. 源代码层面的错误处理流程

#### 5.1 错误处理流程图

```
错误发生
    ↓
CreateRuntimeException() - 创建异常对象
    ↓
SetThrownToken() - 设置抛出的令牌
    ↓
UnhandledException() - 未处理异常处理
    ↓
检查 mOnError.Count() - 是否有注册的回调
    ↓
[有回调] → 调用 OnError 回调
    ↓
[回调返回 1] → 抑制弹窗，返回 FAIL
[回调返回 0] → 继续正常处理
    ↓
[无回调或返回 0] → ShowError() - 显示错误弹窗
    ↓
DialogBoxParam() - 显示错误对话框
```

#### 5.2 关键源代码分析

**文件**：`source/error.cpp`

**关键函数**：

1. **UnhandledException()** (第 1065 行)
   - 处理未捕获的异常
   - 调用 OnError 回调
   - 根据回调返回值决定是否显示弹窗

2. **ShowError()** (第 655 行)
   - 显示错误弹窗
   - 创建错误对话框
   - 处理用户响应

3. **RuntimeError()** (第 251 行)
   - 处理运行时错误
   - 决定是抛出异常还是显示错误

**关键变量**：
- `mOnError`：存储 OnError 回调的列表 (MsgMonitorList 类型)
- `g.ThrownToken`：当前抛出的异常令牌
- `g.ExcptMode`：异常处理模式

#### 5.3 错误对象结构

**Error 对象属性**：
- `Message`：错误消息
- `What`：错误来源
- `File`：错误发生的文件
- `Line`：错误发生的行号
- `Extra`：额外信息
- `Stack`：调用堆栈

### 6. 已有错误日志系统分析

#### 6.1 error_logger.ahk 功能

项目中已有一个完整的错误日志系统 (`error_logger.ahk`)，提供以下功能：

- ✅ 完整错误捕获
- ✅ 无弹窗干扰（返回 1 抑制弹窗）
- ✅ 详细日志记录
- ✅ 日志轮转
- ✅ 灵活配置
- ✅ 调试支持

#### 6.2 使用方法

```autohotkey
#Requires AutoHotkey v2.0
#Include error_logger.ahk

; 初始化错误日志系统
ErrorLogger(A_ScriptDir "\logs\error.log", {
    MaxLogSize: 10485760,    ; 10MB
    MaxLogFiles: 10,          ; 保留10个文件
    DebugMode: true,          ; 启用调试模式
    LogToConsole: false       ; 不输出到控制台
})

; 主程序
Main()

Main() {
    try {
        ; 主逻辑
        ProcessData()
    } catch as e {
        ErrorLogger.LogError(e, "Exit")
    }
}
```

### 7. 最佳实践建议

#### 7.1 完整的错误处理策略

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force

; 1. 处理加载时错误
#ErrorStdOut "UTF-8"

; 2. 注册运行时错误处理
OnError(LogError, -1)

; 3. 初始化日志系统
InitErrorLogger()

Main()

Main() {
    try {
        ; 主逻辑
        ProcessData()
    } catch as e {
        LogError(e, "Exit")
    }
}

InitErrorLogger() {
    global LogFile := A_ScriptDir "\logs\error.log"
    
    ; 确保日志目录存在
    SplitPath(LogFile, , &logDir)
    if !DirExist(logDir)
        DirCreate(logDir)
}

LogError(Thrown, Mode) {
    global LogFile
    
    try {
        ; 构建错误信息
        errorMsg := FormatError(Thrown, Mode)
        
        ; 写入日志
        FileAppend(errorMsg, LogFile, "UTF-8")
        
        ; 输出到调试器
        OutputDebug(errorMsg)
        
    } catch {
        OutputDebug("Failed to log error")
    }
    
    ; 返回 1 抑制弹窗
    return 1
}

FormatError(Thrown, Mode) {
    errorMsg := "========================================`n"
    errorMsg .= "Timestamp: " A_Now "`n"
    errorMsg .= "Mode: " Mode "`n"
    errorMsg .= "----------------------------------------`n"
    
    if IsObject(Thrown) {
        if HasProp(Thrown, "Message")
            errorMsg .= "Message: " Thrown.Message "`n"
        if HasProp(Thrown, "File")
            errorMsg .= "File: " Thrown.File "`n"
        if HasProp(Thrown, "Line")
            errorMsg .= "Line: " Thrown.Line "`n"
        if HasProp(Thrown, "Stack")
            errorMsg .= "Stack:`n" Thrown.Stack "`n"
    } else {
        errorMsg .= "Message: " String(Thrown) "`n"
    }
    
    errorMsg .= "========================================`n`n"
    return errorMsg
}
```

#### 7.2 错误处理检查清单

- [ ] 使用 `#ErrorStdOut` 处理加载时错误
- [ ] 使用 `OnError` 注册错误处理回调
- [ ] 回调函数返回 `1` 抑制错误弹窗
- [ ] 在回调中记录详细的错误信息
- [ ] 使用 try-catch 处理预期的错误
- [ ] 确保日志目录存在
- [ ] 实现日志轮转机制
- [ ] 提供调试输出选项

#### 7.3 常见错误和解决方案

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 错误仍然显示弹窗 | OnError 回调未返回 1 | 确保回调返回 1 |
| 加载时错误无法捕获 | OnError 不处理加载时错误 | 使用 #ErrorStdOut |
| 日志文件无法创建 | 目录不存在或权限不足 | 创建目录并检查权限 |
| 错误信息不完整 | Error 对象属性缺失 | 使用 HasProp 检查属性 |
| 日志文件过大 | 未实现日志轮转 | 实现日志轮转机制 |

### 8. 总结

#### 8.1 核心要点

1. **OnError 函数**是捕获运行时错误的主要方法
2. **返回值 1** 可以完全抑制错误弹窗
3. **#ErrorStdOut** 用于处理加载时错误
4. **try-catch** 用于主动错误处理
5. **已有 error_logger.ahk** 提供了完整的解决方案

#### 8.2 推荐方案

**最佳实践**：结合使用多种方法

```autohotkey
; 1. 加载时错误处理
#ErrorStdOut "UTF-8"

; 2. 运行时错误处理
OnError(LogError, -1)

; 3. 主动错误处理
try {
    Main()
} catch as e {
    LogError(e, "Exit")
}
```

#### 8.3 参考资源

- AutoHotkey v2 官方文档：[OnError](https://www.autohotkey.com/docs/v2/lib/OnError.htm)
- AutoHotkey v2 官方文档：[#ErrorStdOut](https://www.autohotkey.com/docs/v2/lib/_ErrorStdOut.htm)
- 项目源代码：`source/error.cpp`
- 已有实现：`error_logger.ahk`
