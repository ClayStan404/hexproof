#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise publication and uncertain-push recovery using separate local Git repositories."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("public_source_publication", TOOLS / "publish-public-source.py")
PUBLICATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLICATION)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "private"
        self.public = self.root / "public.git"
        self.source.mkdir()
        self.command(self.source, "init", "--quiet", "--initial-branch=main")
        self.command(self.source, "config", "user.name", "Private Author")
        self.command(self.source, "config", "user.email", "private@example.invalid")
        self.command(self.source, "config", "maintenance.auto", "false")
        self.command(self.source, "config", "gc.auto", "0")
        (self.source / "README.md").write_text("Allowed source\n")
        (self.source / "deployment-secret").write_text("fixture-only secret\n")
        self.first = self.source_commit()
        self.command(self.root, "init", "--quiet", "--bare", str(self.public))
        self.policy = self.root / "policy.json"
        self.policy.write_text(json.dumps({"schemaVersion": 1, "include": ["README.md"], "exclude": []}))
        self.args = argparse.Namespace(
            source_repo=str(self.source), source_commit=self.first, source_ref="refs/heads/main",
            public_repo=str(self.public), public_ref="refs/heads/main", expected_public_head="none",
            receipt=str(self.root / "receipt.json"), policy=str(self.policy),
            baseline_source_commit=None, adopt_public_parent=False, prepare_only=False)

    def command(self, repo, *args, data=None, check=True):
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        env.update({"GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                    "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"})
        return subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null",
                               "-c", "commit.gpgSign=false", *args], input=data, env=env,
                              capture_output=True, check=check).stdout.decode().strip()

    def source_commit(self):
        self.command(self.source, "add", "--all")
        self.command(self.source, "commit", "--quiet", "--allow-empty", "-m", "Private review and operational details")
        return self.command(self.source, "rev-parse", "HEAD")

    def advance_source(self):
        (self.source / "README.md").write_text("New allowed source\n")
        self.args.source_commit = self.source_commit()
        return self.args.source_commit

    def next_intent(self, parent):
        self.args.expected_public_head = parent
        self.args.receipt = str(self.root / "next-receipt.json")

    def public_head(self):
        return self.command(self.public, "rev-parse", "refs/heads/main")

    def competing_commit(self, parent, message="Independent public change\n"):
        tree = self.command(self.public, "rev-parse", parent + "^{tree}")
        competing = self.command(self.public, "commit-tree", tree, "-p", parent, data=message.encode())
        self.command(self.public, "update-ref", "refs/heads/main", competing, parent)
        return competing

    def test_only_filtered_blobs_and_public_parents_are_pushed(self):
        first = PUBLICATION.publish(self.args)
        self.assertEqual(first["state"], "published")
        self.assertEqual(self.public_head(), first["publicCommit"])
        self.assertEqual(self.command(self.public, "ls-tree", "--name-only", self.public_head()), "README.md")
        self.assertEqual(self.command(self.public, "show", "HEAD:deployment-secret", check=False), "")
        missing = subprocess.run(["git", "-C", str(self.public), "cat-file", "-e", self.first], capture_output=True)
        self.assertNotEqual(missing.returncode, 0, "Private history must never enter the public object database")
        self.assertNotIn("Private review", self.command(self.public, "show", "-s", "--format=%B", self.public_head()))
        self.assertEqual(self.command(self.public, "rev-list", "--count", self.public_head()), "1")
        self.advance_source()
        self.next_intent(first["publicCommit"])
        second = PUBLICATION.publish(self.args)
        self.assertEqual(self.command(self.public, "show", "-s", "--format=%P", second["publicCommit"]), first["publicCommit"])
        self.assertEqual(self.command(self.public, "show", second["publicCommit"] + ":README.md"), "New allowed source")

    def test_preparation_is_reviewable_and_retry_is_idempotent(self):
        self.args.prepare_only = True
        prepared = PUBLICATION.publish(self.args)
        self.assertEqual(prepared["state"], "prepared")
        self.assertEqual(self.command(self.public, "show-ref", check=False), "")
        self.assertEqual(Path(self.args.receipt).stat().st_mode & 0o777, 0o600)
        self.args.prepare_only = False
        published = PUBLICATION.publish(self.args)
        self.assertEqual(published["publicCommit"], prepared["publicCommit"])
        self.assertEqual(PUBLICATION.publish(self.args), published)
        self.assertEqual(self.command(self.public, "rev-list", "--count", self.public_head()), "1")

    def test_lost_push_response_reconciles_before_testing_a_now_stale_source(self):
        real_git = PUBLICATION.git

        def lost_response(repo, *args, **kwargs):
            result = real_git(repo, *args, **kwargs)
            if args[0] == "push":
                raise OSError("simulated connection loss after remote acceptance")
            return result

        with mock.patch.object(PUBLICATION, "git", side_effect=lost_response):
            with self.assertRaisesRegex(OSError, "connection loss"):
                PUBLICATION.publish(self.args)
        self.assertEqual(json.loads(Path(self.args.receipt).read_text())["state"], "uncertain")
        self.advance_source()
        self.args.source_commit = self.first
        reconciled = PUBLICATION.publish(self.args)
        self.assertEqual(reconciled["state"], "published")
        self.assertEqual(reconciled["publicCommit"], self.public_head())

    def test_rejected_push_can_retry_the_identical_prepared_commit(self):
        real_git = PUBLICATION.git

        def rejected(repo, *args, **kwargs):
            if args[0] == "push":
                return subprocess.CompletedProcess(args, 1, b"", b"simulated transport failure")
            return real_git(repo, *args, **kwargs)

        with mock.patch.object(PUBLICATION, "git", side_effect=rejected):
            with self.assertRaisesRegex(PUBLICATION.PublicationError, "unconfirmed"):
                PUBLICATION.publish(self.args)
        saved = json.loads(Path(self.args.receipt).read_text())
        self.assertEqual(saved["state"], "uncertain")
        self.assertEqual(PUBLICATION.publish(self.args)["publicCommit"], saved["publicCommit"])

    def test_published_commit_is_reconciled_when_public_branch_has_advanced(self):
        published = PUBLICATION.publish(self.args)
        newer = self.competing_commit(published["publicCommit"])
        result = PUBLICATION.publish(self.args)
        self.assertEqual(result["state"], "published")
        self.assertEqual(result["observedPublicHead"], newer)
        self.assertEqual(self.public_head(), newer)

    def test_remote_race_is_rejected_by_ordinary_non_force_push(self):
        first = PUBLICATION.publish(self.args)
        self.advance_source()
        self.next_intent(first["publicCommit"])
        real_git = PUBLICATION.git
        competing = []

        def race(repo, *args, **kwargs):
            if args[0] == "push":
                competing.append(self.competing_commit(first["publicCommit"]))
            return real_git(repo, *args, **kwargs)

        with mock.patch.object(PUBLICATION, "git", side_effect=race):
            with self.assertRaisesRegex(PUBLICATION.PublicationError, "unconfirmed"):
                PUBLICATION.publish(self.args)
        self.assertEqual(self.public_head(), competing[0])
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "changed unexpectedly"):
            PUBLICATION.publish(self.args)

    def test_stale_source_is_not_published_after_preparation(self):
        self.args.prepare_only = True
        PUBLICATION.publish(self.args)
        self.advance_source()
        self.args.source_commit = self.first
        self.args.prepare_only = False
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "stale"):
            PUBLICATION.publish(self.args)
        self.assertEqual(self.command(self.public, "show-ref", check=False), "")

    def test_current_source_ref_cannot_regress_the_published_source(self):
        self.advance_source()
        published = PUBLICATION.publish(self.args)
        self.command(self.source, "update-ref", "refs/heads/main", self.first)
        self.args.source_commit = self.first
        self.next_intent(published["publicCommit"])
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "regress or diverge"):
            PUBLICATION.publish(self.args)
        self.assertEqual(self.public_head(), published["publicCommit"])

    def test_legacy_parent_requires_a_matching_export_baseline(self):
        first = PUBLICATION.publish(self.args)
        tree = self.command(self.public, "rev-parse", first["publicCommit"] + "^{tree}")
        legacy = self.command(self.public, "commit-tree", tree, data=b"Legacy filtered public source\n")
        self.command(self.public, "update-ref", "refs/heads/main", legacy)
        self.advance_source()
        self.next_intent(legacy)
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "baseline-source-commit"):
            PUBLICATION.publish(self.args)
        self.args.baseline_source_commit = self.args.source_commit
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "does not match"):
            PUBLICATION.publish(self.args)
        self.args.baseline_source_commit = self.first
        published = PUBLICATION.publish(self.args)
        self.assertEqual(self.command(self.public, "show", "-s", "--format=%P", published["publicCommit"]), legacy)

    def test_receipt_intent_and_credential_free_destination_are_bound(self):
        self.args.prepare_only = True
        PUBLICATION.publish(self.args)
        self.args.public_ref = "refs/heads/other"
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "different immutable"):
            PUBLICATION.publish(self.args)
        for value in ("https://token@github.com/owner/project.git", "ext::arbitrary command", str(self.source)):
            with self.subTest(value=value), self.assertRaises(PUBLICATION.PublicationError):
                PUBLICATION.public_location(self.source, value)
        self.command(self.source, "remote", "add", "origin", "git@github.com:owner/private.git")
        for value in ("https://github.com/owner/private.git", "https://GitHub.com/owner/private.git",
                      "https://github.com:443/owner/private.git"):
            with self.subTest(value=value), self.assertRaisesRegex(PUBLICATION.PublicationError, "private source remote"):
                PUBLICATION.public_location(self.source, value)
        with self.assertRaises(PUBLICATION.PublicationError):
            PUBLICATION.public_location(self.source, "https://github.com:444/owner/public.git")

    def test_explicit_legacy_adoption_records_unknown_mapping_and_still_requires_exact_parent(self):
        first = PUBLICATION.publish(self.args)
        tree = self.command(self.public, "rev-parse", first["publicCommit"] + "^{tree}")
        legacy = self.command(self.public, "commit-tree", tree, data=b"Legacy public source without a known private mapping\n")
        self.command(self.public, "update-ref", "refs/heads/main", legacy)
        self.advance_source()
        self.next_intent(legacy)
        self.args.adopt_public_parent = True
        self.args.prepare_only = True
        prepared = PUBLICATION.publish(self.args)
        self.assertEqual(prepared["historicalSourceMapping"], "unknown")
        self.assertIsNone(prepared["intent"]["baselineSourceCommit"])
        self.assertEqual(self.public_head(), legacy)
        self.args.prepare_only = False
        published = PUBLICATION.publish(self.args)
        self.assertEqual(self.command(self.public, "show", "-s", "--format=%P", published["publicCommit"]), legacy)
        self.advance_source()
        self.args.receipt = str(self.root / "third-receipt.json")
        self.args.expected_public_head = published["publicCommit"]
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "cannot bypass"):
            PUBLICATION.publish(self.args)
        unmarked = self.competing_commit(published["publicCommit"])
        self.args.expected_public_head = unmarked
        with self.assertRaisesRegex(PUBLICATION.PublicationError, "cannot bypass"):
            PUBLICATION.publish(self.args)

    def test_malformed_provenance_cannot_be_reinterpreted_as_unknown_legacy_history(self):
        first = PUBLICATION.publish(self.args)
        for trailer in (f"Hexproof-Source-Commit: {self.first.upper()}\n",
                        "hexproof-source-commit: malformed\n",
                        f"Hexproof-Source-Commit: {self.first}\nHexproof-Source-Commit: malformed\n"):
            with self.subTest(trailer=trailer):
                self.command(self.public, "update-ref", "refs/heads/main", first["publicCommit"])
                changed = self.competing_commit(first["publicCommit"], "Conflicting provenance\n\n" + trailer)
                self.next_intent(changed)
                self.args.adopt_public_parent = True
                with self.assertRaisesRegex(PUBLICATION.PublicationError, "malformed or ambiguous"):
                    PUBLICATION.publish(self.args)


if __name__ == "__main__":
    unittest.main()
