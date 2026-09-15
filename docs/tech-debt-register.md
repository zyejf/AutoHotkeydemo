# 技术债台账（Tech-Debt Register）

> 配套文档：`docs/tech-debt-plan-2026-09-16.md`（评估模型、分阶段路径、门禁、完成判据）。
> 本文件是**债项的唯一登记处**。规则：
> 1. 新增债项 = 开 PR 改本文件（不允许只在聊天里提）；
> 2. 任何「不修」的项必须落到 `豁免`（附理由 **+ 到期日**）或 `待定`（缺外部信息），**不允许静默消失**；
> 3. 每月按 DPI 重算一次并复审豁免项。

## 评分口径（摘抄自计划 §1.3）

```
DPI = (I + P + V + S) / ( √C × R )
I 影响面  P 恶化速度  V 可验证性  S 战略对齐   （各 1–5）
C 成本（人天，0.5/1/2/3/5/8）   R 风险系数（低 1.0 / 中 1.4 / 高 2.0）
P0 ≥10   P1 5–10   P2 2–5   P3 <2
```
硬性升档（直接 P0）：安全/数据丢失、**误导性文档**、阻塞他人、已证明会产生 flaky。
硬性降级：已确认**刻意保留**（读 `AGENTS.md` / `.workbuddy-ai/memory/MEMORY.md` 确认）。

## 基线快照（2026-09-16 实测）

| 指标 | 0 号基线值 | 当前（2026-09-16 收紧后） |
|---|---|---|
| 入库文件 | AHK 171 / md 162 / png 89 / json 89 / rs 57 / cpp 53 / c 44 / h 43 / js 23 / html 23 | 同左 |
| 生产 AHK | ~32 文件 / 11.4k 行（infrastructure 15/3690、domain 8/3441、application 3/770、presentation 6/3524） | 同左 |
| Rust crates | asd-domain 5/3709、asd-application 8/3754、asd-ipc-protocol 5/948、asd-test-harness 1/389 | 同左 |
| 测试 | AHK 664（CI 657 + 跳过 7）；Rust 405；E2E 53（CI 默认关）；criterion bench 7；fuzz 5 | **AHK 697**（CI 690 + 跳过 7）—— +33 来自 TD-002 |
| 覆盖率 | 仅 3 个纯逻辑 crate 采集，**无阈值、非阻断** | 同左 |
| 仓库体积 | `AutoHotkey-2.0.26/` 221 文件 / 7.9M（vendored 引擎源码） | 同左 |
| C1a 孤儿文件 | **19** 项（AHK 语料 109） | **16** 项（语料 103） |
| C1b 同名重复 | **7** 个 basename（14 个文件） | **1** 个 |
| C1c 代码在非代码目录 | **4** 项（全在 `docs/review/2026-08-20/fix-plan/workspace-snapshot/`） | **0** 项 |
| C2 测试未接入执行 | **10** 项（tests/ 语料 23，可达 13） | **8** 项（语料 22，可达 14） |
| C3 文档-代码不一致 | **0** 项（**不做棘轮，必须恒 0**） | **0** 项 |
| C3b 文档硬写基线数字 | ——（阶段 0 未设此检） | **3** 项（棘轮登记，见下） |
| 覆盖率（纯逻辑 crate · 行） | ——（无阈值、非阻断） | **81.64%** 整体 + 15 个文件逐文件基线，**棘轮只阻下降**（G3f，TD-006） |

> 上表 C1a/C1b/C1c/C2/C3b 五行由 `scripts/check-tech-debt.py` 产出，基线在
> `.review-analysis/tech-debt-baseline.json`。这些是**棘轮**（存量债白名单，只阻新增），
> 收紧水位 = 清理后重跑 `--update-baseline`。
>
> C3b 的 3 项全部落在**带日期的历史报告**里（`2026-09-13` 的两份 review 报告写 616/616、
> `key-latency-benchmark-2026-09-13.md` 写 642/642）。这些是当日实测快照，本身没错，
> **改它反而是篡改历史**，故只登记豁免；闸门阻的是「以后再硬写一个新数字」。

---

## 债项清单

| ID | 类别 | 描述与证据 | I | P | V | S | C | R | DPI | 档 | 状态 | 阶段 |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|:--:|---|---|
| TD-001 | B 重复逻辑 | `docs/review/2026-08-20/fix-plan/workspace-snapshot/` 把 5 个生产 AHK 文件快照进 docs（97K，含 `main.ahk`/`backup_core.ahk`/`migration_logger.ahk`/`run_all_tests.ahk`）。会随生产代码改动而静默陈旧 | 2 | 4 | 4 | 2 | 0.5 | 1.0 | **17.0** | P0 | **已完成**（2026-09-16：4 个 .ahk 已移除，替换为 `README.md` 说明与 `git show 5e97fab:...` 取回路径；C1c 4→0） | 1 |
| TD-002 | A 坏味道 / D 缺失测试 | `tests/test_joystick.ahk` 存在但 `tests/run_all_tests.ahk` 只注册了 `test_ahk_executor/test_joystick.ahk`。要么死文件，要么**测试从未被执行** | 3 | 2 | 5 | 3 | 0.5 | 1.0 | **18.4** | P0 | **已完成**（2026-09-16：经查两者**不是同一个类**——那边测 executor 的 `Joystick`，这边测 domain 的 `JoystickInput`（`main.ahk:42` 仍 include）。故改名 `test_joystick_input.ahk` + 转 AutoHotUnit 套件接入 run_all_tests，33 条断言首次真正执行，并**当场暴露出生产 BUG → TD-017**） | 1 |
| TD-003 | A 坏味道 | 根 `ui_manager.ahk` 无任何 `#Include` 指向它（全部指向 `presentation/ui_manager.ahk`）→ 迁移遗留死代码 | 1 | 1 | 5 | 1 | 0.5 | 1.0 | **11.3** | P0 | **已完成**（2026-09-16：已删除。它与真身**同名 `class UIManager`**，删后全局唯一；独立佐证见 `docs/module-adjacency.md` §4.3 重名警告；C1b 7→6） | 1 |
| TD-004 | B 重复逻辑 | `tools/ahk-bench/_harness.ahk` 与 `tools/ahk-probes/_harness.ahk` 两份 harness。⚠️ 合并时注意 AHK v2 **同名函数重复定义会报错**（现 `bench_prod_tick.ahk` 已在本地定义 `RefBatch`/`MeasureRef`，正是为此） | 2 | 3 | 4 | 2 | 1 | 1.4 | **7.9** | P1 | **已完成**（2026-09-16：抽出 `tools/_ahk_common.ahk` 承载**纯计算原语**（QPC 时钟 / 快排 / 分位数 / mean·max·min），两份 `_harness.ahk` 只保留各自**与输出约定绑定**的部分。⚠️ 合并前实测发现两份 `Pct` **语义不同** —— bench 版要求入参已升序、probes 版内部自排序；**同名不同义才是这笔债真正的成本，行数是次要的**。现统一为「`Pct` 只做索引，排序显式写成 `SortNums`」，probes 侧保留 `_Pct` 薄包装（内部先排）以免动 11 个探针脚本；**22 个 `bench_*/p*_*.ahk` 调用脚本零改动**。刻意**不**统一输出目录 / CSV 编码 / 哨兵语义：两侧本就不同（bench 取 `AHK_BENCH_OUT` + UTF-8 + append；probes 固定 `%TEMP%\ahkprobe` + UTF-8-RAW + 哨兵写耗时），统一会动到已有有效基线的基准。验证：① 等价性对照 **5162 断言**（n=0/1/2/…/101，且刻意混入大量重复值以压测快排分区）新实现与改动前逐字副本**逐位一致**；② 阳性对照注入「忘记排序」→ **323 处 MISMATCH**；③ 门禁基准 prod_escape（0.98~1.14×）/ prod_tick（1.03~1.08×）全部 PASS） | 2 |
| TD-005 | D 缺失测试 | JS **零单测、零 lint、零覆盖率**（`package.json` 无 test/lint 脚本，无 eslint 配置）；23 个 js + 23 个 html | 4 | 3 | 2 | 3 | 5 | 1.4 | **3.8** | P2 | 待排期 | 3 |
| TD-006 | D 门禁缺失 | coverage job 只上传 lcov，**无阈值且非阻断** → 覆盖率事实上无门禁（**当前基线 81.64%，逐文件数字见 `test-map.md`「覆盖率」节**） | 4 | 3 | 4 | 4 | 1 | 1.0 | **15.0** | P0 | **已完成**（2026-09-16：新增 `scripts/check-coverage.py` 做**棘轮**门禁，CI 的 coverage job 由 `continue-on-error` + 仅 push 改为**阻断**。整体容差 0.5pp、单文件 2.0pp，双阈值防「总体稀释」与「丢车保帅」；新文件只登记不判。**刻意不设「≥80%」这类凭空目标** —— 那只会逼出无断言的刷数测试，污染指标本身。阳性对照 4 组：① 单文件腰斩 → 整体+单文件双报 FAIL；② 小文件 100%→25% 而整体仅跌 0.47pp → **只有单文件阈值抓得住**（这条正是双阈值的存在理由）；③ 容差内波动 → PASS 不误报；④ **端到端**：真删掉 `group_service_tests.rs`（212 行）→ 整体 −2.43pp、该文件 −39.95pp，EXIT=1，还原后回绿） | 2 |
| TD-007 | D 缺失测试 | 覆盖率只覆盖 3 个纯逻辑 crate；`src-tauri` 主 crate（Linux 不可编译）、AHK、JS 均无覆盖率 | 4 | 3 | 2 | 3 | 5 | 1.4 | **3.8** | P2 | 待排期 | 3 |
| TD-008 | A/E 架构 | `src-tauri/src/application/`、`src-tauri/src/domain/` 为空历史占位（`AGENTS.md` 禁止加代码），易被误当作可放置目录 | 1 | 1 | 3 | 3 | 1 | 1.0 | **8.0** | P1 | 待排期 | 4 |
| TD-009 | E 架构脆弱 | 3 处 crate 依赖违规（均为 `asd-test-harness`，在 `ALLOWED_CRATE_DEPS` 白名单内），豁免**未写理由与到期日** | 2 | 2 | 4 | 2 | 3 | 1.4 | **4.3** | P2 | 待排期 | 4 |
| TD-010 | E 架构 / 体积 | `AutoHotkey-2.0.26/` 221 文件 / 7.9M vendored 引擎源码入库。**权衡项**：是只读研究参考（`docs/research/ahk-engine-architecture-2026-09-14.md` 依赖它），倾向改 submodule/获取脚本**而非删除** | 3 | 2 | 3 | 2 | 2 | 1.4 | **5.1** | P1 | 待排期 | 4 |
| TD-011 | F 文档漂移 | `test-map.md` 记 `prod_escape` K=2.0，实际已是 1.5（K 值改了但文档未同步）→ 会让人按错阈值判断误报 | 2 | 4 | 5 | 4 | 0.5 | 1.0 | **21.2** | P0 | ✅ **已完成**（2026-09-16） | 1 |
| TD-012 | 静态分析 | 无 `clippy.toml`、无 `#![deny(warnings)]`、无 eslint → lint 只跑默认档，坏味道拦不住 | 3 | 2 | 4 | 3 | 2 | 1.0 | **8.5** | P1 | **已完成**（2026-09-16：① 4 个纯逻辑 crate 开 `clippy::pedantic`（`[lints] workspace = true`），从 248 项收干到 0 —— 其中 146 项文档类（doc_markdown / must_use_candidate）由 clippy 自动修，30 项逐个人工处理（2 处超长函数就地豁免 → TD-023）；`src-tauri` **不开**：587 项里 476 项是 Tauri 样板的文档噪声，开了等于把真信号淹掉；② 新增 `asd-tauri/clippy.toml`（只放阈值，启停一律在根 Cargo.toml 的 `[workspace.lints]`）；③ 前端新增 ESLint 9 flat config + `npm run lint`（棘轮 70，CI 独立 job `js-lint`）。**收紧的第一个回报**：`#[must_use]` 立刻报出 `benches/benchmarks.rs` 丢弃了 `validate()` 的返回值 —— 那是纯函数，优化器会把整段调用删掉，该基准可能一直在测空转，已改 `black_box`。阳性对照 4 组，见 developer-guide §4.6.6） | 2 |
| TD-013 | A/B 重复 | `tests/legacy/json.ahk` 1469 行 legacy JSON 实现，`run_all_tests.ahk` 未引用；仅被历史 review 报告提及 | 2 | 2 | 4 | 2 | 1 | 1.4 | **7.1** | P1 | **已完成**（2026-09-16 删除。定性为 **v1.0 单体实现的历史快照**：① 0 个 `#Include` 引用、0 个 `Test_` 函数 —— 它躺在 `tests/` 下但**根本不是测试**；② 6 个类（`JSONErrorType`/`JSONError`/`JSONLogger`/`JSONParser`/`JSONSerializer`/`ConfigValidator`）与 `infrastructure/` **完全重名**，谁误 include 谁就吃「重复定义」报错；③ `ConfigValidator` 方法集被 infra 版**严格超集**（legacy 9 个里 7 个同名、2 个被重命名取代，infra 多出 13 个新方法）。恢复：`git show 23ede7b:tests/legacy/json.ahk`） | 1 |
| TD-014 | C 过时依赖 | 无 dependabot / renovate；CI 无 `cargo audit` / `npm audit`；依赖版本无跟踪与更新机制 | 3 | 4 | 3 | 2 | 1 | 1.0 | **12.0** | P0 | **已完成**（2026-09-16：① 新增 `.github/dependabot.yml`，覆盖 cargo / npm×2 / github-actions，每周一 03:00（Asia/Shanghai）、每类最多 5 个 PR —— 放任它一次开 20 个 PR 的结果是全部被无视；② CI 新增 `security-audit` job：**npm 生产依赖阻断**（实测前端与 E2E 生产依赖均 0 漏洞）、**dev 依赖只报告不阻断**（E2E dev 有 28 项，不进交付物且 `npm audit fix` 常需 breaking change，一刀切只会逼出「关掉这个 job」→ 另立 TD-020）；`cargo audit` 阻断。⚠️ 本机因网络无法拉取 RustSec advisory-db，cargo audit 的**结果以 CI 首轮为准**，若首轮红则按需加 allowlist 或升级） | 2 |
| TD-015 | F 文档缺失 | `docs/refactor/plan-C-deep.md` 的 M11 验收目标「启动降 ≥15ms」**已被 T13 证伪**（生产唯一 `#Include` 文件仅 5 个，边际 673~825µs/文件 → 收益上界 2.7~4.1ms）。留着会误导后续投入 | 2 | 3 | 4 | 4 | 0.5 | 1.0 | **18.4** | P0（硬性升档：误导性文档） | **已完成**（2026-09-16：M11 目标撤销，T13 由 P2 性能项降级为「纯整洁性可选动作」。`plan-C-deep.md` 共订正 12 处 —— M11 行加删除线并附撤销说明、T13 状态/前置条件/风险点、M0/M7/M8 阶段表、§5.5 压测判据、§6.1 告警、§6.2 回滚触发、§6.3 回滚步骤、§6.4 评审人。启动守卫降级为「不劣化：不高于基线 +5%」） | 1 |
| TD-016 | D 门禁缺失 | E2E 9 suite / 53 用例在 CI **默认关闭**（仅手动触发，需 WebView2 + tauri-driver + msedgedriver）→ 端到端链路零覆盖 | 4 | 3 | 2 | 3 | 5 | 1.4 | **3.8** | P2 | 待排期 | 3 |
| TD-017 | **E 生产 BUG**（由 TD-002 暴露） | `JoystickInput.PovToDirection` 把 centi-degree（0~35900）误除 100 后再与 4500/13500/22500/31500 阈值比较 → **任何方向都返回 `"UP"`**。`joy_hotkey_manager._PollPov` 依赖它，故 POV 十字键热键**首次移动后永不触发** | 4 | 3 | 5 | 4 | 0.5 | 1.0 | **22.6** | P0 | **已修复**（2026-09-16：去掉 `/100`。修复前 3 条新用例红、修复后 697 全绿——这本身就是缺陷的阳性对照） | 1 |

| TD-018 | F 文档缺失 / 误导 | 方案 A/B/C 与 `refactor/README.md` 共 **8 处**把 AHK 回归基线硬写成 `642 / 642`，而实跑总数早已是 697。「通过数 / 总数」这种写法把同一个数字硬编码两遍，**测试一增长就必然过期**，且过期后无人发现 —— 它在文档里，不在代码里，没有任何检查会碰它 | 3 | 3 | 4 | 2 | 0.5 | 1.0 | **17.0** | P1 | **已完成**（2026-09-16：7 处改为「指向 test-map.md 的指针」；剩下 1 处在 `key-latency-benchmark-2026-09-13.md`，是**当日实测快照**，改它等于篡改历史，故保留数字 + 加注说明。同时新增 **C3b 自动检查**：扫 `docs/` 下的 `N / N` 形态，与 test-map 的实跑总数不符即报；走棘轮，历史快照登记豁免，只阻新增。阳性对照 3 组：注入 `123 / 123` → 变红；改为等于权威值 697 → 不检出；破坏权威数字提取 → 硬失败） | 1 |
| TD-019 | B 重复 / 配置漂移 | `asd-tauri/src-tauri/Cargo.lock` 是**冗余**的：`src-tauri` 是根 workspace 的 member（其 `Cargo.toml` 无 `[workspace]`），不该有自己的 lock。两个 lock 并存可能解析出不同依赖版本 | 2 | 3 | 2 | 2 | 1 | 1.4 | **6.4** | P1 | 待排期（2026-09-16 由 TD-014 摸依赖结构时发现。删前须确认没有流程 `cd src-tauri && cargo ...`） | 2 |
| TD-020 | D 门禁缺失 | E2E 的 **dev 依赖有 28 项漏洞**（6 low / 3 moderate / 19 high），前端 dev 另有 3 项 high（vite）。生产依赖均为 0 | 2 | 3 | 3 | 2 | 3 | 1.4 | **4.1** | P2 | 待排期（2026-09-16 由 TD-014 审计发现。不进交付物故未阻断，但 `npm audit fix` 需评估 breaking change） | 3 |
| TD-021 | F 文档缺失 | `missing_errors_doc` / `missing_panics_doc` 两条 lint **有意暂缓**：纯逻辑 crate 有 59 个公开函数缺 `# Errors` / `# Panics` 小节；`src-tauri` 另有同类文档债 476 项（与 `doc_markdown` 合并统计）。属文档工程，与「静态分析收紧」分开做 | 2 | 2 | 3 | 1 | 3 | 1.0 | **4.6** | P2 | 待排期（2026-09-16 由 TD-012 度量得出。已在根 `Cargo.toml` 显式 `allow` 并注明原因，不是漏网） | 3 |
| TD-022 | A 代码坏味道 | 前端 ESLint 存量 **70** 项（no-redeclare 42 / no-unused-vars 18 / no-empty 6 / no-prototype-builtins 4），全部是 var 时代的**风格债不是缺陷**。`main.js` 约 1350 行且**零测试覆盖**，批量改名/删变量的收益小于风险 | 2 | 3 | 2 | 2 | 3 | 1.4 | **3.7** | P2 | 待排期（2026-09-16 由 TD-012 引入 ESLint 时发现。已用 `--max-warnings 70` 棘轮钉住：新增即红，修一处减一） | 3 |
| TD-023 | A 代码坏味道 | 两个函数超过 `too_many_lines` 阈值：`validator.rs::validate_mode_data` **294 行**、`group_service.rs::register_hotkey` **104 行**。前者是「按 mode 分派的子校验器集合」，切分要先把每个 mode 的子校验抽成函数并对齐错误文案 | 3 | 3 | 3 | 3 | 5 | 1.4 | **3.8** | P2 | 待排期（2026-09-16 由 TD-012 度量得出。已就地 `#[allow]` 并注明原因，**未上调阈值** —— 上调等于宣布「这么长是合理的」） | 3 |
| TD-024 | D 门禁缺失 | 覆盖率基线**只存百分比不存行数** → 统计口径漂移时完全看不出来。实测：同一份代码换一条 `llvm-cov` 命令后 `validator.rs` 统计行数 2367→1856（-21.6%），命中数几乎不变，整体「涨」7pp —— 棘轮在拿两个不可比的数字互相比 | 2 | 2 | 3 | 2 | 1 | 1.0 | **9.0** | P1 | **已完成**（2026-09-16：基线改为存每个文件的 `lines`/`hits` 作为口径指纹，新增判定「单文件行数变化 >10% 且 ≥20 行 → FAIL」；同时按 CI 命令重取基线 81.64%→88.65%，并在 test-map 注明**这是量程变化不是覆盖率提升**。阳性对照：砍 30% → FAIL；砍 1.6% → PASS） | 2 |

**统计**：P0 **8** 项（**全部完成**）｜P1 **8** 项（其中 5 项已完成）｜P2 **8** 项｜合计 **24** 项。

> P0 已于 2026-09-16 清零。剩余 12 项集中在「测试补齐」（P2）与「架构收敛/门禁加固」（P1），
> 均不阻塞交付，按阶段 2→4 顺序推进。

> **TD-017 的意义**：它不是一个「债」，而是**把从未执行的测试接入 CI 的直接回报**——
> 那 29 条断言躺了不知多久，第一次跑就抓出一个活跃的功能性 BUG。
> 这也是 C2（测试未接入执行）应当优先于其它清理项的理由。

### 自动检出映射（`scripts/check-tech-debt.py`，阶段 0）

下列债项已能被脚本自动检出 —— 修复后对应计数下降，可据此收紧基线：

| 检 | 覆盖的债项 | 0 号基线 |
|---|---|---|
| C1b 同名重复 | TD-003（根 `ui_manager.ahk`）、TD-002（`tests/test_joystick.ahk`）、TD-004（双 `_harness.ahk`） | 7（**现只剩 1 项**：双 `_harness.ahk` 是**刻意保留**——重复**逻辑**已抽到 `tools/_ahk_common.ahk`，剩下两个同名文件是各守不同输出约定的薄 shim，见 TD-004。C1b 只按 basename 判定，认不出这个区别，所以它会一直绿着；**不要**为了消这一项去合并输出约定） |
| C1c 代码在非代码目录 | TD-001（`docs/**/workspace-snapshot/` 4 个文件） | 4 |
| C2 测试未接入执行 | TD-002、TD-013（`tests/legacy/json.ahk`）+ 8 个独立 runner 未被 `run_all_tests` 覆盖 | 10 |
| C3 文档-代码一致性 | TD-011（K 值漂移，**已修复**；脚本即为防复发手段） | 0 |
| **C3b 文档硬写基线数字** | **TD-018**（**已修复**；`docs/` 下的 `N / N` 与 test-map 实跑总数比对，棘轮只阻新增） | 3 |

C1a/C1b/C1c/C2/C3b 都是**棘轮**：存量债登记进 `.review-analysis/tech-debt-baseline.json`，
只有**基线外的新增项**才让门禁变红。C3 唯一例外，必须恒为 0。

C1a（19 项孤儿）目前**没有**对应已登记债项 —— 其中的 `config.ahk`、`SkillMgrDebugLogger.ahk`、
`_diag/_mock/_rt.ahk`、`test_ob/test_simple/test_val_btn.ahk`、`tools/ahk-bench/lib/seqgen_test.ahk`
需在阶段 1 逐一定性（弃用 / 保留并登记为豁免 / 接入执行）后再开债项，不要凭清单直接删。

---

## 刻意保留项（**不是债，禁止当死代码清理**）

登记在此，防止后续误删。删除前必读。

| 项 | 为什么保留 | 依据 |
|---|---|---|
| `Sender._ExecutePeriodicLegacy` / `_ExecuteHybridLegacy` | T6 的**等价性 oracle**：`bench_prod_tick.ahk` 的 `equiv,tick_onedue_n*,diffs=0` 与 `Test_TickMerge_Periodic_MatchesLegacy` 都靠它比对 | `sender.ahk:82`；`.workbuddy-ai/memory/2026-09-15.md` |
| `JSONSerializer._EscapeStringCharByChar` | T1 的**等价性 oracle**：`JSONSerializerEscapeTests` 逐字符扫描 + `bench_prod_escape` 的 `equiv,ascii_scan,diffs=0` | `infrastructure/json_serializer.ahk` |
| `AutoHotkey-2.0.26/source` | AHK 引擎源码，**只读**（不修改/不 fork/不编译），研究可复现性依赖它；图谱分析已排除（`EXCLUDE_DIRS`） | `MEMORY.md`、`docs/graph-driven-workflow.md:108` |
| `src-tauri/src/application/`、`domain/` 空目录 | 历史占位，`AGENTS.md` 明确禁止加代码（Rust 侧逻辑在 `crates/`） | `AGENTS.md` |
| `asd-test-harness` 的 3 处 crate 违规 | 测试辅助 crate，已白名单 | `ALLOWED_CRATE_DEPS` |

---

## 待定项（缺外部信息，无法定优先级）

| 项 | 缺什么 | 影响 |
|---|---|---|
| joystick / vJoy 是否主力功能 | 产品定位 | 决定「joystick 方案 B（`SleepUntilUs` 忙等）」值不值得做（代价：连续占用 AHK 主线程 ~8~28ms/次） |
| 是否有产品级性能 SLO | 产品输入 | 现有全部阈值（IPC P50 1.2ms、定刻 20ms、基准 K）均为**实测反推**，无产品侧依据 |
| 是否有产品路线图 | 优先级来源 | 决定 41 人天的技术债清理与功能需求的排序 |

---

## 状态流转

```
待评估 → 已排期 → 进行中 → 已完成
                 ↘ 豁免（理由 + 到期日）
                 ↘ 待定（缺外部信息）
```
每月复盘：重算 DPI、复审豁免到期项、更新「基线快照」列。
