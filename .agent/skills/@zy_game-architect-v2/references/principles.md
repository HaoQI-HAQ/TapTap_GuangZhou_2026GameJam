# 架构原理与设计流程

## 六大设计原则

1. **需求为本**：架构服务于具体需求，不盲目追求「高级/完美」
2. **迭代演进**：首次设计奠定基础，后续迭代演进；首次设计至关重要
3. **逻辑隔离**：横向分层（基础层/逻辑层）、纵向分模块；类设计清晰独立
4. **合理混用**：OOP用于业务域模拟（复杂→DDD，简单/性能/网络→Data-Driven）；过程式用于业务流程实现（事件驱动、异步）
5. **预留变化**：识别变化点，用抽象接口隔离
6. **测试友好**：留日志、调试、监控、单元测试框架、GM作弊台

## 模块分层

- **基础层（Foundation）**：引擎封装、公共库、模块管理、第三方库隔离
- **逻辑层（Logic）**：
  - 领域模型类：核心玩法，复杂逻辑（用DDD）
  - 数据逻辑类：轻量业务，UI交互（用Data-Driven/MV系列）
  - 功能服务类：引导、预加载等框架服务

## 核心设计流程

| 流程 | 范式 | 适用场景 | 输入→输出 |
|------|------|----------|----------|
| **宏观设计** | — | 结构划分、层级、基本模块 | 特性列表→架构图 |
| **领域模型** | DDD | 核心玩法、场景、玩家数据 | 领域模型+用例→类设计 |
| **逻辑系统** | Data-Driven | 业务模块（数据管理+展示） | 设计文档+用例→数据层设计 |
| **快速原型** | 用例驱动 | Gameplay原型验证 | 用例+交互流程→迭代实现 |

> 所有流程都是迭代过程。


---

## UrhoX 环境适配

### 设计原则的 UrhoX 落地

| 设计原则 | UrhoX 具体实践 |
|---------|---------------|
| **需求为本** | 先查 `.project/settings.json` 确认单机/多人，再决定架构 |
| **迭代演进** | 从脚手架起步（`templates/`），逐步扩展；单文件 → 模块化 |
| **逻辑隔离** | `scripts/` 按领域分目录（`Combat/`、`UI/`、`Data/`），用 `require` 隔离 |
| **合理混用** | 复杂逻辑用 table+metatable OOP；流程控制用事件（`SubscribeToEvent`）+ 协程 |
| **预留变化** | 数值提取到 JSON 配置（`Config/*.json`），用 `cjson.decode()` 加载 |
| **测试友好** | `print()` / `log:Write()` 输出日志；首次交付保留调试信息 |

### 模块分层映射

| 分层 | UrhoX 实现 | 目录 |
|------|-----------|------|
| **基础层** | 引擎内置（Node/Component/Event/Resource） + `urhox-libs/` | `urhox-libs/` |
| **领域模型类** | Lua table + metatable（DDD 模式） | `scripts/Core/` |
| **数据逻辑类** | JSON 配置 + Lua table 容器（Data-Driven） | `scripts/Data/`、`Config/` |
| **功能服务类** | 全局模块 table（引导、预加载、设置） | `scripts/Services/` |
| **表现层** | `urhox-libs/UI`（Yoga Flexbox）/ NanoVG | `scripts/UI/` |

### 典型项目目录结构

```
scripts/
├── main.lua               # 入口，初始化各模块
├── Core/                  # 领域模型（DDD）
│   ├── Player.lua
│   ├── Enemy.lua
│   └── Combat.lua
├── Data/                  # 数据管理（Data-Driven）
│   ├── GameData.lua       # 全局数据容器
│   └── ConfigLoader.lua   # 配置加载
├── Services/              # 功能服务
│   ├── AudioService.lua
│   └── SaveService.lua
├── UI/                    # UI 表现层
│   ├── HUD.lua
│   └── Menu.lua
└── Utils/                 # 工具
    └── Helper.lua

Config/                    # JSON 配置文件
├── items.json
└── levels.json
```

### 关键提醒

1. **脚手架即基础层**：`templates/scaffold-*.lua` 已封装引擎初始化，不需要从零搭建基础层
2. **事件是胶水**：模块之间通过 `SendEvent` / `SubscribeToEvent` 通信，避免直接 `require` 产生循环依赖
3. **单文件 1500 行上限**：超过时必须拆分为模块化结构（见 CLAUDE.md 规则 #13）
4. **引擎已是基础层**：Node/Component/Resource/Event 系统不需要再封装，直接使用

> **相关**: 需求分析 → `requirements.md` | 领域驱动设计 → `domain-driven-design.md`
