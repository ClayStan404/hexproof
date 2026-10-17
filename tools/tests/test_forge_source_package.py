# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Source packaging tests use synthetic dependencies, never network or Maven."""

import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock
import urllib.error
import zipfile


REPO = Path(__file__).resolve().parents[2]
TOOLS = REPO / "third_party/forge-runtime"
SPEC = importlib.util.spec_from_file_location("forge_source_package", TOOLS / "source-package.py")
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


def make_fixture_trees(directory):
    """Small structurally complete pair for deploy/packager tests; no Maven/network."""
    source = directory / "hexproof-forge-source"
    runtime = directory / "hexproof-forge-runtime"
    source.mkdir(parents=True)
    runtime.mkdir()
    bundled = source / "hexproof-build"
    bundled.mkdir()
    for name in PACKAGE.BUILD_FILES:
        shutil.copy2(TOOLS / name, bundled / name)
    shutil.copytree(TOOLS / "native-host", bundled / "native-host",
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    upstream = PACKAGE.read_upstream(TOOLS)
    (source / "forge").mkdir()
    (source / "forge/pom.xml").write_text("<project/>")
    (source / "forge/LICENSE").write_text("Synthetic GPL fixture license")
    (source / "source.java").write_text("source payload")
    (source / "source-link").symlink_to("source.java")
    for name in ("forge-gui/res/cardsfolder/test.txt", "forge-gui/res/languages/en-US.properties",
                 "forge-gui/res/deckgendecks/Standard.raw.dat"):
        path = source / "forge" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("synthetic resource")
    libraries = runtime / "lib"
    libraries.mkdir()
    artifacts = []
    for module in ("forge-core", "forge-game", "forge-ai", "forge-gui"):
        (source / "forge" / module).mkdir(exist_ok=True)
        (source / "forge" / module / "pom.xml").write_text("<project/>")
        temporary = directory / (module + ".jar")
        with zipfile.ZipFile(temporary, "w") as jar:
            jar.writestr(module.replace("-", "/") + "/Fixture.class", b"synthetic class")
        digest = PACKAGE.sha256(temporary)
        name = f"lib/{digest[:16]}-{module}-1.jar"
        shutil.copy2(temporary, runtime / name)
        artifacts.append({"path": name, "sha256": digest, "source": "forge"})
    dependency = {"groupId": "org.example", "artifactId": "fixture", "version": "1", "classifier": ""}
    jar_path = runtime / "lib/fixture.jar"
    with zipfile.ZipFile(jar_path, "w") as jar:
        jar.writestr("org/example/Fixture.class", b"synthetic dependency")
    artifacts.append({"path": "lib/fixture.jar", "sha256": PACKAGE.sha256(jar_path), "source": dependency})
    payload = source / "third-party/maven/fixture-sources.jar"
    payload.parent.mkdir(parents=True)
    with zipfile.ZipFile(payload, "w") as jar:
        jar.writestr("org/example/Fixture.java", "class Fixture {}")
    pom = payload.with_name("fixture.pom")
    pom.write_text("<project/>")
    dependencies = [{**dependency, "scope": "compile", "binarySha256": PACKAGE.sha256(jar_path),
        "sourceForm": "source-jar", "notices": [], "files": [{"path": payload.relative_to(source).as_posix(),
        "sha256": PACKAGE.sha256(payload), "origin": "https://example.invalid/synthetic-sources.jar"},
        {"path": pom.relative_to(source).as_posix(), "sha256": PACKAGE.sha256(pom), "origin": "https://example.invalid/fixture.pom"}]}]
    PACKAGE.write_json(source / "SOURCE-MANIFEST.json", {"schemaVersion": PACKAGE.SCHEMA_VERSION,
        "upstream": upstream, "sourceDateEpoch": 12345, "runtimeDependencies": dependencies,
        "upstreamSources": [], "files": PACKAGE.inventory(source)})
    shutil.copytree(source / "forge/forge-gui", runtime / "forge-gui")
    shutil.copytree(bundled / "native-host", runtime / "host-source")
    shutil.copy2(source / "forge/LICENSE", runtime / "FORGE-LICENSE")
    with zipfile.ZipFile(runtime / "forge-harness.jar", "w") as jar:
        jar.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\nMain-Class: " + upstream["mainClass"]
            + "\nClass-Path: " + " ".join(entry["path"] for entry in artifacts) + "\n\n")
        jar.writestr("org/hexproof/forge/NativeHost.class", b"synthetic native host")
        resources = bundled / "native-host/src/main/resources"
        for resource in resources.rglob("*"):
            if resource.is_file():
                jar.write(resource, resource.relative_to(resources).as_posix())
    PACKAGE.write_json(runtime / "provenance.json", {**upstream, "developmentOnly": False,
        "corePatches": [upstream["patch"]], "artifacts": artifacts,
        "hostArtifact": {"path": "forge-harness.jar", "sha256": PACKAGE.sha256(runtime / "forge-harness.jar")}})
    return source, runtime


def create_release_fixture(directory):
    source, runtime = make_fixture_trees(directory)
    upstream = PACKAGE.read_upstream(TOOLS)
    suffix = PACKAGE.artifact_suffix(upstream)
    source_archive = directory / f"hexproof-forge-source-{suffix}.tar.gz"
    runtime_archive = directory / f"hexproof-forge-runtime-{suffix}.tar.gz"
    PACKAGE.archive_tree(source, source_archive, 12345)
    PACKAGE.link_runtime(source_archive, runtime, TOOLS)
    PACKAGE.archive_tree(runtime, runtime_archive, 12345)
    return runtime_archive, source_archive


class ForgeSourcePackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def dependencies(self, lines=None):
        binary = self.root / "repository with spaces/library.jar"
        binary.parent.mkdir(exist_ok=True)
        binary.write_bytes(b"compiled library")
        report = self.root / "dependencies.txt"
        report.write_text(lines or f"\nThe following files have been resolved:\n"
                          f"   org.example:library:jar:1.2.3:compile:{binary}\n"
                          f"   org.example:library:jar:linux-aarch64:1.2.3:runtime:{binary}\n")
        return report

    def bundle(self):
        source, _runtime = make_fixture_trees(self.root)
        return source

    def test_dependency_parser_preserves_classifier_and_paths_with_spaces(self):
        dependencies = PACKAGE.parse_dependencies(self.dependencies())
        self.assertEqual(len(dependencies), 2)
        self.assertEqual(dependencies[1]["classifier"], "linux-aarch64")
        self.assertEqual(dependencies[0]["version"], "1.2.3")
        self.assertIn("repository with spaces", str(dependencies[0]["binary"]))

    def test_unrecognized_empty_and_snapshot_dependency_lists_are_rejected(self):
        for contents in ("none\n", "broken dependency\n", "org.example:lib:jar:1-SNAPSHOT:compile:/missing\n"):
            with self.subTest(contents=contents), self.assertRaises(ValueError):
                PACKAGE.parse_dependencies(self.dependencies(contents))

    def test_dependency_sources_are_copied_not_merely_linked(self):
        dependencies = PACKAGE.parse_dependencies(self.dependencies())
        cache = self.root / "cache"
        prefix = cache / "org/example/library/1.2.3/library-1.2.3"
        prefix.parent.mkdir(parents=True)
        with zipfile.ZipFile(str(prefix) + "-sources.jar", "w") as archive:
            archive.writestr("org/example/Library.java", "class Library {}")
        Path(str(prefix) + ".pom").write_text("<project><licenses/></project>")
        destination = self.root / "package"
        with mock.patch.object(PACKAGE.urllib.request, "urlopen", side_effect=AssertionError("network")):
            records = PACKAGE.collect_dependencies(dependencies, destination, cache)
        self.assertEqual(len(records), 2)
        for record in records:
            self.assertEqual(len(record["files"]), 2)
            for source in record["files"]:
                self.assertTrue((destination / source["path"]).is_file())
                self.assertEqual(source["sha256"], PACKAGE.sha256(destination / source["path"]))

    def test_missing_dependency_source_fails_instead_of_writing_a_url_offer(self):
        dependencies = PACKAGE.parse_dependencies(self.dependencies())
        error = urllib.error.HTTPError("https://example.invalid/source", 404, "missing", {}, None)
        self.addCleanup(error.close)
        with mock.patch.object(PACKAGE.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(urllib.error.HTTPError):
                PACKAGE.collect_dependencies(dependencies, self.root / "package", self.root / "cache")
        self.assertFalse(list((self.root / "cache").rglob("*.jar")))

    def test_empty_maven_carrier_is_explicit_and_preserves_all_metadata(self):
        dependencies = PACKAGE.parse_dependencies(self.dependencies())
        with zipfile.ZipFile(dependencies[0]["binary"], "w") as jar:
            jar.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
            jar.writestr("META-INF/maven/org.example/library/pom.properties", "version=1.2.3")
        cache = self.root / "cache"
        pom = cache / "org/example/library/1.2.3/library-1.2.3.pom"
        pom.parent.mkdir(parents=True)
        pom.write_text("<project/>")
        with mock.patch.object(PACKAGE.urllib.request, "urlopen", side_effect=AssertionError("network")):
            records = PACKAGE.collect_dependencies(dependencies, self.root / "package", cache)
        self.assertEqual(records[0]["sourceForm"], "metadata-only")
        self.assertTrue(any(entry["path"].endswith(".jar") for entry in records[0]["files"]))
        with zipfile.ZipFile(dependencies[0]["binary"], "a") as jar:
            jar.writestr("META-INF/native/libexample.so", "compiled native code")
        with mock.patch.object(PACKAGE.urllib.request, "urlopen", side_effect=RuntimeError("source required")):
            with self.assertRaisesRegex(RuntimeError, "source required"):
                PACKAGE.collect_dependencies(dependencies, self.root / "package2", cache)

    def test_bundle_rejects_changed_missing_and_added_files(self):
        root = self.bundle()
        PACKAGE.verify_bundle(root, TOOLS)
        payload = root / "source.java"
        payload.write_text("changed")
        with self.assertRaisesRegex(ValueError, "inventory/checksum"):
            PACKAGE.verify_bundle(root, TOOLS)
        payload.write_text("source payload")
        payload.unlink()
        with self.assertRaisesRegex(ValueError, "inventory/checksum"):
            PACKAGE.verify_bundle(root, TOOLS)
        payload.write_text("source payload")
        (root / ".mvn").mkdir()
        (root / ".mvn/maven.config").write_text("unexpected configuration")
        with self.assertRaisesRegex(ValueError, "inventory/checksum"):
            PACKAGE.verify_bundle(root, TOOLS)

    def test_inventory_checks_symlink_directories_and_rejects_escape(self):
        root = self.bundle()
        (root / "linked-directory").symlink_to("hexproof-build", target_is_directory=True)
        self.assertIn("linked-directory", PACKAGE.inventory(root))
        (root / "escape").symlink_to("../outside")
        with self.assertRaisesRegex(ValueError, "escapes"):
            PACKAGE.inventory(root)

    def test_patch_revision_mismatch_is_rejected(self):
        root = self.bundle()
        manifest = json.loads((root / "SOURCE-MANIFEST.json").read_text())
        manifest["upstream"]["adapterRevision"] = 99999
        (root / "SOURCE-MANIFEST.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "version"):
            PACKAGE.verify_bundle(root, TOOLS)

    def test_source_archive_is_reproducible_and_contains_source_bytes(self):
        root = self.bundle()
        first, second = self.root / "one.tar.gz", self.root / "two.tar.gz"
        PACKAGE.archive_tree(root, first, 12345)
        os.utime(root / "source.java", (9000000, 9000000))
        PACKAGE.archive_tree(root, second, 12345)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with tarfile.open(first) as archive:
            member = archive.getmember("hexproof-forge-source/source.java")
            self.assertEqual(member.uid, 0)
            self.assertEqual(member.mtime, 12345)
            self.assertEqual(archive.extractfile(member).read(), b"source payload")

    def test_rebuild_dependency_graph_or_bytes_cannot_drift(self):
        root = self.bundle()
        report = self.dependencies()
        manifest_path = root / "SOURCE-MANIFEST.json"
        manifest = json.loads(manifest_path.read_text())
        entries = PACKAGE.parse_dependencies(report)
        manifest["runtimeDependencies"] = [
            {**{key: value for key, value in entry.items() if key != "binary"},
             "binarySha256": PACKAGE.sha256(entry["binary"])} for entry in entries]
        manifest_path.write_text(json.dumps(manifest))
        PACKAGE.check_dependencies(root, report)
        entries[0]["binary"].write_bytes(b"changed library")
        with self.assertRaisesRegex(ValueError, "differ"):
            PACKAGE.check_dependencies(root, report)

    def test_output_inside_preserved_source_is_rejected(self):
        root = self.bundle()
        result = subprocess.run(["python3", str(TOOLS / "source-package.py"), "verify",
                                 "--source", str(root), "--output", str(root / "output")],
                                text=True, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside", result.stderr)

    def test_xmlpull_module_uses_only_four_original_api_classes_and_notice(self):
        source = self.root / "official-source"
        (source / "forge").mkdir(parents=True)
        (source / "forge/pom.xml").write_text('<project xmlns="http://maven.apache.org/POM/4.0.0">'
                                             '<properties><revision>2.0.11-SNAPSHOT</revision></properties></project>')
        archive_path = self.root / "xmlpull.tar.gz"
        definition = json.loads((TOOLS / "dependency-sources.json").read_text())
        original = definition["archives"][0]
        payloads = {f"{original['root']}/src/java/api/org/xmlpull/v1/{name}.java": f"original {name}".encode()
                    for name in definition["xmlpullApiCompatibility"]["classes"]}
        payloads[f"{original['root']}/LICENSE.txt"] = b"original public domain notice"
        with tarfile.open(archive_path, "w:gz") as archive:
            for name, data in payloads.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
        with mock.patch.object(PACKAGE, "upstream_archives", return_value=[(original, archive_path)]):
            module = PACKAGE.prepare_dependencies(source, TOOLS, self.root / "cache")
        self.assertEqual(len(list(module.rglob("*.java"))), 4)
        self.assertFalse((module / "src/main/resources/META-INF/services").exists())
        self.assertEqual((module / "src/main/resources/META-INF/LICENSE-XMLPULL.txt").read_bytes(),
                         b"original public domain notice")

    def test_native_archive_corruption_is_rejected_without_download(self):
        preserved = self.root / "preserved"
        directory = preserved / "third-party/upstream"
        directory.mkdir(parents=True)
        definition = json.loads((TOOLS / "dependency-sources.json").read_text())
        (directory / definition["archives"][0]["archive"]).write_bytes(b"not original source")
        with mock.patch.object(PACKAGE, "download", side_effect=AssertionError("network")):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                PACKAGE.upstream_archives(TOOLS, self.root / "cache", preserved)

    def test_release_pair_verifies_after_runtime_relocation(self):
        runtime_archive, source_archive = create_release_fixture(self.root)
        PACKAGE.verify_release(runtime_archive, source_archive, TOOLS)
        relocated = self.root / "different directory" / "runtime"
        relocated.parent.mkdir()
        shutil.move(str(self.root / "hexproof-forge-runtime"), relocated)
        PACKAGE.validate_runtime(relocated, PACKAGE.read_upstream(TOOLS))

    def test_runtime_tampering_extra_jar_and_symlink_are_rejected(self):
        create_release_fixture(self.root)
        runtime = self.root / "hexproof-forge-runtime"
        upstream = PACKAGE.read_upstream(TOOLS)
        card = runtime / "forge-gui/res/cardsfolder/test.txt"
        original = card.read_bytes()
        card.write_bytes(b"tampered card rules")
        with self.assertRaisesRegex(ValueError, "inventory/checksum"):
            PACKAGE.validate_runtime(runtime, upstream)
        card.write_bytes(original)
        extra = runtime / "lib/extra.jar"
        extra.write_bytes(b"undeclared code")
        PACKAGE.seal_runtime(runtime, upstream)
        with self.assertRaisesRegex(ValueError, "classpath"):
            PACKAGE.validate_runtime(runtime, upstream)
        extra.unlink()
        card.unlink()
        card.symlink_to("../languages/en-US.properties")
        PACKAGE.seal_runtime(runtime, upstream)
        with self.assertRaisesRegex(ValueError, "symlinks"):
            PACKAGE.validate_runtime(runtime, upstream)

    def test_self_consistent_runtime_resource_license_and_notice_drift_rejected(self):
        runtime_archive, source_archive = create_release_fixture(self.root)
        runtime = self.root / "hexproof-forge-runtime"
        for name in ("forge-gui/res/cardsfolder/test.txt", "FORGE-LICENSE", "THIRD-PARTY-LICENSES/extra.txt"):
            with self.subTest(name=name):
                path = runtime / name
                original = path.read_bytes() if path.exists() else None
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"different from corresponding source")
                PACKAGE.seal_runtime(runtime, PACKAGE.read_upstream(TOOLS))
                PACKAGE.archive_tree(runtime, runtime_archive, 12345)
                with self.assertRaisesRegex(ValueError, "resources|license|notices"):
                    PACKAGE.verify_release(runtime_archive, source_archive, TOOLS)
                if original is None:
                    path.unlink()
                else:
                    path.write_bytes(original)

    def test_source_cannot_omit_required_native_archives_or_use_unknown_source_form(self):
        root = self.bundle()
        path = root / "SOURCE-MANIFEST.json"
        manifest = json.loads(path.read_text())
        manifest["runtimeDependencies"][0]["sourceForm"] = "url-only-offer"
        PACKAGE.write_json(path, manifest)
        with self.assertRaisesRegex(ValueError, "source form"):
            PACKAGE.verify_bundle(root, TOOLS)
        manifest["runtimeDependencies"][0].update({"sourceForm": "source-jar", "groupId": "at.yawk.lz4",
                                                   "artifactId": "lz4-java", "version": "1.10.2"})
        PACKAGE.write_json(path, manifest)
        with self.assertRaisesRegex(ValueError, "pinned upstream source archives"):
            PACKAGE.verify_bundle(root, TOOLS)

    def test_embedded_rebuild_imports_do_not_modify_preserved_source(self):
        root = self.bundle()
        before = PACKAGE.inventory(root)
        code = """import pathlib, runpy, sys
root = pathlib.Path(sys.argv[1])
namespace = runpy.run_path(str(root / 'hexproof-build/source-package.py'))
namespace['verify_bundle'](root, root / 'hexproof-build')
builder = namespace['load_builder'](root / 'hexproof-build')
builder.packaging().verify_bundle(root, root / 'hexproof-build')
assert not list(root.rglob('*.pyc'))
"""
        subprocess.run(["python3", "-c", code, str(root)], cwd=root, check=True,
                        text=True, capture_output=True, timeout=15)
        self.assertEqual(before, PACKAGE.inventory(root))

    def test_source_repack_keeps_canonical_root_after_directory_rename(self):
        root = self.bundle()
        renamed = self.root / "owner-renamed-sources"
        root.rename(renamed)
        archive = self.root / "renamed.tar.gz"
        PACKAGE.archive_tree(renamed, archive, 12345, "hexproof-forge-source")
        extracted = PACKAGE.extract_archive(archive, self.root / "extracted", "hexproof-forge-source")
        PACKAGE.verify_bundle(extracted, TOOLS)

    def test_archive_rejects_traversal_duplicates_special_files_and_escaping_links(self):
        for kind in ("traversal", "duplicate", "symlink", "fifo"):
            with self.subTest(kind=kind):
                path = self.root / (kind + ".tar.gz")
                with tarfile.open(path, "w:gz") as archive:
                    name = "../outside" if kind == "traversal" else "hexproof-forge-source/item"
                    member = tarfile.TarInfo(name)
                    if kind == "symlink":
                        member.type = tarfile.SYMTYPE
                        member.linkname = "../../outside"
                    elif kind == "fifo":
                        member.type = tarfile.FIFOTYPE
                    archive.addfile(member)
                    if kind == "duplicate":
                        archive.addfile(tarfile.TarInfo("hexproof-forge-source/./item"))
                with self.assertRaisesRegex(ValueError, "Unsafe|duplicate|escapes"):
                    PACKAGE.extract_archive(path, self.root / kind, "hexproof-forge-source")

    def test_workflow_is_optional_native_and_never_publishes_or_deploys(self):
        workflow = (REPO / ".github/workflows/forge-runtime.yml").read_text()
        self.assertIn("  workflow_dispatch:", workflow)
        self.assertNotIn("  push:", workflow)
        self.assertNotIn("  pull_request:", workflow)
        self.assertIn("runner: ubuntu-24.04-arm", workflow)
        self.assertIn("runner: ubuntu-24.04\n", workflow)
        self.assertIn("--from-source", workflow)
        self.assertIn("-tags engineintegration", workflow)
        self.assertIn("./internal/rulesengine/forge ./internal/server", workflow)
        self.assertIn("-p 1 -race", workflow)
        self.assertNotIn("contents: write", workflow)
        self.assertNotIn("gh release", workflow)
        self.assertNotIn("deploy/deploy-", workflow)


if __name__ == "__main__":
    unittest.main()
