#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Validate and atomically publish an online catalog to the maintained mirrors."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import sys
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("server_directory", ROOT / "tools/write-server-directory.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)
sys.path.insert(0, str(Path(__file__).resolve().parent))
import operator_config

# Each write checks the preflight digest again so concurrent operator updates
# cannot be overwritten. Every file lives on the same filesystem as the target.
REMOTE = '''import hashlib, json, os, pathlib, sys
request = json.load(sys.stdin)
root = pathlib.Path("/var/www/hexproof")
live = root / "servers.json"
staged = root / (".servers-" + request["token"] + ".json")
current = live.read_bytes() if live.exists() else b""
if request["mode"] == "read":
    if len(current) > 65536: raise SystemExit("Remote catalog is oversized")
    sys.stdout.buffer.write(current)
elif request["mode"] == "cleanup":
    staged.unlink(missing_ok=True)
else:
    if hashlib.sha256(current).hexdigest() != request["expected"]:
        raise SystemExit("Catalog changed after preflight; retry with the current revision")
    if request["mode"] == "stage":
        with staged.open("xb") as output:
            output.write(request["payload"].encode("utf-8"))
        staged.chmod(0o644)
    elif request["mode"] == "publish":
        if hashlib.sha256(staged.read_bytes()).hexdigest() != request["digest"]:
            raise SystemExit("Staged catalog digest mismatch")
        if current:
            backup = root / (".servers-" + request["token"] + ".previous")
            with backup.open("xb") as output: output.write(current)
            os.replace(backup, root / "servers.json.previous")
        os.replace(staged, live)
    else: raise SystemExit("Invalid operation")
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def remote(target: str, **request: object) -> bytes:
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", target,
         "python3 -c " + shlex.quote(REMOTE)],
        input=json.dumps(request).encode(), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=False, timeout=40,
    )
    if result.returncode:
        raise ValueError(f"{target}: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def validate_update(previous: bytes, document: dict) -> None:
    if not previous:
        return
    old = VALIDATOR.validate_directory(json.loads(previous))
    if old.get("revision", 0) > document["revision"]:
        raise ValueError("refusing to replace a newer catalog revision")
    if old.get("revision", 0) == document["revision"] and old != document:
        raise ValueError("increment revision before changing the catalog")


def publish(path: Path, targets: list[str]) -> None:
    origins = {target: operator_config.cloud_target(target, "publish")["origin"] for target in targets}
    raw = path.read_bytes()
    if len(raw) > 65536:
        raise ValueError("the directory must not exceed 64 KiB")
    document = VALIDATOR.validate_directory(json.loads(raw))
    if document["schemaVersion"] != 2:
        raise ValueError("online catalogs require schemaVersion 2")
    payload = (json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode()
    if len(payload) > 65536:
        raise ValueError("the formatted directory must not exceed 64 KiB")
    token = uuid.uuid4().hex
    previous = {}
    # Finish validation on every host before staging or publishing any host.
    for target in targets:
        previous[target] = remote(target, mode="read", token=token)
        validate_update(previous[target], document)
    changed = [target for target in targets if previous[target] != payload]
    try:
        for target in changed:
            remote(target, mode="stage", token=token, expected=digest(previous[target]),
                   payload=payload.decode())
        for target in changed:
            remote(target, mode="publish", token=token, expected=digest(previous[target]),
                   digest=digest(payload))
            print(f"Published revision {document['revision']} on {target}", flush=True)
        for target in targets:
            request = urllib.request.Request(origins[target] + "/hexproof/servers.json",
                                             headers={"Cache-Control": "no-cache"})
            with urllib.request.urlopen(request, timeout=15) as response:
                observed = response.read(65537)
            if observed != payload:
                raise ValueError(f"{target}: public HTTPS catalog differs from the staged document")
            print(f"Verified {target}: revision {document['revision']} ({digest(payload)[:12]})")
    finally:
        for target in changed:
            try:
                remote(target, mode="cleanup", token=token)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                print(f"Staging cleanup: {error}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--targets", nargs="+", help="Configured publication SSH targets")
    args = parser.parse_args()
    try:
        publish(args.catalog, list(dict.fromkeys(args.targets or operator_config.defaults("publishTargets"))))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Directory publish failed: {error}. After resolving the error, rerun the same catalog to finish any partial mirror update.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
