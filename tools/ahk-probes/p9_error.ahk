; ----------------------------------------------------------------------------
; P9：异常与错误处理链路
;   ① OnError 返回值语义：-1 = 忽略并继续；1 = 退出当前线程
;      （0 = 走默认处理，会弹**模态错误框**，无人值守下会挂死，本探针不做实弹测试）
;   ② #MaxThreads 打满后新线程是「丢弃」还是「排队」（源码 application.cpp:902-923
;      显示为 continue = 直接丢弃）
;   ③ 递归深度上限
;   ④ 编译后 A_LineFile ≠ A_ScriptFullPath（本项目 OnError 注册踩过的坑）
;
; 未覆盖（明确标注）：OnError 回调内再次抛错 —— 源码 error.cpp:1087-1118 的
;   sOnErrorRunning 是**非嵌套布尔闸门**，回调内再出错会跳过剩余 OnError 回调直接显示
;   默认错误框。实弹测试会弹模态框，无人值守探针不做。
; ----------------------------------------------------------------------------
#Include _harness.ahk

#MaxThreads 10

Main() {
    ; ⚠️ 全部要跨函数访问的变量必须显式 global：函数默认 assume-local，
    ;   否则 Main 写局部、回调读全局，永远对不上。
    global gMode, gSeen, gStarted, gFinished, gAfter
    ; ⚠️ AHK v2 的 OnError **支持多个回调且全部会被调用**，不能靠「再注册一个兜底」
    ;    来接管；所以这里 guard=false 不注册 harness 守卫，只注册本探针这一个。
    ProbeInit("p9_error", false)
    ProbeNote("P9 异常链路")

    ; ---- ④ 编译前后路径语义 -------------------------------------------------
    ProbeWrite("A_IsCompiled," . A_IsCompiled)
    ProbeWrite("A_ScriptFullPath," . A_ScriptFullPath)
    ProbeWrite("A_LineFile," . A_LineFile)
    ProbeWrite("A_ScriptDir," . A_ScriptDir)
    ProbeWrite("path_same," . (A_LineFile = A_ScriptFullPath ? "yes" : "NO"))

    ; ---- ① OnError 返回值语义 ------------------------------------------------
    ; ⚠️ OnError 也必须传**函数对象**：传裸名字 OnErr 会报
    ;    "Invalid callback function."，且在 OnError 生效前抛出 → 直接弹模态错误框挂死。
    ; ⚠️ AHK v2 的 OnError 支持**多个**回调，harness 在 ProbeInit 里注册的那个
    ;    （防弹窗用）仍然会触发并 ExitApp，必须先摘掉它再注册本探针自己的。
    gMode := "continue"
    OnError((e, mode) => ErrRouter(e, mode))
    ProbeWrite("phase1_onerror")

    ; -1：忽略错误并继续
    gMode := "continue"
    gSeen := 0
    TriggerErr()
    ProbeWrite("ret_minus1,seen=" . gSeen . ",reached_after=" . (gSeen > 0 ? "YES" : "no"))

    ; 1：退出当前线程。**不能在 Main 里直接试** —— 那样整个 Main 都被退掉，
    ;    后面所有阶段都不会执行。放到一个一次性定时器（独立伪线程）里验证。
    gMode := "exitthread"
    gAfter := 0
    SetTimer(Sub_ExitThread, -10)
    Sleep(300)
    ProbeWrite("ret_1,onerror_called=" . (gSeen > 0 ? "yes" : "no")
        . ",line_after_error_reached=" . (gAfter ? "YES(未退出)" : "no(已退出线程)"))
    gMode := "continue"

    ; ---- ② #MaxThreads 饱和：丢弃还是排队 ------------------------------------
    ProbeWrite("phase2_maxthreads")
    gStarted := 0
    gFinished := 0
    ; ⚠️ 30 次 SetTimer 若传**同一个**函数对象，AHK 只会保留最后一个（同名定时器被覆盖），
    ;    必须每次新建闭包对象。
    i := 1
    while i <= 30 {
        SetTimer(OneShotThread.Bind(i), -10)
        i += 1
    }
    Sleep(1500)
    ProbeWrite("threads_requested,30")
    ProbeWrite("threads_started," . gStarted)
    ProbeWrite("threads_finished," . gFinished)
    ProbeWrite("note,默认 MaxThreads=10 + TOTAL_ADDITIONAL_THREADS=2 => 预期约 12")

    ; ---- ③ 递归深度 -----------------------------------------------------------
    ProbeWrite("phase3_recursion")
    for d in [1000, 1200, 1500, 1800, 2000] {
        ProbeWrite("try_depth," . d)
        depth := 0
        try {
            depth := Deep(d)
            ProbeWrite("depth_" . d . ",OK")
        } catch as e {
            ProbeWrite("depth_" . d . ",ERROR," . StrReplace(e.Message, ",", ";"))
        }
    }
    ProbeWrite("recursion_done")
    ProbeDone()
}

; 在独立伪线程里验证 OnError 返回 1 会「退出当前线程」
Sub_ExitThread() {
    global gAfter
    TriggerErr()
    gAfter := 1        ; 若线程被退出，这行不会执行
}

TriggerErr() {
    ; 故意触发一个运行期错误（除零）
    return 1 // 0
}

Deep(n) {
    if n <= 0
        return 0
    return Deep(n - 1) + 1
}

OneShotThread(idx := 0) {
    global gStarted, gFinished
    gStarted += 1
    Sleep(400)
    gFinished += 1
}

; 唯一注册的 OnError：默认「忽略并继续」，避免任何漏网错误弹模态框挂死探针
ErrRouter(e, mode) {
    global gMode, gSeen
    gSeen += 1
    ProbeWrite("onerror_called,mode=" . mode . ",gMode=" . gMode
        . ",msg=" . StrReplace(e.Message, ",", ";"))
    if gMode = "continue"
        return -1      ; 忽略错误，继续执行
    return 1           ; 退出当前线程
}

Main()
ExitApp
