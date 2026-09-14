# AHK 探针集（`tools/ahk-probes/`）

为《AHK v2 引擎架构分析报告》提供**可复现的实测佐证**。
配套报告：`docs/research/ahk-engine-architecture-2026-09-14.md`。

- 引擎：`AutoHotkey v2.0.26`（源码 vendored 在 `AutoHotkey-2.0.26/source`，**只读**）
- 全部输出落在 `%TEMP%\ahkprobe\`，**不污染仓库、不碰生产目录**
- 这些脚本是**调研工具**，不属于生产代码，也不参与 DoD 四闸门中的测试统计

---

## 1. 跑法

```bash
# 单个探针（结果写 %TEMP%\ahkprobe\<id>.csv，并打印到 stdout）
bash tools/ahk-probes/run.sh p2_timer 150

# P1/P8 的外部墙钟基准（需要 Python）
python tools/ahk-probes/gen_fixtures.py        # 先生成夹具
python tools/ahk-probes/bench_startup.py 9     # 9 = 每场景重复次数
```

`run.sh` 的第二个参数是**哨兵等待超时（秒）**，默认 300。
P2/P3/P4 都是几十秒级，观察类探针（P0/P5/P6/P7/P10）不到 1 秒。

可用环境变量 `AHK` / `AHK_BIN` 覆盖解释器路径，默认
`D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`。

---

## 2. 探针清单

| ID | 文件 | 测什么 | 耗时 |
|---|---|---|---|
| P0 | `p0_version.ahk` | 环境指纹 + 两处 exe 大小比对 | <1 s |
| P1/P8 | `gen_fixtures.py` + `bench_startup.py` | 启动/解析耗时、`#Include` 边际成本 | ~30 s |
| P2 | `p2_timer.ahk` | 15.625 ms 网格根因 + `timeBeginPeriod(1)` 对照 | ~25 s |
| P3 | `p3_occupancy.ahk` | QPC 定刻对主线程的占用 / lead trade-off | ~20 s |
| P4 | `p4_hotkey.ahk` | 热键时延、SendLevel×InputLevel 矩阵、裸 SendInput | ~50 s |
| P5 | `p5_memory.ahk` | 私有内存 / 句柄 / 循环引用泄漏 | <1 s |
| P6 | `p6_longpath.ahk` | 长路径 260 / 1k / 5k / 30k | ~10 s |
| P7 | `p7_unicode.ahk` | Unicode 往返（emoji / 组合 / 66k / 多码页） | <1 s |
| P9 | `p9_error.ahk` | OnError 语义、递归上限、`#MaxThreads` | ~5 s（末尾会因递归测试终止） |
| P10 | `p10_uac.ahk` | 完整性级别 / 提权状态 / 热键可用性（**只读**） | <1 s |
| — | `_harness.ahk` | 公共框架（输出、统计、QPC、OnError 守卫） | — |
| — | `_dbg_*.ahk` | 排查用最小复现脚本 | — |

---

## 3. 为什么需要 harness（两个 Windows 坑）

1. **`AutoHotkey64.exe` 是 GUI 子系统程序**——`cmd` 的 `start`、PowerShell 的 `&`
   启动它**不会等待**；从 Git Bash 直接调用**会**等待（CreateProcess + 等待句柄）。
   所以 `run.sh` 直接调用 exe，不需要 `start /wait`（且 Bash 里调 `cmd` 会被安全策略拦截）。
2. **未捕获错误会弹模态错误框并永久挂起**——无人值守跑批时是灾难。
   `ProbeInit()` 会注册 `OnError` 守卫，把错误写进 CSV 后 `ExitApp`。

因此约定：**结果只写文件**（`%TEMP%\ahkprobe\<id>.csv` + `<id>.done` 哨兵），
**不依赖 stdout、不依赖退出码**。

---

## 4. AHK v2 踩坑清单（改这些脚本前必读）

| # | 坑 | 正确写法 |
|---|---|---|
| 1 | `catch e` 报 `Invalid class` | `catch as e`（`e` 会被解析成类名） |
| 2 | `arr.Sort()` 报 `no method named "Sort"` | **2.0.26 的 Array 没有 Sort**，用 `_harness.ahk` 的 `_SortNums()` |
| 3 | 脚本级变量不被箭头函数闭包捕获 | 主体包 `Main()`；跨函数变量显式 `global` |
| 4 | `Hotkey(name, Cb)` 报 `Invalid callback function.` | 传**函数对象**：`((*) => 0)`（`Func("Cb")` 在本版本报 `Invalid base.`） |
| 5 | `OnError` 注册第二个后两个都执行，且 `-1` 移除不掉 | 需要独占时用 `ProbeInit(id, false)` 跳过守卫注册 |
| 6 | `StrPut(s, 65001)` 报 `Parameter #2 … invalid` | 用字符串：`"UTF-8"` / `"CP936"` |
| 7 | 循环里 `SetTimer(同一个Fn, -n)` 只保留最后一个 | `Fn.Bind(i)` 造不同对象 |
| 8 | `A_TickCount` 步进就是 15/16 ms | 任何 <20 ms 的度量都用 `HighResNow()`（QPC） |
| 9 | 变量名 `log` 与内置 `Log()` 冲突 | 换名 |
| 10 | `while i<=n { ... }` 单行块体非法 | 多行展开 |

---

## 5. 统计口径

- 一律用 **QPC**（`HighResNow()`），不用 `A_TickCount`。
- `_Pct(arr, 0.95)` 的索引是 `Ceil(n*0.95)`：**n 太小（如 7）时断言的其实是最大值**。
  算 P95 至少要 **40 个样本**；判断「是否系统性漂移」用**中位数**。
- 绝对耗时（尤其是进程启动）受本机 Defender 实时扫描影响很大——
  **绝对值不可跨机比较，相对增量可比**。做对照前先按报告 §2.3 标定进程创建基线。
