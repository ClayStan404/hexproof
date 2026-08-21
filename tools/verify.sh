#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
client_build_dir="${HEXPROOF_CLIENT_BUILD_DIR:-$repo_root/build/client-qt}"
server_binary="${HEXPROOF_SERVER_BINARY_PATH:-$repo_root/build/server/hexproof-server}"
run_ctest=1
run_race=1
format_base=""
started_at=$SECONDS

usage() {
    cat <<'EOF'
Usage: ./tools/verify.sh [options]

Build and verify the Hexproof client and server without launching the
interactive client or touching a remote server.

Options:
  --quick             Skip CTest and Go race tests; keep builds and other gates.
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
    local -a command=(git clang-format --diff --extensions cpp,h)
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
            'apps/client-qt/*.cpp' 'apps/client-qt/*.h' \
            'apps/client-qt/**/*.cpp' 'apps/client-qt/**/*.h' \
            'tools/ui-automation/x11/*.cpp' 'tools/ui-automation/x11/*.h'
    )
}

for command in cmake ctest git go gofmt ninja python3 rg clang-format git-clang-format; do
    require_command "$command"
done

section "Static quality gates"
check_clang_format
./tools/check-license-headers.sh
./tools/check-qml-text-safety.sh
python3 tools/check-protocol-parity.py
python3 tools/check-i18n.py --strict
python3 tools/check-module-size.py
quality_tests=(
    tools.tests.test_quality_checks
    tools.tests.test_table_architecture
)
if [[ -f tools/tests/test_deploy_script.py ]]; then
    quality_tests+=(tools.tests.test_deploy_script)
fi
python3 -m unittest "${quality_tests[@]}"

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
    go test -count=1 ./...
    if ((run_race)); then
        go test -count=1 -race ./internal/room ./internal/server ./internal/tournament
    else
        echo "Skipping Go race tests (--quick)."
    fi
)

section "Server build"
cmake -E make_directory "$(dirname "$server_binary")"
echo "Building server binary: $server_binary"
(
    cd apps/server
    CGO_ENABLED=0 go build -a -trimpath \
        -ldflags "-X hexproof/server/internal/buildinfo.Version=$source_version" \
        -o "$server_binary" ./cmd/hexproof-server
)
echo "Server build complete: $server_binary"

section "Client configure and build"
cmake -S apps/client-qt -B "$client_build_dir" -G Ninja \
    -DHEXPROOF_VERSION_OVERRIDE=
cmake --build "$client_build_dir" --clean-first

section "Build version verification"
server_version_output="$("$server_binary" -version)"
client_version_output="$(
    QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
        "$client_build_dir/hexproof" --version
)"
printf '%s\n%s\n' "$server_version_output" "$client_version_output"
if [[ "$server_version_output" != "hexproof-server $source_version" ]]; then
    echo "Server build version does not match source version $source_version." >&2
    exit 1
fi
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

elapsed=$((SECONDS - started_at))
printf '\nAll requested checks passed in %dm %ds.\n' \
    "$((elapsed / 60))" "$((elapsed % 60))"
