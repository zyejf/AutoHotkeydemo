# 项目长期记忆 — ASD 技能管理器

> 长期有效的事实与约定。临时状态见 `YYYY-MM-DD.md`。
> 详见：`env-and-ci.md`（环境/CI/E2E）、`contracts-and-pitfalls.md`（契约统计命令/易误判点/BUG-6）。

## 文档权威边界（五方，各自领域内唯一）

| 文档 | 权威领域 |
|------|---------|
| `AGENTS.md` | 架构决策、分层规则、妥协白名单、关键文件清单 |
| `asd-tauri/docs/test-map.md` | **一切测试数字**（其它文档只写指针） |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 |
| `docs/graph-driven-workflow.md` | 图谱方法、开发/审查流程、同步机制 |
| `docs/research/` | **架构级调研结论唯一落点**（外部引擎/第三方源码走查 + 实测）；探针在 `tools/ahk-probes/` |

冲突：数字→test-map；架构→AGENTS；命令→developer-guide；流程→graph-driven-workflow；
外部引擎调研→`docs/research/`。
**矛盾必须当场修正，不允许两边都留着。**

> AHK v2 引擎调研（2026-09-14）：`docs/research/ahk-engine-architecture-2026-09-14.md`
> —— 含源码锚点、10 个探针实测数据、16 条执行摘要、L1/L2/L3 共 22 项落地清单。
> 引擎源码 `AutoHotkey-2.0.26/source` **只读**（不修改/不 fork/不编译）。

## 图谱工作流与四闸门

```bash
python .review-analysis/build_graph.py     # → .review-analysis/graph-raw.json
python .review-analysis/gen_graph_html.py  # → docs/review/<date>/graph/{json,html}
bash scripts/check-gates.sh [--quick]      # 一键四闸门（CARGO_INCREMENTAL=0 防 ICE）
```
靶点：环 / 逆向边 / 孤点 / 契约断点。
depth（依赖恒大→小）：`infrastructure 0`→`domain 1`→`application 2`→`presentation 3`→
`entry 4`→`executor 5`→`tests 6`→`other 7`；后四者豁免。

**基线（2026-09-14）**：AHK **74** 文件 / 264 边（范围内 258）/ 0 环 / 9 孤点；
Rust 64 / 163 use 边 / 11 crate 边 / 0 生产环 / 3 违规（均 asd-test-harness，白名单）；JS 5 / 9。

坑：① `build_graph.py` 的 `#Include` 正则**必须保留 `re.M`**；
② 分层常量 `LAYER_META`/`LAYER_EXEMPT` 在 **gen_graph_html.py**（不在 build_graph.py）；
③ crate 环检测只用生产边；④ 新增跨 crate 依赖须同步 `ALLOWED_CRATE_DEPS`。

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
| `SetTimer`/`Sleep` | 锁死 **15.625ms 网格**；请求 1/5/10/15/16/20 均 ~15.9；**断点在 21ms**（≥21 才变 ~31） |
| `timeBeginPeriod(1)` | 对 AHK **完全无效**（已有配对对照 + 复原确认：gap p50 15.985→15.995） |
| 一次性 `SetTimer(-1)` | 空闲时中位 **15.67ms**（0.23ms 是探针自身假象） |
| **QPC 忙等** | 误差 **0.0017ms** —— 唯一精确手段 |

精确定刻规范（AGENTS.md §高精度定刻规范，7 条）：
① <50ms 精度一律用 `HighResClock`，禁 `A_TickCount`；② 到点用 `SleepUntil`，禁 `Sleep` 收尾；
③ 提前唤醒量 ≥1 网格+抖动（`WAKE_LEAD_MS=28`；18 会把保持压到 8ms）；
④ 推进基准用**本次计划时刻**；⑤ 滞后**禁止**重置基准为当前时刻（→ 保相位 + `droppedTriggers`）；
⑥ 同刻多键**必须分桶批量** Down→等→Up（串行会让第二个键保持塌到 0.02ms）；
⑦ 序列首步基准在**首次执行**时确立（`nextStepTime := 0` 哨兵），不能取启动调用时刻。

⚠️ **代价：连续占用 AHK 主线程**。实测 interval=100/kpd=15：扣除网格后**最长连续占用 31.4ms、
占空比 29.2%**。
⚠️ **但「忙等=冻结一切」是误解**：`SleepUntil` 里的 `Sleep(0)` 在 AHK 中是 `ScriptSleep(0)` →
`MsgSleep(0)` → `PeekMessage`，**每次迭代都驱动消息泵**。实测自旋 100ms 期间探针定时器仍触发 7 次
（理论 6.4）。真实代价是**探针 gap p95 从 16.6 抬到 ~27ms**，不是无限期推迟。
`WAKE_LEAD_MS=28` 处于合理保守位：lead 8/16 会产生 **13~17% 睡过头**（保持时长塌掉）。

实测「计划时刻→抬起完成」P95：periodic 旧 16~27ms → 新 **15.0ms**；interval=20 旧 ~2000ms → 新 15.0ms；
sequence 旧 248~263ms → 新 14.97ms；hybrid 子组各自保持 100/300ms。
报告 `docs/perf/key-latency-benchmark-2026-09-13.md`。
**Rust 侧下沉不可行**：`SendLevel(10)`+`InputLevel(11)` 使 Rust `SendInput` 被 AHK 当物理键 → 自触发死循环。

## AHK 重构基准（`tools/ahk-bench/`，结论落点 `docs/refactor/`）

生产代码**零改动**：每个脚本内置旧实现（原样复刻生产逻辑）+ 新实现，同进程同数据对比并做等价性校验。
`bash tools/ahk-bench/run.sh <id>`；`cycle_leak_all.sh`（内存类须每用例独立进程）；
`python tools/ahk-bench/report.py [--prev <dir>...]` 生成对比报告。

**内存类基准两条硬纪律**：① 必须带**阳性对照**（否则「没测出来」＝「没有泄漏」无法区分）；
② 必须**每用例独立进程**（同进程基线漂移 3216→4696KB，残留量会算出负值）。

**统计口径（四条）**：① 用 p50 判，不用 max；② P95 需足量样本（n=54 只容忍 2 个离群点），
判漂移用中位数；③ 结论必须**跨轮可复现**；④ CPU 类结论必须给多轮区间并**检查是否重叠**，
重叠即「未测出差异」。

**实测结论（三轮）**：json_escape **19~41×**；tick 遍历合并 **1.80~1.96×**；
键名校验 **1.03×（无收益，不改，三份计划均不含）**；定时器忙等**只改善尾部稳定性**
（new 0.17~0.23ms vs old 1.05~4.92ms），p50/p95 无差别、CPU 三轮区间重叠；
对象互指**确认泄漏** 19,956KB/5万（408.7B每组）；**自引用闭包不泄漏**（代码走查推断被推翻）。

**启动基线**：`empty` p50 164.33ms；`hostname.exe` 144.85ms → 引擎自身约 19ms。
**`#Include` 边际 673µs/文件**（解析仅 1.44µs/行）→ 启动优化唯一确定杠杆是**减少文件数**。

**坑**：`case` 是 AHK v2 **保留字**（Switch/Case），作变量名解析期即失败；
**反斜杠路径上 `rm`/`[ -e ]` 不可靠**（不报错但文件仍在）→ 先 `cygpath -u`；
AHK `FileAppend` 默认系统 ANSI → 必须 `FileAppend(..., "UTF-8")`。

## 工程约定

- 换行符：`.gitattributes` 强制 LF（`.ps1`/`.bat`/`.cmd` 除外）。Edit 可能引入 CRLF，改完用 Python 校验。
- Conventional Commits，描述用中文。⚠️ scope 正则 `[a-z-]+` **不允许数字**（`fix(e2e)` 因含 `2` 被拒）。
  长信息 `git commit -F <file>`（**不接受 MSYS 路径**，须 `cygpath -w`）；`-F` 与 `-m` 不能同用。
- ⚠️ **禁用 `git rm`/safe-delete**（路径拼接 bug 会连带删 54 文件）→ `mv` 到 /tmp + `git add -A`。
- 提交信息**不写具体测试数字**；文档与代码**同 PR**。
- AHK v2：箭头函数 `=>` **只支持表达式体**；类**静态方法只读** → 用注入字段（如 `_sendHook`）。
- AHK v2 保留字不能作变量名（`log`/`in`/`out`…）；`while i<=n {` 不能写单行块体。
- 脚本级变量**不会**被箭头函数闭包捕获（函数 assume-local）→ 包进 `Main()` 或 `global`。
- AHK v2.0.26：`catch as e` 才对（`catch e` 报 `Invalid class`）；**`Array` 没有 `Sort()` 方法**；
  `Hotkey()`/`OnError()` 回调必须传**函数对象**（`((*) => 0)`；裸名字报 `Invalid callback function.`、
  `Func("名")` 报 `Invalid base.`）；`OnError` 多回调**全部执行**且 `-1` 移除不掉；
  `StrPut(s, 65001)` 数字码页非法，要写 `"UTF-8"`。
- AHK v2 **递归上限 ~1200–1500 层且 `try/catch` 捕获不到**（直接 ExitApp 模式终止进程）→ 深递归必须改迭代。
- AHK v2 **循环引用 100% 泄漏**（纯引用计数、无环检测）：5 万个带环 Map 常驻 +22.9MB。
- AHK v2 文件 API **无 MAX_PATH 限制**（30 038 字符读写正常，无需 `\\?\`）。
- **CP936/ANSI 码页往返会静默丢字符**（长度不变、内容变 `?`）→ IPC 必须锁死 UTF-8。
- ⚠️ **`#MaxThreads` 不能当背压**：30 个并发定时器在默认 10 下全部执行。
- 进程启动耗时**必须先标定基线**：本机 `hostname.exe` 都要 144.9ms（Defender），
  AHK 空脚本 163.5ms → **引擎自身仅 ≈19ms**。绝对值不可跨机比。
- **热键注册边际成本平坦 38~55µs/个**（108 个共 4.48ms、0 错误）→
  源码里 `Manifest` 每次全量扫描导致的 **O(n²) 只是最坏界，n≤108 实测不出**；
  **源码复杂度结论必须拿实测兜底，别直接当瓶颈写进清单**。
- 热键端到端时延 p50 **0.64~0.86ms**（两次运行），不是瓶颈；裸 `SendInput` 三档 InputLevel 全中。

## AHK 测试的坑

- ⚠️ **时延类断言统计口径**：`_Pct(arr,0.95)` 索引 = `Ceil(n*0.95)`，**n=7 时断言的是最大值**。
  时延/保持时长断言要 **≥40 样本**再算 P95；**判断「是否漂移」用中位数**。
  **不要用 Map 收集中间结果**（同名键互相覆盖后只剩一个样本）。
  ⚠️ **宿主抖动无法从代码侧消除**（kpd 15ms、预算 20ms，余量 5ms），系统繁忙时偶发 28/78ms 离群
  —— 这是「只在负载高时失败」的典型形态，别误判成回归。
  ⚠️ **样本够多也不保险**：离群点幅度（~15ms = 一个网格）远大于阈值（1ms），所以 P95 实际
  只容忍 `floor(0.05n)` 个离群点——**n=54 也只容忍 2 个**。保持时长断言一律用
  **中位数 ≤1ms 判漂移 + P95 ≤20ms（一个调度网格）兜底**。
  实测（hybrid，5 轮×54）：p50 稳定 **0.033ms**、max 14.98ms 且仅 1/54；
  但 CI 紧跟 24s cargo test 后离群点达 3 个 → `P95≤1.0` 误报（11.2ms）。
  hybrid 两个子组并发 → 占用更高、离群点比 periodic/sequence 更多。
  实例：`SleepUntil` 定位误差断言（n=30、P95≤1.0）在 CI 拿到 **3.817ms** 离群而红，
  本地同代码却全绿 → 已改 **n=60 + 中位数≤1.0 + P95≤5.0 兜底**（`7cc7dce`）。
  同理 `PressPrecise` 保持时长由**单样本**改为 9 次取中位数。
- ⚠️ **「脏环境假阳性」**：断言路径与组件实际写入路径不一致时，只要该路径恰好已存在就一直绿。
  **断言取组件自己的值**（`DebugLogger.logFile`）。
- `AutoHotUnitSuite` **下划线开头方法不收集为用例**。
- 对 **Object 形态**（`{type:"ERROR"}`）**不能用 `[]` 取值**，须 `.prop` 或先判 `e is Map`。
- 隔离跑单个套件：复制 `run_all_tests.ahk` → 只注册目标套件 + 换日志名，跑完删掉。
- ⚠️ **汇总不进 stdout**：直连跑 `run_all_tests.ahk` 时 `>file` 恒为 **0 字节**（GUI 子系统），
  结果写进 **`tests/test_results.log`**（已被 `*.log` 忽略）。判成败读后者，别被空日志误导。

## 环境 / CI / E2E（完整版见 `env-and-ci.md`）

1. 推送：`git -c credential.helper= push "https://x-access-token:$(gh auth token)@github.com/zyejf/AutoHotkeydemo.git" main`；
   失败多为代理 502，**重试 1–3 次**。⚠️ 重试循环里 **`git push ... | tail && break` 是错的**
   （`&&` 取 `tail` 退出码恒 0）→ 判 `${PIPESTATUS[0]}`。`gh api` 需 `GH_TOKEN=$(gh auth token)`。
2. ⚠️ Bash 命令里**不要出现 `powershell`/`pwsh`/`reg.exe`**（整体拦截）。
3. ⚠️ `cargo clippy`/`cargo test` 可能 **ICE**（退出码 101）→ `CARGO_INCREMENTAL=0`，不是代码问题。
4. `AutoHotkey64.exe` 是 GUI 程序：PowerShell 须 `Start-Process -Wait -PassThru`；从 Bash 调用更简单。
5. E2E：debug 构建**一定走 Vite devUrl**，`"Origin header is not a valid URL"` 是「页面没加载」的
   下游症状（**改 `useHttpsScheme` 不对症**）；看 `window.location.protocol` 是否 `chrome-error:`。
