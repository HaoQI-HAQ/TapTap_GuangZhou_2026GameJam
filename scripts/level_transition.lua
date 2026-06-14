---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- level_transition.lua
-- 关卡过渡：状态保存、切换、恢复
---@diagnostic disable: undefined-global, param-type-mismatch, assign-type-mismatch

local ScreenUtils = require("scripts/screen_utils")

local M = {}

local G  -- 由 game_mode 注入

function M.init(shared)
    G = shared
end

-- ============================================================================
-- 关卡过渡调度
-- ============================================================================
function M.scheduleLevelTransition(nextLevel)
    G.transitionTimer = 0.5
    G.transitionTarget = nextLevel
end

function M.scheduleReturnToMenu(delay)
    G.returnToMenuTimer = delay or 3.0
end

-- ============================================================================
-- 执行关卡切换（需要外部传入场景重建回调）
-- ============================================================================

--- 保存当前关卡状态（HP、五感剥夺等）
function M.saveState()
    local state = {}
    state.hp = G.player and G.player:getHp() or nil

    if G.sensesSystem then
        state.senses = {
            deprived = {},
            deprivedCount = G.sensesSystem.deprivedCount or 0,
            driftEnabled = G.sensesSystem.driftEnabled,
            driftOffset = G.sensesSystem.driftOffset,
            uiDistortEnabled = G.sensesSystem.uiDistortEnabled,
            trapWarningHidden = G.sensesSystem.trapWarningHidden,
            timerGlitch = G.sensesSystem.timerGlitch,
            audioMuted = G.sensesSystem.audioMuted,
            visionFading = G.sensesSystem.visionFading,
            visionFadeAlpha = G.sensesSystem.visionFadeAlpha,
        }
        for k, v in pairs(G.sensesSystem.deprived) do
            state.senses.deprived[k] = v
        end
    end

    return state
end

--- 恢复关卡状态
function M.restoreState(state, nextLevel)
    if nextLevel >= 4 then
        -- 第4关及以后重置五感状态
        if G.gameUI then G.gameUI:updateSensesIcons() end
    else
        if state.hp and G.player then
            G.player.hp = state.hp
        end
        if state.senses and G.sensesSystem then
            G.sensesSystem.deprived = state.senses.deprived
            G.sensesSystem.deprivedCount = state.senses.deprivedCount
            G.sensesSystem.driftEnabled = state.senses.driftEnabled
            G.sensesSystem.driftOffset = state.senses.driftOffset
            G.sensesSystem.uiDistortEnabled = state.senses.uiDistortEnabled
            G.sensesSystem.trapWarningHidden = state.senses.trapWarningHidden
            G.sensesSystem.timerGlitch = state.senses.timerGlitch
            G.sensesSystem.audioMuted = state.senses.audioMuted
            G.sensesSystem.visionFading = state.senses.visionFading
            G.sensesSystem.visionFadeAlpha = state.senses.visionFadeAlpha
            if state.senses.audioMuted then
                audio:SetMasterGain("Effect", 0.0)
            end
        end
        if G.gameUI then G.gameUI:updateSensesIcons() end
    end
end

--- 关卡切换后的通用初始化
function M.postTransitionSetup()
    G.cameraNode.position = Vector3(0, -1.9, -10)
    G.physicsWorld_.enabled = true
    G.scene_.updateEnabled = true
    G.gamePaused = false
    G.gameUI:show()
    G.gameUI:resetCountdown()
    G.cardSystem:reset()
    G.cardSkills:reset()
    G.cardUI:show()
end

--- 检查并执行定时器（在 gameUpdate 中调用）
--- @return boolean 如果触发了过渡则返回 true
function M.checkTimers(dt, doTransitionCallback, restartCallback)
    if G.transitionTimer then
        G.transitionTimer = G.transitionTimer - dt
        if G.transitionTimer <= 0 then
            local target = G.transitionTarget
            G.transitionTimer = nil
            G.transitionTarget = nil
            doTransitionCallback(target)
            return true
        end
    end

    if G.returnToMenuTimer then
        G.returnToMenuTimer = G.returnToMenuTimer - dt
        if G.returnToMenuTimer <= 0 then
            G.returnToMenuTimer = nil
            restartCallback()
            return true
        end
    end

    return false
end

return M
