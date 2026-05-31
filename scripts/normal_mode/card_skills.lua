-- 卡牌技能效果执行模块
-- 负责：投射物创建/移动、AOE区域、控制效果等
local CardData = require("scripts/normal_mode/card_data")

CardSkills = {}
CardSkills.__index = CardSkills

-- 投射物/效果节点列表（每帧更新）
local activeProjectiles = {}
local activeAOEs = {}
local activeTraps = {}
local activeWalls = {}

function CardSkills:new(scene, player, enemies, cardSystem)
    local o = setmetatable({}, CardSkills)
    o.scene = scene
    o.player = player
    o.enemies = enemies
    o.cardSystem = cardSystem
    return o
end

--- 执行卡牌技能
---@param card table 卡牌数据
function CardSkills:execute(card)
    local skillType = card.skillType
    local playerPos = self.player:getPosition()
    local faceDir = self.player.facingRight and 1 or -1

    if skillType == "projectile" then
        self:_fireProjectile(card, playerPos, faceDir)
    elseif skillType == "fan_proj" then
        self:_fireFanProjectile(card, playerPos, faceDir)
    elseif skillType == "ground_spike" then
        self:_groundSpike(card, playerPos, faceDir)
    elseif skillType == "self_aoe" then
        self:_selfAOE(card, playerPos)
    elseif skillType == "target_aoe" then
        self:_targetAOE(card, playerPos, faceDir)
    elseif skillType == "buff" then
        -- buff/全局效果已在 card_system._executeCast 中处理
        self:_showBuffEffect(card, playerPos)
    elseif skillType == "teleport" then
        self:_teleport(card, playerPos, faceDir)
    elseif skillType == "beam" then
        self:_beam(card, playerPos, faceDir)
    elseif skillType == "trap" then
        self:_placeTrap(card, playerPos, faceDir)
    elseif skillType == "wall" then
        self:_placeWall(card, playerPos, faceDir)
    elseif skillType == "melee" then
        self:_meleeStrike(card, playerPos, faceDir)
    elseif skillType == "dot" then
        self:_applyDOT(card, playerPos, faceDir)
    end

    log:Write(LOG_INFO, "[CardSkills] Execute: " .. card.name .. " (" .. skillType .. ")")
end

--- 每帧更新所有活跃的技能效果
function CardSkills:update(dt)
    self:_updateProjectiles(dt)
    self:_updateAOEs(dt)
    self:_updateTraps(dt)
    self:_updateWalls(dt)
end

--- 重置所有效果（游戏重开时）
function CardSkills:reset()
    -- 清除投射物
    for _, p in ipairs(activeProjectiles) do
        if p.node then p.node:Remove() end
    end
    activeProjectiles = {}
    -- 清除AOE
    for _, a in ipairs(activeAOEs) do
        if a.node then a.node:Remove() end
    end
    activeAOEs = {}
    -- 清除陷阱
    for _, t in ipairs(activeTraps) do
        if t.node then t.node:Remove() end
    end
    activeTraps = {}
    -- 清除墙壁
    for _, w in ipairs(activeWalls) do
        if w.node then w.node:Remove() end
    end
    activeWalls = {}
end

-- ============ 技能实现 ============

--- 直线投射物
function CardSkills:_fireProjectile(card, pos, dir)
    local node = self.scene:CreateChild("Projectile")
    node.position = Vector3(pos.x + dir * 0.5, pos.y, 1.5)

    -- 视觉：小方块 + 属性颜色
    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(0.4, 1.0, 0.4)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(1, 1, 1, 1)
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    model:SetMaterial(mat)

    table.insert(activeProjectiles, {
        node = node,
        speed = card.speed or 12.0,
        dir = dir,
        range = card.range or 15.0,
        startX = pos.x,
        card = card,
        hitList = {},  -- 已命中的敌人（防重复）
        pierce = card.pierce or 0,
        pierceCount = 0,
    })
end

--- 扇形投射物
function CardSkills:_fireFanProjectile(card, pos, dir)
    local hits = card.hits or 3
    local fanAngle = card.fanAngle or 30
    local angleStep = fanAngle / math.max(1, hits - 1)
    local startAngle = -fanAngle / 2

    for i = 1, hits do
        local angle = startAngle + (i - 1) * angleStep
        local radians = math.rad(angle)
        local vx = dir * math.cos(radians)
        local vy = math.sin(radians)

        local node = self.scene:CreateChild("FanProj")
        node.position = Vector3(pos.x + dir * 0.3, pos.y, 1.5)

        local spriteNode = node:CreateChild("Sprite")
        spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        spriteNode.scale = Vector3(0.25, 1.0, 0.25)

        local model = spriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        local elemInfo = CardData.ELEMENT_COLORS[card.element]
        local color = elemInfo and elemInfo.color or Color(1, 1, 1, 1)
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        model:SetMaterial(mat)

        table.insert(activeProjectiles, {
            node = node,
            speed = card.speed or 10.0,
            dirX = vx,
            dirY = vy,
            range = card.range or 10.0,
            startX = pos.x,
            card = card,
            hitList = {},
            pierce = 0,
            pierceCount = 0,
            isFan = true,
        })
    end
end

--- 地面刺出效果
function CardSkills:_groundSpike(card, pos, dir)
    local range = card.range or 3.0
    local targetX = pos.x + dir * range

    -- 在前方创建地刺效果（Y位置上移，高度缩小，避免覆盖地面）
    local node = self.scene:CreateChild("GroundSpike")
    node.position = Vector3(targetX, pos.y + 0.2, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(range * 0.8, 1.0, 0.8)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(0.5, 0.8, 1, 0.8)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.7)))
    model:SetMaterial(mat)

    -- 立即对范围内敌人造成伤害
    self:_damageInRange(card, pos.x, targetX, pos.y, 1.5)

    -- 0.8秒后消失
    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.8,
        card = card,
        damageApplied = true,  -- 已经伤害过了
    })
end

--- 自身AOE（以玩家为中心）
function CardSkills:_selfAOE(card, pos)
    local radius = card.radius or 2.0

    -- Y位置上移、高度限制，避免覆盖地面
    local node = self.scene:CreateChild("SelfAOE")
    node.position = Vector3(pos.x, pos.y + 0.3, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    local displayH = math.min(radius * 2, 1.5)
    spriteNode.scale = Vector3(radius * 2, 1.0, displayH)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(1, 1, 1, 0.5)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.4)))
    model:SetMaterial(mat)

    local duration = card.duration or 0.5
    local tickInterval = card.tickInterval or 0.5

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = duration,
        card = card,
        tickTimer = 0,
        tickInterval = tickInterval,
        centerX = pos.x,
        centerY = pos.y,
        radius = radius,
        followPlayer = true,  -- 跟随玩家
    })
end

--- 目标位置AOE
function CardSkills:_targetAOE(card, pos, dir)
    local radius = card.radius or 3.0
    local range = card.range or 5.0 -- 使用 range 或默认在前方5m
    -- 如果是 freezeInArea 类型，放在前方
    local targetX = pos.x + dir * math.min(range, 4.0)

    -- Y位置上移、高度限制为1.5，避免覆盖地面
    local node = self.scene:CreateChild("TargetAOE")
    node.position = Vector3(targetX, pos.y + 0.3, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    local displayH = math.min(radius * 2, 1.5)  -- 限高，不超出地面
    spriteNode.scale = Vector3(radius * 2, 1.0, displayH)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(1, 1, 0.5, 0.5)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.35)))
    model:SetMaterial(mat)

    local duration = card.duration or 3.0
    local tickInterval = card.tickInterval or 0.8

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = duration,
        card = card,
        tickTimer = 0,
        tickInterval = tickInterval,
        centerX = targetX,
        centerY = pos.y,
        radius = radius,
        followPlayer = false,
    })
end

--- Buff视觉效果（时间停止等全局效果）
function CardSkills:_showBuffEffect(card, pos)
    -- 简单闪光特效
    local node = self.scene:CreateChild("BuffFX")
    node.position = Vector3(pos.x, pos.y, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(1.5, 1.0, 1.5)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(1, 1, 1, 1)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.6)))
    model:SetMaterial(mat)

    -- 短暂显示后消失
    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.5,
        card = card,
        damageApplied = true,
    })
end

--- 传送
function CardSkills:_teleport(card, pos, dir)
    local maxDist = card.maxDist or 5.0
    local newX = pos.x + dir * maxDist

    -- 途经伤害
    local minX = math.min(pos.x, newX)
    local maxX = math.max(pos.x, newX)
    self:_damageInRange(card, minX, maxX, pos.y, 1.5)

    -- 移动玩家
    self.player.node.position = Vector3(newX, pos.y, pos.z or -1)

    -- 短暂无敌
    if card.invincibleTime then
        self.player.invincible = true
        self.player.invincibleTimer = card.invincibleTime
        self.player.blinkTimer = 0
    end

    -- 闪光效果
    local node = self.scene:CreateChild("TeleportFX")
    node.position = Vector3(pos.x, pos.y, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(0.8, 1.0, 1.5)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.8, 1.0, 0.7)))
    model:SetMaterial(mat)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.4,
        card = card,
        damageApplied = true,
    })
end

--- 光束贯穿
function CardSkills:_beam(card, pos, dir)
    local range = card.range or 12.0

    local node = self.scene:CreateChild("Beam")
    local beamCenterX = pos.x + dir * range / 2
    node.position = Vector3(beamCenterX, pos.y, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(range, 1.0, 0.3)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(1, 1, 1, 0.8)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.7)))
    model:SetMaterial(mat)

    -- 贯穿所有敌人
    local minX = dir > 0 and pos.x or (pos.x - range)
    local maxX = dir > 0 and (pos.x + range) or pos.x
    self:_damageInRange(card, minX, maxX, pos.y, 1.5)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.5,
        card = card,
        damageApplied = true,
    })
end

--- 放置陷阱
function CardSkills:_placeTrap(card, pos, dir)
    local range = card.range or 4.0
    local trapX = pos.x + dir * range

    -- 检查陷阱数量限制
    local maxTraps = card.maxTraps or 2
    local currentCount = 0
    for _, t in ipairs(activeTraps) do
        if t.cardId == card.id then
            currentCount = currentCount + 1
        end
    end
    -- 超出限制时移除最早的
    if currentCount >= maxTraps then
        for i, t in ipairs(activeTraps) do
            if t.cardId == card.id then
                if t.node then t.node:Remove() end
                table.remove(activeTraps, i)
                break
            end
        end
    end

    local node = self.scene:CreateChild("Trap")
    node.position = Vector3(trapX, pos.y - 0.5, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(0.8, 1.0, 0.3)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(0.6, 0.3, 0.0, 0.8)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.6)))
    model:SetMaterial(mat)

    table.insert(activeTraps, {
        node = node,
        cardId = card.id,
        card = card,
        x = trapX,
        y = pos.y - 0.5,
        radius = 0.8,
        lifetime = 15.0,  -- 陷阱存活15秒
        timer = 0,
        triggered = false,
    })
end

--- 放置岩壁
function CardSkills:_placeWall(card, pos, dir)
    local wallX = pos.x + dir * 1.5

    local node = self.scene:CreateChild("Wall")
    node.position = Vector3(wallX, pos.y, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(0.5, 1.0, 2.0)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(0.5, 0.3, 0.1, 1.0)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.85)))
    model:SetMaterial(mat)

    local duration = card.duration or 3.0

    table.insert(activeWalls, {
        node = node,
        card = card,
        x = wallX,
        timer = 0,
        duration = duration,
    })
end

--- 近战斩击
function CardSkills:_meleeStrike(card, pos, dir)
    local range = card.range or 2.0
    local minX = dir > 0 and pos.x or (pos.x - range)
    local maxX = dir > 0 and (pos.x + range) or pos.x

    -- 视觉效果
    local slashX = pos.x + dir * range * 0.5
    local node = self.scene:CreateChild("MeleeSlash")
    node.position = Vector3(slashX, pos.y, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(range, 1.0, 0.8)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(0.8, 0.8, 0.8, 0.7)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.6)))
    model:SetMaterial(mat)

    -- 立即伤害
    self:_damageInRange(card, minX, maxX, pos.y, 1.5)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.3,
        card = card,
        damageApplied = true,
    })
end

--- DOT 效果（对前方最近敌人）
function CardSkills:_applyDOT(card, pos, dir)
    -- 找前方最近敌人
    local target = self:_findNearestEnemy(pos, dir, card.range or 6.0)
    if not target then return end

    -- 视觉标记
    local node = self.scene:CreateChild("DOT_Mark")
    node.position = Vector3(target.node.position.x, target.node.position.y + 0.8, 1.5)

    local spriteNode = node:CreateChild("Sprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(0.5, 1.0, 0.5)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(0.5, 0, 0.5, 0.8)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(color.r, color.g, color.b, 0.7)))
    model:SetMaterial(mat)

    local duration = card.duration or 3.0

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = duration,
        card = card,
        tickTimer = 0,
        tickInterval = 1.0,
        targetEnemy = target,
        isDOT = true,
    })
end

-- ============ 更新逻辑 ============

function CardSkills:_updateProjectiles(dt)
    local i = 1
    while i <= #activeProjectiles do
        local p = activeProjectiles[i]
        local removed = false

        if p.node then
            local pos = p.node.position
            local newX, newY

            if p.isFan then
                newX = pos.x + p.dirX * p.speed * dt
                newY = pos.y + p.dirY * p.speed * dt
            else
                newX = pos.x + p.dir * p.speed * dt
                newY = pos.y
            end

            p.node.position = Vector3(newX, newY, pos.z)

            -- 检测命中敌人
            for _, e in ipairs(self.enemies) do
                if e:isAlive() and e.node and not p.hitList[e] then
                    local ePos = e.node.position
                    local distX = math.abs(newX - ePos.x)
                    local distY = math.abs(newY - ePos.y)
                    if distX < 0.6 and distY < 0.8 then
                        -- 命中
                        p.hitList[e] = true
                        local dmg, isCounter = self.cardSystem:calculateDamage(
                            p.card.id, e.element, e.hp)
                        e:takeDamage(dmg, self.player:getPosition().x)
                        if isCounter then
                            log:Write(LOG_INFO, "[CardSkills] COUNTER! " .. p.card.name .. " → " .. e.element)
                        end

                        -- 溅射
                        if p.card.splashRadius and p.card.splashDamage then
                            self:_splashDamage(p.card, ePos.x, ePos.y, e)
                        end

                        -- 穿透检查
                        p.pierceCount = p.pierceCount + 1
                        if p.pierceCount > p.pierce then
                            p.node:Remove()
                            removed = true
                            break
                        end
                    end
                end
            end

            -- 超出射程
            if not removed then
                local traveled = math.abs(newX - p.startX)
                if traveled >= p.range then
                    p.node:Remove()
                    removed = true
                end
            end
        else
            removed = true
        end

        if removed then
            table.remove(activeProjectiles, i)
        else
            i = i + 1
        end
    end
end

function CardSkills:_updateAOEs(dt)
    local i = 1
    while i <= #activeAOEs do
        local a = activeAOEs[i]
        a.timer = a.timer + dt
        local removed = false

        if a.timer >= a.duration then
            if a.node then a.node:Remove() end
            removed = true
        else
            -- DOT 跟踪目标
            if a.isDOT and a.targetEnemy then
                if a.targetEnemy:isAlive() and a.targetEnemy.node then
                    a.node.position = Vector3(
                        a.targetEnemy.node.position.x,
                        a.targetEnemy.node.position.y + 0.8,
                        -0.6)
                else
                    if a.node then a.node:Remove() end
                    removed = true
                end
            end

            -- AOE tick 伤害
            if not removed and a.tickInterval and not a.damageApplied then
                a.tickTimer = a.tickTimer + dt
                if a.tickTimer >= a.tickInterval then
                    a.tickTimer = a.tickTimer - a.tickInterval
                    if a.isDOT and a.targetEnemy then
                        -- DOT：对单体持续伤害
                        if a.targetEnemy:isAlive() then
                            local dmg, _ = self.cardSystem:calculateDamage(
                                a.card.id, a.targetEnemy.element, a.targetEnemy.hp)
                            a.targetEnemy:takeDamage(math.max(1, dmg), self.player:getPosition().x)
                        end
                    elseif a.radius then
                        -- AOE：对区域内所有敌人伤害
                        local cx = a.centerX
                        local cy = a.centerY
                        if a.followPlayer then
                            local pp = self.player:getPosition()
                            cx = pp.x
                            cy = pp.y
                            a.node.position = Vector3(cx, cy, 1.5)
                        end
                        for _, e in ipairs(self.enemies) do
                            if e:isAlive() and e.node then
                                local ex = e.node.position.x
                                local ey = e.node.position.y
                                local dist = math.sqrt((ex - cx)^2 + (ey - cy)^2)
                                if dist <= a.radius then
                                    local dmg, _ = self.cardSystem:calculateDamage(
                                        a.card.id, e.element, e.hp)
                                    e:takeDamage(math.max(1, dmg), cx)
                                end
                            end
                        end
                    end
                end
            end
        end

        if removed then
            table.remove(activeAOEs, i)
        else
            i = i + 1
        end
    end
end

function CardSkills:_updateTraps(dt)
    local i = 1
    while i <= #activeTraps do
        local t = activeTraps[i]
        t.timer = t.timer + dt
        local removed = false

        -- 超时消失
        if t.timer >= t.lifetime then
            if t.node then t.node:Remove() end
            removed = true
        elseif not t.triggered then
            -- 检测敌人踩到
            for _, e in ipairs(self.enemies) do
                if e:isAlive() and e.node then
                    local ex = e.node.position.x
                    local ey = e.node.position.y
                    if math.abs(ex - t.x) < t.radius and math.abs(ey - t.y) < 1.0 then
                        -- 触发陷阱！
                        t.triggered = true
                        local dmg, isCounter = self.cardSystem:calculateDamage(
                            t.card.id, e.element, e.hp)
                        e:takeDamage(dmg, t.x)
                        if isCounter then
                            log:Write(LOG_INFO, "[CardSkills] Trap COUNTER!")
                        end
                        -- 视觉反馈：变亮后消失
                        if t.node then t.node:Remove() end
                        removed = true
                        break
                    end
                end
            end
        end

        if removed then
            table.remove(activeTraps, i)
        else
            i = i + 1
        end
    end
end

function CardSkills:_updateWalls(dt)
    local i = 1
    while i <= #activeWalls do
        local w = activeWalls[i]
        w.timer = w.timer + dt
        local removed = false

        if w.timer >= w.duration then
            if w.node then w.node:Remove() end
            removed = true
        else
            -- 墙壁阻挡效果：让靠近的敌人反弹
            for _, e in ipairs(self.enemies) do
                if e:isAlive() and e.node then
                    local ex = e.node.position.x
                    if math.abs(ex - w.x) < 0.4 then
                        -- 反弹敌人
                        local pushDir = ex > w.x and 1 or -1
                        e.node.position = Vector3(w.x + pushDir * 0.5, e.node.position.y, e.node.position.z)
                    end
                end
            end
        end

        if removed then
            table.remove(activeWalls, i)
        else
            i = i + 1
        end
    end
end

-- ============ 辅助方法 ============

--- 范围伤害（minX~maxX, y±threshold）
function CardSkills:_damageInRange(card, minX, maxX, y, yThreshold)
    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local ex = e.node.position.x
            local ey = e.node.position.y
            if ex >= minX and ex <= maxX and math.abs(ey - y) < yThreshold then
                local dmg, isCounter = self.cardSystem:calculateDamage(card.id, e.element, e.hp)
                e:takeDamage(dmg, (minX + maxX) / 2)
                if isCounter then
                    log:Write(LOG_INFO, "[CardSkills] COUNTER! " .. card.name)
                end
            end
        end
    end
end

--- 溅射伤害
function CardSkills:_splashDamage(card, cx, cy, excludeEnemy)
    local splashRadius = card.splashRadius or 2.0
    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node and e ~= excludeEnemy then
            local ex = e.node.position.x
            local ey = e.node.position.y
            local dist = math.sqrt((ex - cx)^2 + (ey - cy)^2)
            if dist <= splashRadius then
                -- 溅射伤害为主伤害的比例
                local splashDmg = math.max(1, math.floor(
                    self.cardSystem:getCountdown() * (card.splashDamage or 0.5)))
                e:takeDamage(splashDmg, cx)
            end
        end
    end
end

--- 查找前方最近敌人
function CardSkills:_findNearestEnemy(pos, dir, maxRange)
    local nearest = nil
    local nearestDist = maxRange + 1

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local ex = e.node.position.x
            local inFront = (dir > 0 and ex > pos.x) or (dir < 0 and ex < pos.x)
            if inFront then
                local dist = math.abs(ex - pos.x)
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = e
                end
            end
        end
    end
    return nearest
end

return CardSkills
