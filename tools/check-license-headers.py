#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check first-party source headers, not ignored build output or vendor licenses."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = ("apps", "packaging", "tools", ".github", "deploy")
EXCLUDED_PARTS = {"build", "__pycache__", "third_party", "vendor", ".venv"}
SUFFIXES = {".c", ".cpp", ".go", ".h", ".qml", ".py", ".sh", ".ps1", ".cmake",
            ".service", ".timer", ".yml", ".yaml"}


def source_files(root: Path) -> list[Path]:
    try:
        probe = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True)
    except FileNotFoundError:
        probe = None
    if probe is not None and probe.returncode == 0 and Path(probe.stdout.strip()).resolve() == root.resolve():
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others",
             "--exclude-standard", "--", *SOURCE_ROOTS, ".clang-format"],
            check=True, capture_output=True,
        )
        paths = {root / name.decode("utf-8") for name in result.stdout.split(b"\0") if name}
    else:
        # Source archives have no index. Keep the same first-party boundaries.
        paths = {path for name in SOURCE_ROOTS for path in (root / name).rglob("*")}
        paths.add(root / ".clang-format")
    return sorted(path for path in paths if path.is_file() and not path.is_symlink()
                  and not (set(path.relative_to(root).parts) & EXCLUDED_PARTS)
                  and not path.is_relative_to(root / "apps/server/data")
                  and (path.suffix in SUFFIXES or path.name in ("CMakeLists.txt", ".clang-format")
                       or path.name.endswith(".service.in")))


def leading_header(source: str, path: Path) -> str:
    """Read leading comments/docstrings until code, without a line-count limit."""
    source = source.lstrip("\ufeff")
    hash_style = path.suffix not in {".c", ".cpp", ".go", ".h", ".qml"}
    fragments = []
    while source:
        source = source.lstrip()
        if source.startswith("#!") or (hash_style and source.startswith("#")):
            bracket = re.match(r"#\[(=*)\[", source) if path.suffix == ".cmake" or path.name == "CMakeLists.txt" else None
            if bracket:
                end_marker = "]" + bracket[1] + "]"
                end = source.find(end_marker, bracket.end())
                if end < 0:
                    break
                end += len(end_marker)
            else:
                end = source.find("\n")
                end = len(source) if end < 0 else end + 1
        elif not hash_style and source.startswith("//"):
            end = source.find("\n")
            end = len(source) if end < 0 else end + 1
        else:
            markers = [("/*", "*/")] if not hash_style else []
            if path.suffix == ".ps1":
                markers.append(("<#", "#>"))
            if path.suffix == ".py":
                markers.extend([('"""', '"""'), ("'''", "'''")])
            pair = next((pair for pair in markers if source.startswith(pair[0])), None)
            if pair is None:
                break
            end = source.find(pair[1], len(pair[0]))
            if end < 0:
                break
            end += len(pair[1])
        fragments.append(source[:end])
        source = source[end:]
    return "\n".join(fragments)


def check_header(path: Path) -> list[str]:
    header = leading_header(path.read_text(encoding="utf-8"), path)
    problems = []
    if not re.search(r"SPDX-License-Identifier:\s*GPL-3\.0-or-later(?:\s|$)", header):
        problems.append("missing GPL-3.0-or-later SPDX identifier in the leading header")
    if not re.search(r"SPDX-FileCopyrightText:\s*\S", header):
        problems.append("missing SPDX copyright in the leading header")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    root = parser.parse_args().root.resolve()
    try:
        paths = source_files(root)
        if not paths:
            raise ValueError("no first-party sources found")
        problems = [f"{path.relative_to(root)}: {problem}"
                    for path in paths for problem in check_header(path)]
    except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"License header check failed: {error}", file=sys.stderr)
        return 2
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"License headers ok: {len(paths)} first-party sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
