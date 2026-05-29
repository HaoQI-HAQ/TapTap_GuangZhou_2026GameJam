-- 2D横板平台游戏 - 主入口
require "LuaScripts/Utilities/Sample"
require "scripts/input_manager"
require "scripts/player"
require "scripts/ground"
require "scripts/game_ui"

local scene_ = nil
local cameraNode = nil
local player = nil
local gameUI = nil
local inputManager = nil

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

    -- 创建UI（传入inputManager和player）
    gameUI = GameUI:new(inputManager, player)

    SubscribeToEvent("Update", "HandleUpdate")
    log:Write(LOG_INFO, "[Game] Started")
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local physicsWorld = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld.gravity = Vector2(0, -9.81)
end

function SetupCamera()
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)

    local camera = cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = 5.2

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
    renderer.defaultZone.fogColor = Color(0.6, 0.8, 1.0, 1.0)
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

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 更新输入
    inputManager:update()

    -- 更新玩家
    player:update(dt)

    -- 更新UI（血量显示）
    gameUI:update()

    -- 相机跟随玩家
    local pos = player:getPosition()
    cameraNode.position = Vector3(pos.x, pos.y, -10)
end

function Stop()
    log:Write(LOG_INFO, "[Game] Game stopped")
end
