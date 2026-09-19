# 测试体系与质量门禁生产就绪度评估 —— ASD 技能管理器 v4.0

> 评估人：泰莎（Tessa）· 测试专家
> 日期：2026-09-19　｜　仓库：`D:\1demo\AutoHotkeydemo`（主 worktree，分支 `main`，HEAD `4f05b7a`）
> 范围：**仅测试维度**（门禁有效性 / 覆盖率水位 / 测试判别力 / E2E 与发布验证）
> 判据纪律：**本文件所有"实测"结论均来自本机阳性对照或本机实跑，凡推断均显式标注「推断」**。
> 实测时间窗：2026-09-19 约 18:25–18:55（本机 Windows / Git Bash / rustc 1.95.0）。

---

## 1. 本域结论

**评级：接近生产级（单元测试维度）／不达标（端到端与发布验证维度）**

**"今天发布的把握度"一句话评级：**
> **C+（中等偏低）** —— 「改坏了核心逻辑会不会被拦住」这件事我给 **A-**（666 条 Rust 用例 + 91.82% 纯逻辑覆盖率 + 闸门阳性对照全数变红且点名）；
> 「装到用户机器上能不能起来、能不能跑通一个连招」这件事我给 **D** —— 启动装配路径（`src-tauri/src/lib.rs` 行覆盖 **22.84%**）没有一条自动化用例，53 条 E2E 在 CI 上 **零执行**，发布产物 **无任何冒烟**，`release` job **从未跑过**。
> 也就是说：**代码层面的回归我有把握，安装层面的"打不开"我没有任何自动化把握。**

拆分判据：

| 子维度 | 评级 | 一句话依据 |
|---|---|---|
| 单元测试充分性 | **A-** | 666 条 Rust 运行时注册用例 + 48 条 JS + AHK 722（本机口径），三口径覆盖率 91.82 / 69.98 / 83.98% |
| 闸门真实有效性 | **B+** | 7 道可自动化闸门 **全部实测阳性对照变红且点名**；但 G4 结构上不可能红、G3h 空转、G3f 不在本地闸门内 |
| CI 阻断性 | **C+** | 10 个 job 里 **4 个真阻断**、3 个 `continue-on-error` 永不阻断、E2E/release 结构性不可达；ahk-bench 自称门禁却在 PR 上不跑 |
| 测试判别力 | **A-** | 有成熟阳性对照文化（文档记录 ≥20 组变异对照）；本轮独立复现 2 组变异均变红；仅发现 4 条零断言用例 |
| 覆盖率口径治理 | **C** | 三口径数字已分列，但 **对外主引用的 89.05% 已过期 2.77pp**，`src-tauri` 归属仍悬而未决（T1） |
| E2E / 发布验证 | **D** | E2E 结构性不可达（零执行）；release 从未执行且无冒烟 |

---

## 2. 门禁阳性对照结果表

> 方法：改一个文件制造违规 → 跑闸门 → 确认红 → **立刻还原** → 复跑确认绿。
> ⚠️ G3f 的两组对照用 `--baseline <副本>` / lcov 副本完成（脚本原生支持），**未触碰真基线** `.review-analysis/coverage-baseline.json`，故"还原"一栏标 N/A。
> 全部为本机实测。

| 闸门 | 注入的违规 | 是否变红 | 报错是否点名 | 已还原并复跑回绿 |
|---|---|:---:|:---:|:---:|
| **G1** 图谱基线 | `asd-tauri/src/api.js` 加一行 `import * as __pc_cycle from './main.js'`（与 main.js→api.js 构成 2-环） | ✅ 红（rc=1） | ✅ `js_cycles: 0 -> 1（增加 1）` + 明细 `[["asd-tauri/src/api.js","asd-tauri/src/main.js"]]` | ✅ 已还原，`git status` 干净，复跑 `[PASS]` |
| **G3f-1** 覆盖率棘轮（整体） | 基线副本 `global_lines_pct` 89.05 → 95.00 | ✅ 红（rc=1） | ✅ `整体行覆盖率 91.82% 低于基线 95.00%（跌 3.18pp > 容差 0.5pp）` | N/A（副本，真基线未动） |
| **G3f-2** 覆盖率棘轮（单文件/范围锚点） | 从 lcov 副本删掉 `asd-domain/src/validator.rs` 一条记录（15→14 文件） | ✅ 红（rc=1） | ✅ 三条并列且点名：`validator.rs 在基线里但本次 lcov 没有` + `语料范围缩小：本次 14 < 下限 15` + `整体 88.28% 低于 89.05%` | N/A（副本） |
| **G3g-1** AHK 独立脚本（失败） | `tests/test_key_validator.ahk` 末尾注入 `TestReporter.Assert(1 = 2, ...)` | ✅ 红（rc=1） | ✅ `✗ tests/test_key_validator.ahk（exit=1）` + `失败清单: tests/test_key_validator.ahk` | ✅ 已还原（`git status` 无改动），复跑 `✓ 通过 1 / 失败 0` |
| **G3g-2** AHK 独立脚本（**假绿防护**） | 同文件注入 `ExitApp(0)` 早退（退出码 0、一条断言都不跑） | ✅ 红（rc=1） | ✅ `假绿：exit=0 但既无 stdout 也无新鲜产物——脚本很可能中途静默终止，一条断言都没跑` | ✅ 已还原，复跑绿 |
| **G3d-1** test-map 自洽（文档内部） | `test-map.md` 里 `crates/asd-domain/src/config.rs` 测试数 `35 → 36` | ✅ 红（rc=1） | ✅ `[asd-domain] **小计** 声明 161，实际明细之和 162` | ✅ 已还原，复跑 `[PASS]` |
| **G3d-2** test-map 自洽（**运行时对账分支**） | 「自洽校验」行 `161 → 162`（不动表格，专测 B 分支） | ✅ 红（rc=1） | ✅ `DIFF asd-domain 登记 162 / 实际 161` + `asd-domain: 登记 162，运行时实际 161` | ✅ 已还原，复跑 `[PASS]` |
| **G3e** 技术债度量（C12 安全红线） | `asd-tauri/src-tauri/tauri.conf.json` 注入 `_tessa_pc_debug_port: "--remote-debugging-port=9333"` | ✅ 红（rc=1） | ✅ `正式 tauri.conf.json 出现 --remote-debugging-port 1 处（会进 release 产物，安全红线）（C12）` | ✅ 已按字节还原（用 `cp` 备份还原，diff 0 行），复跑 `[PASS]` |
| **G3i** build_graph 自检 | **本轮未做注入**（需改 `.review-analysis/build_graph.py` 的期望表） | —（本轮未做） | — | — |
| **G4** 文档同步 | **结构上无法注入** —— 见 §2.1 | ❌ **不可能红** | — | — |
| （附加）变异对照 · Rust | `crates/asd-application/src/time_format.rs` 的 `%Y%m%d_%H%M%S` → `%Y%m%d-%H%M%S` | ✅ 红（rc=101） | ✅ `assertion left == right failed / left: Some('-') / right: Some('_')`，2 条用例红 | ✅ 已还原（diff 0 行），复跑 4/4 绿 |
| （附加）变异对照 · 前端 | `asd-tauri/src/main.js` 的 `refreshDiagnostics` 改名 | ✅ 红（rc=1） | ✅ `HTML 里每个 data-action 都在 main.js 有对应分支` / `诊断页的两个 action 已接线` 2 条红 | ✅ 已还原（diff 0 行），复跑 9/9 绿 |

**结论：7 道可自动化闸门，实测 7 道全部会红、且报错都能点名到具体文件/字段。** 这是本项目本轮最硬的一条正面证据 —— 与 TD-058 担心的"看起来在守其实从来没红过"相反，`check-gates.sh` 里的自动闸门是真闸门。

### 2.1 G4 的实际执行方式（为什么它不可能红）

- 本地：`scripts/check-gates.sh:217-230` 是 `cat <<'CHECKLIST'` —— **打印 6 行待办文字后继续往下走**，不读取任何文件、不退出非零。
- CI：`.github/workflows/ci.yml:272-282` 是 6 行 `Write-Host` —— 同样是打印。
- 因此 G4 在两端都**永远返回 0**，无论文档是否同步。

**它实际的执行方式 = 纯人工自觉**：没有任何产物、没有签字留痕、没有 PR 模板勾选项、没有 CODEOWNERS 约束（**推断**：未找到 PR 模板或 CODEOWNERS，本轮未穷尽搜索）。
**建议**：要么把它降级为"提示"并从"四闸门"的编号里摘出去（避免它被当成第 4 道防线计入把握度），要么把它可自动化的 3 项（test-map 数字 → 已由 G3d 兜、ALLOWED_CRATE_DEPS → 已由 G1 兜、baseline 收紧 → 可由 G3e/G3f 兜）合并进已有闸门，剩下 2 项明确写"人工负责、无自动化"。

---

## 3. CI job 阻断性表

读 `.github/workflows/ci.yml` 的 job 级 `if:` / `needs:` / `continue-on-error:` 得出（行号为该文件行号）。

| job | 行号 | 是否阻断合并 | 依据（行号） | 是否曾真正执行 |
|---|:---:|:---:|---|---|
| `gates`（四闸门） | 73 | ✅ **是** | 无 job 级 `if`、无 `continue-on-error` | ✅ 每次 push / PR 都跑 |
| `js-lint` | 286 | ✅ **是** | 无 `if` / 无 `continue-on-error`；`npm run lint` 水位 0（注释 297-299） | ✅ 每次都跑 |
| `coverage`（含 G3f） | 305 | ✅ **是** | 308-312 注释声明 TD-006 起由 `continue-on-error` 改为阻断；job 上无 `continue-on-error` | ✅ 每次都跑（ubuntu） |
| `security-audit` | 344 | ✅ **是**（生产依赖）／❌ dev 依赖不阻断 | 371 `continue-on-error: true` 只作用在"dev 依赖仅报告"那一步 | ✅ 每次都跑 |
| `miri` | 392 | ❌ **否** | 395 `continue-on-error: true` | ✅ 跑，但红了也不管 |
| `fuzz` | 412 | ❌ **否**（且几乎不跑） | 415 `continue-on-error: true` + 416 `if: github.event_name == 'schedule'` | ⚠️ 仅每周日 0 点 UTC 定时 |
| `bench`（Rust criterion） | 441 | ❌ **否** | 446 `continue-on-error: true` + 447 `if: push && main` | ✅ push 到 main 时跑 |
| `ahk-bench`（T11） | 483 | ⚠️ **名义阻断，但 PR 阶段不跑** | 无 `continue-on-error`；但 494-496 `if: (push && main) \|\| (dispatch && update_baseline)` | ✅ push 到 main 时跑；❌ **PR 上零执行** |
| `e2e` | 566 | ❌ **否** | 568 `if: dispatch && inputs.run_e2e`；`run_e2e` 默认 `false`（30-33）；无 `needs` 指向它 | ❌ **CI 上零执行**（TD-061 / TD-062） |
| `release` | 786 | —（不参与合并判定） | 792 `needs: gates` + 794 `if: dispatch && inputs.build_release`（默认 false） | ❌ **从未执行**（TD-074） |
| `gates` 内的 **G3h** 步骤 | 166 | ❌ **否**（双重） | 170 `continue-on-error: true`；且**实测该步骤执行 0 个用例**（见 §5 发现 #5） | ⚠️ 空转 |

**三条最关键的推断（影响"阻断"这件事成立与否）：**

1. **"阻断"的前提是分支保护把这些 job 设为 required checks。** 本轮 `gh` 未登录（`gh auth status` → not logged in），匿名 `curl` 分支保护 API 返回 401，故**无法实测确认**。仓库为 public（`private: False`，实测）。**若 `main` 未配置 required status checks，则上表所有"✅ 是"都只是"job 会红"，而不是"合并不了"。** 这是本轮唯一一条我明确标**推断**的阻断性结论，建议团队用一次 `gh api .../branches/main/protection` 补齐判据。
2. **`coverage` job 是本轮唯一覆盖"覆盖率下降"的阻断防线，且它只跑 3 个纯逻辑 crate**（CI 命令 `--package asd-domain --package asd-ipc-protocol --package asd-application`，ci.yml:330）。`src-tauri`（代码量最大、覆盖率最低 69.98%）**没有任何覆盖率门禁**。
3. **`ahk-bench` 的"门禁"身份与它的触发条件不匹配**（发现 #2）：PR 阶段不跑 ⇒ 性能回归会先合并、再在 main 上红；而 main 红了以后唯一的修法是再发一个 PR，形成"红了→修→又只能在合并后才知道修没修好"的环路。

---

## 4. 覆盖率真实水位（三口径，本机重取 2026-09-19）

**测量命令（与 CI 的 coverage job 同一条，仅平台不同）：**

```bash
cd asd-tauri
# ① 三个纯逻辑 crate
CARGO_INCREMENTAL=0 cargo llvm-cov --package asd-domain --package asd-ipc-protocol \
    --package asd-application --lcov --output-path coverage/lcov.info --summary-only
# ② src-tauri
CARGO_INCREMENTAL=0 cargo llvm-cov --package asd-tauri --summary-only
# ③ 全仓 workspace
CARGO_INCREMENTAL=0 cargo llvm-cov --workspace --summary-only
```

| # | 口径 | 行覆盖率 | 分母/命中 | 重取时间 | 文档现值 | 偏差 |
|:---:|---|:---:|---|:---:|:---:|---|
| ① | **3 个纯逻辑 crate**（asd-domain / asd-ipc-protocol / asd-application，= G3f 棘轮范围） | **91.82%** | 6259 行 / 命中 5747（15 文件） | 本机 2026-09-19 18:29 | 89.05%（test-map.md + 基线 JSON） | **+2.77pp（文档已过期）** |
| ② | **`src-tauri`**（Tauri 主 crate） | **69.98%** | 4001 行 / 未覆盖 1201 | 本机 2026-09-19 18:37 | 69.90%（团队既有锚点） | +0.08pp |
| ③ | **全仓 workspace**（5 crate） | **83.98%** | 10469 行 / 未覆盖 1677 | 本机 2026-09-19 18:37 | 84.00%（团队既有锚点） | −0.02pp |

**口径说明（引用时必须连本段一起引用）**：三者分母不同、不可互相换算、更不可互相"纠正"。① 是**门禁口径**（G3f 唯一守住的数字）；② 是**风险口径**（代码量最大 + 覆盖最低）；③ 是**宣传口径**（最容易被误当成"项目覆盖率"）。此外三者分母都含 `#[cfg(test)]` 测试代码（TD-026 豁免不修），跨文件百分比不可横向排名。

**① 口径下的最低 5 个文件（本机实测，`--show` 输出）：**

| 文件 | 行覆盖率 | 备注 |
|---|:---:|---|
| asd-application/src/recording_service.rs | 67.28% | 分母是纯生产代码（无内联测试） |
| asd-application/src/group_service.rs | 70.96% | 同上，较基线 63.22% **+7.74pp** |
| asd-application/src/backup_service.rs | 78.31% | |
| asd-domain/src/models.rs | 86.62% | |
| asd-application/src/state.rs | 89.17% | |

**② 口径下的重点（本机实测）：**

| 文件 | 行覆盖率 | 未覆盖行 |
|---|:---:|:---:|
| `src-tauri/src/lib.rs` | **22.84%** | 517 / 670 |
| `src-tauri/src/infrastructure/logging.rs` | 33.90% | 39 / 59 |
| `src-tauri/src/main.rs` | 0.00% | 3 / 3 |
| `src-tauri/src/commands/system_cmd.rs` | 68.64% | 53 / 169 |
| `src-tauri/src/commands/hotkey_cmd.rs` | 75.71% | 17 / 70 |
| `src-tauri/src/bridge.rs` | 75.54% | 34 / 139 |
| `src-tauri/src/infrastructure/ipc.rs` | 80.17% | 191 / 963 |
| `src-tauri/src/infrastructure/watchdog.rs` | 84.87% | 148 / 978 |

> **`src-tauri/src/lib.rs` 22.84% 是本评估里最刺眼的一个数字。** 那是 Tauri app 的装配与 `run()` 入口 —— 也就是"用户双击图标之后最先执行的那段代码"。它没有任何自动化用例，唯一能覆盖它的 E2E 又不在 CI 上跑。

### 4.1 测试数字与代码是否一致（B2）

`scripts/check-test-map.py` 全量（含运行时对账）本机实测输出：

```
[A] 文档内部自洽：通过
[D] AHK 两维口径：通过
[B] 运行时对账：
     OK  asd-domain         登记  161 / 实际  161
     OK  asd-ipc-protocol   登记   72 / 实际   72
     OK  asd-application    登记  173 / 实际  173
     OK  asd-test-harness   登记    3 / 实际    3
     OK  asd-tauri          登记  257 / 实际  257
[D5] Rust 明细行（按文件）：通过
[C] 汇总行：登记 666 / 实际 666
[PASS]
```

**结论：test-map.md 的 Rust 数字与运行时注册数完全一致（666/666），未发现漂移。** 另：`cargo test --workspace` 本机实测**全绿、0 ignored**（含 `src-tauri` 256 条 13.12s）；前端 `node --test` 实测 **48 tests / 14 suites / 48 pass**（与"48 个用例"锚点一致）。

**未重取的数字（诚实标注）**：AHK 完整套件"722 用例"本轮**未全量重跑**（全量约 4 分钟，本轮只跑了 G3g 单脚本对照）；该数字由 G3d 的 `[D]` 静态口径校验通过，但**未经本轮执行复验**。

---

## 5. 发现清单表

| # | 严重度 | 类别 | 证据 | 问题描述 | 实测/推断 | 建议 |
|:---:|:---:|---|---|---|---|---|
| 1 | **高** | 门禁松弛 | 基线 JSON `global_lines_pct: 89.05`、`generated_at: 2026-09-16`、`totals.lines: 5992`；本机实测 91.82% / 6259 行 | **G3f 覆盖率棘轮基线已过期 2.77pp**（单文件最高 7.74pp：group_service 63.22→70.96）。棘轮因此在有人真正删测试之前有 **3.27pp（2.77 + 0.5 容差）的静默下降额度** —— 这不是"门禁坏了"，是"门禁的锚点停在上周"。 | 实测 | 本轮提交后重跑 `--update-baseline` 收紧水位（并把这件事并入 DoD：补测试 ⇒ 同 CR 必须收紧基线）。顺便核对 CI（ubuntu）实测值是否与本机 91.82% 一致，不一致则按 CI 口径重取 |
| 2 | **高** | 门禁错位 | `ci.yml:494-496` `if: (push && main) \|\| (dispatch && update_baseline)` | **`ahk-bench`（文件注释 484-486 自称"门禁，不是信号…失败会阻断合并"）在 `pull_request` 上根本不跑。** PR 阶段零阻断，性能回归会先合并、再让 main 变红。 | 实测（读配置） | 要么把它加进 PR 触发（接受 shared runner 抖动风险并按注释重设基线），要么把注释里"阻断合并"改成"仅守卫 main"，别让台账继续声称它在守 PR |
| 3 | **高** | 未覆盖高风险路径 | `ci.yml:566-568` + `30-33`（`run_e2e` 默认 false）；`src-tauri/src/lib.rs` 行覆盖 22.84%（本机 llvm-cov） | **启动装配路径无自动化验证。** 53 条 E2E 在 CI 上结构性不可达（零执行），只能在开发者本机手动跑；而 `lib.rs`（app 装配 + `run()`）覆盖仅 22.84%，`main.rs` 0%。"用户装完双击打不开"这类事故没有任何自动化防线。 | 实测（配置 + 覆盖率） | 接受 E2E 上不了 CI（TD-061 已证伪两条通道），但必须：① 把"发版前本机手动跑一遍 `cd asd-tauri/e2e && npm test` 并把结果贴进发布记录"写成发布 DoD；② 把 `lib.rs` 里可抽出的纯装配逻辑（如 builder 配置映射）抽成纯函数补单测 |
| 4 | **高** | 发布验证缺失 | `ci.yml:786-913` release job 全部步骤：checkout → toolchain → cache → node → `npm ci` → AHK → `npm run tauri build` → 收集 exe + SHA256 → 上传 | **发布产物无任何冒烟**：不安装、不启动、不执行一次连招、不校验 AHK 子进程能否拉起。`release` job 从未执行（TD-074，P0）。也就是说"CI 能出包"目前是**未验证假设**（ci.yml:781-785 自己承认"首次执行不保证一次绿"）。 | 实测（读配置） | 发布前：① 手动 dispatch 跑一次 `release` 并人工观察；② 补一条冒烟步骤（装 NSIS → 启动 → `invoke('get_groups')` 或执行一个连招 → 退出码校验），哪怕只在手动 dispatch 下跑 |
| 5 | **中** | 假守护（空转） | 三种独立算法交叉验证（详见 §5.1）：① `grep -rn "#\[ignore" --include=*.rs asd-tauri/` = **9 命中，全部在注释里**；② PowerShell `Select-String -Pattern '#\[ignore'` = **9**；③ 逐行判定行首非注释的真实属性 = **0**；另 `cargo test -p asd-tauri --lib -- --ignored --list` → **`0 tests, 0 benchmarks`** | **CI 的 G3h 步骤（`ci.yml:166-171`）实测执行 0 个用例**（2026-09-19 提交 `721159a` 摘除了 watchdog 的 15 条 `#[ignore]`，但 G3h 与它的注释 159-164 都没跟着改）。叠加 170 行 `continue-on-error: true` ⇒ 这一步既空转又不阻断。 | 实测 | **采纳 Cody 的方案 2 并加牙**：改写为"元门禁"——断言 `cargo test -p asd-tauri --lib -- --ignored --list` 输出为 `0 tests`（**不要**用 grep 判注释里的 `#[ignore]`，会有假的阳性/阴性），并**去掉 `continue-on-error: true`**，否则仍是没有牙的门禁 |
| 5b | **高** | 门禁晋级未留痕 | `ci.yml:164`「连续跑绿 3-5 次后再摘 `#[ignore]` 转硬门禁」；实测真实 `#[ignore]` 属性 **0**（已摘）、15 条已进入**阻塞的** G3a（Cody 实测 `cargo test -p asd-tauri --lib watchdog` = 59 passed；我实测 `cargo test --workspace` 全绿、asd-tauri `--lib` 256 passed / 13.12s）；全仓检索「观测期 / 3-5」40 处命中，**唯一接近的留痕是 `remaining-issues-review-2026-09-18.md:24` 的"本地 15 passed / 13.39s + CI success"——一次本地 + 一次 CI，不是连续 3-5 次** | **晋级动作做了，前置判据没留痕。** 更麻烦的是**两处判据本身不一致**：`ci.yml:159-164` 写的是「连续跑绿 3-5 次」，`watchdog_integration_tests.rs:5-17` 写的依据却是「实测全量仅约 13 秒且 15/15 通过」（"不慢" ≠ "连续绿 N 次"）——晋级按了后者，规定写的是前者。风险实质化：这批用例**真起 `cmd.exe` 子进程、做 PID/taskkill 清理**（`spawn_fake_executor`、`test_terminate_registered_child_kills_it`、`test_cleanup_does_not_kill_unregistered_same_name_process`），共享 runner 上比本机更易抖；一旦抖，**直接把阻塞的 G3a 打红**，不再被 `continue-on-error` 兜住。 | 实测（配置 + 检索）+ 推断（抖动风险未实测复现） | ① 补留痕：连续 3-5 次 CI 绿跑记录；或 ② 暂把该组单独成步并保留 `continue-on-error` 至观测期完成；③ 统一两处判据文字。**与 team-lead 汇总报告 finding #11 同源，已指派 Tessa，P0，0.5 人日** |
| 6 | **中** | 假守护（排除） | `scripts/check-tech-debt.py:286` `PRUNE_DIR_NAMES = {..., "archive"}` + 130-131 显式排除 `tests/archive`；`find tests/archive -name '*.ahk' \| wc -l` = **41**；G3g 清单只收了其中 3 个 | **C2「测试未接入执行」检查把 `archive` 整个目录排除在扫描之外**，于是 `tests/archive/` 下 **38 个 .ahk 从未被执行、且不出现在任何告警里**（TD-079 的同型问题：死代码穿了隐身衣）。`tests/run_tests.ahk` 同理：全仓零引用、永不执行。 | 实测 | 二选一：① 把 `archive/` 整体移出 `tests/`（比如 `_attic/`），让命名与"归档=不跑"的语义一致；② 在 C2 里对 `archive` 单独出一份"仅统计、不阻断"的清单，让死脚本数量可见 |
| 7 | **中** | 门禁不可达 | `scripts/check-gates.sh` 全文：闸门为 G1/G3i/G2a/G2b/G3a/G3b/G3c/G3d/G3e/G3g + G4，**无 G3f** | **覆盖率棘轮不在本地四闸门里。** 开发者本机跑 `check-gates.sh` 全绿，也可能在 CI 上被 G3f 拦下；反过来本机的 `check-gates.sh` 也没有任何一步会告诉开发者"你把覆盖率跑掉了 3pp"。且 G3f 跑在 ubuntu、基线取于 Windows（`ci.yml:332-333` 自己承认平台可能系统性偏离）。 | 实测 | 给 `check-gates.sh` 加 `--with-coverage`（本机生成 lcov 后跑 `check-coverage.py`，仅提示不阻断），至少让"覆盖率掉了"在本地可见；或明确写"覆盖率判定以 CI 为准"并给出取数命令 |
| 8 | **中** | 口径未决 | 本机实测 ② src-tauri 69.98% / ③ 全仓 83.98%；`test-map.md` 已加 banner 标注 89.05% 是"3 个纯逻辑 crate"口径 | **T1（`src-tauri` 是否纳入覆盖率口径）仍未决策。** 现状是：代码量最大、覆盖最低（69.98%）的那个 crate 完全在棘轮之外，只有文档标注。且 89.05% 这个"对外主引用数字"现在已经过期（见 #1）。 | 实测 + 推断（T1 未决为既有事实） | 本轮就决策：若纳入，用 Windows runner 另起一个 coverage job（`src-tauri` 在 Linux 编不过）并单独设基线；若不纳入，把对外材料的默认引用数字改成"① 91.82%（3 个纯逻辑 crate，门禁口径）/ ② 69.98%（src-tauri）/ ③ 83.98%（全仓）"三数字并列，禁止单引 |
| 9 | **低** | 测试判别力 | 括号配平扫描（本机脚本，16 命中）后逐条人工复核 | **4 条"零断言"测试** —— 只要不 panic 就绿，实现改成 no-op 也不会红：<br>· `crates/asd-application/src/state.rs:1195 test_try_send_ipc_command`<br>· `crates/asd-application/src/state.rs:1210 test_try_send_ipc_message`<br>· `src-tauri/src/infrastructure/watchdog.rs:1689 test_cleanup_stale_executor_processes_exists_and_is_safe`<br>· `src-tauri/src/infrastructure/watchdog.rs:1707 test_register_panic_hook_is_idempotent`<br>（其余 12 条为误报：config.rs 的 `assert_roundtrip` 委托断言、watchdog 的 Send+Sync 编译期钉子） | 实测 | 给 `try_send_*` 补一条"调用后内部状态/计数发生变化"的可观测断言；watchdog 两条改为断言可观测副作用（如 hook 数量、清理返回值）。不必为凑数补，但要么有断言要么删 |
| 10 | **低** | 未覆盖高风险路径 | `grep -rn "connect_to_ahk" --include=*.rs` 在测试中全部是 `.expect("连接失败")`（happy path）；存在 `test_create_listener_reports_name_conflict`（`ipc.rs:1616`、`test_wait_response_timeout`） | **IPC"AHK 侧始终起不来"的失败路径未见针对性用例** —— 有管道抢注对照、有响应超时、有真实命名管道往返（这一点做得很好），但"客户端连不上（AHK 进程没起来 / 认证失败）时 `connect_to_ahk` 是报错还是挂住"没有用例钉住。 | 实测（grep）+ 推断（未见即未覆盖） | 补 1 条：`create_listener` 后不 accept，客户端 `connect_to_ahk` 必须在 N 秒内返回 `Err` 而不是无限阻塞（用 `tokio::time::timeout` 包住断言） |
| 11 | **低** | 阻断性未核实 | `gh auth status` → not logged in；`curl .../branches/main/protection` → 401 Requires authentication；仓库 `private: False`（实测） | **无法确认 `main` 是否配置了 required status checks。** 若未配置，§3 表里的"✅ 是"全部退化为"job 会红但照样能合并"。 | **推断**（唯一一条阻断性推断） | 一次 `gh api repos/zyejf/AutoHotkeydemo/branches/main/protection` 即可闭环；如未配置，至少把 `gates` + `coverage` 设为 required |
| 12 | **低**（已下调） | 门禁不对称 | `check-gates.sh:157-178`（G3b 失败重试 1 次）vs `ci.yml:173-241`（G3b **无重试**） | 本地 G3b 会重试一次、CI 不会。于是同一条偶发红的 AHK 用例：本地绿、CI 红。开发者无法在本机复现 CI 的结论，反过来也一样。 | 实测（读配置） | **经与 Cody 讨论后下调**：`TD-041`「只重试、绝不重试回归判定」的理由成立，且 CI 侧已用 `ASD_HOST_TIMING=0`（`ci.yml:177-183`）显式跳过最易抖的 7 条时延用例——两边本就是有意不同的配置，残留不对称风险不大。**若仍要统一，倾向"给 CI 加同样的重试"**（CI 是共享 runner、更争用），而不是摘掉本地重试。优先级低于 #5b |

---

### 5.1 发现 #5 的证据复现说明（回应 Cody 的复现质疑）

Cody 用 `Select-String` 扫三遍得 **0 命中**，我用 `grep` 得 **9 命中**。同一份代码、同一个文件范围（双方统计的源码 `.rs` 文件数一致，均为 **61 个**，排除 `target`/`node_modules`）——差别只在**匹配方式**：

| 方法 | 命令 | 命中 |
|---|---|:---:|
| 正则（我的原始命令） | `grep -rn "#\[ignore" --include=*.rs asd-tauri/` | **9** |
| PowerShell 正则 | `Select-String -Pattern '#\[ignore'` | **9** |
| PowerShell **字面量** | `Select-String -SimpleMatch '#\[ignore'` | **0** ← Cody 复现出 0 的最可能原因 |
| 逐行判定行首非注释的属性 | 自定义扫描（`Trim()` 后 `^#\[ignore`） | **0（真实属性）** |

- 字面量模式把 `\` 当普通字符，源码里是 `#[ignore]` 而不是 `#\[ignore]`，故恒为 0。
- 那 9 条**确实全在注释里**（`//!` 或 `//` 开头）：`bridge_tests.rs` L5/L181/L189、`watchdog_integration_tests.rs` L5/L6/L7/L14/L15/L17。其中 L181/L189 说的是 BUG-4 已于 2026-09-13 删除的死测试。
- **结论（真实属性 0）双方一致**；但引用"9 处"时必须带上"全在注释里、真实属性 0"，否则审稿人会按字面量复现后扑空。已按此改写发现 #5。

**归属更正**：`#[ignore]` 的摘除来自今日提交 **`721159a`**（`fix(core): 修 IPC 管道名抢注与看门狗误杀范围…`，author `AutoHotkeyDemo Dev`，2026-09-19）。该提交作者是共用账号，**不能归属到某位成员** —— 我上一条给 Cody 的消息里写成"你摘掉的"是不成立的，已更正。（另：`git log -S '#[ignore'` 显示该属性由 `f2edfde` 引入、`721159a` 移除。）

---

## 6. "未发现问题"的检查项（查过且通过）

按团队纪律，查过没问题的靶点一并留痕：

1. **G1 / G3f / G3g / G3d / G3e 五道自动闸门：阳性对照全部变红且点名，无一是永真式。**（见 §2）G3g 的**假绿防护**（退出码 0 但没跑到结尾也算失败）实测有效 —— 这是同类脚本里很少见的、真正防住"空转绿灯"的设计。
2. **`test-map.md` 的 Rust 数字与运行时注册数完全一致**（161/72/173/3/257 = 666，全 OK）。唯一权威地位名副其实。
3. **`cargo test --workspace` 本机全绿、0 ignored**（含 `src-tauri` 256 条 / 13.12s）。
4. **前端 JS 单测 48 条全绿**（14 suites），与既有锚点一致。
5. **AHK 子进程崩溃重启这条高危路径有真实覆盖**：`src-tauri/src/tests/watchdog_integration_tests.rs` 有 `test_watchdog_child_crash_restart`（L134）、`test_watchdog_restart_limit`（L241）、`test_watchdog_exponential_backoff`（L289）、`test_watchdog_full_state_machine_flow`（L529）等 17 条，且 `spawn_fake_executor` **真实起进程**。不是 mock 自嗨。
6. **watchdog 误杀范围有双向阳性对照**：`test_cleanup_does_not_kill_unregistered_same_name_process`（不该杀的必须活）+ `test_terminate_registered_child_kills_it`（该杀的必须死）。这是判别力最强的形态。
7. **配置损坏恢复有覆盖**：`test_load_from_file_invalid_json_falls_back`、`test_load_from_path_invalid_json_returns_error`、`test_restore_from_corrupted_backup`、`test_save_to_file_invalid_directory_returns_error`、`config_repository.rs` 另有 Windows 文件独占退避重试 + `fallback_copy` 专项。
8. **热键冲突有覆盖**：`test_duplicate_hotkey_detection`、`test_control_hotkey_conflict_with_group_hotkey`、`test_config_validator_duplicate_hotkeys_across_groups`、`test_register_hotkey_duplicate_fails`、以及 TD-023 的三条 IPC 失败回滚。
9. **IPC 是真的在测**：`src-tauri/src/tests/ipc_tests.rs` 用真实 Windows 命名管道做 client/server 往返、认证、响应超时；`ipc.rs` 另 54 条含常量时间比较、auth token 随机性、管道名每会话化。
10. **变异对照文化已内化**：test-map.md 记录了 JSON 转义快路径（7 组）、标量类型分派（5 组）、缩进分派（2 组）、手柄字段（2 组）等变异对照，且都写明"全部变红"。本轮我独立复现了 2 组（Rust `time_format`、前端 `data-action` 接线），**均变红并点名** —— 文档里的"做过阳性对照"是可信的。
11. **新加的跨语言校验对拍装置（`cross_lang_validator_parity.rs`）有防"空集对空集"假绿的装置自检**（夹具非空、四类样本各至少一条、`min_cases` 双向 `==`）。这个设计是对的。
12. **G3e 的 C12 安全红线（正式配置不得带 `--remote-debugging-port`）实测会红** —— 一条真正守安全而不只是守格式的门禁。
13. **`src-tauri` 在 CI 上并非"不可测"**：`gates` job 跑 windows-latest，`cargo test -p asd-tauri` 一直在跑（ci.yml:155-157）。test-map.md:199-202 已订正 TD-007 的"Linux 不可编译"措辞，勿据此认为 src-tauri 没测。

---

## 7. Go / No-Go 建议（仅就测试维度）

### 7.1 分场景结论

| 场景 | 结论 | 理由 |
|---|---|---|
| **代码合入 `main`** | ✅ **Go** | 4 个阻断 job + 7 道实测有效闸门 + 666 条用例全绿 + 覆盖率棘轮（虽松弛但仍存在）。合入后回归风险可控 |
| **打包 NSIS 安装包发给用户** | ❌ **No-Go** | `release` job 从未执行过（TD-074），且产物无任何冒烟。启动路径（`lib.rs` 22.84%）无自动化验证，E2E 不在 CI 跑。这是"装完打不开"的盲区 |
| **对外宣称质量水位** | ⚠️ **有条件** | 三口径数字必须并列引用且**更新 ① 为 91.82%**；不得单引 89.05%（已过期），更不得把 ① 当全仓覆盖率 |

### 7.2 发布前必做（按 ROI 排序，仅测试维度）

**P0（不做就不要发安装包）**
1. **手动 dispatch 跑一次 `release` job 并人工观察首次结果**（ci.yml:53-56 已备好开关）。跑绿之前不要把"CI 能出包"当既有事实。
2. **补一条安装包冒烟**：安装 → 启动 → 至少 `invoke` 一个命令 / 执行一个连招 → 退出码校验。哪怕只在手动 dispatch 下跑，也比"零验证"强。
3. **`--update-baseline` 收紧覆盖率基线**（发现 #1），把 89.05 → 91.82（或 CI 实测值）落进本 CR。
4. **补齐 watchdog 晋级留痕**（发现 #5b，Cody 提出、我已独立核实）：补连续 3-5 次 CI 绿跑记录，或暂把该组单独成步并保留 `continue-on-error` 至观测期完成；同时统一 `ci.yml:159-164` 与 `watchdog_integration_tests.rs:5-17` 两处不一致的判据。**（team-lead 汇总报告已列为 finding #11，指派 Tessa，P0，0.5 人日）**

**P1（本轮内）**
5. 决策 T1：`src-tauri` 是否纳入覆盖率门禁（发现 #8）。纳入则需另起 Windows coverage job。
6. 修 `ahk-bench` 的触发条件与注释不匹配（发现 #2）。
7. **把空转的 G3h 改写成"元门禁"**（发现 #5，采纳 Cody 方案 2）：断言 `-- --ignored --list` 输出 `0 tests`，并**去掉 `continue-on-error`**。
7. 给 `check-gates.sh` 补覆盖率可见性（发现 #7）。

**P2（下轮）**
8. 处理 `tests/archive/` 的 38 个死脚本（发现 #6）。
9. 补 IPC 建连失败用例（发现 #10）、修 4 条零断言测试（发现 #9）。
10. 核实分支保护（发现 #11）—— 一条命令的事，但它决定前面所有"阻断"成不成立。
11. G3b 重试不对称（发现 #12，已下调）：若要统一，倾向给 CI 加同样的重试，而非摘掉本地重试。

### 7.3 一句话总结

> 这套测试体系在**"防止代码回归"**上是扎实的、有判别力的、且闸门经得起阳性对照；
> 它在**"防止安装包在用户机器上坏掉"**上几乎是空白 —— 而这恰恰是"个人桌面工具"最不能空白的那一环。
> 所以：**合入可以 Go，发包先 No-Go，补完 P0 三条再谈发布。**

---

### 附：本轮我在仓库留下的痕迹（便于复核与清理）

- 临时脚本 `D:\1demo\AutoHotkeydemo\_tessa_pc_tmp.py`（G3f 对照用，已删除）；复核阶段临时输出 `_tessa_ign.txt` / `_tessa_obs.txt` / `_tessa_git.txt` / `_tessa_git2.txt`（已删除）。
- 生成物 `asd-tauri/coverage/lcov.info`（`.gitignore:72` 已忽略 `coverage/`）。
- 所有阳性对照的注入均已还原，收尾 `git status --short` 只剩队友的产出文件；`git diff` 对 `api.js` / `test_key_validator.ahk` / `test-map.md` / `tauri.conf.json` / `time_format.rs` / `main.js` 均为 **0 行差异**。
- ⚠️ 复核期间 Bash 工具的 stdout 对**所有**命令返回空（Cody 侧 git 亦报 exit 1），已改用「重定向到文件 + Read 工具读取」取证，本报告 §5.1 与发现 #5b 的证据均来自该路径。

### 变更记录

- v1（2026-09-19 18:55）：初稿。
- v2（2026-09-19）：根据 Cody 的独立复核修订 —— ① 发现 #5 的证据改为三算法交叉验证并说明「字面量匹配」复现陷阱（新增 §5.1）；② 新增发现 **#5b（高）门禁晋级未留痕**；③ #5 建议改为 Cody 的方案 2 并去掉 `continue-on-error`；④ 发现 #12（G3b 重试不对称）下调为 P2 并采纳 Cody 的反向建议；⑤ 更正 `#[ignore]` 摘除的归属为提交 `721159a`（共用账号，不归属到个人）。
