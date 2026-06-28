use asd_application::backup_service;
use asd_application::backup_service::{BackupInfo, ConfigDiff};
use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::Config;
use asd_domain::validator::{ConfigValidator, ValidationResult};
use std::sync::Arc;

#[tauri::command]
pub fn get_config(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    state.read_config()
}

#[tauri::command]
pub fn save_config(state: tauri::State<'_, Arc<AppState>>, config: Config) -> Result<(), AppError> {
    // 验证由 save_config_atomic 内部执行，此处不再冗余验证
    state.save_config_atomic(config)?;
    Ok(())
}

#[tauri::command]
pub fn validate_config(config: Config) -> Result<ValidationResult, AppError> {
    let result = ConfigValidator::validate_config(&config);
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
    if filename.trim().is_empty() {
        return Err(AppError::Validation("备份文件名不能为空".to_string()));
    }
    backup_service::restore_backup(&state, &filename)
}

#[tauri::command]
pub fn hot_reload(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    backup_service::hot_reload(&state)
}

#[tauri::command]
pub async fn delete_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    if filename.trim().is_empty() {
        return Err(AppError::Validation("备份文件名不能为空".to_string()));
    }
    backup_service::delete_backup(&state, &filename)
}

#[tauri::command]
pub async fn export_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    if path.trim().is_empty() {
        return Err(AppError::Validation("导出路径不能为空".to_string()));
    }
    backup_service::export_config(&state, &path)
}

#[tauri::command]
pub async fn import_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    if path.trim().is_empty() {
        return Err(AppError::Validation("导入路径不能为空".to_string()));
    }
    backup_service::import_config(&state, &path)
}

#[tauri::command]
pub async fn compare_configs(
    state: tauri::State<'_, Arc<AppState>>,
    backup_filename: String,
) -> Result<ConfigDiff, AppError> {
    if backup_filename.trim().is_empty() {
        return Err(AppError::Validation("备份文件名不能为空".to_string()));
    }
    backup_service::compare_configs(&state, &backup_filename)
}

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;
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
