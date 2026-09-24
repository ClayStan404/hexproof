#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Generate a reproducible, offline printing alias index using a catalog and pinned native runtime."""

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "third_party/forge-runtime/native-host"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def export_catalog(catalog, destination):
    with closing(sqlite3.connect(catalog.resolve().as_uri() + "?mode=ro", uri=True)) as connection:
        rows = connection.execute("""SELECT DISTINCT oracle_id, name, upper(set_code), collector_number
            FROM cards WHERE lang = 'en' AND digital = 0 AND oracle_id != ''
            AND set_code != '' AND collector_number != ''
            AND layout NOT IN ('token', 'double_faced_token', 'emblem', 'art_series')
            ORDER BY oracle_id, name, upper(set_code), collector_number""").fetchall()
        metadata = dict(connection.execute("SELECT key, value FROM metadata"))
    if not rows or any(any(not value or '\t' in value or '\n' in value for value in row) for row in rows):
        raise ValueError("Invalid or empty printing catalog")
    identities = {}
    for oracle, name, set_code, number in rows:
        key = (name.casefold(), set_code, number)
        if key in identities and identities[key] != oracle:
            raise ValueError("Conflicting Oracle identities for one printing")
        identities[key] = oracle
    destination.write_text(json.dumps(rows, ensure_ascii=False) + "\n", encoding="utf-8")
    return metadata


def write_provenance(catalog, metadata, index, report, destination):
    summary = json.loads(report.read_text(encoding="utf-8"))
    summary.pop("unresolved")
    destination.write_text(json.dumps({"schema": 1, "catalogSha256": digest(catalog),
        "catalogGeneratedAt": metadata.get("generated_at", ""),
        "forgeRevision": json.loads((HOST / "upstream.json").read_text(encoding="utf-8"))["revision"],
        "indexSha256": digest(index), **summary}, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "tools/local-forge-runtime.py"),
                    "--root", str(args.runtime.resolve())], check=True, stdout=subprocess.DEVNULL)
    args.output.mkdir(parents=True, exist_ok=False)
    candidates = args.output / "catalog.json"
    metadata = export_catalog(args.catalog, candidates)
    classes = args.output / "classes"
    classes.mkdir()
    classpath = os.pathsep.join([str(args.runtime.resolve() / "forge-harness.jar"),
                                str(args.runtime.resolve() / "lib/*")])
    subprocess.run(["javac", "--release", "21", "-encoding", "UTF-8", "-cp", classpath,
                    "-d", str(classes), str(Path(__file__).with_name("NativePrintingIndex.java"))], check=True)
    index, report = args.output / "printing-aliases.tsv", args.output / "report.json"
    with (args.output / "native.log").open("w") as log:
        subprocess.run(["java", "-Xmx2g", "-Djava.awt.headless=true", "-cp", str(classes) + os.pathsep + classpath,
                        "org.hexproof.forge.NativePrintingIndex", str(args.runtime.resolve() / "forge-gui"),
                        str(candidates), str(index), str(report)], stdout=log, stderr=subprocess.STDOUT, check=True)
    write_provenance(args.catalog, metadata, index, report, args.output / "printing-aliases.json")


if __name__ == "__main__":
    main()
