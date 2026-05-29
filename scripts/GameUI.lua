-- ============================================================================
-- GameUI 模块 - 游戏内所有 UI（血条、倒计时、按钮、面板）
-- ============================================================================

local UI = require("urhox-libs/UI")

local GameUI = {}
GameUI.__index = GameUI

-- ============================================================================
-- 构造
-- ============================================================================

---@return table
function GameUI.New()
    local self = setmetatable({}, GameUI)
    self.root_ = nil
    self.maxHP_ = 5

    -- 回调（由外部设置）
    self.onAttack = nil     -- function()
    self.onJump = nil       -- function()
    self.onRestart = nil    -- function()
    self.onTouchLeft = nil  -- function(pressed: boolean)
    self.onTouchRight = nil -- function(pressed: boolean)

    return self
end

-- ============================================================================
-- 创建
-- ============================================================================

function GameUI:Create(maxHP)
    self.maxHP_ = maxHP or 5
    self.root_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            self:CreateHPBar(),
            self:CreateCountdownUI(),
            self:CreateRestartButton(),
            self:CreateAttackButton(),
            self:CreateVirtualJoystick(),
            self:CreateJumpButton(),
            self:CreateAttackTip(),
            self:CreateGameOverPanel(),
        }
    }
    UI.SetRoot(self.root_)
end

function GameUI:Destroy()
    UI.SetRoot(nil)
    self.root_ = nil
end

-- ============================================================================
-- UI 组件创建
-- ============================================================================

function GameUI:CreateHPBar()
    local hearts = {}
    for i = 1, self.maxHP_ do
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

function GameUI:CreateCountdownUI()
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

function GameUI:CreateAttackTip()
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

function GameUI:CreateGameOverPanel()
    local self_ = self
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
                        onClick = function(btn)
                            if self_.onRestart then self_.onRestart() end
                        end,
                    },
                },
            },
        },
    }
end

function GameUI:CreateRestartButton()
    local self_ = self
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
        onClick = function(btn)
            if self_.onRestart then self_.onRestart() end
        end,
    }
end

function GameUI:CreateAttackButton()
    local self_ = self
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
        onClick = function(btn)
            if self_.onAttack then self_.onAttack() end
        end,
    }
end

function GameUI:CreateJumpButton()
    local self_ = self
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
            if self_.onJump then self_.onJump() end
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

function GameUI:CreateVirtualJoystick()
    local self_ = self
    return UI.Panel {
        id = "dirButtons",
        position = "absolute",
        bottom = 32,
        left = 24,
        flexDirection = "row",
        gap = 16,
        children = {
            -- 左移
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
                    if self_.onTouchLeft then self_.onTouchLeft(true) end
                    widget:SetBackgroundColor({ 120, 120, 180, 255 })
                end,
                onPointerUp = function(event, widget)
                    if self_.onTouchLeft then self_.onTouchLeft(false) end
                    widget:SetBackgroundColor({ 80, 80, 100, 200 })
                end,
                children = {
                    UI.Label { text = "◀", fontSize = 28, fontColor = { 255, 255, 255, 255 }, pointerEvents = "none" },
                }
            },
            -- 右移
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
                    if self_.onTouchRight then self_.onTouchRight(true) end
                    widget:SetBackgroundColor({ 120, 120, 180, 255 })
                end,
                onPointerUp = function(event, widget)
                    if self_.onTouchRight then self_.onTouchRight(false) end
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
-- 更新方法
-- ============================================================================

function GameUI:UpdateHP(currentHP)
    if not self.root_ then return end
    for i = 1, self.maxHP_ do
        local heart = self.root_:FindById("heart_" .. i)
        if heart then
            if i <= currentHP then
                heart:SetFontColor({ 255, 60, 60, 255 })
            else
                heart:SetFontColor({ 80, 80, 80, 100 })
            end
        end
    end
end

function GameUI:UpdateCountdown(time)
    if not self.root_ then return end
    local label = self.root_:FindById("countdownLabel")
    if label then
        label:SetText(tostring(math.ceil(time)))
    end
end

function GameUI:ShowAttackTip(visible)
    if not self.root_ then return end
    local tip = self.root_:FindById("attackTip")
    if tip then
        tip:SetVisible(visible)
    end
end

function GameUI:ShowGameOver(visible)
    if not self.root_ then return end
    local panel = self.root_:FindById("gameOverPanel")
    if panel then
        panel:SetVisible(visible)
    end
end

return GameUI
