#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Revalidate OS input and natural game evidence for every planned case."""

import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

SPEC = importlib.util.spec_from_file_location("native_runner", Path(__file__).with_name("run-native.py"))
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)
REQUIRED = dict.fromkeys(["standard", "pioneer", "modern", "legacy", "set_sealed", "set_draft", "cube_draft"], 10)


def inspect(run):
    report = json.loads((run / "report.json").read_text())
    if report.get("status") != "passed":
        errors = []
        for path in run.glob("seat-*/artifacts/result.json"):
            result = json.loads(path.read_text())
            if result.get("error"):
                errors.append(result["error"])
        return {"status": "failed", "reason": "; ".join(dict.fromkeys(errors)) or report.get("reason")}
    games, actions, seats = [], Counter(), []
    for seat in report["seats"]:
        artifacts = Path(seat["artifacts"])
        result = RUNNER.seat_result(SimpleNamespace(poll=lambda: seat["exitCode"]), artifacts,
                                   expected_evidence="system-input")
        if result["status"] != "passed":
            return {"status": "failed", "reason": result["reason"]}
        summary = json.loads((artifacts / "audit-summary.json").read_text())
        actions.update(json.loads(line)["action"] for line in (artifacts / "actions.jsonl").read_text().splitlines())
        state = result["scenarioResult"]
        if state.get("scenario") == "forge-duel-match":
            terminal = state.get("result", {})
            if (state.get("gameOver") is not True or state.get("winnerSeat") not in [0, 1]
                    or terminal.get("matchFinished") is not True or terminal.get("concededSeat") != -1
                    or state.get("roomAndDeckSetup") != "production-controls"):
                return {"status": "failed", "reason": "Missing a natural match with production UI setup"}
            games.append({"gameId": state["gameId"], "winnerSeat": state["winnerSeat"], "turn": state["turn"]})
            seats.append({"seat": state["seat"], "castAttempts": state["casts"], "attacks": state["attacks"],
                          "blocks": state["blocks"], "payments": state["payments"],
                          "decisionKinds": state["kinds"], "inputs": summary["inputs"],
                          "attemptedCards": state.get("formatReview", {}).get("seen", [])})
    if len(games) != 2 or games[0] != games[1]:
        return {"status": "failed", "reason": "Both player views must agree on the final natural game"}
    return {"status": "passed", "game": games[0], "actions": dict(actions), "seats": seats,
            "durationSeconds": report["durationSeconds"]}


def report(root):
    plan = json.loads((root / "plan.json").read_text())
    runs = plan["runs"]
    if (plan.get("requiredRuns") != 70 or plan.get("requiredInput") != "system-input"
            or Counter(case["format"] for case in runs) != REQUIRED
            or len({case["id"] for case in runs}) != 70):
        raise ValueError("Campaign requires 70 unique cases, ten per requested format, using system input")
    cases = []
    expected, passed, actions = Counter(), Counter(), Counter()
    for case in plan["runs"]:
        expected[case["format"]] += 1
        attempts = []
        for path in sorted(root.glob(case["id"] + "-*/report.json")):
            attempts.append(dict(inspect(path.parent), path=str(path.parent)))
        accepted = next((a for a in reversed(attempts) if a["status"] == "passed"), None)
        if accepted:
            passed[case["format"]] += 1
            actions.update(accepted["actions"])
        cases.append(dict(case, status="passed" if accepted else "pending", accepted=accepted, attempts=attempts))
    complete = len(cases) == plan["requiredRuns"] and all(c["status"] == "passed" for c in cases)
    summary = {"status": "complete" if complete else "in-progress", "required": dict(expected),
               "passed": dict(passed), "completedGames": sum(passed.values()),
               "actions": dict(actions), "cases": cases}
    RUNNER.write_json(root / "campaign-report.json", summary)
    lines = ["# System-input campaign", "", f"Status: **{summary['status']}**. Natural games: **{sum(passed.values())} / {len(cases)}**.",
             "", "| Format | Required | Passed |", "| --- | ---: | ---: |"]
    lines += [f"| {format_name} | {count} | {passed[format_name]} |" for format_name, count in expected.items()]
    lines += ["", "Each counted game has two agreeing natural results and revalidated owned-window system input.",
              "The bounded play policy does not establish every ability or competitive strategy.", "", "| Case | Deck | Result | Evidence |", "| --- | --- | --- | --- |"]
    for case in cases:
        evidence = case["accepted"]["path"] if case["accepted"] else case["attempts"][-1]["path"] if case["attempts"] else ""
        deck = f"[{case['deck']}]({case['source']})" if "deck" in case else case["format"]
        lines.append(f"| {case['id']} | {deck} | {case['status']} | {evidence} |")
    (root / "campaign-report.md").write_text("\n".join(lines) + "\n")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    result = report(args.root.resolve())
    print(json.dumps({key: result[key] for key in ["status", "completedGames", "passed", "actions"]}))
    return 1 if args.require_complete and result["status"] != "complete" else 0


if __name__ == "__main__":
    raise SystemExit(main())
