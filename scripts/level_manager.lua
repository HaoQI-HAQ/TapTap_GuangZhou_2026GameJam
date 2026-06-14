---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- 关卡管理器：管理关卡配置、传送门、关卡切换
local LevelManager = {}
LevelManager.__index = LevelManager

-- 属性池（用于随机生成）
local ELEMENT_POOL = { "fire", "ice", "thunder", "grass", "earth" }

-- 关卡配置
local LEVELS = {
    -- 第一关：7个敌人（固定配置）
    [1] = {
        name = "第一关",
        groundWidth = 46.0,
        platforms = {
            { x = 4.0, y = 0.0, w = 5.0, h = 0.3 },
        },
        enemies = {
            { x = 2.5,  y = 1.0, element = "fire" },
            { x = 4.0,  y = 1.0, element = "ice" },
        },
        -- 传送门位置（右侧平台尽头）
        portalX = 20.0,
        portalY = -2.0,
    },
    -- 第二关：比第一关多2个敌人（9个），属性随机
    [2] = {
        name = "第二关",
        groundWidth = 66.0,
        platforms = {
            { x = 5.0, y = 0.0, w = 6.0, h = 0.3 },
            { x = 12.0, y = 1.0, w = 4.0, h = 0.3 },
        },
        enemies = "random",
        enemyCount = 9,
        spawnZones = {
            { xMin = 3.0, xMax = 6.0, y = 1.0 },
            { xMin = 11.0, xMax = 14.0, y = 2.0 },
        },
        portalX = 30.0,
        portalY = -2.0,
    },
    -- 第三关：比第二关少1只（8个），属性随机
    [3] = {
        name = "第三关",
        groundWidth = 70.0,
        platforms = {
            { x = 6.0, y = 0.5, w = 5.0, h = 0.3 },
            { x = 14.0, y = 1.5, w = 5.0, h = 0.3 },
            { x = 22.0, y = 0.0, w = 4.0, h = 0.3 },
        },
        enemies = "random",
        enemyCount = 8,
        spawnZones = {
            { xMin = 5.0, xMax = 9.0, y = 1.5 },
            { xMin = 13.0, xMax = 17.0, y = 2.5 },
            { xMin = 21.0, xMax = 24.0, y = 1.0 },
        },
        portalX = 32.0,
        portalY = -2.0,
    },
    -- 第四关：比第三关多2只（10个），属性随机
    [4] = {
        name = "第四关",
        groundWidth = 76.0,
        platforms = {
            { x = 4.0, y = 0.0, w = 5.0, h = 0.3 },
            { x = 10.0, y = 1.0, w = 4.0, h = 0.3 },
            { x = 18.0, y = 0.5, w = 5.0, h = 0.3 },
            { x = 26.0, y = 1.5, w = 4.0, h = 0.3 },
        },
        enemies = "random",
        enemyCount = 10,
        spawnZones = {
            { xMin = 3.0, xMax = 7.0, y = 1.0 },
            { xMin = 9.0, xMax = 12.0, y = 2.0 },
            { xMin = 17.0, xMax = 21.0, y = 1.5 },
            { xMin = 25.0, xMax = 28.0, y = 2.5 },
        },
        portalX = 35.0,
        portalY = -2.0,
    },
    -- 第五关：Boss战（只有1只Boss，击败通关）
    [5] = {
        name = "最终关 - Boss战",
        groundWidth = 52.0,  -- 右边界26m（平台2右边界18m + 8m）
        platforms = {
            { x = 0.0, y = 1.5, w = 4.0, h = 0.3 },   -- 左侧高台
            { x = 16.0, y = 1.5, w = 4.0, h = 0.3 },  -- 右侧高台
        },
        enemies = "boss_only",
        bossElement = "random",
        bossList = {
            { x = 12.0, y = 1.0, element = "random" },  -- Boss在地面中右侧
        },
        portalX = nil,
        portalY = nil,
    },
}

-- 保存默认关卡数据的备份（用于 clearCustomLevels 恢复）
local DEFAULT_LEVELS = LEVELS

function LevelManager:new()
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, LevelManager)
    self.currentLevel = 1
    self.maxLevel = #LEVELS
    self.portalNode = nil
    self.portalActive = false
    self.portalTimer = 0
    self.portalDuration = 2.0  -- 读条时间（秒）
    self.playerInPortal = false
    self.teleporting = false
    -- 传送门视觉
    self.portalSpriteNode = nil
    self.portalGlowTimer = 0
    -- 未击败提示
    self.nearPortalHintShown = false
    -- 回调
    self.onTeleportStart = nil  -- function() 读条开始
    self.onTeleportProgress = nil  -- function(progress) 0~1
    self.onTeleportComplete = nil  -- function(nextLevel) 传送完成
    self.onPortalActivated = nil  -- function() 传送门激活
    self.onEnemiesNotCleared = nil  -- function() 到达传送点但敌人未全清
    self.onGameComplete = nil  -- function() 击败最终Boss，游戏通关
    self.gameCompleted = false
    self.levelReady = true  -- 关卡是否已就绪（过渡期间为false，防止误判通关）
    return self
end

--- 获取当前关卡配置
function LevelManager:getLevelConfig(level)
    level = level or self.currentLevel
    return LEVELS[level]
end

--- 生成关卡敌人列表（支持固定配置、随机生成和Boss战）
function LevelManager:generateEnemies(level)
    level = level or self.currentLevel
    local cfg = LEVELS[level]
    if not cfg then return {} end

    if cfg.enemies == "boss_only" then
        -- Boss战：支持多Boss自定义位置
        if cfg.bossList then
            -- 使用自定义Boss列表
            local result = {}
            for _, b in ipairs(cfg.bossList) do
                local element = b.element or cfg.bossElement or "random"
                if element == "random" then
                    element = ELEMENT_POOL[math.random(1, #ELEMENT_POOL)]
                end
                table.insert(result, { x = b.x, y = b.y, element = element, boss = true })
            end
            return result
        else
            -- 兼容旧配置：默认1只Boss
            local element = cfg.bossElement
            if element == "random" then
                element = ELEMENT_POOL[math.random(1, #ELEMENT_POOL)]
            end
            return {
                { x = 5.0, y = 2.0, element = element, boss = true },
            }
        end
    elseif cfg.enemies == "random" then
        -- 随机生成敌人
        return self:_generateRandomEnemies(cfg)
    else
        -- 返回固定配置（复制一份防止原始数据被修改）
        local result = {}
        for _, e in ipairs(cfg.enemies) do
            table.insert(result, {
                x = e.x, y = e.y,
                element = e.element,
                boss = e.boss or false,
            })
        end
        return result
    end
end

--- 随机生成敌人
function LevelManager:_generateRandomEnemies(cfg)
    local result = {}
    local count = cfg.enemyCount or 7
    local zones = cfg.spawnZones

    for i = 1, count do
        -- 随机选择生成区域
        local zone = zones[math.random(1, #zones)]
        local x = zone.xMin + math.random() * (zone.xMax - zone.xMin)
        -- 间隔至少2米避免重叠
        local tooClose = true
        local attempts = 0
        while tooClose and attempts < 20 do
            tooClose = false
            for _, existing in ipairs(result) do
                if math.abs(existing.x - x) < 2.0 and math.abs(existing.y - zone.y) < 1.0 then
                    tooClose = true
                    zone = zones[math.random(1, #zones)]
                    x = zone.xMin + math.random() * (zone.xMax - zone.xMin)
                    break
                end
            end
            attempts = attempts + 1
        end

        -- 随机属性
        local element = ELEMENT_POOL[math.random(1, #ELEMENT_POOL)]

        table.insert(result, {
            x = x,
            y = zone.y,
            element = element,
            boss = false,
        })
    end

    return result
end

--- 获取当前关卡的地形配置
function LevelManager:getGroundConfig(level)
    level = level or self.currentLevel
    local cfg = LEVELS[level]
    if not cfg then return 100.0, {} end
    return cfg.groundWidth, cfg.platforms or {}
end

--- 创建传送门（在场景中放置）
function LevelManager:createPortal(scene)
    local cfg = LEVELS[self.currentLevel]
    if not cfg or not cfg.portalX then return end

    -- 如果是最后一关，不创建传送门
    if self.currentLevel >= self.maxLevel then
        self.portalNode = nil
        return
    end

    self.portalNode = scene:CreateChild("Portal")
    self.portalNode.position = Vector3(cfg.portalX, cfg.portalY, 0.0)

    -- 传送门可视化：使用 Plane + Texture2D（与Boss渲染方式一致）
    -- 大小2.4m x 2.4m，底部对齐（Plane中心上移半高）
    self.portalSpriteNode = self.portalNode:CreateChild("PortalSprite")
    self.portalSpriteNode.rotation = Quaternion(-90, Vector3(1, 0, 0))
    self.portalSpriteNode.position = Vector3(0, 0.2, 0)  -- 下移1米
    self.portalSpriteNode.scale = Vector3(2.4, 1.0, 2.4)  -- 宽2.4m 高2.4m

    local closeTex = cache:GetResource("Texture2D", "image/Scene/door_close.png")
    if closeTex then
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
        mat:SetTexture(0, closeTex)
        mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        mat:SetShaderParameter("UOffset", Variant(Vector4(1, 0, 0, 0)))
        mat:SetShaderParameter("VOffset", Variant(Vector4(0, 1, 0, 0)))
        local model = self.portalSpriteNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        model:SetMaterial(mat)
        self.portalMaterial = mat
    end

    -- 初始显示关闭状态的门
    self.portalNode.enabled = true
    self.portalActive = false
    self.portalTimer = 0
    self.playerInPortal = false
    self.teleporting = false

    log:Write(LOG_INFO, "[LevelManager] Portal created at x=" .. cfg.portalX .. " (closed)")
end

--- 激活传送门（所有敌人被击败后调用）
function LevelManager:activatePortal()
    if not self.portalNode then return end
    if self.portalActive then return end

    self.portalActive = true
    self.portalNode.enabled = true
    self.portalGlowTimer = 0

    -- 切换为打开状态贴图
    if self.portalMaterial then
        local openTex = cache:GetResource("Texture2D", "image/Scene/door_open.png")
        if openTex then
            self.portalMaterial:SetTexture(0, openTex)
        end
    end

    if self.onPortalActivated then
        self.onPortalActivated()
    end

    log:Write(LOG_INFO, "[LevelManager] Portal activated! Walk to it to advance.")
end

--- 检查是否所有敌人都被击败
function LevelManager:checkAllEnemiesDefeated(enemies)
    for _, e in ipairs(enemies) do
        if e:isAlive() then
            return false
        end
    end
    return true
end

--- 更新传送门逻辑
function LevelManager:update(dt, playerPos, enemies)
    -- 第五关（Boss战）：无传送门，击败Boss即通关
    if self.currentLevel >= self.maxLevel and not self.gameCompleted then
        -- levelReady 为 false 时表示正在过渡，不做检测
        if not self.levelReady then return end
        if #enemies > 0 and self:checkAllEnemiesDefeated(enemies) then
            self.gameCompleted = true
            log:Write(LOG_INFO, "[LevelManager] Final Boss defeated! Game Complete!")
            if self.onGameComplete then
                self.onGameComplete()
            end
        end
        return
    end

    if not self.portalActive then
        -- 检查是否所有敌人被击败
        if #enemies > 0 and self:checkAllEnemiesDefeated(enemies) then
            self:activatePortal()
        else
            -- 传送门未激活时，检测玩家是否到达传送点区域
            local cfg = LEVELS[self.currentLevel]
            if cfg and cfg.portalX and self.currentLevel < self.maxLevel then
                local dx = math.abs(playerPos.x - cfg.portalX)
                local dy = math.abs(playerPos.y - cfg.portalY)
                if dx < 2.0 and dy < 2.5 then
                    if not self.nearPortalHintShown then
                        self.nearPortalHintShown = true
                        if self.onEnemiesNotCleared then
                            self.onEnemiesNotCleared()
                        end
                    end
                else
                    self.nearPortalHintShown = false
                end
            end
        end
        return
    end

    if self.teleporting then return end

    -- 传送门脉冲缩放效果（激活后轻微呼吸）
    self.portalGlowTimer = self.portalGlowTimer + dt * 2.0
    if self.portalSpriteNode then
        local pulse = 1.0 + 0.03 * math.sin(self.portalGlowTimer)
        local baseScale = 2.4 * pulse
        self.portalSpriteNode.scale = Vector3(baseScale, 1.0, baseScale)
    end

    -- 检查玩家是否在传送门范围内
    local cfg = LEVELS[self.currentLevel]
    if not cfg then return end

    local dx = math.abs(playerPos.x - cfg.portalX)
    local dy = math.abs(playerPos.y - cfg.portalY)

    if dx < 1.2 and dy < 2.0 then
        -- 玩家进入传送门范围
        if not self.playerInPortal then
            self.playerInPortal = true
            self.portalTimer = 0
            if self.onTeleportStart then
                self.onTeleportStart()
            end
            log:Write(LOG_INFO, "[LevelManager] Player entered portal, charging...")
        end

        -- 读条
        self.portalTimer = self.portalTimer + dt
        local progress = math.min(self.portalTimer / self.portalDuration, 1.0)

        if self.onTeleportProgress then
            self.onTeleportProgress(progress)
        end

        -- 读条完成 → 传送
        if progress >= 1.0 then
            self.teleporting = true
            self:_completeTransition()
        end
    else
        -- 玩家离开传送门范围，重置读条
        if self.playerInPortal then
            self.playerInPortal = false
            self.portalTimer = 0
            if self.onTeleportProgress then
                self.onTeleportProgress(0)
            end
            log:Write(LOG_INFO, "[LevelManager] Player left portal, resetting charge")
        end
    end
end

--- 完成关卡切换
function LevelManager:_completeTransition()
    local nextLevel = self.currentLevel + 1
    if nextLevel > self.maxLevel then
        log:Write(LOG_INFO, "[LevelManager] All levels complete!")
        return
    end

    log:Write(LOG_INFO, "[LevelManager] Teleporting to level " .. nextLevel)
    self.currentLevel = nextLevel
    self.levelReady = false  -- 过渡期间标记为未就绪，防止旧敌人列表误触发通关

    if self.onTeleportComplete then
        self.onTeleportComplete(nextLevel)
    end
end

--- 重置关卡管理器（回到第一关）
function LevelManager:reset()
    self.currentLevel = 1
    self.portalNode = nil
    self.portalActive = false
    self.portalTimer = 0
    self.playerInPortal = false
    self.teleporting = false
end

--- 注入外部关卡数据（编辑器测试用）
--- 将编辑器中编辑的关卡数据覆盖到内部 LEVELS 表
---@param customLevels table 编辑器格式的关卡列表
function LevelManager:setCustomLevels(customLevels)
    if not customLevels or #customLevels == 0 then return end
    -- 覆盖 LEVELS 表
    LEVELS = {}
    for i, src in ipairs(customLevels) do
        local level = {
            name = src.name or ("第" .. i .. "关"),
            groundWidth = src.groundWidth or 100.0,
            platforms = src.platforms or {},
            portalX = src.portalX,
            portalY = src.portalY or -2.0,
        }
        -- 编辑器格式的 enemies 是固定表（非 "random" 字符串）
        if type(src.enemies) == "table" then
            level.enemies = src.enemies
        else
            level.enemies = {}
        end
        LEVELS[i] = level
    end
    self.maxLevel = #LEVELS
    log:Write(LOG_INFO, "[LevelManager] Custom levels injected: " .. #LEVELS .. " levels")
end

--- 清除自定义关卡数据，恢复到硬编码默认值
function LevelManager:clearCustomLevels()
    LEVELS = DEFAULT_LEVELS
    self.maxLevel = #LEVELS
    log:Write(LOG_INFO, "[LevelManager] Restored default levels: " .. #LEVELS .. " levels")
end

--- 设置当前关卡（用于编辑器测试跳转）
function LevelManager:setLevel(level)
    if level >= 1 and level <= self.maxLevel then
        self.currentLevel = level
    end
    self.portalNode = nil
    self.portalActive = false
    self.portalTimer = 0
    self.playerInPortal = false
    self.teleporting = false
end

--- 获取当前关卡号
function LevelManager:getCurrentLevel()
    return self.currentLevel
end

--- 是否是最后一关
function LevelManager:isLastLevel()
    return self.currentLevel >= self.maxLevel
end

return LevelManager
