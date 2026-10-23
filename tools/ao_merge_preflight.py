#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Read-only AO/GitHub evidence preflight; never grants merge authority."""

import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote

# The caller must use a trusted checkout, not a candidate-controlled script.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ao_review_report import AOClient, ReportError, decode, identifier, require, SHA

LIMIT = 1048576
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
MISSING_AUTHORITIES = [
    "coordinator-authenticated independent review and task/acceptance binding",
    "trusted verifier evidence for the exact integration candidate",
    "protected merge controller with fresh conditional-write authorization",
]


def positive(value):
    return type(value) is int and 0 < value < 2**63


def shape(value, keys, description):
    require(isinstance(value, dict) and set(value) == set(keys),
            "Invalid " + description + " fields.")


def source_path(value):
    return (isinstance(value, str) and 0 < len(value) <= 240
            and all(part not in ("", ".", "..") for part in value.split("/"))
            and re.fullmatch(r"[A-Za-z0-9_./-]+", value) is not None)


def validate_policy(policy):
    shape(policy, ("schemaVersion", "repository", "pullRequest", "ao", "ci"), "policy")
    require(type(policy["schemaVersion"]) is int and policy["schemaVersion"] == 1,
            "Unsupported policy schema.")
    repo, pr, ao, ci = (policy[key] for key in ("repository", "pullRequest", "ao", "ci"))
    shape(repo, ("fullName", "id"), "repository")
    require(isinstance(repo["fullName"], str)
            and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,99}/[A-Za-z0-9_.-]{1,100}", repo["fullName"])
            and repo["fullName"].split("/")[1] not in (".", "..") and positive(repo["id"]),
            "Invalid repository identity.")
    shape(pr, ("number", "baseRef", "baseSha", "headSha"), "pull request")
    require(positive(pr["number"]) and source_path(pr["baseRef"]), "Invalid pull request identity.")
    require(all(isinstance(pr[key], str) and SHA.fullmatch(pr[key]) for key in ("baseSha", "headSha")),
            "Policy must freeze full base and head commits.")
    shape(ao, ("hostId", "projectId", "workerSessionId", "reviewSessionId", "runId", "githubActorId"), "AO")
    require(all(identifier(ao[key]) for key in ao if key != "githubActorId")
            and positive(ao["githubActorId"]), "Invalid AO or GitHub actor identity.")
    shape(ci, ("workflowId", "workflowPath", "appId", "requiredJobs", "definitionFiles"), "CI")
    require(positive(ci["workflowId"]) and positive(ci["appId"])
            and source_path(ci["workflowPath"])
            and ci["workflowPath"].startswith(".github/workflows/"), "Invalid workflow identity.")
    jobs, files = ci["requiredJobs"], ci["definitionFiles"]
    require(isinstance(jobs, list) and 1 <= len(jobs) <= 32
            and all(isinstance(job, str) and 0 < len(job) <= 200 for job in jobs)
            and len(set(jobs)) == len(jobs), "Required job names must be nonempty and unique.")
    require(isinstance(files, dict) and 1 <= len(files) <= 32 and ci["workflowPath"] in files
            and all(source_path(path) and isinstance(digest, str) and DIGEST.fullmatch(digest)
                    for path, digest in files.items()), "Pin the workflow and trusted check definition file digests.")
    return policy


def read_policy(path, expected_digest):
    require(isinstance(expected_digest, str) and DIGEST.fullmatch(expected_digest),
            "A separately trusted policy SHA-256 is required.")
    try:
        with open(path, "rb") as stream:
            raw = stream.read(LIMIT + 1)
    except OSError:
        raise ReportError("Cannot read the trusted policy file.") from None
    require(len(raw) <= LIMIT and hashlib.sha256(raw).hexdigest() == expected_digest,
            "Policy content does not match its trusted digest.")
    return validate_policy(decode(raw))


class GitHub:
    def __init__(self, executable):
        require(os.path.isabs(executable) and Path(executable).is_file() and os.access(executable, os.X_OK),
                "An absolute trusted gh executable is required.")
        self.executable = executable

    def get(self, endpoint):
        # Only constructed repository-relative GETs; provider URLs never select a host.
        require(endpoint.startswith("repos/") and ".." not in endpoint,
                "Invalid GitHub read endpoint.")
        try:
            result = subprocess.run([self.executable, "api", "--hostname", "github.com",
                                     "--method", "GET", endpoint], stdin=subprocess.DEVNULL,
                                    capture_output=True, timeout=20, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise ReportError("GitHub read failed or timed out.") from None
        require(result.returncode == 0 and len(result.stdout) <= LIMIT,
                "GitHub read failed or exceeded its size limit.")
        return decode(result.stdout)


def matched_pr(value, policy):
    pr, repo = policy["pullRequest"], policy["repository"]
    require(isinstance(value, dict) and value.get("number") == pr["number"],
            "PR association does not match policy.")
    for side, sha in (("base", pr["baseSha"]), ("head", pr["headSha"])):
        ref = value.get(side)
        require(isinstance(ref, dict) and ref.get("sha") == sha
                and isinstance(ref.get("repo"), dict) and ref["repo"].get("id") == repo["id"],
                "PR base/head commit or repository changed.")
    require(value["base"].get("ref") == pr["baseRef"], "PR target branch changed.")


def published_review(ao_client, github, policy, prefix, pr_url):
    expected = policy["ao"]
    identity = ao_client.request("GET", "/identity")
    require(identity.get("hostId") == expected["hostId"]
            and type(identity.get("apiVersion")) is int and identity["apiVersion"] == 1,
            "AO daemon identity changed.")
    path = "/sessions/" + expected["workerSessionId"]
    session = ao_client.request("GET", path).get("session")
    require(isinstance(session, dict) and session.get("id") == expected["workerSessionId"]
            and session.get("projectId") == expected["projectId"], "AO worker/project binding changed.")
    state = ao_client.request("GET", path + "/reviews")
    runs, reviews = state.get("runs"), state.get("reviews")
    require(isinstance(runs, list) and isinstance(reviews, list), "Malformed AO review state.")
    matches = [run for run in runs if isinstance(run, dict) and run.get("id") == expected["runId"]]
    require(len(matches) == 1, "Pinned AO review run is absent or ambiguous.")
    run = matches[0]
    require(run.get("sessionId") == expected["workerSessionId"]
            and run.get("reviewId") == expected["reviewSessionId"] and run.get("prUrl") == pr_url
            and run.get("targetSha") == policy["pullRequest"]["headSha"], "AO review is bound to another candidate.")
    current = [review for review in reviews if isinstance(review, dict) and review.get("prUrl") == pr_url]
    require(len(current) == 1 and isinstance(current[0].get("latestRun"), dict)
            and current[0]["latestRun"].get("id") == expected["runId"]
            and current[0].get("targetSha") == run["targetSha"], "AO review has been superseded.")
    require(run.get("status") == "complete" and run.get("verdict") == "approved",
            "AO review is not complete and approved.")
    review_id = run.get("githubReviewId")
    require(isinstance(review_id, str) and re.fullmatch(r"[1-9][0-9]{0,19}", review_id),
            "AO review lacks a published GitHub review identifier.")
    review = github.get(prefix + "/pulls/" + str(policy["pullRequest"]["number"]) + "/reviews/" + review_id)
    require(type(review.get("id")) is int and str(review["id"]) == review_id
            and review.get("commit_id") == run["targetSha"] and review.get("state") == "COMMENTED"
            and isinstance(review.get("user"), dict) and review["user"].get("id") == expected["githubActorId"],
            "Published GitHub review commit, actor or state does not match.")
    return {"runId": run["id"], "reviewSessionId": run["reviewId"], "githubReviewId": review_id,
            "githubActorId": expected["githubActorId"], "verdict": "approved"}


def bounded_list(payload, key):
    values = payload.get(key)
    require(isinstance(values, list) and type(payload.get("total_count")) is int
            and payload["total_count"] == len(values) <= 100
            and all(isinstance(item, dict) for item in values),
            "Incomplete, oversized or malformed " + key + " listing; no partial evidence is accepted.")
    return values


def verified_ci(github, policy, prefix):
    ci, pr, repo = policy["ci"], policy["pullRequest"], policy["repository"]
    for path, digest in ci["definitionFiles"].items():
        content = github.get(prefix + "/contents/" + quote(path, safe="/") + "?ref=" + pr["headSha"])
        require(content.get("type") == "file" and content.get("path") == path
                and content.get("encoding") == "base64" and isinstance(content.get("content"), str),
                "Check definition is not a supported source file.")
        try:
            raw = base64.b64decode(content["content"].replace("\n", ""), validate=True)
        except ValueError:
            raise ReportError("Invalid check definition content.") from None
        require(hashlib.sha256(raw).hexdigest() == digest, "Check definition differs from trusted policy: " + path)
    endpoint = (prefix + "/actions/workflows/" + str(ci["workflowId"])
                + "/runs?event=pull_request&head_sha=" + pr["headSha"] + "&per_page=100")
    runs = bounded_list(github.get(endpoint), "workflow_runs")
    require(bool(runs), "Required workflow has no run for this candidate.")
    for run in runs:
        require(positive(run.get("id")) and positive(run.get("run_number"))
                and run.get("workflow_id") == ci["workflowId"] and run.get("head_sha") == pr["headSha"]
                and run.get("event") == "pull_request", "Unexpected workflow run identity.")
    latest_number = max(run["run_number"] for run in runs)
    latest = [run for run in runs if run["run_number"] == latest_number]
    require(len(latest) == 1, "Latest workflow run is ambiguous.")
    run = github.get(prefix + "/actions/runs/" + str(latest[0]["id"]))
    require(run.get("id") == latest[0]["id"] and run.get("run_number") == latest_number
            and run.get("workflow_id") == ci["workflowId"] and run.get("path") == ci["workflowPath"]
            and run.get("event") == "pull_request" and run.get("head_sha") == pr["headSha"]
            and isinstance(run.get("repository"), dict) and run["repository"].get("id") == repo["id"]
            and isinstance(run.get("head_repository"), dict) and run["head_repository"].get("id") == repo["id"]
            and positive(run.get("run_attempt")) and positive(run.get("check_suite_id")),
            "Required workflow run identity does not match policy.")
    associated = run.get("pull_requests")
    require(isinstance(associated, list), "Workflow lacks PR association.")
    matches = [item for item in associated if isinstance(item, dict) and item.get("number") == pr["number"]]
    require(len(matches) == 1, "Workflow is not unambiguously associated with the pinned PR.")
    matched_pr(matches[0], policy)
    require(run.get("status") == "completed" and run.get("conclusion") == "success",
            "Latest required workflow run has not succeeded.")
    jobs = bounded_list(github.get(prefix + "/actions/runs/" + str(run["id"]) + "/attempts/"
                                   + str(run["run_attempt"]) + "/jobs?per_page=100"), "jobs")
    evidence = []
    for name in ci["requiredJobs"]:
        matches = [job for job in jobs if job.get("name") == name]
        require(len(matches) == 1, "Required CI job is missing or ambiguous: " + name)
        job = matches[0]
        require(positive(job.get("id")) and job.get("head_sha") == pr["headSha"]
                and job.get("status") == "completed" and job.get("conclusion") == "success",
                "Required CI job has not succeeded on the exact head: " + name)
        check_url = job.get("check_run_url")
        check_prefix = "https://api.github.com/" + prefix + "/check-runs/"
        require(isinstance(check_url, str) and check_url.startswith(check_prefix)
                and re.fullmatch(r"[1-9][0-9]{0,19}", check_url[len(check_prefix):]), "Unexpected CI check URL.")
        check_id = int(check_url[len(check_prefix):])
        check = github.get(prefix + "/check-runs/" + str(check_id))
        require(check.get("id") == check_id and check.get("name") == name and check.get("head_sha") == pr["headSha"]
                and check.get("status") == "completed" and check.get("conclusion") == "success"
                and isinstance(check.get("app"), dict) and check["app"].get("id") == ci["appId"]
                and isinstance(check.get("check_suite"), dict)
                and check["check_suite"].get("id") == run["check_suite_id"], "Required CI check producer or binding differs.")
        evidence.append({"name": name, "jobId": job["id"], "checkRunId": check_id})
    return {"workflowId": ci["workflowId"], "runId": run["id"], "attempt": run["run_attempt"],
            "checkSuiteId": run["check_suite_id"], "requiredJobs": evidence}


def snapshot(policy, ao_client, github):
    repo, expected_pr = policy["repository"], policy["pullRequest"]
    prefix = "repos/" + repo["fullName"]
    remote = github.get(prefix)
    require(remote.get("id") == repo["id"] and remote.get("full_name") == repo["fullName"],
            "Repository identity changed.")
    pr = github.get(prefix + "/pulls/" + str(expected_pr["number"]))
    matched_pr(pr, policy)
    require(pr.get("state") == "open" and pr.get("merged") is False and type(pr.get("draft")) is bool,
            "PR is closed, merged or has an unsupported state.")
    branch = github.get(prefix + "/git/ref/heads/" + quote(expected_pr["baseRef"], safe="/"))
    require(branch.get("ref") == "refs/heads/" + expected_pr["baseRef"]
            and isinstance(branch.get("object"), dict) and branch["object"].get("type") == "commit"
            and branch["object"].get("sha") == expected_pr["baseSha"], "Current target branch advanced.")
    pr_url = "https://github.com/" + repo["fullName"] + "/pull/" + str(expected_pr["number"])
    review = published_review(ao_client, github, policy, prefix, pr_url)
    ci = verified_ci(github, policy, prefix)
    return {"repository": repo, "pullRequest": {**expected_pr, "draft": pr["draft"]}, "review": review, "ci": ci}


def preflight(policy, ao_client, github):
    validate_policy(policy)
    first = snapshot(policy, ao_client, github)
    second = snapshot(policy, ao_client, github)
    require(first == second, "Evidence changed during preflight; collect fresh evidence.")
    return {"schemaVersion": 1, "observedEvidenceReady": True, "mergeAuthorized": False,
            "missingAuthorities": MISSING_AUTHORITIES, "evidence": second}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--policy-sha256", required=True)
    parser.add_argument("--ao-run-file", required=True)
    parser.add_argument("--gh", required=True, help="absolute trusted gh executable")
    args = parser.parse_args(argv)
    try:
        policy = read_policy(args.policy, args.policy_sha256)
        ao = AOClient({"HEXPROOF_AO_HOST_ID": policy["ao"]["hostId"], "AO_RUN_FILE": args.ao_run_file})
        result = preflight(policy, ao, GitHub(args.gh))
    except ReportError as error:
        result = {"schemaVersion": 1, "observedEvidenceReady": False, "mergeAuthorized": False,
                  "missingAuthorities": MISSING_AUTHORITIES, "reason": str(error)}
    result["policySha256"] = args.policy_sha256
    result["observedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0 if result["observedEvidenceReady"] else 1


if __name__ == "__main__":
    sys.exit(main())
