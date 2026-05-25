# 验证数据直观性全面重构设计

日期: 2026-05-21
状态: 已批准

## 1. 背景

当前验证面板存在以下直观性问题:
- Canvas时间线太简陋(120px高度, 8px字体, 无缩放/悬停提示)
- 验证报告只是文字表格, 偏差百分比无视觉层次
- 验证过程中缺少实时反馈(只显示事件计数和"验证中...")
- 预期vs实际没有并排对比, 长按超时只显示通过/失败
- 停止验证按钮点击无效果(Bug)

## 2. 改动范围

仅修改 `presentation/app_ui.html`, 不涉及后端AHK代码.

## 3. 核心变更

### 3.1 内嵌Chart.js

将Chart.js精简版(~60KB)以`<script>`标签内嵌到HTML文件中, 确保离线可用.

### 3.2 交互式时间轴(替代Canvas手绘)

使用Chart.js横向浮动条形图(horizontal floating bar):

- 每个按键一行, Y轴为按键名
- 每个事件用浮动条表示(down->up为实心条, click为点)
- 键盘事件绿色, 鼠标事件蓝色, 长按超时红色
- 支持悬停提示(按键名/事件类型/时间戳/持续时长)
- 高度自适应(根据按键数量动态调整)
- 预期序列叠加显示(半透明虚线框)

录制面板和验证面板共用同一时间轴组件.

### 3.3 验证报告4图表布局

停止验证后, 报告区域展示4个图表:

#### 3.3.1 雷达图总评
- 5维度: 顺序正确性/发送成功率/平均间隔偏差(反向)/最大间隔偏差(反向)/长按时序
- 每维度0-100分, 绿色>=80/黄色>=50/红色<50
- 中心显示综合评分

#### 3.3.2 间隔对比图
- 横向分组条形图
- 每个按键一组: 预期间隔(灰色) + 实际间隔(彩色)
- 偏差>20%的条形标红

#### 3.3.3 偏差柱状图
- 纵向柱状图, X轴为按键序号
- 颜色编码: 绿<=20%/橙<=50%/红>50%
- 平均线用虚线标注

#### 3.3.4 长按时序详情
- 横向浮动条形图
- 每个按键的down->up对用条形表示
- 条形长度=持续时长, 颜色编码: 绿(5-200ms)/红(超范围)
- 标注预期范围

### 3.4 实时统计面板

验证过程中顶部显示实时统计:
```
事件: 42 | 发送率: 95% | 平均偏差: 12.3% | 最差: 45.2% | 时长: 3.2s
```
每收到keySendEvent就更新.

### 3.5 验证事件列表

增加与录制面板类似的实时事件列表:
- 每行: 设备图标 + 事件方向 + 按键名 + 时间戳 + 偏差

### 3.6 Bug修复

#### 3.6.1 停止验证按钮改进
- 点击后显示"停止中..."状态
- stopValidation增加本地超时保护(3秒无响应则强制重置UI)
- disabled按钮增加opacity:0.6样式

#### 3.6.2 已修复: init()中renderSettingsPanel未定义
- 移除了对不存在的renderSettingsPanel()的调用

#### 3.6.3 已修复: onAhkReady未调用refreshGroupList
- 在onAhkReady中添加了refreshGroupList()调用

## 4. 数据流

不变:
```
AHK KeyValidator.OnSend -> WebView2Manager._PushSendEvent -> JS onBridgeEvent -> 更新图表
```

新增前端计算:
- 实时统计面板: 从_valEvents数组计算发送率/平均偏差/最差偏差
- 雷达图评分: 从报告数据计算各维度分数

## 5. Chart.js配置

- 版本: 4.x (最新稳定版)
- 需要的模块: core, bar, radar, tooltip, legend
- 不需要zoom plugin(用自定义范围滑块替代)
- 主题: 深色背景, 与现有UI一致

## 6. HTML结构变更

验证面板(panel-validate)新结构:
```html
<div class="keytest-panel" id="panel-validate" style="display:none;">
  <!-- 分组选择 -->
  <div>...</div>
  <!-- 实时统计面板 -->
  <div id="valLiveStats">...</div>
  <!-- 控制按钮 -->
  <div>...</div>
  <!-- 交互式时间轴 -->
  <div><canvas id="valTimeline"></canvas></div>
  <!-- 验证事件列表 -->
  <div id="valEventList">...</div>
  <!-- 验证报告(4图表) -->
  <div id="valReport" style="display:none;">
    <div id="valRadarChart"><canvas id="radarCanvas"></canvas></div>
    <div id="valIntervalChart"><canvas id="intervalCanvas"></canvas></div>
    <div id="valDeviationChart"><canvas id="deviationCanvas"></canvas></div>
    <div id="valHoldChart"><canvas id="holdCanvas"></canvas></div>
  </div>
</div>
```

录制面板(panel-record)同步更新:
- Canvas替换为Chart.js交互式时间轴
- 保留现有统计面板和事件列表

## 7. 实施约束

- Chart.js内嵌到HTML, 不依赖网络
- 保持与现有深色主题一致
- 所有图表支持悬停提示
- 图表容器响应式布局
