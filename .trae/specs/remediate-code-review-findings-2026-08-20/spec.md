# 代码审查问题修复执行 Spec

## Why

`docs/remediation-plan-2026-08-20.md`（下称「修复计划」）已把 `docs/code-review-report-2026-08-20.md` 的 72 条去重发现（Critical 3 / Important 23 / Minor 46）转化为可执行的修复路线图，并划分 Phase 0~3。但计划本身只是「诊断 + 处方」，尚未落到源码。当前工作区处于一次「不完整的 I6 重构 + 未提交回退」造成的**半回退不一致状态**——直接运行主程序会因 `ConfigIO`/`BackupService` 未接入生产入口 `#Include` 而在运行时抛 `Unknown class` 崩溃。本任务按计划落地全部修复，使项目回归可运行、可验证的健康状态。

## What Changes

- **Phase 0（紧急，先于一切）**：处置工作区 4 个未提交文件（先备份、确认归属，禁止 `git checkout`/`restore`/`reset --hard` 覆盖）+ 修复 CR1/CR2/CR3。
- **Phase 1（重要）**：修复 23 项 Important（G1~G10 十个主题批次）。
- **Phase 2（次要）**：修复 46 项 Minor（B1~B12 十二个批次）。
- **Phase 3（收尾）**：全量回归验证（V-01~V-15）+ 测试统计口径收敛 + 历史修复核对表清零 + 产出修复报告。

**破坏性变更（BREAKING）**：无对公开产品行为的破坏性改动。CR2/G2/G4/G6 对执行器/日志/IPC/vJoy 的优化会改变内部运行路径，但功能语义保持不变（详见计划各节的风险评估）。修复计划全文（file:line、原子提交粒度、验证/回滚/效果标准）是本 spec 的**权威执行依据**，本 spec 不重复其 93KB 细节，仅做归一化与可验证性约束。

## Impact

- Affected specs: `remediation-plan-2026-08-20`（其产出物作为本次执行的输入；不修改该计划本身）。
- Affected code: 覆盖 AHK v2（`main.ahk`、`infrastructure/`、`application/`、`domain/`、`presentation/`、根目录 `tests/`）、AHK 执行器（`src-tauri/ahk_executor/`）、Rust workspace（`asd-domain`/`asd-ipc-protocol`/`asd-application`/`src-tauri`，含 `Cargo.toml`）、E2E（`asd-tauri/e2e/`）、文档（`AGENTS.md`、`docs/developer-guide.md`、`docs/migration-guide.md`、`asd-tauri/TESTING.md`、`asd-tauri/docs/test-map.md`）。
- 产出物: 修复后的源码 + 提交记录 + `docs/remediation-execution-report-2026-08-20.md` 修复报告。

## ADDED Requirements

### Requirement: 工作区处置与不可覆盖约束

执行过程 SHALL 严格遵循计划 §3.1.0 的「工作区 4 个未提交文件处置预案」，并以之为唯一硬性前置。

#### Scenario: 处置前保护用户未提交改动

- **WHEN** 开始任何代码修改
- **THEN** 先将 `main.ahk` / `infrastructure/backup_core.ahk` / `infrastructure/migration_logger.ahk` / `tests/run_all_tests.ahk` 四个文件的当前工作区版本快照到 `docs/review/2026-08-20/fix-plan/workspace-snapshot/`（含 `git diff > snapshot.patch`）
- **AND** 逐文件确认每处未提交改动归属（「半回退拆坏」vs「用户有意回退/清理」），仅定向恢复「确定为半回退拆坏」的部分
- **AND** 严禁 `git checkout <file>` / `git restore <file>` / `git reset --hard` 直接覆盖或回滚未提交改动

#### Scenario: 原子提交与可回滚

- **WHEN** 修复通过验证
- **THEN** 每项/每步骤以独立原子提交（`fix/perf/refactor/docs/test/chore(<scope>): <中文描述>`，遵循 Conventional Commits）
- **AND** 任一提交可单独 `git revert` 回退，且不损坏其它修复

### Requirement: Phase 0 Critical 修复

执行 SHALL 完成 CR1/CR2/CR3，且 CR1 处置必须先于 CR2/CR3。

#### Scenario: CR1 半回退状态修复

- **WHEN** 处置 CR1（T2-01+T2-02）
- **THEN** 恢复 `main.ahk` 的 `#Include "infrastructure\config_io.ahk"` 与 `#Include "application\backup_service.ahk"`，恢复两处 OnExit 为 `(JoyHotkeyManager.Shutdown(), SkillManager.OnExit())`
- **AND** `backup_core.ahk:70` 改回 `ConfigIO.ExportToFile(BackupCore.currentConfigPath, config)`，并恢复其 `#Include "config_io.ahk"`（不动 `_SortBackupsByTime` 未提交回退）
- **AND** `config_service.ahk` 三处调用点（:36/:106/:376）改直调 `ConfigIO`，删除 :407-418 的 `ImportConfigFromFile`/`ExportConfigToFile` 全局包装
- **AND** 达到 §3.1.1 效果评估标准：语法检查 0 / 启动无 `Unknown class` / `layering_security_suites` 通过 / `InStr(backup_core, "ExportConfigToFile") == 0` / 工作区 4 文件均有明确处置结果 / OnExit 完整

#### Scenario: CR2 逐键 IPC 上报优化

- **WHEN** 处置 CR2（T6-01）
- **THEN** 引入 `Sender._reportKeyEvents` 开关，`_SendKeyDown`/`_SendKeyUp` 仅在该开关为 true 时发送 `key_send_event`（`SendInput` 始终执行）
- **AND** `CommandDispatcher` 的 start/stop recording/validation 四分支与开关联动；sender 不反向引用 CommandDispatcher
- **AND** `ipc_client.ahk` `_SendMsg` 写失败降级跳过并限速 DEBUG（非断连）
- **AND** 非录制/验证模式下逐键 `key_send_event` 上报为 0，录制/验证模式行为不变

#### Scenario: CR3 developer-guide 文档重写

- **WHEN** 处置 CR3（T7-01）
- **THEN** 重写 `docs/developer-guide.md` 为 5-member workspace 结构，IpcCommand 表补 13 变体，附录 E 改 34 个 Tauri Command，api.js 计数与 `asd-tauri/src/api.js` 实际一致
- **AND** 无「9 变体」「13 个 Tauri Command」「src-tauri/src/{domain,application,infrastructure}」残留表述

### Requirement: Phase 1 Important 主题修复

执行 SHALL 完成 G1~G10 十个主题批次（23 项），每批以原子提交落地并通过对应测验证。

#### Scenario: 主题批次修复与验收

- **WHEN** 修复 G1（校验覆盖）、G2（日志限速）、G3（定时器生命周期）、G4（IPC 背压）、G5（unsafe soundness）、G6（vJoy 复用）、G7（隐式依赖/永真断言）、G8（输入误报/注入检查）、G9（测试补强）、G10（文档漂移）
- **THEN** 每批满足计划 §3.2 对应小节的具体步骤、测试验证、效果标准（如 G1 四类非法输入被拦截、G2 同源落盘 ≤1 次/秒、G3 重复 start 不双倍发键、G4 挂死时 `send()` 超时返回、G5 `state()` 不再返回跨锁引用、G6 单次按键不触发 Acquire/Relinquish、G7 去环且无永真断言、G8 保存失败如实反馈 + joystick 启动期拦截、G9 增 IPC/关机白盒与 E2E 基建、G10 文档口径收敛）

### Requirement: Phase 2 Minor 批量修复

执行 SHALL 完成 B1~B12 十二个批次（46 项），遵循计划 §3.3 的批量方案与回滚/效果标准，并遵守跨批依赖（B9 待 P1 G2 后、B12 待 CR1 处置确认后）。

### Requirement: Phase 3 回归验证与收口

执行 SHALL 在 Phase 0/1/2 完成并解冲突后，按计划 §3.4 顺序跑全量回归，并完成统计口径收敛与修复报告。

#### Scenario: 全量回归通过

- **WHEN** 进入 Phase 3
- **THEN** 按 V-01~V-15 顺序执行（AHK 语法 → AHK 全套 → Rust 编译/测试 → Miri → clippy → fmt → E2E → 汇总 → 覆盖率），全部通过
- **AND** 文档统计口径收敛至单一权威来源（`test-map.md` 为测试统计权威、`AGENTS.md` 为架构权威），其余文档引用不复制数字
- **AND** 历史修复核对表三项（C6/I1/I6）闭环清零，无「引入回归」项

#### Scenario: 修复报告产出

- **WHEN** 全部修复完成
- **THEN** 产出 `docs/remediation-execution-report-2026-08-20.md`，含问题解决情况、实施步骤、测试结果、后续措施

## MODIFIED Requirements

无。

## REMOVED Requirements

无。