-- MenuOverlay 游戏开始界面（全屏UI覆盖层）
MenuOverlay = {}
MenuOverlay.__index = MenuOverlay

function MenuOverlay:new()
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, MenuOverlay)
    self.visible = true
    self.panel = nil
    self:_create()
    return self
end

function MenuOverlay:_create()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    -- 全屏遮罩面板
    self.panel = UIElement:new()
    uiRoot:AddChild(self.panel)
    self.panel:SetSize(graphics.width, graphics.height)
    self.panel:SetAlignment(HA_CENTER, VA_CENTER)
    self.panel:SetPriority(1000)

    -- 纯白不透明背景
    local bg = Window:new()
    self.panel:AddChild(bg)
    bg:SetStyleAuto()
    bg:SetSize(graphics.width, graphics.height)
    bg:SetPosition(0, 0)
    bg:SetColor(Color(1.0, 1.0, 1.0, 1.0))
    bg:SetOpacity(1.0)
    bg.movable = false
    bg.resizable = false

    -- 游戏标题
    local title = Text:new()
    self.panel:AddChild(title)
    title:SetStyleAuto()
    title.text = "My Platformer"
    title:SetFontSize(42)
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, -80)
    title.color = Color(0.1, 0.1, 0.2, 1.0)

    -- 开始按钮
    local btnStart = Button:new()
    self.panel:AddChild(btnStart)
    btnStart:SetStyleAuto()
    btnStart:SetSize(200, 60)
    btnStart:SetAlignment(HA_CENTER, VA_CENTER)
    btnStart:SetPosition(0, 20)
    btnStart:SetOpacity(0.9)

    local startText = Text:new()
    btnStart:AddChild(startText)
    startText:SetStyleAuto()
    startText.text = "START"
    startText:SetFontSize(28)
    startText:SetAlignment(HA_CENTER, VA_CENTER)

    -- 退出按钮
    local btnExit = Button:new()
    self.panel:AddChild(btnExit)
    btnExit:SetStyleAuto()
    btnExit:SetSize(200, 60)
    btnExit:SetAlignment(HA_CENTER, VA_CENTER)
    btnExit:SetPosition(0, 100)
    btnExit:SetOpacity(0.9)

    local exitText = Text:new()
    btnExit:AddChild(exitText)
    exitText:SetStyleAuto()
    exitText.text = "EXIT"
    exitText:SetFontSize(28)
    exitText:SetAlignment(HA_CENTER, VA_CENTER)

    -- 绑定事件
    SubscribeToEvent(btnStart, "Released", "HandleMenuStart")
    SubscribeToEvent(btnExit, "Released", "HandleMenuExit")

    self.panel.visible = true
    log:Write(LOG_INFO, "[MenuOverlay] Created")
end

function MenuOverlay:show()
    self.visible = true
    self.panel.visible = true
end

function MenuOverlay:hide()
    self.visible = false
    self.panel.visible = false
end

function MenuOverlay:isVisible()
    return self.visible
end

return MenuOverlay
