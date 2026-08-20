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
goos="${HEXPROOF_GOOS:-$(go env GOOS)}"
arch="${HEXPROOF_ARCH:-$(go env GOARCH)}"
case "${arch}" in
    x86_64 | x64)
        arch="amd64"
        ;;
    aarch64)
        arch="arm64"
        ;;
esac
if [[ "${goos}" != "linux" ]]; then
    printf 'Unsupported server target OS: %s (expected linux)\n' "${goos}" >&2
    exit 1
fi
case "${arch}" in
    amd64 | arm64) ;;
    *)
        printf 'Unsupported server target architecture: %s\n' "${arch}" >&2
        exit 1
        ;;
esac
build_dir="${repo_root}/build/package-server"
output_dir="${HEXPROOF_OUTPUT_DIR:-${repo_root}/build/packages}"
go_tmp_dir="${GOTMPDIR:-${build_dir}/go-tmp-${goos}-${arch}}"

mkdir -p "${build_dir}" "${output_dir}" "${go_tmp_dir}"
stage_dir="$(mktemp -d "${build_dir}/stage.XXXXXX")"
trap 'rm -rf -- "${stage_dir}"' EXIT
package_root="${stage_dir}/hexproof-server-${version}-linux-${arch}"
mkdir -p "${package_root}/bin" "${package_root}/deploy"

(
    cd "${repo_root}/apps/server"
    CGO_ENABLED=0 GOOS="${goos}" GOARCH="${arch}" GOTMPDIR="${go_tmp_dir}" \
        go build -trimpath \
        -ldflags "-X hexproof/server/internal/buildinfo.Version=${version}" \
        -o "${package_root}/bin/hexproof-server" \
        ./cmd/hexproof-server
)
cp "${repo_root}/packaging/server/hexproof-server.service.in" \
    "${package_root}/deploy/"
cp "${repo_root}/packaging/server/README.md" "${package_root}/SELF-HOSTING.md"
cp "${repo_root}/LICENSE" "${package_root}/"

tar -C "${stage_dir}" -czf \
    "${output_dir}/hexproof-server-${version}-linux-${arch}.tar.gz" \
    "$(basename -- "${package_root}")"

printf '%s\n' "${output_dir}/hexproof-server-${version}-linux-${arch}.tar.gz"
