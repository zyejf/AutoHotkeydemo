# Commands 层逻辑下沉 + Service 层测试设计

## 背景

Commands 层（5 个文件，29 个 Tauri 命令）当前覆盖率 0-5%，核心挑战是 `tauri::State<'_, Arc<AppState>>` 无法在 Tauri 运行时外构造。

## 方案：逻辑下沉到 Service 模块

将 commands 中的业务逻辑提取为 `asd-application` 中的 Service 模块函数，commands 变为一行委托调用。

### 架构变更

```
当前: Tauri Command → [业务逻辑 + I/O + IPC] → 返回结果
目标: Tauri Command → service::function(&state) → 返回结果
```

### 3 个 Service 模块

| 模块 | 文件 | 方法数 | 职责 |
|------|------|--------|------|
| `backup_service` | `crates/asd-application/src/backup_service.rs` | 8 | 备份 CRUD + 配置导入导出 + 热重载 |
| `group_service` | `crates/asd-application/src/group_service.rs` | 8 | 分组生命周期 + 热键注册 + IPC 命令构造 |
| `recording_service` | `crates/asd-application/src/recording_service.rs` | 8 | 录制控制 + 验证 + 文件导入导出 |

### 保留在 AppState 的操作

- `emergency_release()` — 仅 set atomic + send IPC
- `toggle_hold_mode()` — 同上

### 保留在 commands 层的操作（一行委托）

- `get_config` → `state.read_config()`
- `validate_config` → `ConfigValidator::validate()`
- `get_groups` → `state.read_groups()` + map
- `get_group_detail` → `state.get_group()`
- `get_executor_status` → 读 watchdog_state

## BackupService 详细设计

```rust
pub struct BackupInfo { filename: String, timestamp: String, size: u64 }
pub struct ConfigDiff { added_groups: Vec<String>, removed_groups: Vec<String>, modified_groups: Vec<String> }

pub fn list_backups(state: &AppState) -> Result<Vec<BackupInfo>, AppError>
pub fn create_backup(state: &AppState) -> Result<String, AppError>
pub fn restore_backup(state: &AppState, filename: &str) -> Result<(), AppError>
pub fn delete_backup(state: &AppState, filename: &str) -> Result<(), AppError>
pub fn compare_configs(state: &AppState, backup_filename: &str) -> Result<ConfigDiff, AppError>
pub fn hot_reload(state: &AppState) -> Result<Config, AppError>
pub fn export_config(state: &AppState, path: &str) -> Result<(), AppError>
pub fn import_config(state: &AppState, path: &str) -> Result<(), AppError>
```

关键决策：
- 路径遍历防护提取为内部函数 `validate_path_in_backup_dir()`
- 文件 I/O 通过 `ConfigRepository`（原子写入）
- `chrono::Local::now()` 用于时间戳

## GroupService 详细设计

```rust
pub struct GroupSummary { id: String, name: String, hotkey: String, mode: String, active: bool }
pub struct GroupStatus { id: String, active: bool }

pub fn toggle_group(state: &AppState, group_id: &str) -> Result<GroupStatus, AppError>
pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError>
pub fn toggle_all(state: &AppState, active: bool) -> Result<(), AppError>
pub fn batch_toggle_groups(state: &AppState, group_ids: &[String], active: bool) -> Result<(), AppError>
pub fn batch_delete_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError>
pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError>
pub fn register_hotkey(state: &AppState, hotkey: &str, group_id: &str) -> Result<(), AppError>
pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError>
```

关键决策：
- IPC 命令构造封装在服务内部
- `active_hotkeys` 通过 `state.active_hotkeys`（pub 字段）访问
- 批量操作用 `try_send_ipc_command`，单个操作用 `send_ipc_command`

## RecordingService 详细设计

```rust
pub struct RecordingResult { seq: u64, keys: Vec<String>, mode: String, intervals: Vec<u64>, delays: Vec<u64> }
pub struct ImportedRecording { keys: Vec<String>, intervals: Vec<u64>, mode: String }

pub fn start_recording(state: &AppState, group_id: &str, mode: &str) -> Result<(), AppError>
pub fn stop_recording(state: &AppState) -> Result<RecordingResult, AppError>
pub fn pause_recording(state: &AppState) -> Result<u64, AppError>
pub fn resume_recording(state: &AppState) -> Result<u64, AppError>
pub fn export_recording(path: &str, keys: &[String], intervals: &[u64], mode: &str) -> Result<(), AppError>
pub fn import_recording(path: &str) -> Result<ImportedRecording, AppError>
pub fn start_validation(state: &AppState, group_id: &str) -> Result<u64, AppError>
pub fn stop_validation(state: &AppState) -> Result<u64, AppError>
```

关键决策：
- `export_recording` 和 `import_recording` 不需要 `&AppState`
- `stop_recording` 使用 `send_ipc_and_wait` 等待 AHK 响应

## Commands 层变更示例

```rust
// 之前: 30 行逻辑
#[tauri::command]
pub async fn create_backup(state: tauri::State<'_, Arc<AppState>>) -> Result<String, AppError> {
    let config_path = state.get_config_path().ok_or_else(|| ...)?;
    // ... 30 行 ...
}

// 之后: 一行委托
#[tauri::command]
pub async fn create_backup(state: tauri::State<'_, Arc<AppState>>) -> Result<String, AppError> {
    backup_service::create_backup(&state)
}
```

## 测试策略

### Mock 基础设施

复用 AppState 现有 Mock（MockIpcSender, MockEventEmitter, MockProcessWatcher），新增：
- `RecordingMockIpcSender` — 记录所有发送的 IpcCommand
- `RecordingMockEventEmitter` — 记录所有发出的事件

### 测试分类

| 类别 | 测试数 | 示例 |
|------|--------|------|
| BackupService 正常路径 | 8 | 创建备份、列出备份、恢复备份 |
| BackupService 错误路径 | 6 | 路径遍历攻击、不存在的备份、无配置路径 |
| GroupService 正常路径 | 8 | 切换分组、删除分组、批量操作 |
| GroupService 错误路径 | 4 | 分组不存在、热键重复注册 |
| RecordingService 正常路径 | 6 | 开始/停止录制、导入导出 |
| RecordingService 错误路径 | 3 | 录制时分组不存在、导入格式错误 |
| **总计** | **~35** | |

### 测试文件位置

- `crates/asd-application/tests/backup_service_tests.rs`
- `crates/asd-application/tests/group_service_tests.rs`
- `crates/asd-application/tests/recording_service_tests.rs`

## DTO 迁移

| DTO | 原位置 | 迁移至 |
|-----|--------|--------|
| BackupInfo | config_cmd.rs | backup_service.rs |
| ConfigDiff | config_cmd.rs | backup_service.rs |
| GroupSummary | group_cmd.rs | group_service.rs |
| GroupStatus | group_cmd.rs | group_service.rs |
| RecordingResult | recording_cmd.rs | recording_service.rs |
| ImportedRecording | recording_cmd.rs | recording_service.rs |

## 文件变更清单

### 新增文件
- `crates/asd-application/src/backup_service.rs`
- `crates/asd-application/src/group_service.rs`
- `crates/asd-application/src/recording_service.rs`
- `crates/asd-application/tests/backup_service_tests.rs`
- `crates/asd-application/tests/group_service_tests.rs`
- `crates/asd-application/tests/recording_service_tests.rs`

### 修改文件
- `crates/asd-application/src/lib.rs` — 添加 3 个模块声明
- `crates/asd-application/Cargo.toml` — 添加 chrono 依赖
- `src-tauri/src/commands/config_cmd.rs` — 删除逻辑，委托 backup_service
- `src-tauri/src/commands/group_cmd.rs` — 删除逻辑，委托 group_service
- `src-tauri/src/commands/hotkey_cmd.rs` — 删除逻辑，委托 group_service
- `src-tauri/src/commands/recording_cmd.rs` — 删除逻辑，委托 recording_service
- `src-tauri/src/commands/system_cmd.rs` — 保持不变（逻辑在 AppState）
- `src-tauri/src/lib.rs` — 更新 use 路径
