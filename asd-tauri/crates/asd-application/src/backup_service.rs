//! 配置备份与恢复：列出 / 创建 / 恢复 / 删除备份，导入导出，热重载。
//!
//! ## 错误处理的两条共同事实（写在这里，避免在每个函数下重复）
//!
//! · `AppState::read_config` 的 `Result` **恒定返回 `Ok`**，它只是为 API 稳定保留了
//!   返回类型，调用方不必为它写错误处理。⚠️ `clippy::unnecessary_wraps` 报不出来：
//!   该 lint 默认**不检查导出函数**（`avoid-breaking-exported-api`）。
//! · `AppState::save_config_atomic` 在**写盘失败时会先回滚内存状态**再返回错误，
//!   所以调用方拿到 `Err` 时，内存里的配置仍是旧值（不会「内存改了、磁盘没改」）。
//!
//! 除 `Validation`（配置内容校验不通过）外，本模块的错误基本都落在 `AppError::Config` ——
//! 它们对调用方而言都属「操作没做成、状态未变」，没有各自区分处理的必要。

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

/// 列出备份目录下的所有备份，按时间戳倒序（最新在前）。
///
/// # Errors
/// `Config`：配置路径未设置、备份目录创建或读取失败、备份文件元数据读取失败。
/// ⚠️ 备份目录不存在时**不报错** —— 会自动创建并返回空列表。
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

/// 把当前配置快照写入备份目录，返回备份文件名。
///
/// # Errors
/// `Config`：配置路径未设置、备份目录创建失败、备份文件写入失败。
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

/// 用指定备份覆盖当前配置。
///
/// # Errors
/// - `Validation`：文件名不以 `backup_` 开头；恢复出的配置校验不通过。
/// - `Config`：配置路径未设置、备份文件不存在、备份读取或写回失败。
///
/// ⚠️ **恢复前会自动先备份当前配置，但那个自动备份失败不算失败**（只记 `warn` 后继续）。
/// 代价是：若恢复后想反悔，可能已经拿不到恢复前的那份配置了。
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

/// 删除指定备份文件。
///
/// # Errors
/// - `Validation`：文件名不以 `backup_` 开头。
/// - `Config`：配置路径未设置、备份文件不存在、路径解析失败、
///   文件不在备份目录内（防路径逃逸）、删除失败。
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

/// 对比当前配置与指定备份，返回分组的新增 / 删除 / 变更清单。
///
/// # Errors
/// `Config`：配置路径未设置、备份文件不存在、路径解析失败或不在备份目录内、备份读取失败。
/// 本函数只按分组 id 做集合比较，**不校验配置内容**，因此不会返回 `Validation`。
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

/// 从磁盘重新加载配置并替换内存中的配置，返回新配置。
///
/// 返回 `Config` 是有意为之：前端需要新配置来更新 UI 状态。
/// 即使调用方当前不需要返回值，保留返回类型可避免未来需要时再改签名。
///
/// # Errors
/// - `Config`：配置路径未设置、读取失败、写回失败。
/// - `Validation`：重载出的配置校验不通过 —— 此时**内存中的配置未被改动**。
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

/// 把当前配置导出到指定路径。
///
/// # Errors
/// `Config`：路径非法（含空字节 / 是相对路径 / 含 `..` / UNC 或设备路径 /
/// 扩展名不是 `.json`），或目标文件写入失败。
pub fn export_config(state: &AppState, path: &str) -> Result<(), AppError> {
    validate_file_path(path)?;

    let config = state.read_config()?;

    ConfigRepository::save_to_path(&config, path).map_err(AppError::Config)?;

    tracing::info!("配置已导出: {}", path);
    Ok(())
}

/// 从指定路径导入配置并替换当前配置（含 BOM 剥离）。
///
/// # Errors
/// - `Config`：路径非法、文件读取失败、JSON 解析失败、写回失败。
/// - `Validation`：导入的配置校验不通过 —— 此时**不会写盘、内存配置也不变**。
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
