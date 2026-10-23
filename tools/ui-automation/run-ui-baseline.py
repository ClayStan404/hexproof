#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Qualify maintained interaction contracts against the recorded 2.5 reference."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import socketserver
import subprocess
import sys
import threading
import time

from ui_baseline import load_manifest, validate_evidence


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def command_result(command, log, env, timeout):
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as output:
        # Forward terminal interrupts once; a second signal during run-native's
        # own finally block could otherwise interrupt its descendant cleanup.
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # run-native handles SIGTERM by stopping its own audit/helper groups.
            # Give that cleanup time to run before escalating this owned child.
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            exit_code = 124
            output.write("\nAcceptance command exceeded its deadline.\n")
        except BaseException:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            raise
    return {"command": [str(part) for part in command], "exitCode": exit_code,
            "durationSeconds": round(time.monotonic() - started, 3), "log": str(log)}


def run_qml_suites(manifest, binary, output, env):
    results = []
    test_env = dict(env, QT_QPA_PLATFORM="offscreen", QT_FATAL_WARNINGS="1")
    for suite in manifest["qmlSuites"]:
        log = output / (Path(suite).stem + ".txt")
        command = [str(binary), "-input", str(ROOT / "apps/client-qt/tests/qml" / suite),
                   "-import", str(ROOT / "apps/client-qt/qml")]
        result = command_result(command, log, test_env, 180)
        text = log.read_text(encoding="utf-8", errors="replace")
        totals = re.findall(r"Totals: (\d+) passed, (\d+) failed, (\d+) skipped", text)
        result["suite"] = suite
        result["status"] = "passed" if (
            result["exitCode"] == 0 and totals
            and all(int(passed) > 0 and failed == "0" and skipped == "0"
                    for passed, failed, skipped in totals)
            and "QWARN" not in text and "FAIL!" not in text) else "failed"
        results.append(result)
        if result["status"] != "passed":
            break
    return results


@contextmanager
def refusing_proxy():
    """Retain session-bus access while refusing every HTTP(S) proxy request."""
    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(1)
            try:
                self.request.recv(4096)
                with self.server.counter_lock:
                    self.server.request_count += 1
                self.request.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n"
                                     b"Connection: close\r\n\r\n")
            except OSError:
                pass

    class Server(socketserver.ThreadingTCPServer):
        daemon_threads = True

    with Server(("127.0.0.1", 0), Handler) as server:
        server.request_count = 0
        server.counter_lock = threading.Lock()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield server, f"http://127.0.0.1:{server.server_address[1]}"
        finally:
            server.shutdown()
            thread.join(timeout=2)


def native_environment(env, proxy_url):
    result = dict(env)
    for key in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "all_proxy", "ALL_PROXY"):
        result[key] = proxy_url
    result["NO_PROXY"] = result["no_proxy"] = ""
    return result


def run_native_scope(scope, manifest, args, output, fixture, env):
    scenario = HERE / "scenarios" / manifest["scenarios"][scope]["file"]
    destination = output / scope
    command = [sys.executable, str(HERE / "run-native.py"), "--binary", str(args.binary),
               "--scenario", str(scenario), "--freeze-scenarios", "--output", str(destination),
               "--os-input-helper", str(args.os_input_helper), "--timeout", "240",
               "--hang-timeout", "30"]
    if scope == "deck":
        command += ["--catalog", str(fixture / "cards.sqlite"),
                    "--fixture-dir", str(fixture), "--deck-manifest", str(fixture / "manifest.json")]
    result = command_result(command, output / (scope + "-runner.log"), env, 270)
    artifacts = destination / "seat-1/artifacts"
    try:
        runner = json.loads((destination / "report.json").read_text())
        if result["exitCode"] != 0 or runner.get("status") != "passed":
            raise ValueError("Native runner did not pass: " + str(runner.get("reason", "")))
        read = lambda name: json.loads((artifacts / name).read_text())
        actions = [json.loads(line) for line in (artifacts / "actions.jsonl").read_text().splitlines()
                   if line.strip()]
        result["coverage"] = validate_evidence(manifest, scope, read("ui-baseline.json"),
                                                read("startup.json"), read("audit-summary.json"), actions)
        result["status"] = "passed"
    except (OSError, ValueError, TypeError) as error:
        result.update(status="failed", error=str(error))
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--output", required=True, type=Path, help="New artifact directory")
    result.add_argument("--checks-only", action="store_true",
                        help="Run automated guards only; never claim full native acceptance")
    result.add_argument("--binary", type=Path, default=ROOT / "build/client-qt/hexproof_native_audit")
    result.add_argument("--qml-test-binary", type=Path, default=ROOT / "build/client-qt/hexproof_qml_test")
    result.add_argument("--os-input-helper", type=Path,
                        help="Explicit guarded compositor helper required for native acceptance")
    return result


def run(args):
    manifest_path = HERE / "ui-behavior-baseline.json"
    manifest = load_manifest(manifest_path)
    args.output = args.output.resolve()
    args.binary = args.binary.resolve()
    args.qml_test_binary = args.qml_test_binary.resolve()
    if args.output.exists():
        raise ValueError("Output already exists; preserve previous acceptance evidence")
    if not args.qml_test_binary.is_file():
        raise ValueError("Build the Qt test runner first: " + str(args.qml_test_binary))
    if not args.checks_only:
        if not args.binary.is_file() or args.os_input_helper is None:
            raise ValueError("Native acceptance needs a built audit client and explicit --os-input-helper")
        args.os_input_helper = args.os_input_helper.resolve()
        if not args.os_input_helper.is_file() or not os.access(args.os_input_helper, os.X_OK):
            raise ValueError("The explicit system-input helper must be executable")
    args.output.mkdir(parents=True)
    report = {"schema": "hexproof.ui-baseline-report.v1", "reference": manifest["reference"],
              "performance": "not-assessed",
              "qualification": "failed", "native": {"status": "not-run"}}
    write_json(args.output / "report.json", report)
    try:
        (args.output / "baseline-manifest.json").write_bytes(manifest_path.read_bytes())
        report.update(manifestSha256=digest(manifest_path),
                      tools={path.name: digest(path) for path in
                             (Path(__file__), HERE / "ui_baseline.py",
                              HERE / "make-deck-regression-fixture.py")},
                      qmlTestBinarySha256=digest(args.qml_test_binary),
                      qmlSuiteSha256={suite: digest(ROOT / "apps/client-qt/tests/qml" / suite)
                                      for suite in manifest["qmlSuites"]})
        report["automated"] = run_qml_suites(manifest, args.qml_test_binary, args.output, os.environ)
        passed = len(report["automated"]) == len(manifest["qmlSuites"]) and all(
            item["status"] == "passed" for item in report["automated"])
        if passed and args.checks_only:
            report["qualification"] = "automated-only"
        elif passed:
            fixture = args.output / "fixture"
            preparation = command_result(
                [sys.executable, str(HERE / "make-deck-regression-fixture.py"), "--output", str(fixture)],
                args.output / "fixture.log", os.environ, 30)
            report["fixture"] = preparation
            if preparation["exitCode"] == 0:
                report["binarySha256"] = digest(args.binary)
                with refusing_proxy() as (proxy, url):
                    env = native_environment(os.environ, url)
                    report["native"] = {"status": "running", "scenarios": []}
                    scopes = report["native"]["scenarios"]
                    for scope in manifest["scenarios"]:
                        report["native"]["activeScope"] = scope
                        scopes.append(run_native_scope(scope, manifest, args, args.output, fixture, env))
                        write_json(args.output / "report.json", report)
                        if scopes[-1]["status"] != "passed":
                            break
                    report["proxy"] = {"forwarding": False, "requestsRefused": proxy.request_count,
                                       "strictNetworkIsolation": False}
                report["native"].pop("activeScope", None)
                report["native"]["status"] = "passed" if len(scopes) == len(manifest["scenarios"]) \
                    and all(item["status"] == "passed" for item in scopes) else "failed"
                if report["native"]["status"] == "passed":
                    report["qualification"] = "passed"
    except BaseException as error:
        report.update(qualification="failed", error=str(error) or type(error).__name__)
        if report["native"]["status"] == "running":
            report["native"]["status"] = "failed"
        raise
    finally:
        write_json(args.output / "report.json", report)
    print(f"{report['qualification']}: {args.output / 'report.json'}")
    return 0 if report["qualification"] in ("passed", "automated-only") else 1


def main():
    try:
        return run(parser().parse_args())
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Interrupted; owned acceptance commands stopped.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
