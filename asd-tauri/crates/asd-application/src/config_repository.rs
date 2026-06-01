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
pub struct ConfigRepository;

impl ConfigRepository {
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

        let file_name = path
            .file_name()
            .ok_or_else(|| "无效的文件路径".to_string())?
            .to_string_lossy()
            .to_string();
        let tmp_file_name = format!(".tmp_{file_name}");
        let tmp_path = path.with_file_name(&tmp_file_name);

        fs::write(&tmp_path, &json).map_err(|e| format!("写入临时配置文件失败: {e}"))?;

        if let Err(e) = fs::rename(&tmp_path, path) {
            let _ = fs::remove_file(&tmp_path);
            return Err(format!("重命名配置文件失败: {e}"));
        }

        Ok(())
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
        assert_eq!(loaded.version.as_deref(), Some("3.0"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_from_file_missing_file_falls_back() {
        let path = std::path::PathBuf::from("/nonexistent/path/config.json");
        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
    }

    #[test]
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
}
