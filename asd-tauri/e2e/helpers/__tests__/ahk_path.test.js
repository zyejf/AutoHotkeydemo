// =================================================================
// ahk_path 模块单元测试 - 验证 AHK 路径集中管理与硬编码消除
// =================================================================
// 测试运行器：Node.js 内置 node:test（无需额外依赖，与 E2E 环境隔离）
// 运行命令：node --test helpers/__tests__/ahk_path.test.js
// 设计说明：
//   - 硬编码检查使用 readFileSync 直接读取源码，不依赖 ahk_path.js，
//     这样即使模块尚未创建也能独立验证硬编码消除。
//   - 模块行为测试使用动态 import，模块不存在时该 describe 的测试
//     会失败，但不影响硬编码检查的运行。
// =================================================================
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// 源码中硬编码路径的字面形式（JS 源码字符串转义后的双反斜杠）
// hotkey_cmd.spec.js / key_receiver.js 中原始写法为 'D:\\Program Files\\...'
// 读取文件后字节内容包含字面的 "D:\\Program Files"（两个反斜杠字符）
const HARDCODED_PATH_FRAGMENT = String.raw`D:\\Program Files\\AutoHotkey`;

// -----------------------------------------------------------------
// 硬编码路径消除验证（不依赖 ahk_path.js，可独立运行）
// -----------------------------------------------------------------
describe('硬编码路径消除验证', () => {
  test('hotkey_cmd.spec.js 不含硬编码 AHK 路径', () => {
    const specPath = join(__dirname, '../../specs/hotkey_cmd.spec.js');
    const content = readFileSync(specPath, 'utf-8');
    assert.ok(
      !content.includes(HARDCODED_PATH_FRAGMENT),
      'hotkey_cmd.spec.js 不应包含硬编码路径 D:\\Program Files\\AutoHotkey，应改用 ahk_path 模块'
    );
  });

  test('key_receiver.js 不含硬编码 AHK 路径', () => {
    const helperPath = join(__dirname, '../key_receiver.js');
    const content = readFileSync(helperPath, 'utf-8');
    assert.ok(
      !content.includes(HARDCODED_PATH_FRAGMENT),
      'key_receiver.js 不应包含硬编码路径 D:\\Program Files\\AutoHotkey，应改用 ahk_path 模块'
    );
  });
});

// -----------------------------------------------------------------
// ahk_path 模块行为测试（动态导入，模块不存在时测试失败但不影响硬编码检查）
// -----------------------------------------------------------------
describe('ahk_path 模块行为', () => {
  let getAhkPath, getAhkDir, DEFAULT_AHK_PATH;
  let savedAhkPath;

  before(async () => {
    // 保存原始环境变量，确保测试结束后恢复
    savedAhkPath = process.env.AHK_PATH;
    // 动态导入模块（模块不存在时此处抛错，该 describe 的测试会标记为失败）
    const mod = await import('../ahk_path.js');
    getAhkPath = mod.getAhkPath;
    getAhkDir = mod.getAhkDir;
    DEFAULT_AHK_PATH = mod.DEFAULT_AHK_PATH;
  });

  after(() => {
    // 恢复原始环境变量，避免测试污染
    if (savedAhkPath === undefined) {
      delete process.env.AHK_PATH;
    } else {
      process.env.AHK_PATH = savedAhkPath;
    }
  });

  test('getAhkPath 设置 AHK_PATH 环境变量时返回该值', () => {
    process.env.AHK_PATH = 'C:\\Custom\\AutoHotkey.exe';
    assert.equal(getAhkPath(), 'C:\\Custom\\AutoHotkey.exe');
  });

  test('getAhkPath 未设置环境变量时返回默认路径', () => {
    delete process.env.AHK_PATH;
    assert.equal(getAhkPath(), DEFAULT_AHK_PATH);
  });

  test('getAhkDir 返回路径的目录部分', () => {
    process.env.AHK_PATH = 'D:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe';
    assert.equal(getAhkDir(), 'D:\\Program Files\\AutoHotkey\\v2');
  });
});
