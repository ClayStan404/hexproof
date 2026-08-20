#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Enforce ratcheted production-source line budgets."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "tools/module-size-policy.json"
SOURCE_ROOTS = (ROOT / "apps/client-qt", ROOT / "apps/server/internal", ROOT / "tools")


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def excluded(path: str, policy: dict[str, object]) -> bool:
    prefixes = policy.get("excludePrefixes", [])
    return any(path.startswith(str(prefix)) for prefix in prefixes)


def source_files(policy: dict[str, object]) -> list[Path]:
    defaults = policy["defaults"]
    assert isinstance(defaults, dict)
    suffixes = set(defaults)
    result: list[Path] = []
    for source_root in SOURCE_ROOTS:
        for path in source_root.rglob("*"):
            path_string = relative(path)
            if not path.is_file() or path.suffix not in suffixes:
                continue
            if excluded(path_string, policy):
                go_prefix = str(policy.get("includeGoPrefix", ""))
                if path.suffix != ".go" or not path_string.startswith(go_prefix):
                    continue
                if path.name.endswith("_test.go") or "generated" in path.name:
                    continue
            result.append(path)
    return sorted(result)


def line_count(path: Path) -> int:
    with path.open("r", encoding="utf-8") as source:
        return sum(1 for _ in source)


def main() -> int:
    policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    defaults = policy.get("defaults", {})
    overrides = policy.get("overrides", {})
    if not isinstance(defaults, dict) or not isinstance(overrides, dict):
        print("module-size policy must define object defaults and overrides", file=sys.stderr)
        return 2

    problems: list[str] = []
    checked = 0
    for path in source_files(policy):
        path_string = relative(path)
        limit = overrides.get(path_string, defaults.get(path.suffix))
        if not isinstance(limit, int) or limit <= 0:
            problems.append(f"{path_string}: missing positive line budget")
            continue
        count = line_count(path)
        checked += 1
        if count > limit:
            problems.append(f"{path_string}: {count} lines exceeds budget {limit}")

    stale = sorted(set(overrides) - {relative(path) for path in source_files(policy)})
    problems.extend(f"{path}: stale policy override" for path in stale)
    if problems:
        print("module-size policy failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "Extract a cohesive module and lower the ratchet; do not raise a budget for a feature.",
            file=sys.stderr,
        )
        return 1
    print(f"module-size policy ok: {checked} production files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
