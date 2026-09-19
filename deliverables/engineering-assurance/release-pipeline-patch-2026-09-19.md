# 发布链路补丁 · 可直接粘贴（2026-09-19）

**作者：** 系统架构师（阿奇） ｜ **面向：** 执行
**完整论证：** `docs/research/release-pipeline-2026-09-19.md`（§2 ADR-003、§9）
**锚点版本：** `.github/workflows/ci.yml` **933 行版** —— `release` job `:799`、`if:` `:813`、`上传安装包 + 校验和` `:924`、inputs 末尾 `:56`、顶层 `concurrency` `:58-60`
**约束：** 本文件只出方案。**不得真实发版、不得建 tag、不得建 Release。**

---

## 0. 一句话结论

`workflow_dispatch` + 作业内 `gh release create --target ${{ github.sha }}`：tag 由 runner 用 `GITHUB_TOKEN` 经 **API** 创建，**全程不需要本机 push**（本机 `github.com` 直连 000 不影响）。

---

## 1. 补丁（三块，按粘贴顺序）

### (a) 新增两个 `workflow_dispatch` input

**插在 `:56` 的 `build_release` 之后、`concurrency:`（`:58`）之前。**

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

### (b) `release` job 新增 `permissions` + job 级 `concurrency`

**插在 `release:` 下、`if:`（`:813`）之前。**

```yaml
    permissions:
      contents: write
    concurrency:
      group: release-publish-${{ github.repository }}
      cancel-in-progress: false
```

- **`permissions: contents: write` 是必需的，不是可选**：缺它 `gh release create` 必红，且报错是误导性的权限串（本仓 TD-014 在 `security-audit` job 上踩过同型坑：审计其实跑完了，最后一步写回 Checks API 才报权限错，看起来像「action 配置坏了」）。
- **job 级 `concurrency` 的取值理由**见 §3，**它现在承担的职责已随主理人的顶层改动而变化** —— 见 §3.3，别照抄旧理由。

### (c) `gh release create` 步骤

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

---

## 2. 该 step 插在第几位

**插在最后一个 —— 即 `上传安装包 + 校验和`（`:924`）之后。**

| 理由 | 说明 |
|---|---|
| ① artifact 是唯一兜底 | artifact 有 90 天保留期。若发布放在 upload 之前，发布一失败 job 就中止 ⇒ **连 artifact 都没有**。放在之后则「发布失败但产物已存档」，严格优于前者 |
| ② 发布是唯一未跑过的步骤 | 其余步骤（含硬失败的产物收集）已落地或至少可静态判定；未验证的步骤应最后跑，把已确定的先落袋 |
| ③ 与冒烟不冲突 | 产物冒烟（B13，见主报告 §3）应插在「收集产物并生成 SHA256」与「上传安装包 + 校验和」之间；发布在其后，顺序为 **构建 → SHA256 → 冒烟 → 上传 artifact → 发 Release** |

---

## 3. `concurrency` 的两层设计

### 3.1 顶层（现有 `:58-60`，主理人拟改为 `ci-${{ github.ref }}-${{ github.event_name }}`）

### 3.2 job 层（本补丁 (b) 新增）

### 3.3 ⚠️ 主理人的顶层改动改变了 job 层守卫的**理由**（重要，别照抄旧说法）

我原先给 job 层守卫的理由是「防 tag 二次触发 + 顶层按 ref 分组拦不住 tag 事件」。**主理人实测后，这两条都已被更准确地重写：**

| 我原先的判断 | 现状 |
|---|---|
| 「tag 二次触发是主要风险」 | **降级。** 本 workflow 的 `on.push` 只有 `branches:[main,master]`、无 `tags` 过滤器；GitHub 文档明确「只定义 `branches` 而不定义 `tags` 时，workflow 不会为未定义的 Git ref 运行」⇒ tag 推送**不会**触发。且主理人查 `?head_sha=<tag sha>` 得 `total_count=0` **无判别力**（tag 早于 workflow 存在），故**不能当证据**。⇒ 有权威文档依据，**但仍非实测** |
| 「顶层拦不住 tag 触发的第二次 run」 | **不再是主要矛盾。** 真正的风险是主理人实测发现的：**顶层 `cancel-in-progress: true` 在取消 main 上正在跑的 run**（近 50 次运行里 `4 push → cancelled`、`1 workflow_dispatch → cancelled`）。即发布构建跑到一半，任何人 push 一下 main 就把它杀掉 —— **这是已发生的真实风险，优先级高于我原先担心的那条** |

⇒ **job 层守卫保留，但理由更新为：**

1. **跨 ref 序列化两次发布**：顶层按 `${{ github.ref }}-${{ github.event_name }}` 分组后，main 上的 dispatch 与其它 ref 上的 dispatch 仍属不同组；job 层的静态组 `release-publish-<repo>` 让**任何两次发布执行不论 ref 都进同一组**。
2. **保护上传不被取消**：`cancel-in-progress: false` —— 发布上传中途被 cancel 会留下「Release 建了但资产不全」的半成品，排队比取消安全。
3. ⚠️ **未验证**：workflow 级 `cancel-in-progress: true` 与 job 级 `cancel-in-progress: false` 同时存在时，**到底谁生效、workflow 级取消是否会连带取消已声明 job 级 concurrency 的 job** —— GitHub 文档未明确，**我没有实测**。若 workflow 级取消仍会杀掉该 job，则主理人的顶层改动就是**必需项**而非锦上添花；若 job 级能兜住，则两者互为冗余。**首次实跑时看一眼**：push 一下 main，观察发布 run 是否被取消。

---

## 4. 主理人顶层 group 改法的评审结论：**不冲突，赞成**

> 提案：顶层 `group: ci-${{ github.ref }}` → `ci-${{ github.ref }}-${{ github.event_name }}`

**我原先的担心是「别把顶层改成静态名」** —— 静态名会把**所有分支**的 CI 串行化（不同分支的 PR 互相阻塞），那是回归。

**主理人的改法仍按 `${{ github.ref }}` 分组、只是再叠加 `event_name` 维度，不是静态名 ⇒ 我的担心不适用，两者不冲突。**

我额外看了三个维度，未见回归：

| 维度 | 评估 |
|---|---|
| push 的防堆积能力 | **不变**：同一 ref 上的连续 push 仍同组，仍互相取消 |
| PR | `github.ref` = `refs/pull/<n>/merge`，叠加 `pull_request`，无变化 |
| schedule（每周 fuzz） | ref = 默认分支，组为 `ci-refs/heads/main-schedule`，与 push 组分离 —— 反而更符合「fuzz 是独立长任务」的预期 |

**唯一新增的代价**（可接受）：push 组与 dispatch 组分离后，最坏并发从 1 变成 **2**（1 个 push run + 1 个 dispatch run）；push 组内部仍自我取消，不会堆积。

**结论：赞成改，不必改回。** 且它对发布链路是**正向**的 —— 解决了「发布构建被 push 杀掉」这个已实测的真实风险，比我原方案里那条 tag 防御更有价值。

---

## 5. 已实证 / 未验证（强制分界，不许混）

### ✅ 已实证（实读 / 实调 API / 实跑 grep）

| 断言 | 取证 |
|---|---|
| `release` job 结构与 `:799 / :813 / :924` 锚点；inputs 末尾 `:56`；顶层 `concurrency` `:58-60` | 实读 ci.yml |
| 本 workflow `on.push` **只有 `branches:[main,master]`、无 `tags:` 过滤器** | 实读 + 主理人独立复核 |
| 远端 Release `v0.1.0` 存在、0 资产、tag → `0fbfce5`（2026-06-28），较 HEAD 落后 363 提交 | GitHub API 实调 |
| `tauri.conf.json:4` `version = 0.1.0`、`productName = ASD - 技能管理器`；TD-078 记有「产物名会长期停在 0.1.0」 | 实读（主理人复核，属实 ⇒ notes 里那句引用成立） |
| 顶层 `cancel-in-progress: true` 实际取消 main 上正在跑的 run（近 50 次里 4 push / 1 dispatch 被取消） | 主理人实测 |
| 断言字符串 `IPC 已接受 AHK 连接（已认证）`（`ipc.rs:284`）、`使用便携/编译模式 AHK 子进程`（`lib.rs:640/653`） | 实读 |
| 本机 `github.com` 000 / `api.github.com` 200 / `gh` v2.89.0 未登录 | 实跑 |

### ❌ 未验证（推测 / 未实跑，**不得当结论**）

| 断言 | 状态 |
|---|---|
| **API 创建的 tag 是否会触发 `on.push`** | **维持「未查证」，不改口。** 现有的是**权威文档依据**（只定义 `branches` 时不触发未定义 ref）+ 结构上无 `tags:` 过滤器 ⇒ 判定为不会；但**无实测**（`?head_sha` 查询无判别力）。Rex 的 N9 仅覆盖 GITHUB_TOKEN 情形且**非我实测**。⇒ 标为「**有权威文档依据的推断**」，**不升为已实证** |
| `gh release create --target` 建 tag 的实际行为 | **未实跑** |
| `--verify-tag` 与新建 tag 冲突 | **按 CLI 语义推断**（该开关要求 tag 事先存在），故建议去掉；**未实证** |
| `permissions: contents: write` 是否足够 | 标准做法，但**本仓未实测过写权限路径** |
| workflow 级与 job 级 `concurrency` 同时存在时的优先级 | **文档未明确、未实测**（见 §3.3 第 3 条） |
| **本补丁整个发布 step** | **一次都没跑过** —— 首次必须人工盯全程 |

---

## 6. 执行前的两个前置

1. **发布需同时勾 `build_release` + `publish_release`** —— job 级 `if`（`:813`）已要求前者。若想让 `publish_release` 单独生效，须把 job 的 `if` 改为 `inputs.build_release || inputs.publish_release`，但那改的是主理人设定的三重护栏语义，**本方案不擅自改**。
2. **首次执行只能勾 `build_release`、不勾 `publish_release`** —— 先把构建路径跑绿（ci.yml `:794-798` 自述「首次执行不保证一次绿」），确认产物出包后，再单独验证发布段。
