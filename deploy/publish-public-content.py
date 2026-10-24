#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Publish a validated content package; immutable assets first, atomic index last."""

from __future__ import annotations

import argparse
import base64
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import sys
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("public_content", ROOT / "tools/public-content.py")
CONTENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTENT)
sys.path.insert(0, str(Path(__file__).resolve().parent))
import operator_config

REMOTE = '''import base64, fcntl, hashlib, json, os, pathlib, re, sys
request = json.load(sys.stdin)
root = pathlib.Path("/var/www/hexproof/content")
name = request.get("path", "index.json")
if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_./-]{0,511}", name) or any(p in ("", ".", "..") for p in name.split("/")):
    raise SystemExit("Invalid content path")
path = root / name
if request["mode"] == "read":
    if path.exists() and path.stat().st_size > 2097152: raise SystemExit("Content is oversized")
    sys.stdout.buffer.write(path.read_bytes() if path.exists() else b"")
elif request["mode"] == "asset":
    if not name.startswith("releases/"): raise SystemExit("Expected immutable release path")
    data = base64.b64decode(request["payload"], validate=True)
    if hashlib.sha256(data).hexdigest() != request["sha256"]: raise SystemExit("Asset digest mismatch")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() != data: raise SystemExit("An immutable asset already has different bytes")
    else:
        staged = path.with_name("." + path.name + "-" + request["token"])
        try:
            with staged.open("xb") as output: output.write(data)
            staged.chmod(0o644)
            os.link(staged, path)
        except FileExistsError:
            if not path.exists() or path.read_bytes() != data: raise
        finally:
            staged.unlink(missing_ok=True)
elif request["mode"] == "index":
    if name != "index.json": raise SystemExit("Expected the content index")
    root.mkdir(parents=True, exist_ok=True)
    lock = (root / ".publish.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    data = base64.b64decode(request["payload"], validate=True)
    current = path.read_bytes() if path.exists() else b""
    if hashlib.sha256(current).hexdigest() != request["expected"]:
        raise SystemExit("Content index changed after preflight; retry")
    staged = root / (".index-" + request["token"] + ".json")
    try:
        with staged.open("xb") as output: output.write(data)
        staged.chmod(0o644)
        if current:
            previous = root / (".previous-" + request["token"])
            previous.write_bytes(current)
            os.replace(previous, root / "index.json.previous")
        os.replace(staged, path)
    finally:
        staged.unlink(missing_ok=True)
else:
    raise SystemExit("Unknown publication operation")
'''


def remote(target: str, **request: object) -> bytes:
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", target,
         "python3 -c " + shlex.quote(REMOTE)],
        input=json.dumps(request).encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False, timeout=40,
    )
    if result.returncode:
        raise ValueError(result.stderr.decode(errors="replace").strip())
    return result.stdout


def publish(package: Path, target: str) -> None:
    public_origin = operator_config.cloud_target(target, "publish")["origin"] + "/hexproof/content/"
    index, files, documents = CONTENT.read_package(package)
    previous = remote(target, mode="read")
    if previous:
        old = CONTENT.validate_index(json.loads(previous))
        CONTENT.require(index["revision"] >= old["revision"], "Index revision must not decrease")
        if index["revision"] == old["revision"]:
            CONTENT.require(index == old, "Increment index revision before changing content")
        for kind in ("sponsors", "announcements"):
            old_payload = remote(target, mode="read", path=old[kind]["path"])
            CONTENT.require(CONTENT.sha256(old_payload) == old[kind]["sha256"], "Published content does not match its index")
            CONTENT.validate_update(CONTENT.validate_document(kind, json.loads(old_payload)), documents[kind], kind)
    token = uuid.uuid4().hex
    for path, payload in files.items():
        if path != "index.json":
            remote(target, mode="asset", path=path, token=token,
                   payload=base64.b64encode(payload).decode(), sha256=CONTENT.sha256(payload))
    # Verify public asset delivery before making the new index visible to clients.
    for path, expected in files.items():
        if path == "index.json":
            continue
        with urllib.request.urlopen(public_origin + path, timeout=15) as response:
            CONTENT.require(response.read(len(expected) + 1) == expected, f"Public content differs: {path}")
    remote(target, mode="index", token=token, expected=CONTENT.sha256(previous),
           payload=base64.b64encode(files["index.json"]).decode())
    request = urllib.request.Request(public_origin + "index.json", headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=15) as response:
        CONTENT.require(response.read(32769) == files["index.json"], "Public index differs after publication")
    print(f"Published and verified public content revision {index['revision']} on {target}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--target", help="Configured publication SSH target")
    args = parser.parse_args()
    try:
        publish(args.package, args.target or operator_config.defaults("publishTargets")[0])
        return 0
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
        print(f"Content publication failed: {error}. Fix the cause, then retry the same package.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
