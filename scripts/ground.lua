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
    self.node.position = Vector3(x, y, 0.5)  -- Z=0.5，比技能效果(Z=1.5)更靠前，遮挡技能

    -- 可视化：使用 3D Plane（与技能效果在同一渲染管线，Z深度才能正确遮挡）
    local spriteNode = self.node:CreateChild("GroundSprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(width, 1.0, height)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 0.3, 1.0)))
    model:SetMaterial(mat)

    -- 物理
    local body = self.node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(width, height)
    shape.friction = 0.5
    shape.categoryBits = 1  -- CATEGORY_GROUND

    log:Write(LOG_INFO, "[Ground] Created at (" .. x .. ", " .. y .. ") size: " .. width .. "x" .. height)
end

return Ground
