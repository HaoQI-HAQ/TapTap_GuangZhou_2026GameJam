-- ============================================================================
-- IsoMapEditor.lua — 等距场景编辑器集成入口模块
-- ============================================================================
--
-- 用法（在宿主项目的 main.lua 中）:
--
--   local IsoMapEditor = require("IsoMapEditor")
--
--   function Start()
--       -- ... 宿主项目初始化 UI.Init() ...
--       IsoMapEditor.Init({ tileFolder = "Tiles" })
--
--       -- 方式一: 将浮窗按钮嵌入宿主 UI 树
--       local myRoot = UI.Panel {
--           width = "100%", height = "100%",
--           children = {
--               -- ... 宿主 UI ...
--               IsoMapEditor.CreateFloatingButton(),
--           }
--       }
--       UI.SetRoot(myRoot)
--
--       -- 方式二 (推荐): 独立覆盖层，不受宿主 UI 树影响
--       -- IsoMapEditor.AttachOverlay()
--
--       SubscribeToEvent("Update", "HandleUpdate")
--       SubscribeToEvent("KeyDown", "HandleKeyDown")
--   end
--
--   function HandleUpdate(eventType, eventData)
--       local dt = eventData["TimeStep"]:GetFloat()
--       IsoMapEditor.Update(dt)
--       if not IsoMapEditor.IsActive() then
--           -- ... 宿主项目的 Update 逻辑 ...
--       end
--   end
--
--   function HandleKeyDown(eventType, eventData)
--       local key = eventData["Key"]:GetInt()
--       if IsoMapEditor.HandleKeyDown(key) then return end
--       -- ... 宿主项目的 KeyDown 逻辑 ...
--   end
--
-- ============================================================================

local UI = require("urhox-libs/UI")
local MapData = require("MapData")
local EditorUI = require("EditorUI")

local IsoMapEditor = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local isActive = false          -- 编辑器是否处于活跃状态
local isInited = false          -- 是否已初始化
local hostRoot = nil            -- 宿主项目的 UI 根节点
local editorRoot = nil          -- 编辑器的 UI 根节点
local floatingBtn = nil         -- 浮窗按钮引用
local config = {
    tileFolder = "Tiles",       -- 瓦片图片资源文件夹（相对 assets/）
    buttonSize = 56,            -- 浮窗按钮尺寸（像素）
    buttonLabel = "Map",        -- 浮窗按钮文本
    autoSave = true,            -- 离开编辑器时自动保存
}

-- 拖拽状态
local drag = {
    isDragging = false,         -- 是否正在拖拽
    pressTime = 0,              -- 鼠标按下累计时间
    isPressed = false,          -- 鼠标是否按在按钮上
    startMouseX = 0,            -- 按下时鼠标 X
    startMouseY = 0,            -- 按下时鼠标 Y
    startBtnX = 0,              -- 按下时按钮 X
    startBtnY = 0,              -- 按下时按钮 Y
    btnX = 0,                   -- 当前按钮左上角 X（逻辑坐标）
    btnY = 0,                   -- 当前按钮左上角 Y（逻辑坐标）
    positioned = false,         -- 是否已设置过初始位置
}

local LONG_PRESS_THRESHOLD = 0.3  -- 长按触发阈值（秒）
local DRAG_DEAD_ZONE = 4          -- 拖拽死区（像素，防止点击误触）

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取逻辑分辨率（考虑 DPR）
local function getLogicalSize()
    local dpr = graphics:GetDPR()
    return graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
end

--- 获取当前鼠标逻辑坐标
local function getMouseLogical()
    local pos = input:GetMousePosition()
    local dpr = graphics:GetDPR()
    return pos.x / dpr, pos.y / dpr
end

--- 判断鼠标逻辑坐标是否在按钮矩形内
local function isMouseInButton(mx, my)
    local size = config.buttonSize
    return mx >= drag.btnX and mx <= drag.btnX + size
       and my >= drag.btnY and my <= drag.btnY + size
end

--- 将按钮位置限制在屏幕内
local function clampToScreen(x, y)
    local logW, logH = getLogicalSize()
    local size = config.buttonSize
    x = math.max(0, math.min(x, logW - size))
    y = math.max(0, math.min(y, logH - size))
    return x, y
end

--- 更新按钮 widget 位置样式
local function applyButtonPosition()
    if not floatingBtn then return end
    floatingBtn:SetStyle({
        left = math.floor(drag.btnX),
        top = math.floor(drag.btnY),
        -- 清除 right/bottom，使用 left/top 绝对定位
        right = nil,
        bottom = nil,
    })
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 初始化编辑器（仅需调用一次）
--- 注意：调用前须确保宿主项目已调用 UI.Init()
---@param opts? table 配置项（可选）
---   tileFolder    string  瓦片图片文件夹路径，默认 "Tiles"
---   buttonSize    number  浮窗按钮尺寸，默认 56
---   buttonLabel   string  浮窗按钮文本，默认 "Map"
---   autoSave      boolean 离开时自动保存，默认 true
function IsoMapEditor.Init(opts)
    if isInited then return end

    -- 合并配置
    if opts then
        for k, v in pairs(opts) do
            config[k] = v
        end
    end

    -- 初始化地图数据
    MapData.Init()

    isInited = true
    print("[IsoMapEditor] 初始化完成, tileFolder=" .. config.tileFolder)
end

--- 创建浮窗入口按钮（默认屏幕中心，支持长按拖动）
--- 返回按钮 widget，宿主项目可嵌入其 UI 树
---@return table buttonWidget
function IsoMapEditor.CreateFloatingButton()
    local size = config.buttonSize

    -- 初始位置：屏幕中心
    if not drag.positioned then
        local logW, logH = getLogicalSize()
        drag.btnX = (logW - size) / 2
        drag.btnY = (logH - size) / 2
        drag.positioned = true
    end

    floatingBtn = UI.Panel {
        position = "absolute",
        left = math.floor(drag.btnX),
        top = math.floor(drag.btnY),
        width = size,
        height = size,
        borderRadius = size / 2,
        backgroundColor = { 59, 130, 246, 200 },
        justifyContent = "center",
        alignItems = "center",
        -- 阴影增强可见性
        shadowColor = { 0, 0, 0, 120 },
        shadowOffsetX = 0,
        shadowOffsetY = 2,
        shadowBlur = 8,
        children = {
            UI.Label {
                text = config.buttonLabel,
                fontSize = 13,
                fontWeight = "bold",
                color = { 255, 255, 255, 255 },
            },
        },
    }

    return floatingBtn
end

--- 获取浮窗按钮 widget（供宿主项目添加到其 UI 树中）
---@return table|nil
function IsoMapEditor.GetFloatingButton()
    return floatingBtn
end

--- 进入编辑器界面
function IsoMapEditor.Enter()
    if not isInited then
        print("[IsoMapEditor] 错误: 请先调用 IsoMapEditor.Init()")
        return
    end
    if isActive then return end

    -- 保存宿主项目的 UI 根节点
    hostRoot = UI.GetRoot()

    -- 构建编辑器 UI
    local editorContent = EditorUI.Build()

    editorRoot = UI.Panel {
        width = "100%",
        height = "100%",
        children = {
            -- 编辑器主体
            editorContent,
            -- 浮动返回按钮（左下角）
            UI.Panel {
                position = "absolute",
                bottom = 48,
                left = 12,
                children = {
                    UI.Button {
                        text = "< 返回",
                        fontSize = 12,
                        paddingHorizontal = 12,
                        paddingVertical = 6,
                        backgroundColor = "rgba(0,0,0,0.5)",
                        color = "#cccccc",
                        borderRadius = 6,
                        onClick = function()
                            IsoMapEditor.Exit()
                        end,
                    },
                },
            },
        },
    }

    UI.SetRoot(editorRoot)
    isActive = true

    -- 加载存档或项目地图
    if MapData.HasSave() then
        MapData.Load()
        print("[IsoMapEditor] 已加载临时存档")
    elseif MapData.LoadFromProject() then
        print("[IsoMapEditor] 已加载项目地图")
    end

    print("[IsoMapEditor] 进入编辑器")
end

--- 退出编辑器，返回宿主项目界面
function IsoMapEditor.Exit()
    if not isActive then return end

    -- 自动保存
    if config.autoSave then
        MapData.Save()
        print("[IsoMapEditor] 自动保存完成")
    end

    -- 恢复宿主项目 UI
    if hostRoot then
        UI.SetRoot(hostRoot)
    end

    isActive = false
    editorRoot = nil
    print("[IsoMapEditor] 退出编辑器")
end

--- 编辑器是否处于活跃状态
---@return boolean
function IsoMapEditor.IsActive()
    return isActive
end

--- 每帧更新（宿主项目在 HandleUpdate 中调用）
--- 包含：编辑器逻辑 + 浮窗按钮拖拽处理
---@param dt number 帧间隔
function IsoMapEditor.Update(dt)
    -- ---- 浮窗按钮拖拽（编辑器未激活时才处理） ----
    if not isActive and floatingBtn then
        local mx, my = getMouseLogical()
        local leftDown = input:GetMouseButtonDown(MOUSEB_LEFT)
        local leftPress = input:GetMouseButtonPress(MOUSEB_LEFT)

        -- 鼠标刚按下：检测是否在按钮上
        if leftPress and isMouseInButton(mx, my) then
            drag.isPressed = true
            drag.pressTime = 0
            drag.isDragging = false
            drag.startMouseX = mx
            drag.startMouseY = my
            drag.startBtnX = drag.btnX
            drag.startBtnY = drag.btnY
        end

        if drag.isPressed then
            if leftDown then
                drag.pressTime = drag.pressTime + dt

                local dx = math.abs(mx - drag.startMouseX)
                local dy = math.abs(my - drag.startMouseY)
                local moved = dx > DRAG_DEAD_ZONE or dy > DRAG_DEAD_ZONE

                -- 长按 或 已拖出死区 → 进入拖拽模式
                if not drag.isDragging and (drag.pressTime >= LONG_PRESS_THRESHOLD or moved) then
                    drag.isDragging = true
                    -- 拖拽开始：视觉反馈（半透明）
                    floatingBtn:SetStyle({ opacity = 0.6 })
                end

                -- 拖拽中：跟随鼠标
                if drag.isDragging then
                    local newX = drag.startBtnX + (mx - drag.startMouseX)
                    local newY = drag.startBtnY + (my - drag.startMouseY)
                    drag.btnX, drag.btnY = clampToScreen(newX, newY)
                    applyButtonPosition()
                end
            else
                -- 松开鼠标
                if drag.isDragging then
                    -- 拖拽结束：恢复不透明
                    floatingBtn:SetStyle({ opacity = 1.0 })
                    drag.isDragging = false
                else
                    -- 短按 = 点击 → 进入编辑器
                    IsoMapEditor.Enter()
                end
                drag.isPressed = false
                drag.pressTime = 0
            end
        end
    end

    -- ---- 编辑器逻辑 ----
    if not isActive then return end
    EditorUI.Update(dt)
    EditorUI.HandleWASDPan(dt)
end

--- 处理键盘事件（宿主项目在 HandleKeyDown 中调用）
--- 返回 true 表示编辑器已消费该事件，宿主项目应跳过处理
---@param key number 按键码
---@return boolean consumed 是否已消费
function IsoMapEditor.HandleKeyDown(key)
    if not isActive then return false end
    EditorUI.HandleKeyDown(key)
    return true
end

--- 手动保存当前地图
function IsoMapEditor.Save()
    if isInited then
        MapData.Save()
    end
end

--- 手动加载地图
function IsoMapEditor.Load()
    if isInited then
        MapData.Load()
    end
end

--- 导出地图数据为 JSON 字符串
---@return string|nil json
function IsoMapEditor.ExportJSON()
    if not isInited then return nil end
    local data = MapData.ExportToLua()
    if data then
        return cjson.encode(data)
    end
    return nil
end

--- 获取当前配置
---@return table
function IsoMapEditor.GetConfig()
    return config
end

--- 设置瓦片资源文件夹并重新扫描
---@param folder string 文件夹路径
---@return number count 加载的图片数量
function IsoMapEditor.SetTileFolder(folder)
    config.tileFolder = folder
    MapData.ClearImageTiles()
    local count = MapData.ScanAndLoadImages(folder)
    print(string.format("[IsoMapEditor] 扫描文件夹 '%s', 加载 %d 张图片", folder, count))
    return count
end

--- 设置浮窗按钮位置（逻辑坐标）
---@param x number 左上角 X
---@param y number 左上角 Y
function IsoMapEditor.SetButtonPosition(x, y)
    drag.btnX, drag.btnY = clampToScreen(x, y)
    drag.positioned = true
    applyButtonPosition()
end

--- 获取浮窗按钮位置
---@return number x, number y
function IsoMapEditor.GetButtonPosition()
    return drag.btnX, drag.btnY
end

return IsoMapEditor
