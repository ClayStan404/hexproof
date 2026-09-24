#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Resolve a verified local native Forge runtime without replacing old packages."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import unquote
import zipfile


ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "third_party/forge-runtime/native-host"
INDEX = ROOT / "build/forge-native/local-runtime.json"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_object(path):
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args], stderr=subprocess.PIPE)


def validate(candidate, expected):
    for resource in ("forge-harness.jar", "forge-gui/res/languages/en-US.properties",
                     "forge-gui/res/deckgendecks/Standard.raw.dat"):
        if not (candidate / resource).is_file():
            raise ValueError(f"Native runtime is missing {resource}: {candidate}")
    if not (candidate / "forge-gui/res/cardsfolder").is_dir():
        raise ValueError(f"Native card resources are missing: {candidate}")
    provenance = read_object(candidate / "provenance.json")
    if any(provenance.get(key) != value for key, value in expected.items()):
        raise ValueError(f"Native runtime provenance differs from upstream.json: {candidate}")
    if read_object(candidate / "host-source/upstream.json") != expected:
        raise ValueError(f"Packaged native pin differs from upstream.json: {candidate}")
    patches = [expected["patch"]] if expected.get("patch") else []
    if provenance.get("corePatches") != patches or (provenance.get("developmentOnly") is not True
            and provenance.get("developmentOnly") is not False):
        raise ValueError(f"Native runtime has unexpected patch provenance: {candidate}")
    host_artifact = provenance.get("hostArtifact")
    if not isinstance(host_artifact, dict) or host_artifact.get("path") != "forge-harness.jar":
        raise ValueError("Native runtime host artifact provenance is missing or invalid")
    if digest(candidate / "forge-harness.jar") != host_artifact.get("sha256"):
        raise ValueError("Native host JAR checksum mismatch")
    java_root = HOST / "src/main/java"
    current = {path.relative_to(java_root): path.read_bytes() for path in java_root.rglob("*.java")}
    bundled_root = candidate / "host-source/src/main/java"
    bundled = {path.relative_to(bundled_root): path.read_bytes() for path in bundled_root.rglob("*.java")}
    if not current or current != bundled:
        raise ValueError(f"Native host source changed since this runtime was built: {candidate}")
    resources = HOST / "src/main/resources"
    current_resources = {path.relative_to(resources): path.read_bytes()
                         for path in resources.rglob("*") if path.is_file()}
    bundled_resources = candidate / "host-source/src/main/resources"
    packaged_resources = {path.relative_to(bundled_resources): path.read_bytes()
                          for path in bundled_resources.rglob("*") if path.is_file()}
    if not current_resources or current_resources != packaged_resources:
        raise ValueError(f"Native printing resources changed since this runtime was built: {candidate}")
    with zipfile.ZipFile(candidate / "forge-harness.jar") as archive:
        for path, content in current_resources.items():
            if archive.read(path.as_posix()) != content:
                raise ValueError(f"Native printing resource differs from its source: {path}")
    if provenance["developmentOnly"] is False:
        specification = importlib.util.spec_from_file_location(
            "forge_source_package", ROOT / "third_party/forge-runtime/source-package.py")
        packager = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(packager)
        packager.validate_runtime(candidate, expected)
        return
    source = Path(provenance["resourceSource"])
    if not source.is_absolute() or (candidate / "forge-gui").resolve() != (source / "forge-gui").resolve():
        raise ValueError(f"Native resource source does not match provenance: {candidate}")
    if git(source, "rev-parse", "HEAD").decode().strip() != expected["revision"]:
        raise ValueError(f"Native resource checkout is at another revision: {source}")
    patch = b""
    if patches:
        name = expected["patch"]["file"]
        if Path(name).name != name:
            raise ValueError("Invalid native patch filename")
        patch = (HOST / name).read_bytes()
        if hashlib.sha256(patch).hexdigest() != expected["patch"]["sha256"]:
            raise ValueError("Native patch checksum differs from upstream.json")
    delta = git(source, "diff", "--no-ext-diff", "--no-textconv", "--binary", "--full-index",
                "--no-color", "--src-prefix=a/", "--dst-prefix=b/", "HEAD")
    if delta != patch or git(source, "diff", "--cached") or git(source, "ls-files", "--others", "--exclude-standard"):
        raise ValueError(f"Native resource checkout has unreviewed changes: {source}")
    artifacts = provenance.get("artifacts", [])
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError("Native runtime dependency provenance is empty")
    names = []
    for artifact in artifacts:
        if not isinstance(artifact, dict) or not isinstance(artifact.get("path"), str):
            raise ValueError("Invalid native dependency provenance")
        name = artifact["path"]
        path = Path(name)
        if path.parts[:1] != ("lib",) or len(path.parts) != 2 or path.suffix != ".jar" or name in names:
            raise ValueError("Invalid native dependency path")
        if (candidate / path).is_symlink() or digest(candidate / path) != artifact["sha256"]:
            raise ValueError(f"Native dependency checksum mismatch: {name}")
        names.append(name)
    with zipfile.ZipFile(candidate / "forge-harness.jar") as archive:
        manifest = archive.read("META-INF/MANIFEST.MF").decode().replace("\r\n", "\n").replace("\n ", "")
        fields = dict(line.split(": ", 1) for line in manifest.splitlines() if ": " in line)
        if fields.get("Main-Class") != expected["mainClass"]:
            raise ValueError("Native runtime has another main class")
        if [unquote(name) for name in fields.get("Class-Path", "").split()] != names:
            raise ValueError("Native runtime manifest differs from dependency provenance")


def build(args, expected):
    command = [sys.executable, str(ROOT / "third_party/forge-runtime/build-native.py")]
    for flag, value in (("--source", args.source), ("--output", args.output)):
        if value:
            command += [flag, str(Path(value).absolute())]
    last = ""
    process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    for line in process.stdout:
        print(line, end="", file=sys.stderr, flush=True)
        if line.strip():
            last = line.strip()
    if process.wait() != 0:
        raise ValueError("Native runtime builder failed; existing runtimes and index were preserved")
    runtime = Path(last)
    if not last or not runtime.is_absolute():
        raise ValueError("Native builder did not return an absolute runtime directory")
    validate(runtime, expected)
    return runtime


def resolve(args):
    expected = read_object(HOST / "upstream.json")
    original_index = None
    candidate = Path(args.root).absolute() if args.root else None
    if candidate is None and (INDEX.exists() or INDEX.is_symlink()):
        original_index = INDEX.read_bytes()
        index = json.loads(original_index)
        if INDEX.is_symlink() or not isinstance(index, dict) or index.get("schema") != 1 or not isinstance(index.get("runtimeRoot"), str) or not Path(index["runtimeRoot"]).is_absolute():
            raise ValueError(f"Unrecognized native runtime index; preserved: {INDEX}")
        candidate = Path(index["runtimeRoot"])
    if candidate is not None:
        try:
            validate(candidate, expected)
            return candidate
        except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
            if not args.prepare or args.root and (candidate.exists() or candidate.is_symlink()):
                raise ValueError(f"{error}\nExisting runtime preserved. Select a fresh HEXPROOF_FORGE_LOCAL_ROOT or prepare the default native index.") from error
            print(f"Preparing a new native runtime; preserving {candidate}", file=sys.stderr)
    elif not args.prepare:
        raise ValueError("No native runtime is selected. Run with --native --prepare or set HEXPROOF_FORGE_LOCAL_ROOT.")
    runtime = build(args, expected)
    if args.root:
        candidate.parent.mkdir(parents=True, exist_ok=True)
        try:
            candidate.symlink_to(runtime, target_is_directory=True)
        except FileExistsError as error:
            raise ValueError(f"Runtime destination appeared during preparation; preserved new runtime at {runtime}") from error
        return candidate
    INDEX.parent.mkdir(parents=True, exist_ok=True)
    current_index = INDEX.read_bytes() if INDEX.exists() or INDEX.is_symlink() else None
    if current_index != original_index:
        raise ValueError(f"Native runtime index changed during preparation; preserved new runtime at {runtime}")
    with tempfile.NamedTemporaryFile(mode="w", dir=INDEX.parent, prefix="local-runtime-", suffix=".json", delete=False) as stream:
        json.dump({"schema": 1, "runtimeRoot": str(runtime), "upstream": expected}, stream, indent=2)
        stream.write("\n")
        temporary = Path(stream.name)
    os.replace(temporary, INDEX)
    return runtime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--root")
    parser.add_argument("--source")
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        print(resolve(args))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Local native Forge runtime rejected: {error}\n")


if __name__ == "__main__":
    main()
