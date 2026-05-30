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
local BOSS_SKILL_CD = 4.0        -- Boss大招冷却时间（秒）
local BOSS_SKILL_RANGE = 3.0     -- Boss大招伤害范围（嘴前方3米）
local BOSS_SKILL_DAMAGE = 1      -- Boss大招伤害
local BOSS_SKILL_FRAMES = 3      -- Boss大招动画帧数（身体）
local BOSS_SKILL_FRAME_DUR = 0.267 -- 每帧持续时间（秒）0.8s/3帧
local BOSS_SKILL_FRAME_PX = 682  -- 每帧像素宽度
local BOSS_SKILL_TEX_W = 2048    -- 精灵图总宽度
-- Boss大招特效参数（嘴巴处喷射特效）
local BOSS_EFF_FRAMES = 4        -- 特效帧数
local BOSS_EFF_FRAME_PX = 512    -- 特效每帧像素宽度
local BOSS_EFF_TEX_W = 2048      -- 特效精灵图总宽度
local BOSS_EFF_TEX_H = 269       -- 特效精灵图高度
-- 小怪行走动画参数
local ENEMY_WALK_FRAMES = 4      -- 行走帧数
local ENEMY_WALK_FPS = 8          -- 行走动画帧率
-- 小怪贴图路径（按属性）facesLeft=贴图默认朝左
local ENEMY_WALK_TEXTURES = {
    fire    = { path = "image/Enemy/fire/enemy_fire_walk.png",      framePx = 250, texW = 1000, texH = 250, frames = 4, facesLeft = false },
    ice     = { path = "image/Enemy/ice/enemy_ice_walk.png",        framePx = 200, texW = 1000, texH = 400, frames = 5, facesLeft = false },
    thunder = { path = "image/Enemy/thunder/enemy_thunder_walk.png", framePx = 200, texW = 800,  texH = 90,  frames = 4, facesLeft = false },
    grass   = { path = "image/Enemy/grass/enemy_grass_walk.png",    framePx = 200, texW = 800,  texH = 250, frames = 4, facesLeft = true },
    earth   = { path = "image/Enemy/earth/enemy_earth_walk.png",  framePx = 200, texW = 800,  texH = 270, frames = 4, facesLeft = false },
}
-- 小怪攻击动画贴图（按属性）
local ENEMY_ATK_TEXTURES = {
    ice = { path = "image/Enemy/ice/enemy_ice_atk.png", framePx = 200, texW = 800, texH = 339, frames = 4, facesLeft = false },
}
local ENEMY_ATK_FPS = 8  -- 攻击动画帧率

-- 属性定义：颜色 + 克制关系
Enemy.ELEMENTS = {
    fire  = { name = "火", icon = "🔥", color = Color(1.0, 0.3, 0.1, 1.0),  beats = { "wind", "ice" }, weak = { "water" } },
    water = { name = "水", icon = "💧", color = Color(0.1, 0.5, 1.0, 1.0),  beats = { "fire" },        weak = { "thunder" } },
    thunder = { name = "雷", icon = "⚡", color = Color(0.9, 0.8, 0.1, 1.0), beats = { "water" },       weak = { "wind" } },
    wind  = { name = "风", icon = "🌪️", color = Color(0.2, 0.9, 0.4, 1.0),  beats = { "thunder" },     weak = { "fire" } },
    ice   = { name = "冰", icon = "❄️", color = Color(0.5, 0.9, 1.0, 1.0),  beats = { "wind", "thunder" }, weak = { "fire" } },
    grass = { name = "草", icon = "🌿", color = Color(0.2, 0.8, 0.3, 1.0),  beats = { "water" },       weak = { "fire" } },
    earth = { name = "土", icon = "🪨", color = Color(0.55, 0.27, 0.07, 1.0), beats = { "thunder" },  weak = { "ice" } },
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


    -- Boss大招状态
    self.skillTimer = 0          -- 大招CD计时器
    self.skillActive = false     -- 是否正在释放大招
    self.skillFrameTimer = 0     -- 当前帧计时
    self.skillCurrentFrame = 0   -- 当前帧索引(0-2)
    self.skillDamageDealt = false -- 本次大招是否已造成伤害
    self.skillMaterial = nil     -- 大招动画材质
    self.skillFirstApproachTriggered = false  -- 第一次靠近是否已触发
    self:_createNode(scene, x, y)
    self:_createHpBar()


    if self.isBoss then
        self:_initBossSkill()
    end
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
        -- Boss使用行走动画精灵图（2048x293, 6帧）
        self.spriteNode = self.node:CreateChild("BossSprite")
        self.spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        -- 按帧比例计算显示尺寸：帧宽≈341, 帧高=293, 显示高度=2.4
        local bossFrameW = 2048.0 / 6.0
        local bossFrameH = 293.0
        local dispH = halfH * 2  -- 2.4
        local dispW = dispH * (bossFrameW / bossFrameH)  -- ≈2.79
        self.spriteNode.scale = Vector3(dispW, 1.0, dispH)
        local bossTexture = cache:GetResource("Texture2D", "image/Enemy/boss_01_walk.png")
        if bossTexture then
            local mat = Material:new()
            mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
            mat:SetTexture(0, bossTexture)
            mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
            -- 初始UV：显示第1帧（1/6宽度）
            local frameU = 1.0 / 6.0
            mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, 0)))
            mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
            local model = self.spriteNode:CreateComponent("StaticModel")
            model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
            model:SetMaterial(mat)
            self.bossMaterial = mat
            self.bossWalkFrames = 6
            self.bossWalkFPS = 8
            self.bossWalkFrameTimer = 0
            self.bossWalkCurrentFrame = 0
            self.bossDispW = dispW
            self.bossDispH = dispH
        else
            log:Write(LOG_ERROR, "[Enemy] Failed to load boss walk texture")
        end
    else
        -- 检查是否有该属性的动画贴图
        local walkData = ENEMY_WALK_TEXTURES[self.element]
        if walkData then
            -- 使用 Plane + 精灵图动画（和Boss/Player相同方式）
            -- 按每帧像素比例计算显示尺寸，以碰撞高度(halfH*2)为基准
            local frameAspect = walkData.framePx / walkData.texH  -- 宽高比
            local dispH = halfH * 2       -- 显示高度 = 碰撞体高度
            local dispW = dispH * frameAspect  -- 显示宽度按比例
            self.spriteNode = self.node:CreateChild("EnemySprite")
            self.spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
            self.spriteNode.scale = Vector3(dispW, 1.0, dispH)
            local tex = cache:GetResource("Texture2D", walkData.path)
            if tex then
                local mat = Material:new()
                mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
                mat:SetTexture(0, tex)
                mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
                local frameU = walkData.framePx / walkData.texW
                mat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, 0)))
                mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
                local model = self.spriteNode:CreateComponent("StaticModel")
                model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
                model:SetMaterial(mat)
                self.walkMaterial = mat
                self.walkData = walkData
                self.walkFrameTimer = 0
                self.walkCurrentFrame = 0
            end
            -- 预加载攻击动画材质（如果有）
            local atkData = ENEMY_ATK_TEXTURES[self.element]
            if atkData then
                local atkTex = cache:GetResource("Texture2D", atkData.path)
                if atkTex then
                    local atkMat = Material:new()
                    atkMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
                    atkMat:SetTexture(0, atkTex)
                    atkMat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
                    local frameU = atkData.framePx / atkData.texW
                    atkMat:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, 0)))
                    atkMat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
                    self.atkMaterial = atkMat
                    self.atkData = atkData
                    self.atkFrameTimer = 0
                    self.atkCurrentFrame = 0
                end
            end
        else
            -- 无贴图属性：使用纯色方块
            local sprite = self.node:CreateComponent("StaticSprite2D")
            sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
            sprite.color = self.elementData.color
            sprite.drawRect = Rect(-halfW, -halfH, halfW, halfH)
            self.sprite = sprite
        end
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

    -- 血条背景（深灰色）
    local bgBar = BorderImage:new()
    self.hpBarContainer:AddChild(bgBar)
    bgBar:SetSize(60, 10)
    bgBar:SetPosition(0, 18)
    bgBar.color = Color(0.2, 0.2, 0.2, 0.9)

    -- 血条填充（红色）
    self.hpBarFill = BorderImage:new()
    self.hpBarContainer:AddChild(self.hpBarFill)
    self.hpBarFill:SetSize(60, 10)
    self.hpBarFill:SetPosition(0, 18)
    self.hpBarFill.color = Color(1.0, 0.1, 0.1, 1.0)
end





-- 初始化Boss大招（创建独立技能特效节点）
function Enemy:_initBossSkill()
    -- 加载大招精灵图（2048x585, 3帧横排）
    local skillTex = cache:GetResource("Texture2D", "image/Enemy/boss_01_skill_01.png")
    if not skillTex then
        log:Write(LOG_ERROR, "[Enemy] Failed to load boss skill texture")
        return
    end
    self.skillTexture = skillTex

    -- 创建大招材质（按682px每帧精确切分）
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(0, skillTex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    local frameW = BOSS_SKILL_FRAME_PX / BOSS_SKILL_TEX_W  -- 682/2048 = 0.3330078125
    mat:SetShaderParameter("UOffset", Variant(Vector4(frameW, 0, 0, 0)))
    mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
    self.skillMaterial = mat

    -- 创建技能特效子节点（独立于本体精灵，叠加显示）
    self.skillNode = self.node:CreateChild("SkillEffect")
    self.skillNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    -- 技能特效尺寸：与Boss等高，宽度按精灵图比例(682:585≈1.17:1)
    local skillH = 2.4  -- 与Boss同高
    local skillW = skillH * (682.0 / 585.0)
    self.skillNode.scale = Vector3(skillW, 1.0, skillH)
    self.skillNode.position = Vector3(0, 0, -0.1)  -- 与本体同高，无位移

    local skillModel = self.skillNode:CreateComponent("StaticModel")
    skillModel:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    skillModel:SetMaterial(mat)

    -- 初始隐藏
    self.skillNode.enabled = false

    -- 大招范围线框已移除（不再显示）

    -- 大招喷射特效节点（嘴巴处，覆盖攻击范围）
    local effTex = cache:GetResource("Texture2D", "image/Enemy/boss_01_skill_01_eff.png")
    if effTex then
        local effMat = Material:new()
        effMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        effMat:SetTexture(0, effTex)
        effMat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        local effFrameU = BOSS_EFF_FRAME_PX / BOSS_EFF_TEX_W  -- 512/2048 = 0.25
        effMat:SetShaderParameter("UOffset", Variant(Vector4(effFrameU, 0, 0, 0)))
        effMat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
        self.effMaterial = effMat

        self.effNode = self.node:CreateChild("SkillBlastEff")
        self.effNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
        -- 特效宽度=攻击范围，高度按贴图比例
        local effW = BOSS_SKILL_RANGE  -- 3.0m
        local effH = effW * (BOSS_EFF_TEX_H / BOSS_EFF_FRAME_PX)  -- 3.0 * 269/512 ≈ 1.576m
        self.effNode.scale = Vector3(effW, 1.0, effH)
        self.effNode.position = Vector3(0, 0, -0.12)  -- 略前方

        local effModel = self.effNode:CreateComponent("StaticModel")
        effModel:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        effModel:SetMaterial(effMat)
        self.effNode.enabled = false
    end

    log:Write(LOG_INFO, "[Enemy] Boss skill initialized (overlay node)")
end

-- 设置大招材质的UV帧（frameIdx: 0,1,2）按682px精确切
function Enemy:_setSkillFrame(frameIdx)
    if not self.skillMaterial then return end
    local frameW = BOSS_SKILL_FRAME_PX / BOSS_SKILL_TEX_W  -- 682/2048
    local offsetU = frameIdx * frameW
    -- UOffset格式: Vector4(scaleU, 0, 0, offsetU) — 偏移在第4分量(w)
    self.skillMaterial:SetShaderParameter("UOffset", Variant(Vector4(frameW, 0, 0, offsetU)))
end

-- 设置特效材质的UV帧（frameIdx: 0,1,2,3）按512px精确切
function Enemy:_setEffFrame(frameIdx)
    if not self.effMaterial then return end
    local frameU = BOSS_EFF_FRAME_PX / BOSS_EFF_TEX_W  -- 512/2048 = 0.25
    local offsetU = frameIdx * frameU
    self.effMaterial:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, offsetU)))
end

-- 开始释放大招（隐藏本体，显示大招动画）
function Enemy:_startSkill()
    self.skillActive = true
    self.skillTimer = 0  -- 重置CD计时器
    self.skillFrameTimer = 0
    self.skillCurrentFrame = 0
    self.skillDamageDealt = false
    -- 隐藏本体精灵
    if self.spriteNode then
        self.spriteNode.enabled = false
    end
    -- 计算面朝方向
    local playerPos = self.player:getPosition()
    local bossPos = self.node.position
    local faceDir = playerPos.x > bossPos.x and 1 or -1
    self.skillFaceDir = faceDir  -- 保存方向供特效更新用
    -- 显示技能特效节点（根据方向翻转，贴图默认朝左需取反）
    if self.skillNode then
        local skillH = 2.4
        local skillW = skillH * (682.0 / 585.0)
        self.skillNode.scale = Vector3(-skillW * faceDir, 1.0, skillH)
        self.skillNode.enabled = true
    end
    -- 显示喷射特效（从嘴巴向前延伸，覆盖攻击范围）
    if self.effNode then
        local effW = BOSS_SKILL_RANGE
        local effH = effW * (BOSS_EFF_TEX_H / BOSS_EFF_FRAME_PX)
        -- 特效中心位于嘴巴+半个范围处（贴图默认朝左，需取反faceDir）
        local mouthOffset = 1.2  -- 嘴巴距中心
        self.effNode.position = Vector3(faceDir * (mouthOffset + effW / 2), 0, -0.12)
        self.effNode.scale = Vector3(-effW * faceDir, 1.0, effH)
        self.effNode.enabled = true
        self.effFrameTimer = 0
        self.effCurrentFrame = 0
        self:_setEffFrame(0)
    end

    self:_setSkillFrame(0)
    log:Write(LOG_INFO, "[Enemy] Boss skill started!")
end

-- 更新大招状态（循环播放三帧动画）
function Enemy:_updateSkill(dt)
    if not self.skillActive then return end

    self.skillFrameTimer = self.skillFrameTimer + dt

    -- 切换身体动画帧
    if self.skillFrameTimer >= BOSS_SKILL_FRAME_DUR then
        self.skillFrameTimer = self.skillFrameTimer - BOSS_SKILL_FRAME_DUR
        self.skillCurrentFrame = self.skillCurrentFrame + 1

        if self.skillCurrentFrame >= BOSS_SKILL_FRAMES then
            -- 播放完一轮结束大招
            self:_endSkill()
            return
        end
        self:_setSkillFrame(self.skillCurrentFrame)
    end

    -- 更新喷射特效帧（4帧均匀分布在0.8s内，每帧0.2s）
    if self.effNode and self.effNode.enabled then
        self.effFrameTimer = self.effFrameTimer + dt
        local effFrameDur = (BOSS_SKILL_FRAMES * BOSS_SKILL_FRAME_DUR) / BOSS_EFF_FRAMES  -- 0.8/4=0.2s
        if self.effFrameTimer >= effFrameDur then
            self.effFrameTimer = self.effFrameTimer - effFrameDur
            self.effCurrentFrame = self.effCurrentFrame + 1
            if self.effCurrentFrame < BOSS_EFF_FRAMES then
                self:_setEffFrame(self.effCurrentFrame)
            end
        end
    end

    -- 第2帧（索引1，蓄力完毕）时造成伤害
    if self.skillCurrentFrame >= 1 and not self.skillDamageDealt then
        self:_skillDamageCheck()
        self.skillDamageDealt = true
    end
end

-- 大招伤害检测：嘴巴前方3米范围
function Enemy:_skillDamageCheck()
    if not self.node or not self.player then return end

    local bossPos = self.node.position
    local playerPos = self.player:getPosition()

    -- 判断Boss面朝方向（朝向玩家）
    local faceDir = playerPos.x > bossPos.x and 1 or -1

    -- 嘴巴位置大约在Boss中心前方1.2米处
    local mouthX = bossPos.x + faceDir * 1.2

    -- 检测玩家是否在嘴巴前方3米范围内
    local playerDx = playerPos.x - mouthX
    local inFront = (faceDir > 0 and playerDx >= 0 and playerDx <= BOSS_SKILL_RANGE)
                 or (faceDir < 0 and playerDx <= 0 and math.abs(playerDx) <= BOSS_SKILL_RANGE)

    -- 垂直距离在合理范围内
    local dy = math.abs(playerPos.y - bossPos.y)

    if inFront and dy <= 2.5 then
        self.player:takeDamage(BOSS_SKILL_DAMAGE, bossPos.x)
        log:Write(LOG_INFO, "[Enemy] Boss skill hit player!")
    end
end

-- 结束大招，隐藏技能特效，恢复本体
function Enemy:_endSkill()
    self.skillActive = false
    self.skillTimer = 0  -- 重置CD
    -- 隐藏技能特效节点
    if self.skillNode then
        self.skillNode.enabled = false
    end
    -- 隐藏喷射特效
    if self.effNode then
        self.effNode.enabled = false
    end

    -- 恢复本体精灵
    if self.spriteNode then
        self.spriteNode.enabled = true
    end
    log:Write(LOG_INFO, "[Enemy] Boss skill ended")
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

    -- 卡牌系统冻结检查：全屏冻结时敌人完全停止
    if self.cardSystem and self.cardSystem:isEnemyFrozen() then
        self.body:SetLinearVelocity(Vector2(0, velocity.y))
        self:_updateHpBar()
        self:_updateFloatingTexts(dt)
        return
    end

    -- 卡牌系统速度倍率
    local cardSpeedMult = 1.0
    if self.cardSystem then
        cardSpeedMult = self.cardSystem:getEnemySpeedMultiplier()
    end

    -- Boss大招更新（释放期间停止移动）
    if self.isBoss and self.skillActive then
        self.body:SetLinearVelocity(Vector2(0, velocity.y))
        self:_updateSkill(dt)
        self:_updateHpBar()
        self:_updateFloatingTexts(dt)
        return
    end

    -- 计算与玩家的距离
    local playerPos = self.player:getPosition()
    local distX = math.abs(playerPos.x - pos.x)

    -- 垂直距离（用于判断是否同层）
    local distY = math.abs(playerPos.y - pos.y)
    local selfHeight = self.isBoss and 2.4 or 1.2  -- 敌人自身高度

    -- 朝向：追逐/攻击时朝向玩家，idle巡逻时朝移动方向
    local faceDir
    if self.chasing then
        faceDir = playerPos.x > pos.x and 1 or -1
    else
        faceDir = self.patrolDir
    end

    if self.isBoss and self.spriteNode then
        local dw = self.bossDispW or 2.4
        local dh = self.bossDispH or 2.4
        self.spriteNode.scale = Vector3(-dw * faceDir, 1.0, dh)
    elseif not self.isBoss and self.spriteNode then
        -- 有贴图的小怪：按每帧比例计算尺寸，通过scale.x翻转
        local halfH = 0.6
        local dispH = halfH * 2
        local dispW = dispH  -- 默认正方形
        local currentData = (self.atkAnimActive and self.atkData) or self.walkData
        if currentData then
            local frameAspect = currentData.framePx / currentData.texH
            dispW = dispH * frameAspect
        end
        -- facesLeft=true时贴图默认朝左(需取反), facesRight时不取反
        local flipSign = (currentData and currentData.facesLeft) and -1 or 1
        self.spriteNode.scale = Vector3(flipSign * dispW * faceDir, 1.0, dispH)
    elseif not self.isBoss and self.sprite then
        self.sprite.flipX = (faceDir > 0)
    end

    -- 小怪动画帧更新（攻击/行走切换）
    if self.atkMaterial and self.atkData and self.attacking then
        -- 攻击动画：切换到攻击材质并播放帧
        if not self.atkAnimActive then
            -- 刚切换到攻击状态，设置攻击材质
            self.atkAnimActive = true
            self.atkFrameTimer = 0
            self.atkCurrentFrame = 0
            local mdl = self.spriteNode:GetComponent("StaticModel")
            if mdl then mdl:SetMaterial(self.atkMaterial) end
            -- 调整精灵尺寸适配攻击帧比例
            local halfH = 0.6
            local dispH = halfH * 2
            local frameAspect = self.atkData.framePx / self.atkData.texH
            self.atkDispW = dispH * frameAspect
            self.atkDispH = dispH
        end
        self.atkFrameTimer = self.atkFrameTimer + dt
        local frameDur = 1.0 / ENEMY_ATK_FPS
        if self.atkFrameTimer >= frameDur then
            self.atkFrameTimer = self.atkFrameTimer - frameDur
            self.atkCurrentFrame = (self.atkCurrentFrame + 1) % self.atkData.frames
            local frameU = self.atkData.framePx / self.atkData.texW
            local offsetU = self.atkCurrentFrame * frameU
            self.atkMaterial:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, offsetU)))
        end
    else
        -- 非攻击状态：如果之前在攻击动画，切回行走材质
        if self.atkAnimActive then
            self.atkAnimActive = false
            if self.walkMaterial and self.spriteNode then
                local mdl = self.spriteNode:GetComponent("StaticModel")
                if mdl then mdl:SetMaterial(self.walkMaterial) end
            end
        end
        -- 行走动画帧更新
        if self.walkMaterial and self.walkData then
            self.walkFrameTimer = self.walkFrameTimer + dt
            local frameDur = 1.0 / ENEMY_WALK_FPS
            if self.walkFrameTimer >= frameDur then
                self.walkFrameTimer = self.walkFrameTimer - frameDur
                local totalFrames = self.walkData.frames or ENEMY_WALK_FRAMES
                self.walkCurrentFrame = (self.walkCurrentFrame + 1) % totalFrames
                local frameU = self.walkData.framePx / self.walkData.texW
                local offsetU = self.walkCurrentFrame * frameU
                self.walkMaterial:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, offsetU)))
            end
        end
    end

    -- Boss行走动画帧更新
    if self.isBoss and self.bossMaterial and self.bossWalkFrames then
        self.bossWalkFrameTimer = self.bossWalkFrameTimer + dt
        local frameDur = 1.0 / self.bossWalkFPS
        if self.bossWalkFrameTimer >= frameDur then
            self.bossWalkFrameTimer = self.bossWalkFrameTimer - frameDur
            self.bossWalkCurrentFrame = (self.bossWalkCurrentFrame + 1) % self.bossWalkFrames
            local frameU = 1.0 / self.bossWalkFrames
            local offsetU = self.bossWalkCurrentFrame * frameU
            self.bossMaterial:SetShaderParameter("UOffset", Variant(Vector4(frameU, 0, 0, offsetU)))
        end
    end

    -- 追逐触发：水平距离在范围内 且 玩家在同一层（垂直距离在自身高度内）
    if not self.chasing and distX <= CHASE_RANGE and distY <= selfHeight then
        self.chasing = true
    end

    -- Boss大招触发：只要存活就持续计时，每4秒释放一次（不依赖追逐状态）
    if self.isBoss and not self.skillActive then
        self.skillTimer = self.skillTimer + dt
        if self.skillTimer >= BOSS_SKILL_CD then
            self:_startSkill()
        end
    end

    if self.chasing then
        if distX <= self.attackRange and distY <= selfHeight then
            -- 攻击状态：停下攻击并造成伤害
            self.attacking = true

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


            local dir = playerPos.x > pos.x and 1 or -1
            local blocked = self:_isBlockedByAlly(dir)

            if blocked then
                -- 前方有友军，停下待机
                self.blockedByAlly = true
                self.body:SetLinearVelocity(Vector2(0, velocity.y))
            else
                -- 无阻挡，正常追逐
                self.blockedByAlly = false
                self.body:SetLinearVelocity(Vector2(self.chaseSpeed * dir * cardSpeedMult, velocity.y))
            end
        end
    else
        -- 待机模式：左右徘徊
        if pos.x > self.startX + self.patrolRange then
            self.patrolDir = -1
        elseif pos.x < self.startX - self.patrolRange then
            self.patrolDir = 1
        end
        self.body:SetLinearVelocity(Vector2(self.patrolSpeed * self.patrolDir * cardSpeedMult, velocity.y))
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
    -- 重置Boss大招状态
    self.skillTimer = 0
    self.skillActive = false
    self.skillFrameTimer = 0
    self.skillCurrentFrame = 0
    self.skillDamageDealt = false
    self.skillFirstApproachTriggered = false
    -- 隐藏技能特效节点
    if self.isBoss and self.skillNode then
        self.skillNode.enabled = false
    end
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
end

function Enemy:isAlive()
    return self.alive
end

function Enemy:getElement()
    return self.element
end

return Enemy
