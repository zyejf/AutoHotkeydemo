#!/usr/bin/env python3
"""闸门③「已登记 test-map.md」的自动化检查。

做四件事：
  A. 文档内部自洽：每个 `##` 章节内，小计/总计行的数字必须等于其之前明细行之和
     （末位小计较全部累计和，中间小计较本段和，兼容 asd-application 的
     单元小计 / 集成小计 / 总计 三段结构与 asd-tauri 跨表 `--lib` + `tests/` 结构）。
  B. 运行时对账：解析「自洽校验」行的各 crate 数字，与
     `cargo test -p <crate> --all-targets -- --list` 的实际注册数比对。
  C. 汇总行对账：解析《汇总》表中 Rust 总数的首个数字，与 B 的实际总和比对。
  D. AHK 两维口径校验（2026-09-19 新增，见审查发现 #9）：见 `check_d_ahk_dimensions`。

用法：
    python scripts/check-test-map.py                # A + B + C + D
    python scripts/check-test-map.py --no-cargo     # 只做 A + D（快，不编译）
"""

from __future__ import annotations

import argparse
import os
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


# ------------------------------------------------------------------ D 段：AHK 两维口径
# 2026-09-19 审查发现 #9（test-map 三处无机器守护）：
#   AHK 明细行的单元格形如 `10 / 46`（套件数 / `Test_` 方法数），而 A 段用的是
#   `first_int()` —— **只取单元格里首个整数**，第二个数字（方法数）**从未进入校验**。
#   实测 6 条阳性对照：改方法数 / 改《汇总》AHK 行 / 改文首口径提示，G3d 全部 exit 0
#   放行，只有「套件数」这一维会红（改 `10 -> 11` 时 exit 1）。
# 本段把「方法数」这一维补上，并补三处交叉引用与实测扫描：
#   D1 文档内两维自洽：AHK 明细行两维分别求和 == 总计行两维。
#   D2 《汇总》→ 明细：汇总「AHK 执行器测试」两数 == 明细两维合计；
#                      汇总「AHK 完整套件」用例数 == 文首口径提示的实跑数。
#   D3 实测静态扫描（不依赖 cargo / AHK 运行时，几毫秒）：
#      · `tests/**/*.ahk`（排除 `run_tests.ahk` 与 `archive/`）的 `Test_` 方法定义总数
#        == 文首口径提示的静态数；
#      · `tests/test_ahk_executor/` 5 个文件各自的「套件数 / 方法数」== 明细行两维。
#   D4 文首口径提示 → 明细：口径提示里 `watchdog_integration_tests.rs` 的 `fn` 定义数
#      == 明细行该文件登记数。
# ⚠️ 为什么 AHK 可以用正则而 Rust 不行：本文档「统计命令」章节已记录 Rust 侧正则计数
#    不可靠（`#[cfg]` / 宏展开 / 带参属性），故 Rust 一律走运行时注册数；而 AHK 的权威
#    口径**就是**「`test_ahk_executor/*.ahk` 中以 `Test_` 开头的方法定义数」，本文档自己
#    给出的统计命令也是正则。两者口径不同源，不混用。
AHK_PAIR_RE = re.compile(r"(\d+)\s*/\s*(\d+)")
AHK_TOTAL_RE = re.compile(r"(\d+)\s*套件\s*/\s*(\d+)")
AHK_METHOD_RE = re.compile(r"^\s*Test_[A-Za-z0-9_]+", re.M)
AHK_SUITE_RE = re.compile(r"class\s+\w+\s+extends\s+AutoHotUnitSuite")
AHK_EXECUTOR_DIR = "tests/test_ahk_executor"
# 静态 `Test_` 计数的排除项（口径取自文档文首：「不含 `tests/run_tests.ahk` 的 24 个，
# 那是另一个 runner」；`archive/` 是已下线脚本，实测其 92 个不在 720 内）
AHK_SCAN_SKIP_NAMES = {"run_tests.ahk"}
AHK_SCAN_SKIP_PARTS = {"archive"}


def _scan_ahk_file(path: Path) -> tuple[int, int]:
    """返回 (套件数, Test_ 方法数)。读不了按 (-1, -1) 由调用方判失败。"""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return (-1, -1)
    return (len(AHK_SUITE_RE.findall(text)), len(AHK_METHOD_RE.findall(text)))


def parse_ahk_detail_rows(text: str) -> tuple[list[tuple[str, int, int]], tuple[int, int] | None]:
    """解析「## AHK 执行器测试」章节：明细行 (文件, 套件, 方法) + 总计行 (套件, 方法)。"""
    rows: list[tuple[str, int, int]] = []
    total: tuple[int, int] | None = None
    in_section = False
    for line in text.splitlines():
        if line.startswith("## "):
            in_section = line[3:].strip() == "AHK 执行器测试"
            continue
        if not in_section or not line.strip().startswith("|") or is_separator(line):
            continue
        cs = cells(line)
        if len(cs) < 4:
            continue
        if SUBTOTAL_RE.search(cs[0]):
            m = AHK_TOTAL_RE.search(cs[3].replace("**", ""))
            if m:
                total = (int(m.group(1)), int(m.group(2)))
            continue
        m = AHK_PAIR_RE.fullmatch(cs[3].replace("**", "").strip())
        if m:
            rows.append((cs[2].replace("`", ""), int(m.group(1)), int(m.group(2))))
    return rows, total


def parse_summary_ahk_rows(text: str) -> dict[str, int | None]:
    """解析《汇总》表：AHK 执行器测试两维 + AHK 完整套件实跑用例数。"""
    out: dict[str, int | None] = {"suites": None, "methods": None, "full_cases": None}
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        cs = cells(line)
        if len(cs) < 2:
            continue
        label, val = cs[0], cs[1]
        if "AHK 执行器测试" in label:
            m = AHK_TOTAL_RE.search(val.replace("**", ""))
            if m:
                out["suites"], out["methods"] = int(m.group(1)), int(m.group(2))
        elif "AHK v2 完整测试套件" in label:
            v = first_int(val)
            if v is not None:
                out["full_cases"] = v
    return out


def parse_preamble_hints(text: str) -> dict[str, int]:
    """解析文首「口径差异提示」里的三个数字：实跑数 / 静态数 / watchdog fn 定义数。"""
    head = text.split("\n## ", 1)[0]
    out: dict[str, int] = {}
    m = re.search(
        r"实跑总数（\*\*(\d+)\*\*）略高于静态\s*`Test_`\s*计数（\*\*(\d+)\*\*", head
    )
    if m:
        out["runtime"], out["static"] = int(m.group(1)), int(m.group(2))
    m = re.search(r"`fn`\s*定义数\s*=\s*\*\*(\d+)\*\*", head)
    if m:
        out["wdog_fn"] = int(m.group(1))
    return out


def parse_detail_test_count(text: str, needle: str) -> int | None:
    """按文件路径关键字取明细行登记的测试数。"""
    for line in text.splitlines():
        if not line.strip().startswith("|") or needle not in line:
            continue
        cs = cells(line)
        if len(cs) >= 4 and not SUBTOTAL_RE.search(cs[0]):
            return first_int(cs[3])
    return None


def check_d_ahk_dimensions(text: str, repo_root: Path) -> list[str]:
    """D 段：AHK 套件数 / 方法数两个维度 + 文首口径提示的交叉引用与实测扫描。"""
    errors: list[str] = []

    rows, total = parse_ahk_detail_rows(text)
    if not rows:
        return ["未能解析「## AHK 执行器测试」章节的明细行（D 段无法校验，按失败处理）"]

    sum_suites = sum(r[1] for r in rows)
    sum_methods = sum(r[2] for r in rows)

    # D1 文档内两维自洽
    if total is None:
        errors.append("未能解析 AHK 总计行的「套件 / 方法」两个数字")
    else:
        if total[0] != sum_suites:
            errors.append(f"[D1] AHK 总计套件数 登记 {total[0]}，明细之和 {sum_suites}")
        if total[1] != sum_methods:
            errors.append(f"[D1] AHK 总计方法数 登记 {total[1]}，明细之和 {sum_methods}")

    # D2 《汇总》→ 明细
    summ = parse_summary_ahk_rows(text)
    if summ["suites"] is None or summ["methods"] is None:
        errors.append("未能解析《汇总》表「AHK 执行器测试」行的两维数字")
    else:
        if summ["suites"] != sum_suites:
            errors.append(
                f"[D2] 《汇总》套件数 {summ['suites']} ≠ 明细之和 {sum_suites}"
            )
        if summ["methods"] != sum_methods:
            errors.append(
                f"[D2] 《汇总》方法数 {summ['methods']} ≠ 明细之和 {sum_methods}"
            )

    hints = parse_preamble_hints(text)
    if "runtime" not in hints or "static" not in hints:
        errors.append("未能解析文首口径提示的「实跑总数 / 静态 Test_ 计数」")
    if summ["full_cases"] is not None and "runtime" in hints:
        if summ["full_cases"] != hints["runtime"]:
            errors.append(
                f"[D2] 《汇总》AHK 完整套件用例数 {summ['full_cases']} "
                f"≠ 文首口径提示实跑数 {hints['runtime']}"
            )

    # D3 实测静态扫描
    static_total = 0
    scanned = 0
    for p in sorted((repo_root / "tests").rglob("*.ahk")):
        rel = p.relative_to(repo_root)
        if p.name in AHK_SCAN_SKIP_NAMES or (set(rel.parts) & AHK_SCAN_SKIP_PARTS):
            continue
        n_suites, n_methods = _scan_ahk_file(p)
        if n_methods < 0:
            errors.append(f"[D3] 扫描失败：{rel.as_posix()} 读取出错")
            continue
        scanned += 1
        static_total += n_methods
    if "static" in hints and static_total != hints["static"]:
        errors.append(
            f"[D3] 实测 `tests/` 下 `Test_` 方法数 {static_total} "
            f"≠ 文首口径提示静态数 {hints['static']}"
        )

    exec_dir = repo_root / AHK_EXECUTOR_DIR
    for name, d_suites, d_methods in rows:
        p = repo_root / name if not name.startswith(AHK_EXECUTOR_DIR) else repo_root / name
        if not p.exists():
            # 明细行写的是 `tests/test_ahk_executor/xxx.ahk` 形式
            p = exec_dir / name.split("/")[-1]
        if not p.exists():
            errors.append(f"[D3] 明细行文件不存在：{name}")
            continue
        a_suites, a_methods = _scan_ahk_file(p)
        if a_methods < 0:
            errors.append(f"[D3] 扫描失败：{name}")
            continue
        if a_suites != d_suites:
            errors.append(
                f"[D3] {name} 套件数：登记 {d_suites}，实测 {a_suites}"
            )
        if a_methods != d_methods:
            errors.append(
                f"[D3] {name} 方法数：登记 {d_methods}，实测 {a_methods}"
            )

    # D4 文首口径提示 → 明细行
    if "wdog_fn" in hints:
        declared = parse_detail_test_count(text, "watchdog_integration_tests.rs")
        if declared is None:
            errors.append("[D4] 未能解析明细行 `watchdog_integration_tests.rs` 的登记数")
        elif declared != hints["wdog_fn"]:
            errors.append(
                f"[D4] 文首口径提示 `fn` 定义数 {hints['wdog_fn']} "
                f"≠ 明细行登记数 {declared}"
            )

    return errors


_LIST_CACHE: dict[str, list[str]] = {}


def list_tests(crate: str) -> list[str]:
    """`cargo test -- --list` 的条目名（去掉 `: test` 后缀）。按 crate 缓存，避免重复编译。

    ⚠️ 用 `--tests`（= lib 测试 + 集成测试）而不是 `--all-targets`：后者会额外构建
    criterion benches（harness = false，`--list` 下注册数为 0），白花编译时间。
    ⚠️ 必须带 CARGO_INCREMENTAL=0：rustc 1.95 在增量编译下可能 ICE（exit 101），会被
    误读成「对账失败」。2026-09-19 实测本地裸跑即撞到（asd-ipc-protocol lib）。在脚本内
    设而不仅改 CI，本地与 CI 同时受益 —— ci.yml:165 的 G3h 步骤已这么做。
    """
    if crate in _LIST_CACHE:
        return _LIST_CACHE[crate]
    proc = subprocess.run(
        ["cargo", "test", "-p", crate, "--tests", "--", "--list"],
        cwd=str(TAURI_DIR),
        env=dict(os.environ, CARGO_INCREMENTAL="0"),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit(f"ERROR: cargo test -p {crate} --list 失败")
    names = [ln[: -len(": test")] for ln in proc.stdout.splitlines()
             if ln.endswith(": test")]
    _LIST_CACHE[crate] = names
    return names


def runtime_count(crate: str) -> int:
    """运行时注册数（口径见 test-map 文首：`--tests`，**不含 doc-test**）。"""
    return len(list_tests(crate))


# ------------------------------------------------------------------ D5
# Rust **按文件**明细行守护（TD-077）。B 段只按 crate 总数对账，单个文件的登记数
# 漂移不会报警 —— 实证：watchdog.rs 由 32 漂到 38，G3d 全程不红，靠人工才发现。
#
# 三类文件的模块归属规则（**2026-09-19 实测得出，勿凭直觉改**）：
#   1) <root>/tests/<f>.rs        Cargo 集成测试 → 顶层 fn，**条目名 == fn 名**（无模块前缀）
#   2) <root>/src/tests/<f>.rs    挂在 src 的 tests 模块下 → `tests::<f>::`
#   3) 其它 <root>/src/**/<f>.rs  内联 `#[cfg(test)] mod <m> {` → `<模块路径>::<m>::`
#      ⚠️ 只取后接 `{` 的内联模块：`mod tests;` 是**外部目录声明**，不算本文件的测试 ——
#      否则 lib.rs 会把整个 tests/ 目录算进去（实证：6 变成 79）。
def _inline_mod_names(path: Path) -> list[str]:
    src = path.read_text(encoding="utf-8", errors="replace")
    names = [m.group(1) for m in
             re.finditer(r"#\[cfg\(test\)\]\s*mod\s+(\w+)\s*\{", src)]
    return names or ["tests"]


def _top_fn_names(path: Path) -> list[str]:
    """crate 根集成测试的顶层 `#[test]` / `#[tokio::test]` fn 名。"""
    src = path.read_text(encoding="utf-8", errors="replace")
    return [m.group(1) for m in
            re.finditer(r"#\[(?:tokio::)?test\b[^\]]*\]\s*(?:async\s+)?fn\s+(\w+)", src)]


def _rust_row_prefixes(rel: str) -> list[str]:
    """rel 相对 `asd-tauri/`；返回以 `::` 结尾者=前缀匹配，否则=精确匹配。"""
    rel = rel.replace("\\", "/")
    rest = ("/".join(rel.split("/")[2:]) if rel.startswith("crates/")
            else rel[len("src-tauri/"):])
    abspath = TAURI_DIR / rel.replace("/", os.sep)
    stem = os.path.basename(rel)[:-3]
    if rest.startswith("tests/"):                       # (1) Cargo 集成测试
        return _top_fn_names(abspath) if abspath.exists() else []
    if rest.startswith("src/tests/"):                   # (2) src 内 tests 模块
        return [f"tests::{stem}::"]
    inner = rest[len("src/"):]                          # (3) 内联
    base = "" if inner == "lib.rs" else inner[:-3].replace("/", "::")
    mods = _inline_mod_names(abspath) if abspath.exists() else ["tests"]
    return [(f"{base}::{m}" if base else m) + "::" for m in mods]


_TARGET_CACHE: dict[tuple[str, str], list[str]] = {}


def list_target_tests(crate: str, target: str) -> list[str]:
    """单个集成测试 target 的条目（`cargo test -p <crate> --test <target> -- --list`）。

    ⚠️ 为什么不能从 `-p <crate> --tests` 的全量列表里按 fn 名过滤：
    集成测试文件**内部还可以定义 mod**，那些测试的条目会带模块前缀，按 fn 名精确匹配
    会漏计 —— 实证：asd-application/tests/integration_tests.rs 真实 28 条，按 fn 名只
    匹配到 22 条。按 target 单独统计才是精确口径。
    """
    key = (crate, target)
    if key in _TARGET_CACHE:
        return _TARGET_CACHE[key]
    proc = subprocess.run(
        ["cargo", "test", "-p", crate, "--test", target, "--", "--list"],
        cwd=str(TAURI_DIR),
        env=dict(os.environ, CARGO_INCREMENTAL="0"),
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit(
            f"ERROR: cargo test -p {crate} --test {target} --list 失败")
    names = [ln[: -len(": test")] for ln in proc.stdout.splitlines()
             if ln.endswith(": test")]
    _TARGET_CACHE[key] = names
    return names


def check_d5_rust_rows(text: str) -> list[str]:
    """Rust 明细行：登记数 vs 从 `--list` 反推的实测数。"""
    by_crate: dict[str, list[tuple[str, int]]] = {}
    for line in text.splitlines():
        if not line.startswith("| "):
            continue
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) < 4 or c[0] not in CRATES or c[1] not in ("单元", "集成"):
            continue
        m = re.fullmatch(r"\**(\d+)\**", c[3])
        if m:
            by_crate.setdefault(c[0], []).append((c[2], int(m.group(1))))
    if not by_crate:
        return ["[D5] 未解析到任何 Rust 明细行（表格格式变更？本段会静默失效）"]

    errors: list[str] = []
    for crate in CRATES:
        for rel, want in by_crate.get(crate, []):
            rel_n = rel.replace("\\", "/")
            rest = ("/".join(rel_n.split("/")[2:]) if rel_n.startswith("crates/")
                    else rel_n[len("src-tauri/"):])
            if rest.startswith("tests/"):
                # Cargo 集成测试：整文件就是一个 target，按 target 精确统计
                got = len(list_target_tests(crate, os.path.basename(rel_n)[:-3]))
            else:
                pfxs = _rust_row_prefixes(rel)
                if not pfxs:
                    errors.append(
                        f"[D5] {rel}：无法推导模块前缀（文件不存在或无测试项）")
                    continue
                got = sum(1 for t in list_tests(crate)
                          if any(t.startswith(p) if p.endswith("::") else t == p
                                 for p in pfxs))
            if got != want:
                errors.append(f"[D5] {rel}：登记 {want}，实测 {got}")
    return errors


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

    # --- D AHK 两维口径（不需要 cargo） ---
    d_errors = check_d_ahk_dimensions(text, REPO_ROOT)
    if d_errors:
        errors.extend(d_errors)
    print(f"[D] AHK 两维口径（套件/方法 + 文首口径提示）："
          f"{'通过' if not d_errors else f'{len(d_errors)} 处不一致'}")

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

    # --- D5 Rust 按文件明细行（需 cargo；放在 B 之后以复用 --list 缓存） ---
    d5 = check_d5_rust_rows(text)
    if d5:
        errors.extend(d5)
    print(f"[D5] Rust 明细行（按文件）：{'通过' if not d5 else f'{len(d5)} 处不一致'}")

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
