---
name: config-skill
description: "将 docs/configs 下的 Excel 配置工作簿生成到 scripts/Configs/Client/CfgC_*.lua 与 scripts/Configs/Server/CfgS_*.lua。\nUse when users need to (1) 把 Excel 配置表导出成 Lua 配置, (2) Excel 配置表更新了重新生成 Lua 配置, (3) 查找或更新配置文件, (4) 重新导出配置, (5) 用户提供了 .xlsx 文件并希望生成游戏配置。"
---

## 如何使用

### 首次安装 / 初始化

对 AI 说：

> **帮我把 Excel 配置表导出成 Lua 配置**

AI 会自动完成以下操作：

1. 扫描 `docs/configs/` 下的所有 `.xlsx` 文件
2. 清空旧产物，生成 `scripts/Configs/Client/CfgC_*.lua` 和 `scripts/Configs/Server/CfgS_*.lua`
3. 生成 `Client/Init.lua` 和 `Server/Init.lua` 入口文件
4. 构建项目

### Excel 更新后重新生成

每次修改了 `docs/configs/` 下的 Excel 文件后，对 AI 说：

> **Excel 配置表更新了，帮我重新生成 Lua 配置**

AI 会清空旧文件并重新导出全部配置，确保代码中的配置与 Excel 保持同步。

---

# Config Skill

默认仓库约定：

- 输入目录：`docs/configs`
- 输出目录：`scripts/Configs`
- 运行时产物：`Client/CfgC_*.lua`、`Server/CfgS_*.lua`

## AI 必读

- `scripts/Configs/Client/*.lua` 和 `scripts/Configs/Server/*.lua` 是 Excel 导表后的运行时配置真源。AI 在分析、修改、联调前后端逻辑时，应优先读取这里，而不是先猜测配置结构。
- 前端或客户端逻辑查配置时，优先查看 `scripts/Configs/Client/Init.lua`，再进入对应的 `CfgC_*.lua` 模块。
- 后端或服务端逻辑查配置时，优先查看 `scripts/Configs/Server/Init.lua`，再进入对应的 `CfgS_*.lua` 模块。
- `docs/configs/*.xlsx` 是配置编辑源；`scripts/Configs/Client/*.lua` 和 `scripts/Configs/Server/*.lua` 是导出后的代码产物。AI 修改 Excel 后，如果后续任务依赖新配置，必须先重新生成 Lua，再继续改代码。
- 当前技能的核心分层规则是：未写环境后缀默认双端都有，`:client` 只进客户端，`:server` 只进服务端，`:shared` 视为双端都有。AI 在排查"为什么某端读不到配置"时，必须先检查这一层规则。
- 不要手工维护 `CfgC_*.lua` / `CfgS_*.lua` 的内容。这些文件是自动生成产物，应通过修改 `docs/configs/*.xlsx` 并重新导出完成更新。
- `scripts/Configs/Config.lua`、`scripts/Configs/ConfigClient.lua`、`scripts/Configs/ConfigServer.lua` 属于参数表模式的旧输出入口。若任务明确依赖当前工作簿导表链路，应优先读取 `Client/CfgC_*` 与 `Server/CfgS_*`，不要混淆两套产物。

## 资源

- 格式与示例：`references/excel-config-format.md`
- 仓库入口脚本：`scripts/generate_docs_configs.py`
- 参数表生成器：`scripts/excel_to_lua_config.py`
- 完整工作簿生成器：`scripts/excel_to_lua_modules.py`

## 工作流

1. 先查看仓库里是否存在 `docs/configs`，并收集其中的 `.xlsx` 文件。
2. 如果需要确认 Excel 结构、Sheet 规则、文件命名、示例或支持的数据类型，阅读 [references/excel-config-format.md](references/excel-config-format.md)。
3. 如果需求是"按仓库约定自动扫描 `docs/configs` 并输出到 `scripts/Configs`"，优先运行：

```powershell
python <skill-dir>/scripts/generate_docs_configs.py --repo-root .
```

这个入口脚本会在生成前先清空 `scripts/Configs/Client`、`scripts/Configs/Server`，并删除旧的 `scripts/Configs/Shared` 目录，再生成新的结果。

如果技能放在仓库根目录的 `.agent/skills/config-skill`，则 `<skill-dir>` 通常是 `.agent/skills/config-skill`。

4. 如果输入是单个参数表，目标是生成三份总配置文件，可直接运行：

```powershell
python <skill-dir>/scripts/excel_to_lua_config.py `
  docs/configs `
  --output-dir scripts/Configs
```

5. 如果输入是完整配置工作簿，包含 `#` 参数 Sheet 和普通数据 Sheet，优先运行：

```powershell
python <skill-dir>/scripts/excel_to_lua_modules.py `
  docs/configs `
  --output-dir scripts/Configs `
  --clean
```

6. 生成后检查以下结果是否齐全：

- `scripts/Configs/Client/CfgC_*.lua`
- `scripts/Configs/Server/CfgS_*.lua`
- `scripts/Configs/Client/Init.lua`
- `scripts/Configs/Server/Init.lua`

## 使用原则

- 不要在技能文档里硬编码某个项目的业务字段、主题色、云变量 Key 或数值表内容。
- 让 Excel 示例承担"字段长什么样"的说明作用；主技能文档只保留 AI 真正需要的流程与读取规则。
- 每次运行技能生成配置时，都要先清空 `scripts/Configs/Client`、`scripts/Configs/Server`，并删除旧的 `scripts/Configs/Shared` 目录，再重新生成。
- 不支持任何外部 enum 映射文件，也不依赖 C#、TypeScript 或其他代码侧枚举定义。
- 如果某个字段原来写的是 enum，请在 Excel 中直接改成 `int` 或 `number`，并填写实际数值。

## 结果校验

- 确认生成文件头部标记为自动生成，不要手改生成产物。
- 抽查至少一个 `Client` 和一个 `Server` 模块，确认字段分层正确。
- 如果传入了 `--clean`，确认旧的生成文件已经被清理，没有残留过时的 Lua 配置。

---

反馈：chaos@ospec.ai
