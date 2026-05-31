-- 传送门读条UI：显示传送进度条和提示文字
local PortalUI = {}
PortalUI.__index = PortalUI

function PortalUI:new()
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, PortalUI)
    self.container = nil
    self.barBg = nil
    self.barFill = nil
    self.hintText = nil
    self.portalHint = nil  -- "进入传送门"提示（靠近传送门时显示）
    self.visible = false
    self:_create()
    return self
end

function PortalUI:_create()
    local uiRoot = ui.root
    local w = uiRoot.width
    local h = uiRoot.height

    -- 读条容器（屏幕中央偏下）
    self.container = UIElement:new()
    uiRoot:AddChild(self.container)
    self.container:SetSize(300, 60)
    self.container:SetAlignment(HA_CENTER, VA_CENTER)
    self.container:SetPosition(0, 80)
    self.container.priority = 850

    -- 提示文字
    self.hintText = Text:new()
    self.container:AddChild(self.hintText)
    self.hintText:SetStyleAuto()
    self.hintText.text = "传送中..."
    self.hintText:SetFontSize(18)
    self.hintText:SetAlignment(HA_CENTER, VA_TOP)
    self.hintText:SetPosition(0, 0)
    self.hintText.color = Color(0.9, 0.9, 1.0, 1.0)

    -- 进度条背景
    self.barBg = BorderImage:new()
    self.container:AddChild(self.barBg)
    self.barBg:SetSize(260, 20)
    self.barBg:SetAlignment(HA_CENTER, VA_TOP)
    self.barBg:SetPosition(0, 28)
    self.barBg.color = Color(0.1, 0.1, 0.2, 0.8)

    -- 进度条填充
    self.barFill = BorderImage:new()
    self.container:AddChild(self.barFill)
    self.barFill:SetSize(0, 16)
    self.barFill:SetAlignment(HA_LEFT, VA_TOP)
    self.barFill:SetPosition(20, 30)  -- barBg起始 + 2px padding
    self.barFill.color = Color(0.3, 0.7, 1.0, 1.0)

    -- 默认隐藏
    self.container.visible = false

    -- === 传送门激活提示（屏幕上方） ===
    self.portalHint = Text:new()
    uiRoot:AddChild(self.portalHint)
    self.portalHint:SetStyleAuto()
    self.portalHint.text = ">> 所有敌人已击败！前往右侧传送门进入下一关 >>"
    self.portalHint:SetFontSize(16)
    self.portalHint:SetAlignment(HA_CENTER, VA_TOP)
    self.portalHint:SetPosition(0, 60)
    self.portalHint.color = Color(0.4, 0.8, 1.0, 1.0)
    self.portalHint.priority = 850
    self.portalHint.visible = false
end

--- 显示传送门激活提示
function PortalUI:showPortalHint()
    if self.portalHint then
        self.portalHint.text = ">> 所有敌人已击败！前往右侧传送门进入下一关 >>"
        self.portalHint.color = Color(0.4, 0.8, 1.0, 1.0)
        self.portalHint.visible = true
        self._portalActivated = true
        self._notClearedTimer = nil
    end
end

--- 隐藏传送门激活提示
function PortalUI:hidePortalHint()
    if self.portalHint then
        self.portalHint.visible = false
    end
end

--- 显示读条UI
function PortalUI:showCharging()
    if self.container then
        self.container.visible = true
    end
    self.visible = true
end

--- 隐藏读条UI
function PortalUI:hideCharging()
    if self.container then
        self.container.visible = false
    end
    self.visible = false
    -- 重置进度条
    if self.barFill then
        self.barFill:SetSize(0, 16)
    end
end

--- 更新进度条（progress: 0~1）
function PortalUI:setProgress(progress)
    if self.barFill then
        local maxWidth = 256  -- 260 - 4px padding
        local fillWidth = math.floor(maxWidth * progress)
        self.barFill:SetSize(fillWidth, 16)

        -- 颜色从蓝色渐变到白色
        local r = 0.3 + 0.7 * progress
        local g = 0.7 + 0.3 * progress
        local b = 1.0
        self.barFill.color = Color(r, g, b, 1.0)
    end

    if self.hintText then
        local pct = math.floor(progress * 100)
        self.hintText.text = "传送中... " .. pct .. "%"
    end
end

--- 显示传送完成效果
function PortalUI:showComplete()
    if self.hintText then
        self.hintText.text = "传送完成！"
        self.hintText.color = Color(1.0, 1.0, 0.5, 1.0)
    end
end

--- 显示通关提示（击败最终Boss后）
function PortalUI:showGameComplete()
    if self.portalHint then
        self.portalHint.text = "★ 恭喜通关！所有关卡已完成 ★"
        self.portalHint.color = Color(1.0, 0.85, 0.0, 1.0)
        self.portalHint.visible = true
        self.portalHint:SetFontSize(22)
        self._portalActivated = true  -- 防止被自动隐藏
    end
    -- 隐藏读条容器
    if self.container then
        self.container.visible = false
    end
end

--- 显示"需要击败所有敌人"提示（自动3秒后消失）
function PortalUI:showEnemiesNotCleared()
    if self.portalHint then
        self.portalHint.text = "!! 需要击败所有敌人才能传送 !!"
        self.portalHint.color = Color(1.0, 0.4, 0.3, 1.0)
        self.portalHint.visible = true
        self._notClearedTimer = 3.0
    end
end

--- 更新（用于自动隐藏提示）
function PortalUI:update(dt)
    if self._notClearedTimer and self._notClearedTimer > 0 then
        self._notClearedTimer = self._notClearedTimer - dt
        if self._notClearedTimer <= 0 then
            self._notClearedTimer = nil
            if self.portalHint and not self._portalActivated then
                self.portalHint.visible = false
            end
        end
    end
end

--- 销毁UI
function PortalUI:destroy()
    if self.container then
        self.container:Remove()
        self.container = nil
    end
    if self.portalHint then
        self.portalHint:Remove()
        self.portalHint = nil
    end
    log:Write(LOG_INFO, "[PortalUI] Destroyed")
end

return PortalUI
