# 整改计划与执行记录 — 基于全面工程审查的 12 项发现

**日期**：2026-09-19
**来源**：`full-review-and-incident-response-2026-09-19.md`（七维度审查，高 4 / 中 5 / 低 3）
**原则**：先验证问题是否真存在 → 再改 → 再验证是否真修好；改动最小化，不破坏现有功能、不引入新问题
**方法**：凡声称"某问题存在/不存在"均以实测取证；凡写进门禁的守护必须做**阳性对照**（证明它会真的变红），不写永真式假守护

---

## 一、逐项梳理（按类别）

### 类别 A：架构与模块划分

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **A1** 跨语言校验双真值分裂 | Rust 与 AHK 对同一份配置有**两套独立实现**，无对拍、无单一真值 | ① 双栈不一致：同一份配置在 v4 Tauri UI（走 Rust 校验）与 v3 AHK UI（走 AHK 校验）结论不同，一侧存得下、另一侧存不下；② v4 侧是**隐性失败不是拒存**：v4 执行器零配置校验（`asd-tauri/src-tauri/ahk_executor/` 全目录 grep `ConfigValidator` 与 `Validate` 均零命中），`<10ms` 被 `sender.ahk:53/422-426` 静默钳制到 10ms、重复热键被 `state.rs:511-522` 静默丢弃 —— 存得进去、跑起来悄悄不对且无提示；③ 拒存只发生在 v3 栈（`application/config_service.ahk:85`），ADR-001 已把 v3 转维护模式。⚠️ 订正：原写"在 Tauri UI 看着合法、保存时被 AHK 拒存"**两个栈串了**（v4 保存路径走 `config_cmd.rs:71` → Rust `asd_domain::validator`，不经 AHK 校验器）。**失败形态由显性（拒存）转为隐性（静默钳制/静默丢弃）**，非影响变小、是更难被发现 | `crates/asd-domain/src/validator.rs` ↔ `infrastructure/config_validator.ahk` | **高（实质）** | ✅ 实跑取证，**7 处**分歧（最小间隔 10ms、24h 上界、下划线键名白名单、分组查重入口、控制热键空值定级、HoldSettings 区间、joystick_hold 50ms）。⚠️ **订正（2026-09-19）**：原计 8 处，多出的「热键长度 256 vs 15 字符」一条**经实跑证伪** —— AHK 的 `StrLen(hotkey)>15 → ERROR` 只存在于 `ValidateGroupHotkeys`（`infrastructure/config_validator.ahk:82`，定义于 `:63`），该入口**生产零调用**（全仓仅 `tests/archive/test_infra_full.ahk:173` 一处调用，且既不在 `tests/run_all_tests.ahk` 也不在 G3g 独立脚本清单内）；对拍口径走 `ConfigValidator.Validate()`，该规则在此不可达，20 字符热键两侧实测均无 ERROR。**实为 7 处，且 7 处已全部入夹具** | **需决策，不擅自修**：收敛前必须先定"以哪侧为准"。本轮已建对拍装置使其**可观测**（TD-067），改任一侧都会改变用户可见的保存行为 |
| **A2** 双栈配置不共享 | Tauri 用 `app_data_dir`，AHK 用 cwd 相对路径，两个真值位置 | 同一份配置在两栈不一致且不报错 | `src-tauri/src/lib.rs:702-707`（含静默回退当前目录）；`application/config_service.ahk:26` | 中 | ✅ 源码确认 | **需决策**：ADR-001 已定"以 Tauri 为准、AHK 栈转维护模式"（TD-069），但**配置路径统一属行为变更**，未动代码 |
| **A3** 上帝文件 | 单文件承载过多聚合 | 整洁性 | `validator.rs`(2626 行)、`state.rs`(1641 行) | 低 | ⚠️ **原判断被实测修正**：生产代码仅 917/862 行，测试占 65%；超长函数已在 TD-023 拆完 | **不拆**，登记 TD-070（已豁免 + 4 条触发条件） |

### 类别 B：依赖与接口

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **D1** 红线 4 锁顺序无守护 | 锁顺序 `ipc_manager → watchdog` 只写在注释里 | 违反即在特定时序死锁 | `src-tauri/src/lib.rs` 注释 | 中 | ✅ 确认无静态守护 | **不硬写守护**：静态正则必漏报+误报，假守护比不守更危险。TD-065 登记，注明"静态不可靠判定" |
| **D2** 依赖面 | — | — | 直接依赖 22 个，`security-audit` job 存在 | 低 | — | 正面项，无动作 |

### 类别 C：错误处理与日志

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **E1** 生产代码 panic 风险 | — | — | 4 个 crate 生产代码 | — | ⚠️ **原印象被推翻**：生产代码 `unwrap`/`expect`/`panic!` = **0 处**（粗略 grep 的 336 处全在内联测试模块内，差 80 倍） | 正面项，无动作 |
| **E2** 日志配置 | — | — | `src-tauri/src/infrastructure/logging.rs`（DAILY 轮转 + `max_log_files(7)` + EnvFilter 兜底） | — | 配置健康 | 正面项，无动作 |
| **E3** 无运行时遥测 | 无崩溃上报、无指标回传；用户连"版本号/日志在哪"都拿不到 | 真实环境黑盒；事故只能靠口头反馈，无法量化影响面 | 全仓无 APM；前端零 `getVersion`/日志导出入口（已 grep 确认） | **中（先行项价值高）** | ✅ 已验证：前端 `exportLog`/`导出日志`/`getVersion` 全部零命中 | ✅ **本轮修复**：UI 加「诊断信息」入口（版本 + 日志目录 + 一键复制）。见 §2.1 |

### 类别 D：性能瓶颈

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **P1** `send()` 持锁做 I/O | 持 `send_half` 互斥锁完成 `write_all`(2s)+`flush`(2s)，最坏 4s；`IpcBridge` 在 `block_in_place+block_on` 里调用 → 堵住 tokio 工作线程 | AHK 偶发繁忙时 UI 卡顿 | `src-tauri/src/infrastructure/ipc.rs`、`bridge.rs` | 中 | ✅ 代码级时延上界确认（注释已修正为真实上界） | **不擅自重构**：结构性修复（单写者任务 + mpsc）属重构；"调小超时"会在 AHK 繁忙时制造误超时→误判断连，是用新故障换旧风险。TD-066 登记。**缺可复现用例**（先补证据再动） |
| **P2** 性能基准结果不可得 | bench job 存在但未与门禁阈值绑定 | 无法判断性能回归 | CI job `bench`/`ahk-bench` | 中 | ✅ 确认 | 排期，需先定阈值 |

### 类别 E：安全与权限控制

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **S1** IPC 管道无 DACL | `interprocess` 2.4.2 的 `ListenerOptions` 不暴露安全描述符 | 同权本地进程可连接 → 窃取 `ASD_AUTH_TOKEN` + 按键注入 | `src-tauri/src/infrastructure/ipc.rs` | **高** | ✅ 已核实：`ListenerOptions::new().name(name)` 只有 name，无 SD 入口；全仓无 `DACL`/`CreateNamedPipe` 实现 | **登记 TD-071**：修法需绕过该库直调 `CreateNamedPipeW`，属替换/包装依赖级改动。当前缓解＝随机管道名 + token 首消息认证（**已注明"随机名 ≠ DACL 等价替代"**） |
| **S2** 导出导入任意 `.json` 路径 | 只校验绝对/无 `..`/非 UNC/`.json`，无根目录白名单 | 任意 `.json` 读写混淆代理面 | `crates/asd-application/src/backup_service.rs:22-50` | 中 | ✅ 源码确认 | **登记 TD-072**，需产品先定义允许的根目录。**刻意不加黑名单**（会被误当完整防护，是假守护） |
| **S3** CSP / 全局 API | — | — | `tauri.conf.json` | — | ✅ 本轮已修复：`withGlobalTauri: false`，`script-src` 去掉 `unsafe-inline` | 已完成 |

### 类别 F：测试覆盖

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **T1** `src-tauri` 覆盖率在棘轮外 | G3f 只圈 3 个纯逻辑 crate；`src-tauri` 占全仓 38.0% 却无门禁 | 对外宣称 89.05% 高估约 5pp（全仓实测 84.00%） | `asd-tauri/src-tauri/`；`docs/developer-guide.md` §4.6.1.3 | **高** | ✅ 实测全仓 84.00% / `src-tauri` 69.90% | **文档侧已修**（强制标注口径 + 声明全仓口径唯一权威）；**纳入口径需重设基线**，涉及水位变更，由负责人决定 |
| **T2** CI E2E 结构性不可达 | 门控 `workflow_dispatch && inputs.run_e2e`（默认 false） | 真实用户路径零自动化验证 | `.github/workflows/ci.yml:564`、`:30-33` | **高** | ✅ 确认；且**上游官方示例在 windows-latest 同失败**（`DevToolsActivePort`） | **判据性不改门控**：开门控 = 从"不跑"变"必跑且必挂"。已做文档口径标注（本机 53 全绿 ≠ CI 信号），登记 TD-061/062 |
| **T3** test-map 明细行无守护 | B 段只按 crate 总数对账 | `watchdog.rs` 32→38 漂移未被发现 | `scripts/check-test-map.py` | 中 | ✅ 实证漂移 | ✅ **本轮修复**：新增 D5 段（原判断"无机械映射方案"**被推翻**）。见 §2.2 |
| **T4** 测试规模与通过率 | — | — | Rust 667/0、AHK 722/0/0、`#[ignore]`=0 | — | — | 正面项 |

### 类别 G：构建与部署配置

| 项 | 根因 | 影响范围 | 涉及文件/模块 | 优先级 | 问题是否真存在 | 处置 |
|---|---|---|---|---|---|---|
| **B1** 无 release job | 9 个 job 全为校验类，无一个产出安装包 | **没有可发布产物、没有可回滚版本**；事故响应「回滚」物理上不存在 | `.github/workflows/ci.yml` | **高（P0 中的 P0）** | ✅ 确认；**并已验证可行路径**：e2e job 内含可复用的 AHK 前置（install-autohotkey@v2.1.0 → 复制到 `ahk_executor/AutoHotkey64.exe`），缺的只是独立 job | ✅ **本轮修复**：新增独立 release job（手动/tag 触发，默认不跑）。见 §2.3 |
| **B2** 无自动更新 | 无 `updater` 配置 | 缺陷版本无法召回 | `tauri.conf.json` | 中 | ✅ 确认 | **登记 TD-075**，前置依赖 B1 |
| **B3** 版本未推进 / 仅 Windows | `version = 0.1.0`、`targets: ['nsis']` | 无版本标识；无其它平台产物 | `tauri.conf.json` | 低 | ✅ 确认 | 随 B1 的发布流程一并推进 |
| **B4** 改动未提交 | 两轮共 22 文件改动 + 新增文件未入库 | 存在丢失面 | 工作区 | 中 | ✅ `git diff --stat` = +1262/−168 | 需人工提交（本 worktree 嵌套 ref，**禁止**在此执行 git 写操作） |

---

## 二、本轮实际执行项（3 项）

### 2.1 E3 先行项：UI「诊断信息」入口（TD-076 拆解项）— ✅ 已完成

- **为什么只做这个**：完整遥测涉及隐私合规与后端，不是纯代码问题；但"让用户能一键拿到版本号与日志位置"成本极低，能立刻改善事故时的信息质量。
- **执行**：成员 `frontend-diag`；**主理人独立复验**
- **约束**：CSP 已无 `unsafe-inline` → **禁止内联事件处理器**，必须 `addEventListener`；优先零 Rust 改动
- **改动**（3 文件，纯新增约 120 行，**零 Rust / 零 capabilities**）：
  - `asd-tauri/index.html` +31：导航新增「🩺 诊断信息」项 + `#page-diagnostics` 页（`#diagVersion`、`#diagLogDir`、`data-action="copyDiagnostics"` 一键复制、`refreshDiagnostics` 刷新、失败兜底 textarea）
  - `asd-tauri/src/api.js` +21：`getAppVersion()` → `getVersion()`、`getLogDirPath()` → `appDataDir()`
  - `asd-tauri/src/main.js` 约 +91：`switchPage` 标题表 + 进入即 `loadDiagnostics()`；新增 `loadDiagnostics/buildDiagnosticText/copyDiagnostics/legacyCopyText/showDiagFallback/hideDiagFallback`，全部走 `data-action` 事件委托
- **⚠️ 主理人实测核实的关键正确性点（做之前最担心错的一条）**：日志目录到底在哪？Rust 侧实际写在 `app.path().app_data_dir()`（`src-tauri/src/infrastructure/logging.rs:19-33`，文件名前缀 `asd` 后缀 `log`）—— **不是 `appLogDir()`**。前端取 `appDataDir()` 与 Rust 侧**同一目录**，路径对得上。若此处选错，这个入口给出的就是错误路径，比不给更糟。
- **零 Rust 的依据**（实测）：`@tauri-apps/api` 实装 **2.11.0**；`getVersion()` → `plugin:app|version`（`core:app:allow-version`）、`appDataDir()` → `plugin:path|resolve_directory`（`core:path:allow-resolve-directory`），两者均已被现有 `core:default` 覆盖 → 无需开 capabilities。产物 JS 中两条 invoke 各命中 1 处（证明未被 tree-shake）。
- **验收（主理人独立复跑，非采信成员自报）**：

| 项 | 改动前基线 | 改动后 | 结论 |
|---|---|---|---|
| `npm test` | tests 39 / pass 39 / fail 0 | tests 39 / pass 39 / fail 0 | ✅ 未破坏 |
| `npx eslint . --max-warnings 0` | rc=0，0 行输出 | rc=0，0 行输出 | ✅ |
| `npm run build` | — | ✓ built，dist/index.html 29.98 kB | ✅ |
| `dist/index.html` 内联处理器 | — | **0** | ✅ #16 硬指标未倒退 |
| 源码 `index.html` 内联处理器 | — | **0** | ✅ |

- **兜底设计**：复制三级兜底 `navigator.clipboard` → textarea + `execCommand` → 页面内只读 textarea 自动全选 + 提示 + error toast，**绝不静默失败**。
- **交付时新发现并已登记**：版本号四处口径冲突（`tauri.conf.json` 0.1.0 / `package.json` 0.1.0 / `index.html` 硬编码「v3.0 Tauri」×2 / `AGENTS.md` v4.0）→ **TD-078**（P1，登记待定）。诊断页显示 `0.1.0`，与用户眼前界面自述冲突。**未擅自改**：选权威源属产品/发布决策。
- **未做**：「打开/导出日志文件」一步到位（需 `plugin-opener` 的 `revealItemInDir`，权限覆盖待确认）——按改动最小化原则留作 TD-076 后续。
- **⚠️ 补记（主理人收口时发现自己的交付缺口）**：首轮交付时测试数 39 → 39，**120 行新代码零测试**。已补 `asd-tauri/src/__tests__/diagnostics_contract.test.js`（**9 个用例**，静态读源码，与 `api_contract.test.js` 同一路子），锁三类不变量：
  1. `index.html` 的每个 `data-action` 都在 `main.js` 有分发分支 —— **防"按钮点了没反应"**（这类错无任何报错，只表现为点击静默无效）。实测 45 个 action 差集为空。
  2. 日志目录必须取 `appDataDir()` 而**不是** `appLogDir()` —— 把上面那条正确性判断钉死，防止后人"顺手修正"成 `appLogDir`。
  3. `index.html` 与 `main.js` 生成的 HTML 均无内联事件处理器 —— CSP 硬指标的回归防线。
- **三条阳性对照全部实测变红并精确点名**（不是只看绿）：① `appDataDir`→`appLogDir` → 「日志目录取 appDataDir()」红；② `refreshDiagnostics`→`refreshDiagnosticsZZZ` → 「每个 data-action 都有分支」红并点名该值；③ 注入 `onclick=` → 「index.html 无内联事件处理器」红。还原后 **48/0 全绿**（39 → 48）。
- **文档同步**：`asd-tauri/docs/test-map.md` 前端测试文件表新增该行（含用例数与三条对照记录）。已确认无脚本硬编码前端测试数，不会触发 G3d 误报。

### 2.2 T3：test-map 明细行守护（D5 段）

- **状态**：✅ **已完成并验证**（详见审查报告 §6）
- **关键**：原判断"无机械映射方案"被推翻；三条实测规则精确推导模块归属
- **阳性对照**：`watchdog.rs` 登记 38→39 → D5 精确变红点名；还原回绿
- **台账**：TD-077 由「登记待定」转「已完成」

### 2.3 B1：release job（TD-074）— ✅ 已完成

- **执行**：成员 `release-engineer`
- **改动**：`.github/workflows/ci.yml` **纯新增 172 行 / 0 删除**（实测 `git diff --numstat`），9 个现有 job 一行未动
- **触发**：**仅 `workflow_dispatch` + `inputs.build_release`（默认 false）**，job 条件 `github.event_name == 'workflow_dispatch' && inputs.build_release`；**未加 `push: tags`**（理由：workflow_dispatch 可在 UI 选任意 ref，重出历史版本天然零自动红灯）
- **依赖**：`needs: gates`（发布必须建立在四闸门绿之上；实测 `other_jobs_with_needs == []`，现有 job 无一被波及）
- **关键步骤**：checkout → rust → node → `npm ci` → **install-autohotkey@v2.1.0 + 复制到 `ahk_executor/AutoHotkey64.exe`（与 gates/e2e 同款）** → `npm run tauri build`（release 模式）→ 生成 SHA256SUMS.txt → upload-artifact（retention 90 天，`if-no-files-found: error`）
- **两处防静默失败设计**：① 产物名从 `tauri.conf.json` 读版本动态生成，不硬编码（productName 含空格与中文，硬编码会在改名时静默上传空 artifact）；② NSIS 目录为空时**硬失败**（"构建 rc=0 但没出包"是最危险的失败形态）
- **验证**：YAML `safe_load` 通过，job 数 9 → 10，结构完好
- **顺带发现（已写入 job 注释）**：
  1. `webviewInstallMode: downloadBootstrapper` ⇒ 构建机无需 WebView2，但**用户安装时必须联网**，离线环境装不上（出路：`offlineInstaller` +约 130MB 或 `embedBootstrapper`）
  2. Tauri NSIS bundler **首次构建联网拉工具链**（缓存 `%LOCALAPPDATA%\tauri`），属新增外部依赖
  3. **release 模式 ≠ e2e 的 `--debug`**（优化/LTO 风险不等价），且 e2e 那条从未执行过 ⇒ **首次执行不保证一次绿，必须人工观察**——不把"CI 能出包"当成既有事实
- **未做**：不加签名/公证（无密钥）；未加 `push: tags`

---

## 三、判定为"不修/需决策"的项及理由汇总

| 项 | 不修理由（一句话） |
|---|---|
| A1 | **7 处**分歧需先定"以哪侧为准"（原计 8 处，「热键长度 256 vs 15 字符」经 2026-09-19 实跑证伪：AHK 该规则位于生产零调用的 `ValidateGroupHotkeys` 入口，对拍口径不可达），改任一侧都改变用户可见行为 |
| A2 | 配置路径统一属行为变更，ADR-001 已定方向但代码改动需单独排期 |
| D1 | 静态正则守护锁顺序必漏报+误报，假守护比不守更危险（TD-065） |
| P1 | 结构性重构风险高；"调小超时"会制造新的间歇性故障；缺可复现用例 |
| S1 | 需绕过 `interprocess` 直调 Win32，属依赖级改动（TD-071） |
| S2 | 需产品先定义允许的根目录；黑名单是假守护（TD-072） |
| T1 | 纳入口径 = 覆盖率水位变更，需负责人决策；文档口径标注已完成 |
| T2 | 上游 windows runner 本身失败，开门控即"必跑且必挂"（TD-061/062） |
| B2/B3 | 依赖 B1 先落地 |

---

---

## 四、汇总清单（最终交付）

### 4.1 总览

| 口径 | 数量 | 明细 |
|---|---|---|
| 审查表行数（含正面记录） | **21** | A1–A3 / D1–D2 / E1–E3 / P1–P2 / S1–S3 / T1–T4 / B1–B4 |
| 其中**实质问题** | **16** | 高 4 / 中 10 / 低 2 |
| 其中**正面记录**（无动作） | 5 | D2 依赖面、E1 生产代码 panic=0、E2 日志配置健康、S3 CSP 已收紧、T4 测试规模健康 |
| **本轮已修复并验证** | **4** | **E3**（UI 诊断入口 + 9 条契约测试）、**T3**（test-map D5 段）、**B1**（release job）、**顺带**：`docs/developer-guide.md` 排障日志路径错误（3 处命令，照抄一条日志都找不到） |
| **已登记台账、待决策后修** | **9** | A1/A2/D1/P1/S1/S2/T1/T2/B2 |
| **不修（已豁免/随其它项推进）** | **4** | A3（TD-070 已豁免）、B3（随 B1 发布流程）、正面项 5 条 |
| 修复过程**新发现并登记** | **2** | **TD-078** 版本号四处口径不一致（P1）；**TD-079** AHK 死校验入口 `ValidateGroupHotkeys`（P1 / 6.48） |
| 本轮**推翻原判断** | **6** | A3（上帝文件实为测试占比 65%）、E1（panic 实为 0，原印象差 80 倍）、T3（"无机械映射方案"被推翻）、TL;DR 计数（12 → 16）、**"8 处分歧"实为 7 处**（第 8 处经实跑证伪）、**A1 的「放大因素」方向写反**（把 v3 的拒存安到 v4 的保存路径上） |

### 4.2 逐项处置清单

| # | 定级 | 问题 | 是否真存在 | 处置 | 具体改动 / 验证结果 |
|---|---|---|---|---|---|
| **A1** | 中 | 跨语言校验双真值分裂 | ✅ 实跑 **7 处**分歧（原计 8 处，「热键长度 256 vs 15 字符」经实跑证伪） | ⚠️ **需决策，未改代码** | 已建对拍夹具 `tests/fixtures/configs/cross_lang_validator_cases.json` + `cross_lang_validator_parity.rs` + AHK 探针 `p_cross_lang_validator.ahk`（**17 例**；原记 16 例，新增 `c17_hotkey_len20_alnum_both_legal`，分类 10 核心 + 7 分歧），使分歧**可观测**。登记 **TD-067**。改任一侧都会改变用户可见的保存行为。**✅ 本轮追加：A1 收敛决策备忘录已出稿**（`deliverables/engineering-assurance/a1-convergence-decision-2026-09-19.md`，阿奇）——裁决标准定为**「真值 = 运行时实际行为」**（不是"Rust 一律赢"、也不是"取严侧"）：ADR-001 的「以 Rust 为准」约束的是**配置存在哪 / 谁做前置校验**，不是**规则内容以谁为准**，这两件事此前被混为一谈。逐处归属：**c09/c10/c13 以 Rust 为准（AHK 改）**、**c11/c12 以 AHK 为准（Rust 收紧）**、**c14/c15 维持现状只改标注**。**待人类拍板 D1–D5** |
| **A2** | 中 | 双栈配置不共享 | ✅ 源码确认 | ⚠️ **需决策，未改代码** | ADR-001 已定"以 Tauri 为准、AHK 栈转维护模式"（**TD-069**）；配置路径统一属行为变更，单独排期 |
| **A3** | 低 | 上帝文件 | ⚠️ **原判断被推翻** | **不修，已豁免** | 实测生产代码仅 917/862 行，测试占 65%；超长函数已在 TD-023 拆完。登记 **TD-070**（4 条触发条件） |
| **D1** | 中 | 锁顺序无守护 | ✅ 确认无静态守护 | **不硬写守护** | 静态正则必漏报+误报，**假守护比不守更危险**。登记 **TD-065**，注明"静态不可靠判定" |
| **D2** | 低(正面) | 依赖面 22 个 | — | 无动作 | `security-audit` job 已存在 |
| **E1** | 低(正面) | 生产代码 panic 风险 | ⚠️ **原印象被推翻** | 无动作 | 排除内联 `#[cfg(test)]` 后精确统计：`unwrap`/`expect`/`panic!` = **0 处**（粗略 grep 336 处，差 80 倍） |
| **E2** | 低(正面) | 日志配置 | — | 无动作 | DAILY 轮转 + `max_log_files(7)` + `EnvFilter` 非法 spec 回落 `info`（含 3 条兜底测试） |
| **E3** | 中 | 无运行时遥测 | ✅ 已验证 | ✅ **已修复** | 3 文件纯新增约 120 行，**零 Rust / 零 capabilities**；补 `diagnostics_contract.test.js` **9 个用例**（测试 39 → **48/0**）。`eslint` rc=0、`build` 成功、产物内联处理器 **0**。三条阳性对照均实测变红并点名。详见 §2.1 |
| **E3b**（顺带） | 中 | `developer-guide.md` 排障日志路径错误 | ✅ **实测**：`identifier` 是 `com.asd.tauri`，文档写 `$env:APPDATA\asd-tauri\`（该目录**不存在**）；且文件名是 `asd.<日期>.log` 而非 `asd.log` | ✅ **已修复** | 3 处命令改为按 `identifier` 取目录 + `asd.*.log` 按时间取最新；新增「§3.1.5 诊断信息页」；在 §3.1.1 写明两个易错点。**这不是文档洁癖** —— 排障时照抄会一条日志都找不到，而本系统无任何遥测，日志是唯一线索 |
| **P1** | 中 | `send()` 持锁做 I/O | ✅ 代码级上界确认 | ⚠️ **不擅自重构** | 注释已修正为真实上界（最坏 4s）。结构性修复属重构；调小超时会在 AHK 繁忙时制造**误超时→误判断连**，是用新故障换旧风险。登记 **TD-066**，缺可复现用例 |
| **P2** | 中 | bench 结果不可得 | ✅ 确认 | 排期 | 需先定阈值再绑门禁 |
| **S1** | 高 | IPC 管道无 DACL | ✅ 已核实 `ListenerOptions` 无 SD 入口 | ⚠️ **登记待修** | **TD-071**（P1）。修法需绕过 `interprocess` 直调 `CreateNamedPipeW`，属依赖级改动。当前缓解＝随机管道名 + token 首消息认证（**已注明"随机名 ≠ DACL 等价替代"**） |
| **S2** | 中 | 导出导入任意 `.json` 路径 | ✅ 源码确认 | ⚠️ **登记待修** | **TD-072**（P1）。需产品先定义允许的根目录；**刻意不加黑名单**（会被误当完整防护＝假守护） |
| **S3** | 低(正面) | CSP / 全局 API | — | ✅ 本轮已修复 | `withGlobalTauri: false`，`script-src` 去掉 `unsafe-inline`；产物内联处理器 = 0 |
| **T1** | 高 | `src-tauri` 覆盖率在棘轮外 | ✅ 实测 69.90% / 全仓 84.00% | ⚠️ **文档已修，纳入口径待决策** | 文档强制标注口径 + 声明全仓口径唯一权威（`developer-guide.md` §4.6.1.3）。纳入口径＝水位变更，需负责人拍板 |
| **T2** | 高 | CI E2E 结构性不可达 | ✅ 确认；上游 windows runner 同失败 | ⚠️ **判据性不改门控** | 开门控＝从"不跑"变"必跑且必挂"。已做文档口径标注（本机 53 全绿 ≠ CI 信号）。登记 **TD-061/062** |
| **T3** | 中 | test-map 明细行无守护 | ✅ 实证漂移 | ✅ **已修复** | `check-test-map.py` 新增 **D5 段**（原判断"无机械映射方案"**被推翻**），三条实测规则精确推导模块归属；16/16 明细行一致；**阳性对照**：`watchdog.rs` 38→39 → 精确变红点名，还原回绿。**TD-077** 转「已完成」 |
| **T4** | 低(正面) | 测试规模与通过率 | — | 无动作 | Rust 667/0、AHK 722/0/0、`#[ignore]`=0 |
| **B1** | 高 | 无 release job | ✅ 确认 | ✅ **已修复** | `.github/workflows/ci.yml` **纯新增 172 行 / 0 删除**，9 个现有 job 一行未动。`workflow_dispatch` + `inputs.build_release`（默认 false）+ `needs: gates`；含 AHK 前置、`npm run tauri build`、SHA256SUMS、upload-artifact；两处防静默失败设计。登记 **TD-074**（P0）转待验证。详见 §2.3 |
| **B2** | 中 | 无自动更新 | ✅ 确认 | ⚠️ 登记，前置依赖 B1 | **TD-075**（P1）。注：TD-078 版本号不定，自动更新的版本比较逻辑会判断错乱 |
| **B3** | 低 | 版本未推进 / 仅 Windows | ✅ 确认 | 随 B1 发布流程推进 | 版本号问题已单列 **TD-078** |
| **B4** | 中 | 改动未提交 | ✅ `git diff --stat` +1262/−168 | ⚠️ **需人工提交** | 本 worktree 为嵌套 ref，**禁止**在此执行 `git commit`/`reset`/`stash`；只 `git add` 过 3 个新文件以满足 G1 |

### 4.3 本轮新增台账条目

| ID | 内容 | 档位 | 状态 |
|---|---|---|---|
| TD-074 | CI 无 release job（**本轮已建 job，待首次实跑验证**） | **P0 / 12.86** | 登记待定（到期复查 2026-10-19，刻意缩短） |
| TD-075 | 无自动更新机制 | P1 / 6.06 | 登记待定 |
| TD-076 | 无运行时遥测（**"当前缓解"措辞本轮已更新**——UI 诊断入口已落地） | P1 / 5.77 | 登记待定 |
| TD-077 | test-map 明细行无守护 → **已由 D5 段闭环** | P2 / 4.55 | **已完成** |
| **TD-078** | **版本号四处口径不一致**（`tauri.conf.json`/`package.json` 0.1.0、`index.html` 硬编码 v3.0 ×2、`AGENTS.md` v4.0） | **P1 / 9.0** | 登记待定（到期复查 2026-12-18） |
| **TD-079** | **AHK 死校验入口** `ConfigValidator.ValidateGroupHotkeys()`（`config_validator.ahk:63`）**生产零调用、活动测试零调用**，却装着两条主入口没有的规则（热键 >15 字符、分组查重）。已实证误导过一次 | **P1 / 6.48** | 登记待定（到期复查 2026-12-18），修法 a/b/c 见 A1 备忘录 |

台账合计 **77 → 78** 项；C9（DPI↔档位）、C13（统计行/状态词/到期日/档位格纯度）**实测核对 78 行全过**，rc=0。

### 4.4 主理人收口判断

1. **三处"原判断被推翻"，都是同一个病因**：凭印象下结论（上帝文件、panic 风险、无机械映射方案、TL;DR 计数）。四次里三次是**数字粗算**（grep 不排除测试代码、`wc -l` 不排除测试、汇总数不回表清点）。已把「汇总数字必须从明细表机器清点」写进审查报告的订正说明。
2. **"假守护"红线本轮守住了两次**：D1（锁顺序）与 S2（路径黑名单）都判定为「写了会误报/漏报，不如不写」，只登记不实现。这比凑一个看起来在守的门禁更诚实。
3. **B1 是唯一改变"能不能回滚"这一物理事实的改动**，也是三条"高"里唯一本轮真正闭环的。另外两条"高"（T1 纳入口径、T2 E2E 门控）都需要负责人决策或外部条件，硬做只会把红灯常态化。
4. **E3 交付时暴露的 TD-078 是典型的"修一个洞、看见下一个洞"**：诊断页给出 `0.1.0`，界面自述 `v3.0` —— 一个为提升事故信息质量而做的功能，第一眼给出的就是用户认不出的版本号。**没有顺手改**，因为选权威源是发布决策。
5. **G4（那条"无法自动化、只能人工打勾"的清单）本轮真的抓到了东西**。它长期被怀疑是假守护（纯 `Write-Host`、退出码恒 0），但"developer-guide 排障是否同步"这一条真去核对时，发现文档里的日志路径**两处全错**（目录名写成不存在的 `asd-tauri`、文件名漏了日期后缀）。**在一个没有任何遥测、日志是唯一线索的系统里，排障文档指错路等于断了最后一条线索。** 结论：G4 的问题不是"没用"，而是"没人真去做"—— 自动化不了 ≠ 可以跳过。
6. **交付后自查发现自己的缺口**：E3 首轮交付 120 行零测试（测试数 39 → 39）。已补齐 9 个用例 + 三条阳性对照。**判断标准：新增代码不挂测试，就是把验证成本推给下一个人。**

---

---

## 五、⚠️ 待完善 / 已知局限

1. **A1 只做到"可决策"，没做到"已决策"**。7 处分歧的裁决标准、逐处归属与用户可见影响已全部取证并出备忘录，但**改哪一侧本身要人类拍板（D1–D5）**。本轮**一行校验规则都没改** —— 这是刻意的，不是遗漏：改任一侧都会改变用户能否保存配置。
2. **三件"高"里只有 B1 真正闭环**。T1（`src-tauri` 覆盖率纳入口径）与 T2（E2E 门控）本轮都只做了文档口径标注 —— 前者是水位变更需负责人决策，后者开门控等于"必跑且必挂"（上游 windows runner 本身失败）。**没有任何一条"高"是靠绕过去解决的。**
3. **TD-074（release job）从未真正执行过**。YAML 已通过解析与结构校验，也确认了 `needs: gates`，但**它跑起来是什么样没人见过** —— release 模式的优化/LTO 与 e2e 的 `--debug` 风险不等价。首次运行必须人工观察，不能把"CI 能出包"当既有事实。
4. **改动已按人类负责人裁决拆成 3 个提交**（44 项改动：代码与测试 / 文档与台账 / 交付报告）。实测当前目录是**主 worktree**（`.git` 是目录、分支 `main` 为顶层 ref），git 写操作安全 —— 危险的是带嵌套 ref 的 linked worktree（`C:/Users/fei/WorkBuddy/Worktrees/AutoHotkeydemo/main-5f18c6a6`，prunable），本轮所有 git 写操作都在主 worktree 完成。
5. **本轮推翻了自己 6 次判断**，其中 5 次同一病因：**凭代码存在推断行为生效**（死入口、执行器无校验器、v4 不走 AHK、AHK 校验器与运行时脱节、TL;DR 计数不回表）。这说明**双栈项目里"读代码得结论"的可靠性显著低于单栈**，凡跨栈结论必须实跑。
6. **覆盖率数字仍是旧口径**：`src-tauri` 69.90% / 全仓 84.00% 为 2026-09-19 实测，但**对外宣称的 89.05%（3 个纯逻辑 crate）尚未按新认知重取**，文档已加口径 banner 但仍可能被误读。
7. **配置文件 BOM：已修症状，但刻意不立债项（附不立理由，供后人推翻）**。D3 尽调时自建扫描脚本连续两次假绿，追下去发现：① 全仓 **12 个配置文件全部带 UTF-8 BOM**（1 层），Python `json.load(open(p, encoding='utf-8'))` **12/12 全失败**，必须 `utf-8-sig` 才能读 —— 任何外部运维/分析脚本都会踩；② **仓库根 `config.json` 带的是双 BOM**（`git show HEAD:config.json` 前 6 字节 = `efbbbf efbbbf`），已归一为单 BOM。**⚠️ 双 BOM 并没有弄坏产品，这是我先按"大概坏了"推断、查源码后才推翻的**：AHK `FileRead(filePath,"UTF-8")`（`json_parser.ahk:34`）按 `AutoHotkey-2.0.26/source/lib/file.cpp:276-281` 剥 **1 层**，`JSONParser.__New`（`:77-78`）再剥 **1 层** → 两层正好剥完；Rust `config_repository.rs:287` 的 `trim_start_matches('\u{feff}')` 对 char 型 pattern 会剥**全部**层 → 也不受影响。**双 BOM 的来源未能确认**（AHK `FileAppend(...,"UTF-8")` 按 `source/TextIO.cpp:87-90` 只在"写入且文件为空"时落 1 层 BOM，追加到非空文件不再落 —— 即应用自身写不出双层，疑为手工/工具编辑所致，**不臆断**）。**不立债项的理由**：BOM 本身是**有意设计**（`infrastructure/config_io.ahk:79` 为 Windows 记事本兼容而写 BOM），两栈都能容忍，唯一代价是外部严格解析器不便；而"双 BOM"是一次性产物、来源未明、已修。**这属于"记录一次踩坑教训"而非"登记一项技术债"**，故写在本节而不进 `docs/tech-debt-register.md`；若后续出现第二例双 BOM、或出现真正依赖严格解析的外部链路，应升级为债项并配字节级守护。**本轮教训并入第 5 条**：这已是第 6 次"凭推断下结论、实跑才推翻"。

---

## 六、📚 数据来源 & 成员产出索引

| 成员 | 产出 | 落点 |
|---|---|---|
| 主理人（甄宇航） | 逐项验证、阳性对照、裁决与收口；E3 日志目录口径核实；`developer-guide` 排障路径缺陷发现；G4 人工核对 | `remediation-plan-2026-09-19.md` §2 / §4.4 |
| 阿奇（架构师） | **A1 收敛决策备忘录**（7 处逐处裁决 + D1–D5 拍板表）；推翻"AHK 执行器会拒收"前提；发现 `joystick_hold.holdDuration` 被 v4 忽略；台账 TD-079 + TD-067 订正；`min_cases` 棘轮（4 条阳性对照） | `deliverables/engineering-assurance/a1-convergence-decision-2026-09-19.md`；`docs/tech-debt-register.md` |
| 科迪（代码审查师） | 首轮 29 项审查；IPC/导出导入/单实例三项债的识别 | `_raw-cody-code-review-2026-09-19.md`；`code-review-full-system-2026-09-19.md` |
| 泰莎（测试专家） | 测试覆盖评估、E2E 与覆盖率口径分析 | `_raw-tessa-testing-2026-09-19.md` |
| 雷克斯（SRE） | 事故响应六阶段预案、检测与告警缺口 | `_raw-rex-incident-2026-09-19.md`；`full-review-and-incident-response-2026-09-19.md` §4 |
| 多库（技术文档师） | 三份报告的「8 处→7 处」「16 例→17 例」「放大因素」订正（共 25 处，均带证伪痕迹） | `full-review-and-incident-response-2026-09-19.md`；`fix-round-2-2026-09-19.md`；本文件 |
| `frontend-diag` | E3 UI「诊断信息」入口（纯前端、零 Rust） | `asd-tauri/index.html`、`src/api.js`、`src/main.js` |
| `release-engineer` | B1 release job（ci.yml 纯新增 172 行 / 0 删除） | `.github/workflows/ci.yml` |
| `parity-probe` | 第 8 处分歧实跑证伪 + 夹具 `c17` | `tests/fixtures/configs/cross_lang_validator_cases.json` |

**验证基线（主理人独立复跑，非采信自报）**：四闸门 `--quick` ALL GATES PASSED；`npm test` 48/0；`cargo test -p asd-domain --test cross_lang_validator_parity` 3 passed；AHK 探针 17 行与夹具逐例一致；`check-tech-debt.py` rc=0 / 79 行。

---

> 本清单与主报告 `full-review-and-incident-response-2026-09-19.md`、第二轮修复报告 `fix-round-2-2026-09-19.md`、A1 决策备忘录 `a1-convergence-decision-2026-09-19.md` 配套阅读。
>
> 本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
