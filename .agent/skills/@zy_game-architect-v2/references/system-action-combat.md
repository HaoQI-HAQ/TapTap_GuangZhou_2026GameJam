# 动作战斗系统架构

## 核心层次

- **状态管理**：控制角色逻辑能力和动画状态
- **交互层**：碰撞检测、空间查询
- **执行流程**：从攻击发起→命中→反馈的完整编排
- **伤害处理管线**：Hook式伤害计算，支持每步修改

## 角色状态机

### 状态结构
- **单状态机**：Idle/Run/Attack/Hit 全在一个机
- **双状态机**：分离 Locomotion（下身/移动）和 Combat（上身/动作），实现「边跑边射」

### 引用计数锁
用引用计数代替布尔值管理动作限制：
```javascript
MoveLockRef++   // 动画或技能增加移动锁
MoveLockRef--   // 完成后解锁，归零才可移动
AtkLockRef++    // 防止攻击中再次发起攻击
```
多个重叠系统可独立锁（如：眩晕+重攻击硬直），全部归零才解锁。

## 碰撞与交互

### Box体系
| 类型 | 用途 | 说明 |
|------|------|------|
| **Hitbox** | 攻击方产生 | 定义伤害生效区域 |
| **Hurtbox** | 防守方附着 | 定义可受击部位 |
| **Query Box** | 非战斗交互 | 拾取、对话、触发器 |

### 实现模式
1. **实例模式**：角色/武器模型挂载持久Box组件，通过动画Notify或技能事件切换Active/Deactive
2. **即时查询（Data-Driven）**：在指定帧执行物理查询（BoxOverlap/SphereSweep），参数在数据资产中定义

### 过滤优化
先按阵营（友军误伤）、Z轴高度、状态标签（无敌）预过滤，再执行昂贵物理重叠检测。

## 战斗流程

### 近战
```
动画触发Active帧 → Hitbox激活/查询执行 → 碰撞命中 → 触发伤害管线 → 播放命中反馈
```

### 远程
```
Fire事件 → 生成投射物/触发体 → 投射物自主移动+碰撞检测 → 命中→伤害管线→销毁
```

## 伤害管线（Hook式）

```javascript
// 伤害数据
DamageData = {
  BaseValue, DamageFactor, CritInfo: {IsCritical, CritMultiplier},
  MitigationInfo: {IsDodge, IsParry, ArmorPenetration}
}

// A打B的完整流程
1. 计算初始结构 → 填入BaseValue
2. 前置Hook：
   - Attacker.onDamagingBefore(Victim, Data)  // 吸血等
   - Victim.onDamageBefore(Attacker, Data)   // 护盾/减伤
3. 应用伤害 → 修改HP
4. 后置Hook：
   - Attacker.onDamaging(Victim, Data)       // 击杀触发
   - Victim.onDamage(Attacker, Data)         // 受伤反应/反伤
```

### 特殊流

| 类型 | 说明 |
|------|------|
| **直接治疗** | 只触发Receiver.onHealingBefore（加成/减疗），直接加HP |
| **环境/DOT** | 无攻击方（环保），跳过Attacker Hook，触发Victim.onDamageBefore |
| **真直接应用** | 升级属性/GM作弊，不触发任何Hook，防止无限循环 |

## 投射物

- **向量式**：Position+Velocity+Acceleration（线性）
- **角度式**：Angle+Speed+AngularVelocity（弧线）

控制器：Homing、Gravity、Drag、变速曲线。

## 命中反馈

根据攻击方Hitbox参数驱动：
- **方向受击动画**：HitFront/HitLeft/HitRight
- **物理力整合**：Force参数驱动击退
- **特效触发**：按AttackForm和双方材质类型匹配VFX/SFX


---

## UrhoX 环境适配

### 引用计数锁（Lua 实现）

```lua
-- JavaScript → Lua
local ActionLock = {}
ActionLock.__index = ActionLock

function ActionLock:new()
    return setmetatable({ moveLockRef = 0, atkLockRef = 0 }, self)
end

function ActionLock:lockMove()   self.moveLockRef = self.moveLockRef + 1 end
function ActionLock:unlockMove() self.moveLockRef = math.max(0, self.moveLockRef - 1) end
function ActionLock:canMove()    return self.moveLockRef == 0 end

function ActionLock:lockAttack()   self.atkLockRef = self.atkLockRef + 1 end
function ActionLock:unlockAttack() self.atkLockRef = math.max(0, self.atkLockRef - 1) end
function ActionLock:canAttack()    return self.atkLockRef == 0 end
```

### 伤害管线（Lua 实现）

```lua
-- DamageData 结构
local function createDamageData(attacker, victim, baseValue)
    return {
        attacker = attacker,
        victim = victim,
        baseValue = baseValue,
        damageFactor = 1.0,
        isCritical = false,
        critMultiplier = 1.5,
        isDodge = false,
        isParry = false,
        finalValue = 0,
    }
end

-- Hook 式伤害管线
local function processDamage(attacker, victim, baseValue)
    local data = createDamageData(attacker, victim, baseValue)

    -- 前置 Hook：攻击方
    for _, hook in ipairs(attacker.onDamagingBefore or {}) do
        hook(data)
    end
    -- 前置 Hook：防守方
    for _, hook in ipairs(victim.onDamageBefore or {}) do
        hook(data)
    end

    -- 计算最终伤害
    if data.isDodge then
        data.finalValue = 0
    else
        data.finalValue = data.baseValue * data.damageFactor
        if data.isCritical then
            data.finalValue = data.finalValue * data.critMultiplier
        end
    end

    -- 应用伤害
    victim.hp = victim.hp - data.finalValue

    -- 后置 Hook
    for _, hook in ipairs(attacker.onDamaging or {}) do hook(data) end
    for _, hook in ipairs(victim.onDamage or {}) do hook(data) end

    return data
end
```

### 碰撞检测映射

| 通用概念 | UrhoX 3D | UrhoX 2D |
|---------|----------|----------|
| Hitbox/Hurtbox | `CollisionShape` + `RigidBody` | `CollisionBox2D` + `RigidBody2D` |
| 碰撞事件 | `SubscribeToEvent("NodeCollision", ...)` | `SubscribeToEvent("PhysicsBeginContact2D", ...)` |
| 即时查询 | `physicsWorld:SphereCast(...)` | `physicsWorld2D:RayCast(...)` |
| 触发器 | `body.trigger = true` | `shape.trigger = true` |
| 碰撞层过滤 | `shape.collisionLayer` / `collisionMask` | 同左 |

### 投射物实现

```lua
-- 简单投射物
local function createProjectile(pos, dir, speed, damage)
    local node = scene_:CreateChild("Projectile")
    node.position = pos

    local body = node:CreateComponent("RigidBody")
    body.mass = 0.1
    body.trigger = true
    body.linearVelocity = dir * speed

    local shape = node:CreateComponent("CollisionShape")
    shape:SetSphere(0.2)

    -- 存储伤害数据
    node.damage = damage
    node.lifetime = 5.0

    return node
end
```

### 关键提醒

1. **碰撞体必须与 RigidBody 在同一节点**：不要将 CollisionShape 放到子节点
2. **伤害公式用纯 Lua 函数**：不依赖引擎组件，便于测试和调试
3. **Hook 管线用 table 数组**：`for _, hook in ipairs(hooks) do hook(data) end`
4. **投射物记得设 lifetime**：避免泄漏，在 Update 中检查并移除超时投射物
5. **枚举值不要用数字**：鼠标按钮用 `MOUSEB_LEFT`，按键用 `KEY_*`

> **相关**: 技能/Buff → `system-skill.md` | 时间/逻辑流 → `system-time.md`
