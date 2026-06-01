-- ============================================================================
-- 2D 动作游戏原型 - game_01 场景模块
-- 功能: WASD移动 + PS手柄支持 + 虚拟摇杆 + 平A攻击 + 5滴血
-- ============================================================================

local UI = require("urhox-libs/UI")

local Game01 = {}

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
---@type Node
local playerNode_ = nil
---@type RigidBody2D
local playerBody_ = nil
---@type Node
local enemyNode_ = nil
local enemyHP_ = 0
local enemyMaxHP_ = 0
---@type Node
local attackFxNode_ = nil  -- 攻击范围表现
local attackFxTimer_ = 0

local uiRoot_ = nil
---@type Node
local enemyHPBarNode_ = nil   -- 小怪血条背景（3D子节点）
---@type Node
local enemyHPFillNode_ = nil  -- 小怪血条填充（3D子节点）

-- ============================================================================
-- 配置表（改这里即可调整手感）
-- ============================================================================
local CONFIG = {
    Title = "2D Action Prototype",

    -- === 物理世界 ===
    Gravity = 20.0,           -- 重力加速度 (m/s²)

    -- === 角色移动 ===
    PlayerSpeed = 4.0,        -- 水平移动速度 (m/s)

    -- === 跳跃 ===
    JumpHeight = 2.0,         -- 单次跳跃高度 (米)，2段跳最大高度 = 2 × JumpHeight
    MaxJumps = 2,             -- 最大跳跃段数（1=单跳, 2=二段跳, 3=三段跳）
    CoyoteTime = 0.12,        -- 土狼时间：走下平台后仍可跳的窗口 (秒)

    -- === 角色尺寸 ===
    PlayerSize = { w = 0.5, h = 0.8 },

    -- === 攻击 ===
    AttackRange = 1.5,        -- 攻击距离 (米)
    AttackDamage = 1,         -- 每次攻击伤害
    AttackCooldown = 0.5,     -- 攻击冷却 (秒)

    -- === 小怪 ===
    EnemyHP = 10,             -- 小怪血量
    EnemySize = { w = 0.5, h = 0.6 },  -- 小怪尺寸
    EnemySpawnX = 4.0,        -- 小怪生成X坐标
    EnemyChaseRange = 1.0,    -- 追逐触发距离 (米)
    EnemyAttackRange = 0.6,   -- 小怪攻击范围 (米，近身)
    EnemySpeed = 0,           -- 小怪追逐速度 (自动计算: 玩家速度 × 0.5)
    EnemyAttackDamage = 1,    -- 小怪每次攻击伤害
    EnemyAttackCooldown = 1.0,-- 小怪攻击冷却 (秒)
}

-- 由配置自动计算的值（不要手动改）
-- 公式: v = sqrt(2 * g * h)，在峰值触发二段跳可达 2 × JumpHeight
CONFIG.JumpForce = math.sqrt(2 * CONFIG.Gravity * CONFIG.JumpHeight)
CONFIG.EnemySpeed = CONFIG.PlayerSpeed * 0.5  -- 小怪速度 = 玩家速度的一半

-- 游戏状态
local playerHP_ = 5
local maxHP_ = 5
local isGrounded_ = false
local facingRight_ = true
local attackTimer_ = 0
local isAttacking_ = false
local attackAnimTimer_ = 0

-- 跳跃
local jumpCount_ = 0
local groundContacts_ = 0  -- 地面接触计数
local coyoteTimer_ = 0  -- 土狼时间计时器
local wasGrounded_ = false  -- 上一帧是否在地面
local jumpGraceTimer_ = 0  -- 跳跃后短暂忽略地面检测（防止刚跳就重新落地）

-- 小怪 AI 状态
local enemyState_ = "idle"   -- idle / chase / attack
local enemyAttackTimer_ = 0  -- 小怪攻击冷却计时
local enemyTriggered_ = false -- 是否已触发追逐（一旦触发不停）
---@type RigidBody2D
local enemyBody_ = nil

-- 游戏状态标记
local gameOver_ = false

-- 倒计时
local countdownTime_ = 5.0
local countdownMax_ = 5.0

-- 输入状态
local moveX_ = 0
local wantJump_ = false
local touchLeft_ = false  -- 触摸左按钮按住
local touchRight_ = false  -- 触摸右按钮按住

-- ============================================================================
-- 生命周期
-- ============================================================================

function Game01.Start()
    graphics.windowTitle = CONFIG.Title
    InitUI()
    CreateScene()
    SetupViewport()
    CreateGameContent()
    CreateGameUI()
    SubscribeToEvents()
    print("=== 2D Action Prototype Started ===")
end

function Game01.Stop()
    -- 清理场景和UI
    UnsubscribeFromAllEvents()
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end
    UI.SetRoot(nil)
    cameraNode_ = nil
    playerNode_ = nil
    playerBody_ = nil
    enemyNode_ = nil
    enemyBody_ = nil
    enemyHPBarNode_ = nil
    enemyHPFillNode_ = nil
    gameOver_ = false
    enemyTriggered_ = false
end

-- ============================================================================
-- 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    local physicsWorld = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld.gravity = Vector2(0, -CONFIG.Gravity)
end

function SetupViewport()
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = 7.2  -- 视野高度7.2米
    cameraNode_.position = Vector3(0, 2, -10)

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

-- ============================================================================
-- 游戏内容
-- ============================================================================

function CreateGameContent()
    -- 背景色
    renderer.defaultZone.fogColor = Color(0.15, 0.15, 0.25, 1.0)

    -- 地面平台
    CreatePlatform(0, -0.5, 20.0, 1.0)

    -- 玩家角色
    CreatePlayer()

    -- 小怪
    CreateEnemy(CONFIG.EnemySpawnX, 0.3)

    -- 攻击范围特效节点（初始隐藏）
    CreateAttackFxNode()
end

function CreatePlatform(x, y, w, h)
    local node = scene_:CreateChild("Platform")
    node.position = Vector3(x, y, 0)

    -- 视觉 (使用 Box 缩放)
    local sprite = node:CreateComponent("StaticModel")
    sprite:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.3, 0.5, 0.3, 1.0)))
    sprite:SetMaterial(mat)
    node:SetScale(Vector3(w, h, 1.0))

    -- 物理
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC

    local shape = node:CreateComponent("CollisionBox2D")
    shape.size = Vector2(w, h)
    shape.friction = 0.5

    return node
end

function CreatePlayer()
    playerNode_ = scene_:CreateChild("Player")
    playerNode_.position = Vector3(0, 1.5, 0)

    -- 视觉 (蓝色立方体)
    local model = playerNode_:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 0.9, 1.0)))
    model:SetMaterial(mat)
    playerNode_:SetScale(Vector3(CONFIG.PlayerSize.w, CONFIG.PlayerSize.h, 0.5))

    -- 物理（linearDamping=0 避免影响跳跃高度，水平停止靠代码控制）
    playerBody_ = playerNode_:CreateComponent("RigidBody2D")
    playerBody_.bodyType = BT_DYNAMIC
    playerBody_.fixedRotation = true
    playerBody_.linearDamping = 0.0
    playerBody_.gravityScale = 1.0

    local shape = playerNode_:CreateComponent("CollisionBox2D")
    shape.size = Vector2(CONFIG.PlayerSize.w, CONFIG.PlayerSize.h)
    shape.density = 1.0
    shape.friction = 0.3
    shape.restitution = 0.0

    -- 脚部传感器 (地面检测) - 使用小薄片在脚底
    local footSensor = playerNode_:CreateComponent("CollisionBox2D")
    footSensor.size = Vector2(CONFIG.PlayerSize.w * 0.6, 0.05)
    footSensor.center = Vector2(0, -CONFIG.PlayerSize.h / 2)
    footSensor.isTrigger = true

    return playerNode_
end

function CreateEnemy(x, y)
    enemyHP_ = CONFIG.EnemyHP
    enemyMaxHP_ = CONFIG.EnemyHP

    enemyNode_ = scene_:CreateChild("Enemy")
    enemyNode_.position = Vector3(x, y, 0)

    -- 视觉 (红色方块)
    local model = enemyNode_:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.2, 0.2, 1.0)))
    model:SetMaterial(mat)
    enemyNode_:SetScale(Vector3(CONFIG.EnemySize.w, CONFIG.EnemySize.h, 0.5))

    -- 物理 (Kinematic: 可移动但不受力/重力，用 sensor 避免推挤玩家)
    enemyBody_ = enemyNode_:CreateComponent("RigidBody2D")
    enemyBody_.bodyType = BT_KINEMATIC
    enemyBody_.fixedRotation = true

    local shape = enemyNode_:CreateComponent("CollisionBox2D")
    shape.size = Vector2(CONFIG.EnemySize.w, CONFIG.EnemySize.h)
    shape.isTrigger = true

    -- 动态创建血条 UI
    SpawnEnemyHPBar()

    return enemyNode_
end

function SpawnEnemyHPBar()
    if not enemyNode_ then return end
    -- 先销毁旧的
    DestroyEnemyHPBar()

    local barWidth = 0.6   -- 血条宽度（米）
    local barHeight = 0.08 -- 血条高度（米）
    local offsetY = CONFIG.EnemySize.h / 2 + 0.15  -- 头顶偏移（相对于敌人缩放后中心）

    -- 注意：enemyNode_ 已经 SetScale(w, h, 0.5)，子节点会继承缩放
    -- 所以子节点的实际位置/尺寸需要除以父节点缩放来抵消
    local parentScaleX = CONFIG.EnemySize.w
    local parentScaleY = CONFIG.EnemySize.h
    local parentScaleZ = 0.5

    -- 背景条（深灰色）
    enemyHPBarNode_ = enemyNode_:CreateChild("HPBarBG")
    enemyHPBarNode_.position = Vector3(0, offsetY / parentScaleY, -0.2 / parentScaleZ)
    enemyHPBarNode_:SetScale(Vector3(barWidth / parentScaleX, barHeight / parentScaleY, 0.01 / parentScaleZ))
    local bgModel = enemyHPBarNode_:CreateComponent("StaticModel")
    bgModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local bgMat = Material:new()
    bgMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    bgMat:SetShaderParameter("MatDiffColor", Variant(Color(0.15, 0.15, 0.15, 1.0)))
    bgModel:SetMaterial(bgMat)

    -- 填充条（红色）
    enemyHPFillNode_ = enemyNode_:CreateChild("HPBarFill")
    enemyHPFillNode_.position = Vector3(0, offsetY / parentScaleY, -0.21 / parentScaleZ)
    enemyHPFillNode_:SetScale(Vector3(barWidth / parentScaleX, barHeight / parentScaleY, 0.01 / parentScaleZ))
    local fillModel = enemyHPFillNode_:CreateComponent("StaticModel")
    fillModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local fillMat = Material:new()
    fillMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    fillMat:SetShaderParameter("MatDiffColor", Variant(Color(0.85, 0.15, 0.15, 1.0)))
    fillModel:SetMaterial(fillMat)
end

function DestroyEnemyHPBar()
    if enemyHPBarNode_ then
        enemyHPBarNode_:Remove()
        enemyHPBarNode_ = nil
    end
    if enemyHPFillNode_ then
        enemyHPFillNode_:Remove()
        enemyHPFillNode_ = nil
    end
end

function CreateAttackFxNode()
    -- 半透明扇形/圆形表示攻击范围
    attackFxNode_ = scene_:CreateChild("AttackFX")
    attackFxNode_.position = Vector3(0, 0, -0.1)  -- 稍微在前面渲染

    local model = attackFxNode_:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.2, 0.4)))
    model:SetMaterial(mat)
    -- 扁平长条表示攻击范围
    attackFxNode_:SetScale(Vector3(CONFIG.AttackRange, 0.3, 0.1))
    attackFxNode_:SetEnabled(false)
end

-- ============================================================================
-- UI
-- ============================================================================

function CreateGameUI()
    uiRoot_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 血量显示 (左上角)
            CreateHPBar(),
            -- 倒计时 (中上)
            CreateCountdownUI(),
            -- 重新开始按钮 (右上角)
            CreateRestartButton(),
            -- 攻击按钮 (右下角)
            CreateAttackButton(),
            -- 虚拟摇杆 (左下角)
            CreateVirtualJoystick(),
            -- 跳跃按钮 (右下角偏上)
            CreateJumpButton(),
            -- 进入攻击范围提示 (初始隐藏)
            CreateAttackTip(),
            -- 游戏失败面板 (初始隐藏)
            CreateGameOverPanel(),
        }
    }
    UI.SetRoot(uiRoot_)
end

function CreateHPBar()
    local hearts = {}
    for i = 1, maxHP_ do
        hearts[#hearts + 1] = UI.Label {
            id = "heart_" .. i,
            text = "❤",
            fontSize = 22,
            fontColor = { 255, 60, 60, 255 },
        }
    end

    return UI.Panel {
        id = "hpBar",
        position = "absolute",
        top = 16,
        left = 16,
        flexDirection = "row",
        gap = 4,
        padding = 8,
        backgroundColor = { 0, 0, 0, 150 },
        borderRadius = 8,
        pointerEvents = "none",
        children = hearts,
    }
end

function CreateCountdownUI()
    return UI.Panel {
        id = "countdownPanel",
        position = "absolute",
        top = 16,
        left = "50%",
        marginLeft = -32,
        width = 64,
        height = 36,
        backgroundColor = { 0, 0, 0, 180 },
        borderRadius = 8,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "none",
        children = {
            UI.Label {
                id = "countdownLabel",
                text = "5",
                fontSize = 22,
                fontColor = { 255, 220, 80, 255 },
            },
        },
    }
end

function CreateAttackTip()
    return UI.Panel {
        id = "attackTip",
        position = "absolute",
        top = 60,
        left = "50%",
        marginLeft = -80,
        width = 160,
        height = 36,
        backgroundColor = { 200, 60, 60, 220 },
        borderRadius = 8,
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        pointerEvents = "none",
        children = {
            UI.Label {
                text = "进入攻击范围!",
                fontSize = 14,
                fontColor = { 255, 255, 255, 255 },
            },
        },
    }
end

function CreateGameOverPanel()
    return UI.Panel {
        id = "gameOverPanel",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        children = {
            UI.Panel {
                width = 240, height = 160,
                backgroundColor = { 30, 30, 50, 240 },
                borderRadius = 16,
                justifyContent = "center",
                alignItems = "center",
                gap = 20,
                children = {
                    UI.Label {
                        text = "游戏失败",
                        fontSize = 28,
                        fontColor = { 255, 80, 80, 255 },
                    },
                    UI.Button {
                        text = "重新开始",
                        fontSize = 16,
                        width = 120, height = 40,
                        borderRadius = 8,
                        variant = "primary",
                        onClick = function(self)
                            RestartGame()
                        end,
                    },
                },
            },
        },
    }
end

function CreateRestartButton()
    return UI.Button {
        id = "restartBtn",
        text = "重开",
        fontSize = 14,
        width = 56,
        height = 32,
        position = "absolute",
        top = 16,
        right = 16,
        borderRadius = 6,
        variant = "outline",
        onClick = function(self)
            RestartGame()
        end,
    }
end



function CreateAttackButton()
    return UI.Button {
        id = "attackBtn",
        text = "平A",
        width = 72,
        height = 72,
        fontSize = 18,
        position = "absolute",
        bottom = 24,
        right = 24,
        borderRadius = 36,
        variant = "danger",
        onClick = function(self)
            TryAttack()
        end,
    }
end

function CreateJumpButton()
    return UI.Panel {
        id = "jumpBtn",
        width = 64,
        height = 64,
        position = "absolute",
        bottom = 108,
        right = 32,
        borderRadius = 32,
        backgroundColor = { 80, 100, 80, 200 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onPointerDown = function(event, widget)
            wantJump_ = true
            widget:SetBackgroundColor({ 120, 180, 120, 255 })
        end,
        onPointerUp = function(event, widget)
            widget:SetBackgroundColor({ 80, 100, 80, 200 })
        end,
        children = {
            UI.Label { text = "跳", fontSize = 16, fontColor = { 255, 255, 255, 255 }, pointerEvents = "none" },
        }
    }
end

function CreateVirtualJoystick()
    -- 左右方向按钮（使用 Panel 实现按住移动，避免 Button 内部拦截 pointer 事件）
    return UI.Panel {
        id = "dirButtons",
        position = "absolute",
        bottom = 32,
        left = 24,
        flexDirection = "row",
        gap = 16,
        children = {
            -- ◀ 左移按钮
            UI.Panel {
                id = "btnLeft",
                width = 72,
                height = 72,
                borderRadius = 12,
                backgroundColor = { 80, 80, 100, 200 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onPointerDown = function(event, widget)
                    touchLeft_ = true
                    widget:SetBackgroundColor({ 120, 120, 180, 255 })
                end,
                onPointerUp = function(event, widget)
                    touchLeft_ = false
                    widget:SetBackgroundColor({ 80, 80, 100, 200 })
                end,
                children = {
                    UI.Label { text = "◀", fontSize = 28, fontColor = { 255, 255, 255, 255 }, pointerEvents = "none" },
                }
            },
            -- ▶ 右移按钮
            UI.Panel {
                id = "btnRight",
                width = 72,
                height = 72,
                borderRadius = 12,
                backgroundColor = { 80, 80, 100, 200 },
                justifyContent = "center",
                alignItems = "center",
                pointerEvents = "auto",
                onPointerDown = function(event, widget)
                    touchRight_ = true
                    widget:SetBackgroundColor({ 120, 120, 180, 255 })
                end,
                onPointerUp = function(event, widget)
                    touchRight_ = false
                    widget:SetBackgroundColor({ 80, 80, 100, 200 })
                end,
                children = {
                    UI.Label { text = "▶", fontSize = 28, fontColor = { 255, 255, 255, 255 }, pointerEvents = "none" },
                }
            },
        }
    }
end

-- ============================================================================
-- 攻击逻辑
-- ============================================================================

function TryAttack()
    if attackTimer_ > 0 then return end
    isAttacking_ = true
    attackAnimTimer_ = 0.2
    attackTimer_ = CONFIG.AttackCooldown

    -- 显示攻击范围特效
    if attackFxNode_ and playerNode_ then
        local px = playerNode_.position.x
        local py = playerNode_.position.y
        local offsetX = facingRight_ and (CONFIG.AttackRange / 2) or (-CONFIG.AttackRange / 2)
        attackFxNode_.position = Vector3(px + offsetX, py, -0.1)
        attackFxNode_:SetEnabled(true)
        attackFxTimer_ = 0.15
    end

    -- 检测攻击范围内的敌人
    if enemyNode_ and playerNode_ and enemyHP_ > 0 then
        local playerPos = playerNode_.position2D
        local enemyPos = enemyNode_.position2D
        local dist = (enemyPos - playerPos):Length()
        if dist <= CONFIG.AttackRange then
            enemyHP_ = enemyHP_ - CONFIG.AttackDamage
            print("Hit enemy! HP=" .. enemyHP_ .. "/" .. enemyMaxHP_)
            -- 小怪受击闪白
            enemyFlashTimer_ = 0.12
            local model = enemyNode_:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
                end
            end
            -- 小怪死亡
            if enemyHP_ <= 0 then
                enemyHP_ = 0
                enemyNode_:SetEnabled(false)
                DestroyEnemyHPBar()
                print("Enemy defeated!")
            end
        end
    end
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 游戏结束时不处理游戏逻辑
    if gameOver_ then
        return
    end

    -- 更新计时器
    if attackTimer_ > 0 then
        attackTimer_ = attackTimer_ - dt
    end
    if attackAnimTimer_ > 0 then
        attackAnimTimer_ = attackAnimTimer_ - dt
        if attackAnimTimer_ <= 0 then
            isAttacking_ = false
        end
    end

    -- 每帧重新计算移动方向
    moveX_ = 0

    -- 触摸按钮
    if touchLeft_ then moveX_ = moveX_ - 1 end
    if touchRight_ then moveX_ = moveX_ + 1 end

    -- 键盘 A/D
    if input:GetKeyDown(KEY_A) then moveX_ = -1 end
    if input:GetKeyDown(KEY_D) then moveX_ = 1 end

    -- 手柄
    ReadGamepadInput()

    -- 跳跃（键盘/按钮）
    if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) then
        wantJump_ = true
    end

    -- 移动角色
    UpdatePlayerMovement(dt)

    -- 攻击动画效果 (角色闪白)
    UpdateAttackVisual()

    -- 攻击范围特效消失
    UpdateAttackFx(dt)

    -- 小怪闪白恢复
    UpdateEnemyVisual(dt)

    -- 小怪 AI
    UpdateEnemyAI(dt)

    -- 倒计时
    UpdateCountdown(dt)

    -- 相机跟随
    UpdateCamera(dt)

    -- 更新血量UI
    UpdateHPUI()
end

---@param eventType string
---@param eventData UpdateEventData
function HandlePostUpdate(eventType, eventData)
    -- PostUpdate 中更新血条位置，确保在相机和物理全部完成后再投影
    UpdateEnemyHPBar()
end

function ReadGamepadInput()
    if input.numJoysticks > 0 then
        local js = input:GetJoystickByIndex(0)
        if js and js:IsController() then
            -- 左摇杆水平轴
            local axisX = js:GetAxisPosition(CONTROLLER_AXIS_LEFTX)
            if math.abs(axisX) > 0.15 then
                moveX_ = axisX
            end
            -- X按钮 = 平A (PS的□)
            if js:GetButtonPress(CONTROLLER_BUTTON_X) then
                TryAttack()
            end
            -- A按钮 = 跳跃 (PS的×)
            if js:GetButtonPress(CONTROLLER_BUTTON_A) then
                wantJump_ = true
            end
        end
    end
end

function UpdatePlayerMovement(dt)
    if not playerBody_ then return end

    -- 跳跃冷却计时
    if jumpGraceTimer_ > 0 then
        jumpGraceTimer_ = jumpGraceTimer_ - dt
    end

    local vel = playerBody_:GetLinearVelocity()
    local desiredVelX = moveX_ * CONFIG.PlayerSpeed

    -- 水平移动（直接设置，无 damping）
    playerBody_:SetLinearVelocity(Vector2(desiredVelX, vel.y))

    -- 朝向
    if moveX_ > 0.1 then
        facingRight_ = true
    elseif moveX_ < -0.1 then
        facingRight_ = false
    end

    -- 土狼时间：刚离开地面时给予短暂跳跃窗口
    if isGrounded_ then
        coyoteTimer_ = CONFIG.CoyoteTime
        wasGrounded_ = true
    else
        if wasGrounded_ then
            if jumpCount_ == 0 then
                coyoteTimer_ = CONFIG.CoyoteTime
            end
            wasGrounded_ = false
        end
        if coyoteTimer_ > 0 then
            coyoteTimer_ = coyoteTimer_ - dt
        end
    end

    -- 跳跃（支持2段跳 + 土狼时间）
    if wantJump_ then
        local canCoyoteJump = (not isGrounded_) and (coyoteTimer_ > 0) and (jumpCount_ == 0)
        if isGrounded_ or canCoyoteJump then
            -- 第一段跳（地面跳或土狼跳）
            playerBody_:SetLinearVelocity(Vector2(desiredVelX, CONFIG.JumpForce))
            jumpCount_ = 1
            isGrounded_ = false
            coyoteTimer_ = 0
            jumpGraceTimer_ = 0.15  -- 起跳后0.15秒内忽略地面检测
        elseif jumpCount_ < CONFIG.MaxJumps then
            -- 第二段跳（空中跳，重置垂直速度确保同等高度）
            playerBody_:SetLinearVelocity(Vector2(desiredVelX, CONFIG.JumpForce))
            jumpCount_ = jumpCount_ + 1
            jumpGraceTimer_ = 0.15
        end
    end
    wantJump_ = false
end

function UpdateAttackVisual()
    if not playerNode_ then return end
    local model = playerNode_:GetComponent("StaticModel")
    if not model then return end
    local mat = model:GetMaterial(0)
    if not mat then return end

    if isAttacking_ then
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, 1.0)))
    else
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.2, 0.4, 0.9, 1.0)))
    end
end



function UpdateAttackFx(dt)
    if attackFxTimer_ > 0 then
        attackFxTimer_ = attackFxTimer_ - dt
        if attackFxTimer_ <= 0 and attackFxNode_ then
            attackFxNode_:SetEnabled(false)
        end
    end
end

local enemyFlashTimer_ = 0

function UpdateEnemyVisual(dt)
    if not enemyNode_ or enemyHP_ <= 0 then return end
    if enemyFlashTimer_ > 0 then
        enemyFlashTimer_ = enemyFlashTimer_ - dt
        if enemyFlashTimer_ <= 0 then
            local model = enemyNode_:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.2, 0.2, 1.0)))
                end
            end
        end
    end
end

function UpdateEnemyAI(dt)
    if not enemyNode_ or not playerNode_ or enemyHP_ <= 0 then
        enemyState_ = "idle"
        HideAttackTip()
        return
    end

    -- 攻击冷却
    if enemyAttackTimer_ > 0 then
        enemyAttackTimer_ = enemyAttackTimer_ - dt
    end

    -- 计算玩家与小怪距离
    local enemyPos = enemyNode_.position
    local playerPos = playerNode_.position
    local dx = playerPos.x - enemyPos.x
    local dist = math.abs(dx)

    -- 进入追逐范围后永久触发
    if dist <= CONFIG.EnemyChaseRange then
        enemyTriggered_ = true
    end

    if dist <= CONFIG.EnemyAttackRange then
        -- 在攻击范围内 → 停止移动，执行攻击
        enemyState_ = "attack"
        ShowAttackTip()

        if enemyAttackTimer_ <= 0 then
            -- 执行攻击
            playerHP_ = playerHP_ - CONFIG.EnemyAttackDamage
            if playerHP_ < 0 then playerHP_ = 0 end
            enemyAttackTimer_ = CONFIG.EnemyAttackCooldown
            print("Enemy attacks! Player HP=" .. playerHP_ .. "/" .. maxHP_)

            -- 玩家死亡 → 显示游戏失败
            if playerHP_ <= 0 then
                ShowGameOver()
                return
            end

            -- 小怪攻击时闪黄
            local model = enemyNode_:GetComponent("StaticModel")
            if model then
                local mat = model:GetMaterial(0)
                if mat then
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.8, 0.0, 1.0)))
                end
            end
            enemyFlashTimer_ = 0.15
        end
    elseif enemyTriggered_ then
        -- 已触发追逐 → 持续朝玩家移动，不停
        enemyState_ = "chase"
        HideAttackTip()
        local dir = dx > 0 and 1 or -1
        local moveAmount = dir * CONFIG.EnemySpeed * dt
        enemyNode_.position = Vector3(enemyPos.x + moveAmount, enemyPos.y, enemyPos.z)
    else
        -- 未触发 → 待机
        enemyState_ = "idle"
        HideAttackTip()
    end
end

function ShowAttackTip()
    if not uiRoot_ then return end
    local tip = uiRoot_:FindById("attackTip")
    if tip then
        tip:SetVisible(true)
    end
end

function HideAttackTip()
    if not uiRoot_ then return end
    local tip = uiRoot_:FindById("attackTip")
    if tip then
        tip:SetVisible(false)
    end
end

function UpdateEnemyHPBar()
    if not enemyHPFillNode_ or enemyHP_ <= 0 then return end

    -- 根据 HP 百分比缩放填充条的 X 轴
    local pct = math.max(0, enemyHP_ / enemyMaxHP_)
    local barWidth = 0.6
    local barHeight = 0.08
    local parentScaleX = CONFIG.EnemySize.w
    local parentScaleY = CONFIG.EnemySize.h
    local parentScaleZ = 0.5

    local fillW = barWidth * pct
    enemyHPFillNode_:SetScale(Vector3(fillW / parentScaleX, barHeight / parentScaleY, 0.01 / parentScaleZ))

    -- 填充条左对齐：向左偏移 (1 - pct) * barWidth / 2
    local offsetY = CONFIG.EnemySize.h / 2 + 0.15
    local offsetX = -(1 - pct) * barWidth / 2
    enemyHPFillNode_.position = Vector3(offsetX / parentScaleX, offsetY / parentScaleY, -0.21 / parentScaleZ)
end

function UpdateCountdown(dt)
    countdownTime_ = countdownTime_ - dt
    if countdownTime_ <= 0 then
        countdownTime_ = countdownMax_
    end

    -- 更新UI显示
    if not uiRoot_ then return end
    local label = uiRoot_:FindById("countdownLabel")
    if label then
        label:SetText(tostring(math.ceil(countdownTime_)))
    end
end

function UpdateCamera(dt)
    if not playerNode_ or not cameraNode_ then return end
    local targetX = playerNode_.position.x
    local targetY = playerNode_.position.y + 1.5
    local camPos = cameraNode_.position
    local lerpSpeed = 6.0
    cameraNode_.position = Vector3(
        camPos.x + (targetX - camPos.x) * lerpSpeed * dt,
        camPos.y + (targetY - camPos.y) * lerpSpeed * dt,
        camPos.z
    )
end

function UpdateHPUI()
    if not uiRoot_ then return end
    for i = 1, maxHP_ do
        local heart = uiRoot_:FindById("heart_" .. i)
        if heart then
            if i <= playerHP_ then
                heart:SetFontColor({ 255, 60, 60, 255 })
            else
                heart:SetFontColor({ 80, 80, 80, 100 })
            end
        end
    end
end

---@param eventType string
---@param eventData PhysicsBeginContact2DEventData
function HandleCollisionBegin(eventType, eventData)
    -- 只处理脚部传感器的触发事件做地面检测
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    local isPlayerContact = (nodeA and nodeA.name == "Player") or (nodeB and nodeB.name == "Player")
    if not isPlayerContact then return end

    -- 跳跃冷却期内忽略地面检测（防止刚起跳就被判定为落地）
    if jumpGraceTimer_ > 0 then return end

    groundContacts_ = groundContacts_ + 1
    isGrounded_ = true
    jumpCount_ = 0  -- 落地重置跳跃次数
end

---@param eventType string
---@param eventData PhysicsEndContact2DEventData
function HandleCollisionEnd(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    local isPlayerContact = (nodeA and nodeA.name == "Player") or (nodeB and nodeB.name == "Player")
    if not isPlayerContact then return end

    groundContacts_ = groundContacts_ - 1
    if groundContacts_ <= 0 then
        groundContacts_ = 0
        isGrounded_ = false
    end
end

-- ============================================================================
-- 重新开始
-- ============================================================================

function ShowGameOver()
    gameOver_ = true
    -- 销毁玩家节点
    if playerNode_ then
        playerNode_:Remove()
        playerNode_ = nil
        playerBody_ = nil
    end
    local panel = uiRoot_:FindById("gameOverPanel")
    if panel then
        panel:SetVisible(true)
    end
end

function RestartGame()
    -- 重新创建玩家（死亡时已销毁）
    if not playerNode_ then
        CreatePlayer()
    end
    playerHP_ = maxHP_
    playerNode_.position = Vector3(0, 1.5, 0)
    playerBody_:SetLinearVelocity(Vector2(0, 0))
    isGrounded_ = false
    jumpCount_ = 0
    groundContacts_ = 0
    coyoteTimer_ = 0
    jumpGraceTimer_ = 0
    attackTimer_ = 0
    countdownTime_ = countdownMax_

    -- 重置小怪
    enemyHP_ = CONFIG.EnemyHP
    enemyMaxHP_ = CONFIG.EnemyHP
    enemyState_ = "idle"
    enemyAttackTimer_ = 0
    enemyTriggered_ = false
    enemyNode_.position = Vector3(CONFIG.EnemySpawnX, 0.3, 0)
    enemyNode_:SetEnabled(true)
    enemyBody_:SetLinearVelocity(Vector2(0, 0))
    local model = enemyNode_:GetComponent("StaticModel")
    if model then
        local mat = model:GetMaterial(0)
        if mat then
            mat:SetShaderParameter("MatDiffColor", Variant(Color(0.8, 0.2, 0.2, 1.0)))
        end
    end

    -- 重新创建血条UI
    SpawnEnemyHPBar()

    -- 隐藏游戏失败面板
    gameOver_ = false
    local panel = uiRoot_:FindById("gameOverPanel")
    if panel then
        panel:SetVisible(false)
    end

    print("=== Game Restarted ===")
end

return Game01
