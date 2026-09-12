# Git 提交信息规范

本项目遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范，并以中文为主要描述语言。

## 格式规范

```
<type>(<scope>): <描述>

[可选 Body]

[可选 Footer]
```

- **type**（必填）：提交类型，全小写
- **scope**（可选）：影响范围，全小写
- **描述**（必填）：简洁说明，中文优先，技术术语保留英文
- **描述** 首字母不大写，结尾不加句号
- 整体长度建议不超过 72 字符（描述行）

## 允许的 type

| type | 含义 | 示例场景 |
|------|------|---------|
| `feat` | 新功能 | 新增 IPC 命令、新增 AHK 执行器模块 |
| `fix` | Bug 修复 | 修复并发崩溃、修复配置解析错误 |
| `docs` | 文档变更 | 更新 AGENTS.md、新增测试文档 |
| `style` | 代码风格 | 格式化、空格调整（不影响逻辑） |
| `refactor` | 重构 | 提取公共函数、调整模块结构（无功能变化） |
| `test` | 测试相关 | 新增测试、修复 flaky test、增强测试覆盖 |
| `chore` | 杂项 | 更新依赖、调整配置文件 |
| `perf` | 性能优化 | 减少锁竞争、优化热路径 |
| `ci` | CI/CD | 修改 GitHub Actions、新增 workflow |
| `build` | 构建系统 | 修改 Cargo.toml、调整 Tauri 构建配置 |

## scope 命名约定

| scope | 说明 |
|-------|------|
| `asd-domain` | 领域层 crate（Config, SkillGroup, Validator, traits） |
| `asd-ipc-protocol` | IPC 协议 crate（IpcCommand, IpcMessage, HotkeyMerger） |
| `asd-application` | 应用层 crate（AppState, ConfigRepository, 各服务） |
| `asd-tauri` | Tauri 主 crate（commands, bridge, infrastructure） |
| `asd-test-harness` | 测试工具 crate |
| `ahk` | AHK v2 脚本（main.ahk, domain/, infrastructure/, application/, presentation/） |
| `test` | 跨模块测试相关 |
| `ci` | CI/CD 配置 |
| `docs` | 文档相关 |
| `config` | 配置文件（.gitignore, Cargo.toml, package.json） |

**scope 可省略**：当变更涉及多个模块或全仓范围时，可省略 scope，如 `docs: 更新 README`。

## 描述语言

- **中文优先**：描述主要使用中文，与项目 AGENTS.md 要求一致
- **技术术语保留英文**：如 `conventional commit`、`scope`、`trait`、`crate`、`IPC`、`Tauri`
- **示例对照**：
  - ✅ `feat(asd-ipc-protocol): 新增 HotkeyMerger 热键合并器`
  - ✅ `fix(asd-tauri): 修复 unique_pipe_name 并发碰撞`
  - ❌ `feat(asd-ipc-protocol): Add HotkeyMerger` （应使用中文）
  - ❌ `feat: 新增热键合并器` （缺少 scope）

## Body 和 Footer

### Body（可选）

- 用于补充说明「为什么」做此变更（而非「做了什么」——diff 已说明）
- 每行不超过 72 字符
- 使用 `-` 列表项

**示例**:
```
fix(asd-test-harness): 修复 unique_pipe_name 并发碰撞

原实现使用 std::process::id() + ts%100000 生成管道名，但：
- 同进程内 std::process::id() 相同
- ts%100000 在并行测试中存在生日悖论碰撞

改用 AtomicU64 全局计数器确保每次调用唯一。
```

### Footer（可选）

用于标注 BREAKING CHANGE、关闭的 issue 等。

```
BREAKING CHANGE: IpcCommand 枚举重构，移除已废弃的 Execute 变体
Closes #123
```

## BREAKING CHANGE 标注

有两种方式标注破坏性变更：

1. **在 type 后加 `!`**（推荐）: `feat(asd-ipc-protocol)!: 重构 IpcCommand 枚举`
2. **在 Footer 中标注**: `BREAKING CHANGE: IpcCommand 枚举重构，移除已废弃的 Execute 变体`

## 示例

### 正例

1. `feat(asd-ipc-protocol): 新增 HotkeyMerger 热键合并器`
2. `fix(asd-test-harness): 修复 unique_pipe_name 并发碰撞`
3. `docs(test): 新建 TESTING.md 测试管理文档`
4. `refactor(asd-domain): 将 IpcSender trait 迁移至应用层`
5. `test(asd-tauri): 新增 hotkey_cmd 命令层测试`

### 反例

1. ❌ `update files` — 缺少 type 和 scope
2. ❌ `feat: Add new feature` — 描述应使用中文
3. ❌ `Fix(asd-tauri): 修复 bug.` — type 应小写，描述不应以句号结尾

## 验证

提交前可使用 [commitlint](https://commitlint.js.org/) 或 [commitizen](http://commitizen.github.io/cz-cli/) 工具校验格式。

项目根目录的 `.gitmessage` 模板已配置为 `commit.template`，执行 `git commit`（不带 -m）时会自动加载模板提示。
