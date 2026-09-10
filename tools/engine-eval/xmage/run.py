#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Compile independent XMage probes against an already built, pinned checkout."""

import argparse
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


PIN = "181b465f3667a015592e5102b69b861dfcf69fd9"


def normalize(results, suite, suite_hash, curated_prepare=False):
    """Only the reviewed full cases are eligible for a semantic PASS."""
    indexed = {result["case_id"]: result for result in results}
    cases = []
    for spec in suite["cases"]:
        raw = indexed.get(spec["id"])
        case = {
            "id": spec["id"], "status": "UNVERIFIED", "layer": "fixture",
            "reason": "This scenario was not selected in this execution.",
            "assertionsPassed": 0, "assertionsFailed": 0,
            "setup": "Direct frozen fixture; real TestPlayer engine actions, costs, stack and SBA retained.",
            "observed": {}, "evidence": [],
        }
        if raw:
            case["observed"] = raw["observations"]
            case["evidence"] = ["raw-results.json", "run.log", "commands.json"]
            if raw["junit_success"] and raw["junit_run_count"] == 1 and not raw["junit_ignored_count"] and raw["observations"]:
                case.update(status="PASS", layer="engine", assertionsPassed=len(spec["assertions"]),
                            reason="All frozen semantic assertions executed and passed.")
            else:
                case.update(reason="Execution did not complete all semantic checks; inspect the retained exception before attributing an engine defect.",
                            assertionsFailed=len(raw["failures"]))
            if spec["id"] == "opening":
                case["setup"] = "Real HumanPlayer opening callbacks with 60 Plains per deck; both keep seven."
            elif spec["id"] == "land_priority":
                case["setup"] += " Wrong actor injected through Player.playLand; this is engine ownership/timing, not host authentication."
            elif spec["id"] == "hidden_views":
                case["setup"] = "Distinct named hand/library secrets and public Bears; actual GameSessionPlayer.prepareGameView owner/opponent/spectator objects serialized recursively."
            elif spec["id"] == "commander_tax":
                case["setup"] += " Two initial Plains, actual Murder, strict optional return; W alone unavailable, later third Plains and paid 2W recast."
            elif spec["id"] == "commander_damage":
                case["setup"] += " Fresh noncombat two-damage fixture first; separate fresh game casts commander, sets historical count 19, then normal unblocked attack for two."
            elif spec["id"] == "morph":
                if raw["observations"].get("rule_observable_characteristics_complete") and raw["junit_success"]:
                    case["reason"] = "Frozen Morph flow plus real restricted-mana and zero-mana-value countering effects passed."
                elif (raw["observations"].get("rule_failure") == "morph_rejected_by_ability_free_restricted_mana"
                      and raw["observations"].get("restricted_mana.positive_control_bears_cast_with_jasmine_only")
                      and raw["failures"]):
                    case.update(status="FAIL", layer="engine", assertionsPassed=2, assertionsFailed=1,
                                reason="Face-down Willbender is rejected by Jasmine's mana restriction to ability-free creature spells despite GW restricted mana plus W available. The same real mana ability casts Grizzly Bears in a fresh positive control. Ordinary morph/turn-up/privacy and actual Chalice mana-value-zero countering pass; no upstream rules fix was applied.")
                else:
                    case.update(status="UNVERIFIED", layer="fixture", assertionsPassed=2 if raw["observations"].get("identity_preserved") else 0,
                                reason="Additional rule-observable Morph diagnostics have not all completed; inspect exact failure and positive controls before attribution.")
            if raw["observations"].get("support_gap") == "catalog_missing":
                case.update(status="UNSUPPORTED", layer="engine", assertionsPassed=0, assertionsFailed=0,
                            reason="The pinned shipped card catalog lacks the required named card; mechanic assertions could not run. This is a catalog gap, not evidence that the underlying Prepare semantics passed or failed.")
            if curated_prepare:
                case["setup"] += " Explicit opt-in directly constructs the existing upstream GoblinGlasswright class (SOS 117); the unfinished class remains absent from the unmodified shipped registry."
                if raw["observations"].get("support_gap") == "curated_prepare_copy_missing":
                    case.update(status="UNSUPPORTED", layer="engine", assertionsPassed=0, assertionsFailed=1,
                                reason="Curated existing upstream card class pays 1R and enters prepared, but no prepared Craft with Pride exile copy is created. The missing runtime copy/cast path prevents the frozen lifecycle; this opt-in result does not change default-catalog support.")
        cases.append(case)
    return {
        "schemaVersion": 1, "suiteVersion": suite["suiteVersion"], "suiteSha256": suite_hash,
        "candidate": "XMage curated Prepare" if curated_prepare else "XMage", "source": {"url": "https://github.com/magefree/mage", "revision": PIN, "patches": []},
        "cases": cases,
        "notes": [
            "New independent probes compiled separately; existing engine build caches reused without modifying engine source.",
            "Previous upstream probes are not selected or included in qualification counts.",
            "JVM limited to 2 GiB and two active processors. Diagnostic runtime is not a performance result.",
            "Commander decks are synthetic fixtures; production deck validation and owner-deck coverage are separate.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cases", nargs="*")
    parser.add_argument("--suite", type=Path,
                        default=Path(__file__).parent.parent / "scenarios.json")
    parser.add_argument("--classpath-file", type=Path,
                        help="Explicit UTF-8 Java classpath instead of discovering a standard Surefire report")
    parser.add_argument("--compile-only", action="store_true",
                        help="Compile probes and write commands.json without executing or claiming any scenario")
    parser.add_argument("--curated-prepare", action="store_true",
                        help="Explicit supplemental opt-in to the existing unfinished Prepare class; never changes shipped-catalog results")
    args = parser.parse_args()
    suite_path = args.suite.resolve()
    suite_bytes = suite_path.read_bytes()
    suite = json.loads(suite_bytes)
    if args.curated_prepare and any(case["id"] not in {"prepare_cast", "prepare_source_leaves"} for case in suite["cases"]):
        parser.error("--curated-prepare requires the separate frozen Prepare extension suite")
    checkout = args.checkout.resolve()
    actual_pin = subprocess.check_output(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual_pin != PIN:
        parser.error(f"expected XMage {PIN}, got {actual_pin}")
    classpath = None
    classpath_source = None
    if args.classpath_file:
        classpath = args.classpath_file.read_text().strip()
        classpath_source = str(args.classpath_file.resolve())
    else:
        reports = sorted((checkout / "Mage.Tests/target/surefire-reports").glob("TEST-*.xml"))
        for report in reports:
            try:
                props = ET.parse(report).findall("./properties/property")
            except (ET.ParseError, OSError):
                continue
            classpath = next((prop.attrib.get("value") for prop in props
                              if prop.attrib.get("name") == "java.class.path"), None)
            if classpath:
                classpath_source = str(report)
                break
    if not classpath:
        parser.error("No compiled test classpath found. Run a standard Mage.Tests test or provide --classpath-file; see README.md.")
    for entry in classpath.split(os.pathsep):
        if entry.endswith(".jar") and not Path(entry).exists():
            parser.error(f"compiled classpath entry missing: {entry}")
    for module in ["Mage/target/classes", "Mage.Sets/target/classes", "Mage.Tests/target/test-classes"]:
        if not (checkout / module).is_dir():
            parser.error(f"compiled module missing: {module}")
        if str(checkout / module) not in classpath.split(os.pathsep):
            parser.error(f"classpath does not contain this checkout's compiled module: {module}")
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="run-", dir=args.output.resolve()))
    classes = output / "classes"
    classes.mkdir()
    profile = output / "profile"
    profile.mkdir()
    snapshot = output / "source"
    snapshot.mkdir()
    for source in Path(__file__).parent.iterdir():
        if source.is_file() and source.suffix in {".java", ".py", ".md"}:
            shutil.copy2(source, snapshot / source.name)
    shutil.copy2(suite_path, snapshot / suite_path.name)
    sources = sorted(Path(__file__).parent.glob("*.java"))
    compile_command = [
        "javac", "-J-Xmx2g", "-J-XX:ActiveProcessorCount=2", "-proc:none",
        "--release", "8", "-cp", classpath, "-d", str(classes),
        *map(str, sources),
    ]
    run_command = [
        "java", "-Xmx2g", "-XX:ActiveProcessorCount=2",
        "-Djava.awt.headless=true", "-Dfile.encoding=UTF-8",
        f"-Duser.home={profile}",
        f"-Dhexproof.eval.curatedPrepare={str(args.curated_prepare).lower()}",
        "-Dxmage.dataCollectors.printGameLogs=false",
        f"-Dlog4j.configuration=file:{checkout}/.travis/log4j.properties",
        "-cp", str(classes) + os.pathsep + classpath,
        "org.hexproof.eval.Qualification", str(output / "raw-results.json"),
        *(args.cases or [case["id"] for case in suite["cases"]]),
    ]
    (output / "commands.json").write_text(json.dumps({
        "engine_pin": actual_pin, "compile": compile_command, "run": run_command,
        "cwd": str(checkout / "Mage.Tests"),
        "classpathSource": classpath_source,
        "sourceSnapshot": str(snapshot),
        "note": "Semantic qualification only; elapsed time is not a benchmark.",
        "sourceSha256": {source.name: hashlib.sha256(source.read_bytes()).hexdigest() for source in sources},
        "suiteSha256": hashlib.sha256(suite_bytes).hexdigest(),
        "suitePath": str(suite_path),
        "curatedPrepareExistingClass": args.curated_prepare,
    }, indent=2) + "\n")
    print(output, flush=True)
    with (output / "compile.log").open("w") as log:
        compiled = subprocess.run(compile_command, stdout=log, stderr=subprocess.STDOUT)
    if compiled.returncode:
        print((output / "compile.log").read_text())
        return compiled.returncode
    if args.compile_only:
        print("Compilation succeeded; no qualification scenarios executed.")
        return 0
    with (output / "run.log").open("w") as log:
        try:
            completed = subprocess.run(run_command, cwd=checkout / "Mage.Tests",
                                       stdout=log, stderr=subprocess.STDOUT, timeout=600)
        except subprocess.TimeoutExpired:
            print("Qualification exceeded 600 seconds; see run.log.")
            return 124
    print(f"exit={completed.returncode}; evidence={output / 'raw-results.json'}")
    if (output / "raw-results.json").exists():
        results = json.loads((output / "raw-results.json").read_text())
        (output / "results.json").write_text(json.dumps(
            normalize(results, suite, hashlib.sha256(suite_bytes).hexdigest(), args.curated_prepare), indent=2) + "\n")
        for result in results:
            print(result["case_id"], result["junit_success"],
                  result["failures"][0].get("message", result["failures"][0]["exception"]) if result["failures"] else "")
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
