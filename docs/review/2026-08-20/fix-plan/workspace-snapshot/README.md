# workspace-snapshot（已清理，2026-09-16）

本目录原本存放 2026-08-20 那次整改的**临时备份**：4 个尚未提交的文件的当前工作区版本，
外加一份 `snapshot.patch`。作用是「任何后续操作都可还原到处置前状态」。

那次整改早已完成并合入，这 4 份代码副本却一直留在 `docs/` 下，会随生产代码改动而
**静默陈旧**——后来者很难分清哪份是权威版本（TD-001）。已于 2026-09-16 移除。

## 曾经在这里的文件

| 文件 | 现在的权威位置 |
|---|---|
| `main.ahk` | 仓库根 `main.ahk` |
| `backup_core.ahk` | `infrastructure/backup_core.ahk` |
| `migration_logger.ahk` | `infrastructure/migration_logger.ahk` |
| `run_all_tests.ahk` | `tests/run_all_tests.ahk` |

`snapshot.patch` 保留（它是当时的 diff 产物，且整改流程文档引用了它）。

## 需要时如何取回

这 4 个文件已随 `5e97fab`（2026-09-12，归档 2026-08-20 审查全量产物）入库，随时可取：

```bash
git show 5e97fab:docs/review/2026-08-20/fix-plan/workspace-snapshot/main.ahk
```

## 约定

`docs/` 下**不再放源码副本**。需要引用代码时写路径 + 行号，或贴关键片段。
该约束由 `scripts/check-tech-debt.py` 的 C1c 自动把关（代码出现在 `docs/` 等
非代码目录即报错）。
