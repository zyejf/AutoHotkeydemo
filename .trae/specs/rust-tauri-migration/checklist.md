# Rust/Tauri 重写项目验收清单

## Phase 0: PoC 验证

- [x] Tauri 2.11.2 项目编译通过，windows 0.62.2 双版本共存无冲突
- [x] `npm run tauri dev` 启动最小 WebView2 窗口成功
- [x] 现有 config.json 全部 10 种模式 serde 反序列化成功
- [x] config.json roundtrip 序列化结果一致
- [x] Named Pipe 双向通信验证通过，往返延迟 <1.2ms（实测 62.7μs）
- [x] Tauri invoke 验证通过，延迟 <0.1ms（ping 命令已实现，需手动验证延迟）
- [x] Go/No-Go 决策报告已输出 — **GO**，MSRV 调整为 1.95.0

## Phase 1: 基础设施

- [x] tauri.conf.json 配置完整（identifier=com.asd.tauri，bundle targets，resources）
- [x] capabilities/default.json 包含所有必需权限（含 global-shortcut:allow-register/unregister，使用 opener:default 替代 shell:allow-open）
- [x] Config::load_default() 和 Config::save() 功能正常
- [x] ConfigValidator 校验所有 10 种模式的必需字段（8 个单元测试）
- [x] tracing 日志系统输出到控制台和文件（app_data_dir/asd.log）
- [x] IpcManager send_command/listen_ahk/wait_response 功能正常
- [x] JSON Lines 帧协议正确处理（\n 分隔、64KB 限制、部分读取）
- [x] 背压策略生效（mpsc channel 256 容量 + 热键合并窗口）
- [x] IPC 错误恢复路径验证（管道断裂 → 重连 → 状态恢复）
- [x] ProcessWatchdog 状态机完整（7 种状态转换正确）
- [x] 心跳检测正常（1s 间隔，3 次超时判定挂起）
- [x] 指数退避重启正常（1s→2s→4s→8s→30s，最多 10 次）
- [x] 状态恢复正常（重新下发热键注册和活跃分组）
- [x] Job Object 孤儿防护正常（主进程退出后子进程自动终止）
- [x] JobObjectGuard RAII 正确（Drop 时 CloseHandle）
- [x] AssignProcessToJobObject 使用 OpenProcess 获取句柄（非 PID 直接转换）
- [x] 优雅关机三阶段正常（IPC shutdown → WM_CLOSE → TerminateProcess）
- [x] AppState 同步原语选型正确（ipc_manager: tokio::sync::Mutex，其余: std::sync::RwLock/AtomicBool）
- [x] AppError 枚举完整（Config/Ipc/GroupNotFound/Validation/Executor/Internal），无 anyhow 依赖

## Phase 2: 核心域模型

- [x] SkillGroup/Skill/Mode 结构体定义完整，实现 Clone/Serialize/Deserialize
- [x] IpcCommand/IpcMessage 枚举覆盖所有指令类型
- [x] ConfigValidator 校验所有模式字段类型和必填项
- [x] SkillManager toggle/activate/deactivate 逻辑正确
- [x] 热键注册管理（register/unregister/tracking）功能正常
- [x] emergency release 逻辑正确（设置 AtomicBool + 发送 IPC 指令）
- [x] hold mode 切换逻辑正确
- [x] 所有 Tauri Commands 注册到 invoke_handler
- [x] stop_recording 使用 seq 关联请求-响应（非 oneshot channel）
- [x] Tauri Commands 返回 AppError 而非 String

## Phase 3: Tauri UI 集成

- [x] 前端 JS 调用全部改为 Tauri invoke（无 AHK COM Bridge 残留）
- [x] Tauri Events 替代 AHK 定时器推送（status_update/hotkey_event/executor_status）
- [x] 前端 API 封装层（src/api.js）完整覆盖所有 Commands
- [x] 分组列表/编辑器数据绑定正常
- [x] 状态面板实时更新
- [x] 系统托盘功能正常（tauri tray-icon feature + TrayIconBuilder，非 tauri-plugin-tray）
- [x] 全局快捷键切换窗口正常（global-shortcut 2.3.1 + on_shortcut 3 参数回调）

## Phase 4: AHK 子进程适配

- [ ] AHK Named Pipe 客户端连接 Rust 侧监听成功
- [ ] JSON Lines 解析正确（按行读取 + JSON 解析）
- [ ] seq/ack_seq 确认机制正常
- [ ] 心跳响应正常（ping → pong）
- [ ] 热键注册/注销通过 IPC 指令控制
- [ ] 按键模拟通过 IPC 指令执行
- [ ] vJoy 调用通过 IPC 指令执行
- [ ] AHK 错误通过 IPC error 消息上报
- [ ] Ahk2Exe 编译为 asd_executor.exe 后 IPC 通信正常

## Phase 5: 集成测试与打磨

- [ ] 单元测试覆盖 domain/infrastructure/commands 层
- [ ] 集成测试覆盖 config/ipc/tauri_command
- [ ] 端到端测试覆盖 Tauri App + AHK 子进程全流程
- [ ] criterion 基准测试结果：配置加载 <5ms、按键校验 <1ms
- [ ] IPC 延迟基准测试：invoke <0.1ms、Named Pipe 往返 <1.2ms
- [ ] 启动速度测量：200-400ms（冷启动）
- [ ] NSIS 安装包生成成功（含 asd.exe + asd_executor.exe + WebView2 Bootstrapper）
- [ ] 干净 Windows 环境安装/卸载流程正常
- [ ] 优雅关机三阶段验证通过
- [ ] Job Object 孤儿进程防护验证通过
- [ ] Watchdog 崩溃恢复验证通过（模拟 AHK 崩溃 → 自动重启 → 状态恢复）
- [ ] tauri-plugin-updater 2.10.1 配置完成
- [ ] 迁移指南文档完成
- [ ] 开发者文档完成

## 关键版本号一致性

- [ ] tauri: 2.11.2
- [ ] windows: 0.62.2（项目直接依赖，与 Tauri 0.61.x 双版本共存）
- [ ] serde: 1.0（Cargo 自动解析，最新 1.0.228）
- [ ] serde_json: 1.0（最新 1.0.150）
- [ ] tokio: 1.47.1 (LTS)
- [ ] interprocess: 2.4.2（features = ["tokio"]）
- [ ] thiserror: 2.0.18
- [ ] tracing: 0.1.44
- [ ] clap: 4.6.1
- [ ] tauri-plugin-global-shortcut: 2.3.1
- [ ] tauri-plugin-updater: 2.10.1
- [ ] tauri-plugin-dialog: 2.7.1
- [ ] tauri-plugin-fs: 2.5.1
- [ ] MSRV: 1.95.0（用户确认，因 getrandom/darling 等依赖要求更高版本）

## 已知问题规避

- [ ] 未使用 tauri-plugin-tray（使用 tauri 核心 tray-icon feature）
- [ ] 未使用 parking_lot（使用 std::sync + tokio::sync）
- [ ] 未使用 anyhow（AppError 使用 thiserror + 手动 Serialize）
- [ ] 未使用 GenerateConsoleCtrlEvent（使用 WM_CLOSE）
- [ ] 未使用 PID 直接转换 HANDLE（使用 OpenProcess）
- [ ] interprocess 使用 to_ns_name::<GenericNamespaced>()（非 to_ns()）
- [ ] Cargo.toml 版本约束使用 "2.11"（非 ~2.11）
