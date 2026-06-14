---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- ui/victory_ui.lua
-- 胜利 CG 界面创建与动画
---@diagnostic disable: undefined-global, param-type-mismatch, assign-type-mismatch

local ScreenUtils = require("scripts/screen_utils")

local M = {}

local G  -- 由 game_mode 注入

-- 动画常量
local BLACK_DURATION = 2.0    -- 黑屏持续秒数
local FADEIN_DURATION = 1.5   -- CG淡入持续秒数

-- 胜利CG图路径
local VICTORY_CG_PATH = "image/edited_victory_boss_killed_clean_20260601152842.png"

function M.init(shared)
    G = shared
end

-- ============================================================================
-- 创建 Victory UI 元素
-- ============================================================================
function M.create()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.victoryContainer = UIElement:new()
    uiRoot:AddChild(G.victoryContainer)
    G.victoryContainer:SetSize(sw, sh)
    G.victoryContainer:SetAlignment(HA_LEFT, VA_TOP)
    G.victoryContainer:SetPosition(0, 0)
    G.victoryContainer.priority = 910

    -- 全黑背景
    local blackBg = BorderImage:new()
    G.victoryContainer:AddChild(blackBg)
    blackBg:SetStyleAuto()
    blackBg:SetSize(sw, sh)
    blackBg:SetPosition(0, 0)
    blackBg:SetAlignment(HA_LEFT, VA_TOP)
    blackBg.color = Color(0, 0, 0, 1.0)
    blackBg.opacity = 1.0
    blackBg.priority = -2

    -- 胜利CG图
    G.victoryBgSprite = BorderImage:new()
    G.victoryContainer:AddChild(G.victoryBgSprite)
    G.victoryBgSprite:SetSize(sw, sh)
    G.victoryBgSprite:SetPosition(0, 0)
    G.victoryBgSprite:SetAlignment(HA_LEFT, VA_TOP)
    G.victoryBgSprite.priority = 0
    G.victoryBgSprite.opacity = 0.0
    G.victoryBgSprite.blendMode = BLEND_ALPHA
    local victoryTex = cache:GetResource("Texture2D", VICTORY_CG_PATH)
    if victoryTex then
        G.victoryBgSprite:SetTexture(victoryTex)
        G.victoryBgSprite:SetImageRect(IntRect(0, 0, victoryTex:GetWidth(), victoryTex:GetHeight()))
    end

    -- 返回主菜单按钮（左边中间）
    G.victoryMenuBtn = Button:new()
    G.victoryContainer:AddChild(G.victoryMenuBtn)
    G.victoryMenuBtn:SetStyleAuto()
    G.victoryMenuBtn:SetSize(S(160), S(50))
    G.victoryMenuBtn:SetAlignment(HA_LEFT, VA_CENTER)
    G.victoryMenuBtn:SetPosition(S(60), 0)
    G.victoryMenuBtn.priority = 10

    local menuBtnText = Text:new()
    G.victoryMenuBtn:AddChild(menuBtnText)
    menuBtnText:SetStyleAuto()
    menuBtnText.text = "回主菜单"
    menuBtnText:SetFontSize(S(20))
    menuBtnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.victoryMenuBtn, "Released", "HandleVictoryMenu")

    -- 重开按钮（右边中间）
    G.victoryRestartBtn = Button:new()
    G.victoryContainer:AddChild(G.victoryRestartBtn)
    G.victoryRestartBtn:SetStyleAuto()
    G.victoryRestartBtn:SetSize(S(160), S(50))
    G.victoryRestartBtn:SetAlignment(HA_RIGHT, VA_CENTER)
    G.victoryRestartBtn:SetPosition(S(-60), 0)
    G.victoryRestartBtn.priority = 10

    local restartBtnText = Text:new()
    G.victoryRestartBtn:AddChild(restartBtnText)
    restartBtnText:SetStyleAuto()
    restartBtnText.text = "重新开始"
    restartBtnText:SetFontSize(S(20))
    restartBtnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(G.victoryRestartBtn, "Released", "HandleVictoryRestart")

    -- 初始隐藏
    G.victoryMenuBtn.visible = false
    G.victoryRestartBtn.visible = false
    G.victoryContainer.visible = false
end

-- ============================================================================
-- 显示胜利CG
-- ============================================================================
function M.show()
    if G.victoryContainer then
        if G.victoryContainer.visible then return end

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()
        G.victoryContainer:SetSize(sw, sh)

        -- 重新加载纹理
        if G.victoryBgSprite then
            local tex = cache:GetResource("Texture2D", VICTORY_CG_PATH)
            if tex then
                G.victoryBgSprite:SetTexture(tex)
                G.victoryBgSprite:SetImageRect(IntRect(0, 0, tex:GetWidth(), tex:GetHeight()))
            end
        end

        -- 初始状态：黑屏
        G.victoryBgSprite.opacity = 0.0
        G.victoryBgSprite:SetSize(0, 0)
        G.victoryContainer.visible = true

        -- 启动动画状态机
        G.victoryPhase = "blackscreen"
        G.victoryTimer = 0.0
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
    if not G.victoryPhase then return end

    G.victoryTimer = G.victoryTimer + dt

    if G.victoryPhase == "blackscreen" then
        if G.victoryTimer >= BLACK_DURATION then
            G.victoryPhase = "fadein"
            G.victoryTimer = 0.0
        end
    elseif G.victoryPhase == "fadein" then
        local progress = math.min(G.victoryTimer / FADEIN_DURATION, 1.0)
        local eased = 1.0 - (1.0 - progress) * (1.0 - progress)

        local sw = ScreenUtils.width()
        local sh = ScreenUtils.height()

        local scale = 0.6 + 0.4 * eased
        local imgW = math.floor(sw * scale)
        local imgH = math.floor(sh * scale)
        local posX = math.floor((sw - imgW) / 2)
        local posY = math.floor((sh - imgH) / 2)

        G.victoryBgSprite:SetSize(imgW, imgH)
        G.victoryBgSprite:SetPosition(posX, posY)
        G.victoryBgSprite.opacity = eased

        if progress >= 1.0 then
            G.victoryPhase = "done"
            G.victoryBgSprite:SetSize(sw, sh)
            G.victoryBgSprite:SetPosition(0, 0)
            G.victoryBgSprite.opacity = 1.0
            if G.victoryMenuBtn then G.victoryMenuBtn.visible = true end
            if G.victoryRestartBtn then G.victoryRestartBtn.visible = true end
        end
    end
end

-- ============================================================================
-- 隐藏/重置
-- ============================================================================
function M.hide()
    G.victoryPhase = nil
    G.victoryTimer = nil
    if G.victoryMenuBtn then G.victoryMenuBtn.visible = false end
    if G.victoryRestartBtn then G.victoryRestartBtn.visible = false end
    if G.victoryContainer then G.victoryContainer.visible = false end
end

return M
