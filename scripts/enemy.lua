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

-- 属性定义：颜色 + 克制关系
Enemy.ELEMENTS = {
    fire  = { name = "火", icon = "🔥", color = Color(1.0, 0.3, 0.1, 1.0),  beats = { "wind", "ice" }, weak = { "water" } },
    water = { name = "水", icon = "💧", color = Color(0.1, 0.5, 1.0, 1.0),  beats = { "fire" },        weak = { "thunder" } },
    thunder = { name = "雷", icon = "⚡", color = Color(0.9, 0.8, 0.1, 1.0), beats = { "water" },       weak = { "wind" } },
    wind  = { name = "风", icon = "🌪️", color = Color(0.2, 0.9, 0.4, 1.0),  beats = { "thunder" },     weak = { "fire" } },
    ice   = { name = "冰", icon = "❄️", color = Color(0.5, 0.9, 1.0, 1.0),  beats = { "wind", "thunder" }, weak = { "fire" } },
}

function Enemy:new(scene, camera, player, x, y, element)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, Enemy)
    self.hp = ENEMY_HP
    self.maxHp = ENEMY_HP
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

    -- 可视化 - 属性颜色方块（与玩家同尺寸）
    local sprite = self.node:CreateComponent("StaticSprite2D")
    sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
    sprite.color = self.elementData.color
    sprite.drawRect = Rect(-0.4, -0.6, 0.4, 0.6)
    self.sprite = sprite

    -- 物理
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_DYNAMIC
    self.body.fixedRotation = true
    self.body.linearDamping = 0.5

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(0.8, 1.2)
    shape.density = 1.0
    shape.friction = 0.0  -- 与玩家零摩擦

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

    -- 血条填充（属性颜色）
    self.hpBarFill = BorderImage:new()
    self.hpBarContainer:AddChild(self.hpBarFill)
    self.hpBarFill:SetStyleAuto()
    self.hpBarFill:SetSize(60, 10)
    self.hpBarFill:SetPosition(0, 18)
    self.hpBarFill.color = self.elementData.color
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

    -- 一旦触发追逐，永不回到待机
    if not self.chasing and distX <= CHASE_RANGE then
        self.chasing = true
        if self.chaseWarning then self.chaseWarning.visible = true end
    end

    if self.chasing then
        if distX <= ATTACK_RANGE then
            -- 攻击状态：停下攻击并造成伤害
            self.attacking = true
            if self.attackWarning then self.attackWarning.visible = true end
            if self.chaseWarning then self.chaseWarning.visible = false end
            self.body:SetLinearVelocity(Vector2(0, velocity.y))
            -- 按冷却间隔对玩家造成伤害
            self.attackTimer = self.attackTimer + dt
            if self.attackTimer >= ATTACK_COOLDOWN then
                local hit = self.player:takeDamage(ATTACK_DAMAGE)
                if hit ~= false then
                    -- 成功造成伤害，重置计时器
                    self.attackTimer = 0
                else
                    -- 被无敌帧挡住，保持计时器满值，下帧重试
                    self.attackTimer = ATTACK_COOLDOWN
                end
            end
        else
            -- 追逐状态：朝玩家移动
            self.attacking = false
            self.attackTimer = 0
            if self.attackWarning then self.attackWarning.visible = false end
            if self.chaseWarning then self.chaseWarning.visible = true end
            local dir = playerPos.x > pos.x and 1 or -1
            self.body:SetLinearVelocity(Vector2(CHASE_SPEED * dir, velocity.y))
        end
    else
        -- 待机模式：左右徘徊
        if pos.x > self.startX + PATROL_RANGE then
            self.patrolDir = -1
        elseif pos.x < self.startX - PATROL_RANGE then
            self.patrolDir = 1
        end
        self.body:SetLinearVelocity(Vector2(PATROL_SPEED * self.patrolDir, velocity.y))
    end

    -- 更新血条位置（跟随头顶）
    self:_updateHpBar()

    -- 更新伤害飘字动画
    self:_updateFloatingTexts(dt)
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
function Enemy:takeDamage(amount)
    if not self.alive then return end
    local dmg = amount or 1
    self.hp = math.max(0, self.hp - dmg)
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
    floatText.priority = 999

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
