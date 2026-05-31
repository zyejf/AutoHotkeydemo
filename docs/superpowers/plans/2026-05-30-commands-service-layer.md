# Commands Service Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract commands layer business logic into 3 testable service modules in asd-application crate, achieving ~35 new tests and >80% commands coverage.

**Architecture:** Move logic from Tauri command functions into free functions in `asd-application` service modules. Each service function takes `&AppState` and uses its public API. Commands become one-line delegates. DTOs migrate from command files to service modules.

**Tech Stack:** Rust, asd-application crate, existing Mock infrastructure (MockIpcSender, MockEventEmitter, MockProcessWatcher)

---

## Phase 1: BackupService

### Task 1: Create BackupService module with DTOs

**Files:**
- Create: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\backup_service.rs`
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\lib.rs`
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\Cargo.toml`

- [ ] **Step 1: Add chrono dependency to asd-application Cargo.toml**

In `crates/asd-application/Cargo.toml`, add to `[dependencies]`:
```toml
chrono = "0.4"
```

- [ ] **Step 2: Add module declaration to lib.rs**

In `crates/asd-application/src/lib.rs`, add:
```rust
pub mod backup_service;
```

- [ ] **Step 3: Create backup_service.rs with DTOs and function stubs**

Create `crates/asd-application/src/backup_service.rs`:
```rust
use crate::error::AppError;
use crate::state::AppState;
use asd_application::config_repository::ConfigRepository;
use asd_domain::config::Config;
use std::path::Path;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BackupInfo {
    pub filename: String,
    pub timestamp: String,
    pub size: u64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConfigDiff {
    #[serde(rename = "addedGroups")]
    pub added_groups: Vec<String>,
    #[serde(rename = "removedGroups")]
    pub removed_groups: Vec<String>,
    #[serde(rename = "modifiedGroups")]
    pub modified_groups: Vec<String>,
}

fn validate_path_in_backup_dir(backup_path: &Path, backup_dir: &Path) -> Result<(), AppError> {
    let canonical_backup = backup_path
        .canonicalize()
        .map_err(|e| AppError::Config(format!("路径解析失败: {e}")))?;
    let canonical_dir = backup_dir
        .canonicalize()
        .map_err(|e| AppError::Config(format!("目录解析失败: {e}")))?;
    if !canonical_backup.starts_with(&canonical_dir) {
        return Err(AppError::Config(
            "非法路径：备份文件不在备份目录内".to_string(),
        ));
    }
    Ok(())
}

fn get_backup_dir(state: &AppState) -> Result<std::path::PathBuf, AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;
    Ok(config_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("backups"))
}

pub fn list_backups(state: &AppState) -> Result<Vec<BackupInfo>, AppError> {
    todo!()
}

pub fn create_backup(state: &AppState) -> Result<String, AppError> {
    todo!()
}

pub fn restore_backup(state: &AppState, filename: &str) -> Result<(), AppError> {
    todo!()
}

pub fn delete_backup(state: &AppState, filename: &str) -> Result<(), AppError> {
    todo!()
}

pub fn compare_configs(state: &AppState, backup_filename: &str) -> Result<ConfigDiff, AppError> {
    todo!()
}

pub fn hot_reload(state: &AppState) -> Result<Config, AppError> {
    todo!()
}

pub fn export_config(state: &AppState, path: &str) -> Result<(), AppError> {
    todo!()
}

pub fn import_config(state: &AppState, path: &str) -> Result<(), AppError> {
    todo!()
}
```

- [ ] **Step 4: Verify compilation**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo check -p asd-application 2>&1 | Select-Object -Last 5`
Expected: Compiled successfully (warnings ok, todo!() compiles)

- [ ] **Step 5: Commit**

```bash
git add crates/asd-application/src/backup_service.rs crates/asd-application/src/lib.rs crates/asd-application/Cargo.toml
git commit -m "feat: add BackupService module stubs with DTOs"
```

### Task 2: Write BackupService failing tests

**Files:**
- Create: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\tests\backup_service_tests.rs`

- [ ] **Step 1: Create test file with Mock infrastructure and failing tests**

```rust
use asd_application::backup_service::*;
use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::*;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use std::sync::Arc;

struct MockIpcSender;
impl IpcSender for MockIpcSender {
    fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> { Ok(1) }
    fn send_and_wait(&self, _cmd: IpcCommand, _timeout: std::time::Duration) -> Result<IpcMessage, String> {
        Ok(IpcMessage::response(1, 0, "ok", None))
    }
    fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> { Ok(()) }
}

struct MockEventEmitter;
impl EventEmitter for MockEventEmitter {
    fn emit(&self, _event: &str, _payload: serde_json::Value) -> bool { true }
}

struct MockProcessWatcher;
impl ProcessWatcher for MockProcessWatcher {
    fn state(&self) -> WatchdogStateEnum { WatchdogStateEnum::Idle }
    fn restart_count(&self) -> u32 { 0 }
}

fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
            name: Some("test".to_string()),
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        },
    );
    Config {
        control_hotkeys: ControlHotkeys {
            emergency: "F10".to_string(),
            release_all_holds: "^r".to_string(),
            show_status: "^0".to_string(),
            toggle_all: "^1".to_string(),
            toggle_hold_mode: "^h".to_string(),
        },
        group_settings,
        hold_settings: None,
        last_modified: None,
        version: Some("3.0".to_string()),
    }
}

fn make_test_state() -> Arc<AppState> {
    let config = make_test_config();
    Arc::new(AppState::new(
        config,
        Arc::new(MockIpcSender),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter),
    ))
}

fn make_test_state_with_path() -> (Arc<AppState>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let config_path = dir.path().join("config.json");
    let state = make_test_state();
    state.set_config_path(config_path);
    (state, dir)
}

#[test]
fn test_list_backups_empty_dir() {
    let (state, _dir) = make_test_state_with_path();
    let result = list_backups(&state);
    assert!(result.is_ok());
    assert!(result.unwrap().is_empty());
}

#[test]
fn test_list_backups_no_config_path() {
    let state = make_test_state();
    let result = list_backups(&state);
    assert!(result.is_err());
}

#[test]
fn test_create_backup() {
    let (state, _dir) = make_test_state_with_path();
    let result = create_backup(&state);
    assert!(result.is_ok());
    let filename = result.unwrap();
    assert!(filename.starts_with("backup_"));
    assert!(filename.ends_with(".json"));
}

#[test]
fn test_create_backup_no_config_path() {
    let state = make_test_state();
    let result = create_backup(&state);
    assert!(result.is_err());
}

#[test]
fn test_restore_backup_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = restore_backup(&state, "nonexistent.json");
    assert!(result.is_err());
}

#[test]
fn test_restore_backup_path_traversal() {
    let (state, _dir) = make_test_state_with_path();
    let result = restore_backup(&state, "../etc/passwd");
    assert!(result.is_err());
}

#[test]
fn test_delete_backup_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = delete_backup(&state, "nonexistent.json");
    assert!(result.is_err());
}

#[test]
fn test_hot_reload_no_config_path() {
    let state = make_test_state();
    let result = hot_reload(&state);
    assert!(result.is_err());
}

#[test]
fn test_export_config() {
    let (state, dir) = make_test_state_with_path();
    let export_path = dir.path().join("exported.json").to_str().unwrap().to_string();
    let result = export_config(&state, &export_path);
    assert!(result.is_ok());
    assert!(std::path::Path::new(&export_path).exists());
}

#[test]
fn test_import_config_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = import_config(&state, "/nonexistent/file.json");
    assert!(result.is_err());
}

#[test]
fn test_compare_configs_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = compare_configs(&state, "nonexistent.json");
    assert!(result.is_err());
}
```

- [ ] **Step 2: Add tempfile dev-dependency**

In `crates/asd-application/Cargo.toml`, add:
```toml
[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 3: Run tests to verify they fail (todo!() panics)**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test -p asd-application --test backup_service_tests 2>&1 | Select-Object -Last 10`
Expected: All tests FAIL (panics from todo!())

- [ ] **Step 4: Commit**

```bash
git add crates/asd-application/tests/backup_service_tests.rs crates/asd-application/Cargo.toml
git commit -m "test: add BackupService failing tests (RED phase)"
```

### Task 3: Implement BackupService functions

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\backup_service.rs`

- [ ] **Step 1: Replace all todo!() with actual implementations**

Replace each `todo!()` with the logic from `src-tauri/src/commands/config_cmd.rs`:

```rust
pub fn list_backups(state: &AppState) -> Result<Vec<BackupInfo>, AppError> {
    let backup_dir = get_backup_dir(state)?;
    if !backup_dir.exists() {
        std::fs::create_dir_all(&backup_dir)
            .map_err(|e| AppError::Config(format!("创建备份目录失败: {e}")))?;
        return Ok(vec![]);
    }
    let mut backups = Vec::new();
    let entries = std::fs::read_dir(&backup_dir)
        .map_err(|e| AppError::Config(format!("读取备份目录失败: {e}")))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("json") {
            let metadata = entry
                .metadata()
                .map_err(|e| AppError::Config(format!("读取备份元数据失败: {e}")))?;
            let filename = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
                .to_string();
            let timestamp = filename
                .trim_end_matches(".json")
                .replace("backup_", "")
                .replace("_", " ")
                .replace("-", ":");
            backups.push(BackupInfo {
                filename,
                timestamp,
                size: metadata.len(),
            });
        }
    }
    backups.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    Ok(backups)
}

pub fn create_backup(state: &AppState) -> Result<String, AppError> {
    let backup_dir = get_backup_dir(state)?;
    if !backup_dir.exists() {
        std::fs::create_dir_all(&backup_dir)
            .map_err(|e| AppError::Config(format!("创建备份目录失败: {e}")))?;
    }
    let now = chrono::Local::now();
    let timestamp = now.format("%Y%m%d_%H%M%S").to_string();
    let backup_filename = format!("backup_{timestamp}.json");
    let backup_path = backup_dir.join(&backup_filename);
    let current_config = state.read_config()?;
    ConfigRepository::save_to_path(&current_config, &backup_path).map_err(AppError::Config)?;
    tracing::info!("已创建备份: {backup_filename}");
    Ok(backup_filename)
}

pub fn restore_backup(state: &AppState, filename: &str) -> Result<(), AppError> {
    let backup_dir = get_backup_dir(state)?;
    let backup_path = backup_dir.join(filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {filename}")));
    }
    validate_path_in_backup_dir(&backup_path, &backup_dir)?;
    let restored_config = ConfigRepository::load_from_path(&backup_path).map_err(AppError::Config)?;
    state.save_config_atomic(restored_config)?;
    tracing::info!("已恢复备份: {filename}");
    Ok(())
}

pub fn delete_backup(state: &AppState, filename: &str) -> Result<(), AppError> {
    let backup_dir = get_backup_dir(state)?;
    let backup_path = backup_dir.join(filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {filename}")));
    }
    validate_path_in_backup_dir(&backup_path, &backup_dir)?;
    std::fs::remove_file(&backup_path)
        .map_err(|e| AppError::Config(format!("删除备份失败: {e}")))?;
    tracing::info!("已删除备份: {filename}");
    Ok(())
}

pub fn compare_configs(state: &AppState, backup_filename: &str) -> Result<ConfigDiff, AppError> {
    let current_config = state.read_config()?;
    let backup_dir = get_backup_dir(state)?;
    let backup_path = backup_dir.join(backup_filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {backup_filename}")));
    }
    validate_path_in_backup_dir(&backup_path, &backup_dir)?;
    let backup_config = ConfigRepository::load_from_path(&backup_path).map_err(AppError::Config)?;
    let current_ids: std::collections::HashSet<String> =
        current_config.group_settings.keys().cloned().collect();
    let backup_ids: std::collections::HashSet<String> =
        backup_config.group_settings.keys().cloned().collect();
    let added: Vec<String> = current_ids.difference(&backup_ids).cloned().collect();
    let removed: Vec<String> = backup_ids.difference(&current_ids).cloned().collect();
    let mut modified = Vec::new();
    for id in current_ids.intersection(&backup_ids) {
        let current_json = serde_json::to_string(current_config.group_settings.get(id).unwrap())
            .unwrap_or_default();
        let backup_json = serde_json::to_string(backup_config.group_settings.get(id).unwrap())
            .unwrap_or_default();
        if current_json != backup_json {
            modified.push(id.clone());
        }
    }
    Ok(ConfigDiff {
        added_groups: added,
        removed_groups: removed,
        modified_groups: modified,
    })
}

pub fn hot_reload(state: &AppState) -> Result<Config, AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;
    let reloaded_config = ConfigRepository::load_from_path(&config_path).map_err(AppError::Config)?;
    state.save_config_atomic(reloaded_config.clone())?;
    tracing::info!("热重载配置成功");
    Ok(reloaded_config)
}

pub fn export_config(state: &AppState, path: &str) -> Result<(), AppError> {
    let config = state.read_config()?;
    let json = serde_json::to_string_pretty(&config)
        .map_err(|e| AppError::Config(format!("序列化配置失败: {e}")))?;
    std::fs::write(path, json).map_err(|e| AppError::Config(format!("写入文件失败: {e}")))?;
    tracing::info!("配置已导出: {}", path);
    Ok(())
}

pub fn import_config(state: &AppState, path: &str) -> Result<(), AppError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| AppError::Config(format!("读取文件失败: {e}")))?;
    let imported_config: Config = serde_json::from_str(&content)
        .map_err(|e| AppError::Config(format!("解析配置失败: {e}")))?;
    state.save_config_atomic(imported_config)?;
    tracing::info!("配置已导入: {}", path);
    Ok(())
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test -p asd-application --test backup_service_tests 2>&1 | Select-Object -Last 5`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add crates/asd-application/src/backup_service.rs
git commit -m "feat: implement BackupService functions (GREEN phase)"
```

### Task 4: Update config_cmd.rs to delegate to BackupService

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\commands\config_cmd.rs`

- [ ] **Step 1: Replace command logic with service delegation**

Replace the entire `config_cmd.rs` content with:

```rust
use asd_application::backup_service;
use asd_application::backup_service::{BackupInfo, ConfigDiff};
use asd_application::error::AppError;
use asd_application::state::AppState;
use crate::domain::config::Config;
use crate::domain::validator::ValidationResult;
use crate::domain::validator::ConfigValidator;
use std::sync::Arc;

#[tauri::command]
pub fn get_config(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    state.read_config()
}

#[tauri::command]
pub fn save_config(state: tauri::State<'_, Arc<AppState>>, config: Config) -> Result<(), AppError> {
    let validation = ConfigValidator::validate(&config.group_settings);
    if !validation.is_valid() {
        return Err(AppError::Validation(
            validation
                .errors
                .iter()
                .map(|e| e.to_string())
                .collect::<Vec<_>>()
                .join("; "),
        ));
    }
    state
        .save_config_atomic(config)
        .map_err(|e| AppError::Config(e.to_string()))?;
    Ok(())
}

#[tauri::command]
pub fn validate_config(config: Config) -> Result<ValidationResult, AppError> {
    let result = ConfigValidator::validate(&config.group_settings);
    Ok(result)
}

#[tauri::command]
pub async fn list_backups(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<Vec<BackupInfo>, AppError> {
    backup_service::list_backups(&state)
}

#[tauri::command]
pub async fn create_backup(state: tauri::State<'_, Arc<AppState>>) -> Result<String, AppError> {
    backup_service::create_backup(&state)
}

#[tauri::command]
pub async fn restore_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    backup_service::restore_backup(&state, &filename)
}

#[tauri::command]
pub async fn delete_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    backup_service::delete_backup(&state, &filename)
}

#[tauri::command]
pub fn hot_reload(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    backup_service::hot_reload(&state)
}

#[tauri::command]
pub async fn export_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    backup_service::export_config(&state, &path)
}

#[tauri::command]
pub async fn import_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    backup_service::import_config(&state, &path)
}

#[tauri::command]
pub async fn compare_configs(
    state: tauri::State<'_, Arc<AppState>>,
    backup_filename: String,
) -> Result<ConfigDiff, AppError> {
    backup_service::compare_configs(&state, &backup_filename)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::config::*;
    use indexmap::IndexMap;

    fn make_valid_config() -> Config {
        let mut group_settings = IndexMap::new();
        group_settings.insert(
            "1".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: Some(10),
                name: Some("测试组".to_string()),
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["1".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        Config {
            control_hotkeys: ControlHotkeys {
                emergency: "F10".to_string(),
                release_all_holds: "^r".to_string(),
                show_status: "^0".to_string(),
                toggle_all: "^1".to_string(),
                toggle_hold_mode: "^h".to_string(),
            },
            group_settings,
            hold_settings: None,
            last_modified: None,
            version: Some("3.0".to_string()),
        }
    }

    #[test]
    fn test_validate_config_valid() {
        let config = make_valid_config();
        let result = ConfigValidator::validate(&config.group_settings);
        assert!(result.is_valid(), "有效配置应通过校验: {:?}", result.errors);
    }

    #[test]
    fn test_validate_config_empty_hotkey() {
        let mut config = make_valid_config();
        config.group_settings.get_mut("1").unwrap().hotkey = String::new();
        let result = ConfigValidator::validate(&config.group_settings);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "hotkey"));
    }

    #[test]
    fn test_validate_config_empty_mode() {
        let mut config = make_valid_config();
        config.group_settings.get_mut("1").unwrap().mode = String::new();
        let result = ConfigValidator::validate(&config.group_settings);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "mode"));
    }

    #[test]
    fn test_validate_config_duplicate_hotkeys() {
        let mut config = make_valid_config();
        config.group_settings.insert(
            "2".to_string(),
            GroupConfig {
                hotkey: "F1".to_string(),
                key_press_duration: None,
                name: None,
                mode: "periodic".to_string(),
                hold_keys: None,
                hold_mode: None,
                hold_pattern: None,
                hold_triggers: None,
                mode_data: ModeData::Periodic(PeriodicData {
                    keys: vec!["2".to_string()],
                    intervals: vec![50],
                }),
            },
        );
        let result = ConfigValidator::validate(&config.group_settings);
        assert!(!result.is_valid());
        assert!(result.errors.iter().any(|e| e.field == "hotkey" && e.message.contains("重复")));
    }

    #[test]
    fn test_app_error_validation_format() {
        let err = AppError::Validation("字段不能为空; 模式不匹配".to_string());
        let msg = err.to_string();
        assert!(msg.contains("验证失败"));
        assert!(msg.contains("字段不能为空"));
    }

    #[test]
    fn test_app_error_config_format() {
        let err = AppError::Config("文件不存在".to_string());
        let msg = err.to_string();
        assert!(msg.contains("配置错误"));
    }

    #[test]
    fn test_app_error_serialization() {
        let err = AppError::Validation("测试".to_string());
        let json = serde_json::to_string(&err).unwrap();
        assert!(json.contains("验证失败"));
    }
}
```

- [ ] **Step 2: Verify full workspace compilation**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo check --workspace 2>&1 | Select-Object -Last 5`
Expected: Compiled successfully

- [ ] **Step 3: Run all tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test --workspace 2>&1 | Select-String -Pattern "test result"`
Expected: All test suites pass

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/commands/config_cmd.rs
git commit -m "refactor: delegate config_cmd to BackupService"
```

---

## Phase 2: GroupService

### Task 5: Create GroupService module with DTOs

**Files:**
- Create: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\group_service.rs`
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\lib.rs`

- [ ] **Step 1: Add module declaration to lib.rs**

In `crates/asd-application/src/lib.rs`, add:
```rust
pub mod group_service;
```

- [ ] **Step 2: Create group_service.rs with DTOs and function stubs**

```rust
use crate::error::AppError;
use crate::state::AppState;
use asd_domain::models::SkillGroup;
use asd_ipc_protocol::IpcCommand;
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupSummary {
    pub id: String,
    pub name: String,
    pub hotkey: String,
    pub mode: String,
    pub active: bool,
}

impl From<&SkillGroup> for GroupSummary {
    fn from(g: &SkillGroup) -> Self {
        Self {
            id: g.id.clone(),
            name: g.name.clone(),
            hotkey: g.hotkey.clone(),
            mode: g.mode.clone(),
            active: g.active,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupStatus {
    pub id: String,
    pub active: bool,
}

pub fn toggle_group(state: &AppState, group_id: &str) -> Result<GroupStatus, AppError> {
    todo!()
}

pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError> {
    todo!()
}

pub fn toggle_all(state: &AppState, active: bool) -> Result<(), AppError> {
    todo!()
}

pub fn batch_toggle_groups(state: &AppState, group_ids: &[String], active: bool) -> Result<(), AppError> {
    todo!()
}

pub fn batch_delete_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    todo!()
}

pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    todo!()
}

pub fn register_hotkey(state: &AppState, hotkey: &str, group_id: &str) -> Result<(), AppError> {
    todo!()
}

pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError> {
    todo!()
}
```

- [ ] **Step 3: Verify compilation**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo check -p asd-application 2>&1 | Select-Object -Last 5`
Expected: Compiled successfully

- [ ] **Step 4: Commit**

```bash
git add crates/asd-application/src/group_service.rs crates/asd-application/src/lib.rs
git commit -m "feat: add GroupService module stubs with DTOs"
```

### Task 6: Write GroupService failing tests

**Files:**
- Create: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\tests\group_service_tests.rs`

- [ ] **Step 1: Create test file with recording Mock infrastructure**

```rust
use asd_application::error::AppError;
use asd_application::group_service::*;
use asd_application::state::AppState;
use asd_domain::config::*;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use std::sync::{Arc, Mutex};

struct RecordingIpcSender {
    commands: Mutex<Vec<IpcCommand>>,
}
impl RecordingIpcSender {
    fn new() -> Self {
        Self { commands: Mutex::new(Vec::new()) }
    }
    fn sent_commands(&self) -> Vec<IpcCommand> {
        self.commands.lock().unwrap().clone()
    }
}
impl IpcSender for RecordingIpcSender {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        self.commands.lock().unwrap().push(cmd);
        Ok(1)
    }
    fn send_and_wait(&self, cmd: IpcCommand, _timeout: std::time::Duration) -> Result<IpcMessage, String> {
        self.commands.lock().unwrap().push(cmd);
        Ok(IpcMessage::response(1, 0, "ok", None))
    }
    fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> { Ok(()) }
}

struct MockEventEmitter;
impl EventEmitter for MockEventEmitter {
    fn emit(&self, _event: &str, _payload: serde_json::Value) -> bool { true }
}

struct MockProcessWatcher;
impl ProcessWatcher for MockProcessWatcher {
    fn state(&self) -> WatchdogStateEnum { WatchdogStateEnum::Idle }
    fn restart_count(&self) -> u32 { 0 }
}

fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
            name: Some("test".to_string()),
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        },
    );
    group_settings.insert(
        "2".to_string(),
        GroupConfig {
            hotkey: "F2".to_string(),
            key_press_duration: Some(10),
            name: Some("test2".to_string()),
            mode: "sequence".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Sequence(SequenceData {
                keys: vec!["2".to_string()],
                delays: vec![100],
            }),
        },
    );
    Config {
        control_hotkeys: ControlHotkeys {
            emergency: "F10".to_string(),
            release_all_holds: "^r".to_string(),
            show_status: "^0".to_string(),
            toggle_all: "^1".to_string(),
            toggle_hold_mode: "^h".to_string(),
        },
        group_settings,
        hold_settings: None,
        last_modified: None,
        version: Some("3.0".to_string()),
    }
}

fn make_test_state() -> Arc<AppState> {
    let config = make_test_config();
    Arc::new(AppState::new(
        config,
        Arc::new(RecordingIpcSender::new()),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter),
    ))
}

fn make_test_state_with_sender() -> (Arc<AppState>, Arc<RecordingIpcSender>) {
    let config = make_test_config();
    let sender = Arc::new(RecordingIpcSender::new());
    let state = Arc::new(AppState::new(
        config,
        sender.clone(),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter),
    ));
    (state, sender)
}

#[test]
fn test_toggle_group() {
    let state = make_test_state();
    let result = toggle_group(&state, "1");
    assert!(result.is_ok());
    let status = result.unwrap();
    assert_eq!(status.id, "1");
    assert!(status.active);
}

#[test]
fn test_toggle_group_not_found() {
    let state = make_test_state();
    let result = toggle_group(&state, "999");
    assert!(matches!(result, Err(AppError::GroupNotFound(_))));
}

#[test]
fn test_toggle_group_sends_ipc() {
    let (state, sender) = make_test_state_with_sender();
    toggle_group(&state, "1").unwrap();
    let cmds = sender.sent_commands();
    assert_eq!(cmds.len(), 1);
}

#[test]
fn test_delete_group() {
    let (state, sender) = make_test_state_with_sender();
    state.set_group_active("1", true).unwrap();
    let result = delete_group(&state, "1");
    assert!(result.is_ok());
}

#[test]
fn test_delete_group_not_found() {
    let state = make_test_state();
    let result = delete_group(&state, "999");
    assert!(result.is_err());
}

#[test]
fn test_toggle_all() {
    let (state, sender) = make_test_state_with_sender();
    let result = toggle_all(&state, true);
    assert!(result.is_ok());
}

#[test]
fn test_batch_toggle_groups() {
    let (state, sender) = make_test_state_with_sender();
    let result = batch_toggle_groups(&state, &["1".to_string()], true);
    assert!(result.is_ok());
}

#[test]
fn test_batch_delete_groups() {
    let (state, sender) = make_test_state_with_sender();
    let result = batch_delete_groups(&state, &["1".to_string()]);
    assert!(result.is_ok());
}

#[test]
fn test_reorder_groups() {
    let state = make_test_state();
    let result = reorder_groups(&state, &["2".to_string(), "1".to_string()]);
    assert!(result.is_ok());
    let groups = state.read_groups().unwrap();
    let order: Vec<&String> = groups.keys().collect();
    assert_eq!(order[0], &"2".to_string());
    assert_eq!(order[1], &"1".to_string());
}

#[test]
fn test_register_hotkey() {
    let (state, sender) = make_test_state_with_sender();
    let result = register_hotkey(&state, "F3", "1");
    assert!(result.is_ok());
}

#[test]
fn test_register_hotkey_duplicate() {
    let state = make_test_state();
    register_hotkey(&state, "F3", "1").unwrap();
    let result = register_hotkey(&state, "F3", "2");
    assert!(result.is_err());
}

#[test]
fn test_unregister_hotkey() {
    let (state, sender) = make_test_state_with_sender();
    register_hotkey(&state, "F3", "1").unwrap();
    let result = unregister_hotkey(&state, "F3");
    assert!(result.is_ok());
}

#[test]
fn test_unregister_hotkey_not_registered() {
    let state = make_test_state();
    let result = unregister_hotkey(&state, "F99");
    assert!(result.is_err());
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test -p asd-application --test group_service_tests 2>&1 | Select-Object -Last 10`
Expected: All tests FAIL (panics from todo!())

- [ ] **Step 3: Commit**

```bash
git add crates/asd-application/tests/group_service_tests.rs
git commit -m "test: add GroupService failing tests (RED phase)"
```

### Task 7: Implement GroupService functions

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\group_service.rs`

- [ ] **Step 1: Replace all todo!() with actual implementations**

```rust
pub fn toggle_group(state: &AppState, group_id: &str) -> Result<GroupStatus, AppError> {
    let group = state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;
    let new_active = !group.active;
    state.set_group_active(group_id, new_active)?;
    let mode_data_json = serde_json::to_value(&group.mode_data)
        .ok()
        .filter(|v| !v.is_null());
    let cmd = IpcCommand::ToggleGroup {
        group_id: group_id.to_string(),
        active: new_active,
        mode: Some(group.mode.clone()),
        key_press_duration: if group.key_press_duration > 0 {
            Some(group.key_press_duration)
        } else {
            None
        },
        hold_keys: group.hold_keys.clone(),
        hold_mode: group.hold_mode.clone(),
        mode_data: mode_data_json,
    };
    state.try_send_ipc_command(&cmd);
    Ok(GroupStatus {
        id: group_id.to_string(),
        active: new_active,
    })
}

pub fn delete_group(state: &AppState, group_id: &str) -> Result<(), AppError> {
    let is_active = {
        let groups = state.read_groups()?;
        groups.get(group_id).map(|g| g.active).unwrap_or(false)
    };
    if is_active {
        let cmd = IpcCommand::ToggleGroup {
            group_id: group_id.to_string(),
            active: false,
            mode: None,
            key_press_duration: None,
            hold_keys: None,
            hold_mode: None,
            mode_data: None,
        };
        state.try_send_ipc_command(&cmd);
    }
    let current_config = state.read_config()?;
    let mut new_config = current_config;
    new_config.group_settings.shift_remove(group_id);
    state.save_config_atomic(new_config)?;
    if is_active {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        registry.remove(group_id);
    }
    tracing::info!("已删除分组: {}", group_id);
    Ok(())
}

pub fn toggle_all(state: &AppState, active: bool) -> Result<(), AppError> {
    let toggle_data: Vec<(String, SkillGroup)> = {
        let groups = state.read_groups()?;
        groups
            .iter()
            .filter(|(_, group)| group.active != active)
            .map(|(id, group)| (id.clone(), group.clone()))
            .collect()
    };
    for (id, group) in &toggle_data {
        let mode_data = serde_json::to_value(&group.mode_data)
            .ok()
            .filter(|v| !v.is_null());
        let cmd = IpcCommand::ToggleGroup {
            group_id: id.clone(),
            active,
            mode: Some(group.mode.clone()),
            key_press_duration: if group.key_press_duration > 0 {
                Some(group.key_press_duration)
            } else {
                None
            },
            hold_keys: group.hold_keys.clone(),
            hold_mode: group.hold_mode.clone(),
            mode_data,
        };
        state.try_send_ipc_command(&cmd);
        state.set_group_active(id, active)?;
    }
    tracing::info!("全局切换: active={}", active);
    Ok(())
}

pub fn batch_toggle_groups(state: &AppState, group_ids: &[String], active: bool) -> Result<(), AppError> {
    for id in group_ids {
        let group_data = {
            let groups = state.read_groups()?;
            groups.get(id).cloned()
        };
        if let Some(group) = group_data {
            let mode_data = serde_json::to_value(&group.mode_data)
                .ok()
                .filter(|v| !v.is_null());
            let cmd = IpcCommand::ToggleGroup {
                group_id: id.clone(),
                active,
                mode: Some(group.mode.clone()),
                key_press_duration: if group.key_press_duration > 0 {
                    Some(group.key_press_duration)
                } else {
                    None
                },
                hold_keys: group.hold_keys.clone(),
                hold_mode: group.hold_mode.clone(),
                mode_data,
            };
            state.try_send_ipc_command(&cmd);
            state.set_group_active(id, active)?;
        }
    }
    tracing::info!("批量切换: {} 个分组, active={}", group_ids.len(), active);
    Ok(())
}

pub fn batch_delete_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    for id in group_ids {
        let group_active = {
            let groups = state.read_groups()?;
            groups.get(id).map(|g| g.active).unwrap_or(false)
        };
        if group_active {
            let cmd = IpcCommand::ToggleGroup {
                group_id: id.clone(),
                active: false,
                mode: None,
                key_press_duration: None,
                hold_keys: None,
                hold_mode: None,
                mode_data: None,
            };
            state.try_send_ipc_command(&cmd);
        }
    }
    let active_ids: Vec<String> = {
        let groups = state.read_groups()?;
        group_ids
            .iter()
            .filter(|id| groups.get(*id).map(|g| g.active).unwrap_or(false))
            .cloned()
            .collect()
    };
    let current_config = state.read_config()?;
    let mut new_config = current_config;
    for id in group_ids {
        new_config.group_settings.shift_remove(id);
    }
    state.save_config_atomic(new_config)?;
    if !active_ids.is_empty() {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        for id in &active_ids {
            registry.remove(id);
        }
    }
    tracing::info!("批量删除: {} 个分组", group_ids.len());
    Ok(())
}

pub fn reorder_groups(state: &AppState, group_ids: &[String]) -> Result<(), AppError> {
    let current_config = state.read_config()?;
    let mut new_settings = IndexMap::new();
    for id in group_ids {
        if let Some(setting) = current_config.group_settings.get(id) {
            new_settings.insert(id.clone(), setting.clone());
        }
    }
    for (id, setting) in &current_config.group_settings {
        if !group_ids.contains(id) {
            new_settings.insert(id.clone(), setting.clone());
        }
    }
    let mut new_config = current_config;
    new_config.group_settings = new_settings;
    state.save_config_atomic(new_config)?;
    tracing::info!("分组排序已更新: {} 个分组", group_ids.len());
    Ok(())
}

pub fn register_hotkey(state: &AppState, hotkey: &str, group_id: &str) -> Result<(), AppError> {
    {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        if let Some(existing_id) = registry.get(hotkey) {
            return Err(AppError::Validation(format!(
                "热键 '{}' 已被分组 '{}' 注册",
                hotkey, existing_id
            )));
        }
        registry.insert(hotkey.to_string(), group_id.to_string());
        tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
    }
    let cmd = IpcCommand::RegisterHotkey {
        hotkey: hotkey.to_string(),
        group_id: group_id.to_string(),
    };
    state.try_send_ipc_command(&cmd);
    Ok(())
}

pub fn unregister_hotkey(state: &AppState, hotkey: &str) -> Result<(), AppError> {
    let removed = {
        let mut registry = state
            .active_hotkeys
            .write()
            .map_err(|e| AppError::Internal(e.to_string()))?;
        registry.remove(hotkey).is_some()
    };
    if removed {
        tracing::info!("热键 '{}' 已注销", hotkey);
        let cmd = IpcCommand::UnregisterHotkey {
            hotkey: hotkey.to_string(),
        };
        state.try_send_ipc_command(&cmd);
        Ok(())
    } else {
        Err(AppError::Validation(format!("热键 '{}' 未注册", hotkey)))
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test -p asd-application --test group_service_tests 2>&1 | Select-Object -Last 5`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add crates/asd-application/src/group_service.rs
git commit -m "feat: implement GroupService functions (GREEN phase)"
```

### Task 8: Update group_cmd.rs and hotkey_cmd.rs to delegate to GroupService

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\commands\group_cmd.rs`
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\commands\hotkey_cmd.rs`

- [ ] **Step 1: Replace group_cmd.rs content**

```rust
use asd_application::error::AppError;
use asd_application::group_service;
use asd_application::group_service::{GroupStatus, GroupSummary};
use asd_application::state::AppState;
use crate::domain::models::SkillGroup;
use std::sync::Arc;

#[tauri::command]
pub fn get_groups(state: tauri::State<'_, Arc<AppState>>) -> Result<Vec<GroupSummary>, AppError> {
    let groups = state.read_groups()?;
    Ok(groups.values().map(GroupSummary::from).collect())
}

#[tauri::command]
pub async fn toggle_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<GroupStatus, AppError> {
    group_service::toggle_group(&state, &group_id)
}

#[tauri::command]
pub fn get_group_detail(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<SkillGroup, AppError> {
    state
        .get_group(&group_id)
        .ok_or(AppError::GroupNotFound(group_id))
}

#[tauri::command]
pub async fn delete_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<(), AppError> {
    group_service::delete_group(&state, &group_id)
}

#[tauri::command]
pub async fn toggle_all(
    state: tauri::State<'_, Arc<AppState>>,
    active: bool,
) -> Result<(), AppError> {
    group_service::toggle_all(&state, active)
}

#[tauri::command]
pub async fn batch_toggle_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
    active: bool,
) -> Result<(), AppError> {
    group_service::batch_toggle_groups(&state, &group_ids, active)
}

#[tauri::command]
pub async fn batch_delete_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<(), AppError> {
    group_service::batch_delete_groups(&state, &group_ids)
}

#[tauri::command]
pub fn reorder_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<(), AppError> {
    group_service::reorder_groups(&state, &group_ids)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::config::*;

    fn make_skill_group() -> SkillGroup {
        SkillGroup {
            id: "1".to_string(),
            name: "测试组".to_string(),
            hotkey: "F1".to_string(),
            active: true,
            mode: "periodic".to_string(),
            key_press_duration: 10,
            hold_keys: Some(vec!["Shift".to_string()]),
            hold_mode: Some("continuous".to_string()),
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        }
    }

    #[test]
    fn test_group_summary_from_skill_group() {
        let group = make_skill_group();
        let summary = GroupSummary::from(&group);
        assert_eq!(summary.id, "1");
        assert_eq!(summary.name, "测试组");
        assert_eq!(summary.hotkey, "F1");
        assert_eq!(summary.mode, "periodic");
        assert!(summary.active);
    }

    #[test]
    fn test_group_summary_from_inactive_group() {
        let mut group = make_skill_group();
        group.active = false;
        let summary = GroupSummary::from(&group);
        assert!(!summary.active);
    }

    #[test]
    fn test_group_summary_serialization() {
        let group = make_skill_group();
        let summary = GroupSummary::from(&group);
        let json = serde_json::to_string(&summary).unwrap();
        let decoded: GroupSummary = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.id, "1");
        assert_eq!(decoded.name, "测试组");
        assert_eq!(decoded.hotkey, "F1");
        assert_eq!(decoded.mode, "periodic");
        assert!(decoded.active);
    }

    #[test]
    fn test_group_status_serialization() {
        let status = GroupStatus {
            id: "2".to_string(),
            active: false,
        };
        let json = serde_json::to_string(&status).unwrap();
        let decoded: GroupStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.id, "2");
        assert!(!decoded.active);
    }
}
```

- [ ] **Step 2: Replace hotkey_cmd.rs content**

```rust
use asd_application::error::AppError;
use asd_application::group_service;
use asd_application::state::AppState;
use std::sync::Arc;

#[tauri::command]
pub async fn register_hotkey(
    state: tauri::State<'_, Arc<AppState>>,
    hotkey: String,
    group_id: String,
) -> Result<(), AppError> {
    group_service::register_hotkey(&state, &hotkey, &group_id)
}

#[tauri::command]
pub async fn unregister_hotkey(
    state: tauri::State<'_, Arc<AppState>>,
    hotkey: String,
) -> Result<(), AppError> {
    group_service::unregister_hotkey(&state, &hotkey)
}
```

- [ ] **Step 3: Verify full workspace compilation**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo check --workspace 2>&1 | Select-Object -Last 5`
Expected: Compiled successfully

- [ ] **Step 4: Run all tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test --workspace 2>&1 | Select-String -Pattern "test result"`
Expected: All test suites pass

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/commands/group_cmd.rs src-tauri/src/commands/hotkey_cmd.rs
git commit -m "refactor: delegate group_cmd and hotkey_cmd to GroupService"
```

---

## Phase 3: RecordingService

### Task 9: Create RecordingService module with DTOs

**Files:**
- Create: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\recording_service.rs`
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\lib.rs`

- [ ] **Step 1: Add module declaration to lib.rs**

In `crates/asd-application/src/lib.rs`, add:
```rust
pub mod recording_service;
```

- [ ] **Step 2: Create recording_service.rs with DTOs and function stubs**

```rust
use crate::error::AppError;
use crate::state::AppState;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingResult {
    pub seq: u64,
    pub keys: Vec<String>,
    pub mode: String,
    #[serde(rename = "intervals", skip_serializing_if = "Vec::is_empty", default)]
    pub intervals: Vec<u64>,
    #[serde(rename = "delays", skip_serializing_if = "Vec::is_empty", default)]
    pub delays: Vec<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ImportedRecording {
    pub keys: Vec<String>,
    pub intervals: Vec<u64>,
    pub mode: String,
}

pub fn start_recording(state: &AppState, group_id: &str, mode: &str) -> Result<(), AppError> {
    todo!()
}

pub fn stop_recording(state: &AppState) -> Result<RecordingResult, AppError> {
    todo!()
}

pub fn pause_recording(state: &AppState) -> Result<u64, AppError> {
    todo!()
}

pub fn resume_recording(state: &AppState) -> Result<u64, AppError> {
    todo!()
}

pub fn export_recording(path: &str, keys: &[String], intervals: &[u64], mode: &str) -> Result<(), AppError> {
    todo!()
}

pub fn import_recording(path: &str) -> Result<ImportedRecording, AppError> {
    todo!()
}

pub fn start_validation(state: &AppState, group_id: &str) -> Result<u64, AppError> {
    todo!()
}

pub fn stop_validation(state: &AppState) -> Result<u64, AppError> {
    todo!()
}
```

- [ ] **Step 3: Verify compilation**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo check -p asd-application 2>&1 | Select-Object -Last 5`
Expected: Compiled successfully

- [ ] **Step 4: Commit**

```bash
git add crates/asd-application/src/recording_service.rs crates/asd-application/src/lib.rs
git commit -m "feat: add RecordingService module stubs with DTOs"
```

### Task 10: Write RecordingService failing tests

**Files:**
- Create: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\tests\recording_service_tests.rs`

- [ ] **Step 1: Create test file**

```rust
use asd_application::error::AppError;
use asd_application::recording_service::*;
use asd_application::state::AppState;
use asd_domain::config::*;
use asd_domain::traits::{EventEmitter, IpcSender, ProcessWatcher};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use indexmap::IndexMap;
use std::sync::Arc;

struct MockIpcSender;
impl IpcSender for MockIpcSender {
    fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> { Ok(1) }
    fn send_and_wait(&self, _cmd: IpcCommand, _timeout: std::time::Duration) -> Result<IpcMessage, String> {
        Ok(IpcMessage::response(1, 0, "ok", Some(serde_json::json!({
            "keys": ["1", "2"],
            "mode": "periodic",
            "intervals": [50, 100],
            "delays": []
        }))))
    }
    fn send_message(&self, _msg: &IpcMessage) -> Result<(), String> { Ok(()) }
}

struct MockEventEmitter;
impl EventEmitter for MockEventEmitter {
    fn emit(&self, _event: &str, _payload: serde_json::Value) -> bool { true }
}

struct MockProcessWatcher;
impl ProcessWatcher for MockProcessWatcher {
    fn state(&self) -> WatchdogStateEnum { WatchdogStateEnum::Idle }
    fn restart_count(&self) -> u32 { 0 }
}

fn make_test_config() -> Config {
    let mut group_settings = IndexMap::new();
    group_settings.insert(
        "1".to_string(),
        GroupConfig {
            hotkey: "F1".to_string(),
            key_press_duration: Some(10),
            name: Some("test".to_string()),
            mode: "periodic".to_string(),
            hold_keys: None,
            hold_mode: None,
            hold_pattern: None,
            hold_triggers: None,
            mode_data: ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        },
    );
    Config {
        control_hotkeys: ControlHotkeys {
            emergency: "F10".to_string(),
            release_all_holds: "^r".to_string(),
            show_status: "^0".to_string(),
            toggle_all: "^1".to_string(),
            toggle_hold_mode: "^h".to_string(),
        },
        group_settings,
        hold_settings: None,
        last_modified: None,
        version: Some("3.0".to_string()),
    }
}

fn make_test_state() -> Arc<AppState> {
    let config = make_test_config();
    Arc::new(AppState::new(
        config,
        Arc::new(MockIpcSender),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter),
    ))
}

#[test]
fn test_start_recording() {
    let state = make_test_state();
    let result = start_recording(&state, "1", "periodic");
    assert!(result.is_ok());
}

#[test]
fn test_start_recording_group_not_found() {
    let state = make_test_state();
    let result = start_recording(&state, "999", "periodic");
    assert!(matches!(result, Err(AppError::GroupNotFound(_))));
}

#[test]
fn test_stop_recording() {
    let state = make_test_state();
    let result = stop_recording(&state);
    assert!(result.is_ok());
    let recording = result.unwrap();
    assert_eq!(recording.seq, 1);
    assert_eq!(recording.keys, vec!["1", "2"]);
    assert_eq!(recording.mode, "periodic");
}

#[test]
fn test_pause_recording() {
    let state = make_test_state();
    let result = pause_recording(&state);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_resume_recording() {
    let state = make_test_state();
    let result = resume_recording(&state);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_export_import_recording() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("recording.json");
    let path_str = path.to_str().unwrap().to_string();

    let keys = vec!["1".to_string(), "2".to_string()];
    let intervals = vec![50u64, 100];
    export_recording(&path_str, &keys, &intervals, "periodic").unwrap();

    let imported = import_recording(&path_str).unwrap();
    assert_eq!(imported.keys, vec!["1", "2"]);
    assert_eq!(imported.intervals, vec![50, 100]);
    assert_eq!(imported.mode, "periodic");
}

#[test]
fn test_import_recording_not_found() {
    let result = import_recording("/nonexistent/file.json");
    assert!(result.is_err());
}

#[test]
fn test_start_validation() {
    let state = make_test_state();
    let result = start_validation(&state, "1");
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 1);
}

#[test]
fn test_stop_validation() {
    let state = make_test_state();
    let result = stop_validation(&state);
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 1);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test -p asd-application --test recording_service_tests 2>&1 | Select-Object -Last 10`
Expected: All tests FAIL (panics from todo!())

- [ ] **Step 3: Commit**

```bash
git add crates/asd-application/tests/recording_service_tests.rs
git commit -m "test: add RecordingService failing tests (RED phase)"
```

### Task 11: Implement RecordingService functions

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\crates\asd-application\src\recording_service.rs`

- [ ] **Step 1: Replace all todo!() with actual implementations**

```rust
pub fn start_recording(state: &AppState, group_id: &str, mode: &str) -> Result<(), AppError> {
    state
        .get_group(group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.to_string()))?;
    let cmd = IpcCommand::StartRecording {
        group_id: group_id.to_string(),
        mode: mode.to_string(),
    };
    state.send_ipc_command(&cmd)?;
    tracing::info!("开始录制: group={}, mode={}", group_id, mode);
    Ok(())
}

pub fn stop_recording(state: &AppState) -> Result<RecordingResult, AppError> {
    let cmd = IpcCommand::StopRecording;
    let response = state
        .send_ipc_and_wait(&cmd, std::time::Duration::from_secs(5))?;
    tracing::info!("停止录制: seq={}", response.seq);
    let keys = response
        .data
        .as_ref()
        .and_then(|d| d.get("keys"))
        .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
        .unwrap_or_default();
    let mode = response
        .data
        .as_ref()
        .and_then(|d| d.get("mode"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let intervals = response
        .data
        .as_ref()
        .and_then(|d| d.get("intervals"))
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();
    let delays = response
        .data
        .as_ref()
        .and_then(|d| d.get("delays"))
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();
    Ok(RecordingResult {
        seq: response.seq,
        keys,
        mode,
        intervals,
        delays,
    })
}

pub fn pause_recording(state: &AppState) -> Result<u64, AppError> {
    let cmd = IpcCommand::PauseRecording;
    let seq = state.send_ipc_command(&cmd)?;
    tracing::info!("暂停录制: seq={}", seq);
    Ok(seq)
}

pub fn resume_recording(state: &AppState) -> Result<u64, AppError> {
    let cmd = IpcCommand::ResumeRecording;
    let seq = state.send_ipc_command(&cmd)?;
    tracing::info!("恢复录制: seq={}", seq);
    Ok(seq)
}

pub fn export_recording(path: &str, keys: &[String], intervals: &[u64], mode: &str) -> Result<(), AppError> {
    let recording_data = serde_json::json!({
        "keys": keys,
        "intervals": intervals,
        "mode": mode,
        "exportedAt": chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
    });
    let json = serde_json::to_string_pretty(&recording_data)
        .map_err(|e| AppError::Config(format!("序列化录制数据失败: {e}")))?;
    std::fs::write(path, json).map_err(|e| AppError::Config(format!("写入文件失败: {e}")))?;
    tracing::info!("录制结果已导出: {}", path);
    Ok(())
}

pub fn import_recording(path: &str) -> Result<ImportedRecording, AppError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| AppError::Config(format!("读取文件失败: {e}")))?;
    let data: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| AppError::Config(format!("解析录制数据失败: {e}")))?;
    let keys = data
        .get("keys")
        .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
        .unwrap_or_default();
    let intervals = data
        .get("intervals")
        .and_then(|v| serde_json::from_value::<Vec<u64>>(v.clone()).ok())
        .unwrap_or_default();
    let mode = data
        .get("mode")
        .and_then(|v| v.as_str())
        .unwrap_or("periodic")
        .to_string();
    Ok(ImportedRecording {
        keys,
        intervals,
        mode,
    })
}

pub fn start_validation(state: &AppState, group_id: &str) -> Result<u64, AppError> {
    let cmd = IpcCommand::StartValidation {
        group_id: group_id.to_string(),
    };
    let seq = state.send_ipc_command(&cmd)?;
    tracing::info!("启动验证: groupId={}, seq={}", group_id, seq);
    Ok(seq)
}

pub fn stop_validation(state: &AppState) -> Result<u64, AppError> {
    let cmd = IpcCommand::StopValidation;
    let seq = state.send_ipc_command(&cmd)?;
    tracing::info!("停止验证: seq={}", seq);
    Ok(seq)
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test -p asd-application --test recording_service_tests 2>&1 | Select-Object -Last 5`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add crates/asd-application/src/recording_service.rs
git commit -m "feat: implement RecordingService functions (GREEN phase)"
```

### Task 12: Update recording_cmd.rs to delegate to RecordingService

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\commands\recording_cmd.rs`

- [ ] **Step 1: Replace recording_cmd.rs content**

```rust
use asd_application::error::AppError;
use asd_application::recording_service;
use asd_application::recording_service::{ImportedRecording, RecordingResult};
use asd_application::state::AppState;
use std::sync::Arc;

#[tauri::command]
pub async fn start_recording(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
    mode: String,
) -> Result<(), AppError> {
    recording_service::start_recording(&state, &group_id, &mode)
}

#[tauri::command]
pub async fn stop_recording(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<RecordingResult, AppError> {
    recording_service::stop_recording(&state)
}

#[tauri::command]
pub async fn pause_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    recording_service::pause_recording(&state)
}

#[tauri::command]
pub async fn resume_recording(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    recording_service::resume_recording(&state)
}

#[tauri::command]
pub async fn export_recording(
    path: String,
    keys: Vec<String>,
    intervals: Vec<u64>,
    mode: String,
) -> Result<(), AppError> {
    recording_service::export_recording(&path, &keys, &intervals, &mode)
}

#[tauri::command]
pub async fn import_recording(path: String) -> Result<ImportedRecording, AppError> {
    recording_service::import_recording(&path)
}

#[tauri::command]
pub async fn start_validation(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<u64, AppError> {
    recording_service::start_validation(&state, &group_id)
}

#[tauri::command]
pub async fn stop_validation(state: tauri::State<'_, Arc<AppState>>) -> Result<u64, AppError> {
    recording_service::stop_validation(&state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_recording_result_serialization() {
        let result = RecordingResult {
            seq: 42,
            keys: vec!["1".to_string(), "2".to_string()],
            mode: "periodic".to_string(),
            intervals: vec![50, 100],
            delays: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        let decoded: RecordingResult = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.seq, 42);
        assert_eq!(decoded.keys, vec!["1", "2"]);
        assert_eq!(decoded.mode, "periodic");
        assert_eq!(decoded.intervals, vec![50, 100]);
        assert!(decoded.delays.is_empty());
    }

    #[test]
    fn test_recording_result_empty_keys() {
        let result = RecordingResult {
            seq: 1,
            keys: vec![],
            mode: String::new(),
            intervals: vec![],
            delays: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        let decoded: RecordingResult = serde_json::from_str(&json).unwrap();
        assert!(decoded.keys.is_empty());
        assert!(decoded.mode.is_empty());
    }

    #[test]
    fn test_recording_result_skip_empty_intervals_and_delays() {
        let result = RecordingResult {
            seq: 1,
            keys: vec!["Space".to_string()],
            mode: "periodic".to_string(),
            intervals: vec![],
            delays: vec![],
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(!json.contains("intervals"));
        assert!(!json.contains("delays"));
    }
}
```

- [ ] **Step 2: Verify full workspace compilation**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo check --workspace 2>&1 | Select-Object -Last 5`
Expected: Compiled successfully

- [ ] **Step 3: Run all tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test --workspace 2>&1 | Select-String -Pattern "test result"`
Expected: All test suites pass

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/commands/recording_cmd.rs
git commit -m "refactor: delegate recording_cmd to RecordingService"
```

---

## Phase 4: Final Verification

### Task 13: Full workspace verification and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run cargo fmt**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo fmt --all -- --check 2>&1 | Select-Object -Last 5`
Expected: No formatting issues (or run `cargo fmt --all` to fix)

- [ ] **Step 2: Run cargo clippy**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo clippy --workspace --all-targets 2>&1 | Select-Object -Last 10`
Expected: No errors (warnings ok)

- [ ] **Step 3: Run full test suite**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test --workspace 2>&1 | Select-String -Pattern "test result"`
Expected: All test suites pass, total test count increased by ~35

- [ ] **Step 4: Verify test count increase**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri; cargo test --workspace 2>&1 | Select-String -Pattern "running"`
Expected: New test suites visible (backup_service_tests, group_service_tests, recording_service_tests)

- [ ] **Step 5: Final commit if any formatting fixes**

```bash
git add -A
git commit -m "chore: fmt and clippy fixes after service layer extraction"
```
