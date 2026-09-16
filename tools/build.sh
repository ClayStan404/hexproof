#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scope=all
jobs=""

usage() {
    cat <<'EOF'
Usage: ./tools/build.sh [options]

Incrementally build the client and Go server into build/.

Options:
  --scope SCOPE   all (default), client, or server.
  -j, --jobs N    Parallel client compilation jobs (default: all online CPUs).
  -h, --help      Show this help.

Examples:
  ./tools/build.sh
  ./tools/build.sh --scope client
  ./tools/build.sh --scope server
  ./tools/build.sh --jobs 2

Run ./tools/verify.sh separately for automated checks. Restart running clients
and servers after building to load the new binaries. The prepared Forge runtime
and card database are reused.
EOF
}

while (($# > 0)); do
    case "$1" in
        --scope)
            if (($# < 2)); then
                echo "--scope requires all, client, or server." >&2
                exit 2
            fi
            scope="$2"
            case "$scope" in
                all|client|server) ;;
                *) echo "Invalid build scope: $scope" >&2; exit 2 ;;
            esac
            shift
            ;;
        -j|--jobs)
            if (($# < 2)) || [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "--jobs requires a positive integer." >&2
                exit 2
            fi
            jobs="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 127
    fi
}

if [[ "$scope" != server ]]; then
    require_command cmake
    require_command ninja
    if [[ -z "$jobs" ]]; then
        require_command getconf
        jobs="$(getconf _NPROCESSORS_ONLN)"
    fi
fi
if [[ "$scope" != client ]]; then
    require_command go
fi

cd "$repo_root"
source_version="$(
    sed -nE \
        's/^[[:space:]]*set\(HEXPROOF_VERSION[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*\)[[:space:]]*$/\1/p' \
        apps/client-qt/CMakeLists.txt
)"
if [[ ! "$source_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Could not read the source version from apps/client-qt/CMakeLists.txt." >&2
    exit 1
fi

if [[ "$scope" != client ]]; then
    printf '\n==> Building Go server %s\n' "$source_version"
    mkdir -p build/server
    (
        cd apps/server
        CGO_ENABLED=0 go build -trimpath \
            -ldflags "-X hexproof/server/internal/buildinfo.Version=$source_version" \
            -o "$repo_root/build/server/hexproof-server" ./cmd/hexproof-server
    )
fi

if [[ "$scope" != server ]]; then
    printf '\n==> Building client %s (%s parallel jobs)\n' "$source_version" "$jobs"
    cmake -S apps/client-qt -B build/client-qt -G Ninja \
        -DHEXPROOF_VERSION_OVERRIDE=
    cmake --build build/client-qt --target hexproof --parallel "$jobs"
fi

printf '\nBuild completed successfully.\n'
if [[ "$scope" != server ]]; then
    printf 'Client: %s/build/client-qt/hexproof\n' "$repo_root"
fi
if [[ "$scope" != client ]]; then
    printf 'Server: %s/build/server/hexproof-server\n' "$repo_root"
fi
printf 'Restart the corresponding running programs to load the new build.\n'
