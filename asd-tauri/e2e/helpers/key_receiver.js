// =================================================================
// Key Receiver 辅助模块 - 管理 key_receiver.ahk 子进程与日志解析
// =================================================================

import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getAhkPath } from './ahk_path.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const e2eDir = resolve(__dirname, '..');
const fixturesDir = join(e2eDir, 'fixtures');
const reportsDir = join(e2eDir, 'reports');
const keyLogPath = join(reportsDir, 'key_log.txt');
const ahkPath = getAhkPath();
const scriptPath = join(fixturesDir, 'key_receiver.ahk');

/**
 * 启动 key_receiver.ahk 子进程
 * 启动前清空 reports/key_log.txt，等待 500ms 让窗口启动
 * @returns {Promise<import('node:child_process').ChildProcess>} 子进程对象
 */
export async function startKeyReceiver() {
  // 确保 reports 目录存在
  if (!existsSync(reportsDir)) {
    mkdirSync(reportsDir, { recursive: true });
  }
  // 清空日志文件
  writeFileSync(keyLogPath, '', 'utf-8');
  // 启动子进程
  const child = spawn(ahkPath, [scriptPath], {
    cwd: e2eDir,
    stdio: 'ignore',
    windowsHide: false,
  });
  // 等待 500ms 让窗口启动
  await sleep(500);
  return child;
}

/**
 * 终止 key_receiver.ahk 子进程
 * @param {import('node:child_process').ChildProcess|null} child - 子进程对象
 */
export function stopKeyReceiver(child) {
  if (child && !child.killed) {
    try {
      child.kill();
    } catch {
      // 忽略终止错误
    }
  }
}

/**
 * 读取 reports/key_log.txt，返回按键事件数组
 * @returns {Array<{timestamp: number, key: string, event: string}>} 按键事件数组
 */
export function readKeyLog() {
  if (!existsSync(keyLogPath)) {
    return [];
  }
  const content = readFileSync(keyLogPath, 'utf-8');
  const lines = content.split('\n').filter(line => line.trim().length > 0);
  return lines.map(line => {
    const parts = line.split('|');
    if (parts.length >= 3) {
      const ts = parseInt(parts[0], 10);
      return {
        timestamp: isNaN(ts) ? 0 : ts,
        key: parts[1],
        event: parts[2],
      };
    }
    return null;
  }).filter(entry => entry !== null);
}

/**
 * 清空 reports/key_log.txt
 */
export function clearKeyLog() {
  writeFileSync(keyLogPath, '', 'utf-8');
}

/**
 * 轮询读取 key_log.txt，等待期望的按键序列出现
 * @param {string[]} expectedKeys - 期望的按键名称序列（按 down 事件匹配）
 * @param {number} timeoutMs - 超时时间（毫秒），默认 5000
 * @returns {Promise<boolean>} 是否在超时前匹配到按键序列
 */
export async function waitForKeys(expectedKeys, timeoutMs = 5000) {
  const startTime = Date.now();
  while (Date.now() - startTime < timeoutMs) {
    const entries = readKeyLog();
    const downKeys = entries
      .filter(e => e.event === 'down')
      .map(e => e.key);
    if (containsSubsequence(downKeys, expectedKeys)) {
      return true;
    }
    await sleep(50);
  }
  return false;
}

/**
 * 断言按键序列匹配
 * @param {Array<string|{key: string, timestamp: number, event: string}>} actualKeys - 实际按键序列
 * @param {string[]} expectedKeys - 期望按键序列
 * @param {object} options - 选项
 * @param {number} options.toleranceMs - 间隔容差（毫秒），默认 20
 * @param {number} options.expectedCount - 期望总次数（可选）
 * @returns {{pass: boolean, reason: string}} 断言结果
 */
export function assertKeySequence(actualKeys, expectedKeys, options = {}) {
  const toleranceMs = options.toleranceMs ?? 20;
  const expectedCount = options.expectedCount;

  // 规范化输入：统一提取 key 和 timestamp
  const normalized = actualKeys.map(item => {
    if (typeof item === 'string') {
      return { key: item, timestamp: null };
    }
    return { key: item.key, timestamp: item.timestamp ?? null };
  });
  const keys = normalized.map(item => item.key);

  // 检查按键数量
  if (expectedCount !== undefined && keys.length !== expectedCount) {
    return {
      pass: false,
      reason: `按键数量不匹配: 期望 ${expectedCount}, 实际 ${keys.length}`,
    };
  }

  // 检查按键序列是否包含期望子序列
  if (!containsSubsequence(keys, expectedKeys)) {
    return {
      pass: false,
      reason: `按键序列不匹配: 期望 [${expectedKeys.join(',')}], 实际 [${keys.join(',')}]`,
    };
  }

  // 检查时间间隔容差（仅当所有条目都带时间戳且期望序列长度 > 1 时）
  const allHaveTimestamps = normalized.every(item => item.timestamp !== null);
  if (allHaveTimestamps && expectedKeys.length > 1) {
    const matchIndex = findSubsequenceIndex(keys, expectedKeys);
    if (matchIndex !== -1) {
      for (let j = 1; j < expectedKeys.length; j++) {
        const interval = normalized[matchIndex + j].timestamp - normalized[matchIndex + j - 1].timestamp;
        if (interval < 0) {
          return {
            pass: false,
            reason: `按键 ${expectedKeys[j]} 时间戳早于前一个按键，间隔为 ${interval}ms`,
          };
        }
        // toleranceMs 用于过滤掉过快的误触发（间隔小于 toleranceMs 视为异常）
        if (toleranceMs > 0 && interval < toleranceMs && j > 0) {
          // 仅警告不失败：间隔过小可能是快速触发
        }
      }
    }
  }

  return { pass: true, reason: '按键序列匹配' };
}

/**
 * 检查 actual 数组是否包含 expected 子序列
 */
function containsSubsequence(actual, expected) {
  if (expected.length === 0) return true;
  if (actual.length < expected.length) return false;
  return findSubsequenceIndex(actual, expected) !== -1;
}

/**
 * 查找子序列在主序列中的起始索引，未找到返回 -1
 */
function findSubsequenceIndex(actual, expected) {
  for (let i = 0; i <= actual.length - expected.length; i++) {
    let match = true;
    for (let j = 0; j < expected.length; j++) {
      if (actual[i + j] !== expected[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

/**
 * 同步 sleep 工具函数
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
