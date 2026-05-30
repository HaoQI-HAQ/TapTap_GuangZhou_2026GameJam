-- ============================================================================
-- CardSystem 模块：5秒倒计时 + 手牌管理 + 属性克制
-- ============================================================================

local CONFIG = require("config")

local CardSystem = {}
CardSystem.__index = CardSystem

-- 卡牌类型
CardSystem.TYPE_ATTACK  = "attack"   -- 属性攻击卡
CardSystem.TYPE_NONE_ATK = "none_atk" -- 无属性攻击(固定2点)
CardSystem.TYPE_MATTER  = "matter"   -- 物质(固定3点穿透)

function CardSystem:new()
    local self = setmetatable({}, CardSystem)

    self.hand = {}              -- 当前手牌 [{element, type, baseDamage}]
    self.countdown = CONFIG.CountdownTime
    self.consumeTimer = 0       -- 每秒消耗计时
    self.roundCount = 0         -- 轮次计数

    -- 初始发牌
    self:_dealHand()

    return self
end

function CardSystem:update(dt)
    -- 倒计时
    self.countdown = self.countdown - dt

    -- 每秒消耗一张(从右侧)
    self.consumeTimer = self.consumeTimer + dt
    if self.consumeTimer >= CONFIG.CardConsumeInterval then
        self.consumeTimer = self.consumeTimer - CONFIG.CardConsumeInterval
        if #self.hand > 0 then
            table.remove(self.hand, #self.hand)
        end
    end

    -- 倒计时归零 → 刷新手牌
    if self.countdown <= 0 then
        self.countdown = CONFIG.CountdownTime
        self.consumeTimer = 0
        self.roundCount = self.roundCount + 1
        self:_dealHand()
    end
end

-- 使用一张卡牌(从左侧取)，返回卡牌信息或nil
function CardSystem:useCard(index)
    index = index or 1
    if index < 1 or index > #self.hand then return nil end
    local card = table.remove(self.hand, index)
    return card
end

-- 获取手牌
function CardSystem:getHand()
    return self.hand
end

function CardSystem:getCountdown()
    return self.countdown
end

function CardSystem:getCountdownMax()
    return CONFIG.CountdownTime
end

-- 计算卡牌对目标的伤害
function CardSystem:calculateDamage(card, targetElement)
    if not card then return 0 end

    -- 无属性攻击卡
    if card.type == CardSystem.TYPE_NONE_ATK then
        return 2
    end

    -- 物质卡(穿透)
    if card.type == CardSystem.TYPE_MATTER then
        return 3
    end

    -- 属性攻击卡
    if card.type == CardSystem.TYPE_ATTACK then
        local relation = self:_getRelation(card.element, targetElement)
        if relation == "counter" then
            -- 克制 = 暴击(怪物剩1滴血，由外部处理)
            return -1  -- 特殊标记: 暴击
        elseif relation == "resisted" then
            -- 被克制: 伤害减半
            return math.max(1, math.floor(card.baseDamage * 0.5))
        else
            -- 非克制: 正常伤害
            return card.baseDamage
        end
    end

    return card.baseDamage or 1
end

-- 判断属性关系
function CardSystem:_getRelation(attackElement, defenseElement)
    if not attackElement or not defenseElement then return "neutral" end

    local counters = CONFIG.ElementCounter[attackElement]
    if counters then
        for _, e in ipairs(counters) do
            if e == defenseElement then
                return "counter"  -- 攻击方克制防御方
            end
        end
    end

    -- 反查: 防御方是否克制攻击方
    local defCounters = CONFIG.ElementCounter[defenseElement]
    if defCounters then
        for _, e in ipairs(defCounters) do
            if e == attackElement then
                return "resisted"  -- 被克制
            end
        end
    end

    return "neutral"
end

-- 内部: 随机发牌
function CardSystem:_dealHand()
    self.hand = {}
    for i = 1, CONFIG.CardHandSize do
        local card = self:_generateCard()
        self.hand[#self.hand + 1] = card
    end
end

function CardSystem:_generateCard()
    local roll = math.random(1, 100)

    if roll <= 70 then
        -- 70% 属性攻击卡
        local element = CONFIG.Elements[math.random(1, #CONFIG.Elements)]
        return {
            type = CardSystem.TYPE_ATTACK,
            element = element,
            baseDamage = math.random(2, 4),
        }
    elseif roll <= 85 then
        -- 15% 无属性攻击
        return {
            type = CardSystem.TYPE_NONE_ATK,
            element = nil,
            baseDamage = 2,
        }
    else
        -- 15% 物质卡
        return {
            type = CardSystem.TYPE_MATTER,
            element = nil,
            baseDamage = 3,
        }
    end
end

return CardSystem
