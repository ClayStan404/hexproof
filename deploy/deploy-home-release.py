#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Home-node backend for deploy-release-server.sh; deploy verified GitHub bytes."""

from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time
import uuid


# Also support importlib-based tooling/tests that do not put deploy/ on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import operator_config

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


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


def running_protocol(target):
    return inspect(target)["protocol"]


def assert_idle(target, version):
    game_protocol = running_protocol(target)
    ws = SMOKE.WebSocket(target["endpoint"])
    try:
        ws.send("session.hello", "hello", {"displayName": "DeploymentPreflight", "clientVersion": version,
                                          "protocol": game_protocol})
        welcome = ws.until("session.welcome")
        if welcome.get("v") != game_protocol or welcome.get("serverVersion") != version:
            raise ValueError("Preflight endpoint does not match the inspected hub")
        ws.send("room.list", "rooms", {})
        if ws.until("room.listed")["rooms"]:
            raise ValueError("Active rooms; node was not restarted: " + target["ssh"])
    finally:
        ws.close()
    ssh(target["ssh"], "sh", "-c", 'test "$(pgrep -u hexproof-home -c java || true)" = 0')


def running_version(target):
    output = ssh(target["ssh"], "/opt/hexproof-home/current/server/bin/hexproof-server", "-version").strip()
    match = re.fullmatch(r"hexproof-server ([0-9]+\.[0-9]+\.[0-9]+)", output)
    if not match:
        raise ValueError("Could not determine current server version: " + target["ssh"])
    return match[1]


def activate(target, record, staged, version, report_dir, allow_active_rooms=False):
    name = target["ssh"]
    stage_path, response = staged
    if response.get("unchanged"):
        print(name + ": already running this verified tree; no restart", flush=True)
        return
    if not response.get("initial"):
        previous_version = running_version(target)
        if not allow_active_rooms:
            assert_idle(target, previous_version)
    result = json.loads(ssh(name, "sudo", "-n", "python3", stage_path + "/install.py",
                            "--prepared", record["releaseId"], "--manifest-sha256", record["manifestSha256"],
                            "--config", response.get("config", "/etc/hexproof-home/node.json"),
                            "--hub-version", version, "--activate"))
    write_json(report_dir / (name + "-activation.json"), result)
    try:
        game_protocol = running_protocol(target)
        # The outbound connector can become reachable after the local hub is ready.
        deadline = time.monotonic() + 120
        while True:
            try:
                report = SMOKE.smoke(target["endpoint"], version, True, False, True, game_protocol)
                break
            except (OSError, ValueError, EOFError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)
        report["forgeGame"] = SMOKE.forge_smoke(target["endpoint"], version, game_protocol)
        assert_idle(target, version)
        write_json(report_dir / (name + "-smoke.json"), report)
        print(name + ": activated; public Forge game and privacy smoke passed", flush=True)
    except BaseException:
        rollback = json.loads(ssh(name, "sudo", "-n", "python3", stage_path + "/install.py",
                                  "--rollback", result["rollbackRecord"], "--activate"))
        write_json(report_dir / (name + "-rollback.json"), rollback)
        raise


PACKAGE = load("home_package", "tools/package-home-node.py")
INSTALL = load("home_install", "deploy/install-home-node.py")
SMOKE = load("home_smoke", "tools/smoke-home-node.py")
INSTALLER = ROOT / "deploy/install-home-node.py"


def github(*args):
    return run(["gh", *args])


def release_metadata(repo, version):
    return json.loads(github("release", "view", *(["v" + version] if version else []),
        "--repo", repo, "--json", "databaseId,tagName,isDraft,targetCommitish,assets,url"))


def validate_release(metadata, version, allow_draft):
    tag = metadata["tagName"]
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) or version and tag != "v" + version:
        raise ValueError("Release tag does not match the requested application version")
    if metadata["isDraft"] and not (allow_draft and version):
        raise ValueError("Draft deployment requires an explicit version and HEXPROOF_ALLOW_DRAFT=1")
    return tag[1:]


def asset_map(metadata):
    assets = {item["name"]: item for item in metadata["assets"]}
    if len(assets) != len(metadata["assets"]):
        raise ValueError("Duplicate release assets")
    return assets


def verify_downloads(directory, metadata, names):
    assets = asset_map(metadata)
    checksums = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        checksum, name = line.split("  ", 1)
        if name in checksums or not re.fullmatch(r"[a-f0-9]{64}", checksum):
            raise ValueError("Invalid or duplicate release checksum")
        checksums[name] = checksum
    for name in ["SHA256SUMS", *names]:
        actual = PACKAGE.digest(directory / name)
        if assets[name].get("digest") != "sha256:" + actual:
            raise ValueError("GitHub asset digest mismatch: " + name)
        if name != "SHA256SUMS" and checksums.get(name) != actual:
            raise ValueError("Release checksum mismatch: " + name)


def fetch_release(repo, version, allow_draft, arches, report):
    metadata = release_metadata(repo, version)
    version = validate_release(metadata, version, allow_draft)
    tag = metadata["tagName"]
    source = github("api", f"repos/{repo}/commits/{tag}", "--jq", ".sha").strip()
    if not re.fullmatch(r"[a-f0-9]{40}", source):
        raise ValueError("Could not pin the release tag's source commit")
    names = {arch: f"hexproof-server-{version}-linux-{arch}.tar.gz" for arch in sorted(arches)}
    assets = asset_map(metadata)
    for name in ["SHA256SUMS", *names.values()]:
        if name not in assets or not re.fullmatch(r"sha256:[a-f0-9]{64}", assets[name].get("digest") or ""):
            raise ValueError("Release lacks a checksum-pinned asset: " + name)
    directory = report / "assets"
    directory.mkdir()
    patterns = [option for name in ["SHA256SUMS", *names.values()] for option in ("--pattern", name)]
    github("release", "download", tag, "--repo", repo, "--dir", str(directory), *patterns)
    verify_downloads(directory, metadata, list(names.values()))
    provenance = github("attestation", "verify", str(directory / "SHA256SUMS"), "--repo", repo,
        "--signer-workflow", repo + "/.github/workflows/release.yml", "--source-digest", source,
        "--source-ref", "refs/tags/" + tag, "--format", "json")
    (report / "provenance.json").write_text(provenance)
    after = release_metadata(repo, version)
    if (after["databaseId"] != metadata["databaseId"] or after["tagName"] != tag
            or after["isDraft"] != metadata["isDraft"]
            or {name: item["digest"] for name, item in asset_map(after).items()}
            != {name: item["digest"] for name, item in assets.items()}
            or github("api", f"repos/{repo}/commits/{tag}", "--jq", ".sha").strip() != source):
        raise ValueError("Release changed during verification; retry with stable artifacts")
    records = {}
    for arch, name in names.items():
        archive = directory / name
        checksum = PACKAGE.digest(archive)
        with tempfile.TemporaryDirectory(prefix="inspect-", dir=report) as temporary:
            tree = PACKAGE.checked_archive(archive, checksum, Path(temporary) / "archive")
            if tree.name != f"hexproof-server-{version}-linux-{arch}":
                raise ValueError("Unexpected server archive root")
            binaries = {}
            for binary in ("hexproof-server", "hexproof-home"):
                path = tree / "bin" / binary
                if path.is_symlink() or not path.is_file() or not path.stat().st_mode & 0o111:
                    raise ValueError("Missing regular release executable: " + binary)
                binaries[binary] = PACKAGE.digest(path)
        records[arch] = {"path": str(archive), "sha256": checksum, "binaries": binaries}
    release = {"version": version, "sourceCommit": source, "github": metadata, "artifacts": records}
    write_json(report / "release.json", release)
    return release


def inspect(target):
    # Stream the reviewed installer; read-only verification needs no remote upload.
    return json.loads(ssh(target["ssh"], "sudo", "-n", "python3", "-", "--inspect-current",
                                 input=INSTALLER.read_text(), timeout=300))


def matches(state, artifact, version):
    return (state["current"] is not None and state["version"] == version
            and state["manifest"]["sources"].get("hubArchiveSha256") == artifact["sha256"]
            and state["hubSha256"] == artifact["binaries"]["hexproof-server"]
            and state["connectorSha256"] == artifact["binaries"]["hexproof-home"])


def unchanged_baseline(before, now):
    if before["current"] is None:
        if now["current"] is not None:
            raise ValueError("A release appeared before initial installation")
        return
    for key in ("current", "manifestSha256", "version", "configSha256", "unitHashes", "pids"):
        if before[key] != now[key]:
            raise ValueError("Deployment baseline changed before activation: " + key)


def build_payloads(inputs, release, targets, report):
    """Assemble GitHub binaries with explicitly supplied, checksum-pinned runtimes."""
    forge = inputs["forge"]
    runtime, source = (verified_artifact(forge[key]) for key in ("runtime", "source"))
    run(["python3", "third_party/forge-runtime/source-package.py", "verify-release",
         "--runtime", runtime, "--source", source], report / "runtime-verification.log")
    records = {}
    for arch in sorted({node["arch"] for node in targets}):
        server = release["artifacts"][arch]
        java = inputs["java"][arch]
        with tempfile.TemporaryDirectory(dir=report) as temporary:
            tree = PACKAGE.checked_archive(Path(server["path"]), server["sha256"], Path(temporary) / "server")
            args = argparse.Namespace(output=report / ("tree-" + arch), directory=True,
                binary=tree / "bin/hexproof-home", kind="node", source_commit=release["sourceCommit"])
            for prefix, artifact in (("hub", server), ("forge", forge["runtime"]),
                                     ("forge_source", forge["source"]), ("java", java)):
                setattr(args, prefix + "_archive", verified_artifact(artifact))
                setattr(args, prefix + "_sha256", artifact["sha256"])
            records[arch] = PACKAGE.build(args)
    return records


def initial_config(inputs, target):
    path = Path(inputs.get("config", {}).get(target["ssh"], "")).resolve()
    if not path.is_file():
        raise ValueError("First installation requires a private config file for " + target["ssh"])
    configuration = json.loads(path.read_text())
    if (configuration.get("backendUrl") != "ws://127.0.0.1:57323/ws"
            or configuration.get("healthUrl") != "http://127.0.0.1:57323/healthz"):
        raise ValueError("Initial node config must use the isolated loopback backend 57323")
    return path


def stage(target, before, artifact, release, upload, report, payload=None, config=None):
    name = target["ssh"]
    ssh(name, "mkdir", "-m", "700", upload)
    run(["scp", "-q", "--", INSTALLER, name + ":" + upload + "/install.py"])
    if payload:
        record = payload
        run(["rsync", "-a", "--checksum", "-e", "ssh -o BatchMode=yes", "--",
             record["directory"] + "/", name + ":" + upload + "/tree/"])
    else:
        ssh(name, "mkdir", upload + "/tools", upload + "/deploy")
        run(["scp", "-q", "--", artifact["path"], name + ":" + upload + "/"])
        run(["scp", "-q", "--", ROOT / "tools/package-home-node.py", name + ":" + upload + "/tools/"])
        ssh(name, "cp", upload + "/install.py", upload + "/deploy/install-home-node.py")
        record = json.loads(ssh(name, "python3", upload + "/tools/package-home-node.py",
            "--kind", "node", "--directory", "--upgrade-from", before["current"],
            "--base-manifest-sha256", before["manifestSha256"], "--hub-archive", upload + "/" + Path(artifact["path"]).name,
            "--hub-sha256", artifact["sha256"], "--source-commit", release["sourceCommit"], "--output", upload + "/tree"))
        if record["sources"].get("baseTreeSha256") != before["manifest"]["treeSha256"]:
            raise ValueError("Prepared tree does not derive from the verified baseline")
    remote_config = "/etc/hexproof-home/node.json"
    if config:
        remote_config = upload + "/node.json"
        run(["scp", "-q", "--", config, name + ":" + remote_config])
    write_json(report / (name + "-tree.json"), record)
    prepared = json.loads(ssh(name, "sudo", "-n", "python3", upload + "/install.py",
        "--directory", upload + "/tree", "--manifest-sha256", record["manifestSha256"],
        "--config", remote_config, "--hub-version", release["version"], "--prepare"))
    if not prepared.get("checked") or prepared.get("activated") or prepared["releaseId"] != record["releaseId"]:
        raise ValueError("Unexpected preparation result")
    prepared.update(initial=before["current"] is None, config=remote_config)
    if config:
        prepared["configSha256"] = PACKAGE.digest(config)
    write_json(report / (name + "-staged.json"), prepared)
    print(name + ": release staged and verified", flush=True)
    return record, (upload, prepared)


def verify_installed(target, before, artifact, release, report, payload=None, config_sha=None):
    after = inspect(target)
    if not matches(after, artifact, release["version"]):
        raise ValueError("Installed binaries do not match the verified release")
    if before["current"] is not None:
        for key in (("configSha256",) if payload else ("configSha256", "unitHashes")):
            if after[key] != before[key]:
                raise ValueError("Upgrade changed node configuration: " + key)
        if payload is None:
            old_sources, new_sources = before["manifest"]["sources"], after["manifest"]["sources"]
            for key in ("forgeArchiveSha256", "forgeSourceArchiveSha256", "forgeSourceArchive", "javaArchiveSha256"):
                if new_sources.get(key) != old_sources.get(key):
                    raise ValueError("Upgrade changed preserved runtime: " + key)
    elif after["configSha256"] != config_sha:
        raise ValueError("Initial configuration changed during installation")
    if payload and after["manifest"]["treeSha256"] != payload["treeSha256"]:
        raise ValueError("Installed runtime differs from the requested inputs")
    welcome = SMOKE.smoke(target["endpoint"], release["version"], True, False, True, after.get("protocol", "hexproof.v2"))
    write_json(report / (target["ssh"] + "-verified.json"), {"state": after, "public": welcome})


def restore(target, before, record, upload, report):
    name = target["ssh"]
    current = ssh(name, "python3", "-c",
        "from pathlib import Path; p=Path('/opt/hexproof-home/current'); print(p.resolve() if p.is_symlink() else '')").strip()
    expected = "/opt/hexproof-home/releases/" + record["releaseId"]
    if current == expected:
        # Deterministic installer record also recovers an activation whose SSH reply was lost.
        rollback = "/var/lib/hexproof-home/deployments/" + record["releaseId"] + ".before/rollback.json"
        result = json.loads(ssh(name, "sudo", "-n", "python3", upload + "/install.py",
                                     "--rollback", rollback, "--activate"))
        write_json(report / (name + "-rollback.json"), result)
    elif current != (before["current"] or ""):
        raise ValueError("Refusing to roll back an unrelated current tree on " + name)
    if before["current"] is None:
        # Initial-install rollback stops its units and removes live config/unit
        # files; inert artifacts remain available for diagnosis, never auto-erased.
        ssh(name, "sh", "-c", "! systemctl is-active --quiet hexproof-home-hub.service && "
            "! systemctl is-active --quiet hexproof-home-node.service")
        print(name + ": failed initial installation stopped; evidence retained", flush=True)
        return
    recovered = inspect(target)
    for key in ("current", "manifestSha256", "configSha256", "unitHashes"):
        if recovered[key] != before[key]:
            raise ValueError("Rollback did not restore baseline on " + name + ": " + key)
    SMOKE.smoke(target["endpoint"], before["version"], True, False, True, recovered.get("protocol", "hexproof.v1"))
    print(name + ": previous release restored and verified", flush=True)


def cleanup(target, upload):
    ssh(target["ssh"], "python3", "-c",
        "import pathlib,shutil,sys; p=pathlib.Path(sys.argv[1]); "
        "assert p.parent==pathlib.Path('/var/tmp') and p.name.startswith('hexproof-release-') and not p.is_symlink(); "
        "shutil.rmtree(p) if p.exists() else None", upload)


def rollout(targets, release, report, verify_only=False, inputs=None, allow_active_rooms=False):
    before, prepared, uploads, attempted = {}, {}, {}, []
    changed, configs, payloads = [], {}, {}
    if verify_only and inputs is not None:
        raise ValueError("Read-only verification does not accept installation inputs")
    if verify_only and allow_active_rooms:
        raise ValueError("Read-only verification does not accept active-room interruption")
    try:
        write_json(report / "interruption-policy.json", {
            "allowActiveRooms": allow_active_rooms, "targets": [node["ssh"] for node in targets]})
        if allow_active_rooms:
            print("Owner-authorized interruption of rooms on: " + ", ".join(node["ssh"] for node in targets), flush=True)
        # Inspect every target before creating staging files on any target.
        for target in targets:
            name = target["ssh"]
            state = before[name] = inspect(target)
            if state["system"] != "Linux" or state["machine"] != {"amd64": "x86_64", "arm64": "aarch64"}[target["arch"]]:
                raise ValueError("Target operating system or architecture mismatch: " + name)
            write_json(report / (name + "-before.json"), state)
            artifact = release["artifacts"][target["arch"]]
            if state["current"] is None:
                if not verify_only:
                    if inputs is None:
                        raise ValueError("First installation requires HEXPROOF_HOME_INPUTS: " + name)
                    configs[name] = initial_config(inputs, target)
            elif tuple(map(int, release["version"].split("."))) < tuple(map(int, state["version"].split("."))):
                raise ValueError("Refusing a version downgrade on " + name + "; use the reviewed rollback procedure")
            if matches(state, artifact, release["version"]) and inputs is None:
                verify_installed(target, state, artifact, release, report)
                print(name + ": verified current release; no upload, room or restart", flush=True)
            else:
                changed.append(target)
        if verify_only and changed:
            raise ValueError("Release not installed on: " + ", ".join(node["ssh"] for node in changed))
        if inputs is not None:
            payloads = build_payloads(inputs, release, changed, report)
        for target in changed:
            if before[target["ssh"]]["current"] is not None and not allow_active_rooms:
                assert_idle(target, before[target["ssh"]]["version"])
        for target in changed:
            name = target["ssh"]
            uploads[name] = "/var/tmp/hexproof-release-" + uuid.uuid4().hex
            write_json(report / "uploads.json", uploads)
            prepared[name] = stage(target, before[name], release["artifacts"][target["arch"]],
                release, uploads[name], report,
                **({"payload": payloads[target["arch"]], "config": configs.get(name)} if payloads else {}))
        for target in changed:
            name = target["ssh"]
            unchanged_baseline(before[name], inspect(target))
            record, staged = prepared[name]
            if not staged[1].get("unchanged"):
                attempted.append(target)
            activate(target, record, staged, release["version"], report, allow_active_rooms=allow_active_rooms)
            verify_installed(target, before[name], release["artifacts"][target["arch"]], release, report,
                payload=payloads.get(target["arch"]), config_sha=staged[1].get("configSha256"))
        activated = [node["ssh"] for node in changed if not prepared[node["ssh"]][1][1].get("unchanged")]
        result = {"version": release["version"], "activated": activated,
                  "unchanged": [node["ssh"] for node in targets if node["ssh"] not in activated], "verifyOnly": verify_only}
        write_json(report / "result.json", result)
        print(json.dumps(result), flush=True)
        return result
    except BaseException as error:
        failures = []
        for target in reversed(attempted):
            name = target["ssh"]
            try:
                restore(target, before[name], prepared[name][0], uploads[name], report)
            except Exception as rollback_error:
                failures.append(name + ": " + str(rollback_error))
        write_json(report / "failure.json", {"error": str(error), "rollbackErrors": failures})
        if failures:
            raise RuntimeError("Deployment failed; rollback needs attention: " + "; ".join(failures)) from error
        raise
    finally:
        # Keep failed-run uploads to support recovery with exactly the same installer.
        if (report / "result.json").exists():
            cleanup_errors = []
            for target in changed:
                try:
                    cleanup(target, uploads[target["ssh"]])
                except Exception as error:
                    cleanup_errors.append(target["ssh"] + ": " + str(error))
            write_json(report / "cleanup.json", {"errors": cleanup_errors})
            if cleanup_errors:
                print("Deployment verified; upload cleanup needs attention: " + "; ".join(cleanup_errors), file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="ClayStan404/hexproof")
    parser.add_argument("--version")
    parser.add_argument("--targets", nargs="+", required=True)
    parser.add_argument("--arch", choices=("amd64", "arm64"))
    parser.add_argument("--allow-draft", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--allow-active-rooms", action="store_true",
                        help="Owner-authorized interruption of existing rooms during activation")
    parser.add_argument("--inputs", type=Path, help="Verified Forge/Java archives and private initial node configs")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/home-deploy")
    args = parser.parse_args()
    version = args.version.removeprefix("v") if args.version else None
    if version is not None and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        parser.error("Release version must use MAJOR.MINOR.PATCH")
    if args.allow_draft and not version:
        parser.error("Draft deployment requires an explicit version")
    if args.allow_active_rooms and (args.verify_only or not version):
        parser.error("Active-room interruption requires an explicit version and cannot be read-only")
    if args.inputs and (args.verify_only or not version):
        parser.error("Installation inputs require an explicit version and cannot be read-only")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        parser.error("Invalid GitHub repository slug")
    try:
        nodes = operator_config.load_nodes()
        names = [operator_config.home_name(name, nodes) for name in args.targets]
    except (ValueError, OSError) as error:
        parser.error(str(error))
    if len(set(names)) != len(names) or any(name not in nodes for name in names):
        parser.error("Unknown or duplicate home deployment target")
    targets = [nodes[name] for name in names]
    # load_nodes() validates aliases for every caller, including dotted aliases.
    if args.arch and any(node["arch"] != args.arch for node in targets):
        parser.error("Forced architecture does not match the selected home targets")
    inputs = json.loads(args.inputs.read_text()) if args.inputs else None
    args.cache = args.cache.resolve()
    args.cache.mkdir(parents=True, exist_ok=True)
    with (args.cache / "deployment.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        runs = args.cache / "runs"
        runs.mkdir(exist_ok=True)
        report = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S") + "-release-", dir=runs))
        print("Evidence: " + str(report), flush=True)
        release = fetch_release(args.repo, version, args.allow_draft, {node["arch"] for node in targets}, report)
        rollout(targets, release, report, args.verify_only, inputs=inputs, allow_active_rooms=args.allow_active_rooms)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit("Home release deployment failed: " + str(error))
