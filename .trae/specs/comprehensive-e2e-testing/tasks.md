# Tasks

- [x] Task 1: 搭建 E2E 测试基础设施
  - [x] SubTask 1.1: 在 `asd-tauri/e2e/` 下创建 `package.json`，声明 WebDriverIO、tauri-driver、@wdio/mocha-framework、@wdio/spec-reporter 等依赖
  - [x] SubTask 1.2: 创建 `wdio.conf.js`，配置 tauri-driver 作为 WebDriver 后端（capabilities 包含 `tauri:options`），指定 specs 路径、 reporters、timeout
  - [x] SubTask 1.3: 创建 `helpers/tauri.js`，封装 tauri-driver 启停、应用启停、`invoke(command, args)` 辅助函数
  - [x] SubTask 1.4: 创建 `helpers/report.js`，封装测试结果收集与 Markdown 报告生成
  - [x] SubTask 1.5: 运行 `npm install` 验证依赖可装、`npx wdio --version` 验证可执行
  - [x] SubTask 1.6: 编写冒烟测试 `specs/smoke.spec.js`（启动应用、关闭应用），验证基础设施可用

- [x] Task 2: 准备测试辅助工具
  - [x] SubTask 2.1: 创建 `fixtures/key_receiver.ahk`，启动一个 AHK GUI 窗口，使用 `OnMessage` 或 `Hotkey` 捕获按键事件，写入 `reports/key_log.txt`（格式：`<timestamp>|<key>|<event>`）
  - [x] SubTask 2.2: 创建 `fixtures/test_config.json`，提供测试专用配置（包含 7 种模式的示例分组）
  - [x] SubTask 2.3: 创建 `helpers/key_receiver.js`，封装接收窗口启停、key_log.txt 读取与解析、按键序列断言辅助函数
  - [x] SubTask 2.4: 创建 `helpers/config.js`，封装测试前备份用户配置、写入测试配置、测试后恢复用户配置的逻辑
  - [x] SubTask 2.5: 验证 key_receiver.ahk 能启动并捕获按键（手动启动 + 手动按键 + 检查 key_log.txt）

- [x] Task 3: 实现 config_cmd E2E 测试（9 个命令）
  - [x] SubTask 3.1: 创建 `specs/config_cmd.spec.js`
  - [x] SubTask 3.2: 测试 `get_config`：调用返回当前配置，字段完整
  - [x] SubTask 3.3: 测试 `save_config`：写入测试配置后 `get_config` 返回一致
  - [x] SubTask 3.4: 测试 `validate_config`：合法配置返回 ok；非法配置（如空 hotkey）返回明确错误
  - [x] SubTask 3.5: 测试 `list_backups`：返回备份列表数组
  - [x] SubTask 3.6: 测试 `create_backup`：创建备份后 `list_backups` 数量 +1
  - [x] SubTask 3.7: 测试 `restore_backup`：先 `save_config` 修改配置，再 `restore_backup` 恢复到之前备份，配置回到原值
  - [x] SubTask 3.8: 测试 `delete_backup`：删除备份后 `list_backups` 数量 -1
  - [x] SubTask 3.9: 测试 `export_config`：导出后文件存在且可被 `import_config` 导入
  - [x] SubTask 3.10: 测试 `import_config`：导入后 `get_config` 返回导入的配置
  - [x] SubTask 3.11: 测试 `compare_configs`：比较两个不同配置返回差异列表
  - [x] SubTask 3.12: 测试 `hot_reload`：从磁盘重新加载配置，返回最新配置

- [x] Task 4: 实现 group_cmd E2E 测试（7 个命令）
  - [x] SubTask 4.1: 创建 `specs/group_cmd.spec.js`
  - [x] SubTask 4.2: 测试 `get_groups`：返回分组摘要列表
  - [x] SubTask 4.3: 测试 `get_group_detail`：返回指定分组的详细配置
  - [x] SubTask 4.4: 测试 `toggle_group`：切换分组状态，`get_group_detail` 返回的 enabled 字段翻转
  - [x] SubTask 4.5: 测试 `toggle_all`：切换所有分组状态
  - [x] SubTask 4.6: 测试 `batch_toggle_groups`：批量切换指定 ID 列表的分组
  - [x] SubTask 4.7: 测试 `delete_group`：删除分组后 `get_groups` 数量 -1
  - [x] SubTask 4.8: 测试 `batch_delete_groups`：批量删除指定 ID 列表的分组
  - [x] SubTask 4.9: 测试 `reorder_groups`：重排序后 `get_groups` 返回的顺序符合新顺序

- [x] Task 5: 实现 hotkey_cmd E2E 测试（2 个命令）
  - [x] SubTask 5.1: 创建 `specs/hotkey_cmd.spec.js`
  - [x] SubTask 5.2: 测试 `register_hotkey`：注册热键后 `get_executor_status` 返回的 registered_hotkeys 包含该热键
  - [x] SubTask 5.3: 测试 `unregister_hotkey`：注销后 `get_executor_status` 返回的 registered_hotkeys 不再包含该热键
  - [x] SubTask 5.4: 测试热键实际触发：注册热键后通过 key_receiver.ahk 验证热键按下能触发分组执行

- [x] Task 6: 实现 recording_cmd E2E 测试（4 个命令）
  - [x] SubTask 6.1: 创建 `specs/recording_cmd.spec.js`
  - [x] SubTask 6.2: 测试 `start_recording`：调用成功，返回录制 session ID
  - [x] SubTask 6.3: 测试 `pause_recording`：录制中调用，状态变为 paused
  - [x] SubTask 6.4: 测试 `resume_recording`：暂停后调用，状态变为 recording
  - [x] SubTask 6.5: 测试 `stop_recording`：停止录制后返回录制的按键序列
  - [x] SubTask 6.6: 测试录制状态机：start → pause → resume → stop，状态转换正确

- [x] Task 7: 实现 system_cmd E2E 测试（5 个命令）
  - [x] SubTask 7.1: 创建 `specs/system_cmd.spec.js`
  - [x] SubTask 7.2: 测试 `get_executor_status`：返回执行器状态、watchdog 状态、已注册热键列表
  - [x] SubTask 7.3: 测试 `emergency_release`：启动分组后调用，所有分组停止
  - [x] SubTask 7.4: 测试 `clear_emergency`：紧急释放后调用，状态清除
  - [x] SubTask 7.5: 测试 `toggle_hold_mode`：切换 hold 模式状态
  - [x] SubTask 7.6: 测试 `reset_watchdog`：调用后 watchdog 状态重置

- [x] Task 8: 实现 7 种执行模式 E2E 测试
  - [x] SubTask 8.1: 创建 `specs/modes.spec.js`
  - [x] SubTask 8.2: 测试 `periodic` 模式：pressKeys=["Space"]，interval=100ms，运行 1s，验证 key_log.txt 包含约 10 次 Space 事件，间隔 100ms ± 20ms
  - [x] SubTask 8.3: 测试 `sequence` 模式：pressKeys=["1","2","3"]，delays=[50,50,50]，运行 1 次，验证按键顺序与延迟
  - [x] SubTask 8.4: 测试 `hybrid` 模式：groups 数组含 1 个周期性 + 1 个序列，验证两组按键并行出现
  - [x] SubTask 8.5: 测试 `hold` 模式：holdKeys=["Shift"]，holdDuration=500ms，验证按键持续按住 500ms 后释放
  - [x] SubTask 8.6: 测试 `enhanced_periodic` 模式：pressKeys=["Space","1"]，intervals=[100,200]，验证两个键按各自间隔触发
  - [x] SubTask 8.7: 测试 `enhanced_sequence` 模式：pressKeys=["1","2","3"]，pressDelays=[100,100,100]，验证增强序列
  - [x] SubTask 8.8: 测试 `enhanced_hybrid` 模式：groups 数组含多个增强模式分组，验证并行执行

- [x] Task 9: 实现 Rust↔AHK IPC 通信 E2E 测试
  - [x] SubTask 9.1: 创建 `specs/ipc.spec.js`
  - [x] SubTask 9.2: 测试 AHK 子进程启动：应用启动后通过 `get_executor_status` 确认 watchdog 状态为 Running
  - [x] SubTask 9.3: 测试命令下发：`toggle_group` 启动分组，Rust 日志显示 `send_command` 成功，AHK 日志显示命令接收
  - [x] SubTask 9.4: 测试心跳：监听 Rust 日志，确认收到 AHK 心跳消息
  - [x] SubTask 9.5: 测试热键事件转发：注册热键并按下，前端通过 Tauri event 收到 `hotkey_event`
  - [x] SubTask 9.6: 测试 key_send_event 转发：分组执行时前端收到 `key_send_event`
  - [x] SubTask 9.7: 测试 key_record_event 转发：录制时前端收到 `key_record_event`
  - [x] SubTask 9.8: 测试 watchdog 重启：强制 kill AHK 子进程，watchdog 检测并重试；超过 MaxRetries 后状态变为 MaxRetriesExceeded

- [x] Task 10: 实现 AHK 执行器按键验证 E2E 测试
  - [x] SubTask 10.1: 创建 `specs/key_send.spec.js`
  - [x] SubTask 10.2: 测试按键实际发送：启动 periodic 分组，key_receiver.ahk 捕获到按键事件
  - [x] SubTask 10.3: 测试按键间隔精度：周期性按键的实际间隔与配置间隔的误差在 ±20ms 内
  - [x] SubTask 10.4: 测试按键顺序：sequence 模式的按键顺序与配置一致
  - [x] SubTask 10.5: 测试 hold 模式按键：holdDuration 期间按键持续按住，结束时释放
  - [x] SubTask 10.6: 测试 emergency_release 后无按键：紧急释放后 key_log.txt 不再新增按键事件

- [x] Task 11: 生成测试报告与产物
  - [x] SubTask 11.1: 在 wdio.conf.js 中配置自定义 reporter 或 `onComplete` 钩子，收集所有测试结果
  - [x] SubTask 11.2: 生成 `docs/e2e-test-report.md`，包含测试概览、按 suite 分组的详细结果、失败用例的日志路径
  - [x] SubTask 11.3: 生成 `docs/e2e-test-checklist.md`，列出所有测试用例（E2E-CFG-001 等编号），含步骤、预期、实际结果、状态字段
  - [x] SubTask 11.4: 整理 `docs/e2e-known-issues.md`，记录测试中发现的问题，含严重程度、复现步骤、修复建议
  - [x] SubTask 11.5: 在 `asd-tauri/docs/test-map.md` 新增「E2E 测试」章节，登记所有 E2E 测试资产

- [x] Task 12: 更新 AGENTS.md 与文档
  - [x] SubTask 12.1: 在 AGENTS.md 的 "Testing Requirements" 章节新增「E2E 测试」小节
  - [x] SubTask 12.2: 说明 E2E 测试位置、运行命令、前置条件（tauri-driver + AHK v2）
  - [x] SubTask 12.3: 在 .gitignore 中确保 `asd-tauri/e2e/node_modules/` 与 `asd-tauri/e2e/reports/` 被忽略

- [x] Task 13: 完整运行与验证
  - [x] SubTask 13.1: 运行完整 E2E 测试套件 `cd asd-tauri/e2e && npm test`
  - [x] SubTask 13.2: 验证所有测试用例执行（无 skip）
  - [x] SubTask 13.3: 收集失败用例，分析原因，更新 `docs/e2e-known-issues.md`
  - [x] SubTask 13.4: 二次运行验证修复后的用例
  - [x] SubTask 13.5: 生成最终测试报告并提交所有变更（conventional commit 格式）

# Task Dependencies

- [Task 1] 必须最先执行（提供基础设施）
- [Task 2] 依赖 [Task 1] 完成（提供辅助工具）
- [Task 3, 4, 5, 6, 7] 依赖 [Task 2] 完成，可并行（19 个命令分 5 个 suite）
- [Task 8] 依赖 [Task 2] 完成（需要 key_receiver.ahk）
- [Task 9] 依赖 [Task 2] 完成（需要应用启动辅助）
- [Task 10] 依赖 [Task 2, 8] 完成（需要按键验证基础设施与模式配置）
- [Task 11] 依赖 [Task 3-10] 完成（需要所有测试结果）
- [Task 12] 可与 [Task 3-10] 并行
- [Task 13] 依赖 [Task 11, 12] 完成
