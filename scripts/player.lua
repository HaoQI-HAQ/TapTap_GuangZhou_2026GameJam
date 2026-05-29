-- Player 类
Player = {}
Player.__index = Player

local MOVE_SPEED = 3.0
local JUMP_FORCE = 5.0
local MAX_JUMPS = 2        -- 最大跳跃次数（2段跳）
local FALL_MULTIPLIER = 2  -- 下落加速倍数（额外1倍重力）

function Player:new(scene, inputManager)
    local self = setmetatable({}, Player)
    self.inputManager = inputManager
    self.jumpCount = 0
    self.jumpPressed = false  -- 用于检测按下瞬间（防止按住连跳）
    self:_createNode(scene)
    return self
end

function Player:_createNode(scene)
    self.node = scene:CreateChild("Player")
    self.node.position = Vector3(0, 2.0, 0)

    -- 可视化
    local sprite = self.node:CreateComponent("StaticSprite2D")
    sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
    sprite.color = Color(0.2, 0.5, 1.0, 1.0)
    sprite.drawRect = Rect(-0.4, -0.6, 0.4, 0.6)

    -- 物理
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_DYNAMIC
    self.body.fixedRotation = true
    self.body.linearDamping = 0.5

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(0.8, 1.2)
    shape.density = 1.0
    shape.friction = 0.3

    log:Write(LOG_INFO, "[Player] Created with double jump")
end

function Player:update(dt)
    if self.body == nil then
        return
    end

    local velocity = self.body:GetLinearVelocity()
    local desiredVelX = 0

    -- 左右移动
    if self.inputManager:isActionActive(InputManager.ACTION_LEFT) then
        desiredVelX = -MOVE_SPEED
    elseif self.inputManager:isActionActive(InputManager.ACTION_RIGHT) then
        desiredVelX = MOVE_SPEED
    end

    self.body:SetLinearVelocity(Vector2(desiredVelX, velocity.y))

    -- 下落时施加额外重力，加快下落速度
    if velocity.y < 0 then
        self.body:ApplyForceToCenter(Vector2(0, -9.81 * FALL_MULTIPLIER), true)
    end

    -- 着地检测：垂直速度接近0视为着地，重置跳跃次数
    if math.abs(velocity.y) < 0.05 then
        self.jumpCount = 0
    end

    -- 跳跃（按下瞬间触发，限制2段）
    local jumpAction = self.inputManager:isActionActive(InputManager.ACTION_JUMP)
    if jumpAction and not self.jumpPressed then
        if self.jumpCount < MAX_JUMPS then
            self.body:SetLinearVelocity(Vector2(velocity.x, 0)) -- 重置垂直速度
            self.body:ApplyLinearImpulseToCenter(Vector2(0, JUMP_FORCE), true)
            self.jumpCount = self.jumpCount + 1
            log:Write(LOG_INFO, "[Player] Jump " .. self.jumpCount .. "/" .. MAX_JUMPS)
        end
    end
    self.jumpPressed = jumpAction
end

function Player:getPosition()
    return self.node.position
end

return Player
