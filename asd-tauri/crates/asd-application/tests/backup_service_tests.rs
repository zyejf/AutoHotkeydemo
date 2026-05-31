mod common;

use asd_application::backup_service::*;
use common::*;

#[test]
fn test_list_backups_empty_dir() {
    let (state, _dir) = make_test_state_with_path();
    let result = list_backups(&state);
    assert!(result.is_ok(), "空备份目录应返回 Ok: {:?}", result);
    assert!(result.unwrap().is_empty(), "空备份目录应返回空列表");
}

#[test]
fn test_list_backups_no_config_path() {
    let state = make_test_state();
    let result = list_backups(&state);
    assert!(result.is_err(), "无配置路径应返回错误");
}

#[test]
fn test_create_backup() {
    let (state, _dir) = make_test_state_with_path();
    let result = create_backup(&state);
    assert!(result.is_ok(), "创建备份应成功: {:?}", result);
    let filename = result.unwrap();
    assert!(
        filename.starts_with("backup_"),
        "备份文件名应以 backup_ 开头: {filename}"
    );
    assert!(
        filename.ends_with(".json"),
        "备份文件名应以 .json 结尾: {filename}"
    );
}

#[test]
fn test_create_backup_no_config_path() {
    let state = make_test_state();
    let result = create_backup(&state);
    assert!(result.is_err(), "无配置路径应返回错误");
}

#[test]
fn test_restore_backup_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = restore_backup(&state, "nonexistent.json");
    assert!(result.is_err(), "不存在的备份应返回错误");
}

#[test]
fn test_restore_backup_path_traversal() {
    let (state, _dir) = make_test_state_with_path();
    let result = restore_backup(&state, "../../../etc/passwd");
    assert!(result.is_err(), "路径遍历攻击应返回错误");
}

#[test]
fn test_delete_backup_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = delete_backup(&state, "nonexistent.json");
    assert!(result.is_err(), "不存在的备份应返回错误");
}

#[test]
fn test_hot_reload_no_config_path() {
    let state = make_test_state();
    let result = hot_reload(&state);
    assert!(result.is_err(), "无配置路径应返回错误");
}

#[test]
fn test_export_config() {
    let dir = tempfile::tempdir().unwrap();
    let export_path = dir.path().join("exported_config.json");
    let (state, _config_dir) = make_test_state_with_path();
    let result = export_config(&state, export_path.to_str().unwrap());
    assert!(result.is_ok(), "导出配置应成功: {:?}", result);
    assert!(export_path.exists(), "导出文件应存在");
    let content = std::fs::read_to_string(&export_path).unwrap();
    let parsed: asd_domain::config::Config = serde_json::from_str(&content).unwrap();
    assert_eq!(parsed.control_hotkeys.emergency, "F10");
}

#[test]
fn test_import_config_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = import_config(&state, "/nonexistent/path/config.json");
    assert!(result.is_err(), "导入不存在的文件应返回错误");
}

#[test]
fn test_compare_configs_not_found() {
    let (state, _dir) = make_test_state_with_path();
    let result = compare_configs(&state, "nonexistent.json");
    assert!(result.is_err(), "比较不存在的备份应返回错误");
}

#[test]
fn test_create_and_list_backups() {
    let (state, _dir) = make_test_state_with_path();
    let filename = create_backup(&state).unwrap();
    let backups = list_backups(&state).unwrap();
    assert!(!backups.is_empty(), "创建备份后列表不应为空");
    assert!(
        backups.iter().any(|b| b.filename == filename),
        "列表中应包含刚创建的备份"
    );
}

#[test]
fn test_create_and_restore_backup() {
    let (state, _dir) = make_test_state_with_path();
    let filename = create_backup(&state).unwrap();
    let result = restore_backup(&state, &filename);
    assert!(result.is_ok(), "恢复备份应成功: {:?}", result);
}

#[test]
fn test_create_and_delete_backup() {
    let (state, _dir) = make_test_state_with_path();
    let filename = create_backup(&state).unwrap();
    let result = delete_backup(&state, &filename);
    assert!(result.is_ok(), "删除备份应成功: {:?}", result);
    let backups = list_backups(&state).unwrap();
    assert!(
        backups.iter().all(|b| b.filename != filename),
        "删除后列表中不应包含该备份"
    );
}

#[test]
fn test_create_and_compare_configs() {
    let (state, _dir) = make_test_state_with_path();
    let filename = create_backup(&state).unwrap();
    let result = compare_configs(&state, &filename);
    assert!(result.is_ok(), "比较配置应成功: {:?}", result);
    let diff = result.unwrap();
    assert!(diff.added_groups.is_empty(), "未修改时不应有新增组");
    assert!(diff.removed_groups.is_empty(), "未修改时不应有删除组");
    assert!(diff.modified_groups.is_empty(), "未修改时不应有修改组");
}
