# Task 7：文档完整性审查

> 审查日期：2026-08-20
> 审查维度：文档完整性（文档与代码实际状态的一致性）
> 审查方式：只读，未修改任何 .md/.toml/.json/.rs/.ahk 文件（仅生成本报告）
> 审查对象：AGENTS.md、docs/developer-guide.md、docs/migration-guide.md、docs/commit-convention.md、docs/code-review-report-2026-08-03.md、docs/review/、docs/superpowers/、asd-tauri/docs/test-map.md、asd-tauri/TESTING.md、asd-tauri/Cargo.toml、asd-tauri/src-tauri/tauri.conf.json、config.json

---

## 一、执行摘要

逐项核对 10 个审查重点后，**核心规范文档 AGENTS.md 已基本与代码保持一致**（workspace 5 members、34 个 Tauri command、13 个 IpcCommand 变体、10 种执行模式、AHK 执行器 57 套件/244 个 Test_ 方法、config.json ↔ domain/config.rs 均核对一致）。但存在两类明显漂移：

1. **`docs/developer-guide.md`、`docs/migration-guide.md` 严重过时**，仍描述旧的单 crate 结构（`src-tauri/src/{domain,application,infrastructure}/`），该目录已不存在；IpcCommand 仍写 9 变体、Tauri Command 仍写 13 个、`Config::load_from_file()/save()` 已迁移到 `ConfigRepository`。这会导致开发者断链（Critical）。
2. **测试统计口径在多份文档间互相矛盾**：test-map.md 汇总表与其自身明细表对不上（asd-tauri 217 vs 明细 154），AGENTS.md 与 test-map.md/TESTING.md 对 Rust 总数、AHK 执行器测试数（244 vs 467）、fuzz target 数（5 vs 3）、以及已移除的 `test-manifest` feature 的描述彼此冲突。

### 已核实一致（无漂移）的条目

| 审查点 | 结论 | 依据 |
|--------|------|------|
| workspace 成员数 5 | ✅ 一致 | Cargo.toml members = asd-domain、asd-ipc-protocol、asd-application、asd-test-harness、src-tauri |
| 34 个 Tauri command | ✅ 一致 | `grep -c '#\[tauri::command\]'` src-tauri/src = 34（group 8 + config 11 + hotkey 2 + recording 8 + system 5） |
| IpcCommand 13 变体 | ✅ 一致 | command.rs 恰好 13 变体，AGENTS.md 示例与源码字段/顺序完全一致 |
| 10 种执行模式 | ✅ 一致 | domain/config.rs `VALID_MODES` 含 10 项，与 AGENTS.md 模式表一致（含 3 个 joystick 模式） |
| AHK 执行器 57 套件/244 Test_ | ✅ 一致 | `grep extends AutoHotUnitSuite` = 57；`grep '^\s*Test_\w+\('` = 244 |
| config.json ↔ config.rs | ✅ 一致 | 顶层结构 CONTROL_HOTKEYS/GroupSettings/HoldSettings/lastModified/version 与 `Config` 结构体 serde 字段完全对应 |
| AHK 架构妥协引用文件存在性 | ✅ 一致 | mode_registry/error_system/joystick_input/config_service/backup_core/joy_hotkey_manager 均存在，被删除的 joystick_input_utils.ahk 确实不存在 |
| E2E 9 suite / 53 用例 | ✅ 一致 | e2e/specs 共 9 个 spec，用例数 1+12+8+3+5+5+7+7+5=53 |

### 发现总数统计

| 严重级别 | 数量 |
|----------|------|
| Critical | 1 |
| Important | 4 |
| Minor | 9 |
| **总计** | **14** |

---

## 二、发现清单

### T7-01（Critical）· developer-guide.md 整篇基于已废弃的单 crate 结构，与实际 5-member workspace 严重不符

- **位置**：`docs/developer-guide.md` §1.2（L51-85）、§2.3.3（L226-236）、附录 E（L975-993）、§1.1（L29）
- **维度**：文档完整性
- **严重级别**：Critical
- **描述**：
  - §1.2 仍把 Rust 源码描述为 `src-tauri/src/domain/`、`src-tauri/src/application/`、`src-tauri/src/infrastructure/` 三个子模块，并称「domain 层 3 文件 / application 层 2 文件」。**实际当前为 5-member workspace**，领域/协议/应用逻辑已拆到 `crates/asd-domain`、`crates/asd-ipc-protocol`、`crates/asd-application`、`crates/asd-test-harness`，`src-tauri/src/` 下已无 `domain/`、`application/` 目录（仅 commands/、infrastructure/、tests/、bridge.rs、lib.rs、main.rs）。
  - `models.rs` 被描述为「SkillGroup、IpcCommand（9 变体）、IpcMessage（8 工厂方法）」，实际 IpcCommand 现为 13 变体且已不在 domain 而在 `asd-ipc-protocol/src/command.rs`。
  - §2.3.3 IpcCommand 表仅列 9 变体，缺 `PauseRecording`、`ResumeRecording`、`StartValidation`、`StopValidation`。
  - 附录 E 称「13 个 Tauri Command」，实际为 34 个。
  - §1.1 称 api.js「13 个已实现 invoke + 19 个 stub」，与 34 个命令不符。
- **根因**：该文档版本 1.0 写于 2026-05-29，早于 crate 抽取（workspace 化）与后续命令扩充，此后未同步更新。
- **修复建议**：重写 §1 项目结构为 5-member workspace；按 command.rs 重写 IpcCommand 表（13 变体）；附录 E 按 `asd-tauri/src-tauri/src/commands/` 下 5 个命令文件重列 34 个 command；并修正 api.js 计数。或直接在文档顶部标注「已过时，以 AGENTS.md 为准」并归档。

### T7-02（Important）· migration-guide.md 引用已迁移/删除的 API 与过时结构

- **位置**：`docs/migration-guide.md` §1.1（L42）、§3.4（L296-306）、§4.1（L421）、§4.3（L517）、§5.4.6（L562）
- **维度**：文档完整性
- **严重级别**：Important
- **描述**：
  - §1.1 仍描述 `src-tauri/` 下 `domain/ infrastructure/ application/` 三目录 +「13 个 Tauri Commands」，与实际 5-member workspace + 34 命令不符。
  - §3.4 IpcCommand 表仅 9 变体（缺 4 个）。
  - §4.1 称 `Config::load_from_file()` 负责「去除 UTF-8 BOM」、§5.4 称 `Config::save()` 使用 `to_string_pretty()`——这两个方法**已不在 `Config` 上**，I/O 已迁移至 `asd-application/src/config_repository.rs`（`ConfigRepository::load_from_file/load_from_file_checked/save_to_file`）。
  - §4.3 顶层结构表把 `GroupSettings` 标为 `HashMap<String, GroupConfig>`，实际 `domain/config.rs` 使用 `IndexMap<String, GroupConfig>`（有序）。
- **根因**：文档写于 I/O 泄漏修复（设计决策 #2）与 crate 抽取之前，未回填。
- **修复建议**：将 I/O 引用改为 `ConfigRepository`；IpcCommand 表补齐 13 变体；`HashMap` 改 `IndexMap`；整体对齐 AGENTS.md 的 5 crate 描述。

### T7-03（Important）· TESTING.md 引用已删除的 test-manifest feature、fuzz 数量与汇总数过期

- **位置**：`asd-tauri/TESTING.md` L6、L8、L133-146
- **维度**：文档完整性
- **严重级别**：Important
- **描述**：
  - 运行命令矩阵（L141-144）与「关键提示」（L152-154）反复要求 `--features test-manifest` / `--features asd-tauri/test-manifest`。**`src-tauri/Cargo.toml` 已无任何 `[features]` 段**（test-manifest 已删除，且有 `src-tauri/tests/test_manifest_feature_removed.rs` 专门验证该 feature 已移除）。
  - L8、L146 写「模糊测试：3 个 fuzz target」，实际 `fuzz/fuzz_targets/` 有 5 个（另缺 `fuzz_ipc_message_parse.rs`、`fuzz_hotkey_merger.rs`）。
  - L6「Rust 测试函数：506+ 个」与 test-map.md 汇总「609」冲突。
- **根因**：test-manifest feature 在 Task 中被移除（见 code-review-report C8），但 TESTING.md 未同步；fuzz target 由 3 增到 5 未更新。
- **修复建议**：删除所有 test-manifest 相关命令与提示；fuzz 数量改为 5 并补全运行命令；Rust 测试数与 test-map.md 对齐为单一口径。

### T7-04（Important）· test-map.md 汇总表与明细表不一致，且逐文件测试计数严重过时

- **位置**：`asd-tauri/docs/test-map.md` L15-19、L27-32、L69、L80-99、L146
- **维度**：文档完整性
- **严重级别**：Important
- **描述**：
  - asd-tauri 明细「小计 153」（L92）+ manifest 集成 1（L98）应 = 154，但「总计 217」（L99）相差 63。
  - asd-ipc-protocol 明细「小计 71」（L32）但汇总写 72（L146）。
  - asd-test-harness 明细写「0」（L69）但汇总写 4（L146）；AGENTS.md 写 3。
  - 以 `grep '#\[(test|tokio::test)\]'` 实际计数对照，多处明细严重不符：`bridge_tests.rs` 文档 13 → 实际 4；`config_cmd.rs` 7 → 29；`group_cmd.rs` 4 → 20；`recording_cmd.rs` 3 → 21；`watchdog.rs` 21 → 28；`watchdog_integration_tests.rs` 17 → 14；`command.rs` 3 → 4；`error.rs` 5 → 6；`integration_tests.rs`（app）36 → 34。
- **根因**：test-map.md 头部标注「2026-06-27 统计」，但明细表与汇总表更新不同步，且与 2026-08-04 后新增/重构测试不一致。
- **修复建议**：用文档自带统计命令（L212-218）重新全量统计各文件测试数，逐行更新明细表，并让「小计=明细之和=汇总」三者一致。

### T7-05（Important）· 测试统计口径跨文档冲突（Rust 592 vs 609、AHK 执行器 244 vs 467、AHK v2 581 无法对账）

- **位置**：`AGENTS.md` L135/L340/L274 vs `asd-tauri/docs/test-map.md` L146-147 vs `asd-tauri/TESTING.md` L6-8
- **维度**：文档完整性
- **严重级别**：Important
- **描述**：
  - Rust 测试总数：AGENTS.md「592（asd-domain 129 + ipc 72 + application 186 + harness 3 + tauri 202，截至 2026-08-04）」vs test-map.md「609（129+72+187+4+217，2026-06-27）」。其中 asd-application 实际 grep 为 186（与 AGENTS.md 一致、test-map 187 略偏），asd-test-harness 实际 4、asd-tauri 实际约 205。
  - AHK 执行器：AGENTS.md「244 个 Test_ 方法」（正确，见 §一核实表）vs test-map.md/TESTING.md「467 测试」——两套口径（Test_ 方法数 vs 断言/用例数）未说明，读者无法对账。
  - AHK v2「581 个测试」仅 AGENTS.md 出现（test-map/TESTING 完全未含 AHK v2 测试），无法交叉验证；AGENTS.md L274 又称 run_all_tests.ahk「80 套件」，与 581 口径不明。
  - AGENTS.md 头部时间戳「Generated 2026-03-24 / Updated 2026-05-30」与正文「截至 2026-08-04 统计」矛盾。
- **根因**：多份文档独立修订，统计日期与计数口径未统一，无单一权威来源（single source of truth）。
- **修复建议**：确立 test-map.md 为唯一测试统计来源；在各文档中统一引用并注明口径（`#[test]`/`#[tokio::test]` 属性数、Test_ 方法数、断言数分别标注）；更新 AGENTS.md 头部的 Updated 时间戳。

### T7-06（Minor）· AGENTS.md 中 IpcMessage 结构示例字段不全

- **位置**：`AGENTS.md` L1220-1227（「数据结构约定 → Rust」）
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：示例把 `IpcMessage` 简化为仅 `seq/type/keys/data` 四个字段，实际 `asd-ipc-protocol/src/message.rs` 有 `id/type/seq/ack_seq/action/keys/delay/status/data` 九个字段。
- **根因**：示例为简化示意，未标注「简化」，与真实结构脱节。
- **修复建议**：补齐字段或加「（字段省略，完整定义见 message.rs）」注释。

### T7-07（Minor）· AGENTS.md AHK 四层模块表不完整

- **位置**：`AGENTS.md` L58-62（AHK v2 架构分层表）
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：
  - domain 表仅列 `interfaces/skill_group/skill_manager/mode_registry`，缺实际存在的 `joystick_input/joystick_executor/key_recorder/key_validator`。
  - infrastructure 表缺 `config_io/joy_sender/migration_logger`。
  - application 表缺 `backup_service`（knä 现存 `application/backup_service.ahk`）。
- **根因**：模块表未随功能新增而补录。
- **修复建议**：按目录实际内容补全三层模块清单。

### T7-08（Minor）· AGENTS.md「AHK 已知架构妥协」第三条实为 Rust 层面妥协，放错章节

- **位置**：`AGENTS.md` L72（「AHK 已知架构妥协」表第 3 条）
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：第 3 条「领域层依赖 IPC 协议层 | domain/traits.rs → asd-ipc-protocol」描述的是 Rust 领域 crate 的依赖，却被列在「AHK 已知架构妥协」章节中，且该主题与 L142「Rust/Tauri 已知架构妥协」第 1 条内容重叠。
- **根因**：编辑时表格串行，未按语言分层归类。
- **修复建议**：将该条移入「Rust/Tauri 已知架构妥协」，或在 AHK 表中明确标注「（Rust，误置于此）」。

### T7-09（Minor）· AGENTS.md tests/ 根目录文件计数描述前后不一致

- **位置**：`AGENTS.md` L251
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：称「22 个核心文件：… + 15 个核心测试文件（…）」，但括号内实际只列出 14 个测试文件；而 tests/ 根目录当前实际有 16 个 `test_*.ahk`（另含 `test_result_reporter.ahk`、`test_joy_hotkey_manager_ahu.ahk`）。`22 个核心文件` 总数虽对，但「15 个核心测试文件」的拆分与列举不吻合。
- **根因**：计数口径与清单未同步。
- **修复建议**：改为「16 个 test_*.ahk + 6 个框架/配置文件 = 22」，或直接引用目录列表。

### T7-10（Minor）· 应用数据目录/标识在文档间三处不一致

- **位置**：`AGENTS.md` L1267 vs `asd-tauri/src-tauri/tauri.conf.json` L5 vs `docs/developer-guide.md` L804-805
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：Tauri 日志目录，AGENTS.md 写 `%APPDATA%/com.asd.skillmanager/logs/`；tauri.conf.json 的 `identifier` 为 `com.asd.tauri`（默认 app data dir 应为 `com.asd.tauri`）；developer-guide 又写 `C:\Users\{username}\AppData\Roaming\asd-tauri\`。三方命名互不一致。
- **根因**：identifier 在 Tauri 迁移中变更过，文档未同步。
- **修复建议**：以 tauri.conf.json `identifier` 为准统一为 `com.asd.tauri`，或显式配置 `tauri::generate_context` 的 app data dir 并在文档中固定一处。

### T7-11（Minor）· AGENTS.md Rust Key Files / 目录表未登记新增模块与测试

- **位置**：`AGENTS.md` L37-47（Key Files 表）、L109-111（架构图 src-tauri 子树）
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：
  - asd-application 新增 `backup_service.rs`、`group_service.rs`、`recording_service.rs`、`time_format.rs` 与 `tests/`（backup/group/recording/cross_crate/e2e_dataflow/concurrency）未在 Key Files 表出现。
  - `src-tauri/src/infrastructure/shutdown.rs`、`src-tauri/src/tests/bridge_tests.rs`、`watchdog_integration_tests.rs`、`mod.rs` 未登记（表中仅列 ipc.rs/watchdog.rs/logging.rs 与 ipc_tests/config_compat_tests）。
  - AHK `application/backup_service.ahk`（项目根）同样未登记。
- **根因**：上述模块均在 test-map.md 与 code-review 之后新增，AGENTS.md 未回填。
- **修复建议**：将上述文件补入 Key Files 与架构子树表，保持与 `asd-tauri/docs/test-map.md` 一致。

### T7-12（Minor）· code-review-report-2026-08-03.md 对 AGENTS.md 的论断现已失效（报告自身过时）

- **位置**：`docs/code-review-report-2026-08-03.md` L15、L17、L39
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：该报告（审查日期 2026-08-03）称「Rust/Tauri 4-crate workspace」「AGENTS.md 的 IpcCommand 示例变体名全错、执行模式表少 3 项、workspace 成员数错误、Tauri commands 数量过期」「Cargo.toml 定义 test-manifest feature」。而当前 AGENTS.md 已修正（5 members / 13 变体 / 10 模式 / 34 commands），test-manifest feature 亦已移除。报告中的这些历史论断已不适用于当前代码库。
- **根因**：历史审查报告未标注「已修复/已过时」状态，容易误导。
- **修复建议**：作为历史快照保留，但在首页或条目上加「部分问题已于 2026-08-04 后修复」的勘误标注，避免被当作现状引用。

### T7-13（Minor）· test-map.md E2E 辅助/固件表未登记新增文件

- **位置**：`asd-tauri/docs/test-map.md` L175-182
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：E2E helpers 表仅列 tauri.js/config.js/key_receiver.js/report.js，未登记已新增的 `helpers/ahk_path.js`、`helpers/error_utils.js` 及 `helpers/__tests__/`（ahk_path.test.js、error_utils.test.js）。
- **根因**：新增辅助脚本未按维护规范（L206-210）到 test-map 登记。
- **修复建议**：补登记上述文件，路径、用途、引用方。

### T7-14（Minor）· E2E「modes（7）：7 种执行模式」与 10 种模式表述矛盾

- **位置**：`AGENTS.md` L356、`asd-tauri/docs/test-map.md` L168 vs `AGENTS.md` L1239-1252
- **维度**：文档完整性
- **严重级别**：Minor
- **描述**：E2E 章节称「modes.spec.js（7）：7 种执行模式」，而「支持的执行模式」表列 10 种（含 joystick_periodic/sequence/hold）。若 E2E 仅覆盖 7 个非 joystick 模式，应显式说明，否则易被误读为系统仅支持 7 种模式。
- **根因**：E2E 覆盖范围与系统能力未区分表述。
- **修复建议**：改为「7 种执行模式（E2E 覆盖）；系统共支持 10 种，joystick_* 3 种暂未纳入 E2E」。

---

## 三、修复优先级建议

1. **立即**：重写/归档 `docs/developer-guide.md`、`docs/migration-guide.md`（T7-01、T7-02），消除最易导致断链的过时结构描述。
2. **尽快**：统一测试统计口径（确立 test-map.md 为唯一来源），修正 test-map 明细与汇总、移除 TESTING.md 已失效的 test-manifest 命令（T7-03、T7-04、T7-05）。
3. **择机**：补齐 AGENTS.md 的模块清单、IpcMessage 示例、时间戳，统一 app data dir 标识，为 code-review-report 加勘误（T7-06 ~ T7-14）。