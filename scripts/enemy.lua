-- Enemy 类：敌人（与玩家同尺寸，头上有血条UI）
Enemy = {}
Enemy.__index = Enemy

local ENEMY_HP = 10
local PATROL_SPEED = 1.5
local PATROL_RANGE = 0.5
local CHASE_RANGE = 1.0
local CHASE_SPEED = 2.5
local ATTACK_RANGE = 1.0
local ATTACK_DAMAGE = 1
local ATTACK_COOLDOWN = 1.0  -- 每秒攻击一次
local FRONT_CHECK_DIST = 1.0  -- 前方友军检测距离

-- 属性定义：颜色 + 克制关系
Enemy.ELEMENTS = {
    fire  = { name = "火", icon = "🔥", color = Color(1.0, 0.3, 0.1, 1.0),  beats = { "wind", "ice" }, weak = { "water" } },
    water = { name = "水", icon = "💧", color = Color(0.1, 0.5, 1.0, 1.0),  beats = { "fire" },        weak = { "thunder" } },
    thunder = { name = "雷", icon = "⚡", color = Color(0.9, 0.8, 0.1, 1.0), beats = { "water" },       weak = { "wind" } },
    wind  = { name = "风", icon = "🌪️", color = Color(0.2, 0.9, 0.4, 1.0),  beats = { "thunder" },     weak = { "fire" } },
    ice   = { name = "冰", icon = "❄️", color = Color(0.5, 0.9, 1.0, 1.0),  beats = { "wind", "thunder" }, weak = { "fire" } },
}

function Enemy:new(scene, camera, player, x, y, element, isBoss)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, Enemy)
    self.isBoss = isBoss or false
    local hp = self.isBoss and ENEMY_HP * 3 or ENEMY_HP  -- Boss 3倍血量
    self.hp = hp
    self.maxHp = hp
    -- Boss与小怪差异化属性
    self.patrolSpeed = self.isBoss and 1.8 or PATROL_SPEED
    self.chaseSpeed = self.isBoss and 1.8 or CHASE_SPEED
    self.attackRange = self.isBoss and 2.0 or ATTACK_RANGE
    self.patrolRange = self.isBoss and 1.0 or PATROL_RANGE
    self.alive = true
    self.scene = scene
    self.camera = camera
    self.player = player
    self.startX = x
    self.spawnY = y
    self.element = element or "fire"
    self.elementData = Enemy.ELEMENTS[self.element]
    self.patrolDir = 1
    self.chasing = false
    self.attacking = false
    self.attackTimer = 0
    self.blockedByAlly = false  -- 前方有友军，暂停追逐
    self.enemyList = nil        -- 在 main.lua 创建后赋值
    self.hpBarContainer = nil
    self.hpBarFill = nil
    self.chaseWarning = nil
    self.attackWarning = nil
    self:_createNode(scene, x, y)
    self:_createHpBar()
    self:_createChaseWarning()
    self:_createAttackWarning()
    return self
end

function Enemy:_createNode(scene, x, y)
    self.node = scene:CreateChild("Enemy_" .. self.element)
    self.node.position = Vector3(x, y, 0)

    -- Boss 体型：1:1 正方形，3倍大小；普通怪：0.8x1.2
    local scale = self.isBoss and 3.0 or 1.0
    local halfW, halfH
    if self.isBoss then
        halfW = 1.2  -- 1:1 正方形，边长2.4（普通怪宽0.8的3倍）
        halfH = 1.2
    else
        halfW = 0.4
        halfH = 0.6
    end

    -- 可视化
    if self.isBoss then
        -- Boss使用 Texture2D + Material + Plane（和Player相同方式）
        self.spriteNode = self.node:CreateChild("BossSprite")
        self.spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        self.spriteNode.scale = Vector3(halfW * 2, 1.0, halfH * 2)
        local bossTexture = cache:GetResource("Texture2D", "image/Enemy/boss_01.png")
        if bossTexture then
            local mat = Material:new()
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
            mat:SetTexture(0, bossTexture)
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
            mat:SetShaderParameter("UOffset", Variant(Vector4(1, 0, 0, 0)))
            mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
            local model = self.spriteNode:CreateComponent("StaticModel")
            model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
            model:SetMaterial(mat)
            self.bossMaterial = mat
        else
            log:Write(LOG_ERROR, "[Enemy] Failed to load boss texture")
        end
    else
        local sprite = self.node:CreateComponent("StaticSprite2D")
        sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
        sprite.color = self.elementData.color
        sprite.drawRect = Rect(-halfW, -halfH, halfW, halfH)
        self.sprite = sprite
    end

    -- 物理
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_DYNAMIC
    self.body.fixedRotation = true
    self.body.linearDamping = 0.5

    if self.isBoss then
        -- Boss：胶囊碰撞体（按boss尺寸缩放）
        local bossRadius = halfW  -- 半径=半宽=1.2
        local bossBoxH = halfH * 2 - bossRadius * 2  -- 中段高度
        if bossBoxH < 0.1 then bossBoxH = 0.1 end

        -- maskBits: 排除玩家(2)，与地面(1)+敌人(4)碰撞 = 0xFFFF & ~2 = 65533
        local MASK_NO_PLAYER = 65533

        local boxShape = self.node:CreateComponent("CollisionBox2D")
        boxShape.size = Vector2(halfW * 2, bossBoxH)
        boxShape.center = Vector2(0, 0)
        boxShape.density = 1.0
        boxShape.friction = 0.0
        boxShape.categoryBits = 4  -- CATEGORY_ENEMY
        boxShape.maskBits = MASK_NO_PLAYER

        local topCircle = self.node:CreateComponent("CollisionCircle2D")
        topCircle.radius = bossRadius
        topCircle.center = Vector2(0, bossBoxH / 2)
        topCircle.density = 1.0
        topCircle.friction = 0.0
        topCircle.categoryBits = 4  -- CATEGORY_ENEMY
        topCircle.maskBits = MASK_NO_PLAYER

        local bottomCircle = self.node:CreateComponent("CollisionCircle2D")
        bottomCircle.radius = bossRadius
        bottomCircle.center = Vector2(0, -bossBoxH / 2)
        bottomCircle.density = 1.0
        bottomCircle.friction = 0.0
        bottomCircle.categoryBits = 4  -- CATEGORY_ENEMY
        bottomCircle.maskBits = MASK_NO_PLAYER
    else
        -- 普通怪：胶囊碰撞体（矩形中段 + 上下两个圆形）
        local radius = 0.4
        local boxH = 1.2 - radius * 2
        -- maskBits: 排除玩家(2)，与地面(1)+敌人(4)碰撞 = 0xFFFF & ~2 = 65533
        local MASK_NO_PLAYER = 65533

        local boxShape = self.node:CreateComponent("CollisionBox2D")
        boxShape.size = Vector2(0.8, boxH)
        boxShape.center = Vector2(0, 0)
        boxShape.density = 1.0
        boxShape.friction = 0.0
        boxShape.categoryBits = 4  -- CATEGORY_ENEMY
        boxShape.maskBits = MASK_NO_PLAYER

        local topCircle = self.node:CreateComponent("CollisionCircle2D")
        topCircle.radius = radius
        topCircle.center = Vector2(0, boxH / 2)
        topCircle.density = 1.0
        topCircle.friction = 0.0
        topCircle.categoryBits = 4  -- CATEGORY_ENEMY
        topCircle.maskBits = MASK_NO_PLAYER

        local bottomCircle = self.node:CreateComponent("CollisionCircle2D")
        bottomCircle.radius = radius
        bottomCircle.center = Vector2(0, -boxH / 2)
        bottomCircle.density = 1.0
        bottomCircle.friction = 0.0
        bottomCircle.categoryBits = 4  -- CATEGORY_ENEMY
        bottomCircle.maskBits = MASK_NO_PLAYER
    end

    log:Write(LOG_INFO, "[Enemy] Created at (" .. x .. ", " .. y .. ") HP=" .. self.hp)
end

-- 头顶血条UI
function Enemy:_createHpBar()
    local uiRoot = ui.root

    self.hpBarContainer = UIElement:new()
    uiRoot:AddChild(self.hpBarContainer)
    self.hpBarContainer:SetSize(60, 30)
    self.hpBarContainer:SetAlignment(HA_LEFT, VA_TOP)

    -- 属性图标（血条上方）
    local elemLabel = Text:new()
    self.hpBarContainer:AddChild(elemLabel)
    elemLabel:SetStyleAuto()
    elemLabel.text = self.elementData.icon
    elemLabel:SetFontSize(14)
    elemLabel:SetAlignment(HA_CENTER, VA_TOP)
    elemLabel:SetPosition(30, 0)

    -- 血条背景（灰色）
    local bgBar = BorderImage:new()
    self.hpBarContainer:AddChild(bgBar)
    bgBar:SetStyleAuto()
    bgBar:SetSize(60, 10)
    bgBar:SetPosition(0, 18)
    bgBar.color = Color(0.3, 0.3, 0.3, 0.8)

    -- 血条填充（统一红色）
    self.hpBarFill = BorderImage:new()
    self.hpBarContainer:AddChild(self.hpBarFill)
    self.hpBarFill:SetStyleAuto()
    self.hpBarFill:SetSize(60, 10)
    self.hpBarFill:SetPosition(0, 18)
    self.hpBarFill.color = Color(1.0, 0.1, 0.1, 1.0)
end

-- 追逐警告文本（屏幕中央偏上）
function Enemy:_createChaseWarning()
    local uiRoot = ui.root

    self.chaseWarning = Text:new()
    uiRoot:AddChild(self.chaseWarning)
    self.chaseWarning:SetStyleAuto()
    self.chaseWarning.text = "! 敌人正在追逐你 !"
    self.chaseWarning:SetFontSize(24)
    self.chaseWarning:SetAlignment(HA_CENTER, VA_CENTER)
    self.chaseWarning:SetPosition(0, -80)
    self.chaseWarning.color = Color(1.0, 0.1, 0.1, 1.0)
    self.chaseWarning.visible = false
end

-- 攻击警告文本
function Enemy:_createAttackWarning()
    local uiRoot = ui.root

    self.attackWarning = Text:new()
    uiRoot:AddChild(self.attackWarning)
    self.attackWarning:SetStyleAuto()
    self.attackWarning.text = "!! 敌人正在攻击 !!"
    self.attackWarning:SetFontSize(26)
    self.attackWarning:SetAlignment(HA_CENTER, VA_CENTER)
    self.attackWarning:SetPosition(0, 0)
    self.attackWarning.color = Color(1.0, 0.0, 0.0, 1.0)
    self.attackWarning.visible = false
end

function Enemy:update(dt)
    if not self.alive or self.node == nil then return end

    -- 玩家死亡时暂停移动
    if self.player.dead then
        self.body:SetLinearVelocity(Vector2(0, 0))
        return
    end

    local pos = self.node.position
    local velocity = self.body:GetLinearVelocity()

    -- 计算与玩家的距离
    local playerPos = self.player:getPosition()
    local distX = math.abs(playerPos.x - pos.x)

    -- 垂直距离（用于判断是否同层）
    local distY = math.abs(playerPos.y - pos.y)
    local selfHeight = self.isBoss and 2.4 or 1.2  -- 敌人自身高度

    -- 追逐触发：水平距离在范围内 且 玩家在同一层（垂直距离在自身高度内）
    if not self.chasing and distX <= CHASE_RANGE and distY <= selfHeight then
        self.chasing = true
        if self.chaseWarning then self.chaseWarning.visible = true end
    end

    if self.chasing then
        if distX <= self.attackRange and distY <= selfHeight then
            -- 攻击状态：停下攻击并造成伤害
            self.attacking = true
            if self.attackWarning then self.attackWarning.visible = true end
            if self.chaseWarning then self.chaseWarning.visible = false end
            self.body:SetLinearVelocity(Vector2(0, velocity.y))
            -- 按冷却间隔对玩家造成伤害
            self.attackTimer = self.attackTimer + dt
            if self.attackTimer >= ATTACK_COOLDOWN then
                local hit = self.player:takeDamage(ATTACK_DAMAGE, pos.x)
                if hit ~= false then
                    -- 成功造成伤害，重置计时器
                    self.attackTimer = 0
                else
                    -- 被无敌帧挡住，保持计时器满值，下帧重试
                    self.attackTimer = ATTACK_COOLDOWN
                end
            end
        else
            -- 追逐状态：检查前方是否有友军挡路
            self.attacking = false
            self.attackTimer = 0
            if self.attackWarning then self.attackWarning.visible = false end

            local dir = playerPos.x > pos.x and 1 or -1
            local blocked = self:_isBlockedByAlly(dir)

            if blocked then
                -- 前方有友军，停下待机
                self.blockedByAlly = true
                self.body:SetLinearVelocity(Vector2(0, velocity.y))
                if self.chaseWarning then self.chaseWarning.visible = false end
            else
                -- 无阻挡，正常追逐
                self.blockedByAlly = false
                if self.chaseWarning then self.chaseWarning.visible = true end
                self.body:SetLinearVelocity(Vector2(self.chaseSpeed * dir, velocity.y))
            end
        end
    else
        -- 待机模式：左右徘徊
        if pos.x > self.startX + self.patrolRange then
            self.patrolDir = -1
        elseif pos.x < self.startX - self.patrolRange then
            self.patrolDir = 1
        end
        self.body:SetLinearVelocity(Vector2(self.patrolSpeed * self.patrolDir, velocity.y))
    end

    -- 更新血条位置（跟随头顶）
    self:_updateHpBar()

    -- 更新伤害飘字动画
    self:_updateFloatingTexts(dt)
end

-- 检测前方是否有友军挡路（dir: 1=右, -1=左）
function Enemy:_isBlockedByAlly(dir)
    if not self.enemyList then return false end
    local myX = self.node.position.x
    for _, other in ipairs(self.enemyList) do
        if other ~= self and other.alive and other.node ~= nil then
            local otherX = other.node.position.x
            local dx = otherX - myX
            -- 检测同方向且距离在阈值内的友军
            if dir > 0 then
                -- 向右追：友军在我右边且距离近
                if dx > 0 and dx < FRONT_CHECK_DIST then
                    return true
                end
            else
                -- 向左追：友军在我左边且距离近
                if dx < 0 and math.abs(dx) < FRONT_CHECK_DIST then
                    return true
                end
            end
        end
    end
    return false
end

-- 将世界坐标转换为屏幕坐标，更新血条位置
function Enemy:_updateHpBar()
    if self.hpBarContainer == nil or self.camera == nil then return end

    local worldPos = self.node.position
    -- 头顶偏移（碰撞体高1.2，顶部+0.2留空）
    local headPos = Vector3(worldPos.x, worldPos.y + 1.2, worldPos.z)

    local screenPos = self.camera:WorldToScreenPoint(headPos)
    local screenX = screenPos.x * graphics.width - 30  -- 居中偏移(血条宽60/2)
    local screenY = screenPos.y * graphics.height

    self.hpBarContainer:SetPosition(screenX, screenY)

    -- 更新血条长度
    local ratio = self.hp / self.maxHp
    self.hpBarFill:SetSize(math.floor(60 * ratio), 10)
end

-- 受伤
function Enemy:takeDamage(amount, sourceX)
    if not self.alive then return end
    local dmg = amount or 1
    self.hp = math.max(0, self.hp - dmg)
    -- 小击退：远离攻击来源方向
    if sourceX and self.body and self.node then
        local myX = self.node.position.x
        local dir = myX > sourceX and 1 or -1
        self.body:ApplyLinearImpulseToCenter(Vector2(dir * 1.5, 1.0), true)
    end
    -- 伤害飘字
    self:_showDamageFloat(dmg)
    if self.hp <= 0 then
        self:die()
    end
end

-- 伤害飘字效果
function Enemy:_showDamageFloat(damage)
    local uiRoot = ui.root

    local floatText = Text:new()
    uiRoot:AddChild(floatText)
    floatText:SetStyleAuto()
    floatText.text = "-" .. tostring(damage)
    floatText:SetFontSize(22)
    floatText.color = Color(1.0, 1.0, 0.0, 1.0)
    floatText.priority = 100

    -- 在敌人头顶位置显示
    if self.node and self.camera then
        local headPos = Vector3(self.node.position.x, self.node.position.y + 1.0, self.node.position.z)
        local screenPos = self.camera:WorldToScreenPoint(headPos)
        local sx = screenPos.x * graphics.width - 10
        local sy = screenPos.y * graphics.height - 20
        floatText:SetPosition(sx, sy)
    end

    -- 存入飘字列表用于动画
    if not self.floatingTexts then
        self.floatingTexts = {}
    end
    table.insert(self.floatingTexts, { text = floatText, timer = 0, duration = 0.8 })
end

-- 更新飘字动画（向上漂浮 + 透明渐隐）
function Enemy:_updateFloatingTexts(dt)
    if not self.floatingTexts then return end

    local i = 1
    while i <= #self.floatingTexts do
        local ft = self.floatingTexts[i]
        ft.timer = ft.timer + dt
        if ft.timer >= ft.duration then
            -- 时间到，移除飘字
            if ft.text then
                ft.text:Remove()
            end
            table.remove(self.floatingTexts, i)
        else
            -- 向上移动并渐隐
            local progress = ft.timer / ft.duration
            local currentPos = ft.text:GetPosition()
            -- 每帧上移 40像素/秒
            ft.text:SetPosition(currentPos.x, currentPos.y - 40 * dt)
            -- 透明度从1渐变到0
            local alpha = 1.0 - progress
            ft.text.color = Color(1.0, 1.0, 0.0, alpha)
            i = i + 1
        end
    end
end

function Enemy:die()
    if not self.alive then return end
    self.alive = false
    if self.node ~= nil then
        self.node:Remove()
        self.node = nil
    end
    -- 只隐藏血条，不移除（避免重建时样式丢失）
    if self.hpBarContainer ~= nil then
        self.hpBarContainer.visible = false
    end
    self:_clearFloatingTexts()
    log:Write(LOG_INFO, "[Enemy] Died")
end

-- 清除所有飘字
function Enemy:_clearFloatingTexts()
    if self.floatingTexts then
        for _, ft in ipairs(self.floatingTexts) do
            if ft.text then ft.text:Remove() end
        end
        self.floatingTexts = {}
    end
end



function Enemy:reset()
    self.hp = self.maxHp
    self.alive = true
    self.patrolDir = 1
    self.chasing = false
    self.attacking = false
    self.attackTimer = 0
    if self.chaseWarning then self.chaseWarning.visible = false end
    if self.attackWarning then self.attackWarning.visible = false end
    self:_clearFloatingTexts()

    -- 如果节点已被移除（敌人死亡时），重新创建
    if self.node == nil then
        self:_createNode(self.scene, self.startX, self.spawnY)
    else
        self.node.position = Vector3(self.startX, self.spawnY, 0)
        self.body:SetLinearVelocity(Vector2(0, 0))
    end

    -- 重置血条填充
    if self.hpBarFill ~= nil then
        self.hpBarFill:SetSize(60, 10)
    end
end

function Enemy:showHpBar()
    if self.hpBarContainer ~= nil then
        self.hpBarContainer.visible = true
    end
end

function Enemy:hideHpBar()
    if self.hpBarContainer ~= nil then
        self.hpBarContainer.visible = false
    end
    if self.chaseWarning ~= nil then
        self.chaseWarning.visible = false
    end
    if self.attackWarning ~= nil then
        self.attackWarning.visible = false
    end
end

function Enemy:isAlive()
    return self.alive
end

function Enemy:getElement()
    return self.element
end

return Enemy
