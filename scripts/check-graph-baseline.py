#!/usr/bin/env python3
"""闸门①：图谱基线校验。

运行 `build_graph.py` 生成最新图谱，与 `.review-analysis/graph-baseline.json` 比对。

策略（与基线文件的 policy 段一致）：
  - 硬失败：环数增加、未解析 include 增加、出现白名单外的新依赖违规
  - 仅警告：文件数/边数变化、孤点数变化

用法：
    python scripts/check-graph-baseline.py            # 重建图谱后比对
    python scripts/check-graph-baseline.py --no-rebuild  # 直接用现有 graph-raw.json
    python scripts/check-graph-baseline.py --update   # 把当前结果写回基线（需人工确认后提交）
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Windows CI runner 上 stdio 默认走系统 ANSI 代码页（cp1252），print 中文会
# UnicodeEncodeError。显式切 UTF-8；本地若已是 UTF-8 则无副作用。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

REPO_ROOT = Path(__file__).resolve().parent.parent
GRAPH_RAW = REPO_ROOT / ".review-analysis" / "graph-raw.json"
BASELINE = REPO_ROOT / ".review-analysis" / "graph-baseline.json"
BUILD_GRAPH = REPO_ROOT / ".review-analysis" / "build_graph.py"

# 硬失败项：当前值 > 基线值 即失败
HARD_FAIL_GREATER = ["ahk_cycles", "rust_crate_cycles", "ahk_missing"]


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def rebuild_graph() -> None:
    proc = subprocess.run(
        [sys.executable, str(BUILD_GRAPH)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit("ERROR: build_graph.py 执行失败，闸门① 无法继续")


def violation_key(item: dict) -> tuple[str, str]:
    return (item.get("from", ""), item.get("to", ""))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-rebuild", action="store_true", help="跳过重建图谱")
    parser.add_argument("--update", action="store_true", help="将当前结果写回基线文件")
    args = parser.parse_args()

    if not args.no_rebuild:
        rebuild_graph()

    if not GRAPH_RAW.exists():
        raise SystemExit(f"ERROR: 找不到图谱文件 {GRAPH_RAW}")
    if not BASELINE.exists():
        raise SystemExit(f"ERROR: 找不到基线文件 {BASELINE}")

    raw = load_json(GRAPH_RAW)
    baseline = load_json(BASELINE)

    cur_counts: dict = raw.get("meta", {}).get("counts", {})
    base_counts: dict = baseline.get("counts", {})
    findings: dict = raw.get("findings", {})

    if args.update:
        baseline["counts"] = {
            k: cur_counts.get(k, base_counts.get(k)) for k in base_counts
        }
        allowed = [
            {"from": v["from"], "to": v["to"], "reason": v.get("reason", "")}
            for v in findings.get("rust_crate_violations", [])
        ]
        baseline["allowed_violations"] = allowed
        with BASELINE.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(baseline, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"OK: 基线已更新 -> {BASELINE.relative_to(REPO_ROOT)}")
        print("    请复核 diff 后提交（可能掩盖真实回归，务必人工确认）")
        return 0

    errors: list[str] = []
    warnings: list[str] = []

    # 1) 硬失败：数值只增不减
    for key in HARD_FAIL_GREATER:
        cur = cur_counts.get(key, 0)
        base = base_counts.get(key, 0)
        if cur > base:
            errors.append(f"{key}: {base} -> {cur}（增加 {cur - base}）")

    # 2) 硬失败：白名单外的新依赖违规
    allowed = {
        (v["from"], v["to"]) for v in baseline.get("allowed_violations", [])
    }
    cur_violations = findings.get("rust_crate_violations", [])
    for item in cur_violations:
        if violation_key(item) not in allowed:
            errors.append(
                f"新增依赖违规 {item.get('from')} -> {item.get('to')}"
                f"（不在白名单；若为有意新增请同步 ALLOWED_CRATE_DEPS 与基线）"
            )

    # 3) 仅警告：结构与规模变化
    for key in sorted(set(base_counts) | set(cur_counts)):
        if key in HARD_FAIL_GREATER or key in ("rust_crate_violations",):
            continue
        cur, base = cur_counts.get(key, 0), base_counts.get(key, 0)
        if cur != base:
            warnings.append(f"{key}: {base} -> {cur}")

    # 4) 环的具体路径（有则输出，帮助定位）
    for name in ("ahk_cycles", "rust_crate_cycles"):
        cycles = findings.get(name, [])
        if cycles:
            errors.append(f"{name} 明细: {json.dumps(cycles, ensure_ascii=False)}")

    print("=" * 60)
    print("闸门① 图谱基线校验")
    print("=" * 60)
    print(
        f"  AHK   {cur_counts.get('ahk_files')} 文件 / "
        f"{cur_counts.get('ahk_edges_total')} 边 / "
        f"{cur_counts.get('ahk_cycles')} 环 / "
        f"{cur_counts.get('ahk_orphans')} 孤点 / "
        f"未解析 include {cur_counts.get('ahk_missing')}"
    )
    print(
        f"  Rust  {cur_counts.get('rust_files')} 文件 / "
        f"{cur_counts.get('rust_edges')} use 边 / "
        f"{cur_counts.get('rust_crate_edges')} crate 边 / "
        f"{cur_counts.get('rust_crate_cycles')} 生产环 / "
        f"{len(cur_violations)} 违规"
    )
    print(
        f"  JS    {cur_counts.get('js_files')} 文件 / "
        f"{cur_counts.get('js_edges')} import 边"
    )

    if warnings:
        print("\n[WARN] 结构变化（不阻塞，供人工确认）:")
        for w in warnings:
            print(f"  - {w}")

    if errors:
        print("\n[FAIL] 闸门① 未通过:")
        for e in errors:
            print(f"  - {e}")
        print(
            "\n  若为有意变更：修正代码，或更新 ALLOWED_CRATE_DEPS 后执行\n"
            "  `python scripts/check-graph-baseline.py --update` 并人工复核 diff。"
        )
        return 1

    print("\n[PASS] 闸门① 通过：无新增环、无白名单外依赖违规")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
