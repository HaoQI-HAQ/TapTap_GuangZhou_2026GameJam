-- MenuOverlay 游戏开始界面（全屏UI覆盖层）
-- 两层菜单：标题页(START) → 模式选择页(测试房间/普通模式/无尽模式/返回)
MenuOverlay = {}
MenuOverlay.__index = MenuOverlay

function MenuOverlay:new()
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, MenuOverlay)
    self.visible = true
    self.panel = nil
    self.titleLayer = nil    -- 标题层
    self.selectLayer = nil   -- 模式选择层
    self.state = "title"     -- "title" / "select"
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
    self.panel:SetAlignment(HA_LEFT, VA_TOP)
    self.panel:SetPosition(0, 0)
    self.panel:SetPriority(1000)

    -- 全屏背景图片 (BorderImage 直接拉伸填满屏幕)
    local bg = BorderImage:new()
    self.panel:AddChild(bg)
    bg:SetSize(graphics.width, graphics.height)
    bg:SetPosition(0, 0)
    local bgTex = cache:GetResource("Texture2D", "image/UI/start_bg.png")
    if bgTex then
        bg:SetTexture(bgTex)
        local texW = bgTex:GetWidth()
        local texH = bgTex:GetHeight()
        bg:SetImageRect(IntRect(0, 0, texW, texH))
        bg.color = Color(1.0, 1.0, 1.0, 1.0)
        log:Write(LOG_INFO, "[MenuOverlay] BG loaded: " .. texW .. "x" .. texH .. " -> fullscreen " .. graphics.width .. "x" .. graphics.height)
    else
        bg.color = Color(0.0, 0.0, 0.0, 1.0)
        log:Write(LOG_WARNING, "[MenuOverlay] BG texture not found, fallback black")
    end

    -- ========== 标题层（底部居中按钮） ==========
    self.titleLayer = UIElement:new()
    self.panel:AddChild(self.titleLayer)
    self.titleLayer:SetSize(graphics.width, graphics.height)
    self.titleLayer:SetPosition(0, 0)

    -- 底部按钮容器（水平排列两个按钮）
    local sw = graphics.width
    local sh = graphics.height
    local btnW = 180
    local btnH = 50
    local gap = 40  -- 两按钮间距

    -- "开始旅途"按钮
    local btnStart = Button:new()
    self.titleLayer:AddChild(btnStart)
    btnStart:SetStyleAuto()
    btnStart:SetSize(btnW, btnH)
    btnStart:SetAlignment(HA_CENTER, VA_BOTTOM)
    btnStart:SetPosition(-math.floor((btnW + gap) / 2), -40)
    btnStart:SetOpacity(0.85)

    local startText = Text:new()
    btnStart:AddChild(startText)
    startText:SetStyleAuto()
    startText.text = "开始旅途"
    startText:SetFontSize(22)
    startText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnStart, "Released", "HandleMenuShowSelect")

    -- "退出游戏"按钮
    local btnExit = Button:new()
    self.titleLayer:AddChild(btnExit)
    btnExit:SetStyleAuto()
    btnExit:SetSize(btnW, btnH)
    btnExit:SetAlignment(HA_CENTER, VA_BOTTOM)
    btnExit:SetPosition(math.floor((btnW + gap) / 2), -40)
    btnExit:SetOpacity(0.85)

    local exitText = Text:new()
    btnExit:AddChild(exitText)
    exitText:SetStyleAuto()
    exitText.text = "退出游戏"
    exitText:SetFontSize(22)
    exitText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnExit, "Released", "HandleMenuExit")

    self.titleLayer.visible = true

    -- ========== 模式选择层 ==========
    self.selectLayer = UIElement:new()
    self.panel:AddChild(self.selectLayer)
    self.selectLayer:SetSize(graphics.width, graphics.height)
    self.selectLayer:SetPosition(0, 0)

    -- 选择模式标题（已移除）

    -- 测试房间
    local btnTest = Button:new()
    self.selectLayer:AddChild(btnTest)
    btnTest:SetStyleAuto()
    btnTest:SetSize(220, 50)
    btnTest:SetAlignment(HA_CENTER, VA_CENTER)
    btnTest:SetPosition(0, -50)

    local testText = Text:new()
    btnTest:AddChild(testText)
    testText:SetStyleAuto()
    testText.text = "测试房间"
    testText:SetFontSize(22)
    testText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnTest, "Released", "HandleModeTest")

    -- 普通模式
    local btnNormal = Button:new()
    self.selectLayer:AddChild(btnNormal)
    btnNormal:SetStyleAuto()
    btnNormal:SetSize(220, 50)
    btnNormal:SetAlignment(HA_CENTER, VA_CENTER)
    btnNormal:SetPosition(0, 10)

    local normalText = Text:new()
    btnNormal:AddChild(normalText)
    normalText:SetStyleAuto()
    normalText.text = "普通模式"
    normalText:SetFontSize(22)
    normalText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnNormal, "Released", "HandleModeNormal")

    -- 无尽模式
    local btnEndless = Button:new()
    self.selectLayer:AddChild(btnEndless)
    btnEndless:SetStyleAuto()
    btnEndless:SetSize(220, 50)
    btnEndless:SetAlignment(HA_CENTER, VA_CENTER)
    btnEndless:SetPosition(0, 70)

    local endlessText = Text:new()
    btnEndless:AddChild(endlessText)
    endlessText:SetStyleAuto()
    endlessText.text = "无尽模式"
    endlessText:SetFontSize(22)
    endlessText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnEndless, "Released", "HandleModeEndless")

    -- 返回
    local btnBack = Button:new()
    self.selectLayer:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(220, 50)
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, 130)

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "返回"
    backText:SetFontSize(22)
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandleModeBack")

    self.selectLayer.visible = false

    self.panel.visible = true
    log:Write(LOG_INFO, "[MenuOverlay] Created (title + mode select)")
end

function MenuOverlay:showTitle()
    self.state = "title"
    self.titleLayer.visible = true
    self.selectLayer.visible = false
end

function MenuOverlay:showSelect()
    self.state = "select"
    self.titleLayer.visible = false
    self.selectLayer.visible = true
end

function MenuOverlay:show()
    self.visible = true
    self.panel.visible = true
    self:showTitle()
end

function MenuOverlay:hide()
    self.visible = false
    self.panel.visible = false
end

function MenuOverlay:isVisible()
    return self.visible
end

return MenuOverlay
