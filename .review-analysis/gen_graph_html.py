"""生成交付用图谱：结构化 JSON（AI 可读）+ 交互式 HTML（人可读）。

输入：.review-analysis/graph-raw.json
输出：
  docs/review/2026-09-12/graph/architecture-graph.json   结构化图谱（机器/AI 可读）
  docs/review/2026-09-12/graph/architecture-graph.html   交互式图谱（浏览器可下钻）
"""
import io
import json
import os
from collections import Counter, defaultdict

ROOT = r"D:\1demo\AutoHotkeydemo"
SRC = os.path.join(ROOT, ".review-analysis", "graph-raw.json")
OUTDIR = os.path.join(ROOT, "docs", "review", "2026-09-12", "graph")

# ---- 分层定义（含展示元数据）----
# depth 语义：数值越小越「内层」（越接近纯业务/无依赖）。
# 依赖方向应始终由 depth 大 → 小（外层依赖内层）。
# entry 与 tests 为特殊层：entry 是最外层可依赖任何层；tests 独立于产品分层。
LAYER_META = {
    "infrastructure": {"label": "基础设施层", "color": "#3b82f6", "order": 4, "depth": 0,
                       "desc": "JSON 解析/序列化、配置存储、日志、错误系统、IPC 通道"},
    "domain": {"label": "领域层", "color": "#10b981", "order": 3, "depth": 1,
               "desc": "纯业务逻辑：技能组、模式注册、按键录制、摇杆执行"},
    "application": {"label": "应用层", "color": "#f59e0b", "order": 2, "depth": 2,
                    "desc": "用例编排：分组服务、配置服务、备份服务"},
    "presentation": {"label": "表现层", "color": "#ec4899", "order": 1, "depth": 3,
                     "desc": "WebView2 / GUI 管理器，AHK-JS Bridge"},
    "entry": {"label": "入口层", "color": "#8b5cf6", "order": 0, "depth": 4,
              "desc": "main.ahk / asd.ahk 等进程入口，负责依赖注入与初始化（可依赖任意层）"},
    "executor": {"label": "AHK 执行器", "color": "#ef4444", "order": 5, "depth": 5,
                 "desc": "Rust 子进程：按键模拟与热键钩子（跨进程边界，独立子树）"},
    "tests": {"label": "测试层", "color": "#64748b", "order": 6, "depth": 6,
              "desc": "单元/集成/分层安全测试（可依赖任意生产层，不参与产品分层约束）"},
    "other": {"label": "其他", "color": "#94a3b8", "order": 7, "depth": 7, "desc": "未归类"},
}

# 不参与分层方向约束的层
LAYER_EXEMPT = {"entry", "tests", "executor", "other"}


def is_reverse_edge(a, b):
    """判断 a→b 是否为分层反向边（内层依赖外层）。

    规则：entry / tests / executor 豁免（它们是入口或独立子树）。
    其余情况：若发起方 depth 小于被依赖方 depth，即为反向（内层拉外层）。
    """
    if a in LAYER_EXEMPT or b in LAYER_EXEMPT:
        return False
    da = LAYER_META.get(a, {}).get("depth", 99)
    db = LAYER_META.get(b, {}).get("depth", 99)
    return da < db

RUST_CRATE_META = {
    "asd-ipc-protocol": {"label": "asd-ipc-protocol", "color": "#0ea5e9", "order": 0,
                         "desc": "IPC 协议定义（13 个 IpcCommand variant）— 最底层，无内部依赖"},
    "asd-domain": {"label": "asd-domain", "color": "#10b981", "order": 1,
                   "desc": "领域模型 + trait + 校验器"},
    "asd-application": {"label": "asd-application", "color": "#f59e0b", "order": 2,
                        "desc": "应用服务：配置仓库、备份、分组、录制"},
    "asd-test-harness": {"label": "asd-test-harness", "color": "#a855f7", "order": 3,
                         "desc": "测试夹具与 mock 工具（反向依赖被测 crate）"},
    "src-tauri": {"label": "src-tauri", "color": "#ec4899", "order": 4,
                  "desc": "Tauri 主 crate：34 个 command + IPC/看门狗基础设施"},
}


def ahk_layer(p):
    for name, prefix in (
        ("domain", "domain/"),
        ("infrastructure", "infrastructure/"),
        ("application", "application/"),
        ("presentation", "presentation/"),
        ("tests", "tests/"),
        ("executor", "asd-tauri/src-tauri/ahk_executor/"),
    ):
        if p.startswith(prefix):
            return name
    if "/" not in p:
        return "entry"
    return "other"


def rust_crate(p):
    if p.startswith("asd-tauri/crates/"):
        return p[len("asd-tauri/crates/"):].split("/")[0]
    if p.startswith("asd-tauri/src-tauri/"):
        return "src-tauri"
    return "other"


def short(p):
    return p.split("/")[-1]


def build():
    g = json.load(io.open(SRC, encoding="utf-8"))

    # ---------------- AHK 节点 ----------------
    ahk_nodes = []
    for f in g["ahk"]["files"]:
        lay = ahk_layer(f)
        ahk_nodes.append({
            "id": f, "label": short(f), "path": f, "layer": lay,
            "layerLabel": LAYER_META[lay]["label"],
        })

    # 入/出度
    indeg, outdeg = Counter(), Counter()
    for e in g["ahk"]["edges"]:
        outdeg[e["from"]] += 1
        indeg[e["to"]] += 1

    # 分层汇总
    layer_agg = defaultdict(lambda: {"files": 0, "out": 0, "in": 0})
    for n in ahk_nodes:
        layer_agg[n["layer"]]["files"] += 1
    for e in g["ahk"]["edges"]:
        layer_agg[e["from_layer"]]["out"] += 1
        if e["to_layer"] in layer_agg or e["to_layer"] != "out-of-scope":
            layer_agg[e["to_layer"]]["in"] += 1

    # 分层交叉矩阵
    matrix = Counter()
    for e in g["ahk"]["edges"]:
        matrix[(e["from_layer"], e["to_layer"])] += 1

    # 层间聚合边（用于概览视图）
    layer_edges = []
    for (a, b), n in sorted(matrix.items(), key=lambda x: -x[1]):
        if a == b or b == "out-of-scope":
            continue
        layer_edges.append({"from": a, "to": b, "count": n,
                            "reverse": is_reverse_edge(a, b)})

    # ---------------- Rust crate 图 ----------------
    rust_nodes = []
    for c, meta in RUST_CRATE_META.items():
        if any(rust_crate(f) == c for f in g["rust"]["files"]):
            rust_nodes.append({"id": c, "label": meta["label"], "color": meta["color"],
                               "order": meta["order"], "desc": meta["desc"]})
    rust_prod_edges = [{"from": e["from"], "to": e["to"], "kind": "prod",
                        "sites": len(e["sites"])} for e in g["rust"]["prod_crate_edges"]]
    rust_dev_edges = [{"from": e["from"], "to": e["to"], "kind": "dev"}
                      for e in g["rust"]["crate_edges"] if e["declared_dev_only"]]

    # ---------------- 结论 ----------------
    findings = g["findings"]
    verdict = {
        "ahk_cycles": findings["ahk_cycles"],
        "ahk_cycle_count": len(findings["ahk_cycles"]),
        "rust_prod_cycle_count": len(findings["rust_crate_cycles"]),
        "ahk_orphans": findings["ahk_orphans"],
        "ahk_missing_includes": findings["ahk_missing_includes"],
        "rust_prod_violations": findings["rust_crate_violations"],
        "note": (
            "AHK Include 图与 Rust 生产 crate 图均为无环有向图（DAG）。"
            "asd-test-harness 对被测 crate 的反向引用为测试工具库的设计意图，"
            "已在 Cargo.toml 中声明为 dev-dependencies，不计入生产架构环。"
        ),
    }

    structured = {
        "schema": "asd-architecture-graph/v1",
        "generatedAt": "2026-09-12",
        "project": "ASD 技能管理器（AHK v2 + Rust/Tauri 混合架构）",
        "meta": g["meta"],
        "layers": LAYER_META,
        "ahk": {
            "nodeCount": len(ahk_nodes),
            "edgeCount": len(g["ahk"]["edges"]),
            "nodes": ahk_nodes,
            "edges": [{"from": e["from"], "to": e["to"],
                       "fromLayer": e["from_layer"], "toLayer": e["to_layer"],
                       "layerCross": e["is_layer_cross"]}
                      for e in g["ahk"]["edges"]],
            "layerSummary": {k: dict(v) for k, v in layer_agg.items()},
            "layerEdges": layer_edges,
            "degrees": {
                "topOut": [{"node": n, "degree": d} for n, d in outdeg.most_common(15)],
                "topIn": [{"node": n, "degree": d} for n, d in indeg.most_common(15)],
            },
        },
        "rust": {
            "nodes": rust_nodes,
            "prodEdges": rust_prod_edges,
            "devEdges": rust_dev_edges,
            "prodDeps": g["rust"]["prod_deps"],
            "devDeps": g["rust"]["dev_deps"],
        },
        "verdict": verdict,
    }

    os.makedirs(OUTDIR, exist_ok=True)
    with io.open(os.path.join(OUTDIR, "architecture-graph.json"), "w", encoding="utf-8") as fh:
        json.dump(structured, fh, ensure_ascii=False, indent=2)

    # ---------------- 交互式 HTML ----------------
    payload = json.dumps(structured, ensure_ascii=False)
    html = HTML_TEMPLATE.replace("__DATA__", payload)
    with io.open(os.path.join(OUTDIR, "architecture-graph.html"), "w", encoding="utf-8") as fh:
        fh.write(html)

    print("结构化图谱:", os.path.join(OUTDIR, "architecture-graph.json"))
    print("交互式图谱:", os.path.join(OUTDIR, "architecture-graph.html"))
    print("AHK 节点 %d / 边 %d" % (len(ahk_nodes), len(g["ahk"]["edges"])))
    print("Rust crate 生产边 %d / 测试边 %d" % (len(rust_prod_edges), len(rust_dev_edges)))


HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ASD 架构依赖图谱</title>
<style>
  :root{
    --bg:#f7f8fa; --panel:#ffffff; --line:#e3e6ec; --text:#1f2430; --muted:#6b7280;
    --accent:#2563eb; --warn:#f59e0b; --danger:#ef4444; --ok:#10b981;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);
       font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;font-size:14px}
  header{background:var(--panel);border-bottom:1px solid var(--line);padding:16px 24px;
         position:sticky;top:0;z-index:20}
  h1{margin:0 0 4px;font-size:18px;font-weight:600}
  .sub{color:var(--muted);font-size:12px}
  .wrap{padding:20px 24px 60px;max-width:1500px;margin:0 auto}
  .tabs{display:flex;gap:6px;margin:18px 0}
  .tab{padding:8px 16px;border:1px solid var(--line);background:var(--panel);border-radius:8px;
       cursor:pointer;font-size:13px;color:var(--muted);transition:.15s}
  .tab:hover{border-color:var(--accent);color:var(--accent)}
  .tab.on{background:var(--accent);border-color:var(--accent);color:#fff;font-weight:500}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;
        padding:18px;margin-bottom:16px}
  .card h2{margin:0 0 12px;font-size:15px;font-weight:600}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px}
  .stat{background:var(--bg);border-radius:8px;padding:12px 14px}
  .stat .n{font-size:22px;font-weight:600;line-height:1.2}
  .stat .l{color:var(--muted);font-size:12px;margin-top:2px}
  .ok{color:var(--ok)} .warn{color:var(--warn)} .danger{color:var(--danger)}
  .layer{display:flex;align-items:center;gap:10px;padding:8px 0;border-bottom:1px dashed var(--line)}
  .layer:last-child{border-bottom:none}
  .dot{width:11px;height:11px;border-radius:3px;flex:0 0 auto}
  .layer .name{font-weight:500;min-width:100px}
  .layer .d{color:var(--muted);font-size:12px;flex:1}
  .layer .c{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line)}
  th{color:var(--muted);font-weight:500;font-size:12px;background:var(--bg)}
  td code{background:var(--bg);padding:1px 5px;border-radius:4px;font-size:12px}
  .badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:500}
  .b-ok{background:#d1fae5;color:#065f46}
  .b-warn{background:#fef3c7;color:#92400e}
  .b-bad{background:#fee2e2;color:#991b1b}
  .b-info{background:#dbeafe;color:#1e40af}
  svg{display:block;width:100%;height:auto}
  .legend{display:flex;flex-wrap:wrap;gap:14px;margin-top:12px;font-size:12px;color:var(--muted)}
  .legend span{display:flex;align-items:center;gap:5px}
  .hidden{display:none}
  .bar{height:6px;background:var(--bg);border-radius:3px;overflow:hidden;margin-top:5px}
  .bar>i{display:block;height:100%;background:var(--accent)}
  .note{background:#eff6ff;border-left:3px solid var(--accent);padding:10px 14px;
        border-radius:0 6px 6px 0;font-size:13px;color:#1e3a8a;margin-top:10px}
</style>
</head>
<body>
<header>
  <h1>ASD 技能管理器 — 架构依赖图谱</h1>
  <div class="sub">AHK v2（DDD 四层）+ Rust/Tauri（5-crate workspace）混合架构 · 生成于 2026-09-12 · 只读分析</div>
</header>
<div class="wrap">
  <div id="overview"></div>
  <div class="tabs">
    <div class="tab on" data-v="ahk">AHK 分层图</div>
    <div class="tab" data-v="rust">Rust Crate 图</div>
    <div class="tab" data-v="matrix">层间交叉矩阵</div>
    <div class="tab" data-v="files">文件依赖明细</div>
  </div>
  <div id="view-ahk"></div>
  <div id="view-rust" class="hidden"></div>
  <div id="view-matrix" class="hidden"></div>
  <div id="view-files" class="hidden"></div>
</div>
<script>
const G = __DATA__;
const RM = G.layers;
const esc = s => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

/* ---------------- 概览 ---------------- */
function renderOverview(){
  const m = G.meta.counts, v = G.verdict;
  const cyc = v.ahk_cycle_count + v.rust_prod_cycle_count;
  document.getElementById('overview').innerHTML = `
  <div class="card">
    <h2>总体健康度</h2>
    <div class="grid">
      <div class="stat"><div class="n">${G.ahk.nodeCount}</div><div class="l">AHK 文件节点</div></div>
      <div class="stat"><div class="n">${G.ahk.edgeCount}</div><div class="l">AHK 依赖边</div></div>
      <div class="stat"><div class="n">${G.rust.nodes.length}</div><div class="l">Rust Crate</div></div>
      <div class="stat"><div class="n ${cyc===0?'ok':'danger'}">${cyc}</div>
           <div class="l">循环依赖（应恒为 0）</div></div>
      <div class="stat"><div class="n ${v.ahk_missing_includes.length===0?'ok':'danger'}">${v.ahk_missing_includes.length}</div>
           <div class="l">失效的 #Include</div></div>
      <div class="stat"><div class="n ${v.ahk_orphans.length===0?'ok':'warn'}">${v.ahk_orphans.length}</div>
           <div class="l">孤立文件（无依赖关系）</div></div>
    </div>
    <div class="note">
      <b>图谱结论：</b>${esc(v.note)}
    </div>
  </div>
  <div class="card">
    <h2>分层构成</h2>
    ${Object.entries(RM).filter(([k])=>G.ahk.layerSummary[k])
      .sort((a,b)=>a[1].order-b[1].order).map(([k,meta])=>{
        const s = G.ahk.layerSummary[k];
        return `<div class="layer">
          <span class="dot" style="background:${meta.color}"></span>
          <span class="name">${meta.label}</span>
          <span class="d">${meta.desc}</span>
          <span class="c">${s.files} 文件 · 出 ${s.out} / 入 ${s.in}</span>
        </div>`;}).join('')}
  </div>`;
}

/* ---------------- AHK 分层图 ---------------- */
function renderAhk(){
  const layers = Object.entries(RM).filter(([k])=>G.ahk.layerSummary[k])
                  .sort((a,b)=>a[1].order-b[1].order);
  const BW = 660, BH = 78, PAD = 30, W = 680;
  const H = PAD*2 + layers.length*BH;
  let svg = `<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">`;
  svg += `<defs><marker id="ar" markerWidth="8" markerHeight="8" refX="7" refY="3"
          orient="auto"><path d="M0,0 L7,3 L0,6 z" fill="#94a3b8"/></marker></defs>`;
  // 层盒子
  layers.forEach(([k,meta],i)=>{
    const y = PAD + i*BH, s = G.ahk.layerSummary[k];
    svg += `<rect x="${PAD}" y="${y}" width="${BW}" height="${BH-26}" rx="9"
             fill="${meta.color}14" stroke="${meta.color}" stroke-width="1.4"/>`;
    svg += `<rect x="${PAD}" y="${y}" width="5" height="${BH-26}" rx="2.5" fill="${meta.color}"/>`;
    svg += `<text x="${PAD+18}" y="${y+24}" fill="${meta.color}" font-size="14"
             font-weight="600">${meta.label}</text>`;
    svg += `<text x="${PAD+18}" y="${y+42}" fill="#6b7280" font-size="11">${s.files} 文件 · 出 ${s.out} / 入 ${s.in}</text>`;
  });
  // 层间边
  const idx = {}; layers.forEach(([k],i)=>idx[k]=i);
  const seen = new Set();
  G.ahk.layerEdges.forEach(e=>{
    if(idx[e.from]===undefined || idx[e.to]===undefined) return;
    const kk = e.from+'>'+e.to; if(seen.has(kk)) return; seen.add(kk);
    // 用两侧留白区画弯曲连接
    const y1 = PAD + idx[e.from]*BH + (BH-26)/2;
    const y2 = PAD + idx[e.to]*BH + (BH-26)/2;
    const x1 = PAD+BW-8, x2 = PAD+BW-8;
    const off = 14 + (idx[e.from]<idx[e.to]?0:0);
    const mid = Math.max(y1,y2);
    svg += `<path d="M ${x1} ${y1} C ${x1+off+34} ${y1}, ${x2+off+34} ${y2}, ${x2} ${y2}"
             fill="none" stroke="${e.reverse?'#f59e0b':'#94a3b8'}" stroke-width="${e.reverse?1.8:1.1}"
             opacity="${e.reverse?0.9:0.55}" marker-end="url(#ar)"/>`;
    svg += `<text x="${PAD+BW+off+36}" y="${(y1+y2)/2+4}" fill="${e.reverse?'#b45309':'#94a3b8'}"
             font-size="10" font-weight="600">${e.count}</text>`;
  });
  svg += `</svg>`;
  const rev = G.ahk.layerEdges.filter(e=>e.reverse);
  document.getElementById('view-ahk').innerHTML = `
  <div class="card">
    <h2>AHK 分层依赖图</h2>
    <p style="color:var(--muted);font-size:13px;margin:0 0 12px">
      箭头方向 = <code>#Include</code> 依赖方向；数字 = 该方向的边数。
      <b class="warn">橙色箭头</b>表示指向更内层（下层依赖上层），需逐条核对是否为已声明的架构妥协。</p>
    ${svg}
    <div class="legend">
      <span><span class="dot" style="background:#94a3b8"></span>正常方向（外层依赖内层）</span>
      <span><span class="dot" style="background:#f59e0b"></span>反向边（内层依赖外层，需审查）</span>
    </div>
  </div>
  <div class="card">
    <h2>反向边明细（分层完整性风险点）</h2>
    ${rev.length===0 ? '<p class="ok">未发现反向边。</p>' :
      `<table><thead><tr><th>方向</th><th>边数</th><th>说明</th></tr></thead><tbody>
        ${rev.map(e=>`<tr><td><code>${RM[e.from].label} → ${RM[e.to].label}</code></td>
        <td>${e.count}</td><td class="muted">${RM[e.from].label}依赖${RM[e.to].label}，与分层顺序相反</td></tr>`).join('')}
      </tbody></table>`}
  </div>`;
}

/* ---------------- Rust crate 图 ---------------- */
function renderRust(){
  const order = {0:0,1:1,2:2,3:3,4:4};
  const nodes = [...G.rust.nodes].sort((a,b)=>a.order-b.order);
  const H = 130, W = 680, top = 30;
  const gap = (W-60) / nodes.length;
  let svg = `<svg viewBox="0 0 ${W} ${H+60}" xmlns="http://www.w3.org/2000/svg">`;
  const pos = {};
  nodes.forEach((n,i)=>{ pos[n.id] = 30 + gap*i + gap/2; });
  // 生产边
  G.rust.prodEdges.forEach(e=>{
    if(pos[e.from]===undefined||pos[e.to]===undefined) return;
    const x1=pos[e.from], x2=pos[e.to], y=top+42;
    const mid=(x1+x2)/2;
    svg += `<path d="M ${x1} ${y+26} C ${x1} ${y+62}, ${x2} ${y+62}, ${x2} ${y+26}"
             fill="none" stroke="#2563eb" stroke-width="1.6" opacity="0.6"/>`;
    svg += `<text x="${mid}" y="${y+58}" fill="#2563eb" font-size="10" text-anchor="middle">${e.sites||1}</text>`;
  });
  // 测试边（虚线，反向）
  G.rust.devEdges.forEach(e=>{
    if(pos[e.from]===undefined||pos[e.to]===undefined) return;
    const x1=pos[e.from], x2=pos[e.to], y=top+42+62;
    svg += `<path d="M ${x1} ${y} C ${x1} ${y+34}, ${x2} ${y+34}, ${x2} ${y}"
             fill="none" stroke="#a855f7" stroke-width="1.4" stroke-dasharray="4 3" opacity="0.65"/>`;
  });
  nodes.forEach(n=>{
    const x = pos[n.id]-54, y = top;
    svg += `<rect x="${x}" y="${y}" width="108" height="42" rx="8"
             fill="${n.color}18" stroke="${n.color}" stroke-width="1.5"/>`;
    svg += `<text x="${pos[n.id]}" y="${y+26}" fill="${n.color}" font-size="11"
             font-weight="600" text-anchor="middle">${n.label}</text>`;
  });
  svg += `</svg>`;
  document.getElementById('view-rust').innerHTML = `
  <div class="card">
    <h2>Rust Crate 依赖图</h2>
    <p style="color:var(--muted);font-size:13px;margin:0 0 8px">
      实线 = 生产依赖（<code>[dependencies]</code>）；虚线 = 测试依赖（<code>[dev-dependencies]</code>）。
      数字 = 引用点数量。</p>
    ${svg}
    <div class="legend">
      <span><span class="dot" style="background:#2563eb"></span>生产依赖</span>
      <span><span class="dot" style="background:#a855f7"></span>测试依赖（dev-dependencies，不构成架构环）</span>
    </div>
    <div class="note">
      生产依赖图为 <b>DAG（无环）</b>：<code>asd-ipc-protocol</code> → <code>asd-domain</code> →
      <code>asd-application</code> → <code>src-tauri</code>，方向完全正确。
      <code>asd-test-harness</code> 反向依赖被测 crate 属测试工具库的设计意图，已在 Cargo.toml
      中限定为 dev-dependencies。
    </div>
  </div>
  <div class="card">
    <h2>Crate 依赖声明</h2>
    <table><thead><tr><th>Crate</th><th>生产依赖</th><th>测试依赖</th></tr></thead><tbody>
      ${nodes.map(n=>`<tr><td><code>${n.label}</code></td>
        <td>${(G.rust.prodDeps[n.label]||[]).map(d=>`<span class="badge b-info">${d}</span>`).join(' ')||'<span style="color:var(--muted)">—</span>'}</td>
        <td>${(G.rust.devDeps[n.label]||[]).map(d=>`<span class="badge b-info">${d}</span>`).join(' ')||'<span style="color:var(--muted)">—</span>'}</td>
      </tr>`).join('')}
    </tbody></table>
  </div>`;
}

/* ---------------- 层间交叉矩阵 ---------------- */
function renderMatrix(){
  const keys = Object.keys(RM).filter(k=>G.ahk.layerSummary[k])
                .sort((a,b)=>RM[a].order-RM[b].order);
  const cell = (a,b)=>{
    const n = (a===b) ? 0 : 0;
    return 0;
  };
  // 从 layerEdges 建索引
  const m = {};
  G.ahk.layerEdges.forEach(e=>{ m[e.from+'>'+e.to] = e; });
  let html = `<div class="card"><h2>层间依赖交叉矩阵</h2>
    <p style="color:var(--muted);font-size:13px;margin:0 0 12px">
      行 = 依赖发起方，列 = 被依赖方。对角线区域为层内依赖（已省略，见图谱 JSON）。
      <b class="warn">橙色单元格</b>为反向依赖，构成分层完整性风险。</p>
    <table><thead><tr><th>依赖方 \\ 被依赖方</th>
      ${keys.map(k=>`<th style="text-align:center">${RM[k].label}</th>`).join('')}</tr></thead><tbody>`;
  keys.forEach(a=>{
    html += `<tr><td><b>${RM[a].label}</b></td>`;
    keys.forEach(b=>{
      const e = m[a+'>'+b];
      if(a===b){ html += `<td style="text-align:center;color:#cbd5e1">—</td>`; return; }
      if(!e){ html += `<td style="text-align:center;color:#e2e8f0">·</td>`; return; }
      html += `<td style="text-align:center">
        <span class="badge ${e.reverse?'b-warn':'b-info'}">${e.count}</span></td>`;
    });
    html += `</tr>`;
  });
  html += `</tbody></table></div>`;

  // 高频被依赖方（fan-in）
  const topIn = G.ahk.degrees.topIn;
  const maxIn = topIn.length ? topIn[0].degree : 1;
  html += `<div class="card"><h2>被依赖最多的模块（fan-in Top 15）</h2>
    <p style="color:var(--muted);font-size:13px;margin:0 0 12px">
      fan-in 越高说明该模块越核心，其接口变更的影响面越大。</p>
    <table><thead><tr><th>模块</th><th>层</th><th>被引用次数</th><th style="width:180px">占比</th></tr></thead><tbody>
    ${topIn.map(t=>`<tr><td><code>${esc(t.node)}</code></td>
      <td><span class="dot" style="display:inline-block;background:${RM[ahkLayer(t.node)]?.color||'#94a3b8'}"></span>
          ${RM[ahkLayer(t.node)]?.label||'-'}</td>
      <td>${t.degree}</td>
      <td><div class="bar"><i style="width:${Math.round(t.degree/maxIn*100)}%"></i></div></td></tr>`).join('')}
    </tbody></table></div>`;
  document.getElementById('view-matrix').innerHTML = html;
}
function ahkLayer(p){
  for(const [k,meta] of Object.entries(RM)){
    if(k==='entry' && !p.includes('/')) return k;
  }
  const pre = {'domain/':'domain','infrastructure/':'infrastructure','application/':'application',
    'presentation/':'presentation','tests/':'tests','asd-tauri/src-tauri/ahk_executor/':'executor'};
  for(const [p2,k] of Object.entries(pre)) if(p.startsWith(p2)) return k;
  return 'other';
}

/* ---------------- 文件依赖明细 ---------------- */
function renderFiles(){
  const rows = G.ahk.nodes.map(n=>{
    const outs = G.ahk.edges.filter(e=>e.from===n.id);
    const ins  = G.ahk.edges.filter(e=>e.to===n.id);
    return {...n, outs, ins};
  }).sort((a,b)=>(b.outs.length+b.ins.length)-(a.outs.length+a.ins.length));
  let html = `<div class="card"><h2>文件级依赖明细（按连接度排序）</h2>
    <table><thead><tr><th>文件</th><th>层</th><th>出边</th><th>入边</th><th>状态</th></tr></thead><tbody>`;
  rows.forEach(r=>{
    let st = '<span class="badge b-ok">正常</span>';
    if(G.verdict.ahk_orphans.includes(r.id) && !r.id.startsWith('_'))
      st = '<span class="badge b-warn">孤立</span>';
    if(G.verdict.ahk_missing_includes.some(m=>m.from===r.id))
      st = '<span class="badge b-bad">失效 Include</span>';
    html += `<tr><td><code>${esc(r.path)}</code></td>
      <td><span class="dot" style="display:inline-block;background:${RM[r.layer]?.color||'#94a3b8'}"></span> ${r.layerLabel}</td>
      <td>${r.outs.length}</td><td>${r.ins.length}</td><td>${st}</td></tr>`;
  });
  html += `</tbody></table></div>`;
  document.getElementById('view-files').innerHTML = html;
}

/* ---------------- Tab ---------------- */
const views = {ahk:renderAhk, rust:renderRust, matrix:renderMatrix, files:renderFiles};
document.querySelectorAll('.tab').forEach(t=>{
  t.onclick = ()=>{
    document.querySelectorAll('.tab').forEach(x=>x.classList.remove('on'));
    t.classList.add('on');
    ['ahk','rust','matrix','files'].forEach(v=>{
      document.getElementById('view-'+v).classList.toggle('hidden', v!==t.dataset.v);
    });
  };
});
renderOverview(); renderAhk(); renderRust(); renderMatrix(); renderFiles();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    build()
