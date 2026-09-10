#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "engine_evaluation", Path(__file__).resolve().parents[1] / "engine-eval/report.py")
evaluation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evaluation)
DRIVE_SPEC = importlib.util.spec_from_file_location(
    "engine_driver", Path(__file__).resolve().parents[1] / "engine-eval/drive.py")
driver = importlib.util.module_from_spec(DRIVE_SPEC)
DRIVE_SPEC.loader.exec_module(driver)


class EngineEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.suite = json.loads(evaluation.SUITE_PATH.read_text())
        self.result = {
            "schemaVersion": 1, "suiteVersion": self.suite["suiteVersion"], "candidate": "test",
            "source": {"url": "https://example.test/engine", "revision": "a" * 40, "patches": []},
            "cases": [{"id": "bolt_player", "status": "PASS", "layer": "engine",
                       "reason": "Executed the complete fixture", "setup": "Fixed main phase",
                       "assertionsPassed": 3, "assertionsFailed": 0,
                       "observed": {"targetLife": 17}, "evidence": ["case.log"]}],
        }

    def test_valid_evidence_bearing_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "case.log").write_text("stack, payment, exact damage and destination assertions\n")
            self.assertEqual(evaluation.validate_result(self.result, self.suite, root), [])

    def test_empty_pass_is_rejected(self):
        for field, value in [("assertionsPassed", 0), ("observed", {}), ("evidence", []),
                             ("assertionsFailed", 1), ("assertionsPassed", True)]:
            with self.subTest(field=field):
                result = copy.deepcopy(self.result)
                result["cases"][0][field] = value
                self.assertTrue(evaluation.validate_result(result, self.suite))

    def test_missing_and_empty_evidence_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(evaluation.validate_result(self.result, self.suite, Path(directory)))
            (Path(directory) / "case.log").touch()
            self.assertTrue(evaluation.validate_result(self.result, self.suite, Path(directory)))

    def test_missing_cases_remain_unverified(self):
        output = evaluation.matrix([self.result], self.suite)
        self.assertIn("| opening | UNVERIFIED |", output)
        self.assertIn("| bolt_player | PASS |", output)

    def test_duplicate_unknown_and_stale_cases_rejected(self):
        result = copy.deepcopy(self.result)
        result["cases"].append(copy.deepcopy(result["cases"][0]))
        self.assertTrue(evaluation.validate_result(result, self.suite))
        result["cases"][1]["id"] = "upstream_test_count"
        self.assertTrue(evaluation.validate_result(result, self.suite))
        self.result["suiteVersion"] = "old"
        self.assertTrue(evaluation.validate_result(self.result, self.suite))

    def test_partial_result_is_not_forced_into_engine_failure(self):
        case = self.result["cases"][0]
        case.update(status="UNVERIFIED", layer="fixture", assertionsPassed=0, evidence=[], observed={})
        self.assertEqual(evaluation.validate_result(self.result, self.suite), [])

    def test_failure_requires_failed_assertion(self):
        self.result["cases"][0]["status"] = "FAIL"
        self.assertTrue(evaluation.validate_result(self.result, self.suite))
        self.result["cases"][0]["assertionsFailed"] = 1
        self.assertEqual(evaluation.validate_result(self.result, self.suite), [])

    def test_life_and_terminal_state_both_required(self):
        event = {"gameOver": True, "view": {"players": [{"id": 0, "life": 20}, {"id": 1, "life": 0}]}}
        self.assertTrue(driver.natural_terminal(event))
        event["gameOver"] = False
        self.assertFalse(driver.natural_terminal(event))
        event["gameOver"] = True
        event["view"]["players"][1]["life"] = 20
        self.assertFalse(driver.natural_terminal(event))

    def test_contradictory_winner_or_natural_flag_rejected(self):
        event = {"gameOver": True, "winner": 0, "view": {"players": [{"id": "player-0", "life": 0}, {"id": "player-1", "life": 20}]}}
        self.assertFalse(driver.natural_terminal(event))
        event["winner"] = 1
        self.assertTrue(driver.natural_terminal(event))
        event["naturalCompletion"] = False
        self.assertFalse(driver.natural_terminal(event))

    def test_common_policy_confirms_payment_before_tapping_extra_mana(self):
        choice = driver.choose_action({"actions": [{"category": "mana"}, {"category": "confirm"}]})
        self.assertEqual(choice["category"], "confirm")
        with self.assertRaises(ValueError):
            driver.choose_action({"kind": "unknown", "actions": [{"category": "other"}]})

    def test_malformed_terminal_fields_are_rejected(self):
        valid = {"gameOver": True, "view": {"players": [{"id": 0, "life": 20}, {"id": 1, "life": 0}]}}
        for field, value in [("naturalCompletion", "false"), ("naturalCompletion", 1),
                             ("winner", None), ("winner", False), ("view", None)]:
            with self.subTest(field=field, value=value):
                event = copy.deepcopy(valid)
                event[field] = value
                self.assertFalse(driver.natural_terminal(event))
        self.assertFalse(driver.natural_terminal({"gameOver": True, "naturalCompletion": "false",
                         "winner": None, "view": {"players": [{"life": 20}, {"life": 0}]}}))

    def test_terminal_needs_unique_ids_and_finite_life(self):
        valid = {"gameOver": True, "view": {"players": [{"id": 0, "life": 20}, {"id": 1, "life": 0}]}}
        for field, value in [("id", 1), ("id", "player-1"), ("id", None),
                             ("id", ""), ("life", float("inf")), ("life", float("nan"))]:
            with self.subTest(field=field, value=value):
                event = copy.deepcopy(valid)
                event["view"]["players"][0][field] = value
                self.assertFalse(driver.natural_terminal(event))

    def test_zone_observation_uses_actual_owner_projection(self):
        event = {"views": [
            {"viewer": -1, "zones": [{"owner": 0, "zone": "hand", "cards": []}]},
            {"viewer": 0, "zones": [{"owner": 0, "zone": "hand", "cards": [{"name": "Forest"}]}]},
        ]}
        self.assertEqual(driver.card_count(event, 0, 0, "hand", "Forest"), 1)
        self.assertEqual(driver.card_count(event, -1, 0, "hand", "Forest"), 0)

    def test_percentile_preserves_outliers_and_empty_samples(self):
        self.assertIsNone(driver.percentile([], .95))
        self.assertEqual(driver.percentile([1] * 18 + [99, 101], .95), 99)


if __name__ == "__main__":
    unittest.main()
