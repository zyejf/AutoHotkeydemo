# 项目长期记忆 — ASD 技能管理器

> 长期有效事实与约定。临时状态见 `YYYY-MM-DD.md`。
> 拆分文件（按需读，不要全部注入）：
> `ahk-timing.md`（定时器硬事实/定刻规范）、`ahk-pitfalls.md`（语言与测试坑）、
> `bench-and-gates.md`（性能基准/生产基准门禁）、`tech-debt-gates.md`（C1a–C6 度量闸门/覆盖率棘轮/文档 lint）、
> `env-and-ci.md`（环境/CI/E2E）、`contracts-and-pitfalls.md`（契约统计/易误判点/BUG-6）。

## 文档权威边界（五方，各自领域内唯一）

| 文档 | 权威领域 |
|------|---------|
| `AGENTS.md` | 架构决策、分层规则、妥协白名单、关键文件清单 |
| `asd-tauri/docs/test-map.md` | **一切测试数字**（其它文档只写指针） |
| `docs/developer-guide.md` | 环境搭建、构建、部署、排障 |
| `docs/tech-debt-register.md` | **技术债债项与状态（唯一登记处）**；配套 `docs/tech-debt-plan-2026-09-16.md` |
| `docs/graph-driven-workflow.md` | 图谱方法、开发/审查流程、同步机制 |
| `docs/research/` | **架构级调研结论唯一落点**；探针在 `tools/ahk-probes/` |

冲突：数字→test-map；架构→AGENTS；命令→developer-guide；流程→graph-driven-workflow；
外部引擎调研→`docs/research/`。**矛盾当场修正，不允许两边都留。**

> AHK v2 引擎调研 `docs/research/ahk-engine-architecture-2026-09-14.md`（源码锚点、10 探针、
> L1/L2/L3 共 22 项）。引擎源码 `AutoHotkey-2.0.26/source` **只读**（不改/不 fork/不编译），
> 由 `check-tech-debt.py` 的 **C6** 守住：须与官方 tag v2.0.26 不多不少（基线
> `scripts/vendor-baseline-ahk-2.0.26.txt` 取自上游）。**别改 submodule**（报告有 60+ 处行级引用）。

## 图谱工作流与四闸门

```bash
python .review-analysis/build_graph.py     # → .review-analysis/graph-raw.json
python .review-analysis/gen_graph_html.py  # → docs/review/<date>/graph/{json,html}
bash scripts/check-gates.sh [--quick]      # 一键四闸门（CARGO_INCREMENTAL=0 防 ICE）
```
靶点：环 / 逆向边 / 孤点 / 契约断点。depth（大→小）：`infrastructure 0`→`domain 1`→
`application 2`→`presentation 3`→`entry 4`→`executor 5`→`tests 6`→`other 7`；后四者豁免。

**基线唯一权威 `.review-analysis/graph-baseline.json`**（文档/记忆只写指针不抄数字）。
最近重取 2026-09-16（TD-025）。

⚠️ **图谱节点用 git 口径**（TD-025）：只认「已跟踪 + 未跟踪但未被 `.gitignore` 忽略」，与 C6 同口径。
不是「只取已跟踪」—— 否则新建未 `add` 的文件会隐身，而「新文件引入图环」最该提交前拦住。

坑：① `#Include` 正则**必须保留 `re.M`**；② 分层常量 `LAYER_META`/`LAYER_EXEMPT` 在
**gen_graph_html.py**（不在 build_graph.py）；③ crate 环检测只用生产边；④ 新增跨 crate
依赖须同步 `ALLOWED_CRATE_DEPS`；⑤ `extra_exclude` 走**子串**匹配且路径**仓库相对** ——
必须写 `"asd-tauri/e2e/"`（带尾斜杠），去掉斜杠永远匹配不上。

## 安全红线

- `watchdog.rs` 的 `STALE_PROCESS_NAMES` **只允许 `asd_executor.exe`**，绝不加 `AutoHotkey64.exe`。
- `src-tauri/src/application/`、`src-tauri/src/domain/` 是空历史占位，禁止加代码（C4 守卫）。
- WebView2 AHK-JS 通信**禁止 sync 代理**（死锁），必须 postMessage。
- 全局锁顺序 **`ipc_manager` → `watchdog`**，反转即死锁。
- 纯逻辑 crate **禁止**引入 `tauri`/`tokio`/`interprocess`/`windows`。

## 工程约定

- 换行：`.gitattributes` 强制 LF（`.ps1/.bat/.cmd` 除外）。既有入库文件在 worktree **本来就是 CRLF**，
  `eol=lf` 只在入库时归一化 → 新文件落盘成 CRLF 不必手工转。Edit 可能引入 CRLF，改完用 Python 校验。
- Conventional Commits，描述中文。⚠️ scope 正则 `[a-z-]+` **不允许数字**（`fix(e2e)` 因含 `2` 被拒）。
  长信息 `git commit -F <file>`（**不接受 MSYS 路径**，须 `cygpath -w`）；`-F` 与 `-m` 不能同用。
- ⚠️ **禁用 `git rm`/safe-delete**（路径拼接 bug 连带删 54 文件）→ `mv` 到 /tmp + `git add -A`。
- ⚠️⚠️ **在本 worktree 里禁用裸 `git reset`**（2026-09-16 两次事故）：分支是
  `refs/heads/workbuddy/main-5f18c6a6`（**带 `/` 的嵌套 ref**），执行 `git reset` 或
  `git commit` 后该引用文件会被清掉，worktree 变成 unborn HEAD，`git status` 于是把
  全部 825 个文件显示成 `A`（看着像"仓库没了"，其实提交对象都还在）。
  恢复方法（git **建不出**嵌套 ref，`git branch`/`update-ref` 都静默失败）：
  ```bash
  cd /d/1demo/AutoHotkeydemo && mkdir -p .git/refs/heads/workbuddy \
    && git rev-parse <sha> > .git/refs/heads/workbuddy/main-5f18c6a6
  ```
  兜底：同时建一个**顶层单名**分支（`git branch techdebt-2026-09-16 <sha>`）——
  顶层 ref 能正常创建且不会被清。主 worktree `D:/1demo/AutoHotkeydemo`（分支 `main`）始终完好，
  丢的只是这个 worktree 的分支指针。
  **第二次事故（同日，更隐蔽）**：`git commit` 自己也触发。这次不是 status 全 A，
  而是**新提交变成无父的 root commit** —— `git log` 只剩一条，`--stat` 显示
  825 files / 345417 insertions（整棵树被重新 add）。恢复（内容零丢失）：
  ```bash
  git log -1 --format=%B <root-commit> > _msg.txt
  NEW=$(git commit-tree "$(git rev-parse '<root-commit>^{tree}')" -p <原HEAD> -F "$(cygpath -w $PWD/_msg.txt)")
  git rev-parse "$NEW" > /d/1demo/AutoHotkeydemo/.git/refs/heads/workbuddy/main-5f18c6a6
  ```
  **排查教训**：`git status --porcelain | head -20` 会把后面的几百行 `A` 截掉，
  看着像"只有 15 个改动"。判断索引是否干净必须用 `| wc -l` 数总数，别用 `head`。

  **结论（2026-09-16 三次事故归纳）**：**任何会移动分支引用的操作都会清掉这个嵌套 ref** ——
  `git reset` / `git commit` / `git merge` / `git rebase` 无一幸免，连 `--ff-only` 也一样。
  现象是 `git log` 报 `your current branch does not have any commits yet`，但提交对象都在。
  **对策：所有 git 写操作都放到主 worktree `D:/1demo/AutoHotkeydemo`（分支 `main`，顶层 ref，稳定）做；
  这个 worktree 只用来读代码和跑 AHK/Rust 测试。** 需要同步分支时，不必在 worktree 里跑 git，
  直接把 main 的 sha 写进引用文件即可：
  ```bash
  mkdir -p /d/1demo/AutoHotkeydemo/.git/refs/heads/workbuddy
  git rev-parse <main 的 sha> > /d/1demo/AutoHotkeydemo/.git/refs/heads/workbuddy/main-5f18c6a6
  ```
  （注意 `mkdir -p` 不能省：引用被清时是整个 `workbuddy/` 目录一起没的。）
  相关：pre-commit 钩子会遍历所有暂存文件做体积检查，**暂存 825 个文件时钩子会跑很久**，
  命令被超时 SIGTERM 打断在 commit 中途 → 加剧上述问题。只暂存必要文件。
- ⚠️ **禁用 `git stash push -- <path>` 做暂存验证**：2026-09-16 用它后 HEAD 指向的 3 个提交对象
  从 `.git/objects` 消失，`git status` 直接 `fatal: bad object HEAD`（靠 fetch 远端救回）。
  要临时还原：`cp` 到 `$TEMP` + `git checkout HEAD -- <path>`。
- 提交信息**不写具体测试数字**；文档与代码**同 PR**。
- ⚠️ 改完 AHK 测试要同步 **test-map 三处**：① 明细行 ②《汇总》表 AHK 两行 ③ 文首「口径提示」
  静态/实跑数。只改①不改②③是**已犯过两次**的错。

## AHK 语言 / 运行时 / 测试坑

> 完整版见 `ahk-pitfalls.md`。高频要点：标识符**大小写不敏感**（常量须带前缀）；`case` 是保留字；
> `if true` 不生效用 `if 1`；不接受单行花括号块体；源码里一个反斜杠写 `"\"`；
> `result .= s` 不是 O(n²)，别优化累加方式。
> 测试侧：时延断言要 ≥40 样本、判漂移用中位数；用例必须选「判别性取值」；
> 结果写 `tests/test_results.log` 不写 stdout；宿主时延断言用 `ASD_HOST_TIMING` 门控。

## 环境 / CI / E2E

> 完整版见 `env-and-ci.md`。高频要点：
> 推送唯一可靠写法 `git -c credential.helper= push "https://x-access-token:$(gh auth token)@github.com/zyejf/AutoHotkeydemo.git" main`，
> 失败多为代理 502，**重试 1–3 次**，重试循环里判 `${PIPESTATUS[0]}`。
> ⚠️ Bash 命令里不要出现 `powershell`/`pwsh`/`reg.exe`（整体拦截）。
> ⚠️ `cargo clippy`/`cargo test` 可能 ICE（退出码 101）→ `CARGO_INCREMENTAL=0`。
> ⚠️ **推送后必须查 CI 结论**（TD-028）：`gh run list --limit 1 --json databaseId --jq '.[0].databaseId'`
> → `gh run view <id>`。「所有 job steps 为空、秒级失败」= 账户账单问题，别改代码。
> ⚠️ **CI 上的 E2E job 从未真正跑过**（2026-09-16 核对 96 次运行）。凡写「实测」都要说清本机还是 CI。
> 仓库已于 2026-09-16 **转公开**（转前扫描 825 个 tracked 文件，高危密钥零命中）。
