-- Ground 类
Ground = {}
Ground.__index = Ground

function Ground:new(scene, x, y, width, height)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, Ground)
    self:_createNode(scene, x, y, width, height)
    return self
end

function Ground:_createNode(scene, x, y, width, height)
    self.node = scene:CreateChild("Ground")
    self.node.position = Vector3(x, y, 0)

    -- 可视化
    local sprite = self.node:CreateComponent("StaticSprite2D")
    sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
    sprite.color = Color(0.4, 0.7, 0.3, 1.0)
    sprite.drawRect = Rect(-width / 2, -height / 2, width / 2, height / 2)

    -- 物理
    local body = self.node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(width, height)
    shape.friction = 0.5

    log:Write(LOG_INFO, "[Ground] Created at (" .. x .. ", " .. y .. ") size: " .. width .. "x" .. height)
end

return Ground
