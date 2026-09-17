#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Local Linux feasibility experiment; does not modify the packaged Forge host.

Compares three production JVMs with one experimental JVM on the same scripted
human games. Synthetic decks exceed copy limits. Isolation probes are negative
controls: reproducing a hazard is successful evidence, not production readiness.
"""

import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import threading
import time

HERE = Path(__file__).resolve().parent
HOST_SOURCE = HERE.parents[1] / "third_party/forge-runtime/native-host"
sys.path.insert(0, str(HOST_SOURCE))
from test_full_game import choose, record_evidence


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def java_args(args, main):
    return ["java", "-Xms32m", f"-Xmx{args.heap}m", "-XX:+UseSerialGC",
            "-XX:ActiveProcessorCount=2", "-XX:+ExitOnOutOfMemoryError",
            "-Djava.awt.headless=true", "-cp", args.classpath, main]


def clean_env(profile):
    env = dict(os.environ, HEXPROOF_FORGE_PROFILE=str(profile))
    for key in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS"):
        env.pop(key, None)
    return env


class Host:
    def __init__(self, args, path, shared):
        path.mkdir()
        profile = path / "profile"
        profile.mkdir()
        self.shared = shared
        self.pending = {}
        self.lock = threading.Lock()
        self.next_id = 0
        self.latencies = []
        self.log = (path / "host.log").open("w")
        main = "SharedJvmHost" if shared and not args.production else "NativeHost"
        command = java_args(args, "org.hexproof.forge." + main)
        command += ([str(args.runtime / "forge-gui")] if shared and not args.production else
                    ["--interactive-server", "--forge-home", str(args.runtime / "forge-gui")])
        if shared and args.production:
            command += ["--max-games", "3"]
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.log, text=True, env=clean_env(profile))
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        try:
            for line in self.process.stdout:
                response = json.loads(line)
                with self.lock:
                    request_id = response["requestId"] if self.shared else next(iter(self.pending))
                    future = self.pending.pop(request_id)
                future.set_result(response)
        except Exception as error:
            self.fail_pending(error)
        finally:
            self.fail_pending(RuntimeError("Host stdout closed"))

    def fail_pending(self, error):
        with self.lock:
            pending, self.pending = self.pending, {}
        for future in pending.values():
            future.set_exception(error)

    def call(self, command, **fields):
        started = time.monotonic()
        future = concurrent.futures.Future()
        with self.lock:
            self.next_id += 1
            request_id = self.next_id
            self.pending[request_id] = future
            request = {"command": command, **fields}
            if self.shared:
                request["requestId"] = request_id
            self.process.stdin.write(json.dumps(request) + "\n")
            self.process.stdin.flush()
        response = future.result(timeout=60)
        with self.lock:
            self.latencies.append((command, time.monotonic() - started))
        if not response["ok"]:
            raise RuntimeError(response["error"])
        return response["result"]

    def close(self):
        try:
            self.process.stdin.write('{"command":"quit"}\n')
            self.process.stdin.flush()
            self.process.wait(timeout=5)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            self.process.kill()
            self.process.wait(timeout=5)
        finally:
            self.reader.join(timeout=2)
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
            self.process.stdout.close()
            self.log.close()


class MemorySamples:
    """Sum simultaneous JVM PSS, counting shared mapped pages proportionally."""
    def __init__(self):
        self.hosts = []
        self.rows = []
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def sample(self):
        row = {"time": time.monotonic(), "rssKiB": 0, "pssKiB": 0, "pids": []}
        for host in tuple(self.hosts):
            if host.process.poll() is not None:
                continue
            pid = host.process.pid
            try:
                values = {}
                for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
                    if line.startswith(("Rss:", "Pss:")):
                        key, value, _ = line.split()
                        values[key] = int(value)
                row["rssKiB"] += values["Rss:"]
                row["pssKiB"] += values["Pss:"]
                row["pids"].append(pid)
            except (FileNotFoundError, ProcessLookupError):
                pass
        self.rows.append(row)
        return row

    def run(self):
        while not self.stop.wait(0.1):
            self.sample()


def setup(game_id, index, seed):
    land, creature = ("Forest", "Elvish Visionary") if index % 2 == 0 else ("Plains", "Glory Seeker")
    deck = [{"name": name} for name in [land] * 24 + [creature] * 36]
    return {"gameId": game_id, "variant": "constructed", "seed": seed, "startingLife": 20,
            "startingPlayerIndex": index % 2,
            "players": [{"name": f"{game_id}-seat-{seat}", "deck": deck} for seat in range(2)]}, land, creature


def privacy(view, viewer, game_id, allowed):
    assert view["gameId"] == game_id, "Cross-game snapshot routing"
    assert [p["name"] for p in view["players"]] == [f"{game_id}-seat-{seat}" for seat in range(2)]
    for zone in view["zones"]:
        if not view["gameOver"] and (zone["zone"] == "library" or
                zone["zone"] == "hand" and zone["ownerId"] != f"player-{viewer}"):
            assert not zone["cards"], "Hidden hand/library disclosed"
        for card in zone["cards"]:
            name = card.get("identity", {}).get("name")
            assert name is None or name in allowed, "Foreign game card identity"


def play(host, config, land, creature, path):
    game_id = config["gameId"]
    metrics, counts = collections.Counter(), collections.Counter()
    previous = None
    started = time.monotonic()
    with path.open("w") as trace:
        for decision in range(3000):
            if host.call("getGameOver", sessionId=game_id) == "true":
                break
            prompt = json.loads(host.call("getPrompt", sessionId=game_id, playerIndex=0))
            viewer = int(prompt["decidingPlayerId"].split("-")[1])
            views = {seat: json.loads(host.call("getSnapshot", sessionId=game_id, viewer=seat))
                     for seat in (-1, 0, 1)}
            for seat, view in views.items():
                privacy(view, seat, game_id, {land, creature})
                if view["turn"] > 0:
                    assert view["startingPlayerId"] == f"player-{config['startingPlayerIndex']}"
            public = views[-1]
            record_evidence(public, previous, creature, metrics)
            previous = public
            kind = prompt["input"]["type"]
            counts[kind] += 1
            presentation = prompt["input"].get("presentation", {})
            if kind == "chooseCards" and (presentation.get("description", "").startswith("Cleanup Phase") or
                                           presentation.get("title") == "Discard to maximum hand size"):
                # Explicit policy for the real end-step hand-size discard.
                amount = prompt["input"]["min"]
                assert 0 < amount == prompt["input"]["max"]
                answer = {"type": "chooseCardsDecision", "chosenCardIds":
                          [card["id"] for card in prompt["input"]["cards"][:amount]]}
                metrics["cleanup_discards"] += amount
            else:
                answer = choose(prompt["input"], views[viewer], land, metrics)
            trace.write(json.dumps({"decision": decision, "prompt": prompt, "views": views, "answer": answer}) + "\n")
            host.call("submitAction", sessionId=game_id, payload=json.dumps({"type": kind, "output": answer}))
        else:
            raise AssertionError("Game exceeded 3000 decisions")
    final = json.loads(host.call("getSnapshot", sessionId=game_id, viewer=-1))
    record_evidence(final, previous, creature, metrics)
    assert final["gameOver"] and final.get("winnerId")
    assert min(p["life"] for p in final["players"]) <= 0, "No natural lethal outcome"
    for key in ("mana_source_choices", "attackers_declared", "creatures_entered", "combat_life_lost"):
        assert metrics[key] > 0, key
    if creature == "Elvish Visionary":
        assert metrics["etb_draws"] > 0, "No observed ETB draw resolution"
    host.call("endGame", sessionId=game_id)
    return {"gameId": game_id, "seconds": time.monotonic() - started, "decisions": decision,
            "metrics": dict(metrics), "prompts": dict(counts), "final": final, "passed": True}


def scenario(args, shared, round_index):
    label = f"{'shared' if shared else 'separate'}-{round_index}"
    path = args.output / label
    path.mkdir()
    memory = MemorySamples()
    memory.thread.start()
    hosts = []
    all_hosts = []
    report = {"scenario": label, "heapMiBPerJVM": args.heap, "gamesPerWave": 3, "waves": []}
    started = time.monotonic()
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            for wave in range(args.waves):
                if not shared or wave == 0:
                    hosts = [Host(args, path / f"host-{wave}-{index}", shared) for index in range(1 if shared else 3)]
                    all_hosts.extend(hosts)
                    memory.hosts = hosts
                    list(pool.map(lambda host: host.call("reset"), hosts))
                cold_ready = time.monotonic() - started
                configs = [setup(f"{label}-wave-{wave}-game-{index}", index, 42 + round_index * 20 + wave * 3 + index)
                           for index in range(3)]
                # Equal startup admission order. All three games stay alive at
                # a mulligan boundary before their concurrent player drivers run.
                for index, (config, _, _) in enumerate(configs):
                    host = hosts[0] if shared else hosts[index]
                    handle = json.loads(host.call("startGame", payload=json.dumps(config)))
                    assert handle["sessionId"] == config["gameId"]
                wave_result = {"wave": wave, "readySecondsSinceStart": cold_ready,
                               "allGamesOpenMemory": memory.sample(), "games": []}
                report["waves"].append(wave_result)
                if shared and wave > 0 and args.abort_between_waves:
                    # Abort one pending game, preserving both other games and
                    # then reuse the freed slot without restarting this JVM.
                    survivor_ids = [config[0]["gameId"] for config in configs[1:]]
                    before = {game: (hosts[0].call("getPrompt", sessionId=game, playerIndex=0),
                                    hosts[0].call("getSnapshot", sessionId=game, viewer=-1)) for game in survivor_ids}
                    aborted = configs[0][0]["gameId"]
                    hosts[0].call("abortGame", sessionId=aborted)
                    try:
                        hosts[0].call("getPrompt", sessionId=aborted, playerIndex=0)
                    except RuntimeError as error:
                        assert args.production or "Unknown session" in str(error)
                    else:
                        raise AssertionError("Closed game still addressable")
                    for game in survivor_ids:
                        after = (hosts[0].call("getPrompt", sessionId=game, playerIndex=0),
                                 hosts[0].call("getSnapshot", sessionId=game, viewer=-1))
                        assert after == before[game], "Abort changed another game's publication"
                    configs[0] = setup(aborted + "-replacement", 0, 42 + round_index * 20 + wave * 3)
                    hosts[0].call("startGame", payload=json.dumps(configs[0][0]))
                    wave_result["abortedGame"] = aborted
                    wave_result["survivorPublicationsPreserved"] = True
                futures = [pool.submit(play, hosts[0] if shared else hosts[index], config, land, creature,
                                       path / f"wave-{wave}-game-{index}.jsonl")
                           for index, (config, land, creature) in enumerate(configs)]
                errors = []
                for index, future in enumerate(futures):
                    try:
                        wave_result["games"].append(future.result(timeout=180))
                    except Exception as error:
                        wave_result["games"].append({"gameId": configs[index][0]["gameId"], "passed": False, "error": repr(error)})
                        errors.append(error)
                if errors:
                    raise RuntimeError(f"{len(errors)} game driver(s) failed: {errors[0]}") from errors[0]
                if shared and not args.production:
                    wave_result["afterCloseGC"] = json.loads(hosts[0].call("stats", gc=True))
                print(f"{label} wave {wave}: 3 natural wins; "
                      f"{wave_result.get('afterCloseGC', {})}", flush=True)
                if not shared:
                    for host in hosts:
                        host.close()
                    hosts = []
                write_json(path / "result.json", report)
        report["passed"] = True
    except BaseException as error:
        report["error"] = repr(error)
        raise
    finally:
        report["seconds"] = time.monotonic() - started
        latencies = [seconds for host in all_hosts for command, seconds in host.latencies if command == "submitAction"]
        if latencies:
            ordered = sorted(latencies)
            report["submitSeconds"] = {"count": len(ordered), "max": max(ordered), "p95": ordered[int(len(ordered) * .95)]}
        for host in hosts:
            try:
                host.close()
            except Exception as error:
                report.setdefault("cleanupErrors", []).append(repr(error))
        memory.stop.set()
        memory.thread.join(timeout=2)
        report["sampledPeakPssKiB"] = max((r["pssKiB"] for r in memory.rows), default=0)
        report["sampledPeakRssKiB"] = max((r["rssKiB"] for r in memory.rows), default=0)
        report["maxSimultaneousJVMs"] = max((len(r["pids"]) for r in memory.rows), default=0)
        write_json(path / "memory.json", memory.rows)
        write_json(path / "result.json", report)
    return report


def isolation(args):
    reports = []
    for name in ("random", "blocked-menu", "failure-routing"):
        path = args.output / name
        path.mkdir()
        profile = path / "profile"
        profile.mkdir()
        command = java_args(args, "org.hexproof.forge.SharedJvmIsolationProbe")
        command += [str(args.runtime / "forge-gui"), name]
        with (path / "host.log").open("w") as log:
            result = subprocess.run(command, env=clean_env(profile), stdout=subprocess.PIPE,
                                    stderr=log, text=True, timeout=100)
        (path / "stdout.json").write_text(result.stdout)
        result.check_returncode()
        report = json.loads(result.stdout)
        assert report["hazardReproduced"]
        reports.append(report)
        print(json.dumps(report), flush=True)
    return reports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--heap", type=int, default=512)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--waves", type=int, default=2)
    parser.add_argument("--only", choices=("all", "games", "isolation"), default="all")
    parser.add_argument("--abort-between-waves", action="store_true",
                        help="Also probe unsafe abort/replacement; may fail on the unmodified lifecycle")
    parser.add_argument("--production", action="store_true",
                        help="Measure the packaged adapter 3 shared worker; use --only games")
    args = parser.parse_args()
    if platform.system() != "Linux" or min(args.heap, args.rounds, args.waves) < 1:
        parser.error("Linux and positive heap/round/wave values are required")
    if args.production and args.only != "games":
        parser.error("Production isolation regressions run in build-native.py; choose --only games here")
    args.runtime = args.runtime.resolve(strict=True)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    classes = args.output / "classes"
    classes.mkdir()
    jars = [args.runtime / "forge-harness.jar", *sorted((args.runtime / "lib").glob("*.jar"))]
    classpath = os.pathsep.join(map(str, jars))
    if not args.production:
        subprocess.run(["javac", "--release", "21", "-encoding", "UTF-8", "-cp", classpath,
                        "-d", str(classes), *map(str, sorted(HERE.glob("*.java")))], check=True)
    args.classpath = str(classes) + os.pathsep + classpath
    artifacts = jars + sorted(HERE.glob("*.java")) + [Path(__file__), HOST_SOURCE / "test_full_game.py"]
    write_json(args.output / "provenance.json", {
        "platform": platform.platform(), "java": subprocess.run(["java", "-version"], capture_output=True, text=True).stderr,
        "argv": sys.argv, "sampleIntervalSeconds": .1, "metric": "sum of live JVM smaps_rollup PSS and RSS",
        "artifacts": [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in artifacts]})
    report = {}
    try:
        if args.only in ("all", "isolation"):
            report["isolation"] = isolation(args)
        if args.only in ("all", "games"):
            report["scenarios"] = []
            for index in range(args.rounds):
                for shared in ((False, True) if index % 2 == 0 else (True, False)):
                    report["scenarios"].append(scenario(args, shared, index))
        report["completed"] = True
    finally:
        write_json(args.output / "result.json", report)


if __name__ == "__main__":
    main()
