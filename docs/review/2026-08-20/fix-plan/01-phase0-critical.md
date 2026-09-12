# Phase 0 紧急修复方案（P0 — Critical）

> **性质**：只读规划文档，仅描述修复步骤，未修改任何 .ahk / .rs / .toml / .json 源码文件
> **来源**：`docs/review/2026-08-20/fix-plan/00-issue-inventory.md` + `docs/code-review-report-2026-08-20.md` §4
> **覆盖范围**：3 项 Critical（CR1 / CR2 / CR3）
> **生效基线**：`main` 分支 `3af1053` + 工作区 4 个未提交文件（详见 CR1 处置预案）
> **硬性前置**：CR1 的「工作区 4 个未提交文件处置预案」必须在所有其他修复（含 CR2/CR3）之前完成

---

## 0. 总览与执行顺序

| 编号 | 标题 | 维度 | 阻塞性 | 优先级 | 时间框 |
|------|------|------|--------|--------|--------|
| CR1 | 工作区半回退不一致状态（`ConfigIO`/`BackupService` 未接入生产入口） | 架构设计 | 🔴 阻塞运行（运行时 `Unknown class` 崩溃） | P0-最高 | T+0（立即，下次运行前） |
| CR2 | 执行器每键 down/up 无条件 IPC 序列化 + 同步阻塞写命名管道 | 性能优化 | 🟠 热路径性能/反向冻结风险（非立即崩溃） | P0 | T+0~T+1 |
| CR3 | `docs/developer-guide.md` 整篇基于已废弃单 crate 结构 | 文档完整性 | 🟡 误导开发者（无运行风险） | P0 | T+0~T+1 |

**执行顺序（强制）**：

1. **CR1 处置预案**（唯一硬性前置，必须先于一切改动执行）
2. CR1 主体修复（4 个原子提交）
3. CR2（可与 CR1 后的验证并行推进，但不可与 CR1 的源码改动交叉混入同一提交）
4. CR3（纯文档，与 CR1/CR2 无源码依赖，可与 CR2 并行）

> **原子提交约定**：下述每个「修复步骤」对应一个独立 `git commit`，采用 Conventional Commits 规范（`fix(asd-tauri): ...` / `fix(ahk): ...` / `docs: ...`），便于逐条 `git revert` 回滚。禁止将 CR1 与 CR2 的改动合并到同一提交。

---

## 1. CR1 ｜ 工作区半回退不一致状态：`ConfigIO`/`BackupService` 未接入生产入口，配置读写核心路径运行时崩溃

> 来源编号：T2-01 + T2-02（归并，对应基线 I1/I6 引入回归）

### 1.1 问题描述（复述报告要点）

I6 重构将配置读写下沉到 `infrastructure/config_io.ahk` 的 `ConfigIO` 类，`application/config_service.ahk:412-417` 通过全局函数 `ImportConfigFromFile`/`ExportConfigToFile` 委托 `ConfigIO.LoadFromFile/ExportToFile`，表现层已改为调用 `application/backup_service.ahk` 的 `BackupService.*`（I1 修复）。但当前工作区存在 4 个未提交文件，其中：

- `main.ahk` 删除了 `#Include "infrastructure\config_io.ahk"` 与 `#Include "application\backup_service.ahk"` 两行，并将 OnExit 从 `(JoyHotkeyManager.Shutdown(), SkillManager.OnExit())` 回退为 `SkillManager.OnExit()`；
- `infrastructure/backup_core.ahk:70` 从 `ConfigIO.ExportToFile(...)` 回退为调用应用层 `ExportConfigToFile(...)`（反向依赖未消除）。

由于 AHK 的 `#Include` 不会自动解析全局类名，`ConfigIO`/`BackupService` 在生产环境**从未被定义**，任何一次配置读写/备份导出都会抛 `Unknown class: ConfigIO` / `Unknown class: BackupService`。单测 `tests/suites/layering_security_suites.ahk` 因单独 `#Include` 拉入 `config_io.ahk` 而掩盖了生产入口缺 include 的问题。

### 1.2 影响范围评估

- **受影响模块**：
  - `main.ahk`（第 21-58 行 include 段、第 115/130 行 OnExit）
  - `application/config_service.ahk`（:36 加载、:106/:376 保存、:412-417 全局包装）
  - `infrastructure/config_io.ahk`（:21 `ConfigIO` 类，从未被生产入口引入）
  - `infrastructure/backup_core.ahk`（:70 反向依赖）
  - `application/backup_service.ahk`（从未被生产入口引入）
- **受影响功能/用户路径**（均触发 `Unknown class` 崩溃）：
  - 配置加载：`config_service.ahk:36` → `ImportConfigFromFile` → `ConfigIO.LoadFromFile`
  - 配置保存：`config_service.ahk:106` / `:376` → `ExportConfigToFile` → `ConfigIO.ExportToFile`
  - 分组增删改：`group_service.ahk:227/236`
  - GUI 全局设置保存：`gui_manager.ahk:212`
  - 备份导出/恢复：`backup_core.ahk:70`（`restoreBackup` 双重失效）+ 表现层 `BackupService.*` 调用
- **触发场景**：主程序启动即触发 `LoadConfig()`；用户任何一次「保存/导入/导出/恢复备份」操作。
- **连带**：OnExit 缺失 `JoyHotkeyManager.Shutdown()`，退出时摇杆热键管理器钩子未清理。

### 1.3 根本原因分析（引用报告 + 因果链）

- **报告根因**：I6 重构只做了一半（新增 `ConfigIO` + 保留应用层全局包装），又叠加工作区对 `main.ahk`/`backup_core.ahk` 的未提交回退，形成半回退状态。
- **因果链**：
  1. 历史 I1/I6 修复已提交（`ConfigIO`/`BackupService` 类定义 + 表现层/应用层改调均落地）；
  2. 工作区未提交变更将两者 `#Include` 从 `main.ahk` 入口删除（`git diff` 确认：`main.ahk` 删除 2 行 include + OnExit 回退）；
  3. `backup_core.ahk` 未提交回退 `:70` 为 `ExportConfigToFile(...)`，并删除 `#Include "config_io.ahk"` / `#Include "utils.ahk"`；
  4. 结果：生产入口缺 include → `ConfigIO`/`BackupService` 未定义 + 反向依赖回归；
  5. 单测 `layering_security_suites.ahk` 因自行 include 掩盖问题，且未提交的 `tests/run_all_tests.ahk` 删除了 `BackupServiceLayeringTests`/`ConfigIOLayeringTests` 的注册，进一步让分层断言退出运行视线。

**工作区 4 个未提交文件的 diff 实测（`git diff` 确认）**：

| 文件 | 未提交改动性质 |
|------|----------------|
| `main.ahk` | 删除 `#Include "infrastructure\config_io.ahk"` + `#Include "application\backup_service.ahk"`；OnExit 回退为仅 `SkillManager.OnExit()`（撤销 `JoyHotkeyManager.Shutdown()`） |
| `infrastructure/backup_core.ahk` | ① 删除 `#Include "config_io.ahk"` + `#Include "utils.ahk"`；② `:70` `ConfigIO.ExportToFile` → `ExportConfigToFile`（反向依赖回归）；③ `_SortBackupsByTime` 回退为手动插入排序（撤销 M13 的 `_SortByField` 复用） |
| `infrastructure/migration_logger.ahk` | 删除 `#Include "utils.ahk"` |
| `tests/run_all_tests.ahk` | +2074 行（新增大量测试类）；**删除 `BackupServiceLayeringTests`、`ConfigIOLayeringTests` 等 12 个 suite 的注册** |

> ⚠️ 注意：`backup_core.ahk` 的未提交改动含 3 处独立变更，其中仅第 ② 项是 CR1 核心；处置时**不得**一刀切 `git checkout` 回滚（详见 §1.5）。

### 1.4 具体修复步骤（原子提交粒度）

> 每步一个 commit。第 0 步（处置预案）完成后才开始第 1~4 步。

**Step 0（唯一硬性前置）**：完成「工作区 4 个未提交文件处置预案」（见 §1.5），确保工作区无半回退、无用户未提交改动丢失风险。

**Step 1 — 恢复 `main.ahk` 的接线（1 commit，`fix(ahk): 恢复 config_io/backup_service 生产入口 include`）**
- 在基础设施层 include 段（`main.ahk:29` `#Include "infrastructure\error_system.ahk"` 之后、`main.ahk:30` `backup_core.ahk` 之前）恢复：
  `#Include "infrastructure\config_io.ahk"`
- 在应用层 include 段（`main.ahk:51` `#Include "application\config_service.ahk"` 之后）恢复：
  `#Include "application\backup_service.ahk"`
- 恢复两处 OnExit（`main.ahk:115`、`main.ahk:130`）为：
  `OnExit((*) => (JoyHotkeyManager.Shutdown(), SkillManager.OnExit()))`
- ⚠️ 注意 `config_io.ahk` 自身 `#Include` 了 `json_logger/json_serializer/json_parser/error_handler`，且依赖 `ErrorHandler.RetryWithPolicy/SafeExecute`，故 `config_io.ahk` 必须在 `error_system.ahk` 之后、`backup_core.ahk` 之前加载（与 HEAD 顺序一致）。

**Step 2 — 修复 `backup_core.ahk:70` 反向依赖（1 commit，`fix(ahk): backup_core 恢复 ConfigIO 写入消除反向依赖`）**
- 在 `infrastructure/backup_core.ahk` 顶部（`backup_core.ahk:16` `#Include "json_parser.ahk"` 之后）恢复 `#Include "config_io.ahk"`；
- 将 `backup_core.ahk:70` 改为：
  `exportResult := ConfigIO.ExportToFile(BackupCore.currentConfigPath, config)`
- ⚠️ 仅改这两处；**不要**动 `backup_core.ahk` 的 `_SortBackupsByTime` 未提交回退（其归属在 §1.5 单独确认，不属 CR1 范围，如确为有意回退则保留）。

**Step 3 — 清理 `config_service.ahk` 无调用方的全局包装（1 commit，`refactor(ahk): config_service 移除 ImportConfigFromFile/ExportConfigToFile 全局包装`）**
- 将 `application/config_service.ahk` 内部 3 处调用点改为直接调用 `ConfigIO`：
  - `:36` `config := ImportConfigFromFile(ConfigService.configPath)` → `config := ConfigIO.LoadFromFile(ConfigService.configPath)`
  - `:106` `return ExportConfigToFile(ConfigService.configPath, config)` → `return ConfigIO.ExportToFile(ConfigService.configPath, config)`
  - `:376` `return ExportConfigToFile(ConfigService.configPath, config)` → `return ConfigIO.ExportToFile(ConfigService.configPath, config)`
- 删除 `config_service.ahk:407-418` 的「通用 IO 函数」整段（含注释与 `ImportConfigFromFile`/`ExportConfigToFile` 两个全局函数）。
- 说明：报告原文称「移除已无调用方的全局包装」，但实测 `backup_core.ahk` 修复后，包装仍被 `config_service` 内部 :36/:106/:376 引用，故必须先改内部调用点再删包装，否则删后即产生 `Unknown function` 编译错误。

**Step 4 — 验证（见 §1.6）。**

### 1.5 工作区 4 个未提交文件处置预案（⚠️ 唯一硬性前置，必须先于一切修复执行）

> 原则：**严禁 `git checkout <file>` / `git restore <file>` / `git reset --hard` 直接回滚或覆盖工作区未提交改动**——这些改动可能是用户有意为之（如 M13 后 `_SortBackupsByTime` 的临时回退、迁移日志 include 清理）。每一步先备份、再确认归属，仅对「确定为半回退拆坏」的部分做定向恢复。

**处置步骤（顺序执行）**：

1. **快照备份**：将 4 个文件的当前工作区版本复制到临时备份目录（`docs/review/2026-08-20/fix-plan/workspace-snapshot/`，以 `git rev-parse HEAD` 短哈希 + 时间戳命名），可用 `git diff > snapshot.patch` 同时保存 diff 快照。确保任何后续操作都可还原到处置前状态。
2. **逐文件确认归属（人工核对）**：
   | 文件 | 待确认点 | 判定 |
   |------|---------|------|
   | `main.ahk` | 删除 config_io/backup_service include + OnExit 回退 | 判定为「半回退拆坏」→ 归 CR1 Step 1 定向恢复 |
   | `infrastructure/backup_core.ahk` | 3 处独立改动：include 删除、:70 反向依赖、`_SortBackupsByTime` 回退 | include 删除 + :70 → 归 CR1 Step 2；`_SortBackupsByTime` 回退需单独确认（若为有意回退 M13，则保留，不属 CR1） |
   | `infrastructure/migration_logger.ahk` | 删除 `#Include "utils.ahk"` | 需确认 `MigrationLogger` 是否仍使用 `_GetField`/`_GetProp` 等 utils 工具；若不再使用，该删除为合理清理，保留；若仍使用，恢复 include |
   | `tests/run_all_tests.ahk` | 删除 12 个 suite 注册（含 `BackupServiceLayeringTests`/`ConfigIOLayeringTests`） | 需确认是「有意精简」还是「误删」；至少 CR1 验证依赖恢复 `BackupServiceLayeringTests`/`ConfigIOLayeringTests` 注册 |
3. **恢复 `main.ahk` 的 2 行 include + OnExit**（= §1.4 Step 1，作为处置后的第一个原子提交）。
4. **修 `backup_core.ahk:70` 反向依赖**（= §1.4 Step 2，恢复 `#Include "config_io.ahk"` + 改 `ConfigIO.ExportToFile`）。
5. **清理 `config_service.ahk` 无调用方包装**（= §1.4 Step 3）。
6. **跑 `layering_security_suites` 验证**（= §1.6 的 CR1 验证项），确认 `Test_BackupCore_NotCallExportConfigToFile` 断言通过、`BackupServiceLayeringTests`/`ConfigIOLayeringTests` 注册并全部通过。

> 只有在第 1~2 步完成、第 3~6 步验证通过后，工作区才算脱离「半回退状态」。此处置是 CR2/CR3 及其余 P1/P2 修复的先决条件。

### 1.6 测试验证方案

**前置检查（引用 AGENTS.md「测试文件前置检查流程」，三步必做）**：

1. **语法检查（stderr 重定向 + 退出码验证）**——修改 `main.ahk`/`backup_core.ahk`/`config_service.ahk` 后分别执行：
   ```powershell
   $proc = Start-Process -FilePath "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" `
       -ArgumentList "/ErrorStdOut","main.ahk" `
       -WorkingDirectory "D:\1demo\AutoHotkeydemo" -NoNewWindow -Wait -PassThru `
       -RedirectStandardError "D:\1demo\AutoHotkeydemo\cr1_stderr.txt"
   Write-Host "Exit code: $($proc.ExitCode)"   # 0 = 无语法错误；2 = 语法错误
   Get-Content "D:\1demo\AutoHotkeydemo\cr1_stderr.txt"
   ```
   对 `application\config_service.ahk`、`infrastructure\backup_core.ahk`、`infrastructure\config_io.ahk` 同样执行（`/ErrorStdOut` + 重定向 stderr）。
2. **接管指令验证**——确认上述每一处改动文件顶部仍含 `#ErrorStdOut`、`#Warn VarUnset`、`#Warn Unreachable`、`#Warn LocalSameAsGlobal`；`main.ahk` 仍含 `OnError(ErrorSystem_HandleError, -1)`。
3. **运行时验证**——启动主脚本确认退出码 0、无 `Unknown class` 弹窗：
   ```powershell
   & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" asd.ahk
   # 退出码 0 = 正常；运行时错误由 OnError 接管，仍为 0
   ```

**分层回归测试（核心验证）**：
- 运行完整测试入口：`& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
- 重点确认 `layering_security_suites.ahk` 中两套件注册并全绿：
  - `BackupServiceLayeringTests`（验证生产入口 `#Include "application\backup_service.ahk"` 后 `BackupService` 类已定义，8 个断言）
  - `ConfigIOLayeringTests`（`Test_ConfigIO_HasExportToFile`、`Test_ConfigIO_ExportToFile_WritesFile`、`Test_BackupCore_NotCallExportConfigToFile`）——其中 `Test_BackupCore_NotCallExportConfigToFile` 断言 `InStr(content, "ExportConfigToFile") == 0`，仅在 Step 2 修复 `backup_core.ahk:70` 后通过。
- **若 `tests/run_all_tests.ahk` 未恢复这两个 suite 的注册**，则须先（按 §1.5 第 2 步确认后）恢复注册再运行；否则分层回归存在盲区。

**功能路径验证**：
- 启动主程序后触发一次「保存配置」「导入配置」「创建备份 / 恢复备份」，确认无 `Unknown class: ConfigIO` / `Unknown class: BackupService` 崩溃（可在 `logs/app.log` 过滤 `"level":"ERROR"` 核对无对应未知类异常）。

### 1.7 回滚机制（可逆性）

- **原子提交粒度**：Step 1/2/3 各为一个独立 commit，可分别 `git revert`。
- **处置预案兜底**：任何一步失败，优先用 §1.5 Step 1 的快照 `snapshot.patch`（或备份目录文件）将工作区还原到处置前状态。
- **禁止**：不得用 `git reset --hard` / `git checkout -- .` 直接回滚（会覆盖未提交改动）。
- **可逆性**：Step 1/2 是「恢复 HEAD 已有基线内容」，本质是把头部状态重现，天然可逆；Step 3 删除全局包装是纯删除，`git revert` 即可恢复（且内部调用点已切到 `ConfigIO`，恢复包装不影响正确性）。

### 1.8 修复后效果评估标准（可度量达标判据）

| # | 判据 | 达标值 |
|---|------|--------|
| 1 | 语法检查退出码 | `main.ahk`/`config_service.ahk`/`backup_core.ahk`/`config_io.ahk` 均为 0，stderr 为空 |
| 2 | 启动无崩溃 | 主脚本启动退出码 0，`logs/app.log` 无 `Unknown class: ConfigIO` / `Unknown class: BackupService` |
| 3 | 分层断言 | `Test_BackupCore_NotCallExportConfigToFile` 通过；`ConfigIOLayeringTests`/`BackupServiceLayeringTests` 全部通过 |
| 4 | 反向依赖消除 | `backup_core.ahk` 源码文本 `InStr(content, "ExportConfigToFile") == 0`（不含该字符串） |
| 5 | 工作区干净 | 处置完成后 `git status --short` 中不残留「半回退」状态（4 个文件均有明确处置结果：已提交或经确认保留） |
| 6 | OnExit 完整 | `main.ahk` 两处 OnExit 均含 `JoyHotkeyManager.Shutdown()` |

### 1.9 时间框（P0 — 立即/下次运行前）

- 处置预案（§1.5）：**T+0，立即执行**（阻塞一切）。
- Step 1~3（原子提交）：处置预案确认后，约 0.5 小时内完成。
- 验证（§1.6）：紧随提交，约 0.5 小时内完成。
- **合计：下次运行/发布前必须完成，预计 T+0 ~ T+0.5 天。**

### 1.10 资源需求

- **人力**：1 名熟悉 AHK 分层与 `#Include` 加载顺序的开发者（执行）；1 名熟悉工作区 4 个文件改动背景的复核人（确认归属，§1.5 第 2 步必须有人工判定）。
- **工具/环境**：`D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`；git；PowerShell。
- **时间**：约 0.5~1 人天（含归属确认沟通成本）。

### 1.11 风险评估与应对

| 风险 | 等级 | 应对 |
|------|------|------|
| 误覆盖/误回滚用户未提交改动（`backup_core.ahk` 的 `_SortBackupsByTime` 回退、`migration_logger.ahk` include 清理、`run_all_tests.ahk` suite 精简可能是有意改动） | 高 | §1.5 先备份 + 逐文件人工确认归属；仅对「判定为半回退拆坏」部分定向恢复；绝不整文件回滚 |
| `layering_security_suites.ahk` 静态断言对源码格式敏感 | 中 | Step 2 改 `:70` 时保持单行 `ConfigIO.ExportToFile(...)` 写法，避免字符串格式触发误判 |
| `config_io.ahk` 加载顺序错误导致 `ErrorHandler` 未定义 | 中 | 严格按 §1.4 Step 1 的顺序：`error_system.ahk` → `config_io.ahk` → `backup_core.ahk`；Step 2 的 include 恢复后运行语法检查确认 |
| Step 3 删除全局包装后遗漏内部调用点 | 中 | 改前 `grep -n "ImportConfigFromFile\|ExportConfigToFile" application/config_service.ahk`，确认仅 :36/:106/:376 三处后逐一改，再删包装 |
| 处置期间误触发运行崩溃 | 低 | 处置全程不运行 `asd.ahk`，只在 Step 4 验证阶段启动 |

### 1.12 责任角色

- **执行人**：配置/接线修复负责人（恢复 include + 反向依赖 + 清理包装，§1.4 Step 1~3）。
- **复核人**：审核者 / Tech Lead（§1.5 第 2 步「归属确认」+ 各 commit diff 审查）。
- **验收人**：QA / 评审人（执行 §1.6 验证并签字确认达标判据）。

---

## 2. CR2 ｜ 执行器每次按键 down/up 无条件执行 IPC 序列化 + 同步阻塞写命名管道

> 来源编号：T6-01

### 2.1 问题描述（复述报告要点）

`asd-tauri/src-tauri/ahk_executor/sender.ahk:494-522` 的 `_SendKeyDown`/`_SendKeyUp` 每次按键动作都无条件调用 `IpcClient._SendMsg(Map("type","key_send_event",...))` 上报 Rust；`ipc_client.ahk:792-818` 的 `_SendMsg` 内部执行 `MiniJson.Stringify`（递归序列化）→ 两次 `StrPut` → `Buffer` 分配 → 同步 `WriteFile`。管道以无 `FILE_FLAG_OVERLAPPED` 方式打开（`ipc_client.ahk:533-541` 的 `CreateFileW` 第 7 参数为 `FILE_ATTRIBUTE_NORMAL`），写为同步阻塞。周期性 50ms 间隔下单键 = 每秒 20 down + 20 up = 40 次消息，每次 2 次 JSON 序列化 + 2 次 Buffer 分配 + 2 次同步管道写，且无背压上限。

### 2.2 影响范围评估

- **受影响模块**：
  - `asd-tauri/src-tauri/ahk_executor/sender.ahk:494-522`（`_SendKeyDown`/`_SendKeyUp`）
  - `asd-tauri/src-tauri/ahk_executor/ipc_client.ahk:792-818`（`_SendMsg`）、`:533-541`（`CreateFileW` 打开方式）
- **受影响功能/用户路径**：所有周期/序列/混合/hold/enhanced 模式的按键执行热路径。
- **触发场景**：前端卡顿 → outbound 慢 → 管道满 → 同步 `WriteFile` 阻塞 AHK 消息循环 → 反向冻结执行；高频模式（50ms 周期）下持续产生大量 IPC 消息。
- **用户可感知**：按键执行延迟/抖动、执行器假死、CPU 浪费在序列化与内核态写管道。

### 2.3 根本原因分析（引用报告 + 因果链）

- **报告根因**：`key_send_event` 仅用于前端展示/反馈，却与最热路径强耦合；管道写为同步阻塞、无 `OVERLAPPED`/背压上限。
- **因果链**：
  1. `_SendKeyDown/_SendKeyUp` 内联 `IpcClient._SendMsg`，不考虑当前是否处于「需要展示逐键反馈」的模式；
  2. `_SendMsg` 每键 2 次 JSON 序列化 + 2 次 Buffer 分配 + 2 次同步 `WriteFile`；
  3. 管道以无 `FILE_FLAG_OVERLAPPED` 打开 → `WriteFile` 同步阻塞；
  4. 前端消费变慢 → Rust outbound 慢 → 管道写满 → AHK 端 `WriteFile` 阻塞消息循环 → 反向冻结。

> 实测：`_recordState`/`_validationGroupId` 状态位于 `executor.ahk` 的 `CommandDispatcher`（`executor.ahk:48` `_recordState := "idle"`、`:238` `_validationGroupId := ""`），而 `Sender` 类（`sender.ahk:17`）自身不感知录制/验证状态；`sender.ahk` 仅 `#Include "ipc_client.ahk"`，`executor.ahk` 反向 `#Include "sender.ahk"`。

### 2.4 具体修复步骤（原子提交粒度）

**Step 1 — 引入按需上报开关（1 commit，`perf(asd-tauri): 执行器逐键 IPC 上报改为录制/验证模式才发送`）**
- 在 `asd-tauri/src-tauri/ahk_executor/sender.ahk` 的 `Sender` 类静态属性区（`sender.ahk:17-28` 附近）新增：
  `static _reportKeyEvents := false`
- 在 `_SendKeyDown`（`sender.ahk:494-507`）中，将 `SendInput` 与 `IpcClient._SendMsg` 之间插入：
  ```autohotkey
  if !Sender._reportKeyEvents
      return
  ```
  （即：`SendInput` 始终执行；仅在 `_reportKeyEvents = true` 时才构造并发送 `key_send_event`）
- 同样在 `_SendKeyUp`（`sender.ahk:509-522`）插入相同判断。
- ⚠️ 注意 AHK 箭头函数块体陷阱：这里用的是 `if` 普通语句，非 `=> { }` 箭头块体，安全。

**Step 2 — 由 CommandDispatcher 控制开关（1 commit，`perf(asd-tauri): 录制/验证状态联动按键上报开关`）**
- 在 `executor.ahk` 的 `start_recording` 分支（`executor.ahk:164` `CommandDispatcher._recordState := "recording"` 之后）追加 `Sender._reportKeyEvents := true`；
- 在 `stop_recording` 分支（`executor.ahk:174` `_recordState := "idle"` 之后）追加 `Sender._reportKeyEvents := false`；
- 在 `start_validation`（`executor.ahk:246` `_validationGroupId := groupId` 之后）追加 `Sender._reportKeyEvents := true`；
- 在 `stop_validation`（`executor.ahk:253` `_validationGroupId := ""` 之后）追加 `Sender._reportKeyEvents := false`。
- ⚠️ 采用「Sender 维护自身开关、由 CommandDispatcher 设置」的方式，避免 `sender.ahk` 反向引用 `CommandDispatcher`（保持 `#Include` 单向：`sender.ahk` 仅依赖 `ipc_client.ahk`）。

**Step 3 — 管道写降级/非阻塞兜底（1 commit，`perf(asd-tauri): IPC 管道写失败降级跳过上报`）**
- 在 `ipc_client.ahk:792-818` 的 `_SendMsg` 中，对 `WriteFile` 失败路径优化为「降级跳过 + 记录一次 DEBUG（限速）」，避免每次失败都走 `_HandleDisconnect`（当前失败即断连在「管道短暂忙」场景过度反应）；更彻底的异步化（`FILE_FLAG_OVERLAPPED` + 事件轮询）作为后续 P1（G4 组 T6-05/T6-06）一并实施，避免本阶段过度改动。
- **说明**：报告方案 ③「管道写入非阻塞/异步」的风险较高（涉及 `ipc_client.ahk:533-541` 的 `CreateFileW` 打开方式与整套读写路径改造），本阶段 P0 以「默认关闭逐键上报 + 发送侧降级」达到消除热路径开销的目标；`OVERLAPPED` 异步化留待 P1 G4 主题统一处理，避免与 T6-05/T6-06 重复改动冲突。

### 2.5 测试验证方案

**前置检查（AGENTS.md 三步，改动文件为 `sender.ahk`/`executor.ahk`/`ipc_client.ahk`）**：
1. 语法检查（`/ErrorStdOut` + stderr 重定向，逐一执行，退出码须为 0）；
2. 接管指令验证（三文件顶部保留 `#ErrorStdOut` + `#Warn VarUnset` + `#Warn Unreachable` + `#Warn LocalSameAsGlobal`）；
3. 运行时验证（执行器测试入口退出码 0）。

**执行器回归测试**：
- 运行执行器套件（`tests/test_ahk_executor/`）：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- 重点回归：`test_sender.ahk`（11 套件）、`test_ipc_client.ahk`（12 套件）、`test_executor.ahk`（9 套件）。
- **新增/补充回归测试**：
  - 在 `test_sender.ahk` 增加 `Test_SendKeyDown_SkipsReporting_WhenNotRecording`：置 `Sender._reportKeyEvents := false`，mock `IpcClient._SendMsg` 计数，调用 `_SendKeyDown("a")`，断言 `_SendMsg` 计数不变；
  - 增加 `Test_SendKeyDown_Reports_WhenRecording`：置 `Sender._reportKeyEvents := true`，断言 `_SendMsg` 被调用且 `type = "key_send_event"`。
  - 在 `test_executor.ahk` 增加 `Test_StartRecording_SetsReportFlag` / `Test_StopValidation_ClearsReportFlag` 断言状态切换正确联动 `Sender._reportKeyEvents`。

### 2.6 回滚机制（可逆性）

- 每个 Step 独立 commit，可 `git revert` 单独回滚。
- Step 1/2 是「加开关 + 状态联动」，回滚即恢复逐键上报行为，无数据迁移风险。
- Step 3 若涉及 `_SendMsg` 失败分支语义变更，回滚后回到「失败即断连」原行为。

### 2.7 修复后效果评估标准（可度量达标判据）

| # | 判据 | 达标值 |
|---|------|--------|
| 1 | 非录制/验证模式 IPC 消息量 | 逐键 `key_send_event` 上报为 0（计数断言验证 `_SendMsg` 不被调用） |
| 2 | 录制/验证模式行为不变 | `_reportKeyEvents = true` 时逐键上报仍按原样发送，`test_ipc_client`/`test_hotkey_hook` 全绿 |
| 3 | 语法检查 | 三文件 `/ErrorStdOut` 检查退出码 0 |
| 4 | 执行器既有套件回归 | `test_sender`/`test_ipc_client`/`test_executor` 全部通过 |
| 5 | 状态切换正确性 | start/stop recording/validation 四分支与 `_reportKeyEvents` 联动断言通过 |

### 2.8 时间框（P0）

- Step 1~3 + 验证：**T+0 ~ T+1**（不阻塞运行，但须在 CR1 处置完成后开展）。
- 注意：CR2 源码改动不得与 CR1 混入同一提交、不得在 CR1 处置预案完成前触碰 `tests/run_all_tests.ahk`。

### 2.9 资源需求

- **人力**：1 名熟悉执行器 IPC 与 `#Include` 关系的开发者；1 名复核人。
- **工具/环境**：AHK v2（`D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`）；git；PowerShell。
- **时间**：约 0.5~1 人天。

### 2.10 风险评估与应对

| 风险 | 等级 | 应对 |
|------|------|------|
| 关闭逐键上报导致前端「按键回显/反馈」缺失 | 中 | 仅在录制/验证模式开启；明确前端逐键反馈的语义边界，若前端可持续依赖其他事件，则记录到文档 |
| `sender.ahk` 反向引用 `CommandDispatcher` 引入新依赖环 | 中 | 采用「Sender 自持开关 + CommandDispatcher 置位」，禁止 sender 引用 CommandDispatcher（见 §2.4 Step 2 注明） |
| Step 3 改动 `_SendMsg` 失败分支改变断连语义 | 中 | 保守实现：失败仅 DEBUG 降级跳过，不改变已成功路径的断连判定；异步化留 G4 |
| 与 CR1 的 `tests/run_all_tests.ahk` 未提交改动耦合 | 高 | CR2 开始前必须先完成 CR1 处置（含 run_all_tests.ahk 归属确认），避免在未提交版本上叠加测试注册改动的冲突 |

### 2.11 责任角色

- **执行人**：执行器性能优化负责人（Step 1~3）。
- **复核人**：IPC/执行器技术负责人。
- **验收人**：QA / 评审人（执行器套件 + 新增回归断言签字）。

---

## 3. CR3 ｜ `docs/developer-guide.md` 整篇基于已废弃单 crate 结构，与实际 5-member workspace 严重不符

> 来源编号：T7-01

### 3.1 问题描述（复述报告要点）

`docs/developer-guide.md` §1.2（L51-85）仍把 Rust 源码描述为 `src-tauri/src/{domain,application,infrastructure}/` 三子模块（该目录已不存在，现为 5-member workspace）；`models.rs` 被描述为「IpcCommand 9 变体」（实际 13 变体，且已移到 `asd-ipc-protocol/src/command.rs`）；§2.3.3（L226-236）IpcCommand 表缺 `PauseRecording/ResumeRecording/StartValidation/StopValidation`；附录 E（L975-993）称「13 个 Tauri Command」（实际 34 个）；§1.1（L29）称 api.js「13 个 invoke + 19 个 stub」。

### 3.2 影响范围评估

- **受影响模块/路径**：
  - `docs/developer-guide.md` §1.1（L29）、§1.2（L51-85）、§1.3（L87-98）、§1.4（L100-115）、§2.3.3（L222-236）、附录 E（L975-993）
- **受影响用户路径**：新加入开发者、贡献者按文档定位目录/文件/命令时形成断链（找不到 `src-tauri/src/domain/`、找不到 `models.rs` 中的 `IpcCommand`、命令数对不上）。
- **触发场景**：任何以该文档为 onboarding / 结构参考的开发活动。

### 3.3 根本原因分析（引用报告 + 因果链）

- **报告根因**：文档 v1.0 写于 2026-05-29，早于 crate 抽取（workspace 化）与命令扩充，此后未同步更新。
- **因果链**：v4.0 从单 crate 抽取为 5-member workspace（`asd-domain`/`asd-ipc-protocol`/`asd-application`/`asd-test-harness`/`asd-tauri`）→ `IpcCommand` 从 9 扩到 13 变体并移入 `asd-ipc-protocol/src/command.rs` → Tauri Command 从 13 增至 34 → 文档未随代码演进回填。

### 3.4 具体修复步骤（原子提交粒度）

**Step 1 — 重写 §1 为 5-member workspace 结构（1 commit，`docs: 重写 developer-guide §1 为 5-crate workspace 结构`）**
- 以 `AGENTS.md` 的「Rust/Tauri 架构（5-Crate Workspace）」章节为权威蓝本重写 §1.1/§1.2；
- §1.2 删除 `src-tauri/src/{domain,application,infrastructure}/` 三子模块描述，改为：
  - `crates/asd-domain/`（config.rs / models.rs / validator.rs / traits.rs）
  - `crates/asd-ipc-protocol/`（command.rs / message.rs / error.rs / hotkey_merger.rs）
  - `crates/asd-application/`（scheduler.rs / state.rs / config_repository.rs / error.rs）
  - `crates/asd-test-harness/`
  - `src-tauri/`（lib.rs / bridge.rs / infrastructure/ / commands/ / ahk_executor/）
- §1.2 中 `models.rs` 的「IpcCommand 9 变体」修正为「IpcCommand 13 变体，定义于 `crates/asd-ipc-protocol/src/command.rs`」。

**Step 2 — 重写 IpcCommand 表为 13 变体（1 commit，`docs: developer-guide IpcCommand 表补全 13 变体`）**
- 按 `asd-tauri/crates/asd-ipc-protocol/src/command.rs` 重写 §2.3.3（L222-236）表，补齐 13 变体：`ToggleGroup`、`RegisterHotkey`、`UnregisterHotkey`、`StartRecording`、`StopRecording`、`PauseRecording`、`ResumeRecording`、`EmergencyRelease`、`Ping`、`Shutdown`、`HoldModeToggle`、`StartValidation`、`StopValidation`。

**Step 3 — 修正附录 E 与 api.js 计数（1 commit，`docs: developer-guide 附录E 修正为 34 个 Tauri Command`）**
- 附录 E（L975-993）：按 `asd-tauri/src-tauri/src/commands/` 下 5 个命令文件（`config_cmd.rs`/`group_cmd.rs`/`hotkey_cmd.rs`/`recording_cmd.rs`/`system_cmd.rs`）实际重列，将「13 个 Tauri Command」改为「34 个 Tauri Command」，并补全缺失命令（含 `pause_recording`/`resume_recording`/`start_validation`/`stop_validation` 等）。
- §1.1 L29 与 §1.4 L104 的 api.js 计数按 `asd-tauri/src/api.js` 实际核对修正（13 个已实现 invoke 的实际清单、stub 数量、事件监听数量）。

**Step 4 — 顶部标注 + 交叉引用（可选并入 Step 1）**：在文档顶部增加「本文档以 AGENTS.md 为最权威来源，结构与命令计数以实际代码为准」的声明，或如图所示报告方案将整篇标注「已过时，以 AGENTS.md 为准」并归档（二选一，需与文档 owner 确认）。

### 3.5 测试验证方案

**文档验证（无需 AHK/cargo 测试，采用一致性核对）**：
- 交叉核对：`developer-guide.md` 中的目录树与 `asd-tauri/` 实际目录（`crates/{asd-domain,asd-ipc-protocol,asd-application,asd-test-harness}` + `src-tauri/`）一一对应；
- IpcCommand 表与 `crates/asd-ipc-protocol/src/command.rs` 中 `pub enum IpcCommand` 的 13 个 variant 逐一比对；
- Tauri Command 计数与 `src-tauri/src/lib.rs` 中 `generate_handler![...]` 列表（或 `EXPECTED_TAURI_COMMAND_COUNT`，见 T5-02 注意其永真式局限）比对至 34；
- 引用 AGENTS.md「测试前置检查流程」**不适用**（纯文档，无 .ahk 改动）；但若 Step 涉及 `.ahk`（本 CR3 不涉及），则须走三步检查。

**可选的机械校验**：
- `grep -c "IpcCommand 变体\|IpcCommand variant" docs/developer-guide.md` 确认无残留「9 变体」表述；
- `Select-String -Path docs\developer-guide.md -Pattern "13 个 Tauri Command|9 变体|domain/.*application/.*infrastructure"` 确认无过时表述残留。

### 3.6 回滚机制（可逆性）

- 纯 Markdown 文档改动，每 Step 独立 commit，`git revert` 即可回滚；无运行时副作用。

### 3.7 修复后效果评估标准（可度量达标判据）

| # | 判据 | 达标值 |
|---|------|--------|
| 1 | 目录结构 | 文档不含 `src-tauri/src/{domain,application,infrastructure}/` 三子模块描述，含 5-member workspace 描述 |
| 2 | IpcCommand 变体数 | 文档 IpcCommand 表含 13 变体（含 4 个缺失 variant） |
| 3 | Tauri Command 数 | 文档标注 34 个（与 `lib.rs` 注册数一致） |
| 4 | api.js 计数 | 与 `asd-tauri/src/api.js` 实际 invoke/stub/事件数一致 |
| 5 | 断链 | 文档中每个「file:///…」链接路径在仓库中可解析 |

### 3.8 时间框（P0）

- Step 1~3：**T+0 ~ T+1**（不阻塞运行；可与 CR2 并行，但不得在 CR1 处置完成前提交到 `main.ahk`/`tests/` 相关路径——本 CR3 仅改 `docs/`，无此冲突）。

### 3.9 资源需求

- **人力**：1 名技术文档负责人（对照 AGENTS.md 与源码重写）。
- **工具/环境**：git；文本编辑器；必要时 `cargo check` 核对命令数。
- **时间**：约 0.5~1 人天。

### 3.10 风险评估与应对

| 风险 | 等级 | 应对 |
|------|------|------|
| 文档与 AGENTS.md/test-map.md 又产生新的口径漂移 | 中 | 以「单一权威来源」策略：结构以 AGENTS.md 为准、命令数以 `lib.rs` 为准、测试数以 test-map.md 为准，文档内显式声明来源 |
| 重新计数时遗漏 34 命令中的个别 | 中 | 用 `grep -n "#\[tauri::command\]" src-tauri/src/commands/*.rs` 机械化统计后逐条列 |
| 与 T7-02（migration-guide.md）重复劳动 | 中 | 本 CR3 仅处理 developer-guide.md；migration-guide.md 属 P1（G10），单独立项，避免范围蔓延 |

### 3.11 责任角色

- **执行人**：技术文档负责人。
- **复核人**：架构负责人（确认 workspace 结构与命令表与代码一致）。
- **验收人**：评审人（§3.7 判据核对签字）。

---

## 4. 验证命令汇总（AGENTS.md 前置检查流程引用）

**AHK 语法检查（stderr 重定向 + 退出码）**（对 CR1/CR2 所有改动 .ahk 文件执行）：
```powershell
$proc = Start-Process -FilePath "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" `
    -ArgumentList "/ErrorStdOut","<目标.ahk>" `
    -WorkingDirectory "D:\1demo\AutoHotkeydemo" -NoNewWindow -Wait -PassThru `
    -RedirectStandardError "D:\1demo\AutoHotkeydemo\_cr_stderr.txt"
Write-Host "Exit code: $($proc.ExitCode)"   # 0 = 通过；2 = 语法错误
Get-Content "D:\1demo\AutoHotkeydemo\_cr_stderr.txt"
```
> ⚠️ 语法检查必须用 `Start-Process -RedirectStandardError` 或 `2>&1` 重定向 stderr，否则无法捕获 `#ErrorStdOut` 输出的错误（AGENTS.md 强制）。

**接管指令验证**（对每个改动 .ahk 文件）：
```powershell
$content = Get-Content "<目标.ahk>" -Raw
if ($content -notmatch '#ErrorStdOut') { Write-Host "ERROR: 缺少 #ErrorStdOut" }
if ($content -notmatch '#Warn VarUnset') { Write-Host "ERROR: 缺少 #Warn VarUnset" }
if ($content -notmatch '#Warn Unreachable') { Write-Host "ERROR: 缺少 #Warn Unreachable" }
if ($content -notmatch 'OnError') { Write-Host "ERROR: 缺少 OnError" }
```

**运行时验证 / 全量回归**：
```powershell
# 主程序启动（CR1）
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" asd.ahk
# 全量测试（CR1/CR2）
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
```

---

## 5. 交付校验

- 覆盖 Critical 编号：**CR1、CR2、CR3**（3/3）。
- 每项 11 要素齐全性：CR1 含「问题描述/影响范围/根因/修复步骤/测试验证/回滚/效果标准/时间框/资源/风险/角色」+ 额外「工作区 4 文件处置预案」子节；CR2、CR3 各含上述 11 要素。
- 硬性前置已标注：CR1 处置预案为唯一硬性前置，先于一切修复执行。