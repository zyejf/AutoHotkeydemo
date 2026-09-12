# 代码审查问题修复计划（2026-08-20）Spec

## Why

`docs/code-review-report-2026-08-20.md` 已完成全面代码审查，产出 72 条去重后发现（Critical 3 / Important 23 / Minor 46），并给出每条问题的根因与修复方向。但报告本身是「诊断」，尚未形成可执行的修复路线图。需要将 72 条发现转化为一份结构化的、可落地的修复计划，明确各问题的描述、影响范围、根因、修复步骤、时间表、资源、风险、测试、回滚与效果评估标准，并划分阶段、责任与时限。

本任务只产出「修复计划」文档，不实施任何代码修改（代码修复是计划获批后的后续任务）。

## What Changes

- 新增一份修复计划文档 `docs/remediation-plan-2026-08-20.md`，覆盖报告全部 72 条发现。
- 按优先级分级（P0=Critical、P1=Important、P2=Minor）并分组。
- 对每项 Critical 提供完整的 11 要素修复方案；对 Important 按主题批次提供完整要素；对 Minor 提供批量处理方案。
- 新增横向管理章节：实施时间表、资源需求、风险评估与应对、测试验证、回滚机制、效果评估标准、责任分工与时限。
- 计划的中间产物统一存放于 `docs/review/2026-08-20/fix-plan/` 目录。

## Impact

- Affected specs: 新增（规划任务，不修改代码）。
- Affected code: 无（只读；产出物仅为计划文档与中间笔记）。
- 依赖基线: `docs/code-review-report-2026-08-20.md` 及 `docs/review/2026-08-20/` 下 9 份分报告（phase1-baseline + task-2 ~ task-8）。
- 产出物: `docs/remediation-plan-2026-08-20.md` + `.trae/specs/remediation-plan-2026-08-20/`（规格文档）。

## ADDED Requirements

### Requirement: 问题清单与优先级分级

计划 SHALL 建立覆盖全部 72 条发现的问题清单，并统一分级。

#### Scenario: 分级与主题分组

- **WHEN** 梳理问题清单
- **THEN** 将发现映射为 P0（3 条 Critical：CR1/CR2/CR3）、P1（23 条 Important）、P2（46 条 Minor）
- **AND** 将 P1/P2 按「主题」分组（如：校验覆盖缺口、热路径日志限速、定时器生命周期、IPC 背压、unsafe 收敛、文档漂移、测试覆盖补强、命名与死代码清理）
- **AND** 保留每条发现的原始编号（T2-01 等）与位置（file:line），以便追溯报告原文

### Requirement: 每项问题的修复方案必需要素

计划 SHALL 对每项 Critical 与每个 Important 主题批次提供完整修复方案，包含以下要素。

#### Scenario: 修复方案要素完整性

- **WHEN** 描述一项（或一个主题批次）的修复方案
- **THEN** 包含「问题描述」（复述报告要点，不虚构）
- **AND** 包含「影响范围评估」（受影响模块/功能/用户路径）
- **AND** 包含「根本原因分析」（引用报告根因，必要时补充因果链）
- **AND** 包含「具体修复步骤」（可执行、有序、指向具体 file:line）
- **AND** 包含「测试验证方案」（针对性验证方法）
- **AND** 包含「回滚机制」（可逆性说明或 revert 方案）
- **AND** 包含「修复后效果评估标准」（可度量的达标判据）

### Requirement: 分阶段实施计划

计划 SHALL 将修复工作划分为清晰阶段，并按依赖与风险排序。

#### Scenario: 阶段划分

- **WHEN** 制定实施计划
- **THEN** 划分 Phase 0（紧急修复：3 项 Critical，含 CR1 工作区半回退状态处置预案）
- **AND** 划分 Phase 1（重要修复：23 项 Important，按主题批次分批）
- **AND** 划分 Phase 2（次要优化：46 项 Minor，批量消化）
- **AND** 划分 Phase 3（回归验证：全量测试 + 文档同步 + 统计口径收敛）
- **AND** 明确各阶段之间的依赖关系（如 CR1 处置必须先于其余修复）

### Requirement: 实施时间表与责任时限

计划 SHALL 提供实施时间表，明确各阶段的责任角色与完成时限。

#### Scenario: 时间表与责任

- **WHEN** 制定时间表
- **THEN** 用表格呈现「阶段 × 时间框 × 责任角色 × 里程碑交付物」
- **AND** 时间框使用优先级驱动的相对时间（P0=立即/下次运行前、P1=短期、P2=长期、P3=回归），避免虚构绝对日历日期
- **AND** 责任角色按职责划分（开发者 / 审查者 / 测试），并注明具体人名需由团队确认填充
- **AND** P0 明确「必须在下次运行/发布前完成」这一硬性时限

### Requirement: 资源需求

计划 SHALL 列出完成修复所需的资源。

#### Scenario: 资源清单

- **WHEN** 评估资源需求
- **THEN** 按阶段列出所需资源（人力投入、工具链、测试环境：AHK v2 运行时、Rust 工具链、tauri-driver、E2E 环境等）
- **AND** 标注每项资源是否已具备或需新增

### Requirement: 风险评估与应对措施

计划 SHALL 对每阶段/每主题识别主要风险并给出应对措施。

#### Scenario: 风险登记

- **WHEN** 进行风险评估
- **THEN** 用「风险 × 影响 × 概率 × 应对措施」矩阵呈现
- **AND** 重点覆盖：CR1 回退状态的处置误判风险、unsafe soundness 改动的回归风险、热路径限速改动对用户体验的影响、文档重写的断链风险、配置校验收紧导致的既有配置被拒绝风险

### Requirement: 测试验证方案

计划 SHALL 提供整体与分项的测试验证方案。

#### Scenario: 测试策略

- **WHEN** 制定测试方案
- **THEN** 规定每个阶段完成后的验证命令（AHK 语法检查 / AHK 全套测试 / `cargo test --workspace` / Miri / E2E）
- **AND** 对每项 Critical/Important 指明其对应的回归测试或需新增的测试用例
- **AND** 引用 AGENTS.md 测试前置检查流程（语法检查 stderr 重定向 / 接管指令验证 / 运行时验证）

### Requirement: 回滚机制

计划 SHALL 规定修复失败时的回滚手段。

#### Scenario: 回滚保障

- **WHEN** 定义回滚机制
- **THEN** 规定：先提交（或 stash）当前工作区 4 个未提交文件形成干净基线，逐项修复独立提交，单项回退用 `git revert <commit>`
- **AND** 强调禁止回滚用户已存在的未提交改动（在处置 CR1 前先备份/明确其归属）

### Requirement: 修复后效果评估标准

计划 SHALL 定义完成后的可量化评估标准。

#### Scenario: 达标判据

- **WHEN** 定义评估标准
- **THEN** 给出可量化指标：Critical/Important 项清零、全量测试通过率 100%、`cargo clippy`/`cargo fmt` 干净、文档漂移项清零、历史修复核对表无「引入回归」项
- **AND** 每条 Critical 附独立验收判据（如 CR1：`main.ahk` 恢复 include 且 `layering_security_suites` 通过）

### Requirement: 只读约束

规划过程 SHALL NOT 修改任何源码文件。

#### Scenario: 仅产出计划

- **WHEN** 编写修复计划
- **THEN** 仅创建 `docs/remediation-plan-2026-08-20.md` 与 `docs/review/2026-08-20/fix-plan/` 下的中间笔记，以及 `.trae/specs/remediation-plan-2026-08-20/` 规格文档
- **AND** 严禁修改任何 .ahk / .rs / .toml / .json 源码或配置文件

## MODIFIED Requirements

无。

## REMOVED Requirements

无。