#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Private working-directory/catalog controls; no real XMage/JVM required."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "engine-eval/xmage/bridge.py"
SPEC = importlib.util.spec_from_file_location("xmage_isolation_bridge", SOURCE)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


@unittest.skipUnless(sys.platform.startswith("linux"), "Catalog quiescence checks require Linux /proc")
class XMageIsolationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cwd = self.root / "checkout"
        (self.cwd / "db").mkdir(parents=True)
        self.catalog = self.cwd / "db/cards.h2.mv.db"
        self.catalog.write_bytes(b"closed-catalog-fixture" * 100)

    def profile(self, name="profile"):
        path = self.root / name
        path.mkdir()
        return path

    def test_private_copy_has_different_inode_and_records_hash_and_boundary(self):
        runtime, evidence = bridge.prepare_runtime(self.profile(), self.cwd)
        target = runtime / "db/cards.h2.mv.db"
        self.assertEqual(target.read_bytes(), self.catalog.read_bytes())
        self.assertNotEqual(target.stat().st_ino, self.catalog.stat().st_ino)
        self.assertEqual(evidence["sourceSha256"], evidence["destinationSha256"])
        self.assertEqual(evidence["destination"], str(target))
        self.assertIn("not an empty-catalog build", evidence["startupBoundary"])

    def test_four_read_only_copies_do_not_share_writable_database(self):
        profiles = [self.profile(f"profile-{n}") for n in range(4)]
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda p: bridge.prepare_runtime(p, self.cwd), profiles))
        targets = [runtime / "db/cards.h2.mv.db" for runtime, _ in results]
        self.assertEqual(len({p.stat().st_ino for p in targets} | {self.catalog.stat().st_ino}), 5)
        before = self.catalog.read_bytes()
        targets[0].write_bytes(b"private runtime writes")
        self.assertEqual(self.catalog.read_bytes(), before)
        self.assertTrue(all(p.read_bytes() == before for p in targets[1:]))

    def test_existing_runtime_rejected_without_overwriting_live_data(self):
        profile = self.profile()
        runtime, _ = bridge.prepare_runtime(profile, self.cwd)
        target = runtime / "db/cards.h2.mv.db"
        target.write_bytes(b"do not overwrite")
        with self.assertRaises(FileExistsError):
            bridge.prepare_runtime(profile, self.cwd)
        self.assertEqual(target.read_bytes(), b"do not overwrite")

    def test_runtime_symlink_and_source_symlink_rejected(self):
        profile = self.profile()
        outside = self.root / "outside"
        outside.mkdir()
        (profile / "runtime").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            bridge.prepare_runtime(profile, self.cwd)
        self.assertEqual(list(outside.iterdir()), [])
        link = self.root / "catalog-link.mv.db"
        link.symlink_to(self.catalog)
        with self.assertRaises(ValueError):
            bridge.prepare_runtime(self.profile("second"), self.cwd, link)

    def test_locked_catalog_rejected_before_creating_runtime(self):
        (self.catalog.parent / "cards.h2.lock.db").write_text("held by H2")
        profile = self.profile()
        with self.assertRaisesRegex(ValueError, "H2 lock"):
            bridge.prepare_runtime(profile, self.cwd)
        self.assertFalse((profile / "runtime").exists())

    def test_writable_descriptor_rejected_but_read_only_descriptor_allowed(self):
        with self.catalog.open("r+b"):
            with self.assertRaisesRegex(ValueError, "writable descriptors"):
                bridge.prepare_runtime(self.profile("writer"), self.cwd)
        with self.catalog.open("rb"):
            bridge.prepare_runtime(self.profile("reader"), self.cwd)

    def test_empty_and_missing_template_rejected(self):
        self.catalog.write_bytes(b"")
        with self.assertRaises(ValueError):
            bridge.prepare_runtime(self.profile("empty"), self.cwd)
        with self.assertRaises(ValueError):
            bridge.prepare_runtime(self.profile("missing"), self.cwd, self.root / "absent.mv.db")

    def test_source_changed_during_copy_is_rejected(self):
        digest = bridge.sha256_file
        changed = False

        def mutate_then_hash(path):
            nonlocal changed
            if not changed:
                self.catalog.write_bytes(b"changed while copied")
                changed = True
            return digest(path)

        with mock.patch.object(bridge, "sha256_file", side_effect=mutate_then_hash):
            with self.assertRaisesRegex(ValueError, "changed while being copied"):
                bridge.prepare_runtime(self.profile(), self.cwd)

    def test_corrupt_destination_is_rejected(self):
        digest = bridge.sha256_file

        def corrupt_then_hash(path):
            if path != self.catalog:
                path.write_bytes(b"corrupt copy")
            return digest(path)

        with mock.patch.object(bridge, "sha256_file", side_effect=corrupt_then_hash):
            with self.assertRaisesRegex(ValueError, "private copy differs"):
                bridge.prepare_runtime(self.profile(), self.cwd)

    def test_trace_and_history_not_copied_or_changed(self):
        trace = self.cwd / "db/cards.h2.trace.db"
        trace.write_text("old diagnostic evidence")
        history = self.cwd / "gamesHistory"
        history.mkdir()
        (history / "old.game").write_text("preserve history")
        runtime, _ = bridge.prepare_runtime(self.profile(), self.cwd)
        self.assertEqual([p.name for p in (runtime / "db").iterdir()], ["cards.h2.mv.db"])
        self.assertFalse((runtime / "gamesHistory").exists())
        self.assertEqual(trace.read_text(), "old diagnostic evidence")
        self.assertEqual((history / "old.game").read_text(), "preserve history")

    def test_relative_and_trailing_empty_classpath_preserve_original_meaning(self):
        (self.cwd / "classes").mkdir()
        command = ["java", "-cp", "classes" + os.pathsep]
        normalized = bridge.absolute_classpath(command, self.cwd)
        self.assertEqual(normalized[2], str(self.cwd / "classes") + os.pathsep + str(self.cwd))
        self.assertEqual(command[2], "classes" + os.pathsep)
        self.assertEqual(bridge.absolute_classpath(["java", "-cp", "absent-optional-directory"], self.cwd)[2],
                         str(self.cwd / "absent-optional-directory"))

    def launch_fixture(self, profile, workload=None):
        run = self.root / "compiled-run"
        run.mkdir(exist_ok=True)
        (self.cwd / "classes").mkdir(exist_ok=True)
        (run / "commands.json").write_text(json.dumps({"cwd": str(self.cwd), "run": [
            "java", "-Xmx2g", "-Duser.home=old", "-cp", "classes" + os.pathsep,
            "org.hexproof.eval.Qualification", "old-results.json"]}))
        args = [str(SOURCE), "--run-dir", str(run), "--profile", str(profile)]
        if workload:
            args += ["--workload", str(workload), "--workload-id", "fixture"]
        with mock.patch.object(sys, "argv", args), mock.patch.object(bridge.os, "chdir") as chdir, mock.patch.object(bridge.os, "execvp") as execute:
            bridge.main()
        return chdir, execute

    def test_launch_uses_private_cwd_and_absolute_classpath(self):
        profile = self.profile()
        chdir, execute = self.launch_fixture(profile)
        manifest = json.loads((profile / "bridge-command.json").read_text())
        chdir.assert_called_once_with(profile / "runtime")
        command = execute.call_args.args[1]
        self.assertEqual(command[command.index("-cp") + 1], str(self.cwd / "classes") + os.pathsep + str(self.cwd))
        self.assertIn(f"-Duser.home={profile}", command)
        self.assertEqual(manifest["cwd"], str(profile / "runtime"))
        self.assertEqual((profile / "bridge-source.py").read_bytes(), SOURCE.read_bytes())
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit) as failure:
            self.launch_fixture(profile)
        self.assertEqual(failure.exception.code, 2)
        self.assertIn("Profile already contains bridge evidence; use a fresh profile", stderr.getvalue())

    def test_profile_symlink_and_workload_symlink_are_not_followed(self):
        outside = self.profile("outside")
        link = self.root / "profile-link"
        link.symlink_to(outside, target_is_directory=True)
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit) as failure:
            self.launch_fixture(link)
        self.assertEqual(failure.exception.code, 2)
        self.assertIn("Profile must not be a symlink", stderr.getvalue())
        profile = self.profile()
        owner_file = self.root / "owner-workloads.json"
        owner_file.write_text("must survive")
        (profile / "workloads.json").symlink_to(owner_file)
        workload = self.root / "input.json"
        workload.write_text("{}")
        with self.assertRaises(FileExistsError):
            self.launch_fixture(profile, workload)
        self.assertEqual(owner_file.read_text(), "must survive")


if __name__ == "__main__":
    unittest.main()
