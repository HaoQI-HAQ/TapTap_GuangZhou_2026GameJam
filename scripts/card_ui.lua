-- 卡牌UI模块 - 右下角5张手牌（在平A按钮上方）
local CardData = require("scripts/card_data")
local ScreenUtils = require("scripts/screen_utils")

CardUI = {}
CardUI.__index = CardUI

-- UI 尺寸常量（运行时缩放）
local CARD_WIDTH = 73
local CARD_HEIGHT = 101
local CARD_SPACING = 4
local CARD_RIGHT_MARGIN = 20
local CARD_BOTTOM_OFFSET = 160  -- 紧贴攻击按钮(bottom80+height70=150)上方

function CardUI:new(cardSystem)
    local o = setmetatable({}, CardUI)
    o.cardSystem = cardSystem
    o.cardSlots = {}   -- UI元素：5个卡牌槽位
    o.container = nil
    o.visible = false

    o:_setup()

    -- 注册手牌变化回调
    cardSystem.onHandChanged = function(hand)
        o:_refreshCards(hand)
    end

    return o
end

function CardUI:_setup()
    local S = ScreenUtils.s
    local uiRoot = ui.root

    -- 缓存缩放后的尺寸
    self._cw = S(CARD_WIDTH)
    self._ch = S(CARD_HEIGHT)
    self._cs = S(CARD_SPACING)

    -- 卡牌容器（右下角，在攻击按钮上方）
    local totalWidth = self._cw * 5 + self._cs * 4
    self.container = UIElement:new()
    uiRoot:AddChild(self.container)
    self.container:SetSize(totalWidth, self._ch)
    self.container:SetAlignment(HA_RIGHT, VA_BOTTOM)
    self.container:SetPosition(-S(CARD_RIGHT_MARGIN), -S(CARD_BOTTOM_OFFSET))
    self.container.priority = 100

    -- 创建5个卡牌槽位
    for i = 1, 5 do
        local slot = self:_createCardSlot(i)
        self.cardSlots[i] = slot
    end

    self.container.visible = false
    log:Write(LOG_INFO, "[CardUI] Created 5 card slots (bottom-right)")
end

function CardUI:_createCardSlot(index)
    local cw, ch, cs = self._cw, self._ch, self._cs
    local x = (index - 1) * (cw + cs)

    -- 卡牌按钮（清除默认灰色纹理样式）
    local btn = Button:new()
    self.container:AddChild(btn)
    btn:SetStyle("none")
    btn.color = Color(0, 0, 0, 0)
    btn:SetSize(cw, ch)
    btn:SetPosition(x, 0)
    btn:SetOpacity(1.0)

    -- 卡牌图片（使用card文件夹下的图片）
    local cardImage = BorderImage:new()
    btn:AddChild(cardImage)
    cardImage:SetSize(cw, ch)
    cardImage:SetPosition(0, 0)
    cardImage.color = Color(1.0, 1.0, 1.0, 1.0)

    -- 属性颜色条（底部薄条，标示元素）
    local elementBar = BorderImage:new()
    btn:AddChild(elementBar)
    elementBar:SetSize(cw, ScreenUtils.s(4))
    elementBar:SetPosition(0, ch - ScreenUtils.s(4))
    elementBar.color = Color(0.5, 0.5, 0.5, 1.0)

    -- 订阅按钮点击事件
    local eventName = "HandleCardBtn" .. index
    SubscribeToEvent(btn, "Released", eventName)

    return {
        btn = btn,
        cardImage = cardImage,
        elementBar = elementBar,
        cardId = nil,
        active = false,
    }
end

--- 刷新卡牌显示（可见卡牌往右靠拢，UI槽位按顺序复用）
function CardUI:_refreshCards(hand)
    local cw, ch, cs = self._cw, self._ch, self._cs

    -- 收集所有可见卡牌（保留原始hand索引用于useCard）
    local visibleCards = {}
    for i = 1, 5 do
        local handSlot = hand[i]
        if handSlot and handSlot.visible then
            local card = CardData.CARDS[handSlot.cardId]
            if card then
                table.insert(visibleCards, { handIndex = i, cardId = handSlot.cardId, card = card })
            end
        end
    end

    -- 计算靠右排列的起始X
    local totalWidth = cw * 5 + cs * 4
    local visibleCount = #visibleCards
    local groupWidth = visibleCount * cw + math.max(0, visibleCount - 1) * cs
    local startX = totalWidth - groupWidth  -- 靠右对齐

    -- 先隐藏所有槽位并清空映射
    for i = 1, 5 do
        self.cardSlots[i].btn.visible = false
        self.cardSlots[i].active = false
        self.cardSlots[i].cardId = nil
        self.cardSlots[i].handIndex = nil
    end

    -- 按顺序将可见卡牌映射到 UI 槽位 1,2,3...（不跳号）
    -- 这样 HandleCardBtn1 对应视觉上第1张，HandleCardBtn2 对应第2张
    for idx, info in ipairs(visibleCards) do
        local slot = self.cardSlots[idx]  -- 用顺序idx，不用原始handIndex
        local x = startX + (idx - 1) * (cw + cs)

        slot.btn.visible = true
        slot.btn:SetPosition(x, 0)
        slot.cardId = info.cardId
        slot.handIndex = info.handIndex  -- 记录对应的hand真实索引
        slot.active = true

        -- 加载卡牌图片
        if info.card.image and info.card.image ~= "" then
            local tex = cache:GetResource("Texture2D", info.card.image)
            if tex then
                slot.cardImage:SetTexture(tex)
                slot.cardImage:SetFullImageRect()
                slot.cardImage.color = Color(1.0, 1.0, 1.0, 1.0)
            end
        end

        -- 设置属性颜色条
        local elemInfo = CardData.ELEMENT_COLORS[info.card.element]
        if elemInfo then
            slot.elementBar.color = elemInfo.color
        else
            slot.elementBar.color = Color(0.5, 0.5, 0.5, 1.0)
        end

        -- 冷却中的卡牌显示更透明（控制图片透明度，不改btn）
        if self.cardSystem.cooldowns[info.cardId] then
            slot.cardImage:SetOpacity(0.3)
        else
            slot.cardImage:SetOpacity(1.0)
        end
    end
end

--- 获取当前可见手牌数量
---@return number
function CardUI:getHandCount()
    local count = 0
    for _, slot in ipairs(self.cardSlots) do
        if slot.active then
            count = count + 1
        end
    end
    return count
end

--- 获取 UI 槽位对应的真实 hand 索引
---@param uiSlot number 1-5 的UI槽位号
---@return number|nil 真实hand索引，无效则返回nil
function CardUI:getHandIndex(uiSlot)
    local slot = self.cardSlots[uiSlot]
    if slot and slot.active and slot.handIndex then
        return slot.handIndex
    end
    return nil
end

--- 每帧更新
function CardUI:update(dt)
    -- 未来可加入卡牌消失/出现动画
end

--- 销毁卡牌UI元素（从 ui.root 移除），重新开始前调用
function CardUI:destroy()
    if self.container then
        self.container:Remove()
        self.container = nil
    end
    self.cardSlots = {}
    log:Write(LOG_INFO, "[CardUI] Destroyed")
end

--- 显示卡牌UI
function CardUI:show()
    self.visible = true
    if self.container then
        self.container.visible = true
    end
    -- 刷新当前手牌
    if self.cardSystem and self.cardSystem.hand then
        self:_refreshCards(self.cardSystem.hand)
    end
end

--- 隐藏卡牌UI
function CardUI:hide()
    self.visible = false
    if self.container then
        self.container.visible = false
    end
end

return CardUI
