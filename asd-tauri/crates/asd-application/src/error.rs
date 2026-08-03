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
    #[error("内部错误: {0}")]
    Internal(String),
}

impl AppError {
    /// 返回错误变体名，用于序列化时保留类型信息。
    pub fn kind_str(&self) -> &'static str {
        match self {
            AppError::Config(_) => "Config",
            AppError::Ipc(_) => "Ipc",
            AppError::GroupNotFound(_) => "GroupNotFound",
            AppError::Validation(_) => "Validation",
            AppError::Internal(_) => "Internal",
        }
    }

    /// 返回错误的内部消息（不含变体前缀），用于序列化时提供具体错误详情。
    pub fn message(&self) -> &str {
        match self {
            AppError::Config(m) => m,
            AppError::Ipc(m) => m,
            AppError::GroupNotFound(m) => m,
            AppError::Validation(m) => m,
            AppError::Internal(m) => m,
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
        state.serialize_field("message", self.message())?;
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
        ];
        for (err, expected_kind) in &cases {
            let json = serde_json::to_string(&err).unwrap();
            let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
            assert_eq!(
                parsed["kind"], *expected_kind,
                "变体 {:?} 的 kind 字段应为 {}", err, expected_kind
            );
            assert!(
                parsed["message"].is_string(),
                "变体 {:?} 的 message 字段应为字符串", err
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
    fn test_app_error_variants() {
        let variants = vec![
            AppError::Config("c".to_string()),
            AppError::Ipc("i".to_string()),
            AppError::GroupNotFound("g".to_string()),
            AppError::Validation("v".to_string()),
            AppError::Internal("x".to_string()),
        ];
        for v in &variants {
            let json = serde_json::to_string(v).unwrap();
            assert!(!json.is_empty());
        }
    }
}
