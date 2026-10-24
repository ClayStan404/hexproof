#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Install a reviewed home-node bundle on its target Linux host.

Run as root with an externally pinned bundle SHA-256 and a private JSON config.
Only the new hexproof-home services and their dedicated directories are managed.
Gateway activation adds one nginx include, validates it, then reloads nginx.
Existing cloud hubs and legacy home servers are never restarted or replaced.
"""

from __future__ import annotations

import argparse
import grp
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import urllib.request


OPT = Path("/opt/hexproof-home")
CONFIG = Path("/etc/hexproof-home")
STATE = Path("/var/lib/hexproof-home")
UNITS = Path("/etc/systemd/system")
NGINX = Path("/etc/nginx/conf.d/hexproof-ip.conf")
SNIPPET = Path("/etc/nginx/snippets/hexproof-home.inc")


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=check, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=120)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def extract_checked(archive_path: Path, expected: str, destination: Path) -> tuple[Path, dict]:
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or digest(archive_path) != expected:
        raise ValueError("Deployment archive SHA-256 mismatch")
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        if len(members) > 200_000 or sum(item.size for item in members) > 4 * 1024**3:
            raise ValueError("Deployment archive exceeds limits")
        archive.extractall(destination, filter="data")
    release = destination / "release"
    return release, verify_tree(release)


def verify_tree(release: Path, manifest_sha256: str | None = None) -> dict:
    """Verify the complete payload; rsync timestamps are never proof of content."""
    if any((release / name).is_symlink() for name in ("manifest.json", "SHA256SUMS")):
        raise ValueError("Bundle metadata must be regular files")
    if manifest_sha256 is not None and (not re.fullmatch(r"[a-f0-9]{64}", manifest_sha256)
            or digest(release / "manifest.json") != manifest_sha256):
        raise ValueError("Deployment manifest SHA-256 mismatch")
    manifest = json.loads((release / "manifest.json").read_text())
    if (manifest.get("schemaVersion") != 1 or manifest.get("kind") not in ("gateway", "node")
            or not re.fullmatch(r"[a-f0-9]{24}", manifest.get("releaseId", ""))):
        raise ValueError("Invalid bundle manifest")
    sums = (release / "SHA256SUMS").read_text()
    expected_files = {"manifest.json", "SHA256SUMS"}
    for record in sums.splitlines():
        checksum, relative = record.split("  ", 1)
        if relative in expected_files or not re.fullmatch(r"[a-f0-9]{64}", checksum):
            raise ValueError("Invalid or duplicate bundle record")
        expected_files.add(relative)
        path = release / relative
        if (not path.resolve().is_relative_to(release.resolve()) or path.is_symlink()
                or not path.is_file() or digest(path) != checksum):
            raise ValueError("Bundle file verification failed")
    links = manifest.get("links", {})
    for relative, target in links.items():
        path = release / relative
        if (not path.is_symlink() or os.readlink(path) != target
                or not path.resolve().is_relative_to(release.resolve())):
            raise ValueError("Bundle symlink verification failed")
    actual_files = {path.relative_to(release).as_posix() for path in release.rglob("*")
                    if not path.is_dir() or path.is_symlink()}
    if actual_files != expected_files | set(links):
        raise ValueError("Bundle contains missing or unlisted files")
    calculated = hashlib.sha256((sums + json.dumps(links, sort_keys=True)).encode()).hexdigest()
    if calculated != manifest.get("treeSha256") or calculated[:24] != manifest["releaseId"]:
        raise ValueError("Bundle identity verification failed")
    return manifest


def nginx_with_home(source: str) -> str:
    directive = f"    include {SNIPPET};"
    if directive in source:
        if source.count(directive) != 1:
            raise ValueError("Duplicate home gateway nginx include")
        return source
    marker = "    include /etc/nginx/snippets/hexproof-server-directory.inc;"
    if source.count(marker) != 1:
        raise ValueError("Unknown nginx layout; add the reviewed home include explicitly")
    return source.replace(marker, marker + "\n" + directive)


def atomic_write(path: Path, data: bytes, mode: int = 0o644, group: int = 0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".home-new")
    with temporary.open("wb") as stream:
        stream.write(data)
    temporary.chmod(mode)
    os.chown(temporary, 0, group)
    temporary.replace(path)


def switch_release(path: Path | None) -> None:
    current = OPT / "current"
    temporary = OPT / "current.home-new"
    temporary.unlink(missing_ok=True)
    if path is None:
        current.unlink(missing_ok=True)
    else:
        temporary.symlink_to(path)
        temporary.replace(current)


def owned_process_active(kind: str) -> bool:
    services = [(f"hexproof-home-{kind}.service", OPT / "current/hexproof-home")]
    if kind == "node":
        services.append(("hexproof-home-hub.service", OPT / "current/server/bin/hexproof-server"))
    for unit, binary in services:
        result = run("systemctl", "show", unit, "--property=MainPID", "--value", check=False)
        process = result.stdout.strip()
        if result.returncode or not process.isdecimal() or int(process) <= 1:
            return False
        try:
            if Path(f"/proc/{process}/exe").resolve(strict=True) != binary.resolve(strict=True):
                return False
        except OSError:
            return False
    return True


def await_ready(kind: str, timeout: int = 120) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if not owned_process_active(kind):
                time.sleep(1)
                continue
            if kind == "gateway":
                with socket.create_connection(("127.0.0.1", 57322), timeout=2):
                    return
            else:
                local_http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                with local_http.open("http://127.0.0.1:57323/healthz", timeout=3) as response:
                    if response.status == 200:
                        return
        except (OSError, ValueError):
            pass
        time.sleep(1)
    raise RuntimeError("New home service did not become healthy")


def verify_current(expected: str, version: str) -> dict:
    current = (OPT / "current").resolve(strict=True)
    if not current.is_relative_to((OPT / "releases").resolve()):
        raise ValueError("Current release escapes managed storage")
    manifest = verify_tree(current)
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or manifest["treeSha256"] != expected:
        raise ValueError("Current release differs from requested tree")
    if manifest["kind"] != "node":
        raise ValueError("Expected a home node")
    if run(str(current / "server/bin/hexproof-server"), "-version").stdout.strip() != "hexproof-server " + version:
        raise ValueError("Current server version mismatch")
    await_ready("node")
    return {"checked": True, "activated": False, "unchanged": True, "releaseId": manifest["releaseId"]}


def binary_protocol(binary):
    # Read only a verified executable. Old releases have no protocol flag;
    # identifying that legacy CLI is an operator inventory operation, not a
    # game client's fallback or application-version compatibility exception.
    help_result = run(str(binary), "-h", check=False)
    if help_result.returncode != 0:
        raise ValueError("Could not inspect hub protocol options")
    if not re.search(r"(?m)^  -protocol(?:\s|$)", help_result.stdout + help_result.stderr):
        return "hexproof.v1"
    value = run(str(binary), "-protocol").stdout.strip()
    match = re.fullmatch(r"hexproof\.v([1-9][0-9]{0,9})", value)
    if not match or int(match[1]) > 2147483647:
        raise ValueError("Invalid installed hub protocol")
    return value


def inspect_current() -> dict:
    """Read a verified deployment baseline without exposing configuration values."""
    if not (OPT / "current").exists() and not (OPT / "current").is_symlink():
        # Protected preparation may already exist; an incomplete installation
        # must never be silently treated as a new host.
        occupied = [OPT / "releases", CONFIG, STATE]
        occupied += [UNITS / (name + suffix) for name in
                     ("hexproof-home-hub.service", "hexproof-home-node.service", "hexproof-home-gateway.service")
                     for suffix in ("", ".d")]
        if any(path.exists() or path.is_symlink() for path in occupied):
            raise ValueError("Incomplete home installation; inspect and resolve its remaining files before deployment")
        for name in ("hexproof-home-hub.service", "hexproof-home-node.service"):
            if run("systemctl", "is-active", "--quiet", name, check=False).returncode == 0:
                raise ValueError("Home service is active without an installed release")
            pid = run("systemctl", "show", name, "--property=MainPID", "--value", check=False).stdout.strip()
            if pid not in ("", "0"):
                raise ValueError("Home service process still exists without an installed release")
        with socket.socket() as probe:
            probe.settimeout(1)
            if probe.connect_ex(("127.0.0.1", 57323)) == 0:
                raise ValueError("Home hub port 57323 is occupied")
        return {"current": None, "system": platform.system(), "machine": platform.machine()}
    current = (OPT / "current").resolve(strict=True)
    if not current.is_relative_to((OPT / "releases").resolve()):
        raise ValueError("Current release escapes managed storage")
    manifest = verify_tree(current)
    if manifest["kind"] != "node":
        raise ValueError("Expected a home node")
    output = run(str(current / "server/bin/hexproof-server"), "-version").stdout.strip()
    version = re.fullmatch(r"hexproof-server ([0-9]+\.[0-9]+\.[0-9]+)", output)
    if not version or run(str(current / "hexproof-home"), "-version").stdout.strip() != "hexproof-home " + version[1]:
        raise ValueError("Installed hub and connector versions must match")
    unit_hashes, pids = {}, {}
    for name in ("hexproof-home-hub.service", "hexproof-home-node.service"):
        unit_hashes[name] = digest(UNITS / name)
        if unit_hashes[name] != digest(current / "deploy" / name):
            raise ValueError("Installed service differs from its sealed template: " + name)
        pids[name] = run("systemctl", "show", name, "--property=MainPID", "--value").stdout.strip()
    await_ready("node")
    return {"current": str(current), "manifest": manifest,
            "manifestSha256": digest(current / "manifest.json"), "version": version[1],
            "system": platform.system(), "machine": platform.machine(),
            "protocol": binary_protocol(current / "server/bin/hexproof-server"),
            "hubSha256": digest(current / "server/bin/hexproof-server"),
            "connectorSha256": digest(current / "hexproof-home"),
            "unitHashes": unit_hashes, "pids": pids,
            "configSha256": digest(CONFIG / "node.json")}


def install(args: argparse.Namespace) -> dict:
    if os.geteuid() != 0:
        raise ValueError("Run this target-host installer as root")
    config_bytes = args.config.read_bytes()
    configuration = json.loads(config_bytes)
    OPT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="stage-", dir=OPT) as temporary:
        prepared = getattr(args, "prepared", None)
        if prepared:
            if not re.fullmatch(r"[a-f0-9]{24}", prepared):
                raise ValueError("Invalid prepared release ID")
            staged = OPT / "prepared" / prepared
            if staged.is_symlink() or staged.stat().st_uid != 0:
                raise ValueError("Prepared release must be root-owned")
            manifest = verify_tree(staged, args.manifest_sha256)
            if manifest["releaseId"] != prepared:
                raise ValueError("Prepared release identity mismatch")
        elif getattr(args, "directory", None):
            staged = Path(temporary) / "release"
            shutil.copytree(args.directory, staged, symlinks=True)
            manifest = verify_tree(staged, args.manifest_sha256)
        else:
            staged, manifest = extract_checked(args.archive, args.sha256, Path(temporary))
        kind = manifest["kind"]
        if kind == "gateway" and configuration.get("listen") != "127.0.0.1:57322":
            raise ValueError("Gateway service requires its isolated loopback port 57322")
        if kind == "node" and (configuration.get("backendUrl") != "ws://127.0.0.1:57323/ws"
                               or configuration.get("healthUrl") != "http://127.0.0.1:57323/healthz"):
            raise ValueError("Node service requires its isolated loopback backend 57323")
        run(str(staged / "hexproof-home"), kind, "-config", str(args.config.resolve()), "-check")
        if kind == "node":
            version = run(str(staged / "server/bin/hexproof-server"), "-version").stdout.strip()
            if version != "hexproof-server " + args.hub_version:
                raise ValueError("Published game server version does not match the requested release")
            java = run(str(staged / "java/bin/java"), "-version")
            if not re.search(r'version "21\.', java.stderr + java.stdout):
                raise ValueError("A verified Java 21 runtime is required")
        changed_paths = [CONFIG / f"{kind}.json"]
        unit_names = [f"hexproof-home-{kind}.service"]
        if kind == "node":
            unit_names.insert(0, "hexproof-home-hub.service")
        changed_paths += [UNITS / name for name in unit_names]
        if kind == "gateway":
            nginx_result = nginx_with_home(NGINX.read_text())
            changed_paths += [NGINX, SNIPPET]
        else:
            nginx_result = None
        current = OPT / "current"
        if current.exists() and not current.is_symlink():
            raise ValueError("Managed current path must be a release symlink")
        previous = current.resolve(strict=True) if current.is_symlink() else None
        if previous is not None:
            previous_manifest = json.loads((previous / "manifest.json").read_text())
            if previous_manifest.get("kind") != kind:
                raise ValueError("Cannot replace a different home deployment role")
        backups = {path: (path.read_bytes(), path.stat().st_mode & 0o777, path.stat().st_gid)
                   if path.exists() else None for path in changed_paths}
        active = {name: run("systemctl", "is-active", "--quiet", name, check=False).returncode == 0
                  for name in unit_names}
        enabled = {name: run("systemctl", "is-enabled", "--quiet", name, check=False).returncode == 0
                   for name in unit_names}
        final = OPT / "releases" / manifest["releaseId"]
        if previous == final:
            installed = verify_tree(final)
            if installed["treeSha256"] != manifest["treeSha256"]:
                raise ValueError("Installed tree differs from requested content")
            await_ready(kind)
            return {"checked": True, "activated": False, "unchanged": True, "kind": kind,
                    "releaseId": manifest["releaseId"], "units": unit_names}
        if not args.activate:
            if getattr(args, "prepare", False) and not prepared:
                destination = OPT / "prepared" / manifest["releaseId"]
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                if destination.exists():
                    verify_tree(destination, args.manifest_sha256)
                else:
                    shutil.move(staged, destination)
            return {"checked": True, "activated": False, "kind": kind,
                    "releaseId": manifest["releaseId"], "units": unit_names}
        try:
            pwd.getpwnam("hexproof-home")
        except KeyError:
            run("useradd", "--system", "--user-group", "--home-dir", str(STATE),
                "--shell", "/usr/sbin/nologin", "hexproof-home")
        account = pwd.getpwnam("hexproof-home")
        group = grp.getgrnam("hexproof-home").gr_gid
        for path in (STATE, STATE / "retained"):
            path.mkdir(parents=True, exist_ok=True)
            path.chmod(0o750)
            os.chown(path, account.pw_uid, group)
        CONFIG.mkdir(parents=True, exist_ok=True)
        CONFIG.chmod(0o750)
        os.chown(CONFIG, 0, group)
        final.parent.mkdir(parents=True, exist_ok=True)
        if final.exists():
            raise ValueError("Release already exists; use a fresh reviewed artifact or explicitly roll back")
        shutil.move(staged, final)
        # Persist non-secret rollback coordinates. Private previous config stays
        # root-only and is never printed by the installer.
        backup_dir = STATE / "deployments" / (manifest["releaseId"] + ".before")
        backup_dir.mkdir(parents=True, mode=0o700)
        backup_dir.chmod(0o700)
        record = {"previousRelease": str(previous) if previous else None,
                  "active": active, "enabled": enabled, "files": {}}
        for index, (path, old) in enumerate(backups.items()):
            name = str(index)
            record["files"][str(path)] = {"file": name, "mode": old[1], "gid": old[2]} if old else None
            if old:
                atomic_write(backup_dir / name, old[0], 0o600)
        atomic_write(backup_dir / "rollback.json", (json.dumps(record, indent=2) + "\n").encode(), 0o600)
        try:
            atomic_write(CONFIG / f"{kind}.json", config_bytes, 0o640, group)
            for name in unit_names:
                atomic_write(UNITS / name, (final / "deploy" / name).read_bytes())
            switch_release(final)
            run("systemctl", "daemon-reload")
            for name in unit_names:
                run("systemctl", "enable", name)
                run("systemctl", "restart", name)
            await_ready(kind)
            if nginx_result is not None:
                atomic_write(SNIPPET, (final / "deploy/hexproof-home-nginx.inc").read_bytes())
                atomic_write(NGINX, nginx_result.encode())
                run("nginx", "-t")
                run("systemctl", "reload", "nginx.service")
        except Exception:
            for name in reversed(unit_names):
                run("systemctl", "stop", name, check=False)
            switch_release(previous)
            for path, old in backups.items():
                if old is None:
                    path.unlink(missing_ok=True)
                else:
                    atomic_write(path, old[0], old[1], old[2])
            run("systemctl", "daemon-reload")
            for name in unit_names:
                run("systemctl", "enable" if enabled[name] else "disable", name, check=False)
                if active[name]:
                    run("systemctl", "start", name)
            if nginx_result is not None:
                run("nginx", "-t")
                run("systemctl", "reload", "nginx.service")
            raise
        return {"checked": True, "activated": True, "kind": kind, "releaseId": manifest["releaseId"],
                "previousRelease": str(previous) if previous else None,
                "rollbackRecord": str(backup_dir / "rollback.json"), "units": unit_names}


def rollback(record_path: Path, activate: bool) -> dict:
    if os.geteuid() != 0:
        raise ValueError("Run this target-host installer as root")
    record_path = record_path.resolve(strict=True)
    if not record_path.is_relative_to((STATE / "deployments").resolve()):
        raise ValueError("Rollback record must belong to the managed deployment directory")
    record = json.loads(record_path.read_text())
    names = list(record["active"])
    allowed_names = {"hexproof-home-gateway.service", "hexproof-home-node.service", "hexproof-home-hub.service"}
    if not names or not set(names) <= allowed_names or set(record["enabled"]) != set(names):
        raise ValueError("Rollback record contains an unrelated service")
    allowed_paths = {CONFIG / "gateway.json", CONFIG / "node.json", NGINX, SNIPPET}
    allowed_paths.update(UNITS / name for name in allowed_names)
    files = {}
    for name, saved in record["files"].items():
        path = Path(name)
        if path not in allowed_paths:
            raise ValueError("Rollback record contains an unrelated path")
        if saved is None:
            files[path] = None
        else:
            backup = record_path.parent / saved["file"]
            if not backup.resolve(strict=True).is_relative_to(record_path.parent):
                raise ValueError("Rollback backup escapes its managed directory")
            files[path] = (backup.read_bytes(), saved["mode"], saved["gid"])
    previous = Path(record["previousRelease"]) if record["previousRelease"] else None
    if previous is not None and (not previous.is_dir() or not previous.resolve().is_relative_to(OPT / "releases")):
        raise ValueError("Previous managed release is unavailable")
    if activate:
        for name in reversed(names):
            run("systemctl", "stop", name, check=False)
        switch_release(previous)
        for path, saved in files.items():
            if saved is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, saved[0], saved[1], saved[2])
        run("systemctl", "daemon-reload")
        for name in names:
            run("systemctl", "enable" if record["enabled"][name] else "disable", name, check=False)
            if record["active"][name]:
                run("systemctl", "start", name)
        if NGINX in files:
            run("nginx", "-t")
            run("systemctl", "reload", "nginx.service")
    return {"rollbackChecked": True, "activated": activate, "restoredRelease": str(previous) if previous else None,
            "units": names}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--directory", type=Path, help="Uploaded tree, copied into protected staging before verification")
    parser.add_argument("--manifest-sha256", help="Externally pinned manifest for directory/prepared input")
    parser.add_argument("--prepare", action="store_true", help="Retain a verified tree for later activation")
    parser.add_argument("--prepared", help="Activate an already verified, root-owned release ID")
    parser.add_argument("--verify-current", help="Read-only verification of the running node's full tree SHA-256")
    parser.add_argument("--inspect-current", action="store_true", help="Read-only verified node inventory; no secrets")
    parser.add_argument("--sha256")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--rollback", type=Path, help="Restore a previously saved rollback.json")
    parser.add_argument("--hub-version", default="2.0.6")
    parser.add_argument("--activate", action="store_true", help="Activate after validation; default only checks")
    args = parser.parse_args()
    sources = sum(bool(value) for value in (args.archive, args.directory, args.prepared))
    if args.inspect_current and any((sources, args.verify_current, args.rollback, args.config,
                                     args.activate, args.prepare, args.sha256, args.manifest_sha256)):
        parser.error("--inspect-current cannot be combined with deployment input")
    if args.verify_current and any((sources, args.rollback, args.config, args.activate, args.prepare)):
        parser.error("--verify-current cannot be combined with deployment input")
    if args.rollback and any((sources, args.sha256, args.config, args.manifest_sha256, args.prepare)):
        parser.error("--rollback cannot be combined with deployment input")
    if not args.rollback and not args.verify_current and not args.inspect_current and (sources != 1 or not args.config):
        parser.error("Exactly one of --archive, --directory or --prepared and --config are required")
    if args.archive and (not args.sha256 or args.prepare):
        parser.error("--archive requires --sha256 and does not support --prepare")
    if (args.directory or args.prepared) and not args.manifest_sha256:
        parser.error("Directory and prepared inputs require --manifest-sha256")
    if args.prepared and not args.activate:
        parser.error("--prepared requires --activate")
    try:
        if args.inspect_current:
            result = inspect_current()
        elif args.verify_current:
            result = verify_current(args.verify_current, args.hub_version)
        else:
            result = rollback(args.rollback, args.activate) if args.rollback else install(args)
        print(json.dumps(result, indent=2))
    except subprocess.CalledProcessError as error:
        # Child config validation can contain private input; never echo it.
        parser.exit(1, f"Home deployment command failed: {Path(error.cmd[0]).name} (exit {error.returncode})\n")
    except (ValueError, OSError, RuntimeError, tarfile.TarError) as error:
        parser.exit(1, f"Home deployment failed: {error}\n")


if __name__ == "__main__":
    main()
