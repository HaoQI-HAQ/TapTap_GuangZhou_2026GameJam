-- main.lua
-- 统一入口：游戏 + 编辑器模式切换（薄分发层）
---@diagnostic disable: undefined-global, redefined-local

require "LuaScripts/Utilities/Sample"
local ScreenUtils = require("scripts/screen_utils")
require "scripts/input_manager"
require "scripts/menu_overlay"
require "scripts/loading_scene"

local GameMode = require("scripts/game_mode")
local EditorMode = require("scripts/editor_mode")

------------------------------------------------------------
-- 共享状态表（跨模块数据容器）
------------------------------------------------------------
local G = {
    -- 应用模式
    APP_MODE = "game",

    -- 游戏状态
    currentMode = nil,
    scene_ = nil,
    cameraNode = nil,
    camera_ = nil,
    player = nil,
    gameUI = nil,
    inputManager = nil,
    menuOverlay = nil,
    physicsWorld_ = nil,
    enemies = {},
    cardSystem = nil,
    cardUI = nil,
    cardSkills = nil,
    sensesSystem = nil,
    levelManager = nil,
    portalUI = nil,
    loadingScene = nil,
    gameReady = false,
    gamePaused = false,
    pausePanel = nil,
    gmButton = nil,
    gameOverContainer = nil,
    comingSoonPanel = nil,
    transitionTimer = nil,
    transitionTarget = nil,
    returnToMenuTimer = nil,

    -- 编辑器状态
    editorActive = false,
    editorInitialized = false,
    editorKeyConsumed = false,
    UI_lib = nil,
    EditorLevel = nil,
    EditorUI = nil,
    nvgCtx = nil,
    editorMode = "level",
    levelEditor = nil,
    uiEditor = nil,
    tabLevel = nil,
    tabUI = nil,
    statusLabel = nil,
    editorRoot = nil,
}

-- 注入共享状态和模块互引用
GameMode.init(G)
EditorMode.init(G)
G.game_module = GameMode
G.editorMode_module = EditorMode

-- 注册全局事件回调函数
GameMode.registerGlobalCallbacks()

------------------------------------------------------------
-- Start()：默认启动游戏
------------------------------------------------------------
function Start()
    SampleStart()
    ScreenUtils.init()

    G.loadingScene = LoadingScene:new(function()
        GameMode.OnLoadingComplete()
    end)

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    log:Write(LOG_INFO, "[App] Started in game mode")
end

------------------------------------------------------------
-- HandleUpdate: 根据 APP_MODE 分发
------------------------------------------------------------
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if G.APP_MODE == "editor" then
        EditorMode.editorUpdate(dt)
        return
    end

    GameMode.gameUpdate(dt)
end

------------------------------------------------------------
-- HandleKeyDown: 编辑器快捷键分发
------------------------------------------------------------
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    local qualifiers = eventData["Qualifiers"]:GetInt()

    G.editorKeyConsumed = false
    if G.APP_MODE == "editor" and G.editorActive then
        if G.editorMode == "level" and G.levelEditor then
            local consumed = G.levelEditor:handleKeyDown(key, qualifiers)
            if consumed then
                G.editorKeyConsumed = true
                return
            end
        end
    end
end

------------------------------------------------------------
-- HandleKeyUp: 根据 APP_MODE 分发
------------------------------------------------------------
function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if G.APP_MODE == "editor" then
        EditorMode.editorHandleKeyUp(key)
        return
    end
end

------------------------------------------------------------
-- Stop
------------------------------------------------------------
function Stop()
    log:Write(LOG_INFO, "[App] Stopped")
end
