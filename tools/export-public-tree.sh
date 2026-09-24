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
public_paths=(
    .github
    .clang-format
    .gitattributes
    .gitignore
    LICENSE
    README.md
    CHANGELOG.md
    THIRD-PARTY-NOTICES.md
    apps
    docs/guide/README.md
    docs/rules-engine.md
    docs/player-hosted-forge.md
    docs/home-servers.md
    docs/public-content.md
    packaging
    protocol
    testdata
    third_party
    tools
)
# These operator-only tools and tests depend on the private deploy/ tree.
public_paths+=(':(exclude)tools/tests/test_deploy_script.py')
public_paths+=(':(exclude)tools/tests/test_home_deployment.py')
public_paths+=(':(exclude)tools/tests/test_home_rollout.py')
public_paths+=(':(exclude)tools/package-home-node.py')

# The archive reads HEAD, not the working tree. Only changes to exported paths
# can make that snapshot unexpectedly stale; private notes/images are unrelated.
if [[ -n "$(git -C "${repo_root}" status --short --untracked-files=all -- "${public_paths[@]}")" ]]; then
    printf 'Exported paths have uncommitted changes; commit them before exporting HEAD.\n' >&2
    exit 1
fi

mkdir -p "${target_dir}"

git -C "${repo_root}" archive --format=tar HEAD -- \
    "${public_paths[@]}" |
    tar -xf - -C "${target_dir}"

printf 'Exported public source from %s to %s\n' \
    "$(git -C "${repo_root}" rev-parse --short HEAD)" "${target_dir}"
