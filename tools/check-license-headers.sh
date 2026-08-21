#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_dirs=(apps packaging tools .github)
if [[ -d deploy ]]; then
    source_dirs+=(deploy)
fi

failed=0
while IFS= read -r -d '' file; do
    case "$file" in
        *.c|*.cpp|*.go|*.h|*.qml|*.sh|*.ps1|*.cmake|*.service|*.yml|*.yaml|*/CMakeLists.txt|.clang-format)
            ;;
        *)
            continue
            ;;
    esac

    header="$(head -n 5 "$file")"
    if ! grep -Fq "SPDX-License-Identifier: GPL-2.0-only" <<<"$header"; then
        echo "missing GPL-2.0-only SPDX header: $file" >&2
        failed=1
    fi
    if ! grep -Fq "SPDX-FileCopyrightText:" <<<"$header"; then
        echo "missing SPDX copyright header: $file" >&2
        failed=1
    fi
done < <(
    {
        find "${source_dirs[@]}" -type f -print0
        printf '%s\0' .clang-format
    } | sort -z
)

exit "$failed"
