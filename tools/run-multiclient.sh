#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_name="start"
count=8
binary="$repo_root/build/client-qt/hexproof"
profiles_root="$repo_root/build/multiclient/default"
server_url="ws://127.0.0.1:57320/ws"
name_prefix="Test Player"
template=""
use_template=1
copy_images=0
windowed=0
declare -a client_args=()

usage() {
    cat <<'EOF'
Usage: ./tools/run-multiclient.sh [start|status|stop] [options] [-- CLIENT_ARGS...]

Launch isolated, full Hexproof clients for manual multi-seat testing. Each
client uses its own XDG configuration, application data, cache, log, and
resume credentials. The default command is start.

Options:
  --count N              Number of clients to start (default: 8, maximum: 16).
  --binary PATH          Client binary (default: build/client-qt/hexproof).
  --profiles-root PATH   Persistent test-profile directory
                         (default: build/multiclient/default).
  --template PATH        AppData template containing cards.sqlite, decks.json,
                         images/, and related files. The default is the current
                         Linux Hexproof AppData directory.
  --no-template          Create empty profiles instead of cloning AppData.
  --copy-images          Copy cached image bytes instead of hard-linking the
                         initial image snapshot. Other mutable data is always
                         copied independently.
  --server URL           Custom server endpoint prefilled for every client
                         (default: ws://127.0.0.1:57320/ws).
  --name-prefix TEXT     Initial display-name prefix (default: Test Player).
  --windowed             Start normal windows instead of maximized windows.
  -h, --help             Show this help.

Examples:
  ./tools/run-multiclient.sh start --count 8 --windowed
  ./tools/run-multiclient.sh status
  ./tools/run-multiclient.sh stop

Profiles are initialized only once and are reused on later starts so reconnect
credentials survive. Use another --profiles-root for a fresh test session.
Existing card-art files are hard-linked by default to reduce disk use. Their
directory entries and all metadata remain profile-local, and Hexproof writes
new/replaced images atomically.
EOF
}

if (($# > 0)); then
    case "$1" in
        start|status|stop)
            command_name="$1"
            shift
            ;;
    esac
fi

while (($# > 0)); do
    case "$1" in
        --count)
            (($# >= 2)) || { echo "--count requires a value." >&2; exit 2; }
            count="$2"
            shift
            ;;
        --binary)
            (($# >= 2)) || { echo "--binary requires a path." >&2; exit 2; }
            binary="$2"
            shift
            ;;
        --profiles-root)
            (($# >= 2)) || { echo "--profiles-root requires a path." >&2; exit 2; }
            profiles_root="$2"
            shift
            ;;
        --template)
            (($# >= 2)) || { echo "--template requires a path." >&2; exit 2; }
            template="$2"
            use_template=1
            shift
            ;;
        --no-template)
            template=""
            use_template=0
            ;;
        --copy-images)
            copy_images=1
            ;;
        --server)
            (($# >= 2)) || { echo "--server requires a URL." >&2; exit 2; }
            server_url="$2"
            shift
            ;;
        --name-prefix)
            (($# >= 2)) || { echo "--name-prefix requires text." >&2; exit 2; }
            name_prefix="$2"
            shift
            ;;
        --windowed)
            windowed=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            client_args=("$@")
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "run-multiclient.sh currently supports Linux developer workstations only." >&2
    exit 1
fi
if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count < 1 || count > 16)); then
    echo "--count must be an integer from 1 through 16." >&2
    exit 2
fi
if [[ ! "$server_url" =~ ^wss?://[^[:space:]]+$ ]]; then
    echo "--server must be a ws:// or wss:// URL without spaces." >&2
    exit 2
fi
if [[ -z "${name_prefix//[[:space:]]/}" ]]; then
    echo "--name-prefix must not be empty." >&2
    exit 2
fi

profiles_root="$(realpath -m "$profiles_root")"
binary="$(realpath -m "$binary")"
pid_dir="$profiles_root/pids"

if ((use_template)) && [[ -z "$template" ]]; then
    template="${XDG_DATA_HOME:-$HOME/.local/share}/Hexproof/Hexproof"
fi
if [[ -n "$template" ]]; then
    template="$(realpath -m "$template")"
fi

managed_process() {
    local pid="$1"
    local instance="$2"
    local entry
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null &&
        [[ -r "/proc/$pid/environ" ]] || return 1
    while IFS= read -r -d '' entry; do
        [[ "$entry" == "HEXPROOF_TEST_INSTANCE=$instance" ]] && return 0
    done <"/proc/$pid/environ"
    return 1
}

profile_number() {
    local instance="$1"
    printf '%s' "${instance#client-}"
}

show_status() {
    local found=0
    local pid_file instance pid number
    shopt -s nullglob
    for pid_file in "$pid_dir"/client-*.pid; do
        found=1
        instance="$(basename "$pid_file" .pid)"
        pid="$(<"$pid_file")"
        number="$(profile_number "$instance")"
        if managed_process "$pid" "$instance"; then
            printf '%s running (pid %s, log %s/client-%s/logs/client.log)\n' \
                "$instance" "$pid" "$profiles_root" "$number"
        else
            printf '%s stopped (stale pid file)\n' "$instance"
        fi
    done
    shopt -u nullglob
    if ((found == 0)); then
        echo "No multi-client processes are recorded under $profiles_root."
    fi
}

stop_clients() {
    local found=0
    local pid_file instance pid attempt
    shopt -s nullglob
    for pid_file in "$pid_dir"/client-*.pid; do
        found=1
        instance="$(basename "$pid_file" .pid)"
        pid="$(<"$pid_file")"
        if ! managed_process "$pid" "$instance"; then
            rm -f -- "$pid_file"
            continue
        fi
        echo "Stopping $instance (pid $pid)..."
        kill -TERM "$pid"
        for attempt in {1..50}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "$instance did not stop after 5 seconds; leaving it running." >&2
        else
            rm -f -- "$pid_file"
        fi
    done
    shopt -u nullglob
    if ((found == 0)); then
        echo "No multi-client processes are recorded under $profiles_root."
    fi
}

case "$command_name" in
    status)
        show_status
        exit 0
        ;;
    stop)
        stop_clients
        exit 0
        ;;
esac

if [[ ! -x "$binary" ]]; then
    echo "Client binary is not executable: $binary" >&2
    echo "Build it first with: cmake --build build/client-qt" >&2
    exit 1
fi
if ((use_template)); then
    if [[ ! -d "$template" ]]; then
        echo "AppData template does not exist: $template" >&2
        echo "Use --template PATH or --no-template." >&2
        exit 1
    fi
    case "$template/" in
        "$profiles_root/"*)
            echo "The template must not be inside the profiles root." >&2
            exit 1
            ;;
    esac
fi

mkdir -p "$pid_dir"
start_failed=0

for ((index = 1; index <= count; ++index)); do
    number="$(printf '%02d' "$index")"
    instance="client-$number"
    profile_root="$profiles_root/$instance"
    data_home="$profile_root/data"
    app_data="$data_home/Hexproof/Hexproof"
    config_home="$profile_root/config"
    cache_home="$profile_root/cache"
    log_dir="$profile_root/logs"
    marker="$profile_root/.initialized"
    pid_file="$pid_dir/$instance.pid"
    display_name="$name_prefix $index"

    if [[ -f "$pid_file" ]]; then
        existing_pid="$(<"$pid_file")"
        if managed_process "$existing_pid" "$instance"; then
            echo "$instance is already running (pid $existing_pid)."
            continue
        fi
        rm -f -- "$pid_file"
    fi

    if [[ ! -f "$marker" ]]; then
        if [[ -d "$profile_root" ]] &&
            [[ -n "$(find "$profile_root" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
            echo "Refusing to initialize non-empty profile without marker: $profile_root" >&2
            start_failed=1
            continue
        fi
        mkdir -p "$app_data" "$config_home/Hexproof" "$cache_home" "$log_dir"
        if ((use_template)); then
            echo "Initializing $instance from $template..."
            shopt -s dotglob nullglob
            for source in "$template"/*; do
                name="$(basename "$source")"
                if [[ "$name" == "images" && -d "$source" && $copy_images -eq 0 ]]; then
                    mkdir -p "$app_data/images"
                    cp -al -- "$source/." "$app_data/images/"
                else
                    cp -a --reflink=auto -- "$source" "$app_data/"
                fi
            done
            shopt -u dotglob nullglob
            python3 - "$app_data" "$template" <<'PY'
import json
import os
import pathlib
import sys

destination = pathlib.Path(sys.argv[1])
source_prefix = os.path.normpath(sys.argv[2])
destination_prefix = os.path.normpath(sys.argv[1])


def rewrite(value):
    if isinstance(value, dict):
        return {key: rewrite(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rewrite(item) for item in value]
    if isinstance(value, str):
        normalized = os.path.normpath(value)
        if normalized == source_prefix:
            return destination_prefix
        prefix = source_prefix + os.sep
        if normalized.startswith(prefix):
            return destination_prefix + normalized[len(source_prefix):]
    return value


for path in destination.glob("*.json"):
    try:
        original = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        continue
    updated = rewrite(original)
    if updated == original:
        continue
    temporary = path.with_name(path.name + ".multiclient.tmp")
    temporary.write_text(
        json.dumps(updated, ensure_ascii=False, indent=4) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)
PY
        fi
        printf 'profile=%s\n' "$instance" >"$marker"
    else
        mkdir -p "$config_home" "$cache_home" "$log_dir"
    fi

    python3 - "$config_home/Hexproof/Hexproof.conf" "$display_name" "$server_url" <<'PY'
import configparser
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
config = configparser.ConfigParser(interpolation=None)
config.optionxform = str
if path.exists():
    config.read(path, encoding="utf-8")
if not config.has_section("network"):
    config.add_section("network")
previous_server = config["network"].get("resumeServerUrl", "")
if previous_server and previous_server != sys.argv[3]:
    config.remove_option("network", "resumeToken")
    config.remove_option("network", "resumeLastSeq")
config["network"]["customServerUrl"] = sys.argv[3]
config["network"]["resumeDisplayName"] = sys.argv[2]
config["network"]["resumeServerUrl"] = sys.argv[3]
with path.open("w", encoding="utf-8") as output:
    config.write(output, space_around_delimiters=False)
PY

    log_file="$log_dir/client.log"
    printf '\n[%s] starting %s as %s\n' "$(date --iso-8601=seconds)" "$instance" \
        "$display_name" >>"$log_file"
    launch_args=(--instance-label "$display_name")
    if ((windowed)); then
        launch_args+=(--windowed)
    fi
    launch_args+=("${client_args[@]}")

    nohup env \
        XDG_CONFIG_HOME="$config_home" \
        XDG_DATA_HOME="$data_home" \
        XDG_CACHE_HOME="$cache_home" \
        HEXPROOF_TEST_INSTANCE="$instance" \
        HEXPROOF_TEST_PROFILE_ROOT="$profile_root" \
        "$binary" "${launch_args[@]}" >>"$log_file" 2>&1 </dev/null &
    pid=$!
    printf '%s\n' "$pid" >"$pid_file.tmp"
    mv -f -- "$pid_file.tmp" "$pid_file"
    sleep 0.1
    if managed_process "$pid" "$instance"; then
        echo "Started $instance as '$display_name' (pid $pid)."
    else
        echo "$instance exited during startup; inspect $log_file" >&2
        rm -f -- "$pid_file"
        start_failed=1
    fi
done

echo "Profiles: $profiles_root"
echo "Use './tools/run-multiclient.sh status --profiles-root $profiles_root' to inspect them."
echo "Use './tools/run-multiclient.sh stop --profiles-root $profiles_root' to stop them."
exit "$start_failed"
