#!/usr/bin/env python3
"""覆盖率门禁（TD-006）：三个纯逻辑 crate 的**行覆盖率**不得低于基线。

用法：
    python scripts/check-coverage.py --lcov coverage/lcov.info
    python scripts/check-coverage.py --lcov ... --show              # 只看现状
    python scripts/check-coverage.py --lcov ... --update-baseline   # 收紧水位

## 为什么是棘轮，而不是「覆盖率 ≥ 80%」

凭空定的目标只有两种下场：要么一上线就红（于是大家用 `#[cfg(test)]` 造假、
加无断言的「跑一遍就算覆盖」测试把数字刷上去），要么低到形同虚设。
两种都比没有门禁更糟 —— 它们会**污染覆盖率这个指标本身的可信度**。

棘轮只保证一件事：**不会比昨天更差**。基线取实测值，只允许上升
（容差内允许小回落）。想提高覆盖率就补测试，补完 `--update-baseline` 钉住新水位。

## 为什么行覆盖率（Lines）而不是 Regions / Functions

- Regions 最灵敏，但对「同一个表达式拆成几段」这种纯格式改动也会跳，噪声大；
- Functions 太粗，一个函数里 200 行只覆盖 3 行也算「已覆盖」；
- **Lines 是三者里最稳、也最符合直觉的**，且与 IDE 显示一致，便于人工核对。

## 两个阈值

- **整体**：低于 `基线 - global_pp` → FAIL。防「总体稀释」（A 文件掉 20% 被 B 文件涨
  5% 盖过去，整体还是涨的，但 A 实际上烂掉了）。
- **单文件**：低于 `基线 - file_pp` → FAIL。防「丢车保帅」。
  容差比整体宽，因为小文件天然波动大（15 行的文件改 1 行就是 6.7pp）。

## 为什么基线要存「行数」而不只是百分比（口径漂移检测）

2026-09-16 实测：同一份代码，换一条 llvm-cov 命令后 `validator.rs` 的统计行数从
2367 变成 1856（-21.6%），命中数几乎没变，于是整体覆盖率「涨」了 7pp ——
**这不是覆盖率提升，是量程变了**。旧基线只存百分比，这种漂移完全看不出来，
棘轮就会拿两个不可比的数字互相比，等于把门禁变成随机数。

所以基线现在存每个文件的 `lines` / `hits`：任一文件统计行数变化超过
`SCALE_FILE_PCT`（10%）且绝对变化 ≥ `SCALE_MIN_LINES`（20 行）时，
判定为**口径漂移**并 FAIL —— 逼人看一眼是不是换命令/换平台了，
确认后再 `--update-baseline`。宁可多一次人工确认，也不要一个悄悄失效的门禁。

新出现的文件**只登记不判**（棘轮精神：新代码第一次不背历史包袱，
第二次起就有基线了），但会在输出里标出来。

## 漂移检测要能区分「换尺子」和「真的改了代码」（TD-007 实测修正）

2026-09-16 给 `asd-domain/src/traits.rs` 补 11 个用例后，该文件的统计行数
15 -> 146（+873%），漂移检测直接 FAIL —— 但这**不是换尺子，是我真的加了
131 行代码**，而且这些行几乎全被执行了。若不区分，后果是：以后每次补测试都会
撞到一个红色 FAIL，人会养成「无脑 `--update-baseline`」的习惯，棘轮就此失效
（和随便 `--update` 图谱基线下场一样）。

区分依据是**命中数是否与行数同向变化**：
- 换尺子（换命令/换平台）：代码没变 → 命中数几乎不动，只有行数剧变
  （实测 `validator.rs` 2367 -> 1856 时命中数只变了 1）。
- 真实改动：新增/删除的代码绝大多数会被执行 → 命中数与行数同步变化。

所以只有 `|Δhits| / |Δlines| < SCALE_NEW_HIT_RATIO` 时才判漂移。

## ⚠️ 已知口径缺陷：分母里含 `#[cfg(test)]` 测试代码（未修，TD-007 记录）

cargo-llvm-cov 测的是**测试二进制**，所以 `src/*.rs` 里的 `#[cfg(test)] mod tests`
会一并进分母。实测占比（`td007` 统计，总行口径）：

    time_format.rs 83.9% / traits.rs 77.9% / validator.rs 60.9% / config.rs 58.0%
    state.rs 51.7% ... 而 group_service.rs、recording_service.rs、backup_service.rs 是 0%

也就是说：**跨文件的百分比不可比**（同一个 90%，可能指「生产代码覆盖 90%」，
也可能指「其中六成是测试代码」），且「往文件里加测试」本身会抬高该文件的百分比。
`最低的 5 个文件` 只能当**同文件纵向趋势**看，不能当横向排名。

为什么没顺手修掉（两条路都实测堵死，别重复踩）：
1. `#[coverage(off)]` 标记的官方方案 —— rustc 1.95.0 上仍是实验特性
   （`error[E0658]: the #[coverage] attribute is an experimental feature`），
   CI 用 stable，不可用。
2. 按源码定位 `#[cfg(test)]` 区间后在 lcov 里逐行剔除 —— 不可行：llvm-cov 的
   `LF`（行数）与逐行 `DA` 记录**并不是一套口径**，实测 15 个文件里 10 个不一致
   （`validator.rs` LF 1856 / DA 1805，差 51；`config.rs` 704 / 682）。
   按行剔除等于又引入一层新的口径误差，比现在更难解释。

要保持这个口径，就必须**始终用同一条命令**取数（见 developer-guide §4.6.1.2）。
想看某个文件的**生产代码**覆盖率，只能人工按行核对（该文件的 LF 与 DA 一致时方可）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# Windows CI 上 cp1252 会把中文输出打崩，与 check-tech-debt.py 同样处理
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

REPO_ROOT = Path(__file__).resolve().parent.parent
BASELINE = REPO_ROOT / ".review-analysis" / "coverage-baseline.json"
DEFAULT_LCOV = REPO_ROOT / "coverage" / "lcov.info"

# 容差（百分点）。整体从严，单文件从宽 —— 理由见模块 docstring。
DEFAULT_TOL_GLOBAL_PP = 0.5
DEFAULT_TOL_FILE_PP = 2.0

# 口径漂移判定：单文件统计行数变化超过此比例 **且** 绝对变化 ≥ SCALE_MIN_LINES。
# 加绝对量是为了不让 15 行的小文件（traits.rs）动一行就报警。
SCALE_FILE_PCT = 10.0
SCALE_MIN_LINES = 20

# 行数剧变时，用「命中数是否跟着变」区分真实改动与换尺子：
# 比值 >= 此阈值 → 判定为真实的代码增减（多半是补测试），只提示不 FAIL。
# 见模块 docstring「漂移检测要能区分『换尺子』和『真的改了代码』」。
SCALE_NEW_HIT_RATIO = 0.5

# lcov 的 SF 在不同平台都是**绝对路径**（本机 D:\...、CI /home/runner/...），
# 必须归一化成「crate 相对路径」才能跨平台比基线。
CRATE_REL_RE = re.compile(r"(asd-[a-z0-9-]+)[\\/](src[\\/].*)$")


def normalize_path(raw: str) -> str:
    """把 lcov 的绝对 SF 路径归一化成 `<crate>/src/...`（posix 分隔）。"""
    p = raw.strip().replace("\\", "/")
    m = CRATE_REL_RE.search(p)
    if m:
        return f"{m.group(1)}/{m.group(2)}"
    # 兜底：取最后三段，至少让 `xxx/src/foo.rs` 这种形态稳定
    parts = [x for x in p.split("/") if x]
    return "/".join(parts[-3:]) if len(parts) >= 3 else p


def parse_lcov(path: Path) -> dict[str, dict[str, int]]:
    """解析 lcov，返回 {文件: {"lines": 总行, "hits": 命中行}}。

    lcov 字段很多，门禁只需要 LF（Lines Found）/ LH（Lines Hit）。
    ⚠️ 不要改用 `DA:` 逐行统计：一个文件里若混有未被 llvm 视为可执行的行
    （宏展开、编译器生成的 glue），两边口径会不一致，白给自己找麻烦。
    """
    out: dict[str, dict[str, int]] = {}
    cur: str | None = None
    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("SF:"):
                cur = normalize_path(line[3:])
                out.setdefault(cur, {"lines": 0, "hits": 0})
            elif cur is None:
                continue
            elif line.startswith("LF:"):
                out[cur]["lines"] = int(line[3:] or 0)
            elif line.startswith("LH:"):
                out[cur]["hits"] = int(line[3:] or 0)
            elif line == "end_of_record":
                cur = None
    return {k: v for k, v in out.items() if v["lines"] > 0}


def pct(hits: int, total: int) -> float:
    return round(hits * 100.0 / total, 2) if total else 0.0


def summarize(files: dict[str, dict[str, int]]) -> tuple[float, dict[str, float], int, int]:
    total_lines = sum(v["lines"] for v in files.values())
    total_hits = sum(v["hits"] for v in files.values())
    per_file = {k: pct(v["hits"], v["lines"]) for k, v in files.items()}
    return pct(total_hits, total_lines), per_file, total_lines, total_hits


def main() -> int:
    ap = argparse.ArgumentParser(
        description="覆盖率门禁（棘轮）：三个纯逻辑 crate 的行覆盖率不得低于基线"
    )
    ap.add_argument("--lcov", default=str(DEFAULT_LCOV), help="lcov 文件路径")
    ap.add_argument("--baseline", default=str(BASELINE),
                    help="基线路径（默认 .review-analysis/coverage-baseline.json）。"
                         "给一个副本就能安全地做漂移检测的阳性对照，不用动真基线")
    ap.add_argument("--update-baseline", action="store_true", help="把当前结果冻结为新基线")
    ap.add_argument("--show", action="store_true", help="只打印当前结果，不与基线比对")
    ap.add_argument("--allow-scope-shrink", action="store_true",
                    help="显式确认「语料范围缩小」（本次文件数少于基线记录的下限）。"
                         "默认拒绝：缩小范围会让覆盖率数字因分母变小而虚高，是假信号")
    ap.add_argument("--tolerance-global", type=float, default=DEFAULT_TOL_GLOBAL_PP,
                    help=f"整体容差（百分点，默认 {DEFAULT_TOL_GLOBAL_PP}）")
    ap.add_argument("--tolerance-file", type=float, default=DEFAULT_TOL_FILE_PP,
                    help=f"单文件容差（百分点，默认 {DEFAULT_TOL_FILE_PP}）")
    args = ap.parse_args()

    lcov = Path(args.lcov)
    print("=" * 60)
    print("覆盖率门禁（棘轮）：asd-domain / asd-ipc-protocol / asd-application")
    print("=" * 60)

    if not lcov.exists():
        print(f"[FAIL] 找不到 lcov 文件：{lcov}")
        print("       先在 asd-tauri/ 下生成：")
        print("       cargo llvm-cov --package asd-domain --package asd-ipc-protocol \\")
        print("           --package asd-application --lcov --output-path coverage/lcov.info")
        return 1

    baseline = Path(args.baseline)
    files = parse_lcov(lcov)
    if not files:
        print(f"[FAIL] {lcov} 里没有任何文件记录（LF>0）—— 覆盖率数据为空")
        return 1

    g_pct, per_file, total_lines, total_hits = summarize(files)
    print(f"语料 {len(files)} 个文件 / {total_lines} 行，命中 {total_hits} 行")
    print(f"整体行覆盖率：**{g_pct:.2f}%**\n")

    cur = {
        "global_lines_pct": g_pct,
        # 每个文件存 {pct, lines, hits}：行数用于口径漂移检测（见模块 docstring）。
        # 旧格式（只存百分比的 float）仍能读，只是跳过漂移检测。
        "files": {
            k: {"pct": per_file[k], "lines": files[k]["lines"], "hits": files[k]["hits"]}
            for k in sorted(per_file)
        },
        "totals": {"lines": total_lines, "hits": total_hits, "files": len(files)},
        "tolerance": {
            "global_pp": args.tolerance_global,
            "file_pp": args.tolerance_file,
        },
    }

    if args.update_baseline:
        baseline.parent.mkdir(parents=True, exist_ok=True)
        # ---- 范围锚点（TD-058 ①）：语料文件数只增不减，缩小须显式确认 ----
        # 只有「基线里有本次没有」那一条（见下方差集检查）挡不住「反复 update 把范围
        # 一点点缩掉」：每次缩一点、每次 update 一次，基线跟着变小，就再也报不出来了。
        # 所以下限必须**独立于基线的 files 字典**持久化，且不随 update 自动下调。
        old_min = 0
        if baseline.exists():
            try:
                old_min = int(
                    (json.loads(baseline.read_text(encoding="utf-8")) or {}).get("min_files", 0) or 0
                )
            except (OSError, ValueError, TypeError):
                old_min = 0
        n_now = len(files)
        if old_min and n_now < old_min:
            if not args.allow_scope_shrink:
                print(f"[FAIL] 语料范围缩小：本次 {n_now} 个文件 < 基线记录的下限 {old_min} 个。")
                print("       缩小范围会让覆盖率因**分母变小**而虚高 —— 这是假信号，不是提升。")
                print("       若确属有意（如删除了源码文件），显式确认后重跑：")
                print("       python scripts/check-coverage.py --lcov <path> "
                      "--update-baseline --allow-scope-shrink")
                return 1
            print(f"[WARN] 已显式确认语料范围缩小：下限 {old_min} -> {n_now} 个文件")
            min_files = n_now          # 已显式确认：下限真的下调，别再被 max() 拉回去
        else:
            min_files = max(old_min, n_now)
        payload = {
            "_comment": (
                "覆盖率基线（scripts/check-coverage.py 生成，TD-006）。"
                "棘轮：只允许上升，容差内的小回落不报。整体容差 "
                f"{args.tolerance_global}pp，单文件 {args.tolerance_file}pp。"
                "files 里的 lines/hits 是**口径指纹**：换 llvm-cov 命令或换平台都可能改变统计行数，"
                "届时百分比不可比，脚本会判定为口径漂移并要求重取基线。"
                "⚠️ 重取基线必须用**同一条命令**（见 developer-guide §4.6.1.2），否则等于换量程。"
            ),
            "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            # 范围锚点：语料文件数的历史最高水位。只增不减，缩小须 --allow-scope-shrink。
            "min_files": min_files,
            **cur,
        }
        with baseline.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"OK: 基线已写入 -> {baseline}")
        return 0

    if not baseline.exists():
        print("[WARN] 尚无基线，本次只打印现状（生成基线加 --update-baseline）：")
        for k, v in sorted(per_file.items(), key=lambda kv: kv[1]):
            print(f"       {v:6.2f}%  {k}")
        return 0

    base = json.loads(baseline.read_text(encoding="utf-8"))
    tol_g = float(base.get("tolerance", {}).get("global_pp", args.tolerance_global))
    tol_f = float(base.get("tolerance", {}).get("file_pp", args.tolerance_file))
    base_g = float(base["global_lines_pct"])
    base_files: dict[str, float] = base.get("files", {})

    errors: list[str] = []
    improved: list[str] = []
    new_files: list[str] = []
    scale: list[str] = []
    real_change: list[str] = []

    # ---- 整体 ----
    delta_g = round(g_pct - base_g, 2)
    if delta_g > 0:
        improved.append(f"整体 {base_g:.2f}% -> {g_pct:.2f}% (+{delta_g:.2f}pp)")
    elif g_pct < base_g - tol_g:
        errors.append(
            f"整体行覆盖率 {g_pct:.2f}% 低于基线 {base_g:.2f}% "
            f"（跌 {abs(delta_g):.2f}pp > 容差 {tol_g}pp）"
        )

    # ---- 单文件 ----
    for k, v in sorted(per_file.items(), key=lambda kv: kv[1]):
        if k not in base_files:
            new_files.append(f"{k}（{v:.2f}%，首次登记）")
            continue
        b_raw = base_files[k]
        b_lines = 0
        b_hits = None
        if isinstance(b_raw, dict):
            b = float(b_raw.get("pct", 0.0))
            b_lines = int(b_raw.get("lines", 0) or 0)
            if "hits" in b_raw:
                b_hits = int(b_raw["hits"] or 0)
        else:
            # 旧格式：只有百分比，无法做口径漂移检测
            b = float(b_raw)

        # ---- 口径漂移：统计行数变了，百分比就不可比 ----
        # 但「行数剧变」有两种截然不同的成因，必须分开（见模块 docstring）：
        #   a) 换尺子（换命令/换平台）：代码没变 -> 命中数几乎不动，只有行数动；
        #   b) 真的改了代码（典型是补测试）：新增的行大多会被执行 -> 命中数同步变。
        # 只有 (a) 才需要人确认。把 (b) 也报成 FAIL，会训练出「无脑 --update-baseline」。
        cur_lines = files[k]["lines"]
        if b_lines > 0:
            d_lines = cur_lines - b_lines
            if abs(d_lines) >= SCALE_MIN_LINES and abs(d_lines) * 100.0 / b_lines > SCALE_FILE_PCT:
                msg = (f"{k} 统计行数 {b_lines} -> {cur_lines}（{d_lines:+d}，"
                       f"{d_lines * 100.0 / b_lines:+.1f}%）")
                if b_hits is None:
                    # 旧基线没记命中数，无从区分 -> 保守按换尺子处理
                    scale.append(msg + "（旧基线无 hits 字段，无法判定是否真实改动）")
                else:
                    d_hits = files[k]["hits"] - b_hits
                    ratio = abs(d_hits) / abs(d_lines) if d_lines else 0.0
                    if ratio >= SCALE_NEW_HIT_RATIO:
                        real_change.append(
                            msg + f"，命中数同步变化 {b_hits} -> {files[k]['hits']}"
                                  f"（|Δhits/Δlines|={ratio:.2f}）—— 判定为真实代码增减"
                        )
                    else:
                        scale.append(
                            msg + f"，但命中数几乎没变 {b_hits} -> {files[k]['hits']}"
                                  f"（|Δhits/Δlines|={ratio:.2f} < {SCALE_NEW_HIT_RATIO}）"
                                  "—— 典型换尺子特征"
                        )

        d = round(v - b, 2)
        if d > 0:
            improved.append(f"{k} {b:.2f}% -> {v:.2f}% (+{d:.2f}pp)")
        elif v < b - tol_f:
            errors.append(
                f"{k} 行覆盖率 {v:.2f}% 低于基线 {b:.2f}% "
                f"（跌 {abs(d):.2f}pp > 容差 {tol_f}pp）"
            )

    # ---- 基线里有、本次没有的文件（被删/被改名）----
    for k in sorted(set(base_files) - set(per_file)):
        errors.append(f"{k} 在基线里但本次 lcov 没有 —— 被删除、改名或未纳入测量")

    # ---- 范围锚点（TD-058 ①）：语料文件数不得低于历史最高水位 ----
    # 上面那条差集检查看的是「具体哪个文件没了」；这条看的是「整体规模有没有缩水」。
    # 两者互补：只靠差集，一次次的 --update-baseline 能把范围悄悄缩掉且不再报错。
    min_files = int(base.get("min_files", 0) or 0)
    if min_files and len(per_file) < min_files:
        errors.append(
            f"语料范围缩小：本次 {len(per_file)} 个文件 < 基线记录的下限 {min_files} 个"
            " —— 缩小范围会让覆盖率因**分母变小**而虚高（假信号，不是提升）；"
            "若属有意，先排查是不是 `--package` 列表被改小或测量命令变了"
        )

    if new_files:
        print("[NEW] 以下文件首次出现，本次只登记不判：")
        for x in new_files:
            print(f"       - {x}")
        print()
    if improved:
        print(f"[UP] 较基线提升 {len(improved)} 项：")
        for x in improved[:15]:
            print(f"       - {x}")
        if len(improved) > 15:
            print(f"       ... 另 {len(improved) - 15} 项")
        print()

    print("最低的 5 个文件（改进优先级）：")
    for k, v in sorted(per_file.items(), key=lambda kv: kv[1])[:5]:
        print(f"       {v:6.2f}%  {k}")
    print("  ⚠️ 分母含 `#[cfg(test)]` 测试代码且各文件占比 0~84% 不等，"
          "此表**只能看同文件的纵向趋势，不能当横向排名**（见模块 docstring）。")
    print()

    if real_change:
        print(f"[NOTE] {len(real_change)} 个文件统计行数大幅变化，但命中数同步变化"
              " —— 判定为真实代码增减（多半是补测试），不算口径漂移：")
        for x in real_change:
            print(f"       - {x}")
        print()

    if args.show:
        print("[SKIP] --show：不做通过/失败判定")
        return 0

    # ---- 口径漂移优先于一切：数字不可比时，判定通过/失败都没有意义 ----
    if scale:
        print("[FAIL] 统计口径漂移：以下文件的**统计行数**发生大幅变化，"
              "百分比已不可比：")
        for x in scale:
            print(f"  - {x}")
        print("\n  判据：行数剧变而**命中数几乎不动** —— 说明代码没变、是尺子变了。")
        print("  常见原因：换了 cargo llvm-cov 的命令（--workspace 与 -p 的"
              "结果不同）、换了平台（Windows / ubuntu 的 cfg 分支不同）。")
        print("  （行数与命中数**同步**变化的，已在上面的 [NOTE] 里记为真实改动，不在此列。）")
        print("  ⚠️ 不要用 --update-baseline 把「量程变小」当成「覆盖率提升」记进台账。")
        print("     确认是真实改动后：")
        print("       python scripts/check-coverage.py --lcov <path> --update-baseline")
        return 1

    if errors:
        print("[FAIL] 覆盖率门禁未通过:")
        for e in errors:
            print(f"  - {e}")
        print("\n  若是**有意**删代码/补测试后覆盖率上升：")
        print("    python scripts/check-coverage.py --lcov <path> --update-baseline")
        return 1

    print(f"[PASS] 覆盖率门禁通过：整体 {g_pct:.2f}%（基线 {base_g:.2f}%，"
          f"容差 {tol_g}pp），单文件均未跌破容差")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
