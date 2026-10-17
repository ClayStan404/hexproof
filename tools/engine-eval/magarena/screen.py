#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Record pinned Magarena structural screening evidence without runtime claims."""

import argparse
import json
import os
from pathlib import Path
import subprocess

PIN = "efa0aba85e681816a92b4938b28741d540384e35"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = args.checkout.resolve()
    actual = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if actual != PIN:
        parser.error(f"expected {PIN}, got {actual}")
    excerpts = []
    for relative, needles in {
        "src/magic/model/MagicDuel.java": ["new MagicPlayer[]{player,opponent}"],
        "src/magic/model/MagicGame.java": [
            "return Arrays.asList(turnPlayer, turnPlayer.getOpponent());",
            "return players[1-player.getIndex()];",
            "return losingPlayer.isValid() || mainPhaseCount <= 0;",
            "public boolean advanceToNextEventWithChoice()",
            "public void executeNextEvent(final Object[] choiceResults)",
            "getOpponent(scorePlayer).setHandToUnknown();",
        ],
    }.items():
        lines = (root / relative).read_text().splitlines()
        for needle in needles:
            hits = [(n, line) for n, line in enumerate(lines, 1) if needle in line]
            if not hits:
                raise ValueError(f"screening evidence absent: {relative}: {needle}")
            for line_number, line in hits:
                excerpts.append({"path": relative, "line": line_number,
                                 "excerpt": line.strip()})
    suite = json.loads((Path(__file__).resolve().parents[1] / "scenarios.json").read_text())
    cases = [{"id": case["id"], "status": "UNVERIFIED", "layer": "fixture",
              "reason": "No runtime fixture executed after the four-player source gate failed.",
              "setup": "Pinned-source screening only.", "assertionsPassed": 0, "assertionsFailed": 0,
              "observed": {}, "evidence": []} for case in suite["cases"]]
    four = next(case for case in cases if case["id"] == "four_player_departure")
    four.update(status="UNSUPPORTED", layer="engine",
                reason="Pinned duel construction, APNAP, opponent indexing, and termination assume two players.",
                observed={"evidenceKind": "source_inspection", "excerpts": excerpts},
                evidence=[os.path.relpath(root / "src/magic/model/MagicGame.java", args.output.resolve().parent),
                          os.path.relpath(root / "src/magic/model/MagicDuel.java", args.output.resolve().parent)])
    report = {
        "schemaVersion": 1, "suiteVersion": suite["suiteVersion"], "candidate": "magarena",
        "source": {"url": "https://github.com/magarena/magarena", "revision": PIN, "patches": []},
        "cases": cases,
        "engine": "magarena", "engine_pin": PIN,
        "evidence_kind": "source_inspection", "runtime_cases_executed": 0,
        "hard_gates": {
            "four_players": {"status": "unsupported", "reason":
                "Duel construction, opponent indexing, APNAP, and termination assume two players."},
            "external_human_decisions": {"status": "not_tested", "reason":
                "Public event-choice methods found; no qualified runtime adapter."},
            "hidden_view_separation": {"status": "not_tested", "reason":
                "AI copy masking is not evidence of a serialized spectator projection."},
        },
        "source_evidence": excerpts,
        "recordedEvaluationBuild": {"date": "2026-09-09", "status": "BLOCKED", "command": "make -j2 release/Magarena.jar",
                  "reason": "Declared Ant executable absent from evaluation environment.",
                  "test_cases_executed": 0, "note": "Historical local observation; this screening command does not rebuild."},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
