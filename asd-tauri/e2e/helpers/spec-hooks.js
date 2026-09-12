// =================================================================
// 共享 spec 生命周期钩子工厂 - 消除 9 个 spec 文件的重复生命周期逻辑
// =================================================================
// 抽象了 E2E spec 中重复出现的四段生命周期：
//   before      - binary 检查 + startApp + backupUserConfig + 写入初始配置
//   beforeEach  - binary 缺失时 skip 所有测试（不 fail）
//   afterEach   - appendResult + 失败时 appendKnownIssue（severity 集中定义）
//   after       - (可选额外清理) + restoreUserConfig + closeApp
//
// 用例编号格式保持 E2E-<SUITE>-NNN 不变，caseId 提取逻辑集中于此。
// =================================================================
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startApp, closeApp } from './tauri.js';
import {
  backupUserConfig,
  restoreUserConfig,
  loadTestConfig,
  saveTestConfig,
} from './config.js';
import { appendResult, appendKnownIssue } from './report.js';

/**
 * 失败严重级别统一约定：E2E 用例失败统一记录为 HIGH。
 * 所有 spec 不再硬编码 'HIGH'，从本常量派生。
 */
export const DEFAULT_FAILURE_SEVERITY = 'HIGH';

/**
 * 统一 caseId 提取：匹配 E2E-<SUITE>-NNN（如 E2E-CFG-001）。
 * 各 suite 前缀不同（CFG/GRP/HK/REC/SYS/MODE/IPC/KEY），统一用同一正则收敛。
 * @param {string} title - 测试标题
 * @returns {string} 匹配到的 caseId，未匹配则返回原标题
 */
const CASE_ID_RE = /E2E-[A-Z]+-\d+/;
export function extractCaseId(title) {
  if (typeof title !== 'string') return title;
  return title.match(CASE_ID_RE)?.[0] || title;
}

/**
 * 从 spec 文件的 import.meta.url 解析 binary 绝对路径
 * @param {string} importMetaUrl - 当前 spec 的 import.meta.url
 * @returns {string} asd-tauri.exe 绝对路径
 */
export function resolveBinaryPath(importMetaUrl) {
  const __dirname = dirname(fileURLToPath(importMetaUrl));
  return resolve(__dirname, '../../target/debug/asd-tauri.exe');
}

/**
 * 记录单个测试结果；失败时追加已知问题（severity 使用集中约定）。
 * @param {object} test - Mocha this.currentTest
 * @param {string} suiteLabel - 套件标题（test.parent 缺失时的兜底）
 * @param {string} [suggestion] - 失败时的修复建议
 */
export function reportAfterEach(test, suiteLabel, suggestion = '检查相关测试实现与断言') {
  if (!test) return;
  const suiteName = test.parent?.title || suiteLabel;
  const testName = `${suiteName} > ${test.title}`;
  const status =
    test.state === 'passed' ? 'PASS' : test.state === 'failed' ? 'FAIL' : 'SKIP';
  const duration = test.duration || 0;
  const errorMsg = test.err ? test.err.message || String(test.err) : '';
  appendResult(testName, status, duration, errorMsg);
  if (test.state === 'failed') {
    const caseId = extractCaseId(test.title);
    appendKnownIssue(
      `ISSUE-${caseId}`,
      DEFAULT_FAILURE_SEVERITY,
      `执行测试用例 ${test.title}`,
      '测试应通过',
      errorMsg,
      `E2E 测试失败: ${test.title}`,
      suggestion,
      caseId
    );
  }
}

/**
 * 注册标准生命周期钩子（before/beforeEach/afterEach/after）。
 * 必须在顶层 describe 回调内调用（Mocha hooks 绑定到当前 suite）。
 *
 * @param {object} options
 * @param {string} options.suiteLabel - 套件标题（用于 skip 消息与结果兜底）
 * @param {string} options.binaryPath - asd-tauri.exe 绝对路径
 * @param {(browser: object) => Promise<void>} [options.setupConfig]
 *   覆盖默认的初始配置写入（默认 loadTestConfig + saveTestConfig）
 * @param {(ctx: {browser: object, state: object}) => Promise<void>} [options.beforeExtra]
 *   startApp + 备份 + 写入配置之后、before 结束前的额外初始化
 * @param {() => Promise<void>} [options.afterEachCleanup]
 *   每个用例结果记录之后执行的额外清理
 * @param {(ctx: {browser: object, state: object}) => Promise<void>} [options.afterExtra]
 *   restore+close 之前的额外清理（如关闭 key_receiver、停止分组）
 * @param {string} [options.suggestion] - 失败时记录到已知问题的修复建议
 * @returns {{binaryAvailable: boolean, appStarted: boolean}} 生命周期共享状态
 */
export function registerStandardLifecycle(options) {
  const {
    suiteLabel,
    binaryPath,
    setupConfig,
    beforeExtra,
    afterEachCleanup,
    afterExtra,
    suggestion,
  } = options;

  const state = { binaryAvailable: false, appStarted: false };

  before(async function () {
    this.timeout(60000);
    if (!existsSync(binaryPath)) {
      // binary 不存在，跳过所有测试（不 fail）
      return;
    }
    state.binaryAvailable = true;
    await startApp(browser);
    state.appStarted = true;
    // 备份用户配置（同步操作）
    backupUserConfig();
    // 写入初始配置（默认加载 test_config），差异可用 setupConfig 覆盖
    if (setupConfig) {
      await setupConfig(browser);
    } else {
      const testConfig = loadTestConfig();
      await saveTestConfig(browser, testConfig);
    }
    if (beforeExtra) {
      await beforeExtra({ browser, state });
    }
  });

  beforeEach(function () {
    if (!state.binaryAvailable) {
      this.skip(`Binary not found, skipping all ${suiteLabel} tests`);
    }
  });

  afterEach(async function () {
    reportAfterEach(this.currentTest, suiteLabel, suggestion);
    if (afterEachCleanup) {
      try {
        await afterEachCleanup();
      } catch {
        // 忽略额外清理错误
      }
    }
  });

  after(async function () {
    if (afterExtra) {
      try {
        await afterExtra({ browser, state });
      } catch {
        // 忽略额外清理错误
      }
    }
    if (state.appStarted) {
      try {
        restoreUserConfig();
      } catch {
        // 忽略恢复错误，不阻塞
      }
      try {
        await closeApp(browser);
      } catch {
        // 忽略关闭错误
      }
    }
  });

  return state;
}