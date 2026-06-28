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
## ISSUE-E2E-GRP-003 [HIGH] (关联用例: E2E-GRP-003)

- **复现步骤:** 执行测试用例 E2E-GRP-003: 切换分组状态，get_group_detail 返回的 active 字段翻转
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-GRP-003: 切换分组状态，get_group_detail 返回的 active 字段翻转
- **建议:** 检查相关 Tauri 命令实现与测试断言

## ISSUE-E2E-GRP-004 [HIGH] (关联用例: E2E-GRP-004)

- **复现步骤:** 执行测试用例 E2E-GRP-004: 切换所有分组状态为 active=true，再恢复为 false
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-GRP-004: 切换所有分组状态为 active=true，再恢复为 false
- **建议:** 检查相关 Tauri 命令实现与测试断言

## ISSUE-E2E-GRP-005 [HIGH] (关联用例: E2E-GRP-005)

- **复现步骤:** 执行测试用例 E2E-GRP-005: 批量切换指定 ID 列表的分组，其他分组不受影响
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-GRP-005: 批量切换指定 ID 列表的分组，其他分组不受影响
- **建议:** 检查相关 Tauri 命令实现与测试断言

## ISSUE-E2E-HK-002 [HIGH] (关联用例: E2E-HK-002)

- **复现步骤:** 执行测试用例 E2E-HK-002: 注销活跃分组热键后分组变为非活跃（active=false）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-HK-002: 注销活跃分组热键后分组变为非活跃（active=false）
- **建议:** 检查相关 Tauri 命令实现与测试断言

## ISSUE-E2E-HK-003 [HIGH] (关联用例: E2E-HK-003)

- **复现步骤:** 执行测试用例 E2E-HK-003: 启动按键接收窗口，注册热键并模拟按下，key_log.txt 捕获到按键事件
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-HK-003: 启动按键接收窗口，注册热键并模拟按下，key_log.txt 捕获到按键事件
- **建议:** 检查相关 Tauri 命令实现与测试断言

## ISSUE-应用启动后 watchdog 状态应为 Running/Starting/Idle [HIGH] (关联用例: 应用启动后 watchdog 状态应为 Running/Starting/Idle)

- **复现步骤:** 执行测试用例 应用启动后 watchdog 状态应为 Running/Starting/Idle
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 应用启动后 watchdog 状态应为 Running/Starting/Idle
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-toggle_group 命令成功返回 GroupStatus 或合理 IPC 错误 [HIGH] (关联用例: toggle_group 命令成功返回 GroupStatus 或合理 IPC 错误)

- **复现步骤:** 执行测试用例 toggle_group 命令成功返回 GroupStatus 或合理 IPC 错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: toggle_group 命令成功返回 GroupStatus 或合理 IPC 错误
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-等待 5 秒后 watchdog 仍为 Running（心跳正常） [HIGH] (关联用例: 等待 5 秒后 watchdog 仍为 Running（心跳正常）)

- **复现步骤:** 执行测试用例 等待 5 秒后 watchdog 仍为 Running（心跳正常）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 等待 5 秒后 watchdog 仍为 Running（心跳正常）
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-前端通过 hotkey_event 事件收到热键通知（或记录已知问题） [HIGH] (关联用例: 前端通过 hotkey_event 事件收到热键通知（或记录已知问题）)

- **复现步骤:** 执行测试用例 前端通过 hotkey_event 事件收到热键通知（或记录已知问题）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 前端通过 hotkey_event 事件收到热键通知（或记录已知问题）
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-分组执行时前端收到 key_send_event 事件（或记录已知问题） [HIGH] (关联用例: 分组执行时前端收到 key_send_event 事件（或记录已知问题）)

- **复现步骤:** 执行测试用例 分组执行时前端收到 key_send_event 事件（或记录已知问题）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 分组执行时前端收到 key_send_event 事件（或记录已知问题）
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-录制时前端收到 key_record_event 事件（或记录已知问题） [HIGH] (关联用例: 录制时前端收到 key_record_event 事件（或记录已知问题）)

- **复现步骤:** 执行测试用例 录制时前端收到 key_record_event 事件（或记录已知问题）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 录制时前端收到 key_record_event 事件（或记录已知问题）
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-KEY-001 [HIGH] (关联用例: E2E-KEY-001)

- **复现步骤:** 执行测试用例 E2E-KEY-001: 应捕获到 periodic 分组的 Space 按键事件
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-KEY-001: 应捕获到 periodic 分组的 Space 按键事件
- **建议:** 检查 AHK 执行器按键发送逻辑与测试断言

## ISSUE-E2E-KEY-002 [HIGH] (关联用例: E2E-KEY-002)

- **复现步骤:** 执行测试用例 E2E-KEY-002: 周期性按键的实际间隔与配置间隔误差应在 ±20ms 内
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-KEY-002: 周期性按键的实际间隔与配置间隔误差应在 ±20ms 内
- **建议:** 检查 AHK 执行器按键发送逻辑与测试断言

## ISSUE-E2E-KEY-003 [HIGH] (关联用例: E2E-KEY-003)

- **复现步骤:** 执行测试用例 E2E-KEY-003: sequence 模式的按键顺序应与配置一致（1→2→3）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-KEY-003: sequence 模式的按键顺序应与配置一致（1→2→3）
- **建议:** 检查 AHK 执行器按键发送逻辑与测试断言

## ISSUE-E2E-KEY-004 [HIGH] (关联用例: E2E-KEY-004)

- **复现步骤:** 执行测试用例 E2E-KEY-004: holdDuration 期间按键持续按住，结束时释放
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-KEY-004: holdDuration 期间按键持续按住，结束时释放
- **建议:** 检查 AHK 执行器按键发送逻辑与测试断言

## ISSUE-E2E-KEY-005 [HIGH] (关联用例: E2E-KEY-005)

- **复现步骤:** 执行测试用例 E2E-KEY-005: 紧急释放后 key_log.txt 不再新增按键事件
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-KEY-005: 紧急释放后 key_log.txt 不再新增按键事件
- **建议:** 检查 AHK 执行器按键发送逻辑与测试断言

## ISSUE-E2E-MODE-001 [HIGH] (关联用例: E2E-MODE-001)

- **复现步骤:** 执行测试用例 E2E-MODE-001: 应按 100ms 间隔周期性发送 Space 键
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-001: 应按 100ms 间隔周期性发送 Space 键
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-MODE-002 [HIGH] (关联用例: E2E-MODE-002)

- **复现步骤:** 执行测试用例 E2E-MODE-002: 应按顺序发送 1→2→3，延迟约 50ms
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-002: 应按顺序发送 1→2→3，延迟约 50ms
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-MODE-003 [HIGH] (关联用例: E2E-MODE-003)

- **复现步骤:** 执行测试用例 E2E-MODE-003: 应并行执行周期性 Space 与序列 1,2
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-003: 应并行执行周期性 Space 与序列 1,2
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-MODE-004 [HIGH] (关联用例: E2E-MODE-004)

- **复现步骤:** 执行测试用例 E2E-MODE-004: 应按住 Shift 约 500ms 后释放
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-004: 应按住 Shift 约 500ms 后释放
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-MODE-005 [HIGH] (关联用例: E2E-MODE-005)

- **复现步骤:** 执行测试用例 E2E-MODE-005: Space 按 100ms 间隔，1 按 200ms 间隔各自触发
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-005: Space 按 100ms 间隔，1 按 200ms 间隔各自触发
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-MODE-006 [HIGH] (关联用例: E2E-MODE-006)

- **复现步骤:** 执行测试用例 E2E-MODE-006: 应按顺序发送 1→2→3，延迟约 100ms
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-006: 应按顺序发送 1→2→3，延迟约 100ms
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-MODE-007 [HIGH] (关联用例: E2E-MODE-007)

- **复现步骤:** 执行测试用例 E2E-MODE-007: 应并行执行增强周期性 Space 与增强序列 1,2
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-MODE-007: 应并行执行增强周期性 Space 与增强序列 1,2
- **建议:** 检查相关模式实现与测试断言

## ISSUE-E2E-REC-001 [HIGH] (关联用例: E2E-REC-001)

- **复现步骤:** 执行测试用例 E2E-REC-001: 调用 start_recording 成功，返回 null/undefined（源码返回 ()）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-001: 调用 start_recording 成功，返回 null/undefined（源码返回 ()）
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-REC-002 [HIGH] (关联用例: E2E-REC-002)

- **复现步骤:** 执行测试用例 E2E-REC-002: 录制中调用 pause_recording，返回 seq（u64）或合理 IPC 错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-002: 录制中调用 pause_recording，返回 seq（u64）或合理 IPC 错误
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-REC-003 [HIGH] (关联用例: E2E-REC-003)

- **复现步骤:** 执行测试用例 E2E-REC-003: 暂停后调用 resume_recording，返回 seq（u64）或合理 IPC 错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-003: 暂停后调用 resume_recording，返回 seq（u64）或合理 IPC 错误
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-REC-004 [HIGH] (关联用例: E2E-REC-004)

- **复现步骤:** 执行测试用例 E2E-REC-004: 停止录制返回 RecordingResult 或合理的空按键错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-004: 停止录制返回 RecordingResult 或合理的空按键错误
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-REC-005 [HIGH] (关联用例: E2E-REC-005)

- **复现步骤:** 执行测试用例 E2E-REC-005: start → pause → resume → stop 完整流程
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-005: start → pause → resume → stop 完整流程
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-SYS-001 [HIGH] (关联用例: E2E-SYS-001)

- **复现步骤:** 执行测试用例 E2E-SYS-001: 返回执行器/看门狗状态（含 status/restartCount/backoffDurationSecs）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-001: 返回执行器/看门狗状态（含 status/restartCount/backoffDurationSecs）
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-SYS-002 [HIGH] (关联用例: E2E-SYS-002)

- **复现步骤:** 执行测试用例 E2E-SYS-002: 启动分组后调用 emergency_release，返回成功或合理 IPC 错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-002: 启动分组后调用 emergency_release，返回成功或合理 IPC 错误
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-SYS-004 [HIGH] (关联用例: E2E-SYS-004)

- **复现步骤:** 执行测试用例 E2E-SYS-004: 切换 hold 模式状态，返回新状态（bool）并恢复原始值
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-004: 切换 hold 模式状态，返回新状态（bool）并恢复原始值
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-SYS-005 [HIGH] (关联用例: E2E-SYS-005)

- **复现步骤:** 执行测试用例 E2E-SYS-005: 调用 reset_watchdog，状态重置或返回合理前置条件错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-005: 调用 reset_watchdog，状态重置或返回合理前置条件错误
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-HK-003 [HIGH] (关联用例: E2E-HK-003)

- **复现步骤:** 执行测试用例 E2E-HK-003: 启动按键接收窗口，注册热键并模拟按下，key_log.txt 捕获到按键事件
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-HK-003: 启动按键接收窗口，注册热键并模拟按下，key_log.txt 捕获到按键事件
- **建议:** 检查相关 Tauri 命令实现与测试断言

## ISSUE-应用启动后 watchdog 状态应为 Running/Starting/Idle [HIGH] (关联用例: 应用启动后 watchdog 状态应为 Running/Starting/Idle)

- **复现步骤:** 执行测试用例 应用启动后 watchdog 状态应为 Running/Starting/Idle
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 应用启动后 watchdog 状态应为 Running/Starting/Idle
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-等待 5 秒后 watchdog 仍为 Running（心跳正常） [HIGH] (关联用例: 等待 5 秒后 watchdog 仍为 Running（心跳正常）)

- **复现步骤:** 执行测试用例 等待 5 秒后 watchdog 仍为 Running（心跳正常）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: 等待 5 秒后 watchdog 仍为 Running（心跳正常）
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-IPC-004-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-004)

- **复现步骤:** 激活分组后等待 3s，前端未收到 hotkey_event 事件
- **预期:** 按下 F1 后前端应收到 hotkey_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，hotkey_event 未触发
- **影响:** 热键事件转发链路无法完整验证
- **建议:** 在手动测试环境按下 F1 验证，或使用 key_receiver 辅助验证

## ISSUE-E2E-IPC-006-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-006)

- **复现步骤:** 开始录制后等待 2s，前端未收到 key_record_event 事件
- **预期:** 录制时按下按键前端应收到 key_record_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，key_record_event 未触发
- **影响:** key_record_event 转发链路无法完整验证
- **建议:** 在手动测试环境按下按键验证

## ISSUE-kill AHK 子进程后 watchdog 检测并重试（restart_count 增加） [HIGH] (关联用例: kill AHK 子进程后 watchdog 检测并重试（restart_count 增加）)

- **复现步骤:** 执行测试用例 kill AHK 子进程后 watchdog 检测并重试（restart_count 增加）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: kill AHK 子进程后 watchdog 检测并重试（restart_count 增加）
- **建议:** 检查 IPC 通信链路、watchdog 状态机与 AHK 子进程，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-KEY-001-IPC [HIGH] (关联用例: E2E-KEY-001)

- **复现步骤:** 启动分组并等待按键执行（periodic Space）
- **预期:** key_log.txt 应包含 periodic Space 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-001 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-002-IPC [HIGH] (关联用例: E2E-KEY-002)

- **复现步骤:** 启动分组并等待按键执行（periodic Space 间隔）
- **预期:** key_log.txt 应包含 periodic Space 间隔 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-002 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-003-IPC [HIGH] (关联用例: E2E-KEY-003)

- **复现步骤:** 启动分组并等待按键执行（sequence 1,2,3）
- **预期:** key_log.txt 应包含 sequence 1,2,3 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-003 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-004-IPC [HIGH] (关联用例: E2E-KEY-004)

- **复现步骤:** 启动分组并等待按键执行（hold Shift down）
- **预期:** key_log.txt 应包含 hold Shift down 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-004 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-KEY-005-IPC [HIGH] (关联用例: E2E-KEY-005)

- **复现步骤:** 启动分组并等待按键执行（periodic Space 紧急释放前）
- **预期:** key_log.txt 应包含 periodic Space 紧急释放前 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦
- **影响:** E2E-KEY-005 测试无法验证
- **建议:** 检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点

## ISSUE-E2E-MODE-001-IPC [HIGH] (关联用例: E2E-MODE-001)

- **复现步骤:** 启动分组并等待按键执行（periodic Space）
- **预期:** key_log.txt 应包含 periodic Space 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-001 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-002-IPC [HIGH] (关联用例: E2E-MODE-002)

- **复现步骤:** 启动分组并等待按键执行（sequence 1,2,3）
- **预期:** key_log.txt 应包含 sequence 1,2,3 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-002 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-003-IPC [HIGH] (关联用例: E2E-MODE-003)

- **复现步骤:** 启动分组并等待按键执行（hybrid Space+1,2）
- **预期:** key_log.txt 应包含 hybrid Space+1,2 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-003 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-004-IPC [HIGH] (关联用例: E2E-MODE-004)

- **复现步骤:** 启动分组并等待按键执行（hold Shift）
- **预期:** key_log.txt 应包含 hold Shift 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-004 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-005-IPC [HIGH] (关联用例: E2E-MODE-005)

- **复现步骤:** 启动分组并等待按键执行（enhanced_periodic Space,1）
- **预期:** key_log.txt 应包含 enhanced_periodic Space,1 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-005 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-006-IPC [HIGH] (关联用例: E2E-MODE-006)

- **复现步骤:** 启动分组并等待按键执行（enhanced_sequence 1,2,3）
- **预期:** key_log.txt 应包含 enhanced_sequence 1,2,3 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-006 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-MODE-007-IPC [HIGH] (关联用例: E2E-MODE-007)

- **复现步骤:** 启动分组并等待按键执行（enhanced_hybrid Space+1,2）
- **预期:** key_log.txt 应包含 enhanced_hybrid Space+1,2 按键事件
- **实际:** 未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败
- **影响:** E2E-MODE-007 测试无法验证
- **建议:** 检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑

## ISSUE-E2E-REC-004 [HIGH] (关联用例: E2E-REC-004)

- **复现步骤:** 执行测试用例 E2E-REC-004: 停止录制返回 RecordingResult 或合理的空按键错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-004: 停止录制返回 RecordingResult 或合理的空按键错误
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-REC-005 [HIGH] (关联用例: E2E-REC-005)

- **复现步骤:** 执行测试用例 E2E-REC-005: start → pause → resume → stop 完整流程
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-REC-005: start → pause → resume → stop 完整流程
- **建议:** 检查录制状态机实现与 IPC 通信，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-SYS-001 [HIGH] (关联用例: E2E-SYS-001)

- **复现步骤:** 执行测试用例 E2E-SYS-001: 返回执行器/看门狗状态（含 status/restartCount/backoffDurationSecs）
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-001: 返回执行器/看门狗状态（含 status/restartCount/backoffDurationSecs）
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-SYS-005 [HIGH] (关联用例: E2E-SYS-005)

- **复现步骤:** 执行测试用例 E2E-SYS-005: 调用 reset_watchdog，状态重置或返回合理前置条件错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-005: 调用 reset_watchdog，状态重置或返回合理前置条件错误
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-IPC-004-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-004)

- **复现步骤:** 激活分组后等待 3s，前端未收到 hotkey_event 事件
- **预期:** 按下 F1 后前端应收到 hotkey_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，hotkey_event 未触发
- **影响:** 热键事件转发链路无法完整验证
- **建议:** 在手动测试环境按下 F1 验证，或使用 key_receiver 辅助验证

## ISSUE-E2E-IPC-006-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-006)

- **复现步骤:** 开始录制后等待 2s，前端未收到 key_record_event 事件
- **预期:** 录制时按下按键前端应收到 key_record_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，key_record_event 未触发
- **影响:** key_record_event 转发链路无法完整验证
- **建议:** 在手动测试环境按下按键验证

## ISSUE-E2E-SYS-005 [HIGH] (关联用例: E2E-SYS-005)

- **复现步骤:** 执行测试用例 E2E-SYS-005: 调用 reset_watchdog，状态重置或返回合理前置条件错误
- **预期:** 测试应通过
- **实际:** 
- **影响:** E2E 测试失败: E2E-SYS-005: 调用 reset_watchdog，状态重置或返回合理前置条件错误
- **建议:** 检查相关 Tauri 命令实现与测试断言，或确认 E2E 环境是否支持 AHK 子进程

## ISSUE-E2E-IPC-004-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-004)

- **复现步骤:** 激活分组后等待 3s，前端未收到 hotkey_event 事件
- **预期:** 按下 F1 后前端应收到 hotkey_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，hotkey_event 未触发
- **影响:** 热键事件转发链路无法完整验证
- **建议:** 在手动测试环境按下 F1 验证，或使用 key_receiver 辅助验证

## ISSUE-E2E-IPC-006-NO-EVENT [MEDIUM] (关联用例: E2E-IPC-006)

- **复现步骤:** 开始录制后等待 2s，前端未收到 key_record_event 事件
- **预期:** 录制时按下按键前端应收到 key_record_event 事件
- **实际:** E2E 环境无法可靠模拟真实键盘按下，key_record_event 未触发
- **影响:** key_record_event 转发链路无法完整验证
- **建议:** 在手动测试环境按下按键验证

## ISSUE-E2E-SYS-005-RESOLVED [RESOLVED] (关联用例: E2E-SYS-005)

- **状态:** 已修复（2026-06-28）
- **原复现步骤:** 调用 reset_watchdog 时，invoke 辅助函数的 browser.execute() 轮询循环因 tauri-driver/msedgedriver 的 flaky "unknown error"（HTTP 200 with error body）而抛出异常，导致测试失败
- **根因:** tauri-driver 在执行 /execute/sync 端点时间歇性返回 HTTP 200 + error body，WebDriverIO 重试 3 次后抛出 "unknown error"，错误消息不匹配测试期望的正则表达式
- **修复方案:** 在 e2e/helpers/tauri.js 的 invoke 辅助函数轮询循环中添加 try-catch，捕获 browser.execute() 的异常后继续轮询，因为 invoke 可能已在后端成功执行，仅前端读取 window.__e2e_result 失败
- **验证:** 修复后 E2E-SYS-005 通过（耗时 18742ms，证明 try-catch 生效，"unknown error" 被捕获后继续轮询直到成功）

## ISSUE-E2E-HK-003-RESOLVED [RESOLVED] (关联用例: E2E-HK-003)

- **状态:** 已修复（2026-06-28）
- **原复现步骤:** 启动 key_receiver 窗口，注册 F8 热键，临时脚本 Send("{F8}") 模拟按下，key_log.txt 应捕获 F8 down 事件
- **根因:** 两个问题协同导致失败：
  1. 临时脚本 `Send("{F8}")` 默认 SendLevel=0，无法触发热键钩子（AHK 默认行为：Send 模拟的按键不触发热键，除非 SendLevel > hook level）
  2. key_receiver.ahk 使用 `Hotkey("IfWinActive", "ahk_id " keyGui.Hwnd)` 限定热键上下文为 GUI 窗口，但 ASD Tauri 应用抢占前台导致窗口激活失败，IfWinActive 上下文不匹配
- **修复方案:**
  1. 在 hotkey_cmd.spec.js 临时脚本中添加 `SendLevel(10)`，让 Send 发送的按键携带 level=10 标记，触发 key_receiver 默认 level=0 的热键钩子
  2. 在 key_receiver.ahk 中移除 `Hotkey("IfWinActive", "ahk_id " keyGui.Hwnd)` 上下文限制，改为全局热键，避免窗口激活问题
- **验证:** 修复后 E2E-HK-003 通过（耗时 1508ms），key_log.txt 正确捕获到 F8 down/up 事件

