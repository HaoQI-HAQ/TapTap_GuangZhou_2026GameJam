-- ============================================================================
-- 《54321》游戏配置表
-- 所有数值调整在这里，不需要改逻辑代码
-- ============================================================================

local CONFIG = {
    Title = "54321",

    -- === 物理世界 ===
    Gravity = 20.0,

    -- === 相机 ===
    CameraOrthoSize = 7.2,
    CameraFollowSpeed = 6.0,
    CameraOffsetY = 1.5,

    -- === 角色 ===
    PlayerSpeed = 4.0,
    PlayerSize = { w = 0.8, h = 1.2 },
    MaxHP = 5,

    -- === 跳跃 ===
    JumpHeight = 2.5,
    MaxJumps = 2,
    CoyoteTime = 0.12,

    -- === 平A攻击（Dead Cells风格连招） ===
    ComboCount = 3,              -- 轻攻击连击数
    LightAttackDamage = 1,       -- 轻攻击伤害
    HeavyAttackDamage = 2,       -- 重击收尾伤害
    AttackRange = 1.5,           -- 攻击距离(米)
    AttackCooldown = 0.25,       -- 连击间隔(秒)
    ComboResetTime = 0.8,        -- 连击超时重置(秒)
    AttackAnimDuration = 0.15,   -- 攻击动画时长

    -- === 下砸攻击 ===
    SlamBaseDamage = 2,          -- 下砸基础伤害
    SlamMaxMultiplier = 3.0,     -- 最大倍率(最高点下砸)
    SlamAOERange = 2.0,          -- 冲击波范围(米)
    SlamAOEDamage = 1,           -- 冲击波伤害
    SlamMinHeight = 0.5,         -- 最低触发高度(米)
    SlamMaxHeight = 4.0,         -- 最大计算高度(米)
    SlamSpeed = 15.0,            -- 下砸速度(m/s)
    SlamCooldown = 0.5,          -- 下砸冷却(秒)

    -- === 卡牌系统 ===
    CardHandSize = 5,            -- 手牌上限
    CountdownTime = 5.0,         -- 倒计时(秒)
    CardConsumeInterval = 1.0,   -- 每秒消耗1张
    CastAnimDuration = 0.3,      -- 施法动画(秒)

    -- === 属性系统 ===
    Elements = { "fire", "water", "thunder", "wind", "ice" },
    ElementColors = {
        fire    = { 255, 69, 0, 255 },     -- #FF4500
        water   = { 30, 144, 255, 255 },   -- #1E90FF
        thunder = { 255, 215, 0, 255 },    -- #FFD700
        wind    = { 50, 205, 50, 255 },    -- #32CD32
        ice     = { 0, 206, 209, 255 },    -- #00CED1
    },
    ElementIcons = {
        fire = "🔥", water = "💧", thunder = "⚡", wind = "🌪️", ice = "❄️",
    },
    -- 克制关系: key 克制 value 列表中的属性
    ElementCounter = {
        fire    = { "wind", "ice" },
        water   = { "fire" },
        thunder = { "water" },
        wind    = { "thunder" },
        ice     = { "wind", "thunder" },
    },

    -- === 怪物 ===
    EnemyHP = 10,
    EnemySize = { w = 0.6, h = 0.8 },
    EnemySpeed = 2.0,
    EnemyChaseRange = 5.0,
    EnemyAttackRange = 1.0,
    EnemyAttackDamage = 1,
    EnemyAttackCooldown = 1.2,

    -- === 五感剥夺 ===
    Senses = { "hearing", "touch", "taste", "smell" },  -- 视觉固定最后
    -- hearing: 音效消失
    -- touch: 受击反馈消失+操控漂移
    -- taste: UI信息混乱
    -- smell: 环境提示消失+倒计时异常
}

-- 自动计算跳跃力 v = sqrt(2*g*h)
CONFIG.JumpForce = math.sqrt(2 * CONFIG.Gravity * CONFIG.JumpHeight)

return CONFIG
