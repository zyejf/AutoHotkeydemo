# Tasks

> 执行依据：`docs/remediation-plan-2026-08-20.md`（file:line / 原子提交粒度 / 验证 / 回滚 / 效果标准均以该计划为准）。每条 Task 界定的文件与步骤见计划对应小节。

## Phase 0 — 紧急修复（Critical，先于一切）

- [x] Task 0：CR1 工作区处置预案（唯一硬性前置，计划 §3.1.0）
  - [ ] 快照 4 个未提交文件到 `docs/review/2026-08-20/fix-plan/workspace-snapshot/`，并保存 `git diff > snapshot.patch`
  - [ ] 逐文件确认未提交改动归属（main.ahk / backup_core.ahk / migration_logger.ahk / run_all_tests.ahk），区分「半回退拆坏」与「用户有意改动」
  - [ ] 明确 `_SortBackupsByTime` 回退、`migration_logger` include 清理、12 个 suite 注册删除的最终归属结论
  - [ ] 记录处置结论（备份路径、归属判定、待恢复清单）

- [x] Task 1：CR1 半回退状态修复（T2-01+T2-02，计划 §3.1.1）
  - [ ] Step 1：恢复 `main.ahk` 两条 include + 两处 OnExit（1 commit）
  - [ ] Step 2：修复 `backup_core.ahk:70` 反向依赖 + 恢复 `#Include "config_io.ahk"`（1 commit，不动 `_SortBackupsByTime`）
  - [ ] Step 3：`config_service.ahk` 三处直调 `ConfigIO` + 删除全局包装（1 commit）
  - [ ] 验证：语法检查 / 接管指令 / 启动无 `Unknown class` / `layering_security_suites` 全绿 / `InStr(...,"ExportConfigToFile")==0` / 工作区干净 / OnExit 完整

- [x] Task 2：CR2 执行器逐键 IPC 上报优化（T6-01，计划 §3.1.2）
  - [ ] Step 1：引入 `Sender._reportKeyEvents` 开关，`_SendKeyDown`/`_SendKeyUp` 条件上报
  - [ ] Step 2：`CommandDispatcher` 四分支（start/stop recording/validation）联动开关
  - [ ] Step 3：`ipc_client.ahk` `_SendMsg` 写失败降级跳过 + 限速 DEBUG
  - [ ] 验证：三文件语法检查 + `test_sender`/`test_ipc_client`/`test_executor` 全绿 + 新增状态联动用例

- [x] Task 3：CR3 developer-guide 文档重写（T7-01，计划 §3.1.3）
  - [ ] Step 1：重写为 5-member workspace 结构，`models.rs` 描述改 13 变体
  - [ ] Step 2：IpcCommand 表补全 13 变体
  - [ ] Step 3：附录 E 改 34 个 Tauri Command，api.js 计数与实际一致
  - [ ] 验证：`Select-String` 无「9 变体 / 13 个 Tauri Command / domain,application,infrastructure 三子模块」残留

## Phase 1 — 重要修复（Important，23 项 / 10 组）

- [x] Task 4：G1 校验覆盖缺口（T3-01/T3-02/T3-03/T4-04，计划 §3.2 G1）
  - [ ] T3-01 `ValidateGroupOnly` 补热键格式校验
  - [ ] T3-02 `_ValidateModeFields` 按键名合法性下沉共享工具
  - [ ] T3-03 `_ValidateHotkeys` 补格式校验
  - [ ] T4-04 Rust `validate_config` 控制热键空值 + 交叉冲突检测
  - [ ] 验证：AHK `run_all_tests.ahk` + `cargo test -p asd-domain` 全绿

- [x] Task 5：G2 热路径日志无限速（T3-05+T6-03，计划 §3.2 G2）
  - [x] `ErrorSystem`/`JSONLogger` 同构限速器（`_rateLastTime`+`_rateSuppressed` 分桶，`_ResolveSource` 分桶键）
  - [x] `DebugLogger` 阈值对齐共享常量 `LOG_RATE_LIMIT_MS := 1000`（`utils.ahk:17`，三处 logger 共享）
  - [x] 验证：新增 `LogRateLimitTests`（4 用例：常量对齐/ErrorSystem 同源抑制/JSONLogger 同源抑制/suppressedCount 落盘），AHK 全量 607/607 通过

- [x] Task 6：G3 定时器生命周期（T6-02/T6-04，计划 §3.2 G3）
  - [x] T6-04 `StartXxx` 幂等保护（先取消旧定时器再覆盖）
  - [x] T6-02 up 定时器纳管进 Map，去除逐键现造闭包
  - [x] 验证：`test_sender`/`test_joystick`/`test_domain` 新增「重复 start 仅 1 活跃引用、停止无滞后 up」用例（AHK 全量 603/603 通过）

- [x] Task 7：G4 IPC 背压与阻塞（T6-05/T6-06，计划 §3.2 G4）
  - [x] T6-05 `send()` 写超时（`tokio::time::timeout`，`SEND_TIMEOUT` 2000ms，超时清理 send_half + notify_pipe_broken + 返回 `SendTimeout`）
  - [x] T6-06 `listen_ahk` 无 ack 免 clone + 非关键消息 `try_send` 背压（`hotkey`/`pong` 保留 `.await`）
  - [x] 验证：`cargo test --lib` 203 通过；新增 `test_send_timeout_configured_to_2000ms` + `test_send_returns_connection_closed_when_disconnected`

- [x] Task 8：G5 unsafe soundness（T5-01，计划 §3.2 G5）
  - [x] 提交 1：`state()` 返回 `WatchdogStateEnum` 快照（值克隆，与锁生命周期解耦）
  - [x] 提交 2：跨线程移动回归测试 `test_watchdog_cross_thread_move_and_mutex_access`（编译期 + 运行期验证 `unsafe impl Send/Sync`）
  - [x] 提交 3：4 处 `unsafe impl Send/Sync` 保留并强化 SAFETY 注释（watchdog.rs:60-79/509-518），登记为待收敛项
  - [x] 验证：`cargo test --lib` 全绿 + 新增跨线程用例通过

- [x] Task 9：G6 vJoy 设备复用（T6-07，计划 §3.2 G6）
  - [x] 设备生命周期提升到组级（含 emergency_release 链）
  - [x] `_GetAxisInfo`/`_IsAxis` 静态缓存
  - [x] 验证：`test_joystick.ahk` 组存活期 Acquire/Relinquish 计数稳定（`Test_VJoyRefCountStableDuringGroupLifetime` 通过）

- [x] Task 10：G7 隐式依赖与永真断言（T2-03/T2-04/T5-02，计划 §3.2 G7）
  - [x] T2-03 打破 `utils ↔ json_parser ↔ json_logger` include 环（`utils.ahk` 已无 `#Include "json_parser.ahk"`，`_GetField` 仅保留 Map/Object 属性访问，调用方 webview2_manager 均传入已解析对象）
  - [x] T2-04 `config_store.ahk:15` 已显式 `#Include "json_logger.ahk"`（同时 `#Include deepclone.ahk`）
  - [x] T5-02 删除 `EXPECTED_TAURI_COMMAND_COUNT` 永真断言（grep 全仓 0 命中）
  - [x] 验证：6 文件语法检查 exit=0（utils/config_store/json_logger/json_parser/joystick_executor/gui_manager）+ AHK 全量 607/607 通过

- [x] Task 11：G8 输入误报与注入检查（T3-04/T3-06，计划 §3.2 G8）
  - [x] T3-04 `GlobalSettingsEditor._Save`（gui_manager.ahk:421-458）逐字段 try-catch `Integer()` 校验 + 检查 `SaveConfig()` 返回值，失败弹「保存失败」不弹「已保存」
  - [x] T3-06 joystick 注入检查移出热路径：`Execute` 三实现（Periodic/Sequence/Hold）入口处 `_EnsureSenderReady()`+`_WarnSenderMissingOnce()`，`_SendJoyKey` 降为防御性静默跳过
  - [x] 验证：语法检查 exit=0 + AHK 全量 607/607 通过

- [x] Task 12：G9 测试覆盖补强（T8-01/T8-02/T8-03，计划 §3.2 G9）
  - [x] T8-01 `ipc.rs` 抽 `parse_message` + `classify_message`(MessageKind) + `forward_to_outbound` 纯函数/私有方法，接回 `recv()`/`listen_ahk`（等价重构），新增 8 单测覆盖三分支+三类边界
  - [x] T8-02 `lib.rs` 抽 `run_shutdown_sequence`（注入式三步异步序列），`perform_graceful_shutdown` 委托之，新增 3 项序列测试（顺序/guard 早退/二次调用拦截）
  - [x] T8-03 E2E 新增 `helpers/spec-hooks.js`（`registerStandardLifecycle`/`resolveBinaryPath`/`extractCaseId`/`reportAfterEach`/`DEFAULT_FAILURE_SEVERITY`），重构 8 spec（+154/-691 行，净删 537 行），`'HIGH'` 硬编码与 caseId 正则收敛单一位置
  - [x] 验证：`cargo test --lib` 214 passed/0 failed/16 ignored + `cargo build --workspace` exit 0；9 spec + spec-hooks.js `node --check` exit 0

- [x] Task 13：G10 文档严重漂移（T7-02/T7-03/T7-04/T7-05，计划 §3.2 G10）
  - [x] T7-02 migration-guide 对齐 5-member workspace/`ConfigRepository`/13 IpcCommand 变体/`IndexMap`/34 commands（6 处）
  - [x] T7-03 TESTING.md 删 test-manifest、fuzz 3→5 并补全命令、测试数改为引用 test-map
  - [x] T7-04 test-map.md 明细/汇总自洽（Rust 624：132+72+186+3+231）
  - [x] T7-05 口径收敛至 test-map（测试权威）/AGENTS（架构权威），AGENTS 头部时间戳→2026-08-20
  - [x] 验证：`test-manifest` 0 残留、迁移 API 0 残留（仅 1 处真实 HashMap 合法保留）、fuzz=5、冲突裸数字 0

## Phase 2 — 次要优化（Minor，46 项 / 12 批）

- [ ] Task 14：B1 冗余依赖与死代码清理（T4-01/T4-02/T4-03/T5-07）
- [ ] Task 15：B2 错误类型与封装统一（T4-06/T4-07/T4-08）
- [ ] Task 16：B3 校验权衡与默认值语义（T4-05/T4-09）
- [ ] Task 17：B4 未登记妥协与规则豁免（T2-05/T4-10/T5-05）
- [ ] Task 18：B5 并发/阻塞/基础设施健壮性（T5-03/T5-04/T5-08/T5-09/T5-10/T5-12）
- [ ] Task 19：B6 AHK 代码一致性（T2-06/T2-08/T2-09/T2-10）
- [ ] Task 20：B7 Rust 代码一致性（T5-06/T5-11/T5-13/T5-14）
- [ ] Task 21：B8 AHK 健壮性补丁（T3-07/T3-09）
- [ ] Task 22：B9 性能微调（T3-08+T6-12/T6-08/T6-09/T6-10/T6-11，待 G2 后）
- [ ] Task 23：B10 AGENTS.md 模块清单与结构补全（T2-07+T7-07/T7-06/T7-08/T7-09/T7-11）
- [ ] Task 24：B11 文档标识/表述一致性（T7-10/T7-12/T7-13/T7-14）
- [ ] Task 25：B12 测试规范与口径收口（T8-04/T8-05/T8-06/T8-07†，待 CR1 处置确认后）

## Phase 3 — 回归验证与收口

- [ ] Task 26：全量回归验证（计划 §3.4.1，V-01~V-15 顺序执行，全部通过）
- [ ] Task 27：统计口径收敛 + 历史修复核对表复核（计划 §3.4.2/§3.4.3）
- [ ] Task 28：产出修复报告 `docs/remediation-execution-report-2026-08-20.md`

# Task Dependencies

- [Task 1] ~ [Task 25] 全部依赖 [Task 0]（工作区处置预案）
- [Task 2] [Task 3] 依赖 [Task 1]（CR1 处置完成；不得与 CR1 源码改动混入同一提交）
- Phase 1 建议执行顺序：G3/G6/G8 → G4/G5 → G1/G7/G2 → G9 → G10（G10 最后收口）
- Phase 2 跨批依赖：[Task 22]（B9）依赖 [Task 5]（G2）；[Task 25]（B12）依赖 [Task 0]/[Task 1]（CR1）
- [Task 26] ~ [Task 28] 依赖 Phase 0/1/2 全部完成