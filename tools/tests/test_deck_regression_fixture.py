#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check that native deck acceptance never depends on an installed profile."""

import importlib.util
import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "ui-automation/make-deck-regression-fixture.py"
SPEC = importlib.util.spec_from_file_location("deck_regression_fixture", SCRIPT)
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)


class DeckRegressionFixtureTests(unittest.TestCase):
    def test_portable_art_printings_and_real_face_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            FIXTURE.generate(output)
            manifest = json.loads((output / "manifest.json").read_text())
            deck = json.loads((output / "decks.json").read_text())["decks"][0]
            positive = json.loads((output / "card-cache.json").read_text())["positive"]
            self.assertEqual(manifest["schema"], FIXTURE.SCHEMA)
            self.assertTrue(manifest["synthetic"])
            self.assertEqual((len(deck["mainboard"]), len(deck["sideboard"])), (80, 20))
            self.assertEqual(len(list((output / "images").glob("*.png"))), 102)
            for row in deck["mainboard"] + deck["sideboard"]:
                self.assertEqual(row["count"], 1)
                self.assertTrue(row["imagePath"].startswith("@PROFILE@/images/"))
                self.assertTrue((output / "images" / Path(row["imagePath"]).name).is_file())
            with closing(sqlite3.connect(output / "cards.sqlite")) as database:
                self.assertEqual(database.execute(
                    "SELECT value FROM metadata WHERE key='schema_version'").fetchone()[0], "10")
                for field, layout in (("sourceCold", "modal_dfc"), ("heldCold", "transform")):
                    identity = manifest[field]
                    catalog = database.execute("SELECT name,layout,type_line FROM cards "
                        "WHERE set_code=? AND collector_number=?",
                        (identity["setCode"].lower(), identity["collectorNumber"])).fetchone()
                    self.assertEqual(catalog[0:2], (identity["name"], layout))
                    faces = identity["name"].split(" // ")
                    records = [positive[f"en|{face.casefold()}|{identity['setCode']}|{identity['collectorNumber']}"]
                               for face in faces]
                    self.assertNotEqual(records[0]["imagePath"], records[1]["imagePath"])
                    for record in records:
                        self.assertTrue(record["faceMetadataChecked"])
                        self.assertEqual(len(record["independentFaces"]), 2)
                        self.assertTrue(record["localizedRulesChecked"])
                    row = next(row for row in deck["mainboard"] if row["name"] == identity["name"])
                    self.assertNotEqual(row["typeLine"], records[0]["typeLine"])
                    self.assertEqual(row["typeLine"], catalog[2])
                    self.assertEqual((output / "images" / Path(records[0]["imagePath"]).name)
                                     .read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            siblings = [row for row in deck["mainboard"] if row["name"] == manifest["singleFace"]["name"]]
            self.assertEqual(len(siblings), 2)
            self.assertNotEqual(siblings[0]["setCode"], siblings[1]["setCode"])

    def test_refuses_inadequate_or_nonempty_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            with self.assertRaises(ValueError):
                FIXTURE.generate(output, 59, 20)
            (output / "keep.txt").write_text("existing data")
            with self.assertRaises(ValueError):
                FIXTURE.generate(output)
            self.assertEqual((output / "keep.txt").read_text(), "existing data")


if __name__ == "__main__":
    unittest.main()
