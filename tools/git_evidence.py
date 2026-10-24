#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Read exact local Git evidence without inherited Git redirection or hooks."""

import os
from pathlib import Path
import subprocess


class GitError(ValueError):
    """The checkout cannot provide the required Git identity."""


def git(repo, *args):
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env["GIT_OPTIONAL_LOCKS"] = "0"
    command = ["git", "--no-replace-objects", "--literal-pathspecs", "-c", "core.fsmonitor=false",
               "-c", "core.hooksPath=/dev/null", "-C", str(repo), *args]
    result = subprocess.run(command, env=env, capture_output=True)
    if result.returncode:
        raise GitError(f"Git {args[0]} failed: {result.stderr.decode('utf-8', errors='replace').strip()}")
    return result.stdout


def repo_root(repo):
    return Path(os.fsdecode(git(repo, "rev-parse", "--show-toplevel")).strip()).resolve()


def require_official_origin(repo, repository):
    """Reject other destinations, including rewritten fetch or push URLs."""
    allowed = {f"{prefix}{repository}{suffix}".casefold()
               for prefix in ("https://github.com/", "git@github.com:", "ssh://git@github.com/")
               for suffix in ("", ".git")}
    for options in (("--all",), ("--push", "--all")):
        urls = git(repo, "remote", "get-url", *options, "origin").decode().splitlines()
        if not urls or any(url.casefold() not in allowed for url in urls):
            raise GitError("Origin fetch and push URLs must target the official public repository")
