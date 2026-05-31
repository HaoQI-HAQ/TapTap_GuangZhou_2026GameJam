-- 卡牌数据定义
local CardData = {}

-- 属性克制环: 火→冰→风→雷→土→火
CardData.COUNTER_MAP = {
    fire    = "ice",      -- 火克冰
    ice     = "wind",     -- 冰克风
    wind    = "thunder",  -- 风克雷
    thunder = "earth",    -- 雷克土
    earth   = "fire",     -- 土克火
}

-- 属性颜色
CardData.ELEMENT_COLORS = {
    fire    = { hex = "#FF4500", color = Color(1.0, 0.27, 0.0, 1.0), icon = "🔥", name = "火" },
    ice     = { hex = "#00CED1", color = Color(0.0, 0.81, 0.82, 1.0), icon = "❄️", name = "冰" },
    wind    = { hex = "#32CD32", color = Color(0.2, 0.8, 0.2, 1.0),  icon = "🌪️", name = "风" },
    thunder = { hex = "#FFD700", color = Color(1.0, 0.84, 0.0, 1.0), icon = "⚡", name = "雷" },
    earth   = { hex = "#8B4513", color = Color(0.55, 0.27, 0.07, 1.0), icon = "🪨", name = "土" },
    time    = { hex = "#4B0082", color = Color(0.29, 0.0, 0.51, 1.0), icon = "⏸️", name = "时" },
    slow    = { hex = "#9370DB", color = Color(0.58, 0.44, 0.86, 1.0), icon = "⏳", name = "缓" },
    space   = { hex = "#C0C0C0", color = Color(0.75, 0.75, 0.75, 1.0), icon = "🌀", name = "空" },
    matter  = { hex = "#8B4513", color = Color(0.55, 0.27, 0.07, 1.0), icon = "💎", name = "质" },
    none    = { hex = "#A9A9A9", color = Color(0.66, 0.66, 0.66, 1.0), icon = "⚪", name = "无" },
}

-- 技能类型枚举
CardData.SKILL_TYPE = {
    PROJECTILE = "projectile",     -- 直线投射物
    FAN_PROJECTILE = "fan_proj",   -- 扇形投射物
    GROUND_SPIKE = "ground_spike", -- 地面刺出
    SELF_AOE = "self_aoe",         -- 自身范围
    TARGET_AOE = "target_aoe",     -- 指定位置范围
    BUFF = "buff",                 -- 增益/控制
    TELEPORT = "teleport",         -- 传送
    BEAM = "beam",                 -- 光束贯穿
    TRAP = "trap",                 -- 陷阱
    WALL = "wall",                 -- 屏障
    MELEE = "melee",               -- 近战斩击
    DOT = "dot",                   -- 持续伤害
}

-- 所有卡牌定义
CardData.CARDS = {
    -- === 火属性 ===
    F01 = {
        id = "F01", name = "烈焰弹", element = "fire", rarity = "normal",
        skillType = "projectile",
        damage = 1.0,  -- 100%攻击力
        speed = 12.0,  -- 投射物速度 m/s
        range = 15.0,  -- 最大射程
        cooldown = 0,
        weight = 8,
        image = "image/card/card_F01_烈焰弹_20260530094100.png",
        desc = "发射一枚火球直线飞行",
    },
    F03 = {
        id = "F03", name = "熔岩喷射", element = "fire", rarity = "rare",
        skillType = "fan_proj",
        damage = 0.5,   -- 每段50%×4段
        hits = 4,
        range = 4.0,    -- 短距
        fanAngle = 40,  -- 扇形角度
        burnDuration = 1.0,  -- 燃烧区域持续
        cooldown = 0,
        weight = 4,
        image = "image/card/card_F03_熔岩喷射_20260530094109.png",
        desc = "扇形喷射熔岩碎片",
    },
    -- === 冰属性 ===
    I01 = {
        id = "I01", name = "冰霜刺", element = "ice", rarity = "normal",
        skillType = "ground_spike",
        damage = 1.1,  -- 110%攻击力
        range = 3.0,   -- 前方距离
        slowPercent = 0.2,
        slowDuration = 1.5,
        cooldown = 0,
        weight = 8,
        image = "image/card/card_I01_冰霜刺_20260530094103.png",
        desc = "地面升起冰刺",
    },
    I02 = {
        id = "I02", name = "冰晶弹幕", element = "ice", rarity = "normal",
        skillType = "fan_proj",
        damage = 0.4,   -- 每枚40%
        hits = 4,
        range = 10.0,
        fanAngle = 30,
        speed = 10.0,
        cooldown = 0,
        weight = 8,
        image = "image/card/card_I02_冰晶弹幕_20260530094105.png",
        desc = "4枚冰晶扇形散射",
    },
    I03 = {
        id = "I03", name = "极寒领域", element = "ice", rarity = "rare",
        skillType = "self_aoe",
        damage = 0.3,     -- 每次30%
        radius = 3.0,
        tickInterval = 0.5,
        duration = 3.0,
        slowPercent = 0.4,
        cooldown = 5.0,
        weight = 4,
        image = "image/card/card_I03_极寒领域_20260530094101.png",
        desc = "展开冰冻领域",
    },
    -- === 风属性 ===
    W01 = {
        id = "W01", name = "旋风斩", element = "wind", rarity = "normal",
        skillType = "self_aoe",
        damage = 0.9,   -- 90%攻击力
        radius = 2.0,
        duration = 0.5, -- 瞬发效果
        tickInterval = 0.5,
        cooldown = 0,
        weight = 8,
        image = "image/card/card_W01_旋风斩_20260530094101.png",
        desc = "风刃环绕一圈",
    },
    W02 = {
        id = "W02", name = "风刃飞射", element = "wind", rarity = "normal",
        skillType = "fan_proj",
        damage = 0.5,   -- 每道50%
        hits = 3,
        range = 12.0,
        fanAngle = 10,  -- 平行排列，小角度
        speed = 14.0,
        pierce = 1,     -- 穿透1个
        cooldown = 0,
        weight = 8,
        image = "image/card/card_W02_风刃飞射_20260530094100.png",
        desc = "3道风刃平行飞射",
    },
    W04 = {
        id = "W04", name = "真空斩", element = "wind", rarity = "rare",
        skillType = "projectile",
        damage = 2.0,   -- 200%攻击力
        speed = 16.0,
        range = 8.0,
        armorIgnore = 0.3,
        knockback = 2.0,
        cooldown = 0,
        weight = 4,
        image = "image/card/card_W04_真空斩_20260530094325.png",
        desc = "真空刀刃前斩",
    },
    -- === 雷属性 ===
    T01 = {
        id = "T01", name = "雷霆击", element = "thunder", rarity = "normal",
        skillType = "projectile",
        damage = 1.0,  -- 100%攻击力
        speed = 14.0,
        range = 12.0,
        chainChance = 0.1,  -- 10%连锁
        cooldown = 0,
        weight = 8,
        image = "image/card/card_T01_雷霆击_20260530120331.png",
        desc = "释放雷击",
    },
    T03 = {
        id = "T03", name = "雷暴领域", element = "thunder", rarity = "rare",
        skillType = "target_aoe",
        damage = 0.8,     -- 每次80%
        radius = 3.0,
        tickInterval = 0.8,
        duration = 3.0,
        stunChance = 0.2,
        cooldown = 6.0,
        weight = 4,
        image = "image/card/card_T03_雷暴领域_20260530120331.png",
        desc = "展开雷暴云层",
    },
    T04 = {
        id = "T04", name = "瞬雷", element = "thunder", rarity = "rare",
        skillType = "target_aoe",
        damage = 1.8,   -- 180%攻击力
        radius = 1.5,
        duration = 0.3, -- 瞬发
        tickInterval = 0.3,
        stunDuration = 0.5,
        cooldown = 0,
        weight = 4,
        image = "image/card/card_T04_瞬雷_20260530094326.png",
        desc = "瞬间落雷",
    },
    -- === 土属性 ===
    E02 = {
        id = "E02", name = "尖刺陷阱", element = "earth", rarity = "normal",
        skillType = "trap",
        damage = 1.2,   -- 120%攻击力
        range = 4.0,
        rootDuration = 1.0,
        maxTraps = 2,
        cooldown = 0,
        weight = 7,
        image = "image/card/card_E02_尖刺陷阱_20260530094325.png",
        desc = "布置尖刺陷阱",
    },
    E03 = {
        id = "E03", name = "岩壁屏障", element = "earth", rarity = "rare",
        skillType = "wall",
        duration = 3.0,
        cooldown = 6.0,
        weight = 4,
        image = "image/card/card_E03_岩壁屏障_20260530094325.png",
        desc = "召唤岩壁",
    },
    E04 = {
        id = "E04", name = "地裂冲击", element = "earth", rarity = "rare",
        skillType = "ground_spike",
        damage = 1.6,    -- 160%攻击力
        range = 6.0,
        floatDuration = 0.8,
        cooldown = 0,
        weight = 4,
        image = "image/card/card_E04_地裂冲击_20260530094325.png",
        desc = "地面裂缝冲击",
    },
    -- === 无属性/特殊 ===
    N01 = {
        id = "N01", name = "时间停止", element = "time", rarity = "rare",
        skillType = "buff",
        duration = 2.0,
        isGlobal = true,  -- 全屏效果
        freezeAll = true,
        cooldown = 0,
        maxUse = 1,       -- 整局限1次
        weight = 2,
        image = "image/card/card_N01_时间停止_20260530094412.png",
        desc = "全屏时间冻结2秒",
    },
    N02 = {
        id = "N02", name = "时间裂隙", element = "time", rarity = "rare",
        skillType = "target_aoe",
        radius = 2.0,
        duration = 2.0,
        freezeInArea = true,
        cooldown = 8.0,
        weight = 3,
        image = "image/card/card_N02_时间裂隙_20260530094353.png",
        desc = "范围时间停止",
    },
    N03 = {
        id = "N03", name = "时间减缓", element = "slow", rarity = "normal",
        skillType = "buff",
        duration = 3.0,
        isGlobal = true,
        slowPercent = 0.5,
        cooldown = 10.0,
        weight = 5,
        image = "image/card/card_N03_时间减缓_20260530094348.png",
        desc = "全屏减速50%",
    },
    N06 = {
        id = "N06", name = "空间折跃", element = "space", rarity = "rare",
        skillType = "teleport",
        damage = 0.8,     -- 途经伤害80%
        maxDist = 5.0,
        invincibleTime = 0.3,
        cooldown = 4.0,
        weight = 3,
        image = "image/card/card_N06_空间折跃_20260530094348.png",
        desc = "瞬移至前方",
    },
    N07 = {
        id = "N07", name = "物质崩解", element = "matter", rarity = "rare",
        skillType = "dot",
        damage = 0.6,     -- 每秒60%
        duration = 3.0,
        defReduce = 0.3,
        cooldown = 8.0,
        weight = 3,
        image = "image/card/card_N07_物质崩解_20260530094348.png",
        desc = "持续物质伤害",
    },
    N08 = {
        id = "N08", name = "物质凝聚弹", element = "matter", rarity = "normal",
        skillType = "projectile",
        damage = 1.3,     -- 130%攻击力
        speed = 10.0,
        range = 10.0,
        splashDamage = 0.5,
        splashRadius = 2.0,
        cooldown = 0,
        weight = 6,
        image = "image/card/card_N08_物质凝聚弹_20260530094354.png",
        desc = "物质弹命中爆散",
    },
    N09 = {
        id = "N09", name = "虚无之刃", element = "none", rarity = "normal",
        skillType = "melee",
        damage = 1.0,     -- 100%攻击力
        range = 2.0,
        ignoreResist = true,
        cooldown = 0,
        weight = 7,
        image = "image/card/card_N09_虚无之刃_20260530094351.png",
        desc = "无属性前刺",
    },
    N10 = {
        id = "N10", name = "中和射线", element = "none", rarity = "normal",
        skillType = "beam",
        damage = 0.7,     -- 70%×命中数
        range = 12.0,
        pierceAll = true,
        removeBuffs = true,
        cooldown = 6.0,
        weight = 6,
        image = "image/card/card_N10_中和射线_20260530094352.png",
        desc = "白光贯穿所有敌人",
    },
    S01 = {
        id = "S01", name = "梦想封印", element = "fire", rarity = "rare",
        skillType = "projectile",
        damage = 0.8,     -- 80%攻击力
        speed = 10.0,
        range = 10.0,
        sealDuration = 3.0,
        cooldown = 10.0,
        weight = 2,
        image = "image/card/card_S01_梦想封印_20260530120331.png",
        desc = "封印敌人技能3秒",
    },
}

-- 构建加权卡池（用于随机抽取）
CardData.POOL = {}
for id, card in pairs(CardData.CARDS) do
    for i = 1, card.weight do
        table.insert(CardData.POOL, id)
    end
end

--- 判断卡牌属性是否克制目标属性
---@param cardElement string
---@param targetElement string
---@return boolean
function CardData.isCounter(cardElement, targetElement)
    return CardData.COUNTER_MAP[cardElement] == targetElement
end

--- 获取卡牌是否为无属性（不参与克制）
function CardData.isNeutral(element)
    return element == "time" or element == "slow" or element == "space"
        or element == "matter" or element == "none"
end

return CardData
