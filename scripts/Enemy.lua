-- ============================================================================
-- Enemy 模块 - 小怪（创建、AI、3D血条、受击）
-- ============================================================================

local Enemy = {}
Enemy.__index = Enemy

-- ============================================================================
-- 配置
-- ============================================================================
Enemy.CONFIG = {
    HP = 10,                   -- 血量
    Size = { w = 0.5, h = 0.6 },
    SpawnX = 4.0,              -- 生成X坐标
    ChaseRange = 1.0,          -- 追逐触发距离 (米)
    AttackRange = 0.6,         -- 攻击范围 (米)
    Speed = 2.0,               -- 追逐速度 (m/s)
    AttackDamage = 1,          -- 每次攻击伤害
    AttackCooldown = 1.0,      -- 攻击冷却 (秒)
}

-- ============================================================================
-- 构造
-- ============================================================================

---@param scene Scene
---@return table
function Enemy.New(scene)
    local self = setmetatable({}, Enemy)

    self.scene_ = scene
    self.node_ = nil           ---@type Node
    self.body_ = nil           ---@type RigidBody2D
    self.hpBarNode_ = nil      ---@type Node
    self.hpFillNode_ = nil     ---@type Node

    -- 状态
    self.hp_ = Enemy.CONFIG.HP
    self.maxHP_ = Enemy.CONFIG.HP
    self.state_ = "idle"       -- idle / chase / attack
    self.attackTimer_ = 0
    self.triggered_ = false    -- 是否已触发追逐
    self.flashTimer_ = 0

    return self
end

-- ============================================================================
-- 创建/销毁
-- ============================================================================

function Enemy:Create(x, y)
    local cfg = Enemy.CONFIG
    self.hp_ = cfg.HP
    self.maxHP_ = cfg.HP

    self.node_ = self.scene_:CreateChild("Enemy")
    self.node_.position = Vector3(x, y, 0)

    -- 视觉 (红色方块)
    local model = self.node_:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.2, 0.2, 1.0)))
    model:SetMaterial(mat)
    self.node_:SetScale(Vector3(cfg.Size.w, cfg.Size.h, 0.5))

    -- 物理 (Kinematic)
    self.body_ = self.node_:CreateComponent("RigidBody2D")
    self.body_.bodyType = BT_KINEMATIC
    self.body_.fixedRotation = true

    local shape = self.node_:CreateComponent("CollisionBox2D")
    shape.size = Vector2(cfg.Size.w, cfg.Size.h)
    shape.isTrigger = true

    -- 3D 血条
    self:SpawnHPBar()

    return self
end

function Enemy:Destroy()
    self:DestroyHPBar()
    if self.node_ then
        self.node_:Remove()
        self.node_ = nil
        self.body_ = nil
    end
end

-- ============================================================================
-- 3D 血条
-- ============================================================================

function Enemy:SpawnHPBar()
    if not self.node_ then return end
    self:DestroyHPBar()

    local cfg = Enemy.CONFIG
    local barWidth = 0.6
    local barHeight = 0.08
    local offsetY = cfg.Size.h / 2 + 0.15

    local parentScaleX = cfg.Size.w
    local parentScaleY = cfg.Size.h
    local parentScaleZ = 0.5

    -- 背景条（深灰色）
    self.hpBarNode_ = self.node_:CreateChild("HPBarBG")
    self.hpBarNode_.position = Vector3(0, offsetY / parentScaleY, -0.2 / parentScaleZ)
    self.hpBarNode_:SetScale(Vector3(barWidth / parentScaleX, barHeight / parentScaleY, 0.01 / parentScaleZ))
    local bgModel = self.hpBarNode_:CreateComponent("StaticModel")
    bgModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local bgMat = Material:new()
    bgMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    bgMat:SetShaderParameter("MatDiffColor", Variant(Color(0.15, 0.15, 0.15, 1.0)))
    bgModel:SetMaterial(bgMat)

    -- 填充条（红色）
    self.hpFillNode_ = self.node_:CreateChild("HPBarFill")
    self.hpFillNode_.position = Vector3(0, offsetY / parentScaleY, -0.21 / parentScaleZ)
    self.hpFillNode_:SetScale(Vector3(barWidth / parentScaleX, barHeight / parentScaleY, 0.01 / parentScaleZ))
    local fillModel = self.hpFillNode_:CreateComponent("StaticModel")
    fillModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local fillMat = Material:new()
    fillMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    fillMat:SetShaderParameter("MatDiffColor", Variant(Color(0.85, 0.15, 0.15, 1.0)))
    fillModel:SetMaterial(fillMat)
end

function Enemy:DestroyHPBar()
    if self.hpBarNode_ then
        self.hpBarNode_:Remove()
        self.hpBarNode_ = nil
    end
    if self.hpFillNode_ then
        self.hpFillNode_:Remove()
        self.hpFillNode_ = nil
    end
end

function Enemy:UpdateHPBar()
    if not self.hpFillNode_ or self.hp_ <= 0 then return end

    local cfg = Enemy.CONFIG
    local pct = math.max(0, self.hp_ / self.maxHP_)
    local barWidth = 0.6
    local barHeight = 0.08
    local parentScaleX = cfg.Size.w
    local parentScaleY = cfg.Size.h
    local parentScaleZ = 0.5

    local fillW = barWidth * pct
    self.hpFillNode_:SetScale(Vector3(fillW / parentScaleX, barHeight / parentScaleY, 0.01 / parentScaleZ))

    local offsetY = cfg.Size.h / 2 + 0.15
    local offsetX = -(1 - pct) * barWidth / 2
    self.hpFillNode_.position = Vector3(offsetX / parentScaleX, offsetY / parentScaleY, -0.21 / parentScaleZ)
end

-- ============================================================================
-- AI 更新
-- ============================================================================

--- 更新小怪 AI
---@param dt number
---@param playerPos2D Vector2|nil 玩家位置
---@return string|nil event 返回事件: "attack_hit" 表示攻击命中玩家
function Enemy:Update(dt, playerPos2D)
    if not self.node_ or self.hp_ <= 0 then
        self.state_ = "idle"
        return nil
    end

    local cfg = Enemy.CONFIG

    -- 攻击冷却
    if self.attackTimer_ > 0 then
        self.attackTimer_ = self.attackTimer_ - dt
    end

    -- 闪白恢复
    self:UpdateFlash(dt)

    -- 无玩家则待机
    if not playerPos2D then
        self.state_ = "idle"
        return nil
    end

    -- 计算距离
    local enemyPos = self.node_.position
    local dx = playerPos2D.x - enemyPos.x
    local dy = playerPos2D.y - enemyPos.y
    local dist = math.abs(dx)

    -- 判断玩家是否在上方（垂直偏移超过小怪身高一半则视为"上方"）
    local playerAbove = dy > cfg.Size.h * 0.5

    -- 进入追逐范围后永久触发
    if dist <= cfg.ChaseRange and not playerAbove then
        self.triggered_ = true
    end

    if dist <= cfg.AttackRange and not playerAbove then
        -- 攻击状态：只有玩家位于左右两侧才攻击
        self.state_ = "attack"

        if self.attackTimer_ <= 0 then
            self.attackTimer_ = cfg.AttackCooldown
            -- 攻击闪黄
            local model = self.node_:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.0, 1.0)))
                end
            end
            self.flashTimer_ = 0.15
            return "attack_hit"
        end
    elseif self.triggered_ and not playerAbove then
        -- 追逐状态：玩家在上方时不追
        self.state_ = "chase"
        local dir = dx > 0 and 1 or -1
        local moveAmount = dir * cfg.Speed * dt
        self.node_.position = Vector3(enemyPos.x + moveAmount, enemyPos.y, enemyPos.z)
    else
        self.state_ = "idle"
    end

    return nil
end

function Enemy:UpdateFlash(dt)
    if self.flashTimer_ > 0 then
        self.flashTimer_ = self.flashTimer_ - dt
        if self.flashTimer_ <= 0 then
            local model = self.node_:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.2, 0.2, 1.0)))
                end
            end
        end
    end
end

-- ============================================================================
-- 受击
-- ============================================================================

function Enemy:TakeDamage(amount)
    self.hp_ = self.hp_ - amount
    -- 受击闪白
    self.flashTimer_ = 0.12
    local model = self.node_:GetComponent("StaticModel")
    if model then
        local mat = model:GetMaterial(0)
        if mat then
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
        end
    end

    if self.hp_ <= 0 then
        self.hp_ = 0
        self.node_:SetEnabled(false)
        self:DestroyHPBar()
        print("Enemy defeated!")
    end

    return self.hp_
end

function Enemy:IsDead()
    return self.hp_ <= 0
end

function Enemy:IsInAttackState()
    return self.state_ == "attack"
end

function Enemy:GetAttackDamage()
    return Enemy.CONFIG.AttackDamage
end

-- ============================================================================
-- 重置
-- ============================================================================

function Enemy:Reset()
    local cfg = Enemy.CONFIG
    self.hp_ = cfg.HP
    self.maxHP_ = cfg.HP
    self.state_ = "idle"
    self.attackTimer_ = 0
    self.triggered_ = false
    self.flashTimer_ = 0

    if self.node_ then
        self.node_.position = Vector3(cfg.SpawnX, 0.3, 0)
        self.node_:SetEnabled(true)
    end
    if self.body_ then
        self.body_:SetLinearVelocity(Vector2(0, 0))
    end

    -- 恢复颜色
    if self.node_ then
        local model = self.node_:GetComponent("StaticModel")
        if model then
            local mat = model:GetMaterial(0)
            if mat then
                mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.2, 0.2, 1.0)))
            end
        end
    end

    -- 重建血条
    self:SpawnHPBar()
end

return Enemy
