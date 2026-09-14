# AHK v2 引擎架构分析报告（源码级 + 实测佐证）

- 日期：2026-09-14
- 引擎版本：**AutoHotkey v2.0.26**（`AutoHotkey-2.0.26/source`，170 文件 / 53 `.cpp`，已 vendored 入库）
- 范围：执行模型、脚本解析机制、热键热字符串注册流程、消息循环处理原理；以及性能 / 稳定性 / 鲁棒性三方向的改进方案
- 性质：**源码走查 + 实际运行探针**（非静态推测）。所有关键结论均可追溯到「源码 `文件:行号`」或「探针 P# 实测数据」
- 引擎源码：**只读分析**，未修改、未 fork、未自行编译
- 生产代码：**未改动**（探针脚本为新增文件，位于独立目录）
- 文档权威边界：本报告只记录本次结论；**测试数字的权威来源为 `asd-tauri/docs/test-map.md`**，冲突以其为准

---

## 一、执行摘要

| # | 结论 | 证据 | 影响 |
|---|---|---|---|
| 1 | **AHK 启动不慢**：空脚本进程墙钟 163.8 ms，但本机「创建并等待任一进程」的基线就有 144.9 ms | P1 + `hostname.exe` 对照 | 引擎自身开销仅 **≈19 ms**，优化启动应去优化**进程创建次数**而非脚本体积 |
| 2 | **解析很便宜**：1.33 µs/行；20 000 行只增加 ~26 ms | P1 | 脚本规模不是启动瓶颈 |
| 3 | **`#Include` 是真瓶颈**：**592 µs/文件**（与文件内行数无关） | P1 (`inc_1000_x1` Δ0.51 ms → `x50` Δ29.5 ms) | 拆文件越多越慢；本项目 6 个文件影响可忽略，但需警惕膨胀 |
| 4 | **15.625 ms 网格根因闭环**：`SLEEP_INTERVAL=10` → `SetTimer` 请求 10 ms → OS 量化 → `WM_TIMER` → `CheckScriptTimers()` | `globaldata.h:218/237-239`、`application.cpp:1342-1352` + P2 | 引擎**主动放弃** `timeBeginPeriod`（`globaldata.h:213-215`） |
| 5 | **`timeBeginPeriod(1)` 对本引擎完全无效**（有配对对照组 + 复原确认） | P2：SetTimer gap p50 15.985 → 15.995 ms | 唯一亚毫秒手段是 **QPC 忙等** |
| 6 | **Sleep 断点在 21 ms**（不是 16 ms）：请求 ≤20 ms 一拍 ~15.9 ms，≥21 ms 两拍 ~31 ms | P2 + `application.cpp:1481` 判据 `D - elapsed ≤ SLEEP_INTERVAL_HALF` | 修正既有认知；20 ms 是「单拍可得」的上限 |
| 7 | **QPC 自旋期间消息泵并未停摆**（`Sleep(0)` 会驱动泵） | P3：自旋 100 ms 期间探针仍触发 7 次（理论 6.4） | 「忙等 = 冻结一切」是误解；真实代价是 **gap p95 从 16.6 升到 ~27 ms** |
| 8 | 现网 `WAKE_LEAD_MS=28` 处于**合理保守位**：占用 20.5% 占空比；降到 16/8 会产生 13~17%「睡过头」 | P3 | 想降占用必须换策略，不能简单调小 lead |
| 9 | **热键端到端时延 p50 ≈ 0.86 ms**，p95 1.30 ms | P4 | 热键链路本身不是瓶颈，瓶颈在调度侧 |
| 10 | **裸 `SendInput`（`dwExtraInfo=0`）能触发任意 InputLevel 的热键**（IL0/IL1/IL11 全中） | P4 phase4 | 坐实「Rust 侧下沉不可行」；且 `SendLevel(10)+InputLevel(11)` **挡不住**它 |
| 11 | **循环引用 100% 泄漏**：5 万个带环 Map 常驻 **+22.9 MB**；无环对照组仅 +64 KB | P5 | 纯引用计数、无环检测器（`script_object.h:16-68`） |
| 12 | **热键注册永不回收**：1080 次注册 **+452 KB**，SimpleHeap 只增不还 | P5 + `SimpleHeap.cpp:114-125` | 频繁增删热键是长期内存增长源 |
| 13 | **长路径无 MAX_PATH 限制**：30 038 字符（无 `\\?\` 前缀）读写全部正常 | P6 | 该风险项可排除 |
| 14 | **CP936/ANSI 码页会静默丢字符**：长度不变、内容变 `?` | P7 | 最难排查的一类 bug；IPC 必须锁定 UTF-8 |
| 15 | **递归上限 ~1200–1500 层，且 `try/catch` 捕获不到**（直接以 ExitApp 模式终止进程） | P9 | 深递归是本引擎硬边界，业务侧必须改写为迭代 |
| 16 | **`#MaxThreads` 不能当背压**：30 个并发定时器在默认 10 下**全部执行** | P9 | 需要背压必须自己实现 |

---

## 二、方法与环境

### 2.1 二进制一致性（P0，前置校验）

| 项 | 值 |
|---|---|
| `asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe` | 1 272 832 B |
| `D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` | 1 272 832 B |
| 两者 SHA256 | `a2a54b8abc476d7671d4de0771bb54bf5f2373d79ff6871d0ba6a62c3b88ae00`（**完全相同**） |
| `A_AhkVersion`（P0 探针实读） | **2.0.26**，与 vendored 源码版本一致 |

→ 后续所有实测结论对本项目有效，无「探针跑的引擎 ≠ 项目用的引擎」失真。

### 2.2 探针 harness

`AutoHotkey64.exe` 是 **GUI 子系统**程序：`cmd` 的 `start`、PowerShell 的 `&` 启动它**不会等待**；且未捕获错误会弹**模态错误框**导致永久挂起。因此：

- 结果一律 `FileAppend` 到 `%TEMP%\ahkprobe\<id>.csv`，结束前写 `<id>.done` 哨兵；
- 运行器 `tools/ahk-probes/run.sh` 轮询哨兵判定结束（**不依赖 stdout、不依赖退出码**）；
- `_harness.ahk` 注册 `OnError` 守卫，把未捕获错误写进 CSV 后 `ExitApp`，杜绝弹框挂死。

统计口径统一用 QPC（不是 `A_TickCount`）。

### 2.3 本机基线标定（关键，否则绝对值会误读）

| 被测 | min / p50 / max (ms) |
|---|---|
| `hostname.exe`（极小 native 程序） | 131.03 / **144.85** / 476.50 |
| AHK —— 不存在的脚本（创建+早期初始化即退出） | 132.96 / 136.58 / 173.24 |
| AHK —— 空脚本 | 149.42 / **163.54** / 194.71 |
| AHK —— 20 000 行 | 188.08 / 194.21 / 289.87 |

**导出**：AHK 引擎自身开销 ≈ 163.5 − 144.9 ≈ **19 ms**；其中「加载并执行一个空脚本」再占 ≈ 27 ms（163.5 − 136.6）。绝对数值受本机 Defender 实时扫描影响，**跨机不可比，但相对增量可比**。

---

## 三、引擎骨架（一条主链路）

```
_tWinMain                        AutoHotkey.cpp:66
  ├─ EarlyAppInit                AutoHotkey.cpp:70
  ├─ ParseCmdLineArgs            AutoHotkey.cpp:73
  ├─ Script::LoadFromFile        script.cpp:1361   ← 解析全在这里（含 #Include 递归展开）
  │    ├─ LoadIncludedFile       script.cpp:3542   （#Include = 解析期文本展开）
  │    ├─ PreparseExpressions    script.cpp:1406   （表达式 → postfix）
  │    ├─ PreparseVarRefs        script.cpp:1409
  │    └─ PreparseCommands       script.cpp:1446   （跳转目标定址 / 终检）
  ├─ InitForExecution            AutoHotkey.cpp:273
  └─ MainExecuteScript           AutoHotkey.cpp:292
       ├─ ManifestAllHotkeys…    hotkey.cpp:202    ← 热键在 auto-exec **之前**生效
       ├─ AutoExecSection        script.cpp:961
       └─ MsgSleep(10, WAIT_FOR_MESSAGES) application.cpp:25 ← 消息泵在 auto-exec **之后**
```

三个值得记住的结构事实：

- **`Line` 是双向链表**（`script.h:717-726`，有 `mPrevLine/mNextLine/mRelatedLine/mParentLine`），跳转在加载期解析成 `Label::mJumpToLine` 指针，运行期是 **O(1)**（`script.cpp:9840`）；只有 `Goto(%var%)` 这类动态目标才退化成 `FindLabel` 线性扫描。
- **「线程」不是 OS 线程**，而是 `g_array[]` 下标 + 独立 Line 游标（`application.cpp:1857-1866` 的 `InitNewThread` 只做 `++g; memcpy(settings)`）。默认上限 10、硬顶 255（`script.h:36-38`）。
- **消息泵是单线程协作式**：`GetMessage()` 阻塞等待 `WM_TIMER`（`application.cpp:227-243`），热键/定时器靠递归 `MsgSleep` 实现「抢占」。

---

## 四、逐项结论

### §4.1 启动与初始化链路〔T1, P1, P8〕

**结论：启动优化的正确目标是「减少进程创建次数」和「减少 `#Include` 文件数」，不是「精简脚本行数」。**

| 场景 | p50 (ms) | 相对空脚本 Δ |
|---|---|---|
| `empty` | 163.84 | — |
| `parse_1k`（1 000 行，函数内不调用） | 165.11 | +1.27 |
| `parse_20k` | 190.40 | +26.56 |
| `exec_1k`（1 000 行，真正执行） | 164.53 | +0.69 |
| `exec_20k` | 190.03 | +26.19 |
| `inc_1000_x1`（1 000 行 / 1 文件） | 164.35 | +0.51 |
| `inc_1000_x10`（1 000 行 / 10 文件） | 170.04 | +6.20 |
| `inc_1000_x50`（1 000 行 / 50 文件） | 193.38 | +29.54 |
| `inc_5000_x50`（5 000 行 / 50 文件） | 196.48 | +32.64 |

派生：

- **解析斜率 1.33 µs/行**（1k→20k）；**执行斜率 1.34 µs/行** → 解析与执行同量级，都便宜。
- **`#Include` 边际成本 ≈ 592 µs/文件**，与文件内行数几乎无关（5 000 行 50 文件 ≈ 1 000 行 50 文件）。
- 源码侧印证：`LoadIncludedFile` 每次都要做路径规范化 + 查 `sSourceFile` 去重表（`script.cpp:1644`），且**所有被包含文件并入同一条全局 Line 链表**，文件数不降低任何运行期查找成本（`script.cpp:1752`、`script.h:719`）。
- 启动期唯一的非线性项是 `ManifestAllHotkeysHotstringsHooks()`（`hotkey.cpp:202`）：三趟全表扫描，key-up 热键还带一层 O(n) 内层（`hotkey.cpp:303-319`）→ 最坏 **O(n²)**。源码自述 high-overhead（`hotkey.cpp:1080`）。

> 本项目 6 个 `.ahk` 文件 → `#Include` 成本约 3.5 ms，可忽略。

### §4.2 定时器与 15.625 ms 网格根因〔T5, P2〕★

**完整因果链（每环都有源码锚点）：**

| 环 | 源码锚点 | 内容 |
|---|---|---|
| 1 | `globaldata.h:218` | `#define SLEEP_INTERVAL 10` |
| 2 | `globaldata.h:237-239` | `SET_MAIN_TIMER` = `SetTimer(g_hWnd, TIMER_ID_MAIN, SLEEP_INTERVAL, NULL)` |
| 3 | `globaldata.h:213-215` | 注释明说**故意不用** `timeBeginPeriod`：「possible incompatibilities … may degrade overall system performance」 |
| 4 | OS | 请求 10 ms 被夹到系统默认粒度（15.625 ms） |
| 5 | `application.cpp:1342-1352` | `case WM_TIMER:` → `CHECK_SCRIPT_TIMERS_IF_NEEDED` |
| 6 | `application.h:75` → `application.cpp:1500` | `CheckScriptTimers()` **线性扫单链表**（`script.h:1864` `mNextTimer`） |

源码里**没有 15.625 这个数字**——它来自 Windows，引擎把定时精度完全外包给 OS 且**不做补偿**。

**实测（P2）：**

| 指标 | 结果 |
|---|---|
| `A_TickCount` 步进 | p50 **16 ms**、min 15、max 16（15.625 网格坐实；**测不了 20 ms 内的东西**） |
| `SetTimer(fn, 1)` 间隔 | p50 **15.985 ms**；直方图 184/189 落在 [14,17) |
| `SetTimer` + `timeBeginPeriod(1)` | p50 **15.995 ms**；直方图 179/187 落在 [14,17) → **零改善** |
| `Sleep(20)` | 基线 p50 15.954 / tbp1 16.033 |
| `Sleep(21)` | 基线 p50 **30.972** / tbp1 30.836 → 断点确在 21 |
| 复原确认（`timeEndPeriod` 后） | p50 15.964 → 与基线一致，无残留副作用 |

**Sleep 请求 → 实际（基线，p50 ms）：**

| 请求 | 1 | 5 | 10 | 15 | 16 | 20 | 21 | 25 |
|---|---|---|---|---|---|---|---|---|
| 实际 | 15.96 | 15.93 | 15.99 | 15.95 | **15.93** | 15.95 | **30.97** | 31.61 |

> **修正既有认知**：先前「请求 16 ms 反而得到 ~31 ms」的说法**不成立**。实测请求 16 的 p50 是 15.93 ms（max 31.59，只是偶发）。真实判据是 `application.cpp:1481`：
> `if (!aAllowEarlyReturn && (int)(aSleepDuration - (tick_now - aStartTime)) > SLEEP_INTERVAL_HALF) return FAIL;`
> 即「**剩余待睡眠时间 ≤ 5 ms 就返回**」，`allow_early_return` 只在 `D ≤ 5` 时生效。首拍 `elapsed` 被 `GetTickCount()` 量化成 15 或 16，故 `D ≤ 20` 一拍返回、`D ≥ 21` 需两拍。

**附带结论**：`CheckScriptTimers()` 每个定时器每次脉冲都要调一次 `GetTickCount()`（`application.cpp:1562`）→ **「定时器越多越慢」成立**，开销 ≈ O(启用定时器数) × 64 Hz。

### §4.3 主线程占用与定刻策略〔P3〕

**先纠正一个直觉：QPC 忙等 ≠ 冻结一切。**

| 自旋时长 | 期间探针定时器触发次数 | 若泵完全停摆应为 | 若泵正常应为 |
|---|---|---|---|
| 40 ms | 2 | 0 | 2.6 |
| 100 ms | 7 | 0 | 6.4 |

→ 泵**仍在跑**。原因是 `SleepUntil` 里的 `Sleep(0)` 在 AHK 中不是「空转让出 CPU」，而是 `ScriptSleep(0)` → `MsgSleep(0)` → `PeekMessage` 路径，**每次迭代都驱动一次消息泵**（`application.cpp:227-243`）。

**策略 trade-off（周期 100 ms，30 周期/策略）：**

| 策略 | 自旋 p50 | 自旋 max | 睡过头率 | gap p50 | gap p95 | gap max | 占空比 |
|---|---|---|---|---|---|---|---|
| lead0（纯 `Sleep(100)`） | 0.00 | 0.00 | — | 15.99 | 16.59 | 37.96 | 0.0 % |
| lead8 | 5.18 | 15.78 | **16.7 %** | 15.97 | 25.64 | 31.55 | 5.8 % |
| lead16 | 6.44 | 16.59 | **13.3 %** | 15.99 | 23.24 | 35.72 | 6.7 % |
| lead20 | 22.34 | 34.52 | 0.0 % | 15.98 | 27.16 | 30.72 | 22.6 % |
| **lead28（现网 `WAKE_LEAD_MS`）** | 19.45 | 32.10 | **0.0 %** | 15.99 | 27.24 | 45.65 | 20.5 % |
| lead40 | 37.82 | 50.54 | 0.0 % | 15.92 | 23.63 | 37.27 | 38.8 % |

读法：

- **占用随 lead 线性增长**：占空比 ≈ lead / 周期。现网 100 ms 周期 + 28 ms lead → ~20 % 的主线程被连续占住。
- **lead < 20 就开始「睡过头」**（8 → 16.7 %、16 → 13.3 %），即 `Sleep` 直接越过目标时刻、保持时长塌掉。这与记忆里「18 会把保持压到 8 ms」完全一致。
- **代价的真实形态**：不是「热键被无限期推迟」，而是 **gap p95 从 16.59 ms 抬到 ~27 ms**（多等约 10 ms），gap max 到 ~45 ms。
- **结论**：`WAKE_LEAD_MS=28` 是**合理保守**的。想进一步降占用，靠调小 lead 行不通（会漏），必须换策略（见 §5 L1-3）。

### §4.4 解析与执行模型〔T2, T3, P8〕

| 问题 | 结论 | 源码锚点 |
|---|---|---|
| 几遍扫描？ | 1 遍读行 + 3 趟后处理（`PreparseExpressions` / `PreparseVarRefs` / `PreparseCommands`） | `script.cpp:1388/1406/1409/1446` |
| `#Include` 何时展开？ | **解析期递归文本展开**，不是运行期加载 | `script.cpp:3542`、`script.cpp:2402-2406` |
| 常量折叠？ | 只有「单操作数退化」：整行只有一个字面量时退化为纯文本；**无算术折叠、无死代码消除**（只 `#Warn` 报警） | `script.cpp:9270-9295`、`script.cpp:7647-7678` |
| 每行内存表示 | `new Line` + `ArgStruct[mArgc]`（SimpleHeap）+ 参数文本 + 可选 deref 表 + **仅当 `is_expression` 且未被折叠时**的 postfix 数组 | `script.cpp:5005/5036/5064/5078/9306` |
| 跳转复杂度 | 加载期定址成 `mJumpToLine`，运行期 **O(1)**；动态 `Goto(%var%)` 才 O(n) | `script.cpp:7613-7619`、`script.cpp:9840` |
| `Var` 布局 | union（`mContentsInt64` / `mContentsDouble` / `mObject`）+ 属性位，**数字有 lazy 缓存**（`VAR_ATTRIB_CACHE`），字符串↔数字只解析一次 | `var.h:122-178`、`var.h:351-375` |
| 对象生命周期 | **纯引用计数，无 GC、无环检测** → 循环引用必泄漏 | `script_object.h:16-68` |
| 函数调用开销 | 无对象池；`mInstances == 0` 时直接复用函数的 Var 对象（零分配），递归/被中断才 `BackupFunctionVars`；**闭包走 `new Var[]`，每次调用真分配** | `script_expression.cpp:1668-1680`、`script.h:1417-1421` |
| 类型检查 | 基本全在运行期；`LocalSameAsGlobal` 明确只加载期，`VarUnset` 只运行期 | `script.cpp:7266`、`globaldata.cpp:78` |

**对本项目可直接用的两条**：① 闭包比普通函数贵（每次分配 `Var[]`），热路径别滥用闭包；② `Var` 的 lazy 数字缓存意味着「反复把同一个字符串当数字用」不会重复解析，但**改了值要重算**。

### §4.5 热键 / 热字符串注册与派发〔T4, P4〕★

**注册链路**：`BIF_Hotkey`（`script2.cpp:2437`）→ `Hotkey::Dynamic`（`:2469`）→ `AddHotkey`（`hotkey.cpp:1259`）→ `new Hotkey`（`:1282`）→ `AddVariant`（`:1523`，`v.mInputLevel = g_InputLevel`）→ `ManifestAllHotkeysHotstringsHooks()`（`hotkey.cpp:202`）→ `ChangeHookState`（`:470`）→ `SetWindowsHookEx(WH_KEYBOARD_LL)`（`hook.cpp:4064`）。

**hook 是否必须**：默认 `HK_NORMAL` 走 `RegisterHotKey()`（`:441`），失败才降级。`#InputLevel>0`、`~`、`$`、`#UseHook`、左右 Ctrl/Alt/Shift、key-up 配对等会强制 hook（`hotkey.cpp:1224-1229/1424/1454/1468/1547/1557`）。

**派发**：hook 线程收键 → `PostMessage(g_hWnd, AHK_HOOK_HOTKEY, id, MAKELONG(sc, input_level))`（`hook.cpp:2056-2067`、`hook.h:28`）→ 主线程 `MsgSleep` 里 `case AHK_HOOK_HOTKEY`（`application.cpp:614`）→ `InitNewThread`（`:986`）。**回调始终在主线程**（`application.cpp:1490-1491` 注释自证）。

**实测（P4）：**

1. **端到端时延**：p50 **0.859 ms**、p95 1.302 ms、max 1.382 ms（n=30）。→ 热键链路**不是**时延瓶颈。
2. **SendLevel × InputLevel 判定矩阵**（`YES` = 被自身 `Send` 触发）：

   | SendLevel | IL0 (F13) | IL1 (F15) | IL11 (F14) |
   |---|---|---|---|
   | 0 / 1 / 2 / 5 / 10 / 11 / 12 / 15 / 20 / 50 / 100 | **全部 YES** | 全部 no | 全部 no |

3. **裸 `SendInput`（`dwExtraInfo = 0`，等价于 Rust 侧调用）**：

   | 按键 | IL0 | IL1 | IL11 |
   |---|---|---|---|
   | F13 | **YES** | no | no |
   | F15 | no | **YES** | no |
   | F14 | no | no | **YES** |

**解读（含推断，已标注）**：

- 判定入口是 `hotkey.cpp:621` `HotInputLevelAllowsFiring()`：`InputLevelFromInfo(事件) > 热键的 InputLevel` 才触发；而 `hotkey.h:75-80` 对**非 AHK 发出的事件**返回 `SendLevelMax + 1 = 101`（`defines.h:850`）。
- 因此**裸 SendInput 的 101 大于任何 InputLevel** → 三档全中（实测吻合）。
- 【推断，未从源码逐行证实】IL0 热键走 `RegisterHotKey` 路径，`WM_HOTKEY` **不携带 `dwExtraInfo`**，所以 AHK 自己的 `Send` 也一律被判成 101 → 无论 `SendLevel` 多少都会触发；而 IL>0 走 hook 路径，能看到 `KEY_IGNORE_LEVEL(SendLevel)` 标记，AHK 自发的键被过滤掉。这解释了矩阵里 IL0 全 YES、IL1/IL11 全 no。
- **对本项目的直接结论**：`SendLevel(10)`（`executor.ahk:15`）+ `InputLevel(11)`（`hotkey_hook.ahk:54`）能挡住 **AHK 自己的** Send，但**挡不住 Rust 的 `SendInput`**——它不写 `dwExtraInfo`，永远被当成物理键。这就是「Rust 侧执行下沉不可行」的根因，且**无法通过调参绕过**。

**热字符串**：本项目 **0 处使用**，只做定位——它靠键盘 hook 逐字符累积环形缓冲（`hook.cpp:2440`）匹配，命中后 `PostMessage(AHK_HOTSTRING)`（`hook.cpp:2069`）。**注意**：只要有任一 enabled hotstring，键盘 hook 会被**强制安装**（`hotkey.cpp:462`），这是隐藏的全局性能代价。

### §4.6 消息循环与伪线程可中断性〔T3, T5〕

| 机制 | 结论 | 源码锚点 |
|---|---|---|
| 等待原语 | 是 `GetMessage()` 阻塞（由 `WM_TIMER` 唤醒），**没有** `MsgWaitForMultipleObjects`（全树仅注释提及）；空闲退避 `Sleep(5)`/`Sleep(0)`，**无自旋** | `application.cpp:227-243`、`:369`、`:429` |
| 可中断判定 | `MSG_FILTER_MAX = IsInterruptible() ? 0 : WM_HOTKEY-1`（`application.h:52-53`）；0/0 表示不过滤，`WM_HOTKEY-1` 表示滤掉热键消息 | `application.h:52-53` |
| 不可中断来源 | ① 新线程前 **17 ms**（`script.cpp:326` `mUninterruptibleTime(17)`）② `Critical` ③ `UninterruptibleDuration == -1` | `application.cpp:1951-2010` |
| 抽消息频率 | `PeekFrequency` 默认 **5 ms**，`Critical` 时提到 16 ms；由 `LONG_OPERATION_UPDATE` 在 `ExecUntil` 每轮顶部触发 | `defines.h:1004-1005`、`script.cpp:9623` |
| 嵌套泵 | `g_DeferMessagesForUnderlyingPump` 在 MsgBox/InputBox/FileSelect/TreeView-ListView 聚焦时置位，放弃 `GetMessage` 改双区间 `PeekMessage` + `Sleep(5)` 退避 | `application.cpp:38-52`、`:249-263` |
| 主定时器生命周期 | `g_nLayersNeedingTimer` 每层 `++`，降到 0 且无脚本定时器才 `KILL_MAIN_TIMER` → 嵌套越深越难被 kill | `application.cpp:178-182`、`:402-413` |

**实践含义**：热键延迟下限 ≈ 17 ms；`Critical` 期间完全不可抢占；脚本循环里每 ~5 ms 会被抽一次消息，所以**纯脚本层死循环不会冻结热键**（但卡在原生 C++ / `DllCall` 里会，此时 `PostMessage` 会在队列堆积）。

### §4.7 内存与对象生命周期〔T6, P5〕

**SimpleHeap = 32 KB 定长块的 bump 分配器，只增不还**（`SimpleHeap.h:35-38`、`SimpleHeap.cpp:77-101`）；`Delete()` 只能回收「最后一次分配」那一个（`SimpleHeap.cpp:114-125`），析构函数**从不被调用**（`SimpleHeap.cpp:173-179`）。走它的对象包括 `Hotkey`/`HotkeyVariant`、行参数数组、postfix 数组、变量名、`Var` 内容 ≤64 B、源码行文本等。

**实测（P5，`PrivateUsage` 增量）：**

| 场景 | Δ私有内存 | Δ句柄 | 耗时 |
|---|---|---|---|
| Map 10 万次增删 | +36 KB | 0 | 20.6 ms |
| Array 10 万次 push/pop | 0 KB | 0 | 16.8 ms |
| **热键 1080 次注册** | **+452 KB**（≈430 B/个，永不回收） | +4 | 29.2 ms |
| 5 万个 **无环** Map | +64 KB（基本回收） | 0 | 47.7 ms |
| **5 万个带环 Map** | **+23 416 KB（22.9 MB，100% 泄漏）** | 0 | 63.5 ms |
| `StrPut/StrGet` 20 万次 | 0 KB | 0 | 67.1 ms |
| 字符串拼接 20 万次 | 0 KB | 0 | 24.6 ms |

→ **引用计数对无环结构工作良好；循环引用一条不回收。** 另注：`Var` 容量 ≤64 B 时走 SimpleHeap，每次扩容都新分配一块、旧块永不回收（`var.cpp:631-637`），超过 64 B 才升级为 `ALLOC_MALLOC` 并**永久锁定**在该模式，此后才是标准 amortized 扩容（`var.cpp:646-661`）。

### §4.8 鲁棒性：Unicode / 长路径 / UAC〔P6, P7, P10〕

**长路径（P6）—— 风险排除**：

| 路径长度 | DirCreate | FileAppend | FileExist | FileRead | FileGetSize | FileDelete |
|---|---|---|---|---|---|---|
| 253 | ok | ok | ok | 5 chars | 5 | ok |
| 290（> MAX_PATH） | ok | ok | ok | 5 chars | 5 | ok |
| 1 030 | ok | ok | ok | ok | ok | ok |
| 5 026 | ok | ok | ok | ok | ok | ok |
| **30 038** | ok | ok | ok | ok | ok | ok |

→ AHK v2.0.26 的文件 API **内部已处理长路径**，无需 `\\?\` 前缀（加了也正常）。唯一未做的是「删除 3 万字符路径可能失败」（已知现象，探针已记录）。

**Unicode（P7）**：AHK v2 内部 UTF-16。文件往返（UTF-8 / UTF-16）对 **BMP 中文、日文、emoji 代理对、组合字符、RTL、控制字符、嵌入 NUL、66 000 code unit 超长串** **全部 ok**；`StrPut→StrGet` 往返在 `UTF-8` / `UTF-16` 下全部 ok。

⚠️ **CP936（GBK）会静默丢字符**：emoji / 组合字符 / RTL / `U+FFFF` 全部 `DIFF`，且**长度不变**（未映射字符被替换成 `?`）。这是最难排查的一类 bug——**长度校验发现不了**。

⚠️ 本版本 `StrPut(s, 65001)` 这种**数字码页**会报 `Parameter #2 of StrPut is invalid.`，必须写 `"UTF-8"` / `"CP936"` 字符串。

**UAC / 权限（P10，纯只读）**：完整性级别 **8192 (0x2000) Medium（默认）**、`elevated=no`、`A_IsAdmin=0`；在此 IL 下**普通热键与 hook 强制型热键（`$` 前缀）均注册成功** → 本项目默认场景无需提权。未做写入实测（避免副作用）。

### §4.9 异常与错误处理链路〔T3, P9〕

| 项 | 结论 | 证据 |
|---|---|---|
| `OnError` 返回 **-1** | 忽略错误并**继续执行**（`reached_after=YES`） | P9 |
| `OnError` 返回 **1** | **退出当前线程**（错误行之后的代码不执行） | P9（必须在独立伪线程里测，否则整个 Main 被退掉） |
| `OnError` 返回 0 | 走默认处理 → 弹**模态错误框**；无人值守会挂死。**本探针未做实弹测试** | 源码 `error.cpp:1087-1118` |
| 回调内再抛 | `sOnErrorRunning` 是**非嵌套布尔闸门**，会跳过本层剩余 OnError 回调直接显示默认错误框 → 多层 OnError **无法形成责任链** | 源码 `error.cpp:1087-1102`；未实弹测试（会弹框） |
| 栈展开机制 | **无 C++ 异常**，靠 `g.ThrownToken` + 每层 `ExecUntil` 返回 `FAIL`；`finally` 由 `ACT_TRY` 显式递归执行 → **无 RAII**，中途 `return FAIL` 的路径靠调用方手工清理 | `error.cpp:131-133`、`script.cpp:10177-10207` |
| **递归上限** | **1 200 层 OK / 1 500 层触发 `Function recursion limit exceeded.`**，且 **`try/catch` 捕获不到**，直接以 `ExitApp` 模式上报并终止进程 | P9 |
| **`#MaxThreads` 背压** | 30 个并发一次性定时器在默认 `#MaxThreads 10` 下 **30 个全部启动并完成**，未观察到丢弃 | P9 |
| `A_LineFile` vs `A_ScriptFullPath` | 未编译时两者相同；**编译后不等**——依赖 `A_ScriptFullPath` 的 `OnError` 注册会在编译版失效 | P9 + 项目历史记录 |

> `OnError` 的**多回调陷阱**：AHK v2 支持多个 `OnError` 回调且**全部会被调用**，`OnError(cb, -1)` **移除不掉**。探针 harness 的守卫会抢先 `ExitApp`，因此 P9 用 `ProbeInit(id, false)` 跳过守卫注册。

---

## 五、落地改造清单（L1/L2/L3，含代码级片段）

> 状态一律为**待办**（本次只调研不改代码）。优先级：P0 = 收益/成本比最高，P3 = 可延后。

### L1 —— 脚本层（`asd-tauri/src-tauri/ahk_executor/*.ahk`）

| ID | 问题 | 依据 | 方案（含片段） | 改动文件 | 收益 | 风险 | 优先级 | 验证 |
|---|---|---|---|---|---|---|---|---|
| L1-1 | IPC 固定 50 ms 轮询，空闲也满负荷 | 架构现状 | **空闲退避 + 有数据自适应**：连续 N 次空读把间隔升到 100 ms，读到数据立刻降回 1 ms | `ipc_client.ahk` | 空闲 CPU 显著下降 | 首次响应需保持 ≤1 档 | P1 | P2 手法 |
| L1-2 | 24 处一次性 `SetTimer(fn,-n)`，定时器越多 `CheckScriptTimers` 越慢 | `application.cpp:1551-1573` | 合并为**单 tick 时间轮**：一个 10 ms tick 扫到期桶 | `sender.ahk` | O(启用定时器数)×64Hz 降为 O(1) | 改动面大 | P1 | P3 的 gap 指标 |
| L1-3 | QPC 纯忙等占主线程 | P3（lead28 → 20.5% 占空比） | **不要简单调小 lead**（8/16 会漏 13~17%）。改为**自适应 lead**：统计最近 K 次 `Sleep` 的实际超调量，取 P95 作为 lead，并记录 miss 率自动回退 | `sender.ahk` / `high_res_clock.ahk` | 占空比 20% → 目标 10% | 需长跑标定 | P0 | P3 的 miss_pct 必须为 0 |
| L1-4 | `OnError` 只有 1 处，且依赖 `A_ScriptFullPath` | P9 + `error.cpp:1086` | 各入口补齐；**用 `A_LineFile`/`A_ScriptDir` 之外的方式定位**，或显式判断 `A_IsCompiled`；回调内**不再抛错** | `executor.ahk:33` 等 | 编译版不再丢错误上报 | 回调吞错 | P1 | P9 |
| L1-5 | `SendLevel(10)+InputLevel(11)` 挡不住 Rust 的 `SendInput` | P4 phase4 | **放弃「Rust 侧下沉」路线**；把防自触发的职责放在 Rust 侧（发送前置全局抑制标志 + AHK 侧 `#HotIf` 判该标志） | `executor.ahk` / `hotkey_hook.ahk` | 明确边界，避免死循环 | 需跨端协议 | P0 | P4 phase4 复现用例 |
| L1-6 | 循环引用必泄漏 | P5（+22.9 MB） | 长生命周期对象**禁止互相持有**；确需双向引用时用**弱引用约定**：`parent["childRef"] := child` 改成只存 key，或显式 `BreakCycle()` 在销毁前置空 | 全局约定 | 消除一整类泄漏 | 需 review | P1 | P5 `cycle_ref_50k` 场景 |
| L1-7 | 深递归会直接终止进程且不可捕获 | P9（1200/1500 层） | JSON 解析 / 树遍历**改为显式栈迭代** | `ipc_client.ahk` | 消除崩溃风险 | 改动局部 | P2 | 构造 2000 层嵌套 JSON |
| L1-8 | 热路径滥用闭包（每次调用分配 `Var[]`） | `script.h:1417-1421` | 热路径改用**具名函数**；闭包只用于注册期 | `sender.ahk` | 减少分配 | 低 | P3 | 微基准 |
| L1-9 | `#Include` 592 µs/文件 | P1 | 合并同层小文件；给 `#Include` 数量设上限（如 ≤10）并在 code review 检查 | 项目约定 | 启动 -数 ms | 低 | P2 | P1 |

### L2 —— Rust ↔ AHK 边界层

| ID | 问题 | 依据 | 方案（含片段） | 改动 | 收益 | 风险 | 优先级 | 验证 |
|---|---|---|---|---|---|---|---|---|
| L2-1 | IPC `WriteFile` 同步阻塞 | 架构现状 | Rust 侧写**超时 + 背压 + 64 KB 分帧校验**；`CreateFile` 时设 `FILE_FLAG_OVERLAPPED` 或写线程 + `WaitForSingleObject(h, 500)` | `asd-ipc-protocol` / `src-tauri` | 单侧卡死不再拖死对端 | 需处理半包 | P1 | 注入慢消费者 |
| L2-2 | GUI exe 不等待 → 无法判定存活 | `AutoHotkey64.exe` GUI 子系统 | **Job Object** 包裹子进程 + **心跳**：AHK 侧每 500 ms 写一次心跳文件/管道，Rust 侧超时即判死 | `src-tauri` | 崩溃可检测 | 低 | P1 | kill 子进程观察 |
| L2-3 | 崩溃取证缺失 | P9 | 统一通道：`OnError` 输出 + 退出码 + `.done`/`.crash` 哨兵 → Rust 汇总落盘 | 双侧 | 现场可复现 | 低 | P2 | 故意抛错 |
| L2-4 | 热键批量注册会反复触发 O(n²) `Manifest` | `hotkey.cpp:202/303-319` | **批量化**：先 `Suspend`/关 hook，注册完再一次性 `Manifest`；或把 47 处注册收敛到启动期一次完成 | `hotkey_hook.ahk` | 注册耗时与抖动下降 | 低 | P2 | P4 phase3 |
| L2-5 | 两处 `AutoHotkey64.exe` 版本漂移风险 | P0（当前一致） | **CI 加一条校验**：比对哈希/版本串，不一致即 fail | `.github/workflows` | 防止实测失真 | 低 | P1 | CI |
| L2-6 | 依赖 `#MaxThreads` 做背压无效 | P9（30/30 全跑） | **自己实现背压**：AHK 侧原子计数器 + 超阈值直接丢弃并计数上报 | `sender.ahk` | 行为可预期 | 低 | P1 | P9 场景 |
| L2-7 | 编码边界未锁定 | P7（CP936 静默丢字符） | **协议层强制 UTF-8**：Rust 侧序列化后校验 `std::str::from_utf8`；AHK 侧自研 JSON 解析器只接受 UTF-8，遇到非法序列**报错而非替换** | 双侧 | 消除静默丢字符 | 低 | P1 | P7 用例集 |

### L3 —— 引擎层（**只评估；明确不实施、不 fork、不编译**）

| ID | 问题 | 源码依据 | 引擎侧改法 | 为何不实施 | 优先级 |
|---|---|---|---|---|---|
| L3-1 | `SLEEP_INTERVAL=10` 导致 15.625 ms 网格 | `globaldata.h:218/237-239` | 改用 `timeSetEvent`/`CreateWaitableTimer`，或按 OS 粒度动态设 `SLEEP_INTERVAL` | 需自行编译分发引擎，违背「用官方发行版」 | P3 |
| L3-2 | `CheckScriptTimers()` 线性扫链 + 每定时器一次 `GetTickCount()` | `application.cpp:1551-1573`、`:1562` | 换成**最小堆 / 时间轮**，按到期时间排序 | 同上 | P3 |
| L3-3 | SimpleHeap 只增不还 | `SimpleHeap.cpp:114-125/173-179` | 给热键/变体加 free-list 或引用计数 | 同上；且本项目热键增删不频繁 | P3 |
| L3-4 | `MsgSleep` 用 `GetTickCount()`（15/16 ms 步进） | `application.cpp:127-128`（注释自认 QPC 开销高） | 关键路径换 QPC；`GetTickCount` 只用于粗判 | 同上 | P3 |
| L3-5 | 无环检测器 → 循环引用必泄漏 | `script_object.h:16-68` | 引入 trial-delete / 弱引用集合 | 同上；已在 L1-6 用约定规避 | P3 |
| L3-6 | 递归上限 ~1200–1500 且不可捕获 | P9 | 改为可捕获异常或提高上限 | 同上；已在 L1-7 用迭代规避 | P3 |
| L3-7 | 无 RAII，`return FAIL` 路径靠手工清理 | `error.cpp:131-133` | 引入作用域守卫 | 同上 | P3 |

---

## 六、风险、边界与未覆盖范围

**已推翻 / 修正的既有认知（重要）**

| 原认知 | 修正后 | 依据 |
|---|---|---|
| 「AHK 启动慢（~164 ms）」 | 引擎自身 ≈19 ms；144.9 ms 是本机制程创建基线 | P1 + `hostname.exe` 对照 |
| 「请求 16 ms 反而得到 ~31 ms」 | 请求 16 的 **p50 = 15.93 ms**；断点在 **21 ms** | P2 |
| 「`timeBeginPeriod(1)` 对 AHK 无效」 | **确认无效**（有配对对照 + 复原确认） | P2 |
| 「QPC 忙等会冻结消息泵」 | **未冻结**：`Sleep(0)` 驱动泵；真实代价是 gap p95 抬到 ~27 ms | P3 |
| 「AHK 受 MAX_PATH 260 限制」 | 30 038 字符正常 | P6 |
| 「`#MaxThreads` 可做背压」 | 30 并发定时器**全部执行** | P9 |

**未覆盖（明确标注）**

1. **热字符串**：本项目 0 处使用，只做了机制定位，未做性能实测。
2. **`OnError` 返回 0 / 回调内再抛**：会弹**模态错误框**导致无人值守挂死，未做实弹测试，结论来自源码 `error.cpp:1087-1118`。
3. **UAC 提权 / VirtualStore 写入行为**：探针设计为只读，未实测写入重定向。
4. **多机差异**：进程创建基线（144.9 ms）明显受本机 Defender 实时扫描影响，**绝对值不可跨机比较**；相对增量可比。
5. **AHK 编译版（`Ahk2Exe`）行为**：P9 只测了解释执行下的 `A_LineFile == A_ScriptFullPath`；编译版差异来自项目历史记录，本次未复现。
6. **P4 判定矩阵中 IL0/IL1/IL11 的差异机理**含【推断】成分（RegisterHotKey 路径 vs hook 路径的 `dwExtraInfo` 可见性），未逐行从源码证实；**实测行为本身是确定的**。

---

## 附：探针清单与原始数据

| 探针 | 文件 | 输出 | 关键结论 |
|---|---|---|---|
| P0 | `p0_version.ahk` | `p0_version.csv` | 二进制一致（SHA256 相同）、版本 2.0.26 |
| P1/P8 | `gen_fixtures.py` + `bench_startup.py` | `p1_startup.csv` | 启动 163.8 ms / 解析 1.33 µs·行 / `#Include` 592 µs·文件 |
| P2 | `p2_timer.ahk` | `p2_timer.csv` | 网格 15.985 ms；`timeBeginPeriod` 零改善；Sleep 断点 21 ms |
| P3 | `p3_occupancy.ahk` | `p3_occupancy.csv` | 自旋期间泵未停；lead<20 漏 13~17%；lead28 占空 20.5% |
| P4 | `p4_hotkey.ahk` | `p4_hotkey.csv` | 时延 p50 0.859 ms；裸 SendInput 三档全中 |
| P5 | `p5_memory.ahk` | `p5_memory.csv` | 循环引用 +22.9 MB；热键注册 +452 KB |
| P6 | `p6_longpath.ahk` | `p6_longpath.csv` | 30 038 字符全绿 |
| P7 | `p7_unicode.ahk` | `p7_unicode.csv` | 文件/UTF-8/UTF-16 全绿；CP936 静默丢字符 |
| P9 | `p9_error.ahk` | `p9_error.csv` | OnError -1/1 语义；递归 1200 OK / 1500 终止；`#MaxThreads` 无效 |
| P10 | `p10_uac.ahk` | `p10_uac.csv` | IL 0x2000 Medium、非提权；热键注册正常 |

**跑法**

```bash
bash tools/ahk-probes/run.sh p2_timer 150      # 单个探针
python tools/ahk-probes/gen_fixtures.py        # 生成 P1/P8 夹具
python tools/ahk-probes/bench_startup.py 9     # P1/P8 外部墙钟基准
```

结果落在 `%TEMP%\ahkprobe\<id>.csv`。详见 `tools/ahk-probes/README.md`。

**AHK v2 探针编写踩坑（已固化进 `_harness.ahk` 注释）**

1. `catch as e` 才是正确语法；`catch e` 被解析成「捕获类 e」→ 加载期 `Invalid class`。
2. **AHK 2.0.26 的 `Array` 没有 `Sort()` 方法**（`This value of type "Array" has no method named "Sort"`），分位数需自写排序。
3. 函数默认 assume-local：**脚本级变量不被箭头函数闭包捕获**；跨函数变量必须显式 `global`。
4. `Hotkey()` / `OnError()` 的回调必须是**函数对象**：裸名字 → `Invalid callback function.`；`Func("名")` 在本版本 → `Invalid base.`；用 `((*) => 0)` 这类闭包才稳。
5. `OnError` 支持**多个**回调且全部执行，`OnError(cb, -1)` 移除不掉。
6. `StrPut(s, 65001)` 数字码页报 `Parameter #2 … invalid`，要用 `"UTF-8"`。
7. `SetTimer` 传**同一个**函数对象多次只会保留最后一个，需 `Fn.Bind(i)` 造不同对象。
8. GUI 子系统未捕获错误会弹模态框挂死 → harness 必须注册 `OnError` 守卫。
