# 项目长期记忆 — ASD 技能管理器

> 长期有效的事实与约定。临时状态见 `YYYY-MM-DD.md`。
> 详见：`env-and-ci.md`（环境/CI/E2E）、`contracts-and-pitfalls.md`（契约统计命令/易误判点/BUG-6）。

## 文档权威边界（五方，各自领域内唯一）

| 文档 | 权威领域 |
|------|---------|
| `AGENTS.md` | 架构决策、分层规则、妥协白名单、关键文件清单 |
| `asd-tauri/docs/test-map.md` | **一切测试数字**（其它文档只写指针） |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 |
| `docs/tech-debt-register.md` | **技术债债项与状态（唯一登记处）**；配套 `docs/tech-debt-plan-2026-09-16.md` |
| `docs/graph-driven-workflow.md` | 图谱方法、开发/审查流程、同步机制 |
| `docs/research/` | **架构级调研结论唯一落点**（外部引擎/第三方源码走查 + 实测）；探针在 `tools/ahk-probes/` |

冲突：数字→test-map；架构→AGENTS；命令→developer-guide；流程→graph-driven-workflow；
外部引擎调研→`docs/research/`。
**矛盾必须当场修正，不允许两边都留着。**

> AHK v2 引擎调研（2026-09-14）：`docs/research/ahk-engine-architecture-2026-09-14.md`
> —— 含源码锚点、10 个探针实测数据、16 条执行摘要、L1/L2/L3 共 22 项落地清单。
> 引擎源码 `AutoHotkey-2.0.26/source` **只读**（不修改/不 fork/不编译）。
> 该目录由 `check-tech-debt.py` 的 **C6** 守住：必须与官方 tag v2.0.26 **不多、不少、不改**（基线 `scripts/vendor-baseline-ahk-2.0.26.txt` 取自上游，非本地快照）。
> **不要改成 submodule**：研究报告对它做了 60+ 处行级引用，submodule 会让普通 clone 得到空目录、引用悬空。它是只读研究参考不是构建依赖（CI 不碰），7.9M 只占 `.git` 100M 约 8%。

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
⑧ 调度时刻一律整数 µs，`Round()` 不可省；⑨ 遍历只能 4→2（开关两侧须同步改）；
⑩ **没有 `SleepUntilUs` 兜底的路径，定时器周期必须 `Ceil` 不能 `Round`** ——
   Round 早醒 ≤0.5ms → 无键到期 → 再排 <1ms 定时器 → 被 `Max(1,…)` 抬成网格白吃一格
   （实测 joystick 序列 3 秒漂移 +15.1~17.2ms → Ceil 后 +1.9~10.7ms）。
   sender 用 Round 没事：它有 28ms 提前量 + `SleepUntilUs` 精修。
   ⚠️ 同理：**`TIMING_EPSILON_US` 在「提前返回处不带容差」的结构下是死代码**（单键场景
   `target == dueAt`，提前返回后走不到 epsilon）。joystick 已删掉它。

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
⚠️ **四种调度模式实为两套内核**：`enhanced_periodic`/`enhanced_sequence` = `StartPeriodic`/`StartSequence`
+ 改写 `state["mode"]` 标签，差异只在配置字段名（`pressKeys`/`pressDelays` vs `keys`/`delays`，
`executor.ahk:303-310`）。`state["mode"]` **只写不读**，不参与任何运行时分支。
⚠️ **分桶键是浮点 dueAt**（`triggerTimes[i] + interval`，`HighResClock.Now()` 返回 ms **浮点**）：
数学上同刻的两个键若末位不同会被拆成两个桶 → 后者保持时长塌成 ~0ms，正是批量化要解决的问题本身。
规划中的修法：时刻改用**整数**（微秒或 QPC 计数）表示，顺带拿到确定性。

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

## 生产基准门禁（T11，gate.py）：共享 runner 上**绝对毫秒不可用**

**硬事实**：同一份代码在 GitHub 托管 runner 上跨 run 的**绝对**耗时散布达 **3.7~3.9 倍**
（实测 0.52× / 0.79× / 0.92× / 1.07× / 1.87~2.09×，且同一 run 内 5 个 metric **同步**移动）。
历史文档里「runner 池 ±10~17% 波动」是**严重低估**，勿引用。

- 绝对值基线两头不讨好：慢机器上**无变化也 FAIL**；快机器上真实 2× 回退读成 1.04× 而 **PASS（漏报更危险）**。
- 故两个 bench（`prod_escape` / `prod_tick`）的 p50 **都是归一化值** = 被测耗时 ÷ 同进程紧邻测得的
  参考负载耗时（与被测代码无关的纯 AHK Array 算术循环）；原始毫秒留在 `raw_ms=` 仅供排障。
- 归一化后：两次独立 CI 相差 1.018~1.101×、本地跑 CI 基线 1.00~1.17×、最终 CI 8 档 0.98~1.03×。
- `gate.py` **不认 info 行**，加归一化不必改它。

**⚠️ 参考负载对 CPU 争用「过度校正」但方向安全**：20 满载进程（12 线程超订）下参考负载 +37~40%，
而转义负载只 +0~43%（payload 越大越偏内存/GC，对 CPU 争用越不敏感）→ 归一化值落到 0.71~1.02×。
即争用只会**压低**读数（不误报、灵敏度下降）→ **别据此收紧 K**。

**K 按各 bench 的信噪比分别定**，不是统一值：
`prod_escape` **1.5 / warn 1.25**（T1 信号 41~49×，可松）；`prod_tick` **1.4 / warn 1.2**（T6 信号仅 ~1.7×，必须紧）。

**定性手法（可直接复用）**：多个 metric 的倍率若**挤在同一窄带**＝整机速度因子；若是某条代码路径退化，
不同路径的倍率会**严重分化**（例：T1 回退时 plain_* 涨 40× 而 ctrl 兜底档 0.99× 不动）。
配合「拉历史倍率序列」即可区分误报与真实回归。

## 技术债度量闸门（`scripts/check-tech-debt.py`，**G3e**，2026-09-16 起在四闸门内）

六信号：C1a 孤儿文件 / C1b 同名重复 / C1c 代码误放 `docs` 等目录 / C2 `tests/` 未接入执行 /
C3 文档-代码一致性 / **C3b 文档硬写的 AHK 基线数字**。
**C1a/C1b/C1c/C2/C3b 走棘轮**（基线内存量债只登记，只有新增项 FAIL），
**C3 不做棘轮、恒 0 硬阻断**。基线：`.review-analysis/tech-debt-baseline.json`，
清理后用 `--update-baseline` 收紧水位（基线 diff 必须出现在 CR）。约 2.5s。

接入点：`check-gates.sh` / `.ps1` 的 G3e（**不随 `--quick`**）；
⚠️ `.github/workflows/ci.yml` 是**独立实现**，不复用闸门脚本，加闸门要改两处。

- ⚠️ **C3b 的写法约定**：文档里**不要复写 AHK 用例总数**，写「见 test-map.md」指针。
  带日期的历史报告里的数字是当日快照，**改它等于篡改历史**，登记豁免即可。
  **举例要写在反引号里** —— 匹配前会剔除反引号片段，裸数字才拦
  （上线第一天台账描述 C3b 自身时举的例子把自己拦了）。
- ⚠️ **「在 tests/ 目录下」不等于「是测试」**：判测试看有没有 `Test_` 函数与 runner 入边，
  `tests/legacy/json.ahk`（1469 行，0 个 `Test_`）就是这样伪装了很久。

- ⚠️ **「数字在文档里出现过」不是一致性证据**：`format(2.0,'g')` == `"2"`，会把
  「AutoHotkey v2.0」「2 个基准脚本」都命中。判 K 值漂移必须 **数字与 bench 名同行**、只认
  小数形态、且排除 `v2.0` 版本号上下文。否则真实漂移照样绿（9 月已发生过一次）。
- ⚠️ 全仓 `Path.rglob` 在本仓库**必须先剪枝**：`asd-tauri/src-tauri/target` 几十万文件，
  光枚举 23s；剪掉 `target/node_modules/.git/AutoHotkey-2.0.26/archive` 后 2.5s。
- 只扫 AHK；JS/TS 的孤儿与未注册测试**未覆盖**（已知盲区）。

## 工程约定

- 换行符：`.gitattributes` 强制 LF（`.ps1`/`.bat`/`.cmd` 除外）。⚠️ 既有入库文件在 worktree
  里**本来就是 CRLF**（`check-test-map.py` 全 230 行 CRLF），`eol=lf` 只在入库时归一化，
  所以新文件落盘成 CRLF 不必手工转。Edit 可能引入 CRLF，改完用 Python 校验。
- Conventional Commits，描述用中文。⚠️ scope 正则 `[a-z-]+` **不允许数字**（`fix(e2e)` 因含 `2` 被拒）。
  长信息 `git commit -F <file>`（**不接受 MSYS 路径**，须 `cygpath -w`）；`-F` 与 `-m` 不能同用。
- ⚠️ **禁用 `git rm`/safe-delete**（路径拼接 bug 会连带删 54 文件）→ `mv` 到 /tmp + `git add -A`。
- 提交信息**不写具体测试数字**；文档与代码**同 PR**。
- ⚠️ 改完 AHK 测试要同步 **test-map 三处**：① 明细行（如 test_sender 13/57）②《汇总》表的
  AHK 两行（执行器套件/方法数、完整套件用例数与套件数）③ 文首「口径提示」里的静态/实跑数。
  只改①不改②③是**已犯过两次**的错。
- AHK v2：箭头函数 `=>` **只支持表达式体**；类**静态方法只读** → 用注入字段（如 `_sendHook`）。
- AHK v2 保留字不能作变量名（`log`/`in`/`out`…）。
- ⚠️ AHK **标识符大小写不敏感** → 全局常量 `SAMPLES` 与局部 `samples := []` 是同一个变量；
  带 `global SAMPLES` 声明后给 `samples` 赋值会把常量写成数组。基准/脚本里的常量名
  必须带前缀（如 `BATCH_CALLS`）与局部变量区分。
- ⚠️ AHK 里 `if true` **实测不生效**，要用 `if 1`（写变异测试时踩过）。
- ⚠️ **AHK 源码里「一个反斜杠」写作 `"\"`，不是 `"\\"`**（双引号串中 `\\` 才表示一个
  反斜杠）。用 Python 写变异/替换脚本时极易因 `repr` 的转义把数量数错一倍 ——
  匹配失败必须先 hexdump 逐字节对比，别直接跳过（「变异未生效」≠「变异被捕获」）。
  字符串字面量里反斜杠是普通字符、只有双引号需写成两个；混用会报 `Missing """`
  → 构造含引号/反斜杠的测试数据一律用 `Chr(34)`/`Chr(92)`。
- ⚠️ AHK v2 **不接受单行花括号块体**：`F(x) { return x * 2 }` 报 `Unexpected {`，
  必须换行写。函数体、`while`/`if` 的 `{}` 都一样（不是只有 `;` 被当注释的问题）。
- ⚠️ AHK v2 **标识符大小写不敏感**：函数名 `Spaces` 与调用方局部变量 `spaces` 同名时，
  `Spaces(cur)` 被解析成那个未赋值的局部变量 → `This local variable has not been assigned
  a value`，且报错行指向**调用方**（极难定位）。生产用 `this._BuildSpaces`（方法调用）天然躲开；
  自写工具函数请带前缀或用 `_` 开头。
- AHK v2 `VarSetStrCapacity(&var, n)` 可用（n 为字符数），`static c := Map()` 惰性初始化可用。
- ⚠️ AHK v2 `result .= s` **不是 O(n²)**（实测字符 4.10× → 耗时 4.12×，严格线性）。
  换 Buffer+`StrPut` **慢 46%**、换数组聚合 **慢 13%**、换「零中间字符串单一累加器」**无差异**。
  JSON 序列化成本 ≈ **0.24 µs/字符**的解释器常数 → **不要优化累加方式**，出路只有「少序列化」（缓存/增量）。
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
- ⚠️ **回归用例必须选「判别性取值」，否则是假阴性**。踩过的坑：用 33.333/99.999 断言
  「浮点毫秒不拆桶」—— 但 `33.333*1000` 在双精度下**恰好 = 33333.0**（99.999 同理），
  浮点实现也返回精确整数，用例恒绿。要挑乘倍数后**非整数**的值：
  **16.001 → 16001.000000000002**、**1/7 → 142.857…**（≥10ms 的 3 位小数里有 5718 个可用）。
- ⚠️ **依赖运行时量级的行为类用例是弱守卫**，必须配一条确定性单元用例。
  实例：端到端「1:3 不拆桶」用例的浮点拆桶率取决于 uptime 位模式（48%~85%，
  即约 20% 概率假阴性通过）；阳性对照下去掉 `Round()` 它仍然绿。
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

### 宿主时延断言：不要在共享 runner 上做硬判（`ASD_HOST_TIMING`）

- ⚠️ **绝对墙钟时延断言在共享 CI runner 上不可判定**（不是阈值没调好）。
  定刻走 **QPC 忙等**，CPU 争用下不是「变慢」而是**量级崩塌**，且存在**悬崖**：
  本机 12 线程施加 N 个满载进程 → SleepUntil 误差 p50 / periodic 端到端 p50：
  空载 0.005 / 15.015 → 11 进程 **0.005 / 15.015**（中位数毫无变化）→
  14 进程 **19.22 / 28.45**（一起崩）→ 24 进程 ~111 / ~745。
  CI（2 vCPU 共享）正落在 11~14 之间 → **中位数也守不住，放宽 P95 无用**。
- ⚠️ **决定性证据**：注入「定刻退化成网格 `Sleep`」缺陷后 periodic 端到端 P95 = **31.76ms**，
  与 CI 失败值 **31.86ms** 几乎相同 → **共享 runner 上「实现退化」与「宿主忙」数值无法区分**。
- ⚠️ **别用「会让出 CPU 的探针」给忙等定刻做归一化**：`Sleep 1` 超调地板在 24 burner 下只涨
  0.44ms，而实际超额 100~700ms，完全不相关。（prod_tick 的参考负载归一化能成立，
  是因为参考负载同为 AHK 解释器算术循环，性质匹配。）
- **现行处置**：`SenderPreciseTimingTests._HostTiming()` 门控 7 条绝对时延断言，
  由 `ASD_HOST_TIMING=0` 关闭（缺省执行）。CI G3b 设 0，本机四闸门不设 → 照跑（真正守护点）。
  CI 会校验「跳过数 ≥1」，防止门控静默失效。
- 框架：`AutoHotUnit.ahk` 有 `AhuSkip extends Error` + `assert.skip(reason)`。
  ⚠️ `RunSuites` 里 `catch AhuSkip` 必须排在 `catch Error` **之前**（继承，反了会被吞）。
  ⚠️ `SilentReporter` 在 **`tests/suites/core_suites.ahk`**（不在 AutoHotUnit.ahk）；
  汇总新增的「跳过」行必须排在「失败」**之后**，否则 CI 的 `总计/通过/失败` 正则被打乱。
- ⚠️ 变异测试纪律：改实现前先 `cp` 备份，还原后校验「文件中不再含 MUTATION 标记」。
  ⚠️ **Sender 走 `SleepUntilUs`（µs 口径）不是 `SleepUntil`** —— 只变异 ms 版只能红 1 条。

## 环境 / CI / E2E（完整版见 `env-and-ci.md`）

1. 推送：`git -c credential.helper= push "https://x-access-token:$(gh auth token)@github.com/zyejf/AutoHotkeydemo.git" main`；
   失败多为代理 502，**重试 1–3 次**。⚠️ 重试循环里 **`git push ... | tail && break` 是错的**
   （`&&` 取 `tail` 退出码恒 0）→ 判 `${PIPESTATUS[0]}`。`gh api` 需 `GH_TOKEN=$(gh auth token)`。
2. ⚠️ Bash 命令里**不要出现 `powershell`/`pwsh`/`reg.exe`**（整体拦截）。
3. ⚠️ `cargo clippy`/`cargo test` 可能 **ICE**（退出码 101）→ `CARGO_INCREMENTAL=0`，不是代码问题。
4. `AutoHotkey64.exe` 是 GUI 程序：PowerShell 须 `Start-Process -Wait -PassThru`；从 Bash 调用更简单。
5. E2E：debug 构建**一定走 Vite devUrl**，`"Origin header is not a valid URL"` 是「页面没加载」的
   下游症状（**改 `useHttpsScheme` 不对症**）；看 `window.location.protocol` 是否 `chrome-error:`。
