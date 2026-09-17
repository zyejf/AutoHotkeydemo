"""构建项目依赖图谱（AHK + Rust + 前端）——只读分析脚本。"""
import os
import re
import json
import io
import sys
import subprocess

# Windows CI runner 上 stdio 默认走系统 ANSI 代码页（cp1252），print 中文会
# UnicodeEncodeError。显式切 UTF-8；本地若已是 UTF-8 则无副作用。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# 项目根由脚本自身位置推导（.review-analysis/ 的上一级），
# 避免硬编码绝对路径导致 CI（不同 checkout 目录）上 FileNotFoundError。
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".review-analysis")
EXCLUDE_DIRS = {"AutoHotkey-2.0.26", "target", "node_modules", ".git", "dist"}
EXCLUDE_SEG = ("AutoHotkey-2.0.26", "asd-tauri/target", "node_modules", "/.git")
# 非活跃代码：审查快照副本、归档测试、第三方 lib
INACTIVE_SEG = (
    "docs/review/",          # 审查历史快照（含 workspace-snapshot 代码副本）
    "tests/archive/",        # 归档测试
    "tests/lib/",            # 第三方 AHK 库
    "test_output/",
    "lib/ahk2_lib/",
)


def norm(p):
    return p.replace("\\", "/")


def _git_lines(args):
    """跑 git 并分行返回；失败即抛出。

    为什么不在 git 不可用时退回 os.walk：退回等于悄悄接受「不同环境算出不同的图」，
    那正是 TD-025 要消灭的东西 —— 宁可响亮地失败，也不要一个看着绿实则不可比的数。"""
    try:
        r = subprocess.run(["git"] + args, cwd=ROOT, capture_output=True, text=True)
    except FileNotFoundError:
        raise RuntimeError("找不到 git：图谱节点发现依赖 git 口径，无法降级为裸扫文件系统")
    if r.returncode != 0:
        raise RuntimeError("git %s 失败（当前目录是 git 仓库吗？）：%s"
                           % (" ".join(args), r.stderr.strip()))
    return [x.strip() for x in r.stdout.splitlines() if x.strip()]


def _git_source_files(exts, extra_exclude=()):
    """返回 (tracked, untracked) 两组绝对路径，两组**永不相加**。

    为什么不用 os.walk 裸扫文件系统：裸扫会把被 .gitignore 忽略的本地产物也
    算成节点 —— 实测吃到 `_diag.ahk` / `_mock.ahk` / `_rt.ahk` 三个临时脚本，
    以及 `asd-tauri/coverage/html/control.js`（覆盖率报告产物）。它们只在开发机
    存在、CI 全新 checkout 没有（TD-025）。

    ⚠️ TD-049①：为什么这里把「已跟踪」与「未跟踪但未 ignore」**拆成两桶**：
    旧实现是 `git ls-files --cached --others --exclude-standard` 一把梭，然后
    把两组之和当成节点集。`--others` 出来的文件**只存在于开发机** —— CI 全新
    checkout 上它们一个都没有。于是基线文件里那句「本基线在开发机与 CI 全新
    checkout 上应当一致」是**假的**：只要有人留一个没提交的 `foo.ahk`，开发机
    `ahk_files` 就是 93、CI 仍是 92，棘轮闸门直接失去比较意义。
    （实测当前工作区就躺着 5 个未跟踪文件，只是恰好不是 .ahk/.rs/.js 才没爆。）

    拆法：
      - tracked  = 已跟踪（CI 与开发机一致）→ **唯一进基线的可比数字**
      - untracked= 未跟踪且未被 ignore（仅开发机）→ 单独计数并交由闸门拦下，
        绝不并入任何基线对比项。

    与 scripts/check-tech-debt.py 的 C6 检查同一个 tracked 口径，两边保持一致。
    """
    def _select(lines):
        out = []
        for p in lines:
            p = norm(p)
            if not p.lower().endswith(exts):
                continue
            if any(e in p for e in EXCLUDE_SEG) or any(e in p for e in extra_exclude):
                continue
            if any(seg in EXCLUDE_DIRS for seg in p.split("/")):
                continue
            # 已跟踪但工作区里已被删（删了没 git rm）：不能当节点，否则 read_text 抛异常。
            if not os.path.isfile(os.path.join(ROOT, p)):
                continue
            out.append(os.path.join(ROOT, p))
        return sorted(out)

    return (_select(_git_lines(["ls-files", "--cached"])),
            _select(_git_lines(["ls-files", "--others", "--exclude-standard"])))


def git_scope_files(exts, extra_exclude=()):
    """**可复现**的节点集：只取 git 已跟踪文件。见 _git_source_files 的说明。"""
    tracked, _ = _git_source_files(exts, extra_exclude)
    return tracked


def git_untracked_files(exts, extra_exclude=()):
    """未跟踪且未被 .gitignore 忽略的源文件 —— 只存在于开发机，进不了基线。

    交给闸门①硬失败：这些文件不会被本图分析到（它们不在 tracked 集里），
    也就是「你本地看到的图」漏了它们。要么 git add 后重跑，要么加进 .gitignore。
    """
    _, untracked = _git_source_files(exts, extra_exclude)
    return untracked


def read_text(path):
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            with io.open(path, "r", encoding=enc, errors="strict") as fh:
                return fh.read()
        except (UnicodeDecodeError, LookupError):
            continue
    with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


# ---------------------------------------------------------------- AHK
AHK_LAYERS = {
    "domain": "domain",
    "infrastructure": "infrastructure",
    "application": "application",
    "presentation": "presentation",
    "tests": "tests",
    "entry": "(root)",
    "executor": "asd-tauri/src-tauri/ahk_executor",
}


def ahk_layer(rel_path):
    p = rel_path
    for name, prefix in AHK_LAYERS.items():
        if prefix == "(root)":
            if "/" not in p:
                return "entry"
        elif p.startswith(prefix + "/"):
            return name
    return "other"


# ---------------------------------------------------------------- AHK 分桶
# TD-049①：`ahk_files` 曾是一个**混桶** —— 一个标量里同时装着生产代码（root
# 入口 + 四层 + ahk_executor）、测试代码（tests/、e2e fixtures）和工具/探针
#（tools/ahk-bench、tools/ahk-probes、scripts/perf）。后果是基线 WARNING 不可判定：
# 删 5 个测试脚本和删 5 个生产文件在 `ahk_files: 97 -> 92` 里长得一模一样，
# reviewer 看到 -5 根本分不清这是清债还是事故。
#
# 三个桶语义互不相交，且**必须穷尽** —— 新增顶层目录若没被任何规则命中，
# 会落进 `unclassified`，由闸门①硬失败（而不是悄悄丢进某个桶里稀释掉）。
AHK_BUCKET_RULES = (
    ("test", ("tests/", "asd-tauri/e2e/")),
    ("tool", ("tools/", "scripts/")),
    ("prod", ("domain/", "infrastructure/", "application/", "presentation/",
              "asd-tauri/src-tauri/ahk_executor/")),
)
AHK_BUCKETS = ("prod", "test", "tool", "unclassified")


def ahk_bucket(rel_path):
    """把 AHK 节点归入 prod / test / tool 之一；无法归类时返回 `unclassified`（应恒为 0）。"""
    for name, prefixes in AHK_BUCKET_RULES:
        if rel_path.startswith(prefixes):
            return name
    if "/" not in rel_path:
        return "prod"  # 仓库根入口脚本（main.ahk / asd.ahk）
    return "unclassified"


def build_ahk(include_inactive=False):
    files = git_scope_files((".ahk",))
    if not include_inactive:
        files = [f for f in files if not any(s in norm(f) for s in INACTIVE_SEG)]
    rel = {f: norm(os.path.relpath(f, ROOT)) for f in files}
    inc_re = re.compile(r'^[ \t]*#Include\s+(?:"([^"]+)"|(\S+))', re.IGNORECASE | re.M)
    edges, missing = [], []
    for absf, r in sorted(rel.items()):
        txt = read_text(absf)
        for m in inc_re.finditer(txt):
            spec = norm(m.group(1) or m.group(2))
            cand = norm(os.path.normpath(os.path.join(norm(os.path.dirname(r)), spec)))
            ok = os.path.isfile(os.path.join(ROOT, cand))
            if not ok and not cand.lower().endswith(".ahk"):
                cand2 = cand + ".ahk"
                if os.path.isfile(os.path.join(ROOT, cand2)):
                    cand, ok = cand2, True
            # 判断目标是否在分析范围内（跨出范围的边单独标记）
            in_scope = ok and not any(s in cand for s in INACTIVE_SEG) and cand in rel.values()
            fb, tb = ahk_bucket(r), ahk_bucket(cand) if in_scope else "out-of-scope"
            edges.append({
                "from": r, "to": cand, "resolved": ok, "in_scope": in_scope,
                "from_layer": ahk_layer(r), "to_layer": ahk_layer(cand) if in_scope else "out-of-scope",
                "is_layer_cross": in_scope and ahk_layer(r) != ahk_layer(cand),
                "from_bucket": fb, "to_bucket": tb,
                # 生产代码 #Include 测试/工具代码 = 架构倒灌，必须单独计数
                "is_bucket_cross_bad": in_scope and fb == "prod" and tb != "prod",
            })
            if not ok:
                missing.append({"from": r, "to": cand})
    return {"files": sorted(rel.values()), "edges": edges, "missing": missing}


# ------------------------------------------------- AHK 跨语言引用（孤点误报修正）
# AHK 脚本经常由 JS/TS/Shell 以子进程方式**按路径拉起**，这类引用不经过
# `#Include`，纯 AHK 图上看不见 —— 于是「在用文件」被判成孤点。典型受害者：
# `asd-tauri/e2e/fixtures/key_receiver.ahk`（由 `e2e/helpers/key_receiver.js`
# spawn，进而被 key_send / ipc / modes 等 spec 使用），TD-049 已判为误报。
#
# ⚠️ 防「把真孤点放过去」的三条约束：
#   1. 只认**带引号的字面量**（`join(fixturesDir,'key_receiver.ahk')` 认，
#      注释里提一句不认 —— 虽然做不到完美，但证据行号会写进 findings 供复核）；
#   2. 只扫源码扩展名 .js/.mjs/.cjs/.ts/.sh，不扫 md/json（文档提及不算在用）；
#   3. **基名歧义不赦** —— 若同一个 basename 对应多个 AHK 文件，这条引用不作为
#      免罪证据（否则一个 `_harness.ahk` 的引用会顺带赦免另一个同名文件）。
AHK_REF_SCAN_EXT = (".js", ".mjs", ".cjs", ".ts", ".sh")


def find_ahk_external_refs(ahk_files, scan_files):
    """返回 [{"ahk": 相对路径, "via": 引用它的文件, "line": 行号, "text": 原文片段}]。"""
    base_index = {}
    for p in ahk_files:
        base_index.setdefault(os.path.basename(p), []).append(p)

    pats = {b: re.compile(r"""["']([^"']*%s)["']""" % re.escape(b)) for b in base_index}
    refs, seen = [], set()
    for absf in scan_files:
        try:
            txt = read_text(absf)
        except OSError:
            continue
        rel_via = norm(os.path.relpath(absf, ROOT))
        for i, line in enumerate(txt.splitlines(), 1):
            if ".ahk" not in line:
                continue
            for b, pat in pats.items():
                for m in pat.finditer(line):
                    mstr = norm(m.group(1))
                    if "/" in mstr:
                        hits = [p for p in ahk_files
                                if p == mstr or p.endswith("/" + mstr)]
                    else:
                        cand = base_index.get(b, [])
                        # 基名歧义 → 不赦（见上方约束 3）
                        hits = cand if len(cand) == 1 else []
                    for h in hits:
                        key = (h, rel_via, i)
                        if key in seen:
                            continue
                        seen.add(key)
                        refs.append({"ahk": h, "via": rel_via, "line": i,
                                     "text": line.strip()[:160]})
    return sorted(refs, key=lambda x: (x["ahk"], x["via"], x["line"]))


# ---------------------------------------------------------------- Rust
RUST_CRATES = ("asd-domain", "asd-ipc-protocol", "asd-application", "asd-test-harness", "src-tauri")


def rust_crate(rel_path):
    p = rel_path
    if p.startswith("asd-tauri/crates/"):
        rest = p[len("asd-tauri/crates/"):]
        return rest.split("/")[0]
    if p.startswith("asd-tauri/src-tauri/"):
        return "src-tauri"
    return "other"


# 允许的 crate 依赖方向（依据 AGENTS.md 声明的架构）
# 生产依赖方向：domain <- ipc-protocol 为底层，application 居中，src-tauri 为顶层
# 依赖方向：ipc-protocol 最底，domain 次之，application 再次，src-tauri 最上；
# asd-test-harness 位于 **tests 层（最深）**，依赖被测代码是它的本体职责
#（它 `pub use` 了 domain 的 trait / 类型，并用到 `AppState`），故允许向下依赖三者。
#
# ⚠️ 这里原本是 `set()`（空集），于是它 Cargo.toml 里的 3 个生产依赖全被判成
#「违规」并塞进基线的 allowed_violations —— 但那不是豁免，是**漏填**
#（TD-009，2026-09-16 更正）。反向才是真风险，且已被挡住：
# 三个生产 crate 的白名单里都没有 asd-test-harness。
#
# ⚠️ 另一个必须保持的现状：`asd-application` 的 **[dev-dependencies] 里有
# asd-test-harness**，与下面的生产边构成 **dev 依赖环**。这是 Rust 集成测试辅助
# crate 的标准做法（cargo 允许 dev-dep 环），图谱按既定策略只检测生产边。
# **但这条边必须保持 dev-only** —— 一旦挪进 [dependencies] 就是真正的生产环。
ALLOWED_CRATE_DEPS = {
    "asd-domain": {"asd-ipc-protocol"},
    "asd-ipc-protocol": set(),
    "asd-application": {"asd-domain", "asd-ipc-protocol"},
    "asd-test-harness": {"asd-domain", "asd-ipc-protocol", "asd-application"},
    "src-tauri": {"asd-domain", "asd-ipc-protocol", "asd-application", "asd-test-harness"},
}


def parse_cargo_deps(path):
    """解析 Cargo.toml，区分生产依赖与 dev-dependencies。"""
    txt = read_text(path)
    prod, dev = set(), set()
    section = None
    for raw in txt.splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line.strip("[]").strip()
            continue
        m = re.match(r'^(asd-[a-z\-]+)\s*=', line)
        if not m:
            continue
        name = m.group(1)
        if section == "dev-dependencies":
            dev.add(name)
        elif section in ("dependencies", "build-dependencies"):
            prod.add(name)
    return prod, dev


def build_rust():
    files = git_scope_files((".rs",), extra_exclude=("asd-tauri/src-tauri/gen",))
    rel = {f: norm(os.path.relpath(f, ROOT)) for f in files}
    use_re = re.compile(r'^\s*(?:pub\s+)?use\s+(crate|super|self|asd_[a-z_]+)::([A-Za-z0-9_:{]*)', re.M)

    prod_deps, dev_deps = {}, {}
    for f in files:
        if f.endswith("Cargo.toml") and "/crates/" not in norm(f):
            pass
    for f in git_scope_files((".toml",)):
        if f.endswith("Cargo.toml"):
            r = rel.get(f)
            if r is None:
                r = norm(os.path.relpath(f, ROOT))
                rel[f] = r
            owner = rust_crate(r)
            p, d = parse_cargo_deps(f)
            if owner != "other":
                prod_deps.setdefault(owner, set()).update(p)
                dev_deps.setdefault(owner, set()).update(d)

    edges = []
    for absf, r in sorted(rel.items()):
        if not r.endswith(".rs"):
            continue
        txt = read_text(absf)
        is_test_file = "/tests/" in ("/" + r) or r.endswith("_tests.rs") or "/tests.rs" in r
        for m in use_re.finditer(txt):
            root, path = m.group(1), m.group(2)
            tgt = (root + "::" + path).rstrip(":")
            edges.append({
                "from": r, "kind": root, "to": tgt,
                "crate": rust_crate(r),
                "in_test_file": is_test_file,
            })

    crate_edges = []
    for e in edges:
        if e["kind"].startswith("asd_"):
            dep = e["kind"].replace("_", "-")
            src = e["crate"]
            if dep in RUST_CRATES and dep != src:
                is_dev_only = dep in dev_deps.get(src, set()) and dep not in prod_deps.get(src, set())
                ok = dep in ALLOWED_CRATE_DEPS.get(src, set())
                crate_edges.append({
                    "from": src, "to": dep, "file": e["from"],
                    "declared_dev_only": is_dev_only,
                    "in_test_file": e["in_test_file"],
                    "allowed": ok,
                    # 仅「生产依赖方向违规」才算真违规
                    "is_violation": (not ok) and not is_dev_only,
                })
    agg = {}
    for e in crate_edges:
        k = (e["from"], e["to"])
        if k not in agg:
            agg[k] = {
                "from": e["from"], "to": e["to"], "allowed": e["allowed"],
                "declared_dev_only": e["declared_dev_only"],
                "is_violation": e["is_violation"], "sites": [],
            }
        agg[k]["sites"].append(e["file"])
        agg[k]["declared_dev_only"] = agg[k]["declared_dev_only"] and e["declared_dev_only"]
        agg[k]["is_violation"] = agg[k]["is_violation"] or e["is_violation"]
    # 仅保留生产依赖边用于环检测
    prod_crate_edges = [v for v in agg.values() if not v["declared_dev_only"]]

    return {
        "files": sorted(rel.values()),
        "edges": edges,
        "crate_edges": list(agg.values()),
        "prod_crate_edges": prod_crate_edges,
        "dev_deps": {k: sorted(v) for k, v in dev_deps.items()},
        "prod_deps": {k: sorted(v) for k, v in prod_deps.items()},
    }


# ---------------------------------------------------------------- JS
def build_js():
    # ⚠️ 尾斜杠不能去掉：extra_exclude 走的是子串匹配，而 git_scope_files 给的是
    # **仓库相对路径**，`asd-tauri/e2e/wdio.conf.js` 含 `asd-tauri/e2e/`。
    # 旧实现走 os.walk、比对的是目录绝对路径（末尾没有斜杠），这条规则从来没生效过，
    # wdio.conf.js 一直被当成节点、还贡献了 5 条 node: 内建模块边（TD-025 顺带修正）。
    files = git_scope_files((".js", ".mjs"), extra_exclude=("asd-tauri/e2e/",))
    rel = {f: norm(os.path.relpath(f, ROOT)) for f in files}
    imp_re = re.compile(r'^\s*import\s+(?:[^"\']*from\s+)?["\']([^"\']+)["\']', re.M)
    edges = []
    for absf, r in sorted(rel.items()):
        txt = read_text(absf)
        for m in imp_re.finditer(txt):
            edges.append({"from": r, "to": m.group(1)})
    return {"files": sorted(rel.values()), "edges": edges}


# ---------------------------------------------------------------- 图分析
def find_cycles(nodes, edges, key_from="from", key_to="to"):
    """Tarjan 强连通分量 → 找出所有 SCC（size>1 即环）。"""
    adj = {n: [] for n in nodes}
    for e in edges:
        a, b = e.get(key_from), e.get(key_to)
        if a in adj and b in adj:
            adj[a].append(b)

    index = {}
    low = {}
    on_stack = {}
    stack = []
    sccs = []
    counter = [0]

    def strongconnect(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on_stack[v] = True
        for w in adj[v]:
            if w not in index:
                strongconnect(w)
                low[v] = min(low[v], low[w])
            elif on_stack.get(w):
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on_stack[w] = False
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1:
                sccs.append(sorted(comp))
    for n in nodes:
        if n not in index:
            strongconnect(n)
    return sccs


def find_orphans(nodes, edges, key_from="from", key_to="to", ignore_no_in=()):
    """孤点：无入边且无出边的节点（排除入口文件）。"""
    has_in = {e.get(key_to) for e in edges}
    has_out = {e.get(key_from) for e in edges}
    out = []
    for n in nodes:
        if n in ignore_no_in:
            continue
        if n not in has_in and n not in has_out:
            out.append(n)
    return sorted(out)


if __name__ == "__main__":
    ahk = build_ahk()
    rust = build_rust()
    js = build_js()

    # 未跟踪源文件：只存在于开发机，绝不进基线数字（TD-049①）
    untracked = {
        "ahk": [norm(os.path.relpath(p, ROOT))
                for p in git_untracked_files((".ahk",))],
        "rust": [norm(os.path.relpath(p, ROOT))
                 for p in git_untracked_files((".rs", ".toml",))],
        "js": [norm(os.path.relpath(p, ROOT))
               for p in git_untracked_files((".js", ".mjs"))],
    }

    ahk_nodes = ahk["files"]
    ahk_scope_edges = [e for e in ahk["edges"] if e["in_scope"]]
    ahk_cycles = find_cycles(ahk_nodes, ahk_scope_edges)

    # 分桶（TD-049①）：生产 / 测试 / 工具 三个互不相交的桶
    ahk_buckets = {p: ahk_bucket(p) for p in ahk_nodes}
    bucket_counts = {b: sum(1 for p in ahk_nodes if ahk_buckets[p] == b)
                     for b in AHK_BUCKETS}

    # 跨语言引用 → 修掉「被 JS/Shell 拉起、却在纯 AHK 图上是孤点」的误报
    # 注意这里**不加** build_js() 那个 extra_exclude=("asd-tauri/e2e/",)：
    # e2e 目录虽被排除在 JS 节点之外，却恰恰是 AHK 跨语言引用的主要来源。
    ref_scan_files = git_scope_files(AHK_REF_SCAN_EXT)
    ahk_ext_refs = find_ahk_external_refs(ahk_nodes, ref_scan_files)
    externally_used = {r["ahk"] for r in ahk_ext_refs}

    # 入口脚本没有入边是天经地义的（整个程序的根），不算孤点
    ahk_entry_nodes = ("main.ahk", "asd.ahk")
    ahk_orphans_all = [n for n in find_orphans(
        ahk_nodes, ahk_scope_edges, ignore_no_in=ahk_entry_nodes)
        if n not in externally_used]
    ahk_orphans_prod = [n for n in ahk_orphans_all
                        if ahk_buckets[n] == "prod"]

    crate_nodes = [c for c in RUST_CRATES if any(rust_crate(f) == c for f in rust["files"])]
    # 环检测只用生产依赖边
    crate_cycles = find_cycles(crate_nodes, rust["prod_crate_edges"])

    # AHK 分层交叉统计
    layer_matrix = {}
    for e in ahk_scope_edges:
        if e["is_layer_cross"]:
            k = e["from_layer"] + " -> " + e["to_layer"]
            layer_matrix[k] = layer_matrix.get(k, 0) + 1

    graph = {
        "meta": {
            "root": ROOT,
            "counts": {
                "ahk_files": len(ahk["files"]),
                # TD-049① 分桶：三个桶互不相交，且 prod+test+tool+unclassified == ahk_files
                "ahk_prod_files": bucket_counts["prod"],
                "ahk_test_files": bucket_counts["test"],
                "ahk_tool_files": bucket_counts["tool"],
                "ahk_unclassified_files": bucket_counts["unclassified"],
                "ahk_edges_total": len(ahk["edges"]),
                "ahk_edges_in_scope": len(ahk_scope_edges),
                "ahk_edges_from_prod": sum(1 for e in ahk_scope_edges
                                           if e["from_bucket"] == "prod"),
                "ahk_edges_from_test": sum(1 for e in ahk_scope_edges
                                           if e["from_bucket"] == "test"),
                "ahk_edges_from_tool": sum(1 for e in ahk_scope_edges
                                           if e["from_bucket"] == "tool"),
                # 生产代码 #Include 测试/工具代码：架构倒灌，硬失败项
                "ahk_prod_to_nonprod_edges": sum(1 for e in ahk_scope_edges
                                                 if e["is_bucket_cross_bad"]),
                "ahk_missing": len(ahk["missing"]),
                "ahk_cycles": len(ahk_cycles),
                "ahk_orphans": len(ahk_orphans_all),
                "ahk_orphans_prod": len(ahk_orphans_prod),
                # 未跟踪源文件数：>0 即表示本地图与 CI 图不同，基线不可比
                "ahk_files_untracked": len(untracked["ahk"]),
                "rust_files_untracked": len(untracked["rust"]),
                "js_files_untracked": len(untracked["js"]),
                "rust_files": len(rust["files"]),
                "rust_edges": len(rust["edges"]),
                "rust_crate_edges": len(rust["crate_edges"]),
                "rust_crate_cycles": len(crate_cycles),
                "rust_crate_violations": sum(1 for e in rust["crate_edges"] if e["is_violation"]),
                "js_files": len(js["files"]),
                "js_edges": len(js["edges"]),
            },
        },
        "findings": {
            "ahk_cycles": ahk_cycles,
            "ahk_orphans": ahk_orphans_all,
            "ahk_orphans_prod": ahk_orphans_prod,
            # 被 JS/TS/Shell 按路径拉起的 AHK（证据行号），用于审计「孤点豁免」不是放水
            "ahk_external_refs": ahk_ext_refs,
            "ahk_missing_includes": ahk["missing"],
            "ahk_layer_cross": layer_matrix,
            "rust_crate_cycles": crate_cycles,
            "rust_crate_violations": [e for e in rust["crate_edges"] if e["is_violation"]],
        },
        "untracked_files": untracked,
        "ahk": {"files": ahk["files"], "edges": ahk_scope_edges, "buckets": ahk_buckets},
        "rust": {
            "files": rust["files"],
            "crate_edges": rust["crate_edges"],
            "prod_crate_edges": rust["prod_crate_edges"],
            "prod_deps": rust["prod_deps"],
            "dev_deps": rust["dev_deps"],
        },
        "js": js,
    }
    with io.open(os.path.join(OUT, "graph-raw.json"), "w", encoding="utf-8") as fh:
        json.dump(graph, fh, ensure_ascii=False, indent=2)

    m = graph["meta"]["counts"]
    print("== 图谱原始数据 ==")
    print("AHK  文件: %(ahk_files)d  (生产 %(ahk_prod_files)d / 测试 %(ahk_test_files)d"
          " / 工具 %(ahk_tool_files)d / 未归类 %(ahk_unclassified_files)d)" % m)
    print("AHK  边(总): %(ahk_edges_total)d | 边(范围内): %(ahk_edges_in_scope)d"
          "  [生产出边 %(ahk_edges_from_prod)d / 测试出边 %(ahk_edges_from_test)d"
          " / 工具出边 %(ahk_edges_from_tool)d]" % m)
    print("AHK  生产->非生产 倒灌边: %(ahk_prod_to_nonprod_edges)d | 未解析: %(ahk_missing)d" % m)
    print("AHK  环: %(ahk_cycles)d | 孤点: %(ahk_orphans)d (其中生产孤点 %(ahk_orphans_prod)d)" % m)
    print("Rust 文件: %(rust_files)d | use 边: %(rust_edges)d | crate 边: %(rust_crate_edges)d" % m)
    print("Rust 生产 crate 环: %(rust_crate_cycles)d | 生产依赖违规: %(rust_crate_violations)d" % m)
    print("JS   文件: %(js_files)d | import 边: %(js_edges)d" % m)
    print()
    print("-- crate 生产依赖方向 --")
    for c, deps in sorted(rust["prod_deps"].items()):
        print("    %-20s -> %s" % (c, ", ".join(deps) or "(无)"))
    print("-- crate 测试依赖(dev-dependencies) --")
    for c, deps in sorted(rust["dev_deps"].items()):
        print("    %-20s -> %s" % (c, ", ".join(deps) or "(无)"))
    print()
    if ahk_cycles:
        print("-- AHK 循环依赖 --")
        for c in ahk_cycles:
            print("   ", "  <->  ".join(c))
    if crate_cycles:
        print("-- Rust crate 循环依赖 --")
        for c in crate_cycles:
            print("   ", "  <->  ".join(c))
    if graph["findings"]["rust_crate_violations"]:
        print("-- Rust crate 依赖方向违规 --")
        for v in graph["findings"]["rust_crate_violations"]:
            print("    %s -> %s  (%d 处)" % (v["from"], v["to"], len(v["sites"])))
    if ahk_orphans_all:
        print("-- AHK 孤点（无任何 #Include 关系、也未被 JS/TS/Shell 按路径引用）--")
        for o in ahk_orphans_all:
            print("   ", o, "[%s]" % ahk_buckets[o])
    if ahk_ext_refs:
        print("-- AHK 跨语言引用（因此不算孤点，供审计）--")
        for r in ahk_ext_refs:
            print("    %s  <-  %s:%d" % (r["ahk"], r["via"], r["line"]))
    for kind in ("ahk", "rust", "js"):
        if untracked[kind]:
            print("-- 未跟踪源文件（%s）：不进基线数字，闸门①会拦 --" % kind)
            for p in untracked[kind]:
                print("   ", p)
    print()
    print("-- AHK 分层交叉边 TOP --")
    for k, v in sorted(layer_matrix.items(), key=lambda x: -x[1])[:15]:
        print("    %-40s %d" % (k, v))
    print()
    print("-- 范围外/未解析的边（前 20）--")
    shown = 0
    for e in ahk["edges"]:
        if not e["in_scope"] and shown < 20:
            print("    %s -> %s  [%s]" % (e["from"], e["to"],
                                          "MISSING" if not e["resolved"] else "out-of-scope"))
            shown += 1
    print("    ... 共 %d 条" % sum(1 for e in ahk["edges"] if not e["in_scope"]))
