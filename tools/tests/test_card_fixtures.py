# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

import hashlib
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest


PATH = Path(__file__).resolve().parents[1] / "ui-automation/make-card-fixtures.py"
SPEC = importlib.util.spec_from_file_location("card_fixtures", PATH)
FIXTURES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURES)


def write_catalog(path):
    """Artificial catalog for generator invariants, never a native fixture."""
    legal = "|" + "|".join(name + ":legal" for name in FIXTURES.FORMATS) + "|"
    with closing(sqlite3.connect(path)) as database, database:
        database.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
        database.executemany("INSERT INTO metadata VALUES (?, ?)",
                             [("schema_version", "10"), ("generated_at", "test-catalog")])
        database.execute("CREATE TABLE cards (" + ",".join(name + " TEXT" for name in FIXTURES.FIELDS)
                         + ", digital INTEGER, lang TEXT)")

        def add(name, number, *, layout="normal", type_line="Creature — Test", colors="",
                status=legal, oracle=None, related=(), set_code="TST", mana_cost="{2}"):
            values = {key: "" for key in FIXTURES.FIELDS}
            values.update(id="id-" + number, oracle_id=oracle or name, name=name, set_code=set_code,
                          collector_number=number, layout=layout, type_line=type_line, colors=colors,
                          card_colors=colors, mana_cost=mana_cost, mana_value=2,
                          legality_statuses=status, related_cards=json.dumps(related))
            database.execute("INSERT INTO cards VALUES (" + ",".join("?" for _ in range(len(values) + 2))
                             + ")", [*(values[key] for key in FIXTURES.FIELDS), 0, "en"])

        for index, name in enumerate(FIXTURES.BASICS):
            add(name, "basic-" + str(index), type_line="Basic Land — " + name, colors="WUBRG"[index])
        add("Kenrith, the Returned King", "king", type_line="Legendary Creature — Human", colors="WUBRG")
        add("Alpha Instant", "instant", type_line="Instant")
        add("Front // Reverse", "transform", layout="transform")
        add("Emeritus of Truce // Swords to Plowshares", "13", layout="prepare", set_code="SOS")
        add("Spell // Land", "modal", layout="modal_dfc", type_line="Instant // Land")
        add("Split // Spell", "split", layout="split", type_line="Instant // Instant")
        add("Meld Part", "part", layout="meld", related=[
            {"component": "meld_result", "id": "id-result", "name": "Meld Result"}])
        add("Meld Result", "result", layout="meld", related=[
            {"component": "meld_result", "id": "id-result", "name": "Meld Result"}])
        add("Banned Everywhere", "banned", status="|modern:banned|")
        add("Restricted Card", "restricted", type_line="Artifact", status="|vintage:restricted|")
        add("Not A Deck Token", "token", layout="token", type_line="Token Creature — Test")
        add("Not A Deck Emblem", "emblem", layout="emblem", type_line="Emblem — Test")
        add("Not A Deck Artwork", "art", layout="art_series")
        add("Duplicate Instant Printing", "duplicate", oracle="Alpha Instant")
        for index in range(115):
            add(f"Test Card {index:03}", str(index))


class CardFixtureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.catalog = self.root / "cards.sqlite"
        write_catalog(self.catalog)

    def test_all_formats_have_valid_physical_counts_and_distinct_oracle_cards(self):
        manifest = FIXTURES.generate(self.catalog, self.root / "all", cube_size=90)
        self.assertEqual(set(manifest["decks"]), set(FIXTURES.FORMATS))
        for name, deck in manifest["decks"].items():
            with self.subTest(format=name):
                commander = name in ("duel", "commander")
                self.assertEqual(deck["mainCount"], 90 if name == "cube" else 100 if commander else 60)
                self.assertEqual(deck["sideCount"], 0 if commander or name == "cube" else 15)
                self.assertEqual(len(deck["commanders"]), int(commander))
                rows = deck["mainboard"] + deck["sideboard"]
                self.assertEqual(len({card["oracleId"] for card in rows}), len(rows))
                for card in rows:
                    self.assertNotIn(card["name"], ("Meld Result", "Banned Everywhere"))
                    self.assertNotIn(card["layout"], ("token", "emblem", "art_series"))
                    self.assertTrue(card["setCode"] and card["collectorNumber"])
                    if name not in ("custom", "cube"):
                        self.assertIn(card["legalStatus"], ("legal", "restricted"))
                    if "basic_land" not in card["shapes"]:
                        self.assertEqual(card["count"], 1)
                if commander:
                    self.assertNotIn(deck["shapeCards"]["creature"]["name"], deck["commanders"])
                    text = (self.root / "all" / deck["textFile"]).read_text()
                    self.assertEqual(text.count("Kenrith, the Returned King"), 1)
                    self.assertIn("Commander\n", text)
        self.assertFalse(manifest["imagesPrecached"])
        self.assertEqual(manifest["evidence"], "fixture-setup")
        self.assertFalse((self.root / "all/images").exists())
        self.assertFalse((self.root / "all/decks.json").exists())

    def test_faces_and_negative_expectations_are_independent_of_live_ui(self):
        manifest = FIXTURES.generate(self.catalog, self.root / "faces", formats=("modern", "commander"))
        shapes = manifest["decks"]["modern"]["shapeCards"]
        self.assertEqual(shapes["transform"]["faces"], ["Front", "Reverse"])
        self.assertEqual(shapes["modal_dfc"]["faces"], ["Spell", "Land"])
        self.assertEqual(shapes["prepare"]["faces"], ["Emeritus of Truce // Swords to Plowshares"])
        self.assertEqual(shapes["split"]["imageFaceCount"], 1)
        negatives = manifest["negativeDecks"]
        self.assertEqual(negatives["modern-short-main"]["mainCount"], 59)
        self.assertFalse(negatives["modern-short-main"]["validationExpectation"]["valid"])
        self.assertEqual(negatives["modern-oversized-sideboard"]["sideCount"], 16)
        self.assertEqual(negatives["commander-short-main"]["mainCount"], 99)
        self.assertTrue(negatives["commander-short-main"]["validationExpectation"]["warning"])
        for deck in negatives.values():
            self.assertTrue(deck["textFile"].startswith("negative/"))

    def test_reproducible_read_only_snapshot_and_import_text_digests(self):
        before = self.catalog.read_bytes()
        first = FIXTURES.generate(self.catalog, self.root / "one", formats=("modern",))
        second = FIXTURES.generate(self.catalog, self.root / "two", formats=("modern",))
        self.assertEqual(first, second)
        self.assertEqual(self.catalog.read_bytes(), before)
        self.assertEqual(first["source"]["access"], "sqlite-mode-ro")
        deck = first["decks"]["modern"]
        text = (self.root / "one" / deck["textFile"]).read_bytes()
        self.assertEqual(hashlib.sha256(text).hexdigest(), deck["textSha256"])
        self.assertIn(b"(SOS) 13", text)
        with closing(sqlite3.connect(self.catalog)) as database, database:
            database.execute("UPDATE cards SET mana_cost='{7}' WHERE name='Alpha Instant'")
        third = FIXTURES.generate(self.catalog, self.root / "three", formats=("modern",))
        self.assertNotEqual(first["source"]["sha256"], third["source"]["sha256"])

    def test_rejects_overwrites_incomplete_catalogs_and_unsupported_formats(self):
        output = self.root / "existing"
        output.mkdir()
        (output / "keep").write_text("unchanged")
        with self.assertRaises(FileExistsError):
            FIXTURES.generate(self.catalog, output, formats=("modern",))
        self.assertEqual((output / "keep").read_text(), "unchanged")
        with self.assertRaises(ValueError):
            FIXTURES.generate(self.catalog, self.root / "forge", formats=("forge",))
        with closing(sqlite3.connect(self.catalog)) as database, database:
            database.execute("DELETE FROM cards WHERE name LIKE 'Test Card %'")
        with self.assertRaisesRegex(ValueError, "eligible distinct cards"):
            FIXTURES.generate(self.catalog, self.root / "small", formats=("modern",))
        self.assertFalse((self.root / "small").exists())


if __name__ == "__main__":
    unittest.main()
