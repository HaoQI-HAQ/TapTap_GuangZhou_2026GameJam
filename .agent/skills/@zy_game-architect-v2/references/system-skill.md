# 技能系统架构

## 核心层次

- **数据层**：属性集、Tags、Effects（修改记录）
- **逻辑层**：技能框架（高层结构）+ Atomic Actions（原子行为）
- **事件层**：数据变化事件、Timing Hooks、Logic触发（Cue/Notify）
- **支持模块**：目标算法、Actor接口、辅助实体

## 数据层

### 属性集
- **Attribute Field**：基础值 + 修改列表 → 动态重算缓存
- **公式**：`final = (base + additive_sum) * multiplicative_factor`

### Tags
语义标签（Stunned、Invulnerable、Burning），用于状态检查和逻辑分支。

### Effects
数据驱动的修改记录，是改变属性和Tags的主要机制。

### 技能参数存储策略
| 策略 | 说明 |
|------|------|
| **Static Config** | 数据表/资产定义，所有实例共享 |
| **Skill Spec** | 技能实例持有，支持道具授予等个体差异 |
| **Skill Blackboard** | 附着于实体的临时参数表，跨技能共享 |
| **Attribute Set** | 直接存角色属性，全局可访问 |

## 逻辑层（两层结构）

### Tier1：技能框架
| 模式 | 说明 |
|------|------|
| **Code-Driven** | 专用类封装技能逻辑（最常用） |
| **Behavior Tree** | 节点树定义AI-like序列和决策 |
| **Timeline** | 时间轴序列，适合固定时机效果 |
| **Node Graph** | 可视化图，灵活+策划友好 |
| **Skill Script/DSL** | 领域特定脚本（如Lua） |

### Tier2：原子Actions
可复用操作（PlayAnimation、ApplyDamage、SpawnProjectile），由框架序列编排。

### 并行状态（Buff/Debuff）
- **Buff对象**：完整技能结构，管理自身生命周期
- **Tag+Effects**：轻量方案，Tag触发逻辑

## 事件层

| 类型 | 说明 |
|------|------|
| **数据修改事件** | OnAttributeChange、OnTagAdded/Removed |
| **Timing Hooks** | OnDamageDealt、OnTargetKilled、OnSpellCast |
| **Logic Cue** | 非关键，VFX/SFX触发 |
| **Logic Notify** | 关键，游戏逻辑触发（如动画Notify触发伤害计算） |

## 技能生命周期阶段

Wind-up（起手）→ Execution（执行）→ Recovery（收招）
阶段明确才能实现：中断、取消、连招链。

## 模板/实例化

**模板**（策划配置）→ **实例**（运行时生成）

| 模板类型 | 内容 |
|----------|------|
| **Actor Template** | Static Data：初始Attribute Set + Tags |
| **Skill Template** | Code-Driven：Skill Type + 参数；其他框架：逻辑资产本身 |
| **Action Template** | Action Type + 参数 |
| **Buff Template** | Tag+Effects：Static Data；Buff对象：同Skill Template |

## 目标选择

```javascript
// TargetSelector
selectTargets(source, params) {
  candidates = filterByRange(params.range)
  candidates = filterByAlignment(params.friendly)
  candidates = filterByTags(params.requireTags)
  return sortByPriority(candidates, params.priority)
}
```

## 伤害计算

```javascript
// DamageCalculator
calculate(input) {
  data = new DamageData(input)
  for (hook in attacker.onDamagingBefore) hook.modify(data)
  for (hook in defender.onDamageBefore) hook.modify(data)
  finalValue = applyFormulas(data)
  defender.HP -= finalValue
  attacker.onDamaging(defender, data)
  defender.onDamage(attacker, data)
  return finalValue
}
```


---

## UrhoX 环境适配

### 属性集（Lua 实现）

```lua
-- AttributeSet：基础值 + 修改列表 → 动态重算
local AttributeSet = {}
AttributeSet.__index = AttributeSet

function AttributeSet:new(base)
    return setmetatable({
        base = base or {},       -- { hp = 100, atk = 20, def = 10 }
        modifiers = {},          -- { {attr="atk", type="add", value=5, source="buff_01"}, ... }
        cache = {},              -- 缓存计算结果
        dirty = true,
    }, self)
end

function AttributeSet:addModifier(attr, modType, value, source)
    table.insert(self.modifiers, {
        attr = attr, type = modType, value = value, source = source
    })
    self.dirty = true
end

function AttributeSet:removeBySource(source)
    for i = #self.modifiers, 1, -1 do
        if self.modifiers[i].source == source then
            table.remove(self.modifiers, i)
        end
    end
    self.dirty = true
end

function AttributeSet:get(attr)
    if self.dirty then self:recalc() end
    return self.cache[attr] or self.base[attr] or 0
end

function AttributeSet:recalc()
    self.cache = {}
    for attr, baseVal in pairs(self.base) do
        local addSum = 0
        local mulFactor = 1.0
        for _, m in ipairs(self.modifiers) do
            if m.attr == attr then
                if m.type == "add" then addSum = addSum + m.value
                elseif m.type == "mul" then mulFactor = mulFactor * m.value
                end
            end
        end
        self.cache[attr] = (baseVal + addSum) * mulFactor
    end
    self.dirty = false
end
```

### 目标选择（Lua 实现）

```lua
function selectTargets(source, params)
    local candidates = {}
    -- 1. 范围过滤
    for _, entity in ipairs(allEntities) do
        local dist = (entity.position - source.position):Length()
        if dist <= (params.range or math.huge) then
            table.insert(candidates, entity)
        end
    end
    -- 2. 阵营过滤
    if params.friendly ~= nil then
        local filtered = {}
        for _, e in ipairs(candidates) do
            if (e.team == source.team) == params.friendly then
                table.insert(filtered, e)
            end
        end
        candidates = filtered
    end
    -- 3. 标签过滤
    if params.requireTags then
        local filtered = {}
        for _, e in ipairs(candidates) do
            local hasAll = true
            for _, tag in ipairs(params.requireTags) do
                if not e.tags[tag] then hasAll = false; break end
            end
            if hasAll then table.insert(filtered, e) end
        end
        candidates = filtered
    end
    -- 4. 排序
    if params.priority == "nearest" then
        table.sort(candidates, function(a, b)
            return (a.position - source.position):Length()
                 < (b.position - source.position):Length()
        end)
    end
    return candidates
end
```

### 技能框架推荐

| 框架模式 | UrhoX 可用性 | 说明 |
|---------|-------------|------|
| Code-Driven | ✅ **推荐** | Lua 函数/table 定义技能逻辑 |
| Behavior Tree | ⚠️ 需自行实现 | 用 Lua table 模拟节点树 |
| Timeline | ⚠️ 用 coroutine | 协程序列模拟时间轴 |
| Node Graph | **❌ 不可用** | 无可视化编辑器 |
| Skill DSL | ✅ 天然适配 | Lua 本身就是脚本语言 |

### Buff 系统简化实现

```lua
-- Buff 管理器
local BuffManager = {}
BuffManager.__index = BuffManager

function BuffManager:new(owner)
    return setmetatable({ owner = owner, buffs = {} }, self)
end

function BuffManager:addBuff(buffDef, source)
    local buff = {
        id = buffDef.id,
        remaining = buffDef.duration,
        source = source,
    }
    -- 应用属性修改
    if buffDef.modifiers then
        for _, m in ipairs(buffDef.modifiers) do
            self.owner.attributes:addModifier(m.attr, m.type, m.value, buffDef.id)
        end
    end
    -- 添加标签
    if buffDef.tags then
        for _, tag in ipairs(buffDef.tags) do
            self.owner.tags[tag] = (self.owner.tags[tag] or 0) + 1
        end
    end
    table.insert(self.buffs, buff)
end

function BuffManager:update(dt)
    for i = #self.buffs, 1, -1 do
        local b = self.buffs[i]
        b.remaining = b.remaining - dt
        if b.remaining <= 0 then
            self:removeBuff(i)
        end
    end
end

function BuffManager:removeBuff(index)
    local b = self.buffs[index]
    self.owner.attributes:removeBySource(b.id)
    table.remove(self.buffs, index)
end
```

### 关键提醒

1. **技能配置与逻辑分离**：配置用 JSON/Lua table，逻辑用函数管线
2. **Buff 用反向遍历移除**：`for i = #buffs, 1, -1 do` 避免跳过元素
3. **属性修改器用 source 标识**：移除 Buff 时按 source 清理修改器
4. **冷却用简单计时器**：`remaining = remaining - dt`，不要过度设计
5. **标签系统用引用计数**：`tags[tag] = (tags[tag] or 0) + 1`，移除时减 1

> **相关**: 战斗/动作 → `system-action-combat.md` | 时间/逻辑流 → `system-time.md`
