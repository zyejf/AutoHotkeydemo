# 项目长期记忆 — ASD 技能管理器

> 长期有效的事实与约定。临时状态见 `YYYY-MM-DD.md`。
> 详见：`env-and-ci.md`（环境/CI/E2E）、`contracts-and-pitfalls.md`（契约统计命令/易误判点/BUG-6）。

## 文档权威边界（四方，各自领域内唯一）

| 文档 | 权威领域 |
|------|---------|
| `AGENTS.md` | 架构决策、分层规则、妥协白名单、关键文件清单 |
| `asd-tauri/docs/test-map.md` | **一切测试数字**（其它文档只写指针） |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 |
| `docs/graph-driven-workflow.md` | 图谱方法、开发/审查流程、同步机制 |

冲突：数字→test-map；架构→AGENTS；命令→developer-guide；流程→graph-driven-workflow。
**矛盾必须当场修正，不允许两边都留着。**

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
| `SetTimer`/`Sleep` | 锁死 **15.625ms 网格**；请求 1/5/10/15 均 ~15.6；**请求 16 反得 ~31** |
| `timeBeginPeriod(1)` | 对 AHK **完全无效** |
| 一次性 `SetTimer(-1)` | 空闲时中位 **15.67ms**（0.23ms 是探针自身假象） |
| **QPC 忙等** | 误差 **0.0017ms** —— 唯一精确手段 |

精确定刻规范（AGENTS.md §高精度定刻规范，7 条）：
① <50ms 精度一律用 `HighResClock`，禁 `A_TickCount`；② 到点用 `SleepUntil`，禁 `Sleep` 收尾；
③ 提前唤醒量 ≥1 网格+抖动（`WAKE_LEAD_MS=28`；18 会把保持压到 8ms）；
④ 推进基准用**本次计划时刻**；⑤ 滞后**禁止**重置基准为当前时刻（→ 保相位 + `droppedTriggers`）；
⑥ 同刻多键**必须分桶批量** Down→等→Up（串行会让第二个键保持塌到 0.02ms）；
⑦ 序列首步基准在**首次执行**时确立（`nextStepTime := 0` 哨兵），不能取启动调用时刻。

⚠️ **代价：连续占用 AHK 主线程**（`SleepUntil` 的 `Sleep(0)` 不放行其它 AHK 定时器）。
实测 interval=100/kpd=15：扣除网格后**最长连续占用 31.4ms、占空比 29.2%**，
IPC/热键最多被推迟 ~31ms（旧实现完全不阻塞）。新增定刻点前必评估。

实测「计划时刻→抬起完成」P95：periodic 旧 16~27ms → 新 **15.0ms**；interval=20 旧 ~2000ms → 新 15.0ms；
sequence 旧 248~263ms → 新 14.97ms；hybrid 子组各自保持 100/300ms。
报告 `docs/perf/key-latency-benchmark-2026-09-13.md`。
**Rust 侧下沉不可行**：`SendLevel(10)`+`InputLevel(11)` 使 Rust `SendInput` 被 AHK 当物理键 → 自触发死循环。

## 工程约定

- 换行符：`.gitattributes` 强制 LF（`.ps1`/`.bat`/`.cmd` 除外）。Edit 可能引入 CRLF，改完用 Python 校验。
- Conventional Commits，描述用中文。⚠️ scope 正则 `[a-z-]+` **不允许数字**（`fix(e2e)` 因含 `2` 被拒）。
  长信息 `git commit -F <file>`（**不接受 MSYS 路径**，须 `cygpath -w`）；`-F` 与 `-m` 不能同用。
- ⚠️ **禁用 `git rm`/safe-delete**（路径拼接 bug 会连带删 54 文件）→ `mv` 到 /tmp + `git add -A`。
- 提交信息**不写具体测试数字**；文档与代码**同 PR**。
- AHK v2：箭头函数 `=>` **只支持表达式体**；类**静态方法只读** → 用注入字段（如 `_sendHook`）。
- AHK v2 保留字不能作变量名（`log`/`in`/`out`…）；`while i<=n {` 不能写单行块体。
- 脚本级变量**不会**被箭头函数闭包捕获（函数 assume-local）→ 包进 `Main()` 或 `global`。

## AHK 测试的坑

- ⚠️ **时延类断言统计口径**：`_Pct(arr,0.95)` 索引 = `Ceil(n*0.95)`，**n=7 时断言的是最大值**。
  时延/保持时长断言要 **≥40 样本**再算 P95；**判断「是否漂移」用中位数**。
  **不要用 Map 收集中间结果**（同名键互相覆盖后只剩一个样本）。
  ⚠️ **宿主抖动无法从代码侧消除**（kpd 15ms、预算 20ms，余量 5ms），系统繁忙时偶发 28/78ms 离群
  —— 这是「只在负载高时失败」的典型形态，别误判成回归。
- ⚠️ **「脏环境假阳性」**：断言路径与组件实际写入路径不一致时，只要该路径恰好已存在就一直绿。
  **断言取组件自己的值**（`DebugLogger.logFile`）。
- `AutoHotUnitSuite` **下划线开头方法不收集为用例**。
- 对 **Object 形态**（`{type:"ERROR"}`）**不能用 `[]` 取值**，须 `.prop` 或先判 `e is Map`。
- 隔离跑单个套件：复制 `run_all_tests.ahk` → 只注册目标套件 + 换日志名，跑完删掉。

## 环境 / CI / E2E（完整版见 `env-and-ci.md`）

1. 推送：`git -c credential.helper= push "https://x-access-token:$(gh auth token)@github.com/zyejf/AutoHotkeydemo.git" main`；
   失败多为代理 502，**重试 1–3 次**。⚠️ 重试循环里 **`git push ... | tail && break` 是错的**
   （`&&` 取 `tail` 退出码恒 0）→ 判 `${PIPESTATUS[0]}`。`gh api` 需 `GH_TOKEN=$(gh auth token)`。
2. ⚠️ Bash 命令里**不要出现 `powershell`/`pwsh`/`reg.exe`**（整体拦截）。
3. ⚠️ `cargo clippy`/`cargo test` 可能 **ICE**（退出码 101）→ `CARGO_INCREMENTAL=0`，不是代码问题。
4. `AutoHotkey64.exe` 是 GUI 程序：PowerShell 须 `Start-Process -Wait -PassThru`；从 Bash 调用更简单。
5. E2E：debug 构建**一定走 Vite devUrl**，`"Origin header is not a valid URL"` 是「页面没加载」的
   下游症状（**改 `useHttpsScheme` 不对症**）；看 `window.location.protocol` 是否 `chrome-error:`。
