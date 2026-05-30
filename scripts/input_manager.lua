-- InputManager 类：统一管理键盘、手机按钮、手柄三种输入
InputManager = {}
InputManager.__index = InputManager

-- 动作定义
InputManager.ACTION_LEFT = "left"
InputManager.ACTION_RIGHT = "right"
InputManager.ACTION_JUMP = "jump"
InputManager.ACTION_ATTACK = "attack"
InputManager.ACTION_DOWN = "down"

function InputManager:new()
    ---@diagnostic disable-next-line: redefined-local
    local self = setmetatable({}, InputManager)

    -- 动作状态
    self.actions = {
        [InputManager.ACTION_LEFT] = false,
        [InputManager.ACTION_RIGHT] = false,
        [InputManager.ACTION_JUMP] = false,
        [InputManager.ACTION_ATTACK] = false,
        [InputManager.ACTION_DOWN] = false
    }

    -- 触摸按钮状态（由UI回调设置）
    self.touchActions = {
        [InputManager.ACTION_LEFT] = false,
        [InputManager.ACTION_RIGHT] = false,
        [InputManager.ACTION_JUMP] = false,
        [InputManager.ACTION_ATTACK] = false,
        [InputManager.ACTION_DOWN] = false
    }

    -- 键盘映射: key -> action
    self.keyboardMap = {
        [KEY_A] = InputManager.ACTION_LEFT,
        [KEY_LEFT] = InputManager.ACTION_LEFT,
        [KEY_D] = InputManager.ACTION_RIGHT,
        [KEY_RIGHT] = InputManager.ACTION_RIGHT,
        [KEY_SPACE] = InputManager.ACTION_JUMP,
        [KEY_W] = InputManager.ACTION_JUMP,
        [KEY_UP] = InputManager.ACTION_JUMP,
        [KEY_J] = InputManager.ACTION_ATTACK,
        [KEY_S] = InputManager.ACTION_DOWN,
        [KEY_DOWN] = InputManager.ACTION_DOWN
    }

    -- 手柄按钮映射: button -> action
    self.gamepadButtonMap = {
        [0] = InputManager.ACTION_JUMP,   -- A按钮（跳跃）
        [2] = InputManager.ACTION_JUMP    -- X按钮（跳跃备选）
    }

    -- 手柄摇杆死区（WASM环境虚拟手柄可能有轴漂移，设大一些）
    self.deadZone = 0.6

    log:Write(LOG_INFO, "[InputManager] Created with keyboard/touch/gamepad support")
    return self
end

-- 设置触摸按钮状态（由GameUI调用）
function InputManager:setTouchAction(action, active)
    self.touchActions[action] = active
end

-- 每帧更新，合并所有输入源
function InputManager:update()
    for action, _ in pairs(self.actions) do
        self.actions[action] = false
    end

    -- 1. 键盘输入
    self:_pollKeyboard()

    -- 2. 手柄输入
    self:_pollGamepad()

    -- 3. 触摸按钮输入（直接合并）
    for action, active in pairs(self.touchActions) do
        if active then
            self.actions[action] = true
        end
    end
end

-- 查询某个动作是否激活
function InputManager:isActionActive(action)
    return self.actions[action] == true
end

-- 键盘轮询
function InputManager:_pollKeyboard()
    for key, action in pairs(self.keyboardMap) do
        if input:GetKeyDown(key) then
            self.actions[action] = true
        end
    end
end

-- 手柄轮询
function InputManager:_pollGamepad()
    local numJoysticks = input:GetNumJoysticks()
    if numJoysticks == 0 then
        return
    end

    local joystick = input:GetJoystickByIndex(0)
    if joystick == nil then
        return
    end

    -- 摇杆左右（轴0为水平）
    if joystick.numAxes > 0 then
        local axisX = joystick:GetAxisPosition(0)
        if axisX < -self.deadZone then
            self.actions[InputManager.ACTION_LEFT] = true
        elseif axisX > self.deadZone then
            self.actions[InputManager.ACTION_RIGHT] = true
        end
    end

    -- 十字键（HAT）
    if joystick.numHats > 0 then
        local hat = joystick:GetHatPosition(0)
        if (hat & HAT_LEFT) ~= 0 then
            self.actions[InputManager.ACTION_LEFT] = true
        end
        if (hat & HAT_RIGHT) ~= 0 then
            self.actions[InputManager.ACTION_RIGHT] = true
        end
        if (hat & HAT_UP) ~= 0 then
            self.actions[InputManager.ACTION_JUMP] = true
        end
    end

    -- 手柄按钮
    for btn, action in pairs(self.gamepadButtonMap) do
        if joystick.numButtons > btn and joystick:GetButtonDown(btn) then
            self.actions[action] = true
        end
    end
end

return InputManager
