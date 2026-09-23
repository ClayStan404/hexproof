#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
client_build_dir="${HEXPROOF_CLIENT_BUILD_DIR:-$repo_root/build/client-qt}"
server_binary="${HEXPROOF_SERVER_BINARY_PATH:-$repo_root/build/server/hexproof-server}"
run_ctest=1
run_race=1
scope=all
clean_build=0
format_base=""
started_at=$SECONDS

usage() {
    cat <<'EOF'
Usage: ./tools/verify.sh [options]

Run incremental, non-interactive checks without touching a remote server.
Native visual verification is separate and should be used when the task needs it.

Options:
  --scope SCOPE       all (default), static, client, or server. Every scope runs
                      shared static checks. Client tests build a local server
                      for integration tests, but do not run the Go test suite.
  --quick             Skip CTest and Go race tests; keep builds and other gates.
  --clean             Force clean rebuilds and uncached Go tests (opt-in).
  --format-base REF   Check changed C/C++ lines against REF (default: working
                      tree against HEAD, or the latest commit when clean).
  -h, --help          Show this help.

Optional environment variables:
  HEXPROOF_CLIENT_BUILD_DIR    Client build directory.
  HEXPROOF_SERVER_BINARY_PATH Server output used by CTest integration tests.
EOF
}

while (($# > 0)); do
    case "$1" in
        --scope)
            if (($# < 2)); then
                echo "--scope requires all, static, client, or server." >&2
                exit 2
            fi
            scope="$2"
            case "$scope" in
                all|static|client|server) ;;
                *) echo "Invalid verification scope: $scope" >&2; exit 2 ;;
            esac
            shift
            ;;
        --clean)
            clean_build=1
            ;;
        --quick)
            run_ctest=0
            run_race=0
            ;;
        --format-base)
            if (($# < 2)); then
                echo "--format-base requires a Git revision." >&2
                exit 2
            fi
            format_base="$2"
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

cd "$repo_root"
build_client=0
build_server=0
test_server=0
if [[ "$scope" == all || "$scope" == client ]]; then
    build_client=1
    if ((run_ctest)); then
        build_server=1
    fi
fi
if [[ "$scope" == all || "$scope" == server ]]; then
    build_server=1
    test_server=1
fi

source_version="$(
    sed -nE \
        's/^[[:space:]]*set\(HEXPROOF_VERSION[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*\)[[:space:]]*$/\1/p' \
        apps/client-qt/CMakeLists.txt
)"
if [[ ! "$source_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Could not read the source version from apps/client-qt/CMakeLists.txt." >&2
    exit 1
fi

section() {
    printf '\n==> %s\n' "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 127
    fi
}

check_clang_format() {
    local output
    local -a command=(git clang-format --diff --extensions c,cpp,h)
    local -a source_paths=(apps/client-qt tools/ui-automation/x11)

    if [[ -n "$format_base" ]]; then
        git rev-parse --verify --quiet "${format_base}^{commit}" >/dev/null || {
            echo "Unknown format base: $format_base" >&2
            return 1
        }
        command+=("$format_base")
    elif ! git diff --quiet HEAD -- "${source_paths[@]}"; then
        command+=(HEAD)
    elif git rev-parse --verify --quiet HEAD^ >/dev/null; then
        command+=(HEAD^ HEAD)
    else
        command+=(HEAD)
    fi
    command+=(-- "${source_paths[@]}")

    output="$("${command[@]}" 2>&1)" || {
        printf '%s\n' "$output" >&2
        return 1
    }
    case "$output" in
        ""|"no modified files to format"|"clang-format did not modify any files")
            ;;
        *)
            printf '%s\n' "$output" >&2
            echo "Changed C/C++ lines must be clang-formatted." >&2
            return 1
            ;;
    esac

    while IFS= read -r -d '' file; do
        clang-format --dry-run --Werror "$file"
    done < <(
        git ls-files --others --exclude-standard -z -- \
            'apps/client-qt/*.c' 'apps/client-qt/*.cpp' 'apps/client-qt/*.h' \
            'apps/client-qt/**/*.c' 'apps/client-qt/**/*.cpp' 'apps/client-qt/**/*.h' \
            'tools/ui-automation/x11/*.c' 'tools/ui-automation/x11/*.cpp' 'tools/ui-automation/x11/*.h'
    )
}

required_commands=(git python3 rg clang-format git-clang-format)
if ((build_client)); then
    required_commands+=(cmake ninja)
    if ((run_ctest)); then
        required_commands+=(ctest)
    fi
fi
if ((build_server)); then
    required_commands+=(go)
fi
if ((test_server)); then
    required_commands+=(gofmt)
fi
for command in "${required_commands[@]}"; do
    require_command "$command"
done

section "Static quality gates"
check_clang_format
while IFS= read -r -d '' script; do
    # bash -n accepts only one script; later arguments would not be checked.
    bash -n "$script"
done < <(git ls-files -co --exclude-standard -z -- '*.sh')
./tools/check-license-headers.sh
./tools/check-qml-text-safety.sh
python3 tools/check-protocol-parity.py
python3 tools/check-i18n.py --strict
python3 tools/check-module-size.py
python3 -m unittest discover -s tools/tests

go_test_flags=()
go_build_flags=()
client_build_flags=()
if ((clean_build)); then
    go_test_flags+=(-count=1)
    go_build_flags+=(-a)
    client_build_flags+=(--clean-first)
fi

if ((test_server)); then
    section "Go formatting"
    go_files="$(cd apps/server && gofmt -l .)"
    if [[ -n "$go_files" ]]; then
        printf 'gofmt required:\n%s\n' "$go_files" >&2
        exit 1
    fi

    section "Go vet and tests"
    (
        cd apps/server
        go vet ./...
        go test "${go_test_flags[@]}" ./...
        if ((run_race)); then
            go test "${go_test_flags[@]}" -race ./internal/room ./internal/server ./internal/tournament ./internal/forgehost ./internal/runtimepkg ./internal/peerlink ./internal/homenode
        else
            echo "Skipping Go race tests (--quick)."
        fi
    )
fi

if ((build_server)); then
    section "Server build"
    mkdir -p "$(dirname "$server_binary")"
    echo "Building server binary: $server_binary"
    (
        cd apps/server
        CGO_ENABLED=0 go build "${go_build_flags[@]}" -trimpath \
            -ldflags "-X hexproof/server/internal/buildinfo.Version=$source_version" \
            -o "$server_binary" ./cmd/hexproof-server
    )
    server_version_output="$("$server_binary" -version)"
    printf '%s\n' "$server_version_output"
    if [[ "$server_version_output" != "hexproof-server $source_version" ]]; then
        echo "Server build version does not match source version $source_version." >&2
        exit 1
    fi
fi

if ((build_client)); then
    section "Client configure and build"
    cmake -S apps/client-qt -B "$client_build_dir" -G Ninja \
        -DHEXPROOF_VERSION_OVERRIDE=
    cmake --build "$client_build_dir" "${client_build_flags[@]}"

    client_version_output="$(
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
            "$client_build_dir/hexproof" --version
    )"
    printf '%s\n' "$client_version_output"
    if [[ "$client_version_output" != "Hexproof $source_version" ]]; then
        echo "Client build version does not match source version $source_version." >&2
        exit 1
    fi

    if ((run_ctest)); then
        section "Client CTest"
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
            HEXPROOF_SERVER_BINARY="$server_binary" \
            ctest --test-dir "$client_build_dir" --output-on-failure
    else
        echo "Skipping CTest (--quick)."
    fi
fi

elapsed=$((SECONDS - started_at))
printf '\nAll requested checks passed in %dm %ds.\n' \
    "$((elapsed / 60))" "$((elapsed % 60))"
