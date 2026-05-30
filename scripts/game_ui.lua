-- ============================================================================
-- GameUI 模块：游戏 HUD (urhox-libs/UI 系统)
-- 包含: HP心/卡牌手牌/倒计时/连击/五感/触摸控制
-- ============================================================================

local UI = require("urhox-libs/UI")
local CONFIG = require("config")
local InputManager = require("input_manager")

local GameUI = {}
GameUI.__index = GameUI

function GameUI.new(_, inputMgr)
    local self = setmetatable({}, GameUI)
    self.inputMgr = inputMgr
    self.root = nil
    return self
end

function GameUI:build()
    self.root = UI.Panel {
        id = "gameHUD",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部状态栏(HP + 连击 + 五感)
            self:_buildTopBar(),
            -- 底部卡牌区域
            self:_buildCardArea(),
            -- 触摸控制按钮(移动端)
            self:_buildTouchControls(),
        }
    }
    UI.SetRoot(self.root)
end

-- ========== 顶部状态栏 ==========

function GameUI:_buildTopBar()
    return UI.Panel {
        id = "topBar",
        position = "absolute",
        top = 12,
        left = 12,
        right = 12,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "flex-start",
        pointerEvents = "none",
        children = {
            -- 左侧: HP
            UI.Panel {
                id = "hpPanel",
                flexDirection = "row",
                gap = 4,
                children = self:_buildHearts(CONFIG.MaxHP),
            },
            -- 中间: 倒计时
            UI.Panel {
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "countdownLabel",
                        text = "5.0",
                        fontSize = 24,
                        fontColor = { 255, 220, 50, 255 },
                    },
                    UI.Label {
                        id = "roundLabel",
                        text = "R1",
                        fontSize = 11,
                        fontColor = { 180, 180, 180, 200 },
                    },
                }
            },
            -- 右侧: 连击 + 五感
            UI.Panel {
                alignItems = "flex-end",
                gap = 4,
                children = {
                    UI.Label {
                        id = "comboLabel",
                        text = "",
                        fontSize = 16,
                        fontColor = { 255, 150, 50, 255 },
                    },
                    UI.Label {
                        id = "senseLabel",
                        text = "",
                        fontSize = 12,
                        fontColor = { 200, 100, 100, 200 },
                    },
                }
            },
        }
    }
end

function GameUI:_buildHearts(count)
    local hearts = {}
    for i = 1, count do
        hearts[i] = UI.Label {
            id = "heart_" .. i,
            text = "♥",
            fontSize = 20,
            fontColor = { 220, 50, 50, 255 },
        }
    end
    return hearts
end

-- ========== 卡牌区域 ==========

function GameUI:_buildCardArea()
    return UI.Panel {
        id = "cardArea",
        position = "absolute",
        bottom = 80,
        left = 0,
        right = 0,
        alignItems = "center",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                id = "cardHand",
                flexDirection = "row",
                gap = 6,
                pointerEvents = "auto",
                children = self:_buildCardSlots(CONFIG.CardHandSize),
            }
        }
    }
end

function GameUI:_buildCardSlots(count)
    local slots = {}
    for i = 1, count do
        slots[i] = UI.Panel {
            id = "card_" .. i,
            width = 48,
            height = 64,
            backgroundColor = { 40, 45, 60, 220 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { 100, 110, 140, 150 },
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    id = "cardIcon_" .. i,
                    text = "?",
                    fontSize = 20,
                },
                UI.Label {
                    id = "cardDmg_" .. i,
                    text = "",
                    fontSize = 10,
                    fontColor = { 200, 200, 200, 180 },
                },
            },
            onClick = function(self_btn)
                if self.onCardUse then
                    self.onCardUse(i)
                end
            end,
        }
    end
    return slots
end

-- ========== 触摸控制 ==========

function GameUI:_buildTouchControls()
    local btnSize = 52
    local self_ref = self

    return UI.Panel {
        id = "touchControls",
        position = "absolute",
        bottom = 16,
        left = 12,
        right = 12,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "flex-end",
        pointerEvents = "box-none",
        children = {
            -- 左侧: 方向
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                pointerEvents = "auto",
                children = {
                    UI.Button {
                        id = "btnLeft",
                        text = "◀",
                        width = btnSize,
                        height = btnSize,
                        onPressIn = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_LEFT, true) end,
                        onPressOut = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_LEFT, false) end,
                    },
                    UI.Button {
                        id = "btnRight",
                        text = "▶",
                        width = btnSize,
                        height = btnSize,
                        onPressIn = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_RIGHT, true) end,
                        onPressOut = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_RIGHT, false) end,
                    },
                }
            },
            -- 右侧: 跳跃/攻击/下砸
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                pointerEvents = "auto",
                children = {
                    UI.Button {
                        id = "btnSlam",
                        text = "▼",
                        width = btnSize,
                        height = btnSize,
                        onPressIn = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_SLAM, true) end,
                        onPressOut = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_SLAM, false) end,
                    },
                    UI.Button {
                        id = "btnAttack",
                        text = "⚔",
                        width = btnSize,
                        height = btnSize,
                        onPressIn = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_ATTACK, true) end,
                        onPressOut = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_ATTACK, false) end,
                    },
                    UI.Button {
                        id = "btnJump",
                        text = "▲",
                        width = btnSize,
                        height = btnSize,
                        onPressIn = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_JUMP, true) end,
                        onPressOut = function() self_ref.inputMgr:setTouchAction(InputManager.ACTION_JUMP, false) end,
                    },
                }
            },
        }
    }
end

-- ========== 更新函数 ==========

function GameUI:updateHP(currentHP, maxHP)
    if not self.root then return end
    for i = 1, maxHP do
        local heart = self.root:FindById("heart_" .. i)
        if heart then
            if i <= currentHP then
                heart:SetText("♥")
                heart:SetFontColor({ 220, 50, 50, 255 })
            else
                heart:SetText("♡")
                heart:SetFontColor({ 80, 80, 80, 150 })
            end
        end
    end
end

function GameUI:updateCountdown(time, round)
    if not self.root then return end
    local label = self.root:FindById("countdownLabel")
    if label then
        label:SetText(string.format("%.1f", math.max(0, time)))
        -- 最后2秒变红
        if time <= 2.0 then
            label:SetFontColor({ 255, 80, 80, 255 })
        else
            label:SetFontColor({ 255, 220, 50, 255 })
        end
    end
    local rLabel = self.root:FindById("roundLabel")
    if rLabel then
        rLabel:SetText("R" .. tostring(round or 1))
    end
end

function GameUI:updateCards(hand)
    if not self.root then return end
    for i = 1, CONFIG.CardHandSize do
        local cardPanel = self.root:FindById("card_" .. i)
        local iconLabel = self.root:FindById("cardIcon_" .. i)
        local dmgLabel = self.root:FindById("cardDmg_" .. i)

        if cardPanel then
            if hand[i] then
                local card = hand[i]
                cardPanel:SetVisible(true)
                if iconLabel then
                    if card.element and CONFIG.ElementIcons[card.element] then
                        iconLabel:SetText(CONFIG.ElementIcons[card.element])
                    elseif card.type == "none_atk" then
                        iconLabel:SetText("⚔")
                    elseif card.type == "matter" then
                        iconLabel:SetText("💎")
                    else
                        iconLabel:SetText("?")
                    end
                end
                if dmgLabel then
                    dmgLabel:SetText(tostring(card.baseDamage))
                end
                -- 属性边框色
                if card.element and CONFIG.ElementColors[card.element] then
                    local c = CONFIG.ElementColors[card.element]
                    cardPanel:SetBorderColor({ c[1], c[2], c[3], 200 })
                else
                    cardPanel:SetBorderColor({ 100, 110, 140, 150 })
                end
            else
                cardPanel:SetVisible(false)
            end
        end
    end
end

function GameUI:updateCombo(step)
    if not self.root then return end
    local label = self.root:FindById("comboLabel")
    if label then
        if step > 0 then
            label:SetText("COMBO x" .. tostring(step))
        else
            label:SetText("")
        end
    end
end

function GameUI:updateSenses(lostSenses)
    if not self.root then return end
    local label = self.root:FindById("senseLabel")
    if label then
        if #lostSenses > 0 then
            local names = { hearing = "听觉", touch = "触觉", taste = "味觉", smell = "嗅觉" }
            local texts = {}
            for _, s in ipairs(lostSenses) do
                texts[#texts + 1] = (names[s] or s) .. "✗"
            end
            label:SetText(table.concat(texts, " "))
        else
            label:SetText("")
        end
    end
end

-- 设置卡牌使用回调
function GameUI:setOnCardUse(fn)
    self.onCardUse = fn
end

return GameUI
