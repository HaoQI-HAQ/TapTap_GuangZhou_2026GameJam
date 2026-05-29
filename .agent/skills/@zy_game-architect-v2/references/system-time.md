# 时间逻辑与流程控制

## 核心机制

| 机制 | 说明 |
|------|------|
| **Update** | 帧更新，频率随FPS变化，适合视觉和非确定性逻辑 |
| **FixedUpdate** | 固定频率，适合物理和确定性逻辑 |

## 异步逻辑

| 机制 | 说明 |
|------|------|
| **Coroutine** | 状态机，`yield return`驱动，轻量，适合顺序脚本 |
| **Async/Await** | Task驱动，需自定义SyncContext确保在主逻辑线程恢复 |

## 定时器

- **轮询列表**：简单精确，小量适用
- **延迟队列（Min-Heap）**：按过期时间优先队列
- **Timing Wheel**：高性能大量Timer，常O(1)

## 命令队列

顺序执行命令（Start/Update/IsComplete/End），支持执行期间动态插入/删除。
扩展：优先级通道（High/Low）、分类队列（UI/Resource/Battle）。

## 状态机

| 模式 | 优势 | 适用 |
|------|------|------|
| **Enum-Switch** | 高性能 | 简单控制器 |
| **Async FSM** | 线性序列和脚本场景 | 脚本化场景 |
| **State Pattern** | 独立复杂行为 | 复杂独立行为 |
| **Stack FSM** | Push/Pop覆盖和返回 | UI覆盖层 |
| **HFSM** | 子状态机嵌套 | 复杂分层行为 |
| **Transition Table** | 集中管理转换条件 | 复杂转换逻辑 |

## 插值与缓动

- **Tween**：Position/Alpha/Scale等数值插值，链式API
- **Timeline**：多轨道并行，关键帧驱动，适合过场和固定技能动画

## 全局游戏流

状态机管理整体生命周期：`Init`→`MainMenu`→`LevelSelect`→`Battle`→`Pause`
- **Init**：async/await处理非阻塞顺序初始化（Resources→Configs→Modules）
- **胜负判定**：轮询检查/触发列表/条件树/Reactive


---

## UrhoX 环境适配

### 机制可用性

| 机制 | UrhoX 可用性 | 替代方案 |
|------|-------------|---------|
| Update（帧更新） | ✅ `SubscribeToEvent("Update", handler)` | — |
| FixedUpdate（固定帧率） | ✅ `SubscribeToEvent("PhysicsPreStep", handler)` | — |
| Coroutine | ✅ Lua 原生 `coroutine` | — |
| Async/Await | **❌ 不可用** | 用 coroutine 模拟 |
| Tween 插值 | ⚠️ 需自行实现或用 `ValueAnimation` | 见下方示例 |
| Timeline | **❌ 不可用** | 用 coroutine 序列替代 |

### Coroutine 异步序列（核心模式）

```lua
-- 替代 async/await 的标准模式
local sequences = {}

function startSequence(fn)
    local co = coroutine.create(fn)
    table.insert(sequences, co)
    coroutine.resume(co)
end

-- 等待 N 秒
function waitSeconds(seconds)
    local elapsed = 0
    while elapsed < seconds do
        elapsed = elapsed + coroutine.yield()  -- yield 返回 dt
    end
end

-- 在 Update 中驱动所有协程
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    for i = #sequences, 1, -1 do
        local co = sequences[i]
        if coroutine.status(co) ~= "dead" then
            coroutine.resume(co, dt)
        else
            table.remove(sequences, i)
        end
    end
end

-- 使用示例：技能释放序列
startSequence(function()
    playAnimation("cast_start")
    waitSeconds(0.5)             -- 起手
    spawnProjectile()
    waitSeconds(0.2)             -- 弹道延迟
    playAnimation("cast_end")
    waitSeconds(0.3)             -- 收招
end)
```

### 简易定时器

```lua
local timers = {}

function addTimer(delay, callback, repeating)
    table.insert(timers, {
        remaining = delay,
        interval = delay,
        callback = callback,
        repeating = repeating or false,
    })
end

function updateTimers(dt)
    for i = #timers, 1, -1 do
        local t = timers[i]
        t.remaining = t.remaining - dt
        if t.remaining <= 0 then
            t.callback()
            if t.repeating then
                t.remaining = t.remaining + t.interval
            else
                table.remove(timers, i)
            end
        end
    end
end

-- 使用
addTimer(3.0, function() print("3秒后执行") end)
addTimer(1.0, function() print("每秒执行") end, true)
```

### 状态机推荐模式

在 Lua 中推荐 **Enum-Switch** 或 **State Table** 模式：

```lua
-- State Table 模式（推荐）
local states = {
    idle = {
        enter = function(self) end,
        update = function(self, dt) end,
        exit = function(self) end,
    },
    attack = {
        enter = function(self) playAnimation("attack") end,
        update = function(self, dt)
            self.timer = self.timer - dt
            if self.timer <= 0 then self:changeState("idle") end
        end,
        exit = function(self) end,
    },
}
```

### 关键提醒

1. **dt 来自事件参数**：`eventData["TimeStep"]:GetFloat()`，不要用 `os.clock()`
2. **定时器用反向遍历移除**：`for i = #timers, 1, -1 do` 避免索引错位
3. **状态机推荐 State Table 模式**：`states[currentState].update(self, dt)`
4. **异步序列用 coroutine**：`coroutine.yield()` 暂停，在 Update 中 `resume`
5. **不要绑定帧率**：所有运动/逻辑乘以 `dt`，确保设备间行为一致

> **相关**: 战斗/动作 → `system-action-combat.md` | 技能/Buff → `system-skill.md`
