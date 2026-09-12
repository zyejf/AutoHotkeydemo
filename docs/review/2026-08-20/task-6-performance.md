# 跨栈性能优化专项审查报告（Task 6）

- 日期：2026-08-20
- 范围：AHK v2 执行热路径 + AHK 基础设施 + Rust↔AHK IPC + AHK 执行器子进程
- 性质：只读审查（未修改任何 .ahk / .rs 文件）

---

## 执行摘要

本次审查覆盖 14 个文件：AHK 领域层（skill_manager / skill_group / mode_registry / joystick_executor）、基础设施层（error_system / json_logger / debug_logger / json_parser / json_serializer / utils / ipc_channel）、Rust 端（ipc.rs / bridge.rs）、AHK 执行器子进程（executor / sender / ipc_client / hotkey_hook / joystick）。

**总体结论**：按键连招的真正热路径在 `asd-tauri/src-tauri/ahk_executor/sender.ahk`（及领域层 `skill_group.ahk` 的按键发送）。当前最大的性能风险不是"算法复杂度过高"，而是 **热路径上无条件执行 IPC 序列化 + 同步阻塞写命名管道、以及每次按键按下都创建新闭包 + 一次性定时器** 这两类高频分配/阻塞操作。Rust 端的 `block_in_place + block_on` 与消息 `clone()` 为次要风险，但已有文档背书。

**合规项（未发现违规）**：
1. ✅ 周期性触发**全部**使用独立触发时间（`_lastTriggerTimes[i]` / `_groupTriggerTimes["grpIdx.i"]` / executor 的 `triggerTimes[i]`），未发现 `Mod(A_TickCount, interval)` 违规（规范要求）。
2. ✅ 定时器采用自适应重臂：`SetTimer(fn, -nextPoll)` 一次性触发，`nextPoll = min(剩余时间)`，避免固定周期忙轮询。
3. ✅ Rust 侧 `HotkeyMerger` 对 hotkey 事件做合并窗口（100ms），`pending_responses` 有 30s 周期清理，`recv()` 用 `take(MAX_MESSAGE_SIZE)` 限制单消息大小，`MAX_DISCARD_SIZE` 限制超大残余数据。
4. ✅ 领域层 `skill_group` 用 `_validKeysMap` 缓存按键名白名单，避免每次 `_IsValidKeyName` 重建 Map。
5. ✅ `deepclone` **未出现在执行热路径**（仅用于 config_store Save/Load/Get 与 group_service 的配置保存路径），不构成执行循环开销。

---

## 发现清单

### T6-01 [Critical] 每次按键 down/up 无条件执行 IPC 序列化 + 同步阻塞写管道

- **位置**：`asd-tauri/src-tauri/ahk_executor/sender.ahk:494-522`（`_SendKeyDown`/`_SendKeyUp`）、`asd-tauri/src-tauri/ahk_executor/ipc_client.ahk:792-818`（`_SendMsg`）、`ipc_client.ahk:533-541`（`CreateFileW` 未传 `FILE_FLAG_OVERLAPPED`）
- **维度**：性能优化
- **严重级别**：Critical
- **描述**：`_SendKeyDown` 和 `_SendKeyUp` 每次按键动作都调用 `IpcClient._SendMsg(Map("type","key_send_event",...))`，无条件把每个 key down/up 事件上报给 Rust。`_SendMsg` 内部执行：`MiniJson.Stringify`（递归序列化，含 `parts` 数组分配）→ 两次 `StrPut`（一次测长、一次写入）→ `Buffer` 分配 → 同步 `WriteFile` DllCall（管道以无 `FILE_FLAG_OVERLAPPED` 方式打开，写为阻塞式）。周期性模式 50ms 间隔下单键 = 每秒 20 down + 20 up = 40 次消息，每次消息 2 次 JSON 序列化 + 2 次 Buffer 分配 + 2 次同步管道写。
- **根因**：`key_send_event` 仅用于前端展示/验证反馈，却与"按下/释放按键"这一最热路径强耦合；且管道写为同步阻塞，无 ONESHOT/OVERLAPPED，也无背压上限。
- **优化方案**：
  1. 默认**关闭**逐键 IPC 上报，仅在录制（`_recordState = "recording"`）或验证（`_validationGroupId != ""`）模式下才发送 `key_send_event`；常态执行只发 `down` 键码不发送或改用批量聚合。
  2. 若必须上报，改为**批量缓冲 + 定时刷新**（如每 50-100ms 汇总一批，复用 HotkeyMerger 思路），把每键一次 WriteFile 降为每批一次。
  3. 管道写入改为非阻塞/异步，至少对 `WriteFile` 失败做降级（不发则跳过上报）而非阻塞 AHK 消息循环。
- **预期收益**：消除热路径上约 2×/按键的串行化+系统调用，高间隔（10ms）多键场景下 CPU 与 IPC 吞吐量可降低一个数量级以上，且解耦"前端卡顿 → AHK 执行冻结"的反向背压。

---

### T6-02 [Important] 每次按键按下创建新闭包 + 一次性 SetTimer（多文件）

- **位置**：`domain/skill_group.ahk:800-805`；`asd-tauri/src-tauri/ahk_executor/sender.ahk:347,394,444,464`；`asd-tauri/src-tauri/ahk_executor/joystick.ahk:203,253`；`domain/joystick_executor.ahk:55,107`
- **维度**：性能优化
- **严重级别**：Important
- **描述**：每次"按下"都用 `SetTimer(((ck) => () => ..._SendKeyUp(ck))(capturedKey), -kpd)` 现造一个闭包并注册一次性定时器。领域层 `_SendKey` 还额外构造 `releaseTimer` 闭包（捕获 4 个变量）并做 `HasProp("_pendingReleases")`/`HasProp("_releaseCounter")` 冗余检查（这些属性已在 `__New` 预初始化）。executor 的 sender.ahk / joystick.ahk 中这些一次性 "up" 定时器**未纳入任何 `_timers`/`_releaseTimers` 跟踪**，分组停止时不会取消，虽然一次性定时器会自动消亡，但在停止瞬间仍可能滞后发送一次 key up。
- **根因**：为了"按下后延时释放"，采用逐键建闭包 + 逐键注册定时器的模式，未复用可复用的释放通道。
- **优化方案**：参考 `skill_group` 已有的 `_releaseTimers` 思路，把 up 定时器引用登记进 Map（`_releaseTimers[key]`）以便停止时统一取消；对 executor 层更优做法是维护"已按下键集合 + 单一周期释放扫描定时器"，一次扫描统一释放到期键，将 O(按键数) 的闭包/定时器创建降为 O(1) 的周期扫描。
- **预期收益**：高频模式（10ms 间隔）从每秒数百次闭包分配 + 数百个一次性定时器降到固定 1 个扫描定时器；同时修复停止时滞后释放的边界问题。

---

### T6-03 [Important] 错误/日志写盘无限速，异常路径每次同步 FileAppend

- **位置**：`infrastructure/error_system.ahk:185-213`（`_WriteLog` → `FileAppend`）；`infrastructure/json_logger.ahk:179-227`（`_WriteLog`/`_LogToFile` → `FileAppend`）；`infrastructure/debug_logger.ahk:22,52-56`
- **维度**：性能优化（热路径日志限速）
- **严重级别**：Important
- **描述**：AGENTS.md 声称"热路径日志（Execute* 方法）会自动限速，每秒最多记录一次"，但实际代码中：① `ErrorSystem._WriteLog` **无任何限速**，每次 `LogError` 都同步 `JSONSerializer.Stringify` + `FileAppend` 落盘；② `JSONLogger._WriteLog` 同样无线速且 `_ShouldLog` 恒为 true；③ 唯一有限速的是 `DebugLogger`，但仅对 `DEBUG` 级别、间隔为 **50ms 而非"每秒一次"**。`_SendKey`/`_ReleaseKey`/各 `Execute` 的 catch 块都直接调用 `ErrorSystem.LogError`（有时还叠加 `SkillGroup._Log`），若按键发送在某场景下持续抛错（如 SendInput 失败、KeyValidator 抛错），同一执行循环内会以 10-50ms 周期反复进行 2 次序列化 + 2 次同步写盘，磁盘 I/O 直接拖垮执行循环。
- **根因**：错误路径缺少令牌桶/滑动窗口限速；AGENTS.md 中"每秒最多一次"的承诺仅在 DebugLogger 的 DEBUG 级别部分实现，未覆盖 ErrorSystem / JSONLogger。
- **优化方案**：给 `ErrorSystem` 与 `JSONLogger` 各加一个与 `DebugLogger` 同构的限速器（如 `_lastWriteTime` + `_suppressedCount`），同一调用源在限速窗口内只落盘一次并批量计数；异常路径改为"记内存计数 + 限速落盘"。同步将 DebugLogger 的 50ms 与文档"每秒一次"口径对齐或修正文档。
- **预期收益**：异常风暴时避免每周期同步磁盘 I/O，恢复执行节奏；消除文档与实现的不一致。

---

### T6-04 [Important] 重复激活已激活分组时覆盖定时器引用、未先取消旧定时器

- **位置**：`asd-tauri/src-tauri/ahk_executor/sender.ahk:178-194`（StartPeriodic）、`:197-215`（StartSequence）、`:290-305`（StartHybrid）、`joystick.ahk:68-85`；触发入口 `executor.ahk:102-107`（`_HandleToggleGroup` active=true 无条件 `_StartGroupWithConfig`）
- **维度**：性能优化（定时器生命周期）
- **严重级别**：Important
- **描述**：`StartPeriodic/StartSequence/StartHybrid/Joystick.StartPeriodic` 每次都 `Sender._timers[groupId] := timerFn; SetTimer(timerFn, 10)`，**直接覆盖**该 groupId 的旧定时器引用，却不先 `SetTimer(旧引用, 0)`。当同一个已激活分组被再次下发 `toggle_group(active=true)`（典型发生在 Rust 端 `post_connect_callback` 重连恢复命令、或前端重复触发）时，会注册一个新的周期定时器，旧的周期定时器仍在运行，形成**重复定时器 → 重复/加倍发键**，且旧引用丢失后无法停止，只能等 `EmergencyRelease`/关机兜底。
- **根因**：启动路径缺少"若已存在定时器则先取消再覆盖"的幂等保护；`_StartGroup` 虽做了 `_activeGroups.Has` 早退，但紧随其后的 `StartXxx` 仍会重复注册定时器。
- **优化方案**：每个 `StartXxx` 开头加 `if Sender._timers.Has(groupId) { SetTimer(Sender._timers[groupId], 0); Sender._timers.Delete(groupId) }` 再注册；或在 `_HandleToggleGroup`/`_StartGroupWithConfig` 层面判断"已激活且配置相同"则直接返回。Joystick 侧同样处理。
- **预期收益**：杜绝重连/重复触发导致的重复定时器与双倍发键，避免定时器累积。

---

### T6-05 [Important] bridge.rs `block_in_place + block_on`；`send()` 无超时，AHK 挂起可无限阻塞工作线程

- **位置**：`asd-tauri/src-tauri/src/bridge.rs:44-67`（`send_command`）、`:69-129`（`send_and_wait`）；`asd-tauri/src-tauri/src/infrastructure/ipc.rs:290-327`（`send`，`write_all`/`flush` 无超时）
- **维度**：性能优化（IPC 阻塞 / executor 线程）
- **严重级别**：Important
- **描述**：`IpcSender` trait 是同步签名，实现用 `tokio::task::block_in_place` + `Handle::current().block_on` 桥接。`send()` 的 `write_all().await` + `flush().await` 没有任何 `tokio::time::timeout`：若 AHK 子进程挂死且管道缓冲区写满，写操作会无限期阻塞，进而把调用方所在工作线程（block_in_place 转成阻塞线程）长期占用。多个 Tauri command 并发调用时可能耗尽线程池。此点已在代码注释中声明为"已知妥协 #2"，但从性能/延迟角度仍属风险（尤其 `send_and_wait` 依赖响应超时，而纯 `send` 无超时）。
- **根因**：同步 trait 与异步 IpcManager 的桥接模式本身引入了阻塞；`send` 缺少写超时兜底。
- **优化方案**：给 `send()` 增加可选的写超时（如 `tokio::time::timeout` 包住 `write_all`+`flush`，超时判定管道不通并触发 `notify_pipe_broken`）；长期方向是让 `IpcSender` 方法返回异步或在应用层以 async 方式调用，避免 `block_in_place`。
- **预期收益**：避免 AHK 挂起时主进程工作线程被无限阻塞、命令无响应。

---

### T6-06 [Important] `listen_ahk` 每条消息 `msg.clone()` 无差别拷贝 + 背压无界传导

- **位置**：`asd-tauri/src-tauri/src/infrastructure/ipc.rs:545`（`dispatch_response(msg.clone())`）、`:567-572`（`outbound_tx.send(msg).await`）、`:504`（内部 channel 容量 64）、`:18`（`IPC_CHANNEL_CAPACITY=512`）
- **维度**：性能优化（IPC 消息处理）
- **严重级别**：Important
- **描述**：列表循环中先 `dispatch_response(msg.clone())`——即使绝大多数消息不是响应（如 hotkey/key_send/key_record），也会为每条消息做一次 `IpcMessage` 深拷贝（其 `data` 是 `serde_json::Value`，克隆成本不低）。而后 `outbound_tx.send(msg).await` 采用 `.await`（非 `try_send`），当 outbound 消费端（前端事件转发）变慢时，监听循环被阻塞，进一步经 recv 任务 → OS 管道缓冲 → AHK 端同步 `WriteFile` 反向压死（与 T6-01 构成同一回路）。
- **根因**：先用 clone 再判断响应归属，未先检查 `msg.ack_seq`；outbound 无丢弃/合并策略，慢消费者会反向阻塞整个读链路。
- **优化方案**：先 `if msg.ack_seq.is_some()` 再决定是否 clone，避免非响应消息的无谓拷贝；对 `key_send_event` 类高频非关键消息采用 `try_send` + 满则丢弃/合并（保留关键 hotkey 用 `.await`），或在 outbound 消费端加解码/转发背压上限。
- **预期收益**：降低每消息一次 `Value` 深拷贝的 GC/分配开销；切断"前端慢 → AHK 执行冻结"的级联。

---

### T6-07 [Important] joystick 每次按键事件 vJoy AcquireVJD/RelinquishVJD + `_GetAxisInfo` 每次重建多个 Map

- **位置**：`asd-tauri/src-tauri/ahk_executor/joystick.ahk:299-317`（`_VJoyOpen`/`_VJoyClose`）、`:360-395`（`_VJoySetBtn`/`_VJoySetAxis`/`_VJoySetPov`）、`:444-454`（`_GetAxisInfo`）、`:435-441`（`_IsAxis`）
- **维度**：性能优化
- **严重级别**：Important
- **描述**：`_VJoySetBtn`/`_VJoySetAxis`/`_VJoySetPov` 每次都 `_VJoyOpen()` → `_VJoyClose()`。由于一次按键事件只做一次 down（或一次 up），引用计数在 `0→1→0` 之间快速往返，**等价于每次按键事件执行一次 AcquireVJD + 一次 RelinquishVJD**（设备获取/释放），引用计数保护的"持有期间复用"效果完全未生效。此外 `_GetAxisInfo` 每次调用重建一个含 6 个子 Map 的新 Map（`_AxisToVJoyId` 与轴方向发送都会调用），`_IsAxis` 每次重建数组，轴类键每次 down/up 都会产生 12 个 Map 分配。
- **根因**：资源"即开即关"峰值复用 + 无缓存的查询表构造。
- **优化方案**：将 vJoy 设备生命周期提升到组级（组启动时 Acquire，组停止/紧急释放时 Relinquish），运行期只做 `SetBtn/SetAxis/SetContPov`；对 `_GetAxisInfo`/`_IsAxis` 结果做 static 缓存（一次性构建后复用）。
- **预期收益**：消除手柄模式逐键事件的设备获取/释放与重复对象分配，明显降低 joystick 模式的 CPU 开销（随 vJoy 设备操作成本不同，幅度可观）。

---

### T6-08 [Minor] IPCChannel（AHK 预留文件管道）每次 Send/Emit 做 FileGetSize 磁盘 IO

- **位置**：`infrastructure/ipc_channel.ahk:66-86`（Send）、`:89-109`（Emit）、`:192-204`（`_EnforcePipeSize`）、`:112-170`（`PollMessages`）
- **维度**：性能优化
- **严重级别**：Minor
- **描述**：该文件是 AHK v2 独立模式的"预留接口"，基于文件的通道（`inbound.json`/`outbound.json`）。每次 `Send`/`Emit` 都调用 `_EnforcePipeSize`（`FileGetSize`）判断是否超限，再整条 `Stringify` + `FileAppend`；`PollMessages` 每次 `FileMove + FileRead + FileDelete + StrSplit + 逐行 JSONParser.Parse`。若该通道被高频调用会产生显著文件 I/O。
- **根因**：预留接口未做发送侧批量/合并，逐条文件写。
- **优化方案**：该路径非 Rust↔AHK 主干（主干走 interprocess named pipe），建议明确标注为低优先级/废弃，或改用内存队列 + 定时刷新，避免每条消息一次 `FileGetSize`。
- **预期收益**：若仍启用，减少逐条文件系统调用。

---

### T6-09 [Minor] JSONSerializer 默认 indent=2 生成多行 pretty JSON，日志单条被拆多行且含额外缩进分配

- **位置**：`infrastructure/json_serializer.ahk:17-21`（`Stringify(value, indent := 2)`）、`:49-88`（`_StringifyObject`/`_StringifyArray`）；`infrastructure/error_system.ahk:199`（`_ToJsonLine`）
- **维度**：性能优化
- **严重级别**：Minor
- **描述**：`ErrorSystem._WriteLog` 通过 `_ToJsonLine` 调用 `JSONSerializer.Stringify(record)` 使用默认 `indent=2`，产出带换行和缩进的"多行 JSON"，却当单行追加：既让 `errors.log` 一条记录被拆成多行（可读性/解析问题），又比紧凑序列化多出大量空格与缩进字符串分配。
- **根因**：日志写入复用了用于展示的 pretty 序列化默认参数。
- **优化方案**：日志路径改用紧凑序列化（`indent := 0` 或新增 `StringifyCompact`），展示路径保留 pretty。
- **预期收益**：减少错误路径序列化体积与临时字符串分配，日志保持一行一条。

---

### T6-10 [Minor] `_GetField` 对 JSON 字符串值每次都重复 `JSONParser.Parse`

- **位置**：`infrastructure/utils.ahk:41-55`
- **维度**：性能优化
- **严重级别**：Minor
- **描述**：`_GetField` 在值为字符串且以 `{`/`[` 开头时，每次调用都会执行 `JSONParser.Parse(obj)` 临时解析后再取字段，无缓存。虽然主要用在表现层 bridge（非执行热路径），但在同一字符串对象被反复读取的循环中会重复解析。
- **根因**：缺省"懒解析 + 缓存"。
- **优化方案**：对已解析结果按对象指针做缓存，或让调用方先行解析后再 `_GetProp` 取值。
- **预期收益**：消除重复 JSON 字符扫描。

---

### T6-11 [Minor] 序列执行器中冗余 `HasProp("_nextStepTime")` 检查

- **位置**：`domain/mode_registry.ahk:317,334`（SequenceExecutor）、`:415,434`（EnhancedSequenceExecutor）
- **维度**：性能优化
- **严重级别**：Minor
- **描述**：`_nextStepTime` 已在 `SkillGroup._SetupMode` 的 sequence 分支统一初始化为 0，`Execute` 循环内仍每次 `group.HasProp("_nextStepTime")` 判断；同理 `joystick_executor` / executor.ahk 的 sequence 路径也保留类似 `HasProp` 检查（属性早已预初始化）。
- **根因**：历史版本中属性可能不存在，后续预初始化后未清理冗余防御。
- **优化方案**：直接访问 `group._nextStepTime`，删除 `HasProp` 分支。
- **预期收益**：极微小；纯属清理。

---

### T6-12 [Minor] 配置保存路径多层冗余 deepclone（关联项，未在执行热路径）

- **位置**：`infrastructure/config_store.ahk:30-48,70`（Save/Load/Get 均 `deepclone`）；`application/group_service.ahk:140`；`presentation/webview2_manager.ahk`（保存桥接路径）
- **维度**：性能优化
- **严重级别**：Minor
- **描述**：`deepclone` 仅出现在配置读写路径（非执行热路径），故不构成按键执行开销；但 Save/Load/Get 与 group_service、webview bridge 之间存在多层叠加的防御性深拷贝（已在 `docs/review/2026-08-20/task-3-ahk-secperf.md`（T3-08）记录），对大型配置保存的延迟有线性放大，属提示性关联项。
- **根因**：为满足 I15/I16/I20 等防御性保护叠加了重复拷贝。
- **优化方案**：保存路径减少冗余 deepclone 层级，解析结果复用（详见 Task 3 结论）。
- **预期收益**：大型配置保存延迟下降，同步 UI 阻塞减轻。

---

## 统计

- 发现总数：**12**
- Critical：**1**（T6-01）
- Important：**6**（T6-02、T6-03、T6-04、T6-05、T6-06、T6-07）
- Minor：**5**（T6-08、T6-09、T6-10、T6-11、T6-12）

## Top 5 最严重发现

1. **T6-01（Critical）** — 执行器每次按键 down/up 无条件走 IPC：`MiniJson` 序列化 + 两次 `StrPut` + `Buffer` 分配 + 同步阻塞 `WriteFile` 写命名管道，且无背压上限，可经反向背压冻结 AHK 消息循环。
2. **T6-02（Important）** — 每次按键按下创建新闭包 + 一次性 SetTimer（多个文件），executor/joystick 侧 "up" 定时器未跟踪，高频模式产生每秒数百次闭包/定时器创建。
3. **T6-03（Important）** — `ErrorSystem._WriteLog`/`JSONLogger._WriteLog` 无限速，异常路径每次同步落盘，违背 AGENTS.md"热路径日志限速"承诺，异常风暴会拖垮执行循环。
4. **T6-04（Important）** — 重复激活已激活分组时 `_timers[groupId]` 被覆盖但旧定时器未取消，重连/重复触发可产生重复定时器与双倍发键。
5. **T6-05（Important）** — `bridge.rs` `block_in_place + block_on` 桥接且 `send()` 无写超时，AHK 挂起时可能无限阻塞 Tauri 工作线程。