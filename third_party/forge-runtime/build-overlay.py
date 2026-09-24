#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Build the current native adapter over an immutable, source-backed Forge base.

Only JDK 21+, Python 3.12+ and Git are needed. No Maven resolution or system Java
installation is performed. Output includes all modified upstream Java sources;
release source packaging also preserves the complete pinned base source archive.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
HOST = HERE / "native-host"
BASE_MANIFEST = ROOT / "apps/server/internal/runtimepkg/manifest.json"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inputs():
    return [HOST / "upstream.json", HOST / "native-hooks.patch",
            *sorted((HOST / "src/main/java").rglob("*.java")),
            *sorted(path for path in (HOST / "src/main/resources").rglob("*") if path.is_file())]


def identity():
    upstream = json.loads((HOST / "upstream.json").read_text())
    if digest(HOST / upstream["patch"]["file"]) != upstream["patch"]["sha256"]:
        raise ValueError("Native patch differs from its reviewed checksum")
    records = {path.relative_to(HOST).as_posix(): digest(path) for path in inputs()}
    source_hash = hashlib.sha256(json.dumps(records, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    runtime_id = f'{upstream["revision"]}-adapter{upstream["adapterRevision"]}-{source_hash}'
    return runtime_id, records


def pinned_file(asset, cache, supplied=None):
    target = supplied or cache / (asset["sha256"] + ".tar.gz")
    if target.is_file() and target.stat().st_size == asset["size"] and digest(target) == asset["sha256"]:
        return target
    if supplied:
        raise ValueError(f"Supplied archive fails its pinned size/checksum: {target}")
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temporary:
        partial = Path(temporary.name)
        try:
            request = urllib.request.Request(asset["url"], headers={"User-Agent": "Hexproof-Forge-Overlay"})
            with urllib.request.urlopen(request, timeout=60) as response:
                if not response.url.startswith("https://"):
                    raise ValueError("Archive redirect must stay HTTPS")
                remaining = asset["size"] + 1
                while remaining:
                    block = response.read(min(1 << 20, remaining))
                    if not block:
                        break
                    temporary.write(block)
                    remaining -= len(block)
            temporary.flush()
            if partial.stat().st_size != asset["size"] or digest(partial) != asset["sha256"]:
                raise ValueError("Downloaded archive fails its pinned size/checksum")
        except BaseException:
            temporary.close()
            partial.unlink(missing_ok=True)
            raise
    os.replace(partial, target)
    return target


def patched_paths(patch):
    paths = re.findall(r"^diff --git a/(\S+) b/\1$", patch, re.MULTILINE)
    if not paths or any(".." in PurePosixPath(path).parts or not re.fullmatch(
            r"forge-[a-z]+/src/main/java/[A-Za-z0-9_/]+\.java", path) for path in paths):
        raise ValueError("Overlay patch must contain only named upstream Java files")
    return paths


def read_member(archive, name, maximum=4 << 20):
    member = archive.getmember(name)
    if not member.isfile() or member.size > maximum:
        raise ValueError(f"Unexpected source member: {name}")
    return archive.extractfile(member).read()


def extract_sources(source_archive, stage):
    current = (HOST / "native-hooks.patch").read_text()
    with tarfile.open(source_archive) as archive:
        old_patch = read_member(archive, "hexproof-forge-source/hexproof-build/native-host/native-hooks.patch")
        old_pin = json.loads(read_member(archive, "hexproof-forge-source/hexproof-build/native-host/upstream.json"))
        if hashlib.sha256(old_patch).hexdigest() != old_pin["patch"]["sha256"]:
            raise ValueError("Base source patch identity mismatch")
        if old_pin["revision"] != json.loads((HOST / "upstream.json").read_text())["revision"]:
            raise ValueError("Overlay must use the same official Forge revision as its base")
        names = sorted(set(patched_paths(current)) | set(patched_paths(old_patch.decode())))
        for name in names:
            target = stage / "forge" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(read_member(archive, "hexproof-forge-source/forge/" + name))
        (stage / "FORGE-LICENSE").write_bytes(read_member(archive, "hexproof-forge-source/forge/LICENSE"))
    previous = stage / "base-hooks.patch"
    previous.write_bytes(old_patch)
    # This disposable source tree is not the owner's upstream checkout.
    patch_env = {key: value for key, value in os.environ.items()
                 if key not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE")}
    patch_env["GIT_CEILING_DIRECTORIES"] = str(stage)
    for patch, reverse in ((previous, True), (HOST / "native-hooks.patch", False)):
        command = ["git", "apply", *(["--reverse"] if reverse else []), str(patch)]
        subprocess.run([*command[:2], "--check", *command[2:]], cwd=stage / "forge", env=patch_env, check=True)
        subprocess.run(command, cwd=stage / "forge", env=patch_env, check=True)
    return [stage / "forge" / name for name in names]


def extract_libraries(base_archive, stage):
    directory = stage / "lib"
    directory.mkdir()
    with tarfile.open(base_archive) as archive:
        for member in archive:
            prefix = "hexproof-forge-runtime/lib/"
            if member.name.startswith(prefix) and member.name.endswith(".jar"):
                name = member.name.removeprefix(prefix)
                if "/" in name or "\\" in name or not member.isfile() or member.size > 100 << 20:
                    raise ValueError("Unexpected base library")
                (directory / name).write_bytes(archive.extractfile(member).read())
    if not list(directory.glob("*.jar")):
        raise ValueError("Pinned base has no runtime libraries")
    return sorted(directory.glob("*.jar"))


def write_zip(destination, files):
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)


def build(args):
    runtime_id, records = identity()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    jar = output / "forge-overlay.jar"
    metadata = output / "forge-overlay.json"
    manifest = json.loads(BASE_MANIFEST.read_text())
    source_pin = json.loads((HERE / "overlay-base.json").read_text())["source"]
    if metadata.is_file() and jar.is_file():
        record = json.loads(metadata.read_text())
        if (record.get("runtimeId") == runtime_id and record.get("sha256") == digest(jar)
                and record.get("buildRecipeSha256") == digest(Path(__file__))):
            source = pinned_file(source_pin, args.cache, args.source_archive) if args.source_output else None
            return record, source
    base = pinned_file(manifest["forge"], args.cache, args.base_archive)
    source = pinned_file(source_pin, args.cache, args.source_archive)
    with tempfile.TemporaryDirectory(prefix="compile-", dir=output) as temporary:
        stage = Path(temporary)
        java = extract_sources(source, stage)
        frozen = stage / "native-host"
        shutil.copytree(HOST, frozen, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        if any(digest(frozen / name) != value for name, value in records.items()):
            raise ValueError("Native sources changed during overlay preparation; retry")
        java += sorted((frozen / "src/main/java").rglob("*.java"))
        libraries = extract_libraries(base, stage)
        classes = stage / "classes"
        classes.mkdir()
        # Argument files avoid Windows command-line length limits. Forward
        # slashes and quoted values preserve spaces without invoking a shell.
        arguments = ["--release", "21", "-encoding", "UTF-8", "-sourcepath", "",
                     "-cp", os.pathsep.join(path.as_posix() for path in libraries),
                     "-d", classes.as_posix(), *(path.as_posix() for path in java)]
        argfile = stage / "javac.args"
        argfile.write_text("\n".join(json.dumps(value) for value in arguments) + "\n")
        subprocess.run([args.javac, "@" + str(argfile)], check=True)
        record = {"schemaVersion": 1, "runtimeId": runtime_id, "baseRuntimeId": manifest["runtimeId"],
                  "baseManifestSha256": manifest["forgeManifestSha256"], "sources": records,
                  "buildRecipeSha256": digest(Path(__file__))}
        content = {path.relative_to(classes).as_posix(): path.read_bytes()
                   for path in classes.rglob("*.class")}
        resources = frozen / "src/main/resources"
        for path in resources.rglob("*"):
            if path.is_file():
                content[path.relative_to(resources).as_posix()] = path.read_bytes()
                content["META-INF/sources/native-host/" + path.relative_to(frozen).as_posix()] = path.read_bytes()
        if "org/hexproof/forge/NativeHost.class" not in content:
            raise ValueError("Overlay does not contain its native host")
        content["META-INF/hexproof-overlay.json"] = (json.dumps(record, sort_keys=True, indent=2) + "\n").encode()
        content["META-INF/FORGE-LICENSE"] = (stage / "FORGE-LICENSE").read_bytes()
        # These exact sources accompany every binary; the release source bundle
        # additionally includes the complete, hash-verified base source archive.
        for path in java:
            content["META-INF/sources/" + path.relative_to(stage).as_posix()] = path.read_bytes()
        staged_jar = stage / "forge-overlay.jar"
        write_zip(staged_jar, content)
        record["sha256"] = digest(staged_jar)
        os.replace(staged_jar, jar)
        metadata.write_text(json.dumps(record, sort_keys=True, indent=2) + "\n")
    return record, source


def package_source(destination, source):
    # Preserve the complete dependency source archive, current native sources,
    # and exact overlay build recipe. No patch-only corresponding-source claim.
    with tarfile.open(destination, "w:gz") as archive:
        archive.add(source, arcname="hexproof-forge-overlay-source/base-source.tar.gz")
        for path in [HERE / "build-overlay.py", HERE / "overlay-base.json", HERE / "OVERLAY-README.md", *inputs(),
                     *sorted((HOST / "src/test").rglob("*.java"))]:
            archive.add(path, arcname="hexproof-forge-overlay-source/third_party/forge-runtime/" + path.relative_to(HERE).as_posix())
        archive.add(BASE_MANIFEST, arcname="hexproof-forge-overlay-source/apps/server/internal/runtimepkg/manifest.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/forge-overlay")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/forge-overlay/downloads")
    parser.add_argument("--base-archive", type=Path)
    parser.add_argument("--source-archive", type=Path)
    parser.add_argument("--javac", default="javac")
    parser.add_argument("--identity", action="store_true")
    parser.add_argument("--source-output", type=Path)
    args = parser.parse_args()
    if args.identity:
        print(identity()[0])
        return
    for key in ("cache", "base_archive", "source_archive"):
        if value := getattr(args, key):
            setattr(args, key, value.resolve())
    record, source = build(args)
    if args.source_output:
        args.source_output.parent.mkdir(parents=True, exist_ok=True)
        package_source(args.source_output, source)
    print(json.dumps({key: record[key] for key in ("runtimeId", "sha256")}))


if __name__ == "__main__":
    main()
