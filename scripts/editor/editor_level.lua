-- editor_level.lua
-- 关卡可视化编辑器 - 入口/协调器
-- 功能：拖拽放置平台、敌人、传送门；平移/缩放画布；撤销/重做；复制/粘贴；快捷键；导出/导入JSON
---@diagnostic disable: undefined-global, redefined-local

-- 加载子模块
local EditorLevelData = require("editor/editor_level_data")
local EditorLevelUI = require("editor/editor_level_ui")
local EditorLevelScene = require("editor/editor_level_scene")

local ELEM_TYPES = EditorLevelData.ELEM_TYPES

local EditorLevel = {}
EditorLevel.__index = EditorLevel

-- 将子模块方法混入 EditorLevel 类
EditorLevelData.mixin(EditorLevel)
EditorLevelScene.mixin(EditorLevel)
EditorLevelUI.mixin(EditorLevel)

-- 模块级引用（供NanoVG全局回调使用）
local _activeEditor = nil
local _nvgCtx = nil

-- ============================================================================
-- 构造函数
-- ============================================================================

function EditorLevel:new(scene, cameraNode, nvgCtx)
    local self = setmetatable({}, EditorLevel)
    self.scene = scene
    self.cameraNode = cameraNode
    self.camera = cameraNode:GetComponent("Camera")

    _nvgCtx = nvgCtx

    -- 编辑器状态
    self.currentLevel = 1
    self.levels = {}
    self.selectedTool = nil
    self.selectedObject = nil
    self.objects = {}

    -- 相机控制
    self.camX = 10.0
    self.camY = 0.0
    self.zoom = 20.0
    self.dragging = false
    self.dragStartX = 0
    self.dragStartY = 0
    self.camStartX = 0
    self.camStartY = 0

    -- WASD 平移速度
    self.panSpeed = 15.0

    -- 悬停状态
    self.hoverWorldX = 0
    self.hoverWorldY = 0
    self.hoverSnapX = 0
    self.hoverSnapY = 0
    self.showGrid = true

    -- 撤销/重做栈
    self.undoStack = {}
    self.redoStack = {}

    -- 复制/粘贴缓存
    self.clipboard = nil

    -- 资源浏览器状态
    self.assetBrowserOpen = false
    self.assetBrowserPanel = nil
    self.assetCategories = {}
    self:_scanAssetFolders()

    -- 场景节点
    self.editorNode = scene:CreateChild("EditorObjects")

    -- UI面板
    self.panel = nil
    self.propsPanel = nil
    self.inspectorPanel = nil
    self.visible = false

    self:_createUI()
    self:_importAllGameLevels()

    _activeEditor = self
    return self
end

-- ============================================================================
-- 键盘事件处理
-- ============================================================================

function EditorLevel:handleKeyDown(key, qualifiers)
    if not self.visible then return false end

    local ctrl = (qualifiers & QUAL_CTRL) ~= 0

    if ctrl and key == KEY_Z then
        self:undo()
        return true
    end
    if ctrl and key == KEY_Y then
        self:redo()
        return true
    end
    if ctrl and key == KEY_C then
        self:copySelected()
        return true
    end
    if ctrl and key == KEY_V then
        self:paste()
        return true
    end
    if ctrl and key == KEY_S then
        self:saveToJSON()
        return true
    end

    if key == KEY_DELETE or key == KEY_BACKSPACE then
        self:_deleteSelected()
        return true
    end

    if key == KEY_H then
        self.showGrid = not self.showGrid
        return true
    end

    if key == KEY_ESCAPE then
        if self.selectedTool then
            self:_selectTool(nil)
            return true
        elseif self.selectedObject then
            self.selectedObject = nil
            self:_updateSelectedLabel()
            return true
        end
        return false
    end

    local numKeys = { KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9 }
    for i, nk in ipairs(numKeys) do
        if key == nk and i <= #ELEM_TYPES then
            self:_selectTool(ELEM_TYPES[i].id)
            return true
        end
    end

    if key == KEY_0 then
        self:_selectTool(nil)
        return true
    end

    return false
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function EditorLevel:update(dt)
    if not self.visible then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr

    -- WASD 键盘平移
    local panDelta = self.panSpeed * dt
    if input:GetKeyDown(KEY_W) then self.camY = self.camY + panDelta end
    if input:GetKeyDown(KEY_S) then self.camY = self.camY - panDelta end
    if input:GetKeyDown(KEY_A) then self.camX = self.camX - panDelta end
    if input:GetKeyDown(KEY_D) then self.camX = self.camX + panDelta end

    -- 滚轮缩放
    local wheel = input:GetMouseMoveWheel()
    if wheel ~= 0 then
        local oldZoom = self.zoom
        self.zoom = math.max(5, math.min(80, self.zoom - wheel * 2))
        if self.zoom ~= oldZoom then
            local mousePos = input:GetMousePosition()
            local worldBefore = self:_screenToWorld(mousePos)
            self.camera.orthoSize = self.zoom
            local worldAfter = self:_screenToWorld(mousePos)
            self.camX = self.camX + (worldBefore.x - worldAfter.x)
            self.camY = self.camY + (worldBefore.y - worldAfter.y)
        end
        self.camera.orthoSize = self.zoom
    end

    -- 右键平移
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        if not self.dragging then
            self.dragging = true
            self.dragStartX = input:GetMousePosition().x
            self.dragStartY = input:GetMousePosition().y
            self.camStartX = self.camX
            self.camStartY = self.camY
        else
            local dx = input:GetMousePosition().x - self.dragStartX
            local dy = input:GetMousePosition().y - self.dragStartY
            local scale = self.zoom / screenH
            self.camX = self.camStartX - dx * scale
            self.camY = self.camStartY + dy * scale
        end
    else
        if self.dragging then
            self.dragging = false
        end
    end

    -- 更新相机位置
    self.cameraNode.position = Vector3(self.camX, self.camY, -10)

    -- 悬停位置
    local mousePos = input:GetMousePosition()
    local worldPos = self:_screenToWorld(mousePos)
    self.hoverWorldX = worldPos.x
    self.hoverWorldY = worldPos.y
    self.hoverSnapX = math.floor(worldPos.x * 2 + 0.5) / 2
    self.hoverSnapY = math.floor(worldPos.y * 2 + 0.5) / 2

    -- 左键放置或选择
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        self:_handleClick()
    end

    -- 拖拽选中对象
    if self.selectedObject and not self.selectedTool and input:GetMouseButtonDown(MOUSEB_LEFT) then
        local logMX = mousePos.x / dpr
        local logMY = mousePos.y / dpr
        local leftPanel = 180
        local rightPanel = 200
        local topBar = 44
        if logMX >= leftPanel and logMX <= (logW - rightPanel) and logMY >= topBar then
            self.selectedObject.node.position = Vector3(self.hoverSnapX, self.hoverSnapY, 0.0)
            self:_updateSelectedLabel()
        end
    end

    -- 拖拽松手时同步数据
    if self.selectedObject and not self.selectedTool and input:GetMouseButtonRelease(MOUSEB_LEFT) then
        self:_syncToLevelData()
    end
end

-- ============================================================================
-- 点击处理
-- ============================================================================

function EditorLevel:_handleClick()
    if self.assetBrowserOpen then return end

    local mousePos = input:GetMousePosition()
    local screenW = graphics:GetWidth()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr

    local logMX = mousePos.x / dpr
    local logMY = mousePos.y / dpr

    local leftPanel = 180
    local rightPanel = 200
    local topBar = 44
    if logMX < leftPanel or logMX > (logW - rightPanel) or logMY < topBar then
        return
    end

    local worldClick = self:_screenToWorld(mousePos)
    if self.selectedTool then
        local hit = self:_findObjectAt(worldClick)
        if hit then
            self.selectedObject = hit
            self:_updateSelectedLabel()
        else
            self:_pushUndo()
            self:_spawnObject(self.selectedTool, self.hoverSnapX, self.hoverSnapY, {})
            self:_syncToLevelData()
        end
    else
        self:_trySelect(worldClick)
    end
end

function EditorLevel:_trySelect(worldPos)
    local hit = self:_findObjectAt(worldPos)
    if hit then
        self.selectedObject = hit
        self:_updateSelectedLabel()
        return
    end

    local closest = nil
    local closestDist = 1.5

    for _, obj in ipairs(self.objects) do
        local pos = obj.node.position
        local dx = worldPos.x - pos.x
        local dy = worldPos.y - pos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < closestDist then
            closestDist = dist
            closest = obj
        end
    end

    self.selectedObject = closest
    self:_updateSelectedLabel()
end

-- ============================================================================
-- 可见性
-- ============================================================================

function EditorLevel:show()
    self.visible = true
    if self.panel then self.panel:Show() end
    if self.propsPanel then self.propsPanel:Show() end
    if self.editorNode then self.editorNode.enabled = true end
    local ground = self.scene:GetChild("EditorGround")
    if ground then ground.enabled = true end
end

function EditorLevel:hide()
    self.visible = false
    if self.panel then self.panel:Hide() end
    if self.propsPanel then self.propsPanel:Hide() end
    if self.editorNode then self.editorNode.enabled = false end
    local ground = self.scene:GetChild("EditorGround")
    if ground then ground.enabled = false end
    if self.assetBrowserOpen then
        self:_closeAssetBrowser()
    end
end

-- ============================================================================
-- NanoVG 渲染（网格 + 悬停预览 + 选中高亮 + 状态栏）
-- ============================================================================

function HandleEditorNanoVGRender(eventType, eventData)
    local editor = _activeEditor
    if not editor or not _nvgCtx then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    if not editor.visible then
        if editor.uiEditorRef and editor.uiEditorRef.visible then
            nvgBeginFrame(_nvgCtx, logW, logH, dpr)
            editor.uiEditorRef:renderPreview(_nvgCtx)
            nvgEndFrame(_nvgCtx)
        end
        return
    end

    nvgBeginFrame(_nvgCtx, logW, logH, dpr)

    local camPos = editor.cameraNode.position
    local orthoH = editor.zoom
    local aspect = logW / logH
    local orthoW = orthoH * aspect

    local left = camPos.x - orthoW * 0.5
    local right = camPos.x + orthoW * 0.5
    local top = camPos.y + orthoH * 0.5
    local bottom = camPos.y - orthoH * 0.5

    -- 网格
    if editor.showGrid then
        local gridSize = 1.0
        if orthoH > 40 then gridSize = 5.0
        elseif orthoH > 20 then gridSize = 2.0 end

        nvgBeginPath(_nvgCtx)
        nvgStrokeColor(_nvgCtx, nvgRGBA(80, 80, 100, 30))
        nvgStrokeWidth(_nvgCtx, 1.0)

        local startX = math.floor(left / gridSize) * gridSize
        for x = startX, right, gridSize do
            local sx = (x - left) / orthoW * logW
            nvgMoveTo(_nvgCtx, sx, 0)
            nvgLineTo(_nvgCtx, sx, logH)
        end

        local startY = math.floor(bottom / gridSize) * gridSize
        for y = startY, top, gridSize do
            local sy = (top - y) / orthoH * logH
            nvgMoveTo(_nvgCtx, 0, sy)
            nvgLineTo(_nvgCtx, logW, sy)
        end
        nvgStroke(_nvgCtx)

        -- X轴
        nvgBeginPath(_nvgCtx)
        nvgStrokeColor(_nvgCtx, nvgRGBA(200, 50, 50, 80))
        nvgStrokeWidth(_nvgCtx, 1.5)
        local yZero = (top - 0) / orthoH * logH
        nvgMoveTo(_nvgCtx, 0, yZero)
        nvgLineTo(_nvgCtx, logW, yZero)
        nvgStroke(_nvgCtx)

        -- Y轴
        nvgBeginPath(_nvgCtx)
        nvgStrokeColor(_nvgCtx, nvgRGBA(50, 200, 50, 80))
        nvgStrokeWidth(_nvgCtx, 1.5)
        local xZero = (0 - left) / orthoW * logW
        nvgMoveTo(_nvgCtx, xZero, 0)
        nvgLineTo(_nvgCtx, xZero, logH)
        nvgStroke(_nvgCtx)
    end

    -- 悬停位置预览
    if editor.selectedTool then
        local snapX = editor.hoverSnapX
        local snapY = editor.hoverSnapY
        local sx = (snapX - left) / orthoW * logW
        local sy = (top - snapY) / orthoH * logH

        nvgBeginPath(_nvgCtx)
        nvgStrokeColor(_nvgCtx, nvgRGBA(255, 255, 255, 120))
        nvgStrokeWidth(_nvgCtx, 1.0)
        nvgMoveTo(_nvgCtx, sx - 10, sy)
        nvgLineTo(_nvgCtx, sx + 10, sy)
        nvgMoveTo(_nvgCtx, sx, sy - 10)
        nvgLineTo(_nvgCtx, sx, sy + 10)
        nvgStroke(_nvgCtx)

        local previewSize = 1.0 / orthoW * logW
        nvgBeginPath(_nvgCtx)
        nvgRect(_nvgCtx, sx - previewSize * 0.5, sy - previewSize * 0.5, previewSize, previewSize)
        nvgFillColor(_nvgCtx, nvgRGBA(255, 255, 100, 40))
        nvgFill(_nvgCtx)
        nvgStrokeColor(_nvgCtx, nvgRGBA(255, 255, 100, 150))
        nvgStrokeWidth(_nvgCtx, 1.5)
        nvgStroke(_nvgCtx)
    end

    -- 选中对象高亮边框
    if editor.selectedObject then
        local pos = editor.selectedObject.node.position
        local objW = editor.selectedObject.w or 1.0
        local objH = editor.selectedObject.h or 1.0

        local sx = (pos.x - objW * 0.5 - left) / orthoW * logW
        local sy = (top - pos.y - objH * 0.5) / orthoH * logH
        local sw = objW / orthoW * logW
        local sh = objH / orthoH * logH

        local pulse = math.sin(os.clock() * 4) * 0.3 + 0.7
        local alpha = math.floor(200 * pulse)

        nvgBeginPath(_nvgCtx)
        nvgRect(_nvgCtx, sx, sy, sw, sh)
        nvgStrokeColor(_nvgCtx, nvgRGBA(255, 255, 0, alpha))
        nvgStrokeWidth(_nvgCtx, 2.0)
        nvgStroke(_nvgCtx)
    end

    -- 底部状态栏
    nvgBeginPath(_nvgCtx)
    nvgRect(_nvgCtx, 0, logH - 28, logW, 28)
    nvgFillColor(_nvgCtx, nvgRGBA(20, 20, 30, 200))
    nvgFill(_nvgCtx)

    nvgFontFace(_nvgCtx, "editor")
    nvgFontSize(_nvgCtx, 12)
    nvgFillColor(_nvgCtx, nvgRGBA(180, 180, 210, 220))

    nvgTextAlign(_nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(_nvgCtx, 190, logH - 14, string.format(
        "坐标: (%.1f, %.1f)  缩放: %.0f  关卡: %d/%d [%s]",
        editor.hoverWorldX, editor.hoverWorldY,
        orthoH, editor.currentLevel, #editor.levels,
        editor.levels[editor.currentLevel] and editor.levels[editor.currentLevel].name or ""
    ))

    nvgTextAlign(_nvgCtx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    local toolName = "选择"
    if editor.selectedTool then
        for _, e in ipairs(ELEM_TYPES) do
            if e.id == editor.selectedTool then toolName = e.name; break end
        end
    end
    local undoCount = #editor.undoStack
    nvgText(_nvgCtx, logW - 210, logH - 14, string.format(
        "工具: %s | 撤销:%d | WASD平移 滚轮缩放 右键拖拽",
        toolName, undoCount
    ))

    nvgEndFrame(_nvgCtx)
end

return EditorLevel
