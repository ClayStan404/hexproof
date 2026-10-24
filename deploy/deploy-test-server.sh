#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -Eeuo pipefail

# Build the current local server source for a maintained host, stage it separately
# from production, activate the loopback-only test process, and publish only
# its path-scoped endpoints through the existing TLS nginx listener.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
target="${HEXPROOF_TEST_TARGET:-}"
requested_version="${HEXPROOF_TEST_VERSION:-}"
provided_binary="${HEXPROOF_TEST_BINARY:-}"
backup_keep="${HEXPROOF_TEST_BACKUP_KEEP:-5}"

service="hexproof-test.service"
production_service="hexproof.service"
app_root="/var/lib/hexproof-test"
binary="/usr/local/bin/hexproof-server-test"
unit="/etc/systemd/system/${service}"
unit_source="${script_dir}/hexproof-test.service"
nginx_include="/etc/nginx/snippets/hexproof-test-locations.conf"
nginx_include_source="${script_dir}/hexproof-test-nginx.inc"
nginx_config="/etc/nginx/conf.d/hexproof-ip.conf"
port="57321"

ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=2
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=3
)

usage() {
    cat <<'EOF'
Usage: ./deploy/deploy-test-server.sh

Build the current local Hexproof server and deploy it to the test service on
the operator-configured test target. Production server paths, data, and the
hexproof.service unit are never modified. The test process listens only on
127.0.0.1:57321, enables player hosting, defaults to server Forge disabled,
and is exposed through the
existing TLS nginx listener at wss://hub.example.com/test/ws.
An explicitly installed test-only Forge runtime drop-in survives deployments.
Enable it separately with HEXPROOF_FORGE_SCOPE=test deploy/deploy-forge-runtime.sh.

Environment overrides:
  HEXPROOF_TEST_TARGET=cloud-b         Configured test-enabled SSH target
  HEXPROOF_TEST_VERSION=1.0.3          Server version (default: source version)
  HEXPROOF_TEST_BINARY=/path/server    Reuse a Linux binary instead of building
  HEXPROOF_TEST_BACKUP_KEEP=5          Successful deployment backups to retain;
                                       use 0 to disable automatic pruning

Publish the test endpoint separately through the online server directory.
The endpoint follows the configured public origin, for example:
  wss://hub.example.com/test/ws
EOF
}

run_ssh() {
    # Callers intentionally expand the local argument array for the remote command.
    # shellcheck disable=SC2029
    ssh "${ssh_options[@]}" "${target}" "$@"
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
if [[ -z "${target}" ]]; then
    target="$(python3 "${script_dir}/operator_config.py" defaults testTarget)" || exit 2
fi
settings="$(python3 "${script_dir}/operator_config.py" cloud "${target}" test)" || exit 2
mapfile -t target_values <<<"${settings}"
public_host="${target_values[2]}"
public_health_url="${target_values[0]}/test/healthz"
public_ws_url="wss://${public_host}/test/ws"
if [[ ! "${backup_keep}" =~ ^[0-9]+$ ]]; then
    printf 'HEXPROOF_TEST_BACKUP_KEEP must be a non-negative integer, got: %s\n' \
        "${backup_keep}" >&2
    exit 2
fi

for command_name in ssh scp curl sha256sum mktemp grep sed date awk rm uname cp chmod sleep; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Required local command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
done
if [[ ! -f "${unit_source}" ]]; then
    printf 'Test service unit not found: %s\n' "${unit_source}" >&2
    exit 1
fi
if [[ ! -f "${nginx_include_source}" ]]; then
    printf 'Test nginx include not found: %s\n' "${nginx_include_source}" >&2
    exit 1
fi
if ! grep -Fqx 'Environment="HEXPROOF_FORGE_HARNESS="' "${unit_source}" ||
   ! grep -Fqx 'Environment="HEXPROOF_FORGE_HOME="' "${unit_source}"; then
    printf 'Test service unit must default to Forge disabled through empty environment settings.\n' >&2
    exit 1
fi
if ! grep -Fq 'proxy_pass http://127.0.0.1:57321/ws;' \
        "${nginx_include_source}" ||
   ! grep -Fq 'proxy_pass http://127.0.0.1:57321/healthz;' \
        "${nginx_include_source}"; then
    printf 'Test nginx include must proxy only the test service endpoints.\n' >&2
    exit 1
fi

if [[ -z "${requested_version}" ]]; then
    requested_version="$(
        sed -nE \
            's/^[[:space:]]*set\(HEXPROOF_VERSION[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*\)[[:space:]]*$/\1/p' \
            "${repo_root}/apps/client-qt/CMakeLists.txt"
    )"
fi
version="${requested_version#v}"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Test server version must use MAJOR.MINOR.PATCH, got: %s\n' \
        "${requested_version}" >&2
    exit 2
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
workdir="$(mktemp -d)"
local_binary="${workdir}/hexproof-server-test"
stage_dir=""
deployment_complete="0"

check_public_test() {
    local attempt curl_status headers_file="${workdir}/test-websocket-headers"

    for attempt in {1..10}; do
        if curl -fsS --connect-timeout 2 --max-time 3 \
            "${public_health_url}" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    if [[ "${attempt}" == "10" ]] &&
       ! curl -fsS --connect-timeout 2 --max-time 3 \
           "${public_health_url}" >/dev/null 2>&1; then
        printf 'Public test health endpoint is unavailable: %s\n' \
            "${public_health_url}" >&2
        return 1
    fi

    for attempt in {1..10}; do
        : >"${headers_file}"
        set +e
        curl -sS --connect-timeout 2 --max-time 3 -D "${headers_file}" \
            -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
            -H 'Sec-WebSocket-Version: 13' \
            -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
            "https://${public_host}/test/ws" 2>/dev/null
        curl_status=$?
        set -e
        if [[ "${curl_status}" == "0" || "${curl_status}" == "28" ]] &&
           grep -q '^HTTP/1.1 101 ' "${headers_file}"; then
            return 0
        fi
        sleep 0.5
    done
    printf 'Public test WebSocket endpoint is unavailable: %s\n' \
        "${public_ws_url}" >&2
    return 1
}

rollback_test_deployment() {
    run_ssh bash -s -- rollback-deployment "${backup_dir}" "${app_root}" \
        "${service}" "${binary}" "${unit}" "${port}" "${nginx_config}" \
        "${nginx_include}" <<'REMOTE_ROLLBACK'
set -euo pipefail
mode="$1"
backup_dir="$2"
app_root="$3"
service="$4"
binary="$5"
unit="$6"
port="$7"
nginx_config="$8"
nginx_include="$9"

[[ "${mode}" == "rollback-deployment" ]]
[[ "${app_root}" == "/var/lib/hexproof-test" ]]
[[ "${backup_dir}" == "${app_root}/backups/test-deploy-"* ]]
[[ "${service}" == "hexproof-test.service" ]]
[[ "${binary}" == "/usr/local/bin/hexproof-server-test" ]]
[[ "${unit}" == "/etc/systemd/system/hexproof-test.service" ]]
[[ "${port}" == "57321" ]]
[[ "${nginx_config}" == "/etc/nginx/conf.d/hexproof-ip.conf" ]]
[[ "${nginx_include}" == "/etc/nginx/snippets/hexproof-test-locations.conf" ]]

service_state="${backup_dir}/service-state"
proxy_state="${backup_dir}/proxy-state"
test -f "${service_state}"
read -r had_binary had_unit was_enabled was_active <"${service_state}"
for value in "${had_binary}" "${had_unit}" "${was_enabled}" "${was_active}"; do
    [[ "${value}" == "0" || "${value}" == "1" ]]
done

rollback_failed=0
if [[ -f "${proxy_state}" ]]; then
    read -r had_include <"${proxy_state}"
    [[ "${had_include}" == "0" || "${had_include}" == "1" ]]
    restored_config="${nginx_config}.rollback"
    restored_include="${nginx_include}.rollback"
    rm -f -- "${restored_config}" "${restored_include}"
    cp -a -- "${backup_dir}/hexproof-ip.conf" \
        "${restored_config}" || rollback_failed=1
    mv -f -- "${restored_config}" "${nginx_config}" || rollback_failed=1
    if [[ "${had_include}" == "1" ]]; then
        cp -a -- "${backup_dir}/hexproof-test-locations.conf" \
            "${restored_include}" || rollback_failed=1
        mv -f -- "${restored_include}" "${nginx_include}" || rollback_failed=1
    else
        rm -f -- "${nginx_include}" || rollback_failed=1
    fi
    nginx -t >/dev/null 2>&1 || rollback_failed=1
    systemctl reload nginx.service || rollback_failed=1
fi

restored_binary="${binary}.rollback"
restored_unit="${unit}.rollback"
rm -f -- "${restored_binary}" "${restored_unit}"
systemctl stop "${service}" >/dev/null 2>&1 || true
if [[ "${had_binary}" == "1" ]]; then
    cp -a -- "${backup_dir}/hexproof-server-test" \
        "${restored_binary}" || rollback_failed=1
    mv -f -- "${restored_binary}" "${binary}" || rollback_failed=1
else
    rm -f -- "${binary}" || rollback_failed=1
fi
if [[ "${had_unit}" == "1" ]]; then
    cp -a -- "${backup_dir}/hexproof-test.service" \
        "${restored_unit}" || rollback_failed=1
    mv -f -- "${restored_unit}" "${unit}" || rollback_failed=1
else
    rm -f -- "${unit}" || rollback_failed=1
fi
systemctl daemon-reload || rollback_failed=1
if [[ "${was_enabled}" == "1" ]]; then
    systemctl enable "${service}" >/dev/null 2>&1 || rollback_failed=1
else
    systemctl disable "${service}" >/dev/null 2>&1 || true
fi
if [[ "${was_active}" == "1" ]]; then
    systemctl restart "${service}" || rollback_failed=1
    healthy=0
    health_deadline=$((SECONDS + 60))
    while ((SECONDS < health_deadline)); do
        if systemctl is-active --quiet "${service}" &&
           curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
               "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            healthy=1
            break
        fi
        sleep 0.5
    done
    [[ "${healthy}" == "1" ]] || rollback_failed=1
else
    systemctl stop "${service}" >/dev/null 2>&1 || true
fi

exit "${rollback_failed}"
REMOTE_ROLLBACK
}

cleanup() {
    local status=$?

    trap - EXIT
    if [[ "${deployment_complete}" != "1" && -n "${stage_dir}" ]]; then
        run_ssh bash -s -- cleanup-staging "${stage_dir}" \
            "${app_root}" <<'REMOTE_CLEANUP' >/dev/null 2>&1 || true
set -euo pipefail
mode="$1"
stage_dir="$2"
app_root="$3"
[[ "${mode}" == "cleanup-staging" ]]
[[ "${app_root}" == "/var/lib/hexproof-test" ]]
[[ "${stage_dir}" == "${app_root}/staging/test-deploy-"* ]]
rm -f -- "${stage_dir}/hexproof-server-test" "${stage_dir}/hexproof-test.service" \
    "${stage_dir}/hexproof-test-nginx.inc" "${stage_dir}/websocket-headers"
rmdir -- "${stage_dir}"
REMOTE_CLEANUP
    fi
    rm -f -- "${workdir}/hexproof-server-test" "${workdir}/test-websocket-headers"
    rmdir -- "${workdir}"
    exit "${status}"
}
trap cleanup EXIT

host_facts="$(run_ssh bash -s -- inspect-host <<'REMOTE_INSPECT'
set -euo pipefail
[[ "$1" == "inspect-host" ]]
source /etc/os-release
printf '%s %s %s\n' "$(uname -s)" "${ID}" "$(uname -m)"
REMOTE_INSPECT
)"
read -r remote_system remote_os remote_machine <<<"${host_facts}"
if [[ "${remote_system}" != "Linux" || -z "${remote_os}" ]]; then
    printf 'Unsupported remote operating system on %s: %s\n' \
        "${target}" "${host_facts}" >&2
    exit 1
fi
case "${remote_machine}" in
    x86_64 | amd64) remote_arch="amd64" ;;
    aarch64 | arm64) remote_arch="arm64" ;;
    *)
        printf 'Unsupported remote architecture on %s: %s\n' \
            "${target}" "${remote_machine}" >&2
        exit 1
        ;;
esac
printf 'Isolated test host: %s (%s, linux/%s)\n' \
    "${target}" "${remote_os}" "${remote_arch}"

if [[ -n "${provided_binary}" ]]; then
    if [[ ! -f "${provided_binary}" ]]; then
        printf 'HEXPROOF_TEST_BINARY does not exist: %s\n' \
            "${provided_binary}" >&2
        exit 1
    fi
    cp -- "${provided_binary}" "${local_binary}"
    chmod 0755 "${local_binary}"
else
    if ! command -v go >/dev/null 2>&1; then
        printf 'Required local command not found: go\n' >&2
        exit 1
    fi
    printf 'Building Hexproof test server %s for linux/%s...\n' \
        "${version}" "${remote_arch}"
    (
        cd "${repo_root}/apps/server"
        CGO_ENABLED=0 GOOS=linux GOARCH="${remote_arch}" \
            go build -trimpath \
            -ldflags "-X hexproof/server/internal/buildinfo.Version=${version}" \
            -o "${local_binary}" ./cmd/hexproof-server
    )
fi

local_machine="$(uname -m)"
case "${local_machine}" in
    x86_64 | amd64) local_arch="amd64" ;;
    aarch64 | arm64) local_arch="arm64" ;;
    *) local_arch="unknown" ;;
esac
if [[ "${local_arch}" == "${remote_arch}" ]]; then
    reported_version="$("${local_binary}" -version)"
    if [[ "${reported_version}" != "hexproof-server ${version}" ]]; then
        printf 'Test binary reported %s, expected hexproof-server %s.\n' \
            "${reported_version}" "${version}" >&2
        exit 1
    fi
fi

binary_sha256="$(sha256sum "${local_binary}" | awk '{print $1}')"
unit_sha256="$(sha256sum "${unit_source}" | awk '{print $1}')"
nginx_include_sha256="$(sha256sum "${nginx_include_source}" | awk '{print $1}')"
deployment_id="${version}-${binary_sha256:0:12}"
stage_dir="${app_root}/staging/test-deploy-${deployment_id}-${timestamp}"
backup_dir="${app_root}/backups/test-deploy-${timestamp}-before-${deployment_id}"

if run_ssh bash -s -- check-current "${service}" "${binary}" "${unit}" \
    "${binary_sha256}" "${unit_sha256}" "${version}" "${port}" \
    "${nginx_include}" "${nginx_config}" "${nginx_include_sha256}" \
    "${public_host}" <<'REMOTE_CURRENT'
set -euo pipefail
mode="$1"
service="$2"
binary="$3"
unit="$4"
binary_sha256="$5"
unit_sha256="$6"
version="$7"
port="$8"
nginx_include="$9"
nginx_config="${10}"
nginx_include_sha256="${11}"
public_host="${12}"
[[ "${mode}" == "check-current" ]]
[[ "${service}" == "hexproof-test.service" ]]
[[ "${binary}" == "/usr/local/bin/hexproof-server-test" ]]
[[ "${unit}" == "/etc/systemd/system/hexproof-test.service" ]]
[[ "${nginx_include}" == "/etc/nginx/snippets/hexproof-test-locations.conf" ]]
[[ "${nginx_config}" == "/etc/nginx/conf.d/hexproof-ip.conf" ]]
[[ "${public_host}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]

current() {
    test -x "${binary}" || return 1
    test -f "${unit}" || return 1
    [[ "$(sha256sum "${binary}" | awk '{print $1}')" == "${binary_sha256}" ]] || return 1
    [[ "$(sha256sum "${unit}" | awk '{print $1}')" == "${unit_sha256}" ]] || return 1
    [[ "$("${binary}" -version)" == "hexproof-server ${version}" ]] || return 1
    grep -Fqx 'Environment="HEXPROOF_FORGE_HARNESS="' "${unit}" || return 1
    grep -Fqx 'Environment="HEXPROOF_FORGE_HOME="' "${unit}" || return 1
    test -f "${nginx_include}" || return 1
    [[ "$(sha256sum "${nginx_include}" | awk '{print $1}')" == "${nginx_include_sha256}" ]] || return 1
    [[ "$(grep -Fc "include ${nginx_include};" "${nginx_config}")" == "1" ]] || return 1
    nginx -t >/dev/null 2>&1 || return 1
    systemctl is-active --quiet nginx.service || return 1
    systemctl is-active --quiet "${service}" || return 1
    systemctl is-enabled --quiet "${service}" || return 1
    main_pid="$(systemctl show "${service}" -p MainPID --value)"
    [[ "${main_pid}" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$(readlink -f -- "/proc/${main_pid}/exe")" == "$(readlink -f -- "${binary}")" ]] || return 1
    curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
        "http://127.0.0.1:${port}/healthz" >/dev/null || return 1
    curl --noproxy '*' --resolve "${public_host}:443:127.0.0.1" \
        -fsS --connect-timeout 2 --max-time 3 \
        "https://${public_host}/test/healthz" >/dev/null || return 1
}
current || exit 10
REMOTE_CURRENT
then
    if ! check_public_test; then
        printf 'The installed isolated test service is current, but its public route failed.\n' >&2
        exit 1
    fi
    deployment_complete="1"
    printf 'Isolated test server %s is already current; no restart needed.\n' \
        "${deployment_id}"
    printf 'Test server URL: %s\n' "${public_ws_url}"
    exit 0
else
    current_status=$?
    if [[ "${current_status}" -ne 10 ]]; then
        printf 'Could not inspect the current isolated test service.\n' >&2
        exit "${current_status}"
    fi
fi

printf 'Preparing isolated test deployment %s...\n' "${deployment_id}"
run_ssh bash -s -- prepare-stage "${stage_dir}" "${app_root}" \
    "${production_service}" "${nginx_config}" <<'REMOTE_PREPARE'
set -euo pipefail
mode="$1"
stage_dir="$2"
app_root="$3"
production_service="$4"
nginx_config="$5"
[[ "${mode}" == "prepare-stage" ]]
[[ "${app_root}" == "/var/lib/hexproof-test" ]]
[[ "${stage_dir}" == "${app_root}/staging/test-deploy-"* ]]
[[ "${production_service}" == "hexproof.service" ]]
[[ "${nginx_config}" == "/etc/nginx/conf.d/hexproof-ip.conf" ]]

for command_name in bash install chmod curl sha256sum awk cp mv rm readlink \
    systemctl grep id sleep uname nginx; do
    command -v "${command_name}" >/dev/null 2>&1 || {
        printf 'Required remote command not found: %s\n' "${command_name}" >&2
        exit 1
    }
done
[[ "$(uname -s)" == "Linux" ]]
id hexproof >/dev/null 2>&1
systemctl is-active --quiet "${production_service}"
systemctl is-active --quiet nginx.service
test -f "${nginx_config}"
nginx -t >/dev/null
install -d -o hexproof -g hexproof -m 0750 "${app_root}"
install -d -o hexproof -g hexproof -m 0750 \
    "${app_root}/retained" "${app_root}/staging" "${app_root}/backups"
test ! -e "${stage_dir}"
install -d -m 0700 "${stage_dir}"
REMOTE_PREPARE

run_scp -q "${local_binary}" "${unit_source}" \
    "${nginx_include_source}" "${target}:${stage_dir}/"

run_ssh bash -s -- verify-stage "${stage_dir}" "${binary_sha256}" \
    "${unit_sha256}" "${nginx_include_sha256}" "${version}" <<'REMOTE_STAGE'
set -euo pipefail
mode="$1"
stage_dir="$2"
binary_sha256="$3"
unit_sha256="$4"
nginx_include_sha256="$5"
version="$6"
[[ "${mode}" == "verify-stage" ]]
[[ "${stage_dir}" == "/var/lib/hexproof-test/staging/test-deploy-"* ]]
staged_binary="${stage_dir}/hexproof-server-test"
staged_unit="${stage_dir}/hexproof-test.service"
staged_nginx_include="${stage_dir}/hexproof-test-nginx.inc"
test -f "${staged_binary}"
test -f "${staged_unit}"
test -f "${staged_nginx_include}"
chmod 0700 "${staged_binary}"
[[ "$(sha256sum "${staged_binary}" | awk '{print $1}')" == "${binary_sha256}" ]]
[[ "$(sha256sum "${staged_unit}" | awk '{print $1}')" == "${unit_sha256}" ]]
[[ "$(sha256sum "${staged_nginx_include}" | awk '{print $1}')" == "${nginx_include_sha256}" ]]
[[ "$("${staged_binary}" -version)" == "hexproof-server ${version}" ]]
grep -Fq -- '-bind 127.0.0.1' "${staged_unit}"
grep -Fq -- '-port 57321' "${staged_unit}"
grep -Fqx 'Environment="HEXPROOF_FORGE_HARNESS="' "${staged_unit}"
grep -Fqx 'Environment="HEXPROOF_FORGE_HOME="' "${staged_unit}"
grep -Fq 'proxy_pass http://127.0.0.1:57321/ws;' "${staged_nginx_include}"
grep -Fq 'proxy_pass http://127.0.0.1:57321/healthz;' "${staged_nginx_include}"
REMOTE_STAGE

if ! run_ssh bash -s -- activate "${stage_dir}" "${backup_dir}" \
    "${app_root}" "${service}" "${binary}" "${unit}" \
    "${binary_sha256}" "${unit_sha256}" "${version}" "${port}" \
    "${backup_keep}" <<'REMOTE_ACTIVATE'
set -euo pipefail
mode="$1"
stage_dir="$2"
backup_dir="$3"
app_root="$4"
service="$5"
binary="$6"
unit="$7"
binary_sha256="$8"
unit_sha256="$9"
version="${10}"
port="${11}"
backup_keep="${12}"

[[ "${mode}" == "activate" ]]
[[ "${app_root}" == "/var/lib/hexproof-test" ]]
[[ "${stage_dir}" == "${app_root}/staging/test-deploy-"* ]]
[[ "${backup_dir}" == "${app_root}/backups/test-deploy-"* ]]
[[ "${service}" == "hexproof-test.service" ]]
[[ "${binary}" == "/usr/local/bin/hexproof-server-test" ]]
[[ "${unit}" == "/etc/systemd/system/hexproof-test.service" ]]
[[ "${port}" == "57321" ]]
[[ "${backup_keep}" =~ ^[0-9]+$ ]]

staged_binary="${stage_dir}/hexproof-server-test"
staged_unit="${stage_dir}/hexproof-test.service"
new_binary="${binary}.new"
new_unit="${unit}.new"
install -d -m 0700 "${backup_dir}"
had_binary=0
had_unit=0
was_enabled=0
was_active=0
if [[ -e "${binary}" ]]; then
    cp -a -- "${binary}" "${backup_dir}/hexproof-server-test"
    had_binary=1
fi
if [[ -e "${unit}" ]]; then
    cp -a -- "${unit}" "${backup_dir}/hexproof-test.service"
    had_unit=1
fi
if systemctl is-enabled --quiet "${service}" 2>/dev/null; then
    was_enabled=1
fi
if systemctl is-active --quiet "${service}" 2>/dev/null; then
    was_active=1
fi
printf '%s %s %s %s\n' \
    "${had_binary}" "${had_unit}" "${was_enabled}" "${was_active}" \
    >"${backup_dir}/service-state"
chmod 0600 "${backup_dir}/service-state"

rollback() {
    local rollback_failed=0

    rm -f -- "${new_binary}" "${new_unit}"
    if [[ "${had_binary}" == "1" ]]; then
        cp -a -- "${backup_dir}/hexproof-server-test" "${new_binary}" || rollback_failed=1
        mv -f -- "${new_binary}" "${binary}" || rollback_failed=1
    else
        rm -f -- "${binary}"
    fi
    if [[ "${had_unit}" == "1" ]]; then
        cp -a -- "${backup_dir}/hexproof-test.service" "${new_unit}" || rollback_failed=1
        mv -f -- "${new_unit}" "${unit}" || rollback_failed=1
    else
        rm -f -- "${unit}"
    fi
    systemctl daemon-reload || rollback_failed=1
    if [[ "${was_enabled}" == "1" ]]; then
        systemctl enable "${service}" >/dev/null 2>&1 || rollback_failed=1
    else
        systemctl disable "${service}" >/dev/null 2>&1 || true
    fi
    if [[ "${was_active}" == "1" ]]; then
        systemctl restart "${service}" || rollback_failed=1
        wait_for_health || rollback_failed=1
    else
        systemctl stop "${service}" >/dev/null 2>&1 || true
    fi
    return "${rollback_failed}"
}

wait_for_health() {
    local deadline=$((SECONDS + 60)) main_pid actual_binary

    while ((SECONDS < deadline)); do
        if systemctl is-active --quiet "${service}" &&
           curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 \
               "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
            main_pid="$(systemctl show "${service}" -p MainPID --value)"
            if [[ "${main_pid}" =~ ^[1-9][0-9]*$ ]]; then
                actual_binary="$(readlink -f -- "/proc/${main_pid}/exe")"
                if [[ "${actual_binary}" == "$(readlink -f -- "${binary}")" ]]; then
                    return 0
                fi
            fi
        fi
        sleep 0.5
    done
    return 1
}

activate_new() {
    install -m 0755 "${staged_binary}" "${new_binary}" || return 1
    mv -f -- "${new_binary}" "${binary}" || return 1
    install -m 0644 "${staged_unit}" "${new_unit}" || return 1
    mv -f -- "${new_unit}" "${unit}" || return 1
    systemctl daemon-reload || return 1
    systemctl enable "${service}" >/dev/null || return 1
    systemctl restart "${service}" || return 1
    wait_for_health || return 1
    [[ "$(sha256sum "${binary}" | awk '{print $1}')" == "${binary_sha256}" ]] || return 1
    [[ "$(sha256sum "${unit}" | awk '{print $1}')" == "${unit_sha256}" ]] || return 1
    [[ "$("${binary}" -version)" == "hexproof-server ${version}" ]] || return 1
    grep -Fqx 'Environment="HEXPROOF_FORGE_HARNESS="' "${unit}" || return 1
    grep -Fqx 'Environment="HEXPROOF_FORGE_HOME="' "${unit}" || return 1
}

if ! activate_new; then
    printf 'Test server activation failed; restoring the previous test deployment.\n' >&2
    if ! rollback; then
        printf 'CRITICAL: Isolated test server rollback failed. Production was not modified.\n' >&2
    fi
    exit 1
fi

if [[ "${backup_keep}" == "0" ]]; then
    exit 0
fi
shopt -s nullglob
backups=("${app_root}/backups"/test-deploy-*)
excess=$((${#backups[@]} - backup_keep))
if ((excess > 0)); then
    for ((index = 0; index < excess; index++)); do
        [[ "${backups[${index}]}" == "${app_root}/backups/test-deploy-"* ]]
        for backup_file in hexproof-server-test hexproof-test.service service-state \
            hexproof-ip.conf hexproof-test-locations.conf proxy-state; do
            rm -f -- "${backups[${index}]}/${backup_file}"
        done
        rmdir -- "${backups[${index}]}" || \
            printf 'Preserved nonempty backup directory: %s\n' "${backups[${index}]}" >&2
    done
fi
REMOTE_ACTIVATE
then
    printf 'Isolated test deployment failed. Production service was not modified.\n' >&2
    exit 1
fi

if ! run_ssh bash -s -- configure-proxy "${stage_dir}" "${backup_dir}" \
    "${app_root}" "${nginx_config}" "${nginx_include}" \
    "${nginx_include_sha256}" "${public_host}" <<'REMOTE_PROXY'
set -euo pipefail
mode="$1"
stage_dir="$2"
backup_dir="$3"
app_root="$4"
nginx_config="$5"
nginx_include="$6"
nginx_include_sha256="$7"
public_host="$8"

[[ "${mode}" == "configure-proxy" ]]
[[ "${app_root}" == "/var/lib/hexproof-test" ]]
[[ "${stage_dir}" == "${app_root}/staging/test-deploy-"* ]]
[[ "${backup_dir}" == "${app_root}/backups/test-deploy-"* ]]
[[ "${nginx_config}" == "/etc/nginx/conf.d/hexproof-ip.conf" ]]
[[ "${nginx_include}" == "/etc/nginx/snippets/hexproof-test-locations.conf" ]]
[[ "${public_host}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]

staged_include="${stage_dir}/hexproof-test-nginx.inc"
new_include="${nginx_include}.new"
new_config="${nginx_config}.new"
test -f "${staged_include}"
test -f "${nginx_config}"
test -d "${backup_dir}"
[[ "$(sha256sum "${staged_include}" | awk '{print $1}')" == "${nginx_include_sha256}" ]]

cp -a -- "${nginx_config}" "${backup_dir}/hexproof-ip.conf"
had_include=0
if [[ -e "${nginx_include}" ]]; then
    cp -a -- "${nginx_include}" "${backup_dir}/hexproof-test-locations.conf"
    had_include=1
fi
printf '%s\n' "${had_include}" >"${backup_dir}/proxy-state"
chmod 0600 "${backup_dir}/proxy-state"

rollback_proxy() {
    local rollback_failed=0

    rm -f -- "${new_include}" "${new_config}"
    cp -a -- "${backup_dir}/hexproof-ip.conf" "${new_config}" || rollback_failed=1
    mv -f -- "${new_config}" "${nginx_config}" || rollback_failed=1
    if [[ "${had_include}" == "1" ]]; then
        cp -a -- "${backup_dir}/hexproof-test-locations.conf" \
            "${new_include}" || rollback_failed=1
        mv -f -- "${new_include}" "${nginx_include}" || rollback_failed=1
    else
        rm -f -- "${nginx_include}"
    fi
    nginx -t >/dev/null 2>&1 || rollback_failed=1
    systemctl reload nginx.service || rollback_failed=1
    return "${rollback_failed}"
}

configure_proxy() {
    local attempt include_count curl_status headers_file

    install -m 0644 "${staged_include}" "${new_include}" || return 1
    mv -f -- "${new_include}" "${nginx_include}" || return 1
    include_count="$(grep -Fc "include ${nginx_include};" "${nginx_config}")"
    if [[ "${include_count}" == "0" ]]; then
        awk -v include_line="    include ${nginx_include};" '
            /^[[:space:]]*listen[[:space:]]+443[[:space:]]+ssl;/ { tls = 1 }
            tls && !inserted && /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/ {
                print include_line
                print ""
                inserted = 1
            }
            { print }
            END { if (!inserted) exit 42 }
        ' "${nginx_config}" >"${new_config}" || return 1
        chmod 0644 "${new_config}" || return 1
        mv -f -- "${new_config}" "${nginx_config}" || return 1
    elif [[ "${include_count}" != "1" ]]; then
        return 1
    fi
    [[ "$(grep -Fc "include ${nginx_include};" "${nginx_config}")" == "1" ]] || return 1
    nginx -t >/dev/null || return 1
    systemctl reload nginx.service || return 1
    attempt=1
    while ! curl --noproxy '*' --resolve "${public_host}:443:127.0.0.1" \
        -fsS --connect-timeout 2 --max-time 3 \
        "https://${public_host}/test/healthz" >/dev/null 2>&1; do
        if [[ "${attempt}" -ge 20 ]]; then
            return 1
        fi
        sleep 0.1
        attempt=$((attempt + 1))
    done

    headers_file="${stage_dir}/websocket-headers"
    for attempt in {1..10}; do
        : >"${headers_file}"
        set +e
        curl --noproxy '*' --resolve "${public_host}:443:127.0.0.1" \
            -sS --connect-timeout 2 --max-time 3 -D "${headers_file}" \
            -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
            -H 'Sec-WebSocket-Version: 13' \
            -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
            "https://${public_host}/test/ws" 2>/dev/null
        curl_status=$?
        set -e
        if [[ "${curl_status}" == "0" || "${curl_status}" == "28" ]] &&
           grep -q '^HTTP/1.1 101 ' "${headers_file}"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

if ! configure_proxy; then
    printf 'Test nginx activation failed; restoring the previous proxy configuration.\n' >&2
    if ! rollback_proxy; then
        printf 'CRITICAL: Isolated test nginx rollback failed.\n' >&2
    fi
    exit 1
fi
REMOTE_PROXY
then
    printf 'Isolated test proxy deployment failed. The production /ws route was preserved.\n' >&2
    if ! rollback_test_deployment; then
        printf 'CRITICAL: Isolated test deployment rollback failed.\n' >&2
    fi
    exit 1
fi

if ! check_public_test; then
    printf 'Isolated test public verification failed; restoring the previous deployment.\n' >&2
    if ! rollback_test_deployment; then
        printf 'CRITICAL: Isolated test deployment rollback failed.\n' >&2
    fi
    exit 1
fi

run_ssh bash -s -- cleanup-staging "${stage_dir}" \
    "${app_root}" <<'REMOTE_FINAL_CLEANUP'
set -euo pipefail
mode="$1"
stage_dir="$2"
app_root="$3"
[[ "${mode}" == "cleanup-staging" ]]
[[ "${app_root}" == "/var/lib/hexproof-test" ]]
[[ "${stage_dir}" == "${app_root}/staging/test-deploy-"* ]]
rm -f -- "${stage_dir}/hexproof-server-test" "${stage_dir}/hexproof-test.service" \
    "${stage_dir}/hexproof-test-nginx.inc" "${stage_dir}/websocket-headers"
rmdir -- "${stage_dir}"
REMOTE_FINAL_CLEANUP

deployment_complete="1"
printf 'Isolated test deployment complete: %s is running on 127.0.0.1:%s.\n' \
    "${deployment_id}" "${port}"
printf 'Test server URL: %s\n' "${public_ws_url}"
