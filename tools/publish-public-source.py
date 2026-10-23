#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Publish one filtered merged snapshot with ordinary Git and a private retry receipt."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit

from public_source_export import ExportError, export_snapshot, policy_digest, tree_manifest


class PublicationError(ValueError):
    """The requested source or public branch does not match the publication intent."""


def git(repo, *args, data=None, extra_env=None, allow_failure=False):
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update({"GIT_TERMINAL_PROMPT": "0", **(extra_env or {})})
    result = subprocess.run(
        ["git", "--no-replace-objects", "--literal-pathspecs", "-c", "core.hooksPath=/dev/null",
         "-c", "core.fsmonitor=false", "-c", "protocol.ext.allow=never", "-C", str(repo), *args],
        input=data, capture_output=True, env=env)
    if result.returncode and not allow_failure:
        raise PublicationError(f"Git {args[0]} failed: {result.stderr.decode(errors='replace').strip()}")
    return result


def output(repo, *args, **kwargs):
    return git(repo, *args, **kwargs).stdout.decode().strip()


def object_id(value):
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", value):
        raise PublicationError("An exact lowercase Git object ID is required")
    return value


def commit(repo, value):
    value = object_id(value)
    if output(repo, "cat-file", "-t", value) != "commit":
        raise PublicationError("Source and parent object IDs must name commits")
    return value


def ref(repo, value, *, public=False):
    if not value.startswith("refs/") or (public and not value.startswith("refs/heads/")):
        raise PublicationError("Use a fully qualified source ref and a public refs/heads/ ref")
    git(repo, "check-ref-format", value)
    return value


def public_location(source_repo, value):
    # Explicit safe transports keep credentials and arbitrary transport commands out of receipts.
    remotes = [output(source_repo, "remote", "get-url", remote)
               for remote in output(source_repo, "remote").splitlines()]
    if Path(value).is_absolute():
        target = Path(value).resolve()
        source_git = Path(output(source_repo, "rev-parse", "--absolute-git-dir")).resolve()
        private_paths = [Path(remote).resolve() for remote in remotes if Path(remote).is_absolute()]
        if target in (Path(source_repo).resolve(), source_git, *private_paths):
            raise PublicationError("Public destination must be separate from the private repository")
        return str(target)

    def github_identity(location):
        location = re.sub(r"^git@github\.com:", "https://github.com/", location, flags=re.IGNORECASE)
        parsed = urlsplit(location)
        if parsed.hostname == "github.com":
            return parsed.path.casefold().removesuffix(".git").strip("/")
        return None

    identity = github_identity(value)
    if identity and any(identity == github_identity(remote) for remote in remotes):
        raise PublicationError("Public destination must not be a private source remote")
    if re.fullmatch(r"git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?", value):
        return value
    parsed = urlsplit(value)
    if (parsed.scheme == "https" and parsed.hostname == "github.com" and parsed.port in (None, 443) and not parsed.username
            and not parsed.password and not parsed.query and not parsed.fragment
            and re.fullmatch(r"/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?", parsed.path)):
        return value
    raise PublicationError("Use a credential-free GitHub HTTPS/SSH URL or an absolute local Git path")


def ancestor(repo, older, newer):
    result = git(repo, "merge-base", "--is-ancestor", older, newer, allow_failure=True)
    if result.returncode not in (0, 1):
        raise PublicationError("Cannot establish Git ancestry")
    return result.returncode == 0


def has_commit(repo, value):
    object_id(value)
    result = git(repo, "cat-file", "-t", value, allow_failure=True)
    return result.returncode == 0 and result.stdout.strip() == b"commit"


def current_source(repo, source_ref, source_commit):
    if output(repo, "rev-parse", "--verify", source_ref + "^{commit}") != source_commit:
        raise PublicationError("Source commit is stale: it must equal the refreshed merged source ref")


def observe(repo, location, public_ref, sequence):
    advertised = output(repo, "ls-remote", "--refs", location, public_ref)
    if not advertised:
        return None
    lines = advertised.splitlines()
    if len(lines) != 1 or lines[0].split("\t")[1] != public_ref:
        raise PublicationError("Unexpected public branch advertisement")
    destination = f"refs/observed/{sequence}"
    git(repo, "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", location,
        f"{public_ref}:{destination}")
    # Fetch can observe a later tip than ls-remote. The caller checks the fetched tip.
    return commit(repo, output(repo, "rev-parse", destination))


def write_receipt(path, value):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix=".publication-", dir=path.parent,
                                     delete=False) as stream:
        temporary = Path(stream.name)
        try:
            os.chmod(temporary, 0o600)
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
            os.replace(temporary, path)
            directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            temporary.unlink(missing_ok=True)


def exported_tree(public_repo, tree):
    records = []
    for entry in tree_manifest(tree)["files"]:
        path = tree / entry["path"]
        data = os.fsencode(os.readlink(path)) if entry["mode"] == "120000" else path.read_bytes()
        blob = output(public_repo, "hash-object", "-w", "--stdin", data=data)
        records.append(f"{entry['mode']} {blob}\t{entry['path']}".encode() + b"\0")
    # Plumbing hashes the already validated bytes; checkout filters and candidate hooks never run.
    git(public_repo, "read-tree", "--empty")
    git(public_repo, "update-index", "-z", "--index-info", data=b"".join(records))
    return output(public_repo, "write-tree")


def provenance(repo, parent):
    # A public documentation commit may lack a trailer; it cannot erase the last watermark.
    messages = output(repo, "log", "--first-parent", "--format=%B%x00", parent).split("\0")
    for message in messages:
        values = re.findall(r"^[ \t]*Hexproof-Source-Commit[ \t]*:(.*)$", message,
                            re.MULTILINE | re.IGNORECASE)
        if values:
            if len(values) != 1 or not re.fullmatch(r" (?:[0-9a-f]{40}|[0-9a-f]{64})", values[0]):
                raise PublicationError("Public parent has malformed or ambiguous source provenance")
            return values[0][1:]
    return None


def make_commit(public_repo, source_repo, source_commit, parent, tree, manifest):
    stamp = output(source_repo, "show", "-s", "--format=%ct", source_commit)
    identity = {"GIT_AUTHOR_NAME": "Hexproof source publisher", "GIT_AUTHOR_EMAIL": "source@hexproof.invalid",
                "GIT_COMMITTER_NAME": "Hexproof source publisher", "GIT_COMMITTER_EMAIL": "source@hexproof.invalid",
                "GIT_AUTHOR_DATE": f"@{stamp} +0000", "GIT_COMMITTER_DATE": f"@{stamp} +0000"}
    message = (f"Publish filtered source\n\nHexproof-Source-Commit: {source_commit}\n"
               f"Hexproof-Export-Policy: {manifest['exportPolicyDigest']}\n"
               f"Hexproof-Export-Tree: {manifest['exportTreeDigest']}\n").encode()
    parents = ["-p", parent] if parent else []
    return output(public_repo, "-c", "commit.gpgSign=false", "commit-tree", tree, *parents,
                  data=message, extra_env=identity)


def publish(args):
    source_repo = Path(args.source_repo).resolve()
    source_commit = commit(source_repo, args.source_commit)
    source_ref = ref(source_repo, args.source_ref)
    public_ref = ref(source_repo, args.public_ref, public=True)
    location = public_location(source_repo, args.public_repo)
    parent = None if args.expected_public_head == "none" else object_id(args.expected_public_head)
    baseline = commit(source_repo, args.baseline_source_commit) if args.baseline_source_commit else None
    adoption = args.adopt_public_parent
    if baseline and adoption:
        raise PublicationError("Choose a verified legacy baseline or explicit legacy parent adoption")
    intent = {"schemaVersion": 1, "sourceCommit": source_commit, "sourceRef": source_ref,
              "publicRepository": location, "publicRef": public_ref, "publicParent": parent,
              "baselineSourceCommit": baseline, "adoptPublicParent": adoption,
              "exportPolicyDigest": policy_digest(args.policy)}
    receipt_path = Path(args.receipt)
    if not receipt_path.is_absolute() or receipt_path.is_symlink():
        raise PublicationError("Receipt must be an absolute private path without a final symlink")
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(str(receipt_path) + ".lock", os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "w", encoding="utf-8") as lock:
        os.fchmod(lock.fileno(), 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        saved = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        if saved and saved.get("intent") != intent:
            raise PublicationError("Receipt belongs to a different immutable publication intent")
        with tempfile.TemporaryDirectory(prefix="hexproof-publication-") as temporary:
            workspace = Path(temporary)
            public_repo = workspace / "public.git"
            public_format = "sha256" if parent and len(parent) == 64 else "sha1"
            git(workspace, "init", "--quiet", "--bare", f"--object-format={public_format}", str(public_repo))
            observed = observe(public_repo, location, public_ref, 1)
            if (saved and observed and has_commit(public_repo, saved["publicCommit"])
                    and ancestor(public_repo, saved["publicCommit"], observed)):
                saved.update(state="published", observedPublicHead=observed)
                write_receipt(receipt_path, saved)
                return saved
            if observed != parent:
                raise PublicationError("Public branch changed unexpectedly; reconcile instead of overwriting it")
            if saved and saved.get("state") == "published":
                raise PublicationError("Previously published commit is no longer on the public branch")
            current_source(source_repo, source_ref, source_commit)
            manifest = export_snapshot(source_repo, source_commit, workspace / "tree", args.policy)
            tree = exported_tree(public_repo, workspace / "tree")
            if parent:
                previous_source = provenance(public_repo, parent)
                if previous_source:
                    if adoption:
                        raise PublicationError("Parent adoption cannot bypass existing public source provenance")
                    if baseline and baseline != previous_source:
                        raise PublicationError("Baseline source conflicts with public parent provenance")
                    commit(source_repo, previous_source)
                else:
                    if not baseline and not adoption:
                        raise PublicationError("Legacy public parent needs an exact --baseline-source-commit")
                    if baseline:
                        export_snapshot(source_repo, baseline, workspace / "baseline", args.policy)
                        baseline_tree = exported_tree(public_repo, workspace / "baseline")
                        if baseline_tree != output(public_repo, "rev-parse", parent + "^{tree}"):
                            raise PublicationError("Baseline export does not match the legacy public parent tree")
                        previous_source = baseline
                if previous_source and not ancestor(source_repo, previous_source, source_commit):
                    raise PublicationError("Source would regress or diverge from the published source")
            elif baseline or adoption:
                raise PublicationError("An empty public branch does not need a legacy baseline or parent adoption")
            candidate = make_commit(public_repo, source_repo, source_commit, parent, tree, manifest)
            if saved and (saved.get("publicCommit") != candidate or saved.get("export") != manifest):
                raise PublicationError("Rebuilt public commit differs from the saved publication intent")
            result = saved or {"intent": intent, "export": manifest, "publicCommit": candidate, "state": "prepared",
                               "historicalSourceMapping": "unknown" if adoption else "verified" if parent else "absent"}
            write_receipt(receipt_path, result)
            if args.prepare_only:
                return result
            current_source(source_repo, source_ref, source_commit)
            if observe(public_repo, location, public_ref, 2) != parent:
                raise PublicationError("Public branch changed before push; reconcile before retry")
            result["state"] = "uncertain"
            write_receipt(receipt_path, result)
            pushed = git(public_repo, "push", "--porcelain", location, f"{candidate}:{public_ref}", allow_failure=True)
            observed = observe(public_repo, location, public_ref, 3)
            if not observed or not ancestor(public_repo, candidate, observed):
                detail = pushed.stderr.decode(errors="replace").strip()
                raise PublicationError(f"Publication unconfirmed; retain the receipt and retry reconciliation. {detail}")
            result.update(state="published", observedPublicHead=observed)
            write_receipt(receipt_path, result)
            return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source-repo", "source-commit", "source-ref", "public-repo", "public-ref",
                 "expected-public-head", "receipt", "policy"):
        parser.add_argument("--" + name, required=True)
    legacy = parser.add_mutually_exclusive_group()
    legacy.add_argument("--baseline-source-commit", help="Exact prior source whose export equals a legacy public parent")
    legacy.add_argument("--adopt-public-parent", action="store_true",
                        help="Explicitly adopt the exact legacy public parent with unknown historical source mapping")
    parser.add_argument("--prepare-only", action="store_true", help="Write the intent and public commit identity without pushing")
    args = parser.parse_args(argv)
    try:
        result = publish(args)
        print(json.dumps(result, sort_keys=True))
    except (PublicationError, ExportError, OSError, UnicodeError, json.JSONDecodeError,
            subprocess.SubprocessError, KeyError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
