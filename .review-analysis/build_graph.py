"""构建项目依赖图谱（AHK + Rust + 前端）——只读分析脚本。"""
import os
import re
import json
import io
import sys

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


def walk_files(exts, extra_exclude=()):
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rp = norm(dirpath)
        if any(e in rp for e in EXCLUDE_SEG) or any(e in rp for e in extra_exclude):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            if fn.lower().endswith(exts):
                found.append(norm(os.path.join(dirpath, fn)))
    return sorted(found)


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


def build_ahk(include_inactive=False):
    files = walk_files((".ahk",))
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
            edges.append({
                "from": r, "to": cand, "resolved": ok, "in_scope": in_scope,
                "from_layer": ahk_layer(r), "to_layer": ahk_layer(cand) if in_scope else "out-of-scope",
                "is_layer_cross": in_scope and ahk_layer(r) != ahk_layer(cand),
            })
            if not ok:
                missing.append({"from": r, "to": cand})
    return {"files": sorted(rel.values()), "edges": edges, "missing": missing}


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
ALLOWED_CRATE_DEPS = {
    "asd-domain": {"asd-ipc-protocol"},
    "asd-ipc-protocol": set(),
    "asd-application": {"asd-domain", "asd-ipc-protocol"},
    "asd-test-harness": set(),
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
    files = walk_files((".rs",), extra_exclude=("asd-tauri/src-tauri/gen",))
    rel = {f: norm(os.path.relpath(f, ROOT)) for f in files}
    use_re = re.compile(r'^\s*(?:pub\s+)?use\s+(crate|super|self|asd_[a-z_]+)::([A-Za-z0-9_:{]*)', re.M)

    prod_deps, dev_deps = {}, {}
    for f in files:
        if f.endswith("Cargo.toml") and "/crates/" not in norm(f):
            pass
    for f in walk_files((".toml",)):
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
    files = walk_files((".js", ".mjs"), extra_exclude=("asd-tauri/e2e/",))
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

    ahk_nodes = ahk["files"]
    ahk_scope_edges = [e for e in ahk["edges"] if e["in_scope"]]
    ahk_cycles = find_cycles(ahk_nodes, ahk_scope_edges)
    ahk_orphans = find_orphans(ahk_nodes, ahk_scope_edges, ignore_no_in=("main.ahk",))

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
                "ahk_edges_total": len(ahk["edges"]),
                "ahk_edges_in_scope": len(ahk_scope_edges),
                "ahk_missing": len(ahk["missing"]),
                "ahk_cycles": len(ahk_cycles),
                "ahk_orphans": len(ahk_orphans),
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
            "ahk_orphans": ahk_orphans,
            "ahk_missing_includes": ahk["missing"],
            "ahk_layer_cross": layer_matrix,
            "rust_crate_cycles": crate_cycles,
            "rust_crate_violations": [e for e in rust["crate_edges"] if e["is_violation"]],
        },
        "ahk": {"files": ahk["files"], "edges": ahk_scope_edges},
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
    print("AHK  文件: %(ahk_files)d | 边(总): %(ahk_edges_total)d | 边(范围内): %(ahk_edges_in_scope)d"
          " | 未解析: %(ahk_missing)d" % m)
    print("AHK  环: %(ahk_cycles)d | 孤点: %(ahk_orphans)d" % m)
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
    if ahk_orphans:
        print("-- AHK 孤点（无任何依赖关系）--")
        for o in ahk_orphans:
            print("   ", o)
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
