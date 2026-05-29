# 联机游戏架构

## 拓扑选型

| 拓扑 | 连接 | 适用场景 | 核心权衡 |
|------|------|----------|----------|
| **专用服务器** | 长连接（TCP） | MMO、竞技FPS、实时动作 | 权威、抗作弊；但需基础设施 |
| **Web服务器** | 短连接（HTTP） | 回合制、休闲、社交 | 无状态易扩展；无实时推送 |
| **玩家托管** | 监听服务器 | 休闲合作、小型PvE | 零服务器成本；但有主机优势 |
| **P2P** | UDP | 格斗游戏、2人对战 | 最低延迟；但O(N²)连接、难反作弊 |

## 会话模型

### 持久世界 + 实例
- **Persistent World**：无缝开放世界，跨玩家会话持久
- **Region/Zone**：分区域，每个区一台服务器
- **Instance**：按需生成的私有副本（副本/竞技场），生命周期：创建→进入→游戏→完成→销毁
- **Channel**：同一野外区域多个复制品，用于分流

### 大厅 + 房间
** Lobby**：匹配前空间
** Matchmaking**：Elo/规则匹配，独立服务
** Party/Team**：组队进入匹配
** Room生命周期**：创建→等待→准备确认→开始→运行→结束条件→结算→销毁

## 同步模型

### State Sync（状态同步）
服务器计算权威状态，推送给客户端。
- **全量快照**：完整世界状态定期发送，简单但带宽重
- **增量压缩**：只发变化字段，结合脏标记
- **客户端预测**：本地玩家输入立即应用，等待服务器确认
- **服务器回溯**：命中检测时服务器回溯世界到客户端感知时间
- **实体插值**：远程实体显示在过去状态（两快照之间插值）

### Frame Sync（帧同步）
所有客户端同一逻辑帧执行同一输入，确定性模拟产生相同状态。
- **确定性要求**：定点数学、确定性随机（种子）、一致迭代顺序
- **输入延迟**：本地输入显示故意延迟N帧
- **乐观回滚（Rollback）**：预测提前，差异时回滚重算（GGPO风格）

### 混合策略
核心世界状态同步，特定子系统（战斗结算）用帧同步。

## 分布式服务器架构

| 进程 | 职责 | 状态 |
|------|------|------|
| **Gateway** | 客户端入口、加密握手、路由 | 无状态 |
| **Connector** | 会话持久、协议编解码、消息转发 | 会话状态 |
| **Auth** | 鉴权、Token | 无状态 |
| **Lobby** | 匹配、组队、房间分配 | 软状态 |
| **Player** | 玩家数据权威（属性/物品/货币等） | 按玩家 |
| **Game/Room** | 房间/比赛权威玩法逻辑 | 按房间 |
| **Scene** | 持久世界区域管理、AOI | 按区域 |
| **DB Proxy** | 数据库抽象、读写缓存 | 缓存 |

## 同步协议设计

命名约定：`{系统}_{动作}` + `Req/Resp/Notify`

```
-- 背包（CRUD）
Item_List_Req / Item_List_Resp
Item_Use_Req / Item_Use_Resp
Item_Change_Notify（服务器推送变化）

-- 玩法（命令，非CRUD）
Move_Req
Skill_Cast_Req / Skill_Cast_Resp
State_Sync_Notify（服务器推送权威状态）
```

## 反作弊（架构）

- **原则**：永远不信任客户端数据
- **命令模式**：客户端发送意图（命令），服务器在权威状态执行
- **输入验证**：范围检查、速率限制、序列验证
- **状态验证**：周期性对比客户端报告状态与服务器状态


---

## UrhoX 环境适配

### UrhoX 多人架构简化模型

UrhoX 提供**内置多人支持**，通过配置驱动，无需自建分布式服务器集群：

| 通用概念 | UrhoX 实现 | 说明 |
|---------|-----------|------|
| 分布式服务器（Gateway/Auth/Lobby 等） | **内置引擎服务** | 配置 `.project/settings.json` 即可 |
| 自定义网络协议 | **Client.lua / Server.lua** 分离 | 引擎自动处理底层通信 |
| 匹配系统 | **内置 matchmaking** | `match_info` 配置即可 |
| 持久世界 | **内置 persistent_world** | 配置 `enabled: true` |

### 配置驱动的多人模式

```json
// .project/settings.json
{
  "@runtime": {
    "multiplayer": {
      "enabled": true,
      "max_players": 4,
      "match_info": {
        "desc_name": "free_match",
        "player_number": 4
      }
    }
  }
}
```

### 代码组织

```
scripts/
├── main.lua              -- 单机入口（multiplayer.enabled = false）
├── client_main.lua       -- 客户端入口（multiplayer.enabled = true）
└── server_main.lua       -- 服务端入口（multiplayer.enabled = true）
```

### 状态同步在 UrhoX 中的实现

```lua
-- Server.lua：权威状态
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 服务器计算游戏逻辑
    updateGameState(dt)
    -- 引擎自动同步到客户端
end

-- Client.lua：客户端预测 + 插值
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 本地预测移动
    predictLocalPlayer(dt)
    -- 远程实体插值
    interpolateRemotePlayers(dt)
end
```

### 关键区别

1. **不需要自建 Gateway/Connector/Auth** — 引擎内置
2. **不需要实现网络协议** — 引擎自动序列化
3. **重点关注**：游戏逻辑的 Client/Server 分离、状态同步策略选择
4. **反作弊原则不变**：服务器权威，客户端只发送意图

### 关键提醒

1. **先读 `.project/settings.json`**：`multiplayer.enabled` 决定单机/多人模式
2. **Client/Server 代码物理分离**：`entry_client` 和 `entry_server` 分别指定入口
3. **不需要自建网络层**：引擎内置 Gateway/Auth/序列化
4. **服务器权威**：客户端只发送意图（按键/方向），不直接修改游戏状态
5. **单机先做好再加联机**：核心循环未验证就加联机 = 高成本无留存

> **相关**: 基础框架 → `system-foundation.md` | 性能优化 → `performance-optimization.md`
