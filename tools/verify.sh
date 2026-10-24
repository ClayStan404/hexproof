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
qml_per_file=0
client_targets=()
test_regex=""
focused_client=0
tool_test_patterns=()
format_base=""
started_at=$SECONDS

usage() {
    cat <<'EOF'
Usage: ./tools/verify.sh [options]

Run incremental, non-interactive checks without touching a remote server.
Native visual verification is separate and should be used when the task needs it.

Options:
  --scope SCOPE       all (default), static, client, or server. Every scope runs
                      shared static checks; all/static run all tool tests.
                      Client tests build a local server
                      for integration tests, but do not run the Go test suite.
  --quick             For client builds, build only the application target;
                      skip CTest and Go race tests.
  --clean             Force clean rebuilds and uncached Go tests (opt-in).
  --qml-per-file      Register every QML test file separately for parallel CTest.
  --target NAME       Build a specific client target (repeatable); requires --tests.
  --tests REGEX       Run matching CTest tests; requires --scope client and --target.
                      These focused options cannot be combined with --quick.
                      Integration labels select a matching local server automatically.
  --tool-tests GLOB   Run selected tool tests (repeatable, e.g. test_ci_scope.py).
                      Only for scoped checks; complete all scope stays complete.
  --format-base REF   Check changed C/C++ lines against REF (default: working
                      tree against HEAD, or the latest commit when clean).
  -h, --help          Show this help.

Optional environment variables:
  HEXPROOF_CLIENT_BUILD_DIR    Client build directory.
  HEXPROOF_SERVER_BINARY_PATH Server output used by CTest integration tests.
  CTEST_PARALLEL_LEVEL        Maximum concurrent CTest tasks (for example 2).
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
        --qml-per-file)
            qml_per_file=1
            ;;
        --target)
            if (($# < 2)) || [[ ! "$2" =~ ^[[:alnum:]_][[:alnum:]_.+-]*$ ]]; then
                echo "--target requires a CMake target name." >&2
                exit 2
            fi
            client_targets+=("$2")
            shift
            ;;
        --tests)
            if (($# < 2)) || [[ -z "$2" || -n "$test_regex" ]]; then
                echo "--tests requires one nonempty CTest regular expression." >&2
                exit 2
            fi
            test_regex="$2"
            shift
            ;;
        --tool-tests)
            if (($# < 2)) || [[ "$2" != test_*.py || "$2" == */* ]]; then
                echo "--tool-tests requires a test_*.py filename or glob." >&2
                exit 2
            fi
            tool_test_patterns+=("$2")
            shift
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
if ((${#client_targets[@]})) || [[ -n "$test_regex" ]]; then
    if [[ "$scope" != client || -z "$test_regex" ]] ||
       ((${#client_targets[@]} == 0 || !run_ctest)); then
        echo "Focused checks require --scope client, --target and --tests, without --quick." >&2
        exit 2
    fi
    focused_client=1
fi
if [[ "$scope" == all ]] && ((${#tool_test_patterns[@]})); then
    echo "Use a scoped check to select tool tests; all scope always runs the full suite." >&2
    exit 2
fi
for pattern in "${tool_test_patterns[@]}"; do
    if ! compgen -G "$repo_root/tools/tests/$pattern" >/dev/null; then
        echo "No tool tests match: $pattern" >&2
        exit 2
    fi
done
build_client=0
build_server=0
test_server=0
if [[ "$scope" == all || "$scope" == client ]]; then
    build_client=1
    if ((run_ctest && !focused_client)); then
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
    local -a command=(git clang-format --diff --extensions 'c,cpp,h')
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

required_commands=(git python3 rg clang-format git-clang-format shellcheck)
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
./tools/check-shell-scripts.sh
./tools/check-license-headers.sh
./tools/check-qml-text-safety.sh
python3 tools/check-qml-resources.py
python3 tools/check-protocol-parity.py
python3 tools/check-i18n.py --strict
python3 tools/check-module-size.py
if ((${#tool_test_patterns[@]})); then
    for pattern in "${tool_test_patterns[@]}"; do
        python3 -m unittest discover -s tools/tests -p "$pattern"
    done
elif [[ "$scope" == all || "$scope" == static ]]; then
    python3 -m unittest discover -s tools/tests
else
    echo "Tool tests are separate from this application scope; use --tool-tests for affected tools."
fi

go_test_flags=()
go_build_flags=()
client_build_flags=()
if ((clean_build)); then
    go_test_flags+=(-count=1)
    go_build_flags+=(-a)
    client_build_flags+=(--clean-first)
fi

configure_client() {
    local -a flags=(-DHEXPROOF_VERSION_OVERRIDE=)
    if ((qml_per_file)); then
        flags+=(-DHEXPROOF_QML_TESTS_PER_FILE=ON)
    fi
    cmake -S apps/client-qt -B "$client_build_dir" -G Ninja "${flags[@]}"
}

if ((focused_client)); then
    section "Select focused client checks"
    configure_client
    # Use CTest's selected names and labels, never infer dependencies from regex text.
    selection="$(ctest --test-dir "$client_build_dir" --show-only=json-v1 -R "$test_regex" |
        python3 -c '
import json
import sys
tests = json.load(sys.stdin)["tests"]
if not tests:
    sys.exit("No CTest tests match the requested regular expression.")
print("Focused CTest selection: " + ", ".join(test["name"] for test in tests), file=sys.stderr)
needs_server = any("integration" in prop["value"]
                   for test in tests for prop in test.get("properties", [])
                   if prop["name"] == "LABELS")
needs_catalog = any(test["name"] == "limited-catalog-builder" for test in tests)
print(int(needs_server), int(needs_catalog))
')"
    read -r build_server build_catalog <<< "$selection"
    if ((build_server)); then
        require_command go
    fi
    if ((build_catalog)) && [[ " ${client_targets[*]} " != *" hexproof_card_database_builder "* ]]; then
        client_targets+=(hexproof_card_database_builder)
    fi
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
            go test "${go_test_flags[@]}" -race ./internal/room ./internal/server ./internal/tournament ./internal/forgehost ./internal/runtimepkg ./internal/peerlink ./internal/homenode ./internal/accounts ./internal/cluster ./internal/syncutil ./internal/feedback
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
    if ((!focused_client)); then
        configure_client
    fi
    if ((!run_ctest)); then
        client_targets=(hexproof)
    fi
    if ((${#client_targets[@]})); then
        client_build_flags+=(--target "${client_targets[@]}")
    fi
    cmake --build "$client_build_dir" "${client_build_flags[@]}"

    check_client_version=$((!focused_client))
    for target in "${client_targets[@]}"; do
        if [[ "$target" == hexproof ]]; then
            check_client_version=1
        fi
    done
    if ((check_client_version)); then
        client_version_output="$(
            QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
                "$client_build_dir/hexproof" --version
        )"
        printf '%s\n' "$client_version_output"
        if [[ "$client_version_output" != "Hexproof $source_version" ]]; then
            echo "Client build version does not match source version $source_version." >&2
            exit 1
        fi
    fi

    if ((run_ctest)); then
        section "Client CTest"
        ctest_flags=(--output-on-failure --no-tests=error)
        if ((focused_client)); then
            ctest_flags+=(-R "$test_regex")
        else
            # The catalog builder is intentionally excluded from normal app builds.
            cmake --build "$client_build_dir" --target hexproof_card_database_builder
        fi
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
            HEXPROOF_SERVER_BINARY="$server_binary" \
            ctest --test-dir "$client_build_dir" "${ctest_flags[@]}"
    else
        echo "Skipping CTest (--quick)."
    fi
fi

elapsed=$((SECONDS - started_at))
if ((focused_client)); then
    echo "Focused client checks only; the complete application/release suite was not run."
fi
printf '\nAll requested checks passed in %dm %ds.\n' \
    "$((elapsed / 60))" "$((elapsed % 60))"
