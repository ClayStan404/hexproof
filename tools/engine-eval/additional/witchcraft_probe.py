#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Independent source-build diagnostics for Witchcraft's public Game/observation API."""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import traceback

PIN = "6b703960979b801882db8bf054ac125aed1811f6"
DATA_SHA256 = "445ff5587474bc5a0f1456905601f41c5d4eb741721ea7eb5bae5a39c4383ecc"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip() == PIN
    assert hashlib.sha256((checkout / "mtg-data.tar.gz").read_bytes()).hexdigest() == DATA_SHA256
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="independent-", dir=args.output.resolve()))
    (output / "probe.py").write_bytes(Path(__file__).read_bytes())
    runtime = output / "runtime"
    runtime.mkdir()
    os.environ.update(TMPDIR=str(runtime), MTG_NO_NATIVE="1", MTG_NO_INPROC="1", OMP_NUM_THREADS="2")
    tempfile.tempdir = str(runtime)
    sys.path[:0] = [str(checkout / "packages"), str(checkout)]
    import mtg

    observed = {}
    results = []

    def opening():
        from mtg.engine import game as setup
        keeps = []
        def keep(state, key, options, default):
            if key == "mulligan":
                keeps.append({"key": key, "handCounts": {p: len([c for pp,c in state["in_hand"] if pp == p]) for p in ["alice","bob"]}})
                return True
            return default
        decks = {"alice": ["Plains"]*60, "bob": ["Plains"]*60}
        initial = setup.new_game(decks, variant="two-player", seed=42)
        observed["beforeFirstTurnHands"] = [len([c for owner,c in initial["in_hand"] if owner == p]) for p in ["alice","bob"]]
        observed["openingDecisionScope"] = "Native default keep; supplied Game policies are installed only after mulligan and receive zero opening callbacks"
        g = mtg.Game(decks, variant="two-player", seed=42,
                     policies={"alice":keep,"bob":keep}, explicit_lands=True, instant_speed=True)
        observed.update(keeps=keeps, life=g.life(), actor=g.turn, step=sorted(g.state["current_step"]),
                        hands=[len(g.hand(p)) for p in ["alice","bob"]],
                        libraries=[g.library_size(p) for p in ["alice","bob"]],
                        legalCount=len(g.legal_moves))
        # instant_speed permits an upkeep window; pass until the first actual main phase.
        for _ in range(10):
            if g.state["current_step"] == {("precombat_main",)}:
                break
            g.push(next(m for m in g.legal_moves if m.kind == "pass"))
        observed.update(step=sorted(g.state["current_step"]), hands=[len(g.hand(p)) for p in ["alice","bob"]],
                        libraries=[g.library_size(p) for p in ["alice","bob"]])
        assert observed["beforeFirstTurnHands"] == [7,7]
        assert observed["life"] == {"alice":20,"bob":20}
        assert observed["step"] == [("precombat_main",)]
        assert observed["hands"] == [7,7] and observed["libraries"] == [53,53], "Starting player must skip first draw in two-player Magic"

    def hidden_library():
        g = mtg.Game({"alice":["Plains"]*59+["Lightning Bolt"], "bob":["Island"]*59+["Counterspell"]},
                     variant="two-player", seed=42, explicit_lands=True,
                     starting_hand={"alice":["Lightning Bolt"], "bob":["Counterspell"]})
        library_ids = {c for p,c in g.state["in_library"]}
        hand_ids = {p:set(g.hand(p)) for p in ["alice","bob"]}
        observed["views"] = []
        for viewer in ["alice","bob","spectator"]:
            view = g.observation(viewer)
            encoded = view.serialize()
            (output / f"view-{viewer}.json").write_text(encoded + "\n")
            leaks = sorted(c for c in library_ids if json.dumps(c) in encoded)
            opposing = sorted(c for p,ids in hand_ids.items() if p != viewer for c in ids if json.dumps(c) in encoded)
            observed["views"].append({"viewer":viewer, "exposedLibraryIds":leaks,
                                      "opposingHandIds":opposing, "visibleOwnHand":view.hand(viewer),
                                      "libraryCount":view.library_size()})
        assert all(not v["opposingHandIds"] for v in observed["views"])
        assert all(not v["exposedLibraryIds"] for v in observed["views"]), "Library per-card identities must not be exposed even to the owner"

    def four_player_loss():
        names = ["alice","bob","carol","dave"]
        g = mtg.Game({p:["Plains"]*99 for p in names}, variant="commander", seed=42,
                     commanders={p:["Isamaru, Hound of Konda"] for p in names}, explicit_lands=True)
        observed.update(startLife=g.life(), registered=g.players, initialGameOver=g.is_game_over())
        assert len(g.players) == 4 and set(g.life().values()) == {40}
        # Fixture positions Carol at zero; public Game.push performs actual SBA/terminal handling.
        state = copy.deepcopy(g.state)
        state["life"] = {(p, 0 if p == "carol" else life) for p,life in state["life"]}
        g = mtg.Game.from_state(state)
        g.push(next(m for m in g.legal_moves if m.kind == "pass"))
        observed.update(afterLife=g.life(), gameOver=g.is_game_over(), outcome=g.outcome(),
                        legalCount=len(g.legal_moves), loser=g.state.get("_loser"))
        assert not g.is_game_over() and g.legal_moves, "A single loss must not terminate a four-player game with three survivors"

    cases = [("opening_first_draw_diagnostic",opening), ("hidden_library_diagnostic",hidden_library),
             ("four_player_commander_loss_diagnostic",four_player_loss)]
    for name, fn in cases:
        observed.clear()
        item = {"id":name,"status":"UNVERIFIED","layer":"fixture"}
        try:
            fn()
            item.update(status="PASS",layer="engine")
        except AssertionError as error:
            item.update(status="FAIL",layer="engine",error=str(error),traceback=traceback.format_exc())
        except Exception as error:
            item.update(error=str(error),traceback=traceback.format_exc())
        item["observed"] = copy.deepcopy(observed)
        results.append(item)
        print(json.dumps(item),flush=True)
    report = {"engine":"Witchcraft","revision":PIN,"dataSha256":DATA_SHA256,
              "source":"https://github.com/yevbar/witchcraft","backend":"pinned local Souffle interpreter",
              "scope":"Three independent diagnostics, not complete shared 17-case qualification; no upstream rules patch.","cases":results}
    (output / "results.json").write_text(json.dumps(report,indent=2)+"\n")
    print(output,flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
