-- ============================================================================
-- 游戏入口 - 开始菜单场景
-- 点击"游戏开始"进入 game_01 场景，点击"游戏退出"退出引擎
-- ============================================================================

local UI = require("urhox-libs/UI")
local Game01 = require("game_01")

-- ============================================================================
-- 菜单 UI
-- ============================================================================

local menuRoot_ = nil

function Start()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    ShowMenu()
end

function ShowMenu()
    menuRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 20, 20, 40, 255 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                height = 320,
                backgroundColor = { 30, 35, 60, 240 },
                borderRadius = 20,
                justifyContent = "center",
                alignItems = "center",
                gap = 24,
                children = {
                    -- 标题
                    UI.Label {
                        text = "2D 动作游戏",
                        fontSize = 32,
                        fontColor = { 220, 230, 255, 255 },
                    },
                    -- 副标题
                    UI.Label {
                        text = "Action Prototype",
                        fontSize = 14,
                        fontColor = { 140, 150, 180, 200 },
                    },
                    -- 间距
                    UI.Panel { height = 20 },
                    -- 游戏开始按钮
                    UI.Button {
                        text = "游戏开始",
                        fontSize = 18,
                        width = 180,
                        height = 50,
                        borderRadius = 12,
                        variant = "primary",
                        onClick = function(self)
                            EnterGame()
                        end,
                    },
                    -- 游戏退出按钮
                    UI.Button {
                        text = "游戏退出",
                        fontSize = 18,
                        width = 180,
                        height = 50,
                        borderRadius = 12,
                        variant = "outline",
                        onClick = function(self)
                            engine:Exit()
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(menuRoot_)
end

function EnterGame()
    -- 清理菜单 UI
    UI.SetRoot(nil)
    menuRoot_ = nil
    -- 启动游戏场景
    Game01.Start()
end
