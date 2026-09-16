// —— TD-021 分阶段：本 crate 的 `# Errors` 按**文件**推进 ——
// 这些服务函数基本都返回 `Result<_, AppError>`，但「在什么条件下失败、会返回哪个变体」
// 必须逐个读函数体才能写准；**快速编一排空话会变成误导性文档**，比缺文档更糟。
// 所以不放 crate 级豁免，而是**在尚未补齐的每个文件顶部单独 allow**：
// 补完一个文件就删掉那一行的 allow，该文件立刻受 lint 保护，不会整体回退。
// 已补齐：`backup_service.rs`、`group_service.rs`、`recording_service.rs`、
// `config_repository.rs`。
// 进度与理由见 `docs/tech-debt-register.md` 的 TD-021。
// 测试代码豁免几条「可读性」lint（TD-012）—— 它们在生产代码里是信号，在测试里是噪声：
//   · similar_names：对照组命名（cfg1/cfg2、g1/g2）本身就是测试要表达的对照关系
//   · match_wildcard_for_single_variants：`_ => panic!("Expected X")` 就是断言的意图
//   · match_same_arms：验证不同变体落到同一结果时，两个分支体天然相同
//   · case_sensitive_file_extension_comparisons：测试数据扩展名固定小写
#![cfg_attr(
    test,
    allow(
        clippy::similar_names,
        clippy::match_wildcard_for_single_variants,
        clippy::match_same_arms,
        clippy::case_sensitive_file_extension_comparisons
    )
)]
pub mod backup_service;
pub mod config_repository;
pub mod error;
pub mod group_service;
pub mod recording_service;
pub mod state;
pub mod time_format;
