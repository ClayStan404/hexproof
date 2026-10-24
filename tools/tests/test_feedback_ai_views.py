# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Compact reads and immutable progress preparation still consult fresh receiver state."""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import json
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

from test_feedback_ai import AI, BINDING, CASE, OUTPUT, QUESTION, ROOT, config, native_server, private_json


def snapshot():
    return {"CaseID": CASE, "State": "active", "SourceRevision": 4, "InputRevision": 2,
            "RevocationRevision": 0, "LatestProjection": None, "QuestionPublication": None,
            "Contributions": [{"ID": CASE, "Revision": 1, "Digest": "c" * 64,
                "Description": "Original report details", "Context": {"platform": "Linux"},
                "Text": "Compatibility text", "Attachments": []}],
            "PublishedProjections": [], "Replies": [], "DeliveryHistory": []}


def decision():
    return {"caseId": CASE, "expectedInputRevision": 2,
            "workState": "implementing", "summary": "AI 团队正在修复这个问题。"}


def observation(identifier=OUTPUT, revision=3, state="published"):
    return {"ID": identifier, "WorkflowRevision": revision,
            "ExpectedInputRevision": 2, "PublicationState": state}


class FeedbackAIViewsTests(unittest.TestCase):
    def invoke(self, connection, value, command="read", extra=()):
        path = Path(connection["socket"]).parent / "connection.json"
        private_json(path, connection)
        return self.run_command(path, value, command, extra)

    def run_command(self, connection_path, value, command, extra):
        return subprocess.run([sys.executable, str(ROOT / "tools/feedback-ai.py"), command,
                               "--connection", str(connection_path), *extra],
                              input=json.dumps(value).encode(), capture_output=True, timeout=10)

    def test_summary_saves_full_bound_snapshot_and_only_prints_compact_state(self):
        current = snapshot()
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": current}) as (connection, requests):
            output = Path(directory) / "snapshot.json"
            result = self.invoke(connection, {"caseId": CASE}, extra=("--view", "summary", "--output", str(output)))
            self.assertEqual(result.returncode, 0, result.stderr)
            view = json.loads(result.stdout)["view"]
            self.assertEqual(view["binding"], BINDING)
            self.assertEqual(view["ContributionCount"], 1)
            self.assertNotIn(b"Original report details", result.stdout)
            self.assertEqual(json.loads(output.read_text()), AI.bound_document("feedback-snapshot", connection, snapshot=current))
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            self.assertEqual(json.loads(requests[0][1]), {"action": "snapshot", "caseId": CASE, "binding": BINDING})

    def test_changes_read_fresh_content_and_keep_named_publication_evidence(self):
        previous = snapshot()
        current = deepcopy(previous)
        current.update(SourceRevision=7, InputRevision=3)
        current["Contributions"].append({"ID": QUESTION, "Description": "New reproduction",
                                         "Context": {}, "Text": "Repeated compatibility body"})
        current["PublishedProjections"] = [{"ID": OUTPUT, "WorkflowRevision": 3,
            "ExpectedInputRevision": 2, "PublishedAt": "2026-10-25T01:00:00Z", "Summary": "An earlier result"}]
        current["Replies"] = [{"ID": "44444444-4444-4444-8444-444444444444", "QuestionID": OUTPUT, "QuestionRevision": 1,
                                "ReceivedAt": "2026-10-25T01:01:00Z", "PublicationState": "pending"}]
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": current}) as (connection, requests):
            before = private_json(Path(directory) / "before.json", AI.bound_document("feedback-snapshot", connection, snapshot=previous))
            after = Path(directory) / "after.json"
            result = self.invoke(connection, {"caseId": CASE}, extra=("--view", "changes", "--since", str(before),
                "--output", str(after), "--receipt", OUTPUT))
            self.assertEqual(result.returncode, 0, result.stderr)
            view = json.loads(result.stdout)["view"]
            self.assertEqual([row["ID"] for row in view["NewContributions"]], [QUESTION])
            self.assertNotIn("Text", view["NewContributions"][0])
            self.assertEqual(view["RequestedReceipt"]["PublicationState"], "published")
            self.assertEqual(view["RequestedReceipt"]["ExpectedInputRevision"], 2)
            self.assertEqual(view["UnpublishedReplies"], current["Replies"])
            self.assertIsNone(view["LatestPublishedProjection"], "An old result is not a result for newer user input")
            self.assertEqual(len(requests), 1)
            self.assertEqual(json.loads(before.read_text())["snapshot"], previous)
            self.assertEqual(json.loads(after.read_text())["snapshot"], current)

    def test_changes_cannot_cross_binding_case_or_regress_revisions(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": snapshot()}) as (connection, requests):
            previous = Path(directory) / "previous.json"
            output = Path(directory) / "new.json"
            for mutate in (lambda doc: doc.update(binding="f" * 64),
                           lambda doc: doc["snapshot"].update(CaseID=QUESTION),
                           lambda doc: doc["snapshot"].update(SourceRevision=99)):
                doc = AI.bound_document("feedback-snapshot", connection, snapshot=snapshot())
                mutate(doc)
                private_json(previous, doc)
                result = self.invoke(connection, {"caseId": CASE}, extra=("--view", "changes", "--since", str(previous), "--output", str(output)))
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())
            self.assertEqual(len(requests), 3, "A prior file never substitutes for a fresh receiver read")

    def test_compact_output_never_overwrites_snapshot_or_previous_reference(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": snapshot()}) as (connection, requests):
            output = private_json(Path(directory) / "saved.json", {"keep": "private evidence"})
            original = output.read_bytes()
            result = self.invoke(connection, {"caseId": CASE}, extra=("--view", "summary", "--output", str(output)))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            self.assertNotIn(b"private evidence", result.stderr)
            requests.clear()
            result = self.invoke(connection, {"caseId": CASE}, extra=("--view", "changes", "--since", str(output), "--output", str(output)))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(requests, [])

    def test_closed_removed_and_unobserved_receipts_do_not_replay_cached_results(self):
        previous = AI.bound_document("feedback-snapshot", config(), snapshot=snapshot())
        for state in ("closed", "removed"):
            current = snapshot()
            current.update(State=state, SourceRevision=1, RevocationRevision=1, Contributions=[])
            view = AI.read_view(current, config(), "changes", previous, OUTPUT)["view"]
            self.assertEqual(view["State"], state)
            self.assertNotIn("NewContributions", view)
            self.assertNotIn("LatestPublishedProjection", view)
            self.assertEqual(view["RequestedReceipt"]["Observation"], "unavailable-for-case-state")
        current = snapshot()
        current["LatestProjection"] = observation(state="pending")
        self.assertEqual(AI.read_view(current, config(), "summary", receipt_id=OUTPUT)["view"]["RequestedReceipt"], current["LatestProjection"])
        self.assertEqual(AI.read_view(current, config(), "summary", receipt_id=QUESTION)["view"]["RequestedReceipt"]["Observation"], "not-in-current-snapshot")

    def test_prepare_reads_only_persists_stable_intent_and_needs_explicit_send(self):
        current = snapshot()
        current["LatestProjection"] = observation()
        def response(request):
            if request["action"] == "snapshot":
                return {"snapshot": current}
            return {"projection": {"id": request["projection"]["id"], "publicationState": "pending"}}
        with tempfile.TemporaryDirectory() as directory, native_server(directory, response) as (connection, requests):
            output = Path(directory) / "intent.json"
            first = self.invoke(connection, decision(), "prepare", ("--output", str(output)))
            self.assertEqual(first.returncode, 0, first.stderr)
            original = output.read_bytes()
            second = self.invoke(connection, decision(), "prepare", ("--output", str(output)))
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(second.stdout, first.stdout)
            self.assertEqual(output.read_bytes(), original)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            saved = json.loads(original)
            projection = saved["intent"]["projection"]
            self.assertRegex(projection["id"], AI.UUID)
            self.assertEqual(projection["workflowRevision"], 4)
            self.assertEqual(projection["expectedInputRevision"], 2)
            self.assertTrue(all(json.loads(raw)["action"] == "snapshot" for _, raw in requests))
            sent = self.invoke(connection, {}, "progress", ("--input", str(output)))
            self.assertEqual(sent.returncode, 0, sent.stderr)
            self.assertEqual(json.loads(requests[-1][1])["projection"], projection)
            self.assertNotIn("kind", json.loads(requests[-1][1]))

    def test_saved_intent_replay_requires_current_input_and_no_workflow_conflict(self):
        current = snapshot()
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": current}) as (connection, requests):
            output = Path(directory) / "intent.json"
            result = self.invoke(connection, decision(), "prepare", ("--output", str(output)))
            self.assertEqual(result.returncode, 0, result.stderr)
            original = output.read_bytes()
            for patch in ({"InputRevision": 3}, {"State": "closed"}, {"State": "removed"},
                          {"LatestProjection": observation(revision=9)}):
                current.clear()
                current.update(snapshot(), **patch)
                result = self.invoke(connection, decision(), "prepare", ("--output", str(output)))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertEqual(output.read_bytes(), original)
            self.assertTrue(all(json.loads(raw)["action"] == "snapshot" for _, raw in requests))

    def test_prepare_preserves_observed_pending_intent_but_does_not_make_another(self):
        current = snapshot()
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": current}) as (connection, requests):
            output = Path(directory) / "intent.json"
            first = self.invoke(connection, decision(), "prepare", ("--output", str(output)))
            self.assertEqual(first.returncode, 0, first.stderr)
            saved = json.loads(output.read_text())["intent"]["projection"]
            current["LatestProjection"] = observation(saved["id"], saved["workflowRevision"], "pending")
            replay = self.invoke(connection, decision(), "prepare", ("--output", str(output)))
            self.assertEqual(replay.returncode, 0, replay.stderr)
            self.assertEqual(json.loads(replay.stdout)["prepared"]["observedReceipt"]["PublicationState"], "pending")
            fresh = Path(directory) / "another.json"
            self.assertNotEqual(self.invoke(connection, decision(), "prepare", ("--output", str(fresh))).returncode, 0)
            self.assertFalse(fresh.exists())
            self.assertTrue(all(json.loads(raw)["action"] == "snapshot" for _, raw in requests))

    def test_prepare_cannot_replace_text_or_rebind_the_same_file(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": snapshot()}) as (connection, _requests):
            output = Path(directory) / "intent.json"
            self.assertEqual(self.invoke(connection, decision(), "prepare", ("--output", str(output))).returncode, 0)
            original = output.read_bytes()
            changed = decision()
            changed["summary"] = "A different intentional message"
            self.assertNotEqual(self.invoke(connection, changed, "prepare", ("--output", str(output))).returncode, 0)
            other = {**connection, "binding": "f" * 64}
            self.assertNotEqual(self.invoke(other, decision(), "prepare", ("--output", str(output))).returncode, 0)
            self.assertEqual(output.read_bytes(), original)

    def test_concurrent_preparations_converge_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": snapshot()}) as (connection, requests):
            config_path = private_json(Path(directory) / "connection.json", connection)
            output = Path(directory) / "intent.json"
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda _: self.run_command(config_path, decision(), "prepare", ("--output", str(output))), range(2)))
            self.assertTrue(all(result.returncode == 0 for result in results), [r.stderr for r in results])
            self.assertEqual(results[0].stdout, results[1].stdout)
            self.assertEqual(len(requests), 2)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_prepare_rejects_unsafe_files_and_unsupported_decisions_without_sending(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": snapshot()}) as (connection, requests):
            output = Path(directory) / "intent.json"
            fifo = Path(directory) / "fifo"
            AI.os.mkfifo(fifo, 0o600)
            link = Path(directory) / "link"
            link.symlink_to(output)
            for path in (fifo, link):
                self.assertNotEqual(self.invoke(connection, decision(), "prepare", ("--output", str(path))).returncode, 0)
            for state in ("released", "source-published-awaiting-release", "needs-information", "assessing", []):
                value = {**decision(), "workState": state}
                self.assertNotEqual(self.invoke(connection, value, "prepare", ("--output", str(output))).returncode, 0)
            self.assertEqual(requests, [])
            self.assertFalse(output.exists())

    def test_view_and_prepare_option_errors_fail_before_connecting(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory, {"snapshot": snapshot()}) as (connection, requests):
            cases = [("read", {"caseId": CASE}, ("--view", "summary")),
                     ("read", {"caseId": CASE}, ("--view", "changes", "--output", str(Path(directory) / "s.json"))),
                     ("read", {"caseId": CASE}, ("--receipt", OUTPUT)),
                     ("prepare", decision(), ()),
                     ("prepare", decision(), ("--view", "summary", "--output", str(Path(directory) / "p.json")))]
            for command, value, extra in cases:
                self.assertNotEqual(self.invoke(connection, value, command, extra).returncode, 0)
            self.assertEqual(requests, [])


if __name__ == "__main__":
    unittest.main()
