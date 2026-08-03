# Tasks

> 修复顺序：安全优先（C3/C4 → C1 → C2/C5/C6 → C8/C9 → C7/C10）
> 任务按文件归属分组，避免多代理编辑同一文件冲突。所有 9 个任务相互独立，可全并行执行。

## Phase 1: 安全漏洞修复（最高优先级）

- [ ] Task 1: 修复 C3+C4 — WebView2 调试端口 + 路径遍历防护（同改 webview2_manager.ahk，合并为一个任务避免冲突）
  - **C3 修复**：`presentation/webview2_manager.ahk:63`
    - 移除无条件的 `EnvSet("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--remote-debugging-port=9222")`
    - 改为仅在非编译模式（`!A_IsCompiled`）或显式调试标志下开启
    - 编译发布时强制不开启调试端口
  - **C4 修复**：`presentation/webview2_manager.ahk:1171-1172` + `infrastructure/backup_core.ahk:112-113`
    - 将 `RegExReplace(path, "\.\.", "")` 替换为 `InStr(path, "..")` 拒绝式检查
    - 路径含 `..` 时直接返回错误
    - 参考 `_BridgeRestoreBackup:721-723` 的正确实现
  - **TDD**：先写测试验证 `....` 输入被拒绝 + 调试端口在编译模式下不开启
  - 验证：`/ErrorStdOut` 语法检查 + 测试通过
  - 产出：修复后的 webview2_manager.ahk + backup_core.ahk

## Phase 2: 架构违规修复

- [ ] Task 2: 修复 C1 — 领域层违规引用基础设施层（完整 DI 重构）
  - 在 `domain/interfaces.ahk` 新增 `IJoySender` 抽象基类
    - 定义 `SendBtn(btn, state)`、`SendPov(pov)`、`SendAxis(axis, value)` 等方法签名
  - 修改 `infrastructure/joy_sender.ahk`：`class JoySender extends IJoySender`
  - 修改 `domain/joystick_executor.ahk`：
    - 删除 `#Include "../infrastructure/joy_sender.ahk"`（第 16 行）
    - `JoystickExecutor` 添加 `joySender` 属性，通过构造函数或 setter 注入
    - `_SendJoyKey`/`_ReleaseJoyKeys` 中 `JoySender.SendBtn(...)` 改为 `this.joySender.SendBtn(...)`
  - 修改 `main.ahk` 的 `InitDependencies()`：
    - 创建 `JoySender` 实例
    - 注入到 `JoystickExecutor.joySender`
  - **TDD**：先写测试验证 `JoystickExecutor` 不再直接依赖 `JoySender` 具体类
  - 验证：`/ErrorStdOut` 语法检查 + 测试通过 + 功能正常
  - 产出：修复后的 interfaces.ahk + joy_sender.ahk + joystick_executor.ahk + main.ahk

## Phase 3: 合规规则修复

- [ ] Task 3: 修复 C2 — migration_logger.ahk 补充 #Warn 指令
  - 在 `infrastructure/migration_logger.ahk` 的 `#ErrorStdOut "UTF-8"` 之后补充：
    - `#Warn VarUnset, OutputDebug`
    - `#Warn Unreachable, OutputDebug`
    - `#Warn LocalSameAsGlobal, Off`
  - **TDD**：先写测试验证文件包含 3 条 #Warn 指令
  - 验证：`/ErrorStdOut` 语法检查
  - 产出：修复后的 migration_logger.ahk

- [ ] Task 4: 修复 C5 — AutoHotUnit.ahk 补充完整接管指令
  - 修改 `tests/AutoHotUnit.ahk:1-4`：
    - 移除 `#Warn All, StdOut`（非标准）
    - 添加 `#Requires AutoHotkey v2.0`
    - 添加 `#ErrorStdOut "UTF-8"`
    - 添加 `#Warn VarUnset, OutputDebug`
    - 添加 `#Warn Unreachable, OutputDebug`
    - 添加 `#Warn LocalSameAsGlobal, Off`
    - 添加 `OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))`
  - **TDD**：先写测试验证 AutoHotUnit.ahk 包含完整指令集
  - 验证：`/ErrorStdOut` 语法检查 + 测试框架仍正常工作
  - 产出：修复后的 AutoHotUnit.ahk

- [ ] Task 5: 修复 C6 — 约 30 个测试文件批量补充 OnError 回调
  - 扫描 `tests/` 根目录下所有 .ahk 测试文件
  - 识别缺少 `OnError` 回调的文件（约 30 个）
  - 为每个文件添加 `OnError((e, mode) => (FileAppend("RUNTIME_ERROR: " e.Message " at line " e.Line "`n", "*"), true))`
  - 添加位置：在所有 `#Include` 和 `#Warn` 指令之后、测试代码之前
  - **TDD**：先写批量检查脚本验证哪些文件缺少 OnError
  - 验证：`/ErrorStdOut` 语法检查所有修改的文件
  - 产出：修复后的约 30 个测试文件

## Phase 4: 配置文档修复

- [ ] Task 6: 修复 C8 — 删除 test-manifest feature + 更新 AGENTS.md
  - 从 `asd-tauri/src-tauri/Cargo.toml` 删除 `test-manifest = []` feature 定义
  - 更新 `AGENTS.md`：
    - 「Testing Requirements」→「Rust/Tauri 测试」章节：移除 `--features test-manifest`
    - 「常见错误」→「Rust/Tauri」第 4 条：移除 test-manifest 相关描述
    - 简化测试运行命令为 `cargo test --lib`（无 feature flag）
  - **TDD**：先写测试验证 Cargo.toml 无 test-manifest feature
  - 验证：`cargo check` 通过 + `cargo test --lib` 仍能运行
  - 产出：修复后的 Cargo.toml + AGENTS.md

- [ ] Task 7: 修复 C9 — E2E 硬编码 AHK 路径环境变量化
  - 修改 `asd-tauri/e2e/specs/hotkey_cmd.spec.js:43`：硬编码路径改为环境变量
  - 修改 `asd-tauri/e2e/helpers/key_receiver.js:16`：同上
  - 创建或修改 `asd-tauri/e2e/helpers/config.js`：集中管理 AHK 路径常量
    - 读取 `process.env.AHK_PATH`
    - 提供默认值回退（如 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`）
  - **TDD**：先写测试验证路径来自环境变量
  - 验证：E2E 测试配置正确加载
  - 产出：修复后的 hotkey_cmd.spec.js + key_receiver.js + config.js

## Phase 5: 测试覆盖补充

- [ ] Task 8: 修复 C7 — 创建 joy_hotkey_manager 测试
  - 创建 `tests/test_joy_hotkey_manager.ahk`
  - 测试覆盖：
    - 热键注册/注销（Joy1~Joy32）
    - 轴/POV 轮询逻辑
    - 热插拔检测（30s 定时器）
    - 多手柄支持
  - 遵循测试文件标准模板（完整接管指令 + OnError + FileAppend 输出）
  - 使用 AutoHotUnitSuite 基类
  - 在 `run_all_tests.ahk` 中注册新测试
  - **TDD**：测试本身就是 TDD 的 RED 阶段
  - 验证：`/ErrorStdOut` 语法检查 + 测试可运行
  - 产出：新建 test_joy_hotkey_manager.ahk + 更新 run_all_tests.ahk

- [ ] Task 9: 修复 C10 — 27 个 Tauri command 补充 _impl 模式 + 测试
  - 修改 `asd-tauri/src-tauri/src/commands/config_cmd.rs`：
    - 将 11 个 `#[tauri::command]` 函数体提取为 `fn xxx_impl(state: &Arc<AppState>, ...) -> Result<...>`
    - command 函数仅一行委托：`xxx_impl(&state, ...).await`
    - 为每个 _impl 函数添加正常路径 + 错误路径测试
  - 修改 `asd-tauri/src-tauri/src/commands/group_cmd.rs`：同上（8 个 commands）
  - 修改 `asd-tauri/src-tauri/src/commands/recording_cmd.rs`：同上（8 个 commands）
  - 参考 `system_cmd.rs` 的现有 `_impl` 模式
  - **TDD**：先写测试验证 _impl 函数行为（RED），再提取 _impl（GREEN）
  - 验证：`cargo test --lib` 通过 + `cargo check` 无错误
  - 产出：修复后的 config_cmd.rs + group_cmd.rs + recording_cmd.rs

# Task Dependencies

- [Task 1] ~ [Task 9] 相互独立，按文件归属分组无冲突，可全部并行执行
- 优先级顺序仅决定验证顺序（Phase 1 → 2 → 3 → 4 → 5），不阻塞并行执行
- 建议按优先级分批验证：先验证 Phase 1 安全修复，再依次验证后续
