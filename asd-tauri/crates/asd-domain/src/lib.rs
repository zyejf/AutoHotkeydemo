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
pub mod config;
pub mod models;
pub mod traits;
pub mod validator;
