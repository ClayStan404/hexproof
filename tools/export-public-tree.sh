#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${1:-}"

if [[ -z "${target_dir}" ]]; then
    printf 'Usage: %s /absolute/path/to/empty-output-directory\n' "$0" >&2
    exit 2
fi
if [[ "${target_dir}" != /* ]]; then
    printf 'Output directory must be an absolute path: %s\n' "${target_dir}" >&2
    exit 2
fi
if [[ "${target_dir}" == "${repo_root}" || "${target_dir}" == "${repo_root}/"* ]]; then
    printf 'Output directory must be outside the private working tree.\n' >&2
    exit 2
fi
if [[ -e "${target_dir}" && ! -d "${target_dir}" ]]; then
    printf 'Output path exists and is not a directory: %s\n' "${target_dir}" >&2
    exit 2
fi
if [[ -d "${target_dir}" ]] &&
    [[ -n "$(find "${target_dir}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    printf 'Output directory must be empty: %s\n' "${target_dir}" >&2
    exit 2
fi
if [[ -n "$(git -C "${repo_root}" status --short)" ]]; then
    printf 'Commit or stash private working-tree changes before exporting.\n' >&2
    exit 1
fi

mkdir -p "${target_dir}"

public_paths=(
    .github
    .clang-format
    .gitignore
    LICENSE
    README.md
    THIRD-PARTY-NOTICES.md
    apps
    packaging
    protocol
    testdata
    third_party
    tools
)

git -C "${repo_root}" archive --format=tar HEAD -- \
    "${public_paths[@]}" \
    ':(exclude)tools/tests/test_deploy_script.py' |
    tar -xf - -C "${target_dir}"

printf 'Exported public source from %s to %s\n' \
    "$(git -C "${repo_root}" rev-parse --short HEAD)" "${target_dir}"
