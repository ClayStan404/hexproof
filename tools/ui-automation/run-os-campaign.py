#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Prepare and run the frozen 40-deck / 30-Limited system-input campaign."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[2]


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def prepare(output, catalog):
    source = ROOT / "tools/forge-card-corpus/decks-2026-09-22.json"
    corpus = json.loads(source.read_text())
    assert Counter(d["format"] for d in corpus["decks"]) == dict.fromkeys(
        ["standard", "pioneer", "modern", "legacy"], 10)
    verified = json.loads((ROOT / "tools/ui-automation/fixtures/format-matches.json").read_text())
    known = {c["name"]: c for d in verified["formats"].values() for zone in ["mainboard", "sideboard"] for c in d[zone]}
    connection = sqlite3.connect(f"file:{catalog}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    def normalized(name):
        return "".join(c for c in unicodedata.normalize("NFKD", name.replace("’", "'"))
                       if not unicodedata.combining(c)).casefold()
    names = {}
    for row in connection.execute("""SELECT DISTINCT name FROM cards WHERE lang='en' AND digital=0
            AND layout NOT IN ('art_series','token','double_faced_token','emblem')"""):
        names[normalized(row[0])] = row[0]
    for name in list(names.values()):
        for face in name.split(" // "):
            names.setdefault(normalized(face), name)
    wanted = {names.get(normalized(c["name"]), c["name"]) for d in corpus["decks"]
              for zone in ["mainboard", "sideboard"] for c in d[zone]}
    candidates_by_name = {}
    for row in connection.execute("""SELECT * FROM cards WHERE lang='en' AND digital=0
            AND layout NOT IN ('art_series','token','double_faced_token','emblem')
            AND name IN (""" + ",".join("?" for _ in wanted) + """)
            ORDER BY CASE WHEN set_code LIKE 'p%' THEN 1 ELSE 0 END, released_at, set_code,
                     CAST(collector_number AS INTEGER), collector_number""", tuple(wanted)):
        candidates_by_name.setdefault(row["name"], []).append(row)
    cache = {}

    def card(entry):
        name = entry["name"]
        lookup = names.get(normalized(name), name)
        if name in cache:
            return dict(cache[name], count=entry["count"])
        candidates = candidates_by_name.get(lookup, [])
        if not candidates:
            raise ValueError("Missing catalog card: " + name)
        chosen = candidates[0]
        if name in known:
            exact = known[name]
            chosen = next((c for c in candidates if c["set_code"].upper() == exact["setCode"].upper()
                           and c["collector_number"] == exact["collectorNumber"]), chosen)
        cache[name] = {"name": chosen["name"], "count": entry["count"], "setCode": chosen["set_code"].upper(),
                "collectorNumber": chosen["collector_number"], "manaValue": chosen["mana_value"],
                "manaCost": chosen["mana_cost"], "typeLine": chosen["type_line"],
                "cardColors": chosen["card_colors"], "sourceName": name}
        return dict(cache[name])

    decks = []
    for published in corpus["decks"]:
        deck = dict(published, deckFormat=published["format"], format="modern")
        deck["mainboard"] = [card(c) for c in published["mainboard"]]
        deck["sideboard"] = [card(c) for c in published["sideboard"]]
        decks.append(deck)
    connection.close()
    opponents = {"standard": "standard-01-", "pioneer": "pioneer-09-", "modern": "modern-07-", "legacy": "legacy-03-"}
    plan = []
    for deck in decks:
        opponent = next(d for d in decks if d["id"].startswith(opponents[deck["deckFormat"]]))
        manifest = output / "manifests" / (deck["id"] + ".json")
        write(manifest, {"schema": 1, "decks": [deck, opponent], "sourceManifest": str(source),
                         "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest()})
        plan.append({"id": deck["id"], "format": deck["deckFormat"], "deck": deck["name"],
                     "source": deck["source"], "opponent": opponent["name"], "players": 2,
                     "variant": "format-" + deck["deckFormat"], "manifest": str(manifest),
                     "scenario": "ForgeDesktopMatch.qml"})
    for mode in ["set_sealed", "set_draft", "cube_draft"]:
        for number in range(1, 11):
            plan.append({"id": f"{mode}-{number:02d}", "format": mode, "players": 3,
                         "variant": mode + "-forge", "scenario": "LimitedLifecycle.qml"})
    write(output / "plan.json", {"schema": 1, "createdAt": datetime.now(timezone.utc).isoformat(),
          "requiredRuns": 70, "requiredInput": "system-input", "runs": plan})
    return plan


def release_catalog_copies(run):
    """Retain profile hashes/evidence and discard only our reproducible DB copies."""
    released = []
    for path in run.glob("seat-*/data/Hexproof/Hexproof/cards.sqlite"):
        if path.is_symlink() or not path.resolve().is_relative_to(run.resolve()):
            raise ValueError("Refusing to remove a catalog outside the owned run")
        released.append({"path": str(path), "bytes": path.stat().st_size})
        path.unlink()
    write(run / "released-catalog-copies.json", released)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--fixture-dir", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--refresh-manifests", action="store_true", help="Resolve the frozen source decks against the current catalog again")
    parser.add_argument("--select", default="", help="Comma-separated run IDs; empty runs all remaining cases")
    parser.add_argument("--attempt", default="r1")
    parser.add_argument("--keep-going", action="store_true", help="Collect independent failures before repairing them")
    args = parser.parse_args()
    output, catalog = args.output.resolve(), args.catalog.resolve()
    output.mkdir(parents=True, exist_ok=True)
    plan = prepare(output, catalog) if args.refresh_manifests or not (output / "plan.json").exists() else json.loads((output / "plan.json").read_text())["runs"]
    if args.prepare_only:
        print(f"Prepared {len(plan)} scenarios in {output}", flush=True)
        return 0
    selected = set(args.select.split(",")) if args.select else {r["id"] for r in plan}
    if selected - {r["id"] for r in plan}:
        parser.error("Unknown campaign case")
    for case in plan:
        if case["id"] not in selected:
            continue
        if not args.select and any(json.loads(path.read_text()).get("status") == "passed"
                                   for path in output.glob(case["id"] + "-*/report.json")):
            continue
        run = output / (case["id"] + "-" + args.attempt)
        if run.exists():
            continue
        command = [sys.executable, str(ROOT / "tools/ui-automation/run-native.py"),
            "--freeze-scenarios",
            "--scenario", str(ROOT / "tools/ui-automation/scenarios" / case["scenario"]),
            "--variant", case["variant"], "--players", str(case["players"]),
            "--catalog", str(catalog), "--fixture-dir", str(args.fixture_dir.resolve()),
            "--server-binary", str(ROOT / "build/server/hexproof-server"),
            "--os-input-helper", str(ROOT / "tools/ui-automation/mutter-input.py"),
            "--timeout", "1800", "--hang-timeout", "120", "--output", str(run)]
        if "manifest" in case:
            command += ["--deck-manifest", case["manifest"]]
        print(json.dumps({"starting": case["id"], "attempt": args.attempt}), flush=True)
        result = subprocess.run(command, cwd=ROOT)
        if run.is_dir():
            release_catalog_copies(run)
        print(json.dumps({"finished": case["id"], "exitCode": result.returncode}), flush=True)
        if result.returncode and not args.keep_going:
            return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
