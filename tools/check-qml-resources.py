#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check that every client QML file is packaged into the application resources.

QML tests import the source directory, so a component missing from the
resource list passes them and then fails to load in the built client.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / "apps/client-qt"
ENTRY = re.compile(r"^\s*(qml/\S+\.qml)\)?\s*$", re.M)


def main() -> int:
    listed = set(ENTRY.findall((CLIENT / "CMakeLists.txt").read_text(encoding="utf-8")))
    present = {path.relative_to(CLIENT).as_posix() for path in (CLIENT / "qml").rglob("*.qml")}
    errors = [f"{path}: not listed in apps/client-qt/CMakeLists.txt" for path in sorted(present - listed)]
    errors += [f"{path}: listed in apps/client-qt/CMakeLists.txt but missing" for path in sorted(listed - present)]
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
