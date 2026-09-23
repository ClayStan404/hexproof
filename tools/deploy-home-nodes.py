#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Build, incrementally stage and sequentially activate reviewed home nodes.

No credentials belong in the input. Existing SSH aliases and protected remote
node configuration are used as-is. Default mode prepares without restarting.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PACKAGE = load("home_package", "tools/package-home-node.py")
INSTALL = load("home_install", "deploy/install-home-node.py")
SMOKE = load("home_smoke", "tools/smoke-home-node.py")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def fingerprint(paths):
    """Hash tracked inputs by content, not by commit or timestamps."""
    names = subprocess.check_output(["git", "ls-files", "-z", "--", *paths], cwd=ROOT).split(b"\0")
    digest = hashlib.sha256()
    for name in sorted(filter(None, names)):
        path = ROOT / os.fsdecode(name)
        digest.update(name + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def run(args, log=None, **kwargs):
    if log is None:
        return subprocess.check_output(list(map(str, args)), cwd=ROOT, text=True, **kwargs)
    with log.open("w") as stream:
        subprocess.run(list(map(str, args)), cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                       check=True, **kwargs)


def ssh(target, *args, **kwargs):
    # SSH concatenates remote argv into shell code; quote every argument.
    return run(["ssh", "-o", "BatchMode=yes", target, shlex.join(list(map(str, args)))], **kwargs)


def verified_artifact(record):
    path = Path(record["path"]).resolve(strict=True)
    if not re.fullmatch(r"[a-f0-9]{64}", record["sha256"]) or PACKAGE.digest(path) != record["sha256"]:
        raise ValueError(f"Artifact checksum mismatch: {path.name}")
    return path


def ensure_forge(inputs, cache):
    recipe = fingerprint(["third_party/forge-runtime"])
    if "forge" in inputs:
        pair = inputs["forge"]
    else:
        output = cache / "forge" / recipe
        output.mkdir(parents=True, exist_ok=True)
        proof = output / "verified.json"
        if proof.exists():
            pair = json.loads(proof.read_text())
        else:
            print("Building Forge and running native/source checks...", flush=True)
            run(["third_party/forge-runtime/build.sh", "--source", inputs["forgeSource"],
                 "--output", output], output / "build.log")
            pair = {}
            for key in ("runtime", "source"):
                path, = output.glob(f"hexproof-forge-{key}-*.tar.gz")
                pair[key] = {"path": str(path), "sha256": PACKAGE.digest(path)}
            write_json(proof, pair)
    runtime, source = (verified_artifact(pair[key]) for key in ("runtime", "source"))
    key = hashlib.sha256((recipe + pair["runtime"]["sha256"] + pair["source"]["sha256"]).encode()).hexdigest()
    proof = cache / "forge-checks" / (key + ".json")
    if not proof.exists():
        proof.parent.mkdir(parents=True, exist_ok=True)
        run(["python3", "third_party/forge-runtime/source-package.py", "verify-release",
             "--runtime", runtime, "--source", source], proof.with_suffix(".log"))
        write_json(proof, pair)
    return pair


def ensure_servers(arches, cache):
    key = fingerprint(["apps/server", "packaging/server", "apps/client-qt/CMakeLists.txt",
                       "docs/home-servers.md", "LICENSE", "THIRD-PARTY-NOTICES.md"])
    output = cache / "server" / key
    output.mkdir(parents=True, exist_ok=True)

    def build(arch):
        proof = output / (arch + ".json")
        if proof.exists():
            record = json.loads(proof.read_text())
            verified_artifact(record)
            return arch, record
        run(["packaging/server/build-tarball.sh"], output / (arch + ".log"),
            env=dict(os.environ, HEXPROOF_ARCH=arch, HEXPROOF_OUTPUT_DIR=str(output), GOFLAGS="-buildvcs=false"))
        path, = output.glob(f"hexproof-server-*-linux-{arch}.tar.gz")
        record = {"path": str(path), "sha256": PACKAGE.digest(path)}
        write_json(proof, record)
        return arch, record

    with ThreadPoolExecutor(max_workers=2) as pool:
        return dict(pool.map(build, sorted(arches)))


def ensure_checks(cache):
    key = fingerprint(["tools", "deploy", "apps/server", "testdata", "third_party/forge-runtime",
                       "apps/client-qt", "docs", "packaging", "CMakeLists.txt", "AGENTS.md"])
    proof = cache / "checks" / (key + ".json")
    if not proof.exists():
        proof.parent.mkdir(parents=True, exist_ok=True)
        print("Running server verification...", flush=True)
        run(["tools/verify.sh", "--scope", "server"], proof.with_suffix(".log"))
        write_json(proof, {"inputSha256": key, "command": "tools/verify.sh --scope server", "passed": True})


def build_tree(target, server, forge, java, revision, cache):
    inputs = {"server": server, "forge": forge, "java": java, "sourceCommit": revision,
              "recipe": fingerprint(["tools/package-home-node.py", "deploy/home"])}
    key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    output = cache / "trees" / key
    proof = output.with_suffix(".json")
    if proof.exists():
        record = json.loads(proof.read_text())
        INSTALL.verify_tree(output, record["manifestSha256"])
        return record
    # Only the tiny connector is needed separately; avoid unpacking server twice.
    import tarfile
    with tarfile.open(server["path"]) as archive:
        member, = [item for item in archive.getmembers() if item.name.endswith("/bin/hexproof-home")]
        binary = cache / ("connector-" + target["arch"])
        binary.write_bytes(archive.extractfile(member).read())
    args = argparse.Namespace(output=output, directory=True, binary=binary, kind="node", source_commit=revision)
    for prefix, artifact in (("hub", server), ("forge", forge["runtime"]),
                             ("forge_source", forge["source"]), ("java", java)):
        setattr(args, prefix + "_archive", verified_artifact(artifact))
        setattr(args, prefix + "_sha256", artifact["sha256"])
    record = PACKAGE.build(args)
    write_json(proof, record)
    return record


def assert_idle(target, version):
    ws = SMOKE.WebSocket(target["endpoint"])
    try:
        ws.send("session.hello", "hello", {"displayName": "DeploymentPreflight", "clientVersion": version,
                                          "protocol": "hexproof.v1"})
        ws.until("session.welcome")
        ws.send("room.list", "rooms", {})
        if ws.until("room.listed")["rooms"]:
            raise ValueError("Active rooms; node was not restarted: " + target["ssh"])
    finally:
        ws.close()
    ssh(target["ssh"], "sh", "-c", 'test "$(pgrep -u hexproof-home -c java || true)" = 0')


def stage(target, record, version, report_dir):
    name = target["ssh"]
    expected = {"amd64": "x86_64", "arm64": "aarch64"}[target["arch"]]
    if ssh(name, "uname", "-m").strip() != expected:
        raise ValueError("Target architecture mismatch: " + name)
    ssh(name, "systemctl", "is-active", "hexproof-home-hub", "hexproof-home-node")
    stage_path = "/var/tmp/hexproof-home-" + record["releaseId"]
    ssh(name, "mkdir", "-p", "-m", "700", stage_path)
    run(["scp", "-q", "deploy/install-home-node.py", name + ":" + stage_path + "/install.py"])
    current = ssh(name, "readlink", "-f", "/opt/hexproof-home/current").strip()
    if current == "/opt/hexproof-home/releases/" + record["releaseId"]:
        response = json.loads(ssh(name, "sudo", "-n", "python3", stage_path + "/install.py",
                                 "--verify-current", record["treeSha256"], "--hub-version", version))
        write_json(report_dir / (name + "-staged.json"), response)
        return stage_path, response
    # Copy unchanged files locally on the target, delta-transfer changed files.
    # Fuzzy twice also finds a previous version's differently named source archive.
    run(["rsync", "-a", "--checksum", "--stats", "--partial", "--fuzzy", "--fuzzy",
         "--copy-dest=/opt/hexproof-home/current", "-e", "ssh -o BatchMode=yes",
         record["directory"] + "/", name + ":" + stage_path + "/tree/"], report_dir / (name + "-transfer.log"))
    response = json.loads(ssh(name, "sudo", "-n", "python3", stage_path + "/install.py",
                             "--directory", stage_path + "/tree", "--manifest-sha256", record["manifestSha256"],
                             "--config", "/etc/hexproof-home/node.json", "--hub-version", version, "--prepare"))
    write_json(report_dir / (name + "-staged.json"), response)
    print(name + ": staged and verified", flush=True)
    return stage_path, response


def activate(target, record, staged, version, report_dir):
    name = target["ssh"]
    stage_path, response = staged
    if response.get("unchanged"):
        print(name + ": already running this verified tree; no restart", flush=True)
        return
    assert_idle(target, version)
    result = json.loads(ssh(name, "sudo", "-n", "python3", stage_path + "/install.py",
                            "--prepared", record["releaseId"], "--manifest-sha256", record["manifestSha256"],
                            "--config", "/etc/hexproof-home/node.json", "--hub-version", version, "--activate"))
    write_json(report_dir / (name + "-activation.json"), result)
    try:
        # The outbound connector can become reachable after the local hub is ready.
        deadline = time.monotonic() + 120
        while True:
            try:
                report = SMOKE.smoke(target["endpoint"], version, True, False, True)
                break
            except (OSError, ValueError, EOFError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)
        report["forgeGame"] = SMOKE.forge_smoke(target["endpoint"], version)
        assert_idle(target, version)
        write_json(report_dir / (name + "-smoke.json"), report)
        print(name + ": activated; public Forge game and privacy smoke passed", flush=True)
    except BaseException:
        rollback = json.loads(ssh(name, "sudo", "-n", "python3", stage_path + "/install.py",
                                  "--rollback", result["rollbackRecord"], "--activate"))
        write_json(report_dir / (name + "-rollback.json"), rollback)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True, help="Verified Forge/JRE inputs; see deploy/home/README.md")
    parser.add_argument("--targets", nargs="+", required=True, help="Names from --nodes")
    parser.add_argument("--nodes", type=Path, default=ROOT / "deploy/home/nodes.json")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/home-deploy")
    parser.add_argument("--activate", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    # A deployment is always reproducible from a committed source snapshot.
    if run(["git", "status", "--porcelain", "--untracked-files=normal", "--", "apps", "tools", "deploy",
            "third_party", "packaging", "testdata", "docs", "AGENTS.md", "LICENSE", "THIRD-PARTY-NOTICES.md"]):
        raise ValueError("Commit reviewed deployment inputs before running this command")
    inputs = json.loads(args.artifacts.read_text())
    nodes = json.loads(args.nodes.read_text())
    targets = [nodes[name] for name in dict.fromkeys(args.targets)]
    if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", node["ssh"]) for node in targets):
        raise ValueError("Targets must use plain existing SSH aliases")
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    # Exclude overlapping deploys sharing cache/prepared trees and service state.
    import fcntl
    with (cache / "deployment.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        revision = run(["git", "rev-parse", "HEAD"]).strip()
        version = re.search(r'set\(HEXPROOF_VERSION\s+"([0-9.]+)"',
                            (ROOT / "apps/client-qt/CMakeLists.txt").read_text())[1]
        report_dir = cache / "runs" / (time.strftime("%Y%m%d-%H%M%S") + "-" + revision[:8])
        report_dir.mkdir(parents=True)
        started = time.monotonic()
        with ThreadPoolExecutor(max_workers=3) as pool:
            forge_job = pool.submit(ensure_forge, inputs, cache)
            server_job = pool.submit(ensure_servers, {node["arch"] for node in targets}, cache)
            checks_job = pool.submit(ensure_checks, cache)
            forge, servers = forge_job.result(), server_job.result()
            checks_job.result()
        records = [build_tree(node, servers[node["arch"]], forge, inputs["java"][node["arch"]], revision, cache)
                   for node in targets]
        write_json(report_dir / "artifacts.json", dict(zip(args.targets, records)))
        with ThreadPoolExecutor(max_workers=2) as pool:
            jobs = [pool.submit(stage, node, record, version, report_dir) for node, record in zip(targets, records)]
            # All nodes finish staging before the first activation.
            staged = [job.result() for job in jobs]
        if args.activate:
            for node, record, preparation in zip(targets, records, staged):
                activate(node, record, preparation, version, report_dir)
            for node, (_, response) in zip(targets, staged):
                # Delete only this exact private upload directory, never releases,
                # sources, rollback records or another task's files.
                path = "/var/tmp/hexproof-home-" + response["releaseId"]
                ssh(node["ssh"], "python3", "-c",
                    "import pathlib,shutil,sys; p=pathlib.Path(sys.argv[1]); "
                    "assert p.parent==pathlib.Path('/var/tmp') and not p.is_symlink(); shutil.rmtree(p)", path)
        write_json(report_dir / "result.json", {"sourceCommit": revision, "activated": args.activate,
                                               "elapsedSeconds": round(time.monotonic() - started, 1)})
        print("Evidence: " + str(report_dir), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"Home deployment failed: {error}")
