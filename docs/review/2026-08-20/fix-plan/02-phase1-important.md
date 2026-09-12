# Phase 1 重要修复方案（Fix Plan 第二步）

> **来源**：`docs/review/2026-08-20/fix-plan/00-issue-inventory.md`（P1 主题分组，以它为准）+ `docs/code-review-report-2026-08-20.md` §5（详细发现清单）
> **覆盖范围**：P1 全部 23 项 Important，按 10 个主题批次组织
> **口径**：23 项 = 去重后口径。其中「T3-05 + T6-03」为合并项（1 条含 2 个原始编号）。其余 9 个批次共 22 项，各批成员数如 §0 校验式所示。
> **性质**：只读规划文档，仅编写本文件；修复步骤为计划内容，**不在本阶段执行任何 .ahk/.rs/.toml/.json 修改**。

---

## 0. 批次总览与统计核对

| 批次 | 主题 | 成员编号 | 成员数 | 主要责任角色 | 相对时间框 |
|:---:|------|---------|:---:|------------|:---:|
| G1 | 校验覆盖缺口 | T3-01、T3-02、T3-03、T4-04 | 4 | AHK 领域/基础设施 + asd-domain 开发者 | 1~2 天 |
| G2 | 热路径日志无限速 | T3-05 + T6-03 | 1（2 编号） | AHK 基础设施开发者 | 1 天 |
| G3 | 定时器生命周期 | T6-02、T6-04 | 2 | AHK 执行器 + 领域层开发者 | 1~2 天 |
| G4 | IPC 背压与阻塞 | T6-05、T6-06 | 2 | Rust 后端开发者 | 1~2 天 |
| G5 | unsafe soundness | T5-01 | 1 | Rust 后端开发者 | 1~2 天（含回测） |
| G6 | vJoy 设备复用 | T6-07 | 1 | AHK 执行器开发者 | 1 天 |
| G7 | 隐式依赖与永真断言 | T2-03、T2-04、T5-02 | 3 | AHK 基础设施 + Rust 后端 | 0.5~1 天 |
| G8 | 输入误报与注入检查 | T3-04、T3-06 | 2 | AHK 表现层 + 领域层开发者 | 0.5~1 天 |
| G9 | 测试覆盖补强 | T8-01、T8-02、T8-03 | 3 | 测试/QA 工程师 | 1~2 天 |
| G10 | 文档严重漂移 | T7-02、T7-03、T7-04、T7-05 | 4 | 文档/技术写作者 | 1~2 天 |

**校验**：4 + 1 + 2 + 2 + 1 + 1 + 3 + 2 + 3 + 4 = **23** ✓（主题批次数 = **10** ✓）

> **依赖关系**：G3（定时器）、G6（vJoy）、G8（注入检查）同属 AHK 执行器/领域层热路径，建议同批或紧邻进行，合并回归测试；G4/G5 同属 `src-tauri` 后端，建议相邻进行以便统一 `cargo test --lib` 回归；G10 文档批次建议放在其余批次收口后统一对齐统计口径，但 T7-03/T7-04/T7-05 的统计漂移可在 G9 测试补强完成后再最终核数。
> **原子提交原则**：每个批次可拆分多个原子提交（按「一次提交只改一个关注点」边界标注于各批修复步骤中），避免「校验 + 性能 + 文档」混在一个 commit 里。

---

## 批次 1：校验覆盖缺口（T3-01、T3-02、T3-03、T4-04）

### 1. 问题描述

本批聚焦「配置验证器多层校验路径不一致导致的非法输入静默放行」，AHK 侧与 Rust 侧各有一处同类缺口：

- **T3-01**（`infrastructure/config_validator.ahk:115-138`）：`_ValidateGroup`（84-88 行）已用 `_IsValidHotkeyFormat` 校验热键格式，但 `ValidateGroupOnly`（121-122 行）只查 `hotkey` 是否 `_HasField`、不校验格式。而 `CreateGroup/UpdateGroup` 实际走的正是 `ValidateGroupOnly`，即 WebView2 保存分组时不做格式校验。
- **T3-02**（`infrastructure/config_validator.ahk:140-284`）：`_ValidateModeFields` 各 mode 分支对 `keys/pressKeys/holdKeys/joyKeys` 只校验「非空/数组长度/数值边界」，从不校验元素是否为合法按键名。领域层运行时由 `SkillGroup._IsValidKeyName`（`skill_group.ahk:889-902`）兜底静默跳过，形成「配置看着正常但按键永不触发」的隐蔽故障。
- **T3-03**（`infrastructure/config_validator.ahk:286-299`）：`_ValidateHotkeys` 只校验 5 个必需 action（`emergency/toggleAll/showStatus/toggleHoldMode/releaseAllHolds`）是否存在、是否为空（空仅记 WARNING），不校验格式；`_BindControlHotkeys`（`skill_manager.ahk:147-187`）运行时 `Hotkey()` 抛异常仅记 WARNING，「紧急停止」等关键安全功能可能静默失效。
- **T4-04**（`crates/asd-domain/src/validator.rs:90-94,137-139`）：`validate_config` 对 5 个控制热键仅调用 `validate_hotkey_format`，而该函数对空串（137-139 行）直接 `return`（无 error/warning），故 `"emergency": ""` 会静默通过并被持久化；`validate_duplicate_hotkeys`（161-170 行起）只比对分组热键之间，未与控制热键做交叉冲突检测。对比同文件对分组热键「刻意补了」`hotkey.is_empty()` 的 error 分支（120-122 行），控制热键路径缺失对应空值 error。

### 2. 影响范围评估

- **受影响模块**：AHK `infrastructure/config_validator.ahk`；Rust `asd-domain/src/validator.rs`；下游 `application/config_service.ahk`（保存入口）、`presentation/group_editor.ahk` + `webview2_manager.ahk`（WebView2 保存分组/设置）、`domain/skill_manager.ahk`（控制热键绑定）、`domain/skill_group.ahk`（按键名运行时兜底）。
- **用户路径**：Web UI 保存单个分组（分组热键校验缺失）、保存任意模式分组（按键名校验缺失）、保存全局设置控制热键（格式校验缺失）、Tauri 侧保存配置（空控制热键静默落盘）。
- **风险后果**：非法热键写入成功 → 运行时 `Hotkey()` 报「热键注册失败…可能被占用」误导真实原因；非法按键名 → 按键永不触发；非法/空控制热键 → 紧急停止等安全功能静默失效。

### 3. 根本原因分析

- **共性根因**：验证器内已存在共享校验原语（AHK 的 `_IsValidHotkeyFormat`；Rust 的 `validate_hotkey_format` + `normalize_hotkey_for_comparison`），但新增/补丁路径没有复用它们，形成多条「只查存在性/非空」的不一致校验分支；且 AHK 侧与 Rust 侧各自独立演进，同类缺口出现两次。
- **成员差异**：
  - T3-01 是「入口用错函数」——`ValidateGroupOnly` 应等价 `_ValidateGroup` 但漏掉了 hotkey 格式分支。
  - T3-02 是「缺一层校验」——没有按键名合法性校验原语（`_IsValidKeyName` 是 `SkillGroup` 私有方法，验证器无法复用）。
  - T3-03 是「控制热键与分组热键校验强度不对等」——`_IsValidHotkeyFormat` 未用在控制热键上。
  - T4-04 是 Rust 侧「必填安全字段复用『空串不校验也不报错』的函数约定」——对必填控制热键未补 `is_empty()` error 分支，且冲突检测未纳入控制热键。

### 4. 具体修复步骤

**提交 1（T3-01，`infrastructure/config_validator.ahk`）**
1. 在 `ValidateGroupOnly` 的 hotkey 分支（121-122 行）改为与 `_ValidateGroup` 一致：保留 `_HasField` 存在性检查（缺失 → ERROR），并在 `else` 分支追加 `_IsValidHotkeyFormat` 校验（非法 → ERROR，message 与 84-88 行保持同一措辞）。

**提交 2（T3-02，`infrastructure/config_validator.ahk` + 可选共享工具下沉）**
2. 将 `SkillGroup._IsValidKeyName`（`domain/skill_group.ahk:889-902`）的合法名单逻辑下沉为共享工具函数（建议放入无外部依赖的 `infrastructure/utils.ahk` 或新建纯校验辅助，避免引入新的跨层依赖；若担心层级，可先复制逻辑到 validator 内部私有方法 `_IsValidKeyName`，并在注释标注「与 skill_group._IsValidKeyName 保持同步，后续统一」）。
3. 在 `_ValidateModeFields` 各 mode 分支（140-284 行）对 `keys/pressKeys/holdKeys/joyKeys` 数组元素逐个校验：元素为非法按键名 → `errors.Push(Map("type","ERROR",...,"分组" id "的按键名非法: " elem))`。注意 `joyKeys` 走「Joy 数字/轴/POV」规则，与键盘按键名规则不同，需单独校验函数或复用 `JoystickInput` 相关校验（`infrastructure` 可引用 `domain/joystick_input.ahk` 纯工具类，符合 AGENTS.md 已备案妥协 #1）。

**提交 3（T3-03，`infrastructure/config_validator.ahk`）**
4. 在 `_ValidateHotkeys`（286-299 行）对每个「非空」action 值追加 `_IsValidHotkeyFormat` 校验：非法 → `errors.Push(Map("type","ERROR",...,"控制热键 " action " 格式无效: " val))`（将现「空值 WARNING」保留，但非法格式升级为 ERROR）。

**提交 4（T4-04，`crates/asd-domain/src/validator.rs`）**
5. 在 `validate_config`（87-106 行）对 5 个控制热键：改为先判 `is_empty()` → `result.add_error("_global", "<字段名>", "控制热键 <名> 不能为空")`，非空再调用 `validate_hotkey_format`（消除 137-139 行「空串静默 return」对必填字段的副作用）。
6. 扩展 `validate_duplicate_hotkeys`（161 行起）：在收集 `normalize_hotkey_for_comparison` 的 `seen` 集合时，把 5 个控制热键一并纳入比对，实现「控制热键 vs 分组热键」、「控制热键 vs 控制热键」交叉冲突检测（`emergency` 与某分组热键相同 → error）。

> 提交可并行：提交 1/2/3 针对同一 AHK 文件，建议按序做以免冲突；提交 4 独立于 Rust 侧可并行。

### 5. 测试验证方案

- **AHK 验证命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- **AHK 新增/回归用例**（`tests/test_infrastructure.ahk` 或对应 validator 套件）：
  - T3-01：`ValidateGroupOnly` 传入非法热键 `"Hotkey":"garbage"` → 断言返回含 ERROR。
  - T3-02：各 mode 分组写入非法按键名（如 `keys:["!badkey"]`、`joyKeys:["Joy999"]`）→ 断言 ERROR；写入合法名 → 断言无 ERROR。
  - T3-03：`_ValidateHotkeys` 传入 `emergency:"garbage"` → 断言 ERROR；空值 → 仍为 WARNING。
- **Rust 验证命令**：
  ```powershell
  cd asd-tauri; cargo test -p asd-domain
  ```
- **Rust 新增/回归用例**（`crates/asd-domain/src/validator.rs` 的 `#[cfg(test)]`，或 `config_compat_tests`）：
  - T4-04：`validate_config` 对 5 个控制热键各造一条 `""` 用例 → 断言 `!result.is_valid()` 且 error field 正确；分组热键与控制热键同名用例 → 断言报冲突 error。

### 6. 回滚机制

- 全部为「新增校验分支」，不改变成功路径的数据流；任一批次回退只需 `git revert` 对应单个提交。
- 校验器行为可由 `validate_config`/`_ValidateModeFields` 的调用方（保存入口）直接观测：若某用例因新增校验误伤合法配置，可先 `git revert` 该提交再修规则，不影响持久化存储格式。

### 7. 修复后效果评估标准

- 非法分组热键、非法按键名、非法/空控制热键、控制热键冲突四类输入在验证阶段被拦截（ERROR），不再写入 config.json。
- `cargo test -p asd-domain` 全部通过，且新增校验用例为绿；AHK `run_all_tests.ahk` 无回归。
- 度量：报告 §5.4 中 T3-01/02/03、§5.4 T4-04 四条的「位置」处均可见对应校验分支，代码审查复核时逐条关闭。

### 8. 责任角色 + 相对时间框

- **责任角色**：AHK 领域/基础设施层开发者（提交 1/2/3）+ asd-domain 开发者（提交 4）。
- **相对时间框**：P1 短期，**1~2 个工作日**；4 个提交，每个 0.5 天可完成（含用例）。

---

## 批次 2：热路径日志无限速（T3-05 + T6-03，合并项）

### 1. 问题描述

- **T3-05 + T6-03**（合并项，原始 2 编号）：
  - `infrastructure/error_system.ahk:185-213`（`_WriteLog`）、`infrastructure/json_logger.ahk:179-227`（`_WriteLog`/`_LogToFile`）、`infrastructure/debug_logger.ahk:22,52-56`（唯一有限速：仅 DEBUG、间隔 50ms）。
  - 各执行器 catch：`domain/mode_registry.ahk:294/343/394/444/463/481/541 等`、`domain/skill_group.ahk:756-758`。
- **描述**：AGENTS.md 承诺「Execute* 热路径日志每秒最多一次」，但 `ErrorSystem.LogError`→`_WriteLog` 与 `JSONLogger._WriteLog` 均无限速，每次同步 `JSONSerializer.Stringify` + `FileAppend` 落盘；`DebugLogger` 仅有 50ms 间隔（非「每秒一次」）且仅覆盖 DEBUG。持续抛异常时以 10-50ms 周期反复 2 次序列化 + 2 次同步写盘。

### 2. 影响范围评估

- **受影响模块**：`infrastructure/error_system.ahk`、`infrastructure/json_logger.ahk`、`infrastructure/debug_logger.ahk`；所有调用 `ErrorSystem.LogError` 的热路径执行器（`domain/mode_registry.ahk`、`domain/skill_group.ahk`、`domain/joystick_executor.ahk` 等）。
- **用户路径**：任何分组处于周期性/序列执行且触发异常时（如 T3-06 未注入场景会放大本问题），日志写盘挤压 AHK 消息循环，导致按键节拍抖动、CPU 与磁盘 I/O 飙升。
- **风险后果**：热路径被日志 I/O 强耦合，违反文档承诺；与 T3-06 叠加时异常 + 高频率写盘双重放大。

### 3. 根本原因分析

- **共性根因**：错误路径缺少「令牌桶/滑动窗口」限速器；限速承诺仅在 `DebugLogger` 部分实现，未下沉到 `ErrorSystem`/`JSONLogger` 的统一落盘入口。
- **成员差异（合并项内部）**：T3-05 侧重「错误日志落盘无限速」；T6-03 侧重「DebugLogger 的限速口径与承诺不符（50ms vs 每秒一次）」。

### 4. 具体修复步骤

**提交 1（T3-05，`infrastructure/error_system.ahk` 与 `infrastructure/json_logger.ahk`）**
1. 在 `ErrorSystem` 与 `JSONLogger` 各自加入与 `DebugLogger` 同构的限速器：静态字段 `_lastWriteTime`（`A_TickCount`）+ `_suppressedCount` + 按调用源（`module`/调用点）分桶的 `Map`（避免不同协程/分组互相抑制误伤）。
2. 在 `_WriteLog`/`_LogToFile` 入口：同一源在限速窗口内再次写入时，仅累加 `_suppressedCount` 并跳过 `Stringify`+`FileAppend`；窗口过期或首次写入时落盘并附 `suppressedCount=N` 字段/注释。

**提交 2（T6-03，`infrastructure/debug_logger.ahk` 或文档二选一并明确）**
3. 将 `DebugLogger` 的 50ms 阈值与「每秒一次」口径对齐（改成共享常量 `LOG_RATE_LIMIT_MS := 1000`），或在 AGENTS.md 明确「热路径日志限速阈值为 50ms（修正文档而非代码）」。**建议**：统一为共享常量，三处 logger 引用同一阈值，消除口径分叉。

> 原子提交：提交 1 与提交 2 分别落一个 commit（限速逻辑 vs 口径/常量统一）。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- **新增/回归用例**：在 `tests/test_error_system.ahk`（保留其 `OnError` 特殊模式）或 `tests/test_infrastructure.ahk` 中，对同一源连续调用 `LogError` N 次，断言实际 `FileAppend` 落盘次数 ≤ 阈值窗口内 1 次（可通过注入 mock writer 或统计日志行数验证），且抑制计数正确累加。

### 6. 回滚机制

- 限速器为纯增量（新增静态字段 + 入口判断），回退单提交即恢复旧行为；日志落盘内容不改变，仅减少重复写。
- 若某依赖「每次必现日志」的调试流程受影响，可临时把阈值常量调回 0/50ms，或按调用源定向放行。

### 7. 修复后效果评估标准

- 同源高频异常下，日志 `FileAppend` 调用频率 ≤ 1 次/秒（与 AGENTS.md 承诺一致），且每条落盘记录含 `suppressedCount` 可观测。
- 度量：持续让某周期性分组抛异常 1 秒，`logs/app.log` 对应行数增长 ≤ 1，`debug.log` 无同源风暴。

### 8. 责任角色 + 相对时间框

- **责任角色**：AHK 基础设施开发者。
- **相对时间框**：P1 短期，**1 个工作日**。

---

## 批次 3：定时器生命周期（T6-02、T6-04）

### 1. 问题描述

- **T6-02**（`domain/skill_group.ahk:800-805`；`ahk_executor/sender.ahk:347,394,444,464`；`ahk_executor/joystick.ahk:203,253`；`domain/joystick_executor.ahk:55,107`）：每次按键「按下」都 `SetTimer(((ck) => () => ...)(capturedKey), -kpd)` 现造闭包 + 注册一次性定时器；`_SendKey` 还额外构造 `releaseTimer` 闭包（捕获 4 变量）+ 冗余 `HasProp` 检查。executor 侧这些「up」定时器未纳入任何 Map 跟踪，分组停止时不被取消（停止瞬间可能滞后发一次 up）。
- **T6-04**（`ahk_executor/sender.ahk:178-194（StartPeriodic）、197-215（StartSequence）、290-305（StartHybrid）、joystick.ahk:68-85`；触发入口 `executor.ahk:102-107`）：各 `StartXxx` 直接 `_timers[groupId] := timerFn; SetTimer(...)` 覆盖旧引用而不先 `SetTimer(旧引用,0)`；重连恢复或前端重复触发 `toggle_group(active=true)` 时旧定时器仍运行 → 双倍发键，旧引用丢失无法停止。

### 2. 影响范围评估

- **受影响模块**：`domain/skill_group.ahk`、`domain/joystick_executor.ahk`、`ahk_executor/sender.ahk`、`ahk_executor/joystick.ahk`、`ahk_executor/executor.ahk`。
- **用户路径**：分组启停、前端重复切换 active、重连恢复期间。用户在周期性/序列/Hold 模式下的按键，可能因 up 定时器泄漏产生「停止后多按一次」或「双倍发键」。
- **风险后果**：重复触发 → 双倍按键输出（游戏/输入场景严重）；停止不彻底 → 残留 up 键导致键位卡住或误触。

### 3. 根本原因分析

- **共性根因**：定时器作为资源未统一纳管——既有「up/release 定时器未登记进 Map」也有「周期定时器覆盖前未先取消」，两条路径都是「启动定时器」与「跟踪/清理定时器」未成对。
- **成员差异**：T6-02 是「一次性 up 定时器无登记、逐键现造闭包」；T6-04 是「周期定时器覆盖引用前缺幂等取消」。

### 4. 具体修复步骤

**提交 1（T6-04，先修时序——重复激活幂等，`ahk_executor/sender.ahk` + `ahk_executor/joystick.ahk`）**
1. 在每个 `StartXxx`（`sender.ahk:178/197/290`、`joystick.ahk:68-85`）开头直接插入幂等保护：`if Sender._timers.Has(groupId) { SetTimer(Sender._timers[groupId], 0); Sender._timers.Delete(groupId) }`（Joystick 侧同构处理）。
2. 或在 `_HandleToggleGroup`/`executor.ahk:102-107` 层增加「已激活且配置相同 → 直接 return」的短路，避免重复进入 `StartXxx`。

**提交 2（T6-02，`domain/skill_group.ahk` + 各 executor）**
3. 领域层：将 `_SendKey` 的 `releaseTimer` 登记进已有的 `_releaseTimers` Map（复用 `skill_group` 现有思路），去除逐键现造闭包与冗余 `HasProp`；分组停止时遍历取消。
4. 执行器层（`sender.ahk:347/394/444/464`、`joystick.ahk:203/253`、`joystick_executor.ahk:55/107`）：维护「已按下键集合 + 单一周期释放扫描定时器」，将 O(按键数) 建闭包/定时器降为 O(1) 周期扫描；如需保留一次性定时器，则将其句柄登记进 `_timers` 派生 Map（如 `_releaseTimers`），停止分组时统一 `SetTimer(句柄,0)`。

> 提交顺序：先做提交 1（幂等），做提交 2（纳管），最后合并回归——因提交 2 依赖提交 1 建立的「定时器可取消」前提。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- **新增/回归用例**（`tests/test_ahk_executor/test_sender.ahk`、`test_joystick.ahk`、`tests/test_domain.ahk`）：
  - T6-04：同 groupId 连续两次 `StartPeriodic` → 断言 `_timers` 仅有 1 个活跃引用、无误留旧定时器（通过 mock `SetTimer` 或统计发键次数验证不双倍）。
  - T6-02：分组停止后立即触发，断言无滞后 `_SendKeyUp`；down 后停止分组，断言「已按下集合」被清空/释放定时器被取消。

### 6. 回滚机制

- 提交 1 为「启动前先取消」的幂等保护，回退单提交恢复旧行为；提交 2 为纳管改造，若 executor 侧选「单一扫描定时器」方案改动面较大，可先仅做「一次性定时器登记进 Map」的最小改动（可独立回退）。

### 7. 修复后效果评估标准

- 重复 `toggle_group(active=true)` 不产生重复定时器、不双倍发键；分组停止后无滞后 up 事件。
- 度量：自动化用例断言「重复 start 后活跃定时器数 == 1」通过，`run_all_tests.ahk` 无回归。

### 8. 责任角色 + 相对时间框

- **责任角色**：AHK 执行器开发者（sender/joystick/executor）+ AHK 领域层开发者（skill_group/joystick_executor）。
- **相对时间框**：P1 短期，**1~2 个工作日**。

---

## 批次 4：IPC 背压与阻塞（T6-05、T6-06）

### 1. 问题描述

- **T6-05**（`src/bridge.rs:44-67（send_command）、69-129（send_and_wait）`；`src/infrastructure/ipc.rs:290-327（send）`）：同步 `IpcSender` trait 用 `block_in_place + block_on` 桥接；`send()` 的 `write_all().await`+`flush().await` 无 `tokio::time::timeout`，AHK 挂死且管道写满时无限阻塞，占用 Tauri 工作线程，多命令并发可能耗尽线程池。
- **T6-06**（`src/infrastructure/ipc.rs:545（dispatch_response(msg.clone())）、567-572（outbound_tx.send(msg).await）、504、18`）：先 `msg.clone()`（`data` 为 `serde_json::Value`，克隆成本不低）再判断响应归属，绝大多数非响应消息被无谓深拷贝；`outbound_tx.send(msg).await`（非 `try_send`）在消费端变慢时阻塞监听循环，经 recv → OS 管道 → AHK 同步 WriteFile 反向压死。

### 2. 影响范围评估

- **受影响模块**：`src/bridge.rs`、`src/infrastructure/ipc.rs`。
- **用户路径**：热键触发、命令发送（toggle/register/recording 等）。AHK 子进程挂起/慢消费时，Rust 主进程工作线程可能被阻塞、监听循环可能被背压拖慢，最终反向冻结 AHK 执行器。
- **风险后果**：Tauri 线程池耗尽 → 主进程 UI 无响应；消息深拷贝与 `await` 无界积累 → 内存与延迟劣化。

### 3. 根本原因分析

- **共性根因**：IPC 写入/分发链路缺乏「超时兜底」与「背压上限」，同步 trait 与异步 IpcManager 桥接方式放大了阻塞窗口。
- **成员差异**：T6-05 是「写侧无超时 + 同步阻塞桥接」；T6-06 是「读侧分发先 clone 后判 + outbound `await` 无界」。

### 4. 具体修复步骤

**提交 1（T6-05，`src/infrastructure/ipc.rs`）**
1. 给 `send()`（290-327 行）的 `write_all`+`flush` 包上 `tokio::time::timeout(Duration::from_millis(<阈值，如 2000>), ...)`：超时视同管道不可靠 → 清理 `send_half`、调用 `notify_pipe_broken()`、返回超时错误（沿用现有 `PipeBroken`/新 `SendTimeout` 变体）。
2. 长期方向（注释标注，非本批强制）：将 `IpcSender::send_command` 改为 async 或应用层改为 async 调用，消除 `block_in_place + block_on`（与已知妥协 #2 协同，见 AGENTS.md）。

**提交 2（T6-06，`src/infrastructure/ipc.rs`）**
3. 在 `listen_ahk`（545 行起）先判 `msg.ack_seq.is_some()` 再决定是否 `clone`：无 `ack_seq`（非响应）直接转移所有权，避免无谓深拷贝。
4. 对 `key_send_event` 等高频非关键 `r#type` 消息用 `try_send` + 满则丢弃/合并；关键 `hotkey`/`pong` 等保留 `.await`（或改用 `send_timeout`）。

> 原子提交：提交 1（写超时）与提交 2（分发优化）各一个 commit，便于独立回滚与性能对比。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  cd asd-tauri/src-tauri; cargo test --lib
  cd asd-tauri; cargo test -p asd-ipc-protocol
  ```
- **新增/回归用例**（`src/tests/ipc_tests.rs` + `bridge_tests.rs`）：
  - T6-05：构造「写端阻塞/管道满」场景，断言 `send()` 在超时窗口内返回 `Err`（超时类）而非无限阻塞，且触发 `notify_pipe_broken`。
  - T6-06：构造慢 `outbound_tx` 消费方，断言 `try_send` 满时对非关键消息丢弃、监听循环不被阻塞（通过计数/时序断言）；无 `ack_seq` 消息不触发深拷贝（可用 `Arc`/计数器观测，或作为白盒测试约束）。

### 6. 回滚机制

- 提交 1 是「给已有写入包 timeout」，回退单提交即可恢复「无超时」旧行为（但旧行为本身是缺陷，回滚仅用于紧急止血后重做）。
- 提交 2 的 `try_send` 丢弃策略可能改变非关键消息的送达语义：回退时仅需恢复 `.await` 发送，不影响核心控制流。

### 7. 修复后效果评估标准

- AHK 挂死时 `send()`/`send_command` 在超时上限内返回错误而非挂起；`listen_ahk` 循环在高频消息下 CPU/内存稳定，无无界 `await`。
- 度量：`cargo test --lib`（含新增 timeout/丢弃用例）全绿；人工挂起 AHK 验证主进程 UI 不冻结。

### 8. 责任角色 + 相对时间框

- **责任角色**：Rust 后端开发者（src-tauri）。
- **相对时间框**：P1 短期，**1~2 个工作日**。

---

## 批次 5：unsafe soundness（T5-01）

### 1. 问题描述

- **T5-01**（`src/infrastructure/watchdog.rs:67,73,499,502`）：`ProcessWatchdog` 含 `Option<Child>`（`Send + !Sync`），手工 `unsafe impl Sync`（依据「所有访问经 `Arc<tokio::sync::Mutex>`」）；`JobObjectGuard(HANDLE)` 手工 `Send/Sync`（依据 Mutex 保护 + Drop 仅 CloseHandle，499/502 行）。当前不变量成立（生产路径先持锁再取 `&Guard`，调用方立即 `.clone()`），但 `state()`（118-120 行）返回 `&WatchdogStateEnum`，一旦未来把引用保存到 guard 之外 → 跨锁共享引用 → 数据竞争 → UB。

### 2. 影响范围评估

- **受影响模块**：`src/infrastructure/watchdog.rs`（`ProcessWatchdog`、`JobObjectGuard`、`state()`）。
- **用户路径**：进程监控/看门狗在 Tauri 异步线程间共享；任何未来对 `state()` 返回引用的误用都可能触发未定义行为。
- **风险后果**：数据竞争 UB（难以复现、后果不可控）；手工 `unsafe impl` 使 `asd-domain/asd-ipc-protocol/asd-application` 之外的 src-tauri 存在 soundness 敏感点。

### 3. 根本原因分析

- **共性根因**：为把含 `!Sync` 字段的结构体装入 `Arc<Mutex>` 跨线程共享，选择手工标记 `unsafe impl` 而非重构字段组合；`state()` 的 `&` 返回把「锁内借用」暴露为「可能跨锁存活」的接口。
- **成员差异（内部两点）**：`unsafe impl` 本身依赖脆弱外部 Mutex 不变量；`state()` 返回引用是放大该脆弱性的入口。

### 4. 具体修复步骤（⚠️ 先降风险顺序 + 独立风险评估）

> **顺序约束（重要）**：先做「低风险、可立即消除 UB 入口」的改动，再评估是否拆结构体；**先加回归测试锁定当前行为，再动 unsafe**。

**提交 1（低风险，先做）：`state()` 改为返回 Clone 类型**
1. 将 `pub fn state(&self) -> &WatchdogStateEnum`（118-120 行）改为 `pub fn state(&self) -> WatchdogStateEnum`（返回 `self.state.clone()`，`WatchdogStateEnum` 已 `Clone`）。同步更新所有调用方（`src/lib.rs`、`bridge.rs`、相关测试中 `watchdog.state()` 的匹配/比较处）由 `&` 解引用改为值比较。
2. 在 `state()` 文档注释补「返回快照，与锁生命周期解耦」。

**提交 2（回归测试先行，再动 unsafe）：**
3. 先加 `#[cfg(test)]`/`#[tokio::test]` 用例：验证 `ProcessWatchdog`/`JobObjectGuard` 可安全跨 `tokio::spawn` 移动并被 Mutex 保护访问（编译期 `Send/Sync` 断言 + 运行时行为不变），作为改动前的回归基线。

**提交 3（可选、更彻底）：消除手写 unsafe**
4. 评估将 `child: Option<Child>` 拆出，或将 `ProcessWatchdog` 数据面重构为「不含 `!Sync` 字段」以自动获得 `Sync`，从而可移除 67/73 行 `unsafe impl`；对 `JobObjectGuard` 评估改用 `windows` crate 的安全封装或加「不跨 Mutex 逃逸」的构造约束。
5. 若短期无法完全移除，至少在 4 处 `unsafe impl` 上方补充/强化 SAFETY 注释，明确「任何访问必须先持有外层 Mutex 锁，State 引用不得超出锁作用域」，并登记为待持续收敛项（不新增技术债未记录）。

### 风险评估（T5-01 专项，单列）

- **改动风险等级**：中。`state()` 返回类型变更会牵连所有调用点，但属机器可查的编译期错误（`&` 引用的匹配/比较会报错），风险可控。
- **拆分/移除 `unsafe impl` 的风险**：较高——涉及结构体字段组合与跨线程所有权模型，若错判可能引入真正的数据竞争。**必须在提交 2 的回归测试通过后**才进行，且每次改动单独 commit。
- **不推荐**：仅靠「文档注明引用不得跨锁存活」而不改代码——它无法阻止未来 UB，只能作为过渡期的临时护栏，最终仍应回到提交 1 + 提交 3。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  cd asd-tauri/src-tauri; cargo test --lib
  cd asd-tauri; cargo build
  ```
- **新增/回归用例**：
  - `state()` 返回值变更后：所有 `watchdog.state()` 调用方编译通过，`state()` 相关既有断言改为值比较继续通过。
  - 提交 2：新增跨线程移动 + 锁保护访问用例，保证 unsafe 改动前基线一致。
  - 若做提交 3：借 `cargo +nightly miri` 仅能覆盖纯逻辑 crate（asd-domain/asd-ipc-protocol/asd-application），watchdog 属 src-tauri 无法 Miri；改为 `#[cfg(test)]` 并发压力用例 + `cargo test --lib` 全绿。

### 6. 回滚机制

- 提交 1 为纯接口返回类型变更，`git revert` 即可恢复（调用点同步回退）；提交 3 如需回退，同样以单提交粒度 revert，不影响提交 1 已消除的 UB 入口。

### 7. 修复后效果评估标准

- `state()` 不再返回跨锁引用，`ProcessWatchdog`/`JobObjectGuard` 的 `unsafe impl` 依赖面收敛（或已移除）。
- 度量：`grep "unsafe impl" watchdog.rs` 数量由 4 处下降至 0（或剩余处均有强化 SAFETY 注释并登记在案）；`cargo test --lib` 全绿。

### 8. 责任角色 + 相对时间框

- **责任角色**：Rust 后端开发者（src-tauri，具备 unsafe/并发安全经验）。
- **相对时间框**：P1 短期，**1~2 个工作日**（含回归测试与 `cargo build` 回测）。

---

## 批次 6：vJoy 设备复用（T6-07）

### 1. 问题描述

- **T6-07**（`ahk_executor/joystick.ahk:299-317（_VJoyOpen/_VJoyClose）、360-395（_VJoySetBtn/_VJoySetAxis/_VJoySetPov）、444-454（_GetAxisInfo）、435-441（_IsAxis）`）：每次按键事件 `_VJoyOpen → _VJoyClose` 引用计数 0→1→0 快速往返，等价每次事件执行一次 `AcquireVJD` + `RelinquishVJD`，引用计数「持有期复用」完全失效；`_GetAxisInfo` 每次重建含 6 个子 Map 的新 Map，`_IsAxis` 每次重建数组，轴类键每次 down/up 产生 12 个 Map 分配。

### 2. 影响范围评估

- **受影响模块**：`ahk_executor/joystick.ahk`（vJoy 设备生命周期、轴键识别）。
- **用户路径**：joystick 周期性/序列/hold 模式的每一个 down/up 事件（高频）。
- **风险后果**：高频 `AcquireVJD/RelinquishVJD` 往返增加驱动调用开销与设备抖动；重建 Map 分配引起 GC 压力与延迟抖动。

### 3. 根本原因分析

- **共性根因**：vJoy 设备「即开即关」峰值复用 + 无缓存查询表构造——设备生命周期未提到组级，识别表未做一次性缓存。
- **成员差异**：设备句柄往返（299-395 行）与轴识别表重建（435-454 行）是两个独立子问题。

### 4. 具体修复步骤

**提交 1（设备生命周期提升，`ahk_executor/joystick.ahk`）**
1. 将 vJoy 设备生命周期提升到组级：组启动时 `_VJoyOpen()`（Acquire 一次），组停止/紧急释放时 `_VJoyClose()`（Relinquish 一次）。
2. 将 `_VJoySetBtn/_VJoySetAxis/_VJoySetPov`（360-395 行）中的 `_VJoyOpen/_VJoyClose` 包裹移除，运行期只做 `SetBtn/SetAxis/SetContPov`（依赖组级已 Acquire）。

**提交 2（识别表静态缓存，`ahk_executor/joystick.ahk`）**
3. 对 `_GetAxisInfo`（444-454 行）/`_IsAxis`（435-441 行）结果做 `static` 一次性缓存（构建一次映射表，后续查表），消除每次 down/up 的 12 个 Map 分配。

> 原子提交：提交 1（生命周期）与提交 2（缓存）各一个 commit；提交 1 需与紧急释放/组停止路径联动，务必覆盖 `emergency_release` 调用链。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- **新增/回归用例**（`tests/test_ahk_executor/test_joystick.ahk`，18 套件内扩展）：
  - 组启动 → 组停止全流程，断言 `_vJoyRefCount` 在组存活期为 1、停止后为 0，无「每事件 0↔1」往返（通过 mock `AcquireVJD/RelinquishVJD` 调用计数验证）。
  - `_GetAxisInfo`/`_IsAxis` 反复调用，断言返回对象为缓存实例（引用相等或计数器验证不再重建）。

### 6. 回滚机制

- 提交 1 若在紧急释放路径遗漏 Relinquish 导致设备占用泄漏，可单提交回退恢复「即开即关」；提交 2 为纯缓存，回退零风险。

### 7. 修复后效果评估标准

- 单次按键事件不触发 `AcquireVJD/RelinquishVJD`；组级生命周期跨度内 `_vJoyRefCount` 稳定为 1；轴识别表不再每事件重建。
- 度量：驱动调用计数（mock 观测）在组存活期内 Acquire=1/Relinquish=1；`test_joystick.ahk` 全部用例绿。

### 8. 责任角色 + 相对时间框

- **责任角色**：AHK 执行器开发者（joystick）。
- **相对时间框**：P1 短期，**1 个工作日**。

---

## 批次 7：隐式依赖与永真断言（T2-03、T2-04、T5-02）

### 1. 问题描述

- **T2-03**（`infrastructure/utils.ahk:13` → `json_parser.ahk:15` → `json_logger.ahk:16` → `utils.ahk`）：三模块形成三节点 `#Include` 环。因 AHK `#Include` 同路径只含一次，运行时暂不崩溃，但属耦合气味，加载顺序调整即触发「未定义符号」。
- **T2-04**（`infrastructure/config_store.ahk:95,14`）：`Set()` 调用 `JSONLogger.Log`，但仅 `#Include "..\lib\ahk2_lib\deepclone.ahk"`（14 行），未显式 `#Include "json_logger.ahk"`；独立加载（如测试）会抛 `Unknown class: JSONLogger`。
- **T5-02**（`src/lib.rs:606-615`）：`assert!(EXPECTED_TAURI_COMMAND_COUNT == 34)` 右侧 `34` 是独立字面量，与 `generate_handler![...]` 列表无绑定，新增第 35 个命令而忘记更新时两个 34 仍相等，编译照常通过——「常量自比」永真式，不构成数量守护。

### 2. 影响范围评估

- **受影响模块**：AHK `infrastructure/utils.ahk/json_parser.ahk/json_logger.ahk/config_store.ahk`；Rust `src/lib.rs`。
- **用户路径**：模块独立加载/单测依赖顺序；维护者在增删 Tauri command 后依赖该断言获得虚假安全感。
- **风险后果**：加载顺序敏感（脆弱）；独立加载崩溃；命令数量漂移无编译期护栏。

### 3. 根本原因分析

- **共性根因**：模块边界声明不全/有错误依赖，且用「形式上的守护」掩盖真实守卫缺失。
- **成员差异**：T2-03 是「环」——`utils` 为兼容 JSON 字符串输入内联调 `JSONParser.Parse`，把解析能力耦合进最底层工具；T2-04 是「缺 include」——依赖外部加载顺序；T5-02 是「伪断言」——`generate_handler!` 编译期不暴露 item 数量，作者用常量自比伪造追踪点。

### 4. 具体修复步骤

**提交 1（T2-03，打破环，`infrastructure/utils.ahk` 为主）**
1. 移除 `utils.ahk:13` 的 `#Include "json_parser.ahk"`。将 `_GetField`（41-55 行）对 JSON 字符串的解析能力抽取——由调用方先解析后传入（推荐），或将 `JSONParser.Parse` 依赖上提到日志/解析层调用点，保证 `utils.ahk` 零依赖下层解析器。
2. 若无调用方依赖 `_GetField` 的「JSON 字符串自动解析」能力，直接删除该分支（41-55 行中的 `IsString` 解析段），仅保留 Map/Object 属性访问。
3. 确认 `json_logger.ahk:16` 的 `#Include "utils.ahk"` 与 `json_parser.ahk:15` 的 `#Include "json_logger.ahk"` 在去除 `utils → json_parser` 后不再形成环（追溯 `main.ahk` 固定加载顺序仍先 log、再 parser、再 config_store）。

**提交 2（T2-04，`infrastructure/config_store.ahk`）**
4. 在 `config_store.ahk:14` 后补 `#Include "json_logger.ahk"`（视需要补 `#Include "json_parser.ahk"` 以获得 `JSONErrorType`），使模块声明依赖自足。

**提交 3（T5-02，`src/lib.rs`）**
5. 删除 613-615 行的永真式 `const _: () = { assert!(...) }` 与 606 行 `EXPECTED_TAURI_COMMAND_COUNT`（或降级为普通 `#[cfg(test)]` 测试/文档注释）。
6. 改为「测试中真实统计已注册命令数」比对：在 `#[cfg(test)]` 中枚举 `generate_handler![...]` 列表长度与文档/常量比对（可通过 `tauri::generate_handler` 的返回宏或手工维护命令清单数组做长度断言）。若短期无法真实统计，将注释改写为「此值仅供文档参考，无编译期强制」，并登记到 test-map.md 的「命令清单」章节维护。

> 原子提交：三个关注点各一个 commit；提交 1 与提交 2 同属 AHK 基础设施，建议先做提交 1（环）再做提交 2（include 自足），避免环未断时补 include 反而强化环。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  cd asd-tauri/src-tauri; cargo test --lib
  ```
- **新增/回归用例**：
  - T2-03：独立加载 `infrastructure/utils.ahk` 单测（不依赖其他 include）验证 `_GetField` 仍工作、无「环」导致的未定义符号。
  - T2-04：单独 `#Include "config_store.ahk"` 的最小测试脚本，断言不再抛 `Unknown class: JSONLogger`。
  - T5-02：`#[cfg(test)]` 断言 `generate_handler!` 命令清单长度 == 期望值，验证「新增命令但忘更新清单」会失败。

### 6. 回滚机制

- 提交 1 若导致 `_GetField` JSON 字符串解析能力缺失且有调用方依赖，需先补「调用方先解析」再提交；回退单提交即恢复旧依赖（环恢复但可接受作为过渡）。
- 提交 2/3 为纯补 include/删断言，回退零风险。

### 7. 修复后效果评估标准

- `utils.ahk` 不再 `#Include` `json_parser.ahk`（环打破）；`config_store.ahk` 独立加载不崩；`src/lib.rs` 无永真式命令计数断言，命令清单长度由测试真实统计守护。
- 度量：`grep '#Include "json_parser.ahk"' utils.ahk` 返回空；`grep 'EXPECTED_TAURI_COMMAND_COUNT' lib.rs` 除注释外为 0 或仅限 `#[cfg(test)]`。

### 8. 责任角色 + 相对时间框

- **责任角色**：AHK 基础设施开发者（提交 1/2）+ Rust 后端开发者（提交 3）。
- **相对时间框**：P1 短期，**0.5~1 个工作日**。

---

## 批次 8：输入误报与注入检查（T3-04、T3-06）

### 1. 问题描述

- **T3-04**（`presentation/gui_manager.ahk:408-438`）：`GlobalSettingsEditor._Save` ① 422-424 行直接 `Integer(Edit.Text)`，非数字抛 `ValueError` 被外层 catch 吞掉、无提示；② 432 行 `ConfigService.SaveConfig()` 返回值被忽略，433 行无条件 `MsgBox("全局设置已保存")`，保存被验证阻止时仍报「已保存」，重启后丢失。与 `WebView2Manager._BridgeSaveSettings` 完整校验+回滚+返回值处理不一致。
- **T3-06**（`domain/joystick_executor.ahk:55,107,157-160`）：`_SendJoyKey` 第 159-160 行在 `try` 外抛「JoySender 未注入」异常，向上传播到 `Execute` 的 catch → 每次 tick 记一次 ERROR 日志（与 T3-05/T6-03 叠加放大高频写盘）；`JoystickHoldExecutor.Execute`（136-137 行）同样受影响。

### 2. 影响范围评估

- **受影响模块**：`presentation/gui_manager.ahk`；`domain/joystick_executor.ahk`（`JoystickPeriodicExecutor`/`JoystickSequenceExecutor`/`JoystickHoldExecutor`）。
- **用户路径**：桌面 GUI 保存全局设置；joystick 模式启动/运行。
- **风险后果**：用户被误导「已保存」但配置丢失；joystick 模式未注入时每 tick 高频 ERROR 日志风暴。

### 3. 根本原因分析

- **共性根因**：错误处理放错位置/粒度——一个「校验失败后误报成功」，一个「注入检查放在热路径而非模式启动前」。
- **成员差异**：T3-04 是 GUI 保存路径缺逐字段校验 + 忽略返回值；T3-06 是注入检查时点错误。

### 4. 具体修复步骤

**提交 1（T3-04，`presentation/gui_manager.ahk`）**
1. 在 `_Save`（408-438 行）对 `debounceDelay/checkInterval/pressSpeed` 逐字段 try-catch 转换：`try Integer(text) catch { MsgBox("字段 X 需为数字","错误","Icon!") return false }`，非法时提示并中止，不再吞异常静默。
2. 检查 `ConfigService.SaveConfig()` 返回值（432 行）：失败 → `MsgBox("保存失败: ...","错误","Icon!")`；成功 → 才 `MsgBox("全局设置已保存")` + `Destroy()`。对齐 `WebView2Manager._BridgeSaveSettings` 的校验+回滚+返回值处理模式。

**提交 2（T3-06，`domain/joystick_executor.ahk`）**
3. 在 joystick 模式激活前（`Toggle`/`_SetupMode`，即 `SetJoySender` 注入之后、`Execute` 循环启动之前）完成 `_joySender` 注入检查：未注入 → 一次性报 ERROR/告警并阻止进入执行循环，避免每 tick 重复抛异常。
4. 将 `_SendJoyKey` 内部（159-160 行）的注入检查保留为「防御性二次检查」或在已前置检查的前提下改为 assert/静默跳过，确保不再进入每 tick 异常路径。

> 原子提交：二者无关，可分两个 commit 并行。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut asd.ahk
  & "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run_all_tests.ahk
  ```
- **新增/回归用例**：
  - T3-04：`_Save` 输入非数字（如 "abc"）→ 断言弹出错误提示且 `SaveConfig` 未被调用或返回未成功；`SaveConfig` 返回 false 时断言不弹「已保存」。
  - T3-06：未注入 `JoySender` 时激活 joystick 分组 → 断言「激活前」拦截、`Execute` 不进入高频异常；日志无每 tick ERROR 风暴（可计数验证）。

### 6. 回滚机制

- 提交 1 为 GUI 保存路径加校验/返回值处理，回退单提交恢复旧行为；提交 2 为注入检查前置，回退零风险。

### 7. 修复后效果评估标准

- 全局设置保存失败时用户看到「保存失败」而非「已保存」；joystick 未注入时仅启动期拦截一次，运行期无高频 ERROR。
- 度量：`GlobalSettingsEditor._Save` 对 3 个数字字段存在 catch 且检查 `SaveConfig()` 返回值；joystick 未注入场景 `logs/app.log` ERROR 计数 ≤ 1（非每 tick）。

### 8. 责任角色 + 相对时间框

- **责任角色**：AHK 表现层开发者（T3-04）+ AHK 领域层开发者（T3-06）。
- **相对时间框**：P1 短期，**0.5~1 个工作日**。

---

## 批次 9：测试覆盖补强（T8-01、T8-02、T8-03）

### 1. 问题描述

- **T8-01**（`src/infrastructure/ipc.rs`，`listen_ahk` 消息解析/分发）：消息接收循环（accept → 解析 `IpcMessage` JSON → 按 `type` 分发 hotkey/heartbeat/recording）缺直接单测；malformed JSON、未知 type、空 data 等边界无白盒覆盖。
- **T8-02**（`src/lib.rs` `perform_graceful_shutdown`）：仅 `infrastructure::shutdown::try_acquire_shutdown_guard` 被提取测试；关机主体（发送 `IpcCommand::Shutdown`、停止 watchdog、销毁窗口、二次调用拦截）无测试。
- **T8-03**（`asd-tauri/e2e/specs/*.spec.js`，9 文件，例 `config_cmd.spec.js:32-95`）：① 9 个 spec 各自复制「binary 检测 → skip / backup-restore / appendResult + appendKnownIssue」四段约 60 行/spec 共 ~500 行重复；② `appendKnownIssue` 严重级别硬编码 `'HIGH'`；③ caseId 提取正则各自硬编码，编号体系脆弱。

### 2. 影响范围评估

- **受影响模块**：`src/infrastructure/ipc.rs`、`src/lib.rs`、`asd-tauri/e2e/specs/` 及 helpers。
- **用户路径**：无直接用户路径，属回归保障缺口（IPC 分发、优雅关机、E2E 生命周期）。
- **风险后果**：核心分发与关机流程改动无回归保护；E2E 维护成本高、失败上报级别失真、caseId 脆弱。

### 3. 根本原因分析

- **共性根因**：「可测试部分」未从 async/生命周期方法中抽离为纯函数/mock 友好的 seam。
- **成员差异**：T8-01 是 `listen_ahk` async 未抽 parse+dispatch 纯函数；T8-02 是关机主体缺 `asd-test-harness` mock 驱动；T8-03 是 E2E spec 缺共享 base hook。

### 4. 具体修复步骤

**提交 1（T8-01，`src/infrastructure/ipc.rs`）**
1. 参照 `infrastructure::shutdown::try_acquire_shutdown_guard` 模式，抽取 `parse_and_dispatch(message_bytes) -> Option<DispatchAction>`（或 `parse_message(&[u8]) -> Result<IpcMessage, _>` + `dispatch(msg) -> DispatchAction`）纯函数，将「解析 → 按 type 分发」与 I/O 解耦。
2. 补 `#[cfg(test)] mod tests` 单测覆盖三分支（hotkey/heartbeat/recording）与 malformed JSON、未知 type、空 data 边界。

**提交 2（T8-02，`src/lib.rs` + `asd-test-harness`）**
3. 复用 `asd-test-harness` 的 mock `IpcSender`/`ProcessWatcher`，为 `perform_graceful_shutdown` 补序列集成测试：断言「锁未获取 → 提前返回 / 锁获取后 → 按序调用 IPC Shutdown + watchdog stop / 二次调用被拦截」。

**提交 3（T8-03，`asd-tauri/e2e/`）**
4. 抽 `helpers/spec-hooks.js` 导出统一 `before/afterEach`（binary 检测→skip、config backup/restore、结果上报），替换 9 个 spec 的重复段。
5. `appendKnownIssue` 严重级别改从 test 元数据传入或按错误类型推断，移除硬编码 `'HIGH'`；caseId 提取统一为共享函数（`E2E-<SUITE>-NNN` 解析收敛一处）。

> 原子提交：三个关注点各一个 commit；提交 3 主要影响 E2E 文件，改动后需 `npm test` 回绿。

### 5. 测试验证方案

- **验证命令**：
  ```powershell
  cd asd-tauri/src-tauri; cargo test --lib
  cd asd-tauri/e2e; npm test
  ```
- **新增/回归用例**：
  - T8-01：`parse_and_dispatch` 单测覆盖 3 分支 + 3 类边界（malformed/未知 type/空 data）。
  - T8-02：shutdown 序列集成测试 2~3 场景。
  - T8-03：`npm test` 全绿且 9 个 spec 行数显著下降（重复段去除）。

### 6. 回滚机制

- 均为「新增测试/重构测试基建」，不影响生产代码路径（提交 1 的纯函数抽取属等价重构，若行为偏差可单提交回退）。

### 7. 修复后效果评估标准

- IPC 分发与优雅关机有白盒/序列测试护航，边界用例覆盖三分支；E2E 冗余代码减少（~500 行重复收敛到共享 hook），失败级别与 caseId 提取统一。
- 度量：`cargo test --lib` 新增用例绿；`grep appendKnownIssue` 无 `'HIGH'` 硬编码；caseId 正则仅一处。

### 8. 责任角色 + 相对时间框

- **责任角色**：测试/QA 工程师（配合 Rust 后端开发者抽 seam）。
- **相对时间框**：P1 短期，**1~2 个工作日**。

---

## 批次 10：文档严重漂移（T7-02、T7-03、T7-04、T7-05）

### 1. 问题描述

- **T7-02**（`docs/migration-guide.md` §1.1(L42)、§3.4(L296-306)、§4.1(L421)、§4.3(L517)、§5.4.6(L562)）：引用已迁移/删除 API——`src-tauri/` 下三目录 +「13 个 Tauri Commands」；§3.4 IpcCommand 表仅 9 变体（缺 4）；§4.1 称 `Config::load_from_file()` 负责 BOM、§5.4 称 `Config::save()` 用 `to_string_pretty()`（已迁到 `ConfigRepository`）；§4.3 把 `GroupSettings` 标为 `HashMap`（实际 `IndexMap`）。
- **T7-03**（`asd-tauri/TESTING.md` L6、L8、L133-146）：反复要求 `--features test-manifest`（`src-tauri/Cargo.toml` 已无 `[features]`）；L8「3 个 fuzz target」实际 5 个；L6「506+ Rust 测试函数」与 test-map「609」冲突。
- **T7-04**（`asd-tauri/docs/test-map.md` L15-19、L27-32、L69、L80-99、L146）：汇总表与明细不一致——asd-tauri 明细「小计 153」+ manifest 1 = 154，但「总计 217」差 63；asd-ipc-protocol 明细 71 但汇总 72；asd-test-harness 明细 0 但汇总 4；逐文件计数大量过时（bridge_tests 13→4、config_cmd 7→29、group_cmd 4→20 等）。
- **T7-05**（`AGENTS.md` L135/L340/L274 vs `test-map.md` L146-147 vs `TESTING.md` L6-8）：测试统计口径跨文档冲突——Rust「592」vs「609」、执行器「244」vs「467」、AHK v2「581」无法对账；AGENTS 头部时间戳「Updated 2026-05-30」与正文「截至 2026-08-04」矛盾。

### 2. 影响范围评估

- **受影响文档**：`docs/migration-guide.md`、`asd-tauri/TESTING.md`、`asd-tauri/docs/test-map.md`、`AGENTS.md`。
- **用户路径**：开发者按过期文档操作/测试（跑 `--features test-manifest` 失败、按错误统计预期偏差、找不到目录/文件）。
- **风险后果**：误导、断链、统计无权威来源、维护者决策被错误数据影响。

### 3. 根本原因分析

- **共性根因**：多文档独立修订、统计日期与计数口径未统一、无单一权威来源；I/O 崩溃修复与 crate 抽取后未回填。
- **成员差异**：T7-02 是 API/结构过时（写于 I/O 泄漏修复与 workspace 化之前）；T7-03 是 feature 移除与 fuzz 增长未同步；T7-04 是 test-map 明细与汇总未同步；T7-05 是跨文档统计口径冲突。

### 4. 具体修复步骤

**提交 1（T7-02，`docs/migration-guide.md`）**
1. I/O 引用改为 `ConfigRepository`（§4.1 L421、§5.4 L562：`Config::load_from_file`/`Config::save` → `ConfigRepository` 对应方法）。
2. §3.4 IpcCommand 表（L296-306）补 13 变体（补齐 `PauseRecording/ResumeRecording/StartValidation/StopValidation`）；§1.1「13 commands」改 34；§4.3 `GroupSettings` 的 `HashMap` 改 `IndexMap`；`src-tauri/` 三目录描述对齐 5-member workspace。

**提交 2（T7-03，`asd-tauri/TESTING.md`）**
3. 删除所有 `--features test-manifest` 命令与「关键提示」（L6、L133-146）；fuzz 数量 3 改 5 并补全命令；Rust 测试数与 test-map 对齐单一口径（见提交 4）。

**提交 3（T7-04，`asd-tauri/docs/test-map.md`）**
4. 按文档自带统计命令重新全量统计，逐行更新明细表（L15-19、L27-32、L69、L80-99、L146），使「小计 = 明细之和 = 汇总」一致（消除差 63、明细 71 vs 汇总 72、明细 0 vs 汇总 4 等）。

**提交 4（T7-05，`AGENTS.md` + 跨文档收口）**
5. 确立 `asd-tauri/docs/test-map.md` 为唯一测试统计来源；统一注明口径（`#[test]` 属性数 / `Test_` 方法数 / 断言数分别标注，解决 592 vs 609、244 vs 467、581 无法对账）。更新 `AGENTS.md` 头部 `Updated` 时间戳（修正为最近一次真实更新日期，与正文「截至 2026-08-04」及后续升级一致）。

> **统计口径建议（须修正的具体口径）**：
> - Rust 总数：以 `cargo llvm-cov`/`cargo test -- --list` 或 `analyze-tests.ps1` 实际输出的 `#[test]` 数为准，统一一处。
> - AHK 执行器：明确是「Test_ 方法数」还是「断言/套件数」，消除 244 vs 467 双口径。
> - AHK v2：581 若只能在 AGENTS 出现，需补一份可复算出处或标注「不可交叉验证，待补」。
> - 原子提交：四个文档各一个 commit；提交 4 依赖提交 3（数据对齐后）、提交 2（test-manifest 清理后）完成再统一写「权威来源」结论。

### 5. 测试验证方案

- 文档批次无代码测试命令；验证方式为**文本核验**：
  ```powershell
  grep -n "test-manifest" asd-tauri/TESTING.md   # 期望无残留
  grep -rn "592\|609\|244\|467" asd-tauri/TESTING.md asd-tauri/docs/test-map.md AGENTS.md  # 期望仅单一权威值
  ```
- 一致性核验：`test-map.md` 明细小计 == 汇总 == 总计（手工/脚本加和）；`migration-guide.md` 无 `HashMap`/`Config::load`/`Config::save`/「13 commands」残留。

### 6. 回滚机制

- 纯文档提交，`git revert` 即完全回退，无运行时影响。

### 7. 修复后效果评估标准

- `migration-guide.md` 与 5-member workspace + `ConfigRepository` + 13 变体 IpcCommand + `IndexMap` + 34 commands 一致；`TESTING.md` 无 `test-manifest` 残留、fuzz=5；`test-map.md` 三点口径自洽；`AGENTS.md` 统计与 test-map 单一口径一致、头部时间戳修正。
- 度量：上述 grep 核验项全部通过；四文档间同一统计量仅出现一个权威值。

### 8. 责任角色 + 相对时间框

- **责任角色**：文档/技术写作者（配合各主题对口开发者核对事实）。
- **相对时间框**：P1 短期，**1~2 个工作日**（建议放在代码批次收口后进行，避免又漂移）。

---

## 附：P1 执行顺序建议与整体时间框

- **整体时间框**：P1 = 短期，全部 10 批建议 **≤ 2 周**（可部分并行）。
- **建议执行顺序**（按依赖与风险）：
  1. G3（定时器）→ G6（vJoy）→ G8（注入检查）—— AHK 执行器/领域层热路径，联动回归。
  2. G4（IPC 背压）→ G5（unsafe）—— src-tauri 后端，统一 `cargo test --lib` 回归。
  3. G1（校验）→ G7（隐式依赖/永真断言）→ G2（日志限速）。
  4. G9（测试补强）—— 与上述代码批次并行/交叉。
  5. G10（文档）—— 最后收口，待 G9 完成后再核最终统计数。
- **每批交付物**：对应文件的原子提交 + 用例 + 本计划 §4/§5 所述验证结果。