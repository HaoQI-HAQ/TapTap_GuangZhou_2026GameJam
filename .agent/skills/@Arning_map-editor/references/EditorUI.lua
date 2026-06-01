-- ============================================================================
-- EditorUI.lua — 编辑器 UI 布局（工具栏 + 调色板 + 状态栏）
-- ============================================================================

local UI = require("urhox-libs/UI")
-- cjson 是引擎内置全局变量，无需 require
local MapData = require("MapData")
local IsoCanvas = require("IsoCanvas")
local PlayMode = require("PlayMode")

local EditorUI = {}

-- 编辑器状态
local currentTool = "brush"    -- "brush" | "eraser" | "fill" | "picker"
local selectedTileID = 1       -- 当前选中瓦片 ID

-- UI 引用
local statusLabel = nil
local toastLabel = nil
local toolBrushBtn = nil
local toolEraserBtn = nil
local tileButtons = {}         -- tileID → button widget
local toastTimer = 0           -- toast 消失倒计时
local imagePaletteGrid = nil   -- 图片瓦片 SimpleGrid 容器
local imagePaletteSection = nil -- 图片瓦片区域面板
local imageTileButtonCache = {} -- imagePath → nvgHandle（按钮预览用）
local rebuildImagePalette      -- 前向声明
local layerListContainer = nil -- 动态层级列表容器
local rebuildLayerList         -- 前向声明
local toolFillBtn = nil
local toolPickerBtn = nil
local toolFloodBtn = nil
local toolSelectBtn = nil
local renameLayerIdx = nil    -- (已废弃，保留兼容)
local renameInput = nil       -- (已废弃，保留兼容)

--- 通用重命名弹窗
---@param title string 弹窗标题
---@param currentName string 当前名称
---@param onConfirm fun(newName: string) 确认回调
local function showRenameModal(title, currentName, onConfirm)
    local modal = UI.Modal {
        title = title,
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self) self:Destroy() end,
    }

    local textField = UI.TextField {
        value = currentName,
        placeholder = "输入新名称",
        fontSize = 13, height = 34, width = "100%",
        onSubmit = function(self, text)
            if text and text ~= "" then
                onConfirm(text)
            end
            modal:Close()
            modal:Destroy()
        end,
    }

    modal:AddContent(UI.Panel {
        flexDirection = "column", gap = 10, padding = 4,
        children = {
            UI.Label { text = "名称:", fontSize = 12, fontColor = { 180, 190, 210, 255 } },
            textField,
        },
    })

    local function doConfirm()
        local val = textField:GetValue()
        if val and val ~= "" then
            onConfirm(val)
        end
        modal:Close()
        modal:Destroy()
    end

    modal:SetFooter(UI.Panel {
        flexDirection = "row", justifyContent = "flex-end", gap = 8,
        children = {
            UI.Button {
                text = "取消", variant = "ghost", fontSize = 12,
                onClick = function() modal:Close(); modal:Destroy() end,
            },
            UI.Button {
                text = "确定", variant = "primary", fontSize = 12,
                onClick = doConfirm,
            },
        },
    })

    modal:Open()
end
local mapSizeLabel = nil      -- 地图尺寸显示标签
local mapWidthInput = nil     -- 宽度输入框
local mapHeightInput = nil    -- 高度输入框
local updateMapSizeLabel      -- 前向声明
local tilePropsContainer = nil -- 瓦片属性编辑容器
local rebuildTileProps         -- 前向声明
local folderTextField = nil    -- 文件夹输入框引用
local showSaveModal            -- 前向声明
local showLoadModal            -- 前向声明

-- ============================================================================
-- 状态访问（给 IsoCanvas 使用）
-- ============================================================================

function EditorUI.GetSelectedTool()
    return currentTool
end

function EditorUI.GetSelectedTileID()
    return selectedTileID
end

-- ============================================================================
-- 工具切换
-- ============================================================================

local function updateToolButtons()
    local toolDefs = {
        { btn = toolBrushBtn,  key = "brush",  activeColor = { 59, 130, 246, 255 } },
        { btn = toolEraserBtn, key = "eraser", activeColor = { 239, 68, 68, 255 } },
        { btn = toolFillBtn,   key = "fill",   activeColor = { 16, 185, 129, 255 } },
        { btn = toolFloodBtn,  key = "flood",  activeColor = { 6, 182, 212, 255 } },
        { btn = toolSelectBtn, key = "select", activeColor = { 255, 215, 0, 255 } },
        { btn = toolPickerBtn, key = "picker", activeColor = { 245, 158, 11, 255 } },
    }
    for _, def in ipairs(toolDefs) do
        if def.btn then
            def.btn:SetStyle({
                backgroundColor = currentTool == def.key
                    and def.activeColor
                    or { 60, 63, 70, 255 },
            })
        end
    end
end

local function selectTool(tool)
    currentTool = tool
    updateToolButtons()
    EditorUI.UpdateStatus()
end

-- ============================================================================
-- 层级管理
-- ============================================================================

local function selectLayer(index)
    MapData.SetCurrentLayer(index)  -- 内部自动退出预览模式
    rebuildLayerList()
    EditorUI.UpdateStatus()
end

local function togglePreview()
    MapData.SetPreviewMode(not MapData.IsPreviewMode())
    rebuildLayerList()
    EditorUI.UpdateStatus()
end

-- ============================================================================
-- 瓦片选择
-- ============================================================================

local function updateTileButtons()
    for id, btn in pairs(tileButtons) do
        btn:SetStyle({
            borderColor = id == selectedTileID
                and { 255, 255, 255, 255 }
                or { 80, 80, 90, 255 },
            borderWidth = id == selectedTileID and 2 or 1,
        })
    end
end

local function selectTile(tileID)
    selectedTileID = tileID
    currentTool = "brush"  -- 选瓦片自动切换画笔
    updateToolButtons()
    updateTileButtons()
    rebuildTileProps()
    EditorUI.UpdateStatus()
end

-- ============================================================================
-- 状态栏更新
-- ============================================================================

function EditorUI.UpdateStatus(mx, my)
    if not statusLabel then return end
    mx = mx or -1
    my = my or -1

    local coordStr = "---"
    if MapData.InBounds(mx, my) then
        coordStr = string.format("(%d, %d)", mx, my)
    end

    local toolNames = { brush = "画笔", eraser = "橡皮擦", fill = "填充", flood = "洪水填充", select = "选区", picker = "取色" }
    local toolName = toolNames[currentTool] or currentTool
    local tileName = MapData.GetTileType(selectedTileID).name

    if PlayMode.IsActive() then
        local gx, gy = PlayMode.GetGridPosition()
        statusLabel:SetText(string.format(
            "坐标: %s  |  游玩模式  |  角色: (%d, %d)  |  WASD 移动",
            coordStr, gx, gy
        ))
    elseif MapData.IsPreviewMode() then
        statusLabel:SetText(string.format(
            "坐标: %s  |  预览模式  |  %d 层",
            coordStr, MapData.GetLayerCount()
        ))
    else
        local layerName = MapData.GetCurrentLayerName()
        local layerIdx = MapData.GetCurrentLayer()
        statusLabel:SetText(string.format(
            "坐标: %s  |  层: %d-%s  |  工具: %s  |  瓦片: %s",
            coordStr, layerIdx, layerName, toolName, tileName
        ))
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

--- 创建工具栏
local function CreateToolbar()
    toolBrushBtn = UI.Button {
        text = "画笔 (B)",
        width = 90,
        height = 32,
        fontSize = 12,
        backgroundColor = { 59, 130, 246, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 6,
        onClick = function() selectTool("brush") end,
    }

    toolEraserBtn = UI.Button {
        text = "橡皮擦 (E)",
        width = 90,
        height = 32,
        fontSize = 12,
        backgroundColor = { 60, 63, 70, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 6,
        onClick = function() selectTool("eraser") end,
    }

    toolFillBtn = UI.Button {
        text = "填充 (U)",
        width = 80,
        height = 32,
        fontSize = 12,
        backgroundColor = { 60, 63, 70, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 6,
        onClick = function() selectTool("fill") end,
    }

    toolFloodBtn = UI.Button {
        text = "泼漆 (G)",
        width = 80,
        height = 32,
        fontSize = 12,
        backgroundColor = { 60, 63, 70, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 6,
        onClick = function() selectTool("flood") end,
    }

    toolSelectBtn = UI.Button {
        text = "选区 (M)",
        width = 80,
        height = 32,
        fontSize = 12,
        backgroundColor = { 60, 63, 70, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 6,
        onClick = function() selectTool("select") end,
    }

    toolPickerBtn = UI.Button {
        text = "取色 (I)",
        width = 80,
        height = 32,
        fontSize = 12,
        backgroundColor = { 60, 63, 70, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 6,
        onClick = function() selectTool("picker") end,
    }

    viewBtn = UI.Button {
        text = "等距",
        width = 64,
        height = 32,
        fontSize = 12,
        backgroundColor = { 50, 52, 58, 255 },
        textColor = { 180, 190, 210, 255 },
        borderRadius = 6,
        onClick = function()
            local newMode = IsoCanvas.ToggleViewMode()
            local isTD = (newMode == "topdown")
            viewBtn:SetText(isTD and "正视" or "等距")
            viewBtn:SetStyle({
                backgroundColor = isTD and { 60, 140, 80, 255 } or { 50, 52, 58, 255 },
                textColor = isTD and { 255, 255, 255, 255 } or { 180, 190, 210, 255 },
            })
            EditorUI.ShowToast(isTD and "正视45°视角" or "等距菱形视角")
        end,
    }

    return UI.Panel {
        id = "toolbar",
        height = 48,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        gap = 8,
        backgroundColor = { 40, 42, 48, 255 },
        borderColor = { 60, 62, 68, 255 },
        borderWidth = { 0, 0, 1, 0 },  -- 仅底边框
        children = {
            UI.Label {
                text = "等距编辑器",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = { 200, 210, 230, 255 },
                marginRight = 16,
            },
            toolBrushBtn,
            toolEraserBtn,
            toolFillBtn,
            toolFloodBtn,
            toolSelectBtn,
            toolPickerBtn,
            -- 视角切换按钮
            UI.Panel { width = 8 },  -- 间距
            viewBtn,
            -- 弹性空间
            UI.Panel { flexGrow = 1 },
            -- 导出按钮
            UI.Button {
                text = "导出",
                width = 64,
                height = 32,
                fontSize = 12,
                backgroundColor = { 139, 92, 246, 255 },
                textColor = { 255, 255, 255, 255 },
                borderRadius = 6,
                onClick = function()
                    local jsonStr = cjson.encode(cjson.decode(
                        -- 用 Save 序列化得到当前场景 JSON
                        (function()
                            local layersData = {}
                            for i, layer in ipairs(MapData.layers) do
                                local tiles = {}
                                for y = 1, MapData.MAP_H do
                                    if layer.data[y] then
                                        for x = 1, MapData.MAP_W do
                                            local id = layer.data[y][x] or 0
                                            if id > 0 then
                                                local t = MapData.TILE_TYPES[id]
                                                local entry = { x = x, y = y, id = id }
                                                if t and t.imagePath then entry.path = t.imagePath end
                                                if t and t.tag and t.tag ~= "" then entry.tag = t.tag end
                                                tiles[#tiles + 1] = entry
                                            end
                                        end
                                    end
                                end
                                layersData[i] = {
                                    name = layer.name, tiles = tiles,
                                    visible = layer.visible ~= false,
                                    locked = layer.locked == true,
                                    opacity = layer.opacity or 1.0,
                                    groupId = layer.groupId,
                                    tag = (layer.tag and layer.tag ~= "") and layer.tag or nil,
                                }
                            end
                            local data = {
                                version = 4,
                                width = MapData.MAP_W, height = MapData.MAP_H,
                                layers = layersData,
                            }
                            return cjson.encode(data)
                        end)()
                    ))

                    local exportModal = UI.Modal {
                        title = "导出 JSON",
                        size = "md",
                        closeOnOverlay = true,
                        closeOnEscape = true,
                        showCloseButton = true,
                        onClose = function(self) self:Destroy() end,
                    }

                    -- 先输出到浏览器控制台，方便从 DevTools 复制
                    print("===== MAP JSON START =====")
                    print(jsonStr)
                    print("===== MAP JSON END =====")

                    exportModal:AddContent(UI.Panel {
                        flexDirection = "column",
                        gap = 8,
                        padding = 4,
                        children = {
                            -- 操作说明
                            UI.Panel {
                                backgroundColor = { 30, 60, 90, 255 },
                                borderRadius = 6,
                                padding = 10,
                                children = {
                                    UI.Label {
                                        text = "JSON 已输出到浏览器控制台",
                                        fontSize = 13,
                                        fontColor = { 100, 200, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "按 F12 打开开发者工具 → Console 标签页 → 复制 JSON",
                                        fontSize = 11,
                                        fontColor = { 170, 190, 210, 255 },
                                        marginTop = 4,
                                    },
                                },
                            },
                            -- JSON 预览
                            UI.Panel {
                                maxHeight = 280,
                                overflow = "scroll",
                                backgroundColor = { 24, 26, 30, 255 },
                                borderRadius = 6,
                                padding = 10,
                                children = {
                                    UI.Label {
                                        text = jsonStr,
                                        fontSize = 11,
                                        fontColor = { 180, 200, 220, 255 },
                                        whiteSpace = "normal",
                                        width = "100%",
                                    },
                                },
                            },
                        }
                    })

                    exportModal:SetFooter(UI.Panel {
                        flexDirection = "row",
                        justifyContent = "flex-end",
                        gap = 8,
                        children = {
                            UI.Button {
                                text = "重新输出到控制台",
                                height = 32, fontSize = 12,
                                backgroundColor = { 59, 130, 246, 255 },
                                textColor = { 255, 255, 255, 255 },
                                borderRadius = 4,
                                onClick = function()
                                    print("===== MAP JSON START =====")
                                    print(jsonStr)
                                    print("===== MAP JSON END =====")
                                    EditorUI.ShowToast("已输出到控制台 (F12)")
                                end,
                            },
                            UI.Button {
                                text = "关闭",
                                height = 32, fontSize = 12,
                                borderRadius = 4,
                                onClick = function() exportModal:Close() end,
                            },
                        },
                    })

                    exportModal:Open()
                end,
            },
            -- 导入按钮
            UI.Button {
                text = "导入",
                width = 64,
                height = 32,
                fontSize = 12,
                backgroundColor = { 16, 185, 129, 255 },
                textColor = { 255, 255, 255, 255 },
                borderRadius = 6,
                onClick = function()
                    -- 优先从资源系统读取，再回退存档目录
                    local IMPORT_FILE = "mapjson/_import.json"
                    local file = cache:GetFile(IMPORT_FILE)
                    if not file then
                        file = File(IMPORT_FILE, FILE_READ)
                        if not file or not file:IsOpen() then
                            EditorUI.ShowToast("未找到导入文件\n请在对话中发送 JSON，AI 会写入该文件")
                            return
                        end
                    end
                    local importText = file:ReadString()
                    file:Close()
                    if importText == "" then
                        EditorUI.ShowToast("mapjson/_import.json 文件内容为空")
                        return
                    end
                    local ok, saveData = pcall(cjson.decode, importText)
                    if not ok or not saveData then
                        EditorUI.ShowToast("JSON 解析失败，请检查文件内容格式")
                        return
                    end
                    -- 恢复地图数据（复用 LoadFromNamedFile 的逻辑）
                    if saveData.width then MapData.MAP_W = saveData.width end
                    if saveData.height then MapData.MAP_H = saveData.height end
                    if saveData.showGrid ~= nil then MapData.showGrid = saveData.showGrid end
                    if saveData.imageRegistry then
                        MapData.ClearImageTiles()
                        MapData.imageFolder = saveData.imageFolder or ""
                        for _, reg in ipairs(saveData.imageRegistry) do
                            local regId = MapData.RegisterImageTile(reg.name, reg.imagePath)
                            if regId and reg.tag and reg.tag ~= "" then
                                MapData.TILE_TYPES[regId].tag = reg.tag
                            end
                        end
                    end
                    if saveData.tileCustomizations then
                        for _, c in ipairs(saveData.tileCustomizations) do
                            local t = MapData.TILE_TYPES[c.id]
                            if t then
                                if c.name then t.name = c.name end
                                if c.tag then t.tag = c.tag end
                            end
                        end
                    end
                    if saveData.groups then MapData.groups = saveData.groups
                    else MapData.groups = {} end
                    if saveData.nextGroupId then MapData.nextGroupId = saveData.nextGroupId end
                    if saveData.layers then
                        MapData.layers = {}
                        for i, layerInfo in ipairs(saveData.layers) do
                            local grid = {}
                            for y = 1, MapData.MAP_H do
                                grid[y] = {}
                                for x = 1, MapData.MAP_W do grid[y][x] = 0 end
                            end
                            if layerInfo.tiles then
                                for _, tile in ipairs(layerInfo.tiles) do
                                    if tile.x >= 1 and tile.x <= MapData.MAP_W
                                       and tile.y >= 1 and tile.y <= MapData.MAP_H then
                                        grid[tile.y][tile.x] = tile.id
                                    end
                                end
                            end
                            MapData.layers[i] = {
                                name = layerInfo.name or ("层 " .. i),
                                data = grid,
                                visible = layerInfo.visible ~= false,
                                locked = layerInfo.locked == true,
                                opacity = layerInfo.opacity or 1.0,
                                groupId = layerInfo.groupId,
                            }
                        end
                        if #MapData.layers == 0 then
                            local grid = {}
                            for y = 1, MapData.MAP_H do
                                grid[y] = {}
                                for x = 1, MapData.MAP_W do grid[y][x] = 0 end
                            end
                            MapData.layers[1] = { name = "地面", data = grid, visible = true, locked = false, opacity = 1.0 }
                        end
                        MapData.currentLayerIndex = math.min(MapData.currentLayerIndex, #MapData.layers)
                    end
                    rebuildImagePalette()
                    rebuildLayerList()
                    updateTileButtons()
                    rebuildTileProps()
                    if updateMapSizeLabel then updateMapSizeLabel() end
                    -- 导入成功后自动保存为命名存档，使"加载"按钮能扫描到
                    MapData.SaveToNamedFile("_import")
                    EditorUI.ShowToast("从 _import.json 导入成功")
                end,
            },
            -- 加载按钮（列出 mapjson/ 下所有存档供选择）
            UI.Button {
                text = "加载",
                width = 64,
                height = 32,
                fontSize = 12,
                backgroundColor = { 59, 130, 246, 255 },
                textColor = { 255, 255, 255, 255 },
                borderRadius = 6,
                onClick = function()
                    showLoadModal()
                end,
            },
            -- 清空按钮
            UI.Button {
                text = "清空",
                width = 64,
                height = 32,
                fontSize = 12,
                variant = "danger",
                borderRadius = 6,
                onClick = function()
                    MapData.Clear()
                    EditorUI.ShowToast("地图已清空")
                end,
            },
        }
    }
end

-- 自定义瓦片按钮 Widget（覆写 Render 绘制菱形预览）
local TileButtonWidget = nil

local function ensureTileButtonWidget()
    if TileButtonWidget then return end
    local Widget = require("urhox-libs/UI/Core/Widget")
    TileButtonWidget = Widget:Extend("TileButtonWidget")

    function TileButtonWidget:Render(nvg)
        self:RenderFullBackground(nvg)

        local l = self:GetAbsoluteLayout()
        local cx = l.x + l.w / 2
        local cy = l.y + l.h / 2

        local imagePath = self.props._imagePath
        if imagePath then
            -- 图片瓦片预览
            if not imageTileButtonCache[imagePath] then
                imageTileButtonCache[imagePath] = nvgCreateImage(nvg, imagePath, 0)
            end
            local handle = imageTileButtonCache[imagePath]
            if handle and handle ~= 0 then
                local pad = 4
                local imgX = l.x + pad
                local imgY = l.y + pad
                local imgW = l.w - pad * 2
                local imgH = l.h - pad * 2
                local paint = nvgImagePattern(nvg, imgX, imgY, imgW, imgH, 0, handle, 1.0)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, imgX, imgY, imgW, imgH, 3)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
            else
                -- fallback 灰色
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, l.x + 4, l.y + 4, l.w - 8, l.h - 8, 3)
                nvgFillColor(nvg, nvgRGBA(80, 80, 80, 200))
                nvgFill(nvg)
            end
        else
            -- 颜色瓦片菱形预览
            local hw = 16
            local hh = 8
            local c = self.props._tileColor
            if c then
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, cx, cy - hh)
                nvgLineTo(nvg, cx + hw, cy)
                nvgLineTo(nvg, cx, cy + hh)
                nvgLineTo(nvg, cx - hw, cy)
                nvgClosePath(nvg)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], c[4]))
                nvgFill(nvg)
            end
        end
    end
end

--- 创建瓦片调色板面板中的单个瓦片按钮
local function CreateTileButton(tileID)
    ensureTileButtonWidget()

    local tileType = MapData.GetTileType(tileID)
    local c = tileType.color

    local btn = TileButtonWidget {
        width = 44,
        height = 44,
        backgroundColor = { 50, 52, 58, 255 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { 80, 80, 90, 255 },
        _tileColor = c,
        _imagePath = tileType.imagePath or nil,

        onClick = function()
            selectTile(tileID)
        end,
    }

    tileButtons[tileID] = btn
    return btn
end

--- 重建图片瓦片调色板（扫描后调用）
rebuildImagePalette = function()
    if not imagePaletteGrid then return end

    -- 清空旧按钮
    imagePaletteGrid:RemoveAllChildren()

    local imageIDs = MapData.GetImageTileIDs()
    if #imageIDs == 0 then
        imagePaletteSection:SetStyle({ display = "none" })
        return
    end

    imagePaletteSection:SetStyle({ display = "flex" })

    -- 创建图片瓦片按钮并逐个添加
    for _, id in ipairs(imageIDs) do
        imagePaletteGrid:AddChild(CreateTileButton(id))
    end

    -- 更新选中高亮
    updateTileButtons()
end

--- 执行文件夹扫描
local function performScan(folder)
    if not folder or folder == "" then
        EditorUI.ShowToast("请输入文件夹路径")
        return
    end
    local count = MapData.ScanAndLoadImages(folder)
    if count > 0 then
        EditorUI.ShowToast(string.format("已加载 %d 张图片", count))
        rebuildImagePalette()
    else
        EditorUI.ShowToast("未找到图片文件")
    end
end

local previewBtn = nil  -- 预览按钮引用
local gridBtn = nil     -- 网格按钮引用
local playBtn = nil     -- 游玩按钮引用
local viewBtn = nil     -- 视角切换按钮引用

--- 更新游玩按钮样式
local function updatePlayButton()
    if not playBtn then return end
    local active = PlayMode.IsActive()
    playBtn:SetStyle({
        backgroundColor = active
            and { 46, 204, 113, 255 }
            or { 50, 52, 58, 255 },
        textColor = active
            and { 30, 30, 30, 255 }
            or { 180, 190, 210, 255 },
    })
end

--- 进入/退出游玩模式
local function togglePlayMode()
    if PlayMode.IsActive() then
        PlayMode.Exit()
        -- 退出时也退出预览模式
        if MapData.IsPreviewMode() then
            MapData.SetPreviewMode(false)
        end
    else
        -- 进入游玩模式：同时启用预览
        if not MapData.IsPreviewMode() then
            MapData.SetPreviewMode(true)
        end
        PlayMode.Enter()
    end
    rebuildLayerList()
    EditorUI.UpdateStatus()
    updatePlayButton()
end

--- 更新预览按钮样式
local function updatePreviewButton()
    if not previewBtn then return end
    local active = MapData.IsPreviewMode()
    previewBtn:SetStyle({
        backgroundColor = active
            and { 245, 158, 11, 255 }
            or { 50, 52, 58, 255 },
        textColor = active
            and { 30, 30, 30, 255 }
            or { 180, 190, 210, 255 },
    })
end

--- 更新网格按钮样式
local function updateGridButton()
    if not gridBtn then return end
    local active = MapData.IsGridVisible()
    gridBtn:SetStyle({
        backgroundColor = active
            and { 80, 120, 200, 255 }
            or { 50, 52, 58, 255 },
        textColor = active
            and { 255, 255, 255, 255 }
            or { 100, 110, 130, 255 },
    })
end

--- 更新视角按钮样式
local function updateViewButton()
    if not viewBtn then return end
    local mode = IsoCanvas.GetViewMode()
    local isTD = (mode == "topdown")
    viewBtn:SetText(isTD and "正视" or "等距")
    viewBtn:SetStyle({
        backgroundColor = isTD
            and { 60, 140, 80, 255 }
            or { 50, 52, 58, 255 },
        textColor = isTD
            and { 255, 255, 255, 255 }
            or { 180, 190, 210, 255 },
    })
end

--- 创建小图标按钮（层级面板用）
local function SmallIconBtn(text, w, bg, fg, onClick)
    return UI.Button {
        text = text,
        width = w or 22,
        minWidth = w or 22,
        height = 22,
        fontSize = 11,
        flexShrink = 0,
        backgroundColor = bg or { 50, 52, 58, 255 },
        textColor = fg or { 180, 190, 210, 255 },
        borderRadius = 3,
        paddingHorizontal = 0,
        onClick = onClick,
    }
end

--- 构建单个层行的 UI
---@param layerIdx number
---@param isPreview boolean
---@param indent boolean 是否缩进（组内层）
---@return table widget
local function buildLayerRow(layerIdx, isPreview, indent)
    local layerName = MapData.GetLayerName(layerIdx)
    local curIdx = MapData.GetCurrentLayer()
    local count = MapData.GetLayerCount()
    local isActive = (not isPreview) and (layerIdx == curIdx)
    local isVisible = MapData.IsLayerVisible(layerIdx)
    local isLocked = MapData.IsLayerLocked(layerIdx)
    local opacity = MapData.GetLayerOpacity(layerIdx)

    local visBtn = SmallIconBtn(
        isVisible and "V" or "-", 22,
        isVisible and { 50, 52, 58, 255 } or { 80, 40, 40, 255 },
        isVisible and { 180, 190, 210, 255 } or { 120, 80, 80, 255 },
        function()
            MapData.ToggleLayerVisible(layerIdx)
            rebuildLayerList()
        end
    )

    local lockBtn = SmallIconBtn(
        isLocked and "L" or "·", 22,
        isLocked and { 200, 120, 20, 255 } or { 50, 52, 58, 255 },
        isLocked and { 255, 255, 255, 255 } or { 100, 110, 130, 255 },
        function()
            MapData.ToggleLayerLocked(layerIdx)
            rebuildLayerList()
            EditorUI.ShowToast(MapData.IsLayerLocked(layerIdx)
                and (layerName .. " 已锁定") or (layerName .. " 已解锁"))
        end
    )

    local upBtn = SmallIconBtn("^", 20,
        layerIdx > 1 and { 50, 52, 58, 255 } or { 40, 40, 42, 255 },
        layerIdx > 1 and { 180, 190, 210, 255 } or { 60, 65, 75, 255 },
        function()
            if MapData.MoveLayerUp(layerIdx) then rebuildLayerList(); EditorUI.UpdateStatus() end
        end
    )

    local downBtn = SmallIconBtn("v", 20,
        layerIdx < count and { 50, 52, 58, 255 } or { 40, 40, 42, 255 },
        layerIdx < count and { 180, 190, 210, 255 } or { 60, 65, 75, 255 },
        function()
            if MapData.MoveLayerDown(layerIdx) then rebuildLayerList(); EditorUI.UpdateStatus() end
        end
    )

    local deleteBtn = SmallIconBtn("×", 22,
        { 80, 40, 40, 255 }, { 200, 100, 100, 255 },
        function()
            if MapData.RemoveLayer(layerIdx) then
                EditorUI.ShowToast("已删除层: " .. layerName)
                rebuildLayerList(); EditorUI.UpdateStatus()
            else EditorUI.ShowToast("至少保留一层") end
        end
    )

    -- 组分配按钮：已在组内 → 移出；未分组且有组 → 点击循环选组
    local groupBtn = nil
    local curGroupId = MapData.GetLayerGroup(layerIdx)
    local groupIDs = MapData.GetGroupIDs()

    if curGroupId then
        -- 已在组内，显示"移出"按钮
        groupBtn = SmallIconBtn("G×", 24,
            { 80, 60, 100, 255 }, { 200, 180, 255, 255 },
            function()
                MapData.SetLayerGroup(layerIdx, nil)
                EditorUI.ShowToast(layerName .. " 已移出组")
                rebuildLayerList()
            end
        )
    elseif #groupIDs > 0 then
        -- 未分组但有组存在，显示"G+"按钮，点击弹窗选择目标组
        groupBtn = SmallIconBtn("G+", 24,
            { 50, 52, 58, 255 }, { 160, 140, 220, 255 },
            function()
                local freshIDs = MapData.GetGroupIDs()
                if #freshIDs == 0 then return end
                local modal = UI.Modal {
                    title = "选择目标组",
                    size = "sm",
                    closeOnOverlay = true,
                    closeOnEscape = true,
                    showCloseButton = true,
                    onClose = function(self) self:Destroy() end,
                }
                local btns = {}
                for _, gid in ipairs(freshIDs) do
                    local g = MapData.GetGroup(gid)
                    if g then
                        btns[#btns + 1] = UI.Button {
                            text = g.name, variant = "outline", fontSize = 13,
                            width = "100%", height = 36,
                            onClick = function()
                                MapData.SetLayerGroup(layerIdx, gid)
                                EditorUI.ShowToast(layerName .. " → " .. g.name)
                                modal:Close(); modal:Destroy()
                                rebuildLayerList()
                            end,
                        }
                    end
                end
                modal:AddContent(UI.Panel {
                    flexDirection = "column", gap = 6, padding = 4,
                    children = btns,
                })
                modal:Open()
            end
        )
    end

    local displayName = layerName
    if not isVisible then displayName = displayName .. " (隐)" end
    local layerTag = MapData.GetLayerTag(layerIdx)
    if layerTag ~= "" then displayName = displayName .. " [" .. layerTag .. "]" end

    local nameWidget = UI.Button {
        text = displayName, height = 24, flexGrow = 1, flexShrink = 1,
        fontSize = 10,
        backgroundColor = isActive and { 59, 130, 246, 255 } or { 50, 52, 58, 255 },
        textColor = isActive and { 255, 255, 255, 255 }
            or (isVisible and { 180, 190, 210, 255 } or { 100, 100, 110, 255 }),
        borderRadius = 4,
        onClick = function()
            if MapData.GetCurrentLayer() ~= layerIdx then
                selectLayer(layerIdx)
            end
        end,
        onDoubleTap = function()
            showRenameModal("重命名图层", layerName, function(newName)
                MapData.RenameLayer(layerIdx, newName)
                EditorUI.ShowToast("已重命名: " .. newName)
                rebuildLayerList()
            end)
        end,
    }

    local opacitySlider = UI.Slider {
        value = math.floor(opacity * 100), min = 0, max = 100, step = 5,
        height = 16, fontSize = 9,
        onChange = function(self, v) MapData.SetLayerOpacity(layerIdx, v / 100) end,
    }

    -- 激活层额外显示标签编辑行
    local tagRow = nil
    if isActive then
        tagRow = UI.Panel {
            flexDirection = "row", alignItems = "center", height = 22, gap = 4, paddingLeft = 4,
            children = {
                UI.Label {
                    text = "标签", fontSize = 9, fontColor = { 140, 150, 170, 255 }, width = 26,
                },
                UI.TextField {
                    value = layerTag,
                    placeholder = "collision, trigger ...",
                    height = 20, flexGrow = 1,
                    fontSize = 9, borderRadius = 3,
                    onSubmit = function(self, text)
                        MapData.SetLayerTag(layerIdx, text or "")
                        rebuildLayerList()
                        local msg = (text and text ~= "") and ("层标签: " .. text) or "层标签已清除"
                        EditorUI.ShowToast(msg)
                    end,
                },
            },
        }
    end

    return UI.Panel {
        gap = 1,
        paddingHorizontal = 2,
        paddingVertical = 2,
        marginLeft = indent and 10 or 0,
        backgroundColor = isActive and { 59, 130, 246, 60 } or { 0, 0, 0, 0 },
        borderRadius = 4,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", height = 26, gap = 2,
                children = { visBtn, lockBtn, nameWidget, groupBtn, upBtn, downBtn, deleteBtn },
            },
            isActive and UI.Panel {
                flexDirection = "row", alignItems = "center", height = 20, gap = 4, paddingLeft = 4,
                children = {
                    UI.Label {
                        text = string.format("透明 %d%%", math.floor(opacity * 100)),
                        fontSize = 9, fontColor = { 140, 150, 170, 255 }, width = 52,
                    },
                    opacitySlider,
                },
            } or nil,
            tagRow,
        },
    }
end

--- 构建组头行 UI
---@param groupId number
---@return table widget
local function buildGroupHeader(groupId)
    local group = MapData.GetGroup(groupId)
    if not group then return UI.Panel {} end

    local collapsed = group.collapsed
    local gName = group.name

    -- 折叠按钮
    local collapseBtn = SmallIconBtn(
        collapsed and ">" or "v", 22,
        { 50, 52, 58, 255 }, { 180, 190, 210, 255 },
        function()
            MapData.ToggleGroupCollapsed(groupId)
            rebuildLayerList()
        end
    )

    -- 整组可见性
    local groupLayers = MapData.GetGroupLayers(groupId)
    local allVisible = true
    local allLocked = true
    for _, li in ipairs(groupLayers) do
        if not MapData.IsLayerVisible(li) then allVisible = false end
        if not MapData.IsLayerLocked(li) then allLocked = false end
    end

    local gVisBtn = SmallIconBtn(
        allVisible and "V" or "-", 22,
        allVisible and { 50, 52, 58, 255 } or { 80, 40, 40, 255 },
        allVisible and { 180, 190, 210, 255 } or { 120, 80, 80, 255 },
        function()
            MapData.SetGroupVisible(groupId, not allVisible)
            rebuildLayerList()
        end
    )

    local gLockBtn = SmallIconBtn(
        allLocked and "L" or "·", 22,
        allLocked and { 200, 120, 20, 255 } or { 50, 52, 58, 255 },
        allLocked and { 255, 255, 255, 255 } or { 100, 110, 130, 255 },
        function()
            MapData.SetGroupLocked(groupId, not allLocked)
            rebuildLayerList()
        end
    )

    -- 组名
    local function doRenameGroup()
        showRenameModal("重命名图层组", gName, function(newName)
            MapData.RenameGroup(groupId, newName)
            EditorUI.ShowToast("组重命名: " .. newName)
            rebuildLayerList()
        end)
    end

    local nameWidget = UI.Button {
        text = gName .. " (" .. #groupLayers .. ")",
        height = 24, flexGrow = 1, flexShrink = 1,
        fontSize = 10,
        backgroundColor = { 60, 55, 80, 255 },
        textColor = { 200, 180, 255, 255 },
        borderRadius = 4,
        onClick = function()
            MapData.ToggleGroupCollapsed(groupId)
            rebuildLayerList()
        end,
        onDoubleTap = function() doRenameGroup() end,
    }

    -- 删除组按钮
    local delGrpBtn = SmallIconBtn("×", 22,
        { 80, 40, 40, 255 }, { 200, 100, 100, 255 },
        function()
            MapData.DeleteGroup(groupId)
            EditorUI.ShowToast("已删除组: " .. gName)
            rebuildLayerList()
        end
    )

    return UI.Panel {
        flexDirection = "row", alignItems = "center", height = 28, gap = 2,
        paddingHorizontal = 2,
        backgroundColor = { 50, 45, 70, 180 },
        borderRadius = 4,
        children = { collapseBtn, gVisBtn, gLockBtn, nameWidget, delGrpBtn },
    }
end

--- 重建层级列表 UI（支持图层组）
rebuildLayerList = function()
    if not layerListContainer then return end

    layerListContainer:RemoveAllChildren()

    local isPreview = MapData.IsPreviewMode()
    local groupIDs = MapData.GetGroupIDs()
    local renderedLayers = {}  -- 已渲染的层索引集合

    -- 先渲染各组
    for _, gid in ipairs(groupIDs) do
        layerListContainer:AddChild(buildGroupHeader(gid))

        if not MapData.IsGroupCollapsed(gid) then
            local layerIndices = MapData.GetGroupLayers(gid)
            for _, li in ipairs(layerIndices) do
                layerListContainer:AddChild(buildLayerRow(li, isPreview, true))
                renderedLayers[li] = true
            end
        else
            -- 折叠时也标记已渲染
            local layerIndices = MapData.GetGroupLayers(gid)
            for _, li in ipairs(layerIndices) do
                renderedLayers[li] = true
            end
        end
    end

    -- 渲染未分组的层
    local count = MapData.GetLayerCount()
    for i = 1, count do
        if not renderedLayers[i] then
            layerListContainer:AddChild(buildLayerRow(i, isPreview, false))
        end
    end

    -- 同步按钮样式
    updatePreviewButton()
    updateGridButton()
    updatePlayButton()
end

--- 重建瓦片属性编辑面板
rebuildTileProps = function()
    if not tilePropsContainer then return end
    tilePropsContainer:RemoveAllChildren()

    local tileType = MapData.GetTileType(selectedTileID)
    if not tileType or selectedTileID == 0 then return end

    -- 瓦片名称
    tilePropsContainer:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4,
        children = {
            UI.Label {
                text = "名称", fontSize = 10, fontColor = { 140, 150, 170, 255 }, width = 30,
            },
            UI.TextField {
                value = tileType.name,
                height = 24, flexGrow = 1,
                fontSize = 10, borderRadius = 4,
                onSubmit = function(self, text)
                    if text and text ~= "" then
                        MapData.SetTileName(selectedTileID, text)
                        EditorUI.ShowToast("瓦片命名: " .. text)
                        updateTileButtons()
                    end
                end,
            },
        },
    })

    -- 显示当前瓦片 ID
    local idStr = "ID: " .. selectedTileID
    if tileType.imagePath then
        idStr = idStr .. "  (图片)"
    end
    tilePropsContainer:AddChild(UI.Label {
        text = idStr,
        fontSize = 9, fontColor = { 100, 110, 130, 255 },
    })
end

-- ============================================================================
-- 保存/加载弹窗
-- ============================================================================

--- 刷新编辑器（加载后调用）
local function refreshAfterLoad()
    rebuildImagePalette()
    rebuildLayerList()
    updateTileButtons()
    rebuildTileProps()
    if updateMapSizeLabel then updateMapSizeLabel() end
end

--- 显示保存弹窗
showSaveModal = function()
    local modal = UI.Modal {
        title = "保存地图",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self) self:Destroy() end,
    }

    local filenameValue = "my_map"
    local filenameInput

    modal:AddContent(UI.Panel {
        flexDirection = "column",
        gap = 10,
        padding = 4,
        children = {
            UI.Label {
                text = "文件名:",
                fontSize = 12,
                fontColor = { 180, 190, 210, 255 },
            },
            (function()
                filenameInput = UI.TextField {
                    placeholder = "输入文件名",
                    value = filenameValue,
                    fontSize = 13,
                    height = 34,
                    width = "100%",
                    onTextChange = function(self, text)
                        filenameValue = text
                    end,
                }
                return filenameInput
            end)(),
            UI.Label {
                text = "保存到 mapjson/ 目录（.json）",
                fontSize = 10,
                fontColor = { 100, 110, 130, 255 },
            },
        }
    })

    modal:SetFooter(UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 8,
        children = {
            UI.Button {
                text = "取消",
                height = 32, fontSize = 12,
                borderRadius = 4,
                onClick = function() modal:Close() end,
            },
            UI.Button {
                text = "保存",
                height = 32, fontSize = 12,
                backgroundColor = { 34, 139, 34, 255 },
                textColor = { 255, 255, 255, 255 },
                borderRadius = 4,
                onClick = function()
                    local name = filenameValue
                    if not name or name == "" then
                        EditorUI.ShowToast("请输入文件名")
                        return
                    end
                    -- 检查重名
                    if MapData.NamedFileExists(name) then
                        modal:Close()
                        -- 弹出覆盖确认
                        local confirmModal = UI.Modal {
                            title = "文件已存在",
                            size = "sm",
                            closeOnOverlay = true,
                            closeOnEscape = true,
                            showCloseButton = true,
                            onClose = function(self) self:Destroy() end,
                        }
                        confirmModal:AddContent(UI.Panel {
                            padding = 4,
                            children = {
                                UI.Label {
                                    text = string.format('"%s.json" 已存在，是否覆盖？', name),
                                    fontSize = 13,
                                    fontColor = { 220, 200, 120, 255 },
                                    whiteSpace = "normal",
                                },
                            }
                        })
                        confirmModal:SetFooter(UI.Panel {
                            flexDirection = "row",
                            justifyContent = "flex-end",
                            gap = 8,
                            children = {
                                UI.Button {
                                    text = "重命名",
                                    height = 32, fontSize = 12,
                                    borderRadius = 4,
                                    onClick = function()
                                        confirmModal:Close()
                                        -- 重新打开保存弹窗
                                        showSaveModal()
                                    end,
                                },
                                UI.Button {
                                    text = "覆盖",
                                    height = 32, fontSize = 12,
                                    backgroundColor = { 220, 80, 60, 255 },
                                    textColor = { 255, 255, 255, 255 },
                                    borderRadius = 4,
                                    onClick = function()
                                        confirmModal:Close()
                                        if MapData.SaveToNamedFile(name) then
                                            MapData.SaveToProject()
                                            EditorUI.ShowToast("已覆盖保存: " .. name .. ".json")
                                        else
                                            EditorUI.ShowToast("保存失败")
                                        end
                                    end,
                                },
                            }
                        })
                        confirmModal:Open()
                    else
                        -- 直接保存
                        modal:Close()
                        if MapData.SaveToNamedFile(name) then
                            MapData.SaveToProject()
                            EditorUI.ShowToast("已保存: " .. name .. ".json")
                        else
                            EditorUI.ShowToast("保存失败")
                        end
                    end
                end,
            },
        }
    })

    modal:Open()
end

--- 显示加载弹窗
showLoadModal = function()
    local maps = MapData.ListSavedMaps()

    if #maps == 0 then
        EditorUI.ShowToast("mapjson/ 目录下没有存档")
        return
    end

    local modal = UI.Modal {
        title = "加载地图",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self) self:Destroy() end,
    }

    local listChildren = {}
    for i, name in ipairs(maps) do
        listChildren[i] = UI.Button {
            text = name .. ".json",
            height = 36,
            fontSize = 12,
            width = "100%",
            backgroundColor = { 50, 54, 62, 255 },
            textColor = { 200, 210, 230, 255 },
            borderRadius = 4,
            marginBottom = 4,
            onClick = function()
                modal:Close()
                if MapData.LoadFromNamedFile(name) then
                    refreshAfterLoad()
                    EditorUI.ShowToast("已加载: " .. name .. ".json")
                else
                    EditorUI.ShowToast("加载失败: " .. name)
                end
            end,
        }
    end

    modal:AddContent(UI.Panel {
        flexDirection = "column",
        gap = 2,
        padding = 4,
        maxHeight = 300,
        overflow = "scroll",
        children = listChildren,
    })

    modal:SetFooter(UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        children = {
            UI.Button {
                text = "取消",
                height = 32, fontSize = 12,
                borderRadius = 4,
                onClick = function() modal:Close() end,
            },
        }
    })

    modal:Open()
end

--- 更新地图尺寸标签
updateMapSizeLabel = function()
    if mapSizeLabel then
        mapSizeLabel:SetText(string.format("地图 %d×%d", MapData.MAP_W, MapData.MAP_H))
    end
    if mapWidthInput then
        mapWidthInput:SetText(tostring(MapData.MAP_W))
    end
    if mapHeightInput then
        mapHeightInput:SetText(tostring(MapData.MAP_H))
    end
end

--- 创建层级管理面板
local function CreateLayerPanel()
    layerListContainer = UI.Panel {
        id = "layerList",
        gap = 2,
    }

    mapSizeLabel = UI.Label {
        text = string.format("地图 %d×%d", MapData.MAP_W, MapData.MAP_H),
        fontSize = 11,
        fontWeight = "bold",
        fontColor = { 160, 170, 190, 255 },
    }

    mapWidthInput = UI.TextField {
        value = tostring(MapData.MAP_W),
        height = 24,
        flexGrow = 1,
        fontSize = 10,
        borderRadius = 4,
    }

    mapHeightInput = UI.TextField {
        value = tostring(MapData.MAP_H),
        height = 24,
        flexGrow = 1,
        fontSize = 10,
        borderRadius = 4,
    }

    previewBtn = UI.Button {
        text = "预览",
        height = 28,
        fontSize = 11,
        backgroundColor = { 50, 52, 58, 255 },
        textColor = { 180, 190, 210, 255 },
        borderRadius = 4,
        onClick = function()
            togglePreview()
        end,
    }

    playBtn = UI.Button {
        text = "游玩",
        height = 28,
        fontSize = 11,
        backgroundColor = { 50, 52, 58, 255 },
        textColor = { 180, 190, 210, 255 },
        borderRadius = 4,
        onClick = function()
            togglePlayMode()
        end,
    }

    gridBtn = UI.Button {
        text = "网格",
        height = 28,
        fontSize = 11,
        backgroundColor = { 80, 120, 200, 255 },
        textColor = { 255, 255, 255, 255 },
        borderRadius = 4,
        onClick = function()
            MapData.SetGridVisible(nil)  -- toggle
            updateGridButton()
            EditorUI.ShowToast(MapData.IsGridVisible() and "网格已显示" or "网格已隐藏")
        end,
    }

    return UI.Panel {
        id = "layerPanel",
        gap = 6,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "层级",
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = { 160, 170, 190, 255 },
                        flexGrow = 1,
                    },
                    gridBtn,
                    previewBtn,
                    playBtn,
                },
            },
            layerListContainer,
            -- 添加层 / 新建组 按钮行
            UI.Panel {
                flexDirection = "row", gap = 4,
                children = {
                    UI.Button {
                        text = "+ 添加层",
                        height = 28,
                        flexGrow = 1,
                        fontSize = 11,
                        backgroundColor = { 50, 120, 50, 255 },
                        textColor = { 200, 255, 200, 255 },
                        borderRadius = 4,
                        onClick = function()
                            local idx = MapData.AddLayer()
                            selectLayer(idx)
                            EditorUI.ShowToast("已添加: " .. MapData.GetLayerName(idx))
                        end,
                    },
                    UI.Button {
                        text = "+ 新建组",
                        height = 28,
                        flexGrow = 1,
                        fontSize = 11,
                        backgroundColor = { 80, 60, 130, 255 },
                        textColor = { 210, 190, 255, 255 },
                        borderRadius = 4,
                        onClick = function()
                            local gid = MapData.CreateGroup()
                            EditorUI.ShowToast("已创建: " .. MapData.GetGroup(gid).name)
                            rebuildLayerList()
                        end,
                    },
                },
            },
            -- 地图尺寸调整区域
            UI.Divider { spacing = 4, color = { 60, 62, 68, 255 } },
            UI.Panel {
                gap = 4,
                children = {
                    mapSizeLabel,
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Label { text = "宽", fontSize = 10, fontColor = { 140, 150, 170, 255 }, width = 18 },
                            mapWidthInput,
                            UI.Label { text = "高", fontSize = 10, fontColor = { 140, 150, 170, 255 }, width = 18 },
                            mapHeightInput,
                            UI.Button {
                                text = "应用",
                                width = 40,
                                height = 24,
                                fontSize = 10,
                                backgroundColor = { 139, 92, 246, 255 },
                                textColor = { 255, 255, 255, 255 },
                                borderRadius = 4,
                                onClick = function()
                                    local wStr = mapWidthInput:GetText()
                                    local hStr = mapHeightInput:GetText()
                                    local newW = tonumber(wStr)
                                    local newH = tonumber(hStr)
                                    if not newW or not newH then
                                        EditorUI.ShowToast("请输入有效数字")
                                        return
                                    end
                                    if MapData.ResizeMap(newW, newH) then
                                        EditorUI.ShowToast(string.format("地图尺寸: %dx%d", MapData.MAP_W, MapData.MAP_H))
                                        updateMapSizeLabel()
                                        IsoCanvas.ResetCamera()
                                    else
                                        EditorUI.ShowToast("尺寸未变化")
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

--- 创建瓦片调色板
local function CreateTilePalette()
    local tileChildren = {}
    for i = 1, MapData.TILE_COUNT do
        tileChildren[i] = CreateTileButton(i)
    end

    -- 瓦片属性编辑容器
    tilePropsContainer = UI.Panel { gap = 4 }

    -- 图片瓦片网格容器
    imagePaletteGrid = UI.SimpleGrid {
        columns = 3,
        gap = 6,
    }

    -- 图片瓦片区域（初始隐藏，扫描后显示）
    imagePaletteSection = UI.Panel {
        id = "imagePaletteSection",
        display = "none",
        gap = 6,
        children = {
            UI.Divider { spacing = 6, color = { 60, 62, 68, 255 } },
            UI.Label {
                text = "图片瓦片",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = { 160, 170, 190, 255 },
            },
            imagePaletteGrid,
        }
    }

    -- 文件夹名输入框 + 扫描按钮
    folderTextField = UI.TextField {
        value = "Tiles",
        placeholder = "输入 assets/ 下的文件夹名",
        fontSize = 11,
        height = 28,
        width = "100%",
        onSubmit = function(self, text)
            if text and text ~= "" then
                performScan(text)
            end
        end,
    }

    return UI.Panel {
        id = "tilePalette",
        width = 250,
        flexShrink = 0,
        backgroundColor = { 36, 38, 44, 255 },
        borderColor = { 60, 62, 68, 255 },
        borderWidth = { 0, 0, 0, 1 },  -- 仅左边框
        padding = 10,
        gap = 8,
        overflow = "scroll",
        children = {
            -- 层级管理面板
            CreateLayerPanel(),
            UI.Divider { spacing = 6, color = { 60, 62, 68, 255 } },
            -- 颜色瓦片
            UI.Label {
                text = "颜色瓦片",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = { 160, 170, 190, 255 },
                marginBottom = 4,
            },
            UI.SimpleGrid {
                columns = 3,
                gap = 6,
                children = tileChildren,
            },
            -- 瓦片属性编辑区
            tilePropsContainer,
            UI.Divider { spacing = 6, color = { 60, 62, 68, 255 } },
            -- 图片资源文件夹
            UI.Label {
                text = "图片资源",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = { 160, 170, 190, 255 },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = { folderTextField },
                    },
                    UI.Button {
                        text = "扫描",
                        width = 42,
                        height = 28,
                        fontSize = 10,
                        backgroundColor = { 59, 130, 246, 255 },
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function()
                            local val = folderTextField:GetValue()
                            if val and val ~= "" then
                                performScan(val)
                            else
                                EditorUI.ShowToast("请输入文件夹名称")
                            end
                        end,
                    },
                },
            },
            imagePaletteSection,
            UI.Divider { spacing = 6, color = { 60, 62, 68, 255 } },
            UI.Label {
                text = "提示",
                fontSize = 11,
                fontWeight = "bold",
                fontColor = { 120, 130, 150, 255 },
                marginBottom = 2,
            },
            UI.Label {
                text = "左键绘制 / 右键平移\nWASD: 平移  滚轮: 缩放\nB: 画笔  E: 橡皮擦\nU: 矩形填充  G: 泼漆  I: 取色\nM: 选区  Ctrl+C: 复制  Ctrl+V: 粘贴\nEsc: 取消选区/粘贴\nH: 切换网格线\nCtrl+Z: 撤销  Ctrl+Y: 重做\nCtrl+S: 保存  Ctrl+L: 加载\nV: 可见  L: 锁定  ^v: 排序\n双击层名/组名: 重命名\nG+: 移入组  G×: 移出组",
                fontSize = 10,
                fontColor = { 100, 110, 130, 255 },
                whiteSpace = "normal",
                lineHeight = 1.6,
            },
        }
    }
end

--- 创建状态栏
local function CreateStatusBar()
    statusLabel = UI.Label {
        text = "坐标: ---  |  工具: 画笔  |  瓦片: 草地",
        fontSize = 11,
        fontColor = { 160, 170, 190, 255 },
    }

    toastLabel = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 100, 255, 100, 255 },
        display = "none",
        marginLeft = 16,
    }

    return UI.Panel {
        id = "statusBar",
        height = 28,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        backgroundColor = { 36, 38, 44, 255 },
        borderColor = { 60, 62, 68, 255 },
        borderWidth = { 1, 0, 0, 0 },  -- 仅上边框
        children = {
            statusLabel,
            toastLabel,
        }
    }
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 构建完整编辑器 UI
---@return table rootWidget
function EditorUI.Build()
    -- 连接 IsoCanvas 回调
    IsoCanvas.getSelectedTool = EditorUI.GetSelectedTool
    IsoCanvas.getSelectedTileID = EditorUI.GetSelectedTileID
    IsoCanvas.onHoverChanged = function(mx, my)
        EditorUI.UpdateStatus(mx, my)
    end
    IsoCanvas.onTilePicked = function(tileID)
        -- 拾色器取色后：设置为当前瓦片，自动切换到画笔
        selectTile(tileID)
        EditorUI.ShowToast("取色: " .. MapData.GetTileType(tileID).name)
    end
    IsoCanvas.onSelectionChanged = function(hasSel)
        if hasSel then
            local _, x1, y1, x2, y2 = IsoCanvas.GetSelection()
            local w = x2 - x1 + 1
            local h = y2 - y1 + 1
            EditorUI.ShowToast(string.format("选区 %dx%d (%d,%d)-(%d,%d)", w, h, x1, y1, x2, y2))
        end
    end

    local canvasPanel = IsoCanvas.CreatePanel(UI)

    local root = UI.Panel {
        id = "editorRoot",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 30, 30, 35, 255 },
        children = {
            -- 顶部工具栏
            CreateToolbar(),
            -- 中间区域（画布 + 调色板）
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "row",
                overflow = "hidden",
                children = {
                    canvasPanel,
                    CreateTilePalette(),
                }
            },
            -- 底部状态栏
            CreateStatusBar(),
        }
    }

    -- 启动后自动加载默认文件夹 "Tiles"
    local defaultFolder = "Tiles"
    local defaultCount = MapData.ScanAndLoadImages(defaultFolder)
    if defaultCount > 0 then
        print(string.format("[EditorUI] 自动加载了 %d 张图片瓦片 (文件夹: %s)", defaultCount, defaultFolder))
    end

    -- 初始化瓦片选中高亮
    updateTileButtons()

    -- 重建图片调色板（自动扫描结果）
    rebuildImagePalette()

    -- 重建层级列表
    rebuildLayerList()

    -- 重建瓦片属性面板
    rebuildTileProps()

    return root
end

--- 显示 Toast 提示（自动消失）
---@param msg string
function EditorUI.ShowToast(msg)
    if toastLabel then
        toastLabel:SetText(msg)
        toastLabel:SetStyle({ display = "flex" })
        toastTimer = 2.0  -- 2秒后消失
    end
    print("[Editor] " .. msg)
end

--- 每帧更新（处理 toast 倒计时）
---@param dt number
function EditorUI.Update(dt)
    if toastTimer > 0 then
        toastTimer = toastTimer - dt
        if toastTimer <= 0 then
            toastTimer = 0
            if toastLabel then
                toastLabel:SetStyle({ display = "none" })
            end
        end
    end
end

--- 处理快捷键
---@param key number 按键码
function EditorUI.HandleKeyDown(key)
    -- P 键：切换游玩模式
    if key == KEY_P then
        togglePlayMode()
        return
    end

    -- 游玩模式下屏蔽编辑快捷键（仅保留 Escape 退出）
    if PlayMode.IsActive() then
        if key == KEY_ESCAPE then
            togglePlayMode()
        end
        return
    end

    local ctrl = input:GetQualifierDown(QUAL_CTRL)

    if ctrl then
        if key == KEY_Z then
            -- Ctrl+Z: 撤销
            if MapData.Undo() then
                EditorUI.ShowToast("撤销")
            else
                EditorUI.ShowToast("无可撤销操作")
            end
        elseif key == KEY_Y then
            -- Ctrl+Y: 重做
            if MapData.Redo() then
                EditorUI.ShowToast("重做")
            else
                EditorUI.ShowToast("无可重做操作")
            end
        elseif key == KEY_S then
            showSaveModal()
        elseif key == KEY_L then
            showLoadModal()
        elseif key == KEY_C then
            -- Ctrl+C: 复制选区
            local hasSel, x1, y1, x2, y2 = IsoCanvas.GetSelection()
            if hasSel then
                local count = MapData.CopyRegion(x1, y1, x2, y2)
                if count > 0 then
                    EditorUI.ShowToast(string.format("已复制 %d 格", count))
                else
                    EditorUI.ShowToast("选区内无瓦片")
                end
            else
                EditorUI.ShowToast("请先框选区域")
            end
        elseif key == KEY_V then
            -- Ctrl+V: 粘贴
            if MapData.HasClipboard() then
                IsoCanvas.EnterPasteMode()
                local w, h = MapData.GetClipboardSize()
                EditorUI.ShowToast(string.format("粘贴模式 (%dx%d) - 点击放置", w, h))
            else
                EditorUI.ShowToast("剪贴板为空")
            end
        end
    else
        if key == KEY_B then
            selectTool("brush")
        elseif key == KEY_E then
            selectTool("eraser")
        elseif key == KEY_U then
            selectTool("fill")
        elseif key == KEY_G then
            selectTool("flood")
        elseif key == KEY_I then
            selectTool("picker")
        elseif key == KEY_M then
            selectTool("select")
        elseif key == KEY_H then
            -- H: 切换网格显隐
            MapData.SetGridVisible(nil)
            updateGridButton()
            EditorUI.ShowToast(MapData.IsGridVisible() and "网格已显示" or "网格已隐藏")
        elseif key == KEY_ESCAPE then
            -- Escape: 取消粘贴模式或清除选区
            if IsoCanvas.IsPasteMode() then
                IsoCanvas.ExitPasteMode()
                EditorUI.ShowToast("已取消粘贴")
            elseif IsoCanvas.GetSelection() then
                IsoCanvas.ClearSelection()
                EditorUI.ShowToast("已取消选区")
            end
        end
    end
end

local PAN_SPEED = 300  -- 像素/秒

--- 每帧处理 WASD 键盘平移（游玩模式时路由到角色移动）
---@param dt number
function EditorUI.HandleWASDPan(dt)
    if PlayMode.IsActive() then
        -- 游玩模式：WASD 控制角色移动
        PlayMode.Update(dt)
        -- 相机跟随角色
        local px, py = PlayMode.GetPosition()
        IsoCanvas.FollowTarget(px, py, dt)
        -- 更新状态栏（显示角色坐标）
        EditorUI.UpdateStatus()
        return
    end

    local dx = 0
    local dy = 0
    if input:GetKeyDown(KEY_W) then dy = dy + 1 end
    if input:GetKeyDown(KEY_S) then dy = dy - 1 end
    if input:GetKeyDown(KEY_A) then dx = dx + 1 end
    if input:GetKeyDown(KEY_D) then dx = dx - 1 end

    if dx ~= 0 or dy ~= 0 then
        IsoCanvas.Pan(dx * PAN_SPEED * dt, dy * PAN_SPEED * dt)
    end
end

return EditorUI
