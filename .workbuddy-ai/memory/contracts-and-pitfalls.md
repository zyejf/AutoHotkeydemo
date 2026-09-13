# 契约统计命令 / 易误判点 / BUG-6（从 MEMORY.md 拆出以控制注入体积）

## 契约统计命令（权威数字的唯一取法）

| 契约 | 命令 | 注意 |
|------|------|------|
| IPC action 分支 | `sed -n '58,85p' ahk_executor/executor.ahk \| grep -cE 'case "'` | **必须限行**：全文件 21 个 `case` 中 10 个是 MergeModeConfig 模式串（`periodic`/`sequence`/`enhanced_*`/`hold`/`hybrid`/`joystick_*`），只有 11 个是 IPC action |
| Tauri 命令数 | `grep -cE '^\s+commands::' src-tauri/src/lib.rs` | — |
| IpcCommand variant | `grep -cE '^\s{4}[A-Z][A-Za-z]+' crates/asd-ipc-protocol/src/command.rs` | — |
| crate 测试数 | `grep -rhE '^\s*#\[(tokio::)?test\]' <crate>/ --include=*.rs \| wc -l` | 用 `-h`+`wc -l`，不要按文件 `grep -c` 再相加 |
| AHK 用例数 | `grep -cE '^\s+Test_\w+\(' <f>` | 实跑数 `tail -8 tests/test_results.log`；实跑 = 静态 + `Setup`/`Teardown`，故略高 |
| AHK 套件数 | `grep -c '【测试套件】' tests/test_results.log` | — |

Rust 运行时口径：domain 136 / ipc-protocol 72 / application 163 / test-harness 3 / tauri 242 = 616
（`#[ignore]` 15）。`--all-targets` 下 criterion benches（`harness=false`）不注册为测试。

## 易误判点（做「陈旧引用清零」时必须注意）

1. `SkillManager` 两义：`AGENTS.md` 里的是 **AHK v2 类**（`domain/skill_manager.ahk`，仍存在）；
   `migration-guide.md` 的十余处是**迁移映射表的 AHK 侧列**（本就该保留）。
   只应清除「**Rust `asd-application` 侧**」的 `SkillManager` 引用。
2. **历史/归档文档严禁改写**：`docs/review/**`、`docs/superpowers/plans/**`、`.trae/specs/**`、
   `docs/code-review-report-*`、`docs/remediation-plan-*` 中出现已删文件名是**当时事实的记录**。
   清零检查只针对 9 份权威文档。
3. `joystick_input_utils.ahk` 在 AGENTS.md 妥协表中的提及是**正确内容**（A1 修复史），不是死链。
4. `asd-application/src/` 实际 8 文件：`backup_service`/`config_repository`/`error`/`group_service`/
   `lib`/`recording_service`/`state`/`time_format`。**无 `scheduler.rs`**。
5. `AppState` 真实字段见 `crates/asd-application/src/state.rs:80-92`（11 个，`config_state: RwLock<ConfigState>` 起），
   **不是**文档旧写的 `scheduler`/`config_repo`。

## BUG-6 双栈对齐（已完成）

AHK 侧 `_ValidateSuspiciousModeValues`（`infrastructure/config_validator.ahk`）对齐
`asd-domain::validator`。**改任一侧必须同步另一侧**，三处刻意差异：

1. 长度不匹配只在「序列 **多于** 按键」时告警（「少于」已由 `_ValidateArrayLength` /
   `_ValidateSubGroups` 输出同义 WARNING，避免重复刷屏）
2. 超长值只覆盖 `(MAX_REASONABLE_INTERVAL_MS, MAX_INTERVAL_MS]` —— 超过硬上界已由 ERROR 拦截
3. 子组下标 **1-based**（AHK 惯例），Rust 为 0-based，跨栈比对日志需 +1

**已知分歧（不修）**：热键长度 AHK 15 字符即 ERROR，比 Rust 256 字符 WARNING 更严，语义已覆盖。

**判定铁律**：`Validate()` 返回 ERROR+WARNING 混合数组，判定「是否致命」
**必须走 `ConfigValidator.FilterByType(errors, "ERROR")`**，绝不可用 `errors.Length > 0`
—— 后者会让仅含 WARNING 的合法配置无法导入/保存。
