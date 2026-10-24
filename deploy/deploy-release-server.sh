#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

# Download prebuilt Linux servers from a GitHub release, stage and validate
# every selected host, then activate the release as one deployment transaction.

repo_slug="${HEXPROOF_REPO:-ClayStan404/hexproof}"
targets_value="${HEXPROOF_TARGETS:-}"
requested_version="${HEXPROOF_VERSION:-}"
requested_arch="${HEXPROOF_ARCH:-}"
backup_keep="${HEXPROOF_BACKUP_KEEP:-5}"
install_monitoring="${HEXPROOF_INSTALL_MONITORING:-0}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=2
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=3
)

usage() {
    cat <<'EOF'
Usage: ./deploy/deploy-release-server.sh

Download the prebuilt Linux server from a GitHub release and deploy it on
the owner-operated hosts. Every host is staged and verified before
the first service is restarted. A failed activation rolls back the hosts
already activated by this invocation.

Environment overrides:
  HEXPROOF_COMPONENT=game                  game (default) or feedback
  HEXPROOF_TARGETS="cloud-a cloud-b"           Space-separated deployment targets
  HEXPROOF_VERSION=2.0.0                   Version (default: latest release)
  HEXPROOF_ARCH=amd64                      Force the asset architecture
  HEXPROOF_REPO=ClayStan404/hexproof       GitHub repository slug
  HEXPROOF_BACKUP_KEEP=5                   Backups retained per deployed host;
                                           use 0 to disable automatic pruning
  HEXPROOF_ALLOW_DRAFT=1                   Allow an explicit authenticated draft version
  HEXPROOF_VERIFY_ONLY=1                   Home nodes: verify without remote changes
  HEXPROOF_ALLOW_ACTIVE_ROOMS=1            Home nodes: owner-authorized room interruption
  HEXPROOF_HOME_INPUTS=/private/inputs.json Home nodes: Forge/Java inputs; config for first install
  HEXPROOF_INSTALL_MONITORING=1            Install local diagnostics after a successful upgrade
  HEXPROOF_FEEDBACK_INPUTS=/private/inputs.json Feedback: explicit target/config/credential inputs
  HEXPROOF_FEEDBACK_TEST_RUN_ID=123          Feedback initial test install: successful manual build
  HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID=456     Exact combined Actions artifact ID
  HEXPROOF_FEEDBACK_TEST_HEAD_SHA=<40 hex>   Exact reviewed build source commit
  HEXPROOF_FEEDBACK_TEST_ARCHIVE=/private/artifact.zip Optional cached original artifact ZIP

Targets and defaults come from operator-owned JSON (see deploy/home/README.md).
Set HEXPROOF_DEPLOYMENT_TARGETS_FILE / HEXPROOF_NODES_FILE to override their paths.
Select cloud and home nodes in
separate invocations; each group is its own deployment transaction. Home
upgrades retain the installed Forge/Java runtime and corresponding sources.
Home nodes and draft deployments require authenticated gh with attestation
verification support.

Examples:
  ./deploy/deploy-release-server.sh
  HEXPROOF_TARGETS=cloud-b HEXPROOF_VERSION=2.0.0 ./deploy/deploy-release-server.sh
  HEXPROOF_TARGETS="home-a home-b" HEXPROOF_VERSION=2.1.0 ./deploy/deploy-release-server.sh
EOF
}

target_config() {
    local settings
    settings="$(python3 "${script_dir}/operator_config.py" cloud "$1")" || exit 2
    local -a values
    mapfile -t values <<<"${settings}"
    target_service="hexproof.service"
    target_app_root="/var/lib/hexproof"
    target_binary="/usr/local/bin/hexproof-server"
    target_backup_dir="${target_app_root}/backups"
    target_use_sudo="0"
    target_health_url="${values[0]}/healthz"
    target_ws_url="${values[0]}/ws"
}

run_ssh() {
    # Callers intentionally expand the local argument array for the remote command.
    # shellcheck disable=SC2029
    ssh "${ssh_options[@]}" "$@"
}

run_scp() {
    scp "${ssh_options[@]}" "$@"
}

download() {
    curl -fsSL --connect-timeout 10 --retry 3 --retry-all-errors \
        --retry-delay 2 "$@"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ "$#" -ne 0 ]]; then
    usage >&2
    exit 2
fi
case "${HEXPROOF_COMPONENT:-game}" in
    feedback)
        read -r -a feedback_targets <<<"${targets_value}"
        if [[ -z "${requested_version}" || "${#feedback_targets[@]}" -ne 1 ||
              -z "${HEXPROOF_TARGETS:-}" || -z "${HEXPROOF_FEEDBACK_INPUTS:-}" ]]; then
            printf 'Feedback deployment requires an explicit version, one target and feedback inputs.\n' >&2
            exit 2
        fi
        feedback_args=(--version "${requested_version#v}" --target "${feedback_targets[0]}"
                       --inputs "${HEXPROOF_FEEDBACK_INPUTS}" --repo "${repo_slug}")
        case "${HEXPROOF_ALLOW_DRAFT:-0}" in
            0) ;; 1) feedback_args+=(--allow-draft) ;;
            *) printf 'HEXPROOF_ALLOW_DRAFT must be 0 or 1.\n' >&2; exit 2 ;;
        esac
        case "${HEXPROOF_VERIFY_ONLY:-0}" in
            0) ;; 1) feedback_args+=(--verify-only) ;;
            *) printf 'HEXPROOF_VERIFY_ONLY must be 0 or 1.\n' >&2; exit 2 ;;
        esac
        if [[ -n "${HEXPROOF_FEEDBACK_TEST_RUN_ID:-}${HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID:-}${HEXPROOF_FEEDBACK_TEST_HEAD_SHA:-}${HEXPROOF_FEEDBACK_TEST_ARCHIVE:-}" ]]; then
            if [[ ! "${HEXPROOF_FEEDBACK_TEST_RUN_ID:-}" =~ ^[1-9][0-9]*$ ||
                  ! "${HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID:-}" =~ ^[1-9][0-9]*$ ||
                  ! "${HEXPROOF_FEEDBACK_TEST_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ||
                  "${HEXPROOF_ALLOW_DRAFT:-0}" != 0 ]]; then
                printf 'Feedback test installation requires explicit run ID, artifact ID and head SHA; draft mode is incompatible.\n' >&2
                exit 2
            fi
            feedback_args+=(--test-run-id "${HEXPROOF_FEEDBACK_TEST_RUN_ID}"
                            --test-artifact-id "${HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID}"
                            --test-head-sha "${HEXPROOF_FEEDBACK_TEST_HEAD_SHA}")
            [[ -z "${HEXPROOF_FEEDBACK_TEST_ARCHIVE:-}" ]] || feedback_args+=(--test-archive "${HEXPROOF_FEEDBACK_TEST_ARCHIVE}")
        fi
        if [[ "${install_monitoring}" != 0 || -n "${HEXPROOF_HOME_INPUTS:-}" ||
              "${HEXPROOF_ALLOW_ACTIVE_ROOMS:-0}" != 0 ]]; then
            printf 'Game/home deployment options do not apply to the feedback component.\n' >&2
            exit 2
        fi
        exec python3 "${script_dir}/feedback/install.py" "${feedback_args[@]}"
        ;;
    game)
        if [[ -n "${HEXPROOF_FEEDBACK_INPUTS:-}${HEXPROOF_FEEDBACK_TEST_RUN_ID:-}${HEXPROOF_FEEDBACK_TEST_ARTIFACT_ID:-}${HEXPROOF_FEEDBACK_TEST_HEAD_SHA:-}${HEXPROOF_FEEDBACK_TEST_ARCHIVE:-}" ]]; then
            printf 'Feedback inputs require HEXPROOF_COMPONENT=feedback.\n' >&2
            exit 2
        fi
        ;;
    *) printf 'HEXPROOF_COMPONENT must be game or feedback.\n' >&2; exit 2 ;;
esac
if [[ ! "${backup_keep}" =~ ^[0-9]+$ ]]; then
    printf 'HEXPROOF_BACKUP_KEEP must be a non-negative integer, got: %s\n' \
        "${backup_keep}" >&2
    exit 2
fi
case "${install_monitoring}" in
    0) ;;
    1)
        if [[ -z "${requested_version}" || "${HEXPROOF_VERIFY_ONLY:-0}" != 0 ]]; then
            printf 'Monitoring installation requires an explicit version and a writable deployment.\n' >&2
            exit 2
        fi
        ;;
    *) printf 'HEXPROOF_INSTALL_MONITORING must be 0 or 1.\n' >&2; exit 2 ;;
esac

install_local_monitoring() {
    if [[ "${install_monitoring}" == 1 ]]; then
        python3 "${script_dir}/monitoring/install.py" \
            --version "${requested_version#v}" --targets "${targets[@]}"
    fi
}

for command_name in ssh scp curl tar sha256sum mktemp grep sed date awk rm; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Required local command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
done

if [[ -z "${targets_value}" ]]; then
    targets_value="$(python3 "${script_dir}/operator_config.py" defaults releaseTargets)" || exit 2
fi
read -r -a targets <<<"${targets_value}"
if [[ "${#targets[@]}" -eq 0 ]]; then
    printf 'HEXPROOF_TARGETS must select at least one target.\n' >&2
    exit 2
fi

# Home nodes have two services and sealed release trees. Keep one operator
# entry point while reusing their existing installer and rollback machinery.
home_targets=0
cloud_targets=0
for target in "${targets[@]}"; do
    target_kind="$(python3 "${script_dir}/operator_config.py" kind "${target}")" || exit 2
    case "${target_kind}" in
        home) home_targets=$((home_targets + 1)) ;;
        cloud) target_config "${target}"; cloud_targets=$((cloud_targets + 1)) ;;
    esac
done
if ((home_targets > 0)); then
    if ((cloud_targets > 0)); then
        printf 'Deploy cloud and home targets in separate invocations.\n' >&2
        exit 2
    fi
    home_args=(--repo "${repo_slug}" --targets "${targets[@]}")
    [[ -z "${requested_version}" ]] || home_args+=(--version "${requested_version}")
    [[ -z "${requested_arch}" ]] || home_args+=(--arch "${requested_arch}")
    [[ -z "${HEXPROOF_HOME_INPUTS:-}" ]] || home_args+=(--inputs "${HEXPROOF_HOME_INPUTS}")
    case "${HEXPROOF_ALLOW_DRAFT:-0}" in
        0) ;;
        1) home_args+=(--allow-draft) ;;
        *) printf 'HEXPROOF_ALLOW_DRAFT must be 0 or 1.\n' >&2; exit 2 ;;
    esac
    case "${HEXPROOF_VERIFY_ONLY:-0}" in
        0) ;;
        1) home_args+=(--verify-only) ;;
        *) printf 'HEXPROOF_VERIFY_ONLY must be 0 or 1.\n' >&2; exit 2 ;;
    esac
    case "${HEXPROOF_ALLOW_ACTIVE_ROOMS:-0}" in
        0) ;;
        1) home_args+=(--allow-active-rooms) ;;
        *) printf 'HEXPROOF_ALLOW_ACTIVE_ROOMS must be 0 or 1.\n' >&2; exit 2 ;;
    esac
    python3 "${script_dir}/deploy-home-release.py" "${home_args[@]}"
    install_local_monitoring
    exit 0
fi
if [[ "${HEXPROOF_VERIFY_ONLY:-0}" != 0 || -n "${HEXPROOF_HOME_INPUTS:-}" || "${HEXPROOF_ALLOW_ACTIVE_ROOMS:-0}" != 0 ]]; then
    printf 'Verify-only, runtime inputs and active-room opt-in apply only to home targets.\n' >&2
    exit 2
fi
case "${HEXPROOF_ALLOW_DRAFT:-0}" in
    0) ;;
    1)
        if [[ -z "${requested_version}" ]]; then
            printf 'Draft deployment requires an explicit HEXPROOF_VERSION.\n' >&2
            exit 2
        fi
        for command_name in python3 gh; do
            command -v "${command_name}" >/dev/null 2>&1 || {
                printf 'Required draft deployment command not found: %s\n' "${command_name}" >&2
                exit 1
            }
        done
        ;;
    *) printf 'HEXPROOF_ALLOW_DRAFT must be 0 or 1.\n' >&2; exit 2 ;;
esac

declare -A seen_targets=()
for target in "${targets[@]}"; do
    target_config "${target}"
    if [[ -n "${seen_targets[${target}]:-}" ]]; then
        printf 'Duplicate deployment target: %s\n' "${target}" >&2
        exit 2
    fi
    seen_targets["${target}"]="1"
done

# Resolve the release version. Accept an optional leading "v"; release asset
# names always use the bare MAJOR.MINOR.PATCH form.
if [[ -z "${requested_version}" ]]; then
    requested_version="$(
        download --max-time 30 \
            "https://api.github.com/repos/${repo_slug}/releases/latest" |
            sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'
    )"
    if [[ -z "${requested_version}" ]]; then
        printf 'Could not resolve the latest release of %s.\n' "${repo_slug}" >&2
        exit 1
    fi
fi
version="${requested_version#v}"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Release version must use MAJOR.MINOR.PATCH, got: %s\n' \
        "${requested_version}" >&2
    exit 2
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
workdir="$(mktemp -d)"
base_url="https://github.com/${repo_slug}/releases/download/v${version}"

declare -A target_arches=()
declare -A target_build_dirs=()
declare -A target_staged_binaries=()
declare -A target_new_binaries=()
declare -A target_backups=()
declare -A staging_created=()
declare -A target_up_to_date=()
declare -a staged_targets=()
declare -a activated_targets=()
deployment_complete="0"

cleanup_remote_staging() {
    local target build_dir app_root

    set +e
    for target in "${targets[@]}"; do
        if [[ "${staging_created[${target}]:-0}" != "1" ]]; then
            continue
        fi
        target_config "${target}"
        build_dir="${target_build_dirs[${target}]}"
        app_root="${target_app_root}"
        run_ssh "${target}" bash -s -- cleanup-staging \
            "${build_dir}" "${app_root}" <<'REMOTE_CLEANUP' >/dev/null 2>&1
set -euo pipefail
mode="$1"
build_dir="$2"
app_root="$3"
[[ "${mode}" == "cleanup-staging" ]]
[[ "${build_dir}" == "${app_root}/staging/server-release-"* ]]
rm -rf -- "${build_dir}"
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
    rm -rf -- "${workdir}"
    exit "${status}"
}
trap cleanup_on_exit EXIT

rollback_activated_targets() {
    local index target rollback_failed="0"

    for ((index = ${#activated_targets[@]} - 1; index >= 0; index--)); do
        target="${activated_targets[${index}]}"
        target_config "${target}"
        printf 'Rolling back %s to %s...\n' \
            "${target}" "${target_backups[${target}]}" >&2
        if ! run_ssh "${target}" bash -s -- rollback \
            "${target_service}" "${target_binary}" "${target_use_sudo}" \
            "${target_backups[${target}]}" <<'REMOTE_ROLLBACK'
set -euo pipefail

mode="$1"
service="$2"
binary="$3"
use_sudo="$4"
backup="$5"
rollback_new="${binary}.fleet-rollback"

[[ "${mode}" == "rollback" ]]

run_systemctl() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n systemctl "$@"
    else
        systemctl "$@"
    fi
}

verify_active_service_binary() {
    local main_pid actual expected
    main_pid="$(run_systemctl show "${service}" -p MainPID --value)"
    [[ "${main_pid}" =~ ^[1-9][0-9]*$ ]] || return 1
    actual="$(readlink -f -- "/proc/${main_pid}/exe")"
    expected="$(readlink -f -- "${binary}")"
    [[ "${actual}" == "${expected}" ]]
}

wait_for_local_health() {
    # Forge probes its card database before the hub binds its HTTP listener.
    local attempt=1 health_deadline=$((SECONDS + 120))
    while [[ "${attempt}" -le 240 && "${SECONDS}" -lt "${health_deadline}" ]]; do
        if run_systemctl is-active --quiet "${service}" &&
           verify_active_service_binary &&
           curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
               http://127.0.0.1:57320/healthz >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done
    return 1
}

cleanup() {
    rm -f -- "${rollback_new}"
}
trap cleanup EXIT

test -f "${backup}"
cp -a "${backup}" "${rollback_new}"
mv "${rollback_new}" "${binary}"
run_systemctl restart "${service}"
wait_for_local_health
"${binary}" -version
REMOTE_ROLLBACK
        then
            printf 'CRITICAL: rollback failed on %s.\n' "${target}" >&2
            rollback_failed="1"
        fi
    done

    [[ "${rollback_failed}" == "0" ]]
}

check_public_target() {
    local target="$1" headers_file _attempt curl_status

    target_config "${target}"
    printf 'Checking %s public health endpoint...\n' "${target}"
    if ! curl --noproxy '*' -fsS --connect-timeout 3 --max-time 10 \
        --retry 2 --retry-all-errors --retry-delay 1 -o /dev/null \
        "${target_health_url}"; then
        return 1
    fi

    headers_file="${workdir}/websocket-headers-${target}"
    printf 'Checking %s public WebSocket upgrade...\n' "${target}"
    for _attempt in 1 2 3; do
        : >"${headers_file}"
        set +e
        curl --noproxy '*' --http1.1 -sS --connect-timeout 3 --max-time 5 \
            -o /dev/null -D "${headers_file}" \
            -H 'Connection: Upgrade' \
            -H 'Upgrade: websocket' \
            -H 'Sec-WebSocket-Version: 13' \
            -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
            "${target_ws_url}" 2>/dev/null
        curl_status=$?
        set -e
        if [[ "${curl_status}" -eq 0 || "${curl_status}" -eq 28 ]] &&
           grep -q '^HTTP/1.1 101 ' "${headers_file}"; then
            return 0
        fi
        sleep 1
    done

    printf '%s public WebSocket upgrade failed (last curl status %s).\n' \
        "${target}" "${curl_status}" >&2
    cat "${headers_file}" >&2
    return 1
}

printf 'Preparing release deployment of Hexproof server %s on: %s\n' \
    "${version}" "${targets[*]}"

printf '%s\n' 'Checking every target before downloading or changing anything...'
for target in "${targets[@]}"; do
    target_config "${target}"

    remote_machine="$(run_ssh "${target}" uname -m)"
    if [[ -n "${requested_arch}" ]]; then
        target_arch="${requested_arch}"
    else
        case "${remote_machine}" in
            x86_64 | amd64) target_arch="amd64" ;;
            aarch64 | arm64) target_arch="arm64" ;;
            *)
                printf 'Unsupported architecture on %s: %s\n' \
                    "${target}" "${remote_machine}" >&2
                exit 1
                ;;
        esac
    fi
    case "${target_arch}:${remote_machine}" in
        amd64:x86_64 | amd64:amd64 | arm64:aarch64 | arm64:arm64) ;;
        *)
            printf 'Architecture %s does not match %s (%s).\n' \
                "${target_arch}" "${target}" "${remote_machine}" >&2
            exit 1
            ;;
    esac
    target_arches["${target}"]="${target_arch}"
    target_build_dirs["${target}"]="${target_app_root}/staging/server-release-${version}-${timestamp}"
    target_staged_binaries["${target}"]="${target_build_dirs[${target}]}/hexproof-server"
    target_new_binaries["${target}"]="${target_binary}.new-v${version}-${timestamp}"
    target_backups["${target}"]="${target_backup_dir}/hexproof-server.rollback-${timestamp}-before-v${version}"

    printf '  preflight: %s (%s)\n' "${target}" "${target_arch}"
    run_ssh "${target}" bash -s -- preflight \
        "${target_service}" "${target_binary}" "${target_app_root}" \
        "${target_use_sudo}" "${target_build_dirs[${target}]}" \
        "${target_new_binaries[${target}]}" "${target_backups[${target}]}" <<'REMOTE_PREFLIGHT'
set -euo pipefail

mode="$1"
service="$2"
binary="$3"
app_root="$4"
use_sudo="$5"
build_dir="$6"
new_binary="$7"
backup="$8"

[[ "${mode}" == "preflight" ]]

run_systemctl() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n systemctl "$@"
    else
        systemctl "$@"
    fi
}

active_service_binary() {
    local main_pid
    main_pid="$(run_systemctl show "${service}" -p MainPID --value)"
    if [[ ! "${main_pid}" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Service %s has no active main process.\n' "${service}" >&2
        return 1
    fi
    readlink -f -- "/proc/${main_pid}/exe"
}

verify_active_service_binary() {
    local actual expected
    actual="$(active_service_binary)" || return 1
    expected="$(readlink -f -- "${binary}")"
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'Service %s runs %s, expected %s.\n' \
            "${service}" "${actual}" "${expected}" >&2
        return 1
    fi
}

[[ "$(uname -s)" == "Linux" ]]
for command_name in bash uname dirname install chmod curl sha256sum awk cp mv rm \
    readlink sleep systemctl; do
    command -v "${command_name}" >/dev/null 2>&1 || {
        printf 'Required remote command not found: %s\n' "${command_name}" >&2
        exit 1
    }
done
if [[ "${use_sudo}" == "1" ]]; then
    command -v sudo >/dev/null 2>&1 || {
        printf 'Required remote command not found: sudo\n' >&2
        exit 1
    }
    sudo -n true
fi
run_systemctl is-active --quiet "${service}"
test -x "${binary}"
verify_active_service_binary
test -w "$(dirname -- "${binary}")"
test -d "${app_root}"
test -w "${app_root}"
test -d "${app_root}/staging"
test -w "${app_root}/staging"
test -d "${app_root}/backups"
test -w "$(dirname -- "${backup}")"
test ! -e "${build_dir}"
test ! -e "${new_binary}"
test ! -e "${backup}"
REMOTE_PREFLIGHT
done

# Draft assets require authentication. Reuse the home backend's pinned release,
# checksum, GitHub digest and attestation verification before any remote write.
asset_dir="${workdir}"
if [[ "${HEXPROOF_ALLOW_DRAFT:-0}" == "1" ]]; then
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    python3 - "${script_dir}" "${repo_slug}" "${version}" "${workdir}" "${target_arches[@]}" <<'PYTHON'
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("release_backend", Path(sys.argv[1]) / "deploy-home-release.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
release = backend.fetch_release(sys.argv[2], sys.argv[3], True, set(sys.argv[5:]), Path(sys.argv[4]))
print("Verified authenticated release v" + release["version"] + " at " + release["sourceCommit"], flush=True)
PYTHON
    asset_dir="${workdir}/assets"
fi

# Download and verify each required architecture once.
declare -A local_archives=()
for target in "${targets[@]}"; do
    target_arch="${target_arches[${target}]}"
    asset="hexproof-server-${version}-linux-${target_arch}.tar.gz"
    if [[ -n "${local_archives[${asset}]:-}" ]]; then
        continue
    fi
    if [[ ! -f "${asset_dir}/SHA256SUMS" ]]; then
        printf 'Downloading release checksums...\n'
        download --max-time 120 -o "${asset_dir}/SHA256SUMS" \
            "${base_url}/SHA256SUMS"
    fi
    printf 'Downloading and verifying %s...\n' "${asset}"
    if [[ "${HEXPROOF_ALLOW_DRAFT:-0}" == "0" ]]; then
        download --max-time 300 -o "${asset_dir}/${asset}" "${base_url}/${asset}"
    fi
    (
        cd "${asset_dir}"
        mapfile -t checksum_lines < <(
            awk -v name="${asset}" '$2 == name { print }' SHA256SUMS
        )
        if [[ "${#checksum_lines[@]}" -ne 1 ]]; then
            printf 'Expected exactly one checksum for %s.\n' "${asset}" >&2
            exit 1
        fi
        printf '%s\n' "${checksum_lines[0]}" | sha256sum -c -
    )
    tar -xzf "${asset_dir}/${asset}" -C "${workdir}"
    test -x "${workdir}/hexproof-server-${version}-linux-${target_arch}/bin/hexproof-server"
    local_archives["${asset}"]="1"
done

# Stage and validate every changed target before restarting any service.
for target in "${targets[@]}"; do
    target_config "${target}"
    target_arch="${target_arches[${target}]}"
    package_root="hexproof-server-${version}-linux-${target_arch}"
    local_binary="${workdir}/${package_root}/bin/hexproof-server"
    expected_sha256="$(sha256sum "${local_binary}" | awk '{print $1}')"

    if run_ssh "${target}" bash -s -- check-current \
        "${target_binary}" "${expected_sha256}" "${version}" <<'REMOTE_CURRENT'
set -euo pipefail
mode="$1"
binary="$2"
expected_sha256="$3"
version="$4"
[[ "${mode}" == "check-current" ]]
actual_sha256="$(sha256sum "${binary}" | awk '{print $1}')" || exit 10
reported_version="$("${binary}" -version 2>/dev/null)" || exit 10
[[ "${actual_sha256}" == "${expected_sha256}" &&
   "${reported_version}" == "hexproof-server ${version}" ]] || exit 10
REMOTE_CURRENT
    then
        printf 'Already current on %s; skipping upload and restart.\n' "${target}"
        target_up_to_date["${target}"]="1"
        continue
    else
        current_status=$?
        if [[ "${current_status}" -ne 10 ]]; then
            printf 'Could not inspect the installed binary on %s.\n' "${target}" >&2
            exit "${current_status}"
        fi
    fi

    printf 'Staging the release build on %s...\n' "${target}"
    # Mark the deterministic path before connecting so an interrupted SSH
    # response still triggers best-effort cleanup of a directory created remotely.
    staging_created["${target}"]="1"
    run_ssh "${target}" bash -s -- prepare-stage \
        "${target_build_dirs[${target}]}" "${target_app_root}" <<'REMOTE_PREPARE'
set -euo pipefail
mode="$1"
build_dir="$2"
app_root="$3"
[[ "${mode}" == "prepare-stage" ]]
[[ "${build_dir}" == "${app_root}/staging/server-release-"* ]]
install -d -m 0700 "${build_dir}"
REMOTE_PREPARE

    run_scp -q "${local_binary}" \
        "${target}:${target_staged_binaries[${target}]}"
    run_ssh "${target}" bash -s -- verify-stage \
        "${target_staged_binaries[${target}]}" "${expected_sha256}" \
        "${version}" <<'REMOTE_STAGE'
set -euo pipefail
mode="$1"
staged_binary="$2"
expected_sha256="$3"
version="$4"
[[ "${mode}" == "verify-stage" ]]
chmod 0700 "${staged_binary}"
actual_sha256="$(sha256sum "${staged_binary}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${expected_sha256}" ]]
reported_version="$("${staged_binary}" -version)"
if [[ "${reported_version}" != "hexproof-server ${version}" ]]; then
    printf 'Staged binary reported %s, expected hexproof-server %s.\n' \
        "${reported_version}" "${version}" >&2
    exit 1
fi
REMOTE_STAGE
    staged_targets+=("${target}")
done

# Activate only after every changed host has a verified staged binary.
for target in "${staged_targets[@]}"; do
    target_config "${target}"
    target_arch="${target_arches[${target}]}"
    local_binary="${workdir}/hexproof-server-${version}-linux-${target_arch}/bin/hexproof-server"
    expected_sha256="$(sha256sum "${local_binary}" | awk '{print $1}')"

    printf 'Activating the release build on %s...\n' "${target}"
    if ! run_ssh "${target}" bash -s -- activate \
        "${target_service}" "${target_binary}" "${target_use_sudo}" \
        "${target_build_dirs[${target}]}" "${target_staged_binaries[${target}]}" \
        "${expected_sha256}" "${target_new_binaries[${target}]}" \
        "${target_backups[${target}]}" "${version}" <<'REMOTE_ACTIVATE'
set -euo pipefail

mode="$1"
service="$2"
binary="$3"
use_sudo="$4"
build_dir="$5"
staged_binary="$6"
expected_sha256="$7"
new_binary="$8"
backup="$9"
version="${10}"

[[ "${mode}" == "activate" ]]

run_systemctl() {
    if [[ "${use_sudo}" == "1" ]]; then
        sudo -n systemctl "$@"
    else
        systemctl "$@"
    fi
}

verify_active_service_binary() {
    local main_pid actual expected
    main_pid="$(run_systemctl show "${service}" -p MainPID --value)"
    [[ "${main_pid}" =~ ^[1-9][0-9]*$ ]] || return 1
    actual="$(readlink -f -- "/proc/${main_pid}/exe")"
    expected="$(readlink -f -- "${binary}")"
    [[ "${actual}" == "${expected}" ]]
}

wait_for_local_health() {
    # Forge probes its card database before the hub binds its HTTP listener.
    local attempt=1 health_deadline=$((SECONDS + 120))
    while [[ "${attempt}" -le 240 && "${SECONDS}" -lt "${health_deadline}" ]]; do
        if run_systemctl is-active --quiet "${service}" &&
           verify_active_service_binary &&
           curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
               http://127.0.0.1:57320/healthz >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done
    return 1
}

cleanup() {
    rm -rf -- "${build_dir}"
    rm -f -- "${new_binary}"
}
trap cleanup EXIT

actual_sha256="$(sha256sum "${staged_binary}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${expected_sha256}" ]]
reported_version="$("${staged_binary}" -version)"
[[ "${reported_version}" == "hexproof-server ${version}" ]]

install -m 0755 "${staged_binary}" "${new_binary}"
cp -a "${binary}" "${backup}"
mv "${new_binary}" "${binary}"

if ! run_systemctl restart "${service}" || ! wait_for_local_health; then
    printf 'Activation failed; restoring %s\n' "${backup}" >&2
    cp -a "${backup}" "${new_binary}"
    mv "${new_binary}" "${binary}"
    if ! run_systemctl restart "${service}" || ! wait_for_local_health; then
        printf 'Rollback health check failed for %s\n' "${service}" >&2
    fi
    exit 1
fi

sha256sum "${binary}"
"${binary}" -version
run_systemctl show "${service}" \
    -p MainPID -p ExecMainStartTimestamp --no-pager
printf 'Rollback binary: %s\n' "${backup}"
REMOTE_ACTIVATE
    then
        printf 'Activation failed on %s; rolling back this deployment.\n' \
            "${target}" >&2
        rollback_activated_targets || true
        exit 1
    fi
    activated_targets+=("${target}")
done

# Public checks are part of the transaction. Retry transient failures before
# restoring every host activated by this invocation.
for target in "${targets[@]}"; do
    if ! check_public_target "${target}"; then
        printf 'Public verification failed on %s; rolling back this deployment.\n' \
            "${target}" >&2
        rollback_activated_targets || true
        exit 1
    fi
done

# Prune backups only after the complete fleet and every public endpoint pass.
if [[ "${backup_keep}" != "0" ]]; then
    for target in "${activated_targets[@]}"; do
        target_config "${target}"
        if ! run_ssh "${target}" bash -s -- prune-backups \
            "${target_backup_dir}" "${backup_keep}" <<'REMOTE_PRUNE'
set -euo pipefail
mode="$1"
backup_dir="$2"
keep="$3"
[[ "${mode}" == "prune-backups" ]]
[[ "${keep}" =~ ^[1-9][0-9]*$ ]]
shopt -s nullglob
backups=("${backup_dir}"/hexproof-server.rollback-*)
excess=$((${#backups[@]} - keep))
if ((excess > 0)); then
    for ((index = 0; index < excess; index++)); do
        rm -f -- "${backups[${index}]}"
    done
fi
REMOTE_PRUNE
        then
            printf 'Warning: could not prune old backups on %s.\n' \
                "${target}" >&2
        fi
    done
fi

deployment_complete="1"
printf 'Deployment complete: release v%s is current on %s (%s activated, %s unchanged).\n' \
    "${version}" "${targets[*]}" "${#activated_targets[@]}" \
    "${#target_up_to_date[@]}"
install_local_monitoring
