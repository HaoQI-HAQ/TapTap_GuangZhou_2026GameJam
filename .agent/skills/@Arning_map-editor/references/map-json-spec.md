# 等距地图 JSON 结构规范 (v4)

> 供其他项目解析本编辑器导出的地图数据

---

## 完整结构

```jsonc
{
  "version": 4,                    // 格式版本，固定为 4
  "width": 20,                     // 地图宽度（列数），范围 2~100
  "height": 20,                    // 地图高度（行数），范围 2~100
  "showGrid": true,                // 编辑器网格线显示状态（解析时可忽略）

  // --- 图片瓦片注册表（可选，使用图片瓦片时才有）---
  "imageFolder": "Tiles",          // 图片资源文件夹路径（可选）
  "imageRegistry": [               // 图片瓦片定义列表
    {
      "id": 100,                   // 瓦片 ID（图片瓦片从 100 起编号）
      "name": "tree",              // 显示名称
      "imagePath": "Tiles/tree.png", // 资源路径
      "tag": "obstacle"            // 自定义标签（可选）
    }
  ],

  // --- 颜色瓦片自定义属性（可选，修改过默认名称/标签时才有）---
  "tileCustomizations": [
    {
      "id": 1,                     // 颜色瓦片 ID（1~5）
      "name": "草原",              // 自定义名称（覆盖默认值）
      "tag": "walkable"            // 自定义标签（可选）
    }
  ],

  // --- 图层组（可选）---
  "groups": {                      // key 为组 ID（数字字符串）
    "1": {
      "name": "地形组",
      "collapsed": false           // 编辑器折叠状态（解析时可忽略）
    }
  },
  "nextGroupId": 2,                // 下一个组 ID 分配器（解析时可忽略）

  // --- 图层数据（核心）---
  "layers": [
    {
      "name": "地面",              // 图层名称
      "visible": true,             // 可见性
      "locked": false,             // 锁定状态
      "opacity": 1.0,              // 不透明度 0.0~1.0
      "groupId": 1,                // 所属组 ID（可选，null/缺失=未分组）
      "tiles": [                   // 非空瓦片列表（稀疏存储）
        { "x": 3, "y": 5, "id": 1 },                              // 颜色瓦片
        { "x": 7, "y": 2, "id": 100, "path": "Tiles/tree.png" }   // 图片瓦片
      ]
    }
  ]
}
```

---

## 关键解析规则

### 1. 坐标系

- **x**: 列坐标，1-based（1 ~ width）
- **y**: 行坐标，1-based（1 ~ height）
- 等距投影时，(1,1) 为地图左上角

### 2. 瓦片类型

| ID 范围 | 类型 | 说明 |
|---------|------|------|
| 0 | 空 | 无瓦片（不会出现在 tiles 数组中） |
| 1~5 | 颜色瓦片 | 内置预设颜色 |
| 100+ | 图片瓦片 | 由 imageRegistry 定义 |

### 3. 内置颜色瓦片默认值

| ID | 默认名称 | 默认颜色 (RGBA) |
|----|---------|----------------|
| 1 | 草地 | (76, 175, 80, 255) |
| 2 | 水面 | (33, 150, 243, 255) |
| 3 | 沙地 | (255, 193, 7, 255) |
| 4 | 石头 | (158, 158, 158, 255) |
| 5 | 泥土 | (121, 85, 72, 255) |

> 如果 `tileCustomizations` 中有对应 ID 的条目，用其 `name`/`tag` 覆盖默认值。

### 4. 图片瓦片解析

```
1. 读取 imageRegistry 数组
2. 建立 id → imagePath 的映射表
3. 遍历 layers[].tiles 时，遇到 id >= 100 的瓦片：
   - 优先使用 tile 自身的 path 字段
   - 若无 path，则从 imageRegistry 映射表查找
```

### 5. 稀疏存储

tiles 数组只包含**非空瓦片**（id > 0）。解析时应先创建 width x height 的全零网格，再逐个填入 tiles 中的数据。

### 6. 图层渲染顺序

layers 数组的索引顺序即渲染顺序：**索引小的先渲染（在底层），索引大的后渲染（在上层）**。

---

## 最简解析示例（伪代码）

```python
import json

with open("my_map.json") as f:
    data = json.load(f)

width = data["width"]
height = data["height"]

# 建立图片资源映射
image_map = {}
for reg in data.get("imageRegistry", []):
    image_map[reg["id"]] = reg["imagePath"]

# 逐层解析
for layer in data["layers"]:
    grid = [[0] * width for _ in range(height)]

    for tile in layer["tiles"]:
        x = tile["x"] - 1   # 转 0-based
        y = tile["y"] - 1   # 转 0-based
        grid[y][x] = tile["id"]

        # 如果是图片瓦片
        if tile["id"] >= 100:
            img_path = tile.get("path") or image_map.get(tile["id"])
            # 加载 img_path 对应的图片资源...

    print(f"Layer '{layer['name']}': {len(layer['tiles'])} tiles")
```

---

## 等距投影公式参考

将地图坐标 (mapX, mapY) 转换为屏幕像素坐标：

```
TILE_W = 64   -- 瓦片宽度（像素）
TILE_H = 32   -- 瓦片高度（像素）

screenX = (mapX - mapY) * (TILE_W / 2)
screenY = (mapX + mapY) * (TILE_H / 2)
```

> 实际使用时需要加上相机偏移和缩放。

---

## 版本兼容性

| 版本 | 特征 | 向后兼容 |
|------|------|---------|
| v4 (当前) | `layers` 数组 + `groups` + `imageRegistry` | -- |
| v3 | `groundTiles` + `objectTiles`（双层） | 编辑器可自动升级为 v4 |
| v1/v2 | `tiles`（单层） | 编辑器可自动升级为 v4 |

其他项目只需支持 v4 即可。
