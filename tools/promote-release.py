#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Guard draft promotion with exact-source qualification and fresh public TLS."""

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "deploy/monitoring"))
import tls_check
from health_alerts import atomic_write

_spec = importlib.util.spec_from_file_location("release_verification", Path(__file__).with_name("release-verification.py"))
qualification = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(qualification)
REPOSITORY = qualification.REPOSITORY
MAX_AGE = 300
MAX_INPUT = 256 * 1024


class PromotionError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    with Path(path).open("rb") as stream:
        data = stream.read(MAX_INPUT + 1)
    if len(data) > MAX_INPUT:
        raise PromotionError("input_capacity")
    return json.loads(data)


def api(path, payload=None):
    command = ["gh", "api", "--hostname", "github.com", "-H", "Accept: application/vnd.github+json", path]
    if payload is not None:
        command += ["--method", "PATCH", "--input", "-"]
    result = subprocess.run(command, input=json.dumps(payload) if payload else None,
                            capture_output=True, text=True, timeout=30, check=True)
    if len(result.stdout) > MAX_INPUT:
        raise PromotionError("github_response_capacity")
    return json.loads(result.stdout)


def identity(release, commit, tree):
    """Notes and complete immutable asset identities are reviewed together."""
    assets = release.get("assets")
    if not isinstance(assets, list) or not 3 <= len(assets) <= 64:
        raise PromotionError("invalid_assets")
    rows = []
    for asset in assets:
        name = asset.get("name")
        if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,180}", name)
                or type(asset.get("id")) is not int or type(asset.get("size")) is not int
                or asset["size"] <= 0 or asset.get("state") != "uploaded"):
            raise PromotionError("invalid_assets")
        rows.append({key: asset.get(key) for key in ("id", "name", "size", "digest", "updated_at")})
    names = [row["name"] for row in rows]
    if len(set(names)) != len(names) or not {"SHA256SUMS", "compatibility.json"} <= set(names):
        raise PromotionError("incomplete_assets")
    return {"repository": REPOSITORY, "commit": commit, "tree": tree,
            "releaseId": release["id"], "tag": release["tag_name"],
            "name": release.get("name"), "prerelease": release.get("prerelease"),
            "bodySha256": digest((release.get("body") or "").encode()),
            "assets": sorted(rows, key=lambda row: row["name"])}


def identity_digest(value):
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def tag_commit(tag, github):
    ref = github(f"repos/{REPOSITORY}/git/ref/tags/{tag}")
    obj = ref["object"]
    for _ in range(4):
        qualification.oid(obj["sha"])
        if obj.get("type") == "commit":
            return obj["sha"]
        if obj.get("type") != "tag":
            break
        obj = github(f"repos/{REPOSITORY}/git/tags/{obj['sha']}")["object"]
    raise PromotionError("invalid_tag")


def trusted_mode(path):
    config = read_json(path)
    if config.get("activation") != "active" or config.get("release", {}).get("publishMode") != "publish-after-checks":
        raise PromotionError("publication_not_enabled")
    return config


def verify_readiness(receipt, frozen, source, operations, github, asset_directory, attest):
    """The independent reviewer supplies readiness; executable gates recheck artifacts."""
    review = receipt.get("review", {})
    allowed = operations.get("native", {}).get("allowedAgentIds", [])
    if (receipt.get("schemaVersion") != 1 or receipt.get("identitySha256") != identity_digest(frozen)
            or review.get("verdict") != "APPROVE" or review.get("reviewerId") not in allowed
            or review.get("implementerId") not in allowed
            or review["reviewerId"] == review["implementerId"]
            or not review.get("evidenceRef")
            or receipt.get("updateReadiness", {}).get("result") != "pass"
            or not receipt["updateReadiness"].get("evidenceRef")):
        raise PromotionError("missing_independent_readiness")
    packaging = receipt.get("packaging", {})
    run_id = packaging.get("runId")
    if type(run_id) is not int or run_id < 1:
        raise PromotionError("missing_packaging")
    run = github(f"repos/{REPOSITORY}/actions/runs/{run_id}")
    if (run.get("head_sha") != source["sourceCommit"] or run.get("conclusion") != "success"
            or run.get("event") != "push" or run.get("head_branch") != frozen["tag"]
            or run.get("path") != ".github/workflows/release.yml"):
        raise PromotionError("unqualified_packaging")
    hashes = packaging.get("sha256")
    if not isinstance(hashes, dict) or set(hashes) != {item["name"] for item in frozen["assets"]}:
        raise PromotionError("incomplete_packaging")
    for asset in frozen["assets"]:
        path = asset_directory / asset["name"]
        if path.is_symlink() or not path.is_file() or path.stat().st_size != asset["size"]:
            raise PromotionError("asset_identity_drift")
        actual = qualification.sha256(path)
        if actual != hashes[asset["name"]] or (asset["digest"] and asset["digest"] != "sha256:" + actual):
            raise PromotionError("asset_identity_drift")
        attest(path, frozen["tag"], source["sourceCommit"])
    checksums = (asset_directory / "SHA256SUMS").read_text().splitlines()
    expected = {name: sha for name, sha in hashes.items() if name != "SHA256SUMS"}
    actual = {}
    for line in checksums:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]{0,180})", line)
        if not match or match[2] in actual:
            raise PromotionError("invalid_checksums")
        actual[match[2]] = match[1]
    if actual != expected:
        raise PromotionError("incomplete_checksums")
    compatibility = read_json(asset_directory / "compatibility.json")
    canonical = read_json(Path(source["repo"]) / "protocol/v3/wire-schema.json")
    if (compatibility.get("schemaVersion") != 1
            or compatibility.get("applicationVersion") != source["sourceVersion"]
            or compatibility.get("gameProtocol") != canonical["protocol"]):
        raise PromotionError("compatibility_mismatch")


def attest_asset(path, tag, commit):
    subprocess.run(["gh", "attestation", "verify", str(path), "--repo", REPOSITORY,
                    "--source-ref", "refs/tags/" + tag, "--source-digest", commit,
                    "--signer-workflow", REPOSITORY + "/.github/workflows/release.yml"],
                   capture_output=True, check=True, timeout=90)


def promote(args, github=api, collector=tls_check.collect, wall=time.time,
            attest=attest_asset, qualify=qualification.check, clean=qualification.clean_source):
    operations = trusted_mode(args.operations)
    source = clean(args.repo)
    source["repo"] = str(args.repo)
    version = source["sourceVersion"]
    tag = "v" + version
    if tag != args.tag:
        raise PromotionError("source_version_mismatch")
    release_path = f"repos/{REPOSITORY}/releases/{args.release_id}"
    release = github(release_path)
    if release.get("id") != args.release_id or release.get("tag_name") != tag or release.get("prerelease") is not False:
        raise PromotionError("release_identity_mismatch")
    if tag_commit(tag, github) != source["sourceCommit"]:
        raise PromotionError("tag_identity_drift")
    frozen = identity(release, source["sourceCommit"], source["sourceTree"])
    journal_path = args.journal
    # Existing uncertain intent is read back, never blindly mutated again.
    previous = read_json(journal_path) if journal_path.exists() else None
    if previous and previous.get("phase") in ("intent", "published"):
        if previous.get("identity") != frozen:
            raise PromotionError("promotion_identity_drift")
        if release.get("draft") is False:
            latest = github(f"repos/{REPOSITORY}/releases/latest")
            if latest.get("id") != args.release_id:
                raise PromotionError("published_latest_mismatch")
            return {"result": "PUBLISHED", "releaseId": args.release_id, "reconciled": True}
        raise PromotionError("promotion_uncertain_operator_reconciliation_required")
    if release.get("draft") is not True:
        raise PromotionError("published_release_immutable")
    if args.command == "snapshot":
        return {"identity": frozen, "identitySha256": identity_digest(frozen)}
    receipt = read_json(args.readiness)
    verify_readiness(receipt, frozen, source, operations, github, args.assets, attest)
    check_args = argparse.Namespace(repository=REPOSITORY, commit=source["sourceCommit"], version=version)
    qualified = qualify(check_args)
    if qualified.get("publicTree") != source["sourceTree"]:
        raise PromotionError("source_tree_mismatch")
    inventory = tls_check.read_inventory(args.inventory, args.bootstrap)
    if receipt.get("bootstrapSha256") != inventory["bootstrapSha256"]:
        raise PromotionError("release_bootstrap_mismatch")
    evidence = collector(inventory)
    tls_check.verify_evidence(evidence, inventory, wall(), MAX_AGE)
    binding = {**frozen, "version": version, "inventorySha256": inventory["inventorySha256"],
               "bootstrapSha256": inventory["bootstrapSha256"]}
    journal = {"schemaVersion": 1, "phase": "ready", "identity": frozen, "binding": binding,
               "evidence": evidence, "readinessSha256": qualification.sha256(args.readiness)}
    atomic_write(journal_path, json.dumps(journal, sort_keys=True).encode())
    if args.command == "check":
        return {"result": "READY", "releaseId": args.release_id, "identitySha256": identity_digest(frozen)}
    # Recheck all identities, mode, qualification, and remaining lifetime at mutation.
    trusted_mode(args.operations)
    if clean(args.repo) != {key: value for key, value in source.items() if key != "repo"}:
        raise PromotionError("source_identity_drift")
    qualify(check_args)
    if qualification.sha256(args.readiness) != journal["readinessSha256"]:
        raise PromotionError("readiness_identity_drift")
    current = github(release_path)
    if (current.get("draft") is not True or identity(current, source["sourceCommit"], source["sourceTree"]) != frozen
            or tag_commit(tag, github) != source["sourceCommit"]
            or tls_check.read_inventory(args.inventory, args.bootstrap) != inventory):
        raise PromotionError("release_identity_drift")
    tls_check.verify_evidence(evidence, inventory, wall(), MAX_AGE)
    journal["phase"] = "intent"
    atomic_write(journal_path, json.dumps(journal, sort_keys=True).encode())
    try:
        github(release_path, {"draft": False, "make_latest": "true"})
    except (OSError, ValueError, subprocess.SubprocessError):
        pass  # The request may have succeeded: always reconcile via readback.
    actual = github(release_path)
    if (actual.get("draft") is not False
            or identity(actual, source["sourceCommit"], source["sourceTree"]) != frozen
            or tag_commit(tag, github) != source["sourceCommit"]):
        raise PromotionError("promotion_uncertain")
    journal["phase"] = "published"
    atomic_write(journal_path, json.dumps(journal, sort_keys=True).encode())
    latest = github(f"repos/{REPOSITORY}/releases/latest")
    if latest.get("id") != args.release_id:
        raise PromotionError("published_latest_mismatch")
    return {"result": "PUBLISHED", "releaseId": args.release_id, "identitySha256": identity_digest(frozen)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("snapshot", "check", "promote"))
    for name in ("repo", "operations", "inventory", "bootstrap", "readiness", "assets"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--release-id", required=True, type=int)
    args = parser.parse_args(argv)
    # All release entry points use this operator-owned path, never a per-run lock.
    # The task's single-writer policy still applies across other hosts/operators.
    try:
        operations = trusted_mode(args.operations)
        state = Path(operations["host"]["privateStateDirectory"]) / "release-promotion"
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        args.journal = qualification.evidence_path(args.repo.resolve(), state / (str(args.release_id) + ".json"))
        fd = os.open(state / "lock", os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print(json.dumps(promote(args), sort_keys=True))
        finally:
            os.close(fd)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        parser.exit(1, "release_promotion_refused; inspect private gate evidence\n")


if __name__ == "__main__":
    main()
