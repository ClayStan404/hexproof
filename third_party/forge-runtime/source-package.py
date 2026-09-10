#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Preserve exact runtime sources locally, with checked third-party source payloads."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile


MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2/"
BUILD_FILES = ("build.sh", "build-harness.sh", "source-package.py", "README.md",
               "SOURCE-README.md", "VERSIONS.env", "dependency-sources.json",
               "XmlDependencyRegressionTest.java")
SCHEMA_VERSION = 1


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_versions(path):
    values = {}
    for line in path.read_text().splitlines():
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    for key in ("MANABREW_REVISION", "FORGE_REVISION"):
        if not re.fullmatch(r"[a-f0-9]{40}", values.get(key, "")):
            raise ValueError(f"Invalid {key}")
    if not re.fullmatch(r"[1-9][0-9]*", values.get("HEXPROOF_FORGE_PATCH_REVISION", "")):
        raise ValueError("Invalid HEXPROOF_FORGE_PATCH_REVISION")
    return values


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
    archives = upstream_archives(build_tools, cache, preserved)
    xmlpull_record, xmlpull_archive = next((record, path) for record, path in archives if record["id"] == "xmlpull-api")
    module = source / "target/hexproof-xmlpull-api"
    java_sources = module / "src/main/java/org/xmlpull/v1"
    java_sources.mkdir(parents=True, exist_ok=True)
    licenses = module / "src/main/resources/META-INF"
    licenses.mkdir(parents=True, exist_ok=True)
    api = json.loads((build_tools / "dependency-sources.json").read_text())["xmlpullApiCompatibility"]
    with tarfile.open(xmlpull_archive) as archive:
        for name in api["classes"]:
            member = f"{xmlpull_record['root']}/src/java/api/org/xmlpull/v1/{name}.java"
            (java_sources / f"{name}.java").write_bytes(archive.extractfile(member).read())
        (licenses / "LICENSE-XMLPULL.txt").write_bytes(
            archive.extractfile(f"{xmlpull_record['root']}/LICENSE.txt").read())
    (module / "pom.xml").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!-- Original XMLPull 1.1.3.4b API, built from the archived official source.
     Not the source-unavailable 1.1.3.4a binary; no parser is replaced. -->
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>forge</groupId><artifactId>forge</artifactId><version>${{revision}}</version>
    <relativePath>../../forge/pom.xml</relativePath>
  </parent>
  <artifactId>hexproof-xmlpull-api</artifactId>
  <name>XMLPull 1.1.3.4b API (Hexproof source build)</name>
  <licenses><license><name>Public Domain (original XMLPull API notice)</name>
    <url>https://github.com/xmlpull-org/xmlpull-api-v1/blob/{xmlpull_record['revision']}/LICENSE.txt</url>
  </license></licenses>
  <build><plugins><plugin>
    <artifactId>maven-checkstyle-plugin</artifactId><configuration><skip>true</skip></configuration>
  </plugin></plugins></build>
</project>
''')


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


def inventory(root):
    records = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == "SOURCE-MANIFEST.json":
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


def archive_tree(root, output, epoch):
    """Stable ordering, times, owners and gzip header; source archives are reproducible."""
    with output.open("wb") as stream:
        with gzip.GzipFile(filename="", fileobj=stream, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for path in [root, *sorted(root.rglob("*"))]:
                    info = archive.gettarinfo(str(path), str(Path(root.name) / path.relative_to(root)))
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
    versions = read_versions(build_tools / "VERSIONS.env")
    if manifest["schemaVersion"] != SCHEMA_VERSION or manifest["versions"] != versions:
        raise ValueError("Source package version does not match the requested runtime")
    if manifest["files"] != inventory(root):
        raise ValueError("Source package inventory/checksum mismatch")
    if (root / "hexproof-build/patches/manifest.json").read_bytes() != (build_tools / "patches/manifest.json").read_bytes():
        raise ValueError("Source package downstream patch manifest mismatch")
    return manifest


def check_dependencies(root, dependency_file):
    expected = json.loads((root / "SOURCE-MANIFEST.json").read_text())["runtimeDependencies"]
    def identity(entry):
        return tuple(entry[key] for key in ("groupId", "artifactId", "version", "classifier"))
    actual = {identity(entry): sha256(entry["binary"]) for entry in parse_dependencies(dependency_file)}
    locked = {identity(entry): entry["binarySha256"] for entry in expected}
    if actual != locked:
        raise ValueError("Rebuilt runtime dependency graph/checksums differ from the source package")


def create(source, build_tools, output, dependency_file):
    versions = read_versions(build_tools / "VERSIONS.env")
    patch_arguments = [str(source), versions["MANABREW_REVISION"], versions["FORGE_REVISION"],
                       versions["HEXPROOF_FORGE_PATCH_REVISION"]]
    subprocess.run(["node", str(build_tools / "patches/manage-source.mjs"), "apply", *patch_arguments], check=True)
    epoch = int(git(source, "show", "-s", "--format=%ct", versions["MANABREW_REVISION"]))
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="source-stage.", dir=output) as temporary:
        root = Path(temporary) / "hexproof-forge-source"
        export_tree(source, versions["MANABREW_REVISION"], root / "manabrew")
        export_tree(source / "forge", versions["FORGE_REVISION"], root / "manabrew/forge")
        for name in git(source, "diff", "--name-only", "HEAD").splitlines():
            target = root / "manabrew" / name
            if (source / name).exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source / name, target)
            else:
                target.unlink()
        # The build has just regenerated these from the pinned Rust types. Keep
        # the generated inputs too, so rebuilding Java does not require Cargo.
        shutil.copytree(source / "src/protocol", root / "manabrew/src/protocol", dirs_exist_ok=True)
        tools = root / "hexproof-build"
        tools.mkdir()
        for name in BUILD_FILES:
            shutil.copy2(build_tools / name, tools / name)
        shutil.copytree(build_tools / "patches", tools / "patches")
        shutil.copy2(build_tools / "SOURCE-README.md", root / "README.md")
        dependencies = collect_dependencies(parse_dependencies(dependency_file), root, output / "source-downloads")
        extra_sources = []
        for record, path in upstream_archives(build_tools, output / "source-downloads"):
            destination = root / "third-party/upstream" / record["archive"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            extra_sources.append({**record, "path": destination.relative_to(root).as_posix()})
        manifest = {"schemaVersion": SCHEMA_VERSION, "versions": versions,
                    "sourceDateEpoch": epoch, "runtimeDependencies": dependencies,
                    "upstreamSources": extra_sources,
                    "files": inventory(root)}
        (root / "SOURCE-MANIFEST.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        verify_bundle(root, build_tools)
        name = f"hexproof-forge-source-{versions['MANABREW_REVISION']}-patch{versions['HEXPROOF_FORGE_PATCH_REVISION']}.tar.gz"
        destination = output / name
        staged = Path(temporary) / name
        archive_tree(root, staged, epoch)
        staged.replace(destination)
        return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("create", "verify", "repack", "check-dependencies",
                                        "link-runtime", "prepare-dependencies", "verify-xmlpull-api"))
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build-tools", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--dependencies", type=Path)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--preserved-source", type=Path)
    args = parser.parse_args()
    if args.mode == "create":
        if args.output is None or args.dependencies is None:
            parser.error("create requires --output and --dependencies")
        print(create(args.source.resolve(), args.build_tools.resolve(), args.output.resolve(), args.dependencies))
    elif args.mode == "verify":
        if args.output is not None and args.output.resolve().is_relative_to(args.source.resolve()):
            parser.error("rebuild output must be outside the preserved source package")
        verify_bundle(args.source.resolve(), args.build_tools.resolve())
    elif args.mode == "check-dependencies":
        if args.dependencies is None:
            parser.error("check-dependencies requires --dependencies")
        check_dependencies(args.source.resolve(), args.dependencies)
    elif args.mode == "repack":
        if args.output is None:
            parser.error("repack requires --output")
        manifest = verify_bundle(args.source.resolve(), args.build_tools.resolve())
        versions = manifest["versions"]
        name = f"hexproof-forge-source-{versions['MANABREW_REVISION']}-patch{versions['HEXPROOF_FORGE_PATCH_REVISION']}.tar.gz"
        args.output.mkdir(parents=True, exist_ok=True)
        destination = args.output / name
        archive_tree(args.source.resolve(), destination, manifest["sourceDateEpoch"])
        print(destination)
    elif args.mode == "prepare-dependencies":
        if args.output is None:
            parser.error("prepare-dependencies requires --output for its source cache")
        prepare_dependencies(args.source.resolve(), args.build_tools.resolve(), args.output.resolve(),
                             args.preserved_source)
    elif args.mode == "verify-xmlpull-api":
        verify_xmlpull_api(args.build_tools.resolve(), args.source.resolve())
    else:
        if args.runtime is None:
            parser.error("link-runtime requires --runtime")
        record = {"schemaVersion": SCHEMA_VERSION, "archive": args.source.name,
                  "sha256": sha256(args.source),
                  "versions": read_versions(args.build_tools / "VERSIONS.env")}
        (args.runtime / "SOURCE.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        shutil.copy2(args.build_tools / "SOURCE-README.md", args.runtime / "SOURCE-README.md")
        with tarfile.open(args.source) as archive:
            source_manifest = json.load(archive.extractfile("hexproof-forge-source/SOURCE-MANIFEST.json"))
            (args.runtime / "DEPENDENCIES.json").write_text(json.dumps({
                "runtimeDependencies": source_manifest["runtimeDependencies"],
                "upstreamSources": source_manifest["upstreamSources"],
            }, indent=2, sort_keys=True) + "\n")
            for dependency in source_manifest["runtimeDependencies"]:
                for name in dependency.get("notices", []):
                    relative = Path(name).relative_to("third-party/notices")
                    if ".." in relative.parts:
                        raise ValueError("Unsafe source package notice path")
                    destination = args.runtime / "THIRD-PARTY-LICENSES" / relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(archive.extractfile("hexproof-forge-source/" + name).read())


if __name__ == "__main__":
    main()
