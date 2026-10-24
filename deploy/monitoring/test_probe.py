#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("monitor_probe", Path(__file__).with_name("probe.py"))
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


def healthy():
    result = {"ready": True, "accounts": {"ready": True, "enabled": True}, "sendFailures": 2,
              "cluster": {"ready": True, "reportFailures": 3, "inFlight": 0, "pendingCompletions": 0}}
    for name in PROBE.TIMINGS:
        result[name] = {"calls": 2, "failed": 0, "cancelled": 0, "inFlight": 0,
                        "totalMs": 20, "maxMs": 15, "buckets": [1, 1, 0, 0, 0, 0, 0]}
    return result


class MonitorTests(unittest.TestCase):
    def sample(self, value, previous=None, status=200):
        with patch.object(PROBE, "fetch", side_effect=[(200, b"ok\n", 1),
                                                     (status, json.dumps(value).encode(), 10)]):
            return PROBE.collect(57320, previous)

    def test_baseline_and_interval_alerts(self):
        baseline = self.sample(healthy())
        self.assertEqual(baseline["alerts"], [])
        value = healthy()
        value["sendFailures"] += 1
        value["cluster"]["reportFailures"] += 1
        value["accountRpc"].update(calls=3, failed=1, totalMs=2020)
        sample = self.sample(value, baseline)
        self.assertEqual(set(sample["alerts"]), {"queue_send_failures", "cluster_report_failures",
                                                "accountRpc_failures", "accountRpc_mean_over_1s"})
        self.assertEqual(sample["interval"]["accountRpc"]["meanMs"], 2000)
        recovered = self.sample(value, sample)
        self.assertTrue(recovered["recovered"])
        self.assertEqual(recovered["alerts"], [])

    def test_restart_counters_do_not_underflow(self):
        before = self.sample(healthy())
        value = healthy()
        value["sendFailures"] = value["cluster"]["reportFailures"] = 0
        for name in PROBE.TIMINGS:
            value[name].update(calls=1, totalMs=2)
        sample = self.sample(value, before)
        self.assertEqual(sample["alerts"], [])
        self.assertEqual(sample["interval"]["accountRpc"]["meanMs"], 2)

    def test_unavailable_and_invalid_responses_are_recorded(self):
        value = healthy()
        value["ready"] = value["accounts"]["ready"] = False
        self.assertFalse(self.sample(value, status=503)["ready"])
        for value in ({}, [], {"ready": "yes"}, None):
            self.assertIn("dependencies_unavailable", self.sample(value)["alerts"])

    def test_only_aggregate_fields_are_persisted(self):
        value = healthy()
        value["secret"] = "private-credential"
        value["accounts"]["error"] = "private-credential"
        value["cluster"]["lastError"] = "private-credential"
        value["accountRpc"]["lastError"] = "private-credential"
        self.assertNotIn("private-credential", json.dumps(self.sample(value)))
        value["accountRpc"]["totalMs"] = float("nan")
        self.assertFalse(self.sample(value)["ready"])

    def test_feedback_readiness_is_distinct_and_does_not_log_response_content(self):
        responses = [(200, b'{"ok":true,"secret":"private-content"}', 1)] * 2
        with patch.object(PROBE, "fetch", side_effect=responses):
            healthy_sample = PROBE.collect(57324, component="feedback")
        self.assertTrue(healthy_sample["live"])
        self.assertTrue(healthy_sample["ready"])
        self.assertNotIn("private-content", json.dumps(healthy_sample))
        self.assertNotIn("diagnostics", healthy_sample)
        for body in (b'{"ok":false}', b'{"ok":"true"}', b'[]', b'not-json', b'ok\n'):
            with self.subTest(body=body), patch.object(PROBE, "fetch", side_effect=[
                    (200, b'{"ok":true}', 1), (200, body, 2)]):
                failed = PROBE.collect(57324, healthy_sample, component="feedback")
                self.assertTrue(failed["live"])
                self.assertFalse(failed["ready"])
                self.assertIn("dependencies_unavailable", failed["alerts"])
        with patch.object(PROBE, "fetch", side_effect=responses):
            self.assertTrue(PROBE.collect(57324, failed, component="feedback")["recovered"])

    def test_live_http_failure_and_recovery_persist(self):
        state = {"code": 503, "body": healthy()}
        state["body"]["ready"] = False

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200 if self.path == "/healthz" else state["code"])
                self.end_headers()
                self.wfile.write(b"ok\n" if self.path == "/healthz" else json.dumps(state["body"]).encode())

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                self.assertFalse(PROBE.run(server.server_port, directory)["ready"])
                state.update(code=200, body=healthy())
                self.assertTrue(PROBE.run(server.server_port, directory)["recovered"])
                self.assertTrue(json.loads((directory / "latest.json").read_text())["ready"])
                alerts = [json.loads(line) for line in (directory / "alerts.jsonl").read_text().splitlines()]
                self.assertEqual(len(alerts), 2)
                # A new invocation can read its own normalized previous snapshot.
                self.assertEqual(PROBE.run(server.server_port, directory)["alerts"], [])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_rotated_logs_are_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for _ in range(30):
                PROBE.append_log(directory / "samples.jsonl", {"payload": "x" * 50}, 100)
            self.assertLessEqual(len(list(directory.iterdir())), 8)


if __name__ == "__main__":
    unittest.main()
