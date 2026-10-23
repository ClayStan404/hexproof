#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Join frozen decks to actual native, projection, and Qt replay evidence."""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re


def records(path):
    result = {}
    with path.open() as stream:
        for line in stream:
            record = json.loads(line)
            key = (record["card"], record["case"])
            if key in result:
                raise ValueError(f"Duplicate case: {key}")
            result[key] = record
    return result


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def summarize(manifest, native, projected, log):
    if any(marker in log for marker in ("FAIL!", "QWARN", "QFATAL")):
        raise ValueError("Qt replay contains failures or warnings")
    if not re.search(r"Totals: \d+ passed, 0 failed, 0 skipped", log):
        raise ValueError("Qt replay did not complete without skips")
    ui_passes = set(re.findall(r"PASS\s+: .*::test_native_frames\((.+)\)", log))
    names = {card["name"] for deck in manifest["decks"]
             for section in ("mainboard", "sideboard") for card in deck[section]}
    if {name for name, _ in native} != names or set(native) != set(projected):
        raise ValueError("Native or projected evidence does not cover exactly the frozen card set")
    if ui_passes != {name + "/" + case for name, case in native}:
        raise ValueError("Qt pass records do not cover exactly the native cases")
    by_card = defaultdict(list)
    decisions = Counter()
    for key, record in native.items():
        if record["status"] != "resolved" or projected[key]["nativeStatus"] != "resolved":
            raise ValueError(f"Native case did not resolve: {key}")
        frames = record["frames"]
        if len(record.get("after", [])) != 3 or len(projected[key]["after"]) != 3:
            raise ValueError(f"Missing final viewer projections: {key}")
        if len(frames) != len(projected[key]["frames"]) or any(len(frame["snapshots"]) != 3 for frame in frames):
            raise ValueError(f"Missing decision projections: {key}")
        kinds = Counter(frame["prompt"]["input"]["type"] for frame in frames)
        decisions.update(kinds)
        by_card[key[0]].append({"case": key[1], "finalZone": record["finalZone"],
                               "resolvedStackObjects": record["resolvedStackObjects"],
                               "decisions": dict(kinds), "native": "resolved", "projection": "passed",
                               "uiReplay": "passed"})
    cards = []
    for name in sorted(names):
        entry = native.get((name, "play-and-resolve"))
        if entry is None:
            raise ValueError(f"Missing ordinary play: {name}")
        expected = {"play-and-resolve"} | {
            f"ability-{ability['index']}" for ability in entry["abilityInventory"]
            if not ability["spell"] and not ability["land"]}
        if {row["case"] for row in by_card[name]} != expected:
            raise ValueError(f"Missing initial activated ability: {name}")
        decks = [deck["id"] for deck in manifest["decks"] if any(
            card["name"] == name for section in ("mainboard", "sideboard") for card in deck[section])]
        cards.append({"name": name, "type": entry["type"], "decks": decks,
                      "initialAbilityInventory": entry["abilityInventory"], "cases": by_card[name]})
    decks = []
    for deck in manifest["decks"]:
        deck_names = sorted({card["name"] for section in ("mainboard", "sideboard") for card in deck[section]})
        decks.append({"id": deck["id"], "format": deck["format"], "name": deck["name"],
                      "source": deck["source"], "cards": deck_names,
                      "uniqueCards": len(deck_names), "cases": sum(len(by_card[name]) for name in deck_names),
                      "native": "resolved", "projection": "passed", "uiReplay": "passed"})
    return {"schema": 1, "decks": decks, "cards": cards,
            "totals": {"decks": len(decks), "cards": len(cards), "cases": len(native),
                       "decisions": sum(decisions.values()), "decisionKinds": dict(decisions)},
            "coverage": {
                "fixture": "Synthetic two-player boards, 120 floating mana per seat; native human controllers and actual card scripts",
                "checks": ["Native ordinary play and each initially available non-spell ability complete",
                           "Stack and waiting triggers settle; the source leaves the casting transaction",
                           "Three viewer snapshots normalize through the production server projection",
                           "UI responses reproduce the exact decisions accepted by the native engine",
                           "Native selection markers and persistent annotations remain visible"],
                "limits": ["Not complete matches or an independent Oracle conformance proof for every effect",
                           "Alternate spell faces, every modal branch, dynamically gained abilities, later triggers and combinations are not exhaustive",
                           "Qt replay uses captured native frames, synthetic catalog labels and no card art; live network scenarios are reported separately",
                           "Qt injected input does not establish OS input routing"]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("decks-2026-09-22.json"))
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--ui", type=Path, required=True)
    parser.add_argument("--ui-log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = summarize(json.loads(args.manifest.read_text()), records(args.native), records(args.ui), args.ui_log.read_text())
    result["evidence"] = {key: {"path": str(path), "sha256": digest(path)} for key, path in
                          (("manifest", args.manifest), ("native", args.native), ("projection", args.ui), ("qml", args.ui_log))}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "coverage.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    with (args.output / "cards.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["card", "decks", "cases", "decisions", "native", "projection", "ui_replay"])
        for card in result["cards"]:
            writer.writerow([card["name"], ";".join(card["decks"]), len(card["cases"]),
                             sum(sum(case["decisions"].values()) for case in card["cases"]), "resolved", "passed", "passed"])
    print(json.dumps(result["totals"], indent=2))


if __name__ == "__main__":
    main()
