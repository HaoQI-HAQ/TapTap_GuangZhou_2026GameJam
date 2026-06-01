-- 关卡与UI可视化编辑器 - 主入口
require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local EditorLevel = require("editor/editor_level")
local EditorUI = require("editor/editor_ui")

---@type Scene
local scene_ = nil
---@type Node
local cameraNode = nil

-- NanoVG 上下文
local nvgCtx = nil

-- 编辑器状态
local editorMode = "level"  -- "level" | "ui"
local levelEditor = nil
local uiEditor = nil

-- UI 引用
local tabLevel = nil
local tabUI = nil
local statusLabel = nil
local editorRoot = nil
local contentPanel = nil

function Start()
    SampleStart()

    -- 创建基础场景
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 相机
    cameraNode = scene_:CreateChild("Camera")
    local camera = cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = 20
    cameraNode.position = Vector3(10, 0, -10)

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)

    -- 创建 NanoVG 上下文（用于编辑器叠加层绘制）
    nvgCtx = nvgCreate(1)
    if not nvgCtx then
        log:Write(LOG_ERROR, "[Editor] Failed to create NanoVG context!")
        return
    end
    -- 创建字体（只调用一次）
    nvgCreateFont(nvgCtx, "editor", "Fonts/MiSans-Regular.ttf")

    -- 初始化UI系统
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化子编辑器（它们会创建自己的 panel）
    levelEditor = EditorLevel:new(scene_, cameraNode, nvgCtx)
    uiEditor = EditorUI:new(nvgCtx)

    -- 创建编辑器主UI（并把子编辑器面板嵌入）
    _createEditorUI()

    -- 默认显示关卡编辑器
    _switchMode("level")

    -- 让关卡编辑器持有 UI 编辑器引用，以便 NanoVG 回调中绘制 UI 预览
    levelEditor.uiEditorRef = uiEditor

    -- NanoVG 渲染事件绑定到上下文对象
    SubscribeToEvent(nvgCtx, "NanoVGRender", "HandleEditorNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    log:Write(LOG_INFO, "[Editor] Started - Level & UI Visual Editor")
end

function _createEditorUI()
    -- 顶部工具栏
    local toolbar = UI.Panel {
        id = "toolbar",
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 35, 35, 45, 240 },
        paddingHorizontal = 12,
        gap = 8,
        children = {
            UI.Label {
                id = "title",
                text = "可视化编辑器",
                fontSize = 16,
                fontColor = { 220, 220, 255, 255 },
                fontWeight = "bold",
            },
            UI.Panel { width = 20 },
            UI.Button {
                id = "tab_level",
                text = "关卡编辑",
                fontSize = 13,
                width = 90,
                height = 30,
                variant = "primary",
                onClick = function() _switchMode("level") end,
            },
            UI.Button {
                id = "tab_ui",
                text = "UI编辑",
                fontSize = 13,
                width = 90,
                height = 30,
                variant = "outline",
                onClick = function() _switchMode("ui") end,
            },
            UI.Panel { flex = 1 },
            UI.Label {
                id = "status",
                text = "就绪",
                fontSize = 12,
                fontColor = { 150, 150, 180, 255 },
            },
        }
    }

    -- 主内容区：左侧工具 + 中间画布 + 右侧属性
    contentPanel = UI.Panel {
        id = "content",
        flex = 1,
        width = "100%",
        flexDirection = "row",
        children = {
            -- 关卡编辑器面板
            levelEditor.panel,
            levelEditor.propsPanel,
            -- UI编辑器面板
            uiEditor.panel,
            uiEditor.propsPanel,
        },
    }

    -- 根容器
    editorRoot = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = { toolbar, contentPanel },
    }

    UI.SetRoot(editorRoot)

    -- 缓存引用
    tabLevel = editorRoot:FindById("tab_level")
    tabUI = editorRoot:FindById("tab_ui")
    statusLabel = editorRoot:FindById("status")
end

function _switchMode(mode)
    editorMode = mode

    if mode == "level" then
        tabLevel:SetVariant("primary")
        tabUI:SetVariant("outline")
        if levelEditor then levelEditor:show() end
        if uiEditor then uiEditor:hide() end
        _setStatus("关卡编辑 | 左键:放置/选择 右键:平移 滚轮:缩放 | Ctrl+S:保存")
    else
        tabLevel:SetVariant("outline")
        tabUI:SetVariant("primary")
        if levelEditor then levelEditor:hide() end
        if uiEditor then uiEditor:show() end
        _setStatus("UI编辑 | 选中元素 调整属性 | Ctrl+S:保存")
    end
end

function _setStatus(text)
    if statusLabel then
        statusLabel:SetText(text)
    end
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if editorMode == "level" and levelEditor then
        levelEditor:update(dt)
    elseif editorMode == "ui" and uiEditor then
        uiEditor:update(dt)
    end
end

function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        engine:Exit()
    elseif key == KEY_TAB then
        if editorMode == "level" then
            _switchMode("ui")
        else
            _switchMode("level")
        end
    elseif key == KEY_S and input:GetQualifierDown(QUAL_CTRL) then
        if editorMode == "level" and levelEditor then
            levelEditor:saveToJSON()
            _setStatus("已保存关卡数据!")
        elseif editorMode == "ui" and uiEditor then
            uiEditor:saveToJSON()
            _setStatus("已保存UI配置!")
        end
    elseif key == KEY_L and input:GetQualifierDown(QUAL_CTRL) then
        if editorMode == "level" and levelEditor then
            levelEditor:loadFromJSON()
            _setStatus("已加载关卡数据!")
        end
    elseif key == KEY_DELETE then
        if editorMode == "level" and levelEditor then
            levelEditor:_deleteSelected()
        end
    end
end
