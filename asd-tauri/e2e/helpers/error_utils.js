// =================================================================
// 错误消息提取工具 - 统一从多种错误形态提取可读消息
// =================================================================
// 背景：AppError（asd-application/src/error.rs）已从字符串序列化改为
// 结构化 {kind, message} 序列化（I34）。Tauri command 返回 Err(AppError) 时，
// 前端 invoke 会 reject 一个 {kind, message} 对象（非 Error 实例）。
// 旧的 `String(err)` 或 `err instanceof Error ? err.message : String(err)`
// 会得到 "[object Object]"，丢失 message。
//
// 此模块提供 extractErrorMessage，兼容：
//   1. AppError 结构化对象 {kind, message}（I34 之后）
//   2. Error 实例（message 属性）
//   3. 字符串（旧格式或手动抛出）
//   4. message 为空但有 kind 的 AppError（返回 [kind]，Minor #3）
//   5. null/undefined/空对象（返回 fallback）
//
// 单元测试：helpers/__tests__/error_utils.test.js（node:test）
// 运行命令：node --test helpers/__tests__/error_utils.test.js
// =================================================================

/**
 * 构建 fallback：当 AppError 的 message 为空时保留 kind 信息（Minor #3）。
 *
 * 背景：tauri.js 的 invoke 错误捕获中，errorObj.message = String(err.message ?? '')。
 * 当 err.message 为空字符串时，extractErrorMessage 因 length > 0 检查失败而走 fallback，
 * 丢失了 kind 信息。此函数构建包含 kind 的 fallback（如 "[Config]"），确保空 message
 * 时错误类型不丢失。
 *
 * @param {unknown} err - 错误对象，可能是 {kind, message}、null、undefined 等
 * @param {string} fallback - 无法提取 kind 时的默认消息
 * @returns {string} `[kind]` 格式的消息，或 fallback
 */
export function buildKindFallback(err, fallback) {
  if (err != null && typeof err === 'object' && typeof err.kind === 'string' && err.kind.length > 0) {
    return '[' + err.kind + ']';
  }
  return fallback;
}

/**
 * 从多种错误形态提取可读消息。
 *
 * @param {unknown} err - 错误对象，可能是 {kind, message}、Error 实例、字符串等
 * @param {string} [fallback='未知错误'] - 无法提取时的默认消息
 * @returns {string} 可读的错误消息，绝不返回 "[object Object]"
 */
export function extractErrorMessage(err, fallback = '未知错误') {
  // 1. AppError {kind, message} 或 Error 实例：提取非空 message 字符串
  if (err != null && typeof err.message === 'string' && err.message.length > 0) {
    return err.message;
  }
  // 2. 字符串错误（旧格式或手动抛出）
  if (typeof err === 'string' && err.length > 0) {
    return err;
  }
  // 3. AppError 结构化对象但 message 为空：保留 kind 信息避免完全丢失上下文（Minor #3）
  return buildKindFallback(err, fallback);
}

// =================================================================
// WebDriver 协议层错误深度展开（BUG-5）
// =================================================================
// 背景：协议层错误（如 Tauri 自定义协议导致 msedgedriver 拒绝
// "Origin header is not a valid URL"）被 WebDriverIO 包装后，
// 顶层 err.message 常退化为通用串 "unknown error"，真实原因藏进嵌套字段。
// 旧代码用 String(err) 得到 "[object Object]: unknown error"，信息全部丢失，
// 导致 E2E 失败长期无法定位。
//
// 本组函数保证：只要真实原因存在于错误对象的任意层级，就能被挖出来。

/**
 * 退化的消息：拿到它们等于没拿到，必须继续向嵌套层挖掘。
 */
const DEGENERATE_MESSAGES = new Set([
  '',
  'unknown error',
  'error',
  '[object Object]',
  'undefined',
  'null',
]);

/**
 * 协议层确定性错误特征：重试无意义，应立即失败（快失败）。
 * 旧实现对这类错误仍重试 150 次（15 秒），只有延迟没有收益。
 */
const FATAL_PROTOCOL_PATTERNS = [
  'Origin header is not a valid URL',
  'session not created',
  'no such window',
  'invalid session id',
  'unexpected alert open',
];

/**
 * 深度展开错误对象，返回第一个「非退化」的可读消息。
 *
 * 依次尝试各层级的 message / error / cause / originalError / value / data / json，
 * 返回第一个有信息量的字符串。适用于被 WebDriverIO 多层包装的协议错误。
 *
 * @param {unknown} err - 任意错误形态（Error 实例、协议对象、字符串、null）
 * @param {string} [fallback='未知错误'] - 无法提取时的默认消息
 * @returns {string} 可读消息，绝不返回 "[object Object]"
 */
export function extractDeepErrorMessage(err, fallback = '未知错误') {
  if (err == null) return fallback;

  if (typeof err === 'string') {
    return !DEGENERATE_MESSAGES.has(err) ? err : fallback;
  }

  const seen = new Set();
  const candidates = [];

  const visit = (node, depth) => {
    if (node == null || depth > 4) return;
    if (typeof node === 'string') {
      candidates.push(node);
      return;
    }
    if (typeof node !== 'object' || seen.has(node)) return;
    seen.add(node);
    // 按「最可能含真实原因」的顺序展开
    for (const key of [
      'message',
      'error',
      'cause',
      'originalError',
      'value',
      'data',
      'json',
    ]) {
      if (key in node) visit(node[key], depth + 1);
    }
  };

  visit(err, 0);

  for (const msg of candidates) {
    if (typeof msg === 'string' && !DEGENERATE_MESSAGES.has(msg)) return msg;
  }
  return extractErrorMessage(err, fallback);
}

/**
 * 判断消息是否为「协议层确定性错误」——重试无法恢复，应立即失败。
 *
 * @param {string} message - 已提取的错误消息
 * @returns {boolean} 是否应快失败
 */
export function isFatalProtocolError(message) {
  if (typeof message !== 'string' || message.length === 0) return false;
  return FATAL_PROTOCOL_PATTERNS.some((pattern) => message.includes(pattern));
}
