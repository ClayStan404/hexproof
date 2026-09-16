#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Exercise four human seats conceding around a real pending native decision."""

import argparse
import json
from pathlib import Path
import selectors
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from test_full_game import java_command, record_runtime


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "profile"
    profile.mkdir(exist_ok=True)
    record_runtime(args, output)
    setup = {"gameId": f"native-lifecycle-{args.phase}", "variant": "constructed", "seed": 93,
             "startingLife": 20, "startingPlayerIndex": 0,
             "players": [{"name": f"Native seat {index}", "deck": [{"name": "Forest"}] * 60} for index in range(4)]}
    error = None
    final = None
    started = time.monotonic()
    with (output / "host.log").open("w") as log, (output / "rpc.jsonl").open("w") as trace:
        process = subprocess.Popen(java_command(args, profile), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=log, text=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)

        def call(command, expect_rejection=False, **fields):
            request = {"command": command, **fields}
            process.stdin.write(json.dumps(request) + "\n")
            process.stdin.flush()
            if not selector.select(args.timeout):
                raise TimeoutError(f"{command} exceeded {args.timeout}s; see host.log")
            line = process.stdout.readline()
            if not line:
                raise RuntimeError("Native host exited; see host.log")
            response = json.loads(line)
            trace.write(json.dumps({"request": request, "response": response}) + "\n")
            trace.flush()
            if expect_rejection:
                assert not response["ok"], "Invalid decision was accepted"
                return None
            if not response["ok"]:
                raise RuntimeError(f"{command}: {response['error']}; see host.log")
            return response["result"]

        def prompt():
            return json.loads(call("getPrompt", sessionId=setup["gameId"], playerIndex=0))

        def snapshot():
            return json.loads(call("getSnapshot", sessionId=setup["gameId"], viewer=-1))

        def submit(answer, **extra):
            envelope = answer if answer["type"] == "directive" else {"type": prompt()["input"]["type"], "output": answer}
            return call("submitAction", sessionId=setup["gameId"], payload=json.dumps(envelope), **extra)

        def concede(player):
            submit({"type": "directive", "player": player, "directive": {"type": "concede"}})

        def departed(view, expected):
            assert [p["id"] for p in view["players"]] == [f"player-{i}" for i in range(4)], "Registered seat IDs shifted"
            for index in expected:
                assert view["players"][index]["status"] in ("lost", "conceded"), f"Seat {index} still playing"
            for zone in view["zones"]:
                if zone["zone"] in ("hand", "library"):
                    assert zone["cards"] == [], "Spectator gained private cards during concession"

        try:
            call("reset")
            call("startGame", payload=json.dumps(setup))
            pending = prompt()
            if args.phase == "priority":
                for _ in range(8):
                    if pending["input"]["type"] == "chooseAction":
                        break
                    assert pending["input"]["type"] == "mulligan", "Unexpected opening decision"
                    submit({"type": "mulliganDecision", "keep": True})
                    pending = prompt()
                else:
                    raise AssertionError("Opening decisions did not reach priority")
            assert pending["decidingPlayerId"] == "player-0", "Expected starting seat to own the decision"
            before = snapshot()
            submit({"type": "invalidTestDecision"}, expect_rejection=True)
            assert prompt() == pending and snapshot() == before, "Rejected action changed the stable publication"
            concede(3)
            still_pending = prompt()
            assert still_pending == pending, "Out-of-turn concession replaced another player's decision"
            departed(snapshot(), [3])
            concede(0)
            advanced = prompt()
            assert advanced["decidingPlayerId"] in ("player-1", "player-2"), "Departed decision owner held the native input open"
            departed(snapshot(), [0, 3])
            last_departure = int(advanced["decidingPlayerId"].split("-")[1])
            concede(last_departure)
            assert call("getGameOver", sessionId=setup["gameId"]) == "true", "One remaining player did not produce a terminal game"
            final = snapshot()
            departed(final, [0, 3, last_departure])
            remaining = 2 if last_departure == 1 else 1
            assert final["gameOver"] and final["winnerId"] == f"player-{remaining}", "Incorrect surviving winner"
        except BaseException as exc:
            error = f"{type(exc).__name__}: {exc}"
            raise
        finally:
            report = {"phase": args.phase, "passed": error is None and final is not None, "error": error,
                      "wireFormat": "canonical-type-output-with-directives",
                      "seconds": round(time.monotonic() - started, 3), "final": final}
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    runtime = parser.add_mutually_exclusive_group(required=True)
    runtime.add_argument("--classpath-file", type=Path)
    runtime.add_argument("--jar", type=Path)
    parser.add_argument("--forge-home", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phase", choices=("mulligan", "priority"), required=True)
    parser.add_argument("--timeout", type=int, default=45)
    run(parser.parse_args())
