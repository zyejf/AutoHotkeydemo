# A1 · 跨语言配置校验收敛决策备忘录

**日期:** 2026-09-19
**作者:** 阿奇（系统架构师）
**状态:** **待人类负责人拍板**（本文档不执行任何改动）
**关联:** 技术债 TD-067（对拍装置）、ADR-001（v3.0 AHK 栈转维护模式）
**范围:** 7 处已实跑确认的分歧。第 8 处「热键长度」已由另一名成员实跑定论：**在本装置的 AHK 口径（`ConfigValidator.Validate`）下不构成分歧**，已固化为夹具用例 `c17_hotkey_len20_alnum_both_legal`（两侧均合法），故本稿仍为 7 处裁决（见 §5 附注 1）。

> 本文只出决策依据与建议，**不改任何代码、夹具、台账**。所有结论附源码行号或实跑输出，便于复核。

---

## 0. 先回答派单的核心问题：「以 Rust 为准」在这里到底是什么意思

### 0.1 结论：**(a) 和 (b) 作为总口径都是错的；正确读法是 (c) 的一个强化版**

| 读法 | 是否采纳 | 理由 |
|---|:--:|---|
| (a) 把 Rust 的规则改成与 AHK 一致（一律采纳更严的一侧） | ❌ | 7 处里有 1 处（c13）**更严的一侧是错的**——AHK 的正则连 AHK 自己的运行时都不认（见 §2 c13 的实跑输出）。一律采纳更严会把一个 bug 固化成契约。 |
| (b) 把 AHK 放宽到与 Rust 一致（一律采纳更宽的一侧） | ❌ | 7 处里有 2 处（c11/c12）放宽后**用户会存下"能保存、但不按预期工作"的配置**，正是派单里担心的失败模式。 |
| (c) 保持两侧各自规则，UI 以 Rust 为准做前置校验、AHK 保留兜底 | ⚠️ 部分 | 方向对，但**表述不完整**：它没有回答"Rust 现在的规则对不对"。7 处里 **4 处需要反过来把 Rust 收紧**（c11/c12 收紧，c14/c15 维持现状但改标注），**1 处需要放宽 AHK**（c13），**2 处需要把 AHK 补严**（c09/c10）。 |

**推荐口径（一句话）：**

> **真值不在"某一侧"，而在"运行时实际行为"。** 两侧都是守护者，都应服从运行时。
> 判据是：**哪一侧的规则与「AHK v4 执行器的真实运行时行为 + v4 用户可见后果」一致，就以哪一侧为准。**
> ADR-001 的「配置真值以 Tauri（Rust）侧为准」约束的是**配置存放在哪、由谁做前置校验**，不是**规则内容以谁为准**——这两件事在本轮被混为一谈了，这是 A1 真正的决策点。

### 0.2 一处必须更正的前提（重要）

派单里的表述是：

> 「AHK 执行器 `asd-tauri/src-tauri/ahk_executor/` 在运行期**仍然可能按自己的规则拒收**这些配置」

**实测结论：v4 的 AHK 执行器没有任何配置校验，它不会"拒收"任何东西。**

证据：

- `asd-tauri/src-tauri/ahk_executor/` 只有 5 个 `.ahk`（`executor.ahk` / `sender.ahk` / `joystick.ahk` / `hotkey_hook.ahk` / `ipc_client.ahk` + `high_res_clock.ahk`），**不含** `infrastructure/config_validator.ahk`，全目录 grep `ConfigValidator|Validate` **零命中**。
- `executor.ahk:115-126` `_HandleRegisterHotkey`：**只**拒 `hotkeyStr = ""`（:119-122），无格式校验、无查重，其余直接 `HotkeyHook.Register(hotkeyStr, groupId)`。
- `hotkey_hook.ahk:55` `Hotkey(normalizedKey, (*) => ..., "On")` —— 键名原样交给 AHK 原生 `Hotkey()`，无白名单。

**那风险消失了吗？没有，而且机制更隐蔽——执行器不"拒收"，它"静默夹紧 / 静默忽略"：**

| 场景 | 执行器真实行为 | 行号 |
|---|---|---|
| interval/delay < 10ms | **静默夹到 10ms**（`MIN_INTERVAL_US := 10000`） | `sender.ahk:53`、`_IntervalUsOf` `sender.ahk:422-426`、`_DelayUsOf` `:429-433` |
| interval 超大（>24h） | **无上界**，原样 `Round(interval*1000)` µs 去等 | `sender.ahk:424` |
| `joystick_hold` 的 `holdDuration` | **完全不读**（`Joystick.StartHold` 签名里没有这个参数） | `executor.ahk:332-335`、`joystick.ahk:189` |
| `HoldSettings.*` | **完全不读**（执行器内零命中） | `ahk_executor/` 全目录 |

**所以派单担心的失败模式成立，但因果链要改写：**

> 不是「放宽 AHK → 执行器拒收 → 保存成功但运行失败」，
> 而是「放宽 AHK → v3 栈能存下 → v4 运行期被**静默夹紧 / 静默忽略 / 长时间挂起** → 用户完全无反馈」。

**这反而强化了同一个结论：c11/c12 绝不能放宽 AHK，而且应当把 Rust 收紧到与之一致。**

### 0.3 一个被忽略的事实：AHK 校验器在 v4 里根本没有执行机会

`infrastructure/config_validator.ahk` 属于 **v3 根栈**，v4 执行器不加载它。它的调用点全在 v3 栈内：`application/config_service.ahk:62/92/179`、`application/group_service.ahk:222`（`Validate`）、`:81/113`（`ValidateGroupOnly`）。

推论：**在 v4 产品语境下，AHK 校验器既不拦你也不放你，它是 v3 独立运行模式自己的守门人。** 因此：

- 改 AHK 校验器 → **只影响 v3 独立运行模式**（ADR-001 已冻结其新功能，影响面有限且可控）；
- 改 Rust 校验器 → **影响 v4 的保存/导入**，是真正需要谨慎的一侧。

这个不对称直接决定了「哪一侧改起来更安全」，也决定了下面每一行的"改这一侧"选择。

---

## 1. 逐处裁决表

> 「建议以哪侧为准」一列不是"选边"，是"**这一侧的规则更贴近运行时真相**"。
> 「用户可见变化」一律指**改这一侧之后**的变化。

| id | 分歧一句话 | 建议以哪侧为准 | 理由（行号依据） | 改这一侧后**用户可见的变化** | 是否需同步改测试/夹具 |
|---|---|---|---|---|:--:|
| **c09** | 两个分组同热键 F1：Rust ERROR / AHK 无 ERROR | **以 Rust 为准**（把 AHK 补严） | 运行时会**静默丢弃**第二个：`state.rs:511-522` `register_hotkey` 命中已占用即 `return Ok(Some(existing))`、**不注册**；v4 执行器侧 `executor.ahk:115-126` 也不查重，重复键交给 `Hotkey()` 后者覆盖前者。即"存得下、其中一个分组永不响应"，且**无任何提示**。AHK 侧并非没有查重代码，而是写在**从未被调用**的 `ValidateGroupHotkeys`（`config_validator.ahk:63`，查重在 `:85-86`）——全仓 grep 该函数**只有定义、零调用点**；真正会被调用的 `Validate()`（`:40-61`）不查重 | **v3 栈**：保存含重复热键的配置由「能存（其中一个分组静默失效）」变为「被拒并报出与哪个分组重复」。**v4/Rust 侧不变** | **是**。c09 由「已知分歧」移入「契约核心」（两侧均判非法）；AHK 侧若有断言「`Validate()` 不查重」的用例需改写 |
| **c10** | 控制热键 `emergency` 为空串：Rust ERROR / AHK WARNING | **以 Rust 为准**（AHK 由 WARNING 升 ERROR） | ① Rust 侧 `ControlHotkeys` 五个字段都是**非 `Option` 的 `String`**（`config.rs:76-86`），**缺失即反序列化失败**，比 ERROR 更硬——"空串"与"缺失"在同一契约里理应同样被拒，否则口径自相矛盾；② `validator.rs:397-408` 空值即 ERROR，与之配套。**另需说明**：v4 目前**没有**把控制热键绑定到实际热键（`src-tauri/src` 里 `config.control_hotkeys` 无功能消费方，Tauri 命令 `toggle_all`/`emergency_release` 由 UI 直接调用，`lib.rs:807/822/823`），v3 侧唯一消费方是设置编辑器（`presentation/gui_manager.ahk:351/411/450`、`webview2_manager.ahk:432/565-571`）。故**当前无功能后果**，但这是"提前把契约钉对"，成本近乎零 | **v3 栈**：保存「控制热键为空」的配置由「可存 + 一条 WARNING」变为「被拒」。**v4/Rust 侧不变** | **是**。c10 移入「契约核心」（两侧均判非法） |
| **c11** | intervals/delays 含 5ms：Rust 合法（只禁 0）/ AHK ERROR（最小 10ms） | **以 AHK 为准**（把 Rust 收紧） | 不是"AHK 更严所以选它"，而是**运行时会静默夹紧**：`sender.ahk:53` `MIN_INTERVAL_US := 10000`；`_IntervalUsOf`（`:422-426`）与 `_DelayUsOf`（`:429-433`）对小于 10ms 的值**一律夹到 10ms，无任何反馈**。Rust 侧 `check_keys_and_timings`（`validator.rs:94-120`）只禁 `0`（`:117` `timings.contains(&0)`），**没有 10ms 下限**——于是用户写 5ms、保存成功、实际按 10ms 跑，这正是"保存成功但不按预期工作" | **v4（Tauri UI）**：保存含 <10ms 间隔/延迟的配置由「成功」变为「失败 + 文案『最小 10ms』」。**AHK 侧不变**。⚠️ 若存在历史配置含 <10ms，保存时会被拦——建议同步评估是否需要在导入路径给一次性的"自动夹紧到 10ms + 提示" | **是**。c11 移入「契约核心」（两侧均判非法）；Rust 侧若有断言「`[50,5]` 合法」的内联用例需改；夹具 `rust_has_error` false→true |
| **c12** | intervals=90000000ms（>24h）：Rust 合法（仅 WARNING，无上界）/ AHK ERROR | **以 AHK 为准**（把 Rust 收紧） | 运行时**无上界**：`sender.ahk:424` 原样 `Round(interval*1000)` µs，90000000ms → 9×10¹⁰ µs（25 小时），分组表现为"卡死/无响应"。AHK 的 `MAX_INTERVAL_MS := 86400000`（`config_validator.ahk:38`，拦截在 `_ValidateArrayLength:739-740`）是**量纲防呆**（把秒当毫秒）。Rust 只有 `MAX_REASONABLE_INTERVAL_MS=60_000`（`validator.rs:10`）的 WARNING（`validate_suspicious_mode_values:575-581`），**没有硬上界**——`u64` 上甚至可能到 `u64::MAX` | **v4**：保存超大间隔/延迟由「成功（只提示）」变为「失败」。**AHK 侧不变** | **是**。c12 移入「契约核心」；需新增「>24h 判非法」的 Rust 用例；夹具 `rust_has_error` false→true |
| **c13** | 热键 `Volume_Up`：Rust 合法 / AHK ERROR | **以 Rust 为准**（修 AHK，AHK 这条是**错的**） | **本次实跑取证**（`AutoHotkey64.exe`，输出见 §4）与派单的"AHK 更严"印象**相反**：<br>· AHK **原生 `Hotkey()`** 接受 `Volume_Up`/`Volume_Down`/`Volume_Mute`/`Media_Next`/`Media_Play_Pause`/`Launch_App1`/`Browser_Home`；<br>· AHK **校验器的正则**（`config_validator.ahk:130` `[A-Z][a-zA-Z0-9]+`，不含 `_`）**把这 7 个全拒了**；<br>· 反方向也错：正则**接受** `VolumeUp`（`REGEX_OK`），而 `Hotkey()` **拒绝**它（`Invalid key name.`）。<br>即 AHK 校验器与**它自己要守护的运行时**在两个方向都不一致 —— 这不是"更严"，是 **bug**。Rust 侧 `VALID_HOTKEY_KEYS`（`validator.rs:131-264`，`Volume_Up` 在 `:246`）与 AHK 原生键名一致，**Rust 才是对的** | **v3 栈**：可以保存 `Volume_Up` / `Media_*` / `Launch_*` / `Browser_*` 等带下划线热键（原本被拒）。**v4/Rust 侧不变** | **是**。c13 移入「契约核心」（两侧均判合法）；AHK 侧若有断言「`Volume_Up` 非法」的用例需改；夹具 `ahk_has_error` true→false |
| **c14** | `HoldSettings.checkInterval=5`：Rust 合法（只判 !=0）/ AHK ERROR（10-1000） | **语境分歧：以 AHK 为准（承认它是 v3 自有契约），但 Rust 不加、AHK 不改** | 取证：`checkInterval` 在 **v4 无消费方** —— Rust 侧只出现在 `config.rs`（定义 `:92`、默认、序列化测试 `:532`）与测试夹具，`src-tauri/src` 无任何功能读取；v4 AHK 执行器（`ahk_executor/`）**零命中**。唯一真实消费方是 **v3 的设置编辑器**（`presentation/gui_manager.ahk:381/430/444`）。因此：<br>· 给 Rust 加 10-1000 规则 = **为无人消费的字段制造噪音**；<br>· 放宽 AHK = 破坏 v3 自有 UI 的自洽约束，且毫无收益。<br>**建议维持现状**，并把 c14 从"必须收敛"降级为「**语境分歧**」——只在 v3 独立运行模式下有意义，随 ADR-001 冻结 v3 新功能而自然静止 | **无**（v4 不受影响；v3 行为不变） | **是**（仅改标注）：夹具 c14 由「已知分歧」改标「语境分歧 / 不计入 v4 契约」，并在 `desc` 写明原因 |
| **c15** | `joystick_hold` 的 `holdDuration=10ms`：Rust 合法 / AHK ERROR（最小 50ms） | **死字段分歧：维持 AHK 现状，Rust 不加；并另立一条债项** | 取证：`executor.ahk:332-335` `joystick_hold → Joystick.StartHold(groupId, joyKeys, sendMethod)` —— **不传 `holdDuration`**；`joystick.ahk:189` `static StartHold(groupId, joyKeys, sendMethod := "auto")` —— **签名里根本没有这个参数**。即 **v4 执行器完全忽略该字段**，AHK 的 50ms 下限在 v4 语境下"无的放矢"。<br>但**真正的问题不是 10ms 还是 50ms，而是"用户设了时长却不生效"** —— 这应另立债项（v4 `joystick_hold` 忽略 `holdDuration`），**不要**靠调整校验规则假装解决。<br>在字段被真正消费之前，争论阈值没有意义；一旦执行器开始读它，再按运行时行为定界 | **无**（v4 里该字段本就不生效；v3 行为不变） | **是**。夹具 c15 改标「死字段分歧 / 待 v4 执行器消费后再定」；**另立一条技术债**：`joystick_hold` 的 `holdDuration` 在 v4 执行器被忽略 |

### 1.1 汇总

| 方向 | 条目 | 改动侧 |
|---|---|---|
| 以 **Rust** 为准（AHK 改） | c09、c10、c13 | AHK `config_validator.ahk` |
| 以 **AHK** 为准（Rust 改） | c11、c12 | Rust `validator.rs` |
| **维持两侧现状**，只改标注 | c14、c15 | 夹具标注 + 另立 1 条债 |

**没有任何一处是"把更严的一侧放宽到更宽的一侧"，除了 c13——而 c13 的更严侧已被实跑证明是 bug。**

---

## 2. 总体收敛策略：单一真值怎么落地

### 2.1 三个候选方案

| 方案 | 做法 | 评估 | 工作量 |
|---|---|---|---|
| **S1** AHK 侧规则由 Rust 生成 | 把 Rust 校验规则编译/生成为 AHK 代码 | **否决**。两侧语言与运行时不同，AHK 无法调用 Rust；生成 AHK 源码会让 v3 栈**依赖 v4 的构建**，直接违反 ADR-001「v3 作为独立运行模式保留」。且构建期生成的代码不可读、不可手工核对，等于把真值藏进产物 | — |
| **S2** 抽一份共享规格文件（JSON/DSL），两侧各自实现 | 规则外置为数据，两侧读同一份 | **教科书写法，本轮不推荐**。① 校验规则里大量是"类型系统已保证"（Rust `u64` 非负）与"文案"，抽 DSL 要建解释器 + 文案模板；② 会引入**第三份真值**——规格本身可能与两侧都不同步，这正是 TD-055 那类「多份权威各说各话」的病；③ 与 ADR-001「v3 冻结新功能」冲突：给一个冻结的栈加规格解释器，投入产出不成比例 | 5–8 人天 |
| **S3（推荐）** 接受两侧各实现，用对拍装置钉住 + 逐处按运行时真值收敛 | 规则各写各的，但**每一处分歧都必须给出"运行时真相"依据并落到夹具**，装置持续防复发 | **推荐**。① 现状已是两套实现且拆不掉（v3 栈不会消失也不会重写）；② TD-067 的对拍装置已经把"分歧"变成**可回归的红灯**——这正是"两侧各实现"这种结构唯一需要的守护；③ 收敛后夹具从"7 处分歧"降到"0 处实质分歧 + 2 处语境/死字段标注"，装置继续防复发；④ 与既有 **C7 布尔契约同步**（以 Rust `bool` 字段为事实源反查 AHK `BoolKeys` 白名单）是**同构先例**，说明本仓已经接受"以一侧为事实源 + 机器反查"的模式 | **1.5–2 人天** |

### 2.2 推荐落地路径（S3）

| 步骤 | 内容 | 人天 |
|---|---|---|
| **P0** | **口径盘点（必须前置）**：AHK 侧实际存在三套可见口径——`Validate()`（探针口径）、`ValidateGroupOnly()`（`group_service.ahk:81/113`）、UI 保存路径直调 `_ValidateHotkeys`/`_ValidateHoldSettings`（`webview2_manager.ahk:576/585`）。先确认 P1 的改动落在哪条（几条）口径上，避免"夹具全绿、用户路径没变" | 0.5 |
| P1 | 改 AHK：c09 把查重并入 `Validate()`（复用 `ValidateGroupHotkeys:85-86` 已有逻辑）；c10 WARNING→ERROR；c13 修正则允许下划线键名 | 0.5 |
| P2 | 改 Rust：c11 加 10ms 下限、c12 加 24h 上界（均在 `check_keys_and_timings` / `validate_suspicious_mode_values` 附近，文案与 AHK 对齐） | 0.5 |
| P3 | 更新夹具：`c09/c10/c11/c12/c13` 五条移入「契约核心」；`c14/c15` 改标注；重跑 AHK 探针复核 `ahk_has_error` 列 | 0.3 |
| P4 | 同步 `asd-tauri/docs/test-map.md` 与台账 TD-067 的分歧清单（7 → 0 实质 + 2 标注） | 0.2 |
| **P5（强烈建议，独立于 P1–P4）** | **把热键键名表抽成共享 JSON**：以 Rust `VALID_HOTKEY_KEYS`（`validator.rs:131-264`）为事实源，AHK 读取同一份；并复用 C7 的模式加一条「键名表同步」门禁。理由：c13 的根因就是**键名表各写一份**，抽表能一次性消灭这类分歧，且有 C7 的成功先例 | 1.0 |

**合计：约 1.5 人天（P1–P4）；含 P0 约 2 人天；含 P0 + P5 约 3 人天。**

> ⚠️ P1–P4 有**严格顺序**：先改两侧规则 → 再重跑 AHK 探针（`tools/ahk-probes/p_cross_lang_validator.ahk`）**实跑**更新 `ahk_has_error` 列 → 最后改夹具标注。
> **绝不允许**先改夹具期望值再改规则——那会让对拍装置从"发现分歧"退化成"确认分歧"，是 TD-058 定义的**假守护**。

---

## 3. 风险小节（派单特别要求）

### 3.1 c09（分组查重）：**若以 AHK 为准 = 放宽，会导致用户存下重复热键的配置**

**会，而且后果严重。**

- **运行时证据**：`state.rs:511-522` `register_hotkey` —— 命中已占用即 `return Ok(Some(existing))`，**本次不注册**；返回 `Ok` 而非 `Err`，只看 `Result` 会误判成注册成功（该函数自己的文档 `:505-510` 就警告了这点）。
- **用户可见后果**：两个分组都显示"已启用"，但**只有一个的热键真的绑上了**；另一个按下去**毫无反应**，且 UI 不报错、日志无 ERROR。这是最难排查的一类问题（用户会报"这个分组坏了"，而不是"热键重复了"）。
- **v4 执行器也不能兜底**：`executor.ahk:115-126` 不查重，重复键交给 `Hotkey()` → AHK 原生行为是**后者覆盖前者**，同样静默。
- **结论**：**严禁放宽**。且 AHK 侧不仅不能放宽，还应**补严**——它现有的查重代码（`config_validator.ahk:85-86`）写在**从未被调用**的 `ValidateGroupHotkeys` 里，等于没有。补到 `Validate()` 里是本轮收益最高的一处改动（把一个静默失效变成一次明确报错）。

### 3.2 c10（控制热键空值）：**若以 AHK 为准 = 放宽为 WARNING，会导致用户存下空控制热键的配置**

**会存下，但当前无功能后果；风险是延后的，且属于安全相关功能。**

- **当前状态（已取证）**：v4 **没有**把 `CONTROL_HOTKEYS` 绑定到实际热键 —— `src-tauri/src` 里 `config.control_hotkeys` 无功能消费方；`toggle_all` / `emergency_release` / `clear_emergency` 是 Tauri 命令，由 UI 直接调用（`lib.rs:807/822/823`），不读配置里的热键值。v3 侧唯一消费方是设置编辑器（`gui_manager.ahk:351/411/450`、`webview2_manager.ahk:432/565-571`）。
  → 所以**今天**存一个空 `emergency`，不会有任何功能缺失。
- **为什么仍不建议放宽**：
  1. **契约自洽**：`ControlHotkeys` 五字段在 Rust 里是非 `Option` 的 `String`（`config.rs:76-86`），**缺一个字段就是反序列化失败**（比 ERROR 更硬）。允许"空串"通过、却不允许"缺字段"，是同一个契约里的自相矛盾。
  2. **延后风险**：控制热键里含 **`emergency`（急停）** 与 **`releaseAllHolds`（释放所有长按）**。一旦未来把它们绑定成真正的全局热键，"空值"就意味着**急停按钮按不下去** —— 这是安全相关功能（与 TD-065 红线系列同一语境），现在省下的成本会在那时连本带利还回来。
  3. **成本近乎零**：AHK 侧从 WARNING 改成 ERROR 是一行的级别，且 v3 栈已冻结新功能，影响面可控。
- **结论**：**不放宽**；按 §1 把 AHK 升为 ERROR。

### 3.3 反向风险：c11/c12 若"以 Rust 为准"放宽 AHK

这是派单最担心的一条，此处确认**风险成立**（但机制是静默夹紧/挂起，不是拒收，见 §0.2）。本备忘录的建议是**收紧 Rust 而不是放宽 AHK**，因此该风险不会发生。

需要额外提示的**新引入风险**：c11/c12 收紧 Rust 后，**历史配置**里若存在 <10ms 或 >24h 的值，原本能保存，现在会被拦。建议 P2 时同步确认：

- 出厂默认配置（`Config::default()`，`config.rs:51+`）与仓库内 `config.json` 是否含此类值（**预计不含**，但必须实跑确认，不能假设）；
- 导入路径是否需要给一次性的「自动夹紧到 10ms + 明确提示」，避免用户手上的旧配置突然存不进去。

---

## 4. 实跑取证附录：AHK 原生 `Hotkey()` vs AHK 校验器正则

**方法**：用 `asd-tauri/src-tauri/ahk_executor/AutoHotkey64.exe` 跑一次性脚本（注册后立即注销，不驻留），对同一批键名同时取「原生 `Hotkey()` 是否接受」与「`_IsValidHotkeyFormat` 正则是否接受」。脚本置于 `%TEMP%`，**未入库**。

```
键名                 AHK 原生 Hotkey()   ConfigValidator 正则
Volume_Up            ACCEPT              REGEX_REJECT     ← 校验器拒了运行时接受的
Volume_Down          ACCEPT              REGEX_REJECT
Volume_Mute          ACCEPT              REGEX_REJECT
Media_Next           ACCEPT              REGEX_REJECT
Media_Play_Pause     ACCEPT              REGEX_REJECT
Launch_App1          ACCEPT              REGEX_REJECT
Browser_Home         ACCEPT              REGEX_REJECT
NumpadDel            ACCEPT              REGEX_OK
BackSpace            ACCEPT              REGEX_OK
Space                ACCEPT              REGEX_OK
F13                  ACCEPT              REGEX_OK
q                    ACCEPT              REGEX_OK
VolumeUp             REJECT: Invalid key name.   REGEX_OK  ← 校验器放了运行时拒的
Volume_              REJECT: Invalid key name.   REGEX_REJECT
Zzz_NotAKey          REJECT: Invalid key name.   REGEX_REJECT
```

**读法**：AHK 校验器的正则与它要守护的运行时**在两个方向都不一致**——既拒了合法的（`Volume_Up` 系列 7 个），又放了非法的（`VolumeUp`）。这决定了 c13 的性质是 **bug 修复**，不是**策略取舍**，也直接否定了「一律采纳更严的一侧」这个总口径。

---

## 5. 待补 / 附注

1. **第 8 处「热键长度」已定论：不构成分歧**（结论来自夹具新增用例 `c17_hotkey_len20_alnum_both_legal`，两侧 `has_error` 均为 false）。该用例的描述已写明：Rust 侧长度阈值是 `MAX_REASONABLE_HOTKEY_LEN = 256`，20 字符连长度规则都不触发；AHK 侧主入口 `Validate` 走 `_IsValidHotkeyFormat`（`config_validator.ahk:126`），20 字符命中 `[A-Z][a-zA-Z0-9]+` → 合法。
   **本稿在定论前给出的取证线索已被证实**：AHK 的 15 字符检查在 `config_validator.ahk:82-83`，位于 `ValidateGroupHotkeys`（`:63-93`），与 c09 的查重代码同属**零调用的死入口**——我对 v3 生产树三层目录（`infrastructure/` + `application/` + `presentation/`）grep `ValidateGroupHotkeys`，结果**只有 `config_validator.ahk:63` 的定义，无任何调用点**。所以第 8 处不是"Rust 256 vs AHK 15 的规则分歧"，而是"**一条 v3 生产路径不可达的死规则**"，裁决方式同 c09：要么补进 `Validate()`，要么显式标注为死代码，**不应"对齐到 256"**（那等于把一条死规则改成另一条活规则，凭空新增用户可见报错）。
   **由此产生的第 3 条口径提示**：v3 UI 保存路径 `presentation/webview2_manager.ahk:576/585` 直接调内部方法 `_ValidateHotkeys`（`:552`）与 `_ValidateHoldSettings`（`:570`），**不经过 `Validate()`**。也就是说 AHK 侧实际存在**三套可见口径**（`Validate()` / `ValidateGroupOnly()` / UI 直调内部方法），本装置只钉住了 `Validate()` 一套。**若 A1 拍板后要改 AHK 侧，必须先确认改动落在哪条口径上**，否则会出现"夹具全绿但用户路径没变"。已作为 **P0** 写入 §2.2 落地路径。

2. **另立债项建议（不在 A1 收敛范围内）**：v4 执行器 `joystick_hold` 完全忽略 `holdDuration`（`executor.ahk:332-335` → `joystick.ahk:189`），用户设置"保持 500ms"不会生效。这是**功能缺陷**而非校验分歧，建议单独立项。

3. 本备忘录未改动任何代码、夹具、台账；TD-067 的分歧清单（7 处）待拍板后再按 §2.2 同步。

---

## 6. 需要人类拍板的事项（本稿不能代替决策的部分）

| # | 拍板点 | 本稿建议 | 不拍板的后果 |
|---|---|---|---|
| D1 | 是否接受「**真理 = 运行时行为**」作为裁决标准（而非「Rust 一律赢」或「取严侧」） | 接受。这是 A1 真正的决策点 | 若按"Rust 一律赢"执行，c11/c12 会把**保存时可见报错**改造成**运行时静默不生效**（§0.2） |
| D2 | c14 / c15 是否**不收敛**（降级为"语境性分歧 / 死字段分歧"，另立债项） | 不收敛。c14 在 v4 无消费方，c15 的字段被 v4 执行器完全忽略 | 若强行收敛，会在一个 v4 不读的字段上改动两侧规则，纯投入无收益 |
| D3 | c11 / c12 收紧 Rust 后，**历史配置**里已存在的 <10ms / >24h 值怎么处理 | ~~先实跑确认~~ → **已实证回答（2026-09-19）：历史样本里一个越界值都没有，本项降级为纯政策决策**，见下方 §6.1 | 用户手上的旧配置突然存不进去，属于"升级即阻断" |
| D4 | 是否投 **P5**（键名表抽共享 JSON + 一条 C7 式同步门禁，1 人日） | 投。c13 的根因是键名表各写一份，不投只会复发 | c13 这类"键名表漂移"会持续以新面孔出现 |
| D5 | 是否接受 **P0 口径盘点前置**（0.5 人日） | 接受。AHK 侧有三套可见口径，夹具只钉住一套 | 出现"对拍全绿但用户实际保存路径行为未变"的假守护（TD-058 型） |

### 6.1 D3 的实证回答（2026-09-19 补齐，本稿 D3 行据此降级）

扫描对象：仓库根 `config.json`、`config_export_20260524021401.json`、`backups/*.json` 共 **12 个文件 / 22 个分组**。

| 指标 | 实测值 |
|---|---|
| 解析成功文件数 | 12 / 12（需 `utf-8-sig`，见 §6.2） |
| 扫到的时间类数值 | **116 个** |
| 会被 c11（<10ms）/ c12（>24h）拦下 | **0 个** |
| 实际取值集合（非零点） | 10 / 15 / 20 / 50 / 100 / 200 / 220 / 240 / 500 / 1000 / 2000 / 2500 |

**结论**：收紧 c11 / c12 **不会造成"升级即阻断"** —— 现存所有历史配置都在合法区间内。D3 因此**不再是一个风险问题，只剩下政策问题**：是否愿意让 Rust 侧从此拒收这类值。

**⚠️ 本结论的两次假绿（记录以免后人重踩）**：① 第一版脚本 12 个文件全部因 UTF-8 BOM 被跳过，输出「命中 0」，真实含义是「扫了 0 个文件」；② 第二版脚本只扫到 11 个值且全为 100，因为**数组元素的键名取成了 `intervals[0]`**（`p.split('.')[-1]`），与目标键 `intervals` 不匹配 → 数组元素被整体跳过。**凡"扫描结果异常地少"都要先怀疑脚本，再怀疑结论。**

### 6.2 顺带发现：配置文件的 BOM（已修症状，但不构成本条债项）

- 12 个配置文件**全部带 1 层 UTF-8 BOM** → 严格解析器（`json.load(..., encoding='utf-8')`）**12/12 失败**，必须 `utf-8-sig`。
- 仓库根 `config.json` 原本是**双 BOM**（`git show HEAD:config.json` 前 6 字节 `efbbbf efbbbf`），已归一为单 BOM。
- **双 BOM 并未弄坏产品**（查 AHK v2.0.26 源码确认，非推断）：`FileRead(...,"UTF-8")` 剥 1 层（`source/lib/file.cpp:276-281`）+ `JSONParser.__New` 再剥 1 层（`infrastructure/json_parser.ahk:77-78`）→ 正好剥完；Rust `config_repository.rs:287` 的 `trim_start_matches('\u{feff}')` 对 char pattern 剥**全部**层 → 亦不受影响。
- **双 BOM 来源未确认**：`FileAppend(...,"UTF-8")` 只在"写入且文件为空"时落 1 层（`source/TextIO.cpp:87-90`），追加到非空文件不再落 —— 应用自身写不出双层，**不臆断成因**。
- **处置**：不立债项。BOM 是有意设计（`config_io.ahk:79` 为记事本兼容），两栈均可容忍；双 BOM 为一次性产物且已修。记载在 `remediation-plan-2026-09-19.md` §5.7。
