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
  C4 占位目录守卫：`src-tauri/src/{application,domain}/` 禁止放任何文件。
  C5 冗余 Cargo.lock：workspace 成员目录下不得有 Cargo.lock。
  C6 vendored 引擎纯净性：`AutoHotkey-2.0.26/` 必须与官方 v2.0.26 不多不少不改。
  C7 布尔契约同步：Rust 侧 `bool` 字段（含 `Option<bool>`）的 JSON 键名，必须都登记在
     AHK `JSONSerializer.BoolKeys` 白名单里。
     —— 起因（TD-030）：AHK v2 没有布尔类型，`Type(true)` 是 "Integer"，
     序列化器只能靠**键名**判断 JSON 布尔；白名单漏一个键，该字段就会被写成
     0/1，Rust 侧 serde 直接 `invalid type`。以 Rust 契约为事实源反向校验白名单。
  C10 三处门禁档位一致：`scripts/check-gates.sh` / `scripts/check-gates.ps1` /
     `.github/workflows/ci.yml` 里同一个闸门的档位必须一致。现覆盖两个探针：
     G3d（`check-test-map.py` 的 `--no-cargo` 有无）与 G3i（`build_graph.py`
     的 `--selftest` 有无）。
     —— 起因（TD-055）：`.sh` 与 `ci.yml` 已切完整模式（含运行时对账），`.ps1`
     却仍是 `--no-cargo` 快速档，于是运行期对账在唯一能开发的平台（Windows）
     上从未真正执行过 —— 守护看着在跑，防的不是它声称防的东西。
     ⚠️ 判据每次从三份文件里正则提取后**互比**，脚本里**不存**「标准档位清单」：
     否则那份清单就成了第五份权威副本，与本检要消灭的漂移是同一类错误。
     本检只管**是否漂移**、不管取哪个值 —— 要整体切档就三处一起改。
  C11 打包资源清单同步：以 `asd-tauri/src-tauri/ahk_executor/*.ahk` 里的 `#Include`
     为事实源，反向校验 `tauri.conf.json` 的 `bundle.resources` 必须覆盖全部被
     引用的**同目录** `.ahk`。
     —— 起因：resources 漏了 `high_res_clock.ahk`，而 `sender.ahk:16` /
     `joystick.ahk:18` 都要 include 它，于是**任何干净的打包构建**（CI 全新
     checkout 或用户拿到安装包）执行器都会**启动即崩**；开发机因为有本地编译的
     `asd_executor.exe` 兜底，本机永远测不出来（与 TD-046 同家族）。
  C12 正式配置不得开调试端口：`asd-tauri/src-tauri/tauri.conf.json` 里**不得出现**
     `--remote-debugging-port`（E2E 专用配置 `tauri.e2e.conf.json` **不查**，它是
     刻意开端口的地方）。
     —— 起因：E2E 要靠 `--remote-debugging-port` 才能让 msedgedriver 挂上 WebView2，
     但这个开关一旦混进正式配置，**分发给用户的 release 产物就会带着远程调试端口**，
     那是安全红线而不只是配置噪声。两个配置长得几乎一样、只差一个字段，
     人眼分不出来，故必须由机器守住。
  C13 台账结构自洽：`docs/tech-debt-register.md` 的**结构**（统计行汇总数 /
     状态词是否在「状态流转」词表内 / 豁免·待定是否附到期日 / 档位格是否纯）
     此前零守卫 —— C9 只校验 DPI·档位这类**数值**是否自洽，行里写什么状态词、
     统计行报几个数，它一概不看。
     —— 起因（2026-09-18 实测）：统计行声明「P0 23 / P1 18 / P2 17 / 合计 58」，
     清单实际是 P0 24 / P1 21 / P2 17 / 合计 **62**；62 行里出现 11 种状态写法，
     而「状态流转」章节只声明 6 种；台账第 5 行要求豁免/待定必须附**到期日**，
     这条规则同样零守卫。与 C9 同族：**度量看着在管，实际管的是另一个东西**。
     ⚠️ 与 C10 同一条教训：判据**一律从台账里提取**（状态词表取自「## 状态流转」
     章节的代码块，统计口径取自「**统计**：」行），再与清单实际行互比 ——
     脚本里**不存**期望值清单，否则那份清单就成了第二份权威副本。

棘轮（ratchet）语义
--------------------
C1/C2 的现状是**存量债**，不可能一次清零。所以脚本不要求「当前为 0」，只要求
「**不比基线更差**」：

  - 出现在基线里、现在还在  → 计为「已登记」，不报错（但要能看见）
  - 出现在基线里、现在没了  → 计为「已清理」，报喜
  - 不在基线里、现在出现了  → **新增债 → FAIL**（这就是闸门的意义）
  - 想主动下调水位：清理掉若干项后跑 `--update-baseline`，把新的（更小的）集合
    冻结为新基线。基线文件 diff 会出现在 CR 里，收紧必须过 review。

C3 / C4 / C5 / C6 / C7 / C8 / C9 / C10 / C11 / C12 / C13 不做棘轮：它们守的是**规则**（文档与代码
必须一致 / 占位目录不得放文件 / 成员目录不得有冗余 lock / vendored 引擎树必须与上游
一致 / 布尔契约必须同步 / 三处门禁档位必须一致 / 打包资源必须覆盖被引用的文件 /
正式配置不得开调试端口 / 台账结构必须自洽），没有「先记账以后再说」的余地。

用法：
    python scripts/check-tech-debt.py                  # 三检 + 与基线比对（CI 用这个）
    python scripts/check-tech-debt.py --show           # 只打印当前结果，不与基线比对
    python scripts/check-tech-debt.py --update-baseline
    python scripts/check-tech-debt.py --only c13       # 只跑某一检（c1…c13）

退出码：0 = 通过；1 = 有新增债或一致性错误。
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import math
import re
import subprocess
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
VENDOR_DIR = "AutoHotkey-2.0.26"
VENDOR_BASELINE = REPO_ROOT / "scripts" / "vendor-baseline-ahk-2.0.26.txt"
DELETED_MARK = "<deleted>"   # 已跟踪但工作区里不存在

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


def _standalone_roots(repo_root: Path, allset: set[Path]) -> list[Path]:
    """从 `scripts/run-standalone-ahk-tests.sh` 的 SCRIPTS 列表里取独立 runner 脚本。

    C2 的判据原本只认 `run_all_tests.ahk` / `run_tests.ahk` 两个 runner 的 `#Include`
    链。但另有一批脚本是**各自独立进程**跑的（全局状态互相污染，合进一个 runner 会
    互相干扰），由 `run-standalone-ahk-tests.sh` 串起来并接入四闸门 **G3g** —— 它们
    确实在执行，只是不走 `#Include` 链。不认这条来源会把「已接入」误报成「未接入」
    （2026-09-17 实测：C2 的 8 项里 **7 项是误报**）。

    只取 `tests/` 语料内的（`allset`），`tools/` 下的那条不在 C2 的统计范围里。
    """
    sh = repo_root / "scripts" / "run-standalone-ahk-tests.sh"
    if not sh.exists():
        return []
    try:
        text = sh.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    out: list[Path] = []
    for line in text.splitlines():
        s = line.strip().strip('"')
        if s.endswith(".ahk") and "/" in s:
            p = (repo_root / s).resolve()
            if p in allset and p not in out:
                out.append(p)
    return out


def check_c2(repo_root: Path) -> dict:
    tests_dir = repo_root / "tests"
    files = [p for p in collect_ahk(repo_root) if str(p.resolve()).startswith(str(tests_dir.resolve()))]
    allset = set(files)
    _inbound, edges, _unres = build_include_graph(files, repo_root)

    roots = [(tests_dir / "run_all_tests.ahk").resolve(),
             (tests_dir / "run_tests.ahk").resolve()]
    roots = [r for r in roots if r in allset]
    roots += _standalone_roots(repo_root, allset)
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
                # ⚠️ finding 里**不能**写当前权威数字 total：它被当作基线项的身份。
                # 一旦写进去，AHK 用例总数每变一次（697→707），同一批历史豁免就会
                # 全部变成「新增债」而 FAIL，把人训练成无脑 --update-baseline。
                # 身份只认「路径:行号 + 硬写的数字」，与 total 无关。
                findings.append(
                    f"{rel(p)}:{i}: 硬写「{n} / {n}」"
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

# --------------------------------------- C6 vendored 引擎树纯净性（TD-010）
#
# `AutoHotkey-2.0.26/` 是**只读研究参考**，不是构建依赖：
#   - `docs/research/ahk-engine-architecture-2026-09-14.md` 对它做了 **60+ 处行级引用**
#     （`script.cpp:9840`、`hotkey.cpp:202` …），涉及 20 个文件。它是可复核的证据。
#   - CI **完全不碰它**（CI 用的是 `asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe`）。
#
# 这条检查守两件事：
#   1. **不被污染**。2026-09 清理时发现目录里混进了 **40 个本项目的实验残留**，其中还有
#      `source/.claude/CLAUDE.md`（外部 AI 工具的编排指令）与 `source/.omc/state/setup-state.json`。
#      放在 vendored 源码里，AI 工具会把它当项目指令读 —— 这是**会改变行为的污染**，不只是碍眼。
#   2. **不被篡改**。一旦有人顺手改了引擎源码，「这是 v2.0.26」这句话就失效，研究报告里
#      60+ 处行号引用随之失真，而且失真**不会有任何报错**。
#
# 基线刻意来自**上游官方仓库**（tag v2.0.26，commit 542510f）而不是本地快照：
# 若取本地快照，一旦本地已被污染，污染就会被固化进基线、从此永远通过。
# 校验的是「本地 == 官方 v2.0.26」，不是「本地 == 本地上一次的样子」。
#
# 与 C3–C13 的其它硬失败项同属**硬失败、不做棘轮**：这守的是规则，不是存量债。


def _load_vendor_baseline(path: Path) -> dict[str, str]:
    """读基线清单 → {相对 VENDOR_DIR 的路径: blob-sha}。跳过空行与 # 注释。"""
    out: dict[str, str] = {}
    for ln, line in enumerate(read_text(path).splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split(None, 1)
        if len(parts) != 2:
            raise ValueError(f"{rel(path)}:{ln} 格式错误（应为 '<sha>  <path>'）：{line!r}")
        sha, p = parts[0], parts[1].strip()
        if len(sha) != 40:
            raise ValueError(f"{rel(path)}:{ln} sha 不是 40 位十六进制：{sha!r}")
        out[p.replace("\\", "/")] = sha
    return out


def _git_lines(repo_root: Path, args: list[str]) -> list[str]:
    r = subprocess.run(["git", *args], cwd=repo_root, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} 失败：{r.stderr.strip()}")
    return [ln for ln in r.stdout.splitlines() if ln.strip()]


def _vendor_present(repo_root: Path) -> dict[str, str]:
    """vendor 目录里「git 认为属于仓库」的文件 → {相对路径: 内容 sha}。

    **路径口径**：git 自己的，不裸扫文件系统。
      - 已跟踪：`git ls-files -s`
      - 未跟踪但**未被 ignore**：`git ls-files --others --exclude-standard`
        （还没提交、但 `git status` 看得见 —— 属于正要被提交进去的污染）
      - 被 ignore 的本机产物（`AutoHotkey.exe`、`*.log`）：**不管**。
        它们只在本地存在，CI 全新 checkout 没有；管了就会出现「本地恒红、CI 恒绿」，
        那种门禁会被人学会无视。

    **内容口径**：**工作区**文件的 hash（`git hash-object`，与 .gitattributes 同一套归一化），
    不是索引。这一点是实测踩出来的：用 `ls-files -s` 的索引 sha 时，「改了引擎源码但还没
    git add」完全抓不到（阳性对照注入后仍然全绿）——而那正是本条要防的顺手篡改；
    等它进了索引，错误已经提交出去了。
    """
    rel_paths: list[str] = []
    seen: set[str] = set()
    for line in _git_lines(repo_root, ["ls-files", "-s", VENDOR_DIR]):
        p = line.split("\t", 1)[1].replace("\\", "/")
        if p.startswith(VENDOR_DIR + "/") and p not in seen:
            seen.add(p)
            rel_paths.append(p)
    untracked: set[str] = set()
    for line in _git_lines(
        repo_root, ["ls-files", "--others", "--exclude-standard", VENDOR_DIR]
    ):
        p = line.strip().replace("\\", "/")
        if p.startswith(VENDOR_DIR + "/") and p not in seen:
            seen.add(p)
            untracked.add(p)
            rel_paths.append(p)

    rel_paths.sort()
    out: dict[str, str] = {}
    for p in rel_paths:
        if not (repo_root / p).is_file():
            out[p[len(VENDOR_DIR) + 1:]] = DELETED_MARK      # 已跟踪但工作区里没了
    on_disk = [p for p in rel_paths if (repo_root / p).is_file()]
    if on_disk:
        r = subprocess.run(
            ["git", "hash-object", "--stdin-paths"],
            cwd=repo_root, input="\n".join(on_disk),
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            raise RuntimeError(f"git hash-object 失败：{r.stderr.strip()}")
        shas = [x.strip() for x in r.stdout.splitlines() if x.strip()]
        if len(shas) != len(on_disk):
            raise RuntimeError(
                f"git hash-object 返回 {len(shas)} 行，期望 {len(on_disk)} 行"
            )
        for p, s in zip(on_disk, shas):
            out[p[len(VENDOR_DIR) + 1:]] = s
    return out


def check_c6(repo_root: Path) -> dict:
    """vendored AHK 引擎树必须与官方 v2.0.26 完全一致：不多、不少、不改。"""
    empty = {"checked": 0, "present": 0,
             "extra": [], "missing": [], "changed": [], "deleted": []}
    if not VENDOR_BASELINE.exists():
        return {"findings": [f"基线清单缺失：{rel(VENDOR_BASELINE)}（C6 无法校验）"], **empty}
    try:
        want = _load_vendor_baseline(VENDOR_BASELINE)
        have = _vendor_present(repo_root)
    except Exception as e:                      # 门禁自身坏了必须响亮失败
        return {"findings": [f"C6 自身执行失败：{e}"], **empty}

    deleted = sorted(p for p, s in have.items() if s == DELETED_MARK)
    have_c = {p: s for p, s in have.items() if s != DELETED_MARK}

    extra = sorted(set(have_c) - set(want))
    missing = sorted((set(want) - set(have_c)) - set(deleted))
    changed = sorted(p for p in (set(want) & set(have_c)) if want[p] != have_c[p])

    findings: list[str] = []
    for p in extra:
        findings.append(
            f"{VENDOR_DIR}/{p} 不在官方 v2.0.26 清单里 —— 非引擎源码，请移出该目录"
        )
    for p in missing:
        findings.append(f"{VENDOR_DIR}/{p} 缺失（官方 v2.0.26 有此文件）")
    for p in deleted:
        findings.append(
            f"{VENDOR_DIR}/{p} 已跟踪但工作区里不存在 —— 引擎源码只读，不要删"
        )
    for p in changed:
        findings.append(
            f"{VENDOR_DIR}/{p} 内容与官方 v2.0.26 不一致 —— 引擎源码只读，禁止修改"
        )

    return {"findings": findings, "checked": len(want), "present": len(have),
            "extra": extra, "missing": missing, "changed": changed, "deleted": deleted}


# ---------------------------------------------------------------- C7 常量
AHK_SERIALIZER = Path("infrastructure") / "json_serializer.ahk"
CRATES_SRC = Path("asd-tauri") / "crates"

# `pub foo: bool` / `pub foo: Option<bool>`
RUST_BOOL_FIELD_RE = re.compile(
    r"^\s*pub\s+(\w+)\s*:\s*(?:Option<\s*)?bool\s*>?\s*,", re.M)
RUST_RENAME_RE = re.compile(r"rename\s*=\s*\"([^\"]+)\"")
AHK_BOOL_KEYS_RE = re.compile(r"static\s+BoolKeys\s*:=\s*Map\((.*?)\)", re.S)

# 纯 Rust 内部、不经 AHK 序列化的布尔字段（附理由才允许登记）
C7_EXEMPT: dict[str, str] = {}


def _snake_to_camel(name: str) -> str:
    head, *rest = name.split("_")
    return head + "".join(w.capitalize() for w in rest)


def _ahk_bool_keys(repo_root: Path) -> set[str]:
    path = repo_root / AHK_SERIALIZER
    if not path.exists():
        return set()
    m = AHK_BOOL_KEYS_RE.search(read_text(path))
    if not m:
        return set()
    return set(re.findall(r'"([^"]+)"', m.group(1)))


def _attr_balanced(buf: str) -> bool:
    return buf.count("[") > 0 and buf.count("[") == buf.count("]")


def _rust_bool_fields(repo_root: Path) -> dict[str, list[str]]:
    """返回 {json 键名: [来源:行]}，键名取 serde rename，无 rename 则 snake→camel。

    ⚠️ rename 必须与**紧邻其上的那个属性块**配对。早期版本回看固定行数取第一个
    rename，会把上一个字段的重命名错配过来（实测把 releaseOnEmergency 报成
    debounceDelay），那种误报会让人直接关掉这条检查。
    """
    out: dict[str, list[str]] = {}
    crates_dir = repo_root / CRATES_SRC
    if not crates_dir.exists():
        return out
    for rs in sorted(crates_dir.glob("*/src/**/*.rs")):
        try:
            lines = read_text(rs).splitlines()
        except Exception:
            continue
        pending: list[str] = []      # 正在累积的属性块（可能跨行）
        rename: str | None = None    # 最近一个完整属性块给出的 rename
        for lineno, line in enumerate(lines, 1):
            s = line.strip()
            if pending or s.startswith("#["):
                pending.append(line)
                if _attr_balanced("\n".join(pending)):
                    m = RUST_RENAME_RE.search("\n".join(pending))
                    rename = m.group(1) if m else None
                    pending = []
                continue
            if s == "" or s.startswith("//"):
                continue
            m = RUST_BOOL_FIELD_RE.match(line)
            if m:
                key = rename if rename else _snake_to_camel(m.group(1))
                out.setdefault(key, []).append(f"{rel(rs)}:{lineno}")
            rename = None
    return out


def check_c7(repo_root: Path) -> dict:
    """C7 布尔契约同步：Rust 的 bool 字段必须都在 AHK 的 BoolKeys 白名单里。

    AHK v2 没有布尔类型（`Type(true) == "Integer"`），序列化器只能靠**键名**判断
    JSON 布尔（见 TD-030）。白名单漏一个键，该字段就会被写成 0/1，Rust 侧 serde
    直接 `invalid type` 失败。这里把 Rust 侧契约当唯一事实源，反向校验白名单。
    """
    ahk_keys = _ahk_bool_keys(repo_root)
    rust_keys = _rust_bool_fields(repo_root)

    findings: list[str] = []
    if not ahk_keys:
        findings.append(
            f"{rel(repo_root / AHK_SERIALIZER)}: 未能解析出 JSONSerializer.BoolKeys "
            f"（C7 无法校验，按失败处理）"
        )
    if not rust_keys:
        findings.append(
            f"{rel(repo_root / CRATES_SRC)}: 未扫描到任何 Rust bool 字段"
            f"（C7 无法校验，按失败处理）"
        )

    for key in sorted(set(rust_keys) - ahk_keys - set(C7_EXEMPT)):
        src = "、".join(rust_keys[key][:3])
        findings.append(
            f"Rust 布尔字段 `{key}`（{src}）不在 AHK 的 JSONSerializer.BoolKeys 里 "
            f"—— 会被序列化成 0/1，Rust 侧 serde 报 invalid type。请加入白名单"
        )
    for key in sorted(C7_EXEMPT):
        if key not in rust_keys:
            findings.append(f"C7_EXEMPT 里的 `{key}` 已无对应 Rust 字段，请删除该豁免")

    return {"findings": findings, "ahk_keys": sorted(ahk_keys),
            "rust_keys": sorted(rust_keys), "checked": len(rust_keys)}


# ---------------------------------------------------------------- C8 IPC 命令契约


def _snake(name: str) -> str:
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()


def _rust_ipc_actions(repo_root: Path) -> dict[str, str]:
    """解析 Rust `IpcCommand` 各变体的**序列化名**（`#[serde(rename = "...")]`）。

    变体名（PascalCase）不等于线上字符串，必须取 serde 的 rename —— 拿变体名去
    比对会得到一堆假阳性。
    """
    p = repo_root / "asd-tauri" / "crates" / "asd-ipc-protocol" / "src" / "command.rs"
    if not p.is_file():
        return {}
    m = re.search(r'pub enum IpcCommand\s*\{(.*?)\n\}', read_text(p), re.S)
    if not m:
        return {}
    out: dict[str, str] = {}
    pending: str | None = None
    for ln in m.group(1).splitlines():
        s = ln.strip()
        if not s or s.startswith('//'):
            continue
        r = re.match(r'#\[serde\(\s*rename\s*=\s*"([^"]+)"\s*\)\]', s)
        if r:
            pending = r.group(1)
            continue
        if s.startswith('#'):
            continue
        v = re.match(r'([A-Z][A-Za-z0-9]*)', s)
        if v:
            out[v.group(1)] = pending or _snake(v.group(1))
            pending = None
    return out


def _ahk_ipc_actions(repo_root: Path) -> set[str]:
    """解析 AHK 侧能处理的 action 集合。

    两处来源：
      - `executor.ahk` 的 `CommandDispatcher.Dispatch` —— 业务命令（11 条）
      - `ipc_client.ahk` 的 `case "ping"` / `case "shutdown"` —— 协议消息，
        走 msgType 路径而非 command 路径（另有防御性路由兜底）
    两者合起来才是 AHK 侧真正能响应的全部 action。
    """
    actions: set[str] = set()
    exe = repo_root / "asd-tauri" / "src-tauri" / "ahk_executor" / "executor.ahk"
    if exe.is_file():
        txt = read_text(exe)
        m = re.search(r'static Dispatch\s*\(.*?\n(.*?)\n\s{4}\}', txt, re.S)
        seg = m.group(1) if m else txt
        actions |= set(re.findall(r'case\s+"([a-z0-9_]+)"\s*:', seg))
    cli = repo_root / "asd-tauri" / "src-tauri" / "ahk_executor" / "ipc_client.ahk"
    if cli.is_file():
        for a in re.findall(r'case\s+"([a-z0-9_]+)"\s*:', read_text(cli)):
            if a in ("ping", "shutdown"):
                actions.add(a)
    return actions


def check_c8(repo_root: Path) -> dict:
    """C8 IPC 命令契约对齐（TD-057）：Rust 变体 ↔ AHK 分发表，双向都不能缺。

    这是图谱审查方法里的**契约断点**靶点：跨 AHK / Rust 边界的命令名靠两边手写
    字符串对齐，此前**没有任何门禁**。Rust 加一个变体而 AHK 忘了接，编译期不会
    报错，只有运行时才吐「未知命令」—— 典型的结构性静默失效。

    硬失败（失败即视为无效，不静默放过）：
      - 两侧任一解析不出内容
      - Rust 有而 AHK 分发表没有（命令到了会被回成「未知命令」）
      - AHK 分发表有而 Rust 没有（死分支）
    """
    rust = _rust_ipc_actions(repo_root)
    ahk = _ahk_ipc_actions(repo_root)

    findings: list[str] = []
    if not rust:
        findings.append("未能解析出 Rust `IpcCommand` 变体（C8 无法校验，按失败处理）")
    if not ahk:
        findings.append("未能解析出 AHK 侧 action 分发表（C8 无法校验，按失败处理）")

    if rust and ahk:
        want = set(rust.values())
        for a in sorted(want - ahk):
            variant = next(v for v, n in rust.items() if n == a)
            findings.append(
                f"Rust `IpcCommand::{variant}`（序列化为 `{a}`）在 AHK 分发表里**没有对应分支** "
                f"—— 命令到达时只会回「未知命令」。请在 executor.ahk 的 Dispatch 里补上，"
                f"或若属 ping/shutdown 类协议消息则在 ipc_client.ahk 处理"
            )
        for a in sorted(ahk - want):
            findings.append(
                f"AHK 分发表里的 `{a}` 在 Rust `IpcCommand` 里**没有对应变体** —— 是死分支，"
                f"请删除或补上 Rust 侧定义"
            )

    return {"findings": findings, "rust_actions": sorted(rust.values()),
            "ahk_actions": sorted(ahk), "checked": len(rust)}


# ---------------------------------------------------------------- C9 台账评分自洽
_REGISTER = "docs/tech-debt-register.md"


def _tier_of(d: float) -> str:
    """档位落档阈值（台账表头明文：P0 ≥10 / P1 5–10 / P2 2–5 / P3 <2）。"""
    if d >= 10:
        return "P0"
    if d >= 5:
        return "P1"
    if d >= 2:
        return "P2"
    return "P3"


def _cell_num(s: str):
    """取单元格开头的数字。DPI 列可能带「**（+ 硬性升档：…）」后缀，档位列可能带括号后缀。"""
    m = re.match(r"^\**\s*([0-9]+(?:\.[0-9]+)?)", s.strip())
    return float(m.group(1)) if m else None


def check_c9(repo_root: Path) -> dict:
    """C9 技术债台账评分自洽（2026-09-18 新增）。

    台账 `docs/tech-debt-register.md` 是技术债的**唯一登记处**，但在本检加入之前，
    它的 DPI 与档位**从来没有被任何东西校验过** —— 2026-09-18 用台账自己第 12 行
    声明的公式反算，58 行里 **12 行对不上**（其中 TD-056 声明 3.0 / 公式 10.0，
    整整差一个档位）。这是典型的「度量失守」：数字看着在管，实际管的是另一个东西。

    与 C3–C13 的其它硬失败项同类：**硬失败、不做棘轮** —— 守的是规则不是存量债。

    校验三条：
      1. `DPI == (I + P + V + S) / ( √C × R )`（容差 0.06，容忍台账保留一位小数）
      2. 档位 == 由 DPI 落档的结果（P0 ≥10 / P1 5–10 / P2 2–5 / P3 <2）
      3. 行结构完整（15 段；缺「阶段」列即按失败处理，不静默放过）
    """
    reg = repo_root / _REGISTER
    findings: list[str] = []
    checked = 0

    if not reg.exists():
        return {"findings": [f"台账 `{_REGISTER}` 不存在（C9 无法校验，按失败处理）"],
                "checked": 0, "rows": 0}

    for lineno, line in enumerate(
            reg.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.startswith("| TD-"):
            continue
        checked += 1
        cells = [x.strip() for x in line.split("|")]
        tid = cells[1] if len(cells) > 1 else f"第 {lineno} 行"

        if len(cells) < 14:
            findings.append(
                f"{tid}：行结构不完整（{len(cells)} 段，应为 15 段）—— 缺「阶段」列，"
                f"请补齐（邻居同批行的阶段值见 TD-008 / TD-010）"
            )
            continue

        nums = [_cell_num(cells[i]) for i in range(4, 10)]
        dpi = _cell_num(cells[10])
        tier = cells[11].replace("*", "").strip()

        if any(v is None for v in nums) or dpi is None:
            findings.append(
                f"{tid}：I/P/V/S/C/R 或 DPI 解析不出数值（C9 无法校验，按失败处理）—— "
                f"实际为 {cells[4:11]}"
            )
            continue

        impact, pace, verify, strat, cost, risk = nums
        if cost <= 0 or risk <= 0:
            findings.append(f"{tid}：C(成本) 与 R(风险系数) 必须为正数，实际 C={cost} R={risk}")
            continue

        expect = (impact + pace + verify + strat) / (math.sqrt(cost) * risk)
        if abs(expect - dpi) >= 0.06:
            findings.append(
                f"{tid}：DPI 与公式不符 —— 台账写 {dpi}，"
                f"按 `DPI=(I+P+V+S)/(√C×R)` 算应为 **{expect:.2f}**"
                f"（I={impact:g} P={pace:g} V={verify:g} S={strat:g} C={cost:g} R={risk:g}）"
            )

        want_tier = _tier_of(dpi)
        if tier[:2] != want_tier:
            findings.append(
                f"{tid}：档位与 DPI 不符 —— DPI {dpi} 按阈值应落 **{want_tier}**，"
                f"台账写 **{tier[:2]}**"
                + ("（若为有意覆盖，须按台账第 19 行的规矩写明「硬性升档」理由，如 "
                   "`**22.6**（+ 硬性升档：数据丢失）`，否则一律视为漏填）")
            )

    return {"findings": findings, "checked": checked, "rows": checked}


# ---------------------------------------------------------------- C10 三处门禁档位一致
# ⚠️ 这里**故意**不写「标准档位应该是完整模式」。判据必须每次从三份文件里正则提取后
#    互比 —— 一旦脚本里存一份期望值，那份清单就成了第五份权威副本，与本检要消灭的
#    漂移是同一类错误（TD-055 的根因恰恰是「多份权威、各说各话」）。
#    清单里列的只是**要比对的地点**，不是要比对的**期望值**。
C10_SITES = [
    "scripts/check-gates.sh",
    "scripts/check-gates.ps1",
    ".github/workflows/ci.yml",
]
# 探针：(闸门 ID, 被调脚本路径片段, 判定档位的标志, 带标志时档位名, 缺标志时档位名)
#   · 被调脚本片段就是闸门的身份标识 —— 改名即视为闸门消失（硬失败）。
#   · 判定用「**标志存在与否**」而不是「调用命令全文」：三处门禁的 shell 语法天然
#     不同（.sh 用 `env CARGO_INCREMENTAL=0 "$PY" …`、.ps1 用 `& $script:Py (Join-Path …)`、
#     ci.yml 用 `python …`），比全文必然全是假阳性。标志是与 shell 无关的语义量。
C10_PROBES = [
    ("G3d", "check-test-map.py", "--no-cargo",
     "QUICK(--no-cargo)", "FULL(含运行时对账)"),
    ("G3i", ".review-analysis/build_graph.py", "--selftest",
     "SELFTEST(带 --selftest)", "BUILD-ONLY(缺 --selftest)"),
]


def _c10_invocations(path: Path, needle: str, flag: str,
                     mode_on: str, mode_off: str) -> list[tuple[str, int, str]]:
    """从单个门禁文件里提取某个闸门（按其被调脚本片段识别）的调用行及档位。

    返回 [(档位, 行号, 原文)]。只认**调用行**：
      - 以 `#` 开头的整行注释跳过（`.sh` 里就有一句"2026-09-18 起不再用
        --no-cargo"的历史说明，被当成当前档位就会误判）；
      - 行尾 ` #...` 注释在匹配前截掉，避免把注释里提到的参数算进来。
    """
    hits: list[tuple[str, int, str]] = []
    for lineno, raw in enumerate(read_text(path).splitlines(), start=1):
        s = raw.strip()
        if s.startswith("#") or s.startswith("<#"):
            continue
        body = s.split(" #", 1)[0]
        if needle not in body:
            continue
        hits.append((mode_on if flag in body else mode_off, lineno, s))
    return hits


def check_c10(repo_root: Path) -> dict:
    """C10 三处门禁档位一致（TD-055 起；2026-09-18 扩展到 G3i）。

    同一个闸门在 `.sh` / `.ps1` / `ci.yml` 三处各有一份调用。2026-09-18 实测 G3d
    这三份已经漂移：`.sh` 与 `ci.yml` 是完整模式（真的跑 `cargo test --list` 对账
    运行期数字），`.ps1` 是 `--no-cargo` 快速档（只查文档内部自洽）。Windows 是本
    项目唯一能真正开发的平台（AHK 只能在 Windows 跑），于是收益恰好在唯一能开发的
    平台上拿不到。G3c 也发生过同一形状的事（漏扫 `src/__tests__`）。

    与 C3–C13 的其它硬失败项同类：**硬失败、不做棘轮** —— 守的是规则。

    每个探针校验两条：
      1. 三处都能提取到该闸门的调用，且每处**恰好一处**（0 处 = 闸门被删/改名；
         多处 = 无法判定哪份生效，都按失败处理，不静默放过）
      2. 三处档位**互比一致**。本检**不管取哪个值** —— 三处一起切成 `--no-cargo`
         也会通过，那是人的决定，不是漂移。

    ⚠️ **为什么不做成「任一闸门的调用命令必须一致」**：三处 shell 语法天然不同，
    比全文必是假阳性（G3c 在 .sh 里是 shell 通配、在 .ps1 里是 Get-ChildItem，
    语义等价、文本不同）；改成比「闸门 ID 集合是否齐备」也不行 —— G3g 只在
    .sh/ci.yml、G3f/G3h 只在 ci.yml，属**既有且已接受的差异**，一上就红，要压下去
    就得维护豁免清单，而豁免清单正是本检要消灭的假权威副本。故只把同一套互比机制
    用在"能用与 shell 无关的标志判定"的闸门上。
    """
    findings: list[str] = []
    table: list[tuple[str, str, str, int]] = []  # (闸门, 文件, 档位, 行号)

    for gid, needle, flag, mode_on, mode_off in C10_PROBES:
        per_probe: list[tuple[str, str, int]] = []  # (文件, 档位, 行号)
        for relpath in C10_SITES:
            p = repo_root / relpath
            if not p.exists():
                findings.append(f"{gid} / {relpath}：文件不存在（C10 无法校验，按失败处理）")
                continue
            hits = _c10_invocations(p, needle, flag, mode_on, mode_off)
            if len(hits) == 0:
                findings.append(
                    f"{gid} / {relpath}：未找到对 `{needle}` 的调用行 —— "
                    f"闸门被删了还是脚本改名了？（C10 无法校验，按失败处理）"
                )
                continue
            if len(hits) > 1:
                findings.append(
                    f"{gid} / {relpath}：找到 {len(hits)} 处 `{needle}` 调用（行 "
                    f"{'、'.join(str(h[1]) for h in hits)}）—— 档位互比要求每处唯一，"
                    f"请合并，或让多余的那处不参与门禁"
                )
                continue
            mode, lineno, _ = hits[0]
            per_probe.append((relpath, mode, lineno))
            table.append((gid, relpath, mode, lineno))

        modes = {m for _, m, _ in per_probe}
        if len(modes) > 1:
            detail = "；".join(f"{rp}:{ln} = {m}" for rp, m, ln in per_probe)
            majority = max(modes, key=lambda m: sum(1 for _, mm, _ in per_probe if mm == m))
            odd = [f"{rp}:{ln}" for rp, m, ln in per_probe if m != majority]
            findings.append(
                f"{gid} 档位在三处门禁间漂移（{detail}）—— "
                f"少数派：{'、'.join(odd)}（其余为 {majority}）。"
                f"三处必须一致；⚠️ 本检只管一致、不管取值，确认要整体切档就三处一起改。"
            )

    return {"findings": findings, "checked": len(table), "table": table}


# ---------------------------------------------------------------- C11 打包资源清单同步
# 以 `ahk_executor/*.ahk` 里的 `#Include` 为**事实源**，反向校验
# `tauri.conf.json` 的 `bundle.resources` 必须覆盖全部被引用的**同目录** `.ahk`。
#
# 起因（2026-09-18，第六道死因真因）：`bundle.resources` 只列了 7 项，漏了
# `high_res_clock.ahk`；而 `sender.ahk:16` 与 `joystick.ahk:18` 都要 `#Include`
# 它。于是**任何干净的打包构建**（CI 全新 checkout，或用户拿到 release 安装包 ——
# 那时没有本地编译的 `asd_executor.exe` 兜底，`resolve_ahk_executor_path` 走便携
# 模式）都会在 `executor.ahk → sender.ahk → #Include high_res_clock.ahk` 这一步
# **启动即崩**。⚠️ 不只是 CI 问题：分发给用户的安装包里执行器同样会崩。
#
# 为什么一直没人发现：开发机上有本地编译的 `asd_executor.exe`（Ahk2Exe 把
# `#Include` 全打进 exe），`resolve_ahk_executor_path` **优先**用它，于是便携模式
# 这条路径在本机从不执行 —— 与 TD-046 同一家族的病：**有一条路径在本机永远走不到**。
C11_TAURI_CONF = "asd-tauri/src-tauri/tauri.conf.json"
C11_AHK_EXECUTOR = "asd-tauri/src-tauri/ahk_executor"
# resources 里的条目相对 `src-tauri/`，故同目录 .ahk 期望写成 `ahk_executor/<name>`
C11_RES_PREFIX = "ahk_executor/"

# ---- C12 正式配置不得开调试端口 ----
C12_TAURI_CONF = "asd-tauri/src-tauri/tauri.conf.json"
# E2E 专用配置**刻意**开端口，是 C12 唯一的合法例外，故不查它
C12_E2E_CONF = "asd-tauri/src-tauri/tauri.e2e.conf.json"
# 只盯这一个开关：E2E 需要它，正式产物绝不能有它
C12_FORBIDDEN = "--remote-debugging-port"


def _c11_norm_resources(raw) -> set[str]:
    """把 bundle.resources 归一化成可比集合（反斜杠 → 斜杠，去掉 ./ 前缀）。"""
    out = set()
    for r in raw or []:
        if not isinstance(r, str):
            continue
        s = r.replace("\\", "/").strip()
        while s.startswith("./"):
            s = s[2:]
        out.add(s.lower())
    return out


def _c11_same_dir_name(spec: str, base: Path, exe_dir: Path, repo_root: Path) -> str | None:
    """取 `#Include` 指向的**同目录** `.ahk` 文件名；不同目录 / 不是 .ahk 则返回 None。

    先走 `resolve_include`（与 C1/C2 同一套解析，负责已存在的目标）；解析不到时再按
    「裸文件名」结构判定一次 —— 这样连「引用了目录里**根本不存在**的 .ahk」也能报出来。
    那种同样是启动即崩，绝不能因为它当前不存在就静默放过（静默放过 = 假绿）。
    """
    tgt = resolve_include(base, spec, repo_root)
    if tgt is not None:
        return tgt.name if tgt.parent == exe_dir else None
    s = spec.strip().replace("/", "\\")
    if s.upper().startswith("%A_SCRIPTDIR%"):
        s = s[len("%A_SCRIPTDIR%"):].lstrip("\\")
    if not s.lower().endswith(".ahk"):
        return None
    if "\\" in s:
        return None          # 带子目录 → 不是同目录，不在本条打击面内
    return s


def check_c11(repo_root: Path) -> dict:
    """C11 打包资源清单与源码依赖同步（2026-09-18 新增）。

    `tauri.conf.json` 的 `bundle.resources` 是**手写清单**，`ahk_executor/` 下的
    `#Include` 是**代码事实** —— 两边一旦脱节，打包产物就缺文件，而缺的那一个
    恰好是启动链上的，症状是「执行器启动即崩」而不是「某个功能不可用」。
    与 C7（布尔契约）/ C8（IPC 命令契约）同类：**契约两边手写、没有守卫**。

    与 C3–C13 的其它硬失败项同类：**硬失败、不做棘轮** —— 守的是规则。

    判据（打击面刻意收窄，不扩大）：
      1. 事实源 = `ahk_executor/` 下**所有 `.ahk`** 里的 `#Include`
         （复用 `INCLUDE_RE` 与 `resolve_include`，与 C1/C2 同一套解析，不另造正则）
      2. **只管同目录**的 `.ahk`：解析后目标文件的父目录必须就是 `ahk_executor/`。
         跨目录引用（`../domain/x.ahk` 等）**不在本条范围内** —— 那些目录各自有
         自己的打包口径，混进来只会制造无法归因的噪声。
      3. 被引用但不在 `bundle.resources` 里 → **硬失败**，点名「被谁在哪一行引用」
      4. 目录里存在但**从未被任何 `#Include` 引用**的 `.ahk` → **只提示、不判失败**：
         它可能是漏 include，也可能是入口脚本（如 `executor.ahk` 由
         `asd_executor.bat` / Rust 直接拉起，本就不该有入边）—— 这需要人判，
         机器判了就是误报。
      5. 配置文件不存在 / 解析失败 / 没有 `bundle.resources` → **按失败处理**，
         不静默放过（与 C8「解析不出即失败」同一口径）。
    """
    conf = repo_root / C11_TAURI_CONF
    exe_dir = (repo_root / C11_AHK_EXECUTOR).resolve()
    findings: list[str] = []

    if not conf.exists():
        return {"findings": [f"`{C11_TAURI_CONF}` 不存在（C11 无法校验，按失败处理）"],
                "checked": 0, "advisory": [], "resources": 0}
    if not exe_dir.exists():
        return {"findings": [f"`{C11_AHK_EXECUTOR}/` 不存在（C11 无法校验，按失败处理）"],
                "checked": 0, "advisory": [], "resources": 0}

    try:
        data = json.loads(read_text(conf))
    except Exception as e:
        return {"findings": [f"`{C11_TAURI_CONF}` 解析失败：{e}（C11 无法校验，按失败处理）"],
                "checked": 0, "advisory": [], "resources": 0}

    bundle = data.get("bundle") if isinstance(data, dict) else None
    raw_res = bundle.get("resources") if isinstance(bundle, dict) else None
    if raw_res is None:
        return {"findings": [f"`{C11_TAURI_CONF}` 缺少 `bundle.resources`（C11 无法校验，按失败处理）"],
                "checked": 0, "advisory": [], "resources": 0}

    packed = _c11_norm_resources(raw_res)

    refs: dict[str, list[str]] = {}          # 被引用的文件名 -> [引用出处（文件:行）]
    present: list[str] = []                  # 目录里实际存在的 .ahk
    for p in sorted(exe_dir.glob("*.ahk")):
        present.append(p.name)
        text = read_text(p)
        for m in INCLUDE_RE.finditer(text):
            spec = m.group(1)
            name = _c11_same_dir_name(spec, p, exe_dir, repo_root)
            if name is None:
                continue                     # 跨目录 / 非 .ahk：不在本条打击面内
            lineno = text[:m.start()].count("\n") + 1
            refs.setdefault(name, []).append(f"{p.name}:{lineno}")
    present_set = set(present)

    for name in sorted(refs):
        want = C11_RES_PREFIX + name
        if want.lower() not in packed:
            srcs = "、".join(sorted(set(refs[name])))
            ghost = "" if name in present_set else \
                "（⚠️ 该文件在 `ahk_executor/` 里**不存在** —— 引用了根本没有的文件）"
            findings.append(
                f"`{name}` 被 {srcs} `#Include` 引用，但不在 `bundle.resources` 里 —— "
                f"应加 `{want}`{ghost}。⚠️ 漏它不会让某个功能不可用，而是让打包产物在"
                f"启动链上缺文件 → **执行器启动即崩**（开发机有本地编译的 "
                f"asd_executor.exe 兜底，故本机永远测不出来）"
            )

    advisory = [n for n in present if n not in refs]

    return {"findings": findings, "checked": len(refs),
            "advisory": advisory, "resources": len(raw_res)}


def check_c12(repo_root: Path) -> dict:
    """C12 正式配置不得开调试端口（2026-09-18 新增，随方案 1 一起上）。

    E2E 要靠 `--remote-debugging-port` 才能让 msedgedriver 挂上 WebView2，所以
    E2E 专用配置 `tauri.e2e.conf.json` 里**必须**有它；而正式 `tauri.conf.json`
    里**绝对不能**有 —— 有的话分发给用户的 release 产物就带着远程调试端口。

    两份配置长得几乎一样（只差一个字段 + 一个文件名），**人眼分不出来**，
    故必须由机器守住：这是典型的「两个手写副本、只靠命名约定区分」的契约断裂，
    与 C7（布尔契约）/ C8（IPC 命令契约）/ C11（打包资源清单）同族。

    与 C3–C13 的其它硬失败项同类：**硬失败、不做棘轮**。

    判据（打击面刻意收窄）：
      1. **只查** `asd-tauri/src-tauri/tauri.conf.json`；`tauri.e2e.conf.json`
         **明确不查**（它是合法开端口的地方，查它就是误报）。
      2. 扫**原始文本**而不是 JSON 解析后的值 —— 开关可能出现在任何字符串值里
         （`additionalBrowserArgs` / 注释 / 别名字段），解析后遍历会漏。
      3. 命中即硬失败，报出**行号**便于定位。
      4. 文件不存在 / 读不了 → **按失败处理**，不静默放过（与 C8/C11 同口径）：
         正式配置都不在了，说明路径变了，守卫必须响。
    """
    conf = repo_root / C12_TAURI_CONF
    findings: list[str] = []

    if not conf.exists():
        return {"findings": [f"`{C12_TAURI_CONF}` 不存在（C12 无法校验，按失败处理）"],
                "checked": 0}

    try:
        text = read_text(conf)
    except Exception as e:
        return {"findings": [f"`{C12_TAURI_CONF}` 读取失败：{e}（C12 无法校验，按失败处理）"],
                "checked": 0}

    for lineno, line in enumerate(text.splitlines(), 1):
        if C12_FORBIDDEN in line:
            findings.append(
                f"`{C12_TAURI_CONF}:{lineno}` 出现 `{C12_FORBIDDEN}` —— "
                f"正式配置**不允许**开远程调试端口：它会进 `tauri build` 的产物，"
                f"分发给用户的 release 也会带着调试端口（安全红线）。"
                f"E2E 需要它请写到 `{C12_E2E_CONF}`，并用 "
                f"`tauri build --config` 走测试专用配置。"
            )

    return {"findings": findings, "checked": 1}


# ---------------------------------------------------------------- C13 台账结构自洽
# 台账 `docs/tech-debt-register.md` 的**结构**（统计行 / 状态词 / 豁免到期日 / 档位格纯度）
# 此前零守卫：C9 只看 DPI 与档位这类**数值**是否自洽，行里写什么状态词、统计行报几个数，
# 它一概不看。2026-09-18 实测：统计行声明 P0 23 / P1 18 / P2 17 / 合计 58，而清单实际是
# P0 24 / P1 21 / P2 17 / 合计 62；62 行里出现 11 种状态写法，而「## 状态流转」只声明 6 种；
# 台账第 5 行要求豁免/待定必须附**到期日**，这条规则同样零守卫。
#
# ⚠️ 与 C10 同一条教训：**判据一律从台账里提取，脚本里不存期望值**。
#    状态词表从「## 状态流转」章节的代码块里正则提取，统计口径从「**统计**：」行里提取，
#    再与清单实际行**互比** —— 于是「词表改了但行没改」与「行改了但词表没改」都会被抓，
#    且不需要脚本跟着改（脚本里存一份词表就成了第二份权威副本，与本检要消灭的漂移同类）。
#    下面三个常量只是**定位**（章节名 / 行首标记 / 日期形状），不是期望值。
C13_STATS_PREFIX = "**统计**"
C13_STATUS_SECTION = "状态流转"
C13_TIER_RE = re.compile(r"P[0-3]")
C13_DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")

# 到期标记词 —— 第 3 条的**定位器**（与 C13_STATS_PREFIX 同类：只负责把「到期日」从
# 状态格里认出来，不是期望值清单）。两点必须写清，否则这里会变成下一个永真式：
#   ① 这些是台账**自己**在用的措辞：第 5–6 行的规矩写作「附理由 + **到期日**」/
#      「**+ 到期复查日**」，5 条不修类行的状态格里也一律用 `到期复查 YYYY-MM-DD`
#      （TD-054/059/061/062）或 `YYYY-MM-DD 复审`（TD-026）落款。故它们是台账现状的
#      忠实提取，不是脚本自造的判据。
#   ② **若台账将来改用别的措辞，C13 会报红（认不出到期日），而不是静默放行。**
#      这是关键：失败方向必须是「红」。所以本集合只影响「多严」，不影响「漏不漏」——
#      漏判的代价是一次显式假红 + 人工把新措辞加进来，绝不可能是「静默变绿」。
# 窗口取 ±30 字符：足够容下 `到期复查 ` 这类前后缀，又不会跨过同格里的决定日。
C13_EXPIRY_MARKERS = ("到期", "复审", "复查", "复核", "expires")
C13_EXPIRY_WINDOW = 30


def _c13_expiry_dates(s: str) -> list[str]:
    """状态格里**锚定在到期标记上**的日期（保序去重）。

    判据：某个 `YYYY-MM-DD` 的**前后** `C13_EXPIRY_WINDOW` 字符窗口内出现任一到期标记词。
    ⚠️ 必须**双向**看：TD-026 写成「日期在前、标记在后」（`2027-03-16 复审`），
    只看「标记→日期」单向会把它误报成「没有到期日」（自造假阳性）；TD-054/059/061/062
    则是「标记在前、日期在后」（`到期复查 2027-03-18`）。两个方向台账都在用。
    这样「括号里的决定日」（如 `已豁免（2026-09-18，接受现状）`）不会被误当成到期日 ——
    它附近没有到期标记，删掉真正的到期复查日仍会变红。
    """
    out: list[str] = []
    for m in C13_DATE_RE.finditer(s):
        lo = max(0, m.start() - C13_EXPIRY_WINDOW)
        hi = min(len(s), m.end() + C13_EXPIRY_WINDOW)
        window = s[lo:hi]
        if any(mk in window for mk in C13_EXPIRY_MARKERS):
            out.append(m.group(0))
    seen: set[str] = set()
    uniq: list[str] = []
    for d in out:
        if d not in seen:
            seen.add(d)
            uniq.append(d)
    return uniq


def _c13_section_body(text: str, heading: str) -> str | None:
    """取含 `## <heading>` 的标题行到下一个 `## ` 之间的正文；找不到返回 None。

    用章节标题定位而不是写死行号 —— 行号会随债项增删漂移（C9 已因写死行号吃过亏）。
    ⚠️ 标题**允许带后缀**（如 `## 状态流转（权威词表）`）：只要求标题行里含该词，
    不要求整行相等 —— 否则给章节起个更清楚的名字就会把本检打成「提取不到」的假红。
    """
    m = re.search(r"(?m)^##[^\n]*" + re.escape(heading) + r"[^\n]*$", text)
    if not m:
        return None
    rest = text[m.end():]
    nxt = re.search(r"(?m)^##\s", rest)
    return rest[:nxt.start()] if nxt else rest


def _c13_table_rows(section_body: str) -> list[list[str]] | None:
    """取章节里第一张 markdown 表格**分隔行之后**的数据行；章节里没有表格返回 None。

    ⚠️ 必须从分隔行（`|---|---|---|`）之后取：表头行「状态词 / 定义 / 项数」本身也是
    `|` 行，不跳过分隔行就会把表头当成一个状态词（自造假阳性）。
    """
    lines = section_body.splitlines()
    sep = next((i for i, l in enumerate(lines)
                if re.fullmatch(r"\s*\|[\s:|-]+\|\s*", l)), None)
    if sep is None:
        return None
    rows: list[list[str]] = []
    for l in lines[sep + 1:]:
        if not l.lstrip().startswith("|"):
            break
        rows.append([x.strip() for x in l.split("|")])
    return rows


def _c13_status_vocab(section_body: str) -> list[str]:
    """从「状态流转」章节里提取状态词（去重保序）。支持两种已出现的排版：

      ① fenced 代码块里的状态机图（`待评估 → 已排期 → 进行中 → 已完成`）；
      ② markdown 表格（`| 状态词 | 定义 | 项数 |`，2026-09-18 起改用的「权威词表」）。

    ⚠️ 表格只取**分隔行之后**的第一列，跳过表头与分隔行 —— 否则表头「状态词」会被
    当成一个状态词。
    ⚠️ 不把整节切词：章节里的散文（「任何『不修』都必须落到此列…」）含状态词字面，
    整节切词会把散文噪声当词表 —— 那是自造的假阳性。
    """
    words: list[str] = []

    m = re.search(r"```[^\n]*\n(.*?)```", section_body, re.S)
    if m:
        for raw in m.group(1).splitlines():
            line = re.sub(r"[（(][^）)]*[）)]", "", raw)   # 去掉（理由 + 到期日）这类批注
            for tok in re.split(r"[→↘\s、,，/|]+", line):
                tok = tok.strip()
                if re.fullmatch(r"[\u4e00-\u9fff]{2,}", tok):
                    words.append(tok)

    for cells in _c13_table_rows(section_body) or []:
        if len(cells) > 2:
            tok = cells[1].replace("*", "").strip()
            if re.fullmatch(r"[\u4e00-\u9fff]{2,}", tok):
                words.append(tok)

    seen: set[str] = set()
    out: list[str] = []
    for w in words:
        if w not in seen:
            seen.add(w)
            out.append(w)
    return out


def check_c13(repo_root: Path) -> dict:
    """C13 台账结构自洽（2026-09-18 新增）。

    `docs/tech-debt-register.md` 是技术债的**唯一登记处**，但它除了 DPI/档位（C9 管）
    之外的**结构**从来没有被校验过：统计行可以随便报数、状态列可以随便造词、
    台账第 5 行白纸黑字写的「豁免/待定必须附到期日」没有任何东西守着。

    与 C3–C13 的其它硬失败项同类：**硬失败、不做棘轮** —— 守的是规则不是存量债。

    校验六条（1–3 是任务指定的必查项，4–6 见下）：
      1. 统计行汇总数 == 清单实际：`**统计**：` 开头的行里声明的 `P0…P3`/`合计`
         必须与按档位格分桶数出来的行数一致。
      2. 状态词必须落在「## 状态流转」章节声明的词表内（词表**从台账提取**，不内嵌）。
      3. 状态属「不修类」（词表里含 `豁免`/`待定` 字样的词）的行，状态格里必须有
         `YYYY-MM-DD` 形式的**到期日**（台账第 5 行的规矩：没有期限的豁免=永久豁免）。
         ⚠️ 必须判「**锚定在到期标记上**」的日期，不是「存在任意一个日期」：
         每条不修类行里同时有**决定日/登记日**（`已豁免（2026-09-18，…）`）与**到期
         复查日**（`到期复查 2027-03-18`）。只判「存在日期」的话，把真正的到期复查日
         整段删掉仍会 PASS —— 那是 C13 自己要消灭的永真式。判据见 `_c13_expiry_dates`。
      4. **档位格纯度**：档位格必须恰为 `P0`/`P1`/`P2`/`P3`。
         —— 第 4 项放在 C13 而不是收紧 C9，理由：① C9 的职责是**数值自洽**
         （DPI↔公式↔落档），它的 `tier[:2]` 是**刻意的容错**（`_cell_num` 注释明写
         档位列可能带括号后缀），把格式纯度塞进 C9 会让「算错分」与「写错格」两类
         失败混进同一个报错，且要改动已发布的 C9 语义与容错承诺；② 「格子里放什么」
         本就是**结构**约束，与 C13 同类；③ C13 的统计分桶要按档位格取前两字符，
         档位格不纯会**直接污染分桶结果**，两者本就耦合。
         「硬性升档」的理由按 C9 报错文案给出的范式写在 **DPI 格**
         （`**22.6**（+ 硬性升档：数据丢失）`），档位格只放档位。
      5. **触发集不得空转**：词表里必须至少有一个含 `豁免`/`待定` 字样的词。
         —— 第 3 条靠「词里含 豁免/待定」挑打击对象；词表若把这两个词改名
         （如 `豁免-A`），触发集变空 → 第 3 条**无声退化成永真式**，而 C13 仍会
         PASS。这正是本检要消灭的形状：守卫看着在跑，防的不是它声称防的东西。
      6. **词表「项数」列 == 清单实际**：项数之和必须 == 清单行数，且每个词的项数
         必须 == 按该词统计出的实际行数。
         —— 「项数」列是**第二份计数声明**，与统计行、清单实际构成三处，只比对
         统计行↔清单会漏掉它。表格解析不出数据行 / 项数列解析不出整数 → 按失败处理。

    ⚠️ 文件不存在 / 读不了 / 正则提取不到 → **按失败处理**，绝不静默放过（与
    C9/C11/C12 同口径）。「提取到 0 个状态词」「找不到统计行」「找不到状态流转章节」
    都必须变红 —— 否则遍历被压到 0 就成了永真式（TD-049 的阳性对照专门钉过这一点）。
    """
    reg = repo_root / _REGISTER
    findings: list[str] = []

    if not reg.exists():
        return {"findings": [f"台账 `{_REGISTER}` 不存在（C13 无法校验，按失败处理）"],
                "checked": 0, "rows": 0, "vocab": [], "tier_counts": {}}
    try:
        text = read_text(reg)
    except Exception as e:
        return {"findings": [f"台账 `{_REGISTER}` 读取失败：{e}（C13 无法校验，按失败处理）"],
                "checked": 0, "rows": 0, "vocab": [], "tier_counts": {}}

    lines = text.splitlines()

    # ---- 清单行（唯一事实源）----
    rows: list[tuple[int, list[str]]] = []
    for lineno, line in enumerate(lines, start=1):
        if line.startswith("| TD-"):
            rows.append((lineno, [x.strip() for x in line.split("|")]))

    tier_counts = {"P0": 0, "P1": 0, "P2": 0, "P3": 0}
    for lineno, cells in rows:
        tid = cells[1] if len(cells) > 1 else f"第 {lineno} 行"
        if len(cells) < 13:
            findings.append(
                f"{tid}：行结构不完整（{len(cells)} 段，取不到档位/状态格）—— "
                f"C13 无法判定该行（按失败处理）"
            )
            continue
        tier_raw = cells[11].replace("*", "").strip()
        # 分桶用**前缀**匹配（与 C9 的 `tier[:2]` 同口径）：档位格不纯时也要能落桶，
        # 否则该行会从统计里凭空消失、把统计行的偏差一起掩盖掉；纯度本身单独报。
        m_tier = C13_TIER_RE.match(tier_raw)
        if m_tier:
            tier_counts[m_tier.group(0)] += 1
        if not C13_TIER_RE.fullmatch(tier_raw):
            findings.append(
                f"{tid}：档位格不纯 —— 实际 `{cells[11]}`，应恰为 `P0`/`P1`/`P2`/`P3`。"
                f"「硬性升档」的理由按 C9 报错文案的范式写在 **DPI 格**"
                f"（`**22.6**（+ 硬性升档：数据丢失）`），档位格只放档位"
            )
    total = len(rows)

    # ---- 1. 统计行汇总数 vs 实际 ----
    stat_line: tuple[int, str] | None = None
    for lineno, line in enumerate(lines, start=1):
        if line.lstrip().startswith(C13_STATS_PREFIX):
            stat_line = (lineno, line)
            break
    if stat_line is None:
        findings.append(
            f"提取不到以 `{C13_STATS_PREFIX}` 开头的统计行（C13 无法校验，按失败处理）"
            f"—— 统计行是台账的汇总口径，它不在就没人能对账"
        )
    else:
        sl_no, sl = stat_line
        declared: dict[str, int] = {}
        for m in re.finditer(r"(合计|P[0-3])\s*\**\s*(\d+)\s*\**\s*项", sl):
            k, n = m.group(1), int(m.group(2))
            if k in declared and declared[k] != n:
                findings.append(
                    f"统计行（第 {sl_no} 行）里 `{k}` 出现两个不同数字"
                    f"（{declared[k]} 与 {n}）—— 无法判定哪个生效（按失败处理）"
                )
            declared.setdefault(k, n)
        if not declared:
            findings.append(
                f"统计行（第 {sl_no} 行）里提取不到任何 `P0…P3`/`合计` 计数"
                f"（C13 无法校验，按失败处理）"
            )
        else:
            for k in ("P0", "P1", "P2", "P3"):
                d = declared.get(k)
                if d is None:
                    if tier_counts[k]:
                        findings.append(
                            f"统计行漏报 `{k}`：清单实际有 **{tier_counts[k]}** 项，"
                            f"统计行只报了 "
                            + "、".join(f"{kk} {vv}" for kk, vv in declared.items())
                        )
                elif d != tier_counts[k]:
                    findings.append(
                        f"统计行 `{k}` 声明 **{d}** 项，实际 **{tier_counts[k]}** 项"
                    )
            d = declared.get("合计")
            if d is None:
                findings.append(f"统计行（第 {sl_no} 行）提取不到 `合计`（按失败处理）")
            elif d != total:
                findings.append(f"统计行 `合计` 声明 **{d}** 项，实际 **{total}** 项")

    # ---- 2 / 3. 状态词表 + 不修类到期日 ----
    section = _c13_section_body(text, C13_STATUS_SECTION)
    vocab: list[str] = []
    declared_items: dict[str, int] = {}   # 词表「项数」列（第二份计数声明）
    if section is None:
        findings.append(
            f"提取不到 `## {C13_STATUS_SECTION}` 章节（C13 无法校验，按失败处理）—— "
            f"状态词表就在那里；章节没了，状态校验会退化成永真式，必须变红"
        )
    else:
        vocab = _c13_status_vocab(section)
        if not vocab:
            findings.append(
                f"`## {C13_STATUS_SECTION}` 章节里提取不到任何状态词（代码块/词表表格缺失或为空）"
                f"—— 提取到 0 个词即视为失败，不放行"
            )
        else:
            # 加固 A：触发集空转。第 3 条到期日校验靠「词里含 豁免/待定」挑出打击对象；
            # 若词表把这两个词改名（如 `豁免-A`），触发集变空 → 第 3 条**无声退化成
            # 永真式**，而 C13 仍会 PASS。故词表里必须至少留一个这类词。
            # ⚠️ 判据从词表提取后再判，脚本里不内嵌词表本身。
            if not any(("豁免" in w) or ("待定" in w) for w in vocab):
                findings.append(
                    f"词表里没有任何含 `豁免`/`待定` 字样的词 —— 台账第 6 行要求任何"
                    f"「不修」必须落到 `豁免`/`待定`，词表里没有这类词就意味着**该规则"
                    f"无法表达**，且第 3 条到期日校验会**空转**（触发集为空 = 永真式）。"
                    f"当前词表：{'、'.join(vocab)}"
                )

            # 加固 B：词表「项数」列。它是**第二份计数声明**，与统计行、清单实际三处
            # 可以各自漂移；只比对统计行↔清单会漏掉它。
            tbl = _c13_table_rows(section)
            if tbl is None:
                findings.append(
                    f"`## {C13_STATUS_SECTION}` 章节里找不到状态词表格 —— 「项数」列是"
                    f"第二份计数声明，缺它就无法与统计行/清单实际三处对账"
                    f"（C13 无法校验，按失败处理）"
                )
            elif not tbl:
                findings.append(
                    f"`## {C13_STATUS_SECTION}` 的状态词表格解析不出任何数据行"
                    f"（表头/分隔行之后为空）—— 按失败处理，不跳过当没事"
                )
            else:
                for r in tbl:
                    last = next((c for c in reversed(r) if c != ""), "")
                    w = r[1].replace("*", "").strip() if len(r) > 1 else ""
                    if len(r) < 3 or not re.fullmatch(r"\d+", last):
                        findings.append(
                            f"词表行 `{w or '（空）'}` 的**项数列**解析不出整数 —— "
                            f"实际 `{last}`（C13 无法校验该词，按失败处理）"
                        )
                        continue
                    declared_items[w] = int(last)
                if declared_items:
                    ssum = sum(declared_items.values())
                    if ssum != total:
                        findings.append(
                            f"词表「项数」之和 **{ssum}** 与清单行数 **{total}** 不符 —— "
                            + "、".join(f"{k} {v}" for k, v in declared_items.items())
                        )

    status_checked = 0
    actual_items: dict[str, int] = {}
    if vocab:
        vocab_sorted = sorted(vocab, key=len, reverse=True)   # 长词优先，避免前缀误吞
        for lineno, cells in rows:
            if len(cells) < 13:
                continue
            tid = cells[1] if len(cells) > 1 else f"第 {lineno} 行"
            raw = cells[12]
            s = re.sub(r"^[^\w\u4e00-\u9fff]+", "", raw.replace("*", "").strip())
            word = next((w for w in vocab_sorted if s.startswith(w)), None)
            if word is None:
                findings.append(
                    f"{tid}：状态词不在「{C13_STATUS_SECTION}」词表内 —— 台账写 "
                    f"`{raw[:40]}`，词表只认 {'、'.join(vocab)}。请改成词表里的词，"
                    f"或（若确需新状态）同时更新「{C13_STATUS_SECTION}」章节"
                )
                continue
            status_checked += 1
            actual_items[word] = actual_items.get(word, 0) + 1
            if ("豁免" in word) or ("待定" in word):
                anchored = _c13_expiry_dates(s)
                if not anchored:
                    all_dates = C13_DATE_RE.findall(s)
                    if all_dates:
                        why = (
                            f"状态格里虽有日期 {'、'.join(dict.fromkeys(all_dates))}，"
                            f"但它们附近（±{C13_EXPIRY_WINDOW} 字符内）都没有到期标记"
                            f"（{'/'.join(C13_EXPIRY_MARKERS)}）—— 那些是决定日/登记日，"
                            f"不是到期日"
                        )
                    else:
                        why = "状态格里连 `YYYY-MM-DD` 形式的日期都没有"
                    findings.append(
                        f"{tid}：状态 `{word}` 属「不修类」，台账第 5 行要求必须附**到期日**"
                        f"（**不是随便一个日期**）—— {why}。"
                        f"到期日须写成 `到期复查 YYYY-MM-DD` 或 `YYYY-MM-DD 复审` 这类"
                        f"**锚定在到期标记上**的形式。实际 `{raw[:60]}`。"
                        f"没有期限的豁免等于永久豁免，白名单会无声膨胀"
                    )

    # 加固 B（续）：逐词比对「项数」列 vs 按该词统计出的实际行数
    for w, declared in declared_items.items():
        got = actual_items.get(w, 0)
        if declared != got:
            findings.append(
                f"词表「项数」列 `{w}` 声明 **{declared}** 项，按状态格实际统计为 **{got}** 项"
            )

    return {"findings": findings, "checked": total, "rows": total,
            "vocab": vocab, "tier_counts": tier_counts,
            "status_checked": status_checked, "declared_items": declared_items}


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


# ---------------------------------------------------------------- C14 安全红线静态契约
# 2026-09-19 全面工程审查（`deliverables/engineering-assurance/code-review-full-system-2026-09-19.md`）
# 发现：5 条硬红线里**只有 2 条**有机器守护（清理名单单测 watchdog.rs:1508 / C4 空占位目录），
# 另外 3 条只写在 `AGENTS.md` 与代码注释里 —— **注释不会在有人改反时变红**。
#
# 本检把其中**判据 crisp、静态扫描能可靠判定**的两条升级为机器守护：
#   R3  WebView2 的 AHK↔JS 通信禁 sync 代理（`AddHostObjectToScript` / 同步 proxy），
#       必须 postMessage —— 同步代理会把 AHK 主线程与 WebView 绑死，直接死锁。
#   R5  纯逻辑 crate（asd-domain / asd-ipc-protocol / asd-application）禁引入
#       tauri / tokio / interprocess / windows —— 直接依赖（Cargo.toml 文本扫描）
#       与**传递闭包**（`cargo tree`）两层都查。
#
# ⚠️ 刻意**不纳入**红线 4（全局锁顺序 ipc_manager → watchdog）：
#   锁顺序是跨函数、跨 await 点的**动态**性质，正则扫不出可靠结论；写一条弱正则会造出
#   **「假守护」**（看着在守，实则大量漏报与误报），比不守更危险 —— 这与本项目
#   2026-09-19 一天三次把「其实已有守护」误判为「没有守护」是同一类陷阱。
#   红线 4 改由人工评审 + 登记技术债，待有可靠手段（如 lock-order 运行时探针）再落地。
#
# 与 C3–C13 的其它硬失败项同类：**硬失败、不做棘轮** —— 守的是规则不是存量债。

C14_WV2_MANAGER = "presentation/webview2_manager.ahk"
C14_WV2_FORBIDDEN = ("AddHostObjectToScript",)
# ⚠️ 名单必须覆盖 AGENTS.md:245 与 AGENTS.md:1393 的**全部三个**纯逻辑 crate。
# 2026-09-19 第二轮修复：原名单只有 asd-domain / asd-ipc-protocol，**漏了
# asd-application** —— 阳性对照实测：往 `asd-application/Cargo.toml` 注入 `tokio = "1"`
# 时 C14 **照常 PASS**（放行），而同样注入 asd-domain 会 FAIL。即红线 5 有 1/3 面裸奔。
C14_PURE_CRATES = ("asd-domain", "asd-ipc-protocol", "asd-application")
C14_FORBIDDEN_DEPS = ("tauri", "tokio", "interprocess", "windows")
C14_DEP_SECTIONS = ("[dependencies]", "[dev-dependencies]", "[build-dependencies]")
C14_CARGO_TREE_TIMEOUT = 180


def check_c14(repo_root: Path) -> dict:
    """C14 安全红线静态契约（2026-09-19 新增）。

    判据（打击面刻意收窄，宁可漏报也不误报）：
      R3 只扫 `presentation/webview2_manager.ahk` 的**生产**代码；注释行（`;` 开头）跳过。
         归档测试与第三方 lib（`lib/ahk2_lib/`）中的同类调用不查 —— 它们不是生产路径。
      R5 分两层：① 直接依赖 —— 只扫三个纯逻辑 crate 的 Cargo.toml，且只在依赖分区
         （`[dependencies]` / `[dev-dependencies]` / `[build-dependencies]`）内匹配
         `^<name>\\s*=`，避免把 `windows-sys = ...` 误判成 `windows`（`-` 不是 `=`，匹配不上）；
         ② 传递闭包 —— `cargo tree -p <crate>` 的精确包名集合。
      Cargo.toml / webview2_manager.ahk 不存在 → **按失败处理**，不静默放过（与 C8/C11/C12 同口径）。
    """
    findings: list[str] = []
    checked = 0

    # ---- R3：WebView2 禁 sync 代理 ----
    wv2 = repo_root / C14_WV2_MANAGER
    if not wv2.exists():
        findings.append(f"`{C14_WV2_MANAGER}` 不存在（C14 R3 无法校验，按失败处理）")
    else:
        checked += 1
        try:
            text = read_text(wv2)
        except Exception as e:
            findings.append(f"`{C14_WV2_MANAGER}` 读取失败：{e}（C14 R3 无法校验，按失败处理）")
            text = ""
        for lineno, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith(";"):
                continue
            for bad in C14_WV2_FORBIDDEN:
                if bad in line:
                    findings.append(
                        f"`{C14_WV2_MANAGER}:{lineno}` 出现 `{bad}` —— "
                        f"AHK↔JS 通信**禁止 sync 代理**：同步调用会把 AHK 主线程与 WebView 绑死导致死锁，"
                        f"必须改用 `PostWebMessageAsJson` + `add_WebMessageReceived`（安全红线 3）。"
                    )

    # ---- R5：纯逻辑 crate 禁依赖 ----
    for crate in C14_PURE_CRATES:
        cargo = repo_root / "asd-tauri" / "crates" / crate / "Cargo.toml"
        rel_cargo = f"asd-tauri/crates/{crate}/Cargo.toml"
        if not cargo.exists():
            findings.append(f"`{rel_cargo}` 不存在（C14 R5 无法校验，按失败处理）")
            continue
        checked += 1
        try:
            text = read_text(cargo)
        except Exception as e:
            findings.append(f"`{rel_cargo}` 读取失败：{e}（C14 R5 无法校验，按失败处理）")
            continue
        section = None
        for lineno, line in enumerate(text.splitlines(), 1):
            s = line.strip()
            if s.startswith("[") and s.endswith("]"):
                section = s
                continue
            if section not in C14_DEP_SECTIONS:
                continue
            for bad in C14_FORBIDDEN_DEPS:
                if re.match(rf"^{re.escape(bad)}\s*=", s):
                    findings.append(
                        f"`{rel_cargo}:{lineno}` 在 `{section}` 引入禁依赖 `{bad}` —— "
                        f"纯逻辑 crate **禁止**依赖 tauri / tokio / interprocess / windows："
                        f"一旦引入就把领域逻辑钉死在 Tauri 运行时与 Windows 平台上，"
                        f"`cargo test` 也将无法在纯逻辑层独立跑（安全红线 5）。"
                    )

    # ---- R5b：传递闭包（`cargo tree`）----
    # 为什么还要这一层：上面只扫**直接**依赖。红线 5 的权威口径（AGENTS.md:1393 与
    # 本次审查的核实方式）是「**引入**以下依赖」—— 经中间 crate 间接引入同样会把领域
    # 逻辑钉死在 Tauri 运行时 / Windows 上。阳性对照实测：往 `asd-domain` 注入
    # `hyper = "1"`（hyper **不在**禁名单、但传递依赖 tokio），上面的文本扫描 **PASS 放行**，
    # 加上下面的 `cargo tree` 才变红。
    # ⚠️ 用**精确包名**比对（`{p}` 的第一个 token），不能子串匹配：
    #   `asd-application` 的 dev 链里有 `windows-sys` / `windows-link`（tempfile → …），
    #   子串匹配会把它们误判成禁依赖 `windows` —— 那是本项目已三次踩过的「假守护」陷阱。
    for crate in C14_PURE_CRATES:
        checked += 1
        proc = subprocess.run(
            ["cargo", "tree", "-p", crate, "-e", "normal,build,dev",
             "--prefix", "none", "--format", "{p}"],
            cwd=str(repo_root / "asd-tauri"),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=C14_CARGO_TREE_TIMEOUT,
        )
        if proc.returncode != 0:
            findings.append(
                f"`cargo tree -p {crate}` 执行失败（退出码 {proc.returncode}）—— "
                f"C14 R5b 无法校验传递闭包，按失败处理（不静默放过）。"
                f"输出尾部：{(proc.stderr or proc.stdout).strip()[-300:]}"
            )
            continue
        names: set[str] = set()
        for line in proc.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            names.add(line.split()[0])
        for bad in C14_FORBIDDEN_DEPS:
            if bad in names:
                findings.append(
                    f"`cargo tree -p {crate}` 的**传递闭包**含禁依赖 `{bad}` —— "
                    f"纯逻辑 crate 禁止（含间接）引入 tauri / tokio / interprocess / windows："
                    f"即使不是直接依赖，也会把领域逻辑钉死在 Tauri 运行时与 Windows 平台上，"
                    f"`cargo test` 无法在纯逻辑层独立跑（安全红线 5）。"
                )

    return {"findings": findings, "checked": checked}


def main() -> int:
    ap = argparse.ArgumentParser(
        description="技术债度量检查（C1–C14：C1 孤儿 / C2 未接入 / C3 文档漂移 / C3b 硬写基线数字 / "
                    "C4 占位目录守卫 / C5 冗余 lock / C6 vendored 引擎纯净性 / C7 布尔契约同步 / "
                    "C8 IPC 契约 / C9 评分自洽 / C10 门禁档位 / C11 打包资源 / C12 调试端口 / C13 台账结构自洽 / C14 安全红线静态契约）"
    )
    ap.add_argument("--update-baseline", action="store_true", help="把当前结果冻结为新基线")
    ap.add_argument("--show", action="store_true", help="只打印当前结果，不与基线比对")
    ap.add_argument("--only", choices=["c1", "c2", "c3", "c3b", "c4", "c5", "c6", "c7", "c8", "c9", "c10", "c11", "c12", "c13", "c14"], help="只跑某一检")
    args = ap.parse_args()

    print("=" * 60)
    print("技术债度量检查（C1–C14：C1 孤儿文件 / C2 测试未接入 / C3 文档漂移 / C3b 硬写基线数字 / "
          "C4 占位目录守卫 / C5 冗余 lock / C6 vendored 引擎纯净性 / C7 布尔契约同步 / "
          "C8 IPC 契约 / C9 评分自洽 / C10 门禁档位 / C11 打包资源 / C12 调试端口 / C13 台账结构自洽 / C14 安全红线静态契约）")
    print("=" * 60)

    cur = {
        "c1": check_c1(REPO_ROOT),
        "c2": check_c2(REPO_ROOT),
        "c3": check_c3(REPO_ROOT),
        "c3b": check_c3b(REPO_ROOT),
        "c4": check_c4(REPO_ROOT),
        "c5": check_c5(REPO_ROOT),
        "c6": check_c6(REPO_ROOT),
        "c7": check_c7(REPO_ROOT),
        "c8": check_c8(REPO_ROOT),
        "c9": check_c9(REPO_ROOT),
        "c10": check_c10(REPO_ROOT),
        "c11": check_c11(REPO_ROOT),
        "c12": check_c12(REPO_ROOT),
        "c13": check_c13(REPO_ROOT),
        "c14": check_c14(REPO_ROOT),
    }

    if args.update_baseline:
        save_baseline(cur)
        return 0

    want = {args.only} if args.only else {"c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "c9", "c10", "c11", "c12", "c13", "c14"}

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

    # ---------- C6：硬失败，vendored 引擎树必须与官方 v2.0.26 一致 ----------
    c6_findings = list(cur["c6"]["findings"])
    if "c6" in want:
        print(f"\n[C6] vendored 引擎树纯净性（对照官方 v2.0.26 的 {cur['c6']['checked']} 个文件）："
              f"本地 {cur['c6']['present']} 个")
        if c6_findings:
            for f in c6_findings[:20]:
                print(f"       - {f}")
            if len(c6_findings) > 20:
                print(f"       … 另有 {len(c6_findings) - 20} 处")
        else:
            print("       通过：与官方 v2.0.26 不多、不少、不改")

    # ---------- C7：硬失败，Rust bool 字段必须都在 AHK BoolKeys 里 ----------
    c7_findings = list(cur["c7"]["findings"])
    if "c7" in want:
        print(f"\n[C7] 布尔契约同步（Rust bool 字段 ↔ AHK BoolKeys）："
              f"Rust {cur['c7']['checked']} 个键 / AHK 白名单 {len(cur['c7']['ahk_keys'])} 个")
        if c7_findings:
            for f in c7_findings[:20]:
                print(f"       - {f}")
        else:
            print("       通过：Rust 侧的布尔字段全部在 AHK 白名单内")

    # ---------- C8：硬失败，IPC 命令契约双向对齐（TD-057）----------
    c8_findings = list(cur["c8"]["findings"])
    if "c8" in want:
        print(f"\n[C8] IPC 命令契约对齐（Rust `IpcCommand` 序列化名 ↔ AHK 分发表）："
              f"Rust {cur['c8']['checked']} 条 / AHK {len(cur['c8']['ahk_actions'])} 条")
        if c8_findings:
            for f in c8_findings[:20]:
                print(f"       - {f}")
        else:
            print("       通过：两侧命令集合完全一致")

    # ---------- C9：硬失败，台账评分自洽（2026-09-18 新增）----------
    c9_findings = list(cur["c9"]["findings"])
    if "c9" in want:
        print(f"\n[C9] 技术债台账评分自洽（DPI 是否等于公式值 / 档位是否等于阈值落档）："
              f"核对 {cur['c9']['checked']} 行")
        if c9_findings:
            for f in c9_findings[:20]:
                print(f"       - {f}")
        else:
            print("       通过：DPI 与档位全部符合公式与阈值")

    # ---------- C10：硬失败，三处门禁 G3d 档位必须一致（TD-055）----------
    c10_findings = list(cur["c10"]["findings"])
    if "c10" in want:
        print(f"\n[C10] 三处门禁档位一致（.sh / .ps1 / ci.yml 互比）："
              f"核对 {cur['c10']['checked']} 处")
        for gid, rp, mode, ln in cur["c10"]["table"]:
            print(f"       {gid}  {rp}:{ln} = {mode}")
        if c10_findings:
            for f in c10_findings[:20]:
                print(f"       - {f}")
        else:
            print("       通过：三处档位一致（本检只管漂移、不管取值）")

    # ---------- C11：硬失败，打包资源必须覆盖 #Include 的全部同目录 .ahk ----------
    c11_findings = list(cur["c11"]["findings"])
    if "c11" in want:
        print(f"\n[C11] 打包资源清单同步（{C11_AHK_EXECUTOR}/*.ahk 的 "
              f"#Include ↔ bundle.resources）：核对 {cur['c11']['checked']} 个被引用文件"
              f"，resources 共 {cur['c11']['resources']} 项")
        if c11_findings:
            for f in c11_findings[:20]:
                print(f"       - {f}")
        else:
            print("       通过：被引用的同目录 .ahk 全部已打包")
        if cur["c11"]["advisory"]:
            # 只提示不判失败：可能是漏 include，也可能是入口脚本（executor.ahk
            # 由 asd_executor.bat / Rust 直接拉起，本就不该有入边）—— 要人判。
            print(f"       [提示] 存在但从未被 #Include 引用（需人判：漏 include 还是入口脚本）："
                  f"{'、'.join(cur['c11']['advisory'])}")

    # ---------- C12：硬失败，正式配置不得开调试端口 ----------
    c12_findings = list(cur["c12"]["findings"])
    if "c12" in want:
        print(f"\n[C12] 正式配置不得开调试端口（{C12_TAURI_CONF} 里不得出现 "
              f"{C12_FORBIDDEN}；{C12_E2E_CONF} 是合法例外、不查）")
        if c12_findings:
            for f in c12_findings[:20]:
                print(f"       - {f}")
        else:
            print("       通过：正式配置未开远程调试端口")

    # ---------- C13：硬失败，台账结构自洽 ----------
    c13_findings = list(cur["c13"]["findings"])
    if "c13" in want:
        print(f"\n[C13] 技术债台账结构自洽（统计行汇总数 / 状态词表 / 豁免到期日 / 档位格纯度）："
              f"核对 {cur['c13']['checked']} 行，状态词表 "
              f"{'、'.join(cur['c13']['vocab']) or '（提取不到）'}")
        if c13_findings:
            for f in c13_findings[:20]:
                print(f"       - {f}")
            if len(c13_findings) > 20:
                print(f"       … 另有 {len(c13_findings) - 20} 处")
        else:
            print("       通过：统计行与清单一致、状态词都在词表内、豁免/待定均附到期日、档位格纯净")

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
    if "c6" in want and c6_findings:
        errors.append(
            f"vendored 引擎树与官方 v2.0.26 不一致 {len(c6_findings)} 处（C6："
            f"多出 {len(cur['c6']['extra'])} / 缺失 {len(cur['c6']['missing'])} / "
            f"被改 {len(cur['c6']['changed'])} / "
            f"被删 {len(cur['c6']['deleted'])}）"
        )
    if "c7" in want and c7_findings:
        errors.append(f"Rust 布尔字段未登记进 AHK BoolKeys {len(c7_findings)} 处（C7）")

    if "c8" in want and c8_findings:
        errors.append(f"IPC 命令契约不对齐 {len(c8_findings)} 处（C8）")

    if "c9" in want and c9_findings:
        errors.append(f"技术债台账评分不自洽 {len(c9_findings)} 处（C9）")

    if "c10" in want and c10_findings:
        errors.append(f"三处门禁档位漂移 {len(c10_findings)} 处（C10）")

    if "c11" in want and c11_findings:
        errors.append(
            f"`bundle.resources` 漏打包被引用的 .ahk {len(c11_findings)} 项（C11）"
        )

    if "c12" in want and c12_findings:
        errors.append(
            f"正式 `tauri.conf.json` 出现 `{C12_FORBIDDEN}` {len(c12_findings)} 处"
            f"（会进 release 产物，安全红线）（C12）"
        )

    if "c13" in want and c13_findings:
        errors.append(
            f"技术债台账结构不自洽 {len(c13_findings)} 处（统计行/状态词/到期日/档位格）（C13）"
        )

    # ---------- C14：硬失败，安全红线静态契约 ----------
    c14_findings = list(cur["c14"]["findings"])
    if "c14" in want:
        print(f"\n[C14] 安全红线静态契约（R3 WebView2 禁 sync 代理 / R5 纯逻辑 crate 禁依赖）："
              f"核对 {cur['c14']['checked']} 个")
        if c14_findings:
            for f in c14_findings[:20]:
                print(f"       - {f}")
            if len(c14_findings) > 20:
                print(f"       … 另有 {len(c14_findings) - 20} 处")
        else:
            print("       通过：无 sync 代理、3 个纯逻辑 crate 的直接依赖与传递闭包均无禁依赖"
                  "（红线 4 锁顺序为动态性质，静态不可靠判定，不在此检 —— 见函数注释）")

    if "c14" in want and c14_findings:
        errors.append(
            f"安全红线静态契约被破坏 {len(c14_findings)} 处"
            f"（C14：WebView2 sync 代理 / 纯逻辑 crate 禁依赖）"
        )

    if errors:
        print("[FAIL] 技术债检查未通过:")
        for e in errors:
            print(f"  - {e}")
        return 1

    print("[PASS] 技术债检查通过：无新增债、文档与代码一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
