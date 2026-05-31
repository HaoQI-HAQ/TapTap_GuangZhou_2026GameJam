-- ============================================================================
-- IsoCanvas.lua — 等距画布自定义 Widget（渲染 + 交互）
-- ============================================================================

local MapData = require("MapData")
local PlayMode = require("PlayMode")

local IsoCanvas = {}

-- 视角模式："iso" = 等距菱形视角, "topdown" = 正视45度视角
local viewMode = "iso"

-- 等距投影常量（基础尺寸，实际渲染乘以 zoom）
local BASE_TILE_W_HALF = 32   -- 基础半宽
local BASE_TILE_H_HALF = 16   -- 基础半高

-- 正视45度常量（基础格子尺寸，正方形）
local BASE_TD_TILE_W = 40     -- 正视瓦片宽度
local BASE_TD_TILE_H = 40     -- 正视瓦片高度（正方形）

-- 相机状态
local camX = 0
local camY = 0
local canvasW = 0   -- 画布宽度（每帧更新，供 FollowTarget 使用）
local canvasH = 0   -- 画布高度
local zoom = 1.0           -- 缩放倍率
local ZOOM_MIN = 0.3
local ZOOM_MAX = 3.0
local ZOOM_STEP = 0.15     -- 每次滚轮缩放步长

-- 缩放后的半宽/半高（每帧根据 zoom 更新）
local tileWH = BASE_TILE_W_HALF
local tileHH = BASE_TILE_H_HALF

-- 缩放后的正视格子尺寸
local tdTileW = BASE_TD_TILE_W
local tdTileH = BASE_TD_TILE_H

--- 更新缩放后的瓦片尺寸
local function updateZoomedSize()
    tileWH = BASE_TILE_W_HALF * zoom
    tileHH = BASE_TILE_H_HALF * zoom
    tdTileW = BASE_TD_TILE_W * zoom
    tdTileH = BASE_TD_TILE_H * zoom
end

-- 图片缓存（imagePath → nvgHandle）
local imageCache = {}

-- 交互状态
local hoverMapX = -1   -- 鼠标悬停的地图坐标
local hoverMapY = -1
local isDrawing = false -- 左键按下持续绘制中
local lastPointerButton = -1  -- 追踪最后按下的按钮

-- Box Fill 拖拽状态
local boxFillStartX = -1
local boxFillStartY = -1
local boxFillEndX = -1
local boxFillEndY = -1
local isBoxDragging = false

-- Select 工具状态
local selectStartX = -1
local selectStartY = -1
local selectEndX = -1
local selectEndY = -1
local isSelectDragging = false
local hasSelection = false      -- 当前是否有选区
local selMinX, selMinY, selMaxX, selMaxY = 0, 0, 0, 0  -- 确定后的选区范围

-- 粘贴预览状态
local isPasteMode = false       -- 是否处于粘贴预览模式

-- 外部引用（由 EditorUI 设置）
IsoCanvas.getSelectedTool = nil    -- function() → "brush" | "eraser" | "fill" | "picker" | "flood" | "select"
IsoCanvas.getSelectedTileID = nil  -- function() → number
IsoCanvas.onHoverChanged = nil     -- function(mx, my)
IsoCanvas.onTilePicked = nil       -- function(tileID) 拾色器回调
IsoCanvas.onSelectionChanged = nil -- function(hasSelection) 选区变化回调

-- ============================================================================
-- 坐标转换
-- ============================================================================

--- 地图坐标 → 屏幕坐标（瓦片中心点，相对于画布原点）
---@param mx number 地图 X (1-based)
---@param my number 地图 Y (1-based)
---@return number screenX, number screenY
local function mapToScreen(mx, my)
    local ix = mx - 1
    local iy = my - 1
    if viewMode == "topdown" then
        -- 正视45度：简单网格排列，(0,0)在左上角
        local sx = ix * tdTileW + camX
        local sy = iy * tdTileH + camY
        return sx, sy
    else
        -- 等距菱形
        local sx = (ix - iy) * tileWH + camX
        local sy = (ix + iy) * tileHH + camY
        return sx, sy
    end
end

--- 屏幕坐标 → 地图坐标 (1-based)
---@param sx number 相对画布原点的 X
---@param sy number 相对画布原点的 Y
---@return number mapX, number mapY (1-based, 可能越界需检查)
local function screenToMap(sx, sy)
    local relX = sx - camX
    local relY = sy - camY
    if viewMode == "topdown" then
        return math.floor(relX / tdTileW) + 1, math.floor(relY / tdTileH) + 1
    else
        local fmx = (relX / tileWH + relY / tileHH) / 2
        local fmy = (relY / tileHH - relX / tileWH) / 2
        return math.floor(fmx) + 1, math.floor(fmy) + 1
    end
end

-- ============================================================================
-- 绘制辅助
-- ============================================================================

--- 绘制填充菱形（使用当前缩放尺寸）
local function drawDiamond(nvg, cx, cy, r, g, b, a)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - tileHH)
    nvgLineTo(nvg, cx + tileWH, cy)
    nvgLineTo(nvg, cx, cy + tileHH)
    nvgLineTo(nvg, cx - tileWH, cy)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(r, g, b, a))
    nvgFill(nvg)
end

--- 绘制菱形描边（使用当前缩放尺寸）
local function strokeDiamond(nvg, cx, cy, r, g, b, a, width)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - tileHH)
    nvgLineTo(nvg, cx + tileWH, cy)
    nvgLineTo(nvg, cx, cy + tileHH)
    nvgLineTo(nvg, cx - tileWH, cy)
    nvgClosePath(nvg)
    nvgStrokeColor(nvg, nvgRGBA(r, g, b, a))
    nvgStrokeWidth(nvg, width or 1)
    nvgStroke(nvg)
end

--- 绘制填充矩形（正视45度模式）
local function drawTDRect(nvg, cx, cy, r, g, b, a)
    nvgBeginPath(nvg)
    nvgRect(nvg, cx - tdTileW / 2, cy - tdTileH / 2, tdTileW, tdTileH)
    nvgFillColor(nvg, nvgRGBA(r, g, b, a))
    nvgFill(nvg)
end

--- 绘制矩形描边（正视45度模式）
local function strokeTDRect(nvg, cx, cy, r, g, b, a, width)
    nvgBeginPath(nvg)
    nvgRect(nvg, cx - tdTileW / 2, cy - tdTileH / 2, tdTileW, tdTileH)
    nvgStrokeColor(nvg, nvgRGBA(r, g, b, a))
    nvgStrokeWidth(nvg, width or 1)
    nvgStroke(nvg)
end

--- 懒加载图片，返回 NanoVG 图片 handle（0 = 加载失败）
---@param nvg userdata NanoVG 上下文
---@param imagePath string 资源路径（相对于 assets/）
---@return number handle
local function getOrLoadImage(nvg, imagePath)
    if imageCache[imagePath] then return imageCache[imagePath] end
    local handle = nvgCreateImage(nvg, imagePath, 0)
    imageCache[imagePath] = handle
    if handle == 0 then
        print("[IsoCanvas] 图片加载失败: " .. imagePath)
    end
    return handle
end

--- 图片尺寸缓存（handle → { w, h }）
local imageSizeCache = {}

--- 绘制图片瓦片（保持原始比例，底部锚定到菱形底点）
---@param nvg userdata NanoVG 上下文
---@param cx number 菱形中心 X
---@param cy number 菱形中心 Y
---@param imagePath string 图片资源路径
local function drawImageTile(nvg, cx, cy, imagePath)
    local handle = getOrLoadImage(nvg, imagePath)
    if handle == 0 then
        drawDiamond(nvg, cx, cy, 100, 100, 100, 200)
        return
    end

    -- 获取图片原始尺寸（缓存）
    if not imageSizeCache[handle] then
        local w, h = nvgImageSize(nvg, handle)
        imageSizeCache[handle] = { w = w, h = h }
    end
    local imgInfo = imageSizeCache[handle]

    -- 目标宽度 = 菱形全宽
    local drawW = tileWH * 2
    -- 按比例计算高度
    local scale = drawW / imgInfo.w
    local drawH = imgInfo.h * scale

    -- 底部锚定：图片底边对齐菱形底点 (cx, cy + tileHH)
    local drawX = cx - drawW / 2
    local drawY = (cy + tileHH) - drawH

    -- 以矩形绘制图片（不做菱形裁剪，让 PNG 透明度自然生效）
    local paint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, handle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, drawX, drawY, drawW, drawH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

--- 绘制图片瓦片 - 正视45度模式（底部锚定到格子底边）
---@param nvg userdata NanoVG 上下文
---@param cx number 格子中心 X
---@param cy number 格子中心 Y
---@param imagePath string 图片资源路径
local function drawImageTileTD(nvg, cx, cy, imagePath)
    local handle = getOrLoadImage(nvg, imagePath)
    if handle == 0 then
        drawTDRect(nvg, cx, cy, 100, 100, 100, 200)
        return
    end
    if not imageSizeCache[handle] then
        local w, h = nvgImageSize(nvg, handle)
        imageSizeCache[handle] = { w = w, h = h }
    end
    local imgInfo = imageSizeCache[handle]
    -- 目标宽度 = 格子宽
    local drawW = tdTileW
    local scale = drawW / imgInfo.w
    local drawH = imgInfo.h * scale
    -- 底部锚定
    local drawX = cx - drawW / 2
    local drawY = (cy + tdTileH / 2) - drawH
    local paint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, handle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, drawX, drawY, drawW, drawH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

--- 通用：根据当前视角绘制填充瓦片
local function drawTileShape(nvg, cx, cy, r, g, b, a)
    if viewMode == "topdown" then
        drawTDRect(nvg, cx, cy, r, g, b, a)
    else
        drawDiamond(nvg, cx, cy, r, g, b, a)
    end
end

--- 通用：根据当前视角绘制描边瓦片
local function strokeTileShape(nvg, cx, cy, r, g, b, a, width)
    if viewMode == "topdown" then
        strokeTDRect(nvg, cx, cy, r, g, b, a, width)
    else
        strokeDiamond(nvg, cx, cy, r, g, b, a, width)
    end
end

--- 通用：根据当前视角绘制图片瓦片
local function drawImageTileAuto(nvg, cx, cy, imagePath)
    if viewMode == "topdown" then
        drawImageTileTD(nvg, cx, cy, imagePath)
    else
        drawImageTile(nvg, cx, cy, imagePath)
    end
end

-- ============================================================================
-- 交互辅助
-- ============================================================================

--- 处理绘制操作（单格）
local function performPaint(mx, my)
    if MapData.IsPreviewMode() then return end
    if not MapData.InBounds(mx, my) then return end
    -- 锁定层拒绝编辑（MapData.SetTile 内部也检查，这里提前返回避免无谓调用）
    if MapData.IsLayerLocked(MapData.GetCurrentLayer()) then return end

    local tool = IsoCanvas.getSelectedTool and IsoCanvas.getSelectedTool() or "brush"
    if tool == "eraser" then
        MapData.SetTile(mx, my, 0)
    elseif tool == "brush" then
        local tileID = IsoCanvas.getSelectedTileID and IsoCanvas.getSelectedTileID() or 1
        MapData.SetTile(mx, my, tileID)
    end
end

--- 执行 Box Fill（矩形填充）
local function performBoxFill(x1, y1, x2, y2)
    if MapData.IsPreviewMode() then return end
    if MapData.IsLayerLocked(MapData.GetCurrentLayer()) then return end

    local minX = math.min(x1, x2)
    local maxX = math.max(x1, x2)
    local minY = math.min(y1, y2)
    local maxY = math.max(y1, y2)

    -- 限制在地图范围内
    minX = math.max(1, minX)
    minY = math.max(1, minY)
    maxX = math.min(MapData.MAP_W, maxX)
    maxY = math.min(MapData.MAP_H, maxY)

    local tileID = IsoCanvas.getSelectedTileID and IsoCanvas.getSelectedTileID() or 1

    MapData.BeginBatch()
    for y = minY, maxY do
        for x = minX, maxX do
            MapData.SetTile(x, y, tileID)
        end
    end
    MapData.CommitBatch()
end

--- 执行拾色器（取当前层指定格的瓦片）
local function performPick(mx, my)
    if MapData.IsPreviewMode() then return end
    if not MapData.InBounds(mx, my) then return end

    local tileID = MapData.GetTile(mx, my)
    if tileID > 0 and IsoCanvas.onTilePicked then
        IsoCanvas.onTilePicked(tileID)
    end
end

--- 执行洪水填充
local function performFloodFill(mx, my)
    if MapData.IsPreviewMode() then return end
    if not MapData.InBounds(mx, my) then return end
    if MapData.IsLayerLocked(MapData.GetCurrentLayer()) then return end

    local tileID = IsoCanvas.getSelectedTileID and IsoCanvas.getSelectedTileID() or 1
    local count = MapData.FloodFill(mx, my, tileID)
    if count > 0 then
        print(string.format("[IsoCanvas] 洪水填充: %d 格", count))
    end
end

--- 计算画布原点偏移
---@param layout table {x, y, w, h}
---@return number ox, number oy
local function getCanvasOrigin(layout)
    if viewMode == "topdown" then
        -- 正视模式：原点在左上角偏移一点（留边距）
        return layout.x + 40, layout.y + 40
    else
        -- 等距模式：原点在画布水平中心
        return layout.x + layout.w / 2, layout.y + 80
    end
end

--- 将全局指针坐标转换为地图坐标
---@param globalX number
---@param globalY number
---@param layout table {x, y, w, h}
---@return number mapX, number mapY
local function pointerToMap(globalX, globalY, layout)
    local ox, oy = getCanvasOrigin(layout)
    local localX = globalX - ox
    local localY = globalY - oy
    return screenToMap(localX, localY)
end

-- ============================================================================
-- 自定义 Widget 创建
-- ============================================================================

--- 创建画布 Widget（使用 Widget:Extend 自定义渲染）
---@param UI table UI 模块
---@return table Widget
function IsoCanvas.CreatePanel(UI)
    local Widget = require("urhox-libs/UI/Core/Widget")

    -- 创建自定义 Widget 类
    local CanvasWidget = Widget:Extend("IsoCanvasWidget")

    --- 覆写 Render 方法 —— 绘制等距地图
    function CanvasWidget:Render(nvg)
        -- 更新缩放尺寸
        updateZoomedSize()

        -- 先渲染背景
        self:RenderFullBackground(nvg)

        local l = self:GetAbsoluteLayout()
        canvasW = l.w
        canvasH = l.h

        nvgSave(nvg)
        nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

        -- 绘制原点
        local ox, oy = getCanvasOrigin(l)

        -- 当前编辑层索引与预览模式
        local curLayerIdx = MapData.GetCurrentLayer()
        local layerCount = MapData.GetLayerCount()
        local isPreview = MapData.IsPreviewMode()

        -- 游玩模式：获取角色浮点位置（用于脚底点排序）
        local playPX, playPY
        if PlayMode.IsActive() then
            playPX, playPY = PlayMode.GetPosition()
        end

        -- 角色绘制辅助函数（使用图片）
        local function drawCharacter(charOx, charOy)
            local psx, psy = mapToScreen(playPX, playPY)
            local pcx = psx + charOx
            local pcy = psy + charOy

            local charImg = PlayMode.charImage
            local handle = getOrLoadImage(nvg, charImg)

            if handle ~= 0 then
                -- 获取图片尺寸
                if not imageSizeCache[handle] then
                    local w, h = nvgImageSize(nvg, handle)
                    imageSizeCache[handle] = { w = w, h = h }
                end
                local imgInfo = imageSizeCache[handle]

                if viewMode == "topdown" then
                    -- 正视模式：角色宽度 = 格子宽度 * 0.7
                    local drawW = tdTileW * 0.7
                    local scale = drawW / imgInfo.w
                    local drawH = imgInfo.h * scale
                    local drawX = pcx - drawW / 2
                    local footY = pcy + tdTileH / 2  -- 格子底边
                    local drawY = footY - drawH       -- 底部锚定到格子底边

                    -- 阴影
                    nvgBeginPath(nvg)
                    nvgEllipse(nvg, pcx, footY - 2, drawW * 0.4, drawW * 0.12)
                    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 50))
                    nvgFill(nvg)

                    -- 角色图片
                    local paint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, handle, 1.0)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, drawX, drawY, drawW, drawH)
                    nvgFillPaint(nvg, paint)
                    nvgFill(nvg)
                else
                    -- 等距模式：角色宽度 = 菱形全宽 * 0.7
                    local drawW = tileWH * 2 * 0.7
                    local scale = drawW / imgInfo.w
                    local drawH = imgInfo.h * scale
                    local drawX = pcx - drawW / 2
                    local drawY = (pcy + tileHH) - drawH  -- 底部锚定到菱形底点

                    -- 阴影
                    nvgBeginPath(nvg)
                    nvgEllipse(nvg, pcx, pcy + tileHH - 2, drawW * 0.35, tileHH * 0.2)
                    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 50))
                    nvgFill(nvg)

                    -- 角色图片
                    local paint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, handle, 1.0)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, drawX, drawY, drawW, drawH)
                    nvgFillPaint(nvg, paint)
                    nvgFill(nvg)
                end
            else
                -- 图片加载失败时的备用：简单圆形
                local pc = PlayMode.playerColor
                nvgBeginPath(nvg)
                nvgCircle(nvg, pcx, pcy, tileHH * 0.4)
                nvgFillColor(nvg, nvgRGBA(pc[1], pc[2], pc[3], 230))
                nvgFill(nvg)
            end
        end

        -- ============================================================
        -- Pass 1: 地面层 (layer 1) — 对角线迭代，永远在最底
        -- ============================================================
        local layer1Visible = MapData.IsLayerVisible(1)
        for diag = 0, MapData.MAP_W + MapData.MAP_H - 2 do
            for ix = 0, diag do
                local iy = diag - ix
                if ix < MapData.MAP_W and iy < MapData.MAP_H then
                    local mx = ix + 1
                    local my = iy + 1
                    local sx, sy = mapToScreen(mx, my)
                    local cx = sx + ox
                    local cy = sy + oy

                    -- 仅绘制 layer 1
                    if layer1Visible then
                        local tileID = MapData.GetTile(mx, my, 1)
                        if tileID > 0 then
                            local layerOpacity = MapData.GetLayerOpacity(1)
                            local alpha = isPreview and layerOpacity or ((1 ~= curLayerIdx) and (layerOpacity * 0.5) or layerOpacity)
                            nvgGlobalAlpha(nvg, alpha)

                            local tt = MapData.GetTileType(tileID)
                            if tt.imagePath then
                                drawImageTileAuto(nvg, cx, cy, tt.imagePath)
                            else
                                local c = tt.color
                                drawTileShape(nvg, cx, cy, c[1], c[2], c[3], c[4])
                            end
                            nvgGlobalAlpha(nvg, 1.0)
                        end
                    end

                    -- 网格线
                    if MapData.IsGridVisible() and not isPreview then
                        strokeTileShape(nvg, cx, cy, 180, 180, 180, 120, 1.0)
                    end
                end
            end
        end

        -- ============================================================
        -- Pass 2: 物体层 (layer 2+) + 角色 — 脚底点排序
        -- 排序键：footY → footX → sortPriority → layerIdx
        -- footY = 菱形底顶点 Y（物体落地接触点）
        -- ============================================================
        local sortList = {}
        local sortN = 0

        -- 收集 layer 2+ 非空瓦片
        for li = 2, layerCount do
            if not MapData.IsLayerVisible(li) then goto continue_sort_layer end
            local layerOpacity = MapData.GetLayerOpacity(li)
            local alpha = isPreview and layerOpacity or ((li ~= curLayerIdx) and (layerOpacity * 0.5) or layerOpacity)

            for my = 1, MapData.MAP_H do
                for mx = 1, MapData.MAP_W do
                    local tileID = MapData.GetTile(mx, my, li)
                    if tileID > 0 then
                        local sx, sy = mapToScreen(mx, my)
                        local cx = sx + ox
                        local cy = sy + oy
                        local footYVal = (viewMode == "topdown") and (cy + tdTileH / 2) or (cy + tileHH)
                        sortN = sortN + 1
                        sortList[sortN] = {
                            t = "tile",
                            cx = cx, cy = cy,
                            footY = footYVal,
                            footX = cx,
                            pri = 0,
                            li = li,
                            id = tileID,
                            alpha = alpha,
                        }
                    end
                end
            end
            ::continue_sort_layer::
        end

        -- 加入角色
        if playPX then
            local psx, psy = mapToScreen(playPX, playPY)
            local charFootY = (viewMode == "topdown") and (psy + oy + tdTileH / 2) or (psy + oy + tileHH)
            sortN = sortN + 1
            sortList[sortN] = {
                t = "char",
                footY = charFootY,
                footX = psx + ox,
                pri = 1,
                li = 0,
            }
        end

        -- 稳定排序：footY, footX, sortPriority, layerIdx
        table.sort(sortList, function(a, b)
            if a.footY ~= b.footY then return a.footY < b.footY end
            if a.footX ~= b.footX then return a.footX < b.footX end
            if a.pri ~= b.pri then return a.pri < b.pri end
            return a.li < b.li
        end)

        -- 按排序顺序绘制
        for i = 1, sortN do
            local item = sortList[i]
            if item.t == "char" then
                drawCharacter(ox, oy)
            else
                nvgGlobalAlpha(nvg, item.alpha)
                local tt = MapData.GetTileType(item.id)
                if tt.imagePath then
                    drawImageTileAuto(nvg, item.cx, item.cy, tt.imagePath)
                else
                    local c = tt.color
                    drawTileShape(nvg, item.cx, item.cy, c[1], c[2], c[3], c[4])
                end
                nvgGlobalAlpha(nvg, 1.0)
            end
        end

        -- 2. Box Fill 拖拽预览
        if isBoxDragging and not isPreview then
            local minX = math.max(1, math.min(boxFillStartX, boxFillEndX))
            local maxX = math.min(MapData.MAP_W, math.max(boxFillStartX, boxFillEndX))
            local minY = math.max(1, math.min(boxFillStartY, boxFillEndY))
            local maxY = math.min(MapData.MAP_H, math.max(boxFillStartY, boxFillEndY))

            for fy = minY, maxY do
                for fx = minX, maxX do
                    local bsx, bsy = mapToScreen(fx, fy)
                    local bcx = bsx + ox
                    local bcy = bsy + oy
                    drawTileShape(nvg, bcx, bcy, 59, 130, 246, 80)
                    strokeTileShape(nvg, bcx, bcy, 59, 130, 246, 200, 1.5)
                end
            end
        end

        -- 3. 绘制鼠标悬停高亮（预览模式下不显示）
        if not isPreview and not isBoxDragging and MapData.InBounds(hoverMapX, hoverMapY) then
            local sx, sy = mapToScreen(hoverMapX, hoverMapY)
            local cx = sx + ox
            local cy = sy + oy

            local tool = IsoCanvas.getSelectedTool and IsoCanvas.getSelectedTool() or "brush"
            if tool == "eraser" then
                drawTileShape(nvg, cx, cy, 255, 80, 80, 60)
                strokeTileShape(nvg, cx, cy, 255, 80, 80, 180, 2)
            elseif tool == "picker" then
                drawTileShape(nvg, cx, cy, 255, 200, 50, 60)
                strokeTileShape(nvg, cx, cy, 255, 200, 50, 220, 2)
            elseif tool == "fill" then
                drawTileShape(nvg, cx, cy, 59, 130, 246, 50)
                strokeTileShape(nvg, cx, cy, 59, 130, 246, 180, 2)
            elseif tool == "flood" then
                drawTileShape(nvg, cx, cy, 16, 185, 129, 70)
                strokeTileShape(nvg, cx, cy, 16, 185, 129, 220, 2)
            elseif tool == "select" then
                drawTileShape(nvg, cx, cy, 255, 215, 0, 50)
                strokeTileShape(nvg, cx, cy, 255, 215, 0, 180, 2)
            else
                drawTileShape(nvg, cx, cy, 255, 255, 255, 40)
                strokeTileShape(nvg, cx, cy, 255, 255, 255, 180, 2)
            end
        end

        -- 4. Select 拖拽预览
        if isSelectDragging and not isPreview then
            local sMinX = math.max(1, math.min(selectStartX, selectEndX))
            local sMaxX = math.min(MapData.MAP_W, math.max(selectStartX, selectEndX))
            local sMinY = math.max(1, math.min(selectStartY, selectEndY))
            local sMaxY = math.min(MapData.MAP_H, math.max(selectStartY, selectEndY))
            for fy = sMinY, sMaxY do
                for fx = sMinX, sMaxX do
                    local bsx, bsy = mapToScreen(fx, fy)
                    local bcx = bsx + ox
                    local bcy = bsy + oy
                    drawTileShape(nvg, bcx, bcy, 255, 215, 0, 50)
                    strokeTileShape(nvg, bcx, bcy, 255, 215, 0, 160, 1.5)
                end
            end
        end

        -- 5. 已确定的选区边框
        if hasSelection and not isSelectDragging and not isPreview then
            for fy = selMinY, selMaxY do
                for fx = selMinX, selMaxX do
                    local bsx, bsy = mapToScreen(fx, fy)
                    local bcx = bsx + ox
                    local bcy = bsy + oy
                    drawTileShape(nvg, bcx, bcy, 255, 215, 0, 30)
                end
            end
            for fy = selMinY, selMaxY do
                for fx = selMinX, selMaxX do
                    if fx == selMinX or fx == selMaxX or fy == selMinY or fy == selMaxY then
                        local bsx, bsy = mapToScreen(fx, fy)
                        local bcx = bsx + ox
                        local bcy = bsy + oy
                        strokeTileShape(nvg, bcx, bcy, 255, 215, 0, 200, 1.5)
                    end
                end
            end
        end

        -- 6. 粘贴预览
        if isPasteMode and MapData.HasClipboard() and MapData.InBounds(hoverMapX, hoverMapY) and not isPreview then
            local cw, ch = MapData.GetClipboardSize()
            if cw and ch then
                for dy = 1, ch do
                    for dx = 1, cw do
                        local tx = hoverMapX + dx - 1
                        local ty = hoverMapY + dy - 1
                        if MapData.InBounds(tx, ty) then
                            local bsx, bsy = mapToScreen(tx, ty)
                            local bcx = bsx + ox
                            local bcy = bsy + oy
                            drawTileShape(nvg, bcx, bcy, 100, 200, 255, 60)
                            strokeTileShape(nvg, bcx, bcy, 100, 200, 255, 180, 1.5)
                        end
                    end
                end
            end
        end

        -- 7. 缩放比例指示（非 1.0 时显示）
        if math.abs(zoom - 1.0) > 0.01 then
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 12)
            nvgFillColor(nvg, nvgRGBA(200, 200, 200, 160))
            nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgText(nvg, l.x + l.w - 8, l.y + l.h - 6,
                string.format("%.0f%%", zoom * 100))
        end

        nvgRestore(nvg)
    end

    --- 覆写 OnWheel —— 滚轮缩放（向鼠标位置缩放）
    function CanvasWidget:OnWheel(dx, dy)
        local l = self:GetAbsoluteLayout()
        local ox, oy = getCanvasOrigin(l)

        -- 鼠标在画布坐标系中的位置
        local mouseX = input:GetMousePosition().x
        local mouseY = input:GetMousePosition().y
        local localMX = mouseX - ox
        local localMY = mouseY - oy

        -- 缩放前：鼠标指向的世界坐标
        local worldX = (localMX - camX) / zoom
        local worldY = (localMY - camY) / zoom

        -- 更新缩放
        local oldZoom = zoom
        if dy > 0 then
            zoom = math.min(ZOOM_MAX, zoom + ZOOM_STEP)
        elseif dy < 0 then
            zoom = math.max(ZOOM_MIN, zoom - ZOOM_STEP)
        end

        -- 缩放后：调整相机使鼠标仍指向同一世界坐标
        camX = localMX - worldX * zoom
        camY = localMY - worldY * zoom

        updateZoomedSize()
    end

    -- 初始化相机
    camX = 0
    camY = 0

    -- 创建 Widget 实例
    local canvasPanel = CanvasWidget {
        id = "isoCanvas",
        flexGrow = 1,
        backgroundColor = { 30, 30, 35, 255 },

        onPointerDown = function(event, widget)
            local layout = widget:GetAbsoluteLayout()
            lastPointerButton = event.button

            -- 右键/中键 → 不处理绘制，留给 pan 手势
            if event.button == MOUSEB_RIGHT or event.button == MOUSEB_MIDDLE then
                return
            end

            -- 左键
            if event.button == MOUSEB_LEFT then
                local mx, my = pointerToMap(event.x, event.y, layout)
                local tool = IsoCanvas.getSelectedTool and IsoCanvas.getSelectedTool() or "brush"

                if isPasteMode then
                    -- 粘贴模式下左键点击 → 执行粘贴
                    local count = MapData.PasteRegion(mx, my)
                    if count > 0 then
                        print(string.format("[IsoCanvas] 粘贴: %d 格", count))
                    end
                    isPasteMode = false
                elseif tool == "select" then
                    -- 选区工具：开始拖拽
                    isSelectDragging = true
                    selectStartX = mx
                    selectStartY = my
                    selectEndX = mx
                    selectEndY = my
                    hasSelection = false
                elseif tool == "picker" then
                    -- 拾色器：单击取色
                    performPick(mx, my)
                elseif tool == "flood" then
                    -- 洪水填充：单击填充连通区域
                    performFloodFill(mx, my)
                elseif tool == "fill" then
                    -- Box Fill：记录起点，开始拖拽
                    isBoxDragging = true
                    boxFillStartX = mx
                    boxFillStartY = my
                    boxFillEndX = mx
                    boxFillEndY = my
                else
                    -- 画笔/橡皮擦：开始批量操作
                    isDrawing = true
                    MapData.BeginBatch()
                    performPaint(mx, my)
                end
            end
        end,

        onPointerMove = function(event, widget)
            local layout = widget:GetAbsoluteLayout()
            local mx, my = pointerToMap(event.x, event.y, layout)

            -- 更新悬停坐标
            if mx ~= hoverMapX or my ~= hoverMapY then
                hoverMapX = mx
                hoverMapY = my
                if IsoCanvas.onHoverChanged then
                    IsoCanvas.onHoverChanged(mx, my)
                end
            end

            -- 持续绘制（仅左键按下时）
            if isDrawing then
                performPaint(mx, my)
            end

            -- Box Fill 拖拽更新终点
            if isBoxDragging then
                boxFillEndX = mx
                boxFillEndY = my
            end

            -- Select 拖拽更新终点
            if isSelectDragging then
                selectEndX = mx
                selectEndY = my
            end
        end,

        onPointerUp = function(event, widget)
            if event.button == MOUSEB_LEFT then
                if isDrawing then
                    -- 画笔/橡皮擦拖拽结束，提交批量操作
                    MapData.CommitBatch()
                    isDrawing = false
                end
                if isBoxDragging then
                    -- Box Fill 拖拽结束，执行填充
                    performBoxFill(boxFillStartX, boxFillStartY, boxFillEndX, boxFillEndY)
                    isBoxDragging = false
                    boxFillStartX = -1
                    boxFillStartY = -1
                    boxFillEndX = -1
                    boxFillEndY = -1
                end
                if isSelectDragging then
                    -- Select 拖拽结束，确定选区
                    isSelectDragging = false
                    selMinX = math.max(1, math.min(selectStartX, selectEndX))
                    selMaxX = math.min(MapData.MAP_W, math.max(selectStartX, selectEndX))
                    selMinY = math.max(1, math.min(selectStartY, selectEndY))
                    selMaxY = math.min(MapData.MAP_H, math.max(selectStartY, selectEndY))
                    hasSelection = (selMinX <= selMaxX and selMinY <= selMaxY)
                    if IsoCanvas.onSelectionChanged then
                        IsoCanvas.onSelectionChanged(hasSelection)
                    end
                end
            end
            if event.button == MOUSEB_RIGHT or event.button == MOUSEB_MIDDLE then
                lastPointerButton = -1
            end
        end,

        onPointerLeave = function(event, widget)
            hoverMapX = -1
            hoverMapY = -1
            if isDrawing then
                MapData.CommitBatch()
                isDrawing = false
            end
            if isBoxDragging then
                isBoxDragging = false
                boxFillStartX = -1
                boxFillStartY = -1
            end
            if isSelectDragging then
                isSelectDragging = false
            end
            lastPointerButton = -1
            if IsoCanvas.onHoverChanged then
                IsoCanvas.onHoverChanged(-1, -1)
            end
        end,

        -- 平移手势：仅右键/中键拖拽时响应
        onPanStart = function(event, widget)
            -- 如果左键在绘制中，不要平移
            if isDrawing then return false end
            return lastPointerButton == MOUSEB_RIGHT or lastPointerButton == MOUSEB_MIDDLE
        end,

        onPanMove = function(event, widget)
            if not isDrawing then
                camX = camX + event.deltaX
                camY = camY + event.deltaY
            end
        end,
    }

    return canvasPanel
end

--- 获取当前悬停坐标
function IsoCanvas.GetHoverCoord()
    return hoverMapX, hoverMapY
end

--- 重置相机到中心
function IsoCanvas.ResetCamera()
    camX = 0
    camY = 0
    zoom = 1.0
    updateZoomedSize()
end

--- 获取当前缩放倍率
---@return number
function IsoCanvas.GetZoom()
    return zoom
end

--- 平移相机（供 WASD 键盘调用）
---@param dx number X 方向偏移量
---@param dy number Y 方向偏移量
function IsoCanvas.Pan(dx, dy)
    camX = camX + dx
    camY = camY + dy
end

--- 获取当前选区范围
---@return boolean hasSelection, number minX, number minY, number maxX, number maxY
function IsoCanvas.GetSelection()
    return hasSelection, selMinX, selMinY, selMaxX, selMaxY
end

--- 清除选区
function IsoCanvas.ClearSelection()
    hasSelection = false
    selMinX, selMinY, selMaxX, selMaxY = 0, 0, 0, 0
    if IsoCanvas.onSelectionChanged then
        IsoCanvas.onSelectionChanged(false)
    end
end

--- 进入粘贴预览模式
function IsoCanvas.EnterPasteMode()
    isPasteMode = true
end

--- 退出粘贴预览模式
function IsoCanvas.ExitPasteMode()
    isPasteMode = false
end

--- 是否处于粘贴预览模式
---@return boolean
function IsoCanvas.IsPasteMode()
    return isPasteMode
end

--- 将相机平滑移向目标地图坐标（使角色保持在画布中心）
---@param targetMX number 目标地图 X
---@param targetMY number 目标地图 Y
---@param dt number 帧间隔
function IsoCanvas.FollowTarget(targetMX, targetMY, dt)
    local ix = targetMX - 1
    local iy = targetMY - 1

    local targetCamX, targetCamY
    if viewMode == "topdown" then
        -- 正视模式：原点偏移 40px，角色居中
        targetCamX = -ix * tdTileW + (canvasW / 2 - 40)
        targetCamY = -iy * tdTileH + (canvasH / 2 - 40)
    else
        -- 等距模式
        targetCamX = -(ix - iy) * tileWH
        targetCamY = -(ix + iy) * tileHH + (canvasH / 2 - 80)
    end

    -- 平滑插值
    local lerp = math.min(1.0, 5.0 * dt)
    camX = camX + (targetCamX - camX) * lerp
    camY = camY + (targetCamY - camY) * lerp
end

--- 设置视角模式
---@param mode string "iso" | "topdown"
function IsoCanvas.SetViewMode(mode)
    if mode == "iso" or mode == "topdown" then
        viewMode = mode
        IsoCanvas.ResetCamera()
    end
end

--- 获取当前视角模式
---@return string "iso" | "topdown"
function IsoCanvas.GetViewMode()
    return viewMode
end

--- 切换视角模式
---@return string newMode 切换后的模式
function IsoCanvas.ToggleViewMode()
    if viewMode == "iso" then
        viewMode = "topdown"
    else
        viewMode = "iso"
    end
    IsoCanvas.ResetCamera()
    return viewMode
end

return IsoCanvas
