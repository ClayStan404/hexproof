#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "ci-scope.py"
SPEC = importlib.util.spec_from_file_location("ci_scope", SCRIPT)
scope = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scope)


class CiScopeTests(unittest.TestCase):
    def test_documentation_only_changes_do_not_need_builds(self):
        self.assertEqual(scope.build_scope(["README.md", "AGENTS.md", "docs/privacy.md",
                                           "apps/client-qt/config/README.md"]), (False, False, False))

    def test_client_changes_build_client(self):
        self.assertEqual(scope.build_scope(["apps/client-qt/qml/Main.qml"]), (True, False, False))

    def test_server_changes_keep_cross_client_integration_coverage(self):
        self.assertEqual(scope.build_scope(["apps/server/internal/room/room.go"]), (True, True, True))

    def test_forge_boundary_changes_select_real_engine_regressions(self):
        for path in ("third_party/forge-runtime/native-host/native-hooks.patch",
                     "third_party/forge-runtime/native-host/src/test/java/org/hexproof/forge/NativeManaUndoRegressionTest.java",
                     "apps/server/internal/rulesengine/forge/live_mana_undo_test.go",
                     "apps/server/internal/server/forge_prompt.go", "apps/server/internal/forgehost/identity.go",
                     "apps/server/internal/runtimepkg/manifest.json", "apps/server/internal/protocol/message.go",
                     "apps/client-qt/qml/components/RulesTable.qml", "apps/client-qt/tests/qml/tst_rulesmana.qml",
                     "apps/client-qt/src/services/WsClient.cpp", "apps/client-qt/CMakeLists.txt",
                     "tools/run-forge-regression.py", "tools/tests/test_native_forge_builder.py"):
            with self.subTest(path=path):
                self.assertTrue(scope.build_scope([path])[2])

    def test_unrelated_known_domains_skip_real_engine_regressions(self):
        for path in ("apps/server/internal/accounts/accounts.go", "apps/server/internal/feedback/feedback_test.go",
                     "apps/client-qt/qml/screens/DeckLibrary.qml", "tools/check-i18n.py"):
            with self.subTest(path=path):
                self.assertFalse(scope.build_scope([path])[2])

    def test_shared_or_unknown_changes_fail_toward_more_checks(self):
        for path in ("protocol/v2/wire-schema.json", "tools/verify.sh", "packaging/linux/build-tarball.sh",
                     ".github/workflows/ci.yml", "future-build-system.conf"):
            with self.subTest(path=path):
                self.assertEqual(scope.build_scope([path]), (True, True, True))

    def test_missing_or_unknown_base_runs_both_domains(self):
        for base in ("", "0" * 40, "missing-ref-for-ci-scope-test"):
            with self.subTest(base=base):
                result = subprocess.run([sys.executable, str(SCRIPT), "--base", base],
                                        text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout, "client=true\nserver=true\nforge=true\n")

    def test_manual_override_does_not_need_git_history(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--force-all"],
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, "client=true\nserver=true\nforge=true\n")

    def test_rename_out_of_source_domain_keeps_old_source_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.run(["git", "-C", str(root), *args], check=True,
                                      text=True, capture_output=True).stdout.strip()
            def commit():
                git("add", ".")
                git("-c", "user.name=Scope Test", "-c", "user.email=scope@example.invalid",
                    "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null",
                    "commit", "--quiet", "-m", "Scope fixture")
                return git("rev-parse", "HEAD")
            git("init", "--quiet")
            git("config", "maintenance.auto", "false")
            git("config", "gc.auto", "0")
            source = root / "apps/server/internal/rulesengine/forge/example.go"
            source.parent.mkdir(parents=True)
            source.write_text("package example\n")
            base = commit()
            source.rename(root / "README.md")
            commit()
            paths = scope.changed_paths(root, base, "HEAD")
            self.assertIn("apps/server/internal/rulesengine/forge/example.go", paths)
            self.assertEqual(scope.build_scope(paths), (True, True, True))

    def test_routine_quality_and_release_gates_are_not_path_skipped(self):
        root = SCRIPT.parents[1]
        ci = (root / ".github/workflows/ci.yml").read_text()
        quality = ci.split("  quality:\n", 1)[1].split("  server:\n", 1)[0]
        self.assertNotIn("needs.changes", quality)
        self.assertIn("python3 -m unittest discover -s tools/tests", quality)
        release = (root / ".github/workflows/release.yml").read_text()
        self.assertNotIn("ci-scope.py", release)

    def test_scoped_forge_gate_runs_current_overlay_without_full_rebuild(self):
        root = SCRIPT.parents[1]
        ci = (root / ".github/workflows/ci.yml").read_text()
        forge = ci.split("  forge-regression:\n", 1)[1].split("  client:\n", 1)[0]
        self.assertIn("needs.changes.outputs.forge == 'true'", forge)
        self.assertIn("timeout-minutes: 20", forge)
        self.assertIn("python3 tools/run-forge-regression.py", forge)
        self.assertNotIn("build-native.py", forge)
        self.assertNotIn("build.sh", forge)
        full = (root / ".github/workflows/forge-runtime.yml").read_text()
        self.assertIn("workflow_dispatch:", full)
        self.assertNotIn("pull_request:", full)
        self.assertIn("./third_party/forge-runtime/build.sh", full)


if __name__ == "__main__":
    unittest.main()
