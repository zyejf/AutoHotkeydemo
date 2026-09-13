# 项目长期记忆 — ASD 技能管理器

> 长期有效的事实与约定。临时状态见 `YYYY-MM-DD.md`。

## 文档权威边界（四方，各自领域内唯一）

| 文档 | 权威领域 | 不负责 |
|------|---------|--------|
| `AGENTS.md` | 架构决策、分层规则、妥协白名单、关键文件清单 | 测试数字、操作步骤 |
| `asd-tauri/docs/test-map.md` | **一切测试数字** | 架构、流程 |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 | 分层、测试数字 |
| `docs/graph-driven-workflow.md` | 图谱方法、开发/审查流程、同步机制 | 架构、测试数字 |

冲突处置：数字→test-map；架构→AGENTS；命令→developer-guide；流程→graph-driven-workflow。
**矛盾必须当场修正，不允许两边都留着。测试数字只允许 test-map 持有，其它文档只写指针。**

## 图谱工作流与四闸门

```bash
python .review-analysis/build_graph.py     # → .review-analysis/graph-raw.json
python .review-analysis/gen_graph_html.py  # → docs/review/<date>/graph/{json,html}
bash scripts/check-gates.sh [--quick]      # 一键四闸门
```
靶点：环 / 逆向边 / 孤点 / 契约断点。
depth（依赖恒大→小）：`infrastructure 0`→`domain 1`→`application 2`→`presentation 3`→
`entry 4`→`executor 5`→`tests 6`→`other 7`；后四者豁免。
**四闸门**：① 图谱无新环 ② fmt+clippy 零告警 ③ 测试通过且登记 test-map ④ 文档同步。

基线（2026-09-13 后）：AHK **73** 文件 / 262 边（范围内 256）/ 0 环 / 9 孤点；
Rust 64 文件 / 163 use 边 / 11 crate 边 / 0 生产环 / 3 违规（均 asd-test-harness，白名单）；
JS 5 / 9。

坑：① `build_graph.py` 的 `#Include` 正则**必须保留 `re.M`**；
② 分层常量 `LAYER_META`/`LAYER_EXEMPT` 在 **gen_graph_html.py**（不在 build_graph.py）；
③ crate 环检测只用生产边；④ 新增跨 crate 依赖须同步 `ALLOWED_CRATE_DEPS`。

## 契约统计命令

| 契约 | 命令 | 注意 |
|------|------|------|
| IPC action 分支 | `sed -n '58,85p' ahk_executor/executor.ahk \| grep -cE 'case "'` | **必须限行**：全文件 21 个 `case` 中 10 个是 MergeModeConfig 模式串 |
| Tauri 命令数 | `grep -cE '^\s+commands::' src-tauri/src/lib.rs` | — |
| IpcCommand variant | `grep -cE '^\s{4}[A-Z][A-Za-z]+' crates/asd-ipc-protocol/src/command.rs` | — |
| crate 测试数 | `grep -rhE '^\s*#\[(tokio::)?test\]' <crate>/ --include=*.rs \| wc -l` | 用 `-h`+`wc -l` |
| AHK 套件/用例 | `grep -cE '^class \S+ extends AutoHotUnitSuite' <f>` / `grep -cE '^\s+Test_\w+\(' <f>` | 见 test-map |
| AHK 实跑数 | `tail -8 tests/test_results.log`；套件数 `grep -c '【测试套件】'` | **权威** |

Rust 运行时口径：domain 136 / ipc-protocol 72 / application 163 / test-harness 3 / tauri 242 = 616
（`#[ignore]` 15）；`cargo test --workspace` 实测 601 passed / 0 failed / 15 ignored + 1 doc-test。
`--all-targets` 下 criterion benches（`harness=false`）不注册为测试。

## 易误判点

1. `SkillManager` 两义：`AGENTS.md` 的是 AHK v2 类（`domain/skill_manager.ahk`，存在）；
   `migration-guide.md` 的是迁移映射表 AHK 侧列（该保留）。只清 **Rust asd-application 侧**引用。
2. **历史/归档文档严禁改写**（`docs/review/**`、`docs/superpowers/plans/**`、`.trae/specs/**`、
   `docs/code-review-report-*`、`docs/remediation-plan-*`）—— 出现已删文件是当时事实的记录。
3. `joystick_input_utils.ahk` 在 AGENTS.md 妥协表中是**正确内容**（A1 修复史）。
4. `asd-application/src/` 实际 8 文件，**无 `scheduler.rs`**。
5. `AppState` 真实字段见 `crates/asd-application/src/state.rs:80-92`，非文档旧写的 scheduler/config_repo。

## 安全红线

- `watchdog.rs` 的 `STALE_PROCESS_NAMES` **只允许 `asd_executor.exe`**，绝不 加 `AutoHotkey64.exe`。
- `src-tauri/src/application/`、`src-tauri/src/domain/` 是空历史占位，禁止加代码。
- WebView2 AHK-JS 通信**禁止 sync 代理**（会死锁），必须 postMessage。
- 全局锁顺序 **`ipc_manager` → `watchdog`**，反转即死锁。
- 纯逻辑 crate **禁止**引入 `tauri`/`tokio`/`interprocess`/`windows`。

## AHK 定时器硬事实（实测，勿再凭直觉）

**没有亚 15.625ms 的唤醒手段**（AHK v2，本机）：

| 机制 | 实测 |
|------|------|
| `A_TickCount` 步进 | 中位 **15.52ms** → 测不了 20ms 内时延 |
| `SetTimer`/`Sleep` | 锁死 **15.625ms 网格**；请求 1/5/10/15 均 ~15.6；**请求 16 反得 ~31**（跨格跳 2 格） |
| `timeBeginPeriod(1)` | 对 AHK **完全无效**，别写进方案 |
| 一次性 `SetTimer(-1)` 自轮询 | 主线程空闲时中位 **15.67ms**（早先 0.23ms 是探针自身 `Sleep 5` 的假象） |
| **QPC 忙等** | 目标 20ms → 误差 **0.0017ms** —— **唯一精确手段** |

精确定刻规范（AGENTS.md §高精度定刻规范）：
① 需 <50ms 精度一律用 `HighResClock`（`ahk_executor/high_res_clock.ahk`），禁 `A_TickCount`；
② 等到点用 `SleepUntil(target)`，禁 `Sleep` 收尾；
③ 定时器提前唤醒量 ≥ 1 网格+抖动（`Sender.WAKE_LEAD_MS=28`；18 时保持时长被压到 8ms，28 时 14.8ms）；
④ 推进周期基准必须用**本次触发的计划时刻**，不能用发送完成后的当前时刻（否则每轮误判「已落后」白跳一周期）；
⑤ 滞后时**禁止**把基准重置为当前时刻（旧 `sender.ahk` 缺陷，既丢相位又吞触发）→ 保相位单调推进 + 计 `droppedTriggers`。

实测：periodic「计划时刻→抬起完成」P95，旧 16~27ms（5 轮 3 轮超标）/ 新 **14.8~15.0ms**；
interval=20 时旧 P95 竟达 **~2000ms**（误差线性累积），新仍 15.0ms。
报告 `docs/perf/key-latency-benchmark-2026-09-13.md`。
**Rust 侧下沉不可行**：`SendLevel(10)`+`InputLevel(11)` 使 Rust `SendInput` 被 AHK 当物理键 → 自触发死循环。

## 工程约定

- 换行符：`.gitattributes` 强制 LF（`.ps1`/`.bat`/`.cmd` 除外）。Edit 工具可能引入 CRLF，改完用 Python 校验。
- Conventional Commits，描述用中文。⚠️ scope 正则 `[a-z-]+` **不允许数字**（`fix(e2e)` 因含 `2` 被拒）。
  长信息用 `git commit -F <file>`；**`-F` 不接受 MSYS 路径**（须 `cygpath -w`）；`-F` 与 `-m` 不能同用。
- ⚠️ **禁用 `git rm` 及 safe-delete**：包装器路径拼接 bug 会把删除放大到邻近目录（实测连带删 54 文件）。
  替代：`mv <f> /tmp/x.bak` + `git add -A <dir>`。误删恢复：先 `mv .git/index.lock /tmp/` 再 `git checkout -- .`
  （会连未暂存改动一起还原 → 重要改动及时提交）。
- 提交信息**不写具体测试数字**；文档与代码**同 PR**。
- AHK 测试前置：语法检查（stderr 重定向+退出码）→ 接管指令验证 → 运行时验证。
- AHK v2 箭头函数 `=>` **只支持表达式体**，禁止块体。
- AHK v2 类**静态方法只读**，不能 `Sender._SendKeyDown := fn` 覆盖 → 用注入字段（如 `_sendHook`）。

## AHK 测试的坑

- ⚠️ **「脏环境假阳性」**：断言路径与组件实际写入路径不一致时，只要该路径恰好已存在就一直绿。
  实测 6 例日志测试写死 `<repo>/logs/`，组件实际写 `tests/logs/`。
  **断言取组件自己的值**（`DebugLogger.logFile`），因 `FileExist`/`FileAppend` 共用相对路径解析规则。
- 日志路径：`DebugLogger`/`JSONLogger` 用相对 `logs/x.log`（按 `A_WorkingDir`）；
  `ErrorSystem` 用 `A_ScriptDir "\logs\errors.log"`。
- `AutoHotUnitSuite` **下划线开头方法不收集为用例**（`AutoHotUnit.ahk:44`），可安全作辅助方法。
- 对 **Object 形态**（`{type:"ERROR"}`）**不能用 `[]` 取值**，须 `.prop` 或先判 `e is Map`。

## 环境 / CI / E2E 的坑（完整版见 `env-and-ci.md`）

高频 6 条（其余见上文件）：

1. 推送：`git -c credential.helper= push "https://x-access-token:$(gh auth token)@github.com/zyejf/AutoHotkeydemo.git" main`；
   失败多为代理 502，**直接重试 1–3 次**，别改凭据。远端真实状态用 `gh api repos/zyejf/AutoHotkeydemo/commits/main`。
2. ⚠️ **禁用 `git rm`/safe-delete**（路径拼接 bug 会连带删 54 文件）→ `mv` 到 /tmp + `git add -A`。
   误删恢复先 `mv .git/index.lock /tmp/` 再 `git checkout -- .`（会连未暂存改动还原 → 及时提交）。
3. ⚠️ Bash 命令里**不要出现 `powershell`/`pwsh`/`reg.exe`**（整体拦截）→ 用 PowerShell/Grep 工具。
4. ⚠️ **`cargo clippy`/`cargo test` 可能 ICE**（退出码 101，`rustc_metadata::rmeta::encoder::encode_metadata`）
   —— 增量缓存损坏/编译器缺陷，**不是代码问题**；`CARGO_INCREMENTAL=0` 重跑。
5. CI：禁硬编码绝对路径；中文输出需 `PYTHONUTF8=1`+`PYTHONIOENCODING=utf-8`+`reconfigure`；
   `AutoHotkey64.exe` 是 GUI 程序，PowerShell 必须 `Start-Process -Wait -PassThru -Redirect*`；
   gitlink 缺 `.gitmodules` 是静默损坏（`git ls-files -s | grep '^160000'`）。
6. E2E：debug 构建**一定走 Vite devUrl**，`"Origin header is not a valid URL"` 是「页面没加载」的
   下游症状（**改 `useHttpsScheme` 不对症**）；`__TAURI__` 存在 ≠ 加载成功，看
   `window.location.protocol` 是否 `chrome-error:`。

## BUG-6 双栈对齐（已完成）

AHK 侧 `_ValidateSuspiciousModeValues` 对齐 `asd-domain::validator`。**改任一侧必须同步另一侧**，
三处刻意差异：① 长度不匹配只在「序列**多于**按键」时告警；② 超长值只覆盖
`(MAX_REASONABLE_INTERVAL_MS, MAX_INTERVAL_MS]`；③ 子组下标 **1-based**（Rust 0-based）。

**已知分歧（不修）**：热键长度 AHK 15 字符即 ERROR，比 Rust 256 字符 WARNING 更严，语义已覆盖。

**判定铁律**：`Validate()` 返回 ERROR+WARNING 混合数组，判定「是否致命」
**必须走 `ConfigValidator.FilterByType(errors, "ERROR")`**，绝不可用 `errors.Length > 0`。
