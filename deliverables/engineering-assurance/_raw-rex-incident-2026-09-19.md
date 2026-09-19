# 事故响应报告：WorkBuddy 托管 worktree 嵌套 ref 被清空导致分支指针丢失

- **报告人**：雷克斯（Rex）· SRE 工程师
- **报告日期**：2026-09-19
- **事故日期**：2026-09-16（当日连续多次触发）
- **仓库**：`D:/1demo/AutoHotkeydemo`（主 worktree，分支 `main`）
- **涉事分支**：`refs/heads/workbuddy/main-5f18c6a6`（嵌套 ref，含 `/`）
- **证据基线**：git 2.55.0.windows.3；所有结论均标注「实测 / 记忆记载 / 推断」三档，推断一律显式标注

> **取证纪律声明**：本项目已多次把「其实已有守护」误判成「没有守护」（2026-09-19 一天三次）。
> 本报告对自己引用的一切来源（含 `.workbuddy-ai/memory/`）**一律先实测再落笔**。
> 实测结论：**记忆文件中关于本事故根因的核心论断已被阳性对照证伪**，详见 §4 与附录 A。

---

## 1. 事故分诊（Triage）

### 1.1 SEV 评级：**SEV2（研发基建严重降级）**

评级采用可审计的五维打分，而非整体印象：

| 维度 | 实测/记载 | 打分 |
|------|-----------|------|
| 用户可见影响 | 个人/小团队桌面应用（Rust/Tauri + AHK），**无线上服务**，无外部用户受影响 | 不构成 SEV1 |
| 核心工作流中断 | 提交链路在一天内 **3 次**中断（reset / commit / merge 各一次），第 4 次导致提交对象真实丢失 | 严重（+） |
| 数据完整性 | 提交对象一度**真实丢失** 3 个（`2bf5063`/`05b4b39`/`4c0b597`），靠远端 fetch 才救回 | 严重（+） |
| 可恢复性 | 4 次中 3 次本地可恢复（写回 ref / commit-tree 重建），1 次依赖远端 | 中等（±） |
| 复发概率 | 触发条件在 09-16 全天未消除，表现为「每次移动 ref 的操作都触发」 | 高（+） |

**判定 SEV2 而非 SEV1** 的依据：无用户可见影响，且存在已验证的本地恢复路径。

**判定 SEV2 而非 SEV3** 的依据：主工作流（提交）完全阻断，且已发生真实的提交对象丢失。

> ⚠️ **「差一点就是 SEV1」**：第 4 次（stash）丢失的 3 个提交对象**当时已推送到远端**，所以能 fetch 回来。
> 若这 3 个提交当时尚未推送，即为**不可恢复的提交历史丢失**，应直接定为 SEV1。
> 这是本次事故最该被记住的一点：**可恢复性依赖于「是否已推送」这一偶然因素，而不是依赖于任何设计。**

### 1.2 影响范围

| 影响面 | 结论 | 证据 |
|--------|------|------|
| 数据丢失风险（当前） | **0**（仅嵌套 ref 可达的提交数 = 0；`9f9eb74` 已是 `main` 祖先，且被顶层分支 `techdebt-2026-09-16` 锚住） | 实测：`git rev-list 9f9eb74 --not main \| wc -l` = 0；`git merge-base --is-ancestor` = 是 |
| 数据丢失风险（事故当时） | **真实存在**：3 个提交对象从 `.git/objects` 消失 | 记忆记载 + 实测该 3 提交现仍存在（已恢复） |
| 提交历史可信度 | **受损**：`31dc567` 是**无父 root commit** 且被写进过 HEAD，其 `--stat` 为 825 files / 345417 insertions，会让任何读历史的人误以为「整棵树被重写」 | 实测 `git log -1 --format='%p' 31dc567` = 空 |
| 工时损失 | **无法量化** —— 记忆未记录排查/恢复的人时，第 3、4 次连时刻都未记录。**不编造** | — |
| 排查误导成本 | 高：`git status --porcelain \| head -20` 把几百行 `A` 截掉，导致误判「索引干净」 | 记忆记载（本项目已列为教训） |

### 1.3 角色分配

| 角色 | 人选 | 职责 |
|------|------|------|
| 事故指挥官（IC） | 甄宇航（主理人） | 决策是否中断当前迭代、批准回滚/改道 |
| 响应者（Responder） | 雷克斯（SRE） | 执行恢复、记录时间线、产出本报告 |
| 沟通负责人 | docu | 对内/对外通报（本项目无外部客户，故只需内部通报） |
| 领域顾问 | cody | git 行为与护栏实现评审 |
| 记录员（Scribe） | 雷克斯 | 时间线与分钟级记录（本角色在 09-16 **缺位**，是第 3、4 次无时刻记录的原因） |

---

## 2. 事故时间线

**时间来源**：`.git/worktrees/main-5f18c6a6/logs/HEAD` 与 `.git/logs/refs/heads/workbuddy/main-5f18c6a6`（reflog，epoch 秒 +0800），
并用两个独立锚点校验换算正确：`9343c4a` author date 20:41:47 ↔ reflog 20:41:47；`84736a3` author date 20:47:01 ↔ reflog 20:47:01。
**时刻未记录的事件一律写明「时刻未记录，顺序确定」，不编造。**

### 事故 #1：`git reset` 触发（症状 = `git status` 全 A）

| 时刻（+0800） | 事件 | 来源 |
|---|---|---|
| 17:46:55 | worktree 建立，分支 `workbuddy/main-5f18c6a6` 从 `main`(315b988) 创建 | reflog「branch: Created from main」+ 目录 mtime 17:46 吻合 |
| 17:46:56 | `reset: moving to HEAD`（1 秒后，疑似 `worktree add` 内部动作） | reflog |
| **20:34:40** | **`reset: moving to HEAD` → 引用文件消失**，worktree 变 unborn HEAD | reflog |
| 20:38:50 | `branch: Created from 315b988` → **恢复成功** | reflog（**注：与记忆「git 建不出嵌套 ref」直接矛盾**） |
| 20:39:14 / 20:40:33 | 两次无消息 ref 写入（update-ref 类），值同为 315b988 | reflog |
| 20:41:47 | `commit` 9343c4a 成功 → 恢复完成，工作流可用 | reflog + author date 双证 |

- **恢复耗时（可测）**：4 分 10 秒（20:34:40 → 20:38:50 重建指针）；完全可用 20:41:47（约 7 分）。

### 事故 #2：`git commit` 触发（症状 = 新提交变无父 root commit）

| 时刻（+0800） | 事件 | 来源 |
|---|---|---|
| 20:54:18 | `commit` 7780223（记录事故 #1） | reflog |
| 22:15:36 | `commit` b28b915，**父 = 7780223（正确）** | 实测 `git log -1 --format='%p'` = 7780223 |
| **22:15:55** | **`commit (initial)` 31dc567 —— 仅隔 19 秒**，reflog 旧值为全零（unborn），新提交**无父** | reflog + 实测 `31dc567` parents=[] |
| — | 恢复：`commit-tree` 重建 `655abac`，父 = 7780223 | 实测 `git log -1 --format='%p' 655abac` = 7780223（**重建正确**） |
| 22:25:25 | `commit` a150b94 落在 655abac 之上（reflog old=655abac）→ 恢复完成 | reflog |

- **恢复耗时（区间）**：≤ 9 分 30 秒（22:15:55 → 22:25:25 之间完成重建）。
- **内容零丢失（硬证据）**：`git diff --stat b28b915 31dc567` **输出为空** → 两棵树完全一致，只是父链接断了。
- 记忆所称「825 files / 345417 insertions」经实测复核**属实**：`git show --stat 31dc567` = 825 files changed, 345417 insertions(+)。

### 事故 #3：`git merge --ff-only` 触发

| 时刻（+0800） | 事件 | 来源 |
|---|---|---|
| 22:42:59 | `main` 上生成 merge commit `63500a3` | author date |
| **22:54:44** | worktree 执行 `merge main: Fast-forward` → 引用再次被清 | reflog；`.git/worktrees/.../ORIG_HEAD` mtime 22:54 吻合 |
| 恢复时刻 | **时刻未记录**（reflog 之后无条目；记忆只记载了恢复命令，未记载时刻） | — |

- **顺序确定，恢复耗时不可测。**

### 事故 #4：`git stash push -- <path>` 触发（**不同的失效模式：对象丢失，不是指针丢失**）

| 时刻 | 事件 | 来源 |
|---|---|---|
| 09:36:31 / 10:49:58 / 10:51:40 | 被吞掉的 3 个提交的 author date（`2bf5063` / `05b4b39` / `4c0b597`） | 实测 |
| **时刻未记录** | `git stash push -- <path>` 后，HEAD 指向的 3 个提交对象从 `.git/objects` 消失，`git status` 报 `fatal: bad object HEAD` | 记忆记载 |
| 时刻未记录 | 恢复靠 `git fetch` 远端（因 3 提交已推送） | 记忆记载 |

- **日期与时刻均未记录**，可确定的唯一边界：事件发生在 10:51:40 之后（它吞掉了当时最新的提交）。
- ⚠️ **记忆记载有歧义**：该段写的是「`HEAD`/`refs/heads/main` 指向的 3 个提交」，但上下文发生在嵌套 worktree 的迭代中；
  **究竟发生在主 worktree 还是嵌套 worktree 无法从记载判定，本报告不据此下结论**。

### 事故 #5（本次调查的**新发现**，非 09-16 当日）：残留注册项

| 时刻 | 事件 | 来源 |
|---|---|---|
| 2026-09-17 16:03 | 嵌套 ref 停在 `9f9eb74`（最后一次写入） | author date + index mtime |
| 2026-09-18 21:42 | WorkBuddy 工作目录 `C:/Users/fei/WorkBuddy/Worktrees/AutoHotkeydemo/` 被**整体删除**（目录已空） | 实测目录 mtime |
| 当前 | `git worktree list` 报告该 worktree **`prunable`**：工作目录没了，`.git/worktrees/main-5f18c6a6/` 注册项与 88KB index 仍残留 | 实测 |

> 这条很关键：它证明**该 worktree 的目录生命周期由外部环境管理、且会被整体清除**，
> 而 `.git` 侧注册项不会被同步清理。见 §4 的根因推断。

---

## 3. 影响范围量化

| 指标 | 数值 | 取证方式 |
|------|------|----------|
| 事故当时 tracked 文件数 | **825** | 实测 `git ls-tree -r --name-only 315b988 \| wc -l` = 825（**记忆数字核实通过**） |
| 当前 tracked 文件数 | 780 | 实测 `git ls-files \| wc -l` |
| root commit 的爆炸半径 | 825 files / 345417 insertions | 实测 `git show --stat 31dc567`（**记忆数字核实通过**） |
| **内容丢失量** | **0**（事故 #2 两棵树 diff 为空） | 实测 `git diff --stat b28b915 31dc567` 无输出 |
| 真实丢失的提交对象 | 3 个（`2bf5063`/`05b4b39`/`4c0b597`），已恢复 | 记忆记载 + 实测现仍存在 |
| 事故 #1 恢复耗时 | 4 分 10 秒（指针重建） | reflog 时间差 |
| 事故 #2 恢复耗时 | ≤ 9 分 30 秒 | reflog 区间 |
| 事故 #3 / #4 恢复耗时 | **不可测（时刻未记录）** | — |
| 工时/排查成本 | **不可量化（无记录），不编造** | — |
| 当前残余数据风险 | **0**（仅嵌套 ref 可达提交 = 0；已被 `techdebt-2026-09-16` 顶层分支锚住） | 实测 |
| 当前残余隐患 | 1 个 `prunable` worktree 注册项 + 88KB 残留 index | 实测 |
| `main` 领先嵌套 ref | 109 个提交（嵌套 ref 已严重过期） | 实测 `git rev-list --count 9f9eb74..main` |

---

## 4. 根因分析（5 Why）

### 4.0 前置：先推翻一个**已被写进长期记忆的错误根因**（本报告的取证重点）

`MEMORY.md` 现行记述：

> 「git 在本环境**建不出**嵌套 ref：`git branch workbuddy/x`、`update-ref refs/heads/zzdir/probe` 都返回 0 却什么都没建」

这条是**错的**。两条独立证据：

**证据 A —— 仓库自己的 reflog（最硬）**：事故 #1 恢复时，reflog 明确记录
`20:38:50 branch: Created from 315b988`，且 `.git/refs/heads/workbuddy/main-5f18c6a6` 至今存在并指向 `9f9eb74`。
**git 当时就是建成了这个嵌套 ref。**

**证据 B —— 阳性对照复现（本次在 `/tmp` 沙箱仓库实测，git 2.55.0.windows.3）**：

| 操作 | 记忆断言 | 实测结果 |
|------|---------|---------|
| `git worktree add -b wb/main-abc`（嵌套名） | — | ✅ 建成 `.git/refs/heads/wb/main-abc` |
| `git branch wb/x <sha>`（嵌套名） | 静默失败、建不出 | ✅ **rc=0 且建成** |
| `git update-ref refs/heads/zzdir/probe <sha>` | 静默失败、建不出 | ✅ **rc=0 且建成** |
| `git reset -q` | 会清掉嵌套 ref | ❌ **ref 完好无损** |
| `git commit` | 会变 root commit | ❌ **父链接正确**（`682c0fb parents=12fe26b`） |
| `git merge --ff-only` | 会清掉嵌套 ref | ❌ **ref 完好无损** |
| `git stash push -- <path>` | 会清掉嵌套 ref | ❌ **ref 完好无损** |

**结论**：「嵌套 ref 本身导致 git 失灵」不是 git 的行为，也不是本环境的普遍性质。
**记忆里的根因结论会误导下一次恢复**——它会让响应者把「手工写 ref 文件」当成唯一手段，
而跳过真正该做的第一步：**先确认提交对象是否还在**（对象没了，写 ref 也无效；这正是事故 #4 的情形）。

### 4.1 五问

**Why 1：为什么分支指针会丢？**
因为有东西把 `.git/refs/heads/workbuddy/` **整个目录连同父目录一起删掉了**。
「父目录一起没」是 git 自身 ref-delete 路径的特征（git 删 ref 后会 `rmdir` 掉变空的父目录），
也符合「整体递归删除」的特征。反正**不是**「git 写不进去」。

**Why 2：为什么删了没人拦得住？**
因为**没有任何护栏**（已用阳性对照核实，非靠读代码推断）：
- 现行 `scripts/hooks/pre-commit`（`core.hooksPath=scripts/hooks`）只做 4 件事：敏感文件、构建产物、>1MB 大文件、临时文件 —— **不检查 ref 是否存在**；
- 现行 `scripts/hooks/commit-msg` 只管提交信息格式；
- 无 `reference-transaction` 钩子（git 唯一能在 ref 事务提交前否决的钩子）—— 实测**该钩子有能力拦住**，见 §6；
- `docs/developer-guide.md`、`docs/tech-debt-register.md` **零提及**本事故（已 grep 核实）。

**Why 3：为什么会把工作放在一个嵌套 ref 的 worktree 里？**
因为分支名 `workbuddy/main-5f18c6a6` 由 **WorkBuddy 托管 git worktree 自动生成**（`workbuddy/<源分支>-<hash>`），
**命名不在项目控制范围内**，项目只能接受它、无法改成顶层单名。

**Why 4：为什么没早点发现？**
两个原因叠加：
- **症状强误导**：`git status` 全 `A`（像"仓库没了"）与「提交变 root commit」（像"历史被重写"）都不指向"指针丢了"；
- **排查手法本身有缺陷**：`git status --porcelain | head -20` 把几百行截断 → 误判索引干净 → 在错误前提下继续提交 → 制造出 #2。

**Why 5：为什么同一天能连着犯三次（并搭上一次对象丢失）？**
因为**每次恢复只修指针，不消除触发条件**：恢复后立刻继续用同一个 worktree 做 ref 移动操作，于是又触发。
而且**根因被误记**（§4.0），导致对策停留在「手工写文件」这个补救动作上，没有指向「别在这里移动 ref」。

**Why 6（系统性根因，本报告认为这才是真根因）：**
**团队的判断未经实测即落笔，并被当作事实写进权威记忆。**
同一天（2026-09-19）团队在「守护是否存在」上犯过三次同类错误（TD-007 描述前提已证伪 / TD-058① 差集检查本就存在 / TD-058② G1 已在守），
本事故是同一个缺陷换了个载体：**一份声称记录"事故根因"的记忆，自己写错了根因**。
具体到本事故，链条是：观察到现象 → 用一个未验证的假设（"git 建不出嵌套 ref"）解释 → 写进长期记忆 →
后续所有人按错误根因采取对策 → **真正的数据丢失风险（对象不可达 → `gc --auto` 回收）从未被正面处理**。

### 4.2 真正的数据丢失机制（推断，已标注）

指针丢失本身**不丢数据**；丢数据的是第二步：

```
嵌套 ref 被删 → 提交变为不可达 → git gc --auto（commit/merge/fetch 后自动触发）回收不可达对象
             → "fatal: bad object HEAD" → 若未推送远端 = 永久丢失
```

这解释了为什么记忆里「顺手建一个顶层单名分支做兜底」这条对策**真的有效**——
它不是迷信，是给对象加了一个可达锚点。实测现状也正是被 `techdebt-2026-09-16` 锚住的。

**触发者推断（未证实，明确标注）**：综合 §2 事故 #5（WorkBuddy 工作目录于 09-18 21:42 被整体删除而 `.git` 注册项残留），
最可能是 **WorkBuddy 的 worktree 生命周期管理 / 沙箱清理在 git 写 ref 的时间窗内动了该路径**，
而非 git 自身缺陷（已被阳性对照排除）。**此推断未证实**，§5 的 P0 行动项按「无论触发者是谁都能防住」来设计。

---

## 5. 行动项

### P0（立即，事故当日级别）

| # | 行动 | 具体做法 | 拦住什么 |
|---|------|---------|---------|
| P0-1 | **嵌套 worktree 内禁止一切 ref 移动操作** | 在 WorkBuddy worktree 内，只用只读 git 命令；所有 `commit`/`merge`/`rebase`/`reset`/`stash` 一律切到主 worktree `D:/1demo/AutoHotkeydemo`（分支 `main`，顶层 ref）执行 | 事故 #1/#2/#3 全部触发源 |
| P0-2 | **给嵌套 ref 挂顶层单名锚点**（每次同步后必做） | `git branch <单名> "$(git rev-parse refs/heads/workbuddy/main-5f18c6a6)"` —— 实测现状已由 `techdebt-2026-09-16` 锚住，需固化为流程 | 对象被 `gc --auto` 回收（事故 #4 的丢失机制） |
| P0-3 | **安装 `reference-transaction` 钩子** | `scripts/hooks/reference-transaction`（见 §6.1），否决一切对 `refs/heads/*/*` 的删除 | 任何来源的嵌套 ref 删除（**实测有效**） |
| P0-4 | **纠正记忆里的错误根因** | 把 `MEMORY.md` 中「git 在本环境建不出嵌套 ref / git branch、update-ref 都静默失败」整段改为「**已证伪**：git 2.55 实测可正常创建/更新/移动嵌套 ref；真因是外部删除 + 无护栏」，并附上本报告的阳性对照 | 防止下一次恢复被错误根因带偏 |

### P1（本周）

| # | 行动 | 具体做法 |
|---|------|---------|
| P1-1 | 安装 `git-ref-guard.sh` 为提交前置检查 | 放入 `scripts/`，`pre-commit` 首行调用（见 §6.2） |
| P1-2 | **修复 pre-commit 的性能诱因** | 现钩子对每个暂存文件 `wc -c`（825 文件 → 逐文件 fork，跑到超时被 SIGTERM）。改为 `git diff --cached --name-only -z \| xargs -0 stat -c '%s %n'` 一次性取体积，或按 `git cat-file -s` 批取。消除"提交被中途 SIGTERM"这一加重因素 |
| P1-3 | 清理残留注册项 | `git worktree prune`（**只读语义外的清理，需 IC 批准**），清掉 `prunable` 的 `main-5f18c6a6` 注册项与残留 index |
| P1-4 | 把事故写进正式 runbook | 在 `docs/developer-guide.md` 新增「§worktree 嵌套 ref 事故处置」，内容取自本报告 §2/§5（当前 docs 零提及，已核实） |

### P2（本月）

| # | 行动 | 具体做法 |
|---|------|---------|
| P2-1 | 排查规范入文档 | 「判断索引是否干净必须用 `git status --porcelain \| wc -l`，禁用 `head`」写入 `developer-guide.md`；`git-ref-guard.sh` 已内建该规则 |
| P2-2 | 建立"事故后必须做阳性对照验证根因"的机制 | 与团队 2026-09-19 已确立的证据铁律合并：凡写入记忆的根因/守护判断，必须附一条可复现的阳性对照命令 |
| P2-3 | 每年演练一次 | 在沙箱仓库复现（本报告的 `/tmp` 复现脚本可直接复用），验证 runbook 与护栏仍有效 |

---

## 6. 预防措施与检测改进

> 设计原则：**提前发现**，而不是事后救火。每条护栏都列出「能拦住哪一类触发」+「阳性对照结果」。

### 6.1 `reference-transaction` 钩子（唯一能在 ref 事务提交**前**否决的钩子）

```sh
#!/bin/sh
# scripts/hooks/reference-transaction
[ "$1" = "prepared" ] || exit 0
while read -r old new ref; do
  case "$ref" in
    refs/heads/*/*)                                   # 嵌套 ref（workbuddy/main-xxx 形态）
      case "$new" in
        0000000000000000000000000000000000000000)     # new 全零 = 删除
          echo "[BLOCKED] 禁止删除嵌套 ref: $ref" >&2
          echo "  恢复/同步请改为主 worktree 操作或写回 sha（见 runbook）" >&2
          exit 1
          ;;
      esac
      ;;
  esac
done
exit 0
```

**阳性对照（实测）**：在沙箱仓库安装该钩子后执行 `git branch -D wb/x`：

```
[BLOCKED] 禁止删除嵌套 ref: refs/heads/wb/x
fatal: in 'prepared' phase, update aborted by the reference-transaction hook
wb/x 是否还在: 12fe26b1d3a086da8bbf51702d368a53f2a8121c   ← 分支存活，删除被真正否决
```

**能拦住**：事故 #1/#2/#3 的共同环节（嵌套 ref 被删除）——**无论删除者是谁**（git 自身、外部清理、另一并发进程）。
这是唯一一条「触发者无关」的护栏，故列为 P0。

### 6.2 `git-ref-guard.sh`（提交前置 + 日常巡检）

已交付：`deliverables/engineering-assurance/git-ref-guard.sh`（只读，绝不写 `.git`）。

| 检查项 | 拦住哪一类触发 | 阳性对照结果 |
|---|---|---|
| ① HEAD 可解析（`rev-parse --verify HEAD`） | 「`fatal: bad object HEAD`」（事故 #4） | PC2：移走 ref 文件 → `[FAIL] HEAD 不可解析`，rc=1 ✅ |
| ② 当前分支 ref 存在且可解析 | 事故 #1/#3 的指针丢失 | PC2 → `[FAIL] 分支 refs/heads/wb/main-abc 的引用不存在` ✅ |
| ③ 分支名含 `/` → 告警 + 改道提示 | 事故特征形态的**提前预警**（在还没坏的时候就提醒别在这里写） | PC1 健康态即告警 ✅ |
| ④ 暂存新增数 > 阈值（默认 50），用 `wc -l` 不用 `head` | 事故 #2「整棵树被重新 add」+ 顺带治掉 `head -20` 截断误判 | PC5：注入 61 个 A → `[FAIL] 暂存区新增 61 个文件 > 阈值 50`，rc=1 ✅ |
| ⑤ HEAD 是无父 root commit 且 reflog >1 条 | 事故 #2「提交变 root commit」 | 见下方 PC7 |
| ⑥ `prunable` worktree 检测 | 事故 #5（注册项残留、工作目录已被外部删除） | PC8 在真实仓库实测：`[WARN] 存在 1 个 prunable worktree` ✅ |
| ⑦ 嵌套 ref 是否有顶层单名锚点 | 对象被 `gc --auto` 回收（事故 #4 丢失机制） | PC1 → `[WARN] 没有指向 … 的顶层单名分支做锚` ✅ |
| ⑧ `--deep` 时跑 `git fsck --connectivity-only` | 对象库损坏 | 可选，默认关 |

**阳性对照全记录（本次在沙箱仓库 `/tmp/rex-gitprobe*` 实测）**：

| 编号 | 场景 | 期望 | 实测 |
|---|---|---|---|
| PC1 | 健康嵌套 worktree | PASS | ✅ rc=0 |
| PC2 | 移走嵌套 ref 文件 | FAIL | ✅ rc=1，三条 FAIL 全部命中 |
| PC3 | 还原后 | PASS（无假阳性） | ✅ rc=0 |
| PC4 | `reference-transaction` 拦删除 | 删除被否决 | ✅ git 报 `update aborted`，分支存活 |
| PC5 | unborn 后 `git add -A`（61 文件，阈值 50） | FAIL | ✅ rc=1（**第一次跑因我自己的参数解析 bug 返回 rc=2，已修**——正好示范了"护栏自身也要被阳性对照测过"） |
| PC6 | 清空暂存后 | PASS | ✅ rc=0 |
| PC7 | 全新仓库仅 1 个 root commit | **不应误报**（PASS + WARN） | ✅ rc=0，输出「reflog 只有 1 条 —— 判定为全新仓库的首个提交，不拦截」 |
| PC8 | 真实主 worktree `D:/1demo/AutoHotkeydemo` | 现状体检 | ✅ rc=0（PASS，但暴露 1 个 prunable worktree） |

### 6.3 检测改进的落点（各拦一类）

| 层级 | 措施 | 拦住的触发类 |
|---|---|---|
| 提交前 | `pre-commit` 调用 `git-ref-guard.sh` | 在"整棵树被重新 add"变成 root commit **之前**拦住 |
| ref 事务前 | `reference-transaction` 钩子 | 任何来源的嵌套 ref 删除 |
| 命令习惯 | `git status` 一律 `\| wc -l` 不接 `head`；git 写操作全部在主 worktree | 排查误导 + 触发源 |
| 日常巡检 | `bash git-ref-guard.sh --deep`（建议纳入 `check-gates.sh`） | 静默劣化（如 worktree 被外部删除而无人知） |
| 恢复后验证 | 恢复完必跑 `git-ref-guard.sh` + `git rev-list <ref> --not main \| wc -l`（应为 0） | 恢复不完整就继续工作 → 二次事故 |

---

## 7. 状态更新与沟通模板

### 7.1 内部通报（事中，SEV2）

```
【事故通报 SEV2】WorkBuddy worktree 分支指针丢失 — <日期> <时间>
状态：响应中 | 影响：提交链路中断 | 用户影响：无（本项目无线上服务）

现象：<git status 全 A（825 条）/ 新提交为无父 root commit / fatal: bad object HEAD>
已确认：提交对象 <是否仍在>（判据：git cat-file -e <sha>^{commit}）
已影响：<哪个 worktree / 哪个分支 / 未提交的 WIP 有哪些>

当前动作：
  1. 已停止在涉事 worktree 执行一切 git 写操作
  2. <恢复动作：写回 ref / commit-tree 重建 / fetch 远端>
  3. 未提交内容已 cp 到 $TEMP 备份

下一步（<时间> 前更新）：<...>
IC：<人名> | 响应：<人名>
⚠️ 所有人：在恢复完成前，不要在该 worktree 执行 git commit/reset/merge/rebase/stash。
```

### 7.2 恢复完成通报

```
【恢复完成】WorkBuddy worktree 分支指针丢失 — <日期> <时间>
状态：已恢复 | 历时：<MTTD> 发现 / <MTTR> 恢复

根因：<一句话；本次为「嵌套 ref 被外部删除 + 无护栏拦截」>
已确认无数据丢失，判据：
  - git diff --stat <原提交> <重建提交>   → 空（内容零差异）
  - git rev-list <ref> --not main | wc -l → 0（无仅存于该 ref 的提交）
  - 已建顶层单名锚点分支：<分支名>（防 gc --auto 回收）

残留：<prunable 注册项 / 待 prune / 待补 runbook>
行动项：P0 <...> / P1 <...>
复盘：<时间>

⚠️ 未消除前，涉事 worktree 仍只允许只读 git 操作。
```

### 7.3 排查规范（写进通报里的两条硬规则）

1. **判断索引是否干净：`git status --porcelain | wc -l`，禁用 `head`**（`head -20` 会把几百行 `A` 截掉，09-16 就是这么误判的）。
2. **判退出码不要接管道**：`git <cmd> | head` 取到的是 `head` 的 0。用 `${PIPESTATUS[0]}`
   （本次 PC4 实测也踩到：`git branch -D ... | head -3; echo rc=$?` 打出 0，但删除其实已被钩子否决）。

---

## 8. 事故响应就绪度评估

### 8.1 假设明天再来一次同类事故

| 指标 | 评估 | 依据 |
|---|---|---|
| **MTTD（发现）** | **数分钟 ~ 30 分钟以上，且不可控** | 当前**零自动检测**：唯一信号是「提交失败/历史异常」被人眼看到。第一次接触者还会被 `head -20` 误导，把「全 A」读成「只有 15 个改动」 |
| **MTTR（恢复）** | **5–15 分钟**（若由亲历者操作且有记忆可查）<br>**数小时或不可恢复**（若对象已丢且未推送） | 历史实测：#1 = 4分10秒；#2 ≤ 9分30秒；#3/#4 无记录 |
| 恢复成功率 | 指针丢失类 ≈ 100%（有成熟手法）<br>对象丢失类 **依赖"是否已推送"这一偶然因素** | 事故 #4 全靠 fetch 远端 |
| 有无 runbook | **有内容，但不在正式文档里** | 内容在 `.workbuddy-ai/memory/MEMORY.md`；`docs/developer-guide.md` 与 `docs/tech-debt-register.md` **零提及**（已 grep 核实） |
| 有无护栏 | **0**（无任何自动拦截或检测） | 阳性对照核实：pre-commit/commit-msg 不含 ref 检查；无 reference-transaction 钩子 |
| 演练 | 无 | — |

### 8.2 当前缺什么（按缺口大小排序）

1. **自动检测 = 0** —— 事故只能靠人眼撞见。（P1-1 补）
2. **runbook 不在开发者文档里** —— 只有 agent 记忆能看到，新成员/新会话看不到。（P1-4 补）
3. **记忆里的根因是错的** —— 比没有 runbook 更危险：它会把恢复者引向错误动作。（P0-4 补，最高优先）
4. **无"触发者无关"的硬拦截** —— 现在只能靠"人守纪律"，而纪律在并行 agent 场景下不可靠。（P0-3 补）
5. **无恢复后验证清单** —— 09-16 每次恢复完就继续干活，导致一天三次。（§6.3「恢复后验证」补）
6. **事故记录不完整** —— #3/#4 连时刻都没有，无法算 MTTR、无法复盘。（本次已为 #1/#2 补出精确时刻）

### 8.3 一句话结论

**可恢复性目前建立在两个偶然之上：① 提交恰好已推送；② 恢复者恰好是亲历者。**
这两条都不是设计。P0 四条做完之后，才能说"同类事故再来一次我们接得住"。

---

## 附录 A：本次的取证清单（可复现）

沙箱复现（不触碰项目仓库，可随时重跑）：

```bash
rm -rf /tmp/rex-gitprobe && mkdir -p /tmp/rex-gitprobe && cd /tmp/rex-gitprobe
git init -q -b main . && git config user.email t@t && git config user.name t
echo hello > a.txt && git add a.txt && git -c core.hooksPath=/dev/null commit -q -m c1
echo world >> a.txt && git -c core.hooksPath=/dev/null commit -q -am c2
git worktree add -q -b wb/main-abc ../rex-gitprobe-wt      # 嵌套 ref 建成 ✅
cd ../rex-gitprobe-wt
git branch wb/x "$(git rev-parse HEAD)"                     # 建成 ✅（证伪"git 建不出嵌套 ref"）
git update-ref refs/heads/zzdir/probe "$(git rev-parse HEAD)"  # 建成 ✅
git reset -q && cat /tmp/rex-gitprobe/.git/refs/heads/wb/main-abc   # ref 仍在 ✅
```

项目侧只读取证：

```bash
cat .git/worktrees/main-5f18c6a6/logs/HEAD          # 事故 #1/#2/#3 的精确时刻
git log -1 --format='%p' 31dc567                    # 空 → 确认 root commit
git show --stat 31dc567 | tail -1                   # 825 files changed, 345417 insertions(+)
git diff --stat b28b915 31dc567                     # 空 → 内容零丢失
git log -1 --format='%p' 655abac                    # 7780223 → 重建父链接正确
git ls-tree -r --name-only 315b988 | wc -l          # 825
git rev-list 9f9eb74 --not main | wc -l             # 0 → 当前无残余数据风险
git worktree list                                   # main-5f18c6a6 = prunable
```

## 附录 B：本报告明确**未证实**的内容（不编造）

1. 嵌套 ref 的**具体删除者**——只排除了「git 自身无法处理嵌套 ref」（已证伪），未确认是 WorkBuddy 生命周期管理、并发 agent、还是其他清理进程。
2. 事故 #3、#4 的**精确时刻与恢复耗时**——无记录。
3. 事故 #4 发生在主 worktree 还是嵌套 worktree——记忆记载有歧义。
4. **工时/成本损失**——无任何记录，无法量化。
