#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Extract compact Hexproof limited-product definitions from MTGJSON AllSetFiles."""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MAX_ENCODED_PRODUCT_BYTES = 800 * 1024


def load_set(archive: zipfile.ZipFile, member: str) -> dict[str, Any] | None:
    try:
        value = json.loads(archive.read(member))
    except (KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    data = value.get("data") if isinstance(value, dict) else None
    return data if isinstance(data, dict) else None


def card_identity(card: dict[str, Any], fallback_set: str) -> dict[str, str] | None:
    name = str(card.get("name", "")).strip()
    set_code = str(card.get("setCode", fallback_set)).strip().upper()
    collector = str(card.get("number", "")).strip()
    if not name or not set_code or not collector:
        return None
    return {
        "name": name,
        "setCode": set_code,
        "collectorNumber": collector,
        "typeLine": str(card.get("type", "")).strip(),
        "rarity": str(card.get("rarity", "")).strip().lower(),
    }


def label_product(product_key: str) -> str:
    return product_key.replace("-", " ").strip().title()


def build_product(
    set_data: dict[str, Any],
    product_key: str,
    source: dict[str, Any],
    identities: dict[str, dict[str, str]],
) -> dict[str, Any] | None:
    source_sheets = source.get("sheets")
    boosters = source.get("boosters")
    if not isinstance(source_sheets, dict) or not isinstance(boosters, list):
        return None

    variants: list[dict[str, Any]] = []
    cards_per_pack = 0
    referenced_sheets: set[str] = set()
    for booster in boosters:
        if not isinstance(booster, dict) or not isinstance(booster.get("contents"), dict):
            continue
        slots = []
        size = 0
        for sheet_name, raw_count in booster["contents"].items():
            try:
                count = int(raw_count)
            except (TypeError, ValueError):
                continue
            if count < 1 or sheet_name not in source_sheets:
                continue
            slots.append({"sheet": sheet_name, "count": count})
            referenced_sheets.add(sheet_name)
            size += count
        try:
            weight = int(booster.get("weight", 0))
        except (TypeError, ValueError):
            weight = 0
        if not slots or not 1 <= size <= 30 or weight < 1:
            continue
        if cards_per_pack == 0:
            cards_per_pack = size
        if size == cards_per_pack:
            variants.append({"weight": weight, "slots": slots})
    if not variants:
        return None

    sheets = []
    for sheet_name in sorted(referenced_sheets):
        raw_sheet = source_sheets.get(sheet_name)
        raw_cards = raw_sheet.get("cards") if isinstance(raw_sheet, dict) else None
        if not isinstance(raw_cards, dict):
            return None
        finish = "foil" if raw_sheet.get("foil") else "nonfoil"
        cards = []
        for uuid, raw_weight in raw_cards.items():
            identity = identities.get(uuid)
            if identity is None:
                return None
            try:
                weight = int(raw_weight)
            except (TypeError, ValueError):
                return None
            if weight < 1 or weight > 1_000_000_000:
                return None
            cards.append({**identity, "finish": finish, "weight": weight})
        if not cards:
            return None
        sheets.append(
            {
                "name": sheet_name,
                "withReplacement": False,
                "cards": cards,
            }
        )

    if len(sheets) > 64 or len(variants) > 64:
        return None
    if sum(len(sheet["cards"]) for sheet in sheets) > 5000:
        return None
    if any(len(variant["slots"]) > 64 for variant in variants):
        return None

    set_code = str(set_data.get("code", "")).strip().upper()
    set_name = str(set_data.get("name", set_code)).strip()
    if not set_code or not set_name:
        return None
    product = {
        "id": f"mtgjson-{set_code.lower()}-{product_key.lower()}",
        "name": f"{set_name} — {label_product(product_key)}",
        "setCode": set_code,
        "productType": "official",
        "authentic": True,
        "cardsPerPack": cards_per_pack,
        "sheets": sheets,
        "variants": variants,
    }
    encoded = json.dumps(product, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return product if len(encoded) <= MAX_ENCODED_PRODUCT_BYTES else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mtgjson-version", default="")
    args = parser.parse_args()

    identities: dict[str, dict[str, str]] = {}
    products: list[dict[str, Any]] = []
    try:
        with zipfile.ZipFile(args.source) as archive:
            members = sorted(name for name in archive.namelist() if name.endswith(".json"))
            for member in members:
                set_data = load_set(archive, member)
                if set_data is None:
                    continue
                fallback_set = str(set_data.get("code", ""))
                for card in set_data.get("cards", []):
                    if not isinstance(card, dict):
                        continue
                    uuid = str(card.get("uuid", ""))
                    identity = card_identity(card, fallback_set)
                    if uuid and identity is not None:
                        identities[uuid] = identity
            for member in members:
                set_data = load_set(archive, member)
                if set_data is None or not isinstance(set_data.get("booster"), dict):
                    continue
                for product_key, source in sorted(set_data["booster"].items()):
                    if not isinstance(source, dict):
                        continue
                    product = build_product(set_data, product_key, source, identities)
                    if product is not None:
                        products.append(product)
    except (OSError, zipfile.BadZipFile) as error:
        print(f"Could not read MTGJSON AllSetFiles: {error}", file=sys.stderr)
        return 1

    products.sort(key=lambda item: (item["setCode"], item["name"], item["id"]))
    output = {
        "schemaVersion": 1,
        "source": "MTGJSON AllSetFiles",
        "sourceVersion": args.mtgjson_version,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "products": products,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
    print(f"generated {len(products)} limited products", file=sys.stderr)
    return 0 if products else 1


if __name__ == "__main__":
    raise SystemExit(main())
