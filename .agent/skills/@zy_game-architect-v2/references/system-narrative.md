# 叙事系统架构

## 核心模块

- **数据与配置**：叙事实体数据、追踪进度的变量
- **叙事逻辑与流程**：原子操作（Commands）和编排（Sequences）
- **运行时执行**：管理序列播放和存档
- **表现层**：UI/游戏操控呈现故事

## 数据配置

### 角色数据库
- **Avatar数据**：ID、图标、立绘、位置数据、动画引用

### 变量面板（Blackboard）
| 范围 | 说明 |
|------|------|
| **Global** | 整个游戏或会话持久 |
| **Local** | 临时，属于特定序列播放器实例 |

## 叙事逻辑

### Commands（原子操作）
| 类型 | 示例 |
|------|------|
| **原子操作** | CameraTo、Say、Wait（异步） |
| **结构命令** | If、Loop、Goto、Parallel、SubModule |
| **变量操作** | Get、Set |
| **外部调用** | 绑定到外部函数/脚本 |

### 序列存储格式
| 格式 | 优势 |
|------|------|
| **数据表** | Excel/CSV，Type+Parameters |
| **脚本文件** | DSL，适合策划 |
| **Node Graph** | 可视化图，灵活 |
| **Timeline** | 轨道式，过场专用 |
| **硬编码** | 链式Action/Fluent API |

## 运行时

### Sequence Player
核心播放器，控制播放/停止/暂停/恢复，管理生命周期事件。

### 存档/读档
**存档**：Global Variables + 所有Sequence Players的光标状态 + 故事场景对象树
**读档**：恢复变量→重建场景→重建播放器→恢复光标

### 快进
跳过Wait、静音音频，快速推进到目标点。

## 表现层

| 形式 | 说明 |
|------|------|
| **Story Scene（UI层）** | 立绘+对话框+选项菜单，用于视觉小说 |
| **Gameplay Scene（游戏层）** | 直接控制游戏摄像机和角色，用于游戏内过场 |


---

## UrhoX 环境适配

### 叙事模块映射

| 通用概念 | UrhoX 实现 | 说明 |
|---------|-----------|------|
| 角色数据库 | JSON 配置 + `cache:GetFile()` | 角色立绘/图标用 `Texture2D` 资源 |
| 变量面板（Blackboard） | Lua table（内存） | Global 持久化用 `File` API 写 JSON |
| Commands（原子操作） | Lua 协程 `coroutine` | 天然支持异步：`coroutine.yield()` 等待 |
| Sequence Player | Lua 协程调度器 | 每帧 `coroutine.resume()`，见下方示例 |
| 存档/读档 | `File` API + `cjson` | 序列化 Blackboard + 光标状态 |
| UI 表现层 | `urhox-libs/UI` | 对话框/选项菜单/立绘用 Yoga Flexbox 布局 |
| 游戏层过场 | 引擎 Node + 动画 | 相机控制用 `node:LookAt()` / 动画组件 |

### 协程驱动的 Sequence Player

```lua
-- 基于协程的叙事序列播放器
local NarrativePlayer = {}
NarrativePlayer.__index = NarrativePlayer

function NarrativePlayer:new()
    return setmetatable({
        co = nil,
        blackboard = {},       -- 变量面板
        waitTime = 0,
        waiting = false,
    }, self)
end

-- 启动序列
function NarrativePlayer:play(sequenceFunc)
    self.co = coroutine.create(function()
        sequenceFunc(self)
    end)
end

-- 每帧更新（在 Update 事件中调用）
function NarrativePlayer:update(dt)
    if not self.co then return end

    if self.waiting then
        self.waitTime = self.waitTime - dt
        if self.waitTime > 0 then return end
        self.waiting = false
    end

    local ok, err = coroutine.resume(self.co)
    if not ok then print("Narrative error: " .. tostring(err)) end
    if coroutine.status(self.co) == "dead" then
        self.co = nil  -- 序列结束
    end
end

-- Commands（原子操作）
function NarrativePlayer:say(speaker, text)
    -- 显示对话 UI（使用 urhox-libs/UI）
    showDialogueUI(speaker, text)
    coroutine.yield()  -- 等待玩家点击继续
end

function NarrativePlayer:wait(seconds)
    self.waitTime = seconds
    self.waiting = true
    coroutine.yield()
end

function NarrativePlayer:setVar(key, value)
    self.blackboard[key] = value
end

function NarrativePlayer:getVar(key)
    return self.blackboard[key]
end

function NarrativePlayer:choice(options)
    -- 显示选项 UI，等待玩家选择
    showChoiceUI(options)
    coroutine.yield()  -- 等待选择回调设置结果
    return self.lastChoice
end
```

### 叙事序列定义示例

```lua
-- 用 Lua 函数直接定义叙事序列（硬编码模式）
local function introSequence(player)
    player:say("旁白", "黎明前的最后一丝暗光中，城镇苏醒了。")
    player:wait(1.0)
    player:say("村长", "冒险者，你终于来了！")

    local choice = player:choice({
        "我准备好了",
        "再等一下",
    })

    if choice == 1 then
        player:setVar("ready", true)
        player:say("村长", "很好，出发吧！")
    else
        player:say("村长", "好吧，准备好了再来找我。")
    end
end

-- 启动
local narrator = NarrativePlayer:new()
narrator:play(introSequence)

-- 在 Update 中驱动
SubscribeToEvent("Update", function(_, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    narrator:update(dt)
end)
```

### 存档与读档

```lua
-- 存档：序列化 Blackboard + 进度
local cjson = require("cjson")

local function saveNarrative(player, slotName)
    local saveData = {
        blackboard = player.blackboard,
        currentSequenceId = player.currentSequenceId,
        -- 光标状态需要在序列设计中维护进度标记
    }
    local file = File(slotName .. ".json", FILE_WRITE)
    file:WriteString(cjson.encode(saveData))
    file:Close()
end

local function loadNarrative(player, slotName)
    if not fileSystem:FileExists(slotName .. ".json") then return false end
    local file = File(slotName .. ".json", FILE_READ)
    local data = cjson.decode(file:ReadString())
    file:Close()
    player.blackboard = data.blackboard or {}
    -- 根据 currentSequenceId 恢复到对应序列
    return true
end
```

### 关键提醒

1. **协程是核心**：Lua 协程天然适合叙事系统的「执行→暂停→等待→继续」模式，不要用回调地狱
2. **UI 层用 urhox-libs/UI**：对话框、选项菜单、立绘展示都应使用 Yoga Flexbox 布局（`UI.Panel` / `UI.Label` / `UI.Button`）
3. **快进实现**：跳过 `wait()` 中的计时器（将 `waitTime` 置 0），静音音效（`SoundSource.gain = 0`）
4. **数据驱动扩展**：大型叙事项目建议将序列存为 JSON 数组，运行时解释执行，而非硬编码 Lua 函数

> **相关**: 时间/逻辑流 → `system-time.md` | UI/模块管理 → `system-ui.md`
