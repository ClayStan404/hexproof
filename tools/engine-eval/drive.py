#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Drive the same trusted hot-seat bridge policy and retain latency/RSS diagnostics."""

import argparse
from collections import Counter, defaultdict
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time

PREFERENCE = ["keep", "land", "cast", "confirm", "mana", "attack_all", "block_none", "pass"]


def choose_action(event):
    options = [action for action in event.get("actions", []) if action.get("category") in PREFERENCE]
    if not options:
        raise ValueError(f"No common-policy action for {event.get('kind')}")
    return min(options, key=lambda action: PREFERENCE.index(action["category"]))


def natural_terminal(event):
    if not isinstance(event, dict) or not isinstance(event.get("view"), dict):
        return False
    players = event["view"].get("players")
    if (event.get("gameOver") is not True
            or ("naturalCompletion" in event and event["naturalCompletion"] is not True)
            or not isinstance(players, list) or len(players) != 2):
        return False

    def key(value):
        return str(value).removeprefix("player-")

    for player in players:
        if (not isinstance(player, dict) or type(player.get("id")) not in (str, int)
                or not key(player["id"]).strip()
                or type(player.get("life")) not in (int, float)):
            return False
        if type(player["life"]) is float and not math.isfinite(player["life"]):
            return False
    if (len({key(player["id"]) for player in players}) != 2
            or not any(player["life"] <= 0 for player in players)
            or not any(player["life"] > 0 for player in players)):
        return False
    if "winner" in event:
        if type(event["winner"]) not in (str, int):
            return False
        return any(key(player["id"]) == key(event["winner"]) and player["life"] > 0 for player in players)
    return True


def card_count(event, viewer, owner, zone_name, name):
    view = next((view for view in event.get("views", []) if view.get("viewer") == viewer), {})
    return sum(card.get("name") == name for zone in view.get("zones", [])
               if zone.get("owner") == owner and zone.get("zone") == zone_name
               for card in zone.get("cards", []))


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def process_tree_rss(pid):
    """Linux sampled aggregate RSS, not an exact simultaneous high-water mark."""
    total = 0
    pending = [pid]
    seen = set()
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        root = Path("/proc") / str(current)
        try:
            for line in (root / "status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    total += int(line.split()[1])
            for task in (root / "task").iterdir():
                pending.extend(int(value) for value in (task / "children").read_text().split())
        except (FileNotFoundError, ProcessLookupError):
            pass
    return total


def drive(command, output, timeout=120):
    output.mkdir()
    (output / "profile").mkdir()
    actual = [arg.replace("{profile}", str(output / "profile")) for arg in command]
    env = os.environ.copy()
    for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
        env[key] = str(output / "profile")
    (output / "command.json").write_text(json.dumps(actual, indent=2) + "\n")
    start = time.monotonic()
    first = None
    previous_response = None
    latency = []
    view_bytes = []
    decisions = 0
    peak_rss = 0
    buffer = b""
    terminal = None
    categories = Counter()
    pending_land = None
    checked_lands = 0
    saw_stack_creature = False
    saw_battlefield_creature = False
    cast_counts = Counter()
    battlefield_ids = defaultdict(set)
    with (output / "backend.log").open("w") as errors, (output / "events.jsonl").open("w") as log:
        process = subprocess.Popen(actual, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, env=env, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        try:
            while terminal is None:
                now = time.monotonic()
                if now - start > timeout:
                    raise TimeoutError("Bridge exceeded bounded run time")
                peak_rss = max(peak_rss, process_tree_rss(process.pid))
                if not selector.select(timeout=0.05):
                    if process.poll() is not None:
                        raise RuntimeError(f"Bridge exited {process.returncode} before terminal event")
                    continue
                chunk = os.read(process.stdout.fileno(), 262144)
                if not chunk:
                    raise RuntimeError("Bridge closed stdout before terminal event")
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    received = time.monotonic()
                    event = json.loads(line)
                    log.write(json.dumps({"seconds": received - start, "event": event}) + "\n")
                    if event.get("type") == "ready":
                        continue
                    if event.get("type") == "result":
                        if not natural_terminal(event):
                            raise ValueError("Terminal result is not an independently observed natural lethal outcome")
                        terminal = event
                        break
                    if event.get("type") != "decision":
                        raise ValueError(f"Unexpected bridge event: {event.get('type')}")
                    if pending_land is not None:
                        owner, hand, battlefield = pending_land
                        if (card_count(event, owner, owner, "hand", "Forest") != hand - 1
                                or card_count(event, owner, owner, "battlefield", "Forest") != battlefield + 1):
                            raise ValueError("Land action did not move exactly one Forest from hand to battlefield")
                        checked_lands += 1
                        pending_land = None
                    for view in event.get("views", []):
                        saw_stack_creature |= any(card.get("name") == "Grizzly Bears" for card in view.get("stack", []))
                        saw_battlefield_creature |= any(card.get("name") == "Grizzly Bears"
                            for zone in view.get("zones", []) if zone.get("zone") == "battlefield"
                            for card in zone.get("cards", []))
                        for zone in view.get("zones", []):
                            if zone.get("zone") == "battlefield":
                                for card in zone.get("cards", []):
                                    if card.get("name") == "Grizzly Bears" and card.get("id"):
                                        battlefield_ids[zone["owner"]].add(card["id"])
                    if first is None:
                        first = received - start
                    if previous_response is not None and decisions >= 20:
                        latency.append((received - previous_response) * 1000)
                    decisions += 1
                    if decisions > 1500:
                        raise ValueError("Decision limit exceeded (possible adapter loop)")
                    for view in event.get("views", []):
                        view_bytes.append(len(json.dumps(view, separators=(",", ":")).encode()))
                    action = choose_action(event)
                    categories[action["category"]] += 1
                    if action["category"] == "cast":
                        cast_counts[event["actor"]] += 1
                    if action["category"] == "land":
                        owner = event["actor"]
                        pending_land = (owner, card_count(event, owner, owner, "hand", "Forest"),
                                        card_count(event, owner, owner, "battlefield", "Forest"))
                    response = {"type": "respond", "id": event["id"], "actor": event["actor"],
                                "response": action["response"]}
                    process.stdin.write(json.dumps(response).encode() + b"\n")
                    process.stdin.flush()
                    previous_response = time.monotonic()
                    log.write(json.dumps({"seconds": previous_response - start, "response": response,
                                          "category": action["category"]}) + "\n")
            process.stdin.close()
            code = process.wait(timeout=5)
            if code:
                raise RuntimeError(f"Bridge exit {code} after terminal")
            required = {"keep", "land", "cast", "mana", "attack_all", "block_none", "pass"}
            if (not required <= categories.keys() or not checked_lands
                    or not saw_stack_creature or not saw_battlefield_creature):
                raise ValueError("Natural result lacks required decision, land-transfer, or creature stack/battlefield evidence")
            if pending_land is not None or any(len(battlefield_ids[owner]) != count for owner, count in cast_counts.items()):
                raise ValueError("Not every cast/land choice has its expected battlefield transition")
            result = {"status": "PASS", "decisions": decisions, "firstDecisionMs": first * 1000,
                      "elapsedSeconds": time.monotonic() - start, "warmIpcLatencySamples": len(latency),
                      "warmIpcP50Ms": percentile(latency, .5), "warmIpcP95Ms": percentile(latency, .95),
                      "sampledProcessTreePeakRssKiB": peak_rss,
                      "perViewJsonP50Bytes": percentile(view_bytes, .5),
                      "perViewJsonP95Bytes": percentile(view_bytes, .95), "terminal": terminal,
                      "categories": dict(categories), "checkedLandTransfers": checked_lands,
                      "castCounts": dict(cast_counts), "distinctBearsEntered": {owner: len(ids) for owner, ids in battlefield_ids.items()},
                      "sawCreatureOnStack": saw_stack_creature, "sawCreatureOnBattlefield": saw_battlefield_creature}
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            return result
        finally:
            selector.close()
            if process.poll() is None:
                # Exact process group created by this driver, never a system-wide name match.
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)
            process.stdout.close()
            if not process.stdin.closed:
                process.stdin.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not 1 <= args.repeat <= 20:
        parser.error("a backend command and 1–20 repetitions are required")
    if not Path("/proc/self/status").is_file():
        parser.error("responsiveness diagnostics require Linux /proc for process-tree RSS; unsupported is not zero memory")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="diagnostics-", dir=args.output.resolve()))
    print(output, flush=True)
    results = []
    for index in range(args.repeat):
        try:
            result = drive(command, output / f"run-{index + 1}")
        except (OSError, ValueError, RuntimeError, TimeoutError, subprocess.SubprocessError) as error:
            result = {"status": "FAIL", "reason": str(error)}
        results.append(result)
        summary = {"candidate": args.candidate, "workload": "interactive_bears_v1", "runs": results,
                   "limitations": ["New engine process per run; OS filesystem caches are not flushed.",
                                   "30 Forest / 30 Grizzly Bears; same policy, not guaranteed same shuffled sequence.",
                                   "Warm latency excludes the first 20 decisions; includes adapter, JSON and local IPC.",
                                   "Sampled Linux process-tree RSS is not an exact high-water measurement.",
                                   "Not a production capacity, network, image-loading, or engine-only speed comparison."]}
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(index + 1, result["status"], result.get("warmIpcP95Ms", result.get("reason")), flush=True)
    return int(any(result["status"] != "PASS" for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
