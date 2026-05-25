<!-- Generated: 2026-03-24T20:45:00+08:00 | Updated: 2026-05-01T12:00:00+08:00 -->

# AutoHotkey v2 技能管理器 v3.0

## Purpose

AutoHotkey v2 技能管理器 - 支持多种执行模式的按键连招管理系统。v3.0 采用**严格 DDD 四层架构**重构。

## Key Files

| File                          | Description                                 |
| ----------------------------- | ------------------------------------------- |
| `main.ahk`                    | 主入口 + 依赖注入 + 初始化                        |
| `asd.ahk`                     | 兼容别名入口 → `#Include "main.ahk"`            |
| `config.json`                 | 运行时配置文件                                   |
| `presentation/app_ui.html`    | WebView2 现代化 GUI 界面（HTML/CSS/JS）         |
| `presentation/webview2_manager.ahk` | WebView2 表现层管理器 + AHK-JS Bridge    |
| `equipment_recognizer.ahk`    | 装备属性识别模块（含OCR，外围模块）                      |
| `ocr.ahk`                     | OCR 封装模块（外围模块）                            |
| `joystick_tester.ahk`         | 摇杆测试器模块（外围模块）                            |

## Architecture (DDD)

| Layer            | Directory          | Modules                                     |
| ---------------- | ------------------ | ------------------------------------------- |
| 领域层 (domain)     | `domain/`          | `interfaces`, `skill_group`, `skill_manager`, `mode_registry` |
| 基础设施层 (infra)    | `infrastructure/`  | `config_store`, `json_parser`, `json_serializer`, `config_validator`, `debug_logger`, `json_logger`, `error_system`, `error_handler`, `backup_core`, `utils`, `ipc_channel` |
| 应用层 (application) | `application/`     | `group_service`, `config_service`           |
| 表现层 (presentation) | `presentation/`    | `webview2_manager`, `ui_manager`, `gui_manager`, `group_editor`, `backup_ui`, `debug_panel` |
| 测试层 (tests)       | `tests/`           | `test_domain`, `test_infrastructure`, `test_application`, `test_presentation`, `test_webview2_bridge`, `test_boundary`, `test_error_captor`, `test_error_system`, `test_integration_error_system`, `test_result_reporter`, `run_all_tests`, `run_tests`, `AutoHotUnit`, `run_tests.ps1` |

## Subdirectories

| Directory        | Purpose                                |
| ---------------- | -------------------------------------- |
| `docs/`          | 技术文档（架构/开发指南/部署/API参考）              |
| `logs/`          | 日志文件（`app.log` / `debug.log`）         |
| `backups/`       | 配置备份文件                                |
| `config_backup/` | 配置备份目录（遗留）                            |

## For AI Agents

### Working In This Directory

- **⚠️ 强制：所有 .ahk 文件顶部必须包含以下警告/错误接管指令（在 `#Requires` 之后、任何代码之前）：**
  ```autohotkey
  #Requires AutoHotkey v2.0
  #ErrorStdOut "UTF-8"          ; 加载时错误重定向到标准输出，不弹窗
  #Warn VarUnset, OutputDebug   ; 未赋值变量警告 → OutputDebug，不弹窗
  #Warn Unreachable, OutputDebug ; 不可达代码警告 → OutputDebug，不弹窗
  #Warn LocalSameAsGlobal, OutputDebug ; 局部与全局同名警告 → 不弹窗
  ```
- **⚠️ 强制：主入口文件（main.ahk / asd.ahk）必须设置 `OnError` 全局回调接管运行时错误：**
  ```autohotkey
  OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))
  ; 返回 true 阻止默认错误对话框弹出
  ```
- **⚠️ 强制：以上规则适用于项目中所有 .ahk 文件，包括 domain/、infrastructure/、application/、presentation/、tests/ 目录下的所有文件，无例外**
- 所有 GUI 控件位置参数必须用双引号包围
- Button 控件使用 `.Text` 属性设置文本
- 日志级别：ERROR/WARNING/DEBUG（不使用 INFO）
- 配置更改后调用 `ConfigService.SaveConfig()` 持久化
- 周期性键必须使用独立触发时间，不能用 `Mod(A_TickCount, interval)`
- 定时器引用必须存储在 `_timers` Map 中，确保能正确停止
- 热路径日志（Execute\* 方法）会自动限速，每秒最多记录一次
- 模块文件顶部必须包含 `#Requires AutoHotkey v2.0`
- 主脚本使用 `#Include` 引入模块

### Testing Requirements

- 运行语法检查: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk`
- 启动脚本: `"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" asd.ahk`
- 查看调试日志（实时）: `Get-Content logs\debug.log -Tail 20 -Wait`
- 查看应用日志: `Get-Content logs\app.log -Tail 10`
- 过滤错误日志: `Select-String -Path logs\app.log -Pattern '"level":"ERROR"'`

### 错误与警告接管机制（⚠️ 强制，无例外）

#### 错误分类

| 错误类型 | 触发时机 | 接管方式 | 退出码 |
|---------|---------|---------|-------|
| 加载时语法错误 | 脚本加载/解析阶段 | `#ErrorStdOut "UTF-8"` → stderr | 2 |
| 加载时警告（未赋值变量等） | 脚本加载阶段 | `#Warn VarUnset, OutputDebug` → OutputDebug | 0 |
| 运行时错误 | 脚本执行阶段 | `OnError` 回调 → 日志 | 0（回调返回 true 时） |
| 运行时警告 | 脚本执行阶段 | `#Warn Unreachable, OutputDebug` → OutputDebug | 0 |

#### 所有 .ahk 文件必须包含的接管指令

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"          ; 加载时语法错误 → stderr，不弹窗
#Warn VarUnset, OutputDebug   ; 未赋值变量警告 → OutputDebug，不弹窗
#Warn Unreachable, OutputDebug ; 不可达代码警告 → OutputDebug，不弹窗
#Warn LocalSameAsGlobal, Off  ; 局部与全局同名警告 → 关闭
```

#### 主入口文件额外必须包含

```autohotkey
OnError((e, mode) => (ErrorSystem.LogError(e.Message, "ERROR", "", 0), true))
; 返回 true 阻止默认错误对话框弹出
```

#### 测试文件额外必须包含

```autohotkey
OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message "`n", "*"), true))
; 测试文件中用 FileAppend 输出到 stdout，确保错误可被捕获
```

#### 测试文件前置检查流程（⚠️ 执行任何测试前必须完成）

**第一步：语法检查（检测加载时错误）**

```powershell
# 方法1：使用 /ErrorStdOut 命令行参数 + stderr 重定向
$proc = Start-Process -FilePath "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" `
    -ArgumentList "/ErrorStdOut","test_file.ahk" `
    -WorkingDirectory "D:\1demo\AutoHotkeydemo" `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardError "D:\1demo\AutoHotkeydemo\test_stderr.txt"
Write-Host "Exit code: $($proc.ExitCode)"
# 退出码 0 = 无语法错误，退出码 2 = 存在语法错误
Get-Content "test_stderr.txt"  # 查看具体错误信息
```

```powershell
# 方法2：使用管道重定向（适用于简单场景）
& "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut test_file.ahk 2>&1 | Select-Object -First 10
# 注意：/ErrorStdOut 将错误输出到 stderr，需要 2>&1 重定向到 stdout
```

**第二步：验证接管指令存在**

```powershell
# 检查文件是否包含必要的接管指令
$content = Get-Content "test_file.ahk" -Raw
if ($content -notmatch '#ErrorStdOut') { Write-Host "ERROR: 缺少 #ErrorStdOut 指令" }
if ($content -notmatch '#Warn VarUnset') { Write-Host "ERROR: 缺少 #Warn VarUnset 指令" }
if ($content -notmatch '#Warn Unreachable') { Write-Host "ERROR: 缺少 #Warn Unreachable 指令" }
if ($content -notmatch 'OnError') { Write-Host "ERROR: 缺少 OnError 回调" }
```

**第三步：运行时错误验证**

```powershell
# 启动测试并检查退出码和输出
$proc = Start-Process -FilePath "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe" `
    -ArgumentList "test_file.ahk" `
    -WorkingDirectory "D:\1demo\AutoHotkeydemo" `
    -NoNewWindow -Wait -PassThru
Write-Host "Exit code: $($proc.ExitCode)"
# 退出码 0 = 正常退出，退出码 2 = 加载时错误
# 运行时错误由 OnError 回调处理，退出码仍为 0
```

#### 退出码含义

| 退出码 | 含义 | 说明 |
|-------|------|------|
| 0 | 正常退出 | 脚本执行完毕或 `ExitApp` |
| 2 | 加载时错误 | 语法错误导致脚本无法启动 |
| 1 | 其他错误 | 一般性错误 |

#### ⚠️ 关键语法陷阱：箭头函数不支持块体

**AHK v2 的箭头函数 `=>` 只支持表达式体，不支持块体 `{ }`！**

```autohotkey
; ❌ 错误：箭头函数使用块体 — 会导致 "Missing propertyname: in object literal" 语法错误
someObj.then((result) => {
    DoSomething(result)
    DoAnotherThing()
})

; ✅ 正确：箭头函数使用表达式体（单行表达式）
someObj.then((result) => DoSomething(result))

; ✅ 正确：多语句用逗号表达式
someObj.then((result) => (DoSomething(result), DoAnotherThing()))

; ✅ 正确：使用闭包函数代替箭头函数块体
someObj.then(Func("MyCallback"))
MyCallback(result) {
    DoSomething(result)
    DoAnotherThing()
}
```

**特别说明：`.then()` 回调中的块体是重灾区！**

WebView2 的 `ExecuteScript().then()` 和 Promise 的 `.then()` 经常需要多行回调，
必须使用逗号表达式或闭包函数，**绝对不能**使用 `=> { }` 块体语法。

#### ⚠️ 关键语法陷阱：字符串拼接中的花括号

**AHK v2 在字符串拼接中，紧跟变量后的 `"..."` 会被解析为对象字面量的属性名！**

```autohotkey
; ❌ 错误：OB 后面的字符串被当作对象属性名
OB := "{"
CB := "}"
testJs := "try" OB "var x=1" CB "catch(e)" OB CB  ; 语法错误！

; ❌ 错误：Chr(123) 在拼接中同样触发对象字面量解析
testJs := "try" Chr(123) "var x=1" Chr(125)  ; 语法错误！

; ✅ 正确：使用 Format 函数
testJs := Format("try{1}var x=1{2}catch(e){1}{2}", "{", "}")

; ✅ 正确：使用单引号字符串（AHK v2 支持单引号字符串）
testJs := 'try{var x=1}catch(e){}'

; ✅ 正确：分步构建
testJs := "try"
testJs .= "{var x=1}"
testJs .= "catch(e){}"
```

#### 测试文件标准模板

```autohotkey
; =================================================================
; 测试模块名称 - 简要描述
; =================================================================
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "..\infrastructure\error_system.ahk"
#Include "..\infrastructure\json_logger.ahk"
; ... 其他必要的 #Include ...

OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))

; =================================================================
; 测试用例
; =================================================================

Test_SomeFeature() {
    try {
        ; 测试逻辑
        result := SomeModule.SomeMethod()
        if result {
            FileAppend("PASS: Test_SomeFeature`n", "*")
        } else {
            FileAppend("FAIL: Test_SomeFeature - unexpected result`n", "*")
        }
    } catch as e {
        FileAppend("ERROR: Test_SomeFeature - " e.Message "`n", "*")
    }
}

; =================================================================
; 执行测试
; =================================================================

FileAppend("=== Test Start ===`n", "*")
Test_SomeFeature()
FileAppend("=== Test End ===`n", "*")
```

#### 完整测试执行脚本（PowerShell）

```powershell
# test_runner.ps1 - 完整的 AHK 测试执行器
param([string]$TestFile)

$ahkPath = "D:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
$workDir = "D:\1demo\AutoHotkeydemo"
$stderrFile = Join-Path $workDir "test_stderr.txt"

# 第1步：验证文件存在
if (-not (Test-Path $TestFile)) {
    Write-Host "ERROR: Test file not found: $TestFile"
    exit 1
}

# 第2步：验证接管指令
$content = Get-Content $TestFile -Raw
$missing = @()
if ($content -notmatch '#ErrorStdOut') { $missing += "#ErrorStdOut" }
if ($content -notmatch '#Warn') { $missing += "#Warn" }
if ($content -notmatch 'OnError') { $missing += "OnError" }
if ($missing.Count -gt 0) {
    Write-Host "WARNING: Missing error handling directives: $($missing -join ', ')"
}

# 第3步：语法检查（加载时错误检测）
$proc = Start-Process -FilePath $ahkPath `
    -ArgumentList "/ErrorStdOut",$TestFile `
    -WorkingDirectory $workDir `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardError $stderrFile

if ($proc.ExitCode -eq 2) {
    Write-Host "SYNTAX ERROR detected (exit code 2):"
    Get-Content $stderrFile
    Remove-Item $stderrFile -ErrorAction SilentlyContinue
    exit 2
}
Remove-Item $stderrFile -ErrorAction SilentlyContinue

# 第4步：运行测试
$proc = Start-Process -FilePath $ahkPath `
    -ArgumentList $TestFile `
    -WorkingDirectory $workDir `
    -NoNewWindow -Wait -PassThru

Write-Host "Test exit code: $($proc.ExitCode)"
exit $proc.ExitCode
```

### Common Patterns

- 文件结构使用分节注释：`; =================================================================`
- 类名使用 PascalCase，方法名使用 PascalCase，静态属性使用 camelCase
- 使用 `HasProp()` 和 `_GetProp()` 兼容 Map 和 Object 访问
- 周期性触发使用独立触发时间而非 `Mod()`
- 使用 `Map()` 和 `SetTimer()` 管理状态和定时器
- 错误处理使用 `try-catch` 并记录 JSON 日志
- 配置数据使用全局 Map 结构

## Dependencies

### Internal

- 模块之间通过 `#Include` 引入
- `asd.ahk` 引入所有其他 .ahk 模块
- `infrastructure/json_parser.ahk` 提供 JSON 解析功能
- `infrastructure/json_serializer.ahk` 提供 JSON 序列化功能
- `presentation/webview2_manager.ahk` 提供 WebView2 GUI 和 AHK-JS Bridge
- `presentation/app_ui.html` WebView2 加载的 HTML 界面

### External

- WebView2 运行时（Edge Chromium 内核，Windows 10+ 内置）
- `lib/ahk2_lib/WebView2/` — thqby/ahk2_lib WebView2 封装库

### AHK-JS Bridge 通信架构（⚠️ 重要设计决策）

**核心问题：** `ExecuteScriptAsync` 使用 ICoreWebView2 原始接口，**不支持 Promise 等待**。所有 async/await 调用返回的 Promise 对象被 JSON 序列化为 `{}`。

**解决方案：** 使用 `WebMessage` 双向通信模式：

| 方向 | 方法 | 说明 |
|------|------|------|
| JS→AHK | `window.chrome.webview.postMessage(msg)` | JS 发送 JSON 消息到 AHK |
| AHK→JS | `wv.PostWebMessageAsJson(response)` | AHK 发送 JSON 响应到 JS |
| AHK 接收 | `wv.add_WebMessageReceived(handler)` | AHK 注册消息接收处理器 |
| JS 接收 | `window.chrome.webview.addEventListener("message", handler)` | JS 注册消息接收处理器 |

**通信流程：**

1. JS 调用 `ahkCall("GetGroupList")` → 生成 `{action, requestId}` → `postMessage()`
2. AHK `_OnWebMessageReceived` 解析 action → 调用对应 Bridge 方法 → `_SendResponse()`
3. AHK `_SendResponse()` 构造 `{requestId, result}` → `PostWebMessageAsJson()`
4. JS message handler 匹配 requestId → resolve Promise → 调用方收到结果

**⚠️ 禁止事项：**
- **禁止**通过 `ExecuteScriptAsync` 调用返回 Promise 的 JS 代码（结果必为 `{}`）
- **禁止**在 `ExecuteScriptAsync` 中使用 `async/await` IIFE
- **禁止**使用 `AddHostObjectToScript` 的 sync 代理（可能导致死锁）

**✅ 允许事项：**
- `ExecuteScriptAsync` 调用**同步** JS 函数（如 `updateDashboard(data)`）
- `InjectAhkComponent` 用于初始化 `window.ahk` 代理对象
- `PostWebMessageAsJson` / `postMessage` 用于所有需要返回值的通信

<!-- MANUAL: 手动添加的注意事项请放在这里，重新生成时将予以保留。 -->

## 构建/运行命令

### 运行脚本

```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" asd.ahk
```

### 语法检查

```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut asd.ahk
```

### 调试命令

```bash
# 查看调试日志（实时）
Get-Content logs\debug.log -Tail 20 -Wait

# 查看应用日志
Get-Content logs\app.log -Tail 10

# 过滤错误日志
Select-String -Path logs\app.log -Pattern '"level":"ERROR"'

# 清空日志文件（测试前）
Clear-Content logs\app.log
Clear-Content logs\debug.log
```

## 代码风格指南

### 文件结构

```autohotkey
; =================================================================
; 模块名称 - 简要描述
; =================================================================
#Requires AutoHotkey v2.0

; 第一部分: 常量/类定义
; 第二部分: 方法实现
; 第三部分: 初始化代码
```

### 导入规范

```autohotkey
#Requires AutoHotkey v2.0  ; 模块文件顶部必须包含
#Include "json.ahk"        ; 主脚本使用 #Include 引入模块
```

### 命名约定

| 类型   | 约定                    | 示例                                             |
| ---- | --------------------- | ---------------------------------------------- |
| 类名   | PascalCase            | `DebugLogger`, `SkillGroup`, `ConfigValidator` |
| 方法名  | PascalCase            | `Init()`, `Log()`, `Toggle()`                  |
| 静态属性 | camelCase             | `logFile`, `enabled`, `maxSize`                |
| 局部变量 | camelCase             | `currentChar`, `grpIdx`, `pressKeys`           |
| 全局变量 | PascalCase + `global` | `global GroupSettings`                         |
| 常量   | 全大写 + 下划线             | `JSONErrorType.FILE_READ_ERROR`                |
| 私有方法 | 下划线前缀                 | `_ExecutePeriodic()`, `_SetupMode()`           |

### 类结构

```autohotkey
class ClassName {
    static property := ""
    static controls := Map()

    static MethodName() {
        ; 实现
    }

    static _PrivateMethod() {
        ; 私有方法
    }
}
```

### 错误处理

```autohotkey
; 使用 try-catch 处理可能失败的操作
try {
    content := FileRead(path, "UTF-8")
} catch as e {
    JSONLogger.Log(JSONError(JSONErrorType.FILE_READ_ERROR, e.Message, 0, "", path))
    return false
}

; 验证输入
if (this.config.hotkey = "") {
    MsgBox("请输入热键", "错误", "Icon!")
    return false
}
```

### 日志系统

```autohotkey
; 普通调试日志
DebugLogger.Log("_ExecuteHybrid: START groups.Length=" this.groups.Length)

; 热路径日志会自动限速（每秒最多一次）
; 受限速的方法: _ExecuteHybrid, _ExecuteEnhancedHybrid, _ExecutePeriodic, _ExecuteEnhancedPeriodic

; JSON 结构化日志
JSONLogger.LogError("Module", JSONErrorType.ERROR_xxx, "消息")
```

### Map vs Object 访问规范（重要！）

```autohotkey
; Map 类型 - 使用 obj.Has(key) 和 obj[key]
if (obj is Map) {
    if obj.Has("groups") {
        val := obj["groups"]
    }
}

; Object 类型 - 使用 HasProp(obj, key) 和 obj.%key%
if (IsObject(obj) && HasProp(obj, "groups")) {
    val := obj.groups
}

; 通用安全获取 - 使用 _GetField() / _GetProp()
val := _GetProp(obj, "type", "periodic")  ; 兼容 Map 和 Object
```

### 周期性触发时间规范（重要！）

```autohotkey
; 错误: 使用 Mod() 导致所有键共享时间基准，倍数间隔会同步触发
if (Mod(A_TickCount, interval) < 50) { ... }

; 正确: 每个键独立触发时间
for i, key in this.pressKeys {
    if (!this._lastTriggerTimes.Has(i)) {
        this._lastTriggerTimes[i] := A_TickCount
    }
    interval := (i <= this.intervals.Length) ? this.intervals[i] : 50
    if (A_TickCount - this._lastTriggerTimes[i] >= interval) {
        this._SendKey(key)
        this._lastTriggerTimes[i] := A_TickCount
    }
}

; 组内周期性键 - 使用 "grpIdx.keyIdx" 格式
triggerKey := grpIdx "." i
lastTime := this._groupTriggerTimes.Has(triggerKey) ? this._groupTriggerTimes[triggerKey] : A_TickCount
```

### 定时器管理规范（重要！）

```autohotkey
; 定时器引用必须存储，以便正确停止
class SkillManager {
    static _timers := Map()  ; 存储定时器引用

    static _StartGroupExecution(id) {
        ; ... 创建执行器 ...
        this._timers[id] := SetTimer(boundExecutor, -10)
    }

    static _StopGroupExecution(id) {
        if this._timers.Has(id) {
            SetTimer(this._timers[id], 0)  ; 取消定时器
            this._timers.Delete(id)
        }
    }
}
```

### GUI 控件规范

```autohotkey
; 控件创建 - 位置参数必须用引号
this.controls["btnOK"] := this.gui.Add("Button", "x20 y30 w100 h35", "确定")

; Button 控件使用 .Text 属性而非 .Value
this.controls["btnToggle"].Text := "🐛 调试日志: 开启"

; 事件绑定 - 无参数使用 (*) =>
this.controls["btnOK"].OnEvent("Click", (*) => this._ApplyChanges())

; 事件绑定 - 带参数使用闭包
this.controls["btnDel"].OnEvent("Click", ((id) => (*) => this._Delete(id))(itemId))
```

### Switch 语句

```autohotkey
switch mode {
    case "periodic":
        result := this._ExecutePeriodic()
    case "sequence":
        result := this._ExecuteSequence()
    default:
        result := 10  ; 注意: default 分支不能用 { }
}
```

### 数据结构约定

```autohotkey
; 分组配置 - groups 数组格式
groups := [
    {type: "periodic", pressKeys: ["Space"], intervals: [50]},
    {type: "sequence", pressKeys: ["1", "2"], delays: [100, 100], seqInterval: 100}
]

; 配置数据
config := {
    hotkey: "F1",
    mode: "enhanced_periodic",
    pressKeys: ["space", "1", "2"],
    intervals: [50, 100, 100],
    holdKeys: ["Shift"],
    holdMode: "continuous"
}
```

## 支持的执行模式

| 模式                  | 说明    | 必需字段                       |
| ------------------- | ----- | -------------------------- |
| `periodic`          | 周期性按键 | `keys`, `intervals`        |
| `sequence`          | 序列按键  | `keys`, `delays`           |
| `hybrid`            | 混合模式  | `groups` 数组                |
| `hold`              | 长按模式  | `holdKeys`, `holdDuration` |
| `enhanced_periodic` | 增强周期性 | `pressKeys`, `intervals`   |
| `enhanced_sequence` | 增强序列  | `pressKeys`, `pressDelays` |
| `enhanced_hybrid`   | 增强混合  | `groups` 数组                |

## 常见问题

### 日志文件位置

- 主日志: `logs/app.log` (JSON Lines 格式)
- 调试日志: `logs/debug.log` (详细执行追踪)
- JSON 错误: `logs/json_errors.log`

### 常见错误

1. **Map 属性访问错误**: `config.groups` 对 Map 无效，应使用 `config["groups"]` 或 `_GetProp()`
2. **控件位置参数错误**: `"x20 y30"` 必须有引号，`x20 y30` 是语法错误
3. **Button.Value 错误**: Button 控件应使用 `.Text` 属性，而非 `.Value`
4. **变量作用域**: 函数内访问全局变量需要 `global` 声明；AHK 变量名不区分大小写
5. **数组越界**: 访问数组前检查 `i <= arr.Length`
6. **OnEvent 静态方法引用**: `gui.OnEvent("Size", ClassName._OnResize)` 不能直接传递静态方法引用，必须用闭包包装：`gui.OnEvent("Size", (a,b,c,d) => ClassName._OnResize(a,b,c,d))`
7. **WebView2 await2 阻塞**: `WebView2.CreateControllerAsync().await2()` 需要消息循环运行，不能在同步初始化流程中直接调用，必须用 `SetTimer` 延迟执行
8. **Map.Delete 不存在的键**: `Map.Delete(key)` 在键不存在时抛出异常，必须先 `Map.Has(key)` 检查
9. **ExecuteScriptAsync 不等待 Promise**: `wv.ExecuteScriptAsync('Promise.resolve(42)')` 返回 `{}`，不是 `42`。必须使用 WebMessage 模式
10. **WebView2 sync 代理死锁**: `hostObjects.sync.ahk.Method()` 在 AHK 消息循环中被调用时会死锁，必须使用 postMessage 模式
9. **⚠️ 箭头函数块体语法错误（致命）**: AHK v2 的箭头函数 `=>` 只支持表达式体，**不支持块体 `{ }`**！使用 `(args) => { ... }` 会导致 "Missing propertyname: in object literal" 语法错误。必须使用逗号表达式 `(expr1, expr2, expr3)` 或闭包函数替代。
10. **⚠️ 字符串拼接中的花括号解析错误**: 在字符串拼接中，紧跟变量后的字符串字面量会被 AHK v2 解析为对象字面量的属性名。例如 `"try" OB "{" "code" CB "}"` 会报错。解决方案：使用 `Format()` 函数、单引号字符串 `'...'`、或分步构建。

## 重要提醒

- 所有 GUI 控件位置参数必须用双引号包围
- Button 控件使用 `.Text` 属性设置文本
- 日志级别：ERROR/WARNING/DEBUG（不使用 INFO）
- 配置更改后调用 `ExportConfigToJson()` 持久化
- 周期性键必须使用独立触发时间，不能用 `Mod(A_TickCount, interval)`
- 定时器引用必须存储在 `_timers` Map 中，确保能正确停止
- 热路径日志（Execute\* 方法）会自动限速，每秒最多记录一次
- **⚠️ 所有 .ahk 文件必须包含错误接管指令（详见 "错误与警告接管机制" 节），无例外**
- **⚠️ 加载时错误通过 `#ErrorStdOut "UTF-8"` 接管，运行时错误通过 `OnError` 回调接管**
- **⚠️ 箭头函数 `=>` 只支持表达式体，绝对不能使用 `=> { }` 块体语法**
- **⚠️ 执行测试前必须完成前置检查：语法检查（stderr 重定向 + 退出码验证）→ 接管指令验证 → 运行时验证**
- **⚠️ 语法检查必须使用 `Start-Process -RedirectStandardError` 或 `2>&1` 重定向 stderr，否则无法捕获 `#ErrorStdOut` 输出的错误**
- 使用中文回复

