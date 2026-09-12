# 全面代码审查（2026-08-20）Spec

## Why

项目在 2026-08-03 完成过一次全面审查（`docs/code-review-report-2026-08-03.md`，94 项发现），随后完成了 10 项 Critical 与 43 项 Important 修复，并持续新增了 `backup_service.rs`、`group_service.rs`、`recording_service.rs`、`time_format.rs`、`shutdown.rs` 等模块。距上次审查约两周，代码库发生显著演进，需要一次新的全面审查：既验证历史修复是否真正落地且未引入回归，又审查新增代码，同时补充此前未重点覆盖的性能优化与文档完整性两个维度。

本次审查为只读分析，不修改任何代码。

## What Changes

- 全面审查 AHK v2 与 Rust/Tauri 两部分代码。
- 扩展审查维度为六项：架构设计、代码质量与可维护性、性能优化、安全性、文档完整性、测试覆盖。
- 验证历史修复（Critical 10 + Important 43）是否落实且未引入回归。
- 审查 08-03 之后新增/改动的代码（`asd-application/*_service.rs`、`time_format.rs`、`shutdown.rs`、`commands/mod.rs` 等）。
- 生成结构化审查报告，按 Critical / Important / Minor 三级分类。
- 每条发现含位置（file:line）、维度、严重级别、描述、根因、具体修复/优化方案。

## Impact

- Affected specs: 新增（只读审查，不修改代码、不影响其他 spec）。
- Affected code（审查范围）:
  - AHK v2：`domain/`、`infrastructure/`、`application/`、`presentation/`、`tests/`、根目录入口（`main.ahk`、`asd.ahk`、`config.ahk`、`gui.ahk`）。
  - Rust/Tauri：`asd-tauri/crates/`（asd-domain / asd-ipc-protocol / asd-application / asd-test-harness）、`asd-tauri/src-tauri/`。
  - 文档：`AGENTS.md`、`docs/`、`asd-tauri/docs/`、`asd-tauri/TESTING.md`、`asd-tauri/Cargo.toml`、`src-tauri/tauri.conf.json`。
- 产出物：`docs/code-review-report-2026-08-20.md`（统一报告） + `.trae/specs/comprehensive-code-review-2026-08-20/`（规格文档）。

## ADDED Requirements

### Requirement: 六维度审查覆盖

系统 SHALL 对 AHK v2 与 Rust/Tauri 两部分执行六维度的审查：架构设计、代码质量与可维护性、性能优化、安全性、文档完整性、测试覆盖。检查项参照 AGENTS.md 中记录的强制规则、已知架构妥协、常见错误与陷阱。

#### Scenario: 架构设计维度

- **WHEN** 审查 AHK v2 部分
- **THEN** 检查 DDD 四层依赖关系（`domain/` → `infrastructure/` 仅允许 `error_system.ahk` 的 `LogError`，以及 `joy_hotkey_manager.ahk` → `joystick_input.ahk` 纯工具函数的已登记妥协）
- **AND** 检查 4 项已知架构妥协的约束边界是否被遵守、是否有新的越界依赖
- **AND** 检查模块间 `#Include` 是否合理、是否存在循环依赖
- **AND** 检查是否有 I/O 或表现层逻辑泄漏到领域层
- **AND** 检查工具函数迁移（`_GetProp`/`_GetField` 于 `infrastructure/utils.ahk`）是否完成
- **WHEN** 审查 Rust/Tauri 部分
- **THEN** 检查 5-crate workspace 依赖关系图（asd-test-harness 为 dev 依赖）
- **AND** 检查纯逻辑 crate 无禁用依赖（tokio / tauri / interprocess / windows；`std::fs` 仅限 asd-application 的 ConfigRepository 与登记例外）
- **AND** 检查 trait 抽象解耦（IpcSender / EventEmitter / ProcessWatcher）
- **AND** 检查新增 service 层（backup_service / group_service / recording_service）与 scheduler / ConfigRepository 的职责边界

#### Scenario: 代码质量与可维护性维度

- **WHEN** 审查代码质量
- **THEN** 检查命名规范（AHK PascalCase/camelCase/下划线私有/全大写常量；Rust snake_case/PascalCase）
- **AND** 检查错误处理（AHK OnError / try-catch / JSONLogger；Rust thiserror / `?`）
- **AND** 检查 AGENTS.md 强制规则遵守（`#ErrorStdOut` + `#Warn VarUnset` + `#Warn Unreachable` + `OnError` 在所有 .ahk 文件）
- **AND** 检查箭头函数 `=>` 块体陷阱、字符串拼接花括号陷阱
- **AND** 检查重复代码、圈复杂度、注释完整度、空 catch 块
- **AND** 检查 GUI 控件规范、定时器管理、周期性触发时间规范
- **AND** 检查 Rust 代码风格（tracing 日志、`#[tauri::command]` 宏、thiserror）

#### Scenario: 性能优化维度

- **WHEN** 审查性能
- **THEN** 检查 AHK 热路径（`Execute*` 方法）日志限速是否有效（每秒最多一次）
- **AND** 检查周期性触发是否使用独立触发时间（禁止 `Mod(A_TickCount, interval)`）
- **AND** 检查定时器是否泄漏、是否可正确停止（`_timers` Map）
- **AND** 检查 Rust↔AHK IPC 吞吐与背压、JSON 序列化热点的开销
- **AND** 检查循环内重复的 JSON 解析/序列化、Map 查找、深拷贝（deepclone）
- **AND** 检查阻塞调用（`blocking_lock`）与异步上下文冲突带来的潜在延迟

#### Scenario: 安全性维度

- **WHEN** 审查安全性
- **THEN** 检查输入验证（配置、热键、用户输入、录制数据）与边界校验
- **AND** 检查 Map/Object 安全访问（Has / HasProp / `Map.Delete` 前置检查 / 数组越界）
- **AND** 检查 WebView2 通信安全（postMessage 模式、禁止 sync 代理、禁止 `ExecuteScriptAsync` 等待 Promise）
- **AND** 检查文件 I/O 错误处理与路径处理（引号、编码）
- **AND** 检查 Rust `unsafe`（应无）、`unwrap`/`expect`（panic 风险）
- **AND** 检查 IPC 通信安全（named pipe 名称一致性、错误处理）
- **AND** 检查进程管理（JobObjects、心跳超时、panic hook 补偿、进程清理仅限 `asd_executor.exe`）
- **AND** 检查并发安全（Arc / Mutex / `blocking_lock` 死锁风险）

#### Scenario: 文档完整性维度

- **WHEN** 审查文档
- **THEN** 检查 AGENTS.md 与实际代码是否一致（crate 数、Tauri commands 数、测试统计口径、执行模式表、IpcCommand 示例）
- **AND** 检查 `docs/`（developer-guide / migration-guide / commit-convention / code-review-report）是否过时
- **AND** 检查 `asd-tauri/docs/test-map.md` 测试分布登记是否与实测一致
- **AND** 检查 `asd-tauri/TESTING.md` 测试指南是否覆盖新模块
- **AND** 检查配置结构（`config.json` schema）文档是否与 Rust/AHK 序列化实现一致

#### Scenario: 测试覆盖维度

- **WHEN** 审查测试
- **THEN** 检查测试覆盖率盲区（纯逻辑 crate 之外的 src-tauri、新增 *_service.rs 模块）
- **AND** 检查测试质量与隔离性（全局状态污染、测试间依赖）
- **AND** 检查 fixture 管理（`tests/fixtures/`、`include_str!`、命名规范）
- **AND** 检查 AHK 执行器测试（57 套件 / 244 Test_ 方法口径）
- **AND** 检查 E2E 测试完整性（9 suite / 53 用例）
- **AND** 检查测试前置检查流程遵守（语法检查 / 接管指令验证 / 运行时验证）

### Requirement: 历史修复验证

系统 SHALL 验证 08-03 报告中 10 项 Critical 与 43 项 Important 修复是否真正落地，且未引入新的回归。

#### Scenario: 修复落地核对

- **WHEN** 盘点 08-03 之后代码变更
- **THEN** 对照 `docs/superpowers/plans/2026-08-04-important-review-findings.md` 与 08-03 报告逐项核对
- **AND** 标记每项的状态：已修复 / 部分修复 / 未修复 / 修复引入回归

### Requirement: 审查报告分级

系统 SHALL 将所有发现按严重程度分为三级。

#### Scenario: Critical 级别

- **WHEN** 发现会导致崩溃、数据损坏、安全漏洞或架构严重违规的问题
- **THEN** 标记为 Critical，含精确位置（file:line）与紧急修复建议

#### Scenario: Important 级别

- **WHEN** 发现影响可维护性、存在潜在风险、性能缺陷或违反 AGENTS.md 强制规范的问题
- **THEN** 标记为 Important，含修复建议

#### Scenario: Minor 级别

- **WHEN** 发现代码风格、命名、注释、文档格式等不影响功能的问题
- **THEN** 标记为 Minor，记录待办

### Requirement: 报告结构

审查报告 SHALL 包含执行摘要、按维度分组的详细发现、历史修复核对表、统计汇总。

#### Scenario: 报告内容

- **WHEN** 生成报告
- **THEN** 包含执行摘要（总体评估、关键风险概述、关键指标）
- **AND** 包含按维度 + 模块分组的发现清单
- **AND** 每条发现含：位置（file:line）、维度、严重级别、描述、根因、修复/优化方案
- **AND** 包含历史修复核对表（Critical/Important 修复状态）
- **AND** 包含统计汇总（各级别数量、按维度分布、按模块分布）

### Requirement: 只读审查约束

审查过程 SHALL NOT 修改、创建或删除任何源代码文件。

#### Scenario: 不修改代码

- **WHEN** 执行审查
- **THEN** 仅读取和分析代码，所有发现记录在报告中
- **AND** 不创建、修改、删除任何 .ahk / .rs / .toml / .json 源代码或配置文件
- **AND** 仅生成审查报告与规格文档

## MODIFIED Requirements

无。

## REMOVED Requirements

无。