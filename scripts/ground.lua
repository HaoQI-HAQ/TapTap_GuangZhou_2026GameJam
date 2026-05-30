-- ============================================================================
-- Ground 模块：静态地面/平台 (使用 StaticModel 渲染)
-- ============================================================================

local Ground = {}
Ground.__index = Ground

function Ground.new(_, scene, x, y, width, height, color)
    local self = setmetatable({}, Ground)
    self.width = width
    self.height = height
    self:_createNode(scene, x, y, width, height, color)
    return self
end

function Ground:_createNode(scene, x, y, width, height, color)
    self.node = scene:CreateChild("Ground")
    self.node.position = Vector3(x, y, 0)

    -- 视觉(3D Box 作为2D平台)
    local model = self.node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    local c = color or { 0.25, 0.55, 0.2, 1.0 }
    mat:SetShaderParameter("MatDiffColor", Variant(Color(c[1], c[2], c[3], c[4] or 1.0)))
    model:SetMaterial(mat)
    self.node:SetScale(Vector3(width, height, 0.5))

    -- 物理
    local body = self.node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC

    local shape = self.node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(width, height)
    shape.friction = 0.5
end

return Ground
