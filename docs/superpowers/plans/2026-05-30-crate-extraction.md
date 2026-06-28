# Crate Extraction 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 asd-tauri 单体 crate 拆分为 4 个 crate 的 workspace，实现严格 DDD 分层

**Architecture:** 4 crate workspace — asd-domain（纯逻辑）、asd-ipc-protocol（IPC 协议）、asd-application（应用逻辑，依赖 domain traits）、asd-tauri（表现层+基础设施实现）

**Tech Stack:** Rust 2021, Cargo workspace, Tauri 2.x, tokio, interprocess

---

## Phase 1: 创建 asd-domain crate

### Task 1: 创建 workspace 根 Cargo.toml

**Files:**
- Create: `asd-tauri/Cargo.toml`

- [ ] **Step 1: 创建 workspace Cargo.toml**

```toml
[workspace]
resolver = "2"
members = [
    "crates/asd-domain",
    "crates/asd-ipc-protocol",
    "crates/asd-application",
    "src-tauri",
]

[workspace.package]
version = "0.1.0"
edition = "2021"

[workspace.dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
indexmap = { version = "2", features = ["serde"] }
thiserror = "2.0"
tracing = "0.1"
```

- [ ] **Step 2: 验证 workspace 结构**

Run: `cd asd-tauri && cargo metadata --format-version 1 2>&1 | Select-Object -First 5`
Expected: 输出包含 workspace members（此时 src-tauri 应能被识别）

### Task 2: 创建 asd-domain 目录结构和 Cargo.toml

**Files:**
- Create: `asd-tauri/crates/asd-domain/Cargo.toml`
- Create: `asd-tauri/crates/asd-domain/src/lib.rs`

- [ ] **Step 1: 创建 Cargo.toml**

```toml
[package]
name = "asd-domain"
version.workspace = true
edition.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
indexmap = { workspace = true }
thiserror = { workspace = true }
```

- [ ] **Step 2: 创建 lib.rs**

```rust
pub mod config;
pub mod models;
pub mod traits;
pub mod validator;
```

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译错误（模块文件不存在），这是预期的

### Task 3: 迁移 config.rs 到 asd-domain（移除 I/O）

**Files:**
- Create: `asd-tauri/crates/asd-domain/src/config.rs`

- [ ] **Step 1: 创建 config.rs（仅数据结构，无 I/O 方法）**

从 `src-tauri/src/domain/config.rs` 复制，执行以下修改：
1. 移除 `use std::fs;` 和 `use std::path::Path;`
2. 移除 `load_default()`, `load_from_file()`, `save()`, `save_to_file()`, `load_from_path()`, `save_to_path()` 方法
3. 移除 `tracing::error!` 和 `tracing::warn!` 引用
4. 保留 `Config` struct, `ControlHotkeys`, `HoldSettings`, `GroupConfig`, `ModeData`, 所有 `*Data` struct, `GroupItem`
5. 保留 `impl Default for Config` 和 `fn default_config()`
6. 保留所有 `#[cfg(test)] mod unit_tests` 中不涉及 I/O 的测试
7. 移除 I/O 相关测试（`test_load_from_file_*`, `test_save_to_file_*`）
8. 将 `crate::domain::config::` 引用改为 `crate::config::`

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译错误（models/traits/validator 模块不存在），这是预期的

### Task 4: 迁移 models.rs 到 asd-domain（仅 SkillGroup）

**Files:**
- Create: `asd-tauri/crates/asd-domain/src/models.rs`

- [ ] **Step 1: 创建 models.rs（仅 SkillGroup）**

从 `src-tauri/src/domain/models.rs` 复制，执行以下修改：
1. 仅保留 `SkillGroup` struct 及其 `serialize_mode_data`, `deserialize_mode_data`, `default_mode_data` 函数
2. 移除 `IpcCommand` enum 和 `IpcMessage` struct（将移至 asd-ipc-protocol）
3. 移除所有 IpcCommand/IpcMessage 相关测试
4. 将 `crate::domain::config::` 引用改为 `crate::config::`
5. 保留 `From<(&String, &GroupConfig)> for SkillGroup` 实现
6. 保留 `test_skill_group_*` 测试

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译错误（traits/validator 模块不存在），这是预期的

### Task 5: 创建 traits.rs

**Files:**
- Create: `asd-tauri/crates/asd-domain/src/traits.rs`

- [ ] **Step 1: 创建 traits.rs**

```rust
use crate::config::WatchdogStateEnum;

pub trait IpcSender: Send + Sync {
    fn send_command(&self, cmd: crate::models::IpcCommand) -> Result<u64, String>;
}

pub trait EventEmitter: Send + Sync {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool;
}

pub trait ProcessWatcher: Send + Sync {
    fn state(&self) -> WatchdogStateEnum;
    fn restart_count(&self) -> u32;
}
```

注意：`IpcSender::send_command` 的参数类型 `IpcCommand` 将在 Phase 2 完成后从 `asd_ipc_protocol::command::IpcCommand` re-export。在 Phase 1 中先使用 `crate::models::IpcCommand` 占位（此时 IpcCommand 仍在 models.rs 中），Phase 2 完成后更新。

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译错误（validator 模块不存在），这是预期的

### Task 6: 迁移 validator.rs 到 asd-domain

**Files:**
- Create: `asd-tauri/crates/asd-domain/src/validator.rs`

- [ ] **Step 1: 创建 validator.rs**

从 `src-tauri/src/domain/validator.rs` 复制全部内容（1666行），执行以下修改：
1. 将 `use crate::domain::config::{GroupConfig, ModeData};` 改为 `use crate::config::{GroupConfig, ModeData};`
2. 将所有 `crate::domain::config::` 引用改为 `crate::config::`
3. 保留全部 213 个测试

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译成功

- [ ] **Step 3: 运行测试**

Run: `cd asd-tauri && cargo test -p asd-domain 2>&1`
Expected: 所有测试通过

- [ ] **Step 4: 提交**

```bash
cd asd-tauri
git add Cargo.toml crates/asd-domain/
git commit -m "feat: create asd-domain crate with config, models, validator, traits"
```

### Task 7: 将 WatchdogStateEnum 移至 asd-domain

**Files:**
- Modify: `asd-tauri/crates/asd-domain/src/config.rs`
- Modify: `asd-tauri/crates/asd-domain/src/lib.rs`

- [ ] **Step 1: 在 asd-domain/src/config.rs 中添加 WatchdogStateEnum**

从 `src-tauri/src/infrastructure/watchdog.rs` 复制 `WatchdogStateEnum` 定义：

```rust
#[derive(Debug, Clone, PartialEq, Serialize)]
pub enum WatchdogStateEnum {
    Idle,
    Starting,
    Running,
    Hung,
    Restarting,
    Recovering,
    Failed,
}
```

- [ ] **Step 2: 更新 lib.rs 添加 re-export**

在 `lib.rs` 中确保 `config` 模块被导出，`WatchdogStateEnum` 可通过 `asd_domain::config::WatchdogStateEnum` 访问。

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译成功

- [ ] **Step 4: 提交**

```bash
cd asd-tauri
git add crates/asd-domain/
git commit -m "feat: add WatchdogStateEnum to asd-domain"
```

---

## Phase 2: 创建 asd-ipc-protocol crate

### Task 8: 创建 asd-ipc-protocol 目录结构和 Cargo.toml

**Files:**
- Create: `asd-tauri/crates/asd-ipc-protocol/Cargo.toml`
- Create: `asd-tauri/crates/asd-ipc-protocol/src/lib.rs`

- [ ] **Step 1: 创建 Cargo.toml**

```toml
[package]
name = "asd-ipc-protocol"
version.workspace = true
edition.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
thiserror = { workspace = true }
```

- [ ] **Step 2: 创建 lib.rs**

```rust
pub mod command;
pub mod error;
pub mod hotkey_merger;
pub mod message;

pub use command::IpcCommand;
pub use error::IpcError;
pub use hotkey_merger::HotkeyMerger;
pub use message::IpcMessage;
```

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-ipc-protocol 2>&1`
Expected: 编译错误（模块文件不存在），这是预期的

### Task 9: 迁移 IpcCommand 到 asd-ipc-protocol

**Files:**
- Create: `asd-tauri/crates/asd-ipc-protocol/src/command.rs`

- [ ] **Step 1: 创建 command.rs**

从 `src-tauri/src/domain/models.rs` 提取 `IpcCommand` enum（第123-186行），原样复制。

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action")]
pub enum IpcCommand {
    #[serde(rename = "toggle_group")]
    ToggleGroup {
        #[serde(rename = "groupId")]
        group_id: String,
        active: bool,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        mode: Option<String>,
        #[serde(
            rename = "keyPressDuration",
            skip_serializing_if = "Option::is_none",
            default
        )]
        key_press_duration: Option<u64>,
        #[serde(rename = "holdKeys", skip_serializing_if = "Option::is_none", default)]
        hold_keys: Option<Vec<String>>,
        #[serde(rename = "holdMode", skip_serializing_if = "Option::is_none", default)]
        hold_mode: Option<String>,
        #[serde(rename = "modeData", skip_serializing_if = "Option::is_none", default)]
        mode_data: Option<serde_json::Value>,
    },
    #[serde(rename = "register_hotkey")]
    RegisterHotkey {
        hotkey: String,
        #[serde(rename = "groupId")]
        group_id: String,
    },
    #[serde(rename = "unregister_hotkey")]
    UnregisterHotkey { hotkey: String },
    #[serde(rename = "start_recording")]
    StartRecording {
        #[serde(rename = "groupId")]
        group_id: String,
        mode: String,
    },
    #[serde(rename = "stop_recording")]
    StopRecording,
    #[serde(rename = "pause_recording")]
    PauseRecording,
    #[serde(rename = "resume_recording")]
    ResumeRecording,
    #[serde(rename = "emergency_release")]
    EmergencyRelease,
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "shutdown")]
    Shutdown,
    #[serde(rename = "hold_mode_toggle")]
    HoldModeToggle { enabled: bool },
    #[serde(rename = "start_validation")]
    StartValidation {
        #[serde(rename = "groupId")]
        group_id: String,
    },
    #[serde(rename = "stop_validation")]
    StopValidation,
}
```

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-ipc-protocol 2>&1`
Expected: 编译错误（其他模块不存在），这是预期的

### Task 10: 迁移 IpcMessage 到 asd-ipc-protocol

**Files:**
- Create: `asd-tauri/crates/asd-ipc-protocol/src/message.rs`

- [ ] **Step 1: 创建 message.rs**

从 `src-tauri/src/domain/models.rs` 提取 `IpcMessage` struct（第188-424行），执行以下修改：
1. 将 `IpcCommand` 引用改为 `crate::command::IpcCommand`
2. 保留所有构造方法：`command()`, `response()`, `ping()`, `pong()`, `execute()`, `result()`, `shutdown()`, `hotkey_event()`, `heartbeat()`, `auth()`
3. 保留 `IpcMessage` 的 `#[cfg(test)] mod tests` 中与 IpcMessage 相关的测试

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-ipc-protocol 2>&1`
Expected: 编译错误（error/hotkey_merger 模块不存在），这是预期的

### Task 11: 迁移 IpcError 到 asd-ipc-protocol

**Files:**
- Create: `asd-tauri/crates/asd-ipc-protocol/src/error.rs`

- [ ] **Step 1: 创建 error.rs**

从 `src-tauri/src/infrastructure/ipc.rs` 提取 `IpcError` enum（第19-63行），原样复制：

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum IpcError {
    #[error("连接已关闭")]
    ConnectionClosed,
    #[error("消息超过大小上限: {0} > {1}")]
    MessageTooLarge(usize, usize),
    #[error("收到空行")]
    EmptyMessage,
    #[error("JSON 解析错误: {0}")]
    JsonError(String),
    #[error("IO 错误: {0}")]
    IoError(String),
    #[error("等待响应超时")]
    Timeout,
    #[error("通道已关闭")]
    ChannelClosed,
    #[error("管道断裂: {0}")]
    PipeBroken(String),
    #[error("命名管道错误: {0}")]
    NameError(String),
    #[error("IPC 认证失败: {0}")]
    AuthFailed(String),
}

impl From<std::io::Error> for IpcError {
    fn from(e: std::io::Error) -> Self {
        let msg = e.to_string();
        if msg.contains("broken pipe")
            || msg.contains("Broken pipe")
            || msg.contains("远程端已关闭")
            || msg.contains("No process")
        {
            IpcError::PipeBroken(msg)
        } else {
            IpcError::IoError(msg)
        }
    }
}

impl From<serde_json::Error> for IpcError {
    fn from(e: serde_json::Error) -> Self {
        IpcError::JsonError(e.to_string())
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-ipc-protocol 2>&1`
Expected: 编译错误（hotkey_merger 模块不存在），这是预期的

### Task 12: 迁移 HotkeyMerger 到 asd-ipc-protocol

**Files:**
- Create: `asd-tauri/crates/asd-ipc-protocol/src/hotkey_merger.rs`

- [ ] **Step 1: 创建 hotkey_merger.rs**

从 `src-tauri/src/infrastructure/ipc.rs` 提取 `HotkeyMerger` struct（第470-513行），执行以下修改：
1. 将 `IpcMessage` 引用改为 `crate::message::IpcMessage`
2. 保留 `HotkeyMerger` struct, `new()`, `merge_window()`, `push()`, `should_flush()`, `flush()`, `impl Default`
3. 保留常量 `HOTKEY_MERGE_WINDOW_MS`
4. 保留 `HotkeyMerger` 相关测试

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-ipc-protocol 2>&1`
Expected: 编译成功

- [ ] **Step 3: 运行测试**

Run: `cd asd-tauri && cargo test -p asd-ipc-protocol 2>&1`
Expected: 所有测试通过

- [ ] **Step 4: 提交**

```bash
cd asd-tauri
git add crates/asd-ipc-protocol/
git commit -m "feat: create asd-ipc-protocol crate with IpcCommand, IpcMessage, IpcError, HotkeyMerger"
```

### Task 13: 更新 asd-domain 的 traits.rs 引用 IpcCommand

**Files:**
- Modify: `asd-tauri/crates/asd-domain/src/traits.rs`
- Modify: `asd-tauri/crates/asd-domain/Cargo.toml`

- [ ] **Step 1: 添加 asd-ipc-protocol 依赖**

在 `asd-domain/Cargo.toml` 中添加：

```toml
asd-ipc-protocol = { path = "../asd-ipc-protocol" }
```

- [ ] **Step 2: 更新 traits.rs**

```rust
use asd_ipc_protocol::IpcCommand;
use crate::config::WatchdogStateEnum;

pub trait IpcSender: Send + Sync {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String>;
}

pub trait EventEmitter: Send + Sync {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool;
}

pub trait ProcessWatcher: Send + Sync {
    fn state(&self) -> WatchdogStateEnum;
    fn restart_count(&self) -> u32;
}
```

- [ ] **Step 3: 从 asd-domain/models.rs 移除 IpcCommand 和 IpcMessage**

将 `models.rs` 中的 `IpcCommand` enum 和 `IpcMessage` struct 及其相关代码全部移除。仅保留 `SkillGroup` 和相关序列化函数。

- [ ] **Step 4: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-domain 2>&1`
Expected: 编译成功

- [ ] **Step 5: 运行测试**

Run: `cd asd-tauri && cargo test -p asd-domain 2>&1`
Expected: 所有测试通过

- [ ] **Step 6: 提交**

```bash
cd asd-tauri
git add crates/asd-domain/
git commit -m "refactor: update asd-domain traits to reference asd-ipc-protocol"
```

---

## Phase 3: 创建 asd-application crate

### Task 14: 创建 asd-application 目录结构和 Cargo.toml

**Files:**
- Create: `asd-tauri/crates/asd-application/Cargo.toml`
- Create: `asd-tauri/crates/asd-application/src/lib.rs`

- [ ] **Step 1: 创建 Cargo.toml**

```toml
[package]
name = "asd-application"
version.workspace = true
edition.workspace = true

[dependencies]
asd-domain = { path = "../asd-domain" }
asd-ipc-protocol = { path = "../asd-ipc-protocol" }
serde = { workspace = true }
serde_json = { workspace = true }
indexmap = { workspace = true }
thiserror = { workspace = true }
tracing = { workspace = true }
```

- [ ] **Step 2: 创建 lib.rs**

```rust
pub mod config_repository;
pub mod error;
pub mod scheduler;
pub mod state;
```

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-application 2>&1`
Expected: 编译错误（模块文件不存在），这是预期的

### Task 15: 创建 error.rs（AppError）

**Files:**
- Create: `asd-tauri/crates/asd-application/src/error.rs`

- [ ] **Step 1: 创建 error.rs**

从 `src-tauri/src/application/state.rs` 提取 `AppError` enum（第15-44行）：

```rust
use asd_ipc_protocol::IpcError;
use serde::Serialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("配置错误: {0}")]
    Config(String),
    #[error("IPC 通信错误: {0}")]
    Ipc(String),
    #[error("分组不存在: {0}")]
    GroupNotFound(String),
    #[error("验证失败: {0}")]
    Validation(String),
    #[error("执行器错误: {0}")]
    Executor(String),
    #[error("内部错误: {0}")]
    Internal(String),
}

impl Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

impl From<IpcError> for AppError {
    fn from(e: IpcError) -> Self {
        AppError::Ipc(e.to_string())
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-application 2>&1`
Expected: 编译错误（其他模块不存在），这是预期的

### Task 16: 创建 config_repository.rs

**Files:**
- Create: `asd-tauri/crates/asd-application/src/config_repository.rs`

- [ ] **Step 1: 创建 config_repository.rs**

从 `src-tauri/src/domain/config.rs` 提取 I/O 方法，改为关联函数：

```rust
use asd_domain::config::Config;
use std::fs;
use std::path::Path;

pub struct ConfigRepository;

impl ConfigRepository {
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Config {
        let path = path.as_ref();
        match fs::read_to_string(path) {
            Ok(content) => {
                let cleaned = content.trim_start_matches('\u{feff}');
                match serde_json::from_str(cleaned) {
                    Ok(config) => config,
                    Err(e) => {
                        tracing::error!("配置文件解析失败: {e}");
                        Config::default()
                    }
                }
            }
            Err(e) => {
                tracing::warn!("配置文件读取失败: {e}，使用默认配置");
                Config::default()
            }
        }
    }

    pub fn save_to_file<P: AsRef<Path>>(config: &Config, path: P) -> Result<(), String> {
        let path = path.as_ref();
        let json =
            serde_json::to_string_pretty(config).map_err(|e| format!("序列化配置失败: {e}"))?;
        fs::write(path, json).map_err(|e| format!("写入配置文件失败: {e}"))?;
        Ok(())
    }

    pub fn load_from_path<P: AsRef<Path>>(path: P) -> Result<Config, String> {
        let path = path.as_ref();
        let content = fs::read_to_string(path).map_err(|e| format!("读取配置文件失败: {e}"))?;
        let cleaned = content.trim_start_matches('\u{feff}');
        serde_json::from_str(cleaned).map_err(|e| format!("解析配置文件失败: {e}"))
    }

    pub fn save_to_path<P: AsRef<Path>>(config: &Config, path: P) -> Result<(), String> {
        let path = path.as_ref();
        let json =
            serde_json::to_string_pretty(config).map_err(|e| format!("序列化配置失败: {e}"))?;

        let file_name = path
            .file_name()
            .ok_or_else(|| "无效的文件路径".to_string())?
            .to_string_lossy()
            .to_string();
        let tmp_file_name = format!(".tmp_{file_name}");
        let tmp_path = path.with_file_name(&tmp_file_name);

        fs::write(&tmp_path, &json).map_err(|e| format!("写入临时配置文件失败: {e}"))?;

        if let Err(e) = fs::rename(&tmp_path, path) {
            let _ = fs::remove_file(&tmp_path);
            return Err(format!("重命名配置文件失败: {e}"));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;

    #[test]
    fn test_load_from_file_valid_file() {
        let dir = std::env::temp_dir().join("asd_test_load_from_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("test_config.json");
        let config = Config::default();
        let json = serde_json::to_string_pretty(&config).unwrap();
        std::fs::write(&path, json).unwrap();

        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
        assert_eq!(loaded.version.as_deref(), Some("3.0"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_load_from_file_missing_file_falls_back() {
        let path = std::path::PathBuf::from("/nonexistent/path/config.json");
        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");
    }

    #[test]
    fn test_load_from_file_invalid_json_falls_back() {
        let dir = std::env::temp_dir().join("asd_test_load_invalid_json");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("bad_config.json");
        std::fs::write(&path, "{invalid json!!!}").unwrap();

        let loaded = ConfigRepository::load_from_file(&path);
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_save_to_file_atomic_write() {
        let dir = std::env::temp_dir().join("asd_test_save_to_file");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("atomic_config.json");
        let config = Config::default();

        ConfigRepository::save_to_file(&config, &path).expect("save_to_file 应成功");

        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).expect("保存的文件应可解析");
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_save_to_file_invalid_directory_returns_error() {
        let path = std::path::PathBuf::from("/nonexistent/directory/config.json");
        let config = Config::default();
        let result = ConfigRepository::save_to_file(&config, &path);
        assert!(result.is_err(), "无效路径应返回 Err");
    }

    #[test]
    fn test_save_to_path_atomic() {
        let dir = std::env::temp_dir().join("asd_test_save_to_path");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let path = dir.join("atomic_config.json");
        let config = Config::default();

        ConfigRepository::save_to_path(&config, &path).expect("save_to_path 应成功");

        let content = std::fs::read_to_string(&path).unwrap();
        let loaded: Config = serde_json::from_str(&content).expect("保存的文件应可解析");
        assert_eq!(loaded.control_hotkeys.emergency, "F10");

        let _ = std::fs::remove_dir_all(&dir);
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-application 2>&1`
Expected: 编译错误（scheduler/state 模块不存在），这是预期的

### Task 17: 迁移 scheduler.rs 到 asd-application

**Files:**
- Create: `asd-tauri/crates/asd-application/src/scheduler.rs`

- [ ] **Step 1: 创建 scheduler.rs**

从 `src-tauri/src/application/scheduler.rs` 复制，执行以下修改：
1. 移除 `use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};`
2. `SkillManager::new()` 不再接收 `IpcOutboundSender`，改为接收 `Arc<dyn IpcSender>`
3. 移除 `ipc_outbound` 字段
4. `send_ipc_command` 改为接收 `&dyn IpcSender` 而非 `&tokio::sync::Mutex<Option<IpcManager>>`
5. `emergency_release` 和 `hold_mode_toggle` 改为接收 `&dyn IpcSender`
6. 将 `use crate::domain::models::IpcCommand;` 改为 `use asd_ipc_protocol::IpcCommand;`
7. 将 `use crate::domain::config::*;` 改为 `use asd_domain::config::*;`
8. 将 `use crate::domain::models::SkillGroup;` 改为 `use asd_domain::models::SkillGroup;`
9. 保留测试，将 `tokio::sync::mpsc::channel` 替换为 mock `IpcSender` 实现

```rust
use asd_domain::models::SkillGroup;
use asd_domain::traits::IpcSender;
use asd_ipc_protocol::IpcCommand;
use std::collections::HashMap;
use std::sync::Arc;

pub struct SkillManager {
    groups: HashMap<String, SkillGroup>,
    hotkey_registry: HashMap<String, String>,
    ipc_sender: Arc<dyn IpcSender>,
}

impl SkillManager {
    pub fn new(groups: HashMap<String, SkillGroup>, ipc_sender: Arc<dyn IpcSender>) -> Self {
        Self {
            groups,
            hotkey_registry: HashMap::new(),
            ipc_sender,
        }
    }

    pub fn toggle(&mut self, group_id: &str) -> Result<bool, String> {
        let group = self
            .groups
            .get(group_id)
            .ok_or_else(|| format!("分组不存在: {group_id}"))?;
        let new_active = !group.active;
        if new_active {
            self.activate(group_id)?;
        } else {
            self.deactivate(group_id)?;
        }
        Ok(new_active)
    }

    pub fn activate(&mut self, group_id: &str) -> Result<(), String> {
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or_else(|| format!("分组不存在: {group_id}"))?;
        group.active = true;
        self.hotkey_registry
            .insert(group.hotkey.clone(), group_id.to_string());
        tracing::info!("分组 {} 已激活", group_id);
        Ok(())
    }

    pub fn deactivate(&mut self, group_id: &str) -> Result<(), String> {
        let group = self
            .groups
            .get_mut(group_id)
            .ok_or_else(|| format!("分组不存在: {group_id}"))?;
        group.active = false;
        self.hotkey_registry.remove(&group.hotkey);
        tracing::info!("分组 {} 已停用", group_id);
        Ok(())
    }

    pub fn get_active_groups(&self) -> Vec<&SkillGroup> {
        self.groups.values().filter(|g| g.active).collect()
    }

    pub fn get_group(&self, group_id: &str) -> Option<&SkillGroup> {
        self.groups.get(group_id)
    }

    pub fn get_group_mut(&mut self, group_id: &str) -> Option<&mut SkillGroup> {
        self.groups.get_mut(group_id)
    }

    pub fn all_groups(&self) -> &HashMap<String, SkillGroup> {
        &self.groups
    }

    pub fn reload_groups(&mut self, groups: HashMap<String, SkillGroup>) {
        self.hotkey_registry.clear();
        for group in groups.values() {
            if group.active {
                self.hotkey_registry
                    .insert(group.hotkey.clone(), group.id.clone());
            }
        }
        self.groups = groups;
    }

    pub fn register_hotkey(&mut self, hotkey: &str, group_id: &str) -> Result<(), String> {
        if let Some(existing_id) = self.hotkey_registry.get(hotkey) {
            return Err(format!("热键 '{}' 已被分组 '{}' 注册", hotkey, existing_id));
        }
        self.hotkey_registry
            .insert(hotkey.to_string(), group_id.to_string());
        tracing::info!("热键 '{}' 已注册到分组 '{}'", hotkey, group_id);
        Ok(())
    }

    pub fn unregister_hotkey(&mut self, hotkey: &str) -> Result<(), String> {
        if self.hotkey_registry.remove(hotkey).is_some() {
            tracing::info!("热键 '{}' 已注销", hotkey);
            Ok(())
        } else {
            Err(format!("热键 '{}' 未注册", hotkey))
        }
    }

    pub fn get_hotkey_group(&self, hotkey: &str) -> Option<&str> {
        self.hotkey_registry.get(hotkey).map(|s| s.as_str())
    }

    pub fn build_toggle_command(group: &SkillGroup) -> IpcCommand {
        IpcCommand::ToggleGroup {
            group_id: group.id.clone(),
            active: group.active,
            mode: Some(group.mode.clone()),
            key_press_duration: if group.key_press_duration > 0 {
                Some(group.key_press_duration)
            } else {
                None
            },
            hold_keys: group.hold_keys.clone(),
            hold_mode: group.hold_mode.clone(),
            mode_data: serde_json::to_value(&group.mode_data)
                .ok()
                .filter(|v| !v.is_null()),
        }
    }

    pub fn emergency_release(ipc_sender: &dyn IpcSender) -> Result<(), String> {
        let cmd = IpcCommand::EmergencyRelease;
        ipc_sender.send_command(cmd)?;
        Ok(())
    }

    pub fn hold_mode_toggle(ipc_sender: &dyn IpcSender, enabled: bool) -> Result<(), String> {
        let cmd = IpcCommand::HoldModeToggle { enabled };
        ipc_sender.send_command(cmd)?;
        Ok(())
    }
}
```

- [ ] **Step 2: 添加测试（使用 mock IpcSender）**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use asd_domain::config::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct MockIpcSender {
        seq: AtomicU64,
    }

    impl MockIpcSender {
        fn new() -> Self {
            Self { seq: AtomicU64::new(1) }
        }
    }

    impl IpcSender for MockIpcSender {
        fn send_command(&self, _cmd: IpcCommand) -> Result<u64, String> {
            Ok(self.seq.fetch_add(1, Ordering::Relaxed))
        }
    }

    fn make_skill_group(id: &str, mode: &str) -> SkillGroup {
        let mode_data = match mode {
            "periodic" => ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
            "sequence" => ModeData::Sequence(SequenceData {
                keys: vec!["1".to_string()],
                delays: vec![100],
            }),
            "enhanced_periodic" => ModeData::EnhancedPeriodic(EnhancedPeriodicData {
                press_keys: vec!["Space".to_string()],
                intervals: vec![50],
            }),
            _ => ModeData::Periodic(PeriodicData {
                keys: vec!["1".to_string()],
                intervals: vec![50],
            }),
        };

        SkillGroup {
            id: id.to_string(),
            name: format!("组 {id}"),
            hotkey: format!("F{id}"),
            active: false,
            mode: mode.to_string(),
            key_press_duration: 10,
            hold_keys: None,
            hold_mode: None,
            mode_data,
        }
    }

    fn make_manager() -> SkillManager {
        let mut groups = HashMap::new();
        groups.insert("1".to_string(), make_skill_group("1", "periodic"));
        groups.insert("2".to_string(), make_skill_group("2", "sequence"));
        let sender = Arc::new(MockIpcSender::new());
        SkillManager::new(groups, sender)
    }

    #[test]
    fn test_toggle_group() {
        let mut mgr = make_manager();
        assert!(!mgr.get_group("1").unwrap().active);
        let result = mgr.toggle("1").unwrap();
        assert!(result);
        assert!(mgr.get_group("1").unwrap().active);
        let result = mgr.toggle("1").unwrap();
        assert!(!result);
        assert!(!mgr.get_group("1").unwrap().active);
    }

    #[test]
    fn test_activate_deactivate() {
        let mut mgr = make_manager();
        mgr.activate("1").unwrap();
        assert!(mgr.get_group("1").unwrap().active);
        mgr.deactivate("1").unwrap();
        assert!(!mgr.get_group("1").unwrap().active);
    }

    #[test]
    fn test_activate_nonexistent() {
        let mut mgr = make_manager();
        let result = mgr.activate("999");
        assert!(result.is_err());
    }

    #[test]
    fn test_get_active_groups() {
        let mut mgr = make_manager();
        assert!(mgr.get_active_groups().is_empty());
        mgr.activate("1").unwrap();
        assert_eq!(mgr.get_active_groups().len(), 1);
        mgr.activate("2").unwrap();
        assert_eq!(mgr.get_active_groups().len(), 2);
    }

    #[test]
    fn test_register_hotkey() {
        let mut mgr = make_manager();
        mgr.register_hotkey("F3", "3").unwrap();
        assert_eq!(mgr.get_hotkey_group("F3"), Some("3"));
    }

    #[test]
    fn test_register_duplicate_hotkey() {
        let mut mgr = make_manager();
        mgr.register_hotkey("F3", "3").unwrap();
        let result = mgr.register_hotkey("F3", "4");
        assert!(result.is_err());
    }

    #[test]
    fn test_unregister_hotkey() {
        let mut mgr = make_manager();
        mgr.register_hotkey("F3", "3").unwrap();
        mgr.unregister_hotkey("F3").unwrap();
        assert_eq!(mgr.get_hotkey_group("F3"), None);
    }

    #[test]
    fn test_unregister_nonexistent_hotkey() {
        let mut mgr = make_manager();
        let result = mgr.unregister_hotkey("F99");
        assert!(result.is_err());
    }

    #[test]
    fn test_hotkey_registry_on_activate() {
        let mut mgr = make_manager();
        mgr.activate("1").unwrap();
        assert_eq!(mgr.get_hotkey_group("F1"), Some("1"));
        mgr.deactivate("1").unwrap();
        assert_eq!(mgr.get_hotkey_group("F1"), None);
    }

    #[test]
    fn test_build_toggle_command() {
        let group = make_skill_group("1", "periodic");
        let cmd = SkillManager::build_toggle_command(&group);
        match cmd {
            IpcCommand::ToggleGroup { group_id, active, .. } => {
                assert_eq!(group_id, "1");
                assert!(!active);
            }
            _ => panic!("Expected ToggleGroup"),
        }
    }

    #[test]
    fn test_build_toggle_command_active() {
        let mut group = make_skill_group("1", "periodic");
        group.active = true;
        let cmd = SkillManager::build_toggle_command(&group);
        match cmd {
            IpcCommand::ToggleGroup { group_id, active, .. } => {
                assert_eq!(group_id, "1");
                assert!(active);
            }
            _ => panic!("Expected ToggleGroup"),
        }
    }

    #[test]
    fn test_reload_groups() {
        let mut mgr = make_manager();
        mgr.activate("1").unwrap();
        assert!(mgr.get_hotkey_group("F1").is_some());

        let mut new_groups = HashMap::new();
        new_groups.insert("3".to_string(), make_skill_group("3", "periodic"));
        mgr.reload_groups(new_groups);

        assert!(mgr.get_group("1").is_none());
        assert!(mgr.get_group("3").is_some());
        assert!(mgr.get_hotkey_group("F1").is_none());
    }

    #[test]
    fn test_all_groups() {
        let mgr = make_manager();
        assert_eq!(mgr.all_groups().len(), 2);
    }

    #[test]
    fn test_get_group_mut() {
        let mut mgr = make_manager();
        let group = mgr.get_group_mut("1").unwrap();
        group.active = true;
        assert!(mgr.get_group("1").unwrap().active);
    }
}
```

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-application 2>&1`
Expected: 编译错误（state 模块不存在），这是预期的

### Task 18: 迁移 state.rs 到 asd-application

**Files:**
- Create: `asd-tauri/crates/asd-application/src/state.rs`

- [ ] **Step 1: 创建 state.rs**

从 `src-tauri/src/application/state.rs` 复制，执行以下修改：
1. 移除 `use tauri::Emitter;`
2. 移除 `use crate::infrastructure::ipc::{IpcManager, IpcOutboundSender};`
3. 移除 `use crate::infrastructure::watchdog::{ProcessWatchdog, WatchdogStateEnum};`
4. 将 `tauri::AppHandle` 替换为 `Arc<dyn EventEmitter>`
5. 将 `IpcOutboundSender` 替换为 `Arc<dyn IpcSender>`
6. 将 `WatchdogStateEnum` 改为从 `asd_domain::config::WatchdogStateEnum` 引用
7. 将 `crate::infrastructure::ipc::IpcError` 改为 `asd_ipc_protocol::IpcError`
8. `emit_event` 方法改为调用 `EventEmitter::emit()`
9. `save_config_atomic` 中使用 `ConfigRepository::save_to_path()` 替代 `Config::save_to_path()`
10. 保留 `WatchdogState` struct（内部状态），但 `AppState` 不再直接持有 `ProcessWatchdog`

关键变化：
- `AppState::new()` 签名改为接收 `Arc<dyn IpcSender>` 和 `Arc<dyn EventEmitter>`
- `app_handle: RwLock<Option<tauri::AppHandle>>` 替换为 `event_emitter: Arc<dyn EventEmitter>`
- `ipc_outbound: IpcOutboundSender` 替换为 `ipc_sender: Arc<dyn IpcSender>`
- `ipc_manager: tokio::sync::Mutex<Option<IpcManager>>` 保留在 asd-tauri 的桥接层

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-application 2>&1`
Expected: 编译成功

- [ ] **Step 3: 运行测试**

Run: `cd asd-tauri && cargo test -p asd-application 2>&1`
Expected: 所有测试通过

- [ ] **Step 4: 提交**

```bash
cd asd-tauri
git add crates/asd-application/
git commit -m "feat: create asd-application crate with scheduler, state, error, config_repository"
```

---

## Phase 4: 重构 asd-tauri 主 crate

### Task 19: 更新 src-tauri/Cargo.toml

**Files:**
- Modify: `asd-tauri/src-tauri/Cargo.toml`

- [ ] **Step 1: 添加新 crate 依赖**

在 `[dependencies]` 中添加：

```toml
asd-domain = { path = "../crates/asd-domain" }
asd-ipc-protocol = { path = "../crates/asd-ipc-protocol" }
asd-application = { path = "../crates/asd-application" }
```

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译错误（import 路径不匹配），这是预期的

### Task 20: 创建 bridge.rs

**Files:**
- Create: `asd-tauri/src-tauri/src/bridge.rs`

- [ ] **Step 1: 创建 IpcSenderBridge**

```rust
use asd_domain::traits::IpcSender;
use asd_ipc_protocol::IpcCommand;
use asd_ipc_protocol::IpcMessage;
use crate::infrastructure::ipc::IpcManager;
use std::sync::Arc;

pub struct IpcSenderBridge {
    ipc_manager: Arc<tokio::sync::Mutex<Option<IpcManager>>>,
}

impl IpcSenderBridge {
    pub fn new(ipc_manager: Arc<tokio::sync::Mutex<Option<IpcManager>>>) -> Self {
        Self { ipc_manager }
    }
}

impl IpcSender for IpcSenderBridge {
    fn send_command(&self, cmd: IpcCommand) -> Result<u64, String> {
        let mgr = self.ipc_manager.clone();
        let rt = tokio::runtime::Handle::current();
        rt.block_on(async {
            let mut guard = mgr.lock().await;
            let manager = guard
                .as_mut()
                .ok_or_else(|| "IPC 管理器未初始化".to_string())?;
            manager
                .send_command(cmd)
                .await
                .map_err(|e| format!("IPC 发送失败: {e}"))
        })
    }
}
```

- [ ] **Step 2: 创建 EventEmitterBridge**

```rust
use asd_domain::traits::EventEmitter;
use std::sync::RwLock;
use tauri::Emitter;

pub struct EventEmitterBridge {
    app_handle: RwLock<Option<tauri::AppHandle>>,
}

impl EventEmitterBridge {
    pub fn new() -> Self {
        Self {
            app_handle: RwLock::new(None),
        }
    }

    pub fn set_app_handle(&self, handle: tauri::AppHandle) {
        if let Ok(mut guard) = self.app_handle.write() {
            *guard = Some(handle);
        }
    }
}

impl EventEmitter for EventEmitterBridge {
    fn emit(&self, event: &str, payload: serde_json::Value) -> bool {
        if let Ok(guard) = self.app_handle.read() {
            if let Some(ref handle) = *guard {
                match handle.emit(event, payload) {
                    Ok(()) => true,
                    Err(e) => {
                        tracing::warn!("emit 事件 '{event}' 失败: {e}");
                        false
                    }
                }
            } else {
                false
            }
        } else {
            false
        }
    }
}
```

- [ ] **Step 3: 创建 ProcessWatcherBridge**

```rust
use asd_domain::config::WatchdogStateEnum;
use asd_domain::traits::ProcessWatcher;
use crate::infrastructure::watchdog::ProcessWatchdog;

pub struct ProcessWatcherBridge {
    watchdog: Arc<tokio::sync::Mutex<ProcessWatchdog>>,
}

impl ProcessWatcherBridge {
    pub fn new(watchdog: Arc<tokio::sync::Mutex<ProcessWatchdog>>) -> Self {
        Self { watchdog }
    }
}

impl ProcessWatcher for ProcessWatcherBridge {
    fn state(&self) -> WatchdogStateEnum {
        let rt = tokio::runtime::Handle::current();
        rt.block_on(async {
            let guard = self.watchdog.lock().await;
            guard.state().clone()
        })
    }

    fn restart_count(&self) -> u32 {
        let rt = tokio::runtime::Handle::current();
        rt.block_on(async {
            let guard = self.watchdog.lock().await;
            guard.restart_count()
        })
    }
}
```

- [ ] **Step 4: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译错误（lib.rs 未引用 bridge），这是预期的

### Task 21: 更新 lib.rs 使用新 crate

**Files:**
- Modify: `asd-tauri/src-tauri/src/lib.rs`

- [ ] **Step 1: 更新 import 路径**

将所有 `crate::domain::*` 改为 `asd_domain::*`，`crate::infrastructure::ipc::*` 中的 `IpcCommand`/`IpcMessage` 改为 `asd_ipc_protocol::*`，`crate::application::state::*` 改为 `asd_application::*`。

关键替换：
- `use crate::domain::config::Config;` → `use asd_domain::config::Config;`
- `use crate::domain::models::{IpcCommand, IpcMessage, SkillGroup};` → `use asd_ipc_protocol::{IpcCommand, IpcMessage}; use asd_domain::models::SkillGroup;`
- `use crate::infrastructure::ipc::{IpcManager, IpcOutboundReceiver};` → `use crate::infrastructure::ipc::{IpcManager, IpcOutboundReceiver};`
- `use crate::infrastructure::watchdog::{ProcessWatchdog, WatchdogRunner, WatchdogStateEnum};` → `use crate::infrastructure::watchdog::{ProcessWatchdog, WatchdogRunner}; use asd_domain::config::WatchdogStateEnum;`
- `use crate::application::state::AppState;` → `use asd_application::state::AppState;`

- [ ] **Step 2: 更新 AppState 构造**

在 `setup()` 中，使用 bridge 实现：

```rust
let ipc_sender_bridge = Arc::new(IpcSenderBridge::new(Arc::clone(&app_state.ipc_manager)));
let event_emitter_bridge = Arc::new(EventEmitterBridge::new());
event_emitter_bridge.set_app_handle(app.handle().clone());

let mut app_state = Arc::new(AppState::new(
    config,
    ipc_sender_bridge,
    event_emitter_bridge.clone(),
    watchdog,
));
```

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 逐步修复编译错误

### Task 22: 更新 commands/ 使用新 crate

**Files:**
- Modify: `asd-tauri/src-tauri/src/commands/config_cmd.rs`
- Modify: `asd-tauri/src-tauri/src/commands/group_cmd.rs`
- Modify: `asd-tauri/src-tauri/src/commands/hotkey_cmd.rs`
- Modify: `asd-tauri/src-tauri/src/commands/recording_cmd.rs`
- Modify: `asd-tauri/src-tauri/src/commands/system_cmd.rs`

- [ ] **Step 1: 更新 config_cmd.rs**

替换 import：
- `use crate::application::state::{AppError, AppState};` → `use asd_application::state::{AppError, AppState};`
- `use crate::domain::config::Config;` → `use asd_domain::config::Config;`
- `use crate::domain::validator::{ConfigValidator, ValidationResult};` → `use asd_domain::validator::{ConfigValidator, ValidationResult};`

更新 `Config::load_from_path` → `ConfigRepository::load_from_path`
更新 `Config::save_to_path` → `ConfigRepository::save_to_path`
更新 `config.save_to_path` → `ConfigRepository::save_to_path(&config, ...)`

- [ ] **Step 2: 更新 group_cmd.rs**

替换 import：
- `use crate::application::state::{AppError, AppState};` → `use asd_application::state::{AppError, AppState};`
- `use crate::domain::models::IpcCommand;` → `use asd_ipc_protocol::IpcCommand;`
- `use crate::domain::models::SkillGroup;` → `use asd_domain::models::SkillGroup;`

- [ ] **Step 3: 更新 hotkey_cmd.rs**

替换 import：
- `use crate::application::state::{AppError, AppState};` → `use asd_application::state::{AppError, AppState};`
- `use crate::domain::models::IpcCommand;` → `use asd_ipc_protocol::IpcCommand;`

- [ ] **Step 4: 更新 recording_cmd.rs**

替换 import：
- `use crate::application::state::{AppError, AppState};` → `use asd_application::state::{AppError, AppState};`
- `use crate::domain::models::IpcCommand;` → `use asd_ipc_protocol::IpcCommand;`

- [ ] **Step 5: 更新 system_cmd.rs**

替换 import：
- `use crate::application::scheduler::SkillManager;` → `use asd_application::scheduler::SkillManager;`
- `use crate::application::state::{AppError, AppState};` → `use asd_application::state::{AppError, AppState};`
- `use crate::infrastructure::watchdog::WatchdogStateEnum;` → `use asd_domain::config::WatchdogStateEnum;`

- [ ] **Step 6: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 23: 更新 infrastructure/ipc.rs

**Files:**
- Modify: `asd-tauri/src-tauri/src/infrastructure/ipc.rs`

- [ ] **Step 1: 移除已迁移的类型**

从 `ipc.rs` 中移除：
1. `IpcError` enum 及其 `impl` 块（已迁移至 asd-ipc-protocol）
2. `HotkeyMerger` struct 及其 `impl` 块（已迁移至 asd-ipc-protocol）
3. 相关常量 `HOTKEY_MERGE_WINDOW_MS`
4. 相关测试

替换为从 asd-ipc-protocol re-export：
```rust
pub use asd_ipc_protocol::{IpcError, HotkeyMerger};
```

- [ ] **Step 2: 更新 IpcManager 中的 import**

```rust
use asd_ipc_protocol::{IpcCommand, IpcMessage, IpcError};
```

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 24: 更新 infrastructure/watchdog.rs

**Files:**
- Modify: `asd-tauri/src-tauri/src/infrastructure/watchdog.rs`

- [ ] **Step 1: 更新 WatchdogStateEnum 引用**

将 `WatchdogStateEnum` 定义替换为从 asd-domain re-export：

```rust
pub use asd_domain::config::WatchdogStateEnum;
```

移除本地的 `WatchdogStateEnum` 定义。

- [ ] **Step 2: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 25: 更新测试文件

**Files:**
- Modify: `asd-tauri/src-tauri/src/tests/config_compat_tests.rs`
- Modify: `asd-tauri/src-tauri/src/tests/ipc_tests.rs`

- [ ] **Step 1: 更新 config_compat_tests.rs**

替换 import：
- `use crate::domain::config::*;` → `use asd_domain::config::*;`

- [ ] **Step 2: 更新 ipc_tests.rs**

替换 import：
- `use crate::domain::models::{IpcCommand, IpcMessage};` → `use asd_ipc_protocol::{IpcCommand, IpcMessage};`
- `use crate::infrastructure::ipc::*;` → `use crate::infrastructure::ipc::{IpcManager, IpcOutboundReceiver, create_listener}; use asd_ipc_protocol::{IpcError, HotkeyMerger};`

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 26: 更新 benchmarks.rs

**Files:**
- Modify: `asd-tauri/src-tauri/benches/benchmarks.rs`

- [ ] **Step 1: 更新 import 路径**

```rust
use asd_domain::config::{
    Config, ControlHotkeys, EnhancedHybridData, EnhancedPeriodicData, EnhancedSequenceData,
    GroupConfig, GroupItem, HoldData, HoldSettings, HybridData, ModeData, PeriodicData,
    SequenceData,
};
use asd_ipc_protocol::{IpcCommand, IpcMessage};
use asd_domain::validator::ConfigValidator;
use asd_domain::models::SkillGroup;
```

- [ ] **Step 2: 更新 benchmark 中的 `asd_tauri_lib::domain::models::SkillGroup::from` 引用**

改为 `asd_domain::models::SkillGroup::from`

- [ ] **Step 3: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 27: 更新 fuzz targets

**Files:**
- Modify: `asd-tauri/src-tauri/fuzz/fuzz_targets/fuzz_config_deserialize.rs`
- Modify: `asd-tauri/src-tauri/fuzz/fuzz_targets/fuzz_ipc_command.rs`
- Modify: `asd-tauri/src-tauri/fuzz/fuzz_targets/fuzz_ipc_json.rs`

- [ ] **Step 1: 更新 fuzz_config_deserialize.rs**

```rust
use asd_domain::config::Config;
```

- [ ] **Step 2: 更新 fuzz_ipc_command.rs**

```rust
use asd_ipc_protocol::IpcCommand;
```

- [ ] **Step 3: 更新 fuzz_ipc_json.rs**

```rust
use asd_ipc_protocol::IpcMessage;
```

- [ ] **Step 4: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 28: 移除已迁移的代码

**Files:**
- Modify: `asd-tauri/src-tauri/src/domain/mod.rs` → 清空或删除
- Modify: `asd-tauri/src-tauri/src/application/mod.rs` → 清空或删除

- [ ] **Step 1: 清空 domain/ 目录**

移除 `src-tauri/src/domain/config.rs`, `src-tauri/src/domain/models.rs`, `src-tauri/src/domain/validator.rs`, `src-tauri/src/domain/mod.rs`

- [ ] **Step 2: 清空 application/ 目录**

移除 `src-tauri/src/application/scheduler.rs`, `src-tauri/src/application/state.rs`, `src-tauri/src/application/mod.rs`

- [ ] **Step 3: 更新 lib.rs 移除旧模块声明**

从 `lib.rs` 中移除 `pub mod domain;` 和 `pub mod application;`

- [ ] **Step 4: 验证编译**

Run: `cd asd-tauri && cargo check -p asd-tauri 2>&1`
Expected: 编译成功

### Task 29: 运行全部测试

- [ ] **Step 1: 运行 workspace 全部测试**

Run: `cd asd-tauri && cargo test --workspace 2>&1`
Expected: 所有测试通过

- [ ] **Step 2: 运行 asd-domain 测试**

Run: `cd asd-tauri && cargo test -p asd-domain 2>&1`
Expected: 所有测试通过

- [ ] **Step 3: 运行 asd-ipc-protocol 测试**

Run: `cd asd-tauri && cargo test -p asd-ipc-protocol 2>&1`
Expected: 所有测试通过

- [ ] **Step 4: 运行 asd-application 测试**

Run: `cd asd-tauri && cargo test -p asd-application 2>&1`
Expected: 所有测试通过

- [ ] **Step 5: 运行 asd-tauri 测试**

Run: `cd asd-tauri && cargo test -p asd-tauri 2>&1`
Expected: 所有测试通过

- [ ] **Step 6: 运行 benchmarks 编译检查**

Run: `cd asd-tauri && cargo check -p asd-tauri --benches 2>&1`
Expected: 编译成功

- [ ] **Step 7: 提交**

```bash
cd asd-tauri
git add -A
git commit -m "refactor: complete crate extraction - migrate to 4-crate workspace"
```

---

## Phase 5: Miri 验证

### Task 30: 对纯逻辑 crate 运行 Miri

- [ ] **Step 1: 安装 nightly 工具链和 Miri**

Run: `rustup toolchain install nightly; rustup component add miri --toolchain nightly`

- [ ] **Step 2: 对 asd-domain 运行 Miri**

Run: `cd asd-tauri && cargo +nightly miri test -p asd-domain 2>&1`
Expected: 所有测试通过，无 UB 报告

- [ ] **Step 3: 对 asd-ipc-protocol 运行 Miri**

Run: `cd asd-tauri && cargo +nightly miri test -p asd-ipc-protocol 2>&1`
Expected: 所有测试通过，无 UB 报告

- [ ] **Step 4: 对 asd-application 运行 Miri**

Run: `cd asd-tauri && cargo +nightly miri test -p asd-application 2>&1`
Expected: 所有测试通过，无 UB 报告（注意：Miri 可能不支持 `std::fs` 操作，需要设置 `MIRIFLAGS="-Zmiri-disable-isolation"`）

- [ ] **Step 5: 提交最终状态**

```bash
cd asd-tauri
git add -A
git commit -m "chore: verify crate extraction with Miri"
```
