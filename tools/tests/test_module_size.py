#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "module_size_review", Path(__file__).resolve().parents[1] / "check-module-size.py"
)
size = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(size)


class ModuleSizeTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.policy = {"defaults": {".qml": 4, ".go": 4, ".h": 4}, "testMultiplier": 1.5}
        self.policy_path = self.root / "policy.json"

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        return target

    def run_review(self):
        self.policy_path.write_text(json.dumps(self.policy), encoding="utf-8")
        output = io.StringIO()
        with patch.multiple(size, ROOT=self.root, POLICY_PATH=self.policy_path,
                            SOURCE_ROOTS=(self.root / "apps",)), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = size.main()
        return code, output.getvalue()

    def test_oversized_source_is_a_hint_not_a_failed_gate(self):
        self.write("apps/example.qml", "line\n" * 2000)
        code, output = self.run_review()
        self.assertEqual(code, 0)
        self.assertIn("2000 lines (review at 4)", output)
        self.assertIn("non-blocking", output)

    def test_tests_get_extra_room_for_fixtures_without_being_excluded(self):
        self.write("apps/client-qt/tests/fixture.qml", "line\n" * 5)
        self.write("apps/server/internal/room/room_test.go", "line\n" * 7)
        code, output = self.run_review()
        self.assertEqual(code, 0)
        self.assertNotIn("fixture.qml:", output)
        self.assertIn("7 lines (review at 6)", output)
        self.assertIn("2 source files", output)

    def test_path_rules_and_overrides_remain_advisory(self):
        self.policy.update(pathRules=[{"glob": "**/*Controller.qml", "limit": 2}],
                           overrides={"apps/Example.qml": 3})
        self.write("apps/TestController.qml", "line\n" * 5)
        self.write("apps/Example.qml", "line\n" * 5)
        code, output = self.run_review()
        self.assertEqual(code, 0)
        self.assertIn("review at 2", output)
        self.assertIn("review at 3", output)

    def test_generated_vendor_and_excluded_sources_are_not_reviewed(self):
        self.policy["excludePrefixes"] = ["apps/generated/"]
        for path in ("apps/generated/file.go", "apps/vendor/file.go", "apps/build/file.h",
                     "apps/WireConstantsGenerated.h", "apps/third_party/file.go"):
            self.write(path, "line\n" * 10)
        self.write("apps/server/cmd/main.go", "line\n" * 10)
        code, output = self.run_review()
        self.assertEqual(code, 0)
        self.assertIn("1 source files, 1 advisory hints", output)
        self.assertIn("apps/server/cmd/main.go", output)

    def test_invalid_policy_still_fails(self):
        for policy in ([], {}, {"defaults": {".qml": -1}},
                       {"defaults": {".qml": True}},
                       {"defaults": {".qml": 10}, "testMultiplier": 0},
                       {"defaults": {".qml": 10}, "excludePrefixes": "apps"},
                       {"defaults": {".qml": 10}, "pathRules": [{}]}):
            with self.subTest(policy=policy):
                self.policy = policy
                self.assertEqual(self.run_review()[0], 2)

    def test_stale_override_is_a_configuration_error(self):
        self.policy["overrides"] = {"apps/missing.qml": 10}
        code, output = self.run_review()
        self.assertEqual(code, 2)
        self.assertIn("stale policy override", output)


if __name__ == "__main__":
    unittest.main()
