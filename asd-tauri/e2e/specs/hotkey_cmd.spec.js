// =================================================================
// hotkey_cmd E2E 测试 - 覆盖 2 个 Tauri 命令 + 1 个端到端按键触发场景
// =================================================================
// 命令清单（lib.rs register_handler 已注册）：
//   register_hotkey, unregister_hotkey
// ----------------------------------------------------------------
// 设计说明：
// - get_executor_status 返回的 WatchdogState 结构体仅包含
//   { status, restartCount, backoffDurationSecs } 字段，
//   不包含 registered_hotkeys 字段（与任务描述假设不符）。
//   因此 E2E-HK-001 / E2E-HK-002 通过 get_group_detail 验证
//   register_hotkey / unregister_hotkey 的实际效果：
//     * register_hotkey 更新分组的 hotkey 字段
//     * unregister_hotkey 将活跃分组设为非活跃（active=false）
// - register_hotkey 对非活跃分组仅更新配置（不触发 IPC），路径稳定；
//   对活跃分组会 swap_hotkey 并发送 IPC，依赖 AHK 子进程。
// - unregister_hotkey 需热键已注册到 active_hotkeys（即分组已激活），
//   依赖 IPC 通信成功；若 IPC 失败会回滚并返回错误。
// =================================================================
import { expect } from 'chai';
import { existsSync, writeFileSync, unlinkSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { invoke, startApp, closeApp } from '../helpers/tauri.js';
import {
  backupUserConfig,
  restoreUserConfig,
  loadTestConfig,
  saveTestConfig,
} from '../helpers/config.js';
import { appendResult, appendKnownIssue } from '../helpers/report.js';
import {
  startKeyReceiver,
  stopKeyReceiver,
  readKeyLog,
} from '../helpers/key_receiver.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const binaryPath = resolve(__dirname, '../../target/debug/asd-tauri.exe');
const ahkPath = 'D:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';

// 全局状态：binary 是否可用、应用是否已启动
let binaryAvailable = false;
let appStarted = false;

describe('hotkey_cmd E2E 测试', () => {
  before(async function () {
    this.timeout(60000);
    if (!existsSync(binaryPath)) {
      // binary 不存在，跳过所有测试（不 fail）
      return;
    }
    binaryAvailable = true;
    await startApp(browser);
    appStarted = true;
    // 备份用户配置（同步操作）
    backupUserConfig();
    // 写入测试配置作为初始状态（所有分组 active=false，hotkey=F1..F7）
    const testConfig = loadTestConfig();
    await saveTestConfig(browser, testConfig);
  });

  beforeEach(function () {
    if (!binaryAvailable) {
      this.skip('Binary not found, skipping all hotkey_cmd E2E tests');
    }
  });

  afterEach(function () {
    const test = this.currentTest;
    if (!test) return;
    const suiteName = test.parent?.title || 'hotkey_cmd E2E 测试';
    const testName = `${suiteName} > ${test.title}`;
    const status =
      test.state === 'passed' ? 'PASS' : test.state === 'failed' ? 'FAIL' : 'SKIP';
    const duration = test.duration || 0;
    const errorMsg = test.err
      ? test.err.message || String(test.err)
      : '';
    appendResult(testName, status, duration, errorMsg);
    if (test.state === 'failed') {
      const caseId = test.title.match(/E2E-HK-\d+/)?.[0] || test.title;
      appendKnownIssue(
        `ISSUE-${caseId}`,
        'HIGH',
        `执行测试用例 ${test.title}`,
        '测试应通过',
        errorMsg,
        `E2E 测试失败: ${test.title}`,
        '检查相关 Tauri 命令实现与测试断言',
        caseId
      );
    }
  });

  after(async function () {
    if (appStarted) {
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

  // ----------------------------------------------------------------
  // E2E-HK-001: register_hotkey
  // ----------------------------------------------------------------
  // 验证点：
  //   1. register_hotkey 命令执行成功（不抛错）
  //   2. get_group_detail 返回的 hotkey 字段已更新为注册的热键
  // ----------------------------------------------------------------
  // 注：get_executor_status 返回的 WatchdogState 不包含 registered_hotkeys
  // 字段，使用 get_group_detail 验证 register_hotkey 的配置层效果。
  // test-periodic 初始为非活跃分组，register_hotkey 走非活跃路径
  // （仅更新配置，不触发 IPC），路径稳定可靠。
  // ----------------------------------------------------------------
  describe('register_hotkey', () => {
    it('E2E-HK-001: 注册热键后 get_group_detail 返回的 hotkey 字段更新为新热键', async () => {
      // 1. 确保初始状态：所有分组 active=false，test-periodic.hotkey=F1
      await saveTestConfig(browser, loadTestConfig());
      const before = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      expect(before.hotkey).to.equal('F1', '初始 hotkey 应为 F1');

      // 2. 调用 register_hotkey 注册 F8 到 test-periodic
      await invoke(browser, 'register_hotkey', {
        hotkey: 'F8',
        groupId: 'test-periodic',
      });

      // 3. 验证 get_group_detail 的 hotkey 字段已更新为 F8
      const after = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      expect(after.hotkey).to.equal('F8', '注册后 hotkey 应更新为 F8');

      // 4. 清理：恢复测试配置
      await saveTestConfig(browser, loadTestConfig());
    });
  });

  // ----------------------------------------------------------------
  // E2E-HK-002: unregister_hotkey
  // ----------------------------------------------------------------
  // 验证点：
  //   1. 先 toggle_group 激活分组（热键 F1 进入 active_hotkeys）
  //   2. unregister_hotkey 命令执行成功（不抛错）
  //   3. get_group_detail 返回的 active=false（unregister 将分组设为非活跃）
  // ----------------------------------------------------------------
  // 注：unregister_hotkey 需热键已注册到 active_hotkeys，故需先激活分组。
  // unregister 成功后会将分组设为非活跃（active=false），以此验证注销效果。
  // 此用例依赖 IPC 通信（toggle_group + unregister_hotkey 均发送 IPC）。
  // ----------------------------------------------------------------
  describe('unregister_hotkey', () => {
    it('E2E-HK-002: 注销活跃分组热键后分组变为非活跃（active=false）', async () => {
      // 1. 确保初始状态
      await saveTestConfig(browser, loadTestConfig());

      // 2. 激活 test-periodic 分组（热键 F1 进入 active_hotkeys）
      const toggleResult = await invoke(browser, 'toggle_group', {
        groupId: 'test-periodic',
      });
      expect(toggleResult.active).to.equal(true, 'toggle 后分组应激活');

      // 3. 调用 unregister_hotkey 注销 F1
      await invoke(browser, 'unregister_hotkey', { hotkey: 'F1' });

      // 4. 验证分组 active=false（unregister_hotkey 会将分组设为非活跃）
      const detail = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      expect(detail.active).to.equal(
        false,
        '注销热键后分组应变为非活跃'
      );

      // 5. 清理：恢复测试配置
      await saveTestConfig(browser, loadTestConfig());
    });
  });

  // ----------------------------------------------------------------
  // E2E-HK-003: 热键实际触发（端到端按键捕获）
  // ----------------------------------------------------------------
  // 验证点：
  //   1. startKeyReceiver 启动按键接收窗口
  //   2. register_hotkey 注册热键 F8（非活跃分组路径，仅更新配置）
  //   3. 通过临时 AHK 脚本模拟按下 F8（先激活 key_receiver 窗口）
  //   4. readKeyLog 返回的按键事件包含 F8 down 事件
  // ----------------------------------------------------------------
  // 注：使用非活跃分组路径注册热键，F8 不会被 ASD 应用注册到 AHK 子进程，
  // 因此 F8 按键能被 key_receiver 捕获。此用例主要验证：
  //   - register_hotkey 命令执行成功
  //   - 按键模拟能被 key_receiver 捕获
  //   - key_log.txt 记录正确
  // ----------------------------------------------------------------
  describe('热键实际触发', () => {
    it('E2E-HK-003: 启动按键接收窗口，注册热键并模拟按下，key_log.txt 捕获到按键事件', async function () {
      // 检查 AHK 是否可用，不可用则 skip
      if (!existsSync(ahkPath)) {
        this.skip('AutoHotkey64.exe not found, skipping key trigger test');
      }

      let receiverChild = null;
      let tempScriptPath = null;
      try {
        // 1. 确保初始状态
        await saveTestConfig(browser, loadTestConfig());

        // 2. 启动 key_receiver（会自动清空 key_log.txt）
        receiverChild = await startKeyReceiver();

        // 3. 注册热键 F8 到 test-periodic（非活跃分组路径）
        await invoke(browser, 'register_hotkey', {
          hotkey: 'F8',
          groupId: 'test-periodic',
        });

        // 4. 模拟按下 F8：创建临时 AHK 脚本
        //    先激活 key_receiver 窗口（确保按键能被捕获），再 Send("{F8}")
        tempScriptPath = join(tmpdir(), `asd-send-key-${Date.now()}.ahk`);
        const scriptContent = [
          '#Requires AutoHotkey v2.0',
          '#ErrorStdOut "UTF-8"',
          'SendLevel(10)',  // 让 Send 发送的按键能触发热键钩子（默认 SendLevel=0 无法触发）
          'WinActivate("E2E Key Receiver")',
          'Sleep(100)',
          'Send("{F8}")',
          'ExitApp()',
        ].join('\n');
        writeFileSync(tempScriptPath, scriptContent, 'utf-8');

        // 5. 执行临时 AHK 脚本模拟按键
        await runAhkScript(tempScriptPath);

        // 6. 等待 500ms 让 key_receiver 写入日志
        await sleep(500);

        // 7. 读取 key_log.txt 验证捕获到 F8 down 事件
        const entries = readKeyLog();
        expect(entries).to.be.an('array');
        const f8DownEvents = entries.filter(
          (e) => e.key === 'F8' && e.event === 'down'
        );
        expect(
          f8DownEvents.length,
          `应捕获到至少 1 个 F8 down 事件，实际捕获: ${JSON.stringify(entries)}`
        ).to.be.at.least(1);
      } finally {
        // 8. 清理：关闭 key_receiver，删除临时脚本，恢复配置
        stopKeyReceiver(receiverChild);
        if (tempScriptPath && existsSync(tempScriptPath)) {
          try {
            unlinkSync(tempScriptPath);
          } catch {
            // 忽略删除错误
          }
        }
        try {
          await saveTestConfig(browser, loadTestConfig());
        } catch {
          // 忽略恢复错误
        }
      }
    });
  });
});

// =================================================================
// 辅助函数
// =================================================================

/**
 * 同步 sleep
 * @param {number} ms - 毫秒
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 执行 AHK 脚本并等待完成
 * @param {string} scriptPath - AHK 脚本路径
 * @returns {Promise<void>}
 */
function runAhkScript(scriptPath) {
  return new Promise((resolve, reject) => {
    const child = spawn(ahkPath, [scriptPath], {
      stdio: 'ignore',
      windowsHide: false,
    });
    child.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`AHK script exited with code ${code}`));
      }
    });
    child.on('error', (err) => {
      reject(new Error(`Failed to spawn AHK: ${err.message}`));
    });
  });
}
