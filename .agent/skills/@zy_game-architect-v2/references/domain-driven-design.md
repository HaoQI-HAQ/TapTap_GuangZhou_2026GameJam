# 领域驱动设计（DDD）

**适用**：核心玩法、场景系统、玩家数据系统、复杂逻辑模块。

## 核心构造块

### Entity（实体）
- **定义**：具有唯一标识的逻辑对象，高内聚
- **用途**：对应领域概念名词（Player、Enemy、Item）
- **设计**：包含属性（数据）和方法（操作）
- **ID**：唯一标识，用于弱引用和持久化索引
- **模式**：可使用继承（分类树）和组合（组件模式）

### Value Object（值对象）
- **定义**：无唯一性，描述领域概念的值（如Vector、Color、Damage）
- **特点**：通常不可变（修改时替换整体）
- **方法**：创建（静态工厂）、计算（返回新值）

### Service（服务）
- **定义**：封装不适合放入实体或值对象的领域逻辑
- **用途**：多实体协调逻辑（双向调度）、复杂流程逻辑（存档、寻路）
- **特点**：通常无状态

### Module（模块）
- **定义**：将相似逻辑归类（Namespace/Package/Directory）
- **原则**：高内聚、低耦合

## 生命周期管理

### Aggregate（聚合）
- **定义**：由实体组成的组合，其中「聚合根」包装部分实体
- **规则**：
  - 外部对象只能引用聚合根
  - 聚合根维护内部一致性
  - 内部实体引用其他聚合根时优先使用ID

### Factory（工厂）
- **定义**：提取创建实体或值对象的过程
- **形式**：构造函数、工厂方法、工厂类、Builder
- **用途**：封装复杂创建逻辑（尤其是聚合实体）

### Repository（仓库）
- **定义**：管理领域实体对象的生命周期（管理、访问、查询）
- **集合概念**：提供类似集合的接口（add/remove/get）
- **查询**：支持ID查询、属性查询、领域逻辑优化查询（如空间索引）
- **范围**：通常只为聚合根提供仓库

## 应用层
- **定义**：处理实际业务逻辑，由用例驱动
- **特点**：薄层，无业务规则，无业务状态，负责协调和委托
- **模式**：
  - **Application Service**：核心，用例驱动，组合相似用例实现
  - **Facade Pattern**：模块外部接口包装
  - **Command Pattern**：封装用户请求


---

## UrhoX 环境适配

### DDD 构造块 Lua 映射

| DDD 概念 | Lua 实现方式 | 说明 |
|---------|-------------|------|
| Entity（实体） | table + metatable | `__index` 实现方法继承，`id` 字段作唯一标识 |
| Value Object（值对象） | 引擎内置 / 纯 table | `Vector3`、`Color`、`Quaternion` 已是值对象；自定义用不可变 table |
| Service（服务） | 模块 table（无状态） | `local CombatService = {}` 导出纯函数 |
| Module（模块） | `require` + 目录结构 | `scripts/Combat/`、`scripts/Inventory/` 按领域组织 |
| Aggregate（聚合） | 嵌套 table + 根方法 | 聚合根 table 包含子实体 table，外部只访问根 |
| Factory（工厂） | 构造函数 / 工厂方法 | `Entity:new(config)` 或 `EntityFactory.create(type, ...)` |
| Repository（仓库） | table 容器 + 查询方法 | 内存中用 `{ [id] = entity }` 哈希表管理 |

### Entity 实现模式

```lua
-- 基于 metatable 的 Entity（带唯一 ID）
local Entity = {}
Entity.__index = Entity

local nextId = 0
function Entity:new(name, config)
    nextId = nextId + 1
    return setmetatable({
        id = nextId,           -- 唯一标识
        name = name,
        hp = config.hp or 100,
        maxHp = config.hp or 100,
        atk = config.atk or 10,
        -- 引擎节点引用（表现层）
        node = nil,
    }, self)
end

function Entity:takeDamage(amount)
    self.hp = math.max(0, self.hp - amount)
    -- 通知变化（通过引擎事件系统）
    local ed = VariantMap()
    ed["EntityId"] = Variant(self.id)
    ed["HP"] = Variant(self.hp)
    SendEvent("EntityHPChanged", ed)
    return self.hp <= 0  -- 是否死亡
end

function Entity:isAlive()
    return self.hp > 0
end
```

### Aggregate 实现模式

```lua
-- 聚合根：Squad（小队）包含多个 Unit（单位）
local Squad = {}
Squad.__index = Squad

function Squad:new(name)
    return setmetatable({
        id = generateId(),
        name = name,
        units = {},           -- 内部实体，外部不直接访问
        leader = nil,
    }, self)
end

-- 外部通过聚合根操作内部实体
function Squad:addUnit(unit)
    unit.squadId = self.id    -- 子实体引用聚合根 ID
    table.insert(self.units, unit)
    if not self.leader then self.leader = unit end
end

function Squad:removeUnit(unitId)
    for i, u in ipairs(self.units) do
        if u.id == unitId then
            table.remove(self.units, i)
            if self.leader and self.leader.id == unitId then
                self.leader = self.units[1]  -- 重选队长
            end
            return u
        end
    end
end

function Squad:getUnitCount()
    return #self.units
end
```

### Repository 实现模式

```lua
-- 仓库：管理 Entity 生命周期
local EntityRepository = {}
EntityRepository.__index = EntityRepository

function EntityRepository:new()
    return setmetatable({
        entities = {},       -- { [id] = entity }
    }, self)
end

function EntityRepository:add(entity)
    self.entities[entity.id] = entity
end

function EntityRepository:remove(id)
    local entity = self.entities[id]
    self.entities[id] = nil
    return entity
end

function EntityRepository:get(id)
    return self.entities[id]
end

-- 领域查询
function EntityRepository:findByName(name)
    for _, e in pairs(self.entities) do
        if e.name == name then return e end
    end
end

function EntityRepository:findAlive()
    local results = {}
    for _, e in pairs(self.entities) do
        if e:isAlive() then table.insert(results, e) end
    end
    return results
end

-- 持久化（通过 File API）
function EntityRepository:save(filename)
    local cjson = require("cjson")
    local data = {}
    for id, e in pairs(self.entities) do
        data[tostring(id)] = { name = e.name, hp = e.hp, atk = e.atk }
    end
    local file = File(filename, FILE_WRITE)
    file:WriteString(cjson.encode(data))
    file:Close()
end
```

### Application Service 模式

```lua
-- 应用服务：协调领域对象，薄层无业务逻辑
local CombatAppService = {}

function CombatAppService.attack(attackerId, defenderId, repo)
    local attacker = repo:get(attackerId)
    local defender = repo:get(defenderId)
    if not attacker or not defender then return false end
    if not attacker:isAlive() or not defender:isAlive() then return false end

    -- 委托给领域实体
    local killed = defender:takeDamage(attacker.atk)

    if killed then
        -- 协调后续流程（非业务逻辑）
        local ed = VariantMap()
        ed["KillerId"] = Variant(attackerId)
        ed["VictimId"] = Variant(defenderId)
        SendEvent("EntityKilled", ed)
    end

    return killed
end

return CombatAppService
```

### 关键提醒

1. **Lua 无类 (class) 关键字**：用 `table + metatable + __index` 模拟 OOP，这是 UrhoX Lua 项目的标准模式
2. **ID 弱引用**：实体之间应通过 `id` 引用（而非直接持有 table 引用），方便序列化和解耦
3. **领域事件用 SendEvent**：实体状态变化通过 `SendEvent("EntityHPChanged", ed)` 广播，UI 层订阅更新
4. **模块目录即 Module**：`scripts/Combat/`、`scripts/Inventory/` 等目录天然对应 DDD 的 Module 概念，用 `require("Combat.Entity")` 引用
5. **持久化用 File + cjson**：Repository 的 `save/load` 通过 `File` API 读写 JSON，遵循引擎沙箱规则

> **相关**: 数据驱动设计 → `data-driven-design.md` | 战斗/动作 → `system-action-combat.md`
