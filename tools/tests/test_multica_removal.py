# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Local withdrawal containment never becomes native purge acknowledgement."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("multica_removal", ROOT / "tools/multica-removal.py")
REMOVAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REMOVAL)


def manifest():
    return {"schemaVersion": 1, "caseId": "00000000-0000-4000-8000-000000000001",
            "binding": "a" * 64, "revocationRevision": 4,
            "family": {"issues": ["issue-1", "issue-2"], "tasks": ["task-1"],
                       "inventoryEvidence": ["inventory-1"]},
            "containmentEvidence": ["dispatch-disabled-1", "task-stopped-1"],
            "localCopies": [{"id": "task-env-1", "path": "task-1"}],
            "nativeResiduals": [{"id": "task-1", "surface": "execution-history", "evidence": ["readback-1"]}],
            "inventoryGaps": ["unqualified-session-purge"]}


class MulticaRemovalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "task-artifacts"
        self.source.mkdir()
        self.copy = self.source / "task-1"
        (self.copy / "logs").mkdir(parents=True)
        (self.copy / "logs/worker.log").write_text("synthetic removed contribution")
        (self.source / "unrelated").write_text("keep")
        self.destination = self.root / "quarantine"

    def tearDown(self):
        if self.destination.exists():
            for path in self.destination.glob("copy-*"):
                os.chmod(path, 0o700 if path.is_dir() else 0o600)
        self.temporary.cleanup()

    def test_plan_inspects_metadata_without_moving_or_opening_content(self):
        with mock.patch.object(Path, "read_bytes", side_effect=AssertionError("content read")), \
                mock.patch.object(Path, "read_text", side_effect=AssertionError("content read")):
            report = REMOVAL.quarantine_copies(manifest(), self.source, self.destination, False)
        self.assertTrue(self.copy.exists())
        self.assertFalse(self.destination.exists())
        self.assertFalse(report["removed"])
        self.assertFalse(report["receiverAcknowledgementSupported"])
        self.assertEqual(report["nativeVerification"], "not-performed")
        self.assertEqual(report["localResiduals"], [{"id": "task-env-1", "state": "retained-at-source"}])
        self.assertNotIn("synthetic removed contribution", json.dumps(report))

    def test_apply_moves_only_explicit_copy_and_reports_bytes_retained(self):
        report = REMOVAL.quarantine_copies(manifest(), self.source, self.destination, True)
        self.assertFalse(self.copy.exists())
        self.assertEqual((self.source / "unrelated").read_text(), "keep")
        self.assertEqual(stat.S_IMODE((self.destination / "copy-0000").stat().st_mode), 0)
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.destination / "report.json").stat().st_mode), 0o600)
        self.assertEqual(json.loads((self.destination / "report.json").read_text()), report)
        self.assertEqual(report["localCopies"][0]["state"], "quarantined")
        self.assertEqual(report["localResiduals"], [{"id": "task-env-1", "state": "retained-in-quarantine"}])
        self.assertEqual(report["declaredNativeResiduals"], manifest()["nativeResiduals"])

    def test_all_copies_are_preflighted_before_first_move(self):
        (self.copy / "escape").symlink_to(self.source / "unrelated")
        document = manifest()
        document["localCopies"].insert(0, {"id": "unrelated", "path": "unrelated"})
        with self.assertRaisesRegex(ValueError, "Symlink"):
            REMOVAL.quarantine_copies(document, self.source, self.destination, True)
        self.assertTrue((self.source / "unrelated").exists())
        self.assertFalse(self.destination.exists())

    def test_overlaps_hardlinks_and_symlink_ancestors_are_rejected(self):
        document = manifest()
        document["localCopies"].append({"id": "nested", "path": "task-1/logs"})
        with self.assertRaisesRegex(ValueError, "overlap"):
            REMOVAL.quarantine_copies(document, self.source, self.destination, True)
        os.link(self.copy / "logs/worker.log", self.source / "outside-hardlink")
        with self.assertRaisesRegex(ValueError, "Hard-linked"):
            REMOVAL.quarantine_copies(manifest(), self.source, self.destination, True)
        alias = self.root / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            REMOVAL.quarantine_copies(manifest(), alias, self.destination, True)
        self.assertFalse(self.destination.exists())

    def test_mid_apply_failure_leaves_private_exact_partial_report(self):
        document = manifest()
        document["localCopies"].append({"id": "other-copy", "path": "unrelated"})
        (self.source / "not-reached").write_text("synthetic later copy")
        document["localCopies"].append({"id": "later-copy", "path": "not-reached"})
        real_rename = Path.rename

        def fail_second(path, target):
            if path.name == "unrelated":
                raise OSError("synthetic move failure")
            return real_rename(path, target)

        with mock.patch.object(Path, "rename", fail_second), self.assertRaisesRegex(ValueError, "partial report"):
            REMOVAL.quarantine_copies(document, self.source, self.destination, True)
        report = json.loads((self.destination / "report.json").read_text())
        self.assertEqual([row["state"] for row in report["localCopies"]], ["quarantined", "unverified", "pending"])
        self.assertEqual(report["localResiduals"], [
            {"id": "task-env-1", "state": "retained-in-quarantine"},
            {"id": "other-copy", "state": "unverified"},
            {"id": "later-copy", "state": "retained-at-source"}])
        self.assertFalse(report["removed"])
        self.assertTrue((self.source / "unrelated").exists())

    def test_cli_defaults_to_plan_and_apply_records_local_retention(self):
        path = self.root / "manifest.json"
        path.write_text(json.dumps(manifest()))
        command = [sys.executable, str(ROOT / "tools/multica-removal.py"), str(path),
                   "--source-root", str(self.source), "--quarantine-root", str(self.destination)]
        plan = subprocess.run(command, capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(plan.stdout)["mode"], "plan")
        self.assertFalse(self.destination.exists())
        applied = subprocess.run(command + ["--apply"], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(applied.stdout)["localResiduals"], [
            {"id": "task-env-1", "state": "retained-in-quarantine"}])
        refused = subprocess.run(command + ["--apply"], capture_output=True, text=True)
        self.assertNotEqual(refused.returncode, 0)
        self.assertNotIn("synthetic removed contribution", plan.stdout + applied.stdout + refused.stderr)

    def test_purge_deletes_only_selected_directory_and_file_without_native_ack(self):
        (self.source / "attachment").write_text("synthetic case attachment")
        document = manifest()
        document["localCopies"].append({"id": "attachment-1", "path": "attachment"})
        report = REMOVAL.quarantine_copies(document, self.source, self.destination, True, True)
        self.assertEqual(report["operation"], "purge")
        self.assertFalse(self.copy.exists())
        self.assertFalse((self.source / "attachment").exists())
        self.assertEqual((self.source / "unrelated").read_text(), "keep")
        self.assertEqual([row["state"] for row in report["localCopies"]], ["purged", "purged"])
        for row in report["localCopies"]:
            self.assertFalse(row["sourcePresent"])
            self.assertFalse(row["destinationPresent"])
            self.assertFalse((self.destination / row["destination"]).exists())
        self.assertEqual(report["localResiduals"], [])
        self.assertEqual(report["declaredNativeResiduals"], document["nativeResiduals"])
        self.assertEqual(report["inventoryGaps"], document["inventoryGaps"])
        self.assertFalse(report["removed"])
        self.assertFalse(report["receiverAcknowledgementSupported"])
        self.assertEqual(json.loads((self.destination / "report.json").read_text()), report)

    def test_partial_purge_records_deleted_unverified_and_untouched_copies(self):
        other = self.source / "other-task"
        other.mkdir()
        (other / "delete-first").write_text("synthetic partial copy")
        (other / "remains").write_text("synthetic remaining copy")
        document = manifest()
        document["localCopies"] += [{"id": "other-task", "path": "other-task"},
                                    {"id": "later-copy", "path": "unrelated"}]
        real_purge = REMOVAL.purge_copy

        def fail_second(target, entry):
            if entry["id"] == "other-task":
                os.chmod(target, 0o700)
                (target / "delete-first").unlink()
                raise OSError("synthetic partial deletion")
            real_purge(target, entry)

        with mock.patch.object(REMOVAL, "purge_copy", fail_second), self.assertRaisesRegex(ValueError, "partial report"):
            REMOVAL.quarantine_copies(document, self.source, self.destination, True, True)
        report = json.loads((self.destination / "report.json").read_text())
        self.assertEqual([row["state"] for row in report["localCopies"]], ["purged", "unverified", "pending"])
        self.assertEqual(report["localResiduals"], [
            {"id": "other-task", "state": "unverified"},
            {"id": "later-copy", "state": "retained-at-source"}])
        self.assertFalse(report["localCopies"][1]["sourcePresent"])
        self.assertTrue(report["localCopies"][1]["destinationPresent"])
        self.assertEqual(stat.S_IMODE((self.destination / "copy-0001").stat().st_mode), 0)
        os.chmod(self.destination / "copy-0001", 0o700)
        self.assertTrue((self.destination / "copy-0001/remains").exists())
        self.assertFalse((self.destination / "copy-0001/delete-first").exists())
        self.assertEqual((self.source / "unrelated").read_text(), "keep")
        self.assertFalse(report["removed"])

    def test_cli_purge_requires_apply_and_then_verifies_local_deletion(self):
        path = self.root / "manifest.json"
        path.write_text(json.dumps(manifest()))
        command = [sys.executable, str(ROOT / "tools/multica-removal.py"), str(path),
                   "--source-root", str(self.source), "--quarantine-root", str(self.destination), "--purge"]
        refused = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(refused.returncode, 0)
        self.assertTrue(self.copy.exists())
        self.assertFalse(self.destination.exists())
        applied = subprocess.run(command + ["--apply"], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(applied.stdout)["localResiduals"], [])
        self.assertFalse(self.copy.exists())
        self.assertFalse((self.destination / "copy-0000").exists())

    def test_purge_refuses_platform_without_symlink_safe_rmtree(self):
        with mock.patch.object(REMOVAL.shutil.rmtree, "avoids_symlink_attacks", False), \
                self.assertRaisesRegex(ValueError, "safe directory purge"):
            REMOVAL.quarantine_copies(manifest(), self.source, self.destination, True, True)
        self.assertTrue(self.copy.exists())
        self.assertFalse(self.destination.exists())

    def test_manifest_rejects_unknown_fields_missing_stop_evidence_and_unsafe_paths(self):
        for change in ({"acknowledged": True}, {"containmentEvidence": []},
                       {"revocationRevision": True}, {"schemaVersion": True},
                       {"localCopies": [{"id": "copy", "path": "../outside"}]},
                       {"localCopies": [{"id": "copy", "path": "/absolute"}]},
                       {"localCopies": [{"id": "copy", "path": "task-1/./logs"}]}):
            with self.subTest(change=change):
                path = self.root / "manifest.json"
                path.write_text(json.dumps(dict(copy.deepcopy(manifest()), **change)))
                with self.assertRaises(ValueError):
                    REMOVAL.read_manifest(path)
        path = self.root / "manifest.json"
        path.write_text('{"schemaVersion":1,"schemaVersion":1}')
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            REMOVAL.read_manifest(path)


if __name__ == "__main__":
    unittest.main()
