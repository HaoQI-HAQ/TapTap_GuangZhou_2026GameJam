-- Player 类
Player = {}
Player.__index = Player

local MOVE_SPEED = 3.0
local JUMP_FORCE = 5.0
local MAX_JUMPS = 2        -- 最大跳跃次数（2段跳）
local FALL_MULTIPLIER = 2  -- 下落加速倍数
local MAX_HP = 5           -- 最大生命值

function Player:new(scene, inputManager)
    local self = setmetatable({}, Player)
    self.inputManager = inputManager
    self.jumpCount = 0
    self.jumpPressed = false
    self.isGrounded = false
    self.hp = MAX_HP
    self.maxHp = MAX_HP
    self.physicsWorld = scene:GetComponent("PhysicsWorld2D")
    self:_createNode(scene)
    return self
end

function Player:_createNode(scene)
    self.node = scene:CreateChild("Player")
    self.node.position = Vector3(0, -1.9, 0)

    -- 可视化 - 蓝色方块角色
    local sprite = self.node:CreateComponent("StaticSprite2D")
    sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
    sprite.color = Color(0.2, 0.4, 0.9, 1.0)
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

    log:Write(LOG_INFO, "[Player] Created with HP=" .. self.hp)
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

    -- 下落加速
    if velocity.y < 0 then
        self.body:ApplyForceToCenter(Vector2(0, -9.81 * FALL_MULTIPLIER), true)
    end

    -- 着地检测：从玩家脚底向下射线检测
    self.isGrounded = self:_checkGrounded()
    if self.isGrounded then
        self.jumpCount = 0
    end

    -- 跳跃（按下瞬间触发，限制2段）
    local jumpAction = self.inputManager:isActionActive(InputManager.ACTION_JUMP)
    if jumpAction and not self.jumpPressed then
        if self.jumpCount < MAX_JUMPS then
            self.body:SetLinearVelocity(Vector2(velocity.x, 0))
            self.body:ApplyLinearImpulseToCenter(Vector2(0, JUMP_FORCE), true)
            self.jumpCount = self.jumpCount + 1
        end
    end
    self.jumpPressed = jumpAction
end

-- 受伤
function Player:takeDamage(amount)
    self.hp = math.max(0, self.hp - (amount or 1))
    log:Write(LOG_INFO, "[Player] Took damage, HP=" .. self.hp)
    return self.hp <= 0
end

-- 回血
function Player:heal(amount)
    self.hp = math.min(self.maxHp, self.hp + (amount or 1))
end

function Player:getHp()
    return self.hp
end

function Player:getMaxHp()
    return self.maxHp
end

function Player:isDead()
    return self.hp <= 0
end

-- 射线检测玩家是否着地
function Player:_checkGrounded()
    local pos = self.node.position
    -- 从玩家脚底位置向下发射短射线
    local startPoint = Vector2(pos.x, pos.y - 0.6)  -- 碰撞体底部
    local endPoint = Vector2(pos.x, pos.y - 0.7)    -- 向下多探测0.1米

    local result = self.physicsWorld:RaycastSingle(startPoint, endPoint)
    if result.body ~= nil and result.body ~= self.body then
        return true
    end
    return false
end

function Player:reset()
    self.hp = MAX_HP
    self.jumpCount = 0
    self.jumpPressed = false
    self.isGrounded = false
    self.node.position = Vector3(0, -1.9, 0)
    self.body:SetLinearVelocity(Vector2(0, 0))
    log:Write(LOG_INFO, "[Player] Reset to initial state")
end

function Player:getPosition()
    return self.node.position
end

return Player
