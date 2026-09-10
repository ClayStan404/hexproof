#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Report source-size review hints; line counts alone never fail a build."""

from __future__ import annotations

import fnmatch
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "tools/module-size-policy.json"
SOURCE_ROOTS = (ROOT / "apps/client-qt", ROOT / "apps/server", ROOT / "tools")


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
            if excluded(path_string, policy) or any(
                part in ("build", "vendor", "third_party", "__pycache__")
                for part in Path(path_string).parts
            ):
                continue
            if path.name.endswith("Generated.h"):
                continue
            result.append(path)
    return sorted(result)


def line_count(path: Path) -> int:
    with path.open("r", encoding="utf-8") as source:
        return sum(1 for _ in source)


def limit_for(path_string: str, suffix: str, policy: dict) -> object:
    overrides = policy.get("overrides", {})
    if path_string in overrides:
        return overrides[path_string]
    for rule in policy.get("pathRules", []):
        if fnmatch.fnmatch(path_string, rule.get("glob", "")):
            return rule.get("limit")
    limit = policy.get("defaults", {}).get(suffix)
    if isinstance(limit, int) and (
        "/tests/" in path_string or path_string.endswith("_test.go")
    ):
        limit = int(limit * policy.get("testMultiplier", 1))
    return limit


def main() -> int:
    try:
        policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"Cannot read module-size policy: {error}", file=sys.stderr)
        return 2
    if not isinstance(policy, dict):
        print("module-size policy must be an object", file=sys.stderr)
        return 2
    defaults = policy.get("defaults", {})
    overrides = policy.get("overrides", {})
    rules = policy.get("pathRules", [])
    prefixes = policy.get("excludePrefixes", [])
    multiplier = policy.get("testMultiplier", 1)
    if (not isinstance(defaults, dict) or not defaults or not isinstance(overrides, dict)
            or not isinstance(rules, list) or not isinstance(multiplier, (int, float))
            or isinstance(multiplier, bool) or not 1 <= multiplier <= 10):
        print("Invalid module-size defaults, overrides, path rules, or test multiplier", file=sys.stderr)
        return 2
    if not isinstance(prefixes, list) or any(not isinstance(prefix, str) for prefix in prefixes):
        print("module-size excludePrefixes must be a list of strings", file=sys.stderr)
        return 2

    limits = list(defaults.values()) + list(overrides.values())
    for rule in rules:
        if not isinstance(rule, dict) or not isinstance(rule.get("glob"), str):
            print("module-size path rules need a glob and positive threshold", file=sys.stderr)
            return 2
        limits.append(rule.get("limit"))
    if any(type(value) is not int or value <= 0 for value in limits):
        print("module-size review thresholds must be positive integers", file=sys.stderr)
        return 2

    problems: list[str] = []
    hints: list[str] = []
    checked = 0
    paths = source_files(policy)
    for path in paths:
        path_string = relative(path)
        limit = limit_for(path_string, path.suffix, policy)
        if not isinstance(limit, int) or limit <= 0:
            problems.append(f"{path_string}: missing positive review threshold")
            continue
        try:
            count = line_count(path)
        except (OSError, UnicodeError) as error:
            problems.append(f"{path_string}: {error}")
            continue
        checked += 1
        if count > limit:
            hints.append(f"{path_string}: {count} lines (review at {limit})")

    stale = sorted(set(overrides) - {relative(path) for path in paths})
    problems.extend(f"{path}: stale policy override" for path in stale)
    if problems:
        print("module-size policy failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 2
    if hints:
        print("Module-size review hints (non-blocking):")
        for hint in hints:
            print(f"  - {hint}")
        print("Review responsibilities, dependencies, and tests; do not split solely to reduce lines.")
    print(f"module-size review complete: {checked} source files, {len(hints)} advisory hints")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
