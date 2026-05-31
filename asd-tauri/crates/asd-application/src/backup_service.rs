use crate::config_repository::ConfigRepository;
use crate::error::AppError;
use crate::state::AppState;
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

    let restored_config =
        ConfigRepository::load_from_path(&backup_path).map_err(AppError::Config)?;
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
        return Err(AppError::Config(format!(
            "备份文件不存在: {backup_filename}"
        )));
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

    let reloaded_config =
        ConfigRepository::load_from_path(&config_path).map_err(AppError::Config)?;
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
