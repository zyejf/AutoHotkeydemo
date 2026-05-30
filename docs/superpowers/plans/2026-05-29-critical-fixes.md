# Critical Issues Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 20 Critical issues identified by 5 parallel architecture reviews

**Architecture:** Mixed Rust/Tauri + AHK subprocess. Rust is IPC server (Named Pipe), AHK is client. Tauri invoke/emit for JS↔Rust, Named Pipe JSON Lines for Rust↔AHK.

**Tech Stack:** Rust (Tauri 2.x, tokio, serde, interprocess), AHK v2, JavaScript (Tauri API)

---

## Wave 1: Independent Groups (Parallel)

### Task A1: Fix toggle_group missing mode config (C-1)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\domain\models.rs` — Extend ToggleGroup data payload
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\commands\group_cmd.rs` — Send full group config
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk` — Receive and use config

- [ ] **Step 1: Write failing test — ToggleGroup data includes mode config**

In `models.rs` tests, add test verifying that `IpcMessage::command()` for ToggleGroup includes mode_data:

```rust
#[test]
fn test_toggle_group_includes_mode_config_in_data() {
    let cmd = IpcCommand::ToggleGroup {
        group_id: "1".to_string(),
        active: true,
    };
    let msg = IpcMessage::command(1, &cmd);
    let data = msg.data.as_ref().expect("ToggleGroup should have data");
    // Currently only has groupId and active — this test should FAIL
    // because mode/intervals/keys are missing
    assert!(data.get("mode").is_some(), "ToggleGroup data should include 'mode' field");
    assert!(data.get("modeData").is_some(), "ToggleGroup data should include 'modeData' field");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test test_toggle_group_includes_mode_config_in_data`
Expected: FAIL — `data.get("mode")` returns None

- [ ] **Step 3: Extend IpcCommand::ToggleGroup to carry mode config**

In `models.rs`, change `IpcCommand::ToggleGroup`:

```rust
#[serde(rename = "toggle_group")]
ToggleGroup {
    #[serde(rename = "groupId")]
    group_id: String,
    active: bool,
    #[serde(rename = "mode", skip_serializing_if = "Option::is_none", default)]
    mode: Option<String>,
    #[serde(rename = "keyPressDuration", skip_serializing_if = "Option::is_none", default)]
    key_press_duration: Option<u64>,
    #[serde(rename = "holdKeys", skip_serializing_if = "Option::is_none", default)]
    hold_keys: Option<Vec<String>>,
    #[serde(rename = "holdMode", skip_serializing_if = "Option::is_none", default)]
    hold_mode: Option<String>,
    #[serde(rename = "modeData", skip_serializing_if = "Option::is_none", default)]
    mode_data: Option<serde_json::Value>,
},
```

Update `IpcMessage::command()` ToggleGroup arm to include new fields in data:

```rust
IpcCommand::ToggleGroup { group_id, active, mode, key_press_duration, hold_keys, hold_mode, mode_data } => {
    let mut data = serde_json::json!({
        "groupId": group_id,
        "active": active
    });
    if let Some(m) = mode {
        data["mode"] = serde_json::Value::String(m);
    }
    if let Some(kpd) = key_press_duration {
        data["keyPressDuration"] = serde_json::Value::Number(kpd.into());
    }
    if let Some(hk) = hold_keys {
        data["holdKeys"] = serde_json::to_value(&hk).unwrap_or(serde_json::Value::Null);
    }
    if let Some(hm) = hold_mode {
        data["holdMode"] = serde_json::Value::String(hm);
    }
    if let Some(md) = mode_data {
        data["modeData"] = md;
    }
    Some(data)
},
```

- [ ] **Step 4: Update group_cmd.rs toggle_group to send full config**

```rust
#[tauri::command]
pub async fn toggle_group(
    state: tauri::State<'_, Arc<AppState>>,
    group_id: String,
) -> Result<GroupStatus, AppError> {
    let group = state
        .get_group(&group_id)
        .ok_or_else(|| AppError::GroupNotFound(group_id.clone()))?;
    let new_active = !group.active;
    state.set_group_active(&group_id, new_active)?;

    let mode_data_value = serde_json::to_value(&group.mode_data)
        .ok()
        .filter(|v| !v.is_null());

    let cmd = IpcCommand::ToggleGroup {
        group_id: group_id.clone(),
        active: new_active,
        mode: Some(group.mode.clone()),
        key_press_duration: if group.key_press_duration > 0 { Some(group.key_press_duration) } else { None },
        hold_keys: group.hold_keys.clone(),
        hold_mode: group.hold_mode.clone(),
        mode_data: mode_data_value,
    };
    state.try_send_ipc_command(&cmd).await;

    Ok(GroupStatus {
        id: group_id,
        active: new_active,
    })
}
```

- [ ] **Step 5: Update AHK executor to use config from toggle_group data**

In `executor.ahk`, modify `_HandleToggleGroup`:

```autohotkey
static _HandleToggleGroup(data, seq) {
    groupId := CommandDispatcher._GetStr(data, "groupId", "")
    active := CommandDispatcher._GetBool(data, "active", false)

    if groupId = "" {
        IpcClient.SendResult(seq, Map("status", "error", "message", "缺少 groupId"))
        return
    }

    if active {
        if data is Map {
            if data.Has("mode") {
                CommandDispatcher._groupConfigs[groupId] := data
                CommandDispatcher._StartGroupWithConfig(groupId, data)
            } else if CommandDispatcher._groupConfigs.Has(groupId)
                CommandDispatcher._StartGroupWithConfig(groupId, CommandDispatcher._groupConfigs[groupId])
            else
                Sender.ToggleGroup(groupId, true)
        } else
            Sender.ToggleGroup(groupId, true)
    } else {
        Sender.ToggleGroup(groupId, false)
        Joystick.StopGroup(groupId)
    }

    IpcClient.SendResult(seq, Map("status", "ok", "groupId", groupId, "active", active))
}
```

- [ ] **Step 6: Update pipe_broken recovery in lib.rs to send full config**

In `lib.rs` `setup_ipc_callbacks`, update the pipe_broken recovery loop to include mode config:

```rust
for id in active_group_ids {
    let group = state.get_group(&id);
    if let Some(g) = group {
        let mode_data_value = serde_json::to_value(&g.mode_data)
            .ok()
            .filter(|v| !v.is_null());
        let cmd = IpcCommand::ToggleGroup {
            group_id: id,
            active: true,
            mode: Some(g.mode.clone()),
            key_press_duration: if g.key_press_duration > 0 { Some(g.key_press_duration) } else { None },
            hold_keys: g.hold_keys.clone(),
            hold_mode: g.hold_mode.clone(),
            mode_data: mode_data_value,
        };
        state.try_send_ipc_command(&cmd).await;
    }
}
```

- [ ] **Step 7: Run all tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test && cargo clippy`
Expected: All tests pass, zero clippy warnings

---

### Task A2: Fix joystick not stopped on deactivate (C-6)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\sender.ahk` — Add Joystick.StopGroup call
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk` — Add Joystick.StopGroup in deactivate

- [ ] **Step 1: Add Joystick.StopGroup call in Sender._StopGroup**

In `sender.ahk`, add at the end of `_StopGroup` method, before the last OutputDebug:

```autohotkey
; 停止摇杆轮询
Joystick.StopGroup(groupId)
```

- [ ] **Step 2: Add Joystick.StopGroup in EmergencyRelease**

In `sender.ahk` `EmergencyRelease`, after the hold keys release loop, add:

```autohotkey
; 紧急释放所有摇杆
Joystick.EmergencyRelease()
```

Note: This already exists in `CommandDispatcher._HandleEmergencyRelease`, but should also be in Sender for consistency.

- [ ] **Step 3: Verify AHK syntax**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\sender.ahk" 2>&1`
Expected: No syntax errors (exit code 0)

---

### Task A3: Fix recording returns empty results (C-7)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk` — Implement recording logic
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\hotkey_hook.ahk` — Add recording capture hook

- [ ] **Step 1: Add recording state to CommandDispatcher**

In `executor.ahk`, add recording state fields to `CommandDispatcher`:

```autohotkey
static _isRecording := false
static _recordedKeys := []
static _recordMode := "periodic"
static _recordGroupId := ""
```

- [ ] **Step 2: Implement _HandleStartRecording with key capture**

```autohotkey
static _HandleStartRecording(data, seq) {
    groupId := CommandDispatcher._GetStr(data, "groupId", "")
    mode := CommandDispatcher._GetStr(data, "mode", "periodic")

    if CommandDispatcher._isRecording {
        IpcClient.SendResult(seq, Map("status", "error", "message", "已在录制中"))
        return
    }

    CommandDispatcher._isRecording := true
    CommandDispatcher._recordedKeys := []
    CommandDispatcher._recordMode := mode
    CommandDispatcher._recordGroupId := groupId

    OutputDebug("CommandDispatcher: 录制开始 groupId=" groupId " mode=" mode)
    IpcClient.SendResult(seq, Map("status", "ok", "groupId", groupId, "mode", mode))
}
```

- [ ] **Step 3: Implement _HandleStopRecording with result return**

```autohotkey
static _HandleStopRecording(seq) {
    if !CommandDispatcher._isRecording {
        IpcClient.SendResult(seq, Map("status", "error", "message", "未在录制中"))
        return
    }

    CommandDispatcher._isRecording := false
    keys := CommandDispatcher._recordedKeys
    mode := CommandDispatcher._recordMode

    OutputDebug("CommandDispatcher: 录制停止 keys=" keys.Length)
    IpcClient.SendResult(seq, Map(
        "status", "ok",
        "keys", keys,
        "mode", mode,
        "count", keys.Length
    ))
}
```

- [ ] **Step 4: Add key capture in HotkeyHook._OnHotkeyPress**

In `hotkey_hook.ahk`, add recording capture in `_OnHotkeyPress`:

```autohotkey
; 录制模式：捕获按键
if CommandDispatcher._isRecording {
    CommandDispatcher._recordedKeys.Push(normalizedKey)
    OutputDebug("HotkeyHook: 录制捕获 key=" normalizedKey)
}
```

Note: This requires `#Include "executor.ahk"` or forward declaration. Since hotkey_hook.ahk is included by executor.ahk, we need to use a callback pattern instead. Add a recording callback:

In `hotkey_hook.ahk`, add:
```autohotkey
static OnKeyRecorded := ""

; In _OnHotkeyPress, after the existing code:
if HotkeyHook.OnKeyRecorded
    HotkeyHook.OnKeyRecorded.Call(normalizedKey)
```

In `executor.ahk` `Executor_Init()`, add:
```autohotkey
HotkeyHook.OnKeyRecorded := (key) => CommandDispatcher.RecordKey(key)
```

Add to CommandDispatcher:
```autohotkey
static RecordKey(key) {
    if CommandDispatcher._isRecording
        CommandDispatcher._recordedKeys.Push(key)
}
```

- [ ] **Step 5: Verify AHK syntax**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk" 2>&1`
Expected: No syntax errors

---

### Task B1: Fix hotkey events not forwarded to frontend (C-2)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\lib.rs` — Add Tauri emit for hotkey events

- [ ] **Step 1: Write failing test — hotkey event emits Tauri event**

In `lib.rs` tests (or a new test file), add:

```rust
#[cfg(test)]
mod test_tauri_events {
    use crate::domain::models::IpcMessage;

    #[test]
    fn test_hotkey_message_type_identification() {
        let msg = IpcMessage::hotkey_event(1, "F1");
        assert_eq!(msg.r#type, "hotkey");
        assert_eq!(msg.keys.as_ref().unwrap().first().unwrap(), "F1");
    }
}
```

- [ ] **Step 2: Modify spawn_ipc_listener to emit Tauri events**

Change `spawn_ipc_listener` signature to accept `AppHandle`:

```rust
fn spawn_ipc_listener(mut rx: IpcOutboundReceiver, app_state: Arc<AppState>, app_handle: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match msg.r#type.as_str() {
                "hotkey" => {
                    if let Some(keys) = &msg.keys {
                        if let Some(hotkey) = keys.first() {
                            tracing::info!("收到热键事件: {hotkey}");
                            let _ = app_handle.emit("hotkey_event", serde_json::json!({
                                "hotkey": hotkey,
                                "keys": keys,
                            }));
                        }
                    }
                }
                "result" => {
                    if let Some(ref data) = msg.data {
                        tracing::debug!("收到 IPC 结果: {:?}", data);
                    }
                }
                "heartbeat" => {
                    tracing::debug!("收到心跳");
                }
                _ => {
                    tracing::debug!("收到 IPC 消息: type={}", msg.r#type);
                }
            }
        }
    });
}
```

- [ ] **Step 3: Update spawn_ipc_listener call in setup to pass AppHandle**

In `setup()`, change:
```rust
spawn_ipc_listener(outbound_rx, app_state.clone(), app.handle().clone());
```

- [ ] **Step 4: Run tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test && cargo clippy`
Expected: All tests pass

---

### Task B2: Fix Rust never emits Tauri Events (C-3)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\lib.rs` — Add emit for state changes
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\application\state.rs` — Add AppHandle field

- [ ] **Step 1: Add AppHandle to AppState**

In `state.rs`, add:
```rust
pub struct AppState {
    pub config: RwLock<Config>,
    pub groups: RwLock<HashMap<String, SkillGroup>>,
    pub ipc_manager: tokio::sync::Mutex<Option<IpcManager>>,
    pub ipc_outbound: IpcOutboundSender,
    pub active_hotkeys: RwLock<HashMap<String, String>>,
    pub emergency_mode: AtomicBool,
    pub hold_mode_enabled: AtomicBool,
    pub watchdog_state: RwLock<WatchdogState>,
    pub watchdog: Arc<tokio::sync::Mutex<ProcessWatchdog>>,
    pub app_handle: Option<tauri::AppHandle>,
}
```

Add setter:
```rust
pub fn set_app_handle(&mut self, handle: tauri::AppHandle) {
    self.app_handle = Some(handle);
}

pub fn emit_event(&self, event: &str, payload: serde_json::Value) {
    if let Some(ref handle) = self.app_handle {
        let _ = handle.emit(event, payload);
    }
}
```

- [ ] **Step 2: Set AppHandle in setup()**

In `lib.rs` setup(), after creating AppState:
```rust
let mut app_state = Arc::new(AppState::new(config, ipc_manager.outbound_sender(), watchdog));
{
    let mut state = Arc::get_mut(&mut app_state).expect("AppState should be uniquely held during setup");
    state.set_app_handle(app.handle().clone());
}
```

- [ ] **Step 3: Add emit calls for state changes**

In `state.rs` `set_group_active`:
```rust
pub fn set_group_active(&self, id: &str, active: bool) -> Result<(), AppError> {
    let mut groups = self.groups.write().map_err(|e| AppError::Internal(e.to_string()))?;
    if let Some(group) = groups.get_mut(id) {
        group.active = active;
        if active {
            self.active_hotkeys.write().map_err(|e| AppError::Internal(e.to_string()))?.insert(id.to_string(), group.hotkey.clone());
        } else {
            self.active_hotkeys.write().map_err(|e| AppError::Internal(e.to_string()))?.remove(id);
        }
        self.emit_event("group_status_changed", serde_json::json!({
            "groupId": id,
            "active": active,
        }));
        Ok(())
    } else {
        Err(AppError::GroupNotFound(id.to_string()))
    }
}
```

In `state.rs` `update_watchdog_state`:
```rust
pub fn update_watchdog_state(&self, status: WatchdogStateEnum, restart_count: u32) {
    if let Ok(mut ws) = self.watchdog_state.write() {
        ws.status = status.clone();
        ws.restart_count = restart_count;
    }
    self.emit_event("executor_status", serde_json::json!({
        "status": status,
        "restartCount": restart_count,
    }));
}
```

- [ ] **Step 4: Run tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test && cargo clippy`
Expected: All tests pass

---

### Task D1: Fix config file uses relative path (C-5/C-20)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\domain\config.rs` — Accept path parameter
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\lib.rs` — Use app_data_dir

- [ ] **Step 1: Write failing test — Config load from custom path**

In `config.rs` tests:
```rust
#[test]
fn test_config_load_from_custom_path() {
    let temp_dir = std::env::temp_dir();
    let config_path = temp_dir.join("asd_test_config.json");
    let _ = std::fs::remove_file(&config_path);

    let config = Config::default();
    config.save_to_path(&config_path).expect("save should succeed");

    let loaded = Config::load_from_path(&config_path).expect("load should succeed");
    assert_eq!(loaded.version, config.version);

    let _ = std::fs::remove_file(&config_path);
}
```

- [ ] **Step 2: Add save_to_path and load_from_path methods to Config**

In `config.rs`:
```rust
impl Config {
    pub fn load_from_path(path: &std::path::Path) -> Result<Self, String> {
        if !path.exists() {
            let config = Config::default();
            config.save_to_path(path)?;
            return Ok(config);
        }
        let content = std::fs::read_to_string(path)
            .map_err(|e| format!("读取配置文件失败: {e}"))?;
        serde_json::from_str(&content)
            .map_err(|e| format!("解析配置文件失败: {e}"))
    }

    pub fn save_to_path(&self, path: &std::path::Path) -> Result<(), String> {
        let parent = path.parent();
        if let Some(dir) = parent {
            std::fs::create_dir_all(dir)
                .map_err(|e| format!("创建配置目录失败: {e}"))?;
        }

        let temp_path = path.with_extension("json.tmp");
        let json = serde_json::to_string_pretty(self)
            .map_err(|e| format!("序列化配置失败: {e}"))?;
        std::fs::write(&temp_path, json)
            .map_err(|e| format!("写入配置文件失败: {e}"))?;
        std::fs::rename(&temp_path, path)
            .map_err(|e| format!("重命名配置文件失败: {e}"))?;
        Ok(())
    }
}
```

- [ ] **Step 3: Add config_path to AppState**

In `state.rs`:
```rust
pub struct AppState {
    // ... existing fields ...
    pub config_path: Option<std::path::PathBuf>,
}
```

- [ ] **Step 4: Update lib.rs setup to use app_data_dir**

In `setup()`:
```rust
let config_path = app.path().app_data_dir()
    .expect("无法获取 app_data_dir")
    .join("config.json");
let config = Config::load_from_path(&config_path).unwrap_or_else(|e| {
    tracing::warn!("加载配置失败: {e}，使用默认配置");
    Config::default()
});
```

Store config_path in AppState and update save_config to use it.

- [ ] **Step 5: Update save_config command to use stored path**

In `config_cmd.rs`:
```rust
#[tauri::command]
pub fn save_config(
    state: tauri::State<'_, Arc<AppState>>,
    config: Config,
) -> Result<(), AppError> {
    let validation = ConfigValidator::validate(&config.group_settings);
    if !validation.is_valid() {
        return Err(AppError::Validation(/* ... */));
    }

    let config_path = state.config_path.clone()
        .ok_or_else(|| AppError::Config("配置路径未设置".to_string()))?;

    config.save_to_path(&config_path)
        .map_err(|e| AppError::Config(e.to_string()))?;

    // Update in-memory state
    {
        let mut guard = state.config.write().map_err(|e| AppError::Internal(e.to_string()))?;
        *guard = config;
    }
    {
        let config_snapshot = state.config.read().map_err(|e| AppError::Internal(e.to_string()))?.clone();
        let new_groups = AppState::build_groups_from_config(&config_snapshot);
        let mut groups = state.groups.write().map_err(|e| AppError::Internal(e.to_string()))?;
        *groups = new_groups;
    }
    Ok(())
}
```

- [ ] **Step 6: Run tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test && cargo clippy`
Expected: All tests pass

---

### Task D2: Fix save_config non-atomic (C-9)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\domain\config.rs` — Atomic write (temp+rename)

- [ ] **Step 1: Already implemented in D1 Step 2**

The `save_to_path` method in D1 already uses temp file + rename for atomic writes. No additional changes needed.

- [ ] **Step 2: Update save_config to update memory first, then write**

In `config_cmd.rs`, reorder: update memory state first, then write to file. If write fails, rollback memory.

---

### Task E1: Fix key injection vulnerability (C-13)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\sender.ahk` — Add key whitelist validation

- [ ] **Step 1: Add key whitelist to Sender**

In `sender.ahk`, add at the top of the class:

```autohotkey
static ALLOWED_KEYS := Map(
    ; Function keys
    "F1", true, "F2", true, "F3", true, "F4", true, "F5", true, "F6", true,
    "F7", true, "F8", true, "F9", true, "F10", true, "F11", true, "F12", true,
    ; Number keys
    "1", true, "2", true, "3", true, "4", true, "5", true,
    "6", true, "7", true, "8", true, "9", true, "0", true,
    ; Letter keys
    "a", true, "b", true, "c", true, "d", true, "e", true, "f", true,
    "g", true, "h", true, "i", true, "j", true, "k", true, "l", true,
    "m", true, "n", true, "o", true, "p", true, "q", true, "r", true,
    "s", true, "t", true, "u", true, "v", true, "w", true, "x", true,
    "y", true, "z", true,
    ; Special keys
    "Space", true, "Enter", true, "Tab", true, "Esc", true, "Backspace", true,
    "Delete", true, "Insert", true, "Home", true, "End", true,
    "PgUp", true, "PgDn", true,
    ; Arrow keys
    "Up", true, "Down", true, "Left", true, "Right", true,
    ; Modifier keys
    "Shift", true, "Ctrl", true, "Alt", true, "LWin", true, "RWin", true,
    "LShift", true, "RShift", true, "LCtrl", true, "RCtrl", true,
    "LAlt", true, "RAlt", true,
    ; Numpad
    "Numpad0", true, "Numpad1", true, "Numpad2", true, "Numpad3", true,
    "Numpad4", true, "Numpad5", true, "Numpad6", true, "Numpad7", true,
    "Numpad8", true, "Numpad9", true,
    "NumpadEnter", true, "NumpadAdd", true, "NumpadSub", true,
    "NumpadMult", true, "NumpadDiv", true,
    ; Joystick keys (vJoy)
    "Joy1", true, "Joy2", true, "Joy3", true, "Joy4", true,
    "Joy5", true, "Joy6", true, "Joy7", true, "Joy8", true,
    "JoyX", true, "JoyY", true, "JoyZ", true, "JoyR", true,
    "JoyU", true, "JoyV", true, "JoyPOV", true,
)
```

- [ ] **Step 2: Add validation in _SendKeyDown and _SendKeyUp**

```autohotkey
static _ValidateKey(key) {
    if Sender.ALLOWED_KEYS.Has(key)
        return true
    OutputDebug("Sender: 按键被拒绝（不在白名单中） key=" key)
    return false
}

static _SendKeyDown(key) {
    if !Sender._ValidateKey(key)
        return
    try {
        SendInput("{Blind}{" key " Down}")
    } catch as e {
        OutputDebug("Sender: 按键按下失败 key=" key " err=" e.Message)
    }
}

static _SendKeyUp(key) {
    if !Sender._ValidateKey(key)
        return
    try {
        SendInput("{Blind}{" key " Up}")
    } catch as e {
        OutputDebug("Sender: 按键释放失败 key=" key " err=" e.Message)
    }
}
```

- [ ] **Step 3: Verify AHK syntax**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\sender.ahk" 2>&1`
Expected: No syntax errors

---

### Task E2: Fix Named Pipe authentication (C-14)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\infrastructure\ipc.rs` — Add handshake validation
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\ipc_client.ahk` — Send auth token on connect

- [ ] **Step 1: Add handshake token constant**

In `ipc.rs`:
```rust
const IPC_AUTH_TOKEN: &str = "ASD_IPC_AUTH_V1";
```

- [ ] **Step 2: Add handshake validation in accept_from_ahk**

In `ipc.rs` `accept_from_ahk`, after accepting connection, read first message and validate:

```rust
pub async fn accept_from_ahk(&self, listener: &Listener) -> Result<(), IpcError> {
    use interprocess::local_socket::traits::tokio::Listener as ListenerTrait;
    let stream = listener.accept().await.map_err(|e| IpcError::IoError(e.to_string()))?;
    let (recv, send) = stream.split();

    *self.send_half.lock().await = Some(send);
    *self.recv_half.lock().await = Some(BufReader::new(recv));

    // Validate handshake
    match self.recv().await {
        Ok(msg) if msg.r#type == "auth" => {
            if let Some(ref data) = msg.data {
                if data.get("token").and_then(|t| t.as_str()) == Some(IPC_AUTH_TOKEN) {
                    tracing::info!("IPC 客户端认证成功");
                    // Send auth success response
                    let resp = IpcMessage::response(msg.seq, msg.seq, "ok", Some(serde_json::json!({"auth": true})));
                    let _ = self.send(&resp).await;
                    return Ok(());
                }
            }
            tracing::warn!("IPC 客户端认证失败：token 不匹配");
            *self.send_half.lock().await = None;
            *self.recv_half.lock().await = None;
            Err(IpcError::IoError("认证失败".to_string()))
        }
        Ok(_) => {
            tracing::warn!("IPC 客户端认证失败：首条消息类型不是 auth");
            *self.send_half.lock().await = None;
            *self.recv_half.lock().await = None;
            Err(IpcError::IoError("认证失败：首条消息类型不是 auth".to_string()))
        }
        Err(e) => {
            tracing::warn!("IPC 客户端认证失败：{e}");
            Err(e)
        }
    }
}
```

- [ ] **Step 3: Add auth message send in AHK ipc_client.ahk**

In `ipc_client.ahk`, after successful connection in `_TryConnect`, add:

```autohotkey
; 发送认证消息
authMsg := Map(
    "type", "auth",
    "seq", IpcClient._NextSeq(),
    "data", Map("token", "ASD_IPC_AUTH_V1")
)
IpcClient._SendMsg(authMsg)
```

- [ ] **Step 4: Verify AHK syntax**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\ipc_client.ahk" 2>&1`
Expected: No syntax errors

- [ ] **Step 5: Run Rust tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test && cargo clippy`
Expected: All tests pass

---

### Task F1: Fix build_ahk.ps1 hardcoded paths (C-17)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\build_ahk.ps1` — Use environment variables

- [ ] **Step 1: Replace hardcoded paths with env-based detection**

```powershell
$ahkCompiler = if ($env:AHK_COMPILER) { $env:AHK_COMPILER } else { "D:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" }
$ahkBin = if ($env:AHK_BIN) { $env:AHK_BIN } else { "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" }
```

- [ ] **Step 2: Add auto-detection fallback**

```powershell
if (-not (Test-Path $ahkBin)) {
    $ahkBin = Get-ChildItem "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not (Test-Path $ahkBin)) {
    $ahkBin = Get-ChildItem "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
```

---

### Task F2: Fix wildcard resources (C-18)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\tauri.conf.json` — Specify exact files

- [ ] **Step 1: Replace wildcard with specific files**

```json
"resources": [
    "ahk_executor/asd_executor.exe",
    "ahk_executor/executor.ahk",
    "ahk_executor/ipc_client.ahk",
    "ahk_executor/hotkey_hook.ahk",
    "ahk_executor/sender.ahk",
    "ahk_executor/joystick.ahk"
]
```

Note: Also include AutoHotkey64.exe and asd_executor.bat for portable mode fallback.

---

### Task F3: Fix empty updater config (C-16)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\tauri.conf.json` — Remove updater config
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\Cargo.toml` — Remove updater dependency

- [ ] **Step 1: Remove updater plugin from tauri.conf.json**

Remove the `"plugins"` section entirely or set it to empty:
```json
"plugins": {}
```

- [ ] **Step 2: Remove tauri-plugin-updater from Cargo.toml**

Remove line: `tauri-plugin-updater = "2.10.1"`

- [ ] **Step 3: Remove updater plugin registration from lib.rs**

Remove: `.plugin(tauri_plugin_updater::Builder::new().build())`

- [ ] **Step 4: Run cargo check**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo check`
Expected: Compiles successfully

---

### Task F4: Fix blocking_lock() deadlock risk (C-19)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\src\lib.rs` — Replace blocking_lock with async

- [ ] **Step 1: Replace blocking_lock() in setup with structured async init**

In `setup()`, the two `blocking_lock()` calls need to be restructured:

Replace:
```rust
{
    let mut ipc_mgr = app_state.ipc_manager.blocking_lock();
    *ipc_mgr = Some(ipc_manager);
}
```

With a pre-initialization approach — set IPC manager before spawning tasks:
```rust
// Pre-initialize IPC manager before spawning async tasks
{
    let mut ipc_mgr = app_state.ipc_manager.blocking_lock();
    *ipc_mgr = Some(ipc_manager);
}
```

Actually, `blocking_lock()` in `setup()` is safe because the tokio runtime hasn't started processing tasks yet. But to be safe, we can use `tokio::task::block_in_place`:

```rust
tokio::task::block_in_place(|| {
    let mut ipc_mgr = app_state.ipc_manager.blocking_lock();
    *ipc_mgr = Some(ipc_manager);
});
```

Same for the watchdog spawn_child call.

- [ ] **Step 2: Run tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test && cargo clippy`
Expected: All tests pass

---

### Task F5: Fix missing JS plugin bindings (C-15)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\package.json` — Add @tauri-apps/plugin-* packages

- [ ] **Step 1: Add JS plugin packages**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri && npm install @tauri-apps/plugin-global-shortcut @tauri-apps/plugin-dialog @tauri-apps/plugin-fs`

- [ ] **Step 2: Verify package.json updated**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri && cat package.json | Select-String "plugin-"`

---

## Wave 2: Dependent Groups

### Task C1: Fix saveConfig format mismatch (C-4)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src\main.js` — Ensure frontend sends full Config
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src\api.js` — Verify saveConfig passes full config

- [ ] **Step 1: Verify frontend sends complete Config structure**

The `save_config` Rust command expects a `Config` struct with `control_hotkeys`, `group_settings`, `hold_settings`, etc. The frontend must send the complete structure.

In `api.js`, `saveConfig(config)` already passes the config object directly. Verify that `main.js` builds the complete Config object before calling save.

- [ ] **Step 2: Fix any format mismatches in main.js**

Ensure the config object built in main.js matches Rust's Config struct:
- `control_hotkeys` → `ControlHotkeys` (camelCase matches serde default)
- `group_settings` → `HashMap<String, GroupConfig>` (must be object with string keys)
- `hold_settings` → `Option<HoldSettings>` (can be null)
- `version` → `Option<String>` (can be null)

---

### Task C2: Fix startRecording empty groupId (C-10)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src\main.js` — Pass actual groupId

- [ ] **Step 1: Find and fix the startRecording call**

In `main.js`, find where `startRecording` is called and ensure it passes the current editor's groupId:

```javascript
// Before (broken):
await startRecording('', currentMode);

// After (fixed):
await startRecording(editorConfig.groupId || currentGroupId, currentMode);
```

---

### Task C3: Fix getGroupDetail format mismatch (C-11)

**Files:**
- Modify: `d:\1demo\AutoHotkeydemo\asd-tauri\src\main.js` — Handle nested mode_data format

- [ ] **Step 1: Verify frontend handles SkillGroup response correctly**

The Rust `get_group_detail` returns `SkillGroup` which includes `mode_data` (nested ModeData enum). The frontend must read `mode_data` to extract keys/intervals/delays.

Verify that the editor loading code reads from `group.modeData` (camelCase via serde) instead of flat `group.keys`/`group.intervals`.

---

## Integration Verification

### Task INT1: Full integration test

- [ ] **Step 1: Run all Rust tests**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo test`
Expected: All tests pass

- [ ] **Step 2: Run cargo clippy**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo clippy -- -D warnings`
Expected: Zero warnings

- [ ] **Step 3: AHK syntax check all files**

Run: `& "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut "d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri\ahk_executor\executor.ahk" 2>&1`
Expected: No syntax errors

- [ ] **Step 4: Build release**

Run: `cd d:\1demo\AutoHotkeydemo\asd-tauri\src-tauri && cargo build --release`
Expected: Build succeeds
