#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 DATABASE.sqlite OUTPUT_DIRECTORY" >&2
  exit 2
fi

database_path="$1"
output_directory="$2"
asset_name="hexproof-default-cards.sqlite.gz"
manifest_name="card-database-manifest.json"

if [[ ! -f "$database_path" ]]; then
  echo "Card database not found: $database_path" >&2
  exit 1
fi
for command_name in gzip python3 sha256sum sqlite3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

quick_check="$(sqlite3 "$database_path" 'PRAGMA quick_check;')"
package_name="$(
  sqlite3 "$database_path" \
    "SELECT value FROM metadata WHERE key = 'package' LIMIT 1;"
)"
schema_version="$(
  sqlite3 "$database_path" \
    "SELECT value FROM metadata WHERE key = 'schema_version' LIMIT 1;"
)"
generated_at="$(
  sqlite3 "$database_path" \
    "SELECT value FROM metadata WHERE key = 'generated_at' LIMIT 1;"
)"
card_count="$(
  sqlite3 "$database_path" \
    "SELECT value FROM metadata WHERE key = 'count' LIMIT 1;"
)"
alias_count="$(
  sqlite3 "$database_path" \
    "SELECT value FROM metadata WHERE key = 'alias_count' LIMIT 1;"
)"
token_count="$(
  sqlite3 "$database_path" \
    "SELECT value FROM metadata WHERE key = 'token_count' LIMIT 1;"
)"
localized_printing_count="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM localized_printings;"
)"
localized_layout_column="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('localized_printings') WHERE name = 'layout';"
)"
token_metadata_columns="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('cards') WHERE name IN ('power', 'toughness', 'oracle_text');"
)"
legality_status_columns="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('cards') WHERE name = 'legality_statuses';"
)"
card_image_status_columns="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('cards') WHERE name = 'image_status';"
)"
localized_image_status_columns="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('localized_printings') WHERE name = 'image_status';"
)"
booster_columns="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('cards') WHERE name = 'booster';"
)"
limited_product_columns="$(
  sqlite3 "$database_path" \
    "SELECT COUNT(*) FROM pragma_table_info('limited_products') WHERE name IN ('id', 'name', 'set_code', 'product_type', 'authentic', 'definition_json');"
)"
limited_product_count="$(
  sqlite3 "$database_path" 'SELECT COUNT(*) FROM limited_products;'
)"

if [[ "$quick_check" != "ok" ||
      "$package_name" != "default_cards" ||
      "$schema_version" != "10" ||
      ! "$generated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ||
      "$localized_layout_column" != "1" ||
      "$token_metadata_columns" != "3" ||
      "$legality_status_columns" != "1" ||
      "$card_image_status_columns" != "1" ||
      "$localized_image_status_columns" != "1" ||
      "$booster_columns" != "1" ||
      "$limited_product_columns" != "6" ||
      ! "$limited_product_count" =~ ^[1-9][0-9]*$ ||
      ! "$card_count" =~ ^[1-9][0-9]*$ ||
      ! "$alias_count" =~ ^[1-9][0-9]*$ ||
      ! "$token_count" =~ ^[1-9][0-9]*$ ||
      ! "$localized_printing_count" =~ ^[1-9][0-9]*$ ||
      "$localized_printing_count" -lt 10000 ]]; then
  echo "Database is not a complete Hexproof schema-v10 Default Cards database." >&2
  exit 1
fi

mkdir -p "$output_directory"
asset_path="$output_directory/$asset_name"
asset_temporary_path="$asset_path.tmp"
manifest_path="$output_directory/$manifest_name"
manifest_temporary_path="$manifest_path.tmp"
rm -f "$asset_temporary_path" "$manifest_temporary_path"
gzip -n -9 -c "$database_path" > "$asset_temporary_path"

database_size="$(stat -c '%s' "$database_path")"
compressed_size="$(stat -c '%s' "$asset_temporary_path")"
database_sha256="$(sha256sum "$database_path" | awk '{print $1}')"
compressed_sha256="$(sha256sum "$asset_temporary_path" | awk '{print $1}')"
python3 - \
  "$manifest_temporary_path" \
  "$asset_name" \
  "$generated_at" \
  "$database_size" \
  "$compressed_size" \
  "$database_sha256" \
  "$compressed_sha256" \
  "$card_count" \
  "$alias_count" \
  "$token_count" \
  "$localized_printing_count" <<'PY'
import json
import pathlib
import sys

(
    manifest_path,
    asset,
    generated_at,
    uncompressed_size,
    compressed_size,
    sha256,
    compressed_sha256,
    card_count,
    alias_count,
    token_count,
    localized_printing_count,
) = sys.argv[1:]

manifest = {
    "format": "hexproof-card-database-v1",
    "schemaVersion": 10,
    "package": "default_cards",
    "asset": asset,
    "generatedAt": generated_at,
    "uncompressedSize": int(uncompressed_size),
    "compressedSize": int(compressed_size),
    "sha256": sha256,
    "compressedSha256": compressed_sha256,
    "cardCount": int(card_count),
    "aliasCount": int(alias_count),
    "tokenCount": int(token_count),
    "localizedPrintingCount": int(localized_printing_count),
}
pathlib.Path(manifest_path).write_text(
    json.dumps(manifest, ensure_ascii=True, indent=2) + "\n",
    encoding="utf-8",
)
PY

mv "$asset_temporary_path" "$asset_path"
mv "$manifest_temporary_path" "$manifest_path"
(
  cd "$output_directory"
  sha256sum "$asset_name" "$manifest_name" > SHA256SUMS
)

printf 'Created %s and %s\n' "$asset_path" "$manifest_path"
