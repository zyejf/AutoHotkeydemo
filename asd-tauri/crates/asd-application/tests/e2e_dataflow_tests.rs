//! 跨 crate 端到端数据流集成测试
//!
//! 验证 Config → `AppState` → `sync_config_changes_to_ahk` → `IpcCommand` → `IpcMessage` 的完整数据流。
//! 涵盖配置变更、录制流程、分组切换、热键注册/注销等场景，并验证 IPC 消息的 JSON 序列化往返正确性。

use asd_application::group_service;
use asd_application::recording_service;
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use asd_test_harness::*;

// =================================================================
// 测试 1: 配置变更 → IPC 命令完整数据流
// =================================================================
//
// 验证路径：Config 参数变更 → save_config_atomic → sync_config_changes_to_ahk
//          → IpcCommand::ToggleGroup → IpcMessage → JSON 序列化往返
//
// 注意：sync_config_changes_to_ahk 是 AppState 的私有方法，无法从外部直接调用。
// save_config_atomic 会内部调用它，比较 old_groups 和 new_groups 的差异并发送相应 IPC 命令。
// 当分组已激活且参数变化时，sync 会发送 ToggleGroup(true) 命令以重新同步到 AHK。

#[test]
fn test_config_change_to_ipc_command_full_flow() {
    let (state, sender) = make_test_state_with_recording_sender();

    // 初始状态：分组 1 未激活
    let old_groups = state.read_groups().unwrap();
    assert!(!old_groups["1"].active, "初始状态分组 1 应未激活");

    // 激活分组 1（set_group_active 不发送 IPC 命令，仅更新内存状态）
    state.set_group_active("1", true).unwrap();
    // 清空命令缓冲（set_group_active 不应发送 IPC，但为安全起见消费任何残留命令）
    let _initial_cmds = sender.sent_commands();

    // 修改配置参数：将 key_press_duration 从 10 改为 99
    // 这会触发 sync_config_changes_to_ahk 检测到参数变化并发送 ToggleGroup(true)
    let mut new_config = state.read_config().unwrap();
    new_config
        .group_settings
        .get_mut("1")
        .unwrap()
        .key_press_duration = Some(99);

    // save_config_atomic 内部会：
    // 1. 保留旧 active 状态（分组 1 仍为激活）
    // 2. 检测到 key_press_duration 变化
    // 3. 调用 sync_config_changes_to_ahk 发送 ToggleGroup(true) 命令
    state.save_config_atomic(new_config).unwrap();

    // 捕获发送的 IPC 命令
    let cmds = sender.sent_commands();

    // 验证 ToggleGroup 命令存在且参数正确
    let toggle_cmd = cmds
        .iter()
        .find(|c| matches!(c, IpcCommand::ToggleGroup { .. }));
    assert!(
        toggle_cmd.is_some(),
        "应发送 ToggleGroup 命令，实际收到的命令: {cmds:?}"
    );

    match toggle_cmd.unwrap() {
        IpcCommand::ToggleGroup {
            group_id,
            active,
            mode,
            key_press_duration,
            hold_keys,
            hold_mode,
            mode_data,
        } => {
            assert_eq!(group_id, "1", "group_id 应为 \"1\"");
            assert!(*active, "active 应为 true（分组已激活，参数变更重新同步）");
            assert_eq!(mode.as_deref(), Some("periodic"), "mode 应为 \"periodic\"");
            assert_eq!(
                *key_press_duration,
                Some(99),
                "key_press_duration 应为 Some(99)"
            );
            assert!(hold_keys.is_none(), "hold_keys 应为 None");
            assert!(hold_mode.is_none(), "hold_mode 应为 None");
            assert!(
                mode_data.is_some(),
                "mode_data 应为 Some（包含 keys 和 intervals）"
            );
        }
        other => panic!("Expected ToggleGroup, got {other:?}"),
    }

    // 序列化 ToggleGroup 命令到 IpcMessage，然后 JSON，然后反序列化验证往返正确性
    let original_cmd = toggle_cmd.unwrap().clone();
    let msg = IpcMessage::command(42, &original_cmd);

    // 验证 IpcMessage 结构
    assert_eq!(msg.r#type, "command", "IpcMessage.type 应为 \"command\"");
    assert_eq!(msg.seq, 42, "IpcMessage.seq 应为 42");
    assert_eq!(
        msg.action.as_deref(),
        Some("toggle_group"),
        "IpcMessage.action 应为 \"toggle_group\""
    );
    assert!(msg.data.is_some(), "IpcMessage.data 应为 Some");

    // JSON 序列化往返
    let json = serde_json::to_string(&msg).expect("序列化 IpcMessage 到 JSON 失败");
    let decoded: IpcMessage =
        serde_json::from_str(&json).expect("从 JSON 反序列化 IpcMessage 失败");

    assert_eq!(decoded.r#type, "command");
    assert_eq!(decoded.seq, 42);
    assert_eq!(decoded.action.as_deref(), Some("toggle_group"));
    assert!(decoded.data.is_some());

    let data = decoded.data.as_ref().unwrap();
    assert_eq!(data["groupId"], "1", "JSON 往返后 groupId 应为 \"1\"");
    assert_eq!(data["active"], true, "JSON 往返后 active 应为 true");
    assert_eq!(
        data["keyPressDuration"], 99,
        "JSON 往返后 keyPressDuration 应为 99"
    );
    assert_eq!(
        data["mode"], "periodic",
        "JSON 往返后 mode 应为 \"periodic\""
    );
}

// =================================================================
// 测试 2: 录制流程完整数据流
// =================================================================
//
// 验证路径：start_recording → recording_mode 设置 → stop_recording → recording_mode 清除
//          → export_recording → import_recording 往返一致性
//
// 使用 MockIpcSender（通过 make_test_state），其 send_and_wait 返回包含
// keys/mode/intervals/delays 的有效录制响应，满足 stop_recording 的解析要求。

#[test]
fn test_recording_flow_full_dataflow() {
    // 使用 MockIpcSender，其 send_and_wait 返回有效录制响应
    let state = make_test_state();

    // 初始状态：recording_mode 应为 None
    {
        let mode = state.recording_mode.read();
        assert!(mode.is_none(), "初始状态 recording_mode 应为 None");
    }

    // 启动录制
    recording_service::start_recording(&state, "1", "periodic").expect("启动录制应成功");

    // 验证 recording_mode 已设置为 "periodic"
    {
        let mode = state.recording_mode.read();
        assert_eq!(
            *mode,
            Some("periodic".to_string()),
            "录制启动后 recording_mode 应为 Some(\"periodic\")"
        );
    }

    // 停止录制
    let result = recording_service::stop_recording(&state).expect("停止录制应成功");

    // 验证 recording_mode 已清除
    {
        let mode = state.recording_mode.read();
        assert!(mode.is_none(), "录制停止后 recording_mode 应为 None");
    }

    // 验证录制结果（MockIpcSender 返回的固定响应数据）
    assert_eq!(result.seq, 1, "录制结果 seq 应为 1");
    assert_eq!(
        result.keys,
        vec!["1", "2"],
        "录制结果 keys 应为 [\"1\", \"2\"]"
    );
    assert_eq!(result.mode, "periodic", "录制结果 mode 应为 \"periodic\"");
    assert_eq!(
        result.intervals,
        vec![50, 100],
        "录制结果 intervals 应为 [50, 100]"
    );
    assert!(result.delays.is_empty(), "录制结果 delays 应为空");

    // 测试 export_recording 和 import_recording 往返一致性
    // 使用 sequence 模式以验证 delays 参数的往返
    let dir = std::env::temp_dir().join("asd_e2e_recording_dataflow_test");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("创建临时目录失败");

    let export_path = dir.join("recording.json");
    let path_str = export_path.to_str().expect("路径转换失败");

    // 准备录制数据（sequence 模式需要 delays 非空）
    let keys = vec!["A".to_string(), "B".to_string(), "C".to_string()];
    let intervals: Vec<u64> = vec![]; // sequence 模式不需要 intervals
    let delays = vec![100u64, 200u64, 300u64];
    let mode = "sequence";

    // 导出录制数据
    recording_service::export_recording(path_str, &keys, &intervals, &delays, mode)
        .expect("导出录制应成功");

    // 导入录制数据
    let imported = recording_service::import_recording(path_str).expect("导入录制应成功");

    // 验证导入数据匹配导出数据
    assert_eq!(imported.keys, keys, "导入的 keys 应与导出的 keys 一致");
    assert_eq!(
        imported.delays, delays,
        "导入的 delays 应与导出的 delays 一致"
    );
    assert_eq!(
        imported.intervals, intervals,
        "导入的 intervals 应与导出的 intervals 一致（空向量）"
    );
    assert_eq!(imported.mode, mode, "导入的 mode 应与导出的 mode 一致");

    // 清理临时目录
    let _ = std::fs::remove_dir_all(&dir);
}

// =================================================================
// 测试 3: 分组切换 → ToggleGroup 命令数据流
// =================================================================
//
// 验证路径：group_service::toggle_group → state.toggle_group_active
//          → IpcCommand::ToggleGroup → IpcMessage → JSON 序列化往返
//
// toggle_group 激活/停用时会发送 RegisterHotkey/UnregisterHotkey 和 ToggleGroup 命令。
// 本测试验证 ToggleGroup 命令的 active 参数正确性及 IPC 消息序列化往返。

#[test]
fn test_group_toggle_to_toggle_command_flow() {
    let (state, sender) = make_test_state_with_recording_sender();

    // 初始状态：分组 1 未激活
    let initial_group = state.get_group("1").expect("分组 1 应存在");
    assert!(!initial_group.active, "初始状态分组 1 应未激活");

    // 第一次切换：激活分组 1
    let status = group_service::toggle_group(&state, "1").expect("激活分组应成功");
    assert!(status.active, "切换后分组应为激活状态");
    assert_eq!(status.id, "1");

    // 捕获发送的 IPC 命令
    let cmds_after_activate = sender.sent_commands();

    // 验证 ToggleGroup{active:true} 命令存在
    let toggle_on_cmd = cmds_after_activate
        .iter()
        .find(|c| matches!(c, IpcCommand::ToggleGroup { active: true, .. }));
    assert!(
        toggle_on_cmd.is_some(),
        "激活时应发送 ToggleGroup{{active:true}} 命令，实际: {cmds_after_activate:?}"
    );

    // 验证 ToggleGroup 命令参数
    match toggle_on_cmd.unwrap() {
        IpcCommand::ToggleGroup {
            group_id,
            active,
            mode,
            key_press_duration,
            ..
        } => {
            assert_eq!(group_id, "1");
            assert!(*active, "active 应为 true");
            assert_eq!(mode.as_deref(), Some("periodic"));
            // make_test_config 中分组 1 的 key_press_duration 为 Some(10)
            assert_eq!(*key_press_duration, Some(10));
        }
        other => panic!("Expected ToggleGroup, got {other:?}"),
    }

    // 序列化 ToggleGroup{active:true} 到 IpcMessage 并验证 JSON 往返
    let toggle_on_cmd_ref = cmds_after_activate
        .iter()
        .find(|c| matches!(c, IpcCommand::ToggleGroup { active: true, .. }))
        .unwrap()
        .clone();
    let msg_on = IpcMessage::command(1, &toggle_on_cmd_ref);
    let json_on = serde_json::to_string(&msg_on).expect("序列化失败");
    let decoded_on: IpcMessage = serde_json::from_str(&json_on).expect("反序列化失败");
    assert_eq!(decoded_on.action.as_deref(), Some("toggle_group"));
    assert_eq!(decoded_on.data.as_ref().unwrap()["groupId"], "1");
    assert_eq!(decoded_on.data.as_ref().unwrap()["active"], true);

    // 第二次切换：停用分组 1
    let status = group_service::toggle_group(&state, "1").expect("停用分组应成功");
    assert!(!status.active, "再次切换后分组应为未激活状态");

    // 捕获所有发送的 IPC 命令（包含激活和停用的命令）
    let cmds_all = sender.sent_commands();

    // 验证 ToggleGroup{active:false} 命令存在
    let toggle_off_cmd = cmds_all
        .iter()
        .find(|c| matches!(c, IpcCommand::ToggleGroup { active: false, .. }));
    assert!(
        toggle_off_cmd.is_some(),
        "停用时应发送 ToggleGroup{{active:false}} 命令"
    );

    // 验证 ToggleGroup{active:false} 命令参数
    match toggle_off_cmd.unwrap() {
        IpcCommand::ToggleGroup {
            group_id,
            active,
            mode,
            ..
        } => {
            assert_eq!(group_id, "1");
            assert!(!*active, "active 应为 false");
            assert_eq!(mode.as_deref(), Some("periodic"));
        }
        other => panic!("Expected ToggleGroup, got {other:?}"),
    }

    // 序列化 ToggleGroup{active:false} 到 IpcMessage 并验证 JSON 往返
    let toggle_off_cmd_ref = cmds_all
        .iter()
        .find(|c| matches!(c, IpcCommand::ToggleGroup { active: false, .. }))
        .unwrap()
        .clone();
    let msg_off = IpcMessage::command(2, &toggle_off_cmd_ref);
    let json_off = serde_json::to_string(&msg_off).expect("序列化失败");
    let decoded_off: IpcMessage = serde_json::from_str(&json_off).expect("反序列化失败");
    assert_eq!(decoded_off.action.as_deref(), Some("toggle_group"));
    assert_eq!(decoded_off.data.as_ref().unwrap()["groupId"], "1");
    assert_eq!(decoded_off.data.as_ref().unwrap()["active"], false);

    // 验证最终状态：分组 1 未激活
    let final_group = state.get_group("1").expect("分组 1 应存在");
    assert!(!final_group.active, "最终状态分组 1 应未激活");
}

// =================================================================
// 测试 4: 热键注册/注销数据流
// =================================================================
//
// 验证路径：group_service::register_hotkey → IpcCommand::RegisterHotkey
//          → group_service::unregister_hotkey → IpcCommand::UnregisterHotkey
//          → IpcMessage → JSON 序列化往返
//
// 注意：group_service::register_hotkey 对活跃分组才发送 IPC 命令。
// 非活跃分组仅更新配置，激活时自动注册。因此本测试先激活分组，再修改热键。

#[test]
fn test_hotkey_register_unregister_flow() {
    let (state, sender) = make_test_state_with_recording_sender();

    // 初始状态：分组 1 未激活，热键为 F1
    let initial_group = state.get_group("1").expect("分组 1 应存在");
    assert!(!initial_group.active, "初始状态分组 1 应未激活");
    assert_eq!(initial_group.hotkey, "F1", "初始热键应为 F1");

    // 先激活分组 1（register_hotkey 对活跃分组才发送 IPC）
    state.set_group_active("1", true).unwrap();
    // 消费 set_group_active 可能产生的任何命令（set_group_active 不发送 IPC）
    let _ = sender.sent_commands();

    // 注册新热键 F3 到分组 1（原热键为 F1）
    // register_hotkey 对活跃分组会：
    // 1. 更新配置中的热键（set_group_hotkey）
    // 2. 更新 active_hotkeys（swap_hotkey）
    // 3. 发送 UnregisterHotkey{F1}（注销旧热键）
    // 4. 发送 RegisterHotkey{F3, 1}（注册新热键）
    group_service::register_hotkey(&state, "F3", "1").expect("注册热键 F3 应成功");

    // 捕获发送的 IPC 命令
    let cmds_after_register = sender.sent_commands();

    // 验证 UnregisterHotkey{F1} 命令存在（注销旧热键）
    let has_unregister_f1 = cmds_after_register
        .iter()
        .any(|c| matches!(c, IpcCommand::UnregisterHotkey { hotkey } if hotkey == "F1"));
    assert!(
        has_unregister_f1,
        "注册新热键时应发送 UnregisterHotkey{{F1}} 命令注销旧热键，实际: {cmds_after_register:?}"
    );

    // 验证 RegisterHotkey{F3, 1} 命令存在
    let register_cmd = cmds_after_register
        .iter()
        .find(|c| matches!(c, IpcCommand::RegisterHotkey { hotkey, group_id } if hotkey == "F3" && group_id == "1"));
    assert!(
        register_cmd.is_some(),
        "应发送 RegisterHotkey{{F3, 1}} 命令"
    );

    // 序列化 RegisterHotkey 命令到 IpcMessage 并验证 JSON 往返
    let register_cmd_ref = register_cmd.unwrap().clone();
    let msg_reg = IpcMessage::command(1, &register_cmd_ref);
    assert_eq!(msg_reg.r#type, "command");
    assert_eq!(msg_reg.action.as_deref(), Some("register_hotkey"));
    assert_eq!(msg_reg.seq, 1);

    let json_reg = serde_json::to_string(&msg_reg).expect("序列化失败");
    let decoded_reg: IpcMessage = serde_json::from_str(&json_reg).expect("反序列化失败");
    assert_eq!(decoded_reg.action.as_deref(), Some("register_hotkey"));
    assert_eq!(decoded_reg.data.as_ref().unwrap()["hotkey"], "F3");
    assert_eq!(decoded_reg.data.as_ref().unwrap()["groupId"], "1");

    // 验证配置中的热键已更新为 F3
    let group_after_register = state.get_group("1").expect("分组 1 应存在");
    assert_eq!(
        group_after_register.hotkey, "F3",
        "注册后分组 1 的热键应为 F3"
    );

    // 注销热键 F3
    // unregister_hotkey 会：
    // 1. 从 active_hotkeys 移除 F3
    // 2. 发送 UnregisterHotkey{F3}
    // 3. 因为分组活跃，发送 ToggleGroup{1, false} 并 set_group_active(false)
    group_service::unregister_hotkey(&state, "F3").expect("注销热键 F3 应成功");

    // 捕获所有发送的 IPC 命令
    let cmds_all = sender.sent_commands();

    // 验证 UnregisterHotkey{F3} 命令存在
    let unregister_f3_cmd = cmds_all
        .iter()
        .find(|c| matches!(c, IpcCommand::UnregisterHotkey { hotkey } if hotkey == "F3"));
    assert!(
        unregister_f3_cmd.is_some(),
        "应发送 UnregisterHotkey{{F3}} 命令"
    );

    // 序列化 UnregisterHotkey 命令到 IpcMessage 并验证 JSON 往返
    let unregister_cmd_ref = unregister_f3_cmd.unwrap().clone();
    let msg_unreg = IpcMessage::command(2, &unregister_cmd_ref);
    assert_eq!(msg_unreg.r#type, "command");
    assert_eq!(msg_unreg.action.as_deref(), Some("unregister_hotkey"));

    let json_unreg = serde_json::to_string(&msg_unreg).expect("序列化失败");
    let decoded_unreg: IpcMessage = serde_json::from_str(&json_unreg).expect("反序列化失败");
    assert_eq!(decoded_unreg.action.as_deref(), Some("unregister_hotkey"));
    assert_eq!(decoded_unreg.data.as_ref().unwrap()["hotkey"], "F3");

    // 验证最终状态：分组 1 已停用（unregister_hotkey 会自动停用活跃分组）
    let final_group = state.get_group("1").expect("分组 1 应存在");
    assert!(!final_group.active, "注销热键后分组 1 应已停用");
}
