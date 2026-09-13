#!/usr/bin/env python3
"""闸门③「已登记 test-map.md」的自动化检查。

做三件事：
  A. 文档内部自洽：每个 `##` 章节内，小计/总计行的数字必须等于其之前明细行之和
     （末位小计较全部累计和，中间小计较本段和，兼容 asd-application 的
     单元小计 / 集成小计 / 总计 三段结构与 asd-tauri 跨表 `--lib` + `tests/` 结构）。
  B. 运行时对账：解析「自洽校验」行的各 crate 数字，与
     `cargo test -p <crate> --all-targets -- --list` 的实际注册数比对。
  C. 汇总行对账：解析《汇总》表中 Rust 总数的首个数字，与 B 的实际总和比对。

用法：
    python scripts/check-test-map.py                # A + B + C
    python scripts/check-test-map.py --no-cargo     # 只做 A（快，不编译）
"""

from __future__ import annotations

import argparse
import re
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
TEST_MAP = REPO_ROOT / "asd-tauri" / "docs" / "test-map.md"
TAURI_DIR = REPO_ROOT / "asd-tauri"

CRATES = [
    "asd-domain",
    "asd-ipc-protocol",
    "asd-application",
    "asd-test-harness",
    "asd-tauri",
]

SUBTOTAL_RE = re.compile(r"小计|总计")
NUM_RE = re.compile(r"\d+")


def cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def first_int(text: str) -> int | None:
    m = NUM_RE.search(text.replace("**", "").replace("`", ""))
    return int(m.group()) if m else None


def is_separator(line: str) -> bool:
    return bool(re.fullmatch(r"\|[\s:|-]+\|", line.strip()))


def check_internal_consistency(lines: list[str]) -> list[str]:
    """检查 A：章节内小计/总计 = 其之前明细之和。"""
    errors: list[str] = []
    section = "(未命名)"
    details_cum = 0          # 本章节累计明细
    segment = 0              # 上一个小计之后的明细
    pending: list[tuple[str, int, int, int]] = []  # (标签, 声明值, 段内和, 累计和)
    in_table = False

    def flush(last_is_final: bool) -> None:
        nonlocal pending
        for idx, (label, declared, seg_sum, cum_sum) in enumerate(pending):
            expected = cum_sum if (last_is_final and idx == len(pending) - 1) else seg_sum
            if declared != expected:
                errors.append(
                    f"[{section}] {label} 声明 {declared}，实际明细之和 {expected}"
                )
        pending = []

    for raw in lines:
        line = raw.rstrip("\n")
        if line.startswith("## "):
            flush(last_is_final=True)
            section = line[3:].strip()
            details_cum = segment = 0
            in_table = False
            continue
        if not line.strip().startswith("|"):
            if in_table:
                flush(last_is_final=True)
            in_table = False
            continue
        if is_separator(line):
            in_table = True
            continue
        cs = cells(line)
        in_table = True
        if len(cs) < 4:
            continue
        if SUBTOTAL_RE.search(cs[0]):
            val = first_int(cs[3])
            if val is None:
                continue  # 形如「59 套件 / 255 个 Test_ 方法」，无法按纯数字校验
            pending.append((cs[0], val, segment, details_cum))
            segment = 0
            continue
        val = first_int(cs[3])
        if val is None:
            continue
        details_cum += val
        segment += val

    flush(last_is_final=True)
    return errors


def parse_self_check_line(text: str) -> dict[str, int] | None:
    """解析「自洽校验」行：... = 136 + 72 + 163 + 3 + 242 = 616。"""
    for line in text.splitlines():
        if "自洽校验" not in line:
            continue
        m = re.search(
            r"=\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)\s*=\s*(\d+)",
            line,
        )
        if not m:
            continue
        nums = [int(g) for g in m.groups()]
        return dict(zip(CRATES, nums[:5])) | {"__total__": nums[5]}
    return None


def parse_summary_total(text: str) -> int | None:
    """解析《汇总》表中 Rust 总数的首个数字（形如 `| Rust 测试... | 616（...`）"""
    for line in text.splitlines():
        if line.startswith("|") and "Rust 测试" in line:
            cs = cells(line)
            if len(cs) >= 2:
                val = first_int(cs[1])
                if val is not None:
                    return val
    return None


def runtime_count(crate: str) -> int:
    proc = subprocess.run(
        ["cargo", "test", "-p", crate, "--all-targets", "--", "--list"],
        cwd=str(TAURI_DIR),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit(f"ERROR: cargo test -p {crate} --list 失败")
    return sum(1 for ln in proc.stdout.splitlines() if ln.endswith(": test"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-cargo", action="store_true", help="跳过运行时对账（不编译）")
    args = ap.parse_args()

    if not TEST_MAP.exists():
        raise SystemExit(f"ERROR: 找不到 {TEST_MAP}")
    text = TEST_MAP.read_text(encoding="utf-8")
    lines = text.splitlines()

    print("=" * 60)
    print("闸门③ 登记检查：test-map.md")
    print("=" * 60)

    errors: list[str] = []

    # --- A 文档内部自洽 ---
    internal = check_internal_consistency(lines)
    if internal:
        errors.extend(internal)
    print(f"[A] 文档内部自洽：{'通过' if not internal else f'{len(internal)} 处不一致'}")

    if args.no_cargo:
        for e in errors:
            print(f"  - {e}")
        print("\n（--no-cargo：已跳过 B/C 运行时对账）")
        return 1 if errors else 0

    # --- B 运行时对账 ---
    declared = parse_self_check_line(text)
    if declared is None:
        errors.append("未能在 test-map.md 中找到可解析的「自洽校验」行")
        print("[B] 运行时对账：跳过（无自洽校验行）")
        actual: dict[str, int] = {}
    else:
        actual = {c: runtime_count(c) for c in CRATES}
        for c in CRATES:
            d, a = declared.get(c), actual[c]
            if d != a:
                errors.append(f"{c}: 登记 {d}，运行时实际 {a}")
        s = sum(actual.values())
        if declared.get("__total__") != s:
            errors.append(f"自洽校验总和: 登记 {declared.get('__total__')}，实际 {s}")
        print("[B] 运行时对账：")
        for c in CRATES:
            mark = "OK " if declared.get(c) == actual[c] else "DIFF"
            print(f"     {mark} {c:<18} 登记 {declared.get(c):>4} / 实际 {actual[c]:>4}")

    # --- C 汇总行对账 ---
    summary = parse_summary_total(text)
    if actual:
        s = sum(actual.values())
        if summary is None:
            errors.append("未能解析《汇总》表中的 Rust 总数")
        elif summary != s:
            errors.append(f"《汇总》Rust 总数：登记 {summary}，实际 {s}")
        print(f"[C] 汇总行：登记 {summary} / 实际 {s}")

    if errors:
        print("\n[FAIL] 闸门③ 未通过:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("\n[PASS] 闸门③ 通过：文档登记数与运行时一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
