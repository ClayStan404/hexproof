#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Run bounded Linux CI JVM regressions over the pinned base and current overlay."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FORGE = ROOT / "third_party/forge-runtime"
NATIVE_TESTS = (
    "NativeManaUndoRegressionTest", "NativePriorityManaUndoRegressionTest", "NativeLotusBloomRegressionTest",
    "NativeSnapshotRegressionTest", "NativePaymentIdRegressionTest",
    "NativePromptWaitRegressionTest", "NativeCrashDiagnosticsRegressionTest",
)
# Each selected Go test explicitly accepts the current overlay. Other live
# tests still construct base-only commands and belong to the full runtime gate.
GO_TESTS = (
    "TestLiveForgeManaUndo", "TestLiveForgePriorityManaUndo", "TestLiveForgeLotusBloom",
    "TestLiveForgeCrashDiagnosticsExternalKill", "TestLiveForgeCrashDiagnosticsCleanAbort",
)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def run_step(name, command, output, report, *, cwd=ROOT, env=None, timeout=120):
    log = output / (name + ".log")
    record = {"name": name, "command": [str(value) for value in command], "log": log.name}
    report["steps"].append(record)
    started = time.monotonic()
    print(f"Running {name}", flush=True)
    try:
        with log.open("w") as stream:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                # Go may own a test executable and several JVMs. Kill the
                # whole isolated POSIX session, then reap its direct child.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise
            if code:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                raise subprocess.CalledProcessError(code, command)
        record["status"] = "passed"
    except (OSError, subprocess.SubprocessError, KeyboardInterrupt):
        record["status"] = "failed"
        if log.is_file():
            print(log.read_text(errors="replace")[-8000:], file=sys.stderr)
        raise
    finally:
        record["elapsedSeconds"] = round(time.monotonic() - started, 3)


def require_go_results(log):
    passed = set()
    for line in log.read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("Action") == "pass" and event.get("Test") in GO_TESTS:
            passed.add(event["Test"])
    if missing := set(GO_TESTS) - passed:
        raise ValueError("Selected real Go regressions did not pass: " + ", ".join(sorted(missing)))


def overlay_directory(output, manifest, source):
    pins = {"baseRuntimeId": manifest["runtimeId"], "baseManifestSha256": manifest["forgeManifestSha256"],
            "baseArchiveSha256": manifest["forge"]["sha256"], "sourceArchiveSha256": source["sha256"]}
    key = hashlib.sha256(json.dumps(pins, sort_keys=True).encode()).hexdigest()
    return output / ("overlay-" + key[:20])


def validate_overlay(metadata, manifest, jar, overlay):
    if (metadata.get("baseRuntimeId") != manifest["runtimeId"]
            or metadata.get("baseManifestSha256") != manifest["forgeManifestSha256"]):
        raise ValueError("Regression overlay was compiled against different pinned base inputs")
    if metadata.get("runtimeId") != overlay.identity()[0] or metadata.get("sha256") != overlay.digest(jar):
        raise ValueError("Regression overlay differs from the current reviewed sources")


def qualify(args, report):
    overlay = module("regression_overlay", FORGE / "build-overlay.py")
    args.javac = overlay.find_javac(args.javac)
    if not args.java:
        args.java = str(Path(args.javac).with_name("java"))
    packager = module("regression_packager", FORGE / "source-package.py")
    manifest = json.loads(overlay.BASE_MANIFEST.read_text())
    # Use the existing downloader: cache hits and explicit files receive the
    # same mandatory pinned size/checksum validation as production builds.
    started = time.monotonic()
    base = overlay.pinned_file(manifest["forge"], args.cache, args.base_archive)
    report["baseArchiveSha256"] = manifest["forge"]["sha256"]
    report["basePreparationSeconds"] = round(time.monotonic() - started, 3)
    source = json.loads((FORGE / "overlay-base.json").read_text())["source"]
    report["sourceArchiveSha256"] = source["sha256"]
    # The builder's native identity intentionally excludes immutable base pins.
    # Separate their caches so a base/source upgrade cannot reuse old bytecode.
    overlay_output = overlay_directory(args.output, manifest, source)
    run_step("build-overlay", [sys.executable, FORGE / "build-overlay.py", "--output", overlay_output,
                               "--cache", args.cache, "--base-archive", base, "--javac", args.javac],
             args.output, report, timeout=300)
    jar = overlay_output / "forge-overlay.jar"
    metadata = json.loads((overlay_output / "forge-overlay.json").read_text())
    validate_overlay(metadata, manifest, jar, overlay)
    report["runtimeId"] = metadata["runtimeId"]
    report["overlaySha256"] = metadata["sha256"]

    # Re-extract only authenticated archives into a disposable test directory;
    # no local production runtime/index is replaced or trusted from a cache.
    with tempfile.TemporaryDirectory(prefix="engine-", dir=args.output) as temporary:
        stage = Path(temporary)
        runtime = packager.extract_archive(base, stage, "hexproof-forge-runtime")
        classes = stage / "test-classes"
        classes.mkdir()
        classpath = os.pathsep.join(map(str, (jar, runtime / "forge-harness.jar", runtime / "lib/*")))
        tests = sorted((FORGE / "native-host/src/test/java").rglob("*.java"))
        if not tests:
            raise ValueError("Native regression sources are missing")
        arguments = ["--release", "21", "-encoding", "UTF-8", "-sourcepath", "", "-cp", classpath,
                     "-d", str(classes), *map(str, tests)]
        argfile = stage / "javac.args"
        argfile.write_text("\n".join(json.dumps(value) for value in arguments) + "\n")
        run_step("compile-native-tests", [args.javac, "@" + str(argfile)], args.output, report)
        for test in NATIVE_TESTS:
            profile = stage / test
            profile.mkdir()
            run_step(test, [args.java, "-Xmx2g", "-Djava.awt.headless=true", "-Duser.home=" + str(profile),
                           "-cp", str(classes) + os.pathsep + classpath, "org.hexproof.forge." + test,
                           runtime / "forge-gui"], args.output, report, timeout=90)

        environment = {**os.environ, "HEXPROOF_FORGE_JAVA": args.java,
                       "HEXPROOF_REAL_FORGE_ROOT": str(runtime), "HEXPROOF_REAL_FORGE_OVERLAY": str(jar)}
        run_step("go-engine-regressions", [args.go, "test", "-json", "-p", "1", "-race", "-tags",
                 "engineintegration", "-count=1", "-timeout", "10m", "./internal/rulesengine/forge",
                 "-run", "^(" + "|".join(GO_TESTS) + ")$"], args.output, report,
                 cwd=ROOT / "apps/server", env=environment, timeout=630)
        require_go_results(args.output / "go-engine-regressions.log")
        report["passedGoTests"] = list(GO_TESTS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/forge-regression")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/forge-overlay/downloads")
    parser.add_argument("--base-archive", type=Path)
    parser.add_argument("--java", help="Java runtime; defaults to the selected JDK 21 runtime")
    parser.add_argument("--javac", help="Explicit JDK 21 compiler; otherwise discover an installed JDK 21")
    parser.add_argument("--go", default="go")
    args = parser.parse_args()
    for key in ("output", "cache", "base_archive"):
        if value := getattr(args, key):
            setattr(args, key, value.resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"status": "failed", "steps": []}
    started = time.monotonic()
    try:
        if os.name != "posix":
            raise ValueError("Forge CI regression requires POSIX process-group cleanup")
        qualify(args, report)
        report["status"] = "passed"
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        print(f"Forge regression failed: {error}", file=sys.stderr)
        return 1
    finally:
        report["elapsedSeconds"] = round(time.monotonic() - started, 3)
        (args.output / "qualification.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
