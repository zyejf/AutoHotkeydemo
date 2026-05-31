use asd_domain::models::SkillGroup;
use asd_domain::traits::IpcSender;
use asd_ipc_protocol::IpcCommand;
use std::collections::HashMap;
use std::sync::Arc;

#[deprecated(
    since = "3.1.0",
    note = "SkillManager 与 AppState 职责重叠，请使用 AppState 的方法替代。activate/deactivate → set_group_active, register_hotkey/unregister_hotkey → AppState::register_hotkey/unregister_hotkey, build_toggle_command → group_service::build_toggle_command"
)]
pub struct SkillManager {
    groups: HashMap<String, SkillGroup>,
    hotkey_registry: HashMap<String, String>,
    #[allow(dead_code)]
    ipc_sender: Arc<dyn IpcSender>,
}

#[allow(deprecated)]
impl SkillManager {
    pub fn new(groups: HashMap<String, SkillGroup>, ipc_sender: Arc<dyn IpcSender>) -> Self {
        Self {
            groups,
            hotkey_registry: HashMap::new(),
            ipc_sender,
        }
    }

    pub fn toggle(&mut self, group_id: &str) -> Result<bool, String> {
        let group = self
            .groups
            .get(group_id)
            .ok_or_else(|| format!("分组不存在: {group_id}"))?;
        let new_active = !group.active;
        if new_active {
            self.activate(group_id)?;
        } else {
            self.deactivate(group_id)?;
        }
        Ok(new_active)
    }

    pub fn activate(&mut self, group_id: &str) -> Result<(), String> {
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or_else(|| format!("分组不存在: {group_id}"))?;
        group.active = true;
        self.hotkey_registry
            .insert(group.hotkey.clone(), group_id.to_string());
        tracing::info!("分组 {} 已激活", group_id);
        Ok(())
    }

    pub fn deactivate(&mut self, group_id: &str) -> Result<(), String> {
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or_else(|| format!("分组不存在: {group_id}"))?;
        group.active = false;
        self.hotkey_registry.remove(&group.hotkey);
        tracing::info!("分组 {} 已停用", group_id);
        Ok(())
    }

    pub fn get_active_groups(&self) -> Vec<&SkillGroup> {
        self.groups.values().filter(|g| g.active).collect()
    }

    pub fn get_group(&self, group_id: &str) -> Option<&SkillGroup> {
        self.groups.get(group_id)
    }

    pub fn get_group_mut(&mut self, group_id: &str) -> Option<&mut SkillGroup> {
        self.groups.get_mut(group_id)
    }

    pub fn all_groups(&self) -> &HashMap<String, SkillGroup> {
        &self.groups
    }

    pub fn reload_groups(&mut self, groups: HashMap<String, SkillGroup>) {
        self.hotkey_registry.clear();
        for group in groups.values() {
            if group.active {
                self.hotkey_registry
                    .insert(group.hotkey.clone(), group.id.clone());
            }
        }
        self.groups = groups;
    }

    pub fn register_hotkey(&mut self, hotkey: &str, group_id: &str) -> Result<(), String> {
        if let Some(existing_id) = self.hotkey_registry.get(hotkey) {
            return Err(format!("热键 '{}' 已被分组 '{}' 注册", hotkey, existing_id));
        }
        self.hotkey_registry
            .insert(hotkey.to_string(), group_id.to_string());
        tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
        Ok(())
    }

    pub fn unregister_hotkey(&mut self, hotkey: &str) -> Result<(), String> {
        if self.hotkey_registry.remove(hotkey).is_some() {
            tracing::info!("热键 '{}' 已注销", hotkey);
            Ok(())
        } else {
            Err(format!("热键 '{}' 未注册", hotkey))
        }
    }

    pub fn get_hotkey_group(&self, hotkey: &str) -> Option<&str> {
        self.hotkey_registry.get(hotkey).map(|s| s.as_str())
    }

    pub fn build_toggle_command(group: &SkillGroup) -> IpcCommand {
        IpcCommand::ToggleGroup {
            group_id: group.id.clone(),
            active: group.active,
            mode: Some(group.mode.clone()),
            key_press_duration: if group.key_press_duration > 0 {
                Some(group.key_press_duration)
            } else {
                None
            },
            hold_keys: group.hold_keys.clone(),
            hold_mode: group.hold_mode.clone(),
            mode_data: serde_json::to_value(&group.mode_data)
                .ok()
                .filter(|v| !v.is_null()),
        }
    }

    pub fn send_ipc_command(ipc_sender: &dyn IpcSender, cmd: IpcCommand) -> Result<u64, String> {
        ipc_sender.send_command(cmd)
    }

    pub fn emergency_release(ipc_sender: &dyn IpcSender) -> Result<(), String> {
        let cmd = IpcCommand::EmergencyRelease;
        Self::send_ipc_command(ipc_sender, cmd)?;
        Ok(())
    }

    pub fn hold_mode_toggle(ipc_sender: &dyn IpcSender, enabled: bool) -> Result<(), String> {
        let cmd = IpcCommand::HoldModeToggle { enabled };
        Self::send_ipc_command(ipc_sender, cmd)?;
        Ok(())
    }
}

#[cfg(test)]
#[allow(deprecated)]
mod tests {
    use super::*;
    use asd_domain::config::*;

    struct MockIpcSender;
    impl IpcSender for MockIpcSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Ok(1)
        }
    }

    fn make_skill_group(id: &str, mode: &str) -> SkillGroup {
        let mode_data = match mode {
            "periodic" => ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
            "sequence" => ModeData::Sequence(SequenceData {
                keys: vec!["1".to_string()],
                delays: vec![100],
            }),
            "enhanced_periodic" => ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                press_keys: vec!["Space".to_string()],
                intervals: vec![50],
            }),
            _ => ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        };

        SkillGroup {
            id: id.to_string(),
            name: format!("组 {id}"),
            hotkey: format!("F{id}"),
            active: false,
            mode: mode.to_string(),
            key_press_duration: 10,
            hold_keys: None,
            hold_mode: None,
            mode_data,
        }
    }

    fn make_manager() -> SkillManager {
        let ipc_sender = Arc::new(MockIpcSender);
        let mut groups = HashMap::new();
        groups.insert("1".to_string(), make_skill_group("1", "periodic"));
        groups.insert("2".to_string(), make_skill_group("2", "sequence"));
        SkillManager::new(groups, ipc_sender)
    }

    #[test]
    fn test_toggle_group() {
        let mut mgr = make_manager();
        assert!(!mgr.get_group("1").unwrap().active);

        let result = mgr.toggle("1").unwrap();
        assert!(result);
        assert!(mgr.get_group("1").unwrap().active);

        let result = mgr.toggle("1").unwrap();
        assert!(!result);
        assert!(!mgr.get_group("1").unwrap().active);
    }

    #[test]
    fn test_activate_deactivate() {
        let mut mgr = make_manager();
        mgr.activate("1").unwrap();
        assert!(mgr.get_group("1").unwrap().active);

        mgr.deactivate("1").unwrap();
        assert!(!mgr.get_group("1").unwrap().active);
    }

    #[test]
    fn test_activate_nonexistent() {
        let mut mgr = make_manager();
        let result = mgr.activate("999");
        assert!(result.is_err());
    }

    #[test]
    fn test_get_active_groups() {
        let mut mgr = make_manager();
        assert!(mgr.get_active_groups().is_empty());

        mgr.activate("1").unwrap();
        assert_eq!(mgr.get_active_groups().len(), 1);

        mgr.activate("2").unwrap();
        assert_eq!(mgr.get_active_groups().len(), 2);
    }

    #[test]
    fn test_register_hotkey() {
        let mut mgr = make_manager();
        mgr.register_hotkey("F3", "3").unwrap();
        assert_eq!(mgr.get_hotkey_group("F3"), Some("3"));
    }

    #[test]
    fn test_register_duplicate_hotkey() {
        let mut mgr = make_manager();
        mgr.register_hotkey("F3", "3").unwrap();
        let result = mgr.register_hotkey("F3", "4");
        assert!(result.is_err());
    }

    #[test]
    fn test_unregister_hotkey() {
        let mut mgr = make_manager();
        mgr.register_hotkey("F3", "3").unwrap();
        mgr.unregister_hotkey("F3").unwrap();
        assert_eq!(mgr.get_hotkey_group("F3"), None);
    }

    #[test]
    fn test_unregister_nonexistent_hotkey() {
        let mut mgr = make_manager();
        let result = mgr.unregister_hotkey("F99");
        assert!(result.is_err());
    }

    #[test]
    fn test_hotkey_registry_on_activate() {
        let mut mgr = make_manager();
        mgr.activate("1").unwrap();
        assert_eq!(mgr.get_hotkey_group("F1"), Some("1"));

        mgr.deactivate("1").unwrap();
        assert_eq!(mgr.get_hotkey_group("F1"), None);
    }

    #[test]
    fn test_build_toggle_command() {
        let group = make_skill_group("1", "periodic");
        let cmd = SkillManager::build_toggle_command(&group);
        match cmd {
            IpcCommand::ToggleGroup {
                group_id, active, ..
            } => {
                assert_eq!(group_id, "1");
                assert!(!active);
            }
            _ => panic!("Expected ToggleGroup"),
        }
    }

    #[test]
    fn test_build_toggle_command_active() {
        let mut group = make_skill_group("1", "periodic");
        group.active = true;
        let cmd = SkillManager::build_toggle_command(&group);
        match cmd {
            IpcCommand::ToggleGroup {
                group_id, active, ..
            } => {
                assert_eq!(group_id, "1");
                assert!(active);
            }
            _ => panic!("Expected ToggleGroup"),
        }
    }

    #[test]
    fn test_reload_groups() {
        let mut mgr = make_manager();
        mgr.activate("1").unwrap();
        assert!(mgr.get_hotkey_group("F1").is_some());

        let mut new_groups = HashMap::new();
        new_groups.insert("3".to_string(), make_skill_group("3", "periodic"));
        mgr.reload_groups(new_groups);

        assert!(mgr.get_group("1").is_none());
        assert!(mgr.get_group("3").is_some());
        assert!(mgr.get_hotkey_group("F1").is_none());
    }

    #[test]
    fn test_all_groups() {
        let mgr = make_manager();
        assert_eq!(mgr.all_groups().len(), 2);
    }

    #[test]
    fn test_get_group_mut() {
        let mut mgr = make_manager();
        let group = mgr.get_group_mut("1").unwrap();
        group.active = true;
        assert!(mgr.get_group("1").unwrap().active);
    }

    #[test]
    fn test_send_ipc_command_via_trait() {
        let ipc_sender = MockIpcSender;
        let cmd = IpcCommand::EmergencyRelease;
        let result = SkillManager::send_ipc_command(&ipc_sender, cmd);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 1);
    }

    #[test]
    fn test_emergency_release_via_trait() {
        let ipc_sender = MockIpcSender;
        let result = SkillManager::emergency_release(&ipc_sender);
        assert!(result.is_ok());
    }

    #[test]
    fn test_hold_mode_toggle_via_trait() {
        let ipc_sender = MockIpcSender;
        let result = SkillManager::hold_mode_toggle(&ipc_sender, true);
        assert!(result.is_ok());
    }
}
