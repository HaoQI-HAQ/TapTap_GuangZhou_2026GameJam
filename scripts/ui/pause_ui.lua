---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- ui/pause_ui.lua
-- 暂停面板和 ComingSoon 面板
---@diagnostic disable: undefined-global, param-type-mismatch, assign-type-mismatch

local ScreenUtils = require("scripts/screen_utils")

local M = {}

local G  -- 由 game_mode 注入

function M.init(shared)
    G = shared
end

-- ============================================================================
-- 暂停面板
-- ============================================================================
function M.createPausePanel()
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.pausePanel = UIElement:new()
    uiRoot:AddChild(G.pausePanel)
    G.pausePanel:SetSize(sw, sh)
    G.pausePanel:SetAlignment(HA_CENTER, VA_CENTER)
    G.pausePanel.priority = 1000

    local bg = BorderImage:new()
    G.pausePanel:AddChild(bg)
    bg:SetSize(sw, sh)
    bg:SetPosition(0, 0)
    bg.color = Color(0, 0, 0, 0.7)

    local title = Text:new()
    G.pausePanel:AddChild(title)
    title:SetStyleAuto()
    title.text = "PAUSED"
    title:SetFontSize(S(36))
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, S(-60))
    title.color = Color(1.0, 1.0, 1.0, 1.0)

    local btnBack = Button:new()
    G.pausePanel:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(S(180), S(55))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(10))

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "Back"
    backText:SetFontSize(S(24))
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandlePauseBack")

    local btnLeave = Button:new()
    G.pausePanel:AddChild(btnLeave)
    btnLeave:SetStyleAuto()
    btnLeave:SetSize(S(180), S(55))
    btnLeave:SetAlignment(HA_CENTER, VA_CENTER)
    btnLeave:SetPosition(0, S(80))

    local leaveText = Text:new()
    btnLeave:AddChild(leaveText)
    leaveText:SetStyleAuto()
    leaveText.text = "Leave"
    leaveText:SetFontSize(S(24))
    leaveText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnLeave, "Released", "HandlePauseLeave")

    G.pausePanel.visible = false
end

-- ============================================================================
-- ComingSoon 面板
-- ============================================================================
function M.showComingSoon()
    if G.comingSoonPanel then
        G.comingSoonPanel.visible = true
        return
    end
    local uiRoot = ui.root
    local S = ScreenUtils.s
    local sw = ScreenUtils.width()
    local sh = ScreenUtils.height()

    G.comingSoonPanel = UIElement:new()
    uiRoot:AddChild(G.comingSoonPanel)
    G.comingSoonPanel:SetSize(sw, sh)
    G.comingSoonPanel:SetAlignment(HA_CENTER, VA_CENTER)
    G.comingSoonPanel:SetPriority(1100)

    local bg = BorderImage:new()
    G.comingSoonPanel:AddChild(bg)
    bg:SetSize(sw, sh)
    bg:SetPosition(0, 0)
    bg.color = Color(0.95, 0.95, 0.98, 1.0)

    local msg = Text:new()
    G.comingSoonPanel:AddChild(msg)
    msg:SetStyleAuto()
    msg.text = "未开发请敬请期待"
    msg:SetFontSize(S(28))
    msg:SetAlignment(HA_CENTER, VA_CENTER)
    msg:SetPosition(0, S(-30))
    msg.color = Color(0.3, 0.3, 0.4, 1.0)

    local btnBack = Button:new()
    G.comingSoonPanel:AddChild(btnBack)
    btnBack:SetStyleAuto()
    btnBack:SetSize(S(160), S(50))
    btnBack:SetAlignment(HA_CENTER, VA_CENTER)
    btnBack:SetPosition(0, S(40))

    local backText = Text:new()
    btnBack:AddChild(backText)
    backText:SetStyleAuto()
    backText.text = "返回"
    backText:SetFontSize(S(22))
    backText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(btnBack, "Released", "HandleComingSoonBack")
end

-- ============================================================================
-- 暂停/恢复切换
-- ============================================================================
function M.togglePause()
    if not G.gamePaused then
        G.gamePaused = true
        G.scene_.updateEnabled = false
        if G.pausePanel then G.pausePanel.visible = true end
    else
        M.resume()
    end
end

function M.resume()
    G.gamePaused = false
    G.scene_.updateEnabled = true
    if G.pausePanel then G.pausePanel.visible = false end
end

return M
