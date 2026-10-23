#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# != 1 ]]; then
    printf 'Usage: %s /absolute/path/to/empty-output-directory\n' "$0" >&2
    exit 2
fi

# This compatibility entry point retains the HEAD/exported-path dirty guard.
# Immutable automation calls the trusted Python exporter with an exact commit.
exec python3 "${repo_root}/tools/public_source_export.py" \
    --repo "${repo_root}" --head-clean --target "$1" \
    --policy "${repo_root}/tools/public_export_policy.json"
