---@diagnostic disable: undefined-global
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

    self:_createHpUI()
    self:_createCountdownUI()
    self:_createMoveButtons()
    self:_createJumpButton()
    self:_createAttackButton()

    self:_createSensesStatusUI()

    -- 应用编辑器保存的UI布局配置
    self:_applyEditorLayout()

    -- 默认隐藏（等菜单点击START后再显示）
    self:hide()

    log:Write(LOG_INFO, "[GameUI] Created with HP display, buttons and BACK")
end

-- 左上角血量显示
function GameUI:_createHpUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s

    self.hpContainer = UIElement:new()
    uiRoot:AddChild(self.hpContainer)
    self.hpContainer:SetAlignment(HA_LEFT, VA_TOP)
    self.hpContainer:SetPosition(S(20), S(20))
    self.hpContainer:SetSize(S(300), S(50))
    table.insert(self.elements, self.hpContainer)

    -- 显式加载字体，确保手机端能正确渲染Unicode符号
    local hpFont = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")

    for i = 1, self.player:getMaxHp() do
        local hpIcon = Text:new()
        self.hpContainer:AddChild(hpIcon)
        hpIcon.text = "♥"
        if hpFont then
            hpIcon:SetFont(hpFont, S(28))
        else
            hpIcon:SetStyleAuto()
            hpIcon:SetFontSize(S(28))
        end
        hpIcon.color = Color(1.0, 0.2, 0.2, 1.0)
        hpIcon:SetPosition((i - 1) * S(40), S(5))
        self.hpIcons[i] = hpIcon
    end
end

-- 中上位置倒计时UI
function GameUI:_createCountdownUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s

    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_CENTER, VA_TOP)
    container:SetSize(S(100), S(50))
    container:SetPosition(0, S(20))
    table.insert(self.elements, container)
    self.countdownContainer = container

    self.countdownText = Text:new()
    container:AddChild(self.countdownText)
    self.countdownText.text = "5"
    local cdFont = cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")
    if cdFont then
        self.countdownText:SetFont(cdFont, S(32))
    else
        self.countdownText:SetStyleAuto()
        self.countdownText:SetFontSize(S(32))
    end
    self.countdownText:SetAlignment(HA_CENTER, VA_TOP)
    self.countdownText.color = Color(0.1, 0.1, 0.1, 1.0)
end

-- 左下角摇杆
function GameUI:_createMoveButtons()
    local uiRoot = ui.root
    local U = ScreenUtils.ui

    local joystickSize = U(150)
    local thumbSize = U(56)
    local deadZone = U(12)  -- 死区像素

    -- 摇杆底座容器
    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_LEFT, VA_BOTTOM)
    container:SetSize(joystickSize, joystickSize)
    container:SetPosition(U(24), U(-30))
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
    local uiRoot = ui.root
    local U = ScreenUtils.ui

    local btnSize = U(88)
    local jumpContainer = UIElement:new()
    uiRoot:AddChild(jumpContainer)
    jumpContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    jumpContainer:SetSize(btnSize, btnSize)
    jumpContainer:SetPosition(U(-24), U(-30))
    table.insert(self.elements, jumpContainer)
    self.jumpContainer = jumpContainer

    self.btnJump = Button:new()
    jumpContainer:AddChild(self.btnJump)
    self.btnJump:SetSize(btnSize, btnSize)
    self.btnJump:SetPosition(0, 0)
    self.btnJump:SetStyle("", nil)  -- 清除默认样式，避免按下时出现白边
    self.btnJump:SetFocusMode(FM_NOTFOCUSABLE)
    self.btnJump.color = Color(0, 0, 0, 0)  -- 按钮背景完全透明

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
    local uiRoot = ui.root
    local U = ScreenUtils.ui

    local btnSize = U(88)
    local attackContainer = UIElement:new()
    uiRoot:AddChild(attackContainer)
    attackContainer:SetAlignment(HA_RIGHT, VA_BOTTOM)
    attackContainer:SetSize(btnSize, btnSize)
    -- 跳跃按钮右边距24+宽88+间距20 = 132
    attackContainer:SetPosition(U(-132), U(-30))
    table.insert(self.elements, attackContainer)

    self.attackContainer = attackContainer

    self.btnAttack = Button:new()
    attackContainer:AddChild(self.btnAttack)
    self.btnAttack:SetSize(btnSize, btnSize)
    self.btnAttack:SetPosition(0, 0)
    self.btnAttack:SetStyle("", nil)  -- 清除默认样式，避免按下时出现白边
    self.btnAttack:SetFocusMode(FM_NOTFOCUSABLE)
    self.btnAttack.color = Color(0, 0, 0, 0)  -- 按钮背景完全透明

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

-- 右上角BACK按钮（五感图标下方）


-- 右上角五感状态图标（使用图片素材）
function GameUI:_createSensesStatusUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s

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

    self.sensesContainer = container
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

-- 隐藏游戏UI
function GameUI:hide()
    for _, elem in ipairs(self.elements) do
        elem.visible = false
    end
end

-- 辅助：判断触摸的UI元素是否属于指定容器
function GameUI:_isTouchOnElement(touchedElem, container)
    if not touchedElem or not container then return false end
    local elem = touchedElem
    while elem do
        if elem == container then return true end
        elem = elem.parent
    end
    return false
end

-- 辅助：判断触摸的UI元素是否属于摇杆容器
function GameUI:_isTouchOnJoystick(touchedElem)
    return self:_isTouchOnElement(touchedElem, self.joystickContainer)
end

-- 多点触控按钮检测（每帧调用）
-- 解决：移动端第一个触摸点被摇杆占用后，其他手指无法触发 Button Pressed/Released 事件
function GameUI:_updateTouchButtons()
    local numTouches = input.numTouches
    if numTouches <= 0 then
        -- 无触摸时释放所有按钮状态
        if self._touchJumpActive then
            self._touchJumpActive = false
            self.inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
        end
        if self._touchAttackActive then
            self._touchAttackActive = false
            self.inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
        end
        return
    end

    local jumpTouched = false
    local attackTouched = false

    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        if touch and touch.touchedElement then
            -- 跳跃按钮
            if self.btnJump and self:_isTouchOnElement(touch.touchedElement, self.jumpContainer) then
                jumpTouched = true
            end
            -- 攻击按钮
            if self.btnAttack and self:_isTouchOnElement(touch.touchedElement, self.attackContainer) then
                attackTouched = true
            end
            -- 卡牌按钮（通过全局 cardUI 引用）
            if G and G.cardUI and G.cardUI.container then
                if self:_isTouchOnElement(touch.touchedElement, G.cardUI.container) then
                    -- 找到具体哪张卡牌被按下
                    for ci = 1, 5 do
                        local slot = G.cardUI.cardSlots[ci]
                        if slot and slot.btn and self:_isTouchOnElement(touch.touchedElement, slot.btn) then
                            if not self._touchCardActive then
                                self._touchCardActive = ci
                                -- 触发卡牌使用
                                local idx = G.cardUI:getHandIndex(ci)
                                if idx and G.cardSystem then
                                    G.cardSystem:useCard(idx)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 跳跃按钮：按下/释放
    if jumpTouched and not self._touchJumpActive then
        self._touchJumpActive = true
        self.inputManager:setTouchAction(InputManager.ACTION_JUMP, true)
    elseif not jumpTouched and self._touchJumpActive then
        self._touchJumpActive = false
        self.inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
    end

    -- 攻击按钮：按下/释放
    if attackTouched and not self._touchAttackActive then
        self._touchAttackActive = true
        self.inputManager:setTouchAction(InputManager.ACTION_ATTACK, true)
    elseif not attackTouched and self._touchAttackActive then
        self._touchAttackActive = false
        self.inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
    end

    -- 卡牌释放（手指离开后允许再次点击）
    if not self._touchCardTouching then
        self._touchCardActive = nil
    end
    self._touchCardTouching = false
    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        if touch and touch.touchedElement and G and G.cardUI and G.cardUI.container then
            if self:_isTouchOnElement(touch.touchedElement, G.cardUI.container) then
                self._touchCardTouching = true
                break
            end
        end
    end
    if not self._touchCardTouching then
        self._touchCardActive = nil
    end
end

-- 摇杆输入处理（每帧调用）- 支持多点触控
-- 修复：在手机端(DPR>1)，touch.position与element.screenPosition可能不在同一坐标空间
function GameUI:_updateJoystick()
    if not self.joystickContainer or not self.joystickContainer.visible then
        return
    end

    -- 使用实际容器尺寸（编辑器布局可能修改了大小）
    local actualSize = self.joystickContainer.size
    local joystickW = actualSize.x > 0 and actualSize.x or self.joystickSize
    local joystickH = actualSize.y > 0 and actualSize.y or self.joystickSize

    -- 获取摇杆容器的屏幕中心位置（在 ui.root 坐标空间）
    local containerPos = self.joystickContainer.screenPosition
    local cx = containerPos.x + joystickW / 2
    local cy = containerPos.y + joystickH / 2
    local hitRadius = joystickW / 2

    -- 坐标空间修正：touch.position 在 graphics 像素空间，screenPosition 在 ui.root 空间
    -- 当 ui.root 尺寸与 graphics 尺寸不同时（手机端DPR），需要缩放
    local gfxW = graphics:GetWidth()
    local gfxH = graphics:GetHeight()
    local uiW = ui.root.width
    local uiH = ui.root.height
    local scaleX = (gfxW > 0 and uiW > 0) and (uiW / gfxW) or 1.0
    local scaleY = (gfxH > 0 and uiH > 0) and (uiH / gfxH) or 1.0

    -- 在所有触摸点中找到落在摇杆区域内的那个
    local numTouches = input.numTouches
    local foundTouch = false
    local touchX, touchY = 0, 0

    if numTouches > 0 then
        for i = 0, numTouches - 1 do
            local touch = input:GetTouch(i)
            if touch then
                -- 将触摸坐标转换到 UI 坐标空间
                local tx = touch.position.x * scaleX
                local ty = touch.position.y * scaleY

                -- 继续跟踪已激活的触摸（通过 touchID）
                if self.joystickActive and self.joystickTouchID == touch.touchID then
                    foundTouch = true
                    touchX = tx
                    touchY = ty
                    break
                end

                -- 新触摸：优先使用 touchedElement 判断（引擎内部坐标映射可靠）
                if not self.joystickActive then
                    local onJoystick = self:_isTouchOnJoystick(touch.touchedElement)
                    -- 备选：距离判断（兼容 touchedElement 为空的情况）
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
                        touchX = tx
                        touchY = ty
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
            touchX = mx
            touchY = my
        end
    end

    if foundTouch then
        self.joystickActive = true
        local dx = touchX - cx
        local dy = touchY - cy
        local dist = math.sqrt(dx * dx + dy * dy)

        local maxDist = self.joystickMaxDist
        if dist > maxDist then
            dx = dx * maxDist / dist
            dy = dy * maxDist / dist
        end

        self.joystickThumb:SetPosition(
            self.joystickCenterX + dx,
            self.joystickCenterY + dy
        )

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
    -- 多点触控按钮检测（解决摇杆占用首触摸点后其他按钮无响应）
    self:_updateTouchButtons()

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

-- 应用编辑器保存的UI布局配置
function GameUI:_applyEditorLayout()
    if not fileSystem:FileExists("editor_ui_config.json") then
        log:Write(LOG_INFO, "[GameUI] No editor UI config, using defaults")
        return
    end

    local file = File("editor_ui_config.json", FILE_READ)
    if not file:IsOpen() then return end
    local jsonStr = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok or not data or not data.elements then
        log:Write(LOG_WARNING, "[GameUI] Failed to parse editor UI config")
        return
    end

    local S = ScreenUtils.s

    -- 编辑器画布 640×360 对应设计分辨率 1280×720，比例为 2
    local CANVAS_SCALE = 2.0

    -- align 字符串转 Urho3D 对齐枚举
    local alignMap = {
        top_left     = { HA_LEFT,   VA_TOP },
        top_center   = { HA_CENTER, VA_TOP },
        top_right    = { HA_RIGHT,  VA_TOP },
        center       = { HA_CENTER, VA_CENTER },
        bottom_left  = { HA_LEFT,   VA_BOTTOM },
        bottom_right = { HA_RIGHT,  VA_BOTTOM },
    }

    -- 元素ID到容器的映射
    local containerMap = {
        hp_bar     = self.hpContainer,
        countdown  = self.countdownContainer,
        joystick   = self.joystickContainer,
        jump_btn   = self.jumpContainer,
        attack_btn = self.attackContainer,
        senses     = self.sensesContainer,
    }

    for id, elem in pairs(data.elements) do
        local container = containerMap[id]
        if container and elem.visible ~= false then
            -- 应用对齐
            local align = alignMap[elem.align]
            if align then
                container:SetAlignment(align[1], align[2])
            end

            -- 应用位置（编辑器坐标×2=设计坐标，再通过S()缩放到屏幕像素）
            local px = S(elem.x * CANVAS_SCALE)
            local py = S(elem.y * CANVAS_SCALE)
            container:SetPosition(px, py)

            -- 应用尺寸
            local pw = S(elem.w * CANVAS_SCALE)
            local ph = S(elem.h * CANVAS_SCALE)
            container:SetSize(pw, ph)

            log:Write(LOG_DEBUG, string.format("[GameUI] Applied layout for '%s': pos(%d,%d) size(%d,%d)", id, px, py, pw, ph))
        end
    end

    log:Write(LOG_INFO, "[GameUI] Editor layout applied")
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
