-- UI可视化编辑器（增强版）
-- 功能：平移缩放画布、拖拽调整UI元素、创建UI图片、资源替换预览、导出配置
---@diagnostic disable: redefined-local, undefined-global
local UI = require("urhox-libs/UI")

local EditorUI = {}
EditorUI.__index = EditorUI

-- 游戏所有UI图片资源分类
local UI_RESOURCES = {
    {
        category = "操作按钮",
        items = {
            { name = "摇杆底座", path = "image/UI/joystick_base.png" },
            { name = "摇杆", path = "image/UI/摇杆.png" },
            { name = "攻击按钮", path = "image/UI/btn_attack.png" },
            { name = "跳跃按钮", path = "image/UI/btn_jump.png" },
            { name = "攻击(旧)", path = "image/UI/攻击.png" },
            { name = "跳跃(旧)", path = "image/UI/跳跃.png" },
        },
    },
    {
        category = "倒计时",
        items = {
            { name = "齿轮1", path = "image/UI/time_01.png" },
            { name = "齿轮2", path = "image/UI/time_02.png" },
            { name = "齿轮3", path = "image/UI/time_03.png" },
            { name = "齿轮4", path = "image/UI/time_04.png" },
            { name = "齿轮5", path = "image/UI/time_05.png" },
        },
    },
    {
        category = "五感图标(正常)",
        items = {
            { name = "视觉_正常", path = "image/TheFiveSenses/normal/视觉_正常.png" },
            { name = "听觉_正常", path = "image/TheFiveSenses/normal/听觉_正常.png" },
            { name = "嗅觉_正常", path = "image/TheFiveSenses/normal/嗅觉_正常.png" },
            { name = "味觉_正常", path = "image/TheFiveSenses/normal/味觉_正常.png" },
            { name = "触觉_正常", path = "image/TheFiveSenses/normal/触觉_正常.png" },
        },
    },
    {
        category = "五感图标(异常)",
        items = {
            { name = "视觉_异常", path = "image/TheFiveSenses/abnormal/视觉_异常.png" },
            { name = "听觉_异常", path = "image/TheFiveSenses/abnormal/听觉_异常.png" },
            { name = "嗅觉_异常", path = "image/TheFiveSenses/abnormal/嗅觉_异常.png" },
            { name = "味觉_异常", path = "image/TheFiveSenses/abnormal/味觉_异常.png" },
            { name = "触觉_异常", path = "image/TheFiveSenses/abnormal/触觉_异常.png" },
        },
    },
    {
        category = "角色",
        items = {
            { name = "玩家_待机", path = "image/Player/player_idle.png" },
            { name = "玩家_行走", path = "image/Player/player_walk.png" },
            { name = "玩家_跳跃", path = "image/Player/player_jump.png" },
            { name = "玩家_攻击", path = "image/Player/player_atk.png" },
            { name = "玩家_死亡", path = "image/Player/player_die.png" },
        },
    },
    {
        category = "背景",
        items = {
            { name = "开始界面", path = "image/开始游戏界面/开始界面_有角色_最终版.png" },
            { name = "关卡1", path = "image/backgrounds/dungeon_rooms/room1_entrance.png" },
            { name = "关卡2", path = "image/backgrounds/dungeon_rooms/room2_prison.png" },
            { name = "关卡3", path = "image/backgrounds/dungeon_rooms/room3_sewer.png" },
            { name = "关卡4", path = "image/backgrounds/dungeon_rooms/room4_altar.png" },
            { name = "关卡5", path = "image/backgrounds/dungeon_rooms/room5_boss_throne.png" },
        },
    },
}

-- 可编辑的UI元素类型（游戏UI布局）
local UI_ELEM_TYPES = {
    { id = "hp_bar", name = "血量条", defaultPos = {20, 20}, defaultSize = {300, 50}, align = "top_left", image = nil },
    { id = "countdown", name = "倒计时", defaultPos = {0, 10}, defaultSize = {64, 64}, align = "top_center", image = "image/UI/time_01.png" },
    { id = "joystick", name = "摇杆", defaultPos = {30, -120}, defaultSize = {140, 140}, align = "bottom_left", image = "image/UI/joystick_base.png" },
    { id = "jump_btn", name = "跳跃按钮", defaultPos = {-180, -120}, defaultSize = {80, 80}, align = "bottom_right", image = "image/UI/btn_jump.png" },
    { id = "attack_btn", name = "攻击按钮", defaultPos = {-80, -120}, defaultSize = {80, 80}, align = "bottom_right", image = "image/UI/btn_attack.png" },
    { id = "senses", name = "五感状态", defaultPos = {20, 70}, defaultSize = {200, 40}, align = "top_left", image = nil },
    { id = "cards", name = "卡牌栏", defaultPos = {-20, -160}, defaultSize = {400, 101}, align = "bottom_right", image = nil },
    { id = "level_indicator", name = "关卡指示", defaultPos = {-100, 20}, defaultSize = {80, 30}, align = "top_right", image = nil },
    { id = "portal_bar", name = "传送进度条", defaultPos = {0, 80}, defaultSize = {260, 60}, align = "center", image = nil },
}

function EditorUI:new(nvgCtx)
    local self = setmetatable({}, EditorUI)
    self.nvgCtx = nvgCtx
    self.elements = {}
    self.selectedElement = nil
    self.visible = false
    self.panel = nil
    self.propsPanel = nil

    -- 画布平移和缩放
    self.panX = 0
    self.panY = 0
    self.zoomScale = 1.0
    self.isPanning = false
    self.panStartX = 0
    self.panStartY = 0
    self.panOriginX = 0
    self.panOriginY = 0

    -- 元素拖拽
    self.isDragging = false
    self.dragStartX = 0
    self.dragStartY = 0
    self.elemStartX = 0
    self.elemStartY = 0

    -- 资源浏览
    self.resourcePanelVisible = false
    self.currentCategory = 1

    -- NanoVG 纹理缓存（资源路径 → nvgImage handle）
    self.imageCache = {}

    -- 初始化默认配置
    for _, def in ipairs(UI_ELEM_TYPES) do
        self.elements[def.id] = {
            id = def.id,
            name = def.name,
            x = def.defaultPos[1],
            y = def.defaultPos[2],
            w = def.defaultSize[1],
            h = def.defaultSize[2],
            align = def.align or "top_left",
            visible = true,
            image = def.image,  -- 关联的图片资源路径
        }
    end

    self:_createUI()
    return self
end

function EditorUI:_createUI()
    -- 左侧元素列表面板
    local panelChildren = {
        UI.Label {
            text = "UI 元素",
            fontSize = 14,
            fontColor = { 200, 200, 230, 255 },
            fontWeight = "bold",
            marginBottom = 4,
        },
    }

    -- 游戏UI元素按钮
    for _, def in ipairs(UI_ELEM_TYPES) do
        table.insert(panelChildren, UI.Button {
            id = "uielem_" .. def.id,
            text = def.name,
            fontSize = 11,
            width = "100%",
            height = 26,
            variant = "outline",
            onClick = function()
                self:_selectElement(def.id)
            end,
        })
    end

    -- 分隔 + 创建图片按钮
    table.insert(panelChildren, UI.Panel { height = 8 })
    table.insert(panelChildren, UI.Label {
        text = "── 创建 ──",
        fontSize = 11,
        fontColor = { 120, 120, 150, 255 },
    })
    table.insert(panelChildren, UI.Button {
        id = "btn_create_image",
        text = "+ 添加UI图片",
        fontSize = 12,
        width = "100%",
        height = 30,
        variant = "success",
        onClick = function()
            self:_createNewImageElement()
        end,
    })

    -- 操作提示
    table.insert(panelChildren, UI.Panel { height = 8 })
    table.insert(panelChildren, UI.Label {
        text = "── 操作 ──",
        fontSize = 11,
        fontColor = { 120, 120, 150, 255 },
    })
    table.insert(panelChildren, UI.Label {
        text = "右键拖拽: 平移画布",
        fontSize = 10,
        fontColor = { 130, 130, 160, 255 },
    })
    table.insert(panelChildren, UI.Label {
        text = "滚轮: 缩放画布",
        fontSize = 10,
        fontColor = { 130, 130, 160, 255 },
    })
    table.insert(panelChildren, UI.Label {
        text = "左键拖拽: 移动元素",
        fontSize = 10,
        fontColor = { 130, 130, 160, 255 },
    })

    self.panel = UI.Panel {
        id = "ui_panel",
        width = 200,
        height = "100%",
        backgroundColor = { 30, 30, 40, 230 },
        padding = 8,
        gap = 5,
        overflow = "hidden",
        children = panelChildren,
    }

    -- 右侧属性面板
    self.propsPanel = UI.Panel {
        id = "ui_props",
        width = 220,
        height = "100%",
        backgroundColor = { 30, 30, 40, 230 },
        padding = 8,
        gap = 5,
        overflow = "hidden",
        children = {
            UI.Label {
                text = "UI 属性",
                fontSize = 14,
                fontColor = { 200, 200, 230, 255 },
                fontWeight = "bold",
            },
            UI.Label {
                id = "ui_selected_name",
                text = "未选中",
                fontSize = 12,
                fontColor = { 150, 150, 180, 255 },
            },
            -- 位置X
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                alignItems = "center",
                children = {
                    UI.Label { text = "X:", fontSize = 12, fontColor = {180,180,200,255}, width = 30 },
                    UI.Slider {
                        id = "ui_pos_x",
                        width = 110,
                        value = 0,
                        min = -640,
                        max = 640,
                        step = 5,
                        onChange = function(_, v)
                            if self.selectedElement then
                                self.elements[self.selectedElement].x = math.floor(v)
                                self:_refreshProps()
                            end
                        end,
                    },
                    UI.Label { id = "ui_val_x", text = "0", fontSize = 11, fontColor = {150,150,180,255}, width = 35 },
                }
            },
            -- 位置Y
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                alignItems = "center",
                children = {
                    UI.Label { text = "Y:", fontSize = 12, fontColor = {180,180,200,255}, width = 30 },
                    UI.Slider {
                        id = "ui_pos_y",
                        width = 110,
                        value = 0,
                        min = -400,
                        max = 400,
                        step = 5,
                        onChange = function(_, v)
                            if self.selectedElement then
                                self.elements[self.selectedElement].y = math.floor(v)
                                self:_refreshProps()
                            end
                        end,
                    },
                    UI.Label { id = "ui_val_y", text = "0", fontSize = 11, fontColor = {150,150,180,255}, width = 35 },
                }
            },
            -- 宽度
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                alignItems = "center",
                children = {
                    UI.Label { text = "W:", fontSize = 12, fontColor = {180,180,200,255}, width = 30 },
                    UI.Slider {
                        id = "ui_size_w",
                        width = 110,
                        value = 100,
                        min = 20,
                        max = 800,
                        step = 5,
                        onChange = function(_, v)
                            if self.selectedElement then
                                self.elements[self.selectedElement].w = math.floor(v)
                                self:_refreshProps()
                            end
                        end,
                    },
                    UI.Label { id = "ui_val_w", text = "100", fontSize = 11, fontColor = {150,150,180,255}, width = 35 },
                }
            },
            -- 高度
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                alignItems = "center",
                children = {
                    UI.Label { text = "H:", fontSize = 12, fontColor = {180,180,200,255}, width = 30 },
                    UI.Slider {
                        id = "ui_size_h",
                        width = 110,
                        value = 50,
                        min = 20,
                        max = 600,
                        step = 5,
                        onChange = function(_, v)
                            if self.selectedElement then
                                self.elements[self.selectedElement].h = math.floor(v)
                                self:_refreshProps()
                            end
                        end,
                    },
                    UI.Label { id = "ui_val_h", text = "50", fontSize = 11, fontColor = {150,150,180,255}, width = 35 },
                }
            },
            -- 对齐方式
            UI.Label {
                text = "对齐:",
                fontSize = 12,
                fontColor = {180,180,200,255},
                marginTop = 4,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 3,
                children = {
                    UI.Button { id = "align_tl", text = "↖", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("top_left") end },
                    UI.Button { id = "align_tc", text = "↑", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("top_center") end },
                    UI.Button { id = "align_tr", text = "↗", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("top_right") end },
                    UI.Button { id = "align_bl", text = "↙", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("bottom_left") end },
                    UI.Button { id = "align_bc", text = "↓", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("bottom_center") end },
                    UI.Button { id = "align_br", text = "↘", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("bottom_right") end },
                    UI.Button { id = "align_c", text = "◎", width = 28, height = 24, fontSize = 12, onClick = function() self:_setAlign("center") end },
                },
            },
            -- 可见性和删除
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                marginTop = 6,
                children = {
                    UI.Button {
                        id = "btn_toggle_vis",
                        text = "显示/隐藏",
                        fontSize = 11,
                        width = 70, height = 26,
                        onClick = function()
                            if self.selectedElement then
                                local elem = self.elements[self.selectedElement]
                                elem.visible = not elem.visible
                            end
                        end,
                    },
                    UI.Button {
                        id = "btn_reset_elem",
                        text = "重置",
                        fontSize = 11,
                        width = 50, height = 26,
                        variant = "outline",
                        onClick = function() self:_resetElement() end,
                    },
                    UI.Button {
                        id = "btn_delete_elem",
                        text = "删除",
                        fontSize = 11,
                        width = 50, height = 26,
                        variant = "danger",
                        onClick = function() self:_deleteElement() end,
                    },
                },
            },
            -- 图片资源
            UI.Panel { height = 6 },
            UI.Label {
                text = "── 图片资源 ──",
                fontSize = 11,
                fontColor = { 120, 120, 150, 255 },
            },
            UI.Label {
                id = "lbl_current_image",
                text = "无图片",
                fontSize = 10,
                fontColor = { 140, 180, 140, 255 },
            },
            UI.Button {
                id = "btn_change_image",
                text = "替换图片资源",
                fontSize = 11,
                width = "100%",
                height = 26,
                variant = "primary",
                onClick = function()
                    self.resourcePanelVisible = not self.resourcePanelVisible
                end,
            },
            UI.Button {
                id = "btn_clear_image",
                text = "清除图片",
                fontSize = 11,
                width = "100%",
                height = 24,
                variant = "outline",
                onClick = function()
                    if self.selectedElement then
                        self.elements[self.selectedElement].image = nil
                        self:_refreshProps()
                    end
                end,
            },
            -- 资源分类选择器
            UI.Label {
                id = "lbl_res_category",
                text = "",
                fontSize = 11,
                fontColor = { 180, 200, 255, 255 },
                marginTop = 4,
            },
            UI.Panel {
                id = "res_category_btns",
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 2,
                children = {
                    UI.Button { text = "按钮", width = 40, height = 20, fontSize = 9, onClick = function() self:_setResourceCategory(1) end },
                    UI.Button { text = "倒计时", width = 45, height = 20, fontSize = 9, onClick = function() self:_setResourceCategory(2) end },
                    UI.Button { text = "五感", width = 40, height = 20, fontSize = 9, onClick = function() self:_setResourceCategory(3) end },
                    UI.Button { text = "异常", width = 40, height = 20, fontSize = 9, onClick = function() self:_setResourceCategory(4) end },
                    UI.Button { text = "角色", width = 40, height = 20, fontSize = 9, onClick = function() self:_setResourceCategory(5) end },
                    UI.Button { text = "背景", width = 40, height = 20, fontSize = 9, onClick = function() self:_setResourceCategory(6) end },
                },
            },
            -- 资源列表（动态更新文本）
            UI.Label {
                id = "lbl_res_list",
                text = "",
                fontSize = 10,
                fontColor = { 160, 160, 190, 255 },
                marginTop = 2,
            },
            -- 资源选择按钮（固定显示当前分类的前6个资源）
            UI.Panel {
                id = "res_items_panel",
                width = "100%",
                gap = 2,
                children = {
                    UI.Button { id = "res_item_1", text = "-", fontSize = 9, width = "100%", height = 20, variant = "outline", onClick = function() self:_applyResource(1) end },
                    UI.Button { id = "res_item_2", text = "-", fontSize = 9, width = "100%", height = 20, variant = "outline", onClick = function() self:_applyResource(2) end },
                    UI.Button { id = "res_item_3", text = "-", fontSize = 9, width = "100%", height = 20, variant = "outline", onClick = function() self:_applyResource(3) end },
                    UI.Button { id = "res_item_4", text = "-", fontSize = 9, width = "100%", height = 20, variant = "outline", onClick = function() self:_applyResource(4) end },
                    UI.Button { id = "res_item_5", text = "-", fontSize = 9, width = "100%", height = 20, variant = "outline", onClick = function() self:_applyResource(5) end },
                    UI.Button { id = "res_item_6", text = "-", fontSize = 9, width = "100%", height = 20, variant = "outline", onClick = function() self:_applyResource(6) end },
                },
            },
            -- 文件操作
            UI.Panel { height = 6 },
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
                        text = "保存配置",
                        fontSize = 11,
                        width = 80, height = 26,
                        variant = "primary",
                        onClick = function() self:saveToJSON() end,
                    },
                    UI.Button {
                        text = "加载配置",
                        fontSize = 11,
                        width = 80, height = 26,
                        variant = "outline",
                        onClick = function() self:loadFromJSON() end,
                    },
                },
            },
        },
    }

    -- 初始化资源列表显示
    self:_updateResourceList()
end

------------------------------------------------------------
-- 元素选择
------------------------------------------------------------
function EditorUI:_selectElement(elemId)
    self.selectedElement = elemId
    local elem = self.elements[elemId]
    if not elem then return end

    -- 更新属性面板
    local nameLabel = self.propsPanel:FindById("ui_selected_name")
    if nameLabel then nameLabel:SetText(elem.name .. " [" .. elem.align .. "]") end

    local sliderX = self.propsPanel:FindById("ui_pos_x")
    if sliderX then sliderX:SetValue(elem.x) end

    local sliderY = self.propsPanel:FindById("ui_pos_y")
    if sliderY then sliderY:SetValue(elem.y) end

    local sliderW = self.propsPanel:FindById("ui_size_w")
    if sliderW then sliderW:SetValue(elem.w) end

    local sliderH = self.propsPanel:FindById("ui_size_h")
    if sliderH then sliderH:SetValue(elem.h) end

    self:_refreshProps()

    -- 高亮选中按钮
    for _, def in ipairs(UI_ELEM_TYPES) do
        local btn = self.panel:FindById("uielem_" .. def.id)
        if btn then
            btn:SetVariant(def.id == elemId and "primary" or "outline")
        end
    end
    -- 自定义图片元素按钮
    for id, el in pairs(self.elements) do
        if id:find("^custom_img_") then
            local btn = self.panel:FindById("uielem_" .. id)
            if btn then
                btn:SetVariant(id == elemId and "primary" or "outline")
            end
        end
    end
end

function EditorUI:_refreshProps()
    if not self.selectedElement then return end
    local elem = self.elements[self.selectedElement]
    if not elem then return end

    local valX = self.propsPanel:FindById("ui_val_x")
    if valX then valX:SetText(tostring(elem.x)) end
    local valY = self.propsPanel:FindById("ui_val_y")
    if valY then valY:SetText(tostring(elem.y)) end
    local valW = self.propsPanel:FindById("ui_val_w")
    if valW then valW:SetText(tostring(elem.w)) end
    local valH = self.propsPanel:FindById("ui_val_h")
    if valH then valH:SetText(tostring(elem.h)) end

    -- 图片标签
    local imgLbl = self.propsPanel:FindById("lbl_current_image")
    if imgLbl then
        if elem.image then
            -- 只显示文件名
            local filename = elem.image:match("([^/]+)$") or elem.image
            imgLbl:SetText(filename)
        else
            imgLbl:SetText("无图片")
        end
    end
end

function EditorUI:_setAlign(align)
    if not self.selectedElement then return end
    self.elements[self.selectedElement].align = align
    local nameLabel = self.propsPanel:FindById("ui_selected_name")
    if nameLabel then
        nameLabel:SetText(self.elements[self.selectedElement].name .. " [" .. align .. "]")
    end
end

function EditorUI:_resetElement()
    if not self.selectedElement then return end
    for _, def in ipairs(UI_ELEM_TYPES) do
        if def.id == self.selectedElement then
            self.elements[def.id] = {
                id = def.id,
                name = def.name,
                x = def.defaultPos[1],
                y = def.defaultPos[2],
                w = def.defaultSize[1],
                h = def.defaultSize[2],
                align = def.align or "top_left",
                visible = true,
                image = def.image,
            }
            self:_selectElement(def.id)
            return
        end
    end
end

function EditorUI:_deleteElement()
    if not self.selectedElement then return end
    -- 只允许删除自定义图片元素
    if self.selectedElement:find("^custom_img_") then
        self.elements[self.selectedElement] = nil
        self.selectedElement = nil
        -- 重建左侧面板(简化：不动态添加，靠rebuild)
        self:_refreshProps()
    end
end

------------------------------------------------------------
-- 创建新UI图片元素
------------------------------------------------------------
local _customImgCounter = 0

function EditorUI:_createNewImageElement()
    _customImgCounter = _customImgCounter + 1
    local id = "custom_img_" .. _customImgCounter
    local elem = {
        id = id,
        name = "图片" .. _customImgCounter,
        x = 0,
        y = 0,
        w = 64,
        h = 64,
        align = "center",
        visible = true,
        image = nil,  -- 待用户选择资源
    }
    self.elements[id] = elem

    -- 动态添加按钮到左侧面板
    local btn = UI.Button {
        id = "uielem_" .. id,
        text = elem.name,
        fontSize = 11,
        width = "100%",
        height = 26,
        variant = "outline",
        onClick = function()
            self:_selectElement(id)
        end,
    }
    -- 插入到面板中（在分隔线之前）
    if self.panel then
        self.panel:AddChild(btn)
    end

    self:_selectElement(id)
    log:Write(LOG_INFO, "[EditorUI] Created new image element: " .. id)
end

------------------------------------------------------------
-- 资源替换
------------------------------------------------------------
function EditorUI:_setResourceCategory(catIdx)
    self.currentCategory = catIdx
    self:_updateResourceList()
end

function EditorUI:_updateResourceList()
    if not self.propsPanel then return end

    local cat = UI_RESOURCES[self.currentCategory]
    if not cat then return end

    local catLbl = self.propsPanel:FindById("lbl_res_category")
    if catLbl then catLbl:SetText(cat.category) end

    -- 更新6个资源按钮
    for i = 1, 6 do
        local btn = self.propsPanel:FindById("res_item_" .. i)
        if btn then
            local item = cat.items[i]
            if item then
                btn:SetText(item.name)
                btn:Show()
            else
                btn:SetText("-")
                btn:Hide()
            end
        end
    end
end

function EditorUI:_applyResource(index)
    if not self.selectedElement then return end
    local cat = UI_RESOURCES[self.currentCategory]
    if not cat then return end
    local item = cat.items[index]
    if not item then return end

    -- 设置选中元素的图片资源
    self.elements[self.selectedElement].image = item.path
    self:_refreshProps()
    log:Write(LOG_INFO, "[EditorUI] Applied resource '" .. item.name .. "' to " .. self.selectedElement)
end

------------------------------------------------------------
-- NanoVG 图片缓存
------------------------------------------------------------
function EditorUI:_getNvgImage(ctx, path)
    if not path then return nil end
    if self.imageCache[path] then
        return self.imageCache[path]
    end
    -- 尝试加载
    local handle = nvgCreateImage(ctx, path, 0)
    if handle and handle > 0 then
        self.imageCache[path] = handle
        return handle
    end
    return nil
end

------------------------------------------------------------
-- Update（处理平移、缩放、拖拽）
------------------------------------------------------------
function EditorUI:update(dt)
    if not self.visible then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    local mousePos = input:GetMousePosition()
    local logMX = mousePos.x / dpr
    local logMY = mousePos.y / dpr

    -- 排除面板区域
    local leftPanel = 200
    local rightPanel = 220
    local topBar = 44
    local inCanvas = logMX >= leftPanel and logMX <= (logW - rightPanel) and logMY >= topBar

    -- 滚轮缩放
    local wheel = input:GetMouseMoveWheel()
    if wheel ~= 0 and inCanvas then
        local oldZoom = self.zoomScale
        self.zoomScale = math.max(0.3, math.min(3.0, self.zoomScale + wheel * 0.1))
    end

    -- 右键平移
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        if not self.isPanning and inCanvas then
            self.isPanning = true
            self.panStartX = logMX
            self.panStartY = logMY
            self.panOriginX = self.panX
            self.panOriginY = self.panY
        elseif self.isPanning then
            self.panX = self.panOriginX + (logMX - self.panStartX)
            self.panY = self.panOriginY + (logMY - self.panStartY)
        end
    else
        self.isPanning = false
    end

    -- 左键拖拽选中元素
    if input:GetMouseButtonPress(MOUSEB_LEFT) and inCanvas then
        -- 检测是否点击了某个元素
        local clicked = self:_hitTest(logMX, logMY)
        if clicked then
            self:_selectElement(clicked)
            self.isDragging = true
            self.dragStartX = logMX
            self.dragStartY = logMY
            local elem = self.elements[clicked]
            self.elemStartX = elem.x
            self.elemStartY = elem.y
        else
            self.isDragging = false
        end
    end

    if self.isDragging and self.selectedElement and input:GetMouseButtonDown(MOUSEB_LEFT) then
        local elem = self.elements[self.selectedElement]
        if elem then
            local dx = (logMX - self.dragStartX) / self.zoomScale
            local dy = (logMY - self.dragStartY) / self.zoomScale
            elem.x = math.floor(self.elemStartX + dx)
            elem.y = math.floor(self.elemStartY + dy)
            self:_refreshProps()
            -- 更新滑块
            local sliderX = self.propsPanel:FindById("ui_pos_x")
            if sliderX then sliderX:SetValue(elem.x) end
            local sliderY = self.propsPanel:FindById("ui_pos_y")
            if sliderY then sliderY:SetValue(elem.y) end
        end
    end

    if not input:GetMouseButtonDown(MOUSEB_LEFT) then
        self.isDragging = false
    end
end

------------------------------------------------------------
-- 命中检测（画布坐标 → UI元素）
------------------------------------------------------------
function EditorUI:_hitTest(logMX, logMY)
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    local phoneW = 640
    local phoneH = 360
    local sidebarLeft = 200
    local sidebarRight = 220
    local topBar = 44
    local availW = logW - sidebarLeft - sidebarRight
    local availH = logH - topBar - 20
    local phoneScale = math.min(availW / phoneW, availH / phoneH) * 0.85 * self.zoomScale
    local pW = phoneW * phoneScale
    local pH = phoneH * phoneScale
    local pX = sidebarLeft + (availW - pW) * 0.5 + self.panX
    local pY = topBar + (availH - pH) * 0.5 + self.panY

    -- 检测每个元素（倒序，上面的优先）
    local allElems = {}
    for _, elem in pairs(self.elements) do
        if elem.visible then
            table.insert(allElems, elem)
        end
    end

    for i = #allElems, 1, -1 do
        local elem = allElems[i]
        local ax, ay = self:_calcAbsolutePos(elem, phoneW, phoneH)
        local drawX = pX + ax * phoneScale
        local drawY = pY + ay * phoneScale
        local drawW = elem.w * phoneScale
        local drawH = elem.h * phoneScale

        if logMX >= drawX and logMX <= drawX + drawW and logMY >= drawY and logMY <= drawY + drawH then
            return elem.id
        end
    end
    return nil
end

------------------------------------------------------------
-- NanoVG 绘制预览
------------------------------------------------------------
function EditorUI:renderPreview(ctx)
    if not self.visible then return end

    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    -- 横屏虚拟手机屏幕预览区域
    local phoneW = 640
    local phoneH = 360
    local sidebarLeft = 200
    local sidebarRight = 220
    local topBar = 44
    local availW = logW - sidebarLeft - sidebarRight
    local availH = logH - topBar - 20
    local phoneScale = math.min(availW / phoneW, availH / phoneH) * 0.85 * self.zoomScale
    local pW = phoneW * phoneScale
    local pH = phoneH * phoneScale
    local pX = sidebarLeft + (availW - pW) * 0.5 + self.panX
    local pY = topBar + (availH - pH) * 0.5 + self.panY

    -- 手机屏幕背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, pX, pY, pW, pH, 8)
    nvgFillColor(ctx, nvgRGBA(20, 25, 35, 230))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(100, 120, 180, 150))
    nvgStrokeWidth(ctx, 2.0)
    nvgStroke(ctx)

    -- 绘制各 UI 元素
    for _, elem in pairs(self.elements) do
        if elem and elem.visible then
            local ax, ay = self:_calcAbsolutePos(elem, phoneW, phoneH)
            local drawX = pX + ax * phoneScale
            local drawY = pY + ay * phoneScale
            local drawW = elem.w * phoneScale
            local drawH = elem.h * phoneScale

            local isSelected = (self.selectedElement == elem.id)

            -- 如果有图片资源，尝试绘制图片
            if elem.image then
                local imgHandle = self:_getNvgImage(ctx, elem.image)
                if imgHandle then
                    local imgPaint = nvgImagePattern(ctx, drawX, drawY, drawW, drawH, 0, imgHandle, 1.0)
                    nvgBeginPath(ctx)
                    nvgRoundedRect(ctx, drawX, drawY, drawW, drawH, 2)
                    nvgFillPaint(ctx, imgPaint)
                    nvgFill(ctx)
                else
                    -- 图片加载失败，显示占位符
                    nvgBeginPath(ctx)
                    nvgRoundedRect(ctx, drawX, drawY, drawW, drawH, 3)
                    nvgFillColor(ctx, nvgRGBA(80, 50, 50, 80))
                    nvgFill(ctx)
                end
            else
                -- 无图片，显示色块
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, drawX, drawY, drawW, drawH, 3)
                if isSelected then
                    nvgFillColor(ctx, nvgRGBA(80, 130, 255, 60))
                else
                    nvgFillColor(ctx, nvgRGBA(60, 100, 160, 40))
                end
                nvgFill(ctx)
            end

            -- 选中边框
            if isSelected then
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, drawX - 1, drawY - 1, drawW + 2, drawH + 2, 3)
                nvgStrokeColor(ctx, nvgRGBA(100, 255, 100, 240))
                nvgStrokeWidth(ctx, 2.5)
                nvgStroke(ctx)
            else
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, drawX, drawY, drawW, drawH, 3)
                nvgStrokeColor(ctx, nvgRGBA(80, 120, 180, 100))
                nvgStrokeWidth(ctx, 1.0)
                nvgStroke(ctx)
            end

            -- 元素名称标签
            nvgFontFace(ctx, "editor")
            local labelSize = math.max(9, 11 * phoneScale / (0.85 * self.zoomScale))
            nvgFontSize(ctx, labelSize)
            nvgFillColor(ctx, nvgRGBA(220, 240, 255, 220))
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(ctx, drawX + drawW * 0.5, drawY + drawH * 0.5, elem.name)
        end
    end

    -- 底部信息
    nvgFontFace(ctx, "editor")
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(150, 150, 180, 180))
    nvgText(ctx, pX, pY + pH + 6, string.format(
        "画布: %dx%d | 缩放: %.0f%% | 偏移: (%.0f, %.0f)",
        phoneW, phoneH, self.zoomScale * 100, self.panX, self.panY
    ))
end

------------------------------------------------------------
-- 坐标计算
------------------------------------------------------------
function EditorUI:_calcAbsolutePos(elem, screenW, screenH)
    local align = elem.align or "top_left"
    local x, y = elem.x, elem.y

    if align == "top_left" then
        return x, y
    elseif align == "top_center" then
        return (screenW - elem.w) * 0.5 + x, y
    elseif align == "top_right" then
        return screenW - elem.w + x, y
    elseif align == "bottom_left" then
        return x, screenH - elem.h + y
    elseif align == "bottom_center" then
        return (screenW - elem.w) * 0.5 + x, screenH - elem.h + y
    elseif align == "bottom_right" then
        return screenW - elem.w + x, screenH - elem.h + y
    elseif align == "center" then
        return (screenW - elem.w) * 0.5 + x, (screenH - elem.h) * 0.5 + y
    end
    return x, y
end

------------------------------------------------------------
-- 显示/隐藏
------------------------------------------------------------
function EditorUI:show()
    self.visible = true
    if self.panel then self.panel:Show() end
    if self.propsPanel then self.propsPanel:Show() end
end

function EditorUI:hide()
    self.visible = false
    if self.panel then self.panel:Hide() end
    if self.propsPanel then self.propsPanel:Hide() end
end

------------------------------------------------------------
-- 文件操作
------------------------------------------------------------
function EditorUI:saveToJSON()
    local data = { elements = self.elements }
    local jsonStr = cjson.encode(data)

    local file = File("editor_ui_config.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
        log:Write(LOG_INFO, "[EditorUI] Saved UI config")
    end
end

function EditorUI:loadFromJSON()
    if not fileSystem:FileExists("editor_ui_config.json") then
        log:Write(LOG_WARNING, "[EditorUI] No saved UI config found")
        return false
    end

    local file = File("editor_ui_config.json", FILE_READ)
    if not file:IsOpen() then return false end
    local jsonStr = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok or not data.elements then
        log:Write(LOG_ERROR, "[EditorUI] Failed to parse UI config JSON")
        return false
    end

    -- 合并
    for id, elem in pairs(data.elements) do
        self.elements[id] = elem
    end

    if self.selectedElement then
        self:_selectElement(self.selectedElement)
    end

    log:Write(LOG_INFO, "[EditorUI] Loaded UI config")
    return true
end

return EditorUI
