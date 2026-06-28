# E2E 测试报告

## 运行环境

| 项目 | 值 |
|------|-----|
| 操作系统 | Windows 11 |
| Tauri 版本 | 2.11.2 |
| WebDriverIO | 8.x |
| tauri-driver | 0.1.x（cargo install） |
| msedgedriver | 149.0.4022.98 |
| Binary 构建方式 | `npx tauri build --debug --no-bundle` |
| Binary 路径 | `target/debug/asd-tauri.exe` |
| 运行时间 | 2026-06-28 19:36-19:37 (UTC+8) |

## 总体结果

| 指标 | 数值 |
|------|------|
| Spec 文件总数 | 10 |
| Spec 文件通过 | 3 |
| Spec 文件失败 | 7 |
| 测试用例总数 | 53 |
| 测试用例通过 | 20 |
| 测试用例失败 | 33 |
| 通过率 | 37.7% |
| 总耗时 | ~56s |

## 按 Suite 统计

| Suite | 通过 | 失败 | 跳过 | 总数 | 状态 |
|-------|------|------|------|------|------|
| smoke | 1 | 0 | 0 | 1 | ✅ 全通过 |
| config_cmd | 12 | 0 | 0 | 12 | ✅ 全通过 |
| group_cmd | 6 | 2 | 0 | 8 | ⚠️ 部分失败 |
| hotkey_cmd | 1 | 2 | 0 | 3 | ⚠️ 部分失败 |
| ipc | 2 | 5 | 0 | 7 | ⚠️ 大部分失败 |
| key_send | 0 | 5 | 0 | 5 | ❌ 全失败 |
| modes | 0 | 7 | 0 | 7 | ❌ 全失败 |
| recording_cmd | 1 | 4 | 0 | 5 | ⚠️ 大部分失败 |
| system_cmd | 2 | 3 | 0 | 5 | ⚠️ 部分失败 |

## 通过的测试用例（20 个）

### smoke.spec.js（1/1）
- ✅ E2E-SMOKE: 应用窗口能启动并关闭

### config_cmd.spec.js（12/12）
- ✅ E2E-CFG-001: get_config 返回字段完整
- ✅ E2E-CFG-002: save_config 写入一致
- ✅ E2E-CFG-003: 合法配置验证
- ✅ E2E-CFG-004: 非法配置验证
- ✅ E2E-CFG-005: list_backups 返回数组
- ✅ E2E-CFG-006: create_backup 数量+1
- ✅ E2E-CFG-007: restore_backup 恢复
- ✅ E2E-CFG-008: delete_backup 数量-1
- ✅ E2E-CFG-009: export_config 文件存在
- ✅ E2E-CFG-010: import_config 一致
- ✅ E2E-CFG-011: compare_configs 返回差异
- ✅ E2E-CFG-012: hot_reload 重新加载

### group_cmd.spec.js（6/8）
- ✅ E2E-GRP-001: get_groups 返回摘要列表
- ✅ E2E-GRP-002: get_group_detail 返回详细配置
- ✅ E2E-GRP-003: toggle_group 状态翻转
- ✅ E2E-GRP-006: delete_group 数量-1
- ✅ E2E-GRP-007: batch_delete_groups 批量删除
- ✅ E2E-GRP-008: reorder_groups 重排序

### hotkey_cmd.spec.js（1/3）
- ✅ E2E-HK-001: register_hotkey 更新热键

### ipc.spec.js（2/7）
- ✅ E2E-IPC-002: toggle_group 命令成功返回
- ✅ E2E-IPC-007: watchdog 检测子进程退出并重试

### recording_cmd.spec.js（1/5）
- ✅ E2E-REC-001: start_recording 成功

### system_cmd.spec.js（2/5）
- ✅ E2E-SYS-002: emergency_release 返回成功
- ✅ E2E-SYS-003: clear_emergency 状态清除

## 失败原因分类

### 1. AHK 子进程未运行（17 个失败）

**影响 Suite**: ipc, key_send, modes, recording_cmd

**根因**: 本次构建跳过了 `build_ahk.ps1`（PowerShell 语法错误），导致 `asd_executor.exe` 未生成。Rust 主进程启动后无法通过 named pipe 连接 AHK 子进程，所有依赖 IPC 通信的命令返回 "IPC 通信错误: 连接已关闭"。

**影响用例**:
- E2E-IPC-001, 003, 004, 005, 006（5 个）
- E2E-KEY-001 ~ 005（5 个）
- E2E-MODE-001 ~ 007（7 个）

**修复方案**: 修复 `build_ahk.ps1` PowerShell 语法问题，或改用 portable 模式（复制 AutoHotkey64.exe）。

### 2. 字段命名不一致（1 个失败）

**影响用例**: E2E-SYS-001

**根因**: `get_executor_status` 返回的字段为 `restart_count`（snake_case），但测试断言期望 `restartCount`（camelCase）。

**实际返回**: `{"backoffDurationSecs":1,"restart_count":0,"status":"Running"}`
**期望**: `restartCount` 字段

**修复方案**: 修改 `system_cmd.spec.js` 中 E2E-SYS-001 的断言，使用 `restart_count` 字段名；或在 Tauri command 中统一为 camelCase 序列化。

### 3. 错误消息模式不匹配（15 个失败）

**影响 Suite**: group_cmd, hotkey_cmd, ipc, recording_cmd, system_cmd

**根因**: 当 IPC 失败时，Tauri invoke 返回的错误消息为 `"unknown error"`，但测试用例使用正则匹配期望特定模式（如 `/IPC|ipc|超时|timeout|连接/`）。`"unknown error"` 不匹配任何预期模式，导致断言失败。

**影响用例**:
- E2E-GRP-004, 005（2 个）
- E2E-HK-002, 003（2 个）
- E2E-REC-002, 003, 004, 005（4 个）
- E2E-SYS-004, 005（2 个）
- 其他 IPC 相关（5 个）

**修复方案**: 
1. 在 `helpers/tauri.js` 的 invoke 函数中改进错误消息提取，捕获完整的错误对象
2. 或修改测试断言放宽匹配模式，接受 `"unknown error"` 作为 IPC 失败的合理错误

## 环境搭建验证

| 检查项 | 状态 | 说明 |
|--------|------|------|
| msedgedriver 安装 | ✅ | 版本 149.0.4022.98，位于 `e2e/drivers/` |
| tauri-driver 安装 | ✅ | 通过 `cargo install tauri-driver` |
| tauri-driver --native-driver | ✅ | 显式指定 msedgedriver.exe 路径 |
| Binary 构建 | ✅ | `npx tauri build --debug --no-bundle` 嵌入前端 |
| 前端加载 | ✅ | 页面标题 "技能管理器 v3.0" |
| window.__TAURI__ | ✅ | withGlobalTauri: true 已启用 |
| WebDriver executeScript | ✅ | 同步执行正常 |
| Tauri invoke 调用 | ✅ | config_cmd 全部 12 个通过 |

## 结论

E2E 测试基础设施已完整搭建并验证可用：
1. **msedgedriver 已安装并正常工作**
2. **tauri-driver 成功驱动 Tauri 应用窗口**
3. **前端正确加载，Tauri invoke 调用链路畅通**
4. **20/53 测试用例通过**，验证了 config_cmd、group_cmd（部分）、system_cmd（部分）等核心功能

主要失败原因为 AHK 子进程未构建（可修复）和测试断言模式匹配问题（可调整）。
