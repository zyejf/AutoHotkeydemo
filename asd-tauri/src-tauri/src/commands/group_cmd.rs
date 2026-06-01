use asd_application::error::AppError;
use asd_application::group_service::{BatchDeleteResult, GroupStatus, GroupSummary};
use asd_application::state::AppState;
use asd_domain::models::SkillGroup;
use std::sync::Arc;

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;

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
    asd_application::group_service::toggle_group(&state, &group_id)
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
    asd_application::group_service::delete_group(&state, &group_id)
}

#[tauri::command]
pub async fn toggle_all(
    state: tauri::State<'_, Arc<AppState>>,
    active: bool,
) -> Result<(), AppError> {
    asd_application::group_service::toggle_all(&state, active)
}

#[tauri::command]
pub async fn batch_toggle_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
    active: bool,
) -> Result<(), AppError> {
    asd_application::group_service::batch_toggle_groups(&state, &group_ids, active)
}

#[tauri::command]
pub async fn batch_delete_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<BatchDeleteResult, AppError> {
    asd_application::group_service::batch_delete_groups(&state, &group_ids)
}

#[tauri::command]
pub fn reorder_groups(
    state: tauri::State<'_, Arc<AppState>>,
    group_ids: Vec<String>,
) -> Result<(), AppError> {
    asd_application::group_service::reorder_groups(&state, &group_ids)
}
