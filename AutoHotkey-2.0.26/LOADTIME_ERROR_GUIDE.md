# AutoHotkey v2 加载时错误处理指南

## 问题说明

用户遇到的问题：
```
Error: Unexpected operator following literal string. 
Specifically: + 123 
064: result := "abc" + 123
The program will exit.
```

这是一个**加载时错误**（语法错误），在脚本加载阶段就被检测到，`OnError` 无法捕获。

---

## 错误类型对比

| 错误类型 | 检测时机 | OnError 能否捕获 | 处理方法 |
|---------|---------|-----------------|---------|
| **加载时错误** | 脚本加载阶段 | ❌ 不能 | `/ErrorStdOut` 参数 |
| **运行时错误** | 脚本执行阶段 | ✅ 能 | `OnError` 函数 |

---

## 加载时错误示例

### 1. 语法错误
```autohotkey
result := "abc" + 123  ; 类型不匹配
```

### 2. 无效表达式
```autohotkey
result := 1 + + 1  ; 双重运算符
```

### 3. 未闭合的字符串
```autohotkey
str := "test  ; 缺少右引号
```

### 4. 无效的变量名
```autohotkey
1abc := 123  ; 变量名不能以数字开头
```

---

## 解决方案

### 方案 1：使用命令行参数 `/ErrorStdOut`

**方法 1：重定向到文件**
```bash
AutoHotkey.exe /ErrorStdOut "script.ahk" 2>error.log
```

**方法 2：管道输出**
```bash
AutoHotkey.exe /ErrorStdOut "script.ahk" 2>&1 | clip
```

**方法 3：使用批处理文件**
```batch
@echo off
AutoHotkey.exe /ErrorStdOut "%1" 2>"%~dpn1_error.log"
```

---

### 方案 2：使用 PowerShell 包装器

```powershell
# run_ahk_silent.ps1
param([string]$ScriptPath)

$AHK = "AutoHotkey.exe"
$ErrorLog = "$ScriptPath.error.log"

# 运行脚本并捕获 stderr
$process = Start-Process -FilePath $AHK `
    -ArgumentList "/ErrorStdOut", $ScriptPath `
    -RedirectStandardError $ErrorLog `
    -Wait -NoNewWindow -PassThru

# 检查错误
if (Test-Path $ErrorLog) {
    $error = Get-Content $ErrorLog -Raw
    if ($error.Trim() -ne "") {
        Write-Host "Error: $error"
    }
}
```

---

### 方案 3：修改源代码（高级）

**文件**: `source/error.cpp`

**函数**: `ShowError()` (第 655 行)

**修改方法**:
```cpp
// 在 ShowError() 函数开头添加
if (g_NoErrorDialog) {
    // 输出错误到 stderr
    fprintf(stderr, "%s", error_message);
    return;
}
```

**编译选项**:
- 定义 `NO_ERROR_DIALOG` 宏
- 重新编译 AutoHotkey

---

## 完整解决方案

### 步骤 1：创建启动脚本

**文件**: `run_ahk_no_popup.bat`
```batch
@echo off
setlocal

set AHK_EXE=AutoHotkey.exe
set SCRIPT=%1
set ERROR_LOG=%~dpn1_error.log

if "%SCRIPT%"=="" (
    echo Usage: run_ahk_no_popup.bat script.ahk
    exit /b 1
)

REM 运行脚本，捕获所有错误
"%AHK_EXE%" /ErrorStdOut "%SCRIPT%" 2>"%ERROR_LOG%"

REM 检查是否有错误
if exist "%ERROR_LOG%" (
    for %%A in ("%ERROR_LOG%") do if %%~zA gtr 0 (
        echo Error detected:
        type "%ERROR_LOG%"
        exit /b 1
    )
)

exit /b 0
```

### 步骤 2：在脚本中添加错误处理

**文件**: `your_script.ahk`
```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"  ; 加载时错误输出到 stderr

; 注册运行时错误处理
OnError(LogError, -1)

global LogFile := A_ScriptDir "\errors.log"

; 主程序
try {
    Main()
} catch as e {
    LogError(e, "Exit")
}

Main() {
    ; 你的代码...
}

; 错误处理函数
LogError(Thrown, Mode) {
    global LogFile
    
    try {
        ; 记录错误
        msg := "Error: " (IsObject(Thrown) && HasProp(Thrown, "Message") ? Thrown.Message : String(Thrown))
        FileAppend(msg "`n", LogFile, "UTF-8")
    } catch {
        OutputDebug("Error")
    }
    
    return 1  ; 抑制运行时错误弹窗
}
```

### 步骤 3：使用启动脚本运行

```bash
run_ahk_no_popup.bat your_script.ahk
```

---

## 测试验证

### 测试 1：加载时错误

**脚本**: `test_loadtime.ahk`
```autohotkey
result := "abc" + 123  ; 语法错误
```

**运行**:
```bash
run_ahk_no_popup.bat test_loadtime.ahk
```

**预期结果**:
- 不显示错误弹窗
- 错误信息写入 `test_loadtime_error.log`

---

### 测试 2：运行时错误

**脚本**: `test_runtime.ahk`
```autohotkey
#Requires AutoHotkey v2.0
OnError(LogError, -1)

result := 1 / 0  ; 运行时错误

LogError(Thrown, Mode) {
    FileAppend("Error: " Thrown.Message "`n", "error.log", "UTF-8")
    return 1
}
```

**运行**:
```bash
run_ahk_no_popup.bat test_runtime.ahk
```

**预期结果**:
- 不显示错误弹窗
- 错误信息写入 `error.log`

---

## 注意事项

### 1. `/ErrorStdOut` 的限制

- 只对加载时错误有效
- 不对运行时错误有效
- 需要通过命令行参数使用

### 2. AutoHotkey 不是控制台程序

- stderr 输出不会直接显示
- 需要通过重定向或管道捕获

### 3. OnError 的限制

- 只能捕获运行时错误
- 不能捕获加载时错误
- 必须在脚本加载后才能注册

---

## 最佳实践

### 完整的错误处理流程

```
1. 使用 /ErrorStdOut 参数运行脚本
   ↓
2. 捕获加载时错误到日志文件
   ↓
3. 脚本加载成功后，OnError 生效
   ↓
4. 捕获运行时错误到日志文件
   ↓
5. 所有错误都记录到日志，无弹窗
```

### 推荐配置

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"  ; 加载时错误

OnError(LogError, -1)  ; 运行时错误

; 统一的错误日志
global ErrorLog := A_ScriptDir "\logs\all_errors.log"
```

---

## 总结

### ✅ 完全无弹窗的方案

1. **加载时错误**: 使用 `/ErrorStdOut` 参数 + 重定向
2. **运行时错误**: 使用 `OnError` 函数 + 返回 1
3. **统一日志**: 所有错误输出到同一个日志文件

### 📝 关键要点

- 加载时错误和运行时错误需要不同的处理方法
- `/ErrorStdOut` 必须通过命令行参数使用
- `OnError` 只能捕获运行时错误
- 两者结合才能实现完全无弹窗

---

## 参考资源

- AutoHotkey 官方文档: [/ErrorStdOut](https://www.autohotkey.com/docs/v2/lib/_ErrorStdOut.htm)
- AutoHotkey 官方文档: [OnError](https://www.autohotkey.com/docs/v2/lib/OnError.htm)
- 源代码: `source/error.cpp`
