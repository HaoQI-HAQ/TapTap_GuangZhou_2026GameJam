-- ============================================================================
-- Player 模块 - 玩家角色（创建、移动、跳跃、攻击、状态管理）
-- ============================================================================

local Player = {}
Player.__index = Player

-- ============================================================================
-- 状态常量
-- ============================================================================
Player.STATE = {
    NORMAL = "normal",     -- 正常：标准颜色，流畅动作
    HURT = "hurt",         -- 受伤：无敌帧闪烁1秒
    DYING = "dying",       -- 濒死（1血）：颜色变暗，动作迟缓
    DEAD = "dead",         -- 死亡：倒地 → Game Over
}

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

    -- 状态相关配置
    InvincibleDuration = 1.0, -- 无敌帧持续时间 (秒)
    BlinkInterval = 0.08,     -- 闪烁间隔 (秒)
    DyingSpeedMult = 0.6,     -- 濒死时速度乘数
    DeathFallDuration = 0.8,  -- 死亡倒地动画时长 (秒)

    -- 颜色
    ColorNormal = Color(0.2, 0.4, 0.9, 1.0),  -- 标准蓝色
    ColorDying = Color(0.15, 0.2, 0.4, 1.0),   -- 暗蓝色（濒死）
    ColorDead = Color(0.1, 0.1, 0.15, 0.8),    -- 极暗色（死亡）
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

    -- 生命值
    self.hp_ = Player.CONFIG.MaxHP
    self.maxHP_ = Player.CONFIG.MaxHP

    -- 角色状态
    self.state_ = Player.STATE.NORMAL
    self.invincibleTimer_ = 0    -- 无敌帧计时
    self.blinkTimer_ = 0        -- 闪烁计时
    self.blinkVisible_ = true   -- 当前是否可见（闪烁用）
    self.deathTimer_ = 0        -- 死亡倒地动画计时
    self.deathRotation_ = 0     -- 死亡时旋转角度

    -- 动作状态
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

    -- 回调
    self.onDeath = nil          -- 死亡完成回调 function()

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

    -- 死亡状态：只播放倒地动画
    if self.state_ == Player.STATE.DEAD then
        self:UpdateDeathAnim(dt)
        return
    end

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

    -- 更新无敌帧
    self:UpdateInvincibility(dt)

    -- 输入
    self:GatherInput()

    -- 移动
    self:UpdateMovement(dt)

    -- 攻击视觉
    self:UpdateAttackVisual()

    -- 攻击特效
    self:UpdateAttackFx(dt)

    -- 更新外观（根据状态）
    self:UpdateStateVisual()

    -- 消耗跳跃输入
    self.wantJump_ = false
end

function Player:UpdateMovement(dt)
    local cfg = Player.CONFIG

    -- 跳跃冷却
    if self.jumpGraceTimer_ > 0 then
        self.jumpGraceTimer_ = self.jumpGraceTimer_ - dt
    end

    -- 濒死时速度降低
    local speedMult = 1.0
    if self.state_ == Player.STATE.DYING then
        speedMult = cfg.DyingSpeedMult
    end

    local vel = self.body_:GetLinearVelocity()
    local desiredVelX = self.moveX_ * cfg.Speed * speedMult
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
    -- 攻击时颜色变白（短暂闪白）由 UpdateStateVisual 统一处理
    -- 这里仅保留攻击逻辑标记
end

-- ============================================================================
-- 状态系统
-- ============================================================================

--- 更新无敌帧计时和闪烁效果
function Player:UpdateInvincibility(dt)
    if self.state_ ~= Player.STATE.HURT then return end

    local cfg = Player.CONFIG
    self.invincibleTimer_ = self.invincibleTimer_ - dt

    -- 闪烁效果
    self.blinkTimer_ = self.blinkTimer_ - dt
    if self.blinkTimer_ <= 0 then
        self.blinkTimer_ = cfg.BlinkInterval
        self.blinkVisible_ = not self.blinkVisible_
        if self.node_ then
            self.node_:SetEnabled(self.blinkVisible_)
        end
    end

    -- 无敌时间结束
    if self.invincibleTimer_ <= 0 then
        self.invincibleTimer_ = 0
        self.blinkVisible_ = true
        if self.node_ then
            self.node_:SetEnabled(true)
        end
        -- 根据 HP 决定下一个状态
        if self.hp_ <= 1 then
            self:EnterState(Player.STATE.DYING)
        else
            self:EnterState(Player.STATE.NORMAL)
        end
    end
end

--- 更新死亡倒地动画
function Player:UpdateDeathAnim(dt)
    local cfg = Player.CONFIG
    self.deathTimer_ = self.deathTimer_ + dt

    -- 停止物理运动
    if self.body_ then
        self.body_:SetLinearVelocity(Vector2(0, self.body_:GetLinearVelocity().y))
    end

    -- 倒地旋转动画 (0 → 90度)
    local progress = math.min(self.deathTimer_ / cfg.DeathFallDuration, 1.0)
    -- 使用 easeOutBounce 缓动
    local eased = self:EaseOutBack(progress)
    self.deathRotation_ = eased * 90.0

    if self.node_ then
        -- 向面朝方向倒下
        local dir = self.facingRight_ and -1 or 1
        self.node_.rotation = Quaternion(dir * self.deathRotation_, Vector3.FORWARD)

        -- 同时更新颜色渐暗
        local model = self.node_:GetComponent("StaticModel")
        if model then
            local mat = model:GetMaterial(0)
            if mat then
                local c = cfg.ColorDead
                mat:SetShaderParameter("MatDiffColor", Variant(Color(c.r, c.g, c.b, 1.0 - progress * 0.3)))
            end
        end
    end

    -- 动画结束，触发 Game Over 回调
    if progress >= 1.0 and self.deathTimer_ < cfg.DeathFallDuration + 0.1 then
        self.deathTimer_ = cfg.DeathFallDuration + 0.1  -- 防止重复触发
        if self.onDeath then
            self.onDeath()
        end
    end
end

--- 缓动函数 - easeOutBack
function Player:EaseOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
end

--- 更新外观 (根据当前状态)
function Player:UpdateStateVisual()
    if not self.node_ then return end
    local model = self.node_:GetComponent("StaticModel")
    if not model then return end
    local mat = model:GetMaterial(0)
    if not mat then return end

    local cfg = Player.CONFIG

    if self.isAttacking_ then
        -- 攻击时闪白
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
    elseif self.state_ == Player.STATE.DYING then
        -- 濒死：暗色
        mat:SetShaderParameter("MatDiffColor", Variant(cfg.ColorDying))
    elseif self.state_ == Player.STATE.HURT then
        -- 受伤中：闪烁时保持正常色（可见性由 node enabled 控制）
        mat:SetShaderParameter("MatDiffColor", Variant(cfg.ColorNormal))
    else
        -- 正常状态
        mat:SetShaderParameter("MatDiffColor", Variant(cfg.ColorNormal))
    end
end

--- 切换状态
function Player:EnterState(newState)
    local oldState = self.state_
    self.state_ = newState

    if newState == Player.STATE.HURT then
        self.invincibleTimer_ = Player.CONFIG.InvincibleDuration
        self.blinkTimer_ = Player.CONFIG.BlinkInterval
        self.blinkVisible_ = true
    elseif newState == Player.STATE.DYING then
        -- 进入濒死：确保可见
        if self.node_ then
            self.node_:SetEnabled(true)
        end
    elseif newState == Player.STATE.DEAD then
        self.deathTimer_ = 0
        self.deathRotation_ = 0
        -- 确保可见
        if self.node_ then
            self.node_:SetEnabled(true)
        end
    elseif newState == Player.STATE.NORMAL then
        -- 恢复正常：确保可见
        if self.node_ then
            self.node_:SetEnabled(true)
        end
    end

    print("[Player] State: " .. oldState .. " -> " .. newState)
end

--- 是否处于无敌状态
function Player:IsInvincible()
    return self.state_ == Player.STATE.HURT or self.state_ == Player.STATE.DEAD
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

--- 受到伤害，自动处理状态切换
---@param amount number 伤害量
---@return number 剩余 HP
function Player:TakeDamage(amount)
    -- 无敌状态下不受伤
    if self:IsInvincible() then
        return self.hp_
    end

    self.hp_ = self.hp_ - amount
    if self.hp_ < 0 then self.hp_ = 0 end

    -- 根据剩余 HP 切换状态
    if self.hp_ <= 0 then
        self:EnterState(Player.STATE.DEAD)
    else
        -- 受伤进入无敌帧（无论是否濒死都先闪烁）
        self:EnterState(Player.STATE.HURT)
    end

    return self.hp_
end

function Player:IsDead()
    return self.state_ == Player.STATE.DEAD
end

--- 获取当前状态
function Player:GetState()
    return self.state_
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
        self.node_.rotation = Quaternion.IDENTITY
        self.node_:SetEnabled(true)
        self.body_:SetLinearVelocity(Vector2(0, 0))
    end

    self.hp_ = self.maxHP_
    self.state_ = Player.STATE.NORMAL
    self.invincibleTimer_ = 0
    self.blinkTimer_ = 0
    self.blinkVisible_ = true
    self.deathTimer_ = 0
    self.deathRotation_ = 0
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
