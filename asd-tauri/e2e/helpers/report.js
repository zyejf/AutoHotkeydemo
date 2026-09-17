// =================================================================
// 测试报告辅助函数 - 生成 JSON 结果与 Markdown 报告
// =================================================================
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const reportsDir = resolve(__dirname, '..', 'reports');
const resultsPath = resolve(reportsDir, 'test-results.json');
const docsDir = resolve(__dirname, '..', 'docs');
const mdReportPath = resolve(docsDir, 'e2e-test-report.md');
const knownIssuesPath = resolve(docsDir, 'e2e-known-issues.md');

function ensureDir(dir) {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
}

function readResults() {
  if (!existsSync(resultsPath)) return [];
  try {
    return JSON.parse(readFileSync(resultsPath, 'utf-8'));
  } catch {
    return [];
  }
}

/**
 * 追加测试结果到 reports/test-results.json
 * @param {string} testName - 测试名称（建议格式：Suite > case）
 * @param {string} status - PASS / FAIL / SKIP
 * @param {number} durationMs - 耗时（毫秒）
 * @param {string} errorMsg - 失败/跳过原因
 */
export function appendResult(testName, status, durationMs, errorMsg = '') {
  ensureDir(reportsDir);
  const results = readResults();
  results.push({
    testName,
    status,
    durationMs,
    errorMsg,
    timestamp: new Date().toISOString(),
  });
  writeFileSync(resultsPath, JSON.stringify(results, null, 2), 'utf-8');
}

/**
 * 读取 reports/test-results.json，生成 docs/e2e-test-report.md
 * @returns {string} 生成的 Markdown 文件路径
 */
export function generateMarkdownReport() {
  ensureDir(docsDir);
  const results = readResults();
  const total = results.length;
  const passed = results.filter((r) => r.status === 'PASS').length;
  const failed = results.filter((r) => r.status === 'FAIL').length;
  const skipped = results.filter((r) => r.status === 'SKIP').length;
  const passRate = total > 0 ? ((passed / total) * 100).toFixed(1) : '0.0';
  const totalDurationMs = results.reduce((sum, r) => sum + (r.durationMs || 0), 0);
  const totalDurationSec = (totalDurationMs / 1000).toFixed(2);
  const timestamp = new Date().toISOString();

  // 按套件分组（testName 中 " > " 之前为套件名）
  const suites = {};
  const suiteOrder = [];
  for (const r of results) {
    const sepIdx = r.testName.indexOf(' > ');
    const suite = sepIdx >= 0 ? r.testName.substring(0, sepIdx) : 'Default';
    const caseName = sepIdx >= 0 ? r.testName.substring(sepIdx + 3) : r.testName;
    if (!suites[suite]) {
      suites[suite] = [];
      suiteOrder.push(suite);
    }
    suites[suite].push({ ...r, caseName });
  }

  let md = '';
  md += `# E2E 测试报告\n\n`;
  md += `生成时间: ${timestamp}\n\n`;
  md += `## 测试概览\n`;
  md += `- 总数: ${total}\n`;
  md += `- 通过: ${passed}\n`;
  md += `- 失败: ${failed}\n`;
  md += `- 跳过: ${skipped}\n`;
  md += `- 通过率: ${passRate}%\n`;
  md += `- 总耗时: ${totalDurationSec}s\n\n`;
  md += `## 详细结果\n`;

  for (const suite of suiteOrder) {
    md += `\n### ${suite}\n`;
    md += `| 用例 | 状态 | 耗时 | 备注 |\n`;
    md += `|------|------|------|------|\n`;
    for (const c of suites[suite]) {
      const durationCell = c.durationMs != null ? `${c.durationMs}ms` : '-';
      const note = c.errorMsg
        ? String(c.errorMsg).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ')
        : '-';
      md += `| ${c.caseName} | ${c.status} | ${durationCell} | ${note} |\n`;
    }
  }

  writeFileSync(mdReportPath, md, 'utf-8');
  return mdReportPath;
}

/**
 * 追加已知问题到 docs/e2e-known-issues.md
 * @param {string} issueId - 问题 ID
 * @param {string} severity - 严重程度（CRITICAL/HIGH/MEDIUM/LOW）
 * @param {string} steps - 复现步骤
 * @param {string} expected - 预期行为
 * @param {string} actual - 实际行为
 * @param {string} impact - 影响范围
 * @param {string} suggestion - 修复建议
 * @param {string} testCaseId - 关联测试用例 ID
 */
export function appendKnownIssue(
  issueId,
  severity,
  steps,
  expected,
  actual,
  impact,
  suggestion,
  testCaseId = ''
) {
  ensureDir(docsDir);
  const issueHeader = testCaseId
    ? `## ${issueId} [${severity}] (关联用例: ${testCaseId})\n\n`
    : `## ${issueId} [${severity}]\n\n`;
  const issueBody =
    `- **复现步骤:** ${steps}\n` +
    `- **预期:** ${expected}\n` +
    `- **实际:** ${actual}\n` +
    `- **影响:** ${impact}\n` +
    `- **建议:** ${suggestion}\n\n`;

  // ⚠️ 必须按 issueId 去重。本函数在「环境限制」（spec 里显式调用后 return）与
  //    「用例失败」（afterEach）两条路径上都会走到，而 e2e-known-issues.md 是
  //    **已入库**的文档 —— 不去重的话每次 E2E 运行都会追加重复条目，
  //    几十次运行后这份文档就没法看了（2026-09-17 实测：一次运行新增 4 条）。
  //    同一 issueId 只登记一次；内容变了请手工改，不要靠重复追加来「更新」。
  if (existsSync(knownIssuesPath)) {
    const existing = readFileSync(knownIssuesPath, 'utf-8');
    if (existing.includes(`## ${issueId} [`)) {
      return;
    }
    appendFileSync(knownIssuesPath, `${issueHeader}${issueBody}`, 'utf-8');
  } else {
    writeFileSync(knownIssuesPath, `# E2E 已知问题\n\n${issueHeader}${issueBody}`, 'utf-8');
  }
}
