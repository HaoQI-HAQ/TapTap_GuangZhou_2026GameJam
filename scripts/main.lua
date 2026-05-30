-- ============================================================================
-- 《54321》主入口 - 2D动作卡牌游戏
-- 架构: scaffold-2d-physics + 模块化系统
-- ============================================================================

local UI = require("urhox-libs/UI")
local CONFIG = require("config")
local InputManager = require("input_manager")
local Player = require("player")
local Enemy = require("enemy")
local CardSystem = require("card_system")
local Ground = require("ground")
local GameUI = require("game_ui")

-- ============================================================================
-- 全局状态
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil

local inputMgr_ = nil
local player_ = nil
local enemies_ = {}
local cardSystem_ = nil
local gameUI_ = nil
local grounds_ = {}

local gameState_ = "playing"  -- playing / dead / victory

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title
    math.randomseed(os.time())

    -- 1. UI系统初始化
    InitUI()

    -- 2. 创建场景
    CreateScene()

    -- 3. 设置相机
    SetupViewport()

    -- 4. 创建游戏内容
    CreateGameContent()

    -- 5. 创建游戏HUD
    CreateGameUI()

    -- 6. 订阅事件
    SubscribeToEvents()

    log:Write(LOG_INFO, "=== 54321 Game Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local physicsWorld = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld.gravity = Vector2(0, -CONFIG.Gravity)

    -- 背景色(深灰蓝)
    local zone = scene_:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-100, -100, -100), Vector3(100, 100, 100))
    zone.fogColor = Color(0.08, 0.08, 0.12, 1.0)
    renderer.defaultZone = zone
end

function SetupViewport()
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = CONFIG.CameraOrthoSize
    cameraNode_.position = Vector3(0, CONFIG.CameraOffsetY, -10)

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

function CreateGameContent()
    -- 输入管理器
    inputMgr_ = InputManager:new()

    -- 地面(主平台)
    grounds_[#grounds_ + 1] = Ground:new(scene_, 0, -1, 20, 0.5, { 0.2, 0.45, 0.15, 1.0 })
    -- 浮空平台
    grounds_[#grounds_ + 1] = Ground:new(scene_, -3, 1.5, 3, 0.3, { 0.3, 0.35, 0.25, 1.0 })
    grounds_[#grounds_ + 1] = Ground:new(scene_, 3, 2.5, 2.5, 0.3, { 0.3, 0.35, 0.25, 1.0 })
    grounds_[#grounds_ + 1] = Ground:new(scene_, 0, 4.0, 2, 0.3, { 0.3, 0.35, 0.25, 1.0 })

    -- 玩家
    player_ = Player:new(scene_, inputMgr_)

    -- 卡牌系统
    cardSystem_ = CardSystem:new()

    -- 生成怪物(3只)
    SpawnEnemies()
end

function SpawnEnemies()
    enemies_ = {}
    local positions = { { 4, 0 }, { -4, 0 }, { 0, 5 } }
    for i, pos in ipairs(positions) do
        local element = CONFIG.Elements[((i - 1) % #CONFIG.Elements) + 1]
        local enemy = Enemy:new(scene_, pos[1], pos[2], element)
        enemies_[#enemies_ + 1] = enemy
    end
end

function CreateGameUI()
    gameUI_ = GameUI:new(inputMgr_)
    gameUI_:build()

    -- 卡牌点击回调
    gameUI_:setOnCardUse(function(index)
        UseCard(index)
    end)
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
end

-- ============================================================================
-- 游戏循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if gameState_ ~= "playing" then return end

    -- 输入
    inputMgr_:update()

    -- 玩家更新
    player_:update(dt)

    -- 卡牌系统
    cardSystem_:update(dt)

    -- 怪物更新
    local playerPos = player_:getPosition()
    for _, enemy in ipairs(enemies_) do
        enemy:update(dt, playerPos)
    end

    -- 战斗逻辑
    HandleCombat(dt)

    -- UI 更新
    UpdateGameUI()

    -- 死亡检测
    if player_:isDead() then
        gameState_ = "dead"
        ShowGameOver()
    end

    -- 胜利检测
    if CheckVictory() then
        gameState_ = "victory"
        ShowVictory()
    end
end

---@param eventType string
---@param eventData PostUpdateEventData
function HandlePostUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 相机跟随
    if player_ and player_.node then
        local targetPos = player_:getPosition()
        local camPos = cameraNode_.position
        local lerpSpeed = CONFIG.CameraFollowSpeed * dt
        cameraNode_.position = Vector3(
            camPos.x + (targetPos.x - camPos.x) * lerpSpeed,
            camPos.y + (targetPos.y + CONFIG.CameraOffsetY - camPos.y) * lerpSpeed,
            camPos.z
        )
    end
end

-- ============================================================================
-- 战斗系统
-- ============================================================================

function HandleCombat(dt)
    -- 玩家攻击判定
    local atkType, comboStep = player_:consumeAttack()
    if atkType then
        local damage = (atkType == "heavy") and CONFIG.HeavyAttackDamage or CONFIG.LightAttackDamage
        local pos = player_:getPosition()
        local dir = player_.facingRight and 1 or -1
        -- 检测攻击范围内的怪物
        for _, enemy in ipairs(enemies_) do
            if enemy.alive then
                local epos = enemy:getPosition()
                local dx = epos.x - pos.x
                if math.abs(dx) <= CONFIG.AttackRange and math.abs(epos.y - pos.y) <= 1.5 then
                    if (dir > 0 and dx >= 0) or (dir < 0 and dx <= 0) then
                        enemy:takeDamage(damage)
                    end
                end
            end
        end
    end

    -- 下砸判定
    local slamDmg, slamH = player_:consumeSlam()
    if slamDmg then
        local pos = player_:getPosition()
        -- AOE伤害(半径内所有怪物)
        for _, enemy in ipairs(enemies_) do
            if enemy.alive then
                local epos = enemy:getPosition()
                local dist = math.abs(epos.x - pos.x)
                if dist <= CONFIG.SlamAOERange and math.abs(epos.y - pos.y) <= 1.0 then
                    local dmg = dist <= 0.5 and slamDmg or CONFIG.SlamAOEDamage
                    enemy:takeDamage(dmg)
                end
            end
        end
    end

    -- 怪物攻击玩家
    local playerPos = player_:getPosition()
    for _, enemy in ipairs(enemies_) do
        if enemy.alive and enemy:shouldDealDamage() then
            local epos = enemy:getPosition()
            local dist = math.abs(epos.x - playerPos.x)
            if dist <= CONFIG.EnemyAttackRange + 0.3 and math.abs(epos.y - playerPos.y) <= 1.0 then
                player_:takeDamage(CONFIG.EnemyAttackDamage)
            end
        end
    end
end

-- 使用卡牌
function UseCard(index)
    if gameState_ ~= "playing" then return end
    local card = cardSystem_:useCard(index)
    if not card then return end

    -- 找最近的怪物
    local target = FindNearestEnemy()
    if not target then return end

    -- 计算伤害
    local damage = cardSystem_:calculateDamage(card, target.element)
    if damage == -1 then
        -- 暴击(克制): 直接打到剩1血
        local critDmg = math.max(1, target.hp - 1)
        target:takeDamage(critDmg)
        log:Write(LOG_INFO, "[Card] CRIT! " .. (card.element or "none") .. " vs " .. target.element)
    elseif damage > 0 then
        target:takeDamage(damage)
    end

    -- 施法动画
    player_:startCast(CONFIG.CastAnimDuration)
end

function FindNearestEnemy()
    local playerPos = player_:getPosition()
    local nearest = nil
    local minDist = math.huge
    for _, enemy in ipairs(enemies_) do
        if enemy.alive then
            local dist = math.abs(enemy:getPosition().x - playerPos.x)
            if dist < minDist then
                minDist = dist
                nearest = enemy
            end
        end
    end
    return nearest
end

-- ============================================================================
-- UI 更新
-- ============================================================================

function UpdateGameUI()
    if not gameUI_ then return end
    gameUI_:updateHP(player_.hp, player_.maxHp)
    gameUI_:updateCountdown(cardSystem_:getCountdown(), cardSystem_.roundCount + 1)
    gameUI_:updateCards(cardSystem_:getHand())
    gameUI_:updateCombo(player_.comboStep)
    gameUI_:updateSenses(player_.lostSenses)
end

-- ============================================================================
-- 游戏状态
-- ============================================================================

function CheckVictory()
    for _, enemy in ipairs(enemies_) do
        if enemy.alive then return false end
    end
    return true
end

function ShowGameOver()
    local overlay = UI.Panel {
        id = "gameOverOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        gap = 16,
        children = {
            UI.Label {
                text = "GAME OVER",
                fontSize = 32,
                fontColor = { 255, 80, 80, 255 },
            },
            UI.Label {
                text = "视觉剥夺...你已无法感知世界",
                fontSize = 14,
                fontColor = { 200, 200, 200, 200 },
            },
            UI.Button {
                text = "重新开始",
                variant = "primary",
                onClick = function()
                    RestartGame()
                end,
            },
        }
    }
    UI.SetRoot(overlay)
end

function ShowVictory()
    local overlay = UI.Panel {
        id = "victoryOverlay",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        gap = 16,
        children = {
            UI.Label {
                text = "VICTORY",
                fontSize = 32,
                fontColor = { 80, 255, 120, 255 },
            },
            UI.Label {
                text = "所有怪物已被击败！",
                fontSize = 14,
                fontColor = { 200, 200, 200, 200 },
            },
            UI.Button {
                text = "继续挑战",
                variant = "primary",
                onClick = function()
                    RestartGame()
                end,
            },
        }
    }
    UI.SetRoot(overlay)
end

function RestartGame()
    -- 移除旧场景对象
    if player_ and player_.node then
        player_.node:Remove()
    end
    for _, enemy in ipairs(enemies_) do
        if enemy.node then enemy.node:Remove() end
    end

    -- 重新创建
    player_ = Player:new(scene_, inputMgr_)
    cardSystem_ = CardSystem:new()
    SpawnEnemies()
    gameState_ = "playing"

    -- 重建UI
    CreateGameUI()
end

-- ============================================================================
-- 物理碰撞
-- ============================================================================

---@param eventType string
---@param eventData PhysicsBeginContact2DEventData
function HandleCollisionBegin(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    if not nodeA or not nodeB then return end

    local nameA = nodeA:GetName()
    local nameB = nodeB:GetName()

    -- 玩家脚部传感器碰到地面
    if nameA == "Player" and nameB == "Ground" then
        player_:onGroundContact()
    elseif nameB == "Player" and nameA == "Ground" then
        player_:onGroundContact()
    end
end

---@param eventType string
---@param eventData PhysicsEndContact2DEventData
function HandleCollisionEnd(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    if not nodeA or not nodeB then return end

    local nameA = nodeA:GetName()
    local nameB = nodeB:GetName()

    if nameA == "Player" and nameB == "Ground" then
        player_:onGroundLeave()
    elseif nameB == "Player" and nameA == "Ground" then
        player_:onGroundLeave()
    end
end
