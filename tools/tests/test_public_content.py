#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("public_content", ROOT / "tools/public-content.py")
CONTENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTENT)
SPONSORS = ROOT / "apps/client-qt/config/content/sponsors.json"
ANNOUNCEMENTS = ROOT / "apps/client-qt/config/content/announcements.json"
AVATARS = ROOT / "apps/client-qt/assets/sponsors"


class PublicContentTests(unittest.TestCase):
    def test_package_preserves_payloads_and_referenced_avatars(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "package"
            index = CONTENT.package(SPONSORS, ANNOUNCEMENTS, AVATARS, output, 1)
            observed, files, documents = CONTENT.read_package(output)
            self.assertEqual(index, observed)
            self.assertEqual(len(documents["sponsors"]["sponsors"]), 9)
            self.assertEqual(len(files), 12)
            self.assertEqual(files[index["sponsors"]["path"]], SPONSORS.read_bytes())
            with self.assertRaises(ValueError):
                CONTENT.package(SPONSORS, ANNOUNCEMENTS, AVATARS, output, 2)

    def test_sponsors_can_be_removed_including_an_empty_roster(self):
        old = json.loads(SPONSORS.read_bytes())
        new = copy.deepcopy(old)
        new.update(revision=2, sponsors=[])
        CONTENT.validate_document("sponsors", new)
        CONTENT.validate_update(old, new, "sponsors")
        new["revision"] = 1
        with self.assertRaises(ValueError):
            CONTENT.validate_update(old, new, "sponsors")

    def test_announcements_retain_history_and_read_revisions(self):
        old = json.loads(ANNOUNCEMENTS.read_bytes())
        old["announcements"] = [{"id": "maintenance", "notificationRevision": 1,
                                 "title": {"en": "Maintenance"}, "body": {"en": "Details"},
                                 "publishedAt": "2026-09-23T00:00:00Z"}]
        CONTENT.validate_document("announcements", old)
        new = copy.deepcopy(old)
        new.update(revision=2, announcements=[])
        with self.assertRaisesRegex(ValueError, "complete announcement history"):
            CONTENT.validate_update(old, new, "announcements")
        new["announcements"] = copy.deepcopy(old["announcements"])
        new["announcements"][0]["withdrawn"] = True
        CONTENT.validate_update(old, new, "announcements")
        new["announcements"][0]["notificationRevision"] = 0
        with self.assertRaises(ValueError):
            CONTENT.validate_update(old, new, "announcements")

    def test_rejects_unsafe_paths_urls_duplicates_and_unresolved_selection(self):
        for path in ("../secret", "/absolute", "https://other/image", "images/%2e%2e/file", "image?x", "a//b"):
            self.assertFalse(CONTENT.safe_path(path), path)
        original = json.loads(SPONSORS.read_bytes())
        for profile in ("file:///etc/passwd", "https://user:pass@example.com", "https://example.com:0", "http://example.com"):
            document = copy.deepcopy(original)
            document["sponsors"][0]["profileUrl"] = profile
            with self.assertRaises(ValueError):
                CONTENT.validate_document("sponsors", document)
        document = copy.deepcopy(original)
        document["sponsors"].append(document["sponsors"][0])
        with self.assertRaises(ValueError):
            CONTENT.validate_document("sponsors", document)
        news = json.loads(ANNOUNCEMENTS.read_bytes())
        news["display"]["selectedIds"] = ["missing"]
        with self.assertRaises(ValueError):
            CONTENT.validate_document("announcements", news)

    def test_failed_validation_writes_no_package(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "sponsors.json"
            document = json.loads(SPONSORS.read_bytes())
            document["sponsors"][0]["avatar"]["sha256"] = "a" * 64
            source.write_text(json.dumps(document))
            output = Path(directory) / "package"
            with self.assertRaises(ValueError):
                CONTENT.package(source, ANNOUNCEMENTS, AVATARS, output, 1)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
