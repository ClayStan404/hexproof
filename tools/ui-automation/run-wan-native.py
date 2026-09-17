#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Run selected Linux/Windows Qt seats against an explicitly configured private WAN hub."""

import argparse
from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlsplit

SPEC = importlib.util.spec_from_file_location("native_runner", Path(__file__).with_name("run-native.py"))
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)
SHARED_KEYS = ("forge-room", "forge-migration", "forge-peer-study", "forge-host-finished", "host-fault")


@contextmanager
def display_lock(path):
    with path.open("a+b") as lock:
        if os.name == "nt":
            import msvcrt
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            if os.name == "nt":
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)


def stop_owned(process):
    if os.name != "nt":
        NATIVE.stop_owned(process)
    elif process.poll() is None:
        # Scope termination to this live child and its descendants. Never match
        # by executable name: the desktop may contain unrelated user clients.
        taskkill = Path(os.environ["SystemRoot"]) / "System32/taskkill.exe"
        subprocess.run([str(taskkill), "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        process.wait(timeout=5)


def source_identity():
    if (NATIVE.ROOT / ".git").exists():
        return {"commit": NATIVE.git_output("rev-parse", "HEAD"),
                "workingTree": NATIVE.git_output("status", "--short")}
    commit = (NATIVE.ROOT / "source-commit.txt").read_text(encoding="ascii").strip()
    if not re.fullmatch(r"[a-f0-9]{40,64}", commit):
        raise ValueError("Packaged native artifact has no valid source identity")
    return {"commit": commit, "workingTree": "packaged-native-artifact"}


class Coordination:
    """Mirror only owner-written scenario markers, never application profiles."""

    def __init__(self, config, shared):
        self.base = config["url"] + "/" + config["token"] + "/coord/" + config["case"] + "-"
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.owner = 1 in config["seats"]
        self.shared = shared
        self.last = {}

    def request(self, key, value=None):
        data = None if value is None else json.dumps(value).encode()
        if data is not None and len(data) > 65536:
            raise ValueError("Coordination record exceeded its bound")
        request = urllib.request.Request(self.base + key, data=data, method="GET" if data is None else "PUT")
        with self.opener.open(request, timeout=5) as response:
            if response.status == 204:
                return None
            raw = response.read(65537)
            if len(raw) > 65536:
                raise ValueError("Coordination record exceeded its bound")
            return json.loads(raw)

    def update(self):
        other = "2" if self.owner else "1"
        done = self.request("node-" + other + "-done")
        if done is not None and done.get("status") != "passed":
            raise RuntimeError("Remote native participant failed; stopping owned test windows")
        for name in SHARED_KEYS:
            path = self.shared / (name + ".json")
            if self.owner:
                if not path.exists():
                    continue
                if path.stat().st_size > 65536:
                    raise ValueError("Shared marker exceeded its bound")
                value = json.loads(path.read_text(encoding="utf-8"))
                if value != self.last.get(name):
                    self.request(name, value)
                    self.last[name] = value
            else:
                value = self.request(name)
                if value is not None and value != self.last.get(name):
                    NATIVE.write_json(path, value)
                    self.last[name] = value


def load_config(path):
    config = json.loads(path.read_text(encoding="utf-8-sig"))
    endpoint = urlsplit(config["url"])
    if (endpoint.scheme != "https" or not endpoint.hostname or endpoint.username is not None
            or endpoint.password is not None or endpoint.port == 0
            or endpoint.path not in ("", "/") or endpoint.query or endpoint.fragment
            or not re.fullmatch(r"[a-f0-9]{64}", config["token"])
            or not re.fullmatch(r"[a-z0-9-]{1,48}", config["case"])
            or config["seats"] not in ([1], [1, 3], [2], [2, 3])
            or config.get("migration", "") not in ("", "1", "loss")
            or not isinstance(config.get("peer", False), bool)
            or config.get("peerExpected", "direct") not in ("direct", "relay")
            or (config.get("peerExpected") == "relay" and not config.get("peer"))
            or not 30 <= config.get("timeout", 900) <= 1800):
        raise ValueError("Invalid private WAN native configuration")
    config["url"] = config["url"].rstrip("/")
    for name in ("output", "binary", "runtime", "catalog", "manifest"):
        if not Path(config[name]).is_absolute():
            raise ValueError("Native test paths must be absolute: " + name)
    return config


def run(config):
    output = Path(config["output"])
    output.mkdir(parents=True, exist_ok=False)
    shared = output / "shared"
    shared.mkdir()
    coordination = Coordination(config, shared)
    processes, logs, results = [], [], []
    reason = None
    started = time.monotonic()
    scenario = NATIVE.ROOT / "tools/ui-automation/scenarios/ForgeDuelMatch.qml"
    NATIVE.write_json(output / "environment.json", {
        **source_identity(),
        "binarySha256": NATIVE.digest(Path(config["binary"])),
        "hostingArtifacts": {name: NATIVE.digest(Path(config["binary"]).parent / name)
                             for name in ("hexproof-forge-host.exe" if os.name == "nt" else "hexproof-forge-host", "forge-overlay.jar")
                             if (Path(config["binary"]).parent / name).is_file()},
        "scenario": NATIVE.scenario_provenance(scenario),
        "seats": config["seats"], "case": config["case"], "variant": config["variant"],
        "migration": config.get("migration", ""), "peer": config.get("peer", False),
        "peerExpected": config.get("peerExpected", "direct"),
        "requestedWindowMode": "maximized", "evidence": "native-qt-input", "startedAt": time.time(),
        "graphicsEnvironment": {name: os.environ[name] for name in
                                ("QT_QPA_PLATFORM", "QSG_RENDER_LOOP", "QSG_RHI_BACKEND",
                                 "QSG_RHI_PREFER_SOFTWARE_RENDERER", "QSG_USE_SIMPLE_ANIMATION_DRIVER",
                                 "QSG_NO_VSYNC", "QT_QUICK_BACKEND", "QSG_INFO") if name in os.environ},
    })
    try:
        for seat in config["seats"]:
            NATIVE.prepare_profile(output / f"seat-{seat}", Path(config["catalog"]))
        coordination.request("node-" + str(config["seats"][0]) + "-ready", {"ready": True})
        # Complete profile copies on both machines before either scenario clock
        # starts. This also prevents a slow remote build from timing out a GUI.
        other = "2" if coordination.owner else "1"
        while coordination.request("node-" + other + "-ready") is None:
            if time.monotonic() - started > 180:
                raise TimeoutError("Remote native participant did not become ready")
            time.sleep(0.5)
        launched = time.monotonic()
        for seat in config["seats"]:
            profile = output / f"seat-{seat}"
            artifacts = profile / "artifacts"
            artifacts.mkdir()
            env = dict(os.environ, XDG_CONFIG_HOME=str(profile / "config"),
                       XDG_DATA_HOME=str(profile / "data"), XDG_CACHE_HOME=str(profile / "cache"),
                       HEXPROOF_TEST_PROFILE_ROOT=str(profile), HEXPROOF_AUDIT_DRIVER=str(scenario),
                       HEXPROOF_AUDIT_OUTPUT=str(artifacts), HEXPROOF_AUDIT_SHARED=str(shared),
                       HEXPROOF_AUDIT_STARTUP_SERVICES="0", HEXPROOF_AUDIT_PLAYER_HOSTED="1",
                       HEXPROOF_AUDIT_SEAT=str(seat), HEXPROOF_AUDIT_PLAYERS="3",
                       HEXPROOF_AUDIT_VARIANT=config["variant"], HEXPROOF_AUDIT_DECK_MANIFEST=config["manifest"],
                       HEXPROOF_AUDIT_MIGRATION=config.get("migration", ""),
                       HEXPROOF_AUDIT_PEER="1" if config.get("peer") else "0",
                       HEXPROOF_AUDIT_PEER_EXPECTED=config.get("peerExpected", "direct"),
                       HEXPROOF_FORGE_HOST_RUNTIME_DIR=config["runtime"], QT_SCALE_FACTOR="1")
            for name in ("HEXPROOF_AUDIT_WIDTH", "HEXPROOF_AUDIT_HEIGHT", "AUDIT_WIDTH", "AUDIT_HEIGHT",
                         "http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
                env.pop(name, None)
            log = (profile / "client.log").open("w")
            logs.append(log)
            command = [config["binary"], "--instance-label", f"WAN Test {config['case']} seat {seat}",
                       "--server-url", "wss" + config["url"][5:] + "/" + config["token"] + "/ws",
                       "--display-name", f"WAN GUI Player {seat}"]
            process = subprocess.Popen(command, cwd=NATIVE.ROOT, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                       start_new_session=os.name != "nt")
            processes.append((seat, process, artifacts))
        with (output / "process-samples.jsonl").open("w") as samples:
            while any(p.poll() is None for _, p, _ in processes):
                coordination.update()
                if time.monotonic() - started > config.get("timeout", 900):
                    raise TimeoutError("Native WAN watchdog expired")
                status = []
                for seat, process, artifacts in processes:
                    if process.poll() is not None:
                        if NATIVE.seat_result(process, artifacts)["status"] != "passed":
                            raise RuntimeError(f"Native seat {seat} exited without a pass")
                        continue
                    heartbeat = artifacts / "heartbeat.json"
                    if not heartbeat.exists() and time.monotonic() - launched > 60:
                        raise TimeoutError(f"Native seat {seat} did not start its driver")
                    if heartbeat.exists() and time.time() - heartbeat.stat().st_mtime > 30:
                        raise TimeoutError(f"Native seat {seat} heartbeat stopped")
                    measured = (NATIVE.process_sample(process) if os.name != "nt" else
                                {"pid": process.pid, "exitCode": process.poll(),
                                 "resourceSampling": "unavailable-on-windows"})
                    sample = dict(measured, seat=seat, elapsed=time.monotonic() - started)
                    samples.write(json.dumps(sample) + "\n")
                    status.append({"seat": seat, "alive": True})
                samples.flush()
                coordination.request("node-" + str(config["seats"][0]) + "-status", {"seats": status})
                time.sleep(0.25)
        coordination.update()
    except (OSError, ValueError, RuntimeError, TimeoutError, KeyboardInterrupt) as error:
        reason = str(error).replace(config["token"], "[namespace]")
    finally:
        for _, process, _ in reversed(processes):
            stop_owned(process)
        for log in logs:
            log.close()
        for seat, process, artifacts in processes:
            results.append(dict(NATIVE.seat_result(process, artifacts), seat=seat))
        passed = reason is None and len(results) == len(config["seats"]) and all(r["status"] == "passed" for r in results)
        report = {"status": "passed" if passed else "failed", "reason": reason,
                  "durationSeconds": round(time.monotonic() - started, 3), "seats": results}
        NATIVE.write_json(output / "report.json", report)
        try:
            coordination.request("node-" + str(config["seats"][0]) + "-done", {"status": report["status"], "reason": reason})
        except (OSError, ValueError):
            pass
        print(json.dumps({"status": report["status"], "reason": reason, "output": str(output)}), flush=True)
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path, help="Private configuration for an explicitly authorized test hub")
    args = parser.parse_args()
    config = load_config(args.config)
    if sys.platform not in ("linux", "win32"):
        parser.error("This native orchestrator currently supports Linux and Windows")
    if os.name != "nt" and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        parser.error("An active native desktop is required")
    lock_path = NATIVE.ROOT / "build/native-verification/.display.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    def interrupted(_number, _frame):
        raise KeyboardInterrupt("Stopping owned WAN test windows")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        with display_lock(lock_path):
            return run(config)
    except (BlockingIOError, PermissionError):
        parser.error("Another native scenario owns the display or the lock is inaccessible")


if __name__ == "__main__":
    raise SystemExit(main())
