; =================================================================
; periodic 按键时延打点基准（可复现）
;
; 用法:
;   AutoHotkey64.exe scripts\perf\bench_periodic_latency.ahk [interval] [kpd] [runMs] [outFile]
;
; 示例:
;   AutoHotkey64.exe scripts\perf\bench_periodic_latency.ahk 100 15 3000 out.txt
;
; 口径（与 docs/perf/key-latency-benchmark-2026-09-13.md 一致）：
;   计划时刻 planned_i = firstDown + (i - 1) * interval
;   时延     = up_i - planned_i          ; 「计划时刻 -> 抬起完成」
;   保持时长 = up_i - down_i             ; 应等于 kpd
;   周期     = down_i - down_{i-1}       ; 应等于 interval
;
; 观测方式：
;   用 Sender._sendHook 替换发送原语（跳过真实 SendInput，消除副作用），
;   并把 IPC 上报替换为空实现（消除 I/O 干扰）。
;   调度与释放逻辑保持原样，故测得的是真实调度时延。
;
; 注意：本脚本测量的是**当前工作区**的 sender.ahk。
;   若要复现「优化前」基线，见同目录 README.md。
; =================================================================

#Requires AutoHotkey v2.0
#ErrorStdOut "UTF-8"
#Warn VarUnset, OutputDebug
#Warn Unreachable, OutputDebug
#Warn LocalSameAsGlobal, Off

#Include "../../asd-tauri/src-tauri/ahk_executor/high_res_clock.ahk"
#Include "../../asd-tauri/src-tauri/ahk_executor/sender.ahk"

SortAsc(arr) {
    i := 2
    while i <= arr.Length {
        v := arr[i], j := i - 1
        while j >= 1 && arr[j] > v {
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := v
        i++
    }
    return arr
}

Pct(arr, p) {
    if arr.Length = 0
        return 0
    idx := Ceil(arr.Length * p)
    idx := Max(1, Min(idx, arr.Length))
    return arr[idx]
}

StatBlock(title, arr, target) {
    if arr.Length = 0
        return "  " title "：无采样`n"
    a := SortAsc(arr.Clone())
    s := "  " title "（目标 " target "）`n"
    s .= "    中位 " Round(Pct(a, 0.5), 3) " ms`n"
    s .= "    P95  " Round(Pct(a, 0.95), 3) " ms`n"
    s .= "    最大 " Round(a[a.Length], 3) " ms`n"
    return s
}

interval := A_Args.Length >= 1 ? Integer(A_Args[1]) : 100
kpd      := A_Args.Length >= 2 ? Integer(A_Args[2]) : 15
runMs    := A_Args.Length >= 3 ? Integer(A_Args[3]) : 3000
outFile  := A_Args.Length >= 4 ? A_Args[4] : ""

gid := "__bench"
events := []

; 跳过真实 IPC 上报
Sender._keyEventSender := (msg) => true
; 发送原语改为打点
Sender._sendHook := (key, st) => events.Push([st, HighResClock.Now()])

t_start := HighResClock.Now()
Sender.StartPeriodic(gid, ["F1"], [interval], kpd)
Sleep runMs
firstDown := events.Length >= 1 ? events[1][2] : 0

; 停止：直接摘定时器，避免引入 joystick 依赖
if Sender._timers.Has(gid)
    SetTimer(Sender._timers[gid], 0)

downs := []
ups := []
for e in events {
    if e[1] = "down"
        downs.Push(e[2])
    else if e[1] = "up"
        ups.Push(e[2])
}

latencies := []
holds := []
i := 1
while i <= ups.Length {
    if i <= downs.Length
        holds.Push(ups[i] - downs[i])
    latencies.Push(ups[i] - (firstDown + (i - 1) * interval))
    i++
}

periods := []
i := 2
while i <= downs.Length {
    periods.Push(downs[i] - downs[i - 1])
    i++
}

out := "配置: interval=" interval "ms, kpd=" kpd "ms, 运行 " runMs "ms`n"
out .= "按下次数: " downs.Length "（理论约 " Floor(runMs / interval) " 次）`n"
out .= "首键延迟: " Round(firstDown - t_start, 3) " ms（启动到第一次按下）`n"
out .= "`n"
out .= StatBlock("[计划时刻 -> 抬起完成] 时延", latencies, "≤ 20 ms")
out .= "`n"
out .= StatBlock("[按下 -> 抬起] 单次保持时长", holds, kpd " ms")
out .= "`n"
out .= StatBlock("[相邻按下间隔] 周期保真度", periods, interval " ms")

out .= "`n[逐次明细] i / 按下-计划(ms) / 抬起-计划(ms) / 保持(ms)`n"
i := 1
while i <= downs.Length {
    dErr := downs[i] - (firstDown + (i - 1) * interval)
    uErr := (i <= ups.Length) ? ups[i] - (firstDown + (i - 1) * interval) : ""
    h := (i <= ups.Length) ? ups[i] - downs[i] : ""
    out .= "  " i "`t" Round(dErr, 3) "`t" (uErr = "" ? "-" : Round(uErr, 3)) "`t" (h = "" ? "-" : Round(h, 3)) "`n"
    i++
}

if outFile != ""
    FileAppend(out, outFile, "UTF-8")

FileAppend(out, "*")
ExitApp(0)
