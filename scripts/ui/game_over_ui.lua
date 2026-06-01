-- ui/game_over_ui.lua
-- Game Over CG 界面创建与动画
---@diagnostic disable: undefined-global

local ScreenUtils = require("scripts/screen_utils")

local M = {}

local G  -- 由 game_mode 注入

-- 动画常量
local BLACK_DURATION = 3.5    -- 黑屏持续秒数
local FADEIN_DURATION = 1.5   -- CG淡入持续秒数

function M.init(shared)
    G = shared
end

-- ============================================================================
-- 创建 Game Over UI 元素
-- ============================================================================
function M.create()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    -- Game Over 背景图列表（每次死亡随机选一张）
    G.gameOverBGs = {
        "image/cg_gameover_G_20260531032355.png",
        "image/cg_gameover_F_20260531032401.png",
    }

    G.gameOverContainer = UIElement:new()
    uiRoot:AddChild(G.gameOverContainer)
    G.gameOverContainer:SetSize(sw, sh)
    G.gameOverContainer:SetAlignment(HA_LEFT, VA_TOP)
    G.gameOverContainer:SetPosition(0, 0)
    G.gameOverContainer.priority = 900

    -- 全黑背景遮罩
    local blackBg = BorderImage:new()
    G.gameOverContainer:AddChild(blackBg)
    blackBg:SetStyleAuto()
    blackBg:SetSize(sw, sh)
    blackBg:SetPosition(0, 0)
    blackBg:SetAlignment(HA_LEFT, VA_TOP)
    blackBg.color = Color(0, 0, 0, 1.0)
    blackBg.opacity = 1.0
    blackBg.priority = -2

    -- CG背景图
    G.gameOverBgSprite = BorderImage:new()
    G.gameOverContainer:AddChild(G.gameOverBgSprite)
    G.gameOverBgSprite:SetSize(sw, sh)
    G.gameOverBgSprite:SetPosition(0, 0)
    G.gameOverBgSprite:SetAlignment(HA_LEFT, VA_TOP)
    G.gameOverBgSprite.priority = 0
    G.gameOverBgSprite.opacity = 0.0
    G.gameOverBgSprite.blendMode = BLEND_ALPHA
    -- 预加载第一张纹理
    local preTex = cache:GetResource("Texture2D", G.gameOverBGs[1])
    if preTex then
        G.gameOverBgSprite:SetTexture(preTex)
        G.gameOverBgSprite:SetImageRect(IntRect(0, 0, preTex:GetWidth(), preTex:GetHeight()))
    end

    -- 返回菜单按钮
    G.gameOverRestartBtn = Button:new()
    G.gameOverContainer:AddChild(G.gameOverRestartBtn)
    G.gameOverRestartBtn:SetStyleAuto()
    G.gameOverRestartBtn:SetSize(S(160), S(50))
    G.gameOverRestartBtn:SetAlignment(HA_CENTER, VA_CENTER)
    G.gameOverRestartBtn:SetPosition(0, S(40))

    local btnText = Text:new()
    G.gameOverRestartBtn:AddChild(btnText)
    btnText:SetStyleAuto()
    btnText.text = "返回菜单"
    btnText:SetFontSize(S(22))
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.gameOverRestartBtn, "Released", "HandleRestart")

    G.gameOverRestartBtn.visible = false
    G.gameOverContainer.visible = false
end

-- ============================================================================
-- 显示 Game Over
-- ============================================================================
function M.show()
    if G.gameOverContainer then
        if G.gameOverContainer.visible then return end

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()
        G.gameOverContainer:SetSize(sw, sh)

        -- 随机选择背景图
        if G.gameOverBGs and G.gameOverBgSprite then
            local idx = math.random(1, #G.gameOverBGs)
            local tex = cache:GetResource("Texture2D", G.gameOverBGs[idx])
            if tex then
                G.gameOverBgSprite:SetTexture(tex)
                G.gameOverBgSprite:SetImageRect(IntRect(0, 0, tex:GetWidth(), tex:GetHeight()))
            end
        end

        -- 初始状态：黑屏，CG隐藏
        G.gameOverBgSprite.opacity = 0.0
        G.gameOverBgSprite:SetSize(0, 0)
        G.gameOverContainer.visible = true

        -- 启动动画状态机
        G.gameOverPhase = "blackscreen"
        G.gameOverTimer = 0.0
    end

    -- 冻结游戏
    G.physicsWorld_.enabled = false
    G.gamePaused = false
    if G.pausePanel then G.pausePanel.visible = false end
    G.gameUI:hide()
    G.cardUI:hide()
    for _, e in ipairs(G.enemies) do
        e:hideHpBar()
    end
end

-- ============================================================================
-- 动画更新（每帧调用）
-- ============================================================================
function M.updateAnim(dt)
    if not G.gameOverPhase then return end

    G.gameOverTimer = G.gameOverTimer + dt

    if G.gameOverPhase == "blackscreen" then
        if G.gameOverTimer >= BLACK_DURATION then
            G.gameOverPhase = "fadein"
            G.gameOverTimer = 0.0
        end
    elseif G.gameOverPhase == "fadein" then
        local progress = math.min(G.gameOverTimer / FADEIN_DURATION, 1.0)
        local eased = 1.0 - (1.0 - progress) * (1.0 - progress)

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()

        -- 从 60% 缩放到 100%
        local scale = 0.6 + 0.4 * eased
        local imgW = math.floor(sw * scale)
        local imgH = math.floor(sh * scale)
        local posX = math.floor((sw - imgW) / 2)
        local posY = math.floor((sh - imgH) / 2)

        G.gameOverBgSprite:SetSize(imgW, imgH)
        G.gameOverBgSprite:SetPosition(posX, posY)
        G.gameOverBgSprite.opacity = eased

        if progress >= 1.0 then
            G.gameOverPhase = "done"
            G.gameOverBgSprite:SetSize(sw, sh)
            G.gameOverBgSprite:SetPosition(0, 0)
            G.gameOverBgSprite.opacity = 1.0
            if G.gameOverRestartBtn then
                G.gameOverRestartBtn.visible = true
            end
        end
    end
end

-- ============================================================================
-- 隐藏/重置
-- ============================================================================
function M.hide()
    G.gameOverPhase = nil
    G.gameOverTimer = nil
    if G.gameOverRestartBtn then G.gameOverRestartBtn.visible = false end
    if G.gameOverContainer then G.gameOverContainer.visible = false end
end

return M
