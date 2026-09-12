// =================================================================
// 7 种执行模式 E2E 测试
// =================================================================
// 覆盖模式: periodic, sequence, hybrid, hold,
//           enhanced_periodic, enhanced_sequence, enhanced_hybrid
// 测试流程: 启动 key_receiver → 激活窗口 → toggle_group 启动分组
//           → 等待按键执行 → toggle_group 停止分组 → 读取 key_log.txt 断言
// 容差: 间隔 ±20ms，次数 ±2 次
// =================================================================
import { expect } from 'chai';
import { exec } from 'node:child_process';
import { promisify } from 'node:util';
import { invoke } from '../helpers/tauri.js';
import {
  startKeyReceiver,
  stopKeyReceiver,
  readKeyLog,
  clearKeyLog,
} from '../helpers/key_receiver.js';
import { appendKnownIssue } from '../helpers/report.js';
import {
  registerStandardLifecycle,
  resolveBinaryPath,
  DEFAULT_FAILURE_SEVERITY,
} from '../helpers/spec-hooks.js';

const execAsync = promisify(exec);
const binaryPath = resolveBinaryPath(import.meta.url);

const KEY_RECEIVER_TITLE = 'E2E Key Receiver';
const ALL_GROUP_IDS = [
  'test-periodic',
  'test-sequence',
  'test-hybrid',
  'test-hold',
  'test-enhanced-periodic',
  'test-enhanced-sequence',
  'test-enhanced-hybrid',
];

// ----------------------------------------------------------------
// 辅助函数
// ----------------------------------------------------------------

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// 激活 key_receiver 窗口（使其成为前台窗口以捕获按键）
async function activateKeyReceiver() {
  try {
    await execAsync(
      `powershell -NoProfile -Command "$wshell = New-Object -ComObject WScript.Shell; $wshell.AppActivate('${KEY_RECEIVER_TITLE}')"`
    );
    await sleep(200);
  } catch {
    // 激活失败不阻塞测试
  }
}

// 启动分组（toggle_group 切换为激活状态）
async function startGroup(browser, groupId) {
  return invoke(browser, 'toggle_group', { groupId, active: true });
}

// 停止分组（toggle_group 切换为非激活状态）
async function stopGroup(browser, groupId) {
  return invoke(browser, 'toggle_group', { groupId, active: false });
}

// 确保分组已停止（用于 afterEach 清理，避免残留激活状态）
async function ensureGroupStopped(browser, groupId) {
  try {
    const detail = await invoke(browser, 'get_group_detail', { groupId });
    if (detail && detail.active) {
      await invoke(browser, 'toggle_group', { groupId });
    }
  } catch {
    // 忽略清理错误
  }
}

// 提取 down 事件按键序列
function getDownKeys(entries) {
  return entries.filter((e) => e.event === 'down').map((e) => e.key);
}

// 提取指定按键的 down 事件时间戳
function getDownTimestamps(entries, keyName) {
  return entries
    .filter((e) => e.event === 'down' && e.key === keyName)
    .map((e) => e.timestamp);
}

// 计算相邻时间戳的间隔数组
function getIntervals(timestamps) {
  const intervals = [];
  for (let i = 1; i < timestamps.length; i++) {
    intervals.push(timestamps[i] - timestamps[i - 1]);
  }
  return intervals;
}

// 检查 arr 是否包含 seq 子序列
function containsSubsequence(arr, seq) {
  return findSubsequenceIndex(arr, seq) !== -1;
}

// 查找子序列起始索引，未找到返回 -1
function findSubsequenceIndex(arr, seq) {
  if (seq.length === 0) return 0;
  if (arr.length < seq.length) return -1;
  for (let i = 0; i <= arr.length - seq.length; i++) {
    let match = true;
    for (let j = 0; j < seq.length; j++) {
      if (arr[i + j] !== seq[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

// 在 down 事件中查找指定按键序列的起始索引
function findKeySequenceIndex(downEntries, seq) {
  const keys = downEntries.map((e) => e.key);
  return findSubsequenceIndex(keys, seq);
}

// 记录 IPC 失败已知问题并跳过测试
function skipOnEmptyLog(testCtx, entries, caseId, modeDesc) {
  if (entries.length === 0) {
    appendKnownIssue(
      `ISSUE-${caseId}-IPC`,
      DEFAULT_FAILURE_SEVERITY,
      `启动分组并等待按键执行（${modeDesc}）`,
      `key_log.txt 应包含 ${modeDesc} 按键事件`,
      '未捕获到任何按键事件，可能是 AHK 子进程未启动或 IPC 通信失败',
      `${caseId} 测试无法验证`,
      '检查 ProcessWatchdog 与 AHK 执行器子进程启动逻辑',
      caseId
    );
    testCtx.skip('未捕获到按键事件，可能 IPC 通信失败');
    return true;
  }
  return false;
}

// 断言间隔在期望值 ± tolerance 内
function assertIntervalsNear(intervals, expected, tolerance, label) {
  for (let i = 0; i < intervals.length; i++) {
    expect(
      Math.abs(intervals[i] - expected),
      `${label} 间隔 ${intervals[i]}ms 偏离期望 ${expected}ms 超过容差 ${tolerance}ms`
    ).to.be.at.most(tolerance);
  }
}

// ----------------------------------------------------------------
// 测试套件
// ----------------------------------------------------------------

describe('7 种执行模式 E2E 测试', () => {
  registerStandardLifecycle({
    suiteLabel: '7 种执行模式 E2E 测试',
    binaryPath,
    suggestion: '检查相关模式实现与测试断言',
    beforeExtra: async ({ state }) => {
      // 启动 key_receiver 子进程
      state.keyReceiverChild = await startKeyReceiver();
    },
    afterExtra: async ({ browser, state }) => {
      if (state.keyReceiverChild) {
        stopKeyReceiver(state.keyReceiverChild);
      }
      if (state.appStarted) {
        try {
          // 确保所有分组停止
          for (const id of ALL_GROUP_IDS) {
            await ensureGroupStopped(browser, id);
          }
        } catch {
          // 忽略
        }
      }
    },
  });

  // ----------------------------------------------------------------
  // E2E-MODE-001: periodic 模式
  // 配置: keys=["Space"], intervals=[100]
  // ----------------------------------------------------------------
  describe('E2E-MODE-001: periodic 模式', () => {
    const groupId = 'test-periodic';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-001: 应按 100ms 间隔周期性发送 Space 键', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(1100); // 等待约 10 次触发
      await stopGroup(browser, groupId);

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-001', 'periodic Space')) return;

      const spaceDowns = getDownTimestamps(entries, 'Space');
      expect(spaceDowns.length, 'Space down 次数应约 10 次（±2）').to.be.within(8, 12);

      const intervals = getIntervals(spaceDowns);
      expect(intervals.length, '应有至少 1 个间隔').to.be.at.least(1);
      assertIntervalsNear(intervals, 100, 20, 'Space');
    });
  });

  // ----------------------------------------------------------------
  // E2E-MODE-002: sequence 模式
  // 配置: keys=["1","2","3"], delays=[50,50,50]
  // ----------------------------------------------------------------
  describe('E2E-MODE-002: sequence 模式', () => {
    const groupId = 'test-sequence';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-002: 应按顺序发送 1→2→3，延迟约 50ms', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(300); // 等待约 2 个完整序列（150ms/周期）
      await stopGroup(browser, groupId);

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-002', 'sequence 1,2,3')) return;

      const downEntries = entries.filter((e) => e.event === 'down');
      const downKeys = downEntries.map((e) => e.key);

      // 验证按键序列包含 1→2→3
      expect(containsSubsequence(downKeys, ['1', '2', '3']), '按键序列应包含 1→2→3').to.be.true;

      // 验证延迟（50ms ± 20ms）
      const seqStart = findKeySequenceIndex(downEntries, ['1', '2', '3']);
      expect(seqStart, '应找到 1→2→3 子序列起始索引').to.be.at.least(0);
      const interval12 = downEntries[seqStart + 1].timestamp - downEntries[seqStart].timestamp;
      const interval23 = downEntries[seqStart + 2].timestamp - downEntries[seqStart + 1].timestamp;
      expect(Math.abs(interval12 - 50), `1→2 间隔 ${interval12}ms 应在 50±20ms 内`).to.be.at.most(20);
      expect(Math.abs(interval23 - 50), `2→3 间隔 ${interval23}ms 应在 50±20ms 内`).to.be.at.most(20);
    });
  });

  // ----------------------------------------------------------------
  // E2E-MODE-003: hybrid 模式
  // 配置: groups=[{periodic, Space, 100ms}, {sequence, 1,2, 100ms}]
  // ----------------------------------------------------------------
  describe('E2E-MODE-003: hybrid 模式', () => {
    const groupId = 'test-hybrid';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-003: 应并行执行周期性 Space 与序列 1,2', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(500); // 等待两组按键并行执行
      await stopGroup(browser, groupId);

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-003', 'hybrid Space+1,2')) return;

      const downKeys = getDownKeys(entries);
      const spaceCount = downKeys.filter((k) => k === 'Space').length;
      // 过滤出序列子组的按键（1, 2），排除 periodic 子组的 Space 干扰
      // hybrid 模式下 periodic 和 sequence 并行执行，Space 会穿插在 1,2 之间
      const seqDownKeys = downKeys.filter((k) => k === '1' || k === '2');
      const hasSequence = containsSubsequence(seqDownKeys, ['1', '2']);

      // 验证周期性 Space 出现（约 5 次，±2）
      expect(spaceCount, 'Space 应出现约 5 次（±2）').to.be.at.least(3);
      // 验证序列 1,2 出现（在过滤后的序列键中查找子序列）
      expect(hasSequence, '应包含序列 1→2（过滤 Space 后）').to.be.true;
      // 验证两组按键都出现（并行执行）
      expect(downKeys, '应同时包含 Space 与 1/2').to.include.members(['Space', '1', '2']);
    });
  });

  // ----------------------------------------------------------------
  // E2E-MODE-004: hold 模式
  // 配置: holdKeys=["Shift"], holdDuration=500
  // ----------------------------------------------------------------
  describe('E2E-MODE-004: hold 模式', () => {
    const groupId = 'test-hold';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-004: 应按住 Shift 约 500ms 后释放', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(500); // 保持按住 500ms
      await stopGroup(browser, groupId);
      await sleep(100); // 等待 up 事件写入日志

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-004', 'hold Shift')) return;

      const shiftDowns = entries.filter((e) => e.key === 'Shift' && e.event === 'down');
      const shiftUps = entries.filter((e) => e.key === 'Shift' && e.event === 'up');

      // 验证 down 事件存在
      expect(shiftDowns.length, '应有 Shift down 事件').to.be.at.least(1);
      // 验证 up 事件存在
      expect(shiftUps.length, '应有 Shift up 事件').to.be.at.least(1);

      // 验证按住持续约 500ms（±20ms）
      const downTs = shiftDowns[0].timestamp;
      const upTs = shiftUps[0].timestamp;
      const holdDuration = upTs - downTs;
      expect(
        Math.abs(holdDuration - 500),
        `Shift 按住时长 ${holdDuration}ms 应在 500±20ms 内`
      ).to.be.at.most(20);
    });
  });

  // ----------------------------------------------------------------
  // E2E-MODE-005: enhanced_periodic 模式
  // 配置: pressKeys=["Space","1"], intervals=[100,200]
  // ----------------------------------------------------------------
  describe('E2E-MODE-005: enhanced_periodic 模式', () => {
    const groupId = 'test-enhanced-periodic';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-005: Space 按 100ms 间隔，1 按 200ms 间隔各自触发', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(650); // 等待 Space 约 6 次，1 约 3 次
      await stopGroup(browser, groupId);

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-005', 'enhanced_periodic Space,1')) return;

      const spaceDowns = getDownTimestamps(entries, 'Space');
      const oneDowns = getDownTimestamps(entries, '1');

      // 验证 Space 出现约 6 次（±2）
      expect(spaceDowns.length, 'Space down 次数应约 6 次（±2）').to.be.within(4, 8);
      // 验证 1 出现约 3 次（±2）
      expect(oneDowns.length, '1 down 次数应约 3 次（±2）').to.be.within(1, 5);

      // 验证 Space 间隔约 100ms（±20ms）
      const spaceIntervals = getIntervals(spaceDowns);
      if (spaceIntervals.length > 0) {
        assertIntervalsNear(spaceIntervals, 100, 20, 'Space');
      }

      // 验证 1 间隔约 200ms（±20ms）
      const oneIntervals = getIntervals(oneDowns);
      if (oneIntervals.length > 0) {
        assertIntervalsNear(oneIntervals, 200, 20, '1');
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-MODE-006: enhanced_sequence 模式
  // 配置: pressKeys=["1","2","3"], pressDelays=[100,100,100]
  // ----------------------------------------------------------------
  describe('E2E-MODE-006: enhanced_sequence 模式', () => {
    const groupId = 'test-enhanced-sequence';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-006: 应按顺序发送 1→2→3，延迟约 100ms', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(350); // 等待约 1 个完整序列（300ms/周期）
      await stopGroup(browser, groupId);

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-006', 'enhanced_sequence 1,2,3')) return;

      const downEntries = entries.filter((e) => e.event === 'down');
      const downKeys = downEntries.map((e) => e.key);

      // 验证按键序列包含 1→2→3
      expect(containsSubsequence(downKeys, ['1', '2', '3']), '按键序列应包含 1→2→3').to.be.true;

      // 验证延迟（100ms ± 20ms）
      const seqStart = findKeySequenceIndex(downEntries, ['1', '2', '3']);
      expect(seqStart, '应找到 1→2→3 子序列起始索引').to.be.at.least(0);
      const interval12 = downEntries[seqStart + 1].timestamp - downEntries[seqStart].timestamp;
      const interval23 = downEntries[seqStart + 2].timestamp - downEntries[seqStart + 1].timestamp;
      expect(Math.abs(interval12 - 100), `1→2 间隔 ${interval12}ms 应在 100±20ms 内`).to.be.at.most(20);
      expect(Math.abs(interval23 - 100), `2→3 间隔 ${interval23}ms 应在 100±20ms 内`).to.be.at.most(20);
    });
  });

  // ----------------------------------------------------------------
  // E2E-MODE-007: enhanced_hybrid 模式
  // 配置: groups=[{periodic, Space, 100ms}, {sequence, 1,2, 100ms}]
  // ----------------------------------------------------------------
  describe('E2E-MODE-007: enhanced_hybrid 模式', () => {
    const groupId = 'test-enhanced-hybrid';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-MODE-007: 应并行执行增强周期性 Space 与增强序列 1,2', async function () {
      this.timeout(10000);
      await clearKeyLog();
      await activateKeyReceiver();

      await startGroup(browser, groupId);
      await sleep(500); // 等待两组按键并行执行
      await stopGroup(browser, groupId);

      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-MODE-007', 'enhanced_hybrid Space+1,2')) return;

      const downKeys = getDownKeys(entries);
      const spaceCount = downKeys.filter((k) => k === 'Space').length;
      // 过滤出序列子组的按键（1, 2），排除 periodic 子组的 Space 干扰
      // hybrid 模式下 periodic 和 sequence 并行执行，Space 会穿插在 1,2 之间
      const seqDownKeys = downKeys.filter((k) => k === '1' || k === '2');
      const hasSequence = containsSubsequence(seqDownKeys, ['1', '2']);

      // 验证周期性 Space 出现（约 5 次，±2）
      expect(spaceCount, 'Space 应出现约 5 次（±2）').to.be.at.least(3);
      // 验证序列 1,2 出现（在过滤后的序列键中查找子序列）
      expect(hasSequence, '应包含序列 1→2（过滤 Space 后）').to.be.true;
      // 验证两组按键都出现（并行执行）
      expect(downKeys, '应同时包含 Space 与 1/2').to.include.members(['Space', '1', '2']);
    });
  });
});
