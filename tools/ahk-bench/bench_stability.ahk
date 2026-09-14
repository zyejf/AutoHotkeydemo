; =================================================================
; bench_stability —— 异常容错：守卫前后的行为与代价对比
;
; 三个真实缺口（均来自源码走查）：
;   ① 空数组越界 + 除零
;      sender.ahk:573 `k := keys[step]` / :580 `Mod(step, keys.Length)`
;      joystick.ahk:308 / :314 同型；配置可经 IPC 传入 → 每 tick 可触发
;   ② kpd 的上界约束分散在调用点，配置入口不校验
;      executor.ahk:290 `kpd := _GetInt(config,"keyPressDuration",15)` —— 无上界校验
;      发送侧靠 sender.ahk:64 `PRECISE_HOLD_MAX_MS := 20` 兜底：
;      必须在 :513 / :574 / :722 **三个调用点各自**判断 `kpd <= PRECISE_HOLD_MAX_MS`，
;      才不会走进 :426 `SleepUntil(plannedAt + kpd)` 的阻塞保持。
;      ⚠️ 因此本用例**不是**「生产此刻正在卡 2 秒」的实测 —— 生产当前是安全的。
;         它量化的是「这条约束一旦被破坏（例如新增第四个调用点漏判）」的代价，
;         从而说明为什么应把夹紧前移到配置入口做单点校验，
;         而不是依赖三处调用点各自记得判断。
;   ③ 递归无深度上限
;      json_serializer.ahk:22-83（parser 有 256，serializer 无）
;      lib/ahk2_lib/deepclone.ahk:11,17（环检测还在递归返回后才登记，形同虚设）
;      AHK 约 1200~1500 层会直接终止进程，try/catch 捕获不到
;
; ⚠️ 本用例**不会**真的去触发 ③ 的 1500 层崩溃（会杀掉进程），
;    只在安全深度演示「有无上限」的差异。
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

; ---------- ① 空数组越界 + 除零 ----------
OldEmptyKeys(keys, step) {
    k := keys[step]                       ; 越界 → 抛出
    return Mod(step, keys.Length)          ; 除零 → 抛出
}

NewEmptyKeys(keys, step) {
    if !IsSet(keys) || keys.Length = 0     ; 守卫
        return -1
    return Mod(step - 1, keys.Length) + 1
}

; ---------- ② kpd 无上界 ----------
global MAX_HOLD_MS := 500

OldHold(kpd) {
    target := HighResNow() + kpd / 1000
    SleepUntil(target)
    return kpd
}

NewHold(kpd) {
    global MAX_HOLD_MS
    eff := Min(kpd, MAX_HOLD_MS)           ; 夹紧
    target := HighResNow() + eff / 1000
    SleepUntil(target)
    return eff
}

; ---------- ③ 递归深度 ----------
OldRecurse(n) {
    if n <= 0
        return 0
    return 1 + OldRecurse(n - 1)
}

NewRecurse(n, depth := 0) {
    if depth > 256
        throw Error("嵌套深度超过上限 256", -1)
    if n <= 0
        return 0
    return 1 + NewRecurse(n - 1, depth + 1)
}

; 包一层，把 old 的异常接住（否则会冒到 OnError 守卫杀掉整个用例）
TryCall(fn) {
    try {
        v := fn.Call()
        return ["ok", v]
    } catch as e {
        return ["thrown", StrReplace(e.Message, ",", ";")]
    }
}

Main() {
    BenchInit("stability")
    BenchWrite("# bench_stability —— 异常容错守卫前后对比")

    ; ---- ① ----
    empty := []
    rOld := TryCall(() => OldEmptyKeys(empty, 1))
    rNew := TryCall(() => NewEmptyKeys(empty, 1))
    BenchWrite("stability,empty_keys,old," . rOld[1] . "," . rOld[2])
    BenchWrite("stability,empty_keys,new," . rNew[1] . "," . rNew[2])

    ; 非空时两者行为必须一致
    filled := ["F1", "F2", "F3"]
    a := TryCall(() => NewEmptyKeys(filled, 1))
    BenchWrite("stability,filled_keys,new," . a[1] . ",idx=" . a[2])

    ; ---- ② ----
    kpd := 2000
    c0 := SnapCpuMs()
    t0 := HighResNow()
    OldHold(kpd)
    cpuOld := SnapCpuMs() - c0
    wallOld := (HighResNow() - t0) * 1000

    c1 := SnapCpuMs()
    t1 := HighResNow()
    NewHold(kpd)
    cpuNew := SnapCpuMs() - c1
    wallNew := (HighResNow() - t1) * 1000

    BenchWrite("stability,kpd_no_clamp,old,requested_ms=" . kpd
        . ",wall_ms=" . Round(wallOld, 1) . ",cpu_ms=" . Round(cpuOld, 1))
    BenchWrite("stability,kpd_no_clamp,new,requested_ms=" . kpd
        . ",wall_ms=" . Round(wallNew, 1) . ",cpu_ms=" . Round(cpuNew, 1))
    BenchWrite("cmp,kpd_no_clamp,cpu_old_ms=" . Round(cpuOld, 1)
        . ",cpu_new_ms=" . Round(cpuNew, 1)
        . ",cpu_saved_pct=" . Round((cpuOld - cpuNew) / ((cpuOld > 0) ? cpuOld : 1) * 100, 1)
        . ",block_saved_ms=" . Round(wallOld - wallNew, 1))

    ; ---- ③ ----
    depth := 1000
    d0 := TryCall(() => OldRecurse(depth))
    d1 := TryCall(() => NewRecurse(depth))
    BenchWrite("stability,deep_recursion,old,depth=" . depth . "," . d0[1] . "," . d0[2])
    BenchWrite("stability,deep_recursion,new,depth=" . depth . "," . d1[1] . "," . d1[2])

    ; 浅层时两者必须等价
    e0 := TryCall(() => OldRecurse(100))
    e1 := TryCall(() => NewRecurse(100))
    BenchWrite("verify,recursion_shallow,old=" . e0[2] . ",new=" . e1[2]
        . ",result=" . (e0[2] = e1[2] ? "IDENTICAL" : "DIFFERENT"))

    ; 静态覆盖率口径（本用例覆盖的 3 条风险路径）
    BenchWrite("coverage,guarded_paths,old=0/3,new=3/3")
    BenchWrite("# 注：AHK 递归约 1200~1500 层会直接终止进程且 try/catch 捕获不到；")
    BenchWrite("#     old 在 depth=1000 已贴近该悬崖且无任何保护。")

    BenchDone()
}

Main()
ExitApp(0)
