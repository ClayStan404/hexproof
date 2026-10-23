# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import argparse
import http.client
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


PATH = Path(__file__).resolve().parents[1] / "ui-automation/run-ui-baseline.py"
SPEC = importlib.util.spec_from_file_location("ui_baseline_runner", PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
sys.path.insert(0, str(PATH.parent))
try:
    SPEC.loader.exec_module(RUNNER)
finally:
    sys.path.pop(0)


class UiBaselineRunnerTests(unittest.TestCase):
    def arguments(self, root):
        binary = root / "test-runner"
        binary.touch()
        return argparse.Namespace(output=root / "evidence", checks_only=True,
                                  binary=binary, qml_test_binary=binary, os_input_helper=None)

    def test_automated_only_never_claims_native_qualification(self):
        manifest = RUNNER.load_manifest(PATH.parent / "ui-behavior-baseline.json")
        checks = [{"suite": suite, "status": "passed"} for suite in manifest["qmlSuites"]]
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(Path(directory))
            with mock.patch.object(RUNNER, "run_qml_suites", return_value=checks), \
                    mock.patch.object(RUNNER, "command_result") as execute:
                self.assertEqual(RUNNER.run(args), 0)
            execute.assert_not_called()
            report = json.loads((args.output / "report.json").read_text())
            self.assertEqual(report["qualification"], "automated-only")
            self.assertEqual(report["native"]["status"], "not-run")
            self.assertEqual(report["performance"], "not-assessed")
            self.assertEqual(RUNNER.digest(args.output / "baseline-manifest.json"),
                             report["manifestSha256"])

    def test_failed_automated_guard_stops_before_native_setup(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(Path(directory))
            with mock.patch.object(RUNNER, "run_qml_suites", return_value=[{"status": "failed"}]), \
                    mock.patch.object(RUNNER, "command_result") as execute:
                self.assertEqual(RUNNER.run(args), 1)
            execute.assert_not_called()
            self.assertEqual(json.loads((args.output / "report.json").read_text())["qualification"],
                             "failed")

    def test_native_requires_explicit_helper_before_writing_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(Path(directory))
            args.checks_only = False
            with self.assertRaisesRegex(ValueError, "explicit --os-input-helper"):
                RUNNER.run(args)
            self.assertFalse(args.output.exists())

    def test_execution_error_retains_a_failed_report(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(Path(directory))
            with mock.patch.object(RUNNER, "run_qml_suites", side_effect=OSError("cannot launch")):
                with self.assertRaisesRegex(OSError, "cannot launch"):
                    RUNNER.run(args)
            report = json.loads((args.output / "report.json").read_text())
            self.assertEqual(report["qualification"], "failed")
            self.assertEqual(report["error"], "cannot launch")

    def test_provenance_error_retains_a_failed_report(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(Path(directory))
            with mock.patch.object(RUNNER, "digest", side_effect=OSError("cannot read")):
                with self.assertRaisesRegex(OSError, "cannot read"):
                    RUNNER.run(args)
            report = json.loads((args.output / "report.json").read_text())
            self.assertEqual(report["qualification"], "failed")
            self.assertEqual(report["error"], "cannot read")

    def test_interrupted_later_scope_preserves_completed_native_scope(self):
        manifest = RUNNER.load_manifest(PATH.parent / "ui-behavior-baseline.json")
        checks = [{"suite": suite, "status": "passed"} for suite in manifest["qmlSuites"]]
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(Path(directory))
            args.checks_only = False
            args.binary.chmod(0o700)
            args.os_input_helper = args.binary
            phase = {"scope": "phase", "status": "passed"}
            with mock.patch.object(RUNNER, "run_qml_suites", return_value=checks), \
                    mock.patch.object(RUNNER, "command_result", return_value={"exitCode": 0}), \
                    mock.patch.object(RUNNER, "run_native_scope", side_effect=[phase, KeyboardInterrupt]):
                with self.assertRaises(KeyboardInterrupt):
                    RUNNER.run(args)
            report = json.loads((args.output / "report.json").read_text())
            self.assertEqual(report["qualification"], "failed")
            self.assertEqual(report["native"], {"status": "failed", "activeScope": "deck", "scenarios": [phase]})

    def test_refusing_proxy_answers_locally_without_forwarding(self):
        with RUNNER.refusing_proxy() as (server, _):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request("CONNECT", "invalid.example:443")
                response = connection.getresponse()
                self.assertEqual(response.status, 502)
                self.assertEqual(response.read(), b"")
            finally:
                connection.close()
            self.assertEqual(server.request_count, 1)

    def test_command_deadline_terminates_the_owned_child(self):
        with tempfile.TemporaryDirectory() as directory:
            result = RUNNER.command_result(
                [sys.executable, "-c", "import time; time.sleep(10)"],
                Path(directory) / "timeout.log", None, 0.05)
            self.assertEqual(result["exitCode"], 124)
            self.assertLess(result["durationSeconds"], 5)

    @unittest.skipUnless(os.name == "posix", "POSIX session ownership")
    def test_owned_command_isolated_from_terminal_interrupt_group(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "session.log"
            result = RUNNER.command_result(
                [sys.executable, "-c", "import os; print(os.getpid(), os.getsid(0))"],
                log, None, 5)
            self.assertEqual(result["exitCode"], 0)
            pid, session = map(int, log.read_text().split())
            self.assertEqual(pid, session)
            self.assertNotEqual(session, os.getsid(0))


if __name__ == "__main__":
    unittest.main()
