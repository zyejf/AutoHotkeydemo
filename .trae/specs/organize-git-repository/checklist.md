# Checklist

## 仓库状态审计
- [x] 提交总数已记录（整理前）
- [x] 分支清单已记录（整理前，应为仅 main）
- [x] Git 配置已记录（整理前）
- [x] .gitignore 规则数已记录（整理前，应为 4 条）
- [x] 已跟踪文件数已记录（整理前）
- [x] 工作树状态已确认（clean）

## .gitignore 增强
- [x] 新增 Rust 构建产物规则（target/、*.rs.bk）
- [x] 新增 Node.js 依赖规则（node_modules/、dist/、.vite/）
- [x] 新增 IDE 配置规则（.vscode/、.idea/、*.swp、*.swo）
- [x] 新增 OS 临时文件规则（Thumbs.db、.DS_Store、Desktop.ini）
- [x] 新增 AHK 临时文件规则（*.ahk.bak、tmp_*.txt、test_err.txt、test_out.txt）
- [x] 新增测试产物规则（tests/backups/、backups/、test-results/、coverage/、*.lcov）
- [x] 新增 Tauri 构建产物规则（src-tauri/target/、asd-tauri/dist/）
- [x] 保留现有规则（nul、logs/、*.log、*.exe）
- [x] .gitignore 采用分层注释结构（# 分类标题）
- [x] `git status` 未显示已跟踪文件因新规则异常

## 提交信息规范文档
- [x] `docs/commit-convention.md` 已创建
- [x] 文档包含格式规范（`<type>(<scope>): <描述>`）
- [x] 文档包含允许的 type 列表（feat/fix/docs/style/refactor/test/chore/perf/ci/build）
- [x] 文档包含 scope 命名约定（asd-domain/asd-ipc-protocol/asd-application/asd-tauri/asd-test-harness/ahk/test/ci/docs/config）
- [x] 文档包含描述语言选择（中文优先，技术术语保留英文）
- [x] 文档包含 Body 和 Footer 格式说明
- [x] 文档包含 BREAKING CHANGE 标注方式
- [x] 文档包含 5 个正例和 3 个反例

## Git commit 模板
- [x] `.gitmessage` 文件已创建（项目根目录）
- [x] 模板包含格式提示（type(scope): 描述）
- [x] 模板包含 type 列表注释
- [x] 模板包含 scope 列表注释
- [x] `git config commit.template .gitmessage` 已执行
- [x] `git config commit.template` 返回 `.gitmessage`

## Git 配置优化
- [x] `core.autocrlf` 设置为 `true`
- [x] `core.safecrlf` 设置为 `warn`
- [x] `core.longpaths` 设置为 `true`
- [x] `init.defaultBranch` 设置为 `main`
- [x] `pull.rebase` 设置为 `false`
- [x] `push.default` 设置为 `current`
- [x] `commit.template` 设置为 `.gitmessage`
- [x] `core.quotepath` 设置为 `false`
- [x] `git config --list --local` 验证所有配置已生效

## AGENTS.md 更新
- [x] "For AI Agents" 节新增「Git 提交规范」小节
- [x] 引用 `docs/commit-convention.md` 路径
- [x] 说明 AI 代理必须遵循提交规范

## 整理报告
- [x] `docs/git-cleanup-report.md` 已创建
- [x] 报告包含「整理前状态」节（分支数、提交数、.gitignore 规则数、配置项）
- [x] 报告包含「整理后状态」节（新增规则数、新增文档、配置项对比）
- [x] 报告包含「执行操作」节（所有 git config 命令、文件清单）
- [x] 报告包含「后续维护建议」节（git gc、远程备份、pre-commit hook、年度审查）

## 最终验证
- [x] `git status` 显示所有新增/修改文件正确识别
- [x] `git diff .gitignore` 内容正确
- [x] `git config --list --local` 所有配置已生效
- [x] 所有新增文档内容完整
- [x] 所有变更已提交（conventional commit 格式）
