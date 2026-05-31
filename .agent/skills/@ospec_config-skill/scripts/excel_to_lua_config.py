#!/usr/bin/env python3
"""
Convert Excel parameter sheets into shared/client/server Lua config modules.

The converter intentionally focuses on the standard three-file Lua config output:
    scripts/Configs/Config.lua
    scripts/Configs/ConfigClient.lua
    scripts/Configs/ConfigServer.lua

Supported input:
- .xlsx file or a directory containing .xlsx files
- parameter sheets whose name starts with '#'
- rows with columns: type | key path | value | comment
- environment suffixes in type definitions: :shared / :client / :server
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from collections import OrderedDict
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DOC_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"

TARGETS = ("shared", "client", "server")
DEFAULT_OUTPUT_FILES = {
    "shared": "Config.lua",
    "client": "ConfigClient.lua",
    "server": "ConfigServer.lua",
}

IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
INT_RE = re.compile(r"^[+-]?\d+$")
NUMBER_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[fFdDmM]?$")
GENERATOR_LABEL = f"{Path(__file__).resolve().parents[1].name}/scripts/{Path(__file__).name}"


class ConfigError(RuntimeError):
    """Raised when the workbook content does not match the expected config format."""


@dataclass(frozen=True)
class WorkbookSheet:
    workbook: Path
    name: str
    rows: list[list[str]]


@dataclass(frozen=True)
class LuaLeaf:
    code: str
    comment: str = ""
    source: str = ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert Excel parameter sheets into Config/ConfigClient/ConfigServer Lua files."
    )
    parser.add_argument(
        "input_path",
        help="Path to a .xlsx file or a directory containing .xlsx files.",
    )
    parser.add_argument(
        "--output-dir",
        default="scripts/Configs",
        help="Directory for generated Lua files. Default: scripts/Configs",
    )
    parser.add_argument(
        "--shared-file",
        default=DEFAULT_OUTPUT_FILES["shared"],
        help=f"Shared config filename. Default: {DEFAULT_OUTPUT_FILES['shared']}",
    )
    parser.add_argument(
        "--client-file",
        default=DEFAULT_OUTPUT_FILES["client"],
        help=f"Client config filename. Default: {DEFAULT_OUTPUT_FILES['client']}",
    )
    parser.add_argument(
        "--server-file",
        default=DEFAULT_OUTPUT_FILES["server"],
        help=f"Server config filename. Default: {DEFAULT_OUTPUT_FILES['server']}",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Only print errors.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input_path).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_files = {
        "shared": args.shared_file,
        "client": args.client_file,
        "server": args.server_file,
    }

    try:
        workbooks = collect_workbooks(input_path)
        if not workbooks:
            raise ConfigError(
                f"未找到可处理的 xlsx 文件: {input_path}。"
                " 如果你在使用默认技能流程，请先把 Excel 配置文件放到 docs/configs。"
            )

        trees: dict[str, OrderedDict[str, object]] = {
            "shared": OrderedDict(),
            "client": OrderedDict(),
            "server": OrderedDict(),
        }
        sources: dict[str, list[str]] = {target: [] for target in TARGETS}

        processed_sheets = 0
        for workbook in workbooks:
            for sheet in load_workbook(workbook):
                if not should_process_sheet(sheet.name):
                    continue
                processed_sheets += 1
                process_parameter_sheet(sheet, trees, sources)

        if processed_sheets == 0:
            raise ConfigError("未找到以 # 开头的参数 Sheet，无法生成 Lua Config。")

        output_dir.mkdir(parents=True, exist_ok=True)
        for target in TARGETS:
            filename = output_files[target]
            module_name = Path(filename).stem
            content = render_module(module_name, trees[target], sources[target])
            output_path = output_dir / filename
            output_path.write_text(content, encoding="utf-8", newline="\n")
            if not args.quiet:
                print(f"[ok] {target:<6} -> {output_path}")

        return 0
    except ConfigError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1


def collect_workbooks(input_path: Path) -> list[Path]:
    if not input_path.exists():
        raise ConfigError(f"输入路径不存在: {input_path}")

    if input_path.is_file():
        if input_path.suffix.lower() != ".xlsx":
            raise ConfigError(f"当前仅支持 .xlsx 文件: {input_path}")
        return [input_path]

    workbooks = []
    for path in sorted(input_path.rglob("*.xlsx")):
        name = path.name
        if name.startswith("~$") or name.endswith("~") or " " in name:
            continue
        workbooks.append(path)
    return workbooks


def should_process_sheet(sheet_name: str) -> bool:
    return sheet_name.strip().startswith("#")


def load_workbook(path: Path) -> list[WorkbookSheet]:
    with zipfile.ZipFile(path, "r") as archive:
        shared_strings = load_shared_strings(archive)
        workbook_xml = ET.fromstring(archive.read("xl/workbook.xml"))
        workbook_rels = load_relationships(archive, "xl/_rels/workbook.xml.rels")

        sheets: list[WorkbookSheet] = []
        for sheet_el in workbook_xml.findall(f"{{{MAIN_NS}}}sheets/{{{MAIN_NS}}}sheet"):
            name = sheet_el.attrib.get("name", "").strip()
            rel_id = sheet_el.attrib.get(f"{{{DOC_REL_NS}}}id")
            if not rel_id:
                continue
            target = workbook_rels.get(rel_id)
            if not target:
                continue
            sheet_path = normalize_zip_path("xl", target)
            rows = load_sheet_rows(archive, sheet_path, shared_strings)
            sheets.append(WorkbookSheet(workbook=path, name=name, rows=rows))
        return sheets


def load_relationships(archive: zipfile.ZipFile, rels_path: str) -> dict[str, str]:
    rels_root = ET.fromstring(archive.read(rels_path))
    result: dict[str, str] = {}
    for rel in rels_root.findall(f"{{{PKG_REL_NS}}}Relationship"):
        rel_id = rel.attrib.get("Id")
        target = rel.attrib.get("Target")
        if rel_id and target:
            result[rel_id] = target
    return result


def load_shared_strings(archive: zipfile.ZipFile) -> list[str]:
    path = "xl/sharedStrings.xml"
    if path not in archive.namelist():
        return []

    root = ET.fromstring(archive.read(path))
    items: list[str] = []
    for item in root.findall(f"{{{MAIN_NS}}}si"):
        texts = []
        for text in item.iterfind(f".//{{{MAIN_NS}}}t"):
            texts.append(text.text or "")
        items.append("".join(texts))
    return items


def load_sheet_rows(
    archive: zipfile.ZipFile,
    sheet_path: str,
    shared_strings: list[str],
) -> list[list[str]]:
    root = ET.fromstring(archive.read(sheet_path))
    sheet_data = root.find(f"{{{MAIN_NS}}}sheetData")
    if sheet_data is None:
        return []

    rows: list[list[str]] = []
    for row_el in sheet_data.findall(f"{{{MAIN_NS}}}row"):
        values: list[str] = []
        for cell_el in row_el.findall(f"{{{MAIN_NS}}}c"):
            ref = cell_el.attrib.get("r", "")
            col_index = cell_ref_to_index(ref)
            while len(values) < col_index:
                values.append("")
            values.append(read_cell(cell_el, shared_strings))
        rows.append(trim_trailing_empty(values))
    return rows


def normalize_zip_path(base: str, target: str) -> str:
    target = target.replace("\\", "/")
    if target.startswith("/"):
        return target.lstrip("/")

    parts = [part for part in f"{base}/{target}".split("/") if part and part != "."]
    normalized: list[str] = []
    for part in parts:
        if part == "..":
            if normalized:
                normalized.pop()
            continue
        normalized.append(part)
    return "/".join(normalized)


def cell_ref_to_index(cell_ref: str) -> int:
    if not cell_ref:
        return 0
    letters = []
    for ch in cell_ref:
        if ch.isalpha():
            letters.append(ch.upper())
        else:
            break
    if not letters:
        return 0
    index = 0
    for ch in letters:
        index = index * 26 + (ord(ch) - ord("A") + 1)
    return index - 1


def read_cell(cell_el: ET.Element, shared_strings: list[str]) -> str:
    cell_type = cell_el.attrib.get("t", "")
    if cell_type == "inlineStr":
        texts = []
        for text in cell_el.iterfind(f".//{{{MAIN_NS}}}t"):
            texts.append(text.text or "")
        return "".join(texts).strip()

    value_el = cell_el.find(f"{{{MAIN_NS}}}v")
    formula_el = cell_el.find(f"{{{MAIN_NS}}}f")
    raw = ""
    if value_el is not None and value_el.text is not None:
        raw = value_el.text
    elif formula_el is not None and formula_el.text is not None:
        raw = formula_el.text

    if cell_type == "s":
        if raw == "":
            return ""
        index = int(raw)
        if index < 0 or index >= len(shared_strings):
            raise ConfigError(f"sharedStrings 索引越界: {index}")
        return shared_strings[index].strip()
    if cell_type == "b":
        return "true" if raw == "1" else "false"
    return (raw or "").strip()


def trim_trailing_empty(values: list[str]) -> list[str]:
    index = len(values)
    while index > 0 and values[index - 1] == "":
        index -= 1
    return values[:index]


def process_parameter_sheet(
    sheet: WorkbookSheet,
    trees: dict[str, OrderedDict[str, object]],
    sources: dict[str, list[str]],
) -> None:
    fallback_target = infer_sheet_target(sheet.name)
    current_target = fallback_target
    header_checked = False

    for row_number, row in enumerate(sheet.rows, start=1):
        first = get_cell(row, 0).strip()
        if first == "":
            continue
        if first.startswith("##"):
            current_target = handle_directive(first, fallback_target, sheet, row_number, current_target)
            continue
        if first.startswith("#"):
            continue

        if not header_checked:
            header_checked = True
            if is_parameter_header(row):
                continue

        key_path = get_cell(row, 1).strip()
        if not key_path:
            raise ConfigError(f"{sheet.workbook.name}:{sheet.name}:{row_number} 缺少变量名/路径。")

        raw_type = get_cell(row, 0).strip()
        raw_value = get_cell(row, 2)
        comment = get_cell(row, 3).strip()

        base_type, target = resolve_type_and_target(raw_type, raw_value, current_target)
        lua_code = to_lua_code(raw_value, base_type, sheet, row_number, key_path)
        source = f"{sheet.workbook.name}/{sheet.name}:{row_number}"
        insert_config_value(
            tree=trees[target],
            key_path=key_path,
            leaf=LuaLeaf(code=lua_code, comment=comment, source=source),
        )
        sources[target].append(source)


def get_cell(row: list[str], index: int) -> str:
    if index < len(row):
        return row[index]
    return ""


def infer_sheet_target(sheet_name: str) -> str:
    lowered = sheet_name.lower()
    if "client" in lowered or "客户端" in sheet_name:
        return "client"
    if "server" in lowered or "服务端" in sheet_name:
        return "server"
    return "shared"


def handle_directive(
    directive_cell: str,
    fallback_target: str,
    sheet: WorkbookSheet,
    row_number: int,
    current_target: str,
) -> str:
    directive = directive_cell[2:].strip()
    if not directive:
        return current_target

    lowered = directive.lower()
    if lowered.startswith("target"):
        parts = directive.split(None, 1)
        if len(parts) != 2:
            raise ConfigError(f"{sheet.workbook.name}:{sheet.name}:{row_number} 的 ##target 指令缺少目标值。")
        target = parts[1].strip().lower()
        if target not in TARGETS:
            raise ConfigError(
                f"{sheet.workbook.name}:{sheet.name}:{row_number} 的 ##target 仅支持: shared/client/server。"
            )
        return target

    if lowered == "reset-target":
        return fallback_target

    raise ConfigError(
        f"{sheet.workbook.name}:{sheet.name}:{row_number} 不支持的 ## 指令: {directive}。"
        " 当前仅支持 ##target shared/client/server 和 ##reset-target。"
    )


def is_parameter_header(row: list[str]) -> bool:
    normalized = [normalize_label(value) for value in row[:4]]
    if len(normalized) < 3:
        return False

    type_aliases = {"type", "类型", "datatype", "数据类型"}
    key_aliases = {"key", "path", "变量名", "字段名", "名称", "keypath", "配置项"}
    value_aliases = {"value", "值", "默认值"}

    return (
        normalized[0] in type_aliases
        and normalized[1] in key_aliases
        and normalized[2] in value_aliases
    )


def normalize_label(text: str) -> str:
    return re.sub(r"[\s_]+", "", text.strip().lower())


def resolve_type_and_target(type_spec: str, raw_value: str, fallback_target: str) -> tuple[str, str]:
    tokens = [token.strip() for token in type_spec.split(":") if token.strip()]
    base_type = tokens[0].lower() if tokens else ""
    target = fallback_target

    for token in tokens[1:] if len(tokens) > 1 else []:
        lowered = token.lower()
        if lowered in TARGETS:
            target = lowered

    if base_type in TARGETS and len(tokens) == 1:
        target = base_type
        base_type = ""

    if not base_type:
        base_type = infer_value_type(raw_value)

    return base_type, target


def infer_value_type(raw_value: str) -> str:
    value = raw_value.strip()
    lowered = value.lower()
    if lowered in {"true", "false"}:
        return "bool"
    if INT_RE.fullmatch(value):
        return "int"
    if NUMBER_RE.fullmatch(value):
        return "number"
    if value.startswith("{") or value.startswith("["):
        return "json"
    return "string"


def to_lua_code(
    raw_value: str,
    base_type: str,
    sheet: WorkbookSheet,
    row_number: int,
    key_path: str,
) -> str:
    normalized = base_type.strip().lower()
    value = raw_value.strip()

    if normalized.endswith("[]"):
        depth = 0
        element_type = normalized
        while element_type.endswith("[]"):
            depth += 1
            element_type = element_type[:-2]
        return render_array(value, element_type or "string", depth, sheet, row_number, key_path)

    if normalized in {"string", "str", "text"}:
        return quote_lua_string(unquote(value))

    if normalized in {"int", "integer", "long", "short", "byte"}:
        number = normalize_integer(value)
        return number

    if normalized in {"float", "double", "number", "decimal"}:
        number = normalize_number(value)
        return number

    if normalized in {"bool", "boolean"}:
        return parse_boolean(value)

    if normalized in {"json", "dict", "object", "table"}:
        if value == "":
            return "{}"
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ConfigError(
                f"{sheet.workbook.name}:{sheet.name}:{row_number} 的 JSON 值无效 ({key_path}): {exc.msg}"
            ) from exc
        return render_lua_literal(parsed)

    if normalized == "luatable":
        return value or "{}"

    if normalized == "luacode":
        return value or "nil"

    if normalized in {"nil", "null"}:
        return "nil"

    raise ConfigError(
        f"{sheet.workbook.name}:{sheet.name}:{row_number} 的类型不受支持: {base_type} ({key_path})"
    )


def render_array(
    raw_value: str,
    element_type: str,
    depth: int,
    sheet: WorkbookSheet,
    row_number: int,
    key_path: str,
) -> str:
    if raw_value == "":
        return "{}"

    if depth > 1:
        try:
            parsed = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise ConfigError(
                f"{sheet.workbook.name}:{sheet.name}:{row_number} 的多维数组必须使用 JSON 格式 ({key_path})"
            ) from exc
        return render_typed_array(parsed, element_type, depth)

    if looks_like_json_array(raw_value):
        try:
            parsed = json.loads(raw_value)
        except json.JSONDecodeError as exc:
            raise ConfigError(
                f"{sheet.workbook.name}:{sheet.name}:{row_number} 的数组值无效 ({key_path}): {exc.msg}"
            ) from exc
        if not isinstance(parsed, list):
            raise ConfigError(f"{sheet.workbook.name}:{sheet.name}:{row_number} 的数组值不是列表: {key_path}")
        return render_typed_array(parsed, element_type, depth)

    parts = [part.strip() for part in split_top_level(raw_value, ",")]
    rendered = [convert_scalar_to_lua(part, element_type) for part in parts if part != ""]
    return "{ " + ", ".join(rendered) + " }"


def render_typed_array(value: object, element_type: str, depth: int) -> str:
    if not isinstance(value, list):
        raise ConfigError("数组类型的值必须是列表。")
    if depth == 1:
        rendered = [convert_scalar_to_lua(item, element_type) for item in value]
        return "{ " + ", ".join(rendered) + " }"
    rendered = [render_typed_array(item, element_type, depth - 1) for item in value]
    return "{ " + ", ".join(rendered) + " }"


def convert_scalar_to_lua(value: object, element_type: str) -> str:
    if isinstance(value, str):
        return to_lua_code(value, element_type, WorkbookSheet(Path("<inline>"), "#", []), 0, "<inline>")
    if element_type in {"string", "str", "text"}:
        return quote_lua_string(str(value))
    if element_type in {"bool", "boolean"}:
        return "true" if bool(value) else "false"
    if element_type in {"int", "integer", "long", "short", "byte"}:
        return normalize_integer(str(value))
    if element_type in {"float", "double", "number", "decimal"}:
        return normalize_number(str(value))
    if element_type in {"json", "dict", "object", "table"}:
        return render_lua_literal(value)
    if element_type == "luatable":
        return str(value)
    if element_type == "luacode":
        return str(value)
    if element_type in {"nil", "null"}:
        return "nil"
    return render_lua_literal(value)


def looks_like_json_array(text: str) -> bool:
    stripped = text.strip()
    return stripped.startswith("[") and stripped.endswith("]")


def split_top_level(text: str, separator: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    quote: str | None = None
    escape = False

    for ch in text:
        if quote is not None:
            current.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            continue

        if ch in {'"', "'"}:
            quote = ch
            current.append(ch)
            continue

        if ch in "[{(":
            depth += 1
            current.append(ch)
            continue

        if ch in "]})":
            depth = max(depth - 1, 0)
            current.append(ch)
            continue

        if ch == separator and depth == 0:
            parts.append("".join(current))
            current = []
            continue

        current.append(ch)

    parts.append("".join(current))
    return parts


def normalize_integer(value: str) -> str:
    text = strip_numeric_suffix(value.strip())
    try:
        parsed = Decimal(text)
    except InvalidOperation as exc:
        raise ConfigError(f"整数值无效: {value}") from exc
    if parsed != parsed.to_integral_value():
        raise ConfigError(f"整数值包含小数部分: {value}")
    return str(int(parsed))


def normalize_number(value: str) -> str:
    text = strip_numeric_suffix(value.strip())
    if text == "":
        raise ConfigError("数值不能为空。")
    if not NUMBER_RE.fullmatch(text):
        try:
            Decimal(text)
        except InvalidOperation as exc:
            raise ConfigError(f"数值无效: {value}") from exc
    normalized = text.lower()
    if "e" in normalized:
        return normalized
    if "." in normalized:
        normalized = normalized.rstrip("0").rstrip(".")
        return normalized or "0"
    return normalized


def strip_numeric_suffix(value: str) -> str:
    return re.sub(r"[fFdDmM]$", "", value)


def parse_boolean(value: str) -> str:
    lowered = unquote(value).strip().lower()
    if lowered in {"true", "1", "yes", "y", "on"}:
        return "true"
    if lowered in {"false", "0", "no", "n", "off"}:
        return "false"
    raise ConfigError(f"布尔值无效: {value}")


def unquote(value: str) -> str:
    text = value.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in {'"', "'"}:
        return text[1:-1]
    return text


def quote_lua_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        .replace('"', '\\"')
    )
    return f'"{escaped}"'


def render_lua_literal(value: object) -> str:
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return normalize_number(repr(value))
    if isinstance(value, str):
        return quote_lua_string(value)
    if isinstance(value, list):
        return "{ " + ", ".join(render_lua_literal(item) for item in value) + " }"
    if isinstance(value, dict):
        parts = []
        for key, item in value.items():
            lua_key = format_lua_key(str(key))
            parts.append(f"{lua_key} = {render_lua_literal(item)}")
        return "{ " + ", ".join(parts) + " }"
    return quote_lua_string(str(value))


def insert_config_value(
    tree: OrderedDict[str, object],
    key_path: str,
    leaf: LuaLeaf,
) -> None:
    parts = [part.strip() for part in key_path.split(".") if part.strip()]
    if not parts:
        raise ConfigError(f"非法配置路径: {key_path}")

    node: OrderedDict[str, object] = tree
    prefix: list[str] = []
    for part in parts[:-1]:
        prefix.append(part)
        current = node.get(part)
        if current is None:
            child: OrderedDict[str, object] = OrderedDict()
            node[part] = child
            node = child
            continue
        if isinstance(current, LuaLeaf):
            dotted = ".".join(prefix)
            raise ConfigError(f"配置路径冲突: {dotted} 既是值又被当作表。")
        node = current

    final_key = parts[-1]
    existing = node.get(final_key)
    if existing is not None:
        previous = existing.source if isinstance(existing, LuaLeaf) else ".".join(parts)
        raise ConfigError(f"重复配置路径: {key_path} (已由 {previous} 定义, 当前 {leaf.source})")
    node[final_key] = leaf


def render_module(module_name: str, tree: OrderedDict[str, object], sources: Iterable[str]) -> str:
    unique_sources = list(OrderedDict.fromkeys(sources))
    lines = [
        "-- ============================================================================",
        f"-- {module_name}",
        f"-- Auto-generated by {GENERATOR_LABEL}",
        "-- Do not edit manually.",
    ]
    if unique_sources:
        lines.append(f"-- Sources: {', '.join(unique_sources)}")
    lines.extend(
        [
            "-- ============================================================================",
            "",
            f"local {module_name} = {render_table(tree, 0)}",
            "",
            f"return {module_name}",
            "",
        ]
    )
    return "\n".join(lines)


def render_table(tree: OrderedDict[str, object], level: int) -> str:
    indent = "    " * level
    child_indent = "    " * (level + 1)
    if not tree:
        return "{}"

    lines = ["{"]
    for key, value in tree.items():
        lua_key = format_lua_key(key)
        if isinstance(value, LuaLeaf):
            line = f"{child_indent}{lua_key} = {value.code},"
            if value.comment:
                line += f" -- {value.comment}"
            lines.append(line)
        else:
            rendered = render_table(value, level + 1)
            lines.append(f"{child_indent}{lua_key} = {rendered},")
    lines.append(f"{indent}}}")
    return "\n".join(lines)


def format_lua_key(key: str) -> str:
    if IDENTIFIER_RE.fullmatch(key):
        return key
    return f"[{quote_lua_string(key)}]"


if __name__ == "__main__":
    raise SystemExit(main())
