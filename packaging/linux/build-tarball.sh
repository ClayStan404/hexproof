#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
source_version="$(
    sed -nE 's/^[[:space:]]*set\(HEXPROOF_VERSION[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*\)[[:space:]]*$/\1/p' \
        "${repo_root}/apps/client-qt/CMakeLists.txt"
)"
version="${HEXPROOF_VERSION:-${source_version}}"
arch="${HEXPROOF_ARCH:-$(uname -m)}"
build_dir="${repo_root}/build/package-linux"
output_dir="${HEXPROOF_OUTPUT_DIR:-${repo_root}/build/packages}"
server_directory_args=()
if [[ -n "${HEXPROOF_SERVER_DIRECTORY_FILE:-}" ]]; then
    server_directory_args+=(
        "-DHEXPROOF_SERVER_DIRECTORY_FILE=${HEXPROOF_SERVER_DIRECTORY_FILE}"
    )
fi

cmake -S "${repo_root}/apps/client-qt" -B "${build_dir}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DHEXPROOF_VERSION_OVERRIDE="${version}" \
    "${server_directory_args[@]}"
cmake --build "${build_dir}" --config Release --target hexproof

mkdir -p "${build_dir}" "${output_dir}"
stage_dir="$(mktemp -d "${build_dir}/stage.XXXXXX")"
trap 'rm -rf -- "${stage_dir}"' EXIT
package_root="${stage_dir}/Hexproof-${version}-linux-${arch}"

cmake --install "${build_dir}" --config Release --prefix "${package_root}"
install -m 0755 "${repo_root}/packaging/linux/install-desktop.sh" \
    "${package_root}/install-desktop.sh"
cmake -DHEXPROOF_PACKAGE_ROOT="${package_root}" \
    -P "${repo_root}/packaging/prune-client-runtime.cmake"
tar -C "${stage_dir}" -czf \
    "${output_dir}/Hexproof-${version}-linux-${arch}.tar.gz" \
    "$(basename -- "${package_root}")"

printf '%s\n' "${output_dir}/Hexproof-${version}-linux-${arch}.tar.gz"
