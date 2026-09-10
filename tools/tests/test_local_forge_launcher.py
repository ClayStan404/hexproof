# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise local Forge startup with isolated tools; never start Java or a hub."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class LocalForgeLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        versions = self.root / "third_party/forge-runtime"
        versions.mkdir(parents=True)
        shutil.copy(REPO_ROOT / "third_party/forge-runtime/VERSIONS.env", versions)
        self.launcher = self.root / "tools/run-local-forge-server.sh"
        shutil.copy(REPO_ROOT / "tools/run-local-forge-server.sh", self.launcher)
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

    def write_executable(self, path, body):
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def prepare_runtime(self, destination=None):
        runtime = destination or self.runtime
        (runtime / "forge-gui/res/cardsfolder").mkdir(parents=True)
        (runtime / "forge-gui/res/languages").mkdir()
        (runtime / "forge-gui/res/deckgendecks").mkdir()
        (runtime / "forge-harness.jar").write_text("synthetic jar")
        (runtime / "forge-gui/res/languages/en-US.properties").touch()
        (runtime / "forge-gui/res/deckgendecks/Standard.raw.dat").touch()
        shutil.copy(self.root / "third_party/forge-runtime/VERSIONS.env", runtime)

    def run_launcher(self, *args):
        return subprocess.run(["bash", str(self.launcher), *args], cwd=self.root,
                              env=self.env, text=True, capture_output=True, timeout=10)

    def test_matching_runtime_forwards_server_arguments(self):
        self.prepare_runtime()
        result = self.run_launcher("-port", "57321", "-bind", "127.0.0.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("server:-port 57321 -bind 127.0.0.1", result.stdout)
        self.assertIn(f"runtime:{self.runtime}/forge-gui", result.stdout)
        self.assertNotIn("build:", result.stdout)

    def test_prepare_reuses_matching_runtime_and_builds_server(self):
        self.prepare_runtime()
        result = self.run_launcher("--prepare", "-port", "57321")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"build:build -o {self.server} ./cmd/hexproof-server CGO=0", result.stdout)
        self.assertIn("server:-port 57321", result.stdout)

    def test_default_runtime_keeps_previous_patch_installation_separate(self):
        versions = dict(line.split("=", 1) for line in
                        (self.root / "third_party/forge-runtime/VERSIONS.env").read_text().splitlines()
                        if line and not line.startswith("#"))
        revision = versions["MANABREW_REVISION"]
        patch = versions["HEXPROOF_FORGE_PATCH_REVISION"]
        previous = self.root / f"build/forge-runtime/local-{revision}/hexproof-forge-runtime"
        self.prepare_runtime(previous)
        old_manifest = previous / "VERSIONS.env"
        old_manifest.write_text("previous patch revision\n")
        current = self.root / f"build/forge-runtime/local-{revision}-patch{patch}/hexproof-forge-runtime"
        self.prepare_runtime(current)
        del self.env["HEXPROOF_FORGE_LOCAL_ROOT"]
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"runtime:{current}/forge-gui", result.stdout)
        self.assertEqual(old_manifest.read_text(), "previous patch revision\n")

    def test_prepare_builds_and_installs_missing_runtime(self):
        package = self.root / "package/hexproof-forge-runtime"
        self.prepare_runtime(package)
        self.write_executable(self.root / "third_party/forge-runtime/build.sh", """
source "$(dirname "$0")/VERSIONS.env"
mkdir -p build/forge-runtime
tar -czf "build/forge-runtime/hexproof-forge-runtime-${MANABREW_REVISION}.tar.gz" -C package hexproof-forge-runtime
""")
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.runtime / "forge-harness.jar").is_file())
        self.assertIn("build:", result.stdout)
        self.assertIn("server:", result.stdout)
        self.assertFalse(list(self.root.glob("forge-install.*")))

    def test_stale_runtime_is_rejected_without_overwriting(self):
        self.prepare_runtime()
        manifest = self.runtime / "VERSIONS.env"
        manifest.write_text("old version\n")
        for args in [(), ("--prepare",)]:
            result = self.run_launcher(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("server:", result.stdout)
            self.assertEqual(manifest.read_text(), "old version\n")

    def test_prepare_resolves_relative_output_before_invoking_builder(self):
        package = self.root / "package/hexproof-forge-runtime"
        self.prepare_runtime(package)
        self.env["HEXPROOF_FORGE_OUTPUT_DIR"] = "archive output"
        self.write_executable(self.root / "third_party/forge-runtime/build.sh", """
source "$(dirname "$0")/VERSIONS.env"
[[ "$HEXPROOF_FORGE_OUTPUT_DIR" == /* ]] || exit 61
printf 'archive-output:%s\\n' "$HEXPROOF_FORGE_OUTPUT_DIR"
mkdir -p "$HEXPROOF_FORGE_OUTPUT_DIR"
tar -czf "$HEXPROOF_FORGE_OUTPUT_DIR/hexproof-forge-runtime-${MANABREW_REVISION}.tar.gz" -C package hexproof-forge-runtime
""")
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"archive-output:{self.root}/archive output", result.stdout)
        self.assertTrue((self.runtime / "forge-harness.jar").is_file())

    def test_prepare_does_not_publish_an_incomplete_archive(self):
        package = self.root / "package/hexproof-forge-runtime"
        self.prepare_runtime(package)
        (package / "forge-gui/res/languages/en-US.properties").unlink()
        self.write_executable(self.root / "third_party/forge-runtime/build.sh", """
source "$(dirname "$0")/VERSIONS.env"
mkdir -p "$HEXPROOF_FORGE_OUTPUT_DIR"
tar -czf "$HEXPROOF_FORGE_OUTPUT_DIR/hexproof-forge-runtime-${MANABREW_REVISION}.tar.gz" -C package hexproof-forge-runtime
""")
        result = self.run_launcher("--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("archive failed revision/resource validation", result.stderr)
        self.assertFalse(self.runtime.exists())
        self.assertNotIn("build:", result.stdout)
        self.assertNotIn("server:", result.stdout)
        self.assertEqual(len(list(self.root.glob("forge-install.*"))), 1)

    def test_missing_language_bundle_is_rejected(self):
        self.prepare_runtime()
        (self.runtime / "forge-gui/res/languages/en-US.properties").unlink()
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("server:", result.stdout)

    def test_relative_overrides_remain_relative_to_invocation(self):
        self.prepare_runtime()
        self.env["HEXPROOF_SERVER_BINARY_PATH"] = "server"
        self.env["HEXPROOF_FORGE_LOCAL_ROOT"] = "runtime"
        result = self.run_launcher("--prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"build:build -o {self.server}", result.stdout)


if __name__ == "__main__":
    unittest.main()
