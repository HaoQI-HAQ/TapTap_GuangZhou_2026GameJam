# 算法与数据结构

## 寻路

| 算法 | 说明 |
|------|------|
| **BFS** | 邻居优先，保证无权图最短路径，适合flood-fill |
| **Dijkstra** | 加权图最短路径 |
| **A*** | 游戏标准，用启发式引导搜索，减少访问节点 |
| **JPS** | 均匀代价Grid优化，跳过中间节点加速 |
| **Flow Fields** | 大量单位向同目标，RTS适用 |
| **NavMesh** | 现代3D标准，处理地形和智能体尺寸 |
| **RRT** | 高维空间或机械臂IK |
| **D*/D* Lite** | 动态环境（障碍变化），无需全量重算 |

## 碰撞检测

**Broad Phase（粗筛）**：
- Sweep and Prune：沿轴排序找重叠
- Grid/Spatial Hash：分格检查同格物体
- BVH：动态包围盒树

**Narrow Phase（精检）**：
- AABB/Sphere/Capsule：先检简单形状
- GJK：凸形状
- SAT：分离轴定理

## 避障

| 算法 | 适用 |
|------|------|
| **Steering** | 单智能体，Seek/Flee/Arrival/Wander |
| **VO/RVO/ORCA** | 多智能体互避，ORCA适合RTS/大规模人群 |

## AI对抗搜索

| 算法 | 适用 |
|------|------|
| **Minimax** | 完全信息回合制 |
| **Alpha-Beta** | Minmax剪枝优化 |
| **MCTS** | 高分支因子（Go、复杂策略） |

优化：转置表（Zobrist哈希）、开局库/残局库。

## 数据结构

| 结构 | 游戏应用 |
|------|----------|
| **Trie（前缀树）** | 自动完成、连招匹配 |
| **Graph Adjacency List** | 寻路图、对话树、科技树 |
| **Graph Adjacency Matrix** | 稠密图，O(1)边检查 |
| **Spatial Hash** | 快速局部查询 |
| **QuadTree/Octree** | 空间分区 |
| **Kd-Tree** | 静态点云最近邻（光子映射） |


---

## UrhoX 环境适配

### 算法可用性映射

| 算法/数据结构 | UrhoX 可用性 | 说明 |
|-------------|-------------|------|
| A* / BFS / Dijkstra | ⚠️ 需自行实现 | 纯 Lua 实现，适合 2D 网格寻路 |
| NavMesh | ⚠️ 需自行实现 | 引擎无内置 NavMesh 生成工具 |
| 碰撞检测（Broad Phase） | ⚙️ **引擎内置** | `Octree`（3D）自动管理；2D 用 Box2D 内置 |
| 碰撞检测（Narrow Phase） | ⚙️ **引擎内置** | `RigidBody` + `CollisionShape` 自动处理 |
| 射线检测 | ⚙️ **引擎内置** | `RaycastSingle` / `Raycast`（3D）、`RayCast`（2D） |
| 空间查询 | ⚙️ **引擎内置** | `SphereCast`（3D）、`GetRigidBodies`（区域查询） |
| Spatial Hash / QuadTree | ⚠️ 需自行实现 | 游戏逻辑层若需自定义分区 |
| Trie / Graph | ⚠️ 需自行实现 | 纯 Lua table 实现 |

### A* 寻路 Lua 实现要点

```lua
-- UrhoX 中 A* 网格寻路的关键适配
-- 1. 用 Lua table 作为 open/closed list
-- 2. Lua 数组索引从 1 开始（网格坐标也建议从 1 开始）
-- 3. 用字符串 key 做 hash（"x,y" 格式）

local function astarKey(x, y)
    return x .. "," .. y
end

local function heuristic(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)  -- 曼哈顿距离
end

-- 方向表（4向/8向）
local DIRS_4 = { {0,-1}, {0,1}, {-1,0}, {1,0} }
local DIRS_8 = { {0,-1}, {0,1}, {-1,0}, {1,0}, {-1,-1}, {1,-1}, {-1,1}, {1,1} }

-- 注意：大地图寻路（>100x100）建议分帧计算
-- 每帧处理固定步数，用 coroutine 暂停
local function astarCoroutine(grid, sx, sy, ex, ey, stepsPerFrame)
    local steps = 0
    -- ... A* 主循环中 ...
    steps = steps + 1
    if steps >= stepsPerFrame then
        steps = 0
        coroutine.yield()  -- 下一帧继续
    end
end
```

### 引擎碰撞检测接口

```lua
-- 3D 射线检测
local result = PhysicsRaycastResult()
local physicsWorld = scene_:GetComponent("PhysicsWorld")
physicsWorld:RaycastSingle(result, Ray(origin, direction), maxDist)
if result.body then
    local hitNode = result.body:GetNode()
    local hitPos = result.position
end

-- 3D 球形查询
local results = {}  -- PhysicsRaycastResult 数组
physicsWorld:SphereCast(results, Ray(origin, direction), radius, maxDist)

-- 2D 射线检测
local physicsWorld2D = scene_:GetComponent("PhysicsWorld2D")
local result2D = PhysicsRaycastResult2D()
physicsWorld2D:RayCastSingle(result2D, startPos, endPos)
```

### 自定义空间分区（Spatial Hash）

```lua
-- 游戏逻辑层轻量空间哈希
local SpatialHash = {}
SpatialHash.__index = SpatialHash

function SpatialHash:new(cellSize)
    return setmetatable({ cellSize = cellSize, cells = {} }, self)
end

function SpatialHash:clear() self.cells = {} end

function SpatialHash:insert(entity)
    local cx = math.floor(entity.position.x / self.cellSize)
    local cz = math.floor(entity.position.z / self.cellSize)
    local key = cx .. "," .. cz
    self.cells[key] = self.cells[key] or {}
    table.insert(self.cells[key], entity)
end

function SpatialHash:query(pos, radius)
    local results = {}
    local r = math.ceil(radius / self.cellSize)
    local cx = math.floor(pos.x / self.cellSize)
    local cz = math.floor(pos.z / self.cellSize)
    for dx = -r, r do
        for dz = -r, r do
            local key = (cx+dx) .. "," .. (cz+dz)
            for _, e in ipairs(self.cells[key] or {}) do
                if (e.position - pos):Length() < radius then
                    table.insert(results, e)
                end
            end
        end
    end
    return results
end
```

### 关键提醒

1. **Lua 性能边界**：纯 Lua 寻路在 50x50 以下网格性能良好；更大地图务必用协程分帧或降低调用频率
2. **引擎物理优先**：碰撞检测应优先使用引擎内置的 `RigidBody` + `CollisionShape` 系统，不要自行实现 AABB/SAT
3. **Lua 数组从 1 开始**：网格数据结构的索引务必从 1 开始，避免 `array[0]` 返回 nil 的陷阱
4. **Octree 可利用**：引擎的 `Octree` 组件自动管理可绘制对象的空间索引，可通过 `octree:GetDrawables()` 做区域查询

> **相关**: 性能优化 → `performance-optimization.md` | 场景/空间 → `system-scene.md`
