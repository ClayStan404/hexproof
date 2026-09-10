#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Run frozen reference games through trusted bridges, never a production capacity estimate."""

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

from drive import percentile, process_tree_rss
from process_control import (ProcessCancelled, cancellation_signals,
                             start_owned_process, stop_owned_process, wait_owned_process)


def player_id(value):
    return int(str(value).removeprefix("player-"))


def choose(event):
    actions = event["actions"]
    if not actions:
        raise ValueError("Bridge has no mapped actions")
    if event["kind"] == "PICK_TARGET":
        opponents = {p["name"]: p for p in event["views"][0]["players"]
                     if player_id(p["id"]) != event["actor"] and not p.get("hasLost")}
        targets = [a for a in actions if a.get("cardName") in opponents]
        if targets:
            return min(targets, key=lambda a: (opponents[a["cardName"]]["life"], opponents[a["cardName"]]["id"]))
        return actions[0]
    if event["kind"] in {"PLAY_MANA", "PLAY_X_MANA"}:
        return next(a for a in actions if a["category"] == "mana")
    preference = ["keep", "land", "cast", "target_opponent", "target", "confirm", "attack_all", "block_none", "pass", "mana", "other"]
    return min(actions, key=lambda a: preference.index(a.get("category", "other")))


def terminal_ok(event, spec):
    if event.get("gameOver") is not True or event.get("naturalCompletion") is not True or event.get("cancelled"):
        return False
    players = event.get("view", {}).get("players", [])
    if len(players) != len(spec["players"]) or "winner" not in event:
        return False
    try:
        winner = player_id(event["winner"])
        if winner not in range(len(spec["players"])) or {player_id(p["id"]) for p in players} != set(range(len(spec["players"]))):
            return False
        if any(p.get("hasWon") is True and player_id(p["id"]) != winner for p in players):
            return False
        return all((p["life"] > 0 and not p.get("hasLost") and p.get("status") != "lost")
                   if player_id(p["id"]) == winner else
                   (p.get("hasLost") is True or p.get("status") in {"lost", "conceded"} or p["life"] <= 0)
                   for p in players)
    except (KeyError, TypeError, ValueError):
        return False


def verify_views(event, player_count):
    views = event["views"]
    if len(views) != player_count + 1 or {v["viewer"] for v in views} != set(range(-1, player_count)):
        raise AssertionError("Missing player or spectator projection")
    private = {v["viewer"]: {c["id"] for z in v["zones"] if z["zone"] == "hand"
                            and z["owner"] == v["viewer"] for c in z["cards"]}
               for v in views if v["viewer"] >= 0}
    for view in views:
        if view["viewer"] >= 0:
            hand = [c for z in view["zones"] if z["zone"] == "hand" and z["owner"] == view["viewer"] for c in z["cards"]]
            if len(hand) != zone_count(view, view["viewer"], "hand") or len({c["id"] for c in hand}) != len(hand):
                raise AssertionError("Owner hand projection does not match public count")
        for zone in view["zones"]:
            if zone["zone"] == "library" or zone["zone"] == "hand" and zone["owner"] != view["viewer"]:
                if zone["cards"]:
                    raise AssertionError("Hidden zone exposes ordered per-card entries")
        encoded = json.dumps(view)
        if any(json.dumps(identity) in encoded for owner, ids in private.items() if owner != view["viewer"] for identity in ids):
            raise AssertionError("Hidden card identifier leaked into another projection")


def zone_count(view, owner, name):
    zones = [z for z in view["zones"] if z["owner"] == owner and z["zone"] == name]
    if len(zones) == 1 and "count" in zones[0]:
        return zones[0]["count"]
    player = next(p for p in view["players"] if player_id(p["id"]) == owner)
    return player[name + "Count"]


def is_priority(event):
    return event["kind"] == "chooseAction" or event["kind"] == "SELECT" and event.get("message") == "Play instants and activated abilities"


class Transfers:
    """Per-attempt checks; old public IDs cannot validate a later failed cast."""
    def __init__(self):
        self.land = None
        self.cast = None
        self.checked_lands = 0
        self.checked_casts = 0

    def observe(self, event):
        if self.land:
            owner, identity, hand_count, battlefield_count = self.land
            view = next(v for v in event["views"] if v["viewer"] == owner)
            battlefield = [c for z in view["zones"] if z["zone"] == "battlefield" and z["owner"] == owner for c in z["cards"]]
            assert zone_count(view, owner, "hand") == hand_count - 1
            assert len(battlefield) == battlefield_count + 1 and any(c["id"] == identity for c in battlefield)
            self.checked_lands += 1
            self.land = None
        if self.cast and is_priority(event):
            identity, old_ids = self.cast
            stack = event["views"][0]["stack"]
            assert any(c.get("cardId", c["id"]) == identity and c["id"] not in old_ids for c in stack), "Cast attempt did not create a new paid stack object"
            self.checked_casts += 1
            self.cast = None

    def selected(self, event, action):
        if action["category"] == "land":
            assert self.land is None
            owner = event["actor"]
            view = next(v for v in event["views"] if v["viewer"] == owner)
            bf = sum(len(z["cards"]) for z in view["zones"] if z["zone"] == "battlefield" and z["owner"] == owner)
            self.land = owner, action["cardId"], zone_count(view, owner, "hand"), bf
        if action["category"] == "cast":
            assert self.cast is None
            self.cast = action["cardId"], {c["id"] for c in event["views"][0]["stack"]}


def verify_opening(event, spec):
    view = event["views"][0]
    assert len(view["players"]) == len(spec["players"])
    for p in view["players"]:
        owner = player_id(p["id"])
        deck = spec["players"][owner]
        assert p["life"] == spec["startingLife"]
        zones = [z for z in view["zones"] if z["owner"] == owner]
        total = zone_count(view, owner, "hand") + zone_count(view, owner, "library")
        assert total == sum(c["count"] for c in deck["cards"]) - len(deck["commanders"])
        command = [c["name"] for z in zones if z["zone"] == "command" for c in z["cards"]]
        assert sorted(command) == sorted(deck["commanders"])


def run(command, output, spec, timeout, cancellation=None):
    output.mkdir()
    profile = output / "profile"
    profile.mkdir()
    actual = [arg.replace("{profile}", str(profile)) for arg in command]
    (output / "command.json").write_text(json.dumps(actual, indent=2) + "\n")
    env = os.environ.copy()
    for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
        env[key] = str(profile)
    started = time.monotonic()
    counts = Counter()
    cast_ids, land_ids, public_ids = set(), set(), set()
    names = set()
    latency, sizes = [], []
    first, previous = None, None
    peak_rss = 0
    terminal = None
    transfers = Transfers()
    result = {"status": "FAIL", "workload": spec["id"]}
    process = None
    selector = None
    with (output / "backend.log").open("w") as errors, (output / "events.jsonl").open("w") as trace:
        try:
            if cancellation is not None:
                cancellation.check()
            process = start_owned_process(actual, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                          stderr=errors, env=env)
            result["pid"] = process.pid
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            buffer = b""
            while terminal is None:
                if cancellation is not None:
                    cancellation.check()
                if time.monotonic() - started > timeout:
                    raise TimeoutError("Frozen workload exceeded bounded runtime")
                peak_rss = max(peak_rss, process_tree_rss(process.pid))
                if not selector.select(.05):
                    if process.poll() is not None:
                        raise RuntimeError(f"Backend exited {process.returncode} before result")
                    continue
                chunk = os.read(process.stdout.fileno(), 262144)
                if not chunk:
                    raise RuntimeError("Backend closed stdout before result")
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    event = json.loads(line)
                    now = time.monotonic()
                    trace.write(json.dumps({"seconds": now - started, "event": event}) + "\n")
                    if event["type"] == "ready":
                        continue
                    if event["type"] == "result":
                        assert terminal_ok(event, spec), "Not a natural terminal with all registered players"
                        terminal = event
                        break
                    assert event["type"] == "decision", event
                    if first is None:
                        first = now - started
                        verify_opening(event, spec)
                    verify_views(event, len(spec["players"]))
                    transfers.observe(event)
                    if previous is not None and counts["decisions"] >= 20:
                        latency.append((now - previous) * 1000)
                    counts["decisions"] += 1
                    assert counts["decisions"] <= 15000, "Decision budget exceeded"
                    for view in event["views"]:
                        sizes.append(len(json.dumps(view, separators=(",", ":")).encode()))
                        priority = is_priority(event)
                        cards = ([c for c in view["stack"]] if priority else [])
                        cards += [c for z in view["zones"] if z["zone"] == "battlefield" for c in z["cards"]]
                        for card in cards:
                            public_ids.add(card.get("cardId", card["id"]))
                            names.add(card["name"])
                    action = choose(event)
                    transfers.selected(event, action)
                    counts[action["category"]] += 1
                    if action["category"] in {"cast", "land"}:
                        (cast_ids if action["category"] == "cast" else land_ids).add(action["cardId"])
                    response = {"type": "respond", "id": event["id"], "actor": event["actor"], "response": action["response"]}
                    process.stdin.write(json.dumps(response).encode() + b"\n")
                    process.stdin.flush()
                    previous = time.monotonic()
                    trace.write(json.dumps({"seconds": previous - started, "response": response, "category": action["category"]}) + "\n")
            process.stdin.close()
            assert wait_owned_process(process, 10, cancellation) == 0, "Backend failed after terminal"
            assert counts["keep"] >= len(spec["players"]) and cast_ids and land_ids
            assert cast_ids <= public_ids, f"Chosen casts never observed after payment: {cast_ids - public_ids}"
            assert land_ids <= public_ids, f"Chosen lands never entered battlefield: {land_ids - public_ids}"
            assert transfers.land is None and transfers.cast is None
            assert transfers.checked_lands == counts["land"] and transfers.checked_casts == counts["cast"]
            result.update(status="PASS", terminal=terminal)
        except ProcessCancelled as error:
            result.update(cancelled=True, signal=error.signum,
                          failureKind="cancelled", reason=str(error))
        except (TimeoutError, subprocess.TimeoutExpired) as error:
            result.update(timedOut=True, failureKind="timeout", reason=str(error))
        except OSError as error:
            result.update(failureKind="launch" if process is None else "io",
                          reason=f"{type(error).__name__}: {error}")
        except Exception as error:
            result["reason"] = f"{type(error).__name__}: {error}"
        finally:
            if selector is not None:
                selector.close()
            if process is not None:
                result["cleanup"] = stop_owned_process(process)
                process.stdout.close()
                if not process.stdin.closed:
                    process.stdin.close()
    result.update(counts=dict(counts), elapsedSeconds=time.monotonic() - started,
                  firstDecisionMs=first * 1000 if first is not None else None,
                  warmIpcLatencySamples=len(latency), warmIpcP50Ms=percentile(latency, .5),
                  warmIpcP95Ms=percentile(latency, .95), sampledProcessTreePeakRssKiB=peak_rss,
                  perViewJsonP95Bytes=percentile(sizes, .95), verifiedCastIds=len(cast_ids & public_ids),
                  verifiedLandIds=len(land_ids & public_ids), observedNames=sorted(names))
    result.update(checkedLandAttempts=transfers.checked_lands, checkedCastAttempts=transfers.checked_casts)
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workloads", type=Path, default=Path(__file__).with_name("workloads.json"))
    parser.add_argument("--workload-id", required=True)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not 1 <= args.repeat <= 100 or not 1 <= args.concurrency <= 4 or not 1 <= args.timeout <= 900:
        parser.error("Require command, 1–100 runs, 1–4 workers, and 1–900 seconds per run")
    payload = args.workloads.read_bytes()
    specs = [s for s in json.loads(payload)["workloads"] if s["id"] == args.workload_id]
    if len(specs) != 1:
        parser.error("Unknown or duplicate workload ID")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="workload-", dir=args.output.resolve()))
    (output / "workloads.json").write_bytes(payload)
    (output / "driver.py").write_bytes(Path(__file__).read_bytes())
    for filename in ("drive.py", "process_control.py"):
        (output / filename).write_bytes(Path(__file__).with_name(filename).read_bytes())
    print(output, flush=True)
    with cancellation_signals() as cancellation, ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        results = list(pool.map(lambda i: run(command, output / f"run-{i:03d}", specs[0], args.timeout, cancellation), range(args.repeat)))
    report = {"workloadSha256": hashlib.sha256(payload).hexdigest(), "concurrency": args.concurrency,
              "note": "Independent trusted host processes, not shared-server capacity. Different engine shuffles/prompt counts prohibit equal-state speed ratios.",
              "results": results}
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"runs": len(results), "passed": sum(r["status"] == "PASS" for r in results)}), flush=True)
    return int(any(r["status"] != "PASS" for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
