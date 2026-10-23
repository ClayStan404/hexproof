#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Generate a wholly synthetic, offline deck-editor acceptance fixture.

The output is independent of installed catalogs and user profiles. Supply its
cards.sqlite, fixture directory and manifest to run-native.py. Geometric PNGs
exercise the real image/cache path; they are not representative card artwork.
"""

import argparse
import copy
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import struct
import uuid
import zlib


SCHEMA = "hexproof.deck-editor-regression.v1"
CARD_COLUMNS = (
    "id TEXT PRIMARY KEY", "oracle_id TEXT", "name TEXT NOT NULL",
    "printed_name TEXT", "type_line TEXT", "set_code TEXT", "collector_number TEXT",
    "image_url TEXT", "image_status TEXT", "lang TEXT", "colors TEXT", "mana_value REAL",
    "rarity TEXT", "layout TEXT", "card_colors TEXT", "mana_cost TEXT", "legal_formats TEXT",
    "illustration_id TEXT", "released_at TEXT", "digital INTEGER", "power TEXT",
    "toughness TEXT", "oracle_text TEXT", "legality_statuses TEXT", "booster INTEGER",
    "related_cards TEXT",
)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def identifier(value):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "hexproof-native-regression/" + value))


def png_pattern(index, face):
    width, height = 252, 352
    color = ((index * 53 + 47) % 176 + 40, (index * 79 + 29) % 176 + 40,
             (index * 97 + face * 83) % 176 + 40)
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            border = min(x, y, width - 1 - x, height - 1 - y) < 10
            marker = 28 < y < 78 and (x // 28) % 2 == face % 2
            diagonal = abs(x - y * width // height) < 8
            rows.extend((18, 24, 30) if border else (245, 245, 245)
                        if marker or diagonal else color)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def card(name, number, *, set_code="RGX", layout="normal", zone="mainboard"):
    return {"name": name, "setCode": set_code, "collectorNumber": str(number), "count": 1,
            "typeLine": "Creature — Synthetic" + (" // Land" if layout == "modal_dfc" else
                        " // Creature — Synthetic" if layout == "transform" else ""),
            "manaValue": 2, "colors": "U", "cardColors": "U", "manaCost": "{1}{U}",
            "rarity": "common", "layout": layout, "zone": zone}


def create_catalog(path, cards):
    with closing(sqlite3.connect(path)) as database, database:
        database.execute("CREATE TABLE cards (" + ",".join(CARD_COLUMNS) + ")")
        database.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
        database.execute("""CREATE TABLE card_aliases (oracle_id TEXT, face_name TEXT,
            localized_name TEXT, localized_type TEXT, preferred INTEGER, face_order INTEGER,
            PRIMARY KEY (oracle_id, face_name, localized_name))""")
        database.execute("""CREATE TABLE localized_printings (id TEXT, face_name TEXT,
            oracle_id TEXT, name TEXT, localized_name TEXT, localized_type TEXT, set_code TEXT,
            collector_number TEXT, illustration_id TEXT, released_at TEXT, image_url TEXT,
            image_status TEXT, digital INTEGER, face_order INTEGER, layout TEXT,
            PRIMARY KEY (id, face_name))""")
        columns = [definition.split()[0] for definition in CARD_COLUMNS]
        for item in cards:
            printing = item["setCode"] + "/" + item["collectorNumber"]
            values = {"id": identifier(printing), "oracle_id": identifier(item["name"]),
                      "name": item["name"], "printed_name": item["name"],
                      "type_line": item["typeLine"], "set_code": item["setCode"].lower(),
                      "collector_number": item["collectorNumber"], "image_url": item["imageUrl"],
                      "image_status": "highres_scan", "lang": "en", "colors": "U",
                      "mana_value": 2, "rarity": "common", "layout": item["layout"],
                      "card_colors": "U", "mana_cost": "{1}{U}", "legal_formats": "modern",
                      "illustration_id": identifier(printing + "/art"), "released_at": "2026-01-01",
                      "digital": 0, "power": "2", "toughness": "2",
                      "oracle_text": "Synthetic acceptance fixture. No game rules claim.",
                      "legality_statuses": "modern:legal", "booster": 0, "related_cards": "[]"}
            database.execute("INSERT INTO cards VALUES (" + ",".join("?" for _ in columns) + ")",
                             [values[column] for column in columns])
        database.executemany("INSERT INTO metadata VALUES (?,?)", {
            "schema_version": "10", "package": "default_cards", "count": str(len(cards)),
            "generated_at": "synthetic-deck-editor-regression-v1", "alias_count": "0",
            "localized_printing_count": "0", "token_count": "0",
        }.items())


def generate(output, main_rows=80, side_rows=20):
    if main_rows < 60 or side_rows < 15:
        raise ValueError("At least 60 main and 15 side rows are required for acceptance")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Choose an empty output directory")
    images = output / "images"
    images.mkdir()
    main = [card("Preview A Modal // Preview A Garden", 1, layout="modal_dfc"),
            card("Preview B Transform // Preview B Reverse", 2, layout="transform"),
            card("Preview C Single", 3), card("Preview C Single", 3, set_code="RGY")]
    main += [card(f"Preview Row {index // 2:03d}", index + 10,
                  set_code="RGY" if index % 2 else "RGX")
             for index in range(main_rows - len(main))]
    side = [card(f"Sideboard Row {index:03d}", index + 1000, zone="sideboard")
            for index in range(side_rows)]
    positive = {}
    for index, item in enumerate(main + side):
        faces = item["name"].split(" // ")
        independent = [{"name": name, "faceName": name if face else "", "displayName": name,
                        "typeLine": item["typeLine"].split(" // ")[face],
                        "setCode": item["setCode"], "collectorNumber": item["collectorNumber"]}
                       for face, name in enumerate(faces)] if len(faces) == 2 else []
        for face, name in enumerate(faces):
            filename = f"synthetic-{index:03d}-face-{face}.png"
            (images / filename).write_bytes(png_pattern(index, face))
            image_url = f"https://deck-regression.invalid/{filename}"
            if face == 0:
                item["imagePath"] = "@PROFILE@/images/" + filename
                item["imageUrl"] = image_url
            # Complete deck metadata avoids startup hydration. The two cold
            # preview cards deliberately retain an older subtype; real cache
            # availability then publishes a same-printing metadata refresh.
            cached_type = item["typeLine"].replace("Synthetic", "Synthetic Refreshed") \
                if index < 2 else item["typeLine"]
            record = {"requestedName": name, "name": item["name"], "localizedName": "",
                      "typeLine": cached_type, "oracleId": identifier(item["name"]),
                      "setCode": item["setCode"], "collectorNumber": item["collectorNumber"],
                      "imagePath": "@PROFILE@/images/" + filename, "imageUrl": image_url,
                      "imageLanguage": "en", "resolutionVersion": 6,
                      "usesSubstituteArt": False, "reusesLocalArt": False,
                      "localizedRulesChecked": True, "oracleTextLanguage": "en",
                      "oracleText": "Synthetic acceptance fixture.", "layout": item["layout"],
                      "faceName": name if len(faces) == 2 else "", "faceMetadataChecked": True,
                      "faceMetadataSetCode": item["setCode"],
                      "faceMetadataCollectorNumber": item["collectorNumber"],
                      "independentFaces": independent, "printingId": identifier(
                          item["setCode"] + "/" + item["collectorNumber"])}
            key = f"en|{name.casefold()}|{item['setCode']}|{item['collectorNumber']}"
            positive[key] = record
            if face == 0 and len(faces) == 2:
                canonical = copy.deepcopy(record)
                canonical["requestedName"] = item["name"]
                positive[f"en|{item['name'].casefold()}|{item['setCode']}|{item['collectorNumber']}"] = canonical
    create_catalog(output / "cards.sqlite", main + side)
    write_json(output / "card-cache.json", {"version": 6, "negativeVersion": 2,
               "faceAuditVersion": 3, "faceRepairNeeded": False, "positive": positive, "negative": {}})
    deck_fields = ("name", "setCode", "collectorNumber", "count", "typeLine", "manaValue",
                   "colors", "cardColors", "manaCost", "rarity", "imagePath")
    write_json(output / "decks.json", {"version": 1, "decks": [{"id": "deck-editor-regression",
               "name": "Synthetic deck editor regression", "format": "modern", "deckFormat": "custom",
               "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z",
               "mainboard": [{key: item[key] for key in deck_fields} for item in main],
               "sideboard": [{key: item[key] for key in deck_fields} for item in side]}]})
    identity = lambda item: {key: item[key] for key in ("name", "setCode", "collectorNumber")}
    write_json(output / "manifest.json", {"schema": SCHEMA, "synthetic": True,
               "art": "Generated geometric PNG patterns; not real card illustrations",
               "catalog": "Generated schema-10 metadata; no installed user catalog or network required",
               "mainRows": len(main), "sideRows": len(side), "sourceCold": identity(main[0]),
               "heldCold": identity(main[1]), "singleFace": identity(main[2]),
               "sameNameSibling": identity(main[3]), "filter": "Preview",
               "coldRefresh": "Deck subtype is stale; cached canonical-front availability updates it",
               "files": {name: hashlib.sha256((output / name).read_bytes()).hexdigest()
                         for name in ("cards.sqlite", "decks.json", "card-cache.json")}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--main-rows", type=int, default=80)
    parser.add_argument("--side-rows", type=int, default=20)
    args = parser.parse_args()
    try:
        generate(args.output, args.main_rows, args.side_rows)
    except (OSError, ValueError, sqlite3.Error) as error:
        parser.error(str(error))
    print(args.output / "manifest.json")


if __name__ == "__main__":
    main()
