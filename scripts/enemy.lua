-- ============================================================================
-- Enemy 模块：怪物AI、属性标签、血条
-- ============================================================================

local CONFIG = require("config")

local Enemy = {}
Enemy.__index = Enemy

Enemy.STATE_IDLE    = "idle"
Enemy.STATE_PATROL  = "patrol"
Enemy.STATE_CHASE   = "chase"
Enemy.STATE_ATTACK  = "attack"

function Enemy.new(_, scene, x, y, element)
    local self = setmetatable({}, Enemy)

    self.hp = CONFIG.EnemyHP
    self.maxHp = CONFIG.EnemyHP
    self.element = element or CONFIG.Elements[math.random(1, #CONFIG.Elements)]
    self.state = Enemy.STATE_PATROL
    self.attackTimer = 0
    self.flashTimer = 0
    self.alive = true

    -- 巡逻
    self.patrolDir = 1
    self.patrolRange = 2.0
    self.spawnX = x

    self:_createNode(scene, x, y)
    return self
end

function Enemy:_createNode(scene, x, y)
    self.node = scene:CreateChild("Enemy")
    self.node.position = Vector3(x, y, 0)

    -- 视觉(方块，颜色对应属性)
    local model = self.node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local c = CONFIG.ElementColors[self.element] or { 200, 50, 50, 255 }
    mat:SetShaderParameter("MatDiffColor", Variant(Color(c[1]/255, c[2]/255, c[3]/255, 1.0)))
    model:SetMaterial(mat)
    self.node:SetScale(Vector3(CONFIG.EnemySize.w, CONFIG.EnemySize.h, 0.5))
    self._baseMat = mat

    -- 物理(Kinematic)
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_KINEMATIC
    self.body.fixedRotation = true

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(CONFIG.EnemySize.w, CONFIG.EnemySize.h)
    shape.isTrigger = true

    -- 血条(3D子节点)
    self:_createHPBar()
end

function Enemy:_createHPBar()
    local barW = 0.7
    local barH = 0.08
    local offsetY = CONFIG.EnemySize.h / 2 + 0.15
    local psx, psy, psz = CONFIG.EnemySize.w, CONFIG.EnemySize.h, 0.5

    -- 背景
    self.hpBarBG = self.node:CreateChild("HPBarBG")
    self.hpBarBG.position = Vector3(0, offsetY / psy, -0.2 / psz)
    self.hpBarBG:SetScale(Vector3(barW / psx, barH / psy, 0.01 / psz))
    local bgM = self.hpBarBG:CreateComponent("StaticModel")
    bgM:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local bgMat = Material:new()
    bgMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    bgMat:SetShaderParameter("MatDiffColor", Variant(Color(0.15, 0.15, 0.15, 1.0)))
    bgM:SetMaterial(bgMat)

    -- 填充
    self.hpBarFill = self.node:CreateChild("HPBarFill")
    self.hpBarFill.position = Vector3(0, offsetY / psy, -0.21 / psz)
    self.hpBarFill:SetScale(Vector3(barW / psx, barH / psy, 0.01 / psz))
    local fM = self.hpBarFill:CreateComponent("StaticModel")
    fM:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local fMat = Material:new()
    fMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    fMat:SetShaderParameter("MatDiffColor", Variant(Color(0.85, 0.15, 0.15, 1.0)))
    fM:SetMaterial(fMat)
    self._hpFillMat = fMat
    self._barW = barW
end

function Enemy:update(dt, playerPos)
    if not self.alive then return end

    -- 攻击冷却
    if self.attackTimer > 0 then
        self.attackTimer = self.attackTimer - dt
    end

    -- 闪白恢复
    if self.flashTimer > 0 then
        self.flashTimer = self.flashTimer - dt
        if self.flashTimer <= 0 then
            self:_resetColor()
        end
    end

    -- AI
    local pos = self.node.position
    local dx = playerPos.x - pos.x
    local dist = math.abs(dx)

    if dist <= CONFIG.EnemyAttackRange then
        self.state = Enemy.STATE_ATTACK
        self:_doAttack()
    elseif dist <= CONFIG.EnemyChaseRange then
        self.state = Enemy.STATE_CHASE
        local dir = dx > 0 and 1 or -1
        local moveX = dir * CONFIG.EnemySpeed * dt
        self.node.position = Vector3(pos.x + moveX, pos.y, pos.z)
    else
        self.state = Enemy.STATE_PATROL
        self:_patrol(dt)
    end

    -- 血条更新
    self:_updateHPBar()
end

function Enemy:_patrol(dt)
    local pos = self.node.position
    local moveX = self.patrolDir * CONFIG.EnemySpeed * 0.4 * dt
    local newX = pos.x + moveX

    if math.abs(newX - self.spawnX) > self.patrolRange then
        self.patrolDir = -self.patrolDir
    end
    self.node.position = Vector3(newX, pos.y, pos.z)
end

function Enemy:_doAttack()
    if self.attackTimer > 0 then return false end
    self.attackTimer = CONFIG.EnemyAttackCooldown
    -- 闪黄表示攻击
    if self._baseMat then
        self._baseMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.0, 1.0)))
        self.flashTimer = 0.2
    end
    return true  -- 外部检测用
end

function Enemy:shouldDealDamage()
    -- 在攻击冷却刚触发时返回true
    return self.state == Enemy.STATE_ATTACK and self.attackTimer >= (CONFIG.EnemyAttackCooldown - 0.05)
end

function Enemy:takeDamage(amount)
    if not self.alive then return end
    self.hp = math.max(0, self.hp - amount)

    -- 闪白
    if self._baseMat then
        self._baseMat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
        self.flashTimer = 0.12
    end

    if self.hp <= 0 then
        self.alive = false
        self.node:SetEnabled(false)
    end
end

function Enemy:_resetColor()
    if not self._baseMat then return end
    local c = CONFIG.ElementColors[self.element] or { 200, 50, 50, 255 }
    self._baseMat:SetShaderParameter("MatDiffColor", Variant(Color(c[1]/255, c[2]/255, c[3]/255, 1.0)))
end

function Enemy:_updateHPBar()
    if not self.hpBarFill then return end
    local pct = math.max(0, self.hp / self.maxHp)
    local psx = CONFIG.EnemySize.w
    local psy = CONFIG.EnemySize.h
    local psz = 0.5
    local barH = 0.08
    local offsetY = CONFIG.EnemySize.h / 2 + 0.15
    local fillW = self._barW * pct

    self.hpBarFill:SetScale(Vector3(fillW / psx, barH / psy, 0.01 / psz))
    local offsetX = -(1 - pct) * self._barW / 2
    self.hpBarFill.position = Vector3(offsetX / psx, offsetY / psy, -0.21 / psz)
end

function Enemy:getPosition()
    return self.node.position
end

return Enemy
