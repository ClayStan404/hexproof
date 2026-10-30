#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Back up and restore the owner's minimal local Hexproof configuration."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_NAME = "hexproof-private-backup.tar.gz"
OPERATOR = ".local/state/hexproof-operator"
FEEDBACK = ".local/state/hexproof-feedback-test"
PREVIOUS = ".local/state/hexproof-config-restore-backups"
TUNNEL = ".config/systemd/user/hexproof-feedback-test-tunnel.service"
REPO_FILES = {"apps/client-qt/config/servers.json", "apps/client-qt/config/feedback.json"}
OPERATOR_FILES = {"multica-operations.json", "deployment-targets.json", "nodes.json",
                  "feedback-deployment.json", "feedback-tunnel.env"}
PATH_KEYS = {"repositoryRoot", "privateStateDirectory", "connectionFile", "inputsFile",
             "configFile", "githubTokenFile", "multicaWebhookFile", "socket", "keyFile",
             "identityFile", "credentialFile"}
FILE_KEYS = PATH_KEYS - {"repositoryRoot", "privateStateDirectory", "socket"}
MAX_FILES = 512
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def destination(name: str, home: Path, repo: Path) -> Path:
    if not isinstance(name, str):
        raise ValueError("Invalid backup path")
    parts = PurePosixPath(name).parts
    if ("\\" in name or "\x00" in name
            or not parts or PurePosixPath(name).is_absolute()
            or str(PurePosixPath(name)) != name
            or any(p in (".", "..") or len(p.encode()) > 255 for p in parts)):
        raise ValueError("Invalid backup path")
    scope, relative = parts[0], "/".join(parts[1:])
    allowed = (scope == "repo" and relative in REPO_FILES) or (
        scope == "home" and (relative == TUNNEL
        or any(relative.startswith(prefix + "/") for prefix in (OPERATOR, FEEDBACK))
        or (relative.startswith(".ssh/") and parts[2] not in ("agent", "known_hosts.old"))))
    if not allowed:
        raise ValueError("Backup path is outside the configuration allowlist: " + name)
    return (home if scope == "home" else repo).joinpath(*parts[1:])


def check_path(path: Path) -> None:
    for parent in reversed(path.parents):
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise ValueError("Unsafe configuration parent: " + str(parent))
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError("Configuration must be a regular file: " + str(path))


def collect(home: Path, repo: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}

    def add(path: Path) -> None:
        if path.is_relative_to(home):
            name = "home/" + path.relative_to(home).as_posix()
        else:
            name = "repo/" + path.relative_to(repo).as_posix()
        # Repository configuration may itself be beneath HOME.
        if path in {repo / name for name in REPO_FILES}:
            name = "repo/" + path.relative_to(repo).as_posix()
        destination(name, home, repo)
        check_path(path)
        if not path.exists():
            return
        if name in result:
            return
        result[name] = path
        if path.suffix == ".json":
            def references(value):
                if isinstance(value, dict):
                    for key, item in value.items():
                        if key in PATH_KEYS and isinstance(item, str):
                            candidate = Path(item)
                            if (key in FILE_KEYS and candidate.is_absolute()
                                    and any(candidate.is_relative_to(home / prefix)
                                            for prefix in (OPERATOR, FEEDBACK))):
                                if not candidate.exists():
                                    raise ValueError("Referenced configuration is missing: " + str(candidate))
                                add(candidate)
                        elif isinstance(item, (dict, list)):
                            references(item)
                elif isinstance(value, list):
                    for item in value:
                        references(item)
            references(json.loads(path.read_text()))

    ssh = home / ".ssh"
    if ssh.exists():
        for directory, subdirs, files in os.walk(ssh, followlinks=False):
            subdirs[:] = [name for name in subdirs if name != "agent"]
            for name in files:
                path = Path(directory) / name
                if name != "known_hosts.old" and not stat.S_ISSOCK(path.lstat().st_mode):
                    add(path)
    for name in OPERATOR_FILES:
        add(home / OPERATOR / name)
    for path in (home / FEEDBACK / "connection.json", home / TUNNEL):
        add(path)
    for name in REPO_FILES:
        add(repo / name)
    return result


def create(archive: Path, home: Path, repo: Path) -> dict:
    if archive.exists() or archive.is_symlink():
        raise ValueError("Backup already exists; choose a different archive path")
    selected = collect(home, repo)
    if not selected or len(selected) > MAX_FILES:
        raise ValueError("No configuration found, or too many configuration files")
    payload, records = {}, []
    for name, path in sorted(selected.items()):
        if path.stat().st_size > MAX_FILE_BYTES:
            raise ValueError("Configuration file exceeds backup size limit")
        data = path.read_bytes()
        mode = 0o700 if path.stat().st_mode & 0o100 else 0o600
        payload[name] = data
        records.append({"path": name, "sha256": digest(data), "mode": mode})
    if sum(map(len, payload.values())) > MAX_TOTAL_BYTES:
        raise ValueError("Configuration backup exceeds total size limit")
    manifest = {"version": 1, "home": str(home), "repository": str(repo),
                "uid": os.getuid(), "files": records}
    payload["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    if sum(map(len, payload.values())) > MAX_TOTAL_BYTES:
        raise ValueError("Configuration backup exceeds total size limit")
    archive.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".hexproof-private-backup-", dir=archive.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), 0o600)
            with tarfile.open(fileobj=output, mode="w:gz") as stream:
                for name, data in payload.items():
                    member = tarfile.TarInfo(name)
                    member.size, member.mode = len(data), 0o600
                    stream.addfile(member, io.BytesIO(data))
            output.flush()
            os.fsync(output.fileno())
        # Publish atomically without replacing an existing archive.
        os.link(temporary, archive)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return {"archive": str(archive), "files": len(records), "bytes": archive.stat().st_size,
            "sha256": digest(archive.read_bytes())}


def read_archive(archive: Path, home: Path, repo: Path) -> tuple[dict, dict[str, bytes]]:
    with tarfile.open(archive, "r:gz") as stream:
        payload = {}
        total = 0
        for member in stream:
            if (not member.isfile() or member.name in payload or len(payload) > MAX_FILES
                    or member.size < 0 or member.size > MAX_FILE_BYTES):
                raise ValueError("Invalid backup member or size limit exceeded")
            if member.name != "manifest.json":
                destination(member.name, home, repo)
            total += member.size
            if total > MAX_TOTAL_BYTES:
                raise ValueError("Backup exceeds total size limit")
            data = stream.extractfile(member).read(MAX_FILE_BYTES + 1)
            if len(data) != member.size:
                raise ValueError("Incomplete backup member")
            payload[member.name] = data
    manifest = json.loads(payload.pop("manifest.json", b"null"))
    if (not isinstance(manifest, dict) or manifest.get("version") != 1
            or not isinstance(manifest.get("files"), list)
            or type(manifest.get("uid")) is not int or manifest["uid"] < 0
            or not manifest["files"] or len(manifest["files"]) > MAX_FILES
            or any(not isinstance(manifest.get(key), str) or not Path(manifest[key]).is_absolute()
                   for key in ("home", "repository"))):
        raise ValueError("Invalid backup manifest")
    names = set()
    for entry in manifest["files"]:
        if (not isinstance(entry, dict) or not isinstance(entry.get("path"), str)
                or entry["path"] in names or entry.get("mode") not in (0o600, 0o700)):
            raise ValueError("Invalid backup file record")
        name = entry["path"]
        names.add(name)
        if name not in payload or digest(payload[name]) != entry.get("sha256"):
            raise ValueError("Backup checksum mismatch")
    if names != set(payload):
        raise ValueError("Backup contains unlisted files")
    return manifest, payload


def relocate(data: bytes, name: str, manifest: dict, home: Path, repo: Path) -> bytes:
    def path(value: str) -> str:
        pairs = [(manifest["repository"], str(repo)), (manifest["home"], str(home)),
                 (f"/run/user/{manifest['uid']}", f"/run/user/{os.getuid()}")]
        for old, new in pairs:
            if value == old or value.startswith(old + "/"):
                return new + value[len(old):]
        return value

    if name.endswith(".json"):
        original = json.loads(data)
        def update(value):
            if isinstance(value, dict):
                return {key: path(item) if key in PATH_KEYS and isinstance(item, str)
                        else update(item) for key, item in value.items()}
            return [update(item) for item in value] if isinstance(value, list) else value
        updated = update(original)
        return data if updated == original else (json.dumps(updated, indent=2, ensure_ascii=False) + "\n").encode()
    if name.startswith("home/.ssh/") and (name.endswith("/config") or "/config.d/" in name):
        allowed = {"identityfile", "certificatefile", "include", "userknownhostsfile",
                   "identityagent", "controlpath", "proxycommand"}
    elif name.endswith(".service"):
        allowed = {"execstart", "execstartpre", "execstartpost", "workingdirectory",
                   "environmentfile", "readwritepaths", "readonlypaths", "conditionpathexists"}
    elif name.endswith(".env"):
        allowed = set()
        for line in data.decode().splitlines():
            key = line.partition("=")[0].strip()
            if key.endswith(("_FILE", "_DIR", "_SOCKET")):
                allowed.add(key.lower())
    else:
        return data
    lines = []
    for line in data.decode().splitlines(keepends=True):
        key = re.split(r"[=\s]", line.strip(), maxsplit=1)[0].lower()
        if key in allowed:
            replacements = {manifest["home"]: str(home), manifest["repository"]: str(repo)}
            pattern = "|".join(re.escape(old) for old in sorted(replacements, key=len, reverse=True))
            line = re.sub(r"(?<![A-Za-z0-9_./-])(" + pattern + r")(?=/|[\s\"']|$)",
                          lambda match: replacements[match[1]], line)
        lines.append(line)
    return "".join(lines).encode()


def make_parents(path: Path) -> None:
    missing = []
    parent = path.parent
    while not parent.exists():
        missing.append(parent)
        parent = parent.parent
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    make_parents(path)
    fd, temporary = tempfile.mkstemp(prefix=".hexproof-restore-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), mode)
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def restore(archive: Path, home: Path, repo: Path, overwrite=False, dry_run=False) -> dict:
    manifest, payload = read_archive(archive, home, repo)
    plan = []
    targets = set()
    previous_total = 0
    for entry in manifest["files"]:
        name = entry["path"]
        target = destination(name, home, repo)
        check_path(target)
        if target in targets:
            raise ValueError("Backup destinations collide")
        targets.add(target)
        data = relocate(payload[name], name, manifest, home, repo)
        if target.exists() and target.stat().st_size > MAX_FILE_BYTES:
            raise ValueError("Existing configuration exceeds size limit")
        previous = target.read_bytes() if target.exists() else None
        previous_total += len(previous) if previous is not None else 0
        if previous_total > MAX_TOTAL_BYTES:
            raise ValueError("Existing configuration exceeds total size limit")
        if previous is not None and previous != data and not overwrite:
            raise ValueError("Existing configuration differs: " + str(target) + "; use --overwrite to retain a backup and replace it")
        plan.append((name, target, data, entry["mode"], previous))
    if any(any(parent in targets for parent in target.parents) for target in targets):
        raise ValueError("Backup destinations overlap")
    previous_root = home / PREVIOUS / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    for name, _, _, _, previous in plan:
        if previous is not None:
            check_path(previous_root / name)
    if not dry_run:
        for name, target, data, mode, previous in plan:
            if previous is not None and previous != data:
                atomic_write(previous_root / name, previous, 0o600)
            if previous != data:
                atomic_write(target, data, mode)
            else:
                target.chmod(mode)
        for prefix in (".ssh", OPERATOR, FEEDBACK):
            directory = home / prefix
            if directory.is_dir():
                directory.chmod(0o700)
    return {"restored": 0 if dry_run else len(plan), "dryRun": dry_run,
            "files": [name for name, *_ in plan],
            "previousFiles": str(previous_root) if previous_root.exists() else None}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=("create", "restore"), default="restore")
    parser.add_argument("archive", nargs="?", type=Path, default=ROOT / ARCHIVE_NAME)
    parser.add_argument("--dry-run", action="store_true", help="Validate a restore without writing files")
    parser.add_argument("--overwrite", action="store_true", help="Back up differing existing files before replacing them")
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("Run as your normal user, without sudo")
    if args.action == "create" and (args.dry_run or args.overwrite):
        parser.error("--dry-run and --overwrite apply only to restore")
    try:
        home = Path.home().resolve()
        result = (create(args.archive, home, ROOT) if args.action == "create" else
                  restore(args.archive, home, ROOT, args.overwrite, args.dry_run))
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (ValueError, OSError, EOFError, tarfile.TarError) as error:
        parser.exit(1, f"Local configuration backup failed: {error}\n")


if __name__ == "__main__":
    main()
