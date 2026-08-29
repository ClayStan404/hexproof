# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUILDER = REPOSITORY_ROOT / "tools/card-database-builder/build_limited_products.py"


class LimitedProductBuilderTests(unittest.TestCase):
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
