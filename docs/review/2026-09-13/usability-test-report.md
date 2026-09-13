# 全模块实际可用性测试报告

> **测试日期**：2026-09-13
> **测试范围**：全项目功能模块（AHK v2 域 + Rust/Tauri 5-crate workspace + 前端 + E2E）
> **测试性质**：**实际运行**（非静态分析），覆盖正常 / 边界 / 异常三类场景
> **文档权威边界**：本报告只记录**本次实测结论与问题清单**；测试数字的权威来源是
> [`asd-tauri/docs/test-map.md`](../../asd-tauri/docs/test-map.md)。本报告中的数字为本次实测快照，
> 若与 test-map.md 冲突，以 test-map.md 为准。

---

## 一、执行摘要

本次对四个测试层做了完整实跑，**全部 4 层的功能正确性均为通过**，
但发现 **`cargo fmt --check` 未通过（50 处）** 与 **E2E 全量套件不可用** 两类工程性问题。

| 测试层 | 命令 | 结果 | 判定 |
|--------|------|------|------|
| AHK v2 全量套件 | `AutoHotkey64.exe tests/run_all_tests.ahk` | **616 / 616 通过，160 套件，0 失败** | ✅ 通过 |
| Rust workspace | `cargo test --workspace` | **598 passed / 0 failed / 16 ignored** | ✅ 通过 |
| Rust 忽略测试 | `cargo test -p asd-tauri --lib -- --ignored` | **15 passed / 1 failed** | ⚠️ 1 例死测试 |
| 前端 helper 单测 | `node --test helpers/__tests__/*.js` | **19 / 19 通过** | ✅ 通过 |
| 前端构建 | `npx vite build` | **成功**（8 模块，1.27s） | ✅ 通过 |
| E2E smoke | `npx wdio run wdio.conf.js --spec specs/smoke.spec.js` | **1 passing (18s)** | ✅ 通过 |
| E2E 全量 | `npx wdio run wdio.conf.js` | **1 passed / 8 failed / 9 files** | ❌ 不可用 |
| `cargo clippy --workspace --all-targets` | — | **0 代码告警**（注：需先清理损坏的 incremental 缓存） | ✅ 通过 |
| `cargo fmt --all --check` | — | **失败：50 处违规，7 文件** | ❌ 未通过 |
| 依赖图谱 | `python .review-analysis/build_graph.py` | 与基线完全一致，**0 新增环** | ✅ 通过 |

**总体结论**：功能层面可用性 **良好**（本地单测层全绿）；工程层面的两道 DoD 闸门
（② fmt 零告警、③ 测试登记准确）**未满足**，且 E2E 集成层**因工具链缺陷整体失效**。

---

## 二、正常场景测试结果

### 2.1 AHK v2 全量套件

```
总计: 616 个测试
通过: 616 个
失败: 0 个
✓ 所有测试通过!
```

- **160 个套件**全部执行；`test_ahk_executor/` 下 5 个文件提供 **59 套件**
- 失败数、`RUNTIME_ERROR` 数均为 **0**
- 覆盖：domain 层（技能管理、热键路由、模式执行、手柄输入）、
  executor（IPC 指令分发、按键发送）、migration logger 等
- **判定：正常场景全通过**

### 2.2 Rust workspace

`cargo test --workspace` 各 target 结果：

| Target | passed | failed | ignored |
|--------|--------|--------|---------|
| asd-ipc-protocol 单测 | 70 | 0 | 0 |
| asd-ipc-protocol 集成 | 17 | 0 | 0 |
| asd-domain 单测 | 89 | 0 | 0 |
| asd-domain 集成 | 43 | 0 | 0 |
| asd-application 单测 | 39 | 0 | 0 |
| asd-application 集成（多文件） | 33 / 28 / 16 / 13 / 11 / 4 / 4 | 0 | 0 |
| asd-test-harness | 3 | 0 | 0 |
| **asd-tauri（lib）** | **226** | **0** | **16** |
| doc-tests | 1 + 1 | 0 | 0 |
| **合计** | **598** | **0** | **16** |

- **0 失败**，全部 function-level 断言通过
- 16 个 `ignored` 见 §4.1（其中 1 例为必然失败的死测试）

### 2.3 前端

- **helper 单测 19/19**：`ahk_path.test.js`（5 例，验证硬编码路径消除 + 环境变量优先级）
  + `error_utils.test.js`（14 例，验证 `AppError {kind,message}` 结构化提取，**确保不返回 `[object Object]`**）
- **`vite build` 成功**：8 模块 → `dist/index.html` 29.95 kB、CSS 16.72 kB、JS 71.01 kB

### 2.4 E2E smoke

修复 driver 版本后 **1 passing (18s)** —— 证明：
- `tauri-driver` ↔ `msedgedriver` ↔ Tauri WebView2 三方通信链路**可用**
- 应用能启动、窗口能就绪、`browser.execute` 桥接**正常**

---

## 三、边界场景测试结果

### 3.1 IO 层边界（`asd-application` — 10 项探测，**10/10 通过**）

| 场景 | 结果 | 说明 |
|------|------|------|
| UTF-8 往返（含 emoji） | ✅ 一致 | 序列化/反序列化**无损** |
| 5 MB 大文件读取 | ✅ 正常 | 无 OOM、无超时 |
| 连续 10 次保存 | ✅ 全部成功 | 临时文件命名含 pid + 纳秒，**无冲突** |
| `save_to_path` → `load_from_path` 往返 | ✅ 7 分组无损 | 数据保真 |
| 深路径写入（父目录不存在） | ✅ `Err` 且 `exists=false` | **by design**：`atomic_write` 不建父目录，职责分离给 `ensure_dir_all` |

### 3.2 配置校验边界（`asd-domain` — 10 项探测）

| 场景 | 结果 | 判定 |
|------|------|------|
| 空配置 | `valid=true`, 0 errors | ✅ 合理（空配置可接受） |
| 空热键 | `valid=false`, 1 error | ✅ 正确拒绝 |
| 重复热键 | `valid=false`, 1 error（含"重复"） | ✅ 正确拒绝 |
| `periodic` 模式无按键 | `valid=false`, 2 errors | ✅ 正确拒绝 |
| 间隔为 `u64::MAX` | `valid=true` | ⚠️ 见 §4.4 |
| `keys` / `intervals` 长度不匹配（3 vs 1） | `valid=true` | ⚠️ 见 §4.4 |
| 乱码热键 `!!!not-a-key!!!` | `valid=true`（仅 warning） | ✅ **设计决策**，见下 |
| 超长热键（10000 字符） | `valid=true`（无长度上限） | ⚠️ 见 §4.4 |
| `keys` 与 `intervals` 不匹配时的**运行时行为** | 优雅回退 50ms | ✅ 见 3.3 |

**关于「乱码热键只报 warning 不报 error」——这是有意的设计决策，不是缺陷。**
`validator.rs:155` 有明确注释：热键键名可能包含 `VALID_HOTKEY_KEYS` 白名单之外、
但 AHK 实际支持的自定义键名；若升级为 `error`，会让这些「合法但不在白名单内」的配置
整体被判无效，**阻止应用启动/保存**。此处选择 warning 是**可用性优先**的正确权衡。

### 3.3 运行时防御性回退（AHK）

`sender.ahk:370`：

```ahk
interval := i <= intervals.Length ? intervals[i] : 50
```

当配置中 `keys` 多于 `intervals` 时，**AHK 侧优雅回退到 50ms**，不抛异常、不中断执行。
这是**双层防御**设计：校验层放行（warning）→ 运行时兜底（回退值）。**判定：正确。**

### 3.4 E2E 夹具有效性

对 `e2e/fixtures/test_config.json`（2281 字节）做完整反序列化探测：

- 反序列化**成功**，分组数 = **7**
- 顶层字段名与 `Config` **完全匹配**（`CONTROL_HOTKEYS` / `GroupSettings` / `HoldSettings` / `version`）
- `mode` 字符串与 `ModeData` 判别式**正确对应**（periodic→0, sequence→1, hybrid→2, hold→3, enhanced\_\*→4/5/6）
- `valid = true`，**0 errors，0 warnings**

**结论：夹具本身完全有效**，E2E 失败与夹具无关。

---

## 四、异常场景测试结果

### 4.1 已发现的缺陷（按严重度排序）

#### 🔴 P0-1：E2E 全量套件 8/9 失败 —— 根因已定位

> **⚠️ 后续更正（2026-09-13 修复阶段）**：本节「根因已确证」的判定
> **部分被实测推翻**，推荐方案 `useHttpsScheme: true` **不对症、已废弃**。
> 真因是 **E2E 未启动 Vite dev server 导致 WebView 页面未加载**（错误页 origin 为 `null`，
> 进而使 Tauri IPC 报 `Origin header is not a valid URL`）。
> 完整更正与最终修复见 **`bug-fix-plan.md` § BUG-1「根因更正」**。
> 本节以下内容按**当时观察**原样保留，仅作历史记录。

**现象**：`npx wdio run wdio.conf.js` → **1 passed / 8 failed**，8 个 spec 均在
`before all` 钩子失败，错误信息被吞成 `Tauri invoke('save_config') failed: [object Object]: unknown error`。

**根因（本次已确证，非推测）**：通过植入诊断 spec 捕获**原始 reject 值**，得到：

```json
{
  "ctor": "String",
  "type": "string",
  "isError": false,
  "keys": [],
  "json": "\"Origin header is not a valid URL\"",
  "message": "NO_MESSAGE_FIELD",
  "kind": "NO_KIND_FIELD"
}
```

真实错误是 **`"Origin header is not a valid URL"`** —— 这是 **WebView2 / msedgedriver 的
WebDriver 协议层拒绝**，**不是** Rust 侧 `AppError`（否则会有 `{kind, message}` 字段）。
同一失败对 `get_config` **也一样复现**，证明**与具体命令无关，是桥接层通病**。

**机理**：Tauri 的 WebView 使用自定义协议（`tauri://localhost` 等），其 `Origin` 头
不是标准 URL。msedgedriver 在处理 `/execute/async` 端点时会校验 `Origin`，
**无法解析即拒绝**。这正是 `e2e/helpers/tauri.js` 文件头注释**已经记载**的问题：

> 注：使用 `browser.execute`（同步）+ 轮询模式，而非 `browser.executeAsync`。
> 原因：msedgedriver 在 Tauri webview 上执行 `/execute/async` 端点时报错
> **"Origin header is not a valid URL"**（Tauri 自定义协议 origin 不被识别）。

**矛盾点**：`invoke()` 已按此注释改用 `/execute/sync`，但**失败依旧**。说明
**该规避措施并未生效**，或 `/execute/sync` 端点**同样**会触发 `Origin` 校验。
`tauri.js:61` 的轮询循环虽加了 `try-catch` 吞掉 `/execute/sync` 异常，
但**捕获后不断重试同一端点 150 次**（15 秒），最终仍以 `lastExecuteError` 抛出——
**吞异常 + 重试并不能解决协议层拒绝**，只是把失败延迟了 15 秒。

**修复建议**（三个方向，按推荐度排序）：

1. **【推荐】给 WebView2 设置合法 Origin**（治本）
   在 `tauri.conf.json` 的窗口配置中显式指定 `useHttpsScheme: true`，
   使 WebView 使用 `https://tauri.localhost` 而非自定义协议。
   这样 `Origin` 头即为合法 URL，WebDriver 协议层不再拒绝。
   - 影响面：`tauri.conf.json`，需回归 E2E + 前端资源加载
   - 风险：可能影响 IPC / asset 协议加载路径，需完整回归

2. **【次选】改用 tauri-driver 原生能力替代 DOM 注入**
   当前 `invoke` 依赖在页面内执行 JS。可改为让后端在测试模式下暴露
   一个本地 HTTP/WS 调试端点，E2E 直接经 Node 侧 `fetch` 调用，
   **完全绕开 WebDriver 的 `execute` 端点**。
   - 优点：彻底规避 Origin 问题，且更稳定
   - 成本：需新增「测试模式」开关与端点，属生产代码改动，需评估安全边界

3. **【兜底】修正错误信息提取，至少让失败可诊断**
   即使桥接不可用，也不应把真实错误吞成 `[object Object]`：
   `tauri.js:73` 的 `lastExecuteError` 是 WebDriverIO 抛出的 `Error`，
   其 `.message` 才含 `"Origin header is not a valid URL"`；
   而当前代码用 `String(lastExecuteError)` 得到 `[object Object]: unknown error`。
   - **低成本、独立可做**：建议**无论是否修复根因，都先做这一项**
   - 同时应**缩短重试**：协议层拒绝是确定性失败，重试 150 次无意义，
     应识别该类错误后**立即失败**（快失败）

> **重要**：本项**不是产品功能缺陷**，而是**测试工具链缺陷**。
> 生产环境中 Tauri WebView 走的是 Tauri 自己的 IPC，不经过 WebDriver，**不受影响**。
> 因此 P0 定级是针对「E2E 集成测试可用性」，而非「产品可用性」。

---

#### 🔴 P0-2：`cargo fmt --check` 未通过 —— 50 处违规，7 个文件

`cargo fmt --all --check` 报 **50 处** `Diff in`，分布如下：

| 文件 | 违规数 |
|------|-------|
| `crates/asd-application/src/recording_service.rs` | 16 |
| `crates/asd-domain/src/validator.rs` | 11 |
| `src-tauri/src/tests/bridge_tests.rs` | 10 |
| `crates/asd-application/src/config_repository.rs` | 5 |
| `src-tauri/src/tests/command_contract_tests.rs` | 4 |
| `src-tauri/benches/benchmarks.rs` | 3 |
| `src-tauri/src/lib.rs` | 1 |
| **合计** | **50** |

**性质**：**全部为 pre-existing**（本次测试未修改任何生产代码，工作区 `git status` 仅含
本次新增的探测文件与记忆文件）。典型形态为长函数调用未换行，例如
`config_repository.rs:37`：

```rust
// 现状（fmt 要求合并为一行）
let tmp_file_name = format!(".tmp_{file_name}_{}_{}",
    std::process::id(),
    now.as_nanos()
);
```

**影响**：违反 **DoD 第 ② 闸门**（fmt + clippy 零告警）。当前**无 CI 工作流**拦截，
因此该问题会持续累积。

**修复建议**：
1. 立即执行 `cargo fmt --all` 一次性归零（**纯格式化，零行为变更**，可安全批量提交）
2. **补 CI 工作流**（GitHub Actions / 本地 hook）加入 `cargo fmt --all --check` 门禁，
   防止再次漂移
3. 注意：`.gitattributes` 强制 LF；`cargo fmt` 输出为 LF，**不会**引入 CRLF 问题

---

#### 🟠 P1-1：测试数登记漂移 —— `asd-tauri` 实际 243 vs 登记 231

**根因**：测试计数正则 `^\s*#\[(tokio::)?test\]` **不匹配带参数的属性**，
例如 `#[tokio::test(flavor = "multi_thread")]`。正确正则应为
`#\[(tokio::)?test[^]]*\]`。

**本次实跑权威数字**（`cargo test -- --list` 运行时注册数）：

| crate | 实际 | 登记 | 差异 |
|-------|------|------|------|
| asd-domain | 132 | — | — |
| asd-ipc-protocol | 72 | — | — |
| asd-application | 163 | — | — |
| asd-test-harness | 3 | — | — |
| **asd-tauri** | **243** | **231** | **+12** |
| **全 workspace** | **613** | **601** | **+12** |

其中 `asd-tauri` 内部关键子项：

| 模块 | 实际 | 登记 | 说明 |
|------|------|------|------|
| `tests::bridge_tests` | **13** | **4** | **漏检 9 个**（全部是 `#[tokio::test(flavor = "multi_thread")]`） |
| `tests::watchdog_integration_tests` | **17** | 14 | 双口径（`#[test]` 属性 14 vs `fn` 17） |

**修复建议**：
1. 修正计数脚本正则为 `#\[(tokio::)?test[^]]*\]`
2. 以 **`cargo test -- --list` 运行时口径**为准更新 `test-map.md`（该文档是测试数字唯一权威）
3. 保留 `watchdog_integration_tests` 的**双口径说明**（两者都对，禁止互纠）

---

#### 🟠 P1-2：`test_tauri_event_bridge_emit` 是必然失败的死测试

`src-tauri/src/tests/bridge_tests.rs:200-213`：

```rust
#[tokio::test(flavor = "multi_thread")]
#[ignore = "TauriEventBridge 需要 tauri::AppHandle，需在 Tauri 集成环境中运行"]
async fn test_tauri_event_bridge_emit() {
    panic!("此测试需要 Tauri AppHandle，无法在纯单元测试环境中运行");
}
```

**问题**：
- `#[ignore]` 使其在常规 `cargo test` 中跳过（不报错）
- 但 `cargo test -- --ignored` 时**必然 panic**（实测：**15 passed / 1 failed**）
- 函数体是**永久占位符**，没有任何断言价值

**影响**：使 `--ignored` 运行**永远不能全绿**，掩盖真实失败（狼来了效应）；
违反 DoD 第 ③ 闸门「测试通过」。

**修复建议**（二选一）：
1. **【推荐】删除该测试**。事件发射逻辑已由 `test_event_emitter_trait_contract`
   通过 `MockEventEmitter` 间接覆盖（实测通过），真实 `AppHandle` 路径应由 E2E 覆盖
2. 若需保留，改为**正常返回 + 显式断言跳过原因**，或转为 E2E 用例

---

#### 🟡 P2-1：clippy 的 ICE 实为缓存损坏（非代码问题）

**现象**：`cargo clippy --workspace --all-targets` 在 `asd-tauri` (lib) 上
报 `error: the compiler unexpectedly panicked ... no entry found for key`
（`rustc_metadata/src/rmeta/encoder.rs:2447`）。

**根因（本次已确证）**：**`target/debug/.fingerprint` / `incremental` 缓存损坏**。
清理后（`cargo clean -p asd-tauri` + 删除 `target/debug/incremental`）：
`cargo clippy --workspace --all-targets` → **`Finished` 且 0 代码告警**。
4 个纯逻辑 crate 单独跑 clippy 也均为 **0 告警**。

**残留 1 条“warning”**：`error copying object file ... 拒绝访问。 (os error 5)`
—— 这是**增量缓存写入的权限/占用问题**，属**构建环境问题**，**不是代码告警**。

**修复建议**：
- 不需改代码
- 在 `developer-guide.md` 的排障章节补充：「遇到 clippy ICE 先执行
  `cargo clean -p asd-tauri` 并删除 `target/debug/incremental`」
- 建议将 `target/` 排除在杀毒软件实时扫描外，减少 `os error 5`

---

#### 🟡 P2-2：E2E driver 版本必须与 WebView2 运行时严格匹配

**现象**：原 `msedgedriver.exe` 为 **149.0.4022.98**，而本机 WebView2 运行时为
**152.0.4191.66**，导致 `session not created: This version of Microsoft Edge WebDriver
only supports Microsoft Edge version 149`。

**本次处置**：已下载并替换为 **152.0.4191.66**（与运行时一致），
smoke 测试随即转为 **passing**。

**残留风险**：
- driver 是**二进制文件**（23 MB），`.gitignore:35` 的 `*.exe` 将其排除，
  **不在版本控制中** —— 其他开发者/CI 需手工下载，**极易版本错配**
- WebView2 运行时**会自动更新**，一旦更新，driver 立刻失效

**修复建议**：
1. 在 `e2e/README` 或 `developer-guide.md` 明确记录**下载命令与版本对齐规则**：
   ```bash
   # 先查本机 WebView2 运行时版本，再下载同版本 driver
   curl -sL -o edgedriver.zip \
     "https://msedgedriver.microsoft.com/<WEBVIEW2_VER>/edgedriver_win64.zip"
   ```
2. 将版本探测**自动化**：在 `wdio.conf.js` 的 `onPrepare` 中读 WebView2 注册表版本，
   与 `msedgedriver.exe --version` 比对，**不一致即明确报错**（而非等到 `session not created`）
3. 长期方案：CI 中固定 WebView2 运行时版本（或用 `--headless` + 固定镜像）

---

### 4.2 异常场景——**表现正确**的部分（无缺陷）

`asd-application` IO 异常探测 **全部优雅返回 `Err`，零 panic**：

| 异常输入 | 返回 | 消息质量 |
|---------|------|---------|
| 文件不存在 | `Err` | `读取配置文件失败: 系统找不到指定的文件。 (os error 2)` ✅ 清晰 |
| 畸形 JSON | `Err` | `解析配置文件失败: key must be a string at line 1 column 3` ✅ **含行号列号** |
| 空文件 | `Err` | ✅ |
| 带 BOM 的 JSON | `Err` | ✅（明确拒绝，不静默） |
| 数字溢出 | `Err` | ✅ |
| 目录当文件传入 | `Err` | ✅ |
| 非法盘符写入 | `Err` | ✅ |
| 父目录缺失时保存 | `Err` | `写入临时文件失败: 系统找不到指定的路径。 (os error 3)` ✅ 且**未创建半成品文件** |

**判定：错误处理健壮，无 panic、无静默失败、消息可诊断。**

### 4.3 异常场景——配置校验的「宽松」行为（待确认设计意图）

以下 3 项**当前放行**，需确认是否有意为之：

| 场景 | 当前行为 | 风险 | 建议 |
|------|---------|------|------|
| `keys` / `intervals` 长度不匹配 | `valid=true` | 中：语义歧义 | 依赖运行时回退（§3.3）可接受，但建议**加 warning** 提示配置可疑 |
| 间隔 = `u64::MAX` | `valid=true` | 低：可能导致超长等待 | 建议加**上界校验**（如 ≤ 60000ms）或 warning |
| 热键长度无上限（10000 字符） | `valid=true` | 低：可能影响 AHK 解析性能 | 建议加**长度上限**（如 256）或 warning |

`validate_mode_data` 已检查 `keys.is_empty()` / `intervals.is_empty()` /
`intervals.contains(&0)`，但**未检查长度一致**。由于 AHK 侧有 50ms 兜底，
**功能不会崩**，但配置错误会**被静默吞掉**，用户难以察觉。

### 4.4 契约一致性（**全部对齐，无缺陷**）

| 契约 | 结果 |
|------|------|
| IPC 契约：Rust `IpcCommand` 13 variants ↔ AHK executor 11 action 分支 | ✅ **完全对齐**；`ping` / `shutdown` 走内部路径，符合设计 |
| Tauri 命令：后端 34 命令 ↔ 前端 34 处调用 | ✅ **完全一致** |
| 依赖分层：`infrastructure 0` → `domain 1` → `application 2` → `presentation 3` → `entry 4` | ✅ 无逆向边 |
| Rust crate 生产依赖环 | ✅ **0 环** |
| 已知白名单违规 | 3 处（均为 `asd-test-harness` 反向依赖，**属夹具设计意图**） |

---

## 五、发现的问题汇总与优先级

| # | 严重度 | 问题 | 影响 | 修复成本 |
|---|-------|------|------|---------|
| 1 | 🔴 P0 | E2E 8/9 失败，根因 `Origin header is not a valid URL` | E2E 集成测试**整体不可用** | 中（治本）／低（兜底） |
| 2 | 🔴 P0 | `cargo fmt --check` 50 处违规 / 7 文件 | 违反 DoD ②；无 CI 拦截 | **低**（`cargo fmt --all`） |
| 3 | 🟠 P1 | 测试数登记漂移（+12；`bridge_tests` 4→13） | 违反 DoD ③；数字不可信 | **低**（改正则 + 更新 test-map） |
| 4 | 🟠 P1 | `test_tauri_event_bridge_emit` 死测试 | `--ignored` 永不全绿 | **低**（删除） |
| 5 | 🟡 P2 | clippy ICE 源自缓存损坏 | 误导为代码问题 | **低**（清缓存 + 文档） |
| 6 | 🟡 P2 | E2E driver 版本硬耦合且不入版本控制 | 换机/更新即失效 | 中（自动化探测） |
| 7 | 🟡 P2 | 配置校验对 3 类可疑值放行 | 配置错误被静默吞掉 | 低（加 warning） |

**建议处置顺序**：**#2 → #3 → #4**（三项均为低成本、纯工程性、可立即消除闸门违规）
→ **#6 兜底部分**（修正错误提取，让 E2E 失败可诊断）
→ **#1 治本**（需评估 `useHttpsScheme` 影响面）→ **#5 / #7**（文档与增强）

---

## 六、测试方法学说明

### 6.1 本次使用的权威口径

- **AHK**：实跑 `run_all_tests.ahk` 的汇总行（`总计 N 个测试 / 通过 N 个 / 失败 0 个`）
- **Rust**：`cargo test -- --list` 的运行时注册数（比正则静态计数更可信）
- **计数正则**：`#\[(tokio::)?test[^]]*\]`（**必须带 `[^]]*`** 以匹配带参属性）

### 6.2 本次探测文件（已清理，未提交）

以下临时文件仅用于本次测试，**已在测试结束后全部删除**，工作区已恢复干净：

```
crates/asd-domain/tests/_probe_boundary.rs         （配置校验边界，10 项）
crates/asd-domain/tests/_probe_e2e_fixture.rs      （E2E 夹具有效性）
crates/asd-domain/tests/_probe_serde_keys.rs       （serde 字段名对齐）
crates/asd-application/tests/_probe_io.rs          （IO 边界，10 项）
crates/asd-application/tests/_probe_e2e_save.rs    （保存序列，4 项）
e2e/specs/_diag_save.spec.js                       （E2E 原始错误捕获）
```

### 6.3 本次**未做**的测试（诚实声明）

- **真实按键注入验证**：E2E `key_send.spec.js` / `hotkey_cmd.spec.js` 因 #1 阻塞，
  未能验证真实按键是否送达目标窗口
- **录制功能端到端**：`recording_cmd.spec.js` 同上阻塞（`recording_service` 单测 39 项已通过）
- **长时间稳定性 / 内存泄漏**：未做 soak test
- **多显示器 / DPI 缩放场景**：未覆盖
- **配置文件损坏后的恢复流程**：单测覆盖，未做真实应用级验证

**建议在 #1 修复后补做前两项。**

---

## 七、结论

- **功能正确性**：四个测试层全部通过，**边界与异常场景的错误处理健壮，无 panic、无静默失败**
- **契约一致性**：IPC（13↔11）、Tauri 命令（34↔34）、分层依赖、crate 环 —— **全部对齐**
- **工程健康度**：**2 项 P0 + 2 项 P1 违反 DoD 闸门**，其中 3 项修复成本极低
- **E2E 可用性**：**当前不可用**，但**根因已确证**且**不影响生产环境**

**核心判断**：本项目的**功能实现质量高**（616 AHK + 598 Rust + 19 JS 全绿、
异常处理优雅），**短板集中在工程纪律**（fmt 未归零、测试数字漂移、死测试）
与**测试工具链**（E2E Origin 阻塞、driver 版本耦合）。
前者可在**一次提交内**全部消除；后者需专项评估，但不构成产品风险。

---

## 附录：本次实测命令清单

```bash
# AHK
"D:/Program Files/AutoHotkey/v2/AutoHotkey64.exe" tests/run_all_tests.ahk > tests/test_results.log

# Rust
cd asd-tauri
cargo test --workspace
cargo test -p asd-tauri --lib -- --ignored
cargo clippy --workspace --all-targets          # 需先 cargo clean -p asd-tauri
cargo fmt --all --check
cargo test -p <crate> --all-targets -- --list   # 权威计数

# 前端
node --test helpers/__tests__/ahk_path.test.js helpers/__tests__/error_utils.test.js
npx vite build

# E2E
cd asd-tauri/e2e
npx wdio run wdio.conf.js --spec specs/smoke.spec.js
npx wdio run wdio.conf.js

# 图谱
python .review-analysis/build_graph.py
python .review-analysis/gen_graph_html.py
```
