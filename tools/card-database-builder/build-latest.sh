#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
output_root="${1:-${repo_root}/build/card-database}"
client_build_dir="${HEXPROOF_CLIENT_BUILD_DIR:-${repo_root}/build/client-qt}"
user_agent="Hexproof card-database-builder/1.0"

usage() {
    cat <<'EOF'
Usage: ./tools/card-database-builder/build-latest.sh [OUTPUT_ROOT]

Download the latest Scryfall Default Cards and All Cards exports, MTGJSON
booster definitions, and the latest MTGCH Simplified Chinese data release,
then build and package the current Hexproof card database. Existing source
files are never used as build inputs.

OUTPUT_ROOT defaults to build/card-database. Relative paths are resolved from
the repository root. Set HEXPROOF_CLIENT_BUILD_DIR to use another configured
Qt build directory.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ "$#" -gt 1 ]]; then
    usage >&2
    exit 2
fi
if [[ "${output_root}" != /* ]]; then
    output_root="${repo_root}/${output_root}"
fi
if [[ "${client_build_dir}" != /* ]]; then
    client_build_dir="${repo_root}/${client_build_dir}"
fi
if [[ -z "${output_root}" || "${output_root}" == "/" ]]; then
    printf 'Refusing unsafe output root: %s\n' "${output_root}" >&2
    exit 2
fi

for command_name in awk cmake curl gzip jq mktemp python3 sha256sum sqlite3 tar; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
done

if [[ ! -f "${client_build_dir}/CMakeCache.txt" ]]; then
    if ! command -v ninja >/dev/null 2>&1; then
        printf 'Required command not found: ninja\n' >&2
        exit 1
    fi
    cmake -S "${repo_root}/apps/client-qt" -B "${client_build_dir}" -G Ninja
fi
cmake --build "${client_build_dir}" --target hexproof_card_database_builder

mkdir -p "${output_root}"
staging_root="$(mktemp -d "${output_root}/.build-latest.XXXXXX")"
cleanup() {
    if [[ -n "${staging_root:-}" &&
          "${staging_root}" == "${output_root}"/.build-latest.* &&
          -d "${staging_root}" ]]; then
        rm -rf -- "${staging_root}"
    fi
}
trap cleanup EXIT
mkdir -p "${staging_root}/source" "${staging_root}/import" "${staging_root}/release"

api_curl=(
    curl --fail --silent --show-error --retry 8 --retry-all-errors
    --connect-timeout 15 --user-agent "${user_agent}"
)
download_curl=(
    curl --fail --location --show-error --retry 8 --retry-all-errors
    --connect-timeout 15 --speed-limit 1024 --speed-time 30
    --user-agent "${user_agent}"
)

printf '%s\n' 'Resolving latest upstream card data...'
bulk_descriptor="$("${api_curl[@]}" --header 'Accept: application/json' \
    https://api.scryfall.com/bulk-data)"
default_descriptor="$(jq -ce '.data[] | select(.type == "default_cards")' \
    <<<"${bulk_descriptor}")"
all_descriptor="$(jq -ce '.data[] | select(.type == "all_cards")' \
    <<<"${bulk_descriptor}")"
default_url="$(jq -er '.jsonl_download_uri // .download_uri' <<<"${default_descriptor}")"
all_url="$(jq -er '.jsonl_download_uri // .download_uri' <<<"${all_descriptor}")"
default_updated_at="$(jq -er '.updated_at' <<<"${default_descriptor}")"
all_updated_at="$(jq -er '.updated_at' <<<"${all_descriptor}")"

mtgch_descriptor="$("${api_curl[@]}" --header 'Accept: application/vnd.github+json' \
    https://api.github.com/repos/HeliumOctahelide/magic-cards-zhs/releases/latest)"
mtgch_release="$(jq -er '.tag_name' <<<"${mtgch_descriptor}")"
mtgch_url="$(jq -er '[.assets[] |
    select(.name | startswith("magic-cards-zhs-data-")) |
    select(.name | endswith(".tar.gz")) |
    .browser_download_url][0]' <<<"${mtgch_descriptor}")"
mtgjson_meta="$("${api_curl[@]}" --header 'Accept: application/json' \
    https://mtgjson.com/api/v5/Meta.json)"
mtgjson_version="$(jq -er '.data.version' <<<"${mtgjson_meta}")"
mtgjson_url="https://mtgjson.com/api/v5/AllSetFiles.zip"

if [[ "${default_url}" != https://data.scryfall.io/* ||
      "${all_url}" != https://data.scryfall.io/* ||
      "${mtgch_url}" != https://github.com/HeliumOctahelide/magic-cards-zhs/releases/download/* ||
      "${mtgjson_url}" != https://mtgjson.com/api/v5/AllSetFiles.zip ]]; then
    printf 'Upstream metadata returned an unexpected download URL.\n' >&2
    exit 1
fi

printf 'Downloading Scryfall Default Cards (%s)...\n' "${default_updated_at}"
"${download_curl[@]}" --output "${staging_root}/source/default-cards.jsonl.gz" \
    "${default_url}"
printf 'Downloading Scryfall All Cards (%s)...\n' "${all_updated_at}"
"${download_curl[@]}" --output "${staging_root}/source/all-cards.jsonl.gz" "${all_url}"
printf 'Downloading MTGCH data (%s)...\n' "${mtgch_release}"
"${download_curl[@]}" --output "${staging_root}/source/magic-cards-zhs-data.tar.gz" \
    "${mtgch_url}"
printf 'Downloading MTGJSON AllSetFiles (%s)...\n' "${mtgjson_version}"
"${download_curl[@]}" --output "${staging_root}/source/mtgjson-all-set-files.zip" \
    "${mtgjson_url}"

gzip -t "${staging_root}/source/default-cards.jsonl.gz"
gzip -t "${staging_root}/source/all-cards.jsonl.gz"
tar -tzf "${staging_root}/source/magic-cards-zhs-data.tar.gz" >/dev/null
python3 -m zipfile --test "${staging_root}/source/mtgjson-all-set-files.zip" >/dev/null
default_sha256="$(sha256sum "${staging_root}/source/default-cards.jsonl.gz" | awk '{print $1}')"
all_sha256="$(sha256sum "${staging_root}/source/all-cards.jsonl.gz" | awk '{print $1}')"
mtgch_sha256="$(sha256sum "${staging_root}/source/magic-cards-zhs-data.tar.gz" | awk '{print $1}')"
mtgjson_sha256="$(sha256sum "${staging_root}/source/mtgjson-all-set-files.zip" | awk '{print $1}')"

python3 "${script_dir}/build_limited_products.py" \
    --source "${staging_root}/source/mtgjson-all-set-files.zip" \
    --output "${staging_root}/source/limited-products.json" \
    --mtgjson-version "${mtgjson_version}"

jq -n \
    --arg downloadedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg defaultUrl "${default_url}" \
    --arg defaultUpdatedAt "${default_updated_at}" \
    --arg defaultSha256 "${default_sha256}" \
    --arg allUrl "${all_url}" \
    --arg allUpdatedAt "${all_updated_at}" \
    --arg allSha256 "${all_sha256}" \
    --arg mtgchUrl "${mtgch_url}" \
    --arg mtgchRelease "${mtgch_release}" \
    --arg mtgchSha256 "${mtgch_sha256}" \
    --arg mtgjsonUrl "${mtgjson_url}" \
    --arg mtgjsonVersion "${mtgjson_version}" \
    --arg mtgjsonSha256 "${mtgjson_sha256}" \
    '{
        downloadedAt: $downloadedAt,
        scryfallDefaultCards: {
            url: $defaultUrl, updatedAt: $defaultUpdatedAt, sha256: $defaultSha256
        },
        scryfallAllCards: {url: $allUrl, updatedAt: $allUpdatedAt, sha256: $allSha256},
        mtgch: {url: $mtgchUrl, release: $mtgchRelease, sha256: $mtgchSha256},
        mtgjson: {url: $mtgjsonUrl, version: $mtgjsonVersion, sha256: $mtgjsonSha256}
    }' > "${staging_root}/source/upstream.json"

printf '%s\n' 'Building the card database...'
"${client_build_dir}/hexproof_card_database_builder" \
    --source "${staging_root}/source/default-cards.jsonl.gz" \
    --chinese-index "${staging_root}/source/magic-cards-zhs-data.tar.gz" \
    --localized-source "${staging_root}/source/all-cards.jsonl.gz" \
    --limited-products "${staging_root}/source/limited-products.json" \
    --output "${staging_root}/import/hexproof-default-cards.sqlite"

"${repo_root}/packaging/card-database/build-release-assets.sh" \
    "${staging_root}/import/hexproof-default-cards.sqlite" \
    "${staging_root}/release"

mkdir -p "${output_root}/source" "${output_root}/import" "${output_root}/release"
for source_file in default-cards.jsonl.gz all-cards.jsonl.gz \
    magic-cards-zhs-data.tar.gz limited-products.json upstream.json; do
    mv -f -- "${staging_root}/source/${source_file}" "${output_root}/source/${source_file}"
done
mv -f -- "${staging_root}/import/hexproof-default-cards.sqlite" \
    "${output_root}/import/hexproof-default-cards.sqlite"
for release_file in hexproof-default-cards.sqlite.gz card-database-manifest.json SHA256SUMS; do
    mv -f -- "${staging_root}/release/${release_file}" "${output_root}/release/${release_file}"
done

printf 'Latest card database written to %s\n' "${output_root}"
