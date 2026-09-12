# ASD 技能管理器 v4.0 代码审查问题修复计划（2026-08-20）

> **整合来源**：`docs/review/2026-08-20/fix-plan/` 下 5 份中间文档（`00-issue-inventory.md`、`01-phase0-critical.md`、`02-phase1-important.md`、`03-phase2-minor.md`、`04-cross-cutting.md`）
> **上游权威**：`docs/code-review-report-2026-08-20.md`（主报告）+ `docs/review/2026-08-20/` 下 9 份分报告
> **生效基线**：`main` 分支 `3af1053` + 工作区 4 个未提交文件（详见「Phase 0 → CR1 处置预案」）
> **性质**：本计划为最终修复计划文档，整合忠实合并 5 份中间文档，不虚构、不遗漏；编写本文件前未修改任何 .ahk / .rs / .toml / .json 源码文件

---

## 1. 概述与范围

### 1.1 目标

针对 2026-08-20 代码审查发现的全部问题，制定分阶段、可追溯、可回滚的修复计划，使项目（AHK v2 部分 + Rust/Tauri 5-crate workspace 部分）恢复架构一致性、消除运行时崩溃、收敛安全与性能缺陷、并统一跨文档口径。

### 1.2 范围

| 指标 | 数值 |
|------|:----:|
| 原始发现问题 | 76 条 |
| 去重合并 | 4 组（8 条 → 4 条） |
| **最终问题数** | **72 条** |
| Critical（P0） | **3** |
| Important（P1） | **23** |
| Minor（P2） | **46** |
| P1 主题分组 | 10 组（G1~G10） |
| P2 批量分组 | 12 批（B1~B12） |

### 1.3 修复原则

1. **原子提交**：每个修复关注点对应一个独立 `git commit`（Conventional Commits 规范，如 `fix(ahk): ...` / `fix(asd-tauri): ...` / `perf(asd-tauri): ...` / `refactor(...): ...` / `docs: ...`），便于逐条 `git revert` 回滚。
2. **逐项可回滚**：任何一项修复都可独立回退，且「提交 ↔ 问题编号」一一对应可追溯。
3. **只读阶段不碰源码**：本计划与 5 份中间文档均为规划产物，未修改任何 .ahk / .rs / .toml / .json 源码文件。
4. **先处置工作区半回退状态**：CR1 的「工作区 4 个未提交文件处置预案」是唯一硬性前置，必须先于一切修复执行；严禁回滚用户未提交改动。
5. **单一权威来源**：测试统计以 `asd-tauri/docs/test-map.md` 为准；架构/依赖/执行模式以 `AGENTS.md` 为准；其余文档不自行复制数字。

---

## 2. 问题清单与优先级分级

### 2.1 去重与编号说明

| 合并组 | 组成 | 归属编号 | 级别 |
|--------|------|---------|------|
| 合并 1 | T2-01 + T2-02 | **CR1** | Critical |
| 合并 2 | T3-05 + T6-03 | **T3-05 + T6-03** | Important |
| 合并 3 | T3-08 + T6-12 | **T3-08 + T6-12** | Minor |
| 合并 4 | T2-07 + T7-07 | **T2-07 + T7-07** | Minor |

> **Task 8 未展开 Minor**：Task 8 分报告「总结」自报 7 条（Important 3 + Minor 4），正文仅列 T8-01~T8-06 共 6 条，第 4 条 Minor 未在正文展开。本清单以 `T8-07†` 占位，位置/描述如实标注「报告正文未展开，编号待定」。

### 2.2 P0 / P1 / P2 分级说明

- **P0（Critical，3 条）**：阻塞运行（运行时崩溃）、热路径性能/反向冻结风险、严重误导开发者的文档漂移——立即/下次运行前处置。
- **P1（Important，23 条）**：影响安全/性能/可靠/可维护，短期（紧随 Phase 0）处置。
- **P2（Minor，46 条）**：次要优化/一致性/文档补全，长期随迭代消化。

### 2.3 P0 — Critical（3 条）

| 编号 | 位置 (file:line) | 维度 | 级别 | 一句话描述 |
|------|------------------|------|------|-----------|
| CR1（T2-01 + T2-02） | `main.ahk`(21-58 include 段缺失)；`infrastructure/config_io.ahk:21`；`application/config_service.ahk:412-417`；`infrastructure/backup_core.ahk:70`；`tests/suites/layering_security_suites.ahk:128-131` | 架构设计 | Critical | 工作区半回退状态：`ConfigIO`/`BackupService` 未接入生产入口 `#Include`，配置读写核心路径运行时 `Unknown class` 崩溃 |
| CR2（T6-01） | `ahk_executor/sender.ahk:494-522`；`ahk_executor/ipc_client.ahk:792-818,533-541` | 性能优化 | Critical | 每次按键 down/up 无条件执行 IPC 序列化 + 同步阻塞写命名管道（无 OVERLAPPED/背压） |
| CR3（T7-01） | `docs/developer-guide.md` §1.2(L51-85)、§2.3.3(L226-236)、附录E(L975-993)、§1.1(L29) | 文档完整性 | Critical | developer-guide.md 整篇基于已废弃单 crate 结构，与 5-member workspace 严重不符 |

### 2.4 P1 — Important（23 条）

| 编号 | 位置 (file:line) | 维度 | 级别 | 一句话描述 |
|------|------------------|------|------|-----------|
| T2-03 | `infrastructure/utils.ahk:13` → `json_parser.ahk:15` → `json_logger.ahk:16` → `utils.ahk` | 架构设计 | Important | 基础设施层三模块形成循环 `#Include` 链（utils ↔ json_parser ↔ json_logger） |
| T2-04 | `infrastructure/config_store.ahk:95,14` | 代码质量 | Important | `config_store` 使用 `JSONLogger.Log` 却未显式 `#Include "json_logger.ahk"`（隐式依赖） |
| T3-01 | `infrastructure/config_validator.ahk:115-138` | 安全性 | Important | `ValidateGroupOnly` 未复用 `_IsValidHotkeyFormat`，Create/Update 分组入口热键格式校验缺口 |
| T3-02 | `infrastructure/config_validator.ahk:140-284` | 安全性 | Important | `_ValidateModeFields` 从不校验 keys/pressKeys/holdKeys/joyKeys 元素是否为合法按键名 |
| T3-03 | `infrastructure/config_validator.ahk:286-299` | 安全性 | Important | `_ValidateHotkeys` 只查非空不查格式，「紧急停止」等控制热键可写入非法值 |
| T3-04 | `presentation/gui_manager.ahk:408-438` | 安全性 | Important | `GlobalSettingsEditor._Save` 无逐字段校验 + 忽略 `SaveConfig()` 返回值导致误报「已保存」 |
| T3-05 + T6-03 | `infrastructure/error_system.ahk:185-213`；`json_logger.ahk:179-227`；`debug_logger.ahk:22,52-56`；`domain/mode_registry.ahk` 各 catch、`skill_group.ahk:756-758` | 性能优化 | Important | 热路径错误/日志写盘无限速，违反 AGENTS.md「每秒最多一次」承诺（DebugLogger 仅 50ms 且仅 DEBUG） |
| T3-06 | `domain/joystick_executor.ahk:55,107,157-160` | 安全性 | Important | `_SendJoyKey` 注入检查在热路径内，JoySender 未注入时每 tick 抛异常并高频写 ERROR 日志 |
| T4-04 | `crates/asd-domain/src/validator.rs:90-94,137-139` | 安全性 | Important | Rust 侧控制热键空值静默放行 + 无「控制热键 vs 分组热键」交叉冲突检测 |
| T5-01 | `src/infrastructure/watchdog.rs:67,73,499,502` | 安全性 | Important | `ProcessWatchdog`/`JobObjectGuard` 4 处手写 `unsafe impl Send/Sync`，soundness 依赖脆弱 Mutex 不变量 |
| T5-02 | `src/lib.rs:606-615` | 代码质量 | Important | `EXPECTED_TAURI_COMMAND_COUNT` 编译时断言为「常量自比」永真式，不构成命令数量守护 |
| T6-02 | `domain/skill_group.ahk:800-805`；`ahk_executor/sender.ahk:347,394,444,464`；`ahk_executor/joystick.ahk:203,253`；`domain/joystick_executor.ahk:55,107` | 性能优化 | Important | 每次按键按下都新建闭包 + 一次性 SetTimer，up 定时器未纳入 Map 跟踪 |
| T6-04 | `ahk_executor/sender.ahk:178-194,197-215,290-305`；`joystick.ahk:68-85`；`executor.ahk:102-107` | 性能优化 | Important | 重复激活已激活分组时直接覆盖 `_timers` 引用而不先取消旧定时器 → 双倍发键 |
| T6-05 | `src/bridge.rs:44-67,69-129`；`src/infrastructure/ipc.rs:290-327` | 性能优化 | Important | bridge `block_in_place + block_on`，`send()` 无写超时，AHK 挂起可无限阻塞工作线程 |
| T6-06 | `src/infrastructure/ipc.rs:545,567-572,504,18` | 性能优化 | Important | `listen_ahk` 每条消息无差别 `msg.clone()` + outbound `send().await` 背压无界传导 |
| T6-07 | `ahk_executor/joystick.ahk:299-317,360-395,444-454,435-441` | 性能优化 | Important | joystick 每次按键事件 AcquireVJD/RelinquishVJD 往返 + `_GetAxisInfo`/`_IsAxis` 每次重建 Map |
| T7-02 | `docs/migration-guide.md` §1.1(L42)、§3.4(L296-306)、§4.1(L421)、§4.3(L517)、§5.4.6(L562) | 文档完整性 | Important | migration-guide.md 引用已迁移/删除 API（Config::load/save、HashMap、13 commands） |
| T7-03 | `asd-tauri/TESTING.md` L6, L8, L133-146 | 文档完整性 | Important | TESTING.md 引用已删除的 test-manifest feature、fuzz 数量 3 写少、Rust 测试数 506 与 test-map 609 冲突 |
| T7-04 | `asd-tauri/docs/test-map.md` L15-19, L27-32, L69, L80-99, L146 | 文档完整性 | Important | test-map.md 汇总表与明细表不一致，逐文件测试计数严重过时（差 63 等） |
| T7-05 | `AGENTS.md` L135/L340/L274 vs `test-map.md` L146-147 vs `TESTING.md` L6-8 | 文档完整性 | Important | 测试统计口径跨文档冲突（Rust 592 vs 609、执行器 244 vs 467、AHK v2 581 无法对账） |
| T8-01 | `src/infrastructure/ipc.rs`（`listen_ahk` 消息解析/分发） | 测试覆盖 | Important | IpcManager 消息接收/分发循环缺直接单测（JSON 解析 + 三分支分发无白盒覆盖） |
| T8-02 | `src/lib.rs` `perform_graceful_shutdown` | 测试覆盖 | Important | 优雅关机流程主体缺测试（仅锁纯函数已覆盖，IPC Shutdown + watchdog stop 无回归保障） |
| T8-03 | `asd-tauri/e2e/specs/*.spec.js`（9 文件，例 `config_cmd.spec.js:32-95`） | 测试覆盖 | Important | E2E spec 生命周期代码 ~500 行高度重复、失败级别硬编码 'HIGH'、caseId 正则各自维护 |

### 2.5 P2 — Minor（46 条）

| 编号 | 位置 (file:line) | 维度 | 级别 | 一句话描述 |
|------|------------------|------|------|-----------|
| T2-05 | `infrastructure/joy_sender.ahk:17` | 架构设计 | Minor | `joy_sender` 反向 `#Include "../domain/interfaces.ahk"`（方向正确但未在 AGENTS.md 登记） |
| T2-06 | `infrastructure/config_store.ahk:82-98` vs `:36-65` | 代码质量 | Minor | `Set()` 直接引用赋值、`Save()` 用 deepclone，两条写入路径防御拷贝策略不一致 |
| T2-08 | `domain/skill_manager.ahk:453-458,470-473` | 代码质量 | Minor | `_resetEmergencyTimer` 未在静态属性区声明，靠 `HasProp` 守卫 |
| T2-09 | `domain/skill_manager.ahk:318-379` | 代码质量 | Minor | `_StartGroupExecution` 嵌套闭包 + `Bind` 递归约 60 行/5 层，圈复杂度高 |
| T2-10 | `presentation/group_editor.ahk`(81 方法)、`webview2_manager.ahk`(60 方法)、`domain/skill_group.ahk`(约 920 行) | 代码质量 | Minor | 表现层/领域层存在超大类 God Object 倾向 |
| T2-07 + T7-07 | `AGENTS.md` Key Files/Subdirectories 表、L58-62 分层表 | 文档完整性 | Minor | AHK 模块清单不完整：infrastructure 缺 config_io/joy_sender/migration_logger，domain 缺 joystick_executor/joystick_input/key_recorder/key_validator，application 缺 backup_service |
| T3-07 | `infrastructure/ipc_channel.ahk:181-184` | 安全性 | Minor | `_OnReceived` 监听器回调 `try callback(msgObj)` 无 catch，异常向上传播中断消息分发 |
| T3-08 + T6-12 | `presentation/webview2_manager.ahk:1040-1081,408,438-439`；`infrastructure/config_store.ahk:30-48,70`；`application/group_service.ahk:140` | 性能优化 | Minor | `_BridgeImportConfig` 对同一 jsonStr 解析两次；保存路径多层冗余 deepclone |
| T3-09 | `domain/key_recorder.ahk:273-302,312-323` | 安全性 | Minor | `_mouseHotkeys` 标志在注册完成后才置位，`_RemoveMouseHooks` 中途异常时已注册钩子残留 |
| T4-01 | `crates/asd-domain/Cargo.toml:11` | 架构设计 | Minor | asd-domain 声明 `tracing` 依赖但零使用，AGENTS.md 亦未登记 |
| T4-02 | `crates/asd-application/src/scheduler.rs:6-13` | 架构设计 | Minor | 已 `#[deprecated]` 的 `SkillManager` 死代码 + AGENTS.md 对该文件描述严重失真 |
| T4-03 | `crates/asd-ipc-protocol/Cargo.toml:10`；`src/hotkey_merger.rs:33` | 架构设计 | Minor | 为仅 1 处 `debug!` 引入 `tracing`，且 AGENTS.md 依赖表未登记 |
| T4-05 | `crates/asd-domain/src/validator.rs:152-158` | 代码质量 | Minor | 无效热键键名仅 warning 不 error（不阻断保存），该权衡未在文档记录 |
| T4-06 | `crates/asd-application/src/config_repository.rs:16`；`recording_service.rs:2` | 代码质量 | Minor | `atomic_write` 为自由函数而非 ConfigRepository 方法，recording_service 直接跨层引用 |
| T4-07 | `crates/asd-application/src/config_repository.rs:105,119,126,148` | 代码质量 | Minor | ConfigRepository 错误返回类型不统一（`ConfigLoadError` vs `String` 并存） |
| T4-08 | `crates/asd-application/src/error.rs:42-44,58-61` | 代码质量 | Minor | `AppError::message()` 对 Io 返回空串，序列化靠手动分支特判，三处需同步维护 |
| T4-09 | `crates/asd-domain/src/config.rs:63` | 代码质量 | Minor | `Config::default_config()` 的 `version` 仍为 `"3.0"`，与 v4.0 不符 |
| T4-10 | `crates/asd-application/src/state.rs:882,900,901`；`tests/*.rs` | 架构设计 | Minor | 测试代码直接 `std::fs`，与「std::fs 仅 ConfigRepository」字面规则存在张力（缺测试豁免说明） |
| T5-03 | `src/bridge.rs:47,76,196,206,216` | 架构设计 | Minor | IpcBridge/WatchdogBridge 用 `Handle::current().block_on`，脱离 tokio 运行时上下文会 panic |
| T5-04 | `src/infrastructure/watchdog.rs:781,214,594-597` | 安全性 | Minor | `spawn_child` 在 async 循环内持锁同步执行 taskkill + `Command::spawn` 阻塞 I/O |
| T5-05 | `src/lib.rs:117-138,140-174` | 架构设计 | Minor | 心跳/接受循环/关机直接操作 IpcManager 未走 IpcSender trait（仅回调注册有 M31 例外） |
| T5-06 | `src/infrastructure/watchdog.rs:518` | 代码质量 | Minor | `JOBOBJECTINFOCLASS(9)` 魔法数字，未查 windows crate 具名常量 |
| T5-07 | `src/infrastructure/watchdog.rs:55,100-101,108-116` | 代码质量 | Minor | `on_state_change` 回调为死代码，`set_state` 持锁同步触发回调有重入死锁隐患 |
| T5-08 | `src/infrastructure/ipc.rs:76-85,180` | 安全性 | Minor | IPC auth token 由时间戳派生且比较非恒定时间，未用密码学随机源 |
| T5-09 | `src/lib.rs:117-138,663` | 安全性 | Minor | 无单实例保护，二次启动 listener 创建失败 + executor 错连首实例 |
| T5-10 | `src/infrastructure/watchdog.rs:417-461` | 安全性 | Minor | `graceful_shutdown` 持 watchdog 锁横跨多个 await（约 5s+），轮询被阻塞 |
| T5-11 | `src/lib.rs:408,757` | 代码质量 | Minor | 生产代码 `Arc::get_mut().expect` 与入口 `expect`（M33 已登记技术债） |
| T5-12 | `src/lib.rs:31`；`ahk_executor/ipc_client.ahk:20` | 架构设计 | Minor | 管道名 Rust 侧 `IPC_PIPE_NAME` 常量与 AHK 侧 `\\.\pipe\asd_ipc` 硬编码无一致性保障 |
| T5-13 | `src/infrastructure/watchdog.rs:1056` | 代码质量 | Minor | `#[test]` 属性缩进 8 空格、其下 fn 4 空格，cargo fmt 未覆盖 |
| T5-14 | `src/infrastructure/watchdog.rs:361-382,390-403` | 代码质量 | Minor | `begin_restart`/`reset_to_restart` 终止子进程后只 `kill()` 未 `wait()`，与 `kill_child` 风格不一致 |
| T6-08 | `infrastructure/ipc_channel.ahk:66-86,89-109,192-204,112-170` | 性能优化 | Minor | AHK 预留文件管道每次 Send/Emit 做 FileGetSize + 整条 Stringify + FileAppend |
| T6-09 | `infrastructure/json_serializer.ahk:17-21,49-88`；`error_system.ahk:199` | 性能优化 | Minor | 日志用默认 `indent=2` 生成多行 pretty JSON，单条记录被拆多行 + 多余分配 |
| T6-10 | `infrastructure/utils.ahk:41-55` | 性能优化 | Minor | `_GetField` 对 JSON 字符串值每次重复 `JSONParser.Parse`，无缓存 |
| T6-11 | `domain/mode_registry.ahk:317,334,415,434` | 性能优化 | Minor | 序列执行器冗余 `HasProp("_nextStepTime")` 检查（属性已预初始化） |
| T7-06 | `AGENTS.md` L1220-1227 | 文档完整性 | Minor | IpcMessage 示例仅 4 字段，实际 message.rs 有 9 字段，未标注简化 |
| T7-08 | `AGENTS.md` L72 | 文档完整性 | Minor | 「AHK 已知架构妥协」第 3 条实为 Rust 层面妥协，放错章节且与 L142 重叠 |
| T7-09 | `AGENTS.md` L251 | 文档完整性 | Minor | tests/ 根目录「22 个核心文件 / 15 个核心测试文件」拆分与列举不吻合（实际 16 个 test_*.ahk） |
| T7-10 | `AGENTS.md` L1267 vs `tauri.conf.json` L5 vs `developer-guide.md` L804-805 | 文档完整性 | Minor | 应用数据目录/标识三处不一致（com.asd.skillmanager / com.asd.tauri / asd-tauri） |
| T7-11 | `AGENTS.md` L37-47, L109-111 | 文档完整性 | Minor | Rust Key Files/目录表未登记 backup_service/group_service/recording_service/time_format/shutdown/bridge_tests 等新增模块 |
| T7-12 | `docs/code-review-report-2026-08-03.md` L15, L17, L39 | 文档完整性 | Minor | 历史报告对 AGENTS.md 的论断（4-crate、13 commands、test-manifest 存在）现已失效，未加勘误 |
| T7-13 | `asd-tauri/docs/test-map.md` L175-182 | 文档完整性 | Minor | E2E helpers 表未登记 ahk_path.js、error_utils.js 及 `__tests__/` |
| T7-14 | `AGENTS.md` L356、`test-map.md` L168 vs `AGENTS.md` L1239-1252 | 文档完整性 | Minor | E2E「modes（7）：7 种执行模式」与「支持 10 种模式」表述矛盾 |
| T8-04 | `tests/run_all_tests.ahk` | 测试覆盖 | Minor | 批量运行入口缺 `OnError` 回调，单 suite 崩溃会弹窗中断整体批量运行 |
| T8-05 | `AGENTS.md`（"16 ignored"）、`test-map.md:84`；`config_compat_tests.rs:3` | 测试覆盖 | Minor | `#[ignore]` 实测 19+ 与文档 16/15 三处不一致；MAIN_CONFIG_JSON 未登记为固件 |
| T8-06 | `tests/fixtures/`；`tests/test_ahk_executor/test_joystick.ahk:463` | 测试覆盖 | Minor | fixtures 缺 joystick 3 模式配置样本；joystick 测试硬编码 `"joystick_periodic"` 字符串 |
| T8-07† | （报告正文未展开） | 测试覆盖 | Minor | Task 8 自报 Minor 第 4 条，正文未展开，编号待定 |

### 2.6 P1 主题分组（10 组 / 23 项）

| 组 | 主题名 | 成员编号 |
|----|--------|---------|
| G1 | 校验覆盖缺口 | T3-01、T3-02、T3-03、T4-04 |
| G2 | 热路径日志无限速 | T3-05 + T6-03（合并项） |
| G3 | 定时器生命周期 | T6-02、T6-04 |
| G4 | IPC 背压与阻塞 | T6-05、T6-06 |
| G5 | unsafe soundness | T5-01 |
| G6 | vJoy 设备复用 | T6-07 |
| G7 | 隐式依赖与永真断言 | T2-03、T2-04、T5-02 |
| G8 | 输入误报与注入检查 | T3-04、T3-06 |
| G9 | 测试覆盖补强 | T8-01、T8-02、T8-03 |
| G10 | 文档严重漂移 | T7-02、T7-03、T7-04、T7-05 |

> 校验：4 + 1 + 2 + 2 + 1 + 1 + 3 + 2 + 3 + 4 = **23** ✓

### 2.7 P2 批量分组（12 批 / 46 项）

| 批 | 主题名 | 成员编号 | 计数 |
|----|--------|---------|:----:|
| B1 | 冗余依赖与死代码清理 | T4-01、T4-02、T4-03、T5-07 | 4 |
| B2 | 错误类型与封装统一 | T4-06、T4-07、T4-08 | 3 |
| B3 | 校验权衡与默认值语义 | T4-05、T4-09 | 2 |
| B4 | 未登记妥协与规则豁免 | T2-05、T4-10、T5-05 | 3 |
| B5 | 并发/阻塞/基础设施健壮性 | T5-03、T5-04、T5-08、T5-09、T5-10、T5-12 | 6 |
| B6 | AHK 代码一致性 | T2-06、T2-08、T2-09、T2-10 | 4 |
| B7 | Rust 代码一致性（watchdog/bridge） | T5-06、T5-11、T5-13、T5-14 | 4 |
| B8 | AHK 健壮性补丁 | T3-07、T3-09 | 2 |
| B9 | 性能微调 | T3-08 + T6-12、T6-08、T6-09、T6-10、T6-11 | 5 |
| B10 | AGENTS.md 模块清单与结构补全 | T2-07 + T7-07、T7-06、T7-08、T7-09、T7-11 | 5 |
| B11 | 文档标识/表述一致性 | T7-10、T7-12、T7-13、T7-14 | 4 |
| B12 | 测试规范与口径收口 | T8-04、T8-05、T8-06、T8-07† | 4 |

> 校验：4 + 3 + 2 + 3 + 6 + 4 + 4 + 2 + 5 + 5 + 4 + 4 = **46** ✓

---

## 3. 分阶段实施计划

### 3.1 Phase 0 — 紧急修复（P0 / Critical：CR1 / CR2 / CR3）

> **时间框**：立即（下一次运行/发布前）
> **执行顺序（强制）**：① CR1 工作区处置预案（唯一硬性前置）→ ② CR1 主体修复 → ③ CR2 → ④ CR3（CR2/CR3 可在 CR1 处置完成后并行，但不得与 CR1 源码改动交叉混入同一提交）

#### 3.1.0 CR1 工作区 4 个未提交文件处置预案（⚠️ 唯一硬性前置，必须先于一切修复执行）

> **原则**：**严禁 `git checkout <file>` / `git restore <file>` / `git reset --hard` 直接回滚或覆盖工作区未提交改动**——这些改动可能是用户有意为之（如 M13 后 `_SortBackupsByTime` 的临时回退、迁移日志 include 清理）。每一步先备份、再确认归属，仅对「确定为半回退拆坏」的部分做定向恢复。

**工作区 4 个未提交文件的 diff 实测（`git diff` 确认）**：

| 文件 | 未提交改动性质 |
|------|----------------|
| `main.ahk` | 删除 `#Include "infrastructure\config_io.ahk"` + `#Include "application\backup_service.ahk"`；OnExit 回退为仅 `SkillManager.OnExit()`（撤销 `JoyHotkeyManager.Shutdown()`） |
| `infrastructure/backup_core.ahk` | ① 删除 `#Include "config_io.ahk"` + `#Include "utils.ahk"`；② `:70` `ConfigIO.ExportToFile` → `ExportConfigToFile`（反向依赖回归）；③ `_SortBackupsByTime` 回退为手动插入排序（撤销 M13 的 `_SortByField` 复用） |
| `infrastructure/migration_logger.ahk` | 删除 `#Include "utils.ahk"` |
| `tests/run_all_tests.ahk` | +2074 行（新增大量测试类）；**删除 `BackupServiceLayeringTests`、`ConfigIOLayeringTests` 等 12 个 suite 的注册** |

> ⚠️ 注意：`backup_core.ahk` 的未提交改动含 3 处独立变更，其中仅第 ② 项是 CR1 核心；处置时**不得**一刀切 `git checkout` 回滚。

**处置步骤（顺序执行）**：

1. **快照备份**：将 4 个文件的当前工作区版本复制到临时备份目录（`docs/review/2026-08-20/fix-plan/workspace-snapshot/`，以 `git rev-parse HEAD` 短哈希 + 时间戳命名），可用 `git diff > snapshot.patch` 同时保存 diff 快照。确保任何后续操作都可还原到处置前状态。
2. **逐文件确认归属（人工核对）**：

   | 文件 | 待确认点 | 判定 |
   |------|---------|------|
   | `main.ahk` | 删除 config_io/backup_service include + OnExit 回退 | 判定为「半回退拆坏」→ 归 CR1 Step 1 定向恢复 |
   | `infrastructure/backup_core.ahk` | 3 处独立改动：include 删除、:70 反向依赖、`_SortBackupsByTime` 回退 | include 删除 + :70 → 归 CR1 Step 2；`_SortBackupsByTime` 回退需单独确认（若为有意回退 M13，则保留，不属 CR1） |
   | `infrastructure/migration_logger.ahk` | 删除 `#Include "utils.ahk"` | 需确认 `MigrationLogger` 是否仍使用 `_GetField`/`_GetProp` 等 utils 工具；若不再使用，该删除为合理清理，保留；若仍使用，恢复 include |
   | `tests/run_all_tests.ahk` | 删除 12 个 suite 注册（含 `BackupServiceLayeringTests`/`ConfigIOLayeringTests`） | 需确认是「有意精简」还是「误删」；至少 CR1 验证依赖恢复 `BackupServiceLayeringTests`/`ConfigIOLayeringTests` 注册 |

3. **恢复 `main.ahk` 的 2 行 include + OnExit**（= §3.1.1 Step 1，作为处置后的第一个原子提交）。
4. **修 `backup_core.ahk:70` 反向依赖**（= §3.1.1 Step 2，恢复 `#Include "config_io.ahk"` + 改 `ConfigIO.ExportToFile`）。
5. **清理 `config_service.ahk` 无调用方包装**（= §3.1.1 Step 3）。
6. **跑 `layering_security_suites` 验证**（= §3.1.1 验证项），确认 `Test_BackupCore_NotCallExportConfigToFile` 断言通过、`BackupServiceLayeringTests`/`ConfigIOLayeringTests` 注册并全部通过。

> 只有在第 1~2 步完成、第 3~6 步验证通过后，工作区才算脱离「半回退状态」。此处置是 CR2/CR3 及其余 P1/P2 修复的先决条件。

#### 3.1.1 CR1 — 工作区半回退不一致状态：`ConfigIO`/`BackupService` 未接入生产入口

> 来源编号：T2-01 + T2-02（归并，对应基线 I1/I6 引入回归）

**问题描述**：I6 重构将配置读写下沉到 `infrastructure/config_io.ahk` 的 `ConfigIO` 类，`application/config_service.ahk:412-417` 通过全局函数 `ImportConfigFromFile`/`ExportConfigToFile` 委托 `ConfigIO.LoadFromFile/ExportToFile`，表现层已改为调用 `application/backup_service.ahk` 的 `BackupService.*`（I1 修复）。但当前工作区存在 4 个未提交文件（见 §3.1.0），其中 `main.ahk` 删除两行 include 并将 OnExit 回退为 `SkillManager.OnExit()`；`backup_core.ahk:70` 从 `ConfigIO.ExportToFile(...)` 回退为 `ExportConfigToFile(...)`。由于 AHK 的 `#Include` 不会自动解析全局类名，`ConfigIO`/`BackupService` 在生产环境**从未被定义**，任何一次配置读写/备份导出都会抛 `Unknown class`。单测 `tests/suites/layering_security_suites.ahk` 因单独 `#Include` 拉入 `config_io.ahk` 而掩盖了生产入口缺 include 的问题。

**影响范围**：
- 受影响模块：`main.ahk`（include 段 + OnExit）、`application/config_service.ahk`（:36/:106/:376/:412-417）、`infrastructure/config_io.ahk`（:21）、`infrastructure/backup_core.ahk`（:70）、`application/backup_service.ahk`
- 受影响路径（均触发 `Unknown class` 崩溃）：配置加载（`config_service.ahk:36`）、配置保存（`:106`/`:376`）、分组增删改（`group_service.ahk:227/236`）、GUI 全局设置保存（`gui_manager.ahk:212`）、备份导出/恢复（`backup_core.ahk:70` + `BackupService.*`）
- 连带：OnExit 缺失 `JoyHotkeyManager.Shutdown()`，退出时摇杆热键管理器钩子未清理。

**根本原因**：I6 重构只做了一半（新增 `ConfigIO` + 保留应用层全局包装），又叠加工作区对 `main.ahk`/`backup_core.ahk` 的未提交回退，形成半回退状态。

**具体修复步骤（原子提交粒度）**：

- **Step 0（唯一硬性前置）**：完成 §3.1.0「工作区 4 个未提交文件处置预案」。
- **Step 1 — 恢复 `main.ahk` 的接线（1 commit，`fix(ahk): 恢复 config_io/backup_service 生产入口 include`）**
  - 在基础设施层 include 段（`main.ahk:29` `#Include "infrastructure\error_system.ahk"` 之后、`main.ahk:30` `backup_core.ahk` 之前）恢复：`#Include "infrastructure\config_io.ahk"`
  - 在应用层 include 段（`main.ahk:51` `#Include "application\config_service.ahk"` 之后）恢复：`#Include "application\backup_service.ahk"`
  - 恢复两处 OnExit（`main.ahk:115`、`main.ahk:130`）为：`OnExit((*) => (JoyHotkeyManager.Shutdown(), SkillManager.OnExit()))`
  - ⚠️ `config_io.ahk` 自身 `#Include` 了 `json_logger/json_serializer/json_parser/error_handler`，且依赖 `ErrorHandler.RetryWithPolicy/SafeExecute`，故 `config_io.ahk` 必须在 `error_system.ahk` 之后、`backup_core.ahk` 之前加载（与 HEAD 顺序一致）。
- **Step 2 — 修复 `backup_core.ahk:70` 反向依赖（1 commit，`fix(ahk): backup_core 恢复 ConfigIO 写入消除反向依赖`）**
  - 在 `infrastructure/backup_core.ahk` 顶部（`backup_core.ahk:16` `#Include "json_parser.ahk"` 之后）恢复 `#Include "config_io.ahk"`；
  - 将 `backup_core.ahk:70` 改为：`exportResult := ConfigIO.ExportToFile(BackupCore.currentConfigPath, config)`
  - ⚠️ 仅改这两处；**不要**动 `_SortBackupsByTime` 未提交回退（其归属在 §3.1.0 单独确认，不属 CR1 范围）。
- **Step 3 — 清理 `config_service.ahk` 无调用方的全局包装（1 commit，`refactor(ahk): config_service 移除 ImportConfigFromFile/ExportConfigToFile 全局包装`）**
  - 将 `application/config_service.ahk` 内部 3 处调用点改为直接调用 `ConfigIO`：`:36`、`:106`、`:376` 均改为 `ConfigIO.LoadFromFile/ExportToFile`。
  - 删除 `config_service.ahk:407-418` 的「通用 IO 函数」整段（含注释与 `ImportConfigFromFile`/`ExportConfigToFile` 两个全局函数）。
  - 说明：必须先改内部调用点再删包装，否则删后即产生 `Unknown function` 编译错误。
- **Step 4 — 验证**（见下）。

**测试验证方案**（引用 AGENTS.md 三步前置检查流程）：
1. 语法检查（stderr 重定向 + 退出码验证）——对 `main.ahk`/`application\config_service.ahk`/`infrastructure\backup_core.ahk`/`infrastructure\config_io.ahk` 分别 `/ErrorStdOut` 检查，退出码须为 0、stderr 为空。
2. 接管指令验证——确认改动文件顶部仍含 `#ErrorStdOut`、`#Warn VarUnset`、`#Warn Unreachable`、`#Warn LocalSameAsGlobal`；`main.ahk` 仍含 `OnError(ErrorSystem_HandleError, -1)`。
3. 运行时验证——启动主脚本确认退出码 0、无 `Unknown class` 弹窗。
4. 分层回归测试——运行 `tests\run_all_tests.ahk`，重点确认 `BackupServiceLayeringTests`（8 断言）与 `ConfigIOLayeringTests`（含 `Test_BackupCore_NotCallExportConfigToFile`）注册并全绿。
5. 功能路径验证——触发一次「保存配置」「导入配置」「创建备份/恢复备份」，确认无 `Unknown class` 崩溃。

**回滚机制**：Step 1/2/3 各为独立 commit，可分别 `git revert`；处置预案兜底用 §3.1.0 Step 1 快照 `snapshot.patch` 还原；禁止 `git reset --hard` / `git checkout -- .`。Step 1/2 是「恢复 HEAD 已有基线内容」，天然可逆；Step 3 是纯删除，`git revert` 即可恢复。

**修复后效果评估标准**：

| # | 判据 | 达标值 |
|---|------|--------|
| 1 | 语法检查退出码 | 4 个文件均为 0，stderr 为空 |
| 2 | 启动无崩溃 | 退出码 0，`logs/app.log` 无 `Unknown class: ConfigIO` / `Unknown class: BackupService` |
| 3 | 分层断言 | `Test_BackupCore_NotCallExportConfigToFile` 通过；`ConfigIOLayeringTests`/`BackupServiceLayeringTests` 全绿 |
| 4 | 反向依赖消除 | `backup_core.ahk` 源码文本 `InStr(content, "ExportConfigToFile") == 0` |
| 5 | 工作区干净 | `git status --short` 不残留「半回退」状态（4 文件均有明确处置结果） |
| 6 | OnExit 完整 | `main.ahk` 两处 OnExit 均含 `JoyHotkeyManager.Shutdown()` |

**时间框**：处置预案 T+0 立即执行；Step 1~3 约 0.5 小时；验证约 0.5 小时；合计 **T+0 ~ T+0.5 天**。

**资源需求**：1 名熟悉 AHK 分层与 `#Include` 加载顺序的开发者（执行）+ 1 名熟悉工作区 4 文件改动背景的复核人（归属确认）；工具 `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`、git、PowerShell；约 0.5~1 人天。

**风险评估与应对**：

| 风险 | 等级 | 应对 |
|------|------|------|
| 误覆盖/误回滚用户未提交改动 | 高 | §3.1.0 先备份 + 逐文件人工确认归属；仅定向恢复「半回退拆坏」部分 |
| `layering_security_suites.ahk` 静态断言对源码格式敏感 | 中 | Step 2 改 `:70` 保持单行 `ConfigIO.ExportToFile(...)` 写法 |
| `config_io.ahk` 加载顺序错误致 `ErrorHandler` 未定义 | 中 | 严格按 `error_system.ahk` → `config_io.ahk` → `backup_core.ahk` 顺序 |
| Step 3 删包装后遗漏内部调用点 | 中 | 改前 `grep` 确认仅 :36/:106/:376 三处 |
| 处置期间误触发运行崩溃 | 低 | 处置全程不运行 `asd.ahk` |

**责任角色**：执行人（配置/接线修复负责人）、复核人（Tech Lead，归属确认 + diff 审查）、验收人（QA，执行验证并签字）。

#### 3.1.2 CR2 — 执行器每键 down/up 无条件 IPC 序列化 + 同步阻塞写命名管道

> 来源编号：T6-01

**问题描述**：`ahk_executor/sender.ahk:494-522` 的 `_SendKeyDown`/`_SendKeyUp` 每次按键动作都无条件调用 `IpcClient._SendMsg` 上报 Rust；`ipc_client.ahk:792-818` 的 `_SendMsg` 内部执行 `MiniJson.Stringify` → 两次 `StrPut` → `Buffer` 分配 → 同步 `WriteFile`。管道以无 `FILE_FLAG_OVERLAPPED` 方式打开（`ipc_client.ahk:533-541`），写为同步阻塞。周期性 50ms 间隔下单键 = 每秒 40 次消息，每次 2 次 JSON 序列化 + 2 次 Buffer 分配 + 2 次同步管道写，且无背压上限。

**影响范围**：所有周期/序列/混合/hold/enhanced 模式的按键执行热路径。前端卡顿 → outbound 慢 → 管道满 → 同步 `WriteFile` 阻塞 AHK 消息循环 → 反向冻结执行。

**根本原因**：`key_send_event` 仅用于前端展示/反馈，却与最热路径强耦合；管道写为同步阻塞、无 `OVERLAPPED`/背压上限。

**具体修复步骤（原子提交粒度）**：

- **Step 1 — 引入按需上报开关（1 commit，`perf(asd-tauri): 执行器逐键 IPC 上报改为录制/验证模式才发送`）**
  - 在 `sender.ahk` 的 `Sender` 类静态属性区（`sender.ahk:17-28` 附近）新增 `static _reportKeyEvents := false`
  - 在 `_SendKeyDown`（`sender.ahk:494-507`）中，`SendInput` 与 `IpcClient._SendMsg` 之间插入 `if !Sender._reportKeyEvents` 后 `return`（`SendInput` 始终执行；仅 `_reportKeyEvents = true` 时才发送 `key_send_event`）；`_SendKeyUp`（`sender.ahk:509-522`）同理。
  - ⚠️ 这里用的是 `if` 普通语句，非 `=> { }` 箭头块体，安全。
- **Step 2 — 由 CommandDispatcher 控制开关（1 commit，`perf(asd-tauri): 录制/验证状态联动按键上报开关`）**
  - `start_recording` 分支（`executor.ahk:164` 后）追加 `Sender._reportKeyEvents := true`；`stop_recording`（`:174` 后）追加 `:= false`；`start_validation`（`:246` 后）/`stop_validation`（`:253` 后）同理。
  - ⚠️ 采用「Sender 维护自身开关、由 CommandDispatcher 设置」，避免 `sender.ahk` 反向引用 `CommandDispatcher`。
- **Step 3 — 管道写降级/非阻塞兜底（1 commit，`perf(asd-tauri): IPC 管道写失败降级跳过上报`）**
  - 在 `ipc_client.ahk:792-818` 的 `_SendMsg` 中，`WriteFile` 失败路径优化为「降级跳过 + 记录一次 DEBUG（限速）」，避免失败即断连。更彻底的 `FILE_FLAG_OVERLAPPED` + 事件轮询异步化作为 P1（G4 组 T6-05/T6-06）一并实施。

**测试验证方案**：三文件语法检查 + 接管指令验证 + 运行时验证；执行器回归（`test_sender` 11 套件 / `test_ipc_client` 12 套件 / `test_executor` 9 套件）；新增回归用例 `Test_SendKeyDown_SkipsReporting_WhenNotRecording`、`Test_SendKeyDown_Reports_WhenRecording`、`Test_StartRecording_SetsReportFlag`/`Test_StopValidation_ClearsReportFlag`。

**回滚机制**：每 Step 独立 commit，可 `git revert` 单独回滚。

**修复后效果评估标准**：

| # | 判据 | 达标值 |
|---|------|--------|
| 1 | 非录制/验证模式 IPC 消息量 | 逐键 `key_send_event` 上报为 0 |
| 2 | 录制/验证模式行为不变 | `_reportKeyEvents = true` 时仍按原样发送，相关套件全绿 |
| 3 | 语法检查 | 三文件退出码 0 |
| 4 | 执行器既有套件回归 | `test_sender`/`test_ipc_client`/`test_executor` 全绿 |
| 5 | 状态切换正确性 | 四分支与 `_reportKeyEvents` 联动断言通过 |

**时间框**：T+0 ~ T+1（不阻塞运行，须在 CR1 处置完成后开展；不得与 CR1 混入同一提交）。

**资源需求**：1 名熟悉执行器 IPC 与 `#Include` 关系的开发者 + 1 名复核人；约 0.5~1 人天。

**风险评估与应对**：

| 风险 | 等级 | 应对 |
|------|------|------|
| 关闭逐键上报导致前端「按键回显/反馈」缺失 | 中 | 仅录制/验证模式开启，明确语义边界并记录 |
| `sender.ahk` 反向引用引入新依赖环 | 中 | 禁止 sender 引用 CommandDispatcher |
| Step 3 改变断连语义 | 中 | 保守实现：仅 DEBUG 降级跳过 |
| 与 CR1 的 `tests/run_all_tests.ahk` 未提交改动耦合 | 高 | 必须先完成 CR1 处置 |

**责任角色**：执行人（执行器性能优化负责人）、复核人（IPC/执行器技术负责人）、验收人（QA）。

#### 3.1.3 CR3 — `docs/developer-guide.md` 整篇基于已废弃单 crate 结构

> 来源编号：T7-01

**问题描述**：`docs/developer-guide.md` §1.2（L51-85）仍把 Rust 源码描述为 `src-tauri/src/{domain,application,infrastructure}/` 三子模块（已不存在）；`models.rs` 被描述为「IpcCommand 9 变体」（实际 13 变体，已移到 `asd-ipc-protocol/src/command.rs`）；§2.3.3（L226-236）IpcCommand 表缺 `PauseRecording/ResumeRecording/StartValidation/StopValidation`；附录 E（L975-993）称「13 个 Tauri Command」（实际 34 个）；§1.1（L29）称 api.js「13 个 invoke + 19 个 stub」。

**根本原因**：文档写于 2026-05-29，早于 crate 抽取（workspace 化）与命令扩充，此后未同步更新。

**具体修复步骤（原子提交粒度）**：

- **Step 1 — 重写 §1 为 5-member workspace 结构（`docs: 重写 developer-guide §1 为 5-crate workspace 结构`）**：以 AGENTS.md「Rust/Tauri 架构（5-Crate Workspace）」为蓝本；§1.2 改为 `crates/asd-domain`/`asd-ipc-protocol`/`asd-application`/`asd-test-harness`/`src-tauri`；`models.rs` 的「IpcCommand 9 变体」修正为「13 变体，定义于 `crates/asd-ipc-protocol/src/command.rs`」。
- **Step 2 — 重写 IpcCommand 表为 13 变体（`docs: developer-guide IpcCommand 表补全 13 变体`）**：补齐 `ToggleGroup`、`RegisterHotkey`、`UnregisterHotkey`、`StartRecording`、`StopRecording`、`PauseRecording`、`ResumeRecording`、`EmergencyRelease`、`Ping`、`Shutdown`、`HoldModeToggle`、`StartValidation`、`StopValidation`。
- **Step 3 — 修正附录 E 与 api.js 计数（`docs: developer-guide 附录E 修正为 34 个 Tauri Command`）**：按 `src-tauri/src/commands/` 下 5 个命令文件重列，改为「34 个 Tauri Command」并补全缺失命令；§1.1/§1.4 api.js 计数按 `asd-tauri/src/api.js` 实际核对修正。
- **Step 4 — 顶部标注 + 交叉引用（可选并入 Step 1）**：顶部增加「本文档以 AGENTS.md 为最权威来源」声明，或整篇标注「已过时，以 AGENTS.md 为准」并归档（二选一，需与文档 owner 确认）。

**测试验证方案**：纯文档一致性核对——目录树与 `asd-tauri/` 实际目录对应；IpcCommand 表与 `command.rs` 13 variant 逐一比对；Tauri Command 计数与 `lib.rs` `generate_handler![...]` 比对至 34（注意 `EXPECTED_TAURI_COMMAND_COUNT` 的永真式局限，见 T5-02）；`grep`/`Select-String` 确认真无残留「9 变体」「13 个 Tauri Command」「domain/application/infrastructure」表述。**不适用** AHK 三步前置检查（纯文档，无 .ahk 改动）。

**回滚机制**：纯 Markdown 改动，每 Step 独立 commit，`git revert` 即可回滚。

**修复后效果评估标准**：

| # | 判据 | 达标值 |
|---|------|--------|
| 1 | 目录结构 | 不含 `src-tauri/src/{domain,application,infrastructure}/` 三子模块描述，含 5-member workspace |
| 2 | IpcCommand 变体数 | 文档表含 13 变体 |
| 3 | Tauri Command 数 | 标注 34 个 |
| 4 | api.js 计数 | 与 `asd-tauri/src/api.js` 实际一致 |
| 5 | 断链 | 每个文件链接路径在仓库可解析 |

**时间框**：T+0 ~ T+1（可与 CR2 并行；仅改 `docs/`，无冲突）。

**资源需求**：1 名技术文档负责人；git + 文本编辑器；约 0.5~1 人天。

**风险评估与应对**：

| 风险 | 等级 | 应对 |
|------|------|------|
| 与 AGENTS.md/test-map.md 又产生口径漂移 | 中 | 单一权威来源策略，文档内显式声明来源 |
| 重新计数遗漏个别命令 | 中 | `grep -n "#\[tauri::command\]"` 机械化统计 |
| 与 T7-02 重复劳动 | 中 | 本 CR3 仅处理 developer-guide.md |

**责任角色**：执行人（技术文档负责人）、复核人（架构负责人）、验收人（评审人）。

---

### 3.2 Phase 1 — 重要修复（P1 / Important：23 项，10 个主题批次）

> **时间框**：短期（紧随 Phase 0），全部 10 批建议 ≤ 2 周（可部分并行）
> **原子提交原则**：每批次可拆分多个原子提交（一次提交只改一个关注点）
> **建议执行顺序**：① G3→G6→G8（AHK 执行器/领域层热路径，联动回归）→ ② G4→G5（src-tauri 后端，统一 `cargo test --lib`）→ ③ G1→G7→G2 → ④ G9（测试补强，与代码批次并行/交叉）→ ⑤ G10（文档，最后收口）

#### G1 — 校验覆盖缺口（T3-01、T3-02、T3-03、T4-04）

**问题描述**：配置验证器多层校验路径不一致导致非法输入静默放行，AHK 与 Rust 各有一处同类缺口。
- **T3-01**（`infrastructure/config_validator.ahk:115-138`）：`ValidateGroupOnly` 只查 `hotkey` 是否 `_HasField`，不校验格式，而 `CreateGroup/UpdateGroup` 正走此入口。
- **T3-02**（`infrastructure/config_validator.ahk:140-284`）：`_ValidateModeFields` 从不校验按键名合法性，领域层 `SkillGroup._IsValidKeyName`（`skill_group.ahk:889-902`）运行时静默跳过，形成隐蔽故障。
- **T3-03**（`infrastructure/config_validator.ahk:286-299`）：`_ValidateHotkeys` 只查非空不查格式，控制热键可写非法值。
- **T4-04**（`crates/asd-domain/src/validator.rs:90-94,137-139`）：`validate_hotkey_format` 对空串（137-139 行）直接 `return`，`"emergency": ""` 静默通过；`validate_duplicate_hotkeys` 未做「控制热键 vs 分组热键」交叉冲突检测。

**根本原因**：验证器已存在共享校验原语（`_IsValidHotkeyFormat` / `validate_hotkey_format`），但新增/补丁路径未复用；且 AHK 与 Rust 两侧独立演进，同类缺口出现两次。

**具体修复步骤（4 个原子提交）**：
1. **提交 1（T3-01）**：`ValidateGroupOnly` hotkey 分支改为与 `_ValidateGroup` 一致（保留存在性 ERROR + 追加 `_IsValidHotkeyFormat` 校验 → 非法 ERROR）。
2. **提交 2（T3-02）**：将 `_IsValidKeyName` 逻辑下沉为共享工具（建议 `infrastructure/utils.ahk`，或先在 validator 内私有复制并标注同步）；`_ValidateModeFields` 各 mode 分支对 `keys/pressKeys/holdKeys/joyKeys` 元素逐个校验（`joyKeys` 走 Joy 数字/轴/POV 规则，可用 `infrastructure` 引用 `domain/joystick_input.ahk` 纯工具类，符合 AGENTS.md 已备案妥协 #1）。
3. **提交 3（T3-03）**：`_ValidateHotkeys` 对每个非空 action 值追加 `_IsValidHotkeyFormat` 校验（空值保留 WARNING，非法格式升级 ERROR）。
4. **提交 4（T4-04）**：`validate_config` 对 5 个控制热键改为先判 `is_empty()` → `add_error`，非空再 `validate_hotkey_format`；扩展 `validate_duplicate_hotkeys` 把 5 个控制热键纳入 `seen` 集合做交叉冲突检测。

**测试验证方案**：AHK `run_all_tests.ahk` + 新增用例（`ValidateGroupOnly` 非法热键 → ERROR；各 mode 非法按键名 → ERROR；`emergency:"garbage"` → ERROR / 空值 → WARNING）；Rust `cargo test -p asd-domain` + 控制热键空值用例 `!result.is_valid()`、控制热键 vs 分组热键同名 → 冲突 error。

**回滚机制**：全部为「新增校验分支」，`git revert` 单提交即回。

**效果标准**：四类非法输入（分组热键/按键名/控制热键/控制热键冲突）在验证阶段被拦截，不再写入 config.json；`cargo test -p asd-domain` 全绿、AHK 无回归。

**责任角色 + 时间框**：AHK 领域/基础设施开发者（提交 1/2/3）+ asd-domain 开发者（提交 4）；1~2 个工作日。

#### G2 — 热路径日志无限速（T3-05 + T6-03，合并项）

**问题描述**：AGENTS.md 承诺「Execute* 热路径日志每秒最多一次」，但 `ErrorSystem.LogError`→`_WriteLog`（`error_system.ahk:185-213`）与 `JSONLogger._WriteLog`（`json_logger.ahk:179-227`）均无限速；`DebugLogger`（`debug_logger.ahk:22,52-56`）仅有 50ms 间隔（非「每秒一次」）且仅覆盖 DEBUG。持续抛异常时以 10-50ms 周期反复落盘。T3-05 侧重「错误日志落盘无限速」，T6-03 侧重「DebugLogger 口径与承诺不符」。

**根本原因**：错误路径缺少「令牌桶/滑动窗口」限速器；限速承诺仅在 `DebugLogger` 部分实现，未下沉到统一落盘入口。

**具体修复步骤（2 个原子提交）**：
1. **提交 1（T3-05）**：`ErrorSystem` 与 `JSONLogger` 加入与 `DebugLogger` 同构的限速器（`_lastWriteTime` + `_suppressedCount` + 按调用源分桶的 `Map`）；`_WriteLog`/`_LogToFile` 入口同源窗口内仅累加计数并跳过 `Stringify`+`FileAppend`，落盘时附 `suppressedCount=N`。
2. **提交 2（T6-03）**：`DebugLogger` 50ms 阈值与「每秒一次」对齐为共享常量 `LOG_RATE_LIMIT_MS := 1000`，三处 logger 引用同一阈值（或修正文档二选一并明确）。

**测试验证方案**：同一源连续调 `LogError` N 次，断言落盘 ≤ 1 次且抑制计数正确（mock writer 或统计日志行数）。

**回滚机制**：限速器为纯增量，回退单提交即恢复旧行为。

**效果标准**：同源高频异常下 `FileAppend` 频率 ≤ 1 次/秒，每条含 `suppressedCount`；度量：持续 1 秒异常，`logs/app.log` 对应行数增长 ≤ 1。

**责任角色 + 时间框**：AHK 基础设施开发者；1 个工作日。

#### G3 — 定时器生命周期（T6-02、T6-04）

**问题描述**：
- **T6-02**（`domain/skill_group.ahk:800-805`；`ahk_executor/sender.ahk:347,394,444,464`；`ahk_executor/joystick.ahk:203,253`；`domain/joystick_executor.ahk:55,107`）：每次按下现造闭包 + 一次性 SetTimer，up 定时器未纳入 Map 跟踪，分组停止时不被取消。
- **T6-04**（`ahk_executor/sender.ahk:178-194,197-215,290-305`、`joystick.ahk:68-85`、`executor.ahk:102-107`）：`StartXxx` 直接覆盖 `_timers[groupId]` 引用而不先取消旧定时器 → 双倍发键。

**根本原因**：定时器作为资源未统一纳管——「启动定时器」与「跟踪/清理定时器」未成对。

**具体修复步骤（2 个原子提交，先幂等后纳管）**：
1. **提交 1（T6-04，先修时序）**：各 `StartXxx` 开头插入幂等保护 `if _timers.Has(groupId) { SetTimer(旧引用,0); Delete(groupId) }`；或在 `executor.ahk:102-107` 增加「已激活且配置相同 → 直接 return」短路。
2. **提交 2（T6-02）**：领域层 `_SendKey` 的 `releaseTimer` 登记进 `_releaseTimers` Map，去除逐键现造闭包；执行器层维护「已按下键集合 + 单一周期释放扫描定时器」，或一次性定时器句柄登记进派生 Map，停止分组时统一 `SetTimer(句柄,0)`。

**测试验证方案**：`test_sender`/`test_joystick`/`test_domain` 新增用例——同 groupId 连续两次 `StartPeriodic` 断言仅 1 个活跃引用；分组停止后无滞后 `_SendKeyUp`。

**回滚机制**：提交 1 回退恢复旧行为；提交 2 若改动面大可先只做「一次性定时器登记进 Map」最小改动。

**效果标准**：重复 `toggle_group(active=true)` 不双倍发键、无重复定时器；停止后无滞后 up；「重复 start 后活跃定时器数 == 1」断言通过。

**责任角色 + 时间框**：AHK 执行器开发者 + AHK 领域层开发者；1~2 个工作日。

#### G4 — IPC 背压与阻塞（T6-05、T6-06）

**问题描述**：
- **T6-05**（`src/bridge.rs:44-67,69-129`；`src/infrastructure/ipc.rs:290-327`）：同步 `IpcSender` trait 用 `block_in_place + block_on`；`send()` 无写超时，AHK 挂死且管道写满时无限阻塞工作线程。
- **T6-06**（`src/infrastructure/ipc.rs:545,567-572,504,18`）：先 `msg.clone()` 再判断响应归属，非响应消息被无谓深拷贝；`outbound_tx.send(msg).await` 无界阻塞监听循环，反向压死 AHK。

**根本原因**：IPC 写入/分发链路缺乏「超时兜底」与「背压上限」。

**具体修复步骤（2 个原子提交）**：
1. **提交 1（T6-05）**：`send()` 的 `write_all`+`flush` 包 `tokio::time::timeout(2000ms, ...)`，超时 → 清理 `send_half`、`notify_pipe_broken()`、返回超时错误。（长期方向注释标注：将 `IpcSender::send_command` 改 async，消除 `block_in_place + block_on`，与已知妥协 #2 协同。）
2. **提交 2（T6-06）**：`listen_ahk` 先判 `msg.ack_seq.is_some()` 再决定是否 clone（无 ack_seq 直接转移所有权）；高频非关键类型用 `try_send` + 满则丢弃/合并，关键 `hotkey`/`pong` 保留 `.await`。

**测试验证方案**：`cargo test --lib` + 新增用例（写端阻塞场景 `send()` 超时返回 `Err`；慢 outbound 场景 `try_send` 满丢弃且监听循环不被阻塞；无 `ack_seq` 消息不触发深拷贝）。

**回滚机制**：提交 1 回退恢复「无超时」旧行为；提交 2 回退仅恢复 `.await` 发送。

**效果标准**：AHK 挂死时 `send()` 在超时上限内返回错误；`listen_ahk` 高频下 CPU/内存稳定；`cargo test --lib` 全绿 + 人工挂起 AHK 验证 UI 不冻结。

**责任角色 + 时间框**：Rust 后端开发者；1~2 个工作日。

#### G5 — unsafe soundness（T5-01）

**问题描述**（`src/infrastructure/watchdog.rs:67,73,499,502`）：`ProcessWatchdog` 含 `Option<Child>`（`Send + !Sync`），手工 `unsafe impl Sync`；`JobObjectGuard(HANDLE)` 手工 `Send/Sync`。当前不变量成立，但 `state()`（118-120 行）返回 `&WatchdogStateEnum`，一旦未来把引用保存到 guard 之外 → 跨锁共享引用 → 数据竞争 → UB。

**根本原因**：为把含 `!Sync` 字段结构体装入 `Arc<Mutex>` 跨线程共享，选择手工 `unsafe impl` 而非重构；`state()` 的 `&` 返回把「锁内借用」暴露为「可能跨锁存活」的接口。

**具体修复步骤（⚠️ 先降风险顺序 + 独立风险评估）**：
1. **提交 1（低风险，先做）**：`state()` 改为返回 `WatchdogStateEnum`（`self.state.clone()`），同步更新所有调用方由 `&` 解引用改为值比较；文档注释补「返回快照，与锁生命周期解耦」。
2. **提交 2（回归测试先行）**：先加 `#[tokio::test]` 用例验证 `ProcessWatchdog`/`JobObjectGuard` 可安全跨 `tokio::spawn` 移动并被 Mutex 保护访问（作为改动前回归基线）。
3. **提交 3（可选、更彻底）**：评估将 `child` 拆出或重构数据面以移除 67/73 行 `unsafe impl`；短期无法移除则在 4 处补强化 SAFETY 注释并登记为待收敛项。

> **专项风险评估**：`state()` 返回类型变更为编译期可查，风险中；拆分 `unsafe impl` 风险较高（须在提交 2 回归测试通过后进行，每次改动单独 commit）。不推荐仅靠文档说明「引用不得跨锁存活」而不改代码。

**测试验证方案**：`cargo test --lib` + `cargo build`；提交 1 后所有调用方编译通过；提交 2 新增跨线程移动 + 锁保护访问用例。watchdog 属 src-tauri 无法 Miri，改为并发压力用例 + `cargo test --lib` 全绿。

**回滚机制**：提交 1 纯接口变更 `git revert` 即回；提交 3 以单提交粒度 revert。

**效果标准**：`state()` 不再返回跨锁引用；`grep "unsafe impl" watchdog.rs` 由 4 处降至 0（或剩余处有强化 SAFETY 注释并登记）；`cargo test --lib` 全绿。

**责任角色 + 时间框**：Rust 后端开发者（具备 unsafe/并发安全经验）；1~2 个工作日（含回归测试与 `cargo build` 回测）。

#### G6 — vJoy 设备复用（T6-07）

**问题描述**（`ahk_executor/joystick.ahk:299-317,360-395,444-454,435-441`）：每次按键事件 `_VJoyOpen → _VJoyClose` 引用计数 0→1→0 快速往返，等价每次事件一次 `AcquireVJD` + `RelinquishVJD`；`_GetAxisInfo` 每次重建含 6 个子 Map 的新 Map，`_IsAxis` 每次重建数组，轴类键每次 down/up 产生 12 个 Map 分配。

**根本原因**：vJoy 设备「即开即关」峰值复用 + 识别表未做一次性缓存。

**具体修复步骤（2 个原子提交）**：
1. **提交 1（设备生命周期提升）**：vJoy 设备生命周期提升到组级（组启动 `_VJoyOpen`/Acquire 一次，组停止/紧急释放 `_VJoyClose`/Relinquish 一次）；`_VJoySetBtn/_VJoySetAxis/_VJoySetPov` 移除包裹的运行期 Acquire/Relinquish。须覆盖 `emergency_release` 调用链。
2. **提交 2（识别表静态缓存）**：`_GetAxisInfo`/`_IsAxis` 结果做 `static` 一次性缓存。

**测试验证方案**：`test_joystick.ahk` 新增用例——组启动到停止 `_vJoyRefCount` 在组存活期为 1、停止后为 0，无「每事件 0↔1」往返（mock Acquire/Relinquish 计数）；`_GetAxisInfo`/`_IsAxis` 返回缓存实例。

**回滚机制**：提交 1 若紧急释放遗漏可单提交回退；提交 2 纯缓存零风险。

**效果标准**：单次按键事件不触发 Acquire/Relinquish；组级跨度内 `_vJoyRefCount` 稳定为 1；轴识别表不再每事件重建（组存活期内 Acquire=1/Relinquish=1）。

**责任角色 + 时间框**：AHK 执行器开发者；1 个工作日。

#### G7 — 隐式依赖与永真断言（T2-03、T2-04、T5-02）

**问题描述**：
- **T2-03**（`infrastructure/utils.ahk:13` → `json_parser.ahk:15` → `json_logger.ahk:16` → `utils.ahk`）：三模块形成三节点 `#Include` 环。
- **T2-04**（`infrastructure/config_store.ahk:95,14`）：`Set()` 调用 `JSONLogger.Log` 却未显式 `#Include "json_logger.ahk"`。
- **T5-02**（`src/lib.rs:606-615`）：`assert!(EXPECTED_TAURI_COMMAND_COUNT == 34)` 右侧 `34` 是独立字面量，与 `generate_handler![...]` 列表无绑定，「常量自比」永真式。

**具体修复步骤（3 个原子提交）**：
1. **提交 1（T2-03，打破环）**：移除 `utils.ahk:13` 的 `#Include "json_parser.ahk"`；`_GetField`（41-55 行）的 JSON 字符串解析能力由调用方先解析后传入，或删该分支仅保留 Map/Object 属性访问；确认去环后加载顺序。
2. **提交 2（T2-04）**：`config_store.ahk:14` 后补 `#Include "json_logger.ahk"`（视需补 `json_parser.ahk` 以获得 `JSONErrorType`）。
3. **提交 3（T5-02）**：删除永真式断言与 `EXPECTED_TAURI_COMMAND_COUNT`（或降级为 `#[cfg(test)]` 测试/文档注释）；改为测试中真实统计 `generate_handler![...]` 列表长度比对，或注释改写「仅供文档参考」并登记 test-map.md。

> 顺序：先提交 1（环）再提交 2（include 自足），避免环未断时补 include 反而强化环。

**测试验证方案**：`utils.ahk` 独立加载单测；单独 `#Include "config_store.ahk"` 最小脚本不抛 `Unknown class`；`#[cfg(test)]` 断言命令清单长度 == 期望值。

**回滚机制**：提交 1 若致 `_GetField` 能力缺失需先补调用方先解析；提交 2/3 零风险。

**效果标准**：`utils.ahk` 不再 `#Include` `json_parser.ahk`；`config_store.ahk` 独立加载不崩；`lib.rs` 无永真式断言。

**责任角色 + 时间框**：AHK 基础设施开发者（1/2）+ Rust 后端开发者（3）；0.5~1 个工作日。

#### G8 — 输入误报与注入检查（T3-04、T3-06）

**问题描述**：
- **T3-04**（`presentation/gui_manager.ahk:408-438`）：`GlobalSettingsEditor._Save` ① 422-424 行直接 `Integer(Edit.Text)`，非数字抛 `ValueError` 被外层 catch 吞掉；② 432 行忽略 `SaveConfig()` 返回值，433 行无条件 `MsgBox("全局设置已保存")`，保存被验证阻止仍报「已保存」。
- **T3-06**（`domain/joystick_executor.ahk:55,107,157-160`）：`_SendJoyKey` 159-160 行注入检查在热路径内，`JoystickHoldExecutor.Execute`（136-137 行）同样受影响，未注入时每 tick 记一次 ERROR 日志（与 G2 叠加放大高频写盘）。

**根本原因**：错误处理放错位置/粒度——一个「校验失败后误报成功」，一个「注入检查放在热路径而非模式启动前」。

**具体修复步骤（2 个原子提交）**：
1. **提交 1（T3-04）**：`_Save` 对 `debounceDelay/checkInterval/pressSpeed` 逐字段 try-catch 转换，非法提示并中止；检查 `SaveConfig()` 返回值，失败 `MsgBox("保存失败")`，成功才弹「已保存」+ `Destroy()`（对齐 `_BridgeSaveSettings`）。
2. **提交 2（T3-06）**：joystick 模式激活前（`Toggle`/`_SetupMode`）完成 `_joySender` 注入检查，未注入一次性 ERROR/告警并阻止进入执行循环；`_SendJoyKey` 内部注入检查降级为防御性二次检查/静默跳过。

**测试验证方案**：`_Save` 非数字输入 → 弹错且不调 `SaveConfig`；`SaveConfig` 返回 false → 不弹「已保存」；未注入激活 joystick → 激活前拦截、`Execute` 不进高频异常、日志无每 tick ERROR。

**回滚机制**：回退单提交恢复旧行为。

**效果标准**：保存失败用户看到「保存失败」；joystick 未注入仅启动期拦截一次，运行期 `logs/app.log` ERROR 计数 ≤ 1。

**责任角色 + 时间框**：AHK 表现层开发者（T3-04）+ AHK 领域层开发者（T3-06）；0.5~1 个工作日。

#### G9 — 测试覆盖补强（T8-01、T8-02、T8-03）

**问题描述**：
- **T8-01**（`src/infrastructure/ipc.rs` `listen_ahk`）：消息接收循环（accept → 解析 JSON → 按 type 分发 hotkey/heartbeat/recording）缺直接单测；malformed JSON、未知 type、空 data 无白盒覆盖。
- **T8-02**（`src/lib.rs` `perform_graceful_shutdown`）：仅 `try_acquire_shutdown_guard` 已测；关机主体（IPC Shutdown + watchdog stop + 销毁窗口 + 二次调用拦截）无测试。
- **T8-03**（`asd-tauri/e2e/specs/*.spec.js` 9 文件）：四段生命周期代码每 spec ~60 行共 ~500 行重复；`appendKnownIssue` 级别硬编码 `'HIGH'`；caseId 提取正则各自维护。

**根本原因**：可测试部分未从 async/生命周期方法中抽离为纯函数/mock 友好 seam。

**具体修复步骤（3 个原子提交）**：
1. **提交 1（T8-01）**：参照 `try_acquire_shutdown_guard` 模式，抽取 `parse_and_dispatch(message_bytes) -> Option<DispatchAction>`（或 `parse_message` + `dispatch`）纯函数，补单测覆盖三分支 + 三类边界。
2. **提交 2（T8-02）**：复用 `asd-test-harness` 的 mock `IpcSender`/`ProcessWatcher`，为 `perform_graceful_shutdown` 补序列集成测试（锁未获取提前返回 / 按序 IPC Shutdown + watchdog stop / 二次调用拦截）。
3. **提交 3（T8-03）**：抽 `helpers/spec-hooks.js` 统一 before/afterEach；`appendKnownIssue` 级别从 test 元数据传入；caseId 提取收敛一处（`E2E-<SUITE>-NNN`）。

**测试验证方案**：`cargo test --lib`（新增白盒/序列用例）；`cd asd-tauri/e2e; npm test` 全绿且 9 个 spec 行数显著下降。

**回滚机制**：均为新增测试/重构基建，不影响生产代码路径（提交 1 纯函数抽取属等价重构，可单提交回退）。

**效果标准**：IPC 分发与优雅关机有白盒/序列测试护航；E2E 冗余 ~500 行收敛到共享 hook；`grep appendKnownIssue` 无 `'HIGH'` 硬编码；caseId 正则仅一处。

**责任角色 + 时间框**：测试/QA 工程师（配合 Rust 后端开发者抽 seam）；1~2 个工作日。

#### G10 — 文档严重漂移（T7-02、T7-03、T7-04、T7-05）

**问题描述**：
- **T7-02**（`docs/migration-guide.md` §1.1/§3.4/§4.1/§4.3/§5.4.6）：引用已迁移/删除 API（`src-tauri/` 三目录 +「13 个 Tauri Commands」；`Config::load_from_file()`/`Config::save()`/`to_string_pretty()` 已迁到 `ConfigRepository`；`GroupSettings` 标记 `HashMap` 实际 `IndexMap`）。
- **T7-03**（`asd-tauri/TESTING.md` L6/L8/L133-146）：反复要求 `--features test-manifest`（已无 `[features]`）；fuzz 3 实际 5；Rust 测试数 506 与 test-map 609 冲突。
- **T7-04**（`asd-tauri/docs/test-map.md`）：汇总表与明细不一致（差 63；asd-ipc-protocol 明细 71 vs 汇总 72；asd-test-harness 明细 0 vs 汇总 4；逐文件计数过时）。
- **T7-05**（`AGENTS.md` vs `test-map.md` vs `TESTING.md`）：测试统计口径跨文档冲突（592 vs 609 / 244 vs 467 / 581 无法对账）；AGENTS 头部时间戳矛盾。

**根本原因**：多文档独立修订、统计日期与计数口径未统一、无单一权威来源；I/O 崩溃修复与 crate 抽取后未回填。

**具体修复步骤（4 个原子提交）**：
1. **提交 1（T7-02）**：I/O 引用改 `ConfigRepository`；§3.4 IpcCommand 表补 13 变体；「13 commands」改 34；`HashMap` 改 `IndexMap`；三目录对齐 5-member workspace。
2. **提交 2（T7-03）**：删除所有 `--features test-manifest` 命令与提示；fuzz 3 改 5 并补全命令；Rust 测试数与 test-map 对齐单一口径。
3. **提交 3（T7-04）**：按文档自带统计命令重新全量统计，逐行更新明细表，使「小计 = 明细之和 = 汇总」一致。
4. **提交 4（T7-05）**：确立 `test-map.md` 为唯一测试统计来源；统一标注 `#[test]` 属性数 / `Test_` 方法数 / 断言数三口径；更新 AGENTS.md 头部 `Updated` 时间戳。

**测试验证方案（文本核验）**：`grep test-manifest` 无残留；`grep "592\|609\|244\|467"` 仅单一权威值；`test-map.md` 明细小计 == 汇总 == 总计；`migration-guide.md` 无 `HashMap`/`Config::load`/`Config::save`/「13 commands」残留。

**回滚机制**：纯文档提交，`git revert` 完全回退。

**效果标准**：migration-guide 与 5-member workspace + `ConfigRepository` + 13 变体 + `IndexMap` + 34 commands 一致；TESTING.md 无 test-manifest、fuzz=5；test-map.md 三点口径自洽；AGENTS.md 统计与 test-map 单一口径一致。

**责任角色 + 时间框**：文档/技术写作者（配合各主题开发者核对事实）；1~2 个工作日（建议放代码批次收口后，避免又漂移）。

---

### 3.3 Phase 2 — 次要优化（P2 / Minor：46 项，12 个批次）

> **时间框**：长期（择机，随迭代收口），不阻塞当前运行与发布
> **提交粒度**：每批次独立一个 commit（`refactor/chore/docs/test(<scope>): <中文描述>`）
> **回滚机制（各批通用）**：`git revert <该批 commit>`；已改动 Cargo.toml 需同时回退 Cargo.lock
> **依赖关系**：B9（T6-09）与 P1 G2（T3-05+T6-03）同文件相交，建议 P1 日志限速落地后再做；B12（T8-04）与 CR1 工作区文件之一同名，须先确认 CR1 处置意图

#### B1 — 冗余依赖与死代码清理（T4-01、T4-02、T4-03、T5-07）

**问题**：`asd-domain/Cargo.toml:11` tracing 依赖零使用；`asd-application/scheduler.rs:6-13` 已 `#[deprecated]` `SkillManager` 死代码 + AGENTS.md 描述失真；`asd-ipc-protocol/Cargo.toml:10` + `hotkey_merger.rs:33` 仅为 1 处 `debug!` 引入 tracing；`watchdog.rs:55,100-101,108-116` `on_state_change` 死代码 + 持锁重入隐患。

**修复步骤**：① `grep` 确认 `scheduler.rs` 无调用后删除 + 更新 `lib.rs` 的 `mod scheduler`；② 两个 Cargo.toml 删 `tracing`；③ `hotkey_merger.rs:33` 的 `debug!` 改为返回丢弃计数或删除；④ `watchdog.rs` 删 `on_state_change` 字段及 setter（若需回调，先 clone、释放锁后再调用）；⑤ AGENTS.md 依赖表移除 tracing 登记、Key Files 删除/改写 scheduler.rs 描述。

**测试**：`cargo check --workspace; cargo build --workspace; cargo test -p asd-domain; cargo test -p asd-ipc-protocol; cargo test -p asd-application`。
**回滚**：按全局约定回滚 5 个文件；`git revert` 后 `cargo fetch` 恢复 Cargo.lock。
**效果**：`cargo tree -p asd-domain -p asd-ipc-protocol` 无 tracing；`grep deprecated` 无命中；watchdog `on_state_change` 零引用。
**角色/时间**：Rust 侧（crates）+ 文档负责人；P2 长期。

#### B2 — 错误类型与封装统一（T4-06、T4-07、T4-08）

**问题**：`config_repository.rs:16` `atomic_write` 为自由函数，`recording_service.rs:2` 跨层引用；`config_repository.rs:105,119,126,148` 错误返回 `ConfigLoadError` vs `String` 并存；`error.rs:42-44,58-61` `AppError::message()` 对 Io 返回空串。

**修复步骤**：① `atomic_write` 改为 `ConfigRepository` 方法，`recording_service` 改调 `repo.atomic_write`；② 统一错误返回为类型化（以 `ConfigLoadError` 为基准，短期不能全量统一则加注释说明）；③ `AppError::message()` 改返回 `Cow<'_, str>`，删手动空串特判；④ `cargo clippy` 清理调用方适配。

**测试**：`cargo test -p asd-application` + `cargo clippy -p asd-application -- -D warnings`。
**回滚**：统一 commit，`git revert` 一次性回退。
**效果**：`atomic_write` 仅以方法形式出现；各错误返回路径类型一致（或有注释）；`message()` 对 Io 非空。
**角色/时间**：Rust 侧（asd-application）；P2 长期，建议与 B1 同迭代合并（同 crate）。

#### B3 — 校验权衡与默认值语义（T4-05、T4-09）

**问题**：`validator.rs:152-158` 无效热键键名仅 warning 不 error（权衡未记录）；`config.rs:63` `default_config()` version 仍为 `"3.0"`。

**修复步骤**：① `validator.rs:152-158` 补注释说明权衡并在 AGENTS.md 登记；② `config.rs:63` version 改 `"4.0"`（或与 `workspace.package.version` 同源），`grep '"3.0"'` 排查其余默认值/兼容硬编码，同步评估 `config_compat_tests`。

**测试**：`cargo test -p asd-domain` + `config_compat_tests`。
**回滚**：`git revert` 本批 commit。
**效果**：默认版本号不出现 `3.0`；权衡有注释 + 文档可追溯。
**角色/时间**：Rust 侧（asd-domain）+ 文档负责人；P2 长期，低风险。

#### B4 — 未登记妥协与规则豁免（T2-05、T4-10、T5-05）

**问题**：`joy_sender.ahk:17` 反向 include 未在妥协表登记；`state.rs:882,900,901`/`tests/*.rs` 直接 `std::fs` 与规则有张力；`lib.rs:117-138,140-174` 心跳/接受循环/关机直接操作 IpcManager 未登记。

**修复步骤（纯文档/注释）**：① AGENTS.md 妥协 #1 补记 `joy_sender → domain/interfaces.ahk`；② 补测试豁免「`#[cfg(test)]`、`tests/` 允许直接 `std::fs` 构造固件」；③ `lib.rs` 补 M31 同款例外注释（或下沉为 IpcManager 方法，纳入 B5 评估）；④ 交叉核对三项在妥协章节可读。

**测试**：`cargo check --workspace` + AHK 语法检查确认未破坏；`grep` 三处登记点。
**回滚**：`git revert`（仅文档/注释）。
**效果**：三处妥协/豁免可 `grep` 命中；Phase 3 文档一致性清单无「未登记妥协」遗留。
**角色/时间**：架构评审确认边界 + 文档负责人；P2 长期。

#### B5 — 并发/阻塞/基础设施健壮性（T5-03、T5-04、T5-08、T5-09、T5-10、T5-12）

**问题**：`bridge.rs:47,76,196,206,216` `Handle::current().block_on` 脱离 tokio 运行时 panic；`watchdog.rs:781,214,594-597` async 循环内持锁同步 taskkill + `Command::spawn`；`ipc.rs:76-85,180` auth token 时间戳派生 + 非恒定时间比较；`lib.rs:117-138,663` 无单实例保护；`watchdog.rs:417-461` 持锁横跨多 await；`lib.rs:31`/`ipc_client.ahk:20` 管道名跨语言无一致性保障。

**修复步骤（改动面较大，拆多个小 commit，归一批验收）**：
1. T5-03：`Handle::current().block_on` 改 `tauri::async_runtime::block_on` 或补注释明确「必须在 Tauri async runtime 上下文内」。
2. T5-04：持锁 taskkill + `Command::spawn` 包进 `tokio::task::spawn_blocking`（或 `tokio::process::Command`）。
3. T5-08：token 生成改随机字节（`uuid`/`getrandom`）；比较改恒定时间（或明确注释保留折中）。
4. T5-09：引入 `tauri-plugin-single-instance`。
5. T5-10：`wait_for_exit` 轮询拆到锁外执行，锁内仅切换状态。
6. T5-12：管道名收敛到 `infrastructure/ipc.rs` 单一导出 + 集成/正则自检守护（Rust 常量 vs AHK 字符串一致）。
7. `cargo clippy` + `cargo fmt` 收尾。

**测试**：`cargo test -p asd-tauri --lib`（ipc_tests、watchdog 集成）+ `cargo test --workspace`；手动验证二次启动仅聚焦首实例、非运行时上下文无 panic。
**回滚**：多 commit，逐条 `git revert`（T5-09 可独立回滚）。
**效果**：`cargo clippy --workspace` 无警告；`grep "block_on" src/bridge.rs` 无裸 `Handle::current()`；管道名仅一处权威并自检守护。
**角色/时间**：Rust 侧（src-tauri 主）+ AHK 执行器侧（仅 T5-12）；P2 长期，可「T5-04/T5-10/T5-12 → T5-08 → T5-03/T5-09」分步消化。

#### B6 — AHK 代码一致性（T2-06、T2-08、T2-09、T2-10）

**问题**：`config_store.ahk:82-98` vs `:36-65` 写入路径拷贝策略不一致；`skill_manager.ahk:453-458,470-473` `_resetEmergencyTimer` 未声明靠 `HasProp` 守卫；`skill_manager.ahk:318-379` `_StartGroupExecution` 嵌套闭包 + `Bind` 递归约 60 行/5 层；`group_editor.ahk`(81 方法)/`webview2_manager.ahk`(60 方法)/`skill_group.ahk`(约 920 行) 超大类。

**修复步骤**：① T2-06 `Set()` 与 `Save()` 对齐改 `deepclone`；② T2-08 静态属性区补 `static _resetEmergencyTimer := 0`，删 `HasProp` 守卫；③ T2-09 提取 `_ExecuteTick(gId, execId)` 私有方法，用显式 `SetTimer` 回调取代自绑定递归，摊平到 2 层以内；④ T2-10 渐进式首刀拆分（group_editor 拆「热键编辑」、webview2_manager 拆「Bridge 消息路由」、skill_group 拆「模式执行器」），保持对外静态方法签名不变。

**测试**：逐文件 `/ErrorStdOut` 语法检查 + `tests\run_all_tests.ahk` 全套（重点 test_application/test_presentation/test_domain/test_infrastructure）。
**回滚**：按文件分批 commit（T2-06/T2-08 一组、T2-09 一组、T2-10 首刀一组）。
**效果**：两条写入路径拷贝策略一致；`_resetEmergencyTimer` 静态声明完整；`_StartGroupExecution` 圈复杂度 ≤ 3 层嵌套；God Object 首刀拆分完成且全套 AHK 测试通过。
**角色/时间**：AHK 侧（domain/presentation）；P2 长期，T2-06/T2-08 低风险先做。

#### B7 — Rust 代码一致性（T5-06、T5-11、T5-13、T5-14）

**问题**：`watchdog.rs:518` `JOBOBJECTINFOCLASS(9)` 魔法数字；`lib.rs:408,757` 生产代码 `Arc::get_mut().expect` + 入口 `expect`；`watchdog.rs:1056` 测试属性缩进格式不齐；`watchdog.rs:361-382,390-403` `begin_restart`/`reset_to_restart` 只 `kill()` 未 `wait()`。

**修复步骤**：① T5-06 改具名常量（查 windows crate）或加注释说明 `9` 语义；② T5-11 按 M33 将 `config_path` 注入移入 `AppState::new(...)` 构造参数（短期降级 `if let` + 返回 `AppError`）；③ T5-13 `cargo fmt` 全仓格式化并纳入 CI 门禁；④ T5-14 抽取 `kill_and_reap` 三处统一复用。

**测试**：`cargo fmt --all -- --check`（0 差异）+ `cargo test -p asd-tauri --lib`（watchdog + `kill_and_reap` 单测）。
**回滚**：`git revert`（`cargo fmt` 建议先格式化再提交，注意提交边界）。
**效果**：无魔法数字；`grep "Arc::get_mut" src/lib.rs` 无命中；`cargo fmt --check` 通过；终止路径统一 `kill_and_reap`。
**角色/时间**：Rust 侧（src-tauri）；P2 长期，T5-06/T5-13/T5-14 低风险随手修，T5-11 与 M33 一起排期。

#### B8 — AHK 健壮性补丁（T3-07、T3-09）

**问题**：`ipc_channel.ahk:181-184` `_OnReceived` 回调无 catch，异常中断分发；`key_recorder.ahk:273-302,312-323` `_mouseHotkeys` 标志注册完成后才置位，中途异常钩子残留。

**修复步骤**：① T3-07 为 `callback(msgObj)` 补 `catch` 记 WARNING；② T3-09 `_RemoveMouseHooks` 无条件遍历注销一轮（或每注册成功一个钩子即维护状态，使部分注册可回滚）。

**测试**：`tests\run_all_tests.ahk`（重点 test_key_recorder、test_infrastructure）；注入抛异常 callback 确认分发不中断。
**回滚**：`git revert`（两处独立）。
**效果**：单条消息异常不中断整体；钩子卸载在「部分注册」下无残留。
**角色/时间**：AHK 侧（infrastructure/domain）；P2 长期，风险低可尽早并入。

#### B9 — 性能微调（T3-08 + T6-12、T6-08、T6-09、T6-10、T6-11）

**问题**：`webview2_manager.ahk:1040-1081,408,438-439`/`config_store.ahk:30-48,70`/`group_service.ahk:140` 导入解析两次 + 保存路径多层冗余 deepclone；`ipc_channel.ahk` 预留文件管道每次 Send/Emit 做 FileGetSize + 整条 Stringify + FileAppend；`json_serializer.ahk:17-21,49-88`/`error_system.ahk:199` 日志默认 `indent=2` 多行 pretty JSON；`utils.ahk:41-55` `_GetField` 重复 `JSONParser.Parse`；`mode_registry.ahk:317,334,415,434` 冗余 `HasProp("_nextStepTime")` 检查。

**修复步骤**：① T3-08+T6-12 复用同一次 `JSONParser.Parse` 结果，保存路径逐层评估去掉冗余 deepclone（保留一层防御）；② T6-08 顶部标注该管道接口为「预留/低优先级」（或改内存队列 + 定时刷新）；③ T6-09 日志写入路径改紧凑序列化（`indent:=0`），**依赖 P1 G2 先行**；④ T6-10 `_GetField` 按对象指针缓存解析结果（注意与 T2-03 环边界一致）；⑤ T6-11 直接访问 `group._nextStepTime`。

**测试**：`tests\run_all_tests.ahk` 全套 + 「导入解析次数 = 1」断言。
**回滚**：按子项分批 commit，逐条 `git revert`（T6-09 注意与 P1 交叉的归属）。
**效果**：`_BridgeImportConfig` 解析 1 次；保存路径 deepclone 层级减少；日志单行紧凑 JSON；`_nextStepTime` 直接访问无 `HasProp`。
**角色/时间**：AHK 侧（presentation/infrastructure/domain）；P2 长期，T6-08/T6-11 低风险先做，T6-09 待 P1 后做。

#### B10 — AGENTS.md 模块清单与结构补全（T2-07 + T7-07、T7-06、T7-08、T7-09、T7-11）

**问题**：AHK 模块清单不完整（infrastructure 缺 config_io/joy_sender/migration_logger，domain 缺 joystick_executor/joystick_input/key_recorder/key_validator，application 缺 backup_service）；`AGENTS.md` L1220-1227 IpcMessage 示例仅 4 字段（实际 9）；L72 妥协第 3 条放错章节且与 L142 重叠；L251 tests 计数与列举不吻合；L37-47/L109-111 Rust 目录表未登记新增模块。

**修复步骤（纯文档）**：按实际目录补全三层模块清单与 Key Files/Subdirectories 表；IpcMessage 9 字段示例（或注「完整定义见 message.rs」）；L72 第 3 条移入 Rust 妥协表或标注；L251 改「16 个 test_*.ahk + 6 个框架/配置文件 = 22」；L37-47/L109-111 补入新增模块。

**测试**：`grep`/`Get-ChildItem` 对比清单完整性；Phase 3 文档口径收敛清单复核。
**回滚**：`git revert`（仅 AGENTS.md 单文件）。
**效果**：模块清单与目录实际 1:1；IpcMessage 示例字段数与 message.rs 一致（或标注简化）；妥协表无错章；tests 计数与列举吻合。
**角色/时间**：文档负责人 + 架构评审；P2 长期。

#### B11 — 文档标识/表述一致性（T7-10、T7-12、T7-13、T7-14）

**问题**：应用标识三处不一致（com.asd.skillmanager / com.asd.tauri / asd-tauri）；历史报告（08-03）论断已失效未加勘误；test-map E2E helpers 未登记 ahk_path.js/error_utils.js/`__tests__/`；「modes（7）」与「支持 10 种模式」矛盾。

**修复步骤**：① T7-10 以 `tauri.conf.json` L5 的 `identifier`（`com.asd.tauri`）为准统一；② T7-12 历史报告加勘误标注（不重写历史）；③ T7-13 补登记 E2E helpers；④ T7-14 统一为「7 种（E2E 覆盖）；系统共 10 种，joystick_* 未纳入 E2E」，并分别标注「系统能力 vs E2E 覆盖」两口径。

**测试**：`Select-String` 全库检索标识统一；Phase 3 文档收敛清单复核。
**回滚**：`git revert`。
**效果**：标识 `com.asd.tauri` 三处一致；历史报告带勘误；E2E helpers 完整；执行模式两口径无冲突。
**角色/时间**：文档负责人；P2 长期。

#### B12 — 测试规范与口径收口（T8-04、T8-05、T8-06、T8-07†）

**问题**：`tests/run_all_tests.ahk` 缺 `OnError` 回调，单 suite 崩溃弹窗中断批量运行；`#[ignore]` 实测 19+ 与文档 16/15 三处不一致 + `MAIN_CONFIG_JSON` 未登记固件；fixtures 缺 joystick 3 模式样本 + `test_joystick.ahk:463` 硬编码字符串；T8-07† 正文未展开占位。

**修复步骤**：① T8-04 顶部补 `#ErrorStdOut` + `#Warn` + `OnError`（**前置**：先确认 CR1 处置意图）；② T8-05 用 `analyze-tests.ps1`（或 `grep -c "#\[ignore\]"`）统计回写 AGENTS.md/test-map.md；补登记 `MAIN_CONFIG_JSON`；③ T8-06 补 `joystick_config.json` fixture（或增补 sample_config），`test_joystick.ahk:463` 从 fixture 派生模式名；④ T8-07† **执行前回查 `task-8-tests.md` 定位第 4 条 Minor**，重复则并入回填编号，新问题则纳入本批处置（不得无说明丢失）。

**测试**：`tests\run_all_tests.ahk` 全套确认不弹窗；`cargo test -p asd-tauri`（含 config_compat_tests）；`grep "#\[ignore\]"` 计数与文档一致。
**回滚**：`git revert`（T8-04 与 CR1 工作区文件重叠，建议 CR1 定稿后再提交）。
**效果**：`run_all_tests.ahk` 含完整错误接管指令；三处 `#[ignore]` 口径一致；fixtures 覆盖 joystick 三模式；`T8-07†` 已定位处置（不留占位）。
**角色/时间**：测试负责人 + 文档负责人；P2 长期，建议与 Phase 3 口径收敛同期完成。

---

### 3.4 Phase 3 — 回归验证（收尾）

> **准入条件**：Phase 0/1/2 均已提交并解冲突后进入全量回归。执行顺序：V-01 语法 → V-02 AHK 全套 → V-03/V-04 Rust 编译与测试 → V-05~V-07 Miri → V-08 clippy → V-09 fmt → V-10~V-13 E2E → V-14 汇总跑 → V-15 覆盖率。语法/编译类失败优先于逻辑测试处理。

#### 3.4.1 全量回归测试矩阵

> 常量：`$ahk = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"`；`$root = "d:\1demo\AutoHotkeydemo"`；`$tauri = "$root\asd-tauri"`。

| ID | 验证项 | 通过标准 | 不通过处置 |
|----|--------|---------|-----------|
| V-01 | AHK v2 全量语法检查（排除 `\lib\`） | 所有 .ahk 退出码非 2 | 定位失败文件 → 回退对应批次（多为 B6/B8/T8-04）重改 |
| V-02 | AHK v2 测试全套（`tests\run_all_tests.ahk`） | 0 失败；无弹窗中断（T8-04 生效） | 按失败 suite 回溯 → 对应批次重改 |
| V-03 | Rust 全仓编译（`cargo build --workspace`） | 退出码 0 | 回退 B1/B2/B5/B7 |
| V-04 | Rust 全仓测试（`cargo test --workspace`） | 全部通过（ignored 除外） | 映射对应批次（B1/B2/B3/B5/B7/B12） |
| V-05 | Miri（asd-domain） | 0 UB、全通过 | 回退 B3 及 P1 校验改动 |
| V-06 | Miri（asd-ipc-protocol） | 0 UB、全通过 | 回退 B1/B7 |
| V-07 | Miri（asd-application，跳过 I/O 用例） | 0 UB、通过 | 回退 B2 |
| V-08 | Clippy（`--workspace --all-targets -- -D warnings`） | 0 warning | 修 warning → 回退对应批次 |
| V-09 | 格式化门禁（`cargo fmt --all -- --check`） | 0 diff（含 T5-13） | `cargo fmt --all` 后重新进入对应批次 |
| V-10 | E2E 前置：release 构建 | 退出码 0 | 回退 Phase 1/2 编译相关 |
| V-11 | E2E 前置：tauri-driver（`cargo install tauri-driver --locked`） | 安装成功 | 记录环境缺失，重试 |
| V-12 | E2E 依赖安装（`e2e; npm install`） | 退出码 0 | 网络/依赖错误记录，不计代码回归 |
| V-13 | E2E 全套（9 suite/53 用例） | 9 suite 全绿；binary 缺失 skip 不算 fail | `appendKnownIssue` 记录，优先回退 B5/B12 |
| V-14 | 汇总测试 + JUnit + 覆盖率 + 分析（`scripts\run-tests.ps1 -JUnit -Coverage -Analyze`） | 测试通过 + 报告生成 | 查看 `test-results/` 与 test-map.md 口径收敛 |
| V-15 | 覆盖率（`cargo llvm-cov --workspace`） | 纯逻辑 crate 覆盖率维持 ~96.57%（不显著回退） | 定位新增未覆盖分支 → 补测或回退 |

**每类验证通过与不通过处置总原则**：任何「不通过」回到对应修复批次的 checklist 重新处理，修复后从该类别重跑（不跳过后续）；不得以「文档标注已知问题」代替代码回归修复。

#### 3.4.2 文档同步与统计口径收敛（确立单一权威来源）

**单一权威来源**：`asd-tauri/docs/test-map.md` 为测试统计唯一权威；`AGENTS.md` 为架构/执行模式/依赖唯一权威；其余文档（TESTING.md、developer-guide.md、migration-guide.md）「引用权威来源，不自行复制数字」。

| 口径项 | 现状冲突 | 收敛目标 | 权威来源 | 关联修复 |
|--------|---------|---------|---------|---------|
| Rust 测试总数 | AGENTS「592」 vs test-map「609」 vs TESTING「506」 | 以 `#[test]` 实录为准，AGENTS/TESTING 指回 test-map | test-map.md | T7-03、T7-05、B12(T8-05) |
| AHK 执行器口径 | AGENTS「244 个 Test_ 方法」 vs test-map/TESTING「467 测试」 | 分别标注 `Test_` 方法数与用例/断言数两口径 | test-map.md | T7-05 |
| test-map 明细 vs 汇总 | 明细 153 vs 汇总 217 差 63；asd-ipc-protocol 明细 71 vs 汇总 72 | 重跑统计 → 小计 = 明细之和 = 汇总 | test-map.md | T7-04 |
| AGENTS.md 依赖表 | asd-domain/asd-ipc-protocol 登记 tracing | 依赖表与 Cargo.toml 1:1 | AGENTS.md + Cargo.toml | T4-01、T4-03、B1 |
| 执行模式表 | 「modes（7）」 vs 「支持 10 种模式」 | 明确「系统能力（10） vs E2E 覆盖（7）」 | AGENTS.md + test-map.md | T7-14、B11 |
| AGENTS 头部时间戳 | Updated 2026-05-30 vs 正文「截至 2026-08-04」 | 统一为本次 Fix Plan 落地日期（2026-08-20 之后） | AGENTS.md 头部 | T7-05 |

**收敛后验收命令**：`grep -rn "592\|609\|506" .../TESTING.md .../AGENTS.md` 无冲突裸数字；`grep -c "#\[test\]"`（按 crate 逐文件）与 test-map 明细逐一比对一致。

#### 3.4.3 历史修复核对表复核（清零项）

| 编号 | 目标状态 | 复核手段 | 判定 |
|------|---------|---------|------|
| C6（部分修复） | 完全修复 | `Select-String test_error_captor.ahk "OnError"` 有命中；全 root 测试文件含 OnError | 0 个测试文件缺 OnError |
| I1（引入回归） | 回归消除 | CR1 处置恢复 `main.ahk` 的 `#Include "application\backup_service.ahk"` 后 `grep -n "backup_service" main.ahk` 命中；运行期 `BackupService` 可解析（V-02 无 `Unknown class`） | 运行时无未定义类 |
| I6（引入回归） | 回归消除 | CR1 后 `backup_core.ahk:70` 改调 `ConfigIO.ExportToFile`、`main.ahk` 恢复 include、`config_service.ahk:412-417` 清理包装；`Test_BackupCore_NotCallExportConfigToFile` 通过 | 反向依赖回归 + 分层测试失败清零 |

> 复核结论须在回归报告末尾写一行：「历史修复核对表三项（C6 / I1 / I6）均已闭环清零，无『引入回归』项遗留。」

#### 3.4.4 Phase 1~3 完成后统一收口

- 汇总运行（V-14）+ 覆盖率（V-15）；产出物核对：`asd-tauri/test-results/`（JUnit XML）、`asd-tauri/coverage/`（HTML）、`lcov.info` 非空；`analyze-tests.ps1` 输出通过率/失败清单/耗时 Top10/按 crate 统计。
- 收尾结论：将「历史修复核对表清零结论」「测试统计口径收敛结论」写入回归笔记，回填 `AGENTS.md` 头部 `Updated` 时间戳与正文统计数。

---

## 4. 实施时间表

> 阶段划分与问题分级对应：**Phase 0 → P0（Critical 3）**；**Phase 1 → P1（Important 23 / 10 组）**；**Phase 2 → P2（Minor 46 / 12 批）**；**Phase 3 → 全量回归验证收尾**。

| 阶段 | 时间框 | 责任角色（具体人名待填） | 处置范围 | 里程碑交付物 |
|------|--------|------------------------|---------|-------------|
| **Phase 0（紧急）** | 立即（下一次运行/发布前） | 开发者（主）、审查者（diff 复核） | CR1 / CR2 / CR3（3 项 Critical） | ① 工作区 4 个未提交文件意图确认并建立干净基线（tag）；② 主程序可运行（CR1 崩溃消除，`layering_security_suites` 通过）；③ 热路径逐键 IPC 上报收敛（CR2）；④ `developer-guide.md` 对齐 5-member workspace 或标注「已过时」（CR3） |
| **Phase 1（重要）** | 短期（紧随 Phase 0） | 开发者（主）、审查者、测试 | 23 项 Important（G1~G10） | G1 校验补全；G2 日志限速；G3 定时器生命周期；G4 IPC 阻塞背压；G5 unsafe 收敛（Miri 0 UB）；G6 vJoy 复用；G7 隐式依赖与永真断言；G8 输入误报与注入检查；G9 测试补强；G10 文档统一 |
| **Phase 2（次要）** | 长期（择机，随迭代收口） | 开发者、测试 | 46 项 Minor（B1~B12） | 冗余依赖/死代码清理（B1）；错误类型与封装统一（B2）；校验权衡与默认值语义（B3）；未登记妥协/豁免（B4）；并发/阻塞/健壮性（B5）；AHK/Rust 代码一致性（B6/B7）；AHK 健壮性补丁（B8）；性能微调（B9）；AGENTS.md 清单补全（B10）；文档标识一致（B11）；测试规范收口（B12） |
| **Phase 3（回归验证）** | 收尾（全部改动合并后） | 测试（主）、开发者、审查者 | 全量回归 + 效果评估 | 全量测试 100% 通过；`cargo clippy` 无 warning；`cargo fmt --check` 干净；覆盖率不下降；历史修复核对表无「引入回归」项；输出最终验收报告 |

> 每阶段内部按「组/批」为单位逐项提交，保持「一个组 = 一次原子提交」的可回退粒度；跨阶段不混签（Phase 0 的 Critical 必须先于 Phase 1 落地）。

---

## 5. 资源需求

> 状态标注：✅ 已具备 · ⚠️ 需确认/新增。人力为相对估算，具体人时以团队排期为准。

### 5.1 人力投入（按阶段）

| 阶段 | 开发者 | 审查者 | 测试 | 说明 |
|------|:------:|:------:|:----:|------|
| Phase 0 | 1（AHK + Rust） | 1（diff 复核） | — | 处置 3 项 Critical，需确认工作区意图 |
| Phase 1 | 1~2（AHK / Rust 并行） | 1 | 1 | 23 项 Important 跨两侧，可按 G 组拆并行 |
| Phase 2 | 1 | —（低强度） | 1 | 46 项 Minor 随迭代分批消化 |
| Phase 3 | 1（配合修复回归） | 1 | 1（主） | 以测试验证与修复回归为主 |

### 5.2 工具链 / 环境

| 资源 | 用途 | 涉及阶段 | 状态 |
|------|------|:-------:|------|
| AHK v2 运行时（`D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`） | 语法检查 / `run_all_tests.ahk` / 执行器测试 | Phase 0~3 | ✅ 已具备 |
| Rust 工具链（stable） | 编译 + `cargo test --workspace` | Phase 1~3 | ✅ 已具备 |
| Rust nightly + **Miri** | T5-01 unsafe 0 UB 验证（纯逻辑 crate） | Phase 1（G5） | ⚠️ 需确认 nightly 已安装 |
| **cargo-llvm-cov** | 覆盖率基线 / 效果评估 | Phase 3 | ⚠️ 需确认已安装 |
| clippy / rustfmt | clippy 无 warning / fmt 干净 | Phase 2、3 | ✅ 已具备 |
| **tauri-driver**（`cargo install tauri-driver --locked`） | E2E 测试驱动 | Phase 3 | ⚠️ 需新增（不在 npm registry） |
| Node + npm（`asd-tauri/e2e/`） | E2E 测试（WebDriverIO 8 + Mocha） | Phase 3 | ⚠️ 需确认依赖已安装 |
| Windows 测试机（联网/桌面会话） | GUI / WebView2 / 全局热键 / vJoy 实测 | Phase 0~3 | ✅ 已具备 |
| vJoy 驱动 | joystick 复用改动实测（G6） | Phase 1（G6） | ⚠️ 需确认已安装 |

---

## 6. 风险评估与应对

| 风险 | 影响 | 概率 | 应对措施 |
|------|:----:|:----:|---------|
| **CR1 半回退状态处置误判（覆盖用户未提交改动）** | 高 | 中 | 处置前逐一确认工作区 4 个文件（`main.ahk`、`backup_core.ahk`、`migration_logger.ahk`、`tests/run_all_tests.ahk`）为「有意回退」还是「暂存」，完成或撤销全部改动后再动手；先 commit/stash 建立干净基线；严禁 `reset --hard`、`checkout .`、`clean -f`；每步小提交，`git revert` 单项回退 |
| **unsafe soundness 改动（T5-01）的回归 / UB 风险** | 高 | 中 | 最小改动策略：优先 `state()` 改返回 Clone 类型或拆出 `Option<Child>`；改动后跑 `cargo +nightly miri test`（纯逻辑 crate）与 watchdog 单测；审查者专项 review 所有 unsafe 改动并核对 Mutex 不变量注释 |
| **热路径限速改动（T3-05/T6-03）对执行流畅度的感知影响** | 中 | 中 | 限速器与 `DebugLogger` 同构，保留 `suppressedCount` 输出；同步修正 50ms 与「每秒一次」口径；改后跑 `run_all_tests` + 高频异常冒烟 |
| **文档重写（CR3、T7-02~05）的断链 / 口径冲突风险** | 中 | 中 | 确立 test-map.md 为唯一统计来源；重写后逐一 grep 核对；历史报告加勘误；文档改动不碰源码 |
| **配置校验收紧（T3-01/02/03、T4-04）导致既有合法配置被拒绝** | 中 | 低 | 只补「格式/非空/冲突」检查，复用 `_IsValidKeyName` 名单；Rust 侧仅对控制热键空值 `add_error`；用 `tests/fixtures/sample_config.json` 做回归基准；新增非法样本用例而非收紧合法集 |

---

## 7. 测试验证方案（整体）

> 覆盖 AHK v2、Rust workspace、Miri、E2E 四层，引用 AGENTS.md「测试前置检查流程」与「错误与警告接管机制」。

### 7.1 AHK v2（Phase 0~3）

- **前置检查（每个改动的 .ahk 文件）**：
  1. 语法检查（stderr 重定向 + 退出码 0）：`Start-Process ... AutoHotkey64.exe /ErrorStdOut <file> -RedirectStandardError`，退出码 2 = 语法错误。
  2. 接管指令验证：确认含 `#ErrorStdOut` / `#Warn VarUnset` / `#Warn Unreachable` / `OnError`。
  3. 运行时错误验证：`OnError` 回调接管，退出码仍为 0。
- **全量测试**：`& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
- **CR1 专项**：恢复 include 后运行 `tests/suites/layering_security_suites.ahk`，`Test_BackupCore_NotCallExportConfigToFile` 断言通过。

### 7.2 Rust workspace（Phase 1~3）

```bash
cd asd-tauri && cargo test --workspace          # 全量测试
cd asd-tauri/src-tauri && cargo check           # 语法检查
cd asd-tauri && cargo clippy --workspace --all-targets   # 无 warning
cd asd-tauri && cargo fmt --check               # 格式干净
```

### 7.3 Miri（Phase 1，G5 unsafe 验证，0 UB）

```bash
cd asd-tauri && cargo +nightly miri test -p asd-domain
cd asd-tauri && cargo +nightly miri test -p asd-ipc-protocol
cd asd-tauri && cargo +nightly miri test -p asd-application -- --skip config_repository --skip save_config --skip load_from
```

### 7.4 覆盖率与 E2E（Phase 3）

```bash
# 覆盖率（评估「覆盖率不下降」）
cd asd-tauri && cargo llvm-cov --workspace --html --output-dir coverage/

# E2E（需先 cargo build --release + 安装 tauri-driver）
cd asd-tauri/e2e && npm install && npm test
```

> 测试报告落点：`asd-tauri/e2e/docs/e2e-test-report.md`；失败用例须调用 `appendKnownIssue` 记录到 `asd-tauri/e2e/docs/e2e-known-issues.md`。

### 7.5 详细回归矩阵

详见 §3.4.1「全量回归测试矩阵」（V-01 ~ V-15）与 §3.4.2「文档同步与统计口径收敛」。

---

## 8. 回滚机制（整体）

> 目标：任何一项修复都可独立回退，且**绝不触碰用户已有未提交改动**。

1. **建立干净基线（Phase 0 前，强制）**：工作区 4 个未提交文件（`main.ahk`、`backup_core.ahk`、`migration_logger.ahk`、`tests/run_all_tests.ahk`）先经团队确认意图，**先 commit 或 stash**，形成干净工作区；在 Phase 0 首项改动前**打 tag**（如 `v4.0-review-fix-baseline`）或记录基线 commit hash，作为回退锚点。
2. **逐项/逐批独立提交**：以清单的「G 组 / B 批」为原子提交单位，提交信息遵循 Conventional Commits，正文标注对应问题编号（如 `CR1`、`G5/T5-01`），确保「提交 ↔ 问题」一一对应可追溯。
3. **单项回退**：需撤回时用 `git revert <commit>`（保留历史、可再正向重提），**禁止** `git reset --hard` 回退历史。
4. **严禁回滚用户已有未提交改动**：任何涉及「撤销/回退工作区」的操作前，先 `git status` / `git diff` 核对是否存在用户未提交内容；若存在，先与用户确认是否提交或 stash，**绝不**用 `checkout .` / `restore .` / `clean -f` 清空。
5. **边界约束**：回滚仅作用于本次修复计划的提交，不跨过基线 tag；若需回退到基线，用 `git checkout <baseline-tag> -- <file>` 逐文件恢复而非整体重置。

---

## 9. 修复后效果评估标准

### 9.1 可量化指标（全局收口）

| 指标 | 目标值 |
|------|:------:|
| Critical 项 | **3 项清零** |
| Important 项 | **23 项清零** |
| 全量测试通过率（AHK 581 + Rust 592 + 执行器 244 + E2E 53） | **100%** |
| `cargo clippy` | **无 warning** |
| `cargo fmt --check` | **干净（无 diff）** |
| 文档漂移项（T7-* / T2-07 等） | **清零** |
| 历史修复核对表「引入回归」项 | **0 项（I1/I6 已通过 CR1 处置恢复为「已修复」）** |
| 代码覆盖率（相对 Phase 0 前基线） | **不下降** |

### 9.2 每条 Critical 独立验收判据

| 编号 | 验收判据 |
|------|---------|
| **CR1** | `main.ahk` 恢复 `#Include "infrastructure\config_io.ahk"` 与 `#Include "application\backup_service.ahk"` 及 OnExit `JoyHotkeyManager.Shutdown()`；`backup_core.ahk:70` 改调 `ConfigIO.ExportToFile` 消除反向依赖；`config_service.ahk:412-417` 清理无调用方的全局包装；`layering_security_suites.ahk` 全绿；主程序启动后可完成一次配置读写/备份导出（无 `Unknown class` 崩溃） |
| **CR2** | 默认关闭逐键 `key_send_event` IPC 上报（仅 `_recordState="recording"` 或 `_validationGroupId != ""` 时发送），或改批量缓冲 + 定时刷新；管道写非阻塞/失败降级（不阻塞 AHK 消息循环）；高频按键场景冒烟无前端卡顿引发的执行冻结 |
| **CR3** | `developer-guide.md` §1 按 5-member workspace 结构重写（`asd-domain` / `asd-ipc-protocol` / `asd-application` / `asd-test-harness` / `src-tauri`）；IpcCommand 表补齐 13 变体；附录 E 命令数对齐 34 个 Tauri Command；或文档顶部明确标注「已过时，以 AGENTS.md 为准」并归档 |

---

## 附录 A：阶段与分组映射总览表

| 阶段 | 优先级 | 计数 | 分组/批次 | 成员编号 |
|------|--------|:----:|-----------|---------|
| **Phase 0** | P0 / Critical | 3 | —（单项处置） | CR1（T2-01+T2-02）、CR2（T6-01）、CR3（T7-01） |
| **Phase 1** | P1 / Important | 23 | G1~G10（10 组，见 §2.6） | T2-03、T2-04、T3-01、T3-02、T3-03、T3-04、T3-05+T6-03、T3-06、T4-04、T5-01、T5-02、T6-02、T6-04、T6-05、T6-06、T6-07、T7-02、T7-03、T7-04、T7-05、T8-01、T8-02、T8-03 |
| **Phase 2** | P2 / Minor | 46 | B1~B12（12 批，见 §2.7） | T2-05、T2-06、T2-07+T7-07、T2-08、T2-09、T2-10、T3-07、T3-08+T6-12、T3-09、T4-01、T4-02、T4-03、T4-05、T4-06、T4-07、T4-08、T4-09、T4-10、T5-03、T5-04、T5-05、T5-06、T5-07、T5-08、T5-09、T5-10、T5-11、T5-12、T5-13、T5-14、T6-08、T6-09、T6-10、T6-11、T7-06、T7-08、T7-09、T7-10、T7-11、T7-12、T7-13、T7-14、T8-04、T8-05、T8-06、T8-07† |
| **Phase 3** | 收尾（回归验证） | — | 全量回归 + 效果评估 | 无新增问题编号；验收判据见 §9 |

> **校验**：Critical 3 ✓（CR1/CR2/CR3）；Important 23 ✓（G1~G10 十组，§2.6 校验式 `4+1+2+2+1+1+3+2+3+4=23`）；Minor 46 ✓（B1~B12 十二批，§2.7 校验式 `4+3+2+3+6+4+4+2+5+5+4+4=46`）；去重合并 4 组（T2-01+T2-02→CR1、T3-05+T6-03、T3-08+T6-12、T2-07+T7-07）+ `T8-07†` 占位（正文未展开，编号待定）。
>
> 本表为整份计划的收口索引：阶段 → 优先级 → 计数 → 分组/批次 → 成员编号，与 §2「问题清单与优先级分级」、§3「分阶段实施计划」完全对齐，供快速定位任一问题编号所处的阶段与批次。