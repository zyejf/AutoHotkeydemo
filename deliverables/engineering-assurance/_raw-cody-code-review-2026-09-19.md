# 全系统代码审查（原始产出）— 科迪 Cody / 代码审查师

- 日期：2026-09-19
- 项目：ASD 技能管理器 v4.0
- 仓库根：`D:\1demo\AutoHotkeydemo`（分支 `main`）
- 审查范围：Rust/Tauri（`asd-tauri/`）+ AHK v2 四层（根 `domain/ infrastructure/ application/ presentation/` `main.ahk`）+ 交叉契约面
- **不审查**：`AutoHotkey-2.0.26/`（vendored 只读引擎）
- 本次为**只读审查**，未修改任何业务代码（唯一落盘物是本文件；C4 阳性对照探针文件已当场删除并复核 `git status` 干净）

---

## 一、发现总表（按严重度排序）

| # | 严重度 | 类别 | 文件:行 | 问题描述 | 建议修复 | 证据 |
|---|--------|------|---------|----------|----------|------|
| 1 | 🟠高 | 正确性/并发 | `asd-tauri/src-tauri/src/infrastructure/watchdog.rs:545-549` | `graceful_shutdown_watchdog` Phase 3 **持 watchdog 锁**执行 `kill_and_reap()`，内含同步阻塞的 `Child::wait()`（`WaitForSingleObject`，无超时）。这与本函数自己的文档（"锁内仅做状态快照，轮询在锁外执行"，行 488-494）直接矛盾。若子进程因任何原因未及时退出，当前 tokio 工作线程被无限期阻塞且 watchdog 锁不释放 → `WatchdogRunner::run()`、`spawn_watchdog` 状态同步循环、`get_executor_status` / `reset_watchdog` 全部挂起，UI 冻结，只剩强杀。 | 把 Phase 3 也改造成「锁外执行」：先短暂加锁取 `pid` 快照，再用 `tokio::task::spawn_blocking` 执行 `kill`+`wait_with_timeout`，返回后在锁内 `cleanup()`。或改用 `WaitForSingleObject(h, 3000)` 超时后直接放弃。 | 行 546 `let mut guard = watchdog.lock().await;` → 行 547 `guard.kill_and_reap();` → 行 548 `guard.cleanup();`；`kill_and_reap` 定义于行 200-207，其中行 204 `let _ = c.wait();` 为阻塞调用且无超时 |
| 2 | 🟠高 | 正确性/进程生命周期 | `watchdog.rs:811-839`（`cleanup_stale_executor_processes`）+ `lib.rs:632-639`（T5-09 未接入） | `taskkill /F /IM asd_executor.exe` 是**按映像名的全系统杀进程**，不区分会话/实例/父进程。项目明确记录了单实例保护（T5-09）**尚未接入**，因此：① 启动第 2 个应用实例会在 `spawn_child` 里杀掉第 1 个实例的执行器；② 开发者手工起的 `asd_executor.exe` 调试进程会被顺手杀掉；③ 便携模式下子进程实际是 `AutoHotkey64.exe`，**不在清理名单内**（这正是红线 1 的代价），JobObject 又可能创建/分配失败（行 220-239 只 `warn`），二者叠加即孤儿进程累积。 | ① 优先接入 `tauri-plugin-single-instance` 并在启动期用**已有 Child 句柄 / PID**精确终止，而非按名 kill；② 若必须保留按名兜底，用 `OpenProcess`+PID 比对排除自身实例，或用 `taskkill /FI "PID ne <self>"`；③ 便携模式的孤儿改用 JobObject 句柄枚举（`QueryInformationJobObject`）兜底。 | 行 816-818 `Command::new("taskkill").args(["/F","/IM",name])`；`lib.rs:632-639` 注释「单实例保护（T5-09）暂缓说明…当前未接入」；`watchdog.rs:289-294` 便携模式走 `AutoHotkey64.exe executor.ahk` |
| 3 | 🟠高 | 安全 | `asd-tauri/src-tauri/src/infrastructure/ipc.rs:36` + `lib.rs:133-141` | IPC 命名管道名**硬编码固定为 `asd_ipc`**，未加随机后缀、未显式设置 DACL。同权本地进程可**抢先创建同名管道（squatting）**：此时 Rust 侧 `create_listener` 失败，代码只 `tracing::error!` 后 `return`，**不重试、不告警、不降级提示**，IPC 永久不可用且用户无感知；更坏的情况是 AHK 执行器连到冒充者，把 `ASD_AUTH_TOKEN` 与全部按键指令交给对方（密钥泄露 + 按键注入）。 | ① 管道名加进程/会话级随机后缀（`asd_ipc_<pid>_<rand>`），由 Rust 通过启动参数传给 AHK（AHK 侧已支持 `--auth-token` 之外的参数解析）；② 创建 listener 时显式设置只允当前用户 SID 的 DACL；③ `create_listener` 失败应作为**启动失败**上报（函数文档行 918-919 已这么要求，但调用点没照做）。 | `ipc.rs:36` `pub const IPC_PIPE_NAME: &str = "asd_ipc";`；`ipc.rs:920-927` `create_listener`；`lib.rs:135-140` 失败分支仅 `return`；`ipc_client.ahk:15` `static PIPE_NAME := "\\.\pipe\asd_ipc"`（两侧被 `test_ipc_pipe_name_matches_ahk_client` 锁死同一常量） |
| 4 | 🟡中 | 正确性/背压 | `ipc.rs:712-725` 与 `:731-743` | 热键消息分支用 `self.outbound_tx.send(msg).await`（**阻塞式**），而 `forward_to_outbound`（行 637-650）按 T6-06 的设计改用 `try_send`「通道满时丢弃而非 await 阻塞监听循环，避免经 recv → OS 管道 → AHK 同步 WriteFile 反向压死」。热键是**高频**消息，恰恰是 T6-06 最该覆盖的场景，却走了阻塞路径 —— outbound 通道（容量 512）一旦因消费端（`spawn_ipc_listener`）瞬时卡顿而填满，监听循环会被反压住，最终压死 AHK 的同步写。 | 热键分支同样改用 `try_send` + 丢弃计数打点；或把 `Hotkey` 的 flush 结果放入 `spawn_blocking`/独立任务，与 `recv` 循环解耦。 | 行 723 `let _ = self.outbound_tx.send(msg).await;` 与行 741 同；对比行 638 `self.outbound_tx.try_send(msg)`；行 634-636 的 T6-06 注释明确写了这条反压链 |
| 5 | 🟡中 | 正确性/协议健壮性 | `asd-tauri/src-tauri/ahk_executor/ipc_client.ahk:70`、`:98` | `MiniJson._StringifyMap` / `_StringifyObject` 中 **Map 的键名未做任何转义**（`keyStr := '"' k '"'`），而值走 `_StringifyScalar` 是有转义的（行 121-127）。只要某个键名含 `"`、`\` 或换行，AHK 侧就会产出**非法 JSON**，Rust 侧 `serde_json::from_str` 失败 → `IpcError::JsonError` → 消息错位/连接断裂重连。热键名、分组名等键路径存在该面。 | 抽出 `_EscapeString(s)` 供键与值共用。 | 行 70 `keyStr := '"' k '"'`（_StringifyMap）、行 98 同（_StringifyObject）；对比行 121-127 的值转义 `StrReplace(val,"\","\\")` 等 |
| 6 | 🟡中 | 安全/纵深防御 | `asd-tauri/src-tauri/tauri.conf.json:13`、`:22` | `"withGlobalTauri": true` 把 `window.__TAURI_INTERNALS__` 暴露到全局，同时 CSP 为 `script-src 'self' 'unsafe-inline'`。任意能在 WebView 内执行一段脚本的注入点，即可直接调用**全部 34 个 Tauri command**。其中 `export_config` / `import_config` / `export_recording` / `import_recording` 接受**任意绝对 `.json` 路径**（`backup_service.rs:22-49` 只校验：绝对路径、无 `..`、非 UNC、扩展名 .json），构成"任意 .json 读 + 任意 .json 写"的混淆代理。 | ① 关掉 `withGlobalTauri`（改用 `@tauri-apps/api` 的 ESM 导入）；② CSP 去掉 `'unsafe-inline'`，改用 nonce/hash；③ 对导入导出路径增加根目录白名单（如仅允许 `app_data_dir` 与用户显式授权的目录）。 | `tauri.conf.json:13` `withGlobalTauri: true`；`:22` `script-src 'self' 'unsafe-inline'`；`lib.rs:765-767, 782-783` 暴露 `export_config`/`import_config`/`export_recording`/`import_recording`；`backup_service.rs:22-49` `validate_file_path` |
| 7 | 🟡中 | 可维护性/门禁缺口 | `bridge.rs:181-183` + `lib.rs:447-465`（仅注释） | **红线 3 / 4 / 5 目前没有任何自动化守护**：锁顺序 `ipc_manager → watchdog` 只写在 `lib.rs:447-465` 与 `bridge.rs:181-183` 的注释里；WebView2 禁 sync 代理只有实现层面的 `PostWebMessageAsJson`，无静态扫描；纯逻辑 crate 禁依赖也只靠人工看 Cargo.toml。注释不会在有人改反时变红。相比红线 1（有单测 `test_stale_process_names_excludes_generic_autohotkey`）和红线 2（有 C4 门禁），这三条是**裸约定**。 | 补三条静态契约测试（与既有 `command_contract_tests.rs` / `doc_markdown_contract_tests.rs` 同一套路）：① 扫源码断言不存在「先 watchdog 后 ipc_manager」的嵌套锁；② 扫 `presentation/webview2_manager.ahk` 断言不含 `AddHostObjectToScript` / 同步 proxy；③ 解析 4 个 crate 的 Cargo.toml（或 `cargo tree`）断言纯逻辑 crate 不含 4 个禁依赖。 | 全仓 `grep -rn "锁顺序\|lock_order\|AddHostObject\|forbidden_deps"` 在 `src-tauri/src/tests/` 与 `scripts/` 下**零命中**；对比红线 1 有 `watchdog.rs:1508-1514` 测试、红线 2 有 `scripts/check-tech-debt.py:615-651` C4 |
| 8 | 🟡中 | 正确性/原子性 | `asd-tauri/crates/asd-application/src/state.rs:415-451` | `save_config_atomic` 先拿 `config_state.write()` 落内存（行 416-446 释放），**再**拿 `active_hotkeys.write()`（行 448-451）。两个锁之间有一段窗口，期间其它线程读到的是「新 config + 旧 active_hotkeys」。而 `set_group_active`（行 205-219）与 `toggle_group_active`（行 261-275）是**嵌套**持有 `config_state.write()` → `active_hotkeys.write()`，说明设计上这两者本应是一次原子更新。 | 把 `active_hotkeys` 的更新并入 `config_state` 的同一个写锁临界区（与 `set_group_active` 的嵌套顺序一致：`config_state` → `active_hotkeys`），或在文档中明确这个窗口并让读路径同时校验 `version`。 | 行 416 `let mut guard = self.config_state.write();` … 行 446 `};` 释放 → 行 449 `let mut registry = self.active_hotkeys.write();`；对比行 205+217 的嵌套写法 |
| 9 | 🟡中 | 性能/可用性 | `ipc.rs:24`（`SEND_TIMEOUT`）+ `ipc.rs:342-392` | `send()` 在**持有 `send_half` tokio 互斥锁**期间做 `write_all`（2s 超时）+ `flush`（2s 超时）= 最坏 4s。这期间所有并发 `send_and_wait` / `IpcBridge::send_command` 全部串行排队；而 `IpcBridge` 是在 `block_in_place + block_on` 里调用它的（bridge.rs:44-63），等于把 tokio 工作线程也一起堵住。注释（bridge.rs:22）称"临界区极短"，与 4s 上界不符。 | 把 `send_half` 改为「单写者任务 + mpsc 队列」，让 `send()` 不直接持锁做 I/O；或把 `SEND_TIMEOUT` 降到 500ms 并在超时路径主动 `kill` 子进程交 Watchdog 重启。 | 行 24 `const SEND_TIMEOUT: Duration = Duration::from_secs(2);`；行 342 `let mut writer_guard = self.send_half.lock().await;` 之后行 347/348 两次 `timeout(...)`；`bridge.rs:22` 「临界区极短（仅 `lock().await` + `send_command().await`）」 |
| 10 | 🟢低 | 正确性 | `asd-tauri/src-tauri/src/lib.rs:608-630` | `resolve_ahk_executor_path` 的兜底分支返回**裸相对路径** `PathBuf::from("AutoHotkey64.exe")`，依赖进程 CWD。这在 Tauri 打包应用里基本必然解析失败，且 `spawn_child` 的错误只会显示「启动子进程失败: … (program=AutoHotkey64.exe)」，把"资源缺失"伪装成"启动失败"，误导排障。 | 兜底应直接返回 `Err` 并由 setup 阶段把「未找到 AHK 执行器」作为**用户可见错误**上报，而不是返回一个注定失败的占位路径。 | 行 626-629 `.unwrap_or_else(\|e\| { tracing::error!(...); std::path::PathBuf::from("AutoHotkey64.exe") })` |
| 11 | 🟢低 | 安全/注入面 | `watchdog.rs:284-288` | 便携模式下 `.bat` 走 `cmd /C <exe_path>`。Windows `cmd.exe` 对含空格且带引号的参数有著名的引号剥离行为，理论上构成命令注入面。当前 `exe_path` 来自受控的 Resource 目录（`lib.rs:608-630`），风险低；但该函数接受任意 `&str`，未来若接外部输入即成真漏洞。 | 改用 `Command::new(exe_path)` 直接执行 `.bat`（Windows 可经由 `cmd` 关联执行），或显式加 `cmd /D /S /C "<path>"` 并做参数白名单校验；在函数文档里标注"不接受外部输入"。 | 行 284-288 `("cmd".to_string(), vec!["/C".to_string(), exe_path.to_string()])` |
| 12 | 🟢低 | 性能/资源 | `lib.rs:213-230` | `spawn_watchdog` 内嵌的状态同步循环是**无退出条件的 `loop`**，每秒抢一次 watchdog 锁，既不看 `shutting_down` 也不看通道关闭。关机后它仍与 `graceful_shutdown_watchdog` 争抢同一把锁直到进程退出（与发现 #1 叠加会放大影响）。 | 传入 `shutting_down` Arc 或 `CancellationToken`，在关机时 `break`；状态变更改成事件驱动而非 1s 轮询。 | 行 214-229：`let mut interval = tokio::time::interval(1s); loop { interval.tick().await; let wd_guard = wd_clone.lock().await; ... }`，循环体内无任何 break 条件 |
| 13 | 🟢低 | 可维护性 | `main.ahk:16-30` + `scripts/check-tech-debt.py` C1a | AHK 侧 `#Include` 采用**手工分层顺序**（先 infrastructure → domain → application → presentation，共 28 行），且 `main.ahk` 未 include `presentation/group_editor.ahk` / `backup_ui.ahk` / `debug_panel.ahk`（这些靠 `gui_manager.ahk` 间接引入）。依赖顺序靠人肉维护，一旦有人调整 include 顺序就会在加载期炸，且孤儿判定只能靠 C1a 的"跨语言字符串引用"兜底。 | 保持现状可接受（C1a/C1b 已守护孤儿与同名重复）；建议补一条"循环 include"静态检入 `check-tech-debt.py`（本次实测确认当前**无环**，见第三节）。 | `main.ahk:16-55` 四段 `#Include`；`check-tech-debt.py` C1a 实测「当前 0 项」 |

### 严重度分布

| 严重度 | 条数 |
|--------|------|
| 🔴严重 | 0 |
| 🟠高 | 3 |
| 🟡中 | 6 |
| 🟢低 | 4 |
| **合计** | **13** |

---

## 二、五条硬红线逐条核实结果

> 方法：**打开源码核实**（不推断）；凡声称"已有守护"的，一律跑一遍门禁/依赖树取阳性证据。

### 红线 1 — `STALE_PROCESS_NAMES` 只允许 `asd_executor.exe` ✅ **遵守**

- 定义：`asd-tauri/src-tauri/src/infrastructure/watchdog.rs:794`
  `const STALE_PROCESS_NAMES: &[&str] = &["asd_executor.exe"];` —— 恰好 1 项。
- `AutoHotkey64.exe` 在 Rust 侧的其它出现处均已核实**不在**清理名单：
  - `watchdog.rs:289` —— `spawn_child` 的「便携模式」启动目标（启动，不是 kill）
  - `watchdog.rs:256/267` —— 文档注释
  - `lib.rs:623/627/628` —— `resolve_ahk_executor_path` 的兜底启动路径
- **守护证据（阳性对照）**：`watchdog.rs:1508-1514` `test_stale_process_names_excludes_generic_autohotkey` 与 `:1517-1523` `test_stale_process_names_includes_project_executor` 双向断言，改坏即红。
- 附加观察：全仓 `grep "AutoHotkey64"` 命中 `build_ahk.ps1` / `run_silent.ps1` / `scripts/perf/*` / `tools/ahk-bench/*` 等，均为**启动器/基准脚本**，无一进入 `taskkill` 名单。

### 红线 2 — `src-tauri/src/{application,domain}/` 必须是空占位 ✅ **遵守（且有门禁）**

- 现状：两个目录在磁盘上**不存在**（`ls` 报 `No such file or directory`），`git ls-files asd-tauri/src-tauri/src` 也不含二者。
- 门禁：`scripts/check-tech-debt.py:615-651`（C4），判据是"目录里有没有文件"而非"目录存不存在"（注释行 622-629 明确解释了为什么——git 不跟踪空目录）。
- **阳性对照实测**（这是本条的关键证据，不满足于"跑一遍通过"）：
  1. 基线：`python scripts/check-tech-debt.py --only c4` → `[C4] … 核对 2 个 / 通过：占位目录为空或不存在` → `[PASS]`
  2. **注入违规样本**：`mkdir -p asd-tauri/src-tauri/src/application && echo '#[test] fn x(){}' > asd-tauri/src-tauri/src/application/_cody_probe.rs`
  3. 复跑：`[C4] … - asd-tauri/src-tauri/src/application 里有 1 个文件（如 …/_cody_probe.rs） —— 禁放代码：真身是 crates/asd-application/…` → **`[FAIL] 技术债检查未通过: 禁止加代码的空占位目录被写入 1 处（C4）`** —— 门禁**确实会变红**，不是摆设。
  4. 清理探针文件 + `rmdir`，复跑回到 `[PASS]`；`git status --short` 无残留（仅有队友的 deliverables）。

### 红线 3 — WebView2 的 AHK↔JS 通信禁 sync 代理，必须 postMessage ✅ **遵守（但无门禁）**

- 项目侧实现全部走异步消息：
  - `presentation/webview2_manager.ahk:143` `wv.PostWebMessageAsJson(combinedJson)`（状态推送）
  - `:370` `wv.PostWebMessageAsJson(response)`（响应）
  - `:187` `wv.add_WebMessageReceived(...)`（接收）
  - `:1258` `wv.PostWebMessageAsJson(json)`（事件）
  - 唯一的 `ExecuteScriptAsync`（`:189`）是 async 变体，非同步求值。
- **`AddHostObjectToScript` / 同步 proxy 的使用面已核实为零生产使用**：全仓 grep 仅命中 `tests/archive/test_app_ui.ahk:45`、`test_webview2_proto.ahk:29`、`test_wv2_v2.ahk:34`（归档测试）与 `lib/ahk2_lib/WebView2/WebView2.ahk:581-693`（第三方 lib 的能力定义，未被 `webview2_manager.ahk` 调用）。
- 另一条 WebView（Tauri 的 `asd-tauri/src/api.js`）同样全走 `window.__TAURI_INTERNALS__.invoke` 的 Promise 形态（Tauri v2 内部即 postMessage），无同步代理。
- ⚠️ 缺口：本红线**没有自动守护**，见发现 #7。

### 红线 4 — 全局锁顺序必须 `ipc_manager → watchdog` ✅ **遵守（但无门禁）**

逐个嵌套点核实，未见任何反转：

| 位置 | 取锁顺序 | 结论 |
|------|----------|------|
| `lib.rs:476-480` → `setup_ipc_callbacks` → `lib.rs:377` | `ipc_manager_arc.blocking_lock()`（476）→ `watchdog.blocking_lock()`（377） | ✅ 正确顺序 |
| `lib.rs:485-491` | 先释放 ipc 锁（480 块结束）→ 再 `watchdog.blocking_lock()` 做 `spawn_child` | ✅ 不嵌套 |
| `perform_graceful_shutdown` `lib.rs:64-77` | ① ipc 锁取放（66-69）→ ② runner 标志 → ③ `graceful_shutdown_watchdog`（只碰 watchdog） | ✅ 不嵌套 |
| `bridge.rs:46-49` | ipc 锁在块内取放后即释放，再对 clone 出的 `mgr` 调用 | ✅ 不嵌套 |
| `bridge.rs:196-201 / 217-219` | 只取 watchdog 锁 | ✅ 单锁 |
| `AppState` 内部（`state.rs`） | 只 `config_state` → `active_hotkeys`（`set_group_active`:205/217；`toggle_group_active`:261/272），与 watchdog/ipc 无交集 | ✅ 不交叉 |

- `watchdog.rs` 内部：只有 watchdog 单锁（`graceful_shutdown_watchdog`、`poll_watchdog_exit`、`WatchdogRunner::run`）；`send_shutdown` 回调（lib.rs:381-397）在**新 spawn 的任务**里锁 ipc_manager，不在 watchdog 锁内。
- ⚠️ 缺口：本红线**没有自动守护**，见发现 #7。另注意发现 #1（Phase 3 长持锁）会放大任何未来的顺序错误。

### 红线 5 — 纯逻辑 crate 禁 `tauri` / `tokio` / `interprocess` / `windows` ✅ **遵守**

- 声明层面：
  - `crates/asd-domain/Cargo.toml` 依赖 = `serde, serde_json, indexmap, thiserror, asd-ipc-protocol`
  - `crates/asd-ipc-protocol/Cargo.toml` 依赖 = `serde, serde_json, thiserror`
- **传递依赖实测（阳性证据）**：`cargo tree -p asd-domain -e normal` 输出去重后为
  `asd-domain / asd-ipc-protocol / equivalent / hashbrown / indexmap / itoa / memchr / proc-macro2 / quote / serde / serde_core / serde_derive / serde_json / syn / thiserror / thiserror-impl / unicode-ident / zmij`
  —— **无 `tauri`、无 `tokio`、无 `interprocess`、无 `windows`**。
- 顺带核实 `asd-application`（虽未被红线点名，但同属"纯逻辑"阵营）：依赖为 `asd-domain, asd-ipc-protocol, chrono, serde, serde_json, indexmap, thiserror, tracing, parking_lot`，同样**不含**4 个禁依赖。
- 唯一持有 4 个禁依赖的是 `src-tauri/Cargo.toml`（`tauri / tokio / interprocess / windows`），符合"入口层"定位。
- ⚠️ 缺口：无自动守护（无 `cargo deny` / 无契约测试），见发现 #7。

### 红线核实小结

| 红线 | 结论 | 守护方式 | 是否机器守护 |
|------|------|----------|--------------|
| 1 watchdog 清理名单 | ✅ 遵守 | `watchdog.rs:1508-1523` 双向单测 | ✅ 是 |
| 2 application/domain 空占位 | ✅ 遵守 | `check-tech-debt.py` C4（**已做阳性对照，实测会 FAIL**） | ✅ 是 |
| 3 WebView2 禁 sync 代理 | ✅ 遵守 | 无（仅实现约定） | ❌ 否 |
| 4 锁顺序 ipc→watchdog | ✅ 遵守 | 无（仅 `lib.rs:447-465` 注释） | ❌ 否 |
| 5 纯逻辑 crate 禁依赖 | ✅ 遵守 | 无（仅人工看 Cargo.toml） | ❌ 否 |

---

## 三、未发现问题的高风险面（已实测，非推测）

以下几处是本次审查中**特意去看、结果与"常见预期相反"**的高风险面。按项目证据铁律，写"没问题"同样要给出实测证据。

1. **生产代码几乎零 `unwrap` / `expect` / `panic!`（🟢 正面）**
   对 `lib.rs / bridge.rs / infrastructure/*.rs / commands/*.rs / crates/*/src/*.rs` 逐个切出 `#[cfg(test)]` 之前的行、排除注释行后统计：
   - `config_repository.rs`（1-336 行生产段）0 处；`state.rs`（1-860）0 处；`config.rs`（1-482）0 处；`message.rs`（1-178）0 处；`command.rs`（1-80）0 处；`ipc.rs`（1-928）0 处；`watchdog.rs`（1-1080）0 处（唯一命中是 728 行注释里引用的 `u32::try_from(..).unwrap()` 反例）。
   - 全项目生产代码仅剩 1 处 `.expect("Tauri 应用启动失败")`（`lib.rs:794`），且 `lib.rs:641-648` 的 `# Panics` 段给出了刻意保留的理由与"不要改成静默退出"的反指示 —— 属**有意设计**，不计为缺陷。
   - `state.rs` / `config_cmd.rs` 等文件里成百的 `unwrap` 全部落在 `#[cfg(test)]` 之后（例：`state.rs` 861 行起），已逐行核对。

2. **AHK `#Include` 图无环（🟢 正面，且经历一次自我证伪）**
   用脚本对 169 个 `.ahk`（排除 vendored 引擎 / `.worktrees` / `lib/ahk2_lib`）建 `#Include` 有向图做 DFS 染色，初检报出 1 个环：`tools/ahk-bench/bench_schedule_e2e.ahk → tools/ahk-bench/lib/seqgen_legacy.ahk → seqgen_legacy.ahk`。
   **复核后证伪**：该"环"来自 `seqgen_legacy.ahk:22-23` 两行**注释**中被我的正则误捕的示例 `#Include`。实际生产 `#Include` 图**无环**。
   工具类同族风险已由 C1a（孤儿）/ C1b（同名重复）覆盖，实测「C1a 当前 0 项、C1b 当前 1 项（已登记，非新增）」。

3. **手写 `unsafe impl Send/Sync` 已被收敛且有回归防线（🟢 正面）**
   `watchdog.rs` 里仅剩 `RawHandle`（行 615）与 `SendSyncCell`（行 653/659）两处手写 unsafe，且 `watchdog.rs:1327-1352` 的 `test_no_handwritten_unsafe_send_sync_for_watchdog_types` 用**源码级白名单扫描**禁止在别处加回手写 impl；注明白名单只允许 `["RawHandle","SendSyncCell"]`。注释（行 1278-1280）还记录了 2026-09-12 的故障注入实测（加入 `Cell<u32>` 后 `assert_sync` 立即报 E0277）—— 属**已做过阳性对照**的守护。

4. **IPC 命令契约（Rust 13 变体 ↔ AHK 分发表）双向对齐（🟢 正面）**
   `python scripts/check-tech-debt.py --only c8` 实测输出：`[C8] … Rust 13 条 / AHK 13 条 / 通过：两侧命令集合完全一致`。
   这直接回应了任务书中"13 个 `IpcCommand` variant 与 AHK 收发一致性"的关注点 —— 该契约**已有门禁**（TD-057），不是靠人肉对齐。

5. **`enum_windows_callback` 的裸指针生命周期安全（🟢 正面）**
   `watchdog.rs:903-912` 用 `RawBoxGuard`（行 767-787，RAII 守卫）承载传给 `EnumWindows` 的 `LPARAM`，`Drop` 时 `Box::from_raw` 回收；回调内另有 `pid_ptr.is_null()` 校验（行 916-919）。`GetWindowThreadProcessId` 的 out 参数用 `addr_of_mut!` 而非 `&mut x as *mut _`，规避了 `clippy::borrow_as_ptr`。未发现泄漏或悬垂。

6. **AHK 侧 WebView 消息分发有统一异常兜底（🟢 正面）**
   `webview2_manager.ahk:195-327` 的 `_OnWebMessageReceived` 整体 `try/catch`，且 catch 分支（行 322-326）在 `requestId != ""` 时回一条带 `error` 的响应，不会出现"前端请求石沉大海"；未知 action 也有显式回错（行 317-320）。

7. **备份文件名与路径有拒绝式（而非删除式）防护（🟢 正面）**
   - `backup_service.rs:216/258` 要求 `filename.starts_with("backup_")`，`:91-110` `validate_path_in_backup_dir` 用 `canonicalize()` + `starts_with` 做真实路径 containment 校验（不是字符串前缀比）。
   - `backup_service.rs:30-34` 用 `Component::ParentDir` **拒绝** `..`，而非 `RegExReplace` 删除式过滤（可绕过）—— 注释里也写明了这个取舍。
   - AHK 侧 `_BridgeCompareConfigs`（`webview2_manager.ahk:1192-1198`）同样是拒绝式（`InStr(absBase,"..")` 直接 return）+ 备份目录前缀校验；`_BridgeRestoreBackup`/`_BridgeDeleteBackup`（`:714`、`:734`）拒绝含 `\`、`/`、`..` 的文件名。

8. **前端 `innerHTML` 拼接已统一转义（🟢 正面）**
   `asd-tauri/src/main.js` 共 19 处 `innerHTML` 赋值，抽查最高风险的 3 处（分组卡片 `:497`、备份列表 `:722`、配置 diff `:330`）确认全部经 `escHtml` / `escAttr`（定义 `:222-223`，转义 `& < > " '`）；组名（`g.name`）、热键（`g.hotkey`）、备份名（`b.filename`）等用户可控字段均在转义链上。未发现可直接利用的 XSS 注入点（这也是发现 #6 只定为 🟡 而非 🔴 的原因）。

9. **门禁整体健康（🟢 正面）**
   `python scripts/check-tech-debt.py` 全量实测 `[PASS]`：C1a 0 项 / C1b 1 项（已登记基线）/ C1c 0 项 / C2 0 项 / C3b 3 项（已登记）/ C4 通过 / C5 通过 / C6 通过 / C7 通过 / C8 13↔13 通过 / C9 通过 / C10 三处档位一致 / C11 打包资源全覆盖 / C12 正式配置未开调试端口 / C13 台账自洽。

---

## 四、正面评价（做得好的地方）

1. **错误契约文档化到近乎苛刻的水位**：`config_cmd.rs`、`system_cmd.rs`、`recording_cmd.rs` 里每个函数都有 `# Errors`，且**主动标注"当前实现不会失败"的反直觉语义**（如 `get_config_impl` 行 38-40、`validate_config_impl` 行 67-69 明确写"别把返回 `Result` 当成可能出错"、"只看 Ok/Err 等于没校验"）。这种"把陷阱写进文档"的做法显著降低了误用概率，是本项目最值得保留的资产。
2. **`Ok` 语义的显式解耦**：`send_and_wait` 的文档（ipc.rs:453-459）明确"返回 Ok 仅表示收到响应，不代表操作成功"；`register_hotkey`（state.rs:503-508）明确 `Ok(Some(_))` 是"没做成却返回 Ok"。这类反直觉契约被写下来而不是靠调用方猜。
3. **时间/资源类缺陷有专项修复痕迹且附论证**：`SEND_TIMEOUT`（T6-05）、`try_send` 反压（T6-06）、`block_in_place` 说明（T5-03）、`spawn_blocking` 迁移动机（T5-04，watchdog.rs:1047-1052）、`checked_sub` 替换时间减法（watchdog.rs:386-389）—— 每一处都留了"为什么这么做"的注释，而不是默默改掉。
4. **auth token 用 `getrandom` + 恒定时间比较**（ipc.rs:814-864），并带随机源不可用时的降级路径与 `warn`；认证失败有指数退避（ipc.rs:282-293）并用 `min(5)` 防位移溢出。
5. **跨语言契约有多条机器守护**：管道名（`test_ipc_pipe_name_matches_ahk_client`）、命令集合（C8）、布尔键白名单（C7）、打包资源清单（C11）—— 这类"AHK↔Rust 漂移"本是本项目最容易出结构性静默失效的地方，目前覆盖得比常见项目好。

---

## 五、结论

**Request Changes**（有条件通过）

- 5 条硬红线**全部当前遵守**，其中 2 条有机器守护且已做阳性对照实测（C4 注入违规样本确实变红），3 条（禁 sync 代理 / 锁顺序 / 纯逻辑 crate 禁依赖）**仅靠注释与人工评审**，建议优先补静态契约测试 → 发现 #7。
- 无 🔴 级问题。3 项 🟠 中，**#1（优雅关机 Phase 3 持锁阻塞）**与 **#2（按进程名全局 taskkill + 无单实例保护）**是可被真实操作路径触发的可用性与数据面缺陷，建议在合入前修复；**#3（固定管道名可被抢占）**属本地安全面，建议随下次安全加固一并处理。
- 6 项 🟡 中，**#4（热键反压）**与 **#5（AHK JSON 键名未转义）**是"平时不发作、一发作就是难排查的连通性故障"，性价比高，建议同批处理。

---

### 附：本次审查的取证方式说明

- 全部红线结论均为**打开文件 + 执行命令**所得，未使用推断。
- 对"是否存在守护"一律采用**阳性对照**：C4 注入违规文件 → 观察门禁由 PASS 变 FAIL → 清理后复跑回 PASS；依赖红线用 `cargo tree` 取传递闭包而非只读 Cargo.toml。
- 初检报出的 AHK `#Include` 环经复核确认为**注释误捕**，已自我证伪并在第三节如实记录。
- 全程未修改任何业务代码；唯一临时产物（C4 探针文件）已删除，`git status --short` 复核仅剩队友的 deliverables 文件。
