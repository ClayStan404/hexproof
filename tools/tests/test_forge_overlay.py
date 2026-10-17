# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check adapter identity and safe, reproducible source/bytecode packaging."""

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("forge_overlay", ROOT / "third_party/forge-runtime/build-overlay.py")
OVERLAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OVERLAY)


class ForgeOverlayTests(unittest.TestCase):
    def test_printing_data_participates_in_runtime_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            host = Path(temporary) / "host"
            shutil.copytree(OVERLAY.HOST, host)
            with patch.object(OVERLAY, "HOST", host):
                before, records = OVERLAY.identity()
                name = "src/main/resources/org/hexproof/forge/printing-aliases.tsv"
                self.assertIn(name, records)
                resource = host / name
                resource.write_text(resource.read_text() + "# new reviewed catalog revision\n")
                after, _ = OVERLAY.identity()
                self.assertNotEqual(before, after)

    def test_helper_identity_covers_current_native_sources(self):
        identity, records = OVERLAY.identity()
        source = (ROOT / "apps/server/internal/forgehost/identity.go").read_text()
        self.assertEqual(re.search(r'const RuntimeID = "([^"]+)"', source)[1], identity)
        self.assertGreater(len(records), 10)
        base = json.loads(OVERLAY.BASE_MANIFEST.read_text())
        self.assertEqual(re.search(r'const BaseRuntimeID = "([^"]+)"', source)[1], base["runtimeId"])

    def test_only_java_paths_enter_the_overlay(self):
        delta = (OVERLAY.HOST / "native-hooks.patch").read_text()
        self.assertGreater(len(OVERLAY.patched_paths(delta)), 10)
        for name in ("../../outside.java", "/tmp/outside.java", "forge-game/other.txt"):
            with self.assertRaises(ValueError):
                OVERLAY.patched_paths(f"diff --git a/{name} b/{name}\n")

    def test_deterministic_archives_and_pinned_offline_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first, second = root / "first.jar", root / "second.jar"
            OVERLAY.write_zip(first, {"b.class": b"two", "a.class": b"one"})
            OVERLAY.write_zip(second, {"a.class": b"one", "b.class": b"two"})
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist(), ["a.class", "b.class"])
            pin = {"size": first.stat().st_size, "sha256": hashlib.sha256(first.read_bytes()).hexdigest()}
            self.assertEqual(OVERLAY.pinned_file(pin, root, first), first)
            first.write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "checksum"):
                OVERLAY.pinned_file(pin, root, first)


if __name__ == "__main__":
    unittest.main()
