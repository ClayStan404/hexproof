# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Exercise the real catalog CLI, compact import and durable source provenance."""

import hashlib
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def main():
    binary = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parents[3]
    fixture = json.loads((root / "testdata/limited/fra-mtgjson.json").read_text())
    with tempfile.TemporaryDirectory(prefix="hexproof-fra-catalog-") as temporary:
        directory = Path(temporary)
        archive, products = directory / "sets.zip", directory / "products.json"
        with zipfile.ZipFile(archive, "w") as source:
            source.writestr("FRA.json", json.dumps(fixture))
        subprocess.run([sys.executable, str(root / "tools/card-database-builder/build_limited_products.py"),
                        "--source", str(archive), "--output", str(products), "--require-product", "FRA:play"],
                       check=True, capture_output=True)
        descriptor = json.loads(products.read_text())
        cards = [{"id": c["uuid"], "oracle_id": c["uuid"], "name": c["name"],
                  "set": c["setCode"].lower(), "collector_number": c["number"],
                  "type_line": c["type"], "rarity": c["rarity"], "lang": "en",
                  "layout": "normal", "booster": True, "digital": False}
                 for c in fixture["data"]["cards"]]
        bulk = directory / "cards.json"
        bulk.write_text(json.dumps(cards))
        aliases = directory / "aliases.tar.gz"
        raw = (json.dumps({"oracle_id": cards[0]["id"], "name": cards[0]["name"],
                           "translated_name": "Test alias", "translated_type": cards[0]["type_line"]}) + "\n").encode()
        with tarfile.open(aliases, "w:gz") as source:
            entry = tarfile.TarInfo("zhs_oracle.json")
            entry.size = len(raw)
            source.addfile(entry, io.BytesIO(raw))
        catalog = directory / "cards.sqlite"
        command = [str(binary), "--source", str(bulk), "--chinese-index", str(aliases),
                   "--limited-products", str(products), "--output", str(catalog)]
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        with sqlite3.connect(catalog) as database:
            stored = json.loads(database.execute("SELECT value FROM metadata WHERE key='limited_product_source'").fetchone()[0])
            assert stored == {"source": descriptor["source"], "version": descriptor["sourceVersion"],
                              "date": descriptor["sourceDate"], "sha256": descriptor["sourceSha256"]}
            assert stored["sha256"] == hashlib.sha256(archive.read_bytes()).hexdigest()
            definition = json.loads(database.execute("SELECT definition_json FROM limited_products WHERE id='mtgjson-fra-play'").fetchone()[0])
            assert definition == descriptor["products"][0]
            assert definition["cardPool"] and len(definition["variants"]) == 232
        before = hashlib.sha256(catalog.read_bytes()).hexdigest()
        descriptor["products"][0]["sheets"][0]["cardRefs"][0]["cardIndex"] = 0
        products.write_text(json.dumps(descriptor))
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode != 0, "invalid reference imported"
        assert hashlib.sha256(catalog.read_bytes()).hexdigest() == before, "failed import replaced valid catalog"
    print("FRA compact catalog/provenance integration passed")


if __name__ == "__main__":
    main()
