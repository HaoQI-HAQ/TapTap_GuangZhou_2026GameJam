-- 2D横板平台游戏 - 主入口
require "LuaScripts/Utilities/Sample"
require "scripts/input_manager"
require "scripts/menu_overlay"
require "scripts/loading_scene"
local LevelManager = require("scripts/level_manager")
local PortalUI = require("scripts/portal_ui")

-- 当前游戏模式："test_room" 或 "normal_mode"
local currentMode = nil

--- 按模式加载对应目录的游戏脚本（清除缓存后重新加载，覆盖全局类）
local function LoadModeScripts(mode)
    local prefix = "scripts/" .. mode .. "/"
    local modules = {
        prefix .. "player",
        prefix .. "enemy",
        prefix .. "ground",
        prefix .. "game_ui",
        prefix .. "card_system",
        prefix .. "card_ui",
        prefix .. "card_skills",
        prefix .. "card_data",
        prefix .. "senses_system",
    }
    -- 清除缓存确保重新加载
    for _, m in ipairs(modules) do
        package.loaded[m] = nil
    end
    -- 加载模块（覆盖全局 Player/Enemy/Ground 等）
    for _, m in ipairs(modules) do
        require(m)
    end
    currentMode = mode
    log:Write(LOG_INFO, "[Game] Loaded mode scripts: " .. mode)
end

local scene_ = nil
local cameraNode = nil
local camera_ = nil
local player = nil
local gameUI = nil
local inputManager = nil
local menuOverlay = nil
local physicsWorld_ = nil
local enemies = {}
local cardSystem = nil
local cardUI = nil
local cardSkills = nil
local sensesSystem = nil
local levelManager = nil
local portalUI = nil

-- 加载状态
local loadingScene = nil
local gameReady = false

-- 暂停状态
local gamePaused = false
local pausePanel = nil

function Start()
    SampleStart()

    -- 先显示加载界面，预加载资源完成后再初始化游戏
    loadingScene = LoadingScene:new(function()
        OnLoadingComplete()
    end)

    SubscribeToEvent("Update", "HandleUpdate")
    log:Write(LOG_INFO, "[Game] Loading started")
end

--- 预加载完成后，初始化基础设施（场景、相机、菜单），等待玩家选择模式
function OnLoadingComplete()
    loadingScene = nil
    gameReady = true

    CreateScene()
    SetupCamera()

    -- 创建输入管理器
    inputManager = InputManager:new()

    -- 创建菜单覆盖层（默认显示，挡住游戏画面）
    menuOverlay = MenuOverlay:new()

    -- Game Over UI（默认隐藏）
    _createGameOverUI()

    -- 暂停UI（默认隐藏）
    _createPauseUI()

    -- 初始状态：菜单显示，物理暂停
    physicsWorld_.enabled = false

    log:Write(LOG_INFO, "[Game] Base systems initialized, waiting for mode selection")
end

--- 初始化游戏对象（根据已加载的模式脚本创建关卡内容）
function InitGameObjects()
    -- 销毁旧UI元素（防止重启时UI累积导致黑屏）
    if sensesSystem then
        sensesSystem:destroy()
        sensesSystem = nil
    end
    if gameUI then
        gameUI:destroy()
        gameUI = nil
    end
    if cardUI then
        cardUI:destroy()
        cardUI = nil
    end
    if portalUI then
        portalUI:destroy()
        portalUI = nil
    end
    -- 移除旧敌人的UI元素（HP条 + 飘字）
    for _, e in ipairs(enemies) do
        if e.hpBarContainer then
            e.hpBarContainer:Remove()
        end
        if e.floatingTexts then
            for _, ft in ipairs(e.floatingTexts) do
                if ft.text then ft.text:Remove() end
            end
            e.floatingTexts = {}
        end
    end

    -- 清空旧敌人列表
    enemies = {}

    -- === 使用关卡管理器构建关卡 ===
    if not levelManager then
        levelManager = LevelManager:new()
    end

    -- === 关卡背景 ===
    local BG_IMAGES = {
        "image/backgrounds/dungeon_rooms/room1_entrance.png",
        "image/backgrounds/dungeon_rooms/room2_prison.png",
        "image/backgrounds/dungeon_rooms/room3_sewer.png",
        "image/backgrounds/dungeon_rooms/room4_altar.png",
        "image/backgrounds/dungeon_rooms/room5_boss_throne.png",
    }
    -- 获取地形配置（需要先获取 groundWidth 用于背景缩放）
    local groundWidth, platforms = levelManager:getGroundConfig()

    -- === 关卡背景（按比例适配屏幕视野，cover策略）===
    local bgPath = BG_IMAGES[levelManager:getCurrentLevel()] or BG_IMAGES[1]
    local bgNode = scene_:CreateChild("Background")
    bgNode.position = Vector3(0, 0, 0)
    local bgSprite = bgNode:CreateComponent("StaticSprite2D")
    bgSprite.orderInLayer = -100  -- 最底层绘制
    local bgRes = cache:GetResource("Sprite2D", bgPath)
    if bgRes then
        bgSprite:SetSprite(bgRes)
        local bgTexture = bgRes:GetTexture()
        local texW = bgTexture:GetWidth() / 100.0   -- 纹理宽（单位：米）
        local texH = bgTexture:GetHeight() / 100.0  -- 纹理高（单位：米）
        -- 相机视野尺寸
        local viewH = camera_.orthoSize * 2
        local aspect = graphics:GetWidth() / graphics:GetHeight()
        local viewW = viewH * aspect
        -- cover 策略：取较大缩放比，保证背景覆盖整个视野且不变形
        local scale = math.max(viewW / texW, viewH / texH)
        bgNode:SetScale(scale)
    end

    -- 主地面
    Ground:new(scene_, 0, -3.0, groundWidth, 1.0)
    -- 浮空平台
    for _, p in ipairs(platforms) do
        Ground:new(scene_, p.x, p.y, p.w, p.h)
    end

    -- 创建玩家
    player = Player:new(scene_, inputManager)

    -- 从关卡管理器获取敌人配置
    local levelEnemies = levelManager:generateEnemies()
    for _, info in ipairs(levelEnemies) do
        local e = Enemy:new(scene_, camera_, player, info.x, info.y, info.element, info.boss)
        table.insert(enemies, e)
    end
    player.enemies = enemies  -- 攻击时动态查找最近敌人
    -- 给每个敌人赋值友军列表（用于前方检测）
    for _, e in ipairs(enemies) do
        e.enemyList = enemies
    end

    -- 创建游戏UI（含BACK按钮，默认隐藏）
    gameUI = GameUI:new(inputManager, player)
    gameUI:setLevel(levelManager:getCurrentLevel(), levelManager.maxLevel)

    -- 创建五感剥夺系统
    sensesSystem = SensesSystem:new(scene_, player, gameUI)
    player.sensesSystem = sensesSystem  -- 让玩家能读取漂移值
    gameUI.sensesSystem = sensesSystem  -- 让UI能读取倒计时异常

    -- 创建卡牌系统
    cardSystem = CardSystem:new()
    cardUI = CardUI:new(cardSystem)
    cardSkills = CardSkills:new(scene_, player, enemies, cardSystem)
    gameUI.cardSystem = cardSystem  -- 绑定卡牌倒计时到顶部UI
    -- 给敌人赋予卡牌系统引用（用于冻结/减速）
    for _, e in ipairs(enemies) do
        e.cardSystem = cardSystem
    end

    -- 卡牌系统回调：施法开始/结束通知玩家
    cardSystem.onCastStart = function()
        player.castingCard = true
    end
    cardSystem.onCastEnd = function()
        player.castingCard = false
    end
    -- 卡牌使用效果回调：执行技能
    cardSystem.onCardUsed = function(card)
        cardSkills:execute(card)
    end

    -- 设置玩家受伤回调：触发五感剥夺
    player.onDamagedCallback = function()
        local sense = sensesSystem:onPlayerDamaged()
        if sense then
            log:Write(LOG_INFO, "[Game] Sense deprived: " .. sense)
        end
    end

    -- 设置玩家死亡回调
    player.gameOverCallback = function()
        ShowGameOver()
    end

    -- === 传送门系统 ===
    portalUI = PortalUI:new()
    levelManager:createPortal(scene_)

    -- 传送门回调
    levelManager.onPortalActivated = function()
        portalUI:showPortalHint()
        log:Write(LOG_INFO, "[Game] Portal activated - Level " .. levelManager:getCurrentLevel())
    end
    levelManager.onTeleportStart = function()
        portalUI:showCharging()
    end
    levelManager.onTeleportProgress = function(progress)
        portalUI:setProgress(progress)
        if progress <= 0 then
            portalUI:hideCharging()
        end
    end
    levelManager.onTeleportComplete = function(nextLevel)
        portalUI:showComplete()
        -- 延迟0.5秒后切换关卡
        _scheduleLevelTransition(nextLevel)
    end
    levelManager.onEnemiesNotCleared = function()
        portalUI:showEnemiesNotCleared()
    end
    levelManager.onGameComplete = function()
        -- 通关！显示通关提示，延迟后回到主菜单
        portalUI:showGameComplete()
        _scheduleReturnToMenu(3.0)
    end

    log:Write(LOG_INFO, "[Game] Game objects initialized for mode: " .. (currentMode or "unknown") .. " Level: " .. levelManager:getCurrentLevel())
end

--- 延迟切换关卡（传送完成后调用）
local transitionTimer = nil
local transitionTarget = nil
local returnToMenuTimer = nil

function _scheduleLevelTransition(nextLevel)
    transitionTimer = 0.5
    transitionTarget = nextLevel
end

function _scheduleReturnToMenu(delay)
    returnToMenuTimer = delay or 3.0
end

--- 执行关卡切换：重建场景，保留玩家状态
function _doLevelTransition(nextLevel)
    log:Write(LOG_INFO, "[Game] === Transitioning to Level " .. nextLevel .. " ===")

    -- 重建场景
    CreateScene()
    SetupCamera()

    -- 重新初始化游戏对象（levelManager.currentLevel 已更新）
    InitGameObjects()

    -- 启动新关卡
    cameraNode.position = Vector3(0, -1.9, -10)
    physicsWorld_.enabled = true
    scene_.updateEnabled = true
    gamePaused = false
    gameUI:show()
    gameUI:resetCountdown()
    cardSystem:reset()
    cardSkills:reset()
    cardUI:show()

    log:Write(LOG_INFO, "[Game] Level " .. nextLevel .. " started!")
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -9.81)

    -- 方向光（DiffAlpha 材质需要光照才能正确显示精灵颜色）
    local lightNode = scene_:CreateChild("DirectionalLight")
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1, 1, 1, 1)
    lightNode.direction = Vector3(0, 0, 1)
end

function SetupCamera()
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)

    camera_ = cameraNode:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = 5.2

    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.defaultZone.fogColor = Color(0.05, 0.05, 0.08, 1.0)  -- 深色背景匹配地牢
end

--- 从菜单进入游戏：加载模式脚本、重建场景、初始化对象
function EnterGame(mode)
    -- 加载对应模式的脚本
    LoadModeScripts(mode)

    -- 重置关卡管理器（从第一关开始）
    if levelManager then
        levelManager:reset()
    else
        levelManager = LevelManager:new()
    end
    -- 清除切换计时器
    transitionTimer = nil
    transitionTarget = nil

    -- 重建场景（彻底清除旧游戏对象）
    CreateScene()
    SetupCamera()

    -- 初始化游戏对象
    InitGameObjects()

    -- 启动游戏
    cameraNode.position = Vector3(0, -1.9, -10)
    physicsWorld_.enabled = true
    scene_.updateEnabled = true
    gamePaused = false
    if pausePanel then pausePanel.visible = false end
    gameUI:show()
    gameUI:resetCountdown()
    cardSystem:reset()
    cardSkills:reset()
    cardUI:show()
    log:Write(LOG_INFO, "[Game] Enter game - mode: " .. mode)
end

--- 从游戏回到菜单：隐藏游戏UI，暂停物理
function ReturnToMenu()
    physicsWorld_.enabled = false
    gamePaused = false
    if pausePanel then pausePanel.visible = false end
    gameUI:hide()
    cardUI:hide()
    for _, e in ipairs(enemies) do
        e:hideHpBar()
    end
    menuOverlay:show()
    log:Write(LOG_INFO, "[Game] Return to menu")
end

-- 菜单按钮回调：START → 显示模式选择
function HandleMenuShowSelect(eventType, eventData)
    menuOverlay:showSelect()
end

-- 模式选择：测试房间（加载 test_room 目录脚本）
function HandleModeTest(eventType, eventData)
    menuOverlay:hide()
    EnterGame("test_room")
end

-- 模式选择：普通模式（加载 normal_mode 目录脚本）
function HandleModeNormal(eventType, eventData)
    menuOverlay:hide()
    EnterGame("normal_mode")
end

-- 模式选择：无尽模式（未开发提示）
function HandleModeEndless(eventType, eventData)
    menuOverlay:hide()
    ShowComingSoon()
    log:Write(LOG_INFO, "[Game] Mode: Endless (coming soon)")
end

-- 模式选择：返回标题页
function HandleModeBack(eventType, eventData)
    menuOverlay:showTitle()
end

-- 旧接口保留兼容
function HandleMenuStart(eventType, eventData)
    menuOverlay:showSelect()
end

-- 菜单按钮回调：退出游戏
function HandleMenuExit(eventType, eventData)
    engine:Exit()
end

-- 游戏中BACK按钮回调：回到菜单
function HandleBackToMenu(eventType, eventData)
    ReturnToMenu()
end

-- 测试按钮回调：触发Boss大招动画
function HandleTestBossSkill(eventType, eventData)
    for _, e in ipairs(enemies) do
        if e.isBoss and e:isAlive() then
            e:_startSkill()
            log:Write(LOG_INFO, "[Game] Test: Boss skill triggered manually!")
            break
        end
    end
end

-- 无尽模式：未开发提示
local comingSoonPanel = nil

function ShowComingSoon()
    if comingSoonPanel then
        comingSoonPanel.visible = true
        return
    end

    local uiRoot = ui.root

    comingSoonPanel = UIElement:new()
    uiRoot:AddChild(comingSoonPanel)
    comingSoonPanel:SetSize(graphics.width, graphics.height)
    comingSoonPanel:SetAlignment(HA_CENTER, VA_CENTER)
    comingSoonPanel:SetPriority(1100)

    -- 背景遮罩
    local bg = BorderImage:new()
    comingSoonPanel:AddChild(bg)
    bg:SetSize(graphics.width, graphics.height)
    bg:SetPosition(0, 0)
    bg.color = Color(0.95, 0.95, 0.98, 1.0)

    -- 提示文字
    local msg = Text:new()
    comingSoonPanel:AddChild(msg)
    msg:SetStyleAuto()
    msg.text = "未开发请敬请期待"
    msg:SetFontSize(28)
    msg:SetAlignment(HA_CENTER, VA_CENTER)
    msg:SetPosition(0, -30)
    msg.color = Color(0.3, 0.3, 0.4, 1.0)

    -- 返回按钮
    local btnBack = Button:new()
    comingSoonPanel:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(160, 50)
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, 40)

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "返回"
    backText:SetFontSize(22)
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandleComingSoonBack")
end

function HandleComingSoonBack(eventType, eventData)
    if comingSoonPanel then
        comingSoonPanel.visible = false
    end
    menuOverlay:show()
end

-- UI按钮回调
function HandleUILeftPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_LEFT, true)
end

function HandleUILeftReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
end

function HandleUIRightPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_RIGHT, true)
end

function HandleUIRightReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
end

function HandleUIJumpPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_JUMP, true)
end

function HandleUIJumpReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
end

function HandleUIAttackPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_ATTACK, true)
end

function HandleUIAttackReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
end

-- 卡牌按钮点击回调（通过cardUI查询真实hand索引）
function HandleCardBtn1(eventType, eventData)
    local idx = cardUI and cardUI:getHandIndex(1)
    if idx then cardSystem:useCard(idx) end
end
function HandleCardBtn2(eventType, eventData)
    local idx = cardUI and cardUI:getHandIndex(2)
    if idx then cardSystem:useCard(idx) end
end
function HandleCardBtn3(eventType, eventData)
    local idx = cardUI and cardUI:getHandIndex(3)
    if idx then cardSystem:useCard(idx) end
end
function HandleCardBtn4(eventType, eventData)
    local idx = cardUI and cardUI:getHandIndex(4)
    if idx then cardSystem:useCard(idx) end
end
function HandleCardBtn5(eventType, eventData)
    local idx = cardUI and cardUI:getHandIndex(5)
    if idx then cardSystem:useCard(idx) end
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 预加载阶段：只更新 Loading 界面
    if loadingScene then
        loadingScene:update(dt)
        return
    end

    -- 游戏未就绪时不执行逻辑
    if not gameReady then return end

    -- 菜单显示时暂停游戏逻辑
    if menuOverlay:isVisible() then
        return
    end

    -- Tab键 或 手机返回键(Escape) 触发暂停/恢复
    if input:GetKeyPress(KEY_TAB) or input:GetKeyPress(KEY_ESCAPE) then
        if not gamePaused then
            -- 进入暂停：冻结场景（物理+动画全部停止）
            gamePaused = true
            scene_.updateEnabled = false
            if pausePanel then pausePanel.visible = true end
            log:Write(LOG_INFO, "[Game] Paused")
        else
            -- 恢复游戏：恢复场景更新
            gamePaused = false
            scene_.updateEnabled = true
            if pausePanel then pausePanel.visible = false end
            log:Write(LOG_INFO, "[Game] Resumed")
        end
        return
    end

    -- 暂停时不更新游戏逻辑
    if gamePaused then
        return
    end

    -- 游戏对象未初始化时不更新
    if not player then return end

    -- 更新输入
    inputManager:update()

    -- 更新玩家
    player:update(dt)

    -- 更新所有敌人
    for _, e in ipairs(enemies) do
        e:update(dt)
    end

    -- 更新卡牌系统
    cardSystem:update(dt)
    cardSkills:update(dt)
    cardUI:update(dt)

    -- 键盘快捷键开牌：根据手牌数动态映射右侧按键
    -- 5张=YUIOP, 4张=UIOP, 3张=IOP, 2张=OP, 1张=P
    local CARD_KEYS = { KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P }
    local handCount = cardUI and cardUI:getHandCount() or 0
    if handCount > 0 then
        local keyOffset = 5 - handCount  -- 从第几个键开始
        for i = 1, handCount do
            if input:GetKeyPress(CARD_KEYS[keyOffset + i]) then
                local idx = cardUI:getHandIndex(i)
                if idx then cardSystem:useCard(idx) end
                break
            end
        end
    end

    -- 更新五感剥夺系统
    sensesSystem:update(dt)

    -- 更新UI（血量显示+倒计时）
    gameUI:update(dt)

    -- 更新关卡管理器（传送门检测）
    if levelManager and not player:isDead() then
        local playerPos = player:getPosition()
        levelManager:update(dt, playerPos, enemies)
    end

    -- 更新传送门 UI（提示自动隐藏计时）
    if portalUI then
        portalUI:update(dt)
    end

    -- 关卡切换延迟计时器
    if transitionTimer then
        transitionTimer = transitionTimer - dt
        if transitionTimer <= 0 then
            local target = transitionTarget
            transitionTimer = nil
            transitionTarget = nil
            _doLevelTransition(target)
            return  -- 本帧不再执行后续逻辑（场景已重建）
        end
    end

    -- 通关回到主菜单计时器
    if returnToMenuTimer then
        returnToMenuTimer = returnToMenuTimer - dt
        if returnToMenuTimer <= 0 then
            returnToMenuTimer = nil
            HandleRestart()
            return
        end
    end

    -- 相机延迟跟随玩家
    local targetPos = player:getPosition()
    local camPos = cameraNode.position
    local lerpSpeed = 3.0
    local newX = camPos.x + (targetPos.x - camPos.x) * lerpSpeed * dt
    local newY = camPos.y + (targetPos.y - camPos.y) * lerpSpeed * dt
    cameraNode.position = Vector3(newX, newY, -10)

    -- 背景跟随相机
    local bgNode = scene_:GetChild("Background")
    if bgNode then
        bgNode.position = Vector3(newX, newY, 0)
    end
end

-- 暂停UI
function _createPauseUI()
    local uiRoot = ui.root

    -- 暂停面板（半透明遮罩 + Back/Leave 按钮）
    pausePanel = UIElement:new()
    uiRoot:AddChild(pausePanel)
    pausePanel:SetSize(graphics.width, graphics.height)
    pausePanel:SetAlignment(HA_CENTER, VA_CENTER)
    pausePanel.priority = 1000

    -- 半透明黑色背景
    local bg = BorderImage:new()
    pausePanel:AddChild(bg)
    bg:SetSize(graphics.width, graphics.height)
    bg:SetPosition(0, 0)
    bg.color = Color(0, 0, 0, 0.7)

    -- "PAUSED" 标题
    local title = Text:new()
    pausePanel:AddChild(title)
    title:SetStyleAuto()
    title.text = "PAUSED"
    title:SetFontSize(36)
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, -60)
    title.color = Color(1.0, 1.0, 1.0, 1.0)

    -- Back 按钮（返回游戏）
    local btnBack = Button:new()
    pausePanel:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(180, 55)
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, 10)

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "Back"
    backText:SetFontSize(24)
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandlePauseBack")

    -- Leave 按钮（返回标题页）
    local btnLeave = Button:new()
    pausePanel:AddChild(btnLeave)
    btnLeave:SetStyleAuto()
    btnLeave:SetSize(180, 55)
    btnLeave:SetAlignment(HA_CENTER, VA_CENTER)
    btnLeave:SetPosition(0, 80)

    local leaveText = Text:new()
    btnLeave:AddChild(leaveText)
    leaveText:SetStyleAuto()
    leaveText.text = "Leave"
    leaveText:SetFontSize(24)
    leaveText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnLeave, "Released", "HandlePauseLeave")

    pausePanel.visible = false
end

-- 暂停菜单：Back（返回游戏）
function HandlePauseBack(eventType, eventData)
    gamePaused = false
    scene_.updateEnabled = true
    if pausePanel then pausePanel.visible = false end
    log:Write(LOG_INFO, "[Game] Resumed")
end

-- 暂停菜单：Leave（返回标题页）
function HandlePauseLeave(eventType, eventData)
    gamePaused = false
    scene_.updateEnabled = true
    if pausePanel then pausePanel.visible = false end
    ReturnToMenu()
    log:Write(LOG_INFO, "[Game] Leave to title")
end

-- Game Over UI
local gameOverContainer = nil

function _createGameOverUI()
    local uiRoot = ui.root
    local w = uiRoot.width
    local h = uiRoot.height

    -- 直接用 BorderImage 作为容器（单层，避免双重遮罩）
    gameOverContainer = BorderImage:new()
    uiRoot:AddChild(gameOverContainer)
    gameOverContainer:SetSize(w, h)
    gameOverContainer:SetAlignment(HA_LEFT, VA_TOP)
    gameOverContainer:SetPosition(0, 0)
    gameOverContainer.priority = 900
    gameOverContainer.color = Color(0, 0, 0, 0.85)

    -- Game Over 文字（居中）
    local title = Text:new()
    gameOverContainer:AddChild(title)
    title:SetStyleAuto()
    title.text = "GAME OVER"
    title:SetFontSize(48)
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, -40)
    title.color = Color(1.0, 0.2, 0.2, 1.0)

    -- 重新开始按钮（居中，文字下方）
    local restartBtn = Button:new()
    gameOverContainer:AddChild(restartBtn)
    restartBtn:SetStyleAuto()
    restartBtn:SetSize(160, 50)
    restartBtn:SetAlignment(HA_CENTER, VA_CENTER)
    restartBtn:SetPosition(0, 40)

    local btnText = Text:new()
    restartBtn:AddChild(btnText)
    btnText:SetStyleAuto()
    btnText.text = "返回菜单"
    btnText:SetFontSize(22)
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(restartBtn, "Released", "HandleRestart")

    gameOverContainer.visible = false
end

function ShowGameOver()
    if gameOverContainer then
        -- 动态获取当前屏幕尺寸，确保全屏覆盖
        local w = ui.root.width
        local h = ui.root.height
        gameOverContainer:SetSize(w, h)
        gameOverContainer.visible = true
    end
    physicsWorld_.enabled = false
    gamePaused = false
    if pausePanel then pausePanel.visible = false end
    gameUI:hide()
    cardUI:hide()
    for _, e in ipairs(enemies) do
        e:hideHpBar()
    end
    log:Write(LOG_INFO, "[Game] Game Over!")
end

function HandleRestart(eventType, eventData)
    if gameOverContainer then
        gameOverContainer.visible = false
    end
    -- 销毁游戏UI，回到主菜单
    if sensesSystem then
        sensesSystem:destroy()
        sensesSystem = nil
    end
    if gameUI then
        gameUI:destroy()
        gameUI = nil
    end
    if cardUI then
        cardUI:destroy()
        cardUI = nil
    end
    if portalUI then
        portalUI:destroy()
        portalUI = nil
    end
    for _, e in ipairs(enemies) do
        if e.hpBarContainer then
            e.hpBarContainer:Remove()
        end
        if e.floatingTexts then
            for _, ft in ipairs(e.floatingTexts) do
                if ft.text then ft.text:Remove() end
            end
            e.floatingTexts = {}
        end
    end
    enemies = {}
    player = nil
    -- 重置关卡和切换计时器
    if levelManager then
        levelManager:reset()
    end
    transitionTimer = nil
    transitionTarget = nil
    returnToMenuTimer = nil
    physicsWorld_.enabled = false
    menuOverlay:show()
    log:Write(LOG_INFO, "[Game] Game Over -> Return to menu")
end

function Stop()
    log:Write(LOG_INFO, "[Game] Stopped")
end
