# 发送时刻序列生成 · 算法设计与工程标准

> **本文是设计文档，不是改造方案。**
> 全部结论来自 `tools/ahk-bench/` 的可复现原型（`lib/seqgen.ahk` + `lib/seqgen_legacy.ahk`）。
> 实测数字见 [`scheduling-bench-2026-09-14.md`](./scheduling-bench-2026-09-14.md)。
>
> **落地状态（2026-09-14 更新）**：
> 1. 「时刻表示 float ms → int µs」**已落地**（新增 `NowUs()` / `SleepUntilUs()`，调度时刻与
>    分桶键全部改为整数 µs，配置在 `Sender._IntervalUsOf` / `_DelayUsOf` 入口处 `Round()` 一次）。
>    因此下文 §现状 中「生产用浮点毫秒」的描述已不再成立，仅作为改造前的记录保留。
> 2. 「每轮 3 次 `_IntervalOf` 收敛为 1 次」**已落地为 T6**，由 `Sender.MERGE_TICK_SCAN`
>    开关控制（2026-09-15 起**默认开启**；置回 `false` 即回退到 `*Legacy` 旧实现，
>    两条路径同时保留），实现为 `_ExecutePeriodicMerged` / `_ExecuteHybridMerged`。
>
> ⚠️ **但生产可达的形态是 4→2 次遍历，不是本文原型测到的 4→1 次**：
> 真实 `_ExecutePeriodic` 的「求 target」与「收集到期」之间隔着一次 `SleepUntilUs(target)`，
> 前者用推进前的 `triggerTimes`、后者用推进后的，物理上无法合成一次。
> 因此本文 / `plan-B-balanced.md` 里 T6 的 **1.80~1.96×** 是**原型上限，生产拿不到**；
> 生产形态的实测见 `tools/ahk-bench/bench_tick_traversal.ahk` 的 `TickProd2`（三轮）：
> K=8 23.8→15.2 µs（1.55×）、K=24 74.9→43.5 µs（1.67×），仍满足 M8 ≤20 / M9 ≤50 的验收线。

---

## 0. 摘要（结论先行）

| 结论 | 依据 |
|---|---|
| **四种模式实为两套内核**。`enhanced_periodic`/`enhanced_sequence` 只是把 `state["mode"]` 改成 `"enhanced_*"` 的标签，调度语义与 `periodic`/`sequence` 完全一致 | `sender.ahk:277-288`；`state["mode"]` 全项目**只写不读** |
| **enhanced 的唯一真实差异是配置字段名**（`pressKeys`/`pressDelays` vs `keys`/`delays`） | `executor.ahk:303-310` |
| 现网**没有**「序列生成」这一步，是**增量式调度**（每 tick 现算） | `sender.ahk:442-532` / `:542-597` |
| 浮点 ms 当分桶键会让「数学同刻」被拆桶：实测 **100 次应合并机会里 94 次被拆开** | 本文 §6.2 / 基准 E 阶段 |
| 改成整数微秒后 **0 次拆桶**，同时吞吐提升 **1.56~1.61×** | 基准 A 阶段（三轮） |
| 第一版原型反而**慢 1.45×**，靠三处针对性优化反转为**快 1.6×** | §7 优化轨迹 |

**一句话建议**：把「时刻表示」从 float ms 换成 int µs、把「分桶」从浮点相等换成整数相等、把「每轮 3 次 `_IntervalOf`」收敛成 1 次——这三点就能拿到几乎全部收益，且**不需要动定时器主循环**。

---

## 1. 需求对齐与术语映射

原始需求里有三个术语建立在 JVM/多线程假设上，而 AHK v2 是**单线程协作式**解释器。逐条映射如下（映射后的标准才是本项目的真实约束）：

| 原始要求 | AHK 侧的真实含义 | 本文如何满足 |
|---|---|---|
| 线程安全（并发无竞态） | **重入安全 + 状态机不变量**。AHK 无线程，但定时器回调可在 `Sleep` 等让出点被重入 | §5.3：策略对象无全局可变状态；`Collect` 只在「读 state → 写 state」之间不调用任何可让出原语 |
| JVM/运行时版本 | AHK v2.0.26（64 位）+ Windows + CPU 型号 + **QPC 频率** | 基准报告 §环境 |
| 100K 任务量 | **分层**：纯生成到 100K（无 I/O），端到端到 1K（真实时钟 + 墙钟等待） | 基准 L1 / L3 |
| 模块化（策略可替换） | 同一组方法契约的多实现，由 `EventWindow` 统一驱动 | §3 策略接口 |
| 确定性时序 | 相同输入（含相同唤醒序列）产生逐位相同的输出 | §5.2 + 单测 `Test_Determinism` |

---

## 2. 现状：两套内核，不是一个四路分支

### 2.1 enhanced 是配置别名（源码证据）

```ahk
; sender.ahk:277-282
static StartEnhancedPeriodic(groupId, keys, intervals, keyPressDuration := 15) {
    Sender.StartPeriodic(groupId, keys, intervals, keyPressDuration)
    if Sender._activeGroups.Has(groupId)
        Sender._activeGroups[groupId]["mode"] := "enhanced_periodic"   ; ← 唯一的差异
}
```

`state["mode"]` 在 `_ExecutePeriodic` / `_ExecuteSequence` 里**从未被读取**，所以：

- `enhanced_periodic` ≡ `periodic`（同一 `_ExecutePeriodic`）
- `enhanced_sequence` ≡ `sequence`（同一 `_ExecuteSequence`）
- 真正的差别在配置解析侧：`executor.ahk:303-310` 对 enhanced 用 `pressKeys`/`pressDelays` 字段名，对基础版用 `keys`/`delays`

**后果**：把 enhanced 当成「第四种调度算法」去优化是找错了对象。正确做法是把它显式声明为别名（`SeqModeOf`），并把差异限制在配置适配层。

### 2.2 现在是增量式调度，不是序列生成

`_ExecutePeriodic`（`sender.ahk:442-532`）每 tick 做的事：

1. 第 1 次遍历：基准缺失时填 `now`（:455-460）
2. 第 2 次遍历：求 `target = min(triggerTimes[i] + interval_i)`（:462）
3. 第 3 次遍历：算 `dueAt`、按 **浮点 `dueAt`** 建 `Map` 分桶、保相位推进（:481-506）
4. 逐桶发送：同刻批量 Down → 等 → Up（`_PressPreciseBatch`，:418-421）
5. 第 4 次遍历：算下次唤醒（:523）

其中 `_IntervalOf` 在同一轮里被调用 **3 次**（:462 / :483 / :522）。

---

## 3. 领域模型与数据结构

### 3.1 时刻表示（最关键的一个决定）

| | 生产现状 | 本设计 |
|---|---|---|
| 类型 | `Double`（ms，`c/freq*1000`） | **Int64（µs）** |
| 分桶键 | 浮点 `dueAt` | 整数 `dueUs` |
| 同刻判定 | `Map` 的浮点精确相等 | 整数相等 |
| 溢出 | 无保护 | 饱和到 `0x7FFFFFFFFFFFFFFF` |

选 µs 而非 ns：`ns` 下 `c*1e9` 在 `c≈1e10` 时约 `1e19`，逼近 Int64 上限 `9.22e18`；µs 下约 `1e16`，留 3 个数量级余量。

### 3.2 核心数据结构

```
Clock            :: { NowUs() -> Int64 }              ; 可注入时间源
MonotonicGuard   :: Clock × { last, backsteps, clampedUs }
                    NowUs(): t ← inner.NowUs()
                             if t < last: backsteps++, clampedUs += last-t, return last
                             last ← t; return t

PeriodicState    :: { bases: Array<Int64>   ; 每键「上一次的计划时刻」
                    , iv:    Array<Int64>   ; 每键**已夹紧**的间隔（Init 时算一次）
                    , intervalsUs           ; 原始入参，仅供诊断
                    , dropped, emitted, truncated: Int64 }

SequenceState    :: { step: Int   ; 当前步（1-based）
                    , nextUs: Int64
                    , dv: Array<Int64>      ; 已夹紧的延时
                    , keyCount, dropped, emitted, truncated }

Event            :: ( dueUs: Int64, keyIdx: Int )     ; SoA 布局：两个平行数组
Window           :: { dueUs: Array<Int64>, keyIdx: Array<Int>, ticks: Int, guard }
```

**为什么用 SoA（两个平行数组）而不是 AoS（对象数组）**：AHK 里每个对象都是一次分配 + 引用计数。实测「每 tick 分配 2 个数组 + 1 个对象」是原型第一版比旧实现慢的第二大来源，改成调用方传入输出数组后消失。

---

## 4. 算法

### 4.1 统一策略契约

```
interface SchedulePolicy:
    Init(...)            -> state                          ; 纯构造
    NextDueUs(state)     -> Int64                          ; 最早的计划时刻；无则 NO_DUE
    CollectInto(state, nowUs, eps, maxCatchup, outDue, outKey) -> Int
                                                            ; 写入调用方数组，返回新增个数
    Collect(state, nowUs, eps, maxCatchup) -> Window        ; 便捷包装（多 3 次分配）
```

`CollectInto` 是主契约，`Collect` 只是它的包装——这样 `EventWindow` 每 tick 零分配，而外部调用方仍能用一行拿到结果。

### 4.2 PeriodicPolicy

```
CONST MIN_INTERVAL_US = 10_000        # sender.ahk:48  MIN_INTERVAL_MS=10
      MAX_INTERVAL_US = 24*3600*1e6   # 防 base+interval 溢出
      EPSILON_US      = 500           # sender.ahk:60  TIMING_EPSILON_MS=0.5
      NO_DUE          = 0x7FFF_FFFF_FFFF_FFFF
      MAX_CATCHUP     = 256           # 生产无此限制（sender.ahk:501 可跳任意多步）

Init(keyCount, intervalsUs, originUs):
    bases ← [originUs] * keyCount
    iv[i] ← clamp(intervalsUs[i] ?? 50_000, MIN_INTERVAL_US, MAX_INTERVAL_US)   # 只算一次
    return {bases, iv, dropped←0, emitted←0, truncated←0}

NextDueUs(st):
    if st.bases is empty: return NO_DUE                     # 空序列：立即返回，不空转
    best ← NO_DUE
    for i in 1..n:
        d ← satAdd(bases[i], iv[i])
        best ← min(best, d)
    return best

CollectInto(st, nowUs, eps, maxCatchup, outDue, outKey):
    lo ← outDue.length + 1                                  # 只排序本轮新增的尾部
    for i in 1..n:
        dueAt ← satAdd(bases[i], iv[i])
        if nowUs < dueAt - eps: continue                    # 未到期
        outDue.push(dueAt); outKey.push(i)

        # 保相位推进：基准用「本次计划时刻」而非发送后的当前时刻。
        # 后者已被 kpd 推后，会让每次都被误判为落后而白跳一个周期。
        last ← dueAt
        next ← satAdd(dueAt, iv[i])
        if next ≤ nowUs:                                    # 已经落后
            steps ← (nowUs - next) // iv[i] + 1
            st.dropped += steps                             # 如实记账，即使不物化
            if steps > maxCatchup:
                last ← nowUs                                # 相位重置，不逐个物化
                st.truncated += 1
            else:
                next ← satAdd(next, steps * iv[i])
                last ← next - iv[i]
        bases[i] ← last
        st.emitted += 1
    if outDue.length > lo: insertionSort(outDue, outKey, from=lo)
    return outDue.length - lo + 1
```

**保相位 vs 重置基准**：落后时用「本次计划时刻」推进，保证长期相位不漂移；代价是累计 `dropped`。若改成「基准 = 当前时刻」，相位会随每次抖动漂移。

**为什么要 `MAX_CATCHUP`**：生产无此限制。对「到达即算」的算术无所谓，但一旦引入窗口预生成，系统休眠 8 小时后醒来会瞬间物化上百万个事件。超限策略是相位重置为 `now` 并计数 `truncated`——**记账不丢**（`dropped` 仍如实累加），只是不物化。

### 4.3 SequencePolicy

```
Init(keyCount, delaysUs, originUs):
    dv[i] ← clamp(delaysUs[i] ?? 100_000, MIN_INTERVAL_US, MAX_INTERVAL_US)
    return {step←1, nextUs←originUs, dv, keyCount, dropped←0, emitted←0, truncated←0}

NextDueUs(st):
    if st.keyCount = 0: return NO_DUE
    return st.nextUs                                        # O(1)，无需扫描

CollectInto(st, nowUs, eps, maxCatchup, outDue, outKey):
    if st.keyCount = 0: return 0                            # 空序列
    if nowUs < st.nextUs - eps: return 0                    # 未到期
    step ← (st.step > st.keyCount) ? 1 : st.step            # 越界回卷
    outDue.push(st.nextUs); outKey.push(step)
    st.emitted += 1

    nextDelay ← dv[Mod(step, keyCount) + 1]
    advance ← 1
    next ← satAdd(st.nextUs, nextDelay)
    if next ≤ nowUs:
        skipped ← (nowUs - next) // nextDelay + 1
        st.dropped += skipped
        if skipped > maxCatchup:
            next ← nowUs; st.truncated += 1
        else:
            next ← satAdd(next, skipped * nextDelay)
            advance ← advance + skipped
    st.nextUs ← next
    st.step   ← Mod(step - 1 + advance, st.keyCount) + 1    # 一次取模，保回卷
    return 1
```

每次只发**当前一步**（与生产 `_ExecuteSequence` 一致）——这是序列模式的语义，不是优化余地。

### 4.4 EventWindow（惰性滑动窗口）

```
Fill(want, tickPlan = ""):
    outDue ← []; outKey ← []
    while outDue.length < want:
        due ← policy.NextDueUs(state)
        if due = NO_DUE: break                    # 空序列：立即返回，不空转
        target ← (tickPlan = "") ? due : tickPlan(due, ticks)   # 抖动只作用于唤醒时刻
        clock.Set(target)
        nowUs ← guard.NowUs()                     # 单调钳制后的值
        policy.CollectInto(state, nowUs, _, _, outDue, outKey)
        ticks++
        if spins++ > want*8 + 4096: break         # 兜底防死循环
    truncate(outDue, outKey, want)                # 一轮可能多产出（批量同刻）
    return {dueUs: outDue, keyIdx: outKey, ticks, guard}
```

**惰性**是硬要求：periodic 序列无界，任何「先生成完整序列再发送」的设计都会在长跑下 OOM。窗口只持有「接下来 want 个事件」。

---

## 5. 工程标准

### 5.1 模块化（策略可替换）

`PeriodicPolicy` / `SequencePolicy` / `LegacyPeriodicPolicy` / `LegacySequencePolicy` 实现同一组方法，由同一个 `EventWindow` 驱动。基准里 `impl` 只是一个变量，新旧同口径对比因此不需要任何重复代码。

### 5.2 确定性时序

生成是**纯函数**：`base' = base + interval`，与 `now` 无关。唤醒抖动只改变「tick 何时发生」，从而改变每 tick 收集到几个事件、是否触发追赶，但**不改变计划时刻的值**。

这条被写成断言（单测 `Test_Determinism`）：

```
PlanOnly(42) ≡ PlanOnly(43)     # 计划时刻序列不随唤醒抖动改变
```

⚠️ 一个反直觉的点：**全局事件序列不是单调的**（各键周期不同）。真正成立的不变量是「**每个键自己的计划时刻严格递增**」。第一版单测断言「全局单调」因此失败——是断言写错了，不是实现错了。

### 5.3 重入安全与状态机不变量

AHK 单线程，但定时器回调会在 `Sleep` 等让出点被重入。三条不变量：

1. **策略对象无全局可变状态**——所有状态在 `state` 里，调用方持有
2. **`Collect` 内部不调用任何可让出原语**（`Sleep` / `SendInput` / IPC），「读 state → 写 state」是原子段
3. **单调守卫钳制而非报错**——时钟回拨时沿用上次值（`MonotonicGuard`），`base` 不倒退、不会重复触发；代价是这一刻被推迟。回拨次数 `backsteps` 与累计钳制量 `clampedUs` 均可监控

### 5.4 可配置（参数外部注入）

时间源（`Clock`）、间隔表、容差 `epsilon`、追赶上限 `maxCatchup`、抖动模型（`tickPlan`）全部从外部注入，无硬编码。生产接 `RealClock`，测试/基准接 `VirtualClock`。

---

## 6. 边界条件矩阵

| 场景 | 输入 | 行为 | 单测 |
|---|---|---|---|
| 空序列 | `keyCount = 0` | `NextDueUs` 返回 `NO_DUE`；`CollectInto` 返回 0；**不空转** | `Test_EmptySequence` |
| 单元素 | `keyCount = 1` | 退化为定周期；`Mod(1,1)+1 = 1` 正确回卷 | `Test_SingleElement` |
| 极大间隔 | 接近/超过 24h | 夹紧到 `MAX_INTERVAL_US`；`satAdd` 饱和到 Int64 上限 | `Test_HugeInterval` |
| 极小间隔 | `< 10ms` | 夹紧到 `MIN_INTERVAL_US`（对齐生产 `MIN_INTERVAL_MS=10`） | `Test_MinIntervalClamp` |
| 时钟回拨 | `now` 倒退 | 钳制到上次值，`backsteps++`；不重复触发 | `Test_ClockRollback` |
| 超长追赶 | 落后步数 > 256 | 相位重置为 `now`，`truncated++`，`dropped` **仍如实累计** | `Test_CatchUp` |
| 同刻多键 | 多个键 `dueUs` 相同 | 整数相等 → 同一桶；批量 Down→等→Up | `Test_SameInstantBucketing` |
| enhanced 别名 | `enhanced_periodic` | `SeqModeOf` 归一化后与 `periodic` 逐位相同 | `Test_EnhancedAlias` |
| 窗口不变量 | 任意 `want` | 每键计划时刻严格递增；长度恰为 `want` | `Test_WindowInvariants` |

**状态**：`tools/ahk-bench/lib/seqgen_test.ahk` —— **53 通过 / 0 失败**。

---

## 7. 复杂度分析

设 `K` = 键数，`N` = 产出事件数，`T` = tick 数。

### PeriodicPolicy

| | 最好 | 平均 | 最坏 |
|---|---|---|---|
| `NextDueUs` | O(K) | O(K) | O(K) |
| `CollectInto` | O(1)（无键到期） | O(K + m log m)，m = 本轮事件数 | O(K + K log K)（全部同刻） |
| `Fill(N)` | O(N)（K=1） | O(T·K)，实测 `T ≈ 0.42N` | O(N·K)（每 tick 1 个事件） |
| 空间 | O(N) 输出 + O(K) 状态 | | |

用堆可以把 `NextDueUs` 降到 O(1)/O(log K) 更新，但 K 实测只有个位数，O(K) 扫描的常数远小于堆维护成本——**不做**。

### SequencePolicy

| | 最好 | 平均 | 最坏 |
|---|---|---|---|
| `NextDueUs` | O(1) | O(1) | O(1) |
| `CollectInto` | O(1) | O(1) | O(1)（一次取模 + 一次饱和加） |
| `Fill(N)` | O(N) | O(N) | O(N) |
| 空间 | O(N) 输出 + O(K) 状态 | | |

序列模式天然 O(1)/事件——它每次只推进一步，没有「取最早」的扫描。

### 优化轨迹（实测，非估算）

| 版本 | periodic 100K | 相对旧实现 |
|---|---|---|
| 旧实现（float ms，4 次遍历） | 969 ms | 1.00× |
| 原型 v1（int µs，但热路径 4 次函数调用/tick） | 1350 ms | **0.72×（更慢）** |
| 原型 v2（Init 预夹紧 + 内联饱和 + 零分配） | **622 ms** | **1.56×** |

三处针对性优化：

1. **Init 时预夹紧间隔**进 `st.iv` —— 去掉热路径里 `IntervalUsOf` → `ClampIntervalUs` 两次嵌套调用
2. **内联饱和加法**为 `(b > lim - v) ? lim : (b + v)` —— 去掉 `AddUsSat` 调用
3. **`CollectInto` 写入调用方数组** —— 去掉每 tick 的 2 数组 + 1 对象分配

⚠️ 第 3 点带来一个必须注意的细节：输出数组是复用的，所以**只能排序本轮新增的尾部**（`lo` 参数）。整表重排会让 `Fill` 退化成 O(N²)。

---

## 8. 实测数据（摘要）

完整数据、环境、方法论与复现步骤见 [`scheduling-bench-2026-09-14.md`](./scheduling-bench-2026-09-14.md)。

环境：Windows 11 22631 / AMD Ryzen 5 5600（12 线程）/ 15.9 GB / **QPC 10 MHz** / **AHK v2.0.26**。三轮可复现，判定用 p50，区间重叠即判「未测出差异」。

### 8.1 L1 纯生成（µs/事件，N=100 000）

| 模式 | 旧 | 新 | 加速比 |
|---|---|---|---|
| periodic | 9.42 – 9.51 | 6.02 – 6.11 | **1.56 – 1.57×** |
| sequence | 6.44 – 6.71 | 3.96 – 4.52 | **1.48 – 1.63×** |

加速比在 100 / 1K / 10K / 100K 全程稳定（1.5~1.6×），说明是常数因子收益，不是渐进复杂度。

### 8.2 收益从哪来（每 tick 分解，µs，p50）

| 模式 | 项 | 旧 | 新 |
|---|---|---|---|
| periodic | `NextDueUs` | 8.4 – 8.7 | 5.1 – 5.3 |
| periodic | `CollectInto` | 12.9 – 14.8 | 8.4 – 8.6 |
| sequence | `NextDueUs` | 1.1 – 1.2 | 1.0 – 1.1（**无差异**，本就 O(1)） |
| sequence | `CollectInto` | 4.9 – 5.1 | 2.6 – 2.7 |

### 8.3 L3 端到端（真实时钟，1000 事件）

| 项 | 旧 | 新 | 判定 |
|---|---|---|---|
| periodic `collect_p50` | 34.2 – 43.2 µs | 18.7 – 22.6 µs | 1.6 – 2.0× |
| sequence `collect_p50` | 32.4 – 33.0 µs | 9.0 – 9.8 µs | 3.4 – 3.6× |
| `e2e_p50`（定刻误差） | 8 – 9 µs | 8 – 9 µs | **未测出差异**（与算法无关） |
| CPU / 内存 | — | — | **未测出差异** |

### 8.4 核心收益其实是正确性，不是性能

| 实现 | 100 次「应合并」机会 | 拆桶率 |
|---|---|---|
| 旧（float ms） | 94 次被拆成两桶 | **94 %** |
| 新（int µs） | 0 次 | **0 %** |

6 µs/事件相对 15.625 ms 的定时器网格完全可以忽略——**改的真正理由是消除浮点拆桶**，
性能提升只是顺带拿到的。

---

## 9. 落地路径与风险

### 9.1 建议的落地顺序（收益递减、风险递增）

| 步 | 改动 | 收益 | 风险 |
|---|---|---|---|
| 1 | 时刻表示 float ms → int µs（`HighResClock` 增加 `NowUs()`） | 消除 94% 的拆桶 | 低：新增方法，旧 `Now()` 保留 |
| 2 | 分桶键改用整数 `dueUs` | 同上，且保持时长不再塌成 ~0ms | 低 |
| 3 | 一轮 3 次 `_IntervalOf` 收敛为 1 次（`iv` 预计算） | 约 1.4× | 中：动 `_ExecutePeriodic` 主循环 |
| 4 | `enhanced_*` 显式声明为配置别名 | 消除误读，无性能影响 | 低 |
| 5 | `MAX_CATCHUP` 上限 + `dropped` 记账 | 防休眠唤醒后爆量 | 中：改变追赶语义 |

### 9.2 已知风险

- **`MAX_CATCHUP` 是行为变更**。生产目前允许一次跳任意多步；加上限后，长时间卡顿后相位会重置。好处是 `dropped` 记账不丢，坏处是**相位不再严格保持**——需要产品确认「长时间卡顿后是保相位还是立即跟上」。
- **不要顺手把发送下沉到 Rust**。`SendLevel(10)` + `InputLevel(11)` 会让 Rust 的 `SendInput` 被 AHK 判定为物理键，触发自触发死循环。已实测，见 `MEMORY.md`。
- **`SleepUntil` 忙等会连续占用 AHK 主线程**（实测 interval=100/kpd=15 时最长 31.4ms、占空比 29.2%）。`Collect` 越快，占用窗口越小——这是步 3 的额外收益，但**新增定刻点前必须重新评估占用**。
