-- 2D横板平台游戏 - 主入口
require "LuaScripts/Utilities/Sample"
require "scripts/input_manager"
require "scripts/player"
require "scripts/ground"
require "scripts/game_ui"
require "scripts/enemy"
require "scripts/menu_overlay"

local scene_ = nil
local cameraNode = nil
local camera_ = nil
local player = nil
local gameUI = nil
local inputManager = nil
local menuOverlay = nil
local physicsWorld_ = nil
local enemies = {}

function Start()
    SampleStart()
    CreateScene()

    -- 创建输入管理器
    inputManager = InputManager:new()

    -- 创建地面
    Ground:new(scene_, 0, -3.0, 20.0, 1.0)

    -- 创建玩家
    player = Player:new(scene_, inputManager)

    -- 设置相机
    SetupCamera()

    -- 创建5种属性敌人（分布在玩家右边，间隔1.5米）
    local elementList = { "fire", "water", "thunder", "wind", "ice" }
    for i, elem in ipairs(elementList) do
        local xPos = 2.0 + (i - 1) * 1.5  -- 间隔1.5米
        local e = Enemy:new(scene_, camera_, player, xPos, -1.9, elem)
        table.insert(enemies, e)
    end
    player.enemies = enemies  -- 攻击时动态查找最近敌人

    -- 创建游戏UI（含BACK按钮，默认隐藏）
    gameUI = GameUI:new(inputManager, player)

    -- 设置玩家死亡回调
    player.gameOverCallback = function()
        ShowGameOver()
    end

    -- 创建菜单覆盖层（默认显示，挡住游戏画面）
    menuOverlay = MenuOverlay:new()
    
    -- Game Over UI（默认隐藏）
    _createGameOverUI()

    -- 初始状态：菜单显示，物理暂停
    physicsWorld_.enabled = false

    SubscribeToEvent("Update", "HandleUpdate")
    log:Write(LOG_INFO, "[Game] Started")
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -9.81)
end

function SetupCamera()
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)

    camera_ = cameraNode:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = 5.2

    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.defaultZone.fogColor = Color(0.6, 0.8, 1.0, 1.0)
end

--- 从菜单进入游戏：重置所有状态，显示游戏UI
function EnterGame()
    player:reset()
    for _, e in ipairs(enemies) do
        e:reset()
        e:showHpBar()
    end
    cameraNode.position = Vector3(0, -1.9, -10)
    physicsWorld_.enabled = true
    gameUI:show()
    gameUI:resetCountdown()
    log:Write(LOG_INFO, "[Game] Enter game scene")
end

--- 从游戏回到菜单：隐藏游戏UI，暂停物理
function ReturnToMenu()
    physicsWorld_.enabled = false
    gameUI:hide()
    for _, e in ipairs(enemies) do
        e:hideHpBar()
    end
    menuOverlay:show()
    log:Write(LOG_INFO, "[Game] Return to menu")
end

-- 菜单按钮回调：开始游戏
function HandleMenuStart(eventType, eventData)
    menuOverlay:hide()
    EnterGame()
end

-- 菜单按钮回调：退出游戏
function HandleMenuExit(eventType, eventData)
    engine:Exit()
end

-- 游戏中BACK按钮回调：回到菜单
function HandleBackToMenu(eventType, eventData)
    ReturnToMenu()
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

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 菜单显示时暂停游戏逻辑
    if menuOverlay:isVisible() then
        return
    end

    -- 更新输入
    inputManager:update()

    -- 更新玩家
    player:update(dt)

    -- 更新所有敌人
    for _, e in ipairs(enemies) do
        e:update(dt)
    end

    -- 更新UI（血量显示+倒计时）
    gameUI:update(dt)

    -- 相机延迟跟随玩家
    local targetPos = player:getPosition()
    local camPos = cameraNode.position
    local lerpSpeed = 3.0
    local newX = camPos.x + (targetPos.x - camPos.x) * lerpSpeed * dt
    local newY = camPos.y + (targetPos.y - camPos.y) * lerpSpeed * dt
    cameraNode.position = Vector3(newX, newY, -10)
end

-- Game Over UI
local gameOverContainer = nil

function _createGameOverUI()
    local uiRoot = ui.root

    gameOverContainer = UIElement:new()
    uiRoot:AddChild(gameOverContainer)
    gameOverContainer:SetSize(graphics.width, graphics.height)
    gameOverContainer:SetAlignment(HA_LEFT, VA_TOP)
    gameOverContainer.priority = 900

    -- 半透明黑色遮罩
    local bg = BorderImage:new()
    gameOverContainer:AddChild(bg)
    bg:SetSize(graphics.width, graphics.height)
    bg.color = Color(0, 0, 0, 0.8)

    -- Game Over 文字
    local title = Text:new()
    gameOverContainer:AddChild(title)
    title:SetStyleAuto()
    title.text = "GAME OVER"
    title:SetFontSize(48)
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, -30)
    title.color = Color(1.0, 0.2, 0.2, 1.0)

    -- 重新开始按钮
    local restartBtn = Button:new()
    gameOverContainer:AddChild(restartBtn)
    restartBtn:SetStyleAuto()
    restartBtn:SetSize(160, 50)
    restartBtn:SetAlignment(HA_CENTER, VA_CENTER)
    restartBtn:SetPosition(0, 40)

    local btnText = Text:new()
    restartBtn:AddChild(btnText)
    btnText:SetStyleAuto()
    btnText.text = "RESTART"
    btnText:SetFontSize(22)
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(restartBtn, "Released", "HandleRestart")

    gameOverContainer.visible = false
end

function ShowGameOver()
    if gameOverContainer then
        gameOverContainer.visible = true
    end
    physicsWorld_.enabled = false
    gameUI:hide()
    for _, e in ipairs(enemies) do
        e:hideHpBar()
    end
    log:Write(LOG_INFO, "[Game] Game Over!")
end

function HandleRestart(eventType, eventData)
    if gameOverContainer then
        gameOverContainer.visible = false
    end
    EnterGame()
end

function Stop()
    log:Write(LOG_INFO, "[Game] Stopped")
end
