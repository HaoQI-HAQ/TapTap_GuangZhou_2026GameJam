-- 配置加载器
-- 从 scripts/config/ 目录加载 Lua 配置表
-- 配置文件为纯 Lua table，可用 Excel 编辑 CSV 后通过脚本转换生成
local ConfigLoader = {}

-- 加载玩家配置
function ConfigLoader.loadPlayerConfig()
    local ok, cfg = pcall(require, "config.player_config")
    if ok and cfg then
        return cfg
    end
    log:Write(LOG_WARNING, "[ConfigLoader] Failed to load player_config, using defaults")
    return {}
end

-- 加载敌人基础配置
function ConfigLoader.loadEnemyConfig()
    local ok, cfg = pcall(require, "config.enemy_config")
    if ok and cfg then
        return cfg
    end
    log:Write(LOG_WARNING, "[ConfigLoader] Failed to load enemy_config, using defaults")
    return {}
end

-- 加载敌人属性配置
function ConfigLoader.loadEnemyElements()
    local ok, cfg = pcall(require, "config.enemy_elements")
    if ok and cfg then
        return cfg
    end
    log:Write(LOG_WARNING, "[ConfigLoader] Failed to load enemy_elements, using defaults")
    -- 返回最小可用的兜底数据
    return {
        fire = { name = "火", icon = "🔥", color = Color(1.0, 0.3, 0.1, 1.0), beats = { "wind", "ice" }, weak = { "water" } },
        water = { name = "水", icon = "💧", color = Color(0.1, 0.5, 1.0, 1.0), beats = { "fire" }, weak = { "thunder" } },
        thunder = { name = "雷", icon = "⚡", color = Color(0.9, 0.8, 0.1, 1.0), beats = { "water" }, weak = { "wind" } },
        wind = { name = "风", icon = "🌪️", color = Color(0.2, 0.9, 0.4, 1.0), beats = { "thunder" }, weak = { "fire" } },
        ice = { name = "冰", icon = "❄️", color = Color(0.5, 0.9, 1.0, 1.0), beats = { "wind", "thunder" }, weak = { "fire" } },
        grass = { name = "草", icon = "🌿", color = Color(0.2, 0.8, 0.3, 1.0), beats = { "water" }, weak = { "fire" } },
        earth = { name = "土", icon = "🪨", color = Color(0.55, 0.27, 0.07, 1.0), beats = { "thunder" }, weak = { "ice" } },
    }
end

return ConfigLoader
