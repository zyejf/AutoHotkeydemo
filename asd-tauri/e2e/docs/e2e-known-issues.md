# E2E 已知问题

## 已解决问题

### ISSUE-011 [RESOLVED] msedgedriver.exe 缺失

- **状态**: ✅ 已解决（2026-06-28）
- **原描述**: msedgedriver.exe 未安装，导致所有 E2E 测试无法启动 WebDriver 会话
- **解决方案**: 下载 msedgedriver 149.0.4022.98 到 `e2e/drivers/msedgedriver.exe`，tauri-driver 通过 `--native-driver` 参数显式指定
- **验证**: smoke 测试通过，WebDriver 会话成功建立

### ISSUE-012 [RESOLVED] Binary 使用 devUrl 而非 frontendDist

- **状态**: ✅ 已解决（2026-06-28）
- **原描述**: `cargo build --release` 构建的 binary 使用 `devUrl`（http://127.0.0.1:5173）而非 `frontendDist`（../dist），导致 webview 无法加载页面，msedgedriver 报 "Origin header is not a valid URL" 错误
- **解决方案**: 改用 `npx tauri build --debug --no-bundle` 构建 binary，正确嵌入前端
- **验证**: 页面标题返回 "技能管理器 v3.0"，executeScript 调用成功

## 未解决问题

### ISSUE-013 [HIGH] build_ahk.ps1 PowerShell 语法错误

- **关联用例**: 所有依赖 AHK 子进程的测试（17 个）
- **复现步骤**: 执行 `npx tauri build --debug --no-bundle`（beforeBuildCommand 调用 build_ahk.ps1）
- **预期**: PowerShell 脚本正常执行，生成 asd_executor.exe
- **实际**: 报错 "表达式或语句中包含意外的标记'}'"（line 29 char 1）
- **影响**: AHK 子进程未构建，所有 IPC/key_send/modes 测试失败
- **建议**: 检查 build_ahk.ps1 编码（可能为 BOM 或 CRLF 问题）；或改用 portable 模式跳过编译

### ISSUE-014 [MEDIUM] get_executor_status 字段命名不一致

- **关联用例**: E2E-SYS-001
- **复现步骤**: 调用 `get_executor_status` 命令
- **预期**: 返回 `restartCount`（camelCase）
- **实际**: 返回 `restart_count`（snake_case）：`{"backoffDurationSecs":1,"restart_count":0,"status":"Running"}`
- **影响**: E2E-SYS-001 断言失败
- **建议**: 修改测试断言使用 `restart_count`，或在 Tauri command 中统一 camelCase 序列化

### ISSUE-015 [MEDIUM] Tauri invoke 错误消息为 "unknown error"

- **关联用例**: E2E-GRP-004, 005, E2E-HK-002, 003, E2E-REC-002~005, E2E-SYS-004, 005（共 15 个）
- **复现步骤**: 当 IPC 失败时调用 Tauri invoke 命令
- **预期**: 错误消息包含 IPC/超时/连接等关键词，匹配测试正则
- **实际**: 错误消息为 "unknown error"，不匹配任何预期模式
- **影响**: 测试用例的正则断言失败
- **建议**: 
  1. 在 `helpers/tauri.js` 中改进错误消息提取，序列化完整错误对象
  2. 或修改测试断言接受 "unknown error" 作为合理错误

### ISSUE-016 [HIGH] AHK 子进程未运行导致 IPC 测试失败

- **关联用例**: E2E-IPC-001, 003~006, E2E-KEY-001~005, E2E-MODE-001~007（共 17 个）
- **复现步骤**: 启动应用后调用依赖 AHK 子进程的命令（toggle_group 激活、key_send 等）
- **预期**: AHK 子进程通过 named pipe 连接，命令成功执行
- **实际**: IPC 通信错误 "连接已关闭"（AHK 子进程未启动）
- **影响**: 所有 IPC/key_send/modes 测试失败
- **建议**: 修复 ISSUE-013 后重新构建 binary，AHK 子进程将正常启动

### ISSUE-E2E-GRP-004 [HIGH] toggle_all 失败

- **关联用例**: E2E-GRP-004: 切换所有分组状态为 active=true，再恢复为 false
- **复现步骤**: 调用 `toggle_all` 命令
- **预期**: 测试应通过
- **实际**: invoke 返回 "unknown error"
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-015 后重新验证

### ISSUE-E2E-GRP-005 [HIGH] batch_toggle_groups 失败

- **关联用例**: E2E-GRP-005: 批量切换指定 ID 列表的分组
- **复现步骤**: 调用 `batch_toggle_groups` 命令
- **预期**: 测试应通过
- **实际**: invoke 返回 "unknown error"
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-015 后重新验证

### ISSUE-E2E-HK-002 [HIGH] unregister_hotkey 失败

- **关联用例**: E2E-HK-002: 注销活跃分组热键后分组变为非活跃
- **复现步骤**: 调用 `unregister_hotkey` 命令
- **预期**: 测试应通过
- **实际**: invoke 返回 "unknown error"
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-015 后重新验证

### ISSUE-E2E-HK-003 [HIGH] 热键实际触发失败

- **关联用例**: E2E-HK-003: 注册热键并模拟按下，key_log.txt 捕获按键事件
- **复现步骤**: 注册热键后模拟按键
- **预期**: key_log.txt 包含按键事件
- **实际**: invoke 返回 "unknown error"（依赖 AHK 子进程）
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-013 和 ISSUE-015 后重新验证

### ISSUE-E2E-IPC-001 [HIGH] watchdog 状态断言失败

- **关联用例**: E2E-IPC-001: 应用启动后 watchdog 状态应为 Running/Starting/Idle
- **复现步骤**: 调用 `get_executor_status` 命令
- **预期**: status 字段为 Running/Starting/Idle
- **实际**: AHK 子进程未启动时 watchdog 可能进入 Failed 状态
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-013 后重新验证

### ISSUE-E2E-IPC-003 [HIGH] 心跳维持测试失败

- **关联用例**: E2E-IPC-003: 等待 5 秒后 watchdog 仍为 Running
- **复现步骤**: 获取初始状态 → 等待 5 秒 → 再次获取状态
- **预期**: watchdog 维持 Running 状态
- **实际**: AHK 子进程未运行，心跳无法维持
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-013 后重新验证

### ISSUE-E2E-IPC-004~006 [HIGH] 事件转发测试失败

- **关联用例**: E2E-IPC-004 (hotkey_event), 005 (key_send_event), 006 (key_record_event)
- **复现步骤**: 注册事件监听器 → 激活分组 → 等待事件
- **预期**: 前端收到对应事件
- **实际**: AHK 子进程未运行，无事件产生
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-013 后重新验证

### ISSUE-E2E-KEY-001~005 [HIGH] 按键发送测试全失败

- **关联用例**: E2E-KEY-001 ~ 005
- **复现步骤**: 启动分组 → 等待按键执行 → 读取 key_log.txt
- **预期**: key_log.txt 包含按键事件
- **实际**: AHK 子进程未运行，无按键发送
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-013 后重新验证

### ISSUE-E2E-MODE-001~007 [HIGH] 7 种执行模式测试全失败

- **关联用例**: E2E-MODE-001 ~ 007
- **复现步骤**: 启动各模式分组 → 等待按键执行 → 验证间隔/顺序
- **预期**: 各模式按配置发送按键
- **实际**: AHK 子进程未运行，无按键发送
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-013 后重新验证

### ISSUE-E2E-REC-002~005 [HIGH] 录制状态机测试失败

- **关联用例**: E2E-REC-002 (pause), 003 (resume), 004 (stop), 005 (完整流程)
- **复现步骤**: start_recording → pause/resume/stop
- **预期**: 返回 seq 或合理 IPC 错误
- **实际**: invoke 返回 "unknown error"（不匹配预期正则）
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-015 后重新验证

### ISSUE-E2E-SYS-001 [HIGH] restartCount 字段不存在

- **关联用例**: E2E-SYS-001
- **复现步骤**: 调用 `get_executor_status` 命令
- **预期**: 返回 `restartCount`（camelCase）
- **实际**: 返回 `restart_count`（snake_case）
- **影响**: E2E 测试失败
- **建议**: 见 ISSUE-014

### ISSUE-E2E-SYS-004 [HIGH] toggle_hold_mode 失败

- **关联用例**: E2E-SYS-004: 切换 hold 模式状态
- **复现步骤**: 调用 `toggle_hold_mode` 命令
- **预期**: 返回新状态（bool）
- **实际**: invoke 返回 "unknown error"
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-015 后重新验证

### ISSUE-E2E-SYS-005 [HIGH] reset_watchdog 失败

- **关联用例**: E2E-SYS-005: 调用 reset_watchdog
- **复现步骤**: 调用 `reset_watchdog` 命令
- **预期**: 状态重置或返回合理前置条件错误
- **实际**: invoke 返回 "unknown error"
- **影响**: E2E 测试失败
- **建议**: 修复 ISSUE-015 后重新验证
