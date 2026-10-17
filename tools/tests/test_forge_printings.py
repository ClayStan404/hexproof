# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check printing-index provenance and the catalog input boundary without network access."""

import importlib.util
from collections import Counter
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
        unavailable = resources / "printing-unavailable.tsv"
        excluded = [line.split("\t") for line in unavailable.read_text().splitlines() if line and not line.startswith("#")]
        excluded_keys = {tuple(row[:3]) for row in excluded}
        self.assertEqual(GENERATOR.digest(unavailable), metadata["unavailableSha256"])
        self.assertEqual(len(excluded), len(excluded_keys))
        self.assertEqual(len(excluded), metadata["unresolvedPrintings"])
        self.assertFalse(keys & excluded_keys)
        self.assertEqual(dict(Counter(row[3] for row in excluded)), metadata["unresolvedReasons"])
        self.assertEqual(metadata["actionableUnresolvedPrintings"], 0)
        self.assertNotIn("unmatched_native_printing", metadata["unresolvedReasons"])
        for path, expected in (metadata["generatorSources"] | metadata["resolverSources"]).items():
            self.assertEqual(GENERATOR.digest(ROOT / path), expected, "Resolver/generator changed: rerun full-catalog census")
        self.assertEqual(metadata["forgeRevision"], json.loads((GENERATOR.HOST / "upstream.json").read_text())["revision"])
        for printing in [("Blood Crypt", "RVR", "397z"), ("Overgrown Tomb", "RVR", "407z"),
                         ("Fyndhorn Elves", "PTC", "bl244"), ("Windswept Heath", "WC04", "jn328"),
                         ("Ancient Tomb", "LTC", "387z"), ("Sophina, Spearsage Deserter", "SLD", "341"),
                         ("Havengul Laboratory // Havengul Mystery", "SLD", "609"),
                         ("Nearby Planet", "UNF", "198"), ("Aswan Jaguar", "PMIC", "1"),
                         ("Abomination", "4BB", "117"), ("Aether Shockwave", "PSAL", "C26")]:
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
                    ("one", "Forest", "pjpn", "1", "ja", 0, "normal"),
                    ("two", "Digital Card", "tst", "1", "en", 1, "normal"),
                    ("three", "Token", "ttst", "1", "en", 0, "token")])
            GENERATOR.export_catalog(catalog, output)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), [
                ["one", "Forest", "7ED", "347★", "normal", 1],
                ["one", "Forest", "PJPN", "1", "normal", 0]])
            anchors = root / "anchors.json"
            GENERATOR.export_catalog(catalog, output, anchors)
            self.assertEqual(json.loads(anchors.read_text()), [["two", "Digital Card", "TST", "1", "normal", 1]])
            self.assertEqual(len(json.loads(output.read_text())), 2, "Digital anchors must not become paper candidates")
            with closing(sqlite3.connect(catalog)) as connection, connection:
                connection.execute("INSERT INTO cards VALUES (?,?,?,?,?,?,?)",
                                   ("different", "Forest", "7ed", "347★", "en", 0, "normal"))
            with self.assertRaisesRegex(ValueError, "Conflicting Oracle"):
                GENERATOR.export_catalog(catalog, output)

    def test_full_catalog_check_rejects_new_gaps_and_stale_baselines(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output, baseline = root / "output", root / "baseline"
            output.mkdir(); baseline.mkdir()
            for name in ("printing-aliases.tsv", "printing-unavailable.tsv", "printing-aliases.json"):
                (output / name).write_text("reviewed\n")
                (baseline / name).write_text("reviewed\n")
            report = output / "report.json"
            report.write_text(json.dumps({"actionableUnresolvedPrintings": 0}))
            GENERATOR.check_coverage(output, baseline)
            report.write_text(json.dumps({"actionableUnresolvedPrintings": 1}))
            with self.assertRaisesRegex(ValueError, "unmatched catalog"):
                GENERATOR.check_coverage(output, baseline)
            report.write_text(json.dumps({"actionableUnresolvedPrintings": 0}))
            for name in ("printing-aliases.tsv", "printing-unavailable.tsv", "printing-aliases.json"):
                (output / name).write_text("new rejection or remapped printing\n")
                with self.assertRaisesRegex(ValueError, "compatibility changed"):
                    GENERATOR.check_coverage(output, baseline)
                (output / name).write_text("reviewed\n")


if __name__ == "__main__":
    unittest.main()
