# 缺失功能全面实施设计

**Goal:** 实施13项缺失功能，覆盖数据层增强、桥接层增强、UI体验增强、高级功能

**Architecture:** 分4批次按依赖顺序实施，数据层优先于桥接层，桥接层优先于UI层

**Tech Stack:** AutoHotkey v2, HTML/CSS/JavaScript (WebView2)

---

## 批次1: 数据层增强（3项）

### 1.1 增量更新机制

**问题:** `_PushStateUpdate`每2秒全量推送所有分组数据，无论数据是否变化

**方案:**
- 后端添加`_stateSnapshot`缓存上次推送的完整状态JSON字符串
- `_PushStateUpdate`中先序列化当前状态，与快照比较（字符串哈希对比），相同则跳过推送
- 变化时推送完整状态（保持前端兼容），但跳过无变化的推送周期
- 添加`_dirtyGroups`集合，分组状态变化时标记脏
- 推送后清除脏标记并更新快照
- 后续优化：可扩展为仅推送脏分组的差异JSON

**文件:**
- Modify: `presentation/webview2_manager.ahk` — 添加脏标记和增量推送逻辑
- Modify: `presentation/app_ui.html` — 前端接收增量更新并局部刷新

### 1.2 配置导入/导出UI

**问题:** 后端已有ImportConfigFromFile/ExportConfigToFile，但前端无UI入口

**方案:**
- 在设置页面添加"导入配置"和"导出配置"按钮
- 导入：文件选择对话框→读取JSON→验证→确认覆盖→应用
- 导出：序列化当前配置→保存为JSON文件
- 导入前自动创建备份
- 支持拖拽导入JSON文件

**文件:**
- Modify: `presentation/app_ui.html` — 添加导入/导出UI和逻辑
- Modify: `presentation/webview2_manager.ahk` — 添加Bridge方法

### 1.3 配置版本迁移日志

**问题:** 配置版本迁移时无详细日志，难以排查迁移问题

**方案:**
- 在ConfigService.MigrateConfig中记录每个迁移步骤的变更
- 迁移日志保存到`migrations.log`
- 包含：源版本、目标版本、迁移字段、变更前后值
- 前端设置页面可查看迁移历史

**文件:**
- Modify: `application/config_service.ahk` — 添加迁移日志记录
- Add: `infrastructure/migration_logger.ahk` — 迁移日志专用记录器

---

## 批次2: 桥接层增强（4项）

### 2.1 分组搜索/过滤

**问题:** 分组数量多时无法快速定位

**方案:**
- 仪表盘顶部添加搜索框
- 支持按名称、热键、模式过滤
- 实时过滤，输入即搜索
- 后端添加BridgeSearchGroups方法（可选，前端过滤即可）

**文件:**
- Modify: `presentation/app_ui.html` — 添加搜索框和过滤逻辑

### 2.2 批量操作

**问题:** 无法批量启用/禁用/删除分组

**方案:**
- 仪表盘添加多选模式（复选框）
- 批量操作工具栏：启用、禁用、删除
- 后端添加BridgeBatchToggleGroups和BridgeBatchDeleteGroups
- 操作前确认对话框

**文件:**
- Modify: `presentation/app_ui.html` — 添加多选UI和批量操作
- Modify: `presentation/webview2_manager.ahk` — 添加批量Bridge方法
- Modify: `domain/skill_manager.ahk` — 添加批量操作方法

### 2.3 性能监控面板

**问题:** 无法实时查看系统性能指标

**方案:**
- 新增"性能"标签页
- 展示：CPU使用率（近似）、内存占用、定时器数量、按键发送频率
- 使用Canvas绘制实时折线图
- 数据来源：_BridgeGetDebugInfo扩展+新增BridgeGetPerformanceMetrics

**文件:**
- Modify: `presentation/app_ui.html` — 添加性能面板UI
- Modify: `presentation/webview2_manager.ahk` — 扩展DebugInfo和新增Metrics

### 2.4 配置差异比较工具

**问题:** 无法对比两个配置版本的差异

**方案:**
- 备份列表中添加"对比"按钮
- 选择两个备份进行差异比较
- 差异以高亮方式展示：新增（绿色）、删除（红色）、修改（黄色）
- 支持当前配置与任意备份对比

**文件:**
- Modify: `presentation/app_ui.html` — 添加差异比较UI
- Modify: `presentation/webview2_manager.ahk` — 添加BridgeDiffConfigs方法
- Add: `infrastructure/config_differ.ahk` — 配置差异计算器

---

## 批次3: UI体验增强（4项）

### 3.1 主题切换

**问题:** 仅支持暗色主题，无亮色选项

**方案:**
- 定义CSS变量集：暗色主题和亮色主题
- 设置页面添加主题切换开关
- 主题偏好保存到localStorage和配置文件
- 切换时平滑过渡（CSS transition）

**文件:**
- Modify: `presentation/app_ui.html` — 添加主题变量和切换逻辑

### 3.2 设置页面热键格式验证

**问题:** 设置页面中热键输入无格式验证，可能输入无效热键

**方案:**
- 输入框添加实时验证
- 验证规则：AHK热键格式（^!+前缀+键名）
- 无效时显示红色边框和错误提示
- 保存前统一验证所有热键

**文件:**
- Modify: `presentation/app_ui.html` — 添加热键验证逻辑

### 3.3 键盘快捷键自定义UI

**问题:** 控制热键（紧急停止、全局开关等）无法在UI中自定义

**方案:**
- 设置页面添加"快捷键"区域
- 每个控制操作一行：操作名+当前快捷键+修改按钮
- 修改时使用热键捕获（复用captureHotkey逻辑）
- 保存时验证热键冲突

**文件:**
- Modify: `presentation/app_ui.html` — 添加快捷键自定义UI

### 3.4 分组模板/预设

**问题:** 新建分组时需从零配置，常用配置无法复用

**方案:**
- 新建分组时显示模板选择
- 内置模板：周期性单键、序列连招、混合模式、纯长按
- 支持保存当前分组为自定义模板
- 模板存储在localStorage

**文件:**
- Modify: `presentation/app_ui.html` — 添加模板选择UI和模板管理

---

## 批次4: 高级功能（2项）

### 4.1 响应式设计

**问题:** 界面在小窗口下布局混乱

**方案:**
- CSS媒体查询适配不同窗口尺寸
- 小窗口：侧边栏折叠为汉堡菜单、卡片单列布局
- 中等窗口：双列布局
- 大窗口：三列布局+侧边详情面板
- 最小宽度支持640px

**文件:**
- Modify: `presentation/app_ui.html` — 添加响应式CSS和布局调整

### 4.2 多语言支持

**问题:** 界面文案硬编码中文，无法切换语言

**方案:**
- 定义i18n字典对象：zh-CN和en-US
- 所有界面文案通过i18n函数获取
- 设置页面添加语言选择
- 语言偏好保存到localStorage
- 默认跟随系统语言

**文件:**
- Modify: `presentation/app_ui.html` — 添加i18n框架和翻译
- Add: `presentation/i18n/zh-CN.json` — 中文翻译
- Add: `presentation/i18n/en-US.json` — 英文翻译

---

## 跨批次关注点

### 数据一致性
- 所有修改操作必须通过ConfigService，确保验证和备份
- 增量更新不能遗漏状态变化
- 批量操作需要原子性（全部成功或全部回滚）

### 性能
- 增量推送减少WebView2通信开销
- 搜索过滤在前端执行，避免频繁后端调用
- 性能监控面板使用requestAnimationFrame节流

### 可扩展性
- 主题系统使用CSS变量，便于添加新主题
- i18n使用字典模式，便于添加新语言
- 模板系统支持自定义模板，便于扩展

### 向后兼容
- 新增功能不影响现有配置文件格式
- 迁移日志记录版本变更
- 默认值确保新功能开箱即用
