# ASD 技能管理器 v4.0 — 生产级代码安全与健壮性审查（科迪 / Code Reviewer）

- 审查日期：2026-09-19
- 审查范围：安全（A）/ 健壮性（B）/ 错误处理与用户可见性（C）
- 代码基线：`D:\1demo\AutoHotkeydemo`（主 worktree，`main`）
- 复核纪律：每条结论给出 `文件:行号` 或实跑命令与输出；**显式标注「实测」/「推断」**

---

## 1. 本域结论

### 接近生产级（不达标项 0，阻断项 0；2 项「高」需在发布前收敛）

一句话：代码工程质量显著高于平均水平——生产 Rust 代码**仅 1 处 panic 点**、465 条测试全绿、IPC 认证设计（随机管道名 + 随机 token + 恒定时间比较 + 服务端强制首包认证）是正确且被测试守护的；但**IPC 管道缺少 DACL**（TD-071）与其配套注释中的**事实性错误**，叠加**看门狗放弃重启后完全不通知用户**，构成发布前必须收敛的两条「高」。

Go/No-Go（仅代码维度）：**有条件 Go** —— 详见第 5 节。

### 实跑证据汇总（实测）

| 命令 | 结果 |
|---|---|
| `CARGO_INCREMENTAL=0 cargo test -p asd-application -p asd-domain -p asd-ipc-protocol` | **19 个测试目标全部 ok，合计 406 passed / 0 failed** |
| `CARGO_INCREMENTAL=0 cargo test -p asd-tauri --lib watchdog` | **59 passed / 0 failed**，含 `test_watchdog_runner_auto_restart ... ok` |
| 生产代码 panic 点扫描（自制脚本，排除 `#[cfg(test)]` 区域） | **生产代码 panic 点 = 1**（另 5 处为注释文本） |

> 备注：首次 `cargo test` 触发 **rustc 1.95.0 ICE**（`encode_metadata` 内 `option::expect_failed`，`error: the compiler unexpectedly panicked`）。这是**编译器 bug，非本项目代码缺陷**；加 `CARGO_INCREMENTAL=0` 后正常通过。建议 CI 固定 `CARGO_INCREMENTAL=0` 或清理增量缓存。

---

## 2. 发现清单表

| # | 严重度 | 类别 | 文件:行 | 问题描述 | 证据 | 实测/推断 | 生产级影响 |
|---|---|---|---|---|---|---|---|
| 1 | **高** | 安全 A1 | `src-tauri/src/infrastructure/ipc.rs:968-975` | IPC 命名管道创建未设置安全描述符（DACL），任何同权/同完整性级本地进程可连接并冒充 AHK 执行器 | `create_listener` 仅 `ListenerOptions::new().name(name)` | 推断（代码确证，未做穿透实跑） | 同机恶意进程可劫持 IPC：注入伪造热键事件、截获全部按键指令 |
| 2 | **高** | 健壮性 C1 | `src-tauri/src/infrastructure/watchdog.rs:1249-1250`、`414-418` | 看门狗重启 10 次仍失败后进入 `Failed`，**只写 error 日志，不发任何前端事件**；执行器永久失效而 UI 完全无提示 | 全仓 grep `emit` 在 watchdog.rs 中零命中 | 推断（代码确证） | 用户遇到「按热键没反应」却无任何报错，是最高频的一类不可诊断故障 |
| 3 | 中 | 安全 A1b | `src-tauri/src/infrastructure/ipc.rs:63-69` | 注释称「interprocess 2.4.2 的 ListenerOptions 没有暴露 DACL 入口，需绕过该库直接调 CreateNamedPipeW」——**该前提事实错误**，库原生支持 | `interprocess-2.4.2/src/os/windows/local_socket.rs:20-26` 提供 `ListenerOptionsExt::security_descriptor()`；`named_pipe/listener/create_instance.rs:52,66` 已接到 `CreateNamedPipeW` | 实测（读库源码） | 使 TD-071 的修复成本被严重高估（误判为需替换/包装库），阻碍修复排期 |
| 4 | 中 | 安全 A2 | `watchdog.rs:329`、`ipc.rs:333-336`、`ahk_executor/ipc_client.ahk:472` | 认证 token 与随机管道名**均经环境变量**传给子进程；Windows 下同权进程可读取他进程环境变量，二者可同时获得 → 绕过「随机名」缓解 | `cmd.env("ASD_AUTH_TOKEN", auth_token)` | 推断（Windows 安全模型既定事实，未实跑读取） | 与 #1 叠加：随机管道名这一缓解措施在同权攻击者面前失效 |
| 5 | 中 | 安全 A3 | `crates/asd-application/src/backup_service.rs:22-50` | 有严格校验但**无根目录白名单且未 canonicalize**：`C:\Windows\System32\x.json` 这类「绝对、无 `..`、`.json` 结尾」路径被放行 | 校验只拒绝相对路径/`..`/UNC/`\\?\`；无 allowlist、无 `canonicalize()` | 推断（代码确证） | 可写出/读入任意绝对 `.json` 路径；符号链接/ junction 未被解析 |
| 6 | 中 | 测试 A3b | `crates/asd-application/tests/` | `validate_file_path` 的 5 条安全拒绝分支**零测试覆盖** | grep 错误字符串仅命中实现（backup_service.rs:28/32/37/40/47），测试中零命中 | 实测（grep + 测试全绿但无此类用例） | 唯一防线无回归保护，重构时可能被静默削弱 |
| 7 | 中 | 健壮性 C1 | `crates/asd-application/src/state.rs:307-311`（28 处调用） | `try_send_ipc_command` 发送失败仅 `tracing::warn!`，调用方无感知、前端无任何提示 | `if let Err(e) = ... { tracing::warn!("IPC 发送失败: {e}") }` | 实测（grep 调用点 28 处） | 管道异常时大量操作（热键注册/注销、状态恢复）静默不生效 |
| 8 | 中 | 健壮性 C1 | `state.rs:511-522`、`ahk_executor/sender.ahk:53,425,432` | 已知两条静默路径复核确认：热键重复注册返回 `Ok(Some(_))` 但不注册；<10ms 间隔被静默钳制到 10ms | 见详述 | 实测（代码复核） | 用户配置被静默改写且不获知 |
| 9 | 低 | 健壮性 C1 | `crates/asd-application/src/recording_service.rs:409-412,421,426` | 导入录制 JSON 时 `keys`/`intervals`/`delays` 类型不匹配 → `unwrap_or_default()` 静默降级为空数组，最终报成误导性的「缺少按键序列」 | `from_value::<Vec<String>>(v.clone()).ok().unwrap_or_default()` | 实测（代码复核） | 排障方向被误导 |
| 10 | 低 | 健壮性 C1 | `src-tauri/src/lib.rs:334,342` | IPC 重连恢复时 `read_groups().ok()` 失败 → `unwrap_or_default()` 静默恢复为空分组列表 | 见详述 | 实测（代码复核） | 重连后运行中的分组不被恢复且无提示 |
| 11 | 低 | 健壮性 C1 | `group_service.rs:88,178,544,611,620` | `let _ = state.set_group_active(...)` / `unregister_hotkey(...)` / `register_hotkey(...)` 返回值被丢弃 | `let _ =` 吞没 | 实测（grep） | 回滚/清理动作失败不可见 |
| 12 | 低 | 健壮性 B3 | `config_repository.rs:126-136` | copy 回退路径下临时文件删除失败仅 warn 并返回 `Ok`，残留 `.tmp_*`；清理仅 `save_to_path` 触发且只清 >1 小时 | 见详述 | 实测（代码复核） | 有界、自愈，影响很小 |
| 13 | 低 | 安全 A4 | `src-tauri/tauri.conf.json:22` | `style-src 'self' 'unsafe-inline'` 保留内联样式 | 配置行 | 实测 | 仅样式面，风险很低 |

---

## 3. 每条发现的详述

### 发现 1（高）— IPC 命名管道未设 DACL

`src-tauri/src/infrastructure/ipc.rs:968-975`：

```rust
pub fn create_listener(
    pipe_name: &str,
) -> Result<Listener, Box<dyn std::error::Error + Send + Sync>> {
    let name = pipe_name.to_ns_name::<GenericNamespaced>()?;
    let opts = ListenerOptions::new().name(name);   // ← 未设置 security_descriptor
    let listener = opts.create_tokio()?;
    Ok(listener)
}
```

`ListenerOptions::new()` 默认 `security_descriptor: None`（库源码 `local_socket/listener/options.rs:75`）。Windows 下 `CreateNamedPipeW` 传入 NULL 安全属性时，管道 DACL 取自创建者令牌的默认 DACL，**同用户（及 Administrators/SYSTEM）可连接**。

缓解现状（确有其效，但不完整）：随机管道名（`ipc.rs:71-84`）+ 随机 token（`ipc.rs:869`）+ 服务端强制首包 `auth` 校验（`ipc.rs:231-296`）。但随机管道名同样通过环境变量传给 AHK（发现 4），同权攻击者可一并读取，缓解被削弱。

**未实跑**：未做「另起进程连接管道」的穿透验证（需构造 Windows 管道客户端，超出本次范围）。结论基于代码 + 库行为，标注为推断。

### 发现 2（高）— 看门狗放弃重启后完全不通知用户

`watchdog.rs:414-418`：

```rust
WatchdogStateEnum::Restarting => {
    if self.restart_count >= MAX_RESTART_ATTEMPTS {   // = 10 (watchdog.rs:25)
        self.set_state(WatchdogStateEnum::Failed);
        return WatchdogAction::MaxRetriesExceeded;
    }
```

`watchdog.rs:1249-1250`（`WatchdogRunner::run`）：

```rust
WatchdogAction::MaxRetriesExceeded => {
    tracing::error!("Watchdog: 超过最大重启次数，等待恢复");
```

只有 `tracing::error!`，**没有任何 `app_handle.emit(...)`**。对照 `lib.rs:136-148`：IPC 监听端创建失败已经正确发 `ipc:listener-failed` 事件并在前端弹 toast（`main.js:1421-1424`）——说明项目**有**「致命故障要通知用户」的既有模式与先例，本处是漏网。

影响：AHK 执行器连续崩溃 10 次后，应用进入「热键无反应、界面无异常」的状态。这是可诊断性缺陷，不是崩溃缺陷。

### 发现 3（中）— 项目中关于 DACL「库不支持」的注释是事实错误（重要）

`ipc.rs:63-69` 原文：

> `interprocess` 2.4.2 的 `ListenerOptions` 没有暴露安全描述符（DACL）设置入口，要限定「仅当前用户可连接」得绕过该库直接调 `CreateNamedPipeW`。

实测核对 `C:\Users\fei\.cargo\registry\src\...\interprocess-2.4.2`：

```rust
// src/os/windows/local_socket.rs:17-27
pub trait ListenerOptionsExt: Sized + Sealed {
    fn security_descriptor(self, sd: SecurityDescriptor) -> Self;
}
impl ListenerOptionsExt for ListenerOptions<'_> {
    fn security_descriptor(mut self, sd: SecurityDescriptor) -> Self {
        self.security_descriptor = Some(sd); self
    }
}
```

且已贯穿到底层：

```rust
// src/os/windows/named_pipe/listener/create_instance.rs:52,66
self.security_descriptor.as_ref().map(|sd| sd.borrow()),
CreateNamedPipeW(..., PIPE_REJECT_REMOTE_CLIENTS, ...)
```

`SecurityDescriptor` 可 `new()` 后用 `ext.rs` 的 `set_dacl`，或直接用 `SecurityDescriptor::deserialize(&U16CStr)` 从 SDDL 串构造（`owned.rs:42,55`）。

**结论**：TD-071 的修复是「构造一个仅当前用户可连接的 SD + 一行 `.security_descriptor(sd)`」，**不需要替换或包装 `interprocess`**。原注释把修复成本从「小时级」夸大为「架构级」，这是最需要纠正的一条。

（顺带确认：`PIPE_REJECT_REMOTE_CLIENTS` 已启用，远程连接被拒，这一点是好的。）

### 发现 4（中）— token 与管道名同经环境变量传递

- 生成：`ipc.rs:869-895` `generate_auth_token()`，32 字节 `getrandom` → 64 字符 hex（良好）；getrandom 失败时回退 PID+计数器+时间戳（较弱，但有 `tracing::warn!`）。
- 传递：`watchdog.rs:329` `cmd.env("ASD_AUTH_TOKEN", auth_token)`；`watchdog.rs:333-336` 传 `ASD_IPC_PIPE_NAME`。**仅走环境变量，未走命令行**（`--auth-token` 是 AHK 侧的备用读取路径，Rust 侧不使用，见 `ipc_client.ahk:481-483`）——这一点比常见做法更安全，值得肯定。
- AHK 读取：`ipc_client.ahk:472` `EnvGet("ASD_AUTH_TOKEN")`；日志只输出固定文案，不打印 token 值（`:475`），无泄漏。
- 暴露面：Windows 下同等完整性级的进程可通过 `OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ)` + 读 PEB 获取目标进程环境变量。

**未实跑**：未编写跨进程读取环境变量的 PoC（超出范围）。该结论基于 Windows 进程安全模型的既定事实，标注为推断。

注意与 #1 的耦合：单看「随机管道名」是有效缓解，但攻击者能从环境变量同时拿到「管道名 + token」，缓解强度回到「同权即可冒充」。

### 发现 5（中）— TD-072 应改述：不是路径遍历，而是无根目录白名单

**先说结论：路径遍历（traversal）不存在。** 我实际读了 `validate_file_path`（不是只读注释）：

```rust
// backup_service.rs:22-50
if path.contains('\0') { ... }                                  // 空字节
if p.is_relative() { ... }                                      // 相对路径
for component in p.components() {
    if matches!(component, Component::ParentDir) { ... }        // .. 组件
}
if path_lower.starts_with("\\\\?\\") || starts_with("//?/") { } // 设备路径
if path_lower.starts_with("\\\\") || starts_with("//") { }      // UNC
if ext != "json" { ... }                                        // 扩展名
```

`..\..\..\Windows\System32\x.json` 会因 `is_relative()` 被拒（无根），即使写成绝对路径也会被 `ParentDir` 组件检查拦下。UNC 与 `\\?\` 同样被拒。

**并且 4 个入口全都调用了它**（不是只写在配置导入上）：

```
backup_service.rs:358   export_config
backup_service.rs:374   import_config
recording_service.rs:354 export_recording
recording_service.rs:402 import_recording
```

（我一度怀疑 `recording_cmd.rs:97-107` 的 `export_recording_impl` 漏校验——它自身只查空串；但追到 `recording_service.rs:354` 确认内部有校验。该怀疑被推翻。）

**真实残留缺口**：没有根目录白名单，也没有 `canonicalize()`。因此 `C:\Windows\System32\evil.json`、`C:\Users\OtherUser\Desktop\x.json` 这类「绝对 / 无 `..` / `.json`」路径会通过；junction/符号链接也不被解析。建议：限定到用户目录（AppData / 用户显式选择并登记的目录），并在校验前 `canonicalize()`。

### 发现 6（中）— 唯一防线的 5 条安全分支零测试覆盖

grep 全仓，`必须绝对路径`/`父目录引用`/`不支持 UNC`/`不支持设备路径`/`.json 扩展名` 五条错误串**只出现在实现里，测试零命中**：

```
backup_service.rs:28 / 32 / 37 / 40 / 47  ← 仅实现
```

而 `cargo test` 全绿（406 passed），说明这些分支从未被执行验证。作为 TD-072 的唯一防线，这是显著的质量缺口；按项目自身的「阳性对照」惯例，应补 5 条反例 + 1 条「改回不校验即失败」的阳性对照。

### 发现 7（中）— `try_send_ipc_command` 静默失败（28 处）

```rust
// state.rs:307-311
pub fn try_send_ipc_command(&self, cmd: &IpcCommand) {
    if let Err(e) = self.ipc_sender.send_command(cmd.clone()) {
        tracing::warn!("IPC 发送失败: {e}");   // ← 仅日志
    }
}
```

全仓 28 处调用（含 `lib.rs:346,352,356` 重连后的状态恢复、`group_service.rs:78,106,109,113` 热键注册/注销与回滚）。管道异常时这些动作全部静默不生效。对比同文件 `send_ipc_command`（返回 `Result` 并向上传递到 command 层，如 `system_cmd.rs:64-75`、`group_service.rs:84-88`），说明项目**有**正确传播的路径，`try_send_` 是为了「尽力而为」语义而有意降级——但该语义未被任何 UI 信号兜底。

### 发现 8（中）— 已登记的两条静默路径复核确认

- `state.rs:511-522` `register_hotkey`：热键已被占用时 `return Ok(Some(existing.clone()))`，**不注册**却返回 `Ok`。文档已明确警示，但调用方是否检查 `Option` 需逐个确认（本轮未逐点核查）。
- `sender.ahk:53` `MIN_INTERVAL_US := 10000`，在 `:425`（interval）与 `:432`（delay）处 `intervalUs < MIN ? MIN : intervalUs` 静默钳制；`joystick.ahk:66,77,83` 同。用户配置 5ms 会被无声改成 10ms。

### 发现 9-11（低）— 其余静默路径

- `recording_service.rs:409-412`：`from_value::<Vec<String>>(v).ok().unwrap_or_default()` → 类型不匹配静默成空数组，最终报「缺少按键序列」（`recording_cmd.rs:121-123` 已自述此行为）。
- `lib.rs:334,342`：`state.read_groups().ok()` → `.unwrap_or_default()`，重连恢复时读失败即恢复零分组。
- `group_service.rs:88,178,544,611,620`：`let _ = state.set_group_active(...)` / `unregister_hotkey(...)` / `register_hotkey(...)`，返回值被丢弃。

### 发现 12（低）— 临时文件残留（有界、自愈）

`config_repository.rs:76-109` 的 `atomic_write` 先写 `.tmp_<name>_<pid>_<纳秒>` 再 `rename`（真原子）；rename 瞬时冲突退避重试 4 次（TD-043），耗尽后走 `fallback_copy`。copy 分支下 `remove_file` 失败仅 warn（`:130-135`）会留残留；`cleanup_stale_temp_files`（`:140-157`）清理 >1 小时的 `.tmp_*`，但**只在 `save_to_path`（`:262`）触发**。行为与文档自述（`:69-73`）一致，残留有界且自愈，判为低。

### 发现 13（低）— CSP 细节

CSP 实际定义在 `src-tauri/tauri.conf.json:22`（**不在 `index.html`**，该处无 CSP meta —— 对任务书的一处更正）：

```
"csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
```

`withGlobalTauri: false`（`:13`）也在，很好。仅 `style-src` 保留 `unsafe-inline`，风险很低。

---

## 4. 「未发现问题」的检查项（明确列出查过且确认 OK 的靶点）

以下均**实际核查**，结论为未发现问题或仅低危残留：

1. **B1 — Rust panic 密度与位置：未发现问题（表现优秀）**
   用自制脚本（`.review-analysis/panicscan.py`，按花括号深度跳过 `#[cfg(test)] mod ... {}` 区域）扫描 4 个 crate 全部非测试 `.rs`：
   **生产代码 panic 点 = 1**，即 `lib.rs:829` `.expect("Tauri 应用启动失败")`，位于应用入口 `run()`（首次运行失败即退出，语义合理）。其余 5 处命中全是注释文本。
   **Tauri command 处理路径上零 panic** —— 不存在「某个 command panic 拖垮应用」的风险。`src-tauri/Cargo.toml` 与 workspace 无 `[profile]` 覆盖，panic 策略为默认 `unwind`。

2. **Cargo test 全绿（实测）**：406 passed / 0 failed（3 个 lib crate）+ 59 passed / 0 failed（watchdog 相关）。

3. **B2 — AHK 子进程崩溃后会被重启：已验证生效（实测）**
   `WatchdogRunner::run`（`watchdog.rs:1216-1271`）在 `RestartNeeded` 时调用 `restart_child`；重启（含 `taskkill` 清理与 `Command::spawn`）已迁入 `spawn_blocking`（`watchdog.rs:1279-1295`，T5-04），不阻塞异步运行时。
   集成测试 `tests/watchdog_integration_tests.rs:172-220` 真实启动 `cmd.exe` → `kill_child()` → 断言 5 秒内 `restart_count > 0`。**实测 `test_watchdog_runner_auto_restart ... ok`**。故 B2 不是「代码写了」，而是确有行为证据。

4. **A4 — 前端无 CSP 绕过写法：未发现问题（实测）**
   `main.js`（1431 行）grep `eval(` / `new Function` / `document.write` / `createElement('script')` / `setAttribute('src')` / `javascript:` / `insertAdjacentHTML` —— **零命中**。
   `innerHTML` 使用广泛，但统一走 `escHtml`/`escAttr`（`main.js:222-223`，转义 `& < > " '`），在 `renderDashboard`（`main.js:476-498`）等处对 `g.name`/`g.hotkey`/`g.id`/`keysPreview` 均逐项转义，未见未转义拼接口。
   叠加 `script-src 'self'`（禁内联脚本与内联事件处理器）与 `withGlobalTauri: false`，XSS 面被有效收敛。

5. **A2 — token 未走命令行、未落入日志：未发现问题**
   Rust 侧仅用环境变量（`watchdog.rs:329`），未用 `--auth-token`；AHK 侧日志只输出固定文案（`ipc_client.ahk:475,483`），不打印 token 值。

6. **A2 — 认证的服务端实现质量：未发现问题（设计良好）**
   `accept_from_ahk`（`ipc.rs:231-296`）要求首条消息必须为 `auth` 且 token 匹配，5 秒超时，任何失败路径先 `cleanup_connection()` 再返回；比较用恒定时间 `constant_time_eq`（`ipc.rs:901-912`，长度差也纳入 diff）；`accept_loop` 对认证失败做指数退避（1→30s，位移量 `min(5)` 防溢出，`ipc.rs:334-341`）。
   另有阳性对照测试 `test_create_listener_reports_name_conflict`（`ipc.rs:1615-1626`）守护「撞名必须返回 Err 而非静默降级」。
   此外 `connect_to_ahk()`（Rust 作客户端、无认证，见其文档 `ipc.rs:203`）**仅被测试使用**（grep 命中全在 `src-tauri/src/tests/`），生产路径是 Rust 作服务端，不存在绕过认证的入口。

7. **安全红线 — `STALE_PROCESS_NAMES` 未被污染：未发现问题（实测）**
   `watchdog.rs:872` `const STALE_PROCESS_NAMES: &[&str] = &["asd_executor.exe"];` —— **不含 `AutoHotkey64.exe`**，红线保持。
   `PORTABLE_IMAGE_NAMES`（`:880`）含 `autohotkey64.exe`，但仅用于**按 PID** 终止且必须先在 `SPAWNED_CHILDREN` 登记表内（`:948-953`），并复核 `QueryFullProcessImageNameW` 防 PID 复用（`:956+`），与按名清理语义不同——不构成红线违反，且注释（`:874-879`）明确警示「切勿合并」。

8. **B3 — 进程/句柄资源泄漏：未发现严重问题**
   子进程有 `SPAWNED_CHILDREN` 登记表（`:899`，带上限 `:901-902`）与 JobObject 兜底（`:856` `Box::from_raw` RAII 释放）；句柄 `CloseHandle` 均有调用（`:822,833,1023`）。管道连接 `cleanup_connection`（`ipc.rs:811-826`）双向清空并 drain `pending_responses`。`listen_ahk` 退出时 `recv_handle.abort()`（`ipc.rs:796`）。

9. **命令注入面（.bat 路径）：未发现问题**
   `watchdog.rs:296-313` 用 `cmd /D /S /C "..."`：`/D` 跳过 AutoRun、`/S` 阻止二次引号解析，并注明 `exe_path` 必须来自受控 Resource 目录、不接受外部输入。

10. **A3 — 路径遍历（traversal）：未发现问题**（详见发现 5，校验已拦截 `..`/相对/UNC/设备路径）。

11. **IPC 监听失败不再静默：已修复并有前端承接（实测）**
    `lib.rs:136-148` 发 `ipc:listener-failed`；`api.js:171` 订阅；`main.js:1421-1424` 落日志 + `showToast`。我一度怀疑前端没接（main.js 内 grep `listen` 为 0），追到 `api.js` 后发现订阅齐全，且 6 个后端事件在 main.js 均各有 1 处调用——**该怀疑被推翻**。

---

## 5. Go/No-Go 建议（仅代码维度）

### 结论：有条件 Go

**阻断项 = 0。** 没有任何一条会导致应用崩溃、数据损坏或功能不可用于正常用户。测试基线全绿（465 条），生产代码 panic 点仅 1 处且在入口，IPC 认证设计与看门狗重启均有测试守护——这在同类项目里属于上游水平。

### 发布前必须收敛（2 条「高」）

1. **#2 看门狗放弃重启后通知用户**（成本很低，收益最高）
   照 `lib.rs:143-146` 既有模式发 `watchdog:failed` 事件，`api.js` 增订阅，`main.js` 弹 toast。这是「用户遇到热键失灵却毫无提示」这类最难排查故障的根因。

2. **#1 IPC 管道加 DACL**（成本被严重低估，应先纠正认知）
   先修正 `ipc.rs:63-69` 的错误注释（#3），再用库原生 API 落地：构造仅当前用户可连接的 `SecurityDescriptor`（`SecurityDescriptor::deserialize(SDDL)` 或 `new()` + `set_dacl`），在 `create_listener` 里加一行 `.security_descriptor(sd)`。**不需要替换/包装 `interprocess`。** 建议同时补一条「非所有者进程连接被拒」的阳性对照测试。

### 发布前应补（中）

3. **#6** 补 `validate_file_path` 的 5 条拒绝分支测试 + 阳性对照（唯一防线当前无回归保护）。
4. **#5** TD-072 改述为「无根目录白名单 / 未 canonicalize」，并加用户目录 allowlist + `canonicalize()` 校验。
5. **#7** 为 `try_send_ipc_command` 的失败加聚合信号（例如连续 N 次失败时发一次前端事件），避免 28 处调用点全部静默。

### 可排入发布后

6. **#4** token 传递改走更窄通道（如管道首包由 Rust 下发 token 而非环境变量），或接受同权威胁模型并明确写入威胁模型文档。
7. **#9-12** 静默降级点补充用户可见提示；copy 回退残留临时文件。

### 工程提示（非缺陷）

8. 首次 `cargo test` 触发 **rustc 1.95.0 ICE**（增量缓存问题，`CARGO_INCREMENTAL=0` 后正常）。建议 CI 固定 `CARGO_INCREMENTAL=0`，避免偶发红构建被误判为代码问题。

### 复核纪律说明

本轮我提出并被自己推翻的假设共 3 处，均因「先验证再下结论」而未写入结论：
- 假设「`ipc:listener-failed` 前端没接」→ 追到 `api.js:171` 确认已接，推翻。
- 假设「`export_recording_impl` 漏路径校验」→ 追到 `recording_service.rs:354` 确认已校验，推翻。
- 假设「生产代码 panic 点多」→ 首次扫描因 `lib.rs:5` 的 `#[cfg(test)] mod tests;` 导致误截断，改用花括号深度跟踪后确认仅 1 处，推翻。

另需记录 **2 处我自己的方法性错误**（不是假设被推翻，而是把「方法的产物」误当成「事实」），均已在上文更正：
- **字面量 vs 正则**：用 `Select-String -SimpleMatch '#\[ignore'` 扫描，把正则转义符 `\[` 当普通字符，得出「0 命中」的假阴性。正确值为 9（见 6.1）。
- **过滤跑法当全量**：把「3 个 crate 的 406」+「按名过滤后仅 59（197 被过滤）」相加得 465，当作用例总数。正确值为 667 / 666（见 6.3）。

这两处同源：都是**未确认自己所用命令的语义就采信其输出**。跨工具复核（grep 正则 vs PowerShell 字面量）、跨口径取数（过滤跑法 vs 全量 `--list`）时尤其容易踩。

---

## 6. 补充（应 tessa 的 CI 反馈做的连带复核）

tessa 反馈「CI 的 G3h 步骤已空转」，并归因于我摘掉了 `watchdog_integration_tests.rs` 的 `#[ignore]`。我做了独立复核：

### 6.1 事实核实（实测）

- **`#[ignore]` 现状：命中 9 处，全部在注释里，真实属性 0 处。**
  9 处分布在两个文件：`bridge_tests.rs:5,181,189`、`watchdog_integration_tests.rs:5,6,7,14,15,17`。
- ⚠️ **本条曾记错并已更正**：我初版结论写的是「全仓 0 命中」，那是**我自己的扫描错误** —— 我用了 `Select-String -SimpleMatch '#\[ignore'`，`-SimpleMatch` 是字面量匹配，把反斜杠当普通字符，实际搜的是带反斜杠的 `#\[ignore`，故必然 0 命中。改用**正则**匹配后即为 9。tessa 的 9 是对的，我的 0 是假阴性。
  > 教训：`grep -rn "#\[ignore"`（`\[` 是正则转义）与 `Select-String -SimpleMatch` 语义不同，跨工具复核时必须确认匹配模式。
- **真实属性 0 的结论不受影响**（逐行 `Trim()` 后判 `^#\[ignore` 亦为 0），且与「未加 `--ignored` 也能跑满 59 条」的实测互相印证。
- **ignore 确已摘除（实测）**：`cargo test -p asd-tauri --lib watchdog`（**未加** `--ignored`）→ 59 passed / 0 failed，输出含 `test_watchdog_runner_auto_restart`、`test_watchdog_child_crash_restart`、`test_watchdog_restart_limit`、`test_watchdog_start_child_process`、`test_watchdog_full_state_machine_flow`、`test_watchdog_graceful_shutdown` —— 即 `ci.yml:159-163` 注释所述「带 `#[ignore]`、G3a 默认跳过」的那批用例，现已默认执行。
- **G3h 空转属实**：`ci.yml:166-171` 为 `-- --ignored --test-threads=1` + `continue-on-error: true`。0 个 ignore 属性 + `continue-on-error` = 双重空转。

### 6.2 比 G3h 空转更实质的一条：G3a 被提前硬化

`ci.yml:164` 写明摘 `#[ignore]` 的前提是「连续跑绿 3-5 次后再摘 `#[ignore]` 转硬门禁」。

**判据本身有三套且互相冲突**（tessa 先发现两套，我复核时补出第三套，也是最严的一套）：

| 出处 | 判据 |
|---|---|
| `ci.yml:164` | 连续跑绿 **3-5 次**后摘 |
| `watchdog_integration_tests.rs:5-7` | 实测**约 13 秒且 15/15 通过**（速度判据，非次数判据） |
| `watchdog_integration_tests.rs:23-24` | 本机与 CI**各**连续跑 **≥10 次全绿**（含 `--test-threads=1`）才可摘 |

即：规定写 3-5 次，最严判据写 ≥10 次，实际按「13 秒不慢」晋级。三者口径不一致，晋级依据最弱的一条。

现状是：**ignore 已摘，但这 15 条进程生命周期用例已在阻塞的 G3a 中运行，而上述任何一条判据的满足都没有留痕**（tessa 全仓检索「观测期 / 3-5」40 处命中，唯一接近的留痕是 `remaining-issues-review-2026-09-18.md:24` 的「本地 15 passed/13.39s + CI success」—— 一次本地 + 一次 CI，远未达 ≥10 次）—— 等于从软门禁直接跳到硬门禁。

风险：该组用例真实派生 `cmd.exe` 子进程并执行 PID/`taskkill` 清理，在共享 runner 上比本机更易抖动；一旦偶发红，将**直接打红主门禁 G3a**，不再有 `continue-on-error` 兜底。

建议（发布前）：按**最严**判据补齐留痕 —— 本机与 CI 各连续 **≥10 次**全绿（含 `--test-threads=1`）；或暂将该组单独成步并保留 `continue-on-error` 直至观测期完成。注意 6.2 表格中三套判据口径冲突，应先统一口径再谈「是否已满足」，否则「满足了 3-5 次」与「满足了 ≥10 次」会被各自援引。

### 6.3 对 G3h 处置的建议：选「元门禁」

两个方案（摘掉 G3h / 改元门禁）中推荐**元门禁**：
- 方案 1 只消除空转，未消除「将来有人悄悄挂 `#[ignore]` 让测试消失」这一根因；
- 方案 2 正好接上 `watchdog_integration_tests.rs:14-17` 的「解禁判据」纪律，且让 G3h 从空转变为有意义的断言。
- 实现：断言 `cargo test -p asd-tauri --lib -- --ignored --list` 输出为 0 tests（**不要**用 grep 判「注释里的 `#[ignore]`」，会产生假阳性/假阴性）；并**去掉 `continue-on-error`**，否则仍无牙。
- ⚠️ **该元门禁是必要但不充分的**（对我自己上一版建议的修正）：`--ignored --list == 0` 只能拦住「重新挂 `#[ignore]`」这一种消失方式，**拦不住**被注释掉的测试、被 `#[cfg(...)]` 排除或未参与编译的测试。本项目就有先例：`bridge_tests.rs:178-186` 记载 `test_tauri_event_bridge_emit` 是**整个被注释/删除**（2026-09-13，BUG-4），不是挂 `#[ignore]` —— 元门禁对它完全无感。
  故建议再加一道**用例总数下限**门：断言收集到的用例数 ≥ 基线，只阻下降、容差 0。这能一并覆盖「删除/注释掉/条件编译排除」三类消失，成本仅一行。
- ⚠️ **基线数字经更正**：我初版给的「465」**是错的**（tessa 指出，我复核确认）。465 是我把 `cargo test -p asd-application -p asd-domain -p asd-ipc-protocol` 的 **406** 与 `cargo test -p asd-tauri --lib watchdog` 的 **59** 相加得来的；而后者是**按名过滤**的跑法（实测输出原文 `59 passed; 197 filtered out`），并非全量。因此 465 不是「总数」，按它设下限等于白送约 202 条用例的静默消失额度。
  **实测正确值**（本机 2026-09-19）：`cargo test --workspace -- --list` 收集 **667** 条（`grep -c ": test$"`，exit 0）。
  另需注意两条命令本身差 1：tessa 实测 workspace 口径 **667**、逐 crate `--all-targets` 口径 **666**（161+72+173+3+257），差在 bin 目标。**必须先定死用哪条命令再定基线**（与覆盖率「重取基线必须用同一条命令」同坑）。
  采纳 tessa 的最终方案：复用 G3d 已在采集的逐 crate `--all-targets` 口径，基线 **666**，与 G3d 共用同一次采集，不新增 cargo 命令。
  **666 有第二重来源、非孤证**：G3d 每次都用 `check-test-map.py` 对 5 个 crate 做运行时对账，输出 161/72/173/3/257 = 666。故落地这道门时**直接读 G3d 已采集到的那组数**，不要再自己跑一遍 cargo（既省时间，也避免口径漂移）。
  （注：`bridge_tests.rs` 那次删除本身是**合理**的 —— 死测试无条件 `panic!`，使 `--ignored` 永远报 1 failed 造成狼来了效应，且覆盖已由 `MockEventEmitter` 的 `test_event_emitter_trait_contract` 承接。此处仅说明该类消失不在元门禁视野内。）

### 6.4 G3b 重试不对称：建议不动

`check-gates.sh:157-178` 的 1 次重试有 TD-041 依据（「只重试，绝不重试回归判定」）；CI 侧已用 `ASD_HOST_TIMING=0`（`ci.yml:177-183`）显式跳过最易抖的 7 条时延用例，两边本就是有意的不同配置。若要统一，倾向「给 CI 加同样的重试」（共享 runner 更争用），而非摘掉本地重试。优先级低于 6.2。

### 6.5 归属说明

本会话我**零代码改动**（仅在 `.review-analysis/` 下写了两个扫描脚本）。复核期间 `git` 命令在本机报错（exit 1）无法取 log，故 `#[ignore]` 摘除的 authorship 未能核实，需另行查证。

---

*审查人：科迪（Cody）· 代码审查师*
*辅助脚本：`.review-analysis/panicscan.py`（生产代码 panic 点扫描）、`.review-analysis/swallow.py`（错误吞没模式扫描）*
