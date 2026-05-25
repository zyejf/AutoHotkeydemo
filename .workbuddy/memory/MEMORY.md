# AutoHotkey Demo - 长期记忆

## AHK v2 关键语法规则
- **try OTB 风格限制**: `try { ... }` 单行 OTB 风格在函数/方法内部会报 "Missing }"。必须用多行: `try {` 换行 `...` 换行 `}`
- **catch 语法**: 必须用 `as` 关键字 — `catch as err`，不能直接 `catch err`
- **continue 限制**: 只能在 Loop/For 循环内使用
- **SetTimer 只有2个参数**: `SetTimer(Callback, Period)`，不支持第三参数传值给回调。需要用闭包捕获: `SetTimer((*) => fn(captured_var), -1000)`
- **static 属性访问**: AHK v2 实例方法中**不能用 `this.staticProp`** 访问静态属性，会报 "no property"。要么声明为实例属性（推荐，在 `__New` 中初始化），要么用全局常量
- **语法检查**: 使用 `& "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "file.ahk" 2>&1` 检查语法

## 项目结构
- 入口: `asd.ahk` (#Include json.ahk, gui.ahk, SkillMgrDebugLogger.ahk, ui_manager.ahk, config.ahk)
- 两个主要类: `SkillGroup` (line 29), `SkillManager` (line 903)
- 配置文件: `config.json`
