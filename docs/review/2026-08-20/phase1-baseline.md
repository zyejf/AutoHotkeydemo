# Phase 1 — 基线核对与变更盘点

> **任务**: 全面代码审查前置信息 — 基线核对 + 变更盘点
> **审查对象**: 按键连招管理系统（AHK v2 + Rust/Tauri 混合架构）
> **基线**: `docs/code-review-report-2026-08-03.md`（94 项发现：C1~C10、I1~I43、M1~M41）
> **修复映射**: `docs/superpowers/plans/2026-08-04-important-review-findings.md`（43 项 Important）
> **核对日期**: 2026-08-20
> **只读审查**: 未修改任何 .ahk/.rs/.toml/.json 源码文件

---

## 0. 结论速览

- **修复核对统计**（以 HEAD 提交状态为准）：**已修复 50 / 部分修复 1 / 未修复 0 / 引入回归（工作区回退）2**
  - Critical（10 项）：已修复 9，部分修复 1（C6）
  - Important（43 项）：已修复 41，引入回归 2（I1、I6）
- **⚠️ 重要发现**：工作区存在 **4 个未提交文件**，疑似对已落地修复进行**回退**，且当前处于**半回退不一致状态**（详见第 3 节），若此刻运行应用会因 `ConfigIO`/`BackupService` 类未加载而运行时报错。

---

## 1. Git 状态（工作区）

`git log --oneline -40` 显示 08-03 之后为密集的修复提交链：Critical 修复（`6527047` C1-C6、`fe82bb9` C7、`1abc283` C8-C10）→ Important 计划（`74dfcfe`）→ 43 项 Important 逐簇落地 → Minor 修复（M1-M41）→ 文档统计更新（`3af1053`）。

`git status --short` 当前工作区（未提交）：

| 状态 | 文件 |
|------|------|
| M | `infrastructure/backup_core.ahk` |
| M | `infrastructure/migration_logger.ahk` |
| M | `main.ahk` |
| M | `tests/run_all_tests.ahk` |
| ?? | `.trae/specs/comprehensive-code-review-2026-08-20/` |

---

## 2. 变更文件清单（08-03 之后，基准：`2862023`）

### 2.1 新增文件（24 个）

**AHK v2 部分**

| 文件 | 职责 |
|------|------|
| `application/backup_service.ahk` | 应用层 `BackupService` 备份 API 封装（ListBackups/RestoreBackup/DeleteBackup/CreateBackup/RecordConfigChange），消除表现层对 `BackupCore` 的直接依赖（I1） |
| `infrastructure/config_io.ahk` | 基础设施层 `ConfigIO` 配置原子读写（带重试+安全回滚），下沉原应用层 `ExportConfigToFile` 逻辑，消除 `BackupCore` 反向依赖（I6） |
| `tests/test_joy_hotkey_manager.ahk` | `joy_hotkey_manager.ahk` 测试（JoyTestRunner 模式，C7 补测） |
| `tests/test_joy_hotkey_manager_ahu.ahk` | `joy_hotkey_manager.ahk` 测试（AutoHotUnitSuite 模式，C7 补测） |
| `tests/suites/base_suites.ahk` | 基础测试套件集合（run_all_tests 拆分，M23/I21） |
| `tests/suites/core_suites.ahk` | 核心域测试套件集合（M23 拆分） |
| `tests/suites/fix_round_suites.ahk` | 修复轮次回归测试套件集合（M23 拆分） |
| `tests/suites/layering_security_suites.ahk` | 分层/安全测试（BackupService/ConfigIO 分层断言等，I1/I6 验证测试） |
| `tests/fixtures/sample_config.json` | 标准配置样本固件（覆盖 7 种模式，M20） |
| `tests/fixtures/import_test_data.json` | 导入测试场景数据固件（M20） |
| `tests/archive/test_di_refactor_c1.ahk` 等 6 个 archive 文件 | C1-C6/C8 修复验证脚本归档（I25/C 系列） |

**Rust/Tauri 部分**

| 文件 | 职责 |
|------|------|
| `asd-tauri/src-tauri/src/infrastructure/shutdown.rs` | 优雅关机锁 `try_acquire_shutdown_guard` 纯函数（`AtomicBool` compare_exchange，I43 提取可测试模块） |
| `asd-tauri/src-tauri/tests/test_manifest_feature_removed.rs` | 验证 `test-manifest` feature 已从 Cargo.toml 移除（C8/I40） |
| `asd-tauri/e2e/helpers/ahk_path.js` | AHK v2 路径集中管理（环境变量 `AHK_PATH` 注入，C9） |
| `asd-tauri/e2e/helpers/ahk_path.test.js` | ahk_path.js 单元测试 |
| `asd-tauri/e2e/helpers/error_utils.js` | 错误信息统一处理工具（R2 遗留，errMsg 风格） |
| `asd-tauri/e2e/helpers/error_utils.test.js` | error_utils.js 单元测试 |
| `asd-tauri/e2e/.env.example` | E2E 环境变量示例（AHK_PATH 等） |

**文档**

| 文件 | 职责 |
|------|------|
| `docs/superpowers/plans/2026-08-04-important-review-findings.md` | 43 项 Important 修复实现计划 |
| `docs/superpowers/specs/2026-08-04-important-review-findings-design.md` | Important 修复设计文档 |

### 2.2 修改文件（关键源码，职责/改动说明）

**AHK v2**

| 文件 | 改动 |
|------|------|
| `domain/interfaces.ahk` | 新增 `IJoySender` 抽象（C1） |
| `domain/joystick_executor.ahk` | 解除对 `infrastructure/joy_sender` 直接依赖，改经 `IJoySender` 注入（C1） |
| `domain/skill_group.ahk` | `_releaseTimers` Map + 覆盖前取消旧定时器（I12） |
| `domain/skill_manager.ahk` | 空 catch 诊断输出（I11） |
| `domain/key_recorder.ahk` | 空 catch 诊断输出（I11） |
| `application/config_service.ahk` | `ExportConfigToFile`/`ImportConfigFromFile` 委托 `ConfigIO`（I6）；空 catch 诊断（I11） |
| `application/group_service.ahk` | ExportConfigToFile 委托调整（I6） |
| `infrastructure/backup_core.ahk` | 路径遍历拒绝式检查（C4）；调用 ConfigIO（I6，*工作区已回退*）；排序（M13，*工作区已回退*） |
| `infrastructure/config_store.ahk` | DeleteGroupConfig Has 检查（I7）；Save 深拷贝（I15）；空 catch（I11） |
| `infrastructure/config_validator.ahk` | 热键格式正则验证 `_IsValidHotkeyFormat`（I18）；数值上限（M19） |
| `infrastructure/joy_hotkey_manager.ahk` | 反向依赖妥协、INFO→DEBUG（I4）、UnregisterHotkey Has 检查（I8）、`_connPollTimer` 引用（I10）、空 catch 诊断（I11） |
| `infrastructure/ipc_channel.ahk` | DirCreate 错误处理（M17）；空 catch 诊断（I11） |
| `infrastructure/joy_sender.ahk` | 空 catch 诊断（I11） |
| `infrastructure/migration_logger.ahk` | 补全 3 条 #Warn 接管指令（C2） |
| `infrastructure/utils.ahk` | `#Include json_parser`（M1）；`_SortByField` 提取（M13）；空 catch 诊断（I11） |
| `main.ahk` | `JoystickExecutor.SetJoySender(JoySender())` 依赖注入（C1）；#Include config_io/backup_service（I1/I6，*工作区已回退*）；OnExit 集成 JoyHotkeyManager.Shutdown（A2，*工作区已回退*） |
| `gui.ahk` | notepad 路径加引号转义（I14） |
| `presentation/backup_ui.ahk` | 改用 `BackupService`（I1） |
| `presentation/gui_manager.ahk` | OnEvent 闭包包装（I5）；改用 BackupService（I1） |
| `presentation/webview2_manager.ahk` | 调试端口条件守卫（C3）、路径遍历拒绝（C4）、FileRead UTF-8（I13）、Map 类型守护（I16）、分组上限（I17）、批量删除快照（I19）、导入备份+损坏提示（I20）、临时文件名（M16）、改用 BackupService（I1） |
| `tests/run_all_tests.ahk` | 拆分为 `tests/suites/*.ahk` + #Include 整合（M23/I21） |
| `tests/run_tests.ahk`、`tests/test_*.ahk`（+2 共 9 个） | 补全 OnError 回调 / TestReporter 钩子清理（C6/I23/I24） |
| `tests/test_error_system.ahk` | 补注释 + OnError（C6/I24） |
| `tests/AutoHotUnit.ahk` | 补全接管指令（C5） |

**Rust/Tauri**

| 文件 | 改动 |
|------|------|
| `crates/asd-domain/src/config.rs` | holdTriggers 格式错误返回 `de::Error::custom`（I35） |
| `crates/asd-domain/src/validator.rs` | `is_none_or` 冗余检查清理（M25） |
| `crates/asd-ipc-protocol/src/command.rs` | Ping/Shutdown 处理层级文档注释 + 测试（I27） |
| `crates/asd-ipc-protocol/src/message.rs` | ping/shutdown 构造函数（I27） |
| `crates/asd-application/src/error.rs` | AppError 结构化序列化（kind+message）+ `Io` 变体（I34/M28） |
| `crates/asd-application/src/config_repository.rs` | 集中封装 std::fs 通用 I/O 方法（I26，+180 行） |
| `crates/asd-application/src/backup_service.rs` | 移除直接 std::fs，委托 ConfigRepository（I26） |
| `crates/asd-application/src/recording_service.rs` | 移除直接 std::fs；输入验证辅助（I26） |
| `crates/asd-application/src/group_service.rs` | 委托调整（I26/输入验证） |
| `crates/asd-application/src/scheduler.rs`/`state.rs` | 死代码清理等（M26/M29） |
| `src-tauri/src/commands/config_cmd.rs`/`group_cmd.rs`/`recording_cmd.rs` | `_impl` 抽取 + 单元测试（C10）；输入验证（I37/M34） |
| `src-tauri/src/bridge.rs` | 锁顺序注释（I31）、`build_hotkey_event_payload` 纯函数抽取（I42） |
| `src-tauri/src/infrastructure/watchdog.rs` | `cleanup_stale_executor_processes` + `register_panic_hook`/`build_panic_hook_closure` 补偿（I36）；移除通用进程名（R1）；panic hook 可测试（R3） |
| `src-tauri/src/infrastructure/mod.rs` | 新增 `pub mod shutdown;` |
| `src-tauri/src/lib.rs` | `IPC_PIPE_NAME` 常量（I33）、锁顺序注释（I31）、接入 shutdown 模块（I43） |
| `src-tauri/src/tests/bridge_tests.rs` | bridge 测试（I38/I42） |
| `src-tauri/src/tests/ipc_tests.rs` | 常量/协议测试（I33） |
| `asd-tauri/src/main.js` | 错误处理统一 `errMsg` 风格（R2/前端 Minor） |
| `asd-tauri/e2e/*`（tauri.js/wdio.conf.js/specs） | AHK_PATH 环境抽象、错误处理（C9） |
| `asd-tauri/docs/test-map.md` | 补 bridge_tests(13)/watchdog(17)/manifest/5 fuzz 登记（I38/I39/I41） |

### 2.3 删除 / 归档 / 移动

- **删除**：`asd-tauri/src-tauri/tests/manifest_helper.rs`（空壳测试，I40）；`tests/` 下 25 个 `.txt`/stderr/stdout 调试输出文件；`tests/bug_repro_results.txt`、`tests/debug_dir.txt`、`tests/debug_output.txt`
- **移动/归档**（`R`→ `tests/archive/`）：39 个调试/原型/旧版本测试文件（I25/M23），含 `benchmark_hotpath.ahk`、`run_bug_repro.ahk`、`test_html_*`、`test_wv2_*`、`test_*_full`、`test_bug_reproduction`、`test_runner.bat/.ps1`、`verify_integration_test.ps1` 等
- **移动**：`json.ahk` → `tests/legacy/json.ahk`（M2）

> **校正说明**：任务提示中列出的"新增模块" `backup_service.rs`、`group_service.rs`、`recording_service.rs`、`time_format.rs`、`commands/mod.rs` 在 08-03 审查报告中**已存在**（I26 直接引用了 `backup_service.rs`/`recording_service.rs`），属于"修改"而非"新增"。真正在 08-03 之后**新增**的 Rust 模块仅 `infrastructure/shutdown.rs`。`time_format.rs` 提供 `format_timestamp()`/`format_datetime()`（chrono 封装），`commands/mod.rs` 声明 5 个 command 模块，两者在基线时已存在。

---

## 3. ⚠️ 工作区未提交变更（疑似回退，需关注）

`git diff`（未提交）4 个文件构成一次**不完整的回退**：

| 文件 | 回退内容 | 影响 |
|------|---------|------|
| `main.ahk` | 删除 `#Include "infrastructure\config_io.ahk"`、`#Include "application\backup_service.ahk"`，OnExit 移除 `JoyHotkeyManager.Shutdown()` | 回退 I1/I6 接线 + A2 退出清理 |
| `infrastructure/backup_core.ahk` | `ConfigIO.ExportToFile` → `ExportConfigToFile`（重新引入反向依赖），`_SortBackupsByTime` 回退手动插入排序 | 回退 I6 + M13 |
| `infrastructure/migration_logger.ahk` | 删除 `#Include "utils.ahk"` | 回退 M3 |
| `tests/run_all_tests.ahk` | 注销 11 个套件（BackupServiceLayeringTests、ConfigIOLayeringTests、ConfigImportSecurityTests、GuiAndTimerSpecTests、IPCChannelInitSafetyTests、ConfigServiceFileCopyCatchTests、ConfigValidatorNumericLimitTests、WebView2TempFileNamingTests、WebView2PushStateNoRedundantParseTests、FixtureUsageTests、JoyHotkeyReviewFixTests）并新增若干套件 | 测试覆盖收缩 |

**不一致风险**：当前 `application/config_service.ahk:412-417` 仍委托 `ConfigIO.LoadFromFile/ExportToFile`，`presentation/*` 仍在调用 `BackupService.*`，但回退后这两者的 `#Include` 已从 `main.ahk` 移除 —— 若此刻运行主程序，`ConfigIO`/`BackupService` 类未定义，将在运行时抛错。建议在下游审查中确认该回退是否为有意为之，并完成或撤销全部相关改动。

---

## 4. 历史修复核对表

> 状态图例：✅ 已修复 · ⚠️ 部分修复 · ❌ 未修复 · 🔄 引入回归（工作区回退）

### 4.1 Critical（C1~C10）

| 编号 | 严重级别 | 问题简述 | 修复状态 | 当前代码证据 file:line |
|------|---------|---------|---------|----------------------|
| C1 | Critical | 领域层违规引用 infrastructure/joy_sender | ✅ | `domain/joystick_executor.ahk:149-160` `SetJoySender`/IJoySender 注入；`main.ahk:91` `JoystickExecutor.SetJoySender(JoySender())` |
| C2 | Critical | migration_logger.ahk 缺 3 条 #Warn | ✅ | `infrastructure/migration_logger.ahk:3-5` 三种 #Warn 齐全 |
| C3 | Critical | WebView2 调试端口无条件开启 | ✅ | `presentation/webview2_manager.ahk:63-67` `if (!A_IsCompiled && EnvGet("ASD_DEBUG_WEBVIEW2")="1")` 守卫 |
| C4 | Critical | 路径遍历 RegExReplace 可被 `....` 绕过 | ✅ | `webview2_manager.ahk:1188-1193`、`backup_core.ahk:112-114` 改用 `InStr(..., "..")` 拒绝式检查 |
| C5 | Critical | AutoHotUnit.ahk 缺接管指令 | ✅ | `tests/AutoHotUnit.ahk:1-8` #Requires/#ErrorStdOut/3×#Warn/OnError 齐全 |
| C6 | Critical | ~30 个测试文件缺 OnError | ⚠️ | 56 个测试文件已含 `OnError`（grep 确认），但 `tests/test_error_captor.ahk:4-14` 仍缺 OnError 回调 |
| C7 | Critical | joy_hotkey_manager.ahk 零测试覆盖 | ✅ | `tests/test_joy_hotkey_manager.ahk`(356行) + `tests/test_joy_hotkey_manager_ahu.ahk`(441行) |
| C8 | Critical | test-manifest feature 废弃未清理 | ✅ | `Cargo.toml` 移除该 feature；`tests/test_manifest_feature_removed.rs` 验证 |
| C9 | Critical | E2E 硬编码 AHK 路径 | ✅ | `e2e/helpers/ahk_path.js` 环境变量抽象 + `ahk_path.test.js` |
| C10 | Critical | 27 个 Tauri command 无单元测试 | ✅ | `commands/{config,group,recording}_cmd.rs` 均抽出 `_impl` + 单测（group_cmd.rs:19-149 定义、231+ 测试） |

### 4.2 Important（I1~I43）

| 编号 | 严重级别 | 问题简述 | 修复状态 | 当前代码证据 file:line |
|------|---------|---------|---------|----------------------|
| I1 | Important | 表现层直接调用 BackupCore | 🔄 | 提交已落地（`application/backup_service.ahk` + 表现层改调 `BackupService.*`），但 `main.ahk` 工作区**未提交删除了** `#Include "application\backup_service.ahk"` |
| I2 | Important | AGENTS.md 妥协 #2 签名漂移 | ✅ | AGENTS.md 妥协 #2 已更新为 `INotifier.Notify` |
| I3 | Important | joy_hotkey_manager 反向依赖 domain | ✅ | 经 AGENTS.md 妥协 #1 登记（A1）+ 删除冗余 `joystick_input_utils.ahk`；`joy_hotkey_manager.ahk:14` 反向 include 保留为备案妥协 |
| I4 | Important | 使用 INFO 日志级别 | ✅ | `joy_hotkey_manager.ahk` 全文件无 `"INFO"`（grep 确认，已改 DEBUG） |
| I5 | Important | OnEvent 静态方法引用未闭包 | ✅ | `presentation/gui_manager.ahk:80` 闭包包装 `(LV,item,isRightClick,*) =>` |
| I6 | Important | backup_core 反向调用应用层 | 🔄 | 提交已落地（`infrastructure/config_io.ahk` + `config_service.ahk:412-417` 委托 ConfigIO），但 `backup_core.ahk:70` 工作区**未提交回退**为 `ExportConfigToFile(...)` 且删除 config_io include |
| I7 | Important | config_store DeleteGroupConfig 无 Has | ✅ | `infrastructure/config_store.ahk:122` `if this._groupSettings.Has(groupId)` |
| I8 | Important | joy_hotkey UnregisterHotkey 无 Has | ✅ | `joy_hotkey_manager.ahk:105` `if JoyHotkeyManager._registered.Has(joyKey)` |
| I9 | Important | MemoryError 返回 0 与规则冲突 | ✅ | AGENTS.md 已补「MemoryError 例外」说明（代码保留返回 0 为有意设计） |
| I10 | Important | 连接轮询定时器未存储引用 | ✅ | `joy_hotkey_manager.ahk:23,324-332` `_connPollTimer` 存储 + `SetTimer(_,0)` 停止 |
| I11 | Important | 21 处空 catch 静默吞异常 | ✅ | `joy_hotkey_manager.ahk:202,225,255,304`、`key_recorder.ahk:280,286,293,299` 等已加 `OutputDebug` 诊断 |
| I12 | Important | skill_group 复杂单行表达式定时器 | ✅ | `domain/skill_group.ahk:797-805` `_releaseTimers` Map + 覆盖前 `SetTimer(old,0)` |
| I13 | Important | FileRead 未指定 UTF-8 | ✅ | `webview2_manager.ahk:1200-1201` `FileRead(absBase, "UTF-8")` |
| I14 | Important | gui.ahk Run 路径未加引号 | ✅ | `gui.ahk:887,907` `Run('notepad.exe "' logFile '"')` |
| I15 | Important | config_store Save 未深拷贝 | ✅ | `infrastructure/config_store.ahk:42,46,48` `deepclone(...)` |
| I16 | Important | JSONParser.Parse 未验证类型 | ✅ | `webview2_manager.ahk:1204-1208` `if !(baseConfig is Map)` 守护 |
| I17 | Important | 导入仅查字节长度不防 OOM | ✅ | `webview2_manager.ahk:1046-1051` `GroupSettings.Count > 1000` 上限 |
| I18 | Important | 热键验证仅查长度 | ✅ | `infrastructure/config_validator.ahk:103-112` `_IsValidHotkeyFormat` 正则 |
| I19 | Important | 批量删除无事务回滚 | ✅ | `webview2_manager.ahk:1120-1138` 快照 `deepclone` + 失败恢复 |
| I20 | Important | 导入异常后状态不一致 | ✅ | `webview2_manager.ahk:1053-1055` 强制备份 + `1067-1077`「配置已损坏」提示 |
| I21 | Important | run_all_tests 未整合独立测试 | ✅ | `tests/run_all_tests.ahk` 拆分 + `tests/suites/*.ahk`（4 文件） |
| I22 | Important | AGENTS.md 执行器测试统计漂移 | ✅ | AGENTS.md 统一口径「Test_ 方法数 244」 |
| I23 | Important | test_joystick.ahk 缺接管指令 | ✅ | `tests/test_joystick.ahk` 补全 #Warn + OnError（grep 命中） |
| I24 | Important | 测试文件静态属性污染全局状态 | ✅ | 提交 `2af2eba` 移除 TestReporter 未使用钩子；测试文件统一 +2 行处理 |
| I25 | Important | tests/ 根目录 32 文件未登记 | ✅ | 39 文件归档至 `tests/archive/`；AGENTS.md 登记 `tests/archive/` |
| I26 | Important | backup/recording_service 直接用 std::fs | ✅ | `config_repository.rs:138+` 集中封装；backup_service.rs/recording_service.rs 无 `std::fs`（grep 确认） |
| I27 | Important | ping/shutdown 执行器无 case | ✅ | `command.rs:48-69` 处理层级文档；`executor.ahk:436,449` `Executor_Shutdown` |
| I28 | Important | AGENTS.md IpcCommand 示例全错 | ✅ | AGENTS.md 示例已替换为 `ToggleGroup{...}`/`RegisterHotkey`/`EmergencyRelease` |
| I29 | Important | 执行模式表缺 3 个 joystick | ✅ | AGENTS.md 已补 `joystick_periodic/sequence/hold` |
| I30 | Important | 4-crate 实际 5 成员 | ✅ | AGENTS.md 全文「5-crate / 5 members」 |
| I31 | Important | 嵌套锁 + block_in_place 无文档 | ✅ | `lib.rs:416-431` 锁顺序注释；`bridge.rs:179-181` 锁顺序注释 |
| I32 | Important | 19 vs 34 Tauri commands | ✅ | AGENTS.md 更新为「34 Tauri commands」 |
| I33 | Important | named pipe 名称两处硬编码 | ✅ | `lib.rs:31` `const IPC_PIPE_NAME`；`119,663` 引用；`773` 测试 |
| I34 | Important | AppError 序列化丢类型 | ✅ | `error.rs:48-64` 结构化序列化（kind+message）+ 测试 |
| I35 | Important | holdTriggers 解析失败静默替换 | ✅ | `config.rs:342-347` `de::Error::custom(...)` + 测试 `741-748` |
| I36 | Important | JobObject 失败无僵尸补偿 | ✅ | `watchdog.rs:213-214` spawn 前清理；`589` `cleanup_stale_executor_processes`；`659` `register_panic_hook` |
| I37 | Important | recording_cmd 缺输入验证 | ✅ | `recording_cmd.rs:21,24,56,67,75` 5 处 `trim().is_empty()` |
| I38 | Important | bridge_tests 未登记 test-map | ✅ | `test-map.md:83` bridge_tests.rs（13 测试） |
| I39 | Important | watchdog 测试数 14 vs 17 | ✅ | `test-map.md:84` watchdog_integration_tests.rs = 17 |
| I40 | Important | manifest_helper.rs 空壳测试 | ✅ | `tests/manifest_helper.rs` 删除；`test_manifest_feature_removed.rs` 替代（test-map:98） |
| I41 | Important | AGENTS.md 3 个 fuzz 实际 5 个 | ✅ | AGENTS.md + `test-map.md:149`「5 个 fuzz target」 |
| I42 | Important | TauriEventBridge::emit 零覆盖 | ✅ | `bridge.rs:157-160` `build_hotkey_event_payload` 纯函数 + 测试 |
| I43 | Important | lib.rs 核心函数零测试 | ✅ | `infrastructure/shutdown.rs` 提取 `try_acquire_shutdown_guard` 纯函数 + 测试 |

---

## 5. 补充观察

1. **I1/I6 的"语义"落地 vs 物理接线**：`BackupService`/`ConfigIO` 类定义与表现层/应用层改调均已提交，架构分层修复确实落地；但工作区未提交变更将两者的 `#Include` 从入口移除，导致运行时回归风险，需在下游审查中界定。
2. **C6 残留**：`tests/test_error_captor.ahk` 是唯一仍缺 `OnError` 的根目录核心测试文件（其它 56 个已达标）。
3. **I3 修复方式**：团队最终选择"AGENTS.md 妥协登记 + 删除冗余 joystick_input_utils.ahk"而非物理解耦，`joy_hotkey_manager.ahk:14` 的 `#Include "../domain/joystick_input.ahk"` 保留（属已备案妥协 A1）。