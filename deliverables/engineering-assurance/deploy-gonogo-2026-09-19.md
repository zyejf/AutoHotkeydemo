# 部署前 Go/No-Go 决策报告 · ASD 技能管理器 v4.0

**日期**：2026-09-19
**负责人**：雷克斯（Rex）· SRE 工程师
**任务编号**：#5
**评估对象（已滚动更新）**：
- 初版：commit `9fd8a6972f9172f9e304c5737ec75739c585d9e0`（G3d 小计修复）→ CI run `35446746668`
- **当前 HEAD：`93d88d68695f5a63fb42011cba1e2f58f5334371`**（"docs(user): 新增用户侧文档三件套并订正安装前置说明"）→ CI run **`35447863126`**

> ⚠️ **本报告在取证期间 HEAD 前进了一个提交**。初版结论基于 `9fd8a69`；收到 Archi 的补充发现后复核，发现 Docu 的三份文档已由 `93d88d6` 入库，故**重新核实了新 HEAD 的 CI**（run 35447863126 = `completed / success`，14:09:16Z → 14:16:31Z）。**下文结论以 `93d88d6` 为准**，`9fd8a69` 的核实过程保留在 §1 作为修复命中性的对照证据。

**上游依据**：`deliverables/engineering-assurance/production-readiness-2026-09-19.md`（阻断项编号 B1–B13 沿用该报告，本报告不自造编号）

---

## 📌 TL;DR

- **CI 已核实到底，且核了两次**：
  - run `35446746668`（`9fd8a69`）= `completed / success`。主理人修的 G3d 闸门**在 CI 上确实转绿**，上一版的红灯精确定位在 `四闸门` job 的 **step 18「G3d test-map.md 登记对账」**，且**只有这一步红**，其余 26 步两版全绿 —— 修复精确命中，无附带损伤。
  - run **`35447863126`（当前 HEAD `93d88d6`）= `completed / success`**（14:09:16Z → 14:16:31Z）。逐 job 结论与上一轮同构：四闸门 ✅、前端 lint ✅、Coverage ✅、依赖安全审计 ✅、AHK bench ✅、Benchmark ✅；Miri ❌（continue-on-error，不阻断）；E2E / Fuzz / 发布构建 ➖ skipped。
- **Miri 红不是 UB，是 Miri 隔离策略配置问题**：`statx` 系统调用在 isolation 开启时不被支持，触发点是测试里的 `Path::is_file()` 夹具自检。同一根因在上一版（c52c826）就已存在，属**存量且稳定**，非本次引入。✅ **不阻断，也不构成发布风险**。
- **决策：`Conditional Go` —— 合入 Go / 发布与分发 No-Go（拆分判定）**
  - ✅ **Go** —— 保持在 `main` / 继续合入：CI 四个真阻断 job 全绿，无回归。
  - ❌ **No-Go** —— 触发发布构建、对外分发安装包：剩余阻断 **B3 / B5 / B12 / B13** 未闭环。
  - ✅ **N4 已解除**（本轮复查时）：Docu 的用户侧三件套已由提交 `93d88d6` 入库 —— `git ls-files` + `git cat-file -e HEAD:<path>` 三条全部 `YES`，新 HEAD 的 CI 也已跑绿。**E 类从"内容就绪但未入库"变为真正落地。**
- **本轮新发现 10 条（N1–N10）**，其中 **N1 是本轮最重的一条**：`main` 分支**无分支保护**（API 404 `Branch not protected`）。上一版报告 §7.2 把它列为"唯一一条纯推断"，现已证实 —— **CI 全绿目前不构成任何准入门槛**。
- **N6（Archi 提出、我已独立复核）是最影响发布判定的一条**：打包布局下**没有 `asd_executor.exe`**，安装包必然走「便携模式」（`AutoHotkey64.exe` + `executor.ahk`）；而本地因为该文件存在走的是「编译模式」。⇒ **本地测过的执行器启动路径，和用户装到的不是同一条**，且这条 shipped 路径从未在打包布局下端到端验证过。
- ⚠️ **那片绿灯不含 G3h 的修复**（N7 / §1.6）：Tessa 已在工作树把 G3h 从 `-- --ignored` 改成按模块名跑，但**未提交**；我核实的 run 跑的是 HEAD 版 ci.yml。⇒ **A10 仍判 ❌**，改判必须等提交后重跑 CI。**不能因为"修好了"就改判据，只能因为"CI 证明它好了"才改判。**
- ⚠️ **`ci.yml` 行号已漂移**（N10）：工作树 926 行 vs HEAD 913 行（净 +13）。本报告行号锚定 HEAD 版，171 行之后对照需 +13。
- ⚠️ **"CI 绿"的作用域只有已提交的 HEAD `93d88d6`**（N5）：工作区里有 **9 处未提交改动**（Cody 的 TD-071、Tessa 的 G3h 用例改动，以及 **`ci.yml` 与 `check-test-map.py` 两处闸门自身的定义**），一个都没过 CI。这张通行证不能代表当前这棵树 —— **放行前必须重跑 `git status` 并重查最新 run**。

---

## 一、CI 结论核实

### 1.1 核实方法（先说方法，因为它决定了结论的可信度）

本环境的三个坑已逐一验证并绕过：

| 坑 | 现象 | 绕过方式 |
|---|---|---|
| `github.com` 不可达 | curl 直连返回 000 | 全程只走 `api.github.com`（HTTP 200） |
| `gh auth status` 谎报未登录 | 报未登录 | `gh auth token` 实际可取到 `gho_` token，直接用它调 API |
| `gh run list` 返回空 | 本仓库查不到 run | 改用 `GET /repos/zyejf/AutoHotkeydemo/actions/runs?head_sha=<完整 sha>` 精确过滤 |
| job 日志下载后被清空 | `/tmp` 在命令之间不持久 | 落盘到工作区目录再解析 |
| 取证中途 Bash/PowerShell 的 stdout 停止回传 | 命令执行成功但输出为空（`echo test` 也返回空） | 改为「命令写文件 → 用 Read 工具读回」；执行能力未受影响，仅回显失效 |

对账前提已确认（三个 sha 均逐字节核对）：`9fd8a69` = `9fd8a6972f9172f9e304c5737ec75739c585d9e0`、`c52c826` = `c52c826a0c423d678c48e7db03cc279a57888af6`、**`93d88d6` = `93d88d68695f5a63fb42011cba1e2f58f5334371`** —— 与各自 run 的 `head_sha` 一致。

> ⚠️ **为何要核两次**：本报告初版基于 `9fd8a69`。收到 Archi 的补充发现后做复核，发现 HEAD 已前进到 `93d88d6`（Docu 的文档入库提交）。**若直接沿用初版结论，就会拿一个已落后一个提交的 CI 结果去放行** —— 故重新按 `head_sha` 查到 run `35447863126` 并等到 `completed`。

### 1.2 逐 job 结论表（run 35446746668，最终态）

| # | Job | 结论 | Steps | 是否真阻断 | 说明 |
|---|---|---|---|---|---|
| 1 | **四闸门 (windows-latest)** | ✅ success | 27 | **是** | 本次修复目标。step 18「G3d test-map.md 登记对账」**转绿** |
| 2 | 前端 lint（ESLint） | ✅ success | 8 | **是** | — |
| 3 | Coverage（纯逻辑 crate） | ✅ success | 11 | **是** | `ci.yml:305` 起为阻断 job |
| 4 | 依赖安全审计（TD-014） | ✅ success | 8 | **是** | — |
| 5 | AHK Benchmark Regression（T11 门禁） | ✅ success | 11 | 部分 | `ci.yml:447` 限定 `main` + `push`，**PR 上不跑** |
| 6 | Miri UB Check | ❌ **failure** | 8 | **否** | `ci.yml:395 continue-on-error: true`，永不阻断。定性见 §二 |
| 7 | Benchmark Regression | ✅ success | 11 | **否** | `ci.yml:446 continue-on-error: true` |
| 8 | E2E（仅手动触发） | ➖ skipped | 0 | — | `ci.yml:568` `workflow_dispatch && inputs.run_e2e`（默认 false），**结构性不可达** |
| 9 | Fuzz Testing | ➖ skipped | 0 | — | `ci.yml:416` 仅 `schedule` 事件触发 |
| 10 | 发布构建（NSIS 安装包，仅手动触发） | ➖ skipped | 0 | — | `ci.yml:794` `workflow_dispatch && inputs.build_release`（默认 false），`needs: gates` |
| 11 | Security audit | ✅ success | **0** | — | ⚠️ **外部 check run**（`html_url` 为 `/runs/` 而非 job 页），0 step、耗时 **1 秒**（13:48:54→13:48:55）。非本仓 `ci.yml` 定义，**不计入本仓自设门禁证据** |

**总计**：`completed / success`。11 个条目中 4 个真阻断 job 全绿、3 个信号类（miri/fuzz/bench）按设计不阻断、2 个手动 job 按设计 skipped、1 个为平台注入的外部 check run。

### 1.3 上一版对照：修复是否精确命中

上一版 run = `35445690697`（sha `c52c826`），结论 `completed / failure`。逐个 step 比对后：

- 唯一非绿 step = **step 18「G3d test-map.md 登记对账」**（failure）；
- 其余 26 步在两版中**均为 success**。

**判读**：这不是"碰巧刷绿"，而是修复精确命中了唯一故障点，且**没有引入任何新失败**。上一版除 G3d 外的所有闸门本来就是绿的。

### 1.4 四闸门内部逐步结论（run 35446746668 ／ `9fd8a69`）

G1 图谱基线 ✅ ／ G3i build_graph.py JS 边归类自检 ✅ ／ G2a `cargo fmt --check` ✅ ／ G2b `clippy -D warnings` ✅ ／ G3a `cargo test --workspace` ✅ ／ **G3h watchdog 进程生命周期 ❌（0 用例，见下）** ／ G3b AHK 完整测试套件 ✅ ／ G3c JS 单元测试 ✅ ／ **G3d test-map.md 登记对账 ✅（本次修复项）** ／ G3e 技术债度量（C1/C2/C3/C3b/C13）✅ ／ G3g AHK 独立脚本 ✅ ／ G4 文档同步 ✅

> **新 HEAD 的 run `35447863126`（`93d88d6`）逐 job 结论与本节同构**：四闸门 27 步全 success、前端 lint / Coverage / 依赖安全审计 / AHK bench / Benchmark 全 success、Miri failure（continue-on-error）、E2E / Fuzz / 发布构建 skipped。**两次核实结论一致。**

⚠️ 三处需看穿绿灯：
- **G3h 是永真空闸门**（`ci.yml:166-171`）。**CI 日志硬证据**（job 105906876013）：
  ```
  ##[group]Run cargo test -p asd-tauri --lib -- --ignored --test-threads=1
  running 0 tests
  test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 256 filtered out
  ```
  **跑 0 条用例 → rc=0 → 绿灯**，且步骤带 `continue-on-error: true`。根因：全仓已无活 `#[ignore]` 属性（本轮 grep `^\s*#\[ignore\]` 全仓 **0 命中**），而上游报告 §四 #11 记录的 15 条已于 `721159a` 摘除，摘除时**未同步改这道门的命令**。⇒ **G3h 的绿灯不携带任何信息，不得计入有效信号。**
- **G4** 经 Tessa 阳性对照确证「结构上不可能红」，两端都只是打印清单 —— **它是纸面核对表，不是自动闸门**（上游报告 §5.3 #7）。
- **G3a 的绿灯不含 watchdog 进程生命周期用例** —— 它们正是被上面那个空跑的 G3h"看护"的。

### 1.5 已排除的一类误判

上游提示的「所有 job steps 为空、秒级失败 = 账户账单问题」**本次不适用**：`四闸门` 27 步、`Coverage` 11 步、`Miri` 8 步，且 `四闸门` 实跑 4 分 17 秒（13:46:28→13:50:45）。**运行痕迹真实，无需改代码。**

### 1.6 ⚠️ 两条时效性告警（读本报告前必看）

**① `ci.yml` 行号已整体漂移。** 工作树的 `.github/workflows/ci.yml` 被改动（未提交）：`git diff HEAD --stat` = **19 插入 / 6 删除（净 +13）**，文件 **913 → 926 行**。
⇒ **本报告引用的 `ci.yml` 行号均为 HEAD（`93d88d6`）版。171 行之后的行号，工作树版需 +13**（例：`release` job 的 `if:` 794→807、artifact 名 908→921、文件末 913→926）。详见 N10。

**② 那片绿灯不含 G3h 的修复 —— 别把它记成"已修"。** 工作树里 Tessa 已把 G3h 从
`cargo test -p asd-tauri --lib -- --ignored --test-threads=1`
改为
`cargo test -p asd-tauri --lib tests::watchdog_integration_tests -- --test-threads=1`
（按模块名直接跑，注释里写明了「恒绿空转」的成因与解禁判据）。**但该改动未提交**，而本报告核实的 run `35447863126` 跑的是 **HEAD 版（913 行）的 ci.yml**。
⇒ **A10「G3h 有实际用例」在本报告里仍判 ❌**，绿灯守的东西没变。**只有等它提交后重跑一次 CI，才能改判。** 这与 N7 是同一条纪律的两面：**不能因为"修好了"就改判据，只能因为"CI 证明它好了"才改判。**

---

## 二、Miri 为什么红 —— 定性结论

### 2.1 直接证据（CI 日志原文，run 35446746668 / job 105906876009）

```
error: unsupported operation: `statx` not available when isolation is enabled
  --> .../library/std/src/sys/pal/unix/weak/syscall.rs:13:26
  = help: set `MIRIFLAGS=-Zmiri-disable-isolation` to disable isolation;
  = help: or set `MIRIFLAGS=-Zmiri-isolation-error=warn` ...
  = note: this is on thread `fixture_self_ch`
     9: std::path::Path::is_file          at .../library/std/src/path.rs:3617:9
    10: fixture_self_check                at crates/asd-domain/tests/cross_lang_validator_parity.rs:200:9
error: aborting due to 1 previous error
error: test failed, to rerun pass `-p asd-domain --test cross_lang_validator_parity`
```

### 2.2 定性：**环境/配置问题，不是 UB** ✅

归因链条完整闭合，不存在歧义：

1. 测试 `fixture_self_check`（`asd-tauri/crates/asd-domain/tests/cross_lang_validator_parity.rs:196-202`）用 `Path::new(CASES_PATH).is_file()` 校验对拍夹具存在 —— 这是**业务上正当的断言**（夹具丢了要报"夹具丢了"而不是"用例逻辑错"）。
2. `Path::is_file()` → `std::fs::metadata` → Linux `statx` 系统调用。
3. Miri **默认开启 isolation**，禁止文件系统访问；workflow 里**没有设置 `MIRIFLAGS`**（`ci.yml:406-410` 只有两条裸命令）。
4. 于是触发 `unsupported operation`，进程退出码 1。

**关键判据**：报错类型是 `unsupported operation`（能力被策略关闭），**不是** `Undefined Behavior` / `dereferencing pointer` / `out-of-bounds` / `use-after-free` 之类。**Miri 在这一次运行里一个 UB 都没报。**

**正面证据（比"没报 UB"更强）**：同一 job 中 Miri 实跑了 **115 条测试全部通过** —— `asd-domain` unittests **111 passed / 0 failed**（26.63s）、`config_version_compat_tests` **4 passed / 0 failed**（1.44s），零 UB、零失败。

**存量性已证实**：上一版 run 的 Miri job（105904102333）日志**同一行、同一根因**（`13:26:03` 处同样 `statx not available when isolation is enabled`，同样 111 + 4 通过）。**非本次提交引入的回归。**

### 2.3 一个被红灯掩盖的真实副作用（值得记，但不阻塞）

`ci.yml:406-410` 是两条串行的 `bash -e` 命令：

```yaml
run: |
  cargo +nightly miri test -p asd-domain        # ← 这条失败，脚本随即中止
  cargo +nightly miri test -p asd-ipc-protocol  # ← 永远跑不到
```

日志中 `asd-ipc-protocol` 只出现在**编译阶段**（已编译），其测试**一次也没执行**。⇒ **`asd-ipc-protocol` 的 Miri UB 覆盖实际为 0**，红灯把它遮住了。修 Miri 配置后会一并暴露（可能变红也可能变绿，属未知面）。

### 2.4 建议修复（P2，不进阻断清单）

二选一，成本都很低：

- **方案 A（推荐，改 CI）**：在 `ci.yml` Miri job 加 `env: MIRIFLAGS: -Zmiri-disable-isolation`。夹具自检是**有意**要做文件检查的，放行隔离符合意图。
- **方案 B（改测试）**：给 `fixture_self_check` 加 `#[cfg(not(miri))]`，让它在 Miri 下跳过。

⚠️ **不要用** `-Zmiri-isolation-error=warn`：那会把所有隔离违例降级为警告，等于把这道信号门彻底关掉，将来真出现文件系统相关的 UB 也看不见。

---

## 三、部署前检查清单

> 图例：✅ 有／满足　❌ 无／不满足　➖ 不适用
> 凡标注「本机」的均未上 CI；凡标注「CI」的均来自 run 35446746668 实测。

### A. 代码与门禁

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| A1 | 四闸门全绿（含 G1/G2a/G2b/G3a–G3g） | ✅ CI | run 35446746668，job「四闸门」27 步全 success |
| A2 | 本次修复项 G3d 在 CI 上转绿 | ✅ CI | step 18 success；上一版同 step failure，对照确认精确命中 |
| A3 | 前端 lint 零警告 | ✅ CI | job「前端 lint（ESLint）」success |
| A4 | 覆盖率闸门通过 | ✅ CI | job「Coverage（纯逻辑 crate）」success |
| A5 | 依赖安全审计通过 | ✅ CI | job「依赖安全审计（TD-014）」success |
| A6 | 本机脚本闸门复跑 | ⚠️ 未在本轮复跑 | 主理人已验 `check-test-map.py` / `check-tech-debt.py` rc=0；本轮重跑因脚本触发 cargo 被超时中断，**以 CI 的 G3d/G3e 绿为准（证据更强）** |
| A7 | UB 检查（Miri）无真 UB 信号 | ✅ CI | 115 条测试通过、零 UB 报告；红灯为隔离配置问题（§二） |
| A8 | 分支保护生效（CI 绿即准入门槛） | ❌ **新发现 N1** | `GET /branches/main/protection` → HTTP **404 `Branch not protected`** |
| A9 | G4 文档同步闸门 | ➖ 不适用 | 结构上不可能红，是纸面核对表（上游报告 §5.3 #7），不产生证据 |
| A10 | **G3h watchdog 闸门有实际用例** | ❌ **新发现 N7** | CI 日志 `running 0 tests` / `0 passed … 256 filtered out`；全仓活 `#[ignore]` = 0。**永真空闸门** |
| A11 | watchdog 进程生命周期路径有有效守护 | ❌ | 其唯一守护者即 A10 的空闸门 |

### B. 构建与产物

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| B1 | 发布构建 job 曾真实执行过 | ❌ | 本次及全部历史 run 中该 job 均 `skipped`；`ci.yml:794` 需手动 `workflow_dispatch` + `build_release=true` |
| B2 | 本机存在 release 产物（exe / bundle / NSIS） | ❌ 本机 | `asd-tauri/src-tauri/target/release/` 下仅有 `ahk_executor`、`asd_tauri.pdb`、`build`、`deps`、`examples`、`incremental`；**无 exe、无 bundle 目录** |
| B3 | 版本号已确定 | ✅ | `tauri.conf.json:4` = `0.1.0` |
| B4 | 安装包随附第三方许可证与源码说明 | ✅ | 上游报告 §九 表 3–5，`bundle.resources` 已含 `AutoHotkey-license.txt` + `THIRD-PARTY-NOTICES.md`（**B2 已闭环**） |
| B5 | 本项目自身许可证已声明 | ✅ | GPL-2.0-only，落 `LICENSE` + `Cargo.toml` ×5 + `package.json` + `bundle.license/licenseFile`（**B1 已闭环**） |
| B6 | **打包布局下的执行器启动路径已实测** | ❌ **新发现 N6** | `bundle.resources`（`tauri.conf.json:37-48`）**不含 `asd_executor.exe`**；`.gitignore:35` `*.exe` 将其排除在库外；`build.rs` 亦不生成它。⇒ 安装包内 `resolve_ahk_executor_path`（`lib.rs:634-661`）必然回落**便携模式**（`AutoHotkey64.exe` + `executor.ahk`）。而本地 `src-tauri/ahk_executor/asd_executor.exe` 存在 → 本地走**编译模式**（`lib.rs:640`）。**两者不是同一条代码路径，且 shipped 的这条从未在打包布局下端到端跑过** |
| B7 | 便携模式参数接线正确（静态） | ✅ | `watchdog.rs:314-319` 对 `AutoHotkey64.exe` 正确追加 `executor.ahk` 为参数；`executor.ahk` 已在 `bundle.resources:38`。⇒ **不是"必然坏"，是"接线看着对但没跑过"** |

### C. 分发与回滚落点

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| C1 | 存在 GitHub Release 步骤 | ❌ | 全 `ci.yml`（913 行）无 `softprops`/`create-release`/`gh release`；release job 仅 `upload-artifact@v4`（retention 90 天）→ **B3 未修** |
| C2 | 存在不过期的分发落点 | ❌ | 唯一落点是 90 天过期的 CI artifact |
| C3 | 自动更新（updater） | ➖ 不适用 | 上游已判定降为中危、非阻断；但**其替代路径「手动重新下载」的落点正是 C1/C2 缺失的那一个** |

### D. 可运维与故障恢复

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| D1 | 执行器 Failed 终态有用户可见提示 | ✅ | 上游 §九 表 12（`addLog` + `showToast` + `_lastExecStatus` 守卫）→ **B4 已闭环** |
| D2 | 存在自助恢复入口（重置看门狗） | ✅ | 上游 §九 表 13（诊断页状态行 + `♻️ 重置看门狗` 按钮，`api.resetWatchdog()` 由零调用转为已接）→ **B4 已闭环** |
| D3 | 配置损坏不再静默回退 | ✅ | 上游 §九 表 15–17（`user_facing_failure()` 按错误类型分流 + 前端拉取）→ **B6 已闭环** |
| D4 | **AHK 子进程重启后热键重注册** | ❌ | `watchdog.rs:1279 restart_child` 仅 `wd.spawn_child()`（kill+spawn），全仓 `active_hotkeys` 无重放路径 → **B5 未修，且仍为推断级**（"重启后确实失效"未经端到端实测） |
| D5 | 日志按天轮转 + 保留上限 | ✅ | `logging.rs:32 max_log_files(7)` 生效（上游 §5.4 推翻了"无限增长"怀疑） |
| D6 | 用户可自助备份/恢复 | ✅ 本机 | 备份管理页已接 UI（`main.js` 309/316/320/346 等处），上游确认三处均接上 |
| D7 | 故障反馈通道（ISSUE_TEMPLATE） | ❌ | 上游 §5.4 实测目录不存在 |

### E. 用户侧文档

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| E1 | README 存在 | ✅ 工作区 | `README.md` 99 行已存在 → **B8 内容已就绪** |
| E2 | 用户手册存在 | ✅ 工作区 | `docs/user-guide.md` 311 行 → **B9 内容已就绪** |
| E3 | 排障表为纯 GUI 路径 | ✅ 工作区 | `docs/troubleshooting.md` 245 行；`:230` 明确劝退 `invoke('get_executor_status')` 等内部 API，指向「诊断信息」页 → **B10 内容已就绪** |
| E4 | 安装前置（WebView2）已说明 | ✅ 工作区 | `README.md:30/32/92`、`user-guide.md:28/30`、`troubleshooting.md:22/27/30` 均说明 `downloadBootstrapper + silent` 及其"失败不提示"代价 → **B11 内容已就绪** |
| E5 | **上述文档已纳入版本控制** | ✅ **已解除** | 提交 `93d88d6` 已入库；`git ls-files` + `git cat-file -e HEAD:<path>` 三条**全部 YES**（初查时为 NO，见 N4） |
| E6 | 上述文档已被 CI 校验 | ✅ | 新 HEAD 的 run `35447863126` = `completed / success`，该 run 的 `head_sha` 即 `93d88d6`，**含**这三份文件 |
| E7 | 存量 `developer-guide.md` 与配置矛盾已修 | ⚠️ 待确认 | 上游 §2.3 B11 的"文档与配置矛盾"指 `developer-guide.md:700`；新文档已写对，存量矛盾是否同步修正需 Docu 确认 |

### F. 端到端与发布验证

| # | 检查项 | 状态 | 证据 |
|---|---|---|---|
| F1 | E2E 53 个用例在 CI 上执行过 | ❌ | 本次 run E2E `skipped`；`ci.yml:568` 结构性不可达 → **B12 未修** |
| F2 | 发布产物冒烟（装→启→执行一个连招） | ❌ | 无任何产物（B2），无从冒烟 → **B13 未修** |
| F3 | 启动路径自动化验证 | ❌ | 上游：`lib.rs` 覆盖率仅 22.84%，启动路径无自动化验证 |

### 检查清单小结

| 类别 | ✅ | ❌ | ⚠️ | ➖ |
|---|---|---|---|---|
| A 代码与门禁 | 6 | 3 | 1 | 1 |
| B 构建与产物 | 4 | 3 | 0 | 0 |
| C 分发与回滚落点 | 0 | 2 | 0 | 1 |
| D 可运维与故障恢复 | 4 | 2 | 0 | 0 |
| E 用户侧文档 | 6 | 0 | 1 | 0 |
| F 端到端与发布验证 | 0 | 3 | 0 | 0 |
| **合计** | **20** | **13** | **2** | **2** |

---

## 四、Go / No-Go 决策

### 4.1 结论：**Conditional Go**（分场景判定，两个方向都不含糊）

| 场景 | 判定 | 理由 |
|---|---|---|
| **① 保持在 `main` / 继续合入后续提交** | ✅ **Go** | 4 个真阻断 job 全绿；G3d 修复经 CI 对照确认精确命中、无附带损伤；Miri 红灯已定性为非 UB 的存量配置问题 |
| **② 触发发布构建（`build_release`）** | ❌ **No-Go** | 会产生一个**已知缺陷**的安装包：B5（重启后热键失效）在内，且 B8–B11 的文档不在 `9fd8a69` 里 → 包出去就是"装得上、用不明白" |
| **③ 对外公开分发** | ❌ **No-Go** | B3 未修：没有 GitHub Release，唯一落点是 90 天过期 artifact；**且回滚方案本身依赖这个不存在的落点** |

### 4.2 决策理由（按重量排序）

1. **CI 这一维是干净的**，本轮没有任何理由因为代码质量叫停 —— 这是 Go（场景①）的全部依据。
2. **但"CI 全绿"在本项目里不构成准入门槛**（N1：main 无分支保护）。所以场景①的 Go 是"技术上可以合入"，不是"有机制保证合进来的都是绿的"。这两者不能混为一谈。
3. **发布/分发的两条硬阻塞是 B3 与 B13**，且它们互相加强：没有 Release ⇒ 没有回滚落点；没有产物冒烟 ⇒ 连"这次包能不能启动"都不知道。**在有回滚方案之前谈发布是没有意义的。**
4. **B5 是唯一一条"可能在用户机器上表现为完全失灵"的阻断**：watchdog 自动重启成功，但热键不重注册 —— 用户看到的是"程序在跑、热键全废"，且无任何提示。它仍属推断级（未经端到端实测），但**推断级不等于可以不阻断**，因为一旦为真，影响面是 100% 的用户会话。
5. **文档这一维出现了"内容已就绪但未入库"的错配**（N4）。这是本轮最容易被误判为"已解决"的地方：Docu 的三份文档质量看起来已经到位，**但发布候选 commit `9fd8a69` 里根本没有它们**。此刻触发发布，产出的包不含 README、不含用户手册、不含排障表 —— B8/B9/B10/B11 四个阻断**在包里一个都没解除**。
6. **"CI 全绿"的作用域必须收紧到已提交的 HEAD `93d88d6`**（N5）。工作区里有 **9 处未提交改动**（含 Cody 的 TD-071、Tessa 的 G3h/watchdog 用例改动，以及 **`ci.yml` 与 `check-test-map.py` 这两处闸门自身的定义**）。**绿的是 HEAD 那个 commit，不是现在这棵树** —— 而且改闸门的同时拿旧闸门的绿灯下结论，逻辑上就不成立。
7. **即便作用域收紧到 `9fd8a69`，那片"绿"里也有水分**（N7）：G3h 跑 0 条用例照样绿灯，G4 结构上不可能红。**真正携带信息的绿灯只有 G1 / G2a / G2b / G3a–G3g 这几道**，而它们守的是单测与静态检查，守不到集成与打包布局。
8. **最要命的是"测过的 ≠ 发出的"**（N6）。打包布局下没有 `asd_executor.exe`，用户装到的是便携模式；本地和 CI 测的是编译模式（本地）或根本没启动应用（CI）。**这条 shipped 路径的验证次数是 0**。这不是"可能有 bug"，而是"这条路径从未被执行过一次"—— 与本报告 §5.3「回滚方案是纸面方案」是同一种失效：**整条外环零执行痕迹**。这使场景②③的 No-Go 从"有若干未闭环缺陷"升级为"将要发布一条从未运行过的启动路径"。

### 4.3 解除 No-Go 的最小路径（按依赖顺序）

| 序 | 动作 | 解除 | 负责 | 预估 |
|---|---|---|---|---|
| 0 | **先定死工作区归宿**：把 9 处未提交改动（TD-071 / G3h 用例 / **`ci.yml` 与 `check-test-map.py`**）提交并等一轮新 CI，或明确剥离后再发 | N5 | 主理人 + Cody + Tessa | — |
| ~~1~~ | ~~把用户侧三件套入库~~ → **已由 `93d88d6` 完成**（N4 解除） | B8/B9/B10/B11 | Docu | ✅ 已完成 |
| 2 | 实测 B5：杀掉 `asd_executor.exe` → 按原热键，确认是否失效；若失效则加 `active_hotkeys` 重放 | B5 | Tessa | 0.5 人日 |
| 2b | **把 N6 的便携模式验证并进冒烟**：A5/A6 断言（日志出现「使用(便携\|编译)模式 AHK 子进程」+ `IPC 已接受 AHK 连接（已认证）` + 进程表有 `AutoHotkey64`/`asd_executor`）。**这是唯一能证明 shipped 启动路径真的能跑的手段**，采纳 Archi 的设计 | N6 | Tessa | 并入 #5 |
| 2c | **G3h 修复已在工作中**（Tessa 改为按模块名跑），**剩余动作只有"提交 + 等 CI 复验"**。⚠️ 未复验前 A10 保持 ❌，不得提前改判 | N7 | Tessa | 极小 |
| 3 | 手动触发 release job（`build_release=true`）**人工盯全程**，确认产出 NSIS 包 | B13 的前置 | Rex | 0.5 人日 |
| 4 | 补 GitHub Release 步骤，把安装包落到不过期的分发点 | B3 | Rex | 0.5 人日 |
| 5 | 跑一次发布产物冒烟（装 → 启 → 执行一个连招）并补进 CI | B13 | Tessa | 1 人日 |
| 6 | 打开 `main` 分支保护（至少要求 `gates` 这个 required check） | N1 | 主理人 | 极小 |
| 6b | 若将来接 tag 自动发版：**先明确 release job 用哪种 token**（`GITHUB_TOKEN` 建 tag 不二次触发；PAT/OAuth 会），实跑验证，并用 `concurrency` 兜底 | N9 | Rex + Archi | 0.2 人日 |
| 7 | 修 Miri 配置（`MIRIFLAGS=-Zmiri-disable-isolation`） | 信号门可信度（P2，不阻塞） | Rex | 极小 |

**顺序约束**：3 必须在 2 之后（否则产出一个已知缺陷的包，反而锁定坏基线）；4 必须与 3 同批（否则产物仍会落到 90 天过期点）。6 可与任何一步并行，且成本极低 —— 建议**现在就做**。

---

## 五、回滚方案

### 5.1 分层回滚

| 层 | 手段 | 可用性 | 备注 |
|---|---|---|---|
| **代码** | 回退到 `c52c826` 或任意历史 ref | ✅ 可用 | `git revert` / `git checkout <ref>`；**本轮未执行任何 git 写操作** |
| **重新构建** | 用旧 ref 重新触发 release job | ✅ 机制上可用 | `workflow_dispatch` 支持在 UI 里**任选 ref**（`ci.yml:756` 已注明"回滚并不需要 tag 触发"） |
| **分发** | 从分发点撤下 / 换回旧版本 | ❌ **不可用** | **没有 GitHub Release**。唯一落点是 90 天过期的 artifact —— B3 的直接后果 |
| **用户侧** | 卸载重装旧版本 | ⚠️ 勉强可用 | 无 updater，需用户手动操作；且用户**不知道去哪下载旧版本**（分发点不存在） |
| **用户数据** | 备份管理页恢复 | ✅ 可用 | 备份入口已接 UI（D6）；配置目录按修正后的真实路径 `%APPDATA%\com.asd.tauri\` |

### 5.2 回滚触发条件（任一命中即启动回滚）

| # | 触发条件 | 对应缺陷 | 判据 |
|---|---|---|---|
| T1 | 安装后双击无反应 / 窗口黑屏空白 | B11 | WebView2 未装且 `silent:true` 下失败无提示；用户无从判断 → 一旦出现即批量出现 |
| T2 | 应用在运行、但热键全部失效 | **B5** | watchdog 重启后无重放。注意：**界面一切正常**，只有"按了没反应"这一个信号 |
| T3 | 首次启动即弹「配置加载失败 / 数据丢失」 | B6 回归 | `user_facing_failure()` 的 `FileNotFound` 分流若失效，新用户首启动必误报 —— **这是修复引入回归的高风险点**，冒烟必须专门验这一条 |
| T4 | 执行器 Failed 后界面无任何提示 | B4 回归 | 已有 4 条静态契约测试守护 |
| T5 | 安装包内的许可证/声明文件缺失 | B2 回归 | 分发前逐包核对 `bundle.resources` |
| **T6** | **日志未出现「使用(便携\|编译)模式 AHK 子进程」，或后续无 `IPC 已接受 AHK 连接（已认证）`** | **N6** | 直接判定 shipped 启动路径不通 —— **这是新包最可能出现的失效模式**，因为它从未被执行过。冒烟必须把它列为第一断言 |

### 5.3 回滚演练现状

❌ **未演练**。不存在可回滚的产物（B2）、不存在可回滚的分发点（B3）、E2E 从未执行（B12）。**当前回滚方案是一份纸面方案** —— 这是本次 No-Go（场景②③）最实质的理由，比任何单条缺陷都硬。

---

## 六、本轮新发现（N1–N5）

| # | 发现 | 证据 | 影响 |
|---|---|---|---|
| **N1** | **`main` 分支无保护** | `GET /repos/zyejf/AutoHotkeydemo/branches/main/protection` → HTTP **404** `Branch not protected` | 上一版报告 §7.2 列为"唯一一条纯推断"，**现已证实**。CI 绿不构成准入门槛；任何人可向 main 直推。**建议立即开启，成本极低** |
| **N2** | **`asd-ipc-protocol` 的 Miri 覆盖为 0** | 日志中该 crate 只出现于编译阶段；`ci.yml` 两条串行命令，第一条失败即中止 | 红灯掩盖了一个真实的覆盖盲区。修 Miri 配置后会暴露 |
| **N3** | **「Security audit」不是本仓门禁** | `html_url` 为 `/runs/`（外部 check run），**0 step**、耗时 **1 秒**，两次运行均 success | 不应计入"本仓质量门全绿"的证据。真阻断的是「依赖安全审计（TD-014）」（8 步） |
| **N4** | ~~**用户侧三件套未入库**~~ → **✅ 已解除** | 初查 `git ls-files` 三条 `tracked = NO`；复查时提交 **`93d88d6`** 已将其入库，`git cat-file -e HEAD:<path>` 三条全部 YES | 报告落盘后 Docu 完成入库，新 HEAD 的 CI（run 35447863126）已跑绿。**B8/B9/B10/B11 现已在发布候选 commit 内**。保留此条是因为它完整记录了"内容就绪 ≠ 已入库"这个差点被误判为已解决的时间窗 |
| **N5** | **工作区存在进行中的改动，且范围在扩大** | 初查 3 处 `M`：`ipc.rs`（+117/−6，Cody 的 TD-071 DACL）、`Cargo.toml`（+7）、`Cargo.lock`（+1）。**复查时已扩到 9 处**，新增：`.github/workflows/ci.yml`、`asd-tauri/docs/test-map.md`、`scripts/check-test-map.py`、`asd-tauri/src-tauri/src/tests/watchdog_integration_tests.rs`、`docs/guard-effectiveness-checklist.md`、`docs/tech-debt-register.md` | CI 绿只代表**已提交的 HEAD**（`93d88d6`）。**这 9 处改动一个都没被 CI 验证过**。⚠️ 其中 `ci.yml` 与 `check-test-map.py` 是**闸门自身的定义** —— 改闸门的同时用旧闸门的结果下 Go/No-Go 结论是无效的。发布前必须先把工作区归宿定死：提交并等一轮新 CI，或明确剥离后再发 |
| **N6** | **打包布局的执行器路径 ≠ 本地开发路径**（Archi 提出，我已独立复核并全部证实） | ① `tauri.conf.json:37-48` `bundle.resources` 无 `asd_executor.exe`；② `.gitignore:35` `*.exe` 排除；③ `build.rs` 全文无 `asd_executor`（不生成）；④ 本地 `src-tauri/ahk_executor/asd_executor.exe` **存在** → 本地走 `lib.rs:640` 编译模式；⑤ 安装包内该文件不存在 → 走 `lib.rs:653` 便携模式 | **本地测过的执行器启动路径，和用户装到的不是同一条**。CI 全新 clone 同样拿不到该文件 ⇒ CI 侧也是便携模式，但 CI 从不启动应用，所以**便携模式在打包布局下从未被端到端验证过**。这是 B13 的直接加重项 |
| **N7** | **G3h 是永真空闸门**（Archi 提出，我用 CI 日志坐实） | job 105906876013 日志：`running 0 tests` → `test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; **256 filtered out**`；全仓 grep `^\s*#\[ignore\]` **0 命中** | 摘 `#[ignore]`（`721159a`）时未同步改这道门的命令。绿灯不携带任何信息；**watchdog 进程生命周期路径当前无任何有效守护** |
| **N8** | **远端 tag `v0.1.0` 已存在且严重落后** | `GET /repos/.../tags` → 全仓仅 **1** 个 tag：`v0.1.0` → `0fbfce52e3c0d3d299e49916091321b992d7ceb8`，日期 **2026-06-28**，较 HEAD `93d88d6` **落后 363 个提交** | ⚠️ **对 Archi 表述的一处修正**：`ci.yml:22-24` 的 `on.push` **只有 `branches: [main, master]`，并无 `tags:` 过滤器** —— 不是"待办失效"，而是 `ci.yml:765-770` 明确记录了**刻意不接 tag 触发**的决策。但这不改变事实本身：**`v0.1.0` 指向的是 3 个月前、落后 362 个提交的代码**。任何人若按"打了 v0.1.0 就算发过版"来理解，会严重误判。将来若要接 tag 自动发版，必须打**新** tag（如 `v0.1.1`） |
| **N9** | **接 tag 自动发版存在二次触发风险 —— 且风险取决于用哪个 token**（Archi 提出为「未验证」，我已查证到官方规则） | GitHub Docs（Events that trigger workflows / Triggering a workflow）原文：「**When you use the repository's `GITHUB_TOKEN` to perform tasks, events triggered by the `GITHUB_TOKEN` will not create a new workflow run**」；并明确「**For all other events** … if a workflow run pushes code using the `GITHUB_TOKEN`, a new workflow will not run even when the repository contains a workflow configured to run on `push` events」；反之「use a **GitHub App installation access token or a personal access token** instead of `GITHUB_TOKEN` to trigger events that require a token」 | **结论：用 `secrets.GITHUB_TOKEN` → 建的 tag 不会二次触发；用 PAT / OAuth token / App token → 会触发。** ⚠️ 本环境 `gh auth token` 取到的是 **`gho_` 前缀的 OAuth 用户 token**（非 `GITHUB_TOKEN`），故**人工手动 `gh release create` 走的是"会触发"那条路**。⇒ 接 tag 自动发版前必须：① 明确 release job 用的是哪种 token；② 实跑一次验证；③ 用 `concurrency` 兜底 |
| **N10** | **`ci.yml` 行号漂移** | 工作树 926 行 vs HEAD 913 行，净 +13（Archi 提出，我已复核 `git diff HEAD --stat` 确认 19 插入 / 6 删除） | 本报告所有 `ci.yml` 行号锚定 **HEAD 版**；与工作树版对照时 171 行之后需 +13。跨报告引用行号时务必注明版本，否则两报告会对不上 |

---

## 七、数据来源与局限

**数据来源**

| 项 | 来源 | 性质 |
|---|---|---|
| CI run 元数据与 job 结论 | `api.github.com` · run `35446746668`（`9fd8a69`）/ `35445690697`（`c52c826`）/ **`35447863126`（`93d88d6`）** | **CI 实测** |
| 用户侧文档入库 | `git ls-files` + `git cat-file -e HEAD:<path>` × 3 | **本机实测**（复查后转为 YES） |
| 工作区未提交改动 | `git status --porcelain` × 2 次（3 处 → 9 处） | **本机实测** |
| Miri 归因 | job `105906876009` 与 `105904102333` 完整日志 | **CI 实测** |
| 分支保护 | `GET /branches/main/protection` | **实测**（首次，此前为推断） |
| G3h 空跑 | job `105906876013` 日志：`running 0 tests` / `256 filtered out` | **CI 实测** |
| 全仓活 `#[ignore]` | Grep `^\s*#\[ignore\]` → 0 命中 | **本机实测** |
| 打包资源清单 | `tauri.conf.json:37-48` + `.gitignore:35` + `build.rs` 全文无 `asd_executor` | **本机实测** |
| 本地执行器模式 | `src-tauri/ahk_executor/asd_executor.exe` 存在（Glob 命中 7 处，含 src 与各 target） | **本机实测** |
| 远端 tag | `GET /repos/.../tags` → 仅 `v0.1.0` → `0fbfce5`（2026-06-28）；`git rev-list --count 0fbfce5..HEAD` = **363** | **实测** |
| `ci.yml` 工作树改动 | `git diff HEAD --stat` → 19 插入 / 6 删除（净 +13），文件 913 → **926** 行 | **本机实测** |
| G3h 命令变更 | 工作树已改为 `cargo test -p asd-tauri --lib tests::watchdog_integration_tests -- --test-threads=1`（HEAD 版仍为 `-- --ignored`） | **本机实测**（工作树，**未过 CI**） |
| 文档入库状态 | `git ls-files --error-unmatch` × 3 | **本机实测** |
| release 产物缺失 | `ls asd-tauri/src-tauri/target/release/`（**浅层，未递归**） | **本机实测** |
| restart_child 无重放 | `watchdog.rs:1279-1300` + 全仓 `active_hotkeys` grep | **本机实测**（"重启后确实失效"仍为推断） |
| 阻断项编号 B1–B13 | `production-readiness-2026-09-19.md` | 沿用上游，**未自造** |

**局限（如实标注）**

1. **A6 未复跑**：本机 `check-test-map.py` / `check-tech-debt.py` 本轮重跑被超时中断（脚本触发 cargo）。以 CI 的 G3d / G3e 绿为准 —— **该证据更强，因为它就是 CI 上的同一道门**。
2. **B5 仍为推断级**：无重放路径已实证，"重启后确实失效"未经端到端实测。这正是不把它降级为非阻断的原因。
3. **E7 未核实**：存量 `developer-guide.md:700` 与 `tauri.conf.json` 的矛盾是否已同步修正，需 Docu 确认，本报告标 ⚠️ 而非 ✅/❌。
4. **未执行任何 git 写操作**：本轮全部为只读取证；未打 tag、未建 Release、未 `workflow_dispatch`、未递归遍历 `target/`。
5. **E2E 的结论沿用 2026-09-16 的 96 次运行核对**，本轮仅确认本次 run 中 E2E 仍为 `skipped`（与之一致）。
6. **N6 的"便携模式从未验证"是推断，但推断方向是保守的**：我确证了"打包布局必然走便携模式"和"本地走的是编译模式"，但**没有**确证便携模式会失败 —— 相反，`watchdog.rs:314-319` 的接线看起来是对的（B7 ✅）。风险评估是"未验证"而非"已知坏"。这一点必须说准，否则会把一条"没跑过"的项夸大成一个已知缺陷。
7. **工作区是移动的 —— 这是本次最大的取证风险**。本报告取证期间 HEAD 从 `9fd8a69` 前进到 `93d88d6`，未提交改动从 3 处扩大到 9 处。N5 反映的是**最后一次 `git status` 时刻的快照**，提交前必须重新确认。⇒ **任何基于本报告的放行动作，都必须先重跑一次 `git status` + 查一次最新 run**。我未对任何代码做改动，也未执行 git 写操作。

---

> 本报告由雷克斯（Rex）· SRE 工程师出具。**CI 部分全部为 run 35446746668 的 CI 实测，非推断**；本机取证项已逐条标注「本机」。所有阻断项编号沿用 `production-readiness-2026-09-19.md`，新增发现单独以 N1–N4 编号，未混入原体系。
