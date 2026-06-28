# Tasks

- [ ] Task 1: 仓库状态审计与快照
  - [ ] SubTask 1.1: 运行 `git log --oneline --all | Measure-Object -Line` 记录提交总数
  - [ ] SubTask 1.2: 运行 `git branch -a -vv` 记录分支清单
  - [ ] SubTask 1.3: 运行 `git config --list --local` 记录当前配置
  - [ ] SubTask 1.4: 读取当前 `.gitignore` 内容并记录规则数
  - [ ] SubTask 1.5: 运行 `git ls-files | Measure-Object -Line` 记录已跟踪文件数
  - [ ] SubTask 1.6: 运行 `git status --porcelain` 确认工作树状态
  - [ ] SubTask 1.7: 将审计快照保存到内存（供 Task 7 报告使用）

- [ ] Task 2: 增强 `.gitignore` 文件
  - [ ] SubTask 2.1: 在 `.gitignore` 中新增「Rust」节：`target/`、`**/*.rs.bk`、`Cargo.lock`（注：Cargo.lock 应被跟踪，不忽略）
  - [ ] SubTask 2.2: 新增「Node.js」节：`node_modules/`、`dist/`、`dist-js/`、`.vite/`
  - [ ] SubTask 2.3: 新增「IDE」节：`.vscode/`（保留 `.vscode/settings.json` 若有共享配置）、`.idea/`、`*.swp`、`*.swo`、`*~`
  - [ ] SubTask 2.4: 新增「OS」节：`Thumbs.db`、`ehthumbs.db`、`Desktop.ini`、`.DS_Store`、`$RECYCLE.BIN/`
  - [ ] SubTask 2.5: 新增「AHK 临时文件」节：`*.ahk.bak`、`tmp_*.txt`、`test_err.txt`、`test_out.txt`、`test_stderr.txt`
  - [ ] SubTask 2.6: 新增「测试产物」节：`tests/backups/backup_*.json`、`backups/backup_*.json`、`test-results/`、`coverage/`、`*.lcov`
  - [ ] SubTask 2.7: 新增「Tauri 构建产物」节：`asd-tauri/src-tauri/target/`、`asd-tauri/dist/`
  - [ ] SubTask 2.8: 新增「日志」节（保留现有 `logs/`、`*.log`，补充 `asd-tauri/logs/`）
  - [ ] SubTask 2.9: 保留现有 `nul`、`*.exe` 规则
  - [ ] SubTask 2.10: 验证 `git status` 不显示已被跟踪的文件因新增 .gitignore 规则而异常

- [ ] Task 3: 建立提交信息规范文档
  - [ ] SubTask 3.1: 新建 `docs/commit-convention.md`
  - [ ] SubTask 3.2: 编写「格式规范」节：`<type>(<scope>): <描述>` 格式说明
  - [ ] SubTask 3.3: 编写「允许的 type」节：feat、fix、docs、style、refactor、test、chore、perf、ci、build（含中文说明）
  - [ ] SubTask 3.4: 编写「scope 命名」节：asd-domain、asd-ipc-protocol、asd-application、asd-tauri、asd-test-harness、ahk、test、ci、docs、config
  - [ ] SubTask 3.5: 编写「描述语言」节：中文优先，技术术语保留英文，示例对照
  - [ ] SubTask 3.6: 编写「Body 和 Footer」节：可选、`-` 列表、`BREAKING CHANGE:` 标注
  - [ ] SubTask 3.7: 编写「示例」节：5 个正例 + 3 个反例

- [ ] Task 4: 新增 Git commit 模板
  - [ ] SubTask 4.1: 新建 `.gitmessage` 文件（项目根目录）
  - [ ] SubTask 4.2: 编写模板内容：格式提示、type 列表、scope 列表、示例注释
  - [ ] SubTask 4.3: 运行 `git config commit.template .gitmessage` 启用模板
  - [ ] SubTask 4.4: 验证 `git config commit.template` 返回 `.gitmessage`

- [ ] Task 5: 优化 Git 配置
  - [ ] SubTask 5.1: 运行 `git config core.autocrlf true`（Windows 行尾符自动转换）
  - [ ] SubTask 5.2: 运行 `git config core.safecrlf warn`（CRLF 转换警告）
  - [ ] SubTask 5.3: 运行 `git config core.longpaths true`（支持 Windows 长路径）
  - [ ] SubTask 5.4: 运行 `git config init.defaultBranch main`（默认分支名）
  - [ ] SubTask 5.5: 运行 `git config pull.rebase false`（merge 策略）
  - [ ] SubTask 5.6: 运行 `git config push.default current`（推送当前分支）
  - [ ] SubTask 5.7: 运行 `git config core.quotepath false`（中文文件名显示）
  - [ ] SubTask 5.8: 运行 `git config --list --local` 验证所有配置已生效

- [ ] Task 6: 更新 AGENTS.md 引用
  - [ ] SubTask 6.1: 在 `AGENTS.md` 的 "For AI Agents" 节新增「Git 提交规范」小节
  - [ ] SubTask 6.2: 引用 `docs/commit-convention.md` 路径
  - [ ] SubTask 6.3: 说明 AI 代理在执行 `git commit` 时必须遵循该规范

- [ ] Task 7: 生成整理报告
  - [ ] SubTask 7.1: 新建 `docs/git-cleanup-report.md`
  - [ ] SubTask 7.2: 编写「整理前状态」节：分支数=1、提交数=60+、.gitignore 规则数=4、配置项清单
  - [ ] SubTask 7.3: 编写「整理后状态」节：.gitignore 规则数=N、新增文档清单、配置项清单
  - [ ] SubTask 7.4: 编写「执行操作」节：列出所有 git config 命令、文件创建/修改清单
  - [ ] SubTask 7.5: 编写「后续维护建议」节：定期 `git gc`、远程备份建议、pre-commit hook 建议、年度审查

- [ ] Task 8: 验证与提交
  - [ ] SubTask 8.1: 运行 `git status` 确认所有新增/修改文件已正确识别
  - [ ] SubTask 8.2: 运行 `git diff .gitignore` 验证 .gitignore 增强内容正确
  - [ ] SubTask 8.3: 运行 `git config --list --local` 验证所有配置已生效
  - [ ] SubTask 8.4: 验证 `docs/commit-convention.md`、`.gitmessage`、`docs/git-cleanup-report.md` 内容完整
  - [ ] SubTask 8.5: 提交所有变更（conventional commit 格式）

# Task Dependencies

- [Task 1] 必须最先执行（提供审计基线）
- [Task 2, 3, 4, 5, 6] 可与 [Task 1] 之后并行（无相互依赖）
- [Task 7] 依赖 [Task 1-6] 完成（需要所有操作结果生成报告）
- [Task 8] 依赖 [Task 7] 完成（最终验证与提交）
