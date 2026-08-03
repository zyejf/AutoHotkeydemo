# 全面代码审查 Spec

## Why

项目采用 AHK v2 + Rust/Tauri 混合架构，包含 506+ Rust 测试、57 套件/467 AHK 执行器测试以及大量模块。在持续迭代过程中，需要对两部分代码进行一次全面审查，识别架构合规性、代码质量、安全性和测试覆盖方面的问题，为后续改进提供按优先级排序的依据。本次审查为只读分析，不修改任何代码。

## What Changes

- 对 AHK v2 部分（domain/infrastructure/application/presentation/tests/外围模块）执行四维度审查
- 对 Rust/Tauri 部分（asd-domain/asd-ipc-protocol/asd-application/src-tauri）执行四维度审查
- 采用矩阵式分工（模块 × 维度）派遣并行子代理，最大化审查效率
- 生成结构化审查报告，按 Critical/Important/Minor 三级分类所有发现
- 报告包含问题位置（file:line）、根因分析、修复建议，但不修改任何代码

## Impact

- Affected specs: 无（本次为只读审查，不修改代码，不影响其他 spec）
- Affected code:
  - AHK v2: `domain/`, `infrastructure/`, `application/`, `presentation/`, `tests/`, `equipment_recognizer.ahk`, `ocr.ahk`, `joystick_tester.ahk`
  - Rust/Tauri: `asd-tauri/crates/asd-domain/`, `asd-tauri/crates/asd-ipc-protocol/`, `asd-tauri/crates/asd-application/`, `asd-tauri/src-tauri/src/`
- 产出物: `docs/code-review-report-2026-08-03.md`（统一审查报告）

## ADDED Requirements

### Requirement: 四维度审查覆盖

系统 SHALL 对 AHK v2 和 Rust/Tauri 两部分代码执行四个维度的审查：架构合规性、代码质量与可维护性、安全性与健壮性、测试覆盖与质量。每个维度的检查项参照 AGENTS.md 中记录的强制规则、已知架构妥协和常见错误。

#### Scenario: 架构合规性审查

- **WHEN** 审查 AHK v2 部分
- **THEN** 检查 DDD 四层依赖关系（domain → infrastructure 仅允许 error_system.ahk 的 LogError）
- **AND** 检查 4 项已知架构妥协的约束边界是否被遵守
- **AND** 检查模块间 `#Include` 关系是否合理
- **AND** 检查是否有 I/O 泄漏到领域层
- **AND** 审查 Rust/Tauri 部分
- **THEN** 检查 4-crate workspace 依赖关系
- **AND** 检查纯逻辑 crate 无禁用依赖（tokio/tauri/interprocess/windows，std::fs 仅限 asd-application 的 ConfigRepository）
- **AND** 检查 trait 抽象解耦（IpcSender/EventEmitter/ProcessWatcher）
- **AND** 检查 I/O 泄漏修复（Config I/O 在 ConfigRepository）
- **AND** 检查 3 项已知架构妥协约束边界

#### Scenario: 代码质量与可维护性审查

- **WHEN** 审查代码质量
- **THEN** 检查命名规范（AHK PascalCase/camelCase；Rust snake_case/PascalCase）
- **AND** 检查错误处理（AHK OnError/try-catch/JSONLogger；Rust thiserror/? 操作符）
- **AND** 检查 AGENTS.md 强制规则遵守（#ErrorStdOut/#Warn/OnError 在所有 .ahk 文件）
- **AND** 检查箭头函数陷阱（`=>` 块体）、字符串拼接花括号陷阱
- **AND** 检查重复代码、圈复杂度、注释完整度
- **AND** 检查 GUI 控件规范、定时器管理规范、周期性触发时间规范
- **AND** 检查 Rust 代码风格（tracing 日志、Tauri command 宏标注）

#### Scenario: 安全性与健壮性审查

- **WHEN** 审查安全性
- **THEN** 检查输入验证、配置校验逻辑
- **AND** 检查 Map/Object 访问安全（Has/HasProp 检查、Map.Delete 前置检查）
- **AND** 检查 WebView2 通信安全（postMessage 模式、禁止 sync 代理、禁止 ExecuteScriptAsync 等待 Promise）
- **AND** 检查 unsafe 代码（应无）、unwrap/expect 使用（panic 风险）
- **AND** 检查 IPC 通信安全（named pipe）、进程管理（JobObjects、心跳超时）
- **AND** 检查并发安全（Arc/Mutex/blocking_lock 死锁风险）
- **AND** 检查错误传播链完整性

#### Scenario: 测试覆盖与质量审查

- **WHEN** 审查测试
- **THEN** 检查测试覆盖率盲区（纯逻辑 crate 96.57% 之外的 src-tauri）
- **AND** 检查测试质量与隔离性（全局状态污染）
- **AND** 检查 fixture 管理（tests/fixtures/、include_str!、命名规范）
- **AND** 检查 test-manifest feature 覆盖
- **AND** 检查 E2E 测试完整性（9 suite/53 用例）
- **AND** 检查 AHK 执行器测试（57 套件/467 测试）
- **AND** 检查测试前置检查流程遵守（语法检查/接管指令验证/运行时验证）

### Requirement: 审查报告分级

系统 SHALL 将所有发现按严重程度分为三级。

#### Scenario: Critical 级别

- **WHEN** 发现会导致崩溃、数据损坏、安全漏洞或架构严重违规的问题
- **THEN** 标记为 Critical
- **AND** 必须包含精确位置（file:line）和紧急修复建议

#### Scenario: Important 级别

- **WHEN** 发现影响可维护性、存在潜在风险或违反 AGENTS.md 强制规范的问题
- **THEN** 标记为 Important
- **AND** 包含修复建议

#### Scenario: Minor 级别

- **WHEN** 发现代码风格、命名、注释等不影响功能的问题
- **THEN** 标记为 Minor
- **AND** 记录待办

### Requirement: 报告结构

审查报告 SHALL 包含执行摘要、按模块分组的详细发现、统计汇总。

#### Scenario: 报告内容

- **WHEN** 生成报告
- **THEN** 包含执行摘要（总体评估、关键风险概述、关键指标）
- **AND** 包含按模块（AHK v2 各层 / Rust 各 crate）分组的发现清单
- **AND** 每条发现含：位置（file:line）、维度、严重级别、描述、根因、修复建议
- **AND** 包含统计汇总（各级别数量、按维度分布、按模块分布）

### Requirement: 只读审查约束

审查过程 SHALL NOT 修改、创建或删除任何源代码文件。

#### Scenario: 不修改代码

- **WHEN** 执行审查
- **THEN** 仅读取和分析代码，所有发现记录在报告中
- **AND** 不创建、修改、删除任何 .ahk / .rs / .toml / .json 源代码或配置文件
- **AND** 仅生成审查报告文档（`docs/code-review-report-2026-08-03.md`）

### Requirement: 矩阵式并行审查

系统 SHALL 采用矩阵式分工（模块 × 维度）派遣并行子代理执行审查，每个子代理聚焦单一模块的单一或相关维度，避免上下文过载和重复读取。

#### Scenario: 并行审查执行

- **WHEN** 执行 Phase 1 审查
- **THEN** 派遣 8 个独立子代理并行执行（AHK v2 4 个 + Rust/Tauri 4 个）
- **AND** 每个子代理产出该模块/维度的发现清单
- **WHEN** Phase 1 全部完成
- **THEN** 派遣 1 个汇总子代理整合所有发现，生成统一报告

## MODIFIED Requirements

无（本次为新增审查任务，不修改已有需求）

## REMOVED Requirements

无
