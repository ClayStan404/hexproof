#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "export-public-tree.sh"


class PublicExportTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name) / "private"
        self.root.mkdir()
        self.target = Path(directory.name) / "public"
        self.write("tools/export-public-tree.sh", SCRIPT.read_text(encoding="utf-8"))
        self.write("README.md", "Public readme\n")
        self.write("apps/example.py", "print('public')\n")
        self.write("docs/private-notes.md", "Private notes\n")
        self.write("tools/tests/test_deploy_script.py", "private deployment test\n")
        self.write("tools/tests/test_home_deployment.py", "private home deployment test\n")
        self.write("tools/package-home-node.py", "private home deployment packager\n")
        for name in (".github/workflows/ci.yml", ".clang-format", ".gitattributes", ".gitignore", "LICENSE",
                     "CHANGELOG.md", "THIRD-PARTY-NOTICES.md", "docs/development-policy.md",
                     "docs/rules-engine.md", "docs/player-hosted-forge.md", "docs/home-servers.md",
                     "docs/public-content.md", "packaging/README.md", "protocol/example.json",
                     "testdata/example.json", "third_party/README.md"):
            self.write(name, "Fixture\n")
        self.git("init", "--quiet")
        # Background Git maintenance must not race temporary-tree cleanup.
        self.git("config", "maintenance.auto", "false")
        self.git("config", "gc.auto", "0")
        self.git("add", ".")
        self.git("-c", "user.name=Export Test", "-c", "user.email=export@example.invalid",
                 "-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null",
                 "commit", "--quiet", "-m", "Fixture snapshot")

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args],
                              check=True, text=True, capture_output=True)

    def run_export(self):
        return subprocess.run(["bash", str(self.root / "tools/export-public-tree.sh"), str(self.target)],
                              text=True, capture_output=True, timeout=10)

    def test_private_changes_and_images_do_not_block_committed_export(self):
        self.write("docs/private-notes.md", "Edited private notes\n")
        self.write("docs/development-policy.md", "Edited internal development policy\n")
        image = self.write("hex-img/reference.png", "User reference\n")
        self.write("tools/tests/test_deploy_script.py", "changed private test\n")
        result = self.run_export()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / "README.md").read_text(), "Public readme\n")
        self.assertFalse((self.target / "docs/private-notes.md").exists())
        self.assertFalse((self.target / "docs/development-policy.md").exists())
        self.assertFalse((self.target / "hex-img").exists())
        self.assertFalse((self.target / "tools/tests/test_deploy_script.py").exists())
        self.assertFalse((self.target / "tools/tests/test_home_deployment.py").exists())
        self.assertFalse((self.target / "tools/package-home-node.py").exists())
        self.assertEqual(image.read_text(), "User reference\n")

    def test_committed_internal_policy_is_never_exported(self):
        result = self.run_export()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.target / "docs/development-policy.md").exists())
        self.assertTrue((self.root / "docs/development-policy.md").exists())
        self.assertTrue((self.target / "docs/rules-engine.md").exists())
        self.assertTrue((self.target / "docs/player-hosted-forge.md").exists())
        self.assertTrue((self.target / "docs/home-servers.md").exists())
        self.assertTrue((self.target / "docs/public-content.md").exists())
        self.assertTrue((self.target / ".gitattributes").exists())

    def test_modified_public_source_still_blocks_export(self):
        self.write("apps/example.py", "changed\n")
        result = self.run_export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Exported paths have uncommitted changes", result.stderr)
        self.assertFalse(self.target.exists())

    def test_staged_public_source_still_blocks_export(self):
        self.write("apps/example.py", "changed\n")
        self.git("add", "apps/example.py")
        self.assertNotEqual(self.run_export().returncode, 0)

    def test_untracked_public_source_is_not_silently_omitted(self):
        self.write("apps/new.py", "new\n")
        self.assertNotEqual(self.run_export().returncode, 0)

    def test_deleted_public_source_still_blocks_export(self):
        (self.root / "apps/example.py").unlink()
        self.assertNotEqual(self.run_export().returncode, 0)

    def test_nonempty_output_is_not_overwritten(self):
        self.target.mkdir()
        marker = self.target / "user-file"
        marker.write_text("preserve\n")
        self.assertNotEqual(self.run_export().returncode, 0)
        self.assertEqual(marker.read_text(), "preserve\n")


if __name__ == "__main__":
    unittest.main()
