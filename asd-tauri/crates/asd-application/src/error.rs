use asd_ipc_protocol::IpcError;
use serde::Serialize;
use std::borrow::Cow;
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
    #[error("内部错误: {0}")]
    Internal(String),
    #[error("IO 错误: {0}")]
    Io(#[from] std::io::Error),
}

impl AppError {
    /// 返回错误变体名，用于序列化时保留类型信息。
    #[must_use]
    pub fn kind_str(&self) -> &'static str {
        match self {
            AppError::Config(_) => "Config",
            AppError::Ipc(_) => "Ipc",
            AppError::GroupNotFound(_) => "GroupNotFound",
            AppError::Validation(_) => "Validation",
            AppError::Internal(_) => "Internal",
            AppError::Io(_) => "Io",
        }
    }

    /// 返回错误的内部消息（不含变体前缀），用于序列化时提供具体错误详情。
    ///
    /// 返回 `Cow<'_, str>`：字符串类变体借用内部字段，`Io` 变体因
    /// `std::io::Error` 无法直接借用 `&str`，通过 `to_string()` 构造自有字符串。
    /// 这样 `Io` 错误也能返回非空消息，避免调用方拿到空串。
    #[must_use]
    pub fn message(&self) -> Cow<'_, str> {
        match self {
            AppError::Config(m)
            | AppError::Ipc(m)
            | AppError::GroupNotFound(m)
            | AppError::Validation(m)
            | AppError::Internal(m) => Cow::Borrowed(m),
            AppError::Io(e) => Cow::Owned(e.to_string()),
        }
    }
}

impl Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut state = serializer.serialize_struct("AppError", 2)?;
        state.serialize_field("kind", self.kind_str())?;
        state.serialize_field("message", &self.message())?;
        state.end()
    }
}

impl From<IpcError> for AppError {
    fn from(e: IpcError) -> Self {
        AppError::Ipc(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_error_serialization_contains_kind() {
        let err = AppError::Config("测试错误".to_string());
        let json = serde_json::to_string(&err).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["kind"], "Config");
        assert_eq!(parsed["message"], "测试错误");
    }

    /// 验证所有变体的 kind 字段正确映射到变体名。
    #[test]
    fn test_app_error_serialization_all_variants_have_kind() {
        let cases = vec![
            (AppError::Config("c".to_string()), "Config"),
            (AppError::Ipc("i".to_string()), "Ipc"),
            (AppError::GroupNotFound("g".to_string()), "GroupNotFound"),
            (AppError::Validation("v".to_string()), "Validation"),
            (AppError::Internal("x".to_string()), "Internal"),
            (
                AppError::Io(std::io::Error::new(std::io::ErrorKind::NotFound, "io")),
                "Io",
            ),
        ];
        for (err, expected_kind) in &cases {
            let json = serde_json::to_string(&err).unwrap();
            let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
            assert_eq!(
                parsed["kind"], *expected_kind,
                "变体 {err:?} 的 kind 字段应为 {expected_kind}"
            );
            assert!(
                parsed["message"].is_string(),
                "变体 {err:?} 的 message 字段应为字符串"
            );
        }
    }

    /// 验证序列化结果不再是纯字符串（旧格式），而是包含 kind 字段的对象。
    #[test]
    fn test_app_error_serialization_not_plain_string() {
        let err = AppError::Validation("参数无效".to_string());
        let json = serde_json::to_string(&err).unwrap();
        // 旧格式是纯字符串如 "\"验证失败: 参数无效\""，以引号开头
        // 新格式是对象，以 { 开头
        assert!(
            json.starts_with('{'),
            "序列化结果应为 JSON 对象，实际: {json}"
        );
    }

    #[test]
    fn test_app_error_from_ipc_error() {
        let ipc_err = IpcError::ConnectionClosed;
        let app_err: AppError = ipc_err.into();
        assert!(matches!(app_err, AppError::Ipc(_)));
    }

    #[test]
    fn test_app_error_from_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::PermissionDenied, "拒绝访问");
        let app_err: AppError = io_err.into();
        assert!(matches!(app_err, AppError::Io(_)));
        // 验证序列化保留 ErrorKind 信息（通过 kind 字段）
        let json = serde_json::to_string(&app_err).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["kind"], "Io");
        assert!(parsed["message"].as_str().unwrap().contains("拒绝访问"));
    }

    #[test]
    fn test_app_error_variants() {
        let variants = vec![
            AppError::Config("c".to_string()),
            AppError::Ipc("i".to_string()),
            AppError::GroupNotFound("g".to_string()),
            AppError::Validation("v".to_string()),
            AppError::Internal("x".to_string()),
            AppError::Io(std::io::Error::other("io")),
        ];
        for v in &variants {
            let json = serde_json::to_string(v).unwrap();
            assert!(!json.is_empty());
        }
    }
}
