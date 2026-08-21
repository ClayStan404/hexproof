#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '%s\n' "This script must run on macOS." >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
source_version="$(
    sed -nE 's/^[[:space:]]*set\(HEXPROOF_VERSION[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*\)[[:space:]]*$/\1/p' \
        "${repo_root}/apps/client-qt/CMakeLists.txt"
)"
version="${HEXPROOF_VERSION:-${source_version}}"
arch="${HEXPROOF_ARCH:-$(uname -m)}"
deployment_target="${HEXPROOF_MACOS_DEPLOYMENT_TARGET:-12.0}"
build_dir="${repo_root}/build/package-macos"
output_dir="${HEXPROOF_OUTPUT_DIR:-${repo_root}/build/packages}"
server_directory_args=()
if [[ -n "${HEXPROOF_SERVER_DIRECTORY_FILE:-}" ]]; then
    server_directory_args+=(
        "-DHEXPROOF_SERVER_DIRECTORY_FILE=${HEXPROOF_SERVER_DIRECTORY_FILE}"
    )
fi

cmake -S "${repo_root}/apps/client-qt" -B "${build_dir}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
    -DHEXPROOF_VERSION_OVERRIDE="${version}" \
    "${server_directory_args[@]}"
cmake --build "${build_dir}" --config Release --target hexproof

mkdir -p "${build_dir}" "${output_dir}"
stage_dir="$(mktemp -d "${build_dir}/stage.XXXXXX")"
trap 'rm -rf -- "${stage_dir}"' EXIT
cmake --install "${build_dir}" --config Release --prefix "${stage_dir}"

bundle="${stage_dir}/hexproof.app"
if [[ ! -d "${bundle}" ]]; then
    bundle="${stage_dir}/Hexproof.app"
fi
if [[ ! -d "${bundle}" ]]; then
    printf '%s\n' "The staged Hexproof application bundle was not found." >&2
    exit 1
fi
cmake -DHEXPROOF_PACKAGE_ROOT="${bundle}" \
    -P "${repo_root}/packaging/prune-client-runtime.cmake"

signing_identity="${HEXPROOF_MACOS_SIGN_IDENTITY:-}"
notary_apple_id="${HEXPROOF_MACOS_NOTARY_APPLE_ID:-}"
notary_password="${HEXPROOF_MACOS_NOTARY_PASSWORD:-}"
notary_team_id="${HEXPROOF_MACOS_NOTARY_TEAM_ID:-}"

if [[ -n "${signing_identity}" ]]; then
    # Developer ID signing; required for the notarization path below.
    codesign --force --deep --options runtime --timestamp \
        --sign "${signing_identity}" "${bundle}"
else
    # No Developer ID certificate configured (free build): ad-hoc sign so
    # every nested Qt framework/dylib carries a signature. This will not
    # satisfy Gatekeeper (users must bypass via right-click "Open" or
    # `xattr -cr`), but it prevents the app from failing to load unsigned
    # libraries at runtime.
    codesign --force --deep --sign - "${bundle}"
fi
codesign --verify --deep --strict --verbose=2 "${bundle}"

notary_values=0
[[ -n "${notary_apple_id}" ]] && ((notary_values += 1))
[[ -n "${notary_password}" ]] && ((notary_values += 1))
[[ -n "${notary_team_id}" ]] && ((notary_values += 1))
if (( notary_values > 0 && notary_values < 3 )); then
    printf '%s\n' "All macOS notarization credentials must be provided together." >&2
    exit 1
fi
if (( notary_values == 3 )); then
    if [[ -z "${signing_identity}" ]]; then
        printf '%s\n' "macOS notarization requires a signing identity." >&2
        exit 1
    fi
    notary_archive="${stage_dir}/Hexproof-notarization.zip"
    ditto -c -k --keepParent "${bundle}" "${notary_archive}"
    xcrun notarytool submit "${notary_archive}" \
        --apple-id "${notary_apple_id}" \
        --password "${notary_password}" \
        --team-id "${notary_team_id}" \
        --wait
    xcrun stapler staple "${bundle}"
    xcrun stapler validate "${bundle}"
fi

archive="${output_dir}/Hexproof-${version}-macos-${arch}.zip"
ditto -c -k --sequesterRsrc --keepParent "${bundle}" "${archive}"
printf '%s\n' "${archive}"
