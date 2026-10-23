#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Bounded local AO transport and exact-commit evidence regressions."""

import copy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ao_review_report as REPORT

SHA = "a" * 40
OTHER_SHA = "b" * 40
WORKER = "project-1"
REVIEWER = "reviewer-1"
ENV = {"AO_REVIEW_WORKER_SESSION_ID": WORKER, "AO_REVIEW_SESSION_ID": REVIEWER,
       "AO_PROJECT_ID": "project", "HEXPROOF_AO_HOST_ID": "h_trusted"}


def item(number=1):
    return {"runId": f"run-{number}", "verdict": "approved", "body": "Checked the candidate.",
            "githubReviewId": str(number)}


class FakeAO:
    def __init__(self, count=1):
        self.calls = []
        self.persist = True
        self.uncertain = False
        self.identity = {"apiVersion": 1, "hostId": "h_trusted"}
        self.session = {"session": {"id": WORKER, "projectId": "project"}}
        self.state = {"runs": [], "reviews": []}
        for number in range(1, count + 1):
            run = {"id": f"run-{number}", "sessionId": WORKER, "reviewId": REVIEWER,
                   "targetSha": SHA, "prUrl": f"https://github.com/owner/repo/pull/{number}",
                   "status": "running", "body": "", "verdict": "", "githubReviewId": ""}
            self.state["runs"].append(run)
            self.state["reviews"].append({"prUrl": run["prUrl"], "targetSha": SHA, "latestRun": run})

    def request(self, method, path, payload=None):
        self.calls.append((method, path, payload))
        if path == "/identity":
            return copy.deepcopy(self.identity)
        if path == f"/sessions/{WORKER}":
            return copy.deepcopy(self.session)
        if method == "GET" and path == f"/sessions/{WORKER}/reviews":
            return copy.deepcopy(self.state)
        if method == "POST" and path == f"/sessions/{WORKER}/reviews/submit":
            if self.persist:
                for result in payload["reviews"]:
                    run = next(run for run in self.state["runs"] if run["id"] == result["runId"])
                    run.update({key: value for key, value in result.items() if key != "runId"})
                    run["status"] = "complete"
            if self.uncertain:
                raise REPORT.ReportError("synthetic transport uncertainty")
            return {"runs": self.state["runs"]}
        raise AssertionError((method, path))

    @property
    def posts(self):
        return [call for call in self.calls if call[0] == "POST"]


class FakeTools:
    def __init__(self):
        self.checkout = SHA
        self.pr_heads = [SHA, SHA]
        self.review_overrides = {}
        self.calls = []

    def head(self):
        return self.checkout

    def github(self, endpoint, projection):
        self.calls.append(endpoint)
        if "/reviews/" in endpoint:
            return {"id": int(endpoint.rsplit("/", 1)[1]), "state": "COMMENTED",
                    "commit_id": SHA, **self.review_overrides}
        head = self.pr_heads.pop(0) if len(self.pr_heads) > 1 else self.pr_heads[0]
        return {"head": {"sha": head}}


class ReviewReportTests(unittest.TestCase):
    def setUp(self):
        self.ao = FakeAO()
        self.tools = FakeTools()
        self.env = dict(ENV)

    def submit(self, items=None):
        return REPORT.submit_reviews(items or [item()], WORKER, self.env,
                                     client=self.ao, tools=self.tools)

    def test_batch_success_records_marker_and_exact_targets_without_bodies(self):
        self.ao = FakeAO(2)
        result = self.submit([item(), item(2)])
        self.assertTrue(result["ok"])
        self.assertEqual(result["marker"], "hexproof-ao-http-report")
        self.assertEqual(result["submittedCount"], 2)
        self.assertEqual(result["reviews"][0], {"runId": "run-1", "targetSha": SHA, "verdict": "approved"})
        self.assertEqual(len(self.ao.posts), 1)
        self.assertEqual(self.ao.posts[0][2], {"reviews": [item(), item(2)]})

    def test_exact_completed_replay_never_posts(self):
        self.submit()
        self.ao.calls.clear()
        self.assertEqual(self.submit()["submittedCount"], 0)
        self.assertEqual(self.ao.posts, [])

    def test_completed_replay_rejects_any_changed_result(self):
        self.submit()
        for key, value in (("body", "Changed."), ("verdict", "changes_requested"), ("githubReviewId", "99")):
            with self.subTest(key=key):
                self.ao.calls.clear()
                with self.assertRaises(REPORT.ReportError):
                    self.submit([{**item(), key: value}])
                self.assertEqual(self.ao.posts, [])

    def test_foreign_or_terminal_runs_and_superseded_passes_are_rejected(self):
        for key, value in (("id", "absent"), ("sessionId", "other-1"), ("reviewId", "other-reviewer"),
                           ("status", "failed"), ("status", "cancelled"), ("status", "delivered"),
                           ("status", "superseded"), ("targetSha", "bad")):
            with self.subTest(key=key, value=value):
                self.ao = FakeAO()
                self.ao.state["runs"][0][key] = value
                with self.assertRaises(REPORT.ReportError):
                    self.submit()
                self.assertEqual(self.ao.posts, [])
        self.ao = FakeAO()
        self.ao.state["reviews"][0]["latestRun"] = {"id": "newer-run"}
        with self.assertRaisesRegex(REPORT.ReportError, "superseded"):
            self.submit()

    def test_worker_reviewer_project_and_daemon_identity_are_bound(self):
        for field in ("AO_REVIEW_WORKER_SESSION_ID", "AO_REVIEW_SESSION_ID", "AO_PROJECT_ID", "HEXPROOF_AO_HOST_ID"):
            with self.subTest(field=field):
                self.env = {**ENV, field: "foreign"}
                with self.assertRaises(REPORT.ReportError):
                    self.submit()
                self.assertEqual(self.ao.posts, [])
        self.env = dict(ENV)
        self.ao.identity["apiVersion"] = True
        with self.assertRaises(REPORT.ReportError):
            self.submit()

    def test_batch_validates_every_item_before_any_write(self):
        self.ao = FakeAO(2)
        self.ao.state["runs"][1]["reviewId"] = "foreign"
        with self.assertRaises(REPORT.ReportError):
            self.submit([item(), item(2)])
        self.assertEqual(self.ao.posts, [])

    def test_checkout_and_initial_or_final_provider_head_must_match(self):
        self.tools.checkout = OTHER_SHA
        with self.assertRaises(REPORT.ReportError):
            self.submit()
        self.assertEqual(self.ao.posts, [])
        self.tools.checkout = SHA
        self.tools.pr_heads = [OTHER_SHA]
        with self.assertRaises(REPORT.ReportError):
            self.submit()
        self.assertEqual(self.ao.posts, [])
        self.tools.pr_heads = [SHA, OTHER_SHA]
        with self.assertRaisesRegex(REPORT.ReportError, "fresh review"):
            self.submit()
        self.assertEqual(len(self.ao.posts), 1)
        self.ao.calls.clear()
        with self.assertRaises(REPORT.ReportError):
            self.submit()  # A completed replay must also reject the stale commit.
        self.assertEqual(self.ao.posts, [])

    def test_github_review_id_commit_and_published_state_are_checked(self):
        for override in ({"id": 99}, {"id": "1"}, {"id": True}, {"commit_id": OTHER_SHA},
                         {"state": "PENDING"}, {"state": "DISMISSED"}, {"state": "APPROVED"}):
            with self.subTest(override=override):
                self.tools.review_overrides = override
                with self.assertRaises(REPORT.ReportError):
                    self.submit()
                self.assertEqual(self.ao.posts, [])

    def test_only_strict_github_pr_urls_are_allowed(self):
        for url in ("http://github.com/o/r/pull/1", "https://github.com.evil/o/r/pull/1",
                    "https://github.com/o/../pull/1", "https://github.com/o/r/pull/1?x=y",
                    "https://github.com/o/r/pull/1/", "https://github.com@evil/o/r/pull/1"):
            with self.subTest(url=url):
                self.ao = FakeAO()
                self.ao.state["runs"][0]["prUrl"] = url
                self.ao.state["reviews"][0]["prUrl"] = url
                with self.assertRaises(REPORT.ReportError):
                    self.submit()
                self.assertEqual(self.ao.posts, [])

    def test_uncertain_write_is_read_back_and_never_blindly_retried(self):
        self.ao.uncertain = True
        self.assertTrue(self.submit()["recoveredAfterUncertainWrite"])
        self.assertEqual(len(self.ao.posts), 1)
        self.ao = FakeAO()
        self.ao.uncertain, self.ao.persist = True, False
        with self.assertRaisesRegex(REPORT.ReportError, "identical submission"):
            self.submit()
        self.assertEqual(len(self.ao.posts), 1)

    def test_stdin_rejects_extra_duplicate_malformed_or_unbounded_data(self):
        valid = {"reviews": [item()]}
        self.assertEqual(REPORT.parse_reviews(json.dumps(valid).encode()), [item()])
        bad = [b"{", b"[]", b'{"reviews":[],"reviews":[]}', b"x" * (REPORT.INPUT_LIMIT + 1)]
        for payload in ({"reviews": []}, {**valid, "extra": True}, {"reviews": [item(), item()]},
                        {"reviews": [{**item(), "body": " "}]}, {"reviews": [{**item(), "body": "x" * 32769}]},
                        {"reviews": [{**item(), "extra": True}]}, {"reviews": [{**item(), "githubReviewId": 1}]},
                        {"reviews": [{**item(), "githubReviewId": "1/other"}]},
                        {"reviews": [{**item(), "verdict": "maybe"}]},
                        {"reviews": [{**item(), "runId": "../foreign"}]}):
            bad.append(json.dumps(payload).encode())
        for raw in bad:
            with self.subTest(raw=raw[:60]), self.assertRaises(REPORT.ReportError):
                REPORT.parse_reviews(raw)


class TransportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.ao = FakeAO()
        self.redirect = False
        self.delay_post = False
        self.paths = []
        test = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                test.paths.append(self.path)
                if test.redirect:
                    self.send_response(302)
                    self.send_header("Location", f"http://127.0.0.1:{self.server.server_port}/secret")
                    self.end_headers()
                    return
                self.respond(test.ao.request("GET", self.path.removeprefix("/api/v1")))

            def do_POST(self):
                test.paths.append(self.path)
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                response = test.ao.request("POST", self.path.removeprefix("/api/v1"), body)
                if test.delay_post:
                    time.sleep(0.2)
                self.respond(response)

            def respond(self, value):
                raw = json.dumps(value).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                try:
                    self.wfile.write(raw)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        run_file = self.root / "running.json"
        run_file.write_text(json.dumps({"port": self.server.server_port, "pid": -9999}))
        self.env = {**ENV, "AO_RUN_FILE": str(run_file)}

    def test_http_ignores_proxy_environment_and_does_not_probe_pid(self):
        with mock.patch.dict(os.environ, {"HTTP_PROXY": "http://127.0.0.1:1", "http_proxy": "http://127.0.0.1:1",
                                          "ALL_PROXY": "http://127.0.0.1:1"}, clear=True):
            result = REPORT.submit_reviews([item()], WORKER, self.env,
                                           client=REPORT.AOClient(self.env), tools=FakeTools())
        self.assertTrue(result["ok"])

    def test_redirect_is_not_followed(self):
        self.redirect = True
        with self.assertRaises(REPORT.ReportError):
            REPORT.AOClient(self.env).request("GET", "/identity")
        self.assertEqual(self.paths, ["/api/v1/identity"])

    def test_real_post_timeout_recovers_by_exact_get_without_retry(self):
        self.delay_post = True
        with mock.patch.object(REPORT, "TIMEOUT", 0.05):
            result = REPORT.submit_reviews([item()], WORKER, self.env,
                                           client=REPORT.AOClient(self.env), tools=FakeTools())
        self.assertTrue(result["recoveredAfterUncertainWrite"])
        self.assertEqual(len(self.ao.posts), 1)

    def test_discovery_port_is_bounded_and_typed(self):
        for port in (True, "3001", 0, 65536):
            Path(self.env["AO_RUN_FILE"]).write_text(json.dumps({"port": port}))
            with self.subTest(port=port), self.assertRaises(REPORT.ReportError):
                REPORT.AOClient(self.env)

    def test_trusted_commands_use_absolute_paths_and_explicit_github_host(self):
        executable = self.root / "trusted-executable"
        executable.write_text("fixture")
        executable.chmod(0o700)
        env = {**self.env, "HEXPROOF_AO_GIT": str(executable), "HEXPROOF_AO_GH": str(executable),
               "GIT_DIR": "/foreign/repository", "GIT_WORK_TREE": "/foreign"}
        tools = REPORT.TrustedTools(env, self.root)
        with mock.patch.object(REPORT.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, SHA.encode(), b"")) as command:
            self.assertEqual(tools.head(), SHA)
            self.assertEqual(command.call_args.args[0], [str(executable), "-C", str(self.root), "rev-parse", "HEAD"])
            self.assertNotIn("GIT_DIR", command.call_args.kwargs["env"])
            self.assertNotIn("shell", command.call_args.kwargs)
        with mock.patch.object(REPORT.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b'{}', b"")) as command:
            tools.github("repos/owner/repo/pulls/1", "{head}")
            self.assertEqual(command.call_args.args[0][1:4], ["api", "--hostname", "github.com"])
        with mock.patch.object(REPORT.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"secret", b"secret")):
            with self.assertRaisesRegex(REPORT.ReportError, "^Trusted provider command failed\\.$"):
                tools.head()
        with self.assertRaises(REPORT.ReportError):
            REPORT.TrustedTools({**env, "HEXPROOF_AO_GIT": "git"}, self.root)


if __name__ == "__main__":
    unittest.main()
