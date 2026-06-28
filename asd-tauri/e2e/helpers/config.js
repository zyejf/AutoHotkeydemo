// =================================================================
// Config 辅助模块 - 管理用户配置备份/恢复与测试配置加载
// =================================================================

import fsExtra from 'fs-extra';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { invoke } from './tauri.js';

const { copyFileSync, existsSync, unlinkSync, readFileSync } = fsExtra;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const e2eDir = resolve(__dirname, '..');
const projectRoot = resolve(e2eDir, '../../..');
const fixturesDir = join(e2eDir, 'fixtures');
const userConfigPath = join(projectRoot, 'config.json');
const backupPath = join(projectRoot, 'config.json.e2e-backup');
const testConfigPath = join(fixturesDir, 'test_config.json');

/**
 * 备份项目根目录的 config.json 到 config.json.e2e-backup
 * @returns {string|null} 备份文件路径，若原文件不存在则返回 null
 */
export function backupUserConfig() {
  if (existsSync(userConfigPath)) {
    copyFileSync(userConfigPath, backupPath);
    return backupPath;
  }
  return null;
}

/**
 * 从 config.json.e2e-backup 恢复用户配置，并删除备份文件
 * @returns {boolean} 是否成功恢复
 */
export function restoreUserConfig() {
  if (existsSync(backupPath)) {
    copyFileSync(backupPath, userConfigPath);
    try {
      unlinkSync(backupPath);
    } catch {
      // 忽略删除备份文件的错误
    }
    return true;
  }
  return false;
}

/**
 * 读取 fixtures/test_config.json，返回 JSON 对象
 * @returns {object} 测试配置对象
 */
export function loadTestConfig() {
  const content = readFileSync(testConfigPath, 'utf-8');
  return JSON.parse(content);
}

/**
 * 通过 Tauri save_config 命令写入测试配置
 * @param {object} browser - WebDriverIO browser 实例
 * @param {object} config - Config 结构体
 * @returns {Promise<any>} 命令返回结果
 */
export async function saveTestConfig(browser, config) {
  return invoke(browser, 'save_config', { config });
}

/**
 * 读取项目根目录的 config.json，返回 JSON 对象
 * @returns {object} 用户配置对象
 */
export function loadConfigFromDisk() {
  const content = readFileSync(userConfigPath, 'utf-8');
  return JSON.parse(content);
}

/**
 * 通过 Tauri validate_config 命令验证配置
 * @param {object} browser - WebDriverIO browser 实例
 * @param {object} config - Config 结构体
 * @returns {Promise<any>} 验证结果（ValidationResult）
 */
export async function validateConfig(browser, config) {
  return invoke(browser, 'validate_config', { config });
}
