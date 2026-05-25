# 全项目集成错误处理系统 Spec

## Why

当前错误处理系统 `ErrorSystem` 已实现核心功能，但仅集成到 `main.ahk`。需要将错误处理能力扩展到整个项目的所有模块，确保：
- 所有模块都有全局错误捕获
- 错误日志统一管理
- 保留现有日志系统（JSONLogger、DebugLogger）用于不同场景
- 保留用户确认类弹窗，移除错误提示弹窗

## What Changes

- 所有模块添加 try-catch 错误捕获
- 错误类 MsgBox 改用 ErrorSystem.LogError 记录
- 保留用户确认类 MsgBox（如删除确认）
- 保留现有 JSONLogger（用于技能执行日志）、DebugLogger（用于调试日志）
- ErrorSystem 专门用于错误日志记录

## Impact

- 受影响的规范：错误处理规范
- 受影响的代码：
  - `domain/` - 所有领域层模块
  - `application/` - 所有应用层模块
  - `presentation/` - 所有表现层模块
  - `infrastructure/` - 部分基础设施模块

## ADDED Requirements

### Requirement: 领域层错误捕获

所有领域层模块 SHALL 集成错误处理：

- `domain/interfaces.ahk` - 接口定义模块
- `domain/mode_registry.ahk` - 模式注册模块
- `domain/skill_group.ahk` - 技能组模块
- `domain/skill_manager.ahk` - 技能管理器模块

#### Scenario: 领域层错误捕获

- **WHEN** 领域层方法执行发生错误
- **THEN** 错误被 try-catch 捕获
- **AND** 错误信息记录到 ErrorSystem
- **AND** 不显示错误弹窗

### Requirement: 应用层错误捕获

所有应用层模块 SHALL 集成错误处理：

- `application/group_service.ahk` - 分组服务模块
- `application/config_service.ahk` - 配置服务模块

#### Scenario: 应用层错误捕获

- **WHEN** 应用层方法执行发生错误
- **THEN** 错误被 try-catch 捕获
- **AND** 错误信息记录到 ErrorSystem
- **AND** 不显示错误弹窗

### Requirement: 表现层错误捕获

所有表现层模块 SHALL 集成错误处理：

- `presentation/ui_manager.ahk` - UI 管理器模块
- `presentation/backup_ui.ahk` - 备份 UI 模块
- `presentation/debug_panel.ahk` - 调试面板模块
- `presentation/group_editor.ahk` - 分组编辑器模块
- `presentation/gui_manager.ahk` - GUI 管理器模块

#### Scenario: 表现层错误捕获

- **WHEN** 表现层方法执行发生错误
- **THEN** 错误被 try-catch 捕获
- **AND** 错误信息记录到 ErrorSystem
- **AND** 不显示错误弹窗（用户确认弹窗除外）

### Requirement: 错误类 MsgBox 替换

所有错误提示类 MsgBox SHALL 替换为 ErrorSystem.LogError：

- 移除 `MsgBox("错误信息", "错误", "Icon!")` 形式的弹窗
- 改用 `ErrorSystem.LogError("错误信息")` 记录

#### Scenario: 错误类 MsgBox 替换

- **WHEN** 发现错误提示类 MsgBox
- **THEN** 替换为 ErrorSystem.LogError 调用
- **AND** 保留用户确认类 MsgBox（如删除确认）

### Requirement: 用户确认弹窗保留

用户确认类 MsgBox SHALL 保留：

- 删除确认弹窗
- 保存确认弹窗
- 重置确认弹窗
- 其他需要用户交互的弹窗

#### Scenario: 用户确认弹窗保留

- **WHEN** 发现用户确认类 MsgBox
- **THEN** 保留该 MsgBox
- **AND** 不做任何修改

## MODIFIED Requirements

### Requirement: 日志系统职责分工

日志系统 SHALL 按职责分工：

| 日志系统 | 用途 | 日志文件 |
|---------|------|---------|
| ErrorSystem | 错误日志 | `logs/errors.log` |
| JSONLogger | 技能执行日志 | `logs/app.log` |
| DebugLogger | 调试日志 | `logs/debug.log` |

## REMOVED Requirements

无移除的需求。
