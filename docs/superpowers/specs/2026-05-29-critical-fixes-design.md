# Critical Issues Fix Design - 20 Critical Bugs

> Date: 2026-05-29
> Status: Approved
> Scope: Fix all 20 Critical issues identified by 5 parallel architecture reviews

## Architecture Context

- **Rust/Tauri main process** (asd.exe) + **AHK execution subprocess** (asd_executor.exe)
- **Dual IPC**: Tauri invoke/emit (JS↔Rust) + Named Pipe JSON Lines (Rust↔AHK)
- **Rust is IPC server** (listens), AHK is client (connects to `\\.\pipe\asd_ipc`)

## Work Groups

### Group A: IPC Protocol & AHK Subprocess (C-1, C-6, C-7)

**C-1: toggle_group missing mode config (P0 - System non-functional)**

- Root cause: `IpcCommand::ToggleGroup { group_id, active }` only sends groupId+active. AHK's `_HandleToggleGroup` receives no mode/keys/intervals info.
- Fix: Extend `IpcCommand::ToggleGroup` data payload to include full group config. In `IpcMessage::command()`, serialize the group's mode_data into the data field. AHK's `_HandleToggleGroup` already has `_StartGroupWithConfig` that reads mode config from data.
- Files: `domain/models.rs` (ToggleGroup data), `commands/group_cmd.rs` (send config), `ahk_executor/executor.ahk` (receive config)

**C-6: Joystick not stopped on deactivate (P0)**

- Root cause: `Sender._StopGroup` and `CommandDispatcher._HandleToggleGroup(active=false)` don't call `Joystick.StopGroup`.
- Fix: Add `Joystick.StopGroup(groupId)` call when deactivating a group.
- Files: `ahk_executor/sender.ahk`, `ahk_executor/executor.ahk`

**C-7: Recording returns empty results (P1)**

- Root cause: `_HandleStartRecording`/`_HandleStopRecording` are stubs.
- Fix: Implement key capture during recording using AHK's InputHook, return captured keys in stop_recording result.
- Files: `ahk_executor/executor.ahk`

### Group B: Tauri Event System (C-2, C-3)

**C-2: Hotkey events not forwarded to frontend (P0)**

- Root cause: `spawn_ipc_listener` logs hotkey events but never emits Tauri events.
- Fix: Add `app_handle.emit("hotkey_event", payload)` in hotkey handler. Need to pass AppHandle to the listener.
- Files: `lib.rs`

**C-3: Rust never emits Tauri Events (P0)**

- Root cause: No `app_handle.emit()` calls for state changes anywhere.
- Fix: Add emit calls for: watchdog state changes, group toggle, config save, recording status.
- Files: `lib.rs`, `application/state.rs`

### Group C: Frontend Integration (C-4, C-10, C-11, C-12)

**C-4: saveConfig format mismatch (P0)**

- Root cause: Frontend sends partial config, Rust expects full `Config` struct.
- Fix: Ensure frontend sends complete Config matching Rust schema. The `save_config` command already accepts `Config` type.
- Files: `src/api.js`, `src/main.js`

**C-10: startRecording empty groupId (P1)**

- Root cause: Frontend doesn't pass current group's ID.
- Fix: Pass actual groupId from editor state.
- Files: `src/main.js`

**C-11: getGroupDetail format mismatch (P1)**

- Root cause: Rust returns `SkillGroup` with nested `mode_data`, frontend expects flat format.
- Fix: Frontend already has mode_data handling via MODE_INFO. Ensure the frontend correctly reads `mode_data` field.
- Files: `src/main.js`

**C-12: WatchdogStateEnum missing Serialize (Already Fixed)**

- The code already has `#[derive(Debug, Clone, PartialEq, Serialize)]` on `WatchdogStateEnum`.
- No changes needed.

### Group D: Config & Path Management (C-5/C-20, C-9)

**C-5/C-20: Config file uses relative path (P0)**

- Root cause: `Config::load_default()` uses relative "config.json", will fail in Program Files.
- Fix: Use Tauri's `app_data_dir` for config path. Store path in AppState.
- Files: `domain/config.rs`, `application/state.rs`, `lib.rs`

**C-9: save_config non-atomic (P1)**

- Root cause: File write then memory update, non-atomic.
- Fix: Write to temp file then rename (atomic). Or update memory first then write.
- Files: `domain/config.rs`, `commands/config_cmd.rs`

### Group E: Security (C-13, C-14)

**C-13: Key injection vulnerability (P0)**

- Root cause: AHK `SendInput` called with unvalidated key names.
- Fix: Add key name whitelist in AHK `_SendKeyDown`/`_SendKeyUp`.
- Files: `ahk_executor/sender.ahk`

**C-14: Named Pipe authentication (P1)**

- Root cause: No authentication on pipe connections.
- Fix: Add handshake validation - AHK sends a token on connect, Rust validates.
- Files: `ahk_executor/ipc_client.ahk`, `infrastructure/ipc.rs`

### Group F: Build & Deploy (C-15, C-16, C-17, C-18, C-19)

**C-15: Missing JS plugin bindings (P1)**

- Fix: Add @tauri-apps/plugin-* JS packages to frontend package.json.
- Files: `package.json`

**C-16: Empty updater config (P2)**

- Fix: Remove updater plugin or add proper config.
- Files: `tauri.conf.json`, `Cargo.toml`

**C-17: Hardcoded paths in build_ahk.ps1 (P1)**

- Fix: Use environment variables or relative paths.
- Files: `build_ahk.ps1`

**C-18: Wildcard resources (P2)**

- Fix: Specify exact files.
- Files: `tauri.conf.json`

**C-19: blocking_lock() deadlock risk (P1)**

- Root cause: `blocking_lock()` in `setup()` can deadlock if tokio runtime is busy.
- Fix: Use `tokio::task::block_in_place` with `lock().await`, or restructure to avoid blocking.
- Files: `lib.rs`

## Execution Plan

- **Wave 1** (5 parallel TDD sub-agents): Groups A, B, D, E, F
- **Wave 2** (1 TDD sub-agent): Group C (depends on B's Tauri events)
- **Integration**: Full test suite + cargo clippy + AHK syntax check
