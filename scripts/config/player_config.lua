-- 玩家属性配置表（由 CSV 转换而来，可直接编辑此文件或编辑 CSV 后重新生成）
-- 修改数值后重新构建即可生效
return {
    MOVE_SPEED = 3.0,             -- 移动速度（米/秒）
    JUMP_FORCE = 5.0,             -- 跳跃力度
    MAX_JUMPS = 2,                -- 最大跳跃次数（2段跳）
    FALL_MULTIPLIER = 2,          -- 下落加速倍数
    MAX_HP = 5,                   -- 最大生命值

    INVINCIBLE_DURATION = 1.5,    -- 无敌帧持续时间（秒）
    BLINK_INTERVAL = 0.1,         -- 闪烁间隔
    NEAR_DEATH_SPEED_MULT = 0.6,  -- 濒死时移动速度倍率

    ATTACK_RANGE = 1.5,           -- 平A攻击距离（米）
    ATTACK_DAMAGE = 1,            -- 平A伤害
    ATTACK_COOLDOWN = 0.5,        -- 攻击冷却（秒）

    SLAM_SPEED = 15.0,            -- 下砸速度（米/秒）
    SLAM_AOE_RANGE = 2.0,         -- 下砸AOE范围（米）
    SLAM_DAMAGE = 3,              -- 下砸伤害
    SLAM_KNOCKBACK = 8.0,         -- 击飞力度
}
