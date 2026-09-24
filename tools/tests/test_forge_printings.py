# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check printing-index provenance and the catalog input boundary without network access."""

import importlib.util
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("printing_generator", ROOT / "tools/forge-printings/generate.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class ForgePrintingTests(unittest.TestCase):
    def test_index_matches_provenance_and_reported_printings(self):
        resources = GENERATOR.HOST / "src/main/resources/org/hexproof/forge"
        index = resources / "printing-aliases.tsv"
        metadata = json.loads((resources / "printing-aliases.json").read_text())
        rows = [line.split("\t") for line in index.read_text().splitlines() if line and not line.startswith("#")]
        keys = {tuple(row[:3]) for row in rows}
        self.assertEqual(len(keys), len(rows))
        self.assertEqual(len(rows), metadata["aliasedPrintings"])
        self.assertEqual(GENERATOR.digest(index), metadata["indexSha256"])
        self.assertEqual(metadata["forgeRevision"], json.loads((GENERATOR.HOST / "upstream.json").read_text())["revision"])
        for printing in [("Blood Crypt", "RVR", "397z"), ("Overgrown Tomb", "RVR", "407z"),
                         ("Fyndhorn Elves", "PTC", "bl244"), ("Windswept Heath", "WC04", "jn328")]:
            self.assertIn(printing, keys)
        for printing in [("Forest", "RVR", "397z"), ("Blood Crypt", "RVR", "999999z"),
                         ("Windswept Heath", "WC04", "jn99999")]:
            self.assertNotIn(printing, keys)

    def test_catalog_filters_and_identity_conflicts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, output = root / "cards.sqlite", root / "catalog.json"
            with closing(sqlite3.connect(catalog)) as connection, connection:
                connection.executescript("""CREATE TABLE cards(oracle_id TEXT, name TEXT, set_code TEXT,
                    collector_number TEXT, lang TEXT, digital INTEGER, layout TEXT);
                    CREATE TABLE metadata(key TEXT, value TEXT);""")
                connection.executemany("INSERT INTO cards VALUES (?,?,?,?,?,?,?)", [
                    ("one", "Forest", "7ed", "347★", "en", 0, "normal"),
                    ("one", "Forest", "7ed", "347★", "en", 0, "normal"),
                    ("one", "Forest", "7ed", "347★", "de", 0, "normal"),
                    ("two", "Digital Card", "tst", "1", "en", 1, "normal"),
                    ("three", "Token", "ttst", "1", "en", 0, "token")])
            GENERATOR.export_catalog(catalog, output)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), [["one", "Forest", "7ED", "347★"]])
            with closing(sqlite3.connect(catalog)) as connection, connection:
                connection.execute("INSERT INTO cards VALUES (?,?,?,?,?,?,?)",
                                   ("different", "Forest", "7ed", "347★", "en", 0, "normal"))
            with self.assertRaisesRegex(ValueError, "Conflicting Oracle"):
                GENERATOR.export_catalog(catalog, output)


if __name__ == "__main__":
    unittest.main()
