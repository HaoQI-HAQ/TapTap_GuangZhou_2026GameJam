-- 卡牌系统核心逻辑（适配 main.lua 接口）
local CardData = require("scripts/test_room/card_data")

CardSystem = {}
CardSystem.__index = CardSystem

-- 常量
local REFRESH_INTERVAL = 5.0  -- 每5秒刷新
local HAND_SIZE = 5           -- 每轮5张
local CAST_TIME = 0.3         -- 施法时间
local DISAPPEAR_INTERVAL = 1.0 -- 每秒消失一张

function CardSystem:new()
    local o = setmetatable({}, CardSystem)

    -- 手牌状态
    o.hand = {}            -- 当前手牌 [{cardId, visible}]
    o.handSize = 0         -- 当前可见手牌数

    -- 计时器
    o.roundTimer = 0       -- 当轮已用时间
    o.roundActive = false  -- 当轮是否激活
    o.countdown = REFRESH_INTERVAL  -- 显示用倒计时

    -- 施法状态
    o.casting = false
    o.castTimer = 0
    o.castCardId = nil
    o.castSlot = 0

    -- 冷却追踪 {cardId = remainingCD}
    o.cooldowns = {}

    -- 使用次数限制追踪 {cardId = usedCount}
    o.useCounts = {}

    -- 全局效果
    o.globalEffects = {}   -- [{type, duration, timer, ...}]

    -- 回调
    o.onHandChanged = nil    -- function(hand)
    o.onCountdownChanged = nil -- function(seconds)
    o.onCardUsed = nil       -- function(card) 卡牌使用时
    o.onCastStart = nil      -- function() 施法开始（锁玩家移动）
    o.onCastEnd = nil        -- function() 施法结束

    -- 立即开始第一轮
    o:_startNewRound()

    return o
end

--- 获取刷新倒计时（供 game_ui 同步顶部倒计时）
function CardSystem:getRefreshTimer()
    return self.countdown
end

--- 每帧更新
function CardSystem:update(dt)
    -- 更新冷却
    for id, cd in pairs(self.cooldowns) do
        self.cooldowns[id] = cd - dt
        if self.cooldowns[id] <= 0 then
            self.cooldowns[id] = nil
        end
    end

    -- 更新全局效果
    self:_updateGlobalEffects(dt)

    -- 更新施法
    if self.casting then
        self.castTimer = self.castTimer - dt
        if self.castTimer <= 0 then
            self:_executeCast()
            self.casting = false
            self.castCardId = nil
            self.castSlot = 0
            if self.onCastEnd then
                self.onCastEnd()
            end
        end
        return  -- 施法中不更新手牌计时
    end

    -- 更新当轮计时
    if self.roundActive then
        self.roundTimer = self.roundTimer + dt
        local elapsed = self.roundTimer

        -- 每秒消失一张卡（从第1秒开始）
        local shouldVisible = HAND_SIZE - math.floor(elapsed / DISAPPEAR_INTERVAL)
        shouldVisible = math.max(0, shouldVisible)

        if shouldVisible < self.handSize then
            self:_removeRandomCard(self.handSize - shouldVisible)
        end

        -- 更新倒计时显示
        self.countdown = math.max(0, REFRESH_INTERVAL - elapsed)
        if self.onCountdownChanged then
            self.onCountdownChanged(self.countdown)
        end

        -- 当轮结束 → 重新刷新
        if elapsed >= REFRESH_INTERVAL then
            self:_startNewRound()
        end
    end
end

--- 使用指定槽位的卡牌
---@param slotIndex number 1-5
---@return boolean 是否成功
function CardSystem:useCard(slotIndex)
    if self.casting then return false end
    if slotIndex < 1 or slotIndex > #self.hand then return false end

    local slot = self.hand[slotIndex]
    if not slot or not slot.visible then return false end

    local card = CardData.CARDS[slot.cardId]
    if not card then return false end

    -- 检查冷却
    if self.cooldowns[slot.cardId] then return false end

    -- 检查使用次数限制
    if card.maxUse then
        local used = self.useCounts[slot.cardId] or 0
        if used >= card.maxUse then return false end
    end

    -- 开始施法
    self.casting = true
    self.castTimer = CAST_TIME
    self.castCardId = slot.cardId
    self.castSlot = slotIndex

    -- 立即隐藏该卡牌
    slot.visible = false
    self.handSize = self.handSize - 1
    if self.onHandChanged then
        self.onHandChanged(self.hand)
    end

    -- 通知施法开始（锁玩家移动）
    if self.onCastStart then
        self.onCastStart()
    end

    return true
end

--- 获取当前倒计时秒数（取整，用于伤害计算）
function CardSystem:getCountdown()
    return math.ceil(self.countdown)
end

--- 计算卡牌对目标的伤害
---@param cardId string
---@param targetElement string 目标属性
---@param targetHp number 目标当前HP
---@return number damage, boolean isCounter
function CardSystem:calculateDamage(cardId, targetElement, targetHp)
    local card = CardData.CARDS[cardId]
    if not card then return 0, false end

    local element = card.element

    -- 无属性/特殊卡牌：固定伤害
    if element == "matter" then
        return 3, false  -- 物质：固定3点
    elseif element == "none" then
        return 2, false  -- 无属性：固定2点
    elseif element == "time" or element == "slow" or element == "space" then
        return 0, false  -- 控制类：无直接伤害
    end

    -- 属性克制判断
    if CardData.isCounter(element, targetElement) then
        -- 克制：伤害 = HP - 1（直接扣到1滴血）
        local dmg = math.max(1, (targetHp or 1) - 1)
        return dmg, true
    end

    -- 非克制：伤害 = 当前剩余倒计时秒数
    local countdown = self:getCountdown()
    return math.max(1, countdown), false
end

--- 属性克制判断（供 main.lua 外部调用）
function CardSystem:isCounter(cardElement, targetElement)
    return CardData.isCounter(cardElement, targetElement)
end

--- 获取减速倍率（全局时间减缓效果）
function CardSystem:getEnemySpeedMultiplier()
    for _, eff in ipairs(self.globalEffects) do
        if eff.type == "freeze" then
            return 0  -- 完全冻结
        elseif eff.type == "slow" then
            return 1.0 - eff.percent
        end
    end
    return 1.0
end

--- 敌人是否被冻结
function CardSystem:isEnemyFrozen()
    for _, eff in ipairs(self.globalEffects) do
        if eff.type == "freeze" then
            return true
        end
    end
    return false
end

--- 获取卡牌数据（供 card_skills 使用）
function CardSystem:getCardData(cardId)
    return CardData.CARDS[cardId]
end

--- 获取卡牌属性颜色信息
function CardSystem:getElementInfo(element)
    return CardData.ELEMENT_COLORS[element]
end

-- ============ 内部方法 ============

function CardSystem:_startNewRound()
    self.roundTimer = 0
    self.roundActive = true
    self.hand = {}
    self.handSize = HAND_SIZE

    -- 从卡池随机抽取5张
    for i = 1, HAND_SIZE do
        local poolIndex = math.random(1, #CardData.POOL)
        local cardId = CardData.POOL[poolIndex]
        self.hand[i] = { cardId = cardId, visible = true }
    end

    self.countdown = REFRESH_INTERVAL
    if self.onHandChanged then
        self.onHandChanged(self.hand)
    end
    if self.onCountdownChanged then
        self.onCountdownChanged(self.countdown)
    end
end

function CardSystem:_removeRandomCard(count)
    for c = 1, count do
        local visibleSlots = {}
        for i, slot in ipairs(self.hand) do
            if slot.visible then
                table.insert(visibleSlots, i)
            end
        end
        if #visibleSlots == 0 then break end

        local pick = visibleSlots[math.random(1, #visibleSlots)]
        self.hand[pick].visible = false
        self.handSize = self.handSize - 1
    end

    if self.onHandChanged then
        self.onHandChanged(self.hand)
    end
end

function CardSystem:_executeCast()
    if not self.castCardId then return end

    local cardId = self.castCardId
    local card = CardData.CARDS[cardId]
    if not card then return end

    -- 记录使用次数
    if card.maxUse then
        self.useCounts[cardId] = (self.useCounts[cardId] or 0) + 1
    end

    -- 设置冷却
    if card.cooldown and card.cooldown > 0 then
        self.cooldowns[cardId] = card.cooldown
    end

    -- 处理全局效果（时间停止/减缓）
    if card.freezeAll then
        self:addGlobalEffect("freeze", card.duration, {})
    elseif card.skillType == "buff" and card.slowPercent then
        self:addGlobalEffect("slow", card.duration, { percent = card.slowPercent })
    end

    -- 触发卡牌使用回调（由 main.lua → card_skills 处理实际效果）
    if self.onCardUsed then
        self.onCardUsed(card)
    end
end

function CardSystem:_updateGlobalEffects(dt)
    local i = 1
    while i <= #self.globalEffects do
        local eff = self.globalEffects[i]
        eff.timer = eff.timer + dt
        if eff.timer >= eff.duration then
            table.remove(self.globalEffects, i)
        else
            i = i + 1
        end
    end
end

--- 添加全局效果
function CardSystem:addGlobalEffect(effectType, duration, params)
    local eff = {
        type = effectType,
        duration = duration,
        timer = 0,
    }
    if params then
        for k, v in pairs(params) do
            eff[k] = v
        end
    end
    table.insert(self.globalEffects, eff)
end

--- 重置（重新开始游戏时调用）
function CardSystem:reset()
    self.hand = {}
    self.handSize = 0
    self.roundTimer = 0
    self.roundActive = false
    self.casting = false
    self.castTimer = 0
    self.castCardId = nil
    self.castSlot = 0
    self.cooldowns = {}
    self.useCounts = {}
    self.globalEffects = {}
    self:_startNewRound()
end

return CardSystem
