---@diagnostic disable: undefined-global, param-type-mismatch, assign-type-mismatch
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
    self:_createLevelIndicator()

    -- 默认隐藏（等菜单点击START后再显示）
    self:hide()

    log:Write(LOG_INFO, "[GameUI] Created with HP display, buttons and BACK")
end

-- 左上角血量显示（像素风）
function GameUI:_createHpUI()
    local S = self._S
    local uiRoot = ui.root

    self.hpContainer = UIElement:new()
    uiRoot:AddChild(self.hpContainer)
    self.hpContainer:SetAlignment(HA_LEFT, VA_TOP)
    self.hpContainer:SetPosition(S(20), S(20))
    self.hpContainer:SetSize(S(300), S(50))
    table.insert(self.elements, self.hpContainer)

    -- 使用像素字体
    local hpFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")
        or cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")

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
        hpIcon.color = Color(1.0, 0.27, 0.34, 1.0)  -- #FF4757 像素风红色
        hpIcon:SetPosition((i - 1) * S(40), S(5))
        self.hpIcons[i] = hpIcon
    end
end

-- 中上位置倒计时UI（使用齿轮图片）
function GameUI:_createCountdownUI()
    local S = self._S
    local uiRoot = ui.root

    local imgSize = S(64)
    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_CENTER, VA_TOP)
    container:SetSize(imgSize, imgSize)
    container:SetPosition(0, S(10))
    table.insert(self.elements, container)

    -- 预加载5张倒计时图片
    self.countdownImages = {}
    for i = 1, 5 do
        self.countdownImages[i] = cache:GetResource("Texture2D", "image/UI/time_0" .. i .. ".png")
    end

    -- 用 BorderImage 显示当前倒计时图片
    self.countdownIcon = BorderImage:new()
    container:AddChild(self.countdownIcon)
    self.countdownIcon:SetSize(imgSize, imgSize)
    self.countdownIcon:SetAlignment(HA_CENTER, VA_CENTER)
    self.countdownIcon.blendMode = BLEND_ALPHA
    if self.countdownImages[5] then
        self.countdownIcon:SetTexture(self.countdownImages[5])
        self.countdownIcon:SetFullImageRect()
    end

    -- 保留 countdownText 兼容性（隐藏的文本，仅用于逻辑）
    self.countdownText = Text:new()
    container:AddChild(self.countdownText)
    self.countdownText.visible = false
    self.countdownText.text = "5"
end

-- 左下角摇杆（使用图片素材）
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

    -- 底座背景（使用摇杆图片）
    local base = BorderImage:new()
    container:AddChild(base)
    base:SetSize(joystickSize, joystickSize)
    base:SetPosition(0, 0)
    base.blendMode = BLEND_ALPHA
    local baseTex = cache:GetResource("Texture2D", "image/UI/joystick_base.png")
    if baseTex then
        base:SetTexture(baseTex)
        base:SetFullImageRect()
    end

    -- 摇杆拇指（可拖动，半透明圆点）
    local thumb = BorderImage:new()
    container:AddChild(thumb)
    thumb:SetSize(thumbSize, thumbSize)
    -- 初始居中
    local centerX = (joystickSize - thumbSize) / 2
    local centerY = (joystickSize - thumbSize) / 2
    thumb:SetPosition(centerX, centerY)
    thumb.color = Color(1.0, 1.0, 1.0, 0.5)

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

-- 右下角跳跃按钮（使用图片素材）
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
    self.jumpContainer = jumpContainer

    -- 跳跃图标背景
    local jumpIcon = BorderImage:new()
    jumpContainer:AddChild(jumpIcon)
    jumpIcon:SetSize(btnSize, btnSize)
    jumpIcon:SetPosition(0, 0)
    jumpIcon.blendMode = BLEND_ALPHA
    local jumpTex = cache:GetResource("Texture2D", "image/UI/btn_jump.png")
    if jumpTex then
        jumpIcon:SetTexture(jumpTex)
        jumpIcon:SetFullImageRect()
    end

    -- 透明按钮覆盖在图标上接收点击（不使用默认样式避免白边）
    self.btnJump = Button:new()
    jumpContainer:AddChild(self.btnJump)
    self.btnJump:SetSize(btnSize, btnSize)
    self.btnJump:SetPosition(0, 0)
    self.btnJump:SetOpacity(0.0)
    self.btnJump:SetStyle("", nil)  -- 清除默认样式，避免按下时出现白边
    self.btnJump:SetFocusMode(FM_NOTFOCUSABLE)
    self.btnJump.color = Color(0, 0, 0, 0)  -- 按钮背景完全透明

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
    self.attackContainer = attackContainer

    -- 攻击图标背景
    local attackIcon = BorderImage:new()
    attackContainer:AddChild(attackIcon)
    attackIcon:SetSize(btnSize, btnSize)
    attackIcon:SetPosition(0, 0)
    attackIcon.blendMode = BLEND_ALPHA
    local attackTex = cache:GetResource("Texture2D", "image/UI/btn_attack.png")
    if attackTex then
        attackIcon:SetTexture(attackTex)
        attackIcon:SetFullImageRect()
    end

    -- 透明按钮覆盖在图标上接收点击（不使用默认样式避免白边）
    self.btnAttack = Button:new()
    attackContainer:AddChild(self.btnAttack)
    self.btnAttack:SetSize(btnSize, btnSize)
    self.btnAttack:SetPosition(0, 0)
    self.btnAttack:SetOpacity(0.0)
    self.btnAttack:SetStyle("", nil)  -- 清除默认样式，避免按下时出现白边
    self.btnAttack:SetFocusMode(FM_NOTFOCUSABLE)
    self.btnAttack.color = Color(0, 0, 0, 0)  -- 按钮背景完全透明

    SubscribeToEvent(self.btnAttack, "Pressed", "HandleUIAttackPressed")
    SubscribeToEvent(self.btnAttack, "Released", "HandleUIAttackReleased")
end

-- 右上角BACK按钮（五感图标下方）


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

-- 底部中间关卡指示器
function GameUI:_createLevelIndicator()
    local S = self._S
    local uiRoot = ui.root

    local container = UIElement:new()
    uiRoot:AddChild(container)
    container:SetAlignment(HA_CENTER, VA_BOTTOM)
    container:SetSize(S(120), S(30))
    container:SetPosition(0, S(-20))
    table.insert(self.elements, container)

    self.levelText = Text:new()
    container:AddChild(self.levelText)
    self.levelText.text = ""
    local lvlFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans.ttf")
        or cache:GetResource("Font", "Fonts/MiSans-Regular.ttf")
    if lvlFont then
        self.levelText:SetFont(lvlFont, S(16))
    else
        self.levelText:SetStyleAuto()
        self.levelText:SetFontSize(S(16))
    end
    self.levelText:SetAlignment(HA_CENTER, VA_CENTER)
    self.levelText.color = Color(0.129, 0.741, 0.682, 0.9)  -- 像素风青色
end

-- 设置当前关卡显示
function GameUI:setLevel(level, maxLevel)
    if self.levelText then
        self.levelText.text = "第 " .. level .. " / " .. maxLevel .. " 关"
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

-- 辅助：坐标命中测试 - 判断屏幕坐标(px,py)是否在容器的屏幕矩形内
-- px,py 为 UI 坐标空间（已转换）
-- margin: 可选的额外命中区域（平板上增大触控容错）
function GameUI:_hitTestContainer(px, py, container, margin)
    if not container or not container.visible then return false end
    local sp = container.screenPosition
    local sz = container.size
    local m = margin or 0
    return px >= (sp.x - m) and px <= (sp.x + sz.x + m) and py >= (sp.y - m) and py <= (sp.y + sz.y + m)
end

-- 多点触控按钮检测（每帧调用）
-- 解决：移动端第一个触摸点被摇杆占用后，其他手指无法触发 Button Pressed/Released 事件
-- 修复：平板端多点触控坐标空间兼容（尝试多种坐标映射方式）
function GameUI:_updateTouchButtons()
    local numTouches = input.numTouches
    local mouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)

    if numTouches <= 0 and not mouseDown then
        if self._touchJumpActive then
            self._touchJumpActive = false
            self.inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
        end
        if self._touchAttackActive then
            self._touchAttackActive = false
            self.inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
        end
        if self._touchCardActive then
            self._touchCardActive = nil
        end
        return
    end

    -- 坐标空间转换（touch.position 在 graphics 像素空间，screenPosition 在 ui.root 空间）
    local gfxW = graphics:GetWidth()
    local gfxH = graphics:GetHeight()
    local uiW = ui.root.width
    local uiH = ui.root.height
    local scaleX = (gfxW > 0 and uiW > 0) and (uiW / gfxW) or 1.0
    local scaleY = (gfxH > 0 and uiH > 0) and (uiH / gfxH) or 1.0

    -- 平板端触控容错边距（像素）
    local hitMargin = ScreenUtils.isTablet and 15 or 5

    -- 诊断日志（仅前几帧输出一次，帮助定位坐标空间问题）
    if not self._touchDiagLogged and numTouches >= 2 then
        self._touchDiagLogged = true
        local t0 = input:GetTouch(0)
        local t1 = input:GetTouch(1)
        if t0 and t1 then
            log:Write(LOG_INFO, string.format(
                "[GameUI:TouchDiag] gfx=%dx%d ui=%dx%d scaleX=%.3f scaleY=%.3f tablet=%s | T0: pos=(%d,%d) id=%d elem=%s | T1: pos=(%d,%d) id=%d elem=%s",
                gfxW, gfxH, uiW, uiH, scaleX, scaleY, tostring(ScreenUtils.isTablet),
                t0.position.x, t0.position.y, t0.touchID, tostring(t0.touchedElement ~= nil),
                t1.position.x, t1.position.y, t1.touchID, tostring(t1.touchedElement ~= nil)))
            -- 输出按钮位置
            if self.jumpContainer then
                local jsp = self.jumpContainer.screenPosition
                local jsz = self.jumpContainer.size
                log:Write(LOG_INFO, string.format(
                    "[GameUI:TouchDiag] jumpBtn: screenPos=(%d,%d) size=(%d,%d)",
                    jsp.x, jsp.y, jsz.x, jsz.y))
            end
            if self.attackContainer then
                local asp = self.attackContainer.screenPosition
                local asz = self.attackContainer.size
                log:Write(LOG_INFO, string.format(
                    "[GameUI:TouchDiag] attackBtn: screenPos=(%d,%d) size=(%d,%d)",
                    asp.x, asp.y, asz.x, asz.y))
            end
        end
    end

    local jumpTouched = false
    local attackTouched = false
    local cardTouching = false

    -- 辅助：尝试多种坐标对(scaled + raw)命中测试，解决平板坐标空间不确定问题
    local function multiHitTest(posX, posY, container)
        if not container or not container.visible then return false end
        -- 方式1：标准缩放坐标
        local tx = posX * scaleX
        local ty = posY * scaleY
        if self:_hitTestContainer(tx, ty, container, hitMargin) then return true end
        -- 方式2：原始坐标（平板可能 touch.position 已经在 UI 空间）
        if scaleX ~= 1.0 or scaleY ~= 1.0 then
            if self:_hitTestContainer(posX, posY, container, hitMargin) then return true end
        end
        return false
    end

    for i = 0, numTouches - 1 do
        local touch = input:GetTouch(i)
        if touch then
            -- 跳过已被摇杆占用的触摸点
            if self.joystickActive and self.joystickTouchID and self.joystickTouchID == touch.touchID then
                goto continue
            end

            local hitJump = false
            local hitAttack = false
            local hitCard = false

            -- 优先通过 touchedElement 判断（准确性最高）
            if touch.touchedElement then
                if self.btnJump and self:_isTouchOnElement(touch.touchedElement, self.jumpContainer) then
                    hitJump = true
                end
                if self.btnAttack and self:_isTouchOnElement(touch.touchedElement, self.attackContainer) then
                    hitAttack = true
                end
                if self.cardUI and self.cardUI.container then
                    if self:_isTouchOnElement(touch.touchedElement, self.cardUI.container) then
                        hitCard = true
                    end
                end
            end

            -- 备选：touchedElement 为 nil 或未命中时，用多模式坐标命中测试
            -- 平板多指触控时第二根手指的 touchedElement 经常为 nil
            if not hitJump and not hitAttack and not hitCard then
                local posX = touch.position.x
                local posY = touch.position.y

                if not hitJump and self.jumpContainer then
                    if multiHitTest(posX, posY, self.jumpContainer) then
                        hitJump = true
                    end
                end
                if not hitAttack and self.attackContainer then
                    if multiHitTest(posX, posY, self.attackContainer) then
                        hitAttack = true
                    end
                end
                if not hitCard and self.cardUI and self.cardUI.container then
                    if multiHitTest(posX, posY, self.cardUI.container) then
                        hitCard = true
                    end
                end
            end

            if hitJump then jumpTouched = true end
            if hitAttack then attackTouched = true end

            -- 卡牌处理：找到具体哪张被按下
            if hitCard and self.cardUI then
                cardTouching = true
                if not self._touchCardActive then
                    self:_handleCardTouch(touch, scaleX, scaleY, hitMargin)
                end
            end

            ::continue::
        end
    end

    -- 额外鼠标回退：平板上第二根手指可能只通过鼠标事件报告
    -- 仅当摇杆活跃且鼠标位置不在摇杆区域时检测按钮
    if mouseDown and self.joystickActive and not jumpTouched and not attackTouched and not cardTouching then
        local mousePos = input.mousePosition
        local mx = mousePos.x * scaleX
        local my = mousePos.y * scaleY
        -- 确保鼠标不在摇杆区域（避免误触发）
        local onJoystick = false
        if self.joystickContainer and self.joystickContainer.visible then
            onJoystick = self:_hitTestContainer(mx, my, self.joystickContainer, 0)
        end
        if not onJoystick then
            if not jumpTouched and self.jumpContainer then
                if self:_hitTestContainer(mx, my, self.jumpContainer, hitMargin) then
                    jumpTouched = true
                end
            end
            if not attackTouched and self.attackContainer then
                if self:_hitTestContainer(mx, my, self.attackContainer, hitMargin) then
                    attackTouched = true
                end
            end
            if not cardTouching and self.cardUI and self.cardUI.container then
                if self:_hitTestContainer(mx, my, self.cardUI.container, hitMargin) then
                    cardTouching = true
                    if not self._touchCardActive then
                        self:_handleCardTouchByCoord(mx, my, hitMargin)
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
    if not cardTouching then
        self._touchCardActive = nil
    end
end

-- 卡牌触摸处理（从 touch 对象找到具体哪张卡）
function GameUI:_handleCardTouch(touch, scaleX, scaleY, hitMargin)
    local bestSlot = nil
    local bestDist = math.huge
    local posX = touch.position.x
    local posY = touch.position.y
    local tx = posX * scaleX
    local ty = posY * scaleY

    for ci = 1, 5 do
        local slot = self.cardUI.cardSlots[ci]
        if slot and slot.active and slot.btn and slot.btn.visible then
            -- 优先用 touchedElement 精确匹配
            if touch.touchedElement and self:_isTouchOnElement(touch.touchedElement, slot.btn) then
                bestSlot = ci
                break
            end
            -- 坐标命中测试（scaled）
            if self:_hitTestContainer(tx, ty, slot.btn, hitMargin) then
                bestSlot = ci
                break
            end
            -- 坐标命中测试（raw，平板兼容）
            if scaleX ~= 1.0 or scaleY ~= 1.0 then
                if self:_hitTestContainer(posX, posY, slot.btn, hitMargin) then
                    bestSlot = ci
                    break
                end
            end
            -- 备选：找距离最近的活跃卡牌（容忍触摸不精确）
            local sp = slot.btn.screenPosition
            local sz = slot.btn.size
            local centerX = sp.x + sz.x / 2
            local centerY = sp.y + sz.y / 2
            local dist = math.abs(tx - centerX) + math.abs(ty - centerY)
            if dist < bestDist then
                bestDist = dist
                bestSlot = ci
            end
        end
    end

    if bestSlot then
        self._touchCardActive = bestSlot
        local idx = self.cardUI:getHandIndex(bestSlot)
        if idx and self.cardSystem then
            self.cardSystem:useCard(idx)
        end
    end
end

-- 卡牌坐标命中（鼠标回退用）
function GameUI:_handleCardTouchByCoord(mx, my, hitMargin)
    local bestSlot = nil
    local bestDist = math.huge

    for ci = 1, 5 do
        local slot = self.cardUI.cardSlots[ci]
        if slot and slot.active and slot.btn and slot.btn.visible then
            if self:_hitTestContainer(mx, my, slot.btn, hitMargin) then
                bestSlot = ci
                break
            end
            local sp = slot.btn.screenPosition
            local sz = slot.btn.size
            local centerX = sp.x + sz.x / 2
            local centerY = sp.y + sz.y / 2
            local dist = math.abs(mx - centerX) + math.abs(my - centerY)
            if dist < bestDist then
                bestDist = dist
                bestSlot = ci
            end
        end
    end

    if bestSlot then
        self._touchCardActive = bestSlot
        local idx = self.cardUI:getHandIndex(bestSlot)
        if idx and self.cardSystem then
            self.cardSystem:useCard(idx)
        end
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
                local tx = touch.position.x * scaleX
                local ty = touch.position.y * scaleY

                if self.joystickActive and self.joystickTouchID == touch.touchID then
                    foundTouch = true
                    touchX = tx
                    touchY = ty
                    break
                end

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
    local displayNum = math.ceil(displayVal)
    displayNum = math.max(1, math.min(5, displayNum))
    self.countdownText.text = tostring(displayNum)
    -- 更新倒计时图片
    if self.countdownIcon and self.countdownImages[displayNum] then
        self.countdownIcon:SetTexture(self.countdownImages[displayNum])
        self.countdownIcon:SetFullImageRect()
    end

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
