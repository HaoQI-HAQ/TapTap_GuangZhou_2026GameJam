---
name: game-architect-v2
description: 游戏系统架构设计技能。设计战斗、技能、AI、UI、联机、叙事等子系统时触发。提供范式选型指南（DDD/Data-Driven/原型），系统设计参考文件索引。
---

> **⚠️ UrhoX 环境适配须知**
>
> 本技能的架构理论和设计模式**通用适用**，但实现层面需注意以下环境约束：
>
> | 维度 | 通用描述 | UrhoX 实际环境 |
> |------|---------|---------------|
> | 语言 | C#/JavaScript 伪代码 | **Lua 5.4**（table+metatable 模拟 OOP） |
> | 架构模型 | ECS / 继承树 | **Node + Component**（类 Unity EC） |
> | 异步 | async/await、Promise | **coroutine**（协程） |
> | 事件系统 | C# Delegate/Rx | **SubscribeToEvent(name, handler)** |
> | UI 框架 | Unity UGUI/NGUI | **Yoga Flexbox + NanoVG**（urhox-libs/UI） |
> | 配置格式 | Excel/CSV/ScriptableObject | **JSON（cjson）或 Lua table** |
> | 多人架构 | 分布式服务器集群 | **内置 Client/Server Lua 分离**（配置驱动） |
> | 多线程 | Job System / Worker Thread | **❌ 不可用**（单线程 Lua VM） |
>
> 各参考文件末尾均附有 **「UrhoX 环境适配」** 章节，提供具体的 Lua 代码范式。



# 游戏系统架构师

## 范式选型

设计任何游戏子系统时，先选范式：

| 范式 | 核心 | 适用场景 | 不适用场景 |
|------|------|----------|------------|
| **DDD** | OOP优先，实体+行为合一 | 战斗逻辑、伤害公式、Buff、AI决策（规则复杂、多实体交互） | 内容多、性能敏感、网络同步 |
| **Data-Driven** | 数据优先，行为分离 | 任务/关卡设计、技能执行流程、UI管理、物品系统（内容多、策划迭代） | 规则复杂、实时决策 |
| **原型驱动** | 用例优先，快速验证 | Game Jam、核心玩法测试（快速验证） | 正式项目、长期维护 |

### 范式混用策略

大多数项目混合三种范式，核心原则：

1. **宏观一致**：所有模块遵循同一模块管理框架
2. **核心用DDD**：高规则复杂度、丰富领域概念的系统（战斗角色、伤害公式）
3. **内容用Data-Driven**：可扩展内容（任务/关卡）、流程编排（教程/技能执行）、数据管理（物品/商店）
4. **混合模式**：
   - 实体即数据：领域实体序列化为纯字段，同时服务数据和行为
   - 流程+领域：数据驱动编排序列，领域逻辑处理各步骤规则（如技能：释放→引导→生效，流程驱动，伤害计算领域处理）
   - 分离数据/领域层：仅在编辑时和运行时表示真正分离时使用，用Bake步骤桥接

### 选型信号表

| 信号 | 倾向DDD | 倾向Data-Driven |
|------|---------|----------------|
| 实体交互 | 复杂多实体规则 | 主要是CRUD+展示 |
| 行为来源 | 随实体类型变化，难表达为纯数据 | 配置表/策划内容驱动 |
| 变化频率 | 规则随平衡迭代变化 | 内容远多于逻辑变化 |
| 性能 | 对象图开销可接受 | 需要批处理、缓存友好布局 |
| 网络 | 有状态对象可接受 | 偏好扁平状态快照 |
| 团队 | 程序员负责逻辑 | 策划需要不写代码就能迭代 |

## 系统设计参考

根据要设计的子系统，读对应参考文件。

**使用流程**：
1. 先确定范式（上方选型表）
2. 根据范式读对应方法论文件：**DDD** → `references/domain-driven-design.md`、**Data-Driven** → `references/data-driven-design.md`、**原型** → `references/prototype-design.md`
3. 读对应子系统参考文件（下方表格）
4. 重点阅读参考文件末尾的 **「UrhoX 环境适配」** 章节获取 Lua 实现范式

### 子系统设计

| 子系统 | 参考文件 |
|--------|---------|
| 战斗/动作系统 | `references/system-action-combat.md` |
| 技能/Buff系统 | `references/system-skill.md` |
| AI行为/决策 | `references/system-game-ai.md` |
| 联机/同步 | `references/system-multiplayer.md` |
| UI/模块管理 | `references/system-ui.md` |
| 叙事/对话/过场 | `references/system-narrative.md` |
| 场景/对象/空间 | `references/system-scene.md` |
| 基础框架 | `references/system-foundation.md` |
| 时间/逻辑流 | `references/system-time.md` |

### 架构方法论

| 方法论 | 参考文件 | 对应范式 |
|--------|---------|---------|
| 架构原理/流程 | `references/principles.md` | 通用 |
| 领域驱动设计 | `references/domain-driven-design.md` | DDD |
| 数据驱动设计 | `references/data-driven-design.md` | Data-Driven |
| 原型驱动开发 | `references/prototype-design.md` | 原型驱动 |

### 工程支撑

| 主题 | 参考文件 |
|------|---------|
| 需求分析 | `references/requirements.md` |
| 算法/数据结构 | `references/algorithm.md` |
| 性能优化 | `references/performance-optimization.md` |

## 架构设计核心原则

1. **需求为本**：架构服务于具体需求，不盲目追求「高级」
2. **迭代演进**：首次设计奠定基础，后续迭代演进架构
3. **逻辑隔离**：横向分层，纵向分模块，类设计清晰独立
4. **合理混用**：不同范式优势结合，形式统一
5. **预留变化空间**：识别变化点，用抽象隔离
6. **测试友好**：留日志、调试、监控、作弊台等辅助接口

## 常见陷阱

- 先搭菜单/背包/外观系统，核心循环还没验证 → 大量无效工作
- 物理/玩法直接绑定帧率 → 设备间行为不一致
- 过早引入重型3D资产 → 移动端完全不可用
- 跳过输入延迟和相机可读性检查 → FPS稳定但玩家还是流失
- 单人循环还没做好就加联机 → 高成本无留存收益
- 忽略存档和状态恢复策略 → 体验断裂

## 扩展性设计策略

| 策略 | 做法 |
|------|------|
| 隔离 | 模块通过事件或受限接口交互，禁止直接深链；用ID代替对象引用 |
| 抽象 | 变量提取为配置（JSON/Excel）、逻辑提取为回调/接口、数据类型抽象 |
| 组合 | 组件模式拆分实体（Position/Render/Collider正交）、策略组合替代条件分支 |
| 重构 | 零容忍无用代码、不留注释掉的旧代码、抽象层用完即删 |

---

## UrhoX 环境适配

### Lua OOP 模式（替代 class/interface）

```lua
-- 基类
local BaseSystem = {}
BaseSystem.__index = BaseSystem

function BaseSystem:new(name)
    local o = setmetatable({}, self)
    o.name = name or "unnamed"
    return o
end

function BaseSystem:Init() end
function BaseSystem:Update(dt) end
function BaseSystem:Destroy() end

-- 子类继承
local CombatSystem = setmetatable({}, { __index = BaseSystem })
CombatSystem.__index = CombatSystem

function CombatSystem:new()
    local o = BaseSystem.new(self, "Combat")
    o.entities = {}
    return o
end

function CombatSystem:Update(dt)
    for _, e in ipairs(self.entities) do
        -- 战斗逻辑
    end
end
```

### 事件系统映射

```lua
-- C# Delegate/Event → UrhoX SubscribeToEvent
SubscribeToEvent("Update", "HandleUpdate")
SubscribeToEvent("PhysicsBeginContact2D", "HandleCollision")

-- 自定义事件（全局事件总线）
local eventData = VariantMap()
eventData["Damage"] = Variant(50)
eventData["TargetID"] = Variant(entityId)
SendEvent("DamageDealt", eventData)

-- 监听自定义事件
SubscribeToEvent("DamageDealt", function(eventType, eventData)
    local dmg = eventData["Damage"]:GetInt()
    local targetId = eventData["TargetID"]:GetInt()
end)
```

### 异步序列（coroutine 替代 async/await）

```lua
-- async/await 风格 → coroutine 实现
local co = coroutine.create(function()
    -- 阶段1：加载资源
    LoadResources()
    coroutine.yield()  -- 等待下一帧

    -- 阶段2：初始化模块
    InitModules()
    coroutine.yield()

    -- 阶段3：进入游戏
    EnterGame()
end)

-- 在 Update 中驱动
function HandleUpdate(eventType, eventData)
    if coroutine.status(co) ~= "dead" then
        coroutine.resume(co)
    end
end
```

### 配置数据格式

```lua
-- Excel/CSV/ScriptableObject → JSON 或 Lua table
-- 方式1：JSON 配置（推荐，策划友好）
local cjson = require("cjson")
local file = cache:GetFile("Config/skills.json")
local jsonStr = file:ReadString()
local skillConfigs = cjson.decode(jsonStr)

-- 方式2：Lua table 配置（程序友好）
local SkillConfig = {
    [1001] = { name = "火球术", damage = 50, cd = 3.0, range = 10 },
    [1002] = { name = "冰冻", damage = 30, cd = 5.0, range = 8, duration = 2.0 },
}
```
