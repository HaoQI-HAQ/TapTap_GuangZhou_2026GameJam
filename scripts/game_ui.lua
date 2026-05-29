-- GameUI 类
GameUI = {}
GameUI.__index = GameUI

function GameUI:new(inputManager)
    local self = setmetatable({}, GameUI)
    self.inputManager = inputManager
    self:_createButtons()
    return self
end

function GameUI:_createButtons()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    -- 按钮容器，锚定在左下角
    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_LEFT, VA_BOTTOM)
    container:SetSize(380, 120)
    container:SetPosition(20, -20)

    -- 左按钮
    self.btnLeft = self:_createButton(container, "<", 0, 10)
    -- 右按钮
    self.btnRight = self:_createButton(container, ">", 120, 10)
    -- 跳跃按钮（右下角）
    self.btnJump = self:_createJumpButton()

    -- 绑定事件
    SubscribeToEvent(self.btnLeft, "Pressed", "HandleUILeftPressed")
    SubscribeToEvent(self.btnLeft, "Released", "HandleUILeftReleased")
    SubscribeToEvent(self.btnRight, "Pressed", "HandleUIRightPressed")
    SubscribeToEvent(self.btnRight, "Released", "HandleUIRightReleased")
    SubscribeToEvent(self.btnJump, "Pressed", "HandleUIJumpPressed")
    SubscribeToEvent(self.btnJump, "Released", "HandleUIJumpReleased")

    log:Write(LOG_INFO, "[GameUI] Buttons created (left/right/jump)")
end

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

function GameUI:_createJumpButton()
    local uiRoot = ui.root

    -- 跳跃按钮容器，锚定在右下角
    local jumpContainer = UIElement:new()
    uiRoot:AddChild(jumpContainer)
    jumpContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    jumpContainer:SetSize(120, 120)
    jumpContainer:SetPosition(-20, -20)

    local btn = self:_createButton(jumpContainer, "^", 10, 10)
    return btn
end

return GameUI
