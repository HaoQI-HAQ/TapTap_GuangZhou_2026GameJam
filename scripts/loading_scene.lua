-- LoadingScene 预加载场景模块
-- 显示加载进度，预加载所有游戏资源后回调通知完成
LoadingScene = {}
LoadingScene.__index = LoadingScene

-- 需要预加载的音频资源
local PRELOAD_SOUNDS = {
    "audio/sfx/player_attack.ogg",
    "audio/sfx/player_drop_attack.ogg",
    "audio/sfx/player_hurt.ogg",
    "audio/sfx/player_walk.ogg",
}

-- 需要预加载的所有纹理资源
local PRELOAD_TEXTURES = {
    -- 开始界面背景
    "image/UI/start_bg.png",
    -- 游戏操控UI
    "image/UI/joystick_base.png",
    "image/UI/btn_attack.png",
    "image/UI/btn_jump.png",
    -- 玩家
    "image/Player/player_idle.png",
    "image/Player/player_walk.png",
    "image/Player/player_jump.png",
    "image/Player/player_die.png",
    "image/Player/player_atk.png",
    "image/Player/player_atk_end.png",
    -- 敌人
    "image/Enemy/fire/enemy_fire_walk.png",
    "image/Enemy/ice/enemy_ice_walk.png",
    "image/Enemy/thunder/enemy_thunder_walk.png",
    "image/Enemy/grass/enemy_grass_walk.png",
    "image/Enemy/earth/enemy_earth_walk.png",
    "image/Enemy/boss_01.png",
    "image/Enemy/boss_01_walk.png",
    "image/Enemy/boss_01_skill_01.png",
    "image/Enemy/boss_01_skill_01_eff.png",
    -- 卡牌
    "image/card/card_F01_烈焰弹_20260601140000.png",
    "image/card/card_F03_熔岩喷射_20260601140000.png",
    "image/card/card_I01_冰霜刺_20260601140000.png",
    "image/card/card_I02_冰晶弹幕_20260601140000.png",
    "image/card/card_I03_极寒领域_20260601140000.png",
    "image/card/card_T01_雷霆击_20260601140000.png",
    "image/card/card_T03_雷暴领域_20260601140000.png",
    "image/card/card_T04_瞬雷_20260601140000.png",
    "image/card/card_W01_旋风斩_20260601140000.png",
    "image/card/card_W02_风刃飞射_20260601140000.png",
    "image/card/card_W04_真空斩_20260601140000.png",
    "image/card/card_E02_尖刺陷阱_20260601140000.png",
    "image/card/card_E03_岩壁屏障_20260601140000.png",
    "image/card/card_E04_地裂冲击_20260601140000.png",
    "image/card/card_N01_时间停止_20260601140000.png",
    "image/card/card_N02_时间裂隙_20260601140000.png",
    "image/card/card_N03_时间减缓_20260601140000.png",
    "image/card/card_N06_空间折跃_20260601140000.png",
    "image/card/card_N07_物质崩解_20260601140000.png",
    "image/card/card_N08_物质凝聚弹_20260601140000.png",
    "image/card/card_N09_虚无之刃_20260601140000.png",
    "image/card/card_N10_中和射线_20260601140000.png",
    "image/card/card_S01_梦想封印_20260601140000.png",
    -- 五感图标
    "image/sense_vision_on_20260530095553.png",
    "image/sense_vision_off_20260530095608.png",
    "image/sense_hearing_on_20260530095610.png",
    "image/sense_hearing_off_20260530095554.png",
    "image/sense_smell_on_20260530095552.png",
    "image/sense_smell_off_20260530095551.png",
    "image/sense_taste_on_20260530095550.png",
    "image/sense_taste_off_20260530095555.png",
    "image/sense_touch_on_20260530095556.png",
    "image/sense_touch_off_20260530095555.png",
}

-- 合并所有需要预加载的资源（类型 + 路径）
local PRELOAD_ALL = {}
for _, p in ipairs(PRELOAD_TEXTURES) do
    table.insert(PRELOAD_ALL, { type = "Texture2D", path = p })
end
for _, p in ipairs(PRELOAD_SOUNDS) do
    table.insert(PRELOAD_ALL, { type = "Sound", path = p })
end

function LoadingScene:new(onComplete)
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, LoadingScene)
    self.onComplete = onComplete
    self.totalCount = #PRELOAD_ALL
    self.loadedCount = 0
    self.asyncPending = 0
    self.asyncMode = false  -- 是否使用异步加载（DWP 模式）
    self.finished = false
    self.panel = nil
    self.progressText = nil
    self.progressBar = nil
    self.progressFill = nil
    self:_createUI()
    self:_startPreload()
    return self
end

function LoadingScene:_createUI()
    local uiRoot = ui.root
    local uiStyle = cache:GetResource("XMLFile", "UI/DefaultStyle.xml")
    uiRoot.defaultStyle = uiStyle

    -- 全屏面板
    self.panel = UIElement:new()
    uiRoot:AddChild(self.panel)
    self.panel:SetSize(graphics.width, graphics.height)
    self.panel:SetAlignment(HA_LEFT, VA_TOP)
    self.panel:SetPriority(2000)  -- 最高优先级

    -- 黑色背景
    local bg = BorderImage:new()
    self.panel:AddChild(bg)
    bg:SetSize(graphics.width, graphics.height)
    bg.color = Color(0.059, 0.059, 0.137, 1.0)  -- PX_BG #0F0F23

    -- 标题文字
    local title = Text:new()
    self.panel:AddChild(title)
    local pxFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf")
    if pxFont then title:SetFont(pxFont, 32) else title:SetStyleAuto(); title:SetFontSize(32) end
    title.text = "LOADING..."
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, -40)
    title.color = Color(0.129, 0.741, 0.682, 1.0)  -- PX_PRIMARY teal

    -- 进度条背景
    local barW = math.floor(graphics.width * 0.6)
    local barH = 16
    self.progressBar = BorderImage:new()
    self.panel:AddChild(self.progressBar)
    self.progressBar:SetSize(barW, barH)
    self.progressBar:SetAlignment(HA_CENTER, VA_CENTER)
    self.progressBar:SetPosition(0, 10)
    self.progressBar.color = Color(0.2, 0.2, 0.3, 1.0)

    -- 进度条填充
    self.progressFill = BorderImage:new()
    self.progressBar:AddChild(self.progressFill)
    self.progressFill:SetSize(0, barH)
    self.progressFill:SetPosition(0, 0)
    self.progressFill.color = Color(0.129, 0.741, 0.682, 1.0)  -- PX_PRIMARY teal

    -- 进度文字
    self.progressText = Text:new()
    self.panel:AddChild(self.progressText)
    local monoFont = cache:GetResource("Font", "Fonts/FusionPixel-12px-Mono-zh_hans.ttf")
    if monoFont then self.progressText:SetFont(monoFont, 16) else self.progressText:SetStyleAuto(); self.progressText:SetFontSize(16) end
    self.progressText.text = "0 / " .. self.totalCount
    self.progressText:SetAlignment(HA_CENTER, VA_CENTER)
    self.progressText:SetPosition(0, 40)
    self.progressText.color = Color(0.627, 0.627, 0.753, 1.0)  -- PX_TEXT_SEC

    log:Write(LOG_INFO, "[Loading] UI created, " .. self.totalCount .. " resources to load")
end

--- 启动预加载：先尝试异步（DWP），如果资源都在本地则走同步快速路径
function LoadingScene:_startPreload()
    -- 检测是否有资源不在本地（DWP 模式下需要异步下载）
    local missing = {}
    for i, item in ipairs(PRELOAD_ALL) do
        if not cache:Exists(item.path) then
            table.insert(missing, i)
        end
    end

    if #missing > 0 then
        -- DWP 异步模式：逐个异步下载缺失资源
        self.asyncMode = true
        self.asyncPending = #missing
        log:Write(LOG_INFO, "[Loading] DWP async mode: " .. #missing .. " resources to download")
        for _, idx in ipairs(missing) do
            local item = PRELOAD_ALL[idx]
            cache:GetResourceAsync(item.type, item.path, function(res)
                self.asyncPending = self.asyncPending - 1
                self.loadedCount = self.loadedCount + 1
                log:Write(LOG_DEBUG, "[Loading] Async loaded: " .. item.path .. " (remaining: " .. self.asyncPending .. ")")
            end)
        end
        -- 已在本地的资源直接计数（同步加载不耗时）
        self.loadedCount = self.totalCount - #missing
        for i, item in ipairs(PRELOAD_ALL) do
            if cache:Exists(item.path) then
                cache:GetResource(item.type, item.path)
            end
        end
    else
        -- 全部在本地：同步快速路径
        self.asyncMode = false
        log:Write(LOG_INFO, "[Loading] Sync mode: all resources cached locally")
    end
end

--- 每帧调用，更新加载进度
function LoadingScene:update(dt)
    -- 已完成加载，等待延迟帧后回调
    if self.finished then
        if self._delayFrames then
            self._delayFrames = self._delayFrames - 1
            if self._delayFrames <= 0 then
                self._delayFrames = nil
                self:_hide()
                if self.onComplete then
                    self.onComplete()
                end
            end
        end
        return
    end

    if self.asyncMode then
        -- DWP 异步模式：等待所有异步回调完成
        -- 进度 = 已加载数 / 总数
        local progress = self.loadedCount / self.totalCount
        local barW = self.progressBar:GetSize().x
        self.progressFill:SetSize(math.floor(barW * progress), self.progressFill:GetSize().y)
        self.progressText.text = self.loadedCount .. " / " .. self.totalCount

        if self.asyncPending <= 0 then
            self.finished = true
            self.progressText.text = "Complete!"
            log:Write(LOG_INFO, "[Loading] All resources preloaded (async)")
            self._delayFrames = 2
        end
    else
        -- 同步模式：每帧加载多个资源（避免卡顿）
        local batchSize = 4
        for i = 1, batchSize do
            if self.loadedCount >= self.totalCount then
                break
            end
            self.loadedCount = self.loadedCount + 1
            local item = PRELOAD_ALL[self.loadedCount]
            cache:GetResource(item.type, item.path)
        end

        -- 更新进度UI
        local progress = self.loadedCount / self.totalCount
        local barW = self.progressBar:GetSize().x
        self.progressFill:SetSize(math.floor(barW * progress), self.progressFill:GetSize().y)
        self.progressText.text = self.loadedCount .. " / " .. self.totalCount

        -- 加载完成
        if self.loadedCount >= self.totalCount then
            self.finished = true
            self.progressText.text = "Complete!"
            log:Write(LOG_INFO, "[Loading] All resources preloaded (sync)")
            self._delayFrames = 2
        end
    end
end

function LoadingScene:_hide()
    if self.panel then
        self.panel.visible = false
        self.panel:Remove()
        self.panel = nil
    end
end

return LoadingScene
