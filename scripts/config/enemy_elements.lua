-- 敌人元素属性配置表（由 CSV 转换而来，可直接编辑此文件或编辑 CSV 后重新生成）
-- 修改数值后重新构建即可生效
-- 每个元素包含：name（名称）、icon（图标）、color（颜色RGBA）、beats（克制）、weak（被克制）
return {
    fire = {
        name = "火", icon = "🔥",
        color = Color(1.0, 0.3, 0.1, 1.0),
        beats = { "wind", "ice" },
        weak = { "water" },
    },
    water = {
        name = "水", icon = "💧",
        color = Color(0.1, 0.5, 1.0, 1.0),
        beats = { "fire" },
        weak = { "thunder" },
    },
    thunder = {
        name = "雷", icon = "⚡",
        color = Color(0.9, 0.8, 0.1, 1.0),
        beats = { "water" },
        weak = { "wind" },
    },
    wind = {
        name = "风", icon = "🌪️",
        color = Color(0.2, 0.9, 0.4, 1.0),
        beats = { "thunder" },
        weak = { "fire" },
    },
    ice = {
        name = "冰", icon = "❄️",
        color = Color(0.5, 0.9, 1.0, 1.0),
        beats = { "wind", "thunder" },
        weak = { "fire" },
    },
    grass = {
        name = "草", icon = "🌿",
        color = Color(0.2, 0.8, 0.3, 1.0),
        beats = { "water" },
        weak = { "fire" },
    },
    earth = {
        name = "土", icon = "🪨",
        color = Color(0.55, 0.27, 0.07, 1.0),
        beats = { "thunder" },
        weak = { "ice" },
    },
}
