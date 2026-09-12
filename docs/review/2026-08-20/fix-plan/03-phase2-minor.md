# 03 — Phase 2 次要优化方案 + Phase 3 回归验证方案

> **来源**：`docs/review/2026-08-20/fix-plan/00-issue-inventory.md`（问题清单与 P2 批量分组，唯一权威）+ `docs/code-review-report-2026-08-20.md` §5（Minor 项明细：位置/描述/根因/修复方案）
> **范围**：P2 = 46 项 Minor，按清单 §3 的 12 个批次（B1~B12）组织
> **性质**：只读规划文档，仅写入本文件，不修改任何 .ahk / .rs / .toml / .json 源码文件
> **相对时间框约定**：P2 = 长期 / 随迭代消化，不阻塞当前运行与发布（区别于 P0 立即、P1 尽快）

---

## 0. 总览与追溯性

### 0.1 批次-成员映射（46 项全覆盖，与 `00-issue-inventory.md` §3 完全一致）

| 批 | 主题名 | 成员编号 | 计数 |
|----|--------|---------|:----:|
| B1 | 冗余依赖与死代码清理 | T4-01、T4-02、T4-03、T5-07 | 4 |
| B2 | 错误类型与封装统一 | T4-06、T4-07、T4-08 | 3 |
| B3 | 校验权衡与默认值语义 | T4-05、T4-09 | 2 |
| B4 | 未登记妥协与规则豁免 | T2-05、T4-10、T5-05 | 3 |
| B5 | 并发/阻塞/基础设施健壮性 | T5-03、T5-04、T5-08、T5-09、T5-10、T5-12 | 6 |
| B6 | AHK 代码一致性 | T2-06、T2-08、T2-09、T2-10 | 4 |
| B7 | Rust 代码一致性（watchdog/bridge） | T5-06、T5-11、T5-13、T5-14 | 4 |
| B8 | AHK 健壮性补丁 | T3-07、T3-09 | 2 |
| B9 | 性能微调 | T3-08 + T6-12、T6-08、T6-09、T6-10、T6-11 | 5 |
| B10 | AGENTS.md 模块清单与结构补全 | T2-07 + T7-07、T7-06、T7-08、T7-09、T7-11 | 5 |
| B11 | 文档标识/表述一致性 | T7-10、T7-12、T7-13、T7-14 | 4 |
| B12 | 测试规范与口径收口 | T8-04、T8-05、T8-06、T8-07† | 4 |

校验：4 + 3 + 2 + 3 + 6 + 4 + 4 + 2 + 5 + 5 + 4 + 4 = **46** ✓

### 0.2 全局执行约定

- **提交粒度**：每批次独立一个 commit（遵循 Conventional Commits，`refactor/chore/docs/test(<scope>): <中文描述>`），使回滚可精确到批。
- **回滚机制（各批通用）**：`git revert <该批 commit>`；若尚未提交则 `git checkout -- <该批涉及文件>`。已改动的 Cargo.toml 需同时回退 `Cargo.lock`（`cargo check` 会自动重生成）。
- **验证基线**：任何批次落地后必跑「该批对应 crate 的 `cargo test -p <crate>`」或「对应 .ahk 语法检查 + `tests\run_all_tests.ahk`」，详见表内「测试验证方案」；全量回归统一由 Phase 3 兜底。
- **依赖关系**：B9（T6-09）与 P1 的「热路径日志限速（T3-05 + T6-03）」同文件（`json_serializer.ahk`/`error_system.ahk`）相交，建议在 P1 日志限速落地后再做 B9 的紧凑序列化，避免两次改动同一处；B12（T8-04 修改 `tests\run_all_tests.ahk`）与 CR1 所列 4 个「工作区未提交文件」之一同名，处置前必须先确认 CR1 阶段对该文件的意图（完成或撤销）。

---

## 1. 任务 A — Phase 2 次要优化方案（12 批次）

> 每批六要素：① 问题描述（概括成员 + 编号 + 位置）；② 批量修复步骤（有序，指向 file:line）；③ 测试验证方案；④ 回滚机制；⑤ 修复后效果评估标准；⑥ 责任角色 + 相对时间框。

---

### B1 冗余依赖与死代码清理（T4-01、T4-02、T4-03、T5-07）

**① 问题描述**
- `T4-01`：`crates/asd-domain/Cargo.toml:11` 声明 `tracing` 依赖但零使用，AGENTS.md 依赖表亦未登记。
- `T4-02`：`crates/asd-application/src/scheduler.rs:6-13` 已 `#[deprecated]` 的 `SkillManager` 为死代码，且 AGENTS.md 对该文件描述（`Arc<dyn IpcSender>`）与实际（普通结构体）严重不符。
- `T4-03`：`crates/asd-ipc-protocol/Cargo.toml:10` + `src/hotkey_merger.rs:33` 为仅 1 处 `debug!` 引入 `tracing`，依赖表未登记。
- `T5-07`：`src/infrastructure/watchdog.rs:55,100-101,108-116` `on_state_change` 回调字段为死代码，`set_state` 持锁同步触发回调有重入死锁隐患。

**② 批量修复步骤**
1. `grep -rn "SkillManager" asd-tauri/crates asd-tauri/src-tauri` 确认 `scheduler.rs` 无生产/测试调用后，删除 `crates/asd-application/src/scheduler.rs`；同步更新 `asd-application/src/lib.rs` 的 `mod scheduler` 声明（若有）。
2. `crates/asd-domain/Cargo.toml:11` 删除 `tracing` 依赖行；`crates/asd-ipc-protocol/Cargo.toml:10` 删除 `tracing` 依赖行。
3. `crates/asd-ipc-protocol/src/hotkey_merger.rs:33` 的 `debug!` 改为「返回值暴露丢弃计数」或直接删除该日志，消除对 tracing 的最后引用。
4. `src/infrastructure/watchdog.rs:55,100-101,108-116` 删除 `on_state_change` 字段及其 setter；若业务仍需要回调通知，改为「先 clone 回调、释放锁后再调用」，杜绝持锁重入。
5. AGENTS.md 同步：依赖表（§Dependencies）移除 asd-domain/asd-ipc-protocol 的 `tracing` 登记（或补齐登记后取消，二选一，推荐「移除」以保持最小依赖面）；Key Files 表中删除/改写 `scheduler.rs` 描述。

**③ 测试验证方案**：`cd asd-tauri; cargo check --workspace; cargo build --workspace; cargo test -p asd-domain; cargo test -p asd-ipc-protocol; cargo test -p asd-application`。

**④ 回滚机制**：按「全局执行约定」回滚本批 5 个文件；若误删依赖致编译失败，`git revert` 后 `cargo fetch` 自动恢复 `Cargo.lock`。

**⑤ 效果评估标准**：`cargo tree -p asd-domain -p asd-ipc-protocol` 无 `tracing`；`grep -rn "deprecated" asd-application/src` 无命中；watchdog `on_state_change` 全库零引用；AGENTS.md 依赖表与实际一致（Phase 3 §B2 复核）。

**⑥ 责任角色 + 时间框**：主责 Rust 侧（crates）+ 文档负责人；P2 长期，随一次迭代顺带清理。

---

### B2 错误类型与封装统一（T4-06、T4-07、T4-08）

**① 问题描述**
- `T4-06`：`crates/asd-application/src/config_repository.rs:16` 的 `atomic_write` 为自由函数而非 `ConfigRepository` 方法，`recording_service.rs:2` 直接跨层引用，封装口径不一致。
- `T4-07`：`config_repository.rs:105,119,126,148` 错误返回类型不统一（`load_from_file_checked` 返回 `ConfigLoadError`，其余方法返回 `String`）。
- `T4-08`：`crates/asd-application/src/error.rs:42-44,58-61` `AppError::message()` 对 Io 返回空串，序列化靠手动分支特判，三处需同步维护。

**② 批量修复步骤**
1. `config_repository.rs:16` 将 `atomic_write` 改为 `ConfigRepository` 的 `pub fn`（或 `pub(crate)`）；`recording_service.rs:2` 改调 `repo.atomic_write(...)`，消除对自由函数/跨层引用。
2. `config_repository.rs:105,119,126,148` 统一错误返回为类型化错误（本批以 `ConfigLoadError` 为基准）；短期若不能全量统一，先在方法签名处加注释说明分工与迁移方向（避免 P2 长期遗留又无说明）。
3. `error.rs:42-44,58-61` `AppError::message()` 改返回 `Cow<'_, str>`；删除 `Serialize` 中对 Io 的手动空串特判（序列化统一走 `message()`）。
4. 全量 `cargo clippy` 清理因签名改动产生的调用方适配。

**③ 测试验证方案**：`cargo test -p asd-application`（重点 `config_repository` 相关用例）；`cargo clippy -p asd-application -- -D warnings`。

**④ 回滚机制**：本批统一 commit，`git revert` 一次性回退。

**⑤ 效果评估标准**：`atomic_write` 仅以方法形式出现；`config_repository` 各错误返回路径类型一致（或均有注释说明）；`AppError::message()` 对 Io 返回非空。

**⑥ 责任角色 + 时间框**：Rust 侧（asd-application）；P2 长期，建议与 B1 同一次迭代合并处理（同 crate）。

---

### B3 校验权衡与默认值语义（T4-05、T4-09）

**① 问题描述**
- `T4-05`：`crates/asd-domain/src/validator.rs:152-158` 无效热键键名仅 `warning` 不 `error`（不阻断保存），该权衡未在文档记录。
- `T4-09`：`crates/asd-domain/src/config.rs:63` `Config::default_config()` 的 `version` 仍为 `"3.0"`，与 v4.0 不符。

**② 批量修复步骤**
1. `validator.rs:152-158` 在 `warning` 分支补注释说明「热键格式仅 warning 级建议，不阻断保存」及原因（避免误报）；并在 AGENTS.md（Rust 校验相关章节或「常见问题」）登记该权衡。
2. `config.rs:63` `version` 改为 `"4.0"`（或与 `workspace.package.version` 同源）；`grep -rn '"3.0"' asd-tauri/crates asd-tauri/src-tauri` 排查其余默认值/兼容测试硬编码，同步评估 `config_compat_tests`。

**③ 测试验证方案**：`cargo test -p asd-domain`；执行 `config_compat_tests`（`cargo test -p asd-tauri config_compat`，路径见 Phase 3）。

**④ 回滚机制**：`git revert` 本批 commit。

**⑤ 效果评估标准**：默认版本号不再出现 `3.0`；`validator.rs:152-158` 权衡有注释 + 文档可追溯。

**⑥ 责任角色 + 时间框**：Rust 侧（asd-domain）+ 文档负责人；P2 长期，低风险可随时并入任意迭代。

---

### B4 未登记妥协与规则豁免（T2-05、T4-10、T5-05）

**① 问题描述**
- `T2-05`：`infrastructure/joy_sender.ahk:17` 反向 `#Include "../domain/interfaces.ahk"`（方向正确但未在 AGENTS.md 妥协表登记）。
- `T4-10`：`crates/asd-application/src/state.rs:882,900,901`、`tests/*.rs` 测试代码直接 `std::fs`，与「std::fs 仅 ConfigRepository」字面规则有张力，缺测试豁免说明。
- `T5-05`：`src/lib.rs:117-138,140-174` 心跳/接受循环/关机直接操作 `IpcManager`，未走 `IpcSender` trait，仅回调注册有 M31 例外，此三处未登记。

**② 批量修复步骤**（本批为纯文档/注释改动，无源码逻辑变更）
1. AGENTS.md「AHK 已知架构妥协」妥协 #1 补记 `joy_sender → domain/interfaces.ahk`（允许的反向依赖）。
2. AGENTS.md「纯逻辑 crate 禁止 std::fs（仅 ConfigRepository）」条目补豁免：「测试代码（`#[cfg(test)]`、`tests/`）允许直接 `std::fs` 构造固件」。
3. `src/lib.rs:117-138,140-174` 补 M31 同款例外注释说明「生命周期逻辑（心跳/接受循环/关机）默认与命令发送不同，允许直接操作 IpcManager」；或选择将其下沉为 `IpcManager` 自身方法（若下沉，纳入 B5 一起评估以避免重复改动）。
4. 交叉核对该三项在「已知架构妥协」章节均有一一行可读位置。

**③ 测试验证方案**：无源码改动 → `cargo check --workspace` + AHK 语法检查确认未破坏；重点核对 AGENTS.md 文本与代码一致（`grep` 三处登记点）。

**④ 回滚机制**：`git revert`（仅文档/注释，回退零风险）。

**⑤ 效果评估标准**：三处妥协/豁免在 AGENTS.md 中可 `grep` 命中；Phase 3 §B2 的文档一致性清单无「未登记妥协」遗留。

**⑥ 责任角色 + 时间框**：架构评审负责确认豁免边界，文档负责人落地；P2 长期。

---

### B5 并发/阻塞/基础设施健壮性（T5-03、T5-04、T5-08、T5-09、T5-10、T5-12）

**① 问题描述**
- `T5-03`：`src/bridge.rs:47,76,196,206,216` `IpcBridge`/`WatchdogBridge` 用 `Handle::current().block_on`，脱离 tokio 运行时上下文会 panic。
- `T5-04`：`src/infrastructure/watchdog.rs:781,214,594-597` `spawn_child` 在 async 循环内持锁同步执行 `taskkill` + `Command::spawn` 阻塞 I/O。
- `T5-08`：`src/infrastructure/ipc.rs:76-85,180` IPC auth token 由时间戳派生、比较非恒定时间。
- `T5-09`：`src/lib.rs:117-138,663` 无单实例保护，二次启动 listener 创建失败 + executor 错连首实例。
- `T5-10`：`src/infrastructure/watchdog.rs:417-461` `graceful_shutdown` 持 watchdog 锁横跨多个 await（约 5s+），轮询被阻塞。
- `T5-12`：`src/lib.rs:31` 与 `ahk_executor/ipc_client.ahk:20` 管道名跨语言无一致性保障。

**② 批量修复步骤**（本批改动面较大，建议拆分多个小 commit，但归一个批次验收）
1. `T5-03`：`bridge.rs` 的 5 处 `Handle::current().block_on` 改为 `tauri::async_runtime::block_on`，或在该 trait 实现顶部补注释明确「必须在 Tauri async runtime 上下文内调用」。
2. `T5-04`：`watchdog.rs:781,214,594-597` 将持锁的 `taskkill` + `Command::spawn` 包进 `tokio::task::spawn_blocking`（或改用 `tokio::process::Command`），锁内仅保留必要的最小临界区。
3. `T5-08`：`ipc.rs:76-85` token 生成改用随机字节（`uuid`/`getrandom`）；`ipc.rs:180` 比较改为恒定时间比较（或明确注释保留退避缓解作为折中）。
4. `T5-09`：引入 `tauri-plugin-single-instance`（聚焦已有窗口并退出二次实例）；`src/lib.rs:117-138,663` 对应初始化/回调接入。
5. `T5-10`：`watchdog.rs:417-461` 将 `wait_for_exit` 轮询逻辑拆到锁外执行，仅在锁内切换状态；或按报告方案文档化阶段性阻塞。
6. `T5-12`：管道名常量收敛到 `infrastructure/ipc.rs` 并由 Rust 侧单一导出；新增集成/正则自检守护 Rust 常量 vs AHK `ipc_client.ahk:20` 硬编码字符串一致（可放入 `ipc_tests`）。
7. 全量 `cargo clippy` + `cargo fmt` 收尾。

**③ 测试验证方案**：`cargo test -p asd-tauri --lib`（重点 ipc_tests、watchdog 集成测试）；`cargo test --workspace`；手动验证二次启动仅聚焦首实例、非运行时上下文无 panic。

**④ 回滚机制**：本批按子改动多 commit，逐条 `git revert`（T5-09 单实例插件若引入依赖面扩展，可独立回滚而不影响其余 5 项）。

**⑤ 效果评估标准**：`cargo clippy --workspace` 无相关 warning；watchdog 集成测试全绿；`grep -n "block_on" src/bridge.rs` 不再出现裸 `Handle::current()`；管道名仅一处权威定义并受自检守护（Phase 3 §B3 核对 `I6` 类回归清零）。

**⑥ 责任角色 + 时间框**：Rust 侧（src-tauri，主责）+ AHK 执行器侧（仅 T5-12 配合）；P2 长期，可按「T5-04/T5-10/T5-12 → T5-08 → T5-03/T5-09」分步消化。

---

### B6 AHK 代码一致性（T2-06、T2-08、T2-09、T2-10）

**① 问题描述**
- `T2-06`：`infrastructure/config_store.ahk:82-98`（`Set()` 直接引用赋值）vs `:36-65`（`Save()` 用 `deepclone`），两条写入路径防御拷贝策略不一致。
- `T2-08`：`domain/skill_manager.ahk:453-458,470-473` `_resetEmergencyTimer` 未在静态属性区声明，靠 `HasProp` 守卫。
- `T2-09`：`domain/skill_manager.ahk:318-379` `_StartGroupExecution` 嵌套闭包 + `Bind` 递归约 60 行/5 层，圈复杂度高。
- `T2-10`：`presentation/group_editor.ahk`（81 方法）、`presentation/webview2_manager.ahk`（60 方法）、`domain/skill_group.ahk`（约 920 行）超大类 God Object 倾向。

**② 批量修复步骤**
1. `T2-06`：`config_store.ahk:82-98` 的 `Set()` GroupSettings/HoldSettings 分支与 `Save()`（36-65）对齐改用 `deepclone`，统一写入路径防御策略。
2. `T2-08`：`skill_manager.ahk` 静态属性区补 `static _resetEmergencyTimer := 0`，删除 `453-458,470-473` 处的 `HasProp` 守卫。
3. `T2-09`：`skill_manager.ahk:318-379` 提取 `_ExecuteTick(gId, execId)` 独立私有方法，用显式 `SetTimer` 回调取代自绑定递归，将 5 层嵌套摊平到 2 层以内。
4. `T2-10`：**渐进式拆分，不要求一次到位**。按报告建议方向做首刀：`group_editor.ahk` 拆出「热键编辑」子模块、`webview2_manager.ahk` 拆出「Bridge 消息路由」子模块、`skill_group.ahk` 拆出「模式执行器」；拆分时保持对外静态方法签名不变，避免破坏 `#Include` 调用方。
5. 所有改动后跑 AHK 语法检查 + 全套测试。

**③ 测试验证方案**：逐文件 `/ErrorStdOut` 语法检查（退出码 0/2）；`& $ahk tests\run_all_tests.ahk` 全套（重点 test_application、test_presentation、test_domain、test_infrastructure）。

**④ 回滚机制**：按文件分批 commit（T2-06/T2-08 一组，T2-09 一组，T2-10 首刀一组），逐组 `git revert`。

**⑤ 效果评估标准**：`config_store` 两条写入路径拷贝策略一致；`skill_manager` 静态属性区声明完整（无 `HasProp` 兜底）；`_StartGroupExecution` 圈复杂度下降（人工评审确认 ≤ 3 层嵌套）；God Object 首刀拆分完成且全套 AHK 测试通过。

**⑥ 责任角色 + 时间框**：AHK 侧（主程序 domain/presentation）；P2 长期，T2-06/T2-08 低风险可先做，T2-09/T2-10 随迭代逐步消化。

---

### B7 Rust 代码一致性（T5-06、T5-11、T5-13、T5-14）

**① 问题描述**
- `T5-06`：`src/infrastructure/watchdog.rs:518` `JOBOBJECTINFOCLASS(9)` 魔法数字。
- `T5-11`：`src/lib.rs:408,757` 生产代码 `Arc::get_mut().expect` + 入口 `expect`（M33 已登记技术债）。
- `T5-13`：`src/infrastructure/watchdog.rs:1056` `#[test]` 属性缩进 8 空格、其下 fn 4 空格，格式不齐。
- `T5-14`：`src/infrastructure/watchdog.rs:361-382,390-403` `begin_restart`/`reset_to_restart` 终止子进程后只 `kill()` 未 `wait()`。

**② 批量修复步骤**
1. `T5-06`：`watchdog.rs:518` 改用具名常量（查 `windows` crate 的 `JOBOBJECTINFOCLASS` 枚举），或最小方案加注释说明 `9` 语义。
2. `T5-11`：`lib.rs:408,757` 按 M33 方案将 `config_path` 注入移入 `AppState::new(...)` 构造参数，消除 `Arc::get_mut().expect`；若短期不能，降级为 `if let` + 返回 `AppError`（不再 `expect`）。
3. `T5-13`：`cargo fmt` 全仓格式化并纳入 CI 格式门禁。
4. `T5-14`：`watchdog.rs:361-382,390-403` 抽取 `kill_and_reap` 辅助方法，三处（`begin_restart`/`reset_to_restart`/`kill_child`）统一复用（kill + wait）。

**③ 测试验证方案**：`cargo fmt --all -- --check`（应为 0 差异）；`cargo test -p asd-tauri --lib`（watchdog 相关测试 + `kill_and_reap` 单测）。

**④ 回滚机制**：`git revert`（`cargo fmt` 产生的纯格式化 diff 若混杂其他批次改动，注意提交边界；建议本批先格式化再提交）。

**⑤ 效果评估标准**：无魔法数字；`grep -n "Arc::get_mut" src/lib.rs` 无命中；`cargo fmt --check` 通过；子进程终止路径统一走 `kill_and_reap`。

**⑥ 责任角色 + 时间框**：Rust 侧（src-tauri）；P2 长期，T5-06/T5-13/T5-14 低风险随迭代随手修，T5-11 与 M33 技术债一起排期。

---

### B8 AHK 健壮性补丁（T3-07、T3-09）

**① 问题描述**
- `T3-07`：`infrastructure/ipc_channel.ahk:181-184` `_OnReceived` 监听器 `try callback(msgObj)` 无 catch，异常向上传播中断消息分发。
- `T3-09`：`domain/key_recorder.ahk:273-302,312-323` `_mouseHotkeys` 标志在注册完成后才置位，`_InstallMouseHooks` 中途异常时已注册钩子残留。

**② 批量修复步骤**
1. `T3-07`：`ipc_channel.ahk:181-184` 为 `callback(msgObj)` 补 `catch` 并记 WARNING（与 KeyRecorder `onEvent` 处理一致），保证单条消息异常不中断分发循环。
2. `T3-09`：`key_recorder.ahk:273-302,312-323` 修正标志语义——`_RemoveMouseHooks` 无条件遍历注销一轮（而非依赖 `_mouseHotkeys` 早退）；或改为「每注册成功一个钩子即维护状态」，使部分注册可被正确回滚。

**③ 测试验证方案**：`& $ahk tests\run_all_tests.ahk`（重点 test_key_recorder、test_infrastructure 相关）；针对性验证：向 `_OnReceived` 注入会抛异常的 callback 确认分发不中断。

**④ 回滚机制**：`git revert`（两处独立可回滚）。

**⑤ 效果评估标准**：IPC 消息分发单条异常不中断整体；钩子卸载在「部分注册」状态下无残留。

**⑥ 责任角色 + 时间框**：AHK 侧（infrastructure/domain）；P2 长期，风险低可尽早并入。

---

### B9 性能微调（T3-08 + T6-12、T6-08、T6-09、T6-10、T6-11）

**① 问题描述**
- `T3-08 + T6-12`：`presentation/webview2_manager.ahk:1040-1081,408,438-439`、`infrastructure/config_store.ahk:30-48,70`、`application/group_service.ahk:140` —— `_BridgeImportConfig` 对同一 jsonStr 解析两次；保存路径多层冗余 deepclone。
- `T6-08`：`infrastructure/ipc_channel.ahk:66-86,89-109,192-204,112-170` 预留文件管道每次 Send/Emit 做 FileGetSize + 整条 Stringify + FileAppend。
- `T6-09`：`infrastructure/json_serializer.ahk:17-21,49-88`、`infrastructure/error_system.ahk:199` 日志用默认 `indent=2` 生成多行 pretty JSON。
- `T6-10`：`infrastructure/utils.ahk:41-55` `_GetField` 对 JSON 字符串值每次重复 `JSONParser.Parse`。
- `T6-11`：`domain/mode_registry.ahk:317,334,415,434` 序列执行器冗余 `HasProp("_nextStepTime")` 检查。

**② 批量修复步骤**
1. `T3-08 + T6-12`：`webview2_manager.ahk:1040-1081` 复用同一次 `JSONParser.Parse` 结果，删除二次解析；保存路径 `config_store.ahk:30-48,70` / `group_service.ahk:140` 逐层评估并去掉冗余 deepclone（保留必要的一层防御拷贝）。
2. `T6-08`：在 `ipc_channel.ahk` 顶部明确标注该文件管道接口为「预留/低优先级」，避免继续被误当热路径；如需保留则改为内存队列 + 定时刷新（二选一，本批优先做「标注 + 冻结」）。
3. `T6-09`：日志写入路径（`json_serializer` 调用点含 `error_system.ahk:199`）改用紧凑序列化（`indent:=0`），展示路径保留 pretty。**依赖 P1 日志限速（T3-05+T6-03）先行**，避免重复改动同文件。
4. `T6-10`：`utils.ahk:41-55` `_GetField` 按对象指针缓存解析结果（或要求调用方先解析）；注意与 B1/`T2-03`（utils↔json_parser 环）的边界一致，避免重新引入耦合。
5. `T6-11`：`mode_registry.ahk:317,334,415,434` 直接访问 `group._nextStepTime`，删除冗余 `HasProp` 分支。

**③ 测试验证方案**：`& $ahk tests\run_all_tests.ahk` 全套；针对 `webview2_manager`/`ConfigStore` 补「导入解析次数 = 1」的断言（若已有桥接测试）；性能冒烟：确认无功能回归即可，不强制 benchmark。

**④ 回滚机制**：按子项分批 commit，逐条 `git revert`（T6-09 与 P1 交叉，回滚需注意归属批次）。

**⑤ 效果评估标准**：`_BridgeImportConfig` 解析 1 次；保存路径 deepclone 层级减少且测试全绿；日志为单行紧凑 JSON；`_nextStepTime` 直接访问无 `HasProp`。

**⑥ 责任角色 + 时间框**：AHK 侧（presentation/infrastructure/domain）；P2 长期，T6-08/T6-11 低风险先做，T6-09 待 P1 落地后做。

---

### B10 AGENTS.md 模块清单与结构补全（T2-07 + T7-07、T7-06、T7-08、T7-09、T7-11）

**① 问题描述**
- `T2-07 + T7-07`：`AGENTS.md` Key Files/Subdirectories 表、L58-62 分层表 AHK 模块清单不完整：infrastructure 缺 `config_io/joy_sender/migration_logger`，domain 缺 `joystick_executor/joystick_input/key_recorder/key_validator`，application 缺 `backup_service`。
- `T7-06`：`AGENTS.md` L1220-1227 `IpcMessage` 示例仅 4 字段，实际 `message.rs` 有 9 字段，未标注简化。
- `T7-08`：`AGENTS.md` L72「AHK 已知架构妥协」第 3 条实为 Rust 层面妥协，放错章节且与 L142 重叠。
- `T7-09`：`AGENTS.md` L251 tests/ 根目录「22 个核心文件 / 15 个核心测试文件」与列举不吻合（实际 16 个 test_*.ahk）。
- `T7-11`：`AGENTS.md` L37-47、L109-111 Rust Key Files/目录表未登记 `backup_service.rs/group_service.rs/recording_service.rs/time_format.rs`、`infrastructure/shutdown.rs`、`tests/bridge_tests.rs`、`application/backup_service.ahk`。

**② 批量修复步骤**（纯文档，均针对 `AGENTS.md`）
1. `T2-07 + T7-07`：按 `infrastructure/`、`domain/`、`application/` 目录实际文件清单（`Get-ChildItem *.ahk`）补全三层模块清单与 Key Files/Subdirectories 表、L58-62 分层表。
2. `T7-06`：L1220-1227 补齐 `IpcMessage` 9 字段示例，或加「完整定义见 `asd-ipc-protocol/src/message.rs`」注释。
3. `T7-08`：L72 第 3 条移入「Rust/Tauri 已知架构妥协」表或标注「（Rust，误置于此）」，消除与 L142 的重叠。
4. `T7-09`：L251 改为「16 个 test_*.ahk + 6 个框架/配置文件 = 22」的准确口径。
5. `T7-11`：L37-47、L109-111 补入上述新增模块到 Key Files 与架构子树表。
6. 交叉核对：全部改动后 `grep` 确认清单与磁盘文件一一对应（可写一个一次性校验脚本，见 Phase 3 §B2）。

**③ 测试验证方案**：无代码改动；`grep`/`Get-ChildItem` 对比模块清单完整性；Phase 3 §B2 文档口径收敛清单复核通过。

**④ 回滚机制**：`git revert`（仅 `AGENTS.md` 单文件，独立 commit）。

**⑤ 效果评估标准**：AHK/Rust 模块清单与目录实际内容 1:1；`IpcMessage` 示例字段数与 `message.rs` 一致（或明确标注简化）；妥协表无错章；tests 计数与列举吻合。

**⑥ 责任角色 + 时间框**：文档负责人（主责）+ 架构评审确认清单范围；P2 长期，可随任意文档维护迭代一并完成。

---

### B11 文档标识/表述一致性（T7-10、T7-12、T7-13、T7-14）

**① 问题描述**
- `T7-10`：`AGENTS.md` L1267 vs `tauri.conf.json` L5 vs `developer-guide.md` L804-805 应用数据目录/标识三处不一致（com.asd.skillmanager / com.asd.tauri / asd-tauri）。
- `T7-12`：`docs/code-review-report-2026-08-03.md` L15、L17、L39 对 AGENTS.md 的论断（4-crate、13 commands、test-manifest 存在）现已失效，未加勘误。
- `T7-13`：`asd-tauri/docs/test-map.md` L175-182 E2E helpers 表未登记 `ahk_path.js`、`error_utils.js` 及 `__tests__/`。
- `T7-14`：`AGENTS.md` L356、`test-map.md` L168 vs `AGENTS.md` L1239-1252 E2E「modes（7）：7 种执行模式」与「支持 10 种模式」矛盾。

**② 批量修复步骤**
1. `T7-10`：以 `tauri.conf.json` L5 的 `identifier`（`com.asd.tauri`）为准，统一 `AGENTS.md` L1267 与 `developer-guide.md` L804-805 的标识/数据目录表述。
2. `T7-12`：在 `docs/code-review-report-2026-08-03.md` 首页或相关条目加勘误标注「部分论断已于 2026-08-04 后失效（现为 5-crate workspace、34 个 tauri command、test-manifest 已移除）」，不重写历史内容。
3. `T7-13`：`test-map.md` L175-182 及相关「测试辅助脚本」节补登记 `ahk_path.js`、`error_utils.js`、`__tests__/` 的路径/用途/引用方。
4. `T7-14`：`AGENTS.md` L356、`test-map.md` L168 与 `AGENTS.md` L1239-1252 统一为「7 种（E2E 覆盖）；系统共 10 种，官方支持执行模式见 AGENTS.md 执行模式表，joystick_* 未纳入 E2E」。
5. 交叉核对「执行模式表」与 E2E 覆盖表两处分别标注「系统能力」与「E2E 覆盖」，避免再次混淆。

**③ 测试验证方案**：无代码改动；`Select-String` 全库检索三处标识确保统一；Phase 3 §B2 文档收敛清单复核通过。

**④ 回滚机制**：`git revert`。

**⑤ 效果评估标准**：标识 `com.asd.tauri` 三处一致；历史报告带勘误；test-map E2E helpers 完整；执行模式「系统能力 vs E2E 覆盖」两口径无冲突。

**⑥ 责任角色 + 时间框**：文档负责人；P2 长期。

---

### B12 测试规范与口径收口（T8-04、T8-05、T8-06、T8-07†）

**① 问题描述**
- `T8-04`：`tests/run_all_tests.ahk` 批量运行入口缺 `OnError` 回调，单 suite 崩溃会弹窗中断整体批量运行。
- `T8-05`：`AGENTS.md`（"16 ignored"）、`test-map.md:84`、`config_compat_tests.rs:3` `#[ignore]` 实测 19+ 与文档 16/15 三处不一致；`MAIN_CONFIG_JSON` 未登记为固件。
- `T8-06`：`tests/fixtures/` 缺 joystick 3 模式配置样本；`tests/test_ahk_executor/test_joystick.ahk:463` 硬编码 `"joystick_periodic"` 字符串。
- `T8-07†`：Task 8 自报 Minor 第 4 条，分报告正文未展开，编号待定占位。

**② 批量修复步骤**
1. `T8-04`：`tests/run_all_tests.ahk` 顶部补 `#ErrorStdOut "UTF-8"` + `#Warn VarUnset/Unreachable, OutputDebug` + `OnError` 回调（FileAppend 到 stdout，返回 true）。**前置**：先确认 CR1 阶段对该「工作区未提交文件」的处置意图（完成或撤销）。
2. `T8-05`：用 `asd-tauri/scripts/analyze-tests.ps1`（或 `grep -c "#\[ignore\]"`）自动统计 `#[ignore]` 数，回写 `AGENTS.md` "16 ignored" 与 `test-map.md:84` 为同一实测值；在 `asd-tauri/tests/fixtures/` 与 test-map「测试固件」节补登记 `MAIN_CONFIG_JSON`（`config_compat_tests.rs:3` 引用）。
3. `T8-06`：在 `tests/fixtures/` 补 `joystick_config.json`（或在 `sample_config.json` 增补 joystick 3 模式样本，并登记 fixtures 规范）；`test_joystick.ahk:463` 改从 fixture 派生 `"joystick_periodic"` 等模式名，消除硬编码。
4. `T8-07†`：**执行前先回查 `docs/review/2026-08-20/task-8-tests.md`，定位该第 4 条 Minor**；若与已有条目重复则并入并回填编号，若为新问题则在本清单标注并纳入本批处置（不得无说明丢失）。
5. 收口：任一条完成后即触发 Phase 3 对应验证。

**③ 测试验证方案**：`& $ahk tests\run_all_tests.ahk` 全套确认批量运行不弹窗；`cargo test -p asd-tauri`（含 `config_compat_tests`）；`grep "#\[ignore\]"` 计数与文档一致。

**④ 回滚机制**：`git revert`（T8-04 与 CR1 工作区文件重叠，回滚需谨慎，建议待 CR1 处置定稿后再提交 T8-04）。

**⑤ 效果评估标准**：`run_all_tests.ahk` 含完整错误接管指令；三处 `#[ignore]` 口径一致；fixtures 覆盖 joystick 三模式；`T8-07†` 已定位并处置（不留占位）。

**⑥ 责任角色 + 时间框**：测试负责人（主责）+ 文档负责人（口径回写）；P2 长期，建议与 Phase 3 口径收敛（§B2）同期完成以保证测试统计唯一权威来源。

---

## 2. 任务 B — Phase 3 回归验证方案

> **准入条件**：Phase 1（P0 Critical + P1 Important，含 CR1 对工作区未提交文件的处置）与 Phase 2（本文件 B1~B12）均已提交并解冲突后，方可进入全量回归。
> **执行顺序**：V-01 语法 → V-02 AHK 全套 → V-03/V-04 Rust 编译与测试 → V-05~V-07 Miri → V-08 clippy → V-09 fmt → V-10~V-13 E2E → V-14 汇总跑 → V-15 覆盖率。语法/编译类失败优先于逻辑测试处理。

### 2.1 全量回归测试矩阵

> 统一常量：`$ahk = "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"`；`$root = "d:\1demo\AutoHotkeydemo"`；`$tauri = "$root\asd-tauri"`。

| ID | 验证项 | PowerShell 命令 | 通过标准 | 不通过处置 |
|----|--------|----------------|---------|-----------|
| V-01 | AHK v2 全量语法检查（加载时错误） | `$ahk="D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"; $root="d:\1demo\AutoHotkeydemo"; $err="$root\asd_syntax.err"; $bad=@(); Get-ChildItem "$root" -Recurse -Filter *.ahk | Where-Object { $_.FullName -notmatch '\\lib\\' } | ForEach-Object { $p=Start-Process -FilePath $ahk -ArgumentList "/ErrorStdOut",$_.FullName -WorkingDirectory $root -NoNewWindow -Wait -PassThru -RedirectStandardError $err; if($p.ExitCode -eq 2){ $bad += $_.FullName; Get-Content $err } }; if($bad.Count -gt 0){ Write-Host "SYNTAX FAIL: $($bad -join '; ')"; exit 1 } else { Write-Host "ALL AHK SYNTAX OK" }` | 所有 .ahk 退出码非 2 | 定位失败文件 → 回退到对应批次（多为 B6/B8/T8-04）checklist 重改 |
| V-02 | AHK v2 测试全套 | `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" "d:\1demo\AutoHotkeydemo\tests\run_all_tests.ahk"` | 0 失败；无弹窗中断（T8-04 生效） | 按失败 suite 回溯（test_*）→ 对应批次重改 |
| V-03 | Rust 全仓编译 | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo build --workspace` | 退出码 0 | 编译错误 → 回退 B1/B2/B5/B7 相关改动 |
| V-04 | Rust 全仓测试 | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo test --workspace` | 全部通过（ignored 除外） | 失败用例 → 映射到对应批次（Rust 侧 B1/B2/B3/B5/B7/B12） |
| V-05 | Miri（asd-domain） | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo +nightly miri test -p asd-domain` | 0 UB、全部通过 | UB/失败 → 回退 B3 及 P1 校验改动 |
| V-06 | Miri（asd-ipc-protocol） | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo +nightly miri test -p asd-ipc-protocol` | 0 UB、全部通过 | 回退 B1/B7 相关 |
| V-07 | Miri（asd-application） | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo +nightly miri test -p asd-application -- --skip config_repository --skip save_config --skip load_from` | 0 UB、通过（跳过 I/O 用例） | 回退 B2 |
| V-08 | Clippy | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo clippy --workspace --all-targets -- -D warnings` | 0 warning | 修 warning → 回退对应批次 |
| V-09 | 格式化门禁 | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo fmt --all -- --check` | 0 diff（含 T5-13） | `cargo fmt --all` 后重新进入对应批次（注意提交边界） |
| V-10 | E2E 前置：release 构建 | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo build --release` | 退出码 0 | 回退 Phase 1/2 编译相关改动 |
| V-11 | E2E 前置：tauri-driver | `cargo install tauri-driver --locked`（一次性，已装可跳过） | 安装成功 | 记录环境缺失，重试 |
| V-12 | E2E 依赖安装 | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri\e2e"; npm install` | 退出码 0 | 网络/依赖错误 → 记录并不计为代码回归 |
| V-13 | E2E 全套（9 suite/53 用例） | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri\e2e"; npm test` | 9 suite 全绿；跳过项（binary 缺失）不算 fail | 失败用例 → `appendKnownIssue` 记录到 `e2e-known-issues.md`，回溯对应批次；优先回退 B5/B12 |
| V-14 | 汇总测试运行 + JUnit + 覆盖率 + 分析 | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; .\scripts\run-tests.ps1 -JUnit -Coverage -Analyze` | 测试通过 + 覆盖率报告生成（`test-results/`、`coverage/`） | 查看 `test-results/` 与 `test-map.md` 口径收敛（§2.2） |
| V-15 | 覆盖率（独立口径） | `Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; cargo llvm-cov --workspace --html --output-dir coverage/; cargo llvm-cov --workspace --lcov --output-path lcov.info` | HTML/lcov 生成；纯逻辑 crate 覆盖率维持在 96.57% 附近（不显著回退） | 覆盖率显著下降 → 定位新增未覆盖分支 → 补测或回退 |

### 2.2 文档同步与统计口径收敛（确立单一权威来源）

**单一权威来源**：`asd-tauri/docs/test-map.md` 为**测试统计**唯一权威；`AGENTS.md` 为**架构/执行模式/依赖**唯一权威，其余文档（TESTING.md、developer-guide.md、migration-guide.md）一律「引用权威来源，不自行复制数字」。

| 口径项 | 现状冲突 | 收敛目标 | 权威来源 | 关联修复 |
|--------|---------|---------|---------|---------|
| Rust 测试总数 | AGENTS「592」 vs test-map「609」 vs TESTING「506」 | 以 `#[test]` 属性实录为准，AGENTS/TESTING 一律指回 test-map | test-map.md | T7-03、T7-05、B12(T8-05) |
| AHK 执行器口径 | AGENTS「244 个 Test_ 方法」 vs test-map/TESTING「467 测试」 | 分别标注 `Test_` 方法数 与「测试用例/断言数」两口径，注明差异 | test-map.md（实际为 `tests/test_ahk_executor/*.ahk`） | T7-05 |
| test-map 明细 vs 汇总 | 明细小计=153 vs 汇总 217 差 63；asd-ipc-protocol 明细 71 vs 汇总 72 | `重跑统计 → 小计 = 明细之和 = 汇总` | test-map.md（按文档自带统计命令） | T7-04 |
| AGENTS.md 依赖表 | asd-domain/asd-ipc-protocol 登记 tracing（B1 后应移除或明确） | 依赖表与 `Cargo.toml` 1:1 | AGENTS.md + Cargo.toml | T4-01、T4-03、B1 |
| 执行模式表 | 「modes（7）」 vs 「支持 10 种模式」 | 明确「系统能力（10/执行模式表） vs E2E 覆盖（7）」两口径 | AGENTS.md + test-map.md | T7-14、B11 |
| AGENTS 头部时间戳 | Updated 2026-05-30 vs 正文「截至 2026-08-04」 | 统一为本次 Fix Plan 落地日期（2026-08-20 之后） | AGENTS.md 头部 | T7-05 |

**收敛后验收命令**：
- `grep -rn "592\|609\|506" d:\1demo\AutoHotkeydemo\asd-tauri\TESTING.md d:\1demo\AutoHotkeydemo\AGENTS.md` → 不再存在相互冲突的裸数字（仅允许「以 test-map.md 为准」引用）。
- `grep -c "#\[test\]"`（按 crate 逐文件）与 test-map 明细逐行比对 → 一致。

### 2.3 历史修复核对表复核（清零项）

复核对象：§3.2「需二次关注的三项」，须确保以下被清零、无「引入回归」遗留：

| 编号 | 目标状态 | 复核手段 | 判定 |
|------|---------|---------|------|
| C6（部分修复） | 完全修复 | `Select-String -Path "d:\1demo\AutoHotkeydemo\tests\test_error_captor.ahk" -Pattern "OnError"` 有命中；且 `grep` 全 root 测试文件均含 OnError | 0 个测试文件缺 OnError |
| I1（引入回归） | 回归消除 | Phase 1（CR1 处置）恢复 `main.ahk` 的 `#Include "application\backup_service.ahk"` 后，`grep -n "backup_service" main.ahk` 命中；运行期 `BackupService` 可解析（V-02 无 `Unknown class`） | 运行时无未定义类 |
| I6（引入回归） | 回归消除 | Phase 1 后 `backup_core.ahk:70` 改调 `ConfigIO.ExportToFile`、`main.ahk` 恢复 `config_io.ahk` include、`config_service.ahk:412-417` 全局包装清理；分层测试 `Test_BackupCore_NotCallExportConfigToFile` 通过 | 反向依赖回归 + 分层测试失败清零 |

> 复核结论须在本次回归报告末尾写一行：「历史修复核对表三项（C6 / I1 / I6）均已闭环清零，无『引入回归』项遗留。」

### 2.4 每类验证的通过与不通过处置

| 验证类别 | 通过 | 不通过（通用回退路径） |
|---------|------|----------------------|
| 语法检查（V-01） | 进入 V-02 | 按失败文件 → 对应批次 checklist 重改；论文法错误优先于逻辑 |
| AHK 全套（V-02） | 进入 V-03 | 按失败 suite → 回溯 `test_*` → 对应批次（B6/B8/T8-04/B9）重改 |
| Rust 编译/测试（V-03/V-04） | 进入 Miri | 编译错误 → B1/B2/B5/B7；测试失败 → 按用例文件映射批次 |
| Miri（V-05~V-07） | 进入 clippy | UB 或失败 → 立即回退对应 crate 改动（B2/B3），不得带病前进 |
| clippy/fmt（V-08/V-09） | 进入 E2E | clippy warning → 修；fmt diff → 格式化后重新走该批次提交 |
| E2E（V-10~V-13） | 进入 V-14 | 失败用例 `appendKnownIssue` 记录 → 回溯批次（优先 B5/B12）；binary 缺失 → skip 不算 fail |
| 汇总覆盖率（V-14/V-15） | 收尾 | 覆盖率显著回退 → 定位新增未覆盖分支 → 补测或回退；口径不一致 → §2.2 收敛 |

**处置总原则**：任何「不通过」都回到**对应修复批次的 checklist 重新处理**，修复后从该类别**重跑**（不直接跳到后续类别）；不得以「文档标注已知问题」代替代码回归修复。

### 2.5 Phase 1~3 完成后统一收口

- 汇总运行（V-14）：`Set-Location "d:\1demo\AutoHotkeydemo\asd-tauri"; .\scripts\run-tests.ps1 -JUnit -Coverage -Analyze`
- 覆盖率（V-15）：`cargo llvm-cov --workspace --html --output-dir coverage/` + `cargo llvm-cov --workspace --lcov --output-path lcov.info`
- 产出物核对：`asd-tauri/test-results/`（JUnit XML）、`asd-tauri/coverage/`（HTML）、`lcov.info` 存在且非空；`analyze-tests.ps1` 输出通过率/失败清单/耗时 Top10/按 crate 统计。
- 收尾结论：将「历史修复核对表清零结论（§2.3）」「测试统计口径收敛结论（§2.2）」一并写入回归笔记，回填 `AGENTS.md` 头部 `Updated` 时间戳与正文统计数。

---

## 3. 交付摘要

| 项 | 值 |
|----|----|
| P2 覆盖 Minor 项数 | **46**（含合并项 `T3-08 + T6-12`、`T2-07 + T7-07` 与占位 `T8-07†` 已全部指派到批） |
| P2 批次数 | **12**（B1~B12，与 `00-issue-inventory.md` §3 一致） |
| Phase 3 验证矩阵命令条数 | **15**（V-01 ~ V-15） |
| 单一权威来源 | 测试统计 = `asd-tauri/docs/test-map.md`；架构/依赖/执行模式 = `AGENTS.md` |
| 历史修复清零项 | C6（部分修复 → 完全）、I1/I6（引入回归 → 消除） |