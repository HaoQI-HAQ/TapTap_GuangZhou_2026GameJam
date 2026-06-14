# 游戏AI系统架构

## 设计原则

### AI三层模型
- **Movement（移动层）**：物理运动控制
- **Decision Making（决策层）**：行为选择
- **Strategy（战略层）**：群体协调、高层规划

### 复杂度谬误
- 简单行为往往优于复杂算法
- **感知窗口**：玩家注意*行为变化*而非算法复杂度
- 路径：Hack → Heuristic → Algorithm，用最简单的能工作的方案

### 性能约束
| 策略 | 做法 |
|------|------|
| 时间切片 | 计算分摊到多帧 |
| AI LOD | 远处/屏外简化逻辑 |
| Anytime算法 | 超时返回「目前最优」 |
| 缓存一致性 | SoA布局减少缓存未命中 |

## 移动技术选型

| 技术 | 适用场景 |
|------|----------|
| **Kinematic** | 简单游戏、俯视角，直接速度无加速 |
| **Steering** | 大多数动作游戏，Seek/Flee/Arrive/Pursue/Wander/PathFollowing |
| **Group Steering** | 集群、鸟群，Separation/Cohesion/Alignment |
| **Avoidance** | 多智能体导航，RVO/ORCA |
| **Formations** | RTS、小队，固定/可缩放/涌现 |

## 寻路（架构层面）

| 表示 | 最佳场景 | 权衡 |
|------|----------|------|
| **Tile/Grid** | 2D游戏、简单关卡 | 简单但大世界内存重 |
| **Waypoint Graph** | 线性关卡、简单3D | 手动放置、稀疏覆盖 |
| **NavMesh** | 现代3D游戏（标准） | 处理地形和智能体尺寸，需生成工具 |
| **Flow Fields** | 大量单位向同目标移动（RTS） | 百量级单位效率高，单场内存高 |

### 架构关注点
- **分层寻路**：先抽象层（房间到房间）再到细节层，大世界必备
- **动态重规划**：D* Lite/LPA* 适应变化环境
- **可中断/时间切片**：大搜索分帧计算
- **路径平滑**：后处理去除锯齿
- **代价函数**：地形代价、战术代价叠加

## 决策技术选型

| 技术 | 复杂度 | 适用场景 | 数据驱动 |
|------|--------|----------|----------|
| **Decision Tree** | 低 | 简单分支逻辑 | 中 |
| **FSM** | 低-中 | 清晰不同状态、可预测转换 | 低 |
| **HFSM** | 中 | 复杂状态含子行为 | 低 |
| **Behavior Tree** | 中-高 | 复杂模块化可复用（行业标准） | 高 |
| **GOAP** | 高 | 动态规划、涌现行为 | 高 |
| **Utility AI** | 中-高 | 计分选择、平滑行为混合 | 高 |
| **Rule-Based** | 中 | 规则集、推理（Rete算法） | 高 |

## 战术与战略AI

- **Influence Maps**：网格表示领土控制/危险/资源
- **Tactical Locations**：标注掩护点/狙击点/伏击点
- **多层架构**：Strategic（指挥官）→ Operational（班组）→ Tactical（个体）
- **涌现协作**：局部规则产生协调行为（鸟群、狼群）

## 感知与接口

- **Sense**：Visual（视线/锥形）、Auditory、Memory
- **优化**：基于区域的感觉管理器，用空间分区
- **通信**：轮询（低频查询）或事件（解耦，优先）

## 板棋游戏/对抗搜索

| 技术 | 适用场景 |
|------|----------|
| **Minimax** | 完全信息回合制（Chess） |
| **Alpha-Beta** | Minimize优化，剪枝 |
| **MCTS** | 高分支因子（Go、复杂策略） |
| **Iterative Deepening** | 时间约束搜索 |

优化：转置表（Zobrist哈希）、开局库/残局库、评估函数。


---

## UrhoX 环境适配

### AI 技术可用性

| AI 技术 | UrhoX 可用性 | 说明 |
|---------|-------------|------|
| FSM / HFSM | ⚠️ 需自行实现 | Lua table + metatable 实现状态机，见下方示例 |
| Behavior Tree | ⚠️ 需自行实现 | 纯 Lua 实现节点树，闭包天然适合叶节点 |
| A* 寻路 | ⚠️ 需自行实现 | 2D 网格寻路用纯 Lua；3D 无内置 NavMesh 生成 |
| Steering Behaviors | ⚠️ 需自行实现 | 基于 `Vector3` 运算，引擎向量 API 完备 |
| 感知系统 | ⚙️ 部分引擎支持 | 射线检测用 `PhysicsRaycastResult` + `RaycastSingle` |
| 空间分区 | ⚙️ 引擎内置 Octree | `octree:GetDrawables()` 可做粗筛；精细分区需自行实现 |
| 事件通信 | ⚙️ **引擎内置** | `SubscribeToEvent` / `SendEvent` 天然适合 AI 事件 |

### FSM Lua 实现模式

```lua
-- 基于 table 的轻量 FSM
local EnemyAI = {}
EnemyAI.__index = EnemyAI

function EnemyAI:new(node)
    return setmetatable({
        node = node,
        state = "idle",
        stateTime = 0,
        target = nil,
    }, self)
end

function EnemyAI:changeState(newState)
    if self.state == newState then return end
    self.state = newState
    self.stateTime = 0
end

function EnemyAI:update(dt)
    self.stateTime = self.stateTime + dt
    local handler = self["update_" .. self.state]
    if handler then handler(self, dt) end
end

function EnemyAI:update_idle(dt)
    -- 检测玩家（用引擎节点查找）
    local player = scene_:GetChild("Player", true)
    if player then
        local dist = (player.position - self.node.position):Length()
        if dist < 10.0 then
            self.target = player
            self:changeState("chase")
        end
    end
end

function EnemyAI:update_chase(dt)
    if not self.target then self:changeState("idle") return end
    local dir = (self.target.position - self.node.position):Normalized()
    self.node.position = self.node.position + dir * 3.0 * dt
    self.node:LookAt(self.target.position)
end
```

### 感知系统与引擎物理射线

```lua
-- 视线检测：利用引擎 RaycastSingle
local function canSeeTarget(entity, target, physicsWorld)
    local origin = entity.position + Vector3.UP  -- 眼睛高度
    local toTarget = target.position - origin
    local dist = toTarget:Length()
    local dir = toTarget:Normalized()

    local result = PhysicsRaycastResult()
    physicsWorld:RaycastSingle(result, Ray(origin, dir), dist)

    if result.body then
        return result.body:GetNode() == target  -- 击中的是目标本身
    end
    return true  -- 无遮挡
end
```

### AI 更新与性能优化

```lua
-- 分帧更新（时间切片）：在 Update 事件中交替更新不同批次
local aiFrame = 0
SubscribeToEvent("Update", function(_, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    aiFrame = (aiFrame + 1) % 3

    for i, ai in ipairs(allAIs) do
        if (i % 3) == aiFrame then
            ai:update(dt * 3)  -- 补偿间隔
        end
    end
end)

-- AI LOD：远处降频
local function updateWithLOD(ai, playerPos, dt)
    local dist = (ai.node.position - playerPos):Length()
    if dist < 20 then
        ai:update(dt)
    else
        ai.lodTimer = (ai.lodTimer or 0) + dt
        if ai.lodTimer > 0.5 then
            ai:update(ai.lodTimer)
            ai.lodTimer = 0
        end
    end
end
```

### 关键提醒

1. **向量运算**：UrhoX 的 `Vector3` 支持 `Normalized()`、`Length()`、`DotProduct()`、`CrossProduct()` 等，可直接用于 Steering 算法
2. **节点查找**：`scene_:GetChild("Name", true)` 递归查找子节点，适合简单目标定位；大量查询应自行维护实体列表
3. **碰撞查询**：3D 用 `PhysicsRaycastResult` + `RaycastSingle`；2D 用 `PhysicsRaycastResult2D` + `physicsWorld2D:RayCast()`
4. **自定义事件通信**：AI 之间可通过 `SendEvent("AIAlert", eventData)` 广播警报，比轮询更高效

> **相关**: 时间/状态机 → `system-time.md` | 战斗/动作 → `system-action-combat.md`
