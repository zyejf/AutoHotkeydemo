# 文档体系与发布物料 — 生产级就绪度评估（Docu）

> 评估人：多库（Docu）· 技术文档师
> 日期：2026-09-19
> 范围：ASD 技能管理器 v4.0（`D:\1demo\AutoHotkeydemo`，主 worktree，分支 `main`）
> 定位：个人桌面工具 + **公开仓库**（`https://github.com/zyejf/AutoHotkeydemo`）
> 核心问题：**一个从未见过这个项目的用户/维护者，能不能靠仓库里的文档把它装起来、用起来、并在出问题时自救？**

---

## 1. 本域结论

### 判定：**不达标**（No-Go）

**一句话回答核心问题：不能。**
- **装不起来** —— 仓库无 README、无安装说明；首次安装需联网下载 WebView2 且 `silent: true`，
  离线会静默失败，而这一点**没有任何面向用户的文字**（只在 `.trae/` 工具目录与今天的评审产出里）。
- **用不起来** —— 全仓 84 篇 `docs/*.md` 里**没有一篇用户手册**；应用内 7 个页面也**没有任何帮助/FAQ**。
  按键连招怎么配、10 种执行模式怎么选、热键怎么设、摇杆怎么配，全部只能靠猜。
- **出问题没法自救** —— 唯一的排障表 `developer-guide.md:676-685` 六行全部要求调用内部 API
  （`get_executor_status` / `active_hotkeys` Map / `mark_shutting_down()`），终端用户无执行路径；
  而用户唯一能自助的「配置在哪」这一条，文档给的路径是**错的**。

### 一个必须说清楚的分裂

这个项目的**工程侧文档质量其实相当高**，远高于一般个人项目：
- `docs/developer-guide.md` 1956 行，IPC 协议、Watchdog 状态机、覆盖率口径漂移、CI 踩坑都有实测数据支撑；
- `AGENTS.md` 1463 行，架构 / 分层 / 妥协白名单 / 关键文件清单齐全，并明确「数字只写指针不复制」；
- `docs/adr/README.md` 当天新建，规范严谨（必备六节 + 复审触发条件 + ADR 只增不改）；
- `scripts/check-tech-debt.py` 已用 C3/C3b/C13 自动守住部分文档—代码一致性。

**但这些文档全都是给「已经上手的人」看的。** 仓库缺的是最外面那一层——
陌生人从 GitHub 落地后看到的第一屏、第一个安装动作、第一个配置动作、第一次报错。
对「个人桌面工具 + 公开仓库」这个定位，**这不是企业级文档体系的过度要求，而是入口缺失**。

### 严重度分布

| 严重度 | 数量 | 主要分布 |
|---|---:|---|
| 阻断 | 6 | README 缺失、用户手册缺失、LICENSE 缺失、安装前置未说明、排障对终端用户不可用、**GPLv2 二进制分发未附许可证与源码说明** |
| 高 | 4 | WebView2 离线静默失败、日志/配置路径过时、围栏吞掉整节、版本四处不一致 |
| 中 | 5 | CHANGELOG 缺失、无 doc lint、历史快照占比 86%、ADR 覆盖不足、硬编码本机路径 |
| 低 | 2 | 章节编号重复、`file://` 死链 |

---

## 2. 发现清单表

| # | 严重度 | 类别 | 证据（文件:行） | 问题描述 | 实测/推断 | 生产级影响 | 建议 |
|---|---|---|---|---|---|---|---|
| 1 | **阻断** | A1 首屏 | 仓库根 `ls README*` 无输出；GitHub 首页 WebFetch | 公开仓库无 README。实测 GitHub 首页：无 README 渲染、无仓库描述、无 License 徽章；首屏为 22 目录 + 37 文件列表，其中显著部分是散落调试截图（`app_ui_loaded.png`/`dashboard_page.png`/`fix1_verified.png`/`initial_state.png`/`keypicker_opened.png`/`light_theme.png`/`mobile_viewport.png`/`preview_test.png`/`sequence_mode.png`/`toast_test.png`/`webview2_initial.png`）与 `demo_*.html`、`config_export_20260524021401.json`、`launch_cdp.bat`、`run_silent.ps1` | **实测**（`ls` + WebFetch 抓取 GitHub 首页） | 陌生人落地后**无法得知这是什么、怎么装**；首屏被调试产物占据，观感像未整理的个人草稿而非可交付产品 | 补 README：①一句话是什么 ②下载/安装 ③3 步上手 ④截图 ⑤排障入口。**素材已在库内**：89 个被跟踪 png，其中 `func_test/01_dashboard_initial.png`…`15_keytest_verify.png` 是成套 UI 截图，可直接用 |
| 2 | **阻断** | A3 使用文档 | 全仓 md 搜 `quickstart\|用户手册\|使用手册` → **0 命中**；`docs/migration-guide.md:5` 自述「面向…开发者」；`asd-tauri/index.html` 搜 `帮助\|使用说明\|FAQ` → **0 命中** | 无任何用户使用手册。10 种执行模式、热键设置、摇杆配置、备份恢复均无说明。`docs/` 里唯一两处「使用说明」（`graph-driven-workflow.md:1251`、`module-adjacency.md:10`）是**图谱工具链**的开发者说明 | **实测**（grep 全仓） | 用户装完不知道怎么用，直接流失；「个人桌面工具」定位下这是转化率的致命伤 | 补 `docs/user-guide.md`：主界面导览 / 建分组 / 设热键 / 10 模式怎么选 / 摇杆 / 备份恢复；或先在应用内加「帮助」页 |
| 3 | **阻断** | A4 自救 | `docs/developer-guide.md:676-685`（§3.4.2 常见问题排查，6 行） | 全部要求调用内部 API：`检查 get_executor_status 返回值`、`检查 active_hotkeys Map 内容`、`确认 mark_shutting_down() 在关机前调用`。终端用户**无执行路径**。三条最高频症状（热键不生效 / 软件打不开 / 配置丢失）中只有「按键不发送」有对应行 | **实测**（读表） | 用户出问题只能去提 issue；本项目**无遥测**（TD-076），事故不可知 → 故障与反馈双盲 | 补 `docs/troubleshooting.md`（面向用户，纯 GUI 操作路径）：热键不生效 → 检查是否被占用/是否在游戏中禁用 → 诊断页看执行器状态 → 附日志目录 |
| 4 | **阻断** | C1 合规 | 仓库根 `ls LICENSE*` 无输出；全仓 find（排除 vendored）`*license*\|*licence*\|NOTICE\|COPYING` → **0 结果** | 公开仓库无 LICENSE | **实测** | 默认「保留所有权利」：**他人无权合法使用、复制、修改、二次分发**，贡献者也无明确许可基础。GitHub 首页实测无 License 徽章 | 立即补 `LICENSE`。注意与 vendored GPLv2 的兼容（见 #6），选许可前先想清楚 |
| 5 | **阻断** | A2 安装 | `asd-tauri/src-tauri/tauri.conf.json:52-55` `webviewInstallMode = {type: downloadBootstrapper, silent: true}`；`docs/developer-guide.md:700` 写「WebView2 \| Edge Chromium 内核 \| **Windows 10+ 内置**」 | 无安装文档；且文档与配置矛盾：文档暗示「系统自带、无需安装」，实际配置要求**联网下载 bootstrapper**，`silent: true` 下失败无提示。全仓 md 中 `downloadBootstrapper` 只出现在 `.trae/specs/`（IDE 工具目录）、`deliverables/`（今日评审产出）、`docs/superpowers/specs/2026-05-28-rust-rewrite-research.md:786`（研究稿）——**`developer-guide.md` 与 `AGENTS.md` 均未提及** | **实测**（读配置 + grep 全仓 md） | 离线/内网/受限网络用户**装不上或装完双击没反应**，且无提示；会产生一批「装不上」反馈，而无遥测下无法归因 | README/安装说明写明「首次安装需联网」；离线场景给 `offlineInstaller`（+约 130MB）或 `embedBootstrapper` 说明 |
| 6 | **阻断** | C2 合规 | `tauri.conf.json:35-44` 打包 `ahk_executor/AutoHotkey64.exe`（实测 1.27MB 存在）；`AutoHotkey-2.0.26/license.txt:79-85`（§1）「give any other recipients of the Program **a copy of this License** along with the Program」、`:134-136`（§3）「distribute the Program … in object code or executable form … provided that you also do one of the following: a) Accompany it with the complete corresponding machine-readable source code … b) Accompany it with a written offer …」；`asd-tauri/` 与 `src-tauri/` 下无任何 license/notice/third-party 文件 | 安装包分发 GPLv2 二进制（另 `asd_executor.exe` 实测 1.34MB，Ahk2Exe 编译、内嵌解释器，由 `tauri.release.conf.json` 打包），**既无许可证副本也无源码说明**。⚠️ **必须拆成两个独立问题**：**Q1**（分发 GPL 程序本身是否须随附许可证+源码说明）→ **确定要**，依据即 §1/§3，与「自研代码是否被传染」无关；GPLv2 §2 mere aggregation（`:129-132`）免除的是「**另一件作品**」，**不免除对被分发的 GPL 程序本身的 §1/§3 义务**。**Q2**（自研 Rust 代码是否被传染、须以 GPL 开源）→ 这才是不确定的，且量级远大于 Q1 | 文件缺失**实测**；§1/§3 条款**实测**（读 license.txt 原文）；Q2 结论属**推断**（需法务意见） | **即使 Q2 答「否」，Q1 依然成立且仍是阻断级**。当前状态属「不解决就不能合法分发」。修复成本极低（包内附许可证文本，约 1 小时），**在 Q2 两种答案下都必须要做** | ①补 `THIRD-PARTY-NOTICES.md`（AutoHotkey v2.0.26 / GPLv2 / 源码获取方式）②NSIS 安装目录随附 `license.txt` ③按 §3b 提供源码或三年有效的书面要约。⚠️ **Q1 不等待 Q2 的法务意见** |
| 7 | **高** | B2 过时路径 | `docs/developer-guide.md:1681-1684`（§4.8 配置文件位置）：日志文件位置 `{app_data_dir}/asd.log`；`{app_data_dir}` 通常为 `C:\Users\{username}\AppData\Roaming\**asd-tauri**\` | 与同文件刚订正的 §3.1.1（`:449-452`）**自相矛盾**。实测证伪：`%APPDATA%\com.asd.tauri\` 存在且文件为 `asd.2026-09-17.log` 等按天轮转文件；`%APPDATA%\asd-tauri\` **不存在** | **实测**（`ls` 真实 APPDATA 目录） | 「配置丢失 / 备份 / 找日志」是最高频的用户自救场景，文档给错目录 → 用户直接找错地方，自救失败 | 改 §4.8 两行为 `%APPDATA%\<identifier>`（当前 `com.asd.tauri`）+ `asd.<YYYY-MM-DD>.log`，与 §3.1.1 一致 |
| 8 | **高** | B2 渲染缺陷 | `docs/developer-guide.md:1600-1601`：1600 行 `cd asd-tauri && cargo audit` 是**游离命令**（无起始围栏），1601 是**孤立闭合围栏** | 按 CommonMark 围栏规则模拟，代码块范围含 **`(1601, 1636)`** → **§4.6.6 静态分析档位整节（含标题 `### 4.6.6`、Rust pedantic 档位决策表、4 条豁免理由、以及 `npm run lint` 命令块）全部渲染为纯文本代码块**，标题与表格不生效。同文件围栏总数 **127（奇数）**，实测不配对 | **实测**（自写 CommonMark 围栏模拟器，脚本留档 `deliverables/engineering-assurance/_docu_fencesim.py`） | 维护者看不到 lint 档位这一节（= 不知道哪些 clippy 规则开/不开、为什么），会重复踩「加 lint 是仪式」的坑 | 在 1600 行前补 ```bash 起始围栏（或删除 1600-1601 两行孤儿） |
| 9 | **高** | B3 版本不一致 | `asd-tauri/index.html:7` `<title>技能管理器 v3.0</title>`、`:16` `v3.0 Tauri`、`:161` `版本 3.0 \| Tauri + AHK v2`；`tauri.conf.json:4` `version: "0.1.0"`；`AGENTS.md:3` `# ASD 技能管理器 v4.0` | TD-078：四处不一致。且诊断信息页（`:348-349`）读真实版本会显示 **0.1.0**，与界面左上角 **v3.0** 并排可见 → **用户能直接看到的自相矛盾** | **实测** | 用户报障时说不清版本；无遥测下版本号是唯一锚点，错了就无法判断「哪个版本有问题」 | 统一为单一真值源（建议 `tauri.conf.json` 的 `version`），`index.html` 改为动态读取 |
| 10 | **高** | B2/B4 决策留痕 | **实例 A（强）**：`docs/developer-guide.md:1673` 声称产物含 `MSI: bundle/msi/`；`tauri.conf.json:27` `"targets": ["nsis"]`；研究稿 `2026-05-28-rust-rewrite-research.md:781` 原本推荐 `"targets": ["nsis","msi"]` 双轨。**实例 B（弱）**：同研究稿 `:895` 列「评估 Tauri 插件 … **updater 2.10.1** …」（🟢 P2）；实测全仓 `Cargo.toml` 与 `tauri.conf.json` grep `updater` **零命中** | 这是一**类**问题而非两处笔误：**研究稿提过 → 落地没做 → 砍的理由没留痕**。⚠️ 两例强度不同，勿等同：MSI 是**明确建议 + 具体配置值**（强）；updater 是 **P2「按需评估」**（弱，佐证：同行 4 个插件 3 个已落地且版本逐一对上，updater 是唯一未拾起项，见 §8.3）——写成「决策被静默砍掉」会让人误以为它曾是硬承诺 | **实测**（读配置/文档 + grep） | 维护者按文档找 MSI 找不到、误判构建失败；更根本的是**后人无法判断「没做」是决策还是遗漏**，可能重复投入或反向优化 | ①删除文档 MSI 一行（或改 `targets` 若确需）②把「不做 MSI / 不做 updater」的结论与理由**补进 ADR**，两例都写清原建议强度 |
| 11 | 中 | C3 版本管理 | 全仓 `find -iname "CHANGELOG*"` → 仅 vendored `AutoHotkey-2.0.26/source/lib_pcre/pcre/ChangeLog`；`git tag` → 仅 `v0.1.0`；`tauri.conf.json:4` 仍 `0.1.0` | 无 CHANGELOG。用户无从知道版本间变了什么 | **实测** | 升级决策无依据；配合 #9 的版本混乱，用户无法判断该不该升级 | 补 `CHANGELOG.md`（可先只记 v0.1.0 → 当前的变化），并用 `tauri.conf.json` 版本打 tag |
| 12 | 中 | D1 自动化 | `.github/workflows/ci.yml`（913 行，11 job）grep `markdown\|link\|lychee\|markdownlint` → **0 命中**；`ci.yml:273-280` G4「文档同步」实际只是 `Write-Host '  [ ] …'` 打印 6 行人工清单 | 无任何 markdown lint / 链接检查 / 术语检查。G4 名为闸门，实为提示 | **实测**（grep CI + 读 G4 步骤） | 文档错误只能靠人发现——本次评估在**唯一一篇主打的开发指南**里就找到 4 处走不通，印证了这点 | 加 markdownlint；优先加「文档内写的文件路径/命令是否存在」的检查（成本最低、命中率最高） |
| 13 | 中 | D2 可维护性 | `docs/` 84 篇 md 实测分布：根 13（含 5 篇带日期报告）、`review/*` 25、`superpowers/*` 32、`refactor` 8、`perf` 1、`research` 1、`adr` 3。**存活文档 ≈ 12 篇，历史快照 ≈ 72 篇（86%）**。实测 `docs/README.md`、`docs/review/README.md`、`docs/superpowers/README.md` **均不存在**（只有 `refactor/` 与 `adr/` 有） | 新来者进 `docs/` 看到 19 篇 `superpowers/plans/`（实现计划）与 25 篇 `review/`，**无从分辨哪些是现状、哪些是 2026-05/08 的快照** | **实测**（按目录计数 + ls） | 后来者可能照着 2026-05 的旧计划改代码；也可能导致「以为有文档实则全是快照」的误判 | 补 `docs/README.md` 作为索引：区分「现行规范」与「历史快照（只读）」；给 `review/` 与 `superpowers/` 各加一行 README 说明冻结状态 |
| 14 | 中 | B4 ADR | `docs/adr/` 仅 ADR-001、ADR-002 + README；两者状态实测**均为 `Proposed`**（`ADR-001:3`、`ADR-002:3`，均「待工程督导复核」） | 无已 Accepted 的决策记录。以下重要决策**没有 ADR**：① 为什么 Rust+Tauri 取代纯 AHK（选型依据只在 `docs/superpowers/specs/2026-05-28-rust-rewrite-research.md`，2894 行研究稿）② 为什么 Named Pipe 而非其它 IPC（`developer-guide.md` §2 只写协议、无选项对比）③ 为什么 CSP 设为 `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'`（`tauri.conf.json:22`，`unsafe-inline` 是安全权衡却无记录）④ 为什么 NSIS 而非 MSI ⑤ 打包 GPLv2 二进制的分发决策 ⑥ Watchdog 心跳参数（1s/3s/5s）取值依据 | **实测**（ls ADR 目录 + 读状态行） | 决策散落在研究稿/记忆/代码注释里；后人改这些决策时不知道当初为何这么定，容易反向优化 | 按 ADR README 规范补 003-006；至少先把「Rust+Tauri 选型」与「GPLv2 打包合规」立成 ADR |
| 15 | 中 | B1 路径可移植 | `docs/developer-guide.md` 含 **31 处** `d:\1demo\...`、**7 处** `D:\Program Files\...`、**16 处** `file:///d:/1demo/...` 绝对链接；全仓 **44 篇** md 含 `1demo` | 公开仓库里对任何其他人都是错路径/死链 | **实测**（grep -cF） | 贡献者照抄命令必然失败；`file://` 链接在 GitHub 上点了没反应 | 改为相对路径或 `<repo-root>` 占位；`file://` 链接改为仓库内相对链接 |
| 16 | 中 | B1 版本定位 | `AGENTS.md:9`「v3.0 采用严格 DDD 四层架构，**作为独立运行模式保留**」 vs `docs/adr/ADR-001`（v3 转维护模式、冻结新功能） | 口径不一致。ADR-001 自己已点名这处（其对比表末行引用了 AGENTS.md 该句），但 ADR 仍是 `Proposed`，AGENTS.md 未同步 | **实测**（读 AGENTS.md:9 + ADR-001 表格） | 新维护者会以为 v3（纯 AHK 栈）仍是可用的独立模式，可能在冻结栈上继续投入 | ADR-001 转为 Accepted 后同步 AGENTS.md:9 措辞 |
| 17 | 中 | B1 过时命令 | `AGENTS.md:889-904`「调试命令」：`Get-Content logs\debug.log`、`Get-Content logs\app.log` | v3 时代路径。实测 `logs/app.log` 内容为 v3 JSONLogger 格式（`{"code":"I002","module":"JSONParser",...}`），而 v4 日志实测在 `%APPDATA%\com.asd.tauri\asd.2026-09-17.log` | **实测**（`head` 日志 + `ls` 真实目录） | 照抄会看 v3 的旧日志，找不到 v4 的任何线索——与 #7 是同一类「排障者找不到日志」 | AGENTS.md §调试命令改为 v4 路径，或加一行「v3 已冻结，此节为 v3」 |
| 18 | 低 | B2 结构 | `docs/developer-guide.md:1561`「### 4.7 E2E 本地跑起来」与 `:1658`「### 4.7 发布构建」编号重复；`:1603`「### 4.6.6」排在「4.7」之后 | 章节编号错乱 | **实测** | 目录/TOC 跳转错乱，快速定位困难 | 重排编号 |
| 19 | 低 | D1 链接 | `docs/developer-guide.md` 16 处 `file:///d:/1demo/...`（另 `.trae/documents/` 1、`docs/superpowers/plans/2026-05-27-joystick-fixes.md` 3、`docs/superpowers/specs/2026-05-28-rust-rewrite-research.md` 2） | 绝对文件链接，在 GitHub 上对所有人都是死链 | **实测** | 引用失效 | 改相对链接 |

---

## 3. 文档走查记录（按 `developer-guide.md` 实际走一遍）

方法：文档说某命令 → 确认脚本/路径存在；文档说某路径 → 确认真实存在。
不执行完整构建（耗时），只做**存在性与语法级**验证。

### 3.1 走通的步骤（✅）

| 步骤 | 文档位置 | 验证方式 | 结果 |
|---|---|---|---|
| `cd asd-tauri && npm install` | §4.1 `:706-707` | `package.json` 存在 | ✅ |
| `cd src-tauri && cargo check` | §4.1 `:710-711` | `src-tauri/Cargo.toml` 存在 | ✅ |
| `.\build_ahk.ps1` | §4.1 `:714` | `src-tauri/build_ahk.ps1` 存在 | ✅ |
| `npm run tauri dev` | §4.2 `:722` | `package.json.scripts.tauri = "tauri"` | ✅ |
| `npm run build` | §4.3 `:737` | `scripts.build = "vite build"` | ✅ |
| `cargo build` / `cargo build --release` | §4.3 `:746-749` | 目录存在 | ✅ |
| `npm run tauri build` | §4.3 `:773` | 同上 `tauri` script | ✅ |
| `cargo test` 系列 | §4.4 `:785-796` | `Cargo.toml` workspace 存在 | ✅ |
| `tests/run_all_tests.ahk` | §4.4 `:821` | 文件存在（10,368 B） | ✅ |
| `bash tools/ahk-probes/run.sh p0_version` | §4.6.2 `:1175` | 文件存在 + `bash -n` 语法通过 | ✅ |
| `bash tools/ahk-bench/run.sh json_escape` | §4.6.3 `:1203` | 文件存在 + `bash -n` 通过 | ✅ |
| `tools/ahk-bench/cycle_leak_all.sh` | §4.6.3 `:1209` | 存在 | ✅ |
| `scripts/check-gates.sh` / `.ps1` | §4.6.1 `:939,943` | 均存在 + `.sh` `bash -n` 通过 | ✅ |
| `python scripts/check-tech-debt.py` | §4.6.1.1 `:1002` | 存在 + `py_compile` 通过 + **实跑 `--only c3` 通过** | ✅ |
| `python scripts/check-coverage.py` | §4.6.1.2 `:1051` | 存在 + `py_compile` 通过 | ✅ |
| `scripts/run-standalone-ahk-tests.sh` | §4.6.1 `:955` | 存在 + `bash -n` 通过 | ✅ |
| `scripts/install-hooks.ps1` / `.sh` | §4.6.1 `:989` | 均存在 + `.sh` `bash -n` 通过 | ✅ |
| `scripts/push-and-verify.sh` | §4.10 `:1727` | 存在 + `bash -n` 通过 | ✅ |
| `scripts/check-graph-baseline.py` / `check-test-map.py` | §4.6.1 `:948,952` | 存在 + `py_compile` 通过 | ✅ |
| `cd asd-tauri && npm run lint` | §4.6.6 `:1635` | `scripts.lint = "eslint src --max-warnings 0"` | ✅ |

**小结：文档引用的脚本 15/15 全部存在，`bash -n` 7/7 通过，`py_compile` 4/4 通过。**
命令层面的「写了不存在的脚本」问题**没有发现** —— 这点必须肯定。

### 3.2 走不通 / 会误导的步骤（❌）

| # | 步骤 | 文档位置 | 实测结果 |
|---|---|---|---|
| 1 | 日志目录 `$env:APPDATA\asd-tauri` | §4.8 `:1684` | ❌ **不存在**。真实为 `%APPDATA%\com.asd.tauri\`（实测含 `asd.2026-09-17.log` 等） |
| 2 | 日志文件 `{app_data_dir}/asd.log` | §4.8 `:1681-1682` | ❌ **无固定 `asd.log`**，按天轮转 `asd.YYYY-MM-DD.log`（与同文件 §3.1.1 `:452` 矛盾） |
| 3 | 产物 `bundle/msi/` | §4.7 `:1673` | ❌ `targets: ["nsis"]`，不产 MSI |
| 4 | §4.6.6 静态分析档位整节 | §4.6.6 `:1603-1636` | ❌ **被围栏吞掉**，渲染为纯文本（详见 #8）：标题 `### 4.6.6`、pedantic 档位表、豁免理由、`npm run lint` 块全部失效 |
| 5 | `cd asd-tauri && cargo audit` | `:1600` | ⚠️ 游离在围栏外的孤儿命令行，前后无配套 |
| 6 | `AHK 全量测试 602 项` | §4.6.6 `:1656` | ❌ 权威 666（`test-map.md:242`，2026-09-19），差 64 |
| 7 | 前置条件「WebView2 Windows 10+ 内置」 | §4.1 `:700` | ⚠️ 与 `downloadBootstrapper` 矛盾，实测需联网下载 |
| 8 | `file:///d:/1demo/...` 链接 | 全文 16 处 | ❌ 对任何其他人都是死链 |

### 3.3 走查结论

**命令与脚本层面健康（15/15 存在、11/11 语法通过），问题集中在「路径 / 数字 / 渲染」三类。**
这与「文档写了很久、代码一直在动」的典型症状一致——脚本名不容易变，但日志目录、产物类型、测试数量会变。
而**恰好没有自动化去守这三类**（见 #12），所以它们必然漂移。

---

## 4. 文档一致性矛盾清单（B3）

权威源：`asd-tauri/docs/test-map.md`（测试数字）、`AGENTS.md`（架构分层）、`docs/tech-debt-register.md`（债项状态）。

| # | 矛盾 | 陈旧方（证据） | 权威方（证据） | 是否被自动化守住 |
|---|---|---|---|---|
| 1 | Rust 全量测试数 | `docs/developer-guide.md:1656`「**602** 项通过」 | `asd-tauri/docs/test-map.md:242`「**666**」（161+72+173+3+257，2026-09-19 实测） | ❌ **无**。C3b 只查 AHK 基线数字，不覆盖 Rust 数字 |
| 2 | Rust 测试数（快照警示自身过期） | `docs/tech-debt-plan-2026-09-16.md:35`「AHK 现 722 / **Rust 现 651**」 | `test-map.md:242`「666」 | ❌ **无**。同上，且其警示语自身已是旧值 |
| 3 | 日志路径（同一文件内自相矛盾） | `docs/developer-guide.md:1681-1684`「`{app_data_dir}/asd.log`」「`...\Roaming\asd-tauri\`」 | 同文件 `docs/developer-guide.md:449-452`（刚订正版）；实测 `%APPDATA%\com.asd.tauri\asd.2026-09-17.log` | ❌ **无** |
| 4 | 安装包产物类型 | `docs/developer-guide.md:1673`「MSI 安装包: `bundle/msi/`」 | `tauri.conf.json:27` `"targets": ["nsis"]` | ❌ **无**（C11 只核对 `#Include ↔ bundle.resources`，不管文档） |
| 5 | 版本号 | `index.html:7/16/161`「v3.0」；`AGENTS.md:3`「v4.0」 | `tauri.conf.json:4`「0.1.0」（构建产物真实版本） | ❌ **无**（实测 `grep TD-078\|版本号` on `check-tech-debt.py` → 无命中） |
| 6 | v3 栈定位 | `AGENTS.md:9`「作为独立运行模式保留」 | `docs/adr/ADR-001`「转维护模式，冻结新功能」 | ❌ 无（且 ADR 仍 `Proposed`） |
| 7 | AHK 基线数字 `642 / 642` | `docs/perf/key-latency-benchmark-2026-09-13.md:231` | `test-map.md:244`「722」 | ✅ **已守**：该文件自带快照警示（`:232-233`），且 C3b 已登记在册（实测 `--only c3` 输出「当前 3 项 / 新增 0 / 已登记 3」） |

**说明**：第 7 项虽然数字陈旧，但**带快照警示 + 已被 C3b 登记**，属于可接受的「历史记录」处理，不列为新债 ——
这也侧面说明：**只要加一行警示 + 进台账，旧数字就不是问题**；上面 1-6 的症结正是「既没警示也没被守住」。

---

## 5. 缺失文档清单

### 5.1 必须补（不补则判定 No-Go）

| 文档 | 对应发现 | 说明 |
|---|---|---|
| `README.md` | #1 | 项目是什么 / 下载安装（**含「首次安装需联网」**）/ 3 步上手 / 截图 / 排障入口。素材已在库内（89 个跟踪 png，`func_test/01..15` 是成套 UI 截图） |
| `LICENSE` | #4 | 先决定许可，再考虑与 vendored GPLv2 的兼容 |
| `docs/user-guide.md`（用户手册） | #2 | 主界面 / 建分组 / 设热键 / 10 种执行模式怎么选 / 摇杆 / 备份恢复 |
| `docs/troubleshooting.md`（用户排障） | #3 | 纯 GUI 路径：热键不生效 / 打不开 / 配置丢失 / 按键不发送；末尾指向诊断信息页与日志目录 |
| `THIRD-PARTY-NOTICES.md` | #6 | AutoHotkey v2.0.26 / GPLv2 / 源码获取方式；并随安装包附 `license.txt` |
| 修复 `developer-guide.md` §4.8 与围栏 | #7 #8 | 存量文档的**阻断级**错误：排障路径写错 + 整节不渲染 |

### 5.2 应该补

| 文档 | 对应发现 |
|---|---|
| `CHANGELOG.md` + 用 `tauri.conf.json` 版本打 tag | #11 |
| `docs/README.md`（docs 索引：区分现行规范 vs 历史快照）+ `review/`、`superpowers/` 各一行冻结说明 | #13 |
| ADR-003～006：Rust+Tauri 选型、Named Pipe IPC、CSP 设定、GPLv2 打包合规；并把 ADR-001/002 从 Proposed 转 Accepted | #14 |
| 版本号统一为单一真值源（`index.html` 动态读取） | #9 |
| `AGENTS.md` §调试命令更新为 v4 路径 | #17 |
| 硬编码路径改相对/占位，`file://` 改相对链接 | #15 #19 |

### 5.3 可选

| 文档 | 说明 |
|---|---|
| `CONTRIBUTING.md` | 提交规范已有 `docs/commit-convention.md`，可补「新克隆后跑 `scripts/install-hooks.ps1`」这一条（`.git/hooks` 不进版本库） |
| `SECURITY.md` | 无遥测、本地桌面工具，优先级低 |
| 应用内「帮助」页 | 若能做，比外部文档更贴近用户；但需权衡 v4 冻结期投入 |

---

## 6. 「未发现问题」的检查项

（查过且没问题的靶点，避免只报坏消息）

1. **脚本引用全部真实存在** —— `scripts/` 与 `tools/` 下文档引用的 15 个脚本 15/15 存在；`bash -n` 7/7 通过；`py_compile` 4/4 通过。**没有「文档写了不存在的命令」这类问题**。
2. **日志文件未进版本库** —— `git ls-files logs/` 为空；`logs/app.log`（1.75MB）/ `logs/debug.log`（1MB）虽在磁盘上但未跟踪。**公开仓库无日志泄露**。
3. **`AutoHotkeydemo.zip`（65MB）未跟踪** —— `git ls-files | grep .zip` 为空。
4. **旧数字有快照警示的好实践存在** —— `docs/perf/key-latency-benchmark-2026-09-13.md:232-233` 明确写「这是本报告撰写当日的实测快照…当前值一律以 test-map.md 为准」。这正是其他历史文档该学而没学的做法。
5. **AGENTS.md 有防漂移意识** —— `:147` 明写「本文档只写指针、不复制数字——数字一旦复制就会过期」，并已清除滞留的旧值 `96.57%`。
6. **ADR 规范质量高** —— `docs/adr/README.md` 规定六必备节（含「负面后果必须写」「复审触发条件必须可判定」）、ADR 只增不改、要求「凡声称某机制存在必须给文件取证不得推断」。当天新建即达此水准，值得肯定。
7. **C3b 已把硬写基线数字登记在案** —— 实测 `python scripts/check-tech-debt.py --only c3` 输出「当前 3 项（新增 0 / 已登记 3）」并 PASS。旧数字问题**部分已被自动化兜住**。
8. **C11 打包资源自动核对通过** —— `#Include ↔ bundle.resources` 5 个被引用文件全部已打包，实测 PASS。
9. **§3.1.1 日志路径已订正且带「不要猜」警示** —— `:449-454` 明确列出两个易错点并指向诊断信息页。这是本次评估中**唯一一处「文档不可靠导致排障失败」已被修复**的地方，做法正确。
10. **诊断信息页设计合理** —— `index.html:344-360` 提供版本号 + 日志目录 + 一键复制 + 复制失败兜底提示，并注明「文件名形如 asd.YYYY-MM-DD.log（按天轮转，保留最近 7 份）」。在无遥测（TD-076）前提下这是拿事故信息成本最低的路径。
11. **`workspace-snapshot` 已清理并留说明** —— `docs/review/2026-08-20/fix-plan/workspace-snapshot/README.md` 解释了原用途与 TD-001 处置，避免后来者误改快照副本。
12. **CI 文档同步有人工清单（G4）** —— 虽不自动校验，但至少把「改代码要同步哪些文档」列成了 6 条明示清单，比完全没有强。

---

## 7. Go / No-Go 建议（仅文档维度）

### 建议：**No-Go**

**理由（按阻断级）：**

1. **用户装不起来** —— 无 README（#1）、无安装说明、WebView2 联网前置完全未告知（#5）。对一个已公开的桌面工具，这等于把陌生人挡在门外。
2. **用户用不起来** —— 全仓零用户手册（#2），应用内零帮助。
3. **用户出问题救不了自己** —— 唯一排障表全是内部 API（#3），而「配置在哪」这条给的路径还是错的（#7）。
4. **公开仓库无 LICENSE（#4）** —— 这是**合规硬阻断**，不是文档完善度问题：没有 LICENSE，仓库里的代码在法律上默认不可被他人使用/贡献/分发，与「已转公开仓库」的动作自相矛盾。
5. **分发 GPLv2 二进制却无任何声明（#6）** —— 与 #4 叠加，合规风险明确。
   ⚠️ 经与 archi 复核，本项已由「高」升为**阻断**：随附许可证文本与源码说明的义务（Q1）
   **不取决于**「自研代码是否被传染」（Q2），依据为 GPLv2 §1/§3 原文，详见 §8.4。
   **修复成本约 1 小时，且不论 Q2 结论如何都必须做 —— 不应等法务意见。**

**必须说明的一点**：以上阻断项**全部集中在「用户侧 + 合规」**，`AGENTS.md` / `developer-guide.md` / ADR 规范这批工程侧文档的成熟度反而超出预期。
所以这不是「文档整体不行」，而是**「内环很结实、外环没有门」**。

### 最小可达 Go 的补文档清单

按投入产出排序，完成前 6 项即可把文档维度从 No-Go 拉到「接近生产级」：

| 序 | 动作 | 预估投入 |
|---|---|---|
| 0 | **包内附 GPLv2 许可证文本 + `THIRD-PARTY-NOTICES.md`（#6，约 1 小时）** | **极小** |
| 1 | 补 `LICENSE`（先定许可，注意 GPLv2 兼容） | 小 |
| 2 | 修复 `developer-guide.md` §4.8 的日志/配置路径（2 行） | **极小** |
| 3 | 修复 `developer-guide.md:1600-1601` 围栏（补 1 行） | **极小** |
| 4 | 补 `README.md`（装 + 联网前置 + 3 步上手 + 截图 + 排障入口） | 中 |
| 5 | 补 `docs/troubleshooting.md`（用户向排障） | 中 |
| 6 | 统一版本号（TD-078）+ 加 CI 守卫（archi 估约 0.5 小时，与 C3/C3b/C13 同类） | 小 |
| 7 | 补 `docs/user-guide.md` | 中 |
| 8 | 补 `CHANGELOG.md` | 小 |
| 9 | 补 `docs/README.md` + 历史快照冻结说明 | 小 |
| 10 | ADR-001/002 转 Accepted，再补「分发形态 ADR」与「IPC 传输机制 ADR」 | 中 |

**第 2、3 项是几分钟的改动，却能立刻消除两处「照文档做必然失败」的坑，建议今晚就做。**
**第 0 项是唯一「不解决就不能合法分发」的合规项，成本约 1 小时，且不需等法务意见（见 §8.4）。**

### 若只能做一件事

**补 `README.md`。** 它是唯一能同时缓解 #1（没门）、#5（离线不知）、#3（排障无入口）三个阻断项的杠杆点，
且素材（截图）已经在仓库里了。

---

## 8. 增补：与架构师（archi）交叉复核后的收敛（2026-09-19）

第 5 章的「ADR 补立候选」已与 archi 对齐，收敛如下：

| 候选 | 收敛结论 | 来源 |
|---|---|---|
| ① Rust+Tauri 选型 | **不立新 ADR**，改为把研究稿结论链入 ADR-001 的「关联」段 | archi 判断 |
| ② Named Pipe IPC | **立**（优先级第 2，对应 archi 的 C3-1/C3-4 契约稳定性域） | archi 判断 |
| ③ CSP `unsafe-inline` | **不单独立**，并入「前端安全基线」或挂 ② 下（archi 定为 D2-1 中危、可接受） | archi 判断 |
| ④ NSIS 而非 MSI | 与 ⑤ **合并为一则「分发形态 ADR」** | archi 判断 |
| ⑤ GPLv2 打包分发 | **最高优先级** —— 唯一一条「不记录就有法律风险」的 | archi 判断 |

### 8.1 ① 的结论摘要 —— archi 已给出可直接用的草稿

archi 复核后指出：原文**其实有**短结论 —— §11.3「最终建议」（`:884-895`）是一张 8 行带
P0/P1/P2 优先级的表格（实测确认）。但它是「下一步做什么」，**不是**「为什么选 Rust+Tauri、否决了什么」；
真正需要蒸馏的是 §3.2 竞争力对比（`:117`）与 §4.6 Tauri vs 裸 wry（`:419`）。

因此本人「必须附 3–5 行结论摘要」的要求**仍然成立**，并由 archi 提供草稿（取证链挂 §3.2 / §4.6 / §11.3）：

> **选型结论**：以 Rust/Tauri 作策略层与 GUI，AHK 作执行层子进程。否决「纯 AHK 继续演进」——
> AHK 侧配置校验与 UI 无法与 Rust 侧共享真值；否决「裸 wry 自绘」——需手写 ~800 行胶水代码
> （窗口/打包/托盘/更新）。选择依据 §3.2 竞争力对比、§4.6 Tauri vs 裸 wry 决策表，落地建议见 §11.3。

⚠️ **修正本人上一版的一处表述**：原文写「没有一段可复制的短结论」**不够准确** ——
准确说法是「有结论表，但性质是**行动建议**而非**选型理由**」，所以需要蒸馏的对象不同。结论不变。

### 8.2 ② 的范围已收窄（archi 复核后修正，避免重复劳动）

研究稿 §12.1「Named Pipe API 选型」（`:905-918`）**已经是一则合格的迷你 ADR** ——
含 `local_socket` vs `named_pipe` 对比表 + 明确决策 + 4 条理由（**实测确认**）。
所以「用哪个 API」**已记录、不必重复立**；真正缺的是**传输机制层**选型
（为什么是命名管道而非 stdin/stdout / TCP / 共享内存 —— 全仓无对比表）。

本报告第 5.2 节的「② Named Pipe IPC」据此**收窄为「传输机制选型」**。

### 8.3 #10 已扩成一类：研究稿提过 → 落地没做 → 无留痕

archi 补充的第二例：**updater**。研究稿 `:895` 列「评估 Tauri 插件 … **updater 2.10.1** …」（🟢 P2）；
实测全仓 `Cargo.toml` 与 `tauri.conf.json` grep `updater` **零命中** —— 与 MSI 同一种病。

⚠️ **但两例强度不同，记录时勿等同**（本人意见）：
- **MSI（强）**：研究稿 `:781` 给出的是**明确建议 + 具体配置值** `"targets": ["nsis","msi"]`；
- **updater（弱）**：研究稿 `:895` 是 **P2「按需评估」**，同一行还列了 global-shortcut / dialog / fs。

若把 updater 也写成「决策被静默砍掉」，后人会误以为它曾是硬承诺。**建议 ADR 里分级写明原建议强度。**

**让该分级站住的佐证（archi 提出，本人复核确认）**：研究稿 `:895` 同一行并列 4 个插件，
其中 **3 个已落地且版本与建议值逐一对上**（**实测** `src-tauri/Cargo.toml:38-40`）：

| 研究稿建议值 | 实际落地 | 命中 |
|---|---|---|
| `global-shortcut 2.3.1` | `Cargo.toml:38` `tauri-plugin-global-shortcut = "2.3.1"` | ✅ |
| `dialog 2.7.1` | `Cargo.toml:39` `tauri-plugin-dialog = "2.7.1"` | ✅ |
| `fs 2.5.1` | `Cargo.toml:40` `tauri-plugin-fs = "2.5.1"` | ✅ |
| `updater 2.10.1` | 全仓 grep `updater` **零命中** | ❌ |

这条把性质钉死：**若该行是「承诺清单」，不会是 3/4 落地**（也不会恰好连版本号都照抄建议值）；
它确实是「按需评估」清单 —— **updater 是清单里唯一没被拾起的一项，而不是「被撤销的决策」**。

⚠️ **计数口径要写死，否则会被第 5 个插件推翻**（双方一致的防御性补充）：
「4 个插件、3 个落地」的计数**仅限研究稿 `:895` 该行所列**。
`Cargo.toml:37` 另有 `tauri-plugin-opener = "2"`，**不在该行内、不计入分母**。

**⚠️ 记录时必须区分「未采纳」与「被否决」（archi 提出，本人完全认同 —— 这是本条最关键的一层）**：

| 状态 | 含义 | 后人应有的动作 |
|---|---|---|
| **未采纳**（本案 updater） | 从未被评估过，只是没被拾起 | **应该重开评估** —— 没有历史结论可依据 |
| **被否决** | 评估后有意决定不做 | 除非复审触发条件出现，否则**不必重开** |

理由是：后人看到「同列 3 个都做了、就它没做」，**极易反推出「那一定是评估后被有意否决的」**，
从而不再重新考虑它。但事实是它**压根没被评估过**。这两种状态对「该不该重开」的结论**完全相反**。

**故 ADR 里的写法建议**：在「原建议强度」之外，**再单独标注「未采纳 / 被否决 / 已实现」三态**。
只写强度不写状态，仍会诱导后人做出反向的判断。

**本人补充：本案 MSI 不属于上述任何一态，必须单列**。
MSI 是「明确建议 + 具体配置值 → 落地只取一轨 → **砍的理由没留痕**」，
其状态是**「未知（无留痕）」**，既不能记成「未采纳」（暗示从没评估过），也不能记成「被否决」（暗示有结论）。
⚠️ **把它归入任一态都会掩盖 #10 本身** —— 该发现要暴露的正是「**我们不知道它是哪种**」。
故三态之外建议保留第四态：**「状态未知 —— 需补决策记录」**。

**四态的归类判据（archi 提出，本人作了一处修正）**：

archi 原判据是「**看原建议是否曾被明确提出** —— 提出过但结局无记录 = ④；从没被提出、只是在待评估清单里躺着 = ②」。

⚠️ **本人修正：光看「是否被列出」不足以区分 ② 与 ④**。反例正是本案 —— updater 在研究稿 `:895`
**也被列出来了，还带了具体版本号 2.10.1**，若按「是否被列出」判，它会被误判为 ④。

真正判据应是：**看该条目本身承诺的是「执行」还是「评估」**：

| 原条目性质 | 归属 | 本案 |
|---|---|---|
| 承诺**执行**（给出应做的结论 / 具体配置值） | 结局有留痕 → ① 或 ③；结局无留痕 → **④** | MSI（`:781` 给 `"targets": ["nsis","msi"]`） |
| 仅承诺**评估**（列入待评估清单） | 未被拾起 → **②** | updater（`:895` 行首即「⚠️ **评估** Tauri 插件 … **按需引入**」） |

判据落点是**原文动词**：研究稿该行写的是「评估 … 按需引入」——它承诺的是「去评估」，
而「从未被评估」正是 ② 的定义。同理，`:781` 给的是可直接写进配置的值，属承诺执行。

**对后人的动作（双方一致）**：
- ② （updater）：**应重开评估** —— 它从未被否决过，不该被当成历史结论。
- ④ （MSI）：**必须先补决策记录，才能判断它属于哪一态** —— 现在归类就是编造。

### 8.4 ⚠️ 对 #6 的严重度修正（archi 提出，本人复核后接受 —— 本次复核最重要的一条）

本人上一版写「若法律意见确认触发，#6 才升为阻断」—— **条件挂错了**，已改正。GPL 此处是**两个独立问题**：

- **Q1**：分发 GPLv2 二进制，是否须随附许可证文本 + 源码说明？→ **确定要**，与「Rust 是否被传染」无关。
  证据（**实测读原文**）：`license.txt:79-85`（§1）「give any other recipients of the Program
  **a copy of this License along with the Program**」；`:134-136`（§3）以目标码分发时须随附
  **完整对应源码**或**三年有效书面要约**。而 §2 的 mere aggregation（`:129-132`）
  免除的是「**另一件作品**」，**不免除对被分发的 GPL 程序本身的 §1/§3 义务**。
- **Q2**：自研 Rust 代码是否被传染、须以 GPL 开源？→ 这才是不确定的，且量级远大于 Q1。

**后果**：即使 Q2 答「否」，**Q1 依然成立且仍是阻断级**。把二者绑定在「法律意见是否确认传染」上的风险是 ——
读者会得出「也许根本没义务」，从而**推迟那个最便宜的修复**（包内附许可证文本，约 1 小时），
而该修复在 Q2 两种答案下**都必须要做**。

**故 #6 已由「高」改为「阻断」**，与 #4（无 LICENSE）并列，二者均属「不解决就不能合法分发」。
修复动作**不等待** Q2 的法务意见。

### 8.5 ⚠️ 次序：先把 ADR-001/002 转 Accepted（archi 提出，本人认同且认为比「补哪条」更重要）

当前 **2 条零条生效**，说明复核环节是断的；流程没跑通就补第 3/4/5 条，只会产出更多
「写了但不生效」的文档，反而稀释 ADR 机制的可信度。这与本报告 #14 一致，特此强化为**前置条件**。

同类观察（本人补充）：本仓已有 C3 / C3b / C13 自动守文档一致性，**唯独版本号没守** ——
archi 复核确认 CI 全文 grep `version` **无一处**做版本号交叉校验（`:857` 只是单纯读 `tauri.conf.json`，
不与 `index.html` / `AGENTS.md` / `package.json` 比对）。**「机制建了却没跑起来」与「ADR 建了却没 Accepted」是同一种病。**

---

## 附：本次评估的方法与证据说明

- 所有「实测」结论均来自：打开文件阅读、`ls`/`find`/`grep` 命令、`bash -n`/`py_compile` 语法校验、
  实跑 `scripts/check-tech-debt.py --only c3` 与 `--only c11`、以及 WebFetch 抓取 GitHub 仓库首页。
- 围栏渲染缺陷（#8）通过自写的 CommonMark 围栏规则模拟器判定，脚本留档于
  `deliverables/engineering-assurance/_docu_fencesim.py`（可复现）。
  ⚠️ 该结论为**规则模拟**，未在浏览器/GitHub 渲染器中二次确认；但「围栏总数 127 为奇数、不配对」是
  可直接复核的硬事实。
- GPL（#6）需分开标注：**Q1**（分发 GPL 程序是否须随附许可证+源码说明）的**条款依据为实测**
  （`AutoHotkey-2.0.26/license.txt:79-85` §1、`:134-136` §3、`:129-132` §2 mere aggregation 的免除对象）；
  **Q2**（自研代码是否被传染）属**推断**，需法务意见。文件缺失为**实测**。
  ⚠️ Q1 的结论不依赖 Q2，详见 §8.4。
- 四态归类判据（§8.3）经 archi 提出、本人修正后收敛；两例（MSI / updater）均已回原文逐字复核。
- `docs/` 下 md 文件实测 **84** 篇（主理人给的锚点为 81，差异不影响结论）。
