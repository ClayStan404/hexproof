#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Run the bounded, pinned Argentum downstream qualification fixture."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import signal

PIN = "3f46367d87c88bcf156a843a9e69fd29e1693872"
TEST_PATH = Path("rules-engine/src/test/kotlin/com/wingedsheep/engine/evaluation/HexproofQualificationTest.kt")


def fixture_payload():
    original = Path(__file__).with_name("HexproofQualificationTest.kt").read_bytes()
    name = "HexproofQualification" + hashlib.sha256(original).hexdigest()[:12] + "Test"
    return TEST_PATH.with_name(name + ".kt"), original.replace(b"class HexproofQualificationTest", ("class " + name).encode()), name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--cache-dir", type=Path, help="Reuse an isolated declared Gradle dependency cache")
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output_directory.resolve()
    if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip() != PIN:
        raise SystemExit("Source pin mismatch")
    if subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=source, text=True).strip():
        raise SystemExit("Unexpected tracked upstream modifications")
    output.mkdir(parents=True, exist_ok=True)
    raw = output / "observations.json"
    log = output / "execution.log"
    if raw.exists() or log.exists():
        raise SystemExit("Use a fresh output directory; previous evidence must not be overwritten")
    test_path, fixture, test_name = fixture_payload()
    installed = source / test_path
    if installed.exists() and installed.read_bytes() != fixture:
        raise SystemExit(f"Refusing to replace existing test source {installed}")
    installed.parent.mkdir(parents=True, exist_ok=True)
    # Gradle compiles every test source, even when --tests selects one class.
    # Archive only this laboratory's previous clearly identified fixtures;
    # otherwise a preserved compile-error iteration would break all later runs.
    for previous in installed.parent.glob("HexproofQualification*Test.kt"):
        if previous == installed:
            continue
        if b"SPDX-FileCopyrightText: 2026 Hexproof contributors" not in previous.read_bytes()[:250]:
            raise SystemExit(f"Unrecognized existing test source: {previous}")
        archive = output / "previous-fixtures"
        archive.mkdir(exist_ok=True)
        previous.rename(archive / previous.name)
    installed.write_bytes(fixture)
    (output / "fixture.kt").write_bytes(fixture)
    env = dict(os.environ)
    env.update(
        GRADLE_USER_HOME=str(args.cache_dir.resolve() if args.cache_dir else source.parent / "argentum-gradle-cache"),
        GRADLE_LOCK_FILE=str(output.parent / "argentum-gradle.lock"),
        HEXPROOF_ARGENTUM_OUTPUT=str(raw),
    )
    command = [
        "scripts/gradle-locked", ":rules-engine:test", "--rerun", "--tests", "*" + test_name,
        "--max-workers=2", "-PkotlinCompileParallelism=1",
        "-Pkotlin.daemon.jvmargs=-Xmx2g -XX:ActiveProcessorCount=2",
        "-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m -XX:ActiveProcessorCount=2",
        "--no-daemon", "--console=plain",
    ]
    (output / "provenance.json").write_text(json.dumps({"pin":PIN,"command":command,"fixture":str(installed),"cache":env["GRADLE_USER_HOME"],"patches":"content-addressed downstream test only; engine and card sources unchanged"},indent=2)+"\n")
    # just is absent on the evaluation host; this is the declared recipe's script.
    with log.open("w") as stream:
        stream.write("Command: " + repr(command) + "\n")
        stream.flush()
        try:
            process = subprocess.Popen(command, cwd=source, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            code = process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL)
                process.wait()
            stream.write("\nTIMEOUT after 900 seconds; owned process group stopped.\n")
            raise SystemExit(124)
    if code:
        raise SystemExit(code)
    subprocess.run([
        sys.executable, str(Path(__file__).with_name("normalize.py")),
        "--source", str(source), "--raw", str(raw), "--log", str(log),
        "--output", str(output / "results.json"),
    ], check=True)
    # Keep the clearly identified downstream test with the artifact checkout.
    # It is disclosed in source.patches and never copied into production.


if __name__ == "__main__":
    main()
