#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "Required command not found: shellcheck. Install ShellCheck to run shell quality checks." >&2
    exit 127
fi

# Keep the maintained lint scope shared by local, CI, and release checks.
# Private deployment scripts are absent from the public source export.
scripts=(tools/card-database-builder/build-latest.sh)
for script in deploy/deploy-release-server.sh deploy/deploy-forge-runtime.sh deploy/deploy-test-server.sh; do
    if [[ -f "$script" ]]; then
        scripts+=("$script")
    fi
done

exec shellcheck "${scripts[@]}"
