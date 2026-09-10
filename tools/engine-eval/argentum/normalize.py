#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Normalize retained Argentum observations, not the upstream test success banner."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from run import fixture_payload

PIN = "3f46367d87c88bcf156a843a9e69fd29e1693872"
URL = "https://github.com/wingedsheep/argentum-engine"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--suite", type=Path, default=Path(__file__).resolve().parents[1] / "scenarios.json")
    args = parser.parse_args()
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=args.source, text=True).strip()
    if revision != PIN:
        raise SystemExit(f"Unexpected source revision {revision}")
    dirty = subprocess.check_output(
        ["git", "diff", "--name-only", "HEAD"], cwd=args.source, text=True).strip()
    if dirty:
        raise SystemExit(f"Tracked upstream modifications not permitted: {dirty}")
    suite = json.loads(args.suite.read_text())
    raw = json.loads(args.raw.read_text())
    fixture = Path(__file__).with_name("HexproofQualificationTest.kt").read_bytes()
    test_path, installed_fixture, _ = fixture_payload()
    installed = args.source / test_path
    if installed.read_bytes() != installed_fixture:
        raise SystemExit("Installed downstream fixture differs from tracked evaluator")
    rows = {row["id"]: row for row in raw}
    if len(rows) != len(raw):
        raise SystemExit("Duplicate raw case IDs")
    if not args.log.is_file() or not args.log.stat().st_size:
        raise SystemExit("Missing execution log")
    evidence = [os.path.relpath(p.resolve(), args.output.resolve().parent)
                for p in [args.raw, args.log, args.raw.parent / "fixture.kt", args.raw.parent / "provenance.json"]]
    cases = []
    for spec in suite["cases"]:
        row = rows.get(spec["id"])
        result = {
            "id": spec["id"], "status": "UNVERIFIED", "layer": "fixture",
            "reason": "Not executed in this bounded core/hard-gate probe.",
            "setup": spec["setup"],
            "assertionsPassed": 0, "assertionsFailed": 0,
            "observed": {}, "evidence": evidence,
        }
        if row:
            checks = row["assertions"]
            passed = sum(c["passed"] is True for c in checks)
            failed = sum(c["passed"] is False for c in checks)
            result.update(assertionsPassed=passed, assertionsFailed=failed,
                          observed=row["observed"])
            result["observed"]["assertions"] = checks
            if row.get("error"):
                result["observed"]["exception"] = row["error"]
                result.update(status="UNVERIFIED", layer="unknown",
                              reason="Probe action/setup raised; incomplete assertions require triage.")
            elif failed:
                result.update(status="FAIL", layer="engine",
                              reason="Executed frozen assertion failed; see raw state and assertion names.")
                if spec["id"] == "hidden_views":
                    result.update(layer="adapter", reason=(
                        "ClientStateTransformer emits exact ordered opaque library entity IDs to all views. "
                        "Hidden names/text are not directly serialized. Supplemental real Time Ebb plus "
                        "paid Myr Mindservant shuffle recovers the known public Bears location from "
                        "that stable ID after shuffle. Strict frozen library-order assertion fails."))
                if spec["id"] == "prepare_cast":
                    result["reason"] = (
                        "Legal-action enumeration correctly excludes the Prepare sorcery in hand, "
                        "but direct same-owner CastSpell(faceIndex=0) is accepted by ActionProcessor, "
                        "pays R, stacks Craft with Pride and resolves a Treasure without preparing "
                        "the creature first. The isolated normal 1R creature / R prepared-copy "
                        "lifecycle passes the other three frozen assertion groups. This is a "
                        "native action-admission validation gap, not a missing Prepare mechanism.")
            elif passed == len(spec["assertions"]):
                result.update(status="PASS", layer="engine",
                              reason="Exact fixture and all frozen assertions executed through real engine actions.")
            else:
                result["reason"] = "Only some frozen assertions executed."
            result["setup"] += (
                " Production MtgSetCatalog definitions, not simplified TestCards overrides. Missing "
                "Lovestruck Beast, Bala Ged Recovery and Soul's Fire use explicitly disclosed "
                "downstream printed-data DSL fixtures and existing native mechanisms. "
                "Except opening: direct empty-hand/30-Plains-library precombat-main fixtures, then "
                "upstream fixture card placement. Costs/legality/targeting/SBA remain enabled; "
                "actions use GameTestDriver -> ActionProcessor. Hidden case uses named secret "
                "hands/libraries and actual ClientStateTransformer spectator mode.")
            if spec["id"] in {"adventure", "modal_dfc", "commander_damage"} and result["status"] == "PASS":
                result["reason"] = "Native mechanism passes the full frozen behavior using explicitly supplied printed card-data fixtures for missing catalog entries; not bundled-card coverage."
        cases.append(result)
    output = {
        "schemaVersion": 1, "suiteVersion": suite["suiteVersion"],
        "candidate": "Argentum", "source": {
            "url": URL, "revision": revision,
            "patches": ["Added downstream HexproofQualificationTest.kt to test sources only; no engine/card changes."]
        }, "cases": cases,
        "evaluator": {"fixtureSha256": hashlib.sha256(fixture).hexdigest()},
        "supplemental": [row for row in raw if row["id"].startswith("supplemental_")],
        "notes": [
            "Upstream seven MultiplayerSmokeTest passes are supplemental, not canonical passes.",
            "Gradle's single wrapper-test PASS means observation collection completed; individual assertion status is normalized here.",
            "Runtime core/view tests do not certify the WebSocket server, event stream, or Hexproof integration.",
            "Lovestruck Beast, Bala Ged Recovery and Soul's Fire are absent from the bundled catalog; the downstream fixture supplies their printed SDK data without implementing or repairing engine rules.",
            "Diagnostic execution used JDK 21, declared Gradle 9.6.1 wrapper, 2 GiB Gradle/Kotlin heaps and max two workers; not a performance measurement.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
