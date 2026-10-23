#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise immutable exports from real Git object databases, without candidate execution."""

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "public_source_export.py"
SPEC = importlib.util.spec_from_file_location("public_source_export", SCRIPT)
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class ImmutableExportTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.target = self.root / "output"
        self.policy = self.root / "trusted-policy.json"
        self.policy.write_text(json.dumps({"schemaVersion": 1, "include": ["README.md", "apps", "tools", ".gitattributes"],
                                           "exclude": ["tools/private.py"]}))
        self.write("README.md", "Public\n")
        self.write("apps/script.sh", "#!/bin/sh\nexit 0\n").chmod(0o755)
        self.write("tools/private.py", "excluded\n")
        self.write("docs/private.md", "private source detail\n")
        self.git("init", "--quiet")
        self.git("config", "user.name", "Export Test")
        self.git("config", "user.email", "export@example.invalid")
        self.git("config", "maintenance.auto", "false")
        self.git("config", "gc.auto", "0")
        self.commit = self.commit_all()

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def git(self, *args, input=None):
        return subprocess.check_output(["git", "-C", str(self.repo), "-c", "core.hooksPath=/dev/null",
                                        "-c", "commit.gpgSign=false", *args], input=input, stderr=subprocess.PIPE)

    def commit_all(self):
        self.git("add", "-A")
        self.git("commit", "--quiet", "-m", "Fixture snapshot")
        return self.git("rev-parse", "HEAD").decode().strip()

    def export(self, commit=None, target=None):
        return EXPORT.export_snapshot(self.repo, commit or self.commit, target or self.target, self.policy)

    def test_fixed_commit_ignores_new_head_and_dirty_files(self):
        self.write("README.md", "Later committed\n")
        self.commit_all()
        self.write("README.md", "Dirty worktree\n")
        result = self.export()
        self.assertEqual((self.target / "README.md").read_text(), "Public\n")
        self.assertEqual(result["sourceCommit"], self.commit)
        self.assertEqual(result["exportTreeDigest"], EXPORT.tree_digest(self.target))
        self.assertFalse((self.target / "docs/private.md").exists())
        self.assertFalse((self.target / "tools/private.py").exists())
        self.assertEqual(sorted(path.name for path in self.target.iterdir()), ["README.md", "apps"])

    def test_private_changes_preserve_export_digest(self):
        first = self.export()
        self.write("docs/private.md", "Other private content\n")
        second_commit = self.commit_all()
        second = self.export(second_commit, self.root / "second")
        self.assertNotEqual(first["sourceCommit"], second["sourceCommit"])
        self.assertEqual(first["exportTreeDigest"], second["exportTreeDigest"])
        self.assertEqual(first["exportPolicyDigest"], second["exportPolicyDigest"])

    def test_policy_digest_is_canonical_and_exclusions_are_bound(self):
        policy = json.loads(self.policy.read_text())
        initial = EXPORT.policy_digest(self.policy)
        self.policy.write_text(json.dumps(dict(reversed(list(policy.items()))), indent=4))
        self.assertEqual(initial, EXPORT.policy_digest(self.policy))
        policy["exclude"].append("apps")
        self.policy.write_text(json.dumps(policy))
        self.assertNotEqual(initial, EXPORT.policy_digest(self.policy))

    def test_trusted_policy_wins_and_candidate_scripts_are_not_executed(self):
        marker = self.root / "executed"
        self.write("tools/export-public-tree.sh", f"#!/bin/sh\ntouch {marker}\n").chmod(0o755)
        self.write("tools/public_export_policy.json", '{"include":["docs"]}')
        commit = self.commit_all()
        self.export(commit)
        self.assertFalse(marker.exists())
        self.assertFalse((self.target / "docs").exists())
        self.assertTrue((self.target / "README.md").exists())

    def test_digest_covers_bytes_modes_paths_and_link_targets(self):
        (self.repo / "apps/link").symlink_to("script.sh")
        self.write("apps/other.sh", "same fixture\n")
        commit = self.commit_all()
        self.export(commit)
        first = EXPORT.tree_digest(self.target)
        script = self.target / "apps/script.sh"
        script.chmod(0o644)
        self.assertNotEqual(first, EXPORT.tree_digest(self.target))
        script.chmod(0o755)
        self.assertEqual(first, EXPORT.tree_digest(self.target))
        script.write_text("Changed\n")
        changed = EXPORT.tree_digest(self.target)
        self.assertNotEqual(first, changed)
        link = self.target / "apps/link"
        link.unlink()
        link.symlink_to("other.sh")
        self.assertNotEqual(changed, EXPORT.tree_digest(self.target))
        entry = next(item for item in EXPORT.tree_manifest(self.target)["files"] if item["path"] == "apps/link")
        self.assertEqual(entry["linkTarget"], "other.sh")
        self.assertEqual(entry["sha256"], hashlib.sha256(b"other.sh").hexdigest())
        before = EXPORT.tree_digest(self.target)
        (self.target / "README.md").rename(self.target / "RENAMED.md")
        self.assertNotEqual(before, EXPORT.tree_digest(self.target))

    def test_tree_compare_ignores_only_explicit_root_git_metadata(self):
        self.export()
        other = self.root / "checkout"
        shutil.copytree(self.target, other, symlinks=True)
        subprocess.run(["git", "init", "--quiet", str(other)], check=True, capture_output=True)
        self.assertTrue(EXPORT.compare_trees(self.target, other, ignore_git=True))
        with self.assertRaises(EXPORT.ExportError):
            EXPORT.tree_digest(other)
        (other / "untracked.txt").write_text("not silently omitted")
        self.assertFalse(EXPORT.compare_trees(self.target, other, ignore_git=True))

    def test_ref_names_abbreviations_and_non_commit_objects_are_rejected(self):
        blob = self.git("rev-parse", "HEAD:README.md").decode().strip()
        tree = self.git("rev-parse", "HEAD^{tree}").decode().strip()
        for value in ("HEAD", "master", self.commit[:12], self.commit + "^{commit}", blob, tree):
            with self.subTest(value=value), self.assertRaises(EXPORT.ExportError):
                self.export(value)
        self.assertFalse(self.target.exists())

    def test_sha256_git_commit_is_supported(self):
        self.repo = self.root / "sha256-source"
        self.repo.mkdir()
        result = subprocess.run(["git", "-C", str(self.repo), "init", "--quiet", "--object-format=sha256"], capture_output=True)
        if result.returncode:
            self.skipTest("Installed Git has no SHA-256 repository support")
        self.git("config", "user.name", "Export Test")
        self.git("config", "user.email", "export@example.invalid")
        self.git("config", "maintenance.auto", "false")
        self.git("config", "gc.auto", "0")
        self.write("README.md", "SHA-256 source\n")
        commit = self.commit_all()
        self.assertEqual(len(commit), 64)
        self.assertEqual(self.export(commit)["sourceCommit"], commit)

    def test_unsafe_committed_paths_fail_before_target_creation(self):
        for name in ("apps/control\nname", "apps/back\\slash", "apps/windows:stream"):
            with self.subTest(name=name):
                path = self.write(name, "unsafe path")
                commit = self.commit_all()
                with self.assertRaises(EXPORT.ExportError):
                    self.export(commit)
                path.unlink()
                self.assertFalse(self.target.exists())

    def test_unsafe_policy_paths_are_rejected(self):
        for value in ("../docs", "/absolute", "apps/../../docs", "apps\\escape", ".git", ":(top)apps", "apps/*"):
            with self.subTest(value=value):
                self.policy.write_text(json.dumps({"schemaVersion": 1, "include": [value], "exclude": []}))
                with self.assertRaises(EXPORT.ExportError):
                    self.export()

    def test_duplicate_policy_fields_fail(self):
        self.policy.write_text('{"schemaVersion":1,"include":["README.md"],"exclude":[],"exclude":["README.md"]}')
        with self.assertRaisesRegex(EXPORT.ExportError, "Duplicate policy field"):
            self.export()

    def test_destination_confinement_and_preservation(self):
        alias = self.root / "source-alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        for path in (self.repo / "export", alias / "export", Path("relative")):
            with self.subTest(path=path), self.assertRaises(EXPORT.ExportError):
                self.export(target=path)
        self.target.mkdir()
        (self.target / "preserve").write_text("user data")
        with self.assertRaises(EXPORT.ExportError):
            self.export()
        self.assertEqual((self.target / "preserve").read_text(), "user data")

    def test_empty_destination_is_supported_but_symlink_destination_is_not(self):
        self.target.mkdir()
        self.export()
        alias = self.root / "alias"
        alias.symlink_to(self.root / "new-output", target_is_directory=True)
        with self.assertRaises(EXPORT.ExportError):
            self.export(target=alias)

    def test_escaping_private_absolute_chained_and_dangling_links_fail(self):
        for value in ("../../outside", "../docs/private.md", "/tmp/private", "missing", "second",
                      "script.sh/../script.sh", "script.sh/", "second/../script.sh"):
            with self.subTest(value=value):
                link = self.repo / "apps/link"
                if link.is_symlink():
                    link.unlink()
                link.symlink_to(value)
                if not (self.repo / "apps/second").is_symlink():
                    (self.repo / "apps/second").symlink_to("script.sh")
                commit = self.commit_all()
                with self.assertRaises(EXPORT.ExportError):
                    self.export(commit)
                self.assertFalse(self.target.exists())

    def test_archive_attributes_fail_before_publishing_target(self):
        for value in ("apps/** export-ignore\n", "README.md export-subst\n", "[attr]private export-ignore\n"):
            with self.subTest(value=value):
                self.write(".gitattributes", value)
                commit = self.commit_all()
                with self.assertRaisesRegex(EXPORT.ExportError, "Archive-changing"):
                    self.export(commit)
                self.assertFalse(self.target.exists())

    def test_filters_are_not_run_during_blob_export(self):
        marker = self.root / "filter-executed"
        self.write(".gitattributes", "README.md filter=untrusted\n")
        commit = self.commit_all()
        self.git("config", "filter.untrusted.smudge", f"touch {marker}")
        self.git("config", "filter.untrusted.clean", f"touch {marker}")
        self.git("config", "core.fsmonitor", f"touch {marker}")
        self.export(commit)
        self.assertFalse(marker.exists())
        self.assertEqual((self.target / "README.md").read_text(), "Public\n")

    def test_gitlinks_and_case_colliding_paths_are_rejected(self):
        self.git("update-index", "--add", "--cacheinfo", f"160000,{self.commit},apps/submodule")
        self.git("commit", "--quiet", "-m", "Gitlink fixture")
        commit = self.git("rev-parse", "HEAD").decode().strip()
        with self.assertRaisesRegex(EXPORT.ExportError, "Unsupported Git entry"):
            self.export(commit)
        self.git("rm", "--cached", "apps/submodule")
        self.write("apps/UPPER", "one")
        self.write("apps/upper", "two")
        commit = self.commit_all()
        with self.assertRaisesRegex(EXPORT.ExportError, "Colliding export paths"):
            self.export(commit)

    def test_manifest_stays_outside_public_tree(self):
        receipt = self.root / "private-receipt.json"
        command = ["python3", str(SCRIPT), "--repo", str(self.repo), "--commit", self.commit,
                   "--target", str(self.target), "--policy", str(self.policy), "--manifest"]
        failed = subprocess.run([*command, str(self.target / "manifest.json")], capture_output=True, text=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertFalse(self.target.exists())
        succeeded = subprocess.run([*command, str(receipt)], capture_output=True, text=True, umask=0)
        self.assertEqual(succeeded.returncode, 0, succeeded.stderr)
        self.assertEqual(json.loads(receipt.read_text())["sourceCommit"], self.commit)
        self.assertEqual(json.loads(succeeded.stdout), json.loads(receipt.read_text()))
        self.assertFalse((self.target / "manifest.json").exists())
        self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)

    def test_manifest_symlink_is_refused_without_exporting(self):
        receipt = self.root / "receipt-link.json"
        receipt.symlink_to(self.root / "unexpected.json")
        result = subprocess.run(["python3", str(SCRIPT), "--repo", str(self.repo), "--commit", self.commit,
                                 "--target", str(self.target), "--policy", str(self.policy),
                                 "--manifest", str(receipt)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.target.exists())
        self.assertFalse((self.root / "unexpected.json").exists())


if __name__ == "__main__":
    unittest.main()
