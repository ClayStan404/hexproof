#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

server_binary="${HEXPROOF_SERVER_BINARY_PATH:-${repo_root}/build/server/hexproof-server}"
java_command="${HEXPROOF_FORGE_JAVA:-java}"
[[ "${server_binary}" == /* ]] || server_binary="${PWD}/${server_binary}"

usage() {
    cat <<'EOF'
Usage: ./tools/run-local-forge-server.sh [--native] [--prepare] [--] [SERVER_ARGS...]

Start the locally built Hexproof server with the prepared Forge runtime.
Arguments are passed directly to hexproof-server. With no arguments, the
server uses its normal 127.0.0.1:57320 default. --prepare builds the local Go
server and prepares the pinned runtime if it is not installed. It does not
install system packages or change any remote service. Only official Forge is
supported; --native is an optional explicit selector. The prepared runtime
is selected by build/forge-native/local-runtime.json unless overridden.
--native and --prepare may appear in either order before server arguments.

Examples:
  ./tools/run-local-forge-server.sh
  ./tools/run-local-forge-server.sh --prepare -port 57321
  ./tools/run-local-forge-server.sh --native --prepare -port 57321
  ./tools/run-local-forge-server.sh -port 57321

Environment overrides:
  HEXPROOF_SERVER_BINARY_PATH  Hexproof server binary.
  HEXPROOF_FORGE_LOCAL_ROOT    Verified official Forge runtime directory.
  HEXPROOF_FORGE_JAVA          Java executable (default: java).
  HEXPROOF_FORGE_SOURCE_DIR    Upstream source checkout used by --prepare.
  HEXPROOF_FORGE_OUTPUT_DIR    Runtime/archive output used by --prepare.
EOF
}

prepare=false
while (($#)); do
    case "$1" in
        --native) shift ;;
        --legacy)
            printf 'The legacy Forge runtime has been retired; use official Forge.\n' >&2
            exit 1 ;;
        --prepare) prepare=true; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

if [[ "${prepare}" == true ]]; then
    if ! command -v go >/dev/null 2>&1; then
        printf 'Missing local server build dependency: go\n' >&2
        exit 1
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf 'Missing native runtime validation dependency: python3\n' >&2
    exit 1
fi
native_args=()
[[ "${prepare}" != true ]] || native_args+=(--prepare)
[[ -z "${HEXPROOF_FORGE_LOCAL_ROOT:-}" ]] || native_args+=(--root "${HEXPROOF_FORGE_LOCAL_ROOT}")
[[ -z "${HEXPROOF_FORGE_SOURCE_DIR:-}" ]] || native_args+=(--source "${HEXPROOF_FORGE_SOURCE_DIR}")
[[ -z "${HEXPROOF_FORGE_OUTPUT_DIR:-}" ]] || native_args+=(--output "${HEXPROOF_FORGE_OUTPUT_DIR}")
runtime_root="$(python3 "${repo_root}/tools/local-forge-runtime.py" "${native_args[@]}")"

if [[ "${prepare}" == true ]]; then
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
if ! command -v "${java_command}" >/dev/null 2>&1; then
    printf 'Forge Java executable was not found: %s\n' "${java_command}" >&2
    exit 1
fi

export HEXPROOF_FORGE_HARNESS="${runtime_root}/forge-harness.jar"
export HEXPROOF_FORGE_HOME="${runtime_root}/forge-gui"
export HEXPROOF_FORGE_JAVA="${java_command}"

printf 'Starting Forge-enabled Hexproof server with official native runtime %s\n' "${runtime_root}"
exec "${server_binary}" "$@"
