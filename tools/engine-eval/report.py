#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Validate evidence-bearing qualification results and print a non-ranking matrix."""

import argparse
import json
from pathlib import Path
import re
import sys

STATUSES = {"PASS", "FAIL", "UNSUPPORTED", "UNVERIFIED", "BLOCKED"}
LAYERS = {"engine", "adapter", "fixture", "build", "unknown"}
SUITE_PATH = Path(__file__).with_name("scenarios.json")


def validate_result(result, suite, directory=None):
    """Validate evidence structure, not the truth of an arbitrary producer's claim."""
    errors = []
    if not isinstance(result, dict):
        return ["result must be an object"]
    if result.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    if result.get("suiteVersion") != suite["suiteVersion"]:
        errors.append("suiteVersion differs from frozen suite")
    if not isinstance(result.get("candidate"), str) or not result["candidate"].strip():
        errors.append("candidate must be a nonempty name")
    source = result.get("source", {})
    if not isinstance(source, dict):
        source = {}
    if not isinstance(source.get("url"), str) or not source["url"].startswith("https://"):
        errors.append("source.url must identify the upstream HTTPS repository")
    if not re.fullmatch(r"[0-9a-f]{40}", str(source.get("revision", ""))):
        errors.append("source.revision must be an immutable full Git revision")
    if not isinstance(source.get("patches"), list):
        errors.append("source.patches must explicitly disclose a list (possibly empty)")
    cases = result.get("cases")
    if not isinstance(cases, list):
        return errors + ["cases must be a list"]
    known = {case["id"]: case for case in suite["cases"]}
    seen = set()
    for case in cases:
        if not isinstance(case, dict):
            errors.append("case must be an object")
            continue
        case_id = case.get("id")
        if not isinstance(case_id, str) or case_id not in known:
            errors.append(f"unknown case id: {case_id!r}")
            continue
        if case_id in seen:
            errors.append(f"{case_id}: duplicate case")
        seen.add(case_id)
        status = case.get("status")
        if status not in STATUSES:
            errors.append(f"{case_id}: invalid status")
        if case.get("layer") not in LAYERS:
            errors.append(f"{case_id}: invalid root-cause layer")
        for field in ("reason", "setup"):
            if not isinstance(case.get(field), str) or not case[field].strip():
                errors.append(f"{case_id}: missing {field}")
        counts_valid = True
        for field in ("assertionsPassed", "assertionsFailed"):
            if type(case.get(field)) is not int or case[field] < 0:
                errors.append(f"{case_id}: {field} must be a nonnegative integer")
                counts_valid = False
        evidence = case.get("evidence", [])
        if not isinstance(evidence, list) or any(not isinstance(p, str) or not p for p in evidence):
            errors.append(f"{case_id}: evidence must be a list of paths")
            evidence = []
        if status in {"PASS", "FAIL", "UNSUPPORTED", "BLOCKED"} and not evidence:
            errors.append(f"{case_id}: {status} requires evidence")
        if directory is not None:
            for item in evidence:
                path = directory / item
                if not path.is_file() or not path.stat().st_size:
                    errors.append(f"{case_id}: missing or empty evidence: {item}")
        if status == "PASS":
            if counts_valid and (case["assertionsPassed"] < len(known[case_id]["assertions"])
                                 or case["assertionsFailed"] != 0):
                errors.append(f"{case_id}: PASS needs all frozen assertions, no failures")
            if not isinstance(case.get("observed"), (dict, list)) or not case["observed"]:
                errors.append(f"{case_id}: PASS needs actual observations")
        if status == "FAIL" and counts_valid and case["assertionsFailed"] < 1:
            errors.append(f"{case_id}: FAIL needs a failed assertion")
    return errors


def matrix(results, suite):
    names = [result["candidate"] for result in results]
    lines = ["| Scenario | " + " | ".join(names) + " |",
             "|---|" + "---|" * len(names)]
    by_engine = [{case["id"]: case for case in result["cases"]} for result in results]
    for case in suite["cases"]:
        statuses = [engine.get(case["id"], {}).get("status", "UNVERIFIED") for engine in by_engine]
        lines.append("| " + case["id"] + " | " + " | ".join(statuses) + " |")
    lines.extend(["", "Missing cases are UNVERIFIED, never implicit passes.",
                  "This matrix is qualification evidence, not a performance ranking or final selection."])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", nargs="+", type=Path)
    parser.add_argument("--suite", type=Path, default=SUITE_PATH)
    parser.add_argument("--require-complete", action="store_true",
                        help="exit 1 if any scenario is not PASS; default allows honest partial reports")
    args = parser.parse_args()
    try:
        suite = json.loads(args.suite.read_text())
        results = []
        for path in args.results:
            result = json.loads(path.read_text())
            errors = validate_result(result, suite, path.resolve().parent)
            if errors:
                print(f"{path}:\n  " + "\n  ".join(errors), file=sys.stderr)
                return 2
            if any(previous["candidate"] == result["candidate"] for previous in results):
                print("Duplicate candidate: keep separate revisions/reruns in separate reports", file=sys.stderr)
                return 2
            results.append(result)
        print(matrix(results, suite), end="")
        if args.require_complete:
            ids = {case["id"] for case in suite["cases"]}
            if any({case["id"] for case in result["cases"] if case["status"] == "PASS"} != ids
                   for result in results):
                return 1
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"Invalid evaluation input: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
