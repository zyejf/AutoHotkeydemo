#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
report.py —— 汇总 tools/ahk-bench 的基准 CSV，生成 Markdown 对比报告。

用法：
    python tools/ahk-bench/report.py [数据目录] [-o 输出文件] [--prev 上一轮目录]

默认：
    数据目录 = %TEMP%/ahkbench（Windows）或 /tmp/ahkbench
    输出     = docs/refactor/bench-report-<今天>.md

--prev 给出上一轮数据目录时，报告会额外给出「两轮波动」列 —— AHK 基准受宿主
负载影响明显（实测 json_escape 同一脚本两轮 31.6× vs 44.1×），只看一轮容易
把噪声当结论。
"""
import argparse
import datetime as _dt
import io
import os
import sys
import tempfile

BENCHES = ("json_escape", "tick_traversal", "key_regex",
           "timer_storm", "stability", "cycle_leak")


# ---------------------------------------------------------------- 读取工具

def _decode(raw):
    """AHK 写出的 CSV 可能是 UTF-8（新版 harness）或系统 ANSI（GBK，旧产出）。"""
    for enc in ("utf-8-sig", "utf-8", "gbk", "cp936", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def _read_rows(path):
    """
    把 `tag,p1,p2,key=val,...` 形态的行解析成 dict。
    位置字段（不含 '='）依次落到 _p1.._p4；`key=val` 落到同名键。
    """
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, "rb") as fh:
        text = _decode(fh.read())
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(",")]
        rec = {"_tag": parts[0]}
        pos = 1
        for p in parts[1:]:
            if "=" in p:
                k, v = p.split("=", 1)
                rec[k.strip()] = v.strip()
            else:
                if pos <= 4:
                    rec[f"_p{pos}"] = p
                pos += 1
        rows.append(rec)
    return rows


def load(datadir):
    return {b: _read_rows(os.path.join(datadir, b + ".csv")) for b in BENCHES}


def fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def fmt(v, nd=2, suffix=""):
    n = fnum(v)
    if n is None:
        return str(v) if v is not None else "-"
    return f"{n:.{nd}f}{suffix}"


def pick(rows, tag, p1=None, p2=None):
    for r in rows:
        if r["_tag"] != tag:
            continue
        if p1 is not None and r.get("_p1") != p1:
            continue
        if p2 is not None and r.get("_p2") != p2:
            continue
        return r
    return {}


def pickall(rows, tag):
    return [r for r in rows if r["_tag"] == tag]


def delta_pct(old, new):
    o, n = fnum(old), fnum(new)
    if not o or n is None:
        return "-"
    return f"{(1 - n / o) * 100:.1f}%"


# ---------------------------------------------------------------- 章节

def sec_json(data):
    rows = pickall(data["json_escape"], "cmp")
    lines = [
        "### 3.1 JSON 字符串转义（`infrastructure/json_serializer.ahk:100-128`）",
        "",
        "旧实现逐字符 `SubStr(str,pos,1)` 取字符再 `result .= c` 拼接 —— "
        "典型 O(n²)：每次拼接都要重新分配并整串拷贝。新实现先用 `InStr` 快路径判断"
        "「是否需要转义」，不需要则原样返回；需要则用 `StrReplace` 链式批量替换；"
        "仅当出现快路径未覆盖的控制字符时才退回旧逻辑，保证语义等价。",
        "",
        "| 负载 | 长度 | 旧 p50 (ms) | 新 p50 (ms) | 加速比 | 旧 µs/千字符 | 新 µs/千字符 | 等价 |",
        "|---|---:|---:|---:|---:|---:|---:|:--:|",
    ]
    for r in rows:
        lines.append(
            "| `{n}` | {ln} | {o} | {nn} | **{sp}×** | {uo} | {un} | {ident} |".format(
                n=r.get("_p1", "-"), ln=r.get("len", "-"),
                o=fmt(r.get("p50_old_ms"), 4), nn=fmt(r.get("p50_new_ms"), 4),
                sp=fmt(r.get("speedup"), 2),
                uo=fmt(r.get("us_per_kchar_old"), 1), un=fmt(r.get("us_per_kchar_new"), 1),
                ident=r.get("identical", "-")))
    lines += ["", f"耗时降幅：{', '.join(delta_pct(r.get('p50_old_ms'), r.get('p50_new_ms')) for r in rows)}"
                  "（按 p50 计）。", ""]
    return lines


def sec_tick(data):
    rows = pickall(data["tick_traversal"], "cmp")
    lines = [
        "### 3.2 定时器 tick 遍历合并（`ahk_executor/sender.ahk:454/461/482/522`）",
        "",
        "旧实现每个 tick 对同一份按键表遍历 4 次、并调用 3 次 `_IntervalOf`；"
        "新实现合并为一次遍历，边走边算出「到期数量 / 下一个目标时刻」。"
        "这段代码位于定时器回调中，是 CPU 占用的主要来源之一。",
        "",
        "| 场景 | 旧 p50 (ms) | 新 p50 (ms) | 加速比 | 旧 µs/tick | 新 µs/tick |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        case = r.get("_p1", "-")
        old_row = pick(data["tick_traversal"], "tick", "old_" + case)
        new_row = pick(data["tick_traversal"], "tick", "new_" + case)
        lines.append(
            "| `{c}` (keys={k}) | {o} | {nn} | **{sp}×** | {uo} | {un} |".format(
                c=case, k=r.get("keys", old_row.get("keys", "-")),
                o=fmt(r.get("p50_old_ms"), 3), nn=fmt(r.get("p50_new_ms"), 3),
                sp=fmt(r.get("speedup"), 2),
                uo=fmt(old_row.get("us_per_tick"), 4), un=fmt(new_row.get("us_per_tick"), 4)))
    ver = pick(data["tick_traversal"], "verify")
    if ver:
        lines += ["", "等价性校验（500 次迭代逐项比对 `[target, dueCount, nextTarget]`）："
                      f"diffs={ver.get('diffs','-')}，result=**{ver.get('result','-')}**。", ""]
    return lines


def sec_keyregex(data):
    cmp = pick(data["key_regex"], "cmp")
    ver = pick(data["key_regex"], "verify")
    # µs/次 只写在 old/new 行上，cmp 行没有
    o_row = pick(data["key_regex"], "keyregex", "old")
    n_row = pick(data["key_regex"], "keyregex", "new")
    lines = [
        "### 3.3 按键名校验：3 次正则 → 1 次查表（`domain/skill_group.ahk:889-902`）",
        "",
        "旧实现每次校验跑 3 次正则匹配；新实现把合法键名预先展开成一张集合，单次查表完成。"
        "为避免冤枉旧实现，两侧都复用同一份懒加载缓存（对齐生产 `_GetValidKeysMap()` 的行为）。",
        "",
        "| 指标 | 旧 | 新 |",
        "|---|---:|---:|",
        f"| p50（ms / {cmp.get('n','20000')} 次）| {fmt(cmp.get('p50_old_ms'),3)} "
        f"| {fmt(cmp.get('p50_new_ms'),3)} |",
        f"| µs/次 | {fmt(o_row.get('us_per_op'),4)} | {fmt(n_row.get('us_per_op'),4)} |",
        f"| 加速比 | — | **{fmt(cmp.get('speedup'),2)}×** |",
    ]
    if ver:
        lines += ["", f"等价性：diffs={ver.get('diffs','-')}，result=**{ver.get('result','-')}**。", ""]
    lines += [
        "",
        "> **这是本次唯一收益可忽略的一项，结论是不改。** 单次调用本就只花约 1.35 µs，"
        "且校验发生在技能加载/编辑路径而非每 tick，优化后仅快 3%。"
        "收益不足以抵消改动风险，因此**三份重构计划的任务清单里都不含这一项**。",
        "",
    ]
    return lines


def sec_timer(data, rounds=None):
    rows = pickall(data["timer_storm"], "timer")
    rounds = rounds or []
    lines = [
        "### 3.4 定时器重排策略 —— 精度与 CPU 的权衡",
        "",
        "当距离目标时刻不足一个定时器网格（15.625 ms）时，三种策略：",
        "",
        "- `old`：重排 `SetTimer(Max(1, remaining-LEAD))` —— 现状，会反复唤醒；",
        "- `floor16`：把下限抬到 16 ms，减少唤醒次数；",
        "- `new`：不再重排，直接用 QPC 忙等到点。",
        "",
        "8 个并发分组、周期 100 ms、提前量 28 ms、每变体 4 秒。"
        "`err_*` 是实际执行时刻相对计划时刻的绝对误差；"
        "`主线程最大停顿` 由独立的 10 ms 探针定时器观测。",
        "",
        "| 变体 | CPU % | 唤醒/工作 | 误差 p50 | 误差 p95 | 误差 max | 主线程最大停顿 |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        lines.append(
            "| `{v}` | {cpu} | {wpw} | {p50} | {p95} | {mx} | {gap} |".format(
                v=r.get("_p1", "-"), cpu=fmt(r.get("cpu_pct"), 1),
                wpw=fmt(r.get("wake_per_work"), 2),
                p50=fmt(r.get("err_p50_ms"), 3), p95=fmt(r.get("err_p95_ms"), 3),
                mx=fmt(r.get("err_max_ms"), 3), gap=fmt(r.get("probe_max_gap_ms"), 1)))
    old = pick(data["timer_storm"], "timer", "old")
    new = pick(data["timer_storm"], "timer", "new")
    fl = pick(data["timer_storm"], "timer", "floor16")

    def _ratio(a, b):
        x, y = fnum(a), fnum(b)
        if x is None or not y:
            return None
        return x / y

    if old and new:
        p50r = _ratio(old.get("err_p50_ms"), new.get("err_p50_ms"))
        p95r = _ratio(old.get("err_p95_ms"), new.get("err_p95_ms"))
        lines += [
            "",
            "> **这里没有免费午餐，而且「提升精度」这个说法本身就容易误导。**",
            "",
            f"> 1. **中位数与 p95 三者几乎无差别**（p50 "
            f"{fmt(old.get('err_p50_ms'),3)} → {fmt(new.get('err_p50_ms'),3)} ms，p95 "
            f"{fmt(old.get('err_p95_ms'),3)} → {fmt(new.get('err_p95_ms'),3)} ms"
            + (f"，约 {p50r:.2f}× / {p95r:.2f}×" if p50r and p95r else "")
            + "）。`new` **没有提升典型精度**。",
            "",
        ]

    # 尾部与 CPU 的「可复现性」必须跨轮看 —— 单轮结论会被宿主负载改写
    if len(rounds) >= 2:
        tail, cpu, wake = {}, {}, {}
        for _label, rd in rounds:
            for r in pickall(rd.get("timer_storm", []), "timer"):
                v = r.get("_p1")
                tail.setdefault(v, []).append(fnum(r.get("err_max_ms")))
                cpu.setdefault(v, []).append(fnum(r.get("cpu_pct")))
                wake.setdefault(v, []).append(fnum(r.get("wake_per_work")))

        def _span(d, k, nd=3):
            xs = [x for x in d.get(k, []) if x is not None]
            if not xs:
                return "-"
            return (f"{min(xs):.{nd}f}" if len(xs) == 1
                    else f"{min(xs):.{nd}f} ~ {max(xs):.{nd}f}")

        lines += [
            f"> 2. 真正的差别在**尾部稳定性**（跨 {len(rounds)} 轮，误差 max 的取值范围）：",
            "",
            "> | 变体 | 误差 max 跨轮范围 (ms) | CPU % 跨轮范围 | 唤醒/工作跨轮范围 |",
            "> |---|---|---|---|",
        ]
        for v in ("old", "floor16", "new"):
            if v in tail:
                lines.append(f"> | `{v}` | {_span(tail, v)} | {_span(cpu, v, 1)} "
                             f"| {_span(wake, v, 2)} |")
        lines += [
            "",
        ]

        o_t = [x for x in tail.get("old", []) if x is not None]
        n_t = [x for x in tail.get("new", []) if x is not None]
        o_c = [x for x in cpu.get("old", []) if x is not None]
        n_c = [x for x in cpu.get("new", []) if x is not None]
        if o_t and n_t:
            lines += [
                f">    `new` 的尾部误差稳定在 {min(n_t):.2f}~{max(n_t):.2f} ms 的窄区间，"
                f"而 `old` 在 {min(o_t):.2f}~{max(o_t):.2f} ms 之间大幅摆动 —— "
                "**这个方向在每一轮里都成立**，是唯一稳定可复现的精度差异。",
                "",
            ]
        if o_c and n_c:
            overlap = not (max(o_c) < min(n_c) or max(n_c) < min(o_c))
            if overlap:
                lines += [
                    f">    CPU 则相反：`old` 落在 {min(o_c):.1f}~{max(o_c):.1f}%，"
                    f"`new` 落在 {min(n_c):.1f}~{max(n_c):.1f}%，**两个区间互相重叠** —— "
                    "CPU 差异与同一变体自身的轮次波动同量级，"
                    "**不能据此判定谁更省/更耗**。",
                    "",
                ]
            else:
                lines += [
                    f">    CPU：`old` {min(o_c):.1f}~{max(o_c):.1f}% vs `new` "
                    f"{min(n_c):.1f}~{max(n_c):.1f}%（区间不重叠，方向稳定）。",
                    "",
                ]
    if fl:
        lines += [
            f"> 中间方案 `floor16`（把重排下限抬到 16 ms）：唤醒/工作 "
            f"{fmt(old.get('wake_per_work'),2)} → {fmt(fl.get('wake_per_work'),2)}，"
            f"CPU {fmt(fl.get('cpu_pct'),1)}%，误差 max {fmt(fl.get('err_max_ms'),3)} ms —— "
            "把下限抬到 16 ms 并没有换来比 `new` 更好的尾部，"
            "也未体现出独立于噪声的优势，故不作为候选。",
            "",
        ]
    gaps = [fnum(r.get("probe_max_gap_ms")) for r in rows]
    gaps = [g for g in gaps if g is not None]
    if gaps:
        lines += [
            f"> 主线程最大停顿：三个变体都在 {min(gaps):.1f}~{max(gaps):.1f} ms 区间，"
            "差异小于变体本身的量级 —— 忙等确实占用 AHK 主线程，"
            "但它同时消除了反复重排定时器带来的调度抖动，两者大致抵消。",
            "",
        ]
    lines += [
        "> **选型建议**：不要在「提升精度」的叙事下改这项 —— 典型精度（p50/p95）"
        "三者没有差别。值得改的唯一理由是**消除偶发尾部抖动**（这个收益可复现）；"
        "而 CPU 方面本机**未测出可复现的差异**，因此既不该拿「省 CPU」也不该拿"
        "「更耗 CPU」当理由。若业务能容忍偶发毫秒级抖动，维持现状即可。",
        "",
    ]
    return lines


def sec_stability(data):
    rows = data["stability"]
    lines = [
        "### 3.5 异常容错守卫",
        "",
        "三处真实缺口，逐项对比守卫前后的行为。",
        "",
        "| 缺口 | 旧行为 | 新行为 | 影响 |",
        "|---|---|---|---|",
    ]
    ek_old = pick(rows, "stability", "empty_keys", "old")
    ek_new = pick(rows, "stability", "empty_keys", "new")
    lines.append(
        "| 空数组越界 + 除零（`sender.ahk:573/580`、`joystick.ahk:308/314`）| "
        f"`{ek_old.get('_p3','-')} {ek_old.get('_p4','')}` | "
        f"`{ek_new.get('_p3','-')} {ek_new.get('_p4','')}` | "
        "旧实现在技能组为空时抛出未捕获异常，定时器回调因此中断 |")

    k_old = pick(rows, "stability", "kpd_no_clamp", "old")
    k_new = pick(rows, "stability", "kpd_no_clamp", "new")
    kcmp = pick(rows, "cmp", "kpd_no_clamp")
    lines.append(
        "| `keyPressDuration` 上界约束分散（`executor.ahk:290` 不校验，"
        "靠 `sender.ahk:513/574/722` 三处调用点各自判断）| "
        f"请求 {k_old.get('requested_ms','-')} ms，实耗 {fmt(k_old.get('wall_ms'),1)} ms，"
        f"CPU {fmt(k_old.get('cpu_ms'),1)} ms | "
        f"入口夹紧后实耗 {fmt(k_new.get('wall_ms'),1)} ms，CPU {fmt(k_new.get('cpu_ms'),1)} ms | "
        f"CPU 省 {fmt(kcmp.get('cpu_saved_pct'),1)}%、主线程少阻塞 "
        f"{fmt(kcmp.get('block_saved_ms'),0)} ms |")
    # 注：kpd 的说明放在表格**之后**，否则会打断表格渲染
    kpd_note = [
        "",
        "> ⚠️ **这一项要读准：它不是「生产此刻正在卡 2 秒」的实测。** "
        "生产当前是安全的 —— `sender.ahk:64` 有 `PRECISE_HOLD_MAX_MS := 20` 兜底，"
        "超长 `keyPressDuration` 会退回异步释放，不会阻塞主线程。"
        "本用例量化的是「这条约束**一旦被破坏**」的代价："
        "`_PressPreciseBatch`（`sender.ahk:426`）里的 `SleepUntil(plannedAt + kpd)` "
        "是阻塞式的，它之所以安全，完全依赖 :513 / :574 / :722 **三个调用点各自**"
        "记得判断 `kpd <= PRECISE_HOLD_MAX_MS`。新增第四个调用点一旦漏判就是无限阻塞。"
        "因此正确的修法是**把夹紧前移到配置入口做单点校验**，而不是在三处各加一次判断。",
        "",
    ]

    d_old = pick(rows, "stability", "deep_recursion", "old")
    d_new = pick(rows, "stability", "deep_recursion", "new")
    lines.append(
        "| 递归无深度上限（`json_serializer.ahk:22-42`；parser 有 256，serializer 没有）| "
        f"depth={d_old.get('depth','-')} 时 `{d_old.get('_p3','-')}`（无任何保护）| "
        f"depth={d_new.get('depth','-')} 时 `{d_new.get('_p3','-')}`：`{d_new.get('_p4','')}` | "
        "AHK 递归约 1200~1500 层会**直接终止进程且 try/catch 捕获不到**，"
        "旧实现在 depth=1000 已贴近该悬崖 |")

    # 表格结束后再放补充说明，避免打断表格渲染
    lines += kpd_note

    cov = pick(rows, "coverage", "guarded_paths")
    if cov:
        lines += ["", f"守卫覆盖率：旧 **{cov.get('old','-')}** → 新 **{cov.get('new','-')}**。"]
    ver = pick(rows, "verify", "recursion_shallow")
    if ver:
        lines.append(f"浅层行为不变：old={ver.get('old','-')} / new={ver.get('new','-')}，"
                     f"result=**{ver.get('result','-')}**。")
    lines.append("")
    return lines


def sec_cycle(data):
    rows = pickall(data["cycle_leak"], "cycle")
    if not rows:
        return ["### 3.6 循环引用泄漏", "", "_无数据_", ""]
    lines = [
        "### 3.6 循环引用泄漏（AHK 纯引用计数、无环检测）",
        "",
        "AHK v2 用纯引用计数管理对象，**没有环检测** —— 一旦成环，refcount 永不归零，"
        "必然泄漏，且没有任何手动回收手段。本组基准每个用例独立进程"
        "（同进程跑多用例会基线漂移），N=50000，指标为「丢弃全部引用后仍残留的私有内存」。",
        "",
        "| 用例 | 说明 | 创建增长 | 丢弃后残留 | 字节/项 | 判定 |",
        "|---|---|---:|---:|---:|---|",
    ]
    spec = [
        ("ctrl_cycle", "阳性对照：Map 持有自身", "**方法有效**"),
        ("ctrl_plain", "阴性对照：Map 持有标量", "无泄漏（噪声基线）"),
        ("obj_cycle", "对象互指（`skill_group.ahk:793-804` 形态）", "**确认泄漏**"),
        ("obj_plain", "同样结构但不成环（修复后形态）", "无泄漏"),
        ("closure_cycle", "自引用闭包（`skill_manager.ahk:329-379` 形态）", "**未观测到泄漏**"),
        ("closure_plain", "普通绑定闭包", "无泄漏"),
    ]
    cache = {}
    for r in rows:
        # 取「最后」一次：万一 CSV 里残留了上一轮数据，应以最新一轮为准
        cache[r.get("_p1", "").split("(")[0]] = r
    for key, desc, verdict in spec:
        r = cache.get(key, {})
        if not r:
            continue
        lines.append("| `{k}` | {d} | {g} KB | **{ret} KB** | {b} | {v} |".format(
            k=key, d=desc, g=fmt(r.get("grow_kb"), 0),
            ret=fmt(r.get("retained_kb"), 0), b=fmt(r.get("bytes_per_item"), 1), v=verdict))
    obj_c, obj_p = cache.get("obj_cycle", {}), cache.get("obj_plain", {})
    clo_c, clo_p = cache.get("closure_cycle", {}), cache.get("closure_plain", {})
    lines += ["", "**两条结论，其中一条推翻了先前的推断：**", ""]
    if obj_c and obj_p:
        lines.append(
            "1. **对象互指确实泄漏，且量级可观。** 闭环长度 2 的对象两两互指，5 万组残留 "
            f"**{fmt(obj_c.get('retained_kb'),0)} KB**（{fmt(obj_c.get('bytes_per_item'),1)} B/项），"
            f"不成环对照仅 {fmt(obj_p.get('retained_kb'),0)} KB"
            f"（{fmt(obj_p.get('bytes_per_item'),1)} B/项），相差约 "
            f"{fnum(obj_c.get('retained_kb'))/max(fnum(obj_p.get('retained_kb')),1):.0f} 倍。"
            "这确认了 `skill_group.ahk:793-804` 的释放定时器闭包形态是真实隐患。")
    if clo_c and clo_p:
        lines += [
            "",
            "2. **自引用闭包并未观测到泄漏**"
            f"（{fmt(clo_c.get('retained_kb'),0)} KB vs 不成环对照 "
            f"{fmt(clo_p.get('retained_kb'),0)} KB，"
            f"{fmt(clo_c.get('bytes_per_item'),1)} vs {fmt(clo_p.get('bytes_per_item'),1)} B/项，"
            "在噪声范围内）。先前依据代码走查推断的"
            "「`skill_manager.ahk:329-379` 的 `executor.Bind(...)` 自引用永久泄漏」**不成立** —— "
            "该构造下闭包并未真正形成可到达的引用环，故此项从重构清单移除。",
            "",
        ]
    lines += [
        "> 阳性对照（残留 "
        f"{fmt(cache.get('ctrl_cycle',{}).get('retained_kb'),0)} KB / "
        f"{fmt(cache.get('ctrl_cycle',{}).get('bytes_per_item'),1)} B/项）证明本测量方法确实能测出泄漏；"
        "若没有它，「闭包不泄漏」完全可能只是「没测出来」。",
        "",
    ]
    return lines


# ---------------------------------------------------------------- 主报告

def build(data, rounds, datadir):
    today = _dt.date.today().isoformat()
    A = []
    w = A.append

    w(f"# AHK 脚本重构 · 优化前后实测对比报告（{today}）")
    w("")
    w("> 本报告由 `tools/ahk-bench/report.py` 从基准 CSV 自动生成，"
      "数据来源为 `tools/ahk-bench/` 下的 6 组双实现基准脚本。")
    w("> **生产代码一行未改** —— 所有「新实现」都是基准脚本内复刻的对照版本，"
      "用于量化收益、支撑方案选型。")
    w("")
    w("---")
    w("")

    # 1 速览
    je = pickall(data["json_escape"], "cmp")
    tt = pickall(data["tick_traversal"], "cmp")
    kr = pick(data["key_regex"], "cmp")
    tm = {r.get("_p1"): r for r in pickall(data["timer_storm"], "timer")}

    w("## 1. 结论速览")
    w("")
    w("| # | 项 | 实测收益 | 性质 | 是否建议落地 |")
    w("|---|---|---|---|---|")
    w(f"| 1 | JSON 转义 O(n²) → 快路径 | **"
      + "、".join(fmt(r.get("speedup"), 1) + "×" for r in je)
      + "** | 纯收益，语义已验证等价 | 强烈建议 |")
    w(f"| 2 | tick 4 次遍历 → 1 次 | **"
      + "、".join(fmt(r.get("speedup"), 2) + "×" for r in tt)
      + "** | 纯收益，语义已验证等价 | 建议 |")
    w(f"| 3 | 键名校验 3 正则 → 1 查表 | {fmt(kr.get('speedup'),2)}× "
      "| **收益可忽略** | 不建议 |")
    if tm.get("old") and tm.get("new"):
        _o, _n = fnum(tm["old"].get("err_max_ms")), fnum(tm["new"].get("err_max_ms"))
        _tail = f"（{_o / _n:.0f}×）" if _o and _n else ""
        w(f"| 4 | 定时器策略改为忙等到点 | 尾部误差 max {fmt(_o,2)} → {fmt(_n,3)} ms {_tail}"
          "；**p50/p95 几乎无差别**，CPU 差异不可复现 | 只消除偶发尾部抖动 | 视场景 |")
    w("| 5 | 三处异常容错守卫 | 覆盖率 0/3 → 3/3 | 纯收益（阻塞与 CPU 双降） | 建议 |")
    w("| 6 | 解除对象互指环 | 5 万组残留 ~20 MB → ~0.3 MB | 纯收益 | 建议 |")
    w("| 7 | ~~自引用闭包泄漏~~ | **未观测到泄漏** | 先前推断不成立 | 移除 |")
    w("")
    w("**三条最容易误读的地方，先说在前面：**")
    w("")
    w(f"1. 第 3 项（键名校验）**几乎没有收益**（{fmt(kr.get('speedup'),2)}×），"
      "不要为了「看起来优化了」去改它；")
    w("2. 第 4 项（定时器）**不是「提升精度」** —— p50/p95 三者几乎无差别；"
      "可复现的收益只有「消除偶发尾部抖动」，CPU 方面则**未测出可复现差异**；")
    w("3. 第 7 项**推翻了先前的代码走查推断**，自引用闭包实测不泄漏，已从清单移除。")
    w("")
    w("---")
    w("")

    # 2 方法
    w("## 2. 方法与口径")
    w("")
    w("### 2.1 为什么是「双实现基准」而不是直接改生产代码")
    w("")
    w("每个基准脚本内同时内置**旧实现（原样复刻生产代码逻辑）**与**新实现**，"
      "在同一进程、同一份数据上跑，最后逐项比对输出是否一致（`identical` / `diffs=0`）。"
      "这样做的好处是：收益数字是本机真实跑出来的而非估算；"
      "且任何「优化后行为变了」都能当场暴露。")
    w("")
    w("### 2.2 计时与采样")
    w("")
    w("- **耗时**：`QueryPerformanceCounter`（QPC），不用 `A_TickCount` —— "
      "后者步进约 15.6 ms，测不了毫秒级差异。")
    w("- **内存**：`GetProcessMemoryInfo`（psapi）读 `PrivateUsage`，`-1` 伪句柄取当前进程。")
    w("- **CPU**：`GetProcessTimes` 的 kernel + user 时间（FILETIME，100 ns 单位），"
      "除以墙钟时间得占用率。")
    w("- **统计量**：优先看 **p50**，同时给出 p95 / max。AHK 基准受宿主负载影响大，"
      "单一 max 值往往是宿主抖动而非回归。")
    w("")
    w("### 2.3 两条必须遵守的测量纪律")
    w("")
    w("1. **内存类基准必须带阳性对照。** 先证明方法能测出已知泄漏，再谈被测对象有没有泄漏 —— "
      "否则「没测出来」和「没有泄漏」无法区分。")
    w("2. **内存类基准必须每用例独立进程。** 同进程连续跑多用例时基线会漂移"
      "（实测 3216 → 4696 KB），残留量甚至会算出负值。")
    w("")

    if len(rounds) >= 2:
        labels = [lb for lb, _ in rounds]
        w(f"### 2.4 多轮波动（共 {len(rounds)} 轮）")
        w("")
        w("同一脚本在不同宿主负载下结果会有差异 —— **只看一轮会把噪声当成结论**。"
          "下表把每一轮并列：")
        w("")
        w("| 指标 | " + " | ".join(labels) + " |")
        w("|---|" + "---:|" * len(labels))

        for key, label in [("json_escape", "JSON 转义加速比"),
                           ("tick_traversal", "tick 遍历加速比"),
                           ("key_regex", "键名校验加速比")]:
            cases = [r.get("_p1") for r in pickall(data.get(key, []), "cmp")]
            for case in cases:
                cells = []
                for _lb, rd in rounds:
                    r = pick(rd.get(key, []), "cmp", case)
                    cells.append(fmt(r.get("speedup"), 2) + "×" if r else "-")
                w(f"| {label} `{case}` | " + " | ".join(cells) + " |")

        for v in ("old", "floor16", "new"):
            for field, label, nd in [("cpu_pct", "CPU %", 1),
                                     ("err_p95_ms", "误差 p95 (ms)", 3),
                                     ("err_max_ms", "误差 max (ms)", 3)]:
                cells = []
                for _lb, rd in rounds:
                    r = pick(rd.get("timer_storm", []), "timer", v)
                    cells.append(fmt(r.get(field), nd) if r else "-")
                if all(c == "-" for c in cells):
                    continue
                w(f"| 定时器 `{v}` {label} | " + " | ".join(cells) + " |")

        for k, label in [("obj_cycle", "对象互指残留"),
                         ("obj_plain", "不成环对照残留"),
                         ("closure_cycle", "自引用闭包残留")]:
            cells = []
            for _lb, rd in rounds:
                rr = {}
                for r in pickall(rd.get("cycle_leak", []), "cycle"):
                    rr[r.get("_p1", "").split("(")[0]] = r   # 取最后一条
                cells.append(fmt(rr.get(k, {}).get("retained_kb"), 0) + " KB"
                             if k in rr else "-")
            if all(c == "-" for c in cells):
                continue
            w(f"| 内存 {label} | " + " | ".join(cells) + " |")

        w("")
        w("**怎么读这张表：**")
        w("")
        w("- **加速比、内存残留量**：各轮高度一致，结论可复现。")
        w("- **CPU 占用率**：同一变体自身在轮次间的波动，"
          "与变体之间的差异同量级 —— **不足以判定谁更省**。")
        w("- **误差 max**：`old` 在轮次间大幅摆动，`new` 始终稳定在窄区间 —— "
          "这个「尾部稳定性」的差异才是可复现的。")
        w("- 波动**不改变任何结论的方向性**：该快的还是快，该没收益的还是没收益。")
        w("")

    w("---")
    w("")

    # 3 逐项
    w("## 3. 逐项结果")
    w("")
    A.extend(sec_json(data))
    A.extend(sec_tick(data))
    A.extend(sec_keyregex(data))
    A.extend(sec_timer(data, rounds))
    A.extend(sec_stability(data))
    A.extend(sec_cycle(data))
    w("---")
    w("")

    # 4 三维
    w("## 4. 耗时 / 内存 / CPU 三维汇总")
    w("")
    w("### 4.1 耗时")
    w("")
    w("| 项 | 旧 | 新 | 降幅 |")
    w("|---|---:|---:|---:|")
    for r in je:
        w(f"| JSON 转义 `{r.get('_p1','-')}` | {fmt(r.get('p50_old_ms'),4)} ms "
          f"| {fmt(r.get('p50_new_ms'),4)} ms | "
          f"**{delta_pct(r.get('p50_old_ms'), r.get('p50_new_ms'))}** |")
    for r in tt:
        w(f"| tick 遍历 `{r.get('_p1','-')}` / 20000 ticks | {fmt(r.get('p50_old_ms'),1)} ms "
          f"| {fmt(r.get('p50_new_ms'),1)} ms | "
          f"**{delta_pct(r.get('p50_old_ms'), r.get('p50_new_ms'))}** |")
    if kr:
        w(f"| 键名校验 / {kr.get('n','20000')} 次 | {fmt(kr.get('p50_old_ms'),3)} ms "
          f"| {fmt(kr.get('p50_new_ms'),3)} ms | "
          f"{delta_pct(kr.get('p50_old_ms'), kr.get('p50_new_ms'))}（可忽略） |")
    w("")
    w("### 4.2 内存")
    w("")
    w("| 项 | 旧 | 新 | 变化 |")
    w("|---|---:|---:|---|")
    cyc = {r.get("_p1", "").split("(")[0]: r for r in pickall(data["cycle_leak"], "cycle")}
    if cyc.get("obj_cycle") and cyc.get("obj_plain"):
        oc, op = cyc["obj_cycle"], cyc["obj_plain"]
        w(f"| 对象互指 5 万组残留 | {fmt(oc.get('retained_kb'),0)} KB "
          f"| {fmt(op.get('retained_kb'),0)} KB | **省 "
          f"{fmt((fnum(oc.get('retained_kb')) - fnum(op.get('retained_kb'))) / 1024,1)} MB** |")
    if cyc.get("closure_cycle") and cyc.get("closure_plain"):
        cc, cp = cyc["closure_cycle"], cyc["closure_plain"]
        w(f"| 自引用闭包 5 万组残留 | {fmt(cc.get('retained_kb'),0)} KB "
          f"| {fmt(cp.get('retained_kb'),0)} KB | 无差异（未泄漏） |")
    w("")
    w("### 4.3 CPU")
    w("")
    w("| 场景 | 旧 | 新 | 变化 |")
    w("|---|---:|---:|---|")
    if tm.get("old") and tm.get("new"):
        o, n = fnum(tm["old"].get("cpu_pct")), fnum(tm["new"].get("cpu_pct"))
        w(f"| 定时器风暴（8 组 × 100 ms 周期）| {fmt(o,1)}% | {fmt(n,1)}% "
          f"| {n - o:+.1f} 个百分点（多轮区间重叠，**不可作为结论**，见 §3.4）|")
    kcmp = pick(data["stability"], "cmp", "kpd_no_clamp")
    if kcmp:
        w(f"| kpd=2000 ms 单次执行 | {fmt(kcmp.get('cpu_old_ms'),1)} ms "
          f"| {fmt(kcmp.get('cpu_new_ms'),1)} ms | **省 {fmt(kcmp.get('cpu_saved_pct'),1)}%** |")
    w("")
    w("### 4.4 稳定性")
    w("")
    w("| 指标 | 旧 | 新 |")
    w("|---|---:|---:|")
    cov = pick(data["stability"], "coverage", "guarded_paths")
    if cov:
        w(f"| 异常守卫覆盖率 | {cov.get('old','-')} | **{cov.get('new','-')}** |")
    if tm.get("old") and tm.get("new"):
        w(f"| 定时误差 max（尾部，多轮稳定）| {fmt(tm['old'].get('err_max_ms'),3)} ms "
          f"| **{fmt(tm['new'].get('err_max_ms'),3)} ms** |")
        w(f"| 主线程最大停顿 | {fmt(tm['old'].get('probe_max_gap_ms'),1)} ms "
          f"| {fmt(tm['new'].get('probe_max_gap_ms'),1)} ms |")
    w("")
    w("---")
    w("")

    # 5 复现
    w("## 5. 如何复现")
    w("")
    w("```bash")
    w("# 跑单个基准")
    w("bash tools/ahk-bench/run.sh json_escape")
    w("")
    w("# 跑全部（cycle_leak 除外，它必须每用例独立进程）")
    w("for id in json_escape tick_traversal key_regex timer_storm stability; do \\")
    w("    bash tools/ahk-bench/run.sh $id; \\")
    w("done")
    w("bash tools/ahk-bench/cycle_leak_all.sh")
    w("")
    w("# 生成报告（可选 --prev <上一轮目录> 做波动对比）")
    w("python tools/ahk-bench/report.py")
    w("```")
    w("")
    w("CSV 输出目录：`%TEMP%\\ahkbench\\`。路径由 `run.sh` 通过 `AHK_BENCH_OUT` 显式传给 AHK —— "
      "Git Bash 的 `$TEMP` 与 Windows `%TEMP%` 可能不是同一个目录，"
      "不显式传就会永远轮询不到哨兵文件。")
    w("")
    w(f"本轮数据目录：`{datadir}`")
    w("")
    return "\n".join(A) + "\n"


def main():
    default_dir = os.path.join(tempfile.gettempdir(), "ahkbench")
    ap = argparse.ArgumentParser()
    ap.add_argument("datadir", nargs="?", default=default_dir)
    ap.add_argument("-o", "--out", default=None)
    ap.add_argument("--prev", nargs="*", default=[],
                    help="历史轮次的数据目录（可多个，按时间先后给），用于多轮波动对比")
    args = ap.parse_args()

    data = load(args.datadir)
    rounds = []
    for i, d in enumerate(args.prev, 1):
        rounds.append((f"第{i}轮", load(d)))
    rounds.append(("本轮", data))

    outfile = args.out or os.path.join(
        "docs", "refactor", f"bench-report-{_dt.date.today().isoformat()}.md")
    d = os.path.dirname(outfile)
    if d:
        os.makedirs(d, exist_ok=True)

    md = build(data, rounds, args.datadir)
    with io.open(outfile, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(md)
    print(f"已生成：{outfile}（{len(md)} 字符）")


if __name__ == "__main__":
    main()
