#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
# shellcheck source=VERSIONS.env
source "${script_dir}/VERSIONS.env"

source_dir="${HEXPROOF_FORGE_SOURCE_DIR:-${repo_root}/build/forge-runtime/source}"
output_dir="${HEXPROOF_FORGE_OUTPUT_DIR:-${repo_root}/build/forge-runtime}"
archive="${output_dir}/hexproof-forge-runtime-${MANABREW_REVISION}.tar.gz"

for command_name in git node cargo java jar mvn tar grep; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Missing Forge runtime build dependency: %s\n' "${command_name}" >&2
        exit 1
    fi
done

mkdir -p "$(dirname -- "${source_dir}")" "${output_dir}"
if [[ ! -d "${source_dir}/.git" ]]; then
    if [[ -e "${source_dir}" ]]; then
        printf 'Forge source path exists but is not a Git checkout: %s\n' "${source_dir}" >&2
        exit 1
    fi
    git clone --filter=blob:none --no-checkout \
        "${MANABREW_REPOSITORY}" "${source_dir}"
fi

actual_origin="$(git -C "${source_dir}" remote get-url origin)"
if [[ "${actual_origin%.git}" != "${MANABREW_REPOSITORY%.git}" ]]; then
    printf 'Unexpected Forge harness origin: %s\n' "${actual_origin}" >&2
    exit 1
fi

git -C "${source_dir}" fetch --depth 1 origin "${MANABREW_REVISION}"
git -C "${source_dir}" checkout --detach "${MANABREW_REVISION}"
git -C "${source_dir}" submodule sync -- forge
git -C "${source_dir}" submodule update --init --depth 1 -- forge

actual_manabrew="$(git -C "${source_dir}" rev-parse HEAD)"
actual_forge="$(git -C "${source_dir}/forge" rev-parse HEAD)"
if [[ "${actual_manabrew}" != "${MANABREW_REVISION}" ]]; then
    printf 'Manabrew revision mismatch: %s\n' "${actual_manabrew}" >&2
    exit 1
fi
if [[ "${actual_forge}" != "${FORGE_REVISION}" ]]; then
    printf 'Forge revision mismatch: %s\n' "${actual_forge}" >&2
    exit 1
fi

(
    cd "${source_dir}"
    node scripts/harness.mjs build
)

runtime_source="${source_dir}/src-tauri/resources/forge-runtime"
languages_source="${source_dir}/forge/forge-gui/res/languages"
deckgen_source="${source_dir}/forge/forge-gui/res/deckgendecks"
if [[ ! -f "${runtime_source}/forge-harness.jar" ||
      ! -d "${runtime_source}/forge-gui/res/cardsfolder" ||
      ! -f "${languages_source}/en-US.properties" ||
      ! -f "${deckgen_source}/Standard.raw.dat" ]]; then
    printf 'Upstream harness did not stage a complete Forge runtime.\n' >&2
    exit 1
fi

stage_dir="$(mktemp -d "${output_dir}/stage.XXXXXX")"
trap 'rm -rf -- "${stage_dir}"' EXIT
package_root="${stage_dir}/hexproof-forge-runtime"
mkdir -p "${package_root}"
cp -a "${runtime_source}/." "${package_root}/"
mkdir -p "${package_root}/forge-gui/res/languages"
cp -a "${languages_source}/." "${package_root}/forge-gui/res/languages/"
cp -a "${deckgen_source}" "${package_root}/forge-gui/res/"
cp "${script_dir}/VERSIONS.env" "${package_root}/"
cp "${source_dir}/LICENSE-AGPL-3.0-or-later" "${package_root}/"
cp "${source_dir}/LICENSE-GPL-3.0-or-later" "${package_root}/"
cp "${source_dir}/THIRD-PARTY-NOTICES.md" "${package_root}/MANABREW-NOTICES.md"

# Maven's jar-with-dependencies assembly keeps Tinylog's built-in Writer
# descriptor and drops Forge GUI's descriptor with the custom network writer.
# Merge the missing provider into the packaged JAR so headless startup does not
# emit a misleading service-resolution error.
tinylog_service="META-INF/services/org.tinylog.writers.Writer"
service_stage="${stage_dir}/tinylog-service"
mkdir -p "${service_stage}"
(
    cd "${service_stage}"
    jar --extract --file "${package_root}/forge-harness.jar" \
        "${tinylog_service}"
)
if [[ ! -f "${service_stage}/${tinylog_service}" ]]; then
    printf 'Forge harness JAR has no Tinylog writer service descriptor.\n' >&2
    exit 1
fi
if ! grep -Fqx 'forge.gamemodes.net.NetworkLogWriter' \
        "${service_stage}/${tinylog_service}"; then
    printf '%s\n' 'forge.gamemodes.net.NetworkLogWriter' \
        >>"${service_stage}/${tinylog_service}"
fi
jar --update --file "${package_root}/forge-harness.jar" \
    -C "${service_stage}" "${tinylog_service}"

probe_stdout="${stage_dir}/forge-probe.stdout"
probe_stderr="${stage_dir}/forge-probe.stderr"
if ! (
    cd "${package_root}"
    printf '%s\n%s\n' '{"command":"reset"}' '{"command":"quit"}' |
        java -jar forge-harness.jar \
            --interactive-server \
            --forge-home forge-gui \
            >"${probe_stdout}" 2>"${probe_stderr}"
); then
    printf 'Packaged Forge runtime failed its cold-start probe.\n' >&2
    cat "${probe_stderr}" >&2
    exit 1
fi
if ! grep -q '^{"ok":true' "${probe_stdout}"; then
    printf 'Packaged Forge runtime returned no successful reset response.\n' >&2
    cat "${probe_stdout}" >&2
    cat "${probe_stderr}" >&2
    exit 1
fi
if grep -Eq 'NullPointerException|LOGGER ERROR: Service implementation .network log. not found' \
        "${probe_stderr}"; then
    printf 'Packaged Forge runtime emitted a known initialization error.\n' >&2
    cat "${probe_stderr}" >&2
    exit 1
fi

tar -C "${stage_dir}" -czf "${archive}" "$(basename -- "${package_root}")"
printf '%s\n' "${archive}"
