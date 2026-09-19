//! TD-045 豁免：`#[tauri::command]` 的参数保持 owned，不按 clippy 的建议改引用。
//!
//! 2026-09-17 **实测**核实（不是推测），详见
//! `tests/command_contract_tests.rs::tauri_command_args_stay_owned`：
//! 1. `state: tauri::State<'_, Arc<AppState>>` —— Tauri 按类型从 DI 容器提取，
//!    写成 `&State` 就提取不到，必须按值。
//! 2. `config: Config` —— serde 没有 `&Config` 的 `Deserialize` 实现，改了编译不过，
//!    不是「懒得改」。
//!
//! ⚠️ 反过来也别写成「改成 &str 会运行时炸」——那是错的：Tauri 走
//! `&'de serde_json::Value` 的 Deserializer，实测**能**借出 `&str`。
//! 这里不改的真正理由是「改对外 IPC 契约，而 E2E 覆盖不全（TD-016）」。
//!
//! 复审触发条件：E2E 全绿、能验证契约变更之后。
#![allow(clippy::needless_pass_by_value)]

use asd_application::backup_service;
use asd_application::backup_service::{BackupInfo, ConfigDiff};
use asd_application::config_repository::ConfigLoadFailure;
use asd_application::error::AppError;
use asd_application::state::AppState;
use asd_domain::config::Config;
use asd_domain::validator::{ConfigValidator, ValidationResult};
use std::sync::Arc;

// =================================================================
// 核心逻辑辅助函数（可测试性重构）
// =================================================================
// 设计说明：
// 由于 `tauri::State` 在 Tauri 2.11.2 中无公共构造函数，无法在单元测试中
// 直接构造 `tauri::State<'_, Arc<AppState>>` 调用 command 函数。为使核心逻辑
// 可测试，将其提取到接收 `&AppState` 的同步辅助函数。command 函数仅做一行委托。
// 这是不改变外部行为的最小可测试性重构。

/// `get_config` 的核心逻辑。
///
/// # Errors
///
/// 当前实现**不会失败**：取读锁克隆一份 `Config`，恒定 `Ok`。
/// `Result` 只是为 API 稳定保留的返回类型 —— 别把「返回 `Result`」当成
/// 「这里可能出错」（`clippy::unnecessary_wraps` 默认不查导出函数，报不出来）。
pub fn get_config_impl(state: &AppState) -> Result<Config, AppError> {
    state.read_config()
}

/// `save_config` 的核心逻辑。
///
/// # Errors
///
/// - `Validation`：`ConfigValidator` 校验不通过 —— 先校验后写，**内存与磁盘都不变**。
/// - `Config`：写盘失败。此时内存已尽力回滚，但**回滚是有条件的**
///   （只有 `version == old_version + 1` 才回滚；并发保存时可能留下
///   「内存新、磁盘旧」的不一致，返回值仍是 `Err`）。
///
/// ⚠️ 两条反直觉语义：① `config_path` 未设置时**不写盘也不报错**，只记 `warn`
/// 返回 `Ok`，配置仅存在于内存、进程退出即丢；② 成功后的 AHK 同步是
/// fire-and-forget，`Ok(())` 不代表 AHK 侧已生效。
pub fn save_config_impl(state: &AppState, config: Config) -> Result<(), AppError> {
    // 验证由 save_config_atomic 内部执行，此处不再冗余验证
    state.save_config_atomic(config)?;
    Ok(())
}

/// `validate_config` 的核心逻辑。
///
/// # Errors
///
/// 当前实现**不会失败**。⚠️ **这不是「配置没问题」的意思** —— 校验器把问题写进
/// `ValidationResult` 而不是返回 `Err`，所以恒定 `Ok`。
/// 调用方必须看 `ValidationResult::is_valid()`，只看 `Ok`/`Err` 等于没校验。
pub fn validate_config_impl(config: &Config) -> Result<ValidationResult, AppError> {
    let result = ConfigValidator::validate_config(config);
    Ok(result)
}

/// `list_backups` 的核心逻辑。
///
/// # Errors
///
/// `Config`：配置路径未设置、备份目录创建或读取失败、备份文件元数据读取失败。
/// ⚠️ **备份目录不存在不算错误** —— 会自动创建并返回空列表。所以拿到
/// `Ok(vec![])` 时无法区分「从来没有备份」和「目录被删了刚重建」。
pub fn list_backups_impl(state: &AppState) -> Result<Vec<BackupInfo>, AppError> {
    backup_service::list_backups(state)
}

/// `create_backup` 的核心逻辑。
///
/// # Errors
///
/// `Config`：配置路径未设置、备份目录创建失败、备份文件写入失败。
/// 返回 `Ok` 时值是备份文件名（`backup_<时间戳>.json`），调用方拿它去
/// 恢复 / 删除 / 对比。
pub fn create_backup_impl(state: &AppState) -> Result<String, AppError> {
    backup_service::create_backup(state)
}

/// `restore_backup` 的核心逻辑。
///
/// # Errors
///
/// - `Validation`：文件名为空或全空白、文件名不以 `backup_` 开头
///   （防误删任意文件）、恢复出的配置校验不通过。
/// - `Config`：配置路径未设置、备份文件不存在、备份读取或写回失败。
///
/// ⚠️ **恢复前会自动先备份当前配置，但那个自动备份失败不算失败**（只记 `warn`
/// 后继续）。代价是：恢复后想反悔，可能已经拿不到恢复前的那份配置了。
pub fn restore_backup_impl(state: &AppState, filename: &str) -> Result<(), AppError> {
    if filename.trim().is_empty() {
        return Err(AppError::Validation("备份文件名不能为空".to_string()));
    }
    backup_service::restore_backup(state, filename)
}

/// `hot_reload` 的核心逻辑。
///
/// # Errors
///
/// - `Config`：配置路径未设置、读取失败、写回失败。
/// - `Validation`：重载出的配置校验不通过 —— 此时**内存中的配置未被改动**
///   （磁盘上那份坏配置依然存在，不会自动修好）。
///
/// 返回重载后的 `Config`，前端拿它刷新 UI。
pub fn hot_reload_impl(state: &AppState) -> Result<Config, AppError> {
    backup_service::hot_reload(state)
}

/// `delete_backup` 的核心逻辑。
///
/// # Errors
///
/// - `Validation`：文件名为空或全空白、文件名不以 `backup_` 开头。
/// - `Config`：配置路径未设置、备份文件不存在、路径解析失败、
///   文件不在备份目录内（**防路径逃逸**）、删除失败。
///
/// ⚠️ 删除**不可撤销**，且没有回收站 —— 前端必须二次确认。
pub fn delete_backup_impl(state: &AppState, filename: &str) -> Result<(), AppError> {
    if filename.trim().is_empty() {
        return Err(AppError::Validation("备份文件名不能为空".to_string()));
    }
    backup_service::delete_backup(state, filename)
}

/// `export_config` 的核心逻辑。
///
/// # Errors
///
/// - `Validation`：导出路径为空或全空白。
/// - `Config`：路径非法（含空字节 / **是相对路径** / 含 `..` / UNC 或设备路径 /
///   扩展名不是 `.json`），或目标文件写入失败。
///
/// ⚠️ 路径白名单很严：相对路径也被拒。前端传进来的如果是用户从文件对话框选的，
/// 一般是绝对路径没问题；手工拼的路径很可能吃 `Config` 错误。
pub fn export_config_impl(state: &AppState, path: &str) -> Result<(), AppError> {
    if path.trim().is_empty() {
        return Err(AppError::Validation("导出路径不能为空".to_string()));
    }
    backup_service::export_config(state, path)
}

/// `import_config` 的核心逻辑。
///
/// # Errors
///
/// - `Validation`：导入路径为空或全空白；导入的配置校验不通过 ——
///   此时**既不写盘、内存配置也不变**，当前配置安然无恙。
/// - `Config`：路径非法、文件读取失败、JSON 解析失败、写回失败。
///
/// 导入是**整体替换**当前配置，不是合并。读取时会剥离 UTF-8 BOM。
pub fn import_config_impl(state: &AppState, path: &str) -> Result<(), AppError> {
    if path.trim().is_empty() {
        return Err(AppError::Validation("导入路径不能为空".to_string()));
    }
    backup_service::import_config(state, path)
}

/// `compare_configs` 的核心逻辑。
///
/// # Errors
///
/// - `Validation`：`backup_filename` 为空或全空白。
/// - `Config`：配置路径未设置、备份文件不存在、路径解析失败或不在备份目录内
///   （防路径逃逸）、备份读取失败。
///
/// ⚠️ 只按**分组 id** 做集合比较，**不校验配置内容**，所以永远不会因为
/// 「配置有问题」而返回 `Validation`。想校验请用 `validate_config`。
pub fn compare_configs_impl(
    state: &AppState,
    backup_filename: &str,
) -> Result<ConfigDiff, AppError> {
    if backup_filename.trim().is_empty() {
        return Err(AppError::Validation("备份文件名不能为空".to_string()));
    }
    backup_service::compare_configs(state, backup_filename)
}

// =================================================================
// Tauri Command 函数
// =================================================================

/// 读取当前内存中的配置。
///
/// # Errors
///
/// 见 [`get_config_impl`]：当前实现不会失败。
#[tauri::command]
pub fn get_config(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    get_config_impl(&state)
}

/// 取「启动时配置文件加载失败」的记录；`None` 表示配置正常（含首次启动）。
///
/// B6 / TD-084：加载失败时进程仍会启动、界面一切正常，但用户看到的是「我的分组没了」。
/// 前端必须在启动后主动拉一次并明确告知，**不能**只在日志里留一行。
///
/// # Errors
///
/// 当前实现不会失败。
#[tauri::command]
pub fn get_config_load_failure(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<Option<ConfigLoadFailure>, AppError> {
    Ok(state.config_load_failure())
}

/// 整体保存配置（先校验再写盘）。
///
/// # Errors
///
/// 见 [`save_config_impl`]：`Validation`（校验不通过，内存与磁盘都不变）或
/// `Config`（写盘失败）。⚠️ 注意那里的两条反直觉语义：未设置配置路径时
/// 「不写盘也不报错」，且 `Ok` 不代表 AHK 侧已生效。
#[tauri::command]
pub fn save_config(state: tauri::State<'_, Arc<AppState>>, config: Config) -> Result<(), AppError> {
    save_config_impl(&state, config)
}

/// 校验一份配置（**不保存**）。
///
/// # Errors
///
/// 见 [`validate_config_impl`]：当前实现不会失败。⚠️ `Ok` **不代表配置有效** —
/// 校验结果在 `ValidationResult::is_valid()` 里，不看它等于没校验。
#[tauri::command]
pub fn validate_config(config: Config) -> Result<ValidationResult, AppError> {
    validate_config_impl(&config)
}

/// 列出所有备份（按时间戳倒序）。
///
/// # Errors
///
/// 见 [`list_backups_impl`]：`Config`。备份目录不存在**不报错**，会返回空列表。
#[tauri::command]
pub async fn list_backups(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<Vec<BackupInfo>, AppError> {
    list_backups_impl(&state)
}

/// 把当前配置做成一份备份，返回备份文件名。
///
/// # Errors
///
/// 见 [`create_backup_impl`]：`Config`（路径未设置 / 目录创建失败 / 写入失败）。
#[tauri::command]
pub async fn create_backup(state: tauri::State<'_, Arc<AppState>>) -> Result<String, AppError> {
    create_backup_impl(&state)
}

/// 用指定备份覆盖当前配置。
///
/// # Errors
///
/// 见 [`restore_backup_impl`]：`Validation`（文件名为空 / 不以 `backup_` 开头 /
/// 恢复出的配置校验不通过）或 `Config`。
/// ⚠️ 恢复前的自动备份失败不算失败，反悔可能拿不到旧配置。
#[tauri::command]
pub async fn restore_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    restore_backup_impl(&state, &filename)
}

/// 从磁盘重新加载配置文件并替换内存中的配置。
///
/// # Errors
///
/// 见 [`hot_reload_impl`]：`Config` 或 `Validation`（重载出的配置不合法，
/// 此时内存未被改动）。
#[tauri::command]
pub fn hot_reload(state: tauri::State<'_, Arc<AppState>>) -> Result<Config, AppError> {
    hot_reload_impl(&state)
}

/// 删除指定备份文件（不可撤销）。
///
/// # Errors
///
/// 见 [`delete_backup_impl`]：`Validation` 或 `Config`。前端必须二次确认。
#[tauri::command]
pub async fn delete_backup(
    state: tauri::State<'_, Arc<AppState>>,
    filename: String,
) -> Result<(), AppError> {
    delete_backup_impl(&state, &filename)
}

/// 把当前配置导出到指定路径。
///
/// # Errors
///
/// 见 [`export_config_impl`]：`Validation`（路径为空）或 `Config`
/// （路径非法 —— 相对路径也会被拒 —— 或写入失败）。
#[tauri::command]
pub async fn export_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    export_config_impl(&state, &path)
}

/// 从指定路径导入配置，**整体替换**当前配置。
///
/// # Errors
///
/// 见 [`import_config_impl`]：`Validation`（路径为空 / 导入的配置不合法 ——
/// 此时不写盘、内存也不变）或 `Config`。
#[tauri::command]
pub async fn import_config(
    state: tauri::State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), AppError> {
    import_config_impl(&state, &path)
}

/// 对比当前配置与指定备份（只按分组 id 做集合比较）。
///
/// # Errors
///
/// 见 [`compare_configs_impl`]：`Validation`（文件名为空）或 `Config`。
/// 本函数**不校验配置内容**。
#[tauri::command]
pub async fn compare_configs(
    state: tauri::State<'_, Arc<AppState>>,
    backup_filename: String,
) -> Result<ConfigDiff, AppError> {
    compare_configs_impl(&state, &backup_filename)
}

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;
    use asd_test_harness::{make_test_config, make_test_state, make_test_state_with_path};
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

    // ----------------------------------------------------------------
    // 原有测试（ConfigValidator 和 AppError 验证）
    // ----------------------------------------------------------------

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
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["kind"], "Validation");
        assert_eq!(parsed["message"], "测试");
    }

    // ----------------------------------------------------------------
    // _impl 函数测试 — 正常路径 + 错误路径
    // ----------------------------------------------------------------

    // --- get_config_impl ---

    /// 验证 `get_config_impl` 返回包含正确分组数量的配置。
    #[test]
    fn test_get_config_impl_success() {
        let state = make_test_state();
        let result = get_config_impl(&state);
        assert!(result.is_ok(), "读取配置应成功: {:?}", result.err());
        let config = result.unwrap();
        assert_eq!(config.group_settings.len(), 2, "测试配置应包含 2 个分组");
    }

    /// 验证 `get_config_impl` 反映 `save_config_impl` 后的配置变更。
    #[test]
    fn test_get_config_impl_reflects_saved_config() {
        let (state, _dir) = make_test_state_with_path();
        let mut config = make_test_config();
        config.control_hotkeys.emergency = "F12".to_string();
        save_config_impl(&state, config).unwrap();

        let result = get_config_impl(&state);
        assert!(result.is_ok());
        assert_eq!(
            result.unwrap().control_hotkeys.emergency,
            "F12",
            "get_config 应反映 save_config 后的变更"
        );
    }

    // --- save_config_impl ---

    /// 验证 `save_config_impl` 成功保存有效配置。
    #[test]
    fn test_save_config_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        let config = make_test_config();
        let result = save_config_impl(&state, config);
        assert!(result.is_ok(), "保存有效配置应成功: {:?}", result.err());
    }

    /// 验证 `save_config_impl` 拒绝无效配置（空热键）。
    #[test]
    fn test_save_config_impl_invalid_config() {
        let state = make_test_state();
        let mut config = make_test_config();
        config.group_settings.get_mut("1").unwrap().hotkey = String::new();
        let result = save_config_impl(&state, config);
        assert!(result.is_err(), "无效配置应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- validate_config_impl ---

    /// 验证 `validate_config_impl` 对有效配置返回 `is_valid()` == true。
    #[test]
    fn test_validate_config_impl_valid() {
        let config = make_test_config();
        let result = validate_config_impl(&config);
        assert!(result.is_ok(), "验证函数应返回 Ok: {:?}", result.err());
        assert!(result.unwrap().is_valid(), "有效配置应通过验证");
    }

    /// 验证 `validate_config_impl` 对无效配置返回 `is_valid()` == false。
    #[test]
    fn test_validate_config_impl_invalid() {
        let mut config = make_test_config();
        config.group_settings.get_mut("1").unwrap().hotkey = String::new();
        let result = validate_config_impl(&config);
        assert!(result.is_ok(), "验证函数本身应返回 Ok");
        assert!(!result.unwrap().is_valid(), "无效配置不应通过验证");
    }

    // --- list_backups_impl ---

    /// 验证 `list_backups_impl` 在无备份时返回空列表。
    #[test]
    fn test_list_backups_impl_empty() {
        let (state, _dir) = make_test_state_with_path();
        let result = list_backups_impl(&state);
        assert!(result.is_ok(), "列出备份应成功: {:?}", result.err());
        assert!(result.unwrap().is_empty(), "无备份时应返回空列表");
    }

    /// 验证 `list_backups_impl` 在未设置 `config_path` 时返回错误。
    #[test]
    fn test_list_backups_impl_no_config_path() {
        let state = make_test_state();
        let result = list_backups_impl(&state);
        assert!(result.is_err(), "无 config_path 应返回错误");
        match result.unwrap_err() {
            AppError::Config(_) => {}
            other => panic!("期望 Config 错误，实际: {other:?}"),
        }
    }

    // --- create_backup_impl ---

    /// 验证 `create_backup_impl` 成功创建备份并返回文件名。
    #[test]
    fn test_create_backup_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        let result = create_backup_impl(&state);
        assert!(result.is_ok(), "创建备份应成功: {:?}", result.err());
        let filename = result.unwrap();
        assert!(
            filename.starts_with("backup_"),
            "备份文件名应以 backup_ 开头"
        );
    }

    /// 验证 `create_backup_impl` 在未设置 `config_path` 时返回错误。
    #[test]
    fn test_create_backup_impl_no_config_path() {
        let state = make_test_state();
        let result = create_backup_impl(&state);
        assert!(result.is_err(), "无 config_path 应返回错误");
    }

    // --- restore_backup_impl ---

    /// 验证 `restore_backup_impl` 成功恢复已有备份。
    #[test]
    fn test_restore_backup_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        // 先创建备份
        let backup_filename = create_backup_impl(&state).unwrap();
        // 恢复备份
        let result = restore_backup_impl(&state, &backup_filename);
        assert!(result.is_ok(), "恢复备份应成功: {:?}", result.err());
    }

    /// 验证 `restore_backup_impl` 拒绝空文件名。
    #[test]
    fn test_restore_backup_impl_empty_filename() {
        let state = make_test_state();
        let result = restore_backup_impl(&state, "");
        assert!(result.is_err(), "空文件名应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- hot_reload_impl ---

    /// 验证 `hot_reload_impl` 成功从磁盘重新加载配置。
    #[test]
    fn test_hot_reload_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        // 先保存配置到文件
        let config = make_test_config();
        save_config_impl(&state, config).unwrap();
        // 热重载
        let result = hot_reload_impl(&state);
        assert!(result.is_ok(), "热重载应成功: {:?}", result.err());
    }

    /// 验证 `hot_reload_impl` 在未设置 `config_path` 时返回错误。
    #[test]
    fn test_hot_reload_impl_no_config_path() {
        let state = make_test_state();
        let result = hot_reload_impl(&state);
        assert!(result.is_err(), "无 config_path 应返回错误");
    }

    // --- delete_backup_impl ---

    /// 验证 `delete_backup_impl` 成功删除已有备份。
    #[test]
    fn test_delete_backup_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        let backup_filename = create_backup_impl(&state).unwrap();
        let result = delete_backup_impl(&state, &backup_filename);
        assert!(result.is_ok(), "删除备份应成功: {:?}", result.err());
    }

    /// 验证 `delete_backup_impl` 拒绝空文件名。
    #[test]
    fn test_delete_backup_impl_empty_filename() {
        let state = make_test_state();
        let result = delete_backup_impl(&state, "");
        assert!(result.is_err(), "空文件名应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- export_config_impl ---

    /// 验证 `export_config_impl` 成功导出配置到文件。
    #[test]
    fn test_export_config_impl_success() {
        let (state, dir) = make_test_state_with_path();
        let export_path = dir.path().join("exported.json");
        let result = export_config_impl(&state, export_path.to_str().unwrap());
        assert!(result.is_ok(), "导出配置应成功: {:?}", result.err());
        assert!(export_path.exists(), "导出文件应存在");
    }

    /// 验证 `export_config_impl` 拒绝空路径。
    #[test]
    fn test_export_config_impl_empty_path() {
        let state = make_test_state();
        let result = export_config_impl(&state, "");
        assert!(result.is_err(), "空路径应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- import_config_impl ---

    /// 验证 `import_config_impl` 成功从文件导入配置。
    #[test]
    fn test_import_config_impl_success() {
        let (state, dir) = make_test_state_with_path();
        let export_path = dir.path().join("importable.json");
        // 先导出配置
        export_config_impl(&state, export_path.to_str().unwrap()).unwrap();
        // 再导入
        let result = import_config_impl(&state, export_path.to_str().unwrap());
        assert!(result.is_ok(), "导入配置应成功: {:?}", result.err());
    }

    /// 验证 `import_config_impl` 拒绝空路径。
    #[test]
    fn test_import_config_impl_empty_path() {
        let state = make_test_state();
        let result = import_config_impl(&state, "");
        assert!(result.is_err(), "空路径应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }

    // --- compare_configs_impl ---

    /// 验证 `compare_configs_impl` 成功比较当前配置与备份。
    #[test]
    fn test_compare_configs_impl_success() {
        let (state, _dir) = make_test_state_with_path();
        // 先创建备份（当前配置与备份相同）
        let backup_filename = create_backup_impl(&state).unwrap();
        // 比较配置
        let result = compare_configs_impl(&state, &backup_filename);
        assert!(result.is_ok(), "比较配置应成功: {:?}", result.err());
        let diff = result.unwrap();
        assert!(diff.added_groups.is_empty(), "无新增分组");
        assert!(diff.removed_groups.is_empty(), "无删除分组");
        assert!(diff.modified_groups.is_empty(), "无修改分组");
    }

    /// 验证 `compare_configs_impl` 拒绝空文件名。
    #[test]
    fn test_compare_configs_impl_empty_filename() {
        let state = make_test_state();
        let result = compare_configs_impl(&state, "");
        assert!(result.is_err(), "空文件名应返回错误");
        match result.unwrap_err() {
            AppError::Validation(_) => {}
            other => panic!("期望 Validation 错误，实际: {other:?}"),
        }
    }
}
