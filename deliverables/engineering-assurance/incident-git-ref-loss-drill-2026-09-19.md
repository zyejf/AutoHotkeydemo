# 事故响应报告：WorkBuddy 托管 worktree 嵌套 ref 被清空导致分支指针丢失

**日期**：2026-09-19（复盘）
**事故日期**：2026-09-16（当日连续多次触发）
**工作流**：工作流 3（事故响应）
**参与成员**：Rex（SRE 工程师，主响应）、Cody（代码审查师，git 行为与护栏评审）、Docu（技术文档师，沟通模板）
**涉事分支**：`refs/heads/workbuddy/main-5f18c6a6`（嵌套 ref，含 `/`）
**证据基线**：git 2.55.0.windows.3；所有结论标注「实测 / 记忆记载 / 推断」三档，推断一律显式标注

---

## 📌 TL;DR

- **SEV 评级：SEV2（研发基建严重降级）**。无用户可见影响（本项目无线上服务），但**提交链路一天中断 3 次**，且一度**真实丢失 3 个提交对象**，靠远端 fetch 才救回。
- **⚠️ 最重要的产出：团队长期记忆里的根因已被证伪。** 记忆记载的「git 在本环境建不出嵌套 ref」经两条独立证据推翻——仓库自己的 reflog 显示 20:38:50 `branch: Created from 315b988` 建成成功；`/tmp` 沙箱复现中 `reset`/`commit`/`merge --ff-only`/`stash` **四者都没**清掉嵌套 ref。**真根因是「嵌套 ref 被外部删除 + 零护栏 + 排查手法缺陷」**，而错误根因会把下次恢复引向「手工写 ref 文件」这条错路，跳过真正该做的第一步「先确认提交对象是否还在」。
- **「差一点就是 SEV1」**：丢失的 3 个对象当时恰好已推送。**可恢复性依赖于「是否已推送」这一偶然因素，而不是任何设计。**
- **当前残余数据风险：0**（仅嵌套 ref 可达提交 = 0，已被顶层分支 `techdebt-2026-09-16` 锚住）。残余隐患仅 1 个 `prunable` worktree 注册项 + 88KB 残留 index。
- **就绪度：MTTD 数分钟~30+ 分钟不可控（零自动检测）；MTTR 5–15 分钟（亲历者）或不可恢复（对象未推送）。runbook 只在 agent 记忆里，docs 零提及。**

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| 整体评级 | 🔴 事故真实发生，已恢复；**护栏缺失**，同类事故再来一次接不住 |
| SEV 评级 | **SEV2**（若丢失对象未推送即为 SEV1） |
| 阻塞项数量 | 0（当前无数据风险） |
| 关键行动项 | 9 条（P0 4 条 / P1 4 条 / P2 3 条） |
| 内容丢失量 | **0**（事故 #2 两棵树 `git diff --stat` 输出为空，只是父链接断了） |
| 真实丢失对象 | 3 个（`2bf5063`/`05b4b39`/`4c0b597`），已 fetch 恢复 |
| 当前残余风险 | **0 数据风险**；1 个 prunable 注册项待清理 |
| 建议下一步 | 立即执行 P0-3（装 `reference-transaction` 钩子）+ P0-4（纠正记忆错误根因） |

---

## 📅 一、事故时间线

> **时间来源**：`.git/worktrees/main-5f18c6a6/logs/HEAD` 与 `.git/logs/refs/heads/workbuddy/main-5f18c6a6`（reflog，epoch 秒 +0800），并用两个独立锚点校验换算正确：`9343c4a` author date 20:41:47 ↔ reflog 20:41:47；`84736a3` author date 20:47:01 ↔ reflog 20:47:01。
> **时刻未记录的事件一律写明「时刻未记录，顺序确定」，不编造。**

### 事故 #1：`git reset` 触发（症状 = `git status` 全 A）

| 时刻（+0800） | 事件 | 来源 |
|---|---|---|
| 17:46:55 | worktree 建立，分支 `workbuddy/main-5f18c6a6` 从 `main`(315b988) 创建 | reflog「branch: Created from main」+ 目录 mtime 17:46 吻合 |
| 17:46:56 | `reset: moving to HEAD`（1 秒后，疑似 `worktree add` 内部动作） | reflog |
| **20:34:40** | **`reset: moving to HEAD` → 引用文件消失**，worktree 变 unborn HEAD | reflog |
| 20:38:50 | `branch: Created from 315b988` → **恢复成功** | reflog（**与记忆「git 建不出嵌套 ref」直接矛盾**） |
| 20:39:14 / 20:40:33 | 两次无消息 ref 写入（update-ref 类），值同为 315b988 | reflog |
| 20:41:47 | `commit` 9343c4a 成功 → 恢复完成，工作流可用 | reflog + author date 双证 |

**恢复耗时（可测）：4 分 10 秒**（指针重建）；完全可用 20:41:47（约 7 分）。

### 事故 #2：`git commit` 触发（症状 = 新提交变无父 root commit）

| 时刻（+0800） | 事件 | 来源 |
|---|---|---|
| 20:54:18 | `commit` 7780223（记录事故 #1） | reflog |
| 22:15:36 | `commit` b28b915，**父 = 7780223（正确）** | 实测 `git log -1 --format='%p'` |
| **22:15:55** | **`commit (initial)` 31dc567 —— 仅隔 19 秒**，reflog 旧值为全零（unborn），新提交**无父** | reflog + 实测 parents=[] |
| — | 恢复：`commit-tree` 重建 `655abac`，父 = 7780223 | 实测 **重建正确** |
| 22:25:25 | `commit` a150b94 落在 655abac 之上 → 恢复完成 | reflog |

- **恢复耗时（区间）**：≤ 9 分 30 秒。
- **内容零丢失（硬证据）**：`git diff --stat b28b915 31dc567` **输出为空** → 两棵树完全一致，只是父链接断了。
- 记忆所称「825 files / 345417 insertions」经实测复核**属实**。

### 事故 #3：`git merge --ff-only` 触发

| 时刻（+0800） | 事件 | 来源 |
|---|---|---|
| 22:42:59 | `main` 上生成 merge commit `63500a3` | author date |
| **22:54:44** | worktree 执行 `merge main: Fast-forward` → 引用再次被清 | reflog；`ORIG_HEAD` mtime 22:54 吻合 |
| 恢复时刻 | **时刻未记录**（reflog 之后无条目） | — |

**顺序确定，恢复耗时不可测。**

### 事故 #4：`git stash push -- <path>` 触发（**不同失效模式：对象丢失，不是指针丢失**）

| 时刻 | 事件 | 来源 |
|---|---|---|
| 09:36:31 / 10:49:58 / 10:51:40 | 被吞掉的 3 个提交的 author date（`2bf5063`/`05b4b39`/`4c0b597`） | 实测 |
| **时刻未记录** | `git stash push -- <path>` 后，HEAD 指向的 3 个提交对象从 `.git/objects` 消失，`git status` 报 `fatal: bad object HEAD` | 记忆记载 |
| 时刻未记录 | 恢复靠 `git fetch` 远端（因 3 提交已推送） | 记忆记载 |

- **日期与时刻均未记录**，唯一边界：事件发生在 10:51:40 之后。
- ⚠️ **记忆记载有歧义**：该段写「`HEAD`/`refs/heads/main` 指向的 3 个提交」，但上下文发生在嵌套 worktree 的迭代中；**究竟发生在主 worktree 还是嵌套 worktree 无法从记载判定，本报告不据此下结论**。

### 事故 #5（本次调查的**新发现**，非 09-16 当日）：残留注册项

| 时刻 | 事件 | 来源 |
|---|---|---|
| 2026-09-17 16:03 | 嵌套 ref 停在 `9f9eb74`（最后一次写入） | author date + index mtime |
| 2026-09-18 21:42 | WorkBuddy 工作目录 `C:/Users/fei/WorkBuddy/Worktrees/AutoHotkeydemo/` 被**整体删除**（目录已空） | 实测目录 mtime |
| 当前 | `git worktree list` 报告该 worktree **`prunable`**：工作目录没了，`.git/worktrees/main-5f18c6a6/` 注册项与 88KB index 仍残留 | 实测 |

> 这条关键：证明**该 worktree 的目录生命周期由外部环境管理、且会被整体清除**，而 `.git` 侧注册项不会被同步清理。

---

## 📊 二、影响范围

| 指标 | 数值 | 取证方式 |
|------|------|----------|
| 事故当时 tracked 文件数 | **825** | 实测 `git ls-tree -r --name-only 315b988 \| wc -l`（**记忆数字核实通过**） |
| 当前 tracked 文件数 | 780 | 实测 `git ls-files \| wc -l` |
| root commit 的爆炸半径 | 825 files / 345417 insertions | 实测 `git show --stat 31dc567`（**记忆数字核实通过**） |
| **内容丢失量** | **0** | 实测 `git diff --stat b28b915 31dc567` 无输出 |
| 真实丢失的提交对象 | 3 个（`2bf5063`/`05b4b39`/`4c0b597`），已恢复 | 记忆记载 + 实测现仍存在 |
| 事故 #1 / #2 恢复耗时 | 4 分 10 秒 / ≤ 9 分 30 秒 | reflog 时间差 |
| 事故 #3 / #4 恢复耗时 | **不可测（时刻未记录）** | — |
| 工时/排查成本 | **不可量化（无记录），不编造** | — |
| 当前残余数据风险 | **0**（仅嵌套 ref 可达提交 = 0；已被 `techdebt-2026-09-16` 顶层分支锚住） | 实测 |
| 当前残余隐患 | 1 个 `prunable` worktree 注册项 + 88KB 残留 index | 实测 |
| `main` 领先嵌套 ref | 109 个提交（嵌套 ref 已严重过期） | 实测 `git rev-list --count 9f9eb74..main` |

**角色分配**：IC 甄宇航（主理人，决策是否中断迭代/批准清理）；响应者 Rex（SRE，执行恢复+时间线+本报告）；沟通 Docu（内部通报）；领域顾问 Cody（git 行为与护栏评审）；记录员 Rex —— **本角色在 09-16 缺位，是 #3/#4 无时刻记录的原因**。

---

## 🚨 三、SEV 评级：**SEV2（研发基建严重降级）**

评级采用可审计的五维打分，而非整体印象：

| 维度 | 实测/记载 | 打分 |
|------|-----------|------|
| 用户可见影响 | 个人/小团队桌面应用，**无线上服务**，无外部用户受影响 | 不构成 SEV1 |
| 核心工作流中断 | 提交链路一天内 **3 次**中断（reset / commit / merge 各一次），第 4 次导致对象真实丢失 | 严重（+） |
| 数据完整性 | 提交对象一度**真实丢失** 3 个，靠远端 fetch 才救回 | 严重（+） |
| 可恢复性 | 4 次中 3 次本地可恢复，1 次依赖远端 | 中等（±） |
| 复发概率 | 触发条件 09-16 全天未消除，表现为「每次移动 ref 的操作都触发」 | 高（+） |

- **判 SEV2 而非 SEV1**：无用户可见影响，且存在已验证的本地恢复路径。
- **判 SEV2 而非 SEV3**：主工作流（提交）完全阻断，且已发生真实的提交对象丢失。
- **⚠️「差一点就是 SEV1」**：#4 丢失的 3 个对象**当时已推送**，所以能 fetch 回来。若尚未推送即为**不可恢复的提交历史丢失**，应定为 SEV1。**可恢复性依赖于「是否已推送」这一偶然因素，而不是依赖于任何设计。**

---

## 🔍 四、根因分析（5 Why）

### 4.0 前置：先推翻一个已被写进长期记忆的错误根因（本次复盘的取证重点）

`MEMORY.md` 现行记述：

> 「git 在本环境**建不出**嵌套 ref：`git branch workbuddy/x`、`update-ref refs/heads/zzdir/probe` 都返回 0 却什么都没建」

**这条是错的。** 两条独立证据：

**证据 A —— 仓库自己的 reflog（最硬）**：事故 #1 恢复时 reflog 明确记录 `20:38:50 branch: Created from 315b988`，且 `.git/refs/heads/workbuddy/main-5f18c6a6` 至今存在并指向 `9f9eb74`。**git 当时就是建成了这个嵌套 ref。**

**证据 B —— 阳性对照复现（`/tmp` 沙箱仓库实测，git 2.55.0）**：

| 操作 | 记忆断言 | 实测结果 |
|------|---------|---------|
| `git worktree add -b wb/main-abc`（嵌套名） | — | ✅ 建成 |
| `git branch wb/x <sha>` | 静默失败、建不出 | ✅ **rc=0 且建成** |
| `git update-ref refs/heads/zzdir/probe <sha>` | 静默失败、建不出 | ✅ **rc=0 且建成** |
| `git reset -q` | 会清掉嵌套 ref | ❌ **ref 完好无损** |
| `git commit` | 会变 root commit | ❌ **父链接正确** |
| `git merge --ff-only` | 会清掉嵌套 ref | ❌ **ref 完好无损** |
| `git stash push -- <path>` | 会清掉嵌套 ref | ❌ **ref 完好无损** |

**为什么这条纠错很重要**：它会让响应者把「手工写 ref 文件」当成唯一手段，从而跳过真正该做的第一步 —— **先确认提交对象是否还在**（对象没了，写 ref 也无效；这正是事故 #4 的情形）。

### 4.1 五问（+1）

**Why 1：为什么分支指针会丢？**
因为有东西把 `.git/refs/heads/workbuddy/` **整个目录连同父目录一起删掉了**。「父目录一起没」符合 git 自身 ref-delete 路径（删 ref 后 `rmdir` 空父目录）或「整体递归删除」的特征。反正**不是**「git 写不进去」。

**Why 2：为什么删了没人拦得住？**
因为**没有任何护栏**（已用阳性对照核实，非读代码推断）：
- 现行 `scripts/hooks/pre-commit`（`core.hooksPath=scripts/hooks`）只做 4 件事：敏感文件、构建产物、>1MB 大文件、临时文件 —— **不检查 ref 是否存在**；
- `commit-msg` 只管提交信息格式；
- **无 `reference-transaction` 钩子**（git 唯一能在 ref 事务提交前否决的钩子）—— 实测**该钩子有能力拦住**；
- `docs/developer-guide.md`、`docs/tech-debt-register.md` **零提及**本事故（已 grep 核实）。

**Why 3：为什么会把工作放在一个嵌套 ref 的 worktree 里？**
因为分支名 `workbuddy/main-5f18c6a6` 由 **WorkBuddy 托管 git worktree 自动生成**（`workbuddy/<源分支>-<hash>`），**命名不在项目控制范围内**，项目只能接受它、无法改成顶层单名。

**Why 4：为什么没早点发现？**
两个原因叠加：
- **症状强误导**：`git status` 全 `A`（像"仓库没了"）与「提交变 root commit」（像"历史被重写"）都不指向"指针丢了"；
- **排查手法本身有缺陷**：`git status --porcelain | head -20` 把几百行截断 → 误判索引干净 → 在错误前提下继续提交 → 制造出 #2。

**Why 5：为什么同一天能连着犯三次（并搭上一次对象丢失）？**
因为**每次恢复只修指针，不消除触发条件**：恢复后立刻继续用同一个 worktree 做 ref 移动操作。而且**根因被误记**，导致对策停留在「手工写文件」这个补救动作上，没有指向「别在这里移动 ref」。

**Why 6（系统性根因，本报告认为这才是真根因）：**
**团队的判断未经实测即落笔，并被当作事实写进权威记忆。**
同一天（2026-09-19）团队在「守护是否存在」上犯过三次同类错误（TD-007 描述前提已证伪 / TD-058① 差集检查本就存在 / TD-058② G1 已在守），本事故是同一个缺陷换了个载体：**一份声称记录"事故根因"的记忆，自己写错了根因**。
链条是：观察到现象 → 用未验证假设（"git 建不出嵌套 ref"）解释 → 写进长期记忆 → 后续所有人按错误根因采取对策 → **真正的数据丢失风险（对象不可达 → `gc --auto` 回收）从未被正面处理**。

### 4.2 真正的数据丢失机制（推断，已标注）

指针丢失本身**不丢数据**；丢数据的是第二步：

```
嵌套 ref 被删 → 提交变为不可达 → git gc --auto（commit/merge/fetch 后自动触发）回收不可达对象
             → "fatal: bad object HEAD" → 若未推送远端 = 永久丢失
```

这解释了为什么记忆里「顺手建一个顶层单名分支做兜底」这条对策**真的有效** —— 它不是迷信，是给对象加了一个可达锚点。实测现状也正被 `techdebt-2026-09-16` 锚住。

**触发者推断（未证实，明确标注）**：综合事故 #5（WorkBuddy 工作目录于 09-18 21:42 被整体删除而 `.git` 注册项残留），最可能是 **WorkBuddy 的 worktree 生命周期管理 / 沙箱清理在 git 写 ref 的时间窗内动了该路径**，而非 git 自身缺陷（已被阳性对照排除）。**此推断未证实**，P0 行动项按「无论触发者是谁都能防住」来设计。

---

## 🛡️ 五、预防措施与检测改进

> 设计原则：**提前发现**，而不是事后救火。每条护栏列出「能拦住哪一类触发」+「阳性对照结果」。

### 5.1 `reference-transaction` 钩子（唯一能在 ref 事务提交**前**否决的钩子）

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

**阳性对照（实测）**：沙箱安装该钩子后执行 `git branch -D wb/x`：

```
[BLOCKED] 禁止删除嵌套 ref: refs/heads/wb/x
fatal: in 'prepared' phase, update aborted by the reference-transaction hook
wb/x 是否还在: 12fe26b1d3a086da8bbf51702d368a53f2a8121c   ← 分支存活，删除被真正否决
```

**能拦住**：事故 #1/#2/#3 的共同环节（嵌套 ref 被删除）—— **无论删除者是谁**（git 自身、外部清理、另一并发进程）。这是唯一一条「触发者无关」的护栏，故列为 P0。

### 5.2 `git-ref-guard.sh`（提交前置 + 日常巡检）

已交付：`deliverables/engineering-assurance/git-ref-guard.sh`（只读，绝不写 `.git`）。

| 检查项 | 拦住哪一类触发 | 阳性对照结果 |
|---|---|---|
| ① HEAD 可解析（`rev-parse --verify HEAD`） | 「`fatal: bad object HEAD`」（事故 #4） | PC2：移走 ref 文件 → `[FAIL] HEAD 不可解析`，rc=1 ✅ |
| ② 当前分支 ref 存在且可解析 | 事故 #1/#3 的指针丢失 | PC2 → `[FAIL] 分支 … 的引用不存在` ✅ |
| ③ 分支名含 `/` → 告警 + 改道提示 | 事故特征形态的**提前预警**（还没坏就提醒别在这里写） | PC1 健康态即告警 ✅ |
| ④ 暂存新增数 > 阈值（默认 50），用 `wc -l` 不用 `head` | 事故 #2「整棵树被重新 add」+ 顺带治掉 `head -20` 截断误判 | PC5：注入 61 个 A → `[FAIL] 暂存区新增 61 个文件 > 阈值 50`，rc=1 ✅ |
| ⑤ HEAD 是无父 root commit 且 reflog >1 条 | 事故 #2「提交变 root commit」 | 见 PC7 |
| ⑥ `prunable` worktree 检测 | 事故 #5（注册项残留、工作目录已被外部删除） | PC8 在真实仓库实测：`[WARN] 存在 1 个 prunable worktree` ✅ |
| ⑦ 嵌套 ref 是否有顶层单名锚点 | 对象被 `gc --auto` 回收（事故 #4 丢失机制） | PC1 → `[WARN] 没有指向 … 的顶层单名分支做锚` ✅ |
| ⑧ `--deep` 时跑 `git fsck --connectivity-only` | 对象库损坏 | 可选，默认关 |

**阳性对照全记录（沙箱 `/tmp/rex-gitprobe*` 实测）**：

| 编号 | 场景 | 期望 | 实测 |
|---|---|---|---|
| PC1 | 健康嵌套 worktree | PASS | ✅ rc=0 |
| PC2 | 移走嵌套 ref 文件 | FAIL | ✅ rc=1，三条 FAIL 全部命中 |
| PC3 | 还原后 | PASS（无假阳性） | ✅ rc=0 |
| PC4 | `reference-transaction` 拦删除 | 删除被否决 | ✅ git 报 `update aborted`，分支存活 |
| PC5 | unborn 后 `git add -A`（61 文件，阈值 50） | FAIL | ✅ rc=1（**第一次跑因护栏自身参数解析 bug 返回 rc=2，已修** —— 正好示范了"护栏自身也要被阳性对照测过"） |
| PC6 | 清空暂存后 | PASS | ✅ rc=0 |
| PC7 | 全新仓库仅 1 个 root commit | **不应误报**（PASS + WARN） | ✅ rc=0，输出「reflog 只有 1 条 —— 判定为全新仓库的首个提交，不拦截」 |
| PC8 | 真实主 worktree `D:/1demo/AutoHotkeydemo` | 现状体检 | ✅ rc=0（PASS，但暴露 1 个 prunable worktree） |

### 5.3 检测改进的落点（各拦一类）

| 层级 | 措施 | 拦住的触发类 |
|---|---|---|
| 提交前 | `pre-commit` 调用 `git-ref-guard.sh` | 在「整棵树被重新 add」变成 root commit **之前**拦住 |
| ref 事务前 | `reference-transaction` 钩子 | 任何来源的嵌套 ref 删除 |
| 命令习惯 | `git status` 一律 `\| wc -l` 不接 `head`；git 写操作全部在主 worktree | 排查误导 + 触发源 |
| 日常巡检 | `bash git-ref-guard.sh --deep`（建议纳入 `check-gates.sh`） | 静默劣化（如 worktree 被外部删除而无人知） |
| 恢复后验证 | 恢复完必跑 `git-ref-guard.sh` + `git rev-list <ref> --not main \| wc -l`（应为 0） | 恢复不完整就继续工作 → 二次事故 |

---

## 📢 六、沟通模板

### 6.1 内部通报（事中，SEV2）

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

### 6.2 恢复完成通报

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

### 6.3 排查规范（写进通报的两条硬规则）

1. **判断索引是否干净：`git status --porcelain | wc -l`，禁用 `head`**（`head -20` 会把几百行 `A` 截掉，09-16 就是这么误判的）。
2. **判退出码不要接管道**：`git <cmd> | head` 取到的是 `head` 的 0。用 `${PIPESTATUS[0]}`（本次 PC4 实测也踩到：`git branch -D ... | head -3; echo rc=$?` 打出 0，但删除其实已被钩子否决）。

---

## ✅ 七、行动清单（按优先级排序）

| # | 行动 | 负责角色 | 紧急度 | 拦住什么 |
|---|------|---------|--------|---------|
| 1 | **嵌套 worktree 内禁止一切 ref 移动操作**：只用只读 git 命令；`commit`/`merge`/`rebase`/`reset`/`stash` 一律切到主 worktree `D:/1demo/AutoHotkeydemo` | Rex（流程） | P0 | 事故 #1/#2/#3 全部触发源 |
| 2 | **给嵌套 ref 挂顶层单名锚点**（每次同步后必做）：`git branch <单名> "$(git rev-parse refs/heads/workbuddy/main-5f18c6a6)"` | Rex | P0 | 对象被 `gc --auto` 回收（#4 丢失机制） |
| 3 | **安装 `reference-transaction` 钩子**（脚本见 §5.1），否决一切对 `refs/heads/*/*` 的删除 | Rex + Cody | P0 | 任何来源的嵌套 ref 删除（**实测有效**，唯一「触发者无关」的硬拦截） |
| 4 | **纠正记忆里的错误根因**：把 `MEMORY.md` 中「git 建不出嵌套 ref / git branch、update-ref 都静默失败」整段改为「**已证伪**：git 2.55 实测可正常创建/更新/移动嵌套 ref；真因是外部删除 + 无护栏」，并附本报告阳性对照 | Rex + Docu | P0 | 防止下一次恢复被错误根因带偏 |
| 5 | 安装 `git-ref-guard.sh` 为提交前置检查（`scripts/`，`pre-commit` 首行调用） | Rex | P1 | 在「整棵树被重新 add」变成 root commit 之前拦住 |
| 6 | **修复 pre-commit 的性能诱因**：现钩子对每个暂存文件 `wc -c`（825 文件逐文件 fork，跑到超时被 SIGTERM）。改 `git diff --cached --name-only -z \| xargs -0 stat -c '%s %n'` 一次性取体积 | Cody | P1 | 消除「提交被中途 SIGTERM」这一加重因素 |
| 7 | 清理残留注册项：`git worktree prune`（**需 IC 批准**，属只读语义外的清理） | Rex | P1 | prunable 注册项 + 88KB 残留 index |
| 8 | 把事故写进正式 runbook：`docs/developer-guide.md` 新增「§worktree 嵌套 ref 事故处置」（当前 docs 零提及，已核实） | Docu | P1 | runbook 只在 agent 记忆里 → 新成员/新会话看不到 |
| 9 | 排查规范入文档 + 建立「写入记忆前必须做阳性对照」机制 + 每年沙箱演练一次 | Docu + Rex | P2 | `head -20` 误判；错误根因再次入库；护栏年久失效 |

---

## 📈 八、事故响应就绪度评估

| 指标 | 评估 | 依据 |
|---|---|---|
| **MTTD（发现）** | **数分钟 ~ 30 分钟以上，且不可控** | 当前**零自动检测**：唯一信号是「提交失败/历史异常」被人眼看到。第一次接触者还会被 `head -20` 误导，把「全 A」读成「只有 15 个改动」 |
| **MTTR（恢复）** | **5–15 分钟**（亲历者操作且有记忆可查）/ **数小时或不可恢复**（对象已丢且未推送） | 历史实测：#1 = 4分10秒；#2 ≤ 9分30秒；#3/#4 无记录 |
| 恢复成功率 | 指针丢失类 ≈ 100%（有成熟手法）/ 对象丢失类 **依赖"是否已推送"这一偶然因素** | 事故 #4 全靠 fetch 远端 |
| 有无 runbook | **有内容，但不在正式文档里** | 内容在 `.workbuddy-ai/memory/MEMORY.md`；`docs/developer-guide.md` 与 `tech-debt-register.md` **零提及**（已 grep 核实） |
| 有无护栏 | **0**（无任何自动拦截或检测） | 阳性对照核实：pre-commit/commit-msg 不含 ref 检查；无 reference-transaction 钩子 |
| 演练 | 无 | — |

### 当前缺什么（按缺口大小排序）

1. **自动检测 = 0** —— 事故只能靠人眼撞见。（行动项 5 补）
2. **runbook 不在开发者文档里** —— 只有 agent 记忆能看到。（行动项 8 补）
3. **记忆里的根因是错的** —— **比没有 runbook 更危险**：它会把恢复者引向错误动作。（行动项 4 补，最高优先）
4. **无"触发者无关"的硬拦截** —— 现在只能靠"人守纪律"，而纪律在并行 agent 场景下不可靠。（行动项 3 补）
5. **无恢复后验证清单** —— 09-16 每次恢复完就继续干活，导致一天三次。（§5.3「恢复后验证」补）
6. **事故记录不完整** —— #3/#4 连时刻都没有，无法算 MTTR、无法复盘。（本次已为 #1/#2 补出精确时刻）

### 一句话结论

**可恢复性目前建立在两个偶然之上：① 提交恰好已推送；② 恢复者恰好是亲历者。这两条都不是设计。**
P0 四条做完之后，才能说"同类事故再来一次我们接得住"。

---

## ⚠️ 九、待完善 / 已知局限

本报告明确**未证实**的内容（不编造）：

1. **嵌套 ref 的具体删除者** —— 只排除了「git 自身无法处理嵌套 ref」（已证伪），未确认是 WorkBuddy 生命周期管理、并发 agent、还是其他清理进程。
2. **事故 #3、#4 的精确时刻与恢复耗时** —— 无记录。
3. **事故 #4 发生在主 worktree 还是嵌套 worktree** —— 记忆记载有歧义。
4. **工时/成本损失** —— 无任何记录，无法量化。
5. `git-ref-guard.sh` 的 PC5 首跑曾因护栏自身 bug 返回 rc=2，已修复并复测；护栏自身同样需要被阳性对照覆盖，否则会出现「护栏静默失效」。

---

## 📚 十、数据来源 & 成员产出索引

- **Rex（SRE）原始产出**：`deliverables/engineering-assurance/_raw-rex-incident-2026-09-19.md`（分诊、时间线、量化、5 Why、P0/P1/P2 行动项、沟通模板、就绪度评估、附录取证清单）
- **Rex 交付的护栏脚本**：`deliverables/engineering-assurance/git-ref-guard.sh`（8 项检查，8 组阳性对照全过）
- **Cody（代码审查师）**：git 行为与 `reference-transaction` 钩子实现评审
- **Docu（技术文档师）**：沟通模板与 runbook 落点建议
- **项目侧只读取证命令**：
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
- **沙箱复现脚本（不触碰项目仓库，可随时重跑）**：见原始报告附录 A。

---

> 本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
