# AutoHotkey v2 技能管理器 - 测试策略设计文档

<!-- Generated: 2026-05-13T22:50:00+08:00 -->

## 1. 概述

### 1.1 目的

为 AutoHotkey v2 技能管理器制定并实施一套全面、系统化的软件测试策略，确保产品质量和功能稳定性。

### 1.2 范围

- 单元测试：所有功能模块、独立函数及组件
- 集成测试：模块间交互、层间数据流
- 端到端测试：完整用户流程
- 测试框架：测试运行器、报告器、Mock 工厂、覆盖率收集器

### 1.3 测试架构

采用**混合测试架构**：
- 单元测试按 DDD 层组织
- 集成测试按场景组织
- 端到端测试按用户流程组织

## 2. 测试架构设计

### 2.1 目录结构

```
tests/
├── unit/                          # 单元测试（按层组织）
│   ├── domain/                    # 领域层单元测试
│   │   ├── test_interfaces.ahk
│   │   ├── test_mode_registry.ahk
│   │   ├── test_skill_group.ahk
│   │   └── test_skill_manager.ahk
│   ├── infrastructure/            # 基础设施层单元测试
│   │   ├── test_config_store.ahk
│   │   ├── test_json_parser.ahk
│   │   ├── test_config_validator.ahk
│   │   ├── test_debug_logger.ahk
│   │   ├── test_json_logger.ahk
│   │   ├── test_error_system.ahk
│   │   ├── test_backup_core.ahk
│   │   └── test_ipc_channel.ahk
│   ├── application/               # 应用层单元测试
│   │   ├── test_group_service.ahk
│   │   └── test_config_service.ahk
│   └── presentation/              # 表现层单元测试
│       ├── test_gui_manager.ahk
│       ├── test_group_editor.ahk
│       ├── test_ui_manager.ahk
│       ├── test_backup_ui.ahk
│       └── test_debug_panel.ahk
│
├── integration/                   # 集成测试（按场景组织）
│   ├── scenarios/                 # 业务场景测试
│   │   ├── test_skill_execution.ahk
│   │   ├── test_config_management.ahk
│   │   ├── test_gui_workflow.ahk
│   │   └── test_error_handling.ahk
│   ├── layer_interaction/         # 层间交互测试
│   │   ├── test_domain_infra.ahk
│   │   ├── test_app_domain.ahk
│   │   └── test_presentation_app.ahk
│   └── e2e/                       # 端到端测试
│       ├── test_full_workflow.ahk
│       └── test_user_scenarios.ahk
│
├── framework/                     # 测试框架
│   ├── test_runner.ahk            # 测试运行器
│   ├── test_reporter.ahk          # 测试报告器
│   ├── assertion.ahk              # 断言库
│   ├── mock_factory.ahk           # Mock 工厂
│   ├── coverage_collector.ahk     # 覆盖率收集器
│   └── test_config.ahk            # 测试配置
│
├── reports/                       # 测试报告
│   ├── latest.json                # 最新测试报告
│   ├── history/                   # 历史报告
│   └── coverage/                  # 覆盖率报告
│
├── run_tests.ps1                  # 测试运行脚本
└── TEST_STRATEGY.md               # 测试策略文档
```

### 2.2 测试分层

| 层级 | 测试类型 | 测试范围 | 依赖 |
|------|----------|----------|------|
| 单元测试 | 功能验证 | 单个模块/函数 | Mock |
| 集成测试 | 交互验证 | 模块间交互 | 真实依赖 |
| 端到端测试 | 流程验证 | 完整用户流程 | 全系统 |

## 3. 测试框架设计

### 3.1 测试运行器 (test_runner.ahk)

**职责：**
- 注册和管理测试套件
- 按顺序执行测试
- 收集测试结果
- 生成测试报告

**接口：**
```autohotkey
class TestRunner {
    static suites := []           ; 测试套件列表
    static results := Map()       ; 测试结果
    static config := ""           ; 测试配置
    
    static RegisterSuite(suite)   ; 注册测试套件
    static RunAll()               ; 运行所有测试
    static RunSuite(name)         ; 运行指定套件
    static GenerateReport()       ; 生成报告
}
```

### 3.2 测试报告器 (test_reporter.ahk)

**职责：**
- 记录测试结果
- 提供断言方法
- 输出 JSON 格式报告

**接口：**
```autohotkey
class TestReporter {
    static currentSuite := ""
    static currentScenario := ""
    static passed := 0
    static failed := 0
    static errors := []
    
    static BeginSuite(name)       ; 开始测试套件
    static EndSuite()             ; 结束测试套件
    static Scenario(name)         ; 开始场景
    static Assert(condition, message)           ; 断言
    static AssertEqual(expected, actual, message) ; 相等断言
    static AssertThrows(fn, errorType, message)   ; 异常断言
    static OutputJSON()           ; 输出 JSON 报告
}
```

### 3.3 Mock 工厂 (mock_factory.ahk)

**职责：**
- 创建接口 Mock 对象
- 提供可配置的 Mock 行为

**接口：**
```autohotkey
class MockFactory {
    static CreateLoggerMock(config := "")    ; 创建 ILogger Mock
    static CreateNotifierMock(config := "")  ; 创建 INotifier Mock
    static CreateConfigStoreMock(config := "") ; 创建 IConfigStore Mock
    static CreateExecutorMock(config := "") ; 创建 IExecutor Mock
}
```

### 3.4 覆盖率收集器 (coverage_collector.ahk)

**职责：**
- 收集代码执行路径
- 计算覆盖率指标
- 生成覆盖率报告

**接口：**
```autohotkey
class CoverageCollector {
    static coveredLines := Map()
    static totalLines := Map()
    
    static Start()                ; 开始收集
    static Record(file, line)     ; 记录覆盖
    static Calculate()            ; 计算覆盖率
    static OutputReport()         ; 输出报告
}
```

## 4. 测试用例规范

### 4.1 单元测试规范

**文件结构：**
```autohotkey
; =================================================================
; 单元测试 - [模块名称]
; 测试目的: [描述测试目标]
; 前置条件: [描述测试前置条件]
; 预期结果: [描述预期结果]
; =================================================================

#Requires AutoHotkey v2.0
#Include "../framework/test_reporter.ahk"
#Include "../framework/mock_factory.ahk"
#Include "../../[模块路径]"

TestReporter.BeginSuite("test_xxx.ahk")

; 场景 1: [场景描述]
TestReporter.Scenario("场景 1: [场景名称]")
TestReporter.Assert(...)

; 场景 2: [场景描述]
TestReporter.Scenario("场景 2: [场景名称]")
TestReporter.Assert(...)

TestReporter.EndSuite()
```

**覆盖率要求：**
- 行覆盖率: 100%
- 分支覆盖率: 100%
- 函数覆盖率: 100%

### 4.2 集成测试规范

**文件结构：**
```autohotkey
; =================================================================
; 集成测试 - [场景名称]
; 测试目的: 验证 [模块A] 与 [模块B] 的交互正确性
; 测试范围: [描述测试覆盖的功能范围]
; 前置条件: [描述测试前置条件]
; 测试步骤: [描述测试步骤]
; 预期结果: [描述预期结果]
; =================================================================

#Requires AutoHotkey v2.0
#Include "../framework/test_reporter.ahk"
#Include "../../[模块A路径]"
#Include "../../[模块B路径]"

TestReporter.BeginSuite("test_integration_xxx.ahk")

; 步骤 1: 初始化测试环境
TestReporter.Scenario("步骤 1: 初始化测试环境")
; ...

; 步骤 2: 执行测试操作
TestReporter.Scenario("步骤 2: 执行测试操作")
; ...

; 步骤 3: 验证结果
TestReporter.Scenario("步骤 3: 验证结果")
; ...

TestReporter.EndSuite()
```

### 4.3 端到端测试规范

**测试内容：**
- 完整用户流程
- 系统行为验证
- 异常处理验证
- 性能指标验证

## 5. 测试执行流程

### 5.1 测试运行脚本

**参数：**
```powershell
param(
    [string]$Type = "all",        # all/unit/integration/e2e
    [string]$Layer = "",          # domain/infrastructure/application/presentation
    [switch]$Coverage,            # 是否收集覆盖率
    [switch]$Verbose              # 详细输出
)
```

**执行流程：**
1. 验证测试环境
2. 收集测试文件
3. 按依赖顺序执行测试
4. 收集覆盖率数据
5. 生成测试报告

### 5.2 测试执行顺序

```
1. 单元测试（按依赖顺序）
   ├── domain/           (无依赖)
   ├── infrastructure/   (依赖 domain)
   ├── application/      (依赖 domain, infrastructure)
   └── presentation/     (依赖 application)

2. 集成测试（按场景）
   ├── layer_interaction/
   ├── scenarios/
   └── e2e/

3. 覆盖率分析
   └── 生成覆盖率报告
```

### 5.3 测试报告格式

```json
{
  "timestamp": "2026-05-13T22:50:00",
  "duration": 12.5,
  "summary": {
    "total": 150,
    "passed": 148,
    "failed": 2,
    "skipped": 0
  },
  "coverage": {
    "lines": 100,
    "branches": 100,
    "functions": 100
  },
  "suites": [
    {
      "name": "test_skill_group.ahk",
      "passed": 25,
      "failed": 0,
      "scenarios": [...]
    }
  ],
  "errors": [...]
}
```

## 6. 质量标准

### 6.1 测试通过率标准

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 单元测试通过率 | 100% | 所有单元测试必须通过 |
| 集成测试通过率 | 100% | 所有集成测试必须通过 |
| 端到端测试通过率 | 100% | 所有端到端测试必须通过 |

### 6.2 覆盖率标准

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 行覆盖率 | 100% | 所有代码行必须被执行 |
| 分支覆盖率 | 100% | 所有分支必须被覆盖 |
| 函数覆盖率 | 100% | 所有函数必须被调用 |

### 6.3 缺陷管理标准

| 优先级 | 修复时限 | 说明 |
|--------|----------|------|
| 高优先级 | 立即修复 | 阻塞功能、数据丢失、安全漏洞 |
| 中优先级 | 24小时内 | 功能异常、性能问题 |
| 低优先级 | 7天内 | 界面问题、文档错误 |

### 6.4 测试文档标准

| 文档类型 | 要求 | 说明 |
|----------|------|------|
| 测试策略 | 完整、准确 | 描述测试方法、范围、标准 |
| 测试用例 | 中文编写 | 包含目的、前置条件、步骤、预期结果 |
| 测试报告 | JSON 格式 | 包含覆盖率、通过率、缺陷列表 |

## 7. 实施计划

### 7.1 阶段 1：测试框架重构（优先级：高）

**任务：**
1. 创建新的测试框架目录结构
2. 重构 test_runner.ahk
3. 重构 test_reporter.ahk
4. 实现 mock_factory.ahk
5. 实现 coverage_collector.ahk
6. 创建 run_tests.ps1

**验收标准：**
- 测试框架可正常运行
- JSON 报告正确生成
- Mock 对象可正确创建

### 7.2 阶段 2：单元测试迁移（优先级：高）

**任务：**
1. 迁移现有单元测试到新结构
2. 补充缺失的单元测试
3. 达到 100% 覆盖率

**验收标准：**
- 所有单元测试通过
- 覆盖率达到 100%

### 7.3 阶段 3：集成测试实施（优先级：中）

**任务：**
1. 创建层间交互测试
2. 创建业务场景测试
3. 创建端到端测试

**验收标准：**
- 所有集成测试通过
- 关键业务流程覆盖完整

### 7.4 阶段 4：测试文档完善（优先级：低）

**任务：**
1. 编写测试策略文档
2. 编写测试用例文档
3. 编写测试报告模板

**验收标准：**
- 文档完整、准确
- 符合团队文档标准

## 8. 风险评估

### 8.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| AutoHotkey 测试框架限制 | 中 | 使用 PowerShell 辅助 |
| 覆盖率收集困难 | 高 | 使用代码注入技术 |
| GUI 测试自动化困难 | 中 | 使用手动测试补充 |

### 8.2 进度风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 测试用例数量大 | 高 | 分阶段实施 |
| 依赖模块不稳定 | 中 | 使用 Mock 隔离 |

## 9. 附录

### 9.1 测试命令

```powershell
# 运行所有测试
.\tests\run_tests.ps1

# 运行单元测试
.\tests\run_tests.ps1 -Type unit

# 运行集成测试
.\tests\run_tests.ps1 -Type integration

# 运行指定层测试
.\tests\run_tests.ps1 -Type unit -Layer domain

# 收集覆盖率
.\tests\run_tests.ps1 -Coverage

# 详细输出
.\tests\run_tests.ps1 -Verbose
```

### 9.2 测试报告位置

- 最新报告: `tests/reports/latest.json`
- 历史报告: `tests/reports/history/`
- 覆盖率报告: `tests/reports/coverage/`
