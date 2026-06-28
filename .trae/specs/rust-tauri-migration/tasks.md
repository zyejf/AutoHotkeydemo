# Tasks

## Phase 0: PoC 验证（1 周）

- [x] Task 0.1: Tauri 2.11.2 项目初始化
  - [x] SubTask 0.1.1: 执行 `npm create tauri-app` 创建项目骨架
  - [x] SubTask 0.1.2: 配置 Cargo.toml 依赖（tauri 2.11.2、serde 1.0、serde_json 1.0、windows 0.62.2、tokio 1.47.1、interprocess 2.4.2、thiserror 2.0、tracing 0.1、clap 4.6）
  - [x] SubTask 0.1.3: 配置 rust-toolchain.toml（MSRV 调整为 1.88.0，因 getrandom/darling 等依赖要求更高版本）
  - [x] SubTask 0.1.4: 验证 `cargo build` 编译通过（确认 windows 0.62.2 与 Tauri 0.61.x 双版本共存无冲突）
  - [x] SubTask 0.1.5: 验证 `npm run tauri dev` 启动最小 WebView2 窗口

- [x] Task 0.2: serde config.json 反序列化验证
  - [x] SubTask 0.2.1: 定义 GroupConfig 结构体（采用自定义 Deserialize 方案，因 flatten+untagged 有兼容性问题）
  - [x] SubTask 0.2.2: 定义 10 种执行模式的 ModeData Variant
  - [x] SubTask 0.2.3: 使用实际 config.json 测试反序列化（含 hybrid/periodic/hold/enhanced_*/joystick_*）
  - [x] SubTask 0.2.4: 验证 roundtrip 序列化一致性
  - [x] SubTask 0.2.5: 验证 serde tag+flatten 兼容性（已切换到自定义 Deserialize，15/15 测试通过）

- [x] Task 0.3: Named Pipe IPC 双向通信验证
  - [x] SubTask 0.3.1: 实现 Rust 侧 IpcManager（interprocess local_socket + tokio 异步）
  - [x] SubTask 0.3.2: 实现 Rust 侧回环测试客户端（AHK 侧客户端留待 Phase 4）
  - [x] SubTask 0.3.3: 验证 JSON Lines 帧协议（\n 分隔、64KB 上限、BufReader read_line）
  - [x] SubTask 0.3.4: 测量往返延迟（平均 62.7μs，远低于 1.2ms 目标）
  - [x] SubTask 0.3.5: 验证 seq/ack_seq 序号机制

- [x] Task 0.4: Tauri invoke 最小验证
  - [x] SubTask 0.4.1: 实现 `#[tauri::command] fn ping() -> String`
  - [x] SubTask 0.4.2: 前端调用 `invoke('ping')` 验证 JS↔Rust 通信
  - [x] SubTask 0.4.3: 测量 invoke 延迟（需手动在 Tauri 窗口中验证）

- [x] Task 0.5: Go/No-Go 决策
  - [x] SubTask 0.5.1: 汇总 PoC 验证结果
  - [x] SubTask 0.5.2: 输出 Go/No-Go 决策报告 — **GO**，MSRV 调整为 1.95.0

## Phase 1: 基础设施（2 周）

- [x] Task 1.1: Tauri 项目骨架完善
  - [x] SubTask 1.1.1: 配置 tauri.conf.json（identifier=com.asd.tauri，标题，bundle targets，resources）
  - [x] SubTask 1.1.2: 配置 capabilities/default.json（core:default、window、opener:default、dialog、fs、global-shortcut）
  - [x] SubTask 1.1.3: 配置 Tauri 插件（global-shortcut 2.3.1、updater 2.10.1、dialog 2.7.1、fs 2.5.1）
  - [x] SubTask 1.1.4: 启用 tray-icon feature（已在 Cargo.toml 中配置）

- [x] Task 1.2: serde 配置管理
  - [x] SubTask 1.2.1: 完善 Config/ControlHotkeys/HoldSettings 结构体
  - [x] SubTask 1.2.2: 实现 Config::load_default() 和 Config::save()
  - [x] SubTask 1.2.3: 实现 ConfigValidator 校验逻辑（8 个单元测试）
  - [x] SubTask 1.2.4: 单元测试覆盖所有 10 种模式

- [x] Task 1.3: tracing 日志系统
  - [x] SubTask 1.3.1: 配置 tracing subscriber（fmt + 文件输出，日志路径：app_data_dir/asd.log）
  - [x] SubTask 1.3.2: 定义日志级别约定（ERROR/WARN/INFO/DEBUG）
  - [x] SubTask 1.3.3: 实现 IPC 消息日志（在 IpcManager 中集成 tracing）

- [x] Task 1.4: Named Pipe IPC 框架
  - [x] SubTask 1.4.1: 实现 IpcManager（send_command / listen_ahk / wait_response）
  - [x] SubTask 1.4.2: 实现 JSON Lines 帧协议（BufReader + read_line + 64KB 限制）
  - [x] SubTask 1.4.3: 实现背压策略（mpsc channel 256 容量 + 热键合并窗口 100ms）
  - [x] SubTask 1.4.4: 实现错误恢复路径（管道断裂 → Watchdog 重启 → 状态恢复）
  - [x] SubTask 1.4.5: 集成测试（本地回环测试）

- [x] Task 1.5: ProcessWatchdog 子进程守护
  - [x] SubTask 1.5.1: 实现 WatchdogStateEnum 状态机（Idle/Starting/Running/Hung/Restarting/Recovering/Failed）
  - [x] SubTask 1.5.2: 实现心跳检测（1s 间隔，3 次超时判定挂起）
  - [x] SubTask 1.5.3: 实现指数退避重启（1s→2s→4s→8s→30s，最多 10 次）
  - [x] SubTask 1.5.4: 实现状态恢复（重新下发热键注册和活跃分组）
  - [x] SubTask 1.5.5: 实现 Windows Job Object 孤儿防护（JobObjectGuard RAII + OpenProcess + AssignProcessToJobObject）
  - [x] SubTask 1.5.6: 实现优雅关机（IPC shutdown → WM_CLOSE → TerminateProcess）

- [x] Task 1.6: Tauri 状态管理
  - [x] SubTask 1.6.1: 定义 AppState 结构体（config: RwLock、groups: RwLock、ipc_manager: tokio::sync::Mutex、ipc_outbound: mpsc、active_hotkeys: RwLock、emergency_mode: AtomicBool、hold_mode_enabled: AtomicBool、watchdog_state: RwLock）
  - [x] SubTask 1.6.2: 定义 AppError 枚举（Config/Ipc/GroupNotFound/Validation/Executor/Internal）+ Serialize 实现
  - [x] SubTask 1.6.3: 实现 Tauri Builder setup（初始化 AppState + spawn IPC listener + spawn Watchdog）

## Phase 2: 核心域模型（3 周）

- [x] Task 2.1: 数据模型定义
  - [x] SubTask 2.1.1: 定义 SkillGroup（含 mode_data）/Mode 结构体
  - [x] SubTask 2.1.2: 定义 JoystickInput/JoystickConfig 结构体（在 ModeData 枚举中覆盖）
  - [x] SubTask 2.1.3: 定义 IpcCommand/IpcMessage/IpcError 枚举
  - [x] SubTask 2.1.4: 实现 Clone/Serialize/Deserialize for 所有模型

- [x] Task 2.2: 配置校验引擎
  - [x] SubTask 2.2.1: 实现字段必填校验（每种 mode 的必需字段）
  - [x] SubTask 2.2.2: 实现字段类型校验（intervals: Vec<u64>、keys: Vec<String> 等）
  - [x] SubTask 2.2.3: 实现跨字段校验（热键格式、重复检测、hold 模式关联）
  - [x] SubTask 2.2.4: 实现 ValidationResult 结构化输出（含 warnings 和 valid 字段）

- [x] Task 2.3: 执行调度器
  - [x] SubTask 2.3.1: 实现 SkillManager（分组激活/停用/toggle）
  - [x] SubTask 2.3.2: 实现模式分发逻辑（build_execute_command 根据 mode 构造 IpcCommand）
  - [x] SubTask 2.3.3: 实现热键注册管理（register/unregister/tracking）
  - [x] SubTask 2.3.4: 实现 emergency release 逻辑
  - [x] SubTask 2.3.5: 实现 hold mode 切换逻辑

- [x] Task 2.4: Tauri Commands 实现
  - [x] SubTask 2.4.1: 实现 config_cmd（get_config / save_config / validate_config）
  - [x] SubTask 2.4.2: 实现 group_cmd（get_groups / toggle_group / get_group_detail）
  - [x] SubTask 2.4.3: 实现 hotkey_cmd（register_hotkey / unregister_hotkey）
  - [x] SubTask 2.4.4: 实现 recording_cmd（start_recording / stop_recording，使用 seq 关联请求-响应）
  - [x] SubTask 2.4.5: 实现 system_cmd（get_executor_status / emergency_release / toggle_hold_mode）
  - [x] SubTask 2.4.6: 注册所有 13 个 Commands 到 invoke_handler

## Phase 3: Tauri UI 集成（2 周）

- [x] Task 3.1: 前端资产迁移
  - [x] SubTask 3.1.1: 迁移 HTML/CSS/JS 到 src/ 目录
  - [x] SubTask 3.1.2: 替换 AHK COM Bridge 调用为 Tauri invoke
  - [x] SubTask 3.1.3: 替换 AHK 定时器推送为 Tauri Events（listen('status_update') / listen('hotkey_event') / listen('executor_status')）
  - [x] SubTask 3.1.4: 实现前端 API 封装层（src/api.js）

- [x] Task 3.2: 仪表盘与编辑器
  - [x] SubTask 3.2.1: 实现分组列表数据绑定（invoke get_groups → 渲染）
  - [x] SubTask 3.2.2: 实现分组编辑器（invoke save_config → 刷新）
  - [x] SubTask 3.2.3: 实现状态面板（executor_status 实时更新）
  - [x] SubTask 3.2.4: 实现热键显示面板

- [x] Task 3.3: 系统托盘
  - [x] SubTask 3.3.1: 配置 tray-icon feature + TrayIconBuilder
  - [x] SubTask 3.3.2: 实现托盘菜单（显示/隐藏/退出）
  - [x] SubTask 3.3.3: 实现全局快捷键切换窗口（global-shortcut 2.3.1 + on_shortcut API）

## Phase 4: AHK 子进程适配（1 周）

- [ ] Task 4.1: AHK IPC 客户端
  - [ ] SubTask 4.1.1: 实现 AHK 侧 Named Pipe 客户端（连接 Rust 侧监听）
  - [ ] SubTask 4.1.2: 实现 JSON Lines 解析（按行读取 + JSON 解析）
  - [ ] SubTask 4.1.3: 实现 seq/ack_seq 确认机制
  - [ ] SubTask 4.1.4: 实现心跳响应（ping → pong）

- [ ] Task 4.2: 热键与执行适配
  - [ ] SubTask 4.2.1: 适配热键注册/注销（接收 IPC 指令 → RegisterHotKey/UnregisterHotKey）
  - [ ] SubTask 4.2.2: 适配按键模拟（接收 IPC 指令 → Send/SendInput）
  - [ ] SubTask 4.2.3: 适配 vJoy 调用（接收 IPC 指令 → DllCall vJoy SDK）
  - [ ] SubTask 4.2.4: 实现错误上报通道（AHK 异常 → IPC error 消息）

- [ ] Task 4.3: AHK 编译
  - [ ] SubTask 4.3.1: 使用 Ahk2Exe 编译为 asd_executor.exe
  - [ ] SubTask 4.3.2: 验证编译后 exe 的 IPC 通信正常

## Phase 5: 集成测试与打磨（2 周）

- [ ] Task 5.1: 测试体系
  - [ ] SubTask 5.1.1: 单元测试（domain 层纯逻辑、infrastructure 层 mock IPC/配置、commands 层 Tauri Command）
  - [ ] SubTask 5.1.2: 集成测试（config_tests: 实际 config.json 反序列化、ipc_tests: Named Pipe 回环、tauri_command_tests: invoke 集成）
  - [ ] SubTask 5.1.3: 端到端测试（Tauri App + AHK 子进程全流程，需 AHK 运行时环境）

- [ ] Task 5.2: 性能基准测试
  - [ ] SubTask 5.2.1: criterion 基准测试（配置加载、按键校验、分组调度、日志写入）
  - [ ] SubTask 5.2.2: IPC 延迟基准测试（invoke 延迟、Named Pipe 往返延迟）
  - [ ] SubTask 5.2.3: 启动速度测量（冷启动/热启动）
  - [ ] SubTask 5.2.4: 与 AHK 原版性能对比

- [ ] Task 5.3: 构建打包
  - [ ] SubTask 5.3.1: 配置 NSIS 安装包（tauri.conf.json bundle targets）
  - [ ] SubTask 5.3.2: 配置 AHK 子进程打包（resources: ahk_executor/*）
  - [ ] SubTask 5.3.3: 配置 WebView2 安装模式（downloadBootstrapper + 离线提示）
  - [ ] SubTask 5.3.4: 验证安装包在干净 Windows 环境的安装/卸载流程

- [ ] Task 5.4: 优雅关机与恢复验证
  - [ ] SubTask 5.4.1: 验证 IPC shutdown → WM_CLOSE → TerminateProcess 三阶段关机
  - [ ] SubTask 5.4.2: 验证 Job Object 孤儿进程防护（主进程崩溃后子进程自动终止）
  - [ ] SubTask 5.4.3: 验证 Watchdog 崩溃恢复（模拟 AHK 崩溃 → 自动重启 → 状态恢复）

- [ ] Task 5.5: 自动更新与文档
  - [ ] SubTask 5.5.1: 配置 tauri-plugin-updater 2.10.1
  - [ ] SubTask 5.5.2: 编写迁移指南（AHK → Rust/Tauri 接口映射）
  - [ ] SubTask 5.5.3: 编写开发者文档（项目结构、IPC 协议、调试策略）

# Task Dependencies

- [Task 0.1-0.4] 可并行执行（PoC 四项验证相互独立）
- [Task 0.5] 依赖 [Task 0.1-0.4] 全部完成
- [Task 1.1-1.3] 可并行执行
- [Task 1.4] 依赖 [Task 0.3]（IPC 验证通过）
- [Task 1.5] 依赖 [Task 1.4]（Watchdog 需要 IPC 框架）
- [Task 1.6] 依赖 [Task 1.2, 1.4, 1.5]（AppState 整合所有组件）
- [Task 2.1-2.3] 可并行执行
- [Task 2.4] 依赖 [Task 2.1-2.3, 1.6]（Commands 需要域模型和状态管理）
- [Task 3.1] 依赖 [Task 2.4]（前端需要后端 API 就绪）
- [Task 3.2] 依赖 [Task 3.1]
- [Task 3.3] 依赖 [Task 1.1]（需要插件配置完成）
- [Task 4.1] 依赖 [Task 1.4]（AHK 客户端需要 IPC 协议确定）
- [Task 4.2] 依赖 [Task 4.1, 2.3]（执行适配需要 IPC 和调度逻辑）
- [Task 4.3] 依赖 [Task 4.2]
- [Task 5.1] 依赖 [Task 2.4, 3.1, 4.2]（测试需要核心功能就绪）
- [Task 5.2] 依赖 [Task 5.1]（基准测试需要功能稳定）
- [Task 5.3] 依赖 [Task 4.3]（打包需要 AHK 编译完成）
- [Task 5.4] 依赖 [Task 1.5, 4.2]（关机验证需要子进程管理完成）
- [Task 5.5] 依赖 [Task 5.3]（自动更新需要打包就绪）
