# Tasks

- [x] Task 1: 删除现有错误处理模块
  - [x] SubTask 1.1: 删除 `infrastructure/unified_error_handler.ahk`
  - [x] SubTask 1.2: 更新 `main.ahk` 移除相关引用

- [x] Task 2: 创建新的错误处理模块 `infrastructure/error_system.ahk`
  - [x] SubTask 2.1: 定义 ErrorSystem 类
  - [x] SubTask 2.2: 实现 Init() 方法
  - [x] SubTask 2.3: 实现 HandleError() 方法
  - [x] SubTask 2.4: 实现错误级别识别功能
  - [x] SubTask 2.5: 实现 JSON Lines 日志格式
  - [x] SubTask 2.6: 创建全局回调函数 ErrorSystem_HandleError

- [x] Task 3: 重写 PowerShell 启动器 `run_silent.ps1`
  - [x] SubTask 3.1: 实现脚本路径参数
  - [x] SubTask 3.2: 使用 /ErrorStdOut 参数启动 AutoHotkey
  - [x] SubTask 3.3: 捕获 stderr 输出并写入日志文件
  - [x] SubTask 3.4: 提供友好的错误信息显示

- [x] Task 4: 修改 `main.ahk` 使用新的错误处理系统
  - [x] SubTask 4.1: 添加 #ErrorStdOut 指令
  - [x] SubTask 4.2: 注册 OnError 回调
  - [x] SubTask 4.3: 初始化 ErrorSystem

- [x] Task 5: 创建全面测试脚本 `tests/test_error_system.ahk`
  - [x] SubTask 5.1: 测试加载时错误捕获
  - [x] SubTask 5.2: 测试运行时错误捕获（多种错误类型）
  - [x] SubTask 5.3: 测试未捕获错误处理
  - [x] SubTask 5.4: 测试错误级别识别
  - [x] SubTask 5.5: 测试日志格式验证
  - [x] SubTask 5.6: 测试无弹窗验证

# Task Dependencies

- [Task 2] depends on [Task 1]
- [Task 4] depends on [Task 2]
- [Task 5] depends on [Task 2, Task 3, Task 4]
