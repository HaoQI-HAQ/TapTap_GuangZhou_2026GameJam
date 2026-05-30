-- CardUI 类：卡牌UI显示
-- 位置：右下角攻击按钮上方（类似战双帕米什三消球）
CardUI = {}
CardUI.__index = CardUI

local MAX_HAND = 5             -- 手牌上限
local CARD_SIZE = 45           -- 单张卡牌尺寸
local CARD_GAP = 5             -- 卡牌间距
local CARD_AREA_PADDING = 5    -- 卡牌区域内边距

function CardUI:new(cardSystem)
    local self = setmetatable({}, CardUI)
    self.cardSystem = cardSystem
    self.cardButtons = {}       -- 卡牌按钮引用
    self.container = nil        -- 主容器
    self.castOverlay = nil      -- 施法遮罩
    self:_setup()
    return self
end

function CardUI:_setup()
    local uiRoot = ui.root

    -- 主容器：右下角，攻击按钮上方
    self.container = UIElement:new()
    uiRoot:AddChild(self.container)
    self.container:SetAlignment(HA_RIGHT, VA_BOTTOM)
    -- 5张卡牌横排 + 间距 + padding
    local totalWidth = MAX_HAND * CARD_SIZE + (MAX_HAND - 1) * CARD_GAP + CARD_AREA_PADDING * 2
    local totalHeight = CARD_SIZE + CARD_AREA_PADDING * 2
    self.container:SetSize(totalWidth, totalHeight)
    -- 位置：攻击按钮上方（攻击按钮bottom=-80, height=70）
    self.container:SetPosition(-10, -155)
    self.container.priority = 100

    -- 卡牌按钮槽位（5个）
    for i = 1, MAX_HAND do
        local cardBtn = Button:new()
        self.container:AddChild(cardBtn)
        cardBtn:SetStyleAuto()
        cardBtn:SetSize(CARD_SIZE, CARD_SIZE)
        local x = CARD_AREA_PADDING + (i - 1) * (CARD_SIZE + CARD_GAP)
        cardBtn:SetPosition(x, CARD_AREA_PADDING)
        cardBtn:SetOpacity(0.9)

        -- 卡牌内容文本（属性图标+类型）
        local cardText = Text:new()
        cardBtn:AddChild(cardText)
        cardText:SetStyleAuto()
        cardText:SetFontSize(11)
        cardText:SetAlignment(HA_CENTER, VA_CENTER)
        cardText.text = ""

        self.cardButtons[i] = {
            button = cardBtn,
            text = cardText,
            index = i,
        }

        -- 绑定点击事件
        local idx = i
        SubscribeToEvent(cardBtn, "Released", "HandleCardBtn" .. idx)
    end

    -- 施法遮罩（施法时覆盖卡牌区域）
    self.castOverlay = UIElement:new()
    self.container:AddChild(self.castOverlay)
    self.castOverlay:SetSize(totalWidth, totalHeight)
    self.castOverlay.priority = 200

    local castBg = BorderImage:new()
    self.castOverlay:AddChild(castBg)
    castBg:SetSize(totalWidth, totalHeight)
    castBg.color = Color(1.0, 1.0, 0.3, 0.3)

    local castText = Text:new()
    self.castOverlay:AddChild(castText)
    castText:SetStyleAuto()
    castText.text = "施法中..."
    castText:SetFontSize(14)
    castText:SetAlignment(HA_CENTER, VA_CENTER)
    castText.color = Color(1.0, 1.0, 0.0, 1.0)

    self.castOverlay.visible = false

    log:Write(LOG_INFO, "[CardUI] Created")
end

-- 每帧更新UI显示
function CardUI:update(dt)
    local hand = self.cardSystem:getHand()

    -- 更新卡牌按钮（右对齐：消失后剩余卡牌靠右显示）
    local offset = (MAX_HAND - #hand) * (CARD_SIZE + CARD_GAP)
    for i = 1, MAX_HAND do
        local slot = self.cardButtons[i]
        if i <= #hand then
            local card = hand[i]
            slot.button.visible = true
            -- 位置：加上偏移量，使卡牌靠右
            local x = CARD_AREA_PADDING + offset + (i - 1) * (CARD_SIZE + CARD_GAP)
            slot.button:SetPosition(x, CARD_AREA_PADDING)
            -- 显示：属性图标 + 类型缩写
            slot.text.text = card.elementData.icon .. "\n" .. card.typeName
            -- 按钮颜色跟随属性
            slot.button.color = card.elementData.color
        else
            -- 空槽位：直接隐藏
            slot.button.visible = false
        end
    end

    -- 施法遮罩
    self.castOverlay.visible = self.cardSystem:isCasting()
end

-- 显示/隐藏
function CardUI:show()
    self.container.visible = true
end

function CardUI:hide()
    self.container.visible = false
end

return CardUI
