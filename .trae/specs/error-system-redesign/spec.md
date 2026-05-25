# 无弹窗错误处理系统重构 Spec

## Why

现有的错误处理系统虽然已经实现了基本功能，但存在以下问题：
1. 架构不够清晰，代码分散在多个位置
2. 缺少错误级别分类功能
3. 日志格式不够完善
4. 需要更全面的错误类型支持

用户需要一个**重新设计**的无弹窗错误处理系统，具备完整的错误捕获、分级和日志记录功能。

## What Changes

- 删除现有的 `infrastructure/unified_error_handler.ahk`
- 创建新的单一模块 `infrastructure/error_system.ahk`
- 重新设计 PowerShell 启动器 `run_silent.ps1`
- 修改 `main.ahk` 使用新的错误处理系统
- 创建全面的测试脚本 `tests/test_error_system.ahk`
- **BREAKING**: 移除 `UnifiedErrorHandler` 类，使用新的 `ErrorSystem` 类

## Impact

- 受影响的规范：错误处理规范
- 受影响的代码：
  - `main.ahk` - 更新错误处理初始化
  - `infrastructure/unified_error_handler.ahk` - 删除
  - `infrastructure/error_system.ahk` - 新建
  - `run_silent.ps1` - 重写
  - `tests/test_error_system.ahk` - 新建

## ADDED Requirements

### Requirement: 单一错误处理模块

系统 SHALL 提供单一错误处理模块 `ErrorSystem`，支持：
- 捕获加载时错误（通过 `/ErrorStdOut` 参数）
- 捕获运行时错误（通过 `OnError` 回调）
- 捕获未捕获的错误
- 完全抑制所有错误弹窗
- 将错误信息记录到文件日志

#### Scenario: 加载时错误捕获

- **WHEN** 脚本存在语法错误
- **THEN** 错误信息被捕获并记录到 `logs/errors.log`
- **AND** 不显示任何错误弹窗

#### Scenario: 运行时错误捕获

- **WHEN** 脚本执行过程中发生运行时错误
- **THEN** 错误信息被捕获并记录到 `logs/errors.log`
- **AND** 不显示任何错误弹窗

### Requirement: 错误级别分类

系统 SHALL 支持错误级别分类：
- `CRITICAL` - 关键错误，程序无法继续运行
- `ERROR` - 普通错误，功能无法完成
- `WARNING` - 警告，可能影响功能
- `INFO` - 信息，不影响功能

#### Scenario: 错误级别识别

- **WHEN** 错误发生时
- **THEN** 系统自动识别错误级别
- **AND** 在日志中记录正确的级别

### Requirement: 结构化日志格式

系统 SHALL 使用 JSON Lines 格式记录日志，包含以下字段：
- `timestamp` - 错误发生时间（ISO 8601 格式）
- `level` - 错误级别（CRITICAL/ERROR/WARNING/INFO）
- `type` - 错误类型（LoadTimeError/RuntimeError/UncaughtError）
- `errorType` - 具体错误类型（ZeroDivisionError、OSError 等）
- `message` - 错误消息
- `file` - 错误发生的文件
- `line` - 错误发生的行号
- `stack` - 调用堆栈（运行时错误）
- `mode` - 错误模式（Return/Exit/ExitApp）

#### Scenario: 日志格式验证

- **WHEN** 错误被记录
- **THEN** 日志格式为有效的 JSON
- **AND** 包含所有必需字段

### Requirement: PowerShell 启动器

系统 SHALL 提供 PowerShell 启动器 `run_silent.ps1`，用于：
- 使用 `/ErrorStdOut` 参数启动 AutoHotkey 脚本
- 捕获 stderr 输出并写入日志文件
- 提供友好的错误信息显示
- 支持配置日志文件路径

#### Scenario: 使用启动器运行脚本

- **WHEN** 用户使用 `run_silent.ps1` 启动脚本
- **THEN** 加载时错误被捕获并显示在终端
- **AND** 错误信息被写入日志文件

### Requirement: 全面测试脚本

系统 SHALL 提供全面测试脚本 `tests/test_error_system.ahk`，测试：
- 加载时错误捕获
- 运行时错误捕获（多种错误类型）
- 未捕获错误处理
- 错误级别识别
- 日志格式验证
- 无弹窗验证

#### Scenario: 测试所有错误类型

- **WHEN** 运行测试脚本
- **THEN** 所有错误类型都被正确捕获
- **AND** 日志文件包含完整的错误信息
- **AND** 没有任何错误弹窗

## MODIFIED Requirements

### Requirement: main.ahk 错误处理初始化

`main.ahk` SHALL 在启动时初始化错误处理系统：

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"  ; 加载时错误输出到 stderr

; 注册运行时错误处理
OnError(ErrorSystem_HandleError, -1)

; 初始化错误处理系统
ErrorSystem.Init()
```

## REMOVED Requirements

### Requirement: UnifiedErrorHandler 类

**Reason**: 新的错误处理系统使用更简洁的单一模块设计

**Migration**: 使用 `ErrorSystem` 替代

### Requirement: UnifiedErrorHandler_Callback 函数

**Reason**: 新的错误处理系统使用更简洁的命名

**Migration**: 使用 `ErrorSystem_HandleError` 替代
