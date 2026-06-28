# Checklist

## E2E 测试基础设施

- [x] `asd-tauri/e2e/package.json` 已创建，声明 WebDriverIO、tauri-driver、@wdio/mocha-framework 等依赖
- [x] `asd-tauri/e2e/wdio.conf.js` 已创建，配置 tauri-driver 后端、specs 路径、reporters
- [x] `asd-tauri/e2e/helpers/tauri.js` 已创建，封装 tauri-driver 启停与应用 invoke 辅助
- [x] `asd-tauri/e2e/helpers/report.js` 已创建，封装 Markdown 报告生成
- [x] `npm install` 在 `asd-tauri/e2e/` 下执行成功
- [x] `npx wdio --version` 可正常输出
- [ ] 冒烟测试 `specs/smoke.spec.js` 能启动并关闭应用（已运行但失败：msedgedriver.exe 缺失）

## 测试辅助工具

- [x] `fixtures/key_receiver.ahk` 已创建，能启动 GUI 窗口捕获按键并写入 `reports/key_log.txt`
- [x] `fixtures/test_config.json` 已创建，包含 7 种模式的示例分组
- [x] `helpers/key_receiver.js` 已创建，封装接收窗口启停与 key_log.txt 解析
- [x] `helpers/config.js` 已创建，封装用户配置备份/恢复逻辑
- [x] 手动验证 key_receiver.ahk 能正确捕获按键事件

## config_cmd E2E 测试（9 个命令）

- [ ] `get_config` 测试通过
- [ ] `save_config` 测试通过
- [ ] `validate_config` 合法配置测试通过
- [ ] `validate_config` 非法配置测试通过（返回明确错误）
- [ ] `list_backups` 测试通过
- [ ] `create_backup` 测试通过（备份数量 +1）
- [ ] `restore_backup` 测试通过（配置恢复到备份值）
- [ ] `delete_backup` 测试通过（备份数量 -1）
- [ ] `export_config` 测试通过
- [ ] `import_config` 测试通过
- [ ] `compare_configs` 测试通过
- [ ] `hot_reload` 测试通过
- [ ] `save_config → create_backup → restore_backup` 端到端链路测试通过

## group_cmd E2E 测试（7 个命令）

- [ ] `get_groups` 测试通过
- [ ] `get_group_detail` 测试通过
- [ ] `toggle_group` 测试通过（enabled 字段翻转）
- [ ] `toggle_all` 测试通过
- [ ] `batch_toggle_groups` 测试通过
- [ ] `delete_group` 测试通过（分组数量 -1）
- [ ] `batch_delete_groups` 测试通过
- [ ] `reorder_groups` 测试通过

## hotkey_cmd E2E 测试（2 个命令）

- [ ] `register_hotkey` 测试通过
- [ ] `unregister_hotkey` 测试通过
- [ ] 热键实际触发测试通过（key_receiver.ahk 验证）

## recording_cmd E2E 测试（4 个命令）

- [ ] `start_recording` 测试通过
- [ ] `pause_recording` 测试通过
- [ ] `resume_recording` 测试通过
- [ ] `stop_recording` 测试通过
- [ ] 录制状态机完整转换测试通过

## system_cmd E2E 测试（5 个命令）

- [ ] `get_executor_status` 测试通过
- [ ] `emergency_release` 测试通过
- [ ] `clear_emergency` 测试通过
- [ ] `toggle_hold_mode` 测试通过
- [ ] `reset_watchdog` 测试通过

## 7 种执行模式 E2E 测试

- [ ] `periodic` 模式测试通过（间隔 100ms ± 20ms 容差）
- [ ] `sequence` 模式测试通过（按键顺序与延迟正确）
- [ ] `hybrid` 模式测试通过（多分组并行）
- [ ] `hold` 模式测试通过（holdDuration 与 holdMode 正确）
- [ ] `enhanced_periodic` 模式测试通过
- [ ] `enhanced_sequence` 模式测试通过
- [ ] `enhanced_hybrid` 模式测试通过

## Rust↔AHK IPC 通信 E2E 测试

- [ ] AHK 子进程启动测试通过（watchdog 状态为 Running）
- [ ] 命令下发测试通过（Rust 日志显示 send_command 成功）
- [ ] 心跳接收测试通过（Rust 日志显示收到 heartbeat）
- [ ] 热键事件转发测试通过（前端收到 `hotkey_event`）
- [ ] `key_send_event` 转发测试通过
- [ ] `key_record_event` 转发测试通过
- [ ] watchdog 重启测试通过（kill 后重试，超过 MaxRetries 进入 MaxRetriesExceeded）

## AHK 执行器按键验证 E2E 测试

- [ ] 按键实际发送测试通过（key_log.txt 包含按键事件）
- [ ] 按键间隔精度测试通过（误差 ±20ms 内）
- [ ] 按键顺序测试通过
- [ ] hold 模式按键测试通过
- [ ] emergency_release 后无按键测试通过

## 测试报告与产物

- [x] `docs/e2e-test-report.md` 已生成，包含测试概览、按 suite 分组详细结果
- [x] `docs/e2e-test-checklist.md` 已生成，包含所有测试用例编号与字段
- [x] `docs/e2e-known-issues.md` 已生成，包含发现的问题与修复建议
- [x] `asd-tauri/docs/test-map.md` 新增「E2E 测试」章节并登记资产

## AGENTS.md 与 .gitignore 更新

- [x] AGENTS.md "Testing Requirements" 章节新增「E2E 测试」小节
- [x] .gitignore 包含 `asd-tauri/e2e/node_modules/` 与 `asd-tauri/e2e/reports/`

## 最终验证

- [ ] 完整 E2E 测试套件 `cd asd-tauri/e2e && npm test` 运行成功（未运行：tauri-driver 未安装）
- [ ] 所有测试用例执行（无 skip）（未运行：tauri-driver 未安装）
- [x] 失败用例已分析并记录到 `docs/e2e-known-issues.md`
- [ ] 所有变更已提交（conventional commit 格式）（由后续步骤处理）
