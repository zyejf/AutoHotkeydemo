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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_error_serialization() {
        let err = AppError::Config("测试错误".to_string());
        let json = serde_json::to_string(&err).unwrap();
        assert!(json.contains("配置错误"));
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
            AppError::Executor("e".to_string()),
            AppError::Internal("x".to_string()),
        ];
        for v in &variants {
            let json = serde_json::to_string(v).unwrap();
            assert!(!json.is_empty());
        }
    }
}
