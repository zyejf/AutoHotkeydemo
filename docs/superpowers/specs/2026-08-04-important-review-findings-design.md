# Important 级别审查发现修复设计文档

> **创建日期**: 2026-08-04
> **来源**: `docs/code-review-report-2026-08-03.md` 3.2 节（43 项 Important 发现）
> **状态**: 已批准，待转入 writing-plans
> **分支**: `fix/important-review-findings`（待创建）
> **前置条件**: Critical 修复已合并到 main（commit ece8b9c）

---

## 一、目标

一次性修复代码审查报告中全部 43 项 Important 级别问题，覆盖架构合规性、代码质量、安全性、测试覆盖四个维度，遵循 AGENTS.md v4.0 强制规则。

### 范围决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 修复批次 | 一次性全部 43 项 | 符合用户规则"并行优先"原则，单次 PR 解决 |
| 任务组织 | 按主题簇打包 | 子代理上下文连贯，避免多代理同改一文件 |
| 测试类范围 | 9 项全部纳入 | 消除测试覆盖盲区，避免技术债遗留 |
| TDD 严格度 | 代码项全 TDD，文档项免 TDD | 符合用户规则强制 TDD，文档项 TDD 价值低 |

---

## 二、主题簇划分（12 簇）

通过文件冲突图分析，将 43 项问题打包为 12 个主题簇。每簇内问题高度关联，簇间文件冲突最小化。

### 簇清单

| 簇 | 主题 | 问题项 | 数量 | 主要文件 | TDD |
|----|------|--------|------|---------|-----|
| **A** | AGENTS.md 文档对齐 | I2, I22, I28, I29, I30, I32, I41 | 7 | AGENTS.md | 否 |
| **B** | BackupCore DDD 分层 | I1, I6 | 2 | presentation/backup_ui.ahk, gui_manager.ahk, webview2_manager.ahk; application/config_service.ahk; infrastructure/backup_core.ahk | 是 |
| **C** | joy_hotkey_manager 综合 | I3, I4, I8, I10 | 4 | infrastructure/joy_hotkey_manager.ahk | 是 |
| **D** | webview2 配置导入安全 | I13, I16, I17, I19, I20 | 5 | presentation/webview2_manager.ahk | 是 |
| **E** | config_store 数据完整性 | I7, I9, I15 | 3 | infrastructure/config_store.ahk, error_system.ahk | 是 |
| **F** | GUI 与定时器规范 | I5, I12, I14 | 3 | presentation/gui_manager.ahk, domain/skill_group.ahk, gui.ahk | 是 |
| **G** | 空 catch 块清理（含 joy_hotkey_manager 4 处） | I11 | 1 | key_recorder.ahk, ipc_channel.ahk, config_service.ahk, joy_sender.ahk, skill_manager.ahk, utils.ahk, gui_manager.ahk, webview2_manager.ahk, joy_hotkey_manager.ahk | 是 |
| **H** | AHK 测试套件整合 | I21, I23, I24, I25 | 4 | tests/run_all_tests.ahk, test_joystick.ahk, AGENTS.md | 是 |
| **I** | Rust 输入验证与错误 | I26, I27, I34, I35, I37 | 5 | asd-application/backup_service.rs, recording_service.rs, error.rs; asd-domain/config.rs; asd-ipc-protocol/command.rs; src-tauri/commands/recording_cmd.rs; ahk_executor/executor.ahk | 是 |
| **J** | Rust IPC 与进程安全 | I31, I33, I36 | 3 | src-tauri/lib.rs, bridge.rs, infrastructure/watchdog.rs | 是 |
| **K** | Rust 测试覆盖补充 | I38, I39, I40, I42, I43 | 5 | src-tauri/tests/, docs/test-map.md | 是 |
| **L** | AHK 热键验证 | I18 | 1 | infrastructure/config_validator.ahk | 是 |

**合计**: 43 项（I11 整体归簇 G，含 joy_hotkey_manager.ahk 4 处 + 其他 7 文件 17 处 = 21 处）

### 文件冲突图

```
webview2_manager.ahk: 簇 B ↔ D ↔ G
gui_manager.ahk:      簇 B ↔ F ↔ G
config_service.ahk:   簇 B ↔ G
lib.rs:               簇 J ↔ K
bridge.rs:            簇 J ↔ K
AGENTS.md:            簇 A ↔ H
```

---

## 三、调度策略（4 阶段流水线）

基于文件冲突图，设计 4 阶段流水线。每阶段内并行，阶段间串行。AHK 与 Rust 部分天然无冲突（不同文件集），可在阶段内并行。

### 阶段 1：基础层（5 簇并行）

无文件冲突，可全部并行启动。

| 子代理 | 簇 | 问题数 | 说明 |
|--------|-----|--------|------|
| Agent-1A | A | 7 | AGENTS.md 文档对齐（免 TDD） |
| Agent-1C | C | 4 | joy_hotkey_manager.ahk 综合 |
| Agent-1E | E | 3 | config_store + error_system |
| Agent-1L | L | 1 | config_validator 热键验证 |
| Agent-1R1 | I+J 合并 | 8 | Rust 核心修复（避免 lib.rs/bridge.rs 冲突） |

**阶段 1 验证检查点 CP1**：
- AHK: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
- Rust: `cargo test -p asd-domain -p asd-ipc-protocol -p asd-application`
- 通过标准：全绿

### 阶段 2：中间层（2 簇并行）

依赖阶段 1 完成（簇 B 需要 AGENTS.md 已更新 BackupCore 妥协描述；R2 测试需要 R1 核心修复完成）。

| 子代理 | 簇 | 问题数 | 说明 |
|--------|-----|--------|------|
| Agent-2B | B | 2 | BackupCore 分层（独占 presentation+application） |
| Agent-2R2 | K | 5 | Rust 测试补充 |

**阶段 2 验证检查点 CP2**：
- AHK: `run_all_tests.ahk`
- Rust: `cargo test --workspace`
- 通过标准：全绿

### 阶段 3：顶层（2 簇并行）

依赖阶段 2 完成（簇 D/F 共享 gui_manager.ahk/webview2_manager.ahk 与簇 B，必须等 B 完成）。

| 子代理 | 簇 | 问题数 | 说明 |
|--------|-----|--------|------|
| Agent-3D | D | 5 | webview2 配置安全 |
| Agent-3F | F | 3 | GUI 与定时器（与 D 无文件冲突） |

**阶段 3 验证检查点 CP3**：
- AHK: `run_all_tests.ahk`
- Rust: `cargo test --workspace`
- 通过标准：全绿

### 阶段 4：整合层（2 簇并行）

依赖阶段 3 完成（簇 G 改 gui_manager.ahk/webview2_manager.ahk/config_service.ahk，已被 B/D/F 改过；簇 H 整合测试需所有代码修复完成）。

| 子代理 | 簇 | 问题数 | 说明 |
|--------|-----|--------|------|
| Agent-4G | G | 1 | 空 catch 块清理（跨 9 文件 21 处，含 joy_hotkey_manager 4 处） |
| Agent-4H | H | 4 | 测试套件整合（最后做，避免与其他簇测试改动冲突） |

**阶段 4 验证检查点 CP4**：
- AHK: `run_all_tests.ahk`（全套）
- Rust: `cargo test --workspace`
- `cargo clippy --workspace -- -D warnings`
- AHK 语法检查: `AutoHotkey64.exe /ErrorStdOut asd.ahk`
- 通过标准：全绿 + 0 warning

---

## 四、TDD 流程（代码项 36 项）

每个 tdd-executor 子代理严格遵循 RED-GREEN-REFACTOR：

1. **RED**：先写失败测试
   - AHK: AutoHotUnitSuite 风格，注册到 run_all_tests.ahk
   - Rust: `#[test]` 或 `#[tokio::test]`
2. **验证 RED**：运行测试确认失败（非错误），失败原因正确
3. **GREEN**：写最小代码通过测试
4. **验证 GREEN**：运行测试确认通过，其他测试不破坏
5. **REFACTOR**：清理代码，保持测试绿色

### 测试规范

| 维度 | 规范 |
|------|------|
| AHK 测试文件 | 顶部必须含 `#ErrorStdOut "UTF-8"` + 3 条 `#Warn` + `OnError` 回调 |
| AHK 测试风格 | AutoHotUnitSuite（beforeEach/afterEach 钩子） |
| Rust 测试 | 纯逻辑 crate 用 `#[cfg(test)] mod tests`；集成测试放 `tests/` |
| 测试隔离 | 禁止静态属性污染全局状态（I24 修复重点） |

---

## 五、工作流策略

### 工作区隔离

调用 `using-git-worktrees` 技能创建隔离工作区：
- 分支名：`fix/important-review-findings`
- 基分支：`main`（commit ece8b9c）

### 技能调用顺序

1. ✅ `using-superpowers`（已调用）
2. ✅ `brainstorming`（已调用，本文档为产出）
3. `using-git-worktrees` — 创建隔离工作区
4. `writing-plans` — 生成实现计划（任务粒度 2-5 分钟）
5. `executing-plans` / `subagent-driven-development` — 派遣 tdd-executor 子代理
6. `dispatching-parallel-agents` — 并行调度（每阶段内）
7. `verification-before-completion` — 每阶段验证检查点
8. `requesting-code-review` — 阶段 4 完成后审查
9. `receiving-code-review` — 处理审查反馈
10. `finishing-a-development-branch` — 合并/PR/保留

### 验证检查点（4 道）

| 检查点 | 时机 | 命令 | 通过标准 |
|--------|------|------|---------|
| CP1 | 阶段 1 完成后 | AHK `run_all_tests.ahk` + Rust `cargo test -p asd-domain -p asd-ipc-protocol -p asd-application` | 全绿 |
| CP2 | 阶段 2 完成后 | AHK 全套 + Rust `cargo test --lib`（src-tauri） | 全绿 |
| CP3 | 阶段 3 完成后 | AHK 全套 + Rust 全 workspace | 全绿 |
| CP4 | 阶段 4 完成后 | 全量测试 + `cargo clippy` + AHK 语法检查 | 全绿 + 0 warning |

### 代码审查

- 阶段 4 完成后调用 `requesting-code-review` 技能
- 审查维度：
  1. 架构合规性（DDD 分层、依赖方向）
  2. TDD 合规性（测试先行、最小实现）
  3. AGENTS.md 一致性（文档与代码同步）
  4. 测试覆盖（新增测试质量、隔离性）
- 关键问题阻碍合并

### 完成流程

调用 `finishing-a-development-branch` 技能，选项：
1. 合并到 main 本地
2. 推送并创建 PR
3. 保留分支
4. 丢弃

---

## 六、风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| 子代理并行编辑同文件 | 低 | 高 | 4 阶段流水线已消除冲突；每阶段内簇无共享文件 |
| TDD 测试框架改动回归 | 中 | 高 | 簇 H 放最后，先确保代码修复稳定；beforeEach/afterEach 钩子 |
| AGENTS.md 多处更新冲突 | 低 | 中 | 簇 A 独占 AGENTS.md；簇 H 阶段 4 再追加 tests 登记 |
| Rust 编译时间长 | 中 | 低 | 每阶段只编译受影响 crate；CP1 不编译 src-tauri |
| I11 空 catch 块清理范围误判 | 中 | 中 | 簇 G 子代理先扫描确认 21 处位置（含 joy_hotkey_manager 4 处），再逐个修复 |
| I21/I24 测试套件整合工作量大 | 高 | 中 | 簇 H 子代理可拆分为多个子任务；优先 I23/I25 低风险项 |
| TDD 对单行修改项过度 | 中 | 低 | 接受形式化测试成本，确保规则一致性 |

---

## 七、成功标准

1. ✅ 43 项 Important 问题全部修复并验证
2. ✅ 4 个验证检查点全部通过（CP1-CP4）
3. ✅ AGENTS.md 与实际代码完全一致（簇 A 7 项 + 簇 H 追加）
4. ✅ 代码审查无 Critical/Important 阻碍问题
5. ✅ 所有新增测试遵循 AGENTS.md 测试规范
6. ✅ 提交遵循 Conventional Commits 规范

---

## 八、下一步

转入 `writing-plans` 技能，将本设计分解为可执行的实现计划（任务粒度 2-5 分钟，每个任务含精确文件路径、完整代码、验证步骤）。
