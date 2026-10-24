#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Read or intentionally publish one public feedback operation over its native socket."""

import argparse
import http.client
import json
import os
from pathlib import Path
import re
import socket
import stat
import sys
import tempfile
import uuid


MAX_INPUT = 16 << 10
MAX_RESPONSE = 2 << 20
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
HASH = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
VERSION = re.compile(r"(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})")
ASSESSMENTS = {"assessing", "ready", "declined", "deferred", "blocked"}
PROGRESS = {"implementing", "verifying", "verified-awaiting-review", "reviewing",
            "verifying-integration", "merge-ready", "merging", "merged-awaiting-release"}
OUTCOMES = {"duplicate": "duplicate", "source-published-awaiting-release": "source", "released": "release"}
QUESTION_CODES = {"custom", "reproduction_steps", "expected_actual", "affected_version", "platform",
                  "minimal_public_example", "user_goal"}


class ToolError(ValueError):
    """A fixed, credential-free explanation suitable for an automation caller."""


def require(condition, message):
    if not condition:
        raise ToolError(message)


def matches(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def integer(value, minimum=1, maximum=(1 << 63) - 1):
    return type(value) is int and minimum <= value <= maximum


def fields(value, required, optional=()):
    require(isinstance(value, dict) and set(required) <= value.keys()
            and value.keys() <= set(required) | set(optional), "Invalid JSON fields")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON fields")
        result[key] = value
    return result


def invalid_constant(_value):
    raise ToolError("Invalid JSON number")


def parse_json(raw, limit):
    require(len(raw) <= limit, "JSON exceeds the size limit")
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=invalid_constant)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ToolError("Invalid JSON document") from error


def read_private_json(path, limit):
    # Do not follow a final symlink or block opening a FIFO/device. Accepted public
    # text can still include accidental private data, so input files stay private.
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid()
                    and info.st_mode & 0o077 == 0, "JSON files must be owned private regular files (0600)")
            return parse_json(stream.read(limit + 1), limit)
    except OSError as error:
        raise ToolError("Cannot read the private JSON file") from error


def connection_config(value):
    fields(value, {"schemaVersion", "socket", "binding", "publicRepository"})
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1, "Invalid connection schema")
    require(isinstance(value["socket"], str) and os.path.isabs(value["socket"])
            and len(os.fsencode(value["socket"])) <= 100 and "\x00" not in value["socket"], "Invalid native socket path")
    require(matches(HASH, value["binding"]), "Invalid native binding")
    require(matches(REPOSITORY, value["publicRepository"]), "Invalid public repository")
    return value


def public_text(value):
    require(isinstance(value, str) and value.strip() and len(value.encode("utf-8")) <= 4096
            and all(ord(c) >= 32 or c in "\n\t" for c in value), "Invalid bounded public text")


def build_request(command, value, config):
    fields(value, {"caseId"} if command == "read" else {"caseId", "projection"})
    require(matches(UUID, value["caseId"]), "Invalid case UUIDv4")
    request = {"action": "snapshot" if command == "read" else "project", "caseId": value["caseId"],
               "binding": config["binding"]}
    if command == "read":
        return request
    # Preserve the caller's immutable intent, IDs, revisions and public text.
    projection = json.loads(json.dumps(value["projection"]))
    fields(projection, {"id", "workflowRevision", "expectedInputRevision", "workState", "summary"}, {"question", "outcome"})
    require(matches(UUID, projection["id"]) and projection["id"] != value["caseId"], "Invalid publication UUIDv4")
    require(integer(projection["workflowRevision"]) and integer(projection["expectedInputRevision"]), "Explicit positive revisions are required")
    public_text(projection["summary"])
    state = projection["workState"]
    require(isinstance(state, str), "Invalid public work state")
    allowed = {"read": set(), "ask": {"needs-information"}, "reply": ASSESSMENTS | PROGRESS,
               "progress": PROGRESS, "outcome": set(OUTCOMES)}[command]
    require(state in allowed, "Public work state does not match the requested operation")
    require((command == "ask") == ("question" in projection), "Questions require the ask operation")
    require((command == "outcome") == ("outcome" in projection), "Typed outcomes require the outcome operation")
    if command == "ask":
        question = projection["question"]
        fields(question, {"id", "revision", "code", "description", "timeoutSeconds"})
        require(matches(UUID, question["id"]) and integer(question["revision"], maximum=1000000)
                and isinstance(question["code"], str) and question["code"] in QUESTION_CODES
                and integer(question["timeoutSeconds"], 60, 30 * 86400), "Invalid public question")
        public_text(question["description"])
    if command == "outcome":
        outcome = projection["outcome"]
        kind = OUTCOMES[state]
        fields(outcome, {"kind", "repository"} | ({"issueNumber"} if kind == "duplicate" else set())
               | ({"tag", "version"} if kind == "release" else set())
               | ({"commit"} if kind != "duplicate" else set()))
        require(outcome["kind"] == kind and outcome["repository"] == config["publicRepository"], "Outcome does not match its state and configured repository")
        if kind == "duplicate":
            require(integer(outcome["issueNumber"], maximum=2147483647), "Invalid public issue number")
        else:
            require(matches(COMMIT, outcome["commit"]), "An explicit full public commit is required")
            # The receiver independently checks public repository/commit evidence
            # and release/tag ancestry before publishing this typed outcome.
        if kind == "release":
            require(matches(VERSION, outcome["version"]) and outcome["tag"] == "v" + outcome["version"], "Release tag and version must match")
    request["projection"] = projection
    require(len(encode(request)) <= MAX_INPUT, "Native request exceeds the size limit")
    return request


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


class NativeConnection(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=30)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)


def exchange(config, request):
    try:
        info = os.lstat(config["socket"])
        require(stat.S_ISSOCK(info.st_mode) and info.st_mode & 0o077 == 0, "Native endpoint must be a private Unix socket")
        connection = NativeConnection(config["socket"])
        try:
            connection.request("POST", "/public-native", encode(request),
                               {"Content-Type": "application/json", "Accept": "application/json"})
            response = connection.getresponse()
            require(response.status == 200, "Native receiver refused or could not confirm the operation; preserve the intent before retrying")
            result = parse_json(response.read(MAX_RESPONSE + 1), MAX_RESPONSE)
        finally:
            connection.close()
    except (OSError, http.client.HTTPException) as error:
        raise ToolError("Native connection failed; publication is unconfirmed, retry only the same saved intent") from error
    key = "snapshot" if request["action"] == "snapshot" else "projection"
    fields(result, {key})
    require(isinstance(result[key], dict), "Invalid native response")
    if key == "snapshot":
        require(result[key].get("CaseID") == request["caseId"]
                and result[key].get("State") in ("active", "closed", "removed"), "Native response does not match the requested case")
    else:
        fields(result[key], {"id", "publicationState"}, {"publishedAt"})
        require(result[key]["id"] == request["projection"]["id"]
                and result[key]["publicationState"] in ("pending", "partial", "published", "stalled", "rejected"),
                "Native receipt does not match the requested publication")
    return result


def write_output(path, result):
    raw = encode(result) + b"\n"
    if path is None:
        sys.stdout.buffer.write(raw)
        return
    target = Path(path)
    require(target.is_absolute() and not target.is_symlink(), "Output must be an absolute private path without a final symlink")
    with tempfile.NamedTemporaryFile(prefix=".feedback-ai-", dir=target.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)


def validate_output(path, inputs):
    if path is None:
        return
    target = Path(path)
    require(target.is_absolute() and not target.is_symlink() and target.parent.is_dir()
            and (not target.exists() or target.is_file()), "Output must be an absolute regular-file path in an existing directory")
    require(target.resolve() not in {Path(value).resolve() for value in inputs if value and value != "-"},
            "Output must not overwrite a connection, input or publication receipt")


def bound_document(kind, config, **content):
    return {"schemaVersion": 1, "kind": kind, "binding": config["binding"],
            "publicRepository": config["publicRepository"], **content}


def bound_content(document, kind, config, key):
    fields(document, {"schemaVersion", "kind", "binding", "publicRepository", key})
    require(type(document["schemaVersion"]) is int and document["schemaVersion"] == 1
            and document["kind"] == kind and document["binding"] == config["binding"]
            and document["publicRepository"] == config["publicRepository"],
            "Saved document does not match this native connection")
    return document[key]


def snapshot_metadata(snapshot):
    require(isinstance(snapshot, dict) and matches(UUID, snapshot.get("CaseID"))
            and snapshot.get("State") in ("active", "closed", "removed")
            and integer(snapshot.get("SourceRevision"))
            and integer(snapshot.get("InputRevision"), minimum=0)
            and integer(snapshot.get("RevocationRevision"), minimum=0), "Invalid snapshot metadata")
    latest = snapshot.get("LatestProjection")
    if latest is not None:
        fields(latest, {"ID", "WorkflowRevision", "ExpectedInputRevision", "PublicationState"})
        require(matches(UUID, latest["ID"]) and integer(latest["WorkflowRevision"])
                and integer(latest["ExpectedInputRevision"])
                and latest["PublicationState"] in ("pending", "partial", "published", "stalled", "rejected"),
                "Invalid projection observation")
    return {key: snapshot.get(key) for key in ("CaseID", "State", "SourceRevision", "InputRevision",
                                              "RevocationRevision", "LatestProjection", "QuestionPublication")}


def snapshot_rows(snapshot, key):
    rows = snapshot.get(key)
    if rows is None:
        rows = []
    require(isinstance(rows, list) and all(isinstance(row, dict) and matches(UUID, row.get("ID"))
                                          for row in rows), "Invalid snapshot observations")
    require(len({row["ID"] for row in rows}) == len(rows), "Duplicate snapshot observations")
    return rows


def read_view(snapshot, config, view, previous=None, receipt_id=None):
    result = {"binding": config["binding"], "publicRepository": config["publicRepository"],
              **snapshot_metadata(snapshot)}
    contributions = snapshot_rows(snapshot, "Contributions")
    published = snapshot_rows(snapshot, "PublishedProjections")
    require(all(integer(row.get("WorkflowRevision")) and integer(row.get("ExpectedInputRevision"))
                and isinstance(row.get("PublishedAt"), str) for row in published),
            "Invalid published projection metadata")
    result.update(ContributionCount=len(contributions), PublishedProjectionCount=len(published))
    if previous is not None:
        old = bound_content(previous, "feedback-snapshot", config, "snapshot")
        snapshot_metadata(old)
        require(old["CaseID"] == snapshot["CaseID"], "Previous snapshot belongs to another case")
        if snapshot["State"] == "active":
            require(old["State"] == "active" and old["SourceRevision"] <= snapshot["SourceRevision"]
                    and old["InputRevision"] <= snapshot["InputRevision"], "Snapshot revisions regressed")
    # Never replay cached history after closure/removal, even if a malformed
    # receiver response included it. A compact view is not a full assessment.
    if snapshot["State"] == "active":
        result["UnpublishedReplies"] = [{key: row.get(key) for key in
            ("ID", "QuestionID", "QuestionRevision", "ReceivedAt", "PublicationState")}
            for row in snapshot_rows(snapshot, "Replies") if row.get("PublicationState") != "published"]
        current = [p for p in published if p.get("ExpectedInputRevision") == snapshot["InputRevision"]]
        result["LatestPublishedProjection"] = current[-1] if current else None
        if view == "changes":
            old_contributions = {p["ID"]: p for p in snapshot_rows(old, "Contributions")}
            old_published = {p["ID"]: p for p in snapshot_rows(old, "PublishedProjections")}
            result["NewContributions"] = [{k: v for k, v in row.items()
                                          if k != "Text" or "Description" not in row or "Context" not in row}
                for row in contributions if old_contributions.get(row["ID"]) != row]
            result["NewPublishedProjections"] = [row for row in published if old_published.get(row["ID"]) != row]
            result["SinceSourceRevision"] = old["SourceRevision"]
    if receipt_id is not None:
        receipt = {"ID": receipt_id, "Observation": "not-in-current-snapshot"}
        if snapshot["State"] != "active":
            receipt["Observation"] = "unavailable-for-case-state"
        elif result["LatestProjection"] and result["LatestProjection"]["ID"] == receipt_id:
            receipt = result["LatestProjection"]
        else:
            match = next((row for row in published if row["ID"] == receipt_id), None)
            if match:
                receipt = {key: match[key] for key in ("ID", "WorkflowRevision", "ExpectedInputRevision", "PublishedAt")}
                receipt["PublicationState"] = "published"
        result["RequestedReceipt"] = receipt
    return {"view": result}


def save_once(path, document, limit):
    """Atomically install a complete 0600 file without replacing any existing intent."""
    target = Path(path)
    with tempfile.NamedTemporaryFile(prefix=".feedback-ai-", dir=target.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(encode(document) + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
            try:
                os.link(temporary, target)
            except FileExistsError:
                return read_private_json(target, limit)
            directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            temporary.unlink(missing_ok=True)
    return document


def progress_decision(value):
    fields(value, {"caseId", "expectedInputRevision", "workState", "summary"})
    require(matches(UUID, value["caseId"]) and integer(value["expectedInputRevision"])
            and isinstance(value["workState"], str) and value["workState"] in PROGRESS,
            "Preparation only supports explicit progress decisions")
    public_text(value["summary"])


def prepared_intent(document, config):
    value = bound_content(document, "prepared-progress", config, "intent")
    build_request("progress", value, config)
    return value


def prepare_progress(value, snapshot, config, output):
    progress_decision(value)
    snapshot_metadata(snapshot)
    require(snapshot["CaseID"] == value["caseId"] and snapshot["State"] == "active"
            and snapshot["InputRevision"] == value["expectedInputRevision"],
            "Case is closed, removed or has newer input; reconcile without rewriting the intent")
    latest = snapshot.get("LatestProjection")
    latest_revision = latest["WorkflowRevision"] if latest else 0
    target = Path(output)
    if target.exists() or target.is_symlink():
        saved = read_private_json(target, MAX_INPUT)
    else:
        require(latest is None or latest["PublicationState"] in ("published", "rejected"),
                "An existing publication is unresolved; reconcile before preparing another")
        projection = {"id": str(uuid.uuid4()), "workflowRevision": latest_revision + 1,
                      **{key: value[key] for key in ("expectedInputRevision", "workState", "summary")}}
        intent = {"caseId": value["caseId"], "projection": projection}
        build_request("progress", intent, config)
        saved = save_once(output, bound_document("prepared-progress", config, intent=intent), MAX_INPUT)
    intent = prepared_intent(saved, config)
    projection = intent["projection"]
    require(intent["caseId"] == value["caseId"]
            and all(projection[key] == value[key] for key in ("expectedInputRevision", "workState", "summary")),
            "Output already contains a different immutable intent")
    require((latest_revision < projection["workflowRevision"]
             and projection["workflowRevision"] == latest_revision + 1)
            or (latest is not None and latest["ID"] == projection["id"]
                and latest["WorkflowRevision"] == projection["workflowRevision"]
                and latest["ExpectedInputRevision"] == projection["expectedInputRevision"]),
            "Prepared intent conflicts with current workflow; preserve it and reconcile")
    return {"prepared": {"caseId": intent["caseId"], "projection": projection,
                         "sent": False, "observedReceipt": latest if latest and latest["ID"] == projection["id"] else None}}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("read", "prepare", "ask", "reply", "progress", "outcome"))
    parser.add_argument("--connection", required=True, help="Private JSON with socket, binding and fixed public repository")
    parser.add_argument("--input", default="-", help="Private intentional-operation JSON file; '-' reads bounded stdin")
    parser.add_argument("--output", help="Atomically write the requested result to a private absolute path instead of stdout")
    parser.add_argument("--view", choices=("summary", "changes"), help="Read a compact view and retain the full snapshot in --output")
    parser.add_argument("--since", help="Previous private full snapshot saved by a compact read; only for --view changes")
    parser.add_argument("--receipt", help="Projection UUID to observe in the fresh compact snapshot")
    args = parser.parse_args(argv)
    try:
        require(not (args.view or args.since or args.receipt) or args.command == "read",
                "View options are only accepted for read")
        require((args.view == "changes") == (args.since is not None), "Changes view requires exactly one previous snapshot")
        require(not args.receipt or args.view and matches(UUID, args.receipt), "Receipt lookup requires a compact view and UUIDv4")
        require(not (args.view or args.command == "prepare") or args.output is not None,
                "Compact reads and preparation require a private output file")
        config = connection_config(read_private_json(args.connection, 4096))
        value = parse_json(sys.stdin.buffer.read(MAX_INPUT + 1), MAX_INPUT) if args.input == "-" else read_private_json(args.input, MAX_INPUT)
        validate_output(args.output, (args.connection, args.input, args.since))
        if args.command == "prepare":
            progress_decision(value)
            request = build_request("read", {"caseId": value["caseId"]}, config)
        else:
            if args.command == "progress" and isinstance(value, dict) and value.get("kind") == "prepared-progress":
                value = prepared_intent(value, config)
            request = build_request(args.command, value, config)
        previous = read_private_json(args.since, MAX_RESPONSE + 4096) if args.since else None
        result = exchange(config, request)
        if args.command == "prepare":
            write_output(None, prepare_progress(value, result["snapshot"], config, args.output))
        elif args.view:
            view = read_view(result["snapshot"], config, args.view, previous, args.receipt)
            document = bound_document("feedback-snapshot", config, snapshot=result["snapshot"])
            require(save_once(args.output, document, MAX_RESPONSE + 4096) == document,
                    "Output already contains another snapshot; choose a new path")
            write_output(None, view)
        else:
            write_output(args.output, result)
    except (ToolError, OSError, UnicodeError) as error:
        message = str(error) if isinstance(error, ToolError) else "Local I/O failed; preserve the intent and check its publication state before retrying"
        print(json.dumps({"error": message}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
