// =================================================================
// error_utils 模块单元测试 - 验证从 AppError 结构化错误提取可读消息
// =================================================================
// 背景：AppError（asd-application/src/error.rs）已从字符串序列化改为
// 结构化 {kind, message} 序列化（I34）。Tauri command 返回 Err(AppError) 时，
// 前端 invoke 会 reject 一个 {kind, message} 对象（非 Error 实例）。
// 旧的 String(err) 会得到 "[object Object]"，丢失 message。
// 此模块统一从多种错误形态提取可读消息。
//
// 测试运行器：Node.js 内置 node:test（与 ahk_path.test.js 一致，与 E2E 环境隔离）
// 运行命令：node --test helpers/__tests__/error_utils.test.js
// =================================================================
import { test, describe, before } from 'node:test';
import assert from 'node:assert/strict';

let extractErrorMessage;

before(async () => {
  // 动态导入模块（模块不存在时此处抛错，所有 describe 的测试会标记为失败 = RED）
  const mod = await import('../error_utils.js');
  extractErrorMessage = mod.extractErrorMessage;
});

// -----------------------------------------------------------------
// 从 AppError {kind, message} 提取 message（R2 核心场景）
// -----------------------------------------------------------------
describe('extractErrorMessage — 从 AppError {kind, message} 提取 message', () => {
  test('从 Ipc AppError 提取 message', () => {
    assert.equal(
      extractErrorMessage({ kind: 'Ipc', message: '连接已关闭' }),
      '连接已关闭'
    );
  });

  test('从 Config AppError 提取 message', () => {
    assert.equal(
      extractErrorMessage({ kind: 'Config', message: '参数无效' }),
      '参数无效'
    );
  });

  test('从 Internal AppError 提取 message（含中文）', () => {
    assert.equal(
      extractErrorMessage({ kind: 'Internal', message: 'CAS 竞争超限' }),
      'CAS 竞争超限'
    );
  });

  test('返回值绝不为 [object Object]', () => {
    const result = extractErrorMessage({ kind: 'Ipc', message: '等待响应超时' });
    assert.notEqual(result, '[object Object]');
    assert.ok(!result.includes('[object Object]'));
  });
});

// -----------------------------------------------------------------
// 兼容 Error 实例与字符串（向后兼容旧格式）
// -----------------------------------------------------------------
describe('extractErrorMessage — 兼容 Error 实例与字符串', () => {
  test('从 Error 实例提取 message', () => {
    assert.equal(extractErrorMessage(new Error('boom')), 'boom');
  });

  test('从字符串直接返回', () => {
    assert.equal(extractErrorMessage('字符串错误'), '字符串错误');
  });
});

// -----------------------------------------------------------------
// 边界情况使用 fallback
// -----------------------------------------------------------------
describe('extractErrorMessage — 边界情况使用 fallback', () => {
  test('null 返回默认 fallback', () => {
    assert.equal(extractErrorMessage(null), '未知错误');
  });

  test('undefined 返回默认 fallback', () => {
    assert.equal(extractErrorMessage(undefined), '未知错误');
  });

  test('支持自定义 fallback', () => {
    assert.equal(extractErrorMessage(null, '默认消息'), '默认消息');
  });

  test('空对象返回 fallback', () => {
    assert.equal(extractErrorMessage({}), '未知错误');
  });
});
