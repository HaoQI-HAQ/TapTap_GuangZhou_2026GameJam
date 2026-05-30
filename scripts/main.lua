-- 2D横板平台游戏 - 主入口
require "LuaScripts/Utilities/Sample"
require "scripts/input_manager"
require "scripts/player"
require "scripts/ground"
require "scripts/game_ui"
require "scripts/enemy"
require "scripts/menu_overlay"
require "scripts/card_system"
require "scripts/card_ui"
require "scripts/senses_system"

local scene_ = nil
local cameraNode = nil
local camera_ = nil
local player = nil
local gameUI = nil
local inputManager = nil
local menuOverlay = nil
local physicsWorld_ = nil
local enemies = {}
local cardSystem = nil
local cardUI = nil
local sensesSystem = nil

function Start()
    SampleStart()
    CreateScene()

    -- 创建输入管理器
    inputManager = InputManager:new()

    -- === 关卡一 ===
    -- 主地面（100米宽）
    Ground:new(scene_, 0, -3.0, 100.0, 1.0)
    -- 浮空平台（y=0）
    Ground:new(scene_, 4.0, 0.0, 5.0, 0.3)

    -- 创建玩家
    player = Player:new(scene_, inputManager)

    -- 设置相机
    SetupCamera()

    -- 关卡一敌人配置
    -- 平台范围 x=1.5~6.5，平台顶面 y=2.15
    local levelEnemies = {
        { x = 2.5,  y = 1.0, element = "fire" },    -- 火怪（平台上）
        { x = 4.0,  y = 1.0, element = "water" },   -- 水怪（平台上）
        { x = 7.0,  y = -1.9, element = "fire" },   -- 火怪（地面）
        { x = 40.0, y = -1.9, element = "fire", boss = true },  -- boss_01（地面，右边界左10m）
    }
    for _, info in ipairs(levelEnemies) do
        local e = Enemy:new(scene_, camera_, player, info.x, info.y, info.element, info.boss)
        table.insert(enemies, e)
    end
    player.enemies = enemies  -- 攻击时动态查找最近敌人
    -- 给每个敌人赋值友军列表（用于前方检测）
    for _, e in ipairs(enemies) do
        e.enemyList = enemies
    end

    -- 创建游戏UI（含BACK按钮，默认隐藏）
    gameUI = GameUI:new(inputManager, player)

    -- 创建五感剥夺系统
    sensesSystem = SensesSystem:new(scene_, player, gameUI)
    player.sensesSystem = sensesSystem  -- 让玩家能读取漂移值
    gameUI.sensesSystem = sensesSystem  -- 让UI能读取倒计时异常

    -- 创建卡牌系统
    cardSystem = CardSystem:new()
    cardUI = CardUI:new(cardSystem)
    gameUI.cardSystem = cardSystem  -- 绑定卡牌倒计时到顶部UI

    -- 卡牌系统回调：施法开始/结束通知玩家
    cardSystem.onCastStart = function()
        player.castingCard = true
    end
    cardSystem.onCastEnd = function()
        player.castingCard = false
    end
    -- 卡牌使用效果回调
    cardSystem.onCardUsed = function(card)
        -- 根据卡牌类型执行效果
        if card.type == CardSystem.TYPE_ATTACK then
            -- 攻击型：对面朝方向最近敌人造成伤害（克制加倍）
            local myPos = player:getPosition()
            local nearestEnemy = nil
            local nearestDist = 3.0  -- 卡牌攻击范围比平A远
            for _, e in ipairs(enemies) do
                if e:isAlive() and e.node then
                    local enemyX = e.node.position.x
                    -- 只能攻击面朝方向的敌人
                    local inFront = (player.facingRight and enemyX > myPos.x) or
                                    (not player.facingRight and enemyX < myPos.x)
                    if inFront then
                        local dist = math.abs(myPos.x - enemyX)
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestEnemy = e
                        end
                    end
                end
            end
            if nearestEnemy then
                local dmg = 2
                if cardSystem:isCounter(card.element, nearestEnemy.element) then
                    dmg = 4  -- 克制加倍
                    log:Write(LOG_INFO, "[Card] Counter! " .. card.element .. " > " .. nearestEnemy.element)
                end
                nearestEnemy:takeDamage(dmg, myPos.x)
            end
        elseif card.type == CardSystem.TYPE_DEFENSE then
            -- 防御型：给予玩家短暂无敌
            player.invincible = true
            player.invincibleTimer = 2.0
            player.blinkTimer = 0
        elseif card.type == CardSystem.TYPE_SUPPORT then
            -- 辅助型：回复1点HP
            player:heal(1)
        end
    end

    -- 设置玩家受伤回调：触发五感剥夺
    player.onDamagedCallback = function()
        local sense = sensesSystem:onPlayerDamaged()
        if sense then
            log:Write(LOG_INFO, "[Game] Sense deprived: " .. sense)
        end
    end

    -- 设置玩家死亡回调
    player.gameOverCallback = function()
        ShowGameOver()
    end

    -- 创建菜单覆盖层（默认显示，挡住游戏画面）
    menuOverlay = MenuOverlay:new()
    
    -- Game Over UI（默认隐藏）
    _createGameOverUI()

    -- 初始状态：菜单显示，物理暂停，卡牌隐藏
    cardUI:hide()
    physicsWorld_.enabled = false

    SubscribeToEvent("Update", "HandleUpdate")
    log:Write(LOG_INFO, "[Game] Started")
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -9.81)

    -- 方向光（DiffAlpha 材质需要光照才能正确显示精灵颜色）
    local lightNode = scene_:CreateChild("DirectionalLight")
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1, 1, 1, 1)
    lightNode.direction = Vector3(0, 0, 1)
end

function SetupCamera()
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)

    camera_ = cameraNode:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = 5.2

    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)
    renderer.defaultZone.fogColor = Color(0.6, 0.8, 1.0, 1.0)
end

--- 从菜单进入游戏：重置所有状态，显示游戏UI
function EnterGame()
    player:reset()
    sensesSystem:reset()
    for _, e in ipairs(enemies) do
        e:reset()
        e:showHpBar()
    end
    cameraNode.position = Vector3(0, -1.9, -10)
    physicsWorld_.enabled = true
    gameUI:show()
    gameUI:resetCountdown()
    cardSystem:reset()
    cardUI:show()
    log:Write(LOG_INFO, "[Game] Enter game scene")
end

--- 从游戏回到菜单：隐藏游戏UI，暂停物理
function ReturnToMenu()
    physicsWorld_.enabled = false
    gameUI:hide()
    cardUI:hide()
    for _, e in ipairs(enemies) do
        e:hideHpBar()
    end
    menuOverlay:show()
    log:Write(LOG_INFO, "[Game] Return to menu")
end

-- 菜单按钮回调：开始游戏
function HandleMenuStart(eventType, eventData)
    menuOverlay:hide()
    EnterGame()
end

-- 菜单按钮回调：退出游戏
function HandleMenuExit(eventType, eventData)
    engine:Exit()
end

-- 游戏中BACK按钮回调：回到菜单
function HandleBackToMenu(eventType, eventData)
    ReturnToMenu()
end

-- UI按钮回调
function HandleUILeftPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_LEFT, true)
end

function HandleUILeftReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_LEFT, false)
end

function HandleUIRightPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_RIGHT, true)
end

function HandleUIRightReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_RIGHT, false)
end

function HandleUIJumpPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_JUMP, true)
end

function HandleUIJumpReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_JUMP, false)
end

function HandleUIAttackPressed(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_ATTACK, true)
end

function HandleUIAttackReleased(eventType, eventData)
    inputManager:setTouchAction(InputManager.ACTION_ATTACK, false)
end

-- 卡牌按钮点击回调（5个槽位）
function HandleCardBtn1(eventType, eventData)
    cardSystem:useCard(1)
end
function HandleCardBtn2(eventType, eventData)
    cardSystem:useCard(2)
end
function HandleCardBtn3(eventType, eventData)
    cardSystem:useCard(3)
end
function HandleCardBtn4(eventType, eventData)
    cardSystem:useCard(4)
end
function HandleCardBtn5(eventType, eventData)
    cardSystem:useCard(5)
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 菜单显示时暂停游戏逻辑
    if menuOverlay:isVisible() then
        return
    end

    -- 更新输入
    inputManager:update()

    -- 更新玩家
    player:update(dt)

    -- 更新所有敌人
    for _, e in ipairs(enemies) do
        e:update(dt)
    end

    -- 更新卡牌系统
    cardSystem:update(dt)
    cardUI:update(dt)

    -- 更新五感剥夺系统
    sensesSystem:update(dt)

    -- 更新UI（血量显示+倒计时）
    gameUI:update(dt)

    -- 相机延迟跟随玩家
    local targetPos = player:getPosition()
    local camPos = cameraNode.position
    local lerpSpeed = 3.0
    local newX = camPos.x + (targetPos.x - camPos.x) * lerpSpeed * dt
    local newY = camPos.y + (targetPos.y - camPos.y) * lerpSpeed * dt
    cameraNode.position = Vector3(newX, newY, -10)
end

-- Game Over UI
local gameOverContainer = nil

function _createGameOverUI()
    local uiRoot = ui.root

    gameOverContainer = UIElement:new()
    uiRoot:AddChild(gameOverContainer)
    gameOverContainer:SetSize(graphics.width, graphics.height)
    gameOverContainer:SetAlignment(HA_LEFT, VA_TOP)
    gameOverContainer.priority = 900

    -- 半透明黑色遮罩
    local bg = BorderImage:new()
    gameOverContainer:AddChild(bg)
    bg:SetSize(graphics.width, graphics.height)
    bg.color = Color(0, 0, 0, 0.8)

    -- Game Over 文字
    local title = Text:new()
    gameOverContainer:AddChild(title)
    title:SetStyleAuto()
    title.text = "GAME OVER"
    title:SetFontSize(48)
    title:SetAlignment(HA_CENTER, VA_CENTER)
    title:SetPosition(0, -30)
    title.color = Color(1.0, 0.2, 0.2, 1.0)

    -- 重新开始按钮
    local restartBtn = Button:new()
    gameOverContainer:AddChild(restartBtn)
    restartBtn:SetStyleAuto()
    restartBtn:SetSize(160, 50)
    restartBtn:SetAlignment(HA_CENTER, VA_CENTER)
    restartBtn:SetPosition(0, 40)

    local btnText = Text:new()
    restartBtn:AddChild(btnText)
    btnText:SetStyleAuto()
    btnText.text = "RESTART"
    btnText:SetFontSize(22)
    btnText:SetAlignment(HA_CENTER, VA_CENTER)

    SubscribeToEvent(restartBtn, "Released", "HandleRestart")

    gameOverContainer.visible = false
end

function ShowGameOver()
    if gameOverContainer then
        gameOverContainer.visible = true
    end
    physicsWorld_.enabled = false
    gameUI:hide()
    cardUI:hide()
    for _, e in ipairs(enemies) do
        e:hideHpBar()
    end
    log:Write(LOG_INFO, "[Game] Game Over!")
end

function HandleRestart(eventType, eventData)
    if gameOverContainer then
        gameOverContainer.visible = false
    end
    EnterGame()
end

function Stop()
    log:Write(LOG_INFO, "[Game] Stopped")
end
