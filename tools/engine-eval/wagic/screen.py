#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Record pinned Wagic structural screening evidence without runtime claims."""

import argparse
import json
import os
from pathlib import Path
import subprocess

PIN = "830604d239fb00a6dfbe943664683603ccb64c79"


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
        "projects/mtg/src/Rules.cpp": ["void Rules::initPlayers", "g->getPlayersNumber() < 2"],
        "projects/mtg/src/Player.cpp": [
            "return this == observer->players[0] ? observer->players[1] : observer->players[0];",
            "out << *(p.game);",
        ],
        "projects/mtg/src/GameObserver.cpp": [
            "void NetworkGameObserver::synchronize()", 'sendCommand("synchronize", out.str())',
            'for (int i = 0; i < 2 ; ++i)',
        ],
        "projects/mtg/src/MTGGameZones.cpp": [
            'out << "library=";', 'out << "hand=";', 'out << z.cards[i]->getMTGId();',
        ],
    }.items():
        # Upstream legacy source contains non-UTF-8 comments; searched evidence is ASCII.
        lines = (root / relative).read_text(encoding="latin-1").splitlines()
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
                reason="Pinned player initialization, opponent selection, SBA, and cleanup assume two players.",
                observed={"evidenceKind": "source_inspection", "excerpts": excerpts},
                evidence=[os.path.relpath(root / "projects/mtg/src/Rules.cpp", args.output.resolve().parent),
                          os.path.relpath(root / "projects/mtg/src/Player.cpp", args.output.resolve().parent)])
    hidden = next(case for case in cases if case["id"] == "hidden_views")
    hidden.update(status="UNSUPPORTED", layer="adapter",
                  reason="Existing NetworkGameObserver serializes both hands and libraries as card IDs. A new host projection could address this; no runtime network test executed.",
                  observed={"evidenceKind": "source_inspection", "excerpts": excerpts},
                  evidence=[os.path.relpath(root / "projects/mtg/src/GameObserver.cpp", args.output.resolve().parent),
                            os.path.relpath(root / "projects/mtg/src/MTGGameZones.cpp", args.output.resolve().parent)])
    report = {
        "schemaVersion": 1, "suiteVersion": suite["suiteVersion"], "candidate": "wagic",
        "source": {"url": "https://github.com/WagicProject/wagic", "revision": PIN, "patches": []},
        "cases": cases,
        "engine": "wagic", "engine_pin": PIN,
        "evidence_kind": "source_inspection", "runtime_cases_executed": 0,
        "hard_gates": {
            "four_players": {"status": "unsupported", "reason":
                "Rules initialization and opponent/cleanup paths assume exactly two players."},
            "external_human_decisions": {"status": "not_tested", "reason":
                "Human input and NetworkGameObserver exist; no runtime adapter was qualified."},
            "hidden_view_separation": {"status": "unsupported", "reason":
                "The inspected network synchronization serializes full hand/library card IDs."},
        },
        "source_evidence": excerpts,
        "recordedEvaluationBuild": {"date": "2026-09-09", "status": "BLOCKED", "configure_exit": 0, "compile_exit": 2,
                  "reason": "Installed Qt 6/GCC 16 incompatible with declared legacy Qt console target.",
                  "diagnostics": ["QT_CONFIG redefined", "QMediaPlaylist missing", "filesystem ambiguity"],
                  "test_cases_executed": 0, "note": "Historical local observation; this screening command does not rebuild."},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
