-- game_mode.lua
-- 游戏模式协调器：组织各子模块完成场景/UI/游戏循环
---@diagnostic disable: undefined-global, redefined-local

local ScreenUtils = require("scripts/screen_utils")
local LevelManager = require("scripts/level_manager")
local PortalUI = require("scripts/portal_ui")
local SceneManager = require("scripts/scene_manager")
local LevelTransition = require("scripts/level_transition")
local GameOverUI = require("scripts/ui/game_over_ui")
local VictoryUI = require("scripts/ui/victory_ui")
local PauseUI = require("scripts/ui/pause_ui")
local Callbacks = require("scripts/callbacks")

local M = {}

-- ============================================================================
-- 注入共享状态
-- ============================================================================
local G  -- 将由 main.lua 注入

function M.init(shared)
    G = shared
    SceneManager.init(shared)
    LevelTransition.init(shared)
    GameOverUI.init(shared)
    VictoryUI.init(shared)
    PauseUI.init(shared)
    Callbacks.init(shared, M, PauseUI)
end

-- ============================================================================
-- LoadModeScripts
-- ============================================================================
function M.LoadModeScripts(mode)
    local prefix = "scripts/" .. mode .. "/"
    local sharedModules = {
        "scripts/enemy",
        "scripts/ground",
        "scripts/card_data",
        "scripts/card_skills",
        "scripts/card_system",
        "scripts/card_ui",
        "scripts/senses_system",
    }
    local modeModules = {
        prefix .. "player",
        prefix .. "game_ui",
    }
    for _, m in ipairs(sharedModules) do package.loaded[m] = nil end
    for _, m in ipairs(modeModules) do package.loaded[m] = nil end
    for _, m in ipairs(sharedModules) do require(m) end
    for _, m in ipairs(modeModules) do require(m) end
    G.currentMode = mode
    log:Write(LOG_INFO, "[Game] Loaded mode scripts: " .. mode)
end

-- ============================================================================
-- 游戏对象初始化
-- ============================================================================
function M.InitGameObjects()
    -- 销毁旧对象
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

    -- 场景背景和地形
    local groundWidth, platforms = G.levelManager:getGroundConfig()
    SceneManager.CreateBackground(groundWidth)
    SceneManager.CreateTerrain(groundWidth, platforms)

    -- 玩家
    G.player = Player:new(G.scene_, G.inputManager)

    -- 敌人
    local levelEnemies = G.levelManager:generateEnemies()
    for _, info in ipairs(levelEnemies) do
        local e = Enemy:new(G.scene_, G.camera_, G.player, info.x, info.y, info.element, info.boss)
        table.insert(G.enemies, e)
    end
    G.player.enemies = G.enemies
    for _, e in ipairs(G.enemies) do
        e.enemyList = G.enemies
    end

    -- UI 系统
    G.gameUI = GameUI:new(G.inputManager, G.player)
    if G.gameUI.setLevel then
        G.gameUI:setLevel(G.levelManager:getCurrentLevel(), G.levelManager.maxLevel)
    end

    -- 五感系统
    G.sensesSystem = SensesSystem:new(G.scene_, G.player, G.gameUI)
    G.player.sensesSystem = G.sensesSystem
    G.gameUI.sensesSystem = G.sensesSystem

    -- 卡牌系统
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

    -- 玩家回调
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
        LevelTransition.scheduleLevelTransition(nextLevel)
    end
    G.levelManager.onEnemiesNotCleared = function()
        G.portalUI:showEnemiesNotCleared()
    end
    G.levelManager.onGameComplete = function()
        G.portalUI:showGameComplete()
        M.ShowVictory()
    end

    G.levelManager.levelReady = true

    log:Write(LOG_INFO, "[Game] Game objects initialized for mode: " .. (G.currentMode or "unknown") .. " Level: " .. G.levelManager:getCurrentLevel())
end

-- ============================================================================
-- 关卡过渡（委托给 LevelTransition）
-- ============================================================================
function M._doLevelTransition(nextLevel)
    log:Write(LOG_INFO, "[Game] === Transitioning to Level " .. nextLevel .. " ===")

    local state = LevelTransition.saveState()

    SceneManager.CreateScene()
    SceneManager.SetupCamera()
    M.InitGameObjects()

    LevelTransition.restoreState(state, nextLevel)
    LevelTransition.postTransitionSetup()
end

-- ============================================================================
-- EnterGame / ReturnToMenu
-- ============================================================================
function M.EnterGame(mode)
    G.loadingScene = LoadingScene:new(function()
        G.loadingScene = nil
        M._doEnterGame(mode)
    end)
end

function M._doEnterGame(mode)
    M.LoadModeScripts(mode)

    if G.levelManager then
        G.levelManager:reset()
    else
        G.levelManager = LevelManager:new()
    end
    G.transitionTimer = nil
    G.transitionTarget = nil

    SceneManager.CreateScene()
    SceneManager.SetupCamera()
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

    -- 暂停切换
    if input:GetKeyPress(KEY_TAB) or input:GetKeyPress(KEY_ESCAPE) then
        PauseUI.togglePause()
        return
    end

    if G.gamePaused then return end
    if not G.player then return end

    -- CG 动画更新
    GameOverUI.updateAnim(dt)
    VictoryUI.updateAnim(dt)

    -- 游戏逻辑更新
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

    -- 定时器检查（关卡过渡 / 返回菜单）
    local triggered = LevelTransition.checkTimers(dt,
        function(target) M._doLevelTransition(target) end,
        function() M.HandleRestart() end
    )
    if triggered then return end

    -- 相机跟随
    local targetPos = G.player:getPosition()
    local camPos = G.cameraNode.position
    local lerpSpeed = 3.0
    local newX = camPos.x + (targetPos.x - camPos.x) * lerpSpeed * dt
    local newY = camPos.y + (targetPos.y - camPos.y) * lerpSpeed * dt
    G.cameraNode.position = Vector3(newX, newY, -10)
end

-- ============================================================================
-- OnLoadingComplete（启动后首次加载完成）
-- ============================================================================
function M.OnLoadingComplete()
    G.loadingScene = nil
    G.gameReady = true

    SceneManager.CreateScene()
    SceneManager.SetupCamera()

    G.inputManager = InputManager:new()
    G.menuOverlay = MenuOverlay:new()
    GameOverUI.create()
    VictoryUI.create()
    PauseUI.createPausePanel()
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
-- 全局回调注册（委托给 callbacks 模块）
-- ============================================================================
function M.registerGlobalCallbacks()
    Callbacks.register()
end

-- ============================================================================
-- Show/Handle 转发（供 callbacks 和外部调用）
-- ============================================================================
function M.ShowComingSoon()
    PauseUI.showComingSoon()
end

function M.ShowGameOver()
    GameOverUI.show()
end

function M.ShowVictory()
    VictoryUI.show()
end

function M.HandleVictoryMenu(eventType, eventData)
    VictoryUI.hide()
    M.ReturnToMenu()
end

function M.HandleVictoryRestart(eventType, eventData)
    VictoryUI.hide()
    M.HandleRestart(eventType, eventData)
end

function M.HandleRestart(eventType, eventData)
    GameOverUI.hide()
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
