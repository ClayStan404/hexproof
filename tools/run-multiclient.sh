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
event_mode=""
set_code=""
test_group=""
event_requested=0
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
  --event draft|sealed   Connect, create a local event, register/check in every
                         client, then start. Picks and deck building stay manual.
  --set CODE             Installed Limited set for --event (for example EOE).
  -h, --help             Show this help.

Examples:
  ./tools/run-multiclient.sh start --count 8 --windowed
  ./tools/run-multiclient.sh start --event draft --set EOE --count 8 --windowed
  ./tools/run-multiclient.sh status
  ./tools/run-multiclient.sh stop

Profiles are initialized only once and are reused on later starts so reconnect
credentials survive. Use another --profiles-root for a fresh test session.
Existing card-art files are hard-linked by default to reduce disk use, with
independent copies when hard links are unavailable (such as across disks). Their
directory entries and all metadata remain profile-local, and Hexproof writes
new/replaced images atomically.
Use a client supporting --server-url and --display-name; rebuild older binaries
when new launcher options require it. Shell-only edits do not always require
a client rebuild. Automatic event setup requires --event and a separately
running loopback server.
EOF
}

require_option_value() {
    if (($# < 2)) || [[ "$2" == --* ]]; then
        echo "$1 requires a value before the next option." >&2
        exit 2
    fi
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
            require_option_value "$@"
            count="$2"
            shift
            ;;
        --binary)
            require_option_value "$@"
            binary="$2"
            shift
            ;;
        --profiles-root)
            require_option_value "$@"
            profiles_root="$2"
            shift
            ;;
        --template)
            require_option_value "$@"
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
            require_option_value "$@"
            server_url="$2"
            shift
            ;;
        --name-prefix)
            require_option_value "$@"
            name_prefix="$2"
            shift
            ;;
        --windowed)
            windowed=1
            ;;
        --event)
            require_option_value "$@"
            event_mode="$2"
            event_requested=1
            shift
            ;;
        --set)
            require_option_value "$@"
            set_code="${2^^}"
            event_requested=1
            shift
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
if [[ ! "$count" =~ ^0*([1-9]|1[0-6])$ ]]; then
    echo "--count must be an integer from 1 through 16." >&2
    exit 2
fi
count="${BASH_REMATCH[1]}"
if ((event_requested)); then
    if [[ "$command_name" != "start" || ! "$event_mode" =~ ^(draft|sealed)$ ||
          ! "$set_code" =~ ^[A-Z0-9]{2,8}$ ]] || ((count < 2)) ||
          [[ "$event_mode" == "draft" && "$count" -gt 8 ]]; then
        echo "Use start --event draft|sealed --set CODE with 2-8 draft or 2-16 sealed clients." >&2
        exit 2
    fi
    for argument in "${client_args[@]}"; do
        case "$argument" in
            --test-*|--server-url|--server-url=*|--display-name|--display-name=*)
                echo "Use launcher options for automatic event setup; do not override $argument after --." >&2
                exit 2
                ;;
        esac
    done
    python3 - "$server_url" <<'PY'
import ipaddress
import sys
from urllib.parse import urlsplit

try:
    url = urlsplit(sys.argv[1])
    local = url.hostname == "localhost" or ipaddress.ip_address(url.hostname).is_loopback
    valid = url.scheme in ("ws", "wss") and local and (url.port is None or url.port > 0)
except ValueError:
    valid = False
if not valid:
    sys.exit("Automatic event setup requires a loopback ws:// or wss:// server.")
PY
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
    local matched_instance=0 matched_profile=0
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null &&
        [[ -r "/proc/$pid/environ" ]] || return 1
    while IFS= read -r -d '' entry; do
        case "$entry" in
            "HEXPROOF_TEST_INSTANCE=$instance") matched_instance=1 ;;
            "HEXPROOF_TEST_PROFILE_ROOT=$profiles_root/$instance") matched_profile=1 ;;
        esac
    done <"/proc/$pid/environ"
    ((matched_instance && matched_profile))
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

if [[ "$command_name" != "status" ]]; then
    if [[ "$command_name" == "stop" && ! -d "$profiles_root" ]]; then
        show_status
        exit 0
    fi
    mkdir -p "$profiles_root"
    exec 9>"$profiles_root/.launcher.lock"
    if ! flock -n 9; then
        echo "Another launcher is starting or stopping clients under $profiles_root." >&2
        exit 1
    fi
fi

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
    case "$template/" in
        "$profiles_root/"*)
            echo "The template must not be inside the profiles root." >&2
            exit 1
            ;;
    esac
fi

mkdir -p "$pid_dir"
if [[ -n "$event_mode" ]]; then
    # A new event must not silently mix already-running clients from an old run.
    shopt -s nullglob
    for recorded_pid in "$pid_dir"/client-*.pid; do
        instance="$(basename "$recorded_pid" .pid)"
        if managed_process "$(<"$recorded_pid")" "$instance"; then
            echo "Stop the existing test group before using --event (or use another --profiles-root)." >&2
            exit 1
        fi
    done
    shopt -u nullglob
    test_group="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
    echo "Preparing $event_mode for $count players using $set_code (group $test_group)."
    echo "The loopback server must already be running; setup progress/errors are in each client log."
fi
start_failed=0
declare -a prepared_indices=()

select_profile_paths() {
    number="$(printf '%02d' "$1")"
    instance="client-$number"
    profile_root="$profiles_root/$instance"
    data_home="$profile_root/data"
    app_data="$data_home/Hexproof/Hexproof"
    config_home="$profile_root/config"
    cache_home="$profile_root/cache"
    log_dir="$profile_root/logs"
    marker="$profile_root/.initialized"
    pid_file="$pid_dir/$instance.pid"
    display_name="$name_prefix $1"
}

for ((index = 1; index <= count; ++index)); do
    select_profile_paths "$index"

    if [[ -f "$pid_file" ]]; then
        existing_pid="$(<"$pid_file")"
        if managed_process "$existing_pid" "$instance"; then
            echo "$instance is already running (pid $existing_pid)."
            continue
        fi
        rm -f -- "$pid_file"
    fi

    if [[ ! -f "$marker" ]]; then
        if ((use_template)) && [[ ! -d "$template" ]]; then
            echo "AppData template does not exist: $template" >&2
            echo "Use --template PATH or --no-template to initialize $instance." >&2
            start_failed=1
            continue
        fi
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
                # Ownership belongs to the source process, never to a clone.
                [[ "$name" == "profile.lock" || "$name" == ".hexproof-art.lock" ||
                   "$name" == ".hexproof-art-owner.json" || "$name" == "card-art-storage.json" ]] && continue
                # A cloned profile owns its own image location. The configured
                # source trees are copied below, never shared by configuration.
                if [[ -f "$template/card-art-storage.json" &&
                      ( "$name" == "images" || "$name" == "custom-art" ) ]]; then
                    continue
                fi
                if [[ "$name" == "images" && -d "$source" && $copy_images -eq 0 ]]; then
                    mkdir -p "$app_data/images"
                    if ! cp -al -- "$source/." "$app_data/images/"; then
                        echo "Hard links unavailable; copying card images for $instance." >&2
                        # A partial link tree may already exist. Unlink each
                        # destination before copying so the template remains
                        # independent even when some hard links succeeded.
                        cp -a --reflink=auto --remove-destination -- \
                            "$source/." "$app_data/images/"
                    fi
                else
                    cp -a --reflink=auto -- "$source" "$app_data/"
                fi
            done
            shopt -u dotglob nullglob
            python3 - "$app_data" "$template" "$copy_images" <<'PY'
import hashlib
import json
import os
import pathlib
import shutil
import sys

destination = pathlib.Path(sys.argv[1])
source_prefix = os.path.normpath(sys.argv[2])
destination_prefix = os.path.normpath(sys.argv[1])
prefixes = [(source_prefix, destination_prefix)]
source_profile = pathlib.Path(sys.argv[2]).resolve()
location_file = source_profile / "card-art-storage.json"
if location_file.exists():
    location = json.loads(location_file.read_text(encoding="utf-8"))
    profile_key = hashlib.sha256(str(source_profile).encode()).hexdigest()[:20]
    if (location.get("format") != "hexproof.card-art-storage"
            or location.get("version") != 1
            or location.get("profileKey") != profile_key
            or not isinstance(location.get("baseDirectory"), str)):
        raise SystemExit("The template card-art location is invalid; no clients were started.")
    base = location["baseDirectory"]
    managed = pathlib.Path(base) / ("hexproof-art-" + profile_key) if base else source_profile
    if base:
        owner = json.loads((managed / ".hexproof-art-owner.json").read_text(encoding="utf-8"))
        if not pathlib.Path(base).is_absolute() or owner.get("profileKey") != profile_key:
            raise SystemExit("The template card-art directory is not owned by its profile.")
    for folder in ("images", "custom-art"):
        origin = managed / folder
        target = destination / folder
        if not origin.is_dir() or origin.is_symlink():
            raise SystemExit("The template card-art directory is unavailable.")
        for current, directories, files in os.walk(origin):
            for name in directories + files:
                if (pathlib.Path(current) / name).is_symlink():
                    raise SystemExit("The template card-art directory contains a symlink.")

        def copy_image(src, dst):
            if sys.argv[3] == "0":
                try:
                    os.link(src, dst)
                    return dst
                except OSError:
                    pass
            return shutil.copy2(src, dst)

        shutil.copytree(origin, target, copy_function=copy_image)
        prefixes.append((str(origin), str(target)))
    for old_root in location.get("previousImageRoots", []):
        if isinstance(old_root, str) and os.path.isabs(old_root):
            prefixes.append((os.path.normpath(old_root), str(destination / "images")))
prefixes.sort(key=lambda item: len(item[0]), reverse=True)


def rewrite(value):
    if isinstance(value, dict):
        return {key: rewrite(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rewrite(item) for item in value]
    if isinstance(value, str):
        normalized = os.path.normpath(value)
        for source, target in prefixes:
            if normalized == source:
                return target
            if normalized.startswith(source + os.sep):
                return target + normalized[len(source):]
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
    prepared_indices+=("$index")
done

if [[ -n "$event_mode" ]] && ((start_failed)); then
    echo "Profile preparation failed; no automatic event clients were launched." >&2
    exit 1
fi

for index in "${prepared_indices[@]}"; do
    select_profile_paths "$index"
    log_file="$log_dir/client.log"
    printf '\n[%s] starting %s as %s\n' "$(date --iso-8601=seconds)" "$instance" \
        "$display_name" >>"$log_file"
    launch_args=(--instance-label "$display_name" --server-url "$server_url"
        --display-name "$display_name")
    if ((windowed)); then
        launch_args+=(--windowed)
    fi
    if [[ -n "$event_mode" ]]; then
        launch_args+=(--test-event "$event_mode" --test-set "$set_code"
            --test-group "$test_group" --test-players "$count" --test-seat "$index")
    fi
    launch_args+=("${client_args[@]}")

    # Close the launcher lock in children so running clients do not retain it.
    nohup env \
        XDG_CONFIG_HOME="$config_home" \
        XDG_DATA_HOME="$data_home" \
        XDG_CACHE_HOME="$cache_home" \
        HEXPROOF_TEST_INSTANCE="$instance" \
        HEXPROOF_TEST_PROFILE_ROOT="$profile_root" \
        "$binary" "${launch_args[@]}" >>"$log_file" 2>&1 </dev/null 9>&- &
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
