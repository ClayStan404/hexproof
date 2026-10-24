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
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.init(self.repo)
        (self.repo / ".gitignore").write_text("build/\n")
        (self.repo / "apps/client-qt").mkdir(parents=True)
        (self.repo / "apps/client-qt/CMakeLists.txt").write_text('set(HEXPROOF_VERSION "3.1.1")\n')
        (self.repo / "source-file").write_text("application source\n")
        (self.repo / "tools").mkdir()
        verifier = self.repo / "tools/verify.sh"
        verifier.write_text('''#!/bin/sh
set -eu
test "$#" = 1
test "$1" = --qml-per-file
test "$CTEST_PARALLEL_LEVEL" = 2
test -z "$GOFLAGS"
test -z "${GIT_DIR:-}"
test -z "${GIT_INDEX_FILE:-}"
test -z "${GIT_CONFIG_COUNT:-}"
mkdir -p build
printf 'run\n' >> build/verifier-count
case "${FIXTURE_VERIFY_BEHAVIOR:-pass}" in
  fail) echo 'Failed fixture gate'; exit 3 ;;
  dirty) echo changed >> source-file ;;
  commit) git -c commit.gpgSign=false commit --quiet --allow-empty -m changed ;;
esac
echo 'Complete fixture verification passed'
''')
        verifier.chmod(0o755)
        self.source_commit = self.commit(self.repo)
        self.receipt = self.repo / "build/release/verified.json"
        self.args = argparse.Namespace(repo=str(self.repo), receipt=str(self.receipt))
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
        self.git(repo, "remote", "add", "origin", f"https://github.com/{VERIFY.REPOSITORY}.git")

    def commit(self, repo):
        self.git(repo, "add", "--all")
        self.git(repo, "commit", "--quiet", "-m", "Fixture source")
        return self.git(repo, "rev-parse", "HEAD")

    def qualify(self):
        with redirect_stdout(io.StringIO()):
            return VERIFY.run(self.args)

    def prepare_publication(self):
        self.qualify()
        self.public_commit = self.source_commit
        self.public_tree = self.git(self.repo, "rev-parse", "HEAD^{tree}")
        return self.args

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
        with patch.dict(os.environ, GOFLAGS="-run=NoTestsShouldMatch",
                        GIT_DIR=str(self.root / "missing.git"),
                        GIT_INDEX_FILE=str(self.root / "missing-index"), GIT_CONFIG_COUNT="0"):
            first = self.qualify()
        self.assertEqual(first["sourceCommit"], self.source_commit)
        self.assertEqual(first["sourceRepository"], VERIFY.REPOSITORY)
        self.assertEqual(first["schemaVersion"], 2)
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
                target = self.repo / ("new-source" if mode == "untracked" else "source-file")
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
                self.git(self.repo, "update-index", "--" + flag, "source-file")
                (self.repo / "source-file").write_text("hidden changed bytes\n")
                self.assertEqual(self.git(self.repo, "status", "--porcelain"), "")
                with self.assertRaisesRegex(VERIFY.VerificationError, "flags before verification"):
                    self.qualify()
                self.assertFalse(self.receipt.exists())
                self.git(self.repo, "update-index", "--no-" + flag, "source-file")
                self.git(self.repo, "reset", "--hard", self.source_commit)
    def test_new_commit_requires_new_full_evidence(self):
        self.qualify()
        (self.repo / "source-file").write_text("next source\n")
        self.commit(self.repo)
        with self.assertRaisesRegex(VERIFY.VerificationError, "exact source"):
            self.qualify()

    def test_partial_failed_or_malformed_receipt_cannot_be_reused(self):
        receipt = self.qualify()
        changed_fields = {"profile": "quick", "result": "failed", "command": ["true"],
                          "sourceVersion": "3.0.0", "sourceTree": "a" * 40,
                          "schemaVersion": 1, "sourceRepository": "someone/else"}
        for name, value in changed_fields.items():
            self.receipt.write_text(json.dumps(dict(receipt, **{name: value})))
            with self.subTest(name=name), self.assertRaises(VERIFY.VerificationError):
                self.qualify()
        self.receipt.write_text("[]")
        with self.assertRaises(VERIFY.VerificationError):
            self.qualify()

    def test_output_cannot_overwrite_source_or_follow_symlinks(self):
        for path in (self.repo / "source-file", self.repo / "new.json"):
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

    def test_publish_validates_same_commit_and_sends_only_public_status(self):
        args = self.prepare_publication()
        with patch.object(VERIFY, "gh_api", side_effect=self.api):
            result = VERIFY.publish(args)
            VERIFY.publish(args)
        self.assertEqual(result["publicCommit"], self.public_commit)
        self.assertEqual(result["publicTree"], self.git(self.repo, "rev-parse", "HEAD^{tree}"))
        writes = [(path, payload) for path, payload in self.api_calls if payload is not None]
        self.assertEqual(len(writes), 1, "Reconciliation must not duplicate an existing success")
        public_payload = json.dumps(writes)
        for private in (str(self.repo), str(self.receipt), "application source"):
            self.assertNotIn(private, public_payload)
        self.assertEqual(set(writes[0][1]), {"state", "context", "description"})

    def test_wrong_missing_or_private_origin_blocks_run_and_publish(self):
        args = self.prepare_publication()
        for remote in ("https://github.com/someone/else.git",
                       "git@github.com:ClayStan404/hexproof-private.git",
                       "https://github.com/ClayStan404/hexproof.git.attacker.invalid",
                       "https://credential@github.com/ClayStan404/hexproof.git"):
            self.git(self.repo, "remote", "set-url", "origin", remote)
            with self.subTest(remote=remote), patch.object(VERIFY, "gh_api") as api:
                for operation in (VERIFY.run, VERIFY.publish):
                    with self.assertRaisesRegex(VERIFY.GitError, "official public repository"):
                        operation(args)
                api.assert_not_called()
        self.git(self.repo, "remote", "remove", "origin")
        with patch.object(VERIFY, "gh_api") as api, self.assertRaises(VERIFY.GitError):
            VERIFY.publish(args)
        api.assert_not_called()

    def test_push_destination_and_git_url_rewrites_cannot_bypass_origin_check(self):
        args = self.prepare_publication()
        settings = [("remote.origin.pushurl", "https://github.com/other/repo.git"),
                    ("url.https://github.com/other/repo.git.insteadOf",
                     f"https://github.com/{VERIFY.REPOSITORY}.git"),
                    ("url.https://github.com/other/repo.git.pushInsteadOf",
                     f"https://github.com/{VERIFY.REPOSITORY}.git")]
        for key, value in settings:
            self.git(self.repo, "config", key, value)
            with self.subTest(key=key), patch.object(VERIFY, "gh_api") as api:
                with self.assertRaisesRegex(VERIFY.GitError, "official public repository"):
                    VERIFY.publish(args)
                api.assert_not_called()
            self.git(self.repo, "config", "--unset", key)
        self.git(self.repo, "config", "--add", "remote.origin.url", "https://github.com/other/repo.git")
        with self.assertRaisesRegex(VERIFY.GitError, "official public repository"):
            VERIFY.publish(args)

    def test_official_https_and_ssh_origin_forms_are_accepted(self):
        for remote in (f"https://github.com/{VERIFY.REPOSITORY}",
                       f"git@github.com:{VERIFY.REPOSITORY}.git",
                       f"ssh://git@github.com/{VERIFY.REPOSITORY}.git"):
            self.git(self.repo, "remote", "set-url", "origin", remote)
            with self.subTest(remote=remote):
                self.assertEqual(self.qualify()["sourceCommit"], self.source_commit)

    def test_inherited_git_redirection_cannot_change_verified_checkout(self):
        with patch.dict(os.environ, GIT_DIR=str(self.root / "missing.git"),
                        GIT_INDEX_FILE=str(self.root / "missing-index"),
                        GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="remote.origin.url",
                        GIT_CONFIG_VALUE_0="https://github.com/other/repo.git"):
            self.assertEqual(VERIFY.clean_source(self.repo)["sourceCommit"], self.source_commit)

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

    def test_new_local_commit_cannot_publish_previous_receipt(self):
        args = self.prepare_publication()
        (self.repo / "extra-source").write_text("unverified")
        self.commit(self.repo)
        with patch.object(VERIFY, "gh_api") as api:
            with self.assertRaisesRegex(VERIFY.VerificationError, "exact source"):
                VERIFY.publish(args)
            api.assert_not_called()

    def test_source_or_log_changes_during_github_lookup_block_status_write(self):
        args = self.prepare_publication()
        receipt = json.loads(self.receipt.read_text())
        log = Path(receipt["logPath"])
        log_text = log.read_text()
        for mutation in ("source", "commit", "log", "receipt", "origin"):
            def mutate_on_lookup(path, payload=None):
                result = self.api(path, payload)
                if path == f"repos/{VERIFY.REPOSITORY}":
                    if mutation == "source":
                        (self.repo / "source-file").write_text("changed")
                    elif mutation == "commit":
                        self.git(self.repo, "commit", "--quiet", "--allow-empty", "-m", "changed")
                    elif mutation == "log":
                        log.write_text("changed")
                    elif mutation == "receipt":
                        self.receipt.write_text(json.dumps(dict(receipt, sourceCommit="a" * 40)))
                    else:
                        self.git(self.repo, "remote", "set-url", "origin", "https://github.com/other/repo.git")
                return result
            with self.subTest(mutation=mutation), patch.object(VERIFY, "gh_api", side_effect=mutate_on_lookup):
                with self.assertRaises((VERIFY.VerificationError, VERIFY.GitError)):
                    VERIFY.publish(args)
            self.git(self.repo, "reset", "--hard", self.source_commit)
            self.git(self.repo, "remote", "set-url", "origin", f"https://github.com/{VERIFY.REPOSITORY}.git")
            log.write_text(log_text)
            self.receipt.write_text(json.dumps(receipt))
        self.assertFalse(any(payload for _, payload in self.api_calls))

    def test_publish_cli_has_no_second_checkout_or_export_receipt(self):
        for option in ("--publication-receipt", "--public-repo"):
            with self.subTest(option=option), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as failed:
                    VERIFY.main(["publish", "--receipt", str(self.receipt), option, "unused"])
                self.assertEqual(failed.exception.code, 2)

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
