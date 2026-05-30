-- Player 类
Player = {}
Player.__index = Player

local MOVE_SPEED = 3.0
local JUMP_FORCE = 5.0
local MAX_JUMPS = 2        -- 最大跳跃次数（2段跳）
local FALL_MULTIPLIER = 2  -- 下落加速倍数
local MAX_HP = 5           -- 最大生命值

local INVINCIBLE_DURATION = 1.5  -- 无敌帧持续时间（秒）（需大于敌人攻击冷却1.0s）
local BLINK_INTERVAL = 0.1       -- 闪烁间隔
local NEAR_DEATH_SPEED_MULT = 0.6  -- 濒死时移动速度倍率
local ATTACK_RANGE = 1.5         -- 平A攻击距离（米）
local ATTACK_DAMAGE = 1           -- 平A伤害
local ATTACK_COOLDOWN = 0.5       -- 攻击冷却（秒）
local SLAM_SPEED = 15.0           -- 下砸速度（米/秒）
local SLAM_AOE_RANGE = 2.0        -- 下砸AOE范围（米）
local SLAM_DAMAGE = 3             -- 下砸伤害
local SLAM_KNOCKBACK = 8.0        -- 击飞力度

function Player:new(scene, inputManager)
    local self = setmetatable({}, Player)
    self.inputManager = inputManager
    self.jumpCount = 0
    self.jumpPressed = false
    self.isGrounded = false
    self.hp = MAX_HP
    self.maxHp = MAX_HP
    self.dead = false
    -- 受伤无敌帧
    self.invincible = false
    self.invincibleTimer = 0
    self.blinkTimer = 0
    -- 濒死
    self.nearDeath = false
    -- 死亡
    self.deathTimer = 0
    self.gameOverCallback = nil
    -- 攻击
    self.attackCooldown = 0
    self.attackPressed = false
    self.targetEnemy = nil  -- 需要外部设置
    -- 下砸攻击
    self.slamming = false
    -- 施法状态（卡牌使用时锁定移动）
    self.castingCard = false
    self.physicsWorld = scene:GetComponent("PhysicsWorld2D")
    self:_createNode(scene)
    return self
end

function Player:_createNode(scene)
    self.node = scene:CreateChild("Player")
    self.node.position = Vector3(0, -1.9, 0)

    -- 可视化 - 蓝色方块角色
    self.sprite = self.node:CreateComponent("StaticSprite2D")
    self.sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
    self.sprite.color = Color(0.2, 0.4, 0.9, 1.0)
    self.sprite.drawRect = Rect(-0.4, -0.6, 0.4, 0.6)
    self.normalColor = Color(0.2, 0.4, 0.9, 1.0)
    self.nearDeathColor = Color(0.1, 0.15, 0.35, 1.0)

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

    -- 死亡状态：倒地动画 + Game Over
    if self.dead then
        self:_updateDeath(dt)
        return
    end

    -- 无敌帧闪烁
    if self.invincible then
        self:_updateInvincible(dt)
    end

    local velocity = self.body:GetLinearVelocity()

    -- 施法状态：锁定水平移动，保持物理
    if self.castingCard then
        self.body:SetLinearVelocity(Vector2(0, velocity.y))
        return
    end

    -- 下砸状态：强制高速下落，着地时触发AOE
    if self.slamming then
        self.body:SetLinearVelocity(Vector2(0, -SLAM_SPEED))
        self.isGrounded = self:_checkGrounded()
        if self.isGrounded then
            self:_slamLand()
        end
        return
    end

    local desiredVelX = 0

    -- 左右移动（濒死时速度降低）
    local speedMult = self.nearDeath and NEAR_DEATH_SPEED_MULT or 1.0
    if self.inputManager:isActionActive(InputManager.ACTION_LEFT) then
        desiredVelX = -MOVE_SPEED * speedMult
    elseif self.inputManager:isActionActive(InputManager.ACTION_RIGHT) then
        desiredVelX = MOVE_SPEED * speedMult
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

    -- 攻击冷却
    if self.attackCooldown > 0 then
        self.attackCooldown = self.attackCooldown - dt
    end

    -- 攻击输入
    local attackAction = self.inputManager:isActionActive(InputManager.ACTION_ATTACK)

    if attackAction and not self.attackPressed and self.attackCooldown <= 0 then
        if not self.isGrounded then
            -- 空中攻击 → 下砸
            self:_enterSlam()
        else
            -- 地面攻击 → 普通平A
            self:_doAttack()
        end
    end
    self.attackPressed = attackAction
end

-- 执行平A攻击（查找范围内最近的存活敌人）
function Player:_doAttack()
    self.attackCooldown = ATTACK_COOLDOWN
    if not self.enemies then return end

    local myPos = self.node.position
    local nearestEnemy = nil
    local nearestDist = ATTACK_RANGE + 1

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local dist = math.abs(myPos.x - e.node.position.x)
            if dist < nearestDist then
                nearestDist = dist
                nearestEnemy = e
            end
        end
    end

    if nearestEnemy and nearestDist <= ATTACK_RANGE then
        nearestEnemy:takeDamage(ATTACK_DAMAGE)
        log:Write(LOG_INFO, "[Player] Attack hit! Dist=" .. string.format("%.2f", nearestDist))
    end
end

-- 进入下砸状态
function Player:_enterSlam()
    self.slamming = true
    self.attackCooldown = ATTACK_COOLDOWN
    -- 停止水平速度，快速下落
    self.body:SetLinearVelocity(Vector2(0, -SLAM_SPEED))
    log:Write(LOG_INFO, "[Player] Slam attack started!")
end

-- 下砸落地：AOE伤害 + 击飞
function Player:_slamLand()
    self.slamming = false
    self.jumpCount = 0

    if not self.enemies then return end

    local myPos = self.node.position

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local enemyPos = e.node.position
            local dist = math.abs(myPos.x - enemyPos.x)
            if dist <= SLAM_AOE_RANGE then
                -- 造成AOE伤害
                e:takeDamage(SLAM_DAMAGE)
                -- 击飞：向远离玩家的方向施加冲量
                if e:isAlive() and e.body then
                    local dir = enemyPos.x > myPos.x and 1 or -1
                    e.body:ApplyLinearImpulseToCenter(Vector2(SLAM_KNOCKBACK * dir, SLAM_KNOCKBACK * 0.6), true)
                end
            end
        end
    end
    log:Write(LOG_INFO, "[Player] Slam landed! AOE damage dealt")
end

-- 无敌帧更新（闪烁效果）
function Player:_updateInvincible(dt)
    self.invincibleTimer = self.invincibleTimer - dt
    self.blinkTimer = self.blinkTimer + dt

    -- 闪烁：交替显示/隐藏
    if self.blinkTimer >= BLINK_INTERVAL then
        self.blinkTimer = 0
        local isEnabled = self.sprite:IsEnabled()
        self.sprite:SetEnabled(not isEnabled)
    end

    -- 无敌时间结束
    if self.invincibleTimer <= 0 then
        self.invincible = false
        self.sprite:SetEnabled(true)
        log:Write(LOG_INFO, "[Player] Invincible OFF")
    end
end

-- 死亡状态更新
function Player:_updateDeath(dt)
    self.deathTimer = self.deathTimer + dt

    -- 阶段1: 倒地（旋转倒下）
    if self.deathTimer < 0.5 then
        local rotation = self.node.rotation
        self.node.rotation = Quaternion(0, 0, self.deathTimer * 180)
    -- 阶段2: 视觉剥夺（变暗消失）
    elseif self.deathTimer < 1.5 then
        local fade = 1.0 - (self.deathTimer - 0.5)
        self.sprite.color = Color(0.1, 0.1, 0.1, math.max(0, fade))
    -- 阶段3: 触发 Game Over
    else
        if self.gameOverCallback then
            self.gameOverCallback()
        end
    end
end

-- 受伤
function Player:takeDamage(amount)
    -- 无敌期间不受伤
    if self.invincible then
        log:Write(LOG_INFO, "[Player] Invincible! Damage blocked.")
        return false
    end
    if self.dead then return false end

    self.hp = math.max(0, self.hp - (amount or 1))
    log:Write(LOG_INFO, "[Player] Took damage, HP=" .. self.hp)

    if self.hp <= 0 then
        -- 死亡
        self:_enterDeath()
        return true
    elseif self.hp == 1 then
        -- 濒死：颜色变暗
        self.nearDeath = true
        self.sprite.color = self.nearDeathColor
        self:_enterInvincible()
    else
        -- 普通受伤：进入无敌帧
        self:_enterInvincible()
    end
    return false
end

-- 进入无敌帧
function Player:_enterInvincible()
    self.invincible = true
    self.invincibleTimer = INVINCIBLE_DURATION
    self.blinkTimer = 0
    log:Write(LOG_INFO, "[Player] Invincible ON for " .. INVINCIBLE_DURATION .. "s")
end

-- 进入死亡
function Player:_enterDeath()
    self.dead = true
    self.deathTimer = 0
    self.body:SetLinearVelocity(Vector2(0, 0))
    log:Write(LOG_INFO, "[Player] Dead!")
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
    self.dead = false
    self.invincible = false
    self.invincibleTimer = 0
    self.blinkTimer = 0
    self.nearDeath = false
    self.deathTimer = 0
    self.attackCooldown = 0
    self.attackPressed = false
    self.slamming = false
    self.castingCard = false
    self.node.position = Vector3(0, -1.9, 0)
    self.node.rotation = Quaternion(0, 0, 0)
    self.sprite:SetEnabled(true)
    self.sprite.color = self.normalColor
    self.body:SetLinearVelocity(Vector2(0, 0))
    log:Write(LOG_INFO, "[Player] Reset to initial state")
end

function Player:getPosition()
    return self.node.position
end

return Player
