# 性能优化

## 优化原则

> **不要猜测，要测量。** 使用Profiler定位瓶颈，确认是CPU-bound还是GPU-bound后再优化。

## 缓存与池化

- **对象池**：复用对象（投射物/敌人/粒子），避免频繁Instantiate/Destroy，减少GC压力
- **组件缓存**：Awake/Start时缓存GetComponent引用，不要每帧获取
- **记忆化**：昂贵纯函数（寻路结果/复杂数学）缓存，输入不变时复用

## 帧时优化

| 策略 | 做法 |
|------|------|
| **时间切片** | 每帧分配时间预算（如2ms），超预算则暂停下帧继续 |
| **队列分帧** | 每帧只处理N个（如每帧只实例化5个敌人） |
| **节流更新** | UI刷新/AI目标选择每N秒执行（如10Hz）而非每帧 |
| **循环分摊** | 1000个实体每帧只更新1/10（轮转） |

## 预计算与预加载

- **LUT查找表**：预计算复杂数学（三角函数/概率曲线）到数组
- **烘焙**：光照/遮挡剔除/寻路网格构建时烘焙
- **预加载**：Loading屏幕强制执行Shader或初始化代码，避免首帧卡顿

## 多线程

- **Worker线程**：AI决策/寻路/程序化生成移至后台线程
- **Job系统**：引擎Job系统（Unity C# Job）安全执行高性能多线程代码
- **GPGPU**：将大量并行任务（集群/流体/粒子物理）移到Compute Shader

## 空间优化

| 策略 | 说明 |
|------|------|
| **AOI** | 只同步/运行视野内实体逻辑 |
| **LOD** | 远处降多边形/纹理/AI行为复杂度 |
| **Hibernation** | 视野外实体完全暂停逻辑 |
| **Frustum Culling** | 视锥体外对象禁用视觉逻辑 |

## 算法优化

- **减少复杂度**：O(N²)→O(N)或O(N log N)
- **数据结构**：HashSet/Dictionary的O(1)查找替代List的O(N)遍历；固定大小用数组
- **SoA vs AoS**：Struct of Arrays布局最大化CPU缓存命中

## 批处理

- **Command Buffer**：收集变化，每帧末或Tick末一次处理
- **UI合批**：共享材质和图集减少Draw Calls
- **数据局部性**：线性遍历数组而非随机内存跳转


---

## UrhoX 环境适配

### 各优化策略可用性

| 策略 | UrhoX 可用性 | 说明 |
|------|-------------|------|
| 对象池 | ✅ 完全可用 | Lua table 管理，`node:SetEnabled(false)` 回收 |
| 组件缓存 | ✅ 推荐 | `node:GetComponent("RigidBody")` 结果缓存到变量 |
| 记忆化 | ✅ 完全可用 | Lua table 作缓存 |
| 时间切片 | ✅ 可用 | `os.clock()` 计时，超预算 yield |
| 队列分帧 | ✅ 可用 | coroutine + 每帧处理 N 个 |
| 节流更新 | ✅ 推荐 | 累加 dt，达到阈值再执行 |
| 循环分摊 | ✅ 可用 | 取模轮转 |
| LUT 查找表 | ✅ 完全可用 | 预计算到 Lua table |
| 预加载 | ✅ 可用 | `cache:GetResource()` 提前加载 |
| Worker 线程 | **❌ 不可用** | Lua VM 单线程 |
| Job 系统 | **❌ 不可用** | 无多线程支持 |
| Compute Shader | **❌ 不可用** | 引擎不支持 |
| AOI | ⚙️ 引擎内置 | Octree 自动管理 |
| LOD | ⚙️ 引擎内置 | 模型 LOD 自动切换 |
| Frustum Culling | ⚙️ 引擎内置 | 自动剔除 |
| 算法优化 | ✅ 完全可用 | 通用优化原则 |
| Command Buffer | ✅ 可用 | 收集变化，批量处理 |
| SoA vs AoS | ⚠️ 效果有限 | Lua table 无内存布局控制 |

### UrhoX 常用优化代码

```lua
-- 对象池
local pool = {}
function getFromPool()
    if #pool > 0 then
        local obj = table.remove(pool)
        obj.node:SetEnabled(true)
        return obj
    end
    return createNewObject()
end
function returnToPool(obj)
    obj.node:SetEnabled(false)
    table.insert(pool, obj)
end

-- 组件缓存（避免每帧 GetComponent）
local cachedBody = node:GetComponent("RigidBody")  -- 初始化时缓存
-- ❌ 错误：每帧调用 node:GetComponent("RigidBody")

-- 节流更新（10Hz AI 更新）
local aiTimer = 0
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    aiTimer = aiTimer + dt
    if aiTimer >= 0.1 then  -- 每 100ms 更新一次
        updateAI()
        aiTimer = aiTimer - 0.1
    end
end
```

### 关键提醒

1. **无多线程** — 所有优化必须在单线程内完成，时间切片和分帧是主要手段
2. **Lua GC** — 减少临时 table 创建，复用对象，避免每帧 `{}` 分配
3. **引擎内置优化** — AOI/LOD/Culling 已由引擎处理，无需手动实现

> **相关**: 算法/数据结构 → `algorithm.md` | 基础框架 → `system-foundation.md`
