#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gate.py —— AHK 生产基准的 CI 门禁（T11）

判据（用户选定：**只设上界 + 多轮中位数**）：
    每个 metric 跑 R 轮（每轮一个独立 AHK 进程，进程内若干次采样取 p50），
    跨轮取 **p50 的中位数**，断言 `median <= baseline * K`。
    - 只设上界：**变快不会失败**，只有变慢超过 K 倍才失败 → 不会因优化而误报；
    - 多轮中位数：p50 已经滤掉单次离群，中位数再滤掉整轮异常（宿主抖动常整轮偏移）；
    - 不设绝对毫秒阈值，只用「相对基线」，以吸收不同机器的主频差异。

为什么用「生产基准」而不是 tools/ahk-bench 里既有的 bench_*.ahk：
    那些是选型期的**双实现对照**基准，old/new 两份实现都复刻在脚本内。
    T1/T6 落地后，脚本里的 new 侧是副本 —— 生产代码再改也不会跟着变，
    对生产回归**零防护力**。CI 门禁必须测真正的生产实现（bench_prod_*.ahk）。

基线自描述校验（基准侧的「阳性对照」）：
    CSV 里每个 metric 都带 `len=`（payload 实际长度）。若 payload 构造写错
    （比如生成了空串），耗时极低会永远 PASS 而无人察觉 —— 故 gate 会断言
    len 与基线一致；不匹配直接 FAIL。同理 `equiv,ascii_scan,diffs=` 必须为 0。

用法：
    python tools/ahk-bench/gate.py                        # 跑默认轮数，与基线比对
    python tools/ahk-bench/gate.py --rounds 5             # 多跑几轮
    python tools/ahk-bench/gate.py --update-baseline      # 重算并写回基线（人工确认后）
退出码：0 = PASS，1 = 回归/校验失败，2 = 运行期错误（AHK 缺失、超时等）
"""
from __future__ import annotations

import argparse
import io
import json
import os
import statistics
import subprocess
import sys
import tempfile
import time

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BASELINE = os.path.join(HERE, "baselines.json")
DEFAULT_AHK = r"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

# 每轮超时（秒）。prod_escape 单轮本机约 3 s，prod_tick 约 10 s，CI 机器更慢，给足余量。
ROUND_TIMEOUT = 300

# 单轮超时后的重试次数（TD-041）。只对「超时」重试，不对「回归判定」重试 ——
# 后者重试等于给回归第二次蒙混过关的机会。改大这个值前先想清楚这一点。
ROUND_ATTEMPTS = 2

# 「形态自描述」字段：基准自己声明它测的是什么规模/什么形状，门禁拿它跟基线比对。
#   len   —— payload 长度（prod_escape）
#   calls —— 每次采样内的调用数（prod_escape）
#   keys  —— 键数量（prod_tick）
#   sends —— 每 tick 实际发送次数（prod_tick；2 = 只有 1 个键到期，2n = 全部到期）
# 只要这些值变了，说明基准已经在测别的东西，此时与基线比耗时毫无意义。
SELF_DESC_FIELDS = ("len", "calls", "keys", "sends")


def _ahk_exe() -> str:
    exe = os.environ.get("AHK_EXE") or DEFAULT_AHK
    if not os.path.isfile(exe):
        print(f"[FATAL] 找不到 AutoHotkey v2：{exe}\n"
              f"        用 AHK_EXE 环境变量指定（CI 里由 install-autohotkey 提供）")
        sys.exit(2)
    return exe


def _run_round(ahk: str, bench: str, outdir: str) -> str:
    """跑一轮，返回 CSV 路径。等待 <bench>.done 哨兵（AHK 是 GUI 子进程，不能靠退出码）。"""
    os.makedirs(outdir, exist_ok=True)
    env = dict(os.environ)
    env["AHK_BENCH_OUT"] = outdir
    csv = os.path.join(outdir, bench + ".csv")
    done = os.path.join(outdir, bench + ".done")
    for p in (csv, done):
        if os.path.exists(p):
            os.remove(p)
    script = os.path.join(HERE, f"bench_{bench}.ahk")
    if not os.path.isfile(script):
        print(f"[FATAL] 无此基准脚本：{script}")
        sys.exit(2)
    # 超时重试（TD-041）：一轮跑满 ROUND_TIMEOUT 是**基础设施故障**，不是耗时结论。
    # 实测 2026-09-16 run 35159560198：prod_escape 第 1/3 轮正常完成后第 2 轮挂死 300s，
    # 重跑整轮即绿、三个 metric 全部 PASS —— 代码无回归。
    # 所以只重试「超时」，**绝不重试回归判定**；且重试必须打进输出，不能静默重试。
    attempts = ROUND_ATTEMPTS
    for attempt in range(1, attempts + 1):
        for p in (csv, done):
            if os.path.exists(p):
                os.remove(p)
        # 必须留住句柄：Popen 是非阻塞的，超时时若不起掉，挂住的 AHK 进程会一直留着，
        # 既占 CPU 又会污染后续轮次（乃至后续 job）的计时。
        proc = subprocess.Popen([ahk, "/ErrorStdOut=UTF-8", script],
                                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        waited = 0
        while not os.path.exists(done):
            time.sleep(0.3)
            waited += 0.3
            if waited >= ROUND_TIMEOUT:
                try:
                    proc.kill()
                except Exception:
                    pass
                if attempt < attempts:
                    print(f"[WARN] 基准 {bench} 第 {attempt}/{attempts} 次尝试超时 "
                          f"{ROUND_TIMEOUT}s（已终止挂起的 AHK 进程），重试一次 —— "
                          f"超时属基础设施故障，不计入耗时判定")
                    break
                print(f"[FATAL] 基准 {bench} 连续 {attempts} 次超时 {ROUND_TIMEOUT}s —— "
                      f"检查 {csv} 末尾有无 FATAL 行（也可能是 AHK 弹了模态错误框）")
                sys.exit(2)
        else:
            if attempt > 1:
                print(f"  基准 {bench} 第 {attempt} 次尝试成功（前一次超时）")
            return csv

    print(f"[FATAL] 基准 {bench} 未能产出结果")
    sys.exit(2)


def _read_rows(path: str) -> list[dict]:
    rows = []
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", errors="replace")
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(",")]
        rec = {"_tag": parts[0], "_p1": parts[1] if len(parts) > 1 else ""}
        for p in parts[1:]:
            if "=" in p:
                k, v = p.split("=", 1)
                rec[k.strip()] = v.strip()
        rows.append(rec)
    return rows


def _fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def collect(ahk: str, bench: str, rounds: int, workdir: str) -> dict:
    """返回 {metric: {"p50": [...], "len": int, "calls": int, ...}}"""
    acc: dict[str, dict] = {}
    equiv_bad = 0
    for r in range(1, rounds + 1):
        csv = _run_round(ahk, bench, os.path.join(workdir, f"r{r}"))
        rows = _read_rows(csv)
        for row in rows:
            if row["_tag"] == "FATAL":
                print(f"[FATAL] 基准内部错误：{row}")
                sys.exit(2)
            if row["_tag"] == "equiv":
                if _fnum(row.get("diffs")) not in (0, 0.0):
                    equiv_bad += 1
                continue
            if row["_tag"] != "metric":
                continue
            name = row["_p1"]
            p50 = _fnum(row.get("p50"))
            if p50 is None:
                continue
            d = acc.setdefault(name, {"p50": []})
            for f in SELF_DESC_FIELDS:
                v = _fnum(row.get(f))
                if v is not None and f not in d:
                    d[f] = int(v)
            d["p50"].append(p50)
        print(f"  第 {r}/{rounds} 轮完成", flush=True)
    if equiv_bad:
        print(f"[FAIL] 等价性自校验 diffs != 0（{equiv_bad} 处）—— "
              f"被测实现与对照实现不等价，属正确性回归（不只是变慢）")
        sys.exit(1)
    return acc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", default="prod_escape")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--baseline", default=DEFAULT_BASELINE)
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--k", type=float, default=None, help="覆盖基线里的 K（调试用）")
    args = ap.parse_args()

    ahk = _ahk_exe()
    print(f"基准门禁：bench={args.bench} 轮数={args.rounds} AHK={ahk}", flush=True)

    workdir = os.path.join(tempfile.gettempdir(), f"ahkgate-{args.bench}")
    acc = collect(ahk, args.bench, args.rounds, workdir)

    if not acc:
        print("[FATAL] 没有收集到任何 metric —— 基准脚本可能没跑起来")
        return 2

    # ---- 汇总
    summary = {}
    for name, d in acc.items():
        rec = {"median": statistics.median(d["p50"]),
               "min": min(d["p50"]), "max": max(d["p50"])}
        for f in SELF_DESC_FIELDS:
            if f in d:
                rec[f] = d[f]
        summary[name] = rec

    base = {}
    if os.path.isfile(args.baseline):
        base = json.load(io.open(args.baseline, encoding="utf-8"))
    b = base.get(args.bench, {})
    k = args.k if args.k is not None else float(b.get("k", 2.0))
    warn_k = float(b.get("warn_k", 1.15))
    old = b.get("metrics", {})

    print("")
    # ⚠️ p50 的单位由基准自己定：prod_escape 是毫秒，prod_tick 是**归一化后的无量纲比值**
    print(f"| metric | 基线 p50 | 本轮中位数 | 跨轮范围 | 相对基线 | 判定 |")
    print("|---|---:|---:|---:|---:|:--:|")
    failed, warned = [], []
    for name in sorted(summary):
        s = summary[name]
        o = old.get(name, {})
        o_p50 = _fnum(o.get("p50_ms"))
        # 基线自描述校验：形态/规模必须与基线一致，否则基准已经在测别的东西
        mism = [f for f in SELF_DESC_FIELDS
                if o.get(f) is not None and s.get(f) is not None
                and int(o[f]) != int(s[f])]
        if mism:
            detail = "；".join(f"{f} 基线 {o[f]} != 本轮 {s[f]}" for f in mism)
            print(f"| `{name}` | {o_p50} | {s['median']:.4f} | "
                  f"{s['min']:.4f}~{s['max']:.4f} | — | **形态不匹配** |")
            failed.append(f"{name}: {detail}（基准形态变了，耗时不再可比）")
            continue
        if o_p50 is None:
            print(f"| `{name}` | — | {s['median']:.4f} | {s['min']:.4f}~{s['max']:.4f} "
                  f"| — | 新指标（无基线） |")
            continue
        ratio = s["median"] / o_p50
        if ratio > k:
            verdict = "**FAIL**"
            failed.append(f"{name}: 中位数 {s['median']:.4f} ms = 基线的 {ratio:.2f}×"
                          f" ＞ 阈值 {k}×")
        elif ratio > warn_k:
            verdict = "WARN"
            warned.append(f"{name}: 基线的 {ratio:.2f}×（>{warn_k}× 但 ≤{k}×，不阻断）")
        else:
            verdict = "PASS"
        print(f"| `{name}` | {o_p50:.4f} | {s['median']:.4f} | "
              f"{s['min']:.4f}~{s['max']:.4f} | {ratio:.2f}× | {verdict} |")
    print("")
    if warned:
        print("[WARN] 有指标进入警告带（可能是真实劣化，也可能是机器差异）：")
        for w in warned:
            print(f"  - {w}")
        print("")

    if args.update_baseline:
        base[args.bench] = {
            "_comment": ("由 gate.py --update-baseline 生成。p50_ms 为多轮中位数；"
                         "len/calls/keys/sends 是基准形态自描述，"
                         "用于校验基准没在测别的东西。"),
            "k": k,
            "warn_k": warn_k,
            "metrics": {n: dict({"p50_ms": round(s["median"], 6)},
                                **{f: s[f] for f in SELF_DESC_FIELDS if f in s})
                        for n, s in summary.items()},
        }
        with io.open(args.baseline, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(base, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print(f"已写入基线：{args.baseline}（bench={args.bench}, k={k}）")
        return 0

    if failed:
        print("[FAIL] 性能回归：")
        for f in failed:
            print(f"  - {f}")
        print("\n提示：CI 机器负载不可控，偶发超阈请先本地复跑确认，"
              "确认是真实回归再修；确属噪音则用 --update-baseline 重设基线。")
        return 1

    print("[PASS] 全部 metric 在上界内")
    return 0


if __name__ == "__main__":
    sys.exit(main())
