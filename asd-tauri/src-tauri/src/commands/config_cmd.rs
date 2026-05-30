use crate::application::state::{AppError, AppState};
use crate::domain::config::Config;
use crate::domain::validator::{ConfigValidator, ValidationResult};
use std::sync::Arc;

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
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let backup_dir = config_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("backups");

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

#[tauri::command]
pub async fn create_backup(state: tauri::State<'_, Arc<AppState>>) -> Result<String, AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let backup_dir = config_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("backups");

    if !backup_dir.exists() {
        std::fs::create_dir_all(&backup_dir)
            .map_err(|e| AppError::Config(format!("创建备份目录失败: {e}")))?;
    }

    let now = chrono::Local::now();
    let timestamp = now.format("%Y%m%d_%H%M%S").to_string();
    let backup_filename = format!("backup_{timestamp}.json");
    let backup_path = backup_dir.join(&backup_filename);

    let current_config = state.read_config()?;

    current_config
        .save_to_path(&backup_path)
        .map_err(AppError::Config)?;

    tracing::info!("已创建备份: {backup_filename}");
    Ok(backup_filename)
}

#[tauri::command]
pub async fn restore_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let backup_dir = config_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("backups");

    let backup_path = backup_dir.join(&filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {filename}")));
    }

    // 安全检查：确保文件在备份目录内，防止路径遍历攻击
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

    let restored_config = Config::load_from_path(&backup_path).map_err(AppError::Config)?;
    state.save_config_atomic(restored_config)?;

    tracing::info!("已恢复备份: {filename}");
    Ok(())
}

#[tauri::command]
pub fn hot_reload(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let reloaded_config = Config::load_from_path(&config_path).map_err(AppError::Config)?;
    state.save_config_atomic(reloaded_config.clone())?;

    tracing::info!("热重载配置成功");
    Ok(reloaded_config)
}

#[tauri::command]
pub async fn delete_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let backup_dir = config_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("backups");

    let backup_path = backup_dir.join(&filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {filename}")));
    }

    // 安全检查：确保文件在备份目录内，防止路径遍历攻击
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

    std::fs::remove_file(&backup_path)
        .map_err(|e| AppError::Config(format!("删除备份失败: {e}")))?;

    tracing::info!("已删除备份: {filename}");
    Ok(())
}

#[tauri::command]
pub async fn export_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    let config = state.read_config()?;

    let json = serde_json::to_string_pretty(&config)
        .map_err(|e| AppError::Config(format!("序列化配置失败: {e}")))?;

    std::fs::write(&path, json).map_err(|e| AppError::Config(format!("写入文件失败: {e}")))?;

    tracing::info!("配置已导出: {}", path);
    Ok(())
}

#[tauri::command]
pub async fn import_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    let content = std::fs::read_to_string(&path)
        .map_err(|e| AppError::Config(format!("读取文件失败: {e}")))?;

    let imported_config: Config = serde_json::from_str(&content)
        .map_err(|e| AppError::Config(format!("解析配置失败: {e}")))?;

    state.save_config_atomic(imported_config)?;

    tracing::info!("配置已导入: {}", path);
    Ok(())
}

#[tauri::command]
pub async fn compare_configs(
    state: tauri::State<'_, Arc<AppState>>,
    backup_filename: String,
) -> Result<ConfigDiff, AppError> {
    let current_config = state.read_config()?;

    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let backup_dir = config_path
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("backups");

    let backup_path = backup_dir.join(&backup_filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!(
            "备份文件不存在: {backup_filename}"
        )));
    }

    // 安全检查：确保文件在备份目录内，防止路径遍历攻击
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

    let backup_config = Config::load_from_path(&backup_path).map_err(AppError::Config)?;

    let current_ids: std::collections::HashSet<String> =
        current_config.group_settings.keys().cloned().collect();
    let backup_ids: std::collections::HashSet<String> =
        backup_config.group_settings.keys().cloned().collect();

    let added: Vec<String> = current_ids.difference(&backup_ids).cloned().collect();
    let removed: Vec<String> = backup_ids.difference(&current_ids).cloned().collect();

    let mut modified = Vec::new();
    for id in current_ids.intersection(&backup_ids) {
        // 使用 JSON 序列化比较，因为 GroupConfig 未实现 PartialEq
        // intersection 保证两边都存在，unwrap 安全
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
        assert!(result
            .errors
            .iter()
            .any(|e| e.field == "hotkey" && e.message.contains("重复")));
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
