//! C8 配置一致性测试 - 验证 test-manifest feature 已从 Cargo.toml 中移除
//!
//! 背景：test-manifest feature 曾用于主 crate 测试，但全代码库中
//! 无任何 `#[cfg(feature = "test-manifest")]` 使用，属于废弃 feature。
//! 此测试确保该 feature 不再存在于 Cargo.toml 中。

use std::path::Path;

/// 验证 Cargo.toml 中不再包含 test-manifest feature 定义
///
/// 如果此测试失败，说明 Cargo.toml 仍包含 `test-manifest = []`，
/// 应删除 [features] 节中的该 feature。
#[test]
fn test_manifest_feature_removed() {
    // 使用 CARGO_MANIFEST_DIR 获取 crate 根目录（编译时确定）
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let cargo_toml_path = Path::new(manifest_dir).join("Cargo.toml");

    // 读取 Cargo.toml 内容
    let content = std::fs::read_to_string(&cargo_toml_path)
        .unwrap_or_else(|e| panic!("无法读取 Cargo.toml ({cargo_toml_path:?}): {e}"));

    // 验证不含 test-manifest feature 定义
    assert!(
        !content.contains("test-manifest"),
        "Cargo.toml 仍包含 test-manifest feature 定义，应删除 [features] 中的 test-manifest = []"
    );
}
