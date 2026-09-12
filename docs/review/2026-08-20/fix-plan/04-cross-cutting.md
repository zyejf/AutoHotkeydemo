# 跨切面管理章节（Fix Plan 第四步：全局管理要素整合）

> **来源**：`00-issue-inventory.md`（问题清单，72 条）+ `docs/code-review-report-2026-08-20.md`（主报告 §1/§2/§3/§6）
> **性质**：只读规划文档。本文件仅整合跨切面的实施时间表、资源、风险、回滚、测试验证与效果评估标准，**不修改任何 .ahk / .rs / .toml / .json 源码文件**。
> **口径**：阶段与时间框均以相对时间（立即 / 短期 / 长期 / 收尾）表述，不虚构绝对日历日期；具体责任人名待团队确认后填充。

---

## 1. 实施时间表

> 阶段划分与问题分级对应：**Phase 0 → P0（Critical 3）**；**Phase 1 → P1（Important 23 / 10 组）**；**Phase 2 → P2（Minor 46 / 12 批）**；**Phase 3 → 全量回归验证收尾**。
> 人员角色划分：**开发者**（改动实施）、**审查者**（diff 复核 / 专项 review）、**测试**（AHK / Rust / E2E 测试执行与验证）。具体人名待团队确认后填充。

| 阶段 | 时间框 | 责任角色（具体人名待填） | 处置范围 | 里程碑交付物 |
|------|--------|------------------------|---------|-------------|
| **Phase 0（紧急）** | 立即（下一次运行 / 发布前） | 开发者（主）、审查者（diff 复核） | CR1 / CR2 / CR3（3 项 Critical） | ① 工作区 4 个未提交文件意图确认（完成或撤销）并建立干净基线（tag）；② 主程序可运行（CR1 崩溃消除，`layering_security_suites` 通过）；③ 热路径逐键 IPC 上报收敛（CR2）；④ `developer-guide.md` 对齐 5-member workspace 或标注「已过时」（CR3） |
| **Phase 1（重要）** | 短期（紧随 Phase 0） | 开发者（主）、审查者、测试 | 23 项 Important（G1~G10 十组） | G1 校验补全（T3-01/02/03、T4-04）；G2 日志限速（T3-05+T6-03）；G3 定时器生命周期（T6-02/04）；G4 IPC 阻塞背压（T6-05/06）；G5 unsafe 收敛（T5-01，Miri 0 UB）；G6 vJoy 复用（T6-07）；G7 隐式依赖与永真断言（T2-03/04、T5-02）；G8 输入误报与注入检查（T3-04/06）；G9 测试补强（T8-01/02/03）；G10 文档统一（T7-03/04/05） |
| **Phase 2（次要）** | 长期（择机，随迭代收口） | 开发者、测试 | 46 项 Minor（B1~B12 十二批） | 冗余依赖/死代码清理（B1）；错误类型与封装统一（B2）；校验权衡与默认值语义（B3）；未登记妥协/规则豁免（B4）；并发/阻塞/健壮性（B5）；AHK/Rust 代码一致性（B6/B7）；AHK 健壮性补丁（B8）；性能微调（B9）；AGENTS.md 模块清单补全（B10）；文档标识一致（B11）；测试规范收口（B12） |
| **Phase 3（回归验证）** | 收尾（全部改动合并后） | 测试（主）、开发者、审查者 | 全量回归 + 效果评估 | 全量测试 100% 通过；`cargo clippy` 无 warning；`cargo fmt --check` 干净；覆盖率不下降；历史修复核对表无「引入回归」项；输出最终验收报告（见 §6 指标） |

> 每阶段内部建议按**组 / 批**为单位逐项提交（见 §4 回滚机制），保持「一个组 = 一次原子提交」的可回退粒度；跨阶段不混签（Phase 0 的 Critical 必须先于 Phase 1 落地，避免半回退状态被后续改动掩盖）。

---

## 2. 资源需求清单

> 状态标注：✅ 已具备 · ⚠️ 需确认/新增。人力投入为相对估算，具体人时以团队排期为准。

### 2.1 人力投入（按阶段）

| 阶段 | 开发者 | 审查者 | 测试 | 说明 |
|------|:------:|:------:|:----:|------|
| Phase 0 | 1（AHK + Rust） | 1（diff 复核） | — | 处置 3 项 Critical，改动面小但需确认工作区意图 |
| Phase 1 | 1~2（AHK / Rust 并行） | 1 | 1 | 23 项 Important 跨 AHK 与 Rust 两侧，可按 G 组拆并行 |
| Phase 2 | 1 | —（低强度） | 1 | 46 项 Minor 为收口性质，可随迭代分批消化 |
| Phase 3 | 1（配合修复回归失败项） | 1 | 1（主） | 以测试验证与修复回归为主 |

### 2.2 工具链 / 环境

| 资源 | 用途 | 涉及阶段 | 状态 |
|------|------|:-------:|------|
| AHK v2 运行时（`D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`） | 语法检查 / `run_all_tests.ahk` / 执行器测试 | Phase 0~3 | ✅ 已具备 |
| Rust 工具链（stable：cargo build / check / test） | 编译 + `cargo test --workspace` | Phase 1~3 | ✅ 已具备 |
| Rust nightly + **Miri** | T5-01 unsafe soundness 改动后的 0 UB 验证（纯逻辑 crate） | Phase 1（G5） | ⚠️ 需确认 nightly toolchain 已安装 |
| **cargo-llvm-cov** | 覆盖率基线 / 效果评估「覆盖率不下降」 | Phase 3 | ⚠️ 需确认已安装（.codecov.yml 已引用） |
| clippy / rustfmt | `cargo clippy` 无 warning / `cargo fmt --check` 干净 | Phase 2、3 | ✅ 已具备（随 Rust 工具链） |
| **tauri-driver**（`cargo install tauri-driver --locked`） | E2E 测试驱动 | Phase 3 | ⚠️ 需新增（不在 npm registry） |
| Node + npm（`asd-tauri/e2e/`） | E2E 测试（WebDriverIO 8 + Mocha） | Phase 3 | ⚠️ 需确认依赖已 `npm install` |
| Windows 测试机（联网/桌面会话） | GUI / WebView2 / 全局热键 / vJoy 实测 | Phase 0~3 | ✅ 已具备（开发机） |
| vJoy 驱动（如需验证 T6-07 组级生命周期） | joystick 复用改动实测 | Phase 1（G6） | ⚠️ 需确认已安装 |

---

## 3. 风险评估与应对

| 风险 | 影响 | 概率 | 应对措施 |
|------|:----:|:----:|---------|
| **CR1 半回退状态处置误判（覆盖用户未提交改动）** | 高 | 中 | 处置前逐一确认工作区 4 个未提交文件（`main.ahk`、`backup_core.ahk`、`migration_logger.ahk`、`tests/run_all_tests.ahk`）为「有意回退」还是「暂存」，完成或撤销全部改动后再动手；先 commit / stash 建立干净基线（§4）；严禁 `reset --hard`、`checkout .`、`clean -f` 等破坏性回滚；每步小提交，用 `git revert` 单项回退 |
| **unsafe soundness 改动（T5-01）的回归 / UB 风险** | 高 | 中 | 采用最小改动策略：优先 `state()` 改返回 Clone 类型或拆出 `Option<Child>`，杜绝跨锁引用外泄；改动后跑 `cargo +nightly miri test`（纯逻辑 crate）与 watchdog 单测验证 0 UB；审查者专项 review 所有 `unsafe` 改动并核对 Mutex 不变量注释 |
| **热路径限速改动（T3-05 / T6-03）对执行流畅度的感知影响** | 中 | 中 | 限速器与 `DebugLogger` 同构（`_lastWriteTime` + `_suppressedCount`），同源窗口内只落盘一次并批量计数，**保留 suppressedCount 输出**避免错误静默丢失；同步修正 `DebugLogger` 50ms 与「每秒一次」口径；改后跑 `run_all_tests` + 高频异常场景冒烟，确认按键节奏稳定无卡顿 |
| **文档重写（CR3、T7-02~05）的断链 / 口径冲突风险** | 中 | 中 | 确立 `test-map.md` 为唯一测试统计来源，统一口径（`#[test]` 属性数 / `Test_` 方法数 / 断言数分别标注）；重写后逐一 grep 核对文件名、行号与变体数量；对历史报告（08-03）加「部分已修复」勘误；文档改动不触碰源码，改完跑一遍文档引用的命令以验证路径仍存在 |
| **配置校验收紧（T3-01/02/03、T4-04）导致既有合法配置被拒绝** | 中 | 低 | 校验只补「格式 / 非空 / 冲突」检查，复用 `_IsValidKeyName` 合法名单逻辑而非新造名单；Rust 侧仅对控制热键空值逐项 `add_error`、非空值不额外加严；改动前用 `tests/fixtures/sample_config.json`（7 模式标准样本）做回归基准，确保现有合法样本全部通过；以新增非法样本用例的方式补覆盖，而非收紧合法集 |

---

## 4. 整体回滚机制

> 目标：任何一项修复都可独立回退，且**绝不触碰用户已有未提交改动**。

1. **建立干净基线（Phase 0 前，强制）**：
   - 工作区 4 个未提交文件（`main.ahk`、`backup_core.ahk`、`migration_logger.ahk`、`tests/run_all_tests.ahk`）先经团队确认意图，**先 commit 或 stash**，形成干净工作区。
   - 在 Phase 0 首项改动前 **打 tag**（如 `v4.0-review-fix-baseline`）或记录基线 commit hash，作为回退锚点。

2. **逐项 / 逐批独立提交**：以清单的「G 组 / B 批」为原子提交单位（一个组 = 一次提交），提交信息遵循 Conventional Commits，并在正文标注对应问题编号（如 `CR1`、`G5/T5-01`），确保「提交 ↔ 问题」一一对应可追溯。

3. **单项回退**：对已合入某组的修复需撤回时，使用 `git revert <commit>`（保留历史、可再正向重提），**禁止** `git reset --hard` 回退历史。

4. **严禁回滚用户已有未提交改动**：任何涉及「撤销/回退工作区」的操作前，先 `git status` / `git diff` 核对是否存在用户未提交内容；若存在，先与用户确认是否提交或 stash，**绝不**用 `checkout .` / `restore .` / `clean -f` 清空其改动。

5. **边界约束**：回滚仅作用于本次修复计划的提交，不跨过基线 tag；若需回退到基线，用 `git checkout <baseline-tag> -- <file>` 逐文件恢复而非整体重置。

---

## 5. 整体测试验证方案

> 覆盖 AHK v2、Rust workspace、Miri、E2E 四层，引用 AGENTS.md「测试前置检查流程」（语法检查 → 接管指令验证 → 运行时验证）与「错误与警告接管机制」。

### 5.1 AHK v2（Phase 0~3）

- **前置检查（每个改动的 .ahk 文件）**：
  1. 语法检查（stderr 重定向 + 退出码 0）：`Start-Process ... AutoHotkey64.exe /ErrorStdOut <file> -RedirectStandardError`，退出码 2 = 语法错误。
  2. 接管指令验证：确认文件含 `#ErrorStdOut` / `#Warn VarUnset` / `#Warn Unreachable` / `OnError`。
  3. 运行时错误验证：`OnError` 回调接管，退出码仍为 0。
- **全量测试**：`& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk`
- **CR1 专项**：恢复 include 后运行 `tests/suites/layering_security_suites.ahk`，`Test_BackupCore_NotCallExportConfigToFile` 断言通过。

### 5.2 Rust workspace（Phase 1~3）

```bash
cd asd-tauri && cargo test --workspace          # 全量测试
cd asd-tauri/src-tauri && cargo check           # 语法检查
cd asd-tauri && cargo clippy --workspace --all-targets   # 无 warning（见 §6）
cd asd-tauri && cargo fmt --check               # 格式干净（见 §6）
```

### 5.3 Miri（Phase 1，G5 unsafe 验证，0 UB）

```bash
cd asd-tauri && cargo +nightly miri test -p asd-domain
cd asd-tauri && cargo +nightly miri test -p asd-ipc-protocol
cd asd-tauri && cargo +nightly miri test -p asd-application -- --skip config_repository --skip save_config --skip load_from
```

### 5.4 覆盖率与 E2E（Phase 3）

```bash
# 覆盖率（评估「覆盖率不下降」）
cd asd-tauri && cargo llvm-cov --workspace --html --output-dir coverage/

# E2E（需先 cargo build --release + 安装 tauri-driver）
cd asd-tauri/e2e && npm install && npm test
```

> 测试报告落点：`asd-tauri/e2e/docs/e2e-test-report.md`；失败用例须调用 `appendKnownIssue` 记录到 `asd-tauri/e2e/docs/e2e-known-issues.md`。

---

## 6. 修复后效果评估标准

### 6.1 可量化指标（全局收口）

| 指标 | 目标值 |
|------|:------:|
| Critical 项 | **3 项清零** |
| Important 项 | **23 项清零** |
| 全量测试通过率（AHK 581 + Rust 592 + 执行器 244 + E2E 53） | **100%** |
| `cargo clippy` | **无 warning** |
| `cargo fmt --check` | **干净（无 diff）** |
| 文档漂移项（T7-* / T2-07 等） | **清零** |
| 历史修复核对表「引入回归」项 | **0 项（I1/I6 已通过 CR1 处置恢复为「已修复」）** |
| 代码覆盖率（相对 Phase 0 前基线） | **不下降** |

### 6.2 每条 Critical 独立验收判据

| 编号 | 验收判据 |
|------|---------|
| **CR1** | `main.ahk` 恢复 `#Include "infrastructure\config_io.ahk"` 与 `#Include "application\backup_service.ahk"` 及 OnExit `JoyHotkeyManager.Shutdown()`；`backup_core.ahk:70` 改调 `ConfigIO.ExportToFile` 消除反向依赖；`config_service.ahk:412-417` 清理无调用方的全局包装；`layering_security_suites.ahk` 全绿；主程序启动后可完成一次配置读写 / 备份导出（无 `Unknown class` 崩溃） |
| **CR2** | 默认关闭逐键 `key_send_event` IPC 上报（仅 `_recordState="recording"` 或 `_validationGroupId != ""` 时发送），或改批量缓冲 + 定时刷新；管道写非阻塞 / 失败降级（不阻塞 AHK 消息循环）；高频按键场景冒烟无前端卡顿引发的执行冻结 |
| **CR3** | `developer-guide.md` §1 按 5-member workspace 结构重写（`asd-domain` / `asd-ipc-protocol` / `asd-application` / `asd-test-harness` / `src-tauri`）；IpcCommand 表补齐 13 变体；附录 E 命令数对齐 34 个 Tauri Command；或文档顶部明确标注「已过时，以 AGENTS.md 为准」并归档 |