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
