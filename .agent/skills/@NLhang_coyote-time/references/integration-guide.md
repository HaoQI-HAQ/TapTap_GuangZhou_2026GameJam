# Coyote Time 集成指南

## 机制总览

| 机制 | 作用 | 触发条件 |
|------|------|---------|
| 土狼时间 | 走出平台后仍可跳跃 | 角色从平台**走出**（非起跳）后的短暂窗口内按跳跃 |
| 输入缓冲 | 落地前按跳跃可自动执行 | 角色落地前的短暂窗口内按跳跃，落地瞬间自动起跳 |

## 状态变量（2D / 3D 通用）

```lua
local COYOTE_GRACE_TIME = 0.1       -- 统一时长参数（秒），调整此值改变手感

local coyoteTimer_ = 0              -- 土狼时间倒计时
local jumpBufferTimer_ = 0          -- 输入缓冲倒计时
local hasJumped_ = false            -- 本次离地是否已执行过跳跃（防重复触发）
```

---

## 2D 项目核心逻辑

替换现有跳跃判断代码（HandleUpdate 内）：

```lua
-- 前置条件: onGround_, jumpPressed, playerBody_(RigidBody2D), PLAYER_JUMP_SPEED

-- 1. 土狼时间计时
if onGround_ then
    coyoteTimer_ = COYOTE_GRACE_TIME
    hasJumped_ = false
else
    if coyoteTimer_ > 0 then
        coyoteTimer_ = coyoteTimer_ - timeStep
    end
end

-- 2. 输入缓冲计时
if jumpPressed then
    jumpBufferTimer_ = COYOTE_GRACE_TIME
else
    if jumpBufferTimer_ > 0 then
        jumpBufferTimer_ = jumpBufferTimer_ - timeStep
    end
end

-- 3. 判断并执行跳跃
local canJump = onGround_ or (coyoteTimer_ > 0 and not hasJumped_)
local wantJump = jumpPressed or jumpBufferTimer_ > 0

if canJump and wantJump then
    playerBody_.linearVelocity = Vector2(playerBody_.linearVelocity.x, PLAYER_JUMP_SPEED)
    playerBody_.awake = true
    coyoteTimer_ = 0
    jumpBufferTimer_ = 0
    hasJumped_ = true
end

```

---

## 3D 项目核心逻辑

3D 项目的计时器逻辑完全相同，仅跳跃执行部分因物理 API 不同而有差异。

### 变体 A：3D 刚体（RigidBody）

```lua
-- 前置条件: onGround_, jumpPressed, playerBody_(RigidBody), PLAYER_JUMP_SPEED

-- 1. 土狼时间计时
if onGround_ then
    coyoteTimer_ = COYOTE_GRACE_TIME
    hasJumped_ = false
else
    if coyoteTimer_ > 0 then
        coyoteTimer_ = coyoteTimer_ - timeStep
    end
end

-- 2. 输入缓冲计时
if jumpPressed then
    jumpBufferTimer_ = COYOTE_GRACE_TIME
else
    if jumpBufferTimer_ > 0 then
        jumpBufferTimer_ = jumpBufferTimer_ - timeStep
    end
end

-- 3. 判断并执行跳跃
local canJump = onGround_ or (coyoteTimer_ > 0 and not hasJumped_)
local wantJump = jumpPressed or jumpBufferTimer_ > 0

if canJump and wantJump then
    local vel = playerBody_.linearVelocity
    playerBody_.linearVelocity = Vector3(vel.x, PLAYER_JUMP_SPEED, vel.z)
    playerBody_.active = true
    coyoteTimer_ = 0
    jumpBufferTimer_ = 0
    hasJumped_ = true
end

```

### 变体 B：3D KinematicCharacter / 手动速度控制

```lua
-- 前置条件: onGround_, jumpPressed, velocityY_(垂直速度变量), PLAYER_JUMP_SPEED

-- 1. 土狼时间计时
if onGround_ then
    coyoteTimer_ = COYOTE_GRACE_TIME
    hasJumped_ = false
else
    if coyoteTimer_ > 0 then
        coyoteTimer_ = coyoteTimer_ - timeStep
    end
end

-- 2. 输入缓冲计时
if jumpPressed then
    jumpBufferTimer_ = COYOTE_GRACE_TIME
else
    if jumpBufferTimer_ > 0 then
        jumpBufferTimer_ = jumpBufferTimer_ - timeStep
    end
end

-- 3. 判断并执行跳跃
local canJump = onGround_ or (coyoteTimer_ > 0 and not hasJumped_)
local wantJump = jumpPressed or jumpBufferTimer_ > 0

if canJump and wantJump then
    velocityY_ = PLAYER_JUMP_SPEED  -- 直接设置垂直速度
    coyoteTimer_ = 0
    jumpBufferTimer_ = 0
    hasJumped_ = true
end

```

---

## 设计说明

### hasJumped_ 如何区分"走出"与"起跳"

**主动起跳**：起跳帧 onGround_=true -> 跳跃执行 -> hasJumped_=true -> 下帧 coyoteTimer_ 虽有残值但被 hasJumped_ 阻止。

**走出边缘**：走出帧 onGround_=false -> hasJumped_ 仍为 false -> coyoteTimer_ 倒计时中按跳跃 -> canJump=true -> 执行跳跃。

### 统一时长参数推荐值

| 值 | 手感 |
|----|------|
| 0.05s | 紧凑，要求精确操作 |
| 0.08-0.12s | **推荐**，自然且不失挑战 |
| 0.15-0.2s | 宽松，适合休闲玩家 |

---

## 集成步骤

### 步骤 1：添加状态变量

在全局变量区域追加上方"状态变量"中的 1 个配置常量和 3 个状态变量。

### 步骤 2：替换跳跃逻辑

根据项目类型选择对应代码变体：
- **2D (Box2D)** → "2D 项目核心逻辑"
- **3D (RigidBody)** → "变体 A"
- **3D (Kinematic/手动控制)** → "变体 B"

替换原有的 `if onGround_ and jumpPressed then ... end` 判断。

### 步骤 3：完成后告知用户

集成完毕后，**必须**向用户说明：

> 土狼时间和输入缓冲已集成完毕。跳跃容差窗口由变量 `COYOTE_GRACE_TIME` 统一控制，当前值为 **0.1 秒**。增大该值（如 0.15）会让跳跃更宽松，减小该值（如 0.05）则要求更精确的操作。
