-- editor_level_data.lua
-- 关卡编辑器 - 数据层（常量、撤销/重做、持久化、关卡管理）
---@diagnostic disable: undefined-global, redefined-local

local M = {}

-- ============================================================================
-- 常量
-- ============================================================================

M.ELEM_TYPES = {
    { id = "platform", name = "平台", color = Color(0.4, 0.7, 0.3, 1.0), key = "1" },
    { id = "enemy_fire", name = "火敌", color = Color(1.0, 0.3, 0.1, 1.0), key = "2" },
    { id = "enemy_ice", name = "冰敌", color = Color(0.2, 0.6, 1.0, 1.0), key = "3" },
    { id = "enemy_thunder", name = "雷敌", color = Color(1.0, 0.9, 0.1, 1.0), key = "4" },
    { id = "enemy_grass", name = "草敌", color = Color(0.2, 0.8, 0.3, 1.0), key = "5" },
    { id = "enemy_earth", name = "土敌", color = Color(0.6, 0.4, 0.2, 1.0), key = "6" },
    { id = "enemy_boss", name = "Boss", color = Color(0.8, 0.1, 0.8, 1.0), key = "7" },
    { id = "portal", name = "传送门", color = Color(0.3, 0.5, 1.0, 0.8), key = "8" },
    { id = "spawn", name = "玩家", color = Color(0.0, 1.0, 0.5, 1.0), key = "9" },
}

M.DEFAULT_LEVEL = {
    name = "新关卡",
    groundWidth = 100.0,
    groundY = -2.5,
    platforms = {},
    enemies = {},
    portalX = 20.0,
    portalY = -2.0,
    spawnX = 0.0,
    spawnY = -1.5,
}

M.GAME_LEVELS = {
    [1] = {
        name = "第一关",
        groundWidth = 100.0,
        platforms = {
            { x = 4.0, y = 0.0, w = 5.0, h = 0.3 },
        },
        enemies = {
            { x = 2.5, y = 1.0, element = "fire" },
            { x = 4.0, y = 1.0, element = "ice" },
        },
        portalX = 20.0,
        portalY = -2.0,
    },
    [2] = {
        name = "第二关",
        groundWidth = 120.0,
        platforms = {
            { x = 5.0, y = 0.0, w = 6.0, h = 0.3 },
            { x = 12.0, y = 1.0, w = 4.0, h = 0.3 },
        },
        enemies = {
            { x = 4.0, y = 1.0, element = "fire" },
            { x = 6.0, y = 1.0, element = "ice" },
            { x = 11.0, y = 2.0, element = "grass" },
            { x = 13.0, y = 2.0, element = "earth" },
        },
        portalX = 30.0,
        portalY = -2.0,
    },
    [3] = {
        name = "第三关",
        groundWidth = 130.0,
        platforms = {
            { x = 6.0, y = 0.5, w = 5.0, h = 0.3 },
            { x = 14.0, y = 1.5, w = 5.0, h = 0.3 },
            { x = 22.0, y = 0.0, w = 4.0, h = 0.3 },
        },
        enemies = {
            { x = 6.0, y = 1.5, element = "fire" },
            { x = 8.0, y = 1.5, element = "ice" },
            { x = 14.0, y = 2.5, element = "thunder" },
            { x = 16.0, y = 2.5, element = "grass" },
            { x = 22.0, y = 1.0, element = "earth" },
        },
        portalX = 32.0,
        portalY = -2.0,
    },
    [4] = {
        name = "第四关",
        groundWidth = 140.0,
        platforms = {
            { x = 4.0, y = 0.0, w = 5.0, h = 0.3 },
            { x = 10.0, y = 1.0, w = 4.0, h = 0.3 },
            { x = 18.0, y = 0.5, w = 5.0, h = 0.3 },
            { x = 26.0, y = 1.5, w = 4.0, h = 0.3 },
        },
        enemies = {
            { x = 4.0, y = 1.0, element = "fire" },
            { x = 6.0, y = 1.0, element = "ice" },
            { x = 10.0, y = 2.0, element = "thunder" },
            { x = 12.0, y = 2.0, element = "grass" },
            { x = 18.0, y = 1.5, element = "earth" },
            { x = 20.0, y = 1.5, element = "fire" },
            { x = 26.0, y = 2.5, element = "ice" },
            { x = 28.0, y = 2.5, element = "thunder" },
        },
        portalX = 35.0,
        portalY = -2.0,
    },
    [5] = {
        name = "最终关 - Boss战",
        groundWidth = 80.0,
        platforms = {
            { x = -3.0, y = 0.5, w = 4.0, h = 0.3 },
            { x = 5.0, y = 1.0, w = 4.0, h = 0.3 },
        },
        enemies = {
        },
        portalX = nil,
        portalY = nil,
    },
}

M.MAX_UNDO_STEPS = 50

-- ============================================================================
-- Mixin: 将数据操作方法附加到 EditorLevel 类
-- ============================================================================

function M.mixin(cls)

    -- ========================================================================
    -- 工具函数
    -- ========================================================================

    function cls:_deepCopy(orig)
        if type(orig) ~= "table" then return orig end
        local copy = {}
        for k, v in pairs(orig) do
            if type(v) == "table" then
                copy[k] = self:_deepCopy(v)
            else
                copy[k] = v
            end
        end
        return copy
    end

    -- ========================================================================
    -- 撤销/重做
    -- ========================================================================

    function cls:_pushUndo()
        self:_syncToLevelData()
        local snapshot = self:_deepCopy(self.levels[self.currentLevel])
        table.insert(self.undoStack, { level = self.currentLevel, data = snapshot })
        if #self.undoStack > M.MAX_UNDO_STEPS then
            table.remove(self.undoStack, 1)
        end
        self.redoStack = {}
    end

    function cls:undo()
        if #self.undoStack == 0 then return end
        self:_syncToLevelData()
        local curSnapshot = self:_deepCopy(self.levels[self.currentLevel])
        table.insert(self.redoStack, { level = self.currentLevel, data = curSnapshot })

        local prev = table.remove(self.undoStack)
        self.levels[prev.level] = prev.data
        if prev.level ~= self.currentLevel then
            self.currentLevel = prev.level
            self:_updateLevelLabel()
        end
        self:_createGround()
        self:_rebuildScene()
        log:Write(LOG_INFO, "[EditorLevel] Undo (stack: " .. #self.undoStack .. ")")
    end

    function cls:redo()
        if #self.redoStack == 0 then return end
        self:_syncToLevelData()
        local curSnapshot = self:_deepCopy(self.levels[self.currentLevel])
        table.insert(self.undoStack, { level = self.currentLevel, data = curSnapshot })

        local next = table.remove(self.redoStack)
        self.levels[next.level] = next.data
        if next.level ~= self.currentLevel then
            self.currentLevel = next.level
            self:_updateLevelLabel()
        end
        self:_createGround()
        self:_rebuildScene()
        log:Write(LOG_INFO, "[EditorLevel] Redo (stack: " .. #self.redoStack .. ")")
    end

    -- ========================================================================
    -- 复制/粘贴
    -- ========================================================================

    function cls:copySelected()
        if not self.selectedObject then return end
        local obj = self.selectedObject
        self.clipboard = {
            typeId = obj.typeId,
            data = self:_deepCopy(obj.data),
            w = obj.w,
            h = obj.h,
        }
        log:Write(LOG_INFO, "[EditorLevel] Copied: " .. obj.typeId)
    end

    function cls:paste()
        if not self.clipboard then return end
        self:_pushUndo()
        local obj = self:_spawnObject(
            self.clipboard.typeId,
            self.hoverSnapX,
            self.hoverSnapY,
            self:_deepCopy(self.clipboard.data)
        )
        if obj then
            self.selectedObject = obj
            self:_syncToLevelData()
            self:_updateSelectedLabel()
        end
        log:Write(LOG_INFO, "[EditorLevel] Pasted: " .. self.clipboard.typeId)
    end

    -- ========================================================================
    -- 数据同步
    -- ========================================================================

    function cls:_syncToLevelData()
        local level = self.levels[self.currentLevel]
        level.platforms = {}
        level.enemies = {}
        level.portalX = nil
        level.portalY = nil

        for _, obj in ipairs(self.objects) do
            local pos = obj.node.position
            local imgPath = (obj.data and obj.data.image) or nil
            if obj.typeId == "platform" then
                table.insert(level.platforms, {
                    x = pos.x, y = pos.y,
                    w = obj.w or 5.0, h = obj.h or 0.3,
                    image = imgPath,
                })
            elseif obj.typeId:find("^enemy_") then
                local element = obj.typeId:gsub("enemy_", "")
                local isBoss = (element == "boss")
                if isBoss then element = "fire" end
                table.insert(level.enemies, {
                    x = pos.x, y = pos.y,
                    element = element,
                    boss = isBoss,
                    image = imgPath,
                })
            elseif obj.typeId == "portal" then
                level.portalX = pos.x
                level.portalY = pos.y
                level.portalImage = imgPath
            elseif obj.typeId == "spawn" then
                level.spawnX = pos.x
                level.spawnY = pos.y
                level.spawnImage = imgPath
            end
        end

        local enemyLbl = self.propsPanel and self.propsPanel:FindById("lbl_enemy_count")
        if enemyLbl then
            local count = type(level.enemies) == "table" and #level.enemies or 0
            enemyLbl:SetText("敌人数量: " .. count)
        end
    end

    -- ========================================================================
    -- 删除和清除
    -- ========================================================================

    function cls:_deleteSelected()
        if not self.selectedObject then return end
        self:_pushUndo()

        for i, obj in ipairs(self.objects) do
            if obj == self.selectedObject then
                table.remove(self.objects, i)
                break
            end
        end

        self.selectedObject.node:Remove()
        self.selectedObject = nil
        self:_updateSelectedLabel()
        self:_syncToLevelData()
    end

    function cls:_clearLevel()
        self:_pushUndo()
        for _, obj in ipairs(self.objects) do
            obj.node:Remove()
        end
        self.objects = {}
        self.selectedObject = nil
        self.levels[self.currentLevel] = self:_deepCopy(M.DEFAULT_LEVEL)
        self:_createGround()
        self:_updateSelectedLabel()
    end

    -- ========================================================================
    -- 关卡管理
    -- ========================================================================

    function cls:_centerCameraOnLevel()
        local level = self.levels[self.currentLevel]
        if not level then return end

        local minX, maxX = 0, level.groundWidth or 20
        local minY, maxY = level.groundY or -2.5, 2.0

        for _, p in ipairs(level.platforms or {}) do
            local px = p.x or 0
            local py = p.y or 0
            local pw = p.w or 5.0
            local ph = p.h or 0.3
            if px - pw / 2 < minX then minX = px - pw / 2 end
            if px + pw / 2 > maxX then maxX = px + pw / 2 end
            if py - ph / 2 < minY then minY = py - ph / 2 end
            if py + ph / 2 > maxY then maxY = py + ph / 2 end
        end
        for _, e in ipairs(level.enemies or {}) do
            if e.x and e.x > maxX then maxX = e.x end
            if e.x and e.x < minX then minX = e.x end
            if e.y and e.y < minY then minY = e.y end
            if e.y and e.y > maxY then maxY = e.y end
        end
        if level.portalX then
            if level.portalX > maxX then maxX = level.portalX end
        end

        self.camX = (minX + maxX) / 2
        self.camY = (minY + maxY) / 2

        local contentW = maxX - minX + 4
        local contentH = maxY - minY + 4
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local aspect = screenW / screenH
        local zoomForW = contentW / aspect
        local zoomForH = contentH
        self.zoom = math.max(10, math.min(60, math.max(zoomForW, zoomForH)))
        self.camera.orthoSize = self.zoom
        self.cameraNode.position = Vector3(self.camX, self.camY, -10)
    end

    function cls:_switchLevel(delta)
        local newLevel = self.currentLevel + delta
        if newLevel < 1 then newLevel = 1 end
        if newLevel > #self.levels then newLevel = #self.levels end
        if newLevel == self.currentLevel then return end

        self:_syncToLevelData()
        self.currentLevel = newLevel
        self:_createGround()
        self:_rebuildScene()
        self:_updateLevelLabel()
        self:_centerCameraOnLevel()
    end

    function cls:_addLevel()
        local newLevel = self:_deepCopy(M.DEFAULT_LEVEL)
        newLevel.name = "新关卡 " .. (#self.levels + 1)
        table.insert(self.levels, newLevel)
        self:_syncToLevelData()
        self.currentLevel = #self.levels
        self:_createGround()
        self:_rebuildScene()
        self:_updateLevelLabel()
        self:_centerCameraOnLevel()
    end

    function cls:_jumpToLevel(targetLevel)
        if targetLevel < 1 or targetLevel > #self.levels then
            log:Write(LOG_WARNING, "[EditorLevel] Level " .. targetLevel .. " not available (total: " .. #self.levels .. ")")
            return
        end
        if targetLevel == self.currentLevel then return end

        self:_syncToLevelData()
        self.currentLevel = targetLevel
        self:_createGround()
        self:_rebuildScene()
        self:_updateLevelLabel()
        self:_centerCameraOnLevel()
    end

    -- ========================================================================
    -- 文件 I/O
    -- ========================================================================

    function cls:saveToJSON()
        self:_syncToLevelData()
        local data = { levels = self.levels }
        local jsonStr = cjson.encode(data)

        local file = File("editor_levels.json", FILE_WRITE)
        if file:IsOpen() then
            file:WriteString(jsonStr)
            file:Close()
            log:Write(LOG_INFO, "[EditorLevel] Saved " .. #self.levels .. " levels to editor_levels.json")
        end
    end

    function cls:loadFromJSON()
        if not fileSystem:FileExists("editor_levels.json") then
            log:Write(LOG_WARNING, "[EditorLevel] No saved file found")
            return false
        end

        local file = File("editor_levels.json", FILE_READ)
        if not file:IsOpen() then return false end
        local jsonStr = file:ReadString()
        file:Close()

        local ok, data = pcall(cjson.decode, jsonStr)
        if not ok or not data.levels then
            log:Write(LOG_ERROR, "[EditorLevel] Failed to parse JSON")
            return false
        end

        self.levels = data.levels
        self.currentLevel = 1
        self.undoStack = {}
        self.redoStack = {}
        self:_createGround()
        self:_rebuildScene()
        self:_updateLevelLabel()
        self:_centerCameraOnLevel()

        log:Write(LOG_INFO, "[EditorLevel] Loaded " .. #self.levels .. " levels")
        return true
    end

    function cls:_exportLua()
        self:_syncToLevelData()
        local lines = {}
        table.insert(lines, "local LEVELS = {")

        for i, level in ipairs(self.levels) do
            table.insert(lines, string.format("    [%d] = {", i))
            table.insert(lines, string.format('        name = "%s",', level.name or ("第" .. i .. "关")))
            table.insert(lines, string.format("        groundWidth = %.1f,", level.groundWidth))

            table.insert(lines, "        platforms = {")
            for _, p in ipairs(level.platforms or {}) do
                table.insert(lines, string.format(
                    "            { x = %.1f, y = %.1f, w = %.1f, h = %.1f },",
                    p.x, p.y, p.w or 5.0, p.h or 0.3
                ))
            end
            table.insert(lines, "        },")

            if type(level.enemies) == "table" and #level.enemies > 0 then
                table.insert(lines, "        enemies = {")
                for _, e in ipairs(level.enemies) do
                    if e.boss then
                        table.insert(lines, string.format(
                            '            { x = %.1f, y = %.1f, element = "%s", boss = true },',
                            e.x, e.y, e.element
                        ))
                    else
                        table.insert(lines, string.format(
                            '            { x = %.1f, y = %.1f, element = "%s" },',
                            e.x, e.y, e.element
                        ))
                    end
                end
                table.insert(lines, "        },")
            end

            if level.portalX then
                table.insert(lines, string.format("        portalX = %.1f,", level.portalX))
                table.insert(lines, string.format("        portalY = %.1f,", level.portalY or -2.0))
            end

            table.insert(lines, "    },")
        end

        table.insert(lines, "}")

        local code = table.concat(lines, "\n")
        local file = File("editor_levels_export.lua", FILE_WRITE)
        if file:IsOpen() then
            file:WriteString(code)
            file:Close()
            log:Write(LOG_INFO, "[EditorLevel] Exported Lua code")
        end
    end

    -- ========================================================================
    -- 游戏关卡导入
    -- ========================================================================

    function cls:_importAllGameLevels()
        -- 优先尝试加载已保存的 JSON 文件
        if fileSystem:FileExists("editor_levels.json") then
            local file = File("editor_levels.json", FILE_READ)
            if file:IsOpen() then
                local jsonStr = file:ReadString()
                file:Close()
                local ok, data = pcall(cjson.decode, jsonStr)
                if ok and data.levels and #data.levels > 0 then
                    self.levels = data.levels
                    self.currentLevel = 1
                    self.undoStack = {}
                    self.redoStack = {}
                    self:_createGround()
                    self:_rebuildScene()
                    self:_updateLevelLabel()
                    self:_centerCameraOnLevel()
                    log:Write(LOG_INFO, "[EditorLevel] Loaded " .. #self.levels .. " levels from editor_levels.json")
                    return
                end
            end
        end

        -- JSON 不存在或无效时，从硬编码的 GAME_LEVELS 导入
        self.levels = {}
        for i = 1, #M.GAME_LEVELS do
            local src = M.GAME_LEVELS[i]
            local level = {
                name = src.name or ("第" .. i .. "关"),
                groundWidth = src.groundWidth or 100.0,
                groundY = -2.5,
                platforms = {},
                enemies = {},
                portalX = src.portalX,
                portalY = src.portalY or -2.0,
                spawnX = 0.0,
                spawnY = -1.5,
            }
            for _, p in ipairs(src.platforms or {}) do
                table.insert(level.platforms, { x = p.x, y = p.y, w = p.w or 5.0, h = p.h or 0.3 })
            end
            if type(src.enemies) == "table" then
                for _, e in ipairs(src.enemies) do
                    table.insert(level.enemies, { x = e.x, y = e.y, element = e.element, boss = e.boss })
                end
            elseif src.enemies == "random" and src.spawnZones and src.enemyCount then
                local ELEMENTS = { "fire", "ice", "thunder", "grass", "earth" }
                local count = src.enemyCount or 8
                for ei = 1, count do
                    local zone = src.spawnZones[((ei - 1) % #src.spawnZones) + 1]
                    local t = count > 1 and ((ei - 1) / (count - 1)) or 0.5
                    local ex = zone.xMin + (zone.xMax - zone.xMin) * t
                    local ey = zone.y or -1.9
                    local elem = ELEMENTS[((ei - 1) % #ELEMENTS) + 1]
                    table.insert(level.enemies, { x = ex, y = ey, element = elem })
                end
            elseif src.enemies == "boss_only" then
                local bossX = (src.groundWidth or 80) * 0.4
                table.insert(level.enemies, { x = bossX, y = 2.0, element = "fire", boss = true })
            end
            table.insert(self.levels, level)
        end

        self.currentLevel = 1
        self.undoStack = {}
        self.redoStack = {}
        self:_createGround()
        self:_rebuildScene()
        self:_updateLevelLabel()
        self:_centerCameraOnLevel()
        log:Write(LOG_INFO, "[EditorLevel] Imported " .. #self.levels .. " game levels from GAME_LEVELS (no saved JSON)")
    end

    -- ========================================================================
    -- 测试关卡
    -- ========================================================================

    function cls:_testCurrentLevel()
        local levelNum = self.currentLevel
        log:Write(LOG_INFO, "[EditorLevel] Test level " .. levelNum .. " requested")
        if self.onTestLevel then
            self.onTestLevel(levelNum)
        end
    end

    function cls:getCurrentLevel()
        return self.currentLevel
    end

end -- mixin

return M
