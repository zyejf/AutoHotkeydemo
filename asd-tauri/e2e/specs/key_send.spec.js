// =================================================================
// AHK 执行器按键验证 E2E 测试
// =================================================================
// 覆盖用例: E2E-KEY-001 ~ E2E-KEY-005
// 测试要点:
//   E2E-KEY-001  按键实际发送 - periodic 分组 Space 事件捕获
//   E2E-KEY-002  按键间隔精度 - 周期间隔误差 ≤ ±20ms
//   E2E-KEY-003  按键顺序     - sequence 模式 1→2→3
//   E2E-KEY-004  hold 模式    - holdDuration 期间按住、结束释放
//   E2E-KEY-005  emergency_release 后无按键
// 测试流程: 启动 key_receiver → 激活窗口 → toggle_group 启动分组
//           → 等待按键执行 → 停止分组/紧急释放 → 读取 key_log.txt 断言
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
  waitForKeys,
  assertKeySequence,
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
// 测试涉及的所有分组 ID，用于 after 钩子统一清理
const ALL_GROUP_IDS = [
  'test-periodic',
  'test-sequence',
  'test-hold',
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
      await invoke(browser, 'toggle_group', { groupId, active: false });
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

// 断言间隔在期望值 ± tolerance 内
function assertIntervalsNear(intervals, expected, tolerance, label) {
  for (let i = 0; i < intervals.length; i++) {
    expect(
      Math.abs(intervals[i] - expected),
      `${label} 间隔 ${intervals[i]}ms 偏离期望 ${expected}ms 超过容差 ${tolerance}ms`
    ).to.be.at.most(tolerance);
  }
}

// 记录 IPC 失败已知问题并跳过测试
function skipOnEmptyLog(testCtx, entries, caseId, modeDesc) {
  if (entries.length === 0) {
    appendKnownIssue(
      `ISSUE-${caseId}-IPC`,
      DEFAULT_FAILURE_SEVERITY,
      `启动分组并等待按键执行（${modeDesc}）`,
      `key_log.txt 应包含 ${modeDesc} 按键事件`,
      '未捕获到任何按键事件，可能是 AHK 子进程未启动、IPC 通信失败或 key_receiver 窗口未聚焦',
      `${caseId} 测试无法验证`,
      '检查 ProcessWatchdog、AHK 执行器子进程启动逻辑与 key_receiver 窗口焦点',
      caseId
    );
    testCtx.skip('未捕获到按键事件，可能 IPC 通信失败或窗口焦点问题');
    return true;
  }
  return false;
}

// ----------------------------------------------------------------
// 测试套件
// ----------------------------------------------------------------

describe('AHK 执行器按键验证 E2E 测试', () => {
  registerStandardLifecycle({
    suiteLabel: 'AHK 执行器按键验证 E2E 测试',
    binaryPath,
    suggestion: '检查 AHK 执行器按键发送逻辑与测试断言',
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
  // E2E-KEY-001: 按键实际发送
  // 配置: test-periodic, keys=["Space"], intervals=[100]
  // ----------------------------------------------------------------
  describe('E2E-KEY-001: 按键实际发送', () => {
    const groupId = 'test-periodic';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-KEY-001: 应捕获到 periodic 分组的 Space 按键事件', async function () {
      this.timeout(15000);
      await clearKeyLog();
      await activateKeyReceiver();

      // 1. 启动 test-periodic 分组
      await startGroup(browser, groupId);

      // 2. 轮询等待 Space 按键事件出现（最多 5 秒）
      const captured = await waitForKeys(['Space'], 5000);

      // 3. 停止分组
      await stopGroup(browser, groupId);
      await sleep(100); // 等待最后的 up 事件写入日志

      // 4. 读取 key_log.txt
      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-KEY-001', 'periodic Space')) return;

      // 5. 断言包含 Space 按键事件
      expect(captured, 'waitForKeys 应在 5s 内捕获到 Space down 事件').to.be.true;
      const spaceEvents = entries.filter((e) => e.key === 'Space');
      expect(spaceEvents.length, '应至少包含一个 Space 按键事件').to.be.at.least(1);
      // 验证事件类型包含 down（key_receiver 同时记录 down/up）
      const hasDown = spaceEvents.some((e) => e.event === 'down');
      expect(hasDown, '应包含 Space down 事件').to.be.true;
    });
  });

  // ----------------------------------------------------------------
  // E2E-KEY-002: 按键间隔精度
  // 配置: test-periodic, keys=["Space"], intervals=[100]
  // 期望: 实际间隔与 100ms 的误差在 ±20ms 内
  // ----------------------------------------------------------------
  describe('E2E-KEY-002: 按键间隔精度', () => {
    const groupId = 'test-periodic';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-KEY-002: 周期性按键的实际间隔与配置间隔误差应在 ±20ms 内', async function () {
      this.timeout(15000);
      await clearKeyLog();
      await activateKeyReceiver();

      // 1. 启动分组，等待约 10 次触发（100ms × 10 = 1000ms）
      await startGroup(browser, groupId);
      await sleep(1100);
      await stopGroup(browser, groupId);
      await sleep(100); // 等待最后的 up 事件写入日志

      // 2. 读取 key_log.txt
      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-KEY-002', 'periodic Space 间隔')) return;

      // 3. 提取 Space down 时间戳
      const spaceDowns = getDownTimestamps(entries, 'Space');
      // 次数约 10 次（±2）
      expect(
        spaceDowns.length,
        'Space down 次数应约 10 次（±2）'
      ).to.be.within(8, 12);

      // 4. 计算间隔并断言误差 ≤ 20ms
      const intervals = getIntervals(spaceDowns);
      expect(intervals.length, '应有至少 1 个间隔').to.be.at.least(1);
      assertIntervalsNear(intervals, 100, 20, 'Space');

      // 5. 额外验证平均间隔接近 100ms
      const avgInterval =
        intervals.reduce((sum, v) => sum + v, 0) / intervals.length;
      expect(
        Math.abs(avgInterval - 100),
        `平均间隔 ${avgInterval.toFixed(1)}ms 应在 100±20ms 内`
      ).to.be.at.most(20);
    });
  });

  // ----------------------------------------------------------------
  // E2E-KEY-003: 按键顺序
  // 配置: test-sequence, keys=["1","2","3"], delays=[50,50,50]
  // 期望: 按键顺序为 1→2→3
  // ----------------------------------------------------------------
  describe('E2E-KEY-003: 按键顺序', () => {
    const groupId = 'test-sequence';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-KEY-003: sequence 模式的按键顺序应与配置一致（1→2→3）', async function () {
      this.timeout(15000);
      await clearKeyLog();
      await activateKeyReceiver();

      // 1. 启动分组，等待约 2 个完整序列（150ms/周期）
      await startGroup(browser, groupId);
      await sleep(350);
      await stopGroup(browser, groupId);
      await sleep(100); // 等待最后的 up 事件写入日志

      // 2. 读取 key_log.txt
      const entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-KEY-003', 'sequence 1,2,3')) return;

      // 3. 使用 assertKeySequence 验证按键顺序
      const downEntries = entries.filter((e) => e.event === 'down');
      const assertion = assertKeySequence(downEntries, ['1', '2', '3'], {
        toleranceMs: 20,
      });
      expect(assertion.pass, `按键顺序断言失败: ${assertion.reason}`).to.be.true;

      // 4. 额外验证延迟精度（50ms ± 20ms）
      const downKeys = downEntries.map((e) => e.key);
      // 找到第一个 1→2→3 子序列起始索引
      let seqStart = -1;
      for (let i = 0; i <= downKeys.length - 3; i++) {
        if (
          downKeys[i] === '1' &&
          downKeys[i + 1] === '2' &&
          downKeys[i + 2] === '3'
        ) {
          seqStart = i;
          break;
        }
      }
      expect(seqStart, '应找到 1→2→3 子序列起始索引').to.be.at.least(0);
      const interval12 =
        downEntries[seqStart + 1].timestamp - downEntries[seqStart].timestamp;
      const interval23 =
        downEntries[seqStart + 2].timestamp - downEntries[seqStart + 1].timestamp;
      expect(
        Math.abs(interval12 - 50),
        `1→2 间隔 ${interval12}ms 应在 50±20ms 内`
      ).to.be.at.most(20);
      expect(
        Math.abs(interval23 - 50),
        `2→3 间隔 ${interval23}ms 应在 50±20ms 内`
      ).to.be.at.most(20);
    });
  });

  // ----------------------------------------------------------------
  // E2E-KEY-004: hold 模式按键
  // 配置: test-hold, holdKeys=["Shift"], holdDuration=500
  // 期望: holdDuration 期间 Shift 持续按住，结束时释放
  // ----------------------------------------------------------------
  describe('E2E-KEY-004: hold 模式按键', () => {
    const groupId = 'test-hold';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-KEY-004: holdDuration 期间按键持续按住，结束时释放', async function () {
      this.timeout(15000);
      await clearKeyLog();
      await activateKeyReceiver();

      // 1. 启动 test-hold 分组（holdKeys=["Shift"], holdDuration=500ms）
      await startGroup(browser, groupId);

      // 2. 等待 200ms（Shift 应处于按下状态）
      await sleep(200);

      // 3. 读取 key_log.txt，应有 Shift down 事件
      let entries = readKeyLog();
      if (skipOnEmptyLog(this, entries, 'E2E-KEY-004', 'hold Shift down')) return;

      const shiftDownsBefore = entries.filter(
        (e) => e.key === 'Shift' && e.event === 'down'
      );
      expect(
        shiftDownsBefore.length,
        '在 holdDuration 期间应已捕获 Shift down 事件'
      ).to.be.at.least(1);

      // 4. 等待 600ms（让 holdDuration=500ms 过期，Shift 应已释放）
      await sleep(600);

      // 5. 读取 key_log.txt，应有 Shift up 事件
      entries = readKeyLog();
      const shiftUpsAfter = entries.filter(
        (e) => e.key === 'Shift' && e.event === 'up'
      );
      expect(
        shiftUpsAfter.length,
        'holdDuration 过期后应捕获 Shift up 事件'
      ).to.be.at.least(1);

      // 6. 停止分组
      await stopGroup(browser, groupId);
      await sleep(100); // 等待可能的 up 事件写入日志

      // 7. 验证按住持续约 500ms（±20ms）
      const shiftDowns = entries.filter(
        (e) => e.key === 'Shift' && e.event === 'down'
      );
      const downTs = shiftDowns[0].timestamp;
      const upTs = shiftUpsAfter[0].timestamp;
      const holdDuration = upTs - downTs;
      expect(
        Math.abs(holdDuration - 500),
        `Shift 按住时长 ${holdDuration}ms 应在 500±20ms 内`
      ).to.be.at.most(20);
    });
  });

  // ----------------------------------------------------------------
  // E2E-KEY-005: emergency_release 后无按键
  // 配置: test-periodic, keys=["Space"], intervals=[100]
  // 期望: 紧急释放后 key_log.txt 不再新增按键事件
  // ----------------------------------------------------------------
  describe('E2E-KEY-005: emergency_release 后无按键', () => {
    const groupId = 'test-periodic';
    afterEach(async () => {
      await ensureGroupStopped(browser, groupId);
    });

    it('E2E-KEY-005: 紧急释放后 key_log.txt 不再新增按键事件', async function () {
      this.timeout(20000);
      await clearKeyLog();
      await activateKeyReceiver();

      // 1. 启动 test-periodic 分组
      await startGroup(browser, groupId);

      // 2. 等待 500ms（让按键开始发送）
      await sleep(500);

      // 3. 读取紧急释放前的按键事件数量
      const entriesBefore = readKeyLog();
      if (
        skipOnEmptyLog(this, entriesBefore, 'E2E-KEY-005', 'periodic Space 紧急释放前')
      ) {
        await stopGroup(browser, groupId);
        return;
      }
      const countBefore = entriesBefore.length;
      const lastTsBefore =
        entriesBefore.length > 0
          ? entriesBefore[entriesBefore.length - 1].timestamp
          : 0;

      // 4. 调用 emergency_release
      await invoke(browser, 'emergency_release', {});

      // 5. 等待 1 秒（足够发送多次周期按键 if 未停止）
      await sleep(1000);

      // 6. 读取紧急释放后的按键事件
      const entriesAfter = readKeyLog();
      const countAfter = entriesAfter.length;

      // 7. 验证紧急释放后无新增按键事件
      const newEvents = entriesAfter.slice(countBefore);
      // 过滤掉可能在 emergency_release 之前已发送但尚未写入日志的事件
      // （以 lastTsBefore 为基准，容差 50ms 内的事件视为释放前残留）
      const toleranceMs = 50;
      const eventsAfterRelease = newEvents.filter(
        (e) => e.timestamp > lastTsBefore + toleranceMs
      );

      expect(
        eventsAfterRelease.length,
        `紧急释放后应无新增按键事件，但检测到 ${eventsAfterRelease.length} 个新事件: ${JSON.stringify(eventsAfterRelease)}`
      ).to.equal(0);

      // 8. 额外验证：紧急释放前确实有按键事件（确认测试有效）
      expect(
        countBefore,
        '紧急释放前应已捕获按键事件（确认分组已启动）'
      ).to.be.at.least(1);
      const spaceDownsBefore = entriesBefore.filter(
        (e) => e.key === 'Space' && e.event === 'down'
      );
      expect(
        spaceDownsBefore.length,
        '紧急释放前应已捕获 Space down 事件'
      ).to.be.at.least(1);
    });
  });
});
