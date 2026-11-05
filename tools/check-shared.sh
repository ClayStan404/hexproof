#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

# Shared check definitions; callers own formatting and verification scope.
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

case "${1:-}" in
    static)
        if (($# != 1)); then
            echo "Usage: tools/check-shared.sh static | race [go test flags...]" >&2
            exit 2
        fi
        while IFS= read -r -d '' script; do
            # bash -n accepts only one script; later arguments are not checked.
            bash -n "$script"
        done < <(git ls-files -co --exclude-standard -z -- '*.sh')
        ./tools/check-shell-scripts.sh
        ./tools/check-license-headers.sh
        ./tools/check-qml-text-safety.sh
        python3 tools/check-qml-resources.py
        python3 tools/check-protocol-parity.py
        python3 tools/check-i18n.py --strict
        python3 tools/check-module-size.py
        ;;
    race)
        shift
        cd apps/server
        exec go test "$@" -race \
            ./internal/room ./internal/server ./internal/tournament \
            ./internal/forgehost ./internal/runtimepkg ./internal/peerlink \
            ./internal/homenode ./internal/accounts ./internal/cluster \
            ./internal/syncutil ./internal/feedback
        ;;
    *)
        echo "Usage: tools/check-shared.sh static | race [go test flags...]" >&2
        exit 2
        ;;
esac
