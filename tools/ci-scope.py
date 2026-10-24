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

# These utilities are covered by static checks and the tool suite. New tools
# must be classified explicitly; an unfamiliar generator may affect both apps.
TOOL_ONLY_PATHS = frozenset({
    "tools/benchmark-control-plane.py",
    "tools/check-i18n.py",
    "tools/check-license-headers.py",
    "tools/check-license-headers.sh",
    "tools/check-module-size.py",
    "tools/check-qml-resources.py",
    "tools/check-qml-text-safety.py",
    "tools/check-qml-text-safety.sh",
    "tools/check-shell-scripts.sh",
    "tools/export-public-tree.sh",
    "tools/feedback-ai.py",
    "tools/module-size-policy.json",
    "tools/multica-removal.py",
    "tools/package-home-node.py",
    "tools/public-content.py",
    "tools/public_export_policy.json",
    "tools/public_source_export.py",
    "tools/publish-public-source.py",
    "tools/release-verification.py",
    "tools/run-multiclient.sh",
    "tools/smoke-home-node.py",
    "tools/write-feedback-config.py",
    "tools/write-release-compatibility.py",
    "tools/write-server-directory.py",
})


def tool_only_path(path: str) -> bool:
    return path in TOOL_ONLY_PATHS or (
        Path(path).parent.as_posix() == "tools/tests"
        and Path(path).name.startswith("test_") and path.endswith(".py")
        and "forge" not in Path(path).name.lower()
        and path != "tools/tests/test_ci_scope.py")


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
        if path.startswith(("tools/ui-automation/", "tools/card-database-builder/")):
            return (path.startswith("tools/ui-automation/fixtures/forge")
                    or "forge" in Path(path).name.lower())
        return not tool_only_path(path)
    # Native sources, shared protocol/fixtures and build/workflow changes can
    # affect the real boundary. Unknown domains fail toward the engine check.
    return True


def build_scope(paths: list[str]) -> tuple[bool, bool, bool]:
    client = server = forge = False
    for path in paths:
        if path.endswith(".md") or path in (".gitignore", ".clang-format", "LICENSE"):
            continue
        # These tools are exercised by the tool suite, not application builds.
        # Keep real build/code generators and engine fixtures in their domains.
        if path.startswith(("deploy/", ".github/screenshots/")):
            continue
        if tool_only_path(path):
            continue
        if path.startswith(".github/workflows/") and path != ".github/workflows/ci.yml":
            continue
        forge = forge or forge_path(path)
        if path.startswith("apps/client-qt/"):
            client = True
        else:
            # Server, shared build inputs and unknown paths keep integration coverage.
            client = server = True
    return client, server, forge


def full_checks(event: str, repository: str, head_repository: str) -> bool:
    """Internal development is verified locally; public/external PRs remain independent."""
    if event == "push":
        return False
    if event == "pull_request":
        return (repository != "ClayStan404/hexproof-private"
                or head_repository != repository)
    # Local scope queries, manual CI and unknown events retain full verification.
    return True


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
    parser.add_argument("--event", default="")
    parser.add_argument("--repository", default="")
    parser.add_argument("--head-repository", default="")
    args = parser.parse_args()
    client = server = forge = True
    full = args.force_all or full_checks(args.event, args.repository, args.head_repository)
    if not full:
        client = server = forge = False
    elif not args.force_all:
        try:
            client, server, forge = build_scope(changed_paths(args.root, args.base, args.head))
        except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError):
            print("Cannot establish CI change scope; running all verification domains.", file=sys.stderr)
    print(f"client={str(client).lower()}")
    print(f"server={str(server).lower()}")
    print(f"forge={str(forge).lower()}")
    print(f"full={str(full).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
