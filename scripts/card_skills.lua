---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- 卡牌技能效果执行模块
-- 负责：投射物创建/移动、AOE区域、控制效果等
local CardData = require("scripts/card_data")

CardSkills = {}
CardSkills.__index = CardSkills

-- 投射物/效果节点列表（每帧更新）
local activeProjectiles = {}
local activeAOEs = {}
local activeTraps = {}
local activeWalls = {}

-- ============ 特效精灵图配置 ============
-- 布局说明：
--   大多数特效：3列×3行网格(800x800)，使用前7帧（第3行只用左1帧）
--   N09(虚无之刃)：2列×4行网格(800x800)，使用8帧
local EFF_TEXTURES = {
    F01 = "image/Effect/eff_F01_fireball_Sheet_20260709090827.png",
    F03 = "image/Effect/eff_F03_lava_shard_Sheet_20260709085449.png",
    S01 = "image/Effect/eff_S01_seal_orb_Sheet_20260709085447.png",
    I01 = "image/Effect/eff_I01_ice_spike_Sheet_20260709092043.png",
    I02 = "image/Effect/eff_I02_ice_shard_Sheet_20260709092037.png",
    I03 = "image/Effect/eff_I03_frost_field_Sheet_20260709092053.png",
    W01 = "image/Effect/eff_W01_whirlwind_Sheet_20260627074458.png",
    W02 = "image/Effect/eff_W02_wind_blade_Sheet_20260627074502.png",
    W04 = "image/Effect/eff_W04_vacuum_slash_Sheet_20260627074503.png",
    T01 = "image/Effect/eff_T01_thunder_bolt_Sheet_20260627082844.png",
    T03 = "image/Effect/eff_T03_storm_field_Sheet_20260627082835.png",
    T04 = "image/Effect/eff_T04_instant_thunder_Sheet_20260627082838.png",
    E02 = "image/Effect/eff_E02_spike_trap_Sheet_20260627091221.png",
    E03 = "image/Effect/eff_E03_rock_wall_Sheet_20260627091243.png",
    E04 = "image/Effect/eff_E04_earth_crack_Sheet_20260627090820.png",
    N01 = "image/Effect/eff_N01_time_stop_Sheet_20260709112259.png",
    N02 = "image/Effect/eff_N02_time_rift_Sheet_20260709112258.png",
    N03 = "image/Effect/eff_N03_time_slow_Sheet_20260709112257.png",
    N06 = "image/Effect/eff_N06_teleport_Sheet_20260627090439.png",
    N07 = "image/Effect/eff_N07_dissolve_mark_Sheet_20260709092800.png",
    N08 = "image/Effect/eff_N08_matter_orb_Sheet_20260709092814.png",
    N09 = "image/Effect/eff_N09_void_slash_Sheet_20260709092811.png",
    N10 = "image/Effect/eff_N10_neutral_beam_Sheet_20260709101110.png",
}

-- 特效帧动画参数
local EFF_FPS = 10  -- 特效播放帧率

-- 获取卡牌的精灵图布局（cols, rows, frames）
local function getEffLayout(cardId)
    if cardId == "N09" then
        return 2, 4, 8  -- 2列×4行，8帧
    end
    return 3, 3, 7  -- 3列×3行，使用前7帧
end

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
--- 注意：场景重建后旧节点已被引擎释放，不能再调用 Remove()
function CardSkills:reset()
    -- 直接清空列表（场景重建时旧节点已被释放，调用 Remove() 会 crash）
    activeProjectiles = {}
    activeAOEs = {}
    activeTraps = {}
    activeWalls = {}
end

-- ============ 特效精灵创建辅助 ============

--- 创建带帧动画的特效精灵节点（替代纯色方块）
--- 返回: spriteNode, material, animInfo（帧动画信息）
function CardSkills:_createEffectNode(parentNode, card, displayW, displayH)
    local cardId = card.id
    local texPath = EFF_TEXTURES[cardId]

    local spriteNode = parentNode:CreateChild("EffSprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(displayW, 1.0, displayH)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()

    if texPath then
        local tex = cache:GetResource("Texture2D", texPath)
        if tex then
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
            mat:SetTexture(0, tex)
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
            -- 设置初始UV为第0帧
            local cols, rows, totalFrames = getEffLayout(cardId)
            local frameU = 1.0 / cols
            local frameV = 1.0 / rows
            mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, 0)))
            mat:SetShaderParameter("VOffset", Variant(Vector4(0, frameV, 0, 0)))
            model:SetMaterial(mat)
            -- 返回帧动画信息
            local animInfo = {
                mat = mat,
                cols = cols,
                rows = rows,
                totalFrames = totalFrames,
                frameTimer = 0,
                currentFrame = 0,
            }
            return spriteNode, mat, animInfo
        end
    end

    -- 回退：无贴图时使用纯色
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local elemInfo = CardData.ELEMENT_COLORS[card.element]
    local color = elemInfo and elemInfo.color or Color(1, 1, 1, 1)
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    model:SetMaterial(mat)
    return spriteNode, mat, nil
end

--- 更新帧动画（每帧调用）
local function updateEffAnim(animInfo, dt)
    if not animInfo then return end
    animInfo.frameTimer = animInfo.frameTimer + dt
    local frameDur = 1.0 / EFF_FPS
    if animInfo.frameTimer >= frameDur then
        animInfo.frameTimer = animInfo.frameTimer - frameDur
        animInfo.currentFrame = (animInfo.currentFrame + 1) % animInfo.totalFrames
        local col = animInfo.currentFrame % animInfo.cols
        local row = math.floor(animInfo.currentFrame / animInfo.cols)
        local frameU = 1.0 / animInfo.cols
        local frameV = 1.0 / animInfo.rows
        -- 检查是否需要水平翻转该帧
        local flip = false
        if animInfo.flipFrames then
            for _, f in ipairs(animInfo.flipFrames) do
                if f == animInfo.currentFrame then flip = true; break end
            end
        end
        if flip then
            animInfo.mat:SetShaderParameter("UOffset", Variant(Vector4(-frameU, 0, 0, (col + 1) * frameU)))
        else
            animInfo.mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, col * frameU)))
        end
        animInfo.mat:SetShaderParameter("VOffset", Variant(Vector4(0, frameV, 0, row * frameV)))
    end
end

-- ============ 技能实现 ============

--- 直线投射物
function CardSkills:_fireProjectile(card, pos, dir)
    local node = self.scene:CreateChild("Projectile")
    node.position = Vector3(pos.x + dir * 0.5, pos.y, -0.5)

    local projSize = 0.6
    if card.id == "F01" or card.id == "S01" then projSize = 1.2 end
    if card.id == "N08" then projSize = 0.9 end  -- N08放大0.5倍
    local spriteNode, _, animInfo = self:_createEffectNode(node, card, projSize, projSize)
    -- 根据方向翻转精灵（N08默认朝向相反，需反转）
    local flipDir = (card.id == "N08") and -dir or dir
    if flipDir < 0 then
        spriteNode.scale = Vector3(-projSize, 1.0, projSize)
    end

    table.insert(activeProjectiles, {
        node = node,
        speed = card.speed or 12.0,
        dir = dir,
        range = card.range or 15.0,
        startX = pos.x,
        card = card,
        hitList = {},
        pierce = card.pierce or 0,
        pierceCount = 0,
        animInfo = animInfo,
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
        node.position = Vector3(pos.x + dir * 0.3, pos.y, -0.5)

        local _, _, animInfo = self:_createEffectNode(node, card, 0.5, 0.5)

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
            animInfo = animInfo,
        })
    end
end

--- 地面刺出效果
function CardSkills:_groundSpike(card, pos, dir)
    local range = card.range or 3.0
    local visualRange = math.min(range, 3.0)  -- 限制视觉距离在视野内
    local targetX = pos.x + dir * visualRange

    local node = self.scene:CreateChild("GroundSpike")
    node.position = Vector3(targetX, pos.y - 0.8, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, 1.2, 1.2)
    -- 地面刺帧动画按持续时间匹配（不循环）
    if animInfo then
        animInfo.matchDuration = true
    end

    -- 伤害范围使用完整range
    local damageEndX = pos.x + dir * range
    self:_damageInRange(card, math.min(pos.x, damageEndX), math.max(pos.x, damageEndX), pos.y, 1.5)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.8,
        card = card,
        damageApplied = true,
        animInfo = animInfo,
    })
end

--- 自身AOE（以玩家为中心）
function CardSkills:_selfAOE(card, pos)
    local radius = card.radius or 2.0

    local node = self.scene:CreateChild("SelfAOE")
    node.position = Vector3(pos.x, pos.y + 0.3, -0.5)

    local displaySize = radius * 2
    local _, _, animInfo = self:_createEffectNode(node, card, displaySize, displaySize)

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
        followPlayer = true,
        animInfo = animInfo,
    })
end

--- 目标位置AOE
function CardSkills:_targetAOE(card, pos, dir)
    local radius = card.radius or 3.0
    local range = card.range or 5.0
    local targetX = pos.x + dir * math.min(range, 2.0)

    local node = self.scene:CreateChild("TargetAOE")
    local yOffset = 0.3
    if card.id == "T04" then yOffset = -0.2 end  -- T04特殊偏移
    if card.id == "N02" then yOffset = -0.3 end  -- N02下移0.6米
    node.position = Vector3(targetX, pos.y + yOffset, -0.5)

    local displaySize = radius
    local _, _, animInfo = self:_createEffectNode(node, card, displaySize, displaySize)

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
        animInfo = animInfo,
    })
end

--- Buff视觉效果（时间停止等全局效果）
function CardSkills:_showBuffEffect(card, pos)
    local node = self.scene:CreateChild("BuffFX")
    node.position = Vector3(pos.x, pos.y, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, 1.5, 1.5)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.5,
        card = card,
        damageApplied = true,
        animInfo = animInfo,
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

    -- 传送残影特效
    local node = self.scene:CreateChild("TeleportFX")
    node.position = Vector3(pos.x, pos.y - 0.8, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, 1.2, 1.2)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.4,
        card = card,
        damageApplied = true,
        animInfo = animInfo,
    })
end

--- 光束贯穿
function CardSkills:_beam(card, pos, dir)
    local range = card.range or 12.0

    local node = self.scene:CreateChild("Beam")
    local visualRange = math.min(range, 8.0)  -- 限制视觉长度在视野内
    local beamCenterX = pos.x + dir * (visualRange / 2 - 1.0)
    node.position = Vector3(beamCenterX, pos.y, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, visualRange / 2, visualRange / 2)
    -- N10第3帧(index=2)水平翻转
    if animInfo then
        animInfo.flipFrames = {2}
    end

    -- 伤害范围使用完整range
    local minX = dir > 0 and pos.x or (pos.x - range)
    local maxX = dir > 0 and (pos.x + range) or pos.x
    self:_damageInRange(card, minX, maxX, pos.y, 1.5)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.5,
        card = card,
        damageApplied = true,
        animInfo = animInfo,
    })
end

--- 放置陷阱
function CardSkills:_placeTrap(card, pos, dir)
    local range = card.range or 4.0
    local trapX = pos.x + dir * math.min(range, 3.0)

    -- 检查陷阱数量限制
    local maxTraps = card.maxTraps or 2
    local currentCount = 0
    for _, t in ipairs(activeTraps) do
        if t.cardId == card.id then
            currentCount = currentCount + 1
        end
    end
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
    node.position = Vector3(trapX, pos.y - 0.8, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, 0.8, 0.8)

    table.insert(activeTraps, {
        node = node,
        cardId = card.id,
        card = card,
        x = trapX,
        y = pos.y - 0.5,
        radius = 0.8,
        lifetime = 15.0,
        timer = 0,
        triggered = false,
        animInfo = animInfo,
    })
end

--- 放置岩壁
function CardSkills:_placeWall(card, pos, dir)
    local wallX = pos.x + dir * 1.5

    local node = self.scene:CreateChild("Wall")
    node.position = Vector3(wallX, pos.y - 0.65, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, 1.5, 1.5)

    local duration = card.duration or 3.0

    table.insert(activeWalls, {
        node = node,
        card = card,
        x = wallX,
        timer = 0,
        duration = duration,
        animInfo = animInfo,
    })
end

--- 近战斩击
function CardSkills:_meleeStrike(card, pos, dir)
    local range = card.range or 2.0
    local minX = dir > 0 and pos.x or (pos.x - range)
    local maxX = dir > 0 and (pos.x + range) or pos.x

    local slashX = pos.x + dir * range * 0.5
    local node = self.scene:CreateChild("MeleeSlash")
    node.position = Vector3(slashX, pos.y - 0.3, -0.5)

    -- N09是2:1比例(2列×4行), 其余技能1:1
    local meleeSize = 1.5
    local meleeW = (card.id == "N09") and (meleeSize * 2) or meleeSize
    local _, _, animInfo = self:_createEffectNode(node, card, meleeW, meleeSize)

    -- 立即伤害
    self:_damageInRange(card, minX, maxX, pos.y, 1.5)

    table.insert(activeAOEs, {
        node = node,
        timer = 0,
        duration = 0.3,
        card = card,
        damageApplied = true,
        animInfo = animInfo,
    })
end

--- DOT 效果（对前方最近敌人）
function CardSkills:_applyDOT(card, pos, dir)
    local target = self:_findNearestEnemy(pos, dir, card.range or 6.0)
    if not target then return end

    local node = self.scene:CreateChild("DOT_Mark")
    node.position = Vector3(target.node.position.x, target.node.position.y + 0.8, -0.5)

    local _, _, animInfo = self:_createEffectNode(node, card, 0.5, 0.5)

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
        animInfo = animInfo,
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

            -- 更新帧动画
            updateEffAnim(p.animInfo, dt)

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
            -- 更新帧动画
            if a.animInfo and a.animInfo.matchDuration then
                -- 帧数与持续时间匹配（不循环）
                local progress = math.min(a.timer / a.duration, 1.0)
                local targetFrame = math.floor(progress * (a.animInfo.totalFrames - 1))
                if targetFrame ~= a.animInfo.currentFrame then
                    a.animInfo.currentFrame = targetFrame
                    local col = targetFrame % a.animInfo.cols
                    local row = math.floor(targetFrame / a.animInfo.cols)
                    local frameU = 1.0 / a.animInfo.cols
                    local frameV = 1.0 / a.animInfo.rows
                    a.animInfo.mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, col * frameU)))
                    a.animInfo.mat:SetShaderParameter("VOffset", Variant(Vector4(0, frameV, 0, row * frameV)))
                end
            else
                updateEffAnim(a.animInfo, dt)
            end

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
                            a.node.position = Vector3(cx, cy, -0.5)
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

        -- 帧动画按存活时间匹配（不循环）
        if t.animInfo then
            local progress = math.min(t.timer / t.lifetime, 1.0)
            local targetFrame = math.floor(progress * (t.animInfo.totalFrames - 1))
            if targetFrame ~= t.animInfo.currentFrame then
                t.animInfo.currentFrame = targetFrame
                local col = targetFrame % t.animInfo.cols
                local row = math.floor(targetFrame / t.animInfo.cols)
                local frameU = 1.0 / t.animInfo.cols
                local frameV = 1.0 / t.animInfo.rows
                t.animInfo.mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, col * frameU)))
                t.animInfo.mat:SetShaderParameter("VOffset", Variant(Vector4(0, frameV, 0, row * frameV)))
            end
        end

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

        -- 帧动画按持续时间均匀分布（不循环）
        if w.animInfo then
            local progress = math.min(w.timer / w.duration, 1.0)
            local targetFrame = math.floor(progress * (w.animInfo.totalFrames - 1))
            if targetFrame ~= w.animInfo.currentFrame then
                w.animInfo.currentFrame = targetFrame
                local col = targetFrame % w.animInfo.cols
                local row = math.floor(targetFrame / w.animInfo.cols)
                local frameU = 1.0 / w.animInfo.cols
                local frameV = 1.0 / w.animInfo.rows
                w.animInfo.mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, col * frameU)))
                w.animInfo.mat:SetShaderParameter("VOffset", Variant(Vector4(0, frameV, 0, row * frameV)))
            end
        end

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
