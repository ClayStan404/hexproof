# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise offline distribution integrity, reproducibility and publication."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("forge_offline", ROOT / "tools/package-forge-offline.py")
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class ForgeOfflinePackTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.forge, self.java = self.root / "forge.tar.gz", self.root / "java.zip"
        self.forge.write_bytes(b"pinned forge payload")
        self.java.write_bytes(b"pinned java payload")

        def asset(path, archive_format):
            return {"size": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "format": archive_format, "url": "https://example.invalid/" + path.name}

        self.manifest = {"forge": asset(self.forge, "tar.gz"),
                         "java": {"windows-amd64": asset(self.java, "zip")}}
        self.raw = json.dumps(self.manifest).encode()

    def build(self, output):
        return PACK.build_pack(self.raw, "windows-amd64", self.forge, self.java, output)

    def test_reproducible_pack_preserves_archives_and_pins(self):
        output, again = self.root / "one.hexproof-forgepack", self.root / "two.hexproof-forgepack"
        report = self.build(output)
        self.build(again)
        self.assertEqual(output.read_bytes(), again.read_bytes())
        self.assertEqual(report["sha256"], hashlib.sha256(output.read_bytes()).hexdigest())
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.namelist(), ["forge-pack.json", "forge.tar.gz", "java.zip"])
            self.assertEqual(archive.read("forge.tar.gz"), self.forge.read_bytes())
            self.assertEqual(archive.read("java.zip"), self.java.read_bytes())
            self.assertEqual(json.loads(archive.read("forge-pack.json")), {
                "schemaVersion": 1, "packageId": hashlib.sha256(self.raw).hexdigest()[:20],
                "platform": "windows-amd64"})
        with self.assertRaises(FileExistsError):
            self.build(output)
        self.assertEqual(output.read_bytes(), again.read_bytes())

    def test_invalid_inputs_do_not_publish_partial_files(self):
        for data in (b"x", b"X" * self.java.stat().st_size):
            with self.subTest(data=data):
                self.java.write_bytes(data)
                output = self.root / "invalid.hexproof-forgepack"
                with self.assertRaises(ValueError):
                    self.build(output)
                self.assertFalse(output.exists())
                self.assertEqual(list(self.root.glob(".forge-pack-*")), [])
        with self.assertRaisesRegex(ValueError, "Unsupported platform"):
            PACK.build_pack(self.raw, "unknown", self.forge, self.java, self.root / "unknown")

    def test_archive_lookup_accepts_original_and_cached_names(self):
        asset = self.manifest["forge"]
        self.assertEqual(PACK.archive_path(asset, None, self.root), self.forge)
        cached = self.root / f"{asset['sha256']}.{asset['format']}"
        self.forge.rename(cached)
        self.assertEqual(PACK.archive_path(asset, None, self.root), cached)
        self.assertEqual(PACK.archive_path(asset, cached, None), cached)
        with self.assertRaisesRegex(ValueError, "Provide the unchanged archive"):
            PACK.archive_path(asset, None, None)


if __name__ == "__main__":
    unittest.main()
