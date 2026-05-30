-- GameUI 类
GameUI = {}
GameUI.__index = GameUI

function GameUI:new(inputManager, player)
    local self = setmetatable({}, GameUI)
    self.inputManager = inputManager
    self.player = player
    self.hpIcons = {}
    self:_setup()
    return self
end

function GameUI:_setup()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    self:_createHpUI()
    self:_createMoveButtons()
    self:_createJumpButton()

    log:Write(LOG_INFO, "[GameUI] Created with HP display and buttons")
end

-- 左上角血量显示
function GameUI:_createHpUI()
    local uiRoot = ui.root

    -- 血量容器，锚定左上角
    self.hpContainer = UIElement:new()
    uiRoot:AddChild(self.hpContainer)
    self.hpContainer:SetAlignment(HA_LEFT, VA_TOP)
    self.hpContainer:SetPosition(20, 20)
    self.hpContainer:SetSize(300, 50)

    -- 创建血滴图标
    for i = 1, self.player:getMaxHp() do
        local hpIcon = Text:new()
        self.hpContainer:AddChild(hpIcon)
        hpIcon:SetStyleAuto()
        hpIcon.text = "♥"
        hpIcon:SetFontSize(28)
        hpIcon.color = Color(1.0, 0.2, 0.2, 1.0) -- 红色
        hpIcon:SetPosition((i - 1) * 40, 5)
        self.hpIcons[i] = hpIcon
    end
end

-- 左下角移动按钮
function GameUI:_createMoveButtons()
    local uiRoot = ui.root

    -- 按钮容器，锚定左下角
    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_LEFT, VA_BOTTOM)
    container:SetSize(260, 120)
    container:SetPosition(20, -20)

    -- 左按钮
    self.btnLeft = self:_createButton(container, "<", 0, 10)
    -- 右按钮
    self.btnRight = self:_createButton(container, ">", 120, 10)

    -- 绑定事件
    SubscribeToEvent(self.btnLeft, "Pressed", "HandleUILeftPressed")
    SubscribeToEvent(self.btnLeft, "Released", "HandleUILeftReleased")
    SubscribeToEvent(self.btnRight, "Pressed", "HandleUIRightPressed")
    SubscribeToEvent(self.btnRight, "Released", "HandleUIRightReleased")
end

-- 右下角跳跃按钮
function GameUI:_createJumpButton()
    local uiRoot = ui.root

    -- 跳跃按钮容器，锚定右下角
    local jumpContainer = UIElement:new()
    uiRoot:AddChild(jumpContainer)
    jumpContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    jumpContainer:SetSize(120, 120)
    jumpContainer:SetPosition(-20, -20)

    self.btnJump = self:_createButton(jumpContainer, "^", 10, 10)

    SubscribeToEvent(self.btnJump, "Pressed", "HandleUIJumpPressed")
    SubscribeToEvent(self.btnJump, "Released", "HandleUIJumpReleased")
end

-- 每帧更新血量UI
function GameUI:update()
    local currentHp = self.player:getHp()
    for i = 1, self.player:getMaxHp() do
        if i <= currentHp then
            self.hpIcons[i].color = Color(1.0, 0.2, 0.2, 1.0) -- 红色：有血
            self.hpIcons[i].text = "♥"
        else
            self.hpIcons[i].color = Color(0.3, 0.3, 0.3, 0.5) -- 灰色：无血
            self.hpIcons[i].text = "♡"
        end
    end
end

-- 通用按钮创建
function GameUI:_createButton(parent, label, x, y)
    local btn = Button:new()
    parent:AddChild(btn)
    btn:SetStyleAuto()
    btn:SetSize(100, 100)
    btn:SetPosition(x, y)
    btn:SetOpacity(0.7)

    local text = Text:new()
    btn:AddChild(text)
    text:SetStyleAuto()
    text.text = label
    text:SetFontSize(32)
    text:SetAlignment(HA_CENTER, VA_CENTER)

    return btn
end

return GameUI
