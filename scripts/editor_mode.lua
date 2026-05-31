-- editor_mode.lua
-- 编辑器模式：初始化/销毁、UI构建、模式切换、更新循环
---@diagnostic disable: undefined-global, redefined-local

local LevelManager = require("scripts/level_manager")

local M = {}

-- ============================================================================
-- 注入共享状态
-- ============================================================================
local G  -- 将由 main.lua 注入

function M.init(shared)
    G = shared
end

-- ============================================================================
-- 切换到编辑器模式
-- ============================================================================
function M.switchToEditor()
    G.APP_MODE = "editor"

    -- 隐藏游戏 UI 元素
    if G.gmButton then G.gmButton.visible = false end
    if G.gameUI then G.gameUI:hide() end
    if G.cardUI then G.cardUI:hide() end
    if G.pausePanel then G.pausePanel.visible = false end
    if G.menuOverlay then G.menuOverlay:hide() end
    if G.gameOverContainer then G.gameOverContainer.visible = false end
    if G.comingSoonPanel then G.comingSoonPanel.visible = false end
    for _, e in ipairs(G.enemies) do
        e:hideHpBar()
    end

    -- 暂停游戏物理
    if G.physicsWorld_ then G.physicsWorld_.enabled = false end
    G.gamePaused = false

    -- 初始化编辑器
    M._initEditor()
end

-- ============================================================================
-- 切换回游戏模式
-- ============================================================================
function M.switchToGame()
    G.APP_MODE = "game"

    -- 销毁编辑器
    M._destroyEditor()

    -- 恢复默认关卡数据（编辑器测试可能注入了自定义数据）
    if G.levelManager then
        G.levelManager:clearCustomLevels()
    end

    -- 恢复游戏 UI
    if G.gmButton then G.gmButton.visible = true end
    if G.menuOverlay then G.menuOverlay:show() end

    -- 重建场景（编辑器可能修改了场景）
    G.game_module.CreateScene()
    G.game_module.SetupCamera()

    log:Write(LOG_INFO, "[App] Switched back to game mode")
end

-- ============================================================================
-- 从编辑器测试指定关卡
-- ============================================================================
function M.testLevelFromEditor(levelNum)
    log:Write(LOG_INFO, "[App] Testing level " .. levelNum .. " from editor")
    G.APP_MODE = "game"

    -- 在销毁编辑器前，提取编辑器中的关卡数据
    local editorLevels = nil
    if G.levelEditor then
        -- 同步场景到数据（确保最新的编辑内容被保存）
        if G.levelEditor._syncToLevelData then
            G.levelEditor:_syncToLevelData()
        end
        editorLevels = G.levelEditor.levels
    end

    -- 销毁编辑器
    M._destroyEditor()

    -- 恢复 GM 按钮
    if G.gmButton then G.gmButton.visible = true end

    -- 加载游戏模式脚本（默认用 normal_mode）
    G.game_module.LoadModeScripts("normal_mode")

    -- 初始化关卡管理器并设置指定关卡
    if G.levelManager then
        G.levelManager:reset()
    else
        G.levelManager = LevelManager:new()
    end

    -- 注入编辑器的关卡数据到 LevelManager（关键：让编辑的数据生效）
    if editorLevels and #editorLevels > 0 then
        G.levelManager:setCustomLevels(editorLevels)
        log:Write(LOG_INFO, "[App] Injected " .. #editorLevels .. " editor levels into LevelManager")
    end

    G.levelManager:setLevel(levelNum)
    G.transitionTimer = nil
    G.transitionTarget = nil

    -- 创建场景和游戏对象
    G.game_module.CreateScene()
    G.game_module.SetupCamera()
    G.game_module.InitGameObjects()

    -- 启动游戏
    G.cameraNode.position = Vector3(0, -1.9, -10)
    G.physicsWorld_.enabled = true
    G.scene_.updateEnabled = true
    G.gamePaused = false
    if G.pausePanel then G.pausePanel.visible = false end
    G.gameUI:show()
    G.gameUI:resetCountdown()
    G.cardSystem:reset()
    G.cardSkills:reset()
    G.cardUI:show()

    log:Write(LOG_INFO, "[App] Game started at level " .. levelNum)
end

-- ============================================================================
-- 编辑器初始化/销毁
-- ============================================================================
function M._initEditor()
    if G.editorActive then return end
    G.editorActive = true

    -- 加载编辑器模块
    if not G.editorInitialized then
        G.UI_lib = require("urhox-libs/UI")
        G.EditorLevel = require("editor/editor_level")
        G.EditorUI = require("editor/editor_ui")
        G.editorInitialized = true
    end

    -- 创建编辑器场景（覆盖游戏场景）
    G.scene_ = Scene()
    G.scene_:CreateComponent("Octree")

    G.cameraNode = G.scene_:CreateChild("Camera")
    local camera = G.cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = 20
    G.cameraNode.position = Vector3(10, 0, -10)

    local viewport = Viewport:new(G.scene_, camera)
    renderer:SetViewport(0, viewport)

    -- 创建 NanoVG 上下文
    if not G.nvgCtx then
        G.nvgCtx = nvgCreate(1)
        if G.nvgCtx then
            nvgCreateFont(G.nvgCtx, "editor", "Fonts/MiSans-Regular.ttf")
        end
    end

    -- 初始化 UI 系统
    G.UI_lib.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = G.UI_lib.Scale.DEFAULT,
    })

    -- 初始化子编辑器
    G.levelEditor = G.EditorLevel:new(G.scene_, G.cameraNode, G.nvgCtx)
    G.uiEditor = G.EditorUI:new(G.nvgCtx)

    -- 创建编辑器 UI（含"启动游戏"按钮）
    M._createEditorUI()

    -- 默认显示关卡编辑器
    M._editorSwitchMode("level")

    G.levelEditor.uiEditorRef = G.uiEditor

    -- 设置"测试当前关卡"回调
    G.levelEditor.onTestLevel = function(levelNum)
        M.testLevelFromEditor(levelNum)
    end

    -- 绑定 NanoVG 渲染事件
    if G.nvgCtx then
        SubscribeToEvent(G.nvgCtx, "NanoVGRender", "HandleEditorNanoVGRender")
    end

    log:Write(LOG_INFO, "[Editor] Initialized")
end

function M._destroyEditor()
    if not G.editorActive then return end
    G.editorActive = false

    -- 取消 NanoVG 事件
    if G.nvgCtx then
        UnsubscribeFromEvent(G.nvgCtx, "NanoVGRender")
    end

    -- 清理编辑器 UI
    if G.UI_lib then
        G.UI_lib.SetRoot(nil)
    end

    -- 清理引用
    G.levelEditor = nil
    G.uiEditor = nil
    G.tabLevel = nil
    G.tabUI = nil
    G.statusLabel = nil
    G.editorRoot = nil

    log:Write(LOG_INFO, "[Editor] Destroyed")
end

-- ============================================================================
-- 编辑器 UI 构建
-- ============================================================================
function M._createEditorUI()
    local toolbar = G.UI_lib.Panel {
        id = "toolbar",
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 35, 35, 45, 240 },
        paddingHorizontal = 12,
        gap = 8,
        children = {
            G.UI_lib.Label {
                id = "title",
                text = "可视化编辑器",
                fontSize = 16,
                fontColor = { 220, 220, 255, 255 },
                fontWeight = "bold",
            },
            G.UI_lib.Panel { width = 20 },
            G.UI_lib.Button {
                id = "tab_level",
                text = "关卡编辑",
                fontSize = 13,
                width = 90,
                height = 30,
                variant = "primary",
                onClick = function() M._editorSwitchMode("level") end,
            },
            G.UI_lib.Button {
                id = "tab_ui",
                text = "UI编辑",
                fontSize = 13,
                width = 90,
                height = 30,
                variant = "outline",
                onClick = function() M._editorSwitchMode("ui") end,
            },
            G.UI_lib.Panel { flex = 1 },
            G.UI_lib.Button {
                id = "btn_start_game",
                text = "启动游戏",
                fontSize = 13,
                width = 90,
                height = 30,
                variant = "danger",
                onClick = function()
                    log:Write(LOG_INFO, "[Editor] Start game button pressed")
                    M.switchToGame()
                end,
            },
            G.UI_lib.Panel { width = 12 },
            G.UI_lib.Label {
                id = "status",
                text = "就绪",
                fontSize = 12,
                fontColor = { 150, 150, 180, 255 },
            },
        }
    }

    local contentPanel = G.UI_lib.Panel {
        id = "content",
        flex = 1,
        width = "100%",
        flexDirection = "row",
        children = {
            G.levelEditor.panel,
            G.levelEditor.propsPanel,
            G.uiEditor.panel,
            G.uiEditor.propsPanel,
        },
    }

    G.editorRoot = G.UI_lib.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = { toolbar, contentPanel },
    }

    G.UI_lib.SetRoot(G.editorRoot)

    G.tabLevel = G.editorRoot:FindById("tab_level")
    G.tabUI = G.editorRoot:FindById("tab_ui")
    G.statusLabel = G.editorRoot:FindById("status")
end

-- ============================================================================
-- 编辑器模式切换
-- ============================================================================
function M._editorSwitchMode(mode)
    G.editorMode = mode
    if mode == "level" then
        G.tabLevel:SetVariant("primary")
        G.tabUI:SetVariant("outline")
        if G.levelEditor then G.levelEditor:show() end
        if G.uiEditor then G.uiEditor:hide() end
        M._editorSetStatus("关卡编辑 | 左键:放置/选择 右键:平移 滚轮:缩放 | Ctrl+S:保存")
    else
        G.tabLevel:SetVariant("outline")
        G.tabUI:SetVariant("primary")
        if G.levelEditor then G.levelEditor:hide() end
        if G.uiEditor then G.uiEditor:show() end
        M._editorSetStatus("UI编辑 | 选中元素 调整属性 | Ctrl+S:保存")
    end
end

function M._editorSetStatus(text)
    if G.statusLabel then G.statusLabel:SetText(text) end
end

-- ============================================================================
-- 编辑器 Update
-- ============================================================================
function M.editorUpdate(dt)
    if not G.editorActive then return end

    if G.editorMode == "level" and G.levelEditor then
        G.levelEditor:update(dt)
    elseif G.editorMode == "ui" and G.uiEditor then
        G.uiEditor:update(dt)
    end
end

-- ============================================================================
-- 编辑器 KeyUp 处理
-- ============================================================================
function M.editorHandleKeyUp(key)
    if not G.editorActive then return end

    -- 如果 KeyDown 已消费此按键，跳过 KeyUp 处理
    if G.editorKeyConsumed then
        G.editorKeyConsumed = false
        return
    end

    if key == KEY_ESCAPE then
        -- 编辑器中 ESC 返回游戏（仅当 handleKeyDown 未消费时触发）
        M.switchToGame()
    elseif key == KEY_TAB then
        if G.editorMode == "level" then
            M._editorSwitchMode("ui")
        else
            M._editorSwitchMode("level")
        end
    elseif key == KEY_S and input:GetQualifierDown(QUAL_CTRL) then
        -- UI编辑器模式的保存（关卡编辑器已由 handleKeyDown 处理）
        if G.editorMode == "ui" and G.uiEditor then
            G.uiEditor:saveToJSON()
            M._editorSetStatus("已保存UI配置!")
        end
    end
end

return M
