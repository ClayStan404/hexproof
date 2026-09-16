# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise managed patch application against disposable real Git checkouts."""

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "native_forge_builder", ROOT / "third_party/forge-runtime/build-native.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


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


if __name__ == "__main__":
    unittest.main()
