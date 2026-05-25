# 错误类 MsgBox 替换为 ErrorSystem.LogError 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标:** 扫描并替换项目中所有错误类 MsgBox 为 ErrorSystem.LogError 调用，保留用户确认类 MsgBox

**架构:** 采用分层扫描策略，按照 DDD 架构分层处理（domain → application → presentation → infrastructure → main.ahk），每个文件独立处理，确保替换准确性和可追溯性

**技术栈:** AutoHotkey v2.0, ErrorSystem 错误处理系统

---

## 文件结构

**需要扫描的文件（共 20 个）：**

### Domain 层（4 个文件）
- `d:\1demo\AutoHotkeydemo\domain\skill_manager.ahk`
- `d:\1demo\AutoHotkeydemo\domain\skill_group.ahk`
- `d:\1demo\AutoHotkeydemo\domain\mode_registry.ahk`
- `d:\1demo\AutoHotkeydemo\domain\interfaces.ahk`

### Application 层（2 个文件）
- `d:\1demo\AutoHotkeydemo\application\config_service.ahk`
- `d:\1demo\AutoHotkeydemo\application\group_service.ahk`

### Presentation 层（5 个文件）
- `d:\1demo\AutoHotkeydemo\presentation\gui_manager.ahk`
- `d:\1demo\AutoHotkeydemo\presentation\group_editor.ahk`
- `d:\1demo\AutoHotkeydemo\presentation\debug_panel.ahk`
- `d:\1demo\AutoHotkeydemo\presentation\backup_ui.ahk`
- `d:\1demo\AutoHotkeydemo\presentation\ui_manager.ahk`

### Infrastructure 层（10 个文件）
- `d:\1demo\AutoHotkeydemo\infrastructure\json_serializer.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\json_parser.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\json_logger.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\ipc_channel.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\error_handler.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\debug_logger.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\config_validator.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\config_store.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\backup_core.ahk`
- `d:\1demo\AutoHotkeydemo\infrastructure\error_system.ahk`（跳过，这是 ErrorSystem 本身）

### 主入口（1 个文件）
- `d:\1demo\AutoHotkeydemo\main.ahk`

---

## 识别规则

### 错误类 MsgBox（需要替换）
- 包含 `"Icon!"` 或 `"IconX"` 参数的 MsgBox
- 标题为 `"错误"` 的 MsgBox
- 显示错误信息的 MsgBox（如"加载失败"、"保存失败"、"无效"、"不存在"等）

**替换模式：**
```autohotkey
; 替换前
MsgBox("错误信息", "错误", "Icon!")

; 替换后
ErrorSystem.LogError("错误信息", "ERROR", A_ThisFunc, A_LineNumber)
```

### 用户确认类 MsgBox（保留）
- 包含 `"YesNo"` 或 `"OKCancel"` 参数的 MsgBox
- 标题为 `"确认"` 的 MsgBox
- 删除确认、保存确认、重置确认等

---

## Task 1: 扫描 domain 层文件

**文件:**
- 扫描: `d:\1demo\AutoHotkeydemo\domain\*.ahk`

- [ ] **Step 1: 扫描 domain/skill_manager.ahk**

使用 Grep 工具搜索 MsgBox 模式：
```bash
Grep -n "MsgBox" d:\1demo\AutoHotkeydemo\domain\skill_manager.ahk
```

预期：找到所有 MsgBox 调用

- [ ] **Step 2: 分析 skill_manager.ahk 中的 MsgBox**

读取文件内容，识别每个 MsgBox 的类型（错误类或确认类）

- [ ] **Step 3: 替换错误类 MsgBox**

如果发现错误类 MsgBox，使用 SearchReplace 工具替换：
```autohotkey
; 替换前
MsgBox("错误信息", "错误", "Icon!")

; 替换后
ErrorSystem.LogError("错误信息", "ERROR", A_ThisFunc, A_LineNumber)
```

- [ ] **Step 4: 验证替换**

运行语法检查：
```bash
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /ErrorStdOut d:\1demo\AutoHotkeydemo\domain\skill_manager.ahk
```

预期：无语法错误

- [ ] **Step 5: 重复步骤 1-4 处理其他 domain 文件**

处理文件：
- `domain/skill_group.ahk`
- `domain/mode_registry.ahk`
- `domain/interfaces.ahk`

---

## Task 2: 扫描 application 层文件

**文件:**
- 扫描: `d:\1demo\AutoHotkeydemo\application\*.ahk`

- [ ] **Step 1: 扫描 application/config_service.ahk**

使用 Grep 工具搜索 MsgBox 模式：
```bash
Grep -n "MsgBox" d:\1demo\AutoHotkeydemo\application\config_service.ahk
```

- [ ] **Step 2: 分析并替换 config_service.ahk 中的 MsgBox**

读取文件，识别并替换错误类 MsgBox

- [ ] **Step 3: 验证替换**

运行语法检查

- [ ] **Step 4: 处理 application/group_service.ahk**

重复步骤 1-3

---

## Task 3: 扫描 presentation 层文件

**文件:**
- 扫描: `d:\1demo\AutoHotkeydemo\presentation\*.ahk`

- [ ] **Step 1: 扫描 presentation/gui_manager.ahk**

使用 Grep 工具搜索 MsgBox 模式

- [ ] **Step 2: 分析并替换 gui_manager.ahk 中的 MsgBox**

特别注意保留用户确认类 MsgBox

- [ ] **Step 3: 验证替换**

运行语法检查

- [ ] **Step 4: 处理其他 presentation 文件**

处理文件：
- `presentation/group_editor.ahk`
- `presentation/debug_panel.ahk`
- `presentation/backup_ui.ahk`
- `presentation/ui_manager.ahk`

---

## Task 4: 扫描 infrastructure 层文件

**文件:**
- 扫描: `d:\1demo\AutoHotkeydemo\infrastructure\*.ahk`（排除 error_system.ahk）

- [ ] **Step 1: 扫描 infrastructure 层所有文件**

使用 Grep 工具批量搜索：
```bash
Grep -n "MsgBox" d:\1demo\AutoHotkeydemo\infrastructure\*.ahk
```

- [ ] **Step 2: 分析并替换每个文件中的 MsgBox**

逐个文件处理，识别并替换错误类 MsgBox

- [ ] **Step 3: 验证替换**

对每个修改的文件运行语法检查

---

## Task 5: 扫描 main.ahk

**文件:**
- 扫描: `d:\1demo\AutoHotkeydemo\main.ahk`

- [ ] **Step 1: 扫描 main.ahk**

使用 Grep 工具搜索 MsgBox 模式：
```bash
Grep -n "MsgBox" d:\1demo\AutoHotkeydemo\main.ahk
```

- [ ] **Step 2: 分析并替换 main.ahk 中的 MsgBox**

识别并替换错误类 MsgBox

- [ ] **Step 3: 验证替换**

运行语法检查

---

## Task 6: 生成替换报告

**文件:**
- 创建: `d:\1demo\AutoHotkeydemo\logs\msgbox_replacement_report.txt`

- [ ] **Step 1: 统计替换数量**

统计每个文件的替换数量

- [ ] **Step 2: 生成报告**

创建报告文件，包含：
- 扫描的文件列表
- 每个文件的替换数量
- 保留的 MsgBox 列表
- 总替换数量

- [ ] **Step 3: 输出报告**

使用 AskUserQuestion 工具向用户汇报结果

---

## 验证清单

- [ ] 所有错误类 MsgBox 已替换为 ErrorSystem.LogError
- [ ] 所有用户确认类 MsgBox 已保留
- [ ] 所有修改的文件通过语法检查
- [ ] 生成了完整的替换报告
- [ ] ErrorSystem 已正确初始化（在 main.ahk 中）

---

## 注意事项

1. **必须保留 ErrorSystem 的 #Include**：确保每个使用 ErrorSystem.LogError 的文件都能访问到 ErrorSystem 类
2. **A_ThisFunc 和 A_LineNumber**：使用这些内置变量自动记录错误位置
3. **错误级别**：根据错误严重程度选择 ERROR、WARNING 或 INFO
4. **不要替换测试文件**：只处理 domain、application、presentation、infrastructure 和 main.ahk
5. **保持代码格式**：替换时保持原有的缩进和格式
