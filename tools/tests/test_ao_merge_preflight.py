#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Read-only provider evidence must not become an implicit merge approval."""

import base64
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ao_merge_preflight as PREFLIGHT

HEAD = "a" * 40
BASE = "b" * 40
OTHER = "c" * 40
WORKFLOW = b"trusted workflow\n"
PREFIX = "repos/owner/project"
PR_URL = "https://github.com/owner/project/pull/46"


def policy():
    return {
        "schemaVersion": 1,
        "repository": {"fullName": "owner/project", "id": 100},
        "pullRequest": {"number": 46, "baseRef": "master", "baseSha": BASE, "headSha": HEAD},
        "ao": {"hostId": "h_trusted", "projectId": "pilot", "workerSessionId": "pilot-3",
               "reviewSessionId": "review-1", "runId": "run-1", "githubActorId": 200},
        "ci": {"workflowId": 300, "workflowPath": ".github/workflows/ci.yml", "appId": 400,
               "requiredJobs": ["Quality", "Scope"],
               "definitionFiles": {".github/workflows/ci.yml": hashlib.sha256(WORKFLOW).hexdigest()}},
    }


def pr_binding():
    return {"number": 46, "base": {"ref": "master", "sha": BASE, "repo": {"id": 100}},
            "head": {"sha": HEAD, "repo": {"id": 100}}}


class FakeAO:
    def __init__(self):
        self.run = {"id": "run-1", "sessionId": "pilot-3", "reviewId": "review-1", "targetSha": HEAD,
                    "prUrl": PR_URL, "status": "complete", "verdict": "approved", "githubReviewId": "500"}
        self.current = {"prUrl": PR_URL, "targetSha": HEAD, "latestRun": {"id": "run-1"}}
        self.calls = []
        self.on_read = None

    def request(self, method, path):
        self.calls.append((method, path))
        if self.on_read:
            self.on_read(path)
        assert method == "GET"
        if path == "/identity":
            return {"hostId": "h_trusted", "apiVersion": 1}
        if path == "/sessions/pilot-3":
            return {"session": {"id": "pilot-3", "projectId": "pilot"}}
        if path == "/sessions/pilot-3/reviews":
            return {"runs": [copy.deepcopy(self.run)], "reviews": [copy.deepcopy(self.current)]}
        raise AssertionError(path)


class FakeGitHub:
    def __init__(self):
        self.pr = {**pr_binding(), "state": "open", "merged": False, "draft": True}
        self.branch = {"ref": "refs/heads/master", "object": {"type": "commit", "sha": BASE}}
        self.review = {"id": 500, "commit_id": HEAD, "state": "COMMENTED", "user": {"id": 200}}
        self.run = {"id": 600, "run_number": 7, "run_attempt": 1, "workflow_id": 300,
                    "path": ".github/workflows/ci.yml", "event": "pull_request", "head_sha": HEAD,
                    "repository": {"id": 100}, "head_repository": {"id": 100}, "check_suite_id": 700,
                    "pull_requests": [pr_binding()], "status": "completed", "conclusion": "success"}
        self.runs = [self.run]
        self.jobs = []
        self.checks = {}
        for number, name in enumerate(("Quality", "Scope"), 800):
            self.jobs.append({"id": number, "name": name, "head_sha": HEAD, "status": "completed",
                              "conclusion": "success", "check_run_url": "https://api.github.com/"
                              + PREFIX + "/check-runs/" + str(number)})
            self.checks[number] = {"id": number, "name": name, "head_sha": HEAD, "status": "completed",
                                   "conclusion": "success", "app": {"id": 400}, "check_suite": {"id": 700}}
        self.content = {"type": "file", "path": ".github/workflows/ci.yml", "encoding": "base64",
                        "content": base64.b64encode(WORKFLOW).decode()}
        self.extra_total = 0
        self.calls = []
        self.on_read = None

    def get(self, endpoint):
        self.calls.append(endpoint)
        if self.on_read:
            self.on_read(endpoint)
        path = endpoint.removeprefix(PREFIX)
        if path == "":
            result = {"id": 100, "full_name": "owner/project"}
        elif path == "/pulls/46":
            result = self.pr
        elif path == "/git/ref/heads/master":
            result = self.branch
        elif path == "/pulls/46/reviews/500":
            result = self.review
        elif path == "/contents/.github/workflows/ci.yml?ref=" + HEAD:
            result = self.content
        elif path == "/actions/workflows/300/runs?event=pull_request&head_sha=" + HEAD + "&per_page=100":
            result = {"total_count": len(self.runs) + self.extra_total, "workflow_runs": self.runs}
        elif path == "/actions/runs/600":
            result = self.run
        elif path == "/actions/runs/600/attempts/" + str(self.run["run_attempt"]) + "/jobs?per_page=100":
            result = {"total_count": len(self.jobs), "jobs": self.jobs}
        elif path.startswith("/check-runs/"):
            result = self.checks[int(path.rsplit("/", 1)[1])]
        else:
            raise AssertionError(endpoint)
        return copy.deepcopy(result)


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.policy, self.ao, self.gh = policy(), FakeAO(), FakeGitHub()

    def check(self):
        return PREFLIGHT.preflight(self.policy, self.ao, self.gh)

    def test_draft_observed_evidence_pass_never_authorizes_merge(self):
        result = self.check()
        self.assertTrue(result["observedEvidenceReady"])
        self.assertIs(result["mergeAuthorized"], False)
        self.assertTrue(result["evidence"]["pullRequest"]["draft"])
        self.assertEqual(result["missingAuthorities"], PREFLIGHT.MISSING_AUTHORITIES)
        self.assertEqual(result["evidence"]["ci"]["attempt"], 1)
        self.assertEqual(self.gh.calls.count(PREFIX + "/pulls/46"), 2)
        self.assertTrue(all(method == "GET" for method, _ in self.ao.calls))

    def test_head_base_branch_or_repository_changes_fail(self):
        for field, value in (("head", OTHER), ("base", OTHER), ("repo", 101), ("branch", OTHER)):
            with self.subTest(field=field):
                self.gh = FakeGitHub()
                if field in ("head", "base"):
                    self.gh.pr[field]["sha"] = value
                elif field == "repo":
                    self.gh.pr["head"]["repo"]["id"] = value
                else:
                    self.gh.branch["object"]["sha"] = value
                with self.assertRaises(PREFLIGHT.ReportError):
                    self.check()

    def test_stale_failed_or_foreign_review_fails(self):
        mutations = [("targetSha", OTHER), ("reviewId", "foreign"), ("sessionId", "other-worker"),
                     ("status", "running"), ("status", "failed"), ("verdict", "changes_requested"),
                     ("githubReviewId", ""), ("prUrl", PR_URL + "0")]
        for field, value in mutations:
            with self.subTest(field=field, value=value):
                self.ao = FakeAO()
                self.ao.run[field] = value
                with self.assertRaises(PREFLIGHT.ReportError):
                    self.check()
        self.ao = FakeAO()
        self.ao.current["latestRun"]["id"] = "run-newer"
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "superseded"):
            self.check()

    def test_review_provider_binding_and_actor_are_checked(self):
        for field, value in (("id", 501), ("commit_id", OTHER), ("state", "DISMISSED"), ("user", {"id": 201})):
            with self.subTest(field=field):
                self.gh = FakeGitHub()
                self.gh.review[field] = value
                with self.assertRaisesRegex(PREFLIGHT.ReportError, "Published GitHub review"):
                    self.check()

    def test_candidate_cannot_replace_trusted_check_definitions(self):
        self.gh.content["content"] = base64.b64encode(b"name: Quality\nrun: true\n").decode()
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "differs from trusted policy"):
            self.check()

    def test_missing_duplicated_and_skipped_required_jobs_fail(self):
        for mutation in ("missing", "duplicate", "skipped", "neutral", "cancelled", "in_progress", "other-head"):
            with self.subTest(mutation=mutation):
                self.gh = FakeGitHub()
                if mutation == "missing":
                    self.gh.jobs.pop()
                elif mutation == "duplicate":
                    self.gh.jobs.append(copy.deepcopy(self.gh.jobs[0]))
                elif mutation == "in_progress":
                    self.gh.jobs[0]["status"] = mutation
                elif mutation == "other-head":
                    self.gh.jobs[0]["head_sha"] = OTHER
                else:
                    self.gh.jobs[0]["conclusion"] = mutation
                with self.assertRaises(PREFLIGHT.ReportError):
                    self.check()

    def test_same_named_check_from_wrong_app_or_suite_fails(self):
        for field, value in (("app", {"id": 401}), ("check_suite", {"id": 701}), ("head_sha", OTHER),
                             ("name", "Not Quality"), ("status", "queued"), ("conclusion", "failure")):
            with self.subTest(field=field):
                self.gh = FakeGitHub()
                self.gh.checks[800][field] = value
                with self.assertRaisesRegex(PREFLIGHT.ReportError, "check producer or binding"):
                    self.check()
        self.gh = FakeGitHub()
        self.gh.jobs[0]["check_run_url"] = "https://evil.example/checks/800"
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "check URL"):
            self.check()

    def test_failed_latest_run_cannot_fall_back_to_older_success(self):
        older = {**self.gh.run, "id": 599, "run_number": 6}
        self.gh.runs.append(older)
        self.gh.run["conclusion"] = "failure"
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "Latest required workflow"):
            self.check()
        self.gh.run.update(status="queued", conclusion=None)
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "Latest required workflow"):
            self.check()

    def test_rerun_uses_latest_attempt_and_rejects_inflight_attempt(self):
        self.gh.run["run_attempt"] = 2
        self.check()
        self.assertIn(PREFIX + "/actions/runs/600/attempts/2/jobs?per_page=100", self.gh.calls)
        self.gh.run["status"] = "in_progress"
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "has not succeeded"):
            self.check()

    def test_wrong_workflow_base_event_or_synthetic_head_not_assumed_equivalent(self):
        for field, value in (("path", ".github/workflows/other.yml"), ("workflow_id", 301),
                             ("event", "push"), ("head_sha", OTHER), ("head_repository", {"id": 101})):
            with self.subTest(field=field):
                self.gh = FakeGitHub()
                self.gh.run[field] = value
                with self.assertRaises(PREFLIGHT.ReportError):
                    self.check()
        self.gh = FakeGitHub()
        self.gh.run["pull_requests"][0]["base"]["sha"] = OTHER
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "base/head"):
            self.check()

    def test_partial_pagination_and_ambiguous_run_are_rejected(self):
        self.gh.extra_total = 1
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "Incomplete"):
            self.check()
        self.gh.extra_total = 0
        self.gh.runs.append({**self.gh.run, "id": 601})
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "ambiguous"):
            self.check()

    def test_changed_evidence_during_reads_fails(self):
        counts = {"reads": 0}

        def mutate(endpoint):
            if endpoint == PREFIX + "/pulls/46":
                counts["reads"] += 1
                if counts["reads"] == 2:
                    self.gh.pr["head"]["sha"] = OTHER

        self.gh.on_read = mutate
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "base/head"):
            self.check()
        self.gh = FakeGitHub()

        def supersede(path):
            if path.endswith("/reviews") and len(self.ao.calls) > 3:
                self.ao.current["latestRun"]["id"] = "run-2"

        self.ao.on_read = supersede
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "superseded"):
            self.check()

    def test_new_successful_attempt_between_snapshots_requires_fresh_preflight(self):
        counts = {"runs": 0}

        def rerun(endpoint):
            if endpoint == PREFIX + "/actions/runs/600":
                counts["runs"] += 1
                if counts["runs"] == 2:
                    self.gh.run["run_attempt"] = 2

        self.gh.on_read = rerun
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "Evidence changed during preflight"):
            self.check()

    def test_policy_must_be_digest_pinned_and_rejects_duplicate_or_unknown_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "policy.json"
            raw = json.dumps(self.policy).encode()
            path.write_bytes(raw)
            digest = hashlib.sha256(raw).hexdigest()
            self.assertEqual(PREFLIGHT.read_policy(path, digest), self.policy)
            with self.assertRaisesRegex(PREFLIGHT.ReportError, "trusted digest"):
                PREFLIGHT.read_policy(path, "0" * 64)
            duplicate = raw[:-1] + b',"schemaVersion":1}'
            path.write_bytes(duplicate)
            with self.assertRaisesRegex(PREFLIGHT.ReportError, "duplicate"):
                PREFLIGHT.read_policy(path, hashlib.sha256(duplicate).hexdigest())
        self.policy["allowMerge"] = True
        with self.assertRaisesRegex(PREFLIGHT.ReportError, "policy fields"):
            self.check()

    def test_policy_requires_workflow_digest_and_nonempty_job_set(self):
        for ci_value in ({"requiredJobs": []}, {"requiredJobs": ["Quality", "Quality"]},
                         {"definitionFiles": {}}, {"workflowPath": "../../unsafe.yml"}):
            with self.subTest(ci_value=ci_value):
                self.policy = policy()
                self.policy["ci"].update(ci_value)
                with self.assertRaises(PREFLIGHT.ReportError):
                    self.check()

    def test_github_transport_is_explicit_get_fixed_host_and_absolute_tool(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "gh"
            executable.write_text("unused")
            executable.chmod(0o700)
            provider = PREFLIGHT.GitHub(str(executable))
            result = subprocess.CompletedProcess([], 0, b'{"ok":true}', b"")
            with mock.patch.object(PREFLIGHT.subprocess, "run", return_value=result) as run:
                self.assertTrue(provider.get(PREFIX)["ok"])
            self.assertEqual(run.call_args.args[0], [str(executable), "api", "--hostname", "github.com",
                                                    "--method", "GET", PREFIX])
            with self.assertRaises(PREFLIGHT.ReportError):
                provider.get("https://evil.example/path")
            with mock.patch.object(PREFLIGHT.subprocess, "run", side_effect=subprocess.TimeoutExpired("gh", 20)):
                with self.assertRaisesRegex(PREFLIGHT.ReportError, "timed out"):
                    provider.get(PREFIX)
        with self.assertRaises(PREFLIGHT.ReportError):
            PREFLIGHT.GitHub("gh")

    def test_cli_failure_still_explicitly_denies_merge(self):
        with mock.patch.object(PREFLIGHT, "read_policy", side_effect=PREFLIGHT.ReportError("Unavailable")), \
                mock.patch("builtins.print") as output:
            code = PREFLIGHT.main(["--policy", "/missing", "--policy-sha256", "0" * 64,
                                   "--ao-run-file", "/running.json", "--gh", "/usr/bin/gh"])
        self.assertEqual(code, 1)
        result = json.loads(output.call_args.args[0])
        self.assertFalse(result["observedEvidenceReady"])
        self.assertFalse(result["mergeAuthorized"])
        self.assertEqual(result["reason"], "Unavailable")


if __name__ == "__main__":
    unittest.main()
