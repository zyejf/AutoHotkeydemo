//! 共享测试工具模块 — 现已迁移至 `asd-test-harness` crate。
//!
//! 此文件保留为薄 re-export 层，以兼容现有通过 `mod common; use common::*;`
//! 引入测试工具的测试文件（backup_service_tests / group_service_tests /
//! recording_service_tests）。新增测试应直接使用 `use asd_test_harness::*;`。

pub use asd_test_harness::*;
