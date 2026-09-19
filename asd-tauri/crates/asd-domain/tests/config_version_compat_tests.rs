//! 配置版本兼容性契约（审查发现 #21）。
//!
//! # 先说清楚本文件的定位 —— 它不是「迁移用例」
//!
//! 2026-09-19 审查登记 #21「Rust 侧配置版本迁移零用例」，建议补「旧版本配置 → 新版本」的
//! 迁移用例。核实结论：**Rust 侧根本不存在配置版本迁移逻辑** ——
//!   · `crates/` 与 `src-tauri/src` 下 `grep -rni migrat --include=*.rs` **零命中**；
//!   · `Config.version` 是 `Option<String>`（`config.rs:42`），`Config::default()` 写死
//!     `Some("4.0")`（`config.rs:70`），而真实 `config.json` 是 `"3.0"`
//!     （`src-tauri/src/tests/config_compat_tests.rs:27` 已实测）—— 两者共存、无迁移；
//!   · 仓库里唯一的 `Migration*` 是 AHK 侧的 `infrastructure/migration_logger.ahk`，
//!     那是**迁移日志**组件，不是配置版本迁移器。
//! 所以「迁移用例」**无对象可测**，本文件改测它真正该测的东西：
//!
//! ⚠️ 复核结论存档（2026-09-19，审查发现 #21）：审查原判「Rust 侧配置版本迁移零用例」，
//! **该判定不成立** —— Rust 侧零迁移逻辑，无迁移可测。工程督导 2026-09-19 裁决：本文件
//! 4 条**不是为凑 #21 而补**，其保留价值是**契约冻结** —— 即使没人再写新测试，将来有人
//! 误给必填字段加 `#[serde(default)]`（残缺配置静默通过）或把可选字段改成必填（旧配置整体
//! 失效）时，这里会被挡住。下一个人看到审查报告 #21 时，请以本段为准，不要重复补测试。
//!
//! **旧版本配置（字段更少 / `version` 更低）必须还能被反序列化。**
//! 这是没有迁移器时唯一能防止「用户升级后配置整体失效」的契约，而且是可证伪的：
//! 一旦有人把某个 `Option` 字段改成必填、或给必填字段加上 `#[serde(default)]` 让残缺
//! 配置静默通过、或引入真的迁移器改写 `version`，下面这些用例会立刻变红。

use asd_domain::config::Config;
use serde_json::json;

/// 取一份「当前版本」的配置 JSON（由 `Config::default()` 序列化而来，必然合法）。
fn current_config_json() -> serde_json::Value {
    serde_json::to_value(Config::default()).expect("Config::default() 必须可序列化")
}

/// 旧版本配置缺 `Option` 字段时必须仍能加载。
///
/// 旧配置是「字段更少」的配置。被 `#[serde(default)]` 覆盖的 `Option` 字段
/// （`HoldSettings` / `lastModified` / `version`）逐个剥离后都必须反序列化成功，
/// 否则老用户的配置文件在升级后会被整体判为非法 → 静默回落出厂默认（用户配置丢失）。
#[test]
fn old_config_without_optional_fields_still_deserializes() {
    for key in ["HoldSettings", "lastModified", "version"] {
        let mut value = current_config_json();
        value
            .as_object_mut()
            .expect("配置顶层必须是 JSON 对象")
            .remove(key);

        let parsed: Result<Config, _> = serde_json::from_value(value);
        assert!(
            parsed.is_ok(),
            "剥离可选字段 `{key}` 后仍应能反序列化（模拟旧版本配置），实际失败：{parsed:?}"
        );
    }
}

/// 低版本 `version` 必须**原样保留**：既不改写，也不报错。
///
/// 钉住「Rust 侧当前无迁移」这一事实。真实 `config.json` 就是 `"3.0"` 而默认值是
/// `"4.0"`，两者共存且都不触发任何动作。将来若引入迁移器（把 `"3.0"` 改写成 `"4.0"`）
/// 或反过来给 `version` 加校验拒绝低版本，本条会红 —— 那时必须同步更新本文件与
/// `docs/test-map.md`，而不是把断言改成迁移后的值了事。
#[test]
fn old_version_string_is_preserved_not_migrated() {
    let mut value = current_config_json();
    value["version"] = json!("3.0");

    let parsed: Config = serde_json::from_value(value).expect("低版本配置必须能反序列化");
    assert_eq!(
        parsed.version.as_deref(),
        Some("3.0"),
        "`version` 应原样保留为 `\"3.0\"`：当前 Rust 侧无迁移逻辑，不得改写也不得拒绝"
    );
}

/// 必填字段**不能**被省略 —— 防止有人给它们加 `#[serde(default)]`。
///
/// 与上一条是同一枚硬币的两面：可选字段要能缺，必填字段必须不能缺。
/// 若给 `CONTROL_HOTKEYS` / `GroupSettings` 加默认值，残缺配置会静默通过反序列化，
/// 加载出一个没有分组、热键为空的配置，表现是「配置读出来了但全不对」。
#[test]
fn required_config_fields_cannot_be_omitted() {
    for key in ["CONTROL_HOTKEYS", "GroupSettings"] {
        let mut value = current_config_json();
        value
            .as_object_mut()
            .expect("配置顶层必须是 JSON 对象")
            .remove(key);

        let parsed: Result<Config, _> = serde_json::from_value(value);
        assert!(
            parsed.is_err(),
            "必填字段 `{key}` 被剥离后必须反序列化失败，实际却成功了：{parsed:?}"
        );
    }
}

/// 未来版本多出的未知字段不得破坏反序列化（前向兼容）。
///
/// AHK 侧先加字段、Rust 侧后跟是常态；若这里失败，表现是「AHK 存了、Rust 读不出来」。
#[test]
fn unknown_extra_fields_do_not_break_deserialization() {
    let mut value = current_config_json();
    value["someFutureField"] = json!({"nested": [1, 2, 3]});

    let parsed: Config =
        serde_json::from_value(value).expect("未知字段不得破坏反序列化（前向兼容）");
    assert_eq!(
        parsed.version.as_deref(),
        Some("4.0"),
        "未知字段应被忽略，不得影响既有字段"
    );
}
