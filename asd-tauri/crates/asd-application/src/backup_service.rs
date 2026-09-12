use crate::config_repository::ConfigRepository;
use crate::error::AppError;
use crate::state::AppState;
use crate::time_format::format_timestamp;
use asd_domain::config::Config;
use asd_domain::validator::ConfigValidator;
use std::path::Path;

pub(crate) fn validate_file_path(path: &str) -> Result<(), AppError> {
    if path.contains('\0') {
        return Err(AppError::Config("路径不能包含空字节".to_string()));
    }
    let p = std::path::Path::new(path);
    if p.is_relative() {
        return Err(AppError::Config("路径必须是绝对路径".to_string()));
    }
    for component in p.components() {
        if matches!(component, std::path::Component::ParentDir) {
            return Err(AppError::Config("路径不能包含父目录引用 (..)".to_string()));
        }
    }
    let path_lower = path.to_lowercase();
    if path_lower.starts_with("\\\\?\\") || path_lower.starts_with("//?/") {
        return Err(AppError::Config("不支持设备路径前缀".to_string()));
    }
    if path_lower.starts_with("\\\\") || path_lower.starts_with("//") {
        return Err(AppError::Config("不支持 UNC 路径或设备路径".to_string()));
    }
    if let Some(ext) = p.extension().and_then(|e| e.to_str()) {
        if ext.to_lowercase() != "json" {
            return Err(AppError::Config("文件扩展名必须是 .json".to_string()));
        }
    } else {
        return Err(AppError::Config("文件必须有 .json 扩展名".to_string()));
    }
    Ok(())
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BackupInfo {
    pub filename: String,
    pub timestamp: String,
    pub size: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ConfigDiff {
    #[serde(rename = "addedGroups")]
    pub added_groups: Vec<String>,
    #[serde(rename = "removedGroups")]
    pub removed_groups: Vec<String>,
    #[serde(rename = "modifiedGroups")]
    pub modified_groups: Vec<String>,
}

fn validate_config_with_context(
    config: &asd_domain::config::Config,
    context: &str,
) -> Result<(), AppError> {
    let validation = ConfigValidator::validate_config(config);
    if !validation.is_valid() {
        let error_msgs: Vec<String> = validation
            .errors
            .iter()
            .map(|e| format!("分组 {} 字段 {}: {}", e.group_id, e.field, e.message))
            .collect();
        return Err(AppError::Validation(format!(
            "{context}配置验证失败: {}",
            error_msgs.join("; ")
        )));
    }
    for warning in &validation.warnings {
        tracing::warn!("{context}配置验证警告: {warning}");
    }
    Ok(())
}

fn validate_path_in_backup_dir(backup_path: &Path, backup_dir: &Path) -> Result<(), AppError> {
    if !backup_dir.exists() {
        return Err(AppError::Config("备份目录不存在".to_string()));
    }
    if !backup_path.exists() {
        return Err(AppError::Config("备份文件不存在".to_string()));
    }
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
        ConfigRepository::ensure_dir_all(&backup_dir)
            .map_err(|e| AppError::Config(format!("创建备份目录失败: {e}")))?;
        return Ok(vec![]);
    }

    let mut backups = Vec::new();
    let entries = ConfigRepository::list_dir_files(&backup_dir)
        .map_err(|e| AppError::Config(format!("读取备份目录失败: {e}")))?;

    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("json") {
            let filename = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("unknown")
                .to_string();
            if !filename.starts_with("backup_") {
                tracing::debug!("跳过非备份文件: {}", filename);
                continue;
            }
            let metadata = entry
                .metadata()
                .map_err(|e| AppError::Config(format!("读取备份元数据失败: {e}")))?;
            let core = filename
                .trim_start_matches("backup_")
                .trim_end_matches(".json");
            let timestamp = if core.len() == 15 && core.chars().nth(8) == Some('_') {
                let date_part = &core[0..8];
                let time_part = &core[9..15];
                format!(
                    "{} {}:{}:{}",
                    date_part,
                    &time_part[0..2],
                    &time_part[2..4],
                    &time_part[4..6]
                )
            } else {
                core.to_string()
            };
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
        ConfigRepository::ensure_dir_all(&backup_dir)
            .map_err(|e| AppError::Config(format!("创建备份目录失败: {e}")))?;
    }

    let timestamp = format_timestamp();
    let backup_filename = format!("backup_{timestamp}.json");
    let backup_path = backup_dir.join(&backup_filename);

    let current_config = state.read_config()?;

    ConfigRepository::save_to_path(&current_config, &backup_path).map_err(AppError::Config)?;

    tracing::info!("已创建备份: {backup_filename}");
    Ok(backup_filename)
}

pub fn restore_backup(state: &AppState, filename: &str) -> Result<(), AppError> {
    if !filename.starts_with("backup_") {
        return Err(AppError::Validation(
            "只能恢复备份文件（文件名须以 backup_ 开头）".to_string(),
        ));
    }

    let backup_dir = get_backup_dir(state)?;

    let backup_path = backup_dir.join(filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {filename}")));
    }

    validate_path_in_backup_dir(&backup_path, &backup_dir)?;

    let restored_config =
        ConfigRepository::load_from_path(&backup_path).map_err(AppError::Config)?;

    validate_config_with_context(&restored_config, "备份")?;

    // 已知设计权衡：create_backup 与 save_config_atomic 之间存在 TOCTOU 窗口，
    // 其他并发操作可能在此期间修改配置。但此窗口极短且恢复操作本身为低频管理操作，
    // 加锁代价过高。auto-backup 仅作为安全网，非关键路径。
    if let Ok(backup_name) = create_backup(state) {
        tracing::info!("恢复前已自动创建备份: {backup_name}");
    } else {
        tracing::warn!("恢复前自动创建备份失败，继续恢复将无法回滚到当前配置");
    }

    state.save_config_atomic(restored_config)?;

    tracing::info!("已恢复备份: {filename}");
    Ok(())
}

pub fn delete_backup(state: &AppState, filename: &str) -> Result<(), AppError> {
    if !filename.starts_with("backup_") {
        return Err(AppError::Validation(
            "只能删除备份文件（文件名须以 backup_ 开头）".to_string(),
        ));
    }

    let backup_dir = get_backup_dir(state)?;

    let backup_path = backup_dir.join(filename);
    if !backup_path.exists() {
        return Err(AppError::Config(format!("备份文件不存在: {filename}")));
    }

    validate_path_in_backup_dir(&backup_path, &backup_dir)?;

    ConfigRepository::delete_file(&backup_path)
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
        if let (Some(curr), Some(backup)) = (
            current_config.group_settings.get(id),
            backup_config.group_settings.get(id),
        ) {
            if curr != backup {
                modified.push(id.clone());
            }
        }
    }

    Ok(ConfigDiff {
        added_groups: added,
        removed_groups: removed,
        modified_groups: modified,
    })
}

/// 返回 `Config` 是有意为之：前端需要新配置来更新 UI 状态。
/// 即使调用方当前不需要返回值，保留返回类型可避免未来需要时再改签名。
pub fn hot_reload(state: &AppState) -> Result<Config, AppError> {
    let config_path = state
        .get_config_path()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    let reloaded_config =
        ConfigRepository::load_from_path(&config_path).map_err(AppError::Config)?;

    validate_config_with_context(&reloaded_config, "热重载")?;

    state.save_config_atomic(reloaded_config.clone())?;

    tracing::info!("热重载配置成功");
    Ok(reloaded_config)
}

pub fn export_config(state: &AppState, path: &str) -> Result<(), AppError> {
    validate_file_path(path)?;

    let config = state.read_config()?;

    ConfigRepository::save_to_path(&config, path).map_err(AppError::Config)?;

    tracing::info!("配置已导出: {}", path);
    Ok(())
}

pub fn import_config(state: &AppState, path: &str) -> Result<(), AppError> {
    validate_file_path(path)?;

    // I26: 通过 ConfigRepository 委托文件 I/O（含 BOM 剥离）
    let cleaned = ConfigRepository::read_file_to_string(path).map_err(AppError::Config)?;

    let imported_config: Config = serde_json::from_str(&cleaned)
        .map_err(|e| AppError::Config(format!("解析配置失败: {e}")))?;

    validate_config_with_context(&imported_config, "导入")?;

    state.save_config_atomic(imported_config)?;

    tracing::info!("配置已导入: {}", path);
    Ok(())
}
