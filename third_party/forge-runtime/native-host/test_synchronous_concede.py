#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Reach a real Pithing Needle menu and verify invalid input and multiplayer continuation.

Four native human seats use synthetic decks that exceed Constructed copy limits.
Every land, spell and mana source is selected through production JSONL. No
start-game hook or injected game state is used by this process-level regression.
"""

import argparse
import collections
import json
from pathlib import Path
import selectors
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from test_full_game import choose, java_command, record_runtime


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "profile"
    profile.mkdir(exist_ok=True)
    record_runtime(args, output)
    setup = {"gameId": "native-synchronous-concession", "variant": "constructed", "seed": 42,
             "startingLife": 20, "startingPlayerIndex": 0,
             "players": [{"name": f"Native seat {seat}",
                          "deck": [{"name": "Forest"}] * 24 + [{"name": "Pithing Needle"}] * 36}
                         for seat in range(4)]}
    (output / "setup.json").write_text(json.dumps(setup, indent=2) + "\n")
    started = time.monotonic()
    result = {"passed": False, "error": None, "wireFormat": "canonical-type-output-with-directives"}
    with (output / "host.log").open("w") as log, (output / "rpc.jsonl").open("w") as trace:
        process = subprocess.Popen(java_command(args, profile), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=log, text=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        def call(command, rejected=False, **fields):
            request = {"command": command, **fields}
            process.stdin.write(json.dumps(request) + "\n")
            process.stdin.flush()
            if not selector.select(args.timeout):
                raise TimeoutError(f"{command} exceeded {args.timeout}s")
            line = process.stdout.readline()
            if not line:
                raise RuntimeError(f"Native host exited with {process.poll()}")
            response = json.loads(line)
            trace.write(json.dumps({"request": request, "response": response}) + "\n")
            trace.flush()
            assert response["ok"] != rejected, f"Unexpected response: {response}"
            return response["result"]

        def prompt():
            return json.loads(call("getPrompt", sessionId=setup["gameId"], playerIndex=0))

        def submit(kind, answer, rejected=False):
            return call("submitAction", rejected=rejected, sessionId=setup["gameId"],
                        payload=json.dumps({"type": kind, "output": answer}))

        try:
            call("startGame", payload=json.dumps(setup))
            for decision in range(200):
                pending = prompt()
                native_input = pending["input"]
                kind = native_input["type"]
                if kind == "chooseCardName":
                    break
                owner = int(pending["decidingPlayerId"].split("-")[1])
                view = json.loads(call("getSnapshot", sessionId=setup["gameId"], viewer=owner))
                if kind == "chooseAction":
                    cards = {card["id"]: card for zone in view["zones"] for card in zone["cards"]}
                    lands = [action for action in native_input["actions"] if action["type"] == "playLand"]
                    sources = [card for zone in view["zones"] if zone["zone"] == "battlefield"
                               and zone["ownerId"] == pending["decidingPlayerId"] for card in zone["cards"]
                               if card.get("identity", {}).get("name") == "Forest" and not card.get("tapped")]
                    needles = [action for action in native_input["actions"] if action["type"] == "cast"
                               and cards.get(action["cardId"], {}).get("identity", {}).get("name") == "Pithing Needle"]
                    selected = next(iter(lands or (needles if sources else [])), None)
                    answer = ({"type": "act", "actionId": selected["id"]} if selected
                              else {"type": "pass", "exhaustStack": False})
                else:
                    answer = choose(native_input, view, "Forest", collections.Counter())
                submit(kind, answer)
            else:
                raise AssertionError("Real Pithing Needle casting did not reach its native naming menu")
            result["decisionsToName"] = decision
            result["prompt"] = pending
            submit("chooseCardName", {"type": "cardName", "name": "This is not a Magic card name"}, rejected=True)
            assert process.poll() is None and prompt() == pending, "Invalid name terminated the host or changed the prompt"
            result["invalidNamePreservedPrompt"] = True
            owner = int(pending["decidingPlayerId"].split("-")[1])
            concession = {"type": "directive", "player": owner, "directive": {"type": "concede"}}
            before = time.monotonic()
            call("submitAction", sessionId=setup["gameId"], payload=json.dumps(concession))
            result["concessionSeconds"] = round(time.monotonic() - before, 3)
            assert process.poll() is None, "Multiplayer concession terminated the native host"
            next_prompt = prompt()
            assert next_prompt["decidingPlayerId"] != f"player-{owner}", "Eliminated player retained a decision"
            public = json.loads(call("getSnapshot", sessionId=setup["gameId"], viewer=-1))
            assert not public["gameOver"] and public["players"][owner]["status"] == "conceded", "Native game lost the nonterminal departure"
            assert all(not zone["cards"] for zone in public["zones"] if zone["ownerId"] == f"player-{owner}"), "Departed player's cards were recreated"
            result["continuedPrompt"] = next_prompt
            for continued in range(250):
                pending = prompt()
                native_input = pending["input"]
                kind = native_input["type"]
                deciding = int(pending["decidingPlayerId"].split("-")[1])
                assert deciding != owner, "A later decision returned to the departed player"
                view = json.loads(call("getSnapshot", sessionId=setup["gameId"], viewer=deciding))
                if kind == "chooseCardName":
                    submit(kind, {"type": "cardName", "name": "Lightning Bolt"})
                    resolved = json.loads(call("getSnapshot", sessionId=setup["gameId"], viewer=-1))
                    assert any(card.get("identity", {}).get("name") == "Pithing Needle"
                               for zone in resolved["zones"] if zone["zone"] == "battlefield"
                               and zone["ownerId"] == f"player-{deciding}" for card in zone["cards"]), "A survivor's next real spell did not resolve"
                    result["survivorResolvedNeedle"] = deciding
                    result["continuedDecisions"] = continued
                    break
                if kind == "chooseAction":
                    cards = {card["id"]: card for zone in view["zones"] for card in zone["cards"]}
                    lands = [action for action in native_input["actions"] if action["type"] == "playLand"]
                    sources = [card for zone in view["zones"] if zone["zone"] == "battlefield"
                               and zone["ownerId"] == pending["decidingPlayerId"] for card in zone["cards"]
                               if card.get("identity", {}).get("name") == "Forest" and not card.get("tapped")]
                    needles = [action for action in native_input["actions"] if action["type"] == "cast"
                               and cards.get(action["cardId"], {}).get("identity", {}).get("name") == "Pithing Needle"]
                    selected = next(iter(lands or (needles if sources else [])), None)
                    answer = ({"type": "act", "actionId": selected["id"]} if selected
                              else {"type": "pass", "exhaustStack": False})
                else:
                    answer = choose(native_input, view, "Forest", collections.Counter())
                submit(kind, answer)
            else:
                raise AssertionError("Remaining players could not cast and resolve their next spell")
            for seat in range(4):
                if seat in (owner, deciding):
                    continue
                call("submitAction", sessionId=setup["gameId"], payload=json.dumps(
                    {"type": "directive", "player": seat, "directive": {"type": "concede"}}))
            final = json.loads(call("getSnapshot", sessionId=setup["gameId"], viewer=-1))
            assert final["gameOver"] and final["winnerId"] == f"player-{deciding}", "Remaining game failed to reach its native terminal outcome"
            result["passed"] = True
        except BaseException as error:
            result["error"] = f"{type(error).__name__}: {error}"
            raise
        finally:
            selector.close()
            if process.poll() is None:
                try:
                    process.stdin.write('{"command":"quit"}\n')
                    process.stdin.flush()
                    process.wait(timeout=5)
                except (BrokenPipeError, subprocess.TimeoutExpired):
                    process.kill()
                    process.wait()
            result["seconds"] = round(time.monotonic() - started, 3)
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    runtime = parser.add_mutually_exclusive_group(required=True)
    runtime.add_argument("--classpath-file", type=Path)
    runtime.add_argument("--jar", type=Path)
    parser.add_argument("--forge-home", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=45)
    run(parser.parse_args())
