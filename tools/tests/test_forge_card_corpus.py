# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1] / "forge-card-corpus"


def load(name):
    spec = importlib.util.spec_from_file_location("corpus_" + name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


COLLECT = load("collect")
REPORT = load("report")


class CorpusTests(unittest.TestCase):
    def test_public_deck_parser_retains_sideboard_and_split_names(self):
        text = "60 Forest\n\n1 Fire // Ice\n2 Artist's Talent"
        parsed = COLLECT.parse_deck(text)
        self.assertEqual(parsed["sideboard"], [{"name": "Fire // Ice", "count": 1},
                                               {"name": "Artist's Talent", "count": 2}])
        self.assertEqual(COLLECT.parse_deck("60 Forest\nSB: 1 Island")["sideboard"][0]["name"], "Island")
        for bad in ("59 Forest", "60 Forest\n\n16 Island", "60 Forest\n0 Island", "60 Forest\ninvalid"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                COLLECT.parse_deck(bad)

    def test_frozen_sample_has_ten_distinct_lists_per_format(self):
        manifest = json.loads((ROOT / "decks-2026-09-22.json").read_text())
        self.assertEqual(len(manifest["decks"]), 40)
        self.assertEqual(len({deck["source"] for deck in manifest["decks"]}), 40)
        for format_name in COLLECT.FORMATS:
            self.assertEqual(sum(deck["format"] == format_name for deck in manifest["decks"]), 10)
        for deck in manifest["decks"]:
            self.assertGreaterEqual(sum(card["count"] for card in deck["mainboard"]), 60)
            self.assertLessEqual(sum(card["count"] for card in deck["sideboard"]), 15)
            self.assertRegex(deck["sourceSha256"], r"^[a-f0-9]{64}$")

    def test_report_refuses_missing_failed_or_unreplayed_evidence(self):
        manifest = {"decks": [{"id": "one", "format": "modern", "name": "Fixture", "source": "test",
                                "mainboard": [{"name": "Forest", "count": 60}], "sideboard": []}]}
        native = {("Forest", "play-and-resolve"): {"status": "resolved", "type": "Land", "frames": [],
                   "after": [{}, {}, {}], "finalZone": "Battlefield", "resolvedStackObjects": 0, "abilityInventory": []}}
        projected = {("Forest", "play-and-resolve"): {"nativeStatus": "resolved", "after": [{}, {}, {}], "frames": []}}
        log = "PASS : qml::ForgeCardCorpus::test_native_frames(Forest/play-and-resolve)\nTotals: 3 passed, 0 failed, 0 skipped\n"
        self.assertEqual(REPORT.summarize(manifest, native, projected, log)["totals"]["cards"], 1)
        for corrupted in ("", log + "QWARN", log + "FAIL!"):
            with self.assertRaises(ValueError):
                REPORT.summarize(manifest, native, projected, corrupted)
        for field, value in (("status", "needs-triage"), ("after", [{}]),
                             ("abilityInventory", [{"index": 1, "spell": False, "land": False}])):
            changed = copy.deepcopy(native)
            changed[("Forest", "play-and-resolve")][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                REPORT.summarize(manifest, changed, projected, log)
        with self.assertRaises(ValueError):
            REPORT.summarize(manifest, native, {}, log)


if __name__ == "__main__":
    unittest.main()
