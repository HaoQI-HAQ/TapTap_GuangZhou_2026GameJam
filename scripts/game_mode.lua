-- game_mode.lua
-- 游戏模式：场景创建、关卡初始化、游戏循环、菜单回调、UI
---@diagnostic disable: undefined-global, redefined-local

local ScreenUtils = require("scripts/screen_utils")
local LevelManager = require("scripts/level_manager")
local PortalUI = require("scripts/portal_ui")

local M = {}

-- ============================================================================
-- 注入共享状态
-- ============================================================================
local G  -- 将由 main.lua 注入

function M.init(shared)
    G = shared
end

-- ============================================================================
-- LoadModeScripts
-- ============================================================================
function M.LoadModeScripts(mode)
    local prefix = "scripts/" .. mode .. "/"
    -- 共享模块（所有模式相同，从根目录加载）
    local sharedModules = {
        "scripts/enemy",
        "scripts/ground",
        "scripts/card_data",
        "scripts/card_skills",
        "scripts/card_system",
        "scripts/card_ui",
        "scripts/senses_system",
    }
    -- 模式专属模块（各模式有差异化实现）
    local modeModules = {
        prefix .. "player",
        prefix .. "game_ui",
    }
    -- 清除缓存确保重新加载
    for _, m in ipairs(sharedModules) do package.loaded[m] = nil end
    for _, m in ipairs(modeModules) do package.loaded[m] = nil end
    -- 加载所有模块（覆盖全局 Player/Enemy/Ground 等类）
    for _, m in ipairs(sharedModules) do require(m) end
    for _, m in ipairs(modeModules) do require(m) end
    G.currentMode = mode
    log:Write(LOG_INFO, "[Game] Loaded mode scripts: " .. mode)
end

-- ============================================================================
-- 场景/相机创建
-- ============================================================================
function M.CreateScene()
    G.scene_ = Scene()
    G.scene_:CreateComponent("Octree")

    G.physicsWorld_ = G.scene_:CreateComponent("PhysicsWorld2D")
    G.physicsWorld_.gravity = Vector2(0, -9.81)

    local lightNode = G.scene_:CreateChild("DirectionalLight")
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1, 1, 1, 1)
    lightNode.direction = Vector3(0, 0, 1)
end

function M.SetupCamera()
    G.cameraNode = G.scene_:CreateChild("Camera")
    G.cameraNode.position = Vector3(0, 0, -10)

    G.camera_ = G.cameraNode:CreateComponent("Camera")
    G.camera_.orthographic = true
    G.camera_.orthoSize = 5.2

    local viewport = Viewport:new(G.scene_, G.camera_)
    renderer:SetViewport(0, viewport)
    renderer.defaultZone.fogColor = Color(0.05, 0.05, 0.08, 1.0)
end

-- ============================================================================
-- 游戏对象初始化
-- ============================================================================
function M.InitGameObjects()
    -- 销毁旧UI元素
    if G.sensesSystem then G.sensesSystem:destroy(); G.sensesSystem = nil end
    if G.gameUI then G.gameUI:destroy(); G.gameUI = nil end
    if G.cardUI then G.cardUI:destroy(); G.cardUI = nil end
    if G.portalUI then G.portalUI:destroy(); G.portalUI = nil end
    for _, e in ipairs(G.enemies) do
        if e.hpBarContainer then e.hpBarContainer:Remove() end
        if e.floatingTexts then
            for _, ft in ipairs(e.floatingTexts) do
                if ft.text then ft.text:Remove() end
            end
            e.floatingTexts = {}
        end
    end
    G.enemies = {}

    if not G.levelManager then
        G.levelManager = LevelManager:new()
    end

    -- 关卡背景
    local BG_IMAGES = {
        "image/backgrounds/dungeon_rooms/room1_entrance.png",
        "image/backgrounds/dungeon_rooms/room2_prison.png",
        "image/backgrounds/dungeon_rooms/room3_sewer.png",
        "image/backgrounds/dungeon_rooms/room4_altar.png",
        "image/backgrounds/dungeon_rooms/room5_boss_throne.png",
    }
    local groundWidth, platforms = G.levelManager:getGroundConfig()

    local bgPath = BG_IMAGES[G.levelManager:getCurrentLevel()] or BG_IMAGES[1]
    local bgNode = G.scene_:CreateChild("Background")
    bgNode.position = Vector3(0, 0, 0)
    local bgSprite = bgNode:CreateComponent("StaticSprite2D")
    bgSprite.orderInLayer = -100
    local bgRes = cache:GetResource("Sprite2D", bgPath)
    if bgRes then
        bgSprite:SetSprite(bgRes)
        local bgTexture = bgRes:GetTexture()
        local texW = bgTexture:GetWidth() / 100.0
        local texH = bgTexture:GetHeight() / 100.0
        local viewH = G.camera_.orthoSize * 2
        local aspect = graphics:GetWidth() / graphics:GetHeight()
        local viewW = viewH * aspect
        local scale = math.max(viewW / texW, viewH / texH)
        bgNode:SetScale(scale)
    end

    Ground:new(G.scene_, 0, -3.0, groundWidth, 1.0)
    for _, p in ipairs(platforms) do
        Ground:new(G.scene_, p.x, p.y, p.w, p.h)
    end

    G.player = Player:new(G.scene_, G.inputManager)

    local levelEnemies = G.levelManager:generateEnemies()
    for _, info in ipairs(levelEnemies) do
        local e = Enemy:new(G.scene_, G.camera_, G.player, info.x, info.y, info.element, info.boss)
        table.insert(G.enemies, e)
    end
    G.player.enemies = G.enemies
    for _, e in ipairs(G.enemies) do
        e.enemyList = G.enemies
    end

    G.gameUI = GameUI:new(G.inputManager, G.player)
    G.gameUI:setLevel(G.levelManager:getCurrentLevel(), G.levelManager.maxLevel)

    G.sensesSystem = SensesSystem:new(G.scene_, G.player, G.gameUI)
    G.player.sensesSystem = G.sensesSystem
    G.gameUI.sensesSystem = G.sensesSystem

    G.cardSystem = CardSystem:new()
    G.cardUI = CardUI:new(G.cardSystem)
    G.cardSkills = CardSkills:new(G.scene_, G.player, G.enemies, G.cardSystem)
    G.gameUI.cardSystem = G.cardSystem
    for _, e in ipairs(G.enemies) do
        e.cardSystem = G.cardSystem
    end

    G.cardSystem.onCastStart = function() G.player.castingCard = true end
    G.cardSystem.onCastEnd = function() G.player.castingCard = false end
    G.cardSystem.onCardUsed = function(card) G.cardSkills:execute(card) end

    G.player.onDamagedCallback = function()
        local sense = G.sensesSystem:onPlayerDamaged()
        if sense then log:Write(LOG_INFO, "[Game] Sense deprived: " .. sense) end
    end
    G.player.gameOverCallback = function() M.ShowGameOver() end

    -- 传送门系统
    G.portalUI = PortalUI:new()
    G.levelManager:createPortal(G.scene_)
    G.levelManager.onPortalActivated = function()
        G.portalUI:showPortalHint()
    end
    G.levelManager.onTeleportStart = function()
        G.portalUI:showCharging()
    end
    G.levelManager.onTeleportProgress = function(progress)
        G.portalUI:setProgress(progress)
        if progress <= 0 then G.portalUI:hideCharging() end
    end
    G.levelManager.onTeleportComplete = function(nextLevel)
        G.portalUI:showComplete()
        M._scheduleLevelTransition(nextLevel)
    end
    G.levelManager.onEnemiesNotCleared = function()
        G.portalUI:showEnemiesNotCleared()
    end
    G.levelManager.onGameComplete = function()
        G.portalUI:showGameComplete()
        M._scheduleReturnToMenu(3.0)
    end

    log:Write(LOG_INFO, "[Game] Game objects initialized for mode: " .. (G.currentMode or "unknown") .. " Level: " .. G.levelManager:getCurrentLevel())
end

-- ============================================================================
-- 关卡过渡
-- ============================================================================
function M._scheduleLevelTransition(nextLevel)
    G.transitionTimer = 0.5
    G.transitionTarget = nextLevel
end

function M._scheduleReturnToMenu(delay)
    G.returnToMenuTimer = delay or 3.0
end

function M._doLevelTransition(nextLevel)
    log:Write(LOG_INFO, "[Game] === Transitioning to Level " .. nextLevel .. " ===")

    local savedHp = G.player and G.player:getHp() or nil
    local savedSenses = nil
    if G.sensesSystem then
        savedSenses = {
            deprived = {},
            deprivedCount = G.sensesSystem.deprivedCount or 0,
            driftEnabled = G.sensesSystem.driftEnabled,
            driftOffset = G.sensesSystem.driftOffset,
            uiDistortEnabled = G.sensesSystem.uiDistortEnabled,
            trapWarningHidden = G.sensesSystem.trapWarningHidden,
            timerGlitch = G.sensesSystem.timerGlitch,
            audioMuted = G.sensesSystem.audioMuted,
            visionFading = G.sensesSystem.visionFading,
            visionFadeAlpha = G.sensesSystem.visionFadeAlpha,
        }
        for k, v in pairs(G.sensesSystem.deprived) do
            savedSenses.deprived[k] = v
        end
    end

    M.CreateScene()
    M.SetupCamera()
    M.InitGameObjects()

    if nextLevel >= 4 then
        if G.gameUI then G.gameUI:updateSensesIcons() end
    else
        if savedHp and G.player then
            G.player.hp = savedHp
        end
        if savedSenses and G.sensesSystem then
            G.sensesSystem.deprived = savedSenses.deprived
            G.sensesSystem.deprivedCount = savedSenses.deprivedCount
            G.sensesSystem.driftEnabled = savedSenses.driftEnabled
            G.sensesSystem.driftOffset = savedSenses.driftOffset
            G.sensesSystem.uiDistortEnabled = savedSenses.uiDistortEnabled
            G.sensesSystem.trapWarningHidden = savedSenses.trapWarningHidden
            G.sensesSystem.timerGlitch = savedSenses.timerGlitch
            G.sensesSystem.audioMuted = savedSenses.audioMuted
            G.sensesSystem.visionFading = savedSenses.visionFading
            G.sensesSystem.visionFadeAlpha = savedSenses.visionFadeAlpha
            if savedSenses.audioMuted then
                audio:SetMasterGain("Effect", 0.0)
            end
        end
        if G.gameUI then G.gameUI:updateSensesIcons() end
    end

    G.cameraNode.position = Vector3(0, -1.9, -10)
    G.physicsWorld_.enabled = true
    G.scene_.updateEnabled = true
    G.gamePaused = false
    G.gameUI:show()
    G.gameUI:resetCountdown()
    G.cardSystem:reset()
    G.cardSkills:reset()
    G.cardUI:show()
end

-- ============================================================================
-- EnterGame / ReturnToMenu
-- ============================================================================
function M.EnterGame(mode)
    M.LoadModeScripts(mode)

    if G.levelManager then
        G.levelManager:reset()
    else
        G.levelManager = LevelManager:new()
    end
    G.transitionTimer = nil
    G.transitionTarget = nil

    M.CreateScene()
    M.SetupCamera()
    M.InitGameObjects()

    G.cameraNode.position = Vector3(0, -1.9, -10)
    G.physicsWorld_.enabled = true
    G.scene_.updateEnabled = true
    G.gamePaused = false
    if G.pausePanel then G.pausePanel.visible = false end
    G.gameUI:show()
    G.gameUI:resetCountdown()
    G.cardSystem:reset()
    G.cardSkills:reset()
    G.cardUI:show()
    log:Write(LOG_INFO, "[Game] Enter game - mode: " .. mode)
end

function M.ReturnToMenu()
    G.physicsWorld_.enabled = false
    G.gamePaused = false
    if G.pausePanel then G.pausePanel.visible = false end
    G.gameUI:hide()
    G.cardUI:hide()
    for _, e in ipairs(G.enemies) do
        e:hideHpBar()
    end
    G.menuOverlay:show()
end

-- ============================================================================
-- 游戏 Update 循环
-- ============================================================================
function M.gameUpdate(dt)
    if G.loadingScene then
        G.loadingScene:update(dt)
        return
    end
    if not G.gameReady then return end

    if G.menuOverlay:isVisible() then return end

    if input:GetKeyPress(KEY_TAB) or input:GetKeyPress(KEY_ESCAPE) then
        if not G.gamePaused then
            G.gamePaused = true
            G.scene_.updateEnabled = false
            if G.pausePanel then G.pausePanel.visible = true end
        else
            G.gamePaused = false
            G.scene_.updateEnabled = true
            if G.pausePanel then G.pausePanel.visible = false end
        end
        return
    end

    if G.gamePaused then return end
    if not G.player then return end

    G.inputManager:update()
    G.player:update(dt)
    for _, e in ipairs(G.enemies) do e:update(dt) end
    G.cardSystem:update(dt)
    G.cardSkills:update(dt)
    G.cardUI:update(dt)

    -- 键盘快捷键开牌
    local CARD_KEYS = { KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P }
    local handCount = G.cardUI and G.cardUI:getHandCount() or 0
    if handCount > 0 then
        local keyOffset = 5 - handCount
        for i = 1, handCount do
            if input:GetKeyPress(CARD_KEYS[keyOffset + i]) then
                local idx = G.cardUI:getHandIndex(i)
                if idx then G.cardSystem:useCard(idx) end
                break
            end
        end
    end

    G.sensesSystem:update(dt)
    G.gameUI:update(dt)

    if G.levelManager and not G.player:isDead() then
        local playerPos = G.player:getPosition()
        G.levelManager:update(dt, playerPos, G.enemies)
    end
    if G.portalUI then G.portalUI:update(dt) end

    if G.transitionTimer then
        G.transitionTimer = G.transitionTimer - dt
        if G.transitionTimer <= 0 then
            local target = G.transitionTarget
            G.transitionTimer = nil
            G.transitionTarget = nil
            M._doLevelTransition(target)
            return
        end
    end

    if G.returnToMenuTimer then
        G.returnToMenuTimer = G.returnToMenuTimer - dt
        if G.returnToMenuTimer <= 0 then
            G.returnToMenuTimer = nil
            M.HandleRestart()
            return
        end
    end

    -- 相机跟随
    local targetPos = G.player:getPosition()
    local camPos = G.cameraNode.position
    local lerpSpeed = 3.0
    local newX = camPos.x + (targetPos.x - camPos.x) * lerpSpeed * dt
    local newY = camPos.y + (targetPos.y - camPos.y) * lerpSpeed * dt
    G.cameraNode.position = Vector3(newX, newY, -10)

    local bgNode = G.scene_:GetChild("Background")
    if bgNode then
        bgNode.position = Vector3(newX, newY, 0)
    end
end

-- ============================================================================
-- OnLoadingComplete
-- ============================================================================
function M.OnLoadingComplete()
    G.loadingScene = nil
    G.gameReady = true

    M.CreateScene()
    M.SetupCamera()

    G.inputManager = InputManager:new()
    G.menuOverlay = MenuOverlay:new()
    M._createGameOverUI()
    M._createPauseUI()
    M._createGMButton()

    G.physicsWorld_.enabled = false
    log:Write(LOG_INFO, "[Game] Base systems initialized, waiting for mode selection")
end

-- ============================================================================
-- GM Button
-- ============================================================================
function M._createGMButton()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()

    G.gmButton = Button:new()
    uiRoot:AddChild(G.gmButton)
    G.gmButton:SetStyleAuto()
    G.gmButton:SetSize(S(50), S(28))
    G.gmButton:SetPosition(sw - S(60), S(8))
    G.gmButton:SetAlignment(HA_LEFT, VA_TOP)
    G.gmButton.priority = 1200
    G.gmButton.opacity = 0.7

    local btnText = Text:new()
    G.gmButton:AddChild(btnText)
    btnText:SetStyleAuto()
    btnText.text = "GM"
    btnText:SetFontSize(S(14))
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.gmButton, "Released", "HandleGMButton")
end

-- ============================================================================
-- 菜单/模式选择回调（全局函数）
-- ============================================================================
function M.registerGlobalCallbacks()
    -- 这些是全局函数，引擎事件系统通过名称调用
    function HandleGMButton(eventType, eventData)
        log:Write(LOG_INFO, "[App] GM button pressed - switching to editor")
        G.editorMode_module.switchToEditor()
    end

    function HandleMenuShowSelect(eventType, eventData)
        G.menuOverlay:showSelect()
    end

    function HandleModeTest(eventType, eventData)
        G.menuOverlay:hide()
        M.EnterGame("test_room")
    end

    function HandleModeNormal(eventType, eventData)
        G.menuOverlay:hide()
        M.EnterGame("normal_mode")
    end

    function HandleModeEndless(eventType, eventData)
        G.menuOverlay:hide()
        M.ShowComingSoon()
    end

    function HandleModeBack(eventType, eventData)
        G.menuOverlay:showTitle()
    end

    function HandleMenuStart(eventType, eventData)
        G.menuOverlay:showSelect()
    end

    function HandleMenuExit(eventType, eventData)
        engine:Exit()
    end

    function HandleBackToMenu(eventType, eventData)
        M.ReturnToMenu()
    end

    function HandleTestBossSkill(eventType, eventData)
        for _, e in ipairs(G.enemies) do
            if e.isBoss and e:isAlive() then
                e:_startSkill()
                break
            end
        end
    end

    -- UI 按钮回调
    function HandleUILeftPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_LEFT, true)
    end
    function HandleUILeftReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
    end
    function HandleUIRightPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_RIGHT, true)
    end
    function HandleUIRightReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
    end
    function HandleUIJumpPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_JUMP, true)
    end
    function HandleUIJumpReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
    end
    function HandleUIAttackPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_ATTACK, true)
    end
    function HandleUIAttackReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
    end

    function HandleCardBtn1(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(1)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn2(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(2)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn3(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(3)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn4(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(4)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn5(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(5)
        if idx then G.cardSystem:useCard(idx) end
    end

    function HandleComingSoonBack(eventType, eventData)
        if G.comingSoonPanel then G.comingSoonPanel.visible = false end
        G.menuOverlay:show()
    end

    function HandlePauseBack(eventType, eventData)
        G.gamePaused = false
        G.scene_.updateEnabled = true
        if G.pausePanel then G.pausePanel.visible = false end
    end

    function HandlePauseLeave(eventType, eventData)
        G.gamePaused = false
        G.scene_.updateEnabled = true
        if G.pausePanel then G.pausePanel.visible = false end
        M.ReturnToMenu()
    end

    function HandleRestart(eventType, eventData)
        M.HandleRestart(eventType, eventData)
    end
end

-- ============================================================================
-- ComingSoon / Pause / GameOver UI
-- ============================================================================
function M.ShowComingSoon()
    if G.comingSoonPanel then
        G.comingSoonPanel.visible = true
        return
    end
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.comingSoonPanel = UIElement:new()
    uiRoot:AddChild(G.comingSoonPanel)
    G.comingSoonPanel:SetSize(sw, sh)
    G.comingSoonPanel:SetAlignment(HA_CENTER, VA_CENTER)
    G.comingSoonPanel:SetPriority(1100)

    local bg = BorderImage:new()
    G.comingSoonPanel:AddChild(bg)
    bg:SetSize(sw, sh)
    bg:SetPosition(0, 0)
    bg.color = Color(0.95, 0.95, 0.98, 1.0)

    local msg = Text:new()
    G.comingSoonPanel:AddChild(msg)
    msg:SetStyleAuto()
    msg.text = "未开发请敬请期待"
    msg:SetFontSize(S(28))
    msg:SetAlignment(HA_CENTER, VA_CENTER)
    msg:SetPosition(0, S(-30))
    msg.color = Color(0.3, 0.3, 0.4, 1.0)

    local btnBack = Button:new()
    G.comingSoonPanel:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(S(160), S(50))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(40))

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "返回"
    backText:SetFontSize(S(22))
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandleComingSoonBack")
end

function M._createPauseUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.pausePanel = UIElement:new()
    uiRoot:AddChild(G.pausePanel)
    G.pausePanel:SetSize(sw, sh)
    G.pausePanel:SetAlignment(HA_CENTER, VA_CENTER)
    G.pausePanel.priority = 1000

    local bg = BorderImage:new()
    G.pausePanel:AddChild(bg)
    bg:SetSize(sw, sh)
    bg:SetPosition(0, 0)
    bg.color = Color(0, 0, 0, 0.7)

    local title = Text:new()
    G.pausePanel:AddChild(title)
    title:SetStyleAuto()
    title.text = "PAUSED"
    title:SetFontSize(S(36))
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, S(-60))
    title.color = Color(1.0, 1.0, 1.0, 1.0)

    local btnBack = Button:new()
    G.pausePanel:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(S(180), S(55))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(10))

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "Back"
    backText:SetFontSize(S(24))
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandlePauseBack")

    local btnLeave = Button:new()
    G.pausePanel:AddChild(btnLeave)
    btnLeave:SetStyleAuto()
    btnLeave:SetSize(S(180), S(55))
    btnLeave:SetAlignment(HA_CENTER, VA_CENTER)
    btnLeave:SetPosition(0, S(80))

    local leaveText = Text:new()
    btnLeave:AddChild(leaveText)
    leaveText:SetStyleAuto()
    leaveText.text = "Leave"
    leaveText:SetFontSize(S(24))
    leaveText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnLeave, "Released", "HandlePauseLeave")

    G.pausePanel.visible = false
end

function M._createGameOverUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.gameOverContainer = BorderImage:new()
    uiRoot:AddChild(G.gameOverContainer)
    G.gameOverContainer:SetSize(sw, sh)
    G.gameOverContainer:SetAlignment(HA_LEFT, VA_TOP)
    G.gameOverContainer:SetPosition(0, 0)
    G.gameOverContainer.priority = 900
    G.gameOverContainer.color = Color(0, 0, 0, 0.85)

    local title = Text:new()
    G.gameOverContainer:AddChild(title)
    title:SetStyleAuto()
    title.text = "GAME OVER"
    title:SetFontSize(S(48))
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, S(-40))
    title.color = Color(1.0, 0.2, 0.2, 1.0)

    local restartBtn = Button:new()
    G.gameOverContainer:AddChild(restartBtn)
    restartBtn:SetStyleAuto()
    restartBtn:SetSize(S(160), S(50))
    restartBtn:SetAlignment(HA_CENTER, VA_CENTER)
    restartBtn:SetPosition(0, S(40))

    local btnText = Text:new()
    restartBtn:AddChild(btnText)
    btnText:SetStyleAuto()
    btnText.text = "返回菜单"
    btnText:SetFontSize(S(22))
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(restartBtn, "Released", "HandleRestart")

    G.gameOverContainer.visible = false
end

function M.ShowGameOver()
    if G.gameOverContainer then
        G.gameOverContainer:SetSize(ScreenUtils.width(), ScreenUtils.height())
        G.gameOverContainer.visible = true
    end
    G.physicsWorld_.enabled = false
    G.gamePaused = false
    if G.pausePanel then G.pausePanel.visible = false end
    G.gameUI:hide()
    G.cardUI:hide()
    for _, e in ipairs(G.enemies) do
        e:hideHpBar()
    end
end

function M.HandleRestart(eventType, eventData)
    if G.gameOverContainer then G.gameOverContainer.visible = false end
    if G.sensesSystem then G.sensesSystem:destroy(); G.sensesSystem = nil end
    if G.gameUI then G.gameUI:destroy(); G.gameUI = nil end
    if G.cardUI then G.cardUI:destroy(); G.cardUI = nil end
    if G.portalUI then G.portalUI:destroy(); G.portalUI = nil end
    for _, e in ipairs(G.enemies) do
        if e.hpBarContainer then e.hpBarContainer:Remove() end
        if e.floatingTexts then
            for _, ft in ipairs(e.floatingTexts) do
                if ft.text then ft.text:Remove() end
            end
            e.floatingTexts = {}
        end
    end
    G.enemies = {}
    G.player = nil
    if G.levelManager then G.levelManager:reset() end
    G.transitionTimer = nil
    G.transitionTarget = nil
    G.returnToMenuTimer = nil
    G.physicsWorld_.enabled = false
    G.menuOverlay:show()
end

return M
