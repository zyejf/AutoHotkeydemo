# ASD 技能管理器 v4.0 —— 架构影响评估

| 项 | 值 |
|----|----|
| 评估人 | 阿奇（Archi）· 系统架构师 |
| 日期 | 2026-09-19 |
| 仓库 | `D:\1demo\AutoHotkeydemo`（主 worktree，分支 `main`，工作区干净） |
| 范围 | 工作流 1 第二段：分层/依赖边界、DDD 妥协白名单健康度、契约一致性、架构债、ADR 建议 |
| 性质 | **只读分析**。未修改任何业务代码、未改基线文件、未提交任何改动 |
| 评级 | 🟡 **有条件通过**（结构性健康，守护真实有效；扣分在"文档白名单失真"与"两处跨语言真值分裂"） |

---

## 0. 方法学与证据口径

本项目三次把"其实已有守护"误判成"没有守护"。本轮所有"有守护/无守护"的判断一律走**阳性对照**（故意造违规样本，看是否真的报错并报对东西），不靠读代码推断。

| # | 守护主张 | 阳性对照做法 | 结果 |
|---|---------|-------------|------|
| PC-1 | 分层逆向边有机器守护（TD-056） | 在 `/tmp/pc` 隔离沙箱（独立 git 仓库，与真仓零接触）建 `domain/ infrastructure/ presentation/` 三层，注入 `infrastructure/leak.ahk → #Include "../presentation/p.ahk"` | ✅ 闸门① 报 `新增逆向边（分层反向依赖）infrastructure/leak.ahk -> presentation/p.ahk —— 依赖方向必须 depth 大 → 小`，exit 1 |
| NC-1 | 同上，不得误报 | 删除 `leak.ahk` 后重跑 | ✅ 无"新增逆向边"输出 —— 判据有鉴别力，非永真式 |
| PC-2 | dev 依赖环必须保持 dev-only（AGENTS.md 明示风险） | 沙箱造 `asd-application ⇄ asd-test-harness` **生产**依赖（`[dependencies]` 而非 `[dev-dependencies]`） | ✅ `Rust 生产 crate 环: 1` **且** `生产依赖违规: 1`，并打印 `asd-application <-> asd-test-harness` |
| NC-2 | 真实仓库当前态 | 真仓跑 `check-graph-baseline.py` / `check-tech-debt.py` | ✅ 均 PASS（exit 0） |
| PC-3 | IPC 命令契约对齐（C8，TD-057） | 直接读脚本实时输出 | ✅ `[C8] … Rust 13 条 / AHK 13 条 通过：两侧命令集合完全一致` |

> PC-1/PC-2 的沙箱是 `/tmp/pc` 下的**独立 git 仓库**，只拷贝了 `.review-analysis/*.py` 与 `scripts/check-graph-baseline.py`，真仓全程 untouched。跑完后 `git status --porcelain` 仅显示其他成员新增的未跟踪文件，无本评估产生的改动。

---

## 1. 分层与依赖边界

### 1.1 Rust crate 依赖（实测，与白名单逐项比对）

`python .review-analysis/build_graph.py` 2026-09-19 重跑输出：

```
Rust 文件: 66 | use 边: 166 | crate 边: 11
Rust 生产 crate 环: 0 | 生产依赖违规: 0
```

生产依赖（`[dependencies]`）与 `ALLOWED_CRATE_DEPS`（`build_graph.py:316`）**逐项一致**：

| crate | 实测生产依赖 | 白名单 | 结论 |
|-------|------------|--------|------|
| `asd-ipc-protocol` | （无） | `set()` | ✅ |
| `asd-domain` | `asd-ipc-protocol` | `{asd-ipc-protocol}` | ✅ |
| `asd-application` | `asd-domain, asd-ipc-protocol` | 同 | ✅ |
| `asd-test-harness` | `asd-application, asd-domain, asd-ipc-protocol` | 同 | ✅ |
| `src-tauri` | `asd-application, asd-domain, asd-ipc-protocol` | 同（+ 允许 `asd-test-harness`） | ✅ |

dev 依赖：`asd-application → asd-test-harness`、`src-tauri → asd-test-harness`。与 `asd-test-harness → asd-application` 构成 **dev 环**，cargo 语义下合法，环检测按既定策略只用生产边，故 `rust_crate_cycles = 0`。

> ⚠️ AGENTS.md:136 把这条边标为"一旦挪进 `[dependencies]` 就是真正的生产环"。PC-2 已证明**这个风险是被双重守护的**：挪过去会同时触发 `rust_crate_cycles` 0→1（HARD_FAIL_GREATER）与 `rust_crate_violations` 0→1（`allowed_violations = []`，白名单外一律硬失败）。**该风险已闭环，不需要新闸门。**

### 1.2 AHK 分层（实测）

```
AHK 文件: 92 (生产 40 / 测试 23 / 工具 29 / 未归类 0)
AHK 边(总): 287 | 边(范围内): 282
AHK 生产->非生产 倒灌边: 0 | 未解析: 0
AHK 环: 0 | 孤点: 0 (其中生产孤点 0)
```

层间矩阵（depth：`infrastructure 0 → domain 1 → application 2 → presentation 3`，依赖须由大→小）：

| from → to | 边数 | 判定 |
|-----------|------|------|
| `infrastructure → domain` | **3** | ⚠️ 唯一逆向边（内层拉外层），见 §2 |
| `domain → infrastructure` | 6 | ✅ 合法方向 |
| `domain → domain` | 13 | ✅ |
| `application → {infrastructure, domain, application}` | 16 / 2 / 1 | ✅ |
| `presentation → {infrastructure, domain, application, presentation}` | 10 / 6 / 6 / 3 | ✅ |
| `tests → *` | 122（出边合计） | ✅ 豁免层 |
| `entry/executor/other → *` | 豁免 | ✅ |

**结论：环 0、孤点 0、生产→非生产倒灌 0、未解析 include 0；唯一方向异常是 3 条 `infrastructure → domain`，与 AGENTS.md 妥协表登记的 3 条一一对应、无第 4 条。** 分层守得住。

### 1.3 JS / 前端

```
JS 文件: 24 (src 5 / e2e 19 / 未归类 0)
JS import 边: 50（非内建值边） | 仅类型边: 0 | 内建边: 45 | 图内边: 36 | 环: 0
```

### 1.4 闸门实况

- `python scripts/check-graph-baseline.py --no-rebuild` → `[PASS] 闸门① 通过：无新增环、无白名单外依赖违规`（exit 0）
- `python scripts/check-tech-debt.py` → `[PASS] 技术债检查通过：无新增债、文档与代码一致`（exit 0）；其中 C8（IPC 契约）13↔13 通过、C13（台账自洽，64 行）通过、C1a 孤儿 0、C2 未接入 0

---

## 2. DDD 妥协白名单健康度（逐条核实，带 file:line）

### 2.1 妥协 #1 主项：domain → `infrastructure/error_system.ahk`

**白名单原文**（AGENTS.md:74）："仅允许 `domain/` 引用 `infrastructure/error_system.ahk` 的 `LogError` 方法。禁止领域层引用 `infrastructure/` 中的其他模块。"

实测 6 条 `domain → infrastructure` 边（图谱数据），**目标全部是 `error_system.ahk`，无一例外**：

| domain 文件 | `#Include` 行 | `ErrorSystem` 调用点 |
|---|---|---|
| `domain/mode_registry.ahk` | :15 | :28 :37 :51 :64 :74 :87 :99 :115 :164 :244 :294 :344 :393 :444 :461 :479 :541 |
| `domain/skill_manager.ahk` | :17 | :99 :112 :123 :141 :183 :221 :264 :311 :372 :463 :479 :516 :539 :555 :581 :595 :610 :643 :649 |
| `domain/skill_group.ahk` | :19 | :98 :414 :485 :700 :735 :757 :819 :849 |
| `domain/joystick_executor.ahk` | :17 | :73 :126 :157 :188 :224 :282 |
| `domain/key_recorder.ahk` | :15 | :55 :122 :146 |
| `domain/key_validator.ahk` | :15 | :52 :86 |

- 反向核查：`grep -rn "ErrorSystem\.[A-Za-z]*" domain/ | grep -v LogError` → **空**；`grep -rn "JSONError" domain/` → **空**。
- **判定：✅ 字面合规，未越界。** 领域层对基础设施层的接触面被精确收敛到"一个模块 + 一个方法"。

**但有两处白名单没写清的"软边界"，建议补登记（不算违规，算白名单精度不足）**：

1. **`LogError` 已被当作通用 logger 用**，第二参 `level` 传了 `"WARNING"` 而非仅 `"ERROR"`：
   - `domain/joystick_executor.ahk:188`、`domain/key_recorder.ahk:122`、`:146`、`domain/key_validator.ahk:86`、`domain/skill_manager.ahk:183`、`:595`、`:643`
   - `domain/skill_manager.ahk:123` 更直接用变量 `level` 传入。
   - 边界措辞是"仅允许 `LogError` 方法"，字面成立；但"只允许记录错误"的**意图**已被稀释成"领域层可以打 WARNING 日志"。
2. **传递依赖未被白名单覆盖**：`infrastructure/error_system.ahk:13-14` 自身 `#Include "utils.ahk"` + `#Include "json_serializer.ahk"`。领域层因此**实际拖入了整个日志/JSON 序列化栈**，而白名单只声明了直接引用。`domain → infrastructure` 在图上是 6 条边，语义上却是 6 × (error_system + utils + json_serializer)。

### 2.2 妥协 #1 附加项：`infrastructure/joy_hotkey_manager.ahk → domain/joystick_input.ahk`

白名单允许"引用 `JoystickInput` 类的纯工具函数（**无副作用、无状态**）"。

实测调用点（`joy_hotkey_manager.ahk`）：`:51 :63 :67 :81`（`IsButton`/`IsAxis`/`IsTrigger`/`IsPov`）、`:213 :214`（`PovToDirection`）、`:323 :338 :352`（`IsJoystickConnected`）。

- `IsButton/IsAxis/IsTrigger/IsPov/PovToDirection`（`domain/joystick_input.ahk:24/32/36/28/65`）确为纯字符串/数值计算 → ✅
- ⚠️ **`IsJoystickConnected()`（`domain/joystick_input.ahk:97`）内部是 `GetKeyState("1Joy1")` —— 查询设备实时状态，既非"无状态"也非"无外部依赖"。** 它是只读查询（无副作用），但与白名单"无副作用、**无状态**"的措辞不符，属**软越界**。
- 建议：要么把白名单措辞改为"纯函数（仅依赖入参）+ 只读设备查询"，要么把 `IsJoystickConnected` / `GetConnectedJoysticks` 从 `JoystickInput` 挪到基础设施层。前者成本更低。

### 2.3 妥协 #1 附加项：`infrastructure/joy_sender.ahk → domain/interfaces.ahk`

- `infrastructure/joy_sender.ahk:17` `#Include "../domain/interfaces.ahk"`，`:19` `class JoySender extends IJoySender {`
- 全文件无其它 `IJoySender` 引用，纯类型继承，无副作用无状态。
- **判定：✅ 合规**，是教科书式的依赖倒置。

### 2.4 妥协 #1 附加项：`infrastructure/config_validator.ahk → domain/joystick_input.ahk`

- `infrastructure/config_validator.ahk:16` `#Include "../domain/joystick_input.ahk"`（:15 有备案注释）
- `:182` `valid := isJoystick ? JoystickInput.IsJoystickKey(keyStr) : ConfigValidator._IsValidKeyName(keyStr)`
- 用的是纯静态 `IsJoystickKey`（`domain/joystick_input.ahk:19`）。**✅ 合规。**
- ⚠️ **行号漂移**：AGENTS.md:74 登记为"`config_validator.ahk:167`"，实际调用在 **`:182`**；167 行是 `_validKeysMap` 的构建代码，与该妥协无关。属 F 文档漂移（同 §3.4 的 Config 示例漂移，同一类问题）。

### 2.5 妥协 #2：`BackupCore` 隐式依赖 —— ❌ **条目已失真，建议重写或注销**

白名单原文（AGENTS.md:75）：

> 影响文件 `application/config_service.ahk` → `infrastructure/backup_core.ahk`；"应用层通过**全局 `BackupCore` 类名隐式**引用基础设施层模块。应通过显式 `#Include` 或接口抽象化。"；约束边界："`ConfigService` 内部**仅通过 `BackupCore.CreateBackup()`** 静态方法调用，不直接访问其内部状态。"

实测三条与登记不符：

| # | 登记 | 实测 | 性质 |
|---|------|------|------|
| a | "**隐式**依赖，应改为显式 `#Include`" | `application/config_service.ahk:19` **已有** `#Include "../infrastructure/backup_core.ahk"` | **妥协已被消解，但白名单条目未注销** —— 描述停留在修复前 |
| b | "仅 `CreateBackup()`" | `application/group_service.ahk:96`、`:174`、`:196`、`:297` 调 **`BackupCore.RecordConfigChange()`**；`:164` 调 `CreateBackup()` | **方法面越界**：白名单只写了 `CreateBackup` |
| c | "`ConfigService` 内部" | 除 `config_service.ahk:170` 外，**`group_service.ahk`（5 处）与 `backup_service.ahk`（5 处）也在用** —— 两个文件都不在白名单登记的"影响文件"里 | **文件面越界** |
| d | "不直接访问其内部状态" | `application/backup_service.ahk:20` `get => BackupCore.backupDir` —— **直接读静态属性** | 明令禁止项被触碰 |

**重要定性**：`application(2) → infrastructure(0)` 是**合法方向**，所以以上**都不是分层违规**，闸门①也不会（也不应）拦。问题是**白名单作为"架构权威文档"已经不能描述现状** —— 它既过严（a、b、d）又过窄（c）。这正是 AGENTS.md 自称"矛盾必须当场修正，不允许两边都留着"（:1441）的那类矛盾。

补充：`application/backup_service.ahk:4-6` 的注释写着"封装 BackupCore 基础设施层 API，供表现层调用 / 修复 I1: 表现层不应直接调用 BackupCore" —— 这是一处**有意为之的封装**，行为合理，只是没进白名单。所以修法应当是**更新白名单**，不是改代码。

### 2.6 白名单健康度小结

| 条目 | 是否越界 | 结论 |
|------|---------|------|
| #1 主项 domain→error_system（6 文件） | 否 | ✅ 合规；建议补"level 用法"与"传递 include"两处精度 |
| #1 附加 joy_hotkey_manager→joystick_input | **软越界**（`IsJoystickConnected` 查设备状态） | 🟡 改措辞或挪方法 |
| #1 附加 joy_sender→interfaces | 否 | ✅ 合规 |
| #1 附加 config_validator→joystick_input | 否（仅行号漂移） | 🟡 修 AGENTS.md 行号 167→182 |
| #2 BackupCore | **是**（条目整体失真：a/b/c/d） | 🔴 需重写或注销 |

---

## 3. 契约一致性

### 3.1 IPC 命令名契约（Rust ↔ AHK）—— ✅ 已守护

- Rust `IpcCommand` 13 variants（`#[serde(rename = "toggle_group")]` 等）；AHK 侧 `executor.ahk:61-81` 分发 11 条 + `ipc_client.ahk:725/727/748/751` 处理 `ping`/`shutdown`。
- **守护**：`scripts/check-tech-debt.py` 的 **C8**（TD-057，2026-09-18 落地），双向校验，硬失败。实时输出：`Rust 13 条 / AHK 13 条 通过：两侧命令集合完全一致`。
- 这条曾经的"纯属运气"（TD-057 原话）现在有机器兜底了。

### 3.2 配置契约（Rust ↔ config.json）—— ✅ 字段对齐，且有真实对拍

- Rust `Config`（`asd-domain/src/config.rs:24`）：`control_hotkeys / group_settings / hold_settings / last_modified / version`
- 真实 `config.json` 顶层键：`CONTROL_HOTKEYS / GroupSettings / HoldSettings / lastModified / version` —— **逐字段对齐**（含 serde rename 的大小写约定）
- `GroupConfig`（`config.rs:103`）：`hotkey / key_press_duration / name / mode / hold_keys / hold_mode / hold_pattern / hold_triggers / mode_data`，与 config.json 分组样本（含 `groups` 子组、`pressKeys`/`intervals`/`delays`）一致
- **守护**：`src-tauri/src/tests/config_compat_tests.rs:6-7` 用 `include_str!("../../config.json")` 直接吃**真实配置**做反序列化 + **序列化往返一致性**（12 个用例），不是拿玩具 fixture 自娱。

**一处卫生问题**：`config.json` 前 6 字节是 `EF BB BF EF BB BF` —— **双重 UTF-8 BOM**。Rust 侧已守护：`config_repository.rs:172`、`:218`、`:243` 用 `trim_start_matches('\u{feff}')`（`trim_start_matches` 会剥掉**所有**连续 BOM，不是只剥一个），测试侧 `config_compat_tests.rs:7` 同样处理。**判定：已守护，无需处理**，但双重 BOM 说明某处写入路径重复加了 BOM，值得单独查一次写盘链路。

### 3.3 热键表示契约 —— 🟡 现状对齐，但**多键语义无约束**

- Rust：`IpcMessage::hotkey_event`（`message.rs:129`）→ `keys: Some(vec![hotkey])`，**单元素**
- AHK：`IpcClient.SendHotkeyEvent(keys*)`（`ipc_client.ahk:485`）→ **可变参数**
- 唯一生产调用点 `hotkey_hook.ahk:129`：`SendHotkeyEvent(normalizedKey)` —— 单键

即：**AHK 的 API 形状允许传多个键，Rust 的契约只定义了单键，两边没有东西钉住这个约定。** 今天恰好一致，属于 TD-057 说的同一类"纯属运气"，但**没有对应守护**（C8 只管命令名，不管 payload 形状）。

### 3.4 ⚠️ AGENTS.md 的 Rust 数据结构示例已过期

AGENTS.md:1327-1333 给的示例：

```rust
pub struct Config {
    pub hotkey: String,
    pub mode: String,
    pub groups: IndexMap<String, GroupConfig>,
}
```

实际（`config.rs:24`）是 `control_hotkeys / group_settings / hold_settings / last_modified / version` —— **字段名、嵌套层级全不对**。

按 AGENTS.md:1432 的权威边界表，`AGENTS.md` 是"架构决策、分层规则、妥协白名单、关键文件清单"的唯一权威。架构权威文档里的核心数据结构与代码不符，而新人/AI Agent 恰恰是拿这段去理解配置的。属 **F 文档漂移**，与 §2.4 的行号漂移、§2.5 的条目失真同源：**AGENTS.md 的"代码事实类"内容没有被任何闸门校验**（C3b 只查"硬写的测试数字"，不查结构示例）。

### 3.5 `HotkeyMerger` 合并语义 —— 🟡 有架构级风险

代码：`asd-ipc-protocol/src/hotkey_merger.rs`；接线：`src-tauri/src/infrastructure/ipc.rs:64`、`:107`、`:674`、`:714`、`:733`（**已接线，非死代码**）。

| # | 风险 | 位置 | 说明 |
|---|------|------|------|
| R1 | **同键 last-write-wins，静默吞事件** | `:37` `self.buffer.insert(hotkey, msg)` | 默认窗口 100 ms（`:4`）。本系统热键是 **toggle 语义**，100 ms 内同一热键触发 2 次只留最后 1 条 → 前端只收到 1 次 → **快速连按/双击丢触发**。丢弃**无日志、无计数、不可观测** |
| R2 | **身份键只取 `keys.first()`** | `:28-33` | 与 §3.3 联动：一旦 AHK 侧发 `SendHotkeyEvent("Ctrl","F1")`，身份退化为 `"Ctrl"`，`Ctrl+F1` 与 `Ctrl+F2` 会在缓冲区互相覆盖 |
| R3 | **同批多键顺序不确定** | `:47` `self.buffer.drain()` | `HashMap` 迭代序随机。当前每批通常单键所以没暴露；多键同批时前端收序随机 |
| R4 | **`flush()` 无条件重置 `last_flush`** | `:46` | buffer 为空时调用也会重置计时器；当前调用点都先判 `should_flush()`，暂无实害，但接口契约不安全 |

**这不是 bug，是语义选择没被记录**：把它当"上报节流"是对的（避免高频热键刷爆前端），但当"事件合并"就是错的（toggle 需要每次都到达）。**台账里 `HotkeyMerger` 零命中**（`grep -c HotkeyMerger docs/tech-debt-register.md` → 0），说明这个取舍从未被显式决策过。建议：要么在代码注释 + ADR 里钉死"这是节流、允许丢中间态"，要么改成计数合并（`{hotkey: {count, latest}}`）让丢弃可观测。

### 3.6 IPC 直连例外边界 —— ✅ 未越界

AGENTS.md:248 的例外只允许 `src-tauri/src/lib.rs` 的 IPC 生命周期函数直连 `IpcManager`。实测 `grep -rn "IpcManager" src-tauri/src/commands/*.rs` → **空**；`lib.rs` 内命中 `:15 :25 :47 :133 :156 :166 :240 :243 :246`，均为生命周期/回调接线。**合规。**

### 3.7 双栈配置不共享（重要架构事实）

- Tauri 运行时：`lib.rs:679` `app.path().app_data_dir()` → `<appdata>/config.json`
- AHK v2 独立模式：`application/config_service.ahk:26` / `infrastructure/backup_core.ahk:25` → cwd 相对 `config.json`

**两套栈在运行时读的是两个不同的配置文件**，只共享 *schema*（靠 root `config.json` 当 fixture 对拍）。这是"v3.0 保留为独立运行模式"的直接后果，也是 §5 ADR-001 的核心议题。

---

## 4. 架构债识别（按"影响面 × 重构可行性"排序）

### 债 A1 —— 🔴 领域校验规则双真值分裂（Rust + AHK 各一份）

- **事实**：`asd-tauri/crates/asd-domain/src/validator.rs` **2626 行**（`ConfigValidator`）与 `infrastructure/config_validator.ahk` **759 行**（同为 `ConfigValidator`），是**同一套领域校验规则的两份独立实现**，跨语言、无共享规约、无对拍测试。
- **影响面**：配置是两套栈唯一的共享资产（§3.7 只共享 schema）。任一侧改规则而另一侧没跟，用户会在"AHK 独立模式能存、Tauri 模式报错"（或反之）之间横跳，且**没有任何门禁会发现**。台账中未登记此类债（`grep "双实现|两套|双份" docs/tech-debt-register.md` → 0 命中）。
- **重构方向**（三选一，按成本升序）：
  1. **共享规约 + 对拍测试**：把校验规则抽成一份机器可读的规则表（JSON/YAML），两侧各自解释；新增一组跨语言对拍测试（同一份配置样本，两侧结论必须一致）。成本最低，能立刻让分叉可见。
  2. **单一真值 + 代码生成**：规则表 → 生成 Rust 与 AHK 两侧代码。彻底消除分叉，需引入生成器。
  3. **单一实现**：让 AHK 侧退化（v3.0 栈下线时自然消失）。依赖 ADR-001 的结论。
- **建议**：先做 1（把"不可见"变成"可见"），再据 ADR-001 决定 2 还是 3。

### 债 A2 —— 🟡 `HotkeyMerger` 合并语义未决策、未登记

- 见 §3.5（R1–R4）。**影响面**：所有热键触发路径（Rust 收包 → 前端）的可靠性；**症状**：偶发"按了没反应"，且日志里查不到。
- **重构方向**：① 代码注释 + ADR 钉死语义（"节流，允许丢中间态"）；② 或改计数合并 `{hotkey: {count, latest}}` 并在丢弃时 `tracing::debug!` 留痕；③ 身份键从 `keys.first()` 改为 `keys.join("+")`，同时 C8 扩展一条"hotkey payload 契约"钉住单键约定。

### 债 A3 —— 🟡 双 UI / 双运行时栈长期并存，去留未决策

- **事实**：AHK v2 栈（`presentation/webview2_manager.ahk` 1296 行 + `group_editor.ahk` 1313 行 + `app_ui.html`，WebView2）与 Tauri 栈（`src/main.js` 1318 行 + 34 个 command）**两套表现层并存**；两者读不同配置文件（§3.7）、各有各的校验器（债 A1）。
- **影响面**：任何"配置/校验/热键"类需求都要改两处；测试预算 ×2；认知负担 ×2。
- **重构方向**：形成 ADR-001，明确 v3.0 AHK 栈是"维护模式（只修 bug）"还是"计划下线"。若下线，债 A1 的解法直接走方案 3。

### 债 A4 —— 🟡 白名单与代码事实失真（AGENTS.md）

- 三条实证：§2.5（妥协 #2 条目 a/b/c/d 全面失真）、§2.4（行号 167→182）、§3.4（Config 结构示例过期）。
- **影响面**：AGENTS.md 自称架构唯一权威（:1432），新人/AI Agent 按它行事会写出与现状不符的代码或做出错误的架构判断。**它比代码注释失真更危险，因为它是给决策用的。**
- **重构方向**：① 立即修三处；② 给 `scripts/check-tech-debt.py` 加一条 **C14：AGENTS.md 代码事实校验** —— 校验妥协表里登记的 `file:line` 是否仍存在、登记的符号/方法是否仍被该文件引用、Config 结构示例字段是否与 `config.rs` 一致。这是把"文档漂移"从人工核对变成机器门禁，与既有 C3/C4/C8 同类（守规则、不棘轮）。

### 债 A5 —— 🟡 上帝文件集中在 domain 与基础设施

生产代码行数 TOP（`git ls-files` 口径，排除 tests/tools/lib/docs）：

| 文件 | 行数 | 备注 |
|------|------|------|
| `asd-domain/src/validator.rs` | **2626** | 纯逻辑 crate 里的巨型校验器 |
| `asd-application/src/state.rs` | 1639 | `AppState` |
| `src-tauri/src/infrastructure/watchdog.rs` | 1572 | |
| `src-tauri/src/infrastructure/ipc.rs` | 1524 | |
| `asd-tauri/src/main.js` | 1318 | 前端（TD-005 已记：仍无单测） |
| `presentation/group_editor.ahk` | 1313 | AHK 表现层 |
| `presentation/webview2_manager.ahk` | 1296 | AHK 表现层 |
| `asd-domain/src/config.rs` | 1147 | |

- **最值得修的是 `validator.rs`**：2626 行校验逻辑塞在 `asd-domain`，把领域层变成了"校验层"。台账显示已做过一次拆分（`validate_mode_data` 304 行 → 分派器 + 10 个 `validate_*`），说明方向正确但还没做完。
- **重构方向**：按 mode 切成 `validator/{periodic,sequence,hybrid,hold,joystick}.rs`，`validator.rs` 只留分派；`config.rs` 按 `Config/GroupConfig/ModeData` 拆。两者都是纯逻辑 crate，拆分可被现有 96.57% 覆盖率与 Miri 直接兜住，风险低。

### 债 A6 —— 🟢 已闭环，仅作记录（避免重复投入）

dev 依赖环（PC-2 已证明双守护）、IPC 命令契约（C8）、逆向边（TD-056 + PC-1）、config.json BOM（已剥离）、IPC 直连例外（§3.6）—— 均已守护，**不需要新增闸门**。

---

## 5. ADR 建议

现有仓库**无 ADR 目录**（`find . -iname "ADR*"` 空；`docs/` 下无 adr/decision 目录）。建议新建 `docs/adr/`，编号从 001 起。以下三条是我认为**最该被写成决策记录**的议题——它们的共同点是：已经被隐式决定了，但没人写下代价。

### ADR-001：v3.0 AHK 独立栈的定位（维护 / 下线 / 双栈长期并存）

- **状态**：Proposed
- **背景**：AHK v2 四层栈（92 个 .ahk 中的 40 个生产文件）与 Rust/Tauri 栈并存，两套表现层、两套配置实例、两套校验器（债 A1/A3）。AGENTS.md:9 只写了"作为独立运行模式保留"，没写保留多久、保留到什么程度。
- **选项**：
  | 选项 | 复杂度 | 成本 | 收益 |
  |------|-------|------|------|
  | A 双栈长期并存，规则双写 | High | 每需求 ×2 | 保留 AHK 独立可运行能力 |
  | B v3.0 转维护模式（只修 P0，不加功能） | Low | 低 | 立即止血，需求只改 Rust 侧 |
  | C v3.0 下线（AHK 只留 `ahk_executor/` 子进程） | Med | 一次性删 ~40 文件 | 消除债 A1/A3 的根因 |
- **决策建议**：**B**（立即生效、零风险），并在 ADR 里写明"触发 C 的条件"（例如：连续两个迭代无 AHK 独立模式反馈）。
- **影响**：选 B 后，债 A1 的解法收敛到方案 1（共享规约 + 对拍），不再追求两侧功能对等。

### ADR-002：热键事件的合并语义（节流 vs 完整事件流）

- **状态**：Proposed
- **背景**：`HotkeyMerger`（100 ms 窗口、同键 last-write-wins）把多个热键事件合并成一条上报。这是**节流**语义，会静默丢弃中间态；但本系统热键是 **toggle** 语义，丢弃 = 状态机丢步。
- **选项**：
  | 选项 | 复杂度 | 代价 | 适用 |
  |------|-------|------|------|
  | A 维持节流，显式记录代价 | Low | 高频场景下偶发丢触发 | UI 只做状态展示 |
  | B 计数合并（`{count, latest}`） | Low | 消息体多一个字段 | 需要知道"按了几次" |
  | C 不合并，全量上报 + 前端限流 | Med | 前端压力上移 | toggle 语义必须每一步都到达 |
- **决策建议**：先明确"UI 需要的是**状态**还是**事件流**"。若是状态 → A（并补日志）；若是事件流 → B 或 C。
- **影响**：决定 `hotkey_merger.rs` 是留、改还是删；连带决定 §3.3 的 payload 契约怎么钉。

### ADR-003：`asd-domain → asd-ipc-protocol` 的领域层/协议层耦合

- **状态**：Proposed（AGENTS.md 妥协表已登记为"已知架构妥协 #1"，但**没有 ADR**）
- **背景**：`asd-domain/Cargo.toml` 依赖 `asd-ipc-protocol`，`asd-domain/src/traits.rs:301` 行规模里的 `IpcSender` trait 直接以 `IpcCommand/IpcMessage` 为参数类型。AGENTS.md:154 自己写了"未来应将其迁移至应用层，领域层定义纯领域命令接口"——**这是一个已被识别但从未排期的架构债**。
- **选项**：
  | 选项 | 复杂度 | 成本 | 风险 |
  |------|-------|------|------|
  | A 维持现状（登记为妥协，带复审期） | — | 0 | 领域模型被传输协议污染，协议变更会穿透到领域层 |
  | B 领域层定义 `DomainCommand`，应用层做 `DomainCommand → IpcCommand` 映射 | Med | 新增一个映射层 | 映射层本身可能变成新的上帝模块 |
  | C 把 `traits.rs` 的 IPC 相关 trait 下沉到 `asd-ipc-protocol` | Low | 低 | 反而固化了耦合，只是挪位置 |
- **决策建议**：**A + 明确复审触发条件**（首次出现"因 IPC 协议变更而改 domain"时，强制转 B）。理由：当前 0 违规、0 环，为一条尚未造成实际成本的洁癖去动 5-crate 的 trait 边界，投入产出不划算——但必须写下"什么时候重新审视"，否则它会在无人注意时固化。
- **影响**：B 一旦执行，需同步改 `ALLOWED_CRATE_DEPS["asd-domain"]`（目前 `{asd-ipc-protocol}`）与基线。

---

## 6. 评级与建议动作

### 评级：🟡 有条件通过

**通过的部分（有实测证据）**：
- 分层守得住：AHK 环 0 / 孤点 0 / 倒灌 0 / 未解析 0；Rust 生产 crate 环 0 / 依赖违规 0；JS 环 0
- 白名单外的逆向边**一条都没有**（3 条全部逐条授权），且**有真实守护**（PC-1/NC-1 实证，非永真式）
- 命令契约、配置契约均有机器守护且当前通过（C8 13↔13；`config_compat_tests` 吃真实 config.json）
- 妥协 #1 主项（6 个 domain 文件）**字面完全合规**，接触面收敛到"1 模块 1 方法"
- dev 依赖环风险**已双守护**（PC-2）

**有条件（必须先处理的）**：
1. 🔴 妥协 #2（`BackupCore`）白名单条目整体失真 —— 修文档，不改代码
2. 🔴 债 A1 双校验器真值分裂 —— 先加对拍测试让分叉可见
3. 🟡 债 A2 HotkeyMerger 语义未决策 —— 走 ADR-002
4. 🟡 债 A4 AGENTS.md 代码事实失真 —— 修三处 + 建议加 C14 机器校验
5. 🟡 债 A3 双栈去留 —— 走 ADR-001

### 建议动作（按优先级）

| P | 动作 | 预期成本 |
|---|------|---------|
| P0 | 重写 AGENTS.md 妥协 #2 条目（现状：显式 include 已存在；登记 `group_service`/`backup_service` 两个文件 + `RecordConfigChange`/`backupDir` 两个用法） | 10 min，纯文档 |
| P0 | 修 AGENTS.md 行号 167→182、Rust Config 结构示例 | 10 min，纯文档 |
| P1 | 立 ADR-001 / ADR-002 / ADR-003（新建 `docs/adr/`） | 半天 |
| P1 | 补一组 Rust↔AHK 校验规则对拍测试（债 A1 方案 1 的第一步） | 1~2 天 |
| P2 | `hotkey_merger.rs` 身份键改 `keys.join("+")` + 丢弃留痕（债 A2） | 半天 |
| P2 | 给 `check-tech-debt.py` 加 C14：AGENTS.md 代码事实校验（债 A4 治本） | 1 天 |
| P3 | `validator.rs` 按 mode 拆分、`config.rs` 拆分（债 A5） | 2~3 天 |

---

## 附录 A：本评估用到的可复现命令

```bash
# 图谱（产物已被还原，未覆盖仓库既有 graph-raw.json / graph-baseline.json）
python .review-analysis/build_graph.py

# 闸门①（真实仓库 → PASS）
python scripts/check-graph-baseline.py --no-rebuild

# 技术债检查（含 C8 IPC 契约 → PASS）
python scripts/check-tech-debt.py

# 白名单越界核实
grep -rn "ErrorSystem\.[A-Za-z]*" domain/ | grep -v "ErrorSystem.LogError"   # → 空
grep -rn "JSONError" domain/                                                 # → 空
grep -n "JoystickInput" infrastructure/joy_hotkey_manager.ahk
grep -n "BackupCore" application/*.ahk
```

## 附录 B：阳性对照沙箱（`/tmp/pc`，独立 git 仓库，与真仓零接触）

```
PC-1  注入 infrastructure/leak.ahk -> presentation/p.ahk
      → 闸门①: "新增逆向边（分层反向依赖）infrastructure/leak.ahk -> presentation/p.ahk …"，exit 1
NC-1  移除 leak.ahk → 无"新增逆向边"输出
PC-2  asd-application ⇄ asd-test-harness 改为 [dependencies]
      → "Rust 生产 crate 环: 1 | 生产依赖违规: 1"，并打印环
NC-2  真实仓库 → 闸门① PASS / 技术债检查 PASS
```

---

*本报告为只读分析产物。评估过程中未修改任何业务代码、未改动 `.review-analysis/graph-baseline.json`，`graph-raw.json` 在重跑后已还原为原始内容；`git status --porcelain` 显示工作区除其他成员新增文件外无改动。*
