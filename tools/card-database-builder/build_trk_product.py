#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Install an explicitly estimated TRK Play product into a staged build database."""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import closing
from fractions import Fraction
import hashlib
import json
from math import gcd, lcm
from pathlib import Path
import sqlite3
import unicodedata

from build_limited_products import (
    MAX_ENCODED_PRODUCT_BYTES, MAX_PRODUCT_CARDS,
    MAX_TOTAL_WEIGHT, compact_product, positive_integer,
)


SOURCE = "https://magic.wizards.com/en/news/feature/collecting-star-trek"
REVISION = "2026-11-08.1"
PRODUCT_ID = "hexproof-trk-play"
METADATA_KEY = "trk_collation"
DUALS = {275, 277, 280, 281, 283, 288, 291, 293, 294, 305}
GROUPS = {
    "base": ("TRK", set(range(1, 307)) - DUALS,
             {"common": 81, "uncommon": 110, "rare": 80, "mythic": 25}),
    "dual": ("TRK", DUALS, {"common": 10}),
    "away": ("TRK", set(range(307, 312)), {"common": 5}),
    "holodeck": ("TRK", set(range(312, 317)), {"common": 5}),
    "basic": ("TRK", set(range(317, 327)), {"common": 10}),
    "borderless": ("TRK", set(range(332, 338)), {"rare": 5, "mythic": 1}),
    "scene": ("TRK", set(range(338, 363)), {"uncommon": 10, "rare": 8, "mythic": 7}),
    "lcars": ("TRK", set(range(363, 392)), {"uncommon": 7, "rare": 14, "mythic": 8}),
    "shock": ("TRK", set(range(392, 402)), {"rare": 10}),
    "classic": ("TRK", set(range(402, 426)), {"uncommon": 5, "rare": 13, "mythic": 6}),
    "klingon": ("TRK", set(range(426, 436)), {"common": 1, "uncommon": 6, "rare": 3}),
    "stardates": ("SDS", set(range(1, 31)), {"mythic": 30}),
}
UPSTREAM_IDS = tuple("mtgjson-trk-" + kind for kind in ("play", "play-arena", "draft", "default"))
ASSUMPTIONS = [
    "The published common/uncommon treatment percentages are interpreted per pack, not per card drawn.",
    "At most one common Klingon and one uncommon treatment replacement occur in their respective groups.",
    "Stardates, common replacement and uncommon replacement branches are independent estimates.",
    "Printings within each listed category are equally likely; factory sheets and color balancing are not modeled.",
    "Each single-card slot divides its unpublished less-than-1% categories equally over the remaining probability.",
    "The published land percentages total 100.2 and are normalized proportionally.",
    "Away-team foil lands follow the detailed Play-slot table (1.7%), despite the earlier treatment paragraph omitting Play Boosters.",
    "Repeated set/collector/finish identities are excluded within a pack; alternate treatments and foil copies remain distinct.",
    "Tokens and advertising inserts are outside the 14 playable-card product; this is not factory-exact or Arena-exact collation.",
]


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def valid_text(value, maximum, *, optional=False):
    return (isinstance(value, str) and (bool(value.strip()) or optional) and len(value) <= maximum
            and not any(unicodedata.category(char) == "Cc" for char in value))


def integer_weights(probabilities):
    denominator = lcm(*(value.denominator for value in probabilities))
    weights = [int(value * denominator) for value in probabilities]
    divisor = gcd(*weights)
    weights = [weight // divisor for weight in weights]
    if (not all(positive_integer(weight) for weight in weights)
            or sum(weights) > MAX_TOTAL_WEIGHT):
        raise ValueError("TRK probabilities exceed supported integer weights")
    return weights


def build_product(cards):
    required = {(code, str(number)) for code, numbers, _ in GROUPS.values() for number in numbers}
    index = {}
    for card in cards:
        key = (card.get("setCode"), card.get("collectorNumber"))
        if key not in required:
            continue
        identity = {field: card.get(field, "") for field in
                    ("name", "setCode", "collectorNumber", "typeLine", "rarity")}
        for field, maximum in (("name", 256), ("setCode", 16), ("collectorNumber", 32),
                               ("typeLine", 256), ("rarity", 32)):
            value = identity[field]
            if not valid_text(value, maximum):
                raise ValueError(f"TRK invalid {field} for {key}")
        if key in index and index[key] != identity:
            raise ValueError(f"TRK conflicting printing identity: {key}")
        index[key] = identity
    missing = sorted(required - index.keys())
    if missing:
        raise ValueError("TRK missing required printings: " + ", ".join("/".join(key) for key in missing))

    pools = {}
    for name, (code, numbers, expected) in GROUPS.items():
        pool = [index[(code, str(number))] for number in sorted(numbers)]
        if dict(Counter(card["rarity"] for card in pool)) != expected:
            raise ValueError(f"TRK {name}: rarity counts differ from the reviewed printing list")
        if name in ("dual", "away", "holodeck", "basic", "borderless", "shock"):
            if any("Land" not in card["typeLine"] for card in pool):
                raise ValueError(f"TRK {name}: land category contains a nonland")
        pools[name] = pool

    def category(name, rarity=None):
        return [card for card in pools[name] if rarity is None or card["rarity"] == rarity]

    sheets = []
    estimates = {}

    def sheet(name, entries, *, finish="nonfoil", percentages=False):
        # None denotes a published <1% category. The explicitly estimated
        # remainder is shared between those categories, then within each pool.
        unknown = sum(rate is None for _, rate, _ in entries)
        known = sum((Fraction(str(rate)) for _, rate, _ in entries if rate is not None), Fraction())
        remainder = (100 - known) / unknown if unknown else None
        if unknown and not 0 < remainder < 1:
            raise ValueError(f"TRK {name}: invalid unpublished probability remainder")
        weighted = []
        for pool, rate, override_finish in entries:
            if not pool:
                raise ValueError(f"TRK {name}: a required category is empty")
            probability = remainder if rate is None else Fraction(str(rate))
            for card in pool:
                weighted.append(({**card, "finish": override_finish or finish}, probability / len(pool)))
        weights = integer_weights([probability for _, probability in weighted])
        sheets.append({"name": name, "withReplacement": False, "excludePrevious": True,
                       "cards": [{**card, "weight": weight} for (card, _), weight in zip(weighted, weights)]})
        if unknown:
            estimates[name] = {"unpublishedCategories": unknown,
                               "percentagePerUnpublishedCategory": str(remainder)}
        if percentages:
            estimates.setdefault(name, {})["publishedPercentageTotal"] = str(known)

    def entry(group, rarity=None, rate=1, finish=None):
        return category(group, rarity), rate, finish

    sheet("common", [entry("base", "common")])
    sheet("common-klingon", [entry("klingon", "common")])
    sheet("uncommon", [entry("base", "uncommon")])
    for treatment in ("scene", "lcars", "classic", "klingon"):
        sheet("uncommon-" + treatment, [entry(treatment, "uncommon")])

    def other_treatments(scene_uncommon, lcars_uncommon):
        return [entry("klingon", "common", None), entry("klingon", "uncommon", 1),
                entry("klingon", "rare", None), entry("scene", "uncommon", scene_uncommon),
                entry("scene", "rare", None), entry("scene", "mythic", None),
                entry("lcars", "uncommon", lcars_uncommon), entry("lcars", "rare", None),
                entry("lcars", "mythic", None), entry("classic", "rare", None),
                entry("classic", "mythic", None), entry("borderless", "rare", None),
                entry("borderless", "mythic", None), entry("shock", None, None)]

    sheet("wildcard", [entry("base", rarity, rate) for rarity, rate in
                        (("common", "20.8"), ("uncommon", "54.1"), ("rare", "16.7"), ("mythic", "2.6"))]
          + other_treatments("1.5", 1))
    sheet("rare", [entry("base", "rare", "80.1"), entry("base", "mythic", "12.4"),
                   entry("klingon", "rare", None), entry("scene", "rare", 1),
                   entry("scene", "mythic", None), entry("lcars", "rare", "1.8"),
                   entry("lcars", "mythic", None), entry("classic", "rare", "1.5"),
                   entry("classic", "mythic", None), entry("borderless", "rare", 1),
                   entry("borderless", "mythic", None), entry("shock", None, "1.4")])
    sheet("foil", [entry("base", rarity, rate) for rarity, rate in
                    (("common", "51.2"), ("uncommon", "34.7"), ("rare", "6.3"), ("mythic", 1))]
          + other_treatments("1.6", "1.1"), finish="foil")
    sheet("land", [entry("dual", rate=40), entry("dual", rate=10, finish="foil"),
                   entry("basic", rate="26.7"), entry("basic", rate="6.7", finish="foil"),
                   entry("holodeck", rate="6.7"), entry("holodeck", rate="1.7", finish="foil"),
                   entry("away", rate="6.7"), entry("away", rate="1.7", finish="foil")], percentages=True)
    sheet("stardates", [entry("stardates")])

    variants, probabilities = [], []
    for stardate, stardate_rate in ((False, Fraction(24, 25)), (True, Fraction(1, 25))):
        for klingon, klingon_rate in ((False, Fraction(971, 1000)), (True, Fraction(29, 1000))):
            for treatment, uncommon_rate in ((None, 781), ("scene", 77), ("lcars", 46),
                                             ("classic", 46), ("klingon", 50)):
                slots = [{"sheet": "common", "count": 7 - int(stardate) - int(klingon)},
                         {"sheet": "uncommon", "count": 3 - int(treatment is not None)}]
                if klingon:
                    slots.append({"sheet": "common-klingon", "count": 1})
                if treatment:
                    slots.append({"sheet": "uncommon-" + treatment, "count": 1})
                slots.extend({"sheet": name, "count": 1} for name in ("wildcard", "rare", "foil", "land"))
                if stardate:
                    slots.append({"sheet": "stardates", "count": 1})
                if sum(slot["count"] for slot in slots) != 14:
                    raise ValueError("TRK variant does not contain 14 cards")
                variants.append({"slots": slots})
                probabilities.append(stardate_rate * klingon_rate * Fraction(uncommon_rate, 1000))
    for variant, weight in zip(variants, integer_weights(probabilities)):
        variant["weight"] = weight
    product = {"id": PRODUCT_ID, "name": "Star Trek — Play (estimated)", "setCode": "TRK",
               "productType": "approximate", "authentic": False, "cardsPerPack": 14,
               "sheets": sheets, "variants": variants}
    if sum(len(sheet["cards"]) for sheet in sheets) > MAX_PRODUCT_CARDS:
        raise ValueError("TRK product exceeds the supported card-entry limit")
    product = compact_product(product)
    if len(encoded(product)) > MAX_ENCODED_PRODUCT_BYTES:
        raise ValueError("TRK product exceeds the event command size limit")
    report = {"source": SOURCE, "revision": REVISION, "productId": PRODUCT_ID,
              "missingPrintings": [], "printingCount": len(index),
              "printingSha256": hashlib.sha256(encoded([index[key] for key in sorted(index)])).hexdigest(),
              "groups": {name: {"setCode": code, "collectorNumbers": sorted(numbers), "rarities": expected}
                         for name, (code, numbers, expected) in GROUPS.items()},
              "estimatedProbabilities": estimates, "assumptions": ASSUMPTIONS,
              "productBytes": len(encoded(product)), "productSha256": hashlib.sha256(encoded(product)).hexdigest(),
              "limits": {"cardsPerPack": 14, "variants": len(variants), "sheets": len(sheets),
                         "maxEncodedBytes": MAX_ENCODED_PRODUCT_BYTES, "maxWeightedEntries": MAX_PRODUCT_CARDS}}
    return product, report


def upstream_product(row):
    product_id, raw = row
    try:
        product = json.loads(raw)
        if (product.get("id") != product_id or product.get("setCode") != "TRK"
                or product.get("productType") != "official" or product.get("authentic") is not True
                or not valid_text(product.get("name"), 128)
                or not positive_integer(product.get("cardsPerPack"), 30)
                or not isinstance(product.get("sheets"), list) or not 1 <= len(product["sheets"]) <= 128
                or not isinstance(product.get("variants"), list) or not 1 <= len(product["variants"]) <= 256
                or len(encoded(product)) > MAX_ENCODED_PRODUCT_BYTES):
            raise ValueError("invalid product envelope")
        pool = product.get("cardPool", [])
        if not isinstance(pool, list) or len(pool) > MAX_PRODUCT_CARDS:
            raise ValueError("invalid card pool")
        type_lines = {}

        def validate_card(card):
            if (not positive_integer(card.get("weight"))
                    or any(not valid_text(card.get(field), maximum) for field, maximum in
                           (("name", 256), ("setCode", 16), ("collectorNumber", 32)))
                    or any(not valid_text(card.get(field, ""), maximum, optional=True)
                           for field, maximum in (("typeLine", 256), ("rarity", 32), ("finish", 32)))
                    or card.get("pairCollectorNumber")):
                # MTGJSON builds ordinary sheets, including fixed pairs drawn
                # twice. A new paired-sheet extension needs explicit review.
                raise ValueError("invalid or unsupported printing identity")
            identity = (card["setCode"].strip().upper(), card["collectorNumber"].strip())
            type_line = card.get("typeLine", "").strip()
            if type_line:
                if identity in type_lines and type_lines[identity] != type_line:
                    raise ValueError("conflicting printing type lines")
                type_lines[identity] = type_line

        for card in pool:
            validate_card(card)
            if card["weight"] != 1:
                raise ValueError("card-pool weights must be one")
        sheets = {}
        total = 0
        for sheet in product["sheets"]:
            if (not valid_text(sheet.get("name"), 128) or sheet["name"] != sheet["name"].strip()
                    or sheet["name"] in sheets
                    or type(sheet.get("withReplacement", False)) is not bool
                    or type(sheet.get("excludePrevious", False)) is not bool
                    or "cards" in sheet and "cardRefs" in sheet):
                raise ValueError("invalid sheet envelope")
            cards = sheet.get("cards", sheet.get("cardRefs"))
            if (not isinstance(cards, list) or not cards
                    or any(not positive_integer(card.get("weight")) for card in cards)
                    or sum(card["weight"] for card in cards) > MAX_TOTAL_WEIGHT):
                raise ValueError("invalid sheet")
            if "cardRefs" in sheet:
                if any(not positive_integer(card.get("cardIndex"), len(pool)) for card in cards):
                    raise ValueError("invalid card reference")
            else:
                for card in cards:
                    validate_card(card)
            total += len(cards)
            sheets[sheet["name"]] = (len(cards), sheet.get("withReplacement", False))
        if total > MAX_PRODUCT_CARDS:
            raise ValueError("too many weighted entries")
        for variant in product["variants"]:
            slots = variant.get("slots")
            if (not positive_integer(variant.get("weight")) or not isinstance(slots, list)
                    or not 1 <= len(slots) <= 30 or len({slot["sheet"] for slot in slots}) != len(slots)
                    or any(slot["sheet"] not in sheets or not positive_integer(slot["count"], 30)
                           for slot in slots)
                    or sum(slot["count"] for slot in slots) != product["cardsPerPack"]):
                raise ValueError("invalid variant")
            if any(not sheets[slot["sheet"]][1] and slot["count"] > sheets[slot["sheet"]][0] for slot in slots):
                raise ValueError("slot needs more cards than its sheet provides")
        if sum(variant["weight"] for variant in product["variants"]) > MAX_TOTAL_WEIGHT:
            raise ValueError("variant weights exceed supported total")
        return product_id
    except (ValueError, TypeError, KeyError, AttributeError) as error:
        raise ValueError(f"TRK upstream product {product_id} is not usable: {error}") from error


def install(database):
    # The caller supplies a staging database, never a live client profile.
    # mode=rw cannot create a typo path; the transaction also rolls back a
    # failed metadata write after a successful product insertion.
    with closing(sqlite3.connect(Path(database).resolve().as_uri() + "?mode=rw", uri=True)) as connection, connection:
        package = dict(connection.execute("SELECT key,value FROM metadata WHERE key IN ('package','schema_version')"))
        if package != {"package": "default_cards", "schema_version": "10"}:
            raise ValueError("TRK installation requires a schema-10 Default Cards build database")
        upstream = connection.execute(
            "SELECT id,definition_json FROM limited_products WHERE upper(set_code)='TRK' "
            "AND product_type='official' AND authentic=1 AND id IN (?,?,?,?) ORDER BY id", UPSTREAM_IDS).fetchall()
        if upstream:
            selected = [upstream_product(row) for row in upstream]
            connection.execute("DELETE FROM limited_products WHERE id=?", (PRODUCT_ID,))
            connection.execute("DELETE FROM metadata WHERE key=?", (METADATA_KEY,))
            report = {"status": "upstream", "productIds": selected}
        else:
            rows = connection.execute(
                "SELECT name,upper(set_code),collector_number,type_line,rarity FROM cards "
                "WHERE upper(set_code) IN ('TRK','SDS') AND lang='en' AND digital=0 ORDER BY id").fetchall()
            cards = [dict(zip(("name", "setCode", "collectorNumber", "typeLine", "rarity"), row)) for row in rows]
            product, report = build_product(cards)
            connection.execute("INSERT OR REPLACE INTO limited_products "
                               "(id,name,set_code,product_type,authentic,definition_json) VALUES (?,?,?,?,?,?)",
                               (PRODUCT_ID, product["name"], "TRK", "approximate", 0, encoded(product).decode()))
            connection.execute("INSERT OR REPLACE INTO metadata (key,value) VALUES (?,?)",
                               (METADATA_KEY, encoded(report).decode()))
        connection.execute("INSERT OR REPLACE INTO metadata (key,value) VALUES "
                           "('limited_product_count', (SELECT count(*) FROM limited_products))")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path,
                        help="Staged schema-10 build database, not a live client profile")
    args = parser.parse_args()
    try:
        print(json.dumps(install(args.database), indent=2))
    except (OSError, ValueError, sqlite3.Error) as error:
        parser.exit(1, f"TRK product build failed: {error}\n")


if __name__ == "__main__":
    main()
