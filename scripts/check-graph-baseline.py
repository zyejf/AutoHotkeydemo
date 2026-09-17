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
from datetime import date
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
HARD_FAIL_GREATER = [
    "ahk_cycles",
    "rust_crate_cycles",
    "ahk_missing",
    # TD-049① 新增：生产代码 #Include 测试/工具代码 = 架构倒灌，绝不能靠基线抬水位放行
    "ahk_prod_to_nonprod_edges",
    # 生产孤点 = 生产 AHK 既不被 include 也不 include 任何东西：漏接线或死代码
    "ahk_orphans_prod",
    # JS 环（TD-051 起）。转入硬失败的**前提已经满足**：阳性对照 PC-2 在
    # helpers/error_utils.js 注入 `import { invoke } from './tauri.js'` 后，
    # js_cycles 0 -> 1 且 js_edges_internal 同步 36 -> 37（说明这条反向边真的进了
    # 邻接表，不是计数凑巧）—— 它不是永真式。
    "js_cycles",
]

# 分桶口径：AHK 节点必须被切成这三个互不相交的桶（TD-049①）
AHK_BUCKET_KEYS = ("ahk_prod_files", "ahk_test_files", "ahk_tool_files")

# 遍历锚点（TD-049①）：扫描类守护最怕「扫到 0 条还一路绿灯」——
# 目录口径一变、git 命令一改、扩展名一写错，节点集塌成空集，
# 于是「没有环 / 没有违规」变成永真。这里给每个桶一个下限：
# 低于下限直接判定**遍历失效**，硬失败。数值取自 2026-09-18 实测值（92/40/23/29、64、5）
# 向下取整留出开发余量 —— 它不是水位线，是「图还在不在」的探针。
SCAN_ANCHOR_MIN = {
    "ahk_files": 80,
    "ahk_prod_files": 30,
    "ahk_test_files": 15,
    "ahk_tool_files": 20,
    "rust_files": 50,
    "js_files": 3,
}


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


def check_exemption_hygiene(baseline: dict) -> list[str]:
    """白名单条目的「卫生」检查：每条必须有**非空理由**与**未过期的到期日**。

    起因（TD-009）：`allowed_violations` 里曾有 3 条 `"reason": ""`、也没有到期日 ——
    那时谁也说不清这 3 条到底是「审过的豁免」还是「当年漏填」。豁免没有理由和期限，
    白名单就会无声膨胀：每加一条都零成本，没人会回头看，债永远不清。
    （这 3 条最终查明是漏填、已消除，但**机制**必须留下 —— 它防的是下一条。）

    硬失败、不做棘轮：这守的是规则，不是存量债。
    """
    errs: list[str] = []
    today = date.today()
    for i, v in enumerate(baseline.get("allowed_violations", [])):
        src_name, dst_name = v.get("from", "?"), v.get("to", "?")
        tag = f"allowed_violations[{i}] {src_name} -> {dst_name}"
        if not (v.get("reason") or "").strip():
            errs.append(f"{tag} 缺 reason —— 说清为什么这是豁免而不是该修的违规"
                        f"（若其实不是违规，应改 `build_graph.py` 的 ALLOWED_CRATE_DEPS）")
        exp = (v.get("expires") or "").strip()
        if not exp:
            errs.append(f"{tag} 缺 expires（ISO 日期，如 2027-03-16）"
                        f"—— 没有期限的豁免等于永久豁免")
            continue
        try:
            d = date.fromisoformat(exp)
        except ValueError:
            errs.append(f"{tag} 的 expires 不是合法 ISO 日期：{exp!r}")
            continue
        if d < today:
            errs.append(f"{tag} 的豁免已于 {exp} 过期（{(today - d).days} 天前）"
                        f"—— 请修掉违规，或重新评估后更长期限")
    return errs


def check_bucket_integrity(raw: dict) -> list[str]:
    """分桶口径完整性（TD-049①）—— 这是**区分新旧实现的探针**。

    为什么不是永真式：`counts` 里的 `ahk_*_files` 与 `ahk.buckets` 是
    build_graph.py 里**两条独立的产出路径**（一个来自 len(files)，一个来自逐节点
    分类表的重算）。这里从 `ahk.buckets` 重新数一遍再跟 counts 对撞 ——
    任一侧漏改都会当场炸。若 graph-raw.json 根本没有 `ahk.buckets`，
    说明跑的是旧实现，直接判定闸门失效而不是「默认通过」。
    """
    errs: list[str] = []
    ahk = raw.get("ahk", {})
    counts = raw.get("meta", {}).get("counts", {})
    buckets = ahk.get("buckets")

    if not isinstance(buckets, dict) or not buckets:
        return ["graph-raw.json 缺 `ahk.buckets`（或为空）—— 跑的是 TD-049① 之前的"
                "旧 build_graph.py？闸门① 无法校验 AHK 分桶口径，拒绝给出结论"
                "（请先重跑 `python .review-analysis/build_graph.py`）"]

    files = ahk.get("files", [])
    if len(buckets) != len(files):
        errs.append(f"ahk.buckets 有 {len(buckets)} 项，但 ahk.files 有 {len(files)} 项"
                    f" —— 分桶表与节点集不同步")

    # ⚠️ 必须是 tuple 而不是 set：set 的迭代顺序不确定，zip 到 AHK_BUCKET_KEYS
    # 上会张冠李戴（实测把 prod 的期望值对到了 test 的实算值上）。
    known = ("prod", "test", "tool", "unclassified")
    bad = sorted({v for v in buckets.values() if v not in known})
    if bad:
        errs.append(f"ahk.buckets 出现未知桶名：{bad}（合法值 {list(known)}）")

    recount = {k: 0 for k in known}
    for v in buckets.values():
        if v in recount:
            recount[v] += 1

    for key, name in zip(AHK_BUCKET_KEYS, known):
        if counts.get(key) != recount[name]:
            errs.append(f"{key} = {counts.get(key)}，但按 ahk.buckets 重算是 "
                        f"{recount[name]} —— 计数与分桶表不一致（build_graph.py 改了一边？）")

    total = sum(recount.values())
    if total != len(files):
        errs.append(f"分桶总数 {total} != ahk_files {len(files)} —— 有节点没被归类或被重复归类")

    if recount["unclassified"]:
        sample = sorted(p for p, v in buckets.items() if v == "unclassified")[:5]
        errs.append(f"有 {recount['unclassified']} 个 AHK 节点无法归入 prod/test/tool：{sample}"
                    f" —— 新增顶层目录请补 AHK_BUCKET_RULES，不要让它掉进洞里")

    # 边的分桶也必须穷尽：三个 from 桶之和 == 范围内边数
    e_prod = counts.get("ahk_edges_from_prod")
    e_test = counts.get("ahk_edges_from_test")
    e_tool = counts.get("ahk_edges_from_tool")
    if None not in (e_prod, e_test, e_tool):
        if e_prod + e_test + e_tool != counts.get("ahk_edges_in_scope"):
            errs.append(f"边分桶之和 {e_prod}+{e_test}+{e_tool} != ahk_edges_in_scope "
                        f"{counts.get('ahk_edges_in_scope')} —— 有边的来源桶没被统计")
    return errs


# 闸门侧**独立实现**一遍分桶规则，用来跟 build_graph.py 的产出对撞。
# 为什么要重复一份：上面只比对 counts 与 buckets 是否自洽，那防不住「两边一起改」。
# 这里由闸门自己按路径重判一遍，build_graph.py 的规则被偷偷改窄/改宽时当场暴露。
# ⚠️ 必须与 build_graph.py 的 AHK_BUCKET_RULES 保持一致 —— 不一致时本检查会
# 逐条报出分歧路径，那正是它存在的意义（不是噪音，是「两边谁改了」的报警器）。
GATE_BUCKET_RULES = (
    ("test", ("tests/", "asd-tauri/e2e/")),
    ("tool", ("tools/", "scripts/")),
    ("prod", ("domain/", "infrastructure/", "application/", "presentation/",
              "asd-tauri/src-tauri/ahk_executor/")),
)


def gate_ahk_bucket(rel_path: str) -> str:
    for name, prefixes in GATE_BUCKET_RULES:
        if rel_path.startswith(prefixes):
            return name
    return "prod" if "/" not in rel_path else "unclassified"


def check_bucket_classification(raw: dict) -> list[str]:
    """独立重判分桶（防 build_graph.py 偷偷改规则 / 防两边一起改的协同造假）。"""
    buckets = raw.get("ahk", {}).get("buckets")
    if not isinstance(buckets, dict) or not buckets:
        return []  # 缺失由 check_bucket_integrity 负责报错，不重复刷屏
    mismatch = []
    for p, claimed in sorted(buckets.items()):
        expect = gate_ahk_bucket(p)
        if expect != claimed:
            mismatch.append(f"{p}: 图里是 {claimed}，闸门重判是 {expect}")
    if not mismatch:
        return []
    return [f"{len(mismatch)} 个 AHK 节点的分桶与闸门独立重判不一致 —— "
            f"build_graph.py 的 AHK_BUCKET_RULES 与本文件的 GATE_BUCKET_RULES "
            f"已经漂移，请同步："
            + "; ".join(mismatch[:5])]


def check_extra_exclude_guard(raw: dict) -> list[str]:
    """TD-051：extra_exclude 规则有效性。判定在 build_graph.py，闸门只负责拦。

    为什么不在闸门里重算：判定要拿 tracked 全量文件列表（git 口径），闸门再跑一遍
    git 很容易和 build_graph.py 跑出两个口径。所以这里**只认图里的结论** ——
    字段缺失即说明跑的是旧实现，直接判失效，绝不默认通过。

    判据（与 build_graph.py 一致）：
      - rule_path_hits == 0 → 失效（路径拼错 / 目录被改名）
      - rule_excluded_count == 0 → **不算失效**，只是审计数字（预防性规则）
    """
    meta = raw.get("meta", {})
    rules = meta.get("extra_exclude_rules")
    if rules is None:
        return ["graph-raw.json 缺 `meta.extra_exclude_rules` —— 跑的是 TD-051 之前的"
                "旧 build_graph.py？extra_exclude 规则无人验证，闸门拒绝给出结论"
                "（请先重跑 `python .review-analysis/build_graph.py`）"]
    errs = list(raw.get("extra_exclude_rule_errors") or [])
    ok = meta.get("extra_exclude_rules_ok")
    if ok is False and not errs:
        errs.append("meta.extra_exclude_rules_ok=False 但没有具体错误项 —— "
                    "build_graph.py 的状态字段自相矛盾，请检查")
    if ok is None:
        errs.append("meta.extra_exclude_rules_ok 字段缺失 —— 图由旧实现生成")
    return ["extra_exclude 规则失效：" + e for e in errs]


def check_js_bucket_integrity(raw: dict, counts: dict) -> list[str]:
    """TD-051：JS 分桶必须与节点集一致（防漏归类 / 防计数与分桶表不同步）。"""
    js = raw.get("js", {})
    buckets = js.get("buckets")
    files = js.get("files", [])
    if not isinstance(buckets, dict) or not buckets:
        return ["graph-raw.json 缺 `js.buckets`（或为空）—— 跑的是 TD-051 之前的"
                "旧 build_graph.py？无法校验 JS 分桶口径"]
    errs = []
    if len(buckets) != len(files):
        errs.append(f"js.buckets 有 {len(buckets)} 项，但 js.files 有 {len(files)} 项")
    known = ("src", "e2e", "unclassified")
    recount = {k: 0 for k in known}
    for v in buckets.values():
        if v in recount:
            recount[v] += 1
    for key, name in (("js_src_files", "src"), ("js_e2e_files", "e2e"),
                      ("js_unclassified_files", "unclassified")):
        if counts.get(key) != recount[name]:
            errs.append(f"{key} = {counts.get(key)}，但按 js.buckets 重算是 "
                        f"{recount[name]} —— 计数与分桶表不一致")
    if sum(recount.values()) != len(files):
        errs.append(f"JS 分桶总数 {sum(recount.values())} != js_files {len(files)}")
    if recount["unclassified"]:
        sample = sorted(p for p, v in buckets.items() if v == "unclassified")[:5]
        errs.append(f"有 {recount['unclassified']} 个 JS 节点无法归入 src/e2e：{sample}"
                    f" —— 新增顶层目录请补 JS_BUCKET_RULES")
    return errs


def check_scan_anchors(counts: dict) -> list[str]:
    """遍历失效探针：低于下限 = 节点发现塌了，不是「代码变干净了」。"""
    errs = []
    for key, floor in SCAN_ANCHOR_MIN.items():
        cur = counts.get(key)
        if cur is None:
            errs.append(f"counts 缺键 `{key}` —— graph-raw.json 由旧版 build_graph.py 生成？")
        elif cur < floor:
            errs.append(f"{key} = {cur}，低于遍历锚点下限 {floor} —— 节点发现疑似失效"
                        f"（目录口径/extra_exclude/git 命令被改坏？）。"
                        f"若确系大规模删文件，请下调 SCAN_ANCHOR_MIN 并在 commit message 说明理由")
    return errs


def check_untracked(raw: dict) -> list[str]:
    """未跟踪源文件会把「开发机的图」和「CI 的图」变成两张图（TD-049①）。

    build_graph.py 已只取 tracked 文件，所以这些文件**污染不到基线数字** ——
    但代价是它们也没被分析。闸门必须拦：否则开发者以为闸门看过自己的新文件，
    实际上 CI 才会第一次见到它。
    """
    counts = raw.get("meta", {}).get("counts", {})
    untracked = raw.get("untracked_files", {})
    total = sum(counts.get(f"{k}_files_untracked", 0) for k in ("ahk", "rust", "js"))
    if not total:
        return []
    listed = []
    for kind in ("ahk", "rust", "js"):
        for p in untracked.get(kind, [])[:20]:
            listed.append(f"{kind}: {p}")
    return [f"有 {total} 个**未跟踪且未被 .gitignore 忽略**的源文件 —— 它们只存在于开发机，"
            f"不进基线数字（已隔离），但也因此**没被本闸门分析到**："
            + "; ".join(listed)
            + "。请 `git add` 后重跑，或确认是临时文件后删除 / 加入 .gitignore"]


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
        # 键集取并集（旧实现只遍历 base_counts，导致 build_graph.py 新增的度量
        # **永远写不进基线** —— 新口径会静默失效。顺序：先旧键后新键，diff 才好看。）
        ordered = list(base_counts) + [k for k in cur_counts if k not in base_counts]
        baseline["counts"] = {
            k: cur_counts.get(k, base_counts.get(k)) for k in ordered
        }
        allowed = [
            {"from": v["from"], "to": v["to"],
             "reason": v.get("reason", ""), "expires": v.get("expires", "")}
            for v in findings.get("rust_crate_violations", [])
        ]
        baseline["allowed_violations"] = allowed
        with BASELINE.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(baseline, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"OK: 基线已更新 -> {BASELINE.relative_to(REPO_ROOT)}")
        print("    请复核 diff 后提交（可能掩盖真实回归，务必人工确认）")
        if allowed:
            print(f"    ⚠️ {len(allowed)} 条豁免的 reason / expires 是空的 ——"
                  f"**必须补全后闸门①才会绿**（TD-009 起强制）")
        return 0

    errors: list[str] = []
    warnings: list[str] = []

    # 1) 硬失败：数值只增不减
    for key in HARD_FAIL_GREATER:
        cur = cur_counts.get(key, 0)
        base = base_counts.get(key, 0)
        if cur > base:
            errors.append(f"{key}: {base} -> {cur}（增加 {cur - base}）")

    # 2) 硬失败：白名单条目的卫生（必须有理由与未过期的期限，TD-009）
    errors.extend(check_exemption_hygiene(baseline))

    # 2a) 硬失败：分桶口径完整性 / 遍历锚点 / 未跟踪文件（TD-049①）
    errors.extend(check_bucket_integrity(raw))
    errors.extend(check_bucket_classification(raw))
    errors.extend(check_js_bucket_integrity(raw, cur_counts))
    errors.extend(check_extra_exclude_guard(raw))
    errors.extend(check_scan_anchors(cur_counts))
    errors.extend(check_untracked(raw))

    # 2b) 硬失败：白名单外的新依赖违规
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
    # js_cycles 也要打印明细：只报「0 -> 1」而不知道是哪两个文件绕成环，等于让人瞎猜
    for name in ("ahk_cycles", "rust_crate_cycles", "js_cycles"):
        cycles = findings.get(name, [])
        if cycles:
            errors.append(f"{name} 明细: {json.dumps(cycles, ensure_ascii=False)}")

    print("=" * 60)
    print("闸门① 图谱基线校验")
    print("=" * 60)
    print(
        f"  AHK   {cur_counts.get('ahk_files')} 文件 "
        f"(生产 {cur_counts.get('ahk_prod_files')} / "
        f"测试 {cur_counts.get('ahk_test_files')} / "
        f"工具 {cur_counts.get('ahk_tool_files')} / "
        f"未归类 {cur_counts.get('ahk_unclassified_files')}) / "
        f"{cur_counts.get('ahk_edges_total')} 边 / "
        f"{cur_counts.get('ahk_cycles')} 环 / "
        f"{cur_counts.get('ahk_orphans')} 孤点"
        f"(生产 {cur_counts.get('ahk_orphans_prod')}) / "
        f"倒灌边 {cur_counts.get('ahk_prod_to_nonprod_edges')} / "
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
        f"  JS    {cur_counts.get('js_files')} 文件 "
        f"(src {cur_counts.get('js_src_files')} / "
        f"e2e {cur_counts.get('js_e2e_files')} / "
        f"未归类 {cur_counts.get('js_unclassified_files')}) / "
        f"{cur_counts.get('js_edges')} import 边"
        f"(非内建) + {cur_counts.get('js_builtin_edges')} 内建边 / "
        f"图内边 {cur_counts.get('js_edges_internal')} / "
        f"环 {cur_counts.get('js_cycles')}"
    )
    for r in (raw.get("meta", {}).get("extra_exclude_rules") or []):
        print(f"  [excl {'OK  ' if r.get('ok') else 'FAIL'}] {r.get('rule')}"
              f"  路径命中 {r.get('rule_path_hits')} / 本次排除 {r.get('rule_excluded_count')}")

    if warnings:
        print("\n[WARN] 结构变化（不阻塞，供人工确认）:")
        for w in warnings:
            print(f"  - {w}")

    ext_refs = findings.get("ahk_external_refs", [])
    if ext_refs:
        print(f"\n[INFO] {len(ext_refs)} 个 AHK 节点被 JS/TS/Shell 按路径引用"
              f"（因此不算孤点，逐条留痕以防放水）:")
        for r in ext_refs[:20]:
            print(f"  - {r.get('ahk')}  <-  {r.get('via')}:{r.get('line')}")

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
