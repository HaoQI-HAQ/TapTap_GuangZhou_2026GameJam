# UI与业务模块架构

## 模块框架

### 模块生命周期
Init → Activate → Deactivate → Destroy
由Singleton ModuleManager或DI Container管理。

### 依赖注入（DI）
控制反转，依赖注入到对象而非主动获取。好处：解耦、易测试。

## 交互与事件

| 模式 | 说明 |
|------|------|
| **Observer（观察者）** | 直接C# Action/Delegate，紧耦合 |
| **Event Bus** | 事件Key（Enum/String）解耦发送方和接收方 |
| **Reactive（Rx）** | 事件流+Linq变换，适合UI数据绑定 |

## MV*框架选型

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **MV** | View观察Model，View含逻辑 | 简单 |
| **MVC** | Controller处理输入，View观察Model | 分离输入逻辑 |
| **MVP** | Presenter完全解耦Model和View，易测试 | 复杂UI |
| **MVVM** | ViewModel抽象View状态，数据绑定自动化同步 | 数据驱动UI |

## UI管理

### UI面板基类（BaseView）
- **生命周期**：Open/Close
- **控件绑定**：自动映射变量到按钮/文本
- **事件注册**

### UI管理器
- **工厂**：创建/加载UI
- **层级**：HUD/Popup/Alert排序
- **栈/队列**：管理返回键和弹窗序列
- **缓存**：关闭的UI放池复用

## 布局
- **Anchors**：相对父级边缘定位
- **Dynamic Layout**：Vertical/Horizontal/Grid Layout Groups
- **Safe Area**：处理刘海屏和曲面屏


---

## UrhoX 环境适配

### UI 系统差异

| 通用概念 | UrhoX 实现 | 说明 |
|---------|-----------|------|
| Unity UGUI / NGUI | **urhox-libs/UI**（Yoga Flexbox + NanoVG） | 40+ 内置控件，原生 UI 已废弃 |
| Anchors 锚点定位 | Yoga Flexbox 布局 | `justifyContent`, `alignItems`, `flexDirection` |
| C# Delegate/Action | `SubscribeToEvent` 或回调函数 | `onClick = function(self) end` |
| Rx / UniRx | **❌ 不可用** | 用事件回调替代 |
| DI Container | **❌ 不可用** | 用全局 require 模块替代 |
| Canvas Scaler | `UI.Scale.DEFAULT` | 见 `engine-docs/recipes/ui.md` §10 |

### UrhoX UI 推荐模式

```lua
local UI = require("urhox-libs/UI")

UI.Init({
    fonts = {
        { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
    },
    scale = UI.Scale.DEFAULT,
})

-- MV 模式：View 直接观察数据变化
local scoreLabel = UI.Label { text = "Score: 0", fontSize = 20 }

-- 更新 UI（在事件回调中）
function updateScore(newScore)
    scoreLabel:set("text", "Score: " .. newScore)
end

-- 面板管理（栈式）
local panels = {}
function pushPanel(panel)
    table.insert(panels, panel)
    UI.SetRoot(panel)
end
function popPanel()
    table.remove(panels)
    if #panels > 0 then
        UI.SetRoot(panels[#panels])
    end
end
```

### MV* 实践建议

在 UrhoX Lua 中，推荐 **MV（Model-View）** 或简化的 **MVP** 模式：
- **Model**：纯 Lua table，存储游戏状态
- **View**：`urhox-libs/UI` 组件树，通过回调更新
- **Presenter/Controller**：普通 Lua 函数，连接 Model 和 View

MVVM 的自动数据绑定在 Lua 中实现成本较高，不推荐。

### 关键提醒

1. **原生 UI 已废弃**：必须使用 `urhox-libs/UI`（Yoga Flexbox + NanoVG）
2. **UI.Init 只调用一次**：在 Start 中初始化，设置字体和缩放
3. **推荐 MV 模式**：Model 为纯 Lua table，View 通过回调更新
4. **面板管理用栈式**：`pushPanel` / `popPanel` 管理多层面板
5. **MVVM 不推荐**：Lua 中自动数据绑定实现成本高，用手动回调更简单

> **相关**: 基础框架 → `system-foundation.md` | 数据驱动设计 → `data-driven-design.md`
