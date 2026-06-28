# Rust/Tauri 重写项目全面验收清单

## Phase 0: PoC 验证

- [x] Tauri 2.11.2 项目初始化成功（`cargo build` + `npm run tauri dev`）
- [x] serde_json 反序列化实际 config.json 成功（10 种模式全部正确解析）
- [x] roundtrip 序列化一致性验证通过
- [x] interprocess Named Pipe 双向通信验证通过
- [x] IPC 延迟 <1.2ms（PoC 实测 62.7μs）
- [x] Tauri invoke JS↔Rust IPC 验证通过
- [x] Go/No-Go 决策：GO

## Phase 1: 基础设施

- [x] `tauri.conf.json` 配置完整（应用名、窗口、权限）
- [x] `capabilities/default.json` 包含 `global-shortcut:allow-register/unregister`
- [x] `rust-toolchain.toml` MSRV 1.95.0
- [x] `Config` 结构体反序列化 config.json 成功
- [x] `GroupConfig` 方案 B（untagged + flatten）10 种模式兼容
- [x] `GroupItem` 枚举 tag = "type" 正确鉴别 periodic/sequence
- [x] 跨模式共享字段（holdKeys/holdMode/holdPattern/holdTriggers）在 GroupConfig 顶层
- [x] `HoldSettings` 为 `Option<HoldSettings>` + `#[serde(default)]`
- [x] tracing 日志系统替代 AHK error_system/debug_logger
- [x] `IpcManager` 实现 accept_loop()（Rust 为 Listener/服务端）
- [x] JSON Lines 帧协议（\n 分隔 + 64KB 限制 + BufReader）
- [x] `IpcCommand` 枚举和 `IpcMessage` 结构体定义完整
- [x] seq/ack_seq 确认机制实现
- [x] 背压与流控（mpsc::channel(256) + 合并窗口 + 指令去重）
- [x] `IpcCallback` 类型别名（`Arc<dyn Fn() + Send + Sync>`）
- [x] ProcessWatchdog 7 状态实现（Idle/Starting/Running/Hung/Restarting/Recovering/Failed）
- [x] 心跳检测参数：1s 间隔，3 次超时判定挂起（共 3s）
- [x] 指数退避重启（1s→2s→4s→8s→30s，最大 10 次）
- [x] `WatchdogRunner::from_arc()` 和 `pub fn set_state()` 可见性正确
- [x] `StateChangeCallback` 类型别名
- [x] `AppState` 同步原语选型正确（std::sync::RwLock / tokio::sync::Mutex / AtomicBool）
- [x] `AppError` 使用 thiserror + 手动 Serialize（不使用 anyhow）
- [x] `try_send_ipc_command()` 方法实现
- [x] `JobObjectGuard` RAII 包装器 + Drop
- [x] `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 配置
- [x] 使用 `OpenProcess` 获取进程句柄（非 PID 直接转换）

## Phase 2: 核心域模型

- [x] `SkillGroup` 实现
- [x] `ModeRegistry` 10 种执行模式注册
- [x] `SkillManager` toggle/activate/deactivate 逻辑
- [x] `KeyValidator` 按键校验
- [x] `KeyRecorder` 按键录制
- [x] `JoystickInput` 手柄输入模型
- [x] `Executor` 执行调度器
- [x] `ConfigValidator` 10 种模式校验
- [x] `intervals`/`delays` 为 `Vec<u64>`（非单个值）
- [x] 13 个 Tauri Commands 实现完整
- [x] `hotkey_cmd.rs` RwLockWriteGuard 在 await 前 drop
- [x] `stop_recording` 使用 seq 关联请求-响应（非 oneshot）
- [x] `ConfigService` 和 `GroupService` 应用层服务实现
- [x] Tauri Builder 注册所有 13 个 Commands + global-shortcut 插件

## Phase 3: Tauri UI 集成

- [x] HTML/CSS/JS 迁移到 src/ 目录
- [x] JS 调用从 AHK COM Bridge 改为 Tauri invoke()
- [x] `api.js` 5 个命名空间封装（config/group/hotkey/recording/system）
- [x] Tauri Events 替代 AHK 定时器推送
- [x] 系统托盘使用 `tauri` 核心 `tray-icon` feature（非 tauri-plugin-tray）
- [x] `TrayIconBuilder` + 菜单实现
- [x] 全局快捷键使用 `tauri-plugin-global-shortcut` 2.3.1
- [x] `on_shortcut` 回调 3 参数（&AppHandle, &Shortcut, ShortcutEvent）
- [x] 仪表盘和分组编辑器数据绑定

## 前置：IPC 架构缺陷修复

- [x] `cargo check` 编译通过，退出码 0
- [x] `cargo test --lib` 全部通过，退出码 0（94 tests）
- [x] `cargo clippy` 无警告，退出码 0
- [x] WatchdogRunner::from_arc() 方法存在且为 pub
- [x] ProcessWatchdog::set_state() 为 pub fn
- [x] ipc_tests.rs 中所有测试使用 IpcCommand enum 语法
- [x] ipc_tests.rs 中所有集成测试使用服务端模式（create_listener + accept）
- [x] fix-ipc-architecture-defects/tasks.md 已更新

## Phase 4: AHK 子进程适配

### Task 4.1: AHK IPC 客户端

- [x] ahk_executor/ 目录结构完整（executor.ahk / ipc_client.ahk / hotkey_hook.ahk / sender.ahk / joystick.ahk）
- [x] 每个 .ahk 文件顶部包含 #Requires + #ErrorStdOut + #Warn + OnError 指令
- [ ] AHK Named Pipe 客户端成功连接 Rust 侧 Listener（\\.\pipe\asd_ipc）
- [x] 连接失败时指数退避重试（1s→2s→4s→8s→30s）
- [x] 管道断裂时自动断线重连
- [x] JSON Lines 解析正确（\n 分隔 + 内联 MiniJson 解析 + 64KB 限制）
- [x] seq/ack_seq 确认机制正常（忽略重复消息 + execute 按 seq 排序）
- [x] 心跳响应正常（收到 ping → 回复 pong）
- [x] 心跳超时检测正常（5s 无 ping → 判定断开 → 重连）
- [ ] AHK 启动后成功连接 Rust，ping/pong 心跳持续正常

### Task 4.2: 热键与执行适配

- [x] 收到 RegisterHotkey IPC 指令 → AHK Hotkey 注册成功
- [x] 收到 UnregisterHotkey IPC 指令 → AHK Hotkey 注销成功
- [x] 热键触发 → IPC 上报 hotkey_event 消息
- [x] 支持组合键（Ctrl+ / Shift+ / Alt+）
- [x] 热键注册失败 → IPC 上报 error 消息
- [x] 收到 ToggleGroup(active:true) → 按模式执行按键序列
- [x] periodic 模式：按 intervals 间隔循环发送
- [x] sequence 模式：按 delays 间隔顺序发送
- [x] enhanced_periodic/enhanced_sequence：holdPattern/holdTriggers 支持
- [x] 收到 ToggleGroup(active:false) → 停止执行
- [x] joystick 模式通过 DllCall vJoy SDK 执行
- [x] SendInput 失败 → IPC 上报 error 消息
- [x] vJoy DLL 加载失败 → IPC 上报 error 消息
- [x] 收到 EmergencyRelease → 释放所有按键 + 停止所有定时器
- [x] 收到 HoldModeToggle → 切换 hold 模式
- [ ] 前端 toggle_group → Rust IPC → AHK 执行 → 结果上报 全链路贯通
- [ ] 前端 register_hotkey → Rust IPC → AHK 注册 → 热键触发 → 事件上报 全链路贯通

### Task 4.3: AHK 编译

- [x] Ahk2Exe 编译成功，生成 asd_executor.exe（1.25MB）
- [ ] asd_executor.exe 启动后 Named Pipe 连接正常
- [ ] asd_executor.exe ping/pong 心跳正常
- [ ] asd_executor.exe 热键注册/触发正常
- [ ] asd_executor.exe 按键模拟正常
- [x] tauri.conf.json resources 包含 ahk_executor/asd_executor.exe + ahk_executor/*.ahk
- [ ] npm run tauri build 将 asd_executor.exe 打包进安装目录

## Phase 5: 集成测试与打磨

### Task 5.1: 测试体系

- [ ] domain 层单元测试覆盖 SkillManager toggle/activate/deactivate
- [ ] domain 层单元测试覆盖 ConfigValidator 10 种模式
- [ ] infrastructure 层单元测试覆盖 IpcManager mock
- [ ] infrastructure 层单元测试覆盖 ProcessWatchdog 状态转换
- [ ] commands 层单元测试覆盖 Tauri Command（mock AppState）
- [ ] 集成测试覆盖 config.json 反序列化 + roundtrip
- [ ] 集成测试覆盖 Named Pipe 回环
- [ ] 集成测试覆盖 Tauri invoke
- [ ] E2E 测试覆盖完整热键流程
- [ ] E2E 测试覆盖分组 toggle 流程
- [ ] E2E 测试覆盖配置保存/加载
- [ ] E2E 测试覆盖 EmergencyRelease

### Task 5.2: 性能基准测试

- [ ] criterion 基准：配置加载 <5ms
- [ ] criterion 基准：按键校验 <1ms
- [ ] criterion 基准：分组调度 <2ms
- [ ] criterion 基准：日志写入 <10ms
- [ ] IPC 延迟基准：Tauri invoke <0.1ms
- [ ] IPC 延迟基准：Named Pipe 往返 <1.2ms
- [ ] 启动速度测量：冷启动 200-400ms
- [ ] 与 AHK 原版性能对比报告已生成

### Task 5.3: 构建打包

- [ ] tauri.conf.json bundle targets 配置为 ["nsis"]
- [ ] 应用图标配置完成
- [ ] NSIS 安装包生成成功
- [ ] 安装包包含 asd.exe + asd_executor.exe
- [ ] 干净 Windows 环境安装成功
- [ ] 安装后 asd.exe 可正常启动
- [ ] 安装后 asd_executor.exe 可正常连接
- [ ] 卸载流程正常
- [ ] WebView2 运行时安装正常（downloadBootstrapper 模式）

### Task 5.4: 优雅关机与恢复验证

- [ ] Phase 1 关机：IPC shutdown 消息 → AHK 2s 内正常退出
- [ ] Phase 2 关机：WM_CLOSE → AHK 窗口关闭
- [ ] Phase 3 关机：TerminateProcess → 强制终止
- [ ] Job Object 孤儿防护：主进程崩溃后子进程自动终止
- [ ] Watchdog 崩溃恢复：检测 → 重启 → 状态恢复
- [ ] 重启后热键状态正确恢复
- [ ] 重启后分组状态正确恢复
- [ ] 最大重启次数限制（10 次）生效

### Task 5.5: 自动更新与文档

- [ ] tauri-plugin-updater 2.10.1 配置完成
- [ ] 更新检测和下载流程验证
- [ ] 迁移指南文档完成（AHK → Rust/Tauri 接口映射）
- [ ] 开发者文档完成（项目结构 / IPC 协议 / 调试策略 / 构建发布）

## 关键版本号一致性

- [ ] tauri: 2.11.2
- [ ] windows: 0.62.2（项目直接依赖，与 Tauri 0.61.x 双版本共存）
- [ ] serde: 1.0
- [ ] serde_json: 1.0
- [ ] tokio: 1.47.1 (LTS)
- [ ] interprocess: 2.4.2（features = ["tokio"]）
- [ ] thiserror: 2.0.18
- [ ] tracing: 0.1.44
- [ ] tauri-plugin-global-shortcut: 2.3.1
- [ ] tauri-plugin-updater: 2.10.1
- [ ] tauri-plugin-dialog: 2.7.1
- [ ] tauri-plugin-fs: 2.5.1
- [ ] MSRV: 1.95.0

## 已知问题规避

- [ ] 未使用 tauri-plugin-tray（使用 tauri 核心 tray-icon feature）
- [ ] 未使用 parking_lot（使用 std::sync + tokio::sync）
- [ ] 未使用 anyhow（AppError 使用 thiserror + 手动 Serialize）
- [ ] 未使用 GenerateConsoleCtrlEvent（使用 WM_CLOSE）
- [ ] 未使用 PID 直接转换 HANDLE（使用 OpenProcess）
- [ ] interprocess 使用 to_ns_name::<GenericNamespaced>()
- [ ] Cargo.toml 版本约束使用 "2.11"
- [ ] serde 映射使用方案 B（untagged + flatten），非 tag + flatten
- [ ] ipc_manager 使用 tokio::sync::Mutex（非 std::sync::Mutex）
- [ ] stop_recording 使用 seq 关联（非 oneshot::channel）

## 最终验收标准

### 功能验收

- [ ] [F1] 前端通过 Tauri invoke 调用所有 13 个 Commands 正常
- [ ] [F2] AHK 子进程通过 Named Pipe IPC 与 Rust 通信正常
- [ ] [F3] 热键注册/注销通过 IPC 指令控制
- [ ] [F4] 按键模拟通过 IPC 指令执行
- [ ] [F5] vJoy 调用通过 IPC 指令执行
- [ ] [F6] 10 种执行模式配置兼容
- [ ] [F7] ProcessWatchdog 崩溃恢复正常
- [ ] [F8] 优雅关机三阶段正常
- [ ] [F9] Job Object 孤儿进程防护正常
- [ ] [F10] 系统托盘 + 全局快捷键正常

### 性能验收

- [ ] [P1] 配置加载 <5ms
- [ ] [P2] JS↔Rust IPC <0.1ms
- [ ] [P3] Named Pipe 往返 <1.2ms
- [ ] [P4] 启动到可用 200-400ms

### 交付物验收

- [ ] [D1] NSIS 安装包生成成功
- [ ] [D2] 干净 Windows 环境安装/卸载正常
- [ ] [D3] asd_executor.exe 编译成功
- [ ] [D4] 所有测试通过（单元/集成/E2E）
