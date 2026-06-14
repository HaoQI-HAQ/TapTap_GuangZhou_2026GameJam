# 需求分析方法

## 核心方法

### Feature List（特性列表）
宏观需求起点：操作系统、游戏类型、性能需求、网络需求、项目规模等。
→ 输出：转化为架构结构划分

### Domain Model Analysis（领域模型分析）
分析问题域需求，适合核心玩法和复杂逻辑系统。
步骤：识别领域专家角色→建立领域词汇表→建立领域模型图（类图/状态图/系统图）→迭代精化

### Structured Design Document（结构化设计文档）
逐步分解系统需求的规范文档，核心形式是业务规则。
- 顺序章节（Word）：清晰有组织，适合全面阐述
- 图表（Excel）：视觉直观，适合数值计算和整理
- 分解细化（思维导图）：结构能力强，适合头脑风暴和大纲

### Use Case（用例）
文本描述的用户需求故事。
- Summary：简单场景描述
- Informal：在Summary基础上细化分支场景
- Fully Detailed：使用正式模板（含前置条件、成功保证、主场景、扩展场景）
→ 与业务规则结合：通过嵌入（引用规则ID）或外链（附录引用）

### Interaction User Flow（交互用户流程）
表示交互需求，清晰呈现交互流。
- UI流程图：用UI设计作块，通过链接组成大图
- 内嵌：直接在块内绘制界面
- 分离：用原始块，UI设计作为附件

## 克隆/移植产品分析

- 特性列表：使用思维导图分解风格枚举
- 截图交互流程图
- 演示屏幕录制（带解说）：捕获动态表现和物理效果
- 数据信息文档：反推数值和公式


---

## UrhoX 环境适配

### 需求分析工具链映射

| 通用方法 | UrhoX 项目推荐工具 | 说明 |
|---------|-------------------|------|
| Feature List | Markdown 文件 | 在 `docs/` 目录维护 `features.md`，列出功能清单 |
| 领域模型图 | Markdown + ASCII | Lua 无类型系统，用文本描述实体关系即可 |
| 结构化设计文档 | Markdown / JSON | 业务规则直接写入 `docs/design.md` 或配置 JSON |
| Use Case | Markdown 用例文档 | 按 Summary → Informal → Detailed 逐步细化 |
| UI 流程图 | 截图 + Markdown | 用引擎截图标注交互流，或文本描述 UI 跳转 |

### UrhoX 项目需求文档结构

```
docs/
├── features.md          # 特性列表（宏观需求）
├── design.md            # 结构化设计文档（业务规则）
├── usecases/            # 用例文档
│   ├── uc-001-login.md
│   └── uc-002-combat.md
└── ui-flow.md           # 交互用户流程
```

### Feature List 实践模板

```markdown
# 游戏特性列表

## 平台与技术
- 运行环境：UrhoX（Lua 5.4）
- 目标平台：移动端 + PC
- 渲染：3D / 2D（NanoVG）
- 网络：单机 / 多人（检查 .project/settings.json）

## 核心玩法
- [ ] 角色移动与跳跃
- [ ] 战斗系统（近战/远程）
- [ ] 关卡设计（3 个关卡）

## 系统功能
- [ ] 背包系统
- [ ] 存档/读档（File API + cjson）
- [ ] 排行榜（clientCloud API）

## UI 需求
- [ ] 主菜单（urhox-libs/UI）
- [ ] HUD（血条、分数）
- [ ] 设置面板
```

### 克隆/移植分析适配

| 分析方法 | UrhoX 实践 | 说明 |
|---------|-----------|------|
| 截图交互流程 | 引擎内截图 + 标注 | 用 `input:GetMousePosition()` 记录交互点 |
| 数值反推 | JSON 配置文件 | 反推的数值直接写入 `Config/*.json` |
| 物理效果观察 | 引擎物理参数调试 | `RigidBody.mass`、`restitution`、`friction` 等 |
| 动态表现录制 | 引擎日志 + 状态记录 | `print()` / `log:Write()` 输出关键帧数据 |

### 关键提醒

1. **需求文档放 `docs/` 目录**：与 `scripts/` 分离，不会被引擎加载
2. **配置即文档**：很多业务规则可以直接表达为 JSON 配置或 Lua table 配置，兼做需求和实现
3. **先验证再编码**：用 Use Case 的主场景/扩展场景验证架构设计后，再开始 Lua 编码
4. **多人/单机先判断**：Feature List 中务必标注网络模式（检查 `.project/settings.json` 的 `multiplayer.enabled`）

> **相关**: 架构原理 → `principles.md` | 原型驱动 → `prototype-design.md`
