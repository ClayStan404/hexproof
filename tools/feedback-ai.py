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
from urllib.parse import urlsplit


MAX_INPUT = 16 << 10
MAX_RESPONSE = 2 << 20
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
HASH = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
SOURCE_COMMIT = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")
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


def github_repository(location):
    require(isinstance(location, str), "Invalid source publication destination")
    ssh = re.fullmatch(r"git@github\.com:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)", location)
    if ssh:
        return ssh[1].removesuffix(".git")
    try:
        url = urlsplit(location)
        require(url.scheme == "https" and url.netloc in ("github.com", "github.com:443")
                and not url.query and not url.fragment and matches(REPOSITORY, url.path.removeprefix("/")),
                "Source publication destination must be credential-free GitHub HTTPS or SSH")
        return url.path.removeprefix("/").removesuffix(".git")
    except ValueError as error:
        raise ToolError("Invalid source publication destination") from error


def public_commit(receipt, repository, source_commit):
    """Extract a published mapping, never return its private intent/export fields.

    This local receipt is the publisher's recorded observation, not independent
    GitHub/release proof. The receiver verifies current public evidence itself.
    """
    fields(receipt, {"intent", "export", "publicCommit", "state", "observedPublicHead", "historicalSourceMapping"})
    require(receipt["state"] == "published", "Source publication is not confirmed")
    require(receipt["historicalSourceMapping"] in ("unknown", "verified", "absent"), "Invalid source publication receipt")
    intent, exported = receipt["intent"], receipt["export"]
    fields(intent, {"schemaVersion", "sourceCommit", "sourceRef", "publicRepository", "publicRef", "publicParent",
                    "baselineSourceCommit", "adoptPublicParent", "exportPolicyDigest"})
    fields(exported, {"schemaVersion", "sourceCommit", "exportPolicyDigest", "exportTreeDigest"})
    require(type(intent["schemaVersion"]) is int and intent["schemaVersion"] == 1
            and type(exported["schemaVersion"]) is int and exported["schemaVersion"] == 1,
            "Invalid source publication receipt schema")
    require(matches(SOURCE_COMMIT, source_commit) and intent["sourceCommit"] == source_commit
            and exported["sourceCommit"] == source_commit, "Receipt does not match the intended private source commit")
    require((intent["baselineSourceCommit"] is None or matches(SOURCE_COMMIT, intent["baselineSourceCommit"]))
            and (intent["publicParent"] is None or matches(COMMIT, intent["publicParent"]))
            and type(intent["adoptPublicParent"]) is bool
            and isinstance(intent["sourceRef"], str) and intent["sourceRef"].startswith("refs/"),
            "Invalid source publication intent")
    require(github_repository(intent["publicRepository"]).casefold() == repository.casefold(),
            "Receipt does not match the configured public repository")
    require(matches(HASH, intent["exportPolicyDigest"])
            and intent["exportPolicyDigest"] == exported["exportPolicyDigest"]
            and matches(HASH, exported["exportTreeDigest"]), "Invalid source export receipt binding")
    require(matches(COMMIT, receipt["publicCommit"]) and matches(COMMIT, receipt["observedPublicHead"])
            and receipt["publicCommit"] not in (source_commit, intent["baselineSourceCommit"]),
            "Invalid public commit mapping")
    require(isinstance(intent["publicRef"], str)
            and re.fullmatch(r"refs/heads/[A-Za-z0-9_./-]+", intent["publicRef"]), "Invalid public source ref")
    return receipt["publicCommit"]


def public_text(value):
    require(isinstance(value, str) and value.strip() and len(value.encode("utf-8")) <= 4096
            and all(ord(c) >= 32 or c in "\n\t" for c in value), "Invalid bounded public text")


def build_request(command, value, config, receipt=None, source_commit=None):
    fields(value, {"caseId"} if command == "read" else {"caseId", "projection"})
    require(matches(UUID, value["caseId"]), "Invalid case UUIDv4")
    request = {"action": "snapshot" if command == "read" else "project", "caseId": value["caseId"],
               "binding": config["binding"]}
    if command == "read":
        require(receipt is None and source_commit is None, "Publication evidence is only accepted for source or release outcomes")
        return request
    # Copy the approved JSON; deriving a public commit must not mutate the caller's
    # saved intent, its IDs, revisions, text or private publication receipt.
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
               | ({"tag", "version"} if kind == "release" else set()), {"commit"} if kind != "duplicate" else set())
        require(outcome["kind"] == kind and outcome["repository"] == config["publicRepository"], "Outcome does not match its state and configured repository")
        if kind == "duplicate":
            require(integer(outcome["issueNumber"], maximum=2147483647), "Invalid public issue number")
        else:
            require(receipt is not None and source_commit is not None, "Source or release outcomes require a published source receipt and explicit source commit")
            mapped = public_commit(receipt, config["publicRepository"], source_commit)
            require("commit" not in outcome or outcome["commit"] == mapped, "Outcome commit does not match the source publication receipt")
            require(all(not private or private.casefold() not in projection["summary"].casefold()
                        for private in (source_commit, receipt["intent"]["baselineSourceCommit"])),
                    "Public text must not contain private source commit references")
            outcome["commit"] = mapped
        if kind == "release":
            require(matches(VERSION, outcome["version"]) and outcome["tag"] == "v" + outcome["version"], "Release tag and version must match")
    needs_evidence = command == "outcome" and state != "duplicate"
    require(needs_evidence or (receipt is None and source_commit is None), "Publication evidence is only accepted for source or release outcomes")
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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("read", "ask", "reply", "progress", "outcome"))
    parser.add_argument("--connection", required=True, help="Private JSON with socket, binding and fixed public repository")
    parser.add_argument("--input", default="-", help="Private intentional-operation JSON file; '-' reads bounded stdin")
    parser.add_argument("--output", help="Atomically write the requested result to a private absolute path instead of stdout")
    parser.add_argument("--publication-receipt", help="Private published receipt from publish-public-source.py")
    parser.add_argument("--source-commit", help="Exact intended private source commit; checked locally and never transmitted")
    args = parser.parse_args(argv)
    try:
        config = connection_config(read_private_json(args.connection, 4096))
        value = parse_json(sys.stdin.buffer.read(MAX_INPUT + 1), MAX_INPUT) if args.input == "-" else read_private_json(args.input, MAX_INPUT)
        receipt = read_private_json(args.publication_receipt, 16 << 10) if args.publication_receipt else None
        request = build_request(args.command, value, config, receipt, args.source_commit)
        validate_output(args.output, (args.connection, args.input, args.publication_receipt))
        result = exchange(config, request)
        write_output(args.output, result)
    except (ToolError, OSError, UnicodeError) as error:
        message = str(error) if isinstance(error, ToolError) else "Local I/O failed; preserve the intent and check its publication state before retrying"
        print(json.dumps({"error": message}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
