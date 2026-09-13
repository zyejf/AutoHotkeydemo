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
let extractDeepErrorMessage;
let isFatalProtocolError;

before(async () => {
  // 动态导入模块（模块不存在时此处抛错，所有 describe 的测试会标记为失败 = RED）
  const mod = await import('../error_utils.js');
  extractErrorMessage = mod.extractErrorMessage;
  extractDeepErrorMessage = mod.extractDeepErrorMessage;
  isFatalProtocolError = mod.isFatalProtocolError;
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

// -----------------------------------------------------------------
// 空 message 但有 kind 时保留 kind 信息（Minor #3 边界修复）
// -----------------------------------------------------------------
// 背景：tauri.js 的 invoke 错误捕获中，String(err.message ?? '') 在
// err.message 为空字符串时得到 ''，extractErrorMessage 因 length > 0
// 检查失败而走 fallback，丢失了 kind 信息。修复后 fallback 路径应
// 包含 kind，避免完全丢失错误上下文。
describe('extractErrorMessage — 空 message 但有 kind 时保留 kind 信息', () => {
  test('空字符串 message + Config kind 返回 [Config]', () => {
    assert.equal(
      extractErrorMessage({ kind: 'Config', message: '' }),
      '[Config]'
    );
  });

  test('空字符串 message + Ipc kind 返回 [Ipc]', () => {
    assert.equal(
      extractErrorMessage({ kind: 'Ipc', message: '' }),
      '[Ipc]'
    );
  });

  test('缺少 message 属性但有 kind 时返回 [kind]', () => {
    assert.equal(
      extractErrorMessage({ kind: 'Internal' }),
      '[Internal]'
    );
  });

  test('有 kind 时不应返回 [object Object]', () => {
    const result = extractErrorMessage({ kind: 'Config', message: '' });
    assert.notEqual(result, '[object Object]');
    assert.ok(!result.includes('[object Object]'));
  });
});

// -----------------------------------------------------------------
// WebDriver 协议层错误深度展开（BUG-5）
// -----------------------------------------------------------------
// 背景：协议层错误（如 Tauri 自定义协议导致 msedgedriver 报
// "Origin header is not a valid URL"）被 WebDriverIO 包装后，
// 顶层 message 退化为 "unknown error"，真实原因藏进嵌套字段。
// 旧实现 String(err) 得到 "[object Object]: unknown error"，无法定位。
describe('extractDeepErrorMessage — 深度展开协议层包装错误', () => {
  test('从嵌套 cause 中提取真实原因', () => {
    const err = new Error('unknown error');
    err.cause = { message: 'Origin header is not a valid URL' };
    assert.equal(
      extractDeepErrorMessage(err),
      'Origin header is not a valid URL'
    );
  });

  test('从嵌套 originalError 中提取真实原因', () => {
    const err = { message: 'unknown error', originalError: { message: 'no such window' } };
    assert.equal(extractDeepErrorMessage(err), 'no such window');
  });

  test('顶层为退化消息时继续向嵌套层挖掘', () => {
    const err = {
      message: 'unknown error',
      value: { error: 'session not created: This version of Microsoft Edge WebDriver' },
    };
    assert.ok(
      extractDeepErrorMessage(err).includes('session not created'),
      '应跳过退化的 unknown error，挖出真实原因'
    );
  });

  test('字符串输入且非退化时直接返回', () => {
    assert.equal(extractDeepErrorMessage('Origin header is not a valid URL'), 'Origin header is not a valid URL');
  });

  test('退化字符串输入返回 fallback', () => {
    assert.equal(extractDeepErrorMessage('unknown error', '默认'), '默认');
  });

  test('null / undefined 返回 fallback', () => {
    assert.equal(extractDeepErrorMessage(null), '未知错误');
    assert.equal(extractDeepErrorMessage(undefined, '兜底'), '兜底');
  });

  test('返回值绝不为 [object Object]', () => {
    const result = extractDeepErrorMessage({ message: 'unknown error', value: {} });
    assert.ok(!result.includes('[object Object]'));
  });

  test('循环引用不导致栈溢出', () => {
    const err = { message: 'unknown error' };
    err.self = err;
    assert.doesNotThrow(() => extractDeepErrorMessage(err));
  });
});

describe('isFatalProtocolError — 识别协议层确定性错误', () => {
  test('识别 Origin header 错误', () => {
    assert.equal(isFatalProtocolError('Origin header is not a valid URL'), true);
  });

  test('识别 session not created', () => {
    assert.equal(isFatalProtocolError('session not created: version mismatch'), true);
  });

  test('普通业务错误不判定为协议错误', () => {
    assert.equal(isFatalProtocolError('验证失败: 热键不能为空'), false);
  });

  test('空串与 null 返回 false', () => {
    assert.equal(isFatalProtocolError(''), false);
    assert.equal(isFatalProtocolError(null), false);
  });
});
