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


class ForgeSourcePackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_default_checkout_is_versioned_but_explicit_override_is_preserved(self):
        assignment = next(line for line in (TOOLS / "build.sh").read_text().splitlines()
                          if line.startswith('source_dir="${HEXPROOF_FORGE_SOURCE_DIR:'))
        environment = {**os.environ, "repo_root": str(self.root),
                       "MANABREW_REVISION": "a" * 40, "HEXPROOF_FORGE_PATCH_REVISION": "2"}
        environment.pop("HEXPROOF_FORGE_SOURCE_DIR", None)
        command = assignment + '\nprintf "%s" "$source_dir"'
        default = subprocess.check_output(["bash", "-c", command], env=environment, text=True)
        self.assertEqual(default, str(self.root / ("build/forge-runtime/source-" + "a" * 40 + "-patch2")))
        environment["HEXPROOF_FORGE_SOURCE_DIR"] = str(self.root / "owner checkout")
        explicit = subprocess.check_output(["bash", "-c", command], env=environment, text=True)
        self.assertEqual(explicit, str(self.root / "owner checkout"))

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
        root = self.root / "hexproof-forge-source"
        tools = root / "hexproof-build"
        (tools / "patches").mkdir(parents=True)
        shutil.copy(TOOLS / "VERSIONS.env", tools)
        shutil.copy(TOOLS / "patches/manifest.json", tools / "patches")
        (root / "source.java").write_text("source payload")
        (root / "source-link").symlink_to("source.java")
        manifest = {"schemaVersion": PACKAGE.SCHEMA_VERSION,
                    "versions": PACKAGE.read_versions(TOOLS / "VERSIONS.env"),
                    "sourceDateEpoch": 12345, "runtimeDependencies": [],
                    "files": PACKAGE.inventory(root)}
        (root / "SOURCE-MANIFEST.json").write_text(json.dumps(manifest))
        return root

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
        manifest["versions"]["HEXPROOF_FORGE_PATCH_REVISION"] = "99999"
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
        source = self.root / "manabrew"
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
            PACKAGE.prepare_dependencies(source, TOOLS, self.root / "cache")
        module = source / "target/hexproof-xmlpull-api"
        self.assertEqual(len(list(module.rglob("*.java"))), 4)
        self.assertIn("../../forge/pom.xml", (module / "pom.xml").read_text())
        self.assertIn("1.1.3.4b", (module / "pom.xml").read_text())
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
