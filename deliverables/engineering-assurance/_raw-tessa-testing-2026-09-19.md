# 测试覆盖与测试债评估（工作流 1 · 第三段）

- **作者**：泰莎（Tessa）· 测试专家
- **日期**：2026-09-19
- **被测对象**：ASD 技能管理器 v4.0，仓库根 `D:\1demo\AutoHotkeydemo`，分支 `main`，HEAD `7cc216b`
- **测试数字权威源**：`asd-tauri/docs/test-map.md`（本报告所有测试数字均引用该文件并注明出处行；未自行造数）
- **本报告未修改任何业务代码，也未修改 test-map.md**（只核对、报告不一致）

---

## 0. 本次评估的证据等级说明

为避免「读代码推断」与「实测」混淆，本报告每条结论标注证据等级：

| 等级 | 含义 |
|---|---|
| **【实测】** | 本次在本机真实执行并拿到输出（命令与结果见 §1） |
| **【代码定位】** | 定位到了具体文件:行，但未实跑该断言（多为 CI 专属逻辑，本机无法复现） |
| **【文献】** | 引自仓内文档/台账（注明出处），未独立复现 |

> 本仓三次把「其实已有守护」误判成「没有守护」。因此凡本报告断言「某处**没有**守护」，均以**阳性对照**（故意造违规看是否报错）为据，见 §2。

---

## 1. 本次实跑记录（本机 Windows，2026-09-19）

| 编号 | 操作 | 命令 | 实测结果 |
|---|---|---|---|
| E1 | test-map 全量对账 | `CARGO_INCREMENTAL=0 python scripts/check-test-map.py` | `[A]` 通过；`[B]` asd-domain 154 / asd-ipc-protocol 72 / asd-application 173 / asd-test-harness 3 / asd-tauri 249 **全部 OK**；`[C]` 汇总行 登记 651 / 实际 651 → **PASS** |
| E2 | AHK 完整套件（默认＝本机口径） | `AutoHotkey64.exe tests/run_all_tests.ahk` | **总计 722 / 通过 722 / 失败 0 / 跳过 0**，耗时 42s，退出码 0 |
| E3 | AHK 完整套件（CI 口径） | `ASD_HOST_TIMING=0 AutoHotkey64.exe tests/run_all_tests.ahk` | **总计 722 / 通过 715 / 失败 0 / 跳过 7**，耗时 17s |
| E4 | 静态 `Test_` 计数 | 对 `run_all_tests.ahk` 纳入的 11 个文件求和 | **720**（46+28+64+84+57+33+41+93+96+77+101） |
| E5 | AHK 执行器各文件 `Test_` 数 | `grep -cE '^\s*Test_[A-Za-z0-9_]+'` | 46 / 28 / 64 / 84 / 57 = **279** |
| E6 | watchdog `--ignored`（G3h 等价） | `CARGO_INCREMENTAL=0 cargo test -p asd-tauri --lib -- --ignored --test-threads=1` | **15 passed / 0 failed / 0 ignored / 233 filtered out**，13.33s |
| E7 | 阳性对照 PC1–PC6 | 沙箱 `/tmp/pc`（仓库外副本），逐条注入违规后跑 `check-test-map.py --no-cargo` | 见 §2（沙箱已还原，与仓库原文 `diff` 一致） |

环境说明：`cargo` 全部带 `CARGO_INCREMENTAL=0`，本次未出现 ICE（退出码 101）。`cargo test` 走缓存，17s 完成。

**未能实跑的部分**：E2E（需 tauri-driver + msedgedriver + 完整构建，本机未装配；且 TD-061 已证明 Windows CI 栈不可用）。见 §5。

---

## 2. 阳性对照矩阵（本报告的方法核心）

在仓库外沙箱 `/tmp/pc`（`scripts/check-test-map.py` + `asd-tauri/docs/test-map.md` 的副本）逐条注入违规，观察闸门③ 是否报错：

| 编号 | 注入的违规 | 是否被捕获 | 判据 |
|---|---|:---:|---|
| **PC1** | AHK 明细行 `Test_` 方法数 46 → 99（套件数不动、总计不动） | ❌ **未捕获** | `[A] 文档内部自洽：通过` |
| **PC2** | AHK 明细行套件数 10 → 11（同一单元格） | ✅ 捕获 | `[AHK 执行器测试] **总计** 声明 61，实际明细之和 62` |
| **PC3** | 《汇总》AHK 执行器行 279 → 999（明细不动） | ❌ **未捕获** | `[A] 通过` |
| **PC4** | 《汇总》AHK v2 完整套件行 722 → 999 | ❌ **未捕获** | `[A] 通过` |
| **PC5** | 文首「口径提示」静态 720 / 实跑 722 → 999 | ❌ **未捕获** | `[A] 通过` |
| **PC6** | Rust 明细 `asd-domain/src/config.rs` 35 → 36（**反向对照**） | ✅ 捕获 | `[asd-domain] **小计** 声明 154，实际明细之和 155` |

**读法**：PC6 是反向对照 —— 它证明该脚本的校验机制**确实工作**。因此 PC1 / PC3 / PC4 / PC5 的「未捕获」是**真实缺口**，不是脚本失效或我的操作失误。

**根因（代码定位）**：`scripts/check-test-map.py:101-112`。明细行与小计行都只取单元格里的**第一个整数**（`first_int(cs[3])`）。AHK 行的单元格形如 `10 / 46`，取到的是**套件数 10**，方法数 46 根本没进求和。所以 AHK 侧只有「套件数」这一维被守护，「`Test_` 方法数」这一维完全裸奔。

---

## 3. 测试覆盖现状

### 3.1 Rust 侧（权威：test-map.md）

| 项 | 数值 | 出处 | 本次核验 |
|---|---|---|---|
| Rust 测试总数（运行时注册数） | **651** | test-map:231、:239 | E1 实测 **651**，逐 crate 全 OK |
| ├ asd-domain | 154 | test-map:35 | ✅ |
| ├ asd-ipc-protocol | 72 | test-map:48 | ✅ |
| ├ asd-application | 173（单元 74 + 集成 99） | test-map:62、:76、:77 | ✅ |
| ├ asd-test-harness | 3 | test-map:86 | ✅ |
| └ asd-tauri（src-tauri） | 249（`--lib` 248 + `tests/` 1） | test-map:111、:118、:120-123 | ✅ |
| 其中 `#[ignore]` | **15**（全在 `watchdog_integration_tests.rs`） | test-map:231 | 实测 15 处 `#[ignore]` 属性（另有 4 处是注释/文档提及，非属性） |
| 基准测试 | 7 criterion | test-map:129 | 未实跑 |
| 模糊测试 | 5 fuzz target | test-map:135-139 | 未实跑（CI 仅周日定时，:26-27） |
| 行覆盖率（**仅 3 个纯逻辑 crate**） | **89.05%**（5336/5992，15 文件） | test-map:148 | 见 §4.1 口径警告 |

> ⚠️ **口径（test-map:150-157）**：覆盖率分母**含 `#[cfg(test)]` 测试代码**，跨文件百分比不可比；`time_format.rs` 的 100% 里六成在测测试自己。已登记 TD-026（豁免不修）。

**类型分布**：单元 392（domain 111 + ipc 39 + app 74 + harness 3 + tauri 165）+ 集成/端到端 259。**单元:集成 ≈ 6:4**，金字塔中上层偏厚，属「集成测试承载契约」的有意设计（test-map:187-189 明确记载：删掉 `asd-ipc-protocol/tests/integration_tests.rs` 覆盖率纹丝不动，其价值在跨模块契约而非覆盖率）。

### 3.2 AHK 侧

| 项 | 数值 | 出处 | 本次核验 |
|---|---|---|---|
| AHK 执行器测试 | **61 套件 / 279 个 `Test_` 方法** | test-map:202、:232 | E5 实测 **279**（46/28/64/84/57），套件 10+12+7+13+19=**61** ✅ |
| AHK v2 完整套件（本机） | **722 用例 / 182 套件**，通过 722 / 失败 0 / 跳过 0 | test-map:233 | E2 实测 **722/722/0/0** ✅；套件数 182 ✅ |
| AHK v2 完整套件（CI） | 通过 715 / 失败 0 / **跳过 7** | test-map:233 | E3 实测 **722/715/0/7** ✅ |
| 静态 `Test_` 计数 | 720（实跑 722，差 2 为 Setup/Teardown 钩子） | test-map:18 | E4 实测 **720** ✅；`run_tests.ahk`（另一 runner）24 个 ✅ |
| 独立 AHK 脚本（G3g） | 11 个脚本 | `scripts/run-standalone-ahk-tests.sh:43-54` | CI:262-266 + check-gates.sh:214 均接入，**未实跑** |

### 3.3 JS 侧

3 个文件 / 静态计数 39 个 `it|test`：
- `asd-tauri/src/__tests__/api_contract.test.js`（test-map:289，TD-005，7 用例，前端 `api.js` ↔ Rust 命令双向契约）
- `asd-tauri/e2e/helpers/__tests__/ahk_path.test.js`、`error_utils.test.js`（test-map:287-288）

由 G3c（`node --test`，ci.yml:238-249）执行。TD-020 记录「G3c（39 用例）全绿、0 失败」——与静态计数一致。

### 3.4 E2E 侧

| 项 | 数值 | 出处 | 状态 |
|---|---|---|---|
| E2E 用例 | **9 suite / 53 用例** | test-map:237、:270、:233 | CI 上 **0 执行**；本机 2026-09-17 曾全绿（TD-016） |
| 执行模式覆盖 | 7/10（`joystick_*` 三种未纳入） | test-map:272 | — |

---

## 4. 覆盖盲区（按风险排序）

### 4.1 【风险最高】`src-tauri` 整体不在覆盖率门禁内 —— 89.05% 不是全仓覆盖率

- **证据**：`ci.yml:326` 覆盖率命令只含 `--package asd-domain --package asd-ipc-protocol --package asd-application`（3 个纯逻辑 crate，跑在 ubuntu，因 `src-tauri` 依赖 windows/tauri 在 Linux 编译不过）。
- **量化**：【文献】TD-007 / TD-054 记载 2026-09-18 本机实测 —— `src-tauri` 行覆盖率 **63.67%**、占全仓代码 **36.6%**；全仓 `--workspace` **82.05%**。与门禁口径 89.05% 差约 7 个百分点。最低三处：`lib.rs` **23.65%**（应用装配 `setup_ipc_callbacks` / `run`）、`infrastructure/watchdog.rs` **57.94%**、`infrastructure/logging.rs` **0%**。
- **盲区后果**：`lib.rs:run` / `setup_ipc_callbacks` 是**唯一入口的装配代码**，漏注册一个回调/插件不会让编译或单测失败，只在运行时静默少一个功能。TD-045 批次 7 已把它登记为「零自动化覆盖」。
- **不可测的结构原因**：【文献】TD-054 —— 未执行的 2124 个函数绝大多数是 `generate_handler!` 生成的闭包与 `run()` 内部闭包，**不是独立函数**，普通单元测试无法触达。已实测 `tauri::test::mock_app()` 这条路不通（且经对照组证明是「整个测试二进制 0xc0000139 无法加载」的 DLL/链接问题，不是 `tauri::test` 本身的问题）。
- **现状**：TD-054 **已豁免**（2026-09-18），明确「在 DLL 依赖或 E2E 兜底落地前，不要再往 `src-tauri` 投入补测试的工作量」。

### 4.2 watchdog 子进程生命周期：15 条 `#[ignore]`，且 CI 上**不阻断**

- **证据**：`ci.yml:162-167` —— G3h 步骤 `continue-on-error: true`（注释明写「观测期不阻断」）。17 个 `fn test_` 中 15 个带 `#[ignore]`（实测行号：60/114/154/223/246/273/308/333/361/378/405/426/444/468/522），仅 `test_backoff_durations_constant`(492) 与 `test_max_restart_attempts_constant`(510) 两个常量测试默认跑。
- **覆盖的路径**：`start_child_process` / `child_crash_restart` / `restart_limit` / `graceful_shutdown` / `heartbeat_recovery` / `exponential_backoff` 等 —— 正是「按键静默失效」这类**无声故障**的路径（ci.yml:155-157 自己的注释就写了「回归时没有任何红灯」）。
- **反证其可跑性**：E6 实测 **15 passed / 0 failed / 13.33s**。原排除理由「避免在 CI 中运行慢测试」**不成立**（ci.yml:158-160 已记录 13.39s）。**理由已不成立却仍未摘 `#[ignore]`，是纯遗留成本。**

### 4.3 关机序列：只有纯函数被测，编排逻辑零覆盖

- **证据**：`lib.rs:33 run_shutdown_sequence` / `lib.rs:45 perform_graceful_shutdown` 全仓仅出现在生产代码与注释中，**无任何测试引用**（实测 grep 仅命中 `infrastructure/shutdown.rs:3,9` 的注释与 `watchdog.rs:985` 的注释）。
- 被测的只有抽出来的纯函数 `try_acquire_shutdown_guard`（`lib.rs:805/810/813/820/825/831/836`，3 条用例，test-map:108）。
- **盲区**：真正的关机编排（释放热键 → 停 watchdog → 关 IPC）无测试。TD-045 批次 8 记载 `graceful_shutdown_watchdog` 是「三阶段降级链，最坏走到 kill」，且**「`Ok` 不代表真的成功了」** —— 恰恰是这种「返回 Ok 但没做成」的语义最需要测试。

### 4.4 死锁/并发：4 条用例，**无超时护栏**

- **证据**：`asd-application/tests/concurrency_tests.rs`（480 行，4 条用例：save/delete 不同分组、同组 save+delete、sync_config_changes）。实测 grep `timeout|deadlock|超时` **零命中** —— 没有任何用例带超时断言或死锁检测。
- **盲区后果**：`AppState` 是 `Arc<Mutex>` 装配（test-map:74）。一旦引入锁顺序反转，表现是**测试永久挂起**而不是变红 —— CI 只能靠 job 级 360 分钟超时兜底，等于**无检测**。TD-045 批次 9 还提到 `bridge.rs:182` 有「锁顺序说明（已知妥协 #2）」，说明锁顺序本身是已知风险面。

### 4.5 配置版本迁移：Rust 侧零迁移测试

- **证据**：`src-tauri/src/tests/config_compat_tests.rs` 11 条用例实测只覆盖「当前格式反序列化 + 7 种模式 + control_hotkeys」，唯一与版本相关的断言是 `:27 assert_eq!(main_cfg.version.as_deref(), Some("3.0"))` —— 只**钉住当前值**，没有 old→new 的迁移路径用例。
- **盲区**：AHK 侧有 `MigrationLoggerTests`（迁移日志），但那是**日志**不是**格式迁移**。config.json 从旧版本升级到 3.0 的转换逻辑在 Rust 侧无用例守护。

### 4.6 AHK 侧：722 个用例，**覆盖率数据为 0**

- **证据**：实测全仓无 AHK 覆盖率采集（grep 无命中）。【文献】`docs/tech-debt-plan-2026-09-16.md:193` 把「AHK 覆盖率方案预研」列为待办，`:196` 明确「AHK v2 无成熟覆盖率工具 → 先做 1 人天预研，出结论即止」。
- **盲区后果**：AHK 是 11.4k 行生产代码（台账基线表），有 722 个用例，**但无法回答「哪些生产行从未被执行」**。补测试只能靠人判断，无法像 Rust 侧那样用覆盖率找洞。

### 4.7 E2E：53 个用例在 CI 上**零执行**（详见 §5）

### 4.8 宿主时延断言：7 条在 CI 上**永远不跑**

- **证据**：`ci.yml:179` 固定 `ASD_HOST_TIMING: '0'`；`tests/test_ahk_executor/test_sender.ahk:482-486` 的 `_HostTiming()` 在 `= "0"` 时 `assert.skip`。E3 实测跳过 7 条，与 7 处 `this._HostTiming()` 调用点（行 526/549/575/691/1116/1191/1228）**逐一对应**：
  1. `Test_HighResClock_SleepUntil_ErrorBelow1ms`
  2. `Test_PressPrecise_HoldDurationMatchesKpd`
  3. `Test_ExecutePeriodic_EndToEndLatencyP95Within20ms`
  4. `Test_MultiKeySameSchedule_AllKeysHoldFullKpd`
  5. `Test_ExecuteSequence_EndToEndLatencyP95Within20ms`
  6. `Test_ExecuteSequence_StepIntervalMatchesDelay_NoDrift`
  7. `Test_ExecuteHybrid_SubGroupsKeepTheirOwnRhythm`
- **盲区量化**：`SenderPreciseTimingTests` 共 15 个 `Test_` 方法，**CI 上只跑 8 个**（含 QPC 分辨率、取整比例、合并遍历等价性等纯逻辑），**7 个端到端时延类永远跳过**。真正的守护点是本机四闸门（ci.yml:178 明写本机不设此变量）。**即：CI 无法发现「定刻退化成 AHK 网格 Sleep」这类回归** —— 而这正是 TD-052 / TD-041 反复处理的故障形状。
- **缓解**：ci.yml:234-236 有「跳过 == 0 → throw」的防失效锚点（防门控静默失效）。但**只校验 ≠0，不校验 ==7** —— 若 6 条被改名只剩 1 条跳过，CI 依然放行。

### 4.9 附带发现：IPC 收发其实**已**有真实覆盖（避免误判）

防止重复踩「把已有守护误判为缺失」的坑，明确记录：
- `src-tauri/src/tests/ipc_tests.rs` 26 条用例**走真实 named pipe**（实测：用 `interprocess::local_socket` 的 `create_listener` + `accept().await`，非 mock），覆盖 ping-pong、`send_command_and_wait_response`、`wait_response_timeout`、`pipe_broken_reconnect`、auth token 三条、`message_size_limit/boundary`、`pending_responses_cleanup` 等。
- `hotkey_merger` 6 条（test-map:46）+ ipc_tests 内 2 条，覆盖率 98.73%（test-map:180）。
- **结论：IPC 收发与热键合并**不属于盲区**（Rust 侧）。但这两块位于 `src-tauri`，**不在覆盖率门禁内**（§4.1），所以「有测试」与「覆盖率被度量」是两件事。

---

## 5. CI 可靠性评估

### 5.1 E2E：结论需要**分层表述**，不能只说「从未跑过」

| 口径 | 结论 | 证据 |
|---|---|---|
| **CI 上** | **仍然从未有任何一个用例被执行** | ①【代码定位】`ci.yml:564` `if: github.event_name == 'workflow_dispatch' && inputs.run_e2e`，且 `ci.yml:30-33` 该 input 默认 `false` → **push / PR 在结构上不可能触发 E2E**；②【文献】TD-061 / TD-062：2026-09-16 全量核对 96 次历史运行 0 次真实执行；2026-09-18 手动触发 4 轮（run 35343866509 / 35346047873 / 35350670139 / 35354358075）**均未建立 WebDriver 会话**，两条机制独立的通道全部证伪，TD-061 已豁免 |
| **本机** | **跑通过，且全绿** | 【文献】TD-016 状态列：2026-09-17 重建 `asd_executor.exe`（Ahk2Exe）后「**全量 E2E 首次跑通：9 suite / 53 用例全绿（9 passed / 9 total，100%）**」 |

**因此甄宇航给的前提「CI 上的 E2E job 从未真正跑过」—— 今天（2026-09-19）仍然成立，且比 2026-09-16 更明确**：不是「运气不好没触发」，而是 `ci.yml` 的 `if` 条件让它在 push/PR 上**结构性不可达**；手动触发的 4 轮也全部卡在栈层（上游 tauri-driver / msedgedriver 在 Windows 上的 `DevToolsActivePort` 问题，TD-061 证据①–⑤）。

**注意一个易错点**：TD-016 状态列同时记载「本条此前所有的 E2E 实测数字都是在『CI 从未真正跑过 E2E』+『跑的是旧执行器』双重失真下得到的」。引用 E2E 数字时必须区分本机/CI。

**E2E 仍有价值，别删**：【文献】TD-060 —— 2026-09-18 的 E2E 排查**实际抓到过 P0 生产缺陷**（`bundle.resources` 漏了 `high_res_clock.ahk`，导致**分发给用户的 release 版本**执行器启动即崩）。TD-062 因此保留其诊断基建。

### 5.2 其他「在 CI 上不生效」的测试

| 测试 | CI 上状态 | 证据 |
|---|---|---|
| watchdog 15 条 `--ignored` | 跑，但 `continue-on-error: true` **不阻断** | `ci.yml:162-167` |
| AHK 7 条宿主时延 | **永远跳过** | `ci.yml:179`；E3 实测 |
| `src-tauri` 249 条 | 跑（G3a，`ci.yml:151-153`），但**不进覆盖率** | `ci.yml:326` |
| fuzz 5 target | 仅周日定时触发 | `ci.yml:26-27` |
| benches 7 criterion | `bench` job，辅助信号 | `ci.yml:437` |
| AHK 生产基准 T1/T6 | `ahk-bench` job，**是门禁**（阻断合并） | `ci.yml:11-12`、`ci.yml:479` |

### 5.3 CI 门禁全景（四闸门）

`gates` job（windows-latest，任一红即失败）：G1 图谱基线 / G2a fmt + G2b clippy -D warnings / G3a cargo test / **G3h watchdog（不阻断）** / G3b AHK 套件 / G3c JS / **G3d test-map 对账** / G3e 技术债度量 / G3g AHK 独立脚本 / G4 人工清单。独立 job：coverage（**G3f 棘轮，阻断**）、js-lint、security-audit、miri、fuzz、bench、ahk-bench（**阻断**）、e2e（手动）。

---

## 6. test-map 三处自洽性核对（逐条给证据）

甄宇航指定的三处：① 明细行 ②《汇总》AHK 两行 ③ 文首「口径提示」静态/实跑数。

| # | 位置 | 文档值 | 本次实测 | 是否自洽 |
|---|---|---|---|:---:|
| ① | 明细行 test-map:197-202 | 61 套件 / **279** `Test_` 方法（46/28/64/84/57） | E5：46/28/64/84/57 = **279**；套件 10+12+7+13+19 = **61** | ✅ |
| ② | 《汇总》test-map:232-233 | AHK 执行器 **279**；完整套件 **722**（本机 722/0/0，CI 715/0/7） | E2：722/722/0/0；E3：722/715/0/7；E5：279 | ✅ |
| ③ | 文首口径提示 test-map:18 | 静态 **720** / 实跑 **722**（不含 `run_tests.ahk` 的 24） | E4：静态 **720**；E2：实跑 **722**；`run_tests.ahk` **24** | ✅ |

### 结论

**当前这三处的数值全部自洽 —— 今天实测一致，没有发现残留的「改①不改②③」。**

**但是：这三处的自洽没有任何机器守护。** PC1 / PC3 / PC4 / PC5 四条阳性对照证明：
- 改 ① 明细行的 **`Test_` 方法数**而不改 ② → 闸门③ **放行**（PC1）
- 改 ②《汇总》AHK 两行而不改 ① → 闸门③ **放行**（PC3、PC4）
- 改 ③ 文首口径提示（或反之）→ 闸门③ **放行**（PC5）
- 只有改 **套件数**这一维会被抓（PC2）

**即：历史「只改①不改②③」犯过两次，其根因（方法数这一维没有校验）至今仍在。** 下次改 AHK 测试时，同样的错误还会静默发生。

### 附带发现（不属于指定三处，但同类）

- **test-map:307-308 的 E2E 文档引用路径是错的**：写成 `docs/e2e-test-report.md` / `docs/e2e-known-issues.md`，实测两处均不存在；真实路径是 **`asd-tauri/e2e/docs/e2e-test-report.md`** 与 **`asd-tauri/e2e/docs/e2e-known-issues.md`**（`find` 实测命中）。属悬空引用。
- **非漂移项（避免误报）**：`docs/tech-debt-register.md:32` 的「AHK 719 / Rust 405」看起来与当前 722 / 651 不符，但该文件 `:23-26` 已**明确声明这是 2026-09-16 历史快照、不得就地改写、当前值以 test-map 为准**。因此**不是文档漂移**，不登记为债。仅提示：`Rust 405` 与当前 `651` 差距较大，读者若跳过表头说明会严重低估测试规模。

---

## 7. 测试债清单

工作量 1–5（5 最难），均为粗略估算。

| # | 债 | 影响 | 修复方向 | 工作量 |
|---|---|---|---|:--:|
| **TT-01** | AHK 测试数字的「`Test_` 方法数」一维无机器守护（PC1/3/4/5 实证） | 改测试后 test-map 静默失真；历史上已犯两次 | 扩 `check-test-map.py`：AHK 明细/汇总行按「套件数 + 方法数」**双维**校验；把文首口径提示的 720/722 做成可解析锚点并纳入 [A]。**注意配套防永真式锚点**（解析不到即 FAIL），否则会造一个新的假绿闸门 | **2** |
| **TT-02** | watchdog 15 条 `#[ignore]` 仍挂 `continue-on-error`，排除理由已不成立 | 子进程生命周期（崩溃重启/重启上限/优雅关机）回归**无任何红灯**，表现为按键静默失效 | 已观测到「13.33s、15 全绿」（E6 实测）。按 `ci.yml:160` 既定路径：连续绿 3–5 次后**摘掉 `#[ignore]`** 转硬门禁，去掉 `continue-on-error` | **2** |
| **TT-03** | `src-tauri`（占全仓 36.6%，覆盖率 63.67%）无任何覆盖率门禁 | 门禁报的 89.05% **不是全仓数字**；`lib.rs` 23.65% 的装配代码漏注册插件不会红 | TD-054 已豁免且明示「不要再投入补测试」。唯一有收益的方向是 TD-054 状态列 ①：用 `dumpbin /imports` 定位 0xc0000139 缺失符号（已排除 `tauri::test` 本身与 cdylib DLL 名冲突两个假设）。**不做新一轮补测试** | **4** |
| **TT-04** | 并发测试无超时护栏，死锁只能靠 job 级 360 分钟超时 | 锁顺序反转 = 永久挂起 = 等同无检测 | 给 `concurrency_tests.rs` 4 条用例加 tokio/线程超时断言（`tokio::time::timeout` 或 `serial_test` + watchdog 线程），让死锁**变红而非挂起**；顺带把 `bridge.rs:182` 的「锁顺序已知妥协」写成可执行判据 | **2** |
| **TT-05** | 关机编排（`perform_graceful_shutdown` / `run_shutdown_sequence`）零覆盖 | 「返回 Ok 但没真关掉」的语义无守护，最坏走到 kill | 沿用项目已有套路（TD-054 给 `logging.rs` 抽纯函数、TD-045 给 `try_acquire_shutdown_guard` 抽纯函数）：把编排中的**可判定部分**继续抽纯函数测；编排本体在 §TT-03 解决前无解 | **3** |
| **TT-06** | E2E 53 用例在 CI 上结构性不可达 | 端到端链路零覆盖；TD-060 证明它能抓 P0，价值真实 | 按 TD-062 既定的三个前置条件（栈恢复 / 修 `E2E_TIMEOUT_MS` 空串→0 / E2E 独立 concurrency group）再启用。**栈未恢复前不得开默认**，否则是噪音闸门 | **4**（受制于上游） |
| **TT-07** | AHK 侧无覆盖率度量（722 用例，0 覆盖率数据） | 无法回答「哪些 AHK 生产行从未执行」，补测试全靠人判断 | 先出**预研结论**即可（`tech-debt-plan:193-196` 已定：1 人天，出结论即止，不硬做）。若结论是不可行，就显式登记为长期盲区并在文档中写清，**不要留成悬而未决的待办** | **1**（仅预研） |
| **TT-08** | Rust 侧配置版本迁移零用例（只钉住 `version == "3.0"`） | 旧配置升级到 3.0 的转换逻辑无守护 | 补 old→new 迁移用例：放几份历史版本 config 样本进 `asd-tauri/tests/fixtures/configs/`，断言迁移后字段与校验器通过。**先确认当前是否真的存在迁移代码**——若无迁移逻辑，则本条应改为「钉住『不支持迁移』这一事实」 | **2** |
| **TT-09** | G3b 只校验「跳过 ≠ 0」，不校验「跳过 == 7」 | 7 条宿主时延断言若被改名/误删到只剩 1 条，CI 依然放行 | `ci.yml:234` 改为精确比对 7（或改为「≥7」并同步 test-map:233）。**注意**：改成精确值后，每次合法增减都要同步改 CI，需评估维护成本 | **1** |
| **TT-10** | test-map:307-308 的 E2E 文档路径悬空 | 读者按图索骥找不到文档 | 改为 `asd-tauri/e2e/docs/e2e-test-report.md` / `.../e2e-known-issues.md`（实测路径） | **1** |

**未列入（已明示豁免/不修，勿重复投入）**：TD-026 覆盖率分母含测试代码（两条修法实测堵死）；TD-054 `src-tauri` 覆盖率（见 TT-03）；TD-061 Windows E2E 栈（上游依赖）；TD-020 E2E dev 依赖 12 high（`extract-zip` 全版本无补丁，生产依赖为 0）。

---

## 8. 给主理人的一句话结论

测试资产**数量充足且数字可信**（Rust 651、AHK 722/279、JS 39，全部本次实测对账通过），真正的风险不在「测试不够多」，而在三处**结构性盲区**：① `src-tauri` 占全仓 36.6% 却完全在覆盖率门禁之外，门禁报的 89.05% 被当成全仓数字会严重高估；② watchdog 子进程生命周期 15 条用例挂 `#[ignore]` 且 CI 不阻断，排除理由（"慢"）实测 13.33s 已不成立；③ AHK 侧 test-map 的**方法数**这一维没有任何机器守护（4 条阳性对照实证放行），历史上犯过两次的错还会再犯。

---

## 附录 A：本次未实跑与不可核实项（诚实声明）

1. **未实跑 E2E**：本机未装配 tauri-driver + msedgedriver + 完整 release/debug 构建；且 TD-061 已证明 Windows 栈不可用。相关结论全部标注【文献】，出处已给。
2. **`gh run list` 无法核实**：`gh` 已安装（v2.89.0）但**未认证**（`gh auth login` / `GH_TOKEN` 均未配置），无法联网核对 2026-09-16 之后是否有新的 E2E 运行。E2E 结论以 `ci.yml` 代码定位 + 仓内文档为准，**未经 GitHub API 独立核实**。
3. **未实跑** fuzz（5 target）、benches（7 criterion）、ahk-bench（T1/T6）、G3g 独立 AHK 脚本（11 个）、完整 `cargo test --workspace`（G3a）。
4. **未实跑** 覆盖率的重采集（约 4 分钟/次）；覆盖率数字引自 test-map:148 与 `.review-analysis/coverage-baseline.json`（`global_lines_pct: 89.05`，15 文件）。
5. **E6 的 233 filtered out** 与 test-map「`--lib` 248」自洽（248 − 15 ignored = 233），可交叉验证。

## 附录 B：对仓库的改动

- **未修改任何业务代码，未修改 test-map.md。**
- 新建：`deliverables/engineering-assurance/_raw-tessa-testing-2026-09-19.md`（本报告）
- 副作用：`tests/test_results.log` 因实跑 AHK 套件被重写（该文件**未被 git 跟踪**，实测 `git ls-files` 无输出；当前内容为 E2 的本机默认口径结果 722/722/0/0）。
- 阳性对照全部在仓库外沙箱 `/tmp/pc` 进行，已还原并与仓库原文 `diff` 一致。
