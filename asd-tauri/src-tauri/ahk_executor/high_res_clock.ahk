; =================================================================
; 高精度时钟 - 基于 QueryPerformanceCounter
; 版本: 1.0
; 说明: 为按键发送提供亚毫秒级时间基准与精确定刻能力
;
; 为什么不能沿用 A_TickCount / SetTimer / Sleep（2026-09-13 本机实测，勿凭直觉回退）：
;   · A_TickCount 步进中位 15.52ms —— 无法度量 20ms 以内的延迟
;   · SetTimer 与 Sleep 被锁死在 15.625ms 网格：请求 1/5/10/15ms 全部得到 ~15.6ms；
;     请求 16ms 反而得到 ~31.25ms（跨过网格阈值直接跳两格）
;   · timeBeginPeriod(1) 对 AHK **无效**（调用后 SetTimer(1ms) 仍为 15.68ms）
; 因此本模块以 QPC 为基准，并用「让出式等待 + 末段忙等」实现精确定刻。
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

class HighResClock {
    ; QPC 频率（每秒计数），惰性初始化
    static _freq := 0

    ; 末段纯忙等窗口（ms）：进入此窗口后不再让出，换取最高精度
    static BUSY_WINDOW_MS := 1.0

    ; 允许使用 AHK Sleep 粗调的最小剩余时间（ms）。
    ; Sleep 同样被量化到 15.625ms，必须留出远大于网格的余量才不会过冲
    static COARSE_SLEEP_MIN_MS := 50.0

    ; 粗调时预留的安全余量（ms），用于吸收 15.625ms 量化误差
    static COARSE_SLEEP_MARGIN_MS := 40.0

    ; ---------------------------------------------------------------
    ; 内部：确保 QPC 频率已读取
    ; ---------------------------------------------------------------
    static _EnsureFreq() {
        if HighResClock._freq = 0 {
            f := 0
            DllCall("QueryPerformanceFrequency", "Int64*", &f)
            HighResClock._freq := f > 0 ? f : 1000
        }
        return HighResClock._freq
    }

    ; ---------------------------------------------------------------
    ; 当前时刻（毫秒，浮点，单调）
    ; ---------------------------------------------------------------
    static Now() {
        c := 0
        DllCall("QueryPerformanceCounter", "Int64*", &c)
        return c / HighResClock._EnsureFreq() * 1000
    }

    ; ---------------------------------------------------------------
    ; 当前时刻（微秒，整数，单调）—— 调度内部一律用这个表示时刻
    ;
    ; 为什么调度内部要用整数微秒而不是浮点毫秒（2026-09-14 实测）：
    ;   浮点毫秒累加会产生末位误差。`33.333 + 33.333 + 33.333` 与 `99.999`
    ;   作为 double 并不相等，导致「同一计划时刻」被 Map 判成两个键、拆成两个桶，
    ;   后一个桶的按键保持时长会塌成 ~0ms。整数微秒下 33333*3 = 99999 精确相等。
    ;   实测分桶场景：浮点累加拆桶率 94%，整数微秒 0%。
    ;
    ; ⚠️ 不能写 `c * 1000000 // freq`：c 在长时间运行后可达 8.6e13，乘 1e6 会溢出 Int64。
    ;   必须拆成「整秒部分」与「余数的微秒部分」两段整数运算，全程不丢精度。
    ; ---------------------------------------------------------------
    static NowUs() {
        c := 0
        DllCall("QueryPerformanceCounter", "Int64*", &c)
        f := HighResClock._EnsureFreq()
        return (c // f) * 1000000 + ((Mod(c, f) * 1000000) // f)
    }

    ; ---------------------------------------------------------------
    ; 精确定刻：阻塞等待到绝对时刻 targetMs
    ;
    ; 三段策略：
    ;   远处（≥50ms）→ AHK Sleep 粗调，预留 40ms 余量防过冲
    ;   中段          → Sleep(0) 让出时间片，避免被量化到 15.625ms
    ;   末段（≤1ms）  → 纯忙等，实测误差约 0.002ms
    ;
    ; 代价：等待期间 AHK 主线程无法处理消息（热键 / IPC 会被推迟）。
    ; 这是 AHK 单线程模型下唯一能突破 15.625ms 网格的手段。
    ; ---------------------------------------------------------------
    static SleepUntil(targetMs) {
        loop {
            remaining := targetMs - HighResClock.Now()

            if remaining <= 0
                return HighResClock.Now()

            if remaining >= HighResClock.COARSE_SLEEP_MIN_MS {
                Sleep(Round(remaining - HighResClock.COARSE_SLEEP_MARGIN_MS))
            } else if remaining > HighResClock.BUSY_WINDOW_MS {
                ; Sleep(0) 只让出当前时间片，不会像 Sleep(1) 那样睡满一个网格
                DllCall("kernel32\Sleep", "UInt", 0)
            } else {
                while HighResClock.Now() < targetMs
                    continue
                return HighResClock.Now()
            }
        }
    }

    ; ---------------------------------------------------------------
    ; 精确定刻（微秒口径）：阻塞等待到绝对时刻 targetUs
    ;
    ; 三段策略与 SleepUntil(targetMs) 完全一致，只是时刻表示换成整数微秒。
    ; 注意末段忙等必须用 NowUs() 比较，若退回 Now() 会把 µs 精度重新抹成浮点。
    ; ---------------------------------------------------------------
    static SleepUntilUs(targetUs) {
        loop {
            remainingMs := (targetUs - HighResClock.NowUs()) / 1000

            if remainingMs <= 0
                return HighResClock.NowUs()

            if remainingMs >= HighResClock.COARSE_SLEEP_MIN_MS {
                Sleep(Round(remainingMs - HighResClock.COARSE_SLEEP_MARGIN_MS))
            } else if remainingMs > HighResClock.BUSY_WINDOW_MS {
                DllCall("kernel32\Sleep", "UInt", 0)
            } else {
                while HighResClock.NowUs() < targetUs
                    continue
                return HighResClock.NowUs()
            }
        }
    }
}
