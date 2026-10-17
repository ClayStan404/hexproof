# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import importlib.util
import hashlib
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BUILDER = REPOSITORY_ROOT / "tools/card-database-builder/build_limited_products.py"


class LimitedProductBuilderTests(unittest.TestCase):
    def test_fra_upstream_recipe_preserves_every_slot_and_weight(self):
        spec = importlib.util.spec_from_file_location("limited_builder", BUILDER)
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        fixture = REPOSITORY_ROOT / "testdata/limited/fra-mtgjson.json"
        data = json.loads(fixture.read_text())["data"]
        identities = {c["uuid"]: builder.card_identity(c, "FRA") for c in data["cards"]}
        source = data["booster"]["play"]
        product = builder.build_product(data, "play", source, identities)
        expected = json.loads((fixture.parent / "fra-upstream-product.json").read_text())
        self.assertEqual(product, expected)
        self.assertTrue(product["authentic"])
        self.assertEqual(product["cardsPerPack"], 14)
        self.assertEqual(len(product["variants"]), 232)
        self.assertEqual(len(product["sheets"]), 109)
        self.assertLessEqual(len(json.dumps(product, ensure_ascii=False, separators=(",", ":")).encode()),
                             builder.MAX_ENCODED_PRODUCT_BYTES)
        self.assertLess(len(json.dumps(product, ensure_ascii=False, separators=(",", ":")).encode()),
                        builder.MAX_ENCODED_PRODUCT_BYTES // 2)
        for variant, original in zip(product["variants"], source["boosters"]):
            self.assertEqual(variant["weight"], original["weight"])
            self.assertEqual({s["sheet"]: s["count"] for s in variant["slots"]}, original["contents"])
        for sheet in product["sheets"]:
            original = source["sheets"][sheet["name"]]
            self.assertFalse(sheet["withReplacement"])
            expected_cards = []
            for uuid, weight in original["cards"].items():
                expected_cards.append({**identities[uuid], "weight": weight,
                                       "finish": "foil" if original["foil"] else "nonfoil"})
            restored = [{**product["cardPool"][ref["cardIndex"] - 1], "weight": ref["weight"]}
                        for ref in sheet["cardRefs"]]
            self.assertEqual(restored, expected_cards)
            if original.get("fixed"):
                self.assertEqual(len(restored), 2)
                self.assertEqual({c["weight"] for c in restored}, {1})

    def test_fra_rejects_missing_upstream_instead_of_using_estimate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "sets.zip"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("FRA.json", json.dumps({"data": {"code": "FRA"}}))
            result = subprocess.run(["python3", str(BUILDER), "--source", str(source),
                                     "--output", str(root / "out.json")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("requires upstream Play booster data", result.stderr)
            self.assertFalse((root / "out.json").exists())

    def test_fra_does_not_truncate_invalid_conditional_variants(self):
        spec = importlib.util.spec_from_file_location("limited_builder", BUILDER)
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        fixture = REPOSITORY_ROOT / "testdata/limited/fra-mtgjson.json"
        for fault in ("missing printing", "unknown sheet", "wrong pack size", "zero weight"):
            with self.subTest(fault=fault):
                data = json.loads(fixture.read_text())["data"]
                identities = {c["uuid"]: builder.card_identity(c, "FRA") for c in data["cards"]}
                source = data["booster"]["play"]
                if fault == "missing printing":
                    identities.pop(next(iter(source["sheets"]["thirdNotAjani"]["cards"])))
                elif fault == "unknown sheet":
                    source["boosters"][0]["contents"]["missing"] = 1
                elif fault == "wrong pack size":
                    source["boosters"][0]["contents"]["common"] = 5
                else:
                    source["boosters"][0]["weight"] = 0
                self.assertIsNone(builder.build_product(data, "play", source, identities))

    def test_fra_rejects_malformed_numbers_and_pairs(self):
        spec = importlib.util.spec_from_file_location("limited_builder", BUILDER)
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        for fault in ("float weight", "bool weight", "string count", "float count", "all 13 cards",
                      "half pair", "nonfixed pair", "third repeats pair"):
            with self.subTest(fault=fault):
                data = json.loads((REPOSITORY_ROOT / "testdata/limited/fra-mtgjson.json").read_text())["data"]
                identities = {c["uuid"]: builder.card_identity(c, "FRA") for c in data["cards"]}
                source = data["booster"]["play"]
                if fault == "float weight":
                    source["boosters"][0]["weight"] = 1512.9
                elif fault == "bool weight":
                    source["sheets"]["common"]["cards"][next(iter(source["sheets"]["common"]["cards"]))] = True
                elif fault in ("string count", "float count"):
                    source["boosters"][0]["contents"]["common"] = "6" if fault == "string count" else 6.1
                elif fault == "all 13 cards":
                    for variant in source["boosters"]:
                        variant["contents"]["common"] -= 1
                elif fault == "half pair":
                    source["sheets"]["pairAjani"]["cards"].pop(next(iter(source["sheets"]["pairAjani"]["cards"])))
                elif fault == "nonfixed pair":
                    source["sheets"]["pairAjani"]["fixed"] = False
                else:
                    source["sheets"]["thirdNotAjani"]["cards"][next(iter(source["sheets"]["pairAjaniBorderless"]["cards"]))] = 1
                self.assertIsNone(builder.build_product(data, "play", source, identities))

    def test_archive_validation_and_provenance_are_atomic(self):
        fixture = json.loads((REPOSITORY_ROOT / "testdata/limited/fra-mtgjson.json").read_text())
        for fault in ("valid", "broken JSON", "missing FRA", "missing revision", "version mismatch", "mixed revisions"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive_path, output = root / "sets.zip", root / "products.json"
                output.write_text("previous output")
                with zipfile.ZipFile(archive_path, "w") as archive:
                    if fault != "missing FRA":
                        source = {k: v for k, v in fixture.items() if k != "meta"} if fault == "missing revision" else fixture
                        archive.writestr("FRA.json", "broken" if fault == "broken JSON" else json.dumps(source))
                    if fault == "mixed revisions":
                        archive.writestr("OTHER.json", json.dumps({"meta": {"version": "wrong"}, "data": {"code": "OTHER"}}))
                args = ["python3", str(BUILDER), "--source", str(archive_path), "--output", str(output),
                        "--require-product", "FRA:play"]
                if fault == "version mismatch":
                    args += ["--mtgjson-version", "wrong-version"]
                result = subprocess.run(args, capture_output=True, text=True)
                if fault != "valid":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(output.read_text(), "previous output")
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    generated = json.loads(output.read_text())
                    self.assertEqual(generated["sourceVersion"], fixture["meta"]["version"])
                    self.assertEqual(generated["sourceDate"], fixture["meta"]["date"])
                    self.assertEqual(generated["sourceSha256"], hashlib.sha256(archive_path.read_bytes()).hexdigest())

    def test_unique_large_product_keeps_smaller_inline_encoding(self):
        spec = importlib.util.spec_from_file_location("limited_builder", BUILDER)
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        identities = {str(i): {"name": f"Card {i} " + "x" * 100, "setCode": "TST",
                               "collectorNumber": str(i), "typeLine": "Creature — Test"}
                      for i in range(2500)}
        source = {"boosters": [{"weight": 1, "contents": {"main": 1}}],
                  "sheets": {"main": {"cards": {key: 1 for key in identities}}}}
        product = builder.build_product({"code": "TST", "name": "Test"}, "play", source, identities)
        self.assertIsNotNone(product)
        self.assertNotIn("cardPool", product)
        encoded = json.dumps(product, ensure_ascii=False, separators=(",", ":")).encode()
        self.assertGreater(len(encoded), builder.MAX_ENCODED_PRODUCT_BYTES // 2)
        self.assertEqual(len(product["sheets"][0]["cards"]), 2500)

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
