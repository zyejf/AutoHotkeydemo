# AutoHotkey Demo - 长期记忆

## AHK v2 关键语法规则
- **try OTB 风格限制**: `try { ... }` 单行 OTB 风格在函数/方法内部会报 "Missing }"。必须用多行: `try {` 换行 `...` 换行 `}`
- **catch 语法**: 必须用 `as` 关键字 — `catch as err`，不能直接 `catch err`
- **continue 限制**: 只能在 Loop/For 循环内使用
- **SetTimer 只有2个参数**: `SetTimer(Callback, Period)`，不支持第三参数传值给回调。需要用闭包捕获: `SetTimer((*) => fn(captured_var), -1000)`
- **static 属性访问**: AHK v2 实例方法中**不能用 `this.staticProp`** 访问静态属性，会报 "no property"。要么声明为实例属性（推荐，在 `__New` 中初始化），要么用全局常量
- **语法检查**: 使用 `& "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut "file.ahk" 2>&1` 检查语法

## 项目结构（v4.0，2026-09-12 更新）
- **混合双栈**：AHK v2（DDD 四层）+ Rust/Tauri（5-crate workspace）
- AHK 入口: `main.ahk`（`asd.ahk` 为兼容别名）；`gui.ahk` 已于 2026-09-12 删除（v1.0 遗留）
- Rust 部分: `asd-tauri/`，5 crate = `asd-ipc-protocol` → `asd-domain` → `asd-application` → `src-tauri`（+ `asd-test-harness`）
- 配置文件: `config.json`
- 架构权威文档: `AGENTS.md`；测试分布权威: `asd-tauri/docs/test-map.md`

## AHK 测试约定
- 推荐 `AutoHotUnitSuite` + `Test_` 前缀方法（可被 `run_all_tests.ahk` 加载）
- `FileExist()` 返回属性字符串（如 `"A"`）而非布尔值，断言须写 `isTrue(FileExist(p) != "")`
- 归档的旧版断言式脚本位于 `tests/archive/`（无法被加载，仅存档）
