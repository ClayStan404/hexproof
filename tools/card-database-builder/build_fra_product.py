#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Install a maintained, explicitly estimated FRA Play recipe into a built catalog."""

from __future__ import annotations

import argparse
from fractions import Fraction
import json
from math import gcd, lcm
from pathlib import Path
import sqlite3

SOURCE = "https://magic.wizards.com/en/news/feature/collecting-reality-fracture"
REVISION = "2026-09-19.1"
PRODUCT_ID = "hexproof-fra-play"
DUALS = {175, 177, 178, 182, 183, 184, 190, 192, 193, 194}


def build_product(cards: list[dict]) -> tuple[dict, dict]:
    # Database printing identity is set/number. Never count translations or
    # duplicate records as additional copies of an English printing.
    index = {(c["setCode"], c["collectorNumber"]): c for c in cards}
    fra = {int(n): c for (s, n), c in index.items() if s == "FRA" and n.isdigit()}
    pairs = json.loads(Path(__file__).with_name("fra-pairs.json").read_text())["pairs"]
    missing = []
    expected = list(range(1, 331)) + list(range(335, 359)) + list(range(363, 402))
    for number in expected:
        if number not in fra:
            missing.append(f"FRA/{number}")
    for number in range(159, 169):
        if ("SPG", str(number)) not in index:
            missing.append(f"SPG/{number}")

    def group(low, high, rarity=None):
        return [c for n, c in sorted(fra.items()) if low <= n <= high
                and (rarity is None or c["rarity"] == rarity)]

    def echo_group(low, high, rarity):
        pool = {c["name"]: c for c in group(low, high, rarity)}
        result = []
        for a, b in pairs:
            if a in pool and b in pool:
                result.extend([{**pool[a], "pairCollectorNumber": pool[b]["collectorNumber"]},
                               {**pool[b], "pairCollectorNumber": pool[a]["collectorNumber"]}])
        return result

    base = {r: [c for n, c in sorted(fra.items()) if n <= 194 and n not in DUALS
                and c["rarity"] == r] for r in ("common", "uncommon", "rare", "mythic")}
    echoes = {r: echo_group(195, 280, r) for r in ("uncommon", "rare", "mythic")}
    border = {r: echo_group(291, 320, r) for r in echoes}
    brain = {r: group(363, 381, r) for r in echoes}
    strong = {r: group(335, 358, r) for r in ("rare", "mythic")}
    shattered = {r: group(321, 330, r) for r in ("rare", "mythic")}
    portal = group(397, 401)
    sheets = []

    def sheet(name, groups, *, paired=False, exclude=False):
        weighted = []
        for pool, rate, finish in groups:
            if not pool:
                raise ValueError(f"FRA {name}: a required category has no available cards")
            for card in pool:
                entry = {**card, "finish": finish}
                if not paired:
                    entry.pop("pairCollectorNumber", None)
                weighted.append((entry, Fraction(str(rate)) / len(pool)))
        denominator = lcm(*(w.denominator for _, w in weighted))
        weights = [int(w * denominator) for _, w in weighted]
        divisor = gcd(*weights)
        entries = [{**c, "weight": w // divisor} for (c, _), w in zip(weighted, weights)]
        if max(c["weight"] for c in entries) > 9_007_199_254_740_991:
            raise ValueError("FRA sheet exceeds JSON-safe weights")
        sheets.append({"name": name, "withReplacement": False,
                       "excludePrevious": exclude, "cards": entries})

    def nf(pool, rate):
        return pool, rate, "nonfoil"

    sheet("common", [nf(base["common"], 1)])
    sheet("uncommon", [nf(base["uncommon"], "96.2"), nf(brain["uncommon"], "3.8")])
    sheet("wildcard", [nf(base["common"], 23), nf(base["uncommon"], 74),
                       nf(brain["uncommon"], 3)], exclude=True)
    echo_groups = [nf(echoes["uncommon"], "88.9"), nf(echoes["rare"], "6.7"),
                   nf(echoes["mythic"], "1.4"), nf(border["uncommon"], "1.7"),
                   nf(border["rare"], ".65"), nf(border["mythic"], ".65")]
    sheet("echo-pair", echo_groups, paired=True)
    sheet("echo-single", echo_groups, exclude=True)
    sheet("rare", [nf(base["rare"], "74.4"), nf(base["mythic"], "14.8"),
                   nf(shattered["rare"], 1), nf(shattered["mythic"], ".45"),
                   nf(strong["rare"], "3.8"), nf(strong["mythic"], 1),
                   nf(brain["rare"], "3.1"), nf(brain["mythic"], ".45"), nf(portal, 1)])
    foil = [(base["common"], "49.5", "foil")]
    for rarity, rate in [("uncommon", "40.5"), ("rare", 6), ("mythic", "1.2")]:
        foil.append((base[rarity] + echoes[rarity], rate, "foil"))
    # Nine categories published only as <1%; split the remaining 2.8% evenly.
    for pool in [*border.values(), *brain.values(), *strong.values(), portal]:
        foil.append((pool, Fraction(28, 90), "foil"))
    sheet("foil", foil)
    sheet("land", [(group(281, 290), "14.6", "nonfoil"),
                   (group(281, 290), "3.6", "foil"),
                   (group(382, 396), "21.8", "nonfoil"),
                   (group(382, 396), "5.5", "foil"),
                   ([fra[n] for n in sorted(DUALS) if n in fra], "43.6", "nonfoil"),
                   ([fra[n] for n in sorted(DUALS) if n in fra], "10.9", "foil")])
    sheet("spg", [nf([index[("SPG", str(n))] for n in range(159, 169)
                       if ("SPG", str(n)) in index], 1)])
    variants = []
    for spg in (False, True):
        slots = [{"sheet": "common", "count": 5 if spg else 6},
                 {"sheet": "uncommon", "count": 1}, {"sheet": "wildcard", "count": 1},
                 {"sheet": "rare", "count": 1}, {"sheet": "echo-pair", "count": 1},
                 {"sheet": "echo-single", "count": 1}, {"sheet": "foil", "count": 1},
                 {"sheet": "land", "count": 1}]
        if spg:
            slots.append({"sheet": "spg", "count": 1})
        variants.append({"weight": 1 if spg else 54, "slots": slots})
    label = "partial preview, estimated" if missing else "estimated"
    product = {"id": PRODUCT_ID, "name": f"Reality Fracture — Play ({label})",
               "setCode": "FRA", "productType": "approximate", "authentic": False,
               "cardsPerPack": 14, "sheets": sheets, "variants": variants}
    encoded = json.dumps(product, ensure_ascii=False, separators=(",", ":"))
    if len(encoded.encode()) > 800 * 1024 or sum(len(s["cards"]) for s in sheets) > 5000:
        raise ValueError("FRA product exceeds event command bounds")
    report = {"source": SOURCE, "revision": REVISION, "missingPrintings": missing,
              "completeBasePairs": sum(len(v) for v in echoes.values()) // 2,
              "completeBorderlessPairs": sum(len(v) for v in border.values()) // 2,
              "productBytes": len(encoded.encode()), "productId": PRODUCT_ID}
    return product, report


def install(database: Path) -> dict:
    with sqlite3.connect(database) as connection:
        rows = connection.execute("SELECT name, upper(set_code), collector_number, type_line, rarity "
                                  "FROM cards WHERE lower(set_code) IN ('fra','spg') "
                                  "AND lang = 'en' AND digital = 0 ORDER BY id").fetchall()
        cards = [dict(zip(("name", "setCode", "collectorNumber", "typeLine", "rarity"), r)) for r in rows]
        product, report = build_product(cards)
        connection.execute("INSERT OR REPLACE INTO limited_products "
                           "(id,name,set_code,product_type,authentic,definition_json) VALUES (?,?,?,?,?,?)",
                           (product["id"], product["name"], "FRA", "approximate", 0,
                            json.dumps(product, ensure_ascii=False, separators=(",", ":"))))
        connection.execute("INSERT OR REPLACE INTO metadata VALUES ('limited_product_count', "
                           "(SELECT count(*) FROM limited_products))")
        connection.execute("INSERT OR REPLACE INTO metadata VALUES ('fra_collation', ?)",
                           (json.dumps(report, separators=(",", ":")),))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    args = parser.parse_args()
    if not args.database.is_file():
        parser.error("database must already exist")
    print(json.dumps(install(args.database), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
