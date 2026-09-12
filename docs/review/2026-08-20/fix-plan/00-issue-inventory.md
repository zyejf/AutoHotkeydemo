# 问题清单矩阵与优先级/主题分级（Fix Plan 第一步）

> **来源**：`docs/code-review-report-2026-08-20.md`（主报告）+ `docs/review/2026-08-20/` 下 9 份分报告（phase1-baseline + task-2~task-8）
> **口径**：原始 76 条 → 去重 4 组（8 条 → 4 条）→ 最终 **72 条**（Critical 3 / Important 23 / Minor 46）
> **性质**：只读规划清单，未修改任何 .ahk / .rs / .toml / .json 源码文件

---

## 0. 去重与编号说明

| 合并组 | 组成 | 归属编号 | 级别 |
|--------|------|---------|------|
| 合并 1 | T2-01 + T2-02 | **CR1** | Critical |
| 合并 2 | T3-05 + T6-03 | **T3-05 + T6-03** | Important |
| 合并 3 | T3-08 + T6-12 | **T3-08 + T6-12** | Minor |
| 合并 4 | T2-07 + T7-07 | **T2-07 + T7-07** | Minor |

> **Task 8 未展开 Minor（T8-07† 已处置）**：Task 8 分报告「总结」自报 7 条（Important 3 + Minor 4），正文「发现清单」仅展开 T8-01~T8-06 共 6 条（Important 3 + Minor 3）。经回查 `docs/review/2026-08-20/task-8-tests.md` 源文件全文，正文确无第 4 条 Minor 条目，『Minor 4 / 总数 7』为总结栏计数笔误，实为『Minor 3 / 总数 6』。**处置结论**：本清单 `T8-07†` 予以关闭，无删减的独立 Minor 项；需在相同总结栏以勘误修正计数（同步见 `task-8-tests.md` 勘误标注）。

---

## 1. 完整问题清单矩阵（72 条）

### 1.1 P0 — Critical（3 条）

| 编号 | 位置 (file:line) | 维度 | 级别 | 一句话描述 |
|------|------------------|------|------|-----------|
| CR1（T2-01 + T2-02） | `main.ahk`(21-58 include 段缺失)；`infrastructure/config_io.ahk:21`；`application/config_service.ahk:412-417`；`infrastructure/backup_core.ahk:70`；`tests/suites/layering_security_suites.ahk:128-131` | 架构设计 | Critical | 工作区半回退状态：`ConfigIO`/`BackupService` 未接入生产入口 `#Include`，配置读写核心路径运行时 `Unknown class` 崩溃 |
| CR2（T6-01） | `ahk_executor/sender.ahk:494-522`；`ahk_executor/ipc_client.ahk:792-818,533-541` | 性能优化 | Critical | 每次按键 down/up 无条件执行 IPC 序列化 + 同步阻塞写命名管道（无 OVERLAPPED/背压） |
| CR3（T7-01） | `docs/developer-guide.md` §1.2(L51-85)、§2.3.3(L226-236)、附录E(L975-993)、§1.1(L29) | 文档完整性 | Critical | developer-guide.md 整篇基于已废弃单 crate 结构，与 5-member workspace 严重不符 |

### 1.2 P1 — Important（23 条）

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

### 1.3 P2 — Minor（46 条）

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
| T8-07† | `docs/review/2026-08-20/task-8-tests.md`（总结栏计数） | 测试覆盖 | Minor | 【已处置】报告总结栏「Minor 4 / 总数 7」与正文 6 条（Minor 3）自相矛盾；回查源文件确认应为 Minor 3 / 总数 6，系计数笔误，无独立第 4 条 Minor 项 |

---

## 2. P1 优先级映射

> **P0** = 3 项 Critical（CR1 / CR2 / CR3）
> **P1** = 23 项 Important
> **P2** = 46 项 Minor

### 2.1 P1 主题分组（10 组 / 23 项）

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

---

## 3. P2 主题批量分组（12 批 / 46 项）

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

## 4. 统计核对

| 指标 | 数值 |
|------|:----:|
| 清单条目数 | **72** |
| P0（Critical） | 3 |
| P1（Important） | 23 |
| P2（Minor） | 46 |
| P1 主题分组数 | 10 |
| P2 批次数 | 12 |

> **追溯性**：每条均保留报告原文编号（Critical 用 CR1~CR3 并标注来源 T 编号；合并项以 `+` 连接双编号；Task 8 未展开 Minor 以 `T8-07†` 占位并如实标注）。