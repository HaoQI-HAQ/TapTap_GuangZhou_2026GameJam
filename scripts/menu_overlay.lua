---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- MenuOverlay 游戏开始界面（全屏UI覆盖层）- PixelForge 像素风主题
-- 两层菜单：标题页(START) → 模式选择页(测试房间/普通模式/无尽模式/返回)
local ScreenUtils = require("scripts/screen_utils")

MenuOverlay = {}
MenuOverlay.__index = MenuOverlay

-- PixelForge 配色常量
local PX_BG         = Color(0.059, 0.059, 0.137, 0.85)   -- #0F0F23 深色背景（半透明）
local PX_SURFACE    = Color(0.106, 0.106, 0.227, 1.0)    -- #1B1B3A 面板
local PX_PRIMARY    = Color(0.129, 0.741, 0.682, 1.0)    -- #21BDAE 主色（青色）
local PX_SECONDARY  = Color(0.424, 0.361, 0.906, 1.0)    -- #6C5CE7 副色（紫色）
local PX_TEXT       = Color(0.941, 0.941, 0.941, 1.0)    -- #F0F0F0 文本白
local PX_TEXT_SEC   = Color(0.627, 0.627, 0.753, 0.7)    -- #A0A0C0 次要文本
local PX_BORDER     = Color(0.227, 0.227, 0.416, 1.0)    -- #3A3A6A 边框
local PX_BTN_HOVER  = Color(0.239, 0.816, 0.757, 1.0)    -- #3DD0C1 按钮hover

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

--- 创建像素风按钮（统一样式）
function MenuOverlay:_createPixelButton(parent, w, h, text, fontSize)
    local S = ScreenUtils.s
    local pixelFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")

    local btn = Button:new()
    parent:AddChild(btn)
    btn:SetStyle("none")
    btn:SetSize(w, h)
    btn.color = PX_SURFACE
    btn:SetOpacity(0.95)

    -- 2px 像素边框效果（用一个略大的底层模拟）
    local border = BorderImage:new()
    btn:AddChild(border)
    border:SetSize(w, h)
    border:SetPosition(0, 0)
    border.color = PX_BORDER
    border.priority = -1

    -- 内部填充（比边框小2px营造边框感）
    local inner = BorderImage:new()
    btn:AddChild(inner)
    inner:SetSize(w - S(4), h - S(4))
    inner:SetPosition(S(2), S(2))
    inner.color = PX_SURFACE

    -- 文字标签
    local label = Text:new()
    btn:AddChild(label)
    if pixelFont then
        label:SetFont(pixelFont, fontSize)
    else
        label:SetFontSize(fontSize)
    end
    label.text = text
    label.color = PX_TEXT
    label:SetAlignment(HA_CENTER, VA_CENTER)

    return btn
end

function MenuOverlay:_create()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    -- 像素字体预加载
    local pixelFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans.ttf")
    local pixelFontBold = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")

    -- 全屏遮罩面板
    self.panel = UIElement:new()
    uiRoot:AddChild(self.panel)
    self.panel:SetSize(sw, sh)
    self.panel:SetAlignment(HA_LEFT, VA_TOP)
    self.panel:SetPosition(0, 0)
    self.panel:SetPriority(1000)

    -- 全屏背景图片 (BorderImage 直接拉伸填满屏幕)
    local bg = BorderImage:new()
    self.panel:AddChild(bg)
    bg:SetSize(sw, sh)
    bg:SetPosition(0, 0)
    local bgTex = cache:GetResource("Texture2D", "image/UI/start_bg.png")
    if bgTex then
        bg:SetTexture(bgTex)
        local texW = bgTex:GetWidth()
        local texH = bgTex:GetHeight()
        bg:SetImageRect(IntRect(0, 0, texW, texH))
        bg.color = Color(1.0, 1.0, 1.0, 1.0)
        log:Write(LOG_INFO, "[MenuOverlay] BG loaded: " .. texW .. "x" .. texH .. " -> fullscreen " .. sw .. "x" .. sh)
    else
        bg.color = Color(0.059, 0.059, 0.137, 1.0)  -- PX_BG fallback
        log:Write(LOG_WARNING, "[MenuOverlay] BG texture not found, fallback pixel dark")
    end

    -- ========== 标题层（底部居中按钮） ==========
    self.titleLayer = UIElement:new()
    self.panel:AddChild(self.titleLayer)
    self.titleLayer:SetSize(sw, sh)
    self.titleLayer:SetPosition(0, 0)

    -- 底部按钮容器（水平排列两个按钮）
    local btnW = S(200)
    local btnH = S(56)
    local gap = S(40)  -- 两按钮间距
    local bottomMargin = S(80)  -- 底部留白

    -- "开始旅途"按钮（像素风）
    local btnStart = self:_createPixelButton(self.titleLayer, btnW, btnH, "开始旅途", S(24))
    btnStart:SetAlignment(HA_CENTER, VA_BOTTOM)
    btnStart:SetPosition(-math.floor((btnW + gap) / 2), -bottomMargin)

    SubscribeToEvent(btnStart, "Released", "HandleMenuShowSelect")

    -- "退出游戏"按钮（像素风）
    local btnExit = self:_createPixelButton(self.titleLayer, btnW, btnH, "退出游戏", S(24))
    btnExit:SetAlignment(HA_CENTER, VA_BOTTOM)
    btnExit:SetPosition(math.floor((btnW + gap) / 2), -bottomMargin)

    SubscribeToEvent(btnExit, "Released", "HandleMenuExit")

    -- 版本号（左下角，像素字体）
    local versionText = Text:new()
    self.titleLayer:AddChild(versionText)
    if pixelFont then
        versionText:SetFont(pixelFont, S(14))
    else
        versionText:SetStyleAuto()
        versionText:SetFontSize(S(14))
    end
    versionText.text = "v1.1.9"
    versionText:SetAlignment(HA_LEFT, VA_BOTTOM)
    versionText:SetPosition(S(12), -S(10))
    versionText.color = PX_TEXT_SEC

    self.titleLayer.visible = true

    -- ========== 模式选择层 ==========
    self.selectLayer = UIElement:new()
    self.panel:AddChild(self.selectLayer)
    self.selectLayer:SetSize(sw, sh)
    self.selectLayer:SetPosition(0, 0)

    -- 半透明暗背景遮罩（像素风深色面板感）
    local selectBg = BorderImage:new()
    self.selectLayer:AddChild(selectBg)
    selectBg:SetSize(S(280), S(320))
    selectBg:SetAlignment(HA_CENTER, VA_CENTER)
    selectBg:SetPosition(0, 0)
    selectBg.color = PX_BG

    -- 模式选择标题
    local selectTitle = Text:new()
    self.selectLayer:AddChild(selectTitle)
    if pixelFontBold then
        selectTitle:SetFont(pixelFontBold, S(26))
    else
        selectTitle:SetStyleAuto()
        selectTitle:SetFontSize(S(26))
    end
    selectTitle.text = "选择模式"
    selectTitle.color = PX_PRIMARY
    selectTitle:SetAlignment(HA_CENTER, VA_CENTER)
    selectTitle:SetPosition(0, S(-120))

    -- 测试房间
    local btnTest = self:_createPixelButton(self.selectLayer, S(220), S(50), "测试房间", S(22))
    btnTest:SetAlignment(HA_CENTER, VA_CENTER)
    btnTest:SetPosition(0, S(-50))
    SubscribeToEvent(btnTest, "Released", "HandleModeTest")

    -- 普通模式
    local btnNormal = self:_createPixelButton(self.selectLayer, S(220), S(50), "普通模式", S(22))
    btnNormal:SetAlignment(HA_CENTER, VA_CENTER)
    btnNormal:SetPosition(0, S(10))
    SubscribeToEvent(btnNormal, "Released", "HandleModeNormal")

    -- 无尽模式
    local btnEndless = self:_createPixelButton(self.selectLayer, S(220), S(50), "无尽模式", S(22))
    btnEndless:SetAlignment(HA_CENTER, VA_CENTER)
    btnEndless:SetPosition(0, S(70))
    SubscribeToEvent(btnEndless, "Released", "HandleModeEndless")

    -- 返回
    local btnBack = self:_createPixelButton(self.selectLayer, S(220), S(50), "返回", S(22))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(130))
    SubscribeToEvent(btnBack, "Released", "HandleModeBack")

    self.selectLayer.visible = false

    self.panel.visible = true
    log:Write(LOG_INFO, "[MenuOverlay] Created (PixelForge theme)")
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
