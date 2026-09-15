#!/usr/bin/env python3
"""技术债度量检查（技术债清理计划 阶段 0 的交付物之一）。

做三件事，全部是**纯静态、不编译、不执行被测程序**，因此可以在 CI 上秒级跑完：

  C1 文件级坏味道，三个互补的子信号（用三个而不是一个，是因为单独任一个都会漏）：
      C1a 孤儿文件：不在 #Include 图上被任何文件指向、不匹配已知入口模式、且没有
          被其它语言（JS/Python/Shell/Rust…）以字符串形式引用。
      C1b 同名重复：同一个 basename 在语料里出现 ≥2 次。
          —— 只靠 C1a 抓不到：死副本常被「basename 跨语言引用」洗白
          （`main.ahk`、`run_all_tests.ahk` 都是常见名，源码里到处出现）。
          实测抓到 根 `ui_manager.ahk`（真身在 presentation/）、
          `tests/test_joystick.ahk`（真身在 test_ahk_executor/）、
          两份 `_harness.ahk`。
      C1c 代码在非代码目录：.ahk 出现在 docs/、reports/、backups/ 等文档产物目录。
          —— 典型：审查报告里粘的 workspace 代码快照。
  C2 测试未接入执行：`tests/` 下的 .ahk 文件，若从 `run_all_tests.ahk` /
     `run_tests.ahk` 出发沿 #Include 图不可达，则它永远不会被 CI 执行 —— 写了等于
     没写。
  C3 文档-代码一致性：`tools/ahk-bench/baselines.json` 里的 `k` / `warn_k` 必须在
     `docs/developer-guide.md` 与 `asd-tauri/docs/test-map.md` 中都能找到同样的数字；
     且每个基准必须登记 `_baseline_runs`（基线来源可追溯）。
     —— 起因：`baselines.json` 把 K 从 2.0 改成 1.5 时，test-map.md 漏改，
     文档与代码漂移了两周没人发现。

棘轮（ratchet）语义
--------------------
C1/C2 的现状是**存量债**，不可能一次清零。所以脚本不要求「当前为 0」，只要求
「**不比基线更差**」：

  - 出现在基线里、现在还在  → 计为「已登记」，不报错（但要能看见）
  - 出现在基线里、现在没了  → 计为「已清理」，报喜
  - 不在基线里、现在出现了  → **新增债 → FAIL**（这就是闸门的意义）
  - 想主动下调水位：清理掉若干项后跑 `--update-baseline`，把新的（更小的）集合
    冻结为新基线。基线文件 diff 会出现在 CR 里，收紧必须过 review。

C3 不做棘轮：一致性问题是当次就必须修的，没有「先记账以后再说」的余地。

用法：
    python scripts/check-tech-debt.py                  # 三检 + 与基线比对（CI 用这个）
    python scripts/check-tech-debt.py --show           # 只打印当前结果，不与基线比对
    python scripts/check-tech-debt.py --update-baseline
    python scripts/check-tech-debt.py --only c1        # 只跑某一检（c1/c2/c3）

退出码：0 = 通过；1 = 有新增债或一致性错误。
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# Windows CI runner 上 stdio 默认走系统 ANSI 代码页（cp1252），print 中文会
# UnicodeEncodeError。显式切 UTF-8；本地若已是 UTF-8 则无副作用。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

REPO_ROOT = Path(__file__).resolve().parent.parent
BASELINE = REPO_ROOT / ".review-analysis" / "tech-debt-baseline.json"
BASELINES_JSON = REPO_ROOT / "tools" / "ahk-bench" / "baselines.json"
DEV_GUIDE = REPO_ROOT / "docs" / "developer-guide.md"
TEST_MAP = REPO_ROOT / "asd-tauri" / "docs" / "test-map.md"

# ---------------------------------------------------------------- 语料与豁免

# 这些目录不进语料：第三方源码、构建产物、已归档的旧测试。
EXCLUDE_DIR_MARKERS = (
    "AutoHotkey-2.0.26",   # 随仓库携带的 AHK 解释器源码（vendor）
    "node_modules",
    ".git",
    "tests\\archive",
    "tests/archive",
    "src-tauri\\target",
    "src-tauri/target",
    "fuzz\\target",
    "\\target\\",
    "/target/",
)

# 跨语言引用扫描要额外排除**生成物 / 分析产物**：
# ⚠️ `.review-analysis/graph-raw.json` 等图谱产物里含全仓文件名，若不排除，
#    xref 会把每一个孤儿都洗白成「被引用」，C1 直接恒为 0（本脚本第一版就踩了这个坑）。
XREF_EXCLUDE_MARKERS = EXCLUDE_DIR_MARKERS + (
    ".review-analysis",
    ".workbuddy-ai",
    "coverage",
    "docs\\review",
    "docs/review",
    "\\results\\",
    "/results/",
    "\\logs\\",
    "/logs/",
    "\\reports\\",
    "/reports/",
    "\\backups\\",
    "/backups/",
    "test_output",
)

# 视为「入口」的 AHK 文件：本来就该没有入边（由人 / 由 shell 直接启动）。
# 用 posix 相对路径做 fnmatch。
ENTRY_PATTERNS = (
    "main.ahk",                     # 生产主入口
    "asd.ahk",                      # 向后兼容入口
    "tests/run_all_tests.ahk",      # AHK 测试总入口
    "tests/run_tests.ahk",          # AHK 测试次入口
    "tools/ahk-bench/bench_*.ahk",  # 基准脚本，run.sh 按 glob 调
    "tools/ahk-probes/p*_*.ahk",    # 探针脚本，run.sh 按 glob 调
    "tools/ahk-probes/_dbg_*.ahk",  # 临时调试探针
    "scripts/perf/*.ahk",           # 手动执行的性能脚本（README 有命令示例）
)

# 跨语言引用扫描：只扫「代码/配置」，不扫 .md。
# 理由：README 里提一句旧文件名太常见了，会把真正的死文件洗白；而 JS/Python 里
# 拼 'key_receiver.ahk' 去起子进程是**真引用**，必须认。
XREF_SUFFIXES = {
    ".js", ".ts", ".mjs", ".cjs", ".py", ".sh", ".ps1", ".cmd", ".bat",
    ".json", ".toml", ".yml", ".yaml", ".rs",
}
XREF_MAX_BYTES = 2 * 1024 * 1024

# xref 只扫这些**源码目录**。全仓扫描实测 24s（CI 上更慢），且会被覆盖率报告、
# 历史报告一类的生成物污染；收到源码目录后 <2s，且假阴性显著变少。
XREF_ROOTS = (
    "asd-tauri/src",
    "asd-tauri/src-tauri",
    "asd-tauri/e2e",
    "scripts",
    "tools",
)

# C1c：这些顶层目录是「文档/产物」，不该出现源码。
NON_CODE_TOPLEVEL = {"docs", "reports", "backups", "logs", "test_output", "config_backup"}

# AHK 的 #Include 是**指令**，必须独占一行（允许前导空白与 `*i`）。
# ⚠️ 不加行首锚定的话，注释里随口写的「#Include xxx」会被当成真边，图谱立刻失真。
INCLUDE_RE = re.compile(
    r'^[ \t]*#Include[ \t]+(?:\*i[ \t]+)?["\']?([^"\'\r\n;]+?)["\']?[ \t]*$',
    re.M,
)

# ---------------------------------------------------------------- C3b 常量
#
# C3b：文档里**硬写**的 AHK 回归基线数字（典型形态「642 / 642」）必须等于
# test-map.md 的实跑总数，否则就是过期数字。
#
# 由来（TD-018，2026-09-16）：方案 A/B/C 与 README 里写了 7 处「642/642」，
# 而实际用例数早已涨到 697。「通过数 / 总数」这种写法把同一个数字硬编码两遍，
# 测试一增长就必然过期，而且过期了没人会发现 —— 它在文档里，不在代码里。
#
# 处置原则：**文档里不复写数字，只写指向 test-map.md 的指针**。
# 历史报告（如 2026-09-13 的基准报告）里的数字是当日快照，本身合法，
# 由棘轮基线登记豁免，不要求回溯修改。

# 从 test-map.md 提取「实跑总数（**697**）」—— AHK 用例总数的唯一权威。
AHK_TOTAL_RE = re.compile(r"实跑总数（\*\*(\d+)\*\*）")

# 「N / N」形态的硬写基线数字。要求两侧数字相同，避免把
# 「通过 697 / 失败 0 / 跳过 7」这类合法的三段式统计误判进来。
STALE_COUNT_RE = re.compile(r"(?<![\d.])(\d{3,4})\s*/\s*\1(?![\d])")

# 同行必须出现这些词之一，才认定这一行在讲测试基线。
# 否则「100 / 100」这种无关比例会被扫进来。
COUNT_CONTEXT_WORDS = ("通过", "用例", "测试", "回归", "套件", "全量")

# 反引号包裹的内容视为「举例 / 代码片段」，不当作文档在声明基线数字。
#
# 由来：本检上线第一天就报出 2 项 [NEW]，全落在台账里**描述本检自身**的句子上
# —— 文档要解释「什么叫硬写 N / N」就必须举一个 N / N 的例子，而举的例子
# 必然是个陈旧数字。这不是债，是说明文字。
# 约定：举例一律写在反引号里（Markdown 里本就是「这是示例」的惯例），
# 真正声明基线数字则用裸数字，仍会被拦。
BACKTICK_SPAN_RE = re.compile(r"`[^`]*`")

# C3b 扫描范围：仓库根的 docs/（权威 test-map.md 在 asd-tauri/docs/，天然排除）。
C3B_DOC_ROOT = "docs"


# ---------------------------------------------------------------- 通用工具


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except Exception:
        return str(path)


def excluded(path: Path) -> bool:
    s = str(path)
    return any(m in s for m in EXCLUDE_DIR_MARKERS)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        try:
            return path.read_text(encoding="utf-8-sig", errors="replace")
        except Exception:
            return ""


def walk_files(root: Path, prune: set[str]):
    """带剪枝的目录遍历。

    ⚠️ 不能先用 rglob 再过滤：`asd-tauri/src-tauri/target` 下有几十万个文件，
    光枚举就要 20s+，整个闸门会慢到不可接受。必须边走边剪。
    """
    stack = [root]
    while stack:
        cur = stack.pop()
        try:
            entries = list(cur.iterdir())
        except Exception:
            continue
        for e in entries:
            if e.is_dir():
                if e.name in prune:
                    continue
                stack.append(e)
            elif e.is_file():
                yield e


# 目录名级别的一刀剪：这些名字在任何位置都不该进语料。
PRUNE_DIR_NAMES = {".git", "node_modules", "target", "AutoHotkey-2.0.26", "archive"}


def collect_ahk(root: Path) -> list[Path]:
    out = []
    for p in walk_files(root, PRUNE_DIR_NAMES):
        if p.suffix.lower() != ".ahk" or excluded(p):
            continue
        out.append(p.resolve())
    return sorted(set(out))


def resolve_include(base: Path, spec: str, repo_root: Path) -> Path | None:
    """把 #Include 的写法解析成绝对路径。

    AHK 的相对路径基准是「包含该指令的文件所在目录」；`%A_ScriptDir%` 起头的按
    仓库根处理。两者都试一遍，取第一个真实存在的。
    """
    s = spec.strip().replace("/", "\\")
    if s.upper().startswith("%A_SCRIPTDIR%"):
        s = s[len("%A_SCRIPTDIR%"):]
    s = s.lstrip("\\")
    if not s.lower().endswith(".ahk"):
        return None
    for base_dir in (base.parent, repo_root):
        cand = (base_dir / s)
        try:
            r = cand.resolve()
        except Exception:
            continue
        if r.exists():
            return r
    return None


def build_include_graph(files: list[Path], repo_root: Path):
    """返回 (入边集合, 出边表, 解析失败的 (文件, 原文) 列表)。"""
    allset = set(files)
    edges: dict[Path, set[Path]] = {}
    inbound: set[Path] = set()
    unresolved: list[tuple[Path, str]] = []
    for p in files:
        targets: set[Path] = set()
        for m in INCLUDE_RE.finditer(read_text(p)):
            t = resolve_include(p, m.group(1), repo_root)
            if t is not None and t in allset and t != p:
                targets.add(t)
            else:
                unresolved.append((p, m.group(1).strip()))
        if targets:
            edges[p] = targets
            inbound |= targets
    return inbound, edges, unresolved


def reachable_from(roots: list[Path], edges: dict[Path, set[Path]]) -> set[Path]:
    seen: set[Path] = set()
    stack = [r for r in roots if r]
    while stack:
        cur = stack.pop()
        for nxt in edges.get(cur, ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


# ---------------------------------------------------------------- C1 孤儿文件


def build_xref_names(repo_root: Path) -> set[str]:
    """收集非 AHK 代码/配置文件里出现过的 `.ahk` 文件名（跨语言引用证据）。"""
    names: set[str] = set()
    scanned = 0
    for root_name in XREF_ROOTS:
        root = repo_root / root_name
        if not root.exists():
            continue
        for p in walk_files(root, PRUNE_DIR_NAMES):
            if not p.is_file() or excluded(p):
                continue
            s = str(p)
            if any(m in s for m in XREF_EXCLUDE_MARKERS):
                continue
            if p.suffix.lower() not in XREF_SUFFIXES:
                continue
            try:
                if p.stat().st_size > XREF_MAX_BYTES:
                    continue
            except Exception:
                continue
            scanned += 1
            for m in re.finditer(r"[A-Za-z0-9_\-.]+\.ahk", read_text(p)):
                names.add(m.group(0).lower())
    return names, scanned


def check_c1(repo_root: Path) -> dict:
    files = collect_ahk(repo_root)
    inbound, _edges, unresolved = build_include_graph(files, repo_root)
    xref, xref_files = build_xref_names(repo_root)

    # --- C1a 孤儿文件 ---
    orphans: list[str] = []
    for p in files:
        if p in inbound:
            continue
        r = rel(p)
        if any(fnmatch.fnmatch(r, pat) for pat in ENTRY_PATTERNS):
            continue
        if p.name.lower() in xref:
            continue          # 被 JS/Python/Shell 等真正引用
        orphans.append(r)

    # --- C1b 同名重复 ---
    by_name: dict[str, list[Path]] = {}
    for p in files:
        by_name.setdefault(p.name.lower(), []).append(p)
    dups = [
        f"{name}（{len(v)} 处）: " + ", ".join(sorted(rel(x) for x in v))
        for name, v in sorted(by_name.items())
        if len(v) > 1
    ]

    # --- C1c 代码在非代码目录 ---
    misplaced = [
        rel(p) for p in files
        if p.relative_to(repo_root).parts[:1] and p.relative_to(repo_root).parts[0] in NON_CODE_TOPLEVEL
    ]

    return {
        "corpus": len(files),
        "unresolved_includes": len(unresolved),
        "xref_files": xref_files,
        "orphans": sorted(orphans),
        "duplicates": dups,
        "misplaced": sorted(misplaced),
        "findings": sorted(orphans) + dups + sorted(misplaced),
    }


# ---------------------------------------------------------------- C2 测试未接入


def check_c2(repo_root: Path) -> dict:
    tests_dir = repo_root / "tests"
    files = [p for p in collect_ahk(repo_root) if str(p.resolve()).startswith(str(tests_dir.resolve()))]
    allset = set(files)
    _inbound, edges, _unres = build_include_graph(files, repo_root)

    roots = [(tests_dir / "run_all_tests.ahk").resolve(),
             (tests_dir / "run_tests.ahk").resolve()]
    roots = [r for r in roots if r in allset]
    reach = reachable_from(roots, edges)

    findings = []
    for p in files:
        if p in roots or p in reach:
            continue
        findings.append(rel(p))

    return {
        "corpus": len(files),
        "reachable": len(reach) + len(roots),
        "findings": sorted(findings),
    }


# ---------------------------------------------------------------- C3 文档一致性


def _declared_in_doc(bench: str, num: float, text: str) -> bool:
    """该 bench 的 K/warn_k 值是否在文档里被写明。

    ⚠️ 只查「数字出现过没有」是不够的，会漏报：把 `prod_escape` 的 k 从 1.5 改回
    陈旧的 2.0 时，`2.0` 会被文档里满地都是的「AutoHotkey v2.0」命中，检查照样绿。
    （这正是 2026-09 真实发生过、且两周没被发现的漂移。）

    所以规则收紧为：**数字必须与 bench 名出现在同一行**。文档里 K 值的写法本来就
    是表格行 / 一句话带名字，这个约束是自然的，不要求文档改成机器可读格式。
    """
    # ⚠️ 只认 `repr` 的小数形态（1.5 / 1.25 / 2.0），**不接受** 裸整数形态：
    # k 若被改回 2.0，裸 `2` 会被 test-map 里「2 个基准脚本」这种无关数字命中而漏报
    # —— 本轮阳性对照实测踩到，两次。
    # 因此 baselines.json 的 k/warn_k 必须写成小数（见 check_c3 的类型检查）。
    # 前视排除 `v2.0` 这类版本号：否则「AutoHotkey v2.0」同样会命中。
    regexes = [re.compile(r"(?<![vV\d.])" + re.escape(repr(float(num))) + r"(?![\d])")]
    for line in text.splitlines():
        if bench.lower() not in line.lower():
            continue
        if any(r.search(line) for r in regexes):
            return True
    return False


def check_c3(repo_root: Path) -> dict:
    errors: list[str] = []
    checked: list[str] = []

    if not BASELINES_JSON.exists():
        return {"findings": [f"找不到 {rel(BASELINES_JSON)}"], "checked": []}
    try:
        data = json.loads(read_text(BASELINES_JSON))
    except Exception as e:  # JSON 坏了本身就是一致性问题
        return {"findings": [f"{rel(BASELINES_JSON)} 解析失败: {e}"], "checked": []}

    docs = {}
    for name, path in (("developer-guide.md", DEV_GUIDE), ("test-map.md", TEST_MAP)):
        docs[name] = read_text(path) if path.exists() else None

    for bench, cfg in data.items():
        if bench.startswith("_"):
            continue
        if not isinstance(cfg, dict):
            continue
        checked.append(bench)

        # (a) 基线来源必须可追溯
        runs = cfg.get("_baseline_runs")
        if not runs:
            errors.append(f"{bench}: 缺少 _baseline_runs，基线来源不可追溯")

        # (b) k / warn_k 必须在两份文档里都写明（与 bench 名同行）
        for key in ("k", "warn_k"):
            val = cfg.get(key)
            if val is None:
                errors.append(f"{bench}: baselines.json 缺少 {key}")
                continue
            if not isinstance(val, float):
                # 见 _declared_in_doc：文本比对只认小数形态，写成 `2` 无法可靠核对。
                errors.append(
                    f"{bench}: {key} 必须写成小数（如 2.0 而不是 2），当前值 {val!r}"
                )
                continue
            for docname, text in docs.items():
                if text is None:
                    errors.append(f"{bench}: 找不到文档 {docname}，无法核对 {key}")
                elif not _declared_in_doc(bench, float(val), text):
                    errors.append(
                        f"{bench}: {key}={val} 在 {docname} 中没有与「{bench}」写在同一行"
                        " —— 文档与代码已漂移"
                    )

    return {"findings": errors, "checked": checked}


# ------------------------------------------------- C3b 文档硬写的基线数字（棘轮）


def check_c3b(repo_root: Path) -> dict:
    """docs/ 下硬写的 AHK 用例总数（形态「N / N」）是否等于 test-map 的实跑总数。

    与 C3 不同，这一条**走棘轮**：带日期的历史报告里的数字是当日实测快照，
    本身没错（改它反而是篡改历史），所以首次检出的存量项登记进基线豁免，
    只有**新增的**硬写数字才会让门禁变红。
    """
    if not TEST_MAP.exists():
        return {"findings": [], "total": None, "scanned": 0}

    m = AHK_TOTAL_RE.search(read_text(TEST_MAP))
    if not m:
        # 权威数字提取不到 = 本检失效。返回 total=None，由 main 当成硬失败。
        return {"findings": [], "total": None, "scanned": 0}
    total = int(m.group(1))

    doc_root = repo_root / C3B_DOC_ROOT
    if not doc_root.is_dir():
        return {"findings": [], "total": total, "scanned": 0}

    findings: list[str] = []
    scanned = 0
    for p in walk_files(doc_root, PRUNE_DIR_NAMES):
        if p.suffix.lower() != ".md":
            continue
        scanned += 1
        try:
            lines = read_text(p).splitlines()
        except Exception:
            continue
        for i, line in enumerate(lines, 1):
            if not any(w in line for w in COUNT_CONTEXT_WORDS):
                continue
            # 举例用的 N / N 写在反引号里，豁免
            line = BACKTICK_SPAN_RE.sub(lambda m: " " * len(m.group(0)), line)
            for mm in STALE_COUNT_RE.finditer(line):
                n = int(mm.group(1))
                if n == total:
                    continue
                findings.append(
                    f"{rel(p)}:{i}: 硬写「{n} / {n}」，与 test-map 实跑总数 {total} 不符"
                    " —— 改为指向 test-map.md 的指针，不要复写数字"
                )

    return {"findings": findings, "total": total, "scanned": scanned}


# ------------------------------------------- C4 禁止加代码的空占位目录（TD-008）
#
# `src-tauri/src/application/` 与 `src-tauri/src/domain/` 是**历史占位**：真身分别是
# `asd-tauri/crates/asd-application/` 与 `asd-tauri/crates/asd-domain/`。留着两个同名
# 空目录，人（和 Agent）很容易把新代码放进「看起来对」的那个 —— 于是同一个分层概念
# 出现两套实现，且两套都不会被对方的错误修到。
#
# 为什么判「目录里有没有文件」而不是「目录存不存在」：
#   git **不跟踪空目录**。CI 是全新 checkout → 目录不存在；本机是老 clone → 目录存在。
#   用存在性判定，同一份代码会在两处得出相反结论 —— 那是埋雷，不是门禁。
#   判「有没有文件」才两边一致：空目录（无论存不存在）都 PASS，
#   有人往里放文件（无论在哪台机器）都 FAIL。
#
# 因此**删目录本身不是交付物**（删了也进不了版本库），这条检查才是。
FORBIDDEN_DIRS = (
    ("asd-tauri/src-tauri/src/application",
     "真身是 crates/asd-application/，在这里放代码会形成第二套 application 层"),
    ("asd-tauri/src-tauri/src/domain",
     "真身是 crates/asd-domain/，在这里放代码会形成第二套 domain 层"),
)


def check_c4(repo_root: Path) -> dict:
    """空占位目录守卫：目录可以不存在、可以为空，但**不能有文件**。"""
    findings: list[str] = []
    for sub, why in FORBIDDEN_DIRS:
        d = repo_root / sub
        if not d.exists():
            continue                      # 不存在 = 没人往里放东西
        if not d.is_dir():
            findings.append(f"{sub} 应是目录，实际是文件 —— 直接删掉（{why}）")
            continue
        inside = sorted(p for p in d.rglob("*") if p.is_file())
        if inside:
            findings.append(
                f"{sub} 里有 {len(inside)} 个文件（如 {rel(inside[0])}）"
                f" —— 禁放代码：{why}"
            )
    return {"findings": findings, "checked": [s for s, _ in FORBIDDEN_DIRS]}

# --------------------------------------------- C5 冗余 Cargo.lock（TD-019）
#
# workspace **成员**目录下的 Cargo.lock 是死文件：cargo 只会读写 workspace 根那一份，
# 成员自己的从来不更新。实测本项目 `src-tauri/Cargo.lock` 与根 lock 有 **14 个包版本不同**，
# 其中 `shlex` 是 2.0.1 vs 1.3.0（**主版本差异**）—— 任何遍历全部 Cargo.lock 的安全扫描
#（cargo audit / dependabot）都会读到那份过期的，报出与实际构建不符的漏洞结论。
# 这不是「碍眼」，是会引错判断的假证据。
#
# 判据：目录里有 Cargo.lock、该目录**不是** workspace 根、但**存在祖先 workspace 根** → 冗余。
# 独立 workspace（如 `src-tauri/fuzz/` 自己有 `[workspace]`）的 lock 合法，跳过。


def _is_workspace_root(cargo_toml: Path) -> bool:
    """Cargo.toml 是否声明了 [workspace]（含 [workspace.package] 等子表）。"""
    try:
        text = read_text(cargo_toml)
    except Exception:
        return False
    return re.search(r"^\[workspace(?:\.|\])", text, re.M) is not None


def check_c5(repo_root: Path) -> dict:
    """冗余 Cargo.lock 守卫：workspace 成员目录下不得有自己的 Cargo.lock。"""
    findings: list[str] = []
    checked = 0
    for lock in sorted(repo_root.rglob("Cargo.lock")):
        try:
            parts = set(lock.relative_to(repo_root).parts)
        except ValueError:
            continue
        if parts & PRUNE_DIR_NAMES:
            continue
        d = lock.parent
        manifest = d / "Cargo.toml"
        if not manifest.exists():
            continue                      # 没有清单文件的 lock 不归这条管
        checked += 1
        if _is_workspace_root(manifest):
            continue                      # 独立 workspace，合法
        anc, root_found = d.parent, None
        while anc == repo_root or anc.is_relative_to(repo_root):
            m = anc / "Cargo.toml"
            if m.exists() and _is_workspace_root(m):
                root_found = anc
                break
            if anc == repo_root:
                break
            anc = anc.parent
        if root_found is not None:
            findings.append(
                f"{rel(lock)} 是 workspace 成员目录下的冗余 lock（workspace 根在 "
                f"{rel(root_found)}）—— cargo 只用根那一份，成员这份永不更新，"
                f"会误导 cargo audit / dependabot 的安全结论"
            )
    return {"findings": findings, "checked": checked}

# ---------------------------------------------------------------- 基线 / 棘轮


def load_baseline() -> dict | None:
    if not BASELINE.exists():
        return None
    try:
        return json.loads(read_text(BASELINE))
    except Exception as e:
        print(f"[WARN] 基线文件解析失败：{e}")
        return None


def save_baseline(cur: dict) -> None:
    payload = {
        "_comment": (
            "技术债基线（scripts/check-tech-debt.py 生成）。"
            "C1a/C1b/C1c/C2/C3b 是存量债白名单（棘轮）：只有「基线外的新增项」才会让门禁"
            "变红；清理后重新 --update-baseline 即收紧水位。"
            "C3b 的存量项多为带日期的历史报告里的当日实测快照，本身合法，故只登记不修。"
            "C3 不做棘轮，必须恒为 0。"
        ),
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "c1a_orphan_files": cur["c1"]["orphans"],
        "c1b_dup_basenames": cur["c1"]["duplicates"],
        "c1c_misplaced_files": cur["c1"]["misplaced"],
        "c2_unwired_tests": cur["c2"]["findings"],
        "c3_doc_drift": cur["c3"]["findings"],
        "c3b_stale_counts": cur["c3b"]["findings"],
        "stats": {
            "c1_corpus": cur["c1"]["corpus"],
            "c1_unresolved_includes": cur["c1"]["unresolved_includes"],
            "c2_corpus": cur["c2"]["corpus"],
            "c2_reachable": cur["c2"]["reachable"],
        },
    }
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    with BASELINE.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"OK: 基线已写入 -> {rel(BASELINE)}")


def diff_set(baseline: list[str] | None, current: list[str]):
    b = set(baseline or [])
    c = set(current)
    return sorted(c - b), sorted(b & c), sorted(b - c)


# ---------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(
        description="技术债度量检查（C1 孤儿 / C2 未接入 / C3 文档漂移 / C3b 硬写基线数字 / C4 占位目录守卫 / C5 冗余 lock）"
    )
    ap.add_argument("--update-baseline", action="store_true", help="把当前结果冻结为新基线")
    ap.add_argument("--show", action="store_true", help="只打印当前结果，不与基线比对")
    ap.add_argument("--only", choices=["c1", "c2", "c3", "c3b", "c4", "c5"], help="只跑某一检")
    args = ap.parse_args()

    print("=" * 60)
    print("技术债度量检查（C1 孤儿文件 / C2 测试未接入 / C3 文档漂移 / C4 占位目录守卫 / C5 冗余 lock）")
    print("=" * 60)

    cur = {
        "c1": check_c1(REPO_ROOT),
        "c2": check_c2(REPO_ROOT),
        "c3": check_c3(REPO_ROOT),
        "c3b": check_c3b(REPO_ROOT),
        "c4": check_c4(REPO_ROOT),
        "c5": check_c5(REPO_ROOT),
    }

    if args.update_baseline:
        save_baseline(cur)
        return 0

    want = {args.only} if args.only else {"c1", "c2", "c3", "c4", "c5"}

    # ---------- C3：硬失败，不做棘轮 ----------
    c3_errors = list(cur["c3"]["findings"])
    if cur["c3b"]["total"] is None:
        # 权威数字提取不到，C3b 直接失效 —— 这本身必须变红，不能靠棘轮蒙混过去
        c3_errors.append(
            f"{rel(TEST_MAP)}: 无法从「实跑总数（**N**）」提取 AHK 用例总数，C3b 失效"
        )
    if "c3" in want:
        print(f"[C3] 文档-代码一致性：核对 {len(cur['c3']['checked'])} 个基准"
              f"（{', '.join(cur['c3']['checked']) or '无'}）")
        if c3_errors:
            for e in c3_errors:
                print(f"       - {e}")
        else:
            print("       通过：k / warn_k / _baseline_runs 与两份文档一致")

    # ---------- C4：硬失败，不做棘轮（这是规则不是存量债） ----------
    c4_findings = list(cur["c4"]["findings"])
    if "c4" in want:
        print(f"\n[C4] 禁止加代码的空占位目录：核对 {len(cur['c4']['checked'])} 个")
        if c4_findings:
            for f in c4_findings:
                print(f"       - {f}")
        else:
            print("       通过：占位目录为空或不存在")

    # ---------- C5：硬失败，冗余 Cargo.lock ----------
    c5_findings = list(cur["c5"]["findings"])
    if "c5" in want:
        print(f"\n[C5] 冗余 Cargo.lock（workspace 成员目录）：核对 {cur['c5']['checked']} 份")
        if c5_findings:
            for f in c5_findings:
                print(f"       - {f}")
        else:
            print("       通过：没有成员级别的冗余 lock")

    # ---------- C1 / C2：棘轮 ----------
    base = None if args.show else load_baseline()
    if base is None and not args.show:
        print("\n[WARN] 尚无基线，本次只打印现状。")
        print(f"       生成 0 号基线：python scripts/check-tech-debt.py --update-baseline")

    new_all: list[str] = []
    sections = [
        ("C1a", "孤儿文件（无入边 / 非入口 / 无跨语言引用）",
         "c1a_orphan_files", cur["c1"]["orphans"]),
        ("C1b", "同名重复（basename 出现 ≥2 次）",
         "c1b_dup_basenames", cur["c1"]["duplicates"]),
        ("C1c", "代码在非代码目录（docs/ reports/ backups/ …）",
         "c1c_misplaced_files", cur["c1"]["misplaced"]),
        ("C2", "测试未接入执行（tests/ 下不可达）",
         "c2_unwired_tests", cur["c2"]["findings"]),
        ("C3b", f"文档硬写的 AHK 基线数字（应指向 test-map，当前权威 {cur['c3b']['total']}）",
         "c3b_stale_counts", cur["c3b"]["findings"]),
    ]
    for tag, desc, bkey, findings in sections:
        if tag[:2].lower() not in want and tag.lower() not in want:
            continue
        if base is None:
            print(f"\n[{tag}] {desc}：{len(findings)} 项")
            for f in findings:
                print(f"       - {f}")
            continue
        new, kept, fixed = diff_set(base.get(bkey), findings)
        new_all.extend(new)
        print(f"\n[{tag}] {desc}：当前 {len(findings)} 项"
              f"（新增 {len(new)} / 已登记 {len(kept)} / 已清理 {len(fixed)}）")
        for f in new:
            print(f"       [NEW] {f}")
        for f in fixed:
            print(f"       [已清理] {f}   ← 记得 --update-baseline 收紧水位")

    print()
    if args.show or base is None:
        print("-" * 60)
        print(f"[C1] 语料 {cur['c1']['corpus']} 个 AHK 文件，"
              f"其中 {cur['c1']['unresolved_includes']} 条 #Include 未解析到语料内（多为注释或已删目标）")
        print(f"[C2] tests/ 语料 {cur['c2']['corpus']} 个，"
              f"从 run_all_tests/run_tests 可达 {cur['c2']['reachable']} 个")
        print("\n[SKIP] 未与基线比对，不做通过/失败判定")
        return 0

    errors: list[str] = []
    if new_all:
        errors.append(f"新增技术债 {len(new_all)} 项（见上方 [NEW]）")
    if "c3" in want and c3_errors:
        errors.append(f"文档-代码一致性 {len(c3_errors)} 处不一致")
    if "c4" in want and c4_findings:
        errors.append(f"禁止加代码的空占位目录被写入 {len(c4_findings)} 处（C4）")
    if "c5" in want and c5_findings:
        errors.append(f"workspace 成员目录下有冗余 Cargo.lock {len(c5_findings)} 处（C5）")

    if errors:
        print("[FAIL] 技术债检查未通过:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("[PASS] 技术债检查通过：无新增债、文档与代码一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
