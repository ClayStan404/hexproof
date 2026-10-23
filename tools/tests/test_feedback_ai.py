# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""The native task tool keeps identities stable and private publication mappings local."""

from contextlib import contextmanager
from copy import deepcopy
import http.server
import importlib.util
import json
import os
from pathlib import Path
import socketserver
import stat
import subprocess
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("feedback_ai", ROOT / "tools/feedback-ai.py")
AI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AI)
CASE = "11111111-1111-4111-8111-111111111111"
OUTPUT = "22222222-2222-4222-8222-222222222222"
QUESTION = "33333333-3333-4333-8333-333333333333"
BINDING = "a" * 64
SOURCE = "b" * 40
PUBLIC = "c" * 40
REPOSITORY = "example/public-project"


def config(path="/tmp/feedback-native.sock"):
    return {"schemaVersion": 1, "socket": path, "binding": BINDING, "publicRepository": REPOSITORY}


def intent(state="assessing"):
    return {"caseId": CASE, "projection": {"id": OUTPUT, "workflowRevision": 5,
            "expectedInputRevision": 3, "workState": state, "summary": "The AI team is investigating this report."}}


def publication_receipt():
    return {"state": "published", "publicCommit": PUBLIC, "observedPublicHead": "d" * 40,
            "historicalSourceMapping": "verified", "intent": {
                "schemaVersion": 1, "sourceCommit": SOURCE, "sourceRef": "refs/heads/master",
                "publicRepository": "git@github.com:example/public-project.git", "publicRef": "refs/heads/master",
                "publicParent": "e" * 40, "baselineSourceCommit": "f" * 40,
                "adoptPublicParent": False, "exportPolicyDigest": "1" * 64},
            "export": {"schemaVersion": 1, "sourceCommit": SOURCE,
                       "exportPolicyDigest": "1" * 64, "exportTreeDigest": "2" * 64}}


def outcome(kind="release"):
    value = intent({"source": "source-published-awaiting-release", "release": "released", "duplicate": "duplicate"}[kind])
    value["projection"]["outcome"] = {"kind": kind, "repository": REPOSITORY}
    if kind == "release":
        value["projection"]["outcome"].update(tag="v3.1.0", version="3.1.0")
    elif kind == "duplicate":
        value["projection"]["outcome"]["issueNumber"] = 123
    return value


def private_json(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(0o600)
    return path


@contextmanager
def native_server(directory, reply=None, status=200, raw_reply=None):
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            raw = self.rfile.read(int(self.headers["Content-Length"]))
            requests.append((self.path, raw))
            request = json.loads(raw)
            result = reply if reply is not None else {"projection": {"id": request["projection"]["id"], "publicationState": "pending"}}
            body = raw_reply if raw_reply is not None else json.dumps(result).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    path = str(Path(directory) / "native.sock")
    server = socketserver.UnixStreamServer(path, Handler)
    os.chmod(path, 0o600)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    thread.start()
    try:
        yield config(path), requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


class FeedbackAITests(unittest.TestCase):
    def invoke(self, connection, value, command="reply", extra=(), raw=None):
        path = Path(connection["socket"]).parent / "connection.json"
        private_json(path, connection)
        return subprocess.run([sys.executable, str(ROOT / "tools/feedback-ai.py"), command,
                               "--connection", str(path), *extra], input=raw if raw is not None else json.dumps(value).encode(),
                              capture_output=True, timeout=10)

    def test_retries_send_identical_intent_and_return_only_requested_receipt(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory) as (connection, requests):
            first = self.invoke(connection, intent())
            second = self.invoke(connection, intent())
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.stdout, first.stdout)
            self.assertEqual(requests[0], requests[1])
            self.assertEqual(requests[0][0], "/public-native")
            body = json.loads(requests[0][1])
            self.assertEqual(body, {"action": "project", "caseId": CASE, "binding": BINDING,
                                    "projection": intent()["projection"]})
            self.assertEqual(json.loads(first.stdout), {"projection": {"id": OUTPUT, "publicationState": "pending"}})
            self.assertNotIn(BINDING.encode(), first.stdout + first.stderr)

    def test_read_returns_structured_current_snapshot_and_closure(self):
        for state in ("active", "closed", "removed"):
            snapshot = {"CaseID": CASE, "State": state, "InputRevision": 4, "Contributions": []}
            with self.subTest(state=state), tempfile.TemporaryDirectory() as directory:
                with native_server(directory, {"snapshot": snapshot}) as (connection, requests):
                    result = self.invoke(connection, {"caseId": CASE}, "read")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout), {"snapshot": snapshot})
                    self.assertEqual(json.loads(requests[0][1]), {"action": "snapshot", "caseId": CASE, "binding": BINDING})

    def test_custom_question_and_development_progress_keep_explicit_revisions(self):
        value = intent("needs-information")
        value["projection"]["question"] = {"id": QUESTION, "revision": 2, "code": "custom",
            "description": "请说明是在哪个模式、哪张牌结算时出现的问题。", "timeoutSeconds": 86400}
        request = AI.build_request("ask", value, config())
        self.assertEqual(request["projection"], value["projection"])
        for state in AI.PROGRESS:
            self.assertEqual(AI.build_request("progress", intent(state), config())["projection"]["workState"], state)

    def test_missing_or_implicit_identity_and_revision_never_generate_output(self):
        for key in ("id", "workflowRevision", "expectedInputRevision"):
            value = intent()
            del value["projection"][key]
            with self.subTest(key=key), self.assertRaises(AI.ToolError):
                AI.build_request("reply", value, config())
        for key, bad in (("id", CASE), ("id", "fresh"), ("workflowRevision", True),
                         ("workflowRevision", 0), ("expectedInputRevision", 1.5)):
            value = intent()
            value["projection"][key] = bad
            with self.subTest(key=key, bad=bad), self.assertRaises(AI.ToolError):
                AI.build_request("reply", value, config())

    def test_command_shape_does_not_smuggle_private_fields_or_unproven_outcome(self):
        candidates = []
        for key in ("privateCommit", "reviewLog", "authorization", "action"):
            value = intent()
            value["projection"][key] = "private-test-value"
            candidates.append(("reply", value))
        candidates.extend([("reply", intent("released")), ("progress", intent("ready")),
                           ("ask", intent("needs-information")), ("outcome", intent("duplicate"))])
        for command, value in candidates:
            with self.subTest(command=command, value=value), self.assertRaises(AI.ToolError):
                AI.build_request(command, value, config())

    def test_source_and_release_use_only_bound_public_mapping(self):
        receipt = publication_receipt()
        for kind in ("source", "release"):
            value = outcome(kind)
            before = deepcopy(value)
            request = AI.build_request("outcome", value, config(), receipt, SOURCE)
            self.assertEqual(request["projection"]["outcome"]["commit"], PUBLIC)
            self.assertEqual(value, before)
            raw = AI.encode(request).decode()
            for private in (SOURCE, receipt["intent"]["baselineSourceCommit"], "sourceCommit", "exportTreeDigest", "sourceRef"):
                self.assertNotIn(private, raw)
            self.assertEqual(AI.build_request("outcome", value, config(), receipt, SOURCE), request)
        self.assertEqual(receipt, publication_receipt())

    def test_receipt_state_repository_source_export_and_public_mapping_are_bound(self):
        mutations = [lambda r: r.update(state="prepared"), lambda r: r.update(state="uncertain"),
                     lambda r: r.update(publicCommit=SOURCE), lambda r: r.update(observedPublicHead="bad"),
                     lambda r: r["intent"].update(publicRepository="https://github.com/private/other"),
                     lambda r: r["intent"].update(publicRepository="https://secret@github.com/example/public-project"),
                     lambda r: r["intent"].update(publicRepository="/tmp/unpublished-local.git"),
                     lambda r: r["intent"].update(sourceCommit="f" * 40),
                     lambda r: r["export"].update(sourceCommit="f" * 40),
                     lambda r: r["export"].update(exportPolicyDigest="3" * 64),
                     lambda r: r["intent"].update(schemaVersion=True)]
        for mutate in mutations:
            receipt = publication_receipt()
            mutate(receipt)
            with self.subTest(receipt=receipt), self.assertRaises(AI.ToolError):
                AI.public_commit(receipt, REPOSITORY, SOURCE)
        receipt = publication_receipt()
        receipt["intent"]["publicRepository"] = "https://github.com/example/public-project.git"
        self.assertEqual(AI.public_commit(receipt, REPOSITORY, SOURCE), PUBLIC)

    def test_release_must_use_intended_mapping_and_matching_tag_version(self):
        for change in ({"commit": SOURCE}, {"version": "3.2.0"}, {"tag": "private-branch"},
                       {"repository": "private/other"}, {"issueNumber": 4}):
            value = outcome()
            value["projection"]["outcome"].update(change)
            with self.subTest(change=change), self.assertRaises(AI.ToolError):
                AI.build_request("outcome", value, config(), publication_receipt(), SOURCE)
        with self.assertRaises(AI.ToolError):
            AI.build_request("outcome", outcome(), config())
        with self.assertRaises(AI.ToolError):
            AI.build_request("outcome", outcome(), config(), publication_receipt(), "f" * 40)
        value = outcome()
        value["projection"]["summary"] = "The private change was " + SOURCE.upper()
        with self.assertRaises(AI.ToolError):
            AI.build_request("outcome", value, config(), publication_receipt(), SOURCE)

    def test_duplicate_uses_fixed_public_repository_without_private_mapping(self):
        value = outcome("duplicate")
        self.assertEqual(AI.build_request("outcome", value, config())["projection"], value["projection"])
        with self.assertRaises(AI.ToolError):
            AI.build_request("outcome", value, config(), publication_receipt(), SOURCE)
        value["projection"]["outcome"]["issueNumber"] = True
        with self.assertRaises(AI.ToolError):
            AI.build_request("outcome", value, config())

    def test_outcome_numeric_bounds_match_receiver_contract(self):
        value = outcome("duplicate")
        value["projection"]["outcome"]["issueNumber"] = 2147483647
        AI.build_request("outcome", value, config())
        value["projection"]["outcome"]["issueNumber"] += 1
        with self.assertRaises(AI.ToolError):
            AI.build_request("outcome", value, config())
        value = outcome()
        value["projection"]["outcome"].update(version="999999999.0.999999999", tag="v999999999.0.999999999")
        AI.build_request("outcome", value, config(), publication_receipt(), SOURCE)
        for version in ("1000000000.0.0", "1.1000000000.0", "1.0.1000000000"):
            value["projection"]["outcome"].update(version=version, tag="v" + version)
            with self.subTest(version=version), self.assertRaises(AI.ToolError):
                AI.build_request("outcome", value, config(), publication_receipt(), SOURCE)

    def test_source_receipt_file_never_enters_native_request_or_output(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory) as (connection, requests):
            receipt = private_json(Path(directory) / "publication.json", publication_receipt())
            result = self.invoke(connection, outcome(), "outcome", ("--publication-receipt", str(receipt), "--source-commit", SOURCE))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(requests[0][1])["projection"]["outcome"]["commit"], PUBLIC)
            self.assertNotIn(SOURCE.encode(), result.stdout + result.stderr + requests[0][1])

    def test_invalid_json_and_oversized_input_do_not_connect_or_echo_values(self):
        with tempfile.TemporaryDirectory() as directory:
            connection = config(str(Path(directory) / "does-not-exist.sock"))
            for raw in (b'{"private":"do-not-print-me",', b'{"caseId":1,"caseId":2}',
                        b'{"caseId":NaN}', b" " * (AI.MAX_INPUT + 1)):
                result = self.invoke(connection, None, raw=raw)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertNotIn(b"do-not-print-me", result.stderr)
                self.assertNotIn(b"connection failed", result.stderr)

    def test_private_file_permissions_symlinks_and_nonregular_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            path = private_json(Path(directory) / "input.json", {"caseId": CASE})
            self.assertEqual(AI.read_private_json(path, AI.MAX_INPUT), {"caseId": CASE})
            path.chmod(0o644)
            with self.assertRaises(AI.ToolError):
                AI.read_private_json(path, AI.MAX_INPUT)
            path.chmod(0o600)
            link = Path(directory) / "link.json"
            link.symlink_to(path)
            with self.assertRaises(AI.ToolError):
                AI.read_private_json(link, AI.MAX_INPUT)
            fifo = Path(directory) / "pipe"
            os.mkfifo(fifo, 0o600)
            with self.assertRaises(AI.ToolError):
                AI.read_private_json(fifo, AI.MAX_INPUT)

    def test_rejected_or_misbound_responses_do_not_print_server_body(self):
        responses = [(403, b'{"error":"private-server-value"}'),
                     (200, b'{"projection":{"id":"wrong","publicationState":"pending"}}'),
                     (200, b'{"projection":{"id":"wrong","publicationState":"private-server-value"}}'),
                     (200, b"private-server-value"), (200, b" " * (AI.MAX_RESPONSE + 1))]
        for status, raw in responses:
            with self.subTest(status=status, size=len(raw)), tempfile.TemporaryDirectory() as directory:
                with native_server(directory, status=status, raw_reply=raw) as (connection, _requests):
                    result = self.invoke(connection, intent())
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, b"")
                    self.assertNotIn(b"private-server-value", result.stderr)

    def test_output_is_private_and_never_replaces_symlink(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory) as (connection, _requests):
            output = Path(directory) / "receipt.json"
            output.write_text("old")
            output.chmod(0o644)
            result = self.invoke(connection, intent(), extra=("--output", str(output)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            self.assertEqual(json.loads(output.read_text())["projection"]["id"], OUTPUT)
            link = Path(directory) / "link.json"
            link.symlink_to(output)
            with self.assertRaises(AI.ToolError):
                AI.write_output(link, {"bad": True})
            self.assertEqual(json.loads(output.read_text())["projection"]["id"], OUTPUT)

    def test_invalid_output_is_rejected_before_any_publication_attempt(self):
        with tempfile.TemporaryDirectory() as directory, native_server(directory) as (connection, requests):
            for output in ("relative.json", str(Path(directory) / "connection.json"),
                           str(Path(directory) / "missing" / "receipt.json")):
                result = self.invoke(connection, intent(), extra=("--output", output))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(requests, [])


if __name__ == "__main__":
    unittest.main()
