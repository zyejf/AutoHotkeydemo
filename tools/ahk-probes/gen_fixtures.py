# -*- coding: utf-8 -*-
"""
生成 P1/P8 用的脚本夹具（全部落在 %TEMP%，不污染仓库）。

设计要点：
  - 把「解析耗时」和「执行耗时」分开：
      *_parse.ahk : N 行语句放在**从不调用**的函数体内 → 只付解析钱，不付执行钱
      *_exec.ahk  : N 行语句放在 auto-exec 段 → 解析 + 执行都付
  - include 组保持**总行数相同**，只改文件数，用于测 #Include 的边际成本
"""
import os
import shutil

TEMP = os.environ.get("TEMP") or os.path.join(os.environ.get("LOCALAPPDATA", "."), "Temp")
FIX = os.path.join(TEMP, "ahkprobe", "fixtures")

if os.path.isdir(FIX):
    shutil.rmtree(FIX)
os.makedirs(FIX, exist_ok=True)


def w(name, text):
    with open(os.path.join(FIX, name), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(text)


def body(n, indent="    "):
    return "".join(f"{indent}acc := acc + 1\n" for _ in range(n))


# ---- 1. 空脚本（基线：纯进程启动 + 引擎初始化） -----------------------------
w("f_empty.ahk", "ExitApp\n")

# ---- 2. 解析 vs 执行，各规模 ------------------------------------------------
for n in (1000, 5000, 20000):
    # 只解析：函数从不调用
    w(f"f_{n}_parse.ahk",
      "NoCall()\n"
      "ExitApp\n"
      "NoCall() {\n"
      "    acc := 0\n"
      f"{body(n)}"
      "    return acc\n"
      "}\n")
    # 解析 + 执行
    w(f"f_{n}_exec.ahk",
      "acc := 0\n"
      f"{body(n, indent='')}"
      "ExitApp\n")

# ---- 3. include 组：总行数相同，文件数不同 ---------------------------------
# 1000 行：1 文件 / 10 文件（每个 100 行）/ 50 文件（每个 20 行）
for total, files in ((1000, 10), (1000, 50), (5000, 50)):
    per = total // files
    libdir = os.path.join(FIX, f"lib_{total}_{files}")
    os.makedirs(libdir, exist_ok=True)
    incs = []
    for i in range(files):
        libname = f"m{i:03d}.ahk"
        with open(os.path.join(libdir, libname), "w", encoding="utf-8", newline="\r\n") as f:
            f.write(f"F{i:03d}() {{\n    acc := 0\n{body(per)}    return acc\n}}\n")
        incs.append(f'#Include "{libdir}\\{libname}"\n')
    w(f"f_inc_{total}_{files}.ahk", "".join(incs) + "ExitApp\n")

# 单文件对照（同总行数，1 个文件）
for total in (1000, 5000):
    w(f"f_inc_{total}_1.ahk",
      "F000() {\n    acc := 0\n" + body(total) + "    return acc\n}\nExitApp\n")

print("fixtures ->", FIX)
for f in sorted(os.listdir(FIX)):
    p = os.path.join(FIX, f)
    if os.path.isfile(p):
        print(f"  {f:24s} {os.path.getsize(p):>9,d} B")
