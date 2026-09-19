# 阶段 3 · 发布链路：要做什么、分几步、谁来做、卡点在哪

**日期：** 2026-09-19 ｜ **作者：** 系统架构师（阿奇） ｜ **面向：** 决策
**v2（2026-09-19 晚）：** 已按 Rex 的独立复核订正 3 处 —— ① `on.push.tags` 的表述（当前无该过滤器，属「刻意不接」而非「失效」）；② HEAD 锚点由 `9fd8a69` 挪到 `93d88d6`（落后 363 提交）；③ X1/X2 补入 Rex 的更硬证据与定性边界。
**完整论证：** `docs/research/release-pipeline-2026-09-19.md`
**覆盖阻断项：** B3（无 GitHub Release 步骤）／B13（发布产物零冒烟）｜债项 TD-074 / TD-078 / TD-083

---

## 一、先纠正一个前提：不是「从没发过版」，是「发过一个错的版本」

实调 GitHub API 得到（**不是推断**）：

| 事实 | 值 |
|---|---|
| 远端 Release | **已存在 1 条**：`v0.1.0 - ASD 技能管理器首个发布`，2026-06-28 发布 |
| 它的资产 | **0 个**（空壳） |
| tag `v0.1.0` 指向 | 提交 `0fbfce5`（**2026-06-28**） |
| 当前 HEAD | `93d88d6`（2026-09-19，Docu 的文档入库提交；**落后 363 个提交**） |

**两个直接后果：**

1. 若按直觉用 `workflow_dispatch` 选 ref=`v0.1.0` 构建，**产出的是 2026-06-28 的旧代码**，会得到一个「看起来发版成功、内容却是三个月前」的包。**这是本方案里最危险的坑。**
2. 将来若要接 `on.push.tags: ['v*']` 自动发版，**它对已存在的 `v0.1.0` 永远不会触发**，必须打新 tag。

> ⚠️ **表述订正（Rex 2026-09-19 复核，已采纳）**：我初稿写「`on.push.tags` 这条路已经死了」**用词不准**。`ci.yml` 的 `on.push` **当前根本没有 `tags:` 过滤器**（只有 `branches: [main, master]`），「加 `tags: ['v*']`」只是注释里的**未来待办**；**刻意不接 tag 触发是一个已写明理由的决策**（release 路径从未验证 + dispatch 可任选 ref），不是「触发器坏了」。事实本身（tag 已存在、指向旧提交）不受影响。

另外，`release` job 一次都没跑的原因是双重的：事件层（`workflow_dispatch && build_release`，默认 false）＋ 路径层（唯一含 `tauri build` 的 e2e job 也被默认 false 挡住）。**ci.yml 全文 913 行没有任何 Release 步骤。**

---

## 二、决策点（需要拍板的只有 3 个）

### D1｜发布走哪条路？→ **建议：`workflow_dispatch` + 作业内 `gh release create --target $GITHUB_SHA`**

| 选项 | 结论 |
|---|---|
| A. `on.push.tags: ['v*']` 自动 | **✗ 不选**：它对**已存在的 `v0.1.0` 永不触发**；新建 tag 若走 push，又被本机 `github.com` 直连 000 阻塞。（注：它不是既有触发器 —— `on.push` 当前**没有** `tags:` 过滤器，见上方订正） |
| B. 上传资产补完已有的 `v0.1.0` | **✗ 否决**：Release 标注旧提交、产物是新代码 ⇒ 制造「标注与内容不符」的假一致性，回滚时会定位到错提交 |
| C. `workflow_dispatch` + `gh release create --target <sha>` | **✓ 推荐**：tag 由 runner 用 `GITHUB_TOKEN` 经 **API** 创建，**全程不需要本机 push**；`--target` 保证 Release 标定的源码 == 实际构建的 commit |
| D. `softprops/action-gh-release` | 备选，功能等价但引入第三方 action；C 出问题就换它 |

**关键约束已化解**：本机 `github.com` 不可达 / `gh` 未登录 —— 都不影响，因为发布动作发生在 GitHub runner 上（`api.github.com` 已实测 200）。

> ⚠️ **一条未验证风险，将来接 tag 自动发布前必须实测**：`gh release create` 会**通过 API 创建 tag**。API 创建的 tag 是否会触发 `on.push` 的 `tags` 过滤器，GitHub 行为在不同时期有差异，**我未实跑、未查证，不做断言**。若会触发，则「本 job 建 Release 建 tag」＋「`tags:['v*']` 触发本 job」会形成**二次触发**。⇒ 接自动发版时先跑一次验证，并用 `concurrency` 兜底。

### D2｜版本号怎么定？→ **必须先拍板，否则别发**

`tauri.conf.json`=0.1.0、UI 自述 v3.0、AGENTS.md 写 v4.0（TD-078）。**建议：发布前定权威版本源**。若来不及，最低要求是 ——

- `release_tag` **禁止填 `v0.1.0`**（那个指向旧提交）；
- artifact 名与 Release 里**必须带 commit sha**（版本号不可信，sha 才是权威溯字段）；
- job summary 里打印 `commit: ${{ github.sha }}`。

### D3｜已存在的空壳 Release `v0.1.0` 删不删？→ **建议保留不动**

它是 2026-06-28 的历史记录，删了会让历史断层。改为在新 Release 说明里注明「v0.1.0 无资产且指向旧提交，可用版本自 <新 tag> 起」。**本方案不擅自删**，删与否属主理人决策。

---

## 三、分几步做（每步谁做、卡点）

| # | 动作 | 谁做 | 卡点 | 估时 |
|---|---|---|---|---|
| 1 | 手动 `workflow_dispatch` 跑一次 `release`（**只勾 `build_release`**） | 主理人，人工盯全程 | 构建路径从未跑过，首次不保证绿 | 0.5 人日 + 1 次 CI 往返 |
| 2 | 确认出包 + LICENSE/第三方许可真的进包（TD-080 遗留，未实跑验证过） | 主理人 | 需下载 artifact 肉眼确认 | 含在上一步 |
| 3 | 加产物冒烟步骤，再跑一次 | 主理人执行（我出脚本） | 断言依赖日志落盘，首次可能要调路径 | 0.5 人日 + 1 次 CI 往返 |
| 4 | 加发布段（inputs + `permissions: contents: write` + `gh release create`） | 主理人执行 | **阻塞于 D2**；`release_tag` 不得填 v0.1.0 | 0.5 人日 |
| 5 | 首次真实发版 | 主理人 | **不可逆**，会创建远端 tag | 0.2 人日 |
| 6 | 跑一次 TD-083 人工验证（15 分钟，不需按键） | 任一熟悉 Windows 的人 | 需一台装了应用的机器 | 15 分钟 |

> **总卡点：#1 没跑绿之前，第 3–5 步全部是纸面方案。**

---

## 四、产物冒烟（B13）：能自动到哪一步

**判据全部放在磁盘证据上，不碰 GUI。** 应用已把关键事件写进按天轮转的日志（`logging.rs`，默认 info 级），因此下列断言都是二值可判的：

| 断言 | 证据（实证位置） |
|---|---|
| 静默安装成功 | `HKCU:\...\Uninstall\*` 出现 DisplayName 含 `ASD` 的键 |
| 启动未秒退 | `Start-Process -PassThru` 后 20s 内未退出 |
| 配置/日志路径可用 | `%APPDATA%\com.asd.tauri\asd.<日期>.log` 生成 |
| 拉起 AHK 子进程 | 日志含 `使用便携/编译模式 AHK 子进程`（`lib.rs:640/653`）+ 进程表有 `AutoHotkey64` |
| **IPC 握手并认证成功** | 日志含 `IPC 已接受 AHK 连接（已认证）`（`ipc.rs:284`） |
| 无负面对证 | 日志不含 `IPC AHK 认证失败` / `认证超时` / `无法解析 AutoHotkey64.exe 路径` |

> **`IPC 已接受 AHK 连接（已认证）` 是高杠杆断言**：它的出现需要「子进程 spawn 成功 + 管道名一致 + 子进程连上 + token 认证通过」四件事同时成立，比「进程存在」强得多，且完全不需要 GUI。

**不能自动、必须人工的（不许写成已自动化）：**

| 项 | 原因 |
|---|---|
| 首次构建/安装 | ci.yml:784-785 自述「首次不保证绿，必须人工观察」 |
| `/S` 是否真静默 | `displayLanguageSelector: true` 组合未实测；卡住的表现是超时，信号很脏 |
| LICENSE 进包 | TD-080 明载遗留，未实跑验证 |
| **真实按键触发连招** | 需交互会话 + 键盘注入；**E2E 通道当前是红的**（TD-061，两条独立通道均已证伪） |
| SmartScreen 告警表现 | 未签名，需真实机器观察 |
| 离线安装 | 需构造离线环境（TD-086） |

---

## 五、TD-083（重启后热键是否恢复）：**不需要 GUI 也能验证**

此前结论「靠推理，需要 GUI，自动化不了」—— **只对了一半**。它把「要跑一个应用」和「要人用鼠标键盘操作」混为一谈。

**L1 结构层（不需要 GUI，证据已闭合，实读非推断）：**

- `hotkey_hook.ahk:17` `static _registered := Map()` —— 新进程必然空注册表；
- `executor.ahk:430-451` `Executor_Init()` 三个 Init + 起 IPC，**不注册任何热键**；
- `executor.ahk:60-86` 分发器 11 个分支**无 resync 命令**；
- `watchdog.rs:1279-1299` `restart_child` **只 kill + spawn**，无重放；
- Rust 侧 grep `重新注册/resync/on_reconnect/OnConnected` **零命中**；`active_hotkeys` 写入点只在激活/切换（`state.rs:235/289`）。

⇒ **「无重放路径」已从推断升级为已验证。**

**L2 行为层 —— 判据不必是「按 F1 有没有反应」：**

因为 `Sender` 的周期定时器**也住在 AHK 进程里**（`executor.ahk:296-298`），active 分组的按键输出是**持续**的。所以判据可以是「**看字符流停没停**」—— 不用按键注入、不用 GUI 驱动、15 分钟能跑完，而且它顺带暴露更严重的一半：**不只是热键没了，正在跑的连招也没了**。

**三条可执行路径（推荐顺序）：**

1. **路径 1（推荐，零 GUI，~1.5 人天，全自动）**：把已存在但无出口的 `HotkeyHook.GetCount()`（`hotkey_hook.ahk:100-102`）接出 `query_hotkeys` IPC 命令 → Rust 侧重启后对账 `active_hotkeys` → 不一致即 `tracing::error!` + emit（顺带补上 TD-083 点名的「热键注册失败零日志」）→ 用现成的 `RecordingMockIpcSender`（`state.rs:1260-1285`）+ 现成的真实进程重启驱动（`watchdog_integration_tests.rs:172-226`）写测试。
   ⚠️ **诚实标注：这条今天就能绿，但它守的是「对账装置存在且会报警」，不是「重启后功能正常」。不能替代一次真实端到端。**
2. **路径 2（一次性人工，15 分钟，不需按键）**：见完整报告 §6 的 11 步脚本（建 2 个周期分组 → 看记事本字符流 → 结束 `asd_executor.exe` → 等 ≤30s → **什么都不按，看字符流恢复没有** → 停用再启用做对照实验）。
3. **路径 3（GUI 自动化）**：不建议现在做 —— E2E 通道是红的，为一次性验证去修一条已知红的通道不划算。

**修复方向建议（排期另定）：先 F3（对账 + 显式报警，把静默失效变成显式失效），再评估 F2（重放全部 active 分组状态）。F1（只重放热键）是半成品 —— 热键回来了但连招不跑。**

---

## 六、附带发现（转交，不在本任务内）

| # | 发现 | 建议转交 |
|---|---|---|
| **X1** | **CI 的 `G3h watchdog（--ignored）` 步骤跑 0 条用例却显示绿灯。** 全仓已无活的 `#[ignore]`（8 处命中全在 `//!` 注释里）。**Rex 拿到了更硬的证据**：CI job `105906876013` 日志实测 `running 0 tests` / `**256 filtered out**`，rc 仍为 0。<br>✅ **Tessa 已在修（未提交）**：工作树里已改为 `cargo test -p asd-tauri --lib tests::watchdog_integration_tests -- --test-threads=1`（按模块名跑，不再用 `--ignored`），并补写了成因与解禁判据 | **Tessa**（已在处理）／**Rex**（已把该绿灯从有效信号中剔除）。本条我不再推进 |
| **X2** | **打包布局只会走「便携模式」**：`bundle.resources` 不含 `asd_executor.exe`（`.gitignore:35` 的 `*.exe` 排除它），包内必然回落 `AutoHotkey64.exe` + `executor.ahk`；**本地因有 `asd_executor.exe` 走「编译模式」** ⇒ **本地测过的执行器路径 ≠ 用户装到的路径**。<br>**Rex 补的证据环**：`build.rs` 全文 grep `asd_executor` **零命中**（排除「构建时自动生成」）。<br>⚠️ **Rex 提出的定性边界（避免夸大）**：`watchdog.rs:314-319` 对 `AutoHotkey64.exe` **正确追加了 `executor.ahk`** 且 `executor.ahk` 在 `bundle.resources` ⇒ **静态接线正确**，故定性是「**未验证**」**不是「已知坏」** | **Rex**（Go/No-Go，记为 N6，拆成 B6 未实测 + B7 静态接线正确）；A5/A6 断言被采用为唯一验证手段 |
| X3 | `displayLanguageSelector: true` 与 `/S` 静默安装的组合未实测 | 冒烟首次执行时人工盯 |

---

## 七、「已验证」与「未验证」不许混

| 已验证（实读/实调/实跑） | 未验证（不许当成已有） |
|---|---|
| release job 触发条件；ci.yml 无 Release 步骤 | **冒烟 job 能否在 CI 跑绿（从未执行过）** |
| 远端存在 0 资产的 Release v0.1.0，指向 2026-06-28 旧提交 | `/S` 静默安装在 `displayLanguageSelector: true` 下生效 |
| 本机 github.com 000 / api 200 / gh 未登录 | `gh release create --target` 建 tag 的行为（工具已知语义，本机未实跑） |
| 断言字符串在代码中确实存在（ipc.rs:284 等） | LICENSE 进包（TD-080 遗留） |
| TD-083 结构层全链条证据 | 打包布局下 `bundle.resources` 解析正确（**这正是冒烟要验的**） |
