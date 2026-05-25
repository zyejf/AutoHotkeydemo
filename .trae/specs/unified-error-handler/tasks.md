# Tasks

- [x] Task 1: 创建统一错误处理模块 `infrastructure/unified_error_handler.ahk`
  - [x] SubTask 1.1: 定义 UnifiedErrorHandler 类
  - [x] SubTask 1.2: 实现 Init() 方法，初始化日志系统
  - [x] SubTask 1.3: 实现 HandleError() 方法，处理运行时错误
  - [x] SubTask 1.4: 实现日志格式化和写入功能
  - [x] SubTask 1.5: 确保返回 1 抑制所有错误弹窗

- [x] Task 2: 创建 PowerShell 启动器 `run_silent.ps1`
  - [x] SubTask 2.1: 实现脚本路径参数
  - [x] SubTask 2.2: 使用 /ErrorStdOut 参数启动 AutoHotkey
  - [x] SubTask 2.3: 捕获 stderr 输出并写入日志文件
  - [x] SubTask 2.4: 提供友好的错误信息显示

- [x] Task 3: 修改 `main.ahk` 添加错误处理初始化
  - [x] SubTask 3.1: 添加 #ErrorStdOut 指令
  - [x] SubTask 3.2: 注册 OnError 回调
  - [x] SubTask 3.3: 初始化 UnifiedErrorHandler
  - [x] SubTask 3.4: 更新 #Include 引用

- [x] Task 4: 删除旧的错误处理模块
  - [x] SubTask 4.1: 删除 `infrastructure/error_captor.ahk`
  - [x] SubTask 4.2: 删除 `infrastructure/error_watchdog.ahk`
  - [x] SubTask 4.3: 更新相关引用

- [x] Task 5: 测试验证
  - [x] SubTask 5.1: 测试加载时错误捕获（语法错误）
  - [x] SubTask 5.2: 测试运行时错误捕获（除零错误等）
  - [x] SubTask 5.3: 验证无弹窗
  - [x] SubTask 5.4: 验证日志文件正确生成

# Task Dependencies

- [Task 3] depends on [Task 1]
- [Task 4] depends on [Task 3]
- [Task 5] depends on [Task 1, Task 2, Task 3, Task 4]
