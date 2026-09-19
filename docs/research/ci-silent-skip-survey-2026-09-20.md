# CI「静默 skip 面」普查（`needs:` / `if:` / `continue-on-error`）

**日期**：2026-09-20　**范围**：只读普查 `.github/workflows/ci.yml`（1249 行）与相关 docs，**不改任何 job 触发逻辑**
**任务**：普查所有挂在 `needs:` 下的 job，画出「上游红 ⇒ 本 job skipped（不红不报警）」的静默 skip 面

---

## 0. 结论摘要

1. **全文件只有一处 `needs:`**：`ci.yml:908` `release: needs: gates`，且**没有** `if: always()`。
   上游 `gates` 红 / skipped / cancelled ⇒ `release` **skipped，不是 failed**。
2. **但「静默」的成因不是这一条，而是 `skipped` 这个状态本身不可自证。** `release` 的 `skipped` 至少由 **4 个互不相同的原因**产生，且**原因 1 在 `release` job 自身完全不可见**（该 job 从未启动，因此没有任何日志）。
3. **另有 4 个 job 靠 `if:` 门控**（`fuzz` / `bench` / `ahk-bench` / `e2e`），它们的 `skipped` 是「按设计不跑」，与 `release` 的「本该跑但被上游掐掉」**外观完全相同**（都是灰色 skipped）。这两类**必须靠人记住上下文才能分开**。
4. **发现一处自述与机制矛盾**：`ahk-bench` 自陈「本 job 是**门禁** —— 失败会阻断合并」（`ci.yml:600-602`），但其 `if:`（`:610-612`）**排除了 `pull_request`** ⇒ 它在 PR 上**从不运行**，因此**结构上不可能阻断合并**，只能在合并之后于 main 上事后报警。
5. **本仓已有先例，且代价昂贵**：TD-016 记载「全量核对 **96 次 CI 运行，E2E job 一次都没真正跑过**（4 次 `workflow_dispatch` 的 `run_e2e` 均未勾选，job 全部 skipped）」。⇒ 「skipped」**不会自我报告**，只能靠专门的清点发现。
6. ⚠️ **危险性的前置条件无法从仓库内部验证**：`skipped` 真正致命的情形是「该 job 被分支保护列为**必需检查**」。本仓 `docs/` 与 `.github/` 内**没有任何**关于必需检查 / 分支保护的记载（`grep -rn -i 'required status|required check|branch protection|分支保护'` 零命中）。**该前提是否成立必须在 GitHub 设置里看，本普查无法回答。**

---

## 1. 方法

只读手段：`grep` 出全部 job 头、`needs:`、`if:`、`continue-on-error`，再逐 job 读上下文确认作用域（job 级 vs step 级）。
**未做**：不实跑 CI、不改任何触发逻辑、不推断 GitHub 侧设置。

---

## 2. A 面 —— `needs:` 级联（核心案例，1 处）

```yaml
release:                                    # ci.yml:902
  needs: gates                              # ci.yml:908
  if: github.event_name == 'workflow_dispatch' && inputs.build_release && github.ref == 'refs/heads/main'   # :930
```

GitHub Actions 语义：`needs` 指向的 job **失败或被跳过或被取消**时，下游 job 默认**被跳过**（除非下游写 `if: always()`）。本 job **没有** `if: always()`。

`ci.yml:905-907` 的注释**已经承认**这个行为并判为刻意：

> 「发布产物是拿去给用户装的，必须建立在四闸门绿之上。若 gates 红，本 job 本就不该产出任何东西 —— 这正是想要的行为。」

⇒ **行为本身是对的**（gates 红时不该出包）。**缺陷在可诊断性**，不在行为。

### `release: skipped` 的四个互不相同的原因

| # | 原因 | 在 `release` job 自身可见吗 |
|---|---|---|
| 1 | `gates` 红 / skipped / cancelled（`needs:` 级联） | **否 —— 该 job 从未启动，没有任何日志** |
| 2 | `inputs.build_release` 未勾选 | 否 |
| 3 | `github.ref != refs/heads/main`（如误选 tag） | 否 |
| 4 | `event_name != workflow_dispatch`（如 push/PR/schedule） | 否 |

**四个原因在 Actions UI 上都只显示一个灰色 `skipped`**。任务描述里那两次（一次因 G2a 红、一次因 G3d 红）正是原因 1 —— 而操作者看到的与「忘了勾复选框」**完全一样**。

**唯一可靠的区分办法**：在**同一次 run 内**横向看 `gates` job 自身的状态。⇒ 原因**可恢复，但必须跨 job 取证**，不在 `release` 这一格里。这条差异值得写进注释，否则每个新操作者都要重学一次。

### 与本仓既有文档的关系（重要）

`docs/research/release-pipeline-2026-09-19.md:53` 把这一条判为：

> 「`needs: gates`（ci.yml:792）—— 建立在四闸门绿之上，**正确**。」

**该判断不完整**：它只审了「gates 绿时才出包」这个**正向**语义，没有审「gates 红时下游变成 skipped 而非 failed」这个**信号**语义。本文是对该行的**限定**，不是否定。

---

## 3. B 面 —— `if:` 门控（4 处）

这些 job 的 `skipped` 是**按设计不跑**，但它们与 A 面**外观相同**，且每一个都是「绿了不代表跑过」的位点。

| job | `if:` | 位置 | 在这些触发下 skipped |
|---|---|---|---|
| `fuzz` | `github.event_name == 'schedule'` | `:532` | push / PR / dispatch |
| `bench` | `github.ref == 'refs/heads/main' && github.event_name == 'push'` | `:563` | PR / schedule / dispatch |
| `ahk-bench` | `(ref==main && push) \|\| (dispatch && inputs.update_ahk_bench_baseline)` | `:610-612` | **PR** / schedule |
| `e2e` | `github.event_name == 'workflow_dispatch' && inputs.run_e2e` | `:684` | push / PR / schedule |

### 3.1 `ahk-bench` 自述与机制矛盾（本普查最锋利的一条）

`ci.yml:600-602` 原文：

> 「与上面 Rust bench 分成两个 job：Rust bench 是「观测信号」（continue-on-error），
> **本 job 是门禁 —— 失败会阻断合并**，用于防止 T1/T6 的性能收益被后续改动吃掉。」

而其 `if:`（`:610-612`）只允许 **push 到 main** 或 **手动 dispatch + 勾选重设基线**。

⇒ **`pull_request` 上它从不运行**，而「阻断合并」只可能发生在 PR 阶段。**该 job 结构上无法实现它自述的目的**：它只能在代码**已经进入 main 之后**才报警，此时「阻断合并」这个动作已经没有对象。

这不是配置错误，是**自述与机制不一致** —— 与 `needs: gates` 那条同族：**都把一个「事后信号」写成了「事前门禁」**。

---

## 4. C 面 —— `continue-on-error: true`（job 级，3 处）

| job | 位置 | 后果 |
|---|---|---|
| `miri` | `:511` | **无 `if:`** ⇒ 每次触发都跑、烧 CI 分钟，但**永不使 workflow 失败** |
| `fuzz` | `:531` | 叠加 `if: schedule` ⇒ 每周一次，永不失败 |
| `bench` | `:562` | 叠加 `if: push&&main` ⇒ 永不失败 |

⇒ 这三个 job **无论内部发生什么，对 workflow 结论零影响**。`miri` 尤其值得注意：它**没有** `if:` 门控，所以它每次都**真的在跑**，但**红绿不影响任何结论** —— 属于「有信号、无后果」。

`ci.yml:186` 已经为本类风险写过一句话（针对 gates 内某一步）：

> 「叠加 `continue-on-error` 后它退化成「恒绿空转」—— 绿，但一条都没跑过。」

**这句话同样适用于 job 级的这三处，但文件里没有在它们旁边重复。**

---

## 5. 总表（全部 10 个 job）

| job | 行 | 性质 | `needs` | `if:` 门控 | job 级 `continue-on-error` | 静默面 |
|---|---|---|---|---|---|---|
| `gates` | 90 | **门禁** | — | 无 | 否 | 每次触发都跑，无 skip 面 |
| `js-lint` | 316 | 门禁 | — | 无 | 否 | 无 |
| `coverage` | 335 | 门禁（TD-006 起） | — | 无 | 否（仅某步有） | 无 |
| `security-audit` | 374 | 门禁（TD-014） | — | 无 | 否（dev 依赖那步有） | 无 |
| `miri` | 508 | 信号 | — | 无 | **是** | **恒绿空转**（跑了但不影响结论） |
| `fuzz` | 528 | 信号 | — | `schedule` | **是** | skip 面 + 恒不失败 |
| `bench` | 557 | 信号 | — | `push&&main` | **是** | skip 面 + 恒不失败 |
| `ahk-bench` | 599 | **自称门禁** | — | `push&&main` 或 dispatch+flag | 否 | **PR 上 skipped ⇒ 无法阻断合并** |
| `e2e` | 682 | 手动 | — | `dispatch && run_e2e` | 否 | skip 面（TD-016 已记账） |
| `release` | 902 | 交付物 | **`gates`** | `dispatch && build_release && main` | 否 | **核心案例：`skipped` 四因不可分** |

---

## 6. 建议（**未执行**，供裁定）

### 6.1 `ci.yml` 注释草案（给 `release` job，插在 `:907` 之后）

> ```yaml
>     # ⚠️ 上面这条「gates 红 ⇒ 本 job 不产出」是对的，但**信号有代价**：
>     #    `needs` 上游不绿时，本 job 是 **skipped（不红、不报警）**，而不是 failed。
>     #    而 `skipped` 至少由 4 个互不相同的原因产生，本 job 自身**一个都看不到**
>     #    （它从未启动，没有日志）：
>     #      ① gates 红/skipped/cancelled  ② 未勾 build_release
>     #      ③ ref 不是 main                ④ 事件不是 workflow_dispatch
>     #    ⇒ 看到 skipped 时，**先去同一次 run 里看 gates 自己的状态**再下结论；
>     #      不要默认「我忘了勾复选框」而重跑一次。
>     #    ⚠️ 另：本 job 至今**从未在 CI 上执行过**（见上方触发段说明）——
>     #      它 skipped 时，与「跑过且成功」在 UI 上都不是同一种颜色，别混淆。
> ```

### 6.2 其余两条（属改机制，**须单独派**）

- `ahk-bench`：自述「阻断合并」与其 `if:` 矛盾。二选一 —— 要么把 `if:` 放宽到 `pull_request`（真门禁，但要承担 PR 上跑基准的成本与抖动），要么**改掉自述**（承认它是「合并后回归信号」）。**本普查不预设选哪个。**
- `miri` / `fuzz` / `bench`：job 级 `continue-on-error` 使它们对结论零影响。是否把其中某个转成硬门禁是**独立的取舍**，不在本任务范围。

---

## 7. 本普查的边界（不许当结论用）

1. **未实跑任何 CI**：全部结论来自静态读 `ci.yml` + GitHub Actions 的**文档语义**。「上游不绿 ⇒ 下游 skipped」是文档语义，**本仓未实测复现**（虽然任务描述里那两次观测与该语义一致）。
2. **未验证分支保护设置**：`skipped` 是否被算作「必需检查通过」，取决于 GitHub 侧配置，**仓库内部看不到**。本文**不主张**该风险已成立，只标注**它是危险性的前提**。
3. **`ci.yml` 是仓库内唯一的 workflow 文件**（`.github/workflows/` 下只有它一个）⇒ 「只扫了 `ci.yml`」等价于「扫了全部 workflow」。若日后新增 workflow，本普查**不覆盖**。
4. 行号取自 2026-09-20 的 `ci.yml`（1249 行）；该文件正在被多人改动，**引用时请连 subject 一起引**，不要只引行号。
