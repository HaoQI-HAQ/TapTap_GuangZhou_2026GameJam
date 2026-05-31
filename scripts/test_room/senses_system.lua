-- 五感剥夺系统 - 读取 Data/senses_config.txt 配置
-- 每次受伤随机剥夺一种感官（前4次），第5次固定剥夺视觉=死亡
SensesSystem = {}
SensesSystem.__index = SensesSystem

-- 感官类型常量
SensesSystem.HEARING = "hearing"
SensesSystem.TOUCH = "touch"
SensesSystem.TASTE = "taste"
SensesSystem.SMELL = "smell"
SensesSystem.VISION = "vision"

function SensesSystem:new(scene, player, gameUI)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, SensesSystem)
    self.scene = scene
    self.player = player
    self.gameUI = gameUI

    -- 感官配置（从txt读取）
    self.config = {}
    -- 已剥夺的感官列表
    self.deprived = {}
    -- 可随机剥夺的感官池
    self.randomPool = {}
    -- 当前剥夺数量
    self.deprivedCount = 0

    -- 效果状态
    self.driftEnabled = false       -- 触觉：操控漂移
    self.driftOffset = 0            -- 漂移偏移量
    self.uiDistortEnabled = false   -- 味觉：UI扭曲
    self.uiDistortTimer = 0
    self.trapWarningHidden = false  -- 嗅觉：陷阱预警消失
    self.timerGlitch = false        -- 嗅觉：倒计时异常
    self.audioMuted = false         -- 听觉：音效静音
    self.visionFading = false       -- 视觉：画面渐黑
    self.visionFadeAlpha = 0

    -- 加载配置
    self:_loadConfig()

    -- 创建视觉遮罩节点（全屏黑色，初始透明）
    self:_createVisionOverlay()

    log:Write(LOG_INFO, "[SensesSystem] Initialized with " .. #self.randomPool .. " random senses")
    return self
end

--- 从 data/senses_config.lua 加载配置
function SensesSystem:_loadConfig()
    local configData = require("scripts/test_room/data/senses_config")

    for _, entry in ipairs(configData) do
        self.config[entry.sense] = {
            order = entry.order,
            effectType = entry.effectType,
            param1 = entry.param1,
            param2 = entry.param2,
            description = entry.description,
        }

        -- 随机池只加入 order=random 的感官
        if entry.order == "random" then
            table.insert(self.randomPool, entry.sense)
        end
    end
    log:Write(LOG_INFO, "[SensesSystem] Loaded config: " .. #self.randomPool .. " random senses")
end

--- 创建视觉遮罩（全屏黑色 sprite，用于视觉剥夺渐黑效果）
function SensesSystem:_createVisionOverlay()
    -- 使用 UI 覆盖层实现渐黑
    local uiRoot = ui.root
    self.fadeOverlay = BorderImage:new()
    uiRoot:AddChild(self.fadeOverlay)
    self.fadeOverlay:SetSize(graphics.width, graphics.height)
    self.fadeOverlay:SetAlignment(HA_LEFT, VA_TOP)
    self.fadeOverlay.color = Color(0, 0, 0, 0)
    self.fadeOverlay.priority = 800  -- 低于 GameOver UI(900)
    self.fadeOverlay.visible = false
end

--- 当玩家受伤时调用（在 Player:takeDamage 之后）
--- @return string|nil 返回被剥夺的感官名，或 nil（如果无可剥夺）
function SensesSystem:onPlayerDamaged()
    -- 如果所有随机感官已剥夺，则剥夺视觉（=死亡）
    if #self.randomPool == 0 then
        self:_depriveSense(SensesSystem.VISION)
        return SensesSystem.VISION
    end

    -- 随机选一个感官剥夺
    local idx = math.random(1, #self.randomPool)
    local sense = self.randomPool[idx]
    table.remove(self.randomPool, idx)

    self:_depriveSense(sense)
    return sense
end

--- 执行感官剥夺效果
function SensesSystem:_depriveSense(sense)
    self.deprived[sense] = true
    self.deprivedCount = self.deprivedCount + 1
    log:Write(LOG_INFO, "[SensesSystem] Deprived: " .. sense .. " (total: " .. self.deprivedCount .. ")")

    if sense == SensesSystem.HEARING then
        self:_applyHearing()
    elseif sense == SensesSystem.TOUCH then
        self:_applyTouch()
    elseif sense == SensesSystem.TASTE then
        self:_applyTaste()
    elseif sense == SensesSystem.SMELL then
        self:_applySmell()
    elseif sense == SensesSystem.VISION then
        self:_applyVision()
    end
end

--- 听觉剥夺：BGM 和音效静音
function SensesSystem:_applyHearing()
    self.audioMuted = true
    -- 静音所有音频
    audio:SetMasterGain("Effect", 0.0)
    audio:SetMasterGain("Music", 0.0)
    log:Write(LOG_INFO, "[SensesSystem] Hearing deprived: audio muted")
end

--- 触觉剥夺：操控漂移（移动有惯性滑动）
function SensesSystem:_applyTouch()
    self.driftEnabled = true
    -- 增加玩家的线性阻尼降低（模拟滑动惯性）
    if self.player.body then
        self.player.body.linearDamping = 0.05  -- 原来0.5，降低=更滑
    end
    log:Write(LOG_INFO, "[SensesSystem] Touch deprived: drift enabled, damping reduced")
end

--- 味觉剥夺：UI 扭曲（血条/卡牌数字乱跳）
function SensesSystem:_applyTaste()
    self.uiDistortEnabled = true
    log:Write(LOG_INFO, "[SensesSystem] Taste deprived: UI distortion enabled")
end

--- 嗅觉剥夺：环境提示消失（倒计时显示异常）
function SensesSystem:_applySmell()
    self.trapWarningHidden = true
    self.timerGlitch = true
    log:Write(LOG_INFO, "[SensesSystem] Smell deprived: env warnings hidden, timer glitch")
end

--- 视觉剥夺：画面渐黑（=死亡）
function SensesSystem:_applyVision()
    self.visionFading = true
    self.fadeOverlay.visible = true
    log:Write(LOG_INFO, "[SensesSystem] Vision deprived: fading to black (death)")
end

--- 每帧更新（处理动态效果）
function SensesSystem:update(dt)
    -- 触觉：漂移随机偏移（每帧微小抖动加到移动上）
    if self.driftEnabled then
        self.driftOffset = (math.random() - 0.5) * 0.3  -- 随机 -0.15~0.15 的偏移
    end

    -- 味觉：UI 数字抖动效果
    if self.uiDistortEnabled then
        self.uiDistortTimer = self.uiDistortTimer + dt
        self:_updateUIDistort()
    end

    -- 视觉：渐黑效果
    if self.visionFading then
        self.visionFadeAlpha = math.min(1.0, self.visionFadeAlpha + dt * 0.5)  -- 2秒渐黑
        self.fadeOverlay.color = Color(0, 0, 0, self.visionFadeAlpha)
    end
end

--- 味觉剥夺效果：HP图标随机偏移+颜色变化
function SensesSystem:_updateUIDistort()
    if not self.gameUI then return end

    -- HP 图标抖动
    if self.gameUI.hpIcons then
        for i, icon in ipairs(self.gameUI.hpIcons) do
            local offsetX = math.random(-4, 4)
            local offsetY = math.random(-3, 3)
            icon:SetPosition((i - 1) * 40 + offsetX, 5 + offsetY)
            -- 颜色随机闪烁
            if math.random() > 0.7 then
                icon.color = Color(math.random(), math.random(), 0.2, 1.0)
            end
        end
    end
end

--- 获取操控漂移值（Player 移动时叠加）
function SensesSystem:getDriftOffset()
    if self.driftEnabled then
        return self.driftOffset
    end
    return 0
end

--- 获取倒计时显示值（嗅觉剥夺时返回乱数）
function SensesSystem:getDisplayCountdown(realValue)
    if self.timerGlitch then
        -- 每次返回一个在真实值附近随机跳动的数字
        local glitch = realValue + (math.random() - 0.5) * 4.0
        return math.max(0, glitch)
    end
    return realValue
end

--- 检查是否已剥夺某种感官
function SensesSystem:isDeprived(sense)
    return self.deprived[sense] == true
end

--- 获取当前剥夺数量
function SensesSystem:getDeprivedCount()
    return self.deprivedCount
end

--- 重置所有感官（游戏重开时调用）
function SensesSystem:reset()
    self.deprived = {}
    self.randomPool = {}
    self.deprivedCount = 0

    -- 重建随机池
    for sense, cfg in pairs(self.config) do
        if cfg.order == "random" then
            table.insert(self.randomPool, sense)
        end
    end

    -- 恢复所有效果
    self.driftEnabled = false
    self.driftOffset = 0
    self.uiDistortEnabled = false
    self.uiDistortTimer = 0
    self.trapWarningHidden = false
    self.timerGlitch = false
    self.audioMuted = false
    self.visionFading = false
    self.visionFadeAlpha = 0

    -- 恢复音频
    audio:SetMasterGain("Effect", 1.0)
    audio:SetMasterGain("Music", 1.0)

    -- 恢复玩家阻尼
    if self.player.body then
        self.player.body.linearDamping = 0.5
    end

    -- 隐藏遮罩
    if self.fadeOverlay then
        self.fadeOverlay.color = Color(0, 0, 0, 0)
        self.fadeOverlay.visible = false
    end

    -- 恢复 UI 位置
    if self.gameUI and self.gameUI.hpIcons then
        for i, icon in ipairs(self.gameUI.hpIcons) do
            icon:SetPosition((i - 1) * 40, 5)
            icon.color = Color(1.0, 0.2, 0.2, 1.0)
        end
    end

    log:Write(LOG_INFO, "[SensesSystem] Reset all senses")
end

return SensesSystem
