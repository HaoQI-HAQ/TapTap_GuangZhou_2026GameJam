# 用例驱动原型设计

**适用**：快速原型开发（验证玩法/技术），以用例为中心，快速迭代。

## 核心
- **核心**：设计完全从用例反推
- **特点**：所见即所得、快、初始架构弱（需要重构）
- **适用**：快速验证、单人/小团队开发

## 步骤

### 1. 用例迭代拆分
拆分为小而快的迭代步骤（每步1-3天）。
- 示例：
  - 迭代1：显示地图
  - 迭代2：角色移动
  - 迭代3：敌人生成与移动
  - ……

### 2. 快速用例导向开发
- **原则**：用最快最直接的方式实现
- **实现**：
  - 无复杂设计，可直接写在Controller或无关类中
  - 用假数据和临时展示
  - **质量底线不打折**：游戏性效果本身要准确实现以验证玩法

### 3. 重构到架构
控制混乱、引入架构的关键步骤。
- **职责提取**：将混合的职责提取为类
- **逻辑分解**：拆分复杂类
- **基类提取**：为相似概念提取基类
- **接口提取**：隔离变化点
- **配置提取**：将数值提取为配置

## 扩展：数据驱动用例开发
1. 将游戏数据结构作为统一数据层（直接暴露）
2. 将用例功能分解为逻辑指令（函数），直接操作数据层
3. 接口直接读取数据展示

特点：跳过封装和类设计，极快实现，但扩展性弱。

## 优缺点

- **优点**：开发快、迭代快、反馈快
- **缺点**：架构不稳定、容易偏离、不适合大团队/长期正式项目（除非严格重构）

---

## UrhoX 环境适配

### 原型方法论 → UrhoX 落地映射

| 原型步骤 | UrhoX 实现方式 |
|---------|---------------|
| 用例迭代拆分 | 每次迭代对应一次 `build` → 预览循环 |
| 快速实现（无复杂设计） | 直接在 `main.lua` 单文件中编写，使用全局函数 |
| 假数据 / 临时展示 | NanoVG 文本 + 硬编码 Lua table |
| 重构到架构 | 提取为 `require` 模块，拆分到 `scripts/` 子目录 |
| 数据驱动用例 | 全局 Lua table 作为数据层 + JSON 配置文件 |

### 快速原型：单文件起手

原型阶段不需要模块化，直接在入口文件中快速实现：

```lua
-- scripts/main.lua（原型阶段，全部写在一起）

-- ① 游戏数据（直接暴露的全局 table）
local gameData = {
    player = { x = 0, y = 0, hp = 100, speed = 5.0 },
    enemies = {},
    score = 0,
}

-- ② 用例函数（直接操作数据层）
local function spawnEnemy()
    table.insert(gameData.enemies, {
        x = math.random(-10, 10),
        y = 0,
        z = math.random(-10, 10),
        hp = 30,
    })
end

local function movePlayer(dx, dz, dt)
    gameData.player.x = gameData.player.x + dx * gameData.player.speed * dt
    if playerNode then
        playerNode.position = Vector3(gameData.player.x, 0, gameData.player.x)
    end
end

-- ③ Start / Update（引擎入口）
function Start()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    local lightNode = scene_:CreateChild("Light")
    lightNode.direction = Vector3(0.5, -1.0, 0.5)
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL

    playerNode = scene_:CreateChild("Player")
    local model = playerNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")

    spawnEnemy()

    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if input:GetKeyDown(KEY_W) then movePlayer(0, 1, dt) end
    if input:GetKeyDown(KEY_S) then movePlayer(0, -1, dt) end
end
```

### 重构到架构：提取模块

当原型验证通过后，按职责拆分文件：

```
scripts/
├── main.lua              -- 入口，只做初始化和事件绑定
├── Data/
│   └── GameData.lua      -- 数据层（从 gameData table 提取）
├── Logic/
│   ├── PlayerLogic.lua   -- 玩家逻辑（从 movePlayer 等提取）
│   └── EnemyLogic.lua    -- 敌人逻辑（从 spawnEnemy 等提取）
└── View/
    └── HUD.lua           -- UI 展示（从临时 NanoVG 文本提取）
```

```lua
-- scripts/Data/GameData.lua（提取后的数据模块）
local M = {}

M.player = { x = 0, y = 0, hp = 100, speed = 5.0 }
M.enemies = {}
M.score = 0

function M.reset()
    M.player.hp = 100
    M.enemies = {}
    M.score = 0
end

return M
```

```lua
-- scripts/main.lua（重构后的入口）
local GameData = require "Data.GameData"
local PlayerLogic = require "Logic.PlayerLogic"
local EnemyLogic = require "Logic.EnemyLogic"

function Start()
    GameData.reset()
    EnemyLogic.spawnWave(3)
    SubscribeToEvent("Update", "HandleUpdate")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    PlayerLogic.handleInput(dt)
    EnemyLogic.updateAll(dt)
end
```

### 迭代验证循环

UrhoX 的原型迭代与构建工具绑定：

```
编写代码 → build 工具构建 → 预览验证 → 调整 → 再 build
     ↑                                          |
     └──────────────────────────────────────────┘
```

每次迭代保持"**可运行**"状态，确保每次 build 后都能看到变化。

### 关键提醒

1. **原型阶段允许单文件**：不要过早拆分，但超过 1000 行时主动提议重构
2. **假数据用 Lua table**：不需要引入 JSON/外部配置，直接硬编码
3. **临时 UI 用 NanoVG 文本**：`nvgText()` 最快展示调试信息
4. **质量底线**：原型代码可以"丑"，但游戏性逻辑必须准确（不要用假碰撞替代真物理）
5. **重构时机**：验证通过 + 代码接近 1000 行 → 开始拆分为 `require` 模块

> **相关**: 架构原理 → `principles.md` | 数据驱动设计 → `data-driven-design.md`
