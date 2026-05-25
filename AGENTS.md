# AGENTS.md

## 项目概述

AutoHotkey v2 技能管理器 - 一个支持多种执行模式的按键连招管理系统，包含完整的 GUI 配置界面和 JSON 配置持久化。

## 技术栈

- **语言**: AutoHotkey v2.0
- **主要文件**:
  - `asd.ahk` - 主脚本入口
  - `json.ahk` - 自定义 JSON 解析器 + 日志系统
  - `gui.ahk` - GUI 模块
- **配置文件**: `config.json`

## 构建/运行命令

### 运行脚本

```bash
# 运行主脚本
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" asd.ahk



### 测试命令

```bash


# 验证 JSON 配置文件格式
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut /i asd.ahk  # 运行脚本会自动验证 config.json

# 运行单元测试方法（AHK v2 特定）
# 由于 AHK v2 没有内置测试框架，建议的测试方法：

# 1. 功能测试：手动通过 GUI 验证核心功能
# 2. 配置测试：创建测试配置文件验证导入/导出
# 3. 日志测试：检查 logs/ 目录下的日志文件是否正确记录
# 4. 边界测试：测试极值情况（如空配置、最大值等）

# 示例：验证配置导出功能
#   1. 修改 GUI 中的某个设置
#   2. 点击"应用"按钮
#   3. 检查 config.json 是否正确更新
#   4. 重启脚本验证新配置是否生效
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
Clear-Content logs\json_errors.log
```

## 代码风格指南

### 文件结构

```autohotkey
; =================================================================
; 模块名称 - 简要描述
; 版本: x.x
; 说明: 详细说明
; =================================================================

#Requires AutoHotkey v2.0

; 第一部分: 常量/类定义
; 第二部分: 方法实现
; 第三部分: 初始化代码
```

### 导入规范

```autohotkey
; 模块文件顶部必须包含
#Requires AutoHotkey v2.0

; 主脚本使用 #Include 引入模块
#Include "json.ahk"
#Include "gui.ahk"
```

### 命名约定

| 类型 | 约定 | 示例 |
|------|------|------|
| 类名 | PascalCase | `DebugLogger`, `JSONParser`, `ConfigValidator` |
| 方法名 | PascalCase | `Init()`, `Log()`, `ParseNumber()` |
| 静态属性 | camelCase | `logFile`, `enabled`, `maxSize` |
| 局部变量 | camelCase | `currentChar`, `hasDecimal`, `numStr` |
| 控件名称 | 引号字符串 | `this.controls["btnOK"]` |
| 全局变量 | PascalCase + `global` | `global GroupSettings` |
| 常量 | 全大写 + 下划线 | `JSONErrorType.FILE_READ_ERROR` |

### 类结构

```autohotkey
class ClassName {
    ; 静态属性
    static property := ""
    static controls := Map()
    
    ; 静态方法
    static MethodName() {
        ; 实现
    }
    
    ; 私有方法（下划线前缀）
    static _PrivateMethod() {
        ; 实现
    }
}
```

### 错误处理

```autohotkey
; 使用 try-catch 处理可能失败的操作
try {
    content := FileRead(path, "UTF-8")
} catch as e {
    JSONLogger.Log(JSONError(
        JSONErrorType.FILE_READ_ERROR,
        "读取文件失败: " e.Message,
        0, "", path
    ))
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
; DEBUG 日志
JSONLogger.LogDebug("Module", JSONErrorType.DEBUG_xxx, "消息")

; WARNING 日志
JSONLogger.LogWarning("Module", JSONErrorType.WARN_xxx, "消息")

; ERROR 日志
JSONLogger.LogError("Module", JSONErrorType.ERROR_xxx, "消息")
```

### JSON 处理规范

```autohotkey
; 安全获取属性（兼容Map和Object）
_GetProp(obj, key, default := "") {
    if (obj is Map)
        return obj.Has(key) ? obj[key] : default
    else if (HasProp(obj, key))
        return obj.%key%
    return default
}

; 安全设置属性
_SetProp(obj, key, value) {
    if (obj is Map)
        obj[key] := value
    else if (HasProp(obj, key))
        obj.%key% := value
}
```

### GUI 控件规范

```autohotkey
; 控件创建
this.controls["controlName"] := this.gui.Add("Type", "x y w h", "Text")

; 事件绑定 - 无参数使用 (*) =>
this.controls["btnOK"].OnEvent("Click", (*) => this._ApplyChanges())

; 事件绑定 - 带参数使用闭包
this.controls["btnDel"].OnEvent("Click", ((id) => (*) => this._Delete(id))(itemId))
```

### 控件位置参数

```autohotkey
; 正确格式 - 参数必须用引号包围
this.gui.Add("Button", "x20 y30 w100 h35", "确定")

; 错误格式 - 缺少引号会导致语法错误
this.gui.Add("Button", x20 y30 w100, "确定")  ; 错误!
```

### Switch 语句

```autohotkey
; 注意: default 分支不能使用花括号
switch mode {
    case "periodic":
        result := this._ExecutePeriodic()
    case "sequence":
        result := this._ExecuteSequence()
    default:
        result := 10  ; 不能用 { }
}
```

### Map 检查

```autohotkey
; 正确: 使用 Map.Has() 方法
if (this.controls.Has("btnAddKey")) {
    this.controls["btnAddKey"].Destroy()
}

; 错误: 不要使用 HasProp() 检查 Map
if (HasProp(this.controls, "btnAddKey"))  ; 错误!
```

### ComboBox 操作

```autohotkey
; 设置选择 - 使用 Choose()
keyCtrl.Choose(index)

; 获取值 - 使用 .Text 属性
key := keyCtrl.Text

; 注意: .Value 是只读的，不能用于设置
```

### 数据结构约定

```autohotkey
; 按键组数据
groupData := {
    type: "periodic",      ; 组类型
    keys: [                ; 按键数组
        {key: "Space", value: 50},
        {key: "1", value: 100}
    ],
    seqInterval: 100       ; 序列间隔
}

; 配置数据
config := {
    hotkey: "F1",
    mode: "enhanced_periodic",
    groups: [...],
    hold: {...}
}
```

## 常见问题解决

### 日志文件位置
- 主日志: `logs/app.log` (JSON Lines 格式)
- 调试日志: `logs/debug.log` (详细执行追踪)
- JSON 错误: `logs/json_errors.log` (JSON 解析错误)

### 日志查看命令

```bash
# 查看最新日志
Get-Content logs\app.log -Tail 20

# 过滤错误日志
Select-String -Path logs\app.log -Pattern '"level":"ERROR"'

# 查看调试日志
Get-Content logs\debug.log -Tail 50
```

### 常见错误处理

1. **JSON 解析失败**
   - 检查文件编码（应为 UTF-8 无 BOM）
   - 验证 JSON 结构是否有效
   - 确保数字格式正确（不带引号）

2. **控件未找到错误**
   - 确认控件名称精确匹配（区分大小写）
   - 验证控件是否已创建后再绑定事件

3. **类型转换错误**
   - 使用 `_GetProp()` 安全获取属性
   - 在转换前检查类型 (`is Integer`, `is String`)

## 开发工作流

1. **功能开发**
   - 在对应模块中实现新功能
   - 添加适当的日志记录
   - 更新相关文档

2. **测试验证**
   - 运行语法检查确保无基本错误
   - 通过 GUI 测试功能完整性
   - 检查日志文件验证执行流程

3. **代码提交前**
   - 确保所有新功能有相应日志
   - 验证错误处理覆盖所有异常路径
   - 检查是否有硬编码值应改为配置项

## 重要提醒

- 所有 GUI 控件位置参数必须用双引号包围
- 事件处理器中避免长时间运行的操作
- 日志级别严格区分：ERROR/WARNING/DEBUG（不使用 INFO）
- 配置更改后应调用 `ExportConfigToJson()` 持久化更改
- GUI 更新应通过 `UIManager.ShowStatus()` 向用户反馈状态