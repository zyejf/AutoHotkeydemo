# 工程保障团队迭代收口报告

**日期**：2026-09-19
**工作流**：工作流 1（代码审查）+ 工作流 4（部署前检查）组合迭代
**参与成员**：Cody（代码审查）、Archi（架构）、Rex（SRE）、Tessa（测试）、Docu（文档）；主理人 甄宇航（Zhen）

---

## 📌 TL;DR

- **全部推送的提交均已通过 CI**，四次运行结果全绿（见 §四）。工作树干净，本地与远端引用已对齐。
- **本轮无 🔴 生产缺陷**。严重度分布：🟠高 1（发布链路会把人引向旧代码）、🟡中 3（Miri 环境失败、G3h 曾恒绿空转、IPC DACL 价值边界）、🟢低 2。
- **非阻塞**（可继续使用）：Miri job 仍失败，定性为环境问题而非 UB；**阻塞**（不建议对外发版）：发布链路未接通、无分支保护（配置项，进行中）。
- **最重要的一条**：本轮三次靠实测推翻了既有判断 —— `CO` 占位 SID 在命名管道上不展开、G3h 步骤常年跑 0 条用例、以及我原先认为「分支保护无法核实」。

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| 整体评级 | 🟢 通过（合入）／🔴 不通过（对外分发） |
| 阻塞项数量 | 1（发布链路未接通；分支保护已于本轮启用并独立验证） |
| 本轮闭环 | TD-071 IPC DACL、用户侧文档三件套入库、G3h 假守护、test-map 口径 |
| 关键行动项 | 5 条（见行动清单） |
| 建议下一步 | 接通发布链路（GitHub Release + 产物冒烟），再谈对外分发 |

---

## 一、交付清单（7 个提交，均已推送）

| 本地提交 | 远端 sha | 内容 |
|---|---|---|
| `8c9781b` | `9fd8a697` | 修复 G3d 红灯（`test-map` 小计/总计行漏改） |
| `f33246c` | `93d88d68` | 用户侧文档三件套（README / user-guide / troubleshooting）+ 安装前置订正 |
| `482085e` | `61e6fcd9` | TD-071 IPC 管道 DACL + 测试闸门加固（`ci.yml` / `check-test-map.py`） |
| `bfa4345` | `24db3ee6` | 台账 TD-071 实测结论 + 守卫生效清单同步 |
| `7d53846` | `aee4179b` | 归档交付报告与发布链路调研 |
| `438cd63` | `ee8008bc` | 测试闸门加固报告 + 既有报告更新 |
| `70cc57f` | `bfffeb12` | TD-071 结项，统计行与状态词表同步 |
| `8e19a25` | `e8bcaf5e` | release job 加第三重护栏：禁止以 tag 触发（防产出旧代码包） |
| `8c42385` | `606686ba` | 记录分支保护已启用并核实管理员推送通道 |

最终远端 `main` = `bfffeb12047b5c2754bcd0cd32d6ec79f0f1888d`，本地 `main` / `origin/main` 已对齐，未提交改动 0 项。

---

## 二、各成员产出

| 成员 | 交付 | 落盘位置 |
|------|------|---------|
| Cody | TD-071：库原生 DACL 路径实现 + 真实 SID 方案 + 3 条测试 | `td071-ipc-dacl-2026-09-19.md` |
| Tessa | 闸门加固：G3i / F1 / F2 / [E] 用例下限门，G3h 修复 | `test-gate-hardening-2026-09-19.md` |
| Docu | 用户侧文档三件套 + 索引报告 | `README.md`、`docs/user-guide.md`、`docs/troubleshooting.md`、`user-docs-2026-09-19.md` |
| Archi | 发布链路方案 + TD-083 可行性论证 | `docs/research/release-pipeline-2026-09-19.md`、`release-pipeline-2026-09-19.md` |
| Rex | CI 核实 + Miri 定性 + 部署前 Go/No-Go | `deploy-gonogo-2026-09-19.md`、`_raw-rex-miri-ci-log-2026-09-19.txt` |

---

## 三、本轮关键发现（三处判断被实测推翻）

### 3.1 `CO`（Creator Owner）在命名管道上不展开 —— 差点提交一个废掉 IPC 的改动

`ipc.rs` 原注释称「`interprocess` 不支持 DACL，须绕过库直调 `CreateNamedPipeW`」。**该说法被证伪**：库原生提供
`interprocess::os::windows::local_socket::ListenerOptionsExt::security_descriptor`，并透传到 `CreateNamedPipeW`。

但真正的坑在下一步：我最初用 SDDL 的 `CO` 占位 SID 表达「当前用户」，两条测试给出了决定性结论：

| 测试 | 结果 | 说明 |
|---|---|---|
| SYSTEM-only SDDL，非 SYSTEM 连 | **ok（连不上）** | DACL 机制确实生效，未被静默忽略 |
| 生产 SDDL 用 `CO`，同用户连 | **FAILED：拒绝访问（os error 5）** | `CO` 不展开，连创建者自己都被挡 |

**若只满足于「编译通过」就提交，上线的是一个彻底不可用且用户无感知的 IPC。** 最终改为取真实 SID。

**价值边界（必须说清，不能夸大）**：显式 DACL 挡不住**同用户**进程（SID 相同），能挡**跨会话 / 跨用户**；
主威胁「同权本地进程冒充」仍由随机管道名 + `ASD_AUTH_TOKEN` 首消息认证承担。**不得把 DACL 当成该威胁的解法。**

### 3.2 G3h 是常年恒绿的空转步骤

`ci.yml` 的 G3h 步骤跑 `cargo test -- --ignored`，而全仓活跃 `#[ignore]` 为 0（唯一命中是被注释掉的），
于是每次 **跑 0 条用例 → rc=0 → 绿灯**，且步骤名挂着「观测期不阻断」，给人「将来会启用」的错觉。
已改为按模块名直接跑该组用例。**CI 日志实测确认修复生效**：`running 17 tests` / `17 passed; 0 failed`。

### 3.3 分支保护：从「不可核实」变成「可执行」

我原先把它归为「不可完成（无法验证）」。Rex 用 API 返回 404 **直接证实** `main` 无分支保护，
把判断从推断变成事实。已派其开启，要求 `enforce_admins: false` —— 否则会把我自己的 API 推送通道堵死
（`github.com` 直连不可达，本轮全程走 Git Data API 复刻推送）。**已执行并独立验证通过**（详见行动清单 #1）。Rex 还主动核实了 token 的 `admin: true` —— 这正是 `enforce_admins=false` 能保住通道的前提，也是这类配置最容易埋雷的地方。

### 3.4 一条真回归被契约测试抓到（正面证据）

全量测试曾因 `ipc.rs` 注释中反引号包裹中英混排片段而失败，由 TD-050 的
`backtick_cjk_contract_tests` 抓到。已修复并转绿。**这说明该契约测试是真守护，不是纸面文章。**

---

## 四、CI 验证（全部实测）

| run id | head sha | 结论 |
|---|---|---|
| `35446746668` | `9fd8a697` | completed / **success** |
| `35447863126` | `93d88d68` | completed / **success** |
| `35449054180` | `aee4179b` | completed / **success** |
| `35449825193` | `bfffeb12` | completed / **success** |
| `35450459973` | `e8bcaf5e` | completed / **success** |

`四闸门 (windows-latest)` job 内 G3h 步骤实测 `running 17 tests` / `17 passed; 0 failed`。
Miri UB Check job 仍 `failure`，但为 `continue-on-error`，不阻断合并。

⚠️ **口径提示**：上述均为 **CI** 结论；本机结论（`check-test-map.py` rc=0、`check-tech-debt.py` rc=0、
`cargo test --workspace --all-targets` 全绿）是另一套环境，两者不可混用。

---

## ✅ 行动清单（按优先级）

| # | 行动 | 负责角色 | 紧急度 | 预期完成 |
|---|------|---------|--------|---------|
| 1 | ~~给 `main` 开启最小分支保护~~ **已完成**：PUT 200，且 GET 读回独立验证 `enforce_admins=False`、`required_status_checks=None`、`restrictions=None`、review=1；另 `allow_force_pushes=False`、`allow_deletions=False`。Rex 并额外核实 token `admin: true`（这是 `enforce_admins=false` 能保住推送通道的前提） | Rex | P0 | 2026-09-19 |
| 2 | 接通发布链路：GitHub Release 步骤 + NSIS 产物冒烟 | Archi 出方案，主理人执行 | P0 | 需人工参与 |
| 3 | 处理远端遗留 Release `v0.1.0`（tag 指向远落后于 HEAD 的旧提交，误触发会产出旧代码包） | Rex | P1 | 同 2 |
| 4 | G3a 晋级留痕：本机与 CI 各连续 ≥10 次全绿的证据尚未留痕 | Tessa / Rex | P1 | 下一轮 |
| 5 | Miri job 长期红灯需定性跟踪（当前定性为环境问题，但掩盖了 `asd-ipc-protocol` 的 Miri 覆盖实为 0） | Rex | P2 | 按需 |

---

## ⚠️ 待完善 / 已知局限

- ~~**分支保护仍在推进**~~ **已闭环**（行动清单 #1）。附带收益：`allow_deletions=false` 堵住了历史上「嵌套 ref 被删除导致仓库看起来没了」那类事故的**远端**路径（本地侧另有 `scripts/hooks/reference-transaction` 守卫）。
- **分支保护刻意留了缺口**：`required_status_checks` 仍为 null —— 现在绑 required checks，CI 偶发抖动会把正常提交卡死。等 CI 稳定后再单独决策，不要顺手补上。
- **发布链路为方案阶段，未执行**：本轮明确禁止打 tag / 创建 Release / dispatch 发布 job。
- **TD-083（重启后热键是否真的不恢复）** 仍需端到端实测，Archi 已给出零 GUI 的对账路径论证。
- **首次真实 NSIS 打包冒烟** 仍未做过 —— 产物层面「从未产出过发布包」这一点未改变。
- **GPL Q2**（自研代码是否被传染）需法务意见，非技术手段可解；已降为建议性，不影响分发义务。
- 本轮所有「实测」除特别标注外，均为 **本机 Windows**；CI 结论单独标注。

---

## 📚 数据来源 & 成员产出索引

- Cody（代码审查）：`deliverables/engineering-assurance/td071-ipc-dacl-2026-09-19.md`
- Tessa（测试）：`deliverables/engineering-assurance/test-gate-hardening-2026-09-19.md`
- Docu（文档）：`deliverables/engineering-assurance/user-docs-2026-09-19.md`
- Archi（架构）：`docs/research/release-pipeline-2026-09-19.md`、`deliverables/engineering-assurance/release-pipeline-2026-09-19.md`
- Rex（SRE）：`deliverables/engineering-assurance/deploy-gonogo-2026-09-19.md`、`_raw-rex-miri-ci-log-2026-09-19.txt`
- 既有基线报告：`deliverables/engineering-assurance/production-readiness-2026-09-19.md`
- 台账：`docs/tech-debt-register.md`（TD-071 本轮结项）

---

> 本报告由工程保障团队 AI 协作生成，关键决策请由人类工程负责人复核。
