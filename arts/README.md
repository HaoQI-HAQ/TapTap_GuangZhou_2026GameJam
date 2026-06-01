# 暗黑地牢像素美术素材

> 风格: 死亡细胞 (Dead Cells) 同款像素风格
> 用途: 横版动作游戏 - 5关卡地牢场景

---

## 目录结构

```
arts/
├── backgrounds/          # 场景背景
│   └── dungeon_rooms/    # 地牢关卡背景 (480x270, 16:9)
│       ├── room1_entrance.png
│       ├── room2_prison.png
│       ├── room3_sewer.png
│       ├── room4_altar.png
│       └── room5_boss_throne.png
│
└── tiles/                # 地块 Tile (32x32, 可平铺)
    ├── floor/            # 地面类
    │   ├── stone_floor.png
    │   ├── cracked_floor.png
    │   └── gold_floor.png
    ├── wall/             # 墙壁/天花板类
    │   ├── stone_wall.png
    │   ├── dark_brick.png
    │   └── ceiling.png
    └── special/          # 特殊功能地块
        └── platform_edge.png
```

---

## 场景背景使用说明

| 文件 | 关卡 | 描述 | 使用场景 |
|------|------|------|---------|
| `room1_entrance.png` | 第1关 | 幽暗地牢入口 | 游戏开始，阴冷石质走廊，火把微光，地面积水 |
| `room2_prison.png` | 第2关 | 地下监牢 | 铁笼锁链，骨头散落，暗红血迹，绿色荧光 |
| `room3_sewer.png` | 第3关 | 腐蚀下水道 | 毒水流淌，生锈管道，蘑菇藤蔓，有毒气体 |
| `room4_altar.png` | 第4关 | 黑暗祭坛 | 紫色魔法阵发光，蜡烛环绕，墙壁符文 |
| `room5_boss_throne.png` | 第5关 (Boss) | Boss王座厅 | 开阔大厅，骷髅王座，王座后金山银山，金币珠宝遍地 |

### 背景加载示例 (UrhoX Lua)

```lua
-- 作为 2D 精灵背景
local bgNode = scene_:CreateChild("Background")
local bgSprite = bgNode:CreateComponent("StaticSprite2D")
local bgTexture = cache:GetResource("Texture2D", "image/bg_dungeon_room1_20260531022412.png")
local sprite2d = Sprite2D:new()
sprite2d:SetTexture(bgTexture)
sprite2d:SetRectangle(IntRect(0, 0, bgTexture:GetWidth(), bgTexture:GetHeight()))
bgSprite:SetSprite(sprite2d)
bgNode:SetPosition2D(Vector2(0, 0))

-- 根据关卡切换背景
local backgrounds = {
    "image/bg_dungeon_room1_20260531022412.png",  -- 关卡1
    "image/bg_dungeon_room2_20260531022410.png",  -- 关卡2
    "image/bg_dungeon_room3_20260531022408.png",  -- 关卡3
    "image/bg_dungeon_room4_20260531022411.png",  -- 关卡4
    "image/bg_dungeon_room5_boss_20260531022408.png",  -- Boss关
}
```

### 背景加载示例 (NanoVG)

```lua
-- 在 NanoVGRender 事件中绘制背景
local bgImage = nvgCreateImage(vg, "image/bg_dungeon_room1_20260531022412.png", 0)

function HandleNanoVGRender(eventType, eventData)
    nvgBeginFrame(vg, width, height, 1.0)
    local paint = nvgImagePattern(vg, 0, 0, width, height, 0, bgImage, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
    nvgEndFrame(vg)
end
```

---

## 地块 Tile 使用说明

所有 Tile 尺寸为 **32x32 像素**，设计为可无缝平铺。

### 地面类 (tiles/floor/)

| 文件 | 用途 | 适用关卡 |
|------|------|---------|
| `stone_floor.png` | 通用地牢地板，深灰石砖 | 全部关卡通用 |
| `cracked_floor.png` | 破损地板，表示危险/老旧区域 | 第2-4关，陷阱附近 |
| `gold_floor.png` | 金币散落的地面 | 第5关 Boss房间专用 |

### 墙壁类 (tiles/wall/)

| 文件 | 用途 | 适用关卡 |
|------|------|---------|
| `stone_wall.png` | 通用石墙，带青苔裂缝 | 第1、3关 |
| `dark_brick.png` | 暗红砖墙，血迹斑驳 | 第2、4关 |
| `ceiling.png` | 天花板/洞顶，潮湿滴水 | 全部关卡顶部 |

### 特殊地块 (tiles/special/)

| 文件 | 用途 | 说明 |
|------|------|------|
| `platform_edge.png` | 可跳跃平台边缘 | 玩家可站立的悬浮平台 |

### Tile 平铺示例 (UrhoX Lua - TileMap 方式)

```lua
-- 使用 Tile 构建关卡地形
local TILE_SIZE = 32  -- 像素

-- 地图数据 (1=石地板, 2=裂缝地板, 3=石墙, 4=暗砖墙, 5=金币地板)
local mapData = {
    {3, 3, 3, 3, 3, 3, 3, 3, 3, 3},  -- 顶部墙壁
    {3, 0, 0, 0, 0, 0, 0, 0, 0, 3},  -- 空气
    {3, 0, 0, 0, 0, 0, 0, 0, 0, 3},  -- 空气
    {3, 1, 1, 2, 1, 1, 2, 1, 1, 3},  -- 地板层
}

-- 对应的贴图路径
local tileTextures = {
    [1] = "image/tile_stone_floor_20260531022502.png",
    [2] = "image/tile_cracked_floor_20260531022500.png",
    [3] = "image/tile_stone_wall_20260531022500.png",
    [4] = "image/tile_dark_brick_20260531022506.png",
    [5] = "image/tile_gold_floor_20260531022500.png",
}
```

### 关卡 Tile 搭配建议

| 关卡 | 地面 | 墙壁 | 天花板 | 特殊 |
|------|------|------|--------|------|
| 第1关 入口 | stone_floor | stone_wall | ceiling | platform_edge |
| 第2关 监牢 | stone_floor + cracked_floor | dark_brick | ceiling | platform_edge |
| 第3关 下水道 | cracked_floor | stone_wall | ceiling | platform_edge |
| 第4关 祭坛 | stone_floor | dark_brick | ceiling | platform_edge |
| 第5关 Boss | gold_floor | dark_brick | ceiling | - |

---

## 技术规格

| 属性 | 背景 | Tile |
|------|------|------|
| 尺寸 | 480x270 px | 32x32 px |
| 宽高比 | 16:9 | 1:1 |
| 透明背景 | 否 | 否 |
| 色彩风格 | 死亡细胞暗色调 | 死亡细胞暗色调 |
| 可平铺 | 否（单张场景图） | 是（无缝拼接） |
