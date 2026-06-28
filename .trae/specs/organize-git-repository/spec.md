# Git 仓库全面梳理与整理 Spec

## Why

当前项目 Git 仓库存在以下问题：
1. `.gitignore` 极度不完整（仅 4 条规则），导致 Rust 构建产物、Node.js 依赖、IDE 配置、OS 临时文件等可能被误提交
2. 提交历史中 commit message 格式不统一（中英文混杂、conventional commit 与自由格式并存、空格不一致）
3. 缺少 Git 配置优化（如行尾符 normalization、默认分支名、pull 策略等）
4. 缺少提交信息模板和规范文档，未来提交可能继续不一致
5. 仓库无远程，缺少备份策略建议

## What Changes

- **增强 `.gitignore`**：新增 Rust（target/、Cargo.lock 除外策略）、Node.js（node_modules/、dist/）、IDE（.vscode/、.idea/）、OS（Thumbs.db、.DS_Store）、AHK 临时文件、测试产物、备份文件等忽略规则
- **建立提交信息规范**：在 `docs/` 下新增 `commit-convention.md`，明确 conventional commit 格式、中英文选择、scope 命名、body/footer 规范
- **新增 Git commit 模板**：`.gitmessage` 模板文件，通过 `git config commit.template` 引用
- **优化 Git 配置**：设置 `core.autocrlf`、`core.safecrlf`、`init.defaultBranch`、`pull.rebase`、`push.default`、`core.longpaths` 等
- **生成整理报告**：`docs/git-cleanup-report.md`，记录整理前后对比、执行操作、后续维护建议
- **不重写历史**：保留现有 60+ 提交历史不变（避免破坏性操作），仅规范未来提交

## Impact

- Affected specs: 无（独立任务）
- Affected code:
  - `.gitignore`（增强）
  - `docs/commit-convention.md`（新建）
  - `.gitmessage`（新建）
  - `docs/git-cleanup-report.md`（新建）
  - `.git/config`（通过 `git config` 命令更新）
- Affected docs: `AGENTS.md`（新增 Git 规范小节引用）

## ADDED Requirements

### Requirement: 全面的 .gitignore

系统 SHALL 维护一个覆盖所有技术栈的 `.gitignore` 文件，确保以下类型的文件不被跟踪：

#### Scenario: Rust 构建产物
- **WHEN** 运行 `cargo build` 生成 `target/` 目录
- **THEN** `target/` 及其所有内容被 Git 忽略

#### Scenario: Node.js 依赖
- **WHEN** 运行 `npm install` 生成 `node_modules/`
- **THEN** `node_modules/` 被忽略，但 `package-lock.json` 被跟踪

#### Scenario: IDE 配置文件
- **WHEN** VSCode/IntelliJ 生成 `.vscode/` 或 `.idea/` 目录
- **THEN** 这些目录被忽略（除团队共享配置外）

#### Scenario: OS 临时文件
- **WHEN** Windows/macOS 生成 `Thumbs.db`、`.DS_Store`、`desktop.ini`
- **THEN** 这些文件被忽略

### Requirement: 提交信息规范文档

系统 SHALL 提供一份提交信息规范文档，明确：

- Conventional Commit 格式（`type(scope): description`）
- 允许的 type 列表（feat、fix、docs、style、refactor、test、chore、perf、ci、build）
- scope 命名约定（asd-domain、asd-ipc-protocol、asd-application、asd-tauri、ahk、test、ci、docs）
- 描述语言选择（中文优先，技术术语保留英文）
- body 和 footer 的可选格式
- BREAKING CHANGE 标注方式

#### Scenario: 开发者撰写提交信息
- **WHEN** 开发者执行 `git commit`
- **THEN** commit message 符合 `<type>(<scope>): <描述>` 格式

### Requirement: Git commit 模板

系统 SHALL 提供一个 `.gitmessage` 模板文件，并通过 `git config commit.template .gitmessage` 启用，使开发者在交互式提交时看到规范提示。

#### Scenario: 交互式提交
- **WHEN** 开发者执行 `git commit`（不带 -m）
- **THEN** 编辑器加载 `.gitmessage` 模板，显示格式提示和示例

### Requirement: Git 配置优化

系统 SHALL 应用以下 Git 配置优化：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `core.autocrlf` | `true`（Windows）| 自动转换 LF/CRLF |
| `core.safecrlf` | `warn` | CRLF 转换警告 |
| `core.longpaths` | `true` | 支持 Windows 长路径 |
| `init.defaultBranch` | `main` | 默认分支名 |
| `pull.rebase` | `false` | 使用 merge 策略 |
| `push.default` | `current` | 推送当前分支 |
| `commit.template` | `.gitmessage` | 提交信息模板 |
| `core.quotepath` | `false` | 正确显示中文文件名 |

#### Scenario: 跨平台协作
- **WHEN** 在 Windows 上检出仓库
- **THEN** 文本文件的行尾符自动转换为 CRLF，提交时转换回 LF

### Requirement: 整理报告

系统 SHALL 生成一份详细的整理报告，包含：

1. 整理前仓库状态快照（分支数、提交数、.gitignore 规则数、配置项）
2. 整理后仓库状态快照
3. 执行的具体操作列表（含命令）
4. 后续维护建议（定期清理、远程备份、hooks 等）

#### Scenario: 整理完成
- **WHEN** 所有整理任务完成
- **THEN** `docs/git-cleanup-report.md` 包含完整的前后对比和操作记录

## MODIFIED Requirements

### Requirement: AGENTS.md Git 规范引用

在 `AGENTS.md` 的 "For AI Agents" 节新增 Git 规范引用，指向 `docs/commit-convention.md`，确保 AI 代理也遵循提交规范。

## REMOVED Requirements

无（本 spec 不删除任何现有功能）

## 设计决策

### 决策 1：不重写 Git 历史

**理由**：
- 现有 60+ 提交已形成项目演进脉络，重写会丢失原始上下文
- `git rebase -i` 或 `git filter-branch` 是破坏性操作，可能导致数据丢失
- 仓库虽无远程，但本地历史也是重要的开发记录

**替代方案**：仅规范未来提交，通过 `.gitmessage` 模板和 `docs/commit-convention.md` 引导

### 决策 2：.gitignore 采用分层结构

**理由**：
- 项目包含 AHK v2 + Rust/Tauri + Node.js 三种技术栈
- 分层结构（全局 → Rust → Node.js → IDE → OS → 项目特定）便于维护
- 参考 GitHub 官方 `gitignore` 模板

### 决策 3：commit.message 以中文为主

**理由**：
- 现有提交历史以中文为主（R14-R21、第34轮审查等）
- `AGENTS.md` 明确要求"使用中文回复"
- 技术术语（如 `conventional commit`、`scope`）保留英文
