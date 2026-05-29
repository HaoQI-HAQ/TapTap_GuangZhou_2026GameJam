-- ============================================================================
-- game_01 场景模块 - 主协调器
-- 职责: 创建场景、连接 Player/Enemy/GameUI 各模块、事件分发
-- ============================================================================

local UI = require("urhox-libs/UI")
local Player = require("Player")
local Enemy = require("Enemy")
local GameUI = require("GameUI")

local Game01 = {}

-- ============================================================================
-- 场景级变量
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil

-- 模块实例
local player_ = nil   ---@type table Player instance
local enemy_ = nil    ---@type table Enemy instance
local gameUI_ = nil   ---@type table GameUI instance

-- 游戏状态
local gameOver_ = false
local countdownTime_ = 5.0
local countdownMax_ = 5.0

-- ============================================================================
-- 配置（场景级）
-- ============================================================================
local CONFIG = {
    Gravity = 20.0,
    CameraOrthoSize = 7.2,
}

-- ============================================================================
-- 生命周期
-- ============================================================================

function Game01.Start()
    InitUI()
    CreateScene()
    SetupViewport()
    CreateGameContent()
    CreateGameUIModule()
    SubscribeToEvents()
    print("=== 2D Action Prototype Started ===")
end

function Game01.Stop()
    UnsubscribeFromAllEvents()

    if player_ then
        player_:Destroy()
        player_ = nil
    end
    if enemy_ then
        enemy_:Destroy()
        enemy_ = nil
    end
    if gameUI_ then
        gameUI_:Destroy()
        gameUI_ = nil
    end
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end

    cameraNode_ = nil
    gameOver_ = false
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
end

function SetupViewport()
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = CONFIG.CameraOrthoSize
    cameraNode_.position = Vector3(0, 2, -10)

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

-- ============================================================================
-- 游戏内容
-- ============================================================================

function CreateGameContent()
    -- 背景色
    renderer.defaultZone.fogColor = Color(0.15, 0.15, 0.25, 1.0)

    -- 地面平台
    CreatePlatform(0, -0.5, 20.0, 1.0)

    -- 创建玩家
    player_ = Player.New(scene_)
    player_:Create(0, 1.5)

    -- 创建小怪
    enemy_ = Enemy.New(scene_)
    enemy_:Create(Enemy.CONFIG.SpawnX, 0.3)
end

function CreatePlatform(x, y, w, h)
    local node = scene_:CreateChild("Platform")
    node.position = Vector3(x, y, 0)

    local sprite = node:CreateComponent("StaticModel")
    sprite:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.5, 0.3, 1.0)))
    sprite:SetMaterial(mat)
    node:SetScale(Vector3(w, h, 1.0))

    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC

    local shape = node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(w, h)
    shape.friction = 0.5

    return node
end

-- ============================================================================
-- UI 模块连接
-- ============================================================================

function CreateGameUIModule()
    gameUI_ = GameUI.New()
    gameUI_:Create(player_.maxHP_)

    -- 绑定 UI 回调
    gameUI_.onAttack = function()
        HandleAttack()
    end
    gameUI_.onJump = function()
        if player_ then player_.wantJump_ = true end
    end
    gameUI_.onRestart = function()
        RestartGame()
    end
    gameUI_.onTouchLeft = function(pressed)
        if player_ then player_.touchLeft_ = pressed end
    end
    gameUI_.onTouchRight = function(pressed)
        if player_ then player_.touchRight_ = pressed end
    end
end

-- ============================================================================
-- 攻击逻辑（协调 Player 和 Enemy）
-- ============================================================================

function HandleAttack()
    if not player_ or gameOver_ then return end

    local attacked = player_:TryAttack()
    if not attacked then return end

    -- 检测是否命中小怪
    if enemy_ and not enemy_:IsDead() then
        local playerPos = player_:GetPosition2D()
        local enemyPos = enemy_.node_.position2D
        if playerPos then
            local dist = (enemyPos - playerPos):Length()
            if dist <= player_:GetAttackRange() then
                enemy_:TakeDamage(player_:GetAttackDamage())
                print("Hit enemy! HP=" .. enemy_.hp_ .. "/" .. enemy_.maxHP_)
            end
        end
    end
end

-- ============================================================================
-- 事件
-- ============================================================================

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if gameOver_ then return end

    -- 更新玩家
    if player_ then
        player_:Update(dt)
    end

    -- 更新小怪 AI
    if enemy_ then
        local playerPos = player_ and player_:GetPosition2D() or nil
        local event = enemy_:Update(dt, playerPos)

        -- 小怪攻击命中玩家
        if event == "attack_hit" and player_ then
            local remainHP = player_:TakeDamage(enemy_:GetAttackDamage())
            print("Enemy attacks! Player HP=" .. remainHP .. "/" .. player_.maxHP_)
            if player_:IsDead() then
                ShowGameOver()
                return
            end
        end

        -- 攻击范围提示
        if gameUI_ then
            gameUI_:ShowAttackTip(enemy_:IsInAttackState())
        end
    end

    -- 倒计时
    UpdateCountdown(dt)

    -- 相机跟随
    UpdateCamera(dt)

    -- 更新 HP UI
    if gameUI_ and player_ then
        gameUI_:UpdateHP(player_.hp_)
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandlePostUpdate(eventType, eventData)
    if enemy_ then
        enemy_:UpdateHPBar()
    end
end

---@param eventType string
---@param eventData PhysicsBeginContact2DEventData
function HandleCollisionBegin(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    local isPlayerContact = (nodeA and nodeA.name == "Player") or (nodeB and nodeB.name == "Player")
    if not isPlayerContact then return end

    if player_ then
        player_:OnCollisionBegin()
    end
end

---@param eventType string
---@param eventData PhysicsEndContact2DEventData
function HandleCollisionEnd(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    local isPlayerContact = (nodeA and nodeA.name == "Player") or (nodeB and nodeB.name == "Player")
    if not isPlayerContact then return end

    if player_ then
        player_:OnCollisionEnd()
    end
end

-- ============================================================================
-- 游戏流程
-- ============================================================================

function UpdateCountdown(dt)
    countdownTime_ = countdownTime_ - dt
    if countdownTime_ <= 0 then
        countdownTime_ = countdownMax_
    end
    if gameUI_ then
        gameUI_:UpdateCountdown(countdownTime_)
    end
end

function UpdateCamera(dt)
    if not player_ or not player_.node_ or not cameraNode_ then return end
    local targetX = player_.node_.position.x
    local targetY = player_.node_.position.y + 1.5
    local camPos = cameraNode_.position
    local lerpSpeed = 6.0
    cameraNode_.position = Vector3(
        camPos.x + (targetX - camPos.x) * lerpSpeed * dt,
        camPos.y + (targetY - camPos.y) * lerpSpeed * dt,
        camPos.z
    )
end

function ShowGameOver()
    gameOver_ = true
    if player_ then
        player_:Destroy()
    end
    if gameUI_ then
        gameUI_:ShowGameOver(true)
    end
end

function RestartGame()
    gameOver_ = false

    -- 重置玩家
    if player_ then
        player_:Reset(0, 1.5)
    end

    -- 重置小怪
    if enemy_ then
        enemy_:Reset()
    end

    -- 重置倒计时
    countdownTime_ = countdownMax_

    -- 隐藏游戏结束面板
    if gameUI_ then
        gameUI_:ShowGameOver(false)
        gameUI_:ShowAttackTip(false)
    end

    print("=== Game Restarted ===")
end

return Game01
