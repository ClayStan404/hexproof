#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Preserve exact runtime sources locally, with checked third-party source payloads."""

import argparse
import gzip
import fnmatch
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile


# Dynamic imports must not alter a preserved corresponding-source tree.
sys.dont_write_bytecode = True

MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2/"
BUILD_FILES = ("build.sh", "build-native.py", "source-package.py", "README.md",
               "SOURCE-README.md", "dependency-sources.json", "XmlDependencyRegressionTest.java")
SCHEMA_VERSION = 2


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_upstream(build_tools):
    upstream = json.loads((build_tools / "native-host/upstream.json").read_text())
    if (upstream.get("repository") != "https://github.com/Card-Forge/forge.git"
            or not re.fullmatch(r"[a-f0-9]{40}", upstream.get("revision", ""))
            or type(upstream.get("adapterRevision")) is not int or upstream["adapterRevision"] < 1
            or upstream.get("mainClass") != "org.hexproof.forge.NativeHost"):
        raise ValueError("Invalid official Forge upstream pin")
    metadata = upstream.get("patch", {})
    name = metadata.get("file", "")
    if (not name.endswith(".patch") or Path(name).name != name
            or sha256(build_tools / "native-host" / name) != metadata.get("sha256")):
        raise ValueError("Official Forge hook checksum mismatch")
    return upstream


def artifact_suffix(upstream):
    return f"{upstream['revision']}-adapter{upstream['adapterRevision']}"


def parse_dependencies(path):
    """Parse Maven dependency:list, including classifiers and spaces in paths."""
    dependencies = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line in ("The following files have been resolved:", "none"):
            continue
        match = re.fullmatch(r"([\w.+-]+):([\w.+-]+):jar:(?:([\w.+-]+):)?"
                             r"([\w.+-]+):(compile|runtime|system):(/.*?)(?: -- module .*)?", line)
        if not match:
            raise ValueError(f"Unrecognized resolved Maven dependency: {line}")
        group, artifact, classifier, version, scope, filename = match.groups()
        if group == "forge":
            continue
        if "SNAPSHOT" in version or not Path(filename).is_file():
            raise ValueError(f"Unpinned or missing Maven dependency: {line}")
        dependencies.append({"groupId": group, "artifactId": artifact,
                             "version": version, "classifier": classifier or "",
                             "scope": scope, "binary": Path(filename)})
    if not dependencies:
        raise ValueError("No external runtime dependencies were resolved")
    return sorted(dependencies, key=lambda entry: tuple(str(entry[key]) for key in
                  ("groupId", "artifactId", "version", "classifier")))


def download(url, destination):
    if destination.is_file():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "Hexproof-Forge-Source-Packager/1"})
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                shutil.copyfileobj(response, output)
            output.close()
            temporary.replace(destination)
        except Exception as error:
            error.add_note(f"Dependency source URL: {url}")
            raise
        finally:
            temporary.unlink(missing_ok=True)


def collect_dependencies(dependencies, root, cache):
    records = []
    for dependency in dependencies:
        group, artifact, version = (dependency[key] for key in ("groupId", "artifactId", "version"))
        base = f"{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}"
        record = {key: value for key, value in dependency.items() if key != "binary"}
        record["binarySha256"] = sha256(dependency["binary"])
        record["files"] = []
        notice_prefix = base + ("-" + dependency["classifier"] if dependency["classifier"] else "")
        record["notices"] = copy_notices(dependency["binary"], root, notice_prefix + "/binary")
        if group == "org.hexproof.thirdparty" and artifact == "xmlpull-api":
            record["sourceForm"] = "pinned-source-build"
            record["upstreamSource"] = "xmlpull-api"
            records.append(record)
            continue
        metadata_only = False
        if zipfile.is_zipfile(dependency["binary"]):
            with zipfile.ZipFile(dependency["binary"]) as archive:
                metadata_names = {"META-INF/MANIFEST.MF", "META-INF/INDEX.LIST", "META-INF/io.netty.versions.properties"}
                metadata_only = all(name.endswith("/") or name in metadata_names or
                                    (name.startswith("META-INF/maven/") and
                                     name.endswith(("/pom.xml", "/pom.properties")))
                                    for name in archive.namelist())
        record["sourceForm"] = "metadata-only" if metadata_only else "source-jar"
        if metadata_only:
            # Empty conflict-avoidance carriers (e.g. Guava listenablefuture)
            # contain no code/resources to supply. Preserve the exact inspected
            # carrier and its POM, not a fictional sources JAR or a silent gap.
            destination = root / "third-party/maven" / (base + ".jar")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(dependency["binary"], destination)
            record["files"].append({"path": destination.relative_to(root).as_posix(),
                                    "sha256": sha256(destination), "origin": MAVEN_CENTRAL + base + ".jar"})
        for suffix in ((".pom",) if metadata_only else ("-sources.jar", ".pom")):
            relative = base + suffix
            cached = cache / relative
            download(MAVEN_CENTRAL + relative, cached)
            if suffix == "-sources.jar":
                with zipfile.ZipFile(cached) as archive:
                    if archive.testzip() is not None:
                        raise ValueError(f"Corrupt source JAR: {relative}")
                record["notices"].extend(copy_notices(cached, root, notice_prefix + "/source"))
            destination = root / "third-party/maven" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(cached, destination)
            record["files"].append({"path": destination.relative_to(root).as_posix(),
                                    "sha256": sha256(destination), "origin": MAVEN_CENTRAL + relative})
        records.append(record)
    return records


def copy_notices(jar, root, prefix):
    paths = []
    if not zipfile.is_zipfile(jar):
        return paths
    with zipfile.ZipFile(jar) as archive:
        for name in sorted(archive.namelist()):
            if name.endswith("/") or not re.search(r"(^|/)(license|notice|copying)([._-].*)?$", name, re.I):
                continue
            if name.endswith((".class", ".jar", ".so", ".dll")):
                continue
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError(f"Unsafe dependency notice path: {name}")
            destination = root / "third-party/notices" / prefix / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read(name))
            paths.append(destination.relative_to(root).as_posix())
    return paths


def upstream_archives(build_tools, cache, preserved=None):
    manifest = json.loads((build_tools / "dependency-sources.json").read_text())
    records = []
    for record in manifest["archives"]:
        path = ((preserved / "third-party/upstream" / record["archive"]) if preserved else
                (cache / "upstream" / record["archive"]))
        if not preserved:
            download(record["origin"], path)
        if sha256(path) != record["sha256"]:
            raise ValueError(f"Pinned upstream dependency source checksum mismatch: {record['id']}")
        records.append((record, path))
    return records


def prepare_dependencies(source, build_tools, cache, preserved=None):
    record, archive_path = next((record, path) for record, path in
        upstream_archives(build_tools, cache, preserved) if record["id"] == "xmlpull-api")
    (source / "target").mkdir(exist_ok=True)
    module = Path(tempfile.mkdtemp(prefix="hexproof-xmlpull-api-", dir=source / "target"))
    java_sources = module / "src/main/java/org/xmlpull/v1"
    java_sources.mkdir(parents=True, exist_ok=True)
    licenses = module / "src/main/resources/META-INF"
    licenses.mkdir(parents=True, exist_ok=True)
    api = json.loads((build_tools / "dependency-sources.json").read_text())["xmlpullApiCompatibility"]
    with tarfile.open(archive_path) as archive:
        for name in api["classes"]:
            member = f"{record['root']}/src/java/api/org/xmlpull/v1/{name}.java"
            (java_sources / f"{name}.java").write_bytes(archive.extractfile(member).read())
        (licenses / "LICENSE-XMLPULL.txt").write_bytes(
            archive.extractfile(f"{record['root']}/LICENSE.txt").read())
    return module


def replace_xmlpull(source, build_tools, cache, report, preserved=None):
    """Replace the source-unavailable API JAR with four original source-built API classes."""
    module = prepare_dependencies(source, build_tools, cache, preserved)
    classes = module / "classes"
    classes.mkdir(exist_ok=True)
    subprocess.run(["javac", "--release", "8", "-encoding", "UTF-8", "-d", str(classes),
                    *map(str, sorted((module / "src/main/java").rglob("*.java")))], check=True)
    shutil.copytree(module / "src/main/resources", classes, dirs_exist_ok=True)
    binary = module / "hexproof-xmlpull-api-1.1.3.4b.jar"
    # Deterministic ZIP entries also lock the replacement's bytes on source rebuild.
    with zipfile.ZipFile(binary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(classes.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(classes).as_posix(), (2000, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
    verify_xmlpull_api(build_tools, binary)
    original = next((entry for entry in parse_dependencies(report)
                     if (entry["groupId"], entry["artifactId"], entry["version"]) ==
                     ("xmlpull", "xmlpull", "1.1.3.4a")), None)
    definition = json.loads((build_tools / "dependency-sources.json").read_text())
    if original is None or sha256(original["binary"]) != definition["xmlpullApiCompatibility"]["referenceBinarySha256"]:
        raise ValueError("Unexpected XMLPull binary selected by official Forge")
    lines = report.read_text().splitlines()
    output = module / "resolved-dependencies.txt"
    output.write_text("\n".join(
        f"   org.hexproof.thirdparty:xmlpull-api:jar:1.1.3.4b:compile:{binary}"
        if line.strip().startswith("xmlpull:xmlpull:jar:") else line for line in lines) + "\n")
    return output


def verify_xmlpull_api(build_tools, jar):
    api = json.loads((build_tools / "dependency-sources.json").read_text())["xmlpullApiCompatibility"]
    signatures = b"".join(subprocess.check_output(
        ["javap", *api["javapOptions"], "-classpath", str(jar), f"org.xmlpull.v1.{name}"])
        for name in api["classes"])
    if hashlib.sha256(signatures).hexdigest() != api["signatureSha256"]:
        raise ValueError("XMLPull public/protected API compatibility regression")


def git(directory, *arguments):
    return subprocess.check_output(["git", "-C", str(directory), *arguments], text=True).strip()


def export_tree(source, revision, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile() as archive:
        subprocess.run(["git", "-C", str(source), "archive", "--format=tar", revision],
                       stdout=archive, check=True)
        archive.seek(0)
        with tarfile.open(fileobj=archive) as contents:
            contents.extractall(destination, filter="data")


def inventory(root, exclude="SOURCE-MANIFEST.json"):
    records = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == exclude:
            continue
        if path.is_symlink():
            target = os.readlink(path)
            if os.path.isabs(target) or not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f"Source symlink escapes the archive: {relative}")
            records[relative] = {"symlink": target}
        elif path.is_dir():
            continue
        elif path.is_file():
            records[relative] = {"sha256": sha256(path), "executable": bool(path.stat().st_mode & 0o111)}
        else:
            raise ValueError(f"Unsupported source entry: {relative}")
    return records


def archive_tree(root, output, epoch, root_name=None):
    """Stable ordering, times, owners and gzip header; source archives are reproducible."""
    with output.open("wb") as stream:
        with gzip.GzipFile(filename="", fileobj=stream, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path in [root, *sorted(root.rglob("*"))]:
                    info = archive.gettarinfo(str(path), str(Path(root_name or root.name) / path.relative_to(root)))
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = epoch
                    info.pax_headers = {}
                    if info.isfile():
                        with path.open("rb") as payload:
                            archive.addfile(info, payload)
                    else:
                        archive.addfile(info)


def verify_bundle(root, build_tools):
    manifest = json.loads((root / "SOURCE-MANIFEST.json").read_text())
    upstream = read_upstream(build_tools)
    if manifest.get("schemaVersion") != SCHEMA_VERSION or manifest.get("upstream") != upstream:
        raise ValueError("Source package version does not match the requested runtime")
    if manifest.get("files") != inventory(root):
        raise ValueError("Source package inventory/checksum mismatch")
    bundled = root / "hexproof-build"
    if read_upstream(bundled) != upstream:
        raise ValueError("Source package native hook mismatch")
    for name in BUILD_FILES:
        if (bundled / name).read_bytes() != (build_tools / name).read_bytes():
            raise ValueError(f"Source package build tool differs: {name}")
    if host_inventory(bundled / "native-host") != host_inventory(build_tools / "native-host"):
        raise ValueError("Source package native host source differs")
    if not (root / "forge/pom.xml").is_file() or not (root / "forge/LICENSE").is_file():
        raise ValueError("Source package lacks the official Forge tree")
    coordinates = {":".join(entry[key] for key in ("groupId", "artifactId", "version"))
                   for entry in manifest["runtimeDependencies"]}
    definitions = json.loads((build_tools / "dependency-sources.json").read_text())["archives"]
    required = [{**record, "path": "third-party/upstream/" + record["archive"]} for record in definitions
                if any(fnmatch.fnmatchcase(coordinate, record.get("requiredBy", record["coordinate"]))
                       for coordinate in coordinates)]
    if manifest["upstreamSources"] != required:
        raise ValueError("Required pinned upstream source archives are incomplete or differ")
    for entry in manifest["runtimeDependencies"]:
        if entry.get("sourceForm") not in ("pinned-source-build", "source-jar", "metadata-only"):
            raise ValueError("Unsupported runtime dependency source form")
        paths = [record["path"] for record in entry.get("files", [])]
        if entry["sourceForm"] == "source-jar" and (not any(name.endswith("-sources.jar") for name in paths)
                or not any(name.endswith(".pom") for name in paths)):
            raise ValueError("Runtime dependency lacks a source JAR or POM")
        if entry["sourceForm"] == "metadata-only" and (not any(name.endswith(".jar") for name in paths)
                or not any(name.endswith(".pom") for name in paths)):
            raise ValueError("Runtime metadata dependency lacks its carrier or POM")
        if entry["sourceForm"] == "pinned-source-build":
            if not any(record["id"] == entry["upstreamSource"] for record in manifest["upstreamSources"]):
                raise ValueError("Runtime dependency lacks complete pinned source")
        elif not entry.get("files"):
            raise ValueError("Runtime dependency lacks locally preserved source")
        for record in entry.get("files", []):
            if sha256(safe_path(root, record["path"])) != record["sha256"]:
                raise ValueError("Runtime dependency source checksum mismatch")
    for record in manifest["upstreamSources"]:
        if sha256(safe_path(root, record["path"])) != record["sha256"]:
            raise ValueError("Pinned upstream source checksum mismatch")
    return manifest


def host_inventory(root):
    return {name: entry for name, entry in inventory(root).items()
            if "__pycache__" not in Path(name).parts and not name.endswith(".pyc")}


def safe_path(root, name):
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or not name:
        raise ValueError(f"Unsafe package path: {name}")
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Package path escapes its root: {name}")
    return path


def check_dependencies(root, dependency_file):
    expected = json.loads((root / "SOURCE-MANIFEST.json").read_text())["runtimeDependencies"]
    def identity(entry):
        return tuple(entry[key] for key in ("groupId", "artifactId", "version", "classifier"))
    actual = {identity(entry): sha256(entry["binary"]) for entry in parse_dependencies(dependency_file)}
    locked = {identity(entry): entry["binarySha256"] for entry in expected}
    if actual != locked:
        raise ValueError("Rebuilt runtime dependency graph/checksums differ from the source package")


def create(source, build_tools, output, dependency_file):
    upstream = read_upstream(build_tools)
    builder = load_builder(build_tools)
    if git(source, "rev-parse", "HEAD") != upstream["revision"]:
        raise ValueError("Official Forge source revision mismatch")
    builder.prepare_patch(source, upstream)
    epoch = int(git(source, "show", "-s", "--format=%ct", upstream["revision"]))
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="source-stage.", dir=output) as temporary:
        root = Path(temporary) / "hexproof-forge-source"
        export_tree(source, upstream["revision"], root / "forge")
        for name in git(source, "diff", "--name-only", "HEAD").splitlines():
            target = safe_path(root / "forge", name)
            if (source / name).is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source / name, target)
            else:
                target.unlink()
        bundled = root / "hexproof-build"
        bundled.mkdir()
        for name in BUILD_FILES:
            shutil.copy2(build_tools / name, bundled / name)
        shutil.copytree(build_tools / "native-host", bundled / "native-host",
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        shutil.copy2(build_tools / "SOURCE-README.md", root / "README.md")
        dependencies = collect_dependencies(parse_dependencies(dependency_file), root, output / "source-downloads")
        extra_sources = []
        for record, path in upstream_archives(build_tools, output / "source-downloads"):
            destination = root / "third-party/upstream" / record["archive"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            extra_sources.append({**record, "path": destination.relative_to(root).as_posix()})
        manifest = {"schemaVersion": SCHEMA_VERSION, "upstream": upstream,
                    "sourceDateEpoch": epoch, "runtimeDependencies": dependencies,
                    "upstreamSources": extra_sources, "files": inventory(root)}
        write_json(root / "SOURCE-MANIFEST.json", manifest)
        verify_bundle(root, build_tools)
        name = f"hexproof-forge-source-{artifact_suffix(upstream)}.tar.gz"
        destination = output / name
        staged = Path(temporary) / name
        archive_tree(root, staged, epoch)
        staged.replace(destination)
        return destination


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def load_builder(build_tools):
    spec = importlib.util.spec_from_file_location("native_forge_builder", build_tools / "build-native.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    return builder


def extract_archive(path, destination, expected_root):
    """Reject alternate roots, duplicate entries, special files and escaping links."""
    with tarfile.open(path) as archive:
        names = set()
        for member in archive:
            relative = Path(member.name)
            if (relative.is_absolute() or ".." in relative.parts or not relative.parts
                    or relative.parts[0] != expected_root or relative.as_posix() in names
                    or not (member.isfile() or member.isdir() or member.issym())):
                raise ValueError(f"Unsafe or duplicate archive member: {member.name}")
            names.add(relative.as_posix())
            if member.issym():
                target = Path(member.linkname)
                resolved = (destination / relative.parent / target).resolve()
                if target.is_absolute() or not resolved.is_relative_to((destination / expected_root).resolve()):
                    raise ValueError("Archive symlink escapes package")
        archive.extractall(destination, filter="data")
    root = destination / expected_root
    if not root.is_dir():
        raise ValueError("Archive has no package root")
    return root


def jar_manifest(path):
    with zipfile.ZipFile(path) as archive:
        text = archive.read("META-INF/MANIFEST.MF").decode("utf-8").replace("\r\n", "\n")
    unfolded = text.replace("\n ", "")
    return dict(line.split(": ", 1) for line in unfolded.splitlines() if ": " in line)


def seal_runtime(root, upstream):
    write_json(root / "RUNTIME-MANIFEST.json", {"schemaVersion": SCHEMA_VERSION,
        "upstream": upstream, "files": inventory(root, "RUNTIME-MANIFEST.json")})


def validate_runtime(root, expected):
    """Validate an extracted relocatable runtime; its source archive may live elsewhere."""
    root = Path(root).resolve()
    manifest = json.loads((root / "RUNTIME-MANIFEST.json").read_text())
    if manifest.get("schemaVersion") != SCHEMA_VERSION or manifest.get("upstream") != expected:
        raise ValueError("Runtime package version mismatch")
    if manifest.get("files") != inventory(root, "RUNTIME-MANIFEST.json"):
        raise ValueError("Runtime package inventory/checksum mismatch")
    if any(path.is_symlink() for path in root.rglob("*")):
        raise ValueError("Standalone runtime must not contain resource symlinks")
    provenance = json.loads((root / "provenance.json").read_text())
    if (any(provenance.get(key) != value for key, value in expected.items())
            or provenance.get("developmentOnly") is not False or "resourceSource" in provenance
            or provenance.get("corePatches") != [expected["patch"]]):
        raise ValueError("Runtime native provenance mismatch")
    host = root / "host-source"
    if json.loads((host / "upstream.json").read_text()) != expected:
        raise ValueError("Runtime copied native pin differs")
    if sha256(host / expected["patch"]["file"]) != expected["patch"]["sha256"]:
        raise ValueError("Runtime copied native hook differs")
    if not list((host / "src/main/java").rglob("*.java")):
        raise ValueError("Runtime native host source is missing")
    if provenance["hostArtifact"].get("path") != "forge-harness.jar":
        raise ValueError("Runtime host artifact path differs")
    artifacts = [provenance["hostArtifact"], *provenance["artifacts"]]
    names = [entry["path"] for entry in artifacts]
    if len(names) != len(set(names)) or set(names) != {path.relative_to(root).as_posix() for path in root.rglob("*.jar")}:
        raise ValueError("Runtime JAR classpath differs from provenance")
    for artifact in artifacts:
        path = safe_path(root, artifact["path"])
        if sha256(path) != artifact["sha256"]:
            raise ValueError("Runtime JAR checksum mismatch")
        with zipfile.ZipFile(path) as archive:
            if any(name.startswith(("forge/harness/", "org/manabrew/")) for name in archive.namelist()):
                raise ValueError("Retired harness classes in official runtime")
    main = jar_manifest(root / "forge-harness.jar")
    from urllib.parse import unquote
    if (main.get("Main-Class") != expected["mainClass"]
            or [unquote(name) for name in main.get("Class-Path", "").split()] != [entry["path"] for entry in provenance["artifacts"]]):
        raise ValueError("Runtime Java main or manifest classpath mismatch")
    for name in ("forge-gui/res/cardsfolder", "forge-gui/res/languages/en-US.properties",
                 "forge-gui/res/deckgendecks/Standard.raw.dat", "FORGE-LICENSE"):
        if not (root / name).exists():
            raise ValueError(f"Runtime resource is missing: {name}")
    source = json.loads((root / "SOURCE.json").read_text())
    if (source.get("schemaVersion") != SCHEMA_VERSION or source.get("upstream") != expected
            or source.get("archive") != f"hexproof-forge-source-{artifact_suffix(expected)}.tar.gz"
            or not re.fullmatch(r"[a-f0-9]{64}", source.get("sha256", ""))):
        raise ValueError("Runtime matching source reference is invalid")
    return provenance


def link_runtime(source_archive, runtime, build_tools):
    upstream = read_upstream(build_tools)
    write_json(runtime / "SOURCE.json", {"schemaVersion": SCHEMA_VERSION, "archive": source_archive.name,
        "sha256": sha256(source_archive), "upstream": upstream})
    shutil.copy2(build_tools / "SOURCE-README.md", runtime / "SOURCE-README.md")
    with tarfile.open(source_archive) as archive:
        manifest = json.load(archive.extractfile("hexproof-forge-source/SOURCE-MANIFEST.json"))
        write_json(runtime / "DEPENDENCIES.json", {key: manifest[key] for key in
            ("runtimeDependencies", "upstreamSources")})
        for entry in manifest["runtimeDependencies"]:
            for name in entry.get("notices", []):
                relative = Path(name).relative_to("third-party/notices")
                destination = safe_path(runtime / "THIRD-PARTY-LICENSES", str(relative))
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.extractfile("hexproof-forge-source/" + name).read())
    seal_runtime(runtime, upstream)


def verify_release(runtime_archive, source_archive, build_tools):
    upstream = read_upstream(build_tools)
    if runtime_archive.name != f"hexproof-forge-runtime-{artifact_suffix(upstream)}.tar.gz":
        raise ValueError("Runtime archive filename differs from pinned version")
    if source_archive.name != f"hexproof-forge-source-{artifact_suffix(upstream)}.tar.gz":
        raise ValueError("Source archive filename differs from pinned version")
    with tempfile.TemporaryDirectory(prefix="hexproof-forge-verify-") as temporary:
        stage = Path(temporary)
        runtime = extract_archive(runtime_archive, stage, "hexproof-forge-runtime")
        source = extract_archive(source_archive, stage, "hexproof-forge-source")
        provenance = validate_runtime(runtime, upstream)
        manifest = verify_bundle(source, build_tools)
        if json.loads((runtime / "SOURCE.json").read_text())["sha256"] != sha256(source_archive):
            raise ValueError("Runtime matching source archive checksum mismatch")
        if host_inventory(runtime / "host-source") != host_inventory(source / "hexproof-build/native-host"):
            raise ValueError("Runtime native host differs from matching source")
        if inventory(runtime / "forge-gui/res") != inventory(source / "forge/forge-gui/res"):
            raise ValueError("Runtime card resources differ from matching source")
        if (runtime / "FORGE-LICENSE").read_bytes() != (source / "forge/LICENSE").read_bytes():
            raise ValueError("Runtime Forge license differs from matching source")
        notices = {}
        for dependency in manifest["runtimeDependencies"]:
            for name in dependency.get("notices", []):
                relative = Path(name).relative_to("third-party/notices").as_posix()
                notices[relative] = sha256(safe_path(source, name))
        actual_notices = {name: entry.get("sha256") for name, entry in
            inventory(runtime / "THIRD-PARTY-LICENSES").items()} if (runtime / "THIRD-PARTY-LICENSES").exists() else {}
        if notices != actual_notices:
            raise ValueError("Runtime dependency notices differ from matching source")
        expected_dependencies = {key: manifest[key] for key in ("runtimeDependencies", "upstreamSources")}
        if json.loads((runtime / "DEPENDENCIES.json").read_text()) != expected_dependencies:
            raise ValueError("Runtime dependency source provenance differs")
        def identity(entry):
            return tuple(entry[key] for key in ("groupId", "artifactId", "version", "classifier"))
        locked = {identity(entry): entry["binarySha256"] for entry in manifest["runtimeDependencies"]}
        actual = {}
        modules = set()
        for artifact in provenance["artifacts"]:
            origin = artifact.get("source")
            if origin == "forge":
                module = next((name for name in ("forge-core", "forge-game", "forge-ai", "forge-gui")
                    if Path(artifact["path"]).name[17:].startswith(name + "-")), None)
                if module is None or module in modules or not (source / "forge" / module / "pom.xml").is_file():
                    raise ValueError("Runtime Forge reactor source provenance differs")
                modules.add(module)
            elif isinstance(origin, dict):
                key = identity(origin)
                if key in actual:
                    raise ValueError("Duplicate runtime dependency provenance")
                actual[key] = artifact["sha256"]
            else:
                raise ValueError("Runtime JAR lacks source provenance")
        if actual != locked or modules != {"forge-core", "forge-game", "forge-ai", "forge-gui"}:
            raise ValueError("Runtime dependency JAR lacks matching source provenance")
    return upstream


def cold_start(runtime, output):
    profile = output / "cold-start-profile"
    profile.mkdir()
    probe = subprocess.run(["java", "-Djava.awt.headless=true", f"-Duser.home={profile}",
        "-jar", "forge-harness.jar", "--interactive-server", "--forge-home", "forge-gui"],
        cwd=runtime, input='{"command":"reset"}\n{"command":"quit"}\n', text=True,
        capture_output=True, timeout=120)
    (output / "cold-start.stdout").write_text(probe.stdout)
    (output / "cold-start.stderr").write_text(probe.stderr)
    responses = [json.loads(line) for line in probe.stdout.splitlines() if line.startswith("{")]
    if probe.returncode or not responses or responses[0].get("ok") is not True:
        raise ValueError("Packaged runtime cold-start/reset failed")


def build_release(source, output, build_tools, preserved=None):
    upstream = read_upstream(build_tools)
    output.mkdir(parents=True, exist_ok=True)
    if preserved is not None:
        if output.resolve().is_relative_to(preserved.resolve()):
            raise ValueError("Rebuild output must be outside the preserved source package")
        manifest = verify_bundle(preserved, build_tools)
        source = Path(tempfile.mkdtemp(prefix="rebuild-source-", dir=output)) / "forge"
        shutil.copytree(preserved / "forge", source, symlinks=True)
    builder = load_builder(build_tools)
    runtime_build = builder.build(source, output, upstream, standalone=True, preserved=preserved)
    if preserved is not None:
        check_dependencies(preserved, runtime_build / "resolved-dependencies.txt")
        source_archive = output / f"hexproof-forge-source-{artifact_suffix(upstream)}.tar.gz"
        archive_tree(preserved, source_archive, manifest["sourceDateEpoch"], "hexproof-forge-source")
    else:
        source_archive = create(source, build_tools, output, runtime_build / "resolved-dependencies.txt")
        with tarfile.open(source_archive) as archive:
            manifest = json.load(archive.extractfile("hexproof-forge-source/SOURCE-MANIFEST.json"))
    stage = Path(tempfile.mkdtemp(prefix="release-stage-", dir=output))
    runtime = stage / "hexproof-forge-runtime"
    runtime.mkdir()
    for name in ("forge-harness.jar", "lib", "forge-gui", "host-source", "FORGE-LICENSE", "provenance.json"):
        item = runtime_build / name
        if item.is_dir():
            shutil.copytree(item, runtime / name, symlinks=True)
        else:
            shutil.copy2(item, runtime / name)
    link_runtime(source_archive, runtime, build_tools)
    validate_runtime(runtime, upstream)
    cold_start(runtime, stage)
    runtime_archive = output / f"hexproof-forge-runtime-{artifact_suffix(upstream)}.tar.gz"
    archive_tree(runtime, runtime_archive, manifest["sourceDateEpoch"])
    verify_release(runtime_archive, source_archive, build_tools)
    checksums = output / f"hexproof-forge-{artifact_suffix(upstream)}.sha256"
    checksums.write_text("".join(f"{sha256(path)}  {path.name}\n" for path in (runtime_archive, source_archive)))
    return runtime_archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "create", "verify", "verify-release", "check-dependencies",
                                        "verify-xmlpull-api"))
    parser.add_argument("--source", type=Path)
    parser.add_argument("--from-source", type=Path)
    parser.add_argument("--build-tools", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--dependencies", type=Path)
    parser.add_argument("--runtime", type=Path)
    args = parser.parse_args()
    build_tools = args.build_tools.resolve()
    try:
        if args.mode == "build":
            upstream = read_upstream(build_tools)
            root = build_tools.parent.parent
            source = args.source or Path(os.environ.get("HEXPROOF_FORGE_SOURCE_DIR",
                str(root / "build/forge-native" / ("source-" + upstream["revision"])) ))
            output = args.output or Path(os.environ.get("HEXPROOF_FORGE_OUTPUT_DIR", str(root / "build/forge-runtime")))
            if args.from_source and args.source:
                parser.error("--source and --from-source are mutually exclusive")
            print(build_release(source.resolve(), output.resolve(), build_tools,
                                args.from_source.resolve() if args.from_source else None))
        elif args.source is None:
            parser.error("This mode requires --source")
        elif args.mode == "verify-release":
            if args.runtime is None:
                parser.error("verify-release requires --runtime")
            verify_release(args.runtime.resolve(), args.source.resolve(), build_tools)
        elif args.mode == "verify":
            if args.output is not None and args.output.resolve().is_relative_to(args.source.resolve()):
                parser.error("rebuild output must be outside the preserved source package")
            verify_bundle(args.source.resolve(), build_tools)
        elif args.mode == "check-dependencies":
            if args.dependencies is None:
                parser.error("check-dependencies requires --dependencies")
            check_dependencies(args.source.resolve(), args.dependencies)
        elif args.mode == "verify-xmlpull-api":
            verify_xmlpull_api(build_tools, args.source)
        elif args.mode == "create":
            if args.output is None or args.dependencies is None:
                parser.error("create requires --output and --dependencies")
            print(create(args.source.resolve(), build_tools, args.output.resolve(), args.dependencies))
    except (ValueError, OSError, KeyError, tarfile.TarError, zipfile.BadZipFile,
            subprocess.CalledProcessError) as error:
        parser.exit(1, f"Forge source packaging failed: {error}\n")


if __name__ == "__main__":
    main()
