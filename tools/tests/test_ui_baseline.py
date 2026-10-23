# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ui_baseline", ROOT / "tools/ui-automation/ui_baseline.py")
BASELINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASELINE)
MANIFEST = ROOT / "tools/ui-automation/ui-behavior-baseline.json"


class UiBaselineTests(unittest.TestCase):
    def setUp(self):
        self.manifest = BASELINE.load_manifest(MANIFEST)
        self.observations = {
            "phase.list_at_approved_budget": {"mode": "list", "completeRows": 11,
                                               "actionsReachable": True, "compactActions": True},
            "phase.presentation_transitions": {"transitions": 3, "authoritativePhaseRetained": True},
            "deck.preview_source": {"metadataPublications": 1, "hiddenFrames": 0, "observedFrames": 30,
                                    "visibleBeforePublication": True, "metadataChangedForPrinting": True},
            "deck.preview_held": {"metadataPublications": 1, "hiddenFrames": 0,
                                  "observedFrames": 30, "heldBeforePublication": True,
                                  "visibleBeforePublication": True, "metadataChangedForPrinting": True},
            "deck.wheel": {"wheelEvents": 6, "downDistance": 800, "upDistance": -300,
                           "unitsPerNotch": 144, "accumulatedTravelRatio": 1,
                           "sameDirectionReverseFrames": 0, "previewHiddenWhileScrolling": True,
                           "previewRecoveredAfterScroll": True},
            "deck.preview_wheel": {"faceCount": 2, "frontDistance": 144,
                                   "backDistance": 144, "pointsInsideGallery": True},
            "deck.first_count": {"cacheActiveBeforePress": True, "maxGalleryDelta": 0,
                                 "maxButtonDelta": 0.5, "countDelta": 1, "presses": 1, "samePrinting": True},
            "deck.explicit_cache": {"activeSamples": 2, "visibleDuringActivity": True,
                                    "maxGalleryDelta": 0, "completed": True},
            "deck.scrollbar": {"distance": 500, "postSettleDrift": 0},
        }

    def action(self, kind, sequence, events):
        action = {"action": kind, "sequence": sequence, "accepted": True, "evidence": "system-input",
                  "systemInput": {"status": "passed", "backend": "mutter-virtual-device", "pid": 1234,
                                  "window": 42, "ownerWindow": 42, "focusVerified": True,
                                  "deliveryVerified": True, "spontaneousEvents": events}}
        if kind == "wheel":
            action["delta"] = -120
        return action

    def evidence(self, scope="deck"):
        expected = [case["id"] for case in self.manifest["cases"] if case["scenario"] == scope]
        evidence = {"schema": BASELINE.EVIDENCE_SCHEMA, "status": "passed", "runId": "test-run",
                    "referenceCommit": self.manifest["reference"]["commit"],
                    "scenario": self.manifest["scenarios"][scope]["name"],
                    "performance": "not-assessed",
                    "cases": [{"id": identity, "observations": copy.deepcopy(self.observations[identity])}
                              for identity in expected]}
        if scope == "deck":
            evidence["fixture"] = {"syntheticArt": True, "mainRows": 85, "sideRows": 24, "faceCount": 2}
        startup = {"evidence": "system-input", "pid": 1234, "runId": "test-run",
                   "window": {"platform": "xcb", "visible": True, "exposed": True, "width": 2560,
                              "height": 1371, "dpr": 1, "windowMode": "maximized",
                              "requestedWindowMode": "maximized"}}
        actions = [self.action("click", 1, {"mousePress": 1, "mouseRelease": 1})]
        if scope == "deck":
            actions.append(self.action("wheel", 2, {"wheel": 1}))
        summary = {"evidence": "system-input", "osInputVerified": True, "inputs": len(actions),
                   "exitCode": 0, "failedInputs": 0, "artifactFailures": 0, "qmlWarnings": []}
        return evidence, startup, summary, actions

    def validate(self, values, scope="deck"):
        return BASELINE.validate_evidence(self.manifest, scope, *values)

    def test_complete_contracts_pass_and_do_not_claim_performance(self):
        for scope in ("phase", "deck"):
            with self.subTest(scope=scope):
                result = self.validate(self.evidence(scope), scope)
                self.assertEqual(result, {"scope": scope,
                    "cases": [case["id"] for case in self.manifest["cases"] if case["scenario"] == scope],
                    "referenceCommit": self.manifest["reference"]["commit"], "performance": "not-assessed"})

    def test_supplemental_fixed_case_does_not_replace_maximized_startup(self):
        values = self.evidence("phase")
        values[0]["cases"][0]["windowGeometry"] = {"windowMode": "windowed", "width": 1280, "height": 686}
        values[1]["requestedWindowMode"] = values[1]["window"].pop("requestedWindowMode")
        values[1]["windowMode"] = values[1]["window"].pop("windowMode")
        self.validate(values, "phase")
        values[1]["windowMode"] = "windowed"
        with self.assertRaisesRegex(ValueError, "maximized"):
            self.validate(values, "phase")

    def test_generic_pass_cannot_mask_missing_duplicate_or_unknown_cases(self):
        for damage in ("missing", "duplicate", "unknown", "other scope"):
            with self.subTest(damage=damage):
                values = self.evidence()
                cases = values[0]["cases"]
                if damage == "missing":
                    cases.pop()
                elif damage == "duplicate":
                    cases.append(copy.deepcopy(cases[0]))
                else:
                    cases[0]["id"] = "deck.unapproved" if damage == "unknown" else "phase.list_at_approved_budget"
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_reference_scenario_run_and_schema_must_match(self):
        for field, wrong in (("schema", "unknown"), ("referenceCommit", "0" * 40),
                             ("scenario", "phase-navigation-regression"), ("runId", "other-run"),
                             ("performance", "verified-60-fps")):
            with self.subTest(field=field):
                values = self.evidence()
                values[0][field] = wrong
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_selector_cannot_satisfy_required_list_case(self):
        values = self.evidence("phase")
        values[0]["cases"][0]["observations"]["mode"] = "selector"
        with self.assertRaisesRegex(ValueError, "mode"):
            self.validate(values, "phase")

    def test_missing_real_fixture_capabilities_cannot_pass(self):
        for field, value in (("fixture", None), ("syntheticArt", False), ("mainRows", 59),
                             ("sideRows", 0), ("faceCount", 0), ("faceCount", True)):
            with self.subTest(field=field, value=value):
                values = self.evidence()
                if field == "fixture":
                    values[0].pop("fixture")
                else:
                    values[0]["fixture"][field] = value
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_each_required_observation_is_required(self):
        values = self.evidence()
        for index, case in enumerate(values[0]["cases"]):
            for name in case["observations"]:
                with self.subTest(case=case["id"], name=name):
                    damaged = copy.deepcopy(values)
                    del damaged[0]["cases"][index]["observations"][name]
                    with self.assertRaises(ValueError):
                        self.validate(damaged)

    def test_false_or_nonfinite_observations_cannot_hide_behind_pass(self):
        changes = [("deck.preview_source", "metadataPublications", 0),
                   ("deck.preview_held", "heldBeforePublication", False),
                   ("deck.wheel", "downDistance", 0), ("deck.wheel", "upDistance", 1),
                   ("deck.wheel", "unitsPerNotch", 1), ("deck.wheel", "accumulatedTravelRatio", 0.5),
                   ("deck.wheel", "sameDirectionReverseFrames", 1),
                   ("deck.first_count", "maxButtonDelta", 45),
                   ("deck.first_count", "cacheActiveBeforePress", 1),
                   ("deck.first_count", "countDelta", True),
                   ("deck.first_count", "presses", 2),
                   ("deck.explicit_cache", "completed", False),
                   ("deck.scrollbar", "postSettleDrift", float("nan")),
                   ("deck.scrollbar", "distance", float("inf")),
                   ("deck.scrollbar", "distance", float("-inf"))]
        for identity, name, value in changes:
            with self.subTest(case=identity, name=name, value=value):
                values = self.evidence()
                next(case for case in values[0]["cases"] if case["id"] == identity)["observations"][name] = value
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_native_startup_and_summary_cannot_be_replaced_with_qt_or_offscreen(self):
        changes = [(1, "evidence", "native-qt-input"), (2, "evidence", "native-qt-input"),
                   (2, "osInputVerified", False), (2, "failedInputs", 1), (2, "exitCode", 1),
                   (2, "artifactFailures", True), (2, "inputs", True), (2, "inputs", 3),
                   (2, "qmlWarnings", ["warning"]), (1, "pid", True)]
        for index, field, value in changes:
            with self.subTest(index=index, field=field):
                values = self.evidence()
                values[index][field] = value
                with self.assertRaises(ValueError):
                    self.validate(values)
        for field, value in (("platform", "offscreen"), ("exposed", False), ("visible", False),
                             ("requestedWindowMode", "windowed"), ("windowMode", "windowed"),
                             ("dpr", float("inf")), ("height", True), ("width", 0)):
            with self.subTest(field=field):
                values = self.evidence()
                values[1]["window"][field] = value
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_real_owned_click_and_wheel_delivery_are_required(self):
        for field, value in (("pid", 999), ("backend", "qt"), ("focusVerified", False),
                             ("deliveryVerified", False), ("window", True), ("ownerWindow", 0),
                             ("spontaneousEvents", {"mouseRelease": 1}),
                             ("spontaneousEvents", {"mousePress": True, "mouseRelease": 1})):
            with self.subTest(field=field):
                values = self.evidence()
                values[3][0]["systemInput"][field] = value
                with self.assertRaises(ValueError):
                    self.validate(values)

        for damage in ("wheel receipt", "wheel delta", "missing wheel", "failed input", "sequence"):
            with self.subTest(damage=damage):
                values = self.evidence()
                if damage == "wheel receipt":
                    values[3][1]["systemInput"]["spontaneousEvents"] = {}
                elif damage == "wheel delta":
                    values[3][1]["delta"] = True
                elif damage == "missing wheel":
                    values[3].pop()
                    values[2]["inputs"] = 1
                elif damage == "failed input":
                    values[3][0]["accepted"] = False
                else:
                    values[3][1]["sequence"] = True
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_malformed_evidence_objects_raise_validation_errors(self):
        for index, value in ((0, None), (1, []), (2, None), (3, {})):
            with self.subTest(index=index):
                values = list(self.evidence())
                values[index] = value
                with self.assertRaises(ValueError):
                    self.validate(values)

    def test_manifest_rejects_invalid_types_duplicates_and_contradictions(self):
        changes = [lambda m: m.update(schema="unknown"),
                   lambda m: m["reference"].update(commit="v2.5.0"),
                   lambda m: m["cases"].append(copy.deepcopy(m["cases"][0])),
                   lambda m: m["cases"][0].update(scenario="unknown"),
                   lambda m: m["qmlSuites"].append(m["qmlSuites"][0]),
                   lambda m: m["cases"][0]["observations"].update(mode={"type": "unknown", "eq": "list"}),
                   lambda m: m["cases"][0]["observations"].update(mode={"type": "string", "min": 0}),
                   lambda m: m["cases"][0]["observations"].update(completeRows={"type": "integer", "eq": True}),
                   lambda m: m["cases"][0]["observations"].update(completeRows={"type": "integer", "gt": 1, "lt": 2}),
                   lambda m: m["cases"][0]["observations"].update(completeRows={"type": "number", "gt": 1, "max": 1}),
                   lambda m: m["cases"][0]["observations"].update(completeRows={"type": "integer", "eq": 11, "max": 10}),
                   lambda m: m["cases"][0]["observations"].update(completeRows={"type": "integer"}),
                   lambda m: m["cases"][0]["observations"].update(completeRows={"type": "number", "min": float("nan")})]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            for index, change in enumerate(changes):
                with self.subTest(change=index):
                    manifest = copy.deepcopy(self.manifest)
                    change(manifest)
                    path.write_text(json.dumps(manifest))
                    with self.assertRaises(ValueError):
                        BASELINE.load_manifest(path)
            path.write_text('{"schema":"first","schema":"second"}')
            with self.assertRaisesRegex(ValueError, "Duplicate JSON"):
                BASELINE.load_manifest(path)


if __name__ == "__main__":
    unittest.main()
