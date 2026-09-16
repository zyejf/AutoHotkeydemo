# AHK 定时器硬事实（实测，勿再凭直觉）

**没有亚 15.625ms 的唤醒手段**（AHK v2，本机）：

| 机制 | 实测 |
|------|------|
| `A_TickCount` 步进 | 中位 **15.52ms** → 测不了 20ms 内时延 |
| `SetTimer`/`Sleep` | 锁死 **15.625ms 网格**；请求 1/5/10/15/16/20 均 ~15.9；**断点在 21ms** |
| `timeBeginPeriod(1)` | 对 AHK **完全无效**（配对对照 + 复原确认） |
| 一次性 `SetTimer(-1)` | 空闲时中位 **15.67ms** |
| **QPC 忙等** | 误差 **0.0017ms** —— 唯一精确手段 |

## 精确定刻规范（AGENTS.md §高精度定刻规范）

① <50ms 精度一律 `HighResClock`，禁 `A_TickCount`；② 到点用 `SleepUntil`，禁 `Sleep` 收尾；
③ 提前唤醒 ≥1 网格+抖动（`WAKE_LEAD_MS=28`；18 会把保持压到 8ms）；
④ 推进基准用**本次计划时刻**；⑤ 滞后**禁止**重置基准为当前时刻（→ 保相位 + `droppedTriggers`）；
⑥ 同刻多键**必须分桶批量** Down→等→Up（串行让第二个键保持塌到 0.02ms）；
⑦ 序列首步基准在**首次执行**时确立（`nextStepTime := 0` 哨兵）；
⑧ 调度时刻一律整数 µs，`Round()` 不可省；⑨ 遍历只能 4→2（开关两侧须同步改）；
⑩ **没有 `SleepUntilUs` 兜底的路径，定时器周期必须 `Ceil` 不能 `Round`** ——
   Round 早醒 ≤0.5ms → 无键到期 → 再排 <1ms 定时器 → 被 `Max(1,…)` 抬成网格白吃一格
   （joystick 序列 3 秒漂移 +15.1~17.2ms → Ceil 后 +1.9~10.7ms）。
   ⚠️ 同理：**`TIMING_EPSILON_US` 在「提前返回处不带容差」的结构下是死代码**（joystick 已删）。

## 代价与误解

⚠️ **代价：连续占用 AHK 主线程**。interval=100/kpd=15：扣除网格后最长连续占用 31.4ms、占空比 29.2%。
⚠️ **「忙等=冻结一切」是误解**：`SleepUntil` 里的 `Sleep(0)` 在 AHK 中是 `ScriptSleep(0)`→`MsgSleep(0)`
→`PeekMessage`，**每次迭代都驱动消息泵**（自旋 100ms 期间探针定时器仍触发 7 次）。
真实代价是探针 gap p95 从 16.6 抬到 ~27ms。`WAKE_LEAD_MS=28` 合理保守：lead 8/16 有 13~17% 睡过头。

实测「计划时刻→抬起完成」P95：periodic 旧 16~27 → 新 **15.0ms**；interval=20 旧 ~2000 → 新 15.0ms；
sequence 旧 248~263 → 新 14.97ms。报告 `docs/perf/key-latency-benchmark-2026-09-13.md`。

**Rust 侧下沉不可行**：`SendLevel(10)`+`InputLevel(11)` 让 Rust `SendInput` 被 AHK 当物理键 → 自触发死循环。

⚠️ **四种调度模式实为两套内核**：`enhanced_periodic`/`enhanced_sequence` = `StartPeriodic`/`StartSequence`
+ 改写 `state["mode"]` 标签，差异只在配置字段名（`executor.ahk:303-310`）。`state["mode"]` **只写不读**。
⚠️ **分桶键是浮点 dueAt**（`HighResClock.Now()` 返回 ms **浮点**）→ 同刻两键末位不同会被拆成两个桶。
修法：时刻改用**整数**（µs 或 QPC 计数）。
