#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../third_party/forge-runtime/VERSIONS.env
source "${repo_root}/third_party/forge-runtime/VERSIONS.env"

server_binary="${HEXPROOF_SERVER_BINARY_PATH:-${repo_root}/build/server/hexproof-server}"
runtime_root="${HEXPROOF_FORGE_LOCAL_ROOT:-${repo_root}/build/forge-runtime/local-${MANABREW_REVISION}-patch${HEXPROOF_FORGE_PATCH_REVISION}/hexproof-forge-runtime}"
java_command="${HEXPROOF_FORGE_JAVA:-java}"
[[ "${server_binary}" == /* ]] || server_binary="${PWD}/${server_binary}"
[[ "${runtime_root}" == /* ]] || runtime_root="${PWD}/${runtime_root}"

usage() {
    cat <<'EOF'
Usage: ./tools/run-local-forge-server.sh [--prepare] [SERVER_ARGS...]

Start the locally built Hexproof server with the prepared Forge runtime.
Arguments are passed directly to hexproof-server. With no arguments, the
server uses its normal 127.0.0.1:57320 default. --prepare builds the local Go
server and prepares the pinned runtime if it is not installed. It does not
install system packages or change any remote service.

Examples:
  ./tools/run-local-forge-server.sh
  ./tools/run-local-forge-server.sh --prepare -port 57321
  ./tools/run-local-forge-server.sh -port 57321

Environment overrides:
  HEXPROOF_SERVER_BINARY_PATH  Hexproof server binary.
  HEXPROOF_FORGE_LOCAL_ROOT    Extracted hexproof-forge-runtime directory.
  HEXPROOF_FORGE_JAVA          Java executable (default: java).
  HEXPROOF_FORGE_SOURCE_DIR    Upstream source checkout used by --prepare.
  HEXPROOF_FORGE_OUTPUT_DIR    Runtime archive output used by --prepare.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

runtime_matches() {
    local candidate="${1:-${runtime_root}}"
    [[ -f "${candidate}/forge-harness.jar" &&
       -d "${candidate}/forge-gui/res/cardsfolder" &&
       -f "${candidate}/forge-gui/res/languages/en-US.properties" &&
       -f "${candidate}/forge-gui/res/deckgendecks/Standard.raw.dat" ]] &&
        cmp -s "${repo_root}/third_party/forge-runtime/VERSIONS.env" \
            "${candidate}/VERSIONS.env"
}

if [[ "${1:-}" == "--prepare" ]]; then
    shift
    if ! command -v go >/dev/null 2>&1; then
        printf 'Missing local server build dependency: go\n' >&2
        exit 1
    fi
    if ! runtime_matches; then
        if [[ -e "${runtime_root}" || -L "${runtime_root}" ]]; then
            printf 'Existing runtime is incomplete or does not match the pinned revision: %s\n' \
                "${runtime_root}" >&2
            printf 'It has been preserved. Select a fresh HEXPROOF_FORGE_LOCAL_ROOT to prepare a matching runtime.\n' >&2
            exit 1
        fi
        runtime_output="${HEXPROOF_FORGE_OUTPUT_DIR:-${repo_root}/build/forge-runtime}"
        [[ "${runtime_output}" == /* ]] || runtime_output="${PWD}/${runtime_output}"
        # The builder changes directory for Java packaging/probes. Keep an
        # explicitly relative override anchored to the launcher's invocation.
        HEXPROOF_FORGE_OUTPUT_DIR="${runtime_output}" \
            "${repo_root}/third_party/forge-runtime/build.sh"
        runtime_archive="${runtime_output}/hexproof-forge-runtime-${MANABREW_REVISION}.tar.gz"
        mkdir -p -- "$(dirname -- "${runtime_root}")"
        runtime_stage="$(mktemp -d "$(dirname -- "${runtime_root}")/forge-install.XXXXXX")"
        # The archive was just built from pinned sources by our build script.
        # Extract beside the destination, then publish only a complete package.
        tar -xzf "${runtime_archive}" -C "${runtime_stage}"
        if ! runtime_matches "${runtime_stage}/hexproof-forge-runtime"; then
            printf 'Runtime archive failed revision/resource validation; preserving staging at %s\n' \
                "${runtime_stage}" >&2
            exit 1
        fi
        if [[ -e "${runtime_root}" || -L "${runtime_root}" ]]; then
            printf 'Runtime destination appeared during preparation; preserving staging at %s\n' \
                "${runtime_stage}" >&2
            exit 1
        fi
        mv -- "${runtime_stage}/hexproof-forge-runtime" "${runtime_root}"
        rmdir -- "${runtime_stage}"
    fi
    if ! runtime_matches; then
        printf 'Prepared runtime failed revision/resource validation: %s\n' "${runtime_root}" >&2
        exit 1
    fi
    (
        cd "${repo_root}/apps/server"
        CGO_ENABLED=0 go build -o "${server_binary}" ./cmd/hexproof-server
    )
fi

if [[ ! -x "${server_binary}" ]]; then
    printf 'Hexproof server binary is missing or not executable: %s\n' \
        "${server_binary}" >&2
    printf 'Run this script with --prepare to build the server and prepare its runtime.\n' >&2
    exit 1
fi
if ! runtime_matches; then
    printf 'Prepared local Forge runtime is incomplete or does not match the pinned revision: %s\n' \
        "${runtime_root}" >&2
    printf 'Run with --prepare; an existing mismatched directory is preserved, not overwritten.\n' >&2
    exit 1
fi
if ! command -v "${java_command}" >/dev/null 2>&1; then
    printf 'Forge Java executable was not found: %s\n' "${java_command}" >&2
    exit 1
fi

export HEXPROOF_FORGE_HARNESS="${runtime_root}/forge-harness.jar"
export HEXPROOF_FORGE_HOME="${runtime_root}/forge-gui"
export HEXPROOF_FORGE_JAVA="${java_command}"

printf 'Starting Forge-enabled Hexproof server with runtime %s (Hexproof patches %s)\n' \
    "${MANABREW_REVISION}" "${HEXPROOF_FORGE_PATCH_REVISION}"
exec "${server_binary}" "$@"
