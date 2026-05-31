#!/usr/bin/env python3
"""
Generate runtime-oriented Lua config modules from Excel workbooks.

The generated Lua modules follow a runtime-friendly layout:
- one `Config_<Workbook>.lua` module per workbook
- top-level constants for parameter sheets
- `dCfgXxx` cache tables
- `Get_dCfgXxx(key)` lazy accessors
- `allCfgXxxs` key lists
- `Get_CfgXxxByIndex(index)` 0-based index accessors

Output layout:
    <output-dir>/Client/Config_Activity.lua
    <output-dir>/Server/Config_Activity.lua
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import excel_to_lua_config as base


TARGETS = ("client", "server")
TARGET_DIRS = {
    "client": "Client",
    "server": "Server",
}
TARGET_ALLOWED_ENVS = {
    "client": {"shared", "client"},
    "server": {"shared", "server"},
}

INTEGER_TYPES = {
    "int",
    "integer",
    "long",
    "short",
    "byte",
    "uint",
    "ulong",
    "ushort",
    "sbyte",
}
NUMBER_TYPES = {"float", "double", "number", "decimal"}
BOOLEAN_TYPES = {"bool", "boolean"}
STRING_TYPES = {"string", "str", "text"}
VECTOR_TYPES = {"v2", "v3", "v4", "vector2", "vector3", "vector4"}
TRAILING_COMMA_RE = re.compile(r",(\s*[}\]])")


@dataclass(frozen=True)
class ParamEntry:
    name: str
    env: str
    code: str
    comment: str = ""


@dataclass(frozen=True)
class ColumnDef:
    index: int
    name: str
    comment: str
    raw_type: str
    base_type: str
    env: str


@dataclass(frozen=True)
class FieldValue:
    env: str
    code: str
    comment: str = ""


@dataclass
class RowModel:
    key_code: str
    fields: OrderedDict[str, FieldValue] = field(default_factory=OrderedDict)


@dataclass
class SheetModel:
    sheet_name: str
    class_name: str
    key_field: str
    key_type: str
    rows: OrderedDict[str, RowModel] = field(default_factory=OrderedDict)
    order: list[str] = field(default_factory=list)
    columns: list[ColumnDef] = field(default_factory=list)

    @property
    def dict_name(self) -> str:
        return f"d{self.class_name}"

    @property
    def order_name(self) -> str:
        return f"all{self.class_name}s"

    @property
    def get_by_key_name(self) -> str:
        return f"Get_{self.dict_name}"

    @property
    def get_by_index_name(self) -> str:
        return f"Get_{self.class_name}ByIndex"


@dataclass
class WorkbookModel:
    workbook: Path
    module_stem: str
    constants: list[ParamEntry] = field(default_factory=list)
    sheets: list[SheetModel] = field(default_factory=list)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate runtime Lua config modules from Excel workbooks.")
    parser.add_argument("input_path", help="Path to a .xlsx file or a directory containing .xlsx files.")
    parser.add_argument(
        "--output-dir",
        default="scripts/Configs",
        help="Root output directory. Default: scripts/Configs",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove old generated .lua files under Client/Server before generating.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input_path).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()

    try:
        workbooks = base.collect_workbooks(input_path)
        if not workbooks:
            raise base.ConfigError(
                f"未找到可处理的 xlsx 文件: {input_path}。"
                " 如果你在使用默认技能流程，请先把 Excel 配置文件放到 docs/configs。"
            )

        models = [build_workbook_model(workbook) for workbook in workbooks]
        prepare_output_dirs(output_dir, clean=args.clean)

        generated: dict[str, list[str]] = {target: [] for target in TARGETS}
        for model in models:
            for target in TARGETS:
                content = render_workbook_module(model, target)
                filename = f"{target_module_name(model, target)}.lua"
                out_path = output_dir / TARGET_DIRS[target] / filename
                out_path.write_text(content, encoding="utf-8", newline="\n")
                generated[target].append(filename)
                print(f"[ok] {target:<6} -> {out_path}")

        write_index_files(output_dir, generated)
        return 0
    except base.ConfigError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1


def prepare_output_dirs(output_dir: Path, clean: bool) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    shared_dir = output_dir / "Shared"
    if shared_dir.exists():
        shutil.rmtree(shared_dir)
    for dirname in TARGET_DIRS.values():
        target_dir = output_dir / dirname
        target_dir.mkdir(parents=True, exist_ok=True)
        if clean:
            for file in target_dir.glob("*.lua"):
                file.unlink()


def build_workbook_model(workbook: Path) -> WorkbookModel:
    model = WorkbookModel(
        workbook=workbook,
        module_stem=workbook.stem,
    )

    previous_sheet_name: str | None = None
    for sheet in base.load_workbook(workbook):
        name = sheet.name.strip()
        if not name or name.startswith("Sheet"):
            continue

        if name.startswith("#"):
            model.constants.extend(process_parameter_sheet(sheet))
            continue

        if name.startswith("="):
            if previous_sheet_name is None:
                raise base.ConfigError(f"{workbook.name}:{name} 是附加表，但前面没有可合并的主表。")
            current_sheet_name = previous_sheet_name
        else:
            current_sheet_name = name
            previous_sheet_name = name

        model.sheets.append(process_data_sheet(sheet, current_sheet_name))

    merge_duplicate_sheet_models(model)
    return model


def process_parameter_sheet(sheet: base.WorkbookSheet) -> list[ParamEntry]:
    entries: list[ParamEntry] = []
    fallback_target = base.infer_sheet_target(sheet.name)
    current_target = fallback_target
    header_checked = False

    for row_number, row in enumerate(sheet.rows, start=1):
        first = base.get_cell(row, 0).strip()
        if first == "":
            if all(base.get_cell(row, idx).strip() == "" for idx in range(1, 4)):
                continue
        if first.startswith("##"):
            current_target = base.handle_directive(first, fallback_target, sheet, row_number, current_target)
            continue
        if first.startswith("#"):
            continue

        if not header_checked:
            header_checked = True
            if base.is_parameter_header(row):
                continue

        raw_type = base.get_cell(row, 0).strip()
        name = base.get_cell(row, 1).strip()
        raw_value = base.get_cell(row, 2)
        comment = base.get_cell(row, 3).strip()

        if not name:
            raise base.ConfigError(f"{sheet.workbook.name}:{sheet.name}:{row_number} 参数行缺少变量名。")

        base_type, env = resolve_type_and_env(raw_type, raw_value, current_target)
        code = convert_value(raw_value, base_type)
        entries.append(ParamEntry(name=name, env=env, code=code, comment=comment))

    return entries


def process_data_sheet(
    sheet: base.WorkbookSheet,
    logical_name: str,
) -> SheetModel:
    for row_number, row in enumerate(sheet.rows, start=1):
        first = base.get_cell(row, 0).strip()
        if first.startswith("##"):
            raise base.ConfigError(
                f"{sheet.workbook.name}:{sheet.name}:{row_number} 数据表不支持 ## 指令: {first}。"
            )

    header = detect_sheet_header(sheet.rows)
    if header is None:
        raise base.ConfigError(f"{sheet.workbook.name}:{sheet.name} 无法识别数据表头。")

    comment_row, type_row, field_row, data_start = header
    columns = build_columns(comment_row, type_row, field_row)
    if not columns:
        raise base.ConfigError(f"{sheet.workbook.name}:{sheet.name} 没有可用字段。")

    class_name = parse_sheet_class_name(logical_name)
    key_column = columns[0]
    sheet_model = SheetModel(
        sheet_name=logical_name,
        class_name=class_name,
        key_field=key_column.name,
        key_type=key_column.base_type,
        columns=columns,
    )

    for row_number, row in enumerate(sheet.rows[data_start:], start=data_start + 1):
        first = base.get_cell(row, 0).strip()
        if first == "":
            continue
        if first.startswith("#"):
            continue

        key_raw = base.get_cell(row, key_column.index).strip()
        if key_raw == "":
            raise base.ConfigError(f"{sheet.workbook.name}:{sheet.name}:{row_number} 主键为空。")

        key_code = convert_key_code(key_raw, key_column.base_type)
        if key_code in sheet_model.rows:
            raise base.ConfigError(f"{sheet.workbook.name}:{sheet.name}:{row_number} 出现重复主键: {key_raw}")

        row_model = RowModel(key_code=key_code)
        for column in columns:
            raw_value = base.get_cell(row, column.index)
            if raw_value.strip() == "":
                continue
            code = convert_value(raw_value, column.base_type)
            row_model.fields[column.name] = FieldValue(env=column.env, code=code, comment=column.comment)

        sheet_model.order.append(key_code)
        sheet_model.rows[key_code] = row_model

    return sheet_model


def merge_duplicate_sheet_models(model: WorkbookModel) -> None:
    if not model.sheets:
        return

    merged: OrderedDict[str, SheetModel] = OrderedDict()
    for sheet in model.sheets:
        existing = merged.get(sheet.class_name)
        if existing is None:
            merged[sheet.class_name] = sheet
            continue

        if existing.key_field != sheet.key_field or existing.key_type != sheet.key_type:
            raise base.ConfigError(f"{model.workbook.name}:{sheet.sheet_name} 附加表与主表主键定义不一致。")

        for key_code in sheet.order:
            if key_code in existing.rows:
                raise base.ConfigError(f"{model.workbook.name}:{sheet.sheet_name} 附加表与主表出现重复主键 {key_code}。")
            existing.order.append(key_code)
            existing.rows[key_code] = sheet.rows[key_code]

    model.sheets = list(merged.values())


def detect_sheet_header(rows: list[list[str]]) -> tuple[list[str], list[str], list[str], int] | None:
    non_comment_rows: list[tuple[int, list[str]]] = []
    for index, row in enumerate(rows):
        first = base.get_cell(row, 0).strip()
        if first.startswith("#"):
            continue
        if all(cell.strip() == "" for cell in row):
            continue
        non_comment_rows.append((index, row))
        if len(non_comment_rows) == 3:
            break

    if len(non_comment_rows) < 3:
        return None

    comment_idx, comment_row = non_comment_rows[0]
    type_idx, type_row = non_comment_rows[1]
    field_idx, field_row = non_comment_rows[2]
    if not (comment_idx < type_idx < field_idx):
        return None
    return comment_row, type_row, field_row, field_idx + 1


def build_columns(comment_row: list[str], type_row: list[str], field_row: list[str]) -> list[ColumnDef]:
    column_count = min(len(type_row), len(field_row))
    columns: list[ColumnDef] = []
    for index in range(column_count):
        raw_type = base.get_cell(type_row, index).strip()
        name = base.get_cell(field_row, index).strip()
        comment = base.get_cell(comment_row, index).strip()
        if not raw_type or not name:
            continue
        if raw_type.lower() == "ignore" or name.lower() == "ignore":
            continue
        base_type, env = resolve_type_and_env(raw_type, "", "shared")
        columns.append(
            ColumnDef(
                index=index,
                name=name,
                comment=comment,
                raw_type=raw_type,
                base_type=base_type,
                env=env,
            )
        )
    return columns


def parse_sheet_class_name(sheet_name: str) -> str:
    parts = [part for part in re.split(r"[ \|]+", sheet_name.strip()) if part]
    if len(parts) == 2:
        return parts[1]
    if len(parts) == 3:
        return f"{parts[2]}Data"
    return parts[0]


def resolve_type_and_env(raw_type: str, raw_value: str, fallback_env: str) -> tuple[str, str]:
    tokens = [token.strip() for token in raw_type.split(":") if token.strip()]
    env = fallback_env
    base_type = tokens[0] if tokens else ""
    for token in tokens[1:] if len(tokens) > 1 else []:
        lowered = token.lower()
        if lowered in TARGETS:
            env = lowered
    if not base_type:
        base_type = base.infer_value_type(raw_value)
    return base_type, env


def convert_key_code(raw_value: str, type_name: str) -> str:
    return convert_value(raw_value, type_name)


def convert_value(raw_value: str, type_name: str) -> str:
    normalized = type_name.strip()
    lowered = normalized.lower()
    value = raw_value.strip()

    if is_unsupported_enum_type(normalized):
        raise base.ConfigError(
            f"不再支持 enum 类型: {type_name}。请在 Excel 中改为 int 或 number，并直接填写数值。"
        )
    if lowered.endswith("[]"):
        return convert_array(value, normalized)
    if lowered in STRING_TYPES:
        return base.quote_lua_string(base.unquote(value))
    if lowered in INTEGER_TYPES:
        return base.normalize_integer(value)
    if lowered in NUMBER_TYPES:
        return base.normalize_number(value)
    if lowered in BOOLEAN_TYPES:
        return base.parse_boolean(value)
    if lowered in {"json", "table", "dict", "object"}:
        parsed = parse_json_like(value, force_wrap=False)
        return base.render_lua_literal(parsed)
    if lowered in {"luatable", "luacode"}:
        return value or "{}"
    if lowered in {"nil", "null"}:
        return "nil"
    if lowered in VECTOR_TYPES:
        return convert_vector(value)
    if value.startswith("{") or value.startswith("["):
        parsed = parse_json_like(value, force_wrap=False)
        return base.render_lua_literal(parsed)
    return base.quote_lua_string(base.unquote(value))


def convert_array(raw_value: str, type_name: str) -> str:
    depth = 0
    element_type = type_name
    while element_type.lower().endswith("[]"):
        depth += 1
        element_type = element_type[:-2]
    element_type = element_type.strip()
    element_lower = element_type.lower()

    if raw_value.strip() == "":
        return "{}"

    if is_unsupported_enum_type(element_type):
        raise base.ConfigError(
            f"不再支持 enum 数组类型: {type_name}。请在 Excel 中改为 int[] 或 number[]，并直接填写数值。"
        )

    if element_lower in STRING_TYPES | INTEGER_TYPES | NUMBER_TYPES | BOOLEAN_TYPES:
        return convert_simple_array(raw_value, element_type, depth)

    parsed = parse_json_like(raw_value, force_wrap=True)
    return base.render_lua_literal(parsed)


def convert_simple_array(raw_value: str, element_type: str, depth: int) -> str:
    text = raw_value.strip()
    if depth > 1:
        parsed = parse_json_like(text, force_wrap=False)
        return render_nested_array(parsed, element_type, depth)

    if text.startswith("[") and text.endswith("]"):
        parsed = parse_json_like(text, force_wrap=False)
        if isinstance(parsed, list):
            items = [convert_python_scalar_to_lua(item, element_type) for item in parsed]
            return "{ " + ", ".join(items) + " }"

    parts = [part.strip() for part in base.split_top_level(text, ",") if part.strip()]
    items = [convert_value(part, element_type) for part in parts]
    return "{ " + ", ".join(items) + " }"


def render_nested_array(parsed: object, element_type: str, depth: int) -> str:
    if not isinstance(parsed, list):
        raise base.ConfigError("数组值解析后不是列表。")
    if depth == 1:
        return "{ " + ", ".join(convert_python_scalar_to_lua(item, element_type) for item in parsed) + " }"
    return "{ " + ", ".join(render_nested_array(item, element_type, depth - 1) for item in parsed) + " }"


def convert_python_scalar_to_lua(value: object, element_type: str) -> str:
    lowered = element_type.lower()
    if isinstance(value, str):
        return convert_value(value, element_type)
    if lowered in INTEGER_TYPES:
        return str(int(value))
    if lowered in NUMBER_TYPES:
        return base.normalize_number(str(value))
    if lowered in BOOLEAN_TYPES:
        return "true" if bool(value) else "false"
    return base.render_lua_literal(value)


def convert_vector(raw_value: str) -> str:
    parts = [part.strip() for part in base.split_top_level(raw_value, ",") if part.strip()]
    return "{ " + ", ".join(base.normalize_number(part) for part in parts) + " }"


def default_value_code(type_name: str) -> str | None:
    lowered = type_name.strip().lower()
    if lowered in INTEGER_TYPES or lowered in NUMBER_TYPES:
        return "0"
    if lowered in BOOLEAN_TYPES:
        return "false"
    if lowered in {"v2", "vector2"}:
        return "{ 0, 0 }"
    if lowered in {"v3", "vector3"}:
        return "{ 0, 0, 0 }"
    if lowered in {"v4", "vector4"}:
        return "{ 0, 0, 0, 0 }"
    return None


def is_unsupported_enum_type(type_name: str) -> bool:
    lowered = type_name.lower()
    return lowered.startswith("enum") or lowered.endswith("enum")


def parse_json_like(text: str, force_wrap: bool) -> object:
    cleaned = cleanup_json_like(text)
    candidates = [cleaned]
    wrapped = f"[{cleaned}]"
    if force_wrap:
        candidates.insert(0, wrapped)
    elif wrapped != cleaned:
        candidates.append(wrapped)

    last_error: Exception | None = None
    for candidate in candidates:
        try:
            return __import__("json").loads(candidate)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
    raise base.ConfigError(f"JSON 解析失败: {last_error}")


def cleanup_json_like(text: str) -> str:
    lines = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        line = remove_inline_comment(line).strip()
        if line:
            lines.append(line)
    cleaned = "\n".join(lines).strip()
    return TRAILING_COMMA_RE.sub(r"\1", cleaned)


def remove_inline_comment(line: str) -> str:
    in_quote: str | None = None
    escaped = False
    for index, char in enumerate(line):
        if in_quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == in_quote:
                in_quote = None
            continue
        if char in {'"', "'"}:
            in_quote = char
            continue
        if char == "/" and index + 1 < len(line) and line[index + 1] == "/":
            return line[:index]
    return line


def render_workbook_module(model: WorkbookModel, target: str) -> str:
    module_name = target_module_name(model, target)
    generator_label = f"{Path(__file__).resolve().parents[1].name}/scripts/{Path(__file__).name}"
    lines = [
        "-- ============================================================================",
        f"-- {module_name} ({target})",
        f"-- Auto-generated by {generator_label}",
        f"-- Source workbook: {model.workbook.name}",
        "-- Do not edit manually.",
        "-- ============================================================================",
        "",
        f"local {module_name} = {{}}",
        "",
    ]

    allowed_envs = TARGET_ALLOWED_ENVS[target]
    visible_constants = [entry for entry in model.constants if entry.env in allowed_envs]
    for entry in visible_constants:
        line = f"{module_name}.{entry.name} = {entry.code}"
        if entry.comment:
            line += f" -- {sanitize_comment(entry.comment)}"
        lines.append(line)
    if visible_constants:
        lines.append("")

    for sheet in model.sheets:
        visible_rows = build_visible_rows(sheet, allowed_envs)
        if not visible_rows:
            continue

        creator_table_name = f"_create{sheet.class_name}"
        lines.append(f"{module_name}.{sheet.dict_name} = {{}}")
        lines.append(f"{module_name}.{sheet.order_name} = {render_lua_array(sheet.order)}")
        lines.append(f"local {creator_table_name} = {{")
        for key_code, fields in visible_rows.items():
            lines.append(f"    [{key_code}] = function()")
            lines.append("        return {")
            for field_name, field_value in fields.items():
                lines.append(f"            {base.format_lua_key(field_name)} = {field_value.code},")
            lines.append("        }")
            lines.append("    end,")
        lines.append("}")
        lines.append("")
        lines.extend(render_lazy_methods(module_name, sheet, creator_table_name))
        lines.append("")

    lines.append(f"return {module_name}")
    lines.append("")
    return "\n".join(lines)


def target_module_name(model: WorkbookModel, target: str) -> str:
    prefix = {
        "client": "CfgC_",
        "server": "CfgS_",
    }[target]
    return f"{prefix}{model.module_stem}"


def build_visible_rows(
    sheet: SheetModel,
    allowed_envs: set[str],
) -> OrderedDict[str, OrderedDict[str, FieldValue]]:
    rows: OrderedDict[str, OrderedDict[str, FieldValue]] = OrderedDict()
    for key_code in sheet.order:
        row = sheet.rows[key_code]
        visible_fields: OrderedDict[str, FieldValue] = OrderedDict()
        for column in sheet.columns:
            if column.env not in allowed_envs:
                continue

            field_value = row.fields.get(column.name)
            if field_value is not None:
                if field_value.env in allowed_envs:
                    visible_fields[column.name] = field_value
                continue

            default_code = default_value_code(column.base_type)
            if default_code is not None:
                visible_fields[column.name] = FieldValue(
                    env=column.env,
                    code=default_code,
                    comment=column.comment,
                )
        if visible_fields:
            rows[key_code] = visible_fields
    return rows


def render_lazy_methods(module_name: str, sheet: SheetModel, creator_table_name: str) -> list[str]:
    lines = [
        f"function {module_name}.{sheet.get_by_key_name}(id)",
        f"    local data = {module_name}.{sheet.dict_name}[id]",
        "    if data ~= nil then",
        "        return data",
        "    end",
        f"    local creator = {creator_table_name}[id]",
        "    if creator == nil then",
        "        return nil",
        "    end",
        "    data = creator()",
        f"    {module_name}.{sheet.dict_name}[id] = data",
        "    return data",
        "end",
        "",
        f"function {module_name}.{sheet.get_by_index_name}(index)",
        f"    if index < 0 or index >= #{module_name}.{sheet.order_name} then",
        "        return nil",
        "    end",
        f"    return {module_name}.{sheet.get_by_key_name}({module_name}.{sheet.order_name}[index + 1])",
        "end",
    ]
    return lines


def render_lua_array(items: Iterable[str]) -> str:
    items = list(items)
    if not items:
        return "{}"
    lines = ["{"]
    for item in items:
        lines.append(f"    {item},")
    lines.append("}")
    return "\n".join(lines)


def sanitize_comment(comment: str) -> str:
    return " ".join(comment.replace("\r", "\n").split())


def write_index_files(output_dir: Path, generated: dict[str, list[str]]) -> None:
    for target, filenames in generated.items():
        dir_name = TARGET_DIRS[target]
        lines = [
            "-- Auto-generated index. Do not edit manually.",
            "return {",
        ]
        for filename in sorted(filenames):
            stem = Path(filename).stem
            lines.append(f'    {stem} = require("Configs.{dir_name}.{stem}"),')
        lines.append("}")
        (output_dir / dir_name / "Init.lua").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    raise SystemExit(main())
