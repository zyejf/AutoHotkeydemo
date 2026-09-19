# ASD 技能管理器 v4.0 · 架构可持续性与分发合规 生产级评估

**评估人：** 阿奇（Archi）· 系统架构师
**日期：** 2026-09-19
**范围：** 分发合规（A）/ 发布与升级机制（B）/ 架构可持续性（C）/ 可观测性架构（D）
**仓库：** `D:\1demo\AutoHotkeydemo`（主 worktree，分支 `main`，origin `https://github.com/zyejf/AutoHotkeydemo.git`）

> **判定口径说明**：本评估按「**个人桌面工具**」定位判定，不套用 SaaS / 企业级服务的标准。
> 例如「没有 Prometheus + Grafana」「没有 APM / 分布式追踪」在本项目中**不计为缺陷**。
> 所有结论区分「实测」（有 `文件:行号` 或实跑命令输出）与「推断」（基于实测事实的推理，已标注）。

---

## 1. 本域结论

| 维度 | 结论 | 一句话理由 |
|---|---|---|
| **架构维度** | **接近生产级**（Conditional Go） | 5-crate workspace 分层清晰、进程隔离干净、日志 / panic 清理 / 依赖治理三项扎实；缺口集中在**契约版本化缺失**与**升级通道缺失**，属"可补的成熟度假口"而非架构性缺陷 |
| **合规维度** | **不达标**（No-Go，仅限"对外公开分发"这一动作） | 已公开仓库 + NSIS 打包 GPLv2 二进制，但**包内无 GPL 许可证文本、无源码获取说明、项目自身无 LICENSE、无第三方许可证清单**；四项均为低成本可修（合计约 1～1.5 人日） |

**关键前提**：TD-067（双校验器 7 处活跃分歧）尚未裁决，其定性是**正确性风险**而非架构风险，但会影响最终"生产级"结论，本评估不覆盖，见 `deliverables/engineering-assurance/a1-convergence-decision-2026-09-19.md`。

---

## 2. 发现清单表

| # | 严重度 | 维度 | 文件:行 或 证据 | 问题描述 | 实测/推断 | 生产级影响 | 建议 |
|---|---|---|---|---|---|---|---|
| A1-1 | **阻断**（仅对外分发） | 合规 | `tauri.conf.json:42`（`bundle.resources` 含 `ahk_executor/AutoHotkey64.exe`）；全仓 find 无 LICENSE/NOTICE（仅 `AutoHotkey-2.0.26/license.txt`） | **NSIS 安装包打包 GPLv2 二进制，但包内不含 GPL 许可证文本**。GPLv2 §1 要求随程序向接收者提供许可证副本 | 实测 | 对外公开分发的法律前置条件未满足；违规后果是 GPL 自动终止授权 | 在 `tauri.conf.json` 加 `bundle.license` 指向 GPLv2 文本，或把 `license.txt` 加入 `bundle.resources`（详见第 3 章） |
| A1-2 | **高** | 合规 | `tauri.conf.json:35-44`（8 项 resources，无一项是许可证/说明）；`src-tauri/` 下 find 无 `*licen*`/`*notice*`，无 `.nsi` 模板 | **安装包内无任何"GPL 源码获取说明 / 书面要约"**。GPLv2 §3 要求提供完整对应源码或 3 年有效的书面要约 | 实测 | 同上。所幸源码物料本身是齐的（见"未发现问题"#9），只差一句说明 | 在安装包内附 `THIRD-PARTY-NOTICES.txt`，写明 AHK v2.0.26 为 GPLv2、源码获取地址（本仓库 `AutoHotkey-2.0.26/` 或官方 tag v2.0.26） |
| A1-3 | 中 | 合规 | 无 `.gitmodules`（实跑 `cat .gitmodules` → No such file）；`git ls-files AutoHotkey-2.0.26 \| wc -l` → **181** | AHK 是 **vendored 源码**（非 submodule），且已随公开仓库分发 181 个文件（其中 `source/` 168 个） | 实测 | 中性偏正面：既已公开分发源码，GPL §3 的"提供源码"物料天然齐备；但也意味着**义务已经触发**（不是"还没分发所以没关系"） | 在 README / NOTICE 中显式声明 vendored 路径与版本，避免他人误以为是本项目自研代码 |
| A1-4 | 中 | 合规 | `.gitignore:35` `*.exe`；`git check-ignore -v` 命中 `ahk_executor/AutoHotkey64.exe` | **打包的 exe 本身不入库**（被 gitignore），但**源码入库** | 实测 | 形成"源码公开、二进制只在安装包里"的状态 —— GPL §3 义务落在安装包上，而安装包恰好没带说明（即 A1-2） | 同 A1-2 |
| A1-5 | 中 | 合规 | `md5sum` 实跑：`asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe` 与 `AutoHotkey-2.0.26/AutoHotkey.exe` 均为 `52086b801555ef17e4b51e0acffc70b3`；CI `ci.yml:821-840` 从 `holy-tao/install-autohotkey@v2.1.0` 现下载 v2.0.26 | 打包的是**未修改的官方 AHK v2.0.26 二进制**（字节级一致，且 CI 现下载而非自行编译） | 实测 | **正面**：无"自行修改后未开源"的风险，provenance 干净 | 保持；在 NOTICE 里写死版本号 2.0.26 便于追溯 |
| A2-1 | **高** | 合规 | 仓库根无 `LICENSE`/`README`/`CHANGELOG`（全仓 find 仅 `AutoHotkey-2.0.26/license.txt` + `lib_pcre` 的两个文件） | **公开仓库无 LICENSE = 默认保留所有权利**，他人无法合法复制/修改/分发，也无法安全贡献 | 实测 | 与"已于 2026-09-16 转公开"这一事实直接冲突；外部贡献者无授权依据；fork/自建无法律依据 | 为**自研代码**选 MIT 或 Apache-2.0（推荐 MIT，与 AHK 的 GPLv2 不冲突，因为二者是独立程序 —— 见第 3 章）；vendored AHK 部分单独标注保持 GPLv2 |
| A3-1 | 中 | 合规 | `ci.yml:386-387` 有 `cargo audit`（阻断）、`ci.yml:364-376` 有 `npm audit`（阻断）；但全仓 find 无 `deny.toml`/`about.toml`/`license-checker` 配置 | **有漏洞扫描，无许可证合规扫描**。这是两件不同的事：audit 查 CVE，license 查授权兼容性 | 实测 | 供应链**安全**有闸门，供应链**合规**无闸门；一旦引入 GPL/AGPL 依赖无法自动发现 | 加 `cargo-deny`（含 `bans`/`licenses`/`sources` 三段）；npm 侧加 `license-checker` 或 `pnpm licenses` 生成清单 |
| B1-1 | **高** | 发布 | `tauri.conf.json` 全文无 updater 段；`src-tauri/Cargo.toml:17-45` 依赖清单无 `tauri-plugin-updater`；grep `check_update\|releases/latest\|github.com/zyejf` 在 `src-tauri/src`、`asd-tauri/src`、`package.json` 均无结果。**补充证据**：`docs/superpowers/specs/2026-05-28-rust-rewrite-research.md:895` §11.3 最终建议表列出「⚠️ **评估** Tauri 插件 \| 按需引入…（global-shortcut 2.3.1、**updater 2.10.1**、dialog 2.7.1、fs 2.5.1）\| 🟢 P2」 | **无自动更新机制**：用户装了 0.1.0 之后无法收到升级提示，只能人工重新下载安装包。**注意：updater 曾被列入研究阶段的待评估项，最终未落地** —— 但**强度弱于 B4-1 的 MSI**，见下方强弱分级说明 | 实测 | 对"生产级分发"是硬伤：安全修复无法触达已装机用户；用户也不知道自己装的是哪一版 | 对外分发前至少接 `tauri-plugin-updater`（需签名配套）；短期可先做"启动时检查 GitHub Release 版本号并提示"（轻量，不需签名） |
| B1-2 | **高** | 发布 | `ci.yml:905-913` 仅 `actions/upload-artifact@v4`，`retention-days: 90`；ci.yml 全文共 **913 行**，末尾即 upload-artifact，**无 GitHub Release 发布步骤**（grep `gh-release\|softprops\|gh release\|create-release` 无结果） | **唯一分发渠道是 90 天过期的 CI 产物**，且无公开 Release 页。90 天后安装包不可获取，回滚窗口也随之消失 | 实测 | 比"没有 updater"更严重：**连"让用户重新下载"的落点都没有**；与 `ci.yml:904` 注释里"90 天覆盖回滚窗口"的设计意图矛盾（artifact 过期即回滚不了） | 增加发布到 GitHub Releases 的步骤（产物永久保留 + 形成事实上的下载页），或改投对象存储 |
| B1-3 | 中 | 发布 | `ci.yml:763` 团队自注：「[1] 产物**未做代码签名 / 未接 updater**（无证书、无密钥、无更新通道）」；`ci.yml:890` 摘要写明「⚠️ 未签名」 | **安装包未签名** → Windows SmartScreen「未知发布者」告警，用户需手动「更多信息 → 仍要运行」 | 实测 | 对外分发时转化率损失，且告警易被误判为恶意软件（对**按键模拟**类工具尤其敏感 —— 这类工具本身就容易被杀软误报） | EV 代码签名证书 + `tauri.conf.json` 的 `bundle.windows.certificateThumbprint`（团队已在 `ci.yml:766-767` 写明路径） |
| B3-1 | 中 | 发布 | `tauri.conf.json:52-55` `webviewInstallMode.type = downloadBootstrapper` + `silent: true`；`ci.yml:769-774` 自注「⇒ 代价转移到了终端：**离线 / 内网隔离环境装不上**」 | 无 WebView2 运行时的机器需**联网下载**；`silent:true` 下下载失败无 UI 提示 | 配置实测；**失败表现属推断** | 离线/内网用户装不上或装完启动不了，且**无明确降级提示**，排障困难 | 目标环境不能联网则改 `offlineInstaller`（+约 130MB）或 `embedBootstrapper`；至少在 README 写明前置条件 |
| C1-1 | 中 | 架构 | `ADR-001-v3-ahk-stack-positioning.md:3` 与 `ADR-002-hotkey-merger-merge-semantics.md:3` **两者均为** `**状态:** Proposed`；均署「待工程督导复核」 | **现有 2 条 ADR 没有一条被 Accepted** —— 不是"某条 ADR 未生效"，而是 ADR 流程**从未走完过一次**（全仓 `docs/adr/` 仅 README + ADR-001 + ADR-002 三个文件） | 实测 | ADR 作为"决策记录"的机制尚未真正运转：写了 2 条高质量提案，但零条产生约束力 | 先走完复核把 ADR-001/002 转 Accepted，验证流程能跑通，再谈补新 ADR |
| C1-2 | 中 | 架构 | `ci.yml` jobs 清单：gates / js-lint / coverage / security-audit / miri / fuzz / bench / ahk-bench / release —— **无冻结守卫 job** | **冻结无执行手段**：没有 CI 检查阻止向 v3 AHK 生产目录新增功能，纯粹靠人工自觉 | 实测 | 「僵尸代码复活」风险**客观存在**（推断）：ADR 未生效 + 无 CI 守卫 + `AGENTS.md:9` 仍写「作为独立运行模式保留」且未提冻结 | 加轻量守卫 job：对 `infrastructure/`、`domain/`、`application/`、`presentation/` 的 PR 变更要求显式 label 或 CODEOWNERS 复核 |
| C2-1 | 低 | 架构 | `src-tauri/Cargo.toml:38` `tauri-plugin-global-shortcut = "2.3.1"` vs `package.json:24` `"@tauri-apps/plugin-global-shortcut": "^2.3.2"` | Rust 侧与 npm 侧同一插件**版本约束错位**（2.3.1 vs ^2.3.2） | 实测 | 轻：Tauri 插件两端版本需匹配，错位可能引入 IPC 行为差异 | 统一为同一版本号 |
| C3-1 | 中 | 架构 | `asd-ipc-protocol/src/message.rs:5-23` `IpcMessage` 结构体字段（`id`/`type`/`seq`/`ack_seq`/`action`/`keys`/`delay`/`status`/`data`）——**无 version 字段**；grep `handshake\|version` 在 `src-tauri/src/infrastructure/ipc.rs` 与 `ahk_executor/ipc_client.ahk` 均无结果 | **IPC 消息格式无版本化，无握手/版本协商** | 实测 | 当前不发作（脚本随包整体替换），但是**未来升级的隐患**：一旦 IPC 格式变更，无法拒绝旧对端，只会出现静默解析失败 | 加 `version` 字段 + 启动时握手校验；短期至少在 `r#type` 未知时显式报错而非静默丢弃 |
| C3-2 | 中 | 架构 | `asd-domain/src/config.rs:42` `pub version: Option<String>`、`:70` 默认写入 `"4.0"`；但全仓 grep 生产代码**无任何读取/迁移/校验**（仅 `config.rs:1077` 与 `config_compat_tests.rs:27` 两处测试断言） | **配置 version 字段是"只写不读"的死元数据** —— 有版本号但无版本校验、无迁移逻辑 | 实测 | 升级后若配置语义变化，旧配置会被静默按新语义解释，无告警、无迁移路径 | 二选一：① 补全读取 + 迁移/拒绝逻辑；② 明确废弃该字段（避免给人"已有版本化"的错觉） |
| C3-3 | 低 | 架构 | `tauri.conf.json:36-43`：AHK 脚本作为 bundle resource 随安装包整体替换 | **缓解因素**：正常情况下不会出现「新版 Rust + 旧版 AHK 脚本」混跑 | 实测 | 降低 C3-1 的即时风险 | 保持；但需在文档中明确"AHK 脚本不可被用户手工替换" |
| C3-4 | 中 | 架构 | `ADR-002-hotkey-merger-merge-semantics.md:46-54`：「Rust 侧 `IpcMessage::hotkey_event` 只接受单个热键 / AHK 侧 `SendHotkeyEvent(keys*)` 是可变参数」；`:52` 「实测当前唯一生产调用点 `hotkey_hook.ahk:129` 传的是单键…**潜伏**断点，不是已发生的缺陷」 | **跨语言 IPC 契约已存在一处被记录在案的潜伏断点**：Rust 用 `keys[0]` 作身份键，AHK 侧可变参可发多键。目前生产未触发，一旦触发则身份与载荷不一致 | 实测（ADR-002 已取证；本文复核 `hotkey_merger.rs:28-33` `keys.as_ref().and_then(\|k\| k.first())` 一致） | 这是 C3-1（无版本/无握手）的**具体兑现路径**：正因为没有版本协商与未知字段校验，这类不对称只能靠"人工记得"来防 | 推进 ADR-002 的 S4（与 AHK 侧对齐 `keys` 取值范围）；同时实施 C3-1 的版本化是**根治**手段 |
| B4-1 | 低 | 发布 | `docs/developer-guide.md:1673` 「MSI 安装包: src-tauri/target/release/bundle/msi/」；`tauri.conf.json:27` `"targets": ["nsis"]`；`docs/superpowers/specs/2026-05-28-rust-rewrite-research.md:781` 建议 `"targets": ["nsis", "msi"]` | 文档声称会产出 MSI，配置只产 NSIS → **MSI 永远不会产出**（死路径）。且研究稿推荐 NSIS+MSI 双轨，实际只取 NSIS，**"为什么砍掉 MSI"无决策记录** | 实测 | 轻：不影响功能。但反映一类问题——打包形态这类**不可逆性较高的决策**没有 ADR | 修文档；并补 ADR 记录"NSIS 而非 MSI"的决策与理由（见第 6 章） |
| D2-1 | 中 | 安全 | `tauri.conf.json:22` `"csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"` | CSP 放行 `style-src 'unsafe-inline'` —— 放宽了内联样式执行，属**安全权衡**但无任何决策记录 | 实测 | Tauri 桌面应用的前端是本地打包资源，攻击面远小于 Web；`'unsafe-inline'` 通常用于满足框架的运行时样式注入。风险**可接受但应留痕** | 补 ADR 记录该权衡及"代价是什么、什么情况下需要收紧"（见第 6 章） |
| D1-1 | 低 | 可观测 | `logging.rs:11-12` 文档写「本仓库目前选择记 stderr 后继续」；但 `lib.rs:705` `infrastructure::logging::init(app).map_err(...)?` → **失败即中止启动** | **文档与代码行为不一致** | 实测 | 若 `app_data_dir` 不可写（`logging.rs:19-26` 的 `create_dir_all` 失败），应用**拒绝启动**且无友好提示。currentUser 安装下概率低 | 修正文档；或改为降级到 stderr 后继续启动（更符合桌面工具容错预期） |
| D1-2 | 低 | 可观测 | `logging.rs:28-34` 日志落在 `app_data_dir`，无导出入口 | 无「一键导出日志」入口，故障排查需用户手动翻 `%APPDATA%\com.asd.tauri\` | 实测 | 个人工具场景下支持成本高（用户找不到日志 → 只能靠描述复现） | 加一个「打开日志目录」或「导出诊断包」菜单项（`tauri-plugin-opener` 已引入，成本极低） |
| TD-078 | 中 | 发布 | `index.html:7` `<title>技能管理器 v3.0</title>`、`:16` `v3.0 Tauri`；`tauri.conf.json:4`/`Cargo.toml:12`/`package.json:4` 均为 `0.1.0`；`AGENTS.md:3` 写 v4.0。**补充证据**：CI 全文 grep `version` 无一处做版本号一致性校验（`ci.yml` 中所有 version 命中均为工具版本或 `:857` 单纯读取 `tauri.conf.json` 版本，**不交叉校验** index.html / AGENTS.md / package.json） | 用户**实际看到的是 "v3.0"**，但包名是 0.1.0、文档写 v4.0 —— 三方口径不一致，且**无任何自动化守卫**（本仓已有 C3/C3b/C13 等一致性守卫，唯独版本号没守 —— 该观察由 Docu 提出，本文复核确认） | 实测 | 升级场景下用户无法辨识版本；对外分发时"版本号"失去意义 | ① 统一单一真值源：以 `tauri.conf.json` 为准，UI 从 `getVersion()` 动态读取，禁止硬编码；② **加 CI 守卫**交叉校验四处口径（与 C3/C3b/C13 同类做法，成本约 0.5 小时） |

---

## 3. GPL 合规专章（A1 完整取证与推理链）

> ⚠️ **免责声明：本章是事实取证 + 常识性许可证分析，不是法律意见，不构成法律建议。**
> GPLv2 的适用范围与传染性判断在不同法域存在争议，且本项目涉及"脚本是否构成衍生作品"这一 GPL 社区长期未决问题。
> **建议在对外公开分发前由专业法务复核。** 本章的价值在于把事实与推理链摆清楚，让法务能直接在此基础上判断，而不必从零取证。

### 3.1 取证链（全部实测）

**第 1 环 — 打包了 GPLv2 二进制吗？**

```
tauri.conf.json:35-44  bundle.resources = [
  ahk_executor/executor.ahk, ipc_client.ahk, hotkey_hook.ahk, sender.ahk,
  joystick.ahk, high_res_clock.ahk,
  ahk_executor/AutoHotkey64.exe,   ← :42  打包 GPLv2 二进制
  ahk_executor/asd_executor.bat
]
tauri.conf.json:27  bundle.targets = ["nsis"]
```

**第 2 环 — 这个二进制是 GPLv2 的吗？是。**

```
AutoHotkey-2.0.26/license.txt:1-2
    GNU GENERAL PUBLIC LICENSE
       Version 2, June 1991
```
且 `grep -in "exception" license.txt` 无针对脚本的例外条款（仅 `:110` 交互式程序显示条款，与脚本无关）。

**第 3 环 — AHK 是 submodule 还是 vendored 源码？是 vendored。**

```
$ cat .gitmodules          → No such file or directory
$ git ls-files AutoHotkey-2.0.26 | wc -l  → 181
  其中 source/ 168 个，另含 AutoHotkeyx.sln / AutoHotkeyx.vcxproj /
  Config.vcxproj（编译脚本）、license.txt
```
⇒ 非 submodule；**完整源码（含 GPL §3 要求的"控制编译与安装的脚本"）已随公开仓库分发**。

**第 4 环 — 打包的二进制与 vendored 源码对应吗？对应，且是官方未修改版本。**

```
$ md5sum asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe  → 52086b801555ef17e4b51e0acffc70b3
$ md5sum AutoHotkey-2.0.26/AutoHotkey.exe                    → 52086b801555ef17e4b51e0acffc70b3
CI: ci.yml:821-840  uses: holy-tao/install-autohotkey@v2.1.0  with version: '2.0.26'
```
⇒ 字节级一致，且 CI 现下载官方发行版，**非自行编译、非修改版**。provenance 干净。

**第 5 环 — 二进制本身入库了吗？没有（但这不改变义务）。**

```
.gitignore:35   *.exe
$ git check-ignore -v asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe
  → .gitignore:35:*.exe
```
⇒ 二进制只随 NSIS 安装包分发，不随 git 分发。**GPL §3 的义务因此落在安装包上。**

**第 6 环 — 安装包里有许可证文本或源码说明吗？没有。**

```
$ grep -n "license" tauri.conf.json        → 无结果（无 bundle.license 键）
$ find src-tauri -iname "*licen*" -o -iname "*notice*"  → 无结果
$ find src-tauri -iname "*.nsi" -o -iname "*installer*" → 无结果（无自定义 NSIS 模板）
bundle.resources 8 项中无任何许可证/说明文件
```
⇒ **NSIS 安装包内既无 GPLv2 许可证文本，也无源码获取说明/书面要约。**

**第 7 环 — 项目自身有 LICENSE 吗？没有。**

```
全仓 find LICENSE*/LICENCE*/COPYING*/NOTICE*/THIRD-PARTY*/about.toml/deny.toml
  → 仅 AutoHotkey-2.0.26/license.txt、AutoHotkey-2.0.26/source/lib_pcre/pcre/{LICENCE,COPYING}
```
⇒ 项目自研代码无任何许可证声明。

### 3.2 推理链（推断部分已标注）

**推论 1：Rust 侧代码大概率不被 GPL 传染（推断）**

依据（实测）：
- Rust 通过**独立 OS 进程**调用 AHK —— `watchdog.rs:324` `let mut cmd = Command::new(&program);`
- `build.rs:1-14` 只有 `tauri_build::build()` 与 manifest 嵌入，**未链接任何 AHK 代码**
- 双侧通过环境变量 token（`watchdog.rs:329` `cmd.env("ASD_AUTH_TOKEN", ...)`）与命名管道 IPC 通信（`:333-336`）

GPLv2 §2 末段规定：将独立作品与受保护程序**仅在同一存储介质上聚合**（mere aggregation），不使该独立作品受本许可证约束。本项目 Rust 与 AHK 是 arm's-length 的进程间通信，符合"独立程序 + 聚合分发"的典型形态。

⇒ **推断**：`asd-domain`/`asd-application`/`asd-ipc-protocol`/`src-tauri` 的 Rust 代码**大概率不构成 AHK 的衍生作品**，可自行选择许可证（如 MIT）。
**不确定性**：此判断依赖"进程边界 + 无链接 + 无共享内存数据结构"的完整性；若未来改为静态链接 AHK 或共享复杂内部结构，结论会变。

> ### ⚠️ 必须拆开的两个问题（回应 Docu 对严重度轴的提问）
>
> 合规判断里最容易混为一谈的是下面两问，它们的**确定性不同、后果量级也不同**：
>
> | | 问题 | 确定性 | 后果 |
> |---|---|---|---|
> | **Q1** | 分发 GPLv2 二进制，是否须随附许可证文本与源码获取说明？ | **确定：是。** 与"Rust 侧是否被传染"**无关** | 补文本 + 补 NOTICE，**约 1 小时** |
> | **Q2** | 本项目自研代码是否因调用 AHK 而被 GPL 传染，须以 GPL 开源？ | **不确定**（即推论 1），需法律意见 | 若答"是"，整个许可证策略需重做 —— **量级远大于 Q1** |
>
> 关键点：GPLv2 §2 的 mere aggregation 条款表述为"不使**其他作品**受本许可证约束" —— 它免除的是**另一件作品**，**并不免除你对被分发的 GPL 程序本身的 §1/§3 义务**。
> 因此**不应**把 A1-1 / A1-2 的严重度挂到"法律意见是否确认传染"这个条件上：
> - 即便 Q2 最终答"否"（Rust 不受传染），**A1-1/A1-2 依然成立**，仍属阻断级；
> - Q2 决定的是另一件事：**自研代码要不要开源、以什么协议开源**。
>
> 把两者绑在一条条件上的风险是：读的人可能得出"也许根本没有义务"，从而**推迟那个最便宜的修复**（包内附许可证文本）。而该修复在 Q2 的两种答案下**都必须要做**。

**推论 2：分发 AutoHotkey64.exe 本身，GPLv2 §1 与 §3 的义务已触发（推断，但前提实测）**

无论推论 1 是否成立，**只要分发了 GPLv2 二进制，对该二进制的义务就独立存在**：
- **§1**："give any other recipients of the Program a copy of this License along with the Program" → **当前未履行**（第 6 环）
- **§3**：须随附完整对应源码，或随附 3 年有效的书面要约 → 源码物料齐备（第 3 环）且公开可得，**但安装包内无任何指向说明** → **当前未完整履行**（第 6 环）

**推论 3：AHK 脚本（executor.ahk 等）的地位不确定，建议按保守口径处理（推断）**

脚本是否构成解释器的衍生作品，GPL 社区长期有争议，无定论；且 AHK 的 `license.txt` 未就此作例外声明（第 2 环）。
保守口径：即使认为脚本受 GPL 约束，**脚本已随公开仓库分发**（`git ls-files ahk_executor/` 含 8 个文件），义务大体可满足。

⇒ 实务建议：不必为脚本单独改变许可证策略，但应在 NOTICE 中一并说明。

**推论 4：项目无 LICENSE 与 GPL 义务不冲突，但是独立的严重问题（推断）**

GPL 只约束"被传染的部分"，不要求整个仓库都 GPL。因此"自研代码无 LICENSE"本身**不产生额外的 GPL 违规**。
但它与"仓库已于 2026-09-16 转公开"直接冲突：无 LICENSE = 默认保留所有权利，外部人员无法合法使用、复制、修改或贡献。

### 3.3 合规缺口汇总与修复建议（按成本排序）

| 优先级 | 动作 | 预计成本 | 解决 |
|---|---|---|---|
| P0 | 在 `tauri.conf.json` 加 `bundle.license`（指向 GPLv2 文本），或将 `AutoHotkey-2.0.26/license.txt` 加入 `bundle.resources` | ~0.5 小时 | A1-1（§1） |
| P0 | 在包内附 `THIRD-PARTY-NOTICES.txt`：AHK v2.0.26 · GPLv2 · 源码获取地址（本仓库 `AutoHotkey-2.0.26/` 或官方 tag v2.0.26） | ~0.5 小时 | A1-2（§3） |
| P0 | 仓库根加 `LICENSE`（自研代码建议 MIT），并在 README 声明 vendored AHK 部分为 GPLv2 | ~1 小时 | A2-1 |
| P1 | 加 `cargo-deny` 配置（licenses 段）+ npm 侧 `license-checker` 生成第三方清单 | ~0.5 天 | A3-1 |
| P1 | **法务复核本章**（重点确认推论 1 的"进程边界不构成衍生作品"） | — | 全章不确定性 |

**合计约 1～1.5 人日 + 一次法务复核。** 这是本次评估中**性价比最高**的一组修复：成本极低，但消除的是唯一一类"对外分发即触发"的风险。

---

## 4. 「未发现问题」的检查项

按要求，查过且没有问题的靶点同样列出：

| # | 检查项 | 证据 | 评价 |
|---|---|---|---|
| 1 | **日志基础设施** | `logging.rs:28-34` 按天滚动、`max_log_files(7)`；`:36` `RUST_LOG` 可覆盖；`:72-77` 非法 spec 回落 `info` 而非 panic；`:79-112` 三条契约测试 | **超出预期**。7 天轮转 + env 覆盖 + 非法输入兜底 + 单测，桌面工具里属良好实践 |
| 2 | **崩溃时子进程清理** | `lib.rs:707-708` 「I36 补偿机制：注册 panic hook，确保崩溃时清理子进程」`register_panic_hook()`；实现见 `watchdog.rs:1072-1114` | 已覆盖桌面工具最关键的一类崩溃副作用（残留僵尸 AHK 进程），且有测试（`watchdog.rs:1918-1931`） |
| 3 | **IPC 认证** | `watchdog.rs:329` `cmd.env("ASD_AUTH_TOKEN", auth_token)`；`:285-287` 空 token 直接报错 | 子进程接入需 token，避免本地任意进程冒充执行器 |
| 4 | **心跳/活跃度检测** | `message.rs:140` `IpcMessage::heartbeat`；`ipc.rs:175` `set_heartbeat_callback`、`:755` 回调分发 | 已具备 liveness 信号，不需要额外引入 |
| 5 | **无遥测/崩溃上报** | 全仓无 Sentry/telemetry 依赖 | **对个人按键模拟工具是正确的隐私姿势**。本项目处理的是用户输入模拟，默认不上报是恰当的；不应因"没有遥测"扣分 |
| 6 | **Rust 锁文件入库** | `git ls-files Cargo.lock` → 有；144KB | 构建可复现 |
| 7 | **npm 锁文件入库** | `git ls-files package-lock.json` → 有 | 构建可复现 |
| 8 | **依赖自动更新** | `.github/dependabot.yml:14-67` 覆盖 cargo / npm / e2e-npm / github-actions 四类，周更（Actions 月更），`open-pull-requests-limit: 5` | 配置克制且合理（限流 5 个是"能真正审完"的量，设计有思考） |
| 9 | **GPL §3 源码物料齐备** | `git ls-files AutoHotkey-2.0.26` → 181 文件，含 `source/` 168 个 + `.sln`/`.vcxproj` 编译脚本 | 第 3 章推论 2 的关键缓解因素：不是"源码拿不出来"，只是"没在包里说明" |
| 10 | **vendored 二进制 provenance** | md5 一致 + CI 现下载官方版本（见 3.1 第 4 环） | 无"修改后未开源"风险 |
| 11 | **watchdog 进程清理的安全约束** | `watchdog.rs:864`、`:1730-1738` 明确禁止把 `AutoHotkey64.exe` 放入 `STALE_PROCESS_NAMES`，理由「否则会误杀用户其他 AHK 脚本」，且有断言守卫 | 有意识避免了全局进程名误杀，考虑周到 |
| 12 | **前端依赖面** | `package.json:14-26`：devDeps 4 个、deps 5 个，**无 React/Vue/Svelte 等框架** | 前端供应链攻击面极小，npm audit 阻断生产依赖已足够 |
| 13 | **ADR-001 决策质量** | 含三选项对比表、决策、正/负面后果、S1-S3 后续步骤、5 条复审触发条件 | 决策记录本身写得扎实（问题在于**状态未 Accepted + 无执行手段**，见 C1-1/C1-2，而非文档质量） |
| 14 | **配置 v3.0 向后兼容** | `config_compat_tests.rs` 存在（9282 字节）；`config.rs:1066-1077` 断言 v3.0 配置可解码 | 有跨版本配置的回归保护（但注意：version 字段只写不读，见 C3-2） |
| 15 | **CI 漏洞闸门** | `ci.yml:386-387` `rustsec/audit-check@v2`（阻断）；`:364-369` npm audit 生产依赖 high 级阻断 | 供应链**安全**有闸门（缺的是**许可证**闸门，见 A3-1） |
| 16 | **release job 的静默失败防护** | `ci.yml:862-866` 未找到安装包即 `throw`；`:878-882` 显式写无 BOM UTF-8 避免校验工具读不出首行 | 对"跑绿了但没产物"这类最危险的静默失败有硬防护，设计考虑细致 |
| 17 | **ADR-002 主动记录了潜伏断点** | `ADR-002:46-54` 在问题**尚未发生**时就记录了 `keys[0]` 与 AHK 可变参的不对称，并明确区分「潜伏断点，不是已发生的缺陷」；`:163-171` 5 条复审触发条件含「AHK 侧开始发多键事件时 S4 必须提前」 | 能主动标记"还没炸但会炸"的点并给出触发条件，是成熟度的体现。问题同样在**流程**（未 Accepted、S4 未排期）而非内容 |
| 18 | **ADR-002 的零行为变更约束** | `ADR-002:109-114` 明确「只加观测，不改变任何行为」，并指出「计数器的公开会改 API 表面…故本次不改代码」 | 架构决策能把"观测需求"与"行为变更"切开、并自我设限不改代码，避免了"顺手改一下"的典型失控 |
| 19 | **研究稿 §12.1 已是一则合格的迷你 ADR** | `2026-05-28-rust-rewrite-research.md:905-918`：`local_socket` vs `named_pipe` 对比表 + 明确「**决策**：使用 `local_socket` API」+ 4 条理由 + feature 启用说明 | 说明团队**有能力**写选型记录（有对比表、有决策、有理由、有落地细节）。因此第 6 章中"IPC 缺 ADR"的判断必须**收窄**到机制层（Named Pipe vs stdin/stdout/TCP），API 层已覆盖，不应重复劳动 |

---

## 5. Go / No-Go 建议

### 合规维度：**No-Go**（针对"对外公开分发"这一动作）

**理由**：安装包打包 GPLv2 二进制，但包内无许可证文本、无源码获取说明；仓库已公开却无自身 LICENSE；无第三方许可证清单。

**但这不是一个"重"阻断**：四项缺口合计约 **1～1.5 人日** 即可闭环，且不需要改动任何架构或代码逻辑。
**建议定性为「低成本必做项」而非「架构性阻断」** —— 即：不应因此推翻整个项目，但**在完成前不应公开分发安装包**。

**放行条件（全部满足即可转 Go）**：
1. NSIS 包内附带 GPLv2 许可证文本（A1-1）
2. 包内附 `THIRD-PARTY-NOTICES.txt` 含 AHK 源码获取地址（A1-2）
3. 仓库根补 `LICENSE`，并在 README 区分自研代码许可证与 vendored AHK 的 GPLv2（A2-1）
4. 法务复核第 3 章推论 1（进程边界是否构成"非衍生作品"）—— 这一条若被推翻，整个许可证策略需要重做，故建议**优先于 1-3 执行**

### 架构维度：**Conditional Go**（有条件放行）

**理由**：核心架构质量是好的 —— 5-crate workspace 分层、Rust/AHK 进程隔离、日志 + panic 清理 + 心跳、依赖治理（锁文件 + dependabot + audit）四项都扎实，且明显经过深思（多处注释体现了"为什么这么做"和"什么情况下会失效"）。
缺口集中在**成熟度**而非**架构正确性**：契约无版本化、ADR 未生效无执行手段、升级通道缺失。

**放行条件**：
- **内部 / 小范围分发**：可直接 Go。上述缺口在此场景下影响有限。
- **对外大规模分发**：需先补 ① 公开 Release 页（解决 B1-2 的 90 天过期问题，这是**最紧急**的一项 —— 它使"回滚窗口"和"用户获取"同时失效）；② 版本号统一（TD-078）。
- **建议排期但不阻塞**：IPC 版本化（C3-1）、配置版本读写闭环（C3-2）、ADR-001 转 Accepted + CI 冻结守卫（C1-1/C1-2）、代码签名（B1-3）。

### 一句话总结

> **架构是"接近生产级"的，且底子比预期好；合规是"不达标"的，但只差最后一公里且修复极便宜。**
> 真正的卡点不是架构设计能力，而是**对外分发的工程配套（Release 页 / 签名 / updater）与法务合规文本**这两件"非代码"的事。

---

## 6. ADR 补立建议（回应 Docu 的第 3 点）

Docu 列出 5 项"缺 ADR 的重要决策"并问是否值得立。按**我的域（架构 / 发布 / 合规 / 可观测）**给出判断，按价值排序：

| 排序 | 候选 ADR | 是否建议立 | 理由 |
|---|---|---|---|
| 1 | **⑤ 打包并分发 GPLv2 的 AutoHotkey64.exe** | **强烈建议，最高优先级** | 这是唯一一条"**不做记录就有法律风险**"的决策。本文第 3 章的完整取证链（7 环）应直接固化成 ADR：记录 vendored 而非 submodule、md5 一致性、CI 现下载官方版、§1/§3 义务的履行方式（包内附许可证 + NOTICE 指向）。**并且它是放行对外分发的前置条件之一** |
| 2 | **② IPC 机制选型 + 契约演进** | **建议立**（但需**收窄范围**） | 直接对应本文 C3-1/C3-4：IPC 无版本化、无握手，且已有一处记录在案的潜伏断点。**范围修正**：研究稿 `§12.1`（`:905-918`）**已经**是一则合格的迷你 ADR（有 `local_socket` vs `named_pipe` 对比表 + 明确决策 + 4 条理由），所以"用哪个 API"**已记录，不必重复**；真正缺失的是**机制层**选型——为什么是命名管道而非 stdin/stdout、TCP、共享内存（全仓 grep `stdin\|TCP\|共享内存` 在研究稿中无对比表，仅 `:622` 一句"替代文件管道方案"、`:643` 把共享内存列为未来升级项）。故本 ADR 应聚焦**机制层选型 + 契约演进策略（版本字段 / 未知字段处理）**。这是一条**现在补成本最低、将来补成本最高**的 ADR |
| 3 | **④ NSIS 而非 MSI** | 建议立（可与 ⑤ 合并为一则"分发形态 ADR"） | 研究稿 `rust-rewrite-research.md:781` 推荐 NSIS+MSI 双轨，实际只取 NSIS，且 `developer-guide.md:1673` 留下死路径。属"决策已发生但没留痕"。**优先级低于 ⑤②**，因为它不产生外部风险 |
| 4 | **③ CSP 的 `'unsafe-inline'`** | 可立，但**优先级最低** | Tauri 桌面应用前端是本地打包资源，攻击面远小于 Web，风险可接受（见 D2-1）。建议**不要单独立**，而是作为第 2 项 IPC/安全 ADR 的一节，或并入一条"前端安全基线"ADR |
| 5 | **① Rust+Tauri 取代纯 AHK 的选型** | **不建议现在立** | 依据在 2894 行研究稿里，材料充分但**已成既成事实**（v4 已跑起来了）。补 ADR 的收益是"让新人理解来龙去脉"，属文档价值而非决策价值。**建议做法**：不立新 ADR，改为把研究稿的结论**摘要**（非纯链接，见下）挂进 ADR-001 的「关联」段——ADR-001 已经处理了"v3 栈怎么办"，选型理由挂靠在它下面即可 |

### 「规划过但没落地」事项的**强度分级**（与 Docu 交叉后校正）

本仓存在一类"研究阶段提到、落地阶段没做"的事项。但它们**强度不同，不应一律写成"决策被静默砍掉"**：

| 事项 | 研究稿表述 | 强度 | 结局状态（四态） |
|---|---|---|---|
| **MSI 打包**（B4-1） | `:781` **明确建议 + 具体配置值** `"targets": ["nsis", "msi"]` | **强** —— 是带具体取值的建议 | **状态未知（无留痕）** —— 见下方四态说明 |
| **updater 插件**（B1-1） | `:895` 🟢 **P2「⚠️ 评估」+「按需引入」**，且**同一行并列** global-shortcut 2.3.1 / dialog 2.7.1 / fs 2.5.1 | **弱** —— 是"待评估"清单项，**非承诺** | **未采纳**（从未评估，只是没被拾起） |

**佐证（本文复核）**：`:895` 同一行并列的 4 个插件中，**global-shortcut 2.3.1、dialog 2.7.1、fs 2.5.1 三个均已落地**（`src-tauri/Cargo.toml:38-40`，版本与建议值**逐字一致**），**updater 是唯一未落地项**。
⇒ 这更像"待评估清单里唯一没被拾起的一项"，而非"已被采纳的决策被撤销"。若写成后者，后人会误以为 updater 曾是硬承诺。

**一处防误读的括注**：`src-tauri/Cargo.toml:37` 另有 `tauri-plugin-opener = "2"`，它**不在** `:895` 那条建议行内（是后续自行引入的）。因此"4 个插件、3 个落地"的计数**仅限该行所列**，不应把 opener 计入分母去质疑计数。（该括注由 Docu 提出，本文同步采纳。）

**写 ADR 时的措辞要求**：须记录**原建议强度**——MSI 是"带具体配置值的建议"（强）、updater 是"P2 按需评估"（弱）。这样后人既不会误以为 updater 是硬承诺，也不会因"同列 3 个都做了"而误判 updater 是被**有意否决**的（未采纳 ≠ 否决）。

### 「建议项结局」的四态分类（第四态由 Docu 提出，本文采纳）

仅用"采纳/未采纳"两态会**抹掉不确定性**，故按四态记录。

**⚠️ 判据（已修正一次，勿用旧版）**：判断 ② 还是 ④，**不是看"有没有被列出来"，而是看该条目承诺的动作是「执行」还是「评估」** —— 落点是**原文动词**：

| 原文承诺的动作 | 结局无留痕时归 | 本案 |
|---|---|---|
| 承诺**执行**（给出应做的结论，或直接给出可写进配置的取值） | **④ 状态未知** | MSI —— `:781` 位于「Tauri 内置打包」段的 `tauri.conf.json` 配置代码块内，给出的是能直接落盘的 `"targets": ["nsis","msi"]` |
| 仅承诺**评估**（列入待评估清单，如"⚠️ 评估…"按需引入"） | **② 未采纳** | updater —— `:895` 行首原文即「⚠️ **评估** Tauri 插件 … **按需引入**」。该行承诺的动作是"去评估"，而"从未被评估"正是 ② 的定义 |

> **本文初版判据写的是「看原建议是否曾被明确提出」，该判据已被推翻**：updater 在 `:895` **同样被明确列出且带了具体版本号 2.10.1**，按"是否被列出"会把 updater 也归成 ④，与 MSI 同质 —— 那样前面四轮的强/弱分级就白做了。
> 修正后的判据由 Docu 提出并举证，本文复核 `:781`（配置代码块）与 `:895`（"评估"动词）原文后采纳。后人按**原文动词**即可自行归类，不必依赖我们当初的判断。

| 状态 | 含义 | 本案 | 对后人的含义 |
|---|---|---|---|
| ① **已落地** | 建议被执行 | global-shortcut / dialog / fs（3 个） | 无需动作 |
| ② **未采纳** | **从未评估过**，只是没被拾起 | **updater** | **应重开评估**（它没被否决过） |
| ③ **被否决** | 评估过并明确拒绝，**有记录** | 无 | 尊重结论，除非前提变化 |
| ④ **状态未知（无留痕）** | **明确建议过，但结局无记录** —— 无法判定属 ②③ | **MSI** | **必须先补决策记录**，才能判断属于哪态 |

**为什么必须保留第 ④ 态**：MSI 曾被**明确建议并给出具体配置值**，因此它**既不是"从未评估"（②）、更不能记为"被否决"（③）**。
- 若把 MSI 记成 ②，等于替它**编造**了一段"从没评估过"的历史，与"曾被明确建议"的事实矛盾；
- 若记成 ③，则是**凭空捏造**一个不存在的拒绝结论。
- **B4-1 这条发现的价值恰恰在于"我们不知道它是哪种"** —— 写成任一确定态都会抹掉这一点，后人便不会再查。

> 该四态分类中第 ④ 态由 Docu 提出并论证，本文复核后采纳，并已据此修正 B4-1 的定性措辞（原写"落地时被砍掉"，现改为"结局无留痕／状态未知"）。

> 该强度分级由 Docu 提出并举证，本文复核确认后采纳。**本文初稿曾把两者写成"完全同一种病"，属过度归并，已按此表修正。**

### 一条流程性建议（比补哪条 ADR 更重要）

在补任何新 ADR 之前，**先把 ADR-001 与 ADR-002 从 Proposed 转为 Accepted**（见 C1-1）。
理由：目前 2 条 ADR 零条生效，说明**复核环节是断的**。在流程没跑通之前补第 3、4、5 条，只会得到更多"写了但不生效"的文档 —— 那反而会稀释 ADR 机制的可信度。
同理，C1-2（无 CI 冻结守卫）应当与 C1-1 一并解决，否则即使 ADR-001 转 Accepted，冻结仍然只靠人工自觉。

> 📌 **读文档时的坑（Docu 提示，本文引用 `developer-guide.md` 时已注意）**：
> `developer-guide.md:1600-1601` 有破损围栏，§4.6.6（约 1601-1636 行）在渲染时会被吞成代码块。
> 本文对 `developer-guide.md` 的引用（`:1673`）取自**源码行**，未依赖渲染结果。

---

## 附：本轮实跑命令清单（供复核）

```bash
# A1 取证
cat .gitmodules                                          # → 无
git ls-files AutoHotkey-2.0.26 | wc -l                   # → 181
git ls-files AutoHotkey-2.0.26/source | wc -l            # → 168
git check-ignore -v .../ahk_executor/AutoHotkey64.exe    # → .gitignore:35:*.exe
md5sum ahk_executor/AutoHotkey64.exe AutoHotkey-2.0.26/AutoHotkey.exe   # → 52086b80… 一致
find . -iname "LICENSE*" -o -iname "NOTICE*" -o -iname "deny.toml" …    # → 仅 AHK / lib_pcre
grep -n "license" tauri.conf.json                        # → 无

# B 发布
grep -rn "updater" Cargo.toml src-tauri/Cargo.toml asd-*/Cargo.toml     # → 无
grep -rn "check_update\|releases/latest\|github.com/zyejf" …            # → 无
wc -l .github/workflows/ci.yml                           # → 913（末尾即 upload-artifact）

# C 架构
grep -rn "VERSION\|version" crates/asd-ipc-protocol/src/*.rs            # → 无
grep -rn "\.version" crates/asd-domain/src/config.rs                    # → 仅测试断言 :1077
git ls-files Cargo.lock package-lock.json                # → 均在
grep -n "状态" docs/adr/ADR-001-v3-ahk-stack-positioning.md             # → Proposed

# D 可观测
grep -rn "tracing_subscriber\|rolling" src-tauri/src/                   # → logging.rs:28,52
grep -rn "register_panic_hook" src-tauri/src/lib.rs                     # → :708
grep -rn "heartbeat" src-tauri/src/infrastructure/ipc.rs                # → :109,175,755

# 第 6 章 / 跨域复核（Docu 同步后补充）
ls docs/adr/                                        # → README.md + ADR-001 + ADR-002（仅 3 个文件）
grep -n "状态" docs/adr/ADR-001*.md docs/adr/ADR-002*.md                # → 两条均 Proposed
grep -rn "msi" docs/developer-guide.md                                  # → :1673（配置无 msi target）
grep -n "targets" docs/superpowers/specs/2026-05-28-rust-rewrite-research.md  # → :781 建议 nsis+msi
sed -n '22p' asd-tauri/src-tauri/tauri.conf.json    # → CSP 含 'unsafe-inline'
sed -n '9p' AGENTS.md                               # → v3「作为独立运行模式保留」，未提冻结
grep -n "keys.first\|keys\[0\]" crates/asd-ipc-protocol/src/hotkey_merger.rs  # → :31-32 与 ADR-002 一致
```
