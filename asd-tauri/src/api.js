import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { getVersion } from '@tauri-apps/api/app';
import { appDataDir } from '@tauri-apps/api/path';

export async function getGroups() {
  return invoke('get_groups');
}

export async function toggleGroup(groupId) {
  return invoke('toggle_group', { groupId });
}

export async function getGroupDetail(groupId) {
  return invoke('get_group_detail', { groupId });
}

export async function saveConfig(config) {
  return invoke('save_config', { config });
}

export async function getConfig() {
  return invoke('get_config');
}

export async function validateConfig(config) {
  return invoke('validate_config', { config });
}

export async function emergencyRelease() {
  return invoke('emergency_release');
}

export async function clearEmergency() {
  return invoke('clear_emergency');
}

export async function getExecutorStatus() {
  return invoke('get_executor_status');
}

export async function resetWatchdog() {
  return invoke('reset_watchdog');
}

// 启动时配置文件加载失败的记录；正常加载（含首次启动）为 null。
// Rust 侧已按错误类型分流：文件不存在 = 首次启动，**不会**出现在这里（B6 / TD-084）。
export async function getConfigLoadFailure() {
  return invoke('get_config_load_failure');
}

export async function toggleHoldMode() {
  return invoke('toggle_hold_mode');
}

export async function registerHotkey(hotkey, groupId) {
  return invoke('register_hotkey', { hotkey, groupId });
}

export async function unregisterHotkey(hotkey) {
  return invoke('unregister_hotkey', { hotkey });
}

export async function startRecording(groupId, mode) {
  return invoke('start_recording', { groupId, mode });
}

export async function stopRecording() {
  return invoke('stop_recording');
}

export async function batchToggleGroups(ids, activate) {
  return invoke('batch_toggle_groups', { groupIds: ids, active: activate });
}

export async function batchDeleteGroups(ids) {
  return invoke('batch_delete_groups', { groupIds: ids });
}

export async function deleteGroup(id) {
  return invoke('delete_group', { groupId: id });
}

export async function hotReload() {
  return invoke('hot_reload', {});
}

export async function createBackup() {
  return invoke('create_backup', {});
}

export async function restoreBackup(name) {
  return invoke('restore_backup', { filename: name });
}

export async function deleteBackup(name) {
  return invoke('delete_backup', { filename: name });
}

export async function listBackups() {
  return invoke('list_backups', {});
}

export async function compareConfigs(backupFilename) {
  return invoke('compare_configs', { backupFilename });
}

export async function exportConfig(path) {
  return invoke('export_config', { path });
}

export async function importConfig(path) {
  return invoke('import_config', { path });
}

export async function reorderGroups(orderIds) {
  return invoke('reorder_groups', { groupIds: orderIds });
}

export async function pauseRecording() {
  return invoke('pause_recording', {});
}

export async function resumeRecording() {
  return invoke('resume_recording', {});
}

// ⚠️ 参数必须与 Rust 命令 export_recording(path, keys, intervals, delays, mode) 一一对应。
// 这里原先漏了 delays —— Tauri 会以「missing required key delays」拒收，调用必失败。
// 契约测试 src/__tests__/api_contract.test.js 会守住这条。
export async function exportRecording(path, keys, intervals, delays, mode) {
  return invoke('export_recording', { path: path, keys: keys, intervals: intervals, delays: delays, mode: mode });
}

export async function importRecording(path) {
  return invoke('import_recording', { path: path });
}

export async function getGroupListForValidation() {
  return getGroups();
}

export async function startValidation(groupId) {
  return invoke('start_validation', { groupId });
}

export async function stopValidation() {
  return invoke('stop_validation', {});
}

export async function toggleAll(active) {
  return invoke('toggle_all', { active: active });
}

export function onStatusUpdate(callback) {
  return listen('status_update', (event) => callback(event.payload));
}

export function onHotkeyEvent(callback) {
  return listen('hotkey_event', (event) => callback(event.payload));
}

export function onExecutorStatus(callback) {
  return listen('executor_status', (event) => callback(event.payload));
}

export function onKeyRecordEvent(callback) {
  return listen('key_record_event', (event) => callback(event.payload));
}

export function onKeySendEvent(callback) {
  return listen('key_send_event', (event) => callback(event.payload));
}

// IPC 监听端创建失败（管道名被占用等）—— 此时 AHK 永远连不上，必须让用户看见。
export function onIpcListenerFailed(callback) {
  return listen('ipc:listener-failed', (event) => callback(event.payload));
}

// ── 诊断信息（TD-076：运行时遥测缺位的低成本先行项）───────────────────────
// 这两个都不走自定义 command，直接用 Tauri 内置能力，因此**不需要新增 Rust 命令**：
//   getVersion()  -> plugin:app|version            （权限 core:app:allow-version）
//   appDataDir()  -> plugin:path|resolve_directory （权限 core:path:allow-resolve-directory）
// 二者都已被 capabilities/default.json 里的 `core:default` 覆盖，无需改 capabilities。
// 日志落点与 Rust 侧 logging.rs 一致：app_data_dir 下的 asd.YYYY-MM-DD.log（保留 7 份）。
export async function getAppVersion() {
  return getVersion();
}

export async function getLogDirPath() {
  return appDataDir();
}
