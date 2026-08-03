# Important 级别审查发现修复实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代码审查报告中全部 43 项 Important 级别问题

**Architecture:** 4 阶段流水线，12 主题簇，11 个 tdd-executor 子代理。每阶段内并行，阶段间串行，4 个验证检查点。

**Tech Stack:** AutoHotkey v2 (DDD 四层), Rust (5-crate workspace), Tauri 2.11, interprocess, AutoHotUnit

**Worktree:** `D:\1demo\AutoHotkeydemo\.worktrees\fix-important-review-findings` (branch: `fix/important-review-findings`)

**Spec:** `docs/superpowers/specs/2026-08-04-important-review-findings-design.md`

---

## 通用 TDD 步骤模板（代码项）

每个代码修复项遵循标准 TDD 5 步：

- [ ] **RED**: 写失败测试（AHK: AutoHotUnitSuite；Rust: `#[test]`）
- [ ] **验证 RED**: 运行测试确认失败，失败原因正确
- [ ] **GREEN**: 写最小代码通过测试
- [ ] **验证 GREEN**: 运行测试确认通过，其他测试不破坏
- [ ] **COMMIT**: `git commit -m "fix(scope): 描述"`

**AHK 测试运行命令**:
```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
```

**Rust 测试运行命令**:
```bash
cd asd-tauri && cargo test -p <crate-name>
```

**AHK 语法检查命令**:
```powershell
& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut <file.ahk>
```

---

## 阶段 1：基础层（5 簇并行）

### 簇 A: AGENTS.md 文档对齐（7 项，免 TDD）

**Agent**: Agent-1A
**文件**: `AGENTS.md`

- [ ] **I2**: 更新妥协 #2 — 移除 `_Notify(event, data)` 描述，改为 `INotifier.Notify(message, type, duration)` 契约说明（或直接移除妥协 #2，因签名差异已不存在）
- [ ] **I22**: 更新 AHK 执行器测试统计 — 明确口径为"Test_ 方法数"，统计 `test_ahk_executor/` 下 5 文件的 Test_ 方法数并更新
- [ ] **I28**: 更新 IpcCommand 示例 — 替换为实际 variant（`ToggleGroup { group_id, active, ... }`、`RegisterHotkey`、`EmergencyRelease` 等）
- [ ] **I29**: 执行模式表格补充 3 个 joystick 模式（`joystick_periodic`、`joystick_sequence`、`joystick_hold`）及必需字段
- [ ] **I30**: 全文 "4-crate" → "5-crate"，"4 members" → "5 members"，补充 asd-test-harness 定位
- [ ] **I32**: "19 Tauri commands" → "34 Tauri commands"；更新或移除妥协 #3（src-tauri/src/domain/、application/ 不存在）；Common Patterns 示例返回类型 `String` → `AppError`
- [ ] **I41**: 关键设计决策 #5 "3 个 fuzz target" → "5 个 fuzz target"
- [ ] **验证**: 渲染 AGENTS.md 确认无断链、无格式错误
- [ ] **提交**: `git commit -m "docs(AGENTS.md): 对齐 7 项 Important 文档漂移 (I2,I22,I28,I29,I30,I32,I41)"`

---

### 簇 C: joy_hotkey_manager.ahk 综合（4 项，TDD）

**Agent**: Agent-1C
**文件**: `infrastructure/joy_hotkey_manager.ahk`、`tests/test_joy_hotkey_manager_ahu.ahk`

- [ ] **I3**: 解耦反向依赖 — 将 `domain/joystick_input.ahk` 中的纯工具函数（IsButton/IsAxis/IsTrigger/IsPov/PovToDirection/IsJoystickConnected）迁移到 `infrastructure/joystick_input_utils.ahk`，或新增抽象基类，或在 AGENTS.md 登记妥协
  - **RED**: 写测试验证 `infrastructure/joy_hotkey_manager.ahk` 不再 `#Include "../domain/joystick_input.ahk"`
  - **GREEN**: 迁移函数 + 更新 #Include
  - **验证**: `run_all_tests.ahk` 通过
- [ ] **I4**: `infrastructure/joy_hotkey_manager.ahk:299` — `"INFO"` → `"DEBUG"`
  - **RED**: 写测试验证日志级别不含 INFO
  - **GREEN**: 修改
- [ ] **I8**: `infrastructure/joy_hotkey_manager.ahk:92` — UnregisterHotkey else 分支添加 `if JoyHotkeyManager._registered.Has(joyKey)` 检查
  - **RED**: 写测试验证 Delete 不存在的 key 不抛异常
  - **GREEN**: 添加 Has 检查
- [ ] **I10**: `infrastructure/joy_hotkey_manager.ahk:285-291` — 连接轮询定时器存储引用到 `_connPollTimer` 静态属性，Init 重置时 `SetTimer(_connPollTimer, 0)`
  - **RED**: 写测试验证定时器可停止
  - **GREEN**: 存储引用 + 停止逻辑
- [ ] **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(infrastructure): joy_hotkey_manager 综合 4 项修复 (I3,I4,I8,I10)"`

---

### 簇 E: config_store 数据完整性（3 项，TDD）

**Agent**: Agent-1E
**文件**: `infrastructure/config_store.ahk`、`infrastructure/error_system.ahk`、`tests/run_all_tests.ahk`

- [ ] **I7**: `infrastructure/config_store.ahk:119-121` — `DeleteGroupConfig` 添加 `if this._groupSettings.Has(groupId)` 前置检查
  - **RED**: 写测试验证 Delete 不存在的 groupId 不抛异常
  - **GREEN**: 添加 Has 检查
- [ ] **I9**: `infrastructure/error_system.ahk:82-85` — 在 AGENTS.md 补充例外说明："MemoryError 等不可恢复错误允许返回 0"（文档对齐，代码不改）
  - **验证**: AGENTS.md 更新
- [ ] **I15**: `infrastructure/config_store.ahk:36-64` — `Save` 方法使用 `this._groupSettings := deepclone(config["GroupSettings"])` 深拷贝
  - **RED**: 写测试验证 Save 后修改原 config 不影响内部状态
  - **GREEN**: 添加 deepclone
- [ ] **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(infrastructure): config_store 数据完整性 3 项修复 (I7,I9,I15)"`

---

### 簇 L: AHK 热键验证（1 项，TDD）

**Agent**: Agent-1L
**文件**: `infrastructure/config_validator.ahk`、`tests/run_all_tests.ahk`

- [ ] **I18**: `infrastructure/config_validator.ahk:65-66` — 在 `_ValidateGroup` 中增加热键格式正则验证
  - **RED**: 写测试验证无效热键（如 "xyz123"）被拒绝
  - **GREEN**: 添加正则验证 `^[!^+#<>~*]*[A-Za-z0-9 F1-F24]{1,2}$`（参考 AHK Hotkey 文档）
  - **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(infrastructure): config_validator 热键格式验证 (I18)"`

---

### 簇 R1: Rust 核心修复（8 项，I+J 合并，TDD）

**Agent**: Agent-1R1
**文件**: `asd-tauri/crates/asd-application/src/backup_service.rs`、`recording_service.rs`、`error.rs`、`asd-tauri/crates/asd-domain/src/config.rs`、`asd-tauri/crates/asd-ipc-protocol/src/command.rs`、`asd-tauri/src-tauri/src/commands/recording_cmd.rs`、`asd-tauri/src-tauri/src/lib.rs`、`bridge.rs`、`infrastructure/watchdog.rs`、`asd-tauri/src-tauri/ahk_executor/executor.ahk`

- [ ] **I26**: `backup_service.rs:110,116,166,230,312`、`recording_service.rs:314` — 将 `std::fs` 操作委托给 ConfigRepository 或新建 IOModule
  - **RED**: 写测试验证 backup_service 不直接调用 std::fs
  - **GREEN**: 委托 I/O
- [ ] **I27**: `command.rs:48-51` — 确认 ping/shutdown 处理层级，在 executor.ahk 补充 case 或在代码注释/AGENTS.md 记录处理层级
  - **RED**: 写测试验证 ping/shutdown 响应
  - **GREEN**: 补充 case 或文档
- [ ] **I31**: `lib.rs:390-406`、`bridge.rs:26-120,151-191` — 添加锁顺序注释，保持现状符合妥协 #2；长期将 trait 改 async
  - **RED**: 写测试验证锁顺序文档存在
  - **GREEN**: 添加注释
- [ ] **I33**: `lib.rs:117,591` — 定义 `const IPC_PIPE_NAME: &str = "asd_ipc";`，替换两处硬编码
  - **RED**: 写测试验证两处使用同一常量
  - **GREEN**: 提取常量
- [ ] **I34**: `asd-application/src/error.rs:19-26` — Serialize 改为结构化序列化（`kind: &'static str` + `message: String`）
  - **RED**: 写测试验证序列化结果含 kind 字段
  - **GREEN**: 改实现
- [ ] **I35**: `asd-domain/src/config.rs:337-345` — holdTriggers 字段存在但解析失败时返回 `serde::de::Error::custom(...)`，区分缺失与格式错误
  - **RED**: 写测试验证格式错误的 holdTriggers 被拒绝
  - **GREEN**: 区分两种情况
- [ ] **I36**: `watchdog.rs:170-199` — JobObject 失败时增加补偿机制（启动时检测遗留 asd_executor.exe + panic hook）
  - **RED**: 写测试验证遗留进程检测
  - **GREEN**: 实现补偿
- [ ] **I37**: `recording_cmd.rs:62-68,92-100,106-109,112-117` — 各命令添加 `if xxx.trim().is_empty()` 输入验证
  - **RED**: 写测试验证空输入被拒绝
  - **GREEN**: 添加验证
- [ ] **验证**: `cd asd-tauri && cargo test --workspace` 全绿
- [ ] **提交**: `git commit -m "fix(asd-tauri): Rust 核心 8 项修复 (I26,I27,I31,I33,I34,I35,I36,I37)"`

---

### 阶段 1 验证检查点 CP1

- [ ] **CP1-AHK**: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk` — 全绿（不含预存 6 项日志路径失败）
- [ ] **CP1-Rust**: `cd asd-tauri && cargo test -p asd-domain -p asd-ipc-protocol -p asd-application` — 全绿
- [ ] **CP1-通过后进入阶段 2**

---

## 阶段 2：中间层（2 簇并行）

### 簇 B: BackupCore DDD 分层（2 项，TDD）

**Agent**: Agent-2B
**文件**: `application/backup_service.ahk`（新建）、`presentation/backup_ui.ahk`、`presentation/gui_manager.ahk`、`presentation/webview2_manager.ahk`、`infrastructure/backup_core.ahk`、`application/config_service.ahk`

- [ ] **I1**: 在 `application/` 新建 `backup_service.ahk` 封装备份 API（ListBackups/RestoreBackup/DeleteBackup/CreateBackup/RecordConfigChange），表现层改为调用应用层方法
  - **RED**: 写测试验证表现层不直接调用 BackupCore
  - **GREEN**: 新建 BackupService + 更新表现层调用
- [ ] **I6**: `infrastructure/backup_core.ahk:70` — 将 `ExportConfigToFile` 核心文件写入逻辑下沉到基础设施层，或让 RestoreBackup 接受写入回调
  - **RED**: 写测试验证 backup_core 不调用应用层函数
  - **GREEN**: 下沉逻辑或接受回调
- [ ] **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(application): BackupCore DDD 分层 2 项修复 (I1,I6)"`

---

### 簇 R2: Rust 测试覆盖补充（5 项，TDD）

**Agent**: Agent-2R2
**文件**: `asd-tauri/src-tauri/src/tests/bridge_tests.rs`、`asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`、`asd-tauri/src-tauri/tests/manifest_helper.rs`、`asd-tauri/src-tauri/src/bridge.rs`、`asd-tauri/src-tauri/src/lib.rs`、`asd-tauri/docs/test-map.md`

- [ ] **I38**: 在 `test-map.md` src-tauri 表格追加 `bridge_tests.rs` 行（10 测试）
- [ ] **I39**: 更新 `test-map.md` 中 `watchdog_integration_tests.rs` 测试数为 17
- [ ] **I40**: 实现 `manifest_helper.rs` 真实 manifest 验证逻辑，或删除空壳测试和 Cargo.toml `[[test]]` 段
  - **RED**: 写测试验证 manifest 解析
  - **GREEN**: 实现或删除
- [ ] **I42**: `bridge.rs:200-213` — 将 emit 逻辑提取为 trait 抽象函数，或在 E2E 中通过 `window.__TAURI__.event.listen` 验证
  - **RED**: 写测试验证 emit 逻辑
  - **GREEN**: 提取可测试函数
- [ ] **I43**: `lib.rs` — 将 `perform_graceful_shutdown` 等纯逻辑提取到独立模块；对 command 注册列表添加编译时断言
  - **RED**: 写测试验证提取的函数
  - **GREEN**: 提取模块
- [ ] **验证**: `cd asd-tauri && cargo test --workspace` 全绿
- [ ] **提交**: `git commit -m "test(asd-tauri): Rust 测试覆盖 5 项补充 (I38,I39,I40,I42,I43)"`

---

### 阶段 2 验证检查点 CP2

- [ ] **CP2-AHK**: `run_all_tests.ahk` 全绿
- [ ] **CP2-Rust**: `cd asd-tauri && cargo test --workspace` 全绿
- [ ] **CP2-通过后进入阶段 3**

---

## 阶段 3：顶层（2 簇并行）

### 簇 D: webview2 配置导入安全（5 项，TDD）

**Agent**: Agent-3D
**文件**: `presentation/webview2_manager.ahk`

- [ ] **I13**: `webview2_manager.ahk:1182-1183` — `FileRead(absBase, "UTF-8")` 指定编码
  - **RED**: 写测试验证 UTF-8 读取中文不乱码
  - **GREEN**: 添加 "UTF-8" 参数
- [ ] **I16**: `webview2_manager.ahk:1184-1185` — `JSONParser.Parse` 后添加 `if !(baseConfig is Map)` 类型守护
  - **RED**: 写测试验证非 Map 输入被拒绝
  - **GREEN**: 添加类型守护
- [ ] **I17**: `webview2_manager.ahk:1057-1058` — 解析后检查 `GroupSettings.Count`，超过阈值拒绝
  - **RED**: 写测试验证超大配置被拒绝
  - **GREEN**: 添加计数检查
- [ ] **I19**: `webview2_manager.ahk:1102-1140` — 批量删除前 `snapshot := deepclone(ConfigStore._groupSettings)`，失败时恢复
  - **RED**: 写测试验证删除失败时状态恢复
  - **GREEN**: 添加快照恢复
- [ ] **I20**: `webview2_manager.ahk:1054-1070` — `_ReplaceAllConfig` 前强制创建备份；回滚失败时显式提示"配置已损坏"
  - **RED**: 写测试验证回滚失败提示
  - **GREEN**: 添加备份 + 提示
- [ ] **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(presentation): webview2 配置导入安全 5 项修复 (I13,I16,I17,I19,I20)"`

---

### 簇 F: GUI 与定时器规范（3 项，TDD）

**Agent**: Agent-3F
**文件**: `presentation/gui_manager.ahk`、`domain/skill_group.ahk`、`gui.ahk`

- [ ] **I5**: `presentation/gui_manager.ahk:79` — `(lv, item, isRightClick, *) => GUIManager._ShowContextMenu(lv, item, isRightClick)` 闭包包装
  - **RED**: 写测试验证闭包包装
  - **GREEN**: 改为闭包
- [ ] **I12**: `domain/skill_group.ahk:783` — 重构复杂单行为闭包函数 `ReleaseKeyLater` + `ObjBindMethod`，或将定时器引用存入 `_timers` Map
  - **RED**: 写测试验证定时器可取消
  - **GREEN**: 重构
- [ ] **I14**: `gui.ahk:886,905` — `Run('notepad.exe "' logFile '"')` 路径加引号转义
  - **RED**: 写测试验证带空格路径正确
  - **GREEN**: 添加引号
- [ ] **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(presentation): GUI 与定时器规范 3 项修复 (I5,I12,I14)"`

---

### 阶段 3 验证检查点 CP3

- [ ] **CP3-AHK**: `run_all_tests.ahk` 全绿
- [ ] **CP3-Rust**: `cd asd-tauri && cargo test --workspace` 全绿
- [ ] **CP3-通过后进入阶段 4**

---

## 阶段 4：整合层（2 簇并行）

### 簇 G: 空 catch 块清理（1 项跨 9 文件，TDD）

**Agent**: Agent-4G
**文件**: `key_recorder.ahk`、`ipc_channel.ahk`、`config_service.ahk`、`joy_sender.ahk`、`skill_manager.ahk`、`utils.ahk`、`gui_manager.ahk`、`webview2_manager.ahk`、`joy_hotkey_manager.ahk`

- [ ] **I11**: 扫描确认 21 处空 catch 块位置，逐个添加 `OutputDebug(...)` 诊断输出；轮询方法（`_Poll`/`_PollPov`/`_PollAxes`/`_PollTriggers`）增加限速日志
  - **RED**: 写测试验证 catch 块有诊断输出（通过 OutputDebug 捕获或日志检查）
  - **GREEN**: 逐个添加诊断
  - **注意**: best-effort 清理的空 catch 可保留但加注释；轮询方法必须加日志
- [ ] **验证**: `run_all_tests.ahk` 全绿
- [ ] **提交**: `git commit -m "fix(ahk): 空 catch 块诊断输出 21 处 (I11)"`

---

### 簇 H: AHK 测试套件整合（4 项，TDD）

**Agent**: Agent-4H
**文件**: `tests/run_all_tests.ahk`、`tests/test_joystick.ahk`、`tests/test_application.ahk`、`tests/test_presentation.ahk`、`tests/test_webview2_bridge.ahk`、`tests/test_error_system.ahk`、`AGENTS.md`

- [ ] **I21**: `run_all_tests.ahk` — 将内联 80 套件拆分为独立文件用 #Include 整合，或将场景式测试迁移为 AutoHotUnitSuite 模式
  - **RED**: 写测试验证所有原内联套件仍被注册
  - **GREEN**: 整合
- [ ] **I23**: `tests/test_joystick.ahk:1-3` — 补全 `#Warn VarUnset, OutputDebug`、`#Warn Unreachable, OutputDebug`、`#Warn LocalSameAsGlobal, Off`、`OnError` 回调
  - **验证**: 语法检查通过
- [ ] **I24**: `test_application.ahk`、`test_presentation.ahk`、`test_webview2_bridge.ahk`、`test_error_system.ahk` — 为 TestReporter 添加 setup/teardown 钩子或迁移为 AutoHotUnitSuite 模式
  - **RED**: 写测试验证测试隔离性（前测试不污染后测试）
  - **GREEN**: 添加钩子或迁移
- [ ] **I25**: tests/ 根目录 32 个额外文件 — 归档调试文件到 `tests/archive/`，评估保留价值，补全接管指令，登记到 AGENTS.md
  - **验证**: `run_all_tests.ahk` 全绿 + AGENTS.md 更新
- [ ] **提交**: `git commit -m "test(ahk): 测试套件整合 4 项修复 (I21,I23,I24,I25)"`

---

### 阶段 4 验证检查点 CP4

- [ ] **CP4-AHK**: `run_all_tests.ahk` 全套全绿
- [ ] **CP4-Rust**: `cd asd-tauri && cargo test --workspace` 全绿
- [ ] **CP4-Clippy**: `cd asd-tauri && cargo clippy --workspace -- -D warnings` 0 warning
- [ ] **CP4-AHK语法**: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk` 退出码 0
- [ ] **CP4-通过后进入代码审查**

---

## 提交规范

所有提交遵循 Conventional Commits（AGENTS.md 规范）：
- `fix(asd-domain): 描述`
- `fix(infrastructure): 描述`
- `fix(presentation): 描述`
- `fix(application): 描述`
- `fix(asd-tauri): 描述`
- `fix(asd-ipc-protocol): 描述`
- `test(ahk): 描述`
- `test(asd-tauri): 描述`
- `docs(AGENTS.md): 描述`

---

## 自我审查

### Spec 覆盖检查
- [x] I1 → 簇 B ✓
- [x] I2 → 簇 A ✓
- [x] I3 → 簇 C ✓
- [x] I4 → 簇 C ✓
- [x] I5 → 簇 F ✓
- [x] I6 → 簇 B ✓
- [x] I7 → 簇 E ✓
- [x] I8 → 簇 C ✓
- [x] I9 → 簇 E ✓
- [x] I10 → 簇 C ✓
- [x] I11 → 簇 G ✓
- [x] I12 → 簇 F ✓
- [x] I13 → 簇 D ✓
- [x] I14 → 簇 F ✓
- [x] I15 → 簇 E ✓
- [x] I16 → 簇 D ✓
- [x] I17 → 簇 D ✓
- [x] I18 → 簇 L ✓
- [x] I19 → 簇 D ✓
- [x] I20 → 簇 D ✓
- [x] I21 → 簇 H ✓
- [x] I22 → 簇 A ✓
- [x] I23 → 簇 H ✓
- [x] I24 → 簇 H ✓
- [x] I25 → 簇 H ✓
- [x] I26 → 簇 R1 ✓
- [x] I27 → 簇 R1 ✓
- [x] I28 → 簇 A ✓
- [x] I29 → 簇 A ✓
- [x] I30 → 簇 A ✓
- [x] I31 → 簇 R1 ✓
- [x] I32 → 簇 A ✓
- [x] I33 → 簇 R1 ✓
- [x] I34 → 簇 R1 ✓
- [x] I35 → 簇 R1 ✓
- [x] I36 → 簇 R1 ✓
- [x] I37 → 簇 R1 ✓
- [x] I38 → 簇 R2 ✓
- [x] I39 → 簇 R2 ✓
- [x] I40 → 簇 R2 ✓
- [x] I41 → 簇 A ✓
- [x] I42 → 簇 R2 ✓
- [x] I43 → 簇 R2 ✓

**43 项全覆盖** ✓

### 占位符扫描
- 无 TBD/TODO ✓
- 每个任务有精确文件路径 ✓
- 验证命令明确 ✓

### 类型一致性
- 簇名跨阶段引用一致 ✓
- 问题编号 I1-I43 无重复无遗漏 ✓
