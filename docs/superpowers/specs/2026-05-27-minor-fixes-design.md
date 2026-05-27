# 轻微项修复设计

**日期**: 2026-05-27  
**来源**: 第32-100轮全栈审查（4个轻微项）  
**状态**: 已批准

---

## M1 — 仪表盘空状态引导

**问题**: `renderDashboard()` 在无分组时显示空白区域，无引导提示。

**位置**: `presentation/app_ui.html` → `renderDashboard()` 函数

**改动**: 在 `for` 循环后、`container.innerHTML = html` 之前，添加空状态判断：

```javascript
if (filtered.length === 0) {
  html = '<div class="empty-state" style="text-align:center;padding:40px;color:var(--text-muted);">📭 暂无分组<br><small>点击"+ 添加新分组"开始</small></div>';
}
```

**验证**: 删除所有分组后刷新仪表盘，应显示"暂无分组"引导文字。

---

## M2 — 热重载完整测试

**问题**: `ConfigService.HotReload()` 缺少独立测试覆盖。

**位置**: 新建 `tests/test_hotreload.ahk`

**测试场景**（5个）:

| 场景 | 描述 | 验证点 |
|------|------|--------|
| A | 正常热重载 | 备份创建→紧急停止→配置替换→分组重新初始化→`HotReload()`返回true |
| B | 配置损坏回滚 | 写入无效JSON→`HotReload()`返回false→分组状态不变→回滚到备份 |
| C | 空分组热重载 | config无GroupSettings→warning通知→旧分组被清除 |
| D | 文件不存在 | 删除config.json→错误通知→`HotReload()`返回false |
| E | 分组状态恢复 | 热重载后分组active状态与config一致 |

**测试模式**: 遵循现有测试惯例
- `TestReporter.BeginTest("test_hotreload.ahk")`
- `LoadTestDependencies()` 依赖注入
- `TestReporter.Scenario("描述")`
- `TestReporter.AssertEqual/AssertTrue/AssertThrows`

**验证**: 运行 `run_all_tests.ahk`，新增用例全部通过。

---

## M3 — 删除OCR相关文件

**问题**: `ocr.ahk` 含2处TODO标记，OCR功能未实际接入（使用mock回退），且依赖链无生产代码引用。

**删除文件**:
1. `ocr.ahk` — OCR封装（mock实现）
2. `equipment_recognizer.ahk` — 依赖ocr.ahk
3. `joystick_tester.ahk` — 依赖equipment_recognizer.ahk

**依赖检查结果**: 三文件互依赖（`joystick_tester.ahk` → `equipment_recognizer.ahk` → `ocr.ahk`），无其他生产代码引用。

**验证**: 全量测试套件运行无回归。

---

## M4 — 无障碍属性补充

**问题**: 多数 `<button>` 元素缺少 `aria-label` 属性。

**位置**: `presentation/app_ui.html`

**改动**: 为以下按钮添加 `aria-label`：

| 按钮 | aria-label |
|------|-----------|
| 全局开关 | "切换所有分组的启用状态" |
| 热重载 | "重新加载配置文件" |
| 批量启动 | "批量启动选中的分组" |
| 批量停止 | "批量停止选中的分组" |
| 批量删除 | "批量删除选中的分组" |
| 退出多选 | "退出多选模式" |
| 添加新分组 | "创建新技能分组" |
| 多选模式 | "切换到多选模式" |
| 导出全部 | "导出所有分组配置" |
| 导入 | "从文件导入分组配置" |
| 模板按钮(6个) | "使用{模式名}模板创建分组" |
| 撤销 | "撤销编辑操作" |
| 重做 | "重做编辑操作" |
| 取消 | "取消编辑返回仪表盘" |
| 保存分组 | "保存当前分组配置" |

**验证**: 使用浏览器无障碍检查工具确认所有按钮有描述性标签。

---

## 实施顺序

1. M3（删除文件）— 无依赖，可独立执行
2. M1（空状态）— 前端改动，依赖M3不涉及
3. M4（aria-label）— 前端改动，与M1同文件
4. M2（测试）— 新增测试文件，依赖现有基础设施