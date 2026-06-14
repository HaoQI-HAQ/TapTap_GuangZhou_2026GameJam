---@diagnostic disable: undefined-global, type-not-found, param-type-mismatch, assign-type-mismatch
-- 屏幕分辨率适配工具
-- 基于设计分辨率 1280x720（16:9 横屏）计算缩放因子
-- 所有 UI 尺寸乘以 scale 后可在不同手机上保持一致比例
-- 支持手机/平板自适应：宽屏（手机）和窄屏（平板4:3）均有良好体验

local ScreenUtils = {}

-- 设计分辨率（基准）
ScreenUtils.DESIGN_WIDTH = 1280
ScreenUtils.DESIGN_HEIGHT = 720

-- 缓存值（Start 后初始化一次）
ScreenUtils.scaleX = 1.0
ScreenUtils.scaleY = 1.0
ScreenUtils.scale = 1.0   -- 通用缩放（布局用）
ScreenUtils.scaleUI = 1.0 -- 交互控件缩放（按钮/摇杆，保证触控舒适度）
ScreenUtils.screenW = 1280
ScreenUtils.screenH = 720
ScreenUtils.isTablet = false  -- 是否为平板（宽高比 < 1.5）

--- 初始化（在 Start 或任何 UI 创建前调用一次）
function ScreenUtils.init()
    -- 使用 ui.root 尺寸（保证与 UI 坐标系完全一致）
    local w = ui.root.width
    local h = ui.root.height
    -- 若 ui.root 尚未初始化则退回到 graphics 物理分辨率
    if w <= 0 or h <= 0 then
        w = graphics:GetWidth()
        h = graphics:GetHeight()
    end
    ScreenUtils.screenW = w
    ScreenUtils.screenH = h
    ScreenUtils.scaleX = ScreenUtils.screenW / ScreenUtils.DESIGN_WIDTH
    ScreenUtils.scaleY = ScreenUtils.screenH / ScreenUtils.DESIGN_HEIGHT
    -- 横屏游戏高度是瓶颈，用 scaleY 做主缩放（宽度方向留空）
    -- 乘 1.2 补偿手机上 UI 过小的问题
    ScreenUtils.scale = ScreenUtils.scaleY * 1.2

    -- 检测平板：宽高比 < 1.5 认为是平板/接近正方形屏幕
    local aspect = ScreenUtils.screenW / ScreenUtils.screenH
    ScreenUtils.isTablet = (aspect < 1.5)

    -- 交互控件缩放：横屏手机上高度是瓶颈，使用 scaleY 保证按钮不会太小
    -- 平板用 scaleY * 0.9，手机也用 scaleY（按高度适配，宽度有富余）
    if ScreenUtils.isTablet then
        ScreenUtils.scaleUI = math.max(ScreenUtils.scale, ScreenUtils.scaleY * 0.9)
    else
        -- 横屏手机：scaleY 通常比 scaleX 小，但用 scaleY 保证按钮按高度等比
        -- 在 20:9 手机上 scaleY=0.54 仍然偏小，乘 1.3 补偿
        ScreenUtils.scaleUI = ScreenUtils.scaleY * 1.3
    end

    -- 确保大屏幕上 scaleUI 不低于 1.0（控件不应缩小）
    if ScreenUtils.screenW >= 1000 and ScreenUtils.scaleUI < 1.0 then
        ScreenUtils.scaleUI = 1.0
    end

    local dpr = graphics:GetDPR()
    log:Write(LOG_INFO, string.format("[ScreenUtils] screen=%dx%d dpr=%.1f scale=%.3f scaleUI=%.3f aspect=%.2f tablet=%s",
        w, h, dpr, ScreenUtils.scale, ScreenUtils.scaleUI, aspect, tostring(ScreenUtils.isTablet)))
end

--- 按等比缩放换算尺寸（整数）— 通用布局
function ScreenUtils.s(px)
    return math.floor(px * ScreenUtils.scale + 0.5)
end

--- 按交互控件缩放（摇杆、攻击/跳跃按钮等触控元素）
--- 平板上比 s() 更大，保证手指可以轻松点到
function ScreenUtils.ui(px)
    return math.floor(px * ScreenUtils.scaleUI + 0.5)
end

--- 按X轴缩放（用于水平位置/宽度）
function ScreenUtils.sx(px)
    return math.floor(px * ScreenUtils.scaleX + 0.5)
end

--- 按Y轴缩放（用于垂直位置/高度）
function ScreenUtils.sy(px)
    return math.floor(px * ScreenUtils.scaleY + 0.5)
end

--- 获取当前屏幕宽（逻辑像素）
function ScreenUtils.width()
    return ScreenUtils.screenW
end

--- 获取当前屏幕高（逻辑像素）
function ScreenUtils.height()
    return ScreenUtils.screenH
end

return ScreenUtils
