#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../third_party/forge-runtime/VERSIONS.env
source "${repo_root}/third_party/forge-runtime/VERSIONS.env"

server_binary="${HEXPROOF_SERVER_BINARY_PATH:-${repo_root}/build/server/hexproof-server}"
runtime_root="${HEXPROOF_FORGE_LOCAL_ROOT:-${repo_root}/build/forge-runtime/local-${MANABREW_REVISION}/hexproof-forge-runtime}"
java_command="${HEXPROOF_FORGE_JAVA:-java}"

usage() {
    cat <<'EOF'
Usage: ./tools/run-local-forge-server.sh [SERVER_ARGS...]

Start the locally built Hexproof server with the prepared Forge runtime.
Arguments are passed directly to hexproof-server. With no arguments, the
server uses its normal 127.0.0.1:57320 default.

Examples:
  ./tools/run-local-forge-server.sh
  ./tools/run-local-forge-server.sh -port 57321

Environment overrides:
  HEXPROOF_SERVER_BINARY_PATH  Hexproof server binary.
  HEXPROOF_FORGE_LOCAL_ROOT    Extracted hexproof-forge-runtime directory.
  HEXPROOF_FORGE_JAVA          Java executable (default: java).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -x "${server_binary}" ]]; then
    printf 'Hexproof server binary is missing or not executable: %s\n' \
        "${server_binary}" >&2
    printf 'Build it first with: (cd apps/server && CGO_ENABLED=0 go build -o ../../build/server/hexproof-server ./cmd/hexproof-server)\n' >&2
    exit 1
fi
if [[ ! -f "${runtime_root}/forge-harness.jar" ||
      ! -d "${runtime_root}/forge-gui/res/cardsfolder" ]]; then
    printf 'Prepared local Forge runtime is incomplete: %s\n' \
        "${runtime_root}" >&2
    printf 'Build and extract the pinned runtime under build/forge-runtime first.\n' >&2
    exit 1
fi
if ! command -v "${java_command}" >/dev/null 2>&1; then
    printf 'Forge Java executable was not found: %s\n' "${java_command}" >&2
    exit 1
fi

export HEXPROOF_FORGE_HARNESS="${runtime_root}/forge-harness.jar"
export HEXPROOF_FORGE_HOME="${runtime_root}/forge-gui"
export HEXPROOF_FORGE_JAVA="${java_command}"

printf 'Starting Forge-enabled Hexproof server with runtime %s\n' \
    "${MANABREW_REVISION}"
exec "${server_binary}" "$@"
