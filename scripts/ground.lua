---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- Ground 类
Ground = {}
Ground.__index = Ground

--- 创建地面/平台
--- @param scene userdata 场景
--- @param x number 中心X
--- @param y number 中心Y
--- @param width number 宽度(米)
--- @param height number 高度(米)
--- @param texturePath string|nil 贴图路径(nil则使用纯色)
function Ground:new(scene, x, y, width, height, texturePath)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, Ground)
    self:_createNode(scene, x, y, width, height, texturePath)
    return self
end

function Ground:_createNode(scene, x, y, width, height, texturePath)
    self.node = scene:CreateChild("Ground")
    self.node.position = Vector3(x, y, 0.5)  -- Z=0.5，比技能效果(Z=1.5)更靠前，遮挡技能

    -- 可视化：使用 3D Plane（与技能效果在同一渲染管线，Z深度才能正确遮挡）
    local spriteNode = self.node:CreateChild("GroundSprite")
    spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    spriteNode.scale = Vector3(width, 1.0, height)

    local model = spriteNode:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

    local mat = Material:new()

    if texturePath then
        -- 使用贴图 + UV平铺
        local tex = cache:GetResource("Texture2D", texturePath)
        if tex then
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
            mat:SetTexture(0, tex)
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
            -- UV平铺：每0.25米重复一次贴图
            local tilesX = width * 4
            local tilesY = height * 4
            mat:SetShaderParameter("UOffset", Variant(Vector4(tilesX, 0, 0, 0)))
            mat:SetShaderParameter("VOffset", Variant(Vector4(0, tilesY, 0, 0)))
        else
            -- 贴图加载失败，回退纯色
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
            mat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 0.3, 1.0)))
        end
    else
        -- 无贴图，纯色
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 0.3, 1.0)))
    end

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
