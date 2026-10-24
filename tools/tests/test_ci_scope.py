#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import json
import os
from pathlib import Path
import re
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

    def test_tool_deployment_and_release_workflow_edits_do_not_build_applications(self):
        for path in ("tools/release-verification.py", "tools/tests/test_release_verification.py",
                     "tools/check-i18n.py", "tools/git_evidence.py",
                     "tools/write-feedback-config.py", "deploy/feedback/install.py",
                     ".github/workflows/release.yml", ".github/screenshots/home.png"):
            with self.subTest(path=path):
                self.assertEqual(scope.build_scope([path]), (False, False, False))

    def test_build_protocol_and_unknown_tools_keep_application_checks(self):
        for path in ("tools/build.sh", "tools/protocol_codegen.py", "tools/payload_schema.py",
                     "tools/payload_go_structs.py", "tools/payload_enums.py",
                     "tools/protocol_fixture_index.py", "tools/check-protocol-parity.py",
                     "tools/generate-runtime.py", "tools/new-generator/build.py",
                     "tools/new-generator/check-i18n.py"):
            with self.subTest(path=path):
                self.assertEqual(scope.build_scope([path]), (True, True, True))

    def test_official_push_and_same_repository_pr_reuse_local_application_checks(self):
        self.assertFalse(scope.full_checks("push", "ClayStan404/hexproof", ""))
        self.assertFalse(scope.full_checks("pull_request", "ClayStan404/hexproof",
                                          "ClayStan404/hexproof"))
        self.assertFalse(scope.full_checks("pull_request", "claystan404/hexproof",
                                          "ClayStan404/hexproof"))

    def test_external_unknown_and_manual_checks_are_not_bypassed(self):
        for event, repository, head in (
                ("pull_request", "ClayStan404/hexproof", "contributor/fork"),
                ("pull_request", "ClayStan404/hexproof", ""),
                ("pull_request", "other/repo", "other/repo"),
                ("push", "other/repo", ""), ("push", "", ""),
                ("workflow_dispatch", "ClayStan404/hexproof", ""),
                ("pull_request", "", ""), ("future_event", "", "")):
            with self.subTest(event=event, repository=repository, head=head):
                self.assertTrue(scope.full_checks(event, repository, head))

    def test_lightweight_events_do_not_need_comparison_history(self):
        for event, repository, head in (
                ("push", "ClayStan404/hexproof", ""),
                ("pull_request", "ClayStan404/hexproof", "ClayStan404/hexproof")):
            with self.subTest(event=event, repository=repository):
                result = subprocess.run([sys.executable, str(SCRIPT), "--event", event,
                                         "--repository", repository, "--head-repository", head],
                                        text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout, "client=false\nserver=false\nforge=false\nfull=false\nforge_host_service=false\n")

    def test_manual_override_cannot_be_bypassed_by_same_repository_event(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--force-all", "--event", "pull_request",
                                 "--repository", "ClayStan404/hexproof", "--head-repository", "ClayStan404/hexproof"],
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, "client=true\nserver=true\nforge=true\nfull=true\nforge_host_service=true\n")

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
                self.assertEqual(result.stdout, "client=true\nserver=true\nforge=true\nfull=true\nforge_host_service=true\n")

    def test_manual_override_does_not_need_git_history(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--force-all"],
                                text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, "client=true\nserver=true\nforge=true\nfull=true\nforge_host_service=true\n")

    def test_helper_cross_platform_paths_also_keep_linux_client_coverage(self):
        for path in ("apps/client-qt/src/services/ForgeHostService.cpp",
                     "apps/client-qt/src/services/ForgeHostDiagnostics.h",
                     "apps/client-qt/src/ApplicationPaths.h",
                     "apps/client-qt/tests/forgehostservice/CMakeLists.txt",
                     "apps/client-qt/tests/forgehostservice_test.cpp",
                     "apps/client-qt/CMakeLists.txt", ".github/workflows/ci.yml",
                     ".github/actions/setup-qt/action.yml"):
            with self.subTest(path=path):
                self.assertTrue(scope.forge_host_service_scope([path]))
                self.assertTrue(scope.build_scope([path])[0])
        for path in ("README.md", "apps/client-qt/qml/Main.qml", "apps/server/go.mod"):
            with self.subTest(path=path):
                self.assertFalse(scope.forge_host_service_scope([path]))

    def test_helper_ci_uses_shared_scope_and_does_not_duplicate_full_suites(self):
        root = SCRIPT.parents[1]
        ci = (root / ".github/workflows/ci.yml").read_text()
        helper = ci.split("  forge-host-service:\n", 1)[1].split("  client-sanitizers:\n", 1)[0]
        self.assertIn("needs: changes", helper)
        self.assertIn("if: github.event_name == 'pull_request' && needs.changes.outputs.forge_host_service == 'true'", helper)
        self.assertIn("os: [windows-2022, macos-15]", helper)
        self.assertIn("cmake -S apps/client-qt/tests/forgehostservice", helper)
        self.assertFalse((root / ".github/workflows/forge-host-service.yml").exists())
        cmake = (root / "apps/client-qt/CMakeLists.txt").read_text()
        self.assertIn("add_test(NAME forgehostservice COMMAND hexproof_forgehostservice_test)", cmake)

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
        self.assertIn("if: needs.changes.outputs.full == 'true'", quality)
        # Cheap checks remain unconditional; only the full tool suite is selected.
        self.assertNotIn("if:", quality.split("      - name: Test quality checks", 1)[0])
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

    def required_verification(self):
        workflow = (SCRIPT.parents[1] / ".github/workflows/ci.yml").read_text().split("jobs:\n", 1)[1]
        job = re.search(r"^  required-verification:\n(.*?)(?=^  [A-Za-z_][A-Za-z0-9_-]*:|\Z)",
                        workflow, re.MULTILINE | re.DOTALL)[1]
        dependencies = set(re.findall(r"^      - ([A-Za-z_][A-Za-z0-9_-]*)$", job, re.MULTILINE))
        script = "\n".join(line[10:] for line in job.split("        run: |\n", 1)[1].splitlines()) + "\n"
        return workflow, job, dependencies, script

    def test_required_check_waits_for_every_job_even_after_failure(self):
        workflow, job, dependencies, _ = self.required_verification()
        jobs = set(re.findall(r"^  ([A-Za-z_][A-Za-z0-9_-]*):", workflow, re.MULTILINE))
        self.assertEqual(dependencies, jobs - {"required-verification"})
        self.assertIn("    name: Required verification\n", job)
        self.assertIn("    if: always()\n", job)
        self.assertIn("JOB_RESULTS: ${{ toJSON(needs) }}", job)
        self.assertNotRegex(workflow, r"(?m)^\s+continue-on-error:")

    def test_required_check_accepts_scoped_skips_but_rejects_incomplete_verification(self):
        _, _, dependencies, script = self.required_verification()
        complete = {name: {"result": "success"} for name in dependencies}
        light = {name: {"result": "success" if name in ("changes", "quality") else "skipped"}
                 for name in dependencies}
        scenarios = [("complete", complete, True), ("light", light, True)]
        for name in dependencies:
            for result in ("failure", "cancelled", "unknown"):
                scenarios.append((name + ":" + result, {**light, name: {"result": result}}, False))
        for name in ("changes", "quality"):
            scenarios.append((name + ":skipped", {**light, name: {"result": "skipped"}}, False))
            scenarios.append((name + ":missing", {key: value for key, value in light.items() if key != name}, False))
        for name, jobs, expected in scenarios:
            with self.subTest(scenario=name):
                result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script],
                                        env=dict(os.environ, JOB_RESULTS=json.dumps(jobs)),
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
