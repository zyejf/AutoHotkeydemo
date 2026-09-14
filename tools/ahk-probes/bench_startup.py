# -*- coding: utf-8 -*-
"""
P1 / P8：启动 + 解析耗时基准（外部墙钟，非脚本内自报）。

为什么从外部测：脚本内拿不到「进程起点」，A_LineFile 首行的 QPC 已经晚于
引擎初始化与 LoadFromFile。进程墙钟才是用户感知的启动成本。

用法：
    python tools/ahk-probes/bench_startup.py [runs]
输出：
    %TEMP%\\ahkprobe\\p1_startup.csv 并打印到 stdout
"""
import os
import subprocess
import sys
import time

AHK = os.environ.get("AHK_BIN") or r"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
TEMP = os.environ.get("TEMP") or os.path.join(os.environ.get("LOCALAPPDATA", "."), "Temp")
OUT = os.path.join(TEMP, "ahkprobe")
FIX = os.path.join(OUT, "fixtures")
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 9

os.makedirs(OUT, exist_ok=True)

# (场景名, 夹具文件名)
CASES = [
    ("empty",            "f_empty.ahk"),
    ("parse_1k",         "f_1000_parse.ahk"),
    ("parse_5k",         "f_5000_parse.ahk"),
    ("parse_20k",        "f_20000_parse.ahk"),
    ("exec_1k",          "f_1000_exec.ahk"),
    ("exec_5k",          "f_5000_exec.ahk"),
    ("exec_20k",         "f_20000_exec.ahk"),
    ("inc_1000_x1",      "f_inc_1000_1.ahk"),
    ("inc_1000_x10",     "f_inc_1000_10.ahk"),
    ("inc_1000_x50",     "f_inc_1000_50.ahk"),
    ("inc_5000_x1",      "f_inc_5000_1.ahk"),
    ("inc_5000_x50",     "f_inc_5000_50.ahk"),
]


def pct(a, p):
    if not a:
        return 0.0
    s = sorted(a)
    i = max(1, min(len(s), -(-len(s) * int(p * 100) // 100)))
    return s[i - 1]


def run_one(path):
    t0 = time.perf_counter()
    subprocess.run([AHK, "/ErrorStdOut=UTF-8", path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    return (time.perf_counter() - t0) * 1000.0


rows = []
print(f"{'case':16s} {'min':>8s} {'p50':>8s} {'p95':>8s} {'max':>8s}  (ms, n=%d)" % RUNS)
for name, fn in CASES:
    p = os.path.join(FIX, fn)
    if not os.path.exists(p):
        print(f"{name:16s} MISSING {p}")
        continue
    # 预热 2 次（冷启动/磁盘缓存差异很大）
    run_one(p)
    run_one(p)
    samples = [run_one(p) for _ in range(RUNS)]
    rows.append((name, min(samples), pct(samples, 0.5), pct(samples, 0.95), max(samples)))
    print(f"{name:16s} {min(samples):8.2f} {pct(samples, 0.5):8.2f} "
          f"{pct(samples, 0.95):8.2f} {max(samples):8.2f}")

with open(os.path.join(OUT, "p1_startup.csv"), "w", encoding="utf-8", newline="\n") as f:
    f.write("# P1/P8 启动+解析耗时（外部墙钟 ms，已预热 2 次）\n")
    f.write(f"# AHK={AHK}\n")
    f.write("case,min_ms,p50_ms,p95_ms,max_ms,n\n")
    for r in rows:
        f.write("%s,%.3f,%.3f,%.3f,%.3f,%d\n" % (r[0], r[1], r[2], r[3], r[4], RUNS))

# 派生指标：斜率
base = dict((r[0], r[2]) for r in rows)
print("\n--- 派生指标（相对 empty 基线的增量）---")


def delta(k):
    return base.get(k, 0) - base.get("empty", 0)


if "parse_1k" in base and "parse_20k" in base:
    d_lines = 19000
    d_ms = base["parse_20k"] - base["parse_1k"]
    print(f"解析斜率        : {d_ms / d_lines * 1000:8.2f} us/行  (1k→20k)")
if "exec_1k" in base and "exec_20k" in base:
    d_lines = 19000
    d_ms = base["exec_20k"] - base["exec_1k"]
    print(f"执行斜率        : {d_ms / d_lines * 1000:8.2f} us/行  (1k→20k)")
for k in ("inc_1000_x1", "inc_1000_x10", "inc_1000_x50", "inc_5000_x1", "inc_5000_x50"):
    if k in base:
        print(f"{k:16s}: Δ={delta(k):8.2f} ms")
if "inc_1000_x1" in base and "inc_1000_x50" in base:
    print(f"#Include 边际成本: {(base['inc_1000_x50'] - base['inc_1000_x1']) / 49 * 1000:8.2f} us/文件")
