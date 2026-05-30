-- GameUI 类
GameUI = {}
GameUI.__index = GameUI

local COUNTDOWN_TIME = 5.0  -- 倒计时秒数

function GameUI:new(inputManager, player)
    local self = setmetatable({}, GameUI)
    self.inputManager = inputManager
    self.player = player
    self.hpIcons = {}
    self.elements = {}  -- 追踪所有UI元素用于显示/隐藏
    self.countdown = COUNTDOWN_TIME
    self.countdownText = nil
    self:_setup()
    return self
end

function GameUI:_setup()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    self:_createHpUI()
    self:_createCountdownUI()
    self:_createMoveButtons()
    self:_createJumpButton()
    self:_createAttackButton()
    self:_createBackButton()

    -- 默认隐藏（等菜单点击START后再显示）
    self:hide()

    log:Write(LOG_INFO, "[GameUI] Created with HP display, buttons and BACK")
end

-- 左上角血量显示
function GameUI:_createHpUI()
    local uiRoot = ui.root

    self.hpContainer = UIElement:new()
    uiRoot:AddChild(self.hpContainer)
    self.hpContainer:SetAlignment(HA_LEFT, VA_TOP)
    self.hpContainer:SetPosition(20, 20)
    self.hpContainer:SetSize(300, 50)
    table.insert(self.elements, self.hpContainer)

    for i = 1, self.player:getMaxHp() do
        local hpIcon = Text:new()
        self.hpContainer:AddChild(hpIcon)
        hpIcon:SetStyleAuto()
        hpIcon.text = "♥"
        hpIcon:SetFontSize(28)
        hpIcon.color = Color(1.0, 0.2, 0.2, 1.0)
        hpIcon:SetPosition((i - 1) * 40, 5)
        self.hpIcons[i] = hpIcon
    end
end

-- 中上位置倒计时UI
function GameUI:_createCountdownUI()
    local uiRoot = ui.root

    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_CENTER, VA_TOP)
    container:SetSize(100, 50)
    container:SetPosition(0, 20)
    table.insert(self.elements, container)

    self.countdownText = Text:new()
    container:AddChild(self.countdownText)
    self.countdownText:SetStyleAuto()
    self.countdownText.text = "5"
    self.countdownText:SetFontSize(32)
    self.countdownText:SetAlignment(HA_CENTER, VA_TOP)
    self.countdownText.color = Color(0.1, 0.1, 0.1, 1.0)
end

-- 左下角移动按钮
function GameUI:_createMoveButtons()
    local uiRoot = ui.root

    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_LEFT, VA_BOTTOM)
    container:SetSize(130, 70)
    container:SetPosition(20, -20)
    table.insert(self.elements, container)

    self.btnLeft = self:_createButton(container, "<", 0, 10)
    self.btnRight = self:_createButton(container, ">", 60, 10)

    SubscribeToEvent(self.btnLeft, "Pressed", "HandleUILeftPressed")
    SubscribeToEvent(self.btnLeft, "Released", "HandleUILeftReleased")
    SubscribeToEvent(self.btnRight, "Pressed", "HandleUIRightPressed")
    SubscribeToEvent(self.btnRight, "Released", "HandleUIRightReleased")
end

-- 右下角跳跃按钮
function GameUI:_createJumpButton()
    local uiRoot = ui.root

    local jumpContainer = UIElement:new()
    uiRoot:AddChild(jumpContainer)
    jumpContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    jumpContainer:SetSize(70, 70)
    jumpContainer:SetPosition(-20, -20)
    table.insert(self.elements, jumpContainer)

    self.btnJump = self:_createButton(jumpContainer, "^", 10, 10)

    SubscribeToEvent(self.btnJump, "Pressed", "HandleUIJumpPressed")
    SubscribeToEvent(self.btnJump, "Released", "HandleUIJumpReleased")
end

-- 右下角攻击按钮（跳跃按钮上方）
function GameUI:_createAttackButton()
    local uiRoot = ui.root

    local attackContainer = UIElement:new()
    uiRoot:AddChild(attackContainer)
    attackContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    attackContainer:SetSize(70, 70)
    attackContainer:SetPosition(-20, -80)
    table.insert(self.elements, attackContainer)

    self.btnAttack = self:_createButton(attackContainer, "A", 10, 10)

    SubscribeToEvent(self.btnAttack, "Pressed", "HandleUIAttackPressed")
    SubscribeToEvent(self.btnAttack, "Released", "HandleUIAttackReleased")
end

-- 右上角BACK按钮
function GameUI:_createBackButton()
    local uiRoot = ui.root

    local backContainer = UIElement:new()
    uiRoot:AddChild(backContainer)
    backContainer:SetAlignment(HA_RIGHT, VA_TOP)
    backContainer:SetSize(80, 40)
    backContainer:SetPosition(-20, 20)
    table.insert(self.elements, backContainer)

    local btnBack = Button:new()
    backContainer:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(80, 40)
    btnBack:SetPosition(0, 0)
    btnBack:SetOpacity(0.8)

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "BACK"
    backText:SetFontSize(18)
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandleBackToMenu")
end

-- 显示游戏UI
function GameUI:show()
    for _, elem in ipairs(self.elements) do
        elem.visible = true
    end
end

-- 隐藏游戏UI
function GameUI:hide()
    for _, elem in ipairs(self.elements) do
        elem.visible = false
    end
end

-- 每帧更新UI（血量+倒计时）
function GameUI:update(dt)
    -- 更新血量
    local currentHp = self.player:getHp()
    for i = 1, self.player:getMaxHp() do
        if i <= currentHp then
            self.hpIcons[i].color = Color(1.0, 0.2, 0.2, 1.0)
            self.hpIcons[i].text = "♥"
        else
            self.hpIcons[i].color = Color(0.3, 0.3, 0.3, 0.5)
            self.hpIcons[i].text = "♡"
        end
    end

    -- 更新倒计时
    self.countdown = self.countdown - dt
    if self.countdown <= 0 then
        self.countdown = COUNTDOWN_TIME
    end
    self.countdownText.text = tostring(math.ceil(self.countdown))
end

-- 重置倒计时
function GameUI:resetCountdown()
    self.countdown = COUNTDOWN_TIME
end

-- 通用按钮创建
function GameUI:_createButton(parent, label, x, y)
    local btn = Button:new()
    parent:AddChild(btn)
    btn:SetStyleAuto()
    btn:SetSize(50, 50)
    btn:SetPosition(x, y)
    btn:SetOpacity(0.7)

    local text = Text:new()
    btn:AddChild(text)
    text:SetStyleAuto()
    text.text = label
    text:SetFontSize(16)
    text:SetAlignment(HA_CENTER, VA_CENTER)

    return btn
end

return GameUI
