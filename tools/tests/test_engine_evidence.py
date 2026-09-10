#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Negative controls for evidence retention and owned-process cleanup."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / "engine-eval"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(ROOT))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.pop(0)
    return module


upstream = load("evidence_upstream", "upstream_report.py")
workloads = load("evidence_workloads", "workload_driver.py")
control = sys.modules["process_control"]


def alive(pid):
    """An orphan zombie is exited, not a live workload; do not signal other PIDs."""
    try:
        if sys.platform.startswith("linux"):
            state = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[0]
            return state != "Z"
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, FileNotFoundError):
        return False


def wait_until(predicate, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(.02)
    return predicate()


def read_json_when_ready(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


class UpstreamReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def inspect(self, xml):
        path = self.directory / "report.xml"
        path.write_text(xml)
        return upstream.inspect(path)

    def test_junit_actual_entries_override_declared_total(self):
        xml = '<testsuite tests="999"><testcase classname="Rule" name="paid"/></testsuite>'
        report = self.inspect(xml)
        self.assertEqual(report["counts"], {"Passed": 1})
        self.assertEqual(report["sha256"], hashlib.sha256(xml.encode()).hexdigest())
        self.assertEqual(report["frameworkSummary"]["suites"][0]["tests"], "999")

    def test_junit_failure_error_skipped_and_nested_suites(self):
        report = self.inspect('''<testsuites><testsuite>
          <testcase name="ok"/><testcase name="fail"><failure>wrong life</failure></testcase>
          <testcase name="crash"><error>engine crash</error></testcase>
          <testcase name="skip"><skipped>missing fixture</skipped></testcase>
          <testsuite><testcase name="nested"/></testsuite></testsuite></testsuites>''')
        self.assertEqual(report["counts"], {"Passed": 2, "Failed": 2, "NotExecuted": 1})
        self.assertEqual(len(report["nonPassing"]), 3)
        self.assertIn("engine crash", json.dumps(report["nonPassing"]))

    def test_empty_failure_element_retains_message_and_type(self):
        report = self.inspect('<testsuite><testcase name="damage"><failure message="wrong life" type="AssertionError"/></testcase></testsuite>')
        self.assertEqual(report["counts"], {"Failed": 1})
        self.assertIn("wrong life", report["nonPassing"][0]["diagnostics"])
        self.assertIn("AssertionError", report["nonPassing"][0]["diagnostics"])

    def test_namespaced_junit_cannot_drop_failure_or_all_results(self):
        report = self.inspect('<testsuite xmlns="urn:fixture:junit"><testcase name="bad"><failure message="negative control"/></testcase><testcase name="skip"><skipped/></testcase></testsuite>')
        self.assertEqual(report["counts"], {"Failed": 1, "NotExecuted": 1})

    def test_failure_wins_over_skipped(self):
        report = self.inspect('<testsuite><testcase name="both"><skipped/><failure>failure remains</failure></testcase></testsuite>')
        self.assertEqual(report["counts"], {"Failed": 1})

    def test_suite_failure_not_lost_behind_passing_case(self):
        report = self.inspect('<testsuite errors="1"><testcase name="ok"/><error message="suite teardown crashed"/></testsuite>')
        self.assertEqual(report["counts"], {"Passed": 1})
        self.assertIn("suite teardown crashed", json.dumps(report["frameworkSummary"]))

    def test_trx_unknown_aborted_and_not_executed_not_passed(self):
        report = self.inspect('''<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"><Results>
          <UnitTestResult testName="ok" outcome="Passed"/>
          <UnitTestResult testName="bad" outcome="Failed"><Output><ErrorInfo><Message>wrong life</Message></ErrorInfo></Output></UnitTestResult>
          <UnitTestResult testName="skip" outcome="NotExecuted"/>
          <UnitTestResult testName="abort" outcome="Aborted"/>
          <UnitTestResult testName="unknown"/></Results></TestRun>''')
        self.assertEqual(report["counts"], {"Passed": 1, "Failed": 1, "NotExecuted": 1, "Aborted": 1, "Unknown": 1})
        self.assertEqual(len(report["nonPassing"]), 4)

    def test_trx_run_abort_retained_without_inventing_missing_cases(self):
        report = self.inspect('''<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
          <Results><UnitTestResult testName="early" outcome="Passed"/></Results>
          <ResultSummary outcome="Aborted"><Counters total="2" executed="1" passed="1"/>
            <RunInfos><RunInfo outcome="Error"><Text>Test host process crashed</Text></RunInfo></RunInfos>
          </ResultSummary></TestRun>''')
        self.assertEqual(report["counts"], {"Passed": 1})
        summary = report["frameworkSummary"]
        self.assertEqual(summary["outcome"], "Aborted")
        self.assertEqual(summary["counters"]["total"], "2")
        self.assertIn("Test host process crashed", json.dumps(summary))

    def test_no_entries_wrong_document_and_malformed_xml_rejected(self):
        for xml in ['<testsuite tests="40"/>', '<TestRun><ResultSummary outcome="Passed"/></TestRun>',
                    '<unrelated><testcase name="not-a-report"/></unrelated>']:
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.inspect(xml)
        with self.assertRaises(ET.ParseError):
            self.inspect('<testsuite><testcase')

    def test_cli_keeps_failed_counts_and_refuses_overwrite(self):
        self.inspect('<testsuite><testcase name="bad"><failure>failure</failure></testcase></testsuite>')
        output = self.directory / "out.json"
        command = [sys.executable, str(ROOT / "upstream_report.py"), "--root", str(self.directory),
                   "--glob", "*.xml", "--output", str(output)]
        first = subprocess.run(command, capture_output=True, timeout=5)
        self.assertEqual(first.returncode, 0, first.stderr)
        original = output.read_bytes()
        result = json.loads(original)
        self.assertEqual(result["totals"], {"Failed": 1})
        self.assertIn("not the frozen", result["scope"])
        self.assertNotIn("cases", result)
        second = subprocess.run(command, capture_output=True, timeout=5)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(output.read_bytes(), original)

    def test_cli_no_matches_does_not_create_output(self):
        output = self.directory / "out.json"
        result = subprocess.run([sys.executable, str(ROOT / "upstream_report.py"), "--root",
                                 str(self.directory), "--glob", "*.xml", "--output", str(output)],
                                capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


@unittest.skipUnless(os.name == "posix", "Owned process groups require POSIX")
class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def command(self, command, timeout=2):
        return [sys.executable, str(ROOT / "capture.py"), "--output", str(self.directory),
                "--name", "negative-control", "--timeout", str(timeout), "--", *command]

    def run_capture(self, code, timeout=2):
        process = subprocess.run(self.command([sys.executable, "-c", code], timeout),
                                 capture_output=True, timeout=10)
        output = Path(process.stdout.decode().splitlines()[0])
        return process, output, json.loads((output / "result.json").read_text())

    def test_success_preserves_both_streams_and_is_not_qualification(self):
        process, output, result = self.run_capture('import sys; print("stdout-proof"); print("stderr-proof",file=sys.stderr)')
        self.assertEqual(process.returncode, 0)
        self.assertEqual(result["exitCode"], 0)
        self.assertIn("Not inferred", result["qualification"])
        self.assertNotIn("status", result)
        log = (output / "execution.log").read_text()
        self.assertIn("stdout-proof", log)
        self.assertIn("stderr-proof", log)
        self.assertTrue((output / "process_control.py").is_file())

    def test_nonzero_exit_retained_without_timeout(self):
        process, _, result = self.run_capture('raise SystemExit(7)')
        self.assertEqual(process.returncode, 7)
        self.assertEqual(result["exitCode"], 7)
        self.assertFalse(result.get("timedOut", False))

    def test_signal_exit_retains_native_and_shell_exit_codes(self):
        process, _, result = self.run_capture('import os,signal; os.kill(os.getpid(),signal.SIGTERM)')
        self.assertEqual(process.returncode, 128 + signal.SIGTERM)
        self.assertEqual(result["exitCode"], -signal.SIGTERM)

    def test_timeout_retains_evidence_and_stops_process(self):
        process, _, result = self.run_capture('import time; print("started",flush=True); time.sleep(30)', 1)
        self.assertEqual(process.returncode, 124)
        self.assertTrue(result["timedOut"])
        self.assertFalse(alive(result["pid"]))

    def test_launch_failure_still_writes_result_and_diagnostic(self):
        process = subprocess.run(self.command([str(self.directory / "missing-executable")]),
                                 capture_output=True, timeout=5)
        self.assertNotEqual(process.returncode, 0)
        output = Path(process.stdout.decode().splitlines()[0])
        result = json.loads((output / "result.json").read_text())
        self.assertIsNone(result["pid"])
        self.assertNotEqual(result["exitCode"], 0)
        self.assertIn("FileNotFoundError", result["launchError"])
        self.assertIn("missing-executable", (output / "execution.log").read_text())

    def test_exited_leader_does_not_leave_sigterm_ignoring_child(self):
        child = 'import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print(os.getpid(),flush=True); time.sleep(30)'
        parent = f'import subprocess,sys; child=subprocess.Popen([sys.executable,"-c",{child!r}],stdout=subprocess.PIPE,text=True); print(child.stdout.readline().strip(),flush=True)'
        _, output, result = self.run_capture(parent)
        pid = int((output / "execution.log").read_text().strip())
        try:
            self.assertTrue(wait_until(lambda: not alive(pid), 1), "Leader exited, but its child survived capture cleanup")
            self.assertTrue(result["cleanup"]["sentKill"])
        finally:
            # Exact PID came from our own fixture; clean up even on a regression.
            if alive(pid):
                os.kill(pid, signal.SIGKILL)

    def test_capture_cancellation_writes_result_and_cleans_child(self):
        process = subprocess.Popen(self.command([sys.executable, "-c", 'import time; print("ready",flush=True); time.sleep(30)']),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output = Path(process.stdout.readline().strip())
        command_path = output / "command.json"
        pid = None
        try:
            self.assertTrue(wait_until(lambda: read_json_when_ready(command_path).get("pid") is not None))
            pid = json.loads(command_path.read_text())["pid"]
            process.send_signal(signal.SIGTERM)
            process.communicate(timeout=5)
            result = json.loads((output / "result.json").read_text())
            self.assertTrue(result["cancelled"])
            self.assertEqual(result["signal"], signal.SIGTERM)
            self.assertNotEqual(result["exitCode"], 0)
            self.assertFalse(alive(pid))
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=3)
            if pid is not None and alive(pid):
                os.killpg(pid, signal.SIGKILL)

    def test_cleanup_refuses_process_not_created_by_owned_factory(self):
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        try:
            with self.assertRaises(ValueError):
                control.stop_owned_process(process)
            self.assertIsNone(process.poll())
        finally:
            process.kill()
            process.wait(timeout=3)


@unittest.skipUnless(os.name == "posix", "Owned process groups require POSIX")
class WorkloadLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.spec = {"id": "negative-control", "players": [{}, {}]}

    def test_launch_failure_is_a_recorded_process_failure(self):
        result = workloads.run([str(self.directory / "missing-executable")], self.directory / "run", self.spec, 1)
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["failureKind"], "launch")
        self.assertTrue((self.directory / "run/result.json").is_file())

    def test_timeout_is_not_natural_completion(self):
        result = workloads.run([sys.executable, "-c", "import time; time.sleep(30)"],
                               self.directory / "run", self.spec, .15)
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(result["timedOut"])
        self.assertFalse(alive(result["pid"]))
        self.assertNotIn("terminal", result)

    def test_invalid_json_is_recorded_and_process_cleaned(self):
        result = workloads.run([sys.executable, "-c", 'import time; print("not-json",flush=True); time.sleep(30)'],
                               self.directory / "run", self.spec, 1)
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("JSONDecodeError", result["reason"])
        self.assertFalse(alive(result["pid"]))

    def test_pre_cancelled_worker_never_launches(self):
        token = control.Cancellation()
        token.cancel(signal.SIGINT)
        result = workloads.run([str(self.directory / "must-not-launch")], self.directory / "run", self.spec, 1, token)
        self.assertEqual(result["status"], "FAIL")
        self.assertTrue(result["cancelled"])
        self.assertEqual(result["signal"], signal.SIGINT)
        self.assertNotIn("pid", result)

    def test_live_cli_cancellation_records_all_workers_and_summary(self):
        specification = self.directory / "workloads.json"
        specification.write_text(json.dumps({"workloads": [self.spec]}))
        # A valid ready envelope keeps the driver waiting without a fake decision.
        script = 'import json,os,sys,time; from pathlib import Path; Path(sys.argv[1]).write_text(str(os.getpid())); print(json.dumps({"type":"ready","pid":os.getpid()}),flush=True); time.sleep(30)'
        command = [sys.executable, str(ROOT / "workload_driver.py"), "--output", str(self.directory),
                   "--workloads", str(specification), "--workload-id", self.spec["id"],
                   "--repeat", "3", "--concurrency", "2", "--timeout", "10", "--",
                   sys.executable, "-c", script, "{profile}/started.pid"]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output = Path(process.stdout.readline().strip())
        try:
            self.assertTrue(wait_until(lambda: len(list(output.glob("run-*/profile/started.pid"))) == 2))
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=6)
            self.assertNotEqual(process.returncode, 0, (stdout, stderr))
            results = json.loads((output / "results.json").read_text())["results"]
            self.assertEqual(len(results), 3)
            for result in results:
                self.assertEqual(result["status"], "FAIL")
                self.assertTrue(result["cancelled"])
                if "pid" in result:
                    self.assertFalse(alive(result["pid"]))
            self.assertTrue((output / "process_control.py").is_file())
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=3)
            # Exact fixture PID files remain usable even when a regression kills
            # the wrapper before it flushes its event log or final result.
            for path in output.glob("run-*/profile/started.pid"):
                pid = int(path.read_text())
                if alive(pid):
                    os.killpg(pid, signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
