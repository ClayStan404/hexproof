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


def forge_path(path: str) -> bool:
    if path.startswith("apps/server/"):
        return path.startswith(("apps/server/internal/rulesengine/", "apps/server/internal/server/",
                                "apps/server/internal/room/", "apps/server/internal/protocol/",
                                "apps/server/internal/forgehost/", "apps/server/internal/runtimepkg/",
                                "apps/server/internal/forgediag/", "apps/server/internal/rulesinput/",
                                "apps/server/internal/peerlink/", "apps/server/internal/limited/",
                                "apps/server/internal/tournament/", "apps/server/cmd/hexproof-forge-host/",
                                "apps/server/cmd/hexproof-server/")) or path in (
                                    "apps/server/go.mod", "apps/server/go.sum")
    if path.startswith("apps/client-qt/"):
        name = Path(path).name.lower()
        return ("forge" in name or "rules" in name
                or name.startswith(("roomclient", "roomsession", "gamesession", "tournamentsession",
                                    "limitedsession", "protocolsession", "wsclient", "table"))
                or path.startswith("apps/client-qt/src/protocol/")
                or path == "apps/client-qt/CMakeLists.txt")
    if path.startswith("tools/"):
        return (path.startswith(("tools/forge-", "tools/ui-automation/fixtures/forge"))
                or "forge" in Path(path).name.lower()
                or path in ("tools/ci-scope.py", "tools/verify.sh", "tools/tests/test_ci_scope.py"))
    # Native sources, shared protocol/fixtures and build/workflow changes can
    # affect the real boundary. Unknown domains fail toward the engine check.
    return True


def build_scope(paths: list[str]) -> tuple[bool, bool, bool]:
    client = server = forge = False
    for path in paths:
        if path.endswith(".md") or path in (".gitignore", ".clang-format", "LICENSE"):
            continue
        forge = forge or forge_path(path)
        if path.startswith("apps/client-qt/"):
            client = True
        else:
            # Server changes need the Qt integration tests too. Tooling, schema,
            # packaging, workflow, and unknown paths conservatively build both.
            client = server = True
    return client, server, forge


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
    client = server = forge = True
    if not args.force_all:
        try:
            client, server, forge = build_scope(changed_paths(args.root, args.base, args.head))
        except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError):
            print("Cannot establish CI change scope; running all verification domains.", file=sys.stderr)
    print(f"client={str(client).lower()}")
    print(f"server={str(server).lower()}")
    print(f"forge={str(forge).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
