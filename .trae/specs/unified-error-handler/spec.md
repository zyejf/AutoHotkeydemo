# 无弹窗错误处理系统 Spec

## Why

当前项目的错误处理机制存在以下问题：
1. **加载时错误**（语法错误）会显示弹窗，无法被 `OnError` 捕获
2. **运行时错误**虽然可以被 `OnError` 捕获，但部分情况下仍会显示弹窗
3. 错误日志分散在多个文件中，不便于统一管理

用户需要一个**完全无弹窗**的错误处理系统，同时能够完整捕获所有错误信息并记录到统一的日志文件。

## What Changes

- 创建统一的错误处理模块 `infrastructure/unified_error_handler.ahk`
- 创建 PowerShell 启动器 `run_silent.ps1`，用于捕获加载时错误
- 在 `main.ahk` 中添加 `#ErrorStdOut` 指令和统一的 `OnError` 回调
- 删除现有的 `error_captor.ahk` 和 `error_watchdog.ahk` 模块
- **BREAKING**: 移除 `ErrorCaptureMode` 类，使用新的统一错误处理接口

## Impact

- 受影响的规范：错误处理规范
- 受影响的代码：
  - `main.ahk` - 添加错误处理初始化
  - `infrastructure/error_captor.ahk` - 删除
  - `infrastructure/error_watchdog.ahk` - 删除
  - `infrastructure/unified_error_handler.ahk` - 新建
  - `run_silent.ps1` - 新建

## ADDED Requirements

### Requirement: 统一错误处理接口

系统 SHALL 提供统一的错误处理接口 `UnifiedErrorHandler`，支持：
- 捕获加载时错误（通过 `/ErrorStdOut` 参数）
- 捕获运行时错误（通过 `OnError` 回调）
- 完全抑制所有错误弹窗
- 将错误信息记录到统一的日志文件

#### Scenario: 加载时错误捕获

- **WHEN** 脚本存在语法错误
- **THEN** 错误信息被捕获并记录到 `logs/errors.log`
- **AND** 不显示任何错误弹窗

#### Scenario: 运行时错误捕获

- **WHEN** 脚本执行过程中发生运行时错误
- **THEN** 错误信息被捕获并记录到 `logs/errors.log`
- **AND** 不显示任何错误弹窗

### Requirement: PowerShell 启动器

系统 SHALL 提供 PowerShell 启动器 `run_silent.ps1`，用于：
- 使用 `/ErrorStdOut` 参数启动 AutoHotkey 脚本
- 捕获 stderr 输出并写入日志文件
- 提供友好的错误信息显示

#### Scenario: 使用启动器运行脚本

- **WHEN** 用户使用 `run_silent.ps1` 启动脚本
- **THEN** 加载时错误被捕获并显示在终端
- **AND** 错误信息被写入日志文件

### Requirement: 统一日志格式

系统 SHALL 使用统一的日志格式，包含以下字段：
- `timestamp` - 错误发生时间
- `type` - 错误类型（LoadTimeError / RuntimeError）
- `level` - 错误级别（ERROR / WARNING / INFO）
- `message` - 错误消息
- `file` - 错误发生的文件
- `line` - 错误发生的行号
- `stack` - 调用堆栈（运行时错误）

## MODIFIED Requirements

### Requirement: main.ahk 错误处理初始化

`main.ahk` SHALL 在启动时初始化统一错误处理系统：

```autohotkey
#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"  ; 加载时错误输出到 stderr

; 注册运行时错误处理
OnError(UnifiedErrorHandler.HandleError, -1)

; 初始化错误处理系统
UnifiedErrorHandler.Init()
```

## REMOVED Requirements

### Requirement: ErrorCaptureMode 类

**Reason**: 新的统一错误处理系统提供更简洁的接口

**Migration**: 使用 `UnifiedErrorHandler` 替代

### Requirement: OnErrorCaptor 和 DialogCaptor 类

**Reason**: 新的统一错误处理系统提供更完善的功能

**Migration**: 使用 `UnifiedErrorHandler` 替代

### Requirement: ErrorWatchdog 类

**Reason**: 新的错误处理系统通过 `/ErrorStdOut` 参数捕获所有错误，不再需要看门狗

**Migration**: 使用 PowerShell 启动器 `run_silent.ps1` 替代
