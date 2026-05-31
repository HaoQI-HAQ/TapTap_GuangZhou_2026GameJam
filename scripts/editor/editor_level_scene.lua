-- editor_level_scene.lua
-- 关卡编辑器 - 场景层（地面、对象生成、材质、坐标转换）
---@diagnostic disable: undefined-global, redefined-local

local EditorLevelData = require("editor/editor_level_data")
local ELEM_TYPES = EditorLevelData.ELEM_TYPES

local M = {}

function M.mixin(cls)

    -- ========================================================================
    -- 地面
    -- ========================================================================

    function cls:_createGround()
        local oldGround = self.scene:GetChild("EditorGround")
        if oldGround then oldGround:Remove() end

        local level = self.levels[self.currentLevel]
        if not level then return end

        local groundNode = self.scene:CreateChild("EditorGround")
        local gY = level.groundY or -2.5
        groundNode.position = Vector3(level.groundWidth / 2, gY, 0.5)

        local spriteNode = groundNode:CreateChild("GroundSprite")
        spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        spriteNode.scale = Vector3(level.groundWidth, 1.0, 0.5)

        local model = spriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.5, 0.25, 1.0)))
        model:SetMaterial(mat)

        if self.propsPanel then
            local lbl = self.propsPanel:FindById("lbl_ground_w")
            if lbl then lbl:SetText(tostring(math.floor(level.groundWidth))) end
        end
    end

    -- ========================================================================
    -- 场景重建
    -- ========================================================================

    function cls:_rebuildScene()
        if self.editorNode then
            self.editorNode:Remove()
        end
        self.editorNode = self.scene:CreateChild("EditorObjects")
        self.objects = {}

        local level = self.levels[self.currentLevel]
        if not level then return end

        for _, plat in ipairs(level.platforms or {}) do
            self:_spawnObject("platform", plat.x, plat.y, { w = plat.w or 5.0, h = plat.h or 0.3, image = plat.image })
        end

        if type(level.enemies) == "table" then
            for _, enemy in ipairs(level.enemies) do
                local etype = "enemy_" .. (enemy.element or "fire")
                if enemy.boss then etype = "enemy_boss" end
                self:_spawnObject(etype, enemy.x, enemy.y, { image = enemy.image })
            end
        end

        if level.portalX then
            self:_spawnObject("portal", level.portalX, level.portalY or -2.0, { image = level.portalImage })
        end

        self:_spawnObject("spawn", level.spawnX or 0, level.spawnY or -1.5, { image = level.spawnImage })
    end

    -- ========================================================================
    -- 对象生成
    -- ========================================================================

    function cls:_spawnObject(typeId, x, y, extraData)
        local elemDef = nil
        for _, e in ipairs(ELEM_TYPES) do
            if e.id == typeId then elemDef = e; break end
        end
        if not elemDef then return end

        local node = self.editorNode:CreateChild(typeId)
        node.position = Vector3(x, y, 0.0)

        local w, h = 1.0, 1.0
        if typeId == "platform" then
            w = (extraData and extraData.w) or 5.0
            h = (extraData and extraData.h) or 0.3
        elseif typeId == "portal" then
            w = 1.5; h = 3.0
        elseif typeId == "spawn" then
            w = 0.8; h = 1.8
        end

        local spriteNode = node:CreateChild("Sprite")
        spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        spriteNode.scale = Vector3(w, 1.0, h)

        local model = spriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(elemDef.color))
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(
            elemDef.color.r * 0.3, elemDef.color.g * 0.3, elemDef.color.b * 0.3, 1.0
        )))
        model:SetMaterial(mat)

        local obj = {
            node = node,
            typeId = typeId,
            data = extraData or {},
            w = w,
            h = h,
        }
        table.insert(self.objects, obj)

        if extraData and extraData.image and extraData.image ~= "" then
            self:_applyImageToObject(obj)
        end

        return obj
    end

    -- ========================================================================
    -- 材质应用
    -- ========================================================================

    function cls:_applyImageToObject(obj)
        if not obj or not obj.node then return end

        local imagePath = obj.data and obj.data.image
        if not imagePath or imagePath == "" then
            self:_applyColorToObject(obj)
            return
        end

        local spriteNode = obj.node:GetChild("Sprite")
        if not spriteNode then return end

        local model = spriteNode:GetComponent("StaticModel")
        if not model then return end

        local texture = cache:GetResource("Texture2D", imagePath)
        if not texture then
            log:Write(LOG_WARNING, "[EditorLevel] Cannot load texture: " .. imagePath)
            self:_applyColorToObject(obj)
            return
        end

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        mat:SetTexture(0, texture)
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
        model:SetMaterial(mat)
    end

    function cls:_applyColorToObject(obj)
        if not obj or not obj.node then return end

        local spriteNode = obj.node:GetChild("Sprite")
        if not spriteNode then return end

        local model = spriteNode:GetComponent("StaticModel")
        if not model then return end

        local color = Color(0.5, 0.5, 0.5, 1.0)
        for _, e in ipairs(ELEM_TYPES) do
            if e.id == obj.typeId then color = e.color; break end
        end

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(color))
        mat:SetShaderParameter("MatEmissiveColor", Variant(Color(
            color.r * 0.3, color.g * 0.3, color.b * 0.3, 1.0
        )))
        model:SetMaterial(mat)
    end

    -- ========================================================================
    -- 空间查询
    -- ========================================================================

    function cls:_findObjectAt(worldPos)
        for _, obj in ipairs(self.objects) do
            local pos = obj.node.position
            local hw = (obj.w or 1.0) * 0.5
            local hh = (obj.h or 1.0) * 0.5
            if worldPos.x >= pos.x - hw and worldPos.x <= pos.x + hw
                and worldPos.y >= pos.y - hh and worldPos.y <= pos.y + hh then
                return obj
            end
        end
        return nil
    end

    -- ========================================================================
    -- 坐标转换
    -- ========================================================================

    function cls:_screenToWorld(mousePos)
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local aspect = screenW / screenH

        local ndcX = (mousePos.x / screenW) * 2.0 - 1.0
        local ndcY = 1.0 - (mousePos.y / screenH) * 2.0

        local halfH = self.zoom * 0.5
        local halfW = halfH * aspect
        local worldX = self.camX + ndcX * halfW
        local worldY = self.camY + ndcY * halfH

        return Vector3(worldX, worldY, 0)
    end

end -- mixin

return M
