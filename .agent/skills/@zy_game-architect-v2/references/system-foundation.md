# 基础框架组件

## 核心组件

### Log System
- 封装日志API，级别：Debug/Info/Warning/Error
- 输出重定向：控制台/文件/网络
- Channels/Tags：按模块过滤

### Timer & Scheduler
| 实现 | 说明 |
|------|------|
| **列表遍历** | 每帧遍历所有Timer，精确但O(N) |
| **Timing Wheel** | 分桶到时间槽，高性能常O(1)，精度固定 |

### Module Management
- 统一生命周期：Init→Active→Deactive→Destroy
- 中心访问点：ModuleCenter
- 按名称/类型获取模块

### Event System（全局事件总线）
- Key类型：Enum/String/Object/Type
- 特性：事件队列（延迟处理）、过滤、调试日志

### Resource Management
- **缓存层次**：Bundle Cache→Asset Cache→Object Pool
- **卸载策略**：引用计数（精确）/ 组卸载 / GC扫描（干净但昂贵）

### Audio System
- 分离BGM（淡入淡出/循环）和SFX（并发限制/优先级）控制
- 对象池复用音频源

### Input System
- 状态记录：当前帧+上一帧状态（Down/Up检测）
- 按键映射重配置
- 全局事件分发

### Utils
- Path操作、Math扩展、String工具
- I18n语言表加载
- Profiler层次性能计时


---

## UrhoX 环境适配

### 组件可用性

| 基础组件 | UrhoX 可用性 | 说明 |
|---------|-------------|------|
| Log System | ⚙️ **引擎内置** | `log:Write(LOG_INFO, "msg")` 或直接 `print()` |
| Timer & Scheduler | ⚠️ 需自行实现 | 见 `system-time.md` 适配节 |
| Module Management | ⚠️ 需自行实现 | Lua `require` + 模块 table |
| Event System | ⚙️ **引擎内置** | `SubscribeToEvent` / `SendEvent` |
| Resource Management | ⚙️ **引擎内置** | `cache:GetResource()` 自动缓存 |
| Audio System | ⚙️ **引擎内置** | `SoundSource` / `SoundSource3D` 组件 |
| Input System | ⚙️ **引擎内置** | `input:GetKeyDown()` / `input:GetMouseButtonPress()` |

### UrhoX 事件系统详解

```lua
-- 1. 订阅引擎内置事件
SubscribeToEvent("Update", "HandleUpdate")
SubscribeToEvent("KeyDown", "HandleKeyDown")
SubscribeToEvent("PhysicsBeginContact2D", "HandleContact")

-- 2. 订阅节点事件（限定发送者）
SubscribeToEvent(specificNode, "NodeCollision", "HandleNodeCollision")

-- 3. 发送自定义事件（全局事件总线）
local eventData = VariantMap()
eventData["Score"] = Variant(100)
eventData["PlayerName"] = Variant("Player1")
SendEvent("ScoreChanged", eventData)

-- 4. 监听自定义事件
SubscribeToEvent("ScoreChanged", function(eventType, eventData)
    local score = eventData["Score"]:GetInt()
    local name = eventData["PlayerName"]:GetString()
    updateScoreUI(name, score)
end)
```

### 模块管理模式

```lua
-- 用 require + table 实现模块管理
-- modules/CombatModule.lua
local CombatModule = {}
CombatModule.__index = CombatModule

function CombatModule:Init()
    self.entities = {}
    SubscribeToEvent("Update", function(_, ed)
        self:Update(ed["TimeStep"]:GetFloat())
    end)
end

function CombatModule:Update(dt)
    -- 战斗逻辑
end

function CombatModule:Destroy()
    self.entities = nil
end

return CombatModule

-- main.lua 中使用
local CombatModule = require("modules.CombatModule")
local combat = setmetatable({}, CombatModule)
combat:Init()
```

### 资源管理

```lua
-- 引擎内置资源缓存，无需手动管理
local model = cache:GetResource("Model", "Models/Box.mdl")        -- 自动缓存
local texture = cache:GetResource("Texture2D", "Textures/bg.png") -- 重复调用不重新加载
local sound = cache:GetResource("Sound", "Sounds/jump.ogg")       -- 音效资源

-- 背景加载（大资源）
cache:BackgroundLoadResource("Model", "Models/LargeScene.mdl")
```

### 关键提醒

1. **OOP 用 `setmetatable + __index`**：不要尝试使用 `class` 关键字
2. **模块导出用 `local M = {} return M`**：不要用全局 table
3. **资源通过 `cache:GetResource()` 获取**：引擎自动缓存，重复调用不重复加载
4. **生命周期管理**：Init → Update → Destroy，在 Destroy 中清理引用避免内存泄漏
5. **事件绑定在 Init 中做**：`SubscribeToEvent` 放在模块初始化时，不要在 Update 中重复绑定

> **相关**: 架构原理 → `principles.md` | 场景/对象 → `system-scene.md`
