# 等距场景编辑器 (Isometric Map Editor)

## 目录

1. [项目概述](#1-项目概述)
2. [文件结构](#2-文件结构)
3. [集成指南](#3-集成指南)
4. [编辑器使用手册](#4-编辑器使用手册)
5. [数据格式](#5-数据格式)
6. [常见问题](#6-常见问题)

---

## 1. 项目概述

等距场景编辑器是一个基于 UrhoX 引擎的可视化地图编辑工具，用于创建和编辑菱形（等距/Isometric）瓦片地图。

核心功能：
- 等距视角的瓦片绘制与编辑
- 多图层系统（支持图层组、可见性、锁定、透明度）
- 颜色瓦片 + 图片瓦片双模式
- 6 种编辑工具（画笔、橡皮擦、填充、洪水填充、选区、取色）
- 撤销/重做（无限步数）
- 复制/粘贴选区
- 导出/导入 JSON 数据
- 地图尺寸动态调整
- 瓦片名称与标签自定义

---

## 2. 文件结构

```
scripts/
  IsoMapEditor.lua    -- 集成入口模块（其他项目通过此文件接入）
  EditorUI.lua        -- 编辑器 UI 布局（工具栏、调色板、图层面板、状态栏）
  IsoCanvas.lua       -- 等距画布渲染与交互（NanoVG 绘制、鼠标操作）
  MapData.lua         -- 地图数据管理（图层、瓦片、存档、导入导出）
  main.lua            -- 独立运行入口（含主界面，用于独立编辑模式）
  maps/
    default_map.lua   -- 默认空白地图模板
  docs/
    map-json-spec.md  -- JSON 数据格式规范
    editor-guide.md   -- 本文档

assets/
  Tiles/              -- 瓦片图片资源（PNG 格式，等距菱形）
    anvil.png
    barrels.png
    floor_stone.png
    wall_wood.png
    ...共 16 张
  Fonts/
    MiSans-Regular.ttf -- UI 字体
```

模块依赖关系：

```
IsoMapEditor (集成入口)
  ├── EditorUI (UI 布局)
  │   ├── IsoCanvas (画布渲染)
  │   │   └── MapData (数据层)
  │   └── MapData (数据层)
  └── MapData (数据层)
```

---

## 3. 集成指南

### 3.1 前置条件

- 宿主项目已正常运行
- 宿主项目的 `Start()` 中已调用 `UI.Init()`
- 瓦片图片资源已放入 `assets/` 目录下某个文件夹（如 `assets/Tiles/`）

### 3.2 复制文件

将以下文件复制到宿主项目的 `scripts/` 目录：

```
IsoMapEditor.lua    -- 必须
EditorUI.lua        -- 必须
IsoCanvas.lua       -- 必须
MapData.lua         -- 必须
maps/               -- 可选（默认地图模板）
```

将瓦片图片复制到宿主项目的 `assets/` 目录下（如 `assets/Tiles/`）。

### 3.3 最小集成代码

在宿主项目的 `main.lua` 中：

```lua
local UI = require("urhox-libs/UI")
local IsoMapEditor = require("IsoMapEditor")

function Start()
    -- 1. 初始化 UI（宿主项目自行配置）
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 2. 初始化编辑器
    IsoMapEditor.Init({
        tileFolder = "Tiles",    -- 瓦片图片文件夹路径
    })

    -- 3. 构建宿主项目界面（把浮窗按钮加进去）
    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- ... 宿主项目的 UI ...
            UI.Label { text = "我的游戏", fontSize = 24 },

            -- 编辑器浮窗入口按钮
            IsoMapEditor.CreateFloatingButton(),
        },
    }
    UI.SetRoot(root)

    -- 4. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 编辑器更新（激活时处理画布交互）
    IsoMapEditor.Update(dt)

    -- 编辑器激活时跳过宿主逻辑
    if IsoMapEditor.IsActive() then return end

    -- ... 宿主项目的 Update 逻辑 ...
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- 编辑器键盘处理（激活时拦截按键）
    if IsoMapEditor.HandleKeyDown(key) then return end

    -- ... 宿主项目的 KeyDown 逻辑 ...
end

function Stop()
    UI.Shutdown()
end
```

### 3.4 IsoMapEditor API 参考

| 方法 | 说明 |
|------|------|
| `Init(opts)` | 初始化编辑器。`opts.tileFolder` 指定瓦片图片文件夹 |
| `CreateFloatingButton()` | 创建浮窗入口按钮，返回 widget（须加入 UI 树） |
| `GetFloatingButton()` | 获取已创建的浮窗按钮 widget |
| `Enter()` | 进入编辑器界面（替换当前 UI） |
| `Exit()` | 退出编辑器，恢复宿主界面 |
| `IsActive()` | 返回编辑器是否处于活跃状态 |
| `Update(dt)` | 每帧更新，在 HandleUpdate 中调用 |
| `HandleKeyDown(key)` | 键盘事件处理，返回 true 表示已消费 |
| `Save()` | 手动保存地图到临时存档 |
| `Load()` | 手动加载临时存档 |
| `ExportJSON()` | 导出地图数据为 JSON 字符串 |
| `SetTileFolder(folder)` | 切换瓦片资源文件夹并重新扫描 |
| `GetConfig()` | 获取当前配置表 |

### 3.5 Init 配置项

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tileFolder` | string | `"Tiles"` | 瓦片图片文件夹路径（相对 assets/） |
| `buttonSize` | number | `56` | 浮窗按钮尺寸（像素） |
| `buttonRight` | number | `16` | 浮窗按钮距右边距 |
| `buttonBottom` | number | `80` | 浮窗按钮距底边距 |
| `buttonLabel` | string | `"Map"` | 浮窗按钮文本 |
| `autoSave` | boolean | `true` | 退出编辑器时自动保存 |

---

## 4. 编辑器使用手册

### 4.1 界面布局

```
+-------------------------------------------------------+
|  工具栏: [画笔][橡皮擦][填充][洪水][选区][取色]  [导出][导入]  |
+-------------------------------------------+-----------+
|                                           | 瓦片调色板 |
|                                           | [颜色瓦片] |
|            等距画布                        | [图片瓦片] |
|         （绘制和编辑区域）                   +-----------+
|                                           | 图层面板   |
|                                           | [层1][层2] |
|                                           | [+][-]     |
+-------------------------------------------+-----------+
|  状态栏: 坐标(x,y) | 工具 | 图层 | 地图尺寸             |
+-------------------------------------------------------+
```

### 4.2 编辑工具

| 工具 | 快捷键 | 说明 |
|------|--------|------|
| 画笔 (Brush) | `B` | 左键点击/拖拽绘制瓦片 |
| 橡皮擦 (Eraser) | `E` | 左键清除瓦片（设为空） |
| 填充 (Box Fill) | `U` | 左键拖拽一个矩形区域，松开后填充 |
| 洪水填充 (Flood) | `G` | 左键点击，填充相同瓦片的连通区域 |
| 选区 (Select) | `M` | 左键拖拽选择矩形区域，配合复制粘贴 |
| 取色 (Picker) | `I` | 左键点击拾取画布上的瓦片，自动切换到画笔 |

### 4.3 画布操作

| 操作 | 方式 |
|------|------|
| 平移画布 | 右键拖拽 / WASD 键盘 |
| 缩放画布 | 鼠标滚轮 |
| 绘制瓦片 | 左键点击或拖拽（画笔/橡皮擦模式） |
| 框选填充 | 左键拖拽矩形（填充模式） |
| 框选区域 | 左键拖拽矩形（选区模式） |

### 4.4 快捷键一览

| 快捷键 | 功能 |
|--------|------|
| `B` | 切换画笔工具 |
| `E` | 切换橡皮擦 |
| `U` | 切换填充工具 |
| `G` | 切换洪水填充 |
| `I` | 切换取色工具 |
| `M` | 切换选区工具 |
| `H` | 切换网格显示/隐藏 |
| `Ctrl+Z` | 撤销 |
| `Ctrl+Y` | 重做 |
| `Ctrl+S` | 保存地图 |
| `Ctrl+L` | 加载地图 |
| `Ctrl+C` | 复制选区 |
| `Ctrl+V` | 粘贴（进入粘贴模式，点击放置） |
| `Esc` | 取消粘贴模式 / 取消选区 |

### 4.5 瓦片调色板

编辑器右侧面板分为三个区域：

**颜色瓦片**（上方）：
- 5 种预定义颜色瓦片（草地、水面、沙地、石头、泥土）
- 点击选择，自动切换到画笔模式
- 可在下方属性面板修改名称和标签

**图片瓦片**（中部）：
- 自动从配置的 `tileFolder` 扫描加载 PNG 图片
- 以缩略图网格展示，点击选择
- 支持自定义名称和标签
- 可通过"扫描文件夹"功能手动切换/刷新文件夹

**瓦片属性**（下方）：
- 显示当前选中瓦片的名称和标签
- 名称和标签可编辑，支持自定义

### 4.6 图层系统

**基本操作**：
- 点击图层名称切换为当前活跃图层
- 双击（或长按）图层名称可重命名
- 眼睛按钮切换图层可见性
- 锁定按钮锁定/解锁图层（锁定后无法绘制）
- 透明度滑块调整图层透明度
- 上下箭头调整图层顺序
- `+` 按钮新建图层
- `-` 按钮删除图层

**图层组**：
- 可创建图层组对图层进行分组管理
- 点击组名折叠/展开组
- 双击（或长按）组名可重命名
- 新建图层时可选择归属的图层组
- 组可以批量切换可见性和锁定状态

**预览模式**：
- 点击"预览"按钮进入预览模式
- 预览模式下合并显示所有可见图层，不可编辑
- 再次点击退出预览模式

### 4.7 地图管理

**调整地图尺寸**：
- 工具栏中可修改地图宽高（范围 2-100）
- 扩大地图时原有数据保留，新增区域为空
- 缩小地图时超出范围的数据会被裁剪

**保存/加载**：
- `Ctrl+S` 打开保存对话框，输入文件名保存
- `Ctrl+L` 打开加载对话框，选择已保存的地图加载
- 编辑器退出时自动保存到临时存档
- 重新进入编辑器时自动恢复临时存档

### 4.8 导出/导入

**导出**：
1. 点击工具栏"导出"按钮
2. JSON 数据自动输出到浏览器控制台
3. 按 F12 打开开发者工具 → Console 标签页
4. 找到 `===== MAP JSON START =====` 和 `===== MAP JSON END =====` 之间的内容
5. 选中 JSON 文本，Ctrl+C 复制

**导入**：
1. 点击工具栏"导入"按钮
2. 在输入框中粘贴 JSON 内容（Ctrl+V）
3. 点击"导入"按钮加载数据

> 注意：由于 WASM 平台限制，编辑器内的复制/粘贴使用引擎内部剪贴板，
> 无法直接与系统剪贴板交互。导出数据需通过浏览器控制台中转。

---

## 5. 数据格式

地图数据使用 JSON v4 格式，详细规范参见 [map-json-spec.md](map-json-spec.md)。

核心结构概要：

```jsonc
{
  "version": 4,
  "width": 20,
  "height": 20,
  "imageFolder": "Tiles",
  "imageRegistry": [
    { "id": 100, "name": "tree", "imagePath": "Tiles/tree.png", "tag": "obstacle" }
  ],
  "tileCustomizations": [
    { "id": 1, "name": "草原", "tag": "walkable" }
  ],
  "groups": {
    "1": { "name": "地形组", "collapsed": false }
  },
  "layers": [
    {
      "name": "地面",
      "visible": true,
      "locked": false,
      "opacity": 1.0,
      "groupId": 1,
      "tiles": [ [0,0,1,1,2], [0,1,1,0,0] ]
    }
  ]
}
```

**瓦片 ID 约定**：
- `0` = 空（无瓦片）
- `1-5` = 颜色瓦片（草地、水面、沙地、石头、泥土）
- `100+` = 图片瓦片（按加载顺序编号）

---

## 6. 常见问题

**Q: 导出的 JSON 无法复制到系统剪贴板？**
A: 这是 WASM 平台限制。请按 F12 打开浏览器开发者工具，在 Console 中找到输出的 JSON 文本复制。

**Q: 导入时粘贴了 JSON 但提示"请先粘贴 JSON 内容"？**
A: 请确保粘贴后光标仍在输入框内，然后点击"导入"按钮。

**Q: 新建的图层无法重命名？**
A: 双击图层名称可重命名。如果双击不灵敏，也可以长按图层名称触发重命名。

**Q: 图片瓦片没有显示？**
A: 检查 `tileFolder` 配置路径是否正确，确保图片文件为 PNG 格式且放在 `assets/` 对应子目录下。

**Q: 如何在宿主项目中读取编辑器数据？**
A: 调用 `IsoMapEditor.ExportJSON()` 获取 JSON 字符串，用 `cjson.decode()` 解析后即可按需使用图层和瓦片数据。

**Q: 编辑器退出后数据会丢失吗？**
A: 默认开启自动保存（`autoSave = true`），退出编辑器时数据保存到临时存档，重新进入自动恢复。注意 WASM 环境刷新页面后临时存档会丢失，需通过导出 JSON 手动备份。
