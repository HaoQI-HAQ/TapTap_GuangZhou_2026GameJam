-- scene_manager.lua
-- 场景创建、相机设置、关卡背景和地形生成
---@diagnostic disable: undefined-global, param-type-mismatch, assign-type-mismatch

local ScreenUtils = require("scripts/screen_utils")

local M = {}

local G  -- 由 game_mode 注入

function M.init(shared)
    G = shared
end

-- ============================================================================
-- 场景/相机创建
-- ============================================================================
function M.CreateScene()
    G.scene_ = Scene()
    G.scene_:CreateComponent("Octree")

    G.physicsWorld_ = G.scene_:CreateComponent("PhysicsWorld2D")
    G.physicsWorld_.gravity = Vector2(0, -9.81)

    local lightNode = G.scene_:CreateChild("DirectionalLight")
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1, 1, 1, 1)
    lightNode.direction = Vector3(0, 0, 1)
end

function M.SetupCamera()
    G.cameraNode = G.scene_:CreateChild("Camera")
    G.cameraNode.position = Vector3(0, 0, -10)

    G.camera_ = G.cameraNode:CreateComponent("Camera")
    G.camera_.orthographic = true
    G.camera_.orthoSize = 5.2

    local viewport = Viewport:new(G.scene_, G.camera_)
    renderer:SetViewport(0, viewport)
    renderer.defaultZone.fogColor = Color(0.05, 0.05, 0.08, 1.0)
end

-- ============================================================================
-- 关卡背景和地形
-- ============================================================================

-- 关卡背景图配置
local BG_IMAGES = {
    "image/backgrounds/dungeon_rooms/room1_entrance.png",
    "image/backgrounds/dungeon_rooms/room2_prison.png",
    "image/backgrounds/dungeon_rooms/room3_sewer.png",
    "image/backgrounds/dungeon_rooms/room4_altar.png",
    "image/backgrounds/dungeon_rooms/room5_boss_throne.png",
}

-- 关卡地形贴图配置
local LEVEL_TILES = {
    [1] = { ground = "image/tiles/floor/stone_floor.png",  platform = "image/tiles/special/platform_edge.png" },
    [2] = { ground = "image/tiles/floor/stone_floor.png",  platform = "image/tiles/special/platform_edge.png" },
    [3] = { ground = "image/tiles/floor/cracked_floor.png", platform = "image/tiles/special/platform_edge.png" },
    [4] = { ground = "image/tiles/floor/stone_floor.png",  platform = "image/tiles/special/platform_edge.png" },
    [5] = { ground = "image/tiles/floor/gold_floor.png",   platform = "image/tiles/floor/gold_floor.png" },
}

--- 创建关卡背景图
function M.CreateBackground(groundWidth)
    local curLevel = G.levelManager:getCurrentLevel()
    local bgPath = BG_IMAGES[curLevel] or BG_IMAGES[1]
    local bgNode = G.scene_:CreateChild("Background")

    local bgTex = cache:GetResource("Texture2D", bgPath)
    if bgTex then
        local planeW = groundWidth + 10
        local texW = bgTex:GetWidth()
        local texH = bgTex:GetHeight()
        local texAspect = texW / texH
        local planeH = planeW / texAspect

        bgNode.position = Vector3(0, 0, 5)

        local spriteNode = bgNode:CreateChild("BgSprite")
        spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        spriteNode.scale = Vector3(planeW, 1.0, planeH)

        local model = spriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))

        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        mat:SetTexture(0, bgTex)
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        mat:SetShaderParameter("UOffset", Variant(Vector4(1, 0, 0, 0)))
        mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
        model:SetMaterial(mat)
    end
end

--- 创建地面和平台
function M.CreateTerrain(groundWidth, platforms)
    local curLevel = G.levelManager:getCurrentLevel()
    local tiles = LEVEL_TILES[curLevel] or LEVEL_TILES[1]

    Ground:new(G.scene_, 0, -3.0, groundWidth, 1.0, tiles.ground)
    for _, p in ipairs(platforms) do
        Ground:new(G.scene_, p.x, p.y, p.w, p.h, tiles.platform)
    end
end

return M
