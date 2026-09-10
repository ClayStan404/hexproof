#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Run fresh Forge qualification fixtures against the pinned downstream runtime."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import shutil
import os

FORGE_PIN = "753b3dd544d6f02061d796ff7a0b54806631edcb"
JAR_HASH = "b6945da0eb250eea66208a6064b29cdc64434a52d0e4a710c74b3698e9363d1e"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--negative-control", action="store_true",
                        help="intentionally expect Bolt to deal four damage; runner must return failure")
    parser.add_argument("--authority-helper", type=Path,
                        help="Built apps/server/cmd/engine-eval-authority; completes the joint host/engine actor case")
    parser.add_argument("--extensions", action="store_true", help="Run the separately frozen Prepare suite")
    args = parser.parse_args()
    if args.negative_control and args.extensions:
        parser.error("the Bolt negative control belongs to the baseline suite, not Prepare")
    runtime = args.runtime.resolve()
    jar = runtime / "forge-harness.jar"
    jar_hash = hashlib.sha256(jar.read_bytes()).hexdigest()
    if jar_hash != JAR_HASH:
        parser.error("runtime JAR differs from the frozen patch2 qualification artifact")
    if f"FORGE_REVISION={FORGE_PIN}" not in (runtime / "VERSIONS.env").read_text():
        parser.error("Forge revision mismatch")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="negative-" if args.negative_control else "run-",
                                   dir=args.output.resolve()))
    classes = output / "classes"
    classes.mkdir()
    profile = output / "profile"
    profile.mkdir()
    source = Path(__file__).with_name("Qualification.java").resolve()
    shutil.copy2(source, output / "Qualification.java")
    suite_path = Path(__file__).parents[1] / ("extensions.json" if args.extensions else "scenarios.json")
    shutil.copy2(suite_path, output / "scenarios.json")
    compile_command = ["javac", "-J-Xmx2g", "-J-XX:ActiveProcessorCount=2", "-cp", str(jar),
                       "-d", str(classes), str(source)]
    run_command = ["java", "-Xmx2g", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true",
                   f"-Duser.home={profile}", "-cp", f"{classes}:{jar}", "Qualification",
                   str(runtime / "forge-gui") + "/", str(output)]
    env = os.environ.copy()
    env.pop("HEXPROOF_EVAL_AUTHORITY_HELPER", None)
    helper_provenance = None
    if args.authority_helper:
        helper = args.authority_helper.resolve()
        env["HEXPROOF_EVAL_AUTHORITY_HELPER"] = str(helper)
        helper_provenance = {"path": str(helper), "sha256": hashlib.sha256(helper.read_bytes()).hexdigest()}
        shutil.copy2(Path(__file__).resolve().parents[3] / "apps/server/cmd/engine-eval-authority/main.go", output / "authority-main.go")
    if args.negative_control:
        run_command.append("--negative-control")
    if args.extensions:
        run_command.append("--extensions")
    (output / "commands.json").write_text(json.dumps({
        "compile": compile_command, "run": run_command, "cwd": str(output),
        "probeSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "jarSha256": jar_hash, "negativeControl": args.negative_control,
        "authorityHelper": helper_provenance,
        "note": "Parallel semantic qualification; not comparative performance data.",
    }, indent=2) + "\n")
    print(output, flush=True)
    with (output / "compile.log").open("w") as log:
        compiled = subprocess.run(compile_command, stdout=log, stderr=subprocess.STDOUT, timeout=120)
    if compiled.returncode:
        print((output / "compile.log").read_text())
        return compiled.returncode
    with (output / "run.log").open("w") as log:
        try:
            ran = subprocess.run(run_command, cwd=output, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        except subprocess.TimeoutExpired:
            print("Runtime timeout: retained partial raw results and run.log")
            return 124
    if ran.returncode or not (output / "raw-results.json").exists():
        print(f"Probe failed to produce complete results; see {output / 'run.log'}")
        return ran.returncode or 1
    suite = json.loads(suite_path.read_text())
    cases = json.loads((output / "raw-results.json").read_text())
    result = {
        "schemaVersion": 1, "suiteVersion": suite["suiteVersion"], "candidate": "Forge Java patch2",
        "source": {"url": "https://github.com/Card-Forge/forge", "revision": FORGE_PIN,
                   "patches": [{"hostRevision": "143a6b556ac365cea97929ffcebb48eed03ecde8",
                                "downstreamPatchRevision": 2, "jarSha256": jar_hash}]},
        "cases": cases, "negativeControl": args.negative_control,
        "notes": ["Existing Hexproof adapter advantage explicitly included; not bare upstream Forge.",
                  "Missing cases remain unverified; prior synthetic live games are separate evidence."],
    }
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    for case in cases:
        print(case["id"], case["status"], case["assertionsPassed"], case["reason"])
    return int(any(case["status"] == "FAIL" for case in cases))


if __name__ == "__main__":
    raise SystemExit(main())
