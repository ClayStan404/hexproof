#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Internal feedback component for deploy-release-server.sh; deploy verified build bytes."""

from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path("/etc/hexproof-feedback/config.json")
PASSWORD = Path("/etc/hexproof-feedback/smtp-password")
GITHUB_TOKEN = Path("/etc/hexproof-feedback/github-token")
MULTICA_WEBHOOK = Path("/etc/hexproof-feedback/multica-webhook")
DATA = Path("/var/lib/hexproof-feedback")
PUBLIC_DATA = Path("/var/lib/hexproof-feedback-public")
BINARY = Path("/usr/local/bin/hexproof-feedback")
UNIT = Path("/etc/systemd/system/hexproof-feedback.service")
SERVICE = "hexproof-feedback.service"
BACKUPS = Path("/var/lib/hexproof-feedback-install")
TEST_PROVENANCE = CONFIG.parent / "test-provenance.json"
COMPONENT_PROVENANCE = CONFIG.parent / "component-provenance.json"
RELEASE_WORKFLOW = ".github/workflows/release.yml"
SYSTEMD_UNIT_DIRECTORIES = tuple(Path(root) / "systemd/system"
                                 for root in ("/etc", "/run", "/usr/lib", "/lib"))
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
               "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3"]


def run(*args, **kwargs):
    return subprocess.check_output(list(map(str, args)), text=True, timeout=60, **kwargs).strip()


def ssh(target, *args):
    return run("ssh", *SSH_OPTIONS, target, shlex.join(list(map(str, args))))


def load_backend():
    spec = importlib.util.spec_from_file_location("feedback_release_backend", ROOT / "deploy/deploy-home-release.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_component():
    spec = importlib.util.spec_from_file_location("feedback_component", Path(__file__).with_name("component.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def test_build_metadata(backend, repo, version, run_id, artifact_id, head_sha):
    """Bind an artifact-only manual build to the reviewed source and workflow."""
    def api(suffix):
        return json.loads(backend.github("api", f"repos/{repo}/{suffix}"))

    run_info = api(f"actions/runs/{run_id}")
    artifact = api(f"actions/artifacts/{artifact_id}")
    workflow = api("actions/workflows/release.yml")
    repository = run_info.get("repository", {})
    repository_id = repository.get("id")
    if (repository.get("full_name") != repo or type(repository_id) is not int or repository_id < 1
            or run_info.get("head_repository", {}).get("id") != repository_id
            or run_info.get("id") != run_id or run_info.get("event") != "workflow_dispatch"
            or run_info.get("status") != "completed" or run_info.get("conclusion") != "success"
            or run_info.get("head_sha") != head_sha or run_info.get("head_branch") != "master"
            or run_info.get("path") != RELEASE_WORKFLOW
            or workflow.get("path") != RELEASE_WORKFLOW
            or workflow.get("id") != run_info.get("workflow_id")
            or type(run_info.get("run_attempt")) is not int or run_info["run_attempt"] < 1):
        raise ValueError("Test build must be a successful manual release workflow on the exact reviewed master source")
    artifact_run = artifact.get("workflow_run", {})
    if (artifact.get("id") != artifact_id or artifact.get("name") != f"Hexproof-{version}-release"
            or artifact.get("expired") is not False
            or not re.fullmatch(r"sha256:[a-f0-9]{64}", artifact.get("digest") or "")
            or type(artifact.get("size_in_bytes")) is not int
            or not 0 < artifact["size_in_bytes"] <= 3 << 30
            or artifact_run.get("id") != run_id or artifact_run.get("head_sha") != head_sha
            or artifact_run.get("repository_id") != repository_id
            or artifact_run.get("head_repository_id") != repository_id):
        raise ValueError("Test artifact is expired, unpinned or belongs to another build")
    workflow_source = api(f"contents/{RELEASE_WORKFLOW}?ref={head_sha}")
    try:
        workflow_bytes = base64.b64decode(workflow_source["content"], validate=False)
    except (KeyError, ValueError, TypeError):
        raise ValueError("Test workflow source could not be verified") from None
    if (workflow_source.get("encoding") != "base64"
            or workflow_bytes != (ROOT / RELEASE_WORKFLOW).read_bytes()):
        raise ValueError("Test workflow differs from the trusted local release workflow")
    pages = json.loads(backend.github("api", "--paginate", "--slurp",
        f"repos/{repo}/actions/runs/{run_id}/attempts/{run_info['run_attempt']}/jobs?per_page=100"))
    jobs = [job for page in pages for job in page.get("jobs", [])]
    assemblies = [job for job in jobs if job.get("name") == "Assemble release"]
    if len(assemblies) != 1 or assemblies[0].get("conclusion") != "success":
        raise ValueError("Test artifact lacks a successful combined assembly")
    steps = {step.get("name"): step.get("conclusion") for step in assemblies[0].get("steps", [])}
    # In the byte-verified workflow these steps run only for tag builds. Their
    # skipped conclusions establish artifact-only mode even if a tag is named master.
    if (steps.get("Upload combined release bundle") != "success"
            or steps.get("Attest release assets") != "skipped"
            or steps.get("Create or update draft release") != "skipped"):
        raise ValueError("Test installation requires an artifact-only, non-tag build")
    return {"mode": "actions-test-initial-install", "repository": repo,
            "repositoryId": repository_id, "version": version, "headSha": head_sha,
            "runId": run_id, "runAttempt": run_info["run_attempt"], "artifactId": artifact_id,
            "artifactDigest": artifact["digest"], "artifactSize": artifact["size_in_bytes"],
            "workflowSha256": hashlib.sha256(workflow_bytes).hexdigest(),
            "releaseAttested": False}


def fetch_test_build(backend, repo, version, arch, report, run_id, artifact_id, head_sha, cached_zip=None):
    provenance = test_build_metadata(backend, repo, version, run_id, artifact_id, head_sha)
    archive = report / "actions-artifact.zip"
    if cached_zip is not None:
        if not cached_zip.is_absolute() or cached_zip.is_symlink() or not cached_zip.is_file():
            raise ValueError("Cached test artifact must be an absolute regular ZIP file")
        shutil.copyfile(cached_zip, archive)
    else:
        with archive.open("wb") as output:
            subprocess.run(["gh", "api", f"repos/{repo}/actions/artifacts/{artifact_id}/zip"],
                           stdout=output, check=True, timeout=600)
    if (archive.stat().st_size != provenance["artifactSize"]
            or "sha256:" + digest(archive) != provenance["artifactDigest"]):
        raise ValueError("Test artifact ZIP digest or size differs from GitHub")
    names = {f"Hexproof-{version}-linux-x86_64.tar.gz", f"Hexproof-{version}-windows-x64.zip",
             f"Hexproof-{version}-macos-arm64.zip", f"hexproof-server-{version}-linux-amd64.tar.gz",
             f"hexproof-server-{version}-linux-arm64.tar.gz", "hexproof-forge-overlay-source.tar.gz",
             "compatibility.json", "SHA256SUMS"}
    package_name = f"hexproof-server-{version}-linux-{arch}.tar.gz"
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        if (len(entries) != len(names) or {item.filename for item in entries} != names
                or any(item.is_dir() or item.flag_bits & 1 or stat.S_ISLNK(item.external_attr >> 16)
                       or not 0 < item.file_size <= 2 << 30 for item in entries)
                or sum(item.file_size for item in entries) > 3 << 30
                or bundle.getinfo("SHA256SUMS").file_size > 16384
                or bundle.getinfo("compatibility.json").file_size > 1024):
            raise ValueError("Unexpected test artifact layout or size")
        checksums = {}
        for line in bundle.read("SHA256SUMS").decode("ascii").splitlines():
            match = re.fullmatch(r"([a-f0-9]{64})  ([^/\\]+)", line)
            if not match or match[2] in checksums:
                raise ValueError("Invalid test artifact checksums")
            checksums[match[2]] = match[1]
        if set(checksums) != names - {"SHA256SUMS"}:
            raise ValueError("Incomplete test artifact checksums")
        compatibility_bytes = bundle.read("compatibility.json")
        compatibility = load_json(compatibility_bytes)
        if (hashlib.sha256(compatibility_bytes).hexdigest() != checksums["compatibility.json"]
                or compatibility != {"schemaVersion": 1, "applicationVersion": version,
                                      "gameProtocol": "hexproof.v2"}):
            raise ValueError("Test artifact compatibility does not match the requested version")
        package = report / package_name
        for name, expected in checksums.items():
            checksum = hashlib.sha256()
            with bundle.open(name) as source:
                if name == package_name:
                    with package.open("wb") as destination:
                        for chunk in iter(lambda: source.read(1 << 20), b""):
                            checksum.update(chunk)
                            destination.write(chunk)
                else:
                    for chunk in iter(lambda: source.read(1 << 20), b""):
                        checksum.update(chunk)
            if checksum.hexdigest() != expected:
                raise ValueError("Test package checksum mismatch: " + name)
    if test_build_metadata(backend, repo, version, run_id, artifact_id, head_sha) != provenance:
        raise ValueError("Test build provenance changed during verification")
    provenance.update(architecture=arch, packageSha256=checksums[package_name])
    (report / "test-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    return {"path": str(package), "sha256": checksums[package_name]}, provenance


def verify_feedback_architecture(binary, arch):
    with binary.open("rb") as stream:
        header = stream.read(20)
    if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
            or int.from_bytes(header[18:20], "little") != {"amd64": 62, "arm64": 183}[arch]):
        raise ValueError("Feedback binary architecture differs from the explicit target")


def verify_component_archive(path, version, arch):
    root = f"hexproof-feedback-{version}-linux-{arch}"
    files = {root + "/bin/hexproof-feedback", root + "/deploy/hexproof-feedback.service.in", root + "/build.json"}
    directories = {root, root + "/bin", root + "/deploy"}
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        names = [item.name.rstrip("/") for item in members]
        if (len(names) != len(set(names)) or set(names) - files - directories
                or {item.name for item in members if item.isfile()} != files
                or sum(item.size for item in members) > 64 << 20
                or any(not ((item.isfile() and item.name in files)
                            or (item.isdir() and item.name.rstrip("/") in directories)) for item in members)):
            raise ValueError("Invalid feedback component archive layout")


def test_installation_paths():
    return (CONFIG.parent, DATA, PUBLIC_DATA, BINARY, UNIT, BACKUPS,
            *(directory / (SERVICE + ".d") for directory in SYSTEMD_UNIT_DIRECTORIES))


def require_empty_test_installation():
    # A manual Actions build must never replace a deployed receiver or inherit
    # real feedback. This guard runs on the target again immediately before writes.
    paths = test_installation_paths()
    if any(path.exists() or path.is_symlink() for path in paths):
        raise ValueError("Test installation requires absent feedback files and state directories")
    if run("systemctl", "show", SERVICE, "--property=LoadState", "--value") != "not-found":
        raise ValueError("Test installation requires an absent feedback service")


def load_json(raw):
    def unique_fields(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("Duplicate feedback JSON field")
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique_fields)


def read_input(path, label, *, private=False, limit=16384):
    if not isinstance(path, (str, Path)) or not Path(path).is_absolute():
        raise ValueError(f"{label} must be an absolute bounded regular file")
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_size > limit or
                    private and (info.st_mode & 0o077 or info.st_size == 0)):
                raise ValueError(f"{label} must be a private bounded regular file" if private else
                                 f"{label} must be a bounded regular file")
            content = stream.read(limit + 1)
            if len(content) > limit:
                raise ValueError(f"{label} exceeds its size limit")
            return content
    except OSError as error:
        raise ValueError(f"{label} is unavailable or not a regular file") from error


def credential_paths(config):
    """Validate managed paths without duplicating the release binary's config validator."""
    if (not isinstance(config, dict) or type(config.get("schemaVersion")) is not int or
            config["schemaVersion"] not in (1, 2)):
        raise ValueError("Use a supported receiver configuration")
    if config.get("dataDir") != str(DATA) or config.get("adminSocket", str(DATA / "admin.sock")) != str(DATA / "admin.sock"):
        raise ValueError("This service component uses the dedicated feedback state directory")
    if not config.get("monitoringConfigured") or not config.get("operatorName"):
        raise ValueError("A named operator and independent monitoring are required")
    expected = {}
    smtp = config.get("smtp", {})
    if not isinstance(smtp, dict):
        raise ValueError("Invalid SMTP configuration")
    if smtp.get("passwordFile") or smtp.get("username"):
        if smtp.get("passwordFile") != str(PASSWORD):
            raise ValueError("SMTP configuration must reference the dedicated remote credential file")
        expected["smtp-password"] = PASSWORD
    public = config.get("public")
    if config["schemaVersion"] == 2:
        if not isinstance(public, dict) or public.get("dataDir") != str(PUBLIC_DATA):
            raise ValueError("Public feedback uses its separate dedicated state directory")
        if public.get("tokenFile") != str(GITHUB_TOKEN):
            raise ValueError("Public configuration must reference the dedicated GitHub credential file")
        expected["github-token"] = GITHUB_TOKEN
    elif public is not None:
        raise ValueError("Public configuration requires receiver schemaVersion 2")
    multica = config.get("multica")
    if multica is not None:
        if config["schemaVersion"] != 2 or not isinstance(multica, dict):
            raise ValueError("Multica requires public receiver configuration")
        if multica.get("webhookFile") != str(MULTICA_WEBHOOK):
            raise ValueError("Multica configuration must reference the dedicated webhook credential file")
        if multica.get("socket") != str(DATA / "native.sock"):
            raise ValueError("Multica socket must be native.sock in the legacy state directory")
        expected["multica-webhook"] = MULTICA_WEBHOOK
    return expected


def inputs(path, target):
    value = load_json(read_input(path, "Feedback inputs"))
    required = {"schemaVersion", "target", "arch", "configFile"}
    credentials = {"smtpPasswordFile": "smtp-password", "githubTokenFile": "github-token",
                   "multicaWebhookFile": "multica-webhook"}
    if not isinstance(value, dict):
        raise ValueError("Feedback inputs must be an object")
    if type(value.get("schemaVersion")) is not int:
        raise ValueError("Feedback input schemaVersion must be an integer")
    if value.get("schemaVersion") == 1:
        valid_fields = set(value) == required | {"smtpPasswordFile"}
    else:
        valid_fields = required <= set(value) <= required | set(credentials)
    if not valid_fields:
        raise ValueError("Feedback inputs have unknown or missing fields")
    if value["schemaVersion"] not in (1, 2) or value["target"] != target or value["arch"] not in ("amd64", "arm64"):
        raise ValueError("Feedback inputs must match the one explicit target and supported architecture")
    config = load_json(read_input(value["configFile"], "Feedback configuration"))
    expected = credential_paths(config)
    supplied = {}
    for field, name in credentials.items():
        source = value.get(field, "")
        if not isinstance(source, str):
            raise ValueError("Credential inputs must be file paths or empty strings")
        if source:
            if name not in expected:
                raise ValueError("Credential input is not referenced by the receiver configuration")
            supplied[name] = read_input(source, name + " credential", private=True, limit=4096)
    if set(supplied) != set(expected):
        raise ValueError("Every configured credential requires an explicit private input file")
    return config, Path(value["configFile"]), supplied, value["arch"]


def render_unit(template, config):
    if config.get("public") is None:
        return template
    replacements = {"StateDirectory=hexproof-feedback":
                    "StateDirectory=hexproof-feedback " + PUBLIC_DATA.name,
                    "ReadWritePaths=" + str(DATA): "ReadWritePaths=" + str(DATA) + " " + str(PUBLIC_DATA)}
    lines = template.splitlines()
    for original, replacement in replacements.items():
        if lines.count(original) != 1:
            raise ValueError("Release service template lacks the fixed feedback state directives")
        lines[lines.index(original)] = replacement
    return "\n".join(lines) + "\n"


def prepare_payload(payload, config, credentials, binary, template, test_provenance=None, component_provenance=None):
    payload.mkdir(mode=0o700)
    shutil.copy2(binary, payload / "hexproof-feedback")
    (payload / "config.json").write_text(json.dumps(config))
    (payload / "hexproof-feedback.service").write_text(render_unit(template.read_text(), config))
    shutil.copy2(Path(__file__), payload / "install.py")
    if test_provenance is not None:
        (payload / "test-provenance.json").write_text(json.dumps(test_provenance, indent=2) + "\n")
    if component_provenance is not None:
        (payload / "component-provenance.json").write_text(json.dumps(component_provenance, indent=2) + "\n")
    for name, content in credentials.items():
        (payload / name).write_bytes(content)
    for item in payload.iterdir():
        item.chmod(0o600)


def atomic_write(path, content, mode, uid=0, gid=0):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix="." + path.name + ".feedback-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            os.fchown(stream.fileno(), uid, gid)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def update_baseline(stage, config, credentials, provenance):
    """An update cannot silently change deployment configuration or credentials."""
    if (not isinstance(provenance, dict) or provenance.get("mode") != "actions-feedback-update"
            or provenance.get("componentAttested") is not True
            or not re.fullmatch(r"[a-f0-9]{40}", provenance.get("headSha", ""))
            or not re.fullmatch(r"[a-f0-9]{64}", provenance.get("expectedReceiverSha256", ""))
            or digest(stage / "hexproof-feedback") != provenance.get("receiverSha256")):
        raise ValueError("Invalid component update provenance")
    paths = [BINARY, CONFIG, UNIT, *credentials.values()]
    baseline = {}
    for path in paths:
        if path.is_symlink() or not path.is_file():
            raise ValueError("Component updates require an existing regular installation")
        info = path.stat()
        baseline[str(path)] = [digest(path), stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid]
    if baseline[str(BINARY)][0] != provenance["expectedReceiverSha256"]:
        raise ValueError("Installed receiver differs from the explicitly selected baseline")
    if load_json(CONFIG.read_bytes()) != config or UNIT.read_bytes() != (stage / "hexproof-feedback.service").read_bytes():
        raise ValueError("Binary-only update cannot change installed configuration or unit")
    if any(path.read_bytes() != (stage / name).read_bytes() for name, path in credentials.items()):
        raise ValueError("Binary-only update cannot change installed credentials")
    return baseline


def store_revision(config):
    """Called only with the receiver stopped; do not restore live data on rollback."""
    result = {}
    for directory in [DATA] + ([PUBLIC_DATA] if config.get("public") is not None else []):
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("Cannot establish the stopped feedback store revision")
        for item in directory.glob("*.json"):
            if item.is_symlink() or not item.is_file():
                raise ValueError("Cannot establish the stopped feedback store revision")
            result[str(item)] = digest(item)
    return result


def verify_running_component(checksum):
    pid = run("systemctl", "show", SERVICE, "--property=MainPID", "--value")
    if not re.fullmatch(r"[1-9][0-9]*", pid) or digest(Path("/proc") / pid / "exe") != checksum:
        raise ValueError("Running feedback process does not match the verified component")


def local_install(stage, version, test_initial=False, component_update=False):
    if os.geteuid() != 0:
        raise ValueError("Feedback installation requires the explicit owner's privileged invocation")
    manifest = load_json((stage / "manifest.json").read_text())
    if not isinstance(manifest, dict) or not isinstance(manifest.get("files"), dict):
        raise ValueError("Invalid staged feedback manifest")
    expected = {"hexproof-feedback", "config.json", "hexproof-feedback.service"}
    if test_initial:
        expected.add("test-provenance.json")
    if component_update:
        expected.add("component-provenance.json")
    expected.update(set(manifest.get("files", {})) & {"smtp-password", "github-token", "multica-webhook"})
    if set(manifest) != {"version", "files"} or manifest["version"] != version or set(manifest["files"]) != expected:
        raise ValueError("Invalid staged feedback manifest")
    for name, checksum in manifest["files"].items():
        item = stage / name
        if item.is_symlink() or not item.is_file() or not re.fullmatch(r"[0-9a-f]{64}", checksum) or digest(item) != checksum:
            raise ValueError("Staged feedback checksum mismatch")
    if test_initial:
        provenance = load_json((stage / "test-provenance.json").read_text())
        if (provenance.get("mode") != "actions-test-initial-install"
                or provenance.get("version") != version or provenance.get("releaseAttested") is not False):
            raise ValueError("Invalid staged test provenance")
        require_empty_test_installation()
    candidate = stage / "hexproof-feedback"
    candidate.chmod(0o755)
    if run(candidate, "-version") != "hexproof-feedback " + version:
        raise ValueError("Feedback release version mismatch")
    config = load_json((stage / "config.json").read_text())
    credentials = credential_paths(config)
    if set(credentials) != expected - {"hexproof-feedback", "config.json", "hexproof-feedback.service",
                                       "test-provenance.json", "component-provenance.json"}:
        raise ValueError("Staged credentials do not match receiver configuration")
    component = load_json((stage / "component-provenance.json").read_bytes()) if component_update else None
    baseline = None
    if component_update:
        if test_initial or not isinstance(component, dict) or component.get("version") != version:
            raise ValueError("Invalid component update mode or version")
        baseline = update_baseline(stage, config, credentials, component)
    # Validate before modifying the current installation. A credential path in
    # this temporary copy points at the supplied private staged file.
    check_config = json.loads(json.dumps(config))
    credential_fields = {"smtp-password": ("smtp", "passwordFile"),
                         "github-token": ("public", "tokenFile"),
                         "multica-webhook": ("multica", "webhookFile")}
    for name in credentials:
        (stage / name).chmod(0o600)
        section, field = credential_fields[name]
        check_config[section][field] = str(stage / name)
    check_path = stage / "checked-config.json"
    atomic_write(check_path, json.dumps(check_config).encode(), 0o600, os.getuid(), os.getgid())
    run(candidate, "-config", check_path, "-validate-config")
    verification_unit = stage / "verification/hexproof-feedback.service"
    verification_unit.parent.mkdir()
    verification_unit.write_text((stage / "hexproof-feedback.service").read_text().replace(str(BINARY), str(candidate)))
    run("systemd-analyze", "verify", verification_unit)
    if test_initial:
        require_empty_test_installation()
    try:
        account = pwd.getpwnam("hexproof-feedback")
    except KeyError:
        if component_update:
            raise ValueError("Component updates require the existing service identity") from None
        run("useradd", "--system", "--user-group", "--home-dir", DATA,
            "--no-create-home", "--shell", "/usr/sbin/nologin", "hexproof-feedback")
        account = pwd.getpwnam("hexproof-feedback")
    if account.pw_uid == 0 or account.pw_dir != str(DATA):
        raise ValueError("Unexpected feedback service identity")
    state_directories = [DATA] + ([PUBLIC_DATA] if config.get("public") is not None else [])
    if any(path.is_symlink() for path in state_directories) or CONFIG.parent.is_symlink():
        raise ValueError("Feedback directories cannot be symlinks")
    for directory in state_directories:
        if component_update:
            if not directory.is_dir():
                raise ValueError("Component updates require existing feedback stores")
            continue
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        directory.chmod(0o700)
        os.chown(directory, account.pw_uid, account.pw_gid)
    if not component_update:
        CONFIG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        CONFIG.parent.chmod(0o700)
        os.chown(CONFIG.parent, account.pw_uid, account.pw_gid)
    if BACKUPS.is_symlink():
        raise ValueError("Feedback installation backups cannot be symlinks")
    BACKUPS.mkdir(parents=True, mode=0o700, exist_ok=True)
    BACKUPS.chmod(0o700)
    backup = BACKUPS / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup.mkdir(parents=True, mode=0o700)
    replacements = {BINARY: (candidate.read_bytes(), 0o755, 0, 0),
                    CONFIG: ((stage / "config.json").read_bytes(), 0o600, account.pw_uid, account.pw_gid),
                    UNIT: ((stage / "hexproof-feedback.service").read_bytes(), 0o644, 0, 0)}
    if test_initial:
        replacements[TEST_PROVENANCE] = ((stage / "test-provenance.json").read_bytes(), 0o600, 0, 0)
    for name, path in credentials.items():
        replacements[path] = ((stage / name).read_bytes(), 0o600, account.pw_uid, account.pw_gid)
    if component_update:
        replacements = {BINARY: (candidate.read_bytes(), *baseline[str(BINARY)][1:]),
                        COMPONENT_PROVENANCE: ((stage / "component-provenance.json").read_bytes(), 0o600, 0, 0)}
    previous = {}
    for index, path in enumerate(replacements):
        if path.is_symlink():
            raise ValueError("Managed feedback file cannot be a symlink")
        if path.exists():
            info = path.stat()
            previous[path] = (path.read_bytes(), info.st_mode & 0o777, info.st_uid, info.st_gid)
            shutil.copy2(path, backup / str(index))
        else:
            previous[path] = None
    was_active = subprocess.run(["systemctl", "is-active", "--quiet", SERVICE], check=False).returncode == 0
    was_enabled = subprocess.run(["systemctl", "is-enabled", "--quiet", SERVICE], check=False).returncode == 0
    if component_update and not was_active:
        raise ValueError("Component updates require an active receiver")
    backup_manifest = {"version": version, "serviceWasActive": was_active, "serviceWasEnabled": was_enabled,
                       "files": [{"path": str(path), "backup": str(index) if value else None,
                                  "mode": value[1] if value else None,
                                  "uid": value[2] if value else None, "gid": value[3] if value else None}
                                 for index, (path, value) in enumerate(previous.items())]}
    atomic_write(backup / "manifest.json", json.dumps(backup_manifest, indent=2).encode() + b"\n", 0o600)
    stopped_revision = None
    candidate_started = False
    if component_update and update_baseline(stage, config, credentials, component) != baseline:
        raise ValueError("Installed feedback files changed during preparation")
    try:
        if was_active:
            run("systemctl", "stop", SERVICE)
        if component_update:
            stopped_revision = store_revision(config)
        for path, parameters in replacements.items():
            atomic_write(path, *parameters)
        run(BINARY, "-config", CONFIG, "-validate-config")
        candidate_started = True
        if component_update:
            run("systemctl", "start", SERVICE)
        else:
            run("systemctl", "daemon-reload")
            run("systemctl", "enable", "--now", SERVICE)
            if was_active:
                run("systemctl", "restart", SERVICE)
        # Probe only the configured literal loopback listener. No external
        # message or new submission is sent by deployment verification.
        origin = "http://" + config.get("listen", "127.0.0.1:57324")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        deadline = time.monotonic() + 30
        while True:
            try:
                with opener.open(origin + "/readyz", timeout=3) as response:
                    if response.status == 200:
                        break
            except OSError:
                pass
            if time.monotonic() >= deadline:
                raise ValueError("Feedback service did not become ready") from None
            time.sleep(1)
        if component_update:
            verify_running_component(component["receiverSha256"])
            updated = dict(component, expectedReceiverSha256=component["receiverSha256"])
            expected_baseline = dict(baseline)
            expected_baseline[str(BINARY)] = [component["receiverSha256"], *baseline[str(BINARY)][1:]]
            if update_baseline(stage, config, credentials, updated) != expected_baseline:
                raise ValueError("Feedback configuration or credentials changed during activation")
        print(json.dumps({"version": version, "service": SERVICE, "backup": str(backup), "ready": True,
                          "configurationSchema": config["schemaVersion"],
                          "publicConfigured": config.get("public") is not None,
                          "multicaConfigured": config.get("multica") is not None,
                          "testBuild": test_initial, "componentUpdate": component_update,
                          "sourceCommit": component["headSha"] if component else None,
                          "receiverSha256": digest(BINARY)}))
    except BaseException:
        if component_update:
            run("systemctl", "stop", SERVICE)
            if candidate_started and (stopped_revision is None or store_revision(config) != stopped_revision):
                raise ValueError("Candidate stopped after feedback state changed; automatic downgrade refused. "
                                 "Preserve the candidate and stores for forward recovery.") from None
        else:
            subprocess.run(["systemctl", "stop", SERVICE], check=False)
        for path, value in previous.items():
            if value is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, *value)
        if not component_update:
            run("systemctl", "daemon-reload")
        if not was_enabled:
            subprocess.run(["systemctl", "disable", SERVICE], check=False)
        if was_active:
            run("systemctl", "start", SERVICE)
        raise


def deploy(target, version, input_path, repo, allow_draft, verify_only,
           test_run_id=None, test_artifact_id=None, test_head_sha=None, test_archive=None,
           component_run_id=None, component_artifact_id=None, component_head_sha=None, expected_receiver_sha=None):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", target):
        raise ValueError("Use an explicit existing SSH alias")
    config, _, credentials, arch = inputs(input_path, target)
    system = ssh(target, "uname", "-s")
    machine = ssh(target, "uname", "-m")
    if system != "Linux" or {"x86_64": "amd64", "aarch64": "arm64"}.get(machine) != arch:
        raise ValueError("Feedback target OS or architecture differs from inputs")
    ssh(target, "sudo", "-n", "true")
    if component_run_id is not None:
        actual = ssh(target, "sha256sum", BINARY).split()[0]
        if actual != expected_receiver_sha:
            raise ValueError("Installed receiver differs from the explicitly selected baseline")
    if test_run_id is not None:
        paths = [str(path) for path in test_installation_paths()]
        probe = ("import pathlib, subprocess; paths=" + repr(paths) + "; "
                 "assert not any(pathlib.Path(p).exists() or pathlib.Path(p).is_symlink() for p in paths), "
                 "'Test installation requires absent feedback files and state'; "
                 "assert subprocess.check_output(['systemctl','show','hexproof-feedback.service',"
                 "'--property=LoadState','--value'],text=True).strip() == 'not-found', "
                 "'Test installation requires an absent feedback service'")
        ssh(target, "sudo", "-n", "python3", "-c", probe)
    backend = load_backend()
    report = ROOT / "build" / ("release-" + version) / "feedback" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    report.mkdir(parents=True)
    test_provenance = None
    component_provenance = None
    if component_run_id is not None:
        record, component_provenance = load_component().fetch_component(
            backend, repo, version, arch, report, component_run_id, component_artifact_id, component_head_sha)
        component_provenance["expectedReceiverSha256"] = expected_receiver_sha
    elif test_run_id is None:
        release = backend.fetch_release(repo, version, allow_draft, {arch}, report)
        record = release["artifacts"][arch]
    else:
        record, test_provenance = fetch_test_build(backend, repo, version, arch, report,
                                                 test_run_id, test_artifact_id, test_head_sha, test_archive)
    with tempfile.TemporaryDirectory(prefix="feedback-release-", dir=report) as temporary:
        stage = Path(temporary)
        if component_provenance is not None:
            verify_component_archive(Path(record["path"]), version, arch)
        archive = backend.PACKAGE.checked_archive(Path(record["path"]), record["sha256"], stage / "archive")
        kind = "feedback" if component_provenance is not None else "server"
        if archive.name != f"hexproof-{kind}-{version}-linux-{arch}":
            raise ValueError("Unexpected feedback package root")
        binary = archive / "bin/hexproof-feedback"
        if binary.is_symlink() or not binary.is_file() or not binary.stat().st_mode & 0o111:
            raise ValueError("Verified release does not contain the feedback receiver")
        if test_provenance is not None:
            verify_feedback_architecture(binary, arch)
            test_provenance["receiverSha256"] = digest(binary)
            (report / "test-provenance.json").write_text(json.dumps(test_provenance, indent=2) + "\n")
        template = archive / "deploy/hexproof-feedback.service.in"
        if template.is_symlink() or not template.is_file():
            raise ValueError("Verified release does not contain the feedback service template")
        render_unit(template.read_text(), config)
        if component_provenance is not None:
            expected_files = {"bin/hexproof-feedback", "deploy/hexproof-feedback.service.in", "build.json"}
            actual_files = {p.relative_to(archive).as_posix() for p in archive.rglob("*") if not p.is_dir()}
            if actual_files != expected_files or any(p.is_symlink() for p in archive.rglob("*")):
                raise ValueError("Unexpected component package files")
            verify_feedback_architecture(binary, arch)
            build = load_json((archive / "build.json").read_bytes())
            if build != {"schemaVersion": 1, "version": version, "sourceCommit": component_head_sha,
                         "architecture": arch, "receiverSha256": digest(binary)}:
                raise ValueError("Component build identity does not match its verified artifact")
            component_provenance["receiverSha256"] = digest(binary)
            (report / "component-provenance.json").write_text(json.dumps(component_provenance, indent=2) + "\n")
        if verify_only:
            print(json.dumps({"version": version, "target": target, "verified": True, "activated": False,
                              "testBuild": test_provenance is not None,
                              "componentUpdate": component_provenance is not None}))
            return
        payload = stage / "payload"
        prepare_payload(payload, config, credentials, binary, template, test_provenance, component_provenance)
        files = [item for item in payload.iterdir() if item.name != "install.py"]
        (payload / "manifest.json").write_text(json.dumps({"version": version, "files": {p.name: digest(p) for p in files}}))
        for item in payload.iterdir():
            item.chmod(0o600)
        remote = ssh(target, "mktemp", "-d", "/tmp/hexproof-feedback.XXXXXXXX")
        if not re.fullmatch(r"/tmp/hexproof-feedback\.[A-Za-z0-9]+", remote):
            raise ValueError("Unexpected remote staging directory")
        try:
            run("scp", *SSH_OPTIONS, *sorted(payload.iterdir()), target + ":" + remote + "/")
            install_args = ["--test-initial-install"] if test_provenance is not None else []
            if component_provenance is not None:
                install_args = ["--component-update"]
            output = ssh(target, "sudo", "-n", "python3", remote + "/install.py",
                         "--local", "--stage", remote, "--version", version, *install_args)
            result = json.loads(output)
            (report / "installation.json").write_text(json.dumps(result, indent=2) + "\n")
            print(target + ": feedback receiver ready; game services were not restarted")
        finally:
            ssh(target, "rm", "-rf", "--", remote)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target")
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--repo", default="ClayStan404/hexproof")
    parser.add_argument("--allow-draft", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--test-run-id", type=int)
    parser.add_argument("--test-artifact-id", type=int)
    parser.add_argument("--test-head-sha")
    parser.add_argument("--test-archive", type=Path)
    parser.add_argument("--test-initial-install", action="store_true")
    parser.add_argument("--component-run-id", type=int)
    parser.add_argument("--component-artifact-id", type=int)
    parser.add_argument("--component-head-sha")
    parser.add_argument("--expected-receiver-sha")
    parser.add_argument("--component-update", action="store_true")
    parser.add_argument("--local", action="store_true")
    parser.add_argument("--stage", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("An explicit release version is required")
    testing = any(value is not None for value in (args.test_run_id, args.test_artifact_id,
                                                 args.test_head_sha, args.test_archive))
    component = any(value is not None for value in (args.component_run_id, args.component_artifact_id,
                                                   args.component_head_sha, args.expected_receiver_sha))
    if component and (not args.component_run_id or args.component_run_id < 1
                      or not args.component_artifact_id or args.component_artifact_id < 1
                      or not re.fullmatch(r"[0-9a-f]{40}", args.component_head_sha or "")
                      or not re.fullmatch(r"[0-9a-f]{64}", args.expected_receiver_sha or "")
                      or testing or args.allow_draft or args.local):
        parser.error("Component update requires exact run, artifact, source and installed binary identities")
    if testing and (not args.test_run_id or args.test_run_id < 1 or not args.test_artifact_id
                    or args.test_artifact_id < 1 or not re.fullmatch(r"[0-9a-f]{40}", args.test_head_sha or "")
                    or args.allow_draft or args.local):
        parser.error("Test deployment requires explicit run, artifact and source identities without draft mode")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("Invalid GitHub repository")
    if args.test_initial_install and not args.local:
        parser.error("Test initial installation is an internal target-host operation")
    if args.component_update and (not args.local or args.test_initial_install):
        parser.error("Component update is an exclusive internal target-host operation")
    if args.local and args.stage:
        local_install(args.stage.resolve(strict=True), args.version, args.test_initial_install, args.component_update)
    elif args.target and args.inputs:
        deploy(args.target, args.version, args.inputs.absolute(), args.repo,
               args.allow_draft, args.verify_only, args.test_run_id, args.test_artifact_id,
               args.test_head_sha, args.test_archive, args.component_run_id, args.component_artifact_id,
               args.component_head_sha, args.expected_receiver_sha)
    else:
        parser.error("Use deploy/deploy-release-server.sh with explicit feedback inputs")


if __name__ == "__main__":
    main()
