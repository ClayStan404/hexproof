#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

# Build or reuse the pinned Forge payload, stage it on every selected public
# hub, then install a persistent systemd environment drop-in. The server probes
# the runtime during every start, so a healthy restart also verifies that Forge
# accepted the packaged harness and card scripts.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_tools="${repo_root}/third_party/forge-runtime"
upstream_file="${build_tools}/native-host/upstream.json"

scope="${HEXPROOF_FORGE_SCOPE:-production}"
targets_value="${HEXPROOF_TARGETS:-}"
default_output_dir="${HEXPROOF_FORGE_OUTPUT_DIR:-${repo_root}/build/forge-runtime}"
build_if_missing="${HEXPROOF_FORGE_BUILD_IF_MISSING:-1}"
java_override="${HEXPROOF_FORGE_JAVA:-}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=2
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=3
)

usage() {
    cat <<'EOF'
Usage: ./deploy/deploy-forge-runtime.sh

Build or reuse Hexproof's pinned Forge runtime and enable it on the selected
owner-operated hubs. The installed systemd drop-in survives ordinary server
binary deployments. Every target is staged before the first service restart;
a later failure rolls back targets already activated by this invocation.

Environment overrides:
  HEXPROOF_FORGE_SCOPE=production          production (default) or test
  HEXPROOF_TARGETS="cloud-b"                   Space-separated deployment targets
                                           Test scope requires one test-enabled target
  HEXPROOF_FORGE_ARCHIVE=/path/<pinned-runtime-name>.tar.gz
                                           Reuse an existing pinned archive;
                                           preserve its canonical package name
  HEXPROOF_FORGE_SOURCE_ARCHIVE=/path/<pinned-source-name>.tar.gz
                                           Matching source archive; defaults to
                                           the pinned name beside the runtime
  HEXPROOF_FORGE_BUILD_IF_MISSING=1         Build the pinned archives if absent
  HEXPROOF_FORGE_JAVA=/path/to/java         Override the target's Java command

Test scope installs only /var/lib/hexproof-test/forge-runtime and the
hexproof-test.service drop-in, then restarts only the test service on 57321.
Its JVM heap is capped at 512 MiB, service memory at 1 GiB, and tasks at 192.
Java 21 must already be installed. Deploy the current test server first with
deploy/deploy-test-server.sh. Publish the matching source archive identified
by the runtime's SOURCE.json before offering Forge over the network.

Examples:
  ./deploy/deploy-forge-runtime.sh
  HEXPROOF_TARGETS=cloud-b ./deploy/deploy-forge-runtime.sh
  HEXPROOF_FORGE_SCOPE=test ./deploy/deploy-forge-runtime.sh
  HEXPROOF_FORGE_OUTPUT_DIR=/path/to/paired-archives \
    ./deploy/deploy-forge-runtime.sh
EOF
}

target_config() {
    local target="$1"

    target_port="57320"
    target_java_command="java"
    local settings
    settings="$(python3 "${script_dir}/operator_config.py" cloud "${target}" forge)" || exit 2
    local -a values
    mapfile -t values <<<"${settings}"
    target_java_command="${values[1]}"
    target_service="hexproof.service"
    target_app_root="/var/lib/hexproof"
    target_binary="/usr/local/bin/hexproof-server"
    target_use_sudo="0"
    target_health_url="${values[0]}/healthz"

    if [[ "${scope}" == "test" ]]; then
        target_service="hexproof-test.service"
        target_app_root="/var/lib/hexproof-test"
        target_binary="/usr/local/bin/hexproof-server-test"
        target_health_url="${target_health_url%/healthz}/test/healthz"
        target_port="57321"
    fi
    target_java_command="${java_override:-${target_java_command}}"
    target_runtime_root="${target_app_root}/forge-runtime"
    target_dropin="/etc/systemd/system/${target_service}.d/forge-runtime.conf"
}

run_ssh() {
    # Callers intentionally expand the local argument array for the remote command.
    # shellcheck disable=SC2029
    ssh "${ssh_options[@]}" "$@"
}

run_scp() {
    scp "${ssh_options[@]}" "$@"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ "$#" -ne 0 ]]; then
    usage >&2
    exit 2
fi
if [[ "${scope}" != "production" && "${scope}" != "test" ]]; then
    printf 'HEXPROOF_FORGE_SCOPE must be production or test, got: %s\n' \
        "${scope}" >&2
    exit 2
fi
if [[ "${build_if_missing}" != "0" && "${build_if_missing}" != "1" ]]; then
    printf 'HEXPROOF_FORGE_BUILD_IF_MISSING must be 0 or 1, got: %s\n' \
        "${build_if_missing}" >&2
    exit 2
fi
if [[ -n "${java_override}" && ! "${java_override}" =~ ^[[:alnum:]_./+:-]+$ ]]; then
    printf 'HEXPROOF_FORGE_JAVA must be one command name or absolute path: %s\n' \
        "${java_override}" >&2
    exit 2
fi

for command_name in python3 ssh scp sha256sum tar grep awk sed date curl dirname; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Required local command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
done

if [[ -z "${targets_value}" ]]; then
    if [[ "${scope}" == "test" ]]; then default_group=testTarget; else default_group=forgeTargets; fi
    targets_value="$(python3 "${script_dir}/operator_config.py" defaults "${default_group}")" || exit 2
fi
read -r -a targets <<<"${targets_value}"
if [[ "${#targets[@]}" -eq 0 ]]; then
    printf 'HEXPROOF_TARGETS must select at least one target.\n' >&2
    exit 2
fi
if [[ "${scope}" == "test" ]] &&
   [[ "${#targets[@]}" -ne 1 ]]; then
    printf 'HEXPROOF_FORGE_SCOPE=test requires one test-enabled target.\n' >&2
    exit 2
fi
declare -A seen_targets=()
for target in "${targets[@]}"; do
    if [[ "${scope}" == "test" ]]; then
        python3 "${script_dir}/operator_config.py" cloud "${target}" test >/dev/null || exit 2
    fi
    target_config "${target}"
    if [[ -n "${seen_targets[${target}]:-}" ]]; then
        printf 'Duplicate deployment target: %s\n' "${target}" >&2
        exit 2
    fi
    seen_targets["${target}"]="1"
done

# Read identifiers as data, never source upstream-controlled shell text.
package_identity="$(python3 - "${upstream_file}" <<'PYTHON'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    upstream = json.load(source)
revision = upstream.get("revision")
adapter_revision = upstream.get("adapterRevision")
if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit("Invalid pinned official Forge revision")
if type(adapter_revision) is not int or adapter_revision < 1:
    raise SystemExit("Invalid pinned Forge adapter revision")
print(f"{revision}-adapter{adapter_revision}")
PYTHON
)"
archive="${HEXPROOF_FORGE_ARCHIVE:-${default_output_dir}/hexproof-forge-runtime-${package_identity}.tar.gz}"
source_archive="${HEXPROOF_FORGE_SOURCE_ARCHIVE:-$(dirname -- "${archive}")/hexproof-forge-source-${package_identity}.tar.gz}"

if [[ ! -f "${archive}" || ! -f "${source_archive}" ]]; then
    if [[ "${build_if_missing}" != "1" ]]; then
        printf 'Forge runtime and matching source archives are required: %s, %s\n' \
            "${archive}" "${source_archive}" >&2
        exit 1
    fi
    if [[ -n "${HEXPROOF_FORGE_ARCHIVE:-}" ||
          -n "${HEXPROOF_FORGE_SOURCE_ARCHIVE:-}" ]]; then
        printf 'A custom Forge archive pair is incomplete and cannot be built implicitly: %s, %s\n' \
            "${archive}" "${source_archive}" >&2
        exit 1
    fi
    printf 'Building pinned official Forge runtime %s...\n' "${package_identity}"
    "${build_tools}/build.sh" --output "${default_output_dir}"
fi
if [[ ! -f "${archive}" || ! -f "${source_archive}" ]]; then
    printf 'Forge build did not create the expected runtime/source archive pair: %s, %s\n' \
        "${archive}" "${source_archive}" >&2
    exit 1
fi

deployment_complete="0"
declare -A target_stage_dirs=()
declare -A target_staged_archives=()
declare -A target_backup_dirs=()
declare -A staging_created=()
declare -A target_up_to_date=()
declare -a staged_targets=()
declare -a activated_targets=()

cleanup_remote_staging() {
    local target stage_dir app_root

    set +e
    for target in "${targets[@]}"; do
        if [[ "${staging_created[${target}]:-0}" != "1" ]]; then
            continue
        fi
        target_config "${target}"
        stage_dir="${target_stage_dirs[${target}]}"
        app_root="${target_app_root}"
        run_ssh "${target}" bash -s -- cleanup-staging \
            "${stage_dir}" "${app_root}" <<'REMOTE_CLEANUP' >/dev/null 2>&1
set -euo pipefail
mode="$1"
stage_dir="$2"
app_root="$3"
[[ "${mode}" == "cleanup-staging" ]]
[[ "${stage_dir}" == "${app_root}/staging/forge-runtime-"* ]]
rm -f -- "${stage_dir}/runtime.tar.gz" "${stage_dir}/runtime.tar.gz.list" \
    "${stage_dir}/forge-runtime.conf"
rmdir -- "${stage_dir}" || printf 'Preserved nonempty staging directory: %s\n' "${stage_dir}" >&2
REMOTE_CLEANUP
    done
    set -e
}

cleanup_on_exit() {
    local status=$?

    trap - EXIT
    if [[ "${deployment_complete}" != "1" ]]; then
        cleanup_remote_staging
    fi
    exit "${status}"
}
trap cleanup_on_exit EXIT

# Validate the matching source, pinned provenance and complete payload hashes
# before the first SSH invocation. Verification also rejects unsafe tar entries.
python3 "${build_tools}/source-package.py" verify-release \
    --runtime "${archive}" --source "${source_archive}" --build-tools "${build_tools}"
archive_sha256="$(sha256sum "${archive}" | awk '{print $1}')"
runtime_id="${package_identity}-${archive_sha256:0:12}"

rollback_activated_targets() {
    local index target rollback_failed="0"

    for ((index = ${#activated_targets[@]} - 1; index >= 0; index--)); do
        target="${activated_targets[${index}]}"
        target_config "${target}"
        printf 'Rolling back Forge runtime on %s...\n' "${target}" >&2
        if ! run_ssh "${target}" bash -s -- rollback \
            "${target_service}" "${target_use_sudo}" \
            "${target_runtime_root}" "${target_dropin}" \
            "${target_backup_dirs[${target}]}" "${target_port}" <<'REMOTE_ROLLBACK'
set -euo pipefail
mode="$1"
service="$2"
use_sudo="$3"
runtime_root="$4"
dropin="$5"
backup_dir="$6"
port="$7"
[[ "${mode}" == "rollback" ]]

if [[ ! -d "${backup_dir}" ]]; then
    exit 0
fi

run_systemctl() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n systemctl "$@"
    else
        systemctl "$@"
    fi
}

install_system_file() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n install "$@"
    else
        install "$@"
    fi
}

remove_system_file() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n rm -f -- "$1"
    else
        rm -f -- "$1"
    fi
}

wait_for_local_health() {
    local deadline=$((SECONDS + 60))
    while ((SECONDS < deadline)); do
        if run_systemctl is-active --quiet "${service}" &&
           curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
               "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

if [[ -f "${backup_dir}/current-target" ]]; then
    old_target="$(<"${backup_dir}/current-target")"
    ln -sfn "${old_target}" "${runtime_root}/current.rollback"
    mv -Tf "${runtime_root}/current.rollback" "${runtime_root}/current"
else
    rm -f -- "${runtime_root}/current"
fi

if [[ -f "${backup_dir}/dropin.conf" ]]; then
    install_system_file -d -m 0755 "$(dirname -- "${dropin}")"
    install_system_file -m 0644 "${backup_dir}/dropin.conf" "${dropin}"
else
    remove_system_file "${dropin}"
fi

run_systemctl daemon-reload
run_systemctl restart "${service}"
wait_for_local_health
REMOTE_ROLLBACK
        then
            printf 'CRITICAL: Forge rollback failed on %s.\n' "${target}" >&2
            rollback_failed="1"
        fi
    done

    [[ "${rollback_failed}" == "0" ]]
}

printf 'Preparing Forge runtime %s (%s scope) on: %s\n' \
    "${runtime_id}" "${scope}" "${targets[*]}"
printf '%s\n' 'Checking every target before uploading or changing anything...'

for target in "${targets[@]}"; do
    target_config "${target}"
    target_release_dir="${target_runtime_root}/releases/${runtime_id}"
    target_stage_dirs["${target}"]="${target_app_root}/staging/forge-runtime-${runtime_id}-${timestamp}"
    target_staged_archives["${target}"]="${target_stage_dirs[${target}]}/runtime.tar.gz"
    target_backup_dirs["${target}"]="${target_app_root}/backups/forge-runtime.rollback-${timestamp}-before-${runtime_id}"

    printf '  operating system: %s\n' "${target}"
    run_ssh "${target}" 'uname -s && cat /etc/os-release'

    printf '  preflight: %s\n' "${target}"
    run_ssh "${target}" bash -s -- preflight \
        "${target_service}" "${target_binary}" "${target_app_root}" \
        "${target_use_sudo}" "${target_java_command}" \
        "${target_stage_dirs[${target}]}" "${target_backup_dirs[${target}]}" \
        "${target_runtime_root}" "${target_dropin}" <<'REMOTE_PREFLIGHT'
set -euo pipefail
mode="$1"
service="$2"
binary="$3"
app_root="$4"
use_sudo="$5"
java_command="$6"
stage_dir="$7"
backup_dir="$8"
runtime_root="$9"
dropin="${10}"
[[ "${mode}" == "preflight" ]]

run_systemctl() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n systemctl "$@"
    else
        systemctl "$@"
    fi
}

[[ "$(uname -s)" == "Linux" ]]
test -r /etc/os-release
for command_name in awk bash basename cat chmod cp curl dirname grep install java ln mv \
    readlink rm sed sha256sum sleep systemctl tar; do
    if [[ "${command_name}" == "java" ]]; then
        command -v "${java_command}" >/dev/null 2>&1 || {
            printf 'Configured Java command not found: %s\n' "${java_command}" >&2
            exit 1
        }
        continue
    fi
    command -v "${command_name}" >/dev/null 2>&1 || {
        printf 'Required remote command not found: %s\n' "${command_name}" >&2
        exit 1
    }
done
if [[ "${use_sudo}" == "1" ]]; then
    command -v sudo >/dev/null 2>&1
    sudo -n true
fi
run_systemctl is-active --quiet "${service}"
test -x "${binary}"
binary_help="$("${binary}" -help 2>&1)"
if ! grep -q 'HEXPROOF_FORGE_HARNESS' <<<"${binary_help}"; then
    printf 'Installed Hexproof server does not support persistent Forge environment configuration.\n' >&2
    exit 1
fi
service_exec_start="$(run_systemctl show "${service}" -p ExecStart --value)"
if grep -Eq -- '-forge-(harness|home)(=| )' <<<"${service_exec_start}"; then
    printf 'Service %s still sets Forge paths in ExecStart; remove those flags before using the managed runtime drop-in.\n' \
        "${service}" >&2
    exit 1
fi

java_version_line="$("${java_command}" -version 2>&1 | sed -n '1p')"
java_major="$(printf '%s\n' "${java_version_line}" | sed -nE 's/.*version "([0-9]+).*/\1/p')"
if [[ ! "${java_major}" =~ ^[0-9]+$ ]] ||
   ((java_major != 21)); then
    printf 'Forge requires Java 21; %s reported: %s\n' \
        "${java_command}" "${java_version_line}" >&2
    exit 1
fi

test -d "${app_root}"
test -w "${app_root}"
test -d "${app_root}/staging"
test -w "${app_root}/staging"
test -d "${app_root}/backups"
test -w "${app_root}/backups"
test ! -e "${stage_dir}"
test ! -e "${backup_dir}"
if [[ -e "${runtime_root}/current" && ! -L "${runtime_root}/current" ]]; then
    printf 'Forge current path exists but is not a symbolic link: %s\n' \
        "${runtime_root}/current" >&2
    exit 1
fi
if [[ -e "${dropin}" && ! -f "${dropin}" ]]; then
    printf 'Forge systemd drop-in exists but is not a regular file: %s\n' \
        "${dropin}" >&2
    exit 1
fi
REMOTE_PREFLIGHT

    if run_ssh "${target}" bash -s -- check-current \
        "${target_service}" "${target_runtime_root}" "${target_release_dir}" \
        "${target_dropin}" "${target_java_command}" "${target_port}" \
        "${scope}" <<'REMOTE_CURRENT'
set -euo pipefail
mode="$1"
service="$2"
runtime_root="$3"
release_dir="$4"
dropin="$5"
java_command="$6"
port="$7"
scope="$8"
[[ "${mode}" == "check-current" ]]
[[ "$(readlink -f -- "${runtime_root}/current")" == "$(readlink -f -- "${release_dir}")" ]] || exit 10
grep -Fqx "Environment=\"HEXPROOF_FORGE_HARNESS=${runtime_root}/current/forge-harness.jar\"" "${dropin}" || exit 10
grep -Fqx "Environment=\"HEXPROOF_FORGE_HOME=${runtime_root}/current/forge-gui\"" "${dropin}" || exit 10
grep -Fqx "Environment=\"HEXPROOF_FORGE_JAVA=${java_command}\"" "${dropin}" || exit 10
systemctl is-active --quiet "${service}" || exit 10
environment="$(systemctl show "${service}" -p Environment --value)"
grep -Fq "HEXPROOF_FORGE_HARNESS=${runtime_root}/current/forge-harness.jar" \
    <<<"${environment}" || exit 10
grep -Fq "HEXPROOF_FORGE_HOME=${runtime_root}/current/forge-gui" \
    <<<"${environment}" || exit 10
grep -Fq "HEXPROOF_FORGE_JAVA=${java_command}" <<<"${environment}" || exit 10
if [[ "${scope}" == "test" ]]; then
    test_java_options='-Xms64m -Xmx512m -XX:ActiveProcessorCount=1 -XX:+ExitOnOutOfMemoryError -Djava.awt.headless=true -Duser.home=/var/lib/hexproof-test'
    grep -Fqx "Environment=\"JAVA_TOOL_OPTIONS=${test_java_options}\"" "${dropin}" || exit 10
    grep -Fqx 'Environment="GOMAXPROCS=1"' "${dropin}" || exit 10
    grep -Fqx 'MemoryMax=1G' "${dropin}" || exit 10
    grep -Fqx 'TasksMax=192' "${dropin}" || exit 10
    grep -Fq "\"JAVA_TOOL_OPTIONS=${test_java_options}\"" <<<"${environment}" || exit 10
    grep -Eq '(^| )"?GOMAXPROCS=1"?( |$)' <<<"${environment}" || exit 10
    [[ "$(systemctl show "${service}" -p MemoryMax --value)" == "1073741824" ]] || exit 10
    [[ "$(systemctl show "${service}" -p TasksMax --value)" == "192" ]] || exit 10
fi
curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${port}/healthz" >/dev/null || exit 10
REMOTE_CURRENT
    then
        printf 'Forge runtime is already current on %s; skipping.\n' "${target}"
        target_up_to_date["${target}"]="1"
        continue
    else
        current_status=$?
        if [[ "${current_status}" -ne 10 ]]; then
            printf 'Could not inspect the installed Forge runtime on %s.\n' \
                "${target}" >&2
            exit "${current_status}"
        fi
    fi

    printf 'Staging Forge runtime on %s...\n' "${target}"
    staging_created["${target}"]="1"
    run_ssh "${target}" bash -s -- prepare-stage \
        "${target_stage_dirs[${target}]}" "${target_app_root}" <<'REMOTE_PREPARE'
set -euo pipefail
mode="$1"
stage_dir="$2"
app_root="$3"
[[ "${mode}" == "prepare-stage" ]]
[[ "${stage_dir}" == "${app_root}/staging/forge-runtime-"* ]]
install -d -m 0700 "${stage_dir}"
REMOTE_PREPARE

    run_scp -q "${archive}" "${target}:${target_staged_archives[${target}]}"
    run_ssh "${target}" bash -s -- verify-stage \
        "${target_staged_archives[${target}]}" "${archive_sha256}" <<'REMOTE_STAGE'
set -euo pipefail
mode="$1"
staged_archive="$2"
expected_sha256="$3"
[[ "${mode}" == "verify-stage" ]]
actual_sha256="$(sha256sum "${staged_archive}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${expected_sha256}" ]]
listing="${staged_archive}.list"
tar -tzf "${staged_archive}" >"${listing}"
grep -Fxq 'hexproof-forge-runtime/forge-harness.jar' "${listing}"
grep -Fq 'hexproof-forge-runtime/forge-gui/res/cardsfolder/' "${listing}"
grep -Fxq 'hexproof-forge-runtime/SOURCE.json' "${listing}"
grep -Fxq 'hexproof-forge-runtime/RUNTIME-MANIFEST.json' "${listing}"
REMOTE_STAGE
    staged_targets+=("${target}")
done

for target in "${staged_targets[@]}"; do
    target_config "${target}"
    target_release_dir="${target_runtime_root}/releases/${runtime_id}"

    printf 'Activating Forge runtime on %s...\n' "${target}"
    # Include an interrupted activation in the fleet rollback set. The remote
    # rollback is a no-op until the activation has created its backup record.
    activated_targets+=("${target}")
    if ! run_ssh "${target}" bash -s -- activate \
        "${target_service}" "${target_use_sudo}" "${target_runtime_root}" \
        "${target_release_dir}" "${target_dropin}" "${target_java_command}" \
        "${target_stage_dirs[${target}]}" "${target_staged_archives[${target}]}" \
        "${target_backup_dirs[${target}]}" "${archive_sha256}" \
        "${target_port}" "${scope}" <<'REMOTE_ACTIVATE'
set -Eeuo pipefail
mode="$1"
service="$2"
use_sudo="$3"
runtime_root="$4"
release_dir="$5"
dropin="$6"
java_command="$7"
stage_dir="$8"
staged_archive="$9"
backup_dir="${10}"
archive_sha256="${11}"
port="${12}"
scope="${13}"
[[ "${mode}" == "activate" ]]

run_systemctl() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n systemctl "$@"
    else
        systemctl "$@"
    fi
}

install_system_file() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n install "$@"
    else
        install "$@"
    fi
}

remove_system_file() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n rm -f -- "$1"
    else
        rm -f -- "$1"
    fi
}

wait_for_local_health() {
    local deadline=$((SECONDS + 60))
    while ((SECONDS < deadline)); do
        if run_systemctl is-active --quiet "${service}" &&
           curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
               "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

restore_previous() {
    if [[ -f "${backup_dir}/current-target" ]]; then
        old_target="$(<"${backup_dir}/current-target")"
        ln -sfn "${old_target}" "${runtime_root}/current.rollback"
        mv -Tf "${runtime_root}/current.rollback" "${runtime_root}/current"
    else
        rm -f -- "${runtime_root}/current"
    fi

    if [[ -f "${backup_dir}/dropin.conf" ]]; then
        install_system_file -d -m 0755 "$(dirname -- "${dropin}")"
        install_system_file -m 0644 "${backup_dir}/dropin.conf" "${dropin}"
    else
        remove_system_file "${dropin}"
    fi
    run_systemctl daemon-reload
    run_systemctl restart "${service}"
    wait_for_local_health
}

backup_ready="0"
activation_complete="0"
rollback_on_exit() {
    local status=$?
    trap - EXIT
    if [[ "${status}" -ne 0 && "${backup_ready}" == "1" &&
          "${activation_complete}" != "1" ]]; then
        printf 'Forge activation failed; restoring previous runtime configuration.\n' >&2
        restore_previous || printf 'Forge rollback health check failed for %s.\n' \
            "${service}" >&2
    fi
    exit "${status}"
}
trap rollback_on_exit EXIT

actual_sha256="$(sha256sum "${staged_archive}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${archive_sha256}" ]]
tar -xzf "${staged_archive}" -C "${stage_dir}"
package_root="${stage_dir}/hexproof-forge-runtime"
test -f "${package_root}/forge-harness.jar"
test -d "${package_root}/forge-gui/res/cardsfolder"

install -d -m 0755 "${runtime_root}/releases"
if [[ ! -e "${release_dir}" ]]; then
    printf '%s\n' "${archive_sha256}" >"${package_root}/.hexproof-archive-sha256"
    mv "${package_root}" "${release_dir}"
fi
test -f "${release_dir}/forge-harness.jar"
test -d "${release_dir}/forge-gui/res/cardsfolder"
grep -Fqx "${archive_sha256}" "${release_dir}/.hexproof-archive-sha256"
chmod -R u=rwX,go=rX "${release_dir}"

install -d -m 0700 "${backup_dir}"
if [[ -L "${runtime_root}/current" ]]; then
    readlink -- "${runtime_root}/current" >"${backup_dir}/current-target"
fi
if [[ -f "${dropin}" ]]; then
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n cat "${dropin}" >"${backup_dir}/dropin.conf"
    else
        cat "${dropin}" >"${backup_dir}/dropin.conf"
    fi
fi
backup_ready="1"

ln -sfn "releases/$(basename -- "${release_dir}")" \
    "${runtime_root}/current.new"
mv -Tf "${runtime_root}/current.new" "${runtime_root}/current"

dropin_stage="${stage_dir}/forge-runtime.conf"
printf '%s\n' \
    '[Service]' \
    "Environment=\"HEXPROOF_FORGE_HARNESS=${runtime_root}/current/forge-harness.jar\"" \
    "Environment=\"HEXPROOF_FORGE_HOME=${runtime_root}/current/forge-gui\"" \
    "Environment=\"HEXPROOF_FORGE_JAVA=${java_command}\"" \
    >"${dropin_stage}"
if [[ "${scope}" == "test" ]]; then
    test_java_options='-Xms64m -Xmx512m -XX:ActiveProcessorCount=1 -XX:+ExitOnOutOfMemoryError -Djava.awt.headless=true -Duser.home=/var/lib/hexproof-test'
    printf '%s\n' \
        "Environment=\"JAVA_TOOL_OPTIONS=${test_java_options}\"" \
        'Environment="GOMAXPROCS=1"' \
        'MemoryMax=1G' \
        'TasksMax=192' >>"${dropin_stage}"
fi
install_system_file -d -m 0755 "$(dirname -- "${dropin}")"
install_system_file -m 0644 "${dropin_stage}" "${dropin}"

run_systemctl daemon-reload
run_systemctl restart "${service}"
wait_for_local_health

environment="$(run_systemctl show "${service}" -p Environment --value)"
grep -Fq "HEXPROOF_FORGE_HARNESS=${runtime_root}/current/forge-harness.jar" \
    <<<"${environment}"
grep -Fq "HEXPROOF_FORGE_HOME=${runtime_root}/current/forge-gui" \
    <<<"${environment}"
grep -Fq "HEXPROOF_FORGE_JAVA=${java_command}" <<<"${environment}"
if [[ "${scope}" == "test" ]]; then
    grep -Fq "\"JAVA_TOOL_OPTIONS=${test_java_options}\"" <<<"${environment}"
    grep -Eq '(^| )"?GOMAXPROCS=1"?( |$)' <<<"${environment}"
    [[ "$(run_systemctl show "${service}" -p MemoryMax --value)" == "1073741824" ]]
    [[ "$(run_systemctl show "${service}" -p TasksMax --value)" == "192" ]]
fi
[[ "$(readlink -f -- "${runtime_root}/current")" == \
   "$(readlink -f -- "${release_dir}")" ]]

activation_complete="1"
trap - EXIT
rm -f -- "${stage_dir}/runtime.tar.gz" "${stage_dir}/runtime.tar.gz.list" \
    "${stage_dir}/forge-runtime.conf"
rmdir -- "${stage_dir}" || printf 'Preserved nonempty staging directory: %s\n' "${stage_dir}" >&2
REMOTE_ACTIVATE
    then
        printf 'Forge activation failed on %s; rolling back this deployment.\n' \
            "${target}" >&2
        rollback_activated_targets || true
        exit 1
    fi
done

for target in "${targets[@]}"; do
    target_config "${target}"
    printf 'Checking %s public health endpoint...\n' "${target}"
    if ! curl --noproxy '*' -fsS --connect-timeout 3 --max-time 10 \
        --retry 2 --retry-all-errors --retry-delay 1 -o /dev/null \
        "${target_health_url}"; then
        printf 'Public verification failed on %s; rolling back Forge deployment.\n' \
            "${target}" >&2
        rollback_activated_targets || true
        exit 1
    fi
done

deployment_complete="1"
printf 'Forge runtime deployment complete on %s (%s activated, %s unchanged).\n' \
    "${targets[*]}" "${#activated_targets[@]}" "${#target_up_to_date[@]}"
