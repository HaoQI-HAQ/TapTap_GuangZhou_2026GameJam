---
name: dwp-loading-optimization
description: "边玩边下体验优化指南。边玩边下（DWP）的核心意义在于大幅缩短玩家首次下载游戏的等待时间，同时在整个游戏过程中让玩家完全意识不到资源加载的存在，获得完整流畅的体验。本 skill 帮助分析项目资源加载需求，设计加载策略，通过占位、前置加载、预下载三层方案实现丝滑无感的游戏体验。Use when users need to (1) 优化 DWP 加载体验, (2) 处理资源加载时的画面跳变/缺失, (3) 设计加载策略或加载顺序, (4) 添加 loading 界面/加载遮罩, (5) 实现后台预下载/预加载, (6) 资源未加载导致灰块/无声/T-pose, (7) 骨架屏/占位图/placeholder, (8) 边下边玩体验优化, (9) download while playing optimization, (10) 新项目启用 DWP 后的体验适配。\nSKIP when: 项目未启用 DWP（全量预加载）、仅询问 DWP API 用法（指向官方文档即可）。\nMUST trigger when: 用户提到资源加载体验问题（灰块、无声、跳变、T-pose），或需要设计加载策略/预下载方案。"
---

# 边玩边下体验优化

> **边玩边下（DWP）的核心意义**在于大幅缩短玩家首次下载游戏的等待时间，同时在整个游戏过程中让玩家完全意识不到资源加载的存在，获得完整流畅的体验。最理想的状态是：玩家玩起来感觉一切都是完整的，完全不会察觉到任何加载过程——这就是我们整体设计的目标。
>
> 本 skill 不重复官方 DWP API 文档（`engine-docs/recipes/download-while-playing.md`），而是聚焦于**官方行为之外、需要游戏侧主动补充的体验优化**——通过占位、前置加载、后台预下载三层方案，让加载对玩家完全透明。

---

## 第一步：分析项目需求

不同游戏对加载体验的要求差异很大。在写任何代码前，先分析项目：

### 1.1 扫描项目资源

```
检查项目中的 DWP 媒体资源：
├─ 纹理/图片（.png .jpg）→ UI 图标、立绘、背景？数量多少？
├─ 模型（.mdl）→ 角色、道具、场景模型？
├─ 动画（.ani）→ 角色动画？
├─ 音效（.ogg .wav）→ 战斗音效、UI 音效？
├─ 音乐（.ogg .mp3）→ BGM？
└─ 字体（.ttf）→ 自定义字体？
```

### 1.2 评估影响程度

对每类资源，问：**如果这个资源在玩家用到时还没下载完，体验会怎样？**

| 资源类型 | 引擎默认占位行为 | 玩家感受 | 严重程度 |
|---------|-----------------|---------|---------|
| 纹理/图片 | 灰色方块 → 下载后跳变 | "游戏在卡" | 中（可用骨架屏缓解） |
| 模型 | 不渲染 → 突然出现 | "凭空冒出来" | 高（无法占位） |
| 音效 | 静默，错过触发时机 | 操作无反馈 | 高（无法补救） |
| 音乐 | 静默 → 突然响起 | 气氛断裂 | 中高 |
| 字体 | 回退字体 → 跳变 | 文字样式突变 | 中 |
| 动画 | T-pose → 切换 | 角色先僵直 | 高（无法占位） |

### 1.3 询问用户或自行判断

根据项目类型确定策略深度：

| 项目规模 | 建议方案 |
|---------|---------|
| 资源少、UI 简单 | 仅前置加载关键资源即可 |
| 多个 UI 界面、中等资源量 | 前置加载 + 加载遮罩 |
| 大量资源、首屏体验要求高 | 三层全上（占位 + 前置加载 + 后台预下载） |

**如果不确定，询问用户**：
- "你的游戏中哪些界面/场景的资源最多？"
- "玩家最先进入的界面是什么？"
- "对加载等待的容忍度如何？（宁可等 loading 也不要看到跳变？还是尽快进入？）"

---

## 第二步：选择加载策略

按资源特点选择对应策略：

```
资源分类决策树：
    ↓
这个资源缺失时玩家能否接受？
    ├─ 完全不能接受（音效、模型、动画、关键字体）
    │   └─ → 必须前置加载：在用到前通过 loading 确保就绪
    ├─ 短暂可接受但需要优雅过渡（UI 图片、立绘）
    │   └─ → 骨架屏占位 + 前置加载
    └─ 可以接受延迟（次要装饰、环境音）
        └─ → 引擎默认行为即可，可选后台预下载
```

### 策略速查表

| 策略 | 适用资源 | 实现方式 | 复杂度 |
|------|---------|---------|--------|
| **引擎默认** | 次要装饰图、环境音 | 无需额外代码 | 零 |
| **骨架屏占位** | NanoVG 渲染的图片 | 替换 nvgCreateImage 调用 | 低 |
| **入口前置加载** | 界面/场景的关键资源 | 进入前 PreloadGate | 中 |
| **后台预下载** | 按玩家流程预判 | 空闲时串行下载 | 中高 |

---

## 第三步：实现

### 层一：骨架屏占位（仅 NanoVG 图片）

> 其他资源类型（音效、模型等）不存在骨架屏概念，直接走层二前置加载。

**核心模式**：封装 `GetImage()` 替代 `nvgCreateImage()`

```lua
-- 封装安全的图片加载
function GetImage(nvg, path, imageCache, cacheKey)
    local cached = imageCache[cacheKey]
    if cached and cached > 0 then return cached end    -- 缓存命中
    if cached == -2 then return -2 end                 -- 下载中

    if cache:Exists(path) then
        local img = nvgCreateImage(nvg, path, 0)
        imageCache[cacheKey] = img
        return img
    else
        imageCache[cacheKey] = -2                      -- 标记下载中
        cache:GetResourceAsync("Image", path, function(res)
            imageCache[cacheKey] = nil                 -- 清标记，下帧重走 Exists 分支
        end)
        return -2
    end
end

-- 调用方
local img = GetImage(nvg, path, imageCache, key)
if img > 0 then
    -- 正常渲染
elseif img == -2 then
    -- 渲染骨架屏占位（统一的脉冲呼吸 + 扫光效果）
    RenderPlaceholder(nvg, x, y, w, h, animTime, cornerRadius)
end
```

**关键设计决策**：
- 异步回调里**不要**直接调 `nvgCreateImage`（不在渲染帧内，有线程安全风险）
- 回调只清标记，让下帧渲染循环自然处理
- `nvgCreateImage` 句柄必须缓存，不可每帧调用（显存泄漏）

**骨架屏效果建议**：
- 深色底板 + 脉冲呼吸（alpha 缓慢波动）+ 从左到右扫光
- 不用文字或加载圆弧——骨架屏暗示"这里有内容"，不是强调"在加载"
- 动画轻柔，不抢注意力
- 支持圆角，适配各种 UI 形状

### 层二：界面/场景入口前置加载

> **最重要的一层**。对所有资源类型通用。

**核心模式**：进入界面前收集路径 → 检查 → 未就绪则显示加载遮罩

```lua
function SomeUI.Show(callback)
    -- 1. 收集该界面需要的所有资源路径
    local paths = {}
    -- 图片
    for _, item in ipairs(items) do table.insert(paths, item.iconPath) end
    -- 音效
    table.insert(paths, "Sounds/confirm.ogg")
    -- 模型、字体等也加入...

    -- 2. 前置加载
    PreloadGate(paths, function()
        -- 3. 全部就绪，安全进入
        SomeUI.visible = true
        if callback then callback() end
    end, "正在加载...")
end
```

**PreloadGate 实现逻辑**：

```lua
function PreloadGate(paths, onReady, statusText)
    local missing = {}
    for _, p in ipairs(paths) do
        if not cache:Exists(p) then table.insert(missing, p) end
    end

    if #missing == 0 then
        onReady()  -- 快速路径：全部已缓存，零延迟
        return
    end

    -- 显示加载遮罩
    LoadingOverlay.Show(statusText, onReady, "manual")

    local completed = 0
    for _, p in ipairs(missing) do
        cache:GetResourceAsync(guessType(p), p, function(res)
            completed = completed + 1
            LoadingOverlay.SetProgress(completed, #missing)
            if completed >= #missing then
                LoadingOverlay.Hide()
            end
        end)
    end
end
```

**哪些资源该放进前置加载**（判断原则：缺失时玩家会否明显感知）：

| 资源 | 缺失表现 | 是否前置加载 |
|------|---------|---------|
| UI 图标/立绘 | 灰块或骨架屏 | 是 |
| 战斗 BGM | 进入后数秒无声 | 是 |
| 关键音效 | 操作无反馈 | 是 |
| 敌人/角色模型 | 隐形或 T-pose | 是 |
| 角色动画 | 僵直 | 是 |
| 自定义字体 | 样式跳变 | 是 |
| 次要装饰图 | 细节缺失 | 可选 |
| 环境音 | 短暂缺失不明显 | 可选 |

**对于非图片资源（音效、模型等），前置加载是唯一防线——没有骨架屏兜底。路径列表必须完整！**

#### 加载遮罩体验技巧

| 技巧 | 做法 | 原因 |
|------|------|------|
| **最短显示时间** | 强制至少显示 0.3 秒 | 避免瞬闪比不显示更刺眼 |
| **手动进度模式** | 每完成一个资源调 `SetProgress(n, total)` | 精确显示"3/20"比全局进度更可控 |
| **回调叠加** | 遮罩已显示时新请求叠加回调而非重建 | 快速切换界面不会丢失回调 |
| **完成钩子** | 遮罩结束时通知其他系统（如后台预加载器恢复） | 前后台协作的桥梁 |

### 层三：后台预下载调度

> 利用空闲时间提前下载，让前置加载走"全部已缓存"快速路径。

**核心模式**：主菜单后启动 → 按优先级串行下载 → 前台加载时暂停

```lua
-- 启动后台预下载
function BackgroundPreloader.Start(resourceCollectors)
    -- 1. 从各模块收集资源路径
    local allPaths = {}
    for _, collector in ipairs(resourceCollectors) do
        local paths = collector()
        for _, p in ipairs(paths) do table.insert(allPaths, p) end
    end

    -- 2. 去重（保留首次出现顺序 = 优先级顺序）
    allPaths = deduplicate(allPaths)

    -- 3. 过滤：跳过不存在于构建引用中的 + 已缓存的
    local toDownload = {}
    for _, p in ipairs(allPaths) do
        if GetDownloadManager():CanResolve(p) and not cache:Exists(p) then
            table.insert(toDownload, p)
        end
    end

    -- 4. 串行下载
    downloadNext(toDownload, 1)
end

function downloadNext(list, index)
    if index > #list then return end  -- 全部完成

    -- 前台在加载？暂停
    if LoadingOverlay.IsActive() then
        paused = true
        LoadingOverlay.OnFinish(function() resume(list, index) end)
        return
    end

    if cache:Exists(list[index]) then
        downloadNext(list, index + 1)  -- 已缓存，跳过
        return
    end

    cache:GetResourceAsync(guessType(list[index]), list[index], function(res)
        downloadNext(list, index + 1)
    end)
end
```

**优先级设计原则**：

```
从新玩家视角出发：
├─ 最先看到的界面资源 → 最高优先级
├─ 高复用资源（多界面共用）→ 提高优先级
├─ 核心玩法资源（战斗音效等）→ 较高优先级
├─ 解锁后才需要的资源 → 最低优先级
└─ 完全不影响体验的 → 不加入预下载
```

**与前台的协作**（关键）：

```
前台 PreloadGate 触发
  → LoadingOverlay 显示
  → BackgroundPreloader 检测到 IsActive() → 暂停
前台加载完成
  → LoadingOverlay 结束 → 触发 OnFinish 钩子
  → BackgroundPreloader.Resume() → 继续
```

**为什么串行而非并行**：可预测、可暂停、低开销、带宽瓶颈在网络（串行总时间差别不大）

#### 调试手段

后台预下载默认静默。通过开关控制调试输出：

```lua
BackgroundPreloader.SetVerbose(true)   -- 开启：控制台日志 + 屏幕面板
BackgroundPreloader.SetVerbose(false)  -- 关闭：静默
```

调试时关注：
- 优先级顺序是否合理（最先下载的是否是玩家最先用到的）
- 是否有遗漏（打开界面仍触发加载遮罩 = 路径未加入预下载）
- 前后台协作是否正常（暂停/恢复时机）

---

## 新项目接入清单

```
1. 扫描项目 DWP 媒体资源，列出所有类型和数量
2. 按"策略速查表"为每类资源选择加载策略
3. 如果有 NanoVG 图片 → 实现层一（骨架屏占位）
4. 找出所有"打开时需要大量资源"的界面/场景 → 实现层二（入口前置加载）
   - 列出每个界面的资源路径清单
   - 特别注意非图片资源（音效、模型等）不要遗漏
5. 设计后台预下载优先级 → 实现层三
   - 从玩家流程角度排列优先级
   - 接入前台协作机制
6. 测试：开启 verbose 模式，走一遍完整游戏流程
   - 确认没有界面仍出现加载遮罩（= 预下载覆盖不全）
   - 确认没有资源缺失（灰块、无声、T-pose）
```

---

## 常见陷阱

| 陷阱 | 说明 |
|------|------|
| **nvgCreateImage 每帧调用** | 必须缓存句柄，否则显存泄漏 |
| **异步回调中操作 NanoVG** | 回调不在渲染帧内，只清标记让下帧处理 |
| **加载遮罩瞬闪** | 强制最短 0.3 秒显示 |
| **后台下载抢带宽** | 必须有前台检测 + 暂停/恢复机制 |
| **nvgCreateFont 每帧调用** | 和 nvgCreateImage 一样，只初始化一次 |
| **前置加载路径列表不完整** | 音效/模型等忘记加入 → 进入时缺失，无骨架屏兜底 |
| **guessType 类型猜错** | 根据扩展名推断资源类型时注意 .ogg 可能是音效也可能是音乐 |

---

## 详细参考

完整的实战案例和代码细节见：`references/implementation-patterns.md`
