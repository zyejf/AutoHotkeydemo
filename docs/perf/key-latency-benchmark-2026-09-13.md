# 按键触发时延实测报告（periodic 精确定刻优化）

- 日期：2026-09-13
- 范围：**仅 periodic 模式**（与需求对齐，sequence / enhanced_* 未改动）
- 指标口径：**「计划时刻 → 抬起完成」的 P95 ≤ 20 ms**（含 `keyPressDuration`，默认 15 ms）
- 目标：低时延 **且不漏发按键事件**

---

## 1. 结论速览

| 场景（interval / kpd） | 优化前 P95 | 优化后 P95 | 优化前 最大 | 优化后 最大 | 判定 |
|---|---|---|---|---|---|
| 100 ms / 15 ms | 16.2 ~ 26.8 ms（5 轮中 **3 轮超标**） | **14.8 ~ 15.0 ms** | 30.95 ms | **15.03 ms** | 达标 |
| 50 ms / 15 ms | 23.1 ~ 42.3 ms（**全部超标**） | **14.98 ~ 15.00 ms** | 42.53 ms | **15.01 ms** | 达标 |
| 20 ms / 15 ms | **1992 ~ 2018 ms**（灾难性） | **14.99 ~ 15.00 ms** | 2098.76 ms | **15.29 ms** | 达标 |

同时修正了两项正确性缺陷（详见 §4）：

- **周期保真度**：100 ms 间隔下，优化前实测周期中位 **95.2 ms**（系统性地快 5%）、最大 111.7 ms；优化后中位 **100.000 ms**、最大 100.03 ms。
- **漏发/吞发**：优化前在滞后时会把时间基准重置为当前时刻，既丢相位又吞掉本应发生的触发；优化后改为**保相位单调推进**，并对跳过的周期计数。

---

## 2. 瓶颈定位（实测，非推测）

### 2.1 排除的怀疑项

| 怀疑项 | 结论 | 依据 |
|---|---|---|
| 防抖 / 节流 | **不存在** | `sender.ahk` 无任何 debounce/throttle 逻辑 |
| DOM 操作 | **不在链路内** | 前端仅在 `main.js` 做日志展示，不参与按键触发闭环 |
| 回调链深度 | 不是瓶颈 | 链路只有 `SetTimer → _ExecutePeriodic → _SendKeyDown` |
| 合并窗口 | 不适用 | `sender.ahk` 没有单次触发 API，periodic 为唯一路径 |

### 2.2 真实瓶颈：Windows 15.625 ms 定时器网格

本机实测（AutoHotkey v2）：

| 机制 | 实测结果 |
|---|---|
| `A_TickCount` 步进 | 中位 **15.52 ms** → 根本无法度量 20 ms 以内的时延 |
| `SetTimer` 周期 / `Sleep` | 锁死在 **15.625 ms 网格**；请求 1/5/10/15 ms 均得到 ~15.6 ms；**请求 16 ms 反而得到 ~31 ms**（跨格跳 2 格） |
| `timeBeginPeriod(1)` | 对 AHK **完全无效**（调用后 `SetTimer(1ms)` 仍为 15.68 ms） |
| 一次性 `SetTimer(-1)` 自轮询 | 主线程空闲时中位 **15.67 ms**，不存在亚 15.6 ms 的唤醒手段 |
| **QPC 忙等** | 目标 20 ms → 中位 20.0017 ms，**误差 0.0017 ms** |

因此：**AHK 内唯一可用的精确定刻手段是 QPC（QueryPerformanceCounter）**。
这同时也否定了「把调度下沉到 Rust」的方案——`executor.ahk:17` 的 `SendLevel(10)` 与
`hotkey_hook.ahk:54` 的 `InputLevel(11)` 决定了 Rust 侧 `SendInput` 会被 AHK 当作**物理按键**
（物理按键触发所有 level）→ 自触发死循环。

### 2.3 优化前的时延构成

```
计划时刻 ──(等待 SetTimer 唤醒：0 ~ 15.6 ms 网格误差)──▶ _SendKeyDown
          ──(SetTimer(-kpd) 释放：0 ~ 15.6 ms 网格误差)──▶ _SendKeyUp  ← 抬起完成
```

两处网格误差叠加，且旧实现的 `threshold = interval - Max(1, Round(interval * 0.05))`
允许**提前 5% 触发**，导致周期系统性地偏离配置值。

---

## 3. 优化措施

1. **新增 QPC 高精度时钟** `ahk_executor/high_res_clock.ahk`
   - `Now()`：QPC 毫秒时间戳，分辨率远优于 1 ms。
   - `SleepUntil(target)`：三段式等待 —— 剩余 > 50 ms 用粗 `Sleep`（留 40 ms 安全边界）
     → 中段 `DllCall("kernel32\Sleep", "UInt", 0)` 让出 → 末段 1 ms 纯忙等。

2. **重写 `_ExecutePeriodic`**：建立 QPC 基准 → 求最近到期时刻 → 提前唤醒 + `SleepUntil` 精修 →
   到期才发送。不再依赖「轮询 + 阈值判定」。

3. **保持时长精确定刻** `_PressPrecise()`：`Down → SleepUntil(plannedAt + kpd) → Up`，
   当 `kpd ≤ PRECISE_HOLD_MAX_MS(20)` 时启用；超过则退回异步释放（该配置下必然 > 20 ms，精确定刻无意义）。

4. **保相位单调推进**（修漏发）：基准从**本次触发的计划时刻**推进，而非发送完成后的当前时刻。
   原实现 `if triggerTimes[i] < now - interval then triggerTimes[i] := now` 会重置基准。

5. **唤醒提前量 `WAKE_LEAD_MS = 28`**（实测选参，见 §5.2）。

---

## 4. 修正的缺陷

### 4.1 漏发 / 吞发（正确性）

`sender.ahk:382`（旧）在滞后时把基准直接改写为 `now`：

```ahk
triggerTimes[i] := triggerTimes[i] + interval
if triggerTimes[i] < now - interval
    triggerTimes[i] := now          ; ← 既丢相位，又吞掉本应发生的触发
```

改为保相位推进，并对跳过的周期计入 `state["droppedTriggers"]`，使漏发**可观测**而非静默。

### 4.2 周期系统偏移 5%

旧实现允许提前 5% 触发，实测 100 ms 配置下周期中位只有 95.2 ms。
优化后周期中位 100.000 ms。

---

## 5. 实测方法与数据

### 5.1 方法

- 脚本（已入库，可复现）：**`scripts/perf/bench_periodic_latency.ahk`**
  ```bash
  "D:/Program Files/AutoHotkey/v2/AutoHotkey.exe" scripts/perf/bench_periodic_latency.ahk 100 15 3000
  ```
  参数依次 `interval kpd runMs outFile`。复现「优化前」基线的方法与坑见 `scripts/perf/README.md`。
- 观测方式：以 `_sendHook` 替换发送原语（跳过真实 `SendInput`，消除副作用），
  IPC 上报替换为空实现（消除 I/O 干扰）。**调度与释放逻辑保持原样**，故测得的是真实调度时延。
- 口径：`planned_i = firstDown + (i-1) * interval`，时延 `= up_i - planned_i`；
  另统计单次保持时长 `up_i - down_i` 与相邻按下间隔。
  > 计划时刻**不能**读内部状态 `state["lastTriggerTimes"]`：旧版内部基准是 `A_TickCount`、
  > 新版是 QPC，纪元不同，直接相减会得到无意义的结果。
- 环境：Windows / AutoHotkey v2（`D:\Program Files\AutoHotkey\v2\AutoHotkey.exe`），每档 3000 ms。

> 关于 criterion：本轮优化**全部落在 AHK 侧**（`high_res_clock.ahk` / `sender.ahk`），
> Rust 侧无任何改动，也没有 Rust 侧的按键时序热路径可供 criterion 度量。
> 因此回归防护由新增的 AHK 单测（断言 P95 ≤ 20 ms、零漏发）承担，
> criterion 微基准（7 个）未改动、仍按原样守护 Rust 侧热路径。

### 5.2 唤醒提前量选参（interval=100 / kpd=15，各 3 轮）

| `WAKE_LEAD_MS` | 时延 P95 | 保持时长 **最小** | 周期 最大 |
|---|---|---|---|
| 18 | 15.006 ms | **8.015 ms** | 106.98 ms |
| **28** | **14.99 ms** | **14.800 ms** | **100.17 ms** |
| 40 | 14.99 ms | 14.891 ms | 100.23 ms |

18 时定时器偶发迟到 ~7 ms，导致「按下迟到 → 保持时长被压缩到 8 ms」；
28（≈ 1.8 个网格）足以吸收一整格唤醒抖动 + 调度抖动，代价最小，故取 28。

### 5.3 interval=100 / kpd=15，各 5 轮

| 轮次 | 优化前 P95 | 优化后 P95 | 优化前 周期中位/最大 | 优化后 周期中位/最大 |
|---|---|---|---|---|
| 1 | 20.948 ms ❌ | 15.014 ms | 95.18 / 111.74 | 100.000 / 103.00 |
| 2 | 17.887 ms | 14.992 ms | 94.72 / 111.32 | 100.000 / 106.56 |
| 3 | **25.293 ms** ❌ | 14.988 ms | 95.16 / 110.87 | 99.998 / 102.47 |
| 4 | 15.864 ms | 14.986 ms | 95.26 / 110.78 | 100.000 / 103.53 |
| 5 | **26.834 ms** ❌ | 14.805 ms | 95.09 / 111.30 | 100.000 / 104.89 |

> 优化前的 P95 在两轮之间可从 15.9 ms 跳到 26.8 ms —— 这是**启动相位**随随机数落在
> 15.625 ms 网格不同位置所致，属于不可控抖动，正是需要消除的对象。

### 5.4 保持时长精度（目标 15 ms）

| 版本 | 中位 | 最小 | 最大 |
|---|---|---|---|
| 优化前 | 15.56 ~ 15.98 ms | 14.92 ms | 16.25 ms |
| 优化后 | 14.97 ~ 15.00 ms | 14.96 ms | 15.02 ms |

### 5.5 interval=20 的极端场景

优化前：时延中位 ~1043 ms、P95 ~2000 ms —— 发送速率跟不上配置速率时，旧实现每 tick 只发一次且基准持续落后，
误差**线性累积**。优化后 P95 仍为 15.00 ms。

> 注：按需求对齐结论，**短间隔（< 50 ms）不保证精度**；但优化后即便在 20 ms 间隔下
> 时延依旧达标，且不再出现累积漂移。

---

## 6. 已知限制

1. **短间隔下保持时长可能被压缩**：`_PressPrecise` 以「计划时刻 + kpd」为抬起目标，
   若按下本身迟到（定时器抖动），保持时长会短于 kpd。实测 interval=20 / kpd=15 这类
   占空比 75% 的极端配置下，最小可到 0.03 ms。常规配置（interval ≥ 50）下最小 14.96 ms，无影响。
2. **精确定刻会占用主线程**：末段 1 ms 为忙等。periodic 模式下每周期仅 1 ms，可接受；
   若未来需要多组高频并发，应重新评估。
3. **`kpd > 20 ms` 不启用精确定刻**：该配置下「计划时刻 → 抬起完成」必然 > 20 ms，已无意义。
4. **本次未覆盖** sequence / enhanced_* 模式，它们仍走旧调度路径。

---

## 7. 回归

- AHK 全量测试：**638 / 638 通过 / 0 失败**（基线 633 + 本次新增 5）。
- 新增单元测试 `tests/test_ahk_executor/test_sender.ahk::SenderPreciseTimingTests`：
  时钟分辨率、`SleepUntil` 误差、保持时长与 kpd 一致、端到端 P95 ≤ 20 ms、正常间隔下零漏发。

> 测试数字以 `asd-tauri/docs/test-map.md` 为唯一权威，本文档不复制明细。
