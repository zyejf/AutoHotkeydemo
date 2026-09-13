use asd_domain::config::Config;
use std::fs;
use std::path::Path;

#[derive(Debug, thiserror::Error)]
pub enum ConfigLoadError {
    #[error("配置文件不存在: {0}")]
    FileNotFound(#[source] std::io::Error),
    #[error("配置文件解析失败: {0}")]
    ParseError(String),
}

/// 配置文件仓库，提供配置的加载、保存和原子写入功能。
///
/// 支持自动剥离 BOM、原子写入（先写临时文件再重命名）和详细的错误类型区分。
///
/// # 错误类型基准（ConfigLoadError）
///
/// `ConfigLoadError` 是本模块的规范错误类型（用于 [`load_from_file_checked`](Self::load_from_file_checked)）。
/// 其余 I/O 方法（`atomic_write` / `read_file_to_string` / `ensure_dir_all` /
/// `list_dir_files` / `delete_file`）目前仍返回 `Result<_, String>`，原因是有较多
/// 跨 crate 调用方（backup_service、recording_service、src-tauri 命令层），
/// 全量统一到 `ConfigLoadError` 需同步改动大量调用点。为避免高回归风险，
/// 本次暂不展开，作为后续错误类型统一的技术债记录。
pub struct ConfigRepository;

impl ConfigRepository {
    /// 原子写入文件：先写临时文件，再重命名到目标路径。
    ///
    /// rename 失败时回退到 copy + remove，避免跨文件系统 rename 限制导致的写入失败。
    pub fn atomic_write(path: &Path, content: &str) -> Result<(), String> {
        let file_name = path
            .file_name()
            .ok_or_else(|| "无效的文件路径".to_string())?
            .to_string_lossy()
            .to_string();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default();
        let tmp_file_name = format!(".tmp_{file_name}_{}_{}", std::process::id(), now.as_nanos());
        let tmp_path = path.with_file_name(&tmp_file_name);

        fs::write(&tmp_path, content).map_err(|e| format!("写入临时文件失败: {e}"))?;

        if let Err(e) = fs::rename(&tmp_path, path) {
            tracing::debug!("rename 失败，尝试 copy+remove fallback: {e}");
            fs::copy(&tmp_path, path).map_err(|e2| {
                let _ = fs::remove_file(&tmp_path);
                format!("重命名和复制均失败: rename={e}, copy={e2}")
            })?;
            if let Err(e) = fs::remove_file(&tmp_path) {
                tracing::warn!(
                    "atomic_write: 临时文件删除失败（可能被锁定）: {} : {e}",
                    tmp_path.display()
                );
            }
        }

        Ok(())
    }
}

fn cleanup_stale_temp_files(dir: &Path) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if name_str.starts_with(".tmp_") {
            if let Ok(metadata) = entry.metadata() {
                if let Ok(modified) = metadata.modified() {
                    if modified.elapsed().unwrap_or_default() > std::time::Duration::from_secs(3600)
                    {
                        let _ = fs::remove_file(entry.path());
                    }
                }
            }
        }
    }
}

impl ConfigRepository {
    /// # Deprecated（M32）
    ///
    /// 此方法在配置文件解析失败或读取失败时返回 `Config::default()`，
    /// 调用方无法区分"默认配置"和"加载失败回退到默认配置"。
    ///
    /// 推荐使用 [`load_from_file_checked`](Self::load_from_file_checked)，
    /// 它返回 `Result<Config, ConfigLoadError>`，提供详细的错误信息。
    #[deprecated(note = "使用 load_from_file_checked 获取错误信息")]
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Config {
        let path = path.as_ref();
        match fs::read_to_string(path) {
            Ok(content) => {
                let cleaned = content.trim_start_matches('\u{feff}');
                match serde_json::from_str(cleaned) {
                    Ok(config) => config,
                    Err(e) => {
                        tracing::error!(
                            "配置文件解析失败: {e}，路径: {}，使用默认配置（建议使用 load_from_file_checked 获取详细错误）",
                            path.display()
                        );
                        Config::default()
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                tracing::info!("配置文件不存在，使用默认配置");
                Config::default()
            }
            Err(e) => {
                tracing::warn!(
                    "配置文件读取失败: {e}，路径: {}，使用默认配置",
                    path.display()
                );
                Config::default()
            }
        }
    }

    pub fn load_from_file_checked<P: AsRef<Path>>(path: P) -> Result<Config, ConfigLoadError> {
        let path = path.as_ref();
        // 注意：cleanup_stale_temp_files 仅在 save_to_path 中调用，
        // 避免在读取路径中引入额外 I/O 延迟
        let content = fs::read_to_string(path).map_err(ConfigLoadError::FileNotFound)?;
        let cleaned = content.trim_start_matches('\u{feff}');
        serde_json::from_str(cleaned).map_err(|e| ConfigLoadError::ParseError(e.to_string()))
    }

    #[deprecated(since = "4.0.0", note = "使用 save_to_path 替代，提供原子写入保证")]
    pub fn save_to_file<P: AsRef<Path>>(config: &Config, path: P) -> Result<(), String> {
        Self::save_to_path(config, path)
    }

    pub fn load_from_path<P: AsRef<Path>>(path: P) -> Result<Config, String> {
        let path = path.as_ref();
        let content = fs::read_to_string(path).map_err(|e| format!("读取配置文件失败: {e}"))?;
        let cleaned = content.trim_start_matches('\u{feff}');
        serde_json::from_str(cleaned).map_err(|e| format!("解析配置文件失败: {e}"))
    }

    pub fn save_to_path<P: AsRef<Path>>(config: &Config, path: P) -> Result<(), String> {
        let path = path.as_ref();
        let json =
            serde_json::to_string_pretty(config).map_err(|e| format!("序列化配置失败: {e}"))?;
        let result = Self::atomic_write(path, &json);
        if let Some(parent) = path.parent() {
            cleanup_stale_temp_files(parent);
        }
        result
    }

    // =================================================================
    // I26: 通用文件 I/O 方法 — 集中封装 std::fs 操作
    //
    // AGENTS.md 规则："std::fs 仅在 asd-application 的 ConfigRepository 中使用"。
    // backup_service 和 recording_service 通过这些方法委托文件 I/O，
    // 避免在各 service 中散落直接的 std::fs 调用。
    // =================================================================

    /// 读取文件内容为字符串，自动剥离 UTF-8 BOM。
    ///
    /// 用于替代 `std::fs::read_to_string`，统一 BOM 处理逻辑。
    pub fn read_file_to_string<P: AsRef<Path>>(path: P) -> Result<String, String> {
        let path = path.as_ref();
        let content = fs::read_to_string(path).map_err(|e| format!("读取文件失败: {e}"))?;
        Ok(content.trim_start_matches('\u{feff}').to_string())
    }

    /// 确保目录存在，不存在则递归创建。
    ///
    /// 用于替代 `std::fs::create_dir_all`。
    pub fn ensure_dir_all<P: AsRef<Path>>(path: P) -> Result<(), String> {
        fs::create_dir_all(path).map_err(|e| format!("创建目录失败: {e}"))
    }

    /// 列出目录中的文件条目。
    ///
    /// 用于替代 `std::fs::read_dir`，返回 `DirEntry` 向量。
    pub fn list_dir_files<P: AsRef<Path>>(path: P) -> Result<Vec<fs::DirEntry>, String> {
        let path = path.as_ref();
        fs::read_dir(path)
            .map_err(|e| format!("读取目录失败: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("读取目录条目失败: {e}"))
    }

    /// 删除文件。
    ///
    /// 用于替代 `std::fs::remove_file`。
    pub fn delete_file<P: AsRef<Path>>(path: P) -> Result<(), String> {
        fs::remove_file(path).map_err(|e| format!("删除文件失败: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;

    fn make_test_config() -> Config {
        let mut group_settings = indexmap::IndexMap::new();
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
    #[allow(deprecated)]
    fn test_load_from_file_valid_file() {
        let dir = std::env::temp_dir().join("asd_app_test_load_from_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("test_config.json");
        let config = Config::default();
        let json = serde_json::to_string_pretty(&config).unwrap();
        std::fs::write(&path, json).unwrap();

        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
        assert_eq!(loaded.version.as_deref(), Some("4.0"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    #[allow(deprecated)]
    fn test_load_from_file_missing_file_falls_back() {
        let path = std::path::PathBuf::from("/nonexistent/path/config.json");
        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
    }

    #[test]
    #[allow(deprecated)]
    fn test_load_from_file_invalid_json_falls_back() {
        let dir = std::env::temp_dir().join("asd_app_test_load_invalid_json");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bad_config.json");
        std::fs::write(&path, "{invalid json!!!}").unwrap();

        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_from_path_valid() {
        let dir = std::env::temp_dir().join("asd_app_test_load_from_path");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let config = make_test_config();
        let json = serde_json::to_string_pretty(&config).unwrap();
        std::fs::write(&path, json).unwrap();

        let loaded = ConfigRepository::load_from_path(&path).unwrap();
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_from_path_missing_file_returns_error() {
        let path = std::path::PathBuf::from("/nonexistent/path/config.json");
        let result = ConfigRepository::load_from_path(&path);
        assert!(result.is_err());
    }

    #[test]
    fn test_load_from_path_invalid_json_returns_error() {
        let dir = std::env::temp_dir().join("asd_app_test_load_from_path_invalid");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bad_config.json");
        std::fs::write(&path, "{invalid json!!!}").unwrap();

        let result = ConfigRepository::load_from_path(&path);
        assert!(result.is_err());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    #[allow(deprecated)]
    fn test_save_to_file_writes_successfully() {
        let dir = std::env::temp_dir().join("asd_app_test_save_to_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let config = Config::default();

        ConfigRepository::save_to_file(&config, &path).expect("save_to_file 应成功");

        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).expect("保存的文件应可解析");
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    #[allow(deprecated)]
    fn test_save_to_file_overwrite_consistency() {
        let dir = std::env::temp_dir().join("asd_app_test_save_overwrite");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("overwrite_config.json");

        let config1 = Config::default();
        ConfigRepository::save_to_file(&config1, &path).unwrap();

        let mut config2 = Config::default();
        config2.control_hotkeys.emergency = "F12".to_string();
        ConfigRepository::save_to_file(&config2, &path).unwrap();

        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).unwrap();
        assert_eq!(loaded.control_hotkeys.emergency, "F12");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    #[allow(deprecated)]
    fn test_save_to_file_invalid_directory_returns_error() {
        let path = std::path::PathBuf::from("/nonexistent/directory/config.json");
        let config = Config::default();
        let result = ConfigRepository::save_to_file(&config, &path);
        assert!(result.is_err());
    }

    #[test]
    fn test_save_to_path_atomic_write() {
        let dir = std::env::temp_dir().join("asd_app_test_save_to_path");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("atomic_config.json");
        let config = make_test_config();

        ConfigRepository::save_to_path(&config, &path).expect("save_to_path 应成功");

        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).expect("保存的文件应可解析");
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_save_to_path_invalid_directory_returns_error() {
        let path = std::path::PathBuf::from("/nonexistent/directory/config.json");
        let config = Config::default();
        let result = ConfigRepository::save_to_path(&config, &path);
        assert!(result.is_err());
    }

    #[test]
    #[allow(deprecated)]
    fn test_load_from_file_bom_stripped() {
        let dir = std::env::temp_dir().join("asd_app_test_bom");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bom_config.json");
        let config = Config::default();
        let json = serde_json::to_string_pretty(&config).unwrap();
        let bom_json = format!("\u{feff}{json}");
        std::fs::write(&path, bom_json.as_bytes()).unwrap();

        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_from_file_checked_valid() {
        let dir = std::env::temp_dir().join("asd_app_test_checked_valid");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("config.json");
        let config = Config::default();
        let json = serde_json::to_string_pretty(&config).unwrap();
        std::fs::write(&path, json).unwrap();

        let result = ConfigRepository::load_from_file_checked(&path);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_from_file_checked_not_found() {
        let path = std::path::PathBuf::from("/nonexistent/path/config.json");
        let result = ConfigRepository::load_from_file_checked(&path);
        assert!(result.is_err());
        match result.unwrap_err() {
            ConfigLoadError::FileNotFound(_) => {}
            other => panic!("Expected FileNotFound, got: {other}"),
        }
    }

    #[test]
    fn test_load_from_file_checked_parse_error() {
        let dir = std::env::temp_dir().join("asd_app_test_checked_parse");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bad_config.json");
        std::fs::write(&path, "{invalid json!!!}").unwrap();

        let result = ConfigRepository::load_from_file_checked(&path);
        assert!(result.is_err());
        match result.unwrap_err() {
            ConfigLoadError::ParseError(msg) => {
                assert!(!msg.is_empty());
            }
            other => panic!("Expected ParseError, got: {other}"),
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    // =================================================================
    // I26: 通用文件 I/O 方法测试 — 委托 std::fs 操作
    // =================================================================

    /// 验证 read_file_to_string 方法能读取有效文件内容。
    #[test]
    fn test_read_file_to_string_valid() {
        let dir = std::env::temp_dir().join("asd_app_test_read_to_string");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("test.txt");
        std::fs::write(&path, "hello world").unwrap();

        let content = ConfigRepository::read_file_to_string(&path).unwrap();
        assert_eq!(content, "hello world");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 验证 read_file_to_string 自动剥离 UTF-8 BOM。
    #[test]
    fn test_read_file_to_string_strips_bom() {
        let dir = std::env::temp_dir().join("asd_app_test_read_bom");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bom.txt");
        std::fs::write(&path, "\u{feff}content with bom").unwrap();

        let content = ConfigRepository::read_file_to_string(&path).unwrap();
        assert_eq!(content, "content with bom");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 验证 read_file_to_string 对不存在的文件返回错误。
    #[test]
    fn test_read_file_to_string_missing_file() {
        let path = std::path::PathBuf::from("/nonexistent/file.txt");
        let result = ConfigRepository::read_file_to_string(&path);
        assert!(result.is_err());
    }

    /// 验证 ensure_dir_all 方法能创建嵌套目录。
    #[test]
    fn test_ensure_dir_all_creates_nested_dirs() {
        let base = std::env::temp_dir().join("asd_app_test_ensure_dir");
        let _ = std::fs::remove_dir_all(&base);
        let nested = base.join("level1").join("level2");

        ConfigRepository::ensure_dir_all(&nested).unwrap();
        assert!(nested.exists());

        let _ = std::fs::remove_dir_all(&base);
    }

    /// 验证 ensure_dir_all 对已存在目录幂等。
    #[test]
    fn test_ensure_dir_all_idempotent() {
        let dir = std::env::temp_dir().join("asd_app_test_ensure_dir_idem");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        // 再次调用不应报错
        ConfigRepository::ensure_dir_all(&dir).unwrap();
        assert!(dir.exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 验证 list_dir_files 方法能列出目录中的 .json 文件。
    #[test]
    fn test_list_dir_files_lists_json() {
        let dir = std::env::temp_dir().join("asd_app_test_list_dir");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("a.json"), "{}").unwrap();
        std::fs::write(dir.join("b.json"), "{}").unwrap();
        std::fs::write(dir.join("c.txt"), "hello").unwrap();

        let entries = ConfigRepository::list_dir_files(&dir).unwrap();
        let json_names: Vec<String> = entries
            .into_iter()
            .filter_map(|e| {
                let name = e.file_name().to_string_lossy().to_string();
                if name.ends_with(".json") {
                    Some(name)
                } else {
                    None
                }
            })
            .collect();
        assert_eq!(json_names.len(), 2);

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 验证 list_dir_files 对不存在的目录返回错误。
    #[test]
    fn test_list_dir_files_missing_dir() {
        let path = std::path::PathBuf::from("/nonexistent/directory");
        let result = ConfigRepository::list_dir_files(&path);
        assert!(result.is_err());
    }

    /// 验证 delete_file 方法能删除文件。
    #[test]
    fn test_delete_file_removes_file() {
        let dir = std::env::temp_dir().join("asd_app_test_delete_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("to_delete.txt");
        std::fs::write(&path, "content").unwrap();
        assert!(path.exists());

        ConfigRepository::delete_file(&path).unwrap();
        assert!(!path.exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// 验证 delete_file 对不存在的文件返回错误。
    #[test]
    fn test_delete_file_missing_file() {
        let path = std::env::temp_dir().join("nonexistent_file_for_delete.txt");
        let result = ConfigRepository::delete_file(&path);
        assert!(result.is_err());
    }
}
