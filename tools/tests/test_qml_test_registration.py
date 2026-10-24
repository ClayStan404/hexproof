#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the real QML CTest registration without building or requiring Qt."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("cmake") and shutil.which("ctest"), "CMake/CTest required")
class QmlTestRegistrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hexproof qml registration ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build = self.root / "build"
        self.inputs = self.root / "tests/qml"
        self.inputs.mkdir(parents=True)
        for name in ("tst_alpha.qml", "tst_beta.qml", "Fixture.qml"):
            (self.inputs / name).write_text("// Registration fixture, never executed.\n")
        source = (ROOT / "apps/client-qt/CMakeLists.txt").read_text()
        option = re.search(r"option\(HEXPROOF_QML_TESTS_PER_FILE\s+.*?\)", source,
                           re.DOTALL)
        self.assertIsNotNone(option)
        registration = source.split(
            "# Register QML tests with one output namespace per runner process.\n", 1)[1]
        registration = registration.split("# Context properties", 1)[0]
        (self.root / "CMakeLists.txt").write_text(
            "cmake_minimum_required(VERSION 3.21)\n"
            "project(qml_registration NONE)\n"
            "enable_testing()\n"
            "add_executable(hexproof_qml_test IMPORTED)\n"
            'set_target_properties(hexproof_qml_test PROPERTIES IMPORTED_LOCATION "${CMAKE_COMMAND}")\n'
            + option[0] + "\n" + registration)

    def configure(self, *options):
        subprocess.run(["cmake", "-S", str(self.root), "-B", str(self.build), *options],
                       check=True, capture_output=True, text=True)
        result = subprocess.run(["ctest", "--test-dir", str(self.build),
                                 "--show-only=json-v1"],
                                check=True, capture_output=True, text=True)
        return json.loads(result.stdout)["tests"]

    def assert_isolated(self, test):
        properties = {item["name"]: item["value"] for item in test["properties"]}
        self.assertEqual(properties["LABELS"], ["qml"])
        self.assertIn("QT_QPA_PLATFORM=offscreen", properties["ENVIRONMENT"])

    def test_default_keeps_single_qml_test_and_existing_report(self):
        tests = self.configure()
        self.assertEqual([test["name"] for test in tests], ["qml"])
        self.assertEqual(tests[0]["command"][2], str(self.inputs))
        self.assertIn(str(self.build / "qml-test-results.xml") + ",junitxml",
                      tests[0]["command"])
        self.assert_isolated(tests[0])

    def test_per_file_covers_inputs_once_with_unique_reports(self):
        tests = self.configure("-DHEXPROOF_QML_TESTS_PER_FILE=ON")
        self.assertEqual({test["name"] for test in tests}, {"qml_alpha", "qml_beta"})
        self.assertEqual({test["command"][2] for test in tests},
                         {str(path) for path in self.inputs.glob("tst_*.qml")})
        outputs = []
        for test in tests:
            self.assert_isolated(test)
            command = test["command"]
            reports = [command[index + 1] for index, value in enumerate(command) if value == "-o"]
            self.assertEqual(len(reports), 2)
            self.assertEqual({report.rsplit(",", 1)[1] for report in reports}, {"txt", "junitxml"})
            outputs.extend(report.rsplit(",", 1)[0] for report in reports)
        self.assertEqual(len(set(outputs)), 2 * len(tests))
        self.assertTrue(all(Path(path).parent == self.build / "qml-test-results"
                            for path in outputs))

    def test_new_file_is_discovered_without_updating_a_manual_list(self):
        self.configure("-DHEXPROOF_QML_TESTS_PER_FILE=ON")
        (self.inputs / "tst_new.qml").write_text("// Newly added test.\n")
        tests = self.configure()
        self.assertEqual({test["name"] for test in tests},
                         {"qml_alpha", "qml_beta", "qml_new"})

    def test_nested_inputs_with_matching_basenames_keep_distinct_reports(self):
        for directory in ("nested", "other"):
            target = self.inputs / directory
            target.mkdir()
            (target / "tst_alpha.qml").write_text("// Nested registration fixture.\n")
        tests = self.configure("-DHEXPROOF_QML_TESTS_PER_FILE=ON")
        self.assertEqual({test["name"] for test in tests},
                         {"qml_alpha", "qml_beta", "qml_nested/alpha", "qml_other/alpha"})
        self.assertEqual({test["command"][2] for test in tests},
                         {str(path) for path in self.inputs.rglob("tst_*.qml")})
        reports = [command[index + 1].rsplit(",", 1)[0]
                   for test in tests for command in [test["command"]]
                   for index, value in enumerate(command) if value == "-o"]
        self.assertEqual(len(set(reports)), 2 * len(tests))
        self.assertTrue(all(Path(path).parent.is_dir() for path in reports))
        self.assertIn(str(self.build / "qml-test-results/nested/alpha.xml"), reports)

    def test_empty_input_directory_cannot_silently_skip_qml(self):
        for path in self.inputs.glob("tst_*.qml"):
            path.unlink()
        with self.assertRaises(subprocess.CalledProcessError) as failed:
            self.configure("-DHEXPROOF_QML_TESTS_PER_FILE=ON")
        self.assertIn("No QML test files found", failed.exception.stderr)


if __name__ == "__main__":
    unittest.main()
