#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Bounded real-human workload/lifecycle verification, not a performance benchmark."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time


def choose(event):
    actions = event["actions"]
    if not actions:
        raise AssertionError(f"No mapped choices: {event['kind']} {event['message']}")
    if event["kind"] == "PICK_TARGET":
        opponents = {p["name"]: p for p in event["views"][0]["players"]
                     if p["id"] != event["actor"] and not p.get("hasLost")}
        targets = [a for a in actions if a.get("cardName") in opponents]
        if targets:
            return min(targets, key=lambda a: (opponents[a["cardName"]]["life"], opponents[a["cardName"]]["id"]))
        return actions[0]
    if event["kind"] in {"PLAY_MANA", "PLAY_X_MANA"}:
        mana = [a for a in actions if a["category"] == "mana"]
        if not mana:
            raise AssertionError(f"Unpayable human cost: {event['message']}")
        return mana[0]
    preference = ["keep", "land", "cast", "confirm", "attack_all", "block_none", "pass", "mana", "other"]
    return min(actions, key=lambda action: preference.index(action.get("category", "other")))


class Session:
    def __init__(self, command, directory):
        self.directory = directory
        self.errors = (directory / "stderr.log").open("w")
        self.trace = (directory / "events.jsonl").open("w")
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.errors, text=True, bufsize=1)
        self.queue = queue.Queue()
        self.deadline = time.monotonic() + 180
        def read():
            try:
                for line in self.process.stdout:
                    self.queue.put(json.loads(line))
            except Exception as error:
                self.queue.put(error)
            self.queue.put(None)
        threading.Thread(target=read, daemon=True).start()

    def receive(self):
        value = self.queue.get(timeout=max(0.01, self.deadline - time.monotonic()))
        if value is None:
            raise AssertionError(f"Backend ended before required evidence: exit={self.process.poll()}")
        if isinstance(value, Exception):
            raise value
        self.trace.write(json.dumps({"event": value}) + "\n")
        self.trace.flush()
        return value

    def send(self, value):
        self.trace.write(json.dumps({"sent": value}) + "\n")
        self.trace.flush()
        self.process.stdin.write(json.dumps(value) + "\n")
        self.process.stdin.flush()

    def close(self):
        if not self.process.stdin.closed:
            self.process.stdin.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process.stdout.close()
        self.errors.close()
        self.trace.close()


def privacy(event):
    views = event["views"]
    owners = {view["viewer"]: [card["id"] for zone in view["zones"] if zone["zone"] == "hand"
                              for card in zone["cards"]] for view in views if view["viewer"] >= 0}
    for view in views:
        encoded = json.dumps(view)
        for owner, ids in owners.items():
            if owner != view["viewer"]:
                assert all(card not in encoded for card in ids), "Another viewer received a private hand UUID"
        assert all(zone["zone"] != "library" or not zone["cards"] for zone in view["zones"])


def run(command, directory, spec, cancel=False):
    player_count = len(spec["players"])
    directory.mkdir()
    (directory / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    session = Session(command, directory)
    counts = Counter()
    casts = set()
    lands = set()
    public_cards = set()
    observed_names = set()
    first = True
    previous_response = None
    replay_checked = False
    snapshots = 0
    try:
        while True:
            event = session.receive()
            if event["type"] == "ready":
                continue
            if event["type"] == "result":
                result = event
                break
            assert event["type"] == "decision", event
            assert event["engine"] == "XMage"
            counts["decisions"] += 1
            assert counts["decisions"] <= 15000, "Decision budget exceeded"
            privacy(event)
            for view in event["views"]:
                # Casting choices and mana prompts can expose a provisional stack
                # object. Only ordinary priority proves casting/payment completed.
                if event["kind"] == "SELECT" and event["message"] == "Play instants and activated abilities":
                    for card in view["stack"]:
                        public_cards.add(card.get("cardId", card["id"]))
                        observed_names.add(card["name"])
                for zone in view["zones"]:
                    if zone["zone"] == "battlefield":
                        for card in zone["cards"]:
                            public_cards.add(card["id"])
                            observed_names.add(card["name"])
            if first:
                for player in event["views"][0]["players"]:
                    deck = spec["players"][player["id"]]
                    expected = sum(card["count"] for card in deck["cards"]) - len(deck["commanders"])
                    assert player["life"] == spec["startingLife"], "Wrong actual starting life"
                    assert player["handCount"] + player["libraryCount"] == expected, "Wrong actual main-deck size"
                    commands = [card for zone in event["views"][0]["zones"]
                                if zone["owner"] == player["id"] and zone["zone"] == "command" for card in zone["cards"]]
                    assert sorted(card["name"] for card in commands) == sorted(deck["commanders"]), "Wrong command zone"
                if cancel:
                    session.send({"type": "test_cancel", "requestId": "cancel-at-pending-human-decision"})
                    acknowledgement = session.receive()
                    assert acknowledgement["type"] == "test_cancelled", acknowledgement
                    result = session.receive()
                    assert result["type"] == "result" and result["cancelled"] and not result["naturalCompletion"], result
                    assert session.process.wait(timeout=10) == 0
                    return {"status": "PASS", "scope": "test-only process cancellation", "result": result}
                for view in event["views"]:
                    session.send({"type": "test_snapshot", "viewer": view["viewer"], "requestId": f"viewer-{view['viewer']}"})
                    snapshot = session.receive()
                    assert snapshot["type"] == "test_snapshot" and snapshot["view"] == view, snapshot
                    assert "decision" not in snapshot and "actions" not in snapshot
                    snapshots += 1
                for invalid in [dict(id=event["id"], actor=(event["actor"] + 1) % player_count, response=event["actions"][0]["response"]),
                                dict(id=event["id"], actor=event["actor"], response={"invalid": True})]:
                    session.send({"type": "respond", **invalid})
                    assert session.receive()["type"] == "error"
                    counts["invalid_rejected"] += 1
                session.send({"type": "test_reissue", "id": event["id"], "actor": event["actor"]})
                replay = session.receive()
                assert replay["type"] == "test_reissued" and replay["decision"] == event
                counts["pending_reissued"] += 1
                first = False
            elif not replay_checked:
                session.send(previous_response)
                error = session.receive()
                assert error["type"] == "error" and "Stale" in error["message"]
                counts["stale_rejected"] += 1
                replay_checked = True
            choice = choose(event)
            counts[choice["category"]] += 1
            if choice["category"] == "cast":
                casts.add(choice["cardId"])
            if choice["category"] == "land":
                lands.add(choice["cardId"])
            response = {"type": "respond", "id": event["id"], "actor": event["actor"], "response": choice["response"]}
            session.send(response)
            previous_response = response
        assert result["gameOver"] and result["naturalCompletion"] and not result["cancelled"], result
        players = result["view"]["players"]
        assert len(players) == player_count
        winners = [p["id"] for p in players if p["hasWon"]]
        assert winners == [result["winner"]], players
        assert all(p["hasLost"] for p in players if p["id"] != result["winner"]), players
        assert counts["keep"] >= player_count and counts["cast"] > 0 and counts["land"] > 0
        assert casts <= public_cards, f"Unobserved casts: {casts - public_cards}"
        assert lands <= public_cards, f"Unobserved lands: {lands - public_cards}"
        session.process.stdin.close()
        assert session.process.wait(timeout=10) == 0
        return {"status": "PASS", "scope": "real HumanPlayer callbacks; test-only local hot-seat lifecycle",
                "counts": dict(counts), "viewerSnapshots": snapshots, "observedPublicCardNames": sorted(observed_names),
                "verifiedCastSourceIds": len(casts), "verifiedLandSourceIds": len(lands), "result": result}
    finally:
        session.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workload", type=Path, default=Path(__file__).parent.parent / "workloads.json")
    parser.add_argument("--workload-id")
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--cancel-only", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.repeat <= 5:
        parser.error("--repeat must be between one and five")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="workloads-", dir=args.output.resolve()))
    payload = args.workload.read_bytes()
    (output / "workloads.json").write_bytes(payload)
    shutil.copy2(__file__, output / "driver.py")
    print(output, flush=True)
    specs = json.loads(payload)["workloads"]
    if args.workload_id:
        specs = [spec for spec in specs if spec["id"] == args.workload_id]
        if not specs:
            parser.error("Unknown workload ID")
    results = []
    for spec in specs:
        for index in range(args.repeat):
            directory = output / f"{spec['id']}-{index + 1}"
            command = [sys.executable, str(Path(__file__).with_name("bridge.py").resolve()),
                       "--run-dir", str(args.run_dir.resolve()), "--workload", str((output / "workloads.json").resolve()),
                       "--workload-id", spec["id"], "--profile", str(directory / "profile")]
            try:
                result = run(command, directory, spec, args.cancel_only)
            except Exception as error:
                result = {"status": "UNVERIFIED", "layer": "adapter", "reason": str(error)}
            result.update(workload=spec["id"], repetition=index + 1)
            results.append(result)
            (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            (output / "summary.json").write_text(json.dumps({"candidate": "XMage", "workloadSha256": hashlib.sha256(payload).hexdigest(),
                                                           "runs": results, "notPerformanceBenchmark": True}, indent=2) + "\n")
            print(spec["id"], index + 1, result["status"], result.get("reason", ""), flush=True)
    return int(any(result["status"] != "PASS" for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
