import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

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

export async function exportRecording(path, keys, intervals, mode) {
  return invoke('export_recording', { path: path, keys: keys, intervals: intervals, mode: mode });
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
