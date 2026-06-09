-- game_mode.lua
-- 游戏模式：场景创建、关卡初始化、游戏循环、菜单回调、UI
---@diagnostic disable: undefined-global, redefined-local, param-type-mismatch, assign-type-mismatch

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

    local bgTex = cache:GetResource("Texture2D", bgPath)
    if bgTex then
        -- 背景宽度 = 主平台宽度 + 左右各5米
        local planeW = groundWidth + 10
        -- 高度按贴图宽高比计算
        local texW = bgTex:GetWidth()
        local texH = bgTex:GetHeight()
        local texAspect = texW / texH
        local planeH = planeW / texAspect

        -- 背景中心：x=0（与主平台对齐），y=0，z=5（最远层）
        bgNode.position = Vector3(0, 0, 5)

        local spriteNode = bgNode:CreateChild("BgSprite")
        spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        spriteNode.scale = Vector3(planeW, 1.0, planeH)

        local model = spriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        mat:SetTexture(0, bgTex)
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        mat:SetShaderParameter("UOffset", Variant(Vector4(1, 0, 0, 0)))
        mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
        model:SetMaterial(mat)
    end

    -- 关卡对应贴图配置
    local LEVEL_TILES = {
        [1] = { ground = "image/tiles/floor/stone_floor.png",  platform = "image/tiles/special/platform_edge.png" },
        [2] = { ground = "image/tiles/floor/stone_floor.png",  platform = "image/tiles/special/platform_edge.png" },
        [3] = { ground = "image/tiles/floor/cracked_floor.png", platform = "image/tiles/special/platform_edge.png" },
        [4] = { ground = "image/tiles/floor/stone_floor.png",  platform = "image/tiles/special/platform_edge.png" },
        [5] = { ground = "image/tiles/floor/gold_floor.png",   platform = "image/tiles/floor/gold_floor.png" },
    }
    local curLevel = G.levelManager:getCurrentLevel()
    local tiles = LEVEL_TILES[curLevel] or LEVEL_TILES[1]

    Ground:new(G.scene_, 0, -3.0, groundWidth, 1.0, tiles.ground)
    for _, p in ipairs(platforms) do
        Ground:new(G.scene_, p.x, p.y, p.w, p.h, tiles.platform)
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
    if G.gameUI.setLevel then
        G.gameUI:setLevel(G.levelManager:getCurrentLevel(), G.levelManager.maxLevel)
    end

    G.sensesSystem = SensesSystem:new(G.scene_, G.player, G.gameUI)
    G.player.sensesSystem = G.sensesSystem
    G.gameUI.sensesSystem = G.sensesSystem

    G.cardSystem = CardSystem:new()
    G.cardUI = CardUI:new(G.cardSystem)
    G.cardSkills = CardSkills:new(G.scene_, G.player, G.enemies, G.cardSystem)
    G.gameUI.cardSystem = G.cardSystem
    G.gameUI.cardUI = G.cardUI
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
        M.ShowVictory()
    end

    -- 标记关卡就绪，允许Boss击杀检测
    G.levelManager.levelReady = true

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
    -- 显示 Loading 界面预加载资源，完成后再进入关卡
    G.loadingScene = LoadingScene:new(function()
        G.loadingScene = nil
        M._doEnterGame(mode)
    end)
end

--- 实际进入游戏逻辑（Loading 完成后回调）
function M._doEnterGame(mode)
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

    -- Game Over / Victory CG 动画（不受暂停影响，在玩家死后持续播放）
    M.UpdateGameOverAnim(dt)
    M.UpdateVictoryAnim(dt)

    if G.gamePaused then return end
    if not G.player then return end

    G.inputManager:update()
    G.player:update(dt)
    for _, e in ipairs(G.enemies) do e:update(dt) end
    if G.cardSystem then G.cardSystem:update(dt) end
    if G.cardSkills then G.cardSkills:update(dt) end
    if G.cardUI then G.cardUI:update(dt) end

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

    -- 背景不跟随相机，保持静止
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
    M._createVictoryUI()
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

    local pxFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Mono-zh_hans.ttf")

    G.gmButton = Button:new()
    uiRoot:AddChild(G.gmButton)
    G.gmButton:SetStyle("none")
    G.gmButton:SetSize(S(50), S(28))
    G.gmButton:SetPosition(sw - S(60), S(8))
    G.gmButton:SetAlignment(HA_LEFT, VA_TOP)
    G.gmButton.priority = 1200
    G.gmButton.opacity = 0.7
    G.gmButton.color = Color(0.106, 0.106, 0.227, 0.8)

    local btnText = Text:new()
    G.gmButton:AddChild(btnText)
    if pxFont then btnText:SetFont(pxFont, S(14)) else btnText:SetStyleAuto(); btnText:SetFontSize(S(14)) end
    btnText.text = "GM"
    btnText.color = Color(0.424, 0.361, 0.906, 1.0)  -- 紫色
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

    function HandleVictoryMenu(eventType, eventData)
        M.HandleVictoryMenu(eventType, eventData)
    end

    function HandleVictoryRestart(eventType, eventData)
        M.HandleVictoryRestart(eventType, eventData)
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

    local pxFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")

    local msg = Text:new()
    G.comingSoonPanel:AddChild(msg)
    if pxFont then msg:SetFont(pxFont, S(28)) else msg:SetStyleAuto(); msg:SetFontSize(S(28)) end
    msg.text = "未开发请敬请期待"
    msg:SetAlignment(HA_CENTER, VA_CENTER)
    msg:SetPosition(0, S(-30))
    msg.color = Color(0.941, 0.941, 0.941, 1.0)

    local btnBack = Button:new()
    G.comingSoonPanel:AddChild(btnBack)
    btnBack:SetStyle("none")
    btnBack:SetSize(S(160), S(50))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(40))
    btnBack.color = Color(0.106, 0.106, 0.227, 1.0)

    local backText = Text:new()
    btnBack:AddChild(backText)
    if pxFont then backText:SetFont(pxFont, S(22)) else backText:SetStyleAuto(); backText:SetFontSize(S(22)) end
    backText.text = "返回"
    backText.color = Color(0.941, 0.941, 0.941, 1.0)
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

    local pxFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")

    local bg = BorderImage:new()
    G.pausePanel:AddChild(bg)
    bg:SetSize(sw, sh)
    bg:SetPosition(0, 0)
    bg.color = Color(0.059, 0.059, 0.137, 0.85)  -- 像素风深色遮罩

    local title = Text:new()
    G.pausePanel:AddChild(title)
    if pxFont then title:SetFont(pxFont, S(36)) else title:SetStyleAuto(); title:SetFontSize(S(36)) end
    title.text = "PAUSED"
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, S(-60))
    title.color = Color(0.129, 0.741, 0.682, 1.0)  -- 青色标题

    local btnBack = Button:new()
    G.pausePanel:AddChild(btnBack)
    btnBack:SetStyle("none")
    btnBack:SetSize(S(180), S(55))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(10))
    btnBack.color = Color(0.106, 0.106, 0.227, 1.0)

    local backText = Text:new()
    btnBack:AddChild(backText)
    if pxFont then backText:SetFont(pxFont, S(24)) else backText:SetStyleAuto(); backText:SetFontSize(S(24)) end
    backText.text = "继续"
    backText.color = Color(0.941, 0.941, 0.941, 1.0)
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandlePauseBack")

    local btnLeave = Button:new()
    G.pausePanel:AddChild(btnLeave)
    btnLeave:SetStyle("none")
    btnLeave:SetSize(S(180), S(55))
    btnLeave:SetAlignment(HA_CENTER, VA_CENTER)
    btnLeave:SetPosition(0, S(80))
    btnLeave.color = Color(0.106, 0.106, 0.227, 1.0)

    local leaveText = Text:new()
    btnLeave:AddChild(leaveText)
    if pxFont then leaveText:SetFont(pxFont, S(24)) else leaveText:SetStyleAuto(); leaveText:SetFontSize(S(24)) end
    leaveText.text = "离开"
    leaveText.color = Color(0.941, 0.941, 0.941, 1.0)
    leaveText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnLeave, "Released", "HandlePauseLeave")

    G.pausePanel.visible = false
end

function M._createGameOverUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    -- Game Over 背景图列表（每次死亡随机选一张）
    G.gameOverBGs = {
        "image/cg_gameover_G_20260531032355.png",
        "image/cg_gameover_F_20260531032401.png",
    }

    G.gameOverContainer = UIElement:new()
    uiRoot:AddChild(G.gameOverContainer)
    G.gameOverContainer:SetSize(sw, sh)
    G.gameOverContainer:SetAlignment(HA_LEFT, VA_TOP)
    G.gameOverContainer:SetPosition(0, 0)
    G.gameOverContainer.priority = 900

    -- 全黑背景遮罩（黑屏阶段用，始终在最底层）
    local blackBg = BorderImage:new()
    G.gameOverContainer:AddChild(blackBg)
    blackBg:SetStyleAuto()
    blackBg:SetSize(sw, sh)
    blackBg:SetPosition(0, 0)
    blackBg:SetAlignment(HA_LEFT, VA_TOP)
    blackBg.color = Color(0, 0, 0, 1.0)
    blackBg.opacity = 1.0
    blackBg.priority = -2

    -- CG背景图（BorderImage，在黑屏之上）
    G.gameOverBgSprite = BorderImage:new()
    G.gameOverContainer:AddChild(G.gameOverBgSprite)
    G.gameOverBgSprite:SetSize(sw, sh)
    G.gameOverBgSprite:SetPosition(0, 0)
    G.gameOverBgSprite:SetAlignment(HA_LEFT, VA_TOP)
    G.gameOverBgSprite.priority = 0
    G.gameOverBgSprite.opacity = 0.0
    G.gameOverBgSprite.blendMode = BLEND_ALPHA
    -- 预加载第一张纹理避免空白
    local preTex = cache:GetResource("Texture2D", G.gameOverBGs[1])
    if preTex then
        G.gameOverBgSprite:SetTexture(preTex)
        G.gameOverBgSprite:SetImageRect(IntRect(0, 0, preTex:GetWidth(), preTex:GetHeight()))
    end

    local pxFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")

    G.gameOverRestartBtn = Button:new()
    G.gameOverContainer:AddChild(G.gameOverRestartBtn)
    G.gameOverRestartBtn:SetStyle("none")
    G.gameOverRestartBtn:SetSize(S(160), S(50))
    G.gameOverRestartBtn:SetAlignment(HA_CENTER, VA_CENTER)
    G.gameOverRestartBtn:SetPosition(0, S(40))
    G.gameOverRestartBtn.color = Color(0.106, 0.106, 0.227, 0.9)

    local btnText = Text:new()
    G.gameOverRestartBtn:AddChild(btnText)
    if pxFont then btnText:SetFont(pxFont, S(22)) else btnText:SetStyleAuto(); btnText:SetFontSize(S(22)) end
    btnText.text = "返回菜单"
    btnText.color = Color(0.941, 0.941, 0.941, 1.0)
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.gameOverRestartBtn, "Released", "HandleRestart")

    -- 初始隐藏重启按钮（等CG淡入完成后再显示）
    G.gameOverRestartBtn.visible = false
    G.gameOverContainer.visible = false
end

-- ============================================================================
-- Victory UI（Boss击败胜利CG）
-- ============================================================================
function M._createVictoryUI()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.victoryContainer = UIElement:new()
    uiRoot:AddChild(G.victoryContainer)
    G.victoryContainer:SetSize(sw, sh)
    G.victoryContainer:SetAlignment(HA_LEFT, VA_TOP)
    G.victoryContainer:SetPosition(0, 0)
    G.victoryContainer.priority = 910

    -- 全黑背景
    local blackBg = BorderImage:new()
    G.victoryContainer:AddChild(blackBg)
    blackBg:SetStyleAuto()
    blackBg:SetSize(sw, sh)
    blackBg:SetPosition(0, 0)
    blackBg:SetAlignment(HA_LEFT, VA_TOP)
    blackBg.color = Color(0, 0, 0, 1.0)
    blackBg.opacity = 1.0
    blackBg.priority = -2

    -- 胜利CG图
    G.victoryBgSprite = BorderImage:new()
    G.victoryContainer:AddChild(G.victoryBgSprite)
    G.victoryBgSprite:SetSize(sw, sh)
    G.victoryBgSprite:SetPosition(0, 0)
    G.victoryBgSprite:SetAlignment(HA_LEFT, VA_TOP)
    G.victoryBgSprite.priority = 0
    G.victoryBgSprite.opacity = 0.0
    G.victoryBgSprite.blendMode = BLEND_ALPHA
    local victoryTex = cache:GetResource("Texture2D", "image/edited_victory_boss_killed_clean_20260601152842.png")
    if victoryTex then
        G.victoryBgSprite:SetTexture(victoryTex)
        G.victoryBgSprite:SetImageRect(IntRect(0, 0, victoryTex:GetWidth(), victoryTex:GetHeight()))
    end

    local pxFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")

    -- 返回主菜单按钮（左边中间，像素风）
    G.victoryMenuBtn = Button:new()
    G.victoryContainer:AddChild(G.victoryMenuBtn)
    G.victoryMenuBtn:SetStyle("none")
    G.victoryMenuBtn:SetSize(S(160), S(50))
    G.victoryMenuBtn:SetAlignment(HA_LEFT, VA_CENTER)
    G.victoryMenuBtn:SetPosition(S(60), 0)
    G.victoryMenuBtn.priority = 10
    G.victoryMenuBtn.color = Color(0.106, 0.106, 0.227, 0.9)

    local menuBtnText = Text:new()
    G.victoryMenuBtn:AddChild(menuBtnText)
    if pxFont then menuBtnText:SetFont(pxFont, S(20)) else menuBtnText:SetStyleAuto(); menuBtnText:SetFontSize(S(20)) end
    menuBtnText.text = "回主菜单"
    menuBtnText.color = Color(0.941, 0.941, 0.941, 1.0)
    menuBtnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.victoryMenuBtn, "Released", "HandleVictoryMenu")

    -- 重开按钮（右边中间，像素风）
    G.victoryRestartBtn = Button:new()
    G.victoryContainer:AddChild(G.victoryRestartBtn)
    G.victoryRestartBtn:SetStyle("none")
    G.victoryRestartBtn:SetSize(S(160), S(50))
    G.victoryRestartBtn:SetAlignment(HA_RIGHT, VA_CENTER)
    G.victoryRestartBtn:SetPosition(S(-60), 0)
    G.victoryRestartBtn.priority = 10
    G.victoryRestartBtn.color = Color(0.106, 0.106, 0.227, 0.9)

    local restartBtnText = Text:new()
    G.victoryRestartBtn:AddChild(restartBtnText)
    if pxFont then restartBtnText:SetFont(pxFont, S(20)) else restartBtnText:SetStyleAuto(); restartBtnText:SetFontSize(S(20)) end
    restartBtnText.text = "重新开始"
    restartBtnText.color = Color(0.941, 0.941, 0.941, 1.0)
    restartBtnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.victoryRestartBtn, "Released", "HandleVictoryRestart")

    -- 初始隐藏
    G.victoryMenuBtn.visible = false
    G.victoryRestartBtn.visible = false
    G.victoryContainer.visible = false
end

function M.ShowVictory()
    if G.victoryContainer then
        if G.victoryContainer.visible then return end

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()
        G.victoryContainer:SetSize(sw, sh)

        -- 重新加载胜利CG纹理（确保纹理可用）
        if G.victoryBgSprite then
            local tex = cache:GetResource("Texture2D", "image/edited_victory_boss_killed_clean_20260601152842.png")
            if tex then
                G.victoryBgSprite:SetTexture(tex)
                G.victoryBgSprite:SetImageRect(IntRect(0, 0, tex:GetWidth(), tex:GetHeight()))
            end
        end

        -- 初始状态：黑屏，CG隐藏
        G.victoryBgSprite.opacity = 0.0
        G.victoryBgSprite:SetSize(0, 0)
        G.victoryContainer.visible = true

        -- 启动胜利动画状态机
        G.victoryPhase = "blackscreen"
        G.victoryTimer = 0.0
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

-- Victory CG 动画更新（每帧调用）
local VICTORY_BLACK_DURATION = 2.0    -- 黑屏持续秒数（Boss击败后较短）
local VICTORY_FADEIN_DURATION = 1.5   -- CG淡入持续秒数

function M.UpdateVictoryAnim(dt)
    if not G.victoryPhase then return end

    G.victoryTimer = G.victoryTimer + dt

    if G.victoryPhase == "blackscreen" then
        if G.victoryTimer >= VICTORY_BLACK_DURATION then
            G.victoryPhase = "fadein"
            G.victoryTimer = 0.0
        end
    elseif G.victoryPhase == "fadein" then
        local progress = math.min(G.victoryTimer / VICTORY_FADEIN_DURATION, 1.0)
        local eased = 1.0 - (1.0 - progress) * (1.0 - progress)

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()

        -- 从 60% 缩放到 100%
        local scale = 0.6 + 0.4 * eased
        local imgW = math.floor(sw * scale)
        local imgH = math.floor(sh * scale)
        local posX = math.floor((sw - imgW) / 2)
        local posY = math.floor((sh - imgH) / 2)

        G.victoryBgSprite:SetSize(imgW, imgH)
        G.victoryBgSprite:SetPosition(posX, posY)
        G.victoryBgSprite.opacity = eased

        if progress >= 1.0 then
            G.victoryPhase = "done"
            -- 确保最终全屏覆盖
            G.victoryBgSprite:SetSize(sw, sh)
            G.victoryBgSprite:SetPosition(0, 0)
            G.victoryBgSprite.opacity = 1.0
            -- 显示按钮
            if G.victoryMenuBtn then G.victoryMenuBtn.visible = true end
            if G.victoryRestartBtn then G.victoryRestartBtn.visible = true end
        end
    end
end

function M.HandleVictoryMenu(eventType, eventData)
    G.victoryPhase = nil
    G.victoryTimer = nil
    if G.victoryMenuBtn then G.victoryMenuBtn.visible = false end
    if G.victoryRestartBtn then G.victoryRestartBtn.visible = false end
    if G.victoryContainer then G.victoryContainer.visible = false end
    M.ReturnToMenu()
end

function M.HandleVictoryRestart(eventType, eventData)
    G.victoryPhase = nil
    G.victoryTimer = nil
    if G.victoryMenuBtn then G.victoryMenuBtn.visible = false end
    if G.victoryRestartBtn then G.victoryRestartBtn.visible = false end
    if G.victoryContainer then G.victoryContainer.visible = false end
    -- 重新开始游戏（从第一关）
    M.HandleRestart(eventType, eventData)
end

function M.ShowGameOver()
    log:Write(LOG_INFO, "[GameOver] ShowGameOver called, container=" .. tostring(G.gameOverContainer ~= nil))
    if not G.gameOverContainer then
        log:Write(LOG_ERROR, "[GameOver] gameOverContainer is nil! Cannot show Game Over CG.")
        return
    end

    -- 已经显示则不重复处理
    if G.gameOverContainer.visible then
        log:Write(LOG_INFO, "[GameOver] Already visible, skipping")
        return
    end

    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()
    G.gameOverContainer:SetSize(sw, sh)

    -- 随机选择一张 Game Over 背景图
    if G.gameOverBGs and G.gameOverBgSprite then
        local idx = math.random(1, #G.gameOverBGs)
        local tex = cache:GetResource("Texture2D", G.gameOverBGs[idx])
        if tex then
            G.gameOverBgSprite:SetTexture(tex)
            G.gameOverBgSprite:SetImageRect(IntRect(0, 0, tex:GetWidth(), tex:GetHeight()))
            log:Write(LOG_INFO, "[GameOver] Loaded CG texture: " .. G.gameOverBGs[idx])
        else
            log:Write(LOG_ERROR, "[GameOver] Failed to load CG texture: " .. G.gameOverBGs[idx])
        end
    end

    -- 初始状态：黑屏，CG图隐藏（缩小+透明）
    G.gameOverBgSprite.opacity = 0.0
    G.gameOverBgSprite:SetSize(0, 0)
    G.gameOverContainer.visible = true

    -- 启动Game Over动画状态机
    G.gameOverPhase = "blackscreen"
    G.gameOverTimer = 0.0
    log:Write(LOG_INFO, "[GameOver] Phase set to blackscreen, container visible=true")

    G.physicsWorld_.enabled = false
    G.gamePaused = false
    if G.pausePanel then G.pausePanel.visible = false end
    if G.gameUI then G.gameUI:hide() end
    if G.cardUI then G.cardUI:hide() end
    for _, e in ipairs(G.enemies) do
        e:hideHpBar()
    end
end

-- Game Over CG 动画更新（每帧调用）
local GAMEOVER_BLACK_DURATION = 3.5   -- 黑屏持续秒数
local GAMEOVER_FADEIN_DURATION = 1.5  -- CG淡入持续秒数

function M.UpdateGameOverAnim(dt)
    if not G.gameOverPhase then return end

    G.gameOverTimer = G.gameOverTimer + dt

    if G.gameOverPhase == "blackscreen" then
        -- 黑屏阶段：等待3.5秒
        if G.gameOverTimer >= GAMEOVER_BLACK_DURATION then
            G.gameOverPhase = "fadein"
            G.gameOverTimer = 0.0
        end
    elseif G.gameOverPhase == "fadein" then
        -- 淡入阶段：CG从中间缩放+透明度渐现
        local progress = math.min(G.gameOverTimer / GAMEOVER_FADEIN_DURATION, 1.0)
        -- 使用 ease-out 缓动（让开始快结尾慢更自然）
        local eased = 1.0 - (1.0 - progress) * (1.0 - progress)

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()

        -- 从 60% 缩放到 100%
        local scale = 0.6 + 0.4 * eased
        local imgW = math.floor(sw * scale)
        local imgH = math.floor(sh * scale)
        local posX = math.floor((sw - imgW) / 2)
        local posY = math.floor((sh - imgH) / 2)

        G.gameOverBgSprite:SetSize(imgW, imgH)
        G.gameOverBgSprite:SetPosition(posX, posY)
        G.gameOverBgSprite.opacity = eased

        if progress >= 1.0 then
            G.gameOverPhase = "done"
            -- 确保最终全屏覆盖
            G.gameOverBgSprite:SetSize(sw, sh)
            G.gameOverBgSprite:SetPosition(0, 0)
            G.gameOverBgSprite.opacity = 1.0
            -- CG淡入完成，显示返回菜单按钮
            if G.gameOverRestartBtn then
                G.gameOverRestartBtn.visible = true
            end
        end
    end
end

function M.HandleRestart(eventType, eventData)
    -- 重置Game Over动画状态
    G.gameOverPhase = nil
    G.gameOverTimer = nil
    if G.gameOverRestartBtn then G.gameOverRestartBtn.visible = false end
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
