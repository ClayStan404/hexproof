# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise managed patch application against disposable real Git checkouts."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "native_forge_builder", ROOT / "third_party/forge-runtime/build-native.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)
REGRESSION_SPEC = importlib.util.spec_from_file_location("forge_regression", ROOT / "tools/run-forge-regression.py")
REGRESSION = importlib.util.module_from_spec(REGRESSION_SPEC)
REGRESSION_SPEC.loader.exec_module(REGRESSION)


class NativeForgeBuilderTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.host = self.root / "host"
        self.host.mkdir()
        self.git("init", "-q")
        self.file = self.source / "input.java"
        self.file.write_text("original\n")
        self.git("add", "input.java")
        self.git("-c", "user.name=Synthetic Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "Fixture")
        self.file.write_text("reviewed hook\n")
        self.delta = self.git("diff", "--binary", "--full-index", "--no-color", "HEAD")
        self.file.write_text("original\n")
        (self.host / "hooks.patch").write_bytes(self.delta)
        self.upstream = {"patch": {"file": "hooks.patch",
                                   "sha256": hashlib.sha256(self.delta).hexdigest()}}

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.source), *args])

    def prepare(self):
        with patch.object(BUILDER, "HOST", self.host):
            return BUILDER.prepare_patch(self.source, self.upstream)

    def test_reviewed_patch_is_idempotent_and_does_not_change_index(self):
        self.assertEqual(self.prepare(), [self.upstream["patch"]])
        self.assertEqual(self.file.read_text(), "reviewed hook\n")
        self.prepare()
        self.assertEqual(self.git("diff", "--cached"), b"")

    def test_unreviewed_tracked_work_is_preserved(self):
        self.file.write_text("owner's unrelated change\n")
        with self.assertRaisesRegex(ValueError, "preserve it"):
            self.prepare()
        self.assertEqual(self.file.read_text(), "owner's unrelated change\n")

    def test_staged_and_untracked_work_are_preserved(self):
        for staged in (False, True):
            with self.subTest(staged=staged):
                note = self.source / "notes.txt"
                note.write_text("owner notes\n")
                if staged:
                    self.git("add", "notes.txt")
                before = self.git("status", "--porcelain")
                with self.assertRaisesRegex(ValueError, "staged or untracked"):
                    self.prepare()
                self.assertEqual(self.git("status", "--porcelain"), before)
                self.assertEqual(note.read_text(), "owner notes\n")

    def test_changed_patch_is_rejected_before_application(self):
        (self.host / "hooks.patch").write_bytes(self.delta + b"unexpected\n")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.prepare()
        self.assertEqual(self.file.read_text(), "original\n")

    def test_reviewed_patch_with_different_context_is_accepted_without_checkout_writes(self):
        original = "".join(f"line {index}\n" for index in range(20))
        self.file.write_text(original)
        self.git("add", "input.java")
        self.git("-c", "user.name=Synthetic Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "Context fixture")
        self.file.write_text(original.replace("line 10", "reviewed line 10"))
        content = self.git("diff", "--binary", "--full-index", "--unified=1", "--no-color", "HEAD")
        self.assertNotEqual(content, self.git("diff", "--binary", "--full-index", "--no-color", "HEAD"))
        (self.host / "hooks.patch").write_bytes(content)
        self.upstream["patch"]["sha256"] = hashlib.sha256(content).hexdigest()
        index = (self.source / ".git/index").read_bytes()
        objects = sorted(path.relative_to(self.source) for path in (self.source / ".git/objects").rglob("*"))
        before = self.file.read_bytes()
        self.assertEqual(self.prepare(), [self.upstream["patch"]])
        self.assertEqual(self.file.read_bytes(), before)
        self.assertEqual((self.source / ".git/index").read_bytes(), index)
        self.assertEqual(sorted(path.relative_to(self.source) for path in (self.source / ".git/objects").rglob("*")), objects)

    def test_extra_edits_outside_reviewed_hunks_are_rejected_and_preserved(self):
        self.prepare()
        self.file.write_text(self.file.read_text() + "owner's extra edit\n")
        before = self.file.read_bytes()
        index = (self.source / ".git/index").read_bytes()
        with self.assertRaisesRegex(ValueError, "preserve it"):
            self.prepare()
        self.assertEqual(self.file.read_bytes(), before)
        self.assertEqual((self.source / ".git/index").read_bytes(), index)

    def test_maven_receives_selected_jdk_before_native_compilation(self):
        environment = {"PATH": "/fixture/jdk21/bin:/fixture/tools", "JAVA_HOME": "/fixture/jdk21"}
        upstream = {"revision": "reviewed"}
        with patch.object(BUILDER.TOOLCHAIN, "build_environment", return_value=environment), \
                patch.object(BUILDER.shutil, "which", return_value="fixture-tool"), \
                patch.object(BUILDER, "git", return_value="reviewed"), \
                patch.object(BUILDER, "prepare_patch", return_value=[]), \
                patch.object(BUILDER.subprocess, "run", side_effect=subprocess.CalledProcessError(7, "fixture-mvn")) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                BUILDER.build(self.source, self.root / "output", upstream)
        self.assertEqual(run.call_args.args[0][0], "mvn")
        self.assertEqual(run.call_args.kwargs["env"], environment)
        self.assertEqual(run.call_args.kwargs["cwd"], self.source)


class ForgeRegressionGateTests(unittest.TestCase):
    def test_overlay_cache_is_bound_to_base_and_source_pins(self):
        manifest = {"runtimeId": "base", "forgeManifestSha256": "manifest", "forge": {"sha256": "archive"}}
        output = Path("fixture")
        original = REGRESSION.overlay_directory(output, manifest, {"sha256": "source"})
        self.assertNotEqual(original, REGRESSION.overlay_directory(output, manifest, {"sha256": "new-source"}))
        manifest["forge"]["sha256"] = "new-base"
        self.assertNotEqual(original, REGRESSION.overlay_directory(output, manifest, {"sha256": "source"}))

    def test_old_base_overlay_is_rejected_even_if_native_identity_matches(self):
        manifest = {"runtimeId": "base", "forgeManifestSha256": "manifest"}
        metadata = {"runtimeId": "current-native", "sha256": "jar", "baseRuntimeId": "base",
                    "baseManifestSha256": "manifest"}
        overlay = SimpleNamespace(identity=lambda: ("current-native", {}), digest=lambda path: "jar")
        REGRESSION.validate_overlay(metadata, manifest, Path("fixture.jar"), overlay)
        for key in ("baseRuntimeId", "baseManifestSha256"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "different pinned base"):
                REGRESSION.validate_overlay({**metadata, key: "retired"}, manifest, Path("fixture.jar"), overlay)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux CI process-group cleanup")
    def test_timeout_stops_nested_engine_process(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            report = {"steps": []}
            command = [sys.executable, "-c",
                "import subprocess,sys,time; child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                "print(child.pid,flush=True); time.sleep(60)"]
            with self.assertRaises(subprocess.TimeoutExpired):
                REGRESSION.run_step("timeout", command, output, report, timeout=1)
            pid = int((output / "timeout.log").read_text().strip())
            state = Path(f"/proc/{pid}/stat")
            # An orphaned killed child can briefly await init's reap as a
            # zombie; it must never remain a running JVM after the gate exits.
            deadline = time.monotonic() + 2
            while True:
                try:
                    status = state.read_text().split()[2]
                except (FileNotFoundError, ProcessLookupError):
                    # The child may be reaped after opening its proc file,
                    # causing the read itself to report ESRCH instead of ENOENT.
                    break
                if status == "Z":
                    break
                if time.monotonic() >= deadline:
                    self.fail(f"Timed-out engine child is still active: {status}")
                time.sleep(0.01)
            self.assertEqual(report["steps"][0]["status"], "failed")

    @unittest.skipUnless(os.name == "posix", "POSIX CI runner")
    def test_native_process_failure_preserves_log_and_fails_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            report = {"steps": []}
            with self.assertRaises(subprocess.CalledProcessError):
                REGRESSION.run_step("native-failure", [sys.executable, "-c",
                    "print('actual native failure'); raise SystemExit(7)"], output, report)
            self.assertEqual(report["steps"][0]["status"], "failed")
            self.assertIn("actual native failure", (output / "native-failure.log").read_text())

    def test_go_empty_selection_or_skip_cannot_make_gate_green(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "go.log"
            for incomplete in ("", '{"Action":"pass","Package":"fixture"}\n',
                               '{"Action":"skip","Test":"TestLiveForgeManaUndo"}\n'):
                with self.subTest(log=incomplete):
                    log.write_text(incomplete)
                    with self.assertRaisesRegex(ValueError, "did not pass"):
                        REGRESSION.require_go_results(log)
            log.write_text("\n".join(json.dumps({"Action": "pass", "Test": test})
                                     for test in REGRESSION.GO_TESTS))
            REGRESSION.require_go_results(log)

    def test_supplied_base_is_rejected_before_build_when_checksum_differs(self):
        overlay = REGRESSION.module("regression_gate_test_overlay", ROOT / "third_party/forge-runtime/build-overlay.py")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            base = output / "base.tar.gz"
            base.write_bytes(b"tampered")
            manifest = output / "manifest.json"
            manifest.write_text('{"forge":{"size":8,"sha256":"' + "0" * 64 + '"}}')
            args = SimpleNamespace(output=output, cache=output / "cache", base_archive=base,
                                   javac=None, java=None)
            with patch.object(overlay, "BASE_MANIFEST", manifest), \
                    patch.object(overlay, "find_javac", return_value="/fixture/jdk21/bin/javac"), \
                    patch.object(REGRESSION, "module", side_effect=[overlay, object()]), \
                    patch.object(REGRESSION, "run_step") as run:
                with self.assertRaisesRegex(ValueError, "pinned size/checksum"):
                    REGRESSION.qualify(args, {"steps": []})
                run.assert_not_called()

    def test_selected_compiler_and_runtime_are_paired_unless_runtime_is_explicit(self):
        compiler = str(Path("fixture JDK 21/bin/javac").resolve())
        for explicit in (None, "chosen-java"):
            with self.subTest(runtime=explicit):
                args = SimpleNamespace(javac=None, java=explicit)
                overlay = SimpleNamespace(find_javac=lambda requested: compiler)
                # Stop after toolchain selection, before any archive preparation.
                with patch.object(REGRESSION, "module", side_effect=[overlay, ValueError("stop probe")]):
                    with self.assertRaisesRegex(ValueError, "stop probe"):
                        REGRESSION.qualify(args, {"steps": []})
                self.assertEqual(args.javac, compiler)
                self.assertEqual(args.java, explicit or str(Path(compiler).with_name("java")))


if __name__ == "__main__":
    unittest.main()
