# 修复：混合模式下子组类型下拉框点击即消失

## 问题描述
在分组编辑器中，选择混合模式（hybrid/enhanced_hybrid）后，子组中的"周期性/序列"类型下拉框点击一下就消失，无法选择。

## 根因分析

### 问题定位
文件：[app_ui.html](file:///d:/1demo/AutoHotkeydemo/presentation/app_ui.html)

### 根因
`<select>` 下拉框的 `data-action="changeSubGroupType"` 被错误地绑定在 **click 事件**处理器中（第 1581 行），而不是 **change 事件**处理器中。

**事件触发流程（当前错误行为）：**
1. 用户点击 `<select>` 下拉框 → 触发 `click` 事件
2. `configSection.onclick` 处理器捕获到 `changeSubGroupType` action
3. 调用 `changeSubGroupType(i, el.value)` — 此时 `el.value` 是当前已选中的值
4. `changeSubGroupType()` 调用 `renderConfigSection()` → 替换整个 `configSection.innerHTML`
5. 下拉框被销毁并重建 → **下拉框消失**

**正确行为应该是：**
- `<select>` 元素的值变更应该由 `change` 事件触发（用户实际选择了不同选项时）
- `click` 事件在用户点击打开下拉框时就触发，此时用户还没选择任何选项

### 代码证据

**第 1572-1586 行（onclick 处理器）— 错误位置：**
```javascript
document.getElementById('configSection').onclick = function(e) {
    var el = e.target.closest('[data-action]');
    if (!el) return;
    var action = el.getAttribute('data-action');
    // ... 其他 action ...
    else if (action === 'changeSubGroupType') changeSubGroupType(parseInt(el.getAttribute('data-group')), el.value);  // ← 问题所在！
    // ...
};
```

**第 1588-1599 行（change 处理器）— 应该在这里处理：**
```javascript
document.getElementById('configSection').addEventListener('change', function(e) {
    var el = e.target.closest('[data-action]');
    if (!el) return;
    var action = el.getAttribute('data-action');
    // ... 其他 action ...
    // changeSubGroupType 不在这里！
});
```

### HTML 模板（第 2242 行）
```html
<select class="input" style="width:90px;padding:3px 6px;font-size:10px;" data-action="changeSubGroupType" data-group="'+i+'">
  <option value="periodic">🔄 周期性</option>
  <option value="sequence">📋 序列</option>
</select>
```

## 修复方案

### 步骤 1：从 onclick 处理器中移除 changeSubGroupType
在 `app_ui.html` 第 1581 行，删除：
```javascript
else if (action === 'changeSubGroupType') changeSubGroupType(parseInt(el.getAttribute('data-group')), el.value);
```

### 步骤 2：将 changeSubGroupType 添加到 change 事件处理器
在 `app_ui.html` 第 1588-1599 行的 change 处理器中，添加：
```javascript
else if (action === 'changeSubGroupType') changeSubGroupType(parseInt(el.getAttribute('data-group')), el.value);
```

### 验证步骤
1. 启动脚本，打开 WebView2 界面
2. 选择混合模式或增强混合模式
3. 点击子组的"周期性/序列"下拉框 → 下拉框应正常展开
4. 选择不同选项 → 类型应正确切换，界面正常重渲染
5. 选择相同选项 → 不应触发重渲染
