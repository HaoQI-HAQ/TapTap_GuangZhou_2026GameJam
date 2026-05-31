---
name: "iso-map-editor"
description: |
  等距场景编辑器（Isometric Map Editor）集成工具。
  提供完整的菱形瓦片地图可视化编辑能力，可作为模块嵌入任何 UrhoX 项目。
  支持双视图模式（等距菱形 + 正视45°方格）、
  多图层、图层组、图片瓦片、颜色瓦片、6种编辑工具、撤销重做、
  复制粘贴、导入导出 JSON、地图尺寸调整等完整功能。
  通过浮窗按钮一键进入编辑器，退出后自动恢复宿主界面。
use-when:
  - 用户需要在项目中加入等距地图编辑器
  - 用户需要可视化编辑等距/菱形瓦片地图
  - 用户需要一个内嵌的关卡编辑器或场景编辑器
  - 用户提到"地图编辑器"、"瓦片编辑器"、"关卡编辑器"并且是等距/菱形视角
  - 用户想要在游戏运行时编辑地图数据
trigger-keywords:
  - 地图编辑器
  - 瓦片编辑器
  - 关卡编辑器
  - 等距编辑器
  - isometric editor
  - map editor
  - tile editor
  - level editor
  - 场景编辑器
---

# 等距场景编辑器 (Isometric Map Editor) — 集成 Skill

一个可嵌入任何 UrhoX 项目的完整等距瓦片地图编辑器。

## 功能清单

- 双视图模式：等距（菱形）视角 + 正视45°（方格）视角，一键切换
- 等距与正视两种网格渲染与交互
- 6 种工具：画笔(B)、橡皮擦(E)、填充(U)、洪水填充(G)、选区(M)、取色(I)
- 多图层系统：新建/删除/重命名/排序/可见性/锁定/透明度
- 图层组：分组管理、批量操作
- 颜色瓦片（5 种预定义）+ 图片瓦片（自动扫描文件夹）
- 瓦片名称和标签自定义
- 撤销/重做（无限步数）
- 选区复制/粘贴
- JSON 导入/导出
- 地图尺寸动态调整（2-100）
- 自动保存/加载临时存档

## 文件清单

集成需要复制以下 4 个 Lua 文件到目标项目的 `scripts/` 目录：

| 文件 | 行数 | 职责 |
|------|------|------|
| `IsoMapEditor.lua` | ~250 | 集成入口模块（Init/Enter/Exit/Update/HandleKeyDown） |
| `EditorUI.lua` | ~2010 | UI 布局（工具栏、调色板、图层面板、状态栏、弹窗） |
| `IsoCanvas.lua` | ~1020 | 等距画布渲染与交互（NanoVG 绘制、鼠标/键盘操作） |
| `MapData.lua` | ~1660 | 地图数据管理（图层、瓦片、存档、撤销重做、导入导出） |

此外需要：
- 瓦片图片资源放入 `assets/` 下某个文件夹（如 `assets/Tiles/`），PNG 格式
- UI 字体文件 `assets/Fonts/MiSans-Regular.ttf`（宿主项目通常已有）

## 集成步骤

### 步骤 1：复制文件

从 `references/` 目录复制 4 个 Lua 文件到目标项目的 `scripts/`：

```
scripts/
  IsoMapEditor.lua
  EditorUI.lua
  IsoCanvas.lua
  MapData.lua
```

### 步骤 2：准备瓦片资源

将等距瓦片 PNG 图片放入 `assets/Tiles/`（或其他文件夹名），编辑器会自动扫描。

### 步骤 3：宿主项目代码集成

在宿主项目的 `main.lua` 中添加：

```lua
local UI = require("urhox-libs/UI")
local IsoMapEditor = require("IsoMapEditor")

function Start()
    -- 宿主项目的 UI.Init()（必须在编辑器初始化之前）
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化编辑器
    IsoMapEditor.Init({
        tileFolder = "Tiles",     -- 瓦片图片文件夹
        buttonSize = 56,          -- 浮窗按钮尺寸
        buttonRight = 16,         -- 按钮距右边距
        buttonBottom = 80,        -- 按钮距底边距
        buttonLabel = "Map",      -- 按钮文本
        autoSave = true,          -- 退出时自动保存
    })

    -- 构建宿主界面，把浮窗按钮加入 UI 树
    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- ... 宿主项目 UI ...
            IsoMapEditor.CreateFloatingButton(),  -- 浮窗入口
        },
    }
    UI.SetRoot(root)

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    IsoMapEditor.Update(dt)
    if IsoMapEditor.IsActive() then return end
    -- ... 宿主项目 Update ...
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if IsoMapEditor.HandleKeyDown(key) then return end
    -- ... 宿主项目 KeyDown ...
end

function Stop()
    UI.Shutdown()
end
```

## API 参考

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `Init(opts)` | — | 初始化编辑器，传入配置表 |
| `CreateFloatingButton()` | widget | 创建浮窗入口按钮（须加入 UI 树） |
| `GetFloatingButton()` | widget/nil | 获取已创建的浮窗按钮 |
| `Enter()` | — | 进入编辑器（替换当前 UI） |
| `Exit()` | — | 退出编辑器（恢复宿主 UI） |
| `IsActive()` | boolean | 编辑器是否激活 |
| `Update(dt)` | — | 每帧调用（非激活时自动跳过） |
| `HandleKeyDown(key)` | boolean | 键盘事件，返回 true 已消费 |
| `Save()` | — | 手动保存 |
| `Load()` | — | 手动加载 |
| `ExportJSON()` | string/nil | 导出地图 JSON |
| `SetTileFolder(folder)` | number | 切换瓦片文件夹，返回加载数量 |
| `GetConfig()` | table | 获取当前配置 |
| `SetViewMode(mode)` | — | 设置视图模式（"iso" 或 "topdown"） |
| `GetViewMode()` | string | 获取当前视图模式 |
| `ToggleViewMode()` | string | 切换视图模式，返回新模式 |

## Init 配置项

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tileFolder` | string | `"Tiles"` | 瓦片图片文件夹（相对 assets/） |
| `buttonSize` | number | `56` | 浮窗按钮尺寸 |
| `buttonRight` | number | `16` | 按钮距右边距 |
| `buttonBottom` | number | `80` | 按钮距底边距 |
| `buttonLabel` | string | `"Map"` | 按钮文本 |
| `autoSave` | boolean | `true` | 退出时自动保存 |

## 快捷键

| 键 | 功能 |
|----|------|
| B / E / U / G / I / M | 画笔 / 橡皮擦 / 填充 / 洪水填充 / 取色 / 选区 |
| H | 切换网格 |
| Ctrl+Z / Ctrl+Y | 撤销 / 重做 |
| Ctrl+S / Ctrl+L | 保存 / 加载 |
| Ctrl+C / Ctrl+V | 复制选区 / 粘贴 |
| Esc | 取消粘贴或选区 |
| WASD | 平移画布 |
| 右键拖拽 | 平移画布 |
| 滚轮 | 缩放画布 |

## 数据格式

地图数据使用 JSON v4 格式，详见 `references/map-json-spec.md`。

瓦片 ID 约定：`0`=空，`1-5`=颜色瓦片，`100+`=图片瓦片。

## 注意事项

- WASM 平台无法直接使用系统剪贴板，导出 JSON 需通过浏览器 F12 控制台复制
- 临时存档在 WASM 刷新页面后丢失，重要数据请导出 JSON 备份
- `EditorUI.lua` 约 1890 行，如需定制 UI 请谨慎修改
- 编辑器使用 NanoVG 绘制画布，与宿主项目的 NanoVG 调用互不冲突（编辑器激活时宿主逻辑被跳过）
