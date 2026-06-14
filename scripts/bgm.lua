---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- BGM 模块：随机循环播放背景音乐
local BGM = {}

-- 曲目列表
local tracks = {
    "Music/bgm_01.mp3",
    "Music/bgm_02.mp3",
}

---@type SoundSource
local musicSource = nil
local currentIndex = 0
local initialized = false

--- 初始化 BGM 系统（在场景创建后调用一次）
---@param scene Scene
function BGM.init(scene)
    if initialized then return end
    initialized = true

    local musicNode = scene:CreateChild("BGMNode")
    musicSource = musicNode:CreateComponent("SoundSource")
    musicSource:SetSoundType(SOUND_MUSIC)

    BGM.playRandom()
    log:Write(LOG_INFO, "[BGM] Initialized with " .. #tracks .. " tracks")
end

--- 随机选择一首（避免连续重复）并播放
function BGM.playRandom()
    if not musicSource then return end

    local nextIndex = currentIndex
    if #tracks > 1 then
        while nextIndex == currentIndex do
            nextIndex = math.random(1, #tracks)
        end
    else
        nextIndex = 1
    end
    currentIndex = nextIndex

    local sound = cache:GetResource("Sound", tracks[currentIndex])
    if sound then
        sound.looped = false  -- 单曲不循环，播完后切换下一首
        musicSource:Play(sound)
        log:Write(LOG_INFO, "[BGM] Playing: " .. tracks[currentIndex])
    else
        log:Write(LOG_WARNING, "[BGM] Failed to load: " .. tracks[currentIndex])
    end
end

--- 每帧检查是否播放完毕，播完则切下一首（在 Update 中调用）
function BGM.update()
    if not musicSource then return end
    if not musicSource.playing then
        BGM.playRandom()
    end
end

--- 停止播放
function BGM.stop()
    if musicSource then
        musicSource:Stop()
    end
end

--- 暂停/恢复
function BGM.setPaused(paused)
    if not musicSource then return end
    if paused then
        musicSource:Stop()
    else
        if not musicSource.playing then
            BGM.playRandom()
        end
    end
end

return BGM
