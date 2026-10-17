#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Regression checks for truthfulness at the executable observation boundary."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("wagic_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ObservationTests(unittest.TestCase):
    def line(self, **extra):
        return "HEXPROOF_OBSERVATION " + json.dumps({"id": "bolt_player", "assertions": [{"passed": True}], "observed": {"life": 17}, **extra})

    def test_normal_exit(self):
        self.assertNotIn("error", runner.observations(self.line(), "bolt_player", 0)[0])

    def test_cleanup_crash_cannot_pass(self):
        self.assertIn("not a completed PASS", runner.observations(self.line(), "bolt_player", -6)[0]["error"])

    def test_missing_row_cannot_pass(self):
        self.assertIn("error", runner.observations("", "bolt_player", 0)[0])

    def test_duplicate_rows_cannot_pass(self):
        self.assertIn("error", runner.observations(self.line() + "\n" + self.line(), "bolt_player", 0)[0])

    def test_wrong_case_cannot_pass(self):
        self.assertIn("error", runner.observations(self.line(id="copy"), "bolt_player", 0)[0])

    def test_real_assertion_failure_preserved(self):
        row = runner.observations(self.line(error="ASSERTION: wrong damage", assertions=[{"passed": False}]), "bolt_player", 1)[0]
        self.assertEqual("ASSERTION: wrong damage", row["error"])
        self.assertFalse(row["assertions"][0]["passed"])


class SourceDiffTests(unittest.TestCase):
    def test_preserves_crlf_context_and_binary_bytes(self):
        raw = b"diff --git a/example.h b/example.h\n@@ -1 +1 @@\n-old\r\n+new\r\n binary:\xff\n"
        with tempfile.TemporaryDirectory(prefix="wagic-diff-test-") as temporary:
            source = Path(temporary)
            target = source / "source-diff.patch"
            with patch.object(runner.subprocess, "check_output", return_value=raw) as command:
                runner.save_source_diff(source, target)
            command.assert_called_once_with(["git", "diff", "--binary"], cwd=source)
            self.assertEqual(raw, target.read_bytes())


if __name__ == "__main__":
    unittest.main()
