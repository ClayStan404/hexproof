#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Exercise the real human callback protocol; this is not native GUI evidence."""

import argparse
import collections
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--block-once", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="human-smoke-", dir=args.output.resolve()))
    print(output, flush=True)
    command = [sys.executable, str(Path(__file__).with_name("bridge.py")), "--run-dir", str(args.run_dir.resolve())]
    counts = collections.Counter()
    preferences = ["keep", "land", "cast", "confirm", "mana", "attack_all", "block_none", "pass", "other"]
    first = True
    result = None
    selected_blocker = False
    observed_combat_deaths = False
    requested_casts = set()
    requested_lands = set()
    entered_creatures = set()
    entered_lands = set()
    with (output / "stderr.log").open("w") as errors, (output / "protocol.jsonl").open("w") as trace:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, text=True, bufsize=1)
        try:
            while line := process.stdout.readline():
                trace.write(line)
                trace.flush()
                packet = json.loads(line)
                if packet["type"] == "result":
                    result = packet
                    break
                if packet["type"] == "error":
                    raise AssertionError(packet)
                if packet["type"] != "decision":
                    continue
                graveyards = {zone["owner"]: zone["cards"] for zone in packet["views"][0]["zones"] if zone["zone"] == "graveyard"}
                observed_combat_deaths |= all(any(card["name"] == "Grizzly Bears" for card in graveyards.get(owner, [])) for owner in [0, 1])
                for zone in packet["views"][0]["zones"]:
                    if zone["zone"] == "battlefield":
                        entered_creatures.update(card["id"] for card in zone["cards"] if card["name"] == "Grizzly Bears")
                        entered_lands.update(card["id"] for card in zone["cards"] if card["name"] == "Forest")
                if first:
                    invalid = {"type": "respond", "id": packet["id"], "actor": 1 - packet["actor"],
                               "response": packet["actions"][0]["response"]}
                    process.stdin.write(json.dumps(invalid) + "\n")
                    process.stdin.flush()
                    rejected = json.loads(process.stdout.readline())
                    trace.write(json.dumps(rejected) + "\n")
                    assert rejected["type"] == "error" and "wrong actor" in rejected["message"]
                    counts["wrong_actor_rejected"] += 1
                    first = False
                assert packet["actions"], packet
                choice = min(packet["actions"], key=lambda action: preferences.index(action.get("category", "other")))
                blockers = [action for action in packet["actions"] if action["label"].startswith("Block: ")]
                if args.block_once and not selected_blocker and blockers:
                    choice = blockers[0]
                    selected_blocker = True
                    counts["blocker_selected"] += 1
                counts[choice["category"]] += 1
                if choice["category"] == "cast":
                    requested_casts.add(choice["response"]["uuid"])
                if choice["category"] == "land":
                    requested_lands.add(choice["response"]["uuid"])
                response = {"type": "respond", "id": packet["id"], "actor": packet["actor"], "response": choice["response"]}
                trace.write(json.dumps({"sent": response, "category": choice["category"]}) + "\n")
                process.stdin.write(json.dumps(response) + "\n")
                process.stdin.flush()
                assert sum(counts.values()) <= 2000, "Decision loop exceeded smoke budget"
            assert result and result["gameOver"] and result["naturalCompletion"], result
            assert any(player["life"] <= 0 for player in result["view"]["players"]), result
            for category in ["keep", "land", "cast", "attack_all", "block_none", "pass"]:
                assert counts[category] > 0, (category, counts)
            if args.block_once:
                assert selected_blocker and observed_combat_deaths, (selected_blocker, observed_combat_deaths)
            assert requested_casts and requested_casts <= entered_creatures, "A requested creature cast never entered the battlefield"
            assert requested_lands and requested_lands <= entered_lands, "A requested land never entered the battlefield"
            process.stdin.close()
            process.wait(timeout=10)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
    (output / "summary.json").write_text(json.dumps({"actionCounts": counts, "blockedCombatDeathsObserved": observed_combat_deaths,
                                                   "verifiedCastEntries": len(requested_casts), "verifiedLandEntries": len(requested_lands),
                                                   "result": result}, indent=2) + "\n")
    print(json.dumps({"counts": counts, "winner": result["winner"], "turn": result["turn"]}))


if __name__ == "__main__":
    main()
