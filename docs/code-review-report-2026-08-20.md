# 全面代码审查最终报告（2026-08-20）

> **审查对象**：按键连招管理系统（AHK v2 + Rust/Tauri 混合架构）
> **审查日期**：2026-08-20
> **审查性质**：只读审查（未修改任何 .ahk / .rs / .toml / .json 源码文件）
> **基线**：`docs/code-review-report-2026-08-03.md`（94 项发现：C1~C10、I1~I43、M1~M41）
> **子报告来源**：`docs/review/2026-08-20/` 下 8 份分报告（Phase 1 基线核对 + Task 2~8）

---

## 1. 执行摘要

### 总体评估

工程整体质量健康、架构骨架清晰、此前的多轮修复（C1~C10 / I1~I43 / M1~M41）绝大部分已正确落地且可验证；**但当前最重要、最紧迫的风险是工作区处于一次「不完整的 I6 重构 + 未提交回退」造成的半回退不一致状态——若此刻运行主程序会因 `ConfigIO`/`BackupService` 类未加载而在运行时崩溃**，必须在下一次运行/发布前优先处置。

### 关键风险概述

- **🔴 最高优先级（运行时崩溃）**：工作区存在 **4 个未提交文件**，其中 `main.ahk` 删除了 `#Include "infrastructure\config_io.ahk"` 与 `#Include "application\backup_service.ahk"` 两行（并移除 OnExit 的 `JoyHotkeyManager.Shutdown()`），而生产代码 `application/config_service.ahk:412-417` 仍委托 `ConfigIO.LoadFromFile/ExportToFile`、`presentation/*` 仍调用 `BackupService.*`。AHK 的 `#Include` 不会自动解析全局类名，因此 `ConfigIO`/`BackupService` 生产环境**从未被定义**，任何一次配置读写/备份导出都会抛 `Unknown class: ConfigIO`/`Unknown class: BackupService`（详见 §4-CR1，由 T2-01/T2-02 归并，并对应基线 I1/I6 回归）。
- **🟠 次要但真实的风险**：① 执行器热路径每次按键 down/up 无条件走 IPC 序列化 + 同步阻塞写命名管道（T6-01，Critical）；② AGENTS.md 之外的两份开发文档（developer-guide / migration-guide）严重过时，会误导开发者（T7-01，Critical）；③ 配置校验存在多处覆盖缺口（热键格式/按键名/控制热键，T3-01/02/03、T4-04）；④ 热路径日志限速承诺未兑现（T3-05/T6-03）；⑤ `watchdog.rs` 4 处手写 `unsafe impl Send/Sync`（T5-01）。

### 关键指标

| 指标 | 数值 |
|------|------|
| 原始发现总数 | 76 条（各分报告自报加和） |
| **去重后最终发现总数** | **72 条** |
| Critical | 3 条（原始 4，去重合并 1 组） |
| Important | 23 条（原始 24，去重合并 1 组） |
| Minor | 46 条（原始 48，去重合并 2 组） |
| 历史修复通过率 | 50 / 53 ≈ **94.3%**（Critical 9/10 已修复 + 1 部分修复；Important 41/43 已修复 + 2 引入回归） |

> **去重说明**：对跨任务重复的发现做合并，共 4 组合并（涉及 8 条 → 4 条）：
> 1. `T2-01 + T2-02` → 「半回退状态」同一根因（Critical）
> 2. `T3-05 + T6-03` → 热路径错误日志无限速（Important）
> 3. `T3-08 + T6-12` → 配置保存路径冗余 deepclone（Minor）
> 4. `T2-07 + T7-07` → AGENTS.md AHK 模块清单不完整（Minor）
>
> **口径提示**：Task 8 分报告「总结」自报 7 条（Important 3 + Minor 4），但其正文仅列示 6 条（T8-01~T8-06，Important 3 + Minor 3），存在 1 条 Minor 未在正文展开。本报告按分报告自报口径计入原始 76 条、去重后 72 条；正文可枚举的实际发现为 71 条（详见 §2 脚注）。

---

## 2. 统计汇总

### 2.1 按严重级别

| 严重级别 | 原始条数 | 去重后条数 | 说明 |
|---------|---------|-----------|------|
| Critical | 4 | 3 | T2-01/T2-02 归并为 1 条 |
| Important | 24 | 23 | T3-05/T6-03 归并为 1 条 |
| Minor | 48 | 46 | T3-08/T6-12、T2-07/T7-07 各归并为 1 条 |
| **合计** | **76** | **72** | |

### 2.2 按六维度分布（去重后）

| 维度 | Critical | Important | Minor | 小计 |
|------|:--------:|:---------:|:-----:|:----:|
| 架构设计 | 1 | 1 | 8 | 10 |
| 代码质量 | 0 | 2 | 14 | 16 |
| 性能优化 | 1 | 6 | 5 | 12 |
| 安全性 | 0 | 7 | 6 | 13 |
| 文档完整性 | 1 | 4 | 9 | 14 |
| 测试覆盖 | 0 | 3 | 4 | 7 |
| **合计** | **3** | **23** | **46** | **72** |

> 注：「测试覆盖」Minor 4 条含 T8-04/T8-05/T8-06 三条（正文列示）与 Task 8 自报但未展开的 1 条。

### 2.3 按模块分布（去重后，按主要模块归类）

| 模块 | Critical | Important | Minor | 小计 |
|------|:--------:|:---------:|:-----:|:----:|
| AHK v2 主程序（domain/infrastructure/application/presentation/main.ahk + 根目录 tests/） | 1 | 8 | 14 | 23 |
| AHK 执行器子进程（src-tauri/ahk_executor/） | 1 | 3 | 0 | 4 |
| asd-domain | 0 | 1 | 3 | 4 |
| asd-ipc-protocol | 0 | 0 | 1 | 1 |
| asd-application | 0 | 0 | 5 | 5 |
| src-tauri（主 crate） | 0 | 6 | 12 | 18 |
| E2E | 0 | 1 | 0 | 1 |
| 文档（AGENTS.md / docs/* / test-map / TESTING） | 1 | 4 | 10 | 15 |
| **可枚举小计** | **3** | **23** | **45** | **71** |
| Task 8 未列示 Minor | — | — | +1 | +1 |
| **合计** | **3** | **23** | **46** | **72** |

---

## 3. 历史修复核对表

> 结论直接引用 `Phase 1 — 基线核对`（phase1-baseline.md §4）。状态图例：✅ 已修复 · ⚠️ 部分修复 · ❌ 未修复 · 🔄 引入回归（工作区回退）

### 3.1 修复核对统计（以 HEAD 提交状态为准）

| 类别 | 已修复 | 部分修复 | 未修复 | 引入回归 |
|------|:------:|:-------:|:------:|:-------:|
| Critical（10 项） | 9 | 1（C6） | 0 | 0 |
| Important（43 项） | 41 | 0 | 0 | 2（I1、I6） |
| **合计（53 项）** | **50** | **1** | **0** | **2** |

- 修复通过率：**50 / 53 ≈ 94.3%**。Critical 修复扎实（9/10 完全通过），Important 绝大多数正确落地（41/43）。
- 需二次关注的 3 项见 §3.2。

### 3.2 需二次关注的三项

| 编号 | 级别 | 问题简述 | 状态 | 当前代码证据 | 二次关注要点 |
|------|------|---------|------|------------|------------|
| **C6** | Critical | ~30 个测试文件缺 OnError 回调 | ⚠️ 部分修复 | 56 个测试文件已含 `OnError`（grep 确认），但 `tests/test_error_captor.ahk:4-14` 仍缺 OnError 回调 | 唯一残留的根目录核心测试文件，需补齐 OnError |
| **I1** | Important | 表现层直接调用 BackupCore | 🔄 引入回归 | 提交已落地（`application/backup_service.ahk` + 表现层改调 `BackupService.*`），但 `main.ahk` 工作区未提交删除了 `#Include "application\backup_service.ahk"` | 运行时 `BackupService` 未定义（见 §4-CR1） |
| **I6** | Important | backup_core 反向调用应用层 ExportConfigToFile | 🔄 引入回归 | 提交已落地（`infrastructure/config_io.ahk` + `config_service.ahk:412-417` 委托 ConfigIO），但 `backup_core.ahk:70` 工作区未提交回退为 `ExportConfigToFile(...)` 且删除 config_io include | 反向依赖回归 + 分层测试失败（见 §4-CR1） |

### 3.3 其他核对结论

- **I1/I6 的「语义落地 vs 物理接线」**：`BackupService`/`ConfigIO` 类定义与表现层/应用层改调均已提交，架构分层修复确实落地；但工作区未提交变更将两者的 `#Include` 从入口移除，导致运行时回归风险。
- **I3 修复方式**：团队最终选择「AGENTS.md 妥协 #1 登记 + 删除冗余 `joystick_input_utils.ahk`」而非物理解耦，`joy_hotkey_manager.ahk:14` 的 `#Include "../domain/joystick_input.ahk"` 保留为已备案妥协。
- **I9 修复方式**：MemoryError 返回 0 为有意设计，AGENTS.md 已补「MemoryError 例外」说明。

---

## 4. Critical 发现（最高优先级）

### CR1 ｜ 工作区半回退不一致状态：`ConfigIO`/`BackupService` 未接入生产入口，配置读写核心路径运行时崩溃

- **来源编号**：T2-01 + T2-02（归并于「不完整的 I6 重构导致的半回退状态」同一根因）
- **位置**：
  - `main.ahk`（第 21-58 行 include 段缺失 `config_io.ahk` 与 `backup_service.ahk`）
  - `infrastructure/config_io.ahk:21`（`ConfigIO` 类，从未被生产入口引入）
  - `application/config_service.ahk:412-417`（`ImportConfigFromFile`/`ExportConfigToFile` 委托 `ConfigIO.LoadFromFile/ExportToFile`）
  - `infrastructure/backup_core.ahk:70`（`RestoreBackup` 调用应用层 `ExportConfigToFile(...)`，反向依赖）
  - `tests/suites/layering_security_suites.ahk:128-131`（分层断言 `InStr(..., "ExportConfigToFile") == 0`）
- **维度**：架构设计
- **描述**：I6 重构将配置读写下沉到 `infrastructure/config_io.ahk` 的 `ConfigIO` 类，`config_service.ahk:412-417` 委托 `ConfigIO`，但 `main.ahk` 的 include 段**未** `#Include "infrastructure\config_io.ahk"`；`backup_core.ahk:70` 又回退为调用应用层 `ExportConfigToFile`（反向依赖未消除）。由于单测 `layering_security_suites.ahk` 单独内置 `#Include` 拉入 `config_io.ahk`，掩盖了生产入口缺 include 的问题。
- **影响**：以下生产路径均触发 `Unknown class` 运行时崩溃——`config_service.ahk:36（加载）/106/376（保存）`、`group_service.ahk:227/236`、`gui_manager.ahk:212`、`backup_core.ahk:70`；同时 `restoreBackup` 双重失效；分层测试 `Test_BackupCore_NotCallExportConfigToFile` 断言命中而失败。
- **根因**：I6 重构只做了一半（新增 `ConfigIO` + 保留应用层全局包装），又叠加工作区对 main.ahk/backup_core.ahk 的未提交回退，形成半回退状态。对应 Phase 1 基线结论的 **I1/I6 引入回归**。
- **修复/优化方案**：
  1. 在 `main.ahk` 基础设施层 include 段（紧邻 `config_store.ahk` 之后）恢复 `#Include "infrastructure\config_io.ahk"`；在应用层 include 段恢复 `#Include "application\backup_service.ahk"`，并恢复 OnExit 的 `JoyHotkeyManager.Shutdown()`。
  2. 将 `backup_core.ahk:70` 改为 `ConfigIO.ExportToFile(BackupCore.currentConfigPath, config)`，同步移除 `config_service.ahk:412-417` 已无调用方的全局包装。
  3. **处置前务必确认**工作区 4 个未提交文件（`main.ahk`、`backup_core.ahk`、`migration_logger.ahk`、`tests/run_all_tests.ahk`）是有意回退还是暂存，完成或撤销全部相关改动，避免将半回退状态带入运行/发布。

### CR2 ｜ 执行器每次按键 down/up 无条件执行 IPC 序列化 + 同步阻塞写命名管道

- **来源编号**：T6-01
- **位置**：`asd-tauri/src-tauri/ahk_executor/sender.ahk:494-522`（`_SendKeyDown`/`_SendKeyUp`）、`ahk_executor/ipc_client.ahk:792-818`（`_SendMsg`）、`ipc_client.ahk:533-541`（`CreateFileW` 未传 `FILE_FLAG_OVERLAPPED`）
- **维度**：性能优化
- **描述**：`_SendKeyDown`/`_SendKeyUp` 每次按键动作都调用 `IpcClient._SendMsg(Map("type","key_send_event",...))` 无条件上报 Rust；`_SendMsg` 内部执行 `MiniJson.Stringify`（递归序列化）→ 两次 `StrPut` → `Buffer` 分配 → 同步 `WriteFile`（管道以无 `FILE_FLAG_OVERLAPPED` 方式打开，写为阻塞）。周期性 50ms 间隔下单键 = 每秒 20 down + 20 up = 40 次消息，每次 2 次 JSON 序列化 + 2 次 Buffer 分配 + 2 次同步管道写，且无背压上限。
- **影响**：按键热路径被 IPC 上报强耦合；前端卡顿会经「outbound 慢 → 管道满 → 同步 WriteFile 阻塞 AHK 消息循环」反向冻结执行。
- **根因**：`key_send_event` 仅用于前端展示/反馈，却与最热路径强耦合；管道写为同步阻塞、无 OVERLAPPED/背压上限。
- **修复/优化方案**：① 默认关闭逐键 IPC 上报，仅在录制（`_recordState="recording"`）或验证（`_validationGroupId != ""`）模式才发送；② 若必须上报，改为批量缓冲 + 定时刷新（每 50-100ms 汇总一批），或复用 `HotkeyMerger` 思路；③ 管道写入非阻塞/异步，`WriteFile` 失败时降级跳过上报。

### CR3 ｜ `docs/developer-guide.md` 整篇基于已废弃的单 crate 结构，与实际 5-member workspace 严重不符

- **来源编号**：T7-01
- **位置**：`docs/developer-guide.md` §1.2（L51-85）、§2.3.3（L226-236）、附录 E（L975-993）、§1.1（L29）
- **维度**：文档完整性
- **描述**：§1.2 仍把 Rust 源码描述为 `src-tauri/src/{domain,application,infrastructure}/` 三子模块（该目录已不存在，现为 5-member workspace）；`models.rs` 被描述为「IpcCommand 9 变体」（实际 13 变体，且已移到 `asd-ipc-protocol/src/command.rs`）；§2.3.3 IpcCommand 表缺 `PauseRecording/ResumeRecording/StartValidation/StopValidation`；附录 E 称「13 个 Tauri Command」（实际 34 个）；§1.1 称 api.js「13 个 invoke + 19 个 stub」。
- **影响**：开发者按此文档操作会找不到目录/文件，形成断链。
- **根因**：文档 v1.0 写于 2026-05-29，早于 crate 抽取（workspace 化）与命令扩充，此后未同步更新。
- **修复/优化方案**：重写 §1 为 5-member workspace 结构；按 `command.rs` 重写 IpcCommand 表（13 变体）；附录 E 按 `commands/` 下 5 个命令文件重列 34 个 command；修正 api.js 计数；或至少在文档顶部标注「已过时，以 AGENTS.md 为准」并归档。

---

## 5. 详细发现清单（按维度分组）

> 每条保持原始编号 + 位置 + 级别 + 描述 + 根因 + 修复方案；跨任务重复项已在合并处注明来源编号。Critical 已在 §4 展开，此处不再重复，仅占位。

### 5.1 架构设计（10 项）

#### Critical（1）

- **CR1（T2-01 + T2-02）**：见 §4-CR1。

#### Important（1）

**T2-03 ｜ 基础设施层循环 `#Include` 链（utils ↔ json_parser ↔ json_logger）**
- 位置：`infrastructure/utils.ahk:13` → `infrastructure/json_parser.ahk:15` → `infrastructure/json_logger.ahk:16` → `infrastructure/utils.ahk`
- 级别：Important
- 描述：三个基础设施模块形成三节点环。因 AHK `#Include` 同路径只含一次，运行时暂不崩溃（依赖 `main.ahk` 固定加载顺序运行），但属耦合气味，任何加载顺序调整都可能触发「未定义符号」。
- 根因：`utils._GetField` 为兼容「JSON 字符串」输入内联调用 `JSONParser.Parse`，把解析能力耦合进最底层工具函数。
- 修复方案：打破环——`_GetField` 的 JSON 解析改由调用方传入解析结果，或把 `JSONParser.Parse` 上提到日志/解析层；至少移除 `utils.ahk` 对 `json_parser.ahk` 的直接依赖。

#### Minor（8）

| 编号 | 位置 | 描述 | 根因 | 修复方案 |
|------|------|------|------|---------|
| T2-05 | `infrastructure/joy_sender.ahk:17` | `joy_sender` 反向 `#Include "../domain/interfaces.ahk"`（依赖倒置，方向正确但未登记） | 文档登记滞后 | 在 AGENTS.md 妥协 #1 补记 `joy_sender → interfaces`（允许） |
| T4-01 | `crates/asd-domain/Cargo.toml:11` | 声明 `tracing` 依赖但零使用；AGENTS.md 依赖表亦未登记为 asd-domain 登记 tracing | workspace 模板带入未消费 | 移除 `asd-domain` 的 `tracing`，保持最小依赖面 |
| T4-02 | `crates/asd-application/src/scheduler.rs:6-13` | 已 `#[deprecated]` 的 `SkillManager` 与 AppState/group_service 职责重叠的死代码；AGENTS.md Key Files 描述「Arc\<dyn IpcSender\>」与实现（普通 HashMap 结构体）严重不符 | v4.0 重构后旧类以 deprecate 过渡未移除，文档未更新 | 确认无调用后删除 scheduler.rs，同步修正 AGENTS.md 描述 |
| T4-03 | `crates/asd-ipc-protocol/Cargo.toml:10`、`src/hotkey_merger.rs:33` | 为仅 1 处 `debug!` 引入 `tracing`，且 AGENTS.md 依赖表未登记 | workspace 预置依赖顺手使用 | 移除 tracing（改为返回值/计数暴露丢弃）或补登记依赖表 |
| T4-10 | `crates/asd-application/src/state.rs:882/900/901`、`tests/*.rs` | 测试代码直接 `std::fs`，与「std::fs 仅在 ConfigRepository」字面规则存在张力（生产代码已满足） | 规则未声明测试豁免 | AGENTS.md 该条补充「测试代码允许直接使用 std::fs 构造固件」豁免说明 |
| T5-03 | `src/bridge.rs:47,76,196,206,216` | `IpcBridge`/`WatchdogBridge` 用 `Handle::current().block_on` 桥接同步 trait；脱离 tokio 运行时上下文会 panic | 同步 trait 与 async 底层适配 | 文档明确必须在 tauri async runtime 内调用，或改用 `tauri::async_runtime::block_on` |
| T5-05 | `src/lib.rs:117-138,140-174` | 心跳/接受循环/关机直接操作 `IpcManager`，未走 `IpcSender` trait（仅回调注册有 M31 例外） | 生命周期逻辑默认与命令发送不同，未登记妥协 | 补 M31 同款例外注释，或下沉为 `IpcManager` 自身方法 |
| T5-12 | `src/lib.rs:31`、`ahk_executor/ipc_client.ahk:20` | 管道名 Rust 侧已收敛为 `IPC_PIPE_NAME` 常量，但与 AHK 侧 `\\.\pipe\asd_ipc` 硬编码字符串跨语言无一致性保障 | 跨语言常量无法共享，靠约定 | 常量移入 `infrastructure/ipc.rs`；新增集成/正则自检守护跨语言一致 |

### 5.2 代码质量（16 项）

#### Important（2）

**T2-04 ｜ `config_store.ahk` 使用 `JSONLogger` 但未显式 `#Include`（隐式依赖）**
- 位置：`infrastructure/config_store.ahk:95`（`JSONLogger.Log`）、`:14`（仅 include `deepclone.ahk`）
- 级别：Important
- 描述：`Set()` 调用 `JSONLogger.Log`，但未引入 `json_logger.ahk`；当前依赖 `main.ahk` 先加载 json_logger 再加载 config_store 掩盖问题，独立加载（如测试）会抛 `Unknown class: JSONLogger`。
- 根因：与 T2-01 同类——模块声明依赖不全，依赖外部加载顺序。
- 修复方案：`config_store.ahk` 顶部补 `#Include "json_logger.ahk"`（视需要补 `json_parser.ahk` 以获得 `JSONErrorType`）。

**T5-02 ｜ `EXPECTED_TAURI_COMMAND_COUNT` 编译时断言是永真式，不构成真正的数量守护**
- 位置：`src/lib.rs:606-615`
- 级别：Important
- 描述：`assert!(EXPECTED_TAURI_COMMAND_COUNT == 34)` 中右侧 `34` 是独立字面量，与 `generate_handler![...]` 列表无绑定，新增第 35 个命令而忘记更新时两个 34 仍相等，编译照常通过，给维护者虚假安全感。
- 根因：`generate_handler!` 编译期不暴露 item 数量，作者用「常量自比」伪造追踪点观感。
- 修复方案：删除误导性断言，或改为 `#[cfg(test)]` 中真实统计已注册命令数比对，或改写注释为「仅文档参考，无编译期强制」。

#### Minor（14）

| 编号 | 位置 | 描述 | 根因 | 修复方案 |
|------|------|------|------|---------|
| T2-06 | `infrastructure/config_store.ahk:82-98` vs `:36-65` | `Set()` 直接引用赋值，`Save()` 用 `deepclone`，两条写入路径防御拷贝策略不一致 | 写入路径未统一 | `Set()` 的 GroupSettings/HoldSettings 分支与 `Save()` 对齐用 deepclone |
| T2-08 | `domain/skill_manager.ahk:453-458,470-473` | `_resetEmergencyTimer` 未在类静态属性区声明，靠 `HasProp` 守卫 | 后补功能未同步声明区 | 补 `static _resetEmergencyTimer := 0`，移除 HasProp 守卫 |
| T2-09 | `domain/skill_manager.ahk:318-379` | `_StartGroupExecution` 嵌套闭包 + `Bind` 递归，约 60 行、5 层嵌套，圈复杂度高 | AHK 无原生 async，闭包+SetTimer 模拟递归 | 提取 `_ExecuteTick(gId, execId)` 独立私有方法，显式 SetTimer 回调取代自绑定 |
| T2-10 | `presentation/group_editor.ahk`（81 方法）、`presentation/webview2_manager.ahk`（60 方法）、`domain/skill_group.ahk`（约 920 行） | 超大类 God Object 倾向 | 功能叠加未模块化拆分 | 按职责拆分（按键选择器/热键编辑/Bridge 消息路由/模式执行器） |
| T4-05 | `crates/asd-domain/src/validator.rs:152-158` | 无效热键键名仅 warning 不 error（warning 不阻断保存），权衡未在文档记录 | 为避免误报降级为 warning | 补注释或在 AGENTS.md 记录「热键格式仅 warning 级建议，不阻断保存」 |
| T4-06 | `crates/asd-application/src/config_repository.rs:16`、`recording_service.rs:2` | `atomic_write` 为自由函数而非 `ConfigRepository` 方法，`recording_service` 直接跨层引用，封装口径不一致 | 自由函数为内部复用，未纳入统一 API 面 | 改 `ConfigRepository::atomic_write`，recording_service 统一走 ConfigRepository |
| T4-07 | `crates/asd-application/src/config_repository.rs:105/119/126/148` | `load_from_file_checked` 返回 `ConfigLoadError`，其余方法返回 `String`，错误类型不统一 | `load_from_file_checked` 是后补，与既有 String 风格并存 | 统一为类型化错误，短期注释说明分工与迁移方向 |
| T4-08 | `crates/asd-application/src/error.rs:42-44,58-61` | `AppError::message()` 对 Io 返回空串，序列化靠手动分支特判，三处逻辑需同步维护 | `message()` 返回 `&str` 的折中 | 改返回 `Cow<'_, str>`，删除 Serialize 中 Io 特判 |
| T4-09 | `crates/asd-domain/src/config.rs:63` | `Config::default_config()` 的 `version` 仍为 `"3.0"`，与 v4.0 不符 | 默认配置建立于 v3.0 未升级 | 改为 `"4.0"`（或与 workspace.package.version 同源），检查依赖该默认值的兼容测试 |
| T5-06 | `src/infrastructure/watchdog.rs:518` | `JOBOBJECTINFOCLASS(9)` 魔法数字 | 未查 windows crate 具名常量 | 改用具名常量或加注释说明 `9` 语义 |
| T5-07 | `src/infrastructure/watchdog.rs:55,100-101,108-116` | `on_state_change` 回调字段为死代码；`set_state` 持锁同步触发回调存在重入死锁隐患 | 状态同步改为轮询后旧 API 未删除 | 删除回调字段/setter；若保留则改「先 clone 释放锁再调用」 |
| T5-11 | `src/lib.rs:408,757` | 生产代码 `Arc::get_mut().expect` 与入口 `expect`（M33 已登记技术债） | 构造后 setter 注入 config_path 技术债 | 按 M33 方案将 config_path 移入 `AppState::new`，或降级为 `if let`+error |
| T5-13 | `src/infrastructure/watchdog.rs:1056` | `#[test]` 属性缩进 8 空格、其下 fn 4 空格，格式不齐 | 编辑后未统一格式化 | 运行 `cargo fmt` 并纳入 CI 格式门禁 |
| T5-14 | `src/infrastructure/watchdog.rs:361-382,390-403` | `begin_restart`/`reset_to_restart` 终止子进程后只 `kill()` 未 `wait()`，与 `kill_child`（kill+wait）风格不一致 | 遗漏 wait() | 统一封装 `kill_and_reap` 辅助方法，三处复用 |

### 5.3 性能优化（12 项）

#### Critical（1）

- **CR2（T6-01）**：见 §4-CR2。

#### Important（6）

**T3-05 + T6-03 ｜ 热路径错误/日志写盘无限速（违反 AGENTS.md 强制规范）** ［合并 T3-05、T6-03］
- 位置：`infrastructure/error_system.ahk:185-213`（`_WriteLog`）、`infrastructure/json_logger.ahk:179-227`（`_WriteLog`/`_LogToFile`）、`infrastructure/debug_logger.ahk:22,52-56`、各执行器 catch（`domain/mode_registry.ahk:294/343/394/444/463/481/541 等`、`domain/skill_group.ahk:756-758`）
- 级别：Important
- 描述：AGENTS.md 承诺「Execute* 热路径日志每秒最多一次」，但 `ErrorSystem.LogError`→`_WriteLog` 与 `JSONLogger._WriteLog` 均无限速，每次同步 `JSONSerializer.Stringify` + `FileAppend` 落盘；唯一有限速的 `DebugLogger` 仅对 DEBUG 级别、间隔 50ms 而非「每秒一次」。持续抛异常时以 10-50ms 周期反复 2 次序列化 + 2 次同步写盘。
- 根因：错误路径缺少令牌桶/滑动窗口限速；文档承诺仅在 DebugLogger 部分实现。
- 修复方案：给 `ErrorSystem`/`JSONLogger` 加与 `DebugLogger` 同构的限速器（`_lastWriteTime` + `_suppressedCount`），同一源限速窗口内只落盘一次并批量计数；同步将 DebugLogger 50ms 与「每秒一次」口径对齐或修正文档。

**T6-02 ｜ 每次按键按下创建新闭包 + 一次性 SetTimer（多文件）**
- 位置：`domain/skill_group.ahk:800-805`；`ahk_executor/sender.ahk:347,394,444,464`；`ahk_executor/joystick.ahk:203,253`；`domain/joystick_executor.ahk:55,107`
- 级别：Important
- 描述：每次「按下」都用 `SetTimer(((ck) => () => ..._SendKeyUp(ck))(capturedKey), -kpd)` 现造闭包 + 注册一次性定时器；领域层 `_SendKey` 还额外构造 `releaseTimer` 闭包（捕获 4 变量）+ 冗余 `HasProp` 检查。executor 侧这些「up」定时器未纳入任何 Map 跟踪，分组停止时不会取消（停止瞬间可能滞后发送一次 up）。
- 根因：逐键建闭包 + 逐键注册定时器，未复用可释放通道。
- 修复方案：复用 `skill_group` 的 `_releaseTimers` 思路把 up 定时器登记进 Map；executor 层更优是维护「已按下键集合 + 单一周期释放扫描定时器」，将 O(按键数) 建闭包/定时器降为 O(1) 周期扫描。

**T6-04 ｜ 重复激活已激活分组时覆盖定时器引用、未先取消旧定时器**
- 位置：`ahk_executor/sender.ahk:178-194（StartPeriodic）、197-215（StartSequence）、290-305（StartHybrid）、joystick.ahk:68-85`；触发入口 `executor.ahk:102-107`
- 级别：Important
- 描述：各 `StartXxx` 直接 `_timers[groupId] := timerFn; SetTimer(...)` 覆盖旧引用而不先 `SetTimer(旧引用,0)`；重连恢复或前端重复触发 `toggle_group(active=true)` 时会注册新周期定时器、旧定时器仍在运行，形成重复定时器 → 双倍发键，且旧引用丢失无法停止。
- 根因：启动路径缺「已存在则先取消再覆盖」的幂等保护。
- 修复方案：每个 `StartXxx` 开头加 `if _timers.Has(groupId) { SetTimer(旧引用,0); Delete }`，或在 `_HandleToggleGroup` 层判断「已激活且配置相同」直接返回；Joystick 侧同样处理。

**T6-05 ｜ bridge.rs `block_in_place + block_on`；`send()` 无超时，AHK 挂起可无限阻塞工作线程**
- 位置：`src/bridge.rs:44-67（send_command）、69-129（send_and_wait）`；`src/infrastructure/ipc.rs:290-327（send）`
- 级别：Important
- 描述：同步 `IpcSender` trait 用 `block_in_place` + `block_on` 桥接；`send()` 的 `write_all().await`+`flush().await` 无 `tokio::time::timeout`，AHK 挂死且管道写满时无限阻塞，占用 Tauri 工作线程，多命令并发可能耗尽线程池（已在注释声明为「已知妥协 #2」）。
- 根因：同步 trait 与异步 IpcManager 桥接 + send 缺写超时兜底。
- 修复方案：给 `send()` 加 `timeout` 包住 write+flush（超时判定管道断并触发 `notify_pipe_broken`）；长期让 `IpcSender` 返回异步或应用层 async 调用。

**T6-06 ｜ `listen_ahk` 每条消息 `msg.clone()` 无差别拷贝 + 背压无界传导**
- 位置：`src/infrastructure/ipc.rs:545（dispatch_response(msg.clone())）、567-572（outbound_tx.send(msg).await）、504、18`
- 级别：Important
- 描述：先 `msg.clone()`（`data` 为 `serde_json::Value`，克隆成本不低）再判断响应归属，绝大多数非响应消息被无谓深拷贝；`outbound_tx.send(msg).await`（非 `try_send`）在消费端变慢时阻塞监听循环，经 recv → OS 管道 → AHK 同步 WriteFile 反向压死。
- 根因：未先检查 `msg.ack_seq` 再 clone；outbound 无丢弃/合并策略。
- 修复方案：先 `if msg.ack_seq.is_some()` 再决定 clone；对 `key_send_event` 类高频非关键消息用 `try_send` + 满则丢弃/合并（关键 hotkey 保留 `.await`）。

**T6-07 ｜ joystick 每次按键事件 vJoy AcquireVJD/RelinquishVJD + `_GetAxisInfo` 每次重建多个 Map**
- 位置：`ahk_executor/joystick.ahk:299-317（_VJoyOpen/_VJoyClose）、360-395（_VJoySetBtn/_VJoySetAxis/_VJoySetPov）、444-454（_GetAxisInfo）、435-441（_IsAxis）`
- 级别：Important
- 描述：每次按键事件 `_VJoyOpen → _VJoyClose` 引用计数 0→1→0 快速往返，等价每次事件执行一次 AcquireVJD + RelinquishVJD，引用计数「持有期复用」完全失效；`_GetAxisInfo` 每次重建含 6 个子 Map 的新 Map，`_IsAxis` 每次重建数组，轴类键每次 down/up 都会产生 12 个 Map 分配。
- 根因：vJoy 设备「即开即关」峰值复用 + 无缓存查询表构造。
- 修复方案：将 vJoy 设备生命周期提升到组级（组启动 Acquire、组停止/紧急释放 Relinquish），运行期只做 `SetBtn/SetAxis/SetContPov`；对 `_GetAxisInfo`/`_IsAxis` 结果做 static 一次性缓存。

#### Minor（5）

| 编号 | 位置 | 描述 | 根因 | 修复方案 |
|------|------|------|------|---------|
| T3-08 + T6-12 ［合并］ | `presentation/webview2_manager.ahk:1040-1081,408,438-439`；`infrastructure/config_store.ahk:30-48,70`；`application/group_service.ahk:140` | `_BridgeImportConfig` 对同一份 jsonStr 解析两次；保存路径 ConfigStore.GetGroupConfig/oldConfigRaw/UpdateGroup 多层冗余 deepclone | I15/I16/I20 防御性拷贝叠加，未复用解析结果 | 解析结果复用；保存路径减少冗余 deepclone 层级 |
| T6-08 | `infrastructure/ipc_channel.ahk:66-86,89-109,192-204,112-170` | AHK 预留文件管道每次 Send/Emit 做 `FileGetSize` + 整条 Stringify + FileAppend | 预留接口未做发送侧批量/合并 | 明确标注低优先级/废弃，或改内存队列 + 定时刷新 |
| T6-09 | `infrastructure/json_serializer.ahk:17-21,49-88`；`infrastructure/error_system.ahk:199` | 日志用默认 `indent=2` 生成多行 pretty JSON，单条记录被拆多行且多出空格/缩进分配 | 日志写入复用了展示用 pretty 默认参数 | 日志路径用紧凑序列化（`indent:=0`），展示路径保留 pretty |
| T6-10 | `infrastructure/utils.ahk:41-55` | `_GetField` 对 JSON 字符串值每次重复 `JSONParser.Parse`，无缓存 | 缺「懒解析 + 缓存」 | 按对象指针缓存解析结果，或调用方先解析 |
| T6-11 | `domain/mode_registry.ahk:317,334,415,434` | 序列执行器冗余 `HasProp("_nextStepTime")` 检查（属性已预初始化） | 历史版本属性可能不存在，后续冗余防御未清理 | 直接访问 `group._nextStepTime`，删除 HasProp 分支 |

### 5.4 安全性（13 项）

> 本维度涵盖「安全 + 健壮性」，对应 Task 3 「安全 + 性能」与 Task 5 「安全性」的交叉判定。

#### Important（7）

**T3-01 ｜ `ValidateGroupOnly` 未校验热键格式，热键校验存在覆盖缺口**
- 位置：`infrastructure/config_validator.ahk:115-138`
- 描述：`_ValidateGroup`（84-88 行）已用 `_IsValidHotkeyFormat` 校验热键格式（I18），但 `ValidateGroupOnly`（121-122 行）只查 `hotkey` 是否存在、不校验格式；而 `ValidateGroupOnly` 正是 `CreateGroup/UpdateGroup` 实际走的入口，即 WebView2 保存分组时不做格式校验。非法热键写入阶段通过，到运行时 `Hotkey()` 才抛「热键注册失败…可能被占用」，误导真实原因。
- 根因：`ValidateGroupOnly` 未复用 `_ValidateGroup` 的 `_IsValidHotkeyFormat`，形成两条不一致校验路径。
- 修复方案：在 `ValidateGroupOnly` 的 hotkey 分支补 `_IsValidHotkeyFormat` 校验。

**T3-02 ｜ 配置验证器未校验按键名合法性**
- 位置：`infrastructure/config_validator.ahk:140-284`（`_ValidateModeFields` 各 mode 分支）
- 描述：验证器对 `keys/pressKeys/holdKeys/joyKeys` 只校验「非空」与数值边界，从不校验元素是否为合法按键名。领域层运行时由 `SkillGroup._IsValidKeyName`（skill_group.ahk:889-902）兜底——非法按键在 `_SendKey`/`_ReleaseKey` 静默跳过，形成「配置看着正常但按键永不触发」的隐蔽故障。
- 根因：验证器缺按键名校验；`_IsValidKeyName` 是 `SkillGroup` 私有方法，验证器无法复用。
- 修复方案：在 `_ValidateModeFields` 校验每个按键数组元素（复用 `_IsValidKeyName` 合法名单逻辑，或下沉到共享工具模块）。

**T3-03 ｜ 控制热键 `_ValidateHotkeys` 未校验热键格式**
- 位置：`infrastructure/config_validator.ahk:286-299`
- 描述：`_ValidateHotkeys` 只校验 5 个必需 action 是否存在、是否为空（空值仅记 WARNING），不校验格式。用户可写入非法控制热键（如 `garbage`），`_BindControlHotkeys`（skill_manager.ahk:147-187）运行时 `Hotkey()` 抛异常仅记 WARNING——「紧急停止」等关键安全功能一旦静默失效，后果严重。
- 根因：`_ValidateHotkeys` 未复用 `_IsValidHotkeyFormat`。
- 修复方案：对非空 action 值补 `_IsValidHotkeyFormat` 校验，非法时记 ERROR。

**T3-04 ｜ `GlobalSettingsEditor._Save` 输入未校验 + 忽略保存结果导致误报成功**
- 位置：`presentation/gui_manager.ahk:408-438`
- 描述：① 422-424 行直接 `Integer(Edit.Text)`，非数字抛 `ValueError` 被外层 catch 吞掉、无提示；② 432 行 `ConfigService.SaveConfig()` 返回值被忽略，433 行无条件 `MsgBox("全局设置已保存")`——保存被验证阻止时仍报「已保存」，重启后丢失。与 `WebView2Manager._BridgeSaveSettings` 完整校验+回滚+返回值处理不一致。
- 根因：`GlobalSettingsEditor._Save` 缺逐字段校验与保存结果检查，两条设置保存路径不一致。
- 修复方案：逐字段 try-catch 转换并提示；检查 `SaveConfig()` 返回值，失败提示「保存失败」。

**T3-06 ｜ 摇杆 JoySender 未注入时热路径每 tick 抛异常**
- 位置：`domain/joystick_executor.ahk:55,107`（两个 Executor）、`:157-160`（`_SendJoyKey` 注入检查）
- 描述：`_SendJoyKey` 第 159-160 行在 `try` 外抛「JoySender 未注入」异常，向上传播到 `Execute` 的 catch → 每次 tick 记一次 ERROR 日志（与 T3-05/T6-03 叠加放大高频写盘）；`JoystickHoldExecutor.Execute`（136-137 行）同样受影响。（其「release 一次性定时器未纳管」子项已并入 T6-02。）
- 根因：注入检查放在热路径内而非模式启动前。
- 修复方案：在 joystick 模式激活前（`Toggle`/`_SetupMode`）完成 `_joySender` 注入检查，避免每 tick 重复抛异常。

**T4-04 ｜ ConfigValidator 控制热键空值静默放行 + 无「控制热键 vs 分组热键」冲突检测**
- 位置：`crates/asd-domain/src/validator.rs:90-94`（validate_config 对 5 个控制热键）、`:137-139`（validate_hotkey_format 空串提前返回）
- 描述：`validate_config` 对 5 个控制热键仅调用 `validate_hotkey_format`，而该函数对空串直接 return（无 error/warning），故 `"emergency": ""` 会静默通过并被 `save_config_atomic` 持久化；`validate_duplicate_hotkeys` 只比对分组热键之间，未与控制热键做交叉冲突检测。对比同文件对分组热键「刻意补了」`hotkey.is_empty()` 的 error 分支（validator.rs:120-122），控制热键路径缺失对应空值 error。（与 T3-03 为 AHK/Rust 两侧同类缺口的对应项。）
- 根因：控制热键复用了「空串不校验也不报错」的函数约定，未意识到其为必填安全关键字段。
- 修复方案：对 5 个控制热键逐一补 `is_empty()` 的 `add_error`；扩展 `validate_duplicate_hotkeys` 纳入控制热键做交叉冲突检测。

**T5-01 ｜ `ProcessWatchdog`/`JobObjectGuard` 手写 `unsafe impl Send/Sync`，soundness 依赖脆弱的外部 Mutex 不变量**
- 位置：`src/infrastructure/watchdog.rs:67,73,499,502`
- 描述：4 处手写 `unsafe impl`（非 FFI 必然 unsafe 范畴，而是 soundness 关键点）：`ProcessWatchdog` 含 `Option<Child>`（`Send + !Sync`），手工 `unsafe impl Sync`（依据「所有访问经 `Arc<tokio::sync::Mutex>`」）；`JobObjectGuard(HANDLE)` 手工 Send/Sync（依据 Mutex 保护 + Drop 仅 CloseHandle）。当前不变量成立（生产路径先持锁再取 `&Guard`，且调用方立即 `.clone()`），但 `state()` 返回 `&WatchdogStateEnum`，一旦未来把引用保存到 guard 之外即形成跨锁共享引用 → 数据竞争 → UB。
- 根因：为把含 `!Sync` 字段的结构体装入 `Arc<Mutex>` 跨线程共享，选择手工标记而非重构字段组合。
- 修复方案：① `state()` 改为返回 Clone 类型杜绝引用外泄；② 或拆出 `Option<Child>` 使数据面可自动 `Sync`；③ 至少在 `state()` 文档注明「返回引用不得跨越锁守卫存活」。

#### Minor（6）

| 编号 | 位置 | 描述 | 根因 | 修复方案 |
|------|------|------|------|---------|
| T3-07 | `infrastructure/ipc_channel.ahk:181-184` | `_OnReceived` 监听器回调 `try callback(msgObj)` 无 catch，异常向上传播中断消息分发 | 误用「无 catch 的 try」 | 补 catch 并记 WARNING（与 KeyRecorder onEvent 处理一致） |
| T3-09 | `domain/key_recorder.ahk:273-302,312-323` | `_mouseHotkeys` 标志在注册完成后才置位，`_InstallMouseHooks` 中途异常时 `_RemoveMouseHooks` 提前返回，已注册钩子残留 | 标志位作为「清理开关」无法反映「部分注册」状态 | `_RemoveMouseHooks` 无条件遍历注销一轮，或每注册成功一个即维护状态 |
| T5-04 | `src/infrastructure/watchdog.rs:781,214,594-597` | `spawn_child` 在 async 循环内持锁同步执行 `taskkill` + `Command::spawn` 阻塞 I/O | 同步函数未做 spawn_blocking 隔离 | 包进 `tokio::task::spawn_blocking` 或改用 `tokio::process::Command` |
| T5-08 | `src/infrastructure/ipc.rs:76-85,180` | IPC auth token 由时间戳派生、比较非恒定时间 | 未引入密码学随机源 | token 改用随机字节（uuid/getrandom），比较改恒定时间（或保留退避缓解） |
| T5-09 | `src/lib.rs:117-138,663` | 无单实例保护，二次启动 listener 创建失败 + executor 错连首实例 | 未加单实例插件/互斥锁 | 使用 `tauri-plugin-single-instance` 聚焦并退出 |
| T5-10 | `src/infrastructure/watchdog.rs:417-461` | `graceful_shutdown` 持 watchdog 锁横跨多个 await（约 5s+），轮询被阻塞 | 锁粒度偏粗 | 将 wait_for_exit 轮询拆到锁外，或文档化阶段性阻塞 |

### 5.5 文档完整性（14 项）

#### Critical（1）

- **CR3（T7-01）**：见 §4-CR3。

#### Important（4）

**T7-02 ｜ `docs/migration-guide.md` 引用已迁移/删除的 API 与过时结构**
- 位置：`docs/migration-guide.md` §1.1（L42）、§3.4（L296-306）、§4.1（L421）、§4.3（L517）、§5.4.6（L562）
- 描述：仍描述 `src-tauri/` 下 `domain/infrastructure/application/` 三目录 +「13 个 Tauri Commands」；§3.4 IpcCommand 表仅 9 变体（缺 4）；§4.1 称 `Config::load_from_file()` 负责 BOM、§5.4 称 `Config::save()` 用 `to_string_pretty()`——这两个方法已迁到 `ConfigRepository`；§4.3 把 `GroupSettings` 标为 `HashMap`（实际 `IndexMap`）。
- 根因：文档写于 I/O 泄漏修复（设计决策 #2）与 crate 抽取之前，未回填。
- 修复方案：I/O 引用改为 `ConfigRepository`；IpcCommand 表补 13 变体；`HashMap` 改 `IndexMap`；对齐 AGENTS.md 5 crate 描述。

**T7-03 ｜ `asd-tauri/TESTING.md` 引用已删除的 test-manifest feature、fuzz 数量与汇总数过期**
- 位置：`asd-tauri/TESTING.md` L6、L8、L133-146
- 描述：运行命令矩阵与「关键提示」反复要求 `--features test-manifest`，但 `src-tauri/Cargo.toml` 已无 `[features]` 段（且有 `test_manifest_feature_removed.rs` 专门验证已移除）；L8「3 个 fuzz target」实际 5 个；L6「506+ Rust 测试函数」与 test-map「609」冲突。
- 根因：test-manifest feature 已移除（C8）但 TESTING.md 未同步；fuzz 由 3 增到 5 未更新。
- 修复方案：删除所有 test-manifest 命令与提示；fuzz 数量改 5 并补全命令；Rust 测试数与 test-map 对齐单一口径。

**T7-04 ｜ `asd-tauri/docs/test-map.md` 汇总表与明细表不一致，逐文件测试计数严重过时**
- 位置：`asd-tauri/docs/test-map.md` L15-19、L27-32、L69、L80-99、L146
- 描述：asd-tauri 明细「小计 153」+ manifest 1 应 = 154，但「总计 217」相差 63；asd-ipc-protocol 明细 71 但汇总 72；asd-test-harness 明细 0 但汇总 4（AGENTS.md 写 3）；逐文件 grep 对照多处严重不符（bridge_tests 13→4、config_cmd 7→29、group_cmd 4→20、recording_cmd 3→21、watchdog 21→28、watchdog_integration 17→14、command 3→4、error 5→6、integration_tests 36→34）。
- 根因：test-map 头部「2026-06-27 统计」，明细与汇总更新不同步。
- 修复方案：按文档自带统计命令重新全量统计，逐行更新明细表，使「小计 = 明细之和 = 汇总」一致。

**T7-05 ｜ 测试统计口径跨文档冲突（Rust 592 vs 609、AHK 执行器 244 vs 467、AHK v2 581 无法对账）**
- 位置：`AGENTS.md` L135/L340/L274 vs `asd-tauri/docs/test-map.md` L146-147 vs `asd-tauri/TESTING.md` L6-8
- 描述：Rust 总数 AGENTS「592」vs test-map「609」；AHK 执行器 AGENTS「244 个 Test_ 方法」vs test-map/TESTING「467 测试」两套口径未说明；AHK v2「581 个测试」仅 AGENTS 出现无法交叉验证；AGENTS 头部时间戳「Updated 2026-05-30」与正文「截至 2026-08-04」矛盾。
- 根因：多文档独立修订，统计日期与计数口径未统一，无单一权威来源。
- 修复方案：确立 test-map.md 为唯一测试统计来源，统一注明口径（`#[test]` 属性数 / Test_ 方法数 / 断言数分别标注），更新 AGENTS 头部 Updated 时间戳。

#### Minor（9）

| 编号 | 位置 | 描述 | 根因 | 修复方案 |
|------|------|------|------|---------|
| T2-07 + T7-07 ［合并］ | `AGENTS.md` Key Files / Subdirectories 表、L58-62 分层表 | AHK 模块清单不完整：infrastructure 缺 `config_io/joy_sender/migration_logger`；domain 缺 `joystick_executor/joystick_input/key_recorder/key_validator`；application 缺 `backup_service` | 模块新增/重构后未同步文档 | 按目录实际内容补全 AHK 三层模块清单 |
| T7-06 | `AGENTS.md` L1220-1227 | `IpcMessage` 示例仅 4 字段，实际 `message.rs` 有 9 字段 | 示例简化未标注 | 补齐字段或加「完整定义见 message.rs」注释 |
| T7-08 | `AGENTS.md` L72 | 「AHK 已知架构妥协」第 3 条实为 Rust 层面妥协，放错章节且与 L142「Rust 妥协」第 1 条重叠 | 编辑时表格串行未分类 | 移入 Rust 妥协表或标注「（Rust，误置于此）」 |
| T7-09 | `AGENTS.md` L251 | tests/ 根目录「22 个核心文件 / 15 个核心测试文件」拆分与列举不吻合（实际 16 个 test_*.ahk） | 计数口径与清单未同步 | 改为「16 个 test_*.ahk + 6 个框架/配置文件 = 22」 |
| T7-10 | `AGENTS.md` L1267 vs `tauri.conf.json` L5 vs `developer-guide.md` L804-805 | 应用数据目录/标识三处不一致（com.asd.skillmanager / com.asd.tauri / asd-tauri） | identifier 迁移未同步 | 以 tauri.conf.json `identifier` 为准统一（com.asd.tauri） |
| T7-11 | `AGENTS.md` L37-47、L109-111 | Rust Key Files / 目录表未登记 `backup_service.rs/group_service.rs/recording_service.rs/time_format.rs`、`infrastructure/shutdown.rs`、`tests/bridge_tests.rs`、`application/backup_service.ahk` | 模块在 test-map 与 code-review 后新增未回填 | 补入 Key Files 与架构子树表 |
| T7-12 | `docs/code-review-report-2026-08-03.md` L15、L17、L39 | 该历史报告对 AGENTS.md 的论断（4-crate、IpcCommand 示例全错、13 commands、test-manifest 存在）现已失效 | 历史报告未标注「已修复/已过时」 | 首页或条目加「部分问题已于 2026-08-04 后修复」勘误标注 |
| T7-13 | `asd-tauri/docs/test-map.md` L175-182 | E2E helpers 表未登记 `ahk_path.js`、`error_utils.js` 及 `__tests__/` | 新增辅助脚本未按规范登记 | 补登记路径/用途/引用方 |
| T7-14 | `AGENTS.md` L356、`test-map.md` L168 vs `AGENTS.md` L1239-1252 | E2E「modes（7）：7 种执行模式」与「支持 10 种模式」矛盾 | E2E 覆盖范围与系统能力未区分 | 改为「7 种（E2E 覆盖）；系统共 10 种，joystick_* 未纳入 E2E」 |

### 5.6 测试覆盖（7 项）

#### Important（3）

**T8-01 ｜ IpcManager 消息接收/分发循环缺直接单元测试**
- 位置：`asd-tauri/src-tauri/src/infrastructure/ipc.rs`（`listen_ahk` 的消息解析与 hotkey/heartbeat/recording 分发）
- 描述：Rust 侧 IPC 消息接收循环（accept → 解析 `IpcMessage` JSON → 按 `type` 分发）缺直接单测。现有覆盖仅 bridge_tests 的超时/断管测试与 E2E `ipc.spec.js`（7 黑盒用例）；malformed JSON、未知 type、空 data 等边界无白盒覆盖。
- 根因：`listen_ahk` 为 async 方法，未把「消息解析 → 分发」抽成可单测纯函数。
- 修复方案：参照 `shutdown::try_acquire_shutdown_guard` 模式，抽取 `parse_and_dispatch(message_bytes) -> Option<DispatchAction>` 纯函数，补 `#[cfg(test)]` 单测覆盖三分支。

**T8-02 ｜ 优雅关机流程主体缺测试（仅锁纯函数已覆盖）**
- 位置：`asd-tauri/src-tauri/src/lib.rs` `perform_graceful_shutdown`
- 描述：仅 `infrastructure::shutdown::try_acquire_shutdown_guard` 被提取测试；`perform_graceful_shutdown` 主体（发送 `IpcCommand::Shutdown`、停止 watchdog、销毁窗口、二次调用拦截）无测试。进程清理是本系统关键保障（设计决策 #6），主体无回归保障。
- 根因：历史重构只提取最易抽离的锁原子操作。
- 修复方案：复用 `asd-test-harness` mock 补 shutdown 序列集成测试，至少断言「锁未获取提前返回 / 锁获取后按序调用 IPC shutdown + watchdog stop」。

**T8-03 ｜ E2E spec 生命周期代码高度重复，失败上报严重级别硬编码、caseId 正则各自维护**
- 位置：`asd-tauri/e2e/specs/*.spec.js`（9 文件，例 config_cmd.spec.js:32-95）
- 描述：① 9 个 spec 各自复制「binary 检测 → skip / backup-restore config / appendResult + appendKnownIssue」四段约 60 行/spec，共 ~500 行重复；② `appendKnownIssue` 严重级别在所有 spec 硬编码 `'HIGH'`；③ caseId 提取正则各自硬编码，未按 `E2E-<SUITE>-NNN` 编号时以完整标题兜底，编号体系脆弱。
- 根因：spec 按文件独立复制模板，缺共享 base hook。
- 修复方案：抽 `helpers/spec-hooks.js` 导出统一 before/afterEach；严重级别改从 test 元数据传入或按错误类型推断；caseId 提取统一为共享函数。

#### Minor（4）

| 编号 | 位置 | 描述 | 根因 | 修复方案 |
|------|------|------|------|---------|
| T8-04 | `tests/run_all_tests.ahk` | 批量运行入口缺 `OnError` 回调，单 suite 崩溃会弹窗中断整体批量运行 | 被视为「运行器」而非「测试文件」 | 顶部补 `#ErrorStdOut` + `#Warn` + `OnError` 回调 |
| T8-05 | `AGENTS.md`（"16 ignored"）、`test-map.md:84` | `#[ignore]` 实测 19+（watchdog 16 + bridge 3），与 AGENTS「16」、test-map「15」三处口径不一致；`config_compat_tests.rs:3` 的 `MAIN_CONFIG_JSON` 未登记为固件 | 测试规模统计手工维护未回写 | 用 analyze-tests.ps1 自动输出 `#[ignore]` 数；补登记 MAIN_CONFIG_JSON |
| T8-06 | `tests/fixtures/`；`tests/test_ahk_executor/test_joystick.ahk:463` | fixtures 缺 joystick 3 模式配置样本；joystick 测试硬编码 `"joystick_periodic"` 字符串 | fixtures v4.1 新增未纳入摇杆模式 | 补 `joystick_config.json`（或 sample_config 增补），测试改 fixture 派生值 |

> 注：Task 8 自报 Minor 4 条，其中第 4 条在分报告正文未展开（对应 §2 的「Task 8 未列示 Minor +1」），故上表仅 T8-04~T8-06 三条。

---

## 6. 改进建议汇总

### P0 — Critical（立即处置，阻塞运行/发布）

| 优先级 | 建议 | 对应发现 |
|:------:|------|---------|
| 1 | **恢复半回退工作区**：在 `main.ahk` 恢复 `#Include "infrastructure\config_io.ahk"` 与 `#Include "application\backup_service.ahk"`，恢复 OnExit 的 `JoyHotkeyManager.Shutdown()`；`backup_core.ahk:70` 改调 `ConfigIO.ExportToFile`；清理 `config_service.ahk:412-417` 全局包装。**先确认工作区 4 个未提交文件意图（完成或撤销）** | CR1（T2-01 + T2-02）→ 基线 I1/I6 |
| 2 | **收敛热路径 IPC 上报**：默认关闭逐键 `key_send_event` 上报（仅录制/验证模式发送），或改批量缓冲 + 定时刷新；管道写非阻塞、失败降级 | CR2（T6-01） |
| 3 | **重写/归档过时文档**：`developer-guide.md`、`migration-guide.md` 对齐 5-member workspace 现状，或标注「已过时以 AGENTS.md 为准」 | CR3（T7-01）、T7-02 |

### P1 — Important（尽快）

| 方向 | 建议 | 对应发现 |
|------|------|---------|
| 校验补全 | 补齐分组热键格式、按键名合法性、控制热键格式/空值/冲突检测（AHK 与 Rust 两侧） | T3-01、T3-02、T3-03、T4-04 |
| 输入健壮性 | `GlobalSettingsEditor._Save` 逐字段校验 + 检查保存结果；joystick 注入检查前置到模式启动前 | T3-04、T3-06 |
| 日志限速 | 给 `ErrorSystem`/`JSONLogger` 加同构限速器，对齐「每秒一次」口径 | T3-05 + T6-03 |
| unsafe 收敛 | `state()` 改返回 Clone 类型 / 拆出 `Option<Child>`，消除 4 处手写 `unsafe impl` 的不变量脆弱性 | T5-01 |
| 伪断言清理 | 删除 `EXPECTED_TAURI_COMMAND_COUNT` 永真式断言或改为真实校验 | T5-02 |
| 定时器生命周期 | 一次性 release/up 定时器登记进 Map；`StartXxx` 覆盖前先取消旧定时器 | T6-02、T6-04 |
| IPC 阻塞与背压 | `send()` 加写超时；先判 `ack_seq` 再 clone、非关键消息 `try_send` | T6-05、T6-06 |
| joystick 性能 | vJoy 设备生命周期提升到组级；`_GetAxisInfo`/`_IsAxis` 结果静态缓存 | T6-07 |
| AHK 架构 | 打破 utils/json_parser/json_logger 循环 include；`config_store` 显式 include `json_logger` | T2-03、T2-04 |
| 文档统一 | 确立 test-map.md 为唯一统计来源，修正 TESTING.md test-manifest 残留、test-map 明细与汇总 | T7-03、T7-04、T7-05 |
| 测试补强 | 为 IpcManager 分发循环、优雅关机主体补单测；抽 E2E 共享 hooks | T8-01、T8-02、T8-03 |

### P2 — Minor（择机，随迭代收口）

- **测试规范**：补 `run_all_tests.ahk` 的 OnError、`test_error_captor.ahk` 的 OnError（对应基线 C6 残留）、joystick fixtures（T8-04、T8-06、C6）。
- **AGENTS.md 补全**：AHK/Rust 模块清单与 Key Files、IpcMessage 完整字段、妥协表归类、tests 计数、app data 标识、头部时间戳（T2-07/T7-07、T7-06、T7-08、T7-09、T7-10、T7-11）。
- **依赖/封装收口**：移除 asd-domain/asd-ipc-protocol 冗余 `tracing`；删除 deprecated scheduler.rs；`atomic_write` 并入 ConfigRepository；错误类型统一（T4-01、T4-02、T4-03、T4-06、T4-07、T4-08）。
- **代码一致性**：`config_store` Set/Save 深拷贝策略统一；静态属性声明补全；`kill_and_reap` 收敛；`cargo fmt` 门禁；JOBOBJECTINFOCLASS 具名常量（T2-06、T2-08、T5-06、T5-13、T5-14）。
- **健壮性**：ipc_channel 监听器补 catch；KeyRecorder 钩子标志位修正；spawn_child 改 spawn_blocking；token 随机化；单实例保护；graceful_shutdown 锁粒度（T3-07、T3-09、T5-04、T5-08、T5-09、T5-10）。
- **性能微调**：减少冗余 deepclone、日志紧凑序列化、`_GetField` 缓存、清理冗余 HasProp、IPCChannel 文件管道降级（T3-08/T6-12、T6-08~T6-11）。

---

> **报告说明**：本报告基于 `docs/review/2026-08-20/` 下 8 份分报告做去重、整合与分级，未引入任何分报告之外的新发现。原始 76 条 → 去重 4 组 → 最终 72 条（Critical 3 / Important 23 / Minor 46）。仅写入本文件 `docs/code-review-report-2026-08-20.md`，未修改任何其他文件。