-- CardSystem 类：卡牌系统
-- 手牌上限5张，每5秒刷新一轮，每秒自动消耗1张（从右侧），同一轮可使用多张
CardSystem = {}
CardSystem.__index = CardSystem

-- 配置常量
local MAX_HAND = 5              -- 手牌上限
local REFRESH_INTERVAL = 5.0    -- 刷新间隔（秒）
local CONSUME_INTERVAL = 1.0    -- 自动消耗间隔（秒）
local CAST_DURATION = 0.3       -- 施法动画时长（秒）

-- 卡牌类型
CardSystem.TYPE_ATTACK  = "attack"
CardSystem.TYPE_DEFENSE = "defense"
CardSystem.TYPE_SUPPORT = "support"

-- 卡牌属性（与Enemy.ELEMENTS对应）
CardSystem.ELEMENTS = {
    fire    = { name = "火", icon = "🔥", color = Color(1.0, 0.3, 0.1, 1.0) },
    water   = { name = "水", icon = "💧", color = Color(0.1, 0.5, 1.0, 1.0) },
    thunder = { name = "雷", icon = "⚡", color = Color(0.9, 0.8, 0.1, 1.0) },
    wind    = { name = "风", icon = "🌪️", color = Color(0.2, 0.9, 0.4, 1.0) },
    ice     = { name = "冰", icon = "❄️", color = Color(0.5, 0.9, 1.0, 1.0) },
}

-- 卡牌类型图标
local TYPE_ICONS = {
    attack  = "⚔️",
    defense = "🛡️",
    support = "✨",
}

-- 卡牌类型名称
local TYPE_NAMES = {
    attack  = "攻",
    defense = "防",
    support = "辅",
}

-- 克制关系（攻击型卡牌打对应属性敌人伤害加倍）
local COUNTER_TABLE = {
    fire    = { "wind", "ice" },
    water   = { "fire" },
    thunder = { "water" },
    wind    = { "thunder" },
    ice     = { "wind", "thunder" },
}

function CardSystem:new()
    local self = setmetatable({}, CardSystem)
    self.hand = {}              -- 当前手牌 [{type, element, elementData}]
    self.refreshTimer = REFRESH_INTERVAL   -- 刷新倒计时
    self.consumeTimer = CONSUME_INTERVAL   -- 消耗倒计时
    self.casting = false        -- 是否正在施法
    self.castTimer = 0          -- 施法计时器
    self.castCard = nil         -- 当前施法的卡牌
    self.onCastStart = nil      -- 施法开始回调（通知player锁定移动）
    self.onCastEnd = nil        -- 施法结束回调（通知player解除锁定）
    self.onCardUsed = nil       -- 卡牌使用回调（执行效果）

    -- 初始发牌
    self:_refreshHand()

    log:Write(LOG_INFO, "[CardSystem] Created, hand=" .. #self.hand)
    return self
end

-- 每帧更新
function CardSystem:update(dt)
    -- 施法动画
    if self.casting then
        self.castTimer = self.castTimer - dt
        if self.castTimer <= 0 then
            self.casting = false
            -- 施法结束：执行卡牌效果
            if self.onCastEnd then
                self.onCastEnd()
            end
            if self.onCardUsed and self.castCard then
                self.onCardUsed(self.castCard)
            end
            self.castCard = nil
        end
        return  -- 施法期间不消耗/不刷新
    end

    -- 自动消耗：每秒从左侧消耗1张
    if #self.hand > 0 then
        self.consumeTimer = self.consumeTimer - dt
        if self.consumeTimer <= 0 then
            self.consumeTimer = CONSUME_INTERVAL
            -- 移除最左边的卡牌
            table.remove(self.hand, 1)
            log:Write(LOG_INFO, "[CardSystem] Auto-consumed, remaining=" .. #self.hand)
        end
    end

    -- 刷新倒计时
    self.refreshTimer = self.refreshTimer - dt
    if self.refreshTimer <= 0 then
        self:_refreshHand()
        self.refreshTimer = REFRESH_INTERVAL
        self.consumeTimer = CONSUME_INTERVAL  -- 重置消耗计时
        log:Write(LOG_INFO, "[CardSystem] Refreshed hand, count=" .. #self.hand)
    end
end

-- 使用指定索引的卡牌（UI按钮点击）
function CardSystem:useCard(index)
    if self.casting then return false end
    if index < 1 or index > #self.hand then return false end

    local card = self.hand[index]
    table.remove(self.hand, index)

    -- 进入施法状态
    self.casting = true
    self.castTimer = CAST_DURATION
    self.castCard = card

    if self.onCastStart then
        self.onCastStart()
    end

    log:Write(LOG_INFO, "[CardSystem] Using card: " .. TYPE_NAMES[card.type] .. " " .. card.elementData.icon)
    return true
end

-- 获取当前手牌
function CardSystem:getHand()
    return self.hand
end

-- 获取刷新倒计时
function CardSystem:getRefreshTimer()
    return self.refreshTimer
end

-- 获取刷新间隔
function CardSystem:getRefreshInterval()
    return REFRESH_INTERVAL
end

-- 是否正在施法
function CardSystem:isCasting()
    return self.casting
end

-- 刷新手牌（随机生成满手卡牌）
function CardSystem:_refreshHand()
    self.hand = {}
    local elements = { "fire", "water", "thunder", "wind", "ice" }
    local types = { CardSystem.TYPE_ATTACK, CardSystem.TYPE_DEFENSE, CardSystem.TYPE_SUPPORT }

    for i = 1, MAX_HAND do
        local elem = elements[math.random(1, #elements)]
        local cardType = types[math.random(1, #types)]
        table.insert(self.hand, {
            type = cardType,
            element = elem,
            elementData = CardSystem.ELEMENTS[elem],
            typeName = TYPE_NAMES[cardType],
            typeIcon = TYPE_ICONS[cardType],
        })
    end
end

-- 检查卡牌是否克制目标属性
function CardSystem:isCounter(cardElement, targetElement)
    local counters = COUNTER_TABLE[cardElement]
    if counters then
        for _, e in ipairs(counters) do
            if e == targetElement then return true end
        end
    end
    return false
end

-- 重置
function CardSystem:reset()
    self.refreshTimer = REFRESH_INTERVAL
    self.consumeTimer = CONSUME_INTERVAL
    self.casting = false
    self.castTimer = 0
    self.castCard = nil
    self:_refreshHand()
end

return CardSystem
