-- ============================================================================
-- Player 模块 - 玩家角色（创建、移动、跳跃、攻击、状态管理）
-- ============================================================================

local Player = {}
Player.__index = Player

-- ============================================================================
-- 配置
-- ============================================================================
Player.CONFIG = {
    Speed = 4.0,              -- 水平移动速度 (m/s)
    JumpHeight = 2.0,         -- 单次跳跃高度 (米)
    MaxJumps = 2,             -- 最大跳跃段数
    CoyoteTime = 0.12,        -- 土狼时间 (秒)
    Size = { w = 0.5, h = 0.8 },
    AttackRange = 1.5,        -- 攻击距离 (米)
    AttackDamage = 1,         -- 每次攻击伤害
    AttackCooldown = 0.5,     -- 攻击冷却 (秒)
    MaxHP = 5,                -- 最大生命值
    Gravity = 20.0,           -- 重力（用于计算跳跃力）
}

-- 由配置自动计算
Player.CONFIG.JumpForce = math.sqrt(2 * Player.CONFIG.Gravity * Player.CONFIG.JumpHeight)

-- ============================================================================
-- 构造
-- ============================================================================

---@param scene Scene
---@return table
function Player.New(scene)
    local self = setmetatable({}, Player)

    self.scene_ = scene
    self.node_ = nil           ---@type Node
    self.body_ = nil           ---@type RigidBody2D
    self.attackFxNode_ = nil   ---@type Node

    -- 状态
    self.hp_ = Player.CONFIG.MaxHP
    self.maxHP_ = Player.CONFIG.MaxHP
    self.isGrounded_ = false
    self.facingRight_ = true
    self.attackTimer_ = 0
    self.isAttacking_ = false
    self.attackAnimTimer_ = 0
    self.attackFxTimer_ = 0

    -- 跳跃
    self.jumpCount_ = 0
    self.groundContacts_ = 0
    self.coyoteTimer_ = 0
    self.wasGrounded_ = false
    self.jumpGraceTimer_ = 0

    -- 输入
    self.moveX_ = 0
    self.wantJump_ = false
    self.touchLeft_ = false
    self.touchRight_ = false

    return self
end

-- ============================================================================
-- 创建/销毁
-- ============================================================================

function Player:Create(x, y)
    local cfg = Player.CONFIG

    self.node_ = self.scene_:CreateChild("Player")
    self.node_.position = Vector3(x, y, 0)

    -- 视觉 (蓝色立方体)
    local model = self.node_:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 0.9, 1.0)))
    model:SetMaterial(mat)
    self.node_:SetScale(Vector3(cfg.Size.w, cfg.Size.h, 0.5))

    -- 物理
    self.body_ = self.node_:CreateComponent("RigidBody2D")
    self.body_.bodyType = BT_DYNAMIC
    self.body_.fixedRotation = true
    self.body_.linearDamping = 0.0
    self.body_.gravityScale = 1.0

    local shape = self.node_:CreateComponent("CollisionBox2D")
    shape.size = Vector2(cfg.Size.w, cfg.Size.h)
    shape.density = 1.0
    shape.friction = 0.3
    shape.restitution = 0.0

    -- 脚部传感器（地面检测）
    local footSensor = self.node_:CreateComponent("CollisionBox2D")
    footSensor.size = Vector2(cfg.Size.w * 0.6, 0.05)
    footSensor.center = Vector2(0, -cfg.Size.h / 2)
    footSensor.isTrigger = true

    -- 攻击范围特效
    self:CreateAttackFx()

    return self
end

function Player:Destroy()
    if self.node_ then
        self.node_:Remove()
        self.node_ = nil
        self.body_ = nil
    end
    if self.attackFxNode_ then
        self.attackFxNode_:Remove()
        self.attackFxNode_ = nil
    end
end

function Player:CreateAttackFx()
    local cfg = Player.CONFIG
    self.attackFxNode_ = self.scene_:CreateChild("AttackFX")
    self.attackFxNode_.position = Vector3(0, 0, -0.1)

    local model = self.attackFxNode_:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.2, 0.4)))
    model:SetMaterial(mat)
    self.attackFxNode_:SetScale(Vector3(cfg.AttackRange, 0.3, 0.1))
    self.attackFxNode_:SetEnabled(false)
end

-- ============================================================================
-- 输入收集
-- ============================================================================

function Player:GatherInput()
    self.moveX_ = 0

    -- 触摸按钮
    if self.touchLeft_ then self.moveX_ = self.moveX_ - 1 end
    if self.touchRight_ then self.moveX_ = self.moveX_ + 1 end

    -- 键盘
    if input:GetKeyDown(KEY_A) then self.moveX_ = -1 end
    if input:GetKeyDown(KEY_D) then self.moveX_ = 1 end

    -- 跳跃
    if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) then
        self.wantJump_ = true
    end

    -- 手柄
    self:ReadGamepad()
end

function Player:ReadGamepad()
    if input.numJoysticks > 0 then
        local js = input:GetJoystickByIndex(0)
        if js and js:IsController() then
            local axisX = js:GetAxisPosition(CONTROLLER_AXIS_LEFTX)
            if math.abs(axisX) > 0.15 then
                self.moveX_ = axisX
            end
            if js:GetButtonPress(CONTROLLER_BUTTON_X) then
                self:TryAttack()
            end
            if js:GetButtonPress(CONTROLLER_BUTTON_A) then
                self.wantJump_ = true
            end
        end
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

function Player:Update(dt)
    if not self.body_ then return end

    -- 计时器
    if self.attackTimer_ > 0 then
        self.attackTimer_ = self.attackTimer_ - dt
    end
    if self.attackAnimTimer_ > 0 then
        self.attackAnimTimer_ = self.attackAnimTimer_ - dt
        if self.attackAnimTimer_ <= 0 then
            self.isAttacking_ = false
        end
    end

    -- 输入
    self:GatherInput()

    -- 移动
    self:UpdateMovement(dt)

    -- 攻击视觉
    self:UpdateAttackVisual()

    -- 攻击特效
    self:UpdateAttackFx(dt)

    -- 消耗跳跃输入
    self.wantJump_ = false
end

function Player:UpdateMovement(dt)
    local cfg = Player.CONFIG

    -- 跳跃冷却
    if self.jumpGraceTimer_ > 0 then
        self.jumpGraceTimer_ = self.jumpGraceTimer_ - dt
    end

    local vel = self.body_:GetLinearVelocity()
    local desiredVelX = self.moveX_ * cfg.Speed
    self.body_:SetLinearVelocity(Vector2(desiredVelX, vel.y))

    -- 朝向
    if self.moveX_ > 0.1 then
        self.facingRight_ = true
    elseif self.moveX_ < -0.1 then
        self.facingRight_ = false
    end

    -- 土狼时间
    if self.isGrounded_ then
        self.coyoteTimer_ = cfg.CoyoteTime
        self.wasGrounded_ = true
    else
        if self.wasGrounded_ then
            if self.jumpCount_ == 0 then
                self.coyoteTimer_ = cfg.CoyoteTime
            end
            self.wasGrounded_ = false
        end
        if self.coyoteTimer_ > 0 then
            self.coyoteTimer_ = self.coyoteTimer_ - dt
        end
    end

    -- 跳跃
    if self.wantJump_ then
        local canCoyoteJump = (not self.isGrounded_) and (self.coyoteTimer_ > 0) and (self.jumpCount_ == 0)
        if self.isGrounded_ or canCoyoteJump then
            self.body_:SetLinearVelocity(Vector2(desiredVelX, cfg.JumpForce))
            self.jumpCount_ = 1
            self.isGrounded_ = false
            self.coyoteTimer_ = 0
            self.jumpGraceTimer_ = 0.15
        elseif self.jumpCount_ < cfg.MaxJumps then
            self.body_:SetLinearVelocity(Vector2(desiredVelX, cfg.JumpForce))
            self.jumpCount_ = self.jumpCount_ + 1
            self.jumpGraceTimer_ = 0.15
        end
    end
end

function Player:UpdateAttackVisual()
    if not self.node_ then return end
    local model = self.node_:GetComponent("StaticModel")
    if not model then return end
    local mat = model:GetMaterial(0)
    if not mat then return end

    if self.isAttacking_ then
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
    else
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 0.9, 1.0)))
    end
end

function Player:UpdateAttackFx(dt)
    if self.attackFxTimer_ > 0 then
        self.attackFxTimer_ = self.attackFxTimer_ - dt
        if self.attackFxTimer_ <= 0 and self.attackFxNode_ then
            self.attackFxNode_:SetEnabled(false)
        end
    end
end

-- ============================================================================
-- 攻击
-- ============================================================================

--- 尝试攻击，返回攻击位置信息供外部判断命中
---@return boolean attacked 是否成功发起攻击
function Player:TryAttack()
    if self.attackTimer_ > 0 then return false end
    local cfg = Player.CONFIG

    self.isAttacking_ = true
    self.attackAnimTimer_ = 0.2
    self.attackTimer_ = cfg.AttackCooldown

    -- 显示攻击范围特效
    if self.attackFxNode_ and self.node_ then
        local px = self.node_.position.x
        local py = self.node_.position.y
        local offsetX = self.facingRight_ and (cfg.AttackRange / 2) or (-cfg.AttackRange / 2)
        self.attackFxNode_.position = Vector3(px + offsetX, py, -0.1)
        self.attackFxNode_:SetEnabled(true)
        self.attackFxTimer_ = 0.15
    end

    return true
end

--- 获取攻击位置（2D）
---@return Vector2|nil
function Player:GetPosition2D()
    if not self.node_ then return nil end
    return self.node_.position2D
end

--- 获取攻击范围
function Player:GetAttackRange()
    return Player.CONFIG.AttackRange
end

--- 获取攻击伤害
function Player:GetAttackDamage()
    return Player.CONFIG.AttackDamage
end

-- ============================================================================
-- 受击
-- ============================================================================

function Player:TakeDamage(amount)
    self.hp_ = self.hp_ - amount
    if self.hp_ < 0 then self.hp_ = 0 end
    return self.hp_
end

function Player:IsDead()
    return self.hp_ <= 0
end

-- ============================================================================
-- 碰撞回调
-- ============================================================================

function Player:OnCollisionBegin()
    if self.jumpGraceTimer_ > 0 then return end
    self.groundContacts_ = self.groundContacts_ + 1
    self.isGrounded_ = true
    self.jumpCount_ = 0
end

function Player:OnCollisionEnd()
    self.groundContacts_ = self.groundContacts_ - 1
    if self.groundContacts_ <= 0 then
        self.groundContacts_ = 0
        self.isGrounded_ = false
    end
end

-- ============================================================================
-- 重置
-- ============================================================================

function Player:Reset(x, y)
    if not self.node_ then
        self:Create(x, y)
    else
        self.node_.position = Vector3(x, y, 0)
        self.body_:SetLinearVelocity(Vector2(0, 0))
    end

    self.hp_ = self.maxHP_
    self.isGrounded_ = false
    self.jumpCount_ = 0
    self.groundContacts_ = 0
    self.coyoteTimer_ = 0
    self.jumpGraceTimer_ = 0
    self.attackTimer_ = 0
    self.isAttacking_ = false
    self.facingRight_ = true
end

return Player
