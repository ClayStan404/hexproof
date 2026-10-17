#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Focused parser regression tests for mixed success/failure libtest output."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("rust_finalize", Path(__file__).with_name("finalize.py"))
FINALIZE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FINALIZE)


class ReadRunTests(unittest.TestCase):
    def test_later_observation_wins_but_failure_is_not_erased(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "run.log").write_text(
                "test prepare_cast ... HEXPROOF_OBSERVATION {}\n"
                "thread 'prepare_cast' panicked\nFAILED\n"
                "test modal_dfc ... HEXPROOF_OBSERVATION {}\nok\n"
                "failures:\n    prepare_cast\n"
                "test result: FAILED. 1 passed; 1 failed\n")
            (directory / "raw-results.json").write_text(json.dumps([
                {"case_id": "prepare_cast", "observations": {"stage": "entry"}},
                {"case_id": "prepare_cast", "observations": {"copies": 0}},
                {"case_id": "modal_dfc", "observations": {"green": 1}},
            ]))
            result = FINALIZE.read_run(directory)
            self.assertEqual(result["prepare_cast"]["status"], "FAIL")
            self.assertEqual(result["prepare_cast"]["observed"], {"copies": 0})
            self.assertEqual(result["modal_dfc"]["status"], "PASS")

    def test_unfinished_test_is_not_a_failure_or_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "run.log").write_text("test complete_4p ... waiting\n")
            (directory / "raw-results.json").write_text("[]")
            self.assertEqual(FINALIZE.read_run(directory)["complete_4p"]["status"], "UNVERIFIED")

    def test_successful_partial_diagnostic_does_not_become_full_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "run.log").write_text("test adventure ... observed\nok\n")
            (directory / "raw-results.json").write_text(json.dumps([
                {"case_id": "adventure", "observations": {"coverageComplete": False}},
            ]))
            self.assertEqual(FINALIZE.read_run(directory)["adventure"]["status"], "UNVERIFIED")


if __name__ == "__main__":
    unittest.main()
