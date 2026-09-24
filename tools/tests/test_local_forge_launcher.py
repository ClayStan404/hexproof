# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise local Forge startup with isolated tools; never start Java or a hub."""

import os
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


REPO_ROOT = Path(__file__).resolve().parents[2]


class LocalForgeLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        versions = self.root / "third_party/forge-runtime"
        versions.mkdir(parents=True)
        self.launcher = self.root / "tools/run-local-forge-server.sh"
        shutil.copy(REPO_ROOT / "tools/run-local-forge-server.sh", self.launcher)
        shutil.copy(REPO_ROOT / "tools/local-forge-runtime.py", self.root / "tools")
        self.runtime = self.root / "runtime"
        self.server = self.root / "server"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "apps/server").mkdir(parents=True)
        self.write_executable(self.server, 'printf "server:%s\\n" "$*"\nprintf "runtime:%s\\n" "$HEXPROOF_FORGE_HOME"\n')
        self.write_executable(self.bin / "java", "exit 0\n")
        self.write_executable(self.bin / "go", 'printf "build:%s CGO=%s\\n" "$*" "$CGO_ENABLED"\n')
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        HEXPROOF_SERVER_BINARY_PATH=str(self.server),
                        HEXPROOF_FORGE_LOCAL_ROOT=str(self.runtime),
                        HEXPROOF_FORGE_JAVA="java")
        self.native_host = versions / "native-host"
        java_source = self.native_host / "src/main/java/org/hexproof/forge"
        java_source.mkdir(parents=True)
        (java_source / "NativeHost.java").write_text("// Synthetic launcher fixture, never compiled.\n")
        resource = self.native_host / "src/main/resources/org/hexproof/forge/printing-aliases.tsv"
        resource.parent.mkdir(parents=True)
        resource.write_text("# Synthetic printing index\n")
        patch = b"reviewed synthetic patch\n"
        (self.native_host / "native.patch").write_bytes(patch)
        self.upstream = {"repository": "https://example.invalid/forge.git", "revision": "a" * 40,
                         "adapterRevision": 1, "mainClass": "org.hexproof.forge.NativeHost",
                         "patch": {"file": "native.patch", "sha256": hashlib.sha256(patch).hexdigest()}}
        (self.native_host / "upstream.json").write_text(json.dumps(self.upstream))
        self.write_executable(self.bin / "git", f'''
case "$3" in
    rev-parse) printf '%s\\n' '{self.upstream["revision"]}' ;;
    diff) if [[ "${{4:-}}" != --cached ]]; then cat '{self.native_host}/native.patch'; fi ;;
    ls-files) ;;
    *) exit 17 ;;
esac
''')

    def write_executable(self, path, body):
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def run_launcher(self, *args):
        return subprocess.run(["bash", str(self.launcher), *args], cwd=self.root,
                              env=self.env, text=True, capture_output=True, timeout=10)

    def prepare_native_runtime(self, destination=None):
        runtime = destination or self.runtime
        runtime.mkdir(parents=True)
        source = self.root / "native source"
        for directory in ("cardsfolder", "languages", "deckgendecks"):
            (source / "forge-gui/res" / directory).mkdir(parents=True, exist_ok=True)
        (source / "forge-gui/res/languages/en-US.properties").touch()
        (source / "forge-gui/res/deckgendecks/Standard.raw.dat").touch()
        (runtime / "forge-gui").symlink_to(source / "forge-gui", target_is_directory=True)
        (runtime / "lib").mkdir()
        dependency = runtime / "lib/official.jar"
        dependency.write_bytes(b"synthetic dependency")
        artifact = {"path": "lib/official.jar", "sha256": hashlib.sha256(dependency.read_bytes()).hexdigest()}
        with zipfile.ZipFile(runtime / "forge-harness.jar", "w") as jar:
            jar.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\r\nMain-Class: org.hexproof.forge.NativeHost\r\nClass-Path: lib/official.jar\r\n\r\n")
            resources = self.native_host / "src/main/resources"
            for resource in resources.rglob("*"):
                if resource.is_file():
                    jar.write(resource, resource.relative_to(resources).as_posix())
        shutil.copytree(self.native_host, runtime / "host-source")
        provenance = dict(self.upstream, developmentOnly=True, corePatches=[self.upstream["patch"]],
                          resourceSource=str(source), artifacts=[artifact],
                          hostArtifact={"path": "forge-harness.jar", "sha256": hashlib.sha256((runtime / "forge-harness.jar").read_bytes()).hexdigest()})
        (runtime / "provenance.json").write_text(json.dumps(provenance))
        return runtime

    def native_builder(self, package, extra=""):
        (self.root / "third_party/forge-runtime/build-native.py").write_text(f'''
from pathlib import Path
import json, sys
Path({str(self.root / "native-builder-args.json")!r}).write_text(json.dumps(sys.argv[1:]))
{extra}
print("native builder progress")
print({str(package)!r})
''')

    def prepare_standalone_runtime(self):
        specification = importlib.util.spec_from_file_location(
            "forge_package_fixtures", REPO_ROOT / "tools/tests/test_forge_source_package.py")
        fixtures = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(fixtures)
        fixture_dir = self.root / "standalone-fixture"
        runtime_archive, _ = fixtures.create_release_fixture(fixture_dir)
        relocated = self.root / "relocated package"
        relocated.mkdir()
        package = fixtures.PACKAGE.extract_archive(runtime_archive, relocated, "hexproof-forge-runtime")
        shutil.copytree(REPO_ROOT / "third_party/forge-runtime/native-host", self.native_host,
                        dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        shutil.copy2(REPO_ROOT / "third_party/forge-runtime/source-package.py",
                     self.root / "third_party/forge-runtime/source-package.py")
        # A standalone runtime must not need its original package/build tree.
        shutil.rmtree(fixture_dir)
        self.env["HEXPROOF_FORGE_LOCAL_ROOT"] = str(package)
        return package

    def test_standalone_runtime_launches_after_relocation_without_source_archive(self):
        package = self.prepare_standalone_runtime()
        result = self.run_launcher("-port", "57321")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"runtime:{package}/forge-gui", result.stdout)
        self.assertIn("server:-port 57321", result.stdout)
        self.assertNotIn("build:", result.stdout)

    def test_standalone_resource_tampering_is_rejected_before_startup(self):
        package = self.prepare_standalone_runtime()
        (package / "forge-gui/res/cardsfolder/test.txt").write_text("changed card script")
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inventory/checksum mismatch", result.stderr)
        self.assertNotIn("server:", result.stdout)

    def test_native_runtime_forwards_arguments_without_building(self):
        self.prepare_native_runtime()
        result = self.run_launcher("--native", "-port", "57321")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"runtime:{self.runtime}/forge-gui", result.stdout)
        self.assertIn("server:-port 57321", result.stdout)
        self.assertNotIn("build:", result.stdout)

    def test_default_mode_is_native(self):
        self.prepare_native_runtime()
        result = self.run_launcher("-port", "57321")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"runtime:{self.runtime}/forge-gui", result.stdout)
        self.assertIn("server:-port 57321", result.stdout)
        self.assertNotIn("build:", result.stdout)
        help_result = self.run_launcher("--help")
        self.assertEqual(help_result.returncode, 0, help_result.stderr)
        self.assertIn("Only official Forge", help_result.stdout)

    def test_changed_printing_index_requires_a_new_runtime(self):
        self.prepare_native_runtime()
        resource = self.native_host / "src/main/resources/org/hexproof/forge/printing-aliases.tsv"
        resource.write_text("# Reviewed new catalog index\n")
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("printing resources changed", result.stderr)
        self.assertNotIn("server:", result.stdout)

    def test_native_prepare_and_mode_can_be_reordered(self):
        self.prepare_native_runtime()
        for args in (("--prepare", "--native"), ("--native", "--prepare")):
            result = self.run_launcher(*args, "-port", "57321")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("build:", result.stdout)
            self.assertIn("server:-port 57321", result.stdout)

    def test_double_dash_preserves_server_arguments(self):
        self.prepare_native_runtime()
        result = self.run_launcher("--native", "--", "--prepare", "--legacy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("server:--prepare --legacy", result.stdout)
        self.assertNotIn("build:", result.stdout)

    def test_legacy_selection_is_rejected_before_startup(self):
        for args in (("--legacy",), ("--native", "--legacy"), ("--prepare", "--legacy")):
            result = self.run_launcher(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("has been retired", result.stderr)
            self.assertNotIn("server:", result.stdout)
            self.assertNotIn("build:", result.stdout)

    def test_relative_overrides_remain_relative_to_invocation(self):
        self.prepare_native_runtime()
        self.env["HEXPROOF_SERVER_BINARY_PATH"] = "server"
        self.env["HEXPROOF_FORGE_LOCAL_ROOT"] = "runtime"
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"build:build -o {self.server}", result.stdout)

    def test_native_prepare_publishes_fresh_runtime_via_symlink(self):
        package = self.prepare_native_runtime(self.root / "generated/runtime-unique")
        self.native_builder(package)
        self.env["HEXPROOF_FORGE_SOURCE_DIR"] = "source with spaces"
        self.env["HEXPROOF_FORGE_OUTPUT_DIR"] = "native output"
        self.env["HEXPROOF_FORGE_LOCAL_ROOT"] = "runtime"
        result = self.run_launcher("--native", "--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.runtime.is_symlink())
        self.assertEqual(self.runtime.resolve(), package)
        arguments = json.loads((self.root / "native-builder-args.json").read_text())
        self.assertEqual(arguments, ["--source", str(self.root / "source with spaces"), "--output", str(self.root / "native output")])
        self.assertIn("native builder progress", result.stderr)
        self.assertIn("build:", result.stdout)

    def test_native_default_index_is_reused(self):
        package = self.prepare_native_runtime(self.root / "generated/runtime-unique")
        self.native_builder(package)
        del self.env["HEXPROOF_FORGE_LOCAL_ROOT"]
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        index = self.root / "build/forge-native/local-runtime.json"
        self.assertEqual(json.loads(index.read_text())["runtimeRoot"], str(package))
        (self.root / "third_party/forge-runtime/build-native.py").unlink()
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"runtime:{package}/forge-gui", result.stdout)
        self.assertNotIn("build:", result.stdout)

    def test_native_stale_index_prepares_new_package_and_preserves_old(self):
        old = self.prepare_native_runtime(self.root / "generated/old")
        provenance = old / "provenance.json"
        content = json.loads(provenance.read_text())
        content["revision"] = "old revision"
        provenance.write_text(json.dumps(content))
        old_bytes = provenance.read_bytes()
        fresh = self.prepare_native_runtime(self.root / "generated/new")
        self.native_builder(fresh)
        index = self.root / "build/forge-native/local-runtime.json"
        index.parent.mkdir(parents=True)
        index.write_text(json.dumps({"schema": 1, "runtimeRoot": str(old)}))
        del self.env["HEXPROOF_FORGE_LOCAL_ROOT"]
        result = self.run_launcher("--native", "--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(index.read_text())["runtimeRoot"], str(fresh))
        self.assertEqual(provenance.read_bytes(), old_bytes)

    def test_native_existing_mismatch_is_never_overwritten(self):
        self.prepare_native_runtime()
        dependency = self.runtime / "lib/official.jar"
        dependency.write_text("modified dependency")
        for args in (("--native",), ("--native", "--prepare")):
            result = self.run_launcher(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checksum mismatch", result.stderr)
            self.assertEqual(dependency.read_text(), "modified dependency")
            self.assertNotIn("build:", result.stdout)

    def test_native_changed_host_source_requires_rebuild(self):
        self.prepare_native_runtime()
        (self.native_host / "src/main/java/NewHost.java").write_text("// changed host\n")
        result = self.run_launcher("--native", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("host source changed", result.stderr)

    def test_native_replaced_host_jar_is_rejected_even_with_same_manifest(self):
        self.prepare_native_runtime()
        jar_path = self.runtime / "forge-harness.jar"
        with zipfile.ZipFile(jar_path, "a") as jar:
            jar.writestr("org/hexproof/forge/NativeHost.class", b"substituted bytecode")
        changed = jar_path.read_bytes()
        result = self.run_launcher("--native", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("host JAR checksum mismatch", result.stderr)
        self.assertEqual(jar_path.read_bytes(), changed)
        self.assertNotIn("build:", result.stdout)

    def test_native_missing_host_jar_provenance_is_rejected(self):
        self.prepare_native_runtime()
        path = self.runtime / "provenance.json"
        value = json.loads(path.read_text())
        del value["hostArtifact"]
        path.write_text(json.dumps(value))
        result = self.run_launcher("--native")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("host artifact provenance is missing", result.stderr)

    def test_native_dangling_override_is_preserved(self):
        self.runtime.symlink_to(self.root / "missing-runtime")
        result = self.run_launcher("--native", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.runtime.is_symlink())

    def test_native_does_not_replace_destination_created_during_build(self):
        package = self.prepare_native_runtime(self.root / "generated/runtime-unique")
        self.native_builder(package, f"Path({str(self.runtime)!r}).mkdir()")
        result = self.run_launcher("--native", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("destination appeared", result.stderr)
        self.assertTrue(self.runtime.is_dir())
        self.assertFalse(self.runtime.is_symlink())
        self.assertTrue(package.is_dir())

    def test_native_failed_builder_preserves_default_index(self):
        index = self.root / "build/forge-native/local-runtime.json"
        index.parent.mkdir(parents=True)
        original = json.dumps({"schema": 1, "runtimeRoot": str(self.root / "previously-built")})
        index.write_text(original)
        del self.env["HEXPROOF_FORGE_LOCAL_ROOT"]
        self.native_builder(self.root / "never-published", "sys.exit(17)")
        result = self.run_launcher("--native", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(index.read_text(), original)
        self.assertNotIn("build:", result.stdout)

    def test_native_unrecognized_index_is_preserved(self):
        index = self.root / "build/forge-native/local-runtime.json"
        index.parent.mkdir(parents=True)
        index.write_text('{"ownerNote":"keep"}')
        del self.env["HEXPROOF_FORGE_LOCAL_ROOT"]
        result = self.run_launcher("--native", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(index.read_text(), '{"ownerNote":"keep"}')


if __name__ == "__main__":
    unittest.main()
