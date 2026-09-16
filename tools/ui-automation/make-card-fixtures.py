#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Build reproducible import texts from a read-only local card catalog.

These are diverse manual-table test decks, not competitive deck recommendations.
Legality means the recorded catalog snapshot, not a live ban-list certification.
No application profile, image cache, or production catalog is written.
"""

import argparse
import copy
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys


FORMATS = ("custom", "standard", "pioneer", "modern", "legacy", "vintage",
           "pauper", "duel", "commander", "cube")
PLAYABLE_LAYOUTS = {"normal", "transform", "modal_dfc", "adventure", "prepare",
                    "split", "flip", "meld", "prototype", "saga", "class",
                    "leveler", "mutate", "case"}
SHAPES = ("instant", "creature", "sorcery", "artifact", "enchantment", "planeswalker",
          "nonbasic_land", "transform", "modal_dfc", "prepare", "adventure", "split",
          "flip", "meld", "prototype", "saga", "class", "battle", "multicolor",
          "hybrid_mana", "x_mana")
BASICS = ("Plains", "Island", "Swamp", "Mountain", "Forest")
PREFERRED = (("MH3", "238"), ("SOS", "13"), ("V17", "7"), ("CLB", "827"),
             ("DDJ", "32"), ("DSK", "43"), ("CHK", "153"), ("V17", "5"),
             ("EMN", "28"), ("BRO", "75"), ("MOM", "194"), ("JGP", "1"))
FIELDS = ("id", "oracle_id", "name", "set_code", "collector_number", "layout",
          "type_line", "colors", "card_colors", "mana_cost", "mana_value",
          "legality_statuses", "oracle_text", "related_cards")


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def statuses(card):
    return dict(part.split(":", 1) for part in card["legality_statuses"].split("|") if ":" in part)


def front_type(card):
    return card["type_line"].split(" // ", 1)[0]


def is_basic(card):
    return "Basic" in front_type(card) and "Land" in front_type(card)


def physical_card(card):
    if (card["layout"] not in PLAYABLE_LAYOUTS or not card["oracle_id"]
            or not card["set_code"] or not card["collector_number"]):
        return False
    # Scryfall also gives meld results legal statuses. They are back faces of
    # their components, not additional physical cards to register in a deck.
    parts = json.loads(card["related_cards"] or "[]")
    return not any(part.get("component") == "meld_result"
                   and (part.get("id") == card["id"] or part.get("name") == card["name"])
                   for part in parts)


def tags(card):
    result = {card["layout"]}
    first = front_type(card)
    for kind in ("Instant", "Creature", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Battle"):
        if kind in first:
            result.add(kind.lower())
    if "Land" in first:
        result.add("basic_land" if is_basic(card) else "nonbasic_land")
    if len(card["card_colors"]) > 1:
        result.add("multicolor")
    if "/" in card["mana_cost"].replace(" // ", ""):
        result.add("hybrid_mana")
    if "{X}" in card["mana_cost"]:
        result.add("x_mana")
    return result


def card_order(card):
    printing = (card["set_code"].upper(), card["collector_number"])
    rank = PREFERRED.index(printing) if printing in PREFERRED else len(PREFERRED)
    return (rank, card["name"].casefold(), not card["collector_number"].isdigit(),
            len(card["collector_number"]), card["collector_number"], card["set_code"], card["id"])


def load_catalog(path):
    path = path.resolve(strict=True)
    digest = hashlib.sha256()
    cards = []
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as database:
        database.row_factory = sqlite3.Row
        database.execute("BEGIN")
        metadata = dict(database.execute("SELECT key, value FROM metadata ORDER BY key"))
        if metadata.get("schema_version") != "10":
            raise ValueError("A schema-10 catalog with legality and face metadata is required")
        digest.update(canonical_json(metadata).encode())
        # All selection fields and candidates participate in a logical hash
        # inside one read transaction, including uncheckpointed WAL contents.
        for row in database.execute("SELECT " + ",".join(FIELDS) +
                                    " FROM cards WHERE digital=0 AND lang='en' ORDER BY id"):
            card = {key: (row[key] if row[key] is not None else "") for key in FIELDS}
            digest.update(b"\n" + canonical_json(card).encode())
            cards.append(card)
    return cards, {"path": str(path), "metadata": metadata,
                   "sha256": digest.hexdigest(), "hashKind": "logical-selection-v1",
                   "candidatePrintings": len(cards), "access": "sqlite-mode-ro"}


def row(card, deck_format, count=1):
    faces = (card["name"].split(" // ") if card["layout"] in
             ("transform", "modal_dfc", "double_faced_token", "reversible_card") else [card["name"]])
    return {"id": card["id"], "oracleId": card["oracle_id"], "name": card["name"],
            "setCode": card["set_code"], "collectorNumber": card["collector_number"],
            "layout": card["layout"], "typeLine": card["type_line"],
            "colorIdentity": card["colors"], "cardColors": card["card_colors"],
            "manaCost": card["mana_cost"], "manaValue": card["mana_value"],
            "legalStatus": statuses(card).get(deck_format, "not_applicable"),
            "legalityStatuses": statuses(card), "shapes": sorted(tags(card)), "count": count,
            "faces": faces, "imageFaceCount": len(faces),
            "relatedCards": json.loads(card["related_cards"] or "[]")}


def eligible(cards, deck_format):
    # Custom and Cube deliberately have no construction-policy claim, but use
    # Commander-legal physical cards to exclude novelty/non-game objects.
    policy = "commander" if deck_format in ("custom", "cube") else deck_format
    unique = {}
    for card in sorted(cards, key=card_order):
        state = statuses(card).get(policy)
        if physical_card(card) and (state == "legal" or (policy == "vintage" and state == "restricted")):
            unique.setdefault(card["oracle_id"], card)
    return list(unique.values())


def choose_diverse(candidates, count, initial=()):
    chosen = list(initial)
    identities = {card["oracle_id"] for card in chosen}

    def append(card):
        if len(chosen) < count and card["oracle_id"] not in identities:
            chosen.append(card)
            identities.add(card["oracle_id"])

    for shape in SHAPES:
        # Ordinary instant/creature actions should have an uncomplicated
        # single-face representative even when a preferred MDFC matches too.
        options = [card for card in candidates if shape in tags(card)]
        if shape in ("instant", "creature"):
            options.sort(key=lambda card: card["layout"] != "normal")
        if options:
            append(options[0])
    for card in candidates:
        append(card)
        if len(chosen) == count:
            break
    if len(chosen) != count:
        raise ValueError(f"Only {len(chosen)} eligible distinct cards; {count} required")
    return chosen


def describe_deck(deck_format, mainboard, sideboard, commanders, available):
    shape_cards = {}
    # Generic library/hand actions must not choose a card starting in command.
    for card in sorted(mainboard, key=lambda card: card["name"] in commanders):
        for shape in card["shapes"]:
            shape_cards.setdefault(shape, card)
    for shape in ("instant", "creature"):
        ordinary = next((card for card in mainboard
                         if shape in card["shapes"] and card["layout"] == "normal"
                         and card["name"] not in commanders), None)
        if ordinary:
            shape_cards[shape] = ordinary
    return {"name": "Card shapes — " + deck_format, "deckFormat": deck_format,
            "tableMode": {"duel": "duel", "commander": "edh"}.get(deck_format, "modern"),
            "mainboard": mainboard, "sideboard": sideboard, "commanders": commanders,
            "mainCount": sum(card["count"] for card in mainboard),
            "sideCount": sum(card["count"] for card in sideboard),
            "shapeCards": shape_cards, "shapeCoverage": sorted(shape_cards),
            "unavailableShapes": sorted(set(SHAPES) - available),
            "validationExpectation": {"valid": True, "basis": "recorded-catalog-snapshot"}}


def make_deck(cards, deck_format, cube_size):
    pool = eligible(cards, deck_format)
    commanders = []
    initial = []
    if deck_format in ("duel", "commander"):
        choices = [card for card in pool if "Legendary" in front_type(card)
                   and "Creature" in front_type(card) and card["layout"] == "normal"]
        choices.sort(key=lambda card: (card["name"] != "Kenrith, the Returned King",
                                       -len(card["colors"]), card_order(card)))
        if not choices:
            raise ValueError(f"No eligible single commander for {deck_format}")
        commander = choices[0]
        commanders = [commander["name"]]
        initial = [commander]
        pool = [card for card in pool if set(card["colors"]) <= set(commander["colors"])]
    available = set().union(*(tags(card) for card in pool))
    if deck_format == "cube":
        main = choose_diverse(pool, cube_size)
        return describe_deck(deck_format, [row(card, deck_format) for card in main], [], [], available)

    land_count = 37 if commanders else 24
    total = 100 if commanders else 60
    nonbasics = [card for card in pool if not is_basic(card)]
    main = choose_diverse(nonbasics, total - land_count, initial)
    lands = [next((card for card in pool if card["name"] == name and is_basic(card)), None)
             for name in BASICS + ("Wastes",)]
    lands = [card for card in lands if card is not None]
    if not lands:
        raise ValueError(f"No legal basic land for {deck_format}")
    # Wastes is used only for an entirely colorless commander/pool.
    colored = [card for card in lands if card["name"] != "Wastes"]
    lands = colored or lands
    mainboard = [row(card, deck_format) for card in main]
    for index, land in enumerate(lands):
        mainboard.append(row(land, deck_format, land_count // len(lands) + (index < land_count % len(lands))))
    used = {card["oracle_id"] for card in main}
    side = [] if commanders else choose_diverse(
        [card for card in nonbasics if card["oracle_id"] not in used], 15)
    return describe_deck(deck_format, mainboard, [row(card, deck_format) for card in side], commanders, available)


def deck_text(deck):
    def lines(cards):
        return [f"{card['count']} {card['name']} ({card['setCode']}) {card['collectorNumber']}"
                for card in cards]

    commander_names = set(deck["commanders"])
    output = ["Deck", *lines(card for card in deck["mainboard"] if card["name"] not in commander_names)]
    if deck["sideboard"]:
        output += ["", "Sideboard", *lines(deck["sideboard"])]
    if commander_names:
        output += ["", "Commander", *[line + " *CMDR*" for line in lines(
            card for card in deck["mainboard"] if card["name"] in commander_names)]]
    return "\n".join(output) + "\n"


def negative_decks(decks):
    result = {}
    for name, original in decks.items():
        if name in ("custom", "cube"):
            continue
        invalid = copy.deepcopy(original)
        invalid["name"] += " — short main"
        basic = next(card for card in invalid["mainboard"] if "basic_land" in card["shapes"])
        basic["count"] -= 1
        invalid["mainCount"] -= 1
        advisory = name == "commander"
        invalid["validationExpectation"] = {
            "valid": advisory, "warning": advisory,
            "reason": "commander-size-advisory" if advisory else "main-deck-too-small"}
        result[name + "-short-main"] = invalid
        if name not in ("duel", "commander"):
            invalid = copy.deepcopy(original)
            invalid["name"] += " — oversized sideboard"
            invalid["sideboard"][0]["count"] += 1
            invalid["sideCount"] = 16
            invalid["validationExpectation"] = {"valid": False, "reason": "sideboard-over-15"}
            result[name + "-oversized-sideboard"] = invalid
    return result


def generate(catalog, output, formats=FORMATS, cube_size=960):
    if not 90 <= cube_size <= 12000:
        raise ValueError("Cube size must be between 90 and 12000 physical cards")
    if len(set(formats)) != len(formats) or not formats or any(name not in FORMATS for name in formats):
        raise ValueError("Choose distinct supported non-Forge formats")
    cards, source = load_catalog(catalog)
    decks = {name: make_deck(cards, name, cube_size) for name in FORMATS if name in formats}
    negatives = negative_decks(decks)
    output.mkdir(parents=True, exist_ok=False)
    for folder, entries in (("decks", decks), ("negative", negatives)):
        (output / folder).mkdir()
        for name, deck in entries.items():
            text = deck_text(deck)
            deck["textFile"] = f"{folder}/{name}.txt"
            deck["textSha256"] = hashlib.sha256(text.encode()).hexdigest()
            (output / deck["textFile"]).write_text(text, encoding="utf-8")
    auxiliary = []
    for layout in ("token", "double_faced_token", "emblem"):
        candidate = next((card for card in sorted(cards, key=card_order)
                          if card["layout"] == layout and ("Token" in card["type_line"]
                                                           or "Emblem" in card["type_line"])), None)
        if candidate:
            auxiliary.append(row(candidate, "custom"))
    manifest = {"schema": "hexproof.card-shape-fixtures.v1", "evidence": "fixture-setup",
                "source": source, "rulesMode": "manual", "imagesPrecached": False,
                "decks": decks, "negativeDecks": negatives, "auxiliaryCards": auxiliary,
                "limitations": ["Catalog-snapshot legality; not current tournament certification.",
                                "Manual tabletop scenarios do not execute card rules.",
                                "Single commanders only; partner pairing is not inferred."]}
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                         encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New output directory; never overwritten")
    parser.add_argument("--formats", nargs="+", choices=FORMATS, default=list(FORMATS))
    parser.add_argument("--cube-size", type=int, default=960)
    args = parser.parse_args()
    try:
        manifest = generate(args.catalog, args.output, args.formats, args.cube_size)
    except (OSError, ValueError, sqlite3.Error) as error:
        parser.error(str(error))
    print(f"Generated {len(manifest['decks'])} decks: {args.output / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
