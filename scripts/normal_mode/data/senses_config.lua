-- 五感剥夺配置数据表
-- 修改此文件可调整各感官的效果参数
-- sense: 感官名称
-- order: "random"=随机剥夺(前4次), "fixed_last"=固定最后(第5次=死亡)
-- effectType: 效果类型
-- param1, param2: 效果参数
-- description: 描述

local config = {
    {
        sense = "hearing",
        order = "random",
        effectType = "audio_mute",
        param1 = "sfx",
        param2 = "bgm",
        description = "攻击预警音消失+BGM消失",
    },
    {
        sense = "touch",
        order = "random",
        effectType = "feedback_disable",
        param1 = "vibration",
        param2 = "drift",
        description = "受击反馈消失+操控漂移",
    },
    {
        sense = "taste",
        order = "random",
        effectType = "ui_distort",
        param1 = "hp_bar",
        param2 = "card_ui",
        description = "UI信息混乱+数字乱跳",
    },
    {
        sense = "smell",
        order = "random",
        effectType = "env_hide",
        param1 = "trap_warning",
        param2 = "timer_glitch",
        description = "环境提示消失+倒计时异常",
    },
    {
        sense = "vision",
        order = "fixed_last",
        effectType = "screen_fade",
        param1 = "fade_duration:2.0",
        param2 = "black",
        description = "画面逐渐模糊直到黑屏",
    },
}

return config
