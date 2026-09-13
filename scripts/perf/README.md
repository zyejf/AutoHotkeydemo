# periodic 按键时延打点基准

测量 **periodic 模式**下每一次模拟按键的「计划时刻 → 抬起完成」时延，
用于验证端到端时延目标（P95 ≤ 20 ms，含 `keyPressDuration`）。

报告：`docs/perf/key-latency-benchmark-2026-09-13.md`。

## 1. 测量当前工作区

```bash
# 仓库根目录
AHK="D:/Program Files/AutoHotkey/v2/AutoHotkey.exe"
"$AHK" scripts/perf/bench_periodic_latency.ahk            # 默认 interval=100 kpd=15 运行 3000ms
"$AHK" scripts/perf/bench_periodic_latency.ahk 50 15 3000 result.txt
```

参数依次是 `interval` `kpd` `runMs` `outFile`，均可省略。
结果同时打到 stdout（便于重定向），给了 `outFile` 时额外写文件。

## 2. 复现「优化前」基线

`bench_periodic_latency.ahk` 测的是**当前** `asd-tauri/src-tauri/ahk_executor/sender.ahk`。
要测历史版本，需要给旧版注入观测钩子 —— AHK v2 的**类静态方法是只读的**，
运行时 `Sender._SendKeyDown := fn` 会报 `Property is read-only.`，只能改源码。

步骤（优化前基线来自 `d19f70b~1`）：

```bash
cd /tmp/bench
git -C D:/1demo/AutoHotkeydemo show d19f70b~1:asd-tauri/src-tauri/ahk_executor/sender.ahk > sender_old.ahk
# 依赖：ipc_client.ahk、high_res_clock.ahk（旧版不含后者，但 bench 需要它计时）
```

然后在 `sender_old.ahk` 里手工做**两处**修改（**只改发送原语，绝不动调度/释放逻辑**）：

1. 在 `static _keyEventSender := ""` 后加一行 `static _sendHook := ""`；
2. 把两处 `SendInput("{Blind}{" key " Down}")` / `... Up}")` 包成：

```autohotkey
if Sender._sendHook != "" {
    Sender._sendHook.Call(key, "down")      ; 第二处为 "up"
} else {
    try
        SendInput("{Blind}{" key " Down}")  ; 第二处为 "Up"
    catch as e
        OutputDebug("Sender: 按键按下失败 key=" key " err=" e.Message)
}
```

**自检**：改完后 `grep -c A_TickCount sender_old.ahk` 应仍为 **7** —— 若变少说明误改了调度逻辑，
测出来的就不是原实现的真实行为。

最后写一个两行入口来跑它：

```autohotkey
#Include "high_res_clock.ahk"
#Include "sender_old.ahk"
#Include "<仓库>/scripts/perf/bench_periodic_latency.ahk"   ; 需要去掉其中对 sender.ahk 的 Include
```

## 3. 方法与坑（改脚本前必读）

- **只替换发送原语**：`_sendHook` 必须只包住 `SendInput`，不能碰 `_ScheduleRelease` /
  `_ExecutePeriodic`，否则测的是改过的实现。
- **必须关掉 IPC 上报**：`Sender._keyEventSender` 若为空，会走真实 `IpcClient._SendMsg`，
  I/O 会污染计时。
- **计划时刻用 `firstDown + (i-1)*interval`，不要读内部状态**
  （`state["lastTriggerTimes"]`）：旧版内部基准是 `A_TickCount`、新版是 QPC，
  **纪元不同，直接相减会得到无意义的结果**。
- **停组用 `SetTimer(Sender._timers[gid], 0)`**，不要 `ToggleGroup`——后者会引到
  `Joystick.StopGroup`，凭空多加依赖。
- **结尾必须 `ExitApp(0)`**，否则 AHK 进程不退出。
- **每档至少跑 3~5 轮**：优化前的 P95 在两轮之间可从 15.9 ms 跳到 26.8 ms，
  取决于启动相位落在 15.625 ms 网格的哪个位置。单轮数字不可信。
- 保持时长被压缩（远小于 `kpd`）通常意味着**定时器唤醒迟到**，
  优先检查 `Sender.WAKE_LEAD_MS` 是否 ≥ 一个网格周期（15.625 ms）+ 抖动余量。
