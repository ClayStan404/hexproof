#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Run full local checks once and bind their private evidence to a public commit status."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from public_source_export import ExportError, _git, _repo_root, _selected, export_snapshot, load_policy


REPOSITORY = "ClayStan404/hexproof"
CONTEXT = "hexproof/local-release"
PROFILE = "full-v1"
COMMAND = ["tools/verify.sh", "--qml-per-file"]
ROOT = Path(__file__).resolve().parents[1]


class VerificationError(ValueError):
    """Local evidence or public source identity cannot qualify this release."""


def oid(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", value):
        raise VerificationError("An exact lowercase Git object ID is required")
    return value


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", value):
        raise VerificationError("An exact MAJOR.MINOR.PATCH version is required")
    return value


def git_text(repo, *args):
    return _git(repo, *args).decode().strip()


def clean_source(repo):
    flags = _git(repo, "ls-files", "-v", "-z").split(b"\0")
    if any(entry and (entry[:1].islower() or entry[:1] == b"S") for entry in flags):
        raise VerificationError("Remove assume-unchanged and skip-worktree flags before verification")
    if _git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
        raise VerificationError("Commit all source changes before release verification")
    commit = oid(git_text(repo, "rev-parse", "HEAD"))
    source = _git(repo, "show", commit + ":apps/client-qt/CMakeLists.txt").decode()
    match = re.search(r'^\s*set\(HEXPROOF_VERSION\s+"([0-9]+\.[0-9]+\.[0-9]+)"\s*\)\s*$', source, re.MULTILINE)
    if not match:
        raise VerificationError("Cannot read the committed application version")
    return {"sourceCommit": commit, "sourceTree": oid(git_text(repo, "rev-parse", commit + "^{tree}")),
            "sourceVersion": match[1]}


def evidence_path(repo, value):
    path = Path(value).absolute()
    if any(parent.is_symlink() for parent in (path, *path.parents)):
        raise VerificationError("Private evidence paths must not contain symlinks")
    path = path.resolve()
    if path == repo or repo in path.parents:
        relative = path.relative_to(repo)
        if len(relative.parts) < 2 or relative.parts[0] != "build":
            raise VerificationError("Keep private evidence under build/ or outside the checkout")
        if _git(repo, "ls-files", "--", relative.as_posix()):
            raise VerificationError("Private evidence must never overwrite a tracked source file")
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_receipt(repo, path, source):
    path = evidence_path(repo, path)
    receipt = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(receipt, dict) or type(receipt.get("schemaVersion")) is not int
            or receipt.get("schemaVersion") != 1 or receipt.get("profile") != PROFILE
            or receipt.get("result") != "passed" or receipt.get("command") != COMMAND
            or any(receipt.get(key) != value for key, value in source.items())):
        raise VerificationError("Receipt does not record full verification of this exact source")
    log = evidence_path(repo, receipt["logPath"])
    if not log.is_file() or sha256(log) != receipt.get("logSha256"):
        raise VerificationError("Verification log is missing or its checksum changed")
    return receipt


def run(args):
    repo = _repo_root(args.repo)
    source = clean_source(repo)
    receipt_path = evidence_path(repo, args.receipt)
    if receipt_path.exists():
        return read_receipt(repo, receipt_path, source)
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc).isoformat()
    with tempfile.NamedTemporaryFile(prefix=receipt_path.stem + "-", suffix=".log",
                                     dir=receipt_path.parent, delete=False) as log:
        log_path = Path(log.name)
        print(f"Running full local checks; log: {log_path}", flush=True)
        # A workstation-wide GOFLAGS=-run/-skip must not narrow this full profile.
        env = dict(os.environ, CTEST_PARALLEL_LEVEL="2", GOFLAGS="")
        completed = subprocess.run([str(repo / COMMAND[0]), *COMMAND[1:]], cwd=repo,
                                   env=env, stdout=log, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise VerificationError(f"Local checks failed ({completed.returncode}); retained log: {log_path}")
    if clean_source(repo) != source:
        raise VerificationError("Source changed during verification; no passing receipt was written")
    receipt = {"schemaVersion": 1, "profile": PROFILE, "result": "passed", **source,
               "command": COMMAND, "startedAt": started,
               "completedAt": datetime.now(timezone.utc).isoformat(),
               "logPath": str(log_path), "logSha256": sha256(log_path)}
    fd = os.open(receipt_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(receipt, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return receipt


def gh_api(path, payload=None):
    command = ["gh", "api", "--hostname", "github.com", "-H", "Accept: application/vnd.github+json", path]
    if payload is not None:
        command += ["--method", "POST", "--input", "-"]
    result = subprocess.run(command, input=None if payload is None else json.dumps(payload),
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def public_identity(repository, commit):
    if repository.casefold() != REPOSITORY.casefold():
        raise VerificationError("Release verification is restricted to the official public repository")
    commit = oid(commit)
    metadata = gh_api(f"repos/{REPOSITORY}")
    if metadata.get("full_name", "").casefold() != REPOSITORY.casefold() or metadata.get("private") is not False:
        raise VerificationError("Expected the official public GitHub repository")
    remote = gh_api(f"repos/{REPOSITORY}/git/commits/{commit}")
    if remote.get("sha") != commit:
        raise VerificationError("GitHub returned a different public commit")
    return oid(remote["tree"]["sha"])


def description(release_version, public_tree):
    return f"Full local verification {version(release_version)}; tree {oid(public_tree)}"


def latest_status(commit):
    # GitHub returns statuses newest first; a newer failure must supersede success.
    page = 1
    while True:
        statuses = gh_api(f"repos/{REPOSITORY}/commits/{oid(commit)}/statuses?per_page=100&page={page}")
        if not isinstance(statuses, list):
            raise VerificationError("Malformed GitHub status response")
        for status in statuses:
            if str(status.get("context", "")).casefold() == CONTEXT.casefold():
                return status
        if len(statuses) < 100:
            return None
        page += 1


def require_status(commit, release_version, public_tree):
    status = latest_status(commit)
    if (not status or status.get("state") != "success"
            or status.get("description") != description(release_version, public_tree)):
        raise VerificationError("This exact public source has no current successful full local verification")
    return {"repository": REPOSITORY, "publicCommit": commit, "publicTree": public_tree,
            "version": release_version, "context": CONTEXT, "state": "success"}


def check(args):
    public_tree = public_identity(args.repository, args.commit)
    return require_status(args.commit, args.version, public_tree)


def public_entries(repo, commit):
    return [entry for entry in _git(repo, "ls-tree", "-r", "-z", "--full-tree", commit).split(b"\0") if entry]


def publish(args):
    repo = _repo_root(args.repo)
    source = clean_source(repo)
    read_receipt(repo, args.receipt, source)
    publication = json.loads(evidence_path(repo, args.publication_receipt).read_text(encoding="utf-8"))
    intent = publication["intent"]
    if publication.get("state") != "published" or intent.get("sourceCommit") != source["sourceCommit"]:
        raise VerificationError("Published source receipt does not match the verified private source")
    allowed_locations = {f"git@github.com:{REPOSITORY}.git", f"https://github.com/{REPOSITORY}.git",
                         f"git@github.com:{REPOSITORY}", f"https://github.com/{REPOSITORY}"}
    if intent.get("publicRepository") not in allowed_locations:
        raise VerificationError("Source receipt belongs to another public destination")
    public_commit = oid(publication["publicCommit"])
    public_repo = _repo_root(args.public_repo)
    public_source = clean_source(public_repo)
    if public_source["sourceCommit"] != public_commit or public_source["sourceVersion"] != source["sourceVersion"]:
        raise VerificationError("Public checkout does not match the published and verified source")
    policy_path = repo / "tools/public_export_policy.json"
    with tempfile.TemporaryDirectory(prefix="hexproof-release-export-") as temporary:
        exported = export_snapshot(repo, source["sourceCommit"], Path(temporary) / "tree", policy_path)
    if exported != publication.get("export") or exported["exportPolicyDigest"] != intent.get("exportPolicyDigest"):
        raise VerificationError("Source publication no longer matches its trusted export policy")
    policy = load_policy(policy_path)
    selected = [entry for entry in public_entries(repo, source["sourceCommit"])
                if _selected(entry.split(b"\t", 1)[1].decode("utf-8"), policy)]
    if selected != public_entries(public_repo, public_commit):
        raise VerificationError("Public committed files differ from the verified filtered source")
    public_tree = public_identity(REPOSITORY, public_commit)
    if public_tree != public_source["sourceTree"]:
        raise VerificationError("GitHub public commit tree differs from the verified local public tree")
    # Keep private commits, log paths, receipts and native task details off GitHub.
    expected = description(source["sourceVersion"], public_tree)
    if clean_source(repo) != source or clean_source(public_repo) != public_source:
        raise VerificationError("Source changed while qualifying the public commit")
    read_receipt(repo, args.receipt, source)
    existing = latest_status(public_commit)
    if existing:
        # Cached evidence must not resurrect a candidate whose status was revoked.
        return require_status(public_commit, source["sourceVersion"], public_tree)
    gh_api(f"repos/{REPOSITORY}/statuses/{public_commit}",
           {"state": "success", "context": CONTEXT, "description": expected})
    return require_status(public_commit, source["sourceVersion"], public_tree)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    local = subparsers.add_parser("run", help="Run all local gates or reuse this exact source's valid receipt")
    local.add_argument("--repo", default=str(ROOT))
    local.add_argument("--receipt", required=True)
    publication = subparsers.add_parser("publish", help="Promote validated private evidence to an exact public commit status")
    publication.add_argument("--repo", default=str(ROOT))
    publication.add_argument("--receipt", required=True)
    publication.add_argument("--publication-receipt", required=True)
    publication.add_argument("--public-repo", required=True)
    remote = subparsers.add_parser("check", help="Require the exact public commit's latest full local verification")
    remote.add_argument("--repository", default=REPOSITORY)
    remote.add_argument("--commit", required=True)
    remote.add_argument("--version", required=True)
    args = parser.parse_args(argv)
    try:
        print(json.dumps({"run": run, "publish": publish, "check": check}[args.operation](args), sort_keys=True))
    except (VerificationError, ExportError, OSError, ValueError, KeyError, TypeError,
            subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
