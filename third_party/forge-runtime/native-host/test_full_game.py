#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Complete native-human games through JSONL using an explicit deterministic policy.

The synthetic decks intentionally exceed normal copy limits. Both seats keep,
play available lands/creatures, select every mana source individually, attack,
and decline blocks. Forge performs all state changes, triggers and combat.
These scenarios do not establish Modern-wide card coverage or adversarial target
validation. The transcript records the deterministic test policy and inputs.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import selectors
import subprocess
import time
import os


def java_command(args, profile):
    command = ["java", "-Xmx2g", "-Djava.awt.headless=true", f"-Duser.home={profile}"]
    if args.jar:
        command += ["-jar", str(args.jar.resolve())]
    else:
        command += ["-cp", args.classpath_file.read_text().strip(), "org.hexproof.forge.NativeHost"]
    return command + ["--interactive-server", "--forge-home", str(args.forge_home.resolve())]


def record_runtime(args, output):
    entries = [args.jar.resolve(), *(args.jar.resolve().parent / "lib").glob("*.jar")] if args.jar else [
        Path(entry) for entry in args.classpath_file.read_text().strip().split(os.pathsep)]
    artifacts = []
    for entry in entries:
        paths = sorted(entry.rglob("*.class")) if entry.is_dir() else [entry]
        for path in paths:
            with path.open("rb") as stream:
                artifacts.append({"path": str(path.resolve()), "sha256": hashlib.file_digest(stream, "sha256").hexdigest()})
    metadata = args.jar.resolve().parent / "host-source/upstream.json" if args.jar else Path(__file__).with_name("upstream.json")
    (output / "runtime.json").write_text(json.dumps({"declaredUpstream": json.loads(metadata.read_text()),
        "metadataSource": str(metadata.resolve()), "testedArtifacts": artifacts}, indent=2) + "\n")


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "profile"
    profile.mkdir(exist_ok=True)
    record_runtime(args, output)
    land, creature = ("Forest", "Elvish Visionary") if args.scenario == "visionary" else ("Plains", "Glory Seeker")
    deck = [{"name": name} for name in [land] * 24 + [creature] * 36]
    setup = {"gameId": f"native-full-{args.scenario}-{args.seed}", "variant": "constructed",
             "seed": args.seed, "startingLife": args.life, "startingPlayerIndex": args.starting_player,
             "players": [{"name": f"Native seat {index}", "deck": deck} for index in range(2)]}
    counts = collections.Counter()
    metrics = collections.Counter()
    previous = None
    error = None
    final = None
    started = time.monotonic()
    (output / "setup.json").write_text(json.dumps(setup, indent=2) + "\n")
    with (output / "host.log").open("w") as log, (output / "decisions.jsonl").open("w") as trace:
        process = subprocess.Popen(java_command(args, profile),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        def call(command, **fields):
            process.stdin.write(json.dumps({"command": command, **fields}) + "\n")
            process.stdin.flush()
            if not selector.select(args.timeout):
                raise TimeoutError(f"{command} exceeded {args.timeout}s; see host.log")
            line = process.stdout.readline()
            if not line:
                raise RuntimeError(f"Native host exited with {process.poll()}; see host.log")
            response = json.loads(line)
            if not response["ok"]:
                raise RuntimeError(f"{command}: {response['error']}; see host.log")
            return response["result"]

        try:
            call("reset")
            handle = json.loads(call("startGame", payload=json.dumps(setup)))
            session = handle["sessionId"]
            for decision in range(args.max_decisions):
                if call("getGameOver", sessionId=session) == "true":
                    break
                raw = call("getPrompt", sessionId=session, playerIndex=0)
                if not raw:
                    raise AssertionError("No stable native prompt before game over")
                prompt = json.loads(raw)
                player = int(prompt["decidingPlayerId"].split("-")[1])
                view = json.loads(call("getSnapshot", sessionId=session, viewer=player))
                public = json.loads(call("getSnapshot", sessionId=session, viewer=-1))
                if public["turn"] > 0:
                    assert public.get("startingPlayerId") == f"player-{args.starting_player}", "Requested starting seat was lost"
                record_evidence(public, previous, creature, metrics)
                previous = public
                kind = prompt["input"]["type"]
                counts[kind] += 1
                (output / "pending.json").write_text(json.dumps({"prompt": prompt, "view": view}, indent=2) + "\n")
                answer = choose(prompt["input"], view, land, metrics)
                trace.write(json.dumps({"decision": decision, "prompt": prompt, "view": view,
                                        "public": public, "answer": answer}) + "\n")
                trace.flush()
                if decision % 50 == 0 or kind in ("chooseAttackers", "chooseBlockers"):
                    print(json.dumps({"decision": decision, "type": kind, "turn": public["turn"],
                                      "step": public["step"], "life": [p["life"] for p in public["players"]]}), flush=True)
                # This is the same canonical envelope emitted by the Go client.
                call("submitAction", sessionId=session,
                     payload=json.dumps({"type": kind, "output": answer}))
            else:
                raise AssertionError("Native game exceeded decision budget")
            final = json.loads(call("getSnapshot", sessionId=session, viewer=-1))
            record_evidence(final, previous, creature, metrics)
            assert final["gameOver"] and final.get("winnerId"), "No natural winning outcome"
            assert min(player["life"] for player in final["players"]) <= 0, "Expected lethal combat, not library exhaustion"
            assert metrics["mana_source_choices"] > 0 and metrics["attackers_declared"] > 0
            assert metrics["creatures_entered"] > 0 and metrics["combat_life_lost"] > 0
            if args.scenario == "visionary":
                assert metrics["etb_draws"] > 0, "No resolved Visionary draw trigger was observed"
        except BaseException as exc:
            error = f"{type(exc).__name__}: {exc}"
            raise
        finally:
            report = {"scenario": args.scenario, "seed": args.seed, "startingLife": args.life,
                      "startingPlayer": args.starting_player,
                      "wireFormat": "canonical-type-output",
                      "passed": error is None and final is not None, "error": error,
                      "seconds": round(time.monotonic() - started, 3), "prompts": dict(counts),
                      "metrics": dict(metrics), "final": final}
            (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({key: value for key, value in report.items() if key != "final"}), flush=True)
            selector.close()
            try:
                process.stdin.write('{"command":"quit"}\n')
                process.stdin.flush()
                process.wait(timeout=5)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                process.kill()
                process.wait()


def choose(prompt, view, land, metrics):
    kind = prompt["type"]
    if kind == "mulligan":
        return {"type": "mulliganDecision", "keep": True}
    if kind == "chooseBoolean":
        return {"type": "decision", "value": True}
    if kind == "chooseAction":
        cards = {card["id"]: card for zone in view["zones"] for card in zone["cards"]}
        casts = [action for action in prompt["actions"] if action["type"] in ("cast", "playLand")]
        lands = [action for action in casts if cards.get(action["cardId"], {}).get("identity", {}).get("name") == land]
        resources = [card for zone in view["zones"] if zone["zone"] == "battlefield"
                     and zone["ownerId"] == view["priorityPlayerId"] for card in zone["cards"]
                     if card.get("identity", {}).get("name") == land and not card.get("tapped")]
        # Both creature fixtures cost two mana; avoid starting a cast that this
        # deterministic human policy cannot pay using its own untapped lands.
        action = next(iter(lands or (casts if len(resources) >= 2 else [])), None)
        if action:
            metrics["cast_or_land_choices"] += 1
            return {"type": "act", "actionId": action["id"]}
        return {"type": "pass", "exhaustStack": False}
    if kind == "payManaCost":
        if prompt.get("canConfirmFromPool"):
            return {"type": "pay", "auto": False}
        if prompt["actions"]:
            metrics["mana_source_choices"] += 1
            return {"type": "act", "actionId": prompt["actions"][0]["id"]}
        raise AssertionError("Native mana prompt has no resource actions and does not permit confirmation")
    if kind == "chooseFromSelection":
        # A native optional ability picker uses min=0 to allow cancellation.
        # This policy deliberately selects an offered ability rather than cancelling.
        amount = min(prompt["maxTotal"], max(prompt["minTotal"], 1 if prompt["options"] else 0))
        return {"type": "selectionDecision", "chosenIndices": list(range(amount))}
    if kind == "chooseAttackers":
        assignments = [{"attackerId": attacker["attackerId"], "targetId": attacker["validTargetIds"][0]}
                       for attacker in prompt["attackers"]]
        metrics["attackers_declared"] += len(assignments)
        return {"type": "declareAttackers", "assignments": assignments}
    if kind == "chooseBlockers":
        return {"type": "declareBlockers", "assignments": []}
    if kind == "chooseBoardTargets":
        return {"type": "boardTargets", "chosen": prompt["candidates"][:prompt["minTargets"]]}
    if kind == "reorder":
        return {"type": "reorderDecision", "orderedIds": [item["id"] for item in prompt["items"]]}
    if kind == "revealCards":
        return {"type": "revealCardsAcknowledged"}
    raise AssertionError(f"No declared policy for native prompt {kind}: {prompt}")


def record_evidence(view, previous, creature, metrics):
    if previous is None:
        return
    before = {card["id"] for zone in previous["zones"] if zone["zone"] == "battlefield" for card in zone["cards"]}
    after = {card["id"] for zone in view["zones"] if zone["zone"] == "battlefield" for card in zone["cards"]
             if card.get("identity", {}).get("name") == creature}
    metrics["creatures_entered"] += len(after - before)
    if view["step"] in ("combatDamage", "combatFirstStrikeDamage") or previous["step"] in ("combatDamage", "combatFirstStrikeDamage"):
        old_life = {player["id"]: player["life"] for player in previous["players"]}
        metrics["combat_life_lost"] += sum(max(0, old_life[player["id"]] - player["life"]) for player in view["players"])
    if view["step"] != "draw" and previous["step"] != "draw" and any(
            item.get("identity", {}).get("name") == "Elvish Visionary" and "draw" in item["text"].lower()
            for item in previous["stack"]):
        libraries = {zone["ownerId"]: zone["count"] for zone in previous["zones"] if zone["zone"] == "library"}
        metrics["etb_draws"] += sum(max(0, libraries[zone["ownerId"]] - zone["count"])
                                     for zone in view["zones"] if zone["zone"] == "library")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    runtime = parser.add_mutually_exclusive_group(required=True)
    runtime.add_argument("--classpath-file", type=Path)
    runtime.add_argument("--jar", type=Path)
    parser.add_argument("--forge-home", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scenario", choices=("visionary", "glory-seeker"), default="visionary")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--life", type=int, default=20)
    parser.add_argument("--starting-player", type=int, choices=(0, 1), default=0)
    parser.add_argument("--max-decisions", type=int, default=3000)
    parser.add_argument("--timeout", type=int, default=45)
    run(parser.parse_args())
