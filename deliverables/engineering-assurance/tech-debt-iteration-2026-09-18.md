# 技术债持续迭代报告：门禁漂移收口 + E2E 首次开火后挖出 P0 打包缺陷

**日期**：2026-09-18
**工作流**：工作流 5（技术债评估）+ 工作流 4（发布前检查）混合
**参与成员**：Cody（代码审查师）· Archi（系统架构师）· Rex（SRE）· 主理人甄宇航（独立复核）
**范围**（用户选定）：E2E 验真 + 门禁修复 TD-055 / TD-051

---

## 📌 TL;DR

- 🔴 **本轮挖出一个 P0 生产缺陷，与 E2E 无关却由 E2E 首次暴露**：`tauri.conf.json` 的 `bundle.resources` 漏了 `high_res_clock.ahk`，而 `sender.ahk:16` 与 `joystick.ahk:18` 都要 `#Include` 它 —— **任何干净的打包构建（含分发给用户的 release 安装包）里，AHK 执行器启动即崩**。已修（`e50f8c2`）+ 加 C11 守卫 + 登记 **TD-060**。
- **第六道死因真因已定位**，因果链完整：执行器崩 → 应用窗口永不就绪 → `POST /session` 干等到 60s 超时。前五道死因的修复**全部确认生效**（tauri-driver 已绑定 4444、9 个 spec 全部派发）。
- **同一个 bug 形状被撞见三次**：`.sh` 与 `ci.yml` 都对，只有开发者实际会用的 `.ps1` 是错的。已修 G3d / G3c / G2b·G3a 三处，并新增 **C10** 让它们不可能再次漂移。
- 本轮产出 **6 组提交**，`613a282`~`e50f8c2` 已推送；末条 `3c8496e`（TD-060 文档）推送撞代理 502，待重试。
- 严重度分布：**🔴严重 1 项（已修）/ 🟠高 1 项 / 🟡中 3 项 / 🟢低 2 项**。

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| 整体评级 | 🟡 有条件通过（P0 已修但**未经 E2E 复跑验证**） |
| 阻塞项数量 | **0**（P0 已修复并推送；复跑验证待出结论） |
| 关键行动项 | **6 条** |
| 建议下一步 | ① 取 run `35335990999` 结论 → ② 人工真终端跑一次 `.ps1` 全量 → ③ 重试推送 `3c8496e` |

---

## 一、🔴 P0：打包资源漏文件，执行器启动即崩（已修）

### 1.1 证据

run `35333326568`（job `105562440162`）日志 10:24:38，来自本轮新增的 `dumpDriverLog` 无条件落盘：

```
\\?\D:\a\...\asd-tauri\target\debug\ahk_executor\sender.ahk (16) : ==> #Include file "high_res_clock.ahk" cannot be opened.
   （重复多行）
Error serving connection: Os { code: 10054, kind: ConnectionReset, message: "An existing connection was forcibly closed by the remote host." }
```

### 1.2 成因

`asd-tauri/src-tauri/tauri.conf.json` 的 `bundle.resources` 只列了 7 项，而 `ahk_executor/` 目录下实际有 **6 个 `.ahk`**，多出的 `high_res_clock.ahk` **不在列表里**。偏偏两个生产文件都要 `#Include` 它：

| 引用方 | 行 |
|---|---|
| `sender.ahk` | `:16` |
| `joystick.ahk` | `:18` |

### 1.3 影响面与藏法

- **不只是 CI 问题**：`bundle.resources` 是 `tauri build` 打安装包用的，**分发给用户的 release 版本里 AHK 执行器同样会崩**。E2E 只是第一个撞上它的地方。
- **为什么长期没暴露**：开发机上有本地编译的 `asd_executor.exe`（Ahk2Exe 把 `#Include` 全部打进 exe），而 `resolve_ahk_executor_path`（`src-tauri/src/lib.rs:608`）**优先**用它，于是「便携模式 `AutoHotkey64.exe + executor.ahk`」这条路径在本机从不执行。**与 TD-046 同家族：有一条路径在本机永远走不到。**
- 推测引入时点：`high_res_clock.ahk` 是较晚新增的文件，加入时未同步 `bundle.resources`。

### 1.4 处置（已完成，`e50f8c2`）

1. `bundle.resources` 补 `ahk_executor/high_res_clock.ahk`（现 8 项，6 个 `.ahk` 全覆盖）
2. 新增 **C11** 打包资源清单同步（硬失败、不做棘轮），随 G3e 在三处门禁 + CI 跑
3. 登记 **TD-060**（`3c8496e`）

**C11 的三个刻意收窄**（Cody 设计，我复核认可）：
- 只管**同目录**：跨目录（如 `../domain/x.ahk`）各有自己的打包口径，混进来只会制造无法归因的噪声
- **引用了目录里根本不存在的 `.ahk` 也报**：否则 `resolve_include` 返回 `None` 就静默跳过 —— 那是**假绿**，比不校验更危险
- 目录里有但**从未被引用**只提示、不判失败：`executor.ahk` 是入口脚本（由 `asd_executor.bat` / Rust 直接拉起，本就不该有入边），机器判了就是误报

阳性对照三组全部成立：去掉 `high_res_clock.ahk` → FAIL 并点名两个引用位置；注入不存在的 `zz_probe.ahk` → FAIL 并注明文件不存在；还原 → PASS 且零残留。

> 💡 **这条是本轮最有价值的产出，而它完全来自「让通道先能自证」**。如果本轮只是继续修 E2E 断言、或者干脆把 E2E 当死门删掉，这个 P0 会一直躺在分发版本里。**「假阳性 > 静默失效 > 通道腐烂」的代价排序再次得到验证。**

---

## 二、E2E：通道第一次真正开火

### 2.1 执行序列（修正后）

| 次序 | run id | commit | 结论 | 关键事实 |
|---|---|---|---|---|
| 1 | `35309066359` | — | failure | 零用例执行（死因④：e2e 未装依赖、`npx wdio` 静默降级废弃 `wdio@6.0.1`） |
| 2 | `35310528367` | `e53d136` | failure | 9 spec 全挂、`ECONNREFUSED`（死因⑤） |
| 3 | **`35312497783`** | `ce78fb1` | failure | **42 分钟**——上轮报告中从未被记录，本轮捞出 |
| 4 | `35327797606` | `ce78fb1` | failure | `Spec Files: 0 passed, 9 failed, 9 total in 00:36:32` |
| 5 | `35333326568` | `cce526f` | failure | 14m23s；探测数据到手 → **真因定位** |
| 6 | `35335990999` | `e50f8c2` | **进行中** | P0 修复后的验证；已跑 15 分钟仍未结束 |

### 2.2 前五道死因修复确认生效

诊断日志原文：`[OK] msedgedriver.exe 存在: ...\asd-tauri\e2e\drivers\msedgedriver.exe`；失败形态由 `ECONNREFUSED`（连不上）变为「连得上但无响应」——**tauri-driver 已成功绑定 4444**，9 个 spec 全部派发（`RUNNING in wry` ×9）。

### 2.3 第五次执行的探测结果（假设①被证伪）

```
[INFO] msedgedriver --version: Microsoft Edge WebDriver 152.0.4191.88
[INFO] WebView2 Runtime (HKLM WOW6432Node): ... | pv REG_SZ 152.0.4191.66
[INFO] WebView2 Runtime (HKCU): ERROR: The system was unable to find the specified registry key or value.
```

- **WebView2 Runtime 确实装着**（机器级安装，在 HKLM；HKCU 找不到属正常）
- ⚠️ 我先前核实到「`ci.yml` 全文只在第 31 行描述文字里提到 WebView2、无安装步骤」，但那**不等于**运行时缺失——`windows-latest` 镜像预装了。假设①**已证伪**，这正是加那行探测的意义。
- msedgedriver `152.0.4191.88` vs WebView2 `152.0.4191.66`：主版本一致（152），**不构成版本不匹配**。

### 2.4 `connectionRetryCount` 3→0 生效

每个 spec 由 4 分钟降为 **60 秒**（`10:15:27 RUNNING` → `10:16:27 FAILED`），整轮 42m26s → **14m23s**。依据是我要求 Rex 给出的实断，且我已独立复核：全文件仅一处 `waitForPort('127.0.0.1', 4444, 30000)`，`process.env.CI` 只出现在注释里。

### 2.5 第六次执行（进行中，一个值得注意的信号）

⌛ 截至 10:57 UTC 已运行约 **15 分钟仍未结束**。对比：修复失败时「运行 E2E」步骤稳定为 9 分钟（9×60s）。**超过该时长强烈提示会话已建立、用例正在真实执行**（历史全量 E2E 约 10m43s）。

⚠️ **但结论未出之前，禁止使用「E2E 已修复 / 已跑通」表述**。当前准确表述：**前五道死因修复确认生效，第六道死因（P0 打包缺陷）已修复，复跑验证进行中。**

---

## 三、门禁漂移收口（同一个 bug 形状三次）

| 闸门 | 问题 | 处置 |
|---|---|---|
| **G3d** | `.ps1` 跑 `--no-cargo` 快速档（只查文档内部自洽），运行期对账从未真正执行 | 切完整模式，实测 **15.8s**、exit 0 |
| **G3c** | `.ps1` 只跑 `e2e/helpers/__tests__`，**漏掉 `src/__tests__`** | 显式收集两目录绝对路径；目录不存在即硬失败 |
| **G2b / G3a** | 缺 `CARGO_INCREMENTAL=0`（`.sh` 有）→ ICE 风险 | 补上，try/finally 不污染后续闸门 |

G3c 的阳性对照**复现了旧配置的静默失效**：少收一个文件却仍显示 ✓，漏掉 `src/__tests__/api_contract.test.js`——那是 TD-005 里唯一抓到过真缺陷的测试（发现 `export_recording` 缺 `delays` 参数）。真跑 `node --test` **39 tests / 39 pass**。

**C10 防漂移守卫**（硬失败、不棘轮），双探针：G3d 的 `--no-cargo` 有无、G3i 的 `--selftest` 有无。两个刻意设计：
1. 判据每次从三份文件**正则提取后互比**，脚本里**不存**标准清单——否则那份清单就成了第五份权威副本
2. 判定用「**标志有无**」而非「调用命令全文」——三处 shell 语法天然不同，比全文必然全是假阳性

✅ Cody 主动**否决了 C10 的通用化**，论证成立：做成「任一闸门命令一致」会因语法差异全是假阳性；做成「闸门 ID 集合齐备」一上就红（G3g 只在 `.sh`/`ci.yml`、G3f/G3h 只在 `ci.yml`），压下去又要维护豁免清单——**而豁免清单正是 C10 要消灭的假权威副本**。

**G3i**：`build_graph.py --selftest` 接入三处，紧挨 G1，且**刻意不进 `--quick` / `-SkipGraph`**——自检类闸门被跳过即等于不存在。阳性对照是端到端真跑：破坏重导出正则 → `bash scripts/check-gates.sh` 真的 FAIL、结尾 `FAILED GATES: G3i`。

---

## 四、TD-051：图谱 JS 依赖提取（Archi）

JS 边改**互斥穷尽的四分法**：

| 类别 | 内容 | 进环检测 |
|---|---|---|
| value | 普通 `import` | ✅ |
| **type-only** | `import type X from` / `import { type X } from` / `export type { X } from` | ❌ |
| **re-export** | `export { x } from` / `export * from` / `export * as ns from` | ✅ |
| builtin | `node:` 前缀 | ❌ |

- 仅类型边编译后被完全擦除、不产生运行时依赖，进环检测会把无害的类型循环判成真环并硬失败阻断提交
- 重导出是此前的**假阴性**，现已计为值边并参与环检测
- 新增 `--selftest` + 闸门 `check_js_edge_taxonomy`：拿 `js.edges` 独立重算环检测输入，与留痕的 `cycle_input_edges` **对撞**（防永真式）
- **基线零漂移**：`counts` 一字未改

**阳性对照用了「新旧行为同注入复算」**：`import type` 注入在旧行为下复算为**环 1**、新行为**环 0**；重导出注入在禁用识别后**环 0**（假阴性坐实）、启用后**环 1** 且闸门点名两文件。

> ⚠️ **我下发的前提有一条是错的，已被 Archi 纠正**：我以为 e2e 目录被整体排除、JS 依赖不在图里。实测 `js_e2e_files=19` 已在图内，该盲区在 TD-051 前半就修掉了。**旧报告的前提要先验证再用。**

---

## ✅ 行动清单

| # | 行动 | 负责角色 | 紧急度 | 预期完成 |
|---|------|---------|--------|---------|
| 1 | 取 run `35335990999` 结论，确认 P0 修复是否让通道转绿 | Rex / 主理人 | P0 | 结论出来即定 |
| 2 | **人工在真终端跑一次 `check-gates.ps1` 全量**（沙箱禁止 PowerShell 启外部进程，端到端未验） | 用户 / 主理人 | P0 | 提 PR 前 |
| 3 | 重试推送 `3c8496e`（TD-060 文档，撞代理 502） | 主理人 | P1 | 即时 |
| 4 | TD-059 到期复查（2026-12-18）：先读描述里三个坑是否仍在 | Cody | P1 | 2026-12-18 |
| 5 | G3f 覆盖率棘轮补「基线文件必须全部出现在本次 lcov」+ 文件数下限 | Tessa / Cody | P1 | 下轮 |
| 6 | G4 清单固化：抽 `docs/g4-manual-checklist.md` 单一来源（编号用 **C12**，C9/C10/C11 已占用） | Docu | P2 | 下轮 |

---

## ⚠️ 待完善 / 已知局限

- **`.ps1` 端到端未验证**：`.sh` 那处是端到端真跑；`.ps1` / `ci.yml` 两处是命令级 + C10 互比验证。提 PR 前必须人工在真终端跑一次全量。
- **第三次执行的 wdio 汇总行至今拿不到**（日志接口 `403 Must have admin rights`）。「第 3、4 次同一失败形态、非 flaky」基于**时长签名**（36m37s / 36m32s，地板 36m00s；第 2 次仅 39 秒），**是推断非原文引用**。
- `connectionRetryCount` 3→0 的残留风险：`waitForPort` 只把关 TCP 可连接、不把关 session 可建立，若 driver 冷启动真超 60s 会少掉重试窗口。已知取舍。
- **P0 的因果链最后一步尚未由复跑证实**：「执行器崩 → 窗口不就绪 → `/session` 超时」逻辑自洽且日志吻合，但严格证明要等 run `35335990999`。
- TD-051 已知限制：动态 `import()` 与 `import x = require()` 仍不识别（非回归）。
- 本轮**未做**：台账自洽收尾（统计行 / 状态词 / TD-007 前提纠错 / 快照数字改指针）—— 用户本轮未选，仍是 P0 欠账。

---

## 📚 数据来源 & 成员产出索引

- **Cody**：TD-055 实测 15.8s；G3c/G2b/G3a 三处漂移修复（含「旧配置复现 → 少收文件仍显示 ✓」存证）；C10 双探针设计与通用化否决论证；G3i 三处接入 + 端到端阳性对照；TD-059 登记与否决理由；**P0 打包缺陷修复 + C11 守卫 + TD-060 登记**；逐条实测我给的三个行号（全部准确）。
- **Archi**：JS 边四分法；`--selftest`；`check_js_edge_taxonomy` 对撞校验；新旧行为同注入复算的阳性对照；**纠正我下发的过时前提**。
- **Rex**：第四次执行完整诊断（汇总行原文 + 9×4min=36m32s 算术交叉验证）；第五道修复生效证据；`driverLog` 提模块级 + 三行环境探测 + `connectionRetryCount` 实断；**两度拒绝在无证据时推断根因、拒绝引用未看到的数字**。
- **主理人独立复核**：远端 main 实为 `ce78fb1`（`origin/main` 因代理 fetch 失败陈旧，误报"领先 206 提交"）；`ci.yml` WebView2 仅出现在第 31 行描述文字；`wdio.conf.js` 语法校验 + `waitForPort` 单调用 + 无 CI 分支；`tauri.conf.json` resources 与 `ahk_executor/` 实际文件比对；第五次执行日志中 driverLog 关键行提取；`C11` 与 `C10` 独立跑通。
- **提交**：`613a282` → `081953a` → `9b4d5e6` → `cce526f` → `33d3c07` → `e50f8c2` → `3c8496e`。
- **CI 佐证**：run `35335990999` 的「四闸门 (windows-latest)」= **success in 4m52s**（含 C11 在内的全部门禁在 CI 的 Windows 上通过）。

---

> 本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
