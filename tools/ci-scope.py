#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Select CI build domains conservatively; shared quality checks always run."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def build_scope(paths: list[str]) -> tuple[bool, bool]:
    client = server = False
    for path in paths:
        if path.endswith(".md") or path in (".gitignore", ".clang-format", "LICENSE"):
            continue
        if path.startswith("apps/client-qt/"):
            client = True
        else:
            # Server changes need the Qt integration tests too. Tooling, schema,
            # packaging, workflow, and unknown paths conservatively build both.
            client = server = True
    return client, server


def changed_paths(root: Path, base: str, head: str) -> list[str]:
    if not base or not base.strip("0"):
        raise ValueError("no usable comparison base")
    commits = []
    for revision in (base, head):
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"],
            check=True, capture_output=True, text=True,
        )
        commits.append(result.stdout.strip())
    # Disable rename detection: moving a file out of a build domain must still
    # include the old path, not just a harmless-looking new documentation path.
    result = subprocess.run(
        ["git", "-C", str(root), "diff", "--no-renames", "--name-only", "-z", *commits, "--"],
        check=True, capture_output=True,
    )
    return [name.decode("utf-8") for name in result.stdout.split(b"\0") if name]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--force-all", action="store_true")
    args = parser.parse_args()
    client = server = True
    if not args.force_all:
        try:
            client, server = build_scope(changed_paths(args.root, args.base, args.head))
        except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError):
            print("Cannot establish CI change scope; running both build domains.", file=sys.stderr)
    print(f"client={str(client).lower()}")
    print(f"server={str(server).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
