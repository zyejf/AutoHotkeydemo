# 功能缺失全面修复设计

日期: 2026-05-22
范围: 25项功能缺失（5严重/11中等/9轻微）

## 1. 严重问题修复

### 1.1 验证功能支持 hold/hybrid/enhanced_hybrid 模式
- **文件**: `domain/key_validator.ahk` `_LoadExpectedSequence`, `presentation/webview2_manager.ahk` `_BridgeGetGroupDetail`, `presentation/app_ui.html` `startValidation`
- **方案**: 
  - `_LoadExpectedSequence` 增加 hybrid 模式：遍历 `groups` 子组，将每个子组的按键展开为预期序列，子组间用 `seqInterval` 间隔
  - `_BridgeGetGroupDetail` 返回 `groups` 子组结构数据
  - 前端 `startValidation` 处理 `detail.groups`，为每个子组生成独立的预期事件序列
  - hold 模式：将 holdKeys 作为持续按住事件，预期序列只有 down 事件（无 up）

### 1.2 验证报告增加 hold timing 详情
- **文件**: `domain/key_validator.ahk` `_BuildReport`
- **方案**: 在 `_BuildReport` 中收集 `holdDetails` 数组：
  ```
  holdDetails: [{key, downTs, upTs, holdDuration, valid}]
  ```
  每个键的 down/up 配对，记录实际 hold 时长和是否在 5-200ms 范围内

### 1.3 删除分组添加确认对话框
- **文件**: `presentation/app_ui.html` `deleteGroup`
- **方案**: 使用 overlay 模式（类似 `showImportDialog`），显示"确定删除分组 XXX？此操作不可撤销"，确认后执行

### 1.4 保存分组时热键冲突检测
- **文件**: `presentation/app_ui.html` `saveConfig`
- **方案**: 保存前遍历 `sampleGroups`，检查是否有其他分组使用相同热键（排除当前编辑的分组），冲突时 toast 提示

### 1.5 导出面板 keyPressDuration max 值修正
- **文件**: `presentation/app_ui.html` L409
- **方案**: `max="500"` → `max="100"`

## 2. 中等问题修复

### 2.1 鼠标事件记录 down/up
- **文件**: `domain/key_recorder.ahk` `_InstallMouseHooks`, `_MakeHotkeyHandler`
- **方案**: 
  - 注册 `~LButton` (down) 和 `~LButton Up` (up) 两个热键
  - `_MakeHotkeyHandler(btn, event)` 返回对应事件的处理器
  - Wheel 事件保持 "click" 不变（无 down/up 概念）

### 2.2 录制器支持暂停/继续
- **文件**: `domain/key_recorder.ahk`, `presentation/app_ui.html`
- **方案**: 
  - 添加 `Pause()`/`Resume()` 方法
  - Pause 时停止 InputHook 和鼠标热键，但保留 `_events` 和 `_startTime`
  - Resume 时重新启动 InputHook 和鼠标热键
  - 前端添加"暂停/继续"按钮

### 2.3 录制/验证事件上限保护
- **文件**: `domain/key_recorder.ahk`, `domain/key_validator.ahk`
- **方案**: 
  - 添加 `MAX_EVENTS := 10000` 常量
  - `OnKey`/`OnMouse`/`OnSend` 中检查事件数，超限自动停止并通知

### 2.4 录制后可编辑/删除按键
- **文件**: `presentation/app_ui.html` 录制面板
- **方案**: 
  - 事件列表每项添加删除按钮（×）
  - 点击删除时从 `_recEvents` 中移除，重绘时间线和统计

### 2.5 录制导出增加 hold 模式
- **文件**: `presentation/app_ui.html` 导出模式下拉, `domain/key_recorder.ahk` `ExportAsGroupConfig`
- **方案**: 
  - 下拉框添加"长按"选项
  - `ExportAsGroupConfig` 增加 hold 模式：所有按键作为 holdKeys，holdDuration=0

### 2.6 分组增加 name 字段
- **文件**: `domain/skill_group.ahk`, `infrastructure/config_validator.ahk`, `presentation/webview2_manager.ahk`, `presentation/app_ui.html`
- **方案**: 
  - SkillGroup 添加 `name` 属性，默认等于 id
  - 配置验证器允许 `name` 字段
  - `_BridgeGetGroupList` 返回 name
  - 仪表盘卡片显示 name
  - 编辑器添加名称输入框

### 2.7 验证历史记录
- **文件**: `presentation/app_ui.html` 验证面板
- **方案**: 
  - 添加 `_valHistory` 数组，保存最近 10 次验证报告
  - 添加历史下拉选择，切换查看不同次验证结果
  - 添加"对比上次"按钮，显示两次验证的关键指标差异

### 2.8 备份恢复确认对话框
- **文件**: `presentation/app_ui.html` `restoreBackup`
- **方案**: 使用 overlay 确认对话框，提示"恢复将覆盖当前所有配置，确定继续？"

### 2.9 hold 图表增强
- **文件**: `presentation/app_ui.html` `_renderHold`
- **方案**: 
  - 改为柱状图，X 轴为按键名，Y 轴为 hold 时长
  - 绿色区域表示有效范围（5-200ms），红色柱表示超出范围
  - 使用 `report.holdDetails` 数据

### 2.10 编辑器撤销/重做
- **文件**: `presentation/app_ui.html` 编辑器
- **方案**: 
  - 维护 `_undoStack` 和 `_redoStack`
  - 每次编辑操作前 push `editorConfig` 快照
  - Ctrl+Z 撤销，Ctrl+Y 重做
  - 栈深度限制 50

### 2.11 调试日志面板修复
- **文件**: `presentation/app_ui.html` `toggleAutoScroll`, `addLog`
- **方案**: 
  - `toggleAutoScroll` 切换 `_autoScroll` 状态变量
  - `addLog` 根据 `_autoScroll` 决定是否自动滚动
  - 错误计数从后端 `GetDebugInfo` 获取

## 3. 轻微问题修复

### 3.1 分组卡片拖拽排序
- **方案**: 使用 HTML5 Drag and Drop API，拖拽后更新 `sampleGroups` 顺序并通知后端保存

### 3.2 分组复制/克隆
- **方案**: 仪表盘添加"复制"按钮，基于当前分组配置创建新分组（ID 加后缀 _copy）

### 3.3 分组配置导出/导入 JSON
- **方案**: 仪表盘添加"导出"按钮下载 JSON，设置页添加"导入配置"按钮上传 JSON

### 3.4 键盘快捷键
- **方案**: 全局 keydown 监听，Ctrl+S 保存、Ctrl+N 新建、Esc 关闭弹窗

### 3.5 关于/版本信息
- **方案**: 导航栏添加"关于"页面，显示版本号和基本信息

### 3.6 无障碍访问
- **方案**: 关键交互元素添加 `aria-label`、`role="button"`、`tabindex`

### 3.7 录制清除按钮
- **方案**: 录制面板添加"清除"按钮，清空 `_recEvents`、时间线和统计

### 3.8 验证实时统计准确性
- **方案**: `updateValLiveStats` 使用与 `_BuildReport` 一致的 down-up 配对逻辑

### 3.9 编辑器间隔上限
- **方案**: 间隔输入框添加 `max="60000"`，JS 验证不超过 60000ms

## 实施顺序

按依赖关系和优先级分 8 批次：

1. **批次1 - 快速修复**: #5 max值修正、#3 删除确认、#8 备份恢复确认、#3.7 录制清除按钮、#3.9 间隔上限
2. **批次2 - 数据层增强**: #2 hold详情数据、#6 name字段、#3 事件上限保护
3. **批次3 - 验证核心增强**: #1 hold/hybrid验证支持、#9 hold图表增强、#3.8 实时统计准确性
4. **批次4 - 录制增强**: #1 鼠标down/up、#2 暂停/继续、#4 编辑录制、#5 导出hold模式
5. **批次5 - 保存流程**: #4 热键冲突检测、#0 编辑器撤销重做
6. **批次6 - 验证体验**: #7 验证历史记录
7. **批次7 - 仪表盘增强**: #1 分组复制、#3 配置导出导入、#1 拖拽排序
8. **批次8 - 体验优化**: #4 键盘快捷键、#5 关于页面、#6 无障碍、#1 调试面板修复
