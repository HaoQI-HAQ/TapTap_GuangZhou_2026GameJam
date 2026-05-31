# 场景与空间系统

## 对象组织模式

| 模式 | 优势 | 劣势 |
|------|------|------|
| **继承树** | 自然概念映射，代码复用容易 | 刚性强，God Class |
| **聚合Parts** | 保留领域概念同时灵活组合 | 适合复杂少对象（如SRPG） |
| **Entity-Component（EC）** | 高度灵活，行业标准（Unity/Cocos） | 领域概念丢失 |
| **ECS** | 极致性能，缓存友好，网络同步容易 | 复杂度高 |

## 场景管理

### 逻辑结构
- **场景树**：Transform父子标准层级
- **分类列表**：按类型存储（Enemy/Bullet），方便逻辑访问
- **渲染层**：Background→Map→Actor→UI排序

### 空间结构（用于碰撞/可见查询）
| 结构 | 优势 | 适用场景 |
|------|------|----------|
| **Grid** | 快粗筛、TileMap | 2D游戏 |
| **Spatial Hash** | 稀疏/无限边界 | 广阔开放世界 |
| **QuadTree/Octree** | 变尺寸对象 | 通用3D |
| **Graph/Node** | 区域连接 | 策略游戏、传送 |

## 场景加载策略

| 策略 | 说明 |
|------|------|
| **Additive** | 基础场景+叠加层 |
| **Chunking** | 基于玩家位置的网格自动加载/卸载 |
| **Streaming** | 基于逻辑的加载（进入Volume加载"Dungeon_A"） |
| **Spawner** | 玩家接近触发敌人生成 |

## 对象创建

- **Template**：Type+初始数据，JSON/XML/Excel定义，Factory按模板实例化
- **Serialization**：Prefab/Save文件的对象树保存和恢复
- **Cloning**：运行时对象复制（原型模式）


---

## UrhoX 环境适配

### UrhoX 使用 Node + Component 模型

UrhoX 采用类似 Unity 的 **Entity-Component (EC)** 模式，不是纯 ECS：

| 通用概念 | UrhoX 对应 | 说明 |
|---------|-----------|------|
| Entity | `Node` | 场景节点，有 Transform |
| Component | `Component` | 挂载到 Node 上的功能组件 |
| Prefab | 无直接等价 | 用工厂函数 + `node:Clone()` 替代 |
| Scene | `Scene` | 场景根节点，管理所有子节点 |
| Scene Tree | `Node` 父子关系 | `node:CreateChild()` / `node.parent` |

### 对象组织

```lua
-- 创建场景层级
local scene_ = Scene()
scene_:CreateComponent("Octree")         -- 空间索引（引擎需要）
scene_:CreateComponent("PhysicsWorld")   -- 3D 物理（如需要）

-- 创建游戏对象
local playerNode = scene_:CreateChild("Player")
playerNode.position = Vector3(0, 1, 0)

-- 添加组件
local model = playerNode:CreateComponent("StaticModel")
model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))

local body = playerNode:CreateComponent("RigidBody")
body.mass = 1.0

local shape = playerNode:CreateComponent("CollisionShape")
shape:SetBox(Vector3(1, 1, 1))

-- 子节点（武器挂点等）
local weaponNode = playerNode:CreateChild("Weapon")
weaponNode.position = Vector3(0.5, 0, 0.5)
```

### 场景管理模式

```lua
-- 分类列表（按类型管理对象）
local enemies = {}
local bullets = {}

function spawnEnemy(pos)
    local node = scene_:CreateChild("Enemy")
    node.position = pos
    -- ... 添加组件
    table.insert(enemies, node)
    return node
end

function removeEnemy(node)
    for i, e in ipairs(enemies) do
        if e == node then
            table.remove(enemies, i)
            node:Remove()
            break
        end
    end
end
```

### 空间查询

```lua
-- 引擎内置 Octree 空间查询
local octree = scene_:GetComponent("Octree")

-- 射线检测
local ray = camera:GetScreenRay(mouseX, mouseY)
local result = octree:RaycastSingle(ray, RAY_TRIANGLE, 100.0)
if result.drawable then
    local hitNode = result.drawable:GetNode()
end

-- 物理射线
local physicsWorld = scene_:GetComponent("PhysicsWorld")
local hitResult = PhysicsRaycastResult()
physicsWorld:RaycastSingle(hitResult, ray, 100.0)
```

### 场景加载

```lua
-- UrhoX 场景加载方式
-- 1. 程序化创建（推荐，完全可控）
function createScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    -- 逐个创建节点...
end

-- 2. XML 场景文件加载
local file = cache:GetFile("Scenes/MyLevel.xml")
scene_:LoadXML(file)

-- 3. 动态生成（Spawner 模式）
function HandleUpdate(eventType, eventData)
    -- 玩家接近时生成
    if playerNearSpawnPoint() and not spawned then
        spawnEnemyWave()
        spawned = true
    end
end
```

### 关键提醒

1. **程序化创建场景为主**：`Scene()` + `CreateChild()` + `CreateComponent()`，完全可控
2. **空间查询用引擎内置**：`Octree`（3D）自动管理，不要自建八叉树
3. **射线检测区分渲染/物理**：`octree:RaycastSingle` 查渲染体，`physicsWorld:RaycastSingle` 查物理体
4. **节点层级影响变换继承**：子节点自动继承父节点的 position/rotation/scale
5. **动态生成用 Spawner 模式**：条件触发时创建，不要在 Start 中一次性生成全部

> **相关**: 基础框架 → `system-foundation.md` | 性能优化 → `performance-optimization.md`
