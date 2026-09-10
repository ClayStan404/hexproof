#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Count actual JUnit/TRX outcomes; never translate upstream counts into shared-case passes."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def local_name(node):
    return node.tag.rsplit("}", 1)[-1]


def diagnostics(node):
    """Empty XML elements may carry the only failure reason in attributes."""
    parts = [node.attrib[key] for key in ("message", "type") if node.attrib.get(key)]
    parts.extend(text.strip() for text in node.itertext() if text.strip())
    return " ".join(parts)


def inspect(path):
    payload = path.read_bytes()
    root = ET.fromstring(payload)
    cases = []
    summary = {}
    if local_name(root) == "TestRun":
        summary = {"outcome": None, "counters": {}, "diagnostics": []}
        for value in root.iter():
            tag = local_name(value)
            if tag == "ResultSummary":
                summary["outcome"] = value.attrib.get("outcome", "Unknown")
            elif tag == "Counters":
                summary["counters"] = dict(value.attrib)
            elif tag == "RunInfo":
                summary["diagnostics"].append({"outcome": value.attrib.get("outcome", "Unknown"),
                                               "text": diagnostics(value)})
            if tag != "UnitTestResult":
                continue
            outcome = value.attrib.get("outcome", "Unknown")
            cases.append({"name": value.attrib.get("testName"), "outcome": outcome,
                          "diagnostics": diagnostics(value) if outcome != "Passed" else ""})
    elif local_name(root) in {"testsuite", "testsuites", "testcase"}:
        summary = {"suites": [], "diagnostics": []}
        for value in root.iter():
            tag = local_name(value)
            if tag in {"testsuite", "testsuites"}:
                summary["suites"].append(dict(value.attrib))
                for child in value:
                    if local_name(child) in {"failure", "error"}:
                        summary["diagnostics"].append({"outcome": "Failed", "text": diagnostics(child)})
            if tag != "testcase":
                continue
            children = {local_name(child) for child in value}
            outcome = "Failed" if children & {"failure", "error"} else "NotExecuted" if "skipped" in children else "Passed"
            detail = " ".join(diagnostics(child) for child in value if local_name(child) in {"failure", "error", "skipped"})
            cases.append({"name": value.attrib.get("classname", "") + "." + value.attrib.get("name", ""),
                          "outcome": outcome, "diagnostics": detail if outcome != "Passed" else ""})
    else:
        raise ValueError(f"Not a JUnit/TRX report: {path}")
    if not cases:
        raise ValueError(f"No actual test result entries in {path}")
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(payload).hexdigest(),
            "counts": dict(Counter(case["outcome"] for case in cases)),
            "nonPassing": [case for case in cases if case["outcome"] != "Passed"],
            "frameworkSummary": summary}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--glob", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    paths = sorted(args.root.glob(args.glob))
    if not paths:
        parser.error("No reports matched")
    reports = [inspect(path) for path in paths]
    totals = Counter()
    for report in reports:
        totals.update(report["counts"])
    result = {"scope": "Upstream test framework outcomes, not the frozen shared scenario matrix",
              "note": "Counts use actual result entries only; framework-level failures, incomplete runs and diagnostics are retained separately and must not be read as a successful complete run.",
              "totals": dict(totals), "reports": reports}
    with args.output.open("x") as output:
        json.dump(result, output, indent=2)
        output.write("\n")
    print(json.dumps(result["totals"]))


if __name__ == "__main__":
    main()
