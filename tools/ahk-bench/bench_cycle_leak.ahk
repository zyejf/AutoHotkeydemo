; =================================================================
; bench_cycle_leak —— 循环引用泄漏实测
;
; 依据（AHK v2 引擎硬事实）：AHK 用纯引用计数、无环检测，成环后 refcount
; 永不为 0 → 泄漏，且没有任何手动回收手段。
;
; ⚠️ 测量方法上的两个坑（第一版踩过，已修）：
;   ① 多个用例跑在同一进程里时，AHK 自身分配会让基线持续漂移（实测 3216→4696KB），
;      导致残留量算出负值。**故每个用例必须独立进程**。
;   ② 必须带「阳性对照」：先证明本方法能测出泄漏，再谈被测对象有没有泄漏。
;      第一版直接测闭包自引用只得到 ~5 字节/项，与上一阶段 p5 探到的
;      「循环引用 +22.9MB/5 万」差了两个数量级 —— 说明很可能根本没成环。
;
; 用法：
;   BENCH_CASE=<case> bash tools/ahk-bench/run.sh cycle_leak
; 不带 BENCH_CASE 时跑全部（数据仅供参考，存在基线漂移）。
; =================================================================
#Requires AutoHotkey v2.0
#Include "_harness.ahk"

; ---------- 阳性对照：Map 直接持有自身（必然成环）----------
MakeMapSelfCycle(n) {
    arr := []
    i := 1
    while i <= n {
        m := Map()
        m["self"] := m
        arr.Push(m)
        i++
    }
    return arr
}

MakeMapSelfPlain(n) {
    arr := []
    i := 1
    while i <= n {
        m := Map()
        m["self"] := 1
        arr.Push(m)
        i++
    }
    return arr
}

; ---------- 原型 A：对象互指（skill_group.ahk:793-804 形态）----------
MakeObjCycle(n) {
    arr := []
    i := 1
    while i <= n {
        a := { id: i }
        b := { id: i }
        a.ref := b
        b.ref := a          ; a → b → a，闭环长度 2
        arr.Push(a)
        i++
    }
    return arr
}

MakeObjPlain(n) {
    arr := []
    i := 1
    while i <= n {
        a := { id: i }
        b := { id: i }
        a.ref := b
        b.ref := 2          ; 不成环
        arr.Push(a)
        i++
    }
    return arr
}

; ---------- 原型 B：自引用闭包（skill_manager.ahk:329-379 形态）----------
MakeClosureCycle(n) {
    arr := []
    i := 1
    while i <= n {
        executor(gId, execId) {
            nextFunc := executor.Bind(gId, execId)   ; 引用外层局部变量 executor 自身
            return nextFunc
        }
        arr.Push(executor(i, i))
        i++
    }
    return arr
}

TickImpl(gId, execId) {
    return gId
}

MakeClosurePlain(n) {
    arr := []
    i := 1
    while i <= n {
        arr.Push(TickImpl.Bind(i, i))
        i++
    }
    return arr
}

RunCase(tag, n, makeFn) {
    before := SnapMemKB()
    arr := makeFn.Call(n)
    afterCreate := SnapMemKB()
    arr := ""                    ; 丢弃全部引用
    afterDrop := SnapMemKB()
    BenchWrite("cycle," . tag . ",N=" . n
        . ",before_kb=" . before[2]
        . ",after_create_kb=" . afterCreate[2]
        . ",after_drop_kb=" . afterDrop[2]
        . ",grow_kb=" . (afterCreate[2] - before[2])
        . ",retained_kb=" . (afterDrop[2] - before[2])
        . ",bytes_per_item=" . Round((afterDrop[2] - before[2]) * 1024 / n, 1))
}

Main() {
    bcase := EnvGet("BENCH_CASE")
    N := 50000
    single := (bcase != "")

    BenchInit("cycle_leak", true, single)     ; 单用例模式用追加写
    if !single
        BenchWrite("# 全部模式：存在基线漂移，数据仅供参考；单用例请用 BENCH_CASE")
    BenchWrite("# case=" . (single ? bcase : "ALL") . ",N=" . N)

    if !single || bcase = "ctrl_cycle"
        RunCase("ctrl_cycle(positive control)", N, MakeMapSelfCycle)
    if !single || bcase = "ctrl_plain"
        RunCase("ctrl_plain(negative control)", N, MakeMapSelfPlain)
    if !single || bcase = "obj_cycle"
        RunCase("obj_cycle(old)", N, MakeObjCycle)
    if !single || bcase = "obj_plain"
        RunCase("obj_plain(new)", N, MakeObjPlain)
    if !single || bcase = "closure_cycle"
        RunCase("closure_cycle(old)", N, MakeClosureCycle)
    if !single || bcase = "closure_plain"
        RunCase("closure_plain(new)", N, MakeClosurePlain)

    BenchDone()
}

Main()
ExitApp(0)
