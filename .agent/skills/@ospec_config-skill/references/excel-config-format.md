# Excel 配置转 Lua 规则

## 适用范围

这个技能用于把 Excel 配置工作簿转换为 Lua 配置模块，默认仓库约定为：

- 从 `docs/configs` 读取 `.xlsx`
- 生成到 `scripts/Configs`

它支持两种输出模式：

1. 参数表模式
输出：
- `scripts/Configs/Config.lua`
- `scripts/Configs/ConfigClient.lua`
- `scripts/Configs/ConfigServer.lua`

2. 完整工作簿模式
输出：
- `scripts/Configs/Client/CfgC_*.lua`
- `scripts/Configs/Server/CfgS_*.lua`

## 输入文件规则

- 只支持 `.xlsx`
- 可以传单文件，也可以传目录
- 目录模式会递归扫描全部 `.xlsx`
- 自动忽略以下文件：
  - 文件名以 `~$` 开头
  - 文件名以 `~` 结尾
  - 文件名包含空格

## Sheet 规则

- 以 `#` 开头的 Sheet 会按参数表处理
- 普通 Sheet 会按数据表处理
- 以 `=` 开头的 Sheet 会作为上一个普通 Sheet 的附加表合并

### 参数 Sheet 默认目标

- Sheet 名包含 `client` 或 `客户端`：默认输出到客户端
- Sheet 名包含 `server` 或 `服务端`：默认输出到服务端
- 其他情况：默认同时输出到客户端和服务端

### 行内指令

第一列以 `##` 开头时，会被识别为指令。当前支持：

- `##target shared`
- `##target client`
- `##target server`
- `##reset-target`

## 参数表列结构

固定四列：

| 列 | 含义 |
|---|---|
| 第 1 列 | 类型 |
| 第 2 列 | 配置路径 |
| 第 3 列 | 值 |
| 第 4 列 | 注释，可选 |

支持表头行，常见表头如下：

- `类型 | 配置路径 | 值 | 注释`
- `type | key | value | comment`

## 配置路径规则

- 使用 `.` 表示嵌套层级
- 例如：
  - `GAME_NAME`
  - `CLOUD_KEYS.PLAYER_LEVEL`
  - `THEME.PRIMARY`
  - `MATCH.MAX_ROUND`

生成后会自动展开为 Lua table。

## Excel 怎么配，Lua 会长什么样

### 1. `#Sheet` 参数表

当 Sheet 名以 `#` 开头时，会按参数表处理。

Excel 示例：

```text
#Global
string    APP_NAME                 DD5
string    VERSION                  0.9.0
int       ENERGY_RECOVER1_SECONDS  360
```

如果它来自 `Global.xlsx`，则会生成：

- `scripts/Configs/Client/CfgC_Global.lua`
- `scripts/Configs/Server/CfgS_Global.lua`

Lua 形态是模块顶层字段：

```lua
local CfgC_Global = {}

CfgC_Global.APP_NAME = "DD5"
CfgC_Global.VERSION = "0.9.0"
CfgC_Global.ENERGY_RECOVER1_SECONDS = 360

return CfgC_Global
```

### 2. 普通数据表，例如 `CfgItem`

普通数据表约定：

- 第 1 行：注释行
- 第 2 行：类型行
- 第 3 行：字段名行
- 第 4 行开始：数据行

Excel 示例：

```text
Sheet: CfgItem

第 1 行：Id | 名称 | 描述 | 品质 | 类型 | 是否虚拟
第 2 行：int | string:client | string:client | int | int | bool
第 3 行：Id | Name | Desc | Quality | BaseType | Virtual
第 4 行起：数据
```

如果它来自 `Items.xlsx`，则会生成：

- `scripts/Configs/Client/CfgC_Items.lua`
- `scripts/Configs/Server/CfgS_Items.lua`

Lua 形态是：

```lua
local CfgC_Items = {}

CfgC_Items.dCfgItem = {}
CfgC_Items.allCfgItems = { ... }

local _createCfgItem = {
    [100] = function()
        return {
            Id = 100,
            Name = "...",
            Desc = "...",
            Quality = 4,
            BaseType = 2,
            Virtual = false,
        }
    end,
}

function CfgC_Items.Get_dCfgItem(id) ... end
function CfgC_Items.Get_CfgItemByIndex(index) ... end
```

### 3. 文件名对应规则

- Excel 文件名决定 Lua 模块文件名
- 普通数据表的 Sheet 名决定模块内部结构名

例如：

- `Global.xlsx` -> `CfgC_Global.lua` / `CfgS_Global.lua`
- `Items.xlsx` -> `CfgC_Items.lua` / `CfgS_Items.lua`
- `Tasks.xlsx` -> `CfgC_Tasks.lua` / `CfgS_Tasks.lua`

而 `CfgItem` 这种 Sheet 名会影响：

- `dCfgItem`
- `allCfgItems`
- `Get_dCfgItem`
- `Get_CfgItemByIndex`

## 类型规则

### 环境后缀

类型支持附加环境后缀：

- `string:shared`
- `int:client`
- `float:server`

规则如下：

- `shared`：同时输出到 `Client` 和 `Server`
- `client`：只输出到 `Client`
- `server`：只输出到 `Server`
- 不写后缀：使用当前 Sheet 的默认目标；如果 Sheet 本身没有 client/server 倾向，则默认双端都有

示例：

```text
string         APP_NAME     DD5
string:client  FONT_NAME    Cinzel
int:server     MAX_ROUND    15
```

生成结果：

- `APP_NAME`：Client 和 Server 都有
- `FONT_NAME`：只有 Client 有
- `MAX_ROUND`：只有 Server 有

### 支持的数据类型

| Excel 类型 | 说明 | 示例 |
|---|---|---|
| `string` | 字符串 | `hello` |
| `int` | 整数 | `50` |
| `float` / `number` | 数字 | `1.5` |
| `bool` | 布尔 | `true` |
| `string[]` | 字符串数组 | `a,b,c` |
| `int[]` | 整数数组 | `1,2,3` |
| `float[]` / `number[]` | 数字数组 | `0.5,1.0,2.5` |
| `json` / `table` / `dict` | JSON 转 Lua table | `{"min":1,"max":5}` |
| `luatable` | 直接写 Lua table | `{ 86, 140, 245, 255 }` |
| `luacode` | 直接写 Lua 表达式 | `math.pi * 2` |
| `nil` | 输出 `nil` | 空值 |

### 自动推断

当类型为空时，脚本会按值做最小推断：

- `true` / `false` -> `bool`
- 整数 -> `int`
- 小数 -> `number`
- 以 `{` 或 `[` 开头 -> `json`
- 其他 -> `string`

## enum 约束

- 本技能不支持从外部代码文件读取 enum 定义
- 本技能不会把 `ItemQuality.Gray`、`ItemBaseType.Other` 这类符号解析成数字
- 如果 Excel 中原本使用 enum，请改成 `int` 或 `number`
- 单元格中应直接填写枚举对应的数值

## 推荐命令

### 仓库默认流程

```powershell
python <skill-dir>/scripts/generate_docs_configs.py --repo-root .
```

这个仓库入口会默认先清空 `scripts/Configs/Client`、`scripts/Configs/Server` 下已有的生成文件，并删除旧的 `scripts/Configs/Shared` 目录，再重新生成。

### 仅生成三份总配置

```powershell
python <skill-dir>/scripts/excel_to_lua_config.py `
  docs/configs `
  --output-dir scripts/Configs
```

### 生成完整模块并清理旧文件

```powershell
python <skill-dir>/scripts/excel_to_lua_modules.py `
  docs/configs `
  --output-dir scripts/Configs `
  --clean
```

命名规则：

- 客户端生成 `CfgC_<Workbook>.lua`
- 服务端生成 `CfgS_<Workbook>.lua`
- 例如 `Items.xlsx` 会生成 `Client/CfgC_Items.lua` 和 `Server/CfgS_Items.lua`

## 使用约束

- 同一目标文件中，同一路径只能定义一次
- 如果中间节点已经是值，不能继续往下写子路径
- 多维数组请使用 JSON
- `json` 值必须是合法 JSON
- 当前不支持 `.xls`
