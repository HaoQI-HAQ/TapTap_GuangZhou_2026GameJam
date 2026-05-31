-- ============================================================================
-- MapData.lua — 等距场景编辑器 地图数据层（动态多层系统）
-- ============================================================================

local MapData = {}

-- 地图尺寸
MapData.MAP_W = 8
MapData.MAP_H = 8

-- 行走规则（tag → 是否可行走）
MapData.walkRules = {
    ["地面"] = true,
    ["墙壁"] = false,
}
MapData.defaultWalkable = true  -- 无 tag 或未匹配规则时默认可走

-- 瓦片类型定义 (id → { name, color{r,g,b,a}, tag })
MapData.TILE_TYPES = {
    [0] = { name = "空",   color = { 0, 0, 0, 0 },       tag = "" },
    [1] = { name = "草地", color = { 76, 175, 80, 255 },  tag = "" },
    [2] = { name = "水面", color = { 33, 150, 243, 255 }, tag = "" },
    [3] = { name = "沙地", color = { 255, 193, 7, 255 },  tag = "" },
    [4] = { name = "石头", color = { 158, 158, 158, 255 },tag = "" },
    [5] = { name = "泥土", color = { 121, 85, 72, 255 },  tag = "" },
}

-- 瓦片类型数量（不含空，仅颜色瓦片）
MapData.TILE_COUNT = 5

-- ============================================================================
-- 图片瓦片系统
-- ============================================================================

MapData.IMAGE_TILE_BASE = 100    -- 图片瓦片 ID 起始值
MapData.imageTileCount = 0       -- 已注册图片瓦片数
MapData.imageTileIDs = {}        -- 有序列表：{ 100, 101, 102, ... }
MapData.imageFolder = ""         -- 当前加载的文件夹路径

--- 注册单个图片瓦片
---@param name string 显示名称（文件名）
---@param imagePath string 资源路径（相对于 assets/）
---@return number tileID 分配的瓦片 ID
function MapData.RegisterImageTile(name, imagePath)
    local id = MapData.IMAGE_TILE_BASE + MapData.imageTileCount
    MapData.TILE_TYPES[id] = {
        name = name,
        imagePath = imagePath,
        color = { 100, 100, 100, 255 },  -- fallback 颜色
        tag = "",
    }
    MapData.imageTileCount = MapData.imageTileCount + 1
    MapData.imageTileIDs[#MapData.imageTileIDs + 1] = id
    return id
end

--- 清除所有已注册的图片瓦片（重新扫描前调用）
function MapData.ClearImageTiles()
    for _, id in ipairs(MapData.imageTileIDs) do
        MapData.TILE_TYPES[id] = nil
    end
    MapData.imageTileCount = 0
    MapData.imageTileIDs = {}
end

--- 扫描文件夹并批量注册图片瓦片（通过读取 manifest.json 清单）
---@param folder string 文件夹路径（资源相对路径，如 "Tiles"）
---@return number count 注册的图片数量
function MapData.ScanAndLoadImages(folder)
    -- 先清除旧的图片瓦片
    MapData.ClearImageTiles()
    MapData.imageFolder = folder

    local count = 0

    -- 读取 manifest.json 清单文件（放在 assets/<folder>/manifest.json）
    local manifestPath = folder .. "/manifest.json"
    if not cache:Exists(manifestPath) then
        print(string.format("[MapData] 未找到清单文件: %s", manifestPath))
        return 0
    end

    local file = cache:GetFile(manifestPath)
    if not file then
        print(string.format("[MapData] 无法打开清单文件: %s", manifestPath))
        return 0
    end

    local jsonStr = file:ReadString()
    file:Close()

    local ok, fileList = pcall(cjson.decode, jsonStr)
    if not ok or type(fileList) ~= "table" then
        print("[MapData] 清单文件 JSON 解析失败")
        return 0
    end

    -- 注册清单中的每个图片文件
    for _, fname in ipairs(fileList) do
        local resPath = folder .. "/" .. fname
        -- 去掉扩展名作为显示名
        local displayName = fname:gsub("%.[^.]+$", "")
        MapData.RegisterImageTile(displayName, resPath)
        count = count + 1
    end

    print(string.format("[MapData] 已从 '%s' 加载 %d 张图片瓦片", folder, count))
    return count
end

--- 获取所有图片瓦片 ID 列表
---@return table ids
function MapData.GetImageTileIDs()
    return MapData.imageTileIDs
end

--- 判断瓦片是否为图片瓦片
---@param tileID number
---@return boolean
function MapData.IsImageTile(tileID)
    return tileID >= MapData.IMAGE_TILE_BASE
end

-- ============================================================================
-- 撤销/重做系统 (Undo/Redo)
-- 每个操作 = { changes = { {layerIndex, x, y, oldID, newID}, ... } }
-- ============================================================================

local undoStack = {}     -- 撤销栈
local redoStack = {}     -- 重做栈
local MAX_UNDO = 100     -- 最大撤销步数
local batchChanges = nil -- 当前批量操作暂存（nil = 非批量模式）

--- 开始一组批量操作（Box Fill 等需要）
function MapData.BeginBatch()
    batchChanges = {}
end

--- 提交批量操作到撤销栈
function MapData.CommitBatch()
    if batchChanges and #batchChanges > 0 then
        undoStack[#undoStack + 1] = { changes = batchChanges }
        -- 限制栈深度
        if #undoStack > MAX_UNDO then
            table.remove(undoStack, 1)
        end
        -- 新操作清空重做栈
        redoStack = {}
    end
    batchChanges = nil
end

--- 取消批量操作（不提交）
function MapData.CancelBatch()
    batchChanges = nil
end

--- 记录单次瓦片变更（内部调用）
---@param layerIndex number
---@param x number
---@param y number
---@param oldID number
---@param newID number
local function recordChange(layerIndex, x, y, oldID, newID)
    if oldID == newID then return end  -- 无变化不记录

    local entry = { layerIndex, x, y, oldID, newID }

    if batchChanges then
        -- 批量模式：暂存到批量列表
        batchChanges[#batchChanges + 1] = entry
    else
        -- 单次模式：直接入撤销栈
        undoStack[#undoStack + 1] = { changes = { entry } }
        if #undoStack > MAX_UNDO then
            table.remove(undoStack, 1)
        end
        redoStack = {}
    end
end

--- 撤销
---@return boolean 是否成功撤销
function MapData.Undo()
    if #undoStack == 0 then return false end

    local op = undoStack[#undoStack]
    undoStack[#undoStack] = nil

    -- 逆序回退变更
    for i = #op.changes, 1, -1 do
        local c = op.changes[i]
        local layerIndex, x, y, oldID = c[1], c[2], c[3], c[4]
        local layer = MapData.layers[layerIndex]
        if layer and MapData.InBounds(x, y) then
            layer.data[y][x] = oldID
        end
    end

    -- 压入重做栈
    redoStack[#redoStack + 1] = op
    return true
end

--- 重做
---@return boolean 是否成功重做
function MapData.Redo()
    if #redoStack == 0 then return false end

    local op = redoStack[#redoStack]
    redoStack[#redoStack] = nil

    -- 正序重放变更
    for _, c in ipairs(op.changes) do
        local layerIndex, x, y, _, newID = c[1], c[2], c[3], c[4], c[5]
        local layer = MapData.layers[layerIndex]
        if layer and MapData.InBounds(x, y) then
            layer.data[y][x] = newID
        end
    end

    -- 压入撤销栈
    undoStack[#undoStack + 1] = op
    return true
end

--- 获取撤销栈深度
---@return number
function MapData.GetUndoCount()
    return #undoStack
end

--- 获取重做栈深度
---@return number
function MapData.GetRedoCount()
    return #redoStack
end

--- 清空撤销/重做历史
function MapData.ClearHistory()
    undoStack = {}
    redoStack = {}
    batchChanges = nil
end

-- ============================================================================
-- 动态多层地图系统
-- layers = { { name = "地面", data = 2D_array }, { name = "物体", data = 2D_array }, ... }
-- ============================================================================

MapData.layers = {}             -- 层数组
MapData.currentLayerIndex = 1   -- 当前编辑层索引 (1-based)
MapData.previewMode = false     -- 预览模式（全层满透明度，禁止编辑）
MapData.showGrid = true         -- 网格线显示开关（独立于预览模式）
MapData.groups = {}             -- 图层组 { { name="组名", collapsed=false }, ... }
MapData.nextGroupId = 1         -- 下一个组 ID 分配器

--- 创建空的二维数组
---@return table 2D array [y][x] = 0
local function createEmptyGrid()
    local grid = {}
    for y = 1, MapData.MAP_H do
        grid[y] = {}
        for x = 1, MapData.MAP_W do
            grid[y][x] = 0
        end
    end
    return grid
end

--- 初始化地图（默认两层）
function MapData.Init()
    MapData.layers = {
        { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0, groupId = nil },
        { name = "物体", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0, groupId = nil },
    }
    MapData.currentLayerIndex = 1
    MapData.groups = {}
    MapData.nextGroupId = 1
end

--- 获取层数量
---@return number
function MapData.GetLayerCount()
    return #MapData.layers
end

--- 获取层信息
---@param index number 层索引 (1-based)
---@return table|nil { name, data }
function MapData.GetLayer(index)
    return MapData.layers[index]
end

--- 获取层名称
---@param index number
---@return string
function MapData.GetLayerName(index)
    local layer = MapData.layers[index]
    return layer and layer.name or "?"
end

--- 添加新层
---@param name string|nil 层名称（默认 "层 N"）
---@return number index 新层索引
function MapData.AddLayer(name, groupId)
    local idx = #MapData.layers + 1
    name = name or ("层 " .. idx)
    MapData.layers[idx] = { name = name, data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0, groupId = groupId or nil, tag = "" }
    print(string.format("[MapData] 添加层 %d: %s", idx, name))
    return idx
end

--- 删除层（至少保留一层）
---@param index number 层索引 (1-based)
---@return boolean success
function MapData.RemoveLayer(index)
    if #MapData.layers <= 1 then
        print("[MapData] 至少保留一层，无法删除")
        return false
    end
    if index < 1 or index > #MapData.layers then
        return false
    end
    table.remove(MapData.layers, index)
    -- 调整当前层索引
    if MapData.currentLayerIndex > #MapData.layers then
        MapData.currentLayerIndex = #MapData.layers
    end
    print(string.format("[MapData] 删除层 %d，剩余 %d 层", index, #MapData.layers))
    return true
end

--- 重命名层
---@param index number
---@param name string
function MapData.RenameLayer(index, name)
    local layer = MapData.layers[index]
    if layer then
        layer.name = name
    end
end

--- 设置层标签
---@param index number
---@param tag string
function MapData.SetLayerTag(index, tag)
    local layer = MapData.layers[index]
    if layer then
        layer.tag = tag or ""
    end
end

--- 获取层标签
---@param index number
---@return string
function MapData.GetLayerTag(index)
    local layer = MapData.layers[index]
    return layer and layer.tag or ""
end

--- 切换层可见性
---@param index number 层索引
---@return boolean newVisible 切换后的可见状态
function MapData.ToggleLayerVisible(index)
    local layer = MapData.layers[index]
    if not layer then return true end
    layer.visible = not layer.visible
    return layer.visible
end

--- 获取层可见性
---@param index number
---@return boolean
function MapData.IsLayerVisible(index)
    local layer = MapData.layers[index]
    return layer and (layer.visible ~= false)
end

--- 切换层锁定
---@param index number 层索引
---@return boolean newLocked 切换后的锁定状态
function MapData.ToggleLayerLocked(index)
    local layer = MapData.layers[index]
    if not layer then return false end
    layer.locked = not layer.locked
    return layer.locked
end

--- 获取层锁定状态
---@param index number
---@return boolean
function MapData.IsLayerLocked(index)
    local layer = MapData.layers[index]
    return layer and (layer.locked == true)
end

--- 上移层（与上方层交换）
---@param index number 层索引
---@return boolean success
function MapData.MoveLayerUp(index)
    if index <= 1 or index > #MapData.layers then return false end
    MapData.layers[index], MapData.layers[index - 1] = MapData.layers[index - 1], MapData.layers[index]
    -- 调整当前层索引跟随
    if MapData.currentLayerIndex == index then
        MapData.currentLayerIndex = index - 1
    elseif MapData.currentLayerIndex == index - 1 then
        MapData.currentLayerIndex = index
    end
    return true
end

--- 下移层（与下方层交换）
---@param index number 层索引
---@return boolean success
function MapData.MoveLayerDown(index)
    if index < 1 or index >= #MapData.layers then return false end
    MapData.layers[index], MapData.layers[index + 1] = MapData.layers[index + 1], MapData.layers[index]
    -- 调整当前层索引跟随
    if MapData.currentLayerIndex == index then
        MapData.currentLayerIndex = index + 1
    elseif MapData.currentLayerIndex == index + 1 then
        MapData.currentLayerIndex = index
    end
    return true
end

--- 获取层不透明度（0.0~1.0）
---@param index number
---@return number
function MapData.GetLayerOpacity(index)
    local layer = MapData.layers[index]
    if not layer then return 1.0 end
    return layer.opacity or 1.0
end

--- 设置层不透明度
---@param index number
---@param opacity number (0.0~1.0)
function MapData.SetLayerOpacity(index, opacity)
    local layer = MapData.layers[index]
    if not layer then return end
    layer.opacity = math.max(0.0, math.min(1.0, opacity))
end

-- ============================================================================
-- 剪贴板系统（区域选择 + 复制/粘贴）
-- ============================================================================

local clipboard = nil  -- { width, height, data = 2D array of tileIDs }

--- 复制指定区域的瓦片数据到剪贴板
---@param x1 number 左上角 X (1-based)
---@param y1 number 左上角 Y (1-based)
---@param x2 number 右下角 X (1-based)
---@param y2 number 右下角 Y (1-based)
---@param layerIndex number|nil 层索引（nil = 当前层）
---@return number count 复制的非空瓦片数
function MapData.CopyRegion(x1, y1, x2, y2, layerIndex)
    layerIndex = layerIndex or MapData.currentLayerIndex
    local layer = MapData.layers[layerIndex]
    if not layer then return 0 end

    local minX = math.max(1, math.min(x1, x2))
    local maxX = math.min(MapData.MAP_W, math.max(x1, x2))
    local minY = math.max(1, math.min(y1, y2))
    local maxY = math.min(MapData.MAP_H, math.max(y1, y2))

    local w = maxX - minX + 1
    local h = maxY - minY + 1
    local data = {}
    local count = 0

    for dy = 1, h do
        data[dy] = {}
        for dx = 1, w do
            local id = layer.data[minY + dy - 1][minX + dx - 1]
            data[dy][dx] = id
            if id > 0 then count = count + 1 end
        end
    end

    clipboard = { width = w, height = h, data = data }
    return count
end

--- 粘贴剪贴板内容到指定位置
---@param startX number 粘贴起始 X (1-based)
---@param startY number 粘贴起始 Y (1-based)
---@param layerIndex number|nil 层索引（nil = 当前层）
---@return number count 粘贴的非空瓦片数
function MapData.PasteRegion(startX, startY, layerIndex)
    if not clipboard then return 0 end
    layerIndex = layerIndex or MapData.currentLayerIndex
    local layer = MapData.layers[layerIndex]
    if not layer then return 0 end
    if layer.locked then return 0 end

    local count = 0
    MapData.BeginBatch()
    for dy = 1, clipboard.height do
        for dx = 1, clipboard.width do
            local tx = startX + dx - 1
            local ty = startY + dy - 1
            local id = clipboard.data[dy][dx]
            if MapData.InBounds(tx, ty) and id > 0 then
                MapData.SetTile(tx, ty, id, layerIndex)
                count = count + 1
            end
        end
    end
    MapData.CommitBatch()
    return count
end

--- 检查剪贴板是否有内容
---@return boolean
function MapData.HasClipboard()
    return clipboard ~= nil
end

--- 获取剪贴板尺寸
---@return number|nil width, number|nil height
function MapData.GetClipboardSize()
    if not clipboard then return nil, nil end
    return clipboard.width, clipboard.height
end

--- 洪水填充（BFS，从指定起点替换同色连通区域）
---@param startX number 起点 X (1-based)
---@param startY number 起点 Y (1-based)
---@param newTileID number 填入的新瓦片 ID
---@param layerIndex number|nil 层索引（nil = 当前层）
---@return number count 填充的格数
function MapData.FloodFill(startX, startY, newTileID, layerIndex)
    layerIndex = layerIndex or MapData.currentLayerIndex
    if not MapData.InBounds(startX, startY) then return 0 end
    local layer = MapData.layers[layerIndex]
    if not layer then return 0 end

    local targetID = layer.data[startY][startX]
    if targetID == newTileID then return 0 end -- 同色不需要填充

    -- BFS
    local queue = { { startX, startY } }
    local visited = {}
    local count = 0
    local W, H = MapData.MAP_W, MapData.MAP_H

    local function key(x, y) return y * 10000 + x end

    visited[key(startX, startY)] = true

    MapData.BeginBatch()

    while #queue > 0 do
        local cell = table.remove(queue, 1)
        local cx, cy = cell[1], cell[2]

        if layer.data[cy][cx] == targetID then
            MapData.SetTile(cx, cy, newTileID, layerIndex)
            count = count + 1

            -- 四方向邻居
            local neighbors = {
                { cx - 1, cy }, { cx + 1, cy },
                { cx, cy - 1 }, { cx, cy + 1 },
            }
            for _, n in ipairs(neighbors) do
                local nx, ny = n[1], n[2]
                if nx >= 1 and nx <= W and ny >= 1 and ny <= H then
                    local k = key(nx, ny)
                    if not visited[k] then
                        visited[k] = true
                        if layer.data[ny][nx] == targetID then
                            queue[#queue + 1] = { nx, ny }
                        end
                    end
                end
            end
        end
    end

    MapData.CommitBatch()
    return count
end

--- 设置当前编辑层
---@param index number 层索引 (1-based)
function MapData.SetCurrentLayer(index)
    if index >= 1 and index <= #MapData.layers then
        MapData.currentLayerIndex = index
        MapData.previewMode = false  -- 选层自动退出预览
    end
end

--- 获取当前编辑层索引
---@return number
function MapData.GetCurrentLayer()
    return MapData.currentLayerIndex
end

--- 设置预览模式
---@param enabled boolean
function MapData.SetPreviewMode(enabled)
    MapData.previewMode = enabled
end

--- 获取预览模式
---@return boolean
function MapData.IsPreviewMode()
    return MapData.previewMode
end

--- 获取网格线显示状态
---@return boolean
function MapData.IsGridVisible()
    return MapData.showGrid
end

--- 切换网格线显示
---@param visible boolean|nil (nil = 取反)
function MapData.SetGridVisible(visible)
    if visible == nil then
        MapData.showGrid = not MapData.showGrid
    else
        MapData.showGrid = visible
    end
end

--- 调整地图尺寸（保留已有数据，超出部分裁剪，不足部分填零）
---@param newW number 新宽度 (>=2, <=100)
---@param newH number 新高度 (>=2, <=100)
---@return boolean success
function MapData.ResizeMap(newW, newH)
    newW = math.max(2, math.min(100, math.floor(newW)))
    newH = math.max(2, math.min(100, math.floor(newH)))

    if newW == MapData.MAP_W and newH == MapData.MAP_H then
        return false -- 尺寸不变
    end

    local oldW = MapData.MAP_W
    local oldH = MapData.MAP_H

    -- 调整每层数据
    for _, layer in ipairs(MapData.layers) do
        local newGrid = {}
        for y = 1, newH do
            newGrid[y] = {}
            for x = 1, newW do
                if y <= oldH and x <= oldW then
                    newGrid[y][x] = layer.data[y][x]
                else
                    newGrid[y][x] = 0
                end
            end
        end
        layer.data = newGrid
    end

    MapData.MAP_W = newW
    MapData.MAP_H = newH

    -- 清空撤销历史（尺寸变了，旧操作坐标可能越界）
    MapData.ClearHistory()

    print(string.format("[MapData] 地图尺寸: %dx%d → %dx%d", oldW, oldH, newW, newH))
    return true
end

--- 获取当前层名称
---@return string
function MapData.GetCurrentLayerName()
    return MapData.GetLayerName(MapData.currentLayerIndex)
end

--- 检查坐标是否在地图范围内
---@param x number 地图 X (1-based)
---@param y number 地图 Y (1-based)
---@return boolean
function MapData.InBounds(x, y)
    return x >= 1 and x <= MapData.MAP_W and y >= 1 and y <= MapData.MAP_H
end

--- 获取指定层的瓦片类型 ID
---@param x number 地图 X (1-based)
---@param y number 地图 Y (1-based)
---@param layerIndex number|nil 层索引（nil = 当前层）
---@return number tileID (0=空)
function MapData.GetTile(x, y, layerIndex)
    if not MapData.InBounds(x, y) then return 0 end
    layerIndex = layerIndex or MapData.currentLayerIndex
    local layer = MapData.layers[layerIndex]
    if not layer then return 0 end
    return layer.data[y][x] or 0
end

--- 设置瓦片（自动记录到撤销栈，锁定层拒绝编辑）
---@param x number 地图 X (1-based)
---@param y number 地图 Y (1-based)
---@param tileID number 瓦片类型 ID
---@param layerIndex number|nil 层索引（nil = 当前层）
---@return boolean 是否成功
function MapData.SetTile(x, y, tileID, layerIndex)
    if not MapData.InBounds(x, y) then return false end
    layerIndex = layerIndex or MapData.currentLayerIndex
    local layer = MapData.layers[layerIndex]
    if not layer then return false end
    -- 锁定层拒绝编辑
    if layer.locked then return false end
    local oldID = layer.data[y][x]
    layer.data[y][x] = tileID
    recordChange(layerIndex, x, y, oldID, tileID)
    return true
end

--- 设置瓦片（不记录撤销，内部恢复用）
---@param x number
---@param y number
---@param tileID number
---@param layerIndex number|nil
function MapData.SetTileRaw(x, y, tileID, layerIndex)
    if not MapData.InBounds(x, y) then return end
    layerIndex = layerIndex or MapData.currentLayerIndex
    local layer = MapData.layers[layerIndex]
    if layer then
        layer.data[y][x] = tileID
    end
end

--- 清空地图（所有层都清空）
function MapData.Clear()
    for _, layer in ipairs(MapData.layers) do
        for y = 1, MapData.MAP_H do
            for x = 1, MapData.MAP_W do
                layer.data[y][x] = 0
            end
        end
    end
end

--- 获取瓦片类型信息
---@param tileID number
---@return table { name, color }
function MapData.GetTileType(tileID)
    return MapData.TILE_TYPES[tileID] or MapData.TILE_TYPES[0]
end

--- 设置瓦片名称
---@param tileID number
---@param name string
function MapData.SetTileName(tileID, name)
    local t = MapData.TILE_TYPES[tileID]
    if t and name and name ~= "" then t.name = name end
end

--- 设置瓦片标签（用于碰撞、触发器等逻辑标记）
---@param tileID number
---@param tag string
function MapData.SetTileTag(tileID, tag)
    local t = MapData.TILE_TYPES[tileID]
    if t then t.tag = tag or "" end
end

--- 获取瓦片标签
---@param tileID number
---@return string
function MapData.GetTileTag(tileID)
    local t = MapData.TILE_TYPES[tileID]
    return t and t.tag or ""
end

-- ============================================================================
-- 行走规则与碰撞查询
-- ============================================================================

--- 设置行走规则
---@param tag string
---@param walkable boolean
function MapData.SetWalkRule(tag, walkable)
    if tag and tag ~= "" then
        MapData.walkRules[tag] = walkable
    end
end

--- 移除行走规则
---@param tag string
function MapData.RemoveWalkRule(tag)
    if tag then
        MapData.walkRules[tag] = nil
    end
end

--- 获取行走规则表
---@return table
function MapData.GetWalkRules()
    return MapData.walkRules
end

--- 检查地图坐标 (mx, my) 是否可行走
--- 优先级：层 tag > 瓦片 tag > defaultWalkable
--- 遍历所有可见层，任一层有阻挡规则则不可走
---@param mx number 地图 X (1-based)
---@param my number 地图 Y (1-based)
---@return boolean
function MapData.IsWalkable(mx, my)
    if not MapData.InBounds(mx, my) then return false end

    local hasMatchedRule = false

    for li = 1, #MapData.layers do
        local layer = MapData.layers[li]
        if layer.visible ~= false then
            local tileID = layer.data[my][mx]
            if tileID > 0 then
                -- 1) 先检查层 tag（层整体标记，如"墙壁"层）
                local ltag = layer.tag
                if ltag and ltag ~= "" then
                    local layerRule = MapData.walkRules[ltag]
                    if layerRule ~= nil then
                        if layerRule == false then
                            return false  -- 层标记为阻挡 → 不可走
                        end
                        hasMatchedRule = true
                    end
                end

                -- 2) 再检查瓦片自身 tag
                local tt = MapData.TILE_TYPES[tileID]
                if tt and tt.tag and tt.tag ~= "" then
                    local rule = MapData.walkRules[tt.tag]
                    if rule ~= nil then
                        if rule == false then
                            return false  -- 瓦片标记为阻挡 → 不可走
                        end
                        hasMatchedRule = true
                    end
                end
            end
        end
    end

    if hasMatchedRule then return true end
    return MapData.defaultWalkable
end

-- ============================================================================
-- 存档（本地 JSON 文件）
-- ============================================================================

local SAVE_FILE = "map_save.json"

--- 辅助：从一个层收集非空瓦片
---@param layerData table 二维数组
---@return table tiles
local function collectLayerTiles(layerData)
    local tiles = {}
    for y = 1, MapData.MAP_H do
        if not layerData[y] then goto continue_row end
        for x = 1, MapData.MAP_W do
            local id = layerData[y][x] or 0
            if id > 0 then
                local tileType = MapData.TILE_TYPES[id]
                local entry = { x = x, y = y, id = id }
                if tileType then
                    if tileType.imagePath then
                        entry.path = tileType.imagePath
                    end
                    if tileType.tag and tileType.tag ~= "" then
                        entry.tag = tileType.tag
                    end
                end
                tiles[#tiles + 1] = entry
            end
        end
        ::continue_row::
    end
    return tiles
end

--- 辅助：从瓦片列表恢复到一个层
---@param layerData table 二维数组
---@param tileList table 瓦片列表
---@return number count
local function restoreLayerTiles(layerData, tileList)
    local count = 0
    if not tileList then return 0 end
    for _, t in ipairs(tileList) do
        local x, y, id
        if t.x then
            x, y, id = t.x, t.y, t.id
        else
            x, y, id = t[1], t[2], t[3]
        end
        if MapData.InBounds(x, y) and MapData.TILE_TYPES[id] then
            layerData[y][x] = id
            count = count + 1
        end
    end
    return count
end

--- 保存地图到本地文件（多层）
---@return boolean success
function MapData.Save()
    -- 收集所有层数据
    local layersData = {}
    local totalCount = 0
    for i, layer in ipairs(MapData.layers) do
        local tiles = collectLayerTiles(layer.data)
        totalCount = totalCount + #tiles
        layersData[i] = {
            name = layer.name,
            tiles = tiles,
            visible = layer.visible ~= false,
            locked = layer.locked == true,
            opacity = layer.opacity or 1.0,
            groupId = layer.groupId,
            tag = (layer.tag and layer.tag ~= "") and layer.tag or nil,
        }
    end

    -- 收集图片瓦片注册表（含 tag）
    local imageRegistry = {}
    for _, imgID in ipairs(MapData.imageTileIDs) do
        local t = MapData.TILE_TYPES[imgID]
        if t then
            imageRegistry[#imageRegistry + 1] = {
                id = imgID,
                name = t.name,
                imagePath = t.imagePath,
                tag = (t.tag and t.tag ~= "") and t.tag or nil,
            }
        end
    end

    -- 收集颜色瓦片自定义属性（name/tag 修改）
    local tileCustomizations = {}
    local defaultNames = { [1] = "草地", [2] = "水面", [3] = "沙地", [4] = "石头", [5] = "泥土" }
    for id = 1, MapData.TILE_COUNT do
        local t = MapData.TILE_TYPES[id]
        if t then
            local hasCustom = false
            local entry = { id = id }
            if t.name ~= (defaultNames[id] or "") then
                entry.name = t.name; hasCustom = true
            end
            if t.tag and t.tag ~= "" then
                entry.tag = t.tag; hasCustom = true
            end
            if hasCustom then
                tileCustomizations[#tileCustomizations + 1] = entry
            end
        end
    end

    -- 收集行走规则（仅非空时保存）
    local walkRulesData = nil
    if next(MapData.walkRules) then
        walkRulesData = {}
        for tag, walkable in pairs(MapData.walkRules) do
            walkRulesData[tag] = walkable
        end
    end

    local saveData = {
        version = 4,
        width = MapData.MAP_W,
        height = MapData.MAP_H,
        showGrid = MapData.showGrid,
        layers = layersData,
        imageFolder = MapData.imageFolder ~= "" and MapData.imageFolder or nil,
        imageRegistry = #imageRegistry > 0 and imageRegistry or nil,
        tileCustomizations = #tileCustomizations > 0 and tileCustomizations or nil,
        groups = next(MapData.groups) and MapData.groups or nil,
        nextGroupId = MapData.nextGroupId,
        walkRules = walkRulesData,
        defaultWalkable = MapData.defaultWalkable,
    }

    local file = File(SAVE_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[MapData] 保存失败: 无法打开文件")
        return false
    end
    file:WriteString(cjson.encode(saveData))
    file:Close()
    print(string.format("[MapData] 已保存 %d 层 共 %d 个瓦片", #MapData.layers, totalCount))
    return true
end

--- 从本地文件加载地图（支持 v1/v2/v3/v4）
---@return boolean success
function MapData.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        print("[MapData] 没有找到存档文件")
        return false
    end

    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then
        print("[MapData] 加载失败: 无法打开文件")
        return false
    end

    local jsonStr = file:ReadString()
    file:Close()

    local ok, saveData = pcall(cjson.decode, jsonStr)
    if not ok or not saveData then
        print("[MapData] 加载失败: JSON 解析错误")
        return false
    end

    -- 重建图片瓦片注册表（如果存档中有）
    if saveData.imageRegistry then
        MapData.ClearImageTiles()
        MapData.imageFolder = saveData.imageFolder or ""
        for _, reg in ipairs(saveData.imageRegistry) do
            local regId = MapData.RegisterImageTile(reg.name, reg.imagePath)
            -- 恢复 tag
            if reg.tag and reg.tag ~= "" then
                MapData.TILE_TYPES[regId].tag = reg.tag
            end
        end
    end

    -- 恢复颜色瓦片自定义属性（name/tag）
    if saveData.tileCustomizations then
        for _, c in ipairs(saveData.tileCustomizations) do
            local t = MapData.TILE_TYPES[c.id]
            if t then
                if c.name then t.name = c.name end
                if c.tag then t.tag = c.tag end
            end
        end
    end

    -- v4: 动态多层
    if saveData.version == 4 and saveData.layers then
        -- 恢复地图尺寸
        if saveData.width and saveData.height then
            MapData.MAP_W = math.max(2, math.min(100, saveData.width))
            MapData.MAP_H = math.max(2, math.min(100, saveData.height))
        end
        -- 恢复网格显示
        if saveData.showGrid ~= nil then
            MapData.showGrid = saveData.showGrid
        end
        MapData.layers = {}
        local totalCount = 0
        for i, layerInfo in ipairs(saveData.layers) do
            local grid = createEmptyGrid()
            local count = restoreLayerTiles(grid, layerInfo.tiles)
            totalCount = totalCount + count
            MapData.layers[i] = {
                name = layerInfo.name, data = grid,
                visible = layerInfo.visible ~= false,
                locked = layerInfo.locked == true,
                opacity = layerInfo.opacity or 1.0,
                groupId = layerInfo.groupId,
                tag = layerInfo.tag or "",
            }
        end
        if #MapData.layers == 0 then
            MapData.layers[1] = { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 }
        end
        MapData.currentLayerIndex = math.min(MapData.currentLayerIndex, #MapData.layers)

        -- 恢复图层组
        if saveData.groups then
            MapData.groups = saveData.groups
            MapData.nextGroupId = saveData.nextGroupId or 1
        else
            MapData.groups = {}
            MapData.nextGroupId = 1
        end

        -- 恢复行走规则
        if saveData.walkRules then
            MapData.walkRules = {}
            for tag, walkable in pairs(saveData.walkRules) do
                MapData.walkRules[tag] = walkable
            end
        end
        if saveData.defaultWalkable ~= nil then
            MapData.defaultWalkable = saveData.defaultWalkable
        end

        print(string.format("[MapData] 已加载 %d 层 共 %d 个瓦片 (地图 %dx%d)", #MapData.layers, totalCount, MapData.MAP_W, MapData.MAP_H))
    elseif saveData.groundTiles then
        -- v3: 双层 → 转为两层
        MapData.layers = {
            { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
            { name = "物体", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
        }
        local gc = restoreLayerTiles(MapData.layers[1].data, saveData.groundTiles)
        local oc = restoreLayerTiles(MapData.layers[2].data, saveData.objectTiles)
        MapData.currentLayerIndex = 1
        print(string.format("[MapData] 已加载(v3兼容) 地面:%d 物体:%d", gc, oc))
    else
        -- v1/v2: 单层 → 转为地面层
        MapData.layers = {
            { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
            { name = "物体", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
        }
        local gc = restoreLayerTiles(MapData.layers[1].data, saveData.tiles)
        MapData.currentLayerIndex = 1
        print(string.format("[MapData] 已加载(旧版兼容) %d 个瓦片→地面层", gc))
    end

    return true
end

--- 检查是否有存档
---@return boolean
function MapData.HasSave()
    return fileSystem:FileExists(SAVE_FILE)
end

-- ============================================================================
-- 命名存档文件管理（mapjson/ 目录）
-- ============================================================================

local MAP_DIR = "mapjson"           -- 存档目录（File API，存入 savedata）
local RES_MAP_DIR = "mapjson"       -- 资源目录（cache:GetFile，打包在 assets/ 中）

--- 保存地图到命名文件
---@param filename string 文件名（不含 .json 后缀）
---@return boolean success
function MapData.SaveToNamedFile(filename)
    fileSystem:CreateDir(MAP_DIR)
    local path = MAP_DIR .. "/" .. filename .. ".json"

    -- 复用 Save 的序列化逻辑
    local layersData = {}
    local totalCount = 0
    for i, layer in ipairs(MapData.layers) do
        local tiles = collectLayerTiles(layer.data)
        totalCount = totalCount + #tiles
        layersData[i] = {
            name = layer.name,
            tiles = tiles,
            visible = layer.visible ~= false,
            locked = layer.locked == true,
            opacity = layer.opacity or 1.0,
            groupId = layer.groupId,
            tag = (layer.tag and layer.tag ~= "") and layer.tag or nil,
        }
    end

    local imageRegistry = {}
    for _, imgID in ipairs(MapData.imageTileIDs) do
        local t = MapData.TILE_TYPES[imgID]
        if t then
            imageRegistry[#imageRegistry + 1] = {
                id = imgID, name = t.name, imagePath = t.imagePath,
                tag = (t.tag and t.tag ~= "") and t.tag or nil,
            }
        end
    end

    local tileCustomizations = {}
    local defaultNames = { [1] = "草地", [2] = "水面", [3] = "沙地", [4] = "石头", [5] = "泥土" }
    for id = 1, MapData.TILE_COUNT do
        local t = MapData.TILE_TYPES[id]
        if t then
            local hasCustom = false
            local entry = { id = id }
            if t.name ~= (defaultNames[id] or "") then entry.name = t.name; hasCustom = true end
            if t.tag and t.tag ~= "" then entry.tag = t.tag; hasCustom = true end
            if hasCustom then tileCustomizations[#tileCustomizations + 1] = entry end
        end
    end

    -- 收集行走规则
    local walkRulesData = nil
    if next(MapData.walkRules) then
        walkRulesData = {}
        for tag, walkable in pairs(MapData.walkRules) do
            walkRulesData[tag] = walkable
        end
    end

    local saveData = {
        version = 4,
        width = MapData.MAP_W, height = MapData.MAP_H,
        showGrid = MapData.showGrid,
        layers = layersData,
        imageFolder = MapData.imageFolder ~= "" and MapData.imageFolder or nil,
        imageRegistry = #imageRegistry > 0 and imageRegistry or nil,
        tileCustomizations = #tileCustomizations > 0 and tileCustomizations or nil,
        groups = next(MapData.groups) and MapData.groups or nil,
        nextGroupId = MapData.nextGroupId,
        walkRules = walkRulesData,
        defaultWalkable = MapData.defaultWalkable,
    }

    local file = File(path, FILE_WRITE)
    if not file:IsOpen() then
        print("[MapData] 保存失败: 无法创建文件 " .. path)
        return false
    end
    file:WriteString(cjson.encode(saveData))
    file:Close()
    print(string.format("[MapData] 已保存到 %s (%d 层 %d 瓦片)", path, #MapData.layers, totalCount))
    return true
end

--- 检查命名文件是否已存在
---@param filename string 不含 .json 后缀
---@return boolean
function MapData.NamedFileExists(filename)
    return fileSystem:FileExists(MAP_DIR .. "/" .. filename .. ".json")
end

--- 列出所有已保存的地图文件
---@return table filenames 文件名列表（不含 .json 后缀）
function MapData.ListSavedMaps()
    local names = {}
    local seen = {}

    -- 方法1: ScanDir 扫描用户存档（引擎 File API 写入的文件）
    if fileSystem:DirExists(MAP_DIR) then
        local files = fileSystem:ScanDir(MAP_DIR .. "/", "*.json", SCAN_FILES, false)
        for _, f in ipairs(files) do
            local name = f:match("^(.+)%.json$")
            if name then
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    -- 方法2: 通过资源系统探测预制地图（assets/mapjson/ 中打包的文件）
    local knownNames = { "demo" }
    for _, name in ipairs(knownNames) do
        if not seen[name] then
            local resPath = RES_MAP_DIR .. "/" .. name .. ".json"
            local f = cache:GetFile(resPath)
            if f then
                f:Close()
                names[#names + 1] = name
                seen[name] = true
            end
        end
    end

    table.sort(names)
    return names
end

--- 从命名文件加载地图
---@param filename string 不含 .json 后缀
---@return boolean success
function MapData.LoadFromNamedFile(filename)
    local relPath = MAP_DIR .. "/" .. filename .. ".json"
    local file = nil
    local source = ""

    -- 优先从资源系统读取（assets/mapjson/ 中的预制地图，不会产生错误日志）
    file = cache:GetFile(relPath)
    if file then
        source = "resource"
    else
        -- 回退到存档目录（用户通过引擎 File API 保存的地图）
        file = File(relPath, FILE_READ)
        if file and file:IsOpen() then
            source = "savedata"
        else
            print("[MapData] 文件不存在: " .. relPath .. " (resource+savedata 均未找到)")
            return false
        end
    end
    local jsonStr = file:ReadString()
    file:Close()
    print("[MapData] 从 " .. source .. " 加载: " .. filename .. ".json")

    local ok, saveData = pcall(cjson.decode, jsonStr)
    if not ok or not saveData then
        print("[MapData] JSON 解析失败: " .. relPath)
        return false
    end

    -- 复用 Load 的反序列化逻辑
    if saveData.width then MapData.MAP_W = saveData.width end
    if saveData.height then MapData.MAP_H = saveData.height end
    if saveData.showGrid ~= nil then MapData.showGrid = saveData.showGrid end

    -- 恢复图片瓦片
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

    -- 恢复颜色瓦片自定义属性
    if saveData.tileCustomizations then
        for _, c in ipairs(saveData.tileCustomizations) do
            local t = MapData.TILE_TYPES[c.id]
            if t then
                if c.name then t.name = c.name end
                if c.tag then t.tag = c.tag end
            end
        end
    end

    -- 恢复组
    if saveData.groups then
        MapData.groups = saveData.groups
    else
        MapData.groups = {}
    end
    if saveData.nextGroupId then MapData.nextGroupId = saveData.nextGroupId end

    -- 恢复层
    if saveData.layers then
        MapData.layers = {}
        local totalCount = 0
        for i, layerInfo in ipairs(saveData.layers) do
            local grid = createEmptyGrid()
            local count = restoreLayerTiles(grid, layerInfo.tiles)
            totalCount = totalCount + count
            MapData.layers[i] = {
                name = layerInfo.name, data = grid,
                visible = layerInfo.visible ~= false,
                locked = layerInfo.locked == true,
                opacity = layerInfo.opacity or 1.0,
                groupId = layerInfo.groupId,
                tag = layerInfo.tag or "",
            }
        end
        if #MapData.layers == 0 then
            MapData.layers[1] = { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 }
        end
        MapData.currentLayerIndex = math.min(MapData.currentLayerIndex, #MapData.layers)
        print(string.format("[MapData] 已从 %s 加载 %d 层 共 %d 瓦片", relPath, #MapData.layers, totalCount))
    end

    if saveData.imageFolder then MapData.imageFolder = saveData.imageFolder end

    return true
end

-- ============================================================================
-- 项目资源文件（持久化到 scripts/ 目录，随构建打包）
-- ============================================================================

local RESOURCE_FILE = "maps/default_map.lua"

--- 辅助：将一层瓦片导出为 Lua 表格式
---@param layerData table 二维数组
---@return table lines
local function exportLayerToLua(layerData)
    local lines = {}
    for y = 1, MapData.MAP_H do
        for x = 1, MapData.MAP_W do
            local id = layerData[y][x]
            if id > 0 then
                local tileType = MapData.TILE_TYPES[id]
                local tagStr = (tileType and tileType.tag and tileType.tag ~= "")
                    and string.format(', tag = %q', tileType.tag) or ""
                if tileType and tileType.imagePath then
                    lines[#lines + 1] = string.format(
                        '            { x = %d, y = %d, id = %d, path = %q%s },',
                        x, y, id, tileType.imagePath, tagStr)
                else
                    lines[#lines + 1] = string.format(
                        '            { x = %d, y = %d, id = %d%s },',
                        x, y, id, tagStr)
                end
            end
        end
    end
    return lines
end

--- 将地图导出为 Lua 数据格式的字符串（多层）
---@return string luaSource
function MapData.ExportToLua()
    local lines = {}
    lines[#lines + 1] = "-- 等距场景编辑器 · 地图数据（自动生成，请勿手动编辑）"
    lines[#lines + 1] = "return {"
    lines[#lines + 1] = string.format("    version = 4,")
    lines[#lines + 1] = string.format("    width = %d,", MapData.MAP_W)
    lines[#lines + 1] = string.format("    height = %d,", MapData.MAP_H)

    -- 图片瓦片注册表
    if #MapData.imageTileIDs > 0 then
        if MapData.imageFolder ~= "" then
            lines[#lines + 1] = string.format("    imageFolder = %q,", MapData.imageFolder)
        end
        lines[#lines + 1] = "    imageRegistry = {"
        for _, imgID in ipairs(MapData.imageTileIDs) do
            local t = MapData.TILE_TYPES[imgID]
            if t then
                local tagStr = (t.tag and t.tag ~= "") and string.format(', tag = %q', t.tag) or ""
                lines[#lines + 1] = string.format(
                    '        { id = %d, name = %q, imagePath = %q%s },',
                    imgID, t.name, t.imagePath, tagStr)
            end
        end
        lines[#lines + 1] = "    },"
    end

    -- 瓦片注册表（颜色瓦片 name/tag）
    lines[#lines + 1] = "    tileRegistry = {"
    for id = 1, MapData.TILE_COUNT do
        local t = MapData.TILE_TYPES[id]
        if t then
            local tagStr = (t.tag and t.tag ~= "") and string.format(', tag = %q', t.tag) or ""
            lines[#lines + 1] = string.format(
                '        { id = %d, name = %q%s },', id, t.name, tagStr)
        end
    end
    lines[#lines + 1] = "    },"

    -- 多层数据
    lines[#lines + 1] = "    layers = {"
    for i, layer in ipairs(MapData.layers) do
        local tagStr = (layer.tag and layer.tag ~= "") and string.format(', tag = %q', layer.tag) or ""
        lines[#lines + 1] = string.format("        { name = %q%s, tiles = {", layer.name, tagStr)
        for _, l in ipairs(exportLayerToLua(layer.data)) do
            lines[#lines + 1] = l
        end
        lines[#lines + 1] = "        } },"
    end
    lines[#lines + 1] = "    },"

    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

--- 保存地图为项目资源文件（Lua 格式，存入 scripts/maps/）
---@return boolean success
function MapData.SaveToProject()
    fileSystem:CreateDir("maps")
    local file = File(RESOURCE_FILE, FILE_WRITE)
    if not file:IsOpen() then
        print("[MapData] 导出失败: 无法创建文件")
        return false
    end
    file:WriteString(MapData.ExportToLua())
    file:Close()

    -- 同时保存 JSON 临时存档
    MapData.Save()

    print("[MapData] 已导出为项目资源: " .. RESOURCE_FILE)
    return true
end

--- 从项目资源文件加载地图（多层兼容）
---@return boolean success
function MapData.LoadFromProject()
    local ok, mapModule = pcall(require, "maps.default_map")
    if not ok or not mapModule then
        print("[MapData] 未找到项目地图资源")
        return false
    end

    -- v4: 多层
    if mapModule.layers then
        MapData.layers = {}
        local totalCount = 0
        for i, layerInfo in ipairs(mapModule.layers) do
            local grid = createEmptyGrid()
            local count = restoreLayerTiles(grid, layerInfo.tiles)
            totalCount = totalCount + count
            MapData.layers[i] = {
                name = layerInfo.name, data = grid,
                visible = layerInfo.visible ~= false,
                locked = layerInfo.locked == true,
                opacity = layerInfo.opacity or 1.0,
            }
        end
        if #MapData.layers == 0 then
            MapData.layers[1] = { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 }
        end
        MapData.currentLayerIndex = math.min(MapData.currentLayerIndex, #MapData.layers)
        print(string.format("[MapData] 已从项目资源加载 %d 层 共 %d 个瓦片", #MapData.layers, totalCount))
    elseif mapModule.groundTiles then
        -- v3 兼容
        MapData.layers = {
            { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
            { name = "物体", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
        }
        local gc = restoreLayerTiles(MapData.layers[1].data, mapModule.groundTiles)
        local oc = restoreLayerTiles(MapData.layers[2].data, mapModule.objectTiles)
        MapData.currentLayerIndex = 1
        print(string.format("[MapData] 已从项目资源加载(v3兼容) 地面:%d 物体:%d", gc, oc))
    else
        -- v1/v2 兼容
        MapData.layers = {
            { name = "地面", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
            { name = "物体", data = createEmptyGrid(), visible = true, locked = false, opacity = 1.0 },
        }
        local gc = restoreLayerTiles(MapData.layers[1].data, mapModule.tiles)
        MapData.currentLayerIndex = 1
        print(string.format("[MapData] 已从项目资源加载(旧版兼容) %d 个瓦片→地面层", gc))
    end

    return true
end

--- 检查项目资源文件是否存在
---@return boolean
function MapData.HasProjectMap()
    local ok, _ = pcall(require, "maps.default_map")
    return ok
end

-- ============================================================================
-- 图层组（Layer Groups）
-- groups = { [id] = { name = "组名", collapsed = false } }
-- 每层 layer.groupId 指向组 ID（nil = 未分组）
-- ============================================================================

--- 创建新图层组
---@param name string|nil 组名（默认 "组 N"）
---@return number groupId
function MapData.CreateGroup(name)
    local id = MapData.nextGroupId
    MapData.nextGroupId = id + 1
    name = name or ("组 " .. id)
    MapData.groups[id] = { name = name, collapsed = false }
    print(string.format("[MapData] 创建图层组 %d: %s", id, name))
    return id
end

--- 删除图层组（组内层变为未分组，不删除层本身）
---@param groupId number
---@return boolean success
function MapData.DeleteGroup(groupId)
    if not MapData.groups[groupId] then return false end
    for _, layer in ipairs(MapData.layers) do
        if layer.groupId == groupId then
            layer.groupId = nil
        end
    end
    MapData.groups[groupId] = nil
    print(string.format("[MapData] 删除图层组 %d", groupId))
    return true
end

--- 重命名图层组
---@param groupId number
---@param name string
function MapData.RenameGroup(groupId, name)
    local g = MapData.groups[groupId]
    if g then g.name = name end
end

--- 获取图层组信息
---@param groupId number
---@return table|nil { name, collapsed }
function MapData.GetGroup(groupId)
    return MapData.groups[groupId]
end

--- 切换图层组折叠状态
---@param groupId number
---@return boolean newCollapsed
function MapData.ToggleGroupCollapsed(groupId)
    local g = MapData.groups[groupId]
    if not g then return false end
    g.collapsed = not g.collapsed
    return g.collapsed
end

--- 获取图层组是否折叠
---@param groupId number
---@return boolean
function MapData.IsGroupCollapsed(groupId)
    local g = MapData.groups[groupId]
    return g and g.collapsed or false
end

--- 设置层的所属组
---@param layerIndex number
---@param groupId number|nil (nil = 移出组)
function MapData.SetLayerGroup(layerIndex, groupId)
    local layer = MapData.layers[layerIndex]
    if not layer then return end
    layer.groupId = groupId
end

--- 获取层的所属组 ID
---@param layerIndex number
---@return number|nil
function MapData.GetLayerGroup(layerIndex)
    local layer = MapData.layers[layerIndex]
    return layer and layer.groupId
end

--- 获取所有组的 ID 列表（有序）
---@return table ids
function MapData.GetGroupIDs()
    local ids = {}
    for id, _ in pairs(MapData.groups) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--- 获取指定组内的层索引列表
---@param groupId number
---@return table layerIndices
function MapData.GetGroupLayers(groupId)
    local indices = {}
    for i, layer in ipairs(MapData.layers) do
        if layer.groupId == groupId then
            indices[#indices + 1] = i
        end
    end
    return indices
end

--- 获取未分组的层索引列表
---@return table layerIndices
function MapData.GetUngroupedLayers()
    local indices = {}
    for i, layer in ipairs(MapData.layers) do
        if not layer.groupId or not MapData.groups[layer.groupId] then
            indices[#indices + 1] = i
        end
    end
    return indices
end

--- 切换整组可见性（组内所有层统一设置）
---@param groupId number
---@param visible boolean
function MapData.SetGroupVisible(groupId, visible)
    for _, layer in ipairs(MapData.layers) do
        if layer.groupId == groupId then
            layer.visible = visible
        end
    end
end

--- 切换整组锁定（组内所有层统一设置）
---@param groupId number
---@param locked boolean
function MapData.SetGroupLocked(groupId, locked)
    for _, layer in ipairs(MapData.layers) do
        if layer.groupId == groupId then
            layer.locked = locked
        end
    end
end

return MapData
