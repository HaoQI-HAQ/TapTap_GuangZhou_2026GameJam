# 数据驱动设计

**适用**：轻量业务模块（物品/商店/任务/UI），以数据管理和展示为中心，适合MV系列架构的Model层设计。

## 核心
- **核心**：聚焦数据结构设计和分析，保持数据结构纯粹性
- **特点**：数据与行为分离
- **优势**：性能优化（批处理）、网络同步便捷

## 设计步骤

### 1. 数据建模与分析
基于「结构化设计文档」和「用例」。
- **提取核心实体与属性**：自顶向下（从文档提取）、自底向上（从属性归纳）、用例驱动
- **定义关系与引用**：用ID引用
- **数据分类与拆分**：
  - 静态不变数据 → Config类（配置）
  - 持久数据 → Database/SaveData类（数据）
  - 运行时实例数据 → Runtime/Presentation类（实例）
- **设计配置结构与数据表**：扁平化为表→定主键→规范化→性能合并→定义外键约束
- **设计全局数据容器**：业务数据聚合根，包含所有实体容器
- **验证**：用业务用例验证数据结构是否满足需求

### 2. 封装数据结构
结构为核心，但需要基础操作封装。
- **子数据结构封装**：生命周期、ID引用、属性获取/计算、属性设置（一致性）、修改事件
- **全局容器封装**：集合通用增删改查、业务定制查询/修改、修改事件

### 3. 设计业务流程
基于用例和UI流程图。
- **独立子步骤** → 放入全局容器类（Model层）
- **胶水逻辑** → 放入模块外部包装/Controller（非Model层）

## 与DDD的核心区别

| 维度 | DDD | Data-Driven |
|------|-----|-------------|
| 数据+行为 | 合一（类中） | 分离 |
| 适用场景 | 复杂逻辑 | 简单逻辑、性能敏感、强展示需求 |
| 网络同步 | 较难 | 较易（扁平快照） |


---

## UrhoX 环境适配

### 配置格式映射

| 通用工具 | UrhoX 替代 | 说明 |
|---------|-----------|------|
| Excel/CSV | **JSON 文件** | `cjson.decode()` 解析，策划可直接编辑 |
| ScriptableObject | **Lua table 配置** | 天然支持复杂嵌套结构 |
| Database | **JSON 文件存储** | `File` API 读写，沙箱内安全 |
| XML 配置 | JSON 或 Lua table | XML 可用但不推荐 |

### 数据分类映射

| 数据类别 | 通用描述 | UrhoX 实现 |
|---------|---------|-----------|
| **Config（静态配置）** | Excel/CSV 导出 | `Config/xxx.json` 或 Lua table 文件 |
| **SaveData（持久数据）** | 数据库存储 | `File` API 写入 JSON 文件 |
| **Runtime（运行时数据）** | 内存对象 | Lua table |
| **Cloud（云端数据）** | 服务器数据库 | `clientCloud` / `serverCloud` API |

### JSON 配置示例

```lua
-- Config/items.json
-- {
--   "1001": {"name": "铁剑", "type": "weapon", "atk": 10, "price": 100},
--   "1002": {"name": "木盾", "type": "shield", "def": 5, "price": 50}
-- }

local cjson = require("cjson")

-- 加载配置
local function loadConfig(path)
    local file = cache:GetFile(path)
    if file then
        local str = file:ReadString()
        return cjson.decode(str)
    end
    return {}
end

local itemConfigs = loadConfig("Config/items.json")
local item = itemConfigs["1001"]  -- { name="铁剑", type="weapon", ... }
```

### Lua Table 配置示例

```lua
-- Config/SkillConfig.lua
local SkillConfig = {
    [1001] = {
        name = "火球术",
        damage = 50,
        cd = 3.0,
        range = 10,
        manaCost = 20,
        effects = { {type = "burn", duration = 3, dps = 10} },
    },
    [1002] = {
        name = "冰冻术",
        damage = 30,
        cd = 5.0,
        range = 8,
        manaCost = 30,
        effects = { {type = "slow", duration = 2, factor = 0.5} },
    },
}
return SkillConfig

-- 使用
local SkillConfig = require("Config.SkillConfig")
local skill = SkillConfig[1001]
```

### 全局数据容器模式

```lua
-- GameData.lua：全局数据容器（聚合根）
local GameData = {
    player = { hp = 100, mp = 50, gold = 0, level = 1 },
    inventory = {},     -- { {id=1001, count=3}, ... }
    quests = {},        -- { {id="q001", status="active"}, ... }
}

-- 修改 + 事件通知
function GameData.addItem(itemId, count)
    -- 查找已有
    for _, slot in ipairs(GameData.inventory) do
        if slot.id == itemId then
            slot.count = slot.count + count
            -- 通知变化
            local ed = VariantMap()
            ed["ItemId"] = Variant(itemId)
            ed["Count"] = Variant(slot.count)
            SendEvent("InventoryChanged", ed)
            return
        end
    end
    -- 新物品
    table.insert(GameData.inventory, { id = itemId, count = count })
    local ed = VariantMap()
    ed["ItemId"] = Variant(itemId)
    ed["Count"] = Variant(count)
    SendEvent("InventoryChanged", ed)
end

-- 持久化（保存/读取）
function GameData.save()
    local cjson = require("cjson")
    local file = File("save.json", FILE_WRITE)
    file:WriteString(cjson.encode(GameData))
    file:Close()
end

function GameData.load()
    local cjson = require("cjson")
    if fileSystem:FileExists("save.json") then
        local file = File("save.json", FILE_READ)
        local data = cjson.decode(file:ReadString())
        file:Close()
        GameData.player = data.player or GameData.player
        GameData.inventory = data.inventory or GameData.inventory
        GameData.quests = data.quests or GameData.quests
    end
end

return GameData
```

### 关键提醒

1. **配置格式选 JSON 或 Lua table**：策划迭代多用 JSON，程序内部用 Lua table
2. **全局数据容器用 `local M = {} return M`**：避免全局变量污染
3. **数据变更通过事件通知**：`SendEvent("InventoryChanged", ed)` 解耦数据层与表现层
4. **持久化用 `File` API**：`io` 库已被沙箱移除，使用 `File(path, FILE_WRITE/FILE_READ)`
5. **Lua 数组从 1 开始**：遍历配置表时注意索引

> **相关**: 领域驱动设计 → `domain-driven-design.md` | 基础框架 → `system-foundation.md`
