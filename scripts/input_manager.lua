-- ============================================================================
-- InputManager：统一管理键盘、触摸按钮、手柄输入
-- 新增: 攻击、下砸动作
-- ============================================================================

local InputManager = {}
InputManager.__index = InputManager

-- 动作定义
InputManager.ACTION_LEFT   = "left"
InputManager.ACTION_RIGHT  = "right"
InputManager.ACTION_JUMP   = "jump"
InputManager.ACTION_ATTACK = "attack"
InputManager.ACTION_SLAM   = "slam"    -- 下砸(下+攻击)

function InputManager:new()
    local self = setmetatable({}, InputManager)

    -- 动作状态(持续按住)
    self.actions = {}
    -- 动作按下瞬间(单帧触发)
    self.actionsPress = {}
    -- 上一帧状态(用于检测Press)
    self.prevActions = {}

    -- 触摸按钮状态
    self.touchActions = {}

    -- 键盘映射
    self.keyboardHoldMap = {
        [KEY_A]     = InputManager.ACTION_LEFT,
        [KEY_LEFT]  = InputManager.ACTION_LEFT,
        [KEY_D]     = InputManager.ACTION_RIGHT,
        [KEY_RIGHT] = InputManager.ACTION_RIGHT,
    }
    self.keyboardPressMap = {
        [KEY_SPACE] = InputManager.ACTION_JUMP,
        [KEY_W]     = InputManager.ACTION_JUMP,
        [KEY_UP]    = InputManager.ACTION_JUMP,
        [KEY_J]     = InputManager.ACTION_ATTACK,
        [KEY_K]     = InputManager.ACTION_ATTACK,
        [KEY_S]     = InputManager.ACTION_SLAM,
        [KEY_DOWN]  = InputManager.ACTION_SLAM,
    }

    self.deadZone = 0.2
    return self
end

function InputManager:setTouchAction(action, active)
    self.touchActions[action] = active
end

function InputManager:update()
    -- 保存上帧状态
    self.prevActions = {}
    for k, v in pairs(self.actions) do
        self.prevActions[k] = v
    end

    -- 重置
    self.actions = {}
    self.actionsPress = {}

    -- 1. 键盘持续按住
    for key, action in pairs(self.keyboardHoldMap) do
        if input:GetKeyDown(key) then
            self.actions[action] = true
        end
    end

    -- 2. 键盘按下瞬间
    for key, action in pairs(self.keyboardPressMap) do
        if input:GetKeyPress(key) then
            self.actionsPress[action] = true
            self.actions[action] = true
        end
        if input:GetKeyDown(key) then
            self.actions[action] = true
        end
    end

    -- 3. 触摸按钮
    for action, active in pairs(self.touchActions) do
        if active then
            self.actions[action] = true
        end
    end

    -- 4. 手柄
    self:_pollGamepad()

    -- 检测Press(当前帧有而上帧没有)
    for action, active in pairs(self.actions) do
        if active and not self.prevActions[action] then
            self.actionsPress[action] = true
        end
    end
end

-- 持续按住判定
function InputManager:isHeld(action)
    return self.actions[action] == true
end

-- 按下瞬间判定(单帧)
function InputManager:isPressed(action)
    return self.actionsPress[action] == true
end

function InputManager:_pollGamepad()
    if input.numJoysticks == 0 then return end
    local js = input:GetJoystickByIndex(0)
    if not js then return end

    -- 摇杆
    if js.numAxes > 0 then
        local axisX = js:GetAxisPosition(0)
        if axisX < -self.deadZone then
            self.actions[InputManager.ACTION_LEFT] = true
        elseif axisX > self.deadZone then
            self.actions[InputManager.ACTION_RIGHT] = true
        end
    end

    -- 按钮
    if js:IsController() then
        if js:GetButtonPress(CONTROLLER_BUTTON_A) then
            self.actionsPress[InputManager.ACTION_JUMP] = true
            self.actions[InputManager.ACTION_JUMP] = true
        end
        if js:GetButtonPress(CONTROLLER_BUTTON_X) then
            self.actionsPress[InputManager.ACTION_ATTACK] = true
            self.actions[InputManager.ACTION_ATTACK] = true
        end
        -- 下+攻击=下砸
        local axisY = js.numAxes > 1 and js:GetAxisPosition(1) or 0
        if axisY > 0.5 and js:GetButtonPress(CONTROLLER_BUTTON_X) then
            self.actionsPress[InputManager.ACTION_SLAM] = true
        end
    end
end

return InputManager
