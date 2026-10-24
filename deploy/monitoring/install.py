#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Monitoring component invoked after a successful release-server deployment."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent
FILES = ("install.py", "probe.py", "hexproof-monitor.service.in", "hexproof-monitor.timer")
LAYOUTS = {"cloud": (57320, "/usr/local/bin/hexproof-server"),
           "home": (57323, "/opt/hexproof-home/current/server/bin/hexproof-server")}
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5",
               "-o", "ServerAliveCountMax=3"]


def command(*args):
    return subprocess.check_output(list(map(str, args)), text=True, timeout=60).strip()


def ssh(target, *args):
    return command("ssh", *SSH_OPTIONS, target, shlex.join(list(map(str, args))))


def local_install(port, binary, version):
    if os.geteuid() != 0:
        raise ValueError("Monitoring installation requires root")
    if command(binary, "-version") != "hexproof-server " + version:
        raise ValueError("Install monitoring only after the requested application upgrade")
    backup = Path("/var/lib/hexproof-monitor-install") / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup.mkdir(parents=True, mode=0o700)
    content = {
        Path("/usr/local/lib/hexproof-monitor/probe.py"): (ROOT / "probe.py").read_bytes(),
        Path("/etc/systemd/system/hexproof-monitor.service"):
            (ROOT / "hexproof-monitor.service.in").read_text().replace("@PORT@", str(port)).encode(),
        Path("/etc/systemd/system/hexproof-monitor.timer"): (ROOT / "hexproof-monitor.timer").read_bytes(),
    }
    record = {"version": version, "port": port, "files": {}}
    for path, data in content.items():
        if path.exists():
            shutil.copy2(path, backup / path.name)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.chmod(0o644)
        temporary.replace(path)
        record["files"][str(path)] = hashlib.sha256(data).hexdigest()
    (backup / "installation.json").write_text(json.dumps(record, indent=2) + "\n")
    command("systemd-analyze", "verify", "/etc/systemd/system/hexproof-monitor.service",
            "/etc/systemd/system/hexproof-monitor.timer")
    command("systemctl", "daemon-reload")
    command("systemctl", "enable", "--now", "hexproof-monitor.timer")
    started = time.time()
    command("systemctl", "start", "hexproof-monitor.service")
    latest = Path("/var/lib/hexproof-monitor/latest.json")
    sample = json.loads(latest.read_text())
    if latest.stat().st_mtime < started - 15 or not sample.get("live") or not sample.get("ready"):
        raise ValueError("Monitor installed, but fresh liveness/readiness collection failed")
    if command("systemctl", "is-active", "hexproof-monitor.timer") != "active":
        raise ValueError("Monitoring timer is inactive")
    record["sample"] = sample
    record["backup"] = str(backup)
    print(json.dumps(record))


def deploy(targets, version):
    # The remote --local installer needs no workstation inventory or loader.
    sys.path.insert(0, str(ROOT.parent))
    import operator_config
    configured = {}
    nodes = operator_config.load_nodes(required=False)
    for name in targets:
        kind = operator_config.classify(name)
        if kind == "home":
            host = nodes[operator_config.home_name(name, nodes)]["ssh"]
        else:
            host = name
        if host in configured:
            raise ValueError("Select distinct configured monitoring targets")
        configured[host] = LAYOUTS[kind]
    names = list(configured)
    if not names:
        raise ValueError("Select distinct configured deployment targets")
    # Check every node before writing any monitoring file.
    for name in names:
        if ssh(name, configured[name][1], "-version") != "hexproof-server " + version:
            raise ValueError(name + ": application version does not match")
        ssh(name, "sudo", "-n", "true")
        ssh(name, "python3", "-c", "import sys; assert sys.version_info >= (3, 9)")
    evidence = ROOT.parents[1] / "build" / ("release-" + version) / "monitoring"
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hexproof-monitor-") as temporary:
        stage = Path(temporary)
        checksums = []
        for name in FILES:
            shutil.copy2(ROOT / name, stage / name)
            checksums.append(hashlib.sha256((stage / name).read_bytes()).hexdigest() + "  " + name)
        (stage / "SHA256SUMS").write_text("\n".join(checksums) + "\n")
        for name in names:
            remote = ssh(name, "mktemp", "-d", "/tmp/hexproof-monitor.XXXXXXXX")
            if not re.fullmatch(r"/tmp/hexproof-monitor\.[A-Za-z0-9]+", remote):
                raise ValueError("Unexpected remote staging path")
            try:
                command("scp", *SSH_OPTIONS, *(stage / item for item in (*FILES, "SHA256SUMS")),
                        name + ":" + remote + "/")
                ssh(name, "sh", "-c", "cd " + shlex.quote(remote) + " && sha256sum -c SHA256SUMS")
                port, binary = configured[name]
                output = ssh(name, "sudo", "-n", "python3", remote + "/install.py", "--local",
                             "--port", port, "--binary", binary, "--version", version)
                result = json.loads(output)
                (evidence / (name + ".json")).write_text(json.dumps(result, indent=2) + "\n")
                print(name + ": local monitoring installed; fresh readiness collection passed", flush=True)
            finally:
                ssh(name, "rm", "-rf", "--", remote)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--targets", nargs="+")
    parser.add_argument("--local", action="store_true")
    parser.add_argument("--port", type=int, choices=(57320, 57323))
    parser.add_argument("--binary")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("An explicit application version is required")
    if args.local:
        if (args.port, args.binary) not in LAYOUTS.values():
            parser.error("Select a configured local hub")
        local_install(args.port, args.binary, args.version)
    elif args.targets:
        deploy(args.targets, args.version)
    else:
        parser.error("Use deploy/deploy-release-server.sh with explicit targets")
