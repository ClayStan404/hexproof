#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate the protocol fixture README against the JSON fixture directory."""

from __future__ import annotations

import fnmatch
import re
from pathlib import Path

_FIXTURE_REFERENCE = re.compile(r"`([^`]*[.]json)`")


def verify_fixture_index(root: Path) -> list[str]:
    fixture_dir = root / "testdata/protocol/v1"
    readme_path = fixture_dir / "README.md"
    fixture_names = sorted(path.name for path in fixture_dir.glob("*.json"))
    readme = readme_path.read_text(encoding="utf-8")
    patterns = sorted(set(_FIXTURE_REFERENCE.findall(readme)))

    problems: list[str] = []
    uncovered = [
        name
        for name in fixture_names
        if not any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns)
    ]
    if uncovered:
        problems.append("protocol fixture README is missing: " + ", ".join(uncovered))

    stale = [
        pattern
        for pattern in patterns
        if not any(fnmatch.fnmatchcase(name, pattern) for name in fixture_names)
    ]
    if stale:
        problems.append(
            "protocol fixture README references missing files: " + ", ".join(stale)
        )
    return problems
