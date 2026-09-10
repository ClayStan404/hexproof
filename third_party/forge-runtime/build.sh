#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
# shellcheck source=VERSIONS.env
source "${script_dir}/VERSIONS.env"

source_dir="${HEXPROOF_FORGE_SOURCE_DIR:-${repo_root}/build/forge-runtime/source-${MANABREW_REVISION}-patch${HEXPROOF_FORGE_PATCH_REVISION}}"
output_dir="${HEXPROOF_FORGE_OUTPUT_DIR:-${repo_root}/build/forge-runtime}"
[[ "${source_dir}" == /* ]] || source_dir="${PWD}/${source_dir}"
[[ "${output_dir}" == /* ]] || output_dir="${PWD}/${output_dir}"
archive="${output_dir}/hexproof-forge-runtime-${MANABREW_REVISION}.tar.gz"
patches_dir="${script_dir}/patches"
source_bundle=""
if [[ "${1:-}" == --from-source && "$#" == 2 ]]; then
    source_bundle="$(cd -- "$2" && pwd)"
elif [[ "$#" != 0 ]]; then
    printf 'Usage: %s [--from-source EXTRACTED_SOURCE_PACKAGE]\n' "$0" >&2
    exit 1
fi

for command_name in git node python3 java javac javap jar mvn tar grep sha256sum; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Missing Forge runtime build dependency: %s\n' "${command_name}" >&2
        exit 1
    fi
done
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else "Forge source packaging requires Python 3.12+")'
if [[ -z "${source_bundle}" ]] && ! command -v cargo >/dev/null 2>&1; then
    printf 'Missing Forge runtime build dependency: cargo\n' >&2
    exit 1
fi

node --test "${patches_dir}/source.test.mjs"
node "${patches_dir}/manage-source.mjs" verify "${source_dir}" \
    "${MANABREW_REVISION}" "${FORGE_REVISION}" "${HEXPROOF_FORGE_PATCH_REVISION}"

mkdir -p "$(dirname -- "${source_dir}")" "${output_dir}"
if [[ -n "${source_bundle}" ]]; then
    python3 "${script_dir}/source-package.py" verify --source "${source_bundle}" \
        --output "${output_dir}"
    # Never compile inside the supplied archive or overwrite an owner's checkout.
    # Retain the isolated rebuild tree for diagnosis and incremental inspection.
    source_dir="$(mktemp -d "${output_dir}/rebuild-source.XXXXXX")"
    cp -a "${source_bundle}/manabrew/." "${source_dir}/"
else
source_created=false
if [[ ! -d "${source_dir}/.git" ]]; then
    if [[ -e "${source_dir}" ]]; then
        printf 'Forge source path exists but is not a Git checkout: %s\n' "${source_dir}" >&2
        exit 1
    fi
    git clone --filter=blob:none --no-checkout \
        "${MANABREW_REPOSITORY}" "${source_dir}"
    source_created=true
fi

actual_origin="$(git -C "${source_dir}" remote get-url origin)"
if [[ "${actual_origin%.git}" != "${MANABREW_REPOSITORY%.git}" ]]; then
    printf 'Unexpected Forge harness origin: %s\n' "${actual_origin}" >&2
    exit 1
fi

source_state=clean
if [[ "${source_created}" != true ]]; then
    source_state="$(node "${patches_dir}/manage-source.mjs" preflight "${source_dir}" \
        "${MANABREW_REVISION}" "${FORGE_REVISION}" "${HEXPROOF_FORGE_PATCH_REVISION}")"
fi

git -C "${source_dir}" fetch --depth 1 origin "${MANABREW_REVISION}"
if [[ "${source_state}" != patched ]]; then
    node "${patches_dir}/checkout-source.mjs" "${source_dir}" "${MANABREW_REVISION}"
fi
git -C "${source_dir}" submodule sync -- forge
# Submodule update has no --no-overwrite-ignore option. For an existing checkout,
# fetch and safely switch it first; update then only confirms the pinned gitlink.
if [[ -e "${source_dir}/forge/.git" ]]; then
    git -C "${source_dir}/forge" fetch --depth 1 origin "${FORGE_REVISION}"
    node "${patches_dir}/checkout-source.mjs" "${source_dir}/forge" "${FORGE_REVISION}"
fi
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

node "${patches_dir}/manage-source.mjs" apply "${source_dir}" \
    "${MANABREW_REVISION}" "${FORGE_REVISION}" "${HEXPROOF_FORGE_PATCH_REVISION}"
fi

protocol_mode=regenerate
[[ -z "${source_bundle}" ]] || protocol_mode=bundled
dependency_arguments=(--source "${source_dir}" --output "${output_dir}/source-downloads")
[[ -z "${source_bundle}" ]] || dependency_arguments+=(--preserved-source "${source_bundle}")
python3 "${script_dir}/source-package.py" prepare-dependencies "${dependency_arguments[@]}"
bash "${script_dir}/build-harness.sh" "${source_dir}" "${protocol_mode}"
dependencies_file="${source_dir}/target/hexproof-runtime-dependencies.txt"
if [[ -n "${source_bundle}" ]]; then
    python3 "${script_dir}/source-package.py" check-dependencies \
        --source "${source_bundle}" --dependencies "${dependencies_file}"
fi

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
cp -a "${patches_dir}" "${package_root}/hexproof-patches"
cp "${source_dir}/LICENSE-AGPL-3.0-or-later" "${package_root}/"
cp "${source_dir}/LICENSE-GPL-3.0-or-later" "${package_root}/"
cp "${source_dir}/LICENSE.md" "${package_root}/MANABREW-LICENSE.md"
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

# Run the downstream real-engine regressions against the final JAR and complete
# packaged resources, not just upstream's narrower source-only regression mains.
regression_classes="${stage_dir}/regression-classes"
mkdir -p "${regression_classes}" "${stage_dir}/regression-profile"
javac -cp "${package_root}/forge-harness.jar" -d "${regression_classes}" \
    "${patches_dir}/HexproofSessionRegressionTest.java" \
    "${script_dir}/XmlDependencyRegressionTest.java"
python3 "${script_dir}/source-package.py" verify-xmlpull-api --source "${package_root}/forge-harness.jar"
java -cp "${regression_classes}:${package_root}/forge-harness.jar" XmlDependencyRegressionTest
java -Xmx2g -Djava.awt.headless=true -Duser.home="${stage_dir}/regression-profile" \
    -cp "${regression_classes}:${package_root}/forge-harness.jar" \
    HexproofSessionRegressionTest "${package_root}/forge-gui"

probe_stdout="${stage_dir}/forge-probe.stdout"
probe_stderr="${stage_dir}/forge-probe.stderr"
if ! (
    cd "${package_root}"
    printf '%s\n%s\n' '{"command":"reset"}' '{"command":"quit"}' |
        java -Djava.awt.headless=true -Duser.home="${stage_dir}/regression-profile" \
            -jar forge-harness.jar \
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

if [[ -n "${source_bundle}" ]]; then
    source_archive="$(python3 "${script_dir}/source-package.py" repack \
        --source "${source_bundle}" --output "${output_dir}")"
else
    # Missing third-party source is a packaging failure, not a URL-only offer.
    python3 "${script_dir}/source-package.py" create --source "${source_dir}" \
        --output "${output_dir}" --dependencies "${dependencies_file}"
    source_archive="${output_dir}/hexproof-forge-source-${MANABREW_REVISION}-patch${HEXPROOF_FORGE_PATCH_REVISION}.tar.gz"
fi
python3 "${script_dir}/source-package.py" link-runtime \
    --source "${source_archive}" --runtime "${package_root}"
tar -C "${stage_dir}" -czf "${archive}" "$(basename -- "${package_root}")"
(
    cd "${output_dir}"
    sha256sum "$(basename -- "${archive}")" "$(basename -- "${source_archive}")" \
        > "hexproof-forge-${MANABREW_REVISION}-patch${HEXPROOF_FORGE_PATCH_REVISION}.sha256"
)
printf '%s\n' "${archive}"
