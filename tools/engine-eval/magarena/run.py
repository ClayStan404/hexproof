#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Rebuild pinned Magarena with declared Ant/JDK 8, then run real test decisions."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PIN = "efa0aba85e681816a92b4938b28741d540384e35"
HERE = Path(__file__).resolve().parent


def command(args, cwd, output, stem, env, timeout=900):
    (output / f"{stem}-command.json").write_text(json.dumps({"argv": args, "cwd": str(cwd),
        "JAVA_HOME": env["JAVA_HOME"], "JAVA_TOOL_OPTIONS": env["JAVA_TOOL_OPTIONS"]}, indent=2) + "\n")
    with (output / f"{stem}.log").open("w") as log:
        result = subprocess.run(args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout, check=False)
    print(stem, result.returncode, flush=True)
    return result.returncode


def normalize(output, suite, code):
    raw = [json.loads(line.removeprefix("HEXPROOF_OBSERVATION "))
           for line in (output / "probe.log").read_text().splitlines() if line.startswith("HEXPROOF_OBSERVATION ")]
    (output / "observations.json").write_text(json.dumps(raw, indent=2) + "\n")
    by_id = {case["id"]: case for case in raw}
    results = []
    for spec in suite["cases"]:
        case = by_id.get(spec["id"], {})
        observed = case.get("observed", {})
        observed["processExit"] = code
        passed = sum(item["passed"] is True for item in case.get("assertions", []))
        failed = sum(item["passed"] is False for item in case.get("assertions", []))
        status = observed.get("statusHint", "PASS" if case else "UNVERIFIED")
        layer = observed.get("layerHint", "engine")
        reason = observed.get("limitation", "All frozen assertions executed through real priority/cost/target/rules decisions")
        if failed:
            status, layer, reason = "FAIL", "engine", case.get("error", "Behavioral assertion failed")
        elif case.get("error"):
            status, layer, reason = "UNVERIFIED", "fixture", case["error"]
        elif status == "PASS" and passed < len(spec["assertions"]):
            status, layer, reason = "UNVERIFIED", "fixture", "Insufficient completed frozen assertions"
        if "HEXPROOF_RUN_COMPLETE" not in (output / "probe.log").read_text() or (code != 0 and not (code == 1 and any(row.get("error") for row in raw))):
            status, layer, reason = "UNVERIFIED", "fixture", "No normal engine/controller cleanup completion marker"
        results.append({"id": spec["id"], "status": status, "layer": layer, "reason": reason,
            "setup": spec["setup"] + " Direct initial setup uses upstream TestGameBuilder; actual choices use public engine event APIs.",
            "assertionsPassed": passed, "assertionsFailed": failed, "observed": observed,
            "evidence": ["observations.json", "probe.log", "Qualification.java"] if case else []})
    result = {"schemaVersion": 1, "suiteVersion": suite["suiteVersion"], "candidate": "Magarena",
        "source": {"url": "https://github.com/magarena/magarena", "revision": PIN, "patches": []},
        "cases": results}
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, required=True)
    parser.add_argument("--skip-upstream-build", action="store_true")
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--suite", choices=["shared", "prepare"], default="shared")
    parser.add_argument("--negative-control", action="store_true", help="Deliberately fail Bolt damage assertion; never qualification evidence")
    args = parser.parse_args()
    source = args.source.resolve()
    if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip() != PIN:
        parser.error("Source revision differs from pinned upstream")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="magarena-run-", dir=args.output.resolve()))
    print(output, flush=True)
    env = os.environ.copy()
    env["JAVA_HOME"] = str(args.java_home.resolve())
    env["PATH"] = str(args.java_home.resolve() / "bin") + os.pathsep + env["PATH"]
    env["JAVA_TOOL_OPTIONS"] = ("-Xmx2g -XX:ActiveProcessorCount=2 -Djava.awt.headless=true "
                                "-Dmagarena.dir=" + str(source / "release"))
    suite_path = HERE.parent / ("extensions.json" if args.suite == "prepare" else "scenarios.json")
    suite = json.loads(suite_path.read_text())
    if set(args.case) - {spec["id"] for spec in suite["cases"]}:
        parser.error("Unknown requested case")
    shutil.copyfile(suite_path, output / suite_path.name)
    shutil.copyfile(HERE / "Qualification.java", output / "Qualification.java")
    (output / "source-diff.patch").write_text(subprocess.check_output(["git", "diff", "--binary"], cwd=source, text=True))
    if command([str(args.java_home.resolve() / "bin/java"), "-version"], source, output, "java-version", env):
        return 2
    if not args.skip_upstream_build and command(["ant", "-f", "build.xml", "jar", "test"], source, output, "upstream", env):
        return 2
    (output / "classes").mkdir()
    classpath = os.pathsep.join([str(source / "build"), str(source / "release/lib/*")])
    if command([str(args.java_home.resolve() / "bin/javac"), "-encoding", "UTF-8", "-cp", classpath, "-d", str(output / "classes"), str(output / "Qualification.java")], source, output, "probe-compile", env):
        return 2
    code = command([str(args.java_home.resolve() / "bin/java"), "-ea", "-Dhexproof.eval.negativeControl=" + str(args.negative_control).lower(), "-Dmagarena.dir=" + str(source / "release"),
        "-cp", str(output / "classes") + os.pathsep + classpath, "magic.model.choice.Qualification", *(args.case or [case["id"] for case in suite["cases"]])], source, output, "probe", env, timeout=180)
    normalize(output, suite, code)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
