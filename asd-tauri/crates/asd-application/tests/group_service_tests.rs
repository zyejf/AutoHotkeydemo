mod common;

use std::sync::{Arc, Mutex};

use asd_application::error::AppError;
use asd_application::group_service;
use asd_domain::traits::IpcSender;
use asd_ipc_protocol::IpcCommand;
use common::*;

/// 只让**指定种类**的 IPC 命令失败的发送器。
///
/// 存在的理由：`register_hotkey` 里有两条**此前完全没有测试覆盖**的回滚路径
/// （注销旧热键失败、注册新热键失败），要逼出其中某一条，就必须让另一条成功 ——
/// 「全部失败」只能走到第一条就返回了。
///
/// 失败与否由 `fail_on` 这个**函数指针**决定（不能用闭包：`IpcSender` 要求
/// `Send + Sync`，而带捕获的闭包不满足；函数指针天然满足）。
struct SelectiveFailingIpcSender {
    sent: Mutex<Vec<IpcCommand>>,
    fail_on: fn(&IpcCommand) -> bool,
}

impl SelectiveFailingIpcSender {
    fn new(fail_on: fn(&IpcCommand) -> bool) -> Self {
        Self {
            sent: Mutex::new(Vec::new()),
            fail_on,
        }
    }
    fn sent_commands(&self) -> Vec<IpcCommand> {
        self.sent.lock().unwrap().clone()
    }
}

impl IpcSender for SelectiveFailingIpcSender {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        let will_fail = (self.fail_on)(&cmd);
        self.sent.lock().unwrap().push(cmd.clone());
        if will_fail {
            return Err("injected IPC failure".to_string());
        }
        Ok(1)
    }
}

fn is_unregister(cmd: &IpcCommand) -> bool {
    matches!(cmd, IpcCommand::UnregisterHotkey { .. })
}

fn is_register(cmd: &IpcCommand) -> bool {
    matches!(cmd, IpcCommand::RegisterHotkey { .. })
}

/// 造一个「IPC 会按 `fail_on` 选择性失败」的 `AppState`，并返回发送器以便检视命令。
fn make_state_with_failing_ipc(
    fail_on: fn(&IpcCommand) -> bool,
) -> (
    Arc<asd_application::state::AppState>,
    Arc<SelectiveFailingIpcSender>,
) {
    let sender = Arc::new(SelectiveFailingIpcSender::new(fail_on));
    let state = Arc::new(asd_application::state::AppState::new(
        make_test_config(),
        sender.clone(),
        Arc::new(MockProcessWatcher),
        Arc::new(MockEventEmitter::new()),
    ));
    (state, sender)
}

#[test]
fn test_toggle_group() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_group(&state, "1");
    assert!(result.is_ok());
    let status = result.unwrap();
    assert_eq!(status.id, "1");
    assert!(status.active);
}

#[test]
fn test_toggle_group_not_found() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_group(&state, "999");
    assert!(matches!(result, Err(AppError::GroupNotFound(_))));
}

#[test]
fn test_toggle_group_sends_ipc() {
    let (state, ipc) = make_test_state_with_recording_sender();
    group_service::toggle_group(&state, "1").unwrap();
    let commands = ipc.sent_commands();
    // toggle_group sends RegisterHotkey (try_send) + ToggleGroup (send)
    assert_eq!(commands.len(), 2);
    match &commands[0] {
        IpcCommand::RegisterHotkey { hotkey, group_id } => {
            assert_eq!(group_id, "1");
            assert!(!hotkey.is_empty());
        }
        _ => panic!("Expected RegisterHotkey IPC command"),
    }
    match &commands[1] {
        IpcCommand::ToggleGroup {
            group_id, active, ..
        } => {
            assert_eq!(group_id, "1");
            assert!(*active);
        }
        _ => panic!("Expected ToggleGroup IPC command"),
    }
}

#[test]
fn test_toggle_group_twice() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let status1 = group_service::toggle_group(&state, "1").unwrap();
    assert!(status1.active);
    let status2 = group_service::toggle_group(&state, "1").unwrap();
    assert!(!status2.active);
}

#[test]
fn test_delete_group() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::delete_group(&state, "1");
    assert!(result.is_ok());
    let group = state.get_group("1");
    assert!(group.is_none());
}

#[test]
fn test_delete_group_not_found() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::delete_group(&state, "999");
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), AppError::GroupNotFound(_)));
}

#[test]
fn test_toggle_all() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::toggle_all(&state, true);
    assert!(result.is_ok());
    let toggle_result = result.unwrap();
    assert!(toggle_result.succeeded.contains(&"1".to_string()));
    assert!(toggle_result.succeeded.contains(&"2".to_string()));
    assert!(toggle_result.state_errors.is_empty());
    assert!(toggle_result.ipc_rolled_back.is_empty());
    assert!(toggle_result.not_found.is_empty());
    let group1 = state.get_group("1").unwrap();
    let group2 = state.get_group("2").unwrap();
    assert!(group1.active);
    assert!(group2.active);
}

#[test]
fn test_batch_toggle_groups() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::batch_toggle_groups(&state, &["1".to_string()], true);
    assert!(result.is_ok());
    let toggle_result = result.unwrap();
    assert!(toggle_result.succeeded.contains(&"1".to_string()));
    assert!(toggle_result.state_errors.is_empty());
    assert!(toggle_result.ipc_rolled_back.is_empty());
    assert!(toggle_result.not_found.is_empty());
    let group1 = state.get_group("1").unwrap();
    assert!(group1.active);
    let group2 = state.get_group("2").unwrap();
    assert!(!group2.active);
}

#[test]
fn test_batch_toggle_groups_not_found() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::batch_toggle_groups(
        &state,
        &["1".to_string(), "999".to_string(), "888".to_string()],
        true,
    );
    assert!(result.is_ok());
    let toggle_result = result.unwrap();
    assert!(toggle_result.succeeded.contains(&"1".to_string()));
    assert!(toggle_result.not_found.contains(&"999".to_string()));
    assert!(toggle_result.not_found.contains(&"888".to_string()));
    assert_eq!(toggle_result.not_found.len(), 2);
}

#[test]
fn test_batch_delete_groups() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::batch_delete_groups(&state, &["1".to_string()]);
    assert!(result.is_ok());
    assert!(state.get_group("1").is_none());
    assert!(state.get_group("2").is_some());
}

#[test]
fn test_reorder_groups() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::reorder_groups(&state, &["2".to_string(), "1".to_string()]);
    assert!(result.is_ok());
    let reorder_result = result.unwrap();
    assert_eq!(reorder_result.reordered_count, 2);
    assert!(reorder_result.appended_groups.is_empty());
    let groups = state.read_groups().unwrap();
    let keys: Vec<&String> = groups.keys().collect();
    assert_eq!(keys[0], &"2".to_string());
    assert_eq!(keys[1], &"1".to_string());
}

#[test]
fn test_reorder_groups_with_appended() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::reorder_groups(&state, &["1".to_string()]);
    assert!(result.is_ok());
    let reorder_result = result.unwrap();
    assert_eq!(reorder_result.reordered_count, 1);
    assert!(reorder_result.appended_groups.contains(&"2".to_string()));
    let groups = state.read_groups().unwrap();
    let keys: Vec<&String> = groups.keys().collect();
    assert_eq!(keys[0], &"1".to_string());
    assert_eq!(keys[1], &"2".to_string());
}

#[test]
fn test_register_hotkey() {
    let (state, ipc) = make_test_state_with_recording_sender();
    // 先激活分组，使热键注册发送 IPC 命令
    group_service::toggle_group(&state, "1").unwrap();
    ipc.sent_commands(); // 清空 toggle 产生的命令
    let result = group_service::register_hotkey(&state, "F3", "1");
    assert!(result.is_ok());
    let commands = ipc.sent_commands();
    // 活跃分组注册新热键：先注销旧热键，再注册新热键
    assert!(!commands.is_empty());
    assert!(commands.iter().any(|c| matches!(
        c,
        IpcCommand::RegisterHotkey { hotkey, group_id } if hotkey == "F3" && group_id == "1"
    )));
}

#[test]
fn test_register_hotkey_duplicate() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    // 激活两个分组，使热键注册经过 active_hotkeys 重复检查
    group_service::toggle_group(&state, "1").unwrap();
    group_service::toggle_group(&state, "2").unwrap();
    // 尝试将分组 2 的热键改为分组 1 已注册的热键
    let group1_hotkey = state.get_group("1").unwrap().hotkey;
    let result = group_service::register_hotkey(&state, &group1_hotkey, "2");
    assert!(matches!(result, Err(AppError::Validation(_))));
}

#[test]
fn test_unregister_hotkey() {
    let (state, ipc) = make_test_state_with_recording_sender();
    // 先激活分组，使热键注册到 active_hotkeys
    group_service::toggle_group(&state, "1").unwrap();
    let hotkey = state.get_group("1").unwrap().hotkey;
    ipc.sent_commands(); // 清空 toggle 产生的命令
    let result = group_service::unregister_hotkey(&state, &hotkey);
    assert!(result.is_ok());
    let commands = ipc.sent_commands();
    assert!(commands.iter().any(|c| matches!(
        c,
        IpcCommand::UnregisterHotkey { hotkey: h } if h == &hotkey
    )));
}

#[test]
fn test_unregister_hotkey_not_registered() {
    let (state, _ipc) = make_test_state_with_recording_sender();
    let result = group_service::unregister_hotkey(&state, "F99");
    assert!(matches!(result, Err(AppError::Validation(_))));
}

// ----------------------------------------------------------------
// TD-023：`register_hotkey` 的两条 IPC 失败回滚路径。
//
// ⚠️ 这两条路径在补这些测试之前**完全没有覆盖** —— 既有的
// `test_register_hotkey` / `test_register_hotkey_duplicate` 只走成功路径和
// 「热键冲突」（那在 `swap_hotkey` 就返回了，根本到不了 IPC）。
// 也就是说：把下面任何一步回滚删掉，测试套件照样全绿。
// ----------------------------------------------------------------

/// 注销**旧**热键失败时：活跃热键表与配置热键都要回滚到原值。
#[test]
fn test_register_hotkey_rolls_back_when_unregister_old_fails() {
    let (state, ipc) = make_state_with_failing_ipc(is_unregister);
    group_service::toggle_group(&state, "1").unwrap();
    let base = ipc.sent_commands().len();

    let result = group_service::register_hotkey(&state, "F3", "1");

    assert!(
        matches!(result, Err(AppError::Ipc(_))),
        "IPC 失败应原样返回 Ipc 错误，实际: {result:?}"
    );

    // ① 配置热键回滚到 F1（不是停在半路的 F3）
    assert_eq!(state.get_group("1").unwrap().hotkey, "F1");
    // ② 活跃热键表回滚：F1 仍指向分组 1，F3 没有残留
    assert_eq!(state.get_hotkey_group("F1").unwrap(), Some("1".to_string()));
    assert_eq!(state.get_hotkey_group("F3").unwrap(), None);
    // ③ 只在注销旧键处失败，所以后面注册新键的命令**不应该**发出
    let tail = &ipc.sent_commands()[base..];
    assert_eq!(tail.len(), 1, "失败后就该停住，不该继续注册新键: {tail:?}");
    assert!(
        matches!(&tail[0], IpcCommand::UnregisterHotkey { hotkey } if hotkey == "F1"),
        "应只发出注销旧键 F1 的命令，实际: {tail:?}"
    );
}

/// 注册**新**热键失败时：除回滚外，还要**把旧热键重新注册回 AHK**
/// （否则 AHK 侧监听丢了，而 Rust 侧却以为还是 F1）。
#[test]
fn test_register_hotkey_rolls_back_when_register_new_fails() {
    let (state, ipc) = make_state_with_failing_ipc(is_register);
    group_service::toggle_group(&state, "1").unwrap();
    let base = ipc.sent_commands().len();

    let result = group_service::register_hotkey(&state, "F3", "1");

    assert!(
        matches!(result, Err(AppError::Ipc(_))),
        "IPC 失败应原样返回 Ipc 错误，实际: {result:?}"
    );

    // ① 配置热键回滚到 F1
    assert_eq!(state.get_group("1").unwrap().hotkey, "F1");
    // ② 活跃热键表回滚
    assert_eq!(state.get_hotkey_group("F1").unwrap(), Some("1".to_string()));
    assert_eq!(state.get_hotkey_group("F3").unwrap(), None);
    // ③ 命令序列：注销旧键 → 注册新键（失败）→ 把旧键注册回去补救
    let tail = &ipc.sent_commands()[base..];
    assert_eq!(tail.len(), 3, "命令序列长度不对: {tail:?}");
    assert!(
        matches!(&tail[0], IpcCommand::UnregisterHotkey { hotkey } if hotkey == "F1"),
        "① 应先注销旧键 F1，实际: {tail:?}"
    );
    assert!(
        matches!(&tail[1], IpcCommand::RegisterHotkey { hotkey, group_id } if hotkey == "F3" && group_id == "1"),
        "② 应尝试注册新键 F3，实际: {tail:?}"
    );
    assert!(
        matches!(&tail[2], IpcCommand::RegisterHotkey { hotkey, group_id } if hotkey == "F1" && group_id == "1"),
        "③ 少了「把旧热键 F1 注册回 AHK」的补救，AHK 侧监听就丢了，实际: {tail:?}"
    );
}

/// 分组处于激活状态、但活跃表里**没有**它的旧热键时（`old_hotkey == None`），
/// 注册失败要把刚刚占住的位置撤掉，否则会留下一条指向该分组的幽灵热键。
#[test]
fn test_register_hotkey_rolls_back_when_register_fails_without_old_hotkey() {
    let (state, ipc) = make_state_with_failing_ipc(is_register);
    group_service::toggle_group(&state, "1").unwrap();
    // 造出「分组仍激活、但活跃表里没有它的热键」这个状态
    state.remove_group_hotkeys("1").unwrap();
    let base = ipc.sent_commands().len();

    let result = group_service::register_hotkey(&state, "F3", "1");

    assert!(
        matches!(result, Err(AppError::Ipc(_))),
        "IPC 失败应原样返回 Ipc 错误，实际: {result:?}"
    );
    // ① 配置热键回滚到 F1
    assert_eq!(state.get_group("1").unwrap().hotkey, "F1");
    // ② 关键：F3 不能留在活跃表里 —— 这就是 `None` 分支要做的事
    assert_eq!(
        state.get_hotkey_group("F3").unwrap(),
        None,
        "注册失败后 F3 不应残留在活跃热键表中"
    );
    // ③ 没有旧热键可注销，所以只有一条注册命令
    let tail = &ipc.sent_commands()[base..];
    assert_eq!(tail.len(), 1, "没有旧热键就不该发注销命令: {tail:?}");
    assert!(
        matches!(&tail[0], IpcCommand::RegisterHotkey { hotkey, group_id } if hotkey == "F3" && group_id == "1"),
        "应只尝试注册新键 F3，实际: {tail:?}"
    );
}
