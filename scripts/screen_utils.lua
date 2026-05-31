-- 屏幕分辨率适配工具
-- 基于设计分辨率 1280x720（16:9 横屏）计算缩放因子
-- 所有 UI 尺寸乘以 scale 后可在不同手机上保持一致比例

local ScreenUtils = {}

-- 设计分辨率（基准）
ScreenUtils.DESIGN_WIDTH = 1280
ScreenUtils.DESIGN_HEIGHT = 720

-- 缓存值（Start 后初始化一次）
ScreenUtils.scaleX = 1.0
ScreenUtils.scaleY = 1.0
ScreenUtils.scale = 1.0   -- 取 min(scaleX, scaleY)，保持等比不变形
ScreenUtils.screenW = 1280
ScreenUtils.screenH = 720

--- 初始化（在 Start 或任何 UI 创建前调用一次）
function ScreenUtils.init()
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    -- 使用逻辑分辨率（物理分辨率 / DPR）
    ScreenUtils.screenW = math.floor(w / dpr)
    ScreenUtils.screenH = math.floor(h / dpr)
    ScreenUtils.scaleX = ScreenUtils.screenW / ScreenUtils.DESIGN_WIDTH
    ScreenUtils.scaleY = ScreenUtils.screenH / ScreenUtils.DESIGN_HEIGHT
    ScreenUtils.scale = math.min(ScreenUtils.scaleX, ScreenUtils.scaleY)
    log:Write(LOG_INFO, string.format("[ScreenUtils] phys=%dx%d dpr=%.1f logical=%dx%d scale=%.3f",
        w, h, dpr, ScreenUtils.screenW, ScreenUtils.screenH, ScreenUtils.scale))
end

--- 按等比缩放换算尺寸（整数）
function ScreenUtils.s(px)
    return math.floor(px * ScreenUtils.scale + 0.5)
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
