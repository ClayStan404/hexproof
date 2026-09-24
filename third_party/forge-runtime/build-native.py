#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Build a local native Forge runtime from the pinned official source.

The default development build references checked-out card resources. The release
packager requests a clean build with copied resources and source-backed dependencies.
No Manabrew classes or custom cost/legality controller enter the classpath.
"""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import quote


# Dynamic imports must not alter a preserved corresponding-source tree.
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
HOST = HERE / "native-host"


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def git(source, *args):
    return subprocess.check_output(
        ["git", "-C", str(source), *args], text=True
    ).strip()


def dependency_jars(report, source):
    paths = [Path(value) for value in re.findall(
        r":(/[^\n]+?\.jar)(?:\s|$)", report.read_text()
    )]
    gui = sorted((source / "forge-gui/target").glob("forge-gui-*.jar"))
    gui = [path for path in gui if not path.name.endswith(
        ("-sources.jar", "-tests.jar", "-javadoc.jar", "-jar-with-dependencies.jar")
    )]
    if len(gui) != 1:
        raise ValueError("Expected exactly one Forge GUI reactor artifact")
    paths.extend(gui)
    if not paths or any(not path.is_file() for path in paths):
        raise ValueError("Incomplete official Forge runtime dependency report")
    if any("harness" in path.name.lower() or "manabrew" in path.name.lower() for path in paths):
        raise ValueError("A Manabrew harness must not enter the native classpath")
    return list(dict.fromkeys(path.resolve() for path in paths))


def prepare_patch(source, upstream):
    """Accept only the reviewed complete delta; never reset an existing tree."""
    if git(source, "diff", "--cached") or git(source, "ls-files", "--others", "--exclude-standard"):
        raise ValueError("Forge source has staged or untracked work; preserve it and choose another checkout")
    delta = subprocess.check_output([
        "git", "-C", str(source), "diff", "--no-ext-diff", "--no-textconv", "--binary",
        "--full-index", "--no-color", "--src-prefix=a/", "--dst-prefix=b/", "HEAD"
    ])
    metadata = upstream.get("patch")
    if metadata is None:
        if delta:
            raise ValueError("Official Forge source has unreviewed changes")
        return []
    name = metadata["file"]
    if Path(name).name != name or not name.endswith(".patch"):
        raise ValueError("Invalid native patch filename")
    patch = HOST / name
    content = patch.read_bytes()
    if hashlib.sha256(content).hexdigest() != metadata["sha256"]:
        raise ValueError("Native Forge patch checksum differs from upstream.json")
    if delta and delta != content:
        raise ValueError("Forge source differs from the reviewed native patch; preserve it")
    if not delta:
        if git(source, "status", "--short"):
            raise ValueError("Forge source changed before patch application; preserve it")
        run("git", "-C", source, "apply", "--check", patch)
        run("git", "-C", source, "apply", patch)
    run("git", "-C", source, "apply", "--reverse", "--check", patch)
    return [metadata]


def manifest_line(key, value):
    # JAR manifests use a leading space on continuation lines. Artifact paths
    # are URL encoded before reaching this function, so wrapping ASCII is safe.
    remaining = f"{key}: {value}"
    lines = []
    while len(remaining) > 70:
        lines.append(remaining[:70])
        remaining = " " + remaining[70:]
    return "\r\n".join([*lines, remaining]) + "\r\n"


def packaging():
    spec = importlib.util.spec_from_file_location("forge_source_package", HERE / "source-package.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build(source, output, upstream, *, standalone=False, preserved=None):
    for command in (("git",) if preserved is None else ()) + ("mvn", "java", "javac", "jar"):
        if shutil.which(command) is None:
            raise ValueError(f"Missing build dependency: {command}")
    if preserved is None and not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        run("git", "init", source)
        run("git", "-C", source, "remote", "add", "origin", upstream["repository"])
        run("git", "-C", source, "fetch", "--depth=1", "origin", upstream["revision"])
        # Only a new checkout is switched; existing source is always read-only
        # to Git operations and must already match the reviewed official pin.
        if git(source, "status", "--short") or git(source, "diff", "--cached"):
            raise ValueError("New source checkout contains unexpected changes")
        run("git", "-C", source, "checkout", "--detach", upstream["revision"])
    if preserved is None:
        if git(source, "rev-parse", "HEAD") != upstream["revision"]:
            raise ValueError("Source revision differs from native-host/upstream.json")
        patches = prepare_patch(source, upstream)
    else:
        packaging().verify_bundle(preserved, HERE)
        patches = [upstream["patch"]]
    output.mkdir(parents=True, exist_ok=True)
    report = source / "target/hexproof-native-dependencies.txt"
    run("mvn", "-B", "-pl", "forge-gui", "-am", *(("clean",) if standalone else ()), "package",
        "org.apache.maven.plugins:maven-dependency-plugin:3.1.2:list",
        "-DskipTests", "-DincludeScope=runtime", "-DoutputAbsoluteArtifactFilename=true",
        f"-DoutputFile={report}", "-DappendOutput=false", "-Dsort=true", cwd=source)
    if standalone:
        report = packaging().replace_xmlpull(source, HERE, output / "source-downloads", report, preserved)
    jars = dependency_jars(report, source)
    stage = Path(tempfile.mkdtemp(prefix="runtime-", dir=output))
    classes = stage / "classes"
    classes.mkdir()
    # Compile exactly the source copied into provenance, even if the workspace
    # adapter is edited while this package is being built.
    frozen_host = stage / "host-source"
    shutil.copytree(HOST, frozen_host, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    if json.loads((frozen_host / "upstream.json").read_text()) != upstream:
        raise ValueError("Native pin changed during the build; rerun after edits finish")
    java_sources = sorted((frozen_host / "src/main/java").rglob("*.java"))
    if not java_sources:
        raise ValueError("Native host source is missing")
    run("javac", "--release", "21", "-encoding", "UTF-8", "-cp", os.pathsep.join(map(str, jars)),
        "-d", classes, *java_sources)
    shutil.copytree(frozen_host / "src/main/resources", classes, dirs_exist_ok=True)
    libraries = stage / "lib"
    libraries.mkdir()
    artifacts = []
    dependencies = {entry["binary"].resolve(): entry for entry in packaging().parse_dependencies(report)} if standalone else {}
    for jar in jars:
        with jar.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        name = digest[:16] + "-" + jar.name
        destination = libraries / name
        shutil.copy2(jar, destination)
        record = {"path": "lib/" + name, "sha256": digest}
        if standalone:
            dependency = dependencies.get(jar)
            record["source"] = ({key: dependency[key] for key in
                ("groupId", "artifactId", "version", "classifier")} if dependency else "forge")
        artifacts.append(record)
    manifest = stage / "MANIFEST.MF"
    manifest.write_bytes((
        manifest_line("Manifest-Version", "1.0")
        + manifest_line("Main-Class", upstream["mainClass"])
        + manifest_line("Class-Path", " ".join(quote(item["path"]) for item in artifacts))
        + "\r\n"
    ).encode("ascii"))
    run("jar", "--create", "--file", stage / "forge-harness.jar", "--manifest", manifest,
        "-C", classes, ".")
    if standalone:
        shutil.copytree(source / "forge-gui/res", stage / "forge-gui/res", symlinks=True)
        packaging().inventory(stage / "forge-gui")
    else:
        (stage / "forge-gui").symlink_to(source / "forge-gui", target_is_directory=True)
    shutil.copy2(report, stage / "resolved-dependencies.txt")
    shutil.copy2(source / "LICENSE", stage / "FORGE-LICENSE")
    with (stage / "forge-harness.jar").open("rb") as stream:
        host_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    provenance = {**upstream, "corePatches": patches, "developmentOnly": not standalone,
                  **({"resourceSource": str(source)} if not standalone else {}), "artifacts": artifacts,
                  "hostArtifact": {"path": "forge-harness.jar", "sha256": host_digest}}
    (stage / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    tests = sorted((frozen_host / "src/test/java").rglob("*.java"))
    if tests:
        test_classes = stage / "test-classes"
        test_classes.mkdir()
        runtime_classpath = os.pathsep.join(map(str, [stage / "forge-harness.jar", *libraries.glob("*.jar")]))
        run("javac", "-encoding", "UTF-8", "-cp", runtime_classpath, "-d", test_classes, *tests)
        profile = stage / "test-profile"
        profile.mkdir()
        scenarios = [(name, []) for name in (
            "NativeProfileRegressionTest", "NativeSnapshotRegressionTest", "NativeAiRegressionTest",
            "NativeEldraziRegressionTest", "NativeDeckRegistrationRegressionTest", "NativeIsolationRegressionTest",
            "NativePrintingAliasRegressionTest",
            "NativeStartFailureRegressionTest", "NativeReplayRegressionTest",
            "NativeOrderingRegressionTest", "NativeDelayedRevealRegressionTest",
            "NativeLethalDamageRegressionTest", "NativeMultiBlockRegressionTest",
            "NativeStartingHandRegressionTest", "NativeAutoPayRegressionTest", "NativeMulliganRegressionTest", "NativeObjectDepartureRegressionTest",
            "NativeSynchronousConcedeRegressionTest", "NativeQueuedInputRegressionTest",
            "NativePriorityRegressionTest", "NativePromptContextRegressionTest", "NativeCardTextRegressionTest",
            "NativePromptPrintingRegressionTest", "NativeTurnAccessRegressionTest")]
        scenarios += [("NativeCallbackRegressionTest", [scenario])
                      for scenario in ("scry", "generic", "damage", "damage_unordered", "damage_single_defender",
                                       "damage_deathtouch", "damage_skip", "phyrexian")]
        scenarios += [("NativeMechanicsRegressionTest", [scenario]) for scenario in (
            "counter-first", "counter-second", "counter-cancel", "needle", "mage",
            "chord", "discard-cancel", "discard-two", "optional-card-batch", "shared-type-incremental",
            "discard-unless-creature", "discard-unless-two", "end-turn-cleanup", "dungeon-options",
            "discard-unless-artifact", "discard-artifact-two", "discard-artifact-undo",
            "frog-pay", "frog-cancel", "crew-pay", "crew-cancel", "waterbend-cap",
            "bolt-resolution", "counterspell-resolution", "counter-counterspell")]
        scenarios += [("NativeImproviseRegressionTest", [scenario])
                      for scenario in ("selection", "cancel-retry", "convoke-cancel")]
        scenarios += [("NativeCardStateRegressionTest", [scenario])
                      for scenario in ("annotations", "labyrinth", "class-level", "chosen-card")]
        for test, arguments in scenarios:
            run("java", "-Xmx2g", "-Djava.awt.headless=true", f"-Duser.home={profile}",
                "-cp", str(test_classes) + os.pathsep + runtime_classpath,
                "org.hexproof.forge." + test, stage / "forge-gui", *arguments)
    if standalone:
        packaging().verify_xmlpull_api(HERE, os.pathsep.join(str(path) for path in libraries.glob("*.jar")))
        run("javac", "--release", "21", "-cp", runtime_classpath, "-d", test_classes,
            HERE / "XmlDependencyRegressionTest.java")
        run("java", "-cp", str(test_classes) + os.pathsep + runtime_classpath,
            "XmlDependencyRegressionTest")
    return stage


def main():
    upstream = json.loads((HOST / "upstream.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        default=ROOT / "build/forge-native" / ("source-" + upstream["revision"]))
    parser.add_argument("--output", type=Path, default=ROOT / "build/forge-native")
    args = parser.parse_args()
    try:
        print(build(args.source.resolve(), args.output.resolve(), upstream))
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Native Forge build failed: {error}\n")


if __name__ == "__main__":
    main()
