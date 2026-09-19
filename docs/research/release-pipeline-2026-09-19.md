# 发布链路方案与 TD-083 可行性论证（2026-09-19）

**作者：** 系统架构师（阿奇）
**范围：** 任务 #4（阶段 3 发布链路）｜阻断项 **B3**（无 GitHub Release 步骤）／**B13**（发布产物零冒烟）｜债项 **TD-074 / TD-083 / TD-078**
**取证方式：** 全部为**实读代码／实调 API／实跑 grep**；凡属推断处均显式标注「推断」或「未验证」。

> ⚠️ **关于 `ci.yml` 行号（2026-09-19 两处订正，必读）**
> 1. 本文所有 `ci.yml:N` 行号以我取证时的 **913 行版本**为准。**该文件在此后被两次改写（均未提交）**：① Tessa 改写 G3h 段（取证时 156-171 行，净 +13）；② 主理人为 release job 加第三条护栏（`github.ref == 'refs/heads/main'`，净 +7）。故 **171 行之后的行号已累计漂移约 +20**（913 → 926 → **933**）。**§9 的补丁按 933 行版给出**；引用其余章节时请以**锚点文本**为准，不要只认行号。
> 2. `on.push` 的表述已按 Rex 的复核订正：它**当前没有 `tags:` 过滤器**，详见 §1.2 与 §2 选项 A。

---

## 0. 结论先行（含「已验证」与「理论上可行」的分界）

| # | 结论 | 状态 |
|---|---|---|
| C1 | 现有 `release` job 的触发条件是 `workflow_dispatch && inputs.build_release`（默认 false），**与 tag 无关**；`ci.yml` 全文 913 行**没有任何** `gh release` / `softprops/action-gh-release` / `on.push.tags` 字样 | **已验证**（实读 ci.yml:786-913、:22-56） |
| C2 | 但「从未发版」这句话**需要修正**：远端**已存在一个 Release** `v0.1.0`（2026-06-28 发布，**0 个资产**），tag `v0.1.0` 指向提交 `0fbfce5`（2026-06-28），较当前 HEAD `93d88d6` **落后 363 个提交**（约 3 个月） | **已验证**（GitHub API 实调 + `git rev-list --count 0fbfce5..HEAD`）。⚠️ HEAD 在我取证期间由 `9fd8a69` 前进到 `93d88d6`（Docu 的文档入库提交），本报告后续引用一律以 `93d88d6` 为锚 |
| C3 | 因此若用 `workflow_dispatch` 选 ref=`v0.1.0` 构建，产出的是 **2026-06-28 的旧代码**，会得到一个「看起来发版成功、内容却是三个月前」的包 | **已验证**（tag 指向 commit 实查） |
| C3′ | ⚠️ **表述修正（Rex 2026-09-19 复核，已采纳）**：`on.push` 当前**根本没有 `tags:` 过滤器**（`ci.yml:23-24` 只有 `branches: [main, master]`），`tags: ['v*']` 只是注释里的**未来待办**，不是既有触发器。故准确表述是「**现在没有、将来加了也对已存在的 v0.1.0 无效**」，而不是「已有的 tag 触发失效了」 | **已验证**（`grep -n "tags:" .github/workflows/ci.yml` 仅命中 1 处注释） |
| C4 | 本机 `github.com` 直连不可达（curl 000），但 `api.github.com` 200；`gh` CLI 已装（v2.89.0）但**未登录** | **已验证** |
| C5 | 发布全链路**可以不经过本机 git push**：GitHub 的 Release/Tag 可通过 **API 创建**（`gh release create --target <sha>` 由 runner 执行，用 `GITHUB_TOKEN`），不需要 `git push` | **已验证 API 可达**；`gh release create --target` 的建 tag 行为属**工具已知语义、本机因未登录未实跑**，首次执行须人工盯 |
| C6 | 产物冒烟**可自动化到「静默安装 → 启动 → 配置落盘 → 拉起 AHK 子进程 → IPC 握手并认证成功」**，判据全部可从**磁盘上的日志文件**与**进程表**读取，无需人工 | **方案已设计，断言字符串已从代码实证**；整条 job **尚未在 CI 上跑过一次** |
| C7 | 冒烟**不能自动化**的部分：真实按键触发连招、SmartScreen 告警表现、离线安装。前者受限于 E2E 通道当前是红的（TD-061） | **已验证**（ci.yml:694-697 方案 1 已证伪） |
| C8 | **TD-083 不需要 GUI 也能验证**。「需要 GUI」这个判断只对了一半：它把「要跑一个应用」和「要人用鼠标键盘操作」混为一谈 | 见 §5，含三条可执行路径与一份 15 分钟人工脚本 |
| C9 | 附带发现（不在本任务范围，但影响发布可信度）：CI 的 `G3h watchdog（--ignored）` 步骤**当前跑 0 条用例**却显示绿灯 —— 全仓已无一条活的 `#[ignore]` 属性（8 处命中全在 `//!` 注释里） | **已验证**（grep 实查） |

> **C2/C3 是本轮最重要的发现。** 它把 B3 的性质从「缺一个步骤」改成了「已有的 Release 是个指向旧提交的空壳」—— 补步骤时必须同时处理它，否则补完会得到一个**错误的发布**。

---

## 1. 现状取证

### 1.1 CI job 清单（`.github/workflows/ci.yml`，实读）

| job | 类型 | 触发条件 | 是否阻断 |
|---|---|---|---|
| `gates` | 校验（四闸门 G1–G4） | push main/master + PR + 手动 | 是 |
| `js-lint` | 校验 | 同上 | 是 |
| `coverage` | 校验（棘轮） | 同上 | 是 |
| `security-audit` | 校验 | 同上 | 是 |
| `miri` / `fuzz` / `bench` | 信号（continue-on-error） | push / 每周日 | 否 |
| `ahk-bench` | **门禁**（T11） | push main / 手动重设基线 | 是 |
| `e2e` | 校验 | `workflow_dispatch && inputs.run_e2e`（默认 false） | 手动才跑 |
| **`release`** | **产物** | `workflow_dispatch && inputs.build_release`（**默认 false**） | 手动才跑 |

**`release` job 为什么一次都没跑过（两层原因，缺一不可）：**

1. **事件层**：`if: github.event_name == 'workflow_dispatch' && inputs.build_release`。默认 false，必须有人在 GitHub UI 上手动勾选。
2. **路径层**：全文**唯一**含 `tauri build` 的 `e2e` job 被 `inputs.run_e2e`（默认 false）挡住，且 ci.yml:753-754 自己写明「这条构建路径在 CI 上从未被验证过」。

**`release` job 现在做对了什么（不要重复造）：**
- `needs: gates`（ci.yml:792）—— 建立在四闸门绿之上，正确。
- 产物名/校验和**从磁盘实际产物推导**（ci.yml:852-901），不硬编码文件名 —— 正确，`productName` 是「ASD - 技能管理器」（含空格与中文）。
- `installers.Count -eq 0` 时 `throw`（ci.yml:864-866）—— 挡住了「构建返回 0 但没出包」这个最危险的静默失败。
- SHA256SUMS 显式写**不带 BOM** 的 UTF-8（ci.yml:878-882）。
- `if-no-files-found: error`（ci.yml:913）。

**`release` job 缺什么（B3 的全部内容）：**
- ❌ 无 `on.push.tags` 触发器。
- ❌ 无任何 Release 创建步骤（全文无 `gh release` / `softprops`）。
- ❌ 无 `permissions: contents: write`（默认 `GITHUB_TOKEN` 可能只有读权限，创建 Release 必红且报错信息有误导性 —— 本仓 `security-audit` job 已在 TD-014 踩过同型坑）。
- ❌ 无产物冒烟（B13）。
- ❌ `retention-days: 90` 的 artifact 是**唯一落点**，且它是一个会过期的 CI 产物，不是分发渠道。

### 1.2 远端真实状态（GitHub API 实调，只读）

```
GET /repos/zyejf/AutoHotkeydemo/releases        → 200，1 条
  tag_name    : v0.1.0
  name        : v0.1.0 - ASD 技能管理器首个发布
  created_at  : 2026-06-28T02:30:47Z
  published_at: 2026-06-28T02:46:26Z
  draft       : false
  prerelease  : false
  assets      : 0                      ← 空壳
  target_commitish: main

GET /repos/zyejf/AutoHotkeydemo/tags            → 1 条：v0.1.0 → 0fbfce52…
本地 git tag -l                                  → v0.1.0 → 0fbfce5
本地 git rev-parse --short HEAD                  → 93d88d6（2026-09-19，Docu 的文档入库提交）
git rev-list --count 0fbfce5..HEAD               → 363
```

`0fbfce5` 的提交信息：`chore(config): 移除 AutoHotkeydemo.zip 大文件跟踪并添加 .gitignore 规则`，日期 **2026-06-28**。

⇒ **当前唯一的 Release 指向的是三个月前的提交，且没有资产。** 这不是「没有发布」，是「有一个错误的发布」。

**`on.push` 的真实形态（Rex 2026-09-19 修正，我已复核采纳）**：`ci.yml:22-28` 只有 `branches: [main, master]` / `pull_request` / `schedule` / `workflow_dispatch`，**没有 `tags:` 过滤器**。全文 `grep -n "tags:"` **仅 1 处命中**，且是 `release` job 头部注释里的**未来待办**：「待本 job 手动跑绿一次后，再按需在 `on.push` 下加 `tags: ['v*']` 接自动发布」。

⇒ 准确表述应为：**「刻意不接 tag 触发」是一个已写明理由的决策**（理由见该注释：release 路径从未验证过 + `workflow_dispatch` 可任选 ref），**不是「触发器存在但失效」**。我初稿写的「这条路已经死了」用词不准，已订正。核心风险不变：将来若真加了 `tags: ['v*']`，它对已存在的 `v0.1.0` **永远不会触发**，必须打新 tag。

### 1.3 本机环境（实查）

| 项 | 实测 | 对方案的影响 |
|---|---|---|
| `curl https://github.com` | **000** | 本机 `git push` / `git push --tags` 不可用 → **发布不能依赖本机推 tag** |
| `curl https://api.github.com` | **200** | Release 可通过 API 操作 |
| `gh --version` | 2.89.0 | 已装 |
| `gh auth status` | **未登录任何 host** | 本机不能用 `gh` 发布；但 **CI runner 上用 `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` 不需要额外登录** |
| `git status -b` | `main...origin/main`，工作树有 3 改 + 1 未跟踪 | 与发布无关，但提醒：改动只能留在工作树 |

---

## 2. ADR-003：发布链路的触发与落地方式

**状态:** Proposed
**日期:** 2026-09-19
**决策人:** 系统架构师（阿奇）· 待工程督导复核
**关联:** B3 / TD-074 / TD-078 / TD-081

### 背景

需要一个能产出**可下载、可回滚**产物的发布链路。约束（全部已实测）：

- **K1** 本机不能 push（github.com 000）→ 任何依赖「先在本地打 tag 再 push」的方案都不可执行。
- **K2** tag `v0.1.0` 已存在于远端且指向旧提交 → `on.push.tags: ['v*']` 对新版本之外的路径无效；对已存在的 tag **永不触发**。
- **K3** 已有一个指向旧提交的空壳 Release `v0.1.0` → 不能「上传资产补完它」，那会制造一个**标注源码与实际产物不符**的发布。
- **K4** 产物未签名、未接 updater（TD-075）→ 手动重新下载是唯一升级路径，**Release 落点是刚需，不是锦上添花**。
- **K5** `tauri.conf.json` 版本仍是 `0.1.0`，而 UI 自述 v3.0、AGENTS.md 写 v4.0（TD-078）→ 版本号不能拿来做权威溯源，必须另加 commit sha。

### 选项分析

#### 选项 A：`on.push.tags: ['v*']` 自动发布（ci.yml:759 里写的「待办」）

| 维度 | 评估 |
|---|---|
| 复杂度 | Low |
| 成本 | 0 |
| 可行性 | **✗ 不选**（注意：它不是「既有触发器失效」，`on.push` 当前**根本没有** `tags:` 过滤器 —— Rex 修正） |

**否决理由**：① 即便将来加上 `tags: ['v*']`，它也**永远不会为已存在的 `v0.1.0` 触发**，而 `0.1.0` 正是当前 `tauri.conf.json` 的版本号 → 首次发布会被无限期推迟；② 新建 tag 若走 push，则受 K1（本机 github.com 000）阻塞。

**给 ci.yml 那条待办注释的修正建议**（原文：「待本 job 手动跑绿一次后，再按需在 `on.push` 下加 `tags: ['v*']` 接自动发布」）：
> 补一句 ——「⚠️ 加 `tags: ['v*']` 对**已存在的 `v0.1.0` 无效**（tag 已存在，不会再有 push 事件），必须打**新 tag** 才会触发；且新 tag 需具备 push 能力。参见 `docs/research/release-pipeline-2026-09-19.md` §1.2。」

⚠️ **一条未验证的风险，首次接入 tag 触发时必须实测**：`gh release create`（本方案选项 C）会**通过 API 创建 tag**。API 创建的 tag 是否会触发 `on.push` 的 `tags` 过滤器，GitHub 的行为在不同时期有差异，**我未实跑也未查证，不做断言**。若会触发，则「本 job 建 Release 建 tag」＋「`tags: ['v*']` 触发本 job」会形成**二次触发/递归**。⇒ 将来若真要接 tag 自动发布，必须先跑一次验证，并在 job 上设 `concurrency` 或显式排除 bot 触发。

#### 选项 B：`workflow_dispatch` + 上传到**已存在的** `v0.1.0` Release

| 维度 | 评估 |
|---|---|
| 复杂度 | Low |
| 成本 | 0 |
| 风险 | **高：制造假一致性** |

**否决理由**：`v0.1.0` Release 的 `target_commitish` 指向 2026-06-28 的 `0fbfce5`。把 HEAD（`9fd8a69`）构建出的包装进去后，用户从 Release 页点「Source code」看到的是三个月前的代码，下载到的却是今天的包 —— **这正是本仓反复强调的「假守护比不守更危险」在发布域的对应物**。回滚时按 Release 标注的 commit 去定位，会定位到错的提交。

#### 选项 C：`workflow_dispatch` + 作业内 `gh release create --target $GITHUB_SHA`

| 维度 | 评估 |
|---|---|
| 复杂度 | Med（2 个 input + 1 个发布步骤 + 幂等保护） |
| 成本 | 0（runner 自带 `gh`） |
| 可行性 | **✓ 可行（API 侧已验证；`gh release create` 建 tag 行为待首次实跑确认）** |
| 副作用 | 会在远端**创建 tag**（由 runner 通过 API 完成），无需 push |

**选它。** 理由：
1. **绕开 K1**：tag 由 runner 用 `GITHUB_TOKEN` 通过 API 创建，本机不需要 push。
2. **绕开 K2/K3**：新 tag 与新 Release 都在**实际构建的 commit** 上生成（`--target ${{ github.sha }}`），产物与标注源码同源。
3. **不引入新的第三方 action**：runner 预装 `gh`，无供应链新增面（本仓 `security-audit` 与 TD-020 对第三方依赖敏感）。
4. **保留人工闸门**：`workflow_dispatch` 天生不产生自动红灯，符合 ci.yml:755-758 已经写明的取舍。

#### 选项 D：`softprops/action-gh-release@v2`

| 维度 | 评估 |
|---|---|
| 复杂度 | Low |
| 成本 | 引入 1 个第三方 action |
| 可行性 | ✓ 可行 |

**未选**，但不是否决：功能等价，脚本更短（一次声明多资产上传）。留作**备选**——若首次实跑发现 `gh release create` 在 `--target` + `--generate-notes` 组合上有意外行为，直接换 D 即可，接口形状一致（都需要 `permissions: contents: write` + 一个 tag 名 + 资产路径）。

### 决策

**采用选项 C**：在现有 `release` job 上追加**发布段**，触发沿用 `workflow_dispatch`，新增两个 input，发布步骤默认关闭且带幂等保护。

```yaml
# 追加到 on.workflow_dispatch.inputs（锚点：现有 `build_release:` input 之后；取证时 ci.yml:56，inputs 区未受 G3h 改动影响，行号仍有效）
      publish_release:
        description: '⚠️ 真实发版：创建 GitHub Release 并上传安装包（会创建远端 tag，不可撤销）。默认关闭'
        type: boolean
        default: false
      release_tag:
        description: '要创建的 Release tag，形如 v0.1.1。留空则只构建不发布。⚠️ 禁止填已存在的 v0.1.0（指向 2026-06-28 旧提交，见 docs/research/release-pipeline-2026-09-19.md §1.2）'
        type: string
        required: false
        default: ''
```

```yaml
# release job 改动（锚点：`name: 发布构建（NSIS 安装包，仅手动触发）`；取证时 ci.yml:786-794，现 +13 → 799-807）
  release:
    permissions:            # ← 必须显式加，否则 gh release create 会以权限错误失败
      contents: write
    # 触发：构建 OR 发布（发布必然包含构建）
    if: >-
      github.event_name == 'workflow_dispatch' &&
      (inputs.build_release || inputs.publish_release)
```

```yaml
# 追加为 release job 的最后一步（锚点：现有 `上传安装包 + 校验和` 步骤之后；取证时 ci.yml:913 = 文件末，现 926）
      - name: 发布 GitHub Release（仅显式勾选时）
        if: inputs.publish_release && inputs.release_tag != ''
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          RELEASE_TAG: ${{ inputs.release_tag }}
        run: |
          $tag = $env:RELEASE_TAG
          if ($tag -notmatch '^v\d+\.\d+\.\d+') { throw "release_tag 形如 v0.1.1，实际: $tag" }

          # 幂等闸门：绝不允许覆盖已有 Release（尤其那个指向旧提交的 v0.1.0）
          gh release view $tag --repo ${{ github.repository }} 2>$null
          if ($LASTEXITCODE -eq 0) { throw "Release $tag 已存在 —— 拒绝覆盖。请换一个新 tag。" }

          # --target 保证 Release 标定的源码 == 本次实际构建的 commit
          gh release create $tag `
            --repo ${{ github.repository }} `
            --target ${{ github.sha }} `
            --title "$tag" `
            --generate-notes `
            --verify-tag `
            (Join-Path $env:RUNNER_TEMP 'release-artifacts' '*')

          # 版本号口径告警（TD-078：tauri.conf.json 仍是 0.1.0，UI 自述 v3.0）
          $confVersion = (Get-Content 'asd-tauri/src-tauri/tauri.conf.json' -Raw -Encoding utf8 | ConvertFrom-Json).version
          if ("v$confVersion" -ne $tag) {
            Add-Content $env:GITHUB_STEP_SUMMARY -Value "⚠️ tag `$tag` 与 tauri.conf.json 版本 `$confVersion` 不一致（TD-078），发布可用但溯源需以 commit ${{ github.sha }} 为准。"
          }
```

**配套的两处小改（不改会互相覆盖 / 不可溯源）：**

1. **artifact 名带 commit sha**（ci.yml:908）。当前是 `ASD-SkillManager-v${{ steps.meta.outputs.version }}-windows-x64`，而 `version` 长期停在 `0.1.0`（TD-078）→ 多次构建同名，事后无法区分是哪次构建。改为：
   `ASD-SkillManager-${{ inputs.release_tag || steps.meta.outputs.version }}-${{ github.sha }}` 之类的形态（具体字符串由执行者定，原则：**tag 与 sha 至少一个进名字**）。
2. **job summary 里写明 commit sha**（ci.yml:885-899 那段表格里加一行 `- commit: ${{ github.sha }}`），因为版本号不可信。

### 影响

**变容易的：**
- 有了稳定、不会过期（Release 资产默认永久）的下载落点 → 事故响应里的「回滚 = 让用户下载上一版」第一次有了物理落点。
- 不再需要本机 push，发布动作可在 GitHub 网页上完成。

**变困难的：**
- 版本号语义必须先定（TD-078），否则 Release 名字与产物名字会持续错位。**建议：首次发布前先由主理人拍板权威版本源**；若来不及，至少按上面的方案把 sha 作为权威溯源字段写进 Release 与 artifact 名。

**需要重新审视的：**
- ci.yml:759 那句「再按需在 `on.push.tags` 下加 `tags: ['v*']`」应改写为：「加 `tags: ['v*']` 对已存在的 v0.1.0 无效；只有当版本号策略确定（TD-078 关闭）且具备 push 能力时才有意义」。
- 那个空壳 Release `v0.1.0`：建议**保留不动**（它是 2026-06-28 的历史记录，删了会让历史断层），但在新 Release 的说明里注明「v0.1.0 无资产且指向旧提交，实际可用版本从 <新 tag> 起」。是否删除属产品/主理人决策，**本方案不擅自删**。

---

## 3. ADR-004：产物冒烟测试（B13）

**状态:** Proposed
**日期:** 2026-09-19

### 背景

出包后「能不能装、能不能启动、能不能加载配置、能不能跟 AHK 子进程建上 IPC」**全部无人验证**（B13）。`lib.rs` 覆盖率仅 22.84%，启动路径无自动化覆盖。

### 关键设计判断：把判据放在「磁盘证据」上，而不是放在 GUI 上

应用已经把关键事件写进**按天轮转的本地日志文件**（`asd-tauri/src-tauri/src/infrastructure/logging.rs`，默认 `info` 级，可用 `RUST_LOG` 覆盖，落点为 `app_data_dir`）。因此**不需要任何 GUI 自动化**，就能拿到下面这些**二值可判**的证据：

| 断言 | 证据来源（实证位置） | 覆盖了什么 |
|---|---|---|
| A1 安装包产出 | `bundle/nsis/*.exe` 存在且非空 | 构建真出包（meta 步骤已有，保留） |
| A2 静默安装成功 | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*` 出现 DisplayName 含 `ASD` 的键 | 安装器可运行、写注册表 |
| A3 主程序启动且未秒退 | `Start-Process -PassThru` 后 20s 内 `$p.HasExited -eq $false` | **能启动** |
| A4 配置/日志路径可用 | `%APPDATA%` 下出现 `com.asd.tauri`（含 `asd.<YYYY-MM-DD>.log`） | **能加载配置**（`app_data_dir` + logging 初始化成功，否则启动即错） |
| A5 拉起 AHK 子进程 | 日志含 `使用便携模式 AHK 子进程` 或 `使用编译模式 AHK 子进程`（`lib.rs:640` / `lib.rs:653`）；且进程表出现 `AutoHotkey64` 或 `asd_executor` | **打包布局下 `bundle.resources` 解析正确**（这是 dev 环境永远测不出来的一类故障） |
| A6 **IPC 握手并认证成功** | 日志含 `IPC 已接受 AHK 连接（已认证）`（`ipc.rs:284`） | **与 AHK 子进程建上 IPC**（B13 明确要求的那条）。这一行同时证明：管道建起来了、token 认证过了、子进程活着 |
| A7 无负面对证 | 日志**不含** `IPC AHK 认证失败`（`ipc.rs:256/263`）、`IPC AHK 认证超时`（`ipc.rs:279`）、`无法解析 AutoHotkey64.exe 路径`（`lib.rs:657`） | 排除「看起来起来了其实是坏的」 |
| A8 可卸载 | 卸载器 `/S` 后安装目录与注册表键消失 | 回滚路径可执行 |

> A6 是一条**高杠杆断言**：`IPC 已接受 AHK 连接（已认证）` 这一行的出现，需要「子进程被 spawn 成功 + 命名管道名一致 + 子进程主动连上 + 首条 auth 消息 token 匹配」四件事同时成立。它比「进程存在」强得多，且完全不需要 GUI。

### 选项分析

#### 选项 S-A：冒烟放在 `release` job 内（构建完立刻在同一 runner 上跑）

| 维度 | 评估 |
|---|---|
| 复杂度 | Low |
| 额外耗时 | ~2–3 分钟 |
| 覆盖 | 不覆盖 artifact 上传/下载链路 |

**选它（首轮）。** 理由：首次执行的目的是**验证「这条构建路径能不能出包、出来的包能不能跑」**，同 job 内最少变量、最快拿到结论；artifact 往返链路是次要风险，可以第二轮再补。

#### 选项 S-B：独立 `smoke` job，`needs: release`，下载 artifact 后再跑

| 维度 | 评估 |
|---|---|
| 复杂度 | Med（多一次上传/下载 + 需要处理 artifact 名不确定） |
| 覆盖 | 更真实（连 artifact 链路一起验） |

**未选（首轮）**，列为**第二轮增强**。理由：首轮若 S-B 红了，无法区分「包有问题」还是「artifact 链路有问题」，排查成本翻倍。

#### 选项 S-C：用现有 E2E（tauri-driver + msedgedriver）跑冒烟

**否决（已证伪）**：ci.yml:694-697 明载「方案 1 已证伪（run 35354358075）」—— 真实 UDF 有 EBWebView 但无 `DevToolsActivePort`，两条机制独立的通道全部失败，TD-061。**当前 E2E 通道是红的，不能作为发布闸门。**

### 决策（S-A 的具体步骤）

```yaml
      # 插在「上传安装包 + 校验和」之前（锚点：该步骤的 uses: actions/upload-artifact@v4；取证时 ci.yml:905，现 918）
      - name: 冒烟 · 静默安装
        shell: pwsh
        run: |
          $bundleDir = Join-Path 'asd-tauri' 'src-tauri' 'target' 'release' 'bundle' 'nsis'
          $installer = (Get-ChildItem $bundleDir -Filter *.exe | Select-Object -First 1).FullName
          # ⚠️ /S 能否在 displayLanguageSelector=true 下真正静默 —— 未实测，首次执行必须人工看
          $p = Start-Process $installer -ArgumentList '/S' -PassThru -Wait
          Write-Host "安装器退出码: $($p.ExitCode)"

          $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
          $hit = Get-ChildItem $uninstallKey -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath).DisplayName -like '*ASD*'
          }
          if (-not $hit) { throw 'A2 失败：静默安装后未找到 ASD 卸载项' }

      - name: 冒烟 · 启动 + IPC 握手
        shell: pwsh
        run: |
          $app = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like '*ASD*' } | Select-Object -First 1
          if (-not $app) { throw '未找到安装目录' }
          $exe = Get-ChildItem $app.FullName -Filter *.exe | Select-Object -First 1

          $env:RUST_LOG = 'info'
          $proc = Start-Process $exe.FullName -PassThru
          Start-Sleep -Seconds 20
          if ($proc.HasExited) { throw "A3 失败：主程序启动后立即退出，exit=$($proc.ExitCode)" }

          # A4 日志目录（不硬编码 identifier，按实际出现的目录定位）
          $logDir = Get-ChildItem $env:APPDATA -Directory -Filter 'com.asd.tauri' -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $logDir) { throw 'A4 失败：未创建 app_data_dir（com.asd.tauri）' }
          $log = Get-ChildItem $logDir.FullName -Filter 'asd.*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
          if (-not $log) { throw 'A4 失败：未生成日志文件' }
          $text = Get-Content $log.FullName -Raw -Encoding utf8

          # A5 子进程模式 + A6 IPC 握手 + A7 负面对证
          if ($text -notmatch '使用(便携|编译)模式 AHK 子进程') { throw 'A5 失败：未解析到 AHK 子进程路径' }
          if ($text -notmatch 'IPC 已接受 AHK 连接（已认证）') { throw 'A6 失败：IPC 未建立或未通过认证' }
          foreach ($bad in @('IPC AHK 认证失败','IPC AHK 认证超时','无法解析 AutoHotkey64.exe 路径')) {
            if ($text -match [regex]::Escape($bad)) { throw "A7 失败：日志出现负面对证 —— $bad" }
          }
          $ahk = Get-Process -Name 'AutoHotkey64','asd_executor' -ErrorAction SilentlyContinue
          if (-not $ahk) { throw 'A5 失败：进程表中无 AHK 子进程' }

          Write-Host '✅ 冒烟通过：安装 / 启动 / 配置落盘 / 拉起 AHK / IPC 已认证'

      - name: 冒烟 · 卸载 + 上传日志
        if: always()
        shell: pwsh
        run: |
          Get-Process -Name 'AutoHotkey64','asd_executor' -ErrorAction SilentlyContinue | Stop-Process -Force
          Get-Process | Where-Object { $_.MainWindowTitle -like '*ASD*' } | Stop-Process -Force
          # A8：卸载（失败不阻断，但明确打印）
          $u = Get-ChildItem "$env:LOCALAPPDATA\Programs" -Directory -Filter '*ASD*' -ErrorAction SilentlyContinue
          if ($u) {
            $un = Get-ChildItem $u.FullName -Filter '*uninst*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($un) { Start-Process $un.FullName -ArgumentList '/S' -Wait }
          }
          # 日志留档，无论成败
          $out = Join-Path $env:RUNNER_TEMP 'smoke-logs'; New-Item -ItemType Directory -Path $out -Force | Out-Null
          Get-ChildItem "$env:APPDATA\com.asd.tauri" -Filter '*.log' -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item $_.FullName $out -Force }
      - name: 上传冒烟日志
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: smoke-logs-${{ github.sha }}
          path: ${{ runner.temp }}/smoke-logs/*
          retention-days: 30
          if-no-files-found: warn
```

### 必须人工看着做的部分（不许写成「已自动化」）

| 步骤 | 为什么不能自动 | 谁做 |
|---|---|---|
| **首次 `workflow_dispatch` 跑 `release` job** | ci.yml:784-785 自己写明「本 job 的构建路径首次执行不保证一次绿，必须人工观察首次结果」 | 主理人 |
| **`/S` 能否真正静默安装**（`displayLanguageSelector: true` 是否会弹语言选择框并卡住） | 未实测；卡住的表现是 job 超时，信号很脏 | 首次执行时人工盯 |
| **安装包内含 LICENSE / 第三方许可**（TD-080 遗留） | `bundle.licenseFile` 的 `../../LICENSE` 能否被打包器解析**未经实跑验证**，需在安装目录里肉眼确认 | 首次执行时人工确认 |
| **真实按键触发连招** | 需交互桌面会话 + 键盘注入；E2E 通道当前红（TD-061） | 人工（脚本见 §6） |
| **SmartScreen「未知发布者」告警的实际表现** | 未签名，需在真实机器上观察 | 人工 |
| **离线/内网安装是否失败**（`downloadBootstrapper` + `silent: true`，失败无提示） | 需构造离线环境 | 人工（TD-086） |

---

## 4. 已验证 / 未验证 分界表（强制遵守）

| 命题 | 状态 |
|---|---|
| `release` job 存在、触发条件如 §1.1 | **已验证**（实读） |
| `ci.yml` 无任何 Release 步骤 | **已验证**（实读 913 行） |
| 远端存在一个 0 资产的 Release `v0.1.0`，指向 `0fbfce5`（2026-06-28） | **已验证**（API 实调） |
| 本机 github.com 不可达 / api.github.com 可达 / gh 未登录 | **已验证**（curl + gh 实跑） |
| 断言字符串 `IPC 已接受 AHK 连接（已认证）` 等在代码中存在 | **已验证**（实读 ipc.rs:284、lib.rs:640/653） |
| 冒烟 job 能在 CI 上跑绿 | **未验证 —— 从未执行过**。断言是真实存在的，脚本是新的，整体未跑 |
| `/S` 静默安装在 `displayLanguageSelector: true` 下生效 | **未验证** |
| `gh release create --target` 会在远端建 tag | **工具已知语义，本机未实跑**（未登录 + 禁止真实发版） |
| LICENSE 进入包内 | **未验证**（TD-080 明载遗留） |
| 打包布局下 `bundle.resources` 解析正确 | **未验证 —— 这正是冒烟要验的**（A5/A6） |

---

## 5. TD-083 可行性论证：重启后热键是否真能恢复

> 债项原文（TD-083）：「AHK 子进程重启后，已注册的热键不会自动重新注册」；状态标注为「**状态为推断**……『重启后热键确实失效』未经端到端实测」。此前结论：「靠推理，需要 GUI，自动化不了」。

### 5.1 结论

**「需要 GUI」这个判断只对了一半。** 它把两件事混为一谈：

- （a）**要有一个跑着的应用** —— 这条是真的，无法回避；
- （b）**要人用鼠标键盘去点、去按** —— 这条**不成立**。

而且 TD-083 的可验证性可以拆成两层，其中**结构层完全不需要 GUI，且证据已经齐了**。

### 5.2 L1 结构层：不需要 GUI，证据已闭合（实读，非推断）

| 环节 | 证据 | 位置 |
|---|---|---|
| 新 AHK 进程的热键注册表**从空开始** | `static _registered := Map()` 是类静态初始化器，新进程必然重新执行 → 空 | `hotkey_hook.ahk:17` |
| 新 AHK 进程启动**不注册任何热键** | `Executor_Init()` 只做三件事：`HotkeyHook.Init()` / `Sender.Init()` / `Joystick.Init()` + 设回调 + `IpcClient.Start()`；**没有任何 register** | `executor.ahk:430-451` |
| 分发器**没有 resync 类命令** | `switch action` 的全部分支：`toggle_group / register_hotkey / unregister_hotkey / emergency_release / hold_mode_toggle / start_recording / stop_recording / pause_recording / resume_recording / start_validation / stop_validation`，`default` 直接回「未知命令」 | `executor.ahk:60-86` |
| Rust 侧重启**只 kill + spawn** | `restart_child` 全文：`begin_restart()` → `spawn_child(&path, &token)` → 返回。无重放 | `watchdog.rs:1279-1299` |
| Rust 侧**没有「重连即重注册」的钩子** | 全仓 grep `重新注册 / resync / re-sync / on_reconnect / OnConnected` 在 `src-tauri/src` 与 `crates/` 下**零命中**（AHK 侧 `OnConnected` 只打一行日志） | 实查；`executor.ahk:441` |
| Rust 侧 `active_hotkeys` 的写入点**只在激活/切换时** | 写入点：`state.rs:235`（激活）/`state.rs:289`（切换），均不发生在重启路径 | 实读 |

⇒ **L1 已经是「已验证」而非「推断」**：重启后的新 AHK 进程必然是空注册表，且没有任何路径会去补。**唯一还没做的是把它变成一个可执行的、别人能复现的观测。**

### 5.3 L2 行为层：如何把它变成可执行观测

**关键洞察：`Sender` 的周期定时器也住在 AHK 进程里。** 一个处于 active 状态的周期性分组，其按键输出是**持续**的（`Sender.StartPeriodic`，`executor.ahk:296-298`）。进程被杀 → 定时器随进程消失 → **字符流停止**。

⇒ 判据不需要「按 F1 看有没有反应」，只需要「**看字符流停没停**」。这一步：

- 不需要按键注入；
- 不需要 GUI 自动化驱动；
- 一个不熟悉项目的人 15 分钟能跑完；
- 而且它同时暴露了 TD-083 更严重的那一半：**不只是热键没了，正在跑的连招也没了**。

### 5.4 三条可执行路径（按推荐顺序）

#### 路径 1（推荐，零 GUI、约 1.5 人天，全自动，纯 `cargo test`）

先补「可观测性」，再写断言。分三步：

- **1a** AHK 侧：`HotkeyHook.GetCount()` **已经存在**（`hotkey_hook.ahk:100-102`），只是**没有 IPC 出口**。在 `CommandDispatcher.Dispatch` 增一个 `query_hotkeys` 分支，回 `{"status":"ok","count":N,"keys":[...]}`。
- **1b** Rust 侧：在 watchdog 回到 `Running` 且 IPC 重新认证后，发一次 `query_hotkeys`，与 `AppState.active_hotkeys` 的数量对账；不一致 → `tracing::error!` + emit 事件（可进 UI）。**这一条顺带补上了 TD-083 点名的「热键注册失败零日志」**。
- **1c** 测试：仓库**已有**两个现成的积木 ——
  - `RecordingMockIpcSender`（`crates/asd-application/src/state.rs:1260-1285`）：把发出的每条 `IpcCommand` 记进 `Vec`，`take_commands()` 取回；
  - 真实进程重启先例（`src-tauri/src/tests/watchdog_integration_tests.rs:187-240`）：`spawn_child("C:\\Windows\\System32\\cmd.exe", "test_auth_token")`（`:194`）+ `WatchdogRunner` + kill + 轮询 `restart_count > 0`，**已有可复现的重启驱动方式**。<br>⚠️ 行号于 2026-09-19 更新：Tessa 在同日改写了该文件头（前瞻约束段落），原 `172-226` → 现 `187-240`，**驱动逻辑本身未变**。

  断言写成：**重启完成后，向 AHK 发出的命令里必须包含一次 `query_hotkeys`，且对账产生的告警被记录**。

> ⚠️ **诚实标注（不许含糊）**：这条测试**今天就能绿**，但它守的是「**对账装置存在且会报警**」，**不是**「重启后功能正常」。它是**回归守护 + 可观测性**，**不能**替代一次真实端到端。TD-083 的「行为是否真的失效」仍须由路径 2 或 3 实跑一次。

#### 路径 2（一次性人工，约 15 分钟，不需要按任何键）

见 §6 的最小人工验证脚本。

#### 路径 3（真实 GUI 自动化）

**不建议现在做。** 现有 E2E 通道是红的（TD-061，两条独立通道均已证伪），为一次性验证去修一条已知红的通道，投入产出比很差。

### 5.5 修复方向（供排期，不在本任务内）

| 方案 | 内容 | 评价 |
|---|---|---|
| F1 | 重启后只重放 `RegisterHotkey` | **只修一半**：热键回来了，但正在跑的连招（`Sender` 定时器）仍然没了。会制造「按 F1 有反应但连招不跑」的新困惑 |
| F2 | 重启后重放**全部 active 分组的完整状态**（`RegisterHotkey` + `ToggleGroup` + 各模式启动命令）。需 Rust 侧保存「已下发指令日志」用于重放 | **修根因**，但属行为变更 + 需要重放日志设计，回归面大 |
| F3 | 不做重放，改为**状态对账 + 显式报警**（路径 1） | 成本最低，把**静默失效变成显式失效** |

**推荐顺序：先 F3，再评估 F2。** 理由与本项目一贯取向一致 —— 在「假守护」与「显式失效」之间，F3 是**真守护**（它报告的是真实测到的不一致，不是「猜你应该没问题」）；而 F1 是典型的半成品修复。

---

## 6. TD-083 最小人工验证脚本（给不熟悉项目的人）

**目标**：用 ≥15 分钟判一次「AHK 子进程重启后，功能是否真的恢复」。
**前提**：已安装并启动应用；**不要在验证期间关闭应用**。
**准备**：打开一个**记事本**（用来当「显示器」），点一下记事本让它获得焦点。

| 步 | 操作 | 预期 | 判据 |
|---|---|---|---|
| 1 | 应用 →「技能组」页 → 新建分组 A：模式 **周期**、热键 **F1**、按键填 **`1`**、间隔 **100ms** | 分组出现在列表 | — |
| 2 | 再建分组 B：模式 **周期**、热键 **F2**、按键填 **`2`**、间隔 **100ms** | — | — |
| 3 | 分别点两个分组的**启用** | 导航栏圆点是**绿色** | — |
| 4 | 点回**记事本**，按 **F1** | 记事本里持续出现 `111111…` | ✅ 基线成立：热键 + 连招都工作 |
| 5 | 按 **F2** | 记事本里出现 `222222…` | ✅ 基线成立 |
| 6 | 打开**任务管理器 → 详细信息**，找到 `asd_executor.exe`（若没有，找 `AutoHotkey64.exe`）→ 右键 **结束任务** | 记事本里的字符**立即停止** | 这一步确认你杀对了进程 |
| 7 | **等待 ≤30 秒**（watchdog 有 1s 心跳 + 指数退避），期间**不要碰任何东西**。然后去应用 →「诊断信息」页看**执行器状态** | 状态应回到 **Running**（不是 Failed）；**重启次数** ≥1 | 若显示 **Failed**：说明重启次数已耗尽 → 点「♻️ 重置看门狗」，从步骤 3 重来 |
| 8 | **回到记事本，什么都别按，只看 10 秒** | — | **判 FAIL（TD-083 成立）**：字符流**没有恢复**，而导航栏圆点**仍是绿色**、应用**没有任何提示**<br>**判 PASS（TD-083 不成立）**：字符流自动恢复 |
| 9 | （无论上一步结果）**按一次 F1** | — | **判 FAIL**：按 F1 无反应 —— 热键在 AHK 侧已不存在 |
| 10 | **对照实验**：回到应用，把分组 A **停用再启用** | 记事本重新出现 `111111…` | 若恢复 ⇒ 证明故障原因是「**没重放注册**」，而不是配置丢了或别的原因。**这一步是区分根因的关键，不要跳过** |
| 11 | **留证**：截三张图（诊断页执行器状态 / 记事本内容 / 任务管理器进程列表）；复制诊断页的**版本号**与**日志所在目录**，把该目录下**当天**的 `asd.<日期>.log` 一起保存 | — | — |

**判定汇总**

- **步骤 8 或 9 出现 FAIL ⇒ TD-083 成立**，把它从「推断」改为「已实测」，按债项原文上调优先级。
- **步骤 8 与 9 都 PASS ⇒ TD-083 被证伪**，需要回去查是否有我们没看到的重放路径（重点查 `group_service.rs:73/113/163/188` 这几个 `RegisterHotkey` 发送点是否被某条重启后的回调触发）。**证伪同样是有效结论，请如实记录。**

**为什么这个脚本不需要「按热键」也能判**：步骤 8 看的是**周期连招的字符流**（`Sender` 定时器在 AHK 进程内，随进程一起消失），比按热键更稳 —— 按热键有「焦点不对」「被别的窗口吃掉」等一堆干扰项。

---

## 7. 分步执行计划（谁来做、卡点在哪）

| # | 动作 | 做 | 卡点 | 估时 |
|---|---|---|---|---|
| 1 | 手动 `workflow_dispatch` 跑一次 `release`（只勾 `build_release`，**不勾 `publish_release`**） | 主理人（人工盯全程） | 构建路径从未跑过；`/S` 静默安装未验证（先跑 S-A 之外的部分即可） | 0.5 人日 + 一次 CI 往返 |
| 2 | 确认产物出包 + LICENSE/第三方许可进包（TD-080 遗留） | 主理人 | 需下载 artifact 肉眼确认 | 含在上一步 |
| 3 | 加 §3 的冒烟步骤，再跑一次 | 主理人执行 / 我出脚本 | A5/A6 断言依赖日志落盘，首次可能要调路径 | 0.5 人日 + 一次 CI 往返 |
| 4 | 加 §2 的发布段（inputs + `permissions` + `gh release create`） | 主理人执行 | **必须先定版本号策略**（TD-078）；`release_tag` 不得填 `v0.1.0` | 0.5 人日 |
| 5 | 首次真实发版（勾 `publish_release` + 新 tag） | 主理人 | 不可逆；发布会创建远端 tag | 0.2 人日 |
| 6 | §6 人工脚本跑一次 TD-083 | 任一熟悉 Windows 的人 | 需一台装了应用的机器 | 15 分钟 |
| 7 | 路径 1（可观测性 + 对账测试） | Cody / Tessa | 需 AHK + Rust 双侧改动 | 1.5 人日（排期另定） |

**总卡点**：**#1 没跑绿之前，后面全部是纸面方案。** 这条与 ci.yml:784-785 已有的判断一致，本方案不推翻它。

---

## 8. 附带发现（不在本任务范围，转交）

| # | 发现 | 证据 | 建议转交 |
|---|---|---|---|
| X1 | **CI 的 `G3h watchdog（--ignored，观测期）` 步骤跑 0 条用例却显示绿灯。** 全仓已无一条活的 `#[ignore]` 属性 —— grep `#\[ignore` 共 8 处命中，**全部在 `//!` 文档注释里**。**Rex 拿到了比我更硬的证据**：直接拉 CI job `105906876013` 的日志，实测输出为 `running 0 tests` / `test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; **256 filtered out**` —— 整组 256 条全被过滤、一条没跑，rc 仍是 0。另 `grep '^\s*#\[ignore\]'` 全仓零命中。<br>⚠️ **状态更新（2026-09-19，Tessa 已在修）**：工作树里的 `ci.yml` 已把该步骤改为 `cargo test -p asd-tauri --lib tests::watchdog_integration_tests -- --test-threads=1`（按模块名直接跑，不再用 `--ignored`），并补写了「恒绿空转」的成因与解禁判据。**该改动尚未提交**，本条保留为记录，供提交后复核 | 我实查 + **Rex 实测 CI 日志**（run `105906876013`） | **Tessa**（已在处理）/ **Rex**（已从有效信号中剔除该步骤的绿灯）。本条我这边不再推进 |
| X2 | **打包布局下只会走「便携模式」**：`bundle.resources`（`tauri.conf.json:37-48`）**不含 `asd_executor.exe`**（且 `.gitignore:35` 的 `*.exe` 会把它排除），故 `resolve_ahk_executor_path`（`lib.rs:634-661`）在包内必然回落到 `AutoHotkey64.exe` + `executor.ahk`。**而本地开发/测试环境因为有 `asd_executor.exe`，走的是「编译模式」**。<br>**Rex 补充的证据链（我已复核采纳）**：③ `build.rs` 全文 grep `asd_executor` **零命中** —— 排除了「构建时自动生成」的可能；④ 本地 `src-tauri/ahk_executor/asd_executor.exe` 确实存在。<br>⚠️ **Rex 提出的定性边界（重要，避免夸大）**：`watchdog.rs:314-319` 对 `AutoHotkey64.exe` **正确追加了 `executor.ahk` 参数**，且 `executor.ahk` 在 `bundle.resources:38` ⇒ **静态接线是正确的**。故本条定性是「**未验证**」，**不是「已知坏」** —— 别把「没跑过」读成「有问题」。Rex 在 Go/No-Go 里拆成了 B6（未实测）+ B7（静态接线正确）两条 | 我实读 + **Rex 补全并复核** | **Rex**（Go/No-Go，记为 N6）：这意味着**本地测过的执行器路径 ≠ 用户装到的执行器路径**；冒烟的 A5/A6 断言被 Rex 采用为唯一验证手段 |
| X3 | `tauri.conf.json` 的 `displayLanguageSelector: true` 与静默安装 `/S` 的组合未实测 | 实读 | 冒烟首次执行时人工盯（见 §3 表） |

---

## 附录：本报告的取证命令（可复现）

```bash
# CI 现状
grep -n "workflow_dispatch\|inputs\.\|gh release\|softprops\|on:" .github/workflows/ci.yml

# 远端 Release / tag（只读）
curl -s https://api.github.com/repos/zyejf/AutoHotkeydemo/releases
curl -s https://api.github.com/repos/zyejf/AutoHotkeydemo/tags
git tag -l && git rev-parse --short HEAD

# 本机环境
curl -s -o /dev/null -w "%{http_code}" https://github.com
curl -s -o /dev/null -w "%{http_code}" https://api.github.com
gh --version && gh auth status

# 断言字符串来源
grep -n "IPC 已接受 AHK 连接" asd-tauri/src-tauri/src/infrastructure/ipc.rs
grep -n "使用便携模式\|使用编译模式" asd-tauri/src-tauri/src/lib.rs

# TD-083 结构层证据
sed -n '1279,1299p' asd-tauri/src-tauri/src/infrastructure/watchdog.rs
sed -n '430,451p' asd-tauri/src-tauri/ahk_executor/executor.ahk
sed -n '15,20p;99,108p' asd-tauri/src-tauri/ahk_executor/hotkey_hook.ahk

# X1：确认无活的 #[ignore]
grep -rn "#\[ignore" --include=*.rs asd-tauri/ | grep -v "/target/"
```

---

## 9. 可直接粘贴的发布段补丁（2026-09-19，供主理人接入）

> 本节是 §2 ADR-003 的**落地文本**。锚点按 ci.yml **933 行版**（release job `:799`、`if:` `:813`、`上传安装包 + 校验和` `:924`、inputs 末尾 `:56`、顶层 `concurrency` `:58-60`）。
> ⚠️ **全部未实跑过一次**（约束：不得真实发版）。已实证 / 未验证的分界见 §9.4，**不许混**。

### 9.1 新增 inputs（插在 `build_release` 之后、`concurrency:` 之前）

```yaml
      publish_release:
        description: '⚠️ 真实发版：创建 GitHub Release 并上传安装包（GITHUB_TOKEN 经 API 建远端 tag，不可逆）。需同时勾选 build_release'
        type: boolean
        default: false
      release_tag:
        description: 'Release tag。留空自动生成 build-<YYYYMMDD>-<sha7>。禁止 v0.1.0（指向 2026-06-28 旧提交）'
        type: string
        required: false
        default: ''
```

### 9.2 release job 加写权限（插在 `release:` 下、`if:` 之前）

```yaml
    permissions:
      contents: write
```

缺它 `gh release create` 必红，且报错是误导性的权限串（本仓 TD-014 同型坑）。

### 9.3 发布 step —— **放在最后一个（upload-artifact 之后）**

理由：① artifact 是 90 天兜底，发布放前面一旦失败 job 中止 ⇒ **连 artifact 都没有**，严格更差；② 发布是唯一未跑过的步骤，先落袋已确定的东西；③ 冒烟（§3）插在 SHA256 与 upload-artifact 之间，不冲突。

```yaml
      - name: 发布 GitHub Release（需勾选 publish_release）
        if: inputs.publish_release
        shell: pwsh
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REQUESTED_TAG: ${{ inputs.release_tag }}
        run: |
          $ErrorActionPreference = 'Stop'
          $sha   = '${{ github.sha }}'
          $short = $sha.Substring(0, 7)

          # 1) tag：留空自动生成；只认两种形态，其它一律拒（防手滑填分支名/旧 tag）
          $tag = $env:REQUESTED_TAG.Trim()
          if ($tag -eq '') {
            $tag = "build-{0}-{1}" -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd'), $short
            Write-Host "自动生成 tag: $tag"
          }
          if ($tag -notmatch '^build-\d{8}-[0-9a-f]{7,40}$' -and $tag -notmatch '^v\d+\.\d+\.\d+$') {
            throw "release_tag 非法: '$tag'（允许 build-<YYYYMMDD>-<sha7> 或 v<X.Y.Z>）"
          }
          if ($tag -eq 'v0.1.0') { throw '禁止发布到 v0.1.0（指向 2026-06-28 旧提交）' }

          # 2) 幂等闸门：已存在即硬失败，绝不覆盖
          gh release view $tag --repo '${{ github.repository }}' 2>$null
          if ($LASTEXITCODE -eq 0) { throw "Release '$tag' 已存在 —— 拒绝覆盖" }

          # 3) 自撰说明（不用 --generate-notes：上一 Release 是 v0.1.0/2026-06-28，
          #    它会吐出数百条提交；且需写清未签名 / 需联网 / 版本号不可信三件事）
          $notes = Join-Path $env:RUNNER_TEMP 'release-notes.md'
          $sum = Get-Content (Join-Path $env:RUNNER_TEMP 'release-artifacts' 'SHA256SUMS.txt') -Raw -Encoding utf8
          @(
            "## ASD 技能管理器 — $tag", ''
            "- commit: ``$sha``（**溯源以此为准**；tauri.conf.json 版本长期停在 0.1.0，见 TD-078）"
            '- 平台: Windows x64 / NSIS（installMode=currentUser）'
            '- ⚠️ 未签名：SmartScreen「未知发布者」告警，需手动「更多信息 → 仍要运行」'
            '- ⚠️ 首次安装需联网下载 WebView2；离线/内网装不上'
            '- ℹ️ 历史 Release v0.1.0 无资产且指向 2026-06-28 旧提交，可用版本自本条起'
            '', '### SHA256', '```', $sum.TrimEnd(), '```'
          ) | Set-Content -Path $notes -Encoding utf8

          # 4) 建 Release。--target 保证标定源码 == 本次构建 commit
          #    ⚠️ 刻意不加 --verify-tag：它要求 tag 事先存在，而本步正是靠 --target 新建，加了自相矛盾
          $files = @(Get-ChildItem (Join-Path $env:RUNNER_TEMP 'release-artifacts') -File | ForEach-Object { $_.FullName })
          if ($files.Count -eq 0) { throw 'release-artifacts 为空，拒绝创建空 Release' }
          gh release create $tag --repo '${{ github.repository }}' --target $sha `
            --title "ASD 技能管理器 $tag" --notes-file $notes $files
          if ($LASTEXITCODE -ne 0) { throw "gh release create 失败（exit=$LASTEXITCODE）" }
          "已发布: https://github.com/${{ github.repository }}/releases/tag/$tag" |
            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
```

### 9.4 concurrency 守卫 —— job 层、静态 group、`cancel-in-progress: false`

```yaml
    concurrency:
      group: release-publish-${{ github.repository }}
      cancel-in-progress: false
```

| 选择 | 理由 |
|---|---|
| **job 层** | 顶层 `:58-60` 是 `ci-${{ github.ref }}`，保护全 CI 不堆积，**不能改** —— 改成静态会把所有分支的 CI 串行化，是回归 |
| **静态 group** | 顶层按 ref 分组，tag 事件的 ref 与 main 不同 ⇒ 顶层**拦不住** tag 触发的第二次 run；静态组让两次 run 不论 ref 都进同一组 |
| **`false`** | 发布上传中途被 cancel 会留下「Release 建了但资产不全」的半成品，排队比取消安全 |

⚠️ **今天它只是纵深防御**：`on.push` 只有 `branches: [main, master]`、**没有 `tags:` 过滤器**，故 tag 创建事件**结构上匹配不到任何触发器**。风险只在将来有人加 `tags:` 时才成立。

### 9.5 实证边界（强制）

**已实证（实读 / 实调）**：release job 结构与 `:799 / :813 / :924` 锚点；inputs 末尾 `:56`；顶层 concurrency `:58-60`；`on.push` 无 `tags:` 过滤器；远端 Release `v0.1.0` 存在、0 资产、tag→`0fbfce5`；本机 github.com 000 / api 200 / gh 未登录。

**未验证（推测，不得当结论）**：

1. `gh release create --target` 建 tag 的实际行为 —— **未实跑**；
2. `--verify-tag` 与新建 tag 冲突 —— **按 CLI 语义推断**，故建议去掉，**未实证**；
3. API 建 tag 是否触发 `on.push.tags` —— **维持「未查证」**；Rex 的 N9 覆盖了 GITHUB_TOKEN 情形（不会二次触发），**采纳他的结论但非我实测**，PAT/OAuth 情形仍需注意；
4. `permissions: contents: write` 是否够 —— 本仓未实测过写权限路径；
5. **整个 step 一次都没跑过。**

另：发布需**同时勾 `build_release` + `publish_release`**（job 级 `if` 已要求前者）。若想让 `publish_release` 单独生效，须把 job 的 `if` 改为 `inputs.build_release || inputs.publish_release` —— 那改的是主理人设定的语义，本方案不擅自改。
