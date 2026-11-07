# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import copy
from contextlib import closing
from fractions import Fraction
import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "tools/card-database-builder/build_trk_product.py"
SPEC = importlib.util.spec_from_file_location("trk_builder", PATH)
BUILDER = importlib.util.module_from_spec(SPEC)
with mock.patch.object(sys, "path", [str(PATH.parent), *sys.path]):
    SPEC.loader.exec_module(BUILDER)


def fixture_cards(product):
    unique = {}
    for sheet in product["sheets"]:
        cards = sheet.get("cards")
        if cards is None:
            cards = [product["cardPool"][reference["cardIndex"] - 1] for reference in sheet["cardRefs"]]
        for card in cards:
            identity = {field: card[field] for field in ("name", "setCode", "collectorNumber", "typeLine", "rarity")}
            unique[(identity["setCode"], identity["collectorNumber"])] = identity
    return list(unique.values())


class TrkProductBuilderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads((ROOT / "testdata/limited/trk-estimated-product.json").read_text())
        cls.cards = fixture_cards(cls.fixture)

    def database(self, directory):
        path = Path(directory) / "build.sqlite"
        with closing(sqlite3.connect(path)) as connection, connection:
            connection.executescript("""
                CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT);
                INSERT INTO metadata VALUES ('package','default_cards'),('schema_version','10');
                CREATE TABLE cards (id INTEGER PRIMARY KEY, name TEXT, set_code TEXT,
                    collector_number TEXT, type_line TEXT, rarity TEXT, lang TEXT,
                    digital INTEGER, booster INTEGER);
                CREATE TABLE limited_products (id TEXT PRIMARY KEY, name TEXT, set_code TEXT,
                    product_type TEXT, authentic INTEGER, definition_json TEXT);
                INSERT INTO limited_products VALUES ('mtgjson-fra-play','FRA','FRA','official',1,'{}');
            """)
            connection.executemany(
                "INSERT INTO cards (name,set_code,collector_number,type_line,rarity,lang,digital,booster) "
                "VALUES (?,?,?,?,?,'en',0,0)",
                [(card["name"], card["setCode"], card["collectorNumber"], card["typeLine"], card["rarity"])
                 for card in self.cards])
        return path

    @staticmethod
    def table_rows(path, table):
        with closing(sqlite3.connect(path)) as connection:
            return connection.execute(f"SELECT * FROM {table} ORDER BY 1").fetchall()

    def test_reviewed_printing_fixture_reproduces_the_estimated_product(self):
        product, report = BUILDER.build_product(self.cards)
        self.assertEqual(product, self.fixture)
        self.assertEqual(product["id"], "hexproof-trk-play")
        self.assertEqual(product["productType"], "approximate")
        self.assertFalse(product["authentic"])
        self.assertEqual(report["printingCount"], 460)
        self.assertEqual(report["missingPrintings"], [])
        self.assertEqual(len(report["printingSha256"]), 64)
        self.assertTrue(report["assumptions"])
        self.assertLess(report["productBytes"], 800 * 1024)

    def test_twenty_variants_preserve_pack_sizes_and_published_branch_rates(self):
        product, _ = BUILDER.build_product(self.cards)
        self.assertEqual(len(product["variants"]), 20)
        total = sum(variant["weight"] for variant in product["variants"])
        rates = {name: Fraction() for name in ("stardates", "common-klingon", "uncommon-scene",
                                              "uncommon-lcars", "uncommon-classic", "uncommon-klingon")}
        for variant in product["variants"]:
            slots = {slot["sheet"]: slot["count"] for slot in variant["slots"]}
            self.assertEqual(len(slots), len(variant["slots"]))
            self.assertEqual(sum(slots.values()), 14)
            self.assertEqual(sum(count for name, count in slots.items() if name.startswith("uncommon")), 3)
            self.assertIn(slots["common"] + slots.get("common-klingon", 0), (6, 7))
            self.assertEqual({name: slots[name] for name in ("wildcard", "rare", "foil", "land")},
                             {name: 1 for name in ("wildcard", "rare", "foil", "land")})
            for name in rates:
                if name in slots:
                    rates[name] += Fraction(variant["weight"], total)
        self.assertEqual(rates, {"stardates": Fraction(1, 25), "common-klingon": Fraction(29, 1000),
                                 "uncommon-scene": Fraction(77, 1000), "uncommon-lcars": Fraction(46, 1000),
                                 "uncommon-classic": Fraction(46, 1000), "uncommon-klingon": Fraction(1, 20)})

    def test_curated_pools_exclude_collector_promos_and_keep_common_nondual_land(self):
        extra = [{"name": "Excluded printing", "setCode": "TRK", "collectorNumber": number,
                  "typeLine": "Creature — Test", "rarity": "rare"}
                 for number in ("327", "328", "331", "436", "446", "482", "497", "550", "579", "1701D")]
        product, _ = BUILDER.build_product(self.cards + extra)
        self.assertEqual(product, self.fixture)
        sheets = {sheet["name"]: sheet["cards"] for sheet in product["sheets"]}
        self.assertIn("303", {card["collectorNumber"] for card in sheets["common"]})
        self.assertNotIn("275", {card["collectorNumber"] for card in sheets["common"]})
        self.assertTrue(all("Land" in card["typeLine"] for card in sheets["land"]))
        self.assertTrue(all(card["setCode"] == "SDS" and card["finish"] == "nonfoil" for card in sheets["stardates"]))
        self.assertTrue(all(card["finish"] == "foil" for card in sheets["foil"]))

    def test_single_slot_weights_and_estimate_report_match_published_categories(self):
        product, report = BUILDER.build_product(self.cards)
        sheets = {sheet["name"]: sheet["cards"] for sheet in product["sheets"]}

        def probability(sheet, predicate):
            cards = sheets[sheet]
            return Fraction(sum(card["weight"] for card in cards if predicate(card)),
                            sum(card["weight"] for card in cards))

        base_rare = lambda card: int(card["collectorNumber"]) <= 306 and card["rarity"] == "rare"
        self.assertEqual(probability("rare", base_rare), Fraction(801, 1000))
        self.assertEqual(probability("wildcard", base_rare), Fraction(167, 1000))
        self.assertEqual(probability("foil", base_rare), Fraction(63, 1000))
        self.assertEqual(probability("rare", lambda card: 426 <= int(card["collectorNumber"]) <= 435), Fraction(4, 2500))
        self.assertEqual(probability("land", lambda card: 307 <= int(card["collectorNumber"]) <= 311
                                    and card["finish"] == "foil"), Fraction(17, 1002))
        self.assertEqual(report["estimatedProbabilities"]["wildcard"]["percentagePerUnpublishedCategory"], "23/110")
        self.assertEqual(report["estimatedProbabilities"]["rare"]["percentagePerUnpublishedCategory"], "4/25")
        self.assertEqual(report["estimatedProbabilities"]["foil"]["percentagePerUnpublishedCategory"], "31/110")
        self.assertEqual(report["estimatedProbabilities"]["land"]["publishedPercentageTotal"], "501/5")

    def test_missing_changed_or_conflicting_printings_fail_closed(self):
        for fault in ("missing", "rarity", "nonland", "duplicate conflict", "invalid text"):
            with self.subTest(fault=fault):
                cards = copy.deepcopy(self.cards)
                card = next(card for card in cards if card["setCode"] == "TRK" and card["collectorNumber"] == "275")
                if fault == "missing":
                    cards.remove(card)
                elif fault == "rarity":
                    card["rarity"] = "rare"
                elif fault == "nonland":
                    card["typeLine"] = "Creature — Test"
                elif fault == "invalid text":
                    card["name"] = "Name\u0085control"
                else:
                    cards.append({**card, "name": "Different name"})
                with self.assertRaises(ValueError):
                    BUILDER.build_product(cards)
        self.assertEqual(BUILDER.build_product(self.cards), BUILDER.build_product(self.cards + self.cards))

    def test_install_preserves_source_flags_and_other_sets_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.database(directory)
            before = self.table_rows(path, "cards")
            BUILDER.install(path)
            first = self.table_rows(path, "limited_products")
            self.assertEqual(len(first), 2)
            self.assertEqual(first[1][0], "mtgjson-fra-play")
            self.assertEqual(BUILDER.install(path)["productId"], "hexproof-trk-play")
            self.assertEqual(self.table_rows(path, "limited_products"), first)
            self.assertEqual(self.table_rows(path, "cards"), before)
            metadata = dict(self.table_rows(path, "metadata"))
            self.assertEqual(metadata["limited_product_count"], "2")
            self.assertEqual(json.loads(metadata["trk_collation"])["printingCount"], 460)

    def test_failed_metadata_write_rolls_back_the_product(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.database(directory)
            with closing(sqlite3.connect(path)) as connection, connection:
                connection.execute("CREATE TRIGGER fail_metadata BEFORE INSERT ON metadata "
                                   "WHEN NEW.key='trk_collation' BEGIN SELECT RAISE(ABORT,'test failure'); END")
            before = {table: self.table_rows(path, table) for table in ("cards", "limited_products", "metadata")}
            with self.assertRaises(sqlite3.IntegrityError):
                BUILDER.install(path)
            self.assertEqual({table: self.table_rows(path, table) for table in before}, before)

    def test_upstream_limited_product_replaces_only_our_old_product(self):
        for kind in ("play", "play-arena", "draft", "default"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                path = self.database(directory)
                BUILDER.install(path)
                upstream = {**self.fixture, "id": "mtgjson-trk-" + kind, "productType": "official", "authentic": True}
                with closing(sqlite3.connect(path)) as connection, connection:
                    connection.execute("INSERT INTO limited_products VALUES (?,?,?,?,?,?)",
                                       (upstream["id"], "Upstream TRK", "TRK", "official", 1, json.dumps(upstream)))
                    connection.execute("DELETE FROM cards")
                report = BUILDER.install(path)
                self.assertEqual(report, {"status": "upstream", "productIds": [upstream["id"]]})
                self.assertEqual({row[0] for row in self.table_rows(path, "limited_products")},
                                 {"mtgjson-fra-play", upstream["id"]})
                self.assertNotIn("trk_collation", dict(self.table_rows(path, "metadata")))

    def test_collector_product_does_not_suppress_our_limited_product(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.database(directory)
            with closing(sqlite3.connect(path)) as connection, connection:
                connection.execute("INSERT INTO limited_products VALUES ('mtgjson-trk-collector','Collector',"
                                   "'TRK','official',1,'{}')")
            BUILDER.install(path)
            self.assertEqual(len(self.table_rows(path, "limited_products")), 3)

    def test_malformed_upstream_preserves_the_previous_estimate(self):
        for fault in ("empty sheet", "invalid reference", "wrong pack count", "too many draws", "mixed references",
                      "conflicting type", "trimmed duplicate sheet", "whitespace slot"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                path = self.database(directory)
                BUILDER.install(path)
                upstream = copy.deepcopy(self.fixture)
                upstream.update(id="mtgjson-trk-play", productType="official", authentic=True)
                sheet = upstream["sheets"][0]
                if fault == "empty sheet":
                    sheet["cards"] = []
                elif fault == "invalid reference":
                    sheet.pop("cards")
                    sheet["cardRefs"] = [{"cardIndex": 1, "weight": 1}]
                elif fault == "mixed references":
                    sheet["cardRefs"] = [{"cardIndex": 1, "weight": 1}]
                elif fault == "too many draws":
                    sheet["cards"] = sheet["cards"][:1]
                elif fault == "conflicting type":
                    sheet["cards"][0]["typeLine"] = "Different conflicting type"
                elif fault == "trimmed duplicate sheet":
                    upstream["sheets"][1]["name"] = " common "
                elif fault == "whitespace slot":
                    upstream["variants"][0]["slots"][0]["sheet"] = " common "
                else:
                    upstream["cardsPerPack"] = 15
                with closing(sqlite3.connect(path)) as connection, connection:
                    connection.execute("INSERT INTO limited_products VALUES (?,?,?,?,?,?)",
                                       (upstream["id"], "Invalid", "TRK", "official", 1, json.dumps(upstream)))
                before = {table: self.table_rows(path, table) for table in ("limited_products", "metadata")}
                with self.assertRaisesRegex(ValueError, "not usable"):
                    BUILDER.install(path)
                self.assertEqual({table: self.table_rows(path, table) for table in before}, before)


if __name__ == "__main__":
    unittest.main()
