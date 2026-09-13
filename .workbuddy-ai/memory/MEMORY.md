# 项目长期记忆 — ASD 技能管理器

> 跨会话持久化的事实与约定。仅记录有长期价值的内容；临时状态见 `YYYY-MM-DD.md` 日志。

## 文档权威边界（四方，各自领域内唯一）

| 文档 | 权威领域 | 不负责 |
|------|---------|-------|
| `AGENTS.md` | 架构决策、分层规则、已知妥协白名单、关键文件清单 | 测试数字、操作步骤 |
| `asd-tauri/docs/test-map.md` | **一切测试数字** | 架构规则、流程 |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 | 分层规则、测试数字 |
| `docs/graph-driven-workflow.md` | 图谱方法、开发流程、审查流程、同步机制 | 架构规则、测试数字 |

**冲突处置**：数字冲突查 test-map.md；架构冲突查 AGENTS.md；命令冲突查 developer-guide.md；
流程冲突查 graph-driven-workflow.md。**发现矛盾必须当场修正，不允许两边都留着。**

**铁律**：测试数字只允许 `test-map.md` 持有。其它文档引用时只写指针，不复制数字。

## 图谱式开发工作流

```bash
python .review-analysis/build_graph.py     # 建图 → .review-analysis/graph-raw.json
python .review-analysis/gen_graph_html.py  # 渲染 → docs/review/<date>/graph/{json,html}
```

**四类审查靶点**：环 / 逆向边 / 孤点 / 契约断点。

**分层 depth 语义**（数值越小越内层，依赖恒由大 → 小）：
`infrastructure 0` → `domain 1` → `application 2` → `presentation 3` → `entry 4`
→ `executor 5` → `tests 6` → `other 7`；`entry`/`tests`/`executor`/`other` 豁免分层约束。

**开发四闸门（DoD）**：① 图谱无新环 ② fmt + clippy 零告警 ③ 测试通过且已登记 test-map.md ④ 文档已同步。

## 图谱工具链的坑（已修复，勿回退）

1. `build_graph.py` 的 `#Include` 正则**必须保留 `re.M`**——缺了会因 `^` 锚点导致边数为 0。
2. **分层常量（`LAYER_META` / `LAYER_EXEMPT`）在 `gen_graph_html.py`，不在 `build_graph.py`。**
   改分层语义时容易找错文件。
3. Rust crate 环检测**只用生产边**（`prod_crate_edges`）；`dev-dependency` 不算违规。
4. `asd-test-harness` 反向依赖三个 crate 是**夹具的设计意图**，属已知可接受偏差；
   新增 crate 或跨 crate 依赖**必须同步 `ALLOWED_CRATE_DEPS`**。

## 契约统计的正确方法

| 契约 | 正确命令 | 注意 |
|------|---------|------|
| IPC action 分支数 | `sed -n '58,85p' ahk_executor/executor.ahk \| grep -cE 'case "'` | **必须限定行范围**——全文件有 21 个 `case`，其中 10 个是模式字符串 switch（`periodic`/`sequence`/`enhanced_*`/`hold`/`hybrid`/`joystick_*`，属 `MergeModeConfig`），只有 11 个是 IPC action |
| Tauri 命令数 | `grep -cE '^\s+commands::' src-tauri/src/lib.rs` | — |
| IpcCommand variant 数 | `grep -cE '^\s{4}[A-Z][A-Za-z]+' crates/asd-ipc-protocol/src/command.rs` | — |
| 各 crate 测试数 | `grep -rhE '^\s*#\[(tokio::)?test\]' <crate>/ --include=*.rs \| wc -l` | 用 `grep -h` 再 `wc -l`，不要用 `grep -c` 按文件计数再相加 |
| AHK 套件数 | `grep -rhcE '^class \S+ extends AutoHotUnitSuite' tests/suites/*.ahk tests/test_ahk_executor/*.ahk tests/test_joy_hotkey_manager_ahu.ahk` | `test_ahk_executor/` 5 文件 = **59 套件**；全量含 joy_hotkey_manager = **160 套件** |
| AHK 实跑用例数 | `tail -20 tests/test_results.log` | **616**（权威）；静态 `Test_` 计数 614，差 2 因 runner 另执行 `Setup`/`Teardown` |

**Rust 测试基线（2026-09-13 修复后，运行时口径）**：asd-domain **136** / asd-ipc-protocol 72 /
asd-application 163 / asd-test-harness 3 / asd-tauri 242 = **616**（`#[ignore]` 15）。
asd-domain 由 132 → 136 是 BUG-6 新增 4 个 validator warning 测试。
`cargo test --workspace` 实测 **601 passed / 0 failed / 15 ignored** + 1 doc-test。
`--all-targets` 下 criterion benches（`harness = false`）**不注册**为测试，故 asd-tauri = 241(lib) + 1(tests/)。

## 测试数字的「双口径」（两者都对，禁止互纠）

- ~~`watchdog_integration_tests.rs`：`#[test]` 属性 14 vs `fn` 17~~ —— **双口径已于 2026-09-13 统一为 17**（运行时 `--list` 口径，与 `TESTING.md` 的 `fn` 一致）。原 14 是严版正则漏计带参属性所致，**不是**「两个都对」。
- AHK 完整套件：实跑 **616**（含生命周期钩子）vs 静态 `Test_` **614**。
- **`test-map.md` 是唯一持有测试数字的文档**；其余文档只写指针。`TESTING.md` 已改为不复制数字。

## 易误判点（做「陈旧引用清零」时必须注意）

1. **`SkillManager` 有两义**：`AGENTS.md` 中的 `class SkillManager` 是 **AHK v2 类**（`domain/skill_manager.ahk`，仍存在）；
   `migration-guide.md` 的十余处是**迁移映射表的 AHK 侧列**（本就该保留）。
   只应清除「**Rust `asd-application` 侧**」的 `SkillManager` 引用。
2. **历史/归档文档严禁改写**：`docs/review/**`、`docs/superpowers/plans/**`、`.trae/specs/**`、
   `docs/code-review-report-*`、`docs/remediation-plan-*` 中出现已删文件名是**当时事实的记录**。
   清零检查只针对 9 份权威文档。
3. **`joystick_input_utils.ahk` 的提及是正确内容**：`AGENTS.md` 妥协表用它记录 A1 修复历史
   （「删除冗余的 …」），不是死链。
4. **`asd-application/src/` 实际 8 文件**：`backup_service`/`config_repository`/`error`/`group_service`/
   `lib`/`recording_service`/`state`/`time_format`。**无 `scheduler.rs`**。
5. **`AppState` 真实字段**见 `crates/asd-application/src/state.rs:80-92`（11 个，`config_state: RwLock<ConfigState>` 起），
   **不是**文档旧写的 `scheduler`/`config_repo`。

## E2E 的坑（2026-09-13 修复，勿回退）

1. **跑 E2E 前必须有 Vite dev server**。debug 构建运行时**一定走 `devUrl`**
   （`http://127.0.0.1:5173`），**即使二进制内嵌了前端资源也走 devUrl**。
   未启动 Vite → WebView 停在 `chrome-error://chromewebdata/` → origin 为 `null`
   → Tauri IPC 拒绝 → 报 `"Origin header is not a valid URL"`。
   **该文案是「页面没加载」的下游症状，不是 Origin 配置问题**；
   `useHttpsScheme: true` **不对症，别改**。
   `wdio.conf.js` 的 `onPrepare` 已自动托管 Vite（含 `onComplete` 回收）。
2. **`withGlobalTauri` 的 `__TAURI__` 在错误页上也存在**（注入脚本对任何文档生效），
   所以「`__TAURI__` 存在」**不能**证明页面加载成功。判据要看 `window.location.protocol`
   是否为 `chrome-error:`。`startApp()` 已内置该健全性检查。
3. **窗口标题非空 ≠ 页面加载成功**（标题取自 `tauri.conf.json`，错误页上照样有值）。
   —— 这正是原来漏掉本问题的原因。
4. msedgedriver 版本须与 WebView2 运行时匹配；driver 是 gitignored 的 `*.exe`。
5. 时序类 E2E（按键间隔）观察窗口须 **≥ 2 个周期**，否则负载高时偶发失败；
   取「最佳匹配周期」而非首个匹配，避免取到窗口边界残帧。

## 安全红线

- `watchdog.rs` 的 `STALE_PROCESS_NAMES` **只允许 `asd_executor.exe`**，
  **绝不**加入 `AutoHotkey64.exe`（`taskkill /F /IM` 会杀掉用户所有 AHK 进程）。
- `src-tauri/src/application/` 与 `src-tauri/src/domain/` 是**空的历史占位**，禁止向其添加代码。
- WebView2 AHK-JS 通信**禁止 sync 代理**（`hostObjects.sync.ahk.Method()` 会死锁），必须 postMessage。
- 全局锁顺序固定为 **`ipc_manager` → `watchdog`**，反转即死锁。
- 纯逻辑 crate（`asd-domain` / `asd-ipc-protocol` / `asd-application`）
  **禁止**引入 `tauri` / `tokio` / `interprocess` / `windows`。

## 工程约定

- **换行符**：`.gitattributes` 强制文本文件 LF（`.ps1`/`.bat`/`.cmd` 除外）。
  ⚠️ Edit 工具在 Windows 上可能引入 CRLF，改完 `.md` 需用 Python 校验/转换。
- **提交规范**：Conventional Commits，10 种 type，**描述用中文**。
  `commit-msg` 钩子**同时校验 type 与 scope 白名单**（2026-09-13 实测：
  `fix(e2e):` 被拒，报「提交信息不符合 Conventional Commits 规范」并列白名单）。
  scope 白名单：`asd-domain` / `asd-ipc-protocol` / `asd-application` / `asd-tauri` /
  `asd-test-harness` / `ahk` / `test` / `ci` / `docs` / `config`。
  `asd-tauri/e2e/` 下的改动用 `test`（`e2e` 不是合法 scope）。
  长提交信息用 `git commit -F <file>`（写进 `.git/COMMIT_MSG_TMP` 后删除），
  避免 shell 转义问题。
- **提交信息中不写具体测试数字**（会立刻过期）。
- **文档与代码改动必须在同一 PR**，禁止「代码先合、文档后补」。
- AHK 测试前置检查：语法检查（stderr 重定向 + 退出码）→ 接管指令验证 → 运行时验证。
- AHK v2 箭头函数 `=>` **只支持表达式体**，禁止 `(args) => { ... }` 块体。

## 图谱当前基线（2026-09-13 复测，与 09-12 一致）

```
AHK   72 文件 / 260 边（范围内 254）/ 0 环 / 9 孤点 / 未解析 include 0
Rust  64 文件 / 163 use 边 / 11 crate 边 / 0 生产环 / 3 生产依赖违规（均为 asd-test-harness）
JS    5 文件 / 9 import 边
```

> 改动后需与此基线对比，环数/违规数增加必须处理或登记白名单。
