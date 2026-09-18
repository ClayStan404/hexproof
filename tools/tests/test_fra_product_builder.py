# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("fra_builder", ROOT / "tools/card-database-builder/build_fra_product.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class FRAProductTests(unittest.TestCase):
    def setUp(self):
        self.cards = json.loads((ROOT / "testdata/limited/fra-preview-printings.json").read_text())["cards"]

    def test_preview_recipe_keeps_complete_pairs_and_reports_missing_cards(self):
        product, report = BUILDER.build_product(self.cards)
        self.assertFalse(product["authentic"])
        self.assertEqual(product["productType"], "approximate")
        self.assertIn("partial preview", product["name"])
        self.assertEqual(report["completeBasePairs"], 42)
        self.assertEqual(report["completeBorderlessPairs"], 15)
        self.assertEqual(report["missingPrintings"], ["FRA/24", "FRA/73", "FRA/206", "FRA/253", "FRA/289", "FRA/290"])
        sheets = {s["name"]: s for s in product["sheets"]}
        for variant in product["variants"]:
            size = sum(slot["count"] * (2 if "pairCollectorNumber" in sheets[slot["sheet"]]["cards"][0] else 1) for slot in variant["slots"])
            self.assertEqual(size, 14)
        self.assertEqual([v["weight"] for v in product["variants"]], [54, 1])
        self.assertTrue(sheets["echo-single"]["excludePrevious"])
        for c in sheets["land"]["cards"]:
            self.assertIn("Land", c["typeLine"])
            self.assertNotEqual(c["name"], "Room of Refuge")

    def test_missing_partner_excludes_both_halves(self):
        cards = [c for c in self.cards if not (c["setCode"] == "FRA" and c["collectorNumber"] == "195")]
        product, report = BUILDER.build_product(cards)
        self.assertEqual(report["completeBasePairs"], 41)
        pairs = next(s["cards"] for s in product["sheets"] if s["name"] == "echo-pair")
        self.assertFalse(any(c["name"] in ("Ajani Resolute", "Ajani Unrelenting") and int(c["collectorNumber"]) <= 280 for c in pairs))

    def test_missing_category_fails_instead_of_silently_renormalizing(self):
        with self.assertRaisesRegex(ValueError, "required category"):
            BUILDER.build_product([c for c in self.cards if c["setCode"] != "SPG"])

    def test_duplicate_source_rows_do_not_change_weights(self):
        self.assertEqual(BUILDER.build_product(self.cards), BUILDER.build_product(self.cards + self.cards))
