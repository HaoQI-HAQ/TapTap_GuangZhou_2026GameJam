-- ============================================================================
-- 游戏开始界面
-- 效果：先显示无角色背景，主角慢慢淡入；底栏左右眼睛位置循环五感图标
--       底栏左侧大格放"开始游戏"，右侧大格放"结束游戏"
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Widget
local uiRoot_ = nil
---@type Widget
local leftIcon_ = nil
---@type Widget
local rightIcon_ = nil
---@type Widget
local charLayer_ = nil

-- 五感图标路径
local normalIcons = {
    "image/UI/正常状态/视觉.png",
    "image/UI/正常状态/听觉.png",
    "image/UI/正常状态/嗅觉.png",
    "image/UI/正常状态/味觉.png",
    "image/UI/正常状态/触觉.png",
}

local abnormalIcons = {
    "image/UI/异常状态/视觉.png",
    "image/UI/异常状态/听觉.png",
    "image/UI/异常状态/嗅觉.png",
    "image/UI/异常状态/味觉.png",
    "image/UI/异常状态/触觉.png",
}

-- 图标循环状态
local leftIndex_ = 1
local rightIndex_ = 1
local switchInterval_ = 1.5
local leftTimer_ = 0
local rightTimer_ = 0.75

-- 角色淡入状态
local fadeTimer_ = 0
local fadeDuration_ = 2.5
local fadeDelay_ = 1.0
local fadeComplete_ = false

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "五感之骰"

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    CreateUI()
    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 开始界面已加载 ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function CreateUI()
    -- 有角色的图层（全屏覆盖，初始透明，渐渐显现）
    charLayer_ = UI.Panel {
        id = "charLayer",
        position = "absolute",
        top = 0,
        left = 0,
        width = "100%",
        height = "100%",
        backgroundImage = "image/game_start_screen_20260531013052.png",
        backgroundFit = "cover",
        opacity = 0,
        pointerEvents = "none",
    }

    -- 左侧五感图标（红框位置 - 底栏最左边的眼睛格）
    leftIcon_ = UI.Panel {
        id = "leftIcon",
        position = "absolute",
        bottom = "1.0%",
        left = "11.5%",
        width = "4.2%",
        height = "6.5%",
        backgroundImage = normalIcons[1],
        backgroundFit = "contain",
    }

    -- 右侧五感图标（红框位置 - 底栏最右边的眼睛格）
    rightIcon_ = UI.Panel {
        id = "rightIcon",
        position = "absolute",
        bottom = "1.0%",
        right = "11.5%",
        width = "4.2%",
        height = "6.5%",
        backgroundImage = abnormalIcons[1],
        backgroundFit = "contain",
    }

    -- 开始游戏按钮（绿框位置 - 底栏左侧大格）
    local startBtn = UI.Panel {
        id = "startBtn",
        position = "absolute",
        bottom = "0.8%",
        left = "17%",
        width = "25%",
        height = "6.8%",
        justifyContent = "center",
        alignItems = "center",
        borderRadius = 4,
        children = {
            UI.Label {
                text = "开始游戏",
                fontSize = 18,
                fontColor = { 200, 180, 220, 255 },
            },
        },
        onClick = function(self)
            print(">>> 开始游戏 <<<")
        end,
    }

    -- 结束游戏按钮（白框位置 - 底栏右侧大格）
    local exitBtn = UI.Panel {
        id = "exitBtn",
        position = "absolute",
        bottom = "0.8%",
        right = "17%",
        width = "25%",
        height = "6.8%",
        justifyContent = "center",
        alignItems = "center",
        borderRadius = 4,
        children = {
            UI.Label {
                text = "结束游戏",
                fontSize = 18,
                fontColor = { 200, 180, 220, 255 },
            },
        },
        onClick = function(self)
            print(">>> 结束游戏 <<<")
            engine:Exit()
        end,
    }

    -- 根布局
    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = "image/edited_game_start_screen_no_char_20260531015554.png",
        backgroundFit = "cover",
        children = {
            charLayer_,
            leftIcon_,
            rightIcon_,
            startBtn,
            exitBtn,
        }
    }

    UI.SetRoot(uiRoot_)
end

-- ============================================================================
-- 更新循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 角色淡入动画
    if not fadeComplete_ then
        fadeTimer_ = fadeTimer_ + dt
        if fadeTimer_ > fadeDelay_ then
            local elapsed = fadeTimer_ - fadeDelay_
            local progress = math.min(elapsed / fadeDuration_, 1.0)
            local eased = progress * progress * (3 - 2 * progress)
            if charLayer_ then
                charLayer_:SetStyle({ opacity = eased })
            end
            if progress >= 1.0 then
                fadeComplete_ = true
            end
        end
    end

    -- 左侧图标循环（正常状态五感）
    leftTimer_ = leftTimer_ + dt
    if leftTimer_ >= switchInterval_ then
        leftTimer_ = leftTimer_ - switchInterval_
        leftIndex_ = leftIndex_ + 1
        if leftIndex_ > #normalIcons then
            leftIndex_ = 1
        end
        if leftIcon_ then
            leftIcon_:SetBackgroundImage(normalIcons[leftIndex_])
        end
    end

    -- 右侧图标循环（异常状态五感）
    rightTimer_ = rightTimer_ + dt
    if rightTimer_ >= switchInterval_ then
        rightTimer_ = rightTimer_ - switchInterval_
        rightIndex_ = rightIndex_ + 1
        if rightIndex_ > #abnormalIcons then
            rightIndex_ = 1
        end
        if rightIcon_ then
            rightIcon_:SetBackgroundImage(abnormalIcons[rightIndex_])
        end
    end
end
