#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Verify a pinned, attested feedback-only Actions package for the installer."""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ".github/workflows/feedback.yml"
MAX_BYTES = 64 << 20


def _positive_integer(value):
    return type(value) is int and value > 0


def _metadata(backend, repo, version, arch, run_id, artifact_id, head_sha):
    def api(suffix):
        value = json.loads(backend.github("api", f"repos/{repo}/{suffix}"))
        if not isinstance(value, dict):
            raise ValueError("Invalid feedback build metadata")
        return value

    run = api(f"actions/runs/{run_id}")
    artifact = api(f"actions/artifacts/{artifact_id}")
    workflow = api("actions/workflows/feedback.yml")
    repository, head_repository = run.get("repository"), run.get("head_repository")
    if not isinstance(repository, dict) or not isinstance(head_repository, dict):
        raise ValueError("Feedback build repository identity is missing")
    repository_id = repository.get("id")
    if (repository.get("full_name") != repo or not _positive_integer(repository_id)
            or head_repository.get("full_name") != repo or head_repository.get("id") != repository_id
            or run.get("id") != run_id or run.get("event") != "workflow_dispatch"
            or run.get("status") != "completed" or run.get("conclusion") != "success"
            or run.get("head_sha") != head_sha or run.get("head_branch") != "master"
            or run.get("path") != WORKFLOW or workflow.get("path") != WORKFLOW
            or not _positive_integer(workflow.get("id")) or workflow["id"] != run.get("workflow_id")
            or not _positive_integer(run.get("run_attempt"))):
        raise ValueError("Feedback update requires the successful registered manual workflow on exact master source")
    artifact_run = artifact.get("workflow_run")
    if (not isinstance(artifact_run, dict) or artifact.get("id") != artifact_id
            or artifact.get("name") != f"hexproof-feedback-{head_sha}-linux-{arch}"
            or artifact.get("expired") is not False
            or not isinstance(artifact.get("digest"), str)
            or not re.fullmatch(r"sha256:[a-f0-9]{64}", artifact["digest"])
            or type(artifact.get("size_in_bytes")) is not int
            or not 0 < artifact["size_in_bytes"] <= MAX_BYTES
            or artifact_run.get("id") != run_id or artifact_run.get("head_sha") != head_sha
            or artifact_run.get("repository_id") != repository_id
            or artifact_run.get("head_repository_id") != repository_id):
        raise ValueError("Feedback artifact is expired, oversized or belongs to another build")

    source = api(f"contents/{WORKFLOW}?ref={head_sha}")
    try:
        workflow_bytes = base64.b64decode("".join(source["content"].split()), validate=True)
    except (KeyError, ValueError, TypeError, AttributeError):
        raise ValueError("Feedback workflow source could not be verified") from None
    if (source.get("encoding") != "base64" or source.get("path") != WORKFLOW
            or source.get("type") != "file" or workflow_bytes != (ROOT / WORKFLOW).read_bytes()):
        raise ValueError("Feedback workflow differs from the trusted local workflow")
    pages = json.loads(backend.github("api", "--paginate", "--slurp",
        f"repos/{repo}/actions/runs/{run_id}/attempts/{run['run_attempt']}/jobs?per_page=100"))
    if (not isinstance(pages, list) or not pages
            or any(not isinstance(page, dict) or not isinstance(page.get("jobs"), list) for page in pages)):
        raise ValueError("Feedback build jobs could not be verified")
    jobs = [job for page in pages for job in page["jobs"]]
    if (len(jobs) != 1 or not isinstance(jobs[0], dict) or jobs[0].get("name") != "Build feedback service"
            or jobs[0].get("status") != "completed" or jobs[0].get("conclusion") != "success"):
        raise ValueError("Feedback artifact lacks its exact successful build job")
    steps = jobs[0].get("steps")
    if not isinstance(steps, list) or any(not isinstance(step, dict) for step in steps):
        raise ValueError("Feedback build steps could not be verified")
    for name in ("Verify feedback service", "Attest feedback package", "Upload feedback package"):
        matches = [step for step in steps if step.get("name") == name]
        if len(matches) != 1 or matches[0].get("conclusion") != "success":
            raise ValueError("Feedback build lacks a successful required step: " + name)
    return {"mode": "actions-feedback-update", "repository": repo, "repositoryId": repository_id,
            "version": version, "headSha": head_sha, "runId": run_id, "runAttempt": run["run_attempt"],
            "artifactId": artifact_id, "artifactDigest": artifact["digest"],
            "artifactSize": artifact["size_in_bytes"], "workflowSha256": hashlib.sha256(workflow_bytes).hexdigest(),
            "architecture": arch}


def _private_output(path):
    # Never follow a pre-existing report symlink or overwrite an earlier proof.
    return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "wb")


def _digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def fetch_component(backend, repo, version, arch, report: Path, run_id: int, artifact_id: int, head_sha: str):
    """Return verified package bytes; the caller still validates the tar layout."""
    if (not isinstance(repo, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repo)
            or not isinstance(version, str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version)
            or arch not in ("amd64", "arm64") or not _positive_integer(run_id)
            or not _positive_integer(artifact_id) or not isinstance(head_sha, str)
            or not re.fullmatch(r"[a-f0-9]{40}", head_sha)):
        raise ValueError("Feedback update requires explicit repository, version, architecture and pinned build IDs")
    if report.is_symlink() or not report.is_dir():
        raise ValueError("Feedback report must be an existing directory")
    provenance = _metadata(backend, repo, version, arch, run_id, artifact_id, head_sha)
    archive = report / "feedback-component-artifact.zip"
    with _private_output(archive) as output:
        subprocess.run(["gh", "api", f"repos/{repo}/actions/artifacts/{artifact_id}/zip"],
                       stdout=output, check=True, timeout=600)
    if (archive.stat().st_size != provenance["artifactSize"]
            or "sha256:" + _digest(archive) != provenance["artifactDigest"]):
        raise ValueError("Feedback artifact ZIP digest or size differs from GitHub")

    package_name = f"hexproof-feedback-{version}-linux-{arch}.tar.gz"
    package = report / package_name
    try:
        with zipfile.ZipFile(archive) as bundle:
            entries = bundle.infolist()
            if len(entries) != 1:
                raise ValueError("Feedback artifact must contain exactly one package")
            entry = entries[0]
            mode = stat.S_IFMT(entry.external_attr >> 16)
            if (entry.filename != package_name or entry.is_dir() or entry.flag_bits & 1
                    or entry.external_attr & 0x10 or mode not in (0, stat.S_IFREG)
                    or not 0 < entry.file_size <= MAX_BYTES):
                raise ValueError("Unexpected feedback artifact entry, type or size")
            with bundle.open(entry) as source, _private_output(package) as output:
                copied = 0
                for chunk in iter(lambda: source.read(1 << 20), b""):
                    copied += len(chunk)
                    if copied > entry.file_size or copied > MAX_BYTES:
                        raise ValueError("Feedback package exceeds its declared size")
                    output.write(chunk)
                if copied != entry.file_size:
                    raise ValueError("Feedback package is truncated")
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        raise ValueError("Invalid feedback artifact ZIP") from error

    package_sha = _digest(package)
    attestation = backend.github("attestation", "verify", str(package), "--repo", repo,
        "--signer-workflow", repo + "/" + WORKFLOW, "--source-digest", head_sha,
        "--source-ref", "refs/heads/master", "--format", "json")
    if not json.loads(attestation):
        raise ValueError("Feedback package lacks verified attestation results")
    with _private_output(report / "feedback-component-attestation.json") as output:
        output.write(attestation.encode("utf-8"))
    if _metadata(backend, repo, version, arch, run_id, artifact_id, head_sha) != provenance:
        raise ValueError("Feedback build provenance changed during verification")
    if _digest(package) != package_sha:
        raise ValueError("Feedback package changed during verification")
    provenance.update(packageSha256=package_sha, componentAttested=True)
    with _private_output(report / "component-provenance.json") as output:
        output.write((json.dumps(provenance, indent=2) + "\n").encode("utf-8"))
    return {"path": str(package), "sha256": package_sha}, provenance
