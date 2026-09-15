# 图谱同步清单

> **定位**：日常开发用的**可勾选操作清单**。每完成一次变更，照着对应小节走一遍。
> **配套文档**：方法说明见 `docs/graph-driven-workflow.md`；架构规则见 `AGENTS.md`。
> **打印建议**：建议作为 PR 模板的一部分使用。

---

## 0. 三步走总纲

任何代码变更，无论是新功能还是修改，都走这三步：

```
① 变更前：建基线  →  ② 变更中：查影响面  →  ③ 变更后：过四闸门
```

| 阶段 | 命令 / 动作 | 产出 |
|------|-----------|------|
| ① 变更前 | `python .review-analysis/build_graph.py` | 基线值（环 / 孤点 / 违规） |
| ② 变更中 | 查 §2 触发对照表 → 查 §3 影响面速查 | 连带改动清单 |
| ③ 变更后 | 走 §4 四闸门 + §5 自检命令 | 可提交状态 |

---

## 1. 变更前：建立基线

### 1.1 记录基线

```bash
python .review-analysis/build_graph.py
```

把输出抄到 PR 描述里，作为对比锚点：

```
基线（变更前）：
  AHK   环 0 | 孤点 6 | 未解析 include 0
  Rust  crate 环 0 | 生产依赖违规 0 | 文件 64
```

- [ ] 已记录基线值
- [ ] 基线中的**违规数**已知其来源（当前 0 条；原 3 条 `asd-test-harness` 出边已于 TD-009
      定性为**依赖矩阵漏填**而非违规，已补进 `ALLOWED_CRATE_DEPS`）

### 1.2 判定变更类型

- [ ] 新增文件 / 模块
- [ ] 修改现有逻辑
- [ ] 删除 / 归档文件
- [ ] 纯文档变更
- [ ] 配置 / CI 变更

---

## 2. 变更中：触发对照表

**在 §2 找到你的触发项，完成「必须同步」列出的全部动作。**

### 2.1 代码结构类

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 增删 AHK 文件 | `docs/module-adjacency.md`、`AGENTS.md` Key Files | `build_graph.py` 无新环/孤点 |
| 修改 `#Include` 关系 | `docs/module-adjacency.md` | 同上 |
| 新增顶层目录 | `docs/graph-driven-workflow.md` §1.1、`AGENTS.md` Subdirectories | 目录表与实际一致 |
| 删除文件 | `docs/module-adjacency.md`、`AGENTS.md`；确认无残留 `#Include` | 图谱无「未解析 include」 |

- [ ] 完成

### 2.2 分层与架构类

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 新增架构妥协 | `AGENTS.md` 对应妥协表（含影响文件/说明/约束边界） | 图谱逆向边与白名单条数一致 |
| 新增反向依赖 | 同上 + `docs/graph-driven-workflow.md` §2.4 白名单表 | 同上 |
| 改分层 depth / 豁免规则 | **`gen_graph_html.py`**（非 `build_graph.py`）+ 主规范 §2.6.2 | 反向边判定正确 |
| 向 `src-tauri/src/application/` 或 `src-tauri/src/domain/` 加代码 | **❌ 禁止**——这是空的历史占位目录 | 确认落点应为对应 crate |

> ⚠️ **分层常量的位置陷阱**：`LAYER_META` / `LAYER_EXEMPT` 在 **`gen_graph_html.py`**，不在 `build_graph.py`。

- [ ] 完成

### 2.3 契约类（跨进程 / 跨语言）

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 新增 `IpcCommand` variant | `ahk_executor/executor.ahk` 的 `Dispatch` 分支、`AGENTS.md`、`test-map.md` | grep variant 双向一致 |
| 改 `IpcCommand` / `IpcMessage` 字段 | `ahk_executor/ipc_client.ahk` 的 `MiniJson` 解析 | 字段名逐一核对 |
| 改 `IPC_PIPE_NAME` | `ahk_executor/ipc_client.ahk` 管道名常量 | **必须完全一致** |
| 新增 Tauri command | `invoke_handler` 注册、`src/api.js` | `command_contract_tests.rs` |
| 改 `Config` / `GroupConfig` / `ModeData` 字段 | AHK `config_store.ahk` / `config_validator.ahk` | `config_compat_tests.rs` |
| 改 `WatchdogStateEnum` | 前端状态展示、状态同步循环 | 状态机迁移表（主规范 §3.5） |

> ⚠️ **新增 variant 的关键判定**：`Dispatch` 的 `switch` 只处理需要业务响应的 action。`Ping` / `Shutdown` 走内部路径，**不经过** `Dispatch`。新增 variant 前先确认它属于哪一类。

- [ ] 完成

### 2.4 Crate 与依赖类

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 新增 crate | `Cargo.toml`（workspace members）、`build_graph.py` 的 `ALLOWED_CRATE_DEPS` 与 `RUST_CRATES`、主规范 §2.2/2.3、`docs/module-adjacency.md` §6 | 图谱无新增违规 |
| 新增 crate 间依赖 | `build_graph.py` 的 `ALLOWED_CRATE_DEPS` | 同上 |
| 纯逻辑 crate 引入外部依赖 | **❌ 禁止** `tauri` / `tokio` / `interprocess` / `windows` | `Cargo.toml` 人工核对 |

- [ ] 完成

### 2.5 测试类

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 增删测试函数 / 改测试数 | **`asd-tauri/docs/test-map.md`（唯一权威）** | 重算自洽校验行 |
| 新增测试文件 | `test-map.md` 对应明细表 | 明细之和 = 小计 |
| 新增 E2E suite | `test-map.md` E2E 段 | — |
| 新增 bench / fuzz target | `test-map.md` 对应段 | — |

> ⚠️ **数字权威铁律**：测试数字**只允许** `test-map.md` 持有。
> 若在其它文档发现测试数字，**立即改为指针**（「见 `test-map.md`」，并标注其为唯一权威）。

- [ ] 完成

### 2.6 CI / 构建类

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 增删 / 改 CI job | `docs/developer-guide.md`、主规范 §5.4 | YAML 与表格一致 |
| 改钩子行为 | `docs/commit-convention.md`、主规范 §5.1/5.2 | 实测提交一次 |
| 改构建脚本 / 打包配置 | `docs/developer-guide.md` | 实际构建通过 |

- [ ] 完成

### 2.7 文档结构类

| 触发变更 | 必须同步更新 | 校验方式 |
|---------|-------------|---------|
| 文档结构大改 | 重跑脚本链，归档到 `docs/review/<date>/graph/` | HTML 可打开、JSON 可解析 |
| 新增文档 | 在 `docs/graph-driven-workflow.md` §0.2 权威表中登记所属领域 | — |
| 改本文档的触发项 | 同步 `docs/graph-driven-workflow.md` §6.1 规则表 | **两张表必须一致** |

> ⚠️ 本文件 §2 与主规范 §6.1 是**同一张表的两种形态**（此处可勾选，彼处为规范正文）。**改一处必须同步另一处。**

- [ ] 完成

---

## 3. 影响面速查（改前先看）

高频改动点及其连带影响：

| 你改这个… | 连带影响（务必检查） |
|----------|-------------------|
| 🔴 `infrastructure/error_system.ahk` | **27 处入边**——任何公开方法签名变更都会波及全项目四层 |
| 🔴 `domain/skill_manager.ahk` | 应用层 2 个服务 + 表现层 2 个面板 |
| 🔴 `presentation/gui_manager.ahk` | 表现层聚合入口，引用同层 3 个面板 |
| 🔴 `infrastructure/backup_core.ahk` | 应用层全部 3 个服务 |
| 🔴 `application/config_service.ahk` | 10 条出边，跨三层的连接点 |
| ⚠️ `STALE_PROCESS_NAMES`（watchdog.rs） | **安全红线**——绝不可加入 `AutoHotkey64.exe`，配套测试必须同步 |
| ⚠️ `Execute*` 热路径方法 | 日志限速（≤1 次/秒）；不得引入阻塞/IO |
| ⚠️ `spawn_ipc_listener` | 热键事件回程路径不得阻塞按键执行 |
| ⚠️ 分层常量 | 在 `gen_graph_html.py`，**不是** `build_graph.py` |
| ⚠️ `Config` 结构体 | AHK 侧格式兼容 + `config_compat_tests.rs` |
| ⚠️ WebView2 Bridge | 禁止 sync 代理（死锁），必须 postMessage |

> 完整依赖数据见 `docs/module-adjacency.md`。

---

## 4. 变更后：四闸门

**四道闸门全绿才算完成。**

### 闸门 ①：图谱

```bash
python .review-analysis/build_graph.py
```

- [ ] AHK 环数 **未增加**（健康值 0）
- [ ] Rust crate 环数 **未增加**（健康值 0）
- [ ] 未解析 `#Include` 为 **0**
- [ ] 生产依赖违规数与「基线 + 本次新登记白名单」**相符**
- [ ] 新增孤点已判定（删除 / 归档 / 确认合理）

### 闸门 ②：质量

```bash
cd asd-tauri && cargo fmt --check && cargo clippy --all-targets -- -D warnings
```

- [ ] 格式化零差异
- [ ] clippy 零告警（`-D warnings` 为硬失败）

### 闸门 ③：测试

```bash
cd asd-tauri && cargo test
# AHK 侧
# 运行 tests/run_all_tests.ahk
```

- [ ] Rust 测试全部通过
- [ ] AHK 完整测试套件通过
- [ ] 执行器测试通过（`tests/test_ahk_executor/`）
- [ ] **测试数字已登记到 `asd-tauri/docs/test-map.md`**
- [ ] `test-map.md` 的自洽校验行已重算且等式成立

> ⚠️ **AHK 测试前置检查**（`AGENTS.md` 要求）：
> 语法检查（stderr 重定向 + 退出码）→ 接管指令验证 → 运行时验证。
> 语法检查必须用 `Start-Process -RedirectStandardError` 或 `2>&1` 重定向 stderr。

### 闸门 ④：文档

- [ ] 已按 §2 触发对照表完成**全部**「必须同步更新」项
- [ ] 本次涉及的**契约**已双向核对（IPC variant ↔ Dispatch、命令名 ↔ api.js、Config ↔ AHK）
- [ ] 新增/修改的文件已登记到 `AGENTS.md` Key Files（如属关键文件）
- [ ] 无新增测试数字散落在 `test-map.md` 之外

---

## 5. 自检命令速查

一次性跑完主要一致性检查：

```bash
# ① 图谱健康度
python .review-analysis/build_graph.py

# ② 各 crate 测试数（应与 test-map.md 一致）
for c in asd-domain asd-ipc-protocol asd-application asd-test-harness; do
  echo -n "$c = "
  grep -rhE '^\s*#\[(tokio::)?test\]' asd-tauri/crates/$c/ --include=*.rs | wc -l
done
echo -n "src-tauri = "
grep -rhE '^\s*#\[(tokio::)?test\]' asd-tauri/src-tauri/ --include=*.rs \
  --exclude-dir=fuzz --exclude-dir=benches | wc -l

# ③ 契约：IpcCommand variant 数 vs Dispatch 分支数
echo -n "IpcCommand variants = "
grep -cE '^\s{4}[A-Z][A-Za-z]+' asd-tauri/crates/asd-ipc-protocol/src/command.rs
echo -n "Dispatch action 分支 = "
# 注意：executor.ahk 内共 21 个 case，其中 10 个属模式字符串 switch（periodic/sequence/...）
# 只有 CommandDispatcher.Dispatch 内的 11 个是 IPC action。用行号范围限定，避免误计。
sed -n '58,85p' asd-tauri/src-tauri/ahk_executor/executor.ahk | grep -cE 'case "'

# ④ Tauri 命令数（应与 api.js 调用数一致）
echo -n "registered commands = "
grep -cE '^\s+commands::' asd-tauri/src-tauri/src/lib.rs

# ⑤ 纯逻辑 crate 不得含禁用依赖
grep -nE '^\s*(tauri|tokio|interprocess|windows)\s*=' \
  asd-tauri/crates/asd-domain/Cargo.toml \
  asd-tauri/crates/asd-ipc-protocol/Cargo.toml \
  asd-tauri/crates/asd-application/Cargo.toml \
  && echo "❌ 发现禁用依赖" || echo "✅ 无禁用依赖"

# ⑥ 文档内路径真实性（抽取 `path.ext` 校验存在性）
```

### 文档内路径校验脚本

```bash
# 抽取文档中所有 `xxx/yyy.ext` 形式路径并检查存在性
grep -ohE '`[a-zA-Z0-9_./-]+\.(rs|ahk|md|json|toml|js|html|yml)`' \
  docs/graph-driven-workflow.md docs/module-adjacency.md docs/graph-sync-checklist.md \
  | tr -d '`' | sort -u | while read -r p; do
    [ -e "asd-tauri/$p" ] || [ -e "$p" ] || echo "MISSING: $p"
  done
```

---

## 6. Mermaid 图校验

本规范引入了 Mermaid 图（项目首次）。修改任何图后**必须**校验语法。

### 6.1 手动检查清单

- [ ] 节点文本含 `/`、`(`、`→`、`:` 等特殊字符时**已用双引号包裹**
- [ ] 边标签使用 `-->|"文本"|` 形式
- [ ] `subgraph` 名与其内节点 ID **不冲突**
- [ ] 单图节点数 **≤ 20**（79 个 AHK 文件不入图，进邻接表）
- [ ] 未使用 `init` / `config` 指令

### 6.2 自动校验

若本地有 Node 环境，可用 Mermaid 官方解析器校验：

```bash
# 提取 mermaid 块
python - <<'PY'
import io, re, os
out = "mmd_check"
os.makedirs(out, exist_ok=True)
src = io.open("docs/graph-driven-workflow.md", encoding="utf-8").read()
for i, b in enumerate(re.findall(r"```mermaid\n(.*?)```", src, re.S), 1):
    io.open(f"{out}/g{i:02d}.mmd", "w", encoding="utf-8", newline="\n").write(b)
print("提取完成")
PY

# 用 mermaid.parse() 校验（需 mermaid 包）
# 见项目 .review-analysis/ 或本地临时脚本
```

- [ ] 全部图 `PASS`
- [ ] 失败数为 0

### 6.3 已知环境坑

| 现象 | 原因 | 处置 |
|------|------|------|
| `DOMPurify.addHook is not a function` | Node 下 mermaid 需要 DOM 环境 | 注入 `jsdom` 提供 `window`/`document` |
| `Cannot set property navigator` | Node 22 的 `navigator` 只读 | 用 `Object.defineProperty` 或保留内置实现 |
| 路径 `ENOENT: C:\tmp\...` | Node 把 `/tmp` 解析为 `C:\tmp` | 用 Windows 绝对路径传给 Node 脚本 |

---

## 7. 提交前最终检查

- [ ] 提交信息符合 `<type>(<scope>): 中文描述`（`commit-msg` 钩子会校验 type）
- [ ] 描述使用中文（项目约定）
- [ ] 代码与文档改动在**同一提交 / 同一 PR**
- [ ] 若为 BREAKING CHANGE，已用 `!` 标注
- [ ] 已记录「基线 → 变更后」的图谱对比数据

### 提交信息示例

```
docs(test): 修正 test-map 残留测试数字
feat(ahk-executor): 新增 StartSequence 命令分发
fix(watchdog): 修正心跳超时阈值不匹配
docs(ahk): 新增图谱式开发流程规范
refactor(application): 拆分 GroupService 校验逻辑
```

> **注意**：提交信息中**不写具体测试数字**（数字只在 `test-map.md` 维护，写入提交信息会立刻过期）。

---

## 8. 快速索引

| 我想… | 去这里 |
|-------|-------|
| 理解图谱方法论 | `docs/graph-driven-workflow.md` §0 |
| 查目录结构与职责 | `docs/graph-driven-workflow.md` §1 |
| 看依赖图与反向边白名单 | `docs/graph-driven-workflow.md` §2 |
| 追踪功能链路 | `docs/graph-driven-workflow.md` §3 |
| 开发新功能的流程 | `docs/graph-driven-workflow.md` §4 |
| 提交与审查规范 | `docs/graph-driven-workflow.md` §5 |
| 查某模块的入边/出边 | `docs/module-adjacency.md` |
| 查架构规则与妥协白名单 | `AGENTS.md` |
| 查测试数字 | `asd-tauri/docs/test-map.md` |
| 查环境搭建与故障排查 | `docs/developer-guide.md` |

---

**相关文档**：`docs/graph-driven-workflow.md`（主规范）· `docs/module-adjacency.md`（邻接表）· `AGENTS.md`（架构权威）· `asd-tauri/docs/test-map.md`（测试数字权威）
