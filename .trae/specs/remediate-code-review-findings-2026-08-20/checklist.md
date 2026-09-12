# 修复执行验证清单

## 处置前置与不可覆盖约束

* [ ] 4 个未提交文件已快照备份（含 `git diff > snapshot.patch`）

* [ ] 4 个文件逐项归属结论已记录（「半回退拆坏」vs「用户有意改动」）

* [ ] 未使用 `git checkout`/`git restore`/`git reset --hard` 覆盖未提交改动

## Phase 0 Critical

* [ ] CR1：`main.ahk` 恢复 config\_io/backup\_service 两行 include

* [ ] CR1：`main.ahk` 两处 OnExit 均含 `JoyHotkeyManager.Shutdown()`

* [ ] CR1：`backup_core.ahk:70` 恢复 `ConfigIO.ExportToFile(...)`（`InStr(...,"ExportConfigToFile")==0`）

* [ ] CR1：`config_service.ahk` 三处直调 `ConfigIO`，:407-418 全局包装已删

* [ ] CR1：`layering_security_suites`（`Test_BackupCore_NotCallExportConfigToFile` + `ConfigIOLayeringTests`/`BackupServiceLayeringTests`）全绿

* [ ] CR1：启动无 `Unknown class: ConfigIO/BackupService` 崩溃

* [ ] CR2：非录制/验证模式逐键 `key_send_event` 上报为 0

* [ ] CR2：录制/验证模式行为不变，`test_sender`/`test_ipc_client`/`test_executor` 全绿

* [ ] CR3：developer-guide 无「9 变体 / 13 个 Tauri Command / 三子模块」残留，IpcCommand 13 变体 + 34 commands

## Phase 1 Important（G1\~G10）

* [ ] G1：四类非法输入（分组热键/按键名/控制热键/控制热键冲突）在验证阶段拦截

* [x] G2：同源高频异常落盘 ≤1 次/秒且含 `suppressedCount`（`LogRateLimitTests` 4 用例，AHK 607/607）

* [ ] G3：重复 `toggle_group(active=true)` 不双倍发键、停止后无滞后 up、活跃定时器数 ==1

* [ ] G4：AHK 挂死时 `send()` 超时返回错误，`cargo test --lib` 全绿

* [ ] G5：`state()` 不再返回跨锁引用，`unsafe impl` 降为 0 或有强化 SAFETY 注释

* [ ] G6：单次按键不触发 Acquire/Relinquish，组存活期 `_vJoyRefCount` 稳定为 1

* [ ] G7：`utils.ahk` 不再 `#Include` `json_parser.ahk`，`config_store.ahk` 独立加载不崩，`lib.rs` 无永真断言

* [ ] G8：保存失败如实反馈，joystick 未注入仅启动期拦截一次

* [ ] G9：IPC 分发 + 优雅关机有白盒/序列测试，E2E 抽共享 hook，`appendKnownIssue` 无 `'HIGH'` 硬编码

* [ ] G10：migration-guide/TESTING/test-map/AGENTS 统计口径收敛（无 test-manifest、fuzz=5、明细=汇总）

## Phase 2 Minor（B1\~B12）

* [ ] B1：`cargo tree` 无未用 tracing，`#[deprecated]` 死代码清除，`on_state_change` 零引用

* [ ] B2：`atomic_write` 以方法形式出现，错误返回类型统一，`message()` 对 Io 非空

* [ ] B3：默认 version 无 `"3.0"`，无效热键权衡有注释

* [ ] B4：三处妥协/豁免已登记可 `grep` 命中

* [ ] B5：`grep "block_on"` 无裸 `Handle::current()`，token 随机 + 恒定时间比较，单实例保护，管道名单一权威

* [ ] B6：写入路径拷贝策略一致，`_resetEmergencyTimer` 静态声明，`_StartGroupExecution` 去递归，God Object 首刀拆分且 AHK 全套通过

* [ ] B7：无魔法数字，`Arc::get_mut().expect` 收敛，`cargo fmt --check` 通过，`kill_and_reap` 统一

* [ ] B8：单条消息异常不中断分发，钩子部分注册下无残留

* [ ] B9：`_BridgeImportConfig` 解析 1 次，日志紧凑 JSON，`_nextStepTime` 直接访问

* [ ] B10：AHK/Rust 模块清单与目录 1:1，IpcMessage 字段数正确，妥协表无错章

* [ ] B11：标识三处一致（`com.asd.tauri`），历史报告带勘误，E2E helpers 完整，模式两口径无冲突

* [ ] B12：`run_all_tests.ahk` 含 OnError，`#[ignore]` 口径一致，joystick 三模式 fixture，T8-07† 已定位处置

## Phase 3 回归与收口

* [ ] V-01\~V-15 全量回归全部通过（AHK 语法/全套、Rust 编译/测试、Miri、clippy、fmt、E2E、汇总、覆盖率）

* [ ] 覆盖率维持 \~96.57% 不显著回退

* [ ] 测试统计口径收敛至单一权威来源（test-map.md / AGENTS.md）

* [ ] 历史修复核对表三项 C6/I1/I6 闭环清零，无「引入回归」遗留

* [ ] 修复报告 `docs/remediation-execution-report-2026-08-20.md` 产出（问题解决/步骤/测试结果/后续措施）

