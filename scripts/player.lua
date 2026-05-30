-- ============================================================================
-- Player 模块：角色移动、跳跃、攻击连招、下砸
-- ============================================================================

local CONFIG = require("config")
local InputManager = require("input_manager")

local Player = {}
Player.__index = Player

-- 状态枚举
Player.STATE_IDLE    = "idle"
Player.STATE_RUN     = "run"
Player.STATE_JUMP    = "jump"
Player.STATE_FALL    = "fall"
Player.STATE_ATTACK  = "attack"
Player.STATE_SLAM    = "slam"
Player.STATE_CAST    = "cast"

function Player:new(scene, inputMgr)
    local self = setmetatable({}, Player)

    self.inputMgr = inputMgr
    self.hp = CONFIG.MaxHP
    self.maxHp = CONFIG.MaxHP
    self.state = Player.STATE_IDLE
    self.facingRight = true

    -- 跳跃
    self.jumpCount = 0
    self.groundContacts = 0
    self.isGrounded = false
    self.coyoteTimer = 0
    self.jumpGraceTimer = 0

    -- 攻击
    self.comboStep = 0          -- 当前连击段数(0=未攻击, 1-3=轻攻击, 4=重击)
    self.attackTimer = 0        -- 攻击动画计时
    self.comboResetTimer = 0    -- 连击重置计时
    self.attackCooldown = 0     -- 攻击冷却

    -- 下砸
    self.isSlamming = false
    self.slamStartY = 0
    self.slamCooldown = 0

    -- 五感剥夺
    self.lostSenses = {}        -- 已失去的感官列表
    self.driftOffset = 0        -- 触觉剥夺: 操控漂移

    -- 创建节点
    self:_createNode(scene)

    return self
end

function Player:_createNode(scene)
    self.node = scene:CreateChild("Player")
    self.node.position = Vector3(0, 2.0, 0)

    -- 视觉(蓝色方块)
    local model = self.node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 0.9, 1.0)))
    model:SetMaterial(mat)
    self.node:SetScale(Vector3(CONFIG.PlayerSize.w, CONFIG.PlayerSize.h, 0.5))

    -- 物理
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_DYNAMIC
    self.body.fixedRotation = true
    self.body.linearDamping = 0.0
    self.body.gravityScale = 1.0

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(CONFIG.PlayerSize.w, CONFIG.PlayerSize.h)
    shape.density = 1.0
    shape.friction = 0.3
    shape.restitution = 0.0

    -- 脚部传感器(地面检测)
    local foot = self.node:CreateComponent("CollisionBox2D")
    foot.size = Vector2(CONFIG.PlayerSize.w * 0.6, 0.05)
    foot.center = Vector2(0, -CONFIG.PlayerSize.h / 2)
    foot.isTrigger = true
end

function Player:update(dt)
    if not self.body or self.hp <= 0 then return end

    -- 更新计时器
    self:_updateTimers(dt)

    -- 施法/攻击中不处理移动
    if self.state == Player.STATE_CAST then return end
    if self.state == Player.STATE_ATTACK and self.attackTimer > 0 then
        self:_updateAttackAnim(dt)
        return
    end

    -- 下砸状态
    if self.isSlamming then
        self:_updateSlam(dt)
        return
    end

    -- 移动
    self:_handleMovement(dt)

    -- 跳跃
    self:_handleJump(dt)

    -- 攻击
    self:_handleAttack()

    -- 下砸
    self:_handleSlam()
end

-- ========== 移动 ==========

function Player:_handleMovement(dt)
    local vel = self.body:GetLinearVelocity()
    local moveX = 0

    if self.inputMgr:isHeld(InputManager.ACTION_LEFT) then
        moveX = -1
    elseif self.inputMgr:isHeld(InputManager.ACTION_RIGHT) then
        moveX = 1
    end

    -- 触觉剥夺: 操控漂移
    if self:hasSenseLost("touch") then
        self.driftOffset = self.driftOffset + (math.random() - 0.5) * 0.1
        self.driftOffset = math.max(-0.3, math.min(0.3, self.driftOffset))
        moveX = moveX + self.driftOffset
    end

    local desiredVelX = moveX * CONFIG.PlayerSpeed
    self.body:SetLinearVelocity(Vector2(desiredVelX, vel.y))

    -- 朝向
    if moveX > 0.1 then self.facingRight = true
    elseif moveX < -0.1 then self.facingRight = false end

    -- 状态更新
    if self.isGrounded then
        self.state = math.abs(moveX) > 0.1 and Player.STATE_RUN or Player.STATE_IDLE
    else
        self.state = vel.y > 0 and Player.STATE_JUMP or Player.STATE_FALL
    end
end

-- ========== 跳跃 ==========

function Player:_handleJump(dt)
    -- 土狼时间
    if self.isGrounded then
        self.coyoteTimer = CONFIG.CoyoteTime
    else
        if self.coyoteTimer > 0 then
            self.coyoteTimer = self.coyoteTimer - dt
        end
    end

    if self.jumpGraceTimer > 0 then
        self.jumpGraceTimer = self.jumpGraceTimer - dt
    end

    if self.inputMgr:isPressed(InputManager.ACTION_JUMP) then
        local vel = self.body:GetLinearVelocity()
        local canCoyote = (not self.isGrounded) and (self.coyoteTimer > 0) and (self.jumpCount == 0)

        if self.isGrounded or canCoyote then
            self.body:SetLinearVelocity(Vector2(vel.x, CONFIG.JumpForce))
            self.jumpCount = 1
            self.isGrounded = false
            self.coyoteTimer = 0
            self.jumpGraceTimer = 0.15
        elseif self.jumpCount < CONFIG.MaxJumps then
            self.body:SetLinearVelocity(Vector2(vel.x, CONFIG.JumpForce))
            self.jumpCount = self.jumpCount + 1
            self.jumpGraceTimer = 0.15
        end
    end
end

-- ========== 攻击 ==========

function Player:_handleAttack()
    if self.attackCooldown > 0 then return end

    if self.inputMgr:isPressed(InputManager.ACTION_ATTACK) then
        self.comboResetTimer = CONFIG.ComboResetTime
        self.comboStep = self.comboStep + 1

        if self.comboStep > CONFIG.ComboCount then
            -- 重击收尾
            self.comboStep = 0
            self.attackTimer = CONFIG.AttackAnimDuration * 1.5
            self.attackCooldown = CONFIG.AttackCooldown * 1.5
            self.state = Player.STATE_ATTACK
            -- 返回重击信息供外部处理伤害
            self._lastAttackType = "heavy"
        else
            -- 轻攻击
            self.attackTimer = CONFIG.AttackAnimDuration
            self.attackCooldown = CONFIG.AttackCooldown
            self.state = Player.STATE_ATTACK
            self._lastAttackType = "light"
        end
        self._attackTriggered = true
    end
end

-- 外部调用: 获取本帧攻击信息(返回后清除)
function Player:consumeAttack()
    if self._attackTriggered then
        self._attackTriggered = false
        return self._lastAttackType, self.comboStep
    end
    return nil, 0
end

function Player:_updateAttackAnim(dt)
    self.attackTimer = self.attackTimer - dt
    -- 攻击闪白
    local model = self.node:GetComponent("StaticModel")
    if model then
        local mat = model:GetMaterial(0)
        if mat then
            if self.attackTimer > 0 then
                mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
            else
                mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 0.9, 1.0)))
            end
        end
    end
end

-- ========== 下砸 ==========

function Player:_handleSlam()
    if self.slamCooldown > 0 then return end
    if self.isGrounded then return end  -- 必须在空中

    -- 下+攻击 或 S键
    local wantSlam = self.inputMgr:isPressed(InputManager.ACTION_SLAM)
    -- 同时按下和攻击也触发
    if not wantSlam and self.inputMgr:isHeld(InputManager.ACTION_SLAM)
        and self.inputMgr:isPressed(InputManager.ACTION_ATTACK) then
        wantSlam = true
    end

    if wantSlam then
        self.isSlamming = true
        self.slamStartY = self.node.position.y
        self.state = Player.STATE_SLAM
        -- 设置高速下落
        self.body:SetLinearVelocity(Vector2(0, -CONFIG.SlamSpeed))
        self.body.gravityScale = 0  -- 下砸时关闭重力，使用固定速度
    end
end

function Player:_updateSlam(dt)
    -- 落地检测
    if self.isGrounded then
        self.isSlamming = false
        self.body.gravityScale = 1.0
        self.slamCooldown = CONFIG.SlamCooldown

        -- 计算高度伤害
        local height = math.max(0, self.slamStartY - self.node.position.y)
        local heightRatio = math.min(height / CONFIG.SlamMaxHeight, 1.0)
        local damage = math.floor(CONFIG.SlamBaseDamage * (1 + (CONFIG.SlamMaxMultiplier - 1) * heightRatio))

        self._slamTriggered = true
        self._slamDamage = damage
        self._slamHeight = height
    end
end

-- 外部调用: 获取下砸信息
function Player:consumeSlam()
    if self._slamTriggered then
        self._slamTriggered = false
        return self._slamDamage, self._slamHeight
    end
    return nil, 0
end

-- ========== 计时器 ==========

function Player:_updateTimers(dt)
    if self.attackCooldown > 0 then
        self.attackCooldown = self.attackCooldown - dt
    end
    if self.slamCooldown > 0 then
        self.slamCooldown = self.slamCooldown - dt
    end
    if self.comboResetTimer > 0 then
        self.comboResetTimer = self.comboResetTimer - dt
        if self.comboResetTimer <= 0 then
            self.comboStep = 0  -- 连击超时重置
        end
    end
end

-- ========== 伤害/血量 ==========

function Player:takeDamage(amount)
    self.hp = math.max(0, self.hp - (amount or 1))
    -- 受伤时剥夺一个感官
    if self.hp > 0 then
        self:_depriveSense()
    end
    return self.hp <= 0
end

function Player:_depriveSense()
    -- 从尚未失去的感官中随机选一个
    local available = {}
    for _, sense in ipairs(CONFIG.Senses) do
        if not self:hasSenseLost(sense) then
            available[#available + 1] = sense
        end
    end
    if #available > 0 then
        local idx = math.random(1, #available)
        self.lostSenses[#self.lostSenses + 1] = available[idx]
    end
end

function Player:hasSenseLost(sense)
    for _, s in ipairs(self.lostSenses) do
        if s == sense then return true end
    end
    return false
end

function Player:isDead()
    return self.hp <= 0
end

function Player:getPosition()
    return self.node.position
end

-- ========== 地面碰撞(外部调用) ==========

function Player:onGroundContact()
    if self.jumpGraceTimer > 0 then return end
    self.groundContacts = self.groundContacts + 1
    self.isGrounded = true
    self.jumpCount = 0
end

function Player:onGroundLeave()
    self.groundContacts = self.groundContacts - 1
    if self.groundContacts <= 0 then
        self.groundContacts = 0
        self.isGrounded = false
    end
end

-- 施法状态(卡牌使用时调用)
function Player:startCast(duration)
    self.state = Player.STATE_CAST
    self._castTimer = duration or CONFIG.CastAnimDuration
end

function Player:updateCast(dt)
    if self.state == Player.STATE_CAST then
        self._castTimer = (self._castTimer or 0) - dt
        if self._castTimer <= 0 then
            self.state = Player.STATE_IDLE
            return true  -- 施法结束
        end
    end
    return false
end

return Player
