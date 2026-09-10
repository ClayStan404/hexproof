# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUILDER = REPOSITORY_ROOT / "tools/card-database-builder/build_limited_products.py"


class LimitedProductBuilderTests(unittest.TestCase):
    def test_sheet_weight_total_boundary(self):
        spec = importlib.util.spec_from_file_location("limited_builder", BUILDER)
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        for count in (1024, 1025, 2049):
            with self.subTest(count=count):
                identities = {
                    str(index): {"name": f"Card {index}", "setCode": "TST",
                                 "collectorNumber": str(index)}
                    for index in range(count)
                }
                source = {
                    "boosters": [{"weight": 1, "contents": {"main": 1}}],
                    "sheets": {"main": {"cards": {
                        key: builder.MAX_PRODUCT_WEIGHT for key in identities
                    }}},
                }
                product = builder.build_product(
                    {"code": "TST", "name": "Test"}, "play", source, identities)
                self.assertEqual(product is not None, count == 1024)

    def test_builds_cross_set_weighted_product(self):
        primary = {
            "data": {
                "code": "TST",
                "name": "Test Set",
                "cards": [
                    self.card("card-a", "Alpha", "TST", "1"),
                    self.card("card-b", "Beta", "TST", "2"),
                ],
                "booster": {
                    "play": {
                        "boosters": [
                            {"contents": {"main": 2, "guest": 1}, "weight": 7}
                        ],
                        "sheets": {
                            "main": {
                                "foil": False,
                                "cards": {"card-a": 2, "card-b": 1},
                            },
                            "guest": {"foil": True, "cards": {"card-c": 1}},
                        },
                    }
                },
            }
        }
        source = {
            "data": {
                "code": "EXT",
                "name": "Guest Set",
                "cards": [self.card("card-c", "Gamma", "EXT", "9")],
            }
        }

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive_path = root / "sets.zip"
            output_path = root / "limited-products.json"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("TST.json", json.dumps(primary))
                archive.writestr("EXT.json", json.dumps(source))
            completed = subprocess.run(
                [
                    "python3",
                    str(BUILDER),
                    "--source",
                    str(archive_path),
                    "--output",
                    str(output_path),
                    "--mtgjson-version",
                    "test-version",
                ],
                cwd=REPOSITORY_ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            generated = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(generated["sourceVersion"], "test-version")
        self.assertEqual(len(generated["products"]), 1)
        product = generated["products"][0]
        self.assertEqual(product["id"], "mtgjson-tst-play")
        self.assertEqual(product["cardsPerPack"], 3)
        self.assertEqual(product["variants"][0]["weight"], 7)
        guest = next(sheet for sheet in product["sheets"] if sheet["name"] == "guest")
        self.assertEqual(guest["cards"][0]["setCode"], "EXT")
        self.assertEqual(guest["cards"][0]["finish"], "foil")

    def test_keeps_play_product_with_json_safe_sheet_weights(self):
        source = {
            "data": {
                "code": "FIN",
                "name": "Final Fantasy",
                "cards": [
                    self.card("common-a", "Common A", "FIN", "1"),
                    self.card("common-b", "Common B", "FIN", "2"),
                    self.card("wildcard-a", "Wildcard A", "FIN", "3"),
                    self.card("wildcard-b", "Wildcard B", "FIN", "4"),
                ],
                "booster": {
                    "play": {
                        "boosters": [{"contents": {"common": 1, "wildcard": 1}, "weight": 1}],
                        "sheets": {
                            "common": {"foil": False, "cards": {"common-a": 1, "common-b": 1}},
                            "wildcard": {
                                "foil": False,
                                "cards": {
                                    "wildcard-a": 1,
                                    "wildcard-b": 1_534_072_540_000,
                                },
                            },
                        },
                    }
                },
            }
        }

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive_path = root / "sets.zip"
            output_path = root / "limited-products.json"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("FIN.json", json.dumps(source))
            completed = subprocess.run(
                [
                    "python3",
                    str(BUILDER),
                    "--source",
                    str(archive_path),
                    "--output",
                    str(output_path),
                    "--mtgjson-version",
                    "test-version",
                ],
                cwd=REPOSITORY_ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            generated = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(len(generated["products"]), 1)
        product = generated["products"][0]
        self.assertEqual(product["id"], "mtgjson-fin-play")
        wildcard = next(sheet for sheet in product["sheets"] if sheet["name"] == "wildcard")
        weights = {card["name"]: card["weight"] for card in wildcard["cards"]}
        self.assertEqual(weights["Wildcard B"], 1_534_072_540_000)

    @staticmethod
    def card(uuid, name, set_code, number):
        return {
            "uuid": uuid,
            "name": name,
            "setCode": set_code,
            "number": number,
            "type": "Creature — Test",
            "rarity": "common",
        }


if __name__ == "__main__":
    unittest.main()
