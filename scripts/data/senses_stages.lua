-- 五感剥夺阶段数据表
-- hp: 剩余血量
-- lost_count: 已失去感官数
-- difficulty: 难度等级
-- description: 体验描述

local stages = {
    { hp = 5, lost_count = 0, difficulty = "normal",   description = "完整游戏体验" },
    { hp = 4, lost_count = 1, difficulty = "mild",     description = "轻微不适仍可正常游玩" },
    { hp = 3, lost_count = 2, difficulty = "moderate", description = "明显干扰需要更集中注意力" },
    { hp = 2, lost_count = 3, difficulty = "severe",   description = "严重干扰游戏信息严重缺失" },
    { hp = 1, lost_count = 4, difficulty = "extreme",  description = "极度困难几乎全凭直觉" },
    { hp = 0, lost_count = 5, difficulty = "death",    description = "视觉剥夺画面渐黑GameOver" },
}

return stages
