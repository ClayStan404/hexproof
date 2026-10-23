#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Persist AO 0.14.4 review evidence without its namespace-sensitive PID probe.

Run from a trusted installation with Python -I -B. This verifies review evidence;
it neither authenticates the review author nor authorizes a merge.
"""

import argparse
import http.client
import json
import os
from pathlib import Path
import re
import subprocess
import sys

INPUT_LIMIT = 131072
RESPONSE_LIMIT = 1048576
TIMEOUT = 5
IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
PR_URL = re.compile(r"https://github\.com/([A-Za-z0-9][A-Za-z0-9-]{0,99})/"
                    r"([A-Za-z0-9_.-]{1,100})/pull/([1-9][0-9]{0,9})\Z")
ITEM_KEYS = {"runId", "verdict", "body", "githubReviewId"}


class ReportError(Exception):
    """A bounded, non-secret diagnostic suitable for the reviewer."""


def require(condition, message):
    if not condition:
        raise ReportError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "JSON contains duplicate keys.")
        result[key] = value
    return result


def decode(raw):
    try:
        value = json.loads(raw, object_pairs_hook=unique_object)
    except (ValueError, UnicodeError, RecursionError):
        raise ReportError("Invalid JSON response or input.") from None
    require(isinstance(value, dict), "Expected a JSON object.")
    return value


def identifier(value):
    return isinstance(value, str) and IDENTIFIER.fullmatch(value) is not None


def parse_reviews(raw):
    require(len(raw) <= INPUT_LIMIT, "Review input exceeds the size limit.")
    payload = decode(raw)
    require(set(payload) == {"reviews"}, "Expected only the reviews array.")
    items = payload["reviews"]
    require(isinstance(items, list) and 1 <= len(items) <= 16,
            "Expected between 1 and 16 reviews.")
    run_ids, github_ids = set(), set()
    for item in items:
        require(isinstance(item, dict) and set(item) == ITEM_KEYS,
                "Each review must contain exactly runId, verdict, body, and githubReviewId.")
        require(identifier(item["runId"]), "Invalid review run identifier.")
        require(item["verdict"] in ("approved", "changes_requested"), "Invalid review verdict.")
        body = item["body"]
        require(isinstance(body, str) and bool(body.strip()), "Review body must be nonempty.")
        try:
            require(len(body.encode("utf-8")) <= 32768, "Review body exceeds the size limit.")
        except UnicodeError:
            raise ReportError("Review body must be valid UTF-8.") from None
        github_id = item["githubReviewId"]
        require(isinstance(github_id, str) and re.fullmatch(r"[1-9][0-9]{0,19}", github_id),
                "A GitHub review identifier is required.")
        require(item["runId"] not in run_ids and github_id not in github_ids,
                "Duplicate run or GitHub review identifiers are not allowed.")
        run_ids.add(item["runId"])
        github_ids.add(github_id)
    return items


class AOClient:
    def __init__(self, environment):
        self.host_id = environment.get("HEXPROOF_AO_HOST_ID", "")
        require(identifier(self.host_id), "Missing or invalid trusted AO host identifier.")
        run_file = environment.get("AO_RUN_FILE", "")
        require(os.path.isabs(run_file), "AO_RUN_FILE must be an absolute path.")
        try:
            with open(run_file, "rb") as stream:
                raw = stream.read(4097)
        except OSError:
            raise ReportError("Cannot read the AO discovery file.") from None
        require(len(raw) <= 4096, "AO discovery file exceeds the size limit.")
        port = decode(raw).get("port")
        require(type(port) is int and 1 <= port <= 65535, "Invalid AO discovery port.")
        self.port = port

    def request(self, method, path, payload=None):
        # http.client does not consult proxy variables or follow redirects.
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=TIMEOUT)
        headers = {"Accept": "application/json", "X-AO-Expected-Host-ID": self.host_id}
        body = None
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        try:
            connection.request(method, "/api/v1" + path, body=body, headers=headers)
            response = connection.getresponse()
            require(response.status == 200, "AO request returned an unexpected HTTP status.")
            raw = response.read(RESPONSE_LIMIT + 1)
            require(len(raw) <= RESPONSE_LIMIT, "AO response exceeds the size limit.")
            return decode(raw)
        except (OSError, http.client.HTTPException):
            raise ReportError("AO transport failed or timed out.") from None
        finally:
            connection.close()


class TrustedTools:
    def __init__(self, environment, cwd):
        self.cwd = cwd
        self.environment = {key: value for key, value in environment.items()
                            if not key.startswith("GIT_")}
        self.executables = {}
        for name in ("git", "gh"):
            path = environment.get("HEXPROOF_AO_" + name.upper(), "")
            require(os.path.isabs(path) and Path(path).is_file() and os.access(path, os.X_OK),
                    "Trusted absolute git and gh executables must be configured.")
            self.executables[name] = path

    def command(self, name, arguments):
        try:
            result = subprocess.run([self.executables[name], *arguments], cwd=self.cwd,
                                    env=self.environment, stdin=subprocess.DEVNULL,
                                    capture_output=True, timeout=10, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise ReportError("Trusted provider command failed or timed out.") from None
        require(result.returncode == 0, "Trusted provider command failed.")
        require(len(result.stdout) <= RESPONSE_LIMIT, "Provider response exceeds the size limit.")
        return result.stdout

    def head(self):
        raw = self.command("git", ["-C", str(self.cwd), "rev-parse", "HEAD"])
        try:
            head = raw.decode("ascii").strip()
        except UnicodeError:
            raise ReportError("Invalid checkout commit.") from None
        require(SHA.fullmatch(head), "Invalid checkout commit.")
        return head

    def github(self, endpoint, projection):
        return decode(self.command("gh", ["api", "--hostname", "github.com", endpoint,
                                          "--jq", projection]))


def stored_runs(state, items, worker, reviewer):
    runs, reviews = state.get("runs"), state.get("reviews")
    require(isinstance(runs, list) and isinstance(reviews, list), "Invalid AO review state.")
    found = []
    for item in items:
        matching = [run for run in runs if isinstance(run, dict) and run.get("id") == item["runId"]]
        require(len(matching) == 1, "Review run is missing or ambiguous.")
        run = matching[0]
        require(run.get("sessionId") == worker and run.get("reviewId") == reviewer,
                "Review run belongs to a different worker or reviewer.")
        require(run.get("status") in ("running", "complete"), "Review run is no longer submittable.")
        require(isinstance(run.get("targetSha"), str) and SHA.fullmatch(run["targetSha"]),
                "Invalid review target commit.")
        current = [review for review in reviews if isinstance(review, dict)
                   and review.get("prUrl") == run.get("prUrl")]
        require(len(current) == 1 and isinstance(current[0].get("latestRun"), dict)
                and current[0]["latestRun"].get("id") == run["id"]
                and current[0].get("targetSha") == run["targetSha"],
                "Review run has been superseded or its target changed.")
        if run["status"] == "complete":
            require(all(run.get(key) == item[key] for key in ITEM_KEYS - {"runId"}),
                    "Completed review differs from this submission; exact replay is required.")
        found.append(run)
    return found


def verify_provider(tools, runs, items):
    head = tools.head()
    for run, item in zip(runs, items):
        url = run.get("prUrl")
        match = PR_URL.fullmatch(url) if isinstance(url, str) else None
        require(match is not None and match[2] not in (".", ".."), "Unsupported GitHub pull request URL.")
        endpoint = f"repos/{match[1]}/{match[2]}/pulls/{match[3]}"
        pr = tools.github(endpoint, "{head: {sha: .head.sha}}")
        require(isinstance(pr.get("head"), dict) and head == run["targetSha"] == pr["head"].get("sha"),
                "Checkout, review target, and current GitHub head must match; request a fresh review.")
        review = tools.github(endpoint + "/reviews/" + item["githubReviewId"],
                              "{id, commit_id, state}")
        require(type(review.get("id")) is int and str(review["id"]) == item["githubReviewId"]
                and review.get("commit_id") == head and review.get("state") == "COMMENTED",
                "GitHub review identifier, commit, or published COMMENTED state does not match.")


def submit_reviews(items, worker, environment, client=None, tools=None, cwd=None):
    require(identifier(worker) and environment.get("AO_REVIEW_WORKER_SESSION_ID") == worker,
            "Worker session does not match the trusted review environment.")
    reviewer, project = environment.get("AO_REVIEW_SESSION_ID"), environment.get("AO_PROJECT_ID")
    require(identifier(reviewer) and identifier(project), "Trusted reviewer and project identifiers are required.")
    client = client or AOClient(environment)
    tools = tools or TrustedTools(environment, cwd or Path.cwd())
    identity = client.request("GET", "/identity")
    require(type(identity.get("apiVersion")) is int and identity["apiVersion"] == 1
            and identity.get("hostId") == environment.get("HEXPROOF_AO_HOST_ID"),
            "AO identity does not match the trusted host and API version.")
    path = "/sessions/" + worker
    session = client.request("GET", path).get("session")
    require(isinstance(session, dict) and session.get("id") == worker and session.get("projectId") == project,
            "AO worker does not belong to the expected project.")
    runs = stored_runs(client.request("GET", path + "/reviews"), items, worker, reviewer)
    verify_provider(tools, runs, items)
    pending = [item for item, run in zip(items, runs) if run["status"] == "running"]
    uncertain = False
    if pending:
        try:
            client.request("POST", path + "/reviews/submit", {"reviews": pending})
        except ReportError:
            # A timeout may occur after persistence. Never retry the write blindly.
            uncertain = True
    try:
        recorded = stored_runs(client.request("GET", path + "/reviews"), items, worker, reviewer)
        require(all(run["status"] == "complete" for run in recorded), "Review persistence is incomplete.")
        require(all(before["targetSha"] == after["targetSha"] and before["prUrl"] == after["prUrl"]
                    for before, after in zip(runs, recorded)), "Stored review target changed.")
    except ReportError:
        raise ReportError("Cannot confirm exact review persistence. Inspect AO, then replay the identical submission; do not change the result.") from None
    # A PR may have advanced during the write, including on exact replay.
    verify_provider(tools, recorded, items)
    return {"ok": True, "marker": "hexproof-ao-http-report",
            "reviews": [{"runId": run["id"], "targetSha": run["targetSha"], "verdict": run["verdict"]}
                        for run in recorded],
            "reviewCount": len(items), "submittedCount": len(pending),
            "recoveredAfterUncertainWrite": uncertain}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ReportError("Use: review submit --session WORKER --reviews -")


def main(argv=None):
    parser = Parser(description=__doc__)
    parser.add_argument("review", choices=["review"])
    parser.add_argument("submit", choices=["submit"])
    parser.add_argument("--session", required=True)
    parser.add_argument("--reviews", required=True, choices=["-"])
    try:
        args = parser.parse_args(argv)
        items = parse_reviews(sys.stdin.buffer.read(INPUT_LIMIT + 1))
        result = submit_reviews(items, args.session, os.environ)
        print(json.dumps(result))
        return 0
    except ReportError as error:
        print("AO review report: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
