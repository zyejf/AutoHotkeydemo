# Critical 修复验证清单

## 安全漏洞修复（C3, C4）

- [ ] C3: `webview2_manager.ahk:63` 的 `EnvSet` 调试端口已移除或条件化
- [ ] C3: 编译模式（`A_IsCompiled` 为 true）下调试端口强制不开启
- [ ] C3: 语法检查通过（`/ErrorStdOut` 退出码 0）
- [ ] C4: `webview2_manager.ahk:1171` 路径遍历防护已改为 `InStr` 拒绝式
- [ ] C4: `backup_core.ahk:112` 路径遍历防护已改为 `InStr` 拒绝式
- [ ] C4: `....` 输入被正确拒绝（不再绕过）
- [ ] C4: 语法检查通过

## 架构违规修复（C1）

- [ ] C1: `domain/interfaces.ahk` 新增了 `IJoySender` 抽象基类
- [ ] C1: `infrastructure/joy_sender.ahk` 的 `JoySender` 类 `extends IJoySender`
- [ ] C1: `domain/joystick_executor.ahk` 不再 `#Include` `infrastructure/joy_sender.ahk`
- [ ] C1: `JoystickExecutor` 通过注入的 `IJoySender` 实例调用方法
- [ ] C1: `main.ahk` 的 `InitDependencies()` 完成 `JoySender` 实例创建和注入
- [ ] C1: 语法检查通过
- [ ] C1: 功能正常（手柄按键仍能发送）

## 合规规则修复（C2, C5, C6）

- [ ] C2: `migration_logger.ahk` 包含 `#Warn VarUnset, OutputDebug`
- [ ] C2: `migration_logger.ahk` 包含 `#Warn Unreachable, OutputDebug`
- [ ] C2: `migration_logger.ahk` 包含 `#Warn LocalSameAsGlobal, Off`
- [ ] C2: 语法检查通过
- [ ] C5: `AutoHotUnit.ahk` 包含 `#Requires AutoHotkey v2.0`
- [ ] C5: `AutoHotUnit.ahk` 包含 `#ErrorStdOut "UTF-8"`
- [ ] C5: `AutoHotUnit.ahk` 包含 3 条细粒度 `#Warn` 指令
- [ ] C5: `AutoHotUnit.ahk` 包含 `OnError` 回调
- [ ] C5: `AutoHotUnit.ahk` 不再使用 `#Warn All, StdOut`
- [ ] C5: 语法检查通过 + 测试框架仍正常工作
- [ ] C6: 所有 tests/ 根目录测试文件包含 `OnError` 回调
- [ ] C6: 批量语法检查通过

## 配置文档修复（C8, C9）

- [ ] C8: `Cargo.toml` 不再包含 `test-manifest` feature
- [ ] C8: `AGENTS.md` 不再包含 `test-manifest` 相关描述
- [ ] C8: 测试运行命令已简化（无 `--features test-manifest`）
- [ ] C8: `cargo check` 通过
- [ ] C8: `cargo test --lib` 仍能运行
- [ ] C9: `hotkey_cmd.spec.js` 不再硬编码 AHK 路径
- [ ] C9: `key_receiver.js` 不再硬编码 AHK 路径
- [ ] C9: 路径通过环境变量 `AHK_PATH` 或配置文件读取
- [ ] C9: 提供合理的默认值回退

## 测试覆盖补充（C7, C10）

- [ ] C7: `tests/test_joy_hotkey_manager.ahk` 已创建
- [ ] C7: 测试覆盖热键注册/注销
- [ ] C7: 测试覆盖轴/POV 轮询
- [ ] C7: 测试覆盖热插拔检测
- [ ] C7: 测试覆盖多手柄支持
- [ ] C7: 测试文件遵循标准模板（完整接管指令 + OnError）
- [ ] C7: `run_all_tests.ahk` 已注册新测试
- [ ] C7: 语法检查通过
- [ ] C10: `config_cmd.rs` 11 个 commands 提取了 `_impl` 函数
- [ ] C10: `group_cmd.rs` 8 个 commands 提取了 `_impl` 函数
- [ ] C10: `recording_cmd.rs` 8 个 commands 提取了 `_impl` 函数
- [ ] C10: 每个 `_impl` 函数有正常路径测试
- [ ] C10: 每个 `_impl` 函数有错误路径测试
- [ ] C10: `cargo test --lib` 通过
- [ ] C10: `cargo check` 无错误

## TDD 流程遵守

- [ ] 每个修复先编写了验证测试（RED）
- [ ] 观察了测试失败
- [ ] 编写了最小修复代码（GREEN）
- [ ] 测试通过

## 范围约束

- [ ] 仅修改与 10 项 Critical 相关的代码
- [ ] 未回滚用户已有的工作区变更
- [ ] 未修改与当前修复无关的代码
