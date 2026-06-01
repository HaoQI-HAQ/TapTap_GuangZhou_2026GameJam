#!/usr/bin/env python3
"""
Generate Lua config modules for a repository that stores Excel workbooks under docs/configs.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
MODULE_SCRIPT = SCRIPT_DIR / "excel_to_lua_modules.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan docs/configs, clear old outputs under scripts/Configs, and generate fresh Client/Server Lua config modules."
    )
    parser.add_argument(
        "--repo-root",
        default="",
        help="Repository root. Default: auto-detect from the current working directory and its parents.",
    )
    parser.add_argument(
        "--input-dir",
        default="docs/configs",
        help="Relative Excel input directory under repo root. Default: docs/configs",
    )
    parser.add_argument(
        "--output-dir",
        default="scripts/Configs",
        help="Relative Lua output directory under repo root. Default: scripts/Configs",
    )
    return parser.parse_args()


def find_repo_root(start: Path, input_dir: str, output_dir: str) -> Path:
    candidates = [start, *start.parents]
    for candidate in candidates:
        if (candidate / input_dir).exists():
            return candidate
    for candidate in candidates:
        if (candidate / "docs").exists() or (candidate / "scripts").exists():
            return candidate
    return start


def resolve_repo_root(raw_repo_root: str, input_dir: str, output_dir: str) -> Path:
    if raw_repo_root:
        return Path(raw_repo_root).expanduser().resolve()
    return find_repo_root(Path.cwd().resolve(), input_dir, output_dir)


def resolve_repo_path(repo_root: Path, raw_path: str) -> Path:
    candidate = Path(raw_path).expanduser()
    if candidate.is_absolute():
        return candidate.resolve()
    return (repo_root / candidate).resolve()


def find_excel_files(input_dir: Path) -> list[Path]:
    files: list[Path] = []
    for path in sorted(input_dir.rglob("*.xlsx")):
        name = path.name
        if name.startswith("~$") or name.endswith("~") or " " in name:
            continue
        files.append(path)
    return files


def main() -> int:
    args = parse_args()
    repo_root = resolve_repo_root(args.repo_root, args.input_dir, args.output_dir)
    input_dir = resolve_repo_path(repo_root, args.input_dir)
    output_dir = resolve_repo_path(repo_root, args.output_dir)

    if not input_dir.exists():
        print(f"[error] Input directory not found: {input_dir}", file=sys.stderr)
        print("[hint] Put your Excel config files under docs/configs, or override --input-dir.", file=sys.stderr)
        return 1

    excel_files = find_excel_files(input_dir)
    if not excel_files:
        print(f"[error] No Excel config files found under: {input_dir}", file=sys.stderr)
        print("[hint] Put one or more .xlsx files under docs/configs before running this skill.", file=sys.stderr)
        return 1

    command = [
        sys.executable,
        str(MODULE_SCRIPT),
        str(input_dir),
        "--output-dir",
        str(output_dir),
        "--clean",
    ]

    print(f"[repo]   {repo_root}")
    print(f"[input]  {input_dir}")
    print(f"[output] {output_dir}")
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
