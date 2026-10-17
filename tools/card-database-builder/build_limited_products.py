#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Extract compact Hexproof limited-product definitions from MTGJSON AllSetFiles."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MAX_ENCODED_PRODUCT_BYTES = 800 * 1024
# JSON numbers stay exact only through 2^53 - 1. FIN Play wildcard weights
# exceed 1e9 but remain inside this bound.
MAX_PRODUCT_WEIGHT = 9_007_199_254_740_991
MAX_TOTAL_WEIGHT = (1 << 63) - 1
MAX_PRODUCT_SHEETS = 128
MAX_PRODUCT_VARIANTS = 256
MAX_PRODUCT_CARDS = 10_000


def load_set(archive: zipfile.ZipFile, member: str) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    try:
        value = json.loads(archive.read(member))
    except (KeyError, json.JSONDecodeError, UnicodeDecodeError) as error:
        raise ValueError(f"{member}: invalid set JSON") from error
    data = value.get("data") if isinstance(value, dict) else None
    descriptor = value.get("meta", {}) if isinstance(value, dict) else {}
    if not isinstance(descriptor, dict) or any(not isinstance(descriptor.get(k, ""), str)
                                               for k in ("version", "date")):
        raise ValueError(f"{member}: invalid source revision")
    return (data if isinstance(data, dict) else None), descriptor


def card_identity(card: dict[str, Any], fallback_set: str) -> dict[str, str] | None:
    name = card.get("name", "")
    set_code = card.get("setCode", fallback_set)
    collector = card.get("number", "")
    type_line = card.get("type", "")
    rarity = card.get("rarity", "")
    if not all(isinstance(v, str) for v in (name, set_code, collector, type_line, rarity)):
        return None
    if not name.strip() or not set_code.strip() or not collector.strip():
        return None
    return {"name": name.strip(), "setCode": set_code.strip().upper(),
            "collectorNumber": collector.strip(), "typeLine": type_line.strip(),
            "rarity": rarity.strip().lower()}


def positive_integer(value: Any, maximum: int = MAX_PRODUCT_WEIGHT) -> bool:
    return type(value) is int and 1 <= value <= maximum


def compact_product(product: dict[str, Any]) -> dict[str, Any]:
    encoded = json.dumps(product, ensure_ascii=False, separators=(",", ":")).encode()
    if len(encoded) <= MAX_ENCODED_PRODUCT_BYTES // 2:
        return product
    pool: list[dict[str, Any]] = []
    indices: dict[str, int] = {}
    sheets = []
    for sheet in product["sheets"]:
        refs = []
        for card in sheet["cards"]:
            identity = {**card, "weight": 1}
            key = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            if key not in indices:
                pool.append(identity)
                indices[key] = len(pool)
            refs.append({"cardIndex": indices[key], "weight": card["weight"]})
        sheets.append({**{k: v for k, v in sheet.items() if k != "cards"}, "cardRefs": refs})
    compact = {**product, "sheets": sheets, "cardPool": pool}
    compact_bytes = json.dumps(compact, ensure_ascii=False, separators=(",", ":")).encode()
    return compact if len(compact_bytes) < len(encoded) else product


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
    require_complete = set_data.get("code") == "FRA" and product_key == "play"

    variants: list[dict[str, Any]] = []
    cards_per_pack = 0
    referenced_sheets: set[str] = set()
    for booster in boosters:
        if not isinstance(booster, dict) or not isinstance(booster.get("contents"), dict):
            return None
        slots = []
        size = 0
        for sheet_name, count in booster["contents"].items():
            if not positive_integer(count, 30) or sheet_name not in source_sheets:
                return None
            slots.append({"sheet": sheet_name, "count": count})
            referenced_sheets.add(sheet_name)
            size += count
        weight = booster.get("weight")
        if not slots or not 1 <= size <= 30 or not positive_integer(weight):
            return None
        if cards_per_pack == 0:
            cards_per_pack = size
        if size != cards_per_pack or (require_complete and size != 14):
            return None
        variants.append({"weight": weight, "slots": slots})
    if not variants or sum(v["weight"] for v in variants) > MAX_TOTAL_WEIGHT:
        return None
    sheets = []
    for sheet_name in sorted(referenced_sheets):
        raw_sheet = source_sheets.get(sheet_name)
        raw_cards = raw_sheet.get("cards") if isinstance(raw_sheet, dict) else None
        if not isinstance(raw_cards, dict):
            return None
        if type(raw_sheet.get("foil", False)) is not bool or (require_complete and raw_sheet.get("balanceColors")):
            return None
        finish = "foil" if raw_sheet.get("foil") else "nonfoil"
        cards = []
        for uuid, raw_weight in raw_cards.items():
            identity = identities.get(uuid)
            if identity is None:
                return None
            weight = raw_weight
            if not positive_integer(weight):
                return None
            cards.append({**identity, "finish": finish, "weight": weight})
        if not cards:
            return None
        if sum(card["weight"] for card in cards) > MAX_TOTAL_WEIGHT:
            return None
        sheets.append(
            {
                "name": sheet_name,
                "withReplacement": False,
                "cards": cards,
            }
        )

    by_name = {sheet["name"]: sheet for sheet in sheets}
    for variant in variants:
        for slot in variant["slots"]:
            if slot["count"] > len(by_name[slot["sheet"]]["cards"]):
                return None
    if require_complete:
        for name, sheet in by_name.items():
            if name.startswith("pair"):
                cards = sheet["cards"]
                if (source_sheets[name].get("fixed") is not True or len(cards) != 2
                        or cards[0]["weight"] != cards[1]["weight"]
                        or (cards[0]["setCode"], cards[0]["collectorNumber"])
                        == (cards[1]["setCode"], cards[1]["collectorNumber"])):
                    return None
        for variant in variants:
            pairs = [slot for slot in variant["slots"] if slot["sheet"].startswith("pair")]
            thirds = [slot for slot in variant["slots"] if slot["sheet"].startswith("thirdNot")]
            if len(pairs) != 1 or len(thirds) != 1 or pairs[0]["count"] != 2 or thirds[0]["count"] != 1:
                return None
            character = pairs[0]["sheet"][4:].removesuffix("Borderless")
            if thirds[0]["sheet"] != "thirdNot" + character:
                return None
            excluded = {(c["setCode"], c["collectorNumber"])
                        for name in ("pair" + character, "pair" + character + "Borderless")
                        for c in by_name.get(name, {}).get("cards", [])}
            if any((c["setCode"], c["collectorNumber"]) in excluded
                   for c in by_name[thirds[0]["sheet"]]["cards"]):
                return None

    if len(sheets) > MAX_PRODUCT_SHEETS or len(variants) > MAX_PRODUCT_VARIANTS:
        return None
    if sum(len(sheet["cards"]) for sheet in sheets) > MAX_PRODUCT_CARDS:
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
    product = compact_product(product)
    encoded = json.dumps(product, ensure_ascii=False, separators=(",", ":")).encode()
    return product if len(encoded) <= MAX_ENCODED_PRODUCT_BYTES else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mtgjson-version", default="")
    parser.add_argument("--require-product", action="append", default=[], metavar="SET:KIND")
    args = parser.parse_args()

    identities: dict[str, dict[str, str]] = {}
    products: list[dict[str, Any]] = []
    versions: set[str] = set()
    dates: set[str] = set()
    try:
        with zipfile.ZipFile(args.source) as archive:
            members = sorted(name for name in archive.namelist() if name.endswith(".json"))
            for member in members:
                set_data, descriptor = load_set(archive, member)
                if set_data is None:
                    continue
                if args.require_product and not all(descriptor.get(k) for k in ("version", "date")):
                    raise ValueError(f"{member}: required upstream revision is missing")
                if descriptor.get("version"):
                    versions.add(descriptor["version"])
                if descriptor.get("date"):
                    dates.add(descriptor["date"])
                fallback_set = str(set_data.get("code", ""))
                for card in set_data.get("cards", []):
                    if not isinstance(card, dict):
                        continue
                    uuid = str(card.get("uuid", ""))
                    identity = card_identity(card, fallback_set)
                    if uuid and identity is not None:
                        identities[uuid] = identity
            for member in members:
                set_data, _ = load_set(archive, member)
                if (set_data is not None and set_data.get("code") == "FRA"
                        and (not isinstance(set_data.get("booster"), dict)
                             or not isinstance(set_data["booster"].get("play"), dict))):
                    raise ValueError("FRA requires upstream Play booster data")
                if set_data is None or not isinstance(set_data.get("booster"), dict):
                    continue
                for product_key, source in sorted(set_data["booster"].items()):
                    if not isinstance(source, dict):
                        continue
                    product = build_product(set_data, product_key, source, identities)
                    if product is not None:
                        products.append(product)
                    elif set_data.get("code") == "FRA" and product_key == "play":
                        raise ValueError("FRA upstream Play booster is invalid or exceeds supported bounds")
        if len(versions) > 1 or len(dates) > 1:
            raise ValueError("set archive has inconsistent upstream revisions")
        version = next(iter(versions), args.mtgjson_version)
        if args.mtgjson_version and version != args.mtgjson_version:
            raise ValueError("downloaded archive version differs from the requested MTGJSON version")
        available = {f"{p['setCode']}:{p['id'].removeprefix('mtgjson-' + p['setCode'].lower() + '-')}"
                     for p in products}
        for required in args.require_product:
            if required not in available:
                raise ValueError(f"required upstream product is missing: {required}")
        if not products:
            raise ValueError("archive contains no supported limited products")
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"Could not read MTGJSON AllSetFiles: {error}", file=sys.stderr)
        return 1

    products.sort(key=lambda item: (item["setCode"], item["name"], item["id"]))
    with args.source.open("rb") as source_file:
        source_sha256 = hashlib.file_digest(source_file, "sha256").hexdigest()
    output = {
        "schemaVersion": 1,
        "source": "MTGJSON AllSetFiles",
        "sourceVersion": version,
        "sourceDate": next(iter(dates), ""),
        "sourceSha256": source_sha256,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "products": products,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=args.output.parent,
                                     prefix=".limited-products-", delete=False) as staged:
        staged.write(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
        staged_path = Path(staged.name)
    try:
        staged_path.replace(args.output)
    finally:
        staged_path.unlink(missing_ok=True)
    print(f"generated {len(products)} limited products", file=sys.stderr)
    return 0 if products else 1


if __name__ == "__main__":
    raise SystemExit(main())
