# 全面工程审查报告 — ASD 技能管理器 v4.0

**日期**：2026-09-19
**工作流**：工作流 1（全面工程审查）
**参与成员**：Cody（代码审查师）、Archi（架构师）、Tessa（测试专家）、Docu（技术文档师）
**审查范围**：Rust/Tauri 5-crate workspace（`asd-tauri/`）+ AHK v2 DDD 四层（仓库根）+ 交叉契约面 + 测试与文档基建
**不审查**：`AutoHotkey-2.0.26/`（vendored 只读引擎，由 C6 守卫）

---

## 📌 TL;DR

- **整体结论：🟡 有条件通过（Request Changes）**。无 🔴 级生产缺陷，5 条安全硬红线**全部当前遵守**，图谱实测环 0 / 孤点 0 / 依赖违规 0，全量技术债门禁 `[PASS]`。
- **严重度分布：🔴严重 3 项 / 🟠高 10 项 / 🟡中 12 项 / 🟢低 4 项 = 29 项**。其中 3 项 🔴 **全部是"权威文档失真"**，不直接破坏运行时，但会让后续所有决策基于错误信息——这正是本项目当天已三次踩中的同一类缺陷的又一次出现。
- **系统性薄弱点集中在三处**：① **watchdog/IPC 进程生命周期**（3 项 🟠 中的 3 项全在这里）；② **门禁覆盖率缺口**（`src-tauri` 占全仓 36.6% 却只有 63.67% 覆盖率且在棘轮之外，CI E2E 结构性不可达）；③ **跨语言双真值分裂**（Rust `validator.rs` 2626 行 ↔ AHK `config_validator.ahk` 759 行，无对拍、台账未登记）。
- **阻塞判定：非阻塞**。建议 3 项 🟠 中的 watchdog 持锁关机（#4）与按名全局 taskkill（#5）在下次合入前修复；其余按行动清单排期。

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| 整体评级 | 🟡 有条件通过（Request Changes） |
| 阻塞项数量 | 0（但建议合入前修 2 项：发现 #4、#5） |
| 关键行动项 | 10 条（P0 4 条 / P1 4 条 / P2 2 条） |
| 安全红线 | 5 条全部遵守；**仅 2 条有机器守护**，3 条靠注释与人工评审 |
| 门禁现状 | `check-tech-debt.py` 全量 `[PASS]`（C1a 0 / C1b 1 已登记 / C4–C13 全通过） |
| 图谱现状 | AHK 92 文件 282 边、Rust 66 文件 —— 环 0 / 孤点 0 / 倒灌 0 / crate 依赖违规 0 |
| 建议下一步 | 先做 4 条 P0（文档纠正 + 补 3 条静态契约测试 + 修 watchdog 关机路径），再立 3 份 ADR |

---

## 🔍 审查发现（按严重度排序）

> 来源列：Cody = 代码审查师；Archi = 架构师；Tessa = 测试专家；Docu = 技术文档师
> 全部结论均经**打开文件 / 执行命令 / 阳性对照**取证，未见证者一律不落笔。

### 🔴 严重（3 项）—— 权威文档失真，会污染后续所有决策

| # | 类别 | 文件:行 | 问题描述 | 建议修复 | 来源 |
|---|------|---------|---------|---------|------|
| 1 | 文档/权威边界 | `AGENTS.md:147` | 同一行先写「本文档只写指针、不复制数字」，紧接着硬编码**已失效**的覆盖率 **96.57%**（当前权威 89.05%，旧量程）。该数字全仓共 7 处，其余 6 处为 08-20 历史快照。 | 删除 `AGENTS.md:147` 的数字，改为指向 `test-map.md` 的指针 | Docu |
| 2 | 文档/权威边界 | `docs/tech-debt-plan-2026-09-16.md:39-40` | 硬编码 AHK 664 / Rust 405（实测现为 722 / 651），且**全文无「这是快照」警示**——同类文档 `tech-debt-register.md:24` 有该警示，此处缺失 | 补「历史快照」警示，或改为指针 | Docu |
| 3 | 架构/文档失真 | `AGENTS.md` 妥协白名单 #2（`BackupCore`） | **整体失真**：`application/config_service.ahk:19` 已有显式 `#Include`，白名单登记的「隐式依赖 / 应通过显式 #Include 抽象化」描述已过期；另 `group_service.ahk:96/174/196/297`（`RecordConfigChange`）与 `backup_service.ahk:20`（直读 `BackupCore.backupDir`）两个文件、两类用法**均超出白名单登记** | 重写该条目；把两个新用法纳入登记或收敛调用面 | Archi |

> 说明：#3 方向 `application → infrastructure` 本身**是合法分层**，不构成分层违规，问题在于**文档失真**——白名单一旦失真就失去"约束边界"的作用。

### 🟠 高（10 项）

| # | 类别 | 文件:行 | 问题描述 | 建议修复 | 来源 |
|---|------|---------|---------|---------|------|
| 4 | 正确性/并发 | `watchdog.rs:545-549` | `graceful_shutdown_watchdog` Phase 3 **持 watchdog 锁**执行 `kill_and_reap()`，内含同步阻塞 `Child::wait()`（`WaitForSingleObject`，**无超时**），与本函数自己的文档（行 488-494「锁内仅做状态快照，轮询在锁外执行」）**直接矛盾**。子进程不退出即无限期阻塞 tokio 工作线程且不释放锁 → `WatchdogRunner::run`、`spawn_watchdog`、`get_executor_status`、`reset_watchdog` 全部挂起，UI 冻结 | Phase 3 也改锁外：加锁取 pid 快照 → `spawn_blocking` 执行 kill + `wait_with_timeout` → 回锁内 `cleanup()`；或改用 `WaitForSingleObject(h, 3000)` | Cody |
| 5 | 正确性/进程生命周期 | `watchdog.rs:811-839` + `lib.rs:632-639` | `taskkill /F /IM asd_executor.exe` 是**按映像名的全系统杀进程**，不区分会话/实例/父进程；而单实例保护（T5-09）**未接入** → ① 第 2 个实例会杀掉第 1 个实例的执行器；② 手工起的调试进程被顺手杀；③ 便携模式子进程实际是 `AutoHotkey64.exe`，**不在清理名单**（这是红线 1 的代价），JobObject 又可能创建失败（行 220-239 只 `warn`），叠加即孤儿累积 | 优先接入 `tauri-plugin-single-instance` 并用已有 Child 句柄/PID 精确终止；必须保留按名兜底时用 `taskkill /FI "PID ne <self>"`；便携孤儿用 `QueryInformationJobObject` 兜底 | Cody |
| 6 | 安全 | `ipc.rs:36` + `lib.rs:133-141` | 管道名**硬编码固定 `asd_ipc`**，无随机后缀、无显式 DACL。同权本地进程可**抢先创建同名管道（squatting）**：Rust 侧 `create_listener` 失败后只 `tracing::error!` 就 `return`，**不重试、不告警、不降级**，IPC 永久不可用且用户无感知；更坏情况是 AHK 连到冒充者，把 `ASD_AUTH_TOKEN` 与全部按键指令交给对方（密钥泄露 + 按键注入） | 管道名加 `asd_ipc_<pid>_<rand>` 并启动参数传给 AHK；listener 显式设置仅当前用户 SID 的 DACL；`create_listener` 失败应按**启动失败**上报（函数文档行 918-919 已这么要求，调用点没照做） | Cody |
| 7 | 测试/门禁缺口 | `asd-tauri/src-tauri/` | `src-tauri` 占全仓代码量 **36.6%**，覆盖率仅 **63.67%**，**完全在 G3f 覆盖率棘轮之外** → 对外宣称的「89.05%」**不是全仓数字**（全仓另算 82.05%） | 要么把 `src-tauri` 纳入棘轮口径，要么在对外表述中强制标注口径 | Tessa |
| 8 | 测试/CI | `.github/workflows/ci.yml:564` | CI 上的 E2E **仍从未有任一用例被执行**，且已从「运气不好」升级为**结构性不可达**：门控为 `workflow_dispatch && inputs.run_e2e`（默认 `false`），push/PR **不可能触发**。9-18 手动 4 轮全部未建立会话（TD-061 已豁免）。另注：本机 9-17 曾 53 用例全绿，两个口径勿混 | 修门控条件，或明确承认 E2E 为「手动按需」并在 test-map 标注 | Tessa |
| 9 | 测试/一致性守护 | `asd-tauri/docs/test-map.md` | test-map 三处（明细行 /《汇总》AHK 两行 / 文首口径提示）**数值当前全部自洽**（279/722/720 实测吻合），但**无机器守护**：4 条阳性对照证明改方法数、改汇总行、改口径提示 G3d **全部放行**，只有「套件数」一维会红。反向对照 PC6 证明校验机制本身有效，故是真缺口。**历史犯过两次的根因仍在** | 补方法数维度校验（G3d） | Tessa |
| 10 | 架构/双真值 | `asd-domain/src/validator.rs`(2626 行) ↔ `infrastructure/config_validator.ahk`(759 行) | **跨语言领域校验双真值分裂**：一套业务规则两套独立实现，**无对拍测试、技术债台账未登记**。任何一侧改动都会静默产生「Rust 判合法 / AHK 判非法」的分歧 | 登记为技术债；补跨语言对拍用例（同一份配置样本两侧结果必须一致） | Archi |
| 11 | 架构/语义未决 | `asd-ipc-protocol/src/hotkey_merger.rs` | `HotkeyMerger` 合并语义**未做架构决策**：100ms 内同键 **last-write-wins 静默吞掉 toggle 事件**且**不可观测**；身份键只取 `keys[0]`，与 AHK 侧可变参 `SendHotkeyEvent` 构成**潜在契约断点** | 立 ADR-002：明确「节流」还是「事件流」语义，并要求被吞事件可观测 | Archi |
| 12 | 测试/可靠性 | 并发测试用例（4 条） | 并发用例**无超时护栏**，死锁 = 永久挂起 = **CI 无检测**（只能靠 job 超时兜底，且 E2E/并发 job 本就不可达） | 给 4 条并发用例加显式超时与失败断言 | Tessa |
| 13 | 文档/权威冲突 | `graph-driven-workflow.md:56` / `tech-debt-register.md:25,43` / `developer-guide.md` | **覆盖率权威三方打架**：graph-driven-workflow 说 test-map；register 说 developer-guide §4.6.1.3；developer-guide 既指 test-map 又自带全仓对照表 | 切分权威：3-crate 基线 → test-map；全仓/跨口径 → developer-guide | Docu |

### 🟡 中（12 项）

| # | 类别 | 文件:行 | 问题描述 | 建议修复 | 来源 |
|---|------|---------|---------|---------|------|
| 14 | 正确性/背压 | `ipc.rs:723`、`:741` | 热键分支用 `send().await`（**阻塞**），而 `forward_to_outbound`（行 637-650）按 T6-06 已改用 `try_send`「通道满时丢弃而非阻塞，避免经 recv → OS 管道 → AHK 同步 WriteFile 反向压死」。热键是**高频**消息，恰是 T6-06 最该覆盖的场景却走了阻塞路径 | 热键分支同样改 `try_send` + 丢弃计数打点 | Cody |
| 15 | 协议健壮性 | `ahk_executor/ipc_client.ahk:70`、`:98` | `MiniJson` 的 **Map 键名未转义**（`keyStr := '"' k '"'`），而值走 `_StringifyScalar` 有转义（行 121-127）。键名含 `"`/`\`/换行即产出**非法 JSON** → Rust `serde_json` 失败 → 消息错位/断连重连。热键名、分组名等键路径存在该面 | 抽 `_EscapeString(s)` 供键与值共用 | Cody |
| 16 | 安全/纵深防御 | `tauri.conf.json:13`、`:22` | `withGlobalTauri: true` 暴露 `window.__TAURI_INTERNALS__`，叠加 CSP `script-src 'self' 'unsafe-inline'` → 任意 WebView 内脚本注入点即可调用**全部 34 个 Tauri command**；其中 `export_config`/`import_config`/`export_recording`/`import_recording` 接受**任意绝对 `.json` 路径**（`backup_service.rs:22-49` 只校验绝对路径/无 `..`/非 UNC/扩展名），构成「任意 .json 读写」混淆代理 | 关 `withGlobalTauri` 改 ESM 导入；CSP 改 nonce/hash；导入导出路径加根目录白名单 | Cody |
| 17 | 可维护性/门禁缺口 | `bridge.rs:181-183` + `lib.rs:447-465` | **红线 3 / 4 / 5 无任何自动化守护**：锁顺序只写在注释里；WebView2 禁 sync 代理只有实现层面；纯逻辑 crate 禁依赖只靠人工看 Cargo.toml。全仓 grep 在 `src-tauri/src/tests/` 与 `scripts/` 下**零命中** | 补 3 条静态契约测试（扫嵌套锁 / 扫 `AddHostObjectToScript` / 解析 `cargo tree`） | Cody |
| 18 | 正确性/原子性 | `asd-application/src/state.rs:415-451` | `save_config_atomic` 先释放 `config_state.write()`（行 446）**再**取 `active_hotkeys.write()`（行 449），两锁之间有窗口 → 其它线程可读到「新 config + 旧 active_hotkeys」；而 `set_group_active`(205/217)、`toggle_group_active`(261/272) 是**嵌套**持有同序两锁，说明设计上本应原子 | 把 `active_hotkeys` 更新并入 `config_state` 同一写锁临界区，或在文档明确该窗口并让读路径校验 `version` | Cody |
| 19 | 性能/可用性 | `ipc.rs:24` + `:342-392` | `send()` 在**持有 `send_half` 互斥锁**期间做 `write_all`(2s) + `flush`(2s) = 最坏 **4s**；期间所有并发 `send_and_wait` 串行排队，而 `IpcBridge` 是在 `block_in_place + block_on` 里调用它（`bridge.rs:44-63`），等于把 tokio 工作线程一起堵住。`bridge.rs:22` 注释称「临界区极短」，与 4s 上界不符 | 改「单写者任务 + mpsc 队列」让 `send()` 不持锁做 I/O；或 `SEND_TIMEOUT` 降到 500ms 并在超时路径 kill 子进程交 Watchdog 重启 | Cody |
| 20 | 测试/盲区 | 关机编排路径 | **关机编排零覆盖**：只测了被抽出的纯函数（`shutdown.rs`），未测真实关机时序 | 补关机时序集成用例 | Tessa |
| 21 | 测试/盲区 | Rust 侧配置迁移 | **Rust 侧配置版本迁移零用例** | 补迁移用例（旧版本配置 → 新版本） | Tessa |
| 22 | 测试/盲区 | `watchdog.rs` 15 条 `#[ignore]` | 15 条 watchdog 用例被 `#[ignore]` 并挂 `continue-on-error`，理由是「避免慢测试」——**实测仅 13.33s，理由已不成立** | 摘掉 `#[ignore]`，纳入常规运行 | Tessa |
| 23 | 架构/白名单软越界 | `joy_hotkey_manager.ahk` → `joystick_input.ahk:97` | `IsJoystickConnected` 内部调 `GetKeyState` 查**设备状态**，与白名单「无副作用、无状态」的措辞不符（软越界，非分层违规） | 修订白名单措辞，或把设备查询下沉 | Archi |
| 24 | 架构/一致性 | Tauri: `app_data_dir` ↔ AHK: cwd 相对 | **双 UI / 双运行时栈并存且配置不共享**：Tauri 用 `app_data_dir`，AHK 用 cwd 相对路径 → 同一份配置两个真值位置 | 立 ADR-001 明确 v3.0 AHK 栈定位（建议转维护模式），或统一配置根 | Archi |
| 25 | 架构/可维护性 | `validator.rs`(2626 行)、`state.rs`(860+ 行) | 上帝文件，改动风险集中 | 按聚合切分 | Archi |

### 🟢 低（4 项）

| # | 类别 | 文件:行 | 问题描述 | 建议修复 | 来源 |
|---|------|---------|---------|---------|------|
| 26 | 正确性 | `lib.rs:608-630` | `resolve_ahk_executor_path` 兜底返回**裸相对路径** `AutoHotkey64.exe`（依赖 CWD），打包应用里必然解析失败，且把「资源缺失」伪装成「启动失败」误导排障 | 兜底直接返回 `Err`，setup 阶段上报用户可见错误 | Cody |
| 27 | 安全/注入面 | `watchdog.rs:284-288` | 便携模式 `cmd /C <exe_path>`，Windows `cmd.exe` 的引号剥离行为构成理论注入面。当前 `exe_path` 来自受控 Resource 目录（风险低），但函数接受任意 `&str` | 改 `Command::new(exe_path)` 或 `cmd /D /S /C "<path>"`；文档标注「不接受外部输入」 | Cody |
| 28 | 性能/资源 | `lib.rs:213-230` | `spawn_watchdog` 状态同步循环是**无退出条件的 `loop`**，每秒抢一次 watchdog 锁，既不看 `shutting_down` 也不看通道关闭；关机后仍与 `graceful_shutdown_watchdog` 争抢同一把锁（与发现 #4 叠加会放大） | 传 `CancellationToken`/`shutting_down` Arc，关机时 `break`；改事件驱动 | Cody |
| 29 | 可维护性 | `main.ahk:16-30` | AHK `#Include` 靠**手工分层顺序**（28 行）维护，一旦有人调序即在加载期炸；`main.ahk` 未直接 include `group_editor`/`backup_ui`/`debug_panel`（靠 `gui_manager` 间接引入） | 保持现状可接受（C1a/C1b 已守护孤儿与同名重复，实测 C1a 0 项）；建议补一条循环 include 静态检 | Cody |

---

## 🔒 五条安全硬红线逐条核实

> 方法：**打开源码核实**（不推断）；凡声称「已有守护」一律跑门禁取阳性证据。

| 红线 | 结论 | 守护方式 | 机器守护 |
|------|------|----------|---------|
| 1 `STALE_PROCESS_NAMES` 只允许 `asd_executor.exe` | ✅ 遵守（`watchdog.rs:794`，恰好 1 项） | `watchdog.rs:1508-1523` 双向单测 | ✅ 是 |
| 2 `src-tauri/src/{application,domain}/` 空占位 | ✅ 遵守（目录不存在） | `check-tech-debt.py` C4 —— **已注射违规样本实测由 PASS 变 FAIL，清理后回 PASS** | ✅ 是 |
| 3 WebView2 禁 sync 代理，必须 postMessage | ✅ 遵守（4 处 `PostWebMessageAsJson`，`AddHostObjectToScript` 零生产使用） | 无，仅实现约定 | ❌ 否 |
| 4 锁顺序 `ipc_manager → watchdog` | ✅ 遵守（6 个嵌套点逐点核实无反转） | 无，仅 `lib.rs:447-465` 注释 | ❌ 否 |
| 5 纯逻辑 crate 禁 `tauri/tokio/interprocess/windows` | ✅ 遵守（`cargo tree -p asd-domain` 传递闭包实测无四者） | 无，仅人工看 Cargo.toml | ❌ 否 |

**判读**：红线本身没被破坏，但**守护是不对称的**——2 条有机器守、3 条裸奔。这 3 条恰好都是「改反了不会立刻炸、但会在特定时序下死锁或绕过安全模型」的类型，人工评审最难发现。→ 行动项 A3。

---

## 🏗️ 架构影响评估

**评级：🟡 有条件通过**

**实测图谱（2026-09-19 重跑）**：AHK 92 文件 / 282 边，环 0、孤点 0、倒灌 0；Rust 66 文件，生产 crate 环 0、依赖违规 0；JS 环 0。闸门①与技术债检查均 PASS。crate 依赖与 `ALLOWED_CRATE_DEPS` 逐项一致。

**守护有效性经阳性对照实测**（沙箱隔离，未碰真仓）：注入 `infrastructure → presentation` 逆向边 → 闸门①精确报错 exit 1，移除后不报（非永真式）；dev 环改生产依赖 → 同时触发 crate 环 0→1 与违规 0→1，说明 `AGENTS.md` 标记的 dev-only 风险**已双守护，无需新增闸门**。

**白名单健康度**：妥协 #1 主项 ✅（6 个 domain 文件全部只 include `error_system.ahk`，调用点 100% 是 `LogError`，`JSONError` 零引用；两处软边界：level 传 `"WARNING"`、error_system 传递 include 拖入 utils+json_serializer）；#2 **🔴 整体失真**（见发现 #3）；`joy_sender`/`config_validator` ✅ 合规（后者行号漂移：AGENTS.md 写 `:167`，实际 `:182`）。

**契约一致性**：IPC 命令契约双向对齐 ✅（`check-tech-debt.py --only c8` 实测「Rust 13 条 / AHK 13 条 / 完全一致」，已有门禁 TD-057，非人肉对齐）。**未对齐的是配置校验**（发现 #10）与**热键合并语义**（发现 #11）。

**建议形成的 ADR**：

| ADR | 议题 | 建议 |
|-----|------|------|
| 001 | v3.0 AHK 栈定位 | 建议转维护模式，冻结新功能；同时解决双栈配置不共享（发现 #24） |
| 002 | 热键合并语义 | 明确「节流」还是「事件流」，要求被吞事件可观测（发现 #11） |
| 003 | `domain → ipc-protocol` 耦合 | 建议维持现状 + 写明复审触发条件 |

---

## 🧪 测试覆盖评估

**覆盖现状（本次实跑，与 test-map 一致）**：Rust **651**（154/72/173/3/249，`check-test-map.py` 运行时对账全 OK）；AHK 执行器 279 `Test_` / 61 套件；AHK 完整套件 **722** 用例 / 182 套件（本机实测 722 通过 0 跳过；`ASD_HOST_TIMING=0` 实测 715 通过 0 失败 **7 跳过**）；JS 39；E2E 53。

**Top 5 盲区**（详见发现 #7、#8、#12、#20、#21）：
1. `src-tauri` 占全仓 36.6%、覆盖率 63.67%，**完全在 G3f 之外** —— 门禁的 89.05% 不是全仓数字
2. watchdog 15 条 `#[ignore]` 挂 `continue-on-error`，实测仅 13.33s，「避免慢测试」的理由已不成立
3. 关机编排零覆盖（只测了抽出的纯函数）
4. 并发 4 条无超时护栏，死锁 = 永久挂起 = 无检测
5. Rust 侧配置版本迁移零用例

**test-map 三处自洽性**：数值当前**全部自洽**（279/722/720 实测吻合），但**无机器守护**——4 条阳性对照证明改明细行方法数、改《汇总》AHK 行、改文首口径提示，G3d **全部放行**，只有「套件数」一维会红；反向对照 PC6 证明校验机制本身有效，故上述是**真缺口**。附带：`test-map:307-308` 的 E2E 文档路径悬空（真实在 `asd-tauri/e2e/docs/`）。

**CI E2E**：**仍从未有任一用例被执行**，已从「运气不好」升级为**结构性不可达**（`ci.yml:564`）。注意**本机 9-17 曾 53 用例全绿**，两个口径勿混用。`gh` 未认证，结论以代码定位 + 仓内文献为准，未联网核实。

**测试债**：已登记 10 条（TT-01~10），最高优先级 TT-01（补方法数维度校验，工作量 2）、TT-02（摘 watchdog `#[ignore]`，工作量 2）。

---

## 📚 文档一致性评估

**权威边界遵守情况**：5 域中「测试数字唯一权威」被明确违反（发现 #1、#2）；覆盖率权威三方打架（发现 #13）；台账自指计数 ✅ 已去数字化且 C13 实测绿（64 行 = 统计行 64）。

**证据铁律执行范例**：Docu 用闸门自身正则做阳性对照 —— C3b 闸门**真实有效**（642/642、722/722 命中），但有 3 个盲区：扫描根仅 `docs/`（`AGENTS.md` 逃逸）、只认 `N / N` 同值形态（`96.57%` 与 `163+242=405` 逃逸）、需上下文词。**是「范围窄」而不是「失效」** —— 这个区分很关键，按老习惯会误报成「C3b 没守护」。

**断链扫描**：扫 82 个 md，命中 207；**真待修 130**（活跃 27 / 归档 103），其余 77 为非缺陷（图节点 ID 18、C4 故意不存在 15、上游路径 4、系统二进制 4、历史已删 36）。历史报告实测**入边 0**：`code-review-report-2026-08-20.md`、`remediation-plan-2026-08-20.md`、`git-cleanup-report.md`、`superpowers/`(37 份) → 建议**整体归档**，不逐条修。

**Top 5 文档债**：DD-01 删 `AGENTS.md:147` 数字（工作量 1）；DD-02 扩 C3b 范围与形态（3，需先登记棘轮豁免）；DD-03 计划文档加快照警示（1）；DD-04 切分覆盖率权威（1）；DD-06 仓库根与 `docs/` 均无 README，加索引（2）。另 DD-05 路径前缀约定未声明（活跃文档 27 处断链的主因）。

---

## ✅ 行动清单（按优先级排序）

| # | 行动 | 负责角色 | 紧急度 | 预期完成 |
|---|------|---------|--------|---------|
| A1 | 修 `watchdog.rs:545-549` 优雅关机 Phase 3：把 `kill_and_reap` 移出锁外并加超时（发现 #4） | Cody | P0 | 下次合入前 |
| A2 | 修 `taskkill /F /IM` 按名全局杀进程：接入单实例保护 + 用 PID 精确终止 + 便携模式孤儿兜底（发现 #5） | Cody | P0 | 下次合入前 |
| A3 | 补 3 条静态契约测试，把红线 3/4/5 从「注释约定」升级为「机器守护」（发现 #17） | Tessa + Cody | P0 | 本周 |
| A4 | 纠正 3 项 🔴 文档失真：`AGENTS.md:147` 去数字、计划文档加快照警示、重写妥协白名单 #2（发现 #1/#2/#3） | Docu + Archi | P0 | 本周 |
| A5 | IPC 加固：管道名加随机后缀 + 显式 DACL + `create_listener` 失败按启动失败上报（发现 #6） | Cody | P1 | 两周内 |
| A6 | 登记「跨语言领域校验双真值分裂」为技术债并补跨语言对拍用例（发现 #10） | Archi + Tessa | P1 | 两周内 |
| A7 | 把 `src-tauri` 纳入覆盖率口径或在对外表述强制标注；修 CI E2E 门控（发现 #7/#8） | Tessa | P1 | 两周内 |
| A8 | 补 test-map 方法数维度守护（TT-01）+ 摘 watchdog 15 条 `#[ignore]`（TT-02）（发现 #9/#22） | Tessa | P1 | 两周内 |
| A9 | 立 3 份 ADR（AHK 栈定位 / 热键合并语义 / domain→ipc-protocol 耦合） | Archi | P2 | 本月 |
| A10 | 归档入边为 0 的历史报告（`superpowers/`、`code-review-report-2026-08-20.md` 等）+ 建 `docs/README.md` 索引 | Docu | P2 | 本月 |

---

## ⚠️ 待完善 / 已知局限

1. **本次为只读审查**，未修改任何业务代码；所有成员均已复核 `git status` 干净（唯一新增物为本报告目录下的原始产出）。
2. **Tessa 未联网核实 CI**（`gh` 未认证），CI E2E 结论以 workflow 代码定位 + 仓内文献为准。
3. **工时/成本类影响未量化** —— 无记录，不编造。
4. **AHK 完整套件 722 用例为本机实跑**；CI 上的对应数字不可得（E2E/完整套件 job 本就不可达）。
5. **发现 #6（Tauri 全局 API 暴露）定为 🟡 而非 🔴** 的前提是前端 `innerHTML` 已统一 `escHtml`/`escAttr` 转义（19 处抽查 3 处最高风险点确认在转义链上）。若未来引入新的 `innerHTML` 拼接点而漏转义，该项应升为 🔴。
6. **Arch 的白名单越界核实覆盖 AHK 侧妥协**；Rust 侧的架构约束（如 `ALLOWED_CRATE_DEPS`）已由图谱与闸门覆盖，两者口径不同，勿混读。

---

## 📚 数据来源 & 成员产出索引

- **Cody（代码审查师）原始产出**：`deliverables/engineering-assurance/_raw-cody-code-review-2026-09-19.md`（13 项发现 + 5 条红线逐条核实 + 9 项「未发现问题的高风险面」实证）
- **Archi（架构师）原始产出**：`deliverables/engineering-assurance/_raw-archi-architecture-2026-09-19.md`（图谱实测、白名单越界核实、Top 5 架构债、3 条 ADR 建议）
- **Tessa（测试专家）原始产出**：`deliverables/engineering-assurance/_raw-tessa-testing-2026-09-19.md`（覆盖现状、Top 5 盲区、test-map 三处核对、10 条测试债、CI E2E 结构性不可达）
- **Docu（技术文档师）原始产出**：`deliverables/engineering-assurance/_raw-docu-docs-2026-09-19.md`（431 行：权威边界审查、断链扫描 207 命中/130 待修、Top 5 文档债、报告骨架规范）
- **取证方法**：所有结论均经打开文件 / 执行命令 / **阳性对照**取证。对「某守护是否存在」一律采用注射违规样本观察门禁是否真变红，不依赖读代码推断。
- **权威数字**：测试数字一律以 `asd-tauri/docs/test-map.md` 为准；本报告不复制数字，仅作指针引用。

---

> 本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
