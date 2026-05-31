-- editor_level_ui.lua
-- 关卡编辑器 - UI层（面板构建、工具选择、Inspector、资源浏览器）
---@diagnostic disable: undefined-global, redefined-local

local UI = require("urhox-libs/UI")
local EditorLevelData = require("editor/editor_level_data")
local ELEM_TYPES = EditorLevelData.ELEM_TYPES

local M = {}

function M.mixin(cls)

    -- ========================================================================
    -- 资源扫描
    -- ========================================================================

    function cls:_scanAssetFolders()
        self.assetCategories = {}
        local categories = {
            { name = "敌人", path = "image/Enemy" },
            { name = "玩家", path = "image/Player" },
            { name = "地板", path = "image/tiles/floor" },
            { name = "墙壁", path = "image/tiles/wall" },
            { name = "特殊", path = "image/tiles/special" },
            { name = "背景", path = "image/backgrounds/dungeon_rooms" },
            { name = "UI", path = "image/UI" },
            { name = "卡牌", path = "image/card" },
            { name = "五感", path = "image/TheFiveSenses/normal" },
            { name = "开始界面", path = "image/开始游戏界面" },
        }

        for _, cat in ipairs(categories) do
            local files = {}
            local knownFiles = self:_getKnownFiles(cat.path)
            for _, fname in ipairs(knownFiles) do
                table.insert(files, {
                    name = fname,
                    path = cat.path .. "/" .. fname,
                })
            end
            if #files > 0 then
                table.insert(self.assetCategories, {
                    name = cat.name,
                    path = cat.path,
                    files = files,
                })
            end
        end
    end

    function cls:_getKnownFiles(dirPath)
        local fileMap = {
            ["image/Enemy"] = {
                "boss_01.png", "boss_01_walk.png", "boss_01_skill_01.png",
            },
            ["image/Enemy/fire"] = { "enemy_fire_walk.png" },
            ["image/Enemy/ice"] = { "enemy_ice_walk.png", "enemy_ice_atk.png" },
            ["image/Enemy/thunder"] = { "enemy_thunder_walk.png" },
            ["image/Enemy/grass"] = { "enemy_grass_walk.png", "enemy_grass_atk.png" },
            ["image/Enemy/earth"] = { "enemy_earth_walk.png", "enemy_earth_atk.png" },
            ["image/Player"] = {
                "player_idle.png", "player_walk.png", "player_atk.png",
                "player_atk_end.png", "player_jump.png", "player_die.png",
            },
            ["image/tiles/floor"] = { "cracked_floor.png", "gold_floor.png", "stone_floor.png" },
            ["image/tiles/wall"] = { "ceiling.png", "dark_brick.png", "stone_wall.png" },
            ["image/tiles/special"] = { "platform_edge.png" },
            ["image/backgrounds/dungeon_rooms"] = {
                "room1_entrance.png", "room2_prison.png", "room3_sewer.png",
                "room4_altar.png", "room5_boss_throne.png",
            },
            ["image/UI"] = {
                "btn_attack.png", "btn_jump.png", "joystick_base.png", "start_bg.png",
            },
            ["image/card"] = {
                "card_F01_烈焰弹_20260530094100.png",
                "card_I01_冰霜刺_20260530094103.png",
                "card_T01_雷霆击_20260530120331.png",
                "card_W01_旋风斩_20260530094101.png",
                "card_E02_尖刺陷阱_20260530094325.png",
            },
            ["image/TheFiveSenses/normal"] = {
                "听觉_正常.png", "味觉_正常.png", "嗅觉_正常.png", "视觉_正常.png", "触觉_正常.png",
            },
            ["image/开始游戏界面"] = {
                "开始界面_无角色_最终版.png", "开始界面_有角色_最终版.png",
            },
        }

        if fileMap[dirPath] then
            return fileMap[dirPath]
        end

        local results = {}
        for path, files in pairs(fileMap) do
            if path:find("^" .. dirPath:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")) then
                for _, f in ipairs(files) do
                    local subDir = path:sub(#dirPath + 2)
                    local displayName = subDir ~= "" and (subDir .. "/" .. f) or f
                    table.insert(results, displayName)
                end
            end
        end
        return results
    end

    -- ========================================================================
    -- UI 构建
    -- ========================================================================

    function cls:_createUI()
        -- 构建工具按钮列表
        local toolChildren = {
            UI.Label {
                text = "工具箱",
                fontSize = 14,
                fontColor = { 200, 200, 230, 255 },
                fontWeight = "bold",
                marginBottom = 4,
            },
            UI.Button {
                id = "tool_select",
                text = "选择/移动 [0]",
                fontSize = 12,
                width = "100%",
                height = 28,
                variant = "primary",
                onClick = function() self:_selectTool(nil) end,
            },
            UI.Label {
                text = "── 放置 ──",
                fontSize = 11,
                fontColor = { 120, 120, 150, 255 },
                marginTop = 4,
            },
        }

        for _, elem in ipairs(ELEM_TYPES) do
            local btn = UI.Button {
                id = "tool_" .. elem.id,
                text = elem.name .. " [" .. elem.key .. "]",
                fontSize = 11,
                width = "100%",
                height = 26,
                variant = "outline",
                onClick = function()
                    self:_selectTool(elem.id)
                end,
            }
            table.insert(toolChildren, btn)
        end

        -- 撤销/重做按钮
        table.insert(toolChildren, UI.Panel { height = 8 })
        table.insert(toolChildren, UI.Label {
            text = "── 编辑 ──",
            fontSize = 11,
            fontColor = { 120, 120, 150, 255 },
        })
        table.insert(toolChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = {
                UI.Button {
                    text = "撤销",
                    fontSize = 11,
                    width = 55, height = 26,
                    variant = "outline",
                    onClick = function() self:undo() end,
                },
                UI.Button {
                    text = "重做",
                    fontSize = 11,
                    width = 55, height = 26,
                    variant = "outline",
                    onClick = function() self:redo() end,
                },
                UI.Button {
                    text = "复制",
                    fontSize = 11,
                    width = 55, height = 26,
                    variant = "outline",
                    onClick = function() self:copySelected() end,
                },
            },
        })
        table.insert(toolChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            marginTop = 2,
            children = {
                UI.Button {
                    text = "粘贴",
                    fontSize = 11,
                    width = 55, height = 26,
                    variant = "outline",
                    onClick = function() self:paste() end,
                },
                UI.Button {
                    text = "网格H",
                    fontSize = 11,
                    width = 55, height = 26,
                    variant = "outline",
                    onClick = function() self.showGrid = not self.showGrid end,
                },
            },
        })

        -- 左侧工具面板
        self.panel = UI.Panel {
            id = "level_panel",
            width = 180,
            height = "100%",
            backgroundColor = { 30, 30, 40, 230 },
            padding = 8,
            gap = 5,
            overflow = "scroll",
            children = toolChildren,
        }

        -- 右侧属性面板
        self.propsPanel = UI.Panel {
            id = "level_props",
            width = 200,
            height = "100%",
            backgroundColor = { 30, 30, 40, 230 },
            padding = 8,
            gap = 5,
            overflow = "scroll",
            children = {
                UI.Label {
                    text = "属性面板",
                    fontSize = 14,
                    fontColor = { 200, 200, 230, 255 },
                    fontWeight = "bold",
                },
                -- 关卡切换
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 4,
                    alignItems = "center",
                    children = {
                        UI.Label { text = "关卡:", fontSize = 12, fontColor = {180,180,200,255} },
                        UI.Button {
                            text = "<", width = 28, height = 24, fontSize = 12,
                            onClick = function() self:_switchLevel(-1) end,
                        },
                        UI.Label {
                            id = "lbl_level_num",
                            text = "1",
                            fontSize = 13,
                            fontColor = {255,255,255,255},
                            width = 24,
                            textAlign = "center",
                        },
                        UI.Button {
                            text = ">", width = 28, height = 24, fontSize = 12,
                            onClick = function() self:_switchLevel(1) end,
                        },
                        UI.Button {
                            text = "+", width = 28, height = 24, fontSize = 12,
                            variant = "success",
                            onClick = function() self:_addLevel() end,
                        },
                    }
                },
                -- 地面宽度
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 4,
                    alignItems = "center",
                    children = {
                        UI.Label { text = "地面宽:", fontSize = 11, fontColor = {180,180,200,255} },
                        UI.Slider {
                            id = "slider_ground_w",
                            width = 90,
                            value = 100,
                            min = 20,
                            max = 300,
                            step = 10,
                            onChange = function(_, v)
                                self:_pushUndo()
                                self.levels[self.currentLevel].groundWidth = v
                                self:_createGround()
                            end,
                        },
                        UI.Label {
                            id = "lbl_ground_w",
                            text = "100",
                            fontSize = 11,
                            fontColor = {150,150,180,255},
                        },
                    }
                },
                -- Inspector 区域
                UI.Panel { height = 4 },
                UI.Label {
                    text = "── 检视器 ──",
                    fontSize = 11,
                    fontColor = { 120, 120, 150, 255 },
                },
                UI.Label {
                    id = "lbl_selected",
                    text = "未选中对象",
                    fontSize = 12,
                    fontColor = { 150, 200, 150, 255 },
                    marginTop = 4,
                },
                UI.Label {
                    id = "lbl_pos",
                    text = "",
                    fontSize = 11,
                    fontColor = { 150, 150, 180, 255 },
                },
                -- 对象尺寸
                UI.Panel {
                    id = "inspector_size_panel",
                    width = "100%",
                    flexDirection = "row",
                    gap = 4,
                    alignItems = "center",
                    marginTop = 2,
                    children = {
                        UI.Label { text = "尺寸:", fontSize = 11, fontColor = {150,150,180,255} },
                        UI.Label {
                            id = "lbl_obj_size",
                            text = "",
                            fontSize = 11,
                            fontColor = {200,200,230,255},
                        },
                    },
                },
                -- 贴图信息
                UI.Panel {
                    id = "inspector_image_panel",
                    width = "100%",
                    marginTop = 4,
                    gap = 3,
                    children = {
                        UI.Label { text = "贴图:", fontSize = 11, fontColor = {150,150,180,255} },
                        UI.Label {
                            id = "lbl_obj_image",
                            text = "无",
                            fontSize = 10,
                            fontColor = { 180, 220, 255, 255 },
                        },
                        UI.Button {
                            id = "btn_change_image",
                            text = "选择贴图...",
                            fontSize = 11,
                            width = "100%", height = 26,
                            marginTop = 2,
                            variant = "outline",
                            onClick = function() self:_openAssetBrowser() end,
                        },
                        UI.Button {
                            id = "btn_clear_image",
                            text = "清除贴图",
                            fontSize = 11,
                            width = "100%", height = 24,
                            marginTop = 2,
                            variant = "outline",
                            onClick = function() self:_clearObjectImage() end,
                        },
                    },
                },
                -- 敌人属性面板
                UI.Panel {
                    id = "inspector_enemy_panel",
                    width = "100%",
                    marginTop = 4,
                    gap = 3,
                    children = {
                        UI.Label { text = "── 敌人属性 ──", fontSize = 11, fontColor = {120,120,150,255} },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            gap = 4, alignItems = "center",
                            children = {
                                UI.Label { text = "元素:", fontSize = 11, fontColor = {150,150,180,255} },
                                UI.Label {
                                    id = "lbl_enemy_element",
                                    text = "",
                                    fontSize = 12,
                                    fontColor = {255,220,100,255},
                                    fontWeight = "bold",
                                },
                            },
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            gap = 4, alignItems = "center",
                            children = {
                                UI.Label { text = "Boss:", fontSize = 11, fontColor = {150,150,180,255} },
                                UI.Label {
                                    id = "lbl_enemy_boss",
                                    text = "",
                                    fontSize = 11,
                                    fontColor = {255,150,150,255},
                                },
                            },
                        },
                    },
                },
                -- 操作按钮
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 4,
                    marginTop = 6,
                    children = {
                        UI.Button {
                            text = "删除选中",
                            fontSize = 11,
                            width = 70, height = 26,
                            variant = "danger",
                            onClick = function() self:_deleteSelected() end,
                        },
                        UI.Button {
                            text = "清空关卡",
                            fontSize = 11,
                            width = 70, height = 26,
                            variant = "outline",
                            onClick = function() self:_clearLevel() end,
                        },
                    },
                },
                -- 文件操作
                UI.Panel { height = 8 },
                UI.Label {
                    text = "── 文件 ──",
                    fontSize = 11,
                    fontColor = { 120, 120, 150, 255 },
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 4,
                    children = {
                        UI.Button {
                            text = "保存JSON",
                            fontSize = 11,
                            width = 80, height = 26,
                            variant = "primary",
                            onClick = function() self:saveToJSON() end,
                        },
                        UI.Button {
                            text = "加载JSON",
                            fontSize = 11,
                            width = 80, height = 26,
                            variant = "outline",
                            onClick = function() self:loadFromJSON() end,
                        },
                    },
                },
                UI.Button {
                    text = "导出Lua代码",
                    fontSize = 11,
                    width = "100%", height = 26,
                    marginTop = 4,
                    variant = "outline",
                    onClick = function() self:_exportLua() end,
                },
                -- 场景导入区域
                UI.Panel { height = 8 },
                UI.Label {
                    text = "── 游戏场景 ──",
                    fontSize = 11,
                    fontColor = { 120, 120, 150, 255 },
                },
                UI.Button {
                    text = "导入全部游戏场景",
                    fontSize = 11,
                    width = "100%", height = 28,
                    marginTop = 4,
                    variant = "primary",
                    onClick = function() self:_importAllGameLevels() end,
                },
                UI.Label {
                    text = "── 快速跳转 ──",
                    fontSize = 11,
                    fontColor = { 120, 120, 150, 255 },
                    marginTop = 4,
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 3,
                    children = {
                        UI.Button { text = "1", width = 28, height = 24, fontSize = 11, onClick = function() self:_jumpToLevel(1) end },
                        UI.Button { text = "2", width = 28, height = 24, fontSize = 11, onClick = function() self:_jumpToLevel(2) end },
                        UI.Button { text = "3", width = 28, height = 24, fontSize = 11, onClick = function() self:_jumpToLevel(3) end },
                        UI.Button { text = "4", width = 28, height = 24, fontSize = 11, onClick = function() self:_jumpToLevel(4) end },
                        UI.Button { text = "5", width = 28, height = 24, fontSize = 11, onClick = function() self:_jumpToLevel(5) end },
                    },
                },
                UI.Label {
                    id = "lbl_level_name",
                    text = "",
                    fontSize = 11,
                    fontColor = { 180, 200, 255, 255 },
                    marginTop = 4,
                },
                UI.Label {
                    id = "lbl_enemy_count",
                    text = "敌人数量: 0",
                    fontSize = 11,
                    fontColor = { 255, 180, 120, 255 },
                    marginTop = 2,
                },
                -- 测试按钮区域
                UI.Panel { height = 8 },
                UI.Label {
                    text = "── 测试 ──",
                    fontSize = 11,
                    fontColor = { 120, 120, 150, 255 },
                },
                UI.Button {
                    id = "btn_test_level",
                    text = "测试当前关卡",
                    fontSize = 12,
                    width = "100%",
                    height = 32,
                    marginTop = 4,
                    variant = "success",
                    onClick = function()
                        self:_testCurrentLevel()
                    end,
                },
            },
        }
    end

    -- ========================================================================
    -- 工具选择
    -- ========================================================================

    function cls:_selectTool(toolId)
        self.selectedTool = toolId
        self.selectedObject = nil

        if self.panel then
            local selectBtn = self.panel:FindById("tool_select")
            if selectBtn then
                selectBtn:SetVariant(toolId == nil and "primary" or "outline")
            end
            for _, elem in ipairs(ELEM_TYPES) do
                local btn = self.panel:FindById("tool_" .. elem.id)
                if btn then
                    btn:SetVariant(elem.id == toolId and "primary" or "outline")
                end
            end
        end
    end

    -- ========================================================================
    -- Inspector 更新
    -- ========================================================================

    function cls:_updateSelectedLabel()
        if not self.propsPanel then return end
        local lbl = self.propsPanel:FindById("lbl_selected")
        local posLbl = self.propsPanel:FindById("lbl_pos")
        local sizeLbl = self.propsPanel:FindById("lbl_obj_size")
        local imageLbl = self.propsPanel:FindById("lbl_obj_image")
        local sizePanel = self.propsPanel:FindById("inspector_size_panel")
        local imagePanel = self.propsPanel:FindById("inspector_image_panel")
        local enemyPanel = self.propsPanel:FindById("inspector_enemy_panel")
        local enemyElemLbl = self.propsPanel:FindById("lbl_enemy_element")
        local enemyBossLbl = self.propsPanel:FindById("lbl_enemy_boss")
        if not lbl then return end

        if self.selectedObject then
            local pos = self.selectedObject.node.position
            local elemName = self.selectedObject.typeId
            for _, e in ipairs(ELEM_TYPES) do
                if e.id == self.selectedObject.typeId then elemName = e.name; break end
            end
            lbl:SetText("已选中: " .. elemName)
            if posLbl then
                posLbl:SetText(string.format("位置: (%.1f, %.1f)", pos.x, pos.y))
            end
            if sizeLbl then
                if self.selectedObject.typeId == "platform" then
                    sizeLbl:SetText(string.format("%.1f x %.1f", self.selectedObject.w or 5.0, self.selectedObject.h or 0.3))
                else
                    sizeLbl:SetText(string.format("%.1f x %.1f", self.selectedObject.w or 1.0, self.selectedObject.h or 1.0))
                end
            end
            if sizePanel then sizePanel:Show() end
            if imageLbl then
                local imgPath = self.selectedObject.data and self.selectedObject.data.image
                if imgPath and imgPath ~= "" then
                    local fname = imgPath:match("([^/]+)$") or imgPath
                    imageLbl:SetText(fname)
                else
                    imageLbl:SetText("无 (纯色)")
                end
            end
            if imagePanel then imagePanel:Show() end
            -- 敌人属性
            local isEnemy = self.selectedObject.typeId:find("^enemy_") ~= nil
            if isEnemy then
                if enemyPanel then enemyPanel:Show() end
                local elemMap = { fire = "火", ice = "冰", thunder = "雷", grass = "草", earth = "土", boss = "Boss" }
                local rawElem = self.selectedObject.typeId:gsub("enemy_", "")
                local elemDisplay = elemMap[rawElem] or rawElem
                if enemyElemLbl then enemyElemLbl:SetText(elemDisplay) end
                local isBoss = (rawElem == "boss")
                if enemyBossLbl then enemyBossLbl:SetText(isBoss and "是" or "否") end
            else
                if enemyPanel then enemyPanel:Hide() end
            end
        else
            lbl:SetText("未选中对象")
            if posLbl then posLbl:SetText("") end
            if sizeLbl then sizeLbl:SetText("") end
            if sizePanel then sizePanel:Hide() end
            if imageLbl then imageLbl:SetText("") end
            if imagePanel then imagePanel:Hide() end
            if enemyPanel then enemyPanel:Hide() end
        end
    end

    function cls:_updateLevelLabel()
        local lbl = self.propsPanel and self.propsPanel:FindById("lbl_level_num")
        if lbl then lbl:SetText(tostring(self.currentLevel)) end

        local level = self.levels[self.currentLevel]

        local nameLbl = self.propsPanel and self.propsPanel:FindById("lbl_level_name")
        if nameLbl then
            local name = level and level.name or ""
            nameLbl:SetText(name)
        end

        local enemyLbl = self.propsPanel and self.propsPanel:FindById("lbl_enemy_count")
        if enemyLbl and level then
            local count = 0
            if type(level.enemies) == "table" then
                count = #level.enemies
            end
            enemyLbl:SetText("敌人数量: " .. count)
        end
    end

    -- ========================================================================
    -- 资源浏览器
    -- ========================================================================

    function cls:_openAssetBrowser()
        if not self.selectedObject then return end
        if self.assetBrowserOpen then return end

        self.assetBrowserOpen = true

        local categoryChildren = {}
        for catIdx, cat in ipairs(self.assetCategories) do
            table.insert(categoryChildren, UI.Label {
                text = "▸ " .. cat.name,
                fontSize = 12,
                fontColor = { 255, 220, 100, 255 },
                fontWeight = "bold",
                marginTop = catIdx > 1 and 8 or 0,
            })
            for _, file in ipairs(cat.files) do
                local displayName = file.name:match("([^/]+)$") or file.name
                if #displayName > 20 then
                    displayName = displayName:sub(1, 17) .. "..."
                end
                table.insert(categoryChildren, UI.Button {
                    text = displayName,
                    fontSize = 10,
                    width = "100%",
                    height = 24,
                    variant = "outline",
                    marginTop = 1,
                    onClick = function()
                        self:_selectAssetImage(file.path)
                    end,
                })
            end
        end

        self.assetBrowserPanel = UI.Panel {
            id = "asset_browser",
            position = "absolute",
            left = "25%",
            top = "10%",
            width = "50%",
            height = "80%",
            backgroundColor = { 25, 25, 35, 245 },
            borderWidth = 2,
            borderColor = { 100, 150, 255, 200 },
            borderRadius = 8,
            padding = 12,
            gap = 4,
            overflow = "scroll",
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    marginBottom = 8,
                    children = {
                        UI.Label {
                            text = "选择贴图资源",
                            fontSize = 16,
                            fontColor = { 255, 255, 255, 255 },
                            fontWeight = "bold",
                        },
                        UI.Button {
                            text = "✕ 关闭",
                            fontSize = 12,
                            width = 60, height = 28,
                            variant = "danger",
                            onClick = function() self:_closeAssetBrowser() end,
                        },
                    },
                },
                UI.Label {
                    text = "点击选择要应用到当前对象的贴图：",
                    fontSize = 11,
                    fontColor = { 160, 160, 190, 255 },
                    marginBottom = 6,
                },
                table.unpack(categoryChildren),
            },
        }
        UI.SetRoot(self.assetBrowserPanel)
    end

    function cls:_closeAssetBrowser()
        self.assetBrowserOpen = false
        if self.assetBrowserPanel then
            self.assetBrowserPanel:Hide()
            self.assetBrowserPanel = nil
        end
    end

    function cls:_selectAssetImage(imagePath)
        if not self.selectedObject then
            self:_closeAssetBrowser()
            return
        end

        self:_pushUndo()

        if not self.selectedObject.data then
            self.selectedObject.data = {}
        end
        self.selectedObject.data.image = imagePath

        self:_applyImageToObject(self.selectedObject)
        self:_updateSelectedLabel()
        self:_syncToLevelData()
        self:_closeAssetBrowser()
    end

    function cls:_clearObjectImage()
        if not self.selectedObject then return end

        self:_pushUndo()

        if self.selectedObject.data then
            self.selectedObject.data.image = nil
        end

        self:_applyColorToObject(self.selectedObject)
        self:_updateSelectedLabel()
        self:_syncToLevelData()
    end

end -- mixin

return M
