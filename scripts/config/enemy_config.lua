-- 敌人属性配置表（由 CSV 转换而来，可直接编辑此文件或编辑 CSV 后重新生成）
-- 修改数值后重新构建即可生效
return {
    -- 小怪基础属性
    ENEMY_HP = 10,                -- 小怪生命值
    PATROL_SPEED = 1.5,           -- 巡逻速度（米/秒）
    PATROL_RANGE = 0.5,           -- 巡逻范围（米）
    CHASE_RANGE = 1.0,            -- 追击触发距离（米）
    CHASE_SPEED = 2.5,            -- 追击速度（米/秒）
    ATTACK_RANGE = 1.0,           -- 攻击距离（米）
    ATTACK_DAMAGE = 1,            -- 攻击伤害
    ATTACK_COOLDOWN = 1.0,        -- 攻击冷却（秒）
    FRONT_CHECK_DIST = 1.0,       -- 前方友军检测距离（米）

    -- Boss 属性
    BOSS_HP_MULT = 3,             -- Boss血量倍率
    BOSS_PATROL_SPEED = 1.8,      -- Boss巡逻速度
    BOSS_CHASE_SPEED = 1.8,       -- Boss追击速度
    BOSS_ATTACK_RANGE = 2.0,      -- Boss攻击距离
    BOSS_PATROL_RANGE = 1.0,      -- Boss巡逻范围
    BOSS_SKILL_CD = 4.0,          -- Boss大招冷却时间（秒）
    BOSS_SKILL_RANGE = 3.0,       -- Boss大招伤害范围（米）
    BOSS_SKILL_DAMAGE = 1,        -- Boss大招伤害
}
