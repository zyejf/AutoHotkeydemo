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
}
