#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise release evidence with local Git fixtures and a fake GitHub boundary."""

import argparse
from contextlib import redirect_stderr, redirect_stdout
import io
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("release_verification", TOOLS / "release-verification.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class ReleaseVerificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / "private"
        self.repo.mkdir()
        self.init(self.repo)
        (self.repo / ".gitignore").write_text("build/\n")
        (self.repo / "apps/client-qt").mkdir(parents=True)
        (self.repo / "apps/client-qt/CMakeLists.txt").write_text('set(HEXPROOF_VERSION "3.1.1")\n')
        (self.repo / "private-notes").write_text("PRIVATE TASK DETAILS\n")
        (self.repo / "tools").mkdir()
        (self.repo / "tools/private-config").write_text("EXCLUDED PRIVATE CONFIG\n")
        (self.repo / "tools/public_export_policy.json").write_text(json.dumps(
            {"schemaVersion": 1, "include": [".gitignore", "apps", "tools"],
             "exclude": ["tools/private-config"]}))
        verifier = self.repo / "tools/verify.sh"
        verifier.write_text('''#!/bin/sh
set -eu
test "$#" = 1
test "$1" = --qml-per-file
test "$CTEST_PARALLEL_LEVEL" = 2
test -z "$GOFLAGS"
mkdir -p build
printf 'run\n' >> build/verifier-count
case "${FIXTURE_VERIFY_BEHAVIOR:-pass}" in
  fail) echo 'Failed fixture gate'; exit 3 ;;
  dirty) echo changed >> private-notes ;;
  commit) git -c commit.gpgSign=false commit --quiet --allow-empty -m changed ;;
esac
echo 'Complete fixture verification passed'
''')
        verifier.chmod(0o755)
        self.source_commit = self.commit(self.repo)
        self.receipt = self.repo / "build/release/verified.json"
        self.args = argparse.Namespace(repo=str(self.repo), receipt=str(self.receipt))
        self.public = self.root / "public"
        self.api_calls = []
        self.statuses = []

    def git(self, repo, *args):
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        return subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null",
                               "-c", "commit.gpgSign=false", *args], env=env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def init(self, repo):
        self.git(repo, "init", "--quiet", "--initial-branch=main")
        self.git(repo, "config", "user.name", "Fixture")
        self.git(repo, "config", "user.email", "fixture@example.invalid")

    def commit(self, repo):
        self.git(repo, "add", "--all")
        self.git(repo, "commit", "--quiet", "-m", "Fixture source")
        return self.git(repo, "rev-parse", "HEAD")

    def qualify(self):
        with redirect_stdout(io.StringIO()):
            return VERIFY.run(self.args)

    def prepare_publication(self):
        self.qualify()
        exported = VERIFY.export_snapshot(self.repo, self.source_commit, self.public,
                                          self.repo / "tools/public_export_policy.json")
        self.init(self.public)
        self.public_commit = self.commit(self.public)
        self.public_tree = self.git(self.public, "rev-parse", "HEAD^{tree}")
        self.publication = {"state": "published", "publicCommit": self.public_commit,
                            "export": exported,
                            "intent": {"sourceCommit": self.source_commit,
                                       "publicRepository": f"git@github.com:{VERIFY.REPOSITORY}.git",
                                       "exportPolicyDigest": exported["exportPolicyDigest"]}}
        self.publication_path = self.repo / "build/publication.json"
        self.write_publication()
        return argparse.Namespace(repo=str(self.repo), receipt=str(self.receipt),
                                  publication_receipt=str(self.publication_path), public_repo=str(self.public))

    def write_publication(self):
        self.publication_path.write_text(json.dumps(self.publication))

    def api(self, path, payload=None):
        self.api_calls.append((path, payload))
        if path == f"repos/{VERIFY.REPOSITORY}":
            return {"full_name": VERIFY.REPOSITORY, "private": False}
        if path == f"repos/{VERIFY.REPOSITORY}/git/commits/{self.public_commit}":
            return {"sha": self.public_commit, "tree": {"sha": self.public_tree}}
        if path == f"repos/{VERIFY.REPOSITORY}/commits/{self.public_commit}/statuses?per_page=100&page=1":
            return self.statuses
        if path == f"repos/{VERIFY.REPOSITORY}/statuses/{self.public_commit}" and payload:
            self.statuses.insert(0, dict(payload))
            return dict(payload)
        raise AssertionError(f"Unexpected API call: {path}")

    def success_status(self):
        return {"context": VERIFY.CONTEXT, "state": "success",
                "description": VERIFY.description("3.1.1", self.public_tree)}

    def test_complete_run_writes_private_receipt_and_reuses_only_exact_source(self):
        with patch.dict(os.environ, GOFLAGS="-run=NoTestsShouldMatch"):
            first = self.qualify()
        self.assertEqual(first["sourceCommit"], self.source_commit)
        self.assertEqual(first["profile"], "full-v1")
        self.assertEqual(first["command"], ["tools/verify.sh", "--qml-per-file"])
        self.assertEqual(Path(first["logPath"]).stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.receipt.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.qualify(), first)
        self.assertEqual((self.repo / "build/verifier-count").read_text().splitlines(), ["run"])
        self.assertEqual(self.git(self.repo, "status", "--porcelain"), "")

    def test_failed_verification_retains_log_without_success_receipt(self):
        with patch.dict(os.environ, FIXTURE_VERIFY_BEHAVIOR="fail"):
            with self.assertRaisesRegex(VERIFY.VerificationError, "checks failed"):
                self.qualify()
        self.assertFalse(self.receipt.exists())
        self.assertIn("Failed fixture gate", next(self.receipt.parent.glob("*.log")).read_text())

    def test_dirty_or_changed_source_cannot_gain_passing_receipt(self):
        for behavior in ("dirty", "commit"):
            with self.subTest(behavior=behavior):
                with patch.dict(os.environ, FIXTURE_VERIFY_BEHAVIOR=behavior):
                    with self.assertRaises(VERIFY.VerificationError):
                        self.qualify()
                self.assertFalse(self.receipt.exists())
                self.git(self.repo, "reset", "--hard", self.source_commit)

    def test_initial_staged_unstaged_and_untracked_changes_are_rejected(self):
        for mode in ("unstaged", "staged", "untracked"):
            with self.subTest(mode=mode):
                target = self.repo / ("new-source" if mode == "untracked" else "private-notes")
                target.write_text("changed\n")
                if mode == "staged":
                    self.git(self.repo, "add", target.name)
                with self.assertRaisesRegex(VERIFY.VerificationError, "Commit all source changes"):
                    self.qualify()
                self.assertFalse(self.receipt.exists())
                self.git(self.repo, "reset", "--hard", self.source_commit)
                if mode == "untracked":
                    target.unlink()

    def test_missing_or_tampered_log_invalidates_receipt(self):
        receipt = self.qualify()
        log = Path(receipt["logPath"])
        log.write_text("different result")
        with self.assertRaisesRegex(VERIFY.VerificationError, "checksum changed"):
            self.qualify()
        log.unlink()
        with self.assertRaisesRegex(VERIFY.VerificationError, "missing"):
            self.qualify()

    def test_index_flags_cannot_hide_modified_source(self):
        for flag in ("assume-unchanged", "skip-worktree"):
            with self.subTest(flag=flag):
                self.git(self.repo, "update-index", "--" + flag, "private-notes")
                (self.repo / "private-notes").write_text("hidden changed bytes\n")
                self.assertEqual(self.git(self.repo, "status", "--porcelain"), "")
                with self.assertRaisesRegex(VERIFY.VerificationError, "flags before verification"):
                    self.qualify()
                self.assertFalse(self.receipt.exists())
                self.git(self.repo, "update-index", "--no-" + flag, "private-notes")
                self.git(self.repo, "reset", "--hard", self.source_commit)
    def test_new_commit_requires_new_full_evidence(self):
        self.qualify()
        (self.repo / "private-notes").write_text("next source\n")
        self.commit(self.repo)
        with self.assertRaisesRegex(VERIFY.VerificationError, "exact source"):
            self.qualify()

    def test_partial_failed_or_malformed_receipt_cannot_be_reused(self):
        receipt = self.qualify()
        changed_fields = {"profile": "quick", "result": "failed", "command": ["true"],
                          "sourceVersion": "3.0.0", "sourceTree": "a" * 40,
                          "schemaVersion": True}
        for name, value in changed_fields.items():
            self.receipt.write_text(json.dumps(dict(receipt, **{name: value})))
            with self.subTest(name=name), self.assertRaises(VERIFY.VerificationError):
                self.qualify()
        self.receipt.write_text("[]")
        with self.assertRaises(VERIFY.VerificationError):
            self.qualify()

    def test_output_cannot_overwrite_source_or_follow_symlinks(self):
        for path in (self.repo / "private-notes", self.repo / "new.json"):
            with self.subTest(path=path):
                with self.assertRaises(VERIFY.VerificationError):
                    VERIFY.run(argparse.Namespace(repo=str(self.repo), receipt=str(path)))
        link = self.root / "linked"
        link.symlink_to(self.root / "target", target_is_directory=True)
        with self.assertRaisesRegex(VERIFY.VerificationError, "symlinks"):
            VERIFY.run(argparse.Namespace(repo=str(self.repo), receipt=str(link / "evidence.json")))

    def test_cli_has_no_quick_scope_or_arbitrary_command_bypass(self):
        for option in ("--quick", "--scope", "--command"):
            with self.subTest(option=option):
                with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failed:
                    VERIFY.main(["run", "--receipt", str(self.receipt), option])
                self.assertEqual(failed.exception.code, 2)

    def test_publish_validates_mapping_and_sends_only_public_status(self):
        args = self.prepare_publication()
        with patch.object(VERIFY, "gh_api", side_effect=self.api):
            result = VERIFY.publish(args)
            VERIFY.publish(args)
        self.assertEqual(result["publicCommit"], self.public_commit)
        self.assertNotIn("tools/private-config", self.git(self.public, "ls-tree", "-r", "--name-only", "HEAD").splitlines())
        writes = [(path, payload) for path, payload in self.api_calls if payload is not None]
        self.assertEqual(len(writes), 1, "Reconciliation must not duplicate an existing success")
        public_payload = json.dumps(writes)
        for private in (self.source_commit, str(self.repo), str(self.receipt),
                        "PRIVATE TASK DETAILS", "EXCLUDED PRIVATE CONFIG"):
            self.assertNotIn(private, public_payload)
        self.assertEqual(set(writes[0][1]), {"state", "context", "description"})

    def test_stale_export_state_commit_policy_or_destination_blocks_publication(self):
        args = self.prepare_publication()
        original = json.loads(json.dumps(self.publication))
        mutations = [lambda data: data.update(state="prepared"),
                     lambda data: data["intent"].update(sourceCommit="a" * 40),
                     lambda data: data["intent"].update(exportPolicyDigest="b" * 64),
                     lambda data: data["intent"].update(publicRepository="https://github.com/other/repo.git"),
                     lambda data: data["export"].update(exportTreeDigest="c" * 64),
                     lambda data: data.update(publicCommit="d" * 40)]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.publication = json.loads(json.dumps(original))
                mutation(self.publication)
                self.write_publication()
                with patch.object(VERIFY, "gh_api") as api:
                    with self.assertRaises(VERIFY.VerificationError):
                        VERIFY.publish(args)
                    api.assert_not_called()

    def test_cached_receipt_cannot_overwrite_a_revoked_public_status(self):
        args = self.prepare_publication()
        revoked = [dict(self.success_status(), state=state) for state in ("failure", "error", "pending")]
        revoked += [dict(self.success_status(), description="conflicting evidence"),
                    dict(self.success_status(), context=VERIFY.CONTEXT.upper(), state="failure")]
        for status in revoked:
            self.statuses = [status, self.success_status()]
            with self.subTest(status=status), patch.object(VERIFY, "gh_api", side_effect=self.api):
                with self.assertRaises(VERIFY.VerificationError):
                    VERIFY.publish(args)
        self.assertFalse(any(payload for _, payload in self.api_calls))

    def test_extra_public_source_file_blocks_even_when_receipt_names_that_commit(self):
        args = self.prepare_publication()
        (self.public / "extra-source").write_text("unverified")
        self.publication["publicCommit"] = self.commit(self.public)
        self.write_publication()
        with patch.object(VERIFY, "gh_api") as api:
            with self.assertRaisesRegex(VERIFY.VerificationError, "committed files differ"):
                VERIFY.publish(args)
            api.assert_not_called()

    def test_github_tree_or_repository_mismatch_blocks_write(self):
        args = self.prepare_publication()
        for mismatch in ("tree", "private", "repository", "commit"):
            def wrong_api(path, payload=None):
                response = self.api(path, payload)
                if "/git/commits/" in path:
                    if mismatch == "tree":
                        response["tree"]["sha"] = "f" * 40
                    if mismatch == "commit":
                        response["sha"] = "e" * 40
                elif path == f"repos/{VERIFY.REPOSITORY}":
                    if mismatch == "private":
                        response["private"] = True
                    if mismatch == "repository":
                        response["full_name"] = "someone/else"
                return response
            with self.subTest(mismatch=mismatch), patch.object(VERIFY, "gh_api", side_effect=wrong_api):
                with self.assertRaises(VERIFY.VerificationError):
                    VERIFY.publish(args)
        self.assertFalse(any(payload for _, payload in self.api_calls))

    def test_check_requires_latest_exact_context_version_and_tree(self):
        self.prepare_publication()
        args = argparse.Namespace(repository=VERIFY.REPOSITORY, commit=self.public_commit, version="3.1.1")
        success = self.success_status()
        bad_lists = [[], [dict(success, state="failure"), success],
                     [dict(success, state="pending"), success],
                     [dict(success, context=VERIFY.CONTEXT.upper(), state="failure"), success],
                     [dict(success, context="unrelated-ci")],
                     [dict(success, description=VERIFY.description("3.1.0", self.public_tree))],
                     [dict(success, description=VERIFY.description("3.1.1", "f" * 40))]]
        with patch.object(VERIFY, "gh_api", side_effect=self.api):
            for statuses in bad_lists:
                self.statuses = statuses
                with self.subTest(statuses=statuses), self.assertRaises(VERIFY.VerificationError):
                    VERIFY.check(args)
            self.statuses = [success, dict(success, state="failure")]
            self.assertEqual(VERIFY.check(args)["state"], "success")
            args.repository = "someone/else"
            with self.assertRaises(VERIFY.VerificationError):
                VERIFY.check(args)

    def test_status_search_paginates_without_falling_back_past_newer_failure(self):
        self.prepare_publication()
        replies = [[{"context": "other", "state": "success"}] * 100,
                   [dict(self.success_status(), state="failure"), self.success_status()]]
        with patch.object(VERIFY, "gh_api", side_effect=replies) as api:
            self.assertEqual(VERIFY.latest_status(self.public_commit)["state"], "failure")
        self.assertIn("page=2", api.call_args_list[-1].args[0])


if __name__ == "__main__":
    unittest.main()
