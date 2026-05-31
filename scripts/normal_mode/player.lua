-- Player 类 - 精灵动画 + 战斗系统
Player = {}
Player.__index = Player

local ConfigLoader = require("config_loader")
local _playerCfg = ConfigLoader.loadPlayerConfig()

local MOVE_SPEED = _playerCfg.MOVE_SPEED or 3.0
local JUMP_FORCE = _playerCfg.JUMP_FORCE or 5.0
local MAX_JUMPS = _playerCfg.MAX_JUMPS or 2
local FALL_MULTIPLIER = _playerCfg.FALL_MULTIPLIER or 2
local MAX_HP = _playerCfg.MAX_HP or 5

local INVINCIBLE_DURATION = _playerCfg.INVINCIBLE_DURATION or 1.5
local BLINK_INTERVAL = _playerCfg.BLINK_INTERVAL or 0.1
local NEAR_DEATH_SPEED_MULT = _playerCfg.NEAR_DEATH_SPEED_MULT or 0.6
local ATTACK_RANGE = _playerCfg.ATTACK_RANGE or 1.5
local ATTACK_DAMAGE = _playerCfg.ATTACK_DAMAGE or 1
local ATTACK_COOLDOWN = _playerCfg.ATTACK_COOLDOWN or 0.5
local SLAM_SPEED = _playerCfg.SLAM_SPEED or 15.0
local SLAM_AOE_RANGE = _playerCfg.SLAM_AOE_RANGE or 2.0
local SLAM_DAMAGE = _playerCfg.SLAM_DAMAGE or 3
local SLAM_KNOCKBACK = _playerCfg.SLAM_KNOCKBACK or 8.0
local SLAM_INVINCIBLE_DURATION = 1.0  -- 下落攻击落地后无敌帧时长
local HEAD_PUSH_FORCE = 4.0           -- 站在敌人头顶时向后推力

-- 精灵图配置
local WALK_SHEET = "image/Player/player_walk.png"
local IDLE_SHEET = "image/Player/player_idle.png"
local JUMP_SHEET = "image/Player/player_jump.png"
local DIE_SHEET  = "image/Player/player_die.png"
local ATK_SHEET  = "image/Player/player_atk.png"
local ATK_END_SHEET = "image/Player/player_atk_end.png"
local WALK_COLS = 6        -- 行走6帧
local IDLE_COLS = 6        -- 待机6帧
local JUMP_COLS = 6        -- 跳跃6帧
local DIE_COLS  = 10       -- 死亡10帧
local DIE_FRAME_WIDTH = 205  -- 每帧像素宽（2048/10≈205）
local DIE_ANIM_DURATION = 1.5  -- 死亡动画总时长（秒）
local ATK_COLS = 4         -- 攻击动画列数
local ATK_ROWS = 4         -- 攻击动画行数
local ATK_FRAMES = 16      -- 攻击总帧数（4x4）
local ATK_FPS = 24         -- 攻击动画帧率（快速挥砍）
local ATK_END_COLS = 4     -- 收刀动画列数
local ATK_END_ROWS = 4     -- 收刀动画行数
local ATK_END_FRAMES = 16  -- 收刀总帧数（4x4）
local ATK_END_FPS = 20     -- 收刀动画帧率
local ANIM_FPS = 10        -- 行走动画帧率
local IDLE_FRAME_INTERVAL = 1.5  -- 待机每1.5秒换一帧
local JUMP_AIRTIME = 0.8   -- 预估滞空时间（秒），用于计算跳跃帧率
local PLAYER_WIDTH = 0.7   -- 精灵宽度（米）
local PLAYER_HEIGHT = 2.4  -- 精灵高度（米）
local SPRITE_OFFSET_Y = -0.6  -- 精灵视觉下移，让脚踩草地
-- 攻击动画帧为正方形(384x384/256x256)，整体缩小10%
local ATK_SPRITE_SCALE = 0.9  -- 攻击时缩放比例（90%）
local ATK_SPRITE_WIDTH = PLAYER_HEIGHT * ATK_SPRITE_SCALE   -- 正方形帧：宽=高，缩小10%
local ATK_SPRITE_HEIGHT = PLAYER_HEIGHT * ATK_SPRITE_SCALE  -- 攻击时高度也缩小10%
local ATK_OFFSET_Y = 0.3  -- 攻击时精灵上移距离（米）

function Player:new(scene, inputManager)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, Player)
    self.inputManager = inputManager
    self.jumpCount = 0
    self.jumpPressed = false
    self.isGrounded = false
    self.hp = MAX_HP
    self.maxHp = MAX_HP
    self.dead = false
    -- 受伤无敌帧
    self.invincible = false
    self.invincibleTimer = 0
    self.blinkTimer = 0
    -- 濒死
    self.nearDeath = false
    -- 死亡
    self.deathTimer = 0
    self.gameOverCallback = nil
    -- 攻击
    self.attackCooldown = 0
    self.attackPressed = false
    self.targetEnemy = nil
    self.attacking = false       -- 正在播放攻击动画
    self.attackAnimDone = false   -- 攻击动画是否播完
    -- 下砸攻击
    self.slamming = false
    -- 施法状态（卡牌使用时锁定移动）
    self.castingCard = false
    -- 精灵动画状态
    self.animTime = 0
    self.currentFrame = 0
    self.facingRight = true
    self.isMoving = false
    self.currentAnim = "idle"
    -- 跳跃动画：记录滞空时间，落地时刚好播完
    self.jumpElapsed = 0
    self.jumpAnimDone = false
    self.physicsWorld = scene:GetComponent("PhysicsWorld2D")
    self:_createNode(scene)
    return self
end

function Player:_createNode(scene)
    self.node = scene:CreateChild("Player")
    self.node.position = Vector3(0, -1.9, -1)  -- z=-1 渲染在敌人前面

    -- 创建精灵子节点（Plane 模型 + 材质 渲染精灵图）
    self.spriteNode = self.node:CreateChild("Sprite")
    self.spriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    self.spriteNode.scale = Vector3(PLAYER_WIDTH, 1.0, PLAYER_HEIGHT)
    self.spriteNode.position = Vector3(0, SPRITE_OFFSET_Y, 0)

    -- 加载纹理
    self.walkTexture = cache:GetResource("Texture2D", WALK_SHEET)
    self.idleTexture = cache:GetResource("Texture2D", IDLE_SHEET)
    self.jumpTexture = cache:GetResource("Texture2D", JUMP_SHEET)
    self.dieTexture  = cache:GetResource("Texture2D", DIE_SHEET)
    self.atkTexture  = cache:GetResource("Texture2D", ATK_SHEET)
    self.atkEndTexture = cache:GetResource("Texture2D", ATK_END_SHEET)

    if self.walkTexture == nil then
        log:Write(LOG_ERROR, "[Player] Failed to load walk texture: " .. WALK_SHEET)
        -- 回退到蓝色方块
        local sprite = self.node:CreateComponent("StaticSprite2D")
        sprite:SetSprite(cache:GetResource("Sprite2D", "Urho2D/Box.png"))
        sprite.color = Color(0.2, 0.4, 0.9, 1.0)
        sprite.drawRect = Rect(-0.3, -1.35, 0.3, 1.05)
    else
        -- 创建材质（DiffAlpha 支持透明）
        self.material = Material:new()
        self.material:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        self.material:SetTexture(0, self.idleTexture or self.walkTexture)
        self.material:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        self.material:SetShaderParameter("UOffset", Variant(Vector4(1.0 / IDLE_COLS, 0, 0, 0)))
        self.material:SetShaderParameter("VOffset", Variant(Vector4(0, 1.0, 0, 0)))

        local model = self.spriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        model:SetMaterial(self.material)
        self.spriteModel = model

        log:Write(LOG_INFO, "[Player] Sprite textures loaded (walk/idle/jump)")
    end

    -- 物理
    self.body = self.node:CreateComponent("RigidBody2D")
    self.body.bodyType = BT_DYNAMIC
    self.body.fixedRotation = true
    self.body.linearDamping = 0.5

    -- 碰撞分类常量
    -- CATEGORY_GROUND = 1, CATEGORY_PLAYER = 2, CATEGORY_ENEMY = 4
    local MASK_ALL = 0xFFFF  -- 与所有物体碰撞（包括敌人）

    -- 胶囊碰撞体：矩形中段 + 上下两个圆形
    -- 总体：宽0.5m，高1.0m，上0m，下1.0m（非对称）
    local radius = 0.25  -- 半径 = 宽度/2
    local boxH = 0.5     -- 中段矩形高度
    local boxCenterY = -0.5  -- 矩形中心偏下

    local boxShape = self.node:CreateComponent("CollisionBox2D")
    boxShape.size = Vector2(0.5, boxH)
    boxShape.center = Vector2(0, boxCenterY)
    boxShape.density = 1.0
    boxShape.friction = 0.3
    boxShape.categoryBits = 2  -- CATEGORY_PLAYER
    boxShape.maskBits = MASK_ALL  -- 与敌人碰撞
    self.boxShape = boxShape

    local topCircle = self.node:CreateComponent("CollisionCircle2D")
    topCircle.radius = radius
    topCircle.center = Vector2(0, boxCenterY + boxH / 2)  -- (0, 0.45)
    topCircle.density = 1.0
    topCircle.friction = 0.3
    topCircle.categoryBits = 2  -- CATEGORY_PLAYER
    topCircle.maskBits = MASK_ALL  -- 与敌人碰撞
    self.topCircle = topCircle

    local bottomCircle = self.node:CreateComponent("CollisionCircle2D")
    bottomCircle.radius = radius
    bottomCircle.center = Vector2(0, boxCenterY - boxH / 2)  -- (0, -0.75)
    bottomCircle.density = 1.0
    bottomCircle.friction = 0.0  -- 底部零摩擦，防止卡边
    bottomCircle.categoryBits = 2  -- CATEGORY_PLAYER
    bottomCircle.maskBits = MASK_ALL  -- 与敌人碰撞
    self.bottomCircle = bottomCircle

    -- 保存碰撞体引用（无敌帧时修改maskBits）
    self.collisionShapes = { boxShape, topCircle, bottomCircle }

    -- 音效
    self.sfxSource = self.node:CreateComponent("SoundSource")
    self.sfxSource:SetSoundType(SOUND_EFFECT)
    self.sfxSource.gain = 1.0
    self.sfxWalkSource = self.node:CreateComponent("SoundSource")
    self.sfxWalkSource:SetSoundType(SOUND_EFFECT)
    self.sfxWalkSource.gain = 1.2

    self.sndAttack = cache:GetResource("Sound", "audio/sfx/player_attack.ogg")
    self.sndDropAttack = cache:GetResource("Sound", "audio/sfx/player_drop_attack.ogg")
    self.sndWalk = cache:GetResource("Sound", "audio/sfx/player_walk.ogg")
    self.sndHurt = cache:GetResource("Sound", "audio/sfx/player_hurt.ogg")
    if self.sndWalk then self.sndWalk.looped = true end

    log:Write(LOG_INFO, "[Player] SFX loaded: attack=" .. tostring(self.sndAttack ~= nil)
        .. " drop=" .. tostring(self.sndDropAttack ~= nil)
        .. " walk=" .. tostring(self.sndWalk ~= nil)
        .. " hurt=" .. tostring(self.sndHurt ~= nil))
    log:Write(LOG_INFO, "[Player] Created with HP=" .. self.hp)
end

function Player:update(dt)
    if self.body == nil then
        return
    end

    -- 死亡状态：倒地动画 + Game Over
    if self.dead then
        self:_updateDeath(dt)
        return
    end

    -- 掉落死亡：主平台y=-3，下方5米(y=-8)即死
    local posY = self.node.position.y
    if posY < -8.0 then
        self.hp = 0
        self:_enterDeath()
        return
    end

    -- 无敌帧闪烁
    if self.invincible then
        self:_updateInvincible(dt)
    end

    -- AOE圆淡出删除


    local velocity = self.body:GetLinearVelocity()

    -- 施法状态：锁定水平移动，保持物理
    if self.castingCard then
        self.body:SetLinearVelocity(Vector2(0, velocity.y))
        self:_updateAnimation(dt)
        return
    end

    -- 下砸状态：强制高速下落，踩到敌人=圆形AOE，落地=半圆AOE
    if self.slamming then
        self.body:SetLinearVelocity(Vector2(0, -SLAM_SPEED))
        -- 先检测是否踩到敌人
        local stompedEnemy = self:_checkStompEnemy()
        if stompedEnemy then
            self:_slamLand(true)  -- 踩到敌人：圆形
        else
            self.isGrounded = self:_checkGrounded()
            if self.isGrounded then
                self:_slamLand(false)  -- 落地：半圆
            end
        end
        self:_updateAnimation(dt)
        return
    end

    local desiredVelX = 0

    -- 左右移动（濒死时速度降低）
    local speedMult = self.nearDeath and NEAR_DEATH_SPEED_MULT or 1.0
    if self.inputManager:isActionActive(InputManager.ACTION_LEFT) then
        desiredVelX = -MOVE_SPEED * speedMult
        self.facingRight = false
        self.isMoving = true
    elseif self.inputManager:isActionActive(InputManager.ACTION_RIGHT) then
        desiredVelX = MOVE_SPEED * speedMult
        self.facingRight = true
        self.isMoving = true
    else
        self.isMoving = false
    end

    -- 触觉剥夺：叠加操控漂移
    if self.sensesSystem then
        desiredVelX = desiredVelX + self.sensesSystem:getDriftOffset() * MOVE_SPEED
    end

    self.body:SetLinearVelocity(Vector2(desiredVelX, velocity.y))

    -- 下落加速
    if velocity.y < 0 then
        self.body:ApplyForceToCenter(Vector2(0, -9.81 * FALL_MULTIPLIER), true)
    end

    -- 着地检测：从玩家脚底向下射线检测
    self.isGrounded = self:_checkGrounded()
    if self.isGrounded then
        self.jumpCount = 0
    end

    -- 检测是否站在敌人头顶，施加向后推力
    self:_checkOnEnemyHead()

    -- 跳跃（按下瞬间触发，限制2段）
    local jumpAction = self.inputManager:isActionActive(InputManager.ACTION_JUMP)
    if jumpAction and not self.jumpPressed then
        if self.jumpCount < MAX_JUMPS then
            self.body:SetLinearVelocity(Vector2(velocity.x, 0))
            self.body:ApplyLinearImpulseToCenter(Vector2(0, JUMP_FORCE), true)
            self.jumpCount = self.jumpCount + 1
        end
    end
    self.jumpPressed = jumpAction

    -- 攻击冷却
    if self.attackCooldown > 0 then
        self.attackCooldown = self.attackCooldown - dt
    end

    -- 攻击输入
    local attackAction = self.inputManager:isActionActive(InputManager.ACTION_ATTACK)

    if attackAction and not self.attackPressed and self.attackCooldown <= 0 then
        if not self.isGrounded then
            -- 空中攻击 → 下砸
            self:_enterSlam()
        elseif self.isGrounded then
            -- 地面攻击 → 普通平A
            self:_doAttack()
        end
    end
    self.attackPressed = attackAction

    -- 更新精灵动画
    self:_updateAnimation(dt)
end

-- 精灵动画更新
function Player:_updateAnimation(dt)
    if self.material == nil then return end

    -- 攻击动画优先级最高（attack → attack_end → 正常状态）
    if self.attacking then
        self:_updateAttackAnimation(dt)
        return
    end

    -- 确定当前应该播放的动画状态（优先级：jump > walk > idle）
    local targetAnim
    if not self.isGrounded then
        targetAnim = "jump"
    elseif self.isMoving then
        targetAnim = "walk"
    else
        targetAnim = "idle"
    end

    local cols
    if targetAnim == "jump" then
        cols = JUMP_COLS
    elseif targetAnim == "walk" then
        cols = WALK_COLS
    else
        cols = IDLE_COLS
    end

    -- 切换动画状态时，重置帧并切换纹理
    if targetAnim ~= self.currentAnim then
        self.currentAnim = targetAnim
        self.currentFrame = 0
        self.animTime = 0
        if targetAnim == "jump" then
            self.jumpElapsed = 0
            self.jumpAnimDone = false
            if self.jumpTexture then
                self.material:SetTexture(0, self.jumpTexture)
            end
        elseif targetAnim == "idle" and self.idleTexture then
            self.material:SetTexture(0, self.idleTexture)
        else
            self.material:SetTexture(0, self.walkTexture)
        end
    end

    -- 走路音效控制（每帧检查）
    if self.sfxWalkSource and self.sndWalk then
        if targetAnim == "walk" then
            if not self.sfxWalkSource:IsPlaying() then
                self.sfxWalkSource:Play(self.sndWalk)
            end
        else
            if self.sfxWalkSource:IsPlaying() then
                self.sfxWalkSource:Stop()
            end
        end
    end

    -- 播放动画帧（不同状态不同逻辑）
    if targetAnim == "jump" then
        -- 跳跃：根据滞空时间均匀分配帧，落地时刚好播完
        self.jumpElapsed = self.jumpElapsed + dt
        if not self.jumpAnimDone then
            -- 用预估滞空时间计算当前应显示的帧
            local progress = math.min(self.jumpElapsed / JUMP_AIRTIME, 1.0)
            self.currentFrame = math.min(math.floor(progress * cols), cols - 1)
        end
    elseif targetAnim == "walk" then
        -- 走路：按住方向键持续循环播放
        self.animTime = self.animTime + dt
        local frameDuration = 1.0 / ANIM_FPS
        if self.animTime >= frameDuration then
            self.animTime = self.animTime - frameDuration
            self.currentFrame = (self.currentFrame + 1) % cols
        end
    else
        -- 待机：每1.5秒换一帧
        self.animTime = self.animTime + dt
        if self.animTime >= IDLE_FRAME_INTERVAL then
            self.animTime = self.animTime - IDLE_FRAME_INTERVAL
            self.currentFrame = (self.currentFrame + 1) % cols
        end
    end

    -- 更新 UV offset 显示当前帧（单行精灵图）
    local uOffset = self.currentFrame / cols
    local uScale = 1.0 / cols

    -- 翻转方向：通过 UOffset 的 scale 符号控制
    if self.facingRight then
        self.material:SetShaderParameter("UOffset", Variant(Vector4(uScale, 0, 0, uOffset)))
    else
        self.material:SetShaderParameter("UOffset", Variant(Vector4(-uScale, 0, 0, uOffset + uScale)))
    end
end

-- 攻击动画更新（4x4 网格精灵图）
function Player:_updateAttackAnimation(dt)
    self.animTime = self.animTime + dt

    local cols, rows, totalFrames, fps, texture
    if self.currentAnim == "attack" then
        cols = ATK_COLS
        rows = ATK_ROWS
        totalFrames = ATK_FRAMES
        fps = ATK_FPS
        texture = self.atkTexture
    else  -- "attack_end"
        cols = ATK_END_COLS
        rows = ATK_END_ROWS
        totalFrames = ATK_END_FRAMES
        fps = ATK_END_FPS
        texture = self.atkEndTexture
    end

    local frameDuration = 1.0 / fps
    if self.animTime >= frameDuration then
        self.animTime = self.animTime - frameDuration
        self.currentFrame = self.currentFrame + 1
    end

    -- 动画播完检查
    if self.currentFrame >= totalFrames then
        if self.currentAnim == "attack" then
            -- 攻击动画播完 → 切到收刀动画
            self.currentAnim = "attack_end"
            self.currentFrame = 0
            self.animTime = 0
            if self.material and self.atkEndTexture then
                self.material:SetTexture(0, self.atkEndTexture)
            end
        else
            -- 收刀动画播完 → 退出攻击状态
            self.attacking = false
            self.attackAnimDone = true
            self.currentAnim = "idle"
            self.currentFrame = 0
            self.animTime = 0
            if self.material then
                if self.idleTexture then
                    self.material:SetTexture(0, self.idleTexture)
                end
                -- 重置 VOffset 回单行模式
                self.material:SetShaderParameter("VOffset", Variant(Vector4(0, 1.0, 0, 0)))
            end
            -- 恢复正常精灵比例和位置
            if self.spriteNode then
                self.spriteNode.scale = Vector3(PLAYER_WIDTH, 1.0, PLAYER_HEIGHT)
                self.spriteNode.position = Vector3(0, SPRITE_OFFSET_Y, 0)
            end
            return
        end
    end

    -- 计算 4x4 网格中的行列位置
    local frame = math.min(self.currentFrame, totalFrames - 1)
    local col = frame % cols
    local row = math.floor(frame / cols)

    local uScale = 1.0 / cols
    local vScale = 1.0 / rows
    local uOfs = col * uScale
    local vOfs = row * vScale

    -- 翻转方向
    if self.facingRight then
        self.material:SetShaderParameter("UOffset", Variant(Vector4(uScale, 0, 0, uOfs)))
    else
        self.material:SetShaderParameter("UOffset", Variant(Vector4(-uScale, 0, 0, uOfs + uScale)))
    end
    self.material:SetShaderParameter("VOffset", Variant(Vector4(0, vScale, 0, vOfs)))
end

-- 执行平A攻击（查找范围内最近的存活敌人）
function Player:_doAttack()
    self.attackCooldown = ATTACK_COOLDOWN
    -- 进入攻击动画状态
    self.attacking = true
    self.attackAnimDone = false
    self.currentAnim = "attack"
    self.currentFrame = 0
    self.animTime = 0
    if self.material and self.atkTexture then
        self.material:SetTexture(0, self.atkTexture)
    end
    -- 攻击帧是正方形，整体缩小20%并上移
    if self.spriteNode then
        self.spriteNode.scale = Vector3(ATK_SPRITE_WIDTH, 1.0, ATK_SPRITE_HEIGHT)
        self.spriteNode.position = Vector3(0, SPRITE_OFFSET_Y + ATK_OFFSET_Y, 0)
    end
    if self.sfxSource and self.sndAttack then self.sfxSource:Play(self.sndAttack) end
    if not self.enemies then return end

    local myPos = self.node.position
    local nearestEnemy = nil
    local nearestDist = ATTACK_RANGE + 1

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local enemyX = e.node.position.x
            -- 只能攻击面朝方向的敌人
            local inFront = (self.facingRight and enemyX > myPos.x) or
                            (not self.facingRight and enemyX < myPos.x)
            if inFront then
                local dist = math.abs(myPos.x - enemyX)
                if dist < nearestDist then
                    nearestDist = dist
                    nearestEnemy = e
                end
            end
        end
    end

    if nearestEnemy and nearestDist <= ATTACK_RANGE then
        nearestEnemy:takeDamage(ATTACK_DAMAGE, myPos.x)
        log:Write(LOG_INFO, "[Player] Attack hit! Dist=" .. string.format("%.2f", nearestDist))
    end
end

-- 进入下砸状态
function Player:_enterSlam()
    self.slamming = true
    self.attackCooldown = ATTACK_COOLDOWN
    self.body:SetLinearVelocity(Vector2(0, -SLAM_SPEED))
    -- 下落攻击时关闭碰撞体（无敌帧结束后恢复）
    self:_setCollisionEnabled(false)
    if self.sfxSource and self.sndDropAttack then self.sfxSource:Play(self.sndDropAttack) end
    log:Write(LOG_INFO, "[Player] Slam attack started! Collision OFF")
end

-- 下砸落地：AOE伤害 + 击飞
-- fullCircle: true=踩到敌人(圆形AOE), false=落地(半圆AOE)
function Player:_slamLand(fullCircle)
    self.slamming = false
    self.jumpCount = 0

    local myPos = self.node.position

    -- 显示AOE范围可视化
    -- AOE视觉特效已移除

    if not self.enemies then return end

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local enemyPos = e.node.position
            local distX = math.abs(myPos.x - enemyPos.x)
            local distY = math.abs(myPos.y - enemyPos.y)
            -- 水平和垂直距离都必须在范围内
            if distX <= SLAM_AOE_RANGE and distY <= SLAM_AOE_RANGE then
                e:takeDamage(SLAM_DAMAGE, myPos.x)
                if e:isAlive() and e.body then
                    local dir = enemyPos.x > myPos.x and 1 or -1
                    e.body:ApplyLinearImpulseToCenter(Vector2(SLAM_KNOCKBACK * dir, SLAM_KNOCKBACK * 0.6), true)
                end
            end
        end
    end
    local shape = fullCircle and "circle" or "semicircle"
    log:Write(LOG_INFO, "[Player] Slam landed! AOE=" .. shape .. " range=" .. SLAM_AOE_RANGE .. "m")

    -- 下落攻击落地后给予1s无敌帧（不闪烁）
    self.invincible = true
    self.slamInvincible = true
    self.invincibleTimer = SLAM_INVINCIBLE_DURATION
    self.blinkTimer = 0
    log:Write(LOG_INFO, "[Player] Slam invincible ON for " .. SLAM_INVINCIBLE_DURATION .. "s (no blink)")
end

-- 检测下砸是否踩到敌人（玩家脚底与敌人头顶重叠）
function Player:_checkStompEnemy()
    if not self.enemies then return false end
    local myPos = self.node.position
    local footY = myPos.y - 0.7  -- 玩家脚底Y

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local ePos = e.node.position
            local distX = math.abs(myPos.x - ePos.x)
            local enemyTopY = ePos.y + 0.6  -- 敌人头顶Y
            -- 水平距离小于踩踏范围，且玩家脚底接近敌人头顶
            if distX <= 0.8 and footY <= enemyTopY and footY >= ePos.y - 0.3 then
                return true
            end
        end
    end
    return false
end

-- 检测玩家是否站在敌人头顶（非下砸状态），施加向后推力使玩家离开
function Player:_checkOnEnemyHead()
    if not self.enemies then return end
    if self.slamming then return end  -- 下砸中不做推力

    local myPos = self.node.position
    local footY = myPos.y - 0.7  -- 玩家脚底Y

    for _, e in ipairs(self.enemies) do
        if e:isAlive() and e.node then
            local ePos = e.node.position
            local distX = math.abs(myPos.x - ePos.x)
            local enemyTopY = ePos.y + 0.6  -- 敌人头顶Y
            -- 水平距离近且玩家脚底在敌人头顶附近
            if distX <= 0.8 and footY <= enemyTopY + 0.3 and footY >= ePos.y then
                -- 向远离敌人的方向施加推力
                local pushDir = (myPos.x >= ePos.x) and 1 or -1
                self.body:ApplyLinearImpulseToCenter(Vector2(HEAD_PUSH_FORCE * pushDir, 0), true)
                return
            end
        end
    end
end

-- 显示下砸AOE范围（fullCircle=true圆形，false=半圆）
function Player:_showSlamAOECircle(pos, fullCircle)
    local scene = self.node:GetScene()
    local circleNode = scene:CreateChild("SlamAOE")
    circleNode.position = Vector3(pos.x, pos.y - 0.6, -0.1)

    local geom = circleNode:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, LINE_STRIP)

    local segments = 32
    local startAngle, endAngle
    if fullCircle then
        -- 完整圆形
        startAngle = 0
        endAngle = math.pi * 2
    else
        -- 上半圆（地面落地，向上扩散）
        startAngle = 0
        endAngle = math.pi
    end

    for i = 0, segments do
        local angle = startAngle + (i / segments) * (endAngle - startAngle)
        local x = math.cos(angle) * SLAM_AOE_RANGE
        local y = math.sin(angle) * SLAM_AOE_RANGE
        geom:DefineVertex(Vector3(x, y, 0))
        geom:DefineColor(Color(1.0, 0.3, 0.0, 0.8))
    end
    geom:Commit()

    -- 无光照材质
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.3, 0.0, 0.8)))
    geom:SetMaterial(mat)

    -- 0.5秒后自动删除
    self.slamAOENode = circleNode
    self.slamAOETimer = 0.5
end

-- 无敌帧更新（闪烁效果）
function Player:_updateInvincible(dt)
    self.invincibleTimer = self.invincibleTimer - dt

    -- 下落攻击无敌帧不闪烁，其他情况正常闪烁
    if not self.slamInvincible then
        self.blinkTimer = self.blinkTimer + dt
        if self.blinkTimer >= BLINK_INTERVAL then
            self.blinkTimer = 0
            if self.spriteNode then
                self.spriteNode.enabled = not self.spriteNode.enabled
            end
        end
    end

    -- 无敌时间结束
    if self.invincibleTimer <= 0 then
        self.invincible = false
        -- 下落攻击无敌结束时恢复碰撞体
        if self.slamInvincible then
            self:_setCollisionEnabled(true)
            log:Write(LOG_INFO, "[Player] Slam invincible ended, Collision ON")
        end
        self.slamInvincible = false
        if self.spriteNode then
            self.spriteNode.enabled = true
        end
        log:Write(LOG_INFO, "[Player] Invincible OFF")
    end
end

-- 死亡状态更新（播放死亡精灵动画）
function Player:_updateDeath(dt)
    self.deathTimer = self.deathTimer + dt

    if self.material and self.dieTexture then
        -- 根据时间进度计算当前帧
        local progress = math.min(self.deathTimer / DIE_ANIM_DURATION, 1.0)
        local frame = math.min(math.floor(progress * DIE_COLS), DIE_COLS - 1)

        -- 死亡帧用像素宽度计算UV（非等分纹理）
        local texW = self.dieTexture:GetWidth()
        local uScale = DIE_FRAME_WIDTH / texW
        local uOffset = frame * uScale

        if self.facingRight then
            self.material:SetShaderParameter("UOffset", Variant(Vector4(uScale, 0, 0, uOffset)))
        else
            self.material:SetShaderParameter("UOffset", Variant(Vector4(-uScale, 0, 0, uOffset + uScale)))
        end
    end

    -- 动画播完后触发 Game Over
    if self.deathTimer >= DIE_ANIM_DURATION + 0.5 then
        if self.gameOverCallback then
            self.gameOverCallback()
        end
    end
end

-- 受伤
function Player:takeDamage(amount, sourceX)
    -- 无敌期间不受伤
    if self.invincible then
        log:Write(LOG_INFO, "[Player] Invincible! Damage blocked.")
        return false
    end
    if self.dead then return false end

    self.hp = math.max(0, self.hp - (amount or 1))
    if self.sfxSource and self.sndHurt then self.sfxSource:Play(self.sndHurt) end
    log:Write(LOG_INFO, "[Player] Took damage, HP=" .. self.hp)

    -- 小击退：远离攻击来源方向
    if sourceX and self.body then
        local myX = self.node.position.x
        local dir = myX > sourceX and 1 or -1
        self.body:ApplyLinearImpulseToCenter(Vector2(dir * 2.0, 1.5), true)
    end

    -- 触发五感剥夺回调
    if self.onDamagedCallback then
        self.onDamagedCallback()
    end

    if self.hp <= 0 then
        self:_enterDeath()
        return true
    elseif self.hp == 1 then
        -- 濒死：材质颜色变暗
        self.nearDeath = true
        if self.material then
            self.material:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.3, 0.3, 1.0)))
        end
        self:_enterInvincible()
    else
        self:_enterInvincible()
    end
    return false
end

-- 切换碰撞掩码：下落攻击期间只与地面碰撞（排除敌人），结束后恢复全碰撞
function Player:_setCollisionEnabled(enabled)
    if self.collisionShapes then
        for _, shape in ipairs(self.collisionShapes) do
            if enabled then
                shape.maskBits = 0xFFFF  -- 恢复与所有物体碰撞
            else
                shape.maskBits = 1  -- 仅与地面碰撞（CATEGORY_GROUND=1）
            end
        end
    end
end

-- 进入无敌帧（仅视觉闪烁+伤害豁免，碰撞已永久排除敌人）
function Player:_enterInvincible()
    -- 如果从下落攻击无敌切换到受伤无敌，恢复碰撞体
    if self.slamInvincible then
        self:_setCollisionEnabled(true)
    end
    self.invincible = true
    self.slamInvincible = false
    self.invincibleTimer = INVINCIBLE_DURATION
    self.blinkTimer = 0
    log:Write(LOG_INFO, "[Player] Invincible ON for " .. INVINCIBLE_DURATION .. "s")
end

-- 进入死亡
function Player:_enterDeath()
    self.dead = true
    self.deathTimer = 0
    self.attacking = false  -- 中断攻击动画
    self.body:SetLinearVelocity(Vector2(0, 0))
    -- 切换到死亡动画纹理
    if self.material and self.dieTexture then
        self.material:SetTexture(0, self.dieTexture)
        self.material:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        -- 重置 VOffset 回单行模式
        self.material:SetShaderParameter("VOffset", Variant(Vector4(0, 1.0, 0, 0)))
    end
    -- 恢复精灵比例和位置（攻击中被击杀时需要）
    if self.spriteNode then
        self.spriteNode.enabled = true
        self.spriteNode.scale = Vector3(PLAYER_WIDTH, 1.0, PLAYER_HEIGHT)
        self.spriteNode.position = Vector3(0, SPRITE_OFFSET_Y, 0)
    end
    log:Write(LOG_INFO, "[Player] Dead! Playing die animation")
end

-- 回血
function Player:heal(amount)
    self.hp = math.min(self.maxHp, self.hp + (amount or 1))
end

function Player:getHp()
    return self.hp
end

function Player:getMaxHp()
    return self.maxHp
end

function Player:isDead()
    return self.hp <= 0
end

-- 射线检测玩家是否着地
function Player:_checkGrounded()
    local pos = self.node.position
    local startPoint = Vector2(pos.x, pos.y - 1.0)
    local endPoint = Vector2(pos.x, pos.y - 1.1)

    local result = self.physicsWorld:RaycastSingle(startPoint, endPoint)
    if result.body ~= nil and result.body ~= self.body then
        return true
    end
    return false
end

function Player:reset()
    self.hp = MAX_HP
    self.jumpCount = 0
    self.jumpPressed = false
    self.isGrounded = false
    self.dead = false
    self.invincible = false
    self.invincibleTimer = 0
    self.blinkTimer = 0
    self.nearDeath = false
    self.deathTimer = 0
    self.attackCooldown = 0
    self.attackPressed = false
    self.slamming = false
    self.castingCard = false
    self.attacking = false
    self.attackAnimDone = false
    self.isMoving = false
    self.currentAnim = "idle"
    self.currentFrame = 0
    self.animTime = 0
    self.node.position = Vector3(0, -1.9, -1)  -- z=-1 渲染在敌人前面
    self.node.rotation = Quaternion(0, 0, 0)
    if self.spriteNode then
        self.spriteNode.enabled = true
        self.spriteNode.scale = Vector3(PLAYER_WIDTH, 1.0, PLAYER_HEIGHT)
        self.spriteNode.position = Vector3(0, SPRITE_OFFSET_Y, 0)
    end
    if self.material then
        self.material:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        self.material:SetTexture(0, self.idleTexture or self.walkTexture)
        -- 重置 VOffset 回单行模式
        self.material:SetShaderParameter("VOffset", Variant(Vector4(0, 1.0, 0, 0)))
    end
    self.body:SetLinearVelocity(Vector2(0, 0))
    log:Write(LOG_INFO, "[Player] Reset to initial state")
end

function Player:getPosition()
    return self.node.position
end

return Player
