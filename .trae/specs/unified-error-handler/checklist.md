# Checklist

- [x] 统一错误处理模块 `unified_error_handler.ahk` 已创建
- [x] UnifiedErrorHandler 类实现完整
- [x] HandleError() 方法返回 1 抑制弹窗
- [x] PowerShell 启动器 `run_silent.ps1` 已创建
- [x] 启动器能正确捕获加载时错误
- [x] `main.ahk` 已添加 #ErrorStdOut 指令
- [x] `main.ahk` 已注册 OnError 回调
- [x] 旧的错误处理模块已删除
- [x] 加载时错误测试通过，无弹窗
- [x] 运行时错误测试通过，无弹窗
- [x] 错误日志正确生成到 `logs/errors.log`
