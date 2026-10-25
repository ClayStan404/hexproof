# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Feedback component provenance validation with isolated GitHub/ZIP fixtures."""

import base64
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import types
import unittest
import zipfile
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("feedback_component_tests", ROOT / "deploy/feedback/component.py")
COMPONENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPONENT)


class FeedbackComponentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.report = self.root / "report"
        self.report.mkdir()
        workflow = self.root / COMPONENT.WORKFLOW
        workflow.parent.mkdir(parents=True)
        workflow.write_bytes(b"name: Synthetic trusted feedback workflow\n")
        root_patch = patch.object(COMPONENT, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        self.head = "a" * 40
        self.repo = "fixture/public"
        self.package_name = "hexproof-feedback-3.1.0-linux-amd64.tar.gz"
        self.package_bytes = b"synthetic tar bytes, intentionally not extracted by this component"
        self.responses = {
            "actions/runs/123": {"id": 123, "repository": {"id": 10, "full_name": self.repo},
                "head_repository": {"id": 10, "full_name": self.repo}, "event": "workflow_dispatch",
                "status": "completed", "conclusion": "success", "head_sha": self.head,
                "head_branch": "master", "path": COMPONENT.WORKFLOW, "workflow_id": 20, "run_attempt": 1},
            "actions/artifacts/456": {"id": 456, "name": f"hexproof-feedback-{self.head}-linux-amd64",
                "expired": False, "workflow_run": {"id": 123, "head_sha": self.head,
                                                   "repository_id": 10, "head_repository_id": 10}},
            "actions/workflows/feedback.yml": {"id": 20, "path": COMPONENT.WORKFLOW},
            f"contents/{COMPONENT.WORKFLOW}?ref={self.head}": {"encoding": "base64", "type": "file",
                "path": COMPONENT.WORKFLOW, "content": base64.b64encode(workflow.read_bytes()).decode()},
            "actions/runs/123/attempts/1/jobs?per_page=100": [{"jobs": [{"name": "Build feedback service",
                "status": "completed", "conclusion": "success", "steps": [
                    {"name": name, "conclusion": "success"} for name in
                    ("Verify feedback service", "Attest feedback package", "Upload feedback package")]}]}],
        }
        self.set_archive([(self.package_name, self.package_bytes, stat.S_IFREG | 0o644)])
        self.commands = []
        self.attestation_error = None
        self.after_attestation = lambda: None
        self.backend = types.SimpleNamespace(github=self.github)
        download_patch = patch.object(COMPONENT.subprocess, "run", side_effect=self.download)
        self.download_mock = download_patch.start()
        self.addCleanup(download_patch.stop)

    def set_archive(self, entries):
        raw = io.BytesIO()
        with zipfile.ZipFile(raw, "w") as bundle:
            for name, payload, mode in entries:
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = mode << 16
                bundle.writestr(entry, payload)
        self.archive = raw.getvalue()
        self.pin_archive()

    def pin_archive(self):
        self.responses["actions/artifacts/456"].update(
            digest="sha256:" + hashlib.sha256(self.archive).hexdigest(), size_in_bytes=len(self.archive))

    def github(self, *args):
        self.commands.append(args)
        if args[:2] == ("attestation", "verify"):
            if self.attestation_error:
                raise self.attestation_error
            self.after_attestation()
            return '[{"verified":true}]'
        self.assertEqual(args[0], "api")
        return json.dumps(self.responses[args[-1].removeprefix("repos/fixture/public/")])

    def download(self, args, *, stdout, check, timeout):
        self.assertEqual(args, ["gh", "api", "repos/fixture/public/actions/artifacts/456/zip"])
        self.assertTrue(check)
        self.assertEqual(timeout, 600)
        stdout.write(self.archive)
        return subprocess.CompletedProcess(args, 0)

    def fetch(self, **overrides):
        arguments = dict(backend=self.backend, repo=self.repo, version="3.1.0", arch="amd64",
                         report=self.report, run_id=123, artifact_id=456, head_sha=self.head)
        arguments.update(overrides)
        return COMPONENT.fetch_component(**arguments)

    def test_verified_bytes_have_exact_attestation_and_private_provenance(self):
        record, provenance = self.fetch()
        self.assertEqual(Path(record["path"]).read_bytes(), self.package_bytes)
        self.assertEqual(record["sha256"], hashlib.sha256(self.package_bytes).hexdigest())
        self.assertEqual(provenance, {
            "mode": "actions-feedback-update", "repository": self.repo, "repositoryId": 10,
            "version": "3.1.0", "headSha": self.head, "runId": 123, "runAttempt": 1,
            "artifactId": 456, "artifactDigest": "sha256:" + hashlib.sha256(self.archive).hexdigest(),
            "artifactSize": len(self.archive), "workflowSha256": hashlib.sha256(
                (self.root / COMPONENT.WORKFLOW).read_bytes()).hexdigest(), "architecture": "amd64",
            "packageSha256": record["sha256"], "componentAttested": True})
        self.assertIn(("attestation", "verify", record["path"], "--repo", self.repo,
            "--signer-workflow", self.repo + "/" + COMPONENT.WORKFLOW, "--source-digest", self.head,
            "--source-ref", "refs/heads/master", "--format", "json"), self.commands)
        self.assertEqual(json.loads((self.report / "component-provenance.json").read_text()), provenance)
        self.assertEqual(json.loads((self.report / "feedback-component-attestation.json").read_text()),
                         [{"verified": True}])
        self.assertEqual(len(list(self.report.iterdir())), 4)
        for path in self.report.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.commands.count(("api", "repos/fixture/public/actions/runs/123")), 2)

    def test_arm64_is_explicit_and_bound_to_artifact_and_package(self):
        self.package_name = "hexproof-feedback-3.1.0-linux-arm64.tar.gz"
        self.set_archive([(self.package_name, self.package_bytes, stat.S_IFREG | 0o644)])
        self.responses["actions/artifacts/456"]["name"] = f"hexproof-feedback-{self.head}-linux-arm64"
        record, provenance = self.fetch(arch="arm64")
        self.assertEqual(Path(record["path"]).name, self.package_name)
        self.assertEqual(provenance["architecture"], "arm64")

    def test_invalid_inputs_never_contact_github(self):
        for changes in ({"repo": "other/../../repo"}, {"version": "3.1.0/escape"}, {"arch": "x86_64"},
                        {"run_id": True}, {"artifact_id": 0}, {"head_sha": "main"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.fetch(**changes)
        self.assertEqual(self.commands, [])
        self.download_mock.assert_not_called()

    def test_wrong_run_repository_source_workflow_or_artifact_is_rejected_before_download(self):
        original = copy.deepcopy(self.responses)
        cases = [
            ("actions/runs/123", "head_branch", "feature"),
            ("actions/runs/123", "head_sha", "b" * 40),
            ("actions/runs/123", "repository", {"id": 10, "full_name": "other/repo"}),
            ("actions/runs/123", "head_repository", {"id": 10, "full_name": "fork/repo"}),
            ("actions/runs/123", "head_repository", {"id": 99, "full_name": self.repo}),
            ("actions/runs/123", "event", "push"),
            ("actions/runs/123", "status", "in_progress"),
            ("actions/runs/123", "conclusion", "failure"),
            ("actions/runs/123", "run_attempt", 0),
            ("actions/runs/123", "workflow_id", 21),
            ("actions/workflows/feedback.yml", "path", ".github/workflows/release.yml"),
            ("actions/artifacts/456", "expired", True),
            ("actions/artifacts/456", "name", "unrelated-artifact"),
            ("actions/artifacts/456", "digest", None),
            ("actions/artifacts/456", "size_in_bytes", COMPONENT.MAX_BYTES + 1),
            ("actions/artifacts/456", "workflow_run", {"id": 124, "head_sha": self.head,
                                                       "repository_id": 10, "head_repository_id": 10}),
            (f"contents/{COMPONENT.WORKFLOW}?ref={self.head}", "content", base64.b64encode(b"unreviewed").decode()),
        ]
        for path, key, value in cases:
            with self.subTest(path=path, key=key):
                self.responses = copy.deepcopy(original)
                self.responses[path][key] = value
                with self.assertRaises(ValueError):
                    self.fetch()
        self.download_mock.assert_not_called()

    def test_job_and_all_required_steps_must_be_exact_successes(self):
        key = "actions/runs/123/attempts/1/jobs?per_page=100"
        original = copy.deepcopy(self.responses[key])
        for failure in ("job-name", "job-failed", "extra-job", "verify", "attest", "upload", "duplicate-step"):
            with self.subTest(failure=failure):
                self.responses[key] = copy.deepcopy(original)
                job = self.responses[key][0]["jobs"][0]
                if failure == "job-name":
                    job["name"] += " (unreviewed)"
                elif failure == "job-failed":
                    job["conclusion"] = "failure"
                elif failure == "extra-job":
                    self.responses[key][0]["jobs"].append(copy.deepcopy(job))
                elif failure == "duplicate-step":
                    job["steps"].append(copy.deepcopy(job["steps"][0]))
                else:
                    job["steps"][("verify", "attest", "upload").index(failure)]["conclusion"] = "skipped"
                with self.assertRaises(ValueError):
                    self.fetch()
        self.download_mock.assert_not_called()

    def test_zip_digest_and_size_are_checked_before_signature(self):
        original = self.archive
        for failure in ("digest", "size"):
            with self.subTest(failure=failure):
                self.report = self.root / failure
                self.report.mkdir()
                self.archive = (b"X" + original[1:]) if failure == "digest" else original + b"extra"
                with self.assertRaisesRegex(ValueError, "digest or size"):
                    self.fetch()
        self.assertFalse(any(command[0] == "attestation" for command in self.commands))

    def test_signed_metadata_does_not_make_a_corrupt_zip_acceptable(self):
        self.archive = b"not a ZIP archive"
        self.pin_archive()
        with self.assertRaisesRegex(ValueError, "Invalid feedback artifact ZIP"):
            self.fetch()
        self.assertFalse(any(command[0] == "attestation" for command in self.commands))

    def test_zip_crc_failure_is_rejected_even_when_archive_digest_matches(self):
        offset = self.archive.index(self.package_bytes)
        self.archive = self.archive[:offset] + b"X" + self.archive[offset + 1:]
        self.pin_archive()
        with self.assertRaisesRegex(ValueError, "Invalid feedback artifact ZIP"):
            self.fetch()

    def test_unexpected_zip_entries_and_special_files_are_rejected(self):
        for name, mode in (("../escape", stat.S_IFREG | 0o644),
                           (self.package_name, stat.S_IFLNK | 0o777),
                           (self.package_name, stat.S_IFIFO | 0o600),
                           (self.package_name, stat.S_IFCHR | 0o600)):
            with self.subTest(name=name, mode=mode):
                self.report = self.root / str(mode)
                self.report.mkdir()
                self.set_archive([(name, self.package_bytes, mode)])
                with self.assertRaisesRegex(ValueError, "entry, type or size"):
                    self.fetch()
        self.assertFalse((self.root / "escape").exists())

    def test_extra_package_is_rejected(self):
        self.set_archive([(self.package_name, self.package_bytes, stat.S_IFREG | 0o644),
                          ("extra.tar.gz", b"extra", stat.S_IFREG | 0o644)])
        with self.assertRaisesRegex(ValueError, "exactly one"):
            self.fetch()

    def test_uncompressed_entry_size_is_bounded_before_reading(self):
        # A small ZIP must not bypass the independent uncompressed package cap.
        raw = bytearray(self.archive)
        central = raw.index(b"PK\x01\x02")
        raw[central + 24:central + 28] = (COMPONENT.MAX_BYTES + 1).to_bytes(4, "little")
        self.archive = bytes(raw)
        self.pin_archive()
        with self.assertRaisesRegex(ValueError, "entry, type or size"):
            self.fetch()
        self.assertFalse((self.report / self.package_name).exists())

    def test_signature_failure_never_claims_attested_component(self):
        self.attestation_error = subprocess.CalledProcessError(1, "gh attestation verify")
        with self.assertRaises(subprocess.CalledProcessError):
            self.fetch()
        self.assertFalse((self.report / "component-provenance.json").exists())

    def test_metadata_change_after_signature_is_rejected(self):
        def mutate():
            self.responses["actions/artifacts/456"]["digest"] = "sha256:" + "b" * 64
        self.after_attestation = mutate
        with self.assertRaisesRegex(ValueError, "provenance changed"):
            self.fetch()
        self.assertFalse((self.report / "component-provenance.json").exists())

    def test_package_change_during_signature_is_rejected(self):
        self.after_attestation = lambda: (self.report / self.package_name).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "package changed"):
            self.fetch()

    def test_preexisting_report_link_is_not_followed(self):
        victim = self.root / "victim"
        victim.write_bytes(b"preserved")
        (self.report / "feedback-component-artifact.zip").symlink_to(victim)
        with self.assertRaises(FileExistsError):
            self.fetch()
        self.assertEqual(victim.read_bytes(), b"preserved")
        self.download_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
