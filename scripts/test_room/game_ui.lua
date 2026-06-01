-- GameUI 类
local ScreenUtils = require("scripts/screen_utils")

GameUI = {}
GameUI.__index = GameUI

local COUNTDOWN_TIME = 5.0  -- 倒计时秒数

function GameUI:new(inputManager, player)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, GameUI)
    self.inputManager = inputManager
    self.player = player
    self.hpIcons = {}
    self.elements = {}  -- 追踪所有UI元素用于显示/隐藏
    self.countdown = COUNTDOWN_TIME
    self.countdownText = nil
    self.cardSystem = nil  -- 可选：绑定卡牌系统后用卡牌倒计时
    self:_setup()
    return self
end

function GameUI:_setup()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    -- 缓存缩放函数
    self._S = ScreenUtils.s

    self:_createHpUI()
    self:_createCountdownUI()
    self:_createMoveButtons()
    self:_createJumpButton()
    self:_createAttackButton()

    self:_createSensesStatusUI()

    -- 默认隐藏（等菜单点击START后再显示）
    self:hide()

    log:Write(LOG_INFO, "[GameUI] Created with HP display, buttons and BACK")
end

-- 左上角血量显示
function GameUI:_createHpUI()
    local S = self._S
    local uiRoot = ui.root

    self.hpContainer = UIElement:new()
    uiRoot:AddChild(self.hpContainer)
    self.hpContainer:SetAlignment(HA_LEFT, VA_TOP)
    self.hpContainer:SetPosition(S(20), S(20))
    self.hpContainer:SetSize(S(300), S(50))
    table.insert(self.elements, self.hpContainer)

    for i = 1, self.player:getMaxHp() do
        local hpIcon = Text:new()
        self.hpContainer:AddChild(hpIcon)
        hpIcon:SetStyleAuto()
        hpIcon.text = "♥"
        hpIcon:SetFontSize(S(28))
        hpIcon.color = Color(1.0, 0.2, 0.2, 1.0)
        hpIcon:SetPosition((i - 1) * S(40), S(5))
        self.hpIcons[i] = hpIcon
    end
end

-- 中上位置倒计时UI
function GameUI:_createCountdownUI()
    local S = self._S
    local uiRoot = ui.root

    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_CENTER, VA_TOP)
    container:SetSize(S(100), S(50))
    container:SetPosition(0, S(20))
    table.insert(self.elements, container)

    self.countdownText = Text:new()
    container:AddChild(self.countdownText)
    self.countdownText:SetStyleAuto()
    self.countdownText.text = "5"
    self.countdownText:SetFontSize(S(32))
    self.countdownText:SetAlignment(HA_CENTER, VA_TOP)
    self.countdownText.color = Color(0.1, 0.1, 0.1, 1.0)
end

-- 左下角摇杆
function GameUI:_createMoveButtons()
    local S = self._S
    local uiRoot = ui.root

    local joystickSize = S(120)
    local thumbSize = S(50)
    local deadZone = S(10)  -- 死区像素

    -- 摇杆底座容器
    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_LEFT, VA_BOTTOM)
    container:SetSize(joystickSize, joystickSize)
    container:SetPosition(S(20), S(-20))
    table.insert(self.elements, container)

    -- 底座背景（使用图片）
    local base = BorderImage:new()
    container:AddChild(base)
    base:SetSize(joystickSize, joystickSize)
    base:SetPosition(0, 0)
    local baseTex = cache:GetResource("Texture2D", "image/UI/joystick_base.png")
    if baseTex then
        base:SetTexture(baseTex)
        base:SetImageRect(IntRect(0, 0, baseTex:GetWidth(), baseTex:GetHeight()))
        base.color = Color(1.0, 1.0, 1.0, 0.8)
    else
        base.color = Color(0.3, 0.3, 0.3, 0.5)
    end

    -- 摇杆拇指（可拖动）
    local thumb = BorderImage:new()
    container:AddChild(thumb)
    thumb:SetSize(thumbSize, thumbSize)
    -- 初始居中
    local centerX = (joystickSize - thumbSize) / 2
    local centerY = (joystickSize - thumbSize) / 2
    thumb:SetPosition(centerX, centerY)
    thumb.color = Color(1.0, 1.0, 1.0, 0.6)

    self.joystickContainer = container
    self.joystickThumb = thumb
    self.joystickSize = joystickSize
    self.joystickThumbSize = thumbSize
    self.joystickCenterX = centerX
    self.joystickCenterY = centerY
    self.joystickDeadZone = deadZone
    self.joystickActive = false
    self.joystickMaxDist = (joystickSize - thumbSize) / 2
end

-- 右下角跳跃按钮（使用图片）
function GameUI:_createJumpButton()
    local S = self._S
    local uiRoot = ui.root

    local btnSize = S(70)
    local jumpContainer = UIElement:new()
    uiRoot:AddChild(jumpContainer)
    jumpContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    jumpContainer:SetSize(btnSize, btnSize)
    jumpContainer:SetPosition(S(-20), S(-20))
    table.insert(self.elements, jumpContainer)

    self.btnJump = Button:new()
    jumpContainer:AddChild(self.btnJump)
    self.btnJump:SetSize(btnSize, btnSize)
    self.btnJump:SetPosition(0, 0)
    self.btnJump:SetStyle("", nil)  -- 清除默认样式，避免按下时出现白边
    self.btnJump:SetFocusMode(FM_NOTFOCUSABLE)
    self.btnJump.color = Color(0, 0, 0, 0)

    local jumpImg = BorderImage:new()
    self.btnJump:AddChild(jumpImg)
    jumpImg:SetSize(btnSize, btnSize)
    jumpImg:SetAlignment(HA_CENTER, VA_CENTER)
    local jumpTex = cache:GetResource("Texture2D", "image/UI/btn_jump.png")
    if jumpTex then
        jumpImg:SetTexture(jumpTex)
        jumpImg:SetImageRect(IntRect(0, 0, jumpTex:GetWidth(), jumpTex:GetHeight()))
        jumpImg.color = Color(1.0, 1.0, 1.0, 0.9)
    end

    SubscribeToEvent(self.btnJump, "Pressed", "HandleUIJumpPressed")
    SubscribeToEvent(self.btnJump, "Released", "HandleUIJumpReleased")
end

-- 右下角攻击按钮（跳跃按钮左侧，水平并排）
function GameUI:_createAttackButton()
    local S = self._S
    local uiRoot = ui.root

    local btnSize = S(70)
    local attackContainer = UIElement:new()
    uiRoot:AddChild(attackContainer)
    attackContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    attackContainer:SetSize(btnSize, btnSize)
    attackContainer:SetPosition(S(-100), S(-20))
    table.insert(self.elements, attackContainer)

    self.btnAttack = Button:new()
    attackContainer:AddChild(self.btnAttack)
    self.btnAttack:SetSize(btnSize, btnSize)
    self.btnAttack:SetPosition(0, 0)
    self.btnAttack:SetStyle("", nil)  -- 清除默认样式，避免按下时出现白边
    self.btnAttack:SetFocusMode(FM_NOTFOCUSABLE)
    self.btnAttack.color = Color(0, 0, 0, 0)

    local atkImg = BorderImage:new()
    self.btnAttack:AddChild(atkImg)
    atkImg:SetSize(btnSize, btnSize)
    atkImg:SetAlignment(HA_CENTER, VA_CENTER)
    local atkTex = cache:GetResource("Texture2D", "image/UI/btn_attack.png")
    if atkTex then
        atkImg:SetTexture(atkTex)
        atkImg:SetImageRect(IntRect(0, 0, atkTex:GetWidth(), atkTex:GetHeight()))
        atkImg.color = Color(1.0, 1.0, 1.0, 0.9)
    end

    SubscribeToEvent(self.btnAttack, "Pressed", "HandleUIAttackPressed")
    SubscribeToEvent(self.btnAttack, "Released", "HandleUIAttackReleased")
end



-- 右上角五感状态图标（使用图片素材）
function GameUI:_createSensesStatusUI()
    local S = self._S
    local uiRoot = ui.root

    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_RIGHT, VA_TOP)
    container:SetSize(S(280), S(50))
    container:SetPosition(S(-10), S(15))
    table.insert(self.elements, container)

    -- 五感定义：key, 正常图片路径, 异常图片路径
    local sensesDef = {
        { key = "hearing", normalTex = "image/TheFiveSenses/normal/听觉_正常.png", abnormalTex = "image/TheFiveSenses/abnormal/听觉_异常.png" },
        { key = "touch",   normalTex = "image/TheFiveSenses/normal/触觉_正常.png", abnormalTex = "image/TheFiveSenses/abnormal/触觉_异常.png" },
        { key = "taste",   normalTex = "image/TheFiveSenses/normal/味觉_正常.png", abnormalTex = "image/TheFiveSenses/abnormal/味觉_异常.png" },
        { key = "smell",   normalTex = "image/TheFiveSenses/normal/嗅觉_正常.png", abnormalTex = "image/TheFiveSenses/abnormal/嗅觉_异常.png" },
        { key = "vision",  normalTex = "image/TheFiveSenses/normal/视觉_正常.png", abnormalTex = "image/TheFiveSenses/abnormal/视觉_异常.png" },
    }

    self.senseIcons = {}
    self.sensesDef = sensesDef

    for i, def in ipairs(sensesDef) do
        local icon = BorderImage:new()
        container:AddChild(icon)
        icon:SetSize(S(44), S(44))
        icon:SetPosition((i - 1) * S(52), S(3))
        -- 设置正常状态图片
        local normalTexture = cache:GetResource("Texture2D", def.normalTex)
        if normalTexture then
            icon:SetTexture(normalTexture)
            icon:SetImageRect(IntRect(0, 0, normalTexture:GetWidth(), normalTexture:GetHeight()))
        end
        icon.color = Color(1.0, 1.0, 1.0, 1.0)

        self.senseIcons[i] = {
            icon = icon,
            key = def.key,
            normalTex = def.normalTex,
            abnormalTex = def.abnormalTex,
        }
    end
end

-- 更新五感状态图标（正常/异常切换图片）
function GameUI:updateSensesIcons()
    if not self.sensesSystem or not self.senseIcons then return end

    for _, iconData in ipairs(self.senseIcons) do
        local texPath
        if self.sensesSystem:isDeprived(iconData.key) then
            texPath = iconData.abnormalTex
        else
            texPath = iconData.normalTex
        end
        local tex = cache:GetResource("Texture2D", texPath)
        if tex then
            iconData.icon:SetTexture(tex)
            iconData.icon:SetImageRect(IntRect(0, 0, tex:GetWidth(), tex:GetHeight()))
        end
        iconData.icon.color = Color(1.0, 1.0, 1.0, 1.0)
    end
end

--- 销毁所有UI元素（从 ui.root 移除），重新开始前调用
function GameUI:destroy()
    for _, elem in ipairs(self.elements) do
        elem:Remove()
    end
    self.elements = {}
    self.hpIcons = {}
    self.countdownText = nil
    self.joystickContainer = nil
    self.joystickThumb = nil
    log:Write(LOG_INFO, "[GameUI] Destroyed")
end

-- 显示游戏UI
function GameUI:show()
    for _, elem in ipairs(self.elements) do
        elem.visible = true
    end
end

-- 设置关卡显示（test_room模式无关卡文字，stub实现）
function GameUI:setLevel(level, maxLevel)
    -- test_room 不显示关卡信息
end

-- 隐藏游戏UI
function GameUI:hide()
    for _, elem in ipairs(self.elements) do
        elem.visible = false
    end
end

-- 辅助：判断触摸的UI元素是否属于摇杆容器
function GameUI:_isTouchOnJoystick(touchedElem)
    if not touchedElem or not self.joystickContainer then return false end
    local elem = touchedElem
    while elem do
        if elem == self.joystickContainer then return true end
        elem = elem.parent
    end
    return false
end

-- 摇杆输入处理（每帧调用）- 支持多点触控
-- 修复：在手机端(DPR>1)，touch.position与element.screenPosition可能不在同一坐标空间
function GameUI:_updateJoystick()
    if not self.joystickContainer or not self.joystickContainer.visible then
        return
    end

    -- 使用实际容器尺寸
    local actualSize = self.joystickContainer.size
    local joystickW = actualSize.x > 0 and actualSize.x or self.joystickSize
    local joystickH = actualSize.y > 0 and actualSize.y or self.joystickSize

    -- 获取摇杆容器的屏幕中心位置（在 ui.root 坐标空间）
    local containerPos = self.joystickContainer.screenPosition
    local cx = containerPos.x + joystickW / 2
    local cy = containerPos.y + joystickH / 2
    local hitRadius = joystickW / 2

    -- 坐标空间修正：touch.position 在 graphics 像素空间，screenPosition 在 ui.root 空间
    local gfxW = graphics:GetWidth()
    local gfxH = graphics:GetHeight()
    local uiW = ui.root.width
    local uiH = ui.root.height
    local scaleX = (gfxW > 0 and uiW > 0) and (uiW / gfxW) or 1.0
    local scaleY = (gfxH > 0 and uiH > 0) and (uiH / gfxH) or 1.0

    local numTouches = input.numTouches
    local foundTouch = false
    local touchX, touchY = 0, 0

    if numTouches > 0 then
        for i = 0, numTouches - 1 do
            local touch = input:GetTouch(i)
            if touch then
                local tx = touch.position.x * scaleX
                local ty = touch.position.y * scaleY

                -- 已激活：追踪同一个触摸点
                if self.joystickActive and self.joystickTouchID == touch.touchID then
                    foundTouch = true
                    touchX = tx; touchY = ty
                    break
                end

                -- 未激活：检测新触摸是否命中摇杆
                if not self.joystickActive then
                    local onJoystick = self:_isTouchOnJoystick(touch.touchedElement)
                    if not onJoystick then
                        local dx = tx - cx
                        local dy = ty - cy
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist <= hitRadius then
                            onJoystick = true
                        end
                    end
                    if onJoystick then
                        foundTouch = true
                        touchX = tx; touchY = ty
                        self.joystickTouchID = touch.touchID
                        break
                    end
                end
            end
        end
    end

    -- 鼠标兼容（桌面端 或 手机端触摸模拟为鼠标）
    if not foundTouch and input:GetMouseButtonDown(MOUSEB_LEFT) then
        local mousePos = input.mousePosition
        local mx = mousePos.x * scaleX
        local my = mousePos.y * scaleY
        local dx = mx - cx
        local dy = my - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        if self.joystickActive or dist <= hitRadius then
            foundTouch = true
            touchX = mx; touchY = my
        end
    end

    if foundTouch then
        self.joystickActive = true
        local dx = touchX - cx
        local dy = touchY - cy
        local dist = math.sqrt(dx * dx + dy * dy)

        -- 限制拇指在圆形范围内
        local maxDist = self.joystickMaxDist
        if dist > maxDist then
            dx = dx * maxDist / dist
            dy = dy * maxDist / dist
        end

        -- 更新拇指位置
        self.joystickThumb:SetPosition(self.joystickCenterX + dx, self.joystickCenterY + dy)

        -- 根据水平偏移设置左右输入（只关心X轴）
        if dx < -self.joystickDeadZone then
            self.inputManager:setTouchAction(InputManager.ACTION_LEFT, true)
            self.inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
        elseif dx > self.joystickDeadZone then
            self.inputManager:setTouchAction(InputManager.ACTION_RIGHT, true)
            self.inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
        else
            self.inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
            self.inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
        end
    else
        -- 松开：复位摇杆
        if self.joystickActive then
            self.joystickActive = false
            self.joystickTouchID = nil
            self.joystickThumb:SetPosition(self.joystickCenterX, self.joystickCenterY)
            self.inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
            self.inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
        end
    end
end

-- 每帧更新UI（血量+倒计时）
function GameUI:update(dt)
    -- 更新摇杆
    self:_updateJoystick()

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

    -- 更新倒计时（如果绑定了卡牌系统则同步其倒计时）
    if self.cardSystem then
        self.countdown = self.cardSystem:getRefreshTimer()
    else
        self.countdown = self.countdown - dt
        if self.countdown <= 0 then
            self.countdown = COUNTDOWN_TIME
        end
    end
    -- 嗅觉剥夺：倒计时数字异常跳动
    local displayVal = self.countdown
    if self.sensesSystem then
        displayVal = self.sensesSystem:getDisplayCountdown(self.countdown)
    end
    self.countdownText.text = tostring(math.ceil(displayVal))

    -- 更新五感状态图标
    self:updateSensesIcons()
end

-- 重置倒计时
function GameUI:resetCountdown()
    self.countdown = COUNTDOWN_TIME
end

-- 通用按钮创建
function GameUI:_createButton(parent, label, x, y)
    local btn = Button:new()
    parent:AddChild(btn)
    btn:SetSize(50, 50)
    btn:SetPosition(x, y)
    btn:SetOpacity(0.5)

    local text = Text:new()
    btn:AddChild(text)
    text:SetStyleAuto()
    text.text = label
    text:SetFontSize(16)
    text:SetAlignment(HA_CENTER, VA_CENTER)

    return btn
end

return GameUI
