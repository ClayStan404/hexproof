#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("keyword_reference", ROOT / "tools/check-keyword-reference.py")
REFERENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REFERENCE)


class KeywordReferenceTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(REFERENCE.CATALOG.read_text())
        self.manifest = json.loads(REFERENCE.MANIFEST.read_text())

    def test_complete_offline_source_index_and_bilingual_content(self):
        REFERENCE.validate(self.catalog, self.manifest)
        self.assertEqual(len(self.catalog["entries"]), 264)
        self.assertEqual(self.catalog["coverage"]["actions"], 70)
        self.assertEqual(self.catalog["coverage"]["abilities"], 194)

    def test_unicode_heading_and_general_prose_exclusion(self):
        rules = ("701.1. General introduction\r\n701.2. Activate\r\n"
                 "701.2a Subrule is not a heading\r\n702.1. General introduction\r\n"
                 "702.186. ∞ (Infinity)\r\n703.1. Outside the index\r\n").encode("utf-8-sig")
        self.assertEqual(REFERENCE.extract_headings(rules), [
            {"rule": "701.2", "english": "Activate", "category": "action"},
            {"rule": "702.186", "english": "∞ (Infinity)", "category": "ability"},
        ])

    def test_missing_uncommon_keyword_wrong_heading_and_duplicate_fail(self):
        for change in ("missing", "name", "duplicate"):
            with self.subTest(change=change):
                catalog = copy.deepcopy(self.catalog)
                if change == "missing":
                    catalog["entries"] = [e for e in catalog["entries"] if e["rule"] != "702.186"]
                elif change == "name":
                    catalog["entries"][-1]["english"] = "Incorrect name"
                else:
                    catalog["entries"].append(catalog["entries"][-1])
                with self.assertRaisesRegex(ValueError, "every pinned"):
                    REFERENCE.validate(catalog, self.manifest)

    def test_empty_translation_markup_and_unfinished_content_fail(self):
        for value in ("", "<b>Flying</b>", "Content verification in progress.", "invalid\x00text"):
            with self.subTest(value=value):
                self.catalog["entries"][0]["summaryZh"] = value
                with self.assertRaises(ValueError):
                    REFERENCE.validate(self.catalog, self.manifest)

    def test_changed_source_fails_before_claiming_coverage(self):
        with self.assertRaisesRegex(ValueError, "pinned SHA-256"):
            REFERENCE.validate(self.catalog, self.manifest, b"a different rules revision")
        self.catalog["source"]["version"] = "2099-01-01"
        with self.assertRaisesRegex(ValueError, "pinned manifest"):
            REFERENCE.validate(self.catalog, self.manifest)


if __name__ == "__main__":
    unittest.main()
