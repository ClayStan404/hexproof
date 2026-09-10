#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Normalize independent native-engine observations without counting upstream tests."""

import argparse
import json
import os
from pathlib import Path
import re


def read_run(directory):
    log = (directory / "run.log").read_text()
    records = {r["case_id"]: r["observations"] for r in json.loads((directory / "raw-results.json").read_text())}
    matches = list(re.finditer(r"(?m)^test (\w+) \.\.\. ", log))
    cases = {}
    for n, match in enumerate(matches):
        end = matches[n + 1].start() if n + 1 < len(matches) else len(log)
        block = log[match.end():end]
        failure = bool(re.search(r"(?m)^FAILED$", block))
        passed = bool(re.search(r"(?m)^ok$", block))
        cases[match.group(1)] = {
            "status": "FAIL" if failure else "PASS" if passed and records.get(match.group(1), {}).get("coverageComplete") is not False else "UNVERIFIED",
            "observed": records.get(match.group(1), {}),
            "block": block,
            "directory": directory,
        }
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", choices=["rust", "phase"], required=True)
    parser.add_argument("--runs", nargs="+", type=Path, required=True,
                        help="Reviewed final runs; later runs override earlier matching cases")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--suite", type=Path, default=Path(__file__).resolve().parents[1] / "scenarios.json")
    args = parser.parse_args()
    suite = json.loads(args.suite.read_text())
    observed = {}
    for run in args.runs:
        observed.update(read_run(run.resolve()))
    result = {"schemaVersion": 1, "suiteVersion": suite["suiteVersion"],
              "candidate": "Manabrew Rust" if args.candidate == "rust" else "Phase",
              "source": {
                  "url": "https://github.com/witchesofthehill/manabrew" if args.candidate == "rust" else "https://github.com/phase-rs/phase",
                  "revision": "143a6b556ac365cea97929ffcebb48eed03ecde8" if args.candidate == "rust" else "87b8355cc1b0771f5152bd33cee8f81a5f0550cb",
                  "patches": [] if args.candidate == "rust" else ["Isolated Cargo.toml removes unstable cargo-features declaration and two codegen-backend settings; engine source unchanged; see run compatibility.patch."]},
              "cases": [], "notes": [
                  "No upstream test counts are incorporated. PASS means independent frozen-fixture assertions ran.",
                  "All observations are debug semantic qualification, not comparative performance data.",
                  "No native Hexproof GUI or production adapter was certified.",
                  "Prepare and complete synthetic-deck games have separate reports; representative owner decks, release performance and finalist GUI are not certified here.",
              ]}
    if args.candidate == "rust":
        result["notes"].extend([
            "Real pinned Forge card scripts are data input, not a Forge rules oracle. Matching submodule revision is 753b3dd544d6f02061d796ff7a0b54806631edcb.",
            "PlayerAgent callbacks execute on the engine thread. land_priority proves external channel suspension and actor rejection in the evaluated host bridge; this requires a host actor boundary.",
            "Native GameViewDto exposes both hands. The evaluated host projection's stronger library privacy qualification requires observed.library_tracking: no known public ID or library order may survive an actual engine shuffle. Morph and all private prompt carriers remain separate coverage.",
            "The earlier historical report mislabeled a token-copy Haste assertion as Flying. Neither assertion is counted in this new qualification.",
            "The checkout's existing Java harness edits are outside the Rust crates executed here. No Rust engine source was patched.",
        ])
    else:
        result["notes"].extend([
            "Inline Oracle-text fixtures use Phase GameScenario parsing/synthesis and normal apply/cast/payment rules. They are not a full card-database ingestion or deck-validator qualification.",
            "The privacy re-audit strengthens the existing frozen library identity/order assertion. Its Time Ebb plus actual seeded shuffle evidence supersedes the earlier names-only hidden_views PASS.",
        ])
    for definition in suite["cases"]:
        case_id = definition["id"]
        case = {"id": case_id, "status": "UNVERIFIED", "layer": "adapter",
                "reason": "This evaluator has not completed the frozen scenario; no engine capability conclusion.",
                "assertionsPassed": 0, "assertionsFailed": 0,
                "setup": "No complete executed fixture in this qualification round.",
                "observed": {}, "evidence": []}
        if case_id in observed:
            raw = observed[case_id]
            case.update(status=raw["status"], layer="engine", observed=raw["observed"],
                        setup=("Direct zone fixtures from pinned actual card scripts, real PlayerAgent choices, payment, priority, resolution and SBA." if args.candidate == "rust" else
                               "Direct GameScenario/Oracle-text zone fixtures; normal reducer actions and casting/payment/SBA. Commander tax has an explicitly separate insufficient-mana branch fixture."),
                        reason="Every frozen assertion group executed through the engine API.",
                        evidence=[os.path.relpath(raw["directory"] / "run.log", args.output.resolve().parent),
                                  os.path.relpath(raw["directory"] / "raw-results.json", args.output.resolve().parent),
                                  os.path.relpath(raw["directory"] / "provenance.json", args.output.resolve().parent),
                                  os.path.relpath(raw["directory"] / "fixture.rs", args.output.resolve().parent)])
            if args.candidate == "phase":
                case["evidence"].append(os.path.relpath(raw["directory"] / "compatibility.patch", args.output.resolve().parent))
            if case_id == "hidden_views":
                case["evidence"].extend(os.path.relpath(p, args.output.resolve().parent) for p in sorted(raw["directory"].glob("*view-*.json")))
            if raw["status"] == "PASS":
                case["assertionsPassed"] = len(definition["assertions"])
            elif raw["status"] == "FAIL":
                case.update(assertionsFailed=1, reason="An executed assertion failed; inspect the preserved exact run log.", layer="unknown")
            else:
                case["reason"] = "The selected test did not report completion. Inspect the bounded run log."
            if args.candidate == "rust" and case_id in {"adventure", "prepare_cast", "prepare_source_leaves"} and raw["status"] != "FAIL" and raw["observed"].get("coverageComplete") is not True:
                case.update(status="UNVERIFIED", layer="fixture", assertionsPassed=0,
                            reason="This is a capability diagnostic, not a complete lifecycle probe. Passing its initial missing-capability assertion cannot establish all frozen groups; complete lifecycle coverage must be explicitly added.")
            if args.candidate == "rust" and case_id == "land_priority":
                case["layer"] = "adapter"
                case["reason"] = "Engine enforces land count; evaluated host channel rejects a different actor while the decision remains blocked, then accepts the owner response."
            if args.candidate == "rust" and case_id == "hidden_views":
                tracking_pass = raw["observed"].get("library_tracking", {}).get("all_viewers_hide_known_card_position") is True
                case.update(status="FAIL", layer="adapter", assertionsPassed=0, assertionsFailed=1,
                            reason=("Native GameViewDto exposes both hands. The evaluated host projection passes basic hidden-zone assertions and actual-shuffle stable-ID tracking; native library DTO is count-only. Morph and private prompt carriers are separate coverage, not inferred from this basic hidden-zone run." if tracking_pass else
                                    "Native GameViewDto exposes both hands. This selected run does not establish host remediation of the full frozen library identity/order assertion; stronger tracking evidence is required."),
                            setup="Distinct secret card identities in native CardInstance objects; native DTO conversion followed by evaluated host hand redaction. Separate public-card zone-move/top-placement and actual seeded shuffle primitives test entire payload ID absence and count-only libraries for three viewers.")
            if args.candidate == "phase" and case_id == "hidden_views":
                tracking = raw["observed"].get("library_tracking", {})
                if tracking.get("all_viewers_hide_known_card_position") is False or tracking.get("all_viewers_hide_all_private_library_ids") is False:
                    case.update(status="FAIL", layer="adapter", assertionsPassed=3, assertionsFailed=1,
                                reason="After a real Time Ebb and seeded engine shuffle, owner, opponent and spectator projections retain ordered stable library object IDs. The previously public Bears identity remains recoverable at its exact shuffled position; hiding names alone does not preserve library privacy.")
                elif tracking.get("all_viewers_hide_all_private_library_ids") is not True:
                    case.update(status="UNVERIFIED", layer="adapter", assertionsPassed=3, assertionsFailed=0,
                                reason="Full-library projection checks are incomplete: temporal tracking must exclude every private library ID, not only one previously public card.")
            if args.candidate == "rust" and case_id == "four_player_departure" and raw["status"] == "PASS":
                projection = observed.get("departure_projection")
                matching_state = projection and Path(projection["observed"].get("state_directory", "")).resolve() == raw["directory"]
                if matching_state and projection["status"] == "PASS" and projection["observed"].get("all_viewers_hide_departed_object") is True and raw["observed"].get("bears_in_any_zone_store") is False and raw["observed"].get("bears_in_zone_index") is False:
                    case["observed"]["dto_projection"] = projection["observed"]
                    case["evidence"].extend(os.path.relpath(projection["directory"] / name, args.output.resolve().parent) for name in ["run.log", "raw-results.json", "fixture.rs", "provenance.json"])
                    case["evidence"].extend(os.path.relpath(p, args.output.resolve().parent) for p in sorted(projection["directory"].glob("departure-view-*.json")))
                    case["evidence"].append(os.path.relpath(raw["directory"] / "departure-state.json", args.output.resolve().parent))
                else:
                    case.update(status="UNVERIFIED", layer="fixture", assertionsPassed=3,
                                reason="Engine zone/continuation checks passed, but the selected runs lack completed DTO exclusion of the departed object.")
            if args.candidate == "phase" and case_id == "four_player_departure" and raw["status"] == "FAIL":
                case.update(layer="engine", assertionsPassed=3, reason="Leaving player owns Bears still present in the shared public exile zone and viewer projection. Three-player continuation and final player-0 victory pass, but owned objects do not leave the game.")
            if args.candidate == "phase" and case_id == "commander_damage" and raw["status"] == "FAIL":
                case.update(layer="engine", assertionsPassed=2, reason="19+2 commander combat damage eliminates the positive-life defender and noncombat damage does not increment the total, but the remaining game waits for an eliminated seat's CommanderZoneChoice.")
            if args.candidate == "phase" and case_id == "morph":
                case["evidence"].extend(os.path.relpath(p, args.output.resolve().parent) for p in sorted(raw["directory"].glob("morph-*-view-*.json")))
            if args.candidate == "rust" and case_id == "adventure" and raw["status"] == "FAIL":
                case.update(status="UNSUPPORTED", layer="engine", assertionsFailed=1,
                            reason="Pinned actual script and parser contain Heart's Desire and Adventure layout. Runtime card assembly discards that alternate face, PlayCardMode has no Adventure choice, and setup_adventure_ability returns None. Executing the sole Normal option pays 2G and puts Beast, not Heart's Desire, on the stack. This is missing runtime mechanic support, not missing card data.")
            if args.candidate == "rust" and case_id == "morph" and raw["status"] == "FAIL":
                case.update(layer="engine", assertionsPassed=0,
                            reason="Real Morph choice pays 3, but the stack card is face-up Willbender (blue, 1/2, printed cost). Resolution sets face-down and 2/2 but retains printed authoritative characteristics; no face-up activation is offered, so 1U cannot be paid. DTO privacy requires separate selected projection evidence.")
                if "morph_projection" in observed:
                    projection = observed["morph_projection"]
                    case["observed"]["dto_projection"] = projection["observed"]
                    case["evidence"].extend(os.path.relpath(projection["directory"] / name, args.output.resolve().parent) for name in ["run.log", "raw-results.json", "fixture.rs", "provenance.json"])
                    case["evidence"].extend(os.path.relpath(p, args.output.resolve().parent) for p in sorted(projection["directory"].glob("morph-*-view-*.json")))
                    if projection["observed"].get("all_private") is False:
                        case["reason"] += " Selected actual DTO replay proves opponent/spectator stack identity leakage; battlefield DTO names are correctly hidden."
                case["evidence"].extend(os.path.relpath(p, args.output.resolve().parent) for p in sorted(raw["directory"].glob("morph-*-state.json")))
            if case_id.startswith("prepare_") and raw["status"] == "FAIL":
                if args.candidate == "rust":
                    case.update(status="UNSUPPORTED", layer="engine", assertionsPassed=0,
                                reason="Pinned actual Goblin Glasswright/Craft with Pride script exists and the creature pays 1R and resolves as 2/2. Parser maps unknown AlternateMode:Prepare to None; runtime has no Prepared attribute handling or prepared-copy cast path. No associated exile copy is created. The separate real Bolt-removal control succeeds, but missing preparation prevents the required copy lifecycle.")
                else:
                    case.update(layer="adapter", assertionsPassed=3 if case_id == "prepare_cast" else 1,
                                reason="Frozen explicit exile-object/projection contract mismatch: real paid entry becomes prepared but has zero linked exile objects until casting. Later normal paid cast, unpreparation, Treasure resolution and Bolt removal behave correctly. Internal lazy representation alone does not establish a rules-observable defect; the required explicit pre-cast-copy assertion still fails and is not waived.")
                    if "supplemental_prepare_cast_restriction" in observed:
                        control = observed["supplemental_prepare_cast_restriction"]
                        case["observed"]["outside_hand_cast_restriction_control"] = control["observed"]
                        case["evidence"].extend(os.path.relpath(control["directory"] / name, args.output.resolve().parent) for name in ["run.log", "raw-results.json", "fixture.rs", "provenance.json"])
            if raw["observed"] == {} and raw["status"] == "FAIL":
                case.update(status="UNVERIFIED", layer="adapter", assertionsPassed=0, assertionsFailed=0,
                            reason="The fixture did not reach its complete observations; adapter/fixture investigation remains necessary before an engine capability conclusion.")
        result["cases"].append(case)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
