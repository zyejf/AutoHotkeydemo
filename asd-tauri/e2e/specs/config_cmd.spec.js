// =================================================================
// config_cmd E2E 测试 - 覆盖 11 个 Tauri 命令
// =================================================================
// 命令清单（lib.rs register_handler 已全部注册）：
//   get_config, save_config, validate_config, list_backups,
//   create_backup, restore_backup, delete_backup, hot_reload,
//   export_config, import_config, compare_configs
// =================================================================
import { expect } from 'chai';
import { existsSync, readFileSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { invoke, getConfig, saveConfig, startApp, closeApp } from '../helpers/tauri.js';
import {
  backupUserConfig,
  restoreUserConfig,
  loadTestConfig,
  saveTestConfig,
  validateConfig,
} from '../helpers/config.js';
import { appendResult, appendKnownIssue } from '../helpers/report.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const binaryPath = resolve(__dirname, '../../target/debug/asd-tauri.exe');

// 全局状态：binary 是否可用、应用是否已启动
let binaryAvailable = false;
let appStarted = false;

describe('config_cmd E2E 测试', () => {
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
    // 写入测试配置作为初始状态
    const testConfig = loadTestConfig();
    await saveTestConfig(browser, testConfig);
  });

  beforeEach(function () {
    if (!binaryAvailable) {
      this.skip('Binary not found, skipping all config_cmd E2E tests');
    }
  });

  afterEach(function () {
    const test = this.currentTest;
    if (!test) return;
    const suiteName = test.parent?.title || 'config_cmd E2E 测试';
    const testName = `${suiteName} > ${test.title}`;
    const status =
      test.state === 'passed' ? 'PASS' : test.state === 'failed' ? 'FAIL' : 'SKIP';
    const duration = test.duration || 0;
    const errorMsg = test.err
      ? test.err.message || String(test.err)
      : '';
    appendResult(testName, status, duration, errorMsg);
    if (test.state === 'failed') {
      const caseId = test.title.match(/E2E-CFG-\d+/)?.[0] || test.title;
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
  // E2E-CFG-001: get_config
  // ----------------------------------------------------------------
  describe('get_config', () => {
    it('E2E-CFG-001: 应返回当前配置，字段完整（hotkey/groups/controlHotkeys/version）', async () => {
      const config = await getConfig(browser);
      expect(config).to.be.an('object');
      // CONTROL_HOTKEYS 字段
      expect(config.CONTROL_HOTKEYS).to.be.an('object');
      expect(config.CONTROL_HOTKEYS.emergency).to.be.a('string');
      expect(config.CONTROL_HOTKEYS.releaseAllHolds).to.be.a('string');
      expect(config.CONTROL_HOTKEYS.showStatus).to.be.a('string');
      expect(config.CONTROL_HOTKEYS.toggleAll).to.be.a('string');
      expect(config.CONTROL_HOTKEYS.toggleHoldMode).to.be.a('string');
      // GroupSettings 字段
      expect(config.GroupSettings).to.be.an('object');
      // version 字段
      expect(config.version).to.be.a('string');
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-002: save_config
  // ----------------------------------------------------------------
  describe('save_config', () => {
    it('E2E-CFG-002: 写入测试配置后 get_config 返回一致', async () => {
      const testConfig = loadTestConfig();
      await saveConfig(browser, testConfig);
      const loaded = await getConfig(browser);
      // 比较 CONTROL_HOTKEYS
      expect(loaded.CONTROL_HOTKEYS.emergency).to.equal(
        testConfig.CONTROL_HOTKEYS.emergency
      );
      expect(loaded.CONTROL_HOTKEYS.releaseAllHolds).to.equal(
        testConfig.CONTROL_HOTKEYS.releaseAllHolds
      );
      // 比较 GroupSettings 的 key 集合
      const testKeys = Object.keys(testConfig.GroupSettings);
      const loadedKeys = Object.keys(loaded.GroupSettings);
      expect(loadedKeys).to.have.members(testKeys);
      // 比较每个分组的 hotkey 和 mode（GroupConfig 识别的字段）
      for (const key of testKeys) {
        expect(loaded.GroupSettings[key].hotkey).to.equal(
          testConfig.GroupSettings[key].hotkey
        );
        expect(loaded.GroupSettings[key].mode).to.equal(
          testConfig.GroupSettings[key].mode
        );
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-003 / E2E-CFG-004: validate_config
  // ----------------------------------------------------------------
  describe('validate_config', () => {
    it('E2E-CFG-003: 合法配置返回 valid=true，errors 为空', async () => {
      const testConfig = loadTestConfig();
      const result = await validateConfig(browser, testConfig);
      expect(result).to.be.an('object');
      expect(result.valid).to.be.true;
      expect(result.errors).to.be.an('array');
      expect(result.errors).to.have.lengthOf(0);
    });

    it('E2E-CFG-004: 非法配置（空 hotkey）返回 valid=false 且 errors 非空', async () => {
      const invalidConfig = loadTestConfig();
      const firstKey = Object.keys(invalidConfig.GroupSettings)[0];
      invalidConfig.GroupSettings[firstKey].hotkey = '';
      const result = await validateConfig(browser, invalidConfig);
      expect(result.valid).to.be.false;
      expect(result.errors).to.be.an('array');
      expect(result.errors.length).to.be.at.least(1);
      // 至少有一个 error 的 field 为 hotkey
      const hotkeyErrors = result.errors.filter((e) => e.field === 'hotkey');
      expect(hotkeyErrors.length).to.be.at.least(1);
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-005: list_backups
  // ----------------------------------------------------------------
  describe('list_backups', () => {
    it('E2E-CFG-005: 返回备份列表数组（可能为空，元素含 filename/timestamp/size）', async () => {
      const backups = await invoke(browser, 'list_backups', {});
      expect(backups).to.be.an('array');
      for (const b of backups) {
        expect(b.filename).to.be.a('string');
        expect(b.timestamp).to.be.a('string');
        expect(b.size).to.be.a('number');
        // 备份文件名应以 backup_ 开头
        expect(b.filename).to.match(/^backup_/);
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-006: create_backup
  // ----------------------------------------------------------------
  describe('create_backup', () => {
    it('E2E-CFG-006: 创建备份后 list_backups 数量 +1，文件名以 backup_ 开头', async () => {
      const before = await invoke(browser, 'list_backups', {});
      const beforeCount = before.length;

      const backupName = await invoke(browser, 'create_backup', {});
      expect(backupName).to.be.a('string');
      expect(backupName).to.match(/^backup_/);
      expect(backupName).to.match(/\.json$/);

      const after = await invoke(browser, 'list_backups', {});
      expect(after.length).to.equal(beforeCount + 1);
      // 新备份应出现在列表中
      expect(after.map((b) => b.filename)).to.include(backupName);

      // 清理：删除测试创建的备份
      await invoke(browser, 'delete_backup', { filename: backupName });
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-007: restore_backup
  // ----------------------------------------------------------------
  describe('restore_backup', () => {
    it('E2E-CFG-007: 恢复备份后 get_config 应回到备份值', async () => {
      // 1. 记录初始备份列表（用于后续清理）
      const initialBackups = await invoke(browser, 'list_backups', {});
      const initialNames = initialBackups.map((b) => b.filename);

      // 2. 保存配置 A（含所有测试分组）
      const configA = loadTestConfig();
      await saveConfig(browser, configA);
      const groupKeysA = Object.keys(configA.GroupSettings);

      // 3. 创建备份 B（含配置 A）
      const backupName = await invoke(browser, 'create_backup', {});

      // 4. 修改为配置 B（删除第一个分组）
      const configB = loadTestConfig();
      const removedKey = groupKeysA[0];
      delete configB.GroupSettings[removedKey];
      await saveConfig(browser, configB);

      // 验证修改已生效
      const modified = await getConfig(browser);
      expect(Object.keys(modified.GroupSettings)).to.not.include(removedKey);

      // 5. 恢复备份 B
      await invoke(browser, 'restore_backup', { filename: backupName });

      // 6. 验证 get_config 返回配置 A（被删除的分组应恢复）
      const restored = await getConfig(browser);
      expect(Object.keys(restored.GroupSettings)).to.include(removedKey);

      // 7. 清理：删除测试过程中创建的所有备份
      // 注意：restore_backup 会自动创建一个备份（"恢复前已自动创建备份"）
      const afterBackups = await invoke(browser, 'list_backups', {});
      const createdBackups = afterBackups
        .map((b) => b.filename)
        .filter((name) => !initialNames.includes(name));
      for (const name of createdBackups) {
        try {
          await invoke(browser, 'delete_backup', { filename: name });
        } catch {
          // 忽略删除错误
        }
      }

      // 8. 恢复测试配置作为初始状态
      await saveConfig(browser, loadTestConfig());
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-008: delete_backup
  // ----------------------------------------------------------------
  describe('delete_backup', () => {
    it('E2E-CFG-008: 删除备份后 list_backups 数量 -1', async () => {
      const before = await invoke(browser, 'list_backups', {});
      const beforeCount = before.length;

      // 创建一个备份用于删除
      const backupName = await invoke(browser, 'create_backup', {});
      const middle = await invoke(browser, 'list_backups', {});
      expect(middle.length).to.equal(beforeCount + 1);

      // 删除备份
      await invoke(browser, 'delete_backup', { filename: backupName });
      const after = await invoke(browser, 'list_backups', {});
      expect(after.length).to.equal(beforeCount);
      // 备份应不再存在于列表中
      expect(after.map((b) => b.filename)).to.not.include(backupName);
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-009: export_config
  // ----------------------------------------------------------------
  describe('export_config', () => {
    it('E2E-CFG-009: 导出后文件存在且内容为有效 JSON 配置', async () => {
      const exportPath = join(tmpdir(), `asd-e2e-export-${Date.now()}.json`);
      try {
        await invoke(browser, 'export_config', { path: exportPath });
        // 文件应存在
        expect(existsSync(exportPath)).to.be.true;
        // 文件内容应为有效 JSON，含 CONTROL_HOTKEYS 字段
        const content = readFileSync(exportPath, 'utf-8');
        const parsed = JSON.parse(content);
        expect(parsed).to.be.an('object');
        expect(parsed.CONTROL_HOTKEYS).to.be.an('object');
        expect(parsed.GroupSettings).to.be.an('object');
      } finally {
        // 清理临时文件
        try {
          unlinkSync(exportPath);
        } catch {
          // 忽略删除错误
        }
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-010: import_config
  // ----------------------------------------------------------------
  describe('import_config', () => {
    it('E2E-CFG-010: 导入导出的配置后 get_config 一致', async () => {
      const exportPath = join(tmpdir(), `asd-e2e-import-${Date.now()}.json`);
      try {
        // 1. 保存配置 A 并获取当前配置
        const configA = loadTestConfig();
        await saveConfig(browser, configA);
        const originalConfig = await getConfig(browser);
        const originalKeys = Object.keys(originalConfig.GroupSettings);

        // 2. 导出配置 A
        await invoke(browser, 'export_config', { path: exportPath });
        expect(existsSync(exportPath)).to.be.true;

        // 3. 修改为配置 B（删除一个分组）
        const configB = loadTestConfig();
        const removedKey = originalKeys[0];
        delete configB.GroupSettings[removedKey];
        await saveConfig(browser, configB);

        // 验证修改已生效
        const modified = await getConfig(browser);
        expect(Object.keys(modified.GroupSettings)).to.not.include(removedKey);

        // 4. 导入之前导出的配置 A
        await invoke(browser, 'import_config', { path: exportPath });

        // 5. 验证 get_config 返回配置 A（被删除的分组应恢复）
        const imported = await getConfig(browser);
        expect(Object.keys(imported.GroupSettings)).to.include(removedKey);
      } finally {
        // 清理临时文件
        try {
          unlinkSync(exportPath);
        } catch {
          // 忽略删除错误
        }
        // 恢复测试配置作为初始状态
        await saveConfig(browser, loadTestConfig());
      }
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-011: compare_configs
  // ----------------------------------------------------------------
  describe('compare_configs', () => {
    it('E2E-CFG-011: 比较两个不同配置返回差异列表（added/removed/modified）', async () => {
      // 1. 保存配置 A
      const configA = loadTestConfig();
      await saveConfig(browser, configA);

      // 2. 创建备份 B（含配置 A）
      const backupName = await invoke(browser, 'create_backup', {});

      // 3. 修改为配置 B：删除一个分组、修改一个分组、添加一个新分组
      const configB = loadTestConfig();
      const keys = Object.keys(configB.GroupSettings);
      const removedKey = keys[0];
      const modifiedKey = keys[1];

      // 删除第一个分组
      delete configB.GroupSettings[removedKey];
      // 修改第二个分组的 hotkey
      if (modifiedKey) {
        configB.GroupSettings[modifiedKey].hotkey = 'F9';
      }
      // 添加新分组
      configB.GroupSettings['new-test-group'] = {
        hotkey: 'F8',
        mode: 'periodic',
        name: 'new-test-group',
        keys: ['1'],
        intervals: [50],
      };
      await saveConfig(browser, configB);

      // 4. 比较当前配置（B）与备份（A）
      const diff = await invoke(browser, 'compare_configs', {
        backupFilename: backupName,
      });
      expect(diff).to.be.an('object');
      expect(diff.addedGroups).to.be.an('array');
      expect(diff.removedGroups).to.be.an('array');
      expect(diff.modifiedGroups).to.be.an('array');

      // 从备份（A）→ 当前（B）的视角：
      // - removedGroups: 备份有但当前没有 = 当前删除的分组
      expect(diff.removedGroups).to.include(removedKey);
      // - addedGroups: 当前有但备份没有 = 当前新增的分组
      expect(diff.addedGroups).to.include('new-test-group');
      // - modifiedGroups: 两边都有但内容不同
      if (modifiedKey) {
        expect(diff.modifiedGroups).to.include(modifiedKey);
      }

      // 清理：删除测试创建的备份
      try {
        await invoke(browser, 'delete_backup', { filename: backupName });
      } catch {
        // 忽略删除错误
      }
      // 恢复测试配置作为初始状态
      await saveConfig(browser, loadTestConfig());
    });
  });

  // ----------------------------------------------------------------
  // E2E-CFG-012: hot_reload
  // ----------------------------------------------------------------
  describe('hot_reload', () => {
    it('E2E-CFG-012: 从磁盘重新加载配置，返回字段完整的 Config', async () => {
      // 获取当前配置（通过 Tauri）
      const before = await getConfig(browser);

      // 调用 hot_reload 从磁盘重新加载
      const reloaded = await invoke(browser, 'hot_reload', {});

      // 验证返回的配置字段完整
      expect(reloaded).to.be.an('object');
      expect(reloaded.CONTROL_HOTKEYS).to.be.an('object');
      expect(reloaded.CONTROL_HOTKEYS.emergency).to.be.a('string');
      expect(reloaded.GroupSettings).to.be.an('object');
      expect(reloaded.version).to.be.a('string');

      // 由于磁盘配置未被外部修改，hot_reload 返回的配置应与之前一致
      // 比较 GroupSettings 的 key 集合
      const beforeKeys = Object.keys(before.GroupSettings);
      const reloadedKeys = Object.keys(reloaded.GroupSettings);
      expect(reloadedKeys).to.have.members(beforeKeys);
    });
  });
});
