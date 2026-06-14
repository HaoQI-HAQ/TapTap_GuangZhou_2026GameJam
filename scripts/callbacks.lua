---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- callbacks.lua
-- 全局事件回调注册（引擎事件系统通过函数名调用）
---@diagnostic disable: undefined-global

local M = {}

local G         -- 共享状态
local GameMode  -- game_mode 引用（用于转发逻辑调用）
local PauseUI   -- pause_ui 引用

function M.init(shared, gameMode, pauseUI)
    G = shared
    GameMode = gameMode
    PauseUI = pauseUI
end

function M.register()
    -- ================================================================
    -- 菜单/模式选择
    -- ================================================================
    function HandleMenuShowSelect(eventType, eventData)
        G.menuOverlay:showSelect()
    end

    function HandleModeTest(eventType, eventData)
        G.menuOverlay:hide()
        GameMode.EnterGame("test_room")
    end

    function HandleModeNormal(eventType, eventData)
        G.menuOverlay:hide()
        GameMode.EnterGame("normal_mode")
    end

    function HandleModeEndless(eventType, eventData)
        G.menuOverlay:hide()
        PauseUI.showComingSoon()
    end

    function HandleModeBack(eventType, eventData)
        G.menuOverlay:showTitle()
    end

    function HandleMenuStart(eventType, eventData)
        G.menuOverlay:showSelect()
    end

    function HandleMenuExit(eventType, eventData)
        engine:Exit()
    end

    function HandleBackToMenu(eventType, eventData)
        GameMode.ReturnToMenu()
    end

    -- ================================================================
    -- GM / Boss 测试
    -- ================================================================
    function HandleGMButton(eventType, eventData)
        log:Write(LOG_INFO, "[App] GM button pressed - switching to editor")
        G.editorMode_module.switchToEditor()
    end

    function HandleTestBossSkill(eventType, eventData)
        for _, e in ipairs(G.enemies) do
            if e.isBoss and e:isAlive() then
                e:_startSkill()
                break
            end
        end
    end

    -- ================================================================
    -- UI 虚拟按钮（触屏操作）
    -- ================================================================
    function HandleUILeftPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_LEFT, true)
    end
    function HandleUILeftReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
    end
    function HandleUIRightPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_RIGHT, true)
    end
    function HandleUIRightReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
    end
    function HandleUIJumpPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_JUMP, true)
    end
    function HandleUIJumpReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
    end
    function HandleUIAttackPressed(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_ATTACK, true)
    end
    function HandleUIAttackReleased(eventType, eventData)
        G.inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
    end

    -- ================================================================
    -- 卡牌按钮
    -- ================================================================
    function HandleCardBtn1(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(1)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn2(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(2)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn3(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(3)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn4(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(4)
        if idx then G.cardSystem:useCard(idx) end
    end
    function HandleCardBtn5(eventType, eventData)
        local idx = G.cardUI and G.cardUI:getHandIndex(5)
        if idx then G.cardSystem:useCard(idx) end
    end

    -- ================================================================
    -- 面板按钮
    -- ================================================================
    function HandleComingSoonBack(eventType, eventData)
        if G.comingSoonPanel then G.comingSoonPanel.visible = false end
        G.menuOverlay:show()
    end

    function HandlePauseBack(eventType, eventData)
        PauseUI.resume()
    end

    function HandlePauseLeave(eventType, eventData)
        PauseUI.resume()
        GameMode.ReturnToMenu()
    end

    -- ================================================================
    -- Restart / Victory 按钮
    -- ================================================================
    function HandleRestart(eventType, eventData)
        GameMode.HandleRestart(eventType, eventData)
    end

    function HandleVictoryMenu(eventType, eventData)
        GameMode.HandleVictoryMenu(eventType, eventData)
    end

    function HandleVictoryRestart(eventType, eventData)
        GameMode.HandleVictoryRestart(eventType, eventData)
    end
end

return M
