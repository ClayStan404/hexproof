#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Compile the test-only controller against an already built pinned Qt5 console engine."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

PIN = "830604d239fb00a6dfbe943664683603ccb64c79"
HERE = Path(__file__).resolve().parent


def save_source_diff(source, target):
    # Diff context can contain upstream CRLF; text mode would corrupt applyable evidence.
    target.write_bytes(subprocess.check_output(["git", "diff", "--binary"], cwd=source))


def observations(log, case, code):
    rows = [json.loads(line.removeprefix("HEXPROOF_OBSERVATION "))
            for line in log.splitlines() if line.startswith("HEXPROOF_OBSERVATION ")]
    if len(rows) != 1 or rows[0].get("id") != case:
        return [{"id": case, "error": f"Executable exited {code}; expected exactly one matching observation, got {len(rows)}", "assertions": [], "observed": {"processExit": code}}]
    row = rows[0]
    row["processExit"] = code
    row.setdefault("observed", {})["processExit"] = code
    if code != 0 and not row.get("error"):
        row["error"] = f"Executable exited {code} after emitting observation; not a completed PASS"
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--suite", choices=["shared", "prepare"], default="shared")
    parser.add_argument("--negative-control", action="store_true", help="Deliberately fail the Bolt damage assertion; never qualification evidence")
    args = parser.parse_args()
    source, build = args.source.resolve(), args.build.resolve()
    if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip() != PIN:
        parser.error("Wrong upstream revision")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="wagic-run-", dir=args.output.resolve()))
    print(output, flush=True)
    profile = output / "profile"
    profile.mkdir()
    primitives = profile / "evaluation-assets"
    primitives.mkdir(parents=True)
    unsupported = (source / "projects/mtg/bin/Res/sets/primitives/unsupported.txt").read_bytes()
    blocks = [block for block in unsupported.split(b"[card]") if b"name=Willbender\n" in block.replace(b"\r\n", b"\n")]
    if len(blocks) != 1:
        parser.error("Expected exactly one unchanged upstream Willbender definition")
    willbender = b"[card]" + blocks[0].split(b"[/card]", 1)[0] + b"[/card]\n"
    (primitives / "willbender-eval.txt").write_bytes(willbender)
    (output / "willbender-original-block.txt").write_bytes(willbender)
    env = os.environ.copy()
    env["WAGIC_EVAL_PROFILE"] = str(profile)
    shutil.copyfile(HERE / "Qualification.cpp", output / "Qualification.cpp")
    shutil.copyfile(HERE / "compatibility.patch", output / "compatibility.patch")
    suite_path = HERE.parent / ("extensions.json" if args.suite == "prepare" else "scenarios.json")
    shutil.copyfile(suite_path, output / suite_path.name)
    save_source_diff(source, output / "source-diff.patch")

    def run(argv, stem, cwd=build, timeout=180):
        (output / f"{stem}-command.json").write_text(json.dumps({"argv": argv, "cwd": str(cwd), "WAGIC_EVAL_PROFILE": str(profile)}, indent=2) + "\n")
        with (output / f"{stem}.log").open("w") as log:
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        print(stem, result.returncode, flush=True)
        return result.returncode

    variables = {}
    for line in (build / "Makefile").read_text().splitlines():
        if "=" in line and not line.startswith("\t"):
            key, value = line.split("=", 1)
            variables[key.strip()] = value.strip()
    flags = shlex.split(variables["CXXFLAGS"].replace("$(DEFINES)", variables["DEFINES"]))
    includes = shlex.split(variables["INCPATH"])
    cpp = str(output / "Qualification.cpp")
    obj = str(output / "Qualification.o")
    define = '-DWAGIC_QT_CONSOLE_SOURCE="' + str(source / "JGE/src/Qtconsole.cpp") + '"'
    if run(["g++", "-c", *flags, *includes, define, "-o", obj, cpp], "compile"):
        return 2
    objects = [str(path) for path in sorted(build.glob("*.o")) if path.name != "Qtconsole.o"]
    binary = str(output / "qualification")
    libraries = variables["LIBS"].replace("$(SUBLIBS)", variables.get("SUBLIBS", ""))
    if run(["g++", "-fPIC", "-o", binary, obj, *objects, *shlex.split(libraries)], "link"):
        return 2
    suite = json.loads(suite_path.read_text())
    raw = []
    selected = args.case or [spec["id"] for spec in suite["cases"]]
    known = {spec["id"] for spec in suite["cases"]} | {"upstream_boosters"}
    if set(selected) - known:
        parser.error("Unknown requested case")
    for case in selected:
        try:
            code = run([binary, case, *( ["negative_control"] if args.negative_control else [])], case, source / "projects/mtg", timeout=90)
            raw.extend(observations((output / f"{case}.log").read_text(), case, code))
        except subprocess.TimeoutExpired as error:
            raw.append({"id": case, "error": str(error), "assertions": [], "observed": {}})
        (output / "observations.json").write_text(json.dumps(raw, indent=2) + "\n")
    by_id = {row["id"]: row for row in raw}
    cases = []
    for spec in suite["cases"]:
        row = by_id.get(spec["id"], {})
        observed = row.get("observed", {})
        passed = sum(item["passed"] is True for item in row.get("assertions", []))
        failed = sum(item["passed"] is False for item in row.get("assertions", []))
        status = observed.get("statusHint", "PASS" if row else "UNVERIFIED")
        layer = observed.get("layerHint", "engine")
        reason = observed.get("limitation", "Real public card-click/interrupt decisions and all frozen behavioral assertions executed")
        if failed: status, reason = "FAIL", row.get("error", observed.get("failureReason", "Behavior assertion failed"))
        elif row.get("error"): status, layer, reason = "UNVERIFIED", "fixture", row["error"]
        elif status == "PASS" and passed < len(spec["assertions"]): status, layer, reason = "UNVERIFIED", "fixture", "Insufficient assertions"
        cases.append({"id": spec["id"], "status": status, "layer": layer, "reason": reason,
            "setup": spec["setup"] + " Direct initial setup uses actual catalog/rule definitions; subsequent actions use public GameObserver input.",
            "assertionsPassed": passed, "assertionsFailed": failed, "observed": observed,
            "evidence": ["observations.json", f"{spec['id']}.log", "Qualification.cpp", "compatibility.patch"] if row else []})
    result = {"schemaVersion": 1, "suiteVersion": suite["suiteVersion"], "candidate": "Wagic",
        "source": {"url": "https://github.com/WagicProject/wagic", "revision": PIN,
                   "patches": ["compatibility.patch: Qt macro namespace, C++11, warnings retained, isolated test profile; no rules repairs"]}, "cases": cases}
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    if any(row.get("error") and not row["error"].startswith("ASSERTION:") for row in raw):
        return 2
    return int(any(item["passed"] is False for row in raw for item in row.get("assertions", [])))


if __name__ == "__main__":
    raise SystemExit(main())
