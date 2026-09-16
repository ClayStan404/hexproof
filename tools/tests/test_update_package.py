# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import argparse
from contextlib import closing
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

PATH = Path(__file__).resolve().parents[1] / "ui-automation/verify-update-package.py"
SPEC = importlib.util.spec_from_file_location("update_package", PATH)
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)
PACKAGE_ROOT = "Hexproof-1.2.0-linux-x86_64"


class UpdatePackageTests(unittest.TestCase):
    def downloaded_run(self, root):
        artifacts = root / "seat-1/artifacts"
        downloads = root / "seat-1/downloads"
        artifacts.mkdir(parents=True)
        downloads.mkdir()
        archive = downloads / (PACKAGE_ROOT + ".tar.gz")
        self.archive(archive, [self.binary_entry()])
        result = {"status": "passed", "scenario": "application-update", "downloadReady": True,
                  "sawDownload": True, "updaterError": "", "sourceVersion": "1.1.0",
                  "targetVersion": "1.2.0", "downloadPath": str(archive)}
        PACKAGE.write_json(artifacts / "result.json", result)
        evidence = {"schema": "hexproof.verified-download.v1", "producer": "native-runner",
                    "runId": "test-run", "seat": 1, "stage": 1,
                    "scenario": "application-update", "sourceVersion": "1.1.0", "targetVersion": "1.2.0",
                    "resultSha256": PACKAGE.digest(artifacts / "result.json"),
                    "path": str(archive), "bytes": archive.stat().st_size, "sha256": PACKAGE.digest(archive)}
        PACKAGE.write_json(artifacts / "download-evidence.json", evidence)
        PACKAGE.write_json(root / "environment.json", {"evidence": "native-qt-input", "runId": "test-run"})
        PACKAGE.write_json(root / "report.json", {"status": "passed", "runId": "test-run", "seats": [
            {"status": "passed", "seat": 1, "stage": 1, "scenarioResult": result,
             "verifiedDownload": {"artifact": "download-evidence.json",
                                  "sha256": PACKAGE.digest(artifacts / "download-evidence.json")}}]})
        return archive, artifacts

    def test_download_binding_accepts_unchanged_verified_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, _ = self.downloaded_run(root)
            found, _, version, provenance = PACKAGE.load_download(root, 1)
            self.assertEqual(found, archive)
            self.assertEqual(version, "1.2.0")
            self.assertEqual(provenance["archiveSha256"], PACKAGE.digest(archive))

    def test_download_binding_rejects_replacement_with_same_filename_and_version(self):
        for same_size in (False, True):
            with self.subTest(same_size=same_size), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive, _ = self.downloaded_run(root)
                if same_size:
                    changed = bytearray(archive.read_bytes())
                    changed[len(changed) // 2] ^= 1
                    archive.write_bytes(changed)
                else:
                    self.archive(archive, [self.binary_entry(), (PACKAGE_ROOT + "/changed", tarfile.REGTYPE, b"different payload")])
                with self.assertRaisesRegex(ValueError, "download.*binding|bound.*download"):
                    PACKAGE.load_download(root, 1)

    def test_download_binding_rejects_missing_or_mismatched_evidence(self):
        for change in ("missing", "different-run", "different-result", "missing-report-binding"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _, artifacts = self.downloaded_run(root)
                if change == "missing":
                    (artifacts / "download-evidence.json").unlink()
                elif change == "different-result":
                    PACKAGE.write_json(artifacts / "result.json", {"status": "passed"})
                else:
                    report = PACKAGE.read_json(root / "report.json")
                    if change == "different-run": report["runId"] = "unrelated-run"
                    else: report["seats"][0].pop("verifiedDownload")
                    PACKAGE.write_json(root / "report.json", report)
                with self.assertRaises((ValueError, OSError)):
                    PACKAGE.load_download(root, 1)

    def archive(self, path, entries):
        with tarfile.open(path, "w:gz") as archive:
            for name, kind, content in entries:
                entry = tarfile.TarInfo(name)
                entry.type = kind
                if kind == tarfile.REGTYPE:
                    entry.size = len(content)
                    entry.mode = 0o755
                    archive.addfile(entry, io.BytesIO(content))
                else:
                    entry.linkname = content
                    archive.addfile(entry)

    def binary_entry(self):
        return (PACKAGE_ROOT + "/bin/hexproof", tarfile.REGTYPE, b"#!/bin/sh\necho 'Hexproof 1.2.0'\n")

    def test_packaged_library_symlink_is_allowed_and_extracted_inside_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "release.tar.gz"
            self.archive(archive, [self.binary_entry(),
                                  (PACKAGE_ROOT + "/lib/libQt.so.6.11", tarfile.REGTYPE, b"library"),
                                  (PACKAGE_ROOT + "/lib/libQt.so.6", tarfile.SYMTYPE, "libQt.so.6.11")])
            binary, metadata = PACKAGE.safe_extract(archive, root / "extract", PACKAGE_ROOT)
            self.assertTrue(binary.stat().st_mode & 0o111)
            self.assertEqual(metadata["members"], 3)
            self.assertEqual((root / "extract" / PACKAGE_ROOT / "lib/libQt.so.6").read_bytes(), b"library")

    def test_unsafe_archive_rejected_before_creating_destination(self):
        bad_entries = [
            ("../outside", tarfile.REGTYPE, b"bad"),
            ("/outside", tarfile.REGTYPE, b"bad"),
            (PACKAGE_ROOT + "/../outside", tarfile.REGTYPE, b"bad"),
            (PACKAGE_ROOT + "/bin/hexproof", tarfile.REGTYPE, b"duplicate"),
            (PACKAGE_ROOT + "/bad", tarfile.SYMTYPE, "../../outside"),
            (PACKAGE_ROOT + "/bad", tarfile.SYMTYPE, "/outside"),
            (PACKAGE_ROOT + "/bad", tarfile.SYMTYPE, "missing"),
            (PACKAGE_ROOT + "/bad", tarfile.LNKTYPE, PACKAGE_ROOT + "/bin/hexproof"),
            (PACKAGE_ROOT + "/bad", tarfile.FIFOTYPE, ""),
            (PACKAGE_ROOT + "/bin/hexproof/child", tarfile.REGTYPE, b"bad"),
        ]
        for bad in bad_entries:
            with self.subTest(path=bad[0], content=bad[2]), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.archive(root / "release.tar.gz", [self.binary_entry(), bad])
                with self.assertRaises(ValueError):
                    PACKAGE.safe_extract(root / "release.tar.gz", root / "extract", PACKAGE_ROOT)
                self.assertFalse((root / "extract").exists())

    def test_archive_limits_and_existing_output_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.archive(root / "release.tar.gz", [self.binary_entry()])
            with mock.patch.object(PACKAGE, "MAX_BYTES", 4), self.assertRaises(ValueError):
                PACKAGE.safe_extract(root / "release.tar.gz", root / "extract", PACKAGE_ROOT)
            with mock.patch.object(PACKAGE, "MAX_MEMBERS", 0), self.assertRaises(ValueError):
                PACKAGE.safe_extract(root / "release.tar.gz", root / "extract", PACKAGE_ROOT)
            (root / "extract").mkdir()
            (root / "extract/keep").write_text("existing")
            with self.assertRaises(ValueError):
                PACKAGE.safe_extract(root / "release.tar.gz", root / "extract", PACKAGE_ROOT)
            self.assertEqual((root / "extract/keep").read_text(), "existing")

    def fixture(self, root):
        app = root / PACKAGE.APP_DATA
        app.mkdir(parents=True)
        with closing(sqlite3.connect(app / "cards.sqlite")) as database:
            database.execute("CREATE TABLE cards (name TEXT)")
            database.execute("INSERT INTO cards VALUES ('Island')")
            database.commit()
        (app / "decks.json").write_text(json.dumps({"decks": [{"name": "Fixture", "mainboard": [{"name": "Island"}]}]}))
        (app / "images").mkdir()
        (app / "images/island.jpg").write_bytes(b"test-art")
        (app / "card-cache.json").write_text(json.dumps({"imagePath": str(app / "images/island.jpg")}))
        (app / "session.json").write_text('{"secret": "not-copied"}')
        return app

    def test_clone_preserves_database_and_rebases_images_without_resume_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            self.fixture(source)
            original = PACKAGE.profile_snapshot(source)
            metadata = PACKAGE.clone_profile(source, root / "copy")
            copy = root / "copy" / PACKAGE.APP_DATA
            self.assertEqual(metadata, {"decks": 1, "imageFiles": 1})
            self.assertEqual(json.loads((copy / "card-cache.json").read_text())["imagePath"], str(copy / "images/island.jpg"))
            self.assertFalse((copy / "session.json").exists())
            self.assertEqual(PACKAGE.profile_snapshot(source), original)
            with closing(sqlite3.connect(copy / "cards.sqlite")) as database:
                self.assertEqual(database.execute("SELECT name FROM cards").fetchall(), [("Island",)])
            before = PACKAGE.profile_snapshot(root / "copy")
            (copy / "images/island.jpg").write_bytes(b"changed")
            self.assertEqual(PACKAGE.changed_files(before, PACKAGE.profile_snapshot(root / "copy")), ["images/island.jpg"])

    def test_source_image_links_and_empty_profiles_cannot_claim_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = self.fixture(root / "source")
            (app / "images/escape.jpg").symlink_to(root / "outside")
            with self.assertRaises(ValueError):
                PACKAGE.clone_profile(root / "source", root / "copy")
            (app / "images/escape.jpg").unlink()
            (app / "decks.json").write_text('{"decks": []}')
            with self.assertRaises(ValueError):
                PACKAGE.clone_profile(root / "source", root / "copy")

    def test_version_mismatch_and_nonzero_exit_are_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for code, stdout in [(0, "Hexproof 1.1.0\n"), (2, "Hexproof 1.2.0\n")]:
                with self.subTest(code=code, stdout=stdout), \
                        mock.patch.object(PACKAGE.subprocess, "run", return_value=subprocess.CompletedProcess([], code, stdout, "")), \
                        self.assertRaises(ValueError):
                    PACKAGE.check_version(root / "hexproof", "1.2.0", root, root)

    def test_default_preparation_never_claims_gui_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root / "source")
            archive = root / "release.tar.gz"
            self.archive(archive, [self.binary_entry()])
            args = argparse.Namespace(output=root / "output", source_run=root, seat=1, profile_run=None,
                                      profile=root / "source", launch=False)
            with mock.patch.object(PACKAGE, "load_download", return_value=(archive, PACKAGE_ROOT, "1.2.0", {})), \
                    mock.patch.object(PACKAGE, "launch_release") as launch:
                self.assertEqual(PACKAGE.run(args), 0)
                launch.assert_not_called()
            report = json.loads((root / "output/report.json").read_text())
            self.assertEqual(report["status"], "prepared")
            self.assertEqual(report["gui"], {"status": "not_run"})
            self.assertEqual(report["preservation"]["cloneDataChanged"], [])

    def test_launch_error_cannot_produce_pass_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root / "source")
            archive = root / "release.tar.gz"
            self.archive(archive, [self.binary_entry()])
            (root / "helper").write_text("test helper")
            args = argparse.Namespace(output=root / "output", source_run=root, seat=1, profile_run=None,
                                      profile=root / "source", launch=True, window_helper=root / "helper", settle_seconds=1)
            with mock.patch.object(PACKAGE, "load_download", return_value=(archive, PACKAGE_ROOT, "1.2.0", {})), \
                    mock.patch.object(PACKAGE, "launch_release", side_effect=ValueError("No owned window")):
                self.assertEqual(PACKAGE.run(args), 1)
            report = json.loads((root / "output/report.json").read_text())
            self.assertEqual(report["status"], "failed")
            self.assertIn("No owned window", report["reason"])

    def test_screenshot_rejects_blank_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "image.ppm").write_bytes(b"P6\n640 400\n255\n" + b"\0" * (640 * 400 * 3))
            with self.assertRaises(ValueError):
                PACKAGE.ppm_to_png(root / "image.ppm", root / "image.png")


if __name__ == "__main__":
    unittest.main()
