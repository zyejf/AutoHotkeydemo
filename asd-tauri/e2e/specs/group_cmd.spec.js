// =================================================================
// group_cmd E2E 测试 - 覆盖 8 个 Tauri 命令
// =================================================================
// 命令清单（lib.rs register_handler 已全部注册）：
//   get_groups, get_group_detail, toggle_group, toggle_all,
//   batch_toggle_groups, delete_group, batch_delete_groups, reorder_groups
// =================================================================
import { expect } from 'chai';
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { invoke, startApp, closeApp } from '../helpers/tauri.js';
import {
  backupUserConfig,
  restoreUserConfig,
  loadTestConfig,
  saveTestConfig,
} from '../helpers/config.js';
import { appendResult, appendKnownIssue } from '../helpers/report.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const binaryPath = resolve(__dirname, '../../target/debug/asd-tauri.exe');

// 测试配置中预期的分组 ID（与 fixtures/test_config.json 一致）
const EXPECTED_GROUP_IDS = [
  'test-periodic',
  'test-sequence',
  'test-hybrid',
  'test-hold',
  'test-enhanced-periodic',
  'test-enhanced-sequence',
  'test-enhanced-hybrid',
];

// 全局状态：binary 是否可用、应用是否已启动
let binaryAvailable = false;
let appStarted = false;

describe('group_cmd E2E 测试', () => {
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
    // 写入测试配置作为初始状态（所有分组 active=false）
    const testConfig = loadTestConfig();
    await saveTestConfig(browser, testConfig);
  });

  beforeEach(function () {
    if (!binaryAvailable) {
      this.skip('Binary not found, skipping all group_cmd E2E tests');
    }
  });

  afterEach(function () {
    const test = this.currentTest;
    if (!test) return;
    const suiteName = test.parent?.title || 'group_cmd E2E 测试';
    const testName = `${suiteName} > ${test.title}`;
    const status =
      test.state === 'passed' ? 'PASS' : test.state === 'failed' ? 'FAIL' : 'SKIP';
    const duration = test.duration || 0;
    const errorMsg = test.err
      ? test.err.message || String(test.err)
      : '';
    appendResult(testName, status, duration, errorMsg);
    if (test.state === 'failed') {
      const caseId = test.title.match(/E2E-GRP-\d+/)?.[0] || test.title;
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
  // E2E-GRP-001: get_groups
  // ----------------------------------------------------------------
  describe('get_groups', () => {
    it('E2E-GRP-001: 返回分组摘要列表，每个元素含 id/name/hotkey/mode/active 字段', async () => {
      const groups = await invoke(browser, 'get_groups', {});
      expect(groups).to.be.an('array');
      // 测试配置中有 7 个分组
      expect(groups).to.have.lengthOf(EXPECTED_GROUP_IDS.length);
      // 验证每个元素的字段结构
      for (const g of groups) {
        expect(g.id).to.be.a('string');
        expect(g.name).to.be.a('string');
        expect(g.hotkey).to.be.a('string');
        expect(g.mode).to.be.a('string');
        expect(g.active).to.be.a('boolean');
      }
      // 验证包含所有预期的分组 ID
      const ids = groups.map((g) => g.id);
      expect(ids).to.have.members(EXPECTED_GROUP_IDS);
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-002: get_group_detail
  // ----------------------------------------------------------------
  describe('get_group_detail', () => {
    it('E2E-GRP-002: 返回指定 ID 分组的详细配置（SkillGroup 结构）', async () => {
      const detail = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      expect(detail).to.be.an('object');
      // 验证 SkillGroup 核心字段
      expect(detail.id).to.equal('test-periodic');
      expect(detail.name).to.equal('test-periodic');
      expect(detail.hotkey).to.equal('F1');
      expect(detail.mode).to.equal('periodic');
      expect(detail.active).to.be.a('boolean');
      expect(detail.keyPressDuration).to.be.a('number');
      // modeData 应为对象，periodic 模式含 keys 与 intervals
      expect(detail.modeData).to.be.an('object');
      expect(detail.modeData.keys).to.be.an('array');
      expect(detail.modeData.intervals).to.be.an('array');
      expect(detail.modeData.keys).to.include('Space');
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-003: toggle_group
  // ----------------------------------------------------------------
  describe('toggle_group', () => {
    it('E2E-GRP-003: 切换分组状态，get_group_detail 返回的 active 字段翻转', async () => {
      // 1. 获取初始状态
      const before = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      const initialActive = before.active;

      // 2. 调用 toggle_group，验证返回 GroupStatus.active 翻转
      const status = await invoke(browser, 'toggle_group', {
        groupId: 'test-periodic',
      });
      expect(status).to.be.an('object');
      expect(status.id).to.equal('test-periodic');
      expect(status.active).to.equal(!initialActive);

      // 3. 通过 get_group_detail 再次确认 active 已翻转
      const after = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      expect(after.active).to.equal(!initialActive);

      // 4. 恢复初始状态
      await invoke(browser, 'toggle_group', {
        groupId: 'test-periodic',
      });
      const restored = await invoke(browser, 'get_group_detail', {
        groupId: 'test-periodic',
      });
      expect(restored.active).to.equal(initialActive);
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-004: toggle_all
  // ----------------------------------------------------------------
  describe('toggle_all', () => {
    it('E2E-GRP-004: 切换所有分组状态为 active=true，再恢复为 false', async () => {
      // 1. 调用 toggle_all({ active: true })
      const resultOn = await invoke(browser, 'toggle_all', { active: true });
      expect(resultOn).to.be.an('object');
      expect(resultOn.succeeded).to.be.an('array');
      // 初始所有分组 active=false，都应被切换（至少一个成功）
      expect(resultOn.succeeded.length).to.be.at.least(1);

      // 2. 验证所有分组 active=true
      const groupsAfterOn = await invoke(browser, 'get_groups', {});
      expect(groupsAfterOn).to.have.lengthOf(EXPECTED_GROUP_IDS.length);
      for (const g of groupsAfterOn) {
        expect(g.active).to.equal(true);
      }

      // 3. 调用 toggle_all({ active: false }) 恢复
      const resultOff = await invoke(browser, 'toggle_all', { active: false });
      expect(resultOff).to.be.an('object');
      expect(resultOff.succeeded).to.be.an('array');

      // 4. 验证所有分组 active=false
      const groupsAfterOff = await invoke(browser, 'get_groups', {});
      for (const g of groupsAfterOff) {
        expect(g.active).to.equal(false);
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-005: batch_toggle_groups
  // ----------------------------------------------------------------
  describe('batch_toggle_groups', () => {
    it('E2E-GRP-005: 批量切换指定 ID 列表的分组，其他分组不受影响', async () => {
      const targetIds = ['test-periodic', 'test-sequence'];

      // 0. 预处理：确保初始所有分组 active=false（避免前序测试残留状态影响）
      await invoke(browser, 'toggle_all', { active: false });

      // 1. 调用 batch_toggle_groups({ active: true })
      const result = await invoke(browser, 'batch_toggle_groups', {
        groupIds: targetIds,
        active: true,
      });
      expect(result).to.be.an('object');
      expect(result.succeeded).to.be.an('array');
      // 两个目标 ID 都应成功
      expect(result.succeeded).to.include.members(targetIds);

      // 2. 验证目标分组 active=true，其他分组保持 false
      const groups = await invoke(browser, 'get_groups', {});
      const byId = Object.fromEntries(groups.map((g) => [g.id, g]));
      for (const id of targetIds) {
        expect(byId[id], `分组 ${id} 应存在`).to.be.an('object');
        expect(byId[id].active).to.equal(true);
      }
      for (const g of groups) {
        if (!targetIds.includes(g.id)) {
          expect(g.active, `分组 ${g.id} 应保持 false`).to.equal(false);
        }
      }

      // 3. 恢复：批量切换回 false
      await invoke(browser, 'batch_toggle_groups', {
        groupIds: targetIds,
        active: false,
      });
      const restored = await invoke(browser, 'get_groups', {});
      for (const g of restored) {
        expect(g.active).to.equal(false);
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-006: delete_group
  // ----------------------------------------------------------------
  describe('delete_group', () => {
    it('E2E-GRP-006: 删除分组后 get_groups 数量 -1，且不再包含该 ID', async () => {
      // 1. 获取删除前的分组数量
      const before = await invoke(browser, 'get_groups', {});
      const beforeCount = before.length;

      // 2. 删除 test-hold 分组
      await invoke(browser, 'delete_group', { groupId: 'test-hold' });

      // 3. 验证数量 -1，且不再包含 test-hold
      const after = await invoke(browser, 'get_groups', {});
      expect(after).to.have.lengthOf(beforeCount - 1);
      expect(after.map((g) => g.id)).to.not.include('test-hold');

      // 4. 清理：重新写入完整测试配置以恢复被删除的分组（避免影响后续测试）
      await saveTestConfig(browser, loadTestConfig());
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-007: batch_delete_groups
  // ----------------------------------------------------------------
  describe('batch_delete_groups', () => {
    it('E2E-GRP-007: 批量删除指定 ID 列表的分组，deleted 包含所有目标 ID', async () => {
      const targetIds = ['test-enhanced-periodic', 'test-enhanced-sequence'];

      // 1. 获取删除前的分组数量
      const before = await invoke(browser, 'get_groups', {});
      const beforeCount = before.length;

      // 2. 调用 batch_delete_groups
      const result = await invoke(browser, 'batch_delete_groups', {
        groupIds: targetIds,
      });
      expect(result).to.be.an('object');
      expect(result.deleted).to.be.an('array');
      expect(result.deleted).to.have.members(targetIds);
      expect(result.failed).to.be.an('array');
      expect(result.failed).to.have.lengthOf(0);

      // 3. 验证数量 -2，且不再包含目标 ID
      const after = await invoke(browser, 'get_groups', {});
      expect(after).to.have.lengthOf(beforeCount - targetIds.length);
      const afterIds = after.map((g) => g.id);
      for (const id of targetIds) {
        expect(afterIds).to.not.include(id);
      }

      // 4. 清理：重新写入完整测试配置以恢复被删除的分组（避免影响后续测试）
      await saveTestConfig(browser, loadTestConfig());
    });
  });

  // ----------------------------------------------------------------
  // E2E-GRP-008: reorder_groups
  // ----------------------------------------------------------------
  describe('reorder_groups', () => {
    it('E2E-GRP-008: 重排序后 get_groups 返回的顺序符合新顺序', async () => {
      // 1. 获取原始顺序
      const before = await invoke(browser, 'get_groups', {});
      const originalOrder = before.map((g) => g.id);
      expect(originalOrder).to.have.lengthOf(EXPECTED_GROUP_IDS.length);

      // 2. 构造新顺序：反转原始顺序
      const newOrder = [...originalOrder].reverse();

      // 3. 调用 reorder_groups
      const result = await invoke(browser, 'reorder_groups', {
        groupIds: newOrder,
      });
      expect(result).to.be.an('object');
      expect(result.reorderedCount).to.equal(newOrder.length);
      expect(result.appendedGroups).to.be.an('array');
      // 所有分组都在 newOrder 中，不应有追加分组
      expect(result.appendedGroups).to.have.lengthOf(0);

      // 4. 验证 get_groups 返回的顺序符合 newOrder
      const after = await invoke(browser, 'get_groups', {});
      const afterOrder = after.map((g) => g.id);
      expect(afterOrder).to.deep.equal(newOrder);

      // 5. 恢复原始顺序（避免影响后续测试）
      await invoke(browser, 'reorder_groups', {
        groupIds: originalOrder,
      });
      const restored = await invoke(browser, 'get_groups', {});
      const restoredOrder = restored.map((g) => g.id);
      expect(restoredOrder).to.deep.equal(originalOrder);
    });
  });
});
